// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.chain.fil

import io.ownbit.core.jsengine.JsArgs
import io.ownbit.core.jsengine.JsBundle
import io.ownbit.core.jsengine.JsEngineManager
import io.ownbit.core.jsengine.JsResults

/**
 * Signing half of iOS `FilJSBridge.swift` over `js/fil/filjs-lib-app.js` (filecoin-signing-tools, byte-identical to
 * iOS): `bridge.sendTxBySeed(seedHex, to, attoFil, nonce)` (key `m/44'/461'/0'/0/0`) /
 * `bridge.sendTxByPrivKey(key, to, attoFil, nonce)`. `amount` is a decimal **string**, `nonce` a JS **number**.
 * Returns the signed message as pretty-printed JSON `{"message": {to, from, nonce, value, gaslimit, gasfeecap,
 * gaspremium, method, params}, "signature": {data, type}}` — the `hexTx` the server broadcasts. Deterministic, offline.
 */
internal class FilJsSigner(private val engines: JsEngineManager) {

    suspend fun signWithSeed(seedHex: CharArray, to: String, amountAtto: String, nonce: Long): String =
        sign("bridge.sendTxBySeed", seedHex, to, amountAtto, nonce)

    suspend fun signWithPrivateKey(privateKey: CharArray, to: String, amountAtto: String, nonce: Long): String =
        sign("bridge.sendTxByPrivKey", privateKey, to, amountAtto, nonce)

    private suspend fun sign(function: String, key: CharArray, to: String, amount: String, nonce: Long): String {
        val result = engines.engine(JsBundle.FIL).call(function, JsArgs.of(key, to, amount, nonce))
        return JsResults.nonEmptyString(result, JsBundle.FIL, function)
    }
}
