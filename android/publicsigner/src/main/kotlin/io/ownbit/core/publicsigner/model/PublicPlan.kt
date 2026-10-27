// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.publicsigner.model

import kotlinx.serialization.json.JsonObject

/**
 * Status of a resolved signing plan (engine `resolveSigningPlan`, `src/resolver.js`). Each one has its own page state.
 * Unknown values read as [INVALID] (fail closed).
 */
enum class PlanStatus(val wire: String) {
    /** Exactly the listed tasks can sign. */
    READY("ready"),

    /** No local wallet holds the requested key. */
    NO_MATCH("noMatch"),

    /** The request names no signer (no path / address / key / fingerprint). */
    MISSING_SIGNER("missingSigner"),

    /** More than one local wallet matches (the same phrase twice). */
    AMBIGUOUS("ambiguous"),

    /** A wallet without a public index might match: prepare it (one password) and resolve again. */
    SETUP_REQUIRED("setupRequired"),

    /** The request is malformed or unsupported. */
    INVALID("invalid"),
    ;

    companion object {
        fun fromWire(wire: String?): PlanStatus = entries.firstOrNull { it.wire == wire } ?: INVALID
    }
}

/**
 * One signing task of a ready plan: one local wallet and the keys it signs with (BitSigner `SigningTask`). A
 * multi-wallet PSBT has one task per wallet, each signed with its own password.
 *
 * @property localWalletId the Ownbit wallet id the plan was resolved with (the unlocked wallet must equal it).
 * @property walletKeyId the engine's wallet identity (64 hex); the engine re-checks it against the decrypted seed.
 * @property paths / [publicKeys] / [addresses] one entry per signing target (same order).
 * @property inputs BTC input indexes this wallet signs (empty for the other chains).
 * @property signerSlot Solana required-signer slot of the key, else `null`.
 * @property raw the task exactly as the engine produced it (part of the plan that is passed back unchanged).
 */
data class PublicTask(
    val id: String,
    val localWalletId: String,
    val walletKeyId: String,
    val chain: PsChain,
    val paths: List<String>,
    val publicKeys: List<String>,
    val addresses: List<String>,
    val inputs: List<Int>,
    val signatureAlgorithm: String,
    val signingBytesDigest: String,
    val signerSlot: Int?,
    val raw: JsonObject,
) {
    /** Distinct non-empty addresses in engine order (the signing wallet card). */
    val displayAddresses: List<String> get() = addresses.filter { it.isNotEmpty() }.distinct()

    /** Distinct non-empty paths in engine order. */
    val displayPaths: List<String> get() = paths.filter { it.isNotEmpty() }.distinct()

    companion object {
        /** Reads one engine task; fails with [MalformedEngineResultException] like BitSigner `SigningTask.init`. */
        fun fromEngine(raw: JsonObject): PublicTask {
            val id = raw.str("id")?.takeIf { it.isNotEmpty() } ?: throw MalformedEngineResultException("task.id")
            val wallet = raw.str("localWalletId")?.takeIf { it.isNotEmpty() }
                ?: throw MalformedEngineResultException("task.localWalletId")
            val keyId = raw.str("walletKeyId")?.takeIf { isHex(it, 32) } ?: throw MalformedEngineResultException("task.walletKeyId")
            val chain = PsChain.fromWire(raw.str("chain")) ?: throw MalformedEngineResultException("task.chain")
            val paths = raw.strings("paths")?.takeIf { it.isNotEmpty() } ?: throw MalformedEngineResultException("task.paths")
            val keys = raw.strings("publicKeys")?.takeIf { it.size == paths.size }
                ?: throw MalformedEngineResultException("task.publicKeys")
            val signerSlot = (raw.arr("targets")?.firstOrNull() as? JsonObject)?.int("signerSlot")
            return PublicTask(
                id = id,
                localWalletId = wallet,
                walletKeyId = keyId.lowercase(),
                chain = chain,
                paths = paths,
                publicKeys = keys,
                addresses = raw.strings("addresses").orEmpty(),
                inputs = raw.ints("inputs").orEmpty(),
                signatureAlgorithm = raw.str("signatureAlgorithm").orEmpty(),
                signingBytesDigest = raw.str("signingBytesDigest").orEmpty(),
                signerSlot = signerSlot,
                raw = raw,
            )
        }
    }
}

/**
 * A resolved signing plan (engine `resolveSigningPlan`). The plan JSON stays in memory only (never `SavedStateHandle`,
 * nav args or disk) and is passed back to `signPlanTask` as [raw], unchanged; the engine re-checks its `planHash`.
 *
 * @property message the engine's English status message for a non-ready plan (shown only in technical details).
 * @property review the engine review (present for ready plans and for most failures), the only source of review rows.
 * @property signingBytesDigest the digest the engine will sign, 64 lower-case hex, never `null` for a ready plan (Kotlin
 *   re-checks it before the password where it can).
 * @property protocolProfile the request transport (`eth-sign-request`, `crypto-psbt`, …).
 */
data class PublicPlan(
    val status: PlanStatus,
    val message: String?,
    val chain: PsChain?,
    val requestHash: String?,
    val planHash: String?,
    val payloadDigest: String?,
    val signingBytesDigest: String?,
    val protocolProfile: String?,
    val review: PublicReview?,
    val tasks: List<PublicTask>,
    val raw: JsonObject,
) {
    val isReady: Boolean get() = status == PlanStatus.READY

    /** The wallets that sign, in task order (one task per wallet). */
    val walletIds: List<String> get() = tasks.map { it.localWalletId }.distinct()

    fun task(id: String): PublicTask? = tasks.firstOrNull { it.id == id }

    companion object {
        /** Most tasks a plan may carry (BitSigner `SigningPlan`; Ownbit holds ≤ 50 wallets). */
        const val MAX_TASKS: Int = 64

        /**
         * Reads an engine plan. A `ready` plan must be complete (BitSigner `SigningPlan.init`): version 1, 64-hex request
         * and plan hashes, a known chain, a review of that chain whose request hash is the plan's, a 64-hex signing digest,
         * 1…[MAX_TASKS] well-formed tasks of the plan's chain with unique ids, each signing that digest. A non-ready plan
         * carries no tasks. Anything else fails with [MalformedEngineResultException].
         */
        fun fromEngine(raw: JsonObject): PublicPlan {
            val status = PlanStatus.fromWire(raw.str("status"))
            val review = raw.obj("review")?.let(PublicReview::fromEngine)
            val taskObjects = raw.arr("tasks") ?: throw MalformedEngineResultException("plan.tasks")
            if (status != PlanStatus.READY) {
                ensureEngine(taskObjects.isEmpty()) { "plan.tasks" }
                return PublicPlan(
                    status = status,
                    message = raw.str("message"),
                    chain = review?.chain,
                    requestHash = review?.requestHash?.takeIf { it.isNotEmpty() },
                    planHash = null,
                    payloadDigest = null,
                    signingBytesDigest = null,
                    protocolProfile = null,
                    review = review,
                    tasks = emptyList(),
                    raw = raw,
                )
            }
            ensureEngine(raw.int("version") == 1) { "plan.version" }
            val requestHash = raw.str("requestHash")?.takeIf { isHex(it, 32) } ?: throw MalformedEngineResultException("plan.requestHash")
            val planHash = raw.str("planHash")?.takeIf { isHex(it, 32) } ?: throw MalformedEngineResultException("plan.planHash")
            val chain = PsChain.fromWire(raw.str("chain")) ?: throw MalformedEngineResultException("plan.chain")
            ensureEngine(review != null && review.requestHash.equals(requestHash, ignoreCase = true)) { "plan.review" }
            // What is shown is what is signed: the review describes this plan's chain, and the plan names the exact
            // digest every task signs (Kotlin re-checks it before the password; the engine re-checks it when signing).
            ensureEngine(review?.chain == chain) { "plan.review.chain" }
            val digest = raw.str("signingBytesDigest")?.takeIf { isHex(it, 32) }
                ?: throw MalformedEngineResultException("plan.signingBytesDigest")
            ensureEngine(taskObjects.size in 1..MAX_TASKS) { "plan.tasks" }
            val tasks = taskObjects.map { PublicTask.fromEngine(it as? JsonObject ?: throw MalformedEngineResultException("plan.task")) }
            ensureEngine(tasks.map { it.id }.toSet().size == tasks.size) { "plan.task.id" }
            ensureEngine(tasks.all { it.chain == chain }) { "plan.task.chain" }
            ensureEngine(tasks.all { it.signingBytesDigest.equals(digest, ignoreCase = true) }) { "plan.task.signingBytesDigest" }
            return PublicPlan(
                status = status,
                message = null,
                chain = chain,
                requestHash = requestHash.lowercase(),
                planHash = planHash.lowercase(),
                payloadDigest = raw.str("payloadDigest"),
                signingBytesDigest = digest.lowercase(),
                protocolProfile = raw.str("protocolProfile"),
                review = review,
                tasks = tasks,
                raw = raw,
            )
        }
    }
}
