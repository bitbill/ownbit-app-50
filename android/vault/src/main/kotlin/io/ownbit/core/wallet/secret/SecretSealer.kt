// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.wallet.secret

import io.ownbit.core.crypto.obv2.Obv2Envelope
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope

/**
 * Seals wallet secrets into self-checked `OBV2:` envelopes (iOS `WalletSecretCipher.reencryptToV2`: encrypt, then
 * decrypt with the same password and compare — an envelope that does not open is never returned). The envelopes of a
 * wallet are sealed concurrently ([io.ownbit.core.crypto.kdf.Scrypt] bounds scrypt concurrency), each with its own
 * random salt and nonce.
 */
class SecretSealer(private val obv2: Obv2Envelope) {

    /**
     * HD wallets: mnemonic + BIP39 seed hex, plus the BIP39 [passphrase] of a passphrase import (sealed exactly like the
     * mnemonic; `null` = none, no envelope). `null` when any self-check failed. The caller owns the arrays.
     */
    suspend fun sealHd(
        walletId: String,
        mnemonic: CharArray,
        seedHex: String,
        password: CharArray,
        now: Long,
        passphrase: CharArray? = null,
    ): SealedSecrets? = coroutineScope {
        val m = async { obv2.encryptVerified(mnemonic, password) }
        val s = async { obv2.encryptVerified(seedHex, password) }
        val p = passphrase?.let { async { obv2.encryptVerified(it, password) } }
        val mnemonicEnvelope = m.await()
        val seedEnvelope = s.await()
        val passphraseEnvelope = p?.await()
        if (mnemonicEnvelope == null || seedEnvelope == null || (passphrase != null && passphraseEnvelope == null)) {
            null
        } else {
            SealedSecrets(
                walletId,
                encryptedMnemonic = mnemonicEnvelope,
                encryptedSeed = seedEnvelope,
                encryptedPassphrase = passphraseEnvelope,
                updatedAt = now,
            )
        }
    }

    /**
     * Private-key wallets (iOS `PrivateKeyWalletModel.resetProperties`: `encryptedPrivateKey` + `encryptedWIF`).
     * [wif] may be empty for chains without a WIF counterpart (TRX: no WIF envelope is stored).
     */
    suspend fun sealPrivateKey(
        walletId: String,
        privateKey: String,
        wif: String,
        password: CharArray,
        now: Long,
    ): SealedSecrets? = coroutineScope {
        val k = async { obv2.encryptVerified(privateKey, password) }
        val w = async { if (wif.isEmpty()) "" else obv2.encryptVerified(wif, password) }
        val keyEnvelope = k.await()
        val wifEnvelope = w.await()
        when {
            keyEnvelope == null || wifEnvelope == null -> null
            else -> SealedSecrets(
                walletId,
                encryptedPrivateKey = keyEnvelope,
                encryptedWif = wifEnvelope.ifEmpty { null },
                updatedAt = now,
            )
        }
    }

    /**
     * Change-password / reset-password re-encryption (iOS `WalletModel.changePassword`): every field of
     * [plaintexts] is sealed under [newPassword]; returns `null` on the first failed self-check.
     */
    suspend fun reseal(
        walletId: String,
        plaintexts: Map<SecretField, CharArray>,
        newPassword: CharArray,
        now: Long,
    ): SealedSecrets? = coroutineScope {
        val jobs = plaintexts.mapValues { (_, chars) -> async { obv2.encryptVerified(chars, newPassword) } }
        val sealed = jobs.mapValues { it.value.await() }
        if (sealed.values.any { it == null }) {
            null
        } else {
            SealedSecrets(
                walletId = walletId,
                encryptedMnemonic = sealed[SecretField.MNEMONIC],
                encryptedSeed = sealed[SecretField.SEED],
                encryptedPrivateKey = sealed[SecretField.PRIVATE_KEY],
                encryptedWif = sealed[SecretField.WIF],
                encryptedPassphrase = sealed[SecretField.PASSPHRASE],
                updatedAt = now,
            )
        }
    }
}
