// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.wallet.api

/**
 * The only way any module gets at a wallet's secrets. Secrets are decrypted from the wallet's `OBV2:` envelopes
 * ([io.ownbit.core.wallet.secret.WalletSecretStore]) with the WALLET PASSWORD (never the app-lock PIN), handed to
 * [block], and wiped when [block] returns — callers must not keep references to the arrays or to Strings derived from
 * them beyond the block.
 *
 * iOS reference: WalletModel.checkPassword / decryptedSeed / decryptedMnemonic, PrivateKeyWalletModel.
 */
interface WalletSecretAccess {

    /** True when [password] opens this wallet's envelopes. Runs the KDF off the main thread. */
    suspend fun verifyPassword(walletId: String, password: CharArray): Boolean

    /**
     * Decrypts the secrets of [walletId] and runs [block] with them. The arrays inside [UnlockedSecrets]
     * are zeroed after [block] completes (normally or exceptionally).
     */
    suspend fun <T> withUnlocked(
        walletId: String,
        password: CharArray,
        block: suspend (UnlockedSecrets) -> T,
    ): UnlockResult<T>
}

sealed interface UnlockResult<out T> {
    data class Success<T>(val value: T) : UnlockResult<T>
    /** Envelope did not open (wrong password, or tampered data). UI counts attempts (3 → suggest re-import). */
    data object WrongPassword : UnlockResult<Nothing>
    /** Watch wallets / multisig-watch wallets have no secrets: sign via offline QR instead. */
    data object NoSecret : UnlockResult<Nothing>
    /** Device key missing / Keystore failure / corrupt envelope — not a password problem. */
    data class Failed(val cause: Throwable) : UnlockResult<Nothing>
}

/**
 * Decrypted secrets of one wallet. Which fields are present depends on the wallet kind:
 * HD wallets → [mnemonic] + [seedHex]; private-key wallets → [privateKey] and/or [wif] (+ [privateKeyCoinType]).
 * JS bridges need Strings: convert with [String] at the last moment, inside the block.
 */
class UnlockedSecrets(
    val walletId: String,
    val mnemonic: CharArray?,
    val seedHex: CharArray?,
    val privateKey: CharArray?,
    val wif: CharArray?,
    /** iOS CoinType raw value the private key belongs to (private-key wallets only). */
    val privateKeyCoinType: Int?,
    /**
     * BIP39 passphrase of a passphrase wallet — only for the backup reveal and password change.
     * [WalletSecretAccess.withUnlocked] (signing, public signer) never fills it: signing uses [seedHex].
     */
    val passphrase: CharArray? = null,
) {
    fun wipe() {
        mnemonic?.fill('\u0000'); seedHex?.fill('\u0000'); privateKey?.fill('\u0000'); wif?.fill('\u0000')
        passphrase?.fill('\u0000')
    }

    override fun toString(): String = "UnlockedSecrets(walletId=$walletId, <redacted>)"
}
