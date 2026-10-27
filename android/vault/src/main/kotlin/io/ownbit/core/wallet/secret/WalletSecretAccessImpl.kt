// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.wallet.secret

import io.ownbit.core.wallet.api.UnlockResult
import io.ownbit.core.wallet.api.UnlockedSecrets
import io.ownbit.core.wallet.api.WalletSecretAccess

/**
 * [WalletSecretAccess] over the OBV2 envelopes of a [WalletSecretStore] (iOS `WalletModel.checkPassword`,
 * `decryptMnemonic`, `decryptSeed`, `PrivateKeyWalletModel.decryptPrivateKey` / `decryptWIF`).
 *
 * - [verifyPassword] opens one envelope (mnemonic for HD wallets, private key for private-key wallets) — one
 *   scrypt, on `Dispatchers.Default` inside [io.ownbit.core.crypto.obv2.Obv2Envelope]. It does **not** count attempts
 *   (use [WalletPasswordVerifier] in UIs that must show the re-import hint).
 * - [withUnlocked] decrypts every envelope signing can need ([SecretField.SIGNING] — HD: mnemonic + seed; private
 *   key: key + WIF; never the BIP39 passphrase: the seed already includes it), concurrently, verifies them against the
 *   stored hashes, runs the block and zeroes the arrays afterwards even when the block throws (the exception is
 *   rethrown after wiping; cancellation propagates).
 */
class WalletSecretAccessImpl(
    private val vault: SecretVault,
) : WalletSecretAccess {

    override suspend fun verifyPassword(walletId: String, password: CharArray): Boolean {
        val field = vault.verificationField(walletId) ?: return false
        return when (val opened = vault.open(walletId, password, setOf(field))) {
            is SecretVault.Opened.Ok -> {
                opened.secrets.wipe()
                true
            }
            else -> false
        }
    }

    override suspend fun <T> withUnlocked(
        walletId: String,
        password: CharArray,
        block: suspend (UnlockedSecrets) -> T,
    ): UnlockResult<T> = when (val opened = vault.open(walletId, password, SecretField.SIGNING)) {
        is SecretVault.Opened.Ok -> try {
            UnlockResult.Success(block(opened.secrets))
        } finally {
            opened.secrets.wipe()
        }
        SecretVault.Opened.WrongPassword -> UnlockResult.WrongPassword
        SecretVault.Opened.NoSecret -> UnlockResult.NoSecret
        is SecretVault.Opened.Unavailable -> UnlockResult.Failed(opened.cause)
    }
}
