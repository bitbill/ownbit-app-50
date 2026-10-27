// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.jsengine.bridge

import io.ownbit.core.jsengine.JsArgs
import io.ownbit.core.jsengine.JsBundle
import io.ownbit.core.jsengine.JsEngine
import io.ownbit.core.jsengine.JsEngineManager
import io.ownbit.core.jsengine.JsResults
import kotlinx.serialization.json.JsonElement

/**
 * Base of the typed per-chain bridges: resolves the bundle's engine and decodes results the way the
 * iOS bridges read `JSValue`s. Every call goes through [JsEngine] (JSON arguments, serialized queue,
 * timeout, redacted logging).
 */
abstract class JsBridge internal constructor(
    private val engines: JsEngineManager,
    /** Bundle this bridge talks to. */
    val bundle: JsBundle,
) {
    /** The engine of [bundle]. */
    protected val engine: JsEngine get() = engines.engine(bundle)

    /** Calls `function` with [args] converted by [JsArgs.of]. */
    protected suspend fun raw(function: String, vararg args: Any?): JsonElement =
        engine.call(function, JsArgs.of(*args))

    /** String result (`JSValue.toString()`). */
    protected suspend fun string(function: String, vararg args: Any?): String =
        JsResults.string(raw(function, *args), bundle, function)

    /** Non-empty string result (iOS `guard let s = result.toString(), !s.isEmpty`). */
    protected suspend fun nonEmptyString(function: String, vararg args: Any?): String =
        JsResults.nonEmptyString(raw(function, *args), bundle, function)

    /** Boolean result with JS truthiness (`JSValue.toBool()`). */
    protected suspend fun bool(function: String, vararg args: Any?): Boolean =
        JsResults.truthy(raw(function, *args))

    /** Array-of-strings result with at least [minSize] elements. */
    protected suspend fun strings(function: String, minSize: Int, vararg args: Any?): List<String> =
        JsResults.stringArray(raw(function, *args), bundle, function, minSize)

    /** `[publicKey, address]` result. */
    protected suspend fun publicKeyAddress(function: String, vararg args: Any?): PublicKeyAddress {
        val values = strings(function, 2, *args)
        return PublicKeyAddress(publicKey = values[0], address = values[1])
    }

    /** First [size] elements of an array result, all non-empty strings (iOS `BILJSArg.strings`, 2026-10 wrappers). */
    protected suspend fun nonEmptyStrings(function: String, size: Int, vararg args: Any?): List<String> =
        JsResults.nonEmptyStrings(raw(function, *args), bundle, function, size)

    internal companion object {
        /** Prefix of every function exported through the UMD global `bridge`. */
        const val BRIDGE = "bridge."

        /** Removes a leading `0x` / `0X`, as the iOS bridges do before passing private keys around. */
        fun strip0x(hex: String): String =
            if (hex.startsWith("0x") || hex.startsWith("0X")) hex.substring(2) else hex

        /**
         * The message pre-encoding the iOS bridges apply before signing / verifying a message
         * (`"` -> `_QUOTE_OWNBIT_`, `\n` -> `_NEWLINE_OWNBIT_`); the bundles reverse it. Kept so the
         * signed bytes are identical to iOS.
         */
        fun encodeMessageForJs(message: String): String =
            message.replace("\"", "_QUOTE_OWNBIT_").replace("\n", "_NEWLINE_OWNBIT_")
    }
}
