// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.wallet.secret

/**
 * What the vault reads and writes for one wallet. In the app these are two Room tables (`wallets` for the hashes and
 * flags, `wallet_secrets` for the envelopes); the storage itself is not part of this repository — implement
 * [WalletSecretStore] over whatever the host app uses.
 *
 * Every `encrypted*` field is an `OBV2:` envelope ([io.ownbit.core.crypto.obv2.Obv2Envelope]) or `null`. The `*Hash`
 * fields are the lower-case hex SHA-256 of the UTF-8 plaintext, written at creation / import (iOS `mnemonicHash` /
 * `seedHash` / `privateKeyHash` / `wifHash`): [SecretVault] refuses a decrypted plaintext that does not match. No hash
 * is ever stored for the BIP39 passphrase (low entropy: a hash would invite offline guessing).
 *
 * @property privateKeyCoinType iOS `CoinType` raw value a private-key wallet's key belongs to.
 */
class StoredWalletSecrets(
    val walletId: String,
    val encryptedMnemonic: String? = null,
    val encryptedSeed: String? = null,
    val encryptedPrivateKey: String? = null,
    val encryptedWif: String? = null,
    val encryptedPassphrase: String? = null,
    val mnemonicHash: String? = null,
    val seedHash: String? = null,
    val privateKeyHash: String? = null,
    val wifHash: String? = null,
    val privateKeyCoinType: Int? = null,
) {
    /** A BIP39 passphrase wallet (its passphrase envelope exists). */
    val hasPassphrase: Boolean get() = encryptedPassphrase != null

    override fun toString(): String = "StoredWalletSecrets(walletId=$walletId)"
}

/** The envelopes [SecretSealer] produced for one wallet; `null` fields have no envelope. */
class SealedSecrets(
    val walletId: String,
    val encryptedMnemonic: String? = null,
    val encryptedSeed: String? = null,
    val encryptedPrivateKey: String? = null,
    val encryptedWif: String? = null,
    val encryptedPassphrase: String? = null,
    val updatedAt: Long,
) {
    override fun toString(): String = "SealedSecrets(walletId=$walletId)"
}

/** Storage of the wallets' envelopes and hashes (a stub interface: the app's Room implementation is not published). */
interface WalletSecretStore {
    /** The stored secrets of [walletId], or `null` when the wallet does not exist. */
    suspend fun read(walletId: String): StoredWalletSecrets?

    /**
     * Replaces **every** envelope of `sealed.walletId` with [sealed] in one transaction (password change). Throws when
     * nothing was written; the old envelopes must then be untouched.
     */
    suspend fun replaceEnvelopes(sealed: SealedSecrets)
}
