// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.publicsigner.verify

import io.ownbit.core.crypto.util.Hex
import io.ownbit.core.publicsigner.model.PublicPlan
import io.ownbit.core.publicsigner.model.PublicResponseQr
import io.ownbit.core.publicsigner.model.PublicSignResult
import io.ownbit.core.publicsigner.model.obj
import io.ownbit.core.publicsigner.model.str
import io.ownbit.core.publicsigner.testing.SigningVectors
import io.ownbit.core.publicsigner.testing.TestUr
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Test
import java.util.Base64
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertTrue

/**
 * [PublicSignVerifier] on the real engine answers of the
 * golden vectors: every answered flow passes pre and post; each tampered variant is refused.
 */
class PublicSignVerifierTest {

    private fun pre(id: String, request: JsonObject = SigningVectors.request(id), plan: PublicPlan = SigningVectors.plan(id)) =
        PublicSignVerifier.pre(request, plan, plan.review?.network?.chainId)

    private fun ok(verdict: PublicSignVerifier.Verdict, what: String = ""): VerifiedPayload? =
        (verdict as? PublicSignVerifier.Verdict.Ok)?.payload ?: kotlin.test.fail("$what: $verdict")

    private fun refused(verdict: PublicSignVerifier.Verdict, reason: PublicSignVerifier.Reason = PublicSignVerifier.Reason.INTEGRITY): String {
        val r = assertIs<PublicSignVerifier.Verdict.Refused>(verdict, "expected a refusal")
        assertEquals(reason, r.reason, r.detail)
        return r.detail
    }

    private fun post(id: String, response: PublicResponseQr = SigningVectors.response(id), result: PublicSignResult = SigningVectors.finalResult(id)) =
        PublicSignVerifier.post(SigningVectors.request(id), SigningVectors.plan(id), ok(pre(id)), result, response)

    @Test fun `every answered vector flow passes the pre and post checks`() {
        val kinds = HashMap<String, Int>()
        for (id in SigningVectors.answeredFlows) {
            val payload = ok(pre(id), id)!!
            kinds.merge(payload.javaClass.simpleName, 1, Int::plus)
            val verdict = post(id)
            assertTrue(verdict is PublicSignVerifier.Verdict.Ok, "$id: $verdict")
        }
        assertEquals(
            setOf("EvmTransaction", "EvmPersonal", "EvmTypedData", "TronTransaction", "TronMessage", "SolanaTransaction", "SolanaMessage", "BitcoinPsbt"),
            kinds.keys,
            "$kinds",
        )
    }

    @Test fun `pre - the EVM digest is keccak of the signed bytes and the chain id is the reviewed network's`() {
        val id = "T8-flow-evm-eip1559"
        val tx = assertIs<VerifiedPayload.EvmTransaction>(ok(pre(id))).tx
        assertEquals(1L, tx.chainId)
        assertEquals(SigningVectors.plan(id).signingBytesDigest, Hex.encode(tx.signingHash))
        // A plan whose digest (and every task's) is not the bytes' (the engine would sign something else).
        refused(pre(id, plan = PublicPlan.fromEngine(withDigest(SigningVectors.planJson(id), "00".repeat(32)))))
        // The review shows another network than the signed bytes carry.
        val plan = SigningVectors.plan(id)
        refused(PublicSignVerifier.pre(SigningVectors.request(id), plan, "56"), PublicSignVerifier.Reason.CHAIN_MISMATCH)
        // The engine's request differs from the QR bytes it claims to come from.
        val request = SigningVectors.request(id)
        val swapped = JsonObject(request + ("transaction" to JsonPrimitive("0x02e70180843b9aca0084773594008252089422222222222222222222222222222222222222220280c0")))
        refused(pre(id, request = swapped))
        // No transport: never a QR request.
        refused(pre(id, request = JsonObject(request - "transport")))
    }

    @Test fun `pre - personal_sign, typed data, TRON and Solana digests`() {
        assertIs<VerifiedPayload.EvmPersonal>(ok(pre("T8-flow-evm-personal")))
        val typed = assertIs<VerifiedPayload.EvmTypedData>(ok(pre("T8-flow-evm-typed-data")))
        assertTrue(typed.hasDomainChainId)
        val noChain = assertIs<VerifiedPayload.EvmTypedData>(ok(pre("O-EVM-5-permit2-no-chain-id")))
        assertTrue(!noChain.hasDomainChainId)
        val tron = assertIs<VerifiedPayload.TronTransaction>(ok(pre("T8-flow-tron-trx-transfer")))
        assertEquals("41c8599111f29c1e1e061265b4af93ea1f274ad78a", tron.ownerHex41)
        assertIs<VerifiedPayload.TronMessage>(ok(pre("T8-flow-tron-message")))
        val sol = assertIs<VerifiedPayload.SolanaTransaction>(ok(pre("T8-flow-solana-transfer")))
        assertEquals(0, sol.signerSlot)
        assertIs<VerifiedPayload.SolanaMessage>(ok(pre("T8-flow-solana-message")))
        // Every one refuses a plan that does not commit to its bytes.
        for (id in listOf("T8-flow-evm-personal", "T8-flow-tron-trx-transfer", "T8-flow-tron-message", "T8-flow-solana-transfer", "T8-flow-solana-message", "T8-flow-bitcoin-crypto-psbt")) {
            refused(pre(id, plan = PublicPlan.fromEngine(withDigest(SigningVectors.planJson(id), "11".repeat(32)))))
        }
    }

    @Test fun `pre - the request id to echo is the one of the QR bytes (O-RESP-1)`() {
        for (id in listOf("O-RESP-1-imtoken-36-byte-id", "T8-flow-tron-trx-transfer", "T8-flow-solana-transfer", "T8-flow-evm-personal-without-request-id")) {
            ok(pre(id), id)
        }
        val id = "O-RESP-1-imtoken-36-byte-id"
        val request = SigningVectors.request(id)
        val transport = request.obj("transport")!!
        val original = transport.str("requestId")!!
        assertEquals(72, original.length, "imToken's 36-byte id")
        fun withId(value: String?): JsonObject {
            val t = if (value == null) JsonObject(transport - "requestId") else JsonObject(transport + ("requestId" to JsonPrimitive(value)))
            return JsonObject(request + ("transport" to t))
        }
        // The 37th byte (or any other) differs from the scanned QR's: the echo would not be bound to what was scanned.
        assertEquals("request.requestId", refused(pre(id, request = withId(original + "00"))))
        assertEquals("request.requestId", refused(pre(id, request = withId("ff" + original.substring(2)))))
        // Dropped from the engine's request although the QR has one, or added although it has none.
        assertEquals("request.requestId", refused(pre(id, request = withId(null))))
        val none = "T8-flow-evm-personal-without-request-id"
        val noneRequest = SigningVectors.request(none)
        val added = JsonObject(noneRequest + ("transport" to JsonObject(noneRequest.obj("transport")!! + ("requestId" to JsonPrimitive("00".repeat(16))))))
        assertEquals("request.requestId", refused(pre(none, request = added)))
    }

    @Test fun `pre - a Solana lookup table is its own refusal`() {
        // The engine refuses it at review; Kotlin refuses it too if it ever reached a plan.
        val request = SigningVectors.steps("O-SOL-2-lookup-table", "resolveSigningPlan").single().request.obj("request")!!
        val plan = PublicPlan.fromEngine(withDigest(SigningVectors.planJson("T8-flow-solana-transfer"), Hex.encode(io.ownbit.core.crypto.hash.Hashes.sha256(Base64.getDecoder().decode(request.str("message"))))))
        val solanaRequest = JsonObject(request)
        refused(PublicSignVerifier.pre(solanaRequest, plan, null), PublicSignVerifier.Reason.LOOKUP_TABLE)
    }

    @Test fun `post - another request id, an extra key, a missing id or a foreign signature are refused`() {
        val id = "T8-flow-evm-eip1559"
        val requestId = SigningVectors.request(id).obj("transport")!!.str("requestId")!!
        val signature = Hex.decode(SigningVectors.finalResult(id).raw.str("qrSignature")!!)
        fun answer(frame: String) = PublicResponseQr("eth-signature", listOf(frame), null)
        assertIs<PublicSignVerifier.Verdict.Ok>(post(id, answer(TestUr.signature("eth-signature", requestId, signature))))
        refused(post(id, answer(TestUr.signature("eth-signature", "00" + requestId.substring(2), signature))), PublicSignVerifier.Reason.VERIFY)
        refused(post(id, answer(TestUr.signature("eth-signature", null, signature))), PublicSignVerifier.Reason.VERIFY)
        refused(post(id, answer(TestUr.signature("eth-signature", requestId, signature, mapOf(3L to "origin")))), PublicSignVerifier.Reason.VERIFY)
        refused(post(id, answer(TestUr.signature("sol-signature", requestId, signature))), PublicSignVerifier.Reason.VERIFY)
        // The engine's result and the QR disagree, or the QR carries a signature of another key / with a wrong v.
        val flipped = signature.copyOf().also { it[10] = (it[10].toInt() xor 1).toByte() }
        val forged = SigningVectors.finalResult(id).let { r -> PublicSignResult.fromEngine(JsonObject(r.raw + ("qrSignature" to JsonPrimitive(Hex.encode(flipped))))) }
        refused(post(id, answer(TestUr.signature("eth-signature", requestId, flipped))), PublicSignVerifier.Reason.VERIFY)
        refused(post(id, answer(TestUr.signature("eth-signature", requestId, flipped)), forged), PublicSignVerifier.Reason.VERIFY)
        val wrongV = signature.copyOf().also { it[64] = 1 }
        val wrongVResult = SigningVectors.finalResult(id).let { r -> PublicSignResult.fromEngine(JsonObject(r.raw + ("qrSignature" to JsonPrimitive(Hex.encode(wrongV))))) }
        refused(post(id, answer(TestUr.signature("eth-signature", requestId, wrongV)), wrongVResult), PublicSignVerifier.Reason.VERIFY)
    }

    @Test fun `post - a Solana answer with a 15-byte id, or a TRON signature of another key`() {
        val sol = "T8-flow-solana-transfer"
        val solSig = Hex.decode(SigningVectors.finalResult(sol).raw.str("signature")!!)
        val solId = SigningVectors.request(sol).obj("transport")!!.str("requestId")!!
        refused(post(sol, PublicResponseQr("sol-signature", listOf(TestUr.signature("sol-signature", solId.substring(2), solSig)), null)), PublicSignVerifier.Reason.VERIFY)
        val tron = "T8-flow-tron-trx-transfer"
        val tronSig = Hex.decode(SigningVectors.finalResult(tron).raw.str("signature")!!)
        val other = tronSig.copyOf().also { it[64] = (1 - it[64]).toByte() } // the other recovery id: another key
        val otherResult = SigningVectors.finalResult(tron).let { r -> PublicSignResult.fromEngine(JsonObject(r.raw + ("signature" to JsonPrimitive(Hex.encode(other))))) }
        val tronId = SigningVectors.request(tron).obj("transport")!!.str("requestId")!!
        refused(post(tron, PublicResponseQr("tron-signature", listOf(TestUr.signature("tron-signature", tronId, other)), null), otherResult), PublicSignVerifier.Reason.VERIFY)
    }

    @Test fun `post - a PSBT answer must be the result and differ only by the task signatures`() {
        val id = "T8-flow-bitcoin-crypto-psbt"
        val result = SigningVectors.finalResult(id)
        val signed = Base64.getDecoder().decode(result.raw.str("psbt"))
        fun answer(bytes: ByteArray) = PublicResponseQr("crypto-psbt", listOf(TestUr.single("crypto-psbt", TestUr.cbor(bytes))), null)
        assertIs<PublicSignVerifier.Verdict.Ok>(post(id, answer(signed)))
        // The QR is not the engine's result.
        val request = Base64.getDecoder().decode(SigningVectors.request(id).str("psbt"))
        refused(post(id, answer(request)), PublicSignVerifier.Reason.VERIFY)
        // Result and QR agree but the PSBT changed beyond signatures (an output value).
        val tampered = signed.copyOf().also { bytes -> bytes[indexOfOutputValue(bytes)] = (bytes[indexOfOutputValue(bytes)] + 1).toByte() }
        val tamperedResult = PublicSignResult.fromEngine(JsonObject(result.raw + ("psbt" to JsonPrimitive(Base64.getEncoder().encodeToString(tampered)))))
        refused(post(id, answer(tampered), tamperedResult), PublicSignVerifier.Reason.VERIFY)
        // Another transport than the request's.
        refused(post(id, PublicResponseQr("psbt-base64", listOf(Base64.getEncoder().encodeToString(signed)), null)), PublicSignVerifier.Reason.VERIFY)
    }

    @Test fun `post - the result must belong to the plan, every task in order`() {
        val id = "T8-flow-psbt-two-wallets"
        assertIs<PublicSignVerifier.Verdict.Ok>(post(id))
        // Only the first task's result as if it were final.
        val first = PublicSignResult.fromEngine(SigningVectors.signResults(id).first())
        refused(post(id, result = first), PublicSignVerifier.Reason.VERIFY)
        val otherPlan = SigningVectors.finalResult(id).let { r -> PublicSignResult.fromEngine(JsonObject(r.raw + ("planHash" to JsonPrimitive("ab".repeat(32))))) }
        refused(post(id, result = otherPlan), PublicSignVerifier.Reason.VERIFY)
    }

    // ---- helpers ------------------------------------------------------------------------------------------------

    /** A plan JSON whose `signingBytesDigest` (and every task's) is [digest]. */
    private fun withDigest(plan: JsonObject, digest: String): JsonObject {
        val tasks = JsonArray((plan["tasks"] as JsonArray).map { JsonObject((it as JsonObject) + ("signingBytesDigest" to JsonPrimitive(digest))) })
        return JsonObject(plan + ("signingBytesDigest" to JsonPrimitive(digest)) + ("tasks" to tasks))
    }

    /** The first byte of the first output amount of a v0 PSBT's global unsigned transaction. */
    private fun indexOfOutputValue(psbt: ByteArray): Int {
        // magic(5) key-len(1)=01 key(1)=00 value-len(compact) tx: version(4) n-in(1) [36 + 1 + 4] n-out(1) value…
        var at = 7
        val first = psbt[at].toInt() and 0xff
        at += if (first < 0xfd) 1 else 3
        val nIn = psbt[at + 4].toInt()
        return at + 4 + 1 + nIn * (36 + 1 + 4) + 1
    }
}
