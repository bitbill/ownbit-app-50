// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.publicsigner.verify

import io.ownbit.core.chain.evm.EvmTxCodec
import io.ownbit.core.chain.tron.TronAddressCodec
import io.ownbit.core.chain.tron.TronRawData
import io.ownbit.core.chain.tron.TronTransactionProto
import io.ownbit.core.crypto.hash.Hashes
import io.ownbit.core.crypto.util.Hex
import io.ownbit.core.publicsigner.model.PublicPlan
import io.ownbit.core.publicsigner.model.PublicResponseQr
import io.ownbit.core.publicsigner.model.PublicSignResult
import io.ownbit.core.publicsigner.scan.TronLinkRequest
import io.ownbit.core.publicsigner.sign.TronLinkAnswerCodec
import io.ownbit.core.publicsigner.sign.TronLinkRequestMapper
import io.ownbit.core.publicsigner.testing.OtherWalletVectors
import io.ownbit.core.publicsigner.testing.SigningVectors
import io.ownbit.core.scanner.publicqr.TronLinkQrFormat
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import org.bouncycastle.crypto.digests.SHA256Digest
import org.bouncycastle.crypto.ec.CustomNamedCurves
import org.bouncycastle.crypto.params.ECDomainParameters
import org.bouncycastle.crypto.params.ECPrivateKeyParameters
import org.bouncycastle.crypto.signers.ECDSASigner
import org.bouncycastle.crypto.signers.HMacDSAKCalculator
import org.junit.Test
import java.math.BigInteger
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertTrue

/**
 * The post-check of a TronLink answer above 1000 characters (the "answer pager"): the
 * numbered static codes TronLink's "Cold Wallet Signed" reader takes — `cN` 1…`tN` **in order** (TronLink refuses
 * part 2 first), the request's address on the first and last part, its type on the last. The golden vectors only have
 * single-code answers, so this signs a large TronLink entry (V3's transfer with a 600-byte memo) with a test key here;
 * the plan and result are V3's with that key's address and signature.
 */
class TronLinkSplitAnswerVerifierTest {

    private val curve = CustomNamedCurves.getByName("secp256k1")
    private val domain = ECDomainParameters(curve.curve, curve.g, curve.n, curve.h)
    private val key = BigInteger(1, Hashes.sha256("ownbit tronlink split answer test key".toByteArray()))
    private val publicKey = curve.g.multiply(key).normalize().getEncoded(false)
    private val address = PublicSignVerifier.tronAddress(publicKey)!!

    /** V3's `raw_data` with a 600-byte memo (field 10): the signed entry no longer fits one 1000-character code. */
    private val raw = Hex.decode(OtherWalletVectors.V3_ENTRY.substring(6)) + byteArrayOf(0x52, 0xd8.toByte(), 0x04) + ByteArray(600) { 0x41 }
    private val txProto = TronTransactionProto.encode(raw, emptyList())
    private val bean = TronLinkQrFormat.parse("""{"address":"$address","type":1,"hexList":["${Hex.encode(txProto)}"]}""", TronLinkQrFormat.MAX_REQUEST_CHARS)!!
    private val request = TronLinkRequestMapper.map(TronLinkRequest.of(bean))
    private val signature = sign(Hashes.sha256(raw))
    private val entry = TronLinkAnswerCodec.signedTransaction(txProto, signature)

    private val id = "O-TL-V3-trx-transfer"
    private val plan = PublicPlan.fromEngine(withTaskAddress(SigningVectors.planJson(id)))
    private val result = PublicSignResult.fromEngine(JsonObject(SigningVectors.signResults(id).last() + ("signature" to JsonPrimitive(Hex.encode(signature)))))
    private val verified = VerifiedPayload.TronTransaction(
        raw,
        TronRawData.decodeOrNull(Hex.decode(OtherWalletVectors.V3_ENTRY.substring(6)))!!,
        TronAddressCodec.toHex41(address)!!.lowercase(),
        1,
        txProto,
    )

    /** `r ‖ s ‖ recId` (RFC 6979, low-S) of [digest] with the test key. */
    private fun sign(digest: ByteArray): ByteArray {
        val signer = ECDSASigner(HMacDSAKCalculator(SHA256Digest()))
        signer.init(true, ECPrivateKeyParameters(key, domain))
        val (r, s0) = signer.generateSignature(digest).let { it[0] to it[1] }
        val s = if (s0 > curve.n.shiftRight(1)) curve.n - s0 else s0
        val recId = (0..1).first { EvmTxCodec.recoverPublicKey(digest, it, r, s)?.contentEquals(publicKey) == true }
        return fixed32(r) + fixed32(s) + byteArrayOf(recId.toByte())
    }

    private fun fixed32(v: BigInteger): ByteArray = v.toByteArray().let { b -> ByteArray(32 - minOf(32, b.size)) + b.takeLast(32).toByteArray() }

    private fun withTaskAddress(plan: JsonObject): JsonObject {
        val task = plan.getValue("tasks").jsonArray.single().jsonObject
        val target = task.getValue("targets").jsonArray.single().jsonObject
        val newTask = JsonObject(
            task + ("addresses" to JsonArray(listOf(JsonPrimitive(address)))) +
                ("targets" to JsonArray(listOf(JsonObject(target + ("address" to JsonPrimitive(address)))))),
        )
        return JsonObject(plan + ("tasks" to JsonArray(listOf(newTask))))
    }

    private fun post(frames: List<String>): PublicSignVerifier.Verdict =
        PublicSignVerifier.post(request, plan, verified, result, PublicResponseQr(PublicResponseQr.TRONLINK, frames, null, signedTransaction = true))

    private fun refused(frames: List<String>): String = assertIs<PublicSignVerifier.Verdict.Refused>(post(frames)).detail

    @Test fun `a split answer in TronLink's numbered codes is verified`() {
        val frames = TronLinkAnswerCodec.encode(bean.json, listOf(entry))
        assertTrue(frames.size >= 2, "the entry is ${entry.length} characters")
        assertIs<PublicSignVerifier.Verdict.Ok>(post(frames), "${post(frames)}")
        frames.forEachIndexed { i, frame ->
            val part = TronLinkQrFormat.parse(frame)!!
            assertEquals(i + 1 to frames.size, part.cN to part.tN)
            assertEquals(if (i == 0 || i == frames.lastIndex) address else null, part.address)
            assertEquals(if (i == frames.lastIndex) 1 else 0, part.type)
        }
    }

    @Test fun `a split answer out of order, of another type, missing a part or not split is refused`() {
        val frames = TronLinkAnswerCodec.encode(bean.json, listOf(entry))
        // TronLink demands part 1 first and then strictly the next: the pager must show them in that order.
        assertEquals("response.tronlink.order", refused(frames.reversed()))
        val otherType = TronLinkAnswerCodec.encode(JsonObject(bean.json + ("type" to JsonPrimitive(7))), listOf(entry))
        assertEquals("response.tronlink.parts", refused(otherType))
        assertEquals("response.tronlink.decode", refused(frames.dropLast(1)))
        // The same entry in one code: above 1000 characters TronLink's reader expects numbered parts.
        val single = listOf(TronLinkAnswerCodec.answerBean(bean.json, listOf(entry)).toString())
        assertEquals("response.tronlink.split", refused(single))
        // Another key's signature in correctly numbered parts.
        val forged = TronLinkAnswerCodec.signedTransaction(txProto, Hex.decode(OtherWalletVectors.V3_SIG))
        assertEquals("response.tronlink.appended", refused(TronLinkAnswerCodec.encode(bean.json, listOf(forged))))
    }
}
