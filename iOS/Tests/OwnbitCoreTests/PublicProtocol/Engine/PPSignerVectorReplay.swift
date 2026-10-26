//  PPSignerVectorReplay.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Test support: the app's `Debug/BILPublicSignerVectorReplay.swift` (the golden-vector replay of the public-protocol
//  engine), unchanged but for this header and the test-target import. The app shared it between its harness and an
//  in-app DEBUG self-test; here only the engine suite uses it.
//
//  DEBUG only: the golden-vector replay of the public-protocol engine (S§13.1, §13.2 #2; design §3.4, R1 §7–§8), shared
//  by the macOS / simulator harness (scripts/public-protocol/tests/engine) and the in-app self-test (`pubvectors`,
//  BILPublicDebugEngine.swift), so both run the same code.
//
//  - `BILPublicSignerVectors` holds `vectors.json` in a helper JSContext (never an engine context): JSON.parse of the
//    file, the generator's `$fixture` substitution, then `JSON.stringify` of every request — this reproduces Node's
//    request bytes exactly (key order, number spelling).
//  - Raw pass: one fresh `BILPublicSignerJSContext` per (case, page), the request text dispatched as is, the UTF-8
//    SHA-256 of the response compared with `responseSha256`; the 4 `volatile` steps (BIP340 aux randomness at
//    `/result/psbt`) are compared outside the pointer and their signatures verified by the engine (accepted on a fresh
//    context, refused with SIGNATURE after one flipped byte). Expected: 923 steps, 919 SHA-equal, 4 verified, 0 fail.
//  - Production pass: every step the production API (`BILPublicSignerEngining`) can express, mapped like Android's
//    `BridgeReplay` (PublicSignerBundleTest.kt); iOS has no fragment-length parameter, so one more step is skipped:
//    expected 908 covered, 15 skipped. Results compare as JSON values (literal-exact numbers, map-equal objects);
//    refusals by code and engine message. With the concrete engine the SHA-256 of every request it sends is also
//    compared with the vector's request text (byte equality with Android / Node).
//
//  Operation names are mapped only through `BILPublicSignerOp(rawValue:)` (guard D-04 d); nothing here is logged.
//

#if DEBUG
import Foundation
import JavaScriptCore
import CryptoKit
@testable import OwnbitCore

/// The golden vectors file (format 1), parsed once in a helper JSContext.
final class BILPublicSignerVectors {

    struct Step {
        /// The vector's page number (consecutive steps with the same page share one context).
        let page: Int
        /// The vector's operation name (the unknown-operation refusal case included).
        let opName: String
        /// `JSON.stringify` of the request after `$fixture` substitution: what the engine received in Node.
        let requestText: String
        /// `JSON.stringify` of the golden response envelope.
        let responseText: String
        let responseSha256: String
        /// JSON pointers relative to the envelope (`/result/psbt`), empty for deterministic steps.
        let volatilePointers: [String]

        var op: BILPublicSignerOp? {
            return BILPublicSignerOp(rawValue: opName)
        }

        func request() -> BILJSONObject? {
            return BILStrictJSON.parseObject(requestText, options: .engine)
        }

        func response() -> BILJSONObject? {
            return BILStrictJSON.parseObject(responseText, options: .engine)
        }

        var ok: Bool {
            return response()?["ok"] == .bool(true)
        }

        var result: BILJSONObject? {
            return response()?.obj("result")
        }

        var error: (code: String, message: String)? {
            guard let e = response()?.obj("error"), let code = e.str("code"), let message = e.str("message") else { return nil }
            return (code: code, message: message)
        }
    }

    struct Case {
        let id: String
        let group: String
        let steps: [Step]

        /// Step indexes grouped by consecutive page.
        var pages: [[Int]] {
            var out: [[Int]] = []
            for (i, step) in steps.enumerated() {
                if let last = out.last?.last, steps[last].page == step.page {
                    out[out.count - 1].append(i)
                } else {
                    out.append([i])
                }
            }
            return out
        }

        func firstStep(_ op: BILPublicSignerOp) -> Step? {
            return steps.first { $0.op == op }
        }
    }

    struct LoadError: Error, CustomStringConvertible {
        let what: String
        var description: String { return "BILPublicSignerVectors: " + what }
    }

    let cases: [Case]
    /// `$fixture` objects replaced while building the request texts (generator: 154).
    let substitutions: Int
    /// `summary` and `engine` of the file.
    let summary: BILJSONObject
    let engineInfo: BILJSONObject
    /// The public test phrases (`id`, phrase, BIP39 seed hex).
    let phrases: [(id: String, phrase: String, seedHex: String)]
    private let fixtureTexts: [String: String]

    private static let helperScript = """
    (function (raw) {
        'use strict';
        var V = JSON.parse(raw);
        var substitutions = 0;
        function rf(value) {
            if (Array.isArray(value)) return value.map(rf);
            if (value && typeof value === 'object') {
                if (Object.keys(value).length === 1 && typeof value.$fixture === 'string') {
                    if (!Object.prototype.hasOwnProperty.call(V.fixtures, value.$fixture)) throw new Error('unknown fixture');
                    substitutions++;
                    return V.fixtures[value.$fixture];
                }
                var out = {};
                Object.keys(value).forEach(function (k) { out[k] = rf(value[k]); });
                return out;
            }
            return value;
        }
        var cases = V.cases.map(function (c) {
            return [String(c.id), String(c.group), c.steps.map(function (s) {
                return [s.page, String(s.request.operation), JSON.stringify(rf(s.request)), JSON.stringify(s.response),
                        String(s.responseSha256), (s.volatile || []).map(String)];
            })];
        });
        var fixtures = [];
        Object.keys(V.fixtures).forEach(function (n) { fixtures.push([n, JSON.stringify(V.fixtures[n])]); });
        var phrases = (V.mnemonics || []).map(function (m) { return [String(m.id), String(m.mnemonic), String(m.seedHex)]; });
        return [cases, substitutions, fixtures, JSON.stringify(V.summary || {}), JSON.stringify(V.engine || {}), phrases];
    })
    """

    init(vectorsJSON: String) throws {
        guard let helper = JSContext() else { throw LoadError(what: "no helper context") }
        var failed = false
        helper.exceptionHandler = { _, _ in failed = true }
        guard let function = helper.evaluateScript(BILPublicSignerVectors.helperScript), !failed,
              let value = function.call(withArguments: [vectorsJSON]), !failed,
              let parts = value.toArray(), parts.count == 6,
              let rawCases = parts[0] as? [Any], let subs = (parts[1] as? NSNumber)?.intValue,
              let rawFixtures = parts[2] as? [Any], let summaryText = parts[3] as? String, let engineText = parts[4] as? String,
              let rawPhrases = parts[5] as? [Any],
              let summary = BILStrictJSON.parseObject(summaryText, options: .engine),
              let engineInfo = BILStrictJSON.parseObject(engineText, options: .engine) else {
            throw LoadError(what: "not a vectors file")
        }
        var cases: [Case] = []
        cases.reserveCapacity(rawCases.count)
        for rc in rawCases {
            guard let c = rc as? [Any], c.count == 3, let id = c[0] as? String, let group = c[1] as? String,
                  let rawSteps = c[2] as? [Any] else { throw LoadError(what: "bad case") }
            var steps: [Step] = []
            for rs in rawSteps {
                guard let s = rs as? [Any], s.count == 6, let page = (s[0] as? NSNumber)?.intValue, let opName = s[1] as? String,
                      let request = s[2] as? String, let response = s[3] as? String, let sha = s[4] as? String,
                      let pointers = s[5] as? [String] else { throw LoadError(what: "bad step in " + id) }
                steps.append(Step(page: page, opName: opName, requestText: request, responseText: response,
                                  responseSha256: sha, volatilePointers: pointers))
            }
            cases.append(Case(id: id, group: group, steps: steps))
        }
        var fixtureTexts: [String: String] = [:]
        for rf in rawFixtures {
            guard let pair = rf as? [String], pair.count == 2 else { throw LoadError(what: "bad fixture") }
            fixtureTexts[pair[0]] = pair[1]
        }
        var phrases: [(id: String, phrase: String, seedHex: String)] = []
        for rp in rawPhrases {
            guard let row = rp as? [String], row.count == 3 else { throw LoadError(what: "bad phrase row") }
            phrases.append((id: row[0], phrase: row[1], seedHex: row[2]))
        }
        self.cases = cases
        self.substitutions = subs
        self.summary = summary
        self.engineInfo = engineInfo
        self.phrases = phrases
        self.fixtureTexts = fixtureTexts
    }

    var stepCount: Int {
        return cases.reduce(0) { $0 + $1.steps.count }
    }

    /// Distinct (case, page) contexts of the raw pass.
    var pageCount: Int {
        return cases.reduce(0) { $0 + $1.pages.count }
    }

    func caseNamed(_ id: String) -> Case? {
        return cases.first { $0.id == id }
    }

    /// `fixtures[name]` (e.g. `publicIndex.abandon`).
    func fixture(_ name: String) -> BILJSONObject? {
        guard let text = fixtureTexts[name] else { return nil }
        return BILStrictJSON.parseObject(text, options: .engine)
    }

    var fixtureNames: [String] {
        return fixtureTexts.keys.sorted()
    }
}

/// Counts of one replay pass.
struct BILPublicSignerReplayReport {
    var steps = 0, shaEqual = 0, volatileVerified = 0, covered = 0
    var skipped: [String] = []
    var failures: [String] = []
    /// Additive (WP7): engine contexts of the raw pass, requests whose SHA-256 was compared with the vector request
    /// text (production pass with the concrete engine) and the ones that differed, wall time.
    var contexts = 0
    var requestTextChecked = 0
    var requestTextDiffers: [String] = []
    var seconds: Double = 0
}

enum BILPublicSignerVectorReplay {

    /// Engine contexts created / released in this process (`BILPublicSignerJSContext` DEBUG counters), for callers
    /// outside the engine boundary (guard rule 11).
    static var contextCounts: (created: Int, released: Int) {
        return (created: BILPublicSignerJSContext.created, released: BILPublicSignerJSContext.released)
    }

    // MARK: Raw pass

    /// Raw byte-exact replay (R1 §7.3) on fresh contexts of `source`. Synchronous; run it on the thread under test.
    static func runRaw(vectors: BILPublicSignerVectors, source: String, sourceURL: URL) -> BILPublicSignerReplayReport {
        var report = BILPublicSignerReplayReport()
        let started = BILMonotonicClock.millis()
        for c in vectors.cases {
            for page in c.pages {
                autoreleasepool {
                    guard let context = try? BILPublicSignerJSContext(source: source, sourceURL: sourceURL) else {
                        report.failures.append(c.id + ": context")
                        return
                    }
                    report.contexts += 1
                    for i in page {
                        let step = c.steps[i]
                        report.steps += 1
                        let label = c.id + "#" + String(i) + " " + step.opName
                        guard let raw = try? context.dispatchText(step.requestText) else {
                            report.failures.append(label + ": dispatch")
                            continue
                        }
                        if step.volatilePointers.isEmpty {
                            if sha256Hex(raw) == step.responseSha256 {
                                report.shaEqual += 1
                            } else {
                                let equal = BILStrictJSON.parse(raw, options: .engine) == BILStrictJSON.parse(step.responseText, options: .engine)
                                report.failures.append(label + ": sha differs (" + (equal ? "deep-equal" : "different JSON") + ")")
                            }
                        } else if let why = verifyVolatileRaw(step: step, raw: raw, source: source, sourceURL: sourceURL) {
                            report.failures.append(label + ": " + why)
                        } else {
                            report.volatileVerified += 1
                        }
                    }
                }
            }
        }
        report.seconds = Double(BILMonotonicClock.millis() - started) / 1000
        return report
    }

    /// (a) same `ok`, (b) equal outside the pointers, (c) only one 64-byte window of the PSBT differs, (d) the engine
    /// accepts the signed PSBT on a fresh context, (e) one flipped byte → `SIGNATURE`.
    private static func verifyVolatileRaw(step: BILPublicSignerVectors.Step, raw: String, source: String, sourceURL: URL) -> String? {
        guard let actual = BILStrictJSON.parseObject(raw, options: .engine), let expected = step.response() else { return "unparsable" }
        guard actual["ok"] == expected["ok"] else { return "ok differs" }
        var a = BILJSONValue.object(actual), e = BILJSONValue.object(expected)
        for pointer in step.volatilePointers {
            a = without(a, pointer: pointer)
            e = without(e, pointer: pointer)
        }
        guard a == e else { return "differs outside the volatile leaves" }
        guard let signed = actual.obj("result")?.str("psbt"), let golden = expected.obj("result")?.str("psbt"),
              let plain = step.request()?.obj("request") else { return "no psbt" }
        let window: (signed: [UInt8], first: Int)
        switch signatureWindow(signed: signed, golden: golden) {
        case .failure(let why): return why
        case .success(let w): window = w
        }
        func reviewOutcome(_ psbt: String) -> BILJSONObject? {
            var request = plain
            request.remove("transport")
            request.set("psbt", .string(psbt))
            let text = BILStrictJSON.serialize(BILJSONObject([("operation", .string(BILPublicSignerOp.review.rawValue)),
                                                              ("request", .object(request))]))
            guard let context = try? BILPublicSignerJSContext(source: source, sourceURL: sourceURL),
                  let answer = try? context.dispatchText(text) else { return nil }
            return BILStrictJSON.parseObject(answer, options: .engine)
        }
        guard let accepted = reviewOutcome(signed), accepted["ok"] == .bool(true),
              accepted.obj("result")?.str("chain") == "bitcoin" else { return "signed PSBT not accepted" }
        var tampered = window.signed
        tampered[window.first] ^= 0x01
        guard let refused = reviewOutcome(Data(tampered).base64EncodedString()), refused["ok"] == .bool(false),
              refused.obj("error")?.str("code") == "SIGNATURE" else { return "flipped signature not refused" }
        return nil
    }

    // MARK: Production pass

    /// Android `BridgeReplay` through `engine` (R1 §7.4). With the concrete `BILPublicSignerEngine` the request texts
    /// are compared too (by SHA-256; the texts are never kept).
    static func runProduction(vectors: BILPublicSignerVectors, engine: BILPublicSignerEngining) async -> BILPublicSignerReplayReport {
        let run = ProductionRun(engine: engine)
        let started = BILMonotonicClock.millis()
        if let concrete = run.concrete {
            await concrete.debugRecordRequests(true)
        }
        for c in vectors.cases {
            await run.run(c)
        }
        if let concrete = run.concrete {
            await concrete.debugRecordRequests(false)
        }
        run.report.seconds = Double(BILMonotonicClock.millis() - started) / 1000
        return run.report
    }

    /// The production pass of one case (e.g. the timed "full EVM flow" of `pubperf`); request texts are not compared.
    static func runProductionCase(_ c: BILPublicSignerVectors.Case, engine: BILPublicSignerEngining) async -> BILPublicSignerReplayReport {
        let run = ProductionRun(engine: engine, comparesRequests: false)
        let started = BILMonotonicClock.millis()
        await run.run(c)
        run.report.seconds = Double(BILMonotonicClock.millis() - started) / 1000
        return run.report
    }

    /// The steps the production API cannot express (Android `PublicSignerJsBridgeTest.EXPECTED_SKIPS`, 14) plus the
    /// golden `encodeResponse` step with a fragment length (iOS has no such parameter, design D-03): 15.
    static let expectedProductionSkips: [String] = [
        "T3-pairing-default-name-evm:" + BILPublicSignerOp.createPublicPairing.rawValue,
        "T3-pairing-default-name-bitcoin:" + BILPublicSignerOp.createPublicPairing.rawValue,
        "T3-pairing-default-name-solana:" + BILPublicSignerOp.createPublicPairing.rawValue,
        "T3-pairing-animated-bitcoin:" + BILPublicSignerOp.createPublicPairing.rawValue,
        "T3-pairing-animated-evm:" + BILPublicSignerOp.createPublicPairing.rawValue,
        "T3-pairing-invalid:" + BILPublicSignerOp.createPublicPairing.rawValue,
        "T3-pairing-invalid:" + BILPublicSignerOp.createPublicPairing.rawValue,
        "T3b-addresses-invalid:" + BILPublicSignerOp.derivePublicAddresses.rawValue,
        "T3b-addresses-invalid:" + BILPublicSignerOp.derivePublicAddresses.rawValue,
        "T5-no-session:" + BILPublicSignerOp.scanAdd.rawValue,
        "T9-tron-type-url-bom:" + BILPublicSignerOp.resolveSigningPlan.rawValue + " after a review refusal",
        "T9-unknown-operation:noSuchOperation",
        "O-BTC-1-prevout-mismatch:" + BILPublicSignerOp.resolveSigningPlan.rawValue + " after a review refusal",
        "O-SOL-2-lookup-table:" + BILPublicSignerOp.resolveSigningPlan.rawValue + " after a review refusal",
        "T8-flow-evm-eip1559-animated-response:" + BILPublicSignerOp.encodeResponse.rawValue,
    ]

    /// BIP340 key-path signatures are verified instead of compared (Android `verifyTaprootSignatures`): only one 64-byte
    /// window differs from the Node PSBT, the engine accepts the signed PSBT as a plain request (`transport` removed),
    /// and refuses it with `SIGNATURE` after one flipped byte. nil = verified, else the reason.
    static func verifyTaproot(request: BILJSONObject, signed: String, golden: String, engine: BILPublicSignerEngining) async -> String? {
        let window: (signed: [UInt8], first: Int)
        switch signatureWindow(signed: signed, golden: golden) {
        case .failure(let why): return why
        case .success(let w): window = w
        }
        var plain = request
        plain.remove("transport")
        let wallets = [BILJSONObject([("localWalletId", .string("verify"))])]
        var signedRequest = plain
        signedRequest.set("psbt", .string(signed))
        guard let accepted = try? await engine.reviewAndResolve(request: signedRequest, wallets: wallets),
              accepted.review.str("chain") == "bitcoin" else { return "signed PSBT not accepted" }
        var tampered = window.signed
        tampered[window.first] ^= 0x01
        var tamperedRequest = plain
        tamperedRequest.set("psbt", .string(Data(tampered).base64EncodedString()))
        do {
            _ = try await engine.reviewAndResolve(request: tamperedRequest, wallets: wallets)
            return "flipped signature not refused"
        } catch let refusal as BILPublicSignerRefusal {
            return refusal.code == "SIGNATURE" ? nil : "flipped signature refused with " + refusal.code
        } catch {
            return "flipped signature: " + String(describing: type(of: error))
        }
    }

    // MARK: Helpers

    /// Synthetic BBQr `H` (hex) frames of a PSBT-shaped payload (Android `PubVectors.bbqrFrames`: byte i = (i·31 + 7) & 0xff,
    /// first 5 bytes `70 73 62 74 ff`, upper-case hex, `B$HP` + total + index in 2-digit base 36), deterministically shuffled
    /// (the U7 "200 BBQr frames" timing; the scan session only assembles them and checks the magic).
    static func syntheticBBQrFrames(frames: Int = 200, bytesPerFrame: Int = 50) -> [String] {
        var payload = (0..<(frames * bytesPerFrame)).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 7) }
        let magic: [UInt8] = [0x70, 0x73, 0x62, 0x74, 0xff]
        for (k, b) in magic.enumerated() { payload[k] = b }
        let hex = payload.map { String(format: "%02X", $0) }.joined()
        let units = Array(hex.utf8)
        let chunk = bytesPerFrame * 2
        func base36(_ n: Int) -> String {
            let s = String(n, radix: 36).uppercased()
            return s.count >= 2 ? s : String(repeating: "0", count: 2 - s.count) + s
        }
        var out = (0..<frames).map { i -> String in
            "B$HP" + base36(frames) + base36(i) + String(decoding: units[(i * chunk)..<((i + 1) * chunk)], as: UTF8.self)
        }
        var state: UInt64 = 7
        for i in stride(from: out.count - 1, to: 0, by: -1) {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let j = Int((state >> 33) % UInt64(i + 1))
            out.swapAt(i, j)
        }
        return out
    }

    static func sha256Hex(_ text: String) -> String {
        return SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// `value` without the leaf at `pointer` (RFC 6901, object members only).
    static func without(_ value: BILJSONValue, pointer: String) -> BILJSONValue {
        let path = pointer.split(separator: "/", omittingEmptySubsequences: false).dropFirst().map {
            $0.replacingOccurrences(of: "~1", with: "/").replacingOccurrences(of: "~0", with: "~")
        }
        return removing(value, Array(path))
    }

    private static func removing(_ value: BILJSONValue, _ path: [String]) -> BILJSONValue {
        guard let key = path.first, var object = value.objectValue else { return value }
        if path.count == 1 {
            object.remove(key)
        } else if let child = object[key] {
            object.set(key, removing(child, Array(path.dropFirst())))
        }
        return .object(object)
    }

    private enum Window {
        case success((signed: [UInt8], first: Int))
        case failure(String)
    }

    private static func signatureWindow(signed: String, golden: String) -> Window {
        guard let a = Data(base64Encoded: signed).map({ [UInt8]($0) }), let b = Data(base64Encoded: golden).map({ [UInt8]($0) }) else {
            return .failure("psbt not base64")
        }
        guard a.count == b.count else { return .failure("psbt size differs") }
        let differing = (0..<a.count).filter { a[$0] != b[$0] }
        guard let first = differing.first, let last = differing.last else { return .failure("no fresh signature") }
        guard last - first < 64 else { return .failure("more than one signature window differs") }
        return .success((signed: a, first: first))
    }

    /// State of one production pass (Android `BridgeReplay`).
    private final class ProductionRun {
        let engine: BILPublicSignerEngining
        let concrete: BILPublicSignerEngine?
        var report = BILPublicSignerReplayReport()

        init(engine: BILPublicSignerEngining, comparesRequests: Bool = true) {
            self.engine = engine
            self.concrete = comparesRequests ? engine as? BILPublicSignerEngine : nil
        }

        private static let pairingOps: Set<BILPublicSignerOp> = [.capabilities, .derivePublicAddresses, .createPublicPairing]
        private static let singleOps: Set<BILPublicSignerOp> = [.derivePublicIndex, .signPlanTask, .encodeResponse, .decodePayload]
        /// The vectors' unknown-operation refusal case (Android `BridgeReplay` skips exactly it and `scanAdd`; a page of
        /// any other unknown operation is "not mapped").
        private static let unknownOperation = "noSuchOperation"

        func run(_ c: BILPublicSignerVectors.Case) async {
            for page in c.pages {
                let steps = page.map { c.steps[$0] }
                let ops = steps.map { $0.op }
                if ops.allSatisfy({ $0.map { ProductionRun.pairingOps.contains($0) } ?? false }) {
                    for (k, step) in steps.enumerated() {
                        await pairing(c, page[k], step)
                    }
                } else if ops.first == .some(.scanBegin), ops.dropFirst().allSatisfy({ $0 == .some(.scanAdd) }) {
                    await scan(c, page, steps)
                } else if ops == [.review, .resolveSigningPlan] || ops == [.review] || ops == [.resolveSigningPlan] {
                    await reviewPage(c, page, steps)
                } else if ops.count == 1, let op = ops[0], ProductionRun.singleOps.contains(op) {
                    await single(c, page[0], steps[0], op)
                } else if ops.indices.allSatisfy({ ops[$0] == .some(.scanAdd) || steps[$0].opName == ProductionRun.unknownOperation }) {
                    for step in steps {
                        report.skipped.append(c.id + ":" + step.opName)
                    }
                } else {
                    report.failures.append(c.id + ": page pattern not mapped")
                }
            }
        }

        private func pairing(_ c: BILPublicSignerVectors.Case, _ i: Int, _ step: BILPublicSignerVectors.Step) async {
            guard let r = step.request() else { return fail(c, i, step, "request") }
            switch step.op {
            case .some(.capabilities):
                await outcome(c, i, step, sends: [step]) { try await self.engine.capabilities() }
            case .some(.derivePublicAddresses):
                guard let start = r.int("start"), let count = r.int("count") else {
                    report.skipped.append(c.id + ":" + step.opName)
                    return
                }
                guard let index = r.obj("publicIndex"), let chain = r.str("chain") else { return fail(c, i, step, "params") }
                await outcome(c, i, step, sends: [step]) {
                    try await self.engine.derivePublicAddresses(publicIndex: index, chain: chain, profile: r.str("profile"),
                                                               start: start, count: count)
                }
            case .some(.createPublicPairing):
                guard let index = r.obj("publicIndex"), let chain = r.str("chain") else { return fail(c, i, step, "params") }
                let at = r.int("index") ?? 0
                let expressible = r.str("deviceName") == BILPublicSignerEngine.deviceName && !r.contains("fragmentLength")
                    && r.contains("index") == (chain == "tron" || at != 0)
                guard expressible else {
                    report.skipped.append(c.id + ":" + step.opName)
                    return
                }
                await outcome(c, i, step, sends: [step]) {
                    try await self.engine.createPublicPairing(publicIndex: index, chain: chain, profile: r.str("profile"),
                                                             outputMode: r.str("outputMode"), index: at)
                }
            default:
                fail(c, i, step, "not a pairing operation")
            }
        }

        private func scan(_ c: BILPublicSignerVectors.Case, _ page: [Int], _ steps: [BILPublicSignerVectors.Step]) async {
            let handle: BILPublicScanHandle
            report.covered += 1
            do {
                handle = try await engine.openScan()
                await checkSends([steps[0]], c, page[0])
            } catch {
                return fail(c, page[0], steps[0], "openScan threw " + String(describing: type(of: error)))
            }
            var ended = false
            for (k, step) in steps.enumerated().dropFirst() {
                if ended {
                    report.skipped.append(c.id + ":" + step.opName + " after the session ended")
                    continue
                }
                guard let frame = step.request()?.str("frame") else {
                    fail(c, page[k], step, "frame")
                    continue
                }
                await outcome(c, page[k], step, sends: [step]) { try await self.engine.scanAdd(handle, frame: frame) }
                ended = !step.ok || step.result?["complete"] == .bool(true)
            }
            await engine.closeScan(handle)
        }

        private func reviewPage(_ c: BILPublicSignerVectors.Case, _ page: [Int], _ steps: [BILPublicSignerVectors.Step]) async {
            let reviewIndex = steps.firstIndex { $0.op == .review }
            let resolveIndex = steps.firstIndex { $0.op == .resolveSigningPlan }
            let review = reviewIndex.map { steps[$0] }
            let resolve = resolveIndex.map { steps[$0] }
            guard let request = (review ?? resolve)?.request()?.obj("request") else {
                return fail(c, page[0], steps[0], "request")
            }
            if let review = review, let ri = reviewIndex, !review.ok {
                if let resolve = resolve {
                    report.skipped.append(c.id + ":" + resolve.opName + " after a review refusal")
                }
                await outcome(c, page[ri], review, sends: [review]) {
                    try await self.engine.reviewAndResolve(request: request, wallets: []).plan
                }
                return
            }
            guard let resolveStep = resolve, let si = resolveIndex else {
                report.skipped.append(c.id + ":" + (review?.opName ?? "?") + " without resolve")
                return
            }
            guard let wallets = resolveStep.request()?.arr("wallets")?.compactMap({ $0.objectValue }) else {
                return fail(c, page[si], resolveStep, "wallets")
            }
            let sends: [BILPublicSignerVectors.Step?] = [review, resolveStep]
            if !resolveStep.ok {
                await outcome(c, page[si], resolveStep, sends: sends) {
                    try await self.engine.reviewAndResolve(request: request, wallets: wallets).plan
                }
                return
            }
            do {
                let both = try await engine.reviewAndResolve(request: request, wallets: wallets)
                await checkSends(sends, c, page[si])
                if let review = review, let ri = reviewIndex {
                    report.covered += 1
                    if review.result != both.review { fail(c, page[ri], review, "review differs") }
                }
                report.covered += 1
                if resolveStep.result != both.plan { fail(c, page[si], resolveStep, "plan differs") }
            } catch {
                report.covered += (review == nil ? 1 : 2)
                fail(c, page[si], resolveStep, "threw " + describe(error))
            }
        }

        private func single(_ c: BILPublicSignerVectors.Case, _ i: Int, _ step: BILPublicSignerVectors.Step,
                            _ op: BILPublicSignerOp) async {
            guard let r = step.request() else { return fail(c, i, step, "request") }
            switch op {
            case .derivePublicIndex:
                if let index = r.obj("publicIndex") {
                    guard let scheme = r.str("tronScheme") else { return fail(c, i, step, "tronScheme") }
                    await outcome(c, i, step, sends: [step]) {
                        try await self.engine.refreshPublicIndex(publicIndex: index, tronScheme: scheme, tronAddressCount: r.int("tronAddressCount"))
                    }
                } else {
                    guard let seedHex = r.str("seed") else { return fail(c, i, step, "params") }
                    await outcome(c, i, step, sends: [step]) {
                        try await self.engine.derivePublicIndex(seedHex: seedHex, tronScheme: r.str("tronScheme"),
                                                               tronAddressCount: r.int("tronAddressCount"))
                    }
                }
            case .signPlanTask:
                guard let request = r.obj("request"), let plan = r.obj("plan"), let taskId = r.str("taskId"),
                      let seedHex = r.str("seed"), let ack = r.bool("riskAcknowledged") else { return fail(c, i, step, "params") }
                await outcome(c, i, step, sends: [step]) {
                    try await self.engine.signPlanTask(request: request, plan: plan, taskId: taskId, seedHex: seedHex,
                                                       riskAcknowledged: ack, previousResult: r.obj("previousResult"))
                }
            case .encodeResponse:
                if r.contains("fragmentLength") {
                    report.skipped.append(c.id + ":" + step.opName)
                    return
                }
                guard let request = r.obj("request"), let result = r.obj("result") else { return fail(c, i, step, "params") }
                await outcome(c, i, step, sends: [step]) { try await self.engine.encodeResponse(request: request, result: result) }
            case .decodePayload:
                guard let payload = r.str("payload") else { return fail(c, i, step, "params") }
                await outcome(c, i, step, sends: [step]) { try await self.engine.decodePayload(payload) }
            default:
                fail(c, i, step, "not a single operation")
            }
        }

        /// One covered step: the golden result (volatile: outside the pointers + signature check) or the golden refusal.
        private func outcome(_ c: BILPublicSignerVectors.Case, _ i: Int, _ step: BILPublicSignerVectors.Step,
                             sends: [BILPublicSignerVectors.Step?], _ call: () async throws -> BILJSONObject) async {
            report.covered += 1
            if step.ok {
                let result: BILJSONObject
                do {
                    result = try await call()
                } catch {
                    await checkSends(sends, c, i)
                    return fail(c, i, step, "threw " + describe(error))
                }
                await checkSends(sends, c, i)
                guard let expected = step.result else { return fail(c, i, step, "golden result") }
                if step.volatilePointers.isEmpty {
                    if result != expected { fail(c, i, step, "result differs") }
                    return
                }
                var a = BILJSONValue.object(result), e = BILJSONValue.object(expected)
                for pointer in step.volatilePointers {
                    let relative = pointer.hasPrefix("/result") ? String(pointer.dropFirst("/result".count)) : pointer
                    a = BILPublicSignerVectorReplay.without(a, pointer: relative)
                    e = BILPublicSignerVectorReplay.without(e, pointer: relative)
                }
                guard a == e else { return fail(c, i, step, "differs outside the volatile leaves") }
                guard let signed = result.str("psbt"), let golden = expected.str("psbt"),
                      let request = step.request()?.obj("request") else { return fail(c, i, step, "psbt") }
                if let why = await BILPublicSignerVectorReplay.verifyTaproot(request: request, signed: signed, golden: golden, engine: engine) {
                    fail(c, i, step, why)
                } else {
                    report.volatileVerified += 1
                }
                if let concrete = concrete {
                    _ = await concrete.debugTakeRequests()          // the verification's own requests
                }
                return
            }
            guard let golden = step.error else { return fail(c, i, step, "golden error") }
            do {
                _ = try await call()
                await checkSends(sends, c, i)
                fail(c, i, step, "expected " + golden.code)
            } catch let refusal as BILPublicSignerRefusal {
                await checkSends(sends, c, i)
                if refusal.code != golden.code || refusal.engineMessage != BILPublicSignerRefusal.bound(golden.message) {
                    fail(c, i, step, "refused with " + refusal.code + " instead of " + golden.code)
                }
            } catch {
                await checkSends(sends, c, i)
                fail(c, i, step, "threw " + describe(error) + " instead of " + golden.code)
            }
        }

        /// Compares the SHA-256 of the requests the concrete engine sent with the vector request texts (nil = a request
        /// the vector page does not record, e.g. the review of a resolve-only page).
        private func checkSends(_ expected: [BILPublicSignerVectors.Step?], _ c: BILPublicSignerVectors.Case, _ i: Int) async {
            guard let concrete = concrete else { return }
            let sent = await concrete.debugTakeRequests()
            let label = c.id + "#" + String(i)
            guard sent.count == expected.count else {
                report.requestTextDiffers.append(label + " (" + String(sent.count) + " requests sent)")
                return
            }
            for (k, step) in expected.enumerated() {
                guard let step = step else { continue }
                report.requestTextChecked += 1
                if sent[k].op != step.op || sent[k].sha256 != BILPublicSignerVectorReplay.sha256Hex(step.requestText) {
                    report.requestTextDiffers.append(label + " " + step.opName)
                }
            }
        }

        private func fail(_ c: BILPublicSignerVectors.Case, _ i: Int, _ step: BILPublicSignerVectors.Step, _ why: String) {
            report.failures.append(c.id + "#" + String(i) + " " + step.opName + ": " + why)
        }

        private func describe(_ error: Error) -> String {
            if let refusal = error as? BILPublicSignerRefusal { return refusal.code }
            if let failure = error as? BILPublicSignerFailure { return failure.code }
            return String(describing: type(of: error))
        }
    }
}
#endif
