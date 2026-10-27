// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.jsengine.bridge

import io.mockk.every
import io.mockk.mockk
import io.ownbit.core.jsengine.JsArgs
import io.ownbit.core.jsengine.JsBundle
import io.ownbit.core.jsengine.JsEngine
import io.ownbit.core.jsengine.JsEngineManager
import io.ownbit.core.jsengine.JsEvent
import io.ownbit.core.jsengine.JsEventSpec
import io.ownbit.core.jsengine.JsResultFormatException
import io.ownbit.core.jsengine.internal.JsProtocol
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import org.junit.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * The 2026-10 XRP / XLM bridge functions (iOS `BILXrpXlmJSBridge.swift`) on the JVM: a scripted engine
 * records what the bridges send (function names, JSON types) and answers like the bundle; result shapes are checked as
 * iOS `BILJSArg.strings` does. What the real bundles compute is checked on a device in the app, and in
 * `js/tools/js-bundles` (`test_xrp.js`, `test_xlm.js`).
 */
class XrpXlmBridgeTest {

    private class FakeEngine(override val bundle: JsBundle) : JsEngine {
        val calls = mutableListOf<Pair<String, JsonArray>>()
        var answer: JsonElement = JsonNull

        override suspend fun call(function: String, args: JsonArray, timeoutMillis: Long): JsonElement {
            calls += function to args
            return answer
        }

        override suspend fun callForEvent(function: String, args: JsonArray, expect: JsEventSpec, timeoutMillis: Long): JsEvent =
            error("the 2026-10 functions are synchronous")

        override val unsolicitedEvents: SharedFlow<JsEvent> = MutableSharedFlow()
    }

    private val xrpEngine = FakeEngine(JsBundle.XRP)
    private val xlmEngine = FakeEngine(JsBundle.XLM)
    private val manager = mockk<JsEngineManager> {
        every { engine(JsBundle.XRP) } returns xrpEngine
        every { engine(JsBundle.XLM) } returns xlmEngine
    }
    private val ripple = RippleJsBridge(manager)
    private val stellar = StellarJsBridge(manager)

    /** The arguments exactly as the page's `JSON.parse` sees them (through the real `evaluateJavascript` statement). */
    private fun argsInThePage(function: String, args: JsonArray): JsonArray {
        val script = JsProtocol.invokeScript(1, function, args)
        val literal = script.removePrefix("window.__ownbitHost.invoke(").removeSuffix(");0")
        val request = Json.parseToJsonElement(Json.parseToJsonElement(literal).jsonPrimitive.content).jsonObject
        assertEquals(function, request["fn"]!!.jsonPrimitive.content)
        return request["args"]!!.jsonArray
    }

    @Test
    fun `XRP indexed derivation sends the seed as a string and the index as a number`() = runTest {
        xrpEngine.answer = JsArgs.of(PUB, R_FRESH)
        assertEquals(PublicKeyAddress(PUB, R_FRESH), ripple.getPublicKeyAndAddressAtIndex(SEED.toCharArray(), 2830416))
        val (function, args) = xrpEngine.calls.single()
        assertEquals("bridge.getPubAddrFromSeedHexIndex", function)
        assertEquals(JsArgs.of(SEED, 2830416), args)
        assertTrue(args[0].jsonPrimitive.isString)
        assertFalse(args[1].jsonPrimitive.isString) // bilIndexKp: typeof i == "number" after Number(t)
    }

    @Test
    fun `XRP results need two non-empty strings`() = runTest {
        for (bad in listOf(JsArgs.of(PUB), JsArgs.of(PUB, ""), JsArgs.of("", R_FRESH), JsArgs.of(PUB, 1), JsonPrimitive(R_FRESH), JsonNull)) {
            xrpEngine.answer = bad
            assertFailsWith<JsResultFormatException>(bad.toString()) { ripple.getPublicKeyAndAddressAtIndex(SEED.toCharArray(), 1) }
        }
    }

    @Test
    fun `deriveAddressFromPubKey takes no secret and needs a non-empty address`() = runTest {
        xrpEngine.answer = JsonPrimitive(R_FRESH)
        assertEquals(R_FRESH, ripple.deriveAddressFromPublicKey(PUB))
        assertEquals("bridge.deriveAddressFromPubKey" to JsArgs.of(PUB), xrpEngine.calls.single())
        xrpEngine.answer = JsonPrimitive("")
        assertFailsWith<JsResultFormatException> { ripple.deriveAddressFromPublicKey(PUB) }
    }

    @Test
    fun `XLM setup sends k as a number and the info as JSON text with the sequence as a string`() = runTest {
        val info = buildJsonObject {
            put("address", G1)
            put("sequence", "236293450399596544") // > 2^53: must stay a string inside the text
            put("serverTime", 1_791_338_400)
            put("perOpFee", 1000)
        }.toString()
        xlmEngine.answer = JsArgs.of(HASH, "AAAA")
        assertEquals(HashAndXdr(HASH, "AAAA"), stellar.buildMsSetup(SEED.toCharArray(), 1, info))
        val (function, args) = xlmEngine.calls.single()
        assertEquals("bridge.buildMsSetupTxWithSeedHexIndex", function)
        assertEquals(JsArgs.of(SEED, 1, info), args)
        val page = argsInThePage(function, args)
        assertTrue(page[2].jsonPrimitive.isString, "info arrives as text for JSON.parse, not as an object")
        val parsed = Json.parseToJsonElement(page[2].jsonPrimitive.content).jsonObject
        assertEquals(JsonPrimitive("236293450399596544"), parsed["sequence"])
    }

    @Test
    fun `XLM indexed derivation, build, sign - function names and argument order`() = runTest {
        xlmEngine.answer = JsArgs.of("e372", G0)
        assertEquals(PublicKeyAddress("e372", G0), stellar.getPublicKeyAndAddressAtIndex(SEED.toCharArray(), 0))
        xlmEngine.answer = JsArgs.of(HASH, "AAAB")
        assertEquals(HashAndXdr(HASH, "AAAB"), stellar.buildMsTxXdr("{\"source\":\"$G1\"}"))
        xlmEngine.answer = JsArgs.of(HASH, "s".repeat(88))
        assertEquals(HashAndSig(HASH, "s".repeat(88)), stellar.signMsTxXdr(SEED.toCharArray(), "AAAB"))
        assertEquals(
            listOf(
                "bridge.getPubAddrFromSeedHexIndex" to JsArgs.of(SEED, 0),
                "bridge.buildMsTxXdr" to JsArgs.of("{\"source\":\"$G1\"}"),
                "bridge.signMsTxXdrWithSeedHex" to JsArgs.of(SEED, "AAAB"),
            ),
            xlmEngine.calls,
        )
    }

    @Test
    fun `XLM pair results need two non-empty strings`() = runTest {
        for (bad in listOf(JsArgs.of(HASH), JsArgs.of(HASH, ""), JsArgs.of("", "AAAA"), JsonPrimitive(HASH))) {
            xlmEngine.answer = bad
            assertFailsWith<JsResultFormatException>(bad.toString()) { stellar.buildMsTxXdr("{}") }
            assertFailsWith<JsResultFormatException>(bad.toString()) { stellar.signMsTxXdr(SEED.toCharArray(), "AAAA") }
        }
    }

    @Test
    fun `decodeMsTxXdr returns the JSON text unchanged and refuses anything else`() = runTest {
        val text = """{"source":"$G1","fee":"100","seqNum":"278350443837390849","minTime":0,"maxTime":1791328423}"""
        xlmEngine.answer = JsonPrimitive(text)
        assertEquals(text, stellar.decodeMsTxXdr("AAAA"))
        assertEquals("bridge.decodeMsTxXdr" to JsArgs.of("AAAA"), xlmEngine.calls.single())
        // iOS `guard result.isString, !s.isEmpty`: a number, an object or "" is a format error.
        for (bad in listOf(JsonPrimitive(""), JsonPrimitive(1), JsonNull, JsArgs.of(text), Json.parseToJsonElement(text))) {
            xlmEngine.answer = bad
            assertFailsWith<JsResultFormatException>(bad.toString()) { stellar.decodeMsTxXdr("AAAA") }
        }
    }

    private companion object {
        /** BIP39 seed of the public test mnemonic "abandon ×11 about". */
        const val SEED = "5eb00bbddcf069084889a8ab9155568165f5c453ccb85e70811aaed6f6da5fc19a5ac40b389cd370d086206dec8aa6c43daea6690f20ad3d8d48b2d2ce9e38e4"
        const val PUB = "0397DDF4C3C796A290BDD7CDE2A7F6C8081B8670222010DFA3D55F0B4018C9B6DE"
        const val R_FRESH = "r3S7AdGba3ZapsPm8ouNWqgsKPmc8HpRwW"
        const val G0 = "GDRXE2BQUC3AZNPVFSCEZ76NJ3WWL25FYFK6RGZGIEKWE4SOOHSUJUJ6"
        const val G1 = "GBAW5XGWORWVFE2XTJYDTLDHXTY2Q2MO73HYCGB3XMFMQ562Q2W2GJQX"
        const val HASH = "d7489cda29b45c6d15aeefeb1a1c2b43a854bad95b079dfe34c7a7d7bbe34539"
    }
}
