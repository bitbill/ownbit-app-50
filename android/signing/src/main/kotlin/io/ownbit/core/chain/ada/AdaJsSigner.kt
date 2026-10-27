// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.chain.ada

import io.ownbit.core.jsengine.JsArgs
import io.ownbit.core.jsengine.JsBundle
import io.ownbit.core.jsengine.JsEngineManager
import io.ownbit.core.jsengine.JsEventSpec
import io.ownbit.core.jsengine.JsResultFormatException

/**
 * Signing half of iOS `AdaJSBridge.swift` over `js/ada/shelley.bundle.js` (AdaLite, patched by Ownbit):
 * `sendTx(entropyHex, myAddress, toAddress, lovelace, utxoJson)`.
 *
 * The bundle loads the wallet from the BIP39 **entropy**, plans the transaction from the given UTXOs (change goes to
 * `myAddress`; an empty `myAddress` makes it return immediately without any callback), signs it and posts
 * `"<signedTxCborHex>:<txHash>"` on the `transaction` channel. Plan / signing errors are **not** reported (no
 * failure callback), so only the timeout ends a failed call — hence the long [SIGN_TIMEOUT_MILLIS]. The TTL comes
 * from the explorer's best slot, falling back to a time-based slot offline.
 */
internal class AdaJsSigner(private val engines: JsEngineManager) {

    suspend fun sendTx(
        entropyHex: String,
        changeAddress: String,
        toAddress: String,
        lovelace: Long,
        utxosJson: String,
        timeoutMillis: Long = SIGN_TIMEOUT_MILLIS,
    ): AdaSignature {
        val event = engines.engine(JsBundle.ADA).callForEvent(
            FUNCTION,
            JsArgs.of(entropyHex, changeAddress, toAddress, lovelace, utxosJson),
            JsEventSpec.of(TRANSACTION_CHANNEL),
            timeoutMillis,
        )
        // iOS: result.split{$0 == ":"} (empty pieces dropped), exactly two parts.
        val parts = event.payload.split(':').filter { it.isNotEmpty() }
        if (parts.size != 2) throw JsResultFormatException(JsBundle.ADA, FUNCTION, "signedTx:txHash")
        return AdaSignature(signedTxCbor = parts[0], txHash = parts[1])
    }

    internal companion object {
        const val FUNCTION = "sendTx"
        const val TRANSACTION_CHANNEL = "transaction"

        /** ADA planning + signing in AdaLite takes seconds; failures are silent, so allow two minutes. */
        const val SIGN_TIMEOUT_MILLIS: Long = 120_000
    }
}

/** Result of `sendTx`: the signed transaction (CBOR hex, iOS `hexTx`) and its hash. */
internal data class AdaSignature(val signedTxCbor: String, val txHash: String)
