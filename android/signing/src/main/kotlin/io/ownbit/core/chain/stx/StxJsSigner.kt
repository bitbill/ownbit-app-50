// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.chain.stx

import io.ownbit.core.jsengine.JsArgs
import io.ownbit.core.jsengine.JsBundle
import io.ownbit.core.jsengine.JsEngineManager
import io.ownbit.core.jsengine.JsEventSpec
import io.ownbit.core.jsengine.JsResultFormatException

/**
 * Signing half of iOS `StackJSBridge.swift` over `js/stx/stxjs-new.js` (@stacks/transactions):
 * `bridge.sendToken(privHex, to, microStx, memo, nonce)` — `amount` and `memo` are strings, `nonce` a JS number.
 * The async function builds a mainnet STX token transfer with `fee: 5000`, `AnchorMode.Any`, signs it and posts the
 * serialized transaction (hex) on the `transaction` channel; a rejection (e.g. memo > 34 bytes) fails fast. The key
 * is the ETH `m/44'/60'/0'/0/0` private key (iOS `StackWalletModel`). Deterministic (RFC 6979), offline.
 */
internal class StxJsSigner(private val engines: JsEngineManager) {

    suspend fun sendToken(
        privateKeyHex: String,
        to: String,
        amountMicro: String,
        memo: String,
        nonce: Long,
        timeoutMillis: Long = SIGN_TIMEOUT_MILLIS,
    ): String {
        val event = engines.engine(JsBundle.STX).callForEvent(
            FUNCTION,
            JsArgs.of(privateKeyHex, to, amountMicro, memo, nonce),
            JsEventSpec.of(TRANSACTION_CHANNEL),
            timeoutMillis,
        )
        if (event.payload.isEmpty()) throw JsResultFormatException(JsBundle.STX, FUNCTION, "serialized tx hex")
        return event.payload
    }

    internal companion object {
        const val FUNCTION = "bridge.sendToken"
        const val TRANSACTION_CHANNEL = "transaction"
        const val SIGN_TIMEOUT_MILLIS: Long = 60_000
    }
}
