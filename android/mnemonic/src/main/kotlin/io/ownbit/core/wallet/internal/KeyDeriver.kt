// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.wallet.internal

import io.ownbit.core.jsengine.bridge.BitcoinAddressType
import io.ownbit.core.jsengine.bridge.BitcoinExtendedPublicKeys
import io.ownbit.core.jsengine.bridge.EthereumAccount
import io.ownbit.core.jsengine.bridge.PublicKeyAddress
import io.ownbit.core.jsengine.bridge.TaprootXpubs
import io.ownbit.core.jsengine.bridge.TronAddress
import io.ownbit.core.jsengine.chain.ChainKeys
import io.ownbit.core.jsengine.chain.JsChain

/**
 * Every JS call the wallet creation / import makes (mnemonic generation and validation, seed, key derivation), behind
 * one seam so the orchestration can be unit-tested without WebViews. The production implementation is [JsKeyDeriver]
 * (the iOS bundles through `:jsengine`). (The app's interface also covers private-key import and key export.)
 *
 * All `String` arguments / results that carry secrets (mnemonic, seed hex, private keys) are only held for the
 * duration of the call; never log them.
 */
interface KeyDeriver {

    /** New English BIP39 mnemonic of [wordCount] words (12 or 24). Secret. */
    suspend fun generateMnemonic(wordCount: Int): String

    /** JS `validateMnemonic` — the final checksum authority (8 word lists). */
    suspend fun validateMnemonic(mnemonic: String): Boolean

    /**
     * BIP39 seed hex of [mnemonic] with the BIP39 [passphrase] (`null` = none: every wallet except a passphrase
     * import). Secret; the caller wipes [passphrase].
     */
    suspend fun mnemonicToSeedHex(mnemonic: String, passphrase: CharArray? = null): String

    /** BTC main (receive-chain) xpub for [seedTypePath] (iOS `getMasterXPublicKey`). */
    suspend fun masterXpub(seedHex: String, seedTypePath: String): String

    /** The six BTC chain-level keys (iOS `getBitcoinXPublicKeysForAll`). */
    suspend fun bitcoinXpubs(seedHex: String, seedTypePath: String): BitcoinExtendedPublicKeys

    /**
     * BTC addresses `from..to` (inclusive) of one flavour from its chain-level xpub ([BitcoinAddressType.TAPROOT]:
     * the Taproot bundle's `getTaprootAddresses`).
     */
    suspend fun bitcoinAddresses(type: BitcoinAddressType, xpub: String, from: Long, to: Long): List<String>

    /** BIP86 chain xpubs `m/86'/0'/0'/0` / `…/1` (Taproot bundle `getTaprootXpubs`, standard `xpub` version). */
    suspend fun taprootXpubs(seedHex: String): TaprootXpubs

    /**
     * Loads the Taproot bundle ahead of use (iOS `BTCTaprootJSBridge.preload()` when the create / import page opens):
     * its first load takes seconds, the user should not wait for it after typing the password. Never throws.
     */
    suspend fun warmUpTaproot() {}

    /** ETH account [index] from the seed (xpub, public key, EIP-55 address). */
    suspend fun ethAccount(seedHex: String, index: Int): EthereumAccount

    /** ETH child [index] of the chain xpub `m/44'/60'/0'/0` (watch wallets, "use address #N"). */
    suspend fun ethAccountFromXpub(xpub: String, index: Int): PublicKeyAddress

    /** TRX index-0 address (`m/44'/195'/0'/0/0`). */
    suspend fun tronIndex0(seedHex: String): TronAddress

    /** TRX address of index > 0 = ETH account N converted (iOS `TronWalletModel.useAddrOnIndexNo`). */
    suspend fun tronFromEthXpub(ethXpub: String, index: Int): TronAddress

    /** SOL address (= public key) from the seed. */
    suspend fun solanaAddress(seedHex: String): String

    /** Keys of any other chain (iOS `updateWallet(for:)`); TON / ADA need [mnemonic]. */
    suspend fun deriveChain(chain: JsChain, seedHex: String, mnemonic: String?): ChainKeys
}
