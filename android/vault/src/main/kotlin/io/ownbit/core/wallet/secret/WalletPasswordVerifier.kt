// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.wallet.secret

import io.ownbit.core.wallet.WalletError
import io.ownbit.core.wallet.WalletResult

/**
 * Wallet-password prompts of the UI (iOS `WalletModel.checkPassword` + the "three wrong attempts" hint): delete wallet,
 * backup, export, …
 *
 * Returns [WalletResult.Ok] for a correct password, [WalletError.WrongPassword] (with the consecutive count and
 * `suggestReimport` after 3 failures), [WalletError.NoSecret] for watch wallets or
 * [WalletError.SecretUnavailable] when the envelopes cannot be opened on this device any more. Never validates the
 * password strength (old passwords must keep working).
 */
class WalletPasswordVerifier(
    private val vault: SecretVault,
) {
    /** Checks [password] against [walletId]'s envelopes. The caller owns and wipes [password]. */
    suspend fun verify(walletId: String, password: CharArray): WalletResult<Unit> {
        val field = vault.verificationField(walletId) ?: return WalletResult.Err(WalletError.NoSecret)
        return vault.use(walletId, password, setOf(field)) { WalletResult.Ok(Unit) }
    }
}
