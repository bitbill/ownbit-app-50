// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.publicsigner.sign

import io.ownbit.core.publicsigner.scan.TronLinkRequest
import io.ownbit.core.publicsigner.testing.OtherWalletVectors
import io.ownbit.core.publicsigner.testing.SigningVectors
import io.ownbit.core.publicsigner.verify.PublicSignVerifier
import io.ownbit.core.publicsigner.verify.VerifiedPayload
import io.ownbit.core.scanner.publicqr.TronLinkQrFormat
import org.junit.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Round-2 rules of [PublicSignPolicy]: the outpoint-amount conflict and TronLink's ownership check. */
class PublicSignPolicyRound2Test {

    @Test fun `an outpoint amount conflict is a hard refusal no checkbox can override`() {
        val id = "O-BTC-6-segwit-witness-only"
        val s = SigningVectors.session(id)
        val verified = assertIs<VerifiedPayload.BitcoinPsbt>(assertIs<PublicSignVerifier.Verdict.Ok>(PublicSignVerifier.pre(s)).payload)
        assertEquals(listOf(0), verified.witnessOnlyInputs)
        val ok = PublicSignPolicy.evaluate(s.review, s.plan, verified)
        assertTrue(ok.canSign)
        assertFalse(ok.requiresAcknowledgement, "a warning only, no checkbox for witness-only amounts")
        val conflict = PublicSignPolicy.evaluate(s.review, s.plan, verified, outpointConflicts = listOf(0))
        assertFalse(conflict.canSign)
        assertFalse(conflict.requiresAcknowledgement)
        assertEquals(PublicSignPolicy.PREVOUT_CONFLICT, conflict.refusal?.code)
        assertEquals("publicprotocol_err_prevoutconflict", conflict.refusal?.message)
        assertEquals(listOf<Any>(1), conflict.refusal?.args, "the 1-based input number, an Int for %1\$d")
    }

    @Test fun `TronLink's ownership check is signed without a checkbox, only by the address it proves`() {
        val id = "O-TL-V1-ownership-ios"
        val plan = SigningVectors.plan(id)
        val request = TronLinkRequestMapper.map(TronLinkRequest.of(TronLinkQrFormat.parse(OtherWalletVectors.V1_REQUEST)!!))
        val s = PublicSignSession("r", request, plan.review!!, plan)
        val proof = assertIs<VerifiedPayload.TronOwnershipProof>(assertIs<PublicSignVerifier.Verdict.Ok>(PublicSignVerifier.pre(s)).payload)
        val result = PublicSignPolicy.evaluate(plan.review!!, plan, proof)
        assertNull(result.refusal)
        assertFalse(result.requiresAcknowledgement)
        val other = VerifiedPayload.TronOwnershipProof(proof.raw, proof.name, "41" + "00".repeat(20), proof.txProto)
        assertEquals("TRON_PROOF_SIGNER", PublicSignPolicy.evaluate(plan.review!!, plan, other).refusal?.code)
    }
}
