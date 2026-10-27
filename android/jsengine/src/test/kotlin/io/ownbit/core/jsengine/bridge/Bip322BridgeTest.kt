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
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Test
import java.util.Base64
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * The BIP-322 functions of the Taproot bridge on the JVM: the WebView cannot run here, so a scripted
 * engine records what the bridge sends and answers like the bundle. What the real bundle computes is checked by the
 * instrumented `Bip322BundleTest` (emulator) and by the iOS `npm test` of the same file (same SHA-256).
 */
class Bip322BridgeTest {

    private class FakeEngine : JsEngine {
        override val bundle: JsBundle = JsBundle.BTC_TAPROOT
        val calls = mutableListOf<Pair<String, JsonArray>>()
        var answer: JsonElement = JsonNull

        override suspend fun call(function: String, args: JsonArray, timeoutMillis: Long): JsonElement {
            calls += function to args
            return answer
        }

        override suspend fun callForEvent(function: String, args: JsonArray, expect: JsEventSpec, timeoutMillis: Long): JsEvent =
            error("not used")

        override val unsolicitedEvents: SharedFlow<JsEvent> = MutableSharedFlow()
    }

    private val engine = FakeEngine()
    private val bridge = BitcoinTaprootJsBridge(mockk<JsEngineManager> { every { engine(JsBundle.BTC_TAPROOT) } returns engine })

    /** The arguments exactly as the page's `JSON.parse` sees them (through the real `evaluateJavascript` statement). */
    private fun argsInThePage(function: String, args: JsonArray): JsonArray {
        val script = JsProtocol.invokeScript(1, function, args)
        assertTrue(script.all { it.code in 0x20..0x7E }, "the statement is plain ASCII")
        val literal = script.removePrefix("window.__ownbitHost.invoke(").removeSuffix(");0")
        val request = Json.parseToJsonElement(Json.parseToJsonElement(literal).jsonPrimitive.content).jsonObject
        assertEquals(function, request["fn"]!!.jsonPrimitive.content)
        return request["args"]!!.jsonArray
    }

    @Test
    fun `signMessageBip322 sends seed, branch flag, numeric index, address and the raw message as JSON`() = runTest {
        engine.answer = JsonPrimitive(SIGNATURE)
        val signature = bridge.signMessageBip322(SEED.toCharArray(), isChange = true, index = 7, address = TR00, message = MESSAGE)
        assertEquals(SIGNATURE, signature)
        val (function, args) = engine.calls.single()
        assertEquals("bridge.signMessageBip322", function)
        assertEquals(JsArgs.of(SEED, true, 7L, TR00, MESSAGE), args)
        // types the bundle checks: a JSON boolean and an integer number (Number.isInteger), not strings
        assertEquals(JsonPrimitive(true), args[1])
        assertFalse(args[2].jsonPrimitive.isString)
        assertEquals("7", args[2].jsonPrimitive.content)
        // quotes, line breaks, emoji and even the iOS pre-encoding tokens arrive unchanged (no _QUOTE_OWNBIT_ encoding)
        val page = argsInThePage(function, args)
        assertEquals(MESSAGE, page[4].jsonPrimitive.content)
        assertEquals(SEED, page[0].jsonPrimitive.content)
    }

    @Test
    fun `signMessageBip322WithPrivateKey sends key, address and the raw message`() = runTest {
        engine.answer = JsonPrimitive(SIGNATURE)
        assertEquals(SIGNATURE, bridge.signMessageBip322WithPrivateKey("KyrSGCFPtest".toCharArray(), PK_TR, MESSAGE))
        val (function, args) = engine.calls.single()
        assertEquals("bridge.signMessageBip322WithPrivateKey", function)
        assertEquals(JsArgs.of("KyrSGCFPtest", PK_TR, MESSAGE), args)
        assertEquals(MESSAGE, argsInThePage(function, args)[2].jsonPrimitive.content)
    }

    @Test
    fun `an index outside 0 until 2^31 is refused before the bundle`() = runTest {
        assertFailsWith<IllegalArgumentException> { bridge.signMessageBip322(SEED.toCharArray(), false, -1, TR00, "m") }
        assertFailsWith<IllegalArgumentException> { bridge.signMessageBip322(SEED.toCharArray(), false, 0x8000_0000L, TR00, "m") }
        assertTrue(engine.calls.isEmpty())
        engine.answer = JsonPrimitive(SIGNATURE)
        bridge.signMessageBip322(SEED.toCharArray(), false, 0x7FFF_FFFFL, TR00, "m")
        assertEquals(JsonPrimitive(0x7FFF_FFFFL), engine.calls.single().second[2])
    }

    @Test
    fun `an empty or non-string signature is a format error`() = runTest {
        engine.answer = JsonPrimitive("")
        assertFailsWith<JsResultFormatException> { bridge.signMessageBip322(SEED.toCharArray(), false, 0, TR00, "m") }
        engine.answer = JsonNull
        assertFailsWith<JsResultFormatException> { bridge.signMessageBip322WithPrivateKey("k".toCharArray(), TR00, "m") }
    }

    @Test
    fun `verifyMessageBip322 sends address, message, signature and maps the three results`() = runTest {
        for ((js, expected) in listOf("valid" to Bip322Verification.VALID, "invalid" to Bip322Verification.INVALID, "unsupported" to Bip322Verification.UNSUPPORTED)) {
            engine.answer = JsonPrimitive(js)
            assertEquals(expected, bridge.verifyMessageBip322(TR00, MESSAGE, SIGNATURE))
        }
        val (function, args) = engine.calls.last()
        assertEquals("bridge.verifyMessageBip322", function)
        assertEquals(JsArgs.of(TR00, MESSAGE, SIGNATURE), args)
        assertEquals(MESSAGE, argsInThePage(function, args)[1].jsonPrimitive.content)
        for (other in listOf(JsonPrimitive("VALID"), JsonPrimitive(true), JsonNull)) {
            engine.answer = other
            assertFailsWith<JsResultFormatException>(other.toString()) { bridge.verifyMessageBip322(TR00, "m", SIGNATURE) }
        }
    }

    @Test
    fun `bip322Hashes returns the three hashes and checks their shape`() = runTest {
        // BIP-322 basic vector "Hello World" for bc1q9vza2e8x573nczrlzms0wvx3gsqjx7vavgkx0l
        val hashes = listOf(
            "f0eb03b1a75ac6d9847f55c624a99169b5dccba2a31f5b23bea77ba270de0a7a",
            "b79d196740ad5217771c1098fc4a4b51e0535c32236c71f1ea4d61a2d603352b",
            "88737ae86f2077145f93cc4b153ae9a1cb8d56afa511988c149c5c8c9d93bddf",
        )
        engine.answer = JsArgs.of(*hashes.toTypedArray())
        assertEquals(Bip322Hashes(hashes[0], hashes[1], hashes[2]), bridge.bip322Hashes("bc1q9vza2e8x573nczrlzms0wvx3gsqjx7vavgkx0l", "Hello World"))
        assertEquals("bridge.bip322Hashes", engine.calls.single().first)
        engine.answer = JsArgs.of(hashes[0], hashes[1])
        assertFailsWith<JsResultFormatException> { bridge.bip322Hashes(TR00, "m") }
        engine.answer = JsArgs.of(hashes[0], hashes[1], hashes[2].uppercase())
        assertFailsWith<JsResultFormatException> { bridge.bip322Hashes(TR00, "m") }
    }

    private fun base64(size: Int, header: Int): String =
        Base64.getEncoder().encodeToString(ByteArray(size) { if (it == 0) header.toByte() else 0x11 })

    @Test
    fun `legacy signature detection - 65 bytes, header 27 to 42, whitespace ignored`() {
        assertFalse(BitcoinTaprootJsBridge.isLegacyMessageSignature(base64(65, 26)))
        for (header in 27..42) assertTrue(BitcoinTaprootJsBridge.isLegacyMessageSignature(base64(65, header)), "header $header")
        assertFalse(BitcoinTaprootJsBridge.isLegacyMessageSignature(base64(65, 43)))
        assertFalse(BitcoinTaprootJsBridge.isLegacyMessageSignature(base64(65, 0)))
        assertFalse(BitcoinTaprootJsBridge.isLegacyMessageSignature(base64(65, 0xff)))
        assertFalse(BitcoinTaprootJsBridge.isLegacyMessageSignature(base64(64, 31)))
        assertFalse(BitcoinTaprootJsBridge.isLegacyMessageSignature(base64(66, 31)))
        // The deterministic legacy signature of /0/0, also when pasted with line breaks and spaces
        assertTrue(BitcoinTaprootJsBridge.isLegacyMessageSignature(LEGACY_SIGNATURE))
        assertTrue(BitcoinTaprootJsBridge.isLegacyMessageSignature(" " + LEGACY_SIGNATURE.chunked(30).joinToString("\n") + "\t\r\n"))
        // not standard base64 / not a multiple of 4 (iOS Data(base64Encoded:)) / empty
        assertFalse(BitcoinTaprootJsBridge.isLegacyMessageSignature(LEGACY_SIGNATURE.removeSuffix("=")))
        assertFalse(BitcoinTaprootJsBridge.isLegacyMessageSignature(LEGACY_SIGNATURE.replace('/', '_')))
        assertFalse(BitcoinTaprootJsBridge.isLegacyMessageSignature(""))
        assertFalse(BitcoinTaprootJsBridge.isLegacyMessageSignature("hello"))
    }

    @Test
    fun `BIP-322 signatures are never taken for legacy ones`() {
        assertFalse(BitcoinTaprootJsBridge.isLegacyMessageSignature(IOS_TAPROOT_SIGNATURE)) // simple, 66 bytes, starts 0x01
        assertFalse(BitcoinTaprootJsBridge.isLegacyMessageSignature("smp$IOS_TAPROOT_SIGNATURE"))
        assertFalse(BitcoinTaprootJsBridge.isLegacyMessageSignature(BC1Q_SMP_SIGNATURE))
        assertFalse(BitcoinTaprootJsBridge.isLegacyMessageSignature(BC1Q_SMP_SIGNATURE.removePrefix("smp")))
        assertFalse(BitcoinTaprootJsBridge.isLegacyMessageSignature("ful" + base64(65, 31).drop(3)))
        assertFalse(BitcoinTaprootJsBridge.isLegacyMessageSignature("pof$IOS_TAPROOT_SIGNATURE"))
        // a 65-byte witness stack (count 2) is not legacy either
        assertFalse(BitcoinTaprootJsBridge.isLegacyMessageSignature(base64(65, 2)))
    }

    private companion object {
        /** BIP39 seed of the public test mnemonic "abandon ×11 about". */
        const val SEED = "5eb00bbddcf069084889a8ab9155568165f5c453ccb85e70811aaed6f6da5fc19a5ac40b389cd370d086206dec8aa6c43daea6690f20ad3d8d48b2d2ce9e38e4"
        const val TR00 = "bc1p5cyxnuxmeuwuvkwfem96lqzszd02n6xdcjrs20cac6yqjjwudpxqkedrcr"
        const val PK_TR = "bc1pss0zhytly75awhm6x2hhvd5lnzv3vssgrf9axfheq8ldyzn88ges79fler"
        const val MESSAGE = "say \"hi\" \\ 'x'\nline 2\r\n✓ 测试 😄 _QUOTE_OWNBIT_ _NEWLINE_OWNBIT_ </script>"
        const val SIGNATURE = "AUCwRjby0yq6tdkpscsKllyJa1yGhs/bVF6E5/Rgh6flrQ3LTlYyT0cJezc0ikSplvirum+TlRG06O/9IzIpUlkp"
        const val IOS_TAPROOT_SIGNATURE = SIGNATURE
        const val LEGACY_SIGNATURE = "IBxJDhRTJ2X4HENhuDY4oJgW86Ugl4Zmxm5IWm4j/xR9GXTSng8a9xWp2g4zsl6yCAiNcEQq4zsS8CqApikty6g="
        const val BC1Q_SMP_SIGNATURE =
            "smpAkgwRQIhAOzyynlqt93lOKJr+wmmxIens//zPzl9tqIOua93wO6MAiBi5n5EyAcPScOjf1lAqIUIQtr3zKNeavYabHyR8eGhowEhAsfxIAMZZEKUPYWI4BruhAQjzFT8FSFSajuFwrDL1Yhy"
    }
}
