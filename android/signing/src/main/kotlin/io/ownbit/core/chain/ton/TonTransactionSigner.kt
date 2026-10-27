// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.chain.ton

import io.ownbit.core.jsengine.JsArgs
import io.ownbit.core.jsengine.JsBundle
import io.ownbit.core.jsengine.JsEngineManager
import io.ownbit.core.jsengine.JsEventSpec
import io.ownbit.core.jsengine.JsResultFormatException
import java.util.Base64

/**
 * Typed access to the TON bundle's transfer functions (iOS `TonJSBridge.buildTonTransaction`, bundle `tonjs-new.js`,
 * tonweb wallet v4R2). Both functions derive the key from the BIP39 **words**, build the external message with the
 * given seqno / `expireAt` (no network) and post `"<txHash>:<bocBase64>"` on `transaction` (the patched
 * `sendBoc` never broadcasts); failures post on `error`.
 */
class TonTransactionSigner(private val manager: JsEngineManager) {

    /** A signed TON external message. */
    data class SignedBoc(val txHash: String, val boc: String)

    /**
     * `bridge.sendTonTx(mnemonic, to, amount, seqno, memo, expireAt)`: [amountWhole] is decimal TON (e.g. "0.04");
     * the bounce flag follows the address form the user entered; [memo] becomes a TEP-74 text comment.
     */
    suspend fun signTonTransfer(
        mnemonic: CharArray,
        to: String,
        amountWhole: String,
        seqno: Long,
        memo: String,
        expireAt: Long,
    ): SignedBoc = sign("sendTonTx", JsArgs.of(mnemonic, to, amountWhole, seqno, memo, expireAt))

    /**
     * `bridge.sendTokenTx(mnemonic, senderJettonWallet, to, jettonMaster, receiverState, amount, seqno, memo,
     * expireAt)`: 0.1 TON to the sender's (bounceable) jetton wallet carrying the transfer to [to]'s main wallet,
     * forward amount chosen by the bundle from [receiverState]; [amountInteger] = jetton base units, integer.
     */
    suspend fun signJettonTransfer(
        mnemonic: CharArray,
        senderJettonWallet: String,
        to: String,
        jettonMaster: String,
        receiverState: Int,
        amountInteger: String,
        seqno: Long,
        memo: String,
        expireAt: Long,
    ): SignedBoc = sign(
        "sendTokenTx",
        JsArgs.of(mnemonic, senderJettonWallet, to, jettonMaster, receiverState, amountInteger, seqno, memo, expireAt),
    )

    private suspend fun sign(function: String, args: kotlinx.serialization.json.JsonArray): SignedBoc {
        val event = manager.engine(JsBundle.TON).callForEvent("bridge.$function", args, JsEventSpec.of(CHANNEL_TRANSACTION))
        return parse(event.payload) ?: throw JsResultFormatException(JsBundle.TON, function, "\"<txHash>:<boc>\"")
    }

    companion object {
        const val CHANNEL_TRANSACTION: String = "transaction"

        /** iOS splits the payload on ":" and requires exactly two parts (hex cell hash, base64 BOC). */
        fun parse(payload: String): SignedBoc? {
            val parts = payload.trim().split(':')
            if (parts.size != 2) return null
            val (hash, boc) = parts
            if (hash.length != 64 || hash.any { Character.digit(it, 16) < 0 }) return null
            if (boc.isEmpty() || runCatching { Base64.getDecoder().decode(boc) }.isFailure) return null
            return SignedBoc(hash.lowercase(), boc)
        }
    }
}
