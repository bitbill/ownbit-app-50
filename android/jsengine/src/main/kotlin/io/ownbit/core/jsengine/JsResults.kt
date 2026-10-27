// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.jsengine

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull

/**
 * Decoders for JS results, mirroring how the iOS bridges read `JSValue`s (`toString()`, `toBool()`,
 * `toArray()` + `as? String`). They throw [JsResultFormatException] on shape mismatches so a broken
 * bundle can never silently produce an empty address.
 */
object JsResults {

    /** A JS string result (numbers / booleans are accepted and rendered like `JSValue.toString()`). */
    fun string(result: JsonElement, bundle: JsBundle, function: String): String {
        val primitive = result as? JsonPrimitive
        if (primitive == null || primitive is JsonNull) throw JsResultFormatException(bundle, function, "string")
        return primitive.content
    }

    /** Like [string] but rejects the empty string, as the iOS bridges do (`guard !s.isEmpty`). */
    fun nonEmptyString(result: JsonElement, bundle: JsBundle, function: String): String {
        val value = string(result, bundle, function)
        if (value.isEmpty()) throw JsResultFormatException(bundle, function, "non-empty string")
        return value
    }

    /** A string result or `null` when JS returned `null` / `undefined`. */
    fun stringOrNull(result: JsonElement, bundle: JsBundle, function: String): String? =
        if (result is JsonNull) null else string(result, bundle, function)

    /** JS truthiness of the result, like `JSValue.toBool()`. */
    fun truthy(result: JsonElement): Boolean = when (result) {
        is JsonNull -> false
        is JsonPrimitive -> when {
            result.isString -> result.content.isNotEmpty()
            result.booleanOrNull != null -> result.booleanOrNull == true
            else -> result.doubleOrNull.let { it != null && it != 0.0 && !it.isNaN() }
        }
        is JsonArray, is JsonObject -> true
    }

    /** A JS array whose first [minSize] elements are strings; returns all string elements. */
    fun stringArray(result: JsonElement, bundle: JsBundle, function: String, minSize: Int = 0): List<String> {
        val array = result as? JsonArray ?: throw JsResultFormatException(bundle, function, "array")
        if (array.size < minSize) throw JsResultFormatException(bundle, function, "array of >= $minSize strings")
        return array.map { element ->
            val primitive = element as? JsonPrimitive
            if (primitive == null || primitive is JsonNull || !primitive.isString) {
                throw JsResultFormatException(bundle, function, "array of strings")
            }
            primitive.content
        }
    }

    /**
     * The first [size] elements of a JS array result, each a **non-empty** string - iOS `BILJSArg.strings(value,
     * count:)` of the 2026-10 XRP / XLM wrappers (`BILXrpXlmJSBridge.swift`), which turns an empty element into a
     * failure instead of an empty txId / signature. Extra elements (of any type) are ignored, as on iOS
     * (`arr.prefix(count)`).
     */
    fun nonEmptyStrings(result: JsonElement, bundle: JsBundle, function: String, size: Int): List<String> {
        val array = result as? JsonArray ?: throw JsResultFormatException(bundle, function, "array")
        if (array.size < size) throw JsResultFormatException(bundle, function, "array of >= $size strings")
        return array.take(size).map { element ->
            val primitive = element as? JsonPrimitive
            if (primitive == null || primitive is JsonNull || !primitive.isString || primitive.content.isEmpty()) {
                throw JsResultFormatException(bundle, function, "array of $size non-empty strings")
            }
            primitive.content
        }
    }
}
