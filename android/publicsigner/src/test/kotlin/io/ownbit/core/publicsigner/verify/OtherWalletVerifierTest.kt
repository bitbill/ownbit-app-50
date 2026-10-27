// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.publicsigner.verify

import io.ownbit.core.crypto.util.Hex
import io.ownbit.core.publicsigner.model.PublicResponseQr
import io.ownbit.core.publicsigner.model.PublicSignResult
import io.ownbit.core.publicsigner.scan.TronLinkRequest
import io.ownbit.core.publicsigner.sign.PublicSignSession
import io.ownbit.core.publicsigner.sign.TronLinkAnswerCodec
import io.ownbit.core.publicsigner.sign.TronLinkRequestMapper
import io.ownbit.core.publicsigner.testing.OtherWalletVectors
import io.ownbit.core.publicsigner.testing.SigningVectors
import io.ownbit.core.scanner.publicqr.TronLinkQrFormat
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs

/**
 * [PublicSignVerifier] on the TronLink transport (TokenPocket's transport is refused): the pre-check
 * binds the engine request to the scanned text (re-mapped with the same mapper) and the plan's digest; the post-check
 * reads Ownbit's own answer frames back and recovers the signer. The engine side is the golden vectors.
 */
class OtherWalletVerifierTest {

    private fun session(id: String, request: JsonObject): PublicSignSession {
        val plan = SigningVectors.plan(id)
        return PublicSignSession("req-$id", request, plan.review!!, plan)
    }

    private fun tronLinkRequest(text: String): JsonObject = TronLinkRequestMapper.map(TronLinkRequest.of(TronLinkQrFormat.parse(text)!!))

    private fun ok(v: PublicSignVerifier.Verdict): VerifiedPayload? = assertIs<PublicSignVerifier.Verdict.Ok>(v, "$v").payload

    private fun refused(v: PublicSignVerifier.Verdict, detail: String) =
        assertEquals(detail, assertIs<PublicSignVerifier.Verdict.Refused>(v, "$v").detail)

    private fun result(id: String): PublicSignResult = SigningVectors.finalResult(id)

    private fun tronLinkAnswer(request: String, entry: String) =
        PublicResponseQr(PublicResponseQr.TRONLINK, TronLinkAnswerCodec.encode(TronLinkQrFormat.parse(request)!!.json, listOf(entry)), null)

    @Test fun `TronLink V1 - the ownership placeholder is verified before and after signing`() {
        val id = "O-TL-V1-ownership-ios"
        val s = session(id, tronLinkRequest(OtherWalletVectors.V1_REQUEST))
        val proof = assertIs<VerifiedPayload.TronOwnershipProof>(ok(PublicSignVerifier.pre(s)))
        assertEquals("TronLinkCustomContract", proof.name)
        assertEquals("41c8599111f29c1e1e061265b4af93ea1f274ad78a", proof.ownerHex41)
        val signed = s.copy(verified = proof)
        val entry = OtherWalletVectors.V1_ENTRY + "1241" + OtherWalletVectors.V1_SIG
        ok(PublicSignVerifier.post(signed, result(id), tronLinkAnswer(OtherWalletVectors.V1_REQUEST, entry)))
        // A changed answer: another signature (V3's), a dropped key, a second signature, a truncated entry.
        refused(
            PublicSignVerifier.post(signed, result(id), tronLinkAnswer(OtherWalletVectors.V1_REQUEST, OtherWalletVectors.V1_ENTRY + "1241" + OtherWalletVectors.V3_SIG)),
            "response.tronlink.appended",
        )
        val dropped = PublicResponseQr(PublicResponseQr.TRONLINK, listOf("""{"address":"${OtherWalletVectors.TRON_0}","type":99,"hexList":["$entry"]}"""), null)
        refused(PublicSignVerifier.post(signed, result(id), dropped), "response.tronlink.keys")
        refused(
            PublicSignVerifier.post(signed, result(id), tronLinkAnswer(OtherWalletVectors.V1_REQUEST, entry + "1241" + OtherWalletVectors.V1_SIG)),
            "response.tronlink.signatures",
        )
        refused(PublicSignVerifier.post(signed, result(id), PublicResponseQr("tron-signature", listOf("ur:x"), null)), "response.type")
    }

    @Test fun `TronLink V3 - a TRX transfer, and the request must be the scanned one`() {
        val id = "O-TL-V3-trx-transfer"
        val request = tronLinkRequest(OtherWalletVectors.V3_REQUEST)
        val s = session(id, request)
        val tx = assertIs<VerifiedPayload.TronTransaction>(ok(PublicSignVerifier.pre(s)))
        assertEquals(1, tx.contractType)
        assertEquals(OtherWalletVectors.V3_ENTRY, Hex.encode(tx.txProto!!))
        ok(PublicSignVerifier.post(s.copy(verified = tx), result(id), tronLinkAnswer(OtherWalletVectors.V3_REQUEST, OtherWalletVectors.V3_ENTRY + "1241" + OtherWalletVectors.V3_SIG)))
        // The engine request differs from what the scanned text maps to (here: the TronLink type).
        val tampered = JsonObject(request + ("transport" to JsonObject(request.getValue("transport") as JsonObject + ("tronlinkType" to JsonPrimitive(7)))))
        refused(PublicSignVerifier.pre(session(id, tampered)), "tronlink.request.differs")
        // A wrong recovery byte (TronLink would recover another signer).
        val badRecId = OtherWalletVectors.V3_SIG.dropLast(2) + "00"
        refused(
            PublicSignVerifier.post(s.copy(verified = tx), result(id), tronLinkAnswer(OtherWalletVectors.V3_REQUEST, OtherWalletVectors.V3_ENTRY + "1241" + badRecId)),
            "response.tronlink.appended",
        )
    }

    @Test fun `TronLink V4 - a TIP-191 message answers 0x r s v`() {
        val id = "O-TL-V4-tip191-message"
        val s = session(id, tronLinkRequest(OtherWalletVectors.V4_REQUEST))
        val message = assertIs<VerifiedPayload.TronMessage>(ok(PublicSignVerifier.pre(s)))
        assertEquals("hello ownbit", String(message.message))
        ok(PublicSignVerifier.post(s.copy(verified = message), result(id), tronLinkAnswer(OtherWalletVectors.V4_REQUEST, OtherWalletVectors.V4_MESSAGE_SIGNATURE)))
        val v27 = OtherWalletVectors.V4_MESSAGE_SIGNATURE.dropLast(2) + "1b"
        refused(PublicSignVerifier.post(s.copy(verified = message), result(id), tronLinkAnswer(OtherWalletVectors.V4_REQUEST, v27)), "response.tronlink.message")
    }

    @Test fun `a TRON request on TokenPocket's transport is refused before signing`() {
        // There is no TokenPocket path — the verifier has no `tokenpocket` branch, so such a request
        // (whatever produced it) falls to the UR check and is refused (fail closed).
        val id = "O-TL-V3-trx-transfer"
        val request = tronLinkRequest(OtherWalletVectors.V3_REQUEST)
        val transport = JsonObject(
            mapOf(
                "type" to JsonPrimitive("tokenpocket"),
                "payloadEncoding" to JsonPrimitive("tokenpocket-text"),
                "payloadBytes" to JsonPrimitive(Hex.encode(OtherWalletVectors.tpRequest.toByteArray(Charsets.UTF_8))),
                "origin" to JsonPrimitive("TokenPocket"),
            ),
        )
        refused(PublicSignVerifier.pre(session(id, JsonObject(request + ("transport" to transport)))), "tron.transport")
    }
}
