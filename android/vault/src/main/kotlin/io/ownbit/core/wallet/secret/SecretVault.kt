// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.wallet.secret

import io.ownbit.core.crypto.hash.Hashes
import io.ownbit.core.crypto.obv2.Obv2DecryptResult
import io.ownbit.core.crypto.obv2.Obv2Envelope
import io.ownbit.core.crypto.util.Secrets
import io.ownbit.core.crypto.util.wipe
import io.ownbit.core.wallet.WalletError
import io.ownbit.core.wallet.WalletResult
import io.ownbit.core.wallet.api.UnlockedSecrets
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import java.security.MessageDigest

/**
 * The envelopes of a wallet. [PASSPHRASE] has no stored hash: it can only be opened together with [MNEMONIC], whose
 * hash gate proves the password, and only the backup reveal / password change ask for it.
 */
enum class SecretField {
    MNEMONIC, SEED, PRIVATE_KEY, WIF, PASSPHRASE;

    companion object {
        /**
         * What signing / key derivation / the public signer may open ([io.ownbit.core.wallet.api.WalletSecretAccess.withUnlocked]):
         * every field except [PASSPHRASE] — the seed already includes it. A new field must be added here explicitly.
         */
        val SIGNING: Set<SecretField> = setOf(MNEMONIC, SEED, PRIVATE_KEY, WIF)
    }
}

/** Why an envelope could not be opened although the password was not proven wrong. */
internal class SecretUnavailableException(val reason: String) : Exception("wallet secret unavailable: $reason")

/**
 * Opens a wallet's `OBV2:` envelopes (iOS `WalletModel.decryptMnemonic` / `decryptSeed`,
 * `PrivateKeyWalletModel.decryptPrivateKey` / `decryptWIF`). Only the requested fields are decrypted (one scrypt
 * each, run concurrently); every plaintext is checked against the hash stored at creation (iOS `mnemonicHash` /
 * `seedHash` / `privateKeyHash` / `wifHash` gate). Plaintexts never leave as `String`s: they are `CharArray`s the
 * caller wipes ([UnlockedSecrets.wipe]).
 */
class SecretVault(
    private val store: WalletSecretStore,
    private val obv2: Obv2Envelope,
    private val attempts: PasswordAttemptTracker,
) {

    /** Raw result of [open]. */
    sealed interface Opened {
        class Ok(val secrets: UnlockedSecrets) : Opened
        data object WrongPassword : Opened
        data object NoSecret : Opened
        class Unavailable(val cause: Throwable) : Opened
    }

    /**
     * Decrypts [fields] of [walletId] with [password]. Missing envelopes stay `null` in the result; when none of
     * the requested envelopes exists the result is [Opened.NoSecret]. The caller owns [password].
     *
     * @throws IllegalArgumentException when [fields] asks for [SecretField.PASSPHRASE] without [SecretField.MNEMONIC]
     *   (the passphrase has no hash of its own: the mnemonic's hash is its password gate).
     */
    suspend fun open(walletId: String, password: CharArray, fields: Set<SecretField>): Opened {
        require(SecretField.PASSPHRASE !in fields || SecretField.MNEMONIC in fields) {
            "the passphrase opens only together with the mnemonic"
        }
        val secret = store.read(walletId) ?: return Opened.Unavailable(SecretUnavailableException("no wallet"))
        val envelopes = fields.associateWith { field ->
            when (field) {
                SecretField.MNEMONIC -> secret.encryptedMnemonic
                SecretField.SEED -> secret.encryptedSeed
                SecretField.PRIVATE_KEY -> secret.encryptedPrivateKey
                SecretField.WIF -> secret.encryptedWif
                SecretField.PASSPHRASE -> secret.encryptedPassphrase
            }
        }.filterValues { it != null }
        if (envelopes.isEmpty()) return Opened.NoSecret
        if (password.isEmpty()) return Opened.WrongPassword

        val results: Map<SecretField, Obv2DecryptResult> = coroutineScope {
            envelopes.mapValues { (_, envelope) -> async { obv2.open(envelope!!, password) } }
                .mapValues { it.value.await() }
        }
        val plain = HashMap<SecretField, CharArray>()
        var outcome: Opened? = null
        try {
            for ((field, result) in results) {
                when (result) {
                    is Obv2DecryptResult.Success -> {
                        val bytes = result.plaintext
                        try {
                            val expected = when (field) {
                                SecretField.MNEMONIC -> secret.mnemonicHash
                                SecretField.SEED -> secret.seedHash
                                SecretField.PRIVATE_KEY -> secret.privateKeyHash
                                SecretField.WIF -> secret.wifHash
                                // No hash is ever stored for the passphrase (low entropy: a hash would invite offline
                                // guessing); the mnemonic's hash checked in the same open is the password gate.
                                SecretField.PASSPHRASE -> null
                            }
                            if (!expected.isNullOrEmpty() && !MessageDigest.isEqual(
                                    Hashes.sha256Hex(bytes).toByteArray(), expected.lowercase().toByteArray(),
                                )
                            ) {
                                if (outcome == null) outcome = Opened.Unavailable(SecretUnavailableException("integrity"))
                            } else {
                                val chars = Secrets.utf8Chars(bytes)
                                if (chars == null) {
                                    if (outcome == null) outcome = Opened.Unavailable(SecretUnavailableException("encoding"))
                                } else {
                                    plain[field] = chars
                                }
                            }
                        } finally {
                            bytes.wipe()
                        }
                    }
                    Obv2DecryptResult.DecryptFailed -> outcome = Opened.WrongPassword
                    Obv2DecryptResult.BadEnvelope, Obv2DecryptResult.KdfFailed,
                    Obv2DecryptResult.DeviceKeyUnavailable, Obv2DecryptResult.DeviceKeyMismatch,
                    -> if (outcome !is Opened.WrongPassword) {
                        outcome = Opened.Unavailable(SecretUnavailableException(result.toString()))
                    }
                }
            }
            outcome?.let { return it }
            return Opened.Ok(
                UnlockedSecrets(
                    walletId = walletId,
                    mnemonic = plain[SecretField.MNEMONIC],
                    seedHex = plain[SecretField.SEED],
                    privateKey = plain[SecretField.PRIVATE_KEY],
                    wif = plain[SecretField.WIF],
                    privateKeyCoinType = secret.privateKeyCoinType,
                    passphrase = plain[SecretField.PASSPHRASE],
                ),
            )
        } finally {
            if (outcome != null) plain.values.forEach { it.wipe() }
        }
    }

    /**
     * [open] with attempt counting ([PasswordAttemptTracker]) and [WalletError] mapping, then runs [block] and wipes
     * the secrets whatever happens.
     *
     * An empty [password] on a wallet that has envelopes is [WalletError.EmptyPassword] and is **not** counted as a
     * wrong attempt (the iOS password dialogs refuse an empty field before they check the password).
     */
    suspend fun <T> use(
        walletId: String,
        password: CharArray,
        fields: Set<SecretField>,
        block: suspend (UnlockedSecrets) -> WalletResult<T>,
    ): WalletResult<T> = when (val opened = open(walletId, password, fields)) {
        is Opened.Ok -> {
            attempts.reset(walletId)
            try {
                block(opened.secrets)
            } finally {
                opened.secrets.wipe()
            }
        }
        Opened.WrongPassword ->
            if (password.isEmpty()) WalletResult.Err(WalletError.EmptyPassword) else WalletResult.Err(wrongPassword(walletId))
        Opened.NoSecret -> WalletResult.Err(WalletError.NoSecret)
        is Opened.Unavailable -> WalletResult.Err(WalletError.SecretUnavailable(opened.cause))
    }

    /** Records a failure and builds the error. */
    fun wrongPassword(walletId: String): WalletError.WrongPassword {
        val n = attempts.recordFailure(walletId)
        return WalletError.WrongPassword(n, attempts.suggestsReimport(n))
    }

    /** The envelope used to check a password: the mnemonic (HD) or the private key (private-key wallets). */
    suspend fun verificationField(walletId: String): SecretField? {
        val secret = store.read(walletId) ?: return null
        return when {
            secret.encryptedMnemonic != null -> SecretField.MNEMONIC
            secret.encryptedPrivateKey != null -> SecretField.PRIVATE_KEY
            secret.encryptedSeed != null -> SecretField.SEED
            secret.encryptedWif != null -> SecretField.WIF
            else -> null
        }
    }
}
