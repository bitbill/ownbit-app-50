// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.jsengine

/**
 * Tuning knobs of [JsEngineManager]. The defaults are what the app uses; tests shorten them.
 *
 * @property warmBundles bundles loaded at [JsEngineManager.start] and kept alive while the process
 *   lives (BTC, ETH and TRX are needed on almost every screen and for wallet creation).
 * @property idleReleaseMillis other bundles are torn down after this long without a call.
 * @property idleCheckIntervalMillis how often the idle sweep runs.
 * @property pageLoadTimeoutMillis max time for a host page + bundle to load and pass the readiness probe.
 * @property healthCheckTimeoutMillis max time for the foreground ping of a live engine.
 */
data class JsEngineConfig(
    val warmBundles: Set<JsBundle> = setOf(JsBundle.BTC, JsBundle.ETH, JsBundle.TRX),
    val idleReleaseMillis: Long = 3 * 60_000L,
    val idleCheckIntervalMillis: Long = 60_000L,
    val pageLoadTimeoutMillis: Long = 60_000L,
    val healthCheckTimeoutMillis: Long = 5_000L,
)
