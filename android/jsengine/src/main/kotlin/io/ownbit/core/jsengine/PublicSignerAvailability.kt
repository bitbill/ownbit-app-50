// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.jsengine

import android.content.Context
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import io.ownbit.core.common.log.Log
import io.ownbit.core.jsengine.bridge.PublicSignerJsBridge
import kotlinx.coroutines.CancellationException
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Can this device run the public-protocol engine (`pubsigner/signer.js`)?
 *
 * - [check] (cheap, synchronous): the installed Android System WebView. The Ownbit edition needs Chrome **91**
 *   ([MIN_WEBVIEW_MAJOR]: optional chaining and the other syntax esbuild emits; `Object.hasOwn` / `.at()` are polyfilled
 *   since the engine patch) and `WEB_MESSAGE_LISTENER` (every Ownbit page). Below 91 → [Availability.Unavailable] with
 *   [Reason.WEBVIEW_TOO_OLD] and the found version (the UI string `publicprotocol_pair_webviewtooold` takes it as
 *   `%1$s`). No WebView at all → [Reason.ENGINE_FAILED]. A version name that cannot be parsed is not refused here; the
 *   [probe] decides.
 * - [probe] (first use, suspend): [check], then `capabilities` on the pairing page must report this engine:
 *   `version == "1.0.0"`, `offline == true`, the Ownbit edition's `pairingOptions` containing `deviceName`, and its
 *   `publicIndexOptions` (`tronScheme`) and TronLink ownership check ([isExpectedEngine]). Any
 *   failure → [Reason.ENGINE_FAILED]. A success is remembered for the process (the asset never changes at runtime; a
 *   WebView update restarts the app process).
 */
object PublicSignerAvailability {

    /** Lowest Android System WebView (Chrome) major version the engine loads on (the API 31 emulator ships 91). */
    const val MIN_WEBVIEW_MAJOR: Int = 91

    /** The engine version the bundle reports (`capabilities.version`). */
    const val ENGINE_VERSION: String = "1.0.0"

    /** Why the public protocol cannot run. */
    enum class Reason { WEBVIEW_TOO_OLD, ENGINE_FAILED }

    /** Result of [check] / [probe]. */
    sealed interface Availability {
        /** The engine can run. */
        data object Available : Availability

        /** It cannot; [found] is the WebView version name when known. */
        data class Unavailable(val reason: Reason, val found: String?) : Availability
    }

    private val probed = AtomicBoolean(false)

    /** The WebView gate (no engine call). */
    fun check(context: Context): Availability {
        val versionName = try {
            WebViewCompat.getCurrentWebViewPackage(context)?.versionName
                ?: return Availability.Unavailable(Reason.ENGINE_FAILED, null)
        } catch (e: RuntimeException) {
            // WebView package missing or being updated.
            Log.w(TAG) { "WebView package unavailable: ${e.javaClass.simpleName}" }
            return Availability.Unavailable(Reason.ENGINE_FAILED, null)
        }
        val messageListener = try {
            WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER)
        } catch (e: RuntimeException) {
            false
        }
        return availabilityFor(versionName, messageListener)
    }

    /** [check], then (once per process, until it succeeds) the `capabilities` probe of the real engine. */
    suspend fun probe(context: Context, bridge: PublicSignerJsBridge): Availability {
        val gate = check(context)
        if (gate !is Availability.Available || probed.get()) return gate
        val found = try {
            WebViewCompat.getCurrentWebViewPackage(context)?.versionName
        } catch (e: RuntimeException) {
            null
        }
        val capabilities = try {
            bridge.capabilities()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            Log.w(TAG) { "engine probe failed: ${e.javaClass.simpleName}" }
            return Availability.Unavailable(Reason.ENGINE_FAILED, found)
        }
        if (!isExpectedEngine(capabilities)) {
            Log.w(TAG) { "engine probe: unexpected capabilities" }
            return Availability.Unavailable(Reason.ENGINE_FAILED, found)
        }
        probed.set(true)
        return Availability.Available
    }

    /** The version gate as a pure function ([check] minus the WebView lookup). */
    fun availabilityFor(versionName: String, hasWebMessageListener: Boolean): Availability {
        val major = majorVersion(versionName)
        return when {
            major != null && major < MIN_WEBVIEW_MAJOR -> Availability.Unavailable(Reason.WEBVIEW_TOO_OLD, versionName)
            !hasWebMessageListener -> Availability.Unavailable(Reason.WEBVIEW_TOO_OLD, versionName)
            else -> Availability.Available
        }
    }

    /** Leading integer of a WebView version name (`"91.0.4472.114"` → 91), or `null` when there is none. */
    fun majorVersion(versionName: String): Int? =
        versionName.trim().takeWhile { it.isDigit() }.takeIf { it.isNotEmpty() && it.length <= 6 }?.toInt()

    /**
     * `capabilities` of the shipped engine: version 1.0.0, offline, the Ownbit edition's `deviceName` pairing option,
     * its `tronScheme` index option (Ownbit's TRX addresses) and the TronLink ownership check — an older engine is never
     * paired with this Kotlin.
     */
    fun isExpectedEngine(capabilities: JsonObject): Boolean {
        fun primitive(key: String) = capabilities[key] as? JsonPrimitive
        fun strings(element: Any?) = (element as? JsonArray).orEmpty().mapNotNull { (it as? JsonPrimitive)?.takeIf { p -> p.isString }?.content }
        val version = primitive("version")?.takeIf { it.isString }?.content
        val offline = primitive("offline")?.takeIf { !it.isString }?.content
        val options = strings(capabilities["pairingOptions"])
        val indexOptions = strings(capabilities["publicIndexOptions"])
        val tron = strings((capabilities["tron"] as? JsonObject)?.get("supported"))
        return version == ENGINE_VERSION && offline == "true" && "deviceName" in options &&
            TRON_SCHEME_OPTION in indexOptions && TRONLINK_OWNERSHIP_CHECK in tron
    }

    /** The Ownbit edition's TRON address scheme option of `derivePublicIndex` (`capabilities.publicIndexOptions`). */
    const val TRON_SCHEME_OPTION: String = "tronScheme"

    /** The Ownbit edition's TronLink ownership check (`capabilities.tron.supported`). */
    const val TRONLINK_OWNERSHIP_CHECK: String = "TronLink ownership check (exact fixed placeholder)"

    /** Forgets a successful probe (tests only). */
    internal fun resetProbe() {
        probed.set(false)
    }

    private const val TAG = "PublicSigner"
}
