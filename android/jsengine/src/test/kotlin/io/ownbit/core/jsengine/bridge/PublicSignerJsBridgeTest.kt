// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.jsengine.bridge

import io.mockk.every
import io.mockk.mockk
import io.ownbit.core.jsengine.JsBundle
import io.ownbit.core.jsengine.JsEngine
import io.ownbit.core.jsengine.JsEngineManager
import io.ownbit.core.jsengine.JsEvent
import io.ownbit.core.jsengine.JsEventSpec
import io.ownbit.core.jsengine.JsException
import io.ownbit.core.jsengine.JsResultFormatException
import io.ownbit.core.jsengine.JsTimeoutException
import io.ownbit.core.jsengine.PublicSignerException
import io.ownbit.core.jsengine.internal.JsProtocol
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.int
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import org.junit.Test
import java.io.File
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import kotlin.test.fail

/**
 * [PublicSignerJsBridge] on the JVM: the WebView cannot run here, so a scripted engine records every
 * `BitSignerEngine.dispatch` request and answers it, and a mocked [JsEngineManager] records `restart` / `discardPage`.
 * What the real engine computes on WebView V8 is the instrumented `PublicSignerBundleTest` (golden byte equality with
 * Node), `PublicSignerIsolationTest`, `PublicSignerNoNetworkTest` and `PublicSignerHardeningOnDeviceTest`.
 *
 * Covered here:
 * - exact request JSON per operation: every golden-vector step the frozen API can express is sent byte-identical
 *   (key order included) to the vector request, and the bridge returns the vector's `result` / throws its error;
 * - the seed appears only in the two SECRET operations; `deviceName: "Ownbit"` in every pairing export;
 * - odd characters survive the real `evaluateJavascript` statement unchanged;
 * - error envelopes → [PublicSignerException] (bounded, code-only message), malformed envelopes → [JsResultFormatException];
 * - the size guard (UTF-8 bytes, before any page);
 * - isolation order (restart → call → discard in `finally`, under one mutex), the pairing page never restarted or
 *   discarded, scan sessions (one page, ended by completion / refusal / close / any other operation).
 */
class PublicSignerJsBridgeTest {

    // region harness

    /** A scripted engine per bundle plus a mocked manager that tracks which pages are loaded. */
    private class Harness(scope: CoroutineScope) {
        val events = mutableListOf<String>()
        val requests = mutableListOf<Pair<JsBundle, String>>()
        val loaded = mutableMapOf<JsBundle, Boolean>()
        var responder: suspend (JsBundle, JsonObject) -> String = { _, _ -> OK_EMPTY }
        private val engines = mutableMapOf<JsBundle, FakeEngine>()

        val manager: JsEngineManager = mockk {
            every { engine(any()) } answers { engines.getOrPut(firstArg()) { FakeEngine(firstArg()) } }
            every { restart(any()) } answers { events += "restart ${firstArg<JsBundle>().name}" }
            every { discardPage(any()) } answers {
                val bundle = firstArg<JsBundle>()
                events += "discard ${bundle.name}"
                loaded[bundle] = false
            }
            every { isPageLoaded(any()) } answers { loaded[firstArg()] == true }
        }
        val bridge = PublicSignerJsBridge(manager, scope)

        /** Requests (parsed) the engine received, in order. */
        val sent: List<JsonObject> get() = requests.map { Json.parseToJsonElement(it.second).jsonObject }

        inner class FakeEngine(override val bundle: JsBundle) : JsEngine {
            override suspend fun call(function: String, args: JsonArray, timeoutMillis: Long): JsonElement {
                assertEquals("BitSignerEngine.dispatch", function, "the only JS function the bridge calls")
                assertEquals(1, args.size, "one argument: the request JSON")
                assertTrue(args[0].jsonPrimitive.isString, "the request travels as a JSON string")
                val json = args[0].jsonPrimitive.content
                val request = Json.parseToJsonElement(json).jsonObject
                loaded[bundle] = true
                events += "call ${bundle.name} ${request.getValue("operation").jsonPrimitive.content}"
                requests += bundle to json
                return JsonPrimitive(responder(bundle, request))
            }

            override suspend fun callForEvent(function: String, args: JsonArray, expect: JsEventSpec, timeoutMillis: Long): JsEvent =
                error("the public signer never waits for bundle callbacks")

            override val unsolicitedEvents: SharedFlow<JsEvent> = MutableSharedFlow()
        }
    }

    private fun TestScope.harness() = Harness(this)

    // endregion

    // region golden vectors: exact JSON per operation

    /**
     * Every step of `vectors.json` (the golden requests and responses of the shipped engine in Node) that the frozen
     * bridge API can express goes through the bridge: the engine must receive exactly the vector's request text (same
     * keys, same order, fixtures substituted) and the bridge must return the vector's `result` or throw its error.
     * The steps it cannot express are pinned below (the bridge always sends `deviceName: "Ownbit"`, always sends
     * `start` / `count`, has no `fragmentLength` for pairing, begins every scan with `scanBegin`, has no unknown
     * operation, and does not resolve a request the engine refused to review: it throws the review's code instead).
     */
    @Test
    fun `every expressible golden vector step is sent exactly and answered like the vector`() = runTest {
        val h = harness()
        val queue = ArrayDeque<Pair<JsonObject, String>>()
        h.responder = { _, request ->
            val (expected, response) = queue.removeFirstOrNull() ?: fail("unexpected engine call ${request["operation"]}")
            assertEquals(expected.toString(), request.toString(), "request text")
            response
        }
        val replay = VectorReplay(h.bridge, queue)
        for (case in Vectors.cases) replay.run(case)
        assertTrue(queue.isEmpty(), "expected requests never sent: ${queue.map { it.first["operation"] }}")
        assertEquals(EXPECTED_SKIPS, replay.skipped, "steps the bridge cannot express")
        assertEquals(Vectors.stepCount - EXPECTED_SKIPS.size, replay.covered, "all other steps covered")
        assertTrue(replay.covered >= 470, "covered ${replay.covered}")
    }

    /** Drives one vector case through the bridge (shared shape with the instrumented `PublicSignerBundleTest`). */
    private class VectorReplay(private val bridge: PublicSignerJsBridge, private val queue: ArrayDeque<Pair<JsonObject, String>>) {
        var covered = 0
        val skipped = mutableListOf<String>()

        private fun expect(step: Vectors.Step) {
            queue += step.request to step.response.toString()
            covered++
        }

        suspend fun run(case: Vectors.Case) {
            for (page in case.pages) {
                val ops = page.map { it.op }
                when {
                    ops.all { it in PAIRING_OPS } -> page.forEach { pairing(case, it) }
                    ops.first() == "scanBegin" && ops.drop(1).all { it == "scanAdd" } -> scan(case, page)
                    ops == listOf("review", "resolveSigningPlan") || ops == listOf("review") || ops == listOf("resolveSigningPlan") ->
                        reviewAndResolve(case, page)
                    ops.size == 1 && ops[0] in SINGLE_OPS -> single(page[0])
                    ops.all { it == "scanAdd" || it == "noSuchOperation" } -> page.forEach { skipped += "${case.id}:${it.op}" }
                    else -> fail("${case.id}: page pattern $ops is not mapped")
                }
            }
        }

        private suspend fun pairing(case: Vectors.Case, step: Vectors.Step) {
            val r = step.request
            when (step.op) {
                "capabilities" -> {
                    expect(step)
                    outcome(step) { bridge.capabilities() }
                }
                "derivePublicAddresses" -> {
                    if ("start" !in r || "count" !in r) return run { skipped += "${case.id}:${step.op}" }
                    expect(step)
                    outcome(step) {
                        bridge.derivePublicAddresses(r.obj("publicIndex"), r.str("chain"), r.strOrNull("profile"), r.int("start"), r.int("count"))
                    }
                }
                "createPublicPairing" -> {
                    val chain = r.str("chain")
                    val index = r["index"]?.jsonPrimitive?.intOrNull ?: 0
                    val expressible = r["deviceName"] == JsonPrimitive("Ownbit") && "fragmentLength" !in r &&
                        ("index" in r) == (chain == "tron" || index != 0)
                    if (!expressible) return run { skipped += "${case.id}:${step.op}" }
                    expect(step)
                    outcome(step) { bridge.createPublicPairing(r.obj("publicIndex"), chain, r.strOrNull("profile"), r.strOrNull("outputMode"), index) }
                }
                else -> fail(step.op)
            }
        }

        private suspend fun scan(case: Vectors.Case, page: List<Vectors.Step>) {
            expect(page[0])
            if (!page[0].ok) return outcome(page[0]) { bridge.openScan(); null }
            val handle = bridge.openScan()
            var ended = false
            for (step in page.drop(1)) {
                if (ended) {
                    skipped += "${case.id}:${step.op} after the session ended"
                    continue
                }
                expect(step)
                outcome(step) { handle.add(step.request.str("frame")) }
                ended = !step.ok || step.result?.get("complete") == JsonPrimitive(true)
            }
            handle.close()
        }

        private suspend fun reviewAndResolve(case: Vectors.Case, page: List<Vectors.Step>) {
            val review = page.firstOrNull { it.op == "review" }
            val resolve = page.firstOrNull { it.op == "resolveSigningPlan" }
            val request = (review ?: resolve)!!.request.obj("request")
            if (review != null) expect(review) else queue += buildJsonObject {
                put("operation", "review")
                put("request", request)
            } to OK_EMPTY // the bridge always reviews first; this vector page has no review step
            if (review != null && !review.ok) {
                // The bridge reports the review's precise code (e.g. LOOKUP_TABLE) instead of resolving to `invalid`.
                if (resolve != null) skipped += "${case.id}:resolveSigningPlan after a review refusal"
                return outcome(review) { bridge.reviewAndResolve(request, JsonArray(emptyList())).plan }
            }
            if (resolve == null) {
                // A review-only page that succeeded: the bridge would also resolve, which the vector does not record.
                queue.removeLast()
                covered--
                skipped += "${case.id}:review without resolve"
                return
            }
            expect(resolve)
            val wallets = resolve.request.getValue("wallets").jsonArray
            if (!resolve.ok) return outcome(resolve) { bridge.reviewAndResolve(request, wallets).plan }
            val both = bridge.reviewAndResolve(request, wallets)
            assertEquals(review?.result ?: JsonObject(emptyMap()), both.review, "${case.id} review")
            assertEquals(resolve.result, both.plan, "${case.id} plan")
        }

        private suspend fun single(step: Vectors.Step) {
            val r = step.request
            expect(step)
            outcome(step) {
                when (step.op) {
                    // The Ownbit edition's TRON address scheme options, and `publicIndex` in place of the seed.
                    "derivePublicIndex" -> if (r["publicIndex"] != null) {
                        bridge.refreshPublicIndex(r.obj("publicIndex"), r.str("tronScheme"), r["tronAddressCount"]?.jsonPrimitive?.int)
                    } else {
                        bridge.derivePublicIndex(r.str("seed").toCharArray(), r["tronScheme"]?.jsonPrimitive?.content, r["tronAddressCount"]?.jsonPrimitive?.int)
                    }
                    "signPlanTask" -> bridge.signPlanTask(
                        r.obj("request"), r.obj("plan"), r.str("taskId"), r.str("seed").toCharArray(),
                        r.getValue("riskAcknowledged").jsonPrimitive.boolean, r["previousResult"]?.jsonObject,
                    )
                    "encodeResponse" -> bridge.encodeResponse(r.obj("request"), r.obj("result"), r["fragmentLength"]?.jsonPrimitive?.int)
                    "decodePayload" -> bridge.decodePayload(r.str("payload"))
                    else -> fail(step.op)
                }
            }
        }

        /** The bridge returns the vector's `result`, or throws its error as [PublicSignerException]. */
        private suspend fun outcome(step: Vectors.Step, block: suspend () -> JsonObject?) {
            if (step.ok) {
                val result = block()
                if (result != null) assertEquals(step.result, result, "${step.op} result")
                return
            }
            val error = step.response.obj("error")
            val thrown = try {
                block()
                fail("${step.op}: expected ${error.str("code")}")
            } catch (e: PublicSignerException) {
                e
            }
            assertEquals(error.str("code"), thrown.code)
            assertEquals(error.str("message").take(PublicSignerException.MAX_MESSAGE), thrown.engineMessage)
            assertFalse(error.str("message") in thrown.toString(), "the engine text never reaches the exception message")
        }
    }

    // endregion

    // region request content

    @Test
    fun `operations send their parameters with JSON types and fixed key order`() = runTest {
        val h = harness()
        val index = buildJsonObject { put("walletKeyId", "k") }
        h.bridge.derivePublicAddresses(index, "evm", null, 7, 1)
        h.bridge.createPublicPairing(index, "tron", "standard", "address")
        h.bridge.createPublicPairing(index, "evm", null, "wallet")
        h.bridge.signPlanTask(index, index, "t1", SEED.toCharArray(), riskAcknowledged = true, previousResult = null)
        h.bridge.encodeResponse(index, index, fragmentLength = 200)
        assertEquals(
            listOf(
                """{"operation":"derivePublicAddresses","publicIndex":{"walletKeyId":"k"},"chain":"evm","start":7,"count":1}""",
                """{"operation":"createPublicPairing","publicIndex":{"walletKeyId":"k"},"chain":"tron","profile":"standard","outputMode":"address","index":0,"deviceName":"Ownbit"}""",
                """{"operation":"createPublicPairing","publicIndex":{"walletKeyId":"k"},"chain":"evm","outputMode":"wallet","deviceName":"Ownbit"}""",
                """{"operation":"signPlanTask","request":{"walletKeyId":"k"},"plan":{"walletKeyId":"k"},"taskId":"t1","seed":"$SEED","riskAcknowledged":true}""",
                """{"operation":"encodeResponse","request":{"walletKeyId":"k"},"result":{"walletKeyId":"k"},"fragmentLength":200}""",
            ),
            h.requests.map { it.second },
        )
    }

    @Test
    fun `the seed appears only in derivePublicIndex and signPlanTask, never on the pairing page`() = runTest {
        val h = harness()
        h.responder = { _, request -> if (request.str("operation") == "scanBegin") OK_STARTED else OK_EMPTY }
        val index = buildJsonObject { put("walletKeyId", "k") }
        h.bridge.capabilities()
        h.bridge.derivePublicAddresses(index, "bitcoin", "native", 0, 3)
        h.bridge.createPublicPairing(index, "solana", "standard", "wallet")
        h.bridge.derivePublicIndex(SEED.toCharArray())
        h.bridge.decodePayload("cHNidP8B")
        h.bridge.reviewAndResolve(index, buildJsonArray { add(buildJsonObject { put("localWalletId", "w") }) })
        h.bridge.signPlanTask(index, index, "t", SEED.toCharArray(), false, index)
        h.bridge.encodeResponse(index, index)
        h.bridge.openScan().add("UR:ETH-SIGN-REQUEST/X")
        val withSeed = h.requests.filter { SEED in it.second }.map { Json.parseToJsonElement(it.second).jsonObject.str("operation") }
        assertEquals(listOf("derivePublicIndex", "signPlanTask"), withSeed)
        assertTrue(h.requests.filter { it.first == JsBundle.PUBLIC_SIGNER_PAIRING }.none { "seed" in it.second })
        assertEquals(
            listOf("capabilities", "derivePublicAddresses", "createPublicPairing"),
            h.requests.filter { it.first == JsBundle.PUBLIC_SIGNER_PAIRING }.map { Json.parseToJsonElement(it.second).jsonObject.str("operation") },
            "only PAIRING operations reach the pairing page",
        )
        val seedRequests = h.sent.filter { it.str("operation") in setOf("derivePublicIndex", "signPlanTask") }
        assertTrue(seedRequests.all { it.str("seed") == SEED })
    }

    /** Gate item 2A: the engine default is "BitSigner" (vectors T3-pairing-default-name-*); Ownbit always names itself. */
    @Test
    fun `every pairing export carries deviceName Ownbit`() = runTest {
        val h = harness()
        val index = buildJsonObject { put("walletKeyId", "k") }
        for ((chain, profile, mode) in PAIRING_MATRIX) h.bridge.createPublicPairing(index, chain, profile, mode)
        assertEquals(PAIRING_MATRIX.size, h.sent.size)
        assertTrue(h.sent.all { it["deviceName"] == OWNBIT_NAME }, "deviceName in ${h.sent}")
        assertEquals("Ownbit", PublicSignerJsBridge.DEVICE_NAME)
        val defaultNamed = Vectors.cases.filter { it.id.startsWith("T3-pairing-default-name-") }
        assertEquals(3, defaultNamed.size)
        for (case in defaultNamed) {
            val response = case.pages.single().single().response.toString()
            assertTrue("BitSigner" in response && "Ownbit" !in response, "${case.id} documents the engine default")
        }
        val ownbitNamed = Vectors.cases.filter {
            it.id.startsWith("T3-pairing-") && it.pages.size == 1 && it.pages[0].size == 1 && it.pages[0][0].request["deviceName"] == OWNBIT_NAME
        }
        assertTrue(ownbitNamed.size >= 24)
        for (case in ownbitNamed.filter { it.pages.single().single().ok && it.pages.single().single().request["outputMode"]?.jsonPrimitive?.content != "address" }) {
            val payload = case.pages.single().single().result!!.toString()
            assertTrue("BitSigner" !in payload, "${case.id}: no BitSigner name in an Ownbit export")
        }
    }

    @Test
    fun `odd characters reach the page unchanged through the real evaluateJavascript statement`() = runTest {
        val h = harness()
        h.responder = { _, request -> if (request.str("operation") == "scanBegin") OK_STARTED else OK_EMPTY }
        h.bridge.decodePayload(ODD)
        h.bridge.openScan().add(ODD)
        h.bridge.reviewAndResolve(buildJsonObject { put("chain", ODD) }, buildJsonArray { add(buildJsonObject { put("localWalletId", ODD) }) })
        for ((_, json) in h.requests) {
            val inPage = requestInThePage(json)
            assertEquals(Json.parseToJsonElement(json), inPage)
        }
        assertEquals(ODD, requestInThePage(h.requests[0].second).str("payload"))
        assertEquals(ODD, requestInThePage(h.requests[2].second).str("frame"))
        assertEquals(ODD, requestInThePage(h.requests.last().second).getValue("wallets").jsonArray[0].jsonObject.str("localWalletId"))
    }

    /** What the engine's `JSON.parse` sees: the request string decoded from the real `evaluateJavascript` statement. */
    private fun requestInThePage(json: String): JsonObject {
        val script = JsProtocol.invokeScript(1, "BitSignerEngine.dispatch", io.ownbit.core.jsengine.JsArgs.of(json))
        assertTrue(script.all { it.code in 0x20..0x7E }, "the statement is plain ASCII")
        val literal = script.removePrefix("window.__ownbitHost.invoke(").removeSuffix(");0")
        val invoke = Json.parseToJsonElement(Json.parseToJsonElement(literal).jsonPrimitive.content).jsonObject
        assertEquals("BitSignerEngine.dispatch", invoke.str("fn"))
        return Json.parseToJsonElement(invoke.getValue("args").jsonArray.single().jsonPrimitive.content).jsonObject
    }

    // endregion

    // region responses and errors

    @Test
    fun `an engine refusal becomes a bounded PublicSignerException whose message carries only the code`() = runTest {
        val h = harness()
        val long = "m".repeat(399) + "😀" + "tail"
        h.responder = { _, _ -> error("bad_code !", long) }
        val e = assertFailsWith<PublicSignerException> { h.bridge.decodePayload("x") }
        assertEquals("BAD_CODE", e.code)
        assertEquals("m".repeat(399), e.engineMessage, "never cut inside a surrogate pair")
        assertEquals(JsBundle.PUBLIC_SIGNER, e.bundle)
        assertEquals("Public signer refused the request: BAD_CODE", e.message)
        assertFalse("mmm" in e.toString())

        h.responder = { _, _ -> """{"ok":false,"error":{}}""" }
        val defaults = assertFailsWith<PublicSignerException> { h.bridge.capabilities() }
        assertEquals("SIGNING_FAILED", defaults.code)
        assertEquals("This request could not be signed.", defaults.engineMessage)
        assertEquals(JsBundle.PUBLIC_SIGNER_PAIRING, defaults.bundle)

        h.responder = { _, _ -> error("X".repeat(200), "short") }
        assertEquals(80, assertFailsWith<PublicSignerException> { h.bridge.capabilities() }.code.length)
        assertTrue(PublicSignerException("", "m").code == "UNKNOWN")
    }

    @Test
    fun `malformed engine envelopes are result-format errors`() = runTest {
        val h = harness()
        for (raw in listOf(
            "not json", "[]", "{}", """{"ok":"true","result":{}}""", """{"ok":true}""", """{"ok":true,"result":[1]}""",
            """{"ok":true,"result":"x"}""", """{"ok":1,"result":{}}""",
        )) {
            h.responder = { _, _ -> raw }
            assertFailsWith<JsResultFormatException>(raw) { h.bridge.capabilities() }
        }
        h.responder = { _, _ -> """{"ok":true,"result":{"x":"${"a".repeat(2_097_152)}"}}""" }
        assertFailsWith<JsResultFormatException>("responses above 2 MiB") { h.bridge.capabilities() }
    }

    @Test
    fun `a request above one million UTF-8 bytes is refused before any engine call`() = runTest {
        val h = harness()
        val overhead = """{"operation":"decodePayload","payload":""}""".length
        h.bridge.decodePayload("a".repeat(1_000_000 - overhead))
        assertEquals(1_000_000, h.requests.single().second.length)
        h.requests.clear()
        h.events.clear()
        val tooLarge = assertFailsWith<PublicSignerException> { h.bridge.decodePayload("a".repeat(1_000_001 - overhead)) }
        assertEquals("LIMIT", tooLarge.code)
        // Multi-byte text counts as the engine counts it (Buffer.byteLength): 333,334 × 3 bytes > 1,000,000.
        assertFailsWith<PublicSignerException> { h.bridge.decodePayload("中".repeat(333_334)) }
        assertTrue(h.requests.isEmpty(), "nothing reached the engine")
        assertTrue(h.events.none { it.startsWith("call") })
        assertEquals(1_000_000L, PublicSignerJsBridge.MAX_REQUEST_BYTES)
    }

    @Test
    fun `utf8 length counts like the engine`() {
        assertEquals(0, PublicSignerJsBridge.utf8Length(""))
        assertEquals(3, PublicSignerJsBridge.utf8Length("abc"))
        assertEquals(2, PublicSignerJsBridge.utf8Length("é"))
        assertEquals(3, PublicSignerJsBridge.utf8Length("中"))
        assertEquals(4, PublicSignerJsBridge.utf8Length("😀"))
        assertEquals(3, PublicSignerJsBridge.utf8Length("\uD83D"), "a lone surrogate becomes U+FFFD")
        assertEquals(6, PublicSignerJsBridge.utf8Length("\uDE00\uD83D"))
    }

    @Test
    fun `a review refusal throws with the engine code and never runs the resolver`() = runTest {
        val h = harness()
        h.responder = { _, request -> if (request.str("operation") == "review") error("NETWORK", "Unsupported EVM network.") else OK_EMPTY }
        val e = assertFailsWith<PublicSignerException> { h.bridge.reviewAndResolve(buildJsonObject { put("chain", "evm") }, JsonArray(emptyList())) }
        assertEquals("NETWORK", e.code)
        assertEquals(listOf("restart PUBLIC_SIGNER", "call PUBLIC_SIGNER review", "discard PUBLIC_SIGNER"), h.events)
        val shown = ReviewAndPlan(buildJsonObject { put("title", "secret-ish") }, buildJsonObject { put("status", "ready") }).toString()
        assertFalse("secret-ish" in shown || "ready" in shown, shown)
    }

    // endregion

    // region isolation

    @Test
    fun `isolated operations restart the page, make their calls and discard it`() = runTest {
        val h = harness()
        val o = buildJsonObject { put("k", "v") }
        h.bridge.derivePublicIndex(SEED.toCharArray())
        h.bridge.signPlanTask(o, o, "t", SEED.toCharArray(), true, null)
        h.bridge.decodePayload("p")
        h.bridge.reviewAndResolve(o, JsonArray(emptyList()))
        h.bridge.encodeResponse(o, o)
        val ps = "PUBLIC_SIGNER"
        assertEquals(
            listOf("derivePublicIndex", "signPlanTask", "decodePayload").flatMap { listOf("restart $ps", "call $ps $it", "discard $ps") } +
                listOf("restart $ps", "call $ps review", "call $ps resolveSigningPlan", "discard $ps") +
                listOf("restart $ps", "call $ps encodeResponse", "discard $ps"),
            h.events,
        )
        assertFalse(h.manager.isPageLoaded(JsBundle.PUBLIC_SIGNER))
    }

    @Test
    fun `pairing operations use the warm pairing page and never restart or discard it`() = runTest {
        val h = harness()
        val index = buildJsonObject { put("walletKeyId", "k") }
        h.bridge.capabilities()
        h.bridge.derivePublicAddresses(index, "evm", null, 0, 1)
        h.bridge.createPublicPairing(index, "evm", null, null)
        val pp = "PUBLIC_SIGNER_PAIRING"
        assertEquals(listOf("call $pp capabilities", "call $pp derivePublicAddresses", "call $pp createPublicPairing"), h.events)
        assertTrue(h.manager.isPageLoaded(JsBundle.PUBLIC_SIGNER_PAIRING))
        h.bridge.releasePairingPage()
        assertEquals("discard $pp", h.events.last())
    }

    @Test
    fun `the page is discarded on refusal, failure and cancellation`() = runTest {
        val h = harness()
        h.responder = { _, _ -> error("SIGNER", "Signing request belongs to a different wallet.") }
        assertFailsWith<PublicSignerException> { h.bridge.signPlanTask(EMPTY, EMPTY, "t", SEED.toCharArray(), false, null) }
        assertEquals("discard PUBLIC_SIGNER", h.events.last())

        h.events.clear()
        h.responder = { _, _ -> throw JsTimeoutException(JsBundle.PUBLIC_SIGNER, "BitSignerEngine.dispatch", 60_000) }
        assertFailsWith<JsTimeoutException> { h.bridge.derivePublicIndex(SEED.toCharArray()) }
        assertEquals(listOf("restart PUBLIC_SIGNER", "discard PUBLIC_SIGNER"), h.events.filter { !it.startsWith("call") })

        h.events.clear()
        val entered = CompletableDeferred<Unit>()
        h.responder = { _, _ ->
            entered.complete(Unit)
            awaitCancellation()
        }
        val job = launch { h.bridge.derivePublicIndex(SEED.toCharArray()) }
        entered.await()
        job.cancel()
        job.join()
        assertEquals(listOf("restart PUBLIC_SIGNER", "call PUBLIC_SIGNER derivePublicIndex", "discard PUBLIC_SIGNER"), h.events)
    }

    @Test
    fun `isolated sequences never interleave`() = runTest {
        val h = harness()
        val release = CompletableDeferred<Unit>()
        h.responder = { _, request ->
            if (request.str("operation") == "derivePublicIndex") release.await()
            OK_EMPTY
        }
        val first = async { h.bridge.derivePublicIndex(SEED.toCharArray()) }
        runCurrent()
        val second = async { h.bridge.decodePayload("p") }
        runCurrent()
        assertEquals(listOf("restart PUBLIC_SIGNER", "call PUBLIC_SIGNER derivePublicIndex"), h.events, "the second waits for the mutex")
        release.complete(Unit)
        first.await()
        second.await()
        assertEquals(
            listOf(
                "restart PUBLIC_SIGNER", "call PUBLIC_SIGNER derivePublicIndex", "discard PUBLIC_SIGNER",
                "restart PUBLIC_SIGNER", "call PUBLIC_SIGNER decodePayload", "discard PUBLIC_SIGNER",
            ),
            h.events,
        )
    }

    // endregion

    // region scan sessions

    @Test
    fun `a scan session keeps its page until the request is complete`() = runTest {
        val h = harness()
        var adds = 0
        h.responder = { _, request ->
            when (request.str("operation")) {
                "scanBegin" -> OK_STARTED
                else -> if (++adds < 3) """{"ok":true,"result":{"complete":false,"progress":0.5}}""" else """{"ok":true,"result":{"complete":true,"progress":1,"request":{"chain":"evm"}}}"""
            }
        }
        val scan = h.bridge.openScan()
        assertTrue(scan.add("UR:A/1-3/X")["complete"] == JsonPrimitive(false))
        scan.add("UR:A/2-3/X")
        assertEquals(listOf("restart PUBLIC_SIGNER", "call PUBLIC_SIGNER scanBegin", "call PUBLIC_SIGNER scanAdd", "call PUBLIC_SIGNER scanAdd"), h.events)
        val done = scan.add("UR:A/3-3/X")
        assertEquals(buildJsonObject { put("chain", "evm") }, done["request"])
        assertEquals("discard PUBLIC_SIGNER", h.events.last(), "complete ends the session and discards its page")
        val ended = assertFailsWith<PublicSignerException> { scan.add("UR:A/1-3/X") }
        assertEquals("SCAN", ended.code)
        assertEquals(4, h.events.count { it.startsWith("call") }, "an ended session never reaches the engine")
        assertTrue(scan.sessionId > 0)
    }

    @Test
    fun `a refused frame ends the session`() = runTest {
        val h = harness()
        h.responder = { _, request ->
            if (request.str("operation") == "scanBegin") OK_STARTED else error("QR_PROTOCOL", "Mixed UR fountain sessions")
        }
        val scan = h.bridge.openScan()
        assertEquals("QR_PROTOCOL", assertFailsWith<PublicSignerException> { scan.add("UR:B/1-2/Y") }.code)
        assertEquals("discard PUBLIC_SIGNER", h.events.last())
        assertEquals("SCAN", assertFailsWith<PublicSignerException> { scan.add("UR:B/1-2/Y") }.code)
    }

    @Test
    fun `another isolated operation or a new scan ends the open session`() = runTest {
        val h = harness()
        h.responder = { _, request -> if (request.str("operation") == "scanBegin") OK_STARTED else OK_EMPTY }
        val first = h.bridge.openScan()
        first.add("f")
        h.bridge.decodePayload("p")
        assertEquals("SCAN", assertFailsWith<PublicSignerException> { first.add("f") }.code)
        val second = h.bridge.openScan()
        val third = h.bridge.openScan()
        assertEquals("SCAN", assertFailsWith<PublicSignerException> { second.add("f") }.code)
        third.add("f")
        assertTrue(third.sessionId > second.sessionId && second.sessionId > first.sessionId)
        assertEquals(
            listOf(
                "restart", "call scanBegin", "call scanAdd",
                "discard", "restart", "call decodePayload", "discard",
                "restart", "call scanBegin",
                "discard", "restart", "call scanBegin",
                "call scanAdd",
            ),
            h.events.map { it.replace(" PUBLIC_SIGNER", "") },
        )
    }

    @Test
    fun `close discards the session page in order, and a superseded close leaves the new page alone`() = runTest {
        val h = harness()
        h.responder = { _, request -> if (request.str("operation") == "scanBegin") OK_STARTED else OK_EMPTY }
        val first = h.bridge.openScan()
        first.close()
        runCurrent()
        assertEquals("discard PUBLIC_SIGNER", h.events.last())
        assertFalse(h.manager.isPageLoaded(JsBundle.PUBLIC_SIGNER))
        assertEquals("SCAN", assertFailsWith<PublicSignerException> { first.add("f") }.code)

        val second = h.bridge.openScan()
        val third = h.bridge.openScan() // ends `second`
        second.close() // must not touch third's page
        runCurrent()
        third.add("f")
        assertEquals(listOf("restart", "call scanBegin", "call scanAdd"), h.events.takeLast(3).map { it.replace(" PUBLIC_SIGNER", "") })
        third.close()
        third.close() // idempotent
        runCurrent()
        assertEquals(1, h.events.takeLast(2).count { it == "discard PUBLIC_SIGNER" })
    }

    @Test
    fun `a session whose page went away reports SCAN without loading a new page`() = runTest {
        val h = harness()
        h.responder = { _, request -> if (request.str("operation") == "scanBegin") OK_STARTED else OK_EMPTY }
        val scan = h.bridge.openScan()
        h.loaded[JsBundle.PUBLIC_SIGNER] = false // idle sweep / renderer death
        assertEquals("SCAN", assertFailsWith<PublicSignerException> { scan.add("f") }.code)
        assertEquals(1, h.events.count { it.startsWith("call") })
    }

    @Test
    fun `a scanBegin that does not start a session fails and discards the page`() = runTest {
        val h = harness()
        h.responder = { _, _ -> OK_EMPTY }
        assertFailsWith<JsResultFormatException> { h.bridge.openScan() }
        assertEquals("discard PUBLIC_SIGNER", h.events.last())
        h.responder = { _, _ -> error("LIMIT", "x") }
        assertFailsWith<JsException> { h.bridge.openScan() }
        assertEquals("discard PUBLIC_SIGNER", h.events.last())
    }

    // endregion

    // region log hygiene

    /**
     * Log hygiene of the bridge: a source scan of the
     * public-signer files of this module. Every log call is one line `Log.x(TAG) { "…" }` and interpolates only the
     * operation's wire name, an engine code or an exception class name — never a request, a frame, a seed, an engine
     * message or a result.
     */
    @Test
    fun `public-signer log lines interpolate only operation names, codes and class names`() {
        val main = File("src/main/kotlin/io/ownbit/core/jsengine")
        val files = listOf("bridge/PublicSignerJsBridge.kt", "bridge/PublicSignerOp.kt", "bridge/PublicSignerException.kt", "PublicSignerAvailability.kt")
            .map { File(main, it) }
        files.forEach { assertTrue(it.isFile, "missing ${it.path} (run with the module directory as working directory)") }
        val logCall = Regex("""\bLog\.[a-z]\(""")
        val singleLine = Regex("""\bLog\.[a-z]\(TAG\) \{ "((?:[^"\\]|\\.)*)" \}""")
        val interpolation = Regex("""\$\{([^}]*)\}|\$([A-Za-z_][A-Za-z0-9_]*)""")
        val allowed = setOf("op.wire", "e.code", "e.javaClass.simpleName")
        var calls = 0
        val violations = mutableListOf<String>()
        for (file in files) {
            file.readLines().forEachIndexed { i, line ->
                if (!logCall.containsMatchIn(line)) return@forEachIndexed
                val where = "${file.name}:${i + 1}"
                val template = singleLine.find(line)?.groupValues?.get(1)
                if (template == null) {
                    violations += "$where: a log call must be one line `Log.x(TAG) { \"…\" }`: ${line.trim()}"
                    return@forEachIndexed
                }
                calls++
                interpolation.findAll(template).map { it.groupValues[1].ifEmpty { it.groupValues[2] } }
                    .filter { it !in allowed }.forEach { violations += "$where: logs `$it`" }
            }
        }
        assertTrue(calls >= 4, "the scan found only $calls log calls")
        if (violations.isNotEmpty()) fail("Payload-bearing log lines:\n" + violations.joinToString("\n"))
    }

    // endregion

    private companion object {
        const val SEED = "5eb00bbddcf069084889a8ab9155568165f5c453ccb85e70811aaed6f6da5fc19a5ac40b389cd370d086206dec8aa6c43daea6690f20ad3d8d48b2d2ce9e38e4"
        const val OK_EMPTY = """{"ok":true,"result":{}}"""
        const val OK_STARTED = """{"ok":true,"result":{"started":true}}"""

        /** Quotes, backslash, CR-LF, tab, NUL, emoji, `</script>`, U+2028 / U+2029, a lone surrogate, BOM, RTL override. */
        const val ODD = "q\"uote\\ back\r\n tab\t nul\u0000 😀 </script><script>x</script>    lone\uD83D ﻿ ‮ end"

        val EMPTY = JsonObject(emptyMap())
        val OWNBIT_NAME = JsonPrimitive("Ownbit")

        val PAIRING_OPS = setOf("capabilities", "derivePublicAddresses", "createPublicPairing")
        val SINGLE_OPS = setOf("derivePublicIndex", "signPlanTask", "encodeResponse", "decodePayload")

        val PAIRING_MATRIX = listOf("native", "taproot", "nested", "legacy").flatMap { p -> listOf("accountXpub", "address").map { Triple("bitcoin", p, it) } } +
            listOf(Triple("bitcoin", "multisig-native", "accountXpub"), Triple("bitcoin", "multisig-nested", "accountXpub")) +
            listOf("wallet", "address").map { Triple("evm", null, it) } +
            listOf("standard", "trust", "legacy").flatMap { p -> listOf("wallet", "address").map { Triple("solana", p, it) } } +
            listOf(Triple("tron", "standard", "address"))

        /** Vector steps the frozen bridge API cannot produce (see the replay test's KDoc). */
        val EXPECTED_SKIPS = listOf(
            "T3-pairing-default-name-evm:createPublicPairing",
            "T3-pairing-default-name-bitcoin:createPublicPairing",
            "T3-pairing-default-name-solana:createPublicPairing",
            "T3-pairing-animated-bitcoin:createPublicPairing",
            "T3-pairing-animated-evm:createPublicPairing",
            "T3-pairing-invalid:createPublicPairing",
            "T3-pairing-invalid:createPublicPairing",
            "T3b-addresses-invalid:derivePublicAddresses",
            "T3b-addresses-invalid:derivePublicAddresses",
            "T5-no-session:scanAdd",
            "T9-tron-type-url-bom:resolveSigningPlan after a review refusal",
            "T9-unknown-operation:noSuchOperation",
            "O-BTC-1-prevout-mismatch:resolveSigningPlan after a review refusal",
            "O-SOL-2-lookup-table:resolveSigningPlan after a review refusal",
        )

        fun error(code: String, message: String): String = buildJsonObject {
            put("ok", false)
            put("error", buildJsonObject {
                put("code", code)
                put("message", message)
            })
        }.toString()

        fun JsonObject.str(key: String): String = getValue(key).jsonPrimitive.content
        fun JsonObject.strOrNull(key: String): String? = this[key]?.jsonPrimitive?.content
        fun JsonObject.int(key: String): Int = getValue(key).jsonPrimitive.int
        fun JsonObject.obj(key: String): JsonObject = getValue(key).jsonObject
    }

    /** `vectors.json` (androidTest assets of this module), with `{"$fixture": name}` replaced by the fixture. */
    private object Vectors {
        class Step(val page: Int, val request: JsonObject, val response: JsonObject) {
            val op: String get() = request.getValue("operation").jsonPrimitive.content
            val ok: Boolean get() = response.getValue("ok").jsonPrimitive.boolean
            val result: JsonObject? get() = response["result"] as? JsonObject
        }

        class Case(val id: String, val pages: List<List<Step>>)

        private val root: JsonObject = Json.parseToJsonElement(File("../../iOS/Tests/OwnbitCoreTests/PublicProtocol/Fixtures/vectors.json").readText()).jsonObject
        private val fixtures = root.getValue("fixtures").jsonObject

        val cases: List<Case> = root.getValue("cases").jsonArray.map { element ->
            val case = element.jsonObject
            val steps = case.getValue("steps").jsonArray.map {
                val s = it.jsonObject
                Step(s.getValue("page").jsonPrimitive.int, resolve(s.getValue("request")).jsonObject, s.getValue("response").jsonObject)
            }
            val pages = mutableListOf<MutableList<Step>>()
            for (step in steps) {
                if (pages.isEmpty() || pages.last().last().page != step.page) pages += mutableListOf(step) else pages.last() += step
            }
            Case(case.getValue("id").jsonPrimitive.content, pages)
        }

        val stepCount: Int = cases.sumOf { c -> c.pages.sumOf { it.size } }

        private fun resolve(e: JsonElement): JsonElement = when (e) {
            is JsonObject -> if (e.size == 1 && "\$fixture" in e) fixtures.getValue(e.getValue("\$fixture").jsonPrimitive.content)
            else JsonObject(e.mapValues { resolve(it.value) })
            is JsonArray -> JsonArray(e.map(::resolve))
            else -> e
        }
    }
}
