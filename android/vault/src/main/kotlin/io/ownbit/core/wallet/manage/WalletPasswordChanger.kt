// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.wallet.manage

import io.ownbit.core.wallet.WalletError
import io.ownbit.core.wallet.WalletResult
import io.ownbit.core.wallet.biometric.QuickSendOffReason
import io.ownbit.core.wallet.biometric.QuickSendRevoker
import io.ownbit.core.wallet.secret.SecretField
import io.ownbit.core.wallet.secret.SecretSealer
import io.ownbit.core.wallet.secret.SecretVault
import io.ownbit.core.wallet.secret.WalletSecretStore
import kotlinx.coroutines.CancellationException

/**
 * "Change wallet password" (iOS `WalletModel.changePassword(oldPwd:newPwd:)`). Only for wallets with a mnemonic (not
 * watch, not private-key wallets).
 *
 * Steps (all-or-nothing):
 * 1. input checks in iOS order: empty old password, confirmation, same as old (the strength of the new password is
 *    checked by the caller before);
 * 2. decrypt mnemonic + seed (+ the BIP39 passphrase of a passphrase wallet) with the old password (wrong →
 *    [WalletError.WrongPassword] with attempt counting; a passphrase wallet whose passphrase does not open →
 *    [WalletError.SecretUnavailable], nothing written — the envelopes are replaced whole, so a missing field would be
 *    lost);
 * 3. re-encrypt each with the new password, every envelope self-checked by decrypting it with the new password and
 *    comparing to the plaintext (`Obv2Envelope.encryptVerified`);
 * 4. replace the envelopes in **one** transaction ([WalletSecretStore.replaceEnvelopes]); any failure leaves the old
 *    envelopes untouched. The plaintext never changes, so the stored hashes stay valid.
 *
 * Afterwards biometric quick send is turned off for the wallet: the password it wraps is stale (no re-wrap).
 */
class WalletPasswordChanger(
    private val store: WalletSecretStore,
    private val vault: SecretVault,
    private val sealer: SecretSealer,
    private val quickSend: QuickSendRevoker = QuickSendRevoker.NONE,
    private val now: () -> Long = System::currentTimeMillis,
) {

    /** Changes the password. The caller owns and wipes the three arrays. */
    suspend fun change(
        walletId: String,
        oldPassword: CharArray,
        newPassword: CharArray,
        confirmPassword: CharArray,
    ): WalletResult<Unit> {
        val stored = store.read(walletId) ?: return WalletResult.Err(WalletError.WalletNotFound(walletId))
        if (stored.encryptedMnemonic == null) return WalletResult.Err(WalletError.NotSupported("no mnemonic"))
        if (oldPassword.isEmpty()) return WalletResult.Err(WalletError.EmptyPassword)
        if (newPassword.isEmpty()) return WalletResult.Err(WalletError.EmptyPassword)
        if (!newPassword.contentEquals(confirmPassword)) return WalletResult.Err(WalletError.PasswordMismatch)
        if (newPassword.contentEquals(oldPassword)) return WalletResult.Err(WalletError.SameAsOldPassword)

        val hasPassphrase = stored.hasPassphrase
        val fields = if (hasPassphrase) {
            setOf(SecretField.MNEMONIC, SecretField.SEED, SecretField.PASSPHRASE)
        } else {
            setOf(SecretField.MNEMONIC, SecretField.SEED)
        }
        val result = vault.use(walletId, oldPassword, fields) { secrets ->
            val mnemonic = secrets.mnemonic ?: return@use WalletResult.Err(WalletError.NotSupported("no mnemonic"))
            val seed = secrets.seedHex ?: return@use WalletResult.Err(WalletError.NotSupported("no seed"))
            val plaintexts = mutableMapOf(SecretField.MNEMONIC to mnemonic, SecretField.SEED to seed)
            if (hasPassphrase) {
                plaintexts[SecretField.PASSPHRASE] = secrets.passphrase
                    ?: return@use WalletResult.Err(WalletError.SecretUnavailable(null))
            }
            val sealed = sealer.reseal(walletId, plaintexts, newPassword, now())
                ?: return@use WalletResult.Err(WalletError.Storage(null))
            // Invariant: the new envelopes carry the passphrase exactly when the wallet has one.
            if ((sealed.encryptedPassphrase != null) != hasPassphrase) {
                return@use WalletResult.Err(WalletError.Storage(null))
            }
            try {
                store.replaceEnvelopes(sealed)
                WalletResult.Ok(Unit)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                WalletResult.Err(WalletError.Storage(e))
            }
        }
        if (result is WalletResult.Ok) {
            quickSend.revoke(walletId, QuickSendOffReason.PASSWORD_CHANGED)
        }
        return result
    }
}
