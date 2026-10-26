//  BILPublicSignerEngine.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Public protocol (cold signer) — the only door to the bundled engine `signer.js` (Ownbit edition of the BitSigner
//  offline engine; C-GEN-1, C-KEY-1…5, C-QR-4; design §3.4, D-01…D-06). Port of BitSigner `Core/SigningEngine.swift`
//  with the Ownbit rules of Android `core/jsengine/.../bridge/PublicSignerJsBridge.kt` (Android wins where they differ):
//
//  - Only `BitSignerEngine.dispatch(requestJson)` is called, with the request JSON as the call **argument** (never
//    script text). The request is `{"operation": <BILPublicSignerOp>, <params in Android put order>}`, serialized with
//    `BILStrictJSON` (byte-identical to Android's kotlinx text and to the golden vectors).
//  - Isolation (D-02): PAIRING ops share one warm context (only the device's own unsealed, cross-checked public index;
//    never a seed or external input); SECRET / UNTRUSTED ops get a fresh context for one operation, dropped when the
//    method returns (success, refusal, failure); a scan session owns its own context until it completes, is refused,
//    fails, is closed, or another SECRET / UNTRUSTED op or a new scan starts. PAIRING ops never end a scan session.
//  - The seed appears only in `derivePublicIndex(seedHex:…)` and `signPlanTask(…)`; a top-level seed parameter on any
//    other operation is a programming error (`BILPublicSignerFailure.invalidRequest`, assertion in DEBUG).
//  - A request above 1,000,000 UTF-8 bytes is refused (`LIMIT`) before any context is created; a response above
//    2 MiB, a non-object envelope, a non-bool `ok`, `ok:true` without an object `result`, or a JS failure is
//    `BILPublicSignerFailure.malformedResponse`; `{"ok":false}` is a bounded `BILPublicSignerRefusal`.
//  - Entropy (D-05): `crypto.getRandomValues` and `Math.random` are installed from `SecRandomCopyBytes` before the
//    bundle runs, and the native entry is deleted first; `isInspectable = false` on iOS 16.4+; the bundled file's
//    SHA-256 is checked once per process (mismatch → engine unavailable).
//  - Logs carry only operation names and codes (C-KEY-5).
//
//  Threading (design §1.4): an actor whose isolated methods call JavaScriptCore synchronously (no `await` inside, so no
//  reentrancy: the whole engine is strictly serial). One cooperative thread is blocked per call.
//
//  Imports only Foundation, JavaScriptCore, Security, CryptoKit. The host app releases the warm PAIRING context when it
//  goes to the background or receives a memory warning (`releasePairingContext()`; the app's UIKit observers lived in
//  BILPublicSignerEngine+Lifecycle.swift, not part of this package). `signer.js` is looked up in `JSBridge.resourceBundle`
//  (see `bundled()`).
//

import Foundation
import JavaScriptCore
import Security
import CryptoKit

// MARK: - JavaScriptCore context

/// One `JSVirtualMachine` + `JSContext` with the native entropy bootstrap and the bundled engine evaluated. Used only by
/// `BILPublicSignerEngine` (and the DEBUG raw vector replay, which drives `dispatchText` directly).
final class BILPublicSignerJSContext {

    /// BitSigner's entropy installer (R1 §6.4 step 5), native entry renamed. It deletes the native entry before
    /// anything else, so the bundle never sees it; `crypto` and `Math.random` are frozen.
    static let bootstrapScript: String = """
    (function (random) {
        'use strict';
        delete globalThis.__bilPublicSignerEntropy;
        Object.defineProperty(globalThis, 'crypto', {value: Object.freeze({
            getRandomValues: function (array) {
                var integer = array instanceof Int8Array || array instanceof Uint8Array ||
                    array instanceof Uint8ClampedArray || array instanceof Int16Array ||
                    array instanceof Uint16Array || array instanceof Int32Array ||
                    array instanceof Uint32Array ||
                    (typeof BigInt64Array !== 'undefined' && array instanceof BigInt64Array) ||
                    (typeof BigUint64Array !== 'undefined' && array instanceof BigUint64Array);
                if (!integer || array.byteLength > 65536) throw new Error('Invalid entropy request');
                if (array.byteLength === 0) return array;
                var bytes = random(array.byteLength);
                if (!bytes || bytes.length !== array.byteLength) throw new Error('Secure randomness unavailable');
                new Uint8Array(array.buffer, array.byteOffset, array.byteLength).set(bytes);
                return array;
            }
        }), writable: false, configurable: false});
        Object.defineProperty(Math, 'random', {value: function () {
            var bytes = new Uint32Array(2);
            crypto.getRandomValues(bytes);
            return ((bytes[0] >>> 5) * 67108864 + (bytes[1] >>> 6)) / 9007199254740992;
        }, writable: false, configurable: false});
    })(__bilPublicSignerEntropy);
    """

    /// Global name of the native entropy block (removed by `bootstrapScript` before the bundle runs).
    private static let entropyEntry = "__bilPublicSignerEntropy"

    /// Set by the context's exception handler; never read for content (JS exceptions are never logged or shown).
    private final class FailureFlag {
        var failed = false
    }

    private let context: JSContext
    private let entry: JSValue
    private let flag: FailureFlag

    /// Creates a VM, installs the entropy bootstrap, evaluates `source` and resolves the engine entry.
    /// Throws `BILPublicSignerFailure.engineUnavailable` on any failure.
    init(source: String, sourceURL: URL) throws {
        guard let machine = JSVirtualMachine(), let context = JSContext(virtualMachine: machine) else {
            throw BILPublicSignerFailure.engineUnavailable
        }
        if #available(iOS 16.4, macOS 13.3, *) {
            context.isInspectable = false
        }
        let flag = FailureFlag()
        context.exceptionHandler = { _, _ in flag.failed = true }
        let entropy: @convention(block) (Int) -> [NSNumber]? = { count in
            return BILPublicSignerJSContext.secureRandom(count)
        }
        context.setObject(entropy, forKeyedSubscript: BILPublicSignerJSContext.entropyEntry as NSString)
        context.evaluateScript(Self.bootstrapScript)
        guard !flag.failed else {
            throw BILPublicSignerFailure.engineUnavailable
        }
        context.evaluateScript(source, withSourceURL: sourceURL)
        guard !flag.failed,
              let engine = context.objectForKeyedSubscript("BitSignerEngine"), engine.isObject,
              let entry = engine.forProperty("dispatch"), entry.isObject,
              JSObjectIsFunction(context.jsGlobalContextRef, entry.jsValueRef) else {
            throw BILPublicSignerFailure.engineUnavailable
        }
        self.context = context
        self.entry = entry
        self.flag = flag
        #if DEBUG
        BILPublicSignerJSContext.counters.didCreate()
        #endif
    }

    #if DEBUG
    deinit {
        BILPublicSignerJSContext.counters.didRelease()
    }
    #endif

    /// One `dispatch` call: the raw response text. Throws `BILPublicSignerFailure.malformedResponse` when the engine
    /// throws or returns anything but a string.
    func dispatchText(_ requestJSON: String) throws -> String {
        return try autoreleasepool { () throws -> String in
            flag.failed = false
            defer { context.exception = nil }
            guard let value = entry.call(withArguments: [requestJSON]), !flag.failed, value.isString,
                  let text = value.toString() else {
                throw BILPublicSignerFailure.malformedResponse
            }
            return text
        }
    }

    /// `SecRandomCopyBytes` for the bootstrap: 1…65,536 bytes, nil otherwise or on failure.
    private static func secureRandom(_ count: Int) -> [NSNumber]? {
        guard (1...65_536).contains(count) else { return nil }
        var bytes = [UInt8](repeating: 0, count: count)
        guard SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess else { return nil }
        return bytes.map { NSNumber(value: $0) }
    }

    #if DEBUG
    /// Contexts created / released in this process (isolation tests, design §4 WP7).
    static var created: Int { return counters.values.created }
    static var released: Int { return counters.values.released }

    private static let counters = Counters()

    private final class Counters {
        private let lock = NSLock()
        private var storage = (created: 0, released: 0)
        var values: (created: Int, released: Int) {
            lock.lock(); defer { lock.unlock() }
            return storage
        }
        func didCreate() {
            lock.lock(); storage.created += 1; lock.unlock()
        }
        func didRelease() {
            lock.lock(); storage.released += 1; lock.unlock()
        }
    }
    #endif
}

// MARK: - Engine

/// The engine host (design §3.4). Every method throws `BILPublicSignerRefusal` (engine or host refusal with an engine
/// code) or `BILPublicSignerFailure`.
public actor BILPublicSignerEngine: BILPublicSignerEngining {

    /// The process-wide engine (bundled `signer.js`, SHA-pinned). The host releases its warm PAIRING context on
    /// background / memory warning (`releasePairingContext()`).
    public static let shared: BILPublicSignerEngine = BILPublicSignerEngine()

    /// SHA-256 of the only `signer.js` this host code runs (`js/pubsigner-lib-bridge/signer.js`, 1,044,192 bytes).
    public static let engineSHA256 = "d89f76bdeec85d90fd88f07372100e9f4c07ab789530ac2bcffd52be536e7b05"
    static let deviceName = "Ownbit"
    public static let maxRequestBytes = 1_000_000, maxResponseBytes = 2_097_152

    /// The only seed parameter name (D-04 c): used by the two SECRET request builders and by the runtime check that no
    /// other request carries it at top level.
    private static let secretKey = "seed"

    private static let tronChain = "tron"

    /// nil = the bundled file (production).
    private let sourceURL: URL?
    private let pinned: Bool
    private var source: (text: String, url: URL)?
    private var pairingContext: BILPublicSignerJSContext?
    private var activeScan: (handle: BILPublicScanHandle, context: BILPublicSignerJSContext)?
    private var probed = false

    /// Bundled `signer.js`, SHA-pinned.
    public init() {
        self.sourceURL = nil
        self.pinned = true
    }

    /// UTF-8 size of `{"operation":"resolveSigningPlan","request":…,"wallets":…}` exactly as `reviewAndResolve` sends it
    /// (the coordinator fits the wallet list under `maxRequestBytes` with it; Android `PublicSignCoordinator.kt:593-601`).
    public static func resolveRequestByteCount(request: BILJSONObject, wallets: [BILJSONObject]) -> Int {
        guard let text = try? requestJSON(.resolveSigningPlan, resolveParams(request, wallets)) else { return Int.max }
        return text.utf8.count
    }

    // MARK: PAIRING (warm context)

    public func capabilities() throws -> BILJSONObject {
        return try pairing(.capabilities, [])
    }

    public func derivePublicAddresses(publicIndex: BILJSONObject, chain: String, profile: String?, start: Int, count: Int) throws -> BILJSONObject {
        var params: [(String, BILJSONValue)] = [("publicIndex", .object(publicIndex)), ("chain", .string(chain))]
        if let profile = profile {
            params.append(("profile", .string(profile)))
        }
        params.append(("start", .int(start)))
        params.append(("count", .int(count)))
        return try pairing(.derivePublicAddresses, params)
    }

    /// Always sends `deviceName: "Ownbit"`; `index` only for TRON or when it is not 0 (the engine then refuses it for the
    /// other chains); never a fragment length.
    public func createPublicPairing(publicIndex: BILJSONObject, chain: String, profile: String?, outputMode: String?, index: Int) throws -> BILJSONObject {
        var params: [(String, BILJSONValue)] = [("publicIndex", .object(publicIndex)), ("chain", .string(chain))]
        if let profile = profile {
            params.append(("profile", .string(profile)))
        }
        if let outputMode = outputMode {
            params.append(("outputMode", .string(outputMode)))
        }
        if BILJSONExact.equal(chain, Self.tronChain) || index != 0 {
            params.append(("index", .int(index)))
        }
        params.append(("deviceName", .string(Self.deviceName)))
        return try pairing(.createPublicPairing, params)
    }

    /// Drops the warm context; the next PAIRING operation loads a new one. Harmless while nothing is loaded.
    public func releasePairingContext() {
        pairingContext = nil
    }

    // MARK: SECRET (fresh context, one call)

    /// `derivePublicIndex` from the 128-hex BIP39 seed (never a phrase). Production callers always pass `"ownbit"` and
    /// the clamped count; both stay optional so every golden step is expressible.
    public func derivePublicIndex(seedHex: String, tronScheme: String?, tronAddressCount: Int?) throws -> BILJSONObject {
        var params: [(String, BILJSONValue)] = [(Self.secretKey, .string(seedHex))]
        if let tronScheme = tronScheme {
            params.append(("tronScheme", .string(tronScheme)))
        }
        if let tronAddressCount = tronAddressCount {
            params.append(("tronAddressCount", .int(tronAddressCount)))
        }
        return try isolated(.derivePublicIndex, params)
    }

    /// `derivePublicIndex` with the device's own verified index in place of the secret: only the TRON cache is
    /// re-derived (Android `refreshPublicIndex`).
    public func refreshPublicIndex(publicIndex: BILJSONObject, tronScheme: String, tronAddressCount: Int?) throws -> BILJSONObject {
        var params: [(String, BILJSONValue)] = [("publicIndex", .object(publicIndex)), ("tronScheme", .string(tronScheme))]
        if let tronAddressCount = tronAddressCount {
            params.append(("tronAddressCount", .int(tronAddressCount)))
        }
        return try isolated(.derivePublicIndex, params)
    }

    /// Signs task `taskId` of `plan` (byte-for-byte the resolver's plan) for `request`.
    public func signPlanTask(request: BILJSONObject, plan: BILJSONObject, taskId: String, seedHex: String,
                      riskAcknowledged: Bool, previousResult: BILJSONObject?) throws -> BILJSONObject {
        var params: [(String, BILJSONValue)] = [
            ("request", .object(request)), ("plan", .object(plan)), ("taskId", .string(taskId)),
            (Self.secretKey, .string(seedHex)), ("riskAcknowledged", .bool(riskAcknowledged)),
        ]
        if let previousResult = previousResult {
            params.append(("previousResult", .object(previousResult)))
        }
        return try isolated(.signPlanTask, params)
    }

    // MARK: UNTRUSTED (fresh context per request)

    public func decodePayload(_ payload: String) throws -> BILJSONObject {
        return try isolated(.decodePayload, [("payload", .string(payload))])
    }

    /// The review and the resolver of one request on one fresh context; a review refusal is thrown and the resolver
    /// never runs. Both requests are serialized (and size-checked) before the context is created.
    public func reviewAndResolve(request: BILJSONObject, wallets: [BILJSONObject]) throws -> BILPublicReviewAndPlan {
        endScan()
        let reviewText = try Self.checkedRequest(.review, [("request", .object(request))])
        let resolveText = try Self.checkedRequest(.resolveSigningPlan, Self.resolveParams(request, wallets))
        let context = try makeContext()
        let review = try exchange(.review, reviewText, on: context)
        let plan = try exchange(.resolveSigningPlan, resolveText, on: context)
        return BILPublicReviewAndPlan(review: review, plan: plan)
    }

    /// The final signing result in the request's own transport (never called for TronLink requests).
    public func encodeResponse(request: BILJSONObject, result: BILJSONObject) throws -> BILJSONObject {
        return try isolated(.encodeResponse, [("request", .object(request)), ("result", .object(result))])
    }

    // MARK: SCAN (one context per session)

    /// Ends any open session, then `scanBegin` on a fresh context, which must answer `{"started": true}`.
    public func openScan() throws -> BILPublicScanHandle {
        endScan()
        let text = try Self.checkedRequest(.scanBegin, [])
        let context = try makeContext()
        let handle = BILPublicScanHandle(sessionId: BILPublicSignerEngine.sessionIds.next())
        let begun = try exchange(.scanBegin, text, on: context)
        guard begun["started"] == .bool(true) else {
            BILPublicLog.code("engine", BILPublicSignerOp.scanBegin.rawValue + "_" + BILPublicSignerFailure.malformedResponse.code)
            throw BILPublicSignerFailure.malformedResponse
        }
        activeScan = (handle: handle, context: context)
        return handle
    }

    /// One frame of the open session `handle`: `{complete, progress, request?}`. A closed / superseded session throws
    /// `SCAN` without reaching the engine; any error and a completed request end the session.
    public func scanAdd(_ handle: BILPublicScanHandle, frame: String) throws -> BILJSONObject {
        guard let scan = activeScan, scan.handle == handle else {
            throw BILPublicSignerRefusal(code: BILPublicSignerRefusal.scanCode, engineMessage: BILPublicSignerRefusal.scanMessage)
        }
        let progress: BILJSONObject
        do {
            let text = try Self.checkedRequest(.scanAdd, [("frame", .string(frame))])
            progress = try exchange(.scanAdd, text, on: scan.context)
        } catch {
            endScan()
            throw error
        }
        if progress["complete"] == .bool(true) {
            endScan()
        }
        return progress
    }

    /// Ends `handle`'s session; a stale close of a superseded session is a no-op; idempotent.
    public func closeScan(_ handle: BILPublicScanHandle) {
        if let scan = activeScan, scan.handle == handle {
            endScan()
        }
    }

    // MARK: Identity probe (R1 §2.4)

    /// `capabilities` on the PAIRING context must report this engine (`BILPublicSignerAvailability.isExpectedEngine`).
    /// A success is remembered for the life of this engine (the process for `shared`); a failure is not.
    public func isAvailable() -> Bool {
        if probed {
            return true
        }
        guard let answer = try? capabilities(), BILPublicSignerAvailability.isExpectedEngine(answer) else {
            BILPublicLog.code("engine", "PROBE_FAILED")
            return false
        }
        probed = true
        return true
    }

    // MARK: - Private

    private func pairing(_ op: BILPublicSignerOp, _ params: [(String, BILJSONValue)]) throws -> BILJSONObject {
        guard op.page == .pairing else {
            throw BILPublicSignerFailure.invalidRequest
        }
        let text = try Self.checkedRequest(op, params)
        let context = try pairingContext ?? makeContext()
        pairingContext = context
        do {
            return try exchange(op, text, on: context)
        } catch let failure as BILPublicSignerFailure {
            pairingContext = nil      // an engine refusal keeps the warm context; a failure does not
            throw failure
        }
    }

    /// End the scan session → serialize (size check before any context) → fresh context → one call → context dropped.
    private func isolated(_ op: BILPublicSignerOp, _ params: [(String, BILJSONValue)]) throws -> BILJSONObject {
        guard op.page == .secret || op.page == .untrusted else {
            throw BILPublicSignerFailure.invalidRequest
        }
        endScan()
        let text = try Self.checkedRequest(op, params)
        let context = try makeContext()
        return try exchange(op, text, on: context)
    }

    private func endScan() {
        activeScan = nil
    }

    private func makeContext() throws -> BILPublicSignerJSContext {
        do {
            let loaded = try loadSource()
            return try BILPublicSignerJSContext(source: loaded.text, sourceURL: loaded.url)
        } catch {
            BILPublicLog.code("engine", BILPublicSignerFailure.engineUnavailable.code)
            throw BILPublicSignerFailure.engineUnavailable
        }
    }

    private func loadSource() throws -> (text: String, url: URL) {
        if let source = source {
            return source
        }
        let loaded: (text: String, url: URL)
        if let url = sourceURL {
            loaded = try BILPublicSignerEngine.readSource(at: url, pinned: pinned)
        } else {
            loaded = try BILPublicSignerEngine.bundled()
        }
        source = loaded
        return loaded
    }

    /// One dispatch on `context` and the envelope rules (Android `parseResponse`).
    private func exchange(_ op: BILPublicSignerOp, _ text: String, on context: BILPublicSignerJSContext) throws -> BILJSONObject {
        #if DEBUG
        if recordsRequests {
            recordedRequests.append((op: op, sha256: BILPublicSignerEngine.sha256Hex(Data(text.utf8)), bytes: text.utf8.count))
        }
        #endif
        let raw: String
        do {
            raw = try context.dispatchText(text)
        } catch {
            BILPublicLog.code("engine", op.rawValue + "_" + BILPublicSignerFailure.malformedResponse.code)
            throw BILPublicSignerFailure.malformedResponse
        }
        do {
            return try BILPublicSignerEngine.parseEnvelope(raw)
        } catch let refusal as BILPublicSignerRefusal {
            BILPublicLog.code("engine", op.rawValue + "_" + refusal.code)
            throw refusal
        } catch {
            BILPublicLog.code("engine", op.rawValue + "_" + BILPublicSignerFailure.malformedResponse.code)
            throw BILPublicSignerFailure.malformedResponse
        }
    }

    /// `requestJSON` plus the 1,000,000-byte guard (before any context is touched).
    private static func checkedRequest(_ op: BILPublicSignerOp, _ params: [(String, BILJSONValue)]) throws -> String {
        let text = try requestJSON(op, params)
        guard text.utf8.count <= maxRequestBytes else {
            BILPublicLog.code("engine", op.rawValue + "_" + BILPublicSignerRefusal.limitCode)
            throw BILPublicSignerRefusal(code: BILPublicSignerRefusal.limitCode, engineMessage: BILPublicSignerRefusal.limitMessage)
        }
        return text
    }

    /// The only request builder: `{"operation": op, <params in order>}` as compact strict JSON. A top-level secret
    /// parameter on a non-SECRET operation is refused (C-KEY-2 runtime assertion).
    private static func requestJSON(_ op: BILPublicSignerOp, _ params: [(String, BILJSONValue)]) throws -> String {
        guard op.carriesSeed || !params.contains(where: { BILJSONExact.equal($0.0, secretKey) }) else {
            #if DEBUG
            if debugAssertsOnInvalidRequest {
                assertionFailure("BILPublicSignerEngine: secret parameter on a non-secret operation")
            }
            #endif
            throw BILPublicSignerFailure.invalidRequest
        }
        var request = BILJSONObject()
        request.set("operation", .string(op.rawValue))
        for (key, value) in params {
            request.set(key, value)
        }
        return BILStrictJSON.serialize(request)
    }

    private static func resolveParams(_ request: BILJSONObject, _ wallets: [BILJSONObject]) -> [(String, BILJSONValue)] {
        return [("request", .object(request)), ("wallets", .array(wallets.map { .object($0) }))]
    }

    /// Android `parseResponse`: ≤ 2 MiB, a JSON object, `ok` a JSON bool; `ok:true` needs an object `result`;
    /// `ok:false` → refusal with `error.code` / `error.message` (JSON strings only) or the defaults.
    private static func parseEnvelope(_ raw: String) throws -> BILJSONObject {
        guard raw.utf8.count <= maxResponseBytes, let envelope = BILStrictJSON.parseObject(raw, options: .engine) else {
            throw BILPublicSignerFailure.malformedResponse
        }
        switch envelope["ok"] {
        case .some(.bool(true)):
            guard let result = envelope.obj("result") else {
                throw BILPublicSignerFailure.malformedResponse
            }
            return result
        case .some(.bool(false)):
            let error = envelope.obj("error")
            throw BILPublicSignerRefusal(code: error?.str("code") ?? BILPublicSignerRefusal.defaultCode,
                                         engineMessage: error?.str("message") ?? BILPublicSignerRefusal.defaultMessage)
        default:
            throw BILPublicSignerFailure.malformedResponse
        }
    }

    // MARK: Source (SHA-pinned, read once)

    private static let bundleCache = SourceCache()

    /// The bundled `signer.js` (SHA-checked once per process; failures are not cached). Looked up in
    /// `JSBridge.resourceBundle` (the bundle where the host copied the package's `js/` files): flat (`signer.js`, as the
    /// app bundles it), then under `pubsigner-lib-bridge/` or `js/pubsigner-lib-bridge/` (folder references).
    private static func bundled() throws -> (text: String, url: URL) {
        if let cached = bundleCache.value {
            return cached
        }
        let bundle = JSBridge.resourceBundle
        guard let url = bundle.url(forResource: "signer", withExtension: "js")
                ?? bundle.url(forResource: "signer", withExtension: "js", subdirectory: "pubsigner-lib-bridge")
                ?? bundle.url(forResource: "signer", withExtension: "js", subdirectory: "js/pubsigner-lib-bridge") else {
            throw BILPublicSignerFailure.engineUnavailable
        }
        let loaded = try readSource(at: url, pinned: true)
        bundleCache.value = loaded
        return loaded
    }

    private static func readSource(at url: URL, pinned: Bool) throws -> (text: String, url: URL) {
        guard url.isFileURL, let data = try? Data(contentsOf: url) else {
            throw BILPublicSignerFailure.engineUnavailable
        }
        if pinned && sha256Hex(data) != engineSHA256 {
            throw BILPublicSignerFailure.engineUnavailable
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw BILPublicSignerFailure.engineUnavailable
        }
        return (text: text, url: url)
    }

    private static func sha256Hex(_ data: Data) -> String {
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private final class SourceCache {
        private let lock = NSLock()
        private var stored: (text: String, url: URL)?
        var value: (text: String, url: URL)? {
            get { lock.lock(); defer { lock.unlock() }; return stored }
            set { lock.lock(); stored = newValue; lock.unlock() }
        }
    }

    /// Scan session ids: strictly increasing per process.
    private static let sessionIds = SessionIds()

    private final class SessionIds {
        private let lock = NSLock()
        private var last: Int64 = 0
        func next() -> Int64 {
            lock.lock(); defer { lock.unlock() }
            last += 1
            return last
        }
    }

    // MARK: - DEBUG (harness, self-tests)

    #if DEBUG
    /// Harness / fake engines: `sourceURL` instead of the bundle; `pinned: false` skips the SHA check (fake sources).
    init(sourceURL: URL, pinned: Bool = true) {
        self.sourceURL = sourceURL
        self.pinned = pinned
    }

    /// The bundled engine source for DEBUG callers (the golden raw replay) — keeps the resource name
    /// engine-only (guard rule 1, D-04 e). SHA-checked like `init()`.
    static func bundledSource() throws -> (text: String, url: URL) {
        return try bundled()
    }

    /// `false` lets the harness exercise the invalid-request path without the assertion trap.
    static var debugAssertsOnInvalidRequest = true

    /// The request text this engine would send for `op` / `params` (same builder and size guard; harness only).
    static func debugRequestText(_ op: BILPublicSignerOp, _ params: [(String, BILJSONValue)]) throws -> String {
        return try checkedRequest(op, params)
    }

    private var recordsRequests = false
    private var recordedRequests: [(op: BILPublicSignerOp, sha256: String, bytes: Int)] = []

    /// Records the operation, SHA-256 and UTF-8 size of every request sent from now on (never the text itself).
    func debugRecordRequests(_ on: Bool) {
        recordsRequests = on
        recordedRequests.removeAll()
    }

    /// The recorded requests so far (cleared).
    func debugTakeRequests() -> [(op: BILPublicSignerOp, sha256: String, bytes: Int)] {
        let taken = recordedRequests
        recordedRequests.removeAll()
        return taken
    }

    var debugHasPairingContext: Bool {
        return pairingContext != nil
    }

    var debugHasScanSession: Bool {
        return activeScan != nil
    }
    #endif
}
