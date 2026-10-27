// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.jsengine.bridge

import io.ownbit.core.jsengine.JsBundle
import io.ownbit.core.jsengine.JsEngineManager

/**
 * Typed bridge over `js/trx/trxjs-lib-app.js` (TronWeb) - the derivation half of iOS `TronJSBridge.swift`.
 *
 * Every TronWeb entry point of the bundle takes a node URL first, and the bundle creates its `tronWeb` instance **once
 * per page with the node of the first call** (`createTronWebIfNotExists`). The functions this repository uses
 * (address derivation here, `signTx` / `multiSignTx` in `:signing`) send no request; the node only has to be a URL
 * TronWeb accepts. The host app supplies it ([setTronNode]; Ownbit passes its configured TRON node, which the app's
 * network-facing code also uses) — this repository contains no node address. When the node changes, the TRX page is
 * restarted before its next call so TronWeb is re-created with it.
 *
 * @param initialNode the node URL handed to TronWeb until [setTronNode] changes it.
 */
class TronJsBridge(private val manager: JsEngineManager, initialNode: String) : JsBridge(manager, JsBundle.TRX) {

    @Volatile
    private var configuredNode: String = initialNode.trim()

    /** The node handed to TronWeb by default (trimmed). */
    val tronNode: String get() = configuredNode

    /**
     * Sets the node handed to TronWeb. Blank values are ignored. When the node changes, the TRX page is restarted
     * before its next call (a call in flight is not disturbed) so TronWeb is re-created with the new node.
     */
    fun setTronNode(node: String) {
        val trimmed = node.trim()
        if (trimmed.isEmpty() || trimmed == configuredNode) return
        configuredNode = trimmed
        manager.restart(JsBundle.TRX)
    }

    /**
     * `bridge.getAddress(tronNode, privateKeyHex)`: `[hex41Address, base58Address]` of a private key
     * (iOS `getPublicKeyAndAddress(privateKey:)`; a leading `0x` is stripped first, as iOS).
     */
    suspend fun getAddressFromPrivateKey(privateKeyHex: String, tronNode: String = this.tronNode): TronAddress {
        val v = strings(BRIDGE + "getAddress", 2, tronNode.trim(), strip0x(privateKeyHex))
        return TronAddress(hexAddress = v[0], base58Address = v[1])
    }

    /**
     * `bridge.getBase58AddrFromHex(tronNode, hex)`: accepts `41...` or an ETH `0x...` address (the
     * `0x` is replaced by `41`), which is how iOS maps ETH account N > 0 to a TRON address
     * (`TronWalletModel.useAddrOnIndexNo`).
     */
    suspend fun getAddressFromHex(hexAddress: String, tronNode: String = this.tronNode): TronAddress {
        val v = strings(BRIDGE + "getBase58AddrFromHex", 2, tronNode.trim(), hexAddress)
        return TronAddress(hexAddress = v[0], base58Address = v[1])
    }

    /** `bridge.isAddress(tronNode, address)`. */
    suspend fun isAddress(address: String, tronNode: String = this.tronNode): Boolean =
        bool(BRIDGE + "isAddress", tronNode.trim(), address)
}
