//  PPEngineTests.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Port of the app harness suite `scripts/public-protocol/tests/engine` (main.swift) to XCTest.
//
//  tests/engine/main.swift — WP7 engine host suite (design §4 WP7, R1 §7–§11; S§13.2 #1–#3).
//  Compiles the real app files (Core/*, pubsigner-lib-bridge/BILPublicSigner{Op,Engine,Availability}.swift,
//  Debug/BILPublicSignerVectorReplay.swift) with tests/support/{TestKit,AppStubs}.swift.
//    engine --engine <signer.js> [--mode all|sim|fast]
//      all  pin, op enum, raw replay on the main thread and on the cooperative pool, production replay, fake-engine
//           behaviour (isolation, warm context, seed placement, request texts, scan rules, envelopes, bounds, size
//           guard, load failures, probe), real-engine hardening, seed parity, BIP340 freshness
//      sim  pin + raw replay (main + pool) only — the binary tests/engine/run.sh --sim cross-compiles for the simulator
//      fast everything except the raw and production replays (development / mutation runs)
//  Fixtures: $PUB_FIXTURES (simctl spawn: SIMCTL_CHILD_PUB_FIXTURES).
//

import Foundation
import XCTest
import CryptoKit
@testable import OwnbitCore

/// The suite namespace (harness helpers are its static members).
enum PPEngineSuite: PPSuite {}

final class PPEngineTests: XCTestCase {
    func testEngine() throws {
        try ppRunSuite("engine") { try PPEngineSuite.run() }
    }
}

extension PPEngineSuite {

    // MARK: - Arguments and fixtures

    static func argument(_ flag: String) -> String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    /// The harness took `--engine <signer.js>` and `--mode all|sim|fast`; here: the package's js/pubsigner-lib-bridge/signer.js,
    /// mode "all". (The app's md5 pins of signer.js and the fixtures — MD5.txt — are not ported; SHA-256 pins stay.)
    static let mode = "all"
    static func sha256Hex(_ data: Data) -> String { return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    static func ser(_ o: BILJSONObject) -> String { return BILStrictJSON.serialize(o) }
    static func obj(_ pairs: (String, BILJSONValue)...) -> BILJSONObject { return BILJSONObject(pairs) }
    static func parse(_ text: String) -> BILJSONObject { return BILStrictJSON.parseObject(text, options: .engine) ?? BILJSONObject() }
    static func refusalCode(_ error: Error) -> String {
        if let r = error as? BILPublicSignerRefusal { return "refusal " + r.code }
        if let f = error as? BILPublicSignerFailure { return "failure " + f.code }
        return "other " + String(describing: type(of: error))
    }
    static func refusal(_ what: String, file: StaticString = #file, line: UInt = #line, _ body: () async throws -> Void) async -> BILPublicSignerRefusal? {
        do {
            try await body()
            t(false, what + ": no refusal", file: file, line: line)
            return nil
        } catch let r as BILPublicSignerRefusal {
            return r
        } catch {
            t(false, what + ": threw " + refusalCode(error), file: file, line: line)
            return nil
        }
    }
    static func expectFailure(_ expected: BILPublicSignerFailure, _ what: String, file: StaticString = #file, line: UInt = #line,
                       _ body: () async throws -> Void) async {
        do {
            try await body()
            t(false, what + ": did not throw", file: file, line: line)
        } catch let f as BILPublicSignerFailure {
            eq(f, expected, what, file: file, line: line)
        } catch {
            t(false, what + ": threw " + refusalCode(error), file: file, line: line)
        }
    }
    static func contextsAlive() -> Int { return BILPublicSignerJSContext.created - BILPublicSignerJSContext.released }
    static let vectorsText = fixtureText("vectors.json")
    static let vectors: BILPublicSignerVectors = {
        do {
            return try BILPublicSignerVectors(vectorsJSON: vectorsText)
        } catch {
            fatalError("vectors.json: \(error)")
        }
    }()
    static func vcase(_ id: String) -> BILPublicSignerVectors.Case {
        guard let c = vectors.caseNamed(id) else {
            print("FAIL missing vector case \(id)")
            fatalError("harness fixture problem")
        }
        return c
    }
    static func steps(_ id: String, _ op: BILPublicSignerOp) -> [BILPublicSignerVectors.Step] { return vcase(id).steps.filter { $0.op == op } }
    @discardableResult
    static func check(_ ok: Bool, _ what: String, file: StaticString = #file, line: UInt = #line) -> Bool {
        return t(ok, what, file: file, line: line)
    }
    @discardableResult
    static func same<T: Equatable>(_ actual: T, _ expected: T, _ what: String, file: StaticString = #file, line: UInt = #line) -> Bool {
        return eq(actual, expected, what, file: file, line: line)
    }
    static func checkRaw(_ r: BILPublicSignerReplayReport, _ label: String) {
        same(r.steps, 923, "\(label): steps")
        same(r.shaEqual, 919, "\(label): SHA-equal")
        same(r.volatileVerified, 4, "\(label): volatile verified")
        same(r.contexts, 395, "\(label): contexts")
        same(r.failures.count, 0, "\(label): failures")
        for f in r.failures.prefix(20) { print("  \(label) failure: \(f)") }
        print("engine: \(label) steps=\(r.steps) sha=\(r.shaEqual) volatile=\(r.volatileVerified) contexts=\(r.contexts) fails=\(r.failures.count) s=\(String(format: "%.1f", r.seconds))")
    }
    static let fakeDir = pubTempDir("pubengine")
    static var fakeCount = 0
    static func fakeSource(_ js: String) -> URL {
        fakeCount += 1
        let url = fakeDir.appendingPathComponent("fake\(fakeCount).js")
        try! js.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
    static func fake(_ js: String) -> BILPublicSignerEngine { return BILPublicSignerEngine(sourceURL: fakeSource(js), pinned: false) }
    static func fakeDispatch(_ body: String) -> BILPublicSignerEngine {
        return fake("var BitSignerEngine = { dispatch: function (json) { " + body + " } };")
    }

    /// The harness main.swift (nonisolated top-level code, as in the harness).
    static func run() throws {
        guard let engineURL = signerJSURL(), let engineData = try? Data(contentsOf: engineURL),
              let engineText = String(data: engineData, encoding: .utf8) else {
            t(false, "js/pubsigner-lib-bridge/signer.js readable")
            return
        }

        let PIN_SHA = "d89f76bdeec85d90fd88f07372100e9f4c07ab789530ac2bcffd52be536e7b05"
        let ABANDON_SEED = "5eb00bbddcf069084889a8ab9155568165f5c453ccb85e70811aaed6f6da5fc19a5ac40b389cd370d086206dec8aa6c43daea6690f20ad3d8d48b2d2ce9e38e4"
        let ALLOWED = ["capabilities", "derivePublicAddresses", "createPublicPairing", "derivePublicIndex", "signPlanTask", "scanBegin",
                       "scanAdd", "decodePayload", "review", "resolveSigningPlan", "encodeResponse"]
        let EXCLUDED = ["decodeQR", "mnemonic", "validateMnemonic", "wordlist", "deriveAccounts", "deriveBitcoinCosigner",
                        "validateBitcoinPolicy", "sign", "encodeQR", "createPairing", "createWalletPairing", "deriveWalletPublic", "execute"]
        /// Characters that must survive Swift → JSC → engine → Swift unchanged (Android ODD minus the lone surrogate).
        let ODD = "q\"uote\\ back\r\n tab\t nul\u{0} 😀 </script><script>x</script> \u{2028}\u{2029} \u{FEFF} \u{202E} end"

        /// Runs `body` and returns the refusal it threw (nil otherwise; a non-refusal error is recorded as a failed check).

        /// Passes when `body` throws exactly `expected`.

        let indexAbandon = vectors.fixture("publicIndex.abandon") ?? BILJSONObject()
        let indexLegal = vectors.fixture("publicIndex.legal") ?? BILJSONObject()
        let indexOwnbit = vectors.fixture("publicIndex.abandonOwnbit") ?? BILJSONObject()
        let walletsAbandon = [obj(("localWalletId", .string("wallet-abandon")), ("publicIndex", .object(indexAbandon)))]

        /// Plain-argument forms of TestKit's `t` / `eq` (their autoclosures cannot contain `await`).

        // MARK: - 1 pin (S§13.2 #1, R1 §8 "pin")

        section("pin")
        same(engineData.count, 1_044_192, "signer.js size")
        same(sha256Hex(engineData), PIN_SHA, "signer.js SHA-256")
        same(BILPublicSignerEngine.engineSHA256, PIN_SHA, "engineSHA256 constant")
        check(engineText.hasPrefix("// Ownbit edition of the BitSigner 1.0.0 offline engine (BitSigner 95baad4 + tools/pubsigner/upstream/ownbit-edition.patch)."),
          "signer.js banner")
        check(engineText.contains("\n\nvar BitSignerEngine=(()=>{"), "IIFE global after the banner")
        do {
            let head = String(vectorsText.utf16.prefix(2000)) ?? ""
            let re = try! NSRegularExpression(pattern: "\"sha256\":\\s*\"" + PIN_SHA + "\"")
            check(re.firstMatch(in: head, range: NSRange(location: 0, length: (head as NSString).length)) != nil, "vectors.json head names the engine SHA")
            same(vectors.engineInfo.long("bytes"), 1_044_192, "vectors engine.bytes")
            same(vectors.engineInfo.str("sha256"), PIN_SHA, "vectors engine.sha256")
            same(vectors.summary.int("cases"), 169, "summary cases")
            same(vectors.summary.int("steps"), 923, "summary steps")
            same(vectors.summary.int("volatileSteps"), 4, "summary volatileSteps")
            same(Set(vectors.summary.strings("operations") ?? []), Set(ALLOWED + ["noSuchOperation"]), "summary operations = allowlist + unknown")
            same(vectors.cases.count, 169, "parsed cases")
            same(vectors.stepCount, 923, "parsed steps")
            same(vectors.pageCount, 395, "distinct (case, page) contexts")
            same(vectors.substitutions, 154, "$fixture substitutions")
            same(vectors.fixtureNames, ["publicIndex.abandon", "publicIndex.abandonOwnbit", "publicIndex.legal"], "fixture names")
            same(Set(vectors.cases.flatMap { $0.steps.map { $0.opName } }), Set(ALLOWED + ["noSuchOperation"]), "vector ops = allowlist + unknown")
            for op in ALLOWED + EXCLUDED.filter({ $0 != "execute" }) {
                check(engineText.contains("case\"" + op + "\":"), "engine names operation \(op)")
            }
        }

        // MARK: - 2 op enum (R1 §11.1)

        section("op")
        same(BILPublicSignerOp.allCases.map { $0.rawValue }, ALLOWED, "11 operations in Android order")
        let pageNames: [BILPublicSignerPage: String] = [.pairing: "pairing", .secret: "secret", .untrusted: "untrusted", .scan: "scan"]
        same(BILPublicSignerOp.allCases.map { pageNames[$0.page]! },
           ["pairing", "pairing", "pairing", "secret", "secret", "scan", "scan", "untrusted", "untrusted", "untrusted", "untrusted"], "pages")
        same(BILPublicSignerOp.allCases.filter { $0.carriesSeed }, [.derivePublicIndex, .signPlanTask], "carriesSeed only for the SECRET ops")
        same(Set(BILPublicSignerOp.allCases.map { $0.rawValue }).count, 11, "raw values unique")
        for name in EXCLUDED { check(BILPublicSignerOp(rawValue: name) == nil, "\(name) is not an operation") }

        // MARK: - 3 raw replay: main thread and cooperative pool (R1 §7.3, design WP7 "JSC stack")

        if mode != "fast" {
        section("raw-main")
        let aliveBeforeRaw = contextsAlive()
        let rawMain = BILPublicSignerVectorReplay.runRaw(vectors: vectors, source: engineText, sourceURL: engineURL)
        checkRaw(rawMain, "raw main")
        same(contextsAlive(), aliveBeforeRaw, "raw main: no context left")

        section("raw-pool")
        var rawPool = BILPublicSignerReplayReport()
        runAsync(timeout: 900) {
            rawPool = await Task.detached(priority: .userInitiated) {
                BILPublicSignerVectorReplay.runRaw(vectors: vectors, source: engineText, sourceURL: engineURL)
            }.value
        }
        checkRaw(rawPool, "raw pool")
        print("engine: stack main=\(rawMain.failures.isEmpty ? "ok" : "\(rawMain.failures.count) fails") pool=\(rawPool.failures.isEmpty ? "ok" : "\(rawPool.failures.count) fails")")

        if mode == "sim" {
            pubSummary("engine")
        }
        }

        // MARK: - 4 production replay (R1 §7.4)

        BILPublicSignerEngine.debugAssertsOnInvalidRequest = false
        let realEngine = BILPublicSignerEngine(sourceURL: engineURL, pinned: true)
        if mode != "fast" {
        section("production")
        let aliveBeforeProd = contextsAlive()
        runAsync(timeout: 900) {
            let report = await BILPublicSignerVectorReplay.runProduction(vectors: vectors, engine: realEngine)
            same(report.covered, 908, "production: covered")
            same(report.skipped.count, 15, "production: skipped")
            same(report.skipped.sorted(), BILPublicSignerVectorReplay.expectedProductionSkips.sorted(), "production: exactly the expected skips")
            same(report.covered + report.skipped.count, 923, "production: every step covered or skipped")
            same(report.volatileVerified, 4, "production: Taproot signatures verified")
            same(report.failures.count, 0, "production: failures")
            for f in report.failures.prefix(20) { print("  production failure: \(f)") }
            check(report.requestTextChecked >= 900, "production: request texts compared (\(report.requestTextChecked))")
            same(report.requestTextDiffers, [], "production: every request text byte-equal to the vector request")
            print("engine: production covered=\(report.covered) skipped=\(report.skipped.count) volatile=\(report.volatileVerified) requests=\(report.requestTextChecked) differ=\(report.requestTextDiffers.count) fails=\(report.failures.count) s=\(String(format: "%.1f", report.seconds))")
            check(await realEngine.debugHasPairingContext, "production: the warm pairing context stays loaded")
            check(!(await realEngine.debugHasScanSession), "production: no scan session left open")
            same(contextsAlive(), aliveBeforeProd + 1, "production: only the warm context is alive")
            await realEngine.releasePairingContext()
            same(contextsAlive(), aliveBeforeProd, "production: no context left after releasing the warm one")
        }
        }

        if mode != "all" && mode != "fast" {
            pubSummary("engine")
        }

        // MARK: - 5 fake engines (R1 §11.2)

        /// An engine whose dispatch body is `body` (`json` = the request text).

        let echoJS = """
        var BitSignerEngine = (function () {
            function hex(a) { return Array.prototype.map.call(a, function (b) { return ('0' + b.toString(16)).slice(-2); }).join(''); }
            function rnd(k) { var a = new Uint8Array(k); crypto.getRandomValues(a); return hex(a); }
            var ctx = null;
            return { dispatch: function (json) {
                var r = JSON.parse(json);
                globalThis.n = (globalThis.n || 0) + 1;
                if (ctx === null) ctx = rnd(8);
                if (r.frame === 'BAD') return JSON.stringify({ ok: false, error: { code: 'QR_PROTOCOL', message: 'Mixed UR fountain sessions' } });
                var result = {
                    op: r.operation, n: globalThis.n, ctx: ctx, hasSeed: Object.prototype.hasOwnProperty.call(r, 'seed'), random: rnd(32),
                    net: [typeof fetch, typeof XMLHttpRequest, typeof WebSocket, typeof setTimeout, typeof importScripts, typeof navigator],
                    entry: typeof __bilPublicSignerEntropy,
                    cryptoWritable: Object.getOwnPropertyDescriptor(globalThis, 'crypto').writable,
                    mathRandomWritable: Object.getOwnPropertyDescriptor(Math, 'random').writable,
                    mathRandom: typeof Math.random(),
                    echo: r.payload !== undefined ? r.payload : (r.frame !== undefined ? r.frame : (r.request !== undefined ? r.request : null)),
                    wallets: r.wallets !== undefined ? r.wallets : null,
                    text: json
                };
                if (r.operation === 'scanBegin') result.started = true;
                if (r.operation === 'scanAdd') { result.complete = r.frame === 'END'; result.progress = 0.5; }
                return JSON.stringify({ ok: true, result: result });
            } };
        })();
        """

        runAsync(timeout: 300) {
            let k = obj(("walletKeyId", .string("k")))
            let e = fake(echoJS)

            section("fake: SECRET / UNTRUSTED isolation")
            let base = contextsAlive()
            var contexts = Set<String>()
            for (label, call) in [
                ("derivePublicIndex", { try await e.derivePublicIndex(seedHex: ABANDON_SEED, tronScheme: "ownbit", tronAddressCount: 100) }),
                ("refreshPublicIndex", { try await e.refreshPublicIndex(publicIndex: k, tronScheme: "ownbit", tronAddressCount: nil) }),
                ("signPlanTask", { try await e.signPlanTask(request: k, plan: k, taskId: "t", seedHex: ABANDON_SEED, riskAcknowledged: false, previousResult: nil) }),
                ("decodePayload", { try await e.decodePayload("p") }),
                ("encodeResponse", { try await e.encodeResponse(request: k, result: k) }),
            ] as [(String, () async throws -> BILJSONObject)] {
                let r = try await call()
                same(r.long("n"), 1, "\(label): fresh context (n == 1)")
                contexts.insert(r.str("ctx") ?? "")
                same(contextsAlive(), base, "\(label): context dropped when the call returns")
                same(r.bool("hasSeed"), label == "derivePublicIndex" || label == "signPlanTask", "\(label): seed only in the SECRET ops")
            }
            same(contexts.count, 5, "a different context for every isolated call")
            let both = try await e.reviewAndResolve(request: k, wallets: [obj(("localWalletId", .string("w")))])
            same(both.review.long("n"), 1, "review: first call of a fresh context")
            same(both.plan.long("n"), 2, "resolve: second call of the same context")
            same(both.review.str("ctx"), both.plan.str("ctx"), "review + resolve share one context")
            same(contextsAlive(), base, "reviewAndResolve: context dropped")
            check(!(contexts.contains(both.review.str("ctx") ?? "")), "reviewAndResolve: a new context")

            section("fake: PAIRING warm context")
            let p1 = try await e.capabilities()
            let p2 = try await e.derivePublicAddresses(publicIndex: k, chain: "evm", profile: nil, start: 0, count: 1)
            let p3 = try await e.createPublicPairing(publicIndex: k, chain: "evm", profile: nil, outputMode: "wallet", index: 0)
            same([p1.long("n"), p2.long("n"), p3.long("n")], [1, 2, 3], "PAIRING calls share the warm context")
            same(Set([p1.str("ctx"), p2.str("ctx"), p3.str("ctx")]).count, 1, "one warm context")
            same([p1.bool("hasSeed"), p2.bool("hasSeed"), p3.bool("hasSeed")], [false, false, false], "PAIRING never carries a seed")
            same(contextsAlive(), base + 1, "the warm context stays alive")
            _ = try await e.decodePayload("between")
            same((try await e.capabilities()).long("n"), 4, "an isolated op does not touch the warm context")
            let createdBefore = BILPublicSignerJSContext.created
            await e.releasePairingContext()
            same(contextsAlive(), base, "release drops the warm context")
            await e.releasePairingContext()
            same(BILPublicSignerJSContext.created, createdBefore, "a second release creates nothing")
            let p4 = try await e.capabilities()
            same(p4.long("n"), 1, "after release: a new warm context (n == 1)")
            check(p4.str("ctx") != p1.str("ctx"), "after release: different context")
            same(BILPublicSignerJSContext.created, createdBefore + 1, "after release: exactly one context created by the next PAIRING op")
            await e.releasePairingContext()

            section("fake: request texts (key order, JSON types)")
            func text(_ r: BILJSONObject) -> String { return r.str("text") ?? "" }
            same(text(try await e.derivePublicAddresses(publicIndex: k, chain: "evm", profile: nil, start: 7, count: 1)),
               "{\"operation\":\"derivePublicAddresses\",\"publicIndex\":{\"walletKeyId\":\"k\"},\"chain\":\"evm\",\"start\":7,\"count\":1}", "derivePublicAddresses text")
            same(text(try await e.derivePublicAddresses(publicIndex: k, chain: "bitcoin", profile: "native", start: 0, count: 3)),
               "{\"operation\":\"derivePublicAddresses\",\"publicIndex\":{\"walletKeyId\":\"k\"},\"chain\":\"bitcoin\",\"profile\":\"native\",\"start\":0,\"count\":3}", "derivePublicAddresses with profile")
            same(text(try await e.createPublicPairing(publicIndex: k, chain: "tron", profile: "standard", outputMode: "address", index: 0)),
               "{\"operation\":\"createPublicPairing\",\"publicIndex\":{\"walletKeyId\":\"k\"},\"chain\":\"tron\",\"profile\":\"standard\",\"outputMode\":\"address\",\"index\":0,\"deviceName\":\"Ownbit\"}", "TRON pairing sends index 0")
            same(text(try await e.createPublicPairing(publicIndex: k, chain: "evm", profile: nil, outputMode: "wallet", index: 0)),
               "{\"operation\":\"createPublicPairing\",\"publicIndex\":{\"walletKeyId\":\"k\"},\"chain\":\"evm\",\"outputMode\":\"wallet\",\"deviceName\":\"Ownbit\"}", "EVM pairing: no index when 0")
            same(text(try await e.createPublicPairing(publicIndex: k, chain: "evm", profile: nil, outputMode: "address", index: 1)),
               "{\"operation\":\"createPublicPairing\",\"publicIndex\":{\"walletKeyId\":\"k\"},\"chain\":\"evm\",\"outputMode\":\"address\",\"index\":1,\"deviceName\":\"Ownbit\"}", "EVM pairing: index when not 0")
            same(text(try await e.createPublicPairing(publicIndex: k, chain: "evm", profile: nil, outputMode: nil, index: 0)),
               "{\"operation\":\"createPublicPairing\",\"publicIndex\":{\"walletKeyId\":\"k\"},\"chain\":\"evm\",\"deviceName\":\"Ownbit\"}", "pairing without profile / mode")
            same(text(try await e.derivePublicIndex(seedHex: ABANDON_SEED, tronScheme: "ownbit", tronAddressCount: 100)),
               "{\"operation\":\"derivePublicIndex\",\"seed\":\"\(ABANDON_SEED)\",\"tronScheme\":\"ownbit\",\"tronAddressCount\":100}", "derivePublicIndex text")
            same(text(try await e.derivePublicIndex(seedHex: ABANDON_SEED, tronScheme: nil, tronAddressCount: nil)),
               "{\"operation\":\"derivePublicIndex\",\"seed\":\"\(ABANDON_SEED)\"}", "derivePublicIndex without options")
            same(text(try await e.refreshPublicIndex(publicIndex: k, tronScheme: "ownbit", tronAddressCount: 250)),
               "{\"operation\":\"derivePublicIndex\",\"publicIndex\":{\"walletKeyId\":\"k\"},\"tronScheme\":\"ownbit\",\"tronAddressCount\":250}", "refresh text")
            same(text(try await e.signPlanTask(request: k, plan: k, taskId: "t1", seedHex: ABANDON_SEED, riskAcknowledged: true, previousResult: nil)),
               "{\"operation\":\"signPlanTask\",\"request\":{\"walletKeyId\":\"k\"},\"plan\":{\"walletKeyId\":\"k\"},\"taskId\":\"t1\",\"seed\":\"\(ABANDON_SEED)\",\"riskAcknowledged\":true}", "signPlanTask text")
            same(text(try await e.signPlanTask(request: k, plan: k, taskId: "t2", seedHex: ABANDON_SEED, riskAcknowledged: false, previousResult: k)),
               "{\"operation\":\"signPlanTask\",\"request\":{\"walletKeyId\":\"k\"},\"plan\":{\"walletKeyId\":\"k\"},\"taskId\":\"t2\",\"seed\":\"\(ABANDON_SEED)\",\"riskAcknowledged\":false,\"previousResult\":{\"walletKeyId\":\"k\"}}", "signPlanTask with previousResult")
            same(text(try await e.encodeResponse(request: k, result: k)),
               "{\"operation\":\"encodeResponse\",\"request\":{\"walletKeyId\":\"k\"},\"result\":{\"walletKeyId\":\"k\"}}", "encodeResponse: no fragment length")
            same(text(try await e.decodePayload("cHNidP8B")), "{\"operation\":\"decodePayload\",\"payload\":\"cHNidP8B\"}", "decodePayload text")
            same(text(try await e.capabilities()), "{\"operation\":\"capabilities\"}", "capabilities text")
            let rr = try await e.reviewAndResolve(request: k, wallets: [obj(("localWalletId", .string("w")))])
            same(text(rr.review), "{\"operation\":\"review\",\"request\":{\"walletKeyId\":\"k\"}}", "review text")
            same(text(rr.plan), "{\"operation\":\"resolveSigningPlan\",\"request\":{\"walletKeyId\":\"k\"},\"wallets\":[{\"localWalletId\":\"w\"}]}", "resolve text")
            same(BILPublicSignerEngine.resolveRequestByteCount(request: k, wallets: [obj(("localWalletId", .string("w")))]), text(rr.plan).utf8.count,
               "resolveRequestByteCount = the resolve request actually sent")
            let bigWallets = [walletsAbandon[0], obj(("localWalletId", .string("中文"))), obj(("localWalletId", .string("w")), ("publicIndex", .object(indexLegal)))]
            let sized = try await e.reviewAndResolve(request: k, wallets: bigWallets)
            same(BILPublicSignerEngine.resolveRequestByteCount(request: k, wallets: bigWallets), text(sized.plan).utf8.count, "resolveRequestByteCount (UTF-8, big indexes)")
            let h0 = try await e.openScan()
            same(text(try await e.scanAdd(h0, frame: "a")), "{\"operation\":\"scanAdd\",\"frame\":\"a\"}", "scanAdd text")
            await e.closeScan(h0)
            await e.releasePairingContext()

            section("fake: deviceName in every pairing export (Android PAIRING_MATRIX)")
            var matrix: [(String, String?, String)] = []
            for p in ["native", "taproot", "nested", "legacy"] { for m in ["accountXpub", "address"] { matrix.append(("bitcoin", p, m)) } }
            matrix += [("bitcoin", "multisig-native", "accountXpub"), ("bitcoin", "multisig-nested", "accountXpub"), ("evm", nil, "wallet"), ("evm", nil, "address")]
            for p in ["standard", "trust", "legacy"] { for m in ["wallet", "address"] { matrix.append(("solana", p, m)) } }
            matrix.append(("tron", "standard", "address"))
            for (chain, profile, m) in matrix {
                let sent = parse(text(try await e.createPublicPairing(publicIndex: k, chain: chain, profile: profile, outputMode: m, index: 0)))
                same(sent.str("deviceName"), "Ownbit", "deviceName for \(chain)/\(profile ?? "-")/\(m)")
                same(sent.keys.last, "deviceName", "deviceName is the last parameter (\(chain))")
                same(sent.contains("index"), chain == "tron", "index only for TRON at #0 (\(chain))")
                check(!sent.contains("fragmentLength"), "no fragment length (\(chain))")
            }
            same(BILPublicSignerEngine.deviceName, "Ownbit", "device name constant")
            same(matrix.count, 19, "19-row pairing matrix (Android PAIRING_MATRIX)")
            // Android `every pairing export carries deviceName Ownbit` (gate 2A, §0 rule 6): the engine default is "BitSigner"
            // (vectors T3-pairing-default-name-*); Ownbit-named exports never carry it.
            func singleStep(_ c: BILPublicSignerVectors.Case) -> BILPublicSignerVectors.Step? {
                return c.pages.count == 1 && c.pages[0].count == 1 ? c.steps[c.pages[0][0]] : nil
            }
            let defaultNamed = vectors.cases.filter { $0.id.hasPrefix("T3-pairing-default-name-") }
            same(defaultNamed.count, 3, "three default-name pairing vectors")
            for c in defaultNamed {
                let response = singleStep(c)?.responseText ?? ""
                check(response.contains("BitSigner") && !response.contains("Ownbit"), "\(c.id) documents the engine default")
            }
            let ownbitNamed = vectors.cases.filter { $0.id.hasPrefix("T3-pairing-") && singleStep($0)?.request()?.str("deviceName") == "Ownbit" }
            check(ownbitNamed.count >= 24, "at least 24 Ownbit-named single-step pairing vectors (\(ownbitNamed.count))")
            var exportsChecked = 0
            for c in ownbitNamed {
                guard let step = singleStep(c), step.ok, step.request()?.str("outputMode") != "address" else { continue }
                exportsChecked += 1
                check(!ser(step.result ?? BILJSONObject()).contains("BitSigner"), "\(c.id): no BitSigner name in an Ownbit export")
            }
            check(exportsChecked > 0, "Ownbit exports checked for the engine default name (\(exportsChecked))")
            await e.releasePairingContext()

            section("fake: seed assertion (top level only)")
            throwsError(BILPublicSignerFailure.self, "seed parameter on decodePayload → invalidRequest") {
                _ = try BILPublicSignerEngine.debugRequestText(.decodePayload, [("seed", .string("x"))])
            }
            for op in BILPublicSignerOp.allCases where !op.carriesSeed {
                do {
                    _ = try BILPublicSignerEngine.debugRequestText(op, [("payload", .string("p")), ("seed", .string("x"))])
                    check(false, "\(op.rawValue) with a seed must be refused")
                } catch let f as BILPublicSignerFailure {
                    same(f, .invalidRequest, "\(op.rawValue) with a seed → invalidRequest")
                }
            }
            same(try BILPublicSignerEngine.debugRequestText(.signPlanTask, [("seed", .string("x"))]), "{\"operation\":\"signPlanTask\",\"seed\":\"x\"}", "SECRET op may carry it")
            let nested = obj(("seed", .string("deep")), ("x", .object(obj(("seed", .string("deeper"))))))
            let nestedAnswer = try await e.reviewAndResolve(request: nested, wallets: [])
            same(nestedAnswer.review.bool("hasSeed"), false, "a seed key nested inside an external request is data, not a parameter")
            same(nestedAnswer.review.obj("echo")?.str("seed"), "deep", "nested seed key passed through unchanged")

            section("fake: scan sessions")
            let s1 = try await e.openScan()
            let a1 = try await e.scanAdd(s1, frame: "a")
            same(a1.bool("complete"), false, "frame a: not complete")
            same(a1.long("n"), 2, "frame a: same context as scanBegin (n == 2)")
            check(await e.debugHasScanSession, "session open")
            _ = try await e.capabilities()
            let a2 = try await e.scanAdd(s1, frame: "b")
            same(a2.long("n"), 3, "a PAIRING op during a scan does not end it")
            let done = try await e.scanAdd(s1, frame: "END")
            same(done.bool("complete"), true, "END completes")
            check(!(await e.debugHasScanSession), "completion ends the session")
            await e.debugRecordRequests(true)
            let ended = await refusal("add after completion") { _ = try await e.scanAdd(s1, frame: "a") }
            same(ended?.code, "SCAN", "add after completion → SCAN")
            same(ended?.engineMessage, "No scan session is active.", "SCAN message")
            same((await e.debugTakeRequests()).count, 0, "an ended session never reaches the engine")
            await e.debugRecordRequests(false)
            let s2 = try await e.openScan()
            same((await refusal("BAD frame") { _ = try await e.scanAdd(s2, frame: "BAD") })?.code, "QR_PROTOCOL", "refused frame → engine code")
            same((await refusal("after a refused frame") { _ = try await e.scanAdd(s2, frame: "a") })?.code, "SCAN", "a refused frame ends the session")
            let s3 = try await e.openScan()
            _ = try await e.scanAdd(s3, frame: "a")
            _ = try await e.decodePayload("p")
            same((await refusal("after an isolated op") { _ = try await e.scanAdd(s3, frame: "a") })?.code, "SCAN", "an isolated op ends the session")
            let s4 = try await e.openScan()
            let s5 = try await e.openScan()
            same((await refusal("superseded") { _ = try await e.scanAdd(s4, frame: "a") })?.code, "SCAN", "a new scan ends the previous one")
            await e.closeScan(s4)
            same((try await e.scanAdd(s5, frame: "a")).bool("complete"), false, "a stale close leaves the new session alone")
            await e.closeScan(s5)
            await e.closeScan(s5)
            same((await refusal("closed") { _ = try await e.scanAdd(s5, frame: "a") })?.code, "SCAN", "closed session → SCAN")
            check([s1, s2, s3, s4, s5].map { $0.sessionId } == [s1, s2, s3, s4, s5].map { $0.sessionId }.sorted()
                && Set([s1, s2, s3, s4, s5].map { $0.sessionId }).count == 5, "handle ids strictly increasing")
            let s6 = try await e.openScan()
            _ = try await e.derivePublicIndex(seedHex: ABANDON_SEED, tronScheme: nil, tronAddressCount: nil)
            same((await refusal("after a SECRET op") { _ = try await e.scanAdd(s6, frame: "a") })?.code, "SCAN", "a SECRET op ends the session")
            // every other SECRET / UNTRUSTED entry point ends the open session too (D-02, S§2.5, C-QR-4)
            for (label, op) in [
                ("reviewAndResolve", { _ = try await e.reviewAndResolve(request: k, wallets: []) }),
                ("encodeResponse", { _ = try await e.encodeResponse(request: k, result: k) }),
                ("signPlanTask", { _ = try await e.signPlanTask(request: k, plan: k, taskId: "t", seedHex: ABANDON_SEED, riskAcknowledged: false, previousResult: nil) }),
                ("refreshPublicIndex", { _ = try await e.refreshPublicIndex(publicIndex: k, tronScheme: "ownbit", tronAddressCount: nil) }),
            ] as [(String, () async throws -> Void)] {
                let s = try await e.openScan()
                try await op()
                check(!(await e.debugHasScanSession), "\(label): no session left")
                same((await refusal("after \(label)") { _ = try await e.scanAdd(s, frame: "a") })?.code, "SCAN", "\(label) ends the session")
            }
            let s7 = try await e.openScan()
            let tooBig = await refusal("oversized frame") { _ = try await e.scanAdd(s7, frame: String(repeating: "f", count: 1_000_001)) }
            same(tooBig?.code, "LIMIT", "oversized frame → LIMIT")
            same((await refusal("after LIMIT") { _ = try await e.scanAdd(s7, frame: "a") })?.code, "SCAN", "a LIMIT refusal ends the session")
            let s8 = try await e.openScan()
            same((await refusal("oversized paste") { _ = try await e.decodePayload(String(repeating: "a", count: 1_000_000)) })?.code, "LIMIT", "oversized paste → LIMIT")
            same((await refusal("after an oversized isolated op") { _ = try await e.scanAdd(s8, frame: "a") })?.code, "SCAN",
               "an isolated op ends the session even when refused for size (Android order)")
            check(await e.debugHasPairingContext, "the PAIRING op of the scan section left its warm context")
            await e.releasePairingContext()
            same(contextsAlive(), base, "scan: no context left")
            let noStart = fakeDispatch("return JSON.stringify({ ok: true, result: {} });")
            await expectFailure(.malformedResponse, "scanBegin without started:true") { _ = try await noStart.openScan() }
            same(contextsAlive(), base, "failed scanBegin: no context left")
            let startedString = fakeDispatch("return JSON.stringify({ ok: true, result: { started: 'true' } });")
            await expectFailure(.malformedResponse, "started must be a JSON bool") { _ = try await startedString.openScan() }
            let startedOne = fakeDispatch("return JSON.stringify({ ok: true, result: { started: 1 } });")
            await expectFailure(.malformedResponse, "started 1 is not true") { _ = try await startedOne.openScan() }
            let beginRefused = fakeDispatch("return JSON.stringify({ ok: false, error: { code: 'LIMIT', message: 'x' } });")
            same((await refusal("scanBegin refusal") { _ = try await beginRefused.openScan() })?.code, "LIMIT", "scanBegin refusal is thrown")
            check(!(await beginRefused.debugHasScanSession), "refused scanBegin: no session")
            same(contextsAlive(), base, "refused scanBegin: no context left")

            section("fake: no network, entropy entry removed, frozen crypto")
            let n1 = try await e.decodePayload("x"), n2 = try await e.decodePayload("x")
            same(n1.strings("net") ?? [], Array(repeating: "undefined", count: 6), "no network / timer / worker API in the context")
            same(n1.str("entry"), "undefined", "native entropy entry deleted before the bundle")
            same(n1.bool("cryptoWritable"), false, "crypto not writable")
            same(n1.bool("mathRandomWritable"), false, "Math.random not writable")
            same(n1.str("mathRandom"), "number", "Math.random works")
            check(n1.str("random") != n2.str("random") && (n1.str("random") ?? "").count == 64, "fresh 32 random bytes per call")
            let injection = "\"; globalThis.n = 99; //"
            let inj = try await e.decodePayload(injection)
            same(inj.str("echo"), injection, "injection text echoed unchanged")
            same(inj.long("n"), 1, "injection text never ran as script")

            section("fake: odd characters")
            same((try await e.decodePayload(ODD)).str("echo"), ODD, "odd payload round trip")
            let so = try await e.openScan()
            same((try await e.scanAdd(so, frame: ODD)).str("echo"), ODD, "odd frame round trip")
            await e.closeScan(so)
            let oddPlan = try await e.reviewAndResolve(request: obj(("chain", .string(ODD))), wallets: [obj(("localWalletId", .string(ODD)))])
            same(oddPlan.plan.arr("wallets")?.first?.objectValue?.str("localWalletId"), ODD, "odd localWalletId round trip")
            same(oddPlan.review.obj("echo")?.str("chain"), ODD, "odd request value round trip")

            section("fake: refusal bounds")
            let long = String(repeating: "m", count: 399) + "😀" + "tail"
            let bounded = fakeDispatch("return JSON.stringify({ ok: false, error: { code: 'bad_code !', message: '" + String(repeating: "m", count: 399) + "\\ud83d\\ude00tail' } });")
            if let r = await refusal("bounded refusal", { _ = try await bounded.decodePayload("x") }) {
                same(r.code, "BAD_CODE", "code sanitized")
                same(r.engineMessage, String(repeating: "m", count: 399), "message cut at 400 UTF-16 units without splitting the pair")
                same(String(describing: r), "Public signer refused the request: BAD_CODE", "description = code only")
                check(!String(describing: r).contains("mmm") && !String(reflecting: r).contains("mmm"), "description never carries the message")
                check(long.utf16.count > 400, "the sample really is longer than the bound")
            }
            let empty = fakeDispatch("return JSON.stringify({ ok: false, error: {} });")
            if let r = await refusal("default refusal", { _ = try await empty.capabilities() }) {
                same(r.code, "SIGNING_FAILED", "default code")
                same(r.engineMessage, "This request could not be signed.", "default message")
            }
            let nonString = fakeDispatch("return JSON.stringify({ ok: false, error: { code: 7, message: ['x'] } });")
            same((await refusal("non-string error members", { _ = try await nonString.capabilities() }))?.code, "SIGNING_FAILED", "non-string code → default")
            let noError = fakeDispatch("return JSON.stringify({ ok: false });")
            same((await refusal("no error object", { _ = try await noError.capabilities() }))?.engineMessage, "This request could not be signed.", "no error → defaults")
            let x200 = fakeDispatch("return JSON.stringify({ ok: false, error: { code: '" + String(repeating: "X", count: 200) + "', message: 'short' } });")
            same((await refusal("long code", { _ = try await x200.capabilities() }))?.code.count, 80, "code ≤ 80")
            same(BILPublicSignerRefusal(code: "", engineMessage: "m").code, "UNKNOWN", "empty code → UNKNOWN")
            for warm in [empty, nonString, noError, x200] { await warm.releasePairingContext() }
            let keepsWarm = fakeDispatch("globalThis.c = (globalThis.c || 0) + 1; return globalThis.c === 1 ? JSON.stringify({ ok: false, error: { code: 'X', message: 'm' } }) : 'not json';")
            _ = await refusal("warm refusal", { _ = try await keepsWarm.capabilities() })
            check(await keepsWarm.debugHasPairingContext, "an engine refusal keeps the warm context")
            await expectFailure(.malformedResponse, "warm failure") { _ = try await keepsWarm.capabilities() }
            check(!(await keepsWarm.debugHasPairingContext), "a malformed answer drops the warm context")

            section("fake: a review refusal never runs the resolver (Android PublicSignerJsBridgeTest)")
            let reviewRefuses = fakeDispatch("var r = JSON.parse(json); return r.operation === 'review' ? JSON.stringify({ ok: false, error: { code: 'NETWORK', message: 'Unsupported network' } }) : JSON.stringify({ ok: true, result: {} });")
            await reviewRefuses.debugRecordRequests(true)
            let reviewRefusal = await refusal("review refusal") { _ = try await reviewRefuses.reviewAndResolve(request: k, wallets: []) }
            same(reviewRefusal?.code, "NETWORK", "review refusal: the engine code")
            same(reviewRefusal?.engineMessage, "Unsupported network", "review refusal: the engine message")
            same((await reviewRefuses.debugTakeRequests()).map { $0.op }, [.review], "the resolver never runs after a review refusal")
            same(contextsAlive(), base, "review refusal: context dropped")

            section("replay: page mapping (Android BridgeReplay skips only scanAdd / noSuchOperation pages)")
            let refusedStep = "\"response\":{\"ok\":false,\"error\":{\"code\":\"OPERATION\",\"message\":\"m\"}},\"responseSha256\":\"0\""
            let synthetic = try BILPublicSignerVectors(vectorsJSON: "{\"fixtures\":{},\"cases\":["
                + "{\"id\":\"X-unknown\",\"group\":\"x\",\"steps\":[{\"page\":0,\"request\":{\"operation\":\"noSuchOperation\"}," + refusedStep + "}]},"
                + "{\"id\":\"X-excluded\",\"group\":\"x\",\"steps\":[{\"page\":0,\"request\":{\"operation\":\"mnemonic\"}," + refusedStep + "}]}]}")
            if let unknownCase = synthetic.caseNamed("X-unknown"), let excludedCase = synthetic.caseNamed("X-excluded") {
                let unknown = await BILPublicSignerVectorReplay.runProductionCase(unknownCase, engine: e)
                same(unknown.skipped, ["X-unknown:noSuchOperation"], "a noSuchOperation page is skipped")
                same(unknown.failures, [], "a noSuchOperation page is not a failure")
                let excluded = await BILPublicSignerVectorReplay.runProductionCase(excludedCase, engine: e)
                same(excluded.skipped, [], "a page of another unknown operation is not skipped")
                same(excluded.failures, ["X-excluded: page pattern not mapped"], "a page of another unknown operation fails")
            } else {
                check(false, "synthetic vectors parse")
            }

            section("fake: malformed envelopes")
            for (label, body) in [
                ("not json", "return 'not json';"), ("array", "return '[]';"), ("empty object", "return '{}';"),
                ("ok string", "return '{\"ok\":\"true\",\"result\":{}}';"), ("ok without result", "return '{\"ok\":true}';"),
                ("result array", "return '{\"ok\":true,\"result\":[1]}';"), ("result string", "return '{\"ok\":true,\"result\":\"x\"}';"),
                ("ok number", "return '{\"ok\":1,\"result\":{}}';"), ("ok null", "return '{\"ok\":null,\"result\":{}}';"),
                ("result null", "return '{\"ok\":true,\"result\":null}';"),
                ("duplicate key", "return '{\"ok\":false,\"result\":{},\"ok\":true}';"),
                ("trailing data", "return '{\"ok\":true,\"result\":{}} x';"),
                ("lone surrogate escape (D-27)", "return '{\"ok\":true,\"result\":{\"x\":\"\\\\ud800\"}}';"),
                ("over 2 MiB", "return '{\"ok\":true,\"result\":{\"x\":\"' + 'a'.repeat(2097152) + '\"}}';"),
                ("throws", "throw new Error('boom');"), ("number", "return 5;"), ("undefined", "return;"),
            ] {
                let m = fakeDispatch(body)
                await expectFailure(.malformedResponse, "malformed: \(label)") { _ = try await m.decodePayload("x") }
            }
            let atLimit = fakeDispatch("var s = '{\"ok\":true,\"result\":{\"x\":\"'; var t = '\"}}'; return s + 'a'.repeat(2097152 - s.length - t.length) + t;")
            let envelopeOverhead = "{\"ok\":true,\"result\":{\"x\":\"".utf8.count + "\"}}".utf8.count
            same((try await atLimit.decodePayload("x")).str("x")?.count, 2_097_152 - envelopeOverhead, "a response of exactly 2 MiB is accepted")
            same(contextsAlive(), base, "envelopes: no context left")

            section("fake: 1,000,000-byte request guard")
            let overhead = "{\"operation\":\"decodePayload\",\"payload\":\"\"}".utf8.count
            same(overhead, 42, "decodePayload overhead")
            let maxPayload = String(repeating: "a", count: 1_000_000 - overhead)
            same((try await e.decodePayload(maxPayload)).str("text")?.utf8.count, 1_000_000, "a request of exactly 1,000,000 bytes reaches the engine")
            let createdBeforeLimit = BILPublicSignerJSContext.created
            let limit = await refusal("one byte more") { _ = try await e.decodePayload(maxPayload + "a") }
            same(limit?.code, "LIMIT", "1,000,001 bytes → LIMIT")
            same(limit?.engineMessage, "Request exceeds one megabyte.", "LIMIT message")
            same((await refusal("multi-byte") { _ = try await e.decodePayload(String(repeating: "中", count: 333_334)) })?.code, "LIMIT", "UTF-8 bytes count (中 × 333,334)")
            same((await refusal("pairing over the limit") {
                _ = try await e.createPublicPairing(publicIndex: obj(("x", .string(maxPayload))), chain: "evm", profile: nil, outputMode: nil, index: 0)
            })?.code, "LIMIT", "PAIRING over the limit → LIMIT")
            same((await refusal("resolve over the limit") {
                _ = try await e.reviewAndResolve(request: k, wallets: [obj(("localWalletId", .string(maxPayload)))])
            })?.code, "LIMIT", "resolve over the limit → LIMIT before any context")
            same(BILPublicSignerJSContext.created, createdBeforeLimit, "no context created for a refused request")
            same(BILPublicSignerEngine.maxRequestBytes, 1_000_000, "maxRequestBytes")
            same(BILPublicSignerEngine.maxResponseBytes, 2_097_152, "maxResponseBytes")

            section("fake: load failures")
            for (label, js) in [
                ("syntax error", "var BitSignerEngine = {"), ("no BitSignerEngine", "var Other = { dispatch: function () { return '{}'; } };"),
                ("dispatch not a function", "var BitSignerEngine = { dispatch: 5 };"),
                ("dispatch an object", "var BitSignerEngine = { dispatch: {} };"),
                ("throws at load", "throw new Error('load');"),
            ] {
                let bad = fake(js)
                await expectFailure(.engineUnavailable, "load: \(label)") { _ = try await bad.decodePayload("x") }
                check(!(await bad.isAvailable()), "load: \(label) → probe false")
            }
            let missing = BILPublicSignerEngine(sourceURL: fakeDir.appendingPathComponent("missing.js"), pinned: false)
            await expectFailure(.engineUnavailable, "load: missing file") { _ = try await missing.capabilities() }
            var changed = [UInt8](engineData)
            changed[10] = changed[10] == 0x61 ? 0x62 : 0x61          // inside the banner comment: still valid JS
            let changedURL = fakeDir.appendingPathComponent("signer-changed.js")
            try Data(changed).write(to: changedURL)
            let pinnedChanged = BILPublicSignerEngine(sourceURL: changedURL, pinned: true)
            await expectFailure(.engineUnavailable, "pinned: one byte changed") { _ = try await pinnedChanged.capabilities() }
            let unpinnedChanged = BILPublicSignerEngine(sourceURL: changedURL, pinned: false)
            same((try await unpinnedChanged.capabilities()).str("version"), "1.0.0", "the same bytes load unpinned (the SHA is the reason)")
            await unpinnedChanged.releasePairingContext()
            same(contextsAlive(), base, "load failures: no context left")

            section("availability (R1 §2.4)")
            guard let golden = vcase("T1-capabilities").steps.first?.result else { check(false, "T1 golden"); return }
            check(BILPublicSignerAvailability.isExpectedEngine(golden), "golden capabilities are the expected engine")
            func mutated(_ change: (inout BILJSONObject) -> Void) -> BILJSONObject { var c = golden; change(&c); return c }
            let tron = golden.obj("tron") ?? BILJSONObject()
            for (label, caps) in [
                ("version 1.0.1", mutated { $0.set("version", .string("1.0.1")) }), ("version number", mutated { $0.set("version", .number("1")) }),
                ("offline false", mutated { $0.set("offline", .bool(false)) }), ("offline \"true\"", mutated { $0.set("offline", .string("true")) }),
                ("offline 1", mutated { $0.set("offline", .number("1")) }),
                ("no pairingOptions", mutated { $0.remove("pairingOptions") }), ("pairingOptions []", mutated { $0.set("pairingOptions", .array([])) }),
                ("pairingOptions string", mutated { $0.set("pairingOptions", .string("deviceName")) }),
                ("no publicIndexOptions", mutated { $0.remove("publicIndexOptions") }),
                ("publicIndexOptions without tronScheme", mutated { $0.set("publicIndexOptions", .array([.string("publicIndex")])) }),
                ("tron.supported without TronLink", mutated { var t2 = tron; t2.set("supported", .array([.string("TRX transfer")])); $0.set("tron", .object(t2)) }),
                ("no tron", mutated { $0.remove("tron") }),
                ("TronLink text changed", mutated {
                    var t2 = tron
                    t2.set("supported", .array([.string("TronLink ownership check (exact fixed placeholder) ")]))
                    $0.set("tron", .object(t2))
                }),
            ] as [(String, BILJSONObject)] {
                check(!BILPublicSignerAvailability.isExpectedEngine(caps), "not the expected engine: \(label)")
            }
            check(BILPublicSignerAvailability.isExpectedEngine(mutated { $0.set("pairingOptions", .array([.number("1"), .null, .string("deviceName")])) }),
              "non-string list elements are ignored (Android strings())")
            same(BILPublicSignerAvailability.engineVersion, "1.0.0", "engineVersion")
            same(BILPublicSignerAvailability.tronSchemeOption, "tronScheme", "tronSchemeOption")
            same(BILPublicSignerAvailability.tronLinkOwnershipCheck, "TronLink ownership check (exact fixed placeholder)", "TronLink check text")
            let goldenText = ser(golden).replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
            let goodCaps = fakeDispatch("globalThis.c = (globalThis.c || 0) + 1; return JSON.stringify({ ok: true, result: JSON.parse('" + goldenText + "') });")
            await goodCaps.debugRecordRequests(true)
            check(await goodCaps.isAvailable(), "probe: expected engine")
            check(await goodCaps.isAvailable(), "probe: cached")
            same((await goodCaps.debugTakeRequests()).count, 1, "probe success cached: one capabilities call")
            let flaky = fakeDispatch("globalThis.c = (globalThis.c || 0) + 1; var r = JSON.parse('" + goldenText + "'); if (globalThis.c === 1) r.version = '0.9'; return JSON.stringify({ ok: true, result: r });")
            await flaky.debugRecordRequests(true)
            check(!(await flaky.isAvailable()), "probe: wrong engine first")
            check(await flaky.isAvailable(), "probe: a failure is not cached")
            check(await flaky.isAvailable(), "probe: then cached")
            same((await flaky.debugTakeRequests()).count, 2, "probe: two capabilities calls")
            // (The app's DEBUG forced probe failures, `-bil_debug_pub_engine_fail`, are not part of the package.)
            await goodCaps.releasePairingContext()
            await flaky.releasePairingContext()

            section("fake: concurrent callers are serialized")
            let slow = fake("""
            var BitSignerEngine = { dispatch: function (json) {
                var r = JSON.parse(json); globalThis.n = (globalThis.n || 0) + 1;
                var x = 0; for (var i = 0; i < 200000; i++) { x += i; }
                return JSON.stringify({ ok: true, result: { n: globalThis.n, tag: r.payload || r.chain || r.operation } });
            } };
            """)
            let tags = try await withThrowingTaskGroup(of: (String, BILJSONObject).self) { group -> [(String, BILJSONObject)] in
                for i in 0..<12 {
                    group.addTask {
                        if i % 3 == 2 {
                            return ("evm", try await slow.createPublicPairing(publicIndex: k, chain: "evm", profile: nil, outputMode: nil, index: 0))
                        }
                        return ("p\(i)", try await slow.decodePayload("p\(i)"))
                    }
                }
                var out: [(String, BILJSONObject)] = []
                for try await item in group { out.append(item) }
                return out
            }
            check(tags.allSatisfy { $0.0 == $0.1.str("tag") }, "every concurrent result belongs to its own request")
            check(tags.filter { $0.0 != "evm" }.allSatisfy { $0.1.long("n") == 1 }, "every concurrent isolated call had its own fresh context")
            same(tags.filter { $0.0 == "evm" }.compactMap { $0.1.long("n") }.sorted(), [1, 2, 3, 4], "concurrent PAIRING calls share the warm context in turn")
            await slow.releasePairingContext()
            same(contextsAlive(), base, "concurrency: no context left")
        }

        // MARK: - 6 real-engine hardening (R1 §11.3; Android PublicSignerHardeningOnDeviceTest, PublicSignerIsolationTest)

        runAsync(timeout: 600) {
            let e = realEngine
            let base = contextsAlive()

            section("hardening: refusal codes")
            let network = steps("T9-unsupported-network", .review)[0].request()?.obj("request") ?? BILJSONObject()
            same((await refusal("NETWORK") { _ = try await e.reviewAndResolve(request: network, wallets: walletsAbandon) })?.code, "NETWORK", "unsupported network")
            for step in steps("T9-tampered-plan", .signPlanTask) where !step.ok {
                let r = step.request() ?? BILJSONObject()
                let got = await refusal("tampered plan") {
                    _ = try await e.signPlanTask(request: r.obj("request") ?? BILJSONObject(), plan: r.obj("plan") ?? BILJSONObject(), taskId: r.str("taskId") ?? "",
                                                 seedHex: r.str("seed") ?? "", riskAcknowledged: r.bool("riskAcknowledged") ?? false, previousResult: nil)
                }
                same(got?.code, step.error?.code, "tampered plan → \(step.error?.code ?? "?")")
            }
            let opaque = steps("O-EVM-4-personal-hash", .signPlanTask)
            if let first = opaque.first?.request(), opaque.count == 2 {
                let req = first.obj("request") ?? BILJSONObject(), plan = first.obj("plan") ?? BILJSONObject(), task = first.str("taskId") ?? ""
                same((await refusal("RISK") { _ = try await e.signPlanTask(request: req, plan: plan, taskId: task, seedHex: ABANDON_SEED, riskAcknowledged: false, previousResult: nil) })?.code,
                   "RISK", "opaque request needs the acknowledgement")
                same(try await e.signPlanTask(request: req, plan: plan, taskId: task, seedHex: ABANDON_SEED, riskAcknowledged: true, previousResult: nil), opaque[1].result,
                   "acknowledged → the golden result")
            } else {
                check(false, "O-EVM-4 vectors")
            }
            for (id, code) in [("O-SOL-2-lookup-table", "LOOKUP_TABLE"), ("O-BTC-1-prevout-mismatch", "INVALID_REQUEST"), ("T9-tron-type-url-bom", "INTEGRITY")] {
                let request = steps(id, .review)[0].request()?.obj("request") ?? BILJSONObject()
                same((await refusal(id) { _ = try await e.reviewAndResolve(request: request, wallets: walletsAbandon) })?.code, code, "\(id) → \(code)")
            }
            let owner = steps("O-TRX-1-owner-not-signer", .signPlanTask)[0]
            if let r = owner.request() {
                same(try await e.signPlanTask(request: r.obj("request") ?? BILJSONObject(), plan: r.obj("plan") ?? BILJSONObject(), taskId: r.str("taskId") ?? "",
                                            seedHex: ABANDON_SEED, riskAcknowledged: r.bool("riskAcknowledged") ?? false, previousResult: nil), owner.result,
                   "the engine signs a TRC-20 transfer whose owner is not the signer (the owner rule is native)")
            }
            same((await refusal("SEED") { _ = try await e.derivePublicIndex(seedHex: "not-a-seed", tronScheme: nil, tronAddressCount: nil) })?.code, "SEED", "bad seed → SEED")
            same(contextsAlive(), base, "refusals: no context left")

            section("hardening: scan refusals end the session")
            for id in ["T5-scan-bbqr-Z-bomb", "T5-wrong-direction-pairing-ur", "T5-wrong-direction-signature-ur", "T5-oversized-frame", "T5-mixed-types", "O-QR-1-foreign-part"] {
                let frames = steps(id, .scanAdd)
                guard let last = frames.last, let lastFrame = last.request()?.str("frame"), let firstFrame = frames.first?.request()?.str("frame") else {
                    check(false, id)
                    continue
                }
                let scan = try await e.openScan()
                for f in frames.dropLast() { _ = try await e.scanAdd(scan, frame: f.request()?.str("frame") ?? "") }
                let got = await refusal(id) { _ = try await e.scanAdd(scan, frame: lastFrame) }
                same(got?.code, "QR_PROTOCOL", "\(id): code")
                same(got?.engineMessage, last.error?.message, "\(id): engine message")
                same((await refusal("\(id) ended") { _ = try await e.scanAdd(scan, frame: firstFrame) })?.code, "SCAN", "\(id): the session ended")
            }
            check(!(await e.debugHasScanSession), "scan refusals: no session left")
            let shuffled = steps("O-QR-1-animated-shuffled", .scanAdd).compactMap { $0.request()?.str("frame") }
            let keep = try await e.openScan()
            for f in shuffled.dropLast() {
                same((try await e.scanAdd(keep, frame: f)).bool("complete"), false, "fountain part keeps the session")
                check(await e.debugHasScanSession, "session owns its context")
            }
            same((try await e.scanAdd(keep, frame: shuffled.last ?? "")).bool("complete"), true, "fountain completes")
            check(!(await e.debugHasScanSession), "completion drops the scan context")
            let two = steps("T8-flow-bitcoin-crypto-psbt", .scanAdd).compactMap { $0.request()?.str("frame") }
            same(two.count, 2, "2-frame PSBT")
            for attempt in 0..<3 {
                _ = await refusal("not a payload") { _ = try await e.decodePayload("not a payload") }
                let scan = try await e.openScan()
                same((try await e.scanAdd(scan, frame: two[0])).bool("complete"), false, "attempt \(attempt): first frame")
                same((try await e.scanAdd(scan, frame: two[1])).bool("complete"), true, "attempt \(attempt): a scan right after a failed op completes")
            }
            let replaced = try await e.openScan()
            _ = try await e.derivePublicIndex(seedHex: ABANDON_SEED, tronScheme: nil, tronAddressCount: nil)
            same((await refusal("after derive") { _ = try await e.scanAdd(replaced, frame: two[0]) })?.code, "SCAN", "no page state reaches the next operation")
            same(contextsAlive(), base, "scans: no context left")

            section("hardening: EIP-712 F1 / F7 / F14")
            let signer = "0x9858EfFD232B4033E47d90003D41EC34EcaEda94"
            func field(_ name: String, _ type: String) -> BILJSONValue { return .object(obj(("name", .string(name)), ("type", .string(type)))) }
            func typedRequest(_ typedData: BILJSONObject) -> BILJSONObject {
                return obj(("chain", .string("evm")), ("kind", .string("typedData")), ("path", .string("m/44'/60'/0'/0/0")), ("address", .string(signer)),
                           ("masterFingerprint", .string("73c5da0a")), ("typedData", .object(typedData)))
            }
            func daiPermit(_ allowed: BILJSONValue) -> BILJSONObject {
                let types = obj(("EIP712Domain", .array([field("name", "string"), field("version", "string"), field("chainId", "uint256"), field("verifyingContract", "address")])),
                                ("Permit", .array([field("holder", "address"), field("spender", "address"), field("nonce", "uint256"), field("expiry", "uint256"), field("allowed", "bool")])))
                return obj(("types", .object(types)), ("primaryType", .string("Permit")),
                           ("domain", .object(obj(("name", .string("Dai Stablecoin")), ("version", .string("1")), ("chainId", .int(1)),
                                                  ("verifyingContract", .string("0x6B175474E89094C44Da98b954EedeAC495271d0F"))))),
                           ("message", .object(obj(("holder", .string(signer)), ("spender", .string("0x" + String(repeating: "ba", count: 20))), ("nonce", .int(0)),
                                                   ("expiry", .int(0)), ("allowed", allowed)))))
            }
            for allowed in [BILJSONValue.string("false"), .string("0"), .string("no"), .string("False"), .string(" "), .int(1), .null] {
                same((await refusal("F1") { _ = try await e.reviewAndResolve(request: typedRequest(daiPermit(allowed)), wallets: walletsAbandon) })?.code,
                   "TYPED_DATA", "F1: bool spelled \(BILStrictJSON.serialize(allowed)) refused")
            }
            let revoke = try await e.reviewAndResolve(request: typedRequest(daiPermit(.bool(false))), wallets: walletsAbandon)
            same(revoke.plan.str("status"), "ready", "F1: false → ready")
            check(!(revoke.review.strings("warnings") ?? []).contains { $0.contains("UNLIMITED") }, "F1: false → no UNLIMITED warning")
            let unlimited = try await e.reviewAndResolve(request: typedRequest(daiPermit(.bool(true))), wallets: walletsAbandon)
            check((unlimited.review.strings("warnings") ?? []).contains { $0.contains("UNLIMITED") }, "F1: true → UNLIMITED warning")
            same(unlimited.review.obj("display")?.str("amount"), "Unlimited", "F1: display amount Unlimited")
            func transfer(_ to: String, _ amount: BILJSONValue) -> BILJSONObject {
                let td = obj(("types", .object(obj(("Transfer", .array([field("to", "address"), field("amount", "uint256")]))))), ("primaryType", .string("Transfer")),
                             ("domain", .object(obj(("name", .string("Test")), ("chainId", .int(1))))), ("message", .object(obj(("to", .string(to)), ("amount", amount)))))
                return obj(("chain", .string("evm")), ("kind", .string("typedData")), ("typedData", .object(td)))
            }
            let to = "0x" + String(repeating: "22", count: 20)
            for amount in ["0o777", "0b101", "  100", "1e3", "-1", "100 ", "0x"].map({ BILJSONValue.string($0) }) + [.number("1.5")] {
                let code = (await refusal("F7") { _ = try await e.reviewAndResolve(request: transfer(to, amount), wallets: walletsAbandon) })?.code
                check(code == "TYPED_DATA" || code == "PRECISION", "F7: amount \(BILStrictJSON.serialize(amount)) refused (\(code ?? "-"))")
            }
            same((await refusal("ICAP") { _ = try await e.reviewAndResolve(request: transfer("XE7338O073KYGTWWZN0F2WZ0R8PX5ZPPZS", .string("1")), wallets: walletsAbandon) })?.code,
               "TYPED_DATA", "F7: ICAP address refused")
            same((await refusal("checksum") { _ = try await e.reviewAndResolve(request: transfer(signer.replacingOccurrences(of: "Ef", with: "eF"), .string("1")), wallets: walletsAbandon) })?.code,
               "TYPED_DATA", "F7: bad checksum refused")
            let max256 = "115792089237316195423570985008687907853269984665640564039457584007913129639935"
            same((try await e.reviewAndResolve(request: transfer(to, .string(max256)), wallets: walletsAbandon)).review.str("decodeStatus"), "partiallyDecoded",
               "F7: 2^256 − 1 accepted (partially decoded)")
            same((await refusal("2^256") { _ = try await e.reviewAndResolve(request: transfer(to, .string("115792089237316195423570985008687907853269984665640564039457584007913129639936")), wallets: walletsAbandon) })?.code,
               "TYPED_DATA", "F7: 2^256 refused")
            func mail(_ domainFields: [(String, String)]) -> BILJSONObject {
                let types = obj(("EIP712Domain", .array(domainFields.map { field($0.0, $0.1) })), ("Mail", .array([field("contents", "string")])),
                                ("Unused", .array([field("x", "uint8")])))
                return obj(("types", .object(types)), ("primaryType", .string("Mail")),
                           ("domain", .object(obj(("name", .string("Order test")), ("chainId", .int(1))))), ("message", .object(obj(("contents", .string("hello"))))))
            }
            let ordered = try await e.reviewAndResolve(request: typedRequest(mail([("chainId", "uint256"), ("name", "string")])), wallets: walletsAbandon)
            same(ordered.plan.str("status"), "ready", "F14: declared order → ready")
            let reversed = try await e.reviewAndResolve(request: typedRequest(mail([("name", "string"), ("chainId", "uint256")])), wallets: walletsAbandon)
            check(ordered.plan.str("signingBytesDigest") != nil && ordered.plan.str("signingBytesDigest") != reversed.plan.str("signingBytesDigest"),
              "F14: the declared domain order defines the separator")
            same((await refusal("F14 missing") { _ = try await e.reviewAndResolve(request: typedRequest(mail([("chainId", "uint256")])), wallets: walletsAbandon) })?.code,
               "TYPED_DATA", "F14: a domain field missing from the declaration is refused")

            section("hardening: strict parser and size limits")
            same((await refusal("unsafe integer") { _ = try await e.reviewAndResolve(request: obj(("chain", .string("evm")), ("nonce", .number("9007199254740993"))), wallets: walletsAbandon) })?.code,
               "QR_PROTOCOL", "an unsafe integer literal is refused, not rounded")
            var deep = BILJSONValue.int(1)
            for _ in 0..<40 { deep = .array([deep]) }
            same((await refusal("deep") { _ = try await e.reviewAndResolve(request: obj(("chain", .string("evm")), ("x", deep)), wallets: walletsAbandon) })?.code,
               "QR_PROTOCOL", "nesting deeper than 32 is refused")
            func rawCode(_ text: String) -> String? {
                guard let c = try? BILPublicSignerJSContext(source: engineText, sourceURL: engineURL), let answer = try? c.dispatchText(text) else { return nil }
                return parse(answer).obj("error")?.str("code")
            }
            same(rawCode("{\"operation\":\"capabilities\",\"operation\":\"capabilities\"}"), "QR_PROTOCOL", "raw: duplicate key")
            same(rawCode(String(repeating: "x", count: 1_048_577)), "LIMIT", "raw: > 1 MiB → engine LIMIT")
            same(rawCode("{\"operation\":\"capabilities\"} trailing"), "QR_PROTOCOL", "raw: trailing data")
            same(rawCode("{\"operation\":\"noSuchOperation\"}"), "OPERATION", "raw: unknown operation")
            let created = BILPublicSignerJSContext.created
            let big = await refusal("big paste") { _ = try await e.decodePayload(String(repeating: "A", count: 1_000_000)) }
            same(big?.code, "LIMIT", "1,000,000 × A → bridge LIMIT")
            same(BILPublicSignerJSContext.created, created, "no context loaded for it")
            let allowedBig = await refusal("900 KB paste") { _ = try await e.decodePayload(String(repeating: "A", count: 900_000)) }
            check(allowedBig != nil && allowedBig?.engineMessage != "Request exceeds one megabyte.", "900,000 × A reaches the engine (\(allowedBig?.code ?? "-"))")

            section("hardening: no echo of the request in engine text (C-KEY-5)")
            let marker = "MARKER-7f3a91"
            let probes: [(String, () async throws -> Void)] = [
                ("UR paste", { _ = try await e.decodePayload("ur:eth-sign-request/" + marker) }),
                ("PSBT paste", { _ = try await e.decodePayload("cHNidP8" + marker) }),
                ("personal", { _ = try await e.reviewAndResolve(request: obj(("chain", .string("evm")), ("kind", .string("personal")), ("message", .string("0x" + marker))), wallets: walletsAbandon) }),
                ("chain", { _ = try await e.reviewAndResolve(request: obj(("chain", .string(marker))), wallets: walletsAbandon) }),
                ("seed", { _ = try await e.derivePublicIndex(seedHex: marker, tronScheme: nil, tronAddressCount: nil) }),
                ("pairing", { _ = try await e.createPublicPairing(publicIndex: indexAbandon, chain: marker, profile: marker, outputMode: marker, index: 0) }),
                ("address profile", { _ = try await e.derivePublicAddresses(publicIndex: indexAbandon, chain: "bitcoin", profile: marker, start: 0, count: 1) }),
                ("scan frame", { let h = try await e.openScan(); _ = try await e.scanAdd(h, frame: "UR:" + marker + "/1-2/X") }),
            ]
            for (label, probe) in probes {
                if let r = await refusal("no echo: \(label)", probe) {
                    check(!r.engineMessage.contains(marker), "no echo: \(label) message")
                    check(!String(describing: r).contains(marker), "no echo: \(label) description")
                    check(r.engineMessage.utf16.count <= 400, "no echo: \(label) bounded")
                }
            }
            await e.releasePairingContext()

            section("hardening: data fidelity, seeds, BIP340")
            let personal = steps("T6-plan-evm-registered-index-8", .resolveSigningPlan)[0].request()?.obj("request") ?? BILJSONObject()
            check(ODD.utf16.count <= 128, "odd id within the engine's local wallet id limit")
            let oddPlan = try await e.reviewAndResolve(request: personal, wallets: [obj(("localWalletId", .string(ODD)), ("publicIndex", .object(indexAbandon)))]).plan
            same(oddPlan.str("status"), "ready", "odd localWalletId: plan ready")
            same(oddPlan.arr("tasks")?.first?.objectValue?.str("localWalletId"), ODD, "odd localWalletId echoed in the task")
            for p in vectors.phrases {
                let golden = vcase("T2-derivePublicIndex-" + p.id).steps.first?.result
                same(try await e.derivePublicIndex(seedHex: p.seedHex, tronScheme: nil, tronAddressCount: nil), golden ?? BILJSONObject(), "seed \(p.id) → T2 golden index")
            }
            same(vectors.phrases.map { $0.id }, ["abandon", "legal", "zh-hans"], "the three vector phrases")
            same(vectors.phrases.first?.seedHex, ABANDON_SEED, "abandon seed")
            same(try await e.derivePublicIndex(seedHex: ABANDON_SEED, tronScheme: "ownbit", tronAddressCount: 100), indexOwnbit, "Ownbit scheme, 100 → publicIndex.abandonOwnbit")
            same(try await e.refreshPublicIndex(publicIndex: indexAbandon, tronScheme: "ownbit", tronAddressCount: nil), indexOwnbit, "refresh of the standard index → abandonOwnbit")
            same((try await e.derivePublicIndex(seedHex: ABANDON_SEED, tronScheme: nil, tronAddressCount: nil)), indexAbandon, "standard index = publicIndex.abandon")
            let psbt3 = steps("T7-native-bitcoin-psbt-3", .signPlanTask)[0]
            if let r = psbt3.request(), let request = r.obj("request"), let plan = r.obj("plan"), let taskId = r.str("taskId"), let golden = psbt3.result?.str("psbt") {
                var psbts: [String] = []
                for _ in 0..<2 {
                    psbts.append((try await e.signPlanTask(request: request, plan: plan, taskId: taskId, seedHex: ABANDON_SEED,
                                                           riskAcknowledged: r.bool("riskAcknowledged") ?? false, previousResult: nil)).str("psbt") ?? "")
                }
                check(psbts[0] != psbts[1], "BIP340 aux randomness differs per signature")
                for (i, p) in psbts.enumerated() {
                    let why = await BILPublicSignerVectorReplay.verifyTaproot(request: request, signed: p, golden: golden, engine: e)
                    check(why == nil, "BIP340 signature \(i) verifies (\(why ?? "ok"))")
                }
                let bad = await BILPublicSignerVectorReplay.verifyTaproot(request: request, signed: golden, golden: golden, engine: e)
                check(bad != nil, "verifyTaproot refuses an unchanged PSBT (no fresh signature)")
            } else {
                check(false, "T7-native-bitcoin-psbt-3")
            }

            section("U7 timings (macOS; the device numbers come from pubperf)")
            func ms(_ t0: Int64) -> Int64 { return BILMonotonicClock.millis() - t0 }
            await e.releasePairingContext()
            var t0 = BILMonotonicClock.millis()
            _ = try await e.capabilities()
            let coldCaps = ms(t0)
            t0 = BILMonotonicClock.millis()
            _ = try await e.derivePublicIndex(seedHex: ABANDON_SEED, tronScheme: "ownbit", tronAddressCount: 100)
            let prepare = ms(t0)
            check(prepare <= 3_000, "Prepare (derivePublicIndex ownbit 100) ≤ 3 s (\(prepare) ms)")
            let sign1 = steps("T7-native-bitcoin-psbt-1", .signPlanTask)[0].request() ?? BILJSONObject()
            t0 = BILMonotonicClock.millis()
            _ = try await e.signPlanTask(request: sign1.obj("request") ?? BILJSONObject(), plan: sign1.obj("plan") ?? BILJSONObject(),
                                         taskId: sign1.str("taskId") ?? "", seedHex: ABANDON_SEED, riskAcknowledged: sign1.bool("riskAcknowledged") ?? false,
                                         previousResult: nil)
            let signOne = ms(t0)
            check(signOne <= 5_000, "1-input PSBT sign ≤ 5 s (\(signOne) ms)")
            var scans: [String] = []
            for (label, frames) in [("27 fountain", steps("O-QR-1-animated-shuffled", .scanAdd).compactMap { $0.request()?.str("frame") }),
                                    ("212 fountain", steps("T5-scan-fountain-large", .scanAdd).compactMap { $0.request()?.str("frame") }),
                                    ("200 BBQr", BILPublicSignerVectorReplay.syntheticBBQrFrames())] {
                t0 = BILMonotonicClock.millis()
                let h = try await e.openScan()
                var last = BILJSONObject()
                for f in frames { last = try await e.scanAdd(h, frame: f) }
                same(last.bool("complete"), true, "\(label) frames complete the request")
                scans.append("\(label)=\(ms(t0))")
            }
            let bbqr = BILPublicSignerVectorReplay.syntheticBBQrFrames()
            same(bbqr.count, 200, "200 synthetic BBQr frames")
            same(Set(bbqr.map { String($0.prefix(6)) }), ["B$HP5K"], "BBQr header: hex, PSBT, 200 parts")
            check(bbqr != bbqr.sorted(), "BBQr frames shuffled")
            print("engine: U7 macOS ms: pairing-load+capabilities=\(coldCaps) prepare=\(prepare) sign1=\(signOne) " + scans.joined(separator: " "))
            await e.releasePairingContext()

            section("hardening: concurrent operations stay isolated")
            let pairingGolden = vcase("T3-pairing-evm-standard-wallet").steps.first?.result ?? BILJSONObject()
            let legalSeed = vectors.phrases.first { $0.id == "legal" }?.seedHex ?? ""
            let results = try await withThrowingTaskGroup(of: (BILJSONObject, BILJSONObject).self) { group -> [(BILJSONObject, BILJSONObject)] in
                for i in 0..<6 {
                    group.addTask {
                        switch i % 3 {
                        case 0: return (try await e.derivePublicIndex(seedHex: ABANDON_SEED, tronScheme: nil, tronAddressCount: nil), indexAbandon)
                        case 1: return (try await e.derivePublicIndex(seedHex: legalSeed, tronScheme: nil, tronAddressCount: nil), indexLegal)
                        default: return (try await e.createPublicPairing(publicIndex: indexAbandon, chain: "evm", profile: "standard", outputMode: "wallet", index: 0), pairingGolden)
                        }
                    }
                }
                var out: [(BILJSONObject, BILJSONObject)] = []
                for try await item in group { out.append(item) }
                return out
            }
            same(results.count, 6, "six concurrent results")
            check(results.allSatisfy { $0.0 == $0.1 }, "every concurrent result equals its golden answer")
            await e.releasePairingContext()
            same(contextsAlive(), base, "hardening: no context left")
        }

        pubSummary("engine")
    }
}
