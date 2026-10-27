// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.publicsigner.model

import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * State of a public scan session after a frame (engine `scanAdd` / `decodePayload`: `{complete, progress, request?}`).
 *
 * @property complete every part arrived; [request] is the decoded signing request.
 * @property progress 0…1, **display only** (fountain codes estimate it; never used for a decision).
 * @property parts distinct frames accepted so far in this session (counted by the session, shown as "%1$d parts").
 * @property request the engine's normalized request object when [complete] (an untrusted input for the next steps),
 *   else `null`.
 */
data class ScanProgress(
    val complete: Boolean,
    val progress: Float,
    val parts: Int,
    val request: JsonObject?,
) {
    init {
        require(!complete || request != null) { "A complete scan carries its request" }
        require(parts >= 0) { "Negative part count" }
    }

    /** The request's chain (`null` until complete, or for a chain this app does not know). */
    val chain: PsChain? get() = request?.let { PsChain.fromWire(it.str("chain")) }

    /** The request's transport (`eth-sign-request`, `crypto-psbt`, `bbqr-psbt`, `psbt-base64`, …), when complete. */
    val transportType: String? get() = request?.obj("transport")?.str("type")

    companion object {
        val EMPTY: ScanProgress = ScanProgress(complete = false, progress = 0f, parts = 0, request = null)

        /**
         * Reads an engine scan status. Fails with [MalformedEngineResultException] when `complete` is missing, or when a
         * complete status has no request object of a known chain.
         */
        fun fromEngine(raw: JsonObject, parts: Int): ScanProgress {
            val complete = raw.bool("complete") ?: throw MalformedEngineResultException("scan.complete")
            if (!complete) {
                val reported = (raw["progress"] as? JsonPrimitive)?.takeIf { !it.isString }?.content?.toFloatOrNull()
                val progress = if (reported == null || reported.isNaN()) 0f else reported.coerceIn(0f, 1f)
                return ScanProgress(complete = false, progress = progress, parts = parts, request = null)
            }
            val request = raw.obj("request") ?: throw MalformedEngineResultException("scan.request")
            ensureEngine(PsChain.fromWire(request.str("chain")) != null) { "scan.request.chain" }
            return ScanProgress(complete = true, progress = 1f, parts = parts, request = request)
        }
    }
}
