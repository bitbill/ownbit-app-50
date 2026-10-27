// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.publicsigner.model

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.longOrNull

/**
 * A result of the engine that does not have the shape this app relies on (missing frames, a `ready` plan without a
 * plan hash, …). The message names only the part that failed — never a payload, address or key — so it may be logged.
 * Callers treat it like an integrity failure: nothing is shown as signable, nothing is signed.
 */
class MalformedEngineResultException(val what: String) : RuntimeException("Malformed engine result: $what")

/** Fails with [MalformedEngineResultException] naming [what] unless [condition] holds. */
internal inline fun ensureEngine(condition: Boolean, what: () -> String) {
    if (!condition) throw MalformedEngineResultException(what())
}

/*
 * Strictly typed readers in the spirit of BitSigner's `raw["x"] as? String`: a value of another JSON type reads as
 * absent (a number is never a string, a string is never a number), so a changed engine shape fails closed instead of
 * being coerced.
 */

internal fun JsonObject.str(key: String): String? = (this[key] as? JsonPrimitive)?.takeIf { it.isString }?.content

internal fun JsonObject.long(key: String): Long? = (this[key] as? JsonPrimitive)?.takeIf { !it.isString }?.longOrNull

internal fun JsonObject.int(key: String): Int? = long(key)?.takeIf { it in Int.MIN_VALUE..Int.MAX_VALUE }?.toInt()

internal fun JsonObject.bool(key: String): Boolean? = (this[key] as? JsonPrimitive)?.takeIf { !it.isString }?.booleanOrNull

internal fun JsonObject.obj(key: String): JsonObject? = this[key] as? JsonObject

internal fun JsonObject.arr(key: String): JsonArray? = this[key] as? JsonArray

/** A list that is all strings, else `null` (BitSigner `as? [String]`). */
internal fun JsonObject.strings(key: String): List<String>? {
    val array = arr(key) ?: return null
    return array.map { (it as? JsonPrimitive)?.takeIf { p -> p.isString }?.content ?: return null }
}

/** A list that is all integers, else `null`. */
internal fun JsonObject.ints(key: String): List<Int>? {
    val array = arr(key) ?: return null
    return array.map { element ->
        (element as? JsonPrimitive)?.takeIf { !it.isString }?.longOrNull?.takeIf { it in Int.MIN_VALUE..Int.MAX_VALUE }
            ?.toInt() ?: return null
    }
}

/** `true` for a non-empty lower- or upper-case hex string of exactly [bytes] bytes. */
internal fun isHex(value: String?, bytes: Int): Boolean =
    value != null && value.length == bytes * 2 && value.all { it in '0'..'9' || it in 'a'..'f' || it in 'A'..'F' }

/** The text of a review field value: strings as they are, anything else in its JSON form (BitSigner `String(describing:)`). */
internal fun JsonElement.displayText(): String = when (this) {
    JsonNull -> ""
    is JsonPrimitive -> if (isString) content else toString()
    else -> toString()
}
