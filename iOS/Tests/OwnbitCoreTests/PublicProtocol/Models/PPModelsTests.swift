//  PPModelsTests.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Port of the app harness suite `scripts/public-protocol/tests/models` (main.swift) to XCTest.
//
//  main.swift — models suite (WP8): the engine-result models and coordinator contract types of
//  wallet-ios-core/Modules/PublicProtocol/Model, compiled with the real Core (WP1), the two Domain files they use (WP5)
//  and the pure Security Center D43 models. Ports Android `PST:model/PublicSignerModelsTest.kt` (models part; Android's
//  `engine-samples.json` is not copied — the same checks run on the pinned golden vectors `vectors.json`) plus the WP8
//  block of the design (§4 Wave 2): every review / plan / sign result / response / pairing payload of the vectors
//  parses (from the compact serialization of the vector response, as the engine sends it), unknown wires fail closed,
//  malformed shapes throw with Android's `what`, format lines, request info, policy result, states, outcomes,
//  observation token, the setup-sheet Prepare texts (lead addendum A4).
//  Prints "models-core: N ok, M FAIL" (tests/models/run.sh adds the iOS typecheck and the source rules).
//

import Foundation
import XCTest
@testable import OwnbitCore

/// The suite namespace (harness helpers are its static members).
enum PPModelsSuite: PPSuite {}

final class PPModelsTests: XCTestCase {
    func testModels() throws {
        try ppRunSuite("models") { try PPModelsSuite.run() }
    }
}

extension PPModelsSuite {

    // MARK: - Helpers

    /// A JSON object from test text in which "`" stands for a double quote (paths keep their apostrophes).
    static func jq(_ text: String) -> BILJSONObject {
        let json = text.replacingOccurrences(of: "`", with: "\"")
        guard let o = BILStrictJSON.parseObject(json, options: .engine) else {
            print("FAIL test JSON does not parse: \(json.prefix(120))")
            exit(2)
        }
        return o
    }

    /// The `what` of the `BILMalformedEngineResult` thrown by `body`, "<no throw>" or "<TypeName>" for another error.
    static func malformedWhat(_ body: () throws -> Void) -> String {
        do {
            try body()
            return "<no throw>"
        } catch let e as BILMalformedEngineResult {
            return e.what
        } catch {
            return "<\(type(of: error))>"
        }
    }

    /// A copy of `o` with keys set (`.some(v)`) or removed (nil), positions kept.
    static func edited(_ o: BILJSONObject, _ changes: [(String, BILJSONValue?)]) -> BILJSONObject {
        var c = o
        for (k, v) in changes {
            if let v = v { c.set(k, v) } else { c.remove(k) }
        }
        return c
    }

    static func s(_ text: String) -> BILJSONValue { return .string(text) }
    static func utf16(_ text: String?) -> [UInt16] { return text.map { Array($0.utf16) } ?? [] }
    static let hex64a = String(repeating: "a", count: 64)
    static let hex64zero = String(repeating: "0", count: 64)

    /// Runs the main queue until every block enqueued before this call has run (the main run loop serves it).
    static func drainMainQueue(timeout: TimeInterval = 10) {
        var done = false
        DispatchQueue.main.async { done = true }
        let deadline = Date().addingTimeInterval(timeout)
        while !done && Date() < deadline {
            _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        t(done, "main queue drained")
    }

    /// Kotlin `filter { it.isNotEmpty() }.distinct()` written independently of the implementation (UTF-16 units).
    static func kotlinDistinctNonEmpty(_ items: [String]) -> [String] {
        var out = [String]()
        for s in items where !s.utf16.isEmpty && !out.contains(where: { Array($0.utf16) == Array(s.utf16) }) {
            out.append(s)
        }
        return out
    }

    /// `==` is exact and every listed variant (one field changed each) is unequal to `base`.
    static func exactEquality<T: Equatable>(_ name: String, base: T, copy: T, canonical: [T], variants: [T]) {
        t(base == copy, "\(name): equal copy")
        for (i, c) in canonical.enumerated() {
            t(base != c, "\(name): canonically equal text #\(i) is not equal (code units)")
        }
        for (i, v) in variants.enumerated() {
            t(base != v && v != base, "\(name): field variant #\(i) takes part in ==")
        }
    }
    /// "é" precomposed / decomposed: canonically equivalent, different code units.
    static let ePre = "\u{00E9}", eDec = "e\u{0301}"

    // MARK: - 1. Enums and wires (fail closed, exact)

    static let base = BILPublicReviewDisplay.fromEngine(jq("{`action`:`Send`,`amount`:`0.0009`,`symbol`:`BTC`,`headline`:`h`,`counterpartyLabel`:`To`,"
        + "`counterparty`:`bc1q…`,`fee`:`0.00001 BTC`,`note`:`Change returns to your wallet`,`tokenId`:`5`,`give`:[`x`],`assetContract`:`0x1`}"))
    struct VStep {
        let caseId: String
        let index: Int
        let op: String
        let request: BILJSONObject
        let result: BILJSONObject?     // the result of an ok:true envelope, read back from its compact serialization
        let rawResult: BILJSONObject?  // as in the file
    }
    static var allSteps = [VStep]()
    static func vectorPlan(_ caseId: String) -> BILPublicPlan? {
        return allSteps.first { $0.caseId == caseId && $0.op == "resolveSigningPlan" && $0.result != nil }?.result.flatMap { try? BILPublicPlan.fromEngine($0) }
    }
    static func expectedSummary(type: String?, bytes: Int, bbqr: String?) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US")
        f.numberStyle = .decimal
        f.usesGroupingSeparator = true
        let b = (f.string(from: NSNumber(value: bytes)) ?? "?") + " B"
        switch type {
        case "bbqr-psbt"?: return "BBQr · PSBT (\(bbqr == "H" ? "hex" : "Base32")) · \(b)"
        case "psbt-base64"?: return "PSBT Base64 · \(b)"
        case "psbt-hex"?: return "PSBT hex · \(b)"
        case nil, "address"?: return "UTF-8 · \(b)"
        case "tronlink"?: return "TronLink · JSON · \(b)"
        default: return "ur:\(type!) · CBOR · \(b)"
        }
    }
    static func checkPretty(_ view: BILPublicPayloadView, _ payload: BILJSONObject?, _ tag: String) {
        guard view.format == .json else { return }
        guard let payload = payload else { t(false, "json payload object \(tag)"); return }
        eq(view.text, BILStrictJSON.prettySorted(.object(payload)), "pretty sorted JSON \(tag)")
        t(BILStrictJSON.parseObject(view.text, options: .engine) == payload, "pretty text parses back to the payload \(tag)")
        t(view.text.hasPrefix("{\n  \"") || payload.isEmpty, "2-space indent \(tag)")
    }
    static let evmReady = allSteps.first { step in
        guard step.op == "resolveSigningPlan", let r = step.result, r.str("status") == "ready", r.str("chain") == "evm" else { return false }
        return (r.arr("tasks") ?? []).count == 1
    }?.result ?? BILJSONObject()
    static let oneTask = evmReady.arr("tasks")?.first?.objectValue ?? BILJSONObject()
    static func planWhat(_ o: BILJSONObject) -> String { return malformedWhat { _ = try BILPublicPlan.fromEngine(o) } }
    static func withTask(_ changes: [(String, BILJSONValue?)]) -> BILJSONObject {
        return edited(evmReady, [("tasks", .array([.object(edited(oneTask, changes))]))])
    }
    static func resultWhat(_ o: BILJSONObject) -> String { return malformedWhat { _ = try BILPublicSignResult.fromEngine(o) } }
    static func responseWhat(_ o: BILJSONObject) -> String { return malformedWhat { _ = try BILPublicResponseQr.fromEngine(o) } }
    static func line(_ type: String?, _ bytes: Int, _ bbqr: String? = nil) -> String {
        return BILPublicPayloadView(format: .json, text: "{}", byteCount: bytes, qrType: type, bbqrEncoding: bbqr).formatSummary
    }
    static let answer = jq("{`b`:`é`,`a`:1}")
    static let none = BILPublicRequestInfo.of(jq("{`chain`:`EVM`,`transport`:`ur`}"))
    static func asset(_ f: Int, _ e: String = ePre) -> BILReviewAsset {
        // f = the field to change (0…8), -1 = none; e = the "é" spelling used in that field.
        func v(_ i: Int, _ base: String) -> String { return f == i ? base + e : base + ePre }
        return BILReviewAsset(chainFamily: v(0, "evm"), chainId: f == 1 && e == "" ? nil : v(1, "1"), assetAddress: v(2, "0x"), name: v(3, "n"),
                              symbol: v(4, "s"), decimals: f == 5 ? 7 : 6, tokenProgram: f == 6 && e == "" ? nil : v(6, "p"),
                              rawAmount: f == 7 && e == "" ? nil : v(7, "1"), displayAmount: f == 8 && e == "" ? nil : v(8, "2"))
    }
    static func display(_ f: Int, _ e: String? = ePre) -> BILPublicReviewDisplay {
        func v(_ i: Int, _ base: String) -> String? { return f == i ? e.map { base + $0 } : base + ePre }
        func lines(_ i: Int) -> BILFlowLines { return f == i ? BILFlowLines(lines: [e.map { "l" + $0 } ?? "l"], more: 0) : BILFlowLines(lines: ["l" + ePre], more: 0) }
        return BILPublicReviewDisplay(action: v(0, "a") ?? "a", amount: v(1, "1"), symbol: v(2, "s"), headline: v(3, "h"),
                                      counterpartyLabel: v(4, "cl"), counterparty: v(5, "c"), fee: v(6, "f"), note: v(7, "n"),
                                      assetKind: f == 8 ? .multiToken : .nft, assetContract: v(9, "0x"), assetContractLabel: v(10, "acl"),
                                      tokenId: v(11, "7"), give: lines(12), receive: lines(13), others: lines(14))
    }
    static func signError(_ f: Int, _ e: String = ePre) -> BILPublicSignError {
        return BILPublicSignError("PublicProtocol.err.x" + (f == 0 ? e : ePre), args: f == 1 && e == "" ? [] : [.text("a" + (f == 1 ? e : ePre))],
                                  code: f == 2 && e == "" ? nil : "C" + (f == 2 ? e : ePre),
                                  engineMessage: f == 3 && e == "" ? nil : "m" + (f == 3 ? e : ePre))
    }
    static var deinitCalls = 0
    static func dropToken() {
        let token = BILPublicObservation { deinitCalls += 1 }
        _ = token.isCancelled
    }
    static var afterCancelCalls = 0
    static func cancelThenDrop() {
        let token = BILPublicObservation { afterCancelCalls += 1 }
        token.cancel()
    }
    @MainActor final class ProbeCoordinator: BILPublicSignCoordinating {
        var states: [String: BILPublicSignState] = [:]
        func prepare(_ input: BILPublicInput) async throws -> String {
            if case .pasted = input { throw BILPublicPrepareError(error: BILPublicSignerErrors.unexpected) }
            states["r1"] = .resolving(BILPublicRequestInfo(chain: nil, transportType: nil, origin: nil))
            return "r1"
        }
        func state(_ requestId: String) -> BILPublicSignState { return states[requestId] ?? .gone }
        func observe(_ requestId: String, _ onChange: @escaping (BILPublicSignState) -> Void) -> BILPublicObservation {
            onChange(state(requestId))
            return BILPublicObservation { }
        }
        func resolveAgain(_ requestId: String) async {}
        func setupThenResolve(_ requestId: String, walletId: String, password: String) async -> BILPublicPrepareResult { return .notEligible }
        func signTask(_ requestId: String, taskId: String, password: String, riskAcknowledged: Bool) async -> BILPublicTaskOutcome { return .gone }
        func answer(_ requestId: String) -> BILPublicResponseQr? { return nil }
        func discard(_ requestId: String) { states[requestId] = nil }
    }

    /// The harness main.swift (nonisolated top-level code, as in the harness).
    static func run() throws {
        section("enums")
        eq(BILDecodeStatus.allCases.map { $0.rawValue }, ["fullyDecoded", "partiallyDecoded", "opaque"], "decode wires")
        eq(BILDecodeStatus.fromWire("fullyDecoded"), .fullyDecoded, "decode fully")
        eq(BILDecodeStatus.fromWire("partiallyDecoded"), .partiallyDecoded, "decode partial")
        eq(BILDecodeStatus.fromWire("somethingNew"), .opaque, "unknown decode → opaque")
        eq(BILDecodeStatus.fromWire(nil), .opaque, "missing decode → opaque")
        eq(BILDecodeStatus.fromWire("FullyDecoded"), .opaque, "decode wire is case-sensitive")
        eq(BILDecodeStatus.fromWire(" fullyDecoded"), .opaque, "decode wire is not trimmed")
        eq(BILRiskLevel.allCases.map { $0.rawValue }, ["normal", "warning", "high"], "risk wires")
        eq(BILRiskLevel.fromWire("normal"), .normal, "risk normal")
        eq(BILRiskLevel.fromWire("warning"), .warning, "risk warning")
        eq(BILRiskLevel.fromWire(nil), .high, "missing risk → high")
        eq(BILRiskLevel.fromWire("low"), .high, "unknown risk → high")
        eq(BILRiskLevel.fromWire("Normal"), .high, "risk wire is case-sensitive")
        eq(BILPlanStatus.allCases.map { $0.rawValue }, ["ready", "noMatch", "missingSigner", "ambiguous", "setupRequired", "invalid"], "status wires")
        eq(BILPlanStatus.fromWire("brandNew"), .invalid, "unknown status → invalid")
        eq(BILPlanStatus.fromWire(nil), .invalid, "missing status → invalid")
        eq(BILPlanStatus.fromWire("Ready"), .invalid, "status wire is case-sensitive")
        eq(BILPlanStatus.fromWire("setupRequired"), .setupRequired, "status setupRequired")
        eq(BILReviewAssetKind.allCases.map { $0.rawValue }, ["nft", "nftOrToken", "multiToken", "nftOrder"], "asset kind wires")
        eq(BILReviewAssetKind.fromWire("rwa"), nil, "unknown asset kind → nil")
        eq(BILReviewAssetKind.fromWire("multiToken"), .multiToken, "asset kind multiToken")
        eq(BILPublicPayloadView.Format.allCases.map { $0.rawValue }, ["json", "hex", "text"], "payload format wires")

        // MARK: - 2. Review fields

        section("review fields")
        let grouped = BILReviewField(index: 3, label: "Instruction 2 · Recipient", value: "v")
        eq(grouped.group, "Instruction 2", "group before the first \" · \"")
        eq(grouped.shortLabel, "Recipient", "short label after it")
        let twoSeparators = BILReviewField(index: 0, label: "A · B · C", value: "")
        eq(twoSeparators.group, "A", "split at the FIRST separator (group)")
        eq(twoSeparators.shortLabel, "B · C", "split at the FIRST separator (short label)")
        let plain = BILReviewField(index: 0, label: "Count", value: "3")
        eq(plain.group, nil, "no separator → no group")
        eq(plain.shortLabel, "Count", "no separator → the label")
        let edge = BILReviewField(index: 0, label: " · x", value: "")
        eq(edge.group, "", "separator at the start → empty group")
        eq(edge.shortLabel, "x", "separator at the start → short label")
        // U+0387 GREEK ANO TELEIA is canonically equal to U+00B7 for Swift / Foundation, but not for Kotlin's indexOf.
        let anoTeleia = "Instruction 2 \u{0387} Recipient"
        t("\u{0387}" == "\u{00B7}" && anoTeleia.range(of: " \u{00B7} ") != nil, "premise: Swift treats U+0387 as U+00B7")
        let ano = BILReviewField(index: 0, label: anoTeleia, value: "")
        eq(ano.group, nil, "U+0387 is not the group separator (code units)")
        eq(utf16(ano.shortLabel), utf16(anoTeleia), "U+0387 label kept whole")
        t(!BILPublicModelText.same("\u{0387}", "\u{00B7}") && BILPublicModelText.same("a\u{00B7}", "a\u{00B7}"), "model string equality is by code units")
        t(!BILPublicModelText.contains(["e\u{0301}"], "\u{00E9}"), "membership is by code units (é decomposed ≠ precomposed)")
        eq(BILPublicModelText.distinct(["\u{00E9}", "e\u{0301}", "\u{00E9}", ""]).count, 3, "distinct is by code units")
        t(BILPublicModelText.sameIgnoringASCIICase("ABCdef", "abcDEF") && !BILPublicModelText.sameIgnoringASCIICase("abc", "abcd")
          && !BILPublicModelText.sameIgnoringASCIICase("\u{212A}", "k") && !BILPublicModelText.sameIgnoringASCIICase("\u{00C4}", "\u{00E4}"), "ASCII case folding only")

        // MARK: - 3. Review: lenient texts, fail-closed statuses (Android "review texts are kept whole …")

        section("review lenient")
        let longValue = String(repeating: "x", count: 5000)
        let lenient = try! BILPublicReview.fromEngine(jq(
            "{`chain`:`solana`,`fields`:[{`label`:`Instruction 2 · Recipient`,`value`:`\(longValue)`},{`label`:`Count`,`value`:3},`not a field`],"
            + "`warnings`:[`w1`,`w2`],`decodeStatus`:`notKnown`}"))
        eq(lenient.fields.first?.value.utf16.count, 5000, "values are never cut")
        eq(lenient.fields.first?.group, "Instruction 2", "field group")
        eq(lenient.fields.first?.shortLabel, "Recipient", "field short label")
        eq(lenient.fields.count, 2, "a non-object field is skipped")
        eq(lenient.fields.count > 1 ? lenient.fields[1].value : "-", "3", "a number value reads as its JSON text")
        eq(lenient.fields.count > 1 ? lenient.fields[1].group : "-", nil, "no group")
        eq(lenient.warnings, ["w1", "w2"], "warnings kept in order")
        eq(lenient.decodeStatus, .opaque, "unknown decode status → opaque")
        eq(lenient.riskLevel, .high, "missing risk → high")
        t(lenient.requiresAcknowledgement, "opaque / high needs consent")
        t(!lenient.canSign, "missing canSign → false")
        eq(lenient.networkName, "Solana", "network name falls back to the chain brand")
        eq(lenient.display, nil, "no display")
        eq(lenient.asset, nil, "no asset")
        eq(lenient.network, nil, "no network")
        eq(lenient.title, "", "missing title → empty")
        eq(lenient.summary, "", "missing summary → empty")
        eq(lenient.requestHash, "", "missing requestHash → empty")
        eq(lenient.chain, .solana, "chain solana")
        eq(try! BILPublicReview.fromEngine(jq("{`chain`:`tron2`}")).chain, nil, "unknown chain → nil")
        eq(try! BILPublicReview.fromEngine(jq("{`chain`:`Bitcoin`}")).chain, nil, "chain wire is case-sensitive")
        eq(try! BILPublicReview.fromEngine(jq("{}")).networkName, "", "no network, no field, no chain → empty name")

        let odd = try! BILPublicReview.fromEngine(jq(
            "{`chain`:`evm`,`title`:`T`,`summary`:`S`,`requestHash`:`\(hex64a)`,`canSign`:true,`decodeStatus`:`partiallyDecoded`,`riskLevel`:`normal`,"
            + "`fields`:[{`label`:`A`,`value`:null},`x`,{`label`:`B`,`value`:{`k`:[1,true,`é/`]}},{`value`:1.50},{`label`:7,`value`:false},{`label`:`Network`,`value`:`Gnosis`}],"
            + "`warnings`:[`HIGH FEE: x`,5,null,{`a`:1}],`network`:{`chainId`:`100`}}"))
        eq(odd.fields.map { $0.index }, [0, 2, 3, 4, 5], "indexes keep the engine positions (a skipped element leaves a gap)")
        eq(odd.fields.map { $0.value }, ["", "{\"k\":[1,true,\"é/\"]}", "1.50", "false", "Gnosis"], "values: null → \"\", JSON text otherwise, literals kept")
        eq(odd.fields.map { $0.label }, ["A", "B", "", "", "Network"], "missing / non-string label → \"\"")
        eq(odd.warnings, ["HIGH FEE: x", "5", "", "{\"a\":1}"], "warnings read as display text")
        eq(odd.network, nil, "a network without a string name is dropped")
        eq(odd.networkName, "Gnosis", "network name from the \"Network\" field")
        t(odd.canSign && odd.title == "T" && odd.summary == "S" && odd.requestHash == hex64a, "texts read")
        t(odd.requiresAcknowledgement, "partially decoded needs consent")
        eq(odd.raw, jq("{`chain`:`evm`,`title`:`T`,`summary`:`S`,`requestHash`:`\(hex64a)`,`canSign`:true,`decodeStatus`:`partiallyDecoded`,`riskLevel`:`normal`,"
            + "`fields`:[{`label`:`A`,`value`:null},`x`,{`label`:`B`,`value`:{`k`:[1,true,`é/`]}},{`value`:1.50},{`label`:7,`value`:false},{`label`:`Network`,`value`:`Gnosis`}],"
            + "`warnings`:[`HIGH FEE: x`,5,null,{`a`:1}],`network`:{`chainId`:`100`}}"), "raw kept")
        let fine = try! BILPublicReview.fromEngine(jq("{`chain`:`evm`,`decodeStatus`:`fullyDecoded`,`riskLevel`:`warning`,`canSign`:`true`,"
            + "`network`:{`chainId`:`1`,`name`:`Ethereum`,`symbol`:`ETH`},`fields`:[{`label`:`Network`,`value`:`Other`}]}"))
        eq(fine.network, BILReviewNetwork(chainId: "1", name: "Ethereum", symbol: "ETH"), "network read")
        eq(fine.networkName, "Ethereum", "the engine network wins over the field")
        t(!fine.requiresAcknowledgement, "fully decoded + warning → no consent from the review alone")
        t(!fine.canSign, "canSign must be a JSON bool")
        t(try! BILPublicReview.fromEngine(jq("{`decodeStatus`:`fullyDecoded`,`riskLevel`:`high`}")).requiresAcknowledgement, "fully decoded + high needs consent")
        t(!(try! BILPublicReview.fromEngine(jq("{`decodeStatus`:`fullyDecoded`,`riskLevel`:`normal`}")).requiresAcknowledgement), "fully decoded + normal: no consent")
        t(try! BILPublicReview.fromEngine(jq("{`decodeStatus`:`partiallyDecoded`,`riskLevel`:`high`}")).requiresAcknowledgement, "partially decoded + high needs consent")
        let netNoId = try! BILPublicReview.fromEngine(jq("{`network`:{`name`:`Bitcoin`,`chainId`:1}}"))
        eq(netNoId.network, BILReviewNetwork(chainId: nil, name: "Bitcoin", symbol: nil), "non-string chainId → nil")
        let networkFieldExact = try! BILPublicReview.fromEngine(jq("{`chain`:`tron`,`fields`:[{`label`:`network`,`value`:`x`},{`label`:`Network `,`value`:`y`}]}"))
        eq(networkFieldExact.networkName, "TRON", "only the exact label \"Network\" names the network")

        section("review asset")
        let assetJSON = "`chainFamily`:`evm`,`chainId`:`1`,`assetAddress`:`0xdac17f958d2ee523a2206206994597c13d831ec7`,`name`:`Tether USD`,`symbol`:`USDT`,`decimals`:6"
        let withAsset = try! BILPublicReview.fromEngine(jq("{`asset`:{\(assetJSON),`rawAmount`:`1000000`,`displayAmount`:`1`,`tokenProgram`:5}}"))
        eq(withAsset.asset, BILReviewAsset(chainFamily: "evm", chainId: "1", assetAddress: "0xdac17f958d2ee523a2206206994597c13d831ec7", name: "Tether USD",
                                           symbol: "USDT", decimals: 6, tokenProgram: nil, rawAmount: "1000000", displayAmount: "1"), "asset read")
        for (key, value) in [("chainFamily", "null"), ("assetAddress", "1"), ("name", "null"), ("symbol", "[]"), ("decimals", "`6`"), ("decimals", "6.0"),
                             ("decimals", "4294967296")] {
            let broken = jq("{`asset`:{\(assetJSON)}}").obj("asset").map { edited($0, [(key, BILStrictJSON.parse(value.replacingOccurrences(of: "`", with: "\"")))]) }!
            eq(try! BILPublicReview.fromEngine(jq("{}").appending("asset", .object(broken))).asset, nil, "asset dropped whole when \(key) = \(value)")
        }
        var noChainId = jq("{`asset`:{\(assetJSON)}}").obj("asset")!
        noChainId.remove("chainId")
        eq(BILReviewAsset.fromEngine(noChainId)?.chainId, nil, "asset chainId optional")
        t(BILReviewAsset.fromEngine(noChainId) != nil, "asset without chainId kept")

        // MARK: - 4. Display (Android "NFT display keys are bounded and read only with a known kind")

        section("display")
        let longLine = String(repeating: "1 ", count: 200) + "to 0xRecipient (unrecognised recipient)"
        let give40 = (1...40).map { "`item \($0)`" }.joined(separator: ",")
        let nftRaw = jq("{`action`:`Approve All NFTs`,`headline`:`Seaport order for NFT #123`,`assetKind`:`nftOrder`,`assetContract`:`0xabc`,`tokenId`:`123`,"
            + "`give`:[\(give40)],`receive`:[`\(longLine)`,`  `],`others`:[`a`,5],`assetContractLabel`:`\(String(repeating: "c", count: 301))`}")
        let nft = BILPublicReviewDisplay.fromEngine(nftRaw)
        t(nft != nil, "NFT display read")
        if let display = nft {
            eq(display.assetKind, .nftOrder, "kind")
            eq(display.give.lines.count, 31, "more than 32 lines keep 31")
            eq(display.give.more, 9, "and count the rest")
            eq(display.give.lines.first, "item 1", "first line kept")
            eq(display.receive.lines.count, 1, "blank lines are dropped")
            eq(display.receive.lines.first?.utf16.count, 300, "an over-long line is cut to 300")
            t(display.receive.lines.first.map { $0.hasSuffix("(unrecognised recipient)") && $0.contains("\u{2026}") } == true, "cut in the middle with …")
            t(display.others.isEmpty, "a list with a non-string is ignored whole")
            eq(display.assetContractLabel, nil, "an over-long identifier is dropped, never cut")
            eq(display.summaryTokenId, nil, "the headline already shows #123")
            t(display.showsAssetBox, "asset box (contract)")
            eq(display.flowSections.map { $0.kind }, [.give, .receive], "flow sections in order, empty ones left out")
            eq(display.flowSections.first?.lines.more, 9, "flow section carries its more count")
            t(display.isNft, "isNft")
            eq(display.action, "Approve All NFTs", "action")
            eq(display.headline, "Seaport order for NFT #123", "headline")
        }
        let unknownKind = BILPublicReviewDisplay.fromEngine(edited(nftRaw, [("assetKind", s("rwa"))]))
        t(unknownKind != nil, "unknown kind: display kept")
        if let display = unknownKind {
            eq(display.assetKind, nil, "unknown kind: no kind")
            eq(display.assetContract, nil, "unknown kind: no contract")
            eq(display.tokenId, nil, "unknown kind: no token id")
            t(display.give.isEmpty && display.flowSections.isEmpty, "unknown kind: no lists")
            eq(display.headline, "Seaport order for NFT #123", "unknown kind: the original keys stay")
            t(!display.isNft && !display.showsAssetBox && display.summaryTokenId == nil, "unknown kind: not an NFT")
        }
        eq(BILPublicReviewDisplay.fromEngine(jq("{`action`:1}")), nil, "non-string action → no display")
        eq(BILPublicReviewDisplay.fromEngine(jq("{`amount`:`1`}")), nil, "missing action → no display")
        eq(BILPublicReviewDisplay.fromEngine(nil), nil, "absent display")
        eq(base, BILPublicReviewDisplay(action: "Send", amount: "0.0009", symbol: "BTC", headline: "h", counterpartyLabel: "To", counterparty: "bc1q…",
                                        fee: "0.00001 BTC", note: "Change returns to your wallet"), "base keys read; NFT keys only with a kind")
        eq(BILPublicReviewDisplay.fromEngine(jq("{`action`:`Send`,`amount`:1,`fee`:null}")), BILPublicReviewDisplay(action: "Send"), "non-string base keys read as absent")
        let nftNoContract = BILPublicReviewDisplay.fromEngine(jq("{`action`:`Send NFT`,`assetKind`:`nft`,`tokenId`:`1234`,`amount`:`NFT #12345`}"))
        eq(nftNoContract?.summaryTokenId, "1234", "#12345 does not show token 1234 → shown separately")
        t(nftNoContract?.showsAssetBox == true, "asset box (token id only)")
        let nftShown = BILPublicReviewDisplay.fromEngine(jq("{`action`:`Send NFT`,`assetKind`:`nft`,`tokenId`:`1234`,`amount`:`#12345 and #1234.`}"))
        eq(nftShown?.summaryTokenId, nil, "#1234. shows token 1234")
        t(nftShown?.showsAssetBox == false, "no asset box without contract and separate id")
        let notNft = BILPublicReviewDisplay(action: "Send", tokenId: "7")
        eq(notNft.summaryTokenId, nil, "summary token id only for NFT reviews")
        t(notNft.flowSections.isEmpty && !notNft.showsAssetBox, "no NFT parts without a kind")
        // Built directly (not through fromEngine): NFT parts present, no kind → still no flow sections and no asset box.
        let kindless = BILPublicReviewDisplay(action: "Send", assetContract: "0x1", tokenId: "7", give: BILFlowLines(lines: ["a"], more: 0),
                                              receive: BILFlowLines(lines: ["b"], more: 1), others: BILFlowLines(lines: ["c"], more: 0))
        t(kindless.flowSections.isEmpty, "no flow sections without a kind (direct construction)")
        t(!kindless.showsAssetBox, "no asset box without a kind (direct construction)")
        let kinded = BILPublicReviewDisplay(action: "Send", assetKind: .nftOrToken, assetContract: "0x1", give: BILFlowLines(lines: ["a"], more: 0),
                                            others: BILFlowLines(lines: ["c"], more: 2))
        eq(kinded.flowSections.map { $0.kind }, [.give, .others], "with a kind: the non-empty lists")
        eq(kinded.flowSections.map { $0.lines }, [BILFlowLines(lines: ["a"], more: 0), BILFlowLines(lines: ["c"], more: 2)], "… with their lines")
        t(kinded.showsAssetBox && kinded.summaryTokenId == nil, "with a kind: contract alone shows the asset box")
        t(BILPublicReviewDisplay(action: "Send", assetKind: .nft, tokenId: "9").showsAssetBox, "with a kind: a separate token id alone shows the asset box")
        t(!BILPublicReviewDisplay(action: "Send", assetKind: .nft).showsAssetBox, "with a kind but neither contract nor id: no asset box")

        section("display bounds")
        t(BILPublicReviewDisplay.textShowsTokenId("Send NFT #1234", "1234"), "#1234 at the end")
        t(!BILPublicReviewDisplay.textShowsTokenId("Send NFT #12345", "1234"), "#12345 is another id")
        t(BILPublicReviewDisplay.textShowsTokenId("#12345 and #1234.", "1234"), "second occurrence")
        t(!BILPublicReviewDisplay.textShowsTokenId("Give 2 items", ""), "empty id")
        t(!BILPublicReviewDisplay.textShowsTokenId("token 1234", "1234"), "needs the #")
        t(BILPublicReviewDisplay.textShowsTokenId("#1234x", "1234"), "followed by a non-digit")
        t(BILPublicReviewDisplay.textShowsTokenId("#1234\u{0661}", "1234"), "followed by a non-ASCII digit counts as shown (Kotlin '0'..'9')")
        let emojiCut = BILPublicReviewDisplay.boundedLine(String(repeating: "😀", count: 200))
        t(emojiCut.utf16.count <= BILPublicReviewDisplay.maxStringLength, "emoji line within 300 units")
        t(!emojiCut.unicodeScalars.contains("\u{FFFD}") && emojiCut.hasPrefix("😀") && emojiCut.hasSuffix("😀"), "no surrogate pair split at either cut")
        eq(emojiCut.utf16.count, 148 + 1 + 150, "emoji cut: 74 pairs + … + 75 pairs")
        let asciiCut = BILPublicReviewDisplay.boundedLine(String(repeating: "a", count: 200) + String(repeating: "b", count: 200))
        eq(asciiCut, String(repeating: "a", count: 149) + "\u{2026}" + String(repeating: "b", count: 150), "ASCII cut: 149 + … + 150")
        let exact300 = String(repeating: "z", count: 300)
        eq(BILPublicReviewDisplay.boundedLine(exact300), exact300, "300 units are kept")
        eq(BILPublicReviewDisplay.boundedValue(s(exact300)), exact300, "a 300-unit identifier is kept")
        eq(BILPublicReviewDisplay.boundedValue(s(exact300 + "z")), nil, "a 301-unit identifier is dropped")
        eq(BILPublicReviewDisplay.boundedValue(s(String(repeating: "😀", count: 151))), nil, "length counts UTF-16 units (302)")
        eq(BILPublicReviewDisplay.boundedValue(s(" \u{2028}\t")), nil, "Kotlin-blank identifier dropped")
        eq(BILPublicReviewDisplay.boundedValue(s("\u{200B}")), "\u{200B}", "U+200B is not Kotlin whitespace")
        eq(BILPublicReviewDisplay.boundedValue(s("\u{0085}")), "\u{0085}", "U+0085 is not Kotlin whitespace")
        eq(BILPublicReviewDisplay.boundedValue(.number("5")), nil, "a number is not an identifier")
        eq(BILPublicReviewDisplay.boundedValue(nil), nil, "absent identifier")
        let lines32 = BILJSONValue.array((1...32).map { s("l\($0)") })
        eq(BILPublicReviewDisplay.boundedLines(lines32), BILFlowLines(lines: (1...32).map { "l\($0)" }, more: 0), "32 lines kept")
        let lines33 = BILJSONValue.array((1...33).map { s("l\($0)") })
        eq(BILPublicReviewDisplay.boundedLines(lines33).lines.count, 31, "33 lines keep 31")
        eq(BILPublicReviewDisplay.boundedLines(lines33).more, 2, "and count 2")
        let blanks33 = BILJSONValue.array((1...32).map { s("l\($0)") } + [s(" ")])
        eq(BILPublicReviewDisplay.boundedLines(blanks33).more, 0, "blank lines are dropped before counting")
        eq(BILPublicReviewDisplay.boundedLines(.object(BILJSONObject())), BILFlowLines.empty, "not an array → empty")
        eq(BILPublicReviewDisplay.boundedLines(.array([s("a"), .null])), BILFlowLines.empty, "a null element → empty")
        t(BILFlowLines.empty.isEmpty && BILFlowLines.empty.more == 0, "empty lines")

        // MARK: - 5. The golden vectors

        section("vectors")
        let vectors: BILJSONObject = {
            guard let o = BILStrictJSON.parseObject(fixtureText("vectors.json"), options: .engine) else {
                print("FAIL vectors.json does not parse with BILStrictJSON (.engine)")
                exit(2)
            }
            return o
        }()

        for element in vectors.arr("cases") ?? [] {
            guard let c = element.objectValue, let id = c.str("id") else { continue }
            for (i, stepValue) in (c.arr("steps") ?? []).enumerated() {
                guard let step = stepValue.objectValue, let request = step.obj("request"), let response = step.obj("response") else { continue }
                // The engine answers with one compact JSON text; the coordinator reads it with BILStrictJSON (.engine, depth 64).
                let envelope = BILStrictJSON.parseObject(BILStrictJSON.serialize(response), options: .engine)
                let ok = envelope?.bool("ok") == true
                allSteps.append(VStep(caseId: id, index: i, op: request.str("operation") ?? "", request: request,
                                      result: ok ? envelope?.obj("result") : nil, rawResult: response.obj("result")))
            }
        }
        eq(allSteps.count, 923, "923 vector steps")
        eq((vectors.arr("cases") ?? []).count, 169, "169 vector cases")

        let lowerHex = { (v: String?) -> Bool in BILEngineJSON.isLowerHex64(v) }

        section("vectors: review")
        var reviewCount = 0
        for step in allSteps where step.op == "review" {
            guard let result = step.result else { continue }
            reviewCount += 1
            let tag = "\(step.caseId)#\(step.index)"
            guard let review = try? BILPublicReview.fromEngine(result) else { t(false, "review parses \(tag)"); continue }
            let requestChain = step.request.obj("request").flatMap { BILPsChain.fromWire($0.str("chain")) }
            t(review.chain != nil && review.chain == requestChain, "review chain = request chain \(tag)")
            t(BILEngineJSON.isHex(review.requestHash, bytes: 32), "review requestHash 64 hex \(tag)")
            t(!review.fields.isEmpty, "review has fields \(tag)")
            let rawFields = result.arr("fields") ?? []
            t(rawFields.allSatisfy { $0.objectValue != nil } && review.fields.count == rawFields.count, "every field read \(tag)")
            let sameRows = zip(review.fields, rawFields).allSatisfy { field, raw in
                guard let o = raw.objectValue else { return false }
                return BILPublicModelText.same(field.label, o.str("label") ?? "\u{0}") && BILPublicModelText.same(field.value, o["value"]?.displayText ?? "\u{0}")
            }
            t(sameRows, "field labels / values byte-equal \(tag)")
            eq(review.warnings.count, (result.arr("warnings") ?? []).count, "every warning kept \(tag)")
            t(BILDecodeStatus(rawValue: result.str("decodeStatus") ?? "") == review.decodeStatus, "decode status is a known wire \(tag)")
            t(BILRiskLevel(rawValue: result.str("riskLevel") ?? "") == review.riskLevel, "risk level is a known wire \(tag)")
            t(review.canSign, "engine canSign \(tag)")
            t(review.title.isEmpty == false, "review title \(tag)")
            if result.obj("display")?.str("action") != nil { t(review.display?.action == result.obj("display")?.str("action"), "display read \(tag)") }
            if result.obj("network")?.str("name") != nil { t(review.network?.name == result.obj("network")?.str("name"), "network read \(tag)") }
            if result.obj("asset") != nil { t(review.asset != nil, "asset read \(tag)") }
            t(review.raw == result, "review raw kept \(tag)")
            t(step.rawResult.map { BILStrictJSON.serialize($0) == BILStrictJSON.serialize(result) } == true, "compact round trip byte-equal \(tag)")
            eq(BILPublicRequestInfo.of(step.request.obj("request") ?? BILJSONObject()).chain, review.chain, "request info chain \(tag)")
        }
        eq(reviewCount, 88, "88 ok review steps")

        section("vectors: plans")
        var planCount = 0, readyCount = 0, solanaSlots = 0
        for step in allSteps where step.op == "resolveSigningPlan" {
            guard let result = step.result else { continue }
            planCount += 1
            let tag = "\(step.caseId)#\(step.index)"
            let plan: BILPublicPlan
            do { plan = try BILPublicPlan.fromEngine(result) } catch { t(false, "plan parses \(tag): \(error)"); continue }
            eq(plan.status.rawValue, result.str("status") ?? "-", "status wire \(tag)")
            t(plan.raw == result && BILStrictJSON.serialize(plan.raw) == BILStrictJSON.serialize(result), "plan raw passed back unchanged \(tag)")
            if plan.isReady {
                readyCount += 1
                t(lowerHex(plan.requestHash) && lowerHex(plan.planHash) && lowerHex(plan.signingBytesDigest), "ready hashes 64 lower hex \(tag)")
                t(plan.chain != nil && plan.review?.chain == plan.chain, "review of the plan's chain \(tag)")
                t(plan.review.map { BILPublicModelText.sameIgnoringASCIICase($0.requestHash, plan.requestHash ?? "") } == true, "review hash = plan hash \(tag)")
                t(!plan.tasks.isEmpty && plan.tasks.count <= BILPublicPlan.maxTasks, "1…64 tasks \(tag)")
                t(plan.message == nil, "no message on a ready plan \(tag)")
                eq(plan.protocolProfile, result.str("protocolProfile"), "protocol profile \(tag)")
                eq(plan.payloadDigest, result.str("payloadDigest"), "payload digest \(tag)")
                for task in plan.tasks {
                    t(lowerHex(task.walletKeyId), "task walletKeyId lower hex \(tag)")
                    t(task.chain == plan.chain && task.paths.count == task.publicKeys.count && !task.paths.isEmpty, "task shape \(tag)")
                    t(BILPublicModelText.sameIgnoringASCIICase(task.signingBytesDigest, plan.signingBytesDigest ?? ""), "task digest \(tag)")
                    t(plan.task(task.id) == task, "task lookup \(tag)")
                    t(!task.localWalletId.isEmpty && !task.signatureAlgorithm.isEmpty, "task wallet / algorithm \(tag)")
                    t(task.raw.arr("targets").map { $0.count == task.targets.count } == true, "targets are objects \(tag)")
                    t(!task.targetFingerprints.isEmpty && task.targetFingerprints.allSatisfy { $0 == $0.lowercased() && $0.utf16.count == 8 }, "target fingerprints \(tag)")
                    if plan.chain == .bitcoin { t(!task.inputs.isEmpty, "BTC task names its inputs \(tag)") } else { t(task.inputs.isEmpty, "no inputs off BTC \(tag)") }
                    eq(task.signerSlot, task.firstTarget?.int("signerSlot"), "signer slot = targets[0].signerSlot \(tag)")
                    eq(task.displayPaths, kotlinDistinctNonEmpty(task.paths), "display paths = distinct non-empty paths \(tag)")
                    eq(task.displayAddresses, kotlinDistinctNonEmpty(task.addresses), "display addresses = distinct non-empty addresses \(tag)")
                    if plan.chain != .solana { t(task.signerSlot == nil, "signer slot only on Solana \(tag)") }
                    if plan.chain == .solana && task.signerSlot != nil { solanaSlots += 1 }
                }
                eq(plan.walletIds.count, Set(plan.tasks.map { $0.localWalletId }).count, "wallet ids distinct \(tag)")
            } else {
                t(plan.tasks.isEmpty && plan.planHash == nil && plan.signingBytesDigest == nil && plan.protocolProfile == nil, "non-ready plan carries no tasks / hashes \(tag)")
                eq(plan.message, result.str("message"), "status message kept \(tag)")
                eq(plan.chain, plan.review?.chain, "non-ready chain from its review \(tag)")
                eq(plan.requestHash, plan.review.flatMap { $0.requestHash.isEmpty ? nil : $0.requestHash }, "non-ready request hash from its review \(tag)")
            }
        }
        eq(planCount, 96, "96 ok resolveSigningPlan steps")
        eq(readyCount, 86, "86 ready plans")
        eq(solanaSlots, 6, "6 Solana transaction tasks carry a signer slot")

        // Android `a ready plan reads its tasks and review` (its `plan_ready` sample = this personal-sign plan of the vectors,
        // wallet id "wallet-abandon" instead of "w1").
        section("vectors: Android ready plan")
        let personal = vectorPlan("T8-flow-evm-personal")
        t(personal?.isReady == true && personal?.tasks.count == 1, "the personal-sign plan is ready with one task")
        if let plan = personal, let task = plan.tasks.first, let review = plan.review {
            eq(plan.chain, .evm, "chain")
            eq(plan.protocolProfile, "eth-sign-request", "protocol profile")
            eq(task.localWalletId, "wallet-abandon", "task wallet")
            eq(task.walletKeyId, "95f7c3fcf6b598ef252e4ee3857f84e712d3264719314d8ccc1bbeceed2d9a34", "wallet key id")
            eq(task.displayPaths, ["m/44'/60'/0'/0/0"], "display paths")
            eq(task.displayAddresses, ["0x9858EfFD232B4033E47d90003D41EC34EcaEda94"], "display addresses")
            eq(task.signatureAlgorithm, "ECDSA secp256k1", "signature algorithm")
            eq(task.signerSlot, nil, "no signer slot")
            eq(plan.walletIds, ["wallet-abandon"], "wallet ids")
            t(plan.task(task.id) == task, "task lookup")
            eq(review.title, "Sign Ethereum message", "review title")
            eq(review.decodeStatus, .fullyDecoded, "fully decoded")
            eq(review.riskLevel, .high, "high risk")
            t(review.requiresAcknowledgement, "high risk needs consent")
            eq(review.network, BILReviewNetwork(chainId: "1", name: "Ethereum", symbol: "ETH"), "network")
            eq(review.networkName, "Ethereum", "network name")
            eq(review.fields.map { $0.index }, [0, 1, 2, 3, 4], "five fields in engine order")
            eq(review.fields.last?.label, "Exact message bytes", "last field")
            eq(review.warnings.count, 1, "one warning")
            eq(review.display?.action, "Sign Message", "display action")
        }
        // Vector tasks with repeated / empty targets: the wallet card shows each path / address once, empty ones not at all.
        let repeated = vectorPlan("T8-flow-bitcoin-psbt-base64-text-too-large")?.tasks.first
        eq(repeated?.paths.count, 5, "five targets on one path")
        eq(repeated?.displayPaths, ["m/84'/0'/0'/0/0"], "repeated path shown once")
        eq(repeated?.displayAddresses, ["bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu"], "repeated address shown once")
        let noAddress = vectorPlan("T6-plan-btc-two-local-bip48-cosigners-without-derivations")?.tasks.first
        eq(noAddress?.addresses, [""], "a multisig target without an address")
        eq(noAddress?.displayAddresses, [], "empty addresses are not shown")
        eq(noAddress?.displayPaths, ["m/48'/0'/0'/2'/0/0"], "its path is")

        section("vectors: sign results")
        var resultCount = 0
        for step in allSteps where step.op == "signPlanTask" {
            guard let result = step.result else { continue }
            resultCount += 1
            let tag = "\(step.caseId)#\(step.index)"
            let signed: BILPublicSignResult
            do { signed = try BILPublicSignResult.fromEngine(result) } catch { t(false, "sign result parses \(tag): \(error)"); continue }
            t(lowerHex(signed.requestHash) && lowerHex(signed.planHash), "result hashes lower hex \(tag)")
            eq(signed.completedTaskIds.last, signed.taskId, "this task last \(tag)")
            t(signed.raw == result, "result raw kept \(tag)")
            // The result belongs to the plan the request passed (the coordinator's check, R5 §1.6 step 6).
            guard let requestPlan = step.request.obj("plan").flatMap({ try? BILPublicPlan.fromEngine($0) }) else { t(false, "request plan parses \(tag)"); continue }
            t(signed.chain == requestPlan.chain && signed.requestHash == requestPlan.requestHash && signed.planHash == requestPlan.planHash,
              "result belongs to the request's plan \(tag)")
            t(step.request.str("taskId").map { BILPublicModelText.same($0, signed.taskId) } == true && requestPlan.task(signed.taskId) != nil, "result task = request task \(tag)")
        }
        eq(resultCount, 80, "80 ok signPlanTask steps")

        /// The format line the table of R6 §6.2 gives for `type` (independent of the implementation's branches).

        /// The view's JSON text is valid JSON equal to the payload object, keys sorted at every level, 2-space indent.

        section("vectors: responses")
        var responseCount = 0
        var responseTypes = Set<String>()
        var sawAnimated = false
        for step in allSteps where step.op == "encodeResponse" {
            guard let result = step.result else { continue }
            responseCount += 1
            let tag = "\(step.caseId)#\(step.index)"
            let qr: BILPublicResponseQr
            do { qr = try BILPublicResponseQr.fromEngine(result) } catch { t(false, "response parses \(tag): \(error)"); continue }
            responseTypes.insert(qr.type)
            eq(qr.type, result.str("type") ?? "-", "response type \(tag)")
            eq(qr.frames, (result.strings("frames") ?? []).filter { !$0.isEmpty }, "response frames \(tag)")
            t(!qr.signedTransaction && !qr.isTronLink && !qr.isPaged, "engine answers are not TronLink \(tag)")
            eq(qr.isPsbt, ["crypto-psbt", "psbt", "bbqr-psbt", "psbt-base64", "psbt-hex"].contains(qr.type), "isPsbt \(tag)")
            eq(qr.isAnimated, qr.frames.count > 1, "isAnimated \(tag)")
            if qr.isAnimated { sawAnimated = true }
            eq(qr.text, qr.frames.joined(separator: "\n"), "copy text \(tag)")
            guard let view = qr.payload else { t(false, "response payload view \(tag)"); continue }
            eq(view.byteCount, result.int("payloadBytes") ?? -1, "payload bytes \(tag)")
            eq(view.qrType, qr.type, "payload type \(tag)")
            eq(view.format.rawValue, result.str("payloadFormat") ?? "-", "payload format \(tag)")
            eq(view.isPsbt, qr.isPsbt, "payload isPsbt \(tag)")
            eq(view.formatSummary, expectedSummary(type: view.qrType, bytes: view.byteCount, bbqr: view.bbqrEncoding), "format line \(tag)")
            let first = qr.frames.first ?? ""
            eq(view.bbqrEncoding, first.hasPrefix("B$") && first.utf16.count > 2 ? String(first[first.index(first.startIndex, offsetBy: 2)]) : nil, "bbqr encoding \(tag)")
            checkPretty(view, result.obj("payload"), tag)
            if view.format != .json { eq(view.text, result.str("payload") ?? "-", "hex / text payload as is \(tag)") }
        }
        eq(responseCount, 65, "65 ok encodeResponse steps")
        t(sawAnimated, "an animated response exists in the vectors")
        t(responseTypes.contains("bbqr-psbt") && responseTypes.contains("psbt-base64") && responseTypes.contains("eth-signature"), "response types covered: \(responseTypes.sorted())")

        section("vectors: pairing payloads")
        var pairingCount = 0
        for step in allSteps where step.op == "createPublicPairing" {
            guard let result = step.result else { continue }
            pairingCount += 1
            let tag = "\(step.caseId)#\(step.index)"
            guard let view = BILPublicPayloadView.fromEngine(result) else { t(false, "pairing payload view \(tag)"); continue }
            eq(view.byteCount, result.int("payloadBytes") ?? -1, "pairing payload bytes \(tag)")
            eq(view.qrType, result.str("type"), "pairing payload type \(tag)")
            eq(view.formatSummary, expectedSummary(type: view.qrType, bytes: view.byteCount, bbqr: view.bbqrEncoding), "pairing format line \(tag)")
            eq(view.isUr, !["address", "bbqr-psbt", "psbt-base64", "psbt-hex", "tronlink"].contains(result.str("type") ?? "address"), "pairing isUr \(tag)")
            checkPretty(view, result.obj("payload"), tag)
        }
        eq(pairingCount, 31, "31 ok createPublicPairing steps")
        let nativeAccount = allSteps.first { $0.op == "createPublicPairing" && $0.result?.str("type") == "crypto-account" && $0.result?.str("profile") == "native" }
        let nativeView = nativeAccount?.result.flatMap { BILPublicPayloadView.fromEngine($0) }
        t(nativeView?.text.hasPrefix("{\n  \"master-fingerprint\": 1942346250,\n  \"output-descriptors\": [") == true, "crypto-account payload: master-fingerprint sorts first (Android sample)")
        t(nativeView.map { $0.formatSummary == "ur:crypto-account · CBOR · \($0.byteCount) B" && $0.isUr && !$0.isPsbt && $0.titleSuffix == "JSON" } == true, "crypto-account format line")

        // MARK: - 6. Malformed plans (Android "a malformed ready plan is refused", same order of checks)

        section("plan malformed")
        t(!evmReady.isEmpty, "a ready single-task EVM plan exists in the vectors")
        let evmReview = evmReady.obj("review") ?? BILJSONObject()
        eq(planWhat(evmReady), "<no throw>", "the base plan is valid")
        eq(planWhat(edited(evmReady, [("planHash", nil)])), "plan.planHash", "missing planHash")
        eq(planWhat(edited(evmReady, [("planHash", s("abc"))])), "plan.planHash", "short planHash")
        eq(planWhat(edited(evmReady, [("planHash", s(String(repeating: "g", count: 64)))])), "plan.planHash", "non-hex planHash")
        eq(planWhat(edited(evmReady, [("requestHash", .number("42"))])), "plan.requestHash", "number requestHash")
        eq(planWhat(edited(evmReady, [("version", .number("2"))])), "plan.version", "version 2")
        eq(planWhat(edited(evmReady, [("version", nil)])), "plan.version", "missing version")
        eq(planWhat(edited(evmReady, [("version", s("1"))])), "plan.version", "string version")
        eq(planWhat(edited(evmReady, [("version", .number("1.0"))])), "plan.version", "version 1.0")
        eq(planWhat(edited(evmReady, [("chain", s("cosmos"))])), "plan.chain", "unknown chain")
        eq(planWhat(edited(evmReady, [("tasks", .array([]))])), "plan.tasks", "no tasks")
        eq(planWhat(edited(evmReady, [("tasks", nil)])), "plan.tasks", "missing tasks")
        eq(planWhat(edited(evmReady, [("tasks", .object(BILJSONObject()))])), "plan.tasks", "tasks not an array")
        eq(planWhat(edited(evmReady, [("tasks", .array([.object(oneTask), .object(oneTask)]))])), "plan.task.id", "duplicate task ids")
        eq(planWhat(edited(evmReady, [("tasks", .array([s("task")]))])), "plan.task", "a task that is not an object")
        eq(planWhat(edited(evmReady, [("tasks", .array(Array(repeating: .object(oneTask), count: 64)))])), "plan.task.id", "64 tasks pass the count (then duplicate ids)")
        eq(planWhat(edited(evmReady, [("tasks", .array(Array(repeating: .object(oneTask), count: 65)))])), "plan.tasks", "65 tasks")
        eq(planWhat(edited(evmReady, [("review", nil)])), "plan.review", "missing review")
        eq(planWhat(edited(evmReady, [("review", .object(edited(evmReview, [("requestHash", s(hex64zero))])))])), "plan.review", "review of another request")
        eq(planWhat(edited(evmReady, [("review", .object(edited(evmReview, [("requestHash", s((evmReady.str("requestHash") ?? "").uppercased()))])))])), "<no throw>",
           "review hash compared ignoring case")
        eq(planWhat(edited(evmReady, [("review", .object(edited(evmReview, [("chain", s("tron"))])))])), "plan.review.chain", "review of another chain")
        eq(planWhat(edited(evmReady, [("signingBytesDigest", nil)])), "plan.signingBytesDigest", "missing digest")
        eq(planWhat(edited(evmReady, [("signingBytesDigest", s("8d63"))])), "plan.signingBytesDigest", "short digest")
        eq(planWhat(withTask([("walletKeyId", s("95f7"))])), "task.walletKeyId", "short walletKeyId")
        eq(planWhat(withTask([("walletKeyId", s(String(repeating: "x", count: 64)))])), "task.walletKeyId", "non-hex walletKeyId")
        eq(planWhat(withTask([("publicKeys", .array([]))])), "task.publicKeys", "no public keys")
        eq(planWhat(withTask([("publicKeys", .array([s("02"), s("03")]))])), "task.publicKeys", "public keys ≠ paths")
        eq(planWhat(withTask([("paths", .array([]))])), "task.paths", "no paths")
        eq(planWhat(withTask([("paths", .array([.number("1")]))])), "task.paths", "a non-string path")
        eq(planWhat(withTask([("id", s(""))])), "task.id", "empty task id")
        eq(planWhat(withTask([("id", nil)])), "task.id", "missing task id")
        eq(planWhat(withTask([("localWalletId", s(""))])), "task.localWalletId", "empty wallet id")
        eq(planWhat(withTask([("chain", s("cosmos"))])), "task.chain", "unknown task chain")
        eq(planWhat(withTask([("chain", s("tron"))])), "plan.task.chain", "task of another chain")
        eq(planWhat(withTask([("signingBytesDigest", s(hex64zero))])), "plan.task.signingBytesDigest", "task signs another digest")
        eq(planWhat(withTask([("signingBytesDigest", nil)])), "plan.task.signingBytesDigest", "task without a digest")
        let upperDigest = (evmReady.str("signingBytesDigest") ?? "").uppercased()
        let upper = try? BILPublicPlan.fromEngine(edited(evmReady, [("signingBytesDigest", s(upperDigest)), ("requestHash", s((evmReady.str("requestHash") ?? "").uppercased())),
                                                                    ("planHash", s((evmReady.str("planHash") ?? "").uppercased()))]))
        eq(upper?.signingBytesDigest, evmReady.str("signingBytesDigest")?.lowercased(), "digest lower-cased (task digests compared ignoring case)")
        eq(upper?.requestHash, evmReady.str("requestHash")?.lowercased(), "request hash lower-cased")
        eq(upper?.planHash, evmReady.str("planHash")?.lowercased(), "plan hash lower-cased")
        let upperKey = try? BILPublicPlan.fromEngine(withTask([("walletKeyId", s((oneTask.str("walletKeyId") ?? "").uppercased()))]))
        eq(upperKey?.tasks.first?.walletKeyId, oneTask.str("walletKeyId")?.lowercased(), "walletKeyId lower-cased")
        let lenientTask = try? BILPublicPlan.fromEngine(withTask([("addresses", .array([.number("1")])), ("inputs", .array([.number("1.5")])),
                                                                  ("signatureAlgorithm", nil), ("targets", .array([s("x"), .object(jq("{`signerSlot`:3}"))]))]))
        eq(lenientTask?.tasks.first?.addresses, [], "non-string addresses → []")
        eq(lenientTask?.tasks.first?.inputs, [], "non-integer inputs → []")
        eq(lenientTask?.tasks.first?.signatureAlgorithm, "", "missing algorithm → \"\"")
        eq(lenientTask?.tasks.first?.signerSlot, nil, "signer slot only from targets[0] when it is an object")
        eq(lenientTask?.tasks.first?.targets.count, 1, "targets: object elements only")
        t(lenientTask?.tasks.first?.firstTarget == nil, "firstTarget: nil when targets[0] is not an object")
        let slotString = try? BILPublicPlan.fromEngine(withTask([("targets", .array([.object(jq("{`signerSlot`:`0`,`masterFingerprint`:`73C5DA0A`}"))]))]))
        eq(slotString?.tasks.first?.signerSlot, nil, "a string signer slot reads as absent")
        eq(slotString?.tasks.first?.targetFingerprints, Set(["73c5da0a"]), "target fingerprints lower-cased")
        let dotTask = edited(oneTask, [("id", s("t\u{00B7}")), ("localWalletId", s("w\u{00B7}"))])
        let anoTask = edited(oneTask, [("id", s("t\u{0387}")), ("localWalletId", s("w\u{0387}"))])
        let exactPlan = try? BILPublicPlan.fromEngine(edited(evmReady, [("tasks", .array([.object(dotTask), .object(anoTask)]))]))
        eq(exactPlan?.tasks.count, 2, "task ids distinct by code units (U+00B7 vs U+0387)")
        eq(exactPlan?.walletIds.count, 2, "wallet ids distinct by code units")
        eq(exactPlan.flatMap { $0.task("t\u{0387}") }.map { utf16($0.id) }, utf16("t\u{0387}"), "task lookup is exact")
        eq(exactPlan?.task("t"), nil, "unknown task id")
        // walletIds = distinct localWalletIds in task order (Android `tasks.map { it.localWalletId }.distinct()`).
        let sameWallet = try? BILPublicPlan.fromEngine(edited(evmReady, [("tasks", .array([
            .object(edited(oneTask, [("id", s("t2")), ("localWalletId", s("w"))])), .object(edited(oneTask, [("id", s("t1")), ("localWalletId", s("v"))])),
            .object(edited(oneTask, [("id", s("t3")), ("localWalletId", s("w"))]))]))]))
        eq(sameWallet?.walletIds, ["w", "v"], "wallet ids: distinct, task order kept")
        eq(sameWallet?.tasks.map { $0.id }, ["t2", "t1", "t3"], "tasks keep the engine order")
        // displayAddresses / displayPaths = distinct non-empty values in engine order (Android `filter { isNotEmpty() }.distinct()`).
        let displayTask = (try? BILPublicPlan.fromEngine(withTask([("addresses", .array([s("a"), s(""), s("a"), s("b"), s("a\u{00B7}"), s("a\u{0387}")])),
                                                                   ("paths", .array([s("m/0"), s(""), s("m/0")])),
                                                                   ("publicKeys", .array([s("k1"), s("k2"), s("k3")]))])))?.tasks.first
        eq(displayTask?.paths, ["m/0", "", "m/0"], "paths kept as sent")
        eq(displayTask?.displayPaths, ["m/0"], "display paths: distinct, empty dropped")
        eq(displayTask?.displayAddresses.map(utf16), [utf16("a"), utf16("b"), utf16("a\u{00B7}"), utf16("a\u{0387}")],
           "display addresses: distinct by code units, empty dropped, order kept")
        eq(displayTask.map { task in task.displayAddresses.count }, 4, "U+00B7 and U+0387 stay two addresses")
        // A non-ready plan never carries tasks; an unknown status reads as invalid (and so must carry none either).
        let noMatch = allSteps.first { $0.op == "resolveSigningPlan" && $0.result?.str("status") == "noMatch" }?.result ?? BILJSONObject()
        t(!noMatch.isEmpty, "a noMatch plan exists in the vectors")
        eq(planWhat(edited(noMatch, [("tasks", .array([.object(oneTask)]))])), "plan.tasks", "non-ready plan with tasks")
        eq(planWhat(edited(evmReady, [("status", s("ready "))])), "plan.tasks", "unknown status with tasks is refused")
        eq(planWhat(edited(evmReady, [("status", s("Ready")), ("tasks", .array([]))])), "<no throw>", "unknown status without tasks reads as invalid")
        eq((try? BILPublicPlan.fromEngine(edited(evmReady, [("status", s("Ready")), ("tasks", .array([]))])))?.status, .invalid, "… as invalid")
        let invalidPlan = try? BILPublicPlan.fromEngine(jq("{`version`:1,`status`:`invalid`,`message`:`x`,`tasks`:[]}"))
        eq(invalidPlan?.status, .invalid, "invalid plan")
        t(invalidPlan?.review == nil && invalidPlan?.chain == nil && invalidPlan?.requestHash == nil, "invalid plan without review")
        eq(invalidPlan?.message, "x", "invalid plan message")
        let emptyHashReview = try? BILPublicPlan.fromEngine(jq("{`status`:`noMatch`,`tasks`:[],`review`:{`chain`:`evm`}}"))
        eq(emptyHashReview?.requestHash, nil, "a review without a request hash gives none")
        eq(emptyHashReview?.chain, .evm, "non-ready chain from the review")
        eq(planWhat(jq("{`status`:`noMatch`}")), "plan.tasks", "non-ready plan without tasks array")

        // MARK: - 7. Sign results and response QR codes (Android "sign results and response QR codes read")

        section("result / response malformed")
        let resultSample = allSteps.first { $0.op == "signPlanTask" && $0.result?.str("chain") == "evm" }?.result ?? BILJSONObject()
        t(!resultSample.isEmpty, "an EVM sign result exists in the vectors")
        eq(resultWhat(resultSample), "<no throw>", "the base result is valid")
        eq(resultWhat(edited(resultSample, [("completedTaskIds", .array([s("other")]))])), "result.completedTaskIds", "another task last")
        eq(resultWhat(edited(resultSample, [("completedTaskIds", .array([]))])), "result.completedTaskIds", "no completed tasks")
        eq(resultWhat(edited(resultSample, [("completedTaskIds", .array([.number("1")]))])), "result.completedTaskIds", "non-string completed ids")
        eq(resultWhat(edited(resultSample, [("completedTaskIds", nil)])), "result.completedTaskIds", "missing completed ids")
        eq(resultWhat(edited(resultSample, [("planHash", nil)])), "result.planHash", "missing planHash")
        eq(resultWhat(edited(resultSample, [("requestHash", s("zz"))])), "result.requestHash", "bad requestHash")
        eq(resultWhat(edited(resultSample, [("chain", s("cosmos"))])), "result.chain", "unknown chain")
        eq(resultWhat(edited(resultSample, [("taskId", s(""))])), "result.taskId", "empty taskId")
        eq(resultWhat(edited(resultSample, [("chain", nil), ("planHash", nil)])), "result.chain", "chain checked first")
        let upperResult = try? BILPublicSignResult.fromEngine(edited(resultSample, [("requestHash", s((resultSample.str("requestHash") ?? "").uppercased())),
                                                                                    ("planHash", s((resultSample.str("planHash") ?? "").uppercased()))]))
        eq(upperResult?.requestHash, resultSample.str("requestHash")?.lowercased(), "result hashes lower-cased")
        let twoDone = edited(resultSample, [("completedTaskIds", .array([s("a"), s(resultSample.str("taskId") ?? "")]))])
        eq((try? BILPublicSignResult.fromEngine(twoDone))?.completedTaskIds.count, 2, "earlier tasks kept")

        let responseSample = allSteps.first { $0.op == "encodeResponse" && $0.result?.str("type") == "eth-signature" }?.result ?? BILJSONObject()
        t(!responseSample.isEmpty, "an eth-signature response exists in the vectors")
        eq(responseWhat(responseSample), "<no throw>", "the base response is valid")
        let evmResponse = try? BILPublicResponseQr.fromEngine(responseSample)
        t(evmResponse?.frames.count == 1 && evmResponse?.frames.first?.hasPrefix("UR:ETH-SIGNATURE/") == true, "eth-signature frame")
        t(evmResponse.map { !$0.isAnimated && !$0.isPsbt } == true, "single frame, not a PSBT")
        t(evmResponse?.payload?.text.contains("\"request-id\"") == true, "payload names request-id")
        eq(responseWhat(edited(responseSample, [("frames", nil)])), "response.frames", "missing frames")
        eq(responseWhat(edited(responseSample, [("frames", .array([]))])), "response.frames", "no frames")
        eq(responseWhat(edited(responseSample, [("frames", .array([s(""), s("")]))])), "response.frames", "only empty frames")
        eq(responseWhat(edited(responseSample, [("frames", .array([s("a"), .number("1")]))])), "response.frames", "a non-string frame drops them all")
        eq(responseWhat(edited(responseSample, [("type", s(""))])), "response.type", "empty type")
        eq(responseWhat(edited(responseSample, [("type", nil)])), "response.type", "missing type")
        eq(responseWhat(edited(responseSample, [("type", .number("5"))])), "response.type", "number type")
        eq((try? BILPublicResponseQr.fromEngine(edited(responseSample, [("frames", .array([s(""), s("x"), s("")]))])))?.frames, ["x"], "empty frames dropped")
        t((try? BILPublicResponseQr.fromEngine(edited(responseSample, [("payloadFormat", nil)])))?.payload == nil, "no payload view without payloadFormat")
        let psbtResponse = allSteps.first { $0.op == "encodeResponse" && $0.result?.str("type") == "psbt-base64" }?.result.flatMap { try? BILPublicResponseQr.fromEngine($0) }
        t(psbtResponse.map { $0.isPsbt && $0.payload?.isPsbt == true && $0.payload?.isUr == false && $0.text.hasPrefix("cHNidP") } == true, "psbt-base64 answer")

        section("response QR")
        let paged = BILPublicResponseQr(type: "tronlink", frames: ["1", "2", "3"], payload: nil, signedTransaction: true)
        t(paged.isTronLink && paged.isPaged && !paged.isAnimated && paged.signedTransaction, "TronLink parts are paged, never animated")
        eq(paged.text, "1\n2\n3", "copy text joins the frames")
        let single = BILPublicResponseQr(type: BILPublicResponseQr.tronLinkType, frames: ["x"], payload: nil)
        t(single.isTronLink && !single.isPaged && !single.isAnimated && !single.signedTransaction, "one TronLink frame: static; signedTransaction defaults to false")
        let animated = BILPublicResponseQr(type: "eth-signature", frames: ["a", "b"], payload: nil, signedTransaction: false)
        t(animated.isAnimated && !animated.isPaged && !animated.isTronLink, "several UR frames are animated")
        t(!BILPublicResponseQr(type: "TronLink", frames: ["x"], payload: nil).isTronLink, "type comparison is exact")
        eq(["crypto-psbt", "psbt", "bbqr-psbt", "psbt-base64", "psbt-hex", "eth-signature", "PSBT"].map { BILPublicResponseQr(type: $0, frames: ["f"], payload: nil).isPsbt },
           [true, true, true, true, true, false, false], "isPsbt table")
        eq(BILPublicResponseQr.tronLinkType, "tronlink", "TronLink type")
        // `checked`: Android's `require(frames.isNotEmpty())` as a throw (DEBUG and release alike) for natively built answers.
        eq(malformedWhat { _ = try BILPublicResponseQr.checked(type: BILPublicResponseQr.tronLinkType, frames: [], payload: nil, signedTransaction: true) },
           "response.frames", "checked: no frame throws response.frames")
        let checkedQr = try? BILPublicResponseQr.checked(type: BILPublicResponseQr.tronLinkType, frames: ["1", "2"], payload: nil, signedTransaction: true)
        eq(checkedQr, BILPublicResponseQr(type: "tronlink", frames: ["1", "2"], payload: nil, signedTransaction: true), "checked: same value as the init")
        t(checkedQr.map { $0.isPaged && $0.signedTransaction } == true, "checked: TronLink parts")
        eq((try? BILPublicResponseQr.checked(type: "eth-signature", frames: ["x"], payload: nil))?.signedTransaction, false, "checked: signedTransaction defaults to false")

        // MARK: - 8. Payload view and the format line (Android "the format line names every transport …")

        section("payload view")
        eq(line("crypto-account", 162), "ur:crypto-account · CBOR · 162 B", "UR line")
        eq(line("eth-signature", 89), "ur:eth-signature · CBOR · 89 B", "UR answer line")
        eq(line("bbqr-psbt", 3120, "H"), "BBQr · PSBT (hex) · 3,120 B", "BBQr hex line")
        eq(line("bbqr-psbt", 3120, "Z"), "BBQr · PSBT (Base32) · 3,120 B", "BBQr Z line")
        eq(line("bbqr-psbt", 3120, "2"), "BBQr · PSBT (Base32) · 3,120 B", "BBQr 2 line")
        eq(line("bbqr-psbt", 3120), "BBQr · PSBT (Base32) · 3,120 B", "BBQr without encoding")
        eq(line("psbt-base64", 412), "PSBT Base64 · 412 B", "PSBT Base64 line")
        eq(line("psbt-hex", 412), "PSBT hex · 412 B", "PSBT hex line")
        eq(line("address", 34), "UTF-8 · 34 B", "address line")
        eq(line(nil, 34), "UTF-8 · 34 B", "no type line")
        eq(line(BILPublicResponseQr.tronLinkType, 1412), "TronLink · JSON · 1,412 B", "TronLink line")
        eq(line("crypto-psbt", 0), "ur:crypto-psbt · CBOR · 0 B", "zero bytes")
        eq(line("x", 999), "ur:x · CBOR · 999 B", "999")
        eq(line("x", 1000), "ur:x · CBOR · 1,000 B", "1,000")
        eq(line("x", 1_234_567), "ur:x · CBOR · 1,234,567 B", "1,234,567")
        eq(line("x", 2_147_483_647), "ur:x · CBOR · 2,147,483,647 B", "Int32.max")
        eq(line("x", -1234), "ur:x · CBOR · -1,234 B", "negative (Java %,d)")
        eq(line("TRONLINK", 1), "ur:TRONLINK · CBOR · 1 B", "type comparison is exact")
        let tronView = BILPublicPayloadView(format: .json, text: "{}", byteCount: 2, qrType: BILPublicResponseQr.tronLinkType)
        t(tronView.isOtherWalletJson && !tronView.isUr && !tronView.isPsbt, "TronLink JSON is another wallet's JSON, not a UR")
        let tronSig = BILPublicPayloadView(format: .hex, text: "00", byteCount: 1, qrType: "tron-signature")
        t(!tronSig.isOtherWalletJson && tronSig.isUr, "tron-signature is a UR")
        let untyped = BILPublicPayloadView(format: .text, text: "a", byteCount: 1, qrType: nil)
        t(!untyped.isUr && !untyped.isPsbt && !untyped.isOtherWalletJson, "no type: nothing")
        eq(["address", "bbqr-psbt", "psbt-base64", "psbt-hex", "crypto-psbt", "psbt", "crypto-account"].map {
            BILPublicPayloadView(format: .text, text: "a", byteCount: 1, qrType: $0).isUr }, [false, false, false, false, true, true, true], "isUr table")
        eq([BILPublicPayloadView.Format.json, .hex, .text].map { BILPublicPayloadView(format: $0, text: "a", byteCount: 1, qrType: nil).titleSuffix },
           ["JSON", "Hex", "UTF-8"], "title suffixes")

        let bbqrView = BILPublicPayloadView.fromEngine(jq("{`type`:`bbqr-psbt`,`payloadFormat`:`hex`,`payload`:`70736274ff`,`payloadBytes`:5,`frames`:[`B$HP0100ABCD`]}"))
        eq(bbqrView?.bbqrEncoding, "H", "BBQr encoding from the first frame")
        eq(bbqrView?.formatSummary, "BBQr · PSBT (hex) · 5 B", "BBQr hex format line")
        eq(bbqrView?.text, "70736274ff", "hex payload as is")
        eq(bbqrView?.format, .hex, "hex format")
        eq(BILPublicPayloadView.fromEngine(jq("{`type`:`bbqr-psbt`,`payloadFormat`:`hex`,`payload`:`00`,`frames`:[`B$`]}"))?.bbqrEncoding, nil, "\"B$\" alone has no encoding")
        eq(BILPublicPayloadView.fromEngine(jq("{`type`:`bbqr-psbt`,`payloadFormat`:`hex`,`payload`:`00`,`frames`:[`B$2P`,1]}"))?.bbqrEncoding, nil, "frames with a non-string: no first frame")
        eq(BILPublicPayloadView.fromEngine(jq("{`payloadFormat`:`hex`,`payload`:`00`,`frames`:[`b$HP`]}"))?.bbqrEncoding, nil, "lower-case b$ is not BBQr")
        eq(BILPublicPayloadView.fromEngine(jq("{`payloadFormat`:`json`,`payload`:`not an object`}")), nil, "JSON payload that is not an object")
        eq(BILPublicPayloadView.fromEngine(jq("{`payloadFormat`:`xml`}")), nil, "unknown payload format")
        eq(BILPublicPayloadView.fromEngine(jq("{`payloadFormat`:`JSON`,`payload`:{}}")), nil, "payload format is case-sensitive")
        eq(BILPublicPayloadView.fromEngine(jq("{`payloadFormat`:`hex`,`payload`:``}")), nil, "empty hex payload")
        eq(BILPublicPayloadView.fromEngine(jq("{`payloadFormat`:`text`,`payload`:5}")), nil, "non-string text payload")
        eq(BILPublicPayloadView.fromEngine(jq("{`payload`:`00`}")), nil, "no payload format")
        let fallbackBytes = BILPublicPayloadView.fromEngine(jq("{`payloadFormat`:`text`,`payload`:`héllo`,`payloadBytes`:`9`}"))
        eq(fallbackBytes?.byteCount, 6, "non-integer payloadBytes → UTF-8 size of the text")
        eq(BILPublicPayloadView.fromEngine(jq("{`payloadFormat`:`text`,`payload`:`a`,`payloadBytes`:2.0}"))?.byteCount, 1, "2.0 is not an integer")
        eq(BILPublicPayloadView.fromEngine(jq("{`payloadFormat`:`text`,`payload`:`a`,`payloadBytes`:4294967296}"))?.byteCount, 1, "beyond Int32 → fallback")
        eq(BILPublicPayloadView.fromEngine(jq("{`payloadFormat`:`text`,`payload`:`a`}"))?.qrType, nil, "no type")

        section("pretty JSON")
        let sample = jq("{`b`:1,`a`:{`d`:[1,{`z`:true,`y`:null}],`c`:`x`},`e`:[],`f`:{},`g`:1.50}")
        let prettyExpected = "{\n  \"a\": {\n    \"c\": \"x\",\n    \"d\": [\n      1,\n      {\n        \"y\": null,\n        \"z\": true\n      }\n    ]\n  },\n"
            + "  \"b\": 1,\n  \"e\": [],\n  \"f\": {},\n  \"g\": 1.50\n}"
        eq(BILPublicPayloadView.prettyJson(sample), prettyExpected, "prettySorted sample (sorted keys, 2-space indent, literals kept)")
        let jsonView = BILPublicPayloadView.fromEngine(jq("{`type`:`crypto-hdkey`,`payloadFormat`:`json`,`payload`:{`b`:1,`a`:{`d`:[1,{`z`:true,`y`:null}],`c`:`x`},`e`:[],`f`:{},`g`:1.50}}"))
        eq(jsonView?.text, prettyExpected, "JSON payload view text")
        eq(jsonView?.byteCount, prettyExpected.utf8.count, "no payloadBytes → UTF-8 size of the shown text (Android)")
        let order = BILPublicPayloadView.prettyJson(jq("{`z`:1,`Z`:2,`é`:3,`\u{FF71}`:4,`😀`:5}"))
        eq(order, "{\n  \"Z\": 2,\n  \"z\": 1,\n  \"é\": 3,\n  \"😀\": 5,\n  \"\u{FF71}\": 4\n}", "keys sorted by UTF-16 units (Kotlin compareTo), not by scalar")

        section("payload factories")
        let addressView = BILPublicPayloadView.text("0x9858EfFD232B4033E47d90003D41EC34EcaEda94", qrType: "address")
        eq(addressView, BILPublicPayloadView(format: .text, text: "0x9858EfFD232B4033E47d90003D41EC34EcaEda94", byteCount: 42, qrType: "address"), "address payload (Android addressOnly)")
        eq(addressView.formatSummary, "UTF-8 · 42 B", "address format line")
        eq(addressView.titleSuffix, "UTF-8", "address title suffix")
        eq(BILPublicPayloadView.text("héllo", qrType: "address").byteCount, 6, "text bytes are UTF-8")
        let answerView = BILPublicPayloadView.json(answer, qrType: BILPublicResponseQr.tronLinkType)
        eq(answerView.format, .json, "TronLink answer view is JSON (Android tronLinkAnswer)")
        eq(answerView.text, "{\n  \"a\": 1,\n  \"b\": \"é\"\n}", "TronLink answer view text is pretty sorted")
        eq(answerView.byteCount, 16, "TronLink answer bytes = UTF-8 of the compact JSON")
        eq(answerView.byteCount, BILStrictJSON.serialize(answer).utf8.count, "… = serialize(answer).utf8.count")
        eq(answerView.formatSummary, "TronLink · JSON · 16 B", "TronLink answer format line")
        t(answerView.isOtherWalletJson && answerView.bbqrEncoding == nil, "TronLink answer view kind")

        // MARK: - 9. Request info

        section("request info")
        let info = BILPublicRequestInfo.of(jq("{`chain`:`evm`,`transport`:{`type`:`eth-sign-request`,`origin`:`imToken`}}"))
        eq(info, BILPublicRequestInfo(chain: .evm, transportType: "eth-sign-request", origin: "imToken"), "chain, transport, origin")
        let long = String(repeating: "a", count: 300)
        eq(BILPublicRequestInfo.of(jq("{`transport`:{`origin`:`\(long)`}}")).origin, String(repeating: "a", count: 256), "origin cut at 256 UTF-16 units")
        eq(BILPublicRequestInfo.of(jq("{`transport`:{`origin`:`\(String(repeating: "a", count: 256))`}}")).origin, String(repeating: "a", count: 256), "256 kept")
        let straddle = String(repeating: "a", count: 255) + "😀" + "b"
        eq(BILPublicRequestInfo.of(jq("{`transport`:{`origin`:`\(straddle)`}}")).origin, String(repeating: "a", count: 255), "a pair at the cut is dropped whole")
        let emojiOrigin = BILPublicRequestInfo.of(jq("{`transport`:{`origin`:`\(String(repeating: "😀", count: 200))`}}")).origin
        eq(emojiOrigin?.utf16.count, 256, "128 emoji = 256 units")
        t(emojiOrigin.map { !$0.unicodeScalars.contains("\u{FFFD}") } == true, "no lone surrogate")
        t(none.chain == nil && none.transportType == nil && none.origin == nil, "unknown chain, non-object transport")
        let numbers = BILPublicRequestInfo.of(jq("{`chain`:`tron`,`transport`:{`type`:1,`origin`:2}}"))
        t(numbers.chain == .tron && numbers.transportType == nil && numbers.origin == nil, "non-string type / origin read as absent")
        eq(BILPublicRequestInfo.maxOrigin, 256, "max origin")

        // MARK: - 10. Policy result (R5 §2 Result rules)

        section("policy result")
        let integrity = BILPublicSignError("PublicProtocol.err.integrity", code: "CHANGE_PATH")
        let low = BILPublicPolicyResult(engineRisk: .low, insightRisk: nil, warnings: [], ackReasons: [], refusal: nil)
        t(low.pageRisk == .low && !low.requiresAcknowledgement && low.canSign, "plain: low, no consent")
        let medium = low.withInsight(.medium)
        t(medium.pageRisk == .medium && medium.insightRisk == .medium && medium.ackReasons.isEmpty, "insight medium: medium, no consent")
        let critical = low.withInsight(.critical)
        t(critical.pageRisk == .critical && critical.ackReasons == [.highRisk] && critical.requiresAcknowledgement, "insight critical: critical + consent")
        let high = low.withInsight(.high)
        eq(high.ackReasons, [.highRisk], "insight high → highRisk")
        eq(high.withInsight(.high).ackReasons, [.highRisk], "highRisk added once")
        let cleared = high.withInsight(nil)
        t(cleared.insightRisk == nil && cleared.pageRisk == .low && cleared.ackReasons == [.highRisk], "withInsight(nil) replaces the risk, keeps the reasons")
        let engineHigh = BILPublicPolicyResult(engineRisk: .high, insightRisk: nil, warnings: [], ackReasons: [.highRisk], refusal: nil).withInsight(.low)
        t(engineHigh.pageRisk == .high && engineHigh.insightRisk == .low && engineHigh.ackReasons == [.highRisk], "engine high beats a low reading (unlimited approve case)")
        let changeWarning = BILPublicOwnbitWarning(kind: .changeIndex, key: "PublicProtocol.warn.changeIndex", args: [.int(2), .text("1000")], risk: .high)
        let withWarning = BILPublicPolicyResult(engineRisk: .low, insightRisk: nil, warnings: [changeWarning], ackReasons: [.changeBeyondBound], refusal: nil)
        t(withWarning.pageRisk == .high && withWarning.requiresAcknowledgement, "an Ownbit HIGH warning raises the page risk")
        let nonce = BILPublicOwnbitWarning(kind: .durableNonce, key: "PublicProtocol.warn.durableNonce", risk: .medium)
        eq(nonce.args, [], "warning args default to none")
        eq(BILPublicPolicyResult(engineRisk: .low, insightRisk: .low, warnings: [nonce], ackReasons: [.durableNonce], refusal: nil).pageRisk, .medium, "durable nonce: medium")
        let refused = BILPublicPolicyResult(engineRisk: .high, insightRisk: nil, warnings: [], ackReasons: [.opaque, .highRisk], refusal: integrity)
        t(!refused.canSign && !refused.requiresAcknowledgement && refused.pageRisk == .high, "a refusal: cannot sign, no checkbox")
        let deduped = BILPublicPolicyResult(engineRisk: .low, insightRisk: nil, warnings: [], ackReasons: [.opaque, .highRisk, .opaque, .durableNonce, .highRisk], refusal: nil)
        eq(deduped.ackReasons, [.opaque, .highRisk, .durableNonce], "reasons ordered and unique (first occurrence)")
        eq(BILPublicPolicyResult(engineRisk: .low, insightRisk: nil, warnings: [], ackReasons: [.opaque], refusal: nil).withInsight(.critical).ackReasons, [.opaque, .highRisk],
           "highRisk appended after the existing reasons")
        t(BILPublicPolicyResult(engineRisk: .low, insightRisk: nil, warnings: [], ackReasons: [.opaque, .highRisk], refusal: nil)
          == BILPublicPolicyResult(engineRisk: .low, insightRisk: nil, warnings: [], ackReasons: [.highRisk, .opaque], refusal: nil), "equality ignores reason order (Kotlin Set)")
        t(low != low.withInsight(.low), "insight risk takes part in equality")
        t(low != BILPublicPolicyResult(engineRisk: .low, insightRisk: nil, warnings: [], ackReasons: [], refusal: integrity), "refusal takes part in equality")
        t(low != BILPublicPolicyResult(engineRisk: .low, insightRisk: nil, warnings: [nonce], ackReasons: [], refusal: nil), "warnings take part in equality")

        // MARK: - 11. Ready session and states

        section("ready / states")
        let twoWalletsStep = allSteps.first { $0.caseId == "T8-flow-psbt-two-wallets" && $0.op == "resolveSigningPlan" }
        let twoPlan = twoWalletsStep?.result.flatMap { try? BILPublicPlan.fromEngine($0) }
        t(twoPlan?.tasks.count == 2, "the two-wallet PSBT plan has two tasks")
        if let plan = twoPlan, let review = plan.review, plan.tasks.count == 2 {
            eq(plan.walletIds, ["wallet-abandon", "wallet-legal"], "wallet ids in task order")
            eq(plan.tasks.map { $0.inputs }, [[0], [1]], "each wallet signs its input")
            eq(plan.tasks.map { $0.targetFingerprints }, [Set(["73c5da0a"]), Set(["b8688df1"])], "task fingerprints")
            eq(plan.tasks.first?.firstTarget?.str("masterFingerprint"), "73c5da0a", "first target")
            let rinfo = BILPublicRequestInfo(chain: .bitcoin, transportType: "crypto-psbt", origin: nil)
            var ready = BILPublicSignReady(info: rinfo, review: review, plan: plan, policy: low, insight: nil, insightInput: nil, signedBefore: nil, completedTaskIds: [])
            t(ready.nextTask == plan.tasks[0] && ready.signatureNumber == 1 && ready.taskCount == 2 && !ready.hasPartialSignatures, "first task next")
            ready.completedTaskIds = [plan.tasks[0].id]
            t(ready.nextTask == plan.tasks[1] && ready.signatureNumber == 2 && ready.hasPartialSignatures, "second task next")
            ready.completedTaskIds = [plan.tasks[1].id]
            t(ready.nextTask == plan.tasks[0], "next = first task not completed (plan order)")
            ready.completedTaskIds = plan.tasks.map { $0.id }
            t(ready.nextTask == nil && ready.signatureNumber == 3, "all signed: no next task")
            ready.completedTaskIds = [plan.tasks[0].id.uppercased()]
            t(ready.nextTask == plan.tasks[0], "completed ids compared exactly")
            eq(BILPublicSignState.ready(ready).requestHash, review.requestHash, "ready → review hash")
            let response = BILPublicResponseQr(type: "crypto-psbt", frames: ["UR:CRYPTO-PSBT/X"], payload: nil)
            eq(BILPublicSignState.answered(info: rinfo, review: review, plan: plan, response: response).requestHash, review.requestHash, "answered → review hash")
            eq(BILPublicSignState.refused(info: rinfo, error: integrity, review: review, canMatchAgain: false).requestHash, review.requestHash, "refused with review")
            eq(BILPublicSignState.refused(info: rinfo, error: integrity, review: nil, canMatchAgain: true).requestHash, nil, "refused without review")
            eq(BILPublicSignState.notReady(info: rinfo, status: .noMatch, review: review, setupWalletIds: [], engineMessage: nil).requestHash, review.requestHash, "not ready with review")
            eq(BILPublicSignState.notReady(info: rinfo, status: .invalid, review: nil, setupWalletIds: [], engineMessage: "x").requestHash, nil, "not ready without review")
            eq(BILPublicSignState.resolving(rinfo).requestHash, nil, "resolving")
            eq(BILPublicSignState.gone.requestHash, nil, "gone")
        }

        section("outcomes / errors / redaction")
        t(BILPublicTaskOutcome.signed(taskId: "a", nextTaskId: nil) == .signed(taskId: "a", nextTaskId: nil), "signed equality")
        t(BILPublicTaskOutcome.signed(taskId: "a", nextTaskId: nil) != .signed(taskId: "a", nextTaskId: "b"), "next task takes part")
        t(BILPublicTaskOutcome.failed(integrity) == .failed(integrity) && BILPublicTaskOutcome.failed(integrity) != .failed(integrity.with(code: "X")), "failed equality")
        t(BILPublicTaskOutcome.gone != .acknowledgementRequired, "gone ≠ acknowledgementRequired")
        let prepareError = BILPublicPrepareError(error: BILPublicSignError("PublicProtocol.err.tooLarge", code: "LIMIT", engineMessage: "Request exceeds one megabyte."))
        eq("\(prepareError)", "BILPublicPrepareError(LIMIT)", "prepare error prints the code")
        eq(String(reflecting: prepareError), "BILPublicPrepareError(LIMIT)", "… also when reflected")
        eq("\(BILPublicPrepareError(error: BILPublicSignError("PublicProtocol.err.qrMalformed")))", "BILPublicPrepareError(PublicProtocol.err.qrMalformed)", "no code → key")
        t(prepareError == BILPublicPrepareError(error: prepareError.error), "prepare error equality")
        let secretPrepare = BILPublicPrepareError(error: BILPublicSignError("PublicProtocol.err.tronOwner", args: [.text("TSECRETADDRESS")], code: "TRON_OWNER",
                                                                            engineMessage: "ENGINE SECRET TEXT"))
        var dumpedPrepare = ""
        dump(secretPrepare, to: &dumpedPrepare)
        t(!dumpedPrepare.contains("SECRET"), "dump of a prepare error shows neither the engine message nor the arguments")
        eq(Mirror(reflecting: secretPrepare).children.count, 0, "prepare error mirror has no child")
        eq(String(reflecting: secretPrepare), "BILPublicPrepareError(TRON_OWNER)", "prepare error reflected: the code only")
        let secretPaste = BILPublicInput.pasted("cHNidP8BAH0CAAAAAf secret")
        eq("\(secretPaste)", "Pasted(25 chars)", "pasted input prints its size only")
        var dumped = ""
        dump(secretPaste, to: &dumped)
        t(!dumped.contains("secret") && !String(reflecting: secretPaste).contains("secret"), "dump / reflection show no pasted text")
        let framesInput = BILPublicInput.frames(jq("{`chain`:`evm`,`address`:`0xsecret`}"))
        eq("\(framesInput)", "Frames(<2 keys>)", "frames input prints its key count only")
        var dumpedFrames = ""
        dump(framesInput, to: &dumpedFrames)
        t(!dumpedFrames.contains("0xsecret"), "dump shows no request content")
        let insightInput = BILPublicInsightInput(request: BILSignatureRequest(chain: "eip155:1", method: "personal_sign", payload: .evmPersonalSign(message: "secret message")),
                                                 raw: "secret raw", ownAddresses: ["0xsecretaddress"])
        eq("\(insightInput)", "BILPublicInsightInput(eip155:1, personal_sign)", "insight input prints chain and method")
        var dumpedInsight = ""
        dump(insightInput, to: &dumpedInsight)
        t(!dumpedInsight.contains("secret"), "dump shows no insight data")

        // MARK: - 11b. Exact `==` of the contract value types (design D-01: never Swift canonical equivalence)

        section("exact equality")
        t(ePre == eDec && [ePre] == [eDec], "premise: Swift String == is canonical equivalence")
        exactEquality("BILReviewField", base: BILReviewField(index: 1, label: "L" + ePre, value: "V" + ePre),
                      copy: BILReviewField(index: 1, label: "L" + ePre, value: "V" + ePre),
                      canonical: [BILReviewField(index: 1, label: "L" + eDec, value: "V" + ePre), BILReviewField(index: 1, label: "L" + ePre, value: "V" + eDec)],
                      variants: [BILReviewField(index: 2, label: "L" + ePre, value: "V" + ePre), BILReviewField(index: 1, label: "L", value: "V" + ePre),
                                 BILReviewField(index: 1, label: "L" + ePre, value: "V")])
        exactEquality("BILReviewNetwork", base: BILReviewNetwork(chainId: "1" + ePre, name: "N" + ePre, symbol: "S" + ePre),
                      copy: BILReviewNetwork(chainId: "1" + ePre, name: "N" + ePre, symbol: "S" + ePre),
                      canonical: [BILReviewNetwork(chainId: "1" + eDec, name: "N" + ePre, symbol: "S" + ePre),
                                  BILReviewNetwork(chainId: "1" + ePre, name: "N" + eDec, symbol: "S" + ePre),
                                  BILReviewNetwork(chainId: "1" + ePre, name: "N" + ePre, symbol: "S" + eDec)],
                      variants: [BILReviewNetwork(chainId: nil, name: "N" + ePre, symbol: "S" + ePre), BILReviewNetwork(chainId: "1" + ePre, name: "N", symbol: "S" + ePre),
                                 BILReviewNetwork(chainId: "1" + ePre, name: "N" + ePre, symbol: nil)])
        exactEquality("BILReviewAsset", base: asset(-1), copy: asset(-1), canonical: [0, 1, 2, 3, 4, 6, 7, 8].map { asset($0, eDec) },
                      variants: [0, 2, 3, 4].map { asset($0, "x") } + [asset(5)] + [1, 6, 7, 8].map { asset($0, "") })
        exactEquality("BILFlowLines", base: BILFlowLines(lines: ["a" + ePre, "b"], more: 1), copy: BILFlowLines(lines: ["a" + ePre, "b"], more: 1),
                      canonical: [BILFlowLines(lines: ["a" + eDec, "b"], more: 1)],
                      variants: [BILFlowLines(lines: ["a" + ePre], more: 1), BILFlowLines(lines: ["a" + ePre, "b", "c"], more: 1),
                                 BILFlowLines(lines: ["a" + ePre, "c"], more: 1), BILFlowLines(lines: ["a" + ePre, "b"], more: 2)])
        /// A display with every key set; `f` = the key to change (0…14), `e` = the text appended to it (nil → the key absent).
        exactEquality("BILPublicReviewDisplay", base: display(-1), copy: display(-1),
                      canonical: [0, 1, 2, 3, 4, 5, 6, 7, 9, 10, 11, 12, 13, 14].map { display($0, eDec) },
                      variants: [display(0, "x")] + [1, 2, 3, 4, 5, 6, 7, 9, 10, 11].map { display($0, nil) } + [display(8)] + [12, 13, 14].map { display($0, nil) })
        let viewPre = BILPublicPayloadView(format: .json, text: "t" + ePre, byteCount: 3, qrType: "q" + ePre, bbqrEncoding: ePre)
        exactEquality("BILPublicPayloadView", base: viewPre, copy: BILPublicPayloadView(format: .json, text: "t" + ePre, byteCount: 3, qrType: "q" + ePre, bbqrEncoding: ePre),
                      canonical: [BILPublicPayloadView(format: .json, text: "t" + eDec, byteCount: 3, qrType: "q" + ePre, bbqrEncoding: ePre),
                                  BILPublicPayloadView(format: .json, text: "t" + ePre, byteCount: 3, qrType: "q" + eDec, bbqrEncoding: ePre),
                                  BILPublicPayloadView(format: .json, text: "t" + ePre, byteCount: 3, qrType: "q" + ePre, bbqrEncoding: eDec)],
                      variants: [BILPublicPayloadView(format: .text, text: "t" + ePre, byteCount: 3, qrType: "q" + ePre, bbqrEncoding: ePre),
                                 BILPublicPayloadView(format: .json, text: "t", byteCount: 3, qrType: "q" + ePre, bbqrEncoding: ePre),
                                 BILPublicPayloadView(format: .json, text: "t" + ePre, byteCount: 4, qrType: "q" + ePre, bbqrEncoding: ePre),
                                 BILPublicPayloadView(format: .json, text: "t" + ePre, byteCount: 3, qrType: nil, bbqrEncoding: ePre),
                                 BILPublicPayloadView(format: .json, text: "t" + ePre, byteCount: 3, qrType: "q" + ePre, bbqrEncoding: nil)])
        let viewDec = BILPublicPayloadView(format: .json, text: "t" + eDec, byteCount: 3, qrType: "q" + ePre, bbqrEncoding: ePre)
        exactEquality("BILPublicResponseQr", base: BILPublicResponseQr(type: "t" + ePre, frames: ["f" + ePre, "g"], payload: viewPre, signedTransaction: true),
                      copy: BILPublicResponseQr(type: "t" + ePre, frames: ["f" + ePre, "g"], payload: viewPre, signedTransaction: true),
                      canonical: [BILPublicResponseQr(type: "t" + eDec, frames: ["f" + ePre, "g"], payload: viewPre, signedTransaction: true),
                                  BILPublicResponseQr(type: "t" + ePre, frames: ["f" + eDec, "g"], payload: viewPre, signedTransaction: true),
                                  BILPublicResponseQr(type: "t" + ePre, frames: ["f" + ePre, "g"], payload: viewDec, signedTransaction: true)],
                      variants: [BILPublicResponseQr(type: "t", frames: ["f" + ePre, "g"], payload: viewPre, signedTransaction: true),
                                 BILPublicResponseQr(type: "t" + ePre, frames: ["f" + ePre], payload: viewPre, signedTransaction: true),
                                 BILPublicResponseQr(type: "t" + ePre, frames: ["f" + ePre, "g"], payload: nil, signedTransaction: true),
                                 BILPublicResponseQr(type: "t" + ePre, frames: ["f" + ePre, "g"], payload: viewPre, signedTransaction: false)])
        exactEquality("BILPublicRequestInfo", base: BILPublicRequestInfo(chain: .evm, transportType: "t" + ePre, origin: "o" + ePre),
                      copy: BILPublicRequestInfo(chain: .evm, transportType: "t" + ePre, origin: "o" + ePre),
                      canonical: [BILPublicRequestInfo(chain: .evm, transportType: "t" + eDec, origin: "o" + ePre),
                                  BILPublicRequestInfo(chain: .evm, transportType: "t" + ePre, origin: "o" + eDec),
                                  BILPublicRequestInfo(chain: .evm, transportType: "\u{212B}", origin: "o" + ePre)],
                      variants: [BILPublicRequestInfo(chain: .tron, transportType: "t" + ePre, origin: "o" + ePre),
                                 BILPublicRequestInfo(chain: nil, transportType: "t" + ePre, origin: "o" + ePre),
                                 BILPublicRequestInfo(chain: .evm, transportType: nil, origin: "o" + ePre),
                                 BILPublicRequestInfo(chain: .evm, transportType: "t" + ePre, origin: nil)])
        t(BILPublicRequestInfo(chain: nil, transportType: "\u{212B}", origin: nil) != BILPublicRequestInfo(chain: nil, transportType: "\u{00C5}", origin: nil),
          "request info: Å (U+212B) ≠ Å (U+00C5)")
        let warnPre = BILPublicOwnbitWarning(kind: .changeIndex, key: "k" + ePre, args: [.text("a" + ePre), .int(1)], risk: .high)
        exactEquality("BILPublicOwnbitWarning", base: warnPre, copy: BILPublicOwnbitWarning(kind: .changeIndex, key: "k" + ePre, args: [.text("a" + ePre), .int(1)], risk: .high),
                      canonical: [BILPublicOwnbitWarning(kind: .changeIndex, key: "k" + eDec, args: [.text("a" + ePre), .int(1)], risk: .high),
                                  BILPublicOwnbitWarning(kind: .changeIndex, key: "k" + ePre, args: [.text("a" + eDec), .int(1)], risk: .high)],
                      variants: [BILPublicOwnbitWarning(kind: .durableNonce, key: "k" + ePre, args: [.text("a" + ePre), .int(1)], risk: .high),
                                 BILPublicOwnbitWarning(kind: .changeIndex, key: "k", args: [.text("a" + ePre), .int(1)], risk: .high),
                                 BILPublicOwnbitWarning(kind: .changeIndex, key: "k" + ePre, args: [.text("a" + ePre)], risk: .high),
                                 BILPublicOwnbitWarning(kind: .changeIndex, key: "k" + ePre, args: [.text("a" + ePre), .int(2)], risk: .high),
                                 BILPublicOwnbitWarning(kind: .changeIndex, key: "k" + ePre, args: [.int(1), .text("a" + ePre)], risk: .high),
                                 BILPublicOwnbitWarning(kind: .changeIndex, key: "k" + ePre, args: [.text("a" + ePre), .int(1)], risk: .medium)])
        /// A sign error with every field set; `f` = the field to change (0 key, 1 args, 2 code, 3 engineMessage), `e` = its "é".
        exactEquality("BILPublicPrepareError", base: BILPublicPrepareError(error: signError(-1)), copy: BILPublicPrepareError(error: signError(-1)),
                      canonical: (0...3).map { BILPublicPrepareError(error: signError($0, eDec)) },
                      variants: (0...3).map { BILPublicPrepareError(error: signError($0, "")) })
        exactEquality("BILPublicTaskOutcome.signed", base: BILPublicTaskOutcome.signed(taskId: "t" + ePre, nextTaskId: "n" + ePre),
                      copy: .signed(taskId: "t" + ePre, nextTaskId: "n" + ePre),
                      canonical: [.signed(taskId: "t" + eDec, nextTaskId: "n" + ePre), .signed(taskId: "t" + ePre, nextTaskId: "n" + eDec)],
                      variants: [.signed(taskId: "t", nextTaskId: "n" + ePre), .signed(taskId: "t" + ePre, nextTaskId: nil), .acknowledgementRequired,
                                 .failed(signError(-1)), .gone])
        exactEquality("BILPublicTaskOutcome.failed", base: BILPublicTaskOutcome.failed(signError(-1)), copy: .failed(signError(-1)),
                      canonical: (0...3).map { BILPublicTaskOutcome.failed(signError($0, eDec)) },
                      variants: (0...3).map { BILPublicTaskOutcome.failed(signError($0, "")) } + [BILPublicTaskOutcome.gone])
        t(BILPublicTaskOutcome.acknowledgementRequired == .acknowledgementRequired && BILPublicTaskOutcome.gone == .gone
          && BILPublicTaskOutcome.signed(taskId: "a", nextTaskId: nil) == .signed(taskId: "a", nextTaskId: nil), "outcomes: reflexive")
        let policyPre = BILPublicPolicyResult(engineRisk: .low, insightRisk: nil, warnings: [warnPre], ackReasons: [.opaque], refusal: signError(-1))
        exactEquality("BILPublicPolicyResult", base: policyPre,
                      copy: BILPublicPolicyResult(engineRisk: .low, insightRisk: nil, warnings: [warnPre], ackReasons: [.opaque], refusal: signError(-1)),
                      canonical: [BILPublicPolicyResult(engineRisk: .low, insightRisk: nil, warnings: [warnPre], ackReasons: [.opaque], refusal: signError(2, eDec)),
                                  BILPublicPolicyResult(engineRisk: .low, insightRisk: nil,
                                                        warnings: [BILPublicOwnbitWarning(kind: .changeIndex, key: "k" + eDec, args: [.text("a" + ePre), .int(1)], risk: .high)],
                                                        ackReasons: [.opaque], refusal: signError(-1))],
                      variants: [BILPublicPolicyResult(engineRisk: .medium, insightRisk: nil, warnings: [warnPre], ackReasons: [.opaque], refusal: signError(-1)),
                                 BILPublicPolicyResult(engineRisk: .low, insightRisk: .low, warnings: [warnPre], ackReasons: [.opaque], refusal: signError(-1)),
                                 BILPublicPolicyResult(engineRisk: .low, insightRisk: nil, warnings: [], ackReasons: [.opaque], refusal: signError(-1)),
                                 BILPublicPolicyResult(engineRisk: .low, insightRisk: nil, warnings: [warnPre], ackReasons: [.highRisk], refusal: signError(-1)),
                                 BILPublicPolicyResult(engineRisk: .low, insightRisk: nil, warnings: [warnPre], ackReasons: [.opaque], refusal: nil)])
        // The parsed engine results are exact through `raw` (exact JSON equality).
        let reviewPre = try! BILPublicReview.fromEngine(jq("{`chain`:`evm`,`fields`:[{`label`:`To`,`value`:`\(ePre)`}]}"))
        let reviewDec = try! BILPublicReview.fromEngine(jq("{`chain`:`evm`,`fields`:[{`label`:`To`,`value`:`\(eDec)`}]}"))
        t(reviewPre != reviewDec && reviewPre.fields != reviewDec.fields, "review: a decomposed value is another review")

        // MARK: - 12. Observation token

        section("observation")
        var cancelCalls = 0
        let observation = BILPublicObservation { cancelCalls += 1 }
        t(!observation.isCancelled, "fresh token not cancelled")
        observation.cancel()
        eq(cancelCalls, 1, "cancel runs the handler")
        t(observation.isCancelled, "cancelled")
        observation.cancel()
        eq(cancelCalls, 1, "cancel is idempotent")
        dropToken()
        eq(deinitCalls, 1, "releasing the token cancels it")
        cancelThenDrop()
        eq(afterCancelCalls, 1, "deinit after cancel does not run the handler again")
        t(Thread.isMainThread, "premise: the checks above ran on the main thread (handler ran synchronously)")
        let racyLock = NSLock()
        var racyCalls = 0
        var racyOffMain = 0
        let racy = BILPublicObservation {
            racyLock.lock(); racyCalls += 1; if !Thread.isMainThread { racyOffMain += 1 }; racyLock.unlock()
        }
        DispatchQueue.concurrentPerform(iterations: 200) { _ in racy.cancel() }
        t(racy.isCancelled, "cancelled after concurrent cancels")
        drainMainQueue()
        eq(racyCalls, 1, "200 concurrent cancels run the handler once")
        eq(racyOffMain, 0, "… on the main thread")
        // Cancel off the main thread: the handler is enqueued on the main queue (the main thread is blocked here, so it has
        // not run yet), then runs once on the main thread.
        var offCalls = 0
        var offOnMain = false
        let offToken = BILPublicObservation { offCalls += 1; offOnMain = Thread.isMainThread }
        let offDone = DispatchSemaphore(value: 0)
        DispatchQueue.global().async { offToken.cancel(); offToken.cancel(); offDone.signal() }
        offDone.wait()
        t(offToken.isCancelled && offCalls == 0, "off-main cancel: cancelled at once, handler not run on the cancelling thread")
        drainMainQueue()
        t(offCalls == 1 && offOnMain, "off-main cancel: handler ran once, on the main thread")
        // Releasing the last reference off the main thread: same.
        var releaseCalls = 0
        var releaseOnMain = false
        let releaseDone = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            autoreleasepool {
                let token = BILPublicObservation { releaseCalls += 1; releaseOnMain = Thread.isMainThread }
                _ = token.isCancelled
            }
            releaseDone.signal()
        }
        releaseDone.wait()
        eq(releaseCalls, 0, "off-main release: handler not run on the releasing thread")
        drainMainQueue()
        t(releaseCalls == 1 && releaseOnMain, "off-main release: handler ran once, on the main thread")

        // MARK: - 13. Setup-sheet Prepare texts (addendum A4, Android PublicSignerErrors.prepare)

        section("prepare texts")
        let prepareCases: [(BILPublicPrepareResult, String?, String?)] = [
            (.ready(fingerprint: "73C5DA0A"), nil, nil),
            (.notEligible, "PublicProtocol.err.noWallet", "PublicProtocol.err.noWallet"),
            (.keysMismatch(.tron), "PublicProtocol.pair.keysMismatch", "PublicProtocol.pair.keysMismatch"),
            (.failed(.engineUnavailable, engineCode: nil), "PublicProtocol.err.engineUnavailable", "PublicProtocol.err.engineUnavailable"),
            (.failed(.engine, engineCode: "SEED"), "PublicProtocol.err.engineUnavailable", "PublicProtocol.err.engineUnavailable"),
            (.failed(.storage, engineCode: nil), "PublicProtocol.err.rebuildPublicData", "PublicProtocol.err.rebuildPublicData"),
            (.failed(.seedMismatch, engineCode: nil), "PublicProtocol.err.rebuildPublicData", "PublicProtocol.pair.keysMismatch"),
            (.failed(.noSecret, engineCode: nil), "PublicProtocol.err.noWallet", "PublicProtocol.err.rebuildPublicData"),
        ]
        for (result, sheet, panel) in prepareCases {
            eq(BILPublicSignerErrors.prepare(result), sheet, "setup sheet text of \(result)")
            eq(result.messageKey, panel, "pairing panel text of \(result) unchanged")
        }
        // (The app also checked that each key exists in its en / zh-Hans / ar PublicProtocol.strings; the package ships no
        // strings tables, so only the keys are checked above.)

        // MARK: - 14. The coordinator protocol is implementable as declared (MainActor)

        section("coordinator protocol")
        runAsync {
            let probe: BILPublicSignCoordinating = await ProbeCoordinator()
            let id = try await probe.prepare(.frames(BILJSONObject()))
            eq(id, "r1", "prepare returns the request id")
            var seen = [String?]()
            let token = await probe.observe(id) { seen.append($0.requestHash) }
            eq(seen.count, 1, "observe delivers the current state at once")
            token.cancel()
            do {
                _ = try await probe.prepare(.pasted("x"))
                t(false, "a pasted prepare error is thrown")
            } catch let e as BILPublicPrepareError {
                eq(e.error.code, "UNEXPECTED", "prepare throws BILPublicPrepareError")
            }
            await probe.discard(id)
            let after = await probe.state(id)
            if case .gone = after { t(true, "discarded → gone") } else { t(false, "discarded → gone") }
        }

        pubSummary("models-core")
    }
}
