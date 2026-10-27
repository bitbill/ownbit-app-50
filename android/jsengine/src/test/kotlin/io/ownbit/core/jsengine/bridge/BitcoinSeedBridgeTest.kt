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
import io.ownbit.core.jsengine.internal.JsProtocol
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * The BIP39 passphrase reaches `bridge.mnemonicToSeedHex(m, password, 0)` verbatim, as data through
 * [JsArgs] (no hand escaping, no `encodeMessageForJs`), and `null` is the empty passphrase every other wallet uses. The
 * seeds themselves are checked against the passphrase vectors on a device (in the app).
 */
class BitcoinSeedBridgeTest {

    private class FakeEngine : JsEngine {
        override val bundle: JsBundle = JsBundle.BTC
        val calls = mutableListOf<Pair<String, JsonArray>>()
        var answer: JsonElement = JsonPrimitive(SEED)

        override suspend fun call(function: String, args: JsonArray, timeoutMillis: Long): JsonElement {
            calls += function to args
            return answer
        }

        override suspend fun callForEvent(function: String, args: JsonArray, expect: JsEventSpec, timeoutMillis: Long): JsEvent =
            error("synchronous")

        override val unsolicitedEvents: SharedFlow<JsEvent> = MutableSharedFlow()
    }

    private val engine = FakeEngine()
    private val bridge = BitcoinJsBridge(mockk<JsEngineManager> { every { engine(JsBundle.BTC) } returns engine })

    /** The arguments exactly as the page's `JSON.parse` sees them (through the real `evaluateJavascript` statement). */
    private fun argsInThePage(function: String, args: JsonArray): JsonArray {
        val script = JsProtocol.invokeScript(1, function, args)
        val literal = script.removePrefix("window.__ownbitHost.invoke(").removeSuffix(");0")
        val request = Json.parseToJsonElement(Json.parseToJsonElement(literal).jsonPrimitive.content).jsonObject
        assertEquals(function, request["fn"]!!.jsonPrimitive.content)
        return request["args"]!!.jsonArray
    }

    @Test fun `no passphrase is the empty string, seed type 0`() = runTest {
        assertEquals(SEED, bridge.mnemonicToSeedHex(MNEMONIC))
        assertEquals(SEED, bridge.mnemonicToSeedHex(MNEMONIC, null))
        for ((function, args) in engine.calls) {
            assertEquals("bridge.mnemonicToSeedHex", function)
            assertEquals(JsArgs.of(MNEMONIC, "", 0), args)
            assertFalse(args[2].jsonPrimitive.isString, "seedType is a number")
        }
        assertEquals(2, engine.calls.size)
    }

    @Test fun `the passphrase arrives in the page verbatim, whatever it contains`() = runTest {
        val passphrases = listOf(
            "TREZOR",
            "pass\"word'with\\backslash",
            "line1\nline2\r\n",
            "a b c",
            "'); throw new Error('x'); //",
            "\"); window.__ownbitHost = null; (\"",
            "${'$'}{x} `tpl` </script>",
            "  edge spaces  ",
            "Ｔｒｅｚｏｒ 😀 中文",
            "é",
        )
        for (p in passphrases) {
            engine.calls.clear()
            bridge.mnemonicToSeedHex(MNEMONIC, p.toCharArray())
            val (function, args) = engine.calls.single()
            assertEquals("bridge.mnemonicToSeedHex", function)
            assertEquals(JsArgs.of(MNEMONIC, p, 0), args)
            val inPage = argsInThePage(function, args)
            assertEquals(3, inPage.size)
            assertEquals(MNEMONIC, inPage[0].jsonPrimitive.content)
            assertTrue(inPage[1].jsonPrimitive.isString)
            assertEquals(p, inPage[1].jsonPrimitive.content, "passphrase changed on its way to JS")
            assertEquals("0", inPage[2].jsonPrimitive.content)
        }
    }

    @Test fun `the bridge does not keep or wipe the caller's array`() = runTest {
        val p = "TREZOR".toCharArray()
        bridge.mnemonicToSeedHex(MNEMONIC, p)
        assertEquals("TREZOR", String(p), "the caller owns (and wipes) the passphrase")
    }

    private companion object {
        const val MNEMONIC = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
        const val SEED = "c55257c360c07c72029aebc1b53c05ed0362ada38ead3e3e9efa3708e53495531f09a6987599d18264c1e1c92f2cf141630c7a3c4ab7c81b2f001698e7463b04"
    }
}
