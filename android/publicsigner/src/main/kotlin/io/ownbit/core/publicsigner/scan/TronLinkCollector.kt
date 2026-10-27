// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.publicsigner.scan

import io.ownbit.core.publicsigner.text.PublicSignError
import io.ownbit.core.scanner.publicqr.TronLinkFrame
import io.ownbit.core.scanner.publicqr.TronLinkQrFormat
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * A complete TronLink request, from one QR or reassembled from its parts.
 *
 * @property bean the request object the answer echoes: the scanned JSON of a single QR as it is; for a split request
 *   the reassembled one — `address` of part 1, `type` / `alpha` / `tokenId` of the last part, every other key of the
 *   parts in first-seen order, `cN` / `tN` removed, `hexList` = the joined entries.
 * @property hexList the entries (transactions as hex of a full `Transaction`, or the message of a message type).
 * @property type TronLink's page type.
 * @property address the account the request is for (`null` when TronLink sent none: refused by the mapper).
 * @property wasSplit it came in numbered parts.
 */
class TronLinkRequest(
    val bean: JsonObject,
    val hexList: List<String>,
    val type: Int,
    val address: String?,
    val alpha: String?,
    val tokenId: String?,
    val wasSplit: Boolean,
) {
    override fun toString(): String = "TronLinkRequest(type=$type, entries=${hexList.size}, split=$wasSplit)"

    companion object {
        /** The request of one complete (unsplit) QR. */
        fun of(frame: TronLinkFrame): TronLinkRequest {
            require(!frame.isPart) { "a part is not a request" }
            return TronLinkRequest(frame.json, frame.hexList, frame.type, frame.address, frame.alpha, frame.tokenId, wasSplit = false)
        }
    }
}

/**
 * Reassembles one TronLink request from its QR frames — pure Kotlin, no engine. A single QR
 * completes at once. Parts (`cN` of `tN`, 2 ≤ `tN` ≤ [MAX_PARTS]) may come in any order (better than TronLink's own
 * strictly ordered reader); a repeat is ignored. Refused as another request ([OtherWalletRequestException.Kind.OTHER_REQUEST]):
 * the same `cN` with another text, another `tN`, a single QR after a part, the first and last parts naming different
 * addresses. Limits: one piece ≤ [MAX_PIECE_CHARS], the joined text ≤ [TronLinkQrFormat.MAX_REQUEST_CHARS].
 *
 * Join: the pieces in `cN` order, concatenated, split at `&&&` (TronLink appends `&&&` after every entry; one trailing
 * empty element is dropped, no other empty entry is accepted). Not thread-safe; one per scan / paste. Nothing logged.
 */
class TronLinkCollector {

    /** The result of [add]. */
    sealed interface Step {
        /** [received] of [total] parts so far. */
        data class Partial(val received: Int, val total: Int) : Step

        data class Complete(val request: TronLinkRequest) : Step
    }

    private var total = 0
    private val pieces = HashMap<Int, TronLinkFrame>()

    /** Parts received so far (0 before the first). */
    val received: Int get() = pieces.size

    /** Adds one frame; throws [OtherWalletRequestException] for a frame of another request or beyond the limits. */
    fun add(frame: TronLinkFrame): Step {
        if (!frame.isPart) {
            if (pieces.isNotEmpty()) throw other()
            return Step.Complete(TronLinkRequest.of(frame))
        }
        val tN = frame.tN!!
        val cN = frame.cN!!
        if (tN > MAX_PARTS) throw tooLarge()
        if (total != 0 && tN != total) throw other()
        val piece = frame.hexList.single()
        if (piece.length > MAX_PIECE_CHARS) throw tooLarge()
        val seen = pieces[cN]
        if (seen != null) {
            if (seen.hexList.single() != piece || seen.json != frame.json) throw other()
            return Step.Partial(pieces.size, total)
        }
        total = tN
        pieces[cN] = frame
        if (pieces.size < total) return Step.Partial(pieces.size, total)
        return Step.Complete(join())
    }

    private fun join(): TronLinkRequest {
        val ordered = (1..total).map { pieces.getValue(it) }
        val first = ordered.first()
        val last = ordered.last()
        // TronLink writes the address on the first and the last part: they must agree.
        if (first.address != null && last.address != null && first.address != last.address) throw other()
        val joined = StringBuilder()
        for (part in ordered) {
            joined.append(part.hexList.single())
            if (joined.length > TronLinkQrFormat.MAX_REQUEST_CHARS) throw tooLarge()
        }
        var entries = joined.toString().split(SEPARATOR)
        if (entries.size > 1 && entries.last().isEmpty()) entries = entries.dropLast(1)
        if (entries.isEmpty() || entries.any { it.isEmpty() } || entries.size > TronLinkQrFormat.MAX_ENTRIES) throw malformed()
        val address = first.address ?: last.address
        val bean = LinkedHashMap<String, kotlinx.serialization.json.JsonElement>()
        for (part in ordered) {
            for ((key, value) in part.json) {
                if (key == "cN" || key == "tN" || key == "hexList" || key in bean) continue
                bean[key] = value
            }
        }
        // The fields of the request itself come from where TronLink writes them.
        if (address != null) bean["address"] = JsonPrimitive(address)
        for (key in LAST_PART_KEYS) {
            val value = last.json[key]
            if (value != null) bean[key] = value else bean.remove(key)
        }
        bean["hexList"] = JsonArray(entries.map(::JsonPrimitive))
        return TronLinkRequest(JsonObject(bean), entries, last.type, address, last.alpha, last.tokenId, wasSplit = true)
    }

    private fun other() = OtherWalletRequestException(
        OtherWalletRequestException.Kind.OTHER_REQUEST,
        PublicSignError("publicprotocol_scan_otherrequest", code = "OTHER_REQUEST"),
    )

    private fun tooLarge() = OtherWalletRequestException(
        OtherWalletRequestException.Kind.TOO_LARGE,
        PublicSignError("publicprotocol_err_toolarge", code = "LIMIT"),
    )

    private fun malformed() = OtherWalletRequestException(
        OtherWalletRequestException.Kind.MALFORMED,
        PublicSignError("publicprotocol_err_qrmalformed", code = "MALFORMED"),
    )

    override fun toString(): String = "TronLinkCollector(received=${pieces.size}, total=$total)"

    companion object {
        /** Parts of one request (the gate's `MAX_TRONLINK_PARTS`). */
        const val MAX_PARTS: Int = 64

        /** Characters of one part's piece (TronLink cuts at 1000). */
        const val MAX_PIECE_CHARS: Int = 4_096

        /** TronLink's entry separator. */
        const val SEPARATOR: String = "&&&"

        /** Keys TronLink writes on the last part only (`type` is `0` on the others). */
        private val LAST_PART_KEYS = listOf("type", "alpha", "tokenId")
    }
}
