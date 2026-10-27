// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.chain.utxo

import io.ownbit.core.chain.json.looseLong
import io.ownbit.core.chain.json.looseString
import io.ownbit.core.chain.json.objects
import kotlinx.serialization.json.JsonObject

/**
 * Android safety check between JS signing and broadcast (iOS broadcasts whatever the bundle returns): the signed
 * transaction must decode, spend exactly the `signDatas` inputs (same outpoints, same order), pay exactly the
 * `signDatas` output amounts (same order; BTC puts the OP_RETURN output first) and carry the requested lock time.
 * When the bundle returned a tx id it must equal the id of the returned hex.
 *
 * Output **scripts** are not compared with the planned addresses (that would need per-chain Base58 / bech32 /
 * CashAddr / ZEN replay-script decoding): the check guards amounts, inputs and ids, not the destinations.
 *
 * ZEC: the requested format is enforced too (v5 header fields from `signDatas`, or v4 without them).
 *
 * Returns the transaction hash to use — the bundle's id when it returned one (iOS `tx.txHash = result.txId`),
 * otherwise the double-SHA-256 of the hex (iOS `BTCTransaction(hex:)`, BCH / LTC) — or `null` when the signed
 * transaction does not match the request (never broadcast it then).
 */
object UtxoSignedTxVerifier {

    fun verify(profile: UtxoChainProfile, signDatas: JsonObject, raw: UtxoSignedRaw): String? {
        val tx = RawUtxoTransaction.decode(raw.rawHex) ?: return mismatch()
        if (raw.txId != null && !raw.txId.equals(tx.txId, ignoreCase = true)) return mismatch()

        val expectedInputs = signDatas.objects("inputs").map { i ->
            val txid = (i["txHash"] ?: i["txid"]).looseString().lowercase()
            val vout = (i["index"] ?: i["vout"]).looseLong()
            "$txid:$vout"
        }
        if (expectedInputs.isEmpty() || expectedInputs != tx.inputs.map { it.outpoint.lowercase() }) return mismatch()

        var outputs = tx.outputs
        val opHex = signDatas["ophex"].looseString()
        if (profile.btcStyleSignDatas && opHex.isNotEmpty() && profile == UtxoChainProfile.BTC) {
            val first = outputs.firstOrNull() ?: return mismatch()
            val data = first.opReturnData ?: return mismatch()
            if (first.value != 0L || !RawUtxoTransaction.toHex(data).equals(opHex, ignoreCase = true)) return mismatch()
            outputs = outputs.drop(1)
        }
        val expectedValues = signDatas.objects("outputs").map { (it[profile.outputAmountKey] ?: it["amount"]).looseLong() }
        if (expectedValues != outputs.map { it.value }) return mismatch()

        val lockTime = signDatas["locktime"].looseLong()
        if (profile == UtxoChainProfile.BTC && lockTime > 0 && tx.lockTime != lockTime) return mismatch()

        if (profile == UtxoChainProfile.ZEC && !zecFormatMatches(signDatas, tx)) return mismatch()

        return raw.txId ?: tx.txId
    }

    /**
     * ZEC: the bundle must have produced the requested format — v5 with exactly the requested
     * branch id / lock time / expiry height when `zecTxVersion == 5` (its txid is then the ZIP 244 digest, recomputed
     * by [RawUtxoTransaction] and compared with the bundle's above), sapling v4 otherwise.
     */
    private fun zecFormatMatches(signDatas: JsonObject, tx: RawUtxoTransaction): Boolean {
        if (!tx.overwintered) return false
        if (ZecSignFields.txVersion(signDatas) != 5) return tx.version == 4L
        return tx.version == 5L &&
            tx.versionGroupId == ZcashV5.VERSION_GROUP_ID &&
            tx.consensusBranchId == signDatas[ZecSignFields.BRANCH_ID].looseLong() &&
            tx.lockTime == signDatas[ZecSignFields.LOCK_TIME].looseLong() &&
            tx.expiryHeight == signDatas[ZecSignFields.EXPIRY_HEIGHT].looseLong()
    }

    private fun mismatch(): String? = null
}
