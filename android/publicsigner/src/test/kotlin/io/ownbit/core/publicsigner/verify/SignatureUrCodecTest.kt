// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.publicsigner.verify

import io.ownbit.core.crypto.util.Hex
import io.ownbit.core.publicsigner.model.obj
import io.ownbit.core.publicsigner.model.str
import io.ownbit.core.publicsigner.testing.SigningVectors
import io.ownbit.core.publicsigner.testing.TestUr
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Kotlin's own decoding of the answer QR: every answer the pinned engine produced in the golden
 * vectors decodes to exactly what the engine says it carries (its `describeQR` payload view), and malformed or extra
 * content is refused.
 */
class SignatureUrCodecTest {

    private val signatureFlows = SigningVectors.answeredFlows.filter { SigningVectors.encoded(it).str("type")!!.endsWith("-signature") }
    private val psbtFlows = SigningVectors.answeredFlows.filter { !SigningVectors.encoded(it).str("type")!!.endsWith("-signature") }

    @Test fun `every engine signature answer decodes to its request id and signature`() {
        assertTrue(signatureFlows.size >= 20, "$signatureFlows")
        for (id in signatureFlows) {
            val encoded = SigningVectors.encoded(id)
            val answer = SignatureUrCodec.decodeSignature(SigningVectors.response(id).frames)
            assertEquals(encoded.str("type"), answer.type, id)
            val payload = encoded.obj("payload")!!
            assertEquals(payload.str("signature"), Hex.encode(answer.signature), id)
            val expectedId = payload.obj("request-id")?.str("uuid")
            assertEquals(expectedId, answer.requestId?.let(Hex::encode), id)
            assertEquals(SigningVectors.request(id).obj("transport")?.str("requestId"), answer.requestId?.let(Hex::encode), id)
        }
    }

    @Test fun `imToken's 36-byte request id is echoed byte for byte`() {
        val answer = SignatureUrCodec.decodeSignature(SigningVectors.response("O-RESP-1-imtoken-36-byte-id").frames)
        assertEquals(36, answer.requestId!!.size)
        assertEquals(SigningVectors.request("O-RESP-1-imtoken-36-byte-id").obj("transport")!!.str("requestId"), Hex.encode(answer.requestId!!))
    }

    @Test fun `an answer without a request id has no key 1`() {
        assertNull(SignatureUrCodec.decodeSignature(SigningVectors.response("T8-flow-evm-personal-without-request-id").frames).requestId)
    }

    @Test fun `an animated eth-signature (pure fountain parts) decodes in any order`() {
        val frames = SigningVectors.response("T8-flow-evm-eip1559-animated-response").frames
        assertEquals(3, frames.size)
        val inOrder = SignatureUrCodec.decodeSignature(frames)
        val shuffled = SignatureUrCodec.decodeSignature(listOf(frames[2], frames[0], frames[1], frames[0]))
        assertContentEquals(inOrder.signature, shuffled.signature)
        assertEquals(Hex.encode(SigningVectors.encoded("T8-flow-evm-eip1559-animated-response").obj("payload")!!.str("signature")!!.let(Hex::decode)), Hex.encode(inOrder.signature))
        assertFailsWith<PublicVerifyException> { SignatureUrCodec.decodeSignature(frames.take(2)) }
    }

    @Test fun `the Keystone TRON signature fixture decodes to its published values`() {
        val fixture = Json.parseToJsonElement(javaClass.classLoader!!.getResource("pubsigner/keystone-tron-public.json")!!.readText()).jsonObject
        val answer = SignatureUrCodec.decodeSignature(listOf(fixture.getValue("signatureUR").jsonPrimitive.content))
        assertEquals("tron-signature", answer.type)
        assertEquals(fixture.getValue("requestId").jsonPrimitive.content, Hex.encode(answer.requestId!!))
        assertEquals(fixture.getValue("signatureHex").jsonPrimitive.content, Hex.encode(answer.signature))
    }

    @Test fun `every engine PSBT answer decodes to the engine's psbt_base64`() {
        assertTrue(psbtFlows.size >= 15, "$psbtFlows")
        val types = HashSet<String>()
        for (id in psbtFlows) {
            val encoded = SigningVectors.encoded(id)
            val type = encoded.str("type")!!
            types += type
            val bytes = SignatureUrCodec.decodePsbt(type, SigningVectors.response(id).frames)
            assertEquals(encoded.obj("payload")!!.str("psbt_base64"), java.util.Base64.getEncoder().encodeToString(bytes), id)
        }
        assertEquals(setOf("crypto-psbt", "psbt", "bbqr-psbt", "psbt-base64", "psbt-hex"), types)
    }

    @Test fun `extra keys, a missing signature, a wrong tag and a broken checksum are refused`() {
        val id = "8f235e99e6e84044a51d51ec3ec942b0"
        val sig = ByteArray(65) { 1 }
        assertContentEquals(sig, SignatureUrCodec.decodeSignature(listOf(TestUr.signature("eth-signature", id, sig))).signature)
        // An origin (key 3) or anything else besides 1 and 2 (signature-only answers).
        assertFailsWith<PublicVerifyException> { SignatureUrCodec.decodeSignature(listOf(TestUr.signature("eth-signature", id, sig, mapOf(3L to "dapp")))) }
        // No signature.
        val noSig = TestUr.single("eth-signature", TestUr.cbor(mapOf(1L to TestUr.Tag(37, Hex.decode(id)))))
        assertFailsWith<PublicVerifyException> { SignatureUrCodec.decodeSignature(listOf(noSig)) }
        // Request id not under the UUID tag 37.
        val wrongTag = TestUr.single("eth-signature", TestUr.cbor(mapOf(1L to TestUr.Tag(38, Hex.decode(id)), 2L to sig)))
        assertFailsWith<PublicVerifyException> { SignatureUrCodec.decodeSignature(listOf(wrongTag)) }
        // Not a signature type.
        assertFailsWith<PublicVerifyException> { SignatureUrCodec.decodeSignature(listOf(TestUr.signature("crypto-hdkey", id, sig))) }
        // One bytewords letter changed: the CRC-32 fails.
        val good = TestUr.signature("eth-signature", id, sig)
        val flipped = good.substring(0, good.length - 12) + (if (good[good.length - 12] == 'A') 'B' else 'A') + good.substring(good.length - 11)
        assertFailsWith<PublicVerifyException> { SignatureUrCodec.decodeSignature(listOf(flipped)) }
        // Two single-part frames, or a mixed fountain part (seq > count).
        assertFailsWith<PublicVerifyException> { SignatureUrCodec.decodeSignature(listOf(good, good)) }
        val mixed = SigningVectors.response("T8-flow-evm-eip1559-animated-response").frames[0].replaceFirst("/1-3/", "/4-3/")
        assertFailsWith<PublicVerifyException> { SignatureUrCodec.decodeUr(listOf(mixed)) }
    }

    @Test fun `strict CBOR - duplicate keys, indefinite lengths and trailing bytes`() {
        assertEquals(mapOf<Any, Any?>(1L to 1L, 2L to 2L), Cbor.decode(Hex.decode("a201010202")))
        assertFailsWith<PublicVerifyException> { Cbor.decode(Hex.decode("a201010101")) } // duplicate key 1
        assertFailsWith<PublicVerifyException> { Cbor.decode(Hex.decode("5f4101ff")) } // indefinite byte string
        assertFailsWith<PublicVerifyException> { Cbor.decode(Hex.decode("0101")) } // trailing byte
        assertFailsWith<PublicVerifyException> { Cbor.decode(Hex.decode("1bffffffffffffffff")) } // beyond 2^53 - 1
        assertEquals(10L, Cbor.decode(Hex.decode("0a")))
    }

    @Test fun `BBQr answers - one header, every part once, the right alphabet`() {
        val frames = SigningVectors.response("T8-flow-bitcoin-bbqr-base32").frames
        assertTrue(frames.size > 1)
        // Missing part.
        assertFailsWith<PublicVerifyException> { SignatureUrCodec.decodePsbt("bbqr-psbt", frames.drop(1)) }
        // A part of another header.
        assertFailsWith<PublicVerifyException> { SignatureUrCodec.decodePsbt("bbqr-psbt", frames + frames[0].replaceFirst("B$2P", "B\$HP")) }
        // Any order is fine.
        assertContentEquals(SignatureUrCodec.decodePsbt("bbqr-psbt", frames), SignatureUrCodec.decodePsbt("bbqr-psbt", frames.reversed()))
        // Base32 padding bits must be zero; Base64 must be canonical.
        assertFailsWith<PublicVerifyException> { SignatureUrCodec.base32("AB") }
        assertFailsWith<PublicVerifyException> { SignatureUrCodec.base64("cHNidP8") }
    }
}
