// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.scanner.publicqr

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * One QR of TronLink's cold-wallet protocol: a JSON object
 * `{"address", "type", "hexList": [...], …}`, or one numbered part of a split one (`cN` 1-based, `tN` parts).
 *
 * @property json the object exactly as scanned (key order and number literals kept: the answer echoes it).
 * @property hexList the entries (a full `Transaction` protobuf as hex, a message, or — in a part — one piece of
 *   `h1&&&h2&&&…`).
 * @property type TronLink's page type (`0` when absent: the first parts of a split request carry none).
 * @property address the account the request is for (single requests, first and last parts).
 * @property cN / [tN] the part number and part count (`0` / `0` in an Android single request, absent on iOS).
 * @property alpha / [tokenId] shielded (TRC-z) fields, refused.
 */
class TronLinkFrame(
    val json: JsonObject,
    val hexList: List<String>,
    val type: Int,
    val address: String?,
    val cN: Int?,
    val tN: Int?,
    val alpha: String?,
    val tokenId: String?,
) {
    /** One part of a split request (`tN ≥ 2`). */
    val isPart: Boolean get() = (tN ?: 0) >= 2

    /** Counts only (the request text is never printed). */
    override fun toString(): String = "TronLinkFrame(type=$type, entries=${hexList.size}, cN=$cN, tN=$tN)"
}

/**
 * Pure classification and parsing of TronLink QR texts. Strict ([StrictJson]: duplicate keys
 * refused); nothing is logged. Disjoint from every other public-protocol prefix and from Ownbit's own `bb_*` codes:
 * TronLink texts start with `{`.
 */
object TronLinkQrFormat {

    /** Entries of one request (TronLink sends 1, 2 for "stake and vote"). */
    const val MAX_ENTRIES: Int = 32

    /** Characters of a reassembled request (128 KiB, the collector's limit). */
    const val MAX_REQUEST_CHARS: Int = 131_072

    /** Longest single QR frame the app's scanner accepts (characters). */
    const val MAX_FRAME_CHARS: Int = 4_300

    /** `true` when [text] (trimmed) has the outer shape of a TronLink QR — a JSON object naming `hexList` (cheap). */
    fun looksLike(text: String): Boolean {
        val t = text.trim()
        return t.length >= 2 && t.first() == '{' && t.last() == '}' && t.contains("\"hexList\"")
    }

    /**
     * [text] (trimmed) as a TronLink frame, or `null` when it is not one: a strict JSON object of at most [maxChars]
     * characters (one QR: [MAX_FRAME_CHARS]; a reassembled request: [MAX_REQUEST_CHARS]) with
     * `hexList` = 1…[MAX_ENTRIES] strings, an integer `type`
     * in `0..Int.MAX_VALUE` (absent → 0), optional string `address`, integer `cN` / `tN` (`0 ≤ cN ≤ tN`, `cN ≥ 1` when
     * `tN ≥ 2`), optional strings `alpha` / `tokenId`. Other keys are kept (echoed) and ignored.
     */
    fun parse(text: String, maxChars: Int = MAX_FRAME_CHARS): TronLinkFrame? {
        val t = text.trim()
        if (t.length > maxChars || !looksLike(t)) return null
        val json = StrictJson.parseObject(t) ?: return null
        val list = json["hexList"] as? JsonArray ?: return null
        if (list.isEmpty() || list.size > MAX_ENTRIES) return null
        val entries = list.map { element ->
            val p = element as? JsonPrimitive ?: return null
            if (!p.isString) return null
            p.content
        }
        val type = if (json.containsKey("type")) int(json["type"]) ?: return null else 0
        val address = if (json.containsKey("address")) string(json["address"]) ?: return null else null
        val cN = if (json.containsKey("cN")) int(json["cN"]) ?: return null else null
        val tN = if (json.containsKey("tN")) int(json["tN"]) ?: return null else null
        if (tN != null && tN >= 2) {
            // A part: its number and exactly one piece of the joined entries.
            if (cN == null || cN < 1 || cN > tN || entries.size != 1) return null
        } else if (cN != null && cN > 1) {
            // A single request (Android writes cN = tN = 0; iOS omits both).
            return null
        }
        val alpha = if (json.containsKey("alpha")) string(json["alpha"]) ?: return null else null
        val tokenId = if (json.containsKey("tokenId")) string(json["tokenId"]) ?: return null else null
        return TronLinkFrame(json, entries, type, address, cN, tN, alpha, tokenId)
    }

    /** A non-negative JSON integer literal that fits an `Int` (no fraction, no exponent, no string). */
    private fun int(element: kotlinx.serialization.json.JsonElement?): Int? {
        val p = element as? JsonPrimitive ?: return null
        if (p.isString) return null
        val c = p.content
        if (c.isEmpty() || c.length > 10 || !c.all { it in '0'..'9' } || (c.length > 1 && c[0] == '0')) return null
        return c.toLongOrNull()?.takeIf { it <= Int.MAX_VALUE }?.toInt()
    }

    private fun string(element: kotlinx.serialization.json.JsonElement?): String? =
        (element as? JsonPrimitive)?.takeIf { it.isString }?.content
}
