// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.wallet

/**
 * Outcome of a vault operation. Never thrown across the module boundary: every public `suspend` function returns one
 * of these (coroutine cancellation still propagates).
 */
sealed interface WalletResult<out T> {
    /** The operation succeeded. */
    data class Ok<T>(val value: T) : WalletResult<T>

    /** The operation failed; nothing was persisted unless the error says otherwise. */
    data class Err(val error: WalletError) : WalletResult<Nothing>
}

/** `value` for [WalletResult.Ok], `null` otherwise. */
fun <T> WalletResult<T>.getOrNull(): T? = (this as? WalletResult.Ok)?.value

/** `error` for [WalletResult.Err], `null` otherwise. */
fun <T> WalletResult<T>.errorOrNull(): WalletError? = (this as? WalletResult.Err)?.error

/**
 * Why a vault operation failed. Errors never contain secrets. (The app's `WalletError` has many more cases for the
 * wallet lifecycle — registration, coins, quotas — which are not part of this repository.)
 */
sealed interface WalletError {
    /**
     * The wallet password did not open the wallet's envelopes. [attempts] = consecutive wrong attempts for this
     * wallet in this process; when [suggestReimport] is true the UI suggests re-importing the recovery phrase.
     */
    data class WrongPassword(val attempts: Int, val suggestReimport: Boolean) : WalletError

    /** Watch / multisig-watch wallets hold no secret (use the cold wallet instead). */
    data object NoSecret : WalletError

    /**
     * The envelopes exist but can no longer be opened on this device (device key missing / replaced, corrupt
     * envelope, failed integrity hash): not a password problem — the user must re-import the recovery phrase.
     */
    data class SecretUnavailable(val cause: Throwable?) : WalletError

    /** Empty password input (never counted as a wrong attempt). */
    data object EmptyPassword : WalletError

    /** New password and confirmation differ. */
    data object PasswordMismatch : WalletError

    /** New password equals the old one. */
    data object SameAsOldPassword : WalletError

    /** The wallet does not exist (deleted meanwhile). */
    data class WalletNotFound(val walletId: String) : WalletError

    /** The operation does not apply to this wallet kind / state; [reason] is diagnostic, not user text. */
    data class NotSupported(val reason: String) : WalletError

    /** Persisting failed (storage / envelope self-check); nothing was written. */
    data class Storage(val cause: Throwable?) : WalletError
}
