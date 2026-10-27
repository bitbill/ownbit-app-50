// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.publicsigner.sign

import io.ownbit.core.publicsigner.model.DecodeStatus
import io.ownbit.core.publicsigner.model.PublicReview
import io.ownbit.core.publicsigner.model.RiskLevel
import io.ownbit.core.publicsigner.sign.PublicSignPolicy.AckReason
import io.ownbit.core.publicsigner.testing.SigningVectors
import io.ownbit.core.publicsigner.text.EngineVocabulary
import io.ownbit.core.publicsigner.verify.PsbtMaps
import io.ownbit.core.publicsigner.verify.PublicSignVerifier
import io.ownbit.core.publicsigner.verify.VerifiedPayload
import io.ownbit.core.publicsigner.sign.SignatureRisk
import org.junit.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * [PublicSignPolicy] on the golden vectors: risk
 * merge, acknowledgement reasons, hard refusals that no checkbox lifts, and no online rule at all.
 */
class PublicSignPolicyTest {

    private fun evaluate(id: String, insight: SignatureRisk? = null): PublicSignPolicy.Result {
        val plan = SigningVectors.plan(id)
        val verified = assertIs<PublicSignVerifier.Verdict.Ok>(PublicSignVerifier.pre(SigningVectors.request(id), plan, plan.review?.network?.chainId)).payload!!
        return PublicSignPolicy.evaluate(plan.review!!, plan, verified, insight)
    }

    @Test fun `a plain transfer needs no acknowledgement`() {
        val r = evaluate("T8-flow-evm-eip1559")
        assertTrue(r.canSign)
        assertFalse(r.requiresAcknowledgement)
        assertEquals(SignatureRisk.LOW, r.pageRisk)
        assertTrue(r.warnings.isEmpty())
    }

    @Test fun `risk merge - the highest of engine, insight card and Ownbit warnings`() {
        val r = evaluate("T8-flow-evm-eip1559")
        assertEquals(SignatureRisk.MEDIUM, r.withInsight(SignatureRisk.MEDIUM).pageRisk)
        assertFalse(r.withInsight(SignatureRisk.MEDIUM).requiresAcknowledgement)
        assertEquals(SignatureRisk.CRITICAL, r.withInsight(SignatureRisk.CRITICAL).pageRisk)
        assertEquals(setOf(AckReason.HIGH_RISK), r.withInsight(SignatureRisk.HIGH).ackReasons, "a high insight reading needs consent")
        assertEquals(SignatureRisk.LOW, PublicSignPolicy.engineRisk(RiskLevel.NORMAL))
        assertEquals(SignatureRisk.MEDIUM, PublicSignPolicy.engineRisk(RiskLevel.WARNING))
        assertEquals(SignatureRisk.HIGH, PublicSignPolicy.engineRisk(RiskLevel.HIGH))
        // Engine "high" alone (unlimited approval) needs consent; the insight card cannot lower it.
        val approve = evaluate("T8-flow-evm-erc20-unlimited-approve", insight = SignatureRisk.LOW)
        assertEquals(SignatureRisk.HIGH, approve.pageRisk)
        assertEquals(setOf(AckReason.HIGH_RISK), approve.ackReasons)
    }

    @Test fun `opaque and partially decoded requests need consent with their own reason`() {
        val opaque = evaluate("O-EVM-4-personal-hash")
        assertEquals(DecodeStatus.OPAQUE, SigningVectors.plan("O-EVM-4-personal-hash").review!!.decodeStatus)
        assertEquals(setOf(AckReason.OPAQUE, AckReason.HIGH_RISK), opaque.ackReasons)
        assertTrue(opaque.requiresAcknowledgement)
        val unknown = evaluate("T8-flow-evm-unknown-contract-call")
        assertTrue(AckReason.OPAQUE in unknown.ackReasons)
        val review = SigningVectors.plan("T8-flow-evm-eip1559").review!!
        val partial = PublicSignPolicy.evaluate(review.copy(decodeStatus = DecodeStatus.PARTIALLY_DECODED), SigningVectors.plan("T8-flow-evm-eip1559"), verified("T8-flow-evm-eip1559"))
        assertEquals(setOf(AckReason.PARTIALLY_DECODED), partial.ackReasons)
    }

    @Test fun `a Solana durable nonce - consent, and the warning once (the engine's, localized)`() {
        val r = evaluate("O-SOL-1-durable-nonce")
        assertEquals(setOf(AckReason.DURABLE_NONCE), r.ackReasons)
        assertTrue(r.requiresAcknowledgement)
        // The engine says it itself; the vocabulary alias shows it with Ownbit's `warn.durableNonce` string.
        val engine = SigningVectors.plan("O-SOL-1-durable-nonce").review!!.warnings.mapNotNull(EngineVocabulary::warning)
            .single { it.id == EngineVocabulary.DURABLE_NONCE_ID }
        assertEquals("publicprotocol_warn_durablenonce", engine.res)
        assertTrue(r.warnings.none { it.kind == PublicSignPolicy.OwnbitWarning.Kind.DURABLE_NONCE }, "no duplicate of the engine warning")
        assertEquals(SignatureRisk.MEDIUM, r.pageRisk, "the engine's Solana review is a warning anyway")
        // Without the engine's text, Ownbit says it itself (and the consent stays).
        val review: PublicReview = SigningVectors.plan("O-SOL-1-durable-nonce").review!!
        val bare = PublicSignPolicy.evaluate(review.copy(warnings = emptyList()), SigningVectors.plan("O-SOL-1-durable-nonce"), verified("O-SOL-1-durable-nonce"))
        val w = bare.warnings.single()
        assertEquals(PublicSignPolicy.OwnbitWarning.Kind.DURABLE_NONCE, w.kind)
        assertEquals("publicprotocol_warn_durablenonce", w.res)
        assertEquals(setOf(AckReason.DURABLE_NONCE), bare.ackReasons)
        assertFalse(AckReason.DURABLE_NONCE in evaluate("T8-flow-solana-transfer").ackReasons)
    }

    @Test fun `change to this wallet at index 1000 is a normal output with a warning, 999 is change`() {
        val beyond = evaluate("O-BTC-3-change-1000")
        assertTrue(AckReason.CHANGE_BEYOND_BOUND in beyond.ackReasons, "${beyond.ackReasons}")
        val w = beyond.warnings.single()
        assertEquals("publicprotocol_warn_changeindex", w.res)
        assertEquals(listOf<Any>(2, "1000"), w.args, "output 2, address index 1000")
        assertEquals(SignatureRisk.HIGH, beyond.pageRisk)
        // The engine proved that output is the wallet's (`Output 2 ownership`) — the bound is Kotlin's.
        assertTrue(SigningVectors.plan("O-BTC-3-change-1000").review!!.fields.any { it.label == "Output 2 ownership" })

        val within = evaluate("O-BTC-3-change-999")
        assertFalse(AckReason.CHANGE_BEYOND_BOUND in within.ackReasons)
        assertTrue(within.warnings.isEmpty())
        // A BIP48 path is never change (the engine does not mark it; Kotlin adds nothing).
        assertTrue(evaluate("O-BTC-3-change-bip48").warnings.isEmpty())
        assertTrue(PublicSignPolicy.beyondBound(path(84, 0, 0, 1, 1000)))
        assertFalse(PublicSignPolicy.beyondBound(path(84, 0, 0, 1, 999)))
        assertFalse(PublicSignPolicy.beyondBound(path(84, 0, 1, 1, 5000)), "another account is not Ownbit's")
        assertFalse(PublicSignPolicy.beyondBound(listOf(48L or PsbtMaps.HARDENED, PsbtMaps.HARDENED, PsbtMaps.HARDENED, 2L or PsbtMaps.HARDENED, 0L, 1000L)))
    }

    @Test fun `beyond the bound the engine risk is the shown request-only review's (HIGH FEE counts that output as sent)`() {
        val plan = SigningVectors.plan("O-BTC-3-change-1000")
        val planReview = plan.review!!
        val highFee = "HIGH FEE: Fee exceeds 0.01 BTC, or exceeds half of the amount sent (and 0.0001 BTC). Verify it carefully."
        // The plan's review leaves the proven output out of the amount sent (HIGH FEE, risk high); the request-only review
        // the page shows counts it as sent (no HIGH FEE, risk warning).
        val proven = planReview.copy(riskLevel = RiskLevel.HIGH, warnings = planReview.warnings + highFee)
        val requestOnly = planReview.copy(fields = planReview.fields.filterNot { it.label.endsWith(" ownership") }, riskLevel = RiskLevel.WARNING)
        val r = PublicSignPolicy.evaluate(proven, plan, verified("O-BTC-3-change-1000"), requestOnlyReview = requestOnly)
        assertEquals(setOf(AckReason.CHANGE_BEYOND_BOUND), r.ackReasons, "no HIGH_RISK for a banner the page does not show")
        assertEquals(SignatureRisk.MEDIUM, r.engineRisk)
        assertEquals(SignatureRisk.HIGH, r.pageRisk, "the change-index warning (shown) keeps the page high")
        assertEquals(listOf<Any>(2, "1000"), r.warnings.single().args, "the bound is still read from the plan's proof")
        // The other way round: the shown review has HIGH FEE → engine risk high + HIGH_RISK.
        val shownHigh = PublicSignPolicy.evaluate(planReview, plan, verified("O-BTC-3-change-1000"), requestOnlyReview = requestOnly.copy(riskLevel = RiskLevel.HIGH, warnings = requestOnly.warnings + highFee))
        assertEquals(setOf(AckReason.CHANGE_BEYOND_BOUND, AckReason.HIGH_RISK), shownHigh.ackReasons)
        assertEquals(SignatureRisk.HIGH, shownHigh.engineRisk)
        // Within the bound the page shows the plan's review: the request-only review is ignored.
        val within = SigningVectors.plan("O-BTC-3-change-999")
        val w = PublicSignPolicy.evaluate(within.review!!.copy(riskLevel = RiskLevel.HIGH), within, verified("O-BTC-3-change-999"), requestOnlyReview = within.review!!.copy(riskLevel = RiskLevel.WARNING))
        assertEquals(SignatureRisk.HIGH, w.engineRisk)
        assertEquals(setOf(AckReason.HIGH_RISK), w.ackReasons)
    }

    @Test fun `change listed only as a Taproot derivation with 101 leaf hashes is still bound`() {
        for ((id, index) in listOf("O-BTC-3-change-taphashes" to "2147483647", "O-BTC-3-change-taproot-taphashes" to "5000")) {
            val review = SigningVectors.plan(id).review!!
            // The engine proved output 2 to be the wallet's and leaves it out of the summary.
            assertTrue(review.fields.any { it.label == "Output 2 ownership" }, id)
            assertEquals("Change returns to your wallet", review.display?.note, id)
            val r = evaluate(id)
            assertTrue(AckReason.CHANGE_BEYOND_BOUND in r.ackReasons, "$id ${r.ackReasons}")
            assertEquals(listOf<Any>(2, index), r.warnings.single().args, id)
            assertEquals(SignatureRisk.HIGH, r.pageRisk, id)
            assertTrue(r.canSign && r.requiresAcknowledgement, id)
        }
    }

    @Test fun `the engine's own proof enforces the bound, whatever Kotlin reads in the PSBT`() {
        val plan = SigningVectors.plan("O-BTC-3-change-1000")
        val review = plan.review!!
        // Maps whose outputs carry no derivation at all (another vector's PSBT): the proven path still counts.
        val bare = assertIs<VerifiedPayload.BitcoinPsbt>(verified("T8-flow-bitcoin-crypto-psbt"))
        assertTrue(bare.maps.outputDerivations().isEmpty())
        assertEquals(listOf<Any>(2, "1000"), PublicSignPolicy.changeBeyondBound(review, plan, bare.maps)!!.single().args)
        val within = SigningVectors.plan("O-BTC-3-change-999")
        assertEquals(emptyList(), PublicSignPolicy.changeBeyondBound(within.review!!, within, bare.maps))
        assertEquals(listOf(84L, 0L, 0L).map { it or PsbtMaps.HARDENED } + listOf(1L, 1000L), PublicSignPolicy.provenPath(review.fields.single { it.label == "Output 2 ownership" }.value))
        assertNull(PublicSignPolicy.provenPath("Returns to the signing wallet"))
        assertNull(PublicSignPolicy.provenPath("Returns to the signing wallet (verified from its public key, m/84'/0'/0'/1/2147483648)"))

        // An ownership proof without a readable path: the PSBT derivation still decides …
        val garbled = review.copy(fields = review.fields.map { if (it.label == "Output 2 ownership") it.copy(value = "Returns to the signing wallet") else it })
        assertEquals(listOf<Any>(2, "1000"), PublicSignPolicy.evaluate(garbled, plan, verified("O-BTC-3-change-1000")).warnings.single().args)
        // … and with no path anywhere the request is refused (fail closed), whatever the checkbox.
        val refused = PublicSignPolicy.evaluate(garbled, plan, bare)
        assertEquals("publicprotocol_err_integrity", refused.refusal?.message)
        assertFalse(refused.canSign)
        assertFalse(refused.requiresAcknowledgement)
    }

    @Test fun `TRON - the owner must be the signer, and no checkbox lifts that`() {
        assertNull(evaluate("T8-flow-tron-trc20-transfer").refusal)
        val member = evaluate("O-TRX-1-owner-not-signer")
        val refusal = assertNotNull(member.refusal)
        assertEquals("publicprotocol_err_tronowner", refusal.message)
        assertEquals(listOf("TJRabPrwbZy45sbavfcjinPJC18kjpRTv8"), refusal.args, "the contract's owner (41 5cbd…)")
        assertFalse(member.canSign)
        assertFalse(member.requiresAcknowledgement, "a hard refusal is not a consent question")
        assertFalse(member.withInsight(SignatureRisk.HIGH).canSign)
    }

    @Test fun `typed data without a chain id - the engine's warning is enough`() {
        val r = evaluate("O-EVM-5-permit2-no-chain-id")
        assertTrue(SigningVectors.plan("O-EVM-5-permit2-no-chain-id").review!!.warnings.any { EngineVocabulary.warning(it)?.id == EngineVocabulary.TYPED_DATA_ANY_CHAIN_ID })
        assertTrue(r.warnings.none { it.kind == PublicSignPolicy.OwnbitWarning.Kind.NO_CHAIN_ID }, "no duplicate of the engine warning")
        // Without the engine's text, Ownbit says it itself.
        val review: PublicReview = SigningVectors.plan("O-EVM-5-permit2-no-chain-id").review!!
        val bare = PublicSignPolicy.evaluate(review.copy(warnings = emptyList()), SigningVectors.plan("O-EVM-5-permit2-no-chain-id"), verified("O-EVM-5-permit2-no-chain-id"))
        assertEquals("publicprotocol_warn_nochainid", bare.warnings.single().res)
    }

    @Test fun `there is no online rule anywhere in the policy`() {
        val signatures = PublicSignPolicy::class.java.declaredMethods.flatMap { m -> m.parameterTypes.map { it.name } + m.name }
        assertTrue(signatures.none { "online" in it.lowercase() || "connectivity" in it.lowercase() }, "$signatures")
    }

    private fun verified(id: String): VerifiedPayload {
        val plan = SigningVectors.plan(id)
        return assertIs<PublicSignVerifier.Verdict.Ok>(PublicSignVerifier.pre(SigningVectors.request(id), plan, plan.review?.network?.chainId)).payload!!
    }

    private fun path(purpose: Long, coin: Long, account: Long, branch: Long, index: Long) =
        listOf(purpose or PsbtMaps.HARDENED, coin or PsbtMaps.HARDENED, account or PsbtMaps.HARDENED, branch, index)
}
