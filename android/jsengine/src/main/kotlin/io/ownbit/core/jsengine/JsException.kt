// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.jsengine

/**
 * Base type of every failure raised by the JS engine and the typed bridges.
 *
 * [message] never contains call arguments, results or JS error text (they can carry secrets), so an
 * exception can be logged safely. The raw JS error text, where available, is exposed separately
 * ([JsCallException.jsMessage], [JsEventFailureException.payload]) for UI mapping only and must never
 * be logged.
 */
sealed class JsException(message: String, cause: Throwable? = null) : Exception(message, cause) {
    /** Bundle the failure belongs to. */
    abstract val bundle: JsBundle
}

/**
 * The JS function threw, or the Promise it returned was rejected.
 *
 * @property function JS function path, e.g. `bridge.getXpubkeys`.
 * @property jsMessage `String(error)` as produced in JS (e.g. `"Error: invalid hex"`). May contain
 *   sensitive material - never log it.
 */
class JsCallException(
    override val bundle: JsBundle,
    val function: String,
    val jsMessage: String?,
) : JsException("JS call ${bundle.id}:$function failed")

/**
 * An async bundle callback reported failure (`android.jsFailureHandler(...)`, or an `error` channel).
 *
 * @property channel callback channel name, e.g. `signed`, `error`.
 * @property payload raw callback payload. May contain sensitive material - never log it.
 */
class JsEventFailureException(
    override val bundle: JsBundle,
    val function: String,
    val channel: String,
    val payload: String,
) : JsException("JS call ${bundle.id}:$function reported failure on channel '$channel'")

/** No result (or expected async callback) arrived within [timeoutMillis]. The page is recycled. */
class JsTimeoutException(
    override val bundle: JsBundle,
    val function: String,
    val timeoutMillis: Long,
) : JsException("JS call ${bundle.id}:$function timed out after $timeoutMillis ms")

/** The host page or bundle could not be loaded (missing asset, load error, readiness probe failed). */
class JsBundleLoadException(
    override val bundle: JsBundle,
    detail: String,
    cause: Throwable? = null,
) : JsException("JS bundle ${bundle.id} failed to load: $detail", cause)

/**
 * The engine was torn down while the call was in flight: WebView renderer process gone, memory trim
 * or explicit release. Retrying the call re-creates the page.
 */
class JsEngineCrashedException(
    override val bundle: JsBundle,
    reason: String,
) : JsException("JS engine ${bundle.id} stopped: $reason")

/**
 * The installed System WebView lacks a feature the hardened engine requires
 * (`WEB_MESSAGE_LISTENER`). The user must update "Android System WebView".
 */
class JsEngineUnavailableException(
    override val bundle: JsBundle,
    reason: String,
) : JsException("JS engine ${bundle.id} unavailable: $reason")

/** The JS function returned a value of an unexpected shape (e.g. array too short). */
class JsResultFormatException(
    override val bundle: JsBundle,
    val function: String,
    expected: String,
) : JsException("JS call ${bundle.id}:$function returned an unexpected result (expected $expected)")
