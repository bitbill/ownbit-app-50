// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.jsengine.bridge

import io.ownbit.core.common.log.Log
import io.ownbit.core.jsengine.JsArgs
import io.ownbit.core.jsengine.JsBundle
import io.ownbit.core.jsengine.JsEngineManager
import io.ownbit.core.jsengine.JsResultFormatException
import io.ownbit.core.jsengine.JsResults
import io.ownbit.core.jsengine.PublicSignerException
import io.ownbit.core.jsengine.internal.WebViewJsEngine
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonObjectBuilder
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.util.concurrent.atomic.AtomicLong

/**
 * A camera scan session of the public protocol: `scanBegin` on a fresh isolated page, then one `scanAdd` per new frame
 * on that same page (the engine's `QRCollector` lives in the page). Obtain one from [PublicSignerJsBridge.openScan].
 *
 * The session ends (and its page is discarded) when a frame completes the request, when the engine refuses a frame
 * (the collector state after a refusal is not trusted; start a new session), on any engine failure, on [close], and
 * when another isolated operation runs. [add] on an ended session throws [PublicSignerException] `SCAN` without
 * reaching the engine.
 */
interface PublicScanHandle {
    /** Process-unique id of this session (increasing). */
    val sessionId: Long

    /**
     * Feeds one frame (`scanAdd`, at most 4300 characters per the engine). Returns `{complete, progress, request?}`:
     * `progress` is display-only, `request` is the assembled signing request once `complete`.
     * @throws PublicSignerException engine refusal (e.g. `QR_PROTOCOL` for mixed / wrong-direction / oversized frames)
     *   or `SCAN` when the session has ended.
     */
    suspend fun add(frame: String): JsonObject

    /** Ends the session and discards its page (asynchronously, in order with the bridge's other operations). */
    fun close()
}

/**
 * `review` and `resolveSigningPlan` of one request, run on the same fresh isolated page.
 *
 * @property review the engine's review of the request alone. The real bridge never returns `null`: when the engine
 *   refuses to review a request, [PublicSignerJsBridge.reviewAndResolve] throws [PublicSignerException] with the
 *   engine code (e.g. `NETWORK`) instead, so the precise reason is not lost. Nullable for fakes.
 * @property plan the resolver's answer (`status` `ready` with tasks and `planHash`, or `noMatch` / `missingSigner` /
 *   `ambiguous` / `setupRequired` / `invalid` with `message`). Pass it back to `signPlanTask` unchanged.
 */
data class ReviewAndPlan(val review: JsonObject?, val plan: JsonObject) {
    /** Never prints the engine JSON (addresses, amounts, request bytes). */
    override fun toString(): String =
        "ReviewAndPlan(review=${if (review == null) "null" else "<${review.size} keys>"}, plan=<${plan.size} keys>)"
}

/**
 * The only door to the public-protocol engine (`pubsigner/signer.js`, Ownbit edition of the BitSigner offline engine).
 * Every call is
 * `BitSignerEngine.dispatch(requestJson)` with `requestJson = {"operation": PublicSignerOp.wire, …params}` built here
 * with `buildJsonObject` and passed as one [JsArgs] string, so request / QR content is always data inside a JSON
 * document the engine parses strictly; it never becomes JS source (`JsCallSiteGuardTest` rules 4 and 8).
 *
 * Isolation, Android's equivalent of BitSigner's fresh `JSContext`:
 * - [PublicSignerPage.PAIRING] operations ([capabilities], [derivePublicAddresses], [createPublicPairing]) run on the
 *   `PUBLIC_SIGNER_PAIRING` page, which may stay loaded (idle sweep, [releasePairingPage]). It only ever receives the
 *   device's own verified public index; a runtime check refuses any other operation on it.
 * - [PublicSignerPage.SECRET] ([derivePublicIndex], [signPlanTask]) and [PublicSignerPage.UNTRUSTED] ([decodePayload],
 *   [reviewAndResolve], [encodeResponse]) run under one bridge [Mutex] as: end the active scan session → `restart()`
 *   (the call starts on a fresh page) → the call(s) of this one operation → discard the page in `finally` (success,
 *   engine refusal, timeout, cancellation). The discard is awaited before the mutex is released, so it can never hit
 *   the next operation's page, and `JsEngineManager.isPageLoaded(PUBLIC_SIGNER)` is `false` when the call returns.
 * - [PublicSignerPage.SCAN]: [openScan] / [PublicScanHandle].
 *
 * Seeds: only [derivePublicIndex] and [signPlanTask] put a `seed` (128-hex BIP39 seed, from
 * `WalletSecretAccess.withUnlocked`) into the request; the JSON string exists only for this call and is never logged,
 * stored or kept (same exposure class as every seed-taking bridge: [JsArgs] turns a `CharArray` into a string too).
 * The caller still owns and wipes its `CharArray`.
 *
 * Errors: an engine refusal → [PublicSignerException] (code + bounded engine text; only the code is logged); a request
 * above [MAX_REQUEST_BYTES] UTF-8 bytes → [PublicSignerException] `LIMIT` before any page is touched; a malformed engine
 * envelope → [JsResultFormatException]; page / WebView failures → the other [io.ownbit.core.jsengine.JsException]s.
 * The device name in every pairing export is always [DEVICE_NAME] (the engine's default would be "BitSigner").
 */
class PublicSignerJsBridge internal constructor(
    private val manager: JsEngineManager,
    /** Runs [PublicScanHandle.close]'s discard in order with the other operations. */
    private val scope: CoroutineScope,
) {

    constructor(manager: JsEngineManager) : this(manager, CoroutineScope(SupervisorJob() + Dispatchers.Default))

    /** Serialises every isolated sequence (restart → call(s) → discard) and the scan session on `PUBLIC_SIGNER`. */
    private val isolation = Mutex()

    /** The open scan session, if any (guarded by [isolation]). */
    private var activeScan: ScanSession? = null

    private val sessionIds = AtomicLong(0)

    // ---- PAIRING page: the device's own verified public index only -------------------------------------------------

    /** `capabilities`: `{version: "1.0.0", offline: true, chains, pairingOptions: ["deviceName"], evm.networks, …}`. */
    suspend fun capabilities(): JsonObject = pairing(PublicSignerOp.CAPABILITIES) {}

    /**
     * `derivePublicAddresses` over [publicIndex] (the device's own verified index): `{addresses: [{chain, profile, path,
     * index, branch, publicKey, address, masterFingerprint}], hasMore, nextIndex?}`. The engine checks [chain] /
     * [profile] and `count ≤ 100`.
     */
    suspend fun derivePublicAddresses(
        publicIndex: JsonObject,
        chain: String,
        profile: String?,
        start: Int,
        count: Int,
    ): JsonObject = pairing(PublicSignerOp.DERIVE_PUBLIC_ADDRESSES) {
        put("publicIndex", publicIndex)
        put("chain", chain)
        if (profile != null) put("profile", profile)
        put("start", start)
        put("count", count)
    }

    /**
     * `createPublicPairing` for [publicIndex] (the device's own verified index): `{type, frames[], text, address, path,
     * profile, outputMode, note?, payloadFormat, payload, payloadBytes}`. Always sends `deviceName: "Ownbit"`.
     * `index` is sent for TRON (the only chain where the engine accepts another index; the export policy keeps it at 0)
     * and whenever it is not 0 (the engine then refuses it for the other chains).
     */
    suspend fun createPublicPairing(
        publicIndex: JsonObject,
        chain: String,
        profile: String?,
        outputMode: String?,
        index: Int = 0,
    ): JsonObject = pairing(PublicSignerOp.CREATE_PUBLIC_PAIRING) {
        put("publicIndex", publicIndex)
        put("chain", chain)
        if (profile != null) put("profile", profile)
        if (outputMode != null) put("outputMode", outputMode)
        if (chain == CHAIN_TRON || index != 0) put("index", index)
        put("deviceName", DEVICE_NAME)
    }

    /**
     * Lets the warm pairing page go now (e.g. when the pairing screen stops); the next pairing call loads it again.
     * Asynchronous; harmless while a call is in flight (it finishes first).
     */
    fun releasePairingPage() {
        manager.discardPage(JsBundle.PUBLIC_SIGNER_PAIRING)
    }

    // ---- SECRET: fresh page, one call, discarded --------------------------------------------------------------------

    /**
     * `derivePublicIndex` from the wallet's BIP39 seed (128 hex): the public index v1 (≈ 30 KB, no secret). Ownbit
     * edition: [tronScheme] `"ownbit"` caches TRON #0 = `m/44'/195'/0'/0/0` and #1… = Ownbit's TRX
     * addresses (the ETH key `m/44'/60'/0'/0/N`, TRON-encoded), [tronAddressCount] of them (100…1000); `null` = the
     * engine's standard scheme (BitSigner, `m/44'/195'/0'/0/N`, 100).
     */
    suspend fun derivePublicIndex(seedHex: CharArray, tronScheme: String? = null, tronAddressCount: Int? = null): JsonObject = isolated {
        call(PublicSignerOp.DERIVE_PUBLIC_INDEX) {
            put("seed", String(seedHex))
            if (tronScheme != null) put("tronScheme", tronScheme)
            if (tronAddressCount != null) put("tronAddressCount", tronAddressCount)
        }
    }

    /**
     * `derivePublicIndex` with `publicIndex` in place of the seed (the engine's `refreshPublicIndex`, Ownbit edition):
     * [publicIndex] (the device's own verified index) with its TRON address cache re-derived from its own public account
     * nodes in [tronScheme], [tronAddressCount] addresses — converts a stored round-1 (standard) index to the Ownbit
     * scheme or extends its cache. No secret; every other member is kept.
     */
    suspend fun refreshPublicIndex(publicIndex: JsonObject, tronScheme: String, tronAddressCount: Int? = null): JsonObject = isolated {
        call(PublicSignerOp.DERIVE_PUBLIC_INDEX) {
            put("publicIndex", publicIndex)
            put("tronScheme", tronScheme)
            if (tronAddressCount != null) put("tronAddressCount", tronAddressCount)
        }
    }

    /**
     * `signPlanTask`: signs task [taskId] of [plan] (byte-for-byte the resolver's plan) for [request] with the wallet
     * seed. The engine re-derives the index from the seed, re-resolves, compares the task, the hashes and the target
     * keys, and refuses partial / opaque requests unless [riskAcknowledged]. [previousResult] chains the tasks of a
     * multi-wallet PSBT.
     */
    suspend fun signPlanTask(
        request: JsonObject,
        plan: JsonObject,
        taskId: String,
        seedHex: CharArray,
        riskAcknowledged: Boolean,
        previousResult: JsonObject?,
    ): JsonObject = isolated {
        call(PublicSignerOp.SIGN_PLAN_TASK) {
            put("request", request)
            put("plan", plan)
            put("taskId", taskId)
            put("seed", String(seedHex))
            put("riskAcknowledged", riskAcknowledged)
            if (previousResult != null) put("previousResult", previousResult)
        }
    }

    // ---- UNTRUSTED: fresh page per request, discarded ---------------------------------------------------------------

    /** `decodePayload` of pasted text (PSBT Base64 / hex, UR or BBQr frames one per line): like a completed scan. */
    suspend fun decodePayload(payload: String): JsonObject = isolated {
        call(PublicSignerOp.DECODE_PAYLOAD) { put("payload", payload) }
    }

    /**
     * `review` then `resolveSigningPlan` of [request] against [wallets] (`[{localWalletId, publicIndex?}]`, ≤ 100), both
     * on one fresh page. A review refusal throws [PublicSignerException] with the engine code before the resolver runs.
     */
    suspend fun reviewAndResolve(request: JsonObject, wallets: JsonArray): ReviewAndPlan = isolated {
        val review = call(PublicSignerOp.REVIEW) { put("request", request) }
        val plan = call(PublicSignerOp.RESOLVE_SIGNING_PLAN) {
            put("request", request)
            put("wallets", wallets)
        }
        ReviewAndPlan(review, plan)
    }

    /** `encodeResponse`: the final signing [result] in [request]'s own transport (`{type, frames[], payload…}`). */
    suspend fun encodeResponse(request: JsonObject, result: JsonObject, fragmentLength: Int? = null): JsonObject = isolated {
        call(PublicSignerOp.ENCODE_RESPONSE) {
            put("request", request)
            put("result", result)
            if (fragmentLength != null) put("fragmentLength", fragmentLength)
        }
    }

    // ---- SCAN: one session per page ---------------------------------------------------------------------------------

    /** Ends any open session, then `scanBegin` on a fresh page. */
    suspend fun openScan(): PublicScanHandle = isolation.withLock {
        endScanLocked()
        manager.restart(JsBundle.PUBLIC_SIGNER)
        val session = ScanSession(sessionIds.incrementAndGet())
        try {
            val begun = dispatch(JsBundle.PUBLIC_SIGNER, PublicSignerOp.SCAN_BEGIN) {}
            if (!isTrue(begun["started"])) throw JsResultFormatException(JsBundle.PUBLIC_SIGNER, DISPATCH, "{started: true}")
        } catch (e: Throwable) {
            discardIsolatedPage()
            throw e
        }
        activeScan = session
        session
    }

    private inner class ScanSession(override val sessionId: Long) : PublicScanHandle {
        @Volatile
        private var ended = false

        override suspend fun add(frame: String): JsonObject = isolation.withLock {
            if (ended || activeScan !== this || !manager.isPageLoaded(JsBundle.PUBLIC_SIGNER)) {
                // Closed, superseded by another operation, or the page went away (idle sweep, renderer death).
                endLocked()
                throw PublicSignerException(SCAN, NO_SCAN_SESSION)
            }
            val progress = try {
                dispatch(JsBundle.PUBLIC_SIGNER, PublicSignerOp.SCAN_ADD) { put("frame", frame) }
            } catch (e: Throwable) {
                endLocked()
                throw e
            }
            if (isTrue(progress["complete"])) endLocked()
            progress
        }

        override fun close() {
            if (ended) return
            ended = true
            scope.launch { isolation.withLock { if (activeScan === this@ScanSession) endLocked() } }
        }

        /** Marks the session ended and, if its page is still the session's, discards it. Holds [isolation]. */
        suspend fun endLocked() {
            ended = true
            if (activeScan === this) {
                activeScan = null
                discardIsolatedPage()
            }
        }

        override fun toString(): String = "PublicScanHandle(sessionId=$sessionId, ended=$ended)"
    }

    // ---- internals --------------------------------------------------------------------------------------------------

    /** Scope of one isolated sequence: only SECRET / UNTRUSTED operations, on the fresh `PUBLIC_SIGNER` page. */
    private inner class IsolatedPage {
        suspend fun call(op: PublicSignerOp, params: JsonObjectBuilder.() -> Unit): JsonObject {
            check(op.page == PublicSignerPage.SECRET || op.page == PublicSignerPage.UNTRUSTED) { "${op.wire} is not isolated" }
            return dispatch(JsBundle.PUBLIC_SIGNER, op, params)
        }
    }

    private suspend fun <T> isolated(block: suspend IsolatedPage.() -> T): T = isolation.withLock {
        endScanLocked() // Any other operation ends the scan session first.
        manager.restart(JsBundle.PUBLIC_SIGNER)
        try {
            IsolatedPage().block()
        } finally {
            discardIsolatedPage()
        }
    }

    private suspend fun endScanLocked() {
        activeScan?.endLocked()
    }

    private suspend fun pairing(op: PublicSignerOp, params: JsonObjectBuilder.() -> Unit): JsonObject {
        check(op.page == PublicSignerPage.PAIRING) { "${op.wire} may not run on the pairing page" }
        return dispatch(JsBundle.PUBLIC_SIGNER_PAIRING, op, params)
    }

    /**
     * Tears the isolated page down and waits until it is gone. Production engines are [WebViewJsEngine]s, whose
     * `discard` is the synchronous form of `JsEngineManager.discardPage` (it waits for the call in flight); other
     * engines (test doubles) get `discardPage` and a bounded wait for `isPageLoaded == false`.
     */
    private suspend fun discardIsolatedPage(): Unit = withContext(NonCancellable) {
        val engine = manager.engine(JsBundle.PUBLIC_SIGNER)
        if (engine is WebViewJsEngine) {
            engine.discard(DISCARD_REASON)
        } else {
            manager.discardPage(JsBundle.PUBLIC_SIGNER)
            val gone = withTimeoutOrNull(DISCARD_WAIT_MILLIS) {
                while (manager.isPageLoaded(JsBundle.PUBLIC_SIGNER)) delay(DISCARD_POLL_MILLIS)
            }
            if (gone == null) Log.w(TAG) { "isolated page still loaded after discard" }
        }
    }

    /**
     * One `BitSignerEngine.dispatch` call. [op] decides the page; the PAIRING page never receives another operation and
     * no request but the two SECRET ones carries a `seed` (runtime assertion).
     */
    private suspend fun dispatch(bundle: JsBundle, op: PublicSignerOp, params: JsonObjectBuilder.() -> Unit): JsonObject {
        check((bundle == JsBundle.PUBLIC_SIGNER_PAIRING) == (op.page == PublicSignerPage.PAIRING)) {
            "${op.wire} may not run on ${bundle.name}"
        }
        val request = buildJsonObject {
            put("operation", op.wire)
            params()
        }
        check(op.carriesSeed || SEED_KEY !in request) { "${op.wire} must not carry a seed" }
        val json = request.toString()
        if (utf8Length(json) > MAX_REQUEST_BYTES) {
            Log.d(TAG) { "${op.wire} refused before the engine: request too large" }
            throw PublicSignerException(LIMIT, REQUEST_TOO_LARGE, bundle)
        }
        val raw = JsResults.string(manager.engine(bundle).call("BitSignerEngine.dispatch", JsArgs.of(json)), bundle, DISPATCH)
        return try {
            parseResponse(raw, bundle)
        } catch (e: PublicSignerException) {
            Log.d(TAG) { "${op.wire} refused: ${e.code}" }
            throw e
        }
    }

    private fun parseResponse(raw: String, bundle: JsBundle): JsonObject {
        if (utf8Length(raw) > MAX_RESPONSE_BYTES) throw JsResultFormatException(bundle, DISPATCH, "a response of at most 2 MiB")
        val envelope = try {
            Json.parseToJsonElement(raw)
        } catch (e: SerializationException) {
            null
        } catch (e: IllegalArgumentException) {
            null
        } as? JsonObject ?: throw JsResultFormatException(bundle, DISPATCH, "a JSON object")
        val ok = (envelope["ok"] as? JsonPrimitive)?.takeIf { !it.isString }?.content
        when (ok) {
            "true" -> return envelope["result"] as? JsonObject
                ?: throw JsResultFormatException(bundle, DISPATCH, "an object result")
            "false" -> {
                val error = envelope["error"] as? JsonObject
                throw PublicSignerException(
                    code = stringOrNull(error?.get("code")) ?: DEFAULT_CODE,
                    engineMessage = stringOrNull(error?.get("message")) ?: DEFAULT_MESSAGE,
                    bundle = bundle,
                )
            }
            else -> throw JsResultFormatException(bundle, DISPATCH, "{ok: boolean}")
        }
    }

    companion object {
        /** The device name every key-bearing pairing export carries (`crypto-hdkey` name / note, `crypto-multi-accounts`). */
        const val DEVICE_NAME: String = "Ownbit"

        /**
         * Largest request sent to the engine, in UTF-8 bytes (the engine refuses above 1 MiB; this leaves headroom and
         * fails before a page is loaded).
         */
        const val MAX_REQUEST_BYTES: Long = 1_000_000

        /** Largest engine response accepted, in UTF-8 bytes (iOS `SigningEngine.swift`: 2 MiB). */
        const val MAX_RESPONSE_BYTES: Long = 2_097_152

        private const val TAG = "PublicSigner"
        private const val DISPATCH = "BitSignerEngine.dispatch"
        private const val CHAIN_TRON = "tron"
        private const val SEED_KEY = "seed"
        private const val DISCARD_REASON = "public signer: isolated operation finished"
        private const val DISCARD_WAIT_MILLIS = 10_000L
        private const val DISCARD_POLL_MILLIS = 10L

        // Bridge-side refusals reuse engine codes and texts (engine_vocabulary.json), so the UI maps them like the
        // engine's own: LIMIT ("Request exceeds one megabyte.", src/index.js) and SCAN (src/index.js scanAdd).
        private const val LIMIT = "LIMIT"
        private const val REQUEST_TOO_LARGE = "Request exceeds one megabyte."
        private const val SCAN = "SCAN"
        private const val NO_SCAN_SESSION = "No scan session is active."

        /** iOS `SigningEngine.swift` defaults for an error envelope without code / message. */
        private const val DEFAULT_CODE = "SIGNING_FAILED"
        private const val DEFAULT_MESSAGE = "This request could not be signed."

        private fun isTrue(element: JsonElement?): Boolean =
            element is JsonPrimitive && !element.isString && element.content == "true"

        private fun stringOrNull(element: JsonElement?): String? =
            (element as? JsonPrimitive)?.takeIf { it.isString }?.content

        /** UTF-8 length as the engine measures it (`Buffer.byteLength`; a lone surrogate counts 3, like U+FFFD). */
        internal fun utf8Length(text: String): Long {
            var bytes = 0L
            var i = 0
            while (i < text.length) {
                val c = text[i]
                bytes += when {
                    c.code < 0x80 -> 1
                    c.code < 0x800 -> 2
                    Character.isHighSurrogate(c) && i + 1 < text.length && Character.isLowSurrogate(text[i + 1]) -> {
                        i++
                        4
                    }
                    else -> 3
                }
                i++
            }
            return bytes
        }
    }
}
