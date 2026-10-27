// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.jsengine.chain

import io.ownbit.core.jsengine.JsBundle
import io.ownbit.core.jsengine.JsResultFormatException
import io.ownbit.core.jsengine.bridge.BitcoinAddressType
import io.ownbit.core.jsengine.bridge.BitcoinCashJsBridge
import io.ownbit.core.jsengine.bridge.BitcoinExtendedPublicKeys
import io.ownbit.core.jsengine.bridge.BitcoinJsBridge
import io.ownbit.core.jsengine.bridge.CardanoAddresses
import io.ownbit.core.jsengine.bridge.CardanoJsBridge
import io.ownbit.core.jsengine.bridge.EthereumJsBridge
import io.ownbit.core.jsengine.bridge.ExtendedPublicKeys
import io.ownbit.core.jsengine.bridge.FilecoinJsBridge
import io.ownbit.core.jsengine.bridge.RippleJsBridge
import io.ownbit.core.jsengine.bridge.SolanaJsBridge
import io.ownbit.core.jsengine.bridge.StacksJsBridge
import io.ownbit.core.jsengine.bridge.StellarJsBridge
import io.ownbit.core.jsengine.bridge.TonJsBridge
import io.ownbit.core.jsengine.bridge.TonWalletAddress
import io.ownbit.core.jsengine.bridge.TronAddress
import io.ownbit.core.jsengine.bridge.TronJsBridge
import io.ownbit.core.jsengine.bridge.UtxoCoin
import io.ownbit.core.jsengine.bridge.UtxoJsBridges

/**
 * Public key material of one chain, shaped like what iOS stores per coin wallet model.
 */
sealed interface ChainKeys {
    /** Chain the keys belong to. */
    val chain: JsChain

    /**
     * BTC: the six chain-level extended keys iOS stores at wallet creation (`resetProperties` ->
     * `getBitcoinXPublicKeysForAll`): `bitcoinWallet` (legacy), `btc_sw_pWallet` (49) and
     * `btc_sw_dWallet` (84) main + change.
     */
    data class Bitcoin(val xpubs: BitcoinExtendedPublicKeys) : ChainKeys {
        override val chain: JsChain get() = JsChain.BTC
    }

    /**
     * HD UTXO chain (BCH, LTC, DOGE, DASH, DGB, ZEN, ZEC): chain-level receive / change xpubs
     * (`extendedPublicKey` / `extendedChangePublicKey` in iOS). BCH carries the BTC legacy xpubs.
     */
    data class Hd(override val chain: JsChain, val xpubs: ExtendedPublicKeys) : ChainKeys

    /**
     * Single-address account chain (EVM, TRX, SOL, XRP, XLM, FIL, STX): `publicKey` / `address` as iOS
     * stores them (TRX: `publicKey` is the `41...` hex address; SOL / STX: both are the address).
     * [extendedPublicKey] is set for EVM (ETH chain xpub `m/44'/60'/0'/0`), [index] is the ETH / TRX
     * account index.
     */
    data class Account(
        override val chain: JsChain,
        val publicKey: String,
        val address: String,
        val extendedPublicKey: String? = null,
        val index: Int = 0,
    ) : ChainKeys

    /** TON v4R2 wallet (`tonWallet.address` / `.publicKey` (raw) / `.tonRealPub`). */
    data class Ton(val wallet: TonWalletAddress) : ChainKeys {
        override val chain: JsChain get() = JsChain.TON
    }

    /** Cardano (`adaWallet.address` = shelley, `.publicKey` = legacy address). */
    data class Cardano(val addresses: CardanoAddresses) : ChainKeys {
        override val chain: JsChain get() = JsChain.ADA
    }
}

/**
 * Key / address derivation for the 24 chains, reproducing iOS `WalletModel.updateWallet(for:)`,
 * `WalletModel.resetProperties(m:pwd:)` and the per-coin `updateWallet` implementations call for call
 * (same JS functions, same argument types, same paths):
 *
 * | chain | iOS source | JS |
 * |---|---|---|
 * | BTC | `resetProperties` | BTC `getBitcoinXPublicKeysForAll(seed, seedTypePath)` |
 * | BCH | `bitcoinWallet.updateWallet` (shared BTC xpub) | BTC `getBitcoinXPublicKeys`, BCH `toCashaddr` |
 * | EVM x8 | `ethereumWallet.updateWallet` | ETH `seedHexToPubAddr(seed, "m/44'/60'/0'/0/N")` |
 * | LTC | `litecoinWallet.updateWallet(seed, "0")` | LTC `getXpubkeysForAll(seed)` |
 * | DOGE/DASH/DGB/ZEN/ZEC | `updateWallet(seed, "0")` | `getXpubkeys(seed)` |
 * | TRX | `updateTronWallet(seedHex:)` | ETH `seedHexToPrivateHex(seed, "m/44'/195'/0'/0/0")` -> TRX `getAddress` |
 * | TRX idx>0 | `TronWalletModel.useAddrOnIndexNo` | ETH `extPubKeyToPubAddr(ethXpub, N)` -> TRX `getBase58AddrFromHex` |
 * | SOL | `updateSolWallet` | SOL `generateAccount(seed)` |
 * | XRP | `updateWallet(seed:)` | XRP `getPubAddrFromSeedHex(seed)` |
 * | XLM | `updateWallet(seed:)` | XLM `getPubAddrFromSeedHex(seed, true)` |
 * | FIL | `updateWallet(seed:)` | FIL `getPubAddrFromSeed(seed)` |
 * | STX | `updateWallet(seed:)` | ETH `seedHexToPrivateHex(seed, m/44'/60'/0'/0/0)` -> STX `getAddressFromPrivateHex` |
 * | TON | `updateTonWallet(mnemonic:)` | TON `mnemonicToAddress(mnemonic)` |
 * | ADA | `updateAdaWallet(mnemonic:)` | BTC `mnemonicToEntropy` -> ADA `getAdaAddress(entropy)` |
 *
 * Inputs are secrets held only in memory by the caller (`seedHex` from [BitcoinJsBridge.mnemonicToSeedHex]).
 */
class ChainKeyDerivation(
    private val bitcoin: BitcoinJsBridge,
    private val bitcoinCash: BitcoinCashJsBridge,
    private val utxo: UtxoJsBridges,
    private val ethereum: EthereumJsBridge,
    private val tron: TronJsBridge,
    private val solana: SolanaJsBridge,
    private val ton: TonJsBridge,
    private val ripple: RippleJsBridge,
    private val stellar: StellarJsBridge,
    private val cardano: CardanoJsBridge,
    private val filecoin: FilecoinJsBridge,
    private val stacks: StacksJsBridge,
) {

    /**
     * Derives the key material of [chain].
     *
     * @param seedHex BIP39 seed (no passphrase) as hex.
     * @param mnemonic required for [JsChain.TON] and [JsChain.ADA] only (they derive from the words /
     *   entropy, not from the seed).
     * @param evmIndex ETH account index for EVM chains (iOS `ethereumWallet.lastIndexNo`, default 0).
     * @param seedTypePath iOS `getSeedTypePath()`: `"0"` or a custom path (BTC / BCH only).
     */
    suspend fun derive(
        chain: JsChain,
        seedHex: String,
        mnemonic: String? = null,
        evmIndex: Int = 0,
        seedTypePath: String = BitcoinJsBridge.BIP39_SEED_TYPE_PATH,
    ): ChainKeys = when (chain) {
        JsChain.BTC -> ChainKeys.Bitcoin(bitcoin.getXPublicKeysForAll(seedHex, seedTypePath))
        JsChain.BCH -> ChainKeys.Hd(JsChain.BCH, bitcoin.getXPublicKeys(seedHex, seedTypePath))
        JsChain.ETH, JsChain.BSC, JsChain.BASE, JsChain.ARB, JsChain.HYPE, JsChain.OP, JsChain.POLYGON, JsChain.ETC -> {
            val account = ethereum.getAccount(seedHex, evmIndex)
            ChainKeys.Account(chain, account.publicKey, account.address, account.extendedPublicKey, evmIndex)
        }
        JsChain.LTC -> hd(JsChain.LTC, UtxoCoin.LTC, seedHex)
        JsChain.DOGE -> hd(JsChain.DOGE, UtxoCoin.DOGE, seedHex)
        JsChain.DASH -> hd(JsChain.DASH, UtxoCoin.DASH, seedHex)
        JsChain.DGB -> hd(JsChain.DGB, UtxoCoin.DGB, seedHex)
        JsChain.ZEN -> hd(JsChain.ZEN, UtxoCoin.ZEN, seedHex)
        JsChain.ZEC -> hd(JsChain.ZEC, UtxoCoin.ZEC, seedHex)
        JsChain.TRX -> {
            val address = tronAddress(seedHex, index = 0)
            ChainKeys.Account(JsChain.TRX, address.hexAddress, address.base58Address)
        }
        JsChain.SOL -> solana.getAddress(seedHex).let { ChainKeys.Account(JsChain.SOL, it, it) }
        JsChain.XRP -> ripple.getPublicKeyAndAddress(seedHex).let { ChainKeys.Account(JsChain.XRP, it.publicKey, it.address) }
        JsChain.XLM -> stellar.getPublicKeyAndAddress(seedHex, isNew = true)
            .let { ChainKeys.Account(JsChain.XLM, it.publicKey, it.address) }
        JsChain.FIL -> filecoin.getPublicKeyAndAddress(seedHex).let { ChainKeys.Account(JsChain.FIL, it.publicKey, it.address) }
        JsChain.STX -> {
            val privateKey = ethereum.getEthPrivateKeyHex(seedHex, index = 0)
            stacks.getPublicKeyAndAddress(privateKey).let { ChainKeys.Account(JsChain.STX, it.publicKey, it.address) }
        }
        JsChain.TON -> ChainKeys.Ton(ton.getWalletAddress(requireMnemonic(chain, mnemonic)))
        JsChain.ADA -> {
            val entropy = bitcoin.mnemonicToEntropy(requireMnemonic(chain, mnemonic))
                ?: throw JsResultFormatException(JsBundle.BTC, "bridge.mnemonicToEntropy", "BIP39 entropy")
            ChainKeys.Cardano(cardano.getAddresses(entropy))
        }
    }

    /** Derives several chains sequentially (engines are per bundle and serialized anyway). */
    suspend fun deriveAll(
        chains: Collection<JsChain>,
        seedHex: String,
        mnemonic: String? = null,
        evmIndex: Int = 0,
        seedTypePath: String = BitcoinJsBridge.BIP39_SEED_TYPE_PATH,
    ): Map<JsChain, ChainKeys> = chains.associateWith { derive(it, seedHex, mnemonic, evmIndex, seedTypePath) }

    /**
     * TRX address of account [index], exactly as iOS: index 0 uses the dedicated `m/44'/195'/0'/0/0`
     * key; index > 0 re-uses ETH account `m/44'/60'/0'/0/N` converted to TRON
     * (`TronWalletModel.useAddrOnIndexNo`) - see [tronAddressFromEthExtendedKey].
     */
    suspend fun tronAddress(seedHex: String, index: Int, tronNode: String = tron.tronNode): TronAddress {
        require(index >= 0) { "index must be >= 0" }
        return if (index == 0) {
            tron.getAddressFromPrivateKey(ethereum.getTronPrivateKeyHex(seedHex), tronNode)
        } else {
            tronAddressFromEthExtendedKey(ethereum.getAccount(seedHex, 0).extendedPublicKey, index, tronNode)
        }
    }

    /**
     * TRX address of account [index] > 0 from the stored ETH chain xpub (works for watch wallets):
     * ETH `extPubKeyToPubAddr(xpub, N)` then TRX `getBase58AddrFromHex(0x...)`. Index 0 cannot be
     * derived this way (it uses the 195' key; iOS keeps a backup `trxAddress0`).
     */
    suspend fun tronAddressFromEthExtendedKey(
        ethExtendedPublicKey: String,
        index: Int,
        tronNode: String = tron.tronNode,
    ): TronAddress {
        require(index > 0) { "TRX index 0 is derived from m/44'/195'/0'/0/0, not from the ETH xpub" }
        val ethAddress = ethereum.getAccountFromExtendedPublicKey(ethExtendedPublicKey, index).address
        return tron.getAddressFromHex(ethAddress, tronNode)
    }

    /**
     * Receive (or change) addresses `fromIndex..toIndex` (inclusive) of an HD chain, as iOS
     * `generateAddresses` / `generateChangeAddresses`. BCH returns CashAddr (converted from the BTC
     * legacy addresses, as the iOS receive screen does).
     */
    suspend fun hdAddresses(keys: ChainKeys.Hd, change: Boolean, fromIndex: Long, toIndex: Long): List<String> {
        val xpub = if (change) keys.xpubs.change else keys.xpubs.main
        return when (keys.chain) {
            JsChain.BCH -> bitcoin.getAddresses(BitcoinAddressType.LEGACY, xpub, fromIndex, toIndex)
                .map { bitcoinCash.toCashAddress(it) }
            JsChain.LTC -> utxo.of(UtxoCoin.LTC).getAddresses(xpub, fromIndex, toIndex)
            JsChain.DOGE -> utxo.of(UtxoCoin.DOGE).getAddresses(xpub, fromIndex, toIndex)
            JsChain.DASH -> utxo.of(UtxoCoin.DASH).getAddresses(xpub, fromIndex, toIndex)
            JsChain.DGB -> utxo.of(UtxoCoin.DGB).getAddresses(xpub, fromIndex, toIndex)
            JsChain.ZEN -> utxo.of(UtxoCoin.ZEN).getAddresses(xpub, fromIndex, toIndex)
            JsChain.ZEC -> utxo.of(UtxoCoin.ZEC).getAddresses(xpub, fromIndex, toIndex)
            else -> throw IllegalArgumentException("${keys.chain} is not an HD UTXO chain")
        }
    }

    /** BTC addresses `fromIndex..toIndex` (inclusive) of one flavour from [keys]. */
    suspend fun bitcoinAddresses(
        keys: ChainKeys.Bitcoin,
        type: BitcoinAddressType,
        change: Boolean,
        fromIndex: Long,
        toIndex: Long,
    ): List<String> {
        val xpub = when (type) {
            BitcoinAddressType.LEGACY -> if (change) keys.xpubs.legacyChange else keys.xpubs.legacyMain
            BitcoinAddressType.NESTED_SEGWIT -> if (change) keys.xpubs.nestedSegwitChange else keys.xpubs.nestedSegwitMain
            BitcoinAddressType.NATIVE_SEGWIT -> if (change) keys.xpubs.nativeSegwitChange else keys.xpubs.nativeSegwitMain
            // The six old-bundle xpubs have no m/86' key: Taproot goes through BitcoinTaprootJsBridge.
            BitcoinAddressType.TAPROOT -> throw IllegalArgumentException("Taproot addresses come from BitcoinTaprootJsBridge")
        }
        return bitcoin.getAddresses(type, xpub, fromIndex, toIndex)
    }

    private suspend fun hd(chain: JsChain, coin: UtxoCoin, seedHex: String): ChainKeys.Hd =
        ChainKeys.Hd(chain, utxo.of(coin).getXPublicKeys(seedHex))

    private fun requireMnemonic(chain: JsChain, mnemonic: String?): String {
        require(!mnemonic.isNullOrEmpty()) { "$chain derivation needs the mnemonic" }
        return mnemonic
    }
}
