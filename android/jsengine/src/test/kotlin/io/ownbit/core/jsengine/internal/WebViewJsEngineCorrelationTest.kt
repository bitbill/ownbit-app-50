// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.jsengine.internal

import android.content.Context
import android.net.Uri
import android.webkit.CookieManager
import android.webkit.ValueCallback
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.webkit.JavaScriptReplyProxy
import androidx.webkit.WebMessageCompat
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import io.mockk.every
import io.mockk.mockk
import io.mockk.mockkConstructor
import io.mockk.mockkStatic
import io.mockk.slot
import io.mockk.unmockkAll
import io.ownbit.core.jsengine.JsArgs
import io.ownbit.core.jsengine.JsBundle
import io.ownbit.core.jsengine.JsEngineConfig
import io.ownbit.core.jsengine.JsEventFailureException
import io.ownbit.core.jsengine.JsEventSpec
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import kotlinx.serialization.json.put
import org.junit.After
import org.junit.Before
import org.junit.Test
import java.util.IdentityHashMap
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNotSame
import kotlin.test.assertSame
import kotlin.test.assertTrue

/**
 * Request / response correlation of the shared per-bundle page, on the JVM: the WebView is mocked and
 * [FakePage] plays the host shim — it answers `invoke`s with `{t:"r", id}` results and posts bundle callbacks
 * `{t:"e", ch}` (which carry **no** request id, like the real bundles) whenever the test says so.
 *
 * What must hold: every `call` gets the result of its own request id; every `callForEvent` gets the callback of its
 * own request, also when requests overlap, when a call failed or was cancelled while the bundle was still working,
 * and when callbacks arrive with nobody waiting.
 */
class WebViewJsEngineCorrelationTest {

    private val listener = slot<WebViewCompat.WebMessageListener>()

    /**
     * The page the engine currently talks to. Calls on constructor-mocked WebViews all report the same `self`, so the
     * real instance is taken from the static `addWebMessageListener(view, …)` that follows its creation.
     */
    private var currentView: WebView? = null
    private var currentClient: WebViewClient? = null

    /** Pages the engine tore down (`removeWebMessageListener(view, …)` is the first step of its teardown). */
    private val tornDown = IdentityHashMap<WebView, Boolean>()
    private val page = FakePage()
    private val context: Context = mockk(relaxed = true)

    private val multiSigned = JsEventSpec.of("multiSigned")

    @Before
    fun setUp() {
        every { context.applicationContext } returns context
        mockkStatic(WebViewFeature::class)
        every { WebViewFeature.isFeatureSupported(any()) } returns true
        mockkStatic(WebViewCompat::class)
        every { WebViewCompat.addWebMessageListener(any(), any(), any(), capture(listener)) } answers { currentView = firstArg() }
        every { WebViewCompat.removeWebMessageListener(any(), any()) } answers { tornDown[firstArg()] = true }
        mockkStatic(CookieManager::class)
        every { CookieManager.getInstance() } returns mockk(relaxed = true)
        mockkConstructor(WebView::class)
        every { anyConstructed<WebView>().settings } returns mockk(relaxed = true)
        every { anyConstructed<WebView>().setWebViewClient(any()) } answers { currentClient = firstArg() }
        every { anyConstructed<WebView>().loadUrl(any<String>()) } answers {
            currentClient!!.onPageFinished(currentView!!, firstArg())
        }
        every { anyConstructed<WebView>().evaluateJavascript(any(), any()) } answers {
            page.onInvoke(currentView!!, firstArg(), secondArg())
        }
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
        unmockkAll()
    }

    @Test
    fun `overlapping signing requests each get their own callback, one in flight at a time`() = runTest {
        Dispatchers.setMain(UnconfinedTestDispatcher(testScheduler))
        val engine = WebViewJsEngine(JsBundle.TRX, context, JsEngineConfig())
        val a = async { engine.callForEvent("bridge.multiSignTx", JsArgs.of("node", "key", "tx-A"), multiSigned).payload }
        val b = async { engine.callForEvent("bridge.multiSignTx", JsArgs.of("node", "key", "tx-B"), multiSigned).payload }
        runCurrent()

        // B waits for the per-bundle queue: only A reached the page.
        assertEquals(listOf("tx-A"), page.signingRequests())
        page.signLatest()
        runCurrent()
        assertEquals("sig-of-tx-A", a.await())
        assertEquals(listOf("tx-A", "tx-B"), page.signingRequests())
        page.signLatest()
        assertEquals("sig-of-tx-B", b.await())
    }

    @Test
    fun `a failed request never hands its late signature to the next request`() = runTest {
        Dispatchers.setMain(UnconfinedTestDispatcher(testScheduler))
        val engine = WebViewJsEngine(JsBundle.TRX, context, JsEngineConfig())
        val a = async {
            assertFailsWith<JsEventFailureException> {
                engine.callForEvent("bridge.multiSignTx", JsArgs.of("node", "key", "tx-A"), multiSigned)
            }
        }
        runCurrent()
        val viewA = page.lastView()
        // An `error` event (e.g. a late one of an earlier call) fails A while A's signing is still running.
        page.event(viewA, "error", ok = true, payload = "stale failure")
        a.await()

        val b = async { engine.callForEvent("bridge.multiSignTx", JsArgs.of("node", "key", "tx-B"), multiSigned).payload }
        runCurrent()
        // A's signature arrives now, while B waits (without recycling it would complete B: the iOS bug); then B's own.
        page.event(viewA, "multiSigned", ok = true, payload = "sig-of-tx-A")
        page.signLatest()
        assertEquals("sig-of-tx-B", b.await())
        // The page A was signing on was torn down after the failure: nothing it posts later can reach another request.
        assertTrue(tornDown[viewA] == true, "the page is recycled after a failure")
        assertNotSame(viewA, page.lastView())
    }

    @Test
    fun `a cancelled request never hands its late signature to the next request`() = runTest {
        Dispatchers.setMain(UnconfinedTestDispatcher(testScheduler))
        val engine = WebViewJsEngine(JsBundle.TRX, context, JsEngineConfig())
        val a = launch { engine.callForEvent("bridge.multiSignTx", JsArgs.of("node", "key", "tx-A"), multiSigned) }
        runCurrent()
        val viewA = page.lastView()
        // The page that asked for A closed (its ViewModel scope is cancelled) before the signature came back.
        a.cancel()
        runCurrent()
        assertTrue(tornDown[viewA] == true)

        val b = async { engine.callForEvent("bridge.multiSignTx", JsArgs.of("node", "key", "tx-B"), multiSigned).payload }
        runCurrent()
        page.event(viewA, "multiSigned", ok = true, payload = "sig-of-tx-A")
        page.signLatest()
        assertEquals("sig-of-tx-B", b.await())
    }

    @Test
    fun `a callback with nobody waiting is unsolicited and never completes a later request`() = runTest {
        Dispatchers.setMain(UnconfinedTestDispatcher(testScheduler))
        val engine = WebViewJsEngine(JsBundle.TRX, context, JsEngineConfig())
        val unsolicited = async(start = CoroutineStart.UNDISPATCHED) { engine.unsolicitedEvents.first() }
        assertEquals("pong", engine.call("__ownbitHost.ping").jsonPrimitive.content) // page loaded, idle
        val view = page.lastView()
        page.event(view, "multiSigned", ok = true, payload = "sig-of-nobody")
        assertEquals("sig-of-nobody", unsolicited.await().payload)

        val b = async { engine.callForEvent("bridge.multiSignTx", JsArgs.of("node", "key", "tx-B"), multiSigned).payload }
        runCurrent()
        assertFalse(b.isCompleted)
        page.signLatest()
        assertEquals("sig-of-tx-B", b.await())
        assertSame(view, page.lastView(), "a successful request keeps the page")
    }

    @Test
    fun `plain calls only take the result of their own request id`() = runTest {
        Dispatchers.setMain(UnconfinedTestDispatcher(testScheduler))
        val engine = WebViewJsEngine(JsBundle.ETH, context, JsEngineConfig())
        page.onCall = { view, id, fn, args ->
            // A stale result of another request id first, then this request's own.
            page.result(view, id + 1_000, JsonPrimitive("stale"))
            page.result(view, id, JsonPrimitive("$fn(${args[0].jsonPrimitive.content})"))
        }
        val first = async { engine.call("bridge.f", JsArgs.of("one")) }
        val second = async { engine.call("bridge.f", JsArgs.of("two")) }
        assertEquals("bridge.f(one)", first.await().jsonPrimitive.content)
        assertEquals("bridge.f(two)", second.await().jsonPrimitive.content)
    }

    /** The host shim of the hidden page: records `invoke`s and posts results / callbacks through the message listener. */
    private inner class FakePage {
        private val json = Json
        private val requests = mutableListOf<Request>()

        /** What a non-probe `invoke` does; default: resolve it ("ASYNC", the bundles' return value) and wait. */
        var onCall: (view: WebView, id: Long, fn: String, args: JsonArray) -> Unit = { view, id, _, _ -> result(view, id, JsonPrimitive("ASYNC")) }

        private val origin: Uri = mockk {
            every { scheme } returns "https"
            every { host } returns "appassets.androidplatform.net"
            every { port } returns -1
        }

        fun onInvoke(view: WebView, script: String, ack: ValueCallback<String>?) {
            val literal = script.substringAfter("window.__ownbitHost.invoke(").substringBeforeLast(");0")
            val request = json.parseToJsonElement(json.decodeFromString<String>(literal)).jsonObject
            val id = request.getValue("id").jsonPrimitive.long
            val fn = request.getValue("fn").jsonPrimitive.content
            val args = request.getValue("args").jsonArray
            ack?.onReceiveValue(JsProtocol.INVOKE_ACK)
            requests += Request(view, id, fn, args)
            when (fn) {
                "__ownbitHost.has" -> result(view, id, JsonPrimitive(true))
                "__ownbitHost.ping" -> result(view, id, JsonPrimitive("pong"))
                else -> onCall(view, id, fn, args)
            }
        }

        fun lastView(): WebView = requests.last().view

        /** The transactions `multiSignTx` was asked to sign, in order. */
        fun signingRequests(): List<String> = requests.filter { it.fn == "bridge.multiSignTx" }.map { it.args[2].jsonPrimitive.content }

        /** Posts the signature of the latest `multiSignTx` request on the page it was sent to. */
        fun signLatest() {
            val r = requests.last { it.fn == "bridge.multiSignTx" }
            event(r.view, "multiSigned", ok = true, payload = "sig-of-" + r.args[2].jsonPrimitive.content)
        }

        fun result(view: WebView, id: Long, value: JsonElement) = post(view, buildJsonObject {
            put("t", "r")
            put("id", id)
            put("ok", true)
            put("v", value)
        }.toString())

        fun event(view: WebView, channel: String, ok: Boolean, payload: String) = post(view, buildJsonObject {
            put("t", "e")
            put("ch", channel)
            put("ok", ok)
            put("d", payload)
        }.toString())

        private fun post(view: WebView, message: String) {
            listener.captured.onPostMessage(view, WebMessageCompat(message), origin, true, mockk<JavaScriptReplyProxy>(relaxed = true))
        }
    }

    private class Request(val view: WebView, val id: Long, val fn: String, val args: JsonArray)
}
