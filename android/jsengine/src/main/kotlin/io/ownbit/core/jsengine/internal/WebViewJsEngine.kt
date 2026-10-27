// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.jsengine.internal

import android.annotation.SuppressLint
import android.content.Context
import android.net.Uri
import android.os.SystemClock
import android.webkit.ConsoleMessage
import android.webkit.CookieManager
import android.webkit.JsPromptResult
import android.webkit.JsResult
import android.webkit.RenderProcessGoneDetail
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.annotation.MainThread
import androidx.webkit.WebViewAssetLoader
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import io.ownbit.core.common.log.Log
import io.ownbit.core.jsengine.JsArgs
import io.ownbit.core.jsengine.JsBundle
import io.ownbit.core.jsengine.JsBundleLoadException
import io.ownbit.core.jsengine.JsCallException
import io.ownbit.core.jsengine.JsEngine
import io.ownbit.core.jsengine.JsEngineConfig
import io.ownbit.core.jsengine.JsEngineCrashedException
import io.ownbit.core.jsengine.JsEngineUnavailableException
import io.ownbit.core.jsengine.JsEvent
import io.ownbit.core.jsengine.JsEventFailureException
import io.ownbit.core.jsengine.JsEventSpec
import io.ownbit.core.jsengine.JsException
import io.ownbit.core.jsengine.JsResults
import io.ownbit.core.jsengine.JsTimeoutException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.atomic.AtomicReference

/**
 * [JsEngine] backed by one hidden System WebView page, hardened:
 *
 * - page served by [WebViewAssetLoader] from `https://appassets.androidplatform.net/js/<bundle>/`;
 *   file / content access off, no `addJavascriptInterface`;
 * - results and bundle callbacks come back through `WebViewCompat.addWebMessageListener`, restricted
 *   to that origin and to the main frame;
 * - the WebView is created lazily on the main thread, kept runnable (renderer priority IMPORTANT,
 *   timers resumed before every call) and torn down on renderer death, timeout or release;
 * - logs carry bundle id, function name and duration only.
 */
internal class WebViewJsEngine(
    override val bundle: JsBundle,
    context: Context,
    private val config: JsEngineConfig,
) : JsEngine {

    private val appContext: Context = context.applicationContext
    private val queue = Mutex()
    private val nextId = AtomicLong(0)
    private val pending = ConcurrentHashMap<Long, CompletableDeferred<JsProtocol.HostMessage.Result>>()
    private val activeWaiter = AtomicReference<EventWaiter?>(null)
    private val unsolicited = MutableSharedFlow<JsEvent>(
        extraBufferCapacity = 16,
        onBufferOverflow = BufferOverflow.DROP_OLDEST,
    )

    override val unsolicitedEvents: SharedFlow<JsEvent> = unsolicited.asSharedFlow()

    private val assetLoader: WebViewAssetLoader = WebViewAssetLoader.Builder()
        .addPathHandler("/${JsAssetsPathHandler.ASSET_ROOT}/", JsAssetsPathHandler(appContext))
        .build()

    // ---- written on the main thread only (volatile so the message listener always sees the latest) --
    @Volatile
    private var webView: WebView? = null

    @Volatile
    private var pageLoad: CompletableDeferred<Unit>? = null

    // ---- cross-thread flags ---------------------------------------------------------------------
    @Volatile
    private var ready = false

    /** `true` while a WebView exists for this bundle (loading or loaded). */
    @Volatile
    var isLoaded: Boolean = false
        private set

    /** `elapsedRealtime` of the last finished call; drives the idle sweep. */
    @Volatile
    var lastUsedAtMillis: Long = SystemClock.elapsedRealtime()
        private set

    /** `true` while a call holds the per-bundle queue. */
    val isBusy: Boolean get() = queue.isLocked

    /** Set by [requestRestart]; consumed by the next call under the queue lock. */
    @Volatile
    private var restartRequested = false

    private val messageListener = WebViewCompat.WebMessageListener { view, message, sourceOrigin, isMainFrame, _ ->
        if (view !== webView) {
            // A late result / callback of a page torn down after a timeout, failure or cancellation: dropped.
            Log.d(TAG) { "${bundle.id}: dropped a message from a torn-down page" }
            return@WebMessageListener
        }
        if (!isMainFrame || !isTrustedOrigin(sourceOrigin)) return@WebMessageListener
        val data = message.data ?: return@WebMessageListener
        when (val parsed = JsProtocol.parse(data)) {
            is JsProtocol.HostMessage.Result -> pending[parsed.id]?.complete(parsed)
            is JsProtocol.HostMessage.Event -> onEvent(JsEvent(parsed.channel, parsed.ok, parsed.payload))
            null -> Log.w(TAG) { "${bundle.id}: dropped malformed host message" }
        }
    }

    // ---- JsEngine -------------------------------------------------------------------------------

    override suspend fun call(function: String, args: JsonArray, timeoutMillis: Long): JsonElement =
        queue.withLock {
            ensureReady()
            try {
                invokeAndAwait(function, args, timeoutMillis)
            } catch (e: JsTimeoutException) {
                recycle("call timeout")
                throw e
            }
        }

    override suspend fun callForEvent(
        function: String,
        args: JsonArray,
        expect: JsEventSpec,
        timeoutMillis: Long,
    ): JsEvent = queue.withLock {
        ensureReady()
        val started = SystemClock.elapsedRealtime()
        val waiter = EventWaiter(bundle, function, expect)
        val id = nextId.incrementAndGet()
        val result = CompletableDeferred<JsProtocol.HostMessage.Result>()
        pending[id] = result
        try {
            // The waiter is armed on the main thread immediately before the script is handed to the
            // renderer: callbacks the call posts (even before it returns) are delivered after this
            // point, while stale callbacks of an earlier call that are still queued on the main looper
            // are delivered before it and end up in unsolicitedEvents instead of being misattributed.
            dispatch(id, function, args, result) { activeWaiter.set(waiter) }
            val event = coroutineScope {
                // A throwing / rejected call fails fast; a resolved call keeps waiting for the callback.
                val watcher = launch {
                    val outcome = try {
                        result.await()
                    } catch (e: CancellationException) {
                        throw e
                    } catch (e: Throwable) {
                        waiter.fail(e)
                        return@launch
                    }
                    if (!outcome.ok) waiter.fail(JsCallException(bundle, function, outcome.error))
                }
                try {
                    withTimeout(timeoutMillis) { waiter.await() }
                } catch (e: TimeoutCancellationException) {
                    throw JsTimeoutException(bundle, function, timeoutMillis)
                } finally {
                    watcher.cancel()
                }
            }
            logCall(function, started, "ok")
            event
        } catch (e: JsTimeoutException) {
            logCall(function, started, "timeout")
            recycle("callback timeout")
            throw e
        } catch (e: JsException) {
            logCall(function, started, "failed")
            // A failure does not prove the bundle stopped working on this call: the call may have thrown after starting
            // async work, and an `error` event can even be a late one of an earlier call. This call's own success
            // callback could then still arrive and complete the next callForEvent on this bundle — e.g. the TRX
            // multisig signature of one proposal returned for the next one. Tear the page down, as on
            // timeout / cancellation; the next call loads a fresh page.
            recycle("failed while the bundle may still be working")
            throw e
        } catch (e: CancellationException) {
            // The caller gave up (screen closed, scope cancelled) while the bundle may still be working
            // (e.g. TRX preSendTx node requests). Its late callback must never be credited to the next
            // callForEvent on this bundle (it could be a different unsigned / signed transaction), so the
            // page is torn down, exactly as on timeout.
            if (!waiter.isCompleted) {
                logCall(function, started, "cancelled")
                recycle("cancelled while awaiting callback")
            }
            throw e
        } finally {
            activeWaiter.compareAndSet(waiter, null)
            pending.remove(id)
            lastUsedAtMillis = SystemClock.elapsedRealtime()
        }
    }

    // ---- lifecycle (used by JsEngineManager) ----------------------------------------------------

    /** Loads the page now (warm-up) instead of on the first call. */
    suspend fun preload() {
        queue.withLock { ensureReady() }
    }

    /**
     * Pings a loaded, idle engine; tears it down when it does not answer. Returns `false` when the
     * engine had to be torn down. Busy or unloaded engines are skipped (their own timeouts guard them).
     */
    suspend fun healthCheck(): Boolean {
        if (!isLoaded || !queue.tryLock()) return true
        try {
            if (!ready) return true
            return try {
                invokeAndAwait(PING, JsArgs.NONE, config.healthCheckTimeoutMillis)
                true
            } catch (e: JsException) {
                Log.w(TAG) { "${bundle.id}: health check failed (${e.javaClass.simpleName}), recycling" }
                recycle("health check failed")
                false
            }
        } finally {
            queue.unlock()
        }
    }

    /**
     * Tears the page down if the engine is idle. Returns `false` (and does nothing) when a call is in
     * flight. The next call re-creates the page transparently.
     */
    suspend fun releaseIfIdle(reason: String): Boolean {
        if (!isLoaded) return true
        if (!queue.tryLock()) return false
        try {
            recycle(reason)
        } finally {
            queue.unlock()
        }
        return true
    }

    /**
     * Tears the page down as soon as no call holds the queue (a call in flight, and calls queued before this one,
     * finish on the current page first). Page-global state goes with it, e.g. a private key a bundle keeps for the
     * page's lifetime. The next call re-creates the page transparently.
     */
    suspend fun discard(reason: String) {
        queue.withLock { recycle(reason) }
    }

    /**
     * Makes the next call start from a fresh page (a call in flight is not disturbed). Used when a
     * value the bundle caches for the page's lifetime changes, e.g. the TRX node: TronWeb is created
     * once with the node of the first call (`createTronWebIfNotExists`).
     */
    fun requestRestart() {
        restartRequested = true
    }

    // ---- internals ------------------------------------------------------------------------------

    private suspend fun ensureReady() {
        if (restartRequested) {
            restartRequested = false
            recycle("restart requested")
        }
        if (ready) return
        val started = SystemClock.elapsedRealtime()
        val load = withContext(Dispatchers.Main.immediate) { startLoadIfNeeded() }
        try {
            withTimeout(config.pageLoadTimeoutMillis) { load.await() }
        } catch (e: TimeoutCancellationException) {
            recycle("page load timeout")
            throw JsBundleLoadException(bundle, "page load timed out")
        } catch (e: JsException) {
            recycle("page load failed")
            throw e
        }
        val present = try {
            invokeAndAwait(HAS_GLOBAL, JsArgs.of(bundle.readyGlobal), config.pageLoadTimeoutMillis)
        } catch (e: JsException) {
            recycle("readiness probe failed")
            throw JsBundleLoadException(bundle, "readiness probe failed", e)
        }
        if (!JsResults.truthy(present)) {
            recycle("bundle global missing")
            throw JsBundleLoadException(bundle, "bundle global '${bundle.readyGlobal}' missing after load")
        }
        ready = true
        Log.d(TAG) { "${bundle.id}: ready in ${SystemClock.elapsedRealtime() - started} ms" }
    }

    private suspend fun invokeAndAwait(function: String, args: JsonArray, timeoutMillis: Long): JsonElement {
        val started = SystemClock.elapsedRealtime()
        val id = nextId.incrementAndGet()
        val result = CompletableDeferred<JsProtocol.HostMessage.Result>()
        pending[id] = result
        try {
            dispatch(id, function, args, result)
            val outcome = try {
                withTimeout(timeoutMillis) { result.await() }
            } catch (e: TimeoutCancellationException) {
                logCall(function, started, "timeout")
                throw JsTimeoutException(bundle, function, timeoutMillis)
            }
            if (!outcome.ok) {
                logCall(function, started, "failed")
                throw JsCallException(bundle, function, outcome.error)
            }
            logCall(function, started, "ok")
            return outcome.value
        } finally {
            pending.remove(id)
            lastUsedAtMillis = SystemClock.elapsedRealtime()
        }
    }

    /**
     * Hands the invoke statement to the page. [beforeEvaluate] runs on the main thread right before
     * `evaluateJavascript` (used to arm the callback waiter of [callForEvent]).
     */
    private suspend fun dispatch(
        id: Long,
        function: String,
        args: JsonArray,
        result: CompletableDeferred<JsProtocol.HostMessage.Result>,
        beforeEvaluate: (() -> Unit)? = null,
    ) {
        val script = JsProtocol.invokeScript(id, function, args)
        withContext(Dispatchers.Main.immediate) {
            val view = webView ?: throw JsEngineCrashedException(bundle, "page not loaded")
            // pauseTimers() is process-wide; make sure nobody left this engine frozen (TRX lesson).
            view.resumeTimers()
            beforeEvaluate?.invoke()
            view.evaluateJavascript(script) { ack ->
                if (ack != JsProtocol.INVOKE_ACK) {
                    result.completeExceptionally(JsBundleLoadException(bundle, "host shim not reachable"))
                }
            }
        }
    }

    private fun onEvent(event: JsEvent) {
        val waiter = activeWaiter.get()
        if (waiter == null || !waiter.offer(event)) {
            Log.d(TAG) { "${bundle.id}: unclaimed callback on channel '${event.channel}'" }
            unsolicited.tryEmit(event)
        }
    }

    private suspend fun recycle(reason: String) {
        withContext(NonCancellable + Dispatchers.Main.immediate) { teardown(reason) }
    }

    @MainThread
    private fun startLoadIfNeeded(): CompletableDeferred<Unit> {
        val existing = pageLoad
        if (existing != null && webView != null) return existing
        if (!WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER)) {
            throw JsEngineUnavailableException(bundle, "System WebView lacks WEB_MESSAGE_LISTENER")
        }
        val view = try {
            WebView(appContext)
        } catch (t: Throwable) {
            // WebView package missing / being updated.
            throw JsEngineUnavailableException(bundle, "WebView cannot be created (${t.javaClass.simpleName})")
        }
        configure(view)
        WebViewCompat.addWebMessageListener(view, JsProtocol.HOST_OBJECT, setOf(JsProtocol.ORIGIN), messageListener)
        val load = CompletableDeferred<Unit>()
        webView = view
        pageLoad = load
        isLoaded = true
        view.loadUrl("${JsProtocol.ORIGIN}/${bundle.hostPath}")
        return load
    }

    @SuppressLint("SetJavaScriptEnabled")
    @MainThread
    private fun configure(view: WebView) {
        view.settings.apply {
            javaScriptEnabled = true
            allowFileAccess = false
            allowContentAccess = false
            @Suppress("DEPRECATION")
            allowFileAccessFromFileURLs = false
            @Suppress("DEPRECATION")
            allowUniversalAccessFromFileURLs = false
            domStorageEnabled = false
            @Suppress("DEPRECATION")
            databaseEnabled = false
            setGeolocationEnabled(false)
            javaScriptCanOpenWindowsAutomatically = false
            setSupportMultipleWindows(false)
            setSupportZoom(false)
            mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
            cacheMode = WebSettings.LOAD_NO_CACHE
            loadsImagesAutomatically = false
            blockNetworkImage = true
            mediaPlaybackRequiresUserGesture = true
        }
        CookieManager.getInstance().setAcceptThirdPartyCookies(view, false)
        // Keep the renderer bound as important even though the view is never attached/visible, so the
        // OS does not freeze or reap it while an async (XHR) call is in flight.
        view.setRendererPriorityPolicy(WebView.RENDERER_PRIORITY_IMPORTANT, false)
        view.isFocusable = false
        view.webViewClient = EngineClient()
        view.webChromeClient = SilentChromeClient()
        view.onResume()
        view.resumeTimers()
    }

    @MainThread
    private fun teardown(reason: String) {
        val view = webView ?: return
        Log.d(TAG) { "${bundle.id}: teardown ($reason)" }
        webView = null
        ready = false
        isLoaded = false
        val failure = JsEngineCrashedException(bundle, reason)
        pageLoad?.completeExceptionally(failure)
        pageLoad = null
        pending.values.forEach { it.completeExceptionally(failure) }
        activeWaiter.get()?.fail(failure)
        runCatching { WebViewCompat.removeWebMessageListener(view, JsProtocol.HOST_OBJECT) }
        runCatching { view.stopLoading() }
        runCatching { view.webChromeClient = null }
        runCatching { view.webViewClient = WebViewClient() }
        runCatching { view.destroy() }
    }

    private fun logCall(function: String, started: Long, outcome: String) {
        Log.d(TAG) { "${bundle.id}:$function $outcome in ${SystemClock.elapsedRealtime() - started} ms" }
    }

    private fun isTrustedOrigin(origin: Uri): Boolean =
        origin.scheme == "https" && origin.host == ASSET_HOST && (origin.port == -1 || origin.port == 443)

    private inner class EngineClient : WebViewClient() {
        override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? {
            val url = request.url
            if (url.host == ASSET_HOST) {
                return assetLoader.shouldInterceptRequest(url) ?: JsAssetsPathHandler.notFound()
            }
            // Chain RPC used by the TRX / TON / SOL bundles (CSP limits it to https).
            return null
        }

        override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean = true

        override fun onPageFinished(view: WebView, url: String?) {
            if (view === webView) pageLoad?.complete(Unit)
        }

        override fun onReceivedError(view: WebView, request: WebResourceRequest, error: WebResourceError) {
            if (view === webView && request.isForMainFrame) {
                pageLoad?.completeExceptionally(JsBundleLoadException(bundle, "main frame error ${error.errorCode}"))
            }
        }

        override fun onReceivedHttpError(
            view: WebView,
            request: WebResourceRequest,
            errorResponse: WebResourceResponse,
        ) {
            val path = request.url.path.orEmpty()
            // Only the host page and the scripts under /js/ matter (Chromium also probes /favicon.ico).
            if (view === webView && request.url.host == ASSET_HOST && path.startsWith("/${JsAssetsPathHandler.ASSET_ROOT}/")) {
                pageLoad?.completeExceptionally(
                    JsBundleLoadException(bundle, "HTTP ${errorResponse.statusCode} for $path"),
                )
            }
        }

        override fun onRenderProcessGone(view: WebView, detail: RenderProcessGoneDetail): Boolean {
            Log.w(TAG) { "${bundle.id}: renderer gone (crashed=${detail.didCrash()})" }
            if (view === webView) {
                teardown("renderer process gone")
            } else {
                runCatching { view.destroy() }
            }
            // Handled: never let a renderer crash take the app down.
            return true
        }
    }

    private inner class SilentChromeClient : WebChromeClient() {
        override fun onConsoleMessage(consoleMessage: ConsoleMessage): Boolean {
            // Console text can contain keys / signed payloads: never log it, only its position.
            if (consoleMessage.messageLevel() == ConsoleMessage.MessageLevel.ERROR) {
                Log.d(TAG) {
                    "${bundle.id}: console error at ${consoleMessage.sourceId()?.substringAfterLast('/')}:" +
                        consoleMessage.lineNumber()
                }
            }
            return true
        }

        override fun onJsAlert(view: WebView?, url: String?, message: String?, result: JsResult): Boolean {
            result.cancel()
            return true
        }

        override fun onJsConfirm(view: WebView?, url: String?, message: String?, result: JsResult): Boolean {
            result.cancel()
            return true
        }

        override fun onJsPrompt(
            view: WebView?,
            url: String?,
            message: String?,
            defaultValue: String?,
            result: JsPromptResult,
        ): Boolean {
            result.cancel()
            return true
        }

        override fun onJsBeforeUnload(view: WebView?, url: String?, message: String?, result: JsResult): Boolean {
            result.confirm()
            return true
        }
    }

    /** Waits for the async callback of one [callForEvent]. */
    private class EventWaiter(
        private val bundle: JsBundle,
        private val function: String,
        private val spec: JsEventSpec,
    ) {
        private val deferred = CompletableDeferred<JsEvent>()

        /** Returns `true` when the event belongs to this call (and completes it if still pending). */
        fun offer(event: JsEvent): Boolean = when (event.channel) {
            in spec.failureChannels -> {
                deferred.completeExceptionally(
                    JsEventFailureException(bundle, function, event.channel, event.payload),
                )
                true
            }
            in spec.successChannels -> {
                if (event.ok) {
                    deferred.complete(event)
                } else {
                    deferred.completeExceptionally(
                        JsEventFailureException(bundle, function, event.channel, event.payload),
                    )
                }
                true
            }
            else -> false
        }

        fun fail(cause: Throwable) {
            deferred.completeExceptionally(cause)
        }

        /** `true` once a callback, failure or teardown settled this call. */
        val isCompleted: Boolean get() = deferred.isCompleted

        suspend fun await(): JsEvent = deferred.await()
    }

    private companion object {
        const val TAG = "JsEngine"
        const val ASSET_HOST = "appassets.androidplatform.net"
        const val HAS_GLOBAL = "__ownbitHost.has"
        const val PING = "__ownbitHost.ping"
    }
}
