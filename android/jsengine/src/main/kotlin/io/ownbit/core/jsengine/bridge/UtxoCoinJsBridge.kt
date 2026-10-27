// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.jsengine.bridge

import io.ownbit.core.jsengine.JsBundle
import io.ownbit.core.jsengine.JsEngineManager

/**
 * The bitcore-style UTXO bundles that share one API shape (iOS `LitecoinJSBridge`, `DogecoinJSBridge`,
 * `DashJSBridge`, `DigibyteJSBridge`, `HorizenJSBridge`, `ZcashJSBridge`). Only the function names
 * differ; they are pinned here exactly as the iOS bridges call them.
 *
 * Paths (inside the bundles): LTC m/44'/2', DOGE m/44'/3', DASH m/44'/5', DGB m/44'/20',
 * ZEN m/44'/121', ZEC m/44'/133' (transparent `t1` addresses only).
 */
enum class UtxoCoin(
    /** Bundle hosting the coin. */
    val bundle: JsBundle,
    internal val xpubsFunction: String,
    internal val addressesFunction: String,
    internal val addressFromPublicKeyFunction: String,
    internal val wifFromSeedFunction: String,
) {
    /** Litecoin. iOS calls `getXpubkeysForAll` (main, change, root). */
    LTC(JsBundle.LTC, "getXpubkeysForAll", "getLtcContinuousAddrFromXpubkey", "getLtcAddrFromPubKey", "getPrivkeyFromSeedHex"),

    /** Dogecoin. */
    DOGE(JsBundle.DOGE, "getXpubkeys", "getDogeContinuousAddrFromXpubkey", "getDogeAddrFromPubKey", "getPrivkeyFromSeedHex"),

    /** Dash. */
    DASH(JsBundle.DASH, "getXpubkeys", "getDshContinuousAddrFromXpubkey", "getDshAddrFromPubKey", "getPrivkeyFromSeedHex"),

    /** DigiByte. */
    DGB(JsBundle.DGB, "getXpubkeys", "getDgbContinuousAddrFromXpubkey", "getDgbAddrFromPubKey", "getPrivkeyFromSeedHex"),

    /** Horizen. */
    ZEN(JsBundle.ZEN, "getXpubkeys", "getZenContinuousAddrFromXpubkey", "getZenAddrFromPubKey", "getPrivkeyFromSeedHex"),

    /** Zcash (transparent). */
    ZEC(JsBundle.ZEC, "getXpubkeys", "getZecContinuousAddrFromXpubkey", "getZecAddrFromPubKey", "getWIFFromSeedHex"),
}

/** Typed bridge for one [UtxoCoin]. Obtain instances from [UtxoJsBridges]. */
class UtxoCoinJsBridge internal constructor(
    engines: JsEngineManager,
    /** Coin served by this bridge. */
    val coin: UtxoCoin,
) : JsBridge(engines, coin.bundle) {

    /**
     * `bridge.<getXpubkeys|getXpubkeysForAll>(seedHex)`: chain-level receive / change xpubs and the
     * account-level root xpub (iOS `updateWallet(seed:seedTypePath:)` stores main + change).
     */
    suspend fun getXPublicKeys(seedHex: String): ExtendedPublicKeys {
        val v = strings(BRIDGE + coin.xpubsFunction, 2, seedHex)
        return ExtendedPublicKeys(main = v[0], change = v[1], root = v.getOrNull(2))
    }

    /** Addresses of a chain-level xpub for `fromIndex..toIndex` (**inclusive**). */
    suspend fun getAddresses(extendedPublicKey: String, fromIndex: Long, toIndex: Long): List<String> {
        require(fromIndex in 0..toIndex) { "invalid index range" }
        val expected = (toIndex - fromIndex + 1).toInt()
        return strings(BRIDGE + coin.addressesFunction, expected, extendedPublicKey, fromIndex, toIndex)
    }

    /** `bridge.isAddress(a)` (for LTC, `3...` addresses must go through [BitcoinJsBridge.address3ToM] first). */
    suspend fun isAddress(address: String): Boolean = bool(BRIDGE + "isAddress", address)

    /**
     * `bridge.getPubkeyAndAddrFromPrivkey(k)`: public key + address of a WIF or hex private key. Note
     * that the bitcore bundles encode a *hex* key as an uncompressed WIF (as on iOS).
     */
    suspend fun getPublicKeyAndAddress(privateKey: String): PublicKeyAddress =
        publicKeyAddress(BRIDGE + "getPubkeyAndAddrFromPrivkey", privateKey)

    /** `bridge.get<Coin>AddrFromPubKey(pub)`. */
    suspend fun getAddressFromPublicKey(publicKey: String): String =
        nonEmptyString(BRIDGE + coin.addressFromPublicKeyFunction, publicKey)

    /** WIF of the key at `index` on the receive (`isChange = false`) or change chain. Secret. */
    suspend fun getWifFromSeedHex(seedHex: String, index: Int, isChange: Boolean): String =
        nonEmptyString(BRIDGE + coin.wifFromSeedFunction, seedHex, index, isChange)
}

/** Holder of the six [UtxoCoinJsBridge]s. */
class UtxoJsBridges(engines: JsEngineManager) {
    private val bridges: Map<UtxoCoin, UtxoCoinJsBridge> =
        UtxoCoin.entries.associateWith { UtxoCoinJsBridge(engines, it) }

    /** Bridge of [coin]. */
    fun of(coin: UtxoCoin): UtxoCoinJsBridge = bridges.getValue(coin)

    /** Litecoin bridge. */
    val litecoin: UtxoCoinJsBridge get() = of(UtxoCoin.LTC)

    /** Dogecoin bridge. */
    val dogecoin: UtxoCoinJsBridge get() = of(UtxoCoin.DOGE)

    /** Dash bridge. */
    val dash: UtxoCoinJsBridge get() = of(UtxoCoin.DASH)

    /** DigiByte bridge. */
    val digibyte: UtxoCoinJsBridge get() = of(UtxoCoin.DGB)

    /** Horizen bridge. */
    val horizen: UtxoCoinJsBridge get() = of(UtxoCoin.ZEN)

    /** Zcash bridge. */
    val zcash: UtxoCoinJsBridge get() = of(UtxoCoin.ZEC)
}
