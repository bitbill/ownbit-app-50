// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.jsengine.chain

import io.ownbit.core.jsengine.JsBundle
import io.ownbit.core.jsengine.JsResultFormatException
import io.ownbit.core.jsengine.bridge.BitcoinJsBridge
import io.ownbit.core.jsengine.bridge.EthereumJsBridge
import io.ownbit.core.jsengine.bridge.StellarJsBridge
import io.ownbit.core.jsengine.bridge.TronJsBridge
import io.ownbit.core.jsengine.bridge.UtxoCoin
import io.ownbit.core.jsengine.bridge.UtxoJsBridges

/** Chains that support private-key wallets (iOS `BILImportPrivateKeyController.supportedCoins` minus XTZ). */
enum class PrivateKeyChain {
    BTC, ETH, TRX, LTC, DASH, XLM, ZEC, DOGE, DGB,
}

/**
 * The key material iOS collects in `BILImportPrivateWalletModel` before registering a private-key
 * wallet. Field semantics are iOS's (quirks included, the server depends on them):
 *
 * - [btcPublicKey] is the wallet lookup key (`md5(btcPublicKey)` -> `getWalletId`): the BTC public key
 *   for BTC / ETH / TRX keys, the chain public key for LTC / ZEC / DASH / DOGE / DGB, `02|04 + raw ed25519
 *   key` for XLM ("never change this logic").
 * - [ethAddress] holds the ETH address for BTC / ETH keys and `"<publicKey>:<address>"` of the chain
 *   for every other chain.
 * - [btc3Address] / [btcBc1Address] are only set for compressed BTC WIFs (`K`/`L`).
 *
 * Contains secrets ([privateKey], [wif]); `toString` is redacted.
 */
class ImportedPrivateKey(
    val chain: PrivateKeyChain,
    val privateKey: String,
    val wif: String,
    val isWif: Boolean,
    val publicKey: String,
    val ethAddress: String,
    val btcPublicKey: String,
    val btcAddress: String,
    val btc3Address: String,
    val btcBc1Address: String,
) {
    override fun toString(): String = "ImportedPrivateKey(chain=$chain, isWif=$isWif, <redacted>)"
}

/**
 * Private-key import, reproducing the JS part of iOS `BILImportPrivateKeyController.nextAction`
 * (`doImport` + `importByPrivateWalletModel`). Usage:
 *
 * ```
 * val key = PrivateKeyImporter.normalize(rawInput)            // strip 0x, trim, drop newlines
 * val checked = PrivateKeyImporter.checkFormat(chain, key)    // null -> "Invalid private key format"
 *     ?: return showFormatError()
 * val imported = importer.derive(chain, checked)              // JsException -> "Private key parse error"
 * ```
 */
class PrivateKeyImporter(
    private val bitcoin: BitcoinJsBridge,
    private val ethereum: EthereumJsBridge,
    private val tron: TronJsBridge,
    private val stellar: StellarJsBridge,
    private val utxo: UtxoJsBridges,
) {

    /**
     * Derives the import model of an already [normalize]d and [checkFormat]ted key.
     *
     * @throws io.ownbit.core.jsengine.JsException when the key cannot be parsed by the bundle.
     */
    suspend fun derive(chain: PrivateKeyChain, key: String): ImportedPrivateKey = when (chain) {
        PrivateKeyChain.BTC, PrivateKeyChain.ETH -> deriveBtcOrEth(chain, key)
        PrivateKeyChain.TRX -> {
            val address = tron.getAddressFromPrivateKey(key)
            // iOS falls through to the BTC branch for TRX: the server lookup key is a BTC public key.
            val btc = bitcoin.getPublicKeyAndAddress(key)
            ImportedPrivateKey(
                chain = chain,
                privateKey = key,
                wif = "",
                isWif = false,
                publicKey = "",
                ethAddress = address.hexAddress + ":" + address.base58Address,
                btcPublicKey = btc.publicKey,
                btcAddress = btc.address,
                btc3Address = "",
                btcBc1Address = "",
            )
        }
        PrivateKeyChain.XLM -> {
            val pair = stellar.getPublicKeyAndAddressFromPrivateKey(key)
            ImportedPrivateKey(
                chain = chain,
                privateKey = key,
                wif = key,
                isWif = true,
                publicKey = "",
                ethAddress = pair.publicKey + ":" + pair.address,
                btcPublicKey = (if (pair.publicKey.length == 64) "02" else "04") + pair.publicKey,
                btcAddress = "",
                btc3Address = "",
                btcBc1Address = "",
            )
        }
        PrivateKeyChain.LTC -> utxoKey(chain, UtxoCoin.LTC, key)
        PrivateKeyChain.ZEC -> utxoKey(chain, UtxoCoin.ZEC, key)
        PrivateKeyChain.DASH -> utxoKey(chain, UtxoCoin.DASH, key)
        PrivateKeyChain.DOGE -> utxoKey(chain, UtxoCoin.DOGE, key)
        PrivateKeyChain.DGB -> utxoKey(chain, UtxoCoin.DGB, key)
    }

    private suspend fun deriveBtcOrEth(chain: PrivateKeyChain, key: String): ImportedPrivateKey {
        val info = bitcoin.getPrivateKeyInfo(key)
            ?: throw JsResultFormatException(JsBundle.BTC, "bridge.getPrivKeyInfoFromPrivKey", "[isWIF, key]")
        val privateKeyHex = if (info.isWif) info.counterpart else key
        val wif = if (info.isWif) key else info.counterpart
        val eth = ethereum.getPublicKeyAndAddress(privateKeyHex)
        val btcInput = if (info.isWif) wif else privateKeyHex
        return if (key.startsWith("K") || key.startsWith("L")) {
            val all = bitcoin.getPublicKeyAndAddresses(btcInput)
            ImportedPrivateKey(
                chain = chain,
                privateKey = privateKeyHex,
                wif = wif,
                isWif = info.isWif,
                publicKey = eth.publicKey,
                ethAddress = eth.address,
                btcPublicKey = all.publicKey,
                btcAddress = all.legacy,
                btc3Address = all.nestedSegwit,
                btcBc1Address = all.nativeSegwit,
            )
        } else {
            val btc = bitcoin.getPublicKeyAndAddress(btcInput)
            ImportedPrivateKey(
                chain = chain,
                privateKey = privateKeyHex,
                wif = wif,
                isWif = info.isWif,
                publicKey = eth.publicKey,
                ethAddress = eth.address,
                btcPublicKey = btc.publicKey,
                btcAddress = btc.address,
                btc3Address = "",
                btcBc1Address = "",
            )
        }
    }

    private suspend fun utxoKey(chain: PrivateKeyChain, coin: UtxoCoin, key: String): ImportedPrivateKey {
        val pair = utxo.of(coin).getPublicKeyAndAddress(key)
        return ImportedPrivateKey(
            chain = chain,
            privateKey = key,
            wif = key,
            isWif = true,
            publicKey = "",
            ethAddress = pair.publicKey + ":" + pair.address,
            btcPublicKey = pair.publicKey,
            btcAddress = "",
            btc3Address = "",
            btcBc1Address = "",
        )
    }

    companion object {
        private val HEX_64 = Regex("^[0-9a-f]{64}$")

        /**
         * iOS `PrivateKeyWalletModel.normalize`: drop a leading `0x`/`0X`, trim, remove newlines. Android first removes
         * the Unicode bidi controls (ALM, LRM / RLM, LRE…RLO, LRI…PDI) a paste from a right-to-left context can carry
         * (Arabic UI, 5.0.1): invisible and never part of a key.
         */
        fun normalize(raw: String): String {
            val text = raw.filterNot(::isBidiControl)
            val stripped = if (text.startsWith("0x") || text.startsWith("0X")) text.substring(2) else text
            return stripped.trim().replace("\n", "")
        }

        private fun isBidiControl(c: Char): Boolean =
            c == '\u061C' || c == '\u200E' || c == '\u200F' || c in '\u202A'..'\u202E' || c in '\u2066'..'\u2069'

        /**
         * iOS per-chain prefix / format gate (`nextAction` switch). Returns the key to import (ETH / TRX:
         * `0x` removed and lower-cased) or `null` for "Invalid private key format".
         */
        fun checkFormat(chain: PrivateKeyChain, key: String): String? {
            if (key.isEmpty()) return null
            return when (chain) {
                PrivateKeyChain.BTC, PrivateKeyChain.DGB ->
                    key.takeIf { it.startsWith("5") || it.startsWith("K") || it.startsWith("L") }
                PrivateKeyChain.ETH, PrivateKeyChain.TRX -> {
                    val bare = if (key.lowercase().startsWith("0x")) key.substring(2) else key
                    when {
                        bare.startsWith("K") || bare.startsWith("L") -> null
                        HEX_64.matches(bare.lowercase()) -> bare.lowercase()
                        else -> null
                    }
                }
                PrivateKeyChain.XLM -> key.takeIf { it.startsWith("S") }
                PrivateKeyChain.LTC -> key.takeIf { it.startsWith("6") || it.startsWith("T") }
                PrivateKeyChain.ZEC -> key.takeIf { it.startsWith("K") || it.startsWith("L") }
                PrivateKeyChain.DASH -> key.takeIf { it.startsWith("7") || it.startsWith("X") }
                PrivateKeyChain.DOGE -> key.takeIf { it.startsWith("6") || it.startsWith("Q") }
            }
        }
    }
}
