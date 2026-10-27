// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.publicsigner.sign

import io.ownbit.core.chain.tron.TronAddressCodec
import io.ownbit.core.publicsigner.model.DecodeStatus
import io.ownbit.core.publicsigner.model.PublicPlan
import io.ownbit.core.publicsigner.model.PublicReview
import io.ownbit.core.publicsigner.model.RiskLevel
import io.ownbit.core.publicsigner.model.arr
import io.ownbit.core.publicsigner.model.str
import io.ownbit.core.publicsigner.text.EngineVocabulary
import io.ownbit.core.publicsigner.text.PublicSignError
import io.ownbit.core.publicsigner.verify.PsbtMaps
import io.ownbit.core.publicsigner.verify.VerifiedPayload
import kotlinx.serialization.json.JsonObject

/**
 * Ownbit's rules on top of the engine for a reviewed public request. Pure; [evaluate] is called once the Kotlin
 * pre-check passed, and [Result.withInsight] when the app's signature-insight reading is known.
 *
 * - **Page risk** = max(engine `riskLevel` (normal → low, warning → medium, high → high) of the review the page shows,
 *   the signature-insight card's risk, Ownbit's own warnings).
 * - **Acknowledgement** (per request, never remembered): engine `partiallyDecoded` / `opaque`, page risk ≥ high, a
 *   Solana durable nonce, a Bitcoin output to this wallet beyond index [MAX_CHANGE_INDEX]. Only then is
 *   `riskAcknowledged = true` passed to the engine (it insists itself for partial / opaque).
 * - **Hard refusals** (no acknowledgement can override): a TRON transaction whose owner is not the signing address
 *   (permission-member signing); a TronLink ownership check for another address than the signing one; a Bitcoin
 *   output the engine marked as the wallet's without a path Kotlin can read (`err.integrity`, fail closed); a Bitcoin input claiming another amount than this device already signed for the same outpoint
 *   (`err.prevoutConflict`, [SignedOutpointMemory][io.ownbit.core.publicsigner.verify.SignedOutpointMemory]).
 *   Every other hard refusal is the engine's or the verifier's.
 * - **No online rule**: the public protocol never checks or warns about connectivity.
 */
object PublicSignPolicy {

    /** Highest receive / change index Ownbit treats as an ordinary address of the wallet. */
    const val MAX_CHANGE_INDEX: Long = 999

    /** Code of the outpoint-amount conflict refusal (a Kotlin code, not an engine one). */
    const val PREVOUT_CONFLICT: String = "PREVOUT_CONFLICT"

    /** Why the per-request checkbox is required (the text depends on the reason). */
    enum class AckReason { PARTIALLY_DECODED, OPAQUE, HIGH_RISK, DURABLE_NONCE, CHANGE_BEYOND_BOUND }

    /** An Ownbit (Kotlin) warning shown with the engine's (`PublicProtocol.warn.*`). */
    data class OwnbitWarning(val kind: Kind, val res: String, val args: List<Any> = emptyList(), val risk: SignatureRisk) {
        enum class Kind { CHANGE_INDEX, DURABLE_NONCE, NO_CHAIN_ID, TOKEN_DECIMALS }
    }

    /** The policy verdict of one request. */
    data class Result(
        val engineRisk: SignatureRisk,
        val insightRisk: SignatureRisk?,
        val warnings: List<OwnbitWarning>,
        val ackReasons: Set<AckReason>,
        val refusal: PublicSignError?,
    ) {
        /** The risk shown once at the top of the page. */
        val pageRisk: SignatureRisk
            get() = (listOfNotNull(engineRisk, insightRisk) + warnings.map { it.risk }).maxBy { it.rank }

        val canSign: Boolean get() = refusal == null

        /** The checkbox above "Sign with …" is required (and Sign stays disabled until it is checked). */
        val requiresAcknowledgement: Boolean get() = canSign && ackReasons.isNotEmpty()

        /** This result with the signature-insight reading's [risk]: a high / critical reading adds [AckReason.HIGH_RISK]. */
        fun withInsight(risk: SignatureRisk?): Result {
            val reasons = if (risk != null && risk.rank >= SignatureRisk.HIGH.rank) ackReasons + AckReason.HIGH_RISK else ackReasons
            return copy(insightRisk = risk, ackReasons = reasons)
        }
    }

    /** The engine's risk level on the signature-insight scale. */
    fun engineRisk(level: RiskLevel): SignatureRisk = when (level) {
        RiskLevel.NORMAL -> SignatureRisk.LOW
        RiskLevel.WARNING -> SignatureRisk.MEDIUM
        RiskLevel.HIGH -> SignatureRisk.HIGH
    }

    /**
     * Evaluates a ready [plan] whose bytes Kotlin decoded into [verified]; [review] is the plan's review.
     * [outpointConflicts]: the Bitcoin inputs (0-based) whose claimed amount differs from one this device signed.
     * [requestOnlyReview]: the engine's review of the request alone (no verified change). With an output beyond the
     * bound ([AckReason.CHANGE_BEYOND_BOUND]) the page shows that review — every output a payment, so the Bitcoin
     * HIGH FEE rule counts that output as sent — and the engine risk (pill, [AckReason.HIGH_RISK]) is taken from it, so
     * the risk level, the HIGH FEE banner and the checkbox agree with what the page shows. The ownership proofs are
     * always read from [review].
     */
    fun evaluate(
        review: PublicReview,
        plan: PublicPlan,
        verified: VerifiedPayload,
        insightRisk: SignatureRisk? = null,
        outpointConflicts: List<Int> = emptyList(),
        requestOnlyReview: PublicReview? = null,
    ): Result {
        val reasons = LinkedHashSet<AckReason>()
        when (review.decodeStatus) {
            DecodeStatus.PARTIALLY_DECODED -> reasons += AckReason.PARTIALLY_DECODED
            DecodeStatus.OPAQUE -> reasons += AckReason.OPAQUE
            DecodeStatus.FULLY_DECODED -> Unit
        }
        val warnings = ArrayList<OwnbitWarning>()
        var refusal: PublicSignError? = null
        when (verified) {
            is VerifiedPayload.BitcoinPsbt -> {
                val beyond = changeBeyondBound(review, plan, verified.maps)
                if (outpointConflicts.isNotEmpty()) {
                    refusal = PublicSignError(
                        "publicprotocol_err_prevoutconflict",
                        args = listOf(outpointConflicts.min() + 1),
                        code = PREVOUT_CONFLICT,
                    )
                } else if (beyond == null) {
                    refusal = PublicSignError("publicprotocol_err_integrity", code = "CHANGE_PATH")
                } else {
                    if (beyond.isNotEmpty()) reasons += AckReason.CHANGE_BEYOND_BOUND
                    warnings += beyond
                }
            }
            is VerifiedPayload.SolanaTransaction -> if (verified.header.usesDurableNonce) {
                // The consent is Ownbit's rule either way. The text: the engine says it too (shown with the same
                // `warn.durableNonce` string through the vocabulary alias); Ownbit's copy only when the engine did not.
                reasons += AckReason.DURABLE_NONCE
                if (!engineSaid(review, EngineVocabulary.DURABLE_NONCE_ID)) {
                    warnings += OwnbitWarning(OwnbitWarning.Kind.DURABLE_NONCE, "publicprotocol_warn_durablenonce", risk = SignatureRisk.MEDIUM)
                }
            }
            is VerifiedPayload.EvmTypedData -> {
                // The engine says it too (`typedDataAnyChain`, localized); Ownbit's text only when the engine did not.
                if (!verified.hasDomainChainId && !engineSaid(review, EngineVocabulary.TYPED_DATA_ANY_CHAIN_ID)) {
                    warnings += OwnbitWarning(OwnbitWarning.Kind.NO_CHAIN_ID, "publicprotocol_warn_nochainid", risk = SignatureRisk.MEDIUM)
                }
            }
            is VerifiedPayload.TronTransaction -> refusal = tronOwnerRefusal(verified, plan)
            is VerifiedPayload.TronOwnershipProof -> {
                // The placeholder proves the request's address: it must be the key that signs it (the engine checks it
                // too). Not a transaction, no risk, no checkbox.
                val signer = plan.tasks.singleOrNull()?.addresses?.firstOrNull()?.let(TronAddressCodec::toHex41)
                if (signer == null || signer != verified.ownerHex41) {
                    refusal = PublicSignError("publicprotocol_err_integrity", code = "TRON_PROOF_SIGNER")
                }
            }
            else -> Unit
        }
        val shown = requestOnlyReview?.takeIf { AckReason.CHANGE_BEYOND_BOUND in reasons } ?: review
        val engine = engineRisk(shown.riskLevel)
        if (engine.rank >= SignatureRisk.HIGH.rank) reasons += AckReason.HIGH_RISK
        return Result(engine, null, warnings, reasons, refusal).withInsight(insightRisk)
    }

    /**
     * the contract's owner must be the signing address; otherwise this is a permission-member signature,
     * refused in 5.0.x (`err.tronOwner` with the owner's address).
     */
    internal fun tronOwnerRefusal(verified: VerifiedPayload.TronTransaction, plan: PublicPlan): PublicSignError? {
        val signer = plan.tasks.singleOrNull()?.addresses?.firstOrNull()?.let(TronAddressCodec::toHex41)
        if (signer != null && signer == verified.ownerHex41) return null
        val owner = TronAddressCodec.toBase58(verified.ownerHex41) ?: verified.ownerHex41
        return PublicSignError("publicprotocol_err_tronowner", args = listOf(owner), code = "TRON_OWNER")
    }

    /**
     * outputs the engine proved to return to the signing wallet (its review adds `Output N ownership`, whose
     * value ends with the proven path: `… public key, m/84'/0'/0'/1/i)`) at a single-sig path
     * `m/{44,49,84,86}'/0'/0'/{0,1}/i` with `i > 999`. They are still the wallet's, but no wallet scans that far:
     * warning + acknowledgement. The paths checked for each such output: the engine's proven path and every PSBT
     * derivation of that output for a task wallet's fingerprint — so a derivation Kotlin does not read (or reads
     * differently) can never hide an output beyond the bound. `null` = the engine marked an output as the wallet's but
     * neither its proof nor the PSBT gives a path Kotlin can read (fail closed: the request is refused).
     */
    internal fun changeBeyondBound(review: PublicReview, plan: PublicPlan, maps: PsbtMaps): List<OwnbitWarning>? {
        val fingerprints = plan.tasks.flatMap { task -> targetFingerprints(task.raw) }.toSet()
        val derivations = maps.outputDerivations().filter { it.fingerprint.lowercase() in fingerprints }
        val owned = review.fields.mapNotNull { field ->
            OWNERSHIP.matchEntire(field.label)?.groupValues?.get(1)?.toIntOrNull()?.let { it to field.value }
        }.distinctBy { it.first }
        val warnings = ArrayList<OwnbitWarning>()
        for ((number, proof) in owned) {
            val paths = listOfNotNull(provenPath(proof)) + derivations.filter { it.outputIndex + 1 == number }.map { it.path }
            if (paths.isEmpty()) return null
            val beyond = paths.firstOrNull(::beyondBound) ?: continue
            warnings += OwnbitWarning(
                OwnbitWarning.Kind.CHANGE_INDEX,
                "publicprotocol_warn_changeindex",
                args = listOf(number, beyond.last().toString()),
                risk = SignatureRisk.HIGH,
            )
        }
        return warnings
    }

    /**
     * The path at the end of the engine's ownership proof (`Returns to the signing wallet (verified from its public
     * key, m/84'/0'/0'/1/5)`), as BIP-32 indexes (hardened ones with [PsbtMaps.HARDENED]); `null` when it ends otherwise.
     */
    internal fun provenPath(proof: String): List<Long>? {
        val text = PROVEN_PATH.find(proof)?.groupValues?.get(1) ?: return null
        return text.removePrefix("m/").split('/').map { part ->
            val hardened = part.endsWith("'")
            val index = part.removeSuffix("'").toLongOrNull()?.takeIf { it in 0 until PsbtMaps.HARDENED } ?: return null
            if (hardened) index or PsbtMaps.HARDENED else index
        }
    }

    /** A single-sig receive / change path of account 0 whose address index is above [MAX_CHANGE_INDEX]. */
    internal fun beyondBound(path: List<Long>): Boolean {
        if (path.size != 5) return false
        val (purpose, coin, account, branch, index) = path
        val single = purpose in SINGLE_SIG_PURPOSES && coin == PsbtMaps.HARDENED && account == PsbtMaps.HARDENED
        return single && (branch == 0L || branch == 1L) && index < PsbtMaps.HARDENED && index > MAX_CHANGE_INDEX
    }

    /** The engine's review already carries the warning with vocabulary id [id] (localized on the page). */
    private fun engineSaid(review: PublicReview, id: String): Boolean = review.warnings.any { EngineVocabulary.warning(it)?.id == id }

    private fun targetFingerprints(task: JsonObject): List<String> =
        task.arr("targets")?.mapNotNull { (it as? JsonObject)?.str("masterFingerprint")?.lowercase() }.orEmpty()

    private val SINGLE_SIG_PURPOSES = listOf(44L, 49L, 84L, 86L).map { it or PsbtMaps.HARDENED }.toSet()
    private val OWNERSHIP = Regex("^Output ([0-9]+) ownership$")
    private val PROVEN_PATH = Regex(", (m(?:/[0-9]{1,10}'?){1,10})\\)$")
}
