// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.jsengine

import android.content.ComponentCallbacks2
import android.content.Context
import android.content.res.Configuration
import android.os.SystemClock
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.ProcessLifecycleOwner
import io.ownbit.core.common.log.Log
import io.ownbit.core.jsengine.internal.WebViewJsEngine
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Owns one [JsEngine] per [JsBundle] and their lifecycle:
 *
 * - engines are created lazily on first use ([engine]); pages load on the first call or on [warmUp];
 * - [start] (call once from `Application.onCreate`) warms [JsEngineConfig.warmBundles] (BTC, ETH, TRX),
 *   runs a health check + re-warm every time the app returns to the foreground (renderer may have
 *   been reaped in the background), releases idle non-warm engines after
 *   [JsEngineConfig.idleReleaseMillis], and trims on memory pressure;
 * - a crashed / released engine is rebuilt transparently by its next call.
 *
 * Never call `WebView.pauseTimers()` anywhere in the app: it freezes every engine (TRX XHR lesson).
 */
class JsEngineManager(
    context: Context,
    private val scope: CoroutineScope,
    /** Effective configuration. */
    val config: JsEngineConfig,
) {

    /** With the default [JsEngineConfig]. */
    constructor(
        context: Context,
        scope: CoroutineScope,
    ) : this(context, scope, JsEngineConfig())

    private val appContext: Context = context.applicationContext
    private val engines = ConcurrentHashMap<JsBundle, WebViewJsEngine>()
    private val started = AtomicBoolean(false)

    /** The engine hosting [bundle]. Cheap; the WebView is only created on first use. */
    fun engine(bundle: JsBundle): JsEngine = engineImpl(bundle)

    private fun engineImpl(bundle: JsBundle): WebViewJsEngine =
        engines.getOrPut(bundle) { WebViewJsEngine(bundle, appContext, config) }

    /**
     * Installs the lifecycle hooks and warms the default bundles. Idempotent; call from
     * `Application.onCreate()`.
     */
    fun start() {
        if (!started.compareAndSet(false, true)) return
        scope.launch(Dispatchers.Main.immediate) {
            ProcessLifecycleOwner.get().lifecycle.addObserver(foregroundObserver)
        }
        appContext.registerComponentCallbacks(memoryCallbacks)
        scope.launch { warmUp() }
        scope.launch {
            while (isActive) {
                delay(config.idleCheckIntervalMillis)
                releaseIdle(includeWarm = false, idleForMillis = config.idleReleaseMillis)
            }
        }
    }

    /** Loads the pages of [bundles] now. Failures are logged and left for the first real call to surface. */
    suspend fun warmUp(bundles: Set<JsBundle> = config.warmBundles) {
        for (bundle in bundles) {
            try {
                engineImpl(bundle).preload()
            } catch (e: JsException) {
                Log.w(TAG) { "warm-up of ${bundle.id} failed: ${e.javaClass.simpleName}" }
            }
        }
    }

    /**
     * Makes the next call on [bundle] start from a freshly loaded page (a call in flight finishes on the
     * current page). Needed when page-lifetime state inside a bundle must change, e.g. the TRX node.
     */
    fun restart(bundle: JsBundle) {
        engines[bundle]?.requestRestart()
    }

    /**
     * Tears down [bundle]'s page as soon as the call in flight on it (if any) has finished; returns at once. Unlike
     * [restart], page-global state is gone now rather than at the next call — e.g. the private key TronWeb keeps after
     * `multiSignTx` (`tronWeb.setPrivateKey`), dropped when a TRX batch signer closes. The next call loads a fresh
     * page.
     */
    fun discardPage(bundle: JsBundle) {
        val engine = engines[bundle] ?: return
        scope.launch { engine.discard("page discarded") }
    }

    /** Whether a page of [bundle] exists now (loading or loaded): diagnostics and tests. */
    fun isPageLoaded(bundle: JsBundle): Boolean = engines[bundle]?.isLoaded == true

    /** Pings every loaded idle engine and rebuilds the ones that do not answer. */
    suspend fun healthCheck() {
        for (engine in engines.values) {
            engine.healthCheck()
        }
    }

    /**
     * Tears down loaded engines that are not busy and have been idle for at least [idleForMillis].
     * Warm bundles are kept unless [includeWarm].
     */
    suspend fun releaseIdle(includeWarm: Boolean, idleForMillis: Long = 0) {
        val now = SystemClock.elapsedRealtime()
        for (engine in engines.values) {
            if (!engine.isLoaded || engine.isBusy) continue
            if (!includeWarm && engine.bundle in config.warmBundles) continue
            if (now - engine.lastUsedAtMillis < idleForMillis) continue
            if (engine.releaseIfIdle("idle")) {
                Log.d(TAG) { "released idle engine ${engine.bundle.id}" }
            }
        }
    }

    private val foregroundObserver = object : DefaultLifecycleObserver {
        override fun onStart(owner: LifecycleOwner) {
            scope.launch {
                healthCheck()
                warmUp()
            }
        }
    }

    private val memoryCallbacks = object : ComponentCallbacks2 {
        override fun onTrimMemory(level: Int) {
            @Suppress("DEPRECATION")
            val includeWarm = level >= ComponentCallbacks2.TRIM_MEMORY_COMPLETE ||
                level == ComponentCallbacks2.TRIM_MEMORY_RUNNING_CRITICAL
            @Suppress("DEPRECATION")
            val trim = includeWarm ||
                level >= ComponentCallbacks2.TRIM_MEMORY_BACKGROUND ||
                level == ComponentCallbacks2.TRIM_MEMORY_RUNNING_LOW
            if (trim) scope.launch { releaseIdle(includeWarm = includeWarm) }
        }

        override fun onConfigurationChanged(newConfig: Configuration) = Unit

        @Deprecated("Deprecated in Java")
        override fun onLowMemory() {
            scope.launch { releaseIdle(includeWarm = true) }
        }
    }

    private companion object {
        const val TAG = "JsEngine"
    }
}
