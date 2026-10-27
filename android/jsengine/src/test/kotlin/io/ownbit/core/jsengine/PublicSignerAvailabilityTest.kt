// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.jsengine

import android.content.Context
import android.content.pm.PackageInfo
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import io.mockk.every
import io.mockk.mockk
import io.mockk.mockkStatic
import io.mockk.unmockkAll
import io.ownbit.core.jsengine.PublicSignerAvailability.Availability.Available
import io.ownbit.core.jsengine.PublicSignerAvailability.Availability.Unavailable
import io.ownbit.core.jsengine.PublicSignerAvailability.Reason.ENGINE_FAILED
import io.ownbit.core.jsengine.PublicSignerAvailability.Reason.WEBVIEW_TOO_OLD
import io.ownbit.core.jsengine.bridge.PublicSignerJsBridge
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.After
import org.junit.Before
import org.junit.Test
import java.io.File
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * P T12 on the JVM: the WebView gate of the public protocol (floor **91**, gate item 2A: the Ownbit edition polyfills
 * `Object.hasOwn` / `.at()`, so 91 is the syntax floor; the API 31 emulator ships 91.0.4472.114) and the `capabilities`
 * probe. The instrumented `PublicSignerBundleTest` checks the same gate against the emulator's real WebView.
 */
class PublicSignerAvailabilityTest {

    private val context: Context = mockk(relaxed = true)

    @Before
    fun setUp() {
        mockkStatic(WebViewCompat::class, WebViewFeature::class)
        every { WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER) } returns true
        PublicSignerAvailability.resetProbe()
    }

    @After
    fun tearDown() {
        unmockkAll()
        PublicSignerAvailability.resetProbe()
    }

    private fun webView(versionName: String?) {
        every { WebViewCompat.getCurrentWebViewPackage(any()) } returns versionName?.let { PackageInfo().apply { this.versionName = it } }
    }

    @Test
    fun `major version parsing`() {
        assertEquals(91, PublicSignerAvailability.majorVersion("91.0.4472.114"))
        assertEquals(128, PublicSignerAvailability.majorVersion(" 128.0.6613.146 "))
        assertEquals(84, PublicSignerAvailability.majorVersion("84"))
        assertNull(PublicSignerAvailability.majorVersion(""))
        assertNull(PublicSignerAvailability.majorVersion("dev-build"))
        assertNull(PublicSignerAvailability.majorVersion("99999999999.0"), "absurd numbers are not trusted")
    }

    @Test
    fun `the floor is WebView 91`() {
        assertEquals(91, PublicSignerAvailability.MIN_WEBVIEW_MAJOR)
        assertEquals(Available, PublicSignerAvailability.availabilityFor("91.0.4472.114", true))
        assertEquals(Available, PublicSignerAvailability.availabilityFor("93.0.4577.62", true))
        assertEquals(Unavailable(WEBVIEW_TOO_OLD, "90.0.4430.210"), PublicSignerAvailability.availabilityFor("90.0.4430.210", true))
        assertEquals(Unavailable(WEBVIEW_TOO_OLD, "84.0.4147.111"), PublicSignerAvailability.availabilityFor("84.0.4147.111", true))
        assertEquals(Unavailable(WEBVIEW_TOO_OLD, "120.0"), PublicSignerAvailability.availabilityFor("120.0", false), "no WEB_MESSAGE_LISTENER")
        assertEquals(Available, PublicSignerAvailability.availabilityFor("custom", true), "unknown versions are left to the probe")
    }

    @Test
    fun `check reads the installed WebView`() {
        webView("91.0.4472.114")
        assertEquals(Available, PublicSignerAvailability.check(context))
        webView("90.0.4430.210")
        assertEquals(Unavailable(WEBVIEW_TOO_OLD, "90.0.4430.210"), PublicSignerAvailability.check(context))
        webView(null)
        assertEquals(Unavailable(ENGINE_FAILED, null), PublicSignerAvailability.check(context), "no WebView package")
        every { WebViewCompat.getCurrentWebViewPackage(any()) } throws IllegalStateException("updating")
        assertEquals(Unavailable(ENGINE_FAILED, null), PublicSignerAvailability.check(context))
        webView("120.0.6099.0")
        every { WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER) } returns false
        assertEquals(Unavailable(WEBVIEW_TOO_OLD, "120.0.6099.0"), PublicSignerAvailability.check(context))
    }

    @Test
    fun `the shipped engine's capabilities identify the Ownbit edition`() {
        val golden = goldenCapabilities()
        assertTrue(PublicSignerAvailability.isExpectedEngine(golden))
        assertFalse(PublicSignerAvailability.isExpectedEngine(golden.with("version", JsonPrimitive("1.0.1"))))
        assertFalse(PublicSignerAvailability.isExpectedEngine(golden.with("offline", JsonPrimitive(false))))
        assertFalse(PublicSignerAvailability.isExpectedEngine(golden.with("offline", JsonPrimitive("true"))))
        assertFalse(PublicSignerAvailability.isExpectedEngine(golden - "pairingOptions"), "BitSigner's own build has no deviceName option")
        assertFalse(PublicSignerAvailability.isExpectedEngine(golden.with("pairingOptions", JsonArray(emptyList()))))
        // The TRON address scheme option and the TronLink ownership check are required too.
        assertFalse(PublicSignerAvailability.isExpectedEngine(golden - "publicIndexOptions"), "a round-1 engine has no tronScheme")
        val tron = golden.getValue("tron") as JsonObject
        val roundOneTron = JsonObject(tron + ("supported" to JsonArray((tron.getValue("supported") as JsonArray).filter { (it as JsonPrimitive).content != PublicSignerAvailability.TRONLINK_OWNERSHIP_CHECK })))
        assertFalse(PublicSignerAvailability.isExpectedEngine(golden.with("tron", roundOneTron)), "a round-1 engine has no ownership check")
    }

    @Test
    fun `probe runs capabilities once and remembers success`() = runTest {
        webView("91.0.4472.114")
        val engine = CapabilitiesEngine(goldenCapabilities())
        val bridge = bridgeOn(engine)
        assertEquals(Available, PublicSignerAvailability.probe(context, bridge))
        assertEquals(Available, PublicSignerAvailability.probe(context, bridge))
        assertEquals(1, engine.calls, "a success is remembered")
    }

    @Test
    fun `probe reports ENGINE_FAILED when the engine fails or is not ours`() = runTest {
        webView("91.0.4472.114")
        val failing = CapabilitiesEngine(null)
        assertEquals(Unavailable(ENGINE_FAILED, "91.0.4472.114"), PublicSignerAvailability.probe(context, bridgeOn(failing)))
        val foreign = CapabilitiesEngine(goldenCapabilities() - "pairingOptions")
        assertEquals(Unavailable(ENGINE_FAILED, "91.0.4472.114"), PublicSignerAvailability.probe(context, bridgeOn(foreign)))
        val ours = CapabilitiesEngine(goldenCapabilities())
        assertEquals(Available, PublicSignerAvailability.probe(context, bridgeOn(ours)), "failures are not remembered")
    }

    @Test
    fun `probe does not touch the engine below the floor`() = runTest {
        webView("88.0.4324.181")
        val engine = CapabilitiesEngine(goldenCapabilities())
        assertEquals(Unavailable(WEBVIEW_TOO_OLD, "88.0.4324.181"), PublicSignerAvailability.probe(context, bridgeOn(engine)))
        assertEquals(0, engine.calls)
    }

    /** Answers `capabilities` with [result] (`null` → the page fails to load). */
    private class CapabilitiesEngine(private val result: JsonObject?) : JsEngine {
        var calls = 0
        override val bundle: JsBundle = JsBundle.PUBLIC_SIGNER_PAIRING
        override suspend fun call(function: String, args: JsonArray, timeoutMillis: Long): JsonElement {
            calls++
            val request = Json.parseToJsonElement(args.single().jsonPrimitive.content).jsonObject
            assertEquals("capabilities", request.getValue("operation").jsonPrimitive.content)
            result ?: throw JsBundleLoadException(bundle, "bundle global 'BitSignerEngine' missing after load")
            return JsonPrimitive(JsonObject(mapOf("ok" to JsonPrimitive(true), "result" to result)).toString())
        }

        override suspend fun callForEvent(function: String, args: JsonArray, expect: JsEventSpec, timeoutMillis: Long): JsEvent = error("unused")
        override val unsolicitedEvents: SharedFlow<JsEvent> = MutableSharedFlow()
    }

    private fun bridgeOn(engine: JsEngine): PublicSignerJsBridge =
        PublicSignerJsBridge(mockk<JsEngineManager> { every { engine(JsBundle.PUBLIC_SIGNER_PAIRING) } returns engine })

    /** `capabilities` of the shipped bundle, from the golden vectors (T1). */
    private fun goldenCapabilities(): JsonObject {
        val vectors = Json.parseToJsonElement(File("../../iOS/Tests/OwnbitCoreTests/PublicProtocol/Fixtures/vectors.json").readText()).jsonObject
        val t1 = vectors.getValue("cases").jsonArray.map { it.jsonObject }.single { it.getValue("id").jsonPrimitive.content == "T1-capabilities" }
        return t1.getValue("steps").jsonArray.single().jsonObject.getValue("response").jsonObject.getValue("result").jsonObject
    }

    private fun JsonObject.with(key: String, value: JsonElement) = JsonObject(this + (key to value))

    private operator fun JsonObject.minus(key: String) = JsonObject(this.filterKeys { it != key })
}
