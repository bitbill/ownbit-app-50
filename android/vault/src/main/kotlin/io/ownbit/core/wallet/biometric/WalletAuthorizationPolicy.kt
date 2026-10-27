// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.wallet.biometric

import io.ownbit.core.crypto.biometric.BiometricCapabilityChecker
import io.ownbit.core.crypto.hash.Hashes
import io.ownbit.core.crypto.util.WallClock
import java.math.BigDecimal
import kotlin.math.abs

/**
 * What is being signed. [biometricAllowed] = may use biometric quick send at all; every other kind is password-only
 * (the call sites of those kinds never build an [AuthorizationRequest] anyway).
 */
enum class TxKind(val biometricAllowed: Boolean) {
    PERSONAL_SEND(true),
    MULTISIG_INITIATE(true),
    MULTISIG_APPROVE(true),
    MULTISIG_BATCH(true),
    MULTISIG_EXECUTE(true),
    MULTISIG_DEPLOY(true),
    ACCOUNT_MS_SETUP(false),
    MULTISIG_ADMIN(false),
    WALLETCONNECT(false),
    MESSAGE_SIGN(false),
    OFFLINE_SIGN(false),
    TRON_BATCH(false),
    TRON_RESOURCE(false),
    ACCELERATE(false),
    UTXO_ARRANGE(false),
    TOKEN_APPROVAL(false),
    OTHER(false),
}

/**
 * One asset leaving the wallet, in whole units of the asset (`BigDecimal`, never `Double`). Every recipient (and, in
 * the app, TRX leasing prepay and XRP-token SendMax) counts; the network fee does not unless it is what the operation
 * spends (multisig execute / deploy).
 *
 * @property chain mainnet of the asset (the app uses its coin-type name); [contract] the token contract, `null` for a
 *   mainnet coin. Only [UsdQuotes] interprets them.
 */
data class AssetOutflow(
    val chain: String,
    val symbol: String,
    val contract: String?,
    val amount: BigDecimal,
)

/** A USD price of one asset unit and when it was fetched. [isUsable] = `false` for a placeholder / zero quote. */
data class UsdQuote(val usd: BigDecimal, val updatedAtMillis: Long, val isUsable: Boolean = true)

/**
 * The prices the value rule uses (the app's price book; fetching prices is not part of this repository). `null` = no
 * price for that asset: the transaction is then treated as "large" (password required).
 */
fun interface UsdQuotes {
    fun quote(outflow: AssetOutflow): UsdQuote?
}

/**
 * A request to authorise one signing operation. [outflows] `null` = the value cannot be determined (contract calls,
 * custom hex data, unknown proposal amount) → never biometric-only. [digest] = [AuthorizationDigest.of] the content the
 * user confirmed; a changed content is a new request (new prompt).
 */
data class AuthorizationRequest(
    val walletId: String,
    val kind: TxKind,
    val outflows: List<AssetOutflow>?,
    val digest: String,
)

/** Why only the password applies. */
enum class PasswordReason { FEATURE_OFF, WALLET_OFF, KIND_NOT_ALLOWED, DEVICE_NOT_ELIGIBLE }

/** Outcome of [WalletAuthorizationPolicy.decide]. */
sealed interface AuthorizationDecision {
    /** The existing wallet-password dialog, unchanged. */
    data class PasswordOnly(val reason: PasswordReason) : AuthorizationDecision

    /** Class 3 crypto-bound prompt; its grant signs. */
    data object BiometricOnly : AuthorizationDecision

    /** Value `>=` threshold, threshold 0, no / stale price or unknown value: the prompt **then** the wallet password. */
    data object BiometricThenPassword : AuthorizationDecision
}

/**
 * The single place deciding whether a signing operation may use biometrics instead of the wallet password. Order:
 * master off / settings unreadable → wallet not enabled → kind not allowed → device no longer
 * [io.ownbit.core.crypto.biometric.BiometricCapability.STRONG_HW] (live check) → value rules ([QuickSendRules]).
 */
class WalletAuthorizationPolicy(
    private val repo: QuickSendRepository,
    private val capability: BiometricCapabilityChecker,
    private val prices: UsdQuotes,
    private val clock: WallClock,
) {

    suspend fun decide(r: AuthorizationRequest): AuthorizationDecision {
        val snapshot = repo.snapshot()
        if (snapshot.corrupt || !snapshot.file.masterOn) return AuthorizationDecision.PasswordOnly(PasswordReason.FEATURE_OFF)
        if (snapshot.file.record(r.walletId) == null) return AuthorizationDecision.PasswordOnly(PasswordReason.WALLET_OFF)
        if (!r.kind.biometricAllowed) return AuthorizationDecision.PasswordOnly(PasswordReason.KIND_NOT_ALLOWED)
        if (!capability.status().canAuthorizeTransactions) {
            return AuthorizationDecision.PasswordOnly(PasswordReason.DEVICE_NOT_ELIGIBLE)
        }
        return QuickSendRules.valueDecision(r.outflows, snapshot.file.thresholdUsd, prices, clock.nowMillis())
    }

    /**
     * Final-path check right before the signing call: [grant] still usable, for the same wallet and the same confirmed
     * content, and the request is still [AuthorizationDecision.BiometricOnly] (prices / threshold / switches re-read).
     * `false` → wipe the grant and ask for the password.
     */
    suspend fun recheck(grant: BiometricGrant, r: AuthorizationRequest): Boolean =
        grant.isUsable() &&
            grant.walletId == r.walletId &&
            grant.digest == r.digest &&
            decide(r) == AuthorizationDecision.BiometricOnly
}

/** The value rules (pure, JVM-tested). */
object QuickSendRules {

    /** A quote older than this is not a reliable price. */
    const val MAX_PRICE_AGE_MILLIS: Long = 24 * 60 * 60 * 1000L

    fun valueDecision(
        outflows: List<AssetOutflow>?,
        thresholdUsd: Long,
        prices: UsdQuotes,
        nowMillis: Long,
    ): AuthorizationDecision {
        if (outflows == null || thresholdUsd <= 0L) return AuthorizationDecision.BiometricThenPassword
        val value = usdValue(outflows, prices, nowMillis) ?: return AuthorizationDecision.BiometricThenPassword
        return if (value >= BigDecimal.valueOf(thresholdUsd)) {
            AuthorizationDecision.BiometricThenPassword
        } else {
            AuthorizationDecision.BiometricOnly
        }
    }

    /**
     * Σ amount × USD price over every outflow; `null` when any amount is negative or any non-zero outflow has no usable
     * price or only a stale one. Zero amounts move nothing and need no price.
     */
    fun usdValue(outflows: List<AssetOutflow>, prices: UsdQuotes, nowMillis: Long): BigDecimal? {
        var total = BigDecimal.ZERO
        for (o in outflows) {
            if (o.amount.signum() < 0) return null
            if (o.amount.signum() == 0) continue
            val quote = prices.quote(o) ?: return null
            if (!quote.isUsable || abs(nowMillis - quote.updatedAtMillis) > MAX_PRICE_AGE_MILLIS) return null
            total = total.add(o.amount.multiply(quote.usd))
        }
        return total
    }
}

/**
 * Canonical SHA-256 (hex) of the content the user confirmed (wallet, kind, coin, contract, recipients + amounts, fee,
 * nonce / sequence, proposal id…). Parts are length-prefixed and `"\u0000"`-joined, `null` distinct from `""`, so
 * different part lists never collide by concatenation.
 */
object AuthorizationDigest {
    fun of(vararg parts: String?): String {
        val canonical = parts.joinToString(SEPARATOR) { p -> if (p == null) NULL_PART else "${p.length}:$p" }
        return Hashes.sha256Hex(canonical)
    }

    private const val SEPARATOR = "\u0000"
    private const val NULL_PART = "-"
}
