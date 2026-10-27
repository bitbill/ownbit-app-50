// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.publicsigner.model

import kotlinx.serialization.json.JsonObject

/**
 * The result of one `signPlanTask` call. [raw] is kept whole: it is the `previousResult` of the next task of a
 * multi-wallet PSBT and the `result` of `encodeResponse`. It holds only public data (a PSBT with partial signatures, a
 * signature) — never key material.
 *
 * @property completedTaskIds every task signed so far in this plan, this one last.
 */
data class PublicSignResult(
    val chain: PsChain,
    val requestHash: String,
    val planHash: String,
    val taskId: String,
    val completedTaskIds: List<String>,
    val raw: JsonObject,
) {
    companion object {
        /**
         * Reads a `signPlanTask` result; fails with [MalformedEngineResultException] unless it names a known chain, 64-hex
         * request / plan hashes, its task, and lists that task last in `completedTaskIds`. Whether it belongs to the
         * reviewed plan is the verifier's check.
         */
        fun fromEngine(raw: JsonObject): PublicSignResult {
            val chain = PsChain.fromWire(raw.str("chain")) ?: throw MalformedEngineResultException("result.chain")
            val requestHash = raw.str("requestHash")?.takeIf { isHex(it, 32) } ?: throw MalformedEngineResultException("result.requestHash")
            val planHash = raw.str("planHash")?.takeIf { isHex(it, 32) } ?: throw MalformedEngineResultException("result.planHash")
            val taskId = raw.str("taskId")?.takeIf { it.isNotEmpty() } ?: throw MalformedEngineResultException("result.taskId")
            val completed = raw.strings("completedTaskIds") ?: throw MalformedEngineResultException("result.completedTaskIds")
            ensureEngine(completed.lastOrNull() == taskId) { "result.completedTaskIds" }
            return PublicSignResult(chain, requestHash.lowercase(), planHash.lowercase(), taskId, completed, raw)
        }
    }
}

/**
 * The answer QR, in the request's own transport (engine `encodeResponse`): `crypto-psbt` / `psbt` / BBQr / static PSBT
 * text for Bitcoin, `eth-signature` / `sol-signature` / `tron-signature` otherwise; built by Kotlin:
 * `tronlink` (TronLink's JSON, numbered static parts above 1000 characters). Nothing here is broadcast: the other
 * wallet finalizes and broadcasts.
 *
 * @property type the transport (`eth-signature`, `crypto-psbt`, `bbqr-psbt`, `psbt-base64`, `tronlink` …).
 * @property frames QR frames; more than one → animated (250 ms per frame), except TronLink's numbered parts
 *   ([isPaged]: a pager, TronLink reads them strictly in order).
 * @property payload the decoded payload view, `null` when the engine sent none.
 * @property signedTransaction the code carries the whole signed transaction (TronLink), not only a
 *   signature (`result.signedTransaction` instead of `result.signatureOnly`).
 */
data class PublicResponseQr(
    val type: String,
    val frames: List<String>,
    val payload: PublicPayloadView?,
    val signedTransaction: Boolean = false,
) {
    init {
        require(frames.isNotEmpty()) { "A response QR has at least one frame" }
    }

    /** A TronLink answer (`result.tronlinkScanBack`). */
    val isTronLink: Boolean get() = type == TRONLINK

    /** TronLink numbered parts: shown one at a time with Previous / Next code, never animated. */
    val isPaged: Boolean get() = isTronLink && frames.size > 1

    val isAnimated: Boolean get() = frames.size > 1 && !isPaged

    /** A signed PSBT (partial signatures only). */
    val isPsbt: Boolean get() = type in PSBT_TYPES

    /** What "Copy" copies: the single frame, or every frame on its own line. */
    val text: String get() = frames.joinToString("\n")

    companion object {
        private val PSBT_TYPES = setOf("crypto-psbt", "psbt", "bbqr-psbt", "psbt-base64", "psbt-hex")

        /** The Kotlin-built answer type. */
        const val TRONLINK: String = "tronlink"

        /** Reads an `encodeResponse` result; fails with [MalformedEngineResultException] without a type or frames. */
        fun fromEngine(raw: JsonObject): PublicResponseQr {
            val type = raw.str("type")?.takeIf { it.isNotEmpty() } ?: throw MalformedEngineResultException("response.type")
            val frames = raw.strings("frames")?.filter { it.isNotEmpty() }.orEmpty()
            ensureEngine(frames.isNotEmpty()) { "response.frames" }
            return PublicResponseQr(type = type, frames = frames, payload = PublicPayloadView.fromEngine(raw))
        }
    }
}
