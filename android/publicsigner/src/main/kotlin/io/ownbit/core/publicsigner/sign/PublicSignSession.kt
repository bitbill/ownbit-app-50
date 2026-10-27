// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.publicsigner.sign

import io.ownbit.core.publicsigner.model.PsChain
import io.ownbit.core.publicsigner.model.PublicPlan
import io.ownbit.core.publicsigner.model.PublicResponseQr
import io.ownbit.core.publicsigner.model.PublicReview
import io.ownbit.core.publicsigner.model.PublicSignResult
import io.ownbit.core.publicsigner.model.PublicTask
import io.ownbit.core.publicsigner.model.obj
import io.ownbit.core.publicsigner.model.str
import io.ownbit.core.publicsigner.verify.VerifiedPayload
import kotlinx.serialization.json.JsonObject

/**
 * One reviewed, signable request (S7 `PublicSignSession`): the request exactly as the engine decoded it (passed back
 * to the engine byte for byte), the plan's review, the ready plan, what Kotlin verified on the original bytes, and the
 * signing progress. An immutable snapshot: the coordinator replaces it after each task. Memory only — never in a
 * `SavedStateHandle`, a navigation argument or on disk; nothing in it is secret (public keys, signatures, a PSBT).
 *
 * @property verified the Kotlin decode of the bytes the plan commits to ([io.ownbit.core.publicsigner.verify.PublicSignVerifier.pre]);
 *   `null` only while the session is being built.
 * @property completedTaskIds the tasks signed so far, in plan order.
 * @property lastResult the latest `signPlanTask` result (the next task's `previousResult`, the `encodeResponse` input).
 * @property response the verified answer QR once every task signed (single use).
 */
data class PublicSignSession(
    val requestId: String,
    val request: JsonObject,
    val review: PublicReview,
    val plan: PublicPlan,
    val verified: VerifiedPayload? = null,
    val completedTaskIds: List<String> = emptyList(),
    val lastResult: PublicSignResult? = null,
    val response: PublicResponseQr? = null,
) {
    val chain: PsChain? get() = plan.chain

    /** The request transport (`eth-sign-request`, `crypto-psbt`, `bbqr-psbt`, `psbt-base64`, …). */
    val transportType: String? get() = request.obj("transport")?.str("type")

    /** The next task to sign (tasks are signed in plan order), `null` when every task signed. */
    val nextTask: PublicTask? get() = plan.tasks.firstOrNull { it.id !in completedTaskIds }

    val isComplete: Boolean get() = plan.tasks.all { it.id in completedTaskIds }

    /** ids and counts only. */
    override fun toString(): String =
        "PublicSignSession($requestId, ${plan.chain?.wire}, tasks=${plan.tasks.size}, done=${completedTaskIds.size}, answered=${response != null})"
}
