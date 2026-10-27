// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.publicsigner.sign

import io.ownbit.core.chain.tron.TronTransactionProto
import io.ownbit.core.crypto.util.Hex
import io.ownbit.core.publicsigner.scan.TronLinkCollector
import io.ownbit.core.publicsigner.scan.TronLinkRequest
import io.ownbit.core.scanner.publicqr.TronLinkQrFormat
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/**
 * Ownbit's answer to a TronLink request — built in Kotlin (the engine's `encodeResponse` has no
 * TronLink profile):
 *
 * - the answer object = the request object ([TronLinkRequest.bean]: same keys, same order, same literal values) with
 *   `hexList` replaced by the signed entries ([answerBean]); a TronLink cold wallet answers with its request bean too;
 * - a transaction entry = the request's `Transaction` bytes ‖ `12 41` ‖ `r ‖ s ‖ recId` (recId 0 / 1), lower-case hex
 *   ([signedTransaction]); a message entry = `"0x" ‖ r ‖ s ‖ v`, v = 27 + recId ([signedMessage]);
 * - one QR when the entries joined with `&&&` (each followed by it) are at most [PART_CHARS] characters, else
 *   `tN = ⌈len / 1000⌉` numbered parts in TronLink's (Gson) field order `address` (first and last part), `cN`,
 *   `hexList` (one 1000-character piece), `tN`, `type` (the request's on the last part, `0` before) — shown as a pager
 *   (TronLink reads them strictly in order). Unlike TronLink's own splitter, exactly 1000 characters stay one QR.
 *
 * [decode] reads frames back with the same parser and collector the scanner uses (the post-check).
 */
object TronLinkAnswerCodec {

    /** Characters of one part's piece (TronLink `QR_LIMIT_SIZE`). */
    const val PART_CHARS: Int = 1_000

    /** The answer object: [bean] with `hexList` = [signed] (key order and every other value kept). */
    fun answerBean(bean: JsonObject, signed: List<String>): JsonObject {
        require(bean.containsKey(HEX_LIST)) { "not a TronLink request" }
        val out = LinkedHashMap(bean)
        out[HEX_LIST] = JsonArray(signed.map(::JsonPrimitive))
        return JsonObject(out)
    }

    /** The QR frames of the answer to [bean] with [signed] entries (see the class documentation). */
    fun encode(bean: JsonObject, signed: List<String>): List<String> {
        require(signed.isNotEmpty() && signed.none { it.isEmpty() || it.contains(TronLinkCollector.SEPARATOR) }) { "signed entries" }
        val joined = signed.joinToString("") { it + TronLinkCollector.SEPARATOR }
        if (joined.length <= PART_CHARS) return listOf(answerBean(bean, signed).toString())
        val address = (bean["address"] as? JsonPrimitive)?.takeIf { it.isString }?.content
        val type = (bean["type"] as? JsonPrimitive)?.takeIf { !it.isString }?.content?.toIntOrNull() ?: 0
        val total = (joined.length + PART_CHARS - 1) / PART_CHARS
        return (1..total).map { i ->
            val piece = joined.substring((i - 1) * PART_CHARS, minOf(i * PART_CHARS, joined.length))
            buildJsonObject {
                if (address != null && (i == 1 || i == total)) put("address", address)
                put("cN", i)
                put(HEX_LIST, JsonArray(listOf(JsonPrimitive(piece))))
                put("tN", total)
                put("type", if (i == total) type else 0)
            }.toString()
        }
    }

    /** `tx ‖ 12 41 ‖ signature` as lower-case hex ([tx] a strict `Transaction`, [signature] 65 bytes). */
    fun signedTransaction(tx: ByteArray, signature: ByteArray): String = Hex.encode(TronTransactionProto.appendSignature(tx, signature))

    /** `"0x" ‖ r ‖ s ‖ v` with v = 27 + recId of a 65-byte `r ‖ s ‖ recId` [signature]. */
    fun signedMessage(signature: ByteArray): String {
        require(signature.size == TronTransactionProto.SIGNATURE_BYTES) { "signature size" }
        val recId = signature[64].toInt() and 0xff
        require(recId == 0 || recId == 1) { "recovery id" }
        return "0x" + Hex.encode(signature, 0, 64) + Hex.encode(byteArrayOf((27 + recId).toByte()))
    }

    /** The answer [frames] read back as one TronLink request object (throws on anything malformed or incomplete). */
    fun decode(frames: List<String>): TronLinkRequest {
        require(frames.isNotEmpty()) { "no frames" }
        val collector = TronLinkCollector()
        var complete: TronLinkRequest? = null
        for ((i, frame) in frames.withIndex()) {
            val parsed = requireNotNull(TronLinkQrFormat.parse(frame)) { "frame $i" }
            val step = collector.add(parsed)
            if (step is TronLinkCollector.Step.Complete) {
                require(i == frames.lastIndex) { "frames after the last part" }
                complete = step.request
            }
        }
        return requireNotNull(complete) { "incomplete answer" }
    }

    private const val HEX_LIST = "hexList"
}
