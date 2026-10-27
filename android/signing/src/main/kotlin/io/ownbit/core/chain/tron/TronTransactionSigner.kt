// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.chain.tron

import io.ownbit.core.jsengine.JsArgs
import io.ownbit.core.jsengine.JsBundle
import io.ownbit.core.jsengine.JsEngineManager
import io.ownbit.core.jsengine.JsEventSpec
import io.ownbit.core.jsengine.JsResultFormatException
import io.ownbit.core.jsengine.JsResults
import io.ownbit.core.jsengine.bridge.TronJsBridge

/**
 * Typed access to the signing half of the TRX bundle (iOS `TronJSBridge.swift`: `buildTrxTransaction`,
 * `buildTrxSigForMultiSig`) and to the iOS `tronSignMessage` bundle ([JsBundle.TRX_MESSAGE], iOS
 * `XemJSBridge.tronSignMessage`).
 *
 * The bundle is the iOS `trxjs-lib-app.js`: async results arrive on the `signed` / `multiSigned` channels, failures on
 * `error`; [JsEngineManager]'s `callForEvent` pairs them with the call (the iOS `pendingAsyncJsHexTx` race cannot
 * happen). Every function passes the node of [TronJsBridge.tronNode] first, like iOS; signing sends nothing to it.
 * Private keys are hex without `0x`; they are never logged.
 *
 * Not part of this repository: the app's `preSendTx` / `extendTxForWc` calls, which ask a TRON node to build or extend
 * the unsigned transaction. Whatever builds it, verify it with [TronTransactionVerifier] before signing.
 */
class TronTransactionSigner(
    private val manager: JsEngineManager,
    private val tronJs: TronJsBridge,
) {
    private val engine get() = manager.engine(JsBundle.TRX)

    /**
     * `bridge.signTx(node, privHex, txJson)` → signed transaction JSON on `signed` (iOS `buildTrxTransaction`). TronWeb
     * refuses (on `error`) a transaction whose owner is not the key's address.
     */
    suspend fun signTx(privateKeyHex: String, txJson: String): String {
        val event = engine.callForEvent(
            BRIDGE + "signTx",
            JsArgs.of(tronJs.tronNode.trim(), privateKeyHex.removePrefix("0x"), txJson),
            JsEventSpec.of(CHANNEL_SIGNED),
        )
        if (event.payload.isBlank()) throw JsResultFormatException(JsBundle.TRX, "signTx", "signed transaction JSON")
        return event.payload
    }

    /** `bridge.multiSignTx(node, privHex, txJson)` → this owner's signature hex on `multiSigned` (multisig / WalletConnect multisig). */
    suspend fun multiSignTx(privateKeyHex: String, txJson: String): String {
        val event = engine.callForEvent(
            BRIDGE + "multiSignTx",
            JsArgs.of(tronJs.tronNode.trim(), privateKeyHex.removePrefix("0x"), txJson),
            JsEventSpec.of(CHANNEL_MULTI_SIGNED),
        )
        if (event.payload.isBlank()) throw JsResultFormatException(JsBundle.TRX, "multiSignTx", "signature hex")
        return event.payload
    }

    /**
     * iOS `XemJSBridge.tronSignMessage(privKey, msg)` (bundle [JsBundle.TRX_MESSAGE]): sha256 of the UTF-8 [message],
     * canonical secp256k1 signature, returned as `0x` + r‖s‖v (v = 27/28). WalletConnect `tron_signMessage`.
     */
    suspend fun signMessage(privateKeyHex: String, message: String): String {
        val fn = BRIDGE + "tronSignMessage"
        val result = manager.engine(JsBundle.TRX_MESSAGE).call(fn, JsArgs.of(privateKeyHex.removePrefix("0x"), message))
        val sig = JsResults.nonEmptyString(result, JsBundle.TRX_MESSAGE, fn)
        if (!SIGNATURE_RE.matches(sig)) throw JsResultFormatException(JsBundle.TRX_MESSAGE, fn, "0x + 65-byte hex")
        return sig
    }

    companion object {
        private const val BRIDGE = "bridge."
        const val CHANNEL_SIGNED: String = "signed"
        const val CHANNEL_MULTI_SIGNED: String = "multiSigned"

        private val SIGNATURE_RE = Regex("^0x[0-9a-fA-F]{130}$")
    }
}
