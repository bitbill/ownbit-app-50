// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.chain.utxo

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * Strict reading of the numbers a UTXO bundle signs with. The bundles get `signDatas`
 * as JSON **text** and `JSON.parse` it, so a value Kotlin reads one way can reach the bundle as another number:
 * `"satoshis": 100000.0000000000000000001` is `100000` in JS (a SegWit input would be signed for that amount) while an
 * exact Kotlin reader refuses it, and integers above 2^53 are rounded by JS. Everything Kotlin checks an input or an
 * output by (the signed-outpoint memory, the review page, [UtxoSignedTxVerifier]) must be the number the bundle signs.
 *
 * Rules, per input ([UtxoChainProfile.inputStyle]: `txHash` / `index` / `satoshis` for BTC, `txid` / `vout` /
 * `satoshis` for the others) and per output (`[UtxoChainProfile.outputAmountKey]`):
 * - the txid is a JSON **string** of exactly 64 hex digits (no `0x`, no blanks);
 * - the index and every amount are JSON **number** tokens of plain decimal digits (no sign, fraction, exponent or
 *   leading zero; a numeric string, a boolean, `null` or a missing key is refused), the index in `0…0xFFFFFFFF`, an
 *   amount in `0…2^53 − 1` (exact in JS);
 * - `inputs` is a non-empty array of objects, `outputs` an array of objects.
 *
 * Anything else refuses the **whole** request (never "skip the input"): a skipped input would still be signed by the
 * bundle. [canonical] rewrites the values as Kotlin read them (txid lower case, integers as JSON integers), so the text
 * the bundle parses carries exactly the checked numbers; every other key is kept as it is.
 *
 * Pure; never logs values.
 */
object UtxoSignDatas {

    /** One input as Kotlin and the bundle both read it: [txid] lower-case hex as explorers write it. */
    class Input(val txid: String, val vout: Long, val satoshis: Long) {
        override fun toString(): String = "Input"
    }

    /** Largest integer JS represents exactly (`Number.MAX_SAFE_INTEGER`). */
    const val MAX_SAFE_INTEGER: Long = 9_007_199_254_740_991L

    /** Largest output index of a transaction (`u32`). */
    const val MAX_VOUT: Long = 0xFFFF_FFFFL

    private val DIGITS = Regex("0|[1-9][0-9]*")
    private val TXID = Regex("[0-9a-fA-F]{64}")

    /** The inputs of [signDatas] in order, or `null` when any input (or the list) cannot be read strictly. */
    fun inputs(profile: UtxoChainProfile, signDatas: JsonObject): List<Input>? {
        val array = signDatas[INPUTS] as? JsonArray ?: return null
        if (array.isEmpty()) return null
        val (txidKey, voutKey) = inputKeys(profile)
        return array.map { element ->
            val input = element as? JsonObject ?: return null
            val txid = txid(input[txidKey]) ?: return null
            val vout = integer(input[voutKey], MAX_VOUT) ?: return null
            val sats = integer(input[SATOSHIS], MAX_SAFE_INTEGER) ?: return null
            Input(txid, vout, sats)
        }
    }

    /**
     * [signDatas] with every input's txid / index / amount and every output's amount rewritten exactly as read (see
     * the class rules), or `null` when any of them cannot be read strictly.
     */
    fun canonical(profile: UtxoChainProfile, signDatas: JsonObject): JsonObject? {
        val inputs = inputs(profile, signDatas) ?: return null
        val rawOutputs = signDatas[OUTPUTS] as? JsonArray ?: return null
        val (txidKey, voutKey) = inputKeys(profile)
        val rawInputs = signDatas[INPUTS] as JsonArray
        if (rawInputs.size != inputs.size) return null
        val canonicalInputs = rawInputs.mapIndexed { i, element ->
            val read = inputs[i]
            JsonObject(
                (element as JsonObject) +
                    (txidKey to JsonPrimitive(read.txid)) +
                    (voutKey to JsonPrimitive(read.vout)) +
                    (SATOSHIS to JsonPrimitive(read.satoshis)),
            )
        }
        val amountKey = profile.outputAmountKey
        val canonicalOutputs = rawOutputs.map { element ->
            val output = element as? JsonObject ?: return null
            val amount = integer(output[amountKey], MAX_SAFE_INTEGER) ?: return null
            JsonObject(output + (amountKey to JsonPrimitive(amount)))
        }
        return JsonObject(signDatas + (INPUTS to JsonArray(canonicalInputs)) + (OUTPUTS to JsonArray(canonicalOutputs)))
    }

    private fun inputKeys(profile: UtxoChainProfile): Pair<String, String> = when (profile.inputStyle) {
        UtxoChainProfile.InputStyle.BTC -> "txHash" to "index"
        UtxoChainProfile.InputStyle.SCRIPT -> "txid" to "vout"
    }

    private fun txid(value: Any?): String? {
        val p = value as? JsonPrimitive ?: return null
        if (p is JsonNull || !p.isString || !TXID.matches(p.content)) return null
        return p.content.lowercase()
    }

    /** A JSON number token of plain digits in `0…max`; anything else `null`. */
    private fun integer(value: Any?, max: Long): Long? {
        val p = value as? JsonPrimitive ?: return null
        if (p is JsonNull || p.isString) return null
        val text = p.content
        if (!DIGITS.matches(text) || text.length > 19) return null
        return text.toLongOrNull()?.takeIf { it <= max }
    }

    private const val INPUTS = "inputs"
    private const val OUTPUTS = "outputs"
    private const val SATOSHIS = "satoshis"
}
