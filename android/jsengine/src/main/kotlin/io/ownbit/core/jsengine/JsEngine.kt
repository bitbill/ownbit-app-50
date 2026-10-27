// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.jsengine

import kotlinx.coroutines.flow.SharedFlow
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement

/**
 * A single JS bundle running in its own hidden, hardened System WebView page.
 *
 * - Calls are **serialized** per bundle (one in flight at a time) and correlated by request id.
 * - Arguments are always passed as JSON ([JsArgs]) and `JSON.parse`d in the page; nothing is spliced
 *   into JS source.
 * - Promise results are awaited in the page before being posted back.
 * - Obtain instances from [JsEngineManager.engine]. All functions are main-safe and may be called from
 *   any dispatcher, but never block the main thread waiting for them (e.g. `runBlocking`).
 */
interface JsEngine {

    /** Bundle this engine hosts. */
    val bundle: JsBundle

    /**
     * Calls a global JS function (e.g. `bridge.getXpubkeys`) and returns its (awaited) result as JSON.
     * `undefined` is returned as [kotlinx.serialization.json.JsonNull].
     *
     * Cancelling the caller stops the wait; the result, when it arrives, is dropped (results are
     * matched by request id, so it can never be returned to another call). The page is *not* recycled,
     * so functions that also post callbacks on a channel another [callForEvent] may wait for must be
     * invoked through [callForEvent] instead.
     *
     * @param function dotted global path; only `[A-Za-z_$][\w$]*` segments are accepted.
     * @param args positional arguments, see [JsArgs.of].
     * @throws JsCallException the function threw / its Promise rejected.
     * @throws JsTimeoutException no result in time (the page is recycled).
     * @throws JsBundleLoadException, JsEngineCrashedException, JsEngineUnavailableException
     */
    suspend fun call(
        function: String,
        args: JsonArray = JsArgs.NONE,
        timeoutMillis: Long = bundle.callTimeoutMillis,
    ): JsonElement

    /**
     * Calls an *asynchronous-callback* JS function - one whose real result is delivered later through
     * a bundle callback channel (old Android `android.jsSuccessHandler(channel, data)`, iOS
     * `window.webkit.messageHandlers.<channel>.postMessage(data)`) - and suspends until a matching
     * callback arrives.
     *
     * The callback waiter is registered **before** the function is invoked, so callbacks that fire
     * before the call itself returns are never lost (the iOS `pendingAsyncJsHexTx` race cannot happen).
     * The per-bundle queue stays locked until the callback, a failure or the timeout, so a callback can
     * never be attributed to another call. A rejected / throwing call fails immediately. On timeout, on any
     * failure, and when the caller is cancelled before the callback arrived, the page is recycled so a late
     * callback (e.g. a previous unsigned / signed transaction) can never leak into a later call. Callbacks
     * carry no request id (the bundles are unmodified copies), so this serialisation + recycling is what
     * ties each callback to its request.
     *
     * @throws JsEventFailureException the bundle reported failure (failure callback or failure channel).
     * @throws JsCallException the call threw / its Promise rejected before any callback.
     * @throws JsTimeoutException no callback in time.
     */
    suspend fun callForEvent(
        function: String,
        args: JsonArray,
        expect: JsEventSpec,
        timeoutMillis: Long = bundle.callTimeoutMillis,
    ): JsEvent

    /**
     * Callbacks that arrived while no [callForEvent] was waiting for them (diagnostics only; do not
     * derive results from this stream).
     */
    val unsolicitedEvents: SharedFlow<JsEvent>
}

/**
 * An asynchronous callback posted by a bundle.
 *
 * @property channel callback name (`transaction`, `signed`, `pre`, `multiSigned`, `mstransaction`,
 *   `address`, `signTypedData`, `error`, ...).
 * @property ok `true` for success callbacks, `false` for `jsFailureHandler` / the `error` channel.
 * @property payload callback payload as text (non-strings are JSON-encoded in the page).
 */
class JsEvent(val channel: String, val ok: Boolean, val payload: String) {
    override fun toString(): String = "JsEvent(channel=$channel, ok=$ok, payload=<${payload.length} chars>)"

    override fun equals(other: Any?): Boolean =
        other is JsEvent && other.channel == channel && other.ok == ok && other.payload == payload

    override fun hashCode(): Int = (channel.hashCode() * 31 + ok.hashCode()) * 31 + payload.hashCode()
}

/**
 * Which callbacks complete a [JsEngine.callForEvent].
 *
 * An event on one of [successChannels] completes the call (or fails it when the bundle used its
 * failure handler for that channel). An event on one of [failureChannels] always fails the call.
 */
data class JsEventSpec(
    val successChannels: Set<String>,
    val failureChannels: Set<String> = setOf(ERROR_CHANNEL),
) {
    init {
        require(successChannels.isNotEmpty()) { "at least one success channel is required" }
    }

    companion object {
        /** Channel used by all bundles for generic failures. */
        const val ERROR_CHANNEL: String = "error"

        /** Convenience factory: success on [channels], failure on `error`. */
        fun of(vararg channels: String): JsEventSpec = JsEventSpec(channels.toSet())
    }
}
