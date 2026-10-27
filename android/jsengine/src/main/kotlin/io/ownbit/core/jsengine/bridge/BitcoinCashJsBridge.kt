// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.jsengine.bridge

import io.ownbit.core.jsengine.JsBundle
import io.ownbit.core.jsengine.JsEngineManager

/**
 * Typed bridge over `js/bch/bitcoincashjs-lib-app.min.js` - mirrors iOS `BitcoinCashJSBridge.swift`.
 *
 * BCH has no keys of its own in Ownbit: it shares the BTC legacy `m/44'/0'` xpubs and addresses
 * ([BitcoinJsBridge.getAddresses] with [BitcoinAddressType.LEGACY]); this bundle only converts them to
 * CashAddr for display / receive and validates BCH addresses.
 */
class BitcoinCashJsBridge(engines: JsEngineManager) : JsBridge(engines, JsBundle.BCH) {

    /** `bridge.toCashaddr(legacy)`: legacy `1...` address -> CashAddr (iOS `translateToNewAddress`). */
    suspend fun toCashAddress(legacyAddress: String): String = string(BRIDGE + "toCashaddr", legacyAddress)

    /** `bridge.isAddress(a)`: legacy or CashAddr BCH address. */
    suspend fun isAddress(address: String): Boolean = bool(BRIDGE + "isAddress", address)
}
