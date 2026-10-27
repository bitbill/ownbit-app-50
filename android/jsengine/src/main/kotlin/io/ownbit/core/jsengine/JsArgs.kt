// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.jsengine

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.math.BigDecimal
import java.math.BigInteger

/**
 * Builds the JSON argument list of a JS call. Every argument travels as JSON and is `JSON.parse`d in
 * the page - user or secret data never becomes JS source.
 *
 * Supported values: `null`, [String], [CharArray] (converted to a string at the last moment; the caller
 * still owns and should wipe the array), [Boolean], [Int]/[Long]/[Short]/[Byte]/[Double]/[Float],
 * [BigInteger]/[BigDecimal], [JsonElement], [List]/[Array] and [Map] with [String] keys.
 *
 * **Numbers become JS doubles.** A number that a JS double cannot hold exactly would silently change
 * value inside the bundle (e.g. a wei amount above 2^53), so it is rejected with
 * [IllegalArgumentException] instead: integers must lie within ±(2^53 - 1) ([MAX_SAFE_INTEGER]),
 * [BigDecimal]s must survive the round trip through `Double`, and NaN / infinity are refused (they are
 * not JSON). Amounts go to the bundles as **decimal strings**, exactly as iOS passes them
 * (`'\(amountResult)'`).
 *
 * Type fidelity matters: iOS passes e.g. `'\(nonce)'` (a JS *string*) to some functions and `\(nonce)`
 * (a *number*) to others; the typed bridges spell out which.
 */
object JsArgs {

    /** Largest integer a JS number represents exactly (`Number.MAX_SAFE_INTEGER`, 2^53 - 1). */
    const val MAX_SAFE_INTEGER: Long = 9_007_199_254_740_991L

    private val MAX_SAFE_BIG = BigInteger.valueOf(MAX_SAFE_INTEGER)

    /** Empty argument list. */
    val NONE: JsonArray = JsonArray(emptyList())

    /** JSON array of [values], converted as described on [JsArgs]. */
    fun of(vararg values: Any?): JsonArray = JsonArray(values.map(::toJson))

    /** Converts one Kotlin value to its JSON representation. */
    fun toJson(value: Any?): JsonElement = when (value) {
        null -> JsonNull
        is JsonElement -> value
        is String -> JsonPrimitive(value)
        is CharArray -> JsonPrimitive(String(value))
        is Boolean -> JsonPrimitive(value)
        is Int -> JsonPrimitive(value)
        is Short -> JsonPrimitive(value)
        is Byte -> JsonPrimitive(value)
        is Long -> JsonPrimitive(safeInteger(value))
        is Double -> JsonPrimitive(finite(value))
        is Float -> JsonPrimitive(finite(value.toDouble()))
        is BigInteger -> JsonPrimitive(safeInteger(value))
        is BigDecimal -> JsonPrimitive(exactDecimal(value))
        is List<*> -> JsonArray(value.map(::toJson))
        is Array<*> -> JsonArray(value.map(::toJson))
        is Map<*, *> -> JsonObject(
            value.entries.associate { (k, v) ->
                require(k is String) { "JS object keys must be strings" }
                k to toJson(v)
            },
        )
        else -> throw IllegalArgumentException("Unsupported JS argument type: ${value::class.java.name}")
    }

    private fun safeInteger(value: Long): Long {
        require(value in -MAX_SAFE_INTEGER..MAX_SAFE_INTEGER) { UNSAFE_NUMBER }
        return value
    }

    private fun safeInteger(value: BigInteger): BigInteger {
        require(value.abs() <= MAX_SAFE_BIG) { UNSAFE_NUMBER }
        return value
    }

    private fun finite(value: Double): Double {
        require(value.isFinite()) { "NaN / infinity cannot be passed to JS (not JSON)" }
        return value
    }

    /** The value as the JS number it will become, provided that number is exactly [value]. */
    private fun exactDecimal(value: BigDecimal): Double {
        val asDouble = value.toDouble()
        require(asDouble.isFinite() && BigDecimal(asDouble.toString()).compareTo(value) == 0) { UNSAFE_NUMBER }
        if (value.signum() != 0 && value.stripTrailingZeros().scale() <= 0) {
            // Integral: also enforce the safe-integer range (doubles above 2^53 skip integers).
            safeInteger(value.toBigInteger())
        }
        return asDouble
    }

    private const val UNSAFE_NUMBER =
        "number not exactly representable as a JS double - pass it as a decimal string (amounts always are)"
}
