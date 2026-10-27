// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.wallet.internal

import io.ownbit.core.jsengine.JsBundle
import io.ownbit.core.jsengine.JsEngineManager
import io.ownbit.core.jsengine.bridge.BitcoinAddressType
import io.ownbit.core.jsengine.bridge.BitcoinExtendedPublicKeys
import io.ownbit.core.jsengine.bridge.BitcoinJsBridge
import io.ownbit.core.jsengine.bridge.BitcoinTaprootJsBridge
import io.ownbit.core.jsengine.bridge.EthereumAccount
import io.ownbit.core.jsengine.bridge.EthereumJsBridge
import io.ownbit.core.jsengine.bridge.MnemonicStrength
import io.ownbit.core.jsengine.bridge.PublicKeyAddress
import io.ownbit.core.jsengine.bridge.SolanaJsBridge
import io.ownbit.core.jsengine.bridge.TaprootXpubs
import io.ownbit.core.jsengine.bridge.TronAddress
import io.ownbit.core.jsengine.chain.ChainKeyDerivation
import io.ownbit.core.jsengine.chain.ChainKeys
import io.ownbit.core.jsengine.chain.JsChain

/**
 * [KeyDeriver] over the iOS JS bundles (`:jsengine`). Every call reproduces the iOS Swift bridge call it replaces
 * (function, argument types, paths).
 */
class JsKeyDeriver(
    private val bitcoin: BitcoinJsBridge,
    private val taproot: BitcoinTaprootJsBridge,
    private val ethereum: EthereumJsBridge,
    private val solana: SolanaJsBridge,
    private val derivation: ChainKeyDerivation,
    private val engines: JsEngineManager,
) : KeyDeriver {

    /** iOS `BitcoinJSBridge.generateMnemonic(entropy: 128|256, language: 0)`. */
    override suspend fun generateMnemonic(wordCount: Int): String = bitcoin.generateMnemonic(
        if (wordCount == MnemonicStrength.WORDS_24.wordCount) MnemonicStrength.WORDS_24 else MnemonicStrength.WORDS_12,
    )

    override suspend fun validateMnemonic(mnemonic: String): Boolean = bitcoin.validateMnemonic(mnemonic)

    override suspend fun mnemonicToSeedHex(mnemonic: String, passphrase: CharArray?): String =
        bitcoin.mnemonicToSeedHex(mnemonic, passphrase)

    /** iOS `BitcoinJSBridge.getMasterXPublicKey(mnemonic:seedType:seedTypePath:)` after `mnemonicToSeedHex`. */
    override suspend fun masterXpub(seedHex: String, seedTypePath: String): String =
        bitcoin.getMasterXPublicKey(seedHex, seedTypePath)

    /** iOS `WalletModel.resetProperties` → `getXPublicKeysForAll(seed:seedTypePath:)`. */
    override suspend fun bitcoinXpubs(seedHex: String, seedTypePath: String): BitcoinExtendedPublicKeys =
        bitcoin.getXPublicKeysForAll(seedHex, seedTypePath)

    override suspend fun bitcoinAddresses(type: BitcoinAddressType, xpub: String, from: Long, to: Long): List<String> =
        if (type == BitcoinAddressType.TAPROOT) {
            taproot.getTaprootAddresses(xpub, from, to)
        } else {
            bitcoin.getAddresses(type, xpub, from, to)
        }

    /** iOS `BTCTaprootJSBridge.getTaprootXpubs(seedHex:)`. */
    override suspend fun taprootXpubs(seedHex: String): TaprootXpubs {
        val chars = seedHex.toCharArray()
        return try {
            taproot.getTaprootXpubs(chars)
        } finally {
            chars.fill('0')
        }
    }

    /** iOS `BTCTaprootJSBridge.preload()` (create / import page). */
    override suspend fun warmUpTaproot() {
        engines.warmUp(setOf(JsBundle.BTC_TAPROOT))
    }

    /** iOS `EthereumJSBridge.getPublicKeyAndAddress(seed:indexNo:)`. */
    override suspend fun ethAccount(seedHex: String, index: Int): EthereumAccount = ethereum.getAccount(seedHex, index)

    /** iOS `EthereumJSBridge.getPublicKeyAndAddress(extPubKey:indexNo:)`. */
    override suspend fun ethAccountFromXpub(xpub: String, index: Int): PublicKeyAddress =
        ethereum.getAccountFromExtendedPublicKey(xpub, index)

    /** iOS `seedHexToTrxPrivateKey` → `TronJSBridge.getPublicKeyAndAddress(privateKey:)`. */
    override suspend fun tronIndex0(seedHex: String): TronAddress = derivation.tronAddress(seedHex, index = 0)

    /** iOS `TronWalletModel.useAddrOnIndexNo`: ETH `extPubKeyToPubAddr` → TRX `getBase58AddrFromHex`. */
    override suspend fun tronFromEthXpub(ethXpub: String, index: Int): TronAddress =
        derivation.tronAddressFromEthExtendedKey(ethXpub, index)

    /** iOS `SolanaJSBridge.getPublicKeyAndAddress(seed:)`. */
    override suspend fun solanaAddress(seedHex: String): String = solana.getAddress(seedHex)

    override suspend fun deriveChain(chain: JsChain, seedHex: String, mnemonic: String?): ChainKeys =
        derivation.derive(chain, seedHex, mnemonic = mnemonic)
}
