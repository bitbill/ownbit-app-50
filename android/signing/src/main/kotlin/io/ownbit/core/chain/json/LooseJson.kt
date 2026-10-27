// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.chain.json

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/*
 * Lenient JSON readers mirroring SwiftyJSON's `stringValue` / `int64Value` semantics that the iOS code relies on. They
 * never throw: a missing key or a type mismatch yields the "zero" value. (In the app they live in the network module
 * next to the server models; only these pure functions are needed here.) Amounts that are signed are read strictly
 * instead ([io.ownbit.core.chain.utxo.UtxoSignDatas]).
 */

/** SwiftyJSON `stringValue`: string as-is, numbers/booleans as their literal, anything else (null/object/array) → "". */
fun JsonElement?.looseString(): String = when (this) {
    null, JsonNull -> ""
    is JsonPrimitive -> content
    else -> ""
}

/**
 * SwiftyJSON `int64Value`: integral numbers and numeric strings are parsed (a fractional part is truncated),
 * booleans become 1/0, everything else → 0.
 */
fun JsonElement?.looseLong(): Long = looseLongOrNull() ?: 0L

/** [looseLong] that distinguishes "absent / not numeric" (`null`) from 0 — the SwiftyJSON `int64` optional. */
fun JsonElement?.looseLongOrNull(): Long? {
    val primitive = this as? JsonPrimitive ?: return null
    if (primitive is JsonNull) return null
    val text = primitive.content.trim()
    if (!primitive.isString) {
        when (text) {
            "true" -> return 1L
            "false" -> return 0L
        }
    }
    text.toLongOrNull()?.let { return it }
    return text.toBigDecimalOrNull()?.let { runCatching { it.toBigInteger().toLong() }.getOrNull() }
}

/** The objects of the array under [key]; non-object entries are skipped, a missing / non-array value is empty. */
fun JsonObject.objects(key: String): List<JsonObject> = ((this[key] as? JsonArray) ?: emptyList()).filterIsInstance<JsonObject>()
