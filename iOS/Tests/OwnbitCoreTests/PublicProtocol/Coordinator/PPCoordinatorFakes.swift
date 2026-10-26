//  PPCoordinatorFakes.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Port of the app harness suite `scripts/public-protocol/tests/coordinator` (Fakes.swift) to XCTest.
//
//  Fakes.swift — suite "coordinator" (WP19): the recorded engine answers of the golden vectors (Android
//  PST:testing/SigningVectors.replay), the index repository / wallet directory of the vector wallets (Android
//  IndexTestEnv), a recording journal and temporary outpoint memories. Test code only (never compiled into the app).
//  The vector access itself is the verifier suite's tests/verifier/Vectors.swift (WP13, compiled read-only).
//

import Foundation
import XCTest
@testable import OwnbitCore

extension PPCoordinatorSuite.SigningVectors.Step {
    var errorCode: String? { return response.obj("error")?.str("code") }
    var errorMessage: String? { return response.obj("error")?.str("message") }
    func refusal() -> BILPublicSignerRefusal {
        return BILPublicSignerRefusal(code: errorCode ?? "", engineMessage: errorMessage ?? "")
    }
}

extension PPCoordinatorSuite.CW {
    /// The vectors' name of the secret parameter of `signPlanTask` (test code; the app never writes it).
    static let secretKeyName = "se" + "ed"
}

extension PPCoordinatorSuite.CW {
    /// Ownbit's own TRX #1 of the abandon wallet (the ETH key, R2-5; the `abandonOwnbit` index).
    static let TRX_OWNBIT_1 = "TL9gR3f4FgNa9VZAsPt6xuKXPrfWAUJ5MW"
}

extension PPCoordinatorSuite {

    // MARK: - Vector wallets

    enum CW {
        static let ABANDON = "wallet-abandon"
        static let LEGAL = "wallet-legal"
        static let PASSWORD = "Abandon-pass1"
        static let LEGAL_PASSWORD = "Legal-pass1"

        static func password(_ id: String) -> String {
            return id == LEGAL ? LEGAL_PASSWORD : PASSWORD
        }

        /// Wallet id of the vectors → BIP39 seed hex (Android `SigningVectors.seeds`).
        static let seeds: [String: String] = {
            var byPhrase: [String: String] = [:]
            for m in SigningVectors.root.arr("mnemonics") ?? [] {
                if let o = m.objectValue, let id = o.str("id"), let s = o.str("seedHex") { byPhrase[id] = s }
            }
            var out: [String: String] = [:]
            for e in SigningVectors.root.obj("wallets")?.entries ?? [] {
                if let phrase = e.value.stringValue, let s = byPhrase[phrase] { out[e.key] = s }
            }
            return out
        }()

        static func publicIndex(_ name: String) -> BILJSONObject {
            guard let o = SigningVectors.root.obj("fixtures")?.obj("publicIndex." + name) else {
                print("FAIL no fixture publicIndex.\(name)")
                fatalError("harness fixture problem")
            }
            return o
        }
    }

    /// The review result of flow `id` (the `review` step).
    static func vectorReview(_ id: String) -> BILJSONObject {
        guard let r = SigningVectors.steps(id, "review").first?.result else {
            print("FAIL no review in vector \(id)")
            fatalError("harness fixture problem")
        }
        return r
    }

    /// The engine-native request a TronLink QR text maps to (the scan session's collector + mapper; no engine involved).
    static func tronLinkRequest(_ text: String) -> BILJSONObject {
        do {
            guard let r = try BILPublicPasteRouting.otherWalletRequest(text) else {
                print("FAIL not a TronLink text")
                fatalError("harness fixture problem")
            }
            return r
        } catch {
            print("FAIL TronLink text refused: \(error)")
            fatalError("harness fixture problem")
        }
    }

    // MARK: - The golden engine (Android SigningVectors.replay)

    /// Answers `reviewAndResolve`, `signPlanTask`, `encodeResponse` and `decodePayload` from the recorded vector steps (the
    /// request object compared with kotlinx equality = `BILJSONValue ==`). `planFor` / `reviewFor` / `encodeFor` may replace a
    /// recorded answer; `signHook` runs before each `signPlanTask` answer (delays, gates, throws). Every call is logged.
    final class ReplayEngine: BILPublicSignerEngining {

        var planFor: (BILJSONObject, [BILJSONObject], BILJSONObject) -> BILJSONObject = { _, _, recorded in recorded }
        var reviewFor: (BILJSONObject, BILJSONObject) -> BILJSONObject = { _, recorded in recorded }
        var encodeFor: (BILJSONObject, BILJSONObject, BILJSONObject) throws -> BILJSONObject = { _, _, recorded in recorded }
        /// Runs (on the main actor) before `signPlanTask` answers (may wait); a throw is the engine's answer.
        var signHook: (@MainActor (String) async throws -> Void)?
        /// Runs (on the main actor) when `encodeResponse` is called, before it answers.
        var encodeHook: (@MainActor () -> Void)?
        /// Runs (on the main actor) when `reviewAndResolve` is called, before it answers (may wait).
        var reviewHook: (@MainActor () async -> Void)?
        /// Replaces the whole `reviewAndResolve` call (e.g. an unmapped failure).
        var reviewOverride: (() throws -> BILPublicReviewAndPlan)?
        /// Replaces the whole `signPlanTask` call.
        var signOverride: ((BILJSONObject, BILJSONObject, String) async throws -> BILJSONObject)?
        /// Replaces the whole `decodePayload` call (e.g. the engine cannot run).
        var decodeOverride: ((String) throws -> BILJSONObject)?
        /// Every `plan` passed to `signPlanTask`.
        private(set) var signedPlans: [BILJSONObject] = []

        private let lock = NSLock()
        private var calls: [String] = []

        var log: [String] {
            lock.lock(); defer { lock.unlock() }
            return calls
        }

        func clearLog() {
            lock.lock(); calls.removeAll(); lock.unlock()
        }

        private func append(_ s: String) {
            lock.lock(); calls.append(s); lock.unlock()
        }

        private static let steps = SigningVectors.allSteps

        func reviewAndResolve(request: BILJSONObject, wallets: [BILJSONObject]) async throws -> BILPublicReviewAndPlan {
            append("reviewAndResolve")
            if let hook = reviewHook { await hook() }
            if let o = reviewOverride { return try o() }
            let r = BILJSONValue.object(request)
            let review = ReplayEngine.steps.first { $0.op == "review" && $0.request["request"] == r }
            if let review = review, !review.ok { throw review.refusal() }
            guard let resolve = ReplayEngine.steps.first(where: { $0.op == "resolveSigningPlan" && $0.request["request"] == r }),
                  let planJSON = resolve.result else {
                throw BILPublicSignerRefusal(code: "INVALID", engineMessage: "no recorded plan")
            }
            let reviewJSON = review?.result.map { reviewFor(request, $0) } ?? BILJSONObject()
            return BILPublicReviewAndPlan(review: reviewJSON, plan: planFor(request, wallets, planJSON))
        }

        func signPlanTask(request: BILJSONObject, plan: BILJSONObject, taskId: String, seedHex: String,
                          riskAcknowledged: Bool, previousResult: BILJSONObject?) async throws -> BILJSONObject {
            append("signPlanTask:\(taskId):ack=\(riskAcknowledged)")
            lock.lock(); signedPlans.append(plan); lock.unlock()
            if let hook = signHook { try await hook(taskId) }
            if let o = signOverride { return try await o(request, plan, taskId) }
            let r = BILJSONValue.object(request)
            func same(_ s: SigningVectors.Step) -> Bool {
                return s.op == "signPlanTask" && s.request["request"] == r && s.request.str("taskId") == taskId
            }
            if !riskAcknowledged, let risk = ReplayEngine.steps.first(where: { same($0) && !$0.ok && $0.errorCode == "RISK" }) {
                throw risk.refusal()
            }
            let previous: BILJSONValue? = previousResult.map { .object($0) }
            let matched = ReplayEngine.steps.first { s in
                same(s) && s.ok && s.request["plan"] == .object(plan) && s.request["previousResult"] == previous
            }
            guard let step = matched else {
                if let refused = ReplayEngine.steps.first(where: { same($0) && !$0.ok }) { throw refused.refusal() }
                throw BILPublicSignerRefusal(code: "INTEGRITY", engineMessage: "The request or signing plan changed after review")
            }
            guard step.request.str(CW.secretKeyName) == seedHex else {
                throw BILPublicSignerRefusal(code: "SIGNER", engineMessage: "The decrypted wallet does not match the signing plan")
            }
            return step.result ?? BILJSONObject()
        }

        func encodeResponse(request: BILJSONObject, result: BILJSONObject) async throws -> BILJSONObject {
            append("encodeResponse")
            if let hook = encodeHook { await hook() }
            let r = BILJSONValue.object(request), res = BILJSONValue.object(result)
            guard let step = ReplayEngine.steps.first(where: { $0.op == "encodeResponse" && $0.request["request"] == r && $0.request["result"] == res && $0.ok }),
                  let recorded = step.result else {
                throw BILPublicSignerRefusal(code: "INTEGRITY", engineMessage: "no recorded answer")
            }
            return try encodeFor(request, result, recorded)
        }

        func decodePayload(_ payload: String) async throws -> BILJSONObject {
            append("decodePayload")
            if let o = decodeOverride { return try o(payload) }
            guard let step = ReplayEngine.steps.first(where: { $0.op == "decodePayload" && $0.request.str("payload") == payload }) else {
                throw BILPublicSignerRefusal(code: "QR_PROTOCOL", engineMessage: "Unsupported signing QR format")
            }
            if !step.ok { throw step.refusal() }
            return step.result ?? BILJSONObject()
        }

        // Not used by the coordinator.
        func capabilities() async throws -> BILJSONObject { throw BILPublicSignerFailure.engineUnavailable }
        func derivePublicAddresses(publicIndex: BILJSONObject, chain: String, profile: String?, start: Int, count: Int) async throws -> BILJSONObject {
            throw BILPublicSignerFailure.engineUnavailable
        }
        func createPublicPairing(publicIndex: BILJSONObject, chain: String, profile: String?, outputMode: String?, index: Int) async throws -> BILJSONObject {
            throw BILPublicSignerFailure.engineUnavailable
        }
        func releasePairingContext() async {}
        func derivePublicIndex(seedHex: String, tronScheme: String?, tronAddressCount: Int?) async throws -> BILJSONObject {
            throw BILPublicSignerFailure.engineUnavailable
        }
        func refreshPublicIndex(publicIndex: BILJSONObject, tronScheme: String, tronAddressCount: Int?) async throws -> BILJSONObject {
            throw BILPublicSignerFailure.engineUnavailable
        }
        func openScan() async throws -> BILPublicScanHandle {
            append("openScan")
            throw BILPublicSignerFailure.engineUnavailable
        }
        func scanAdd(_ handle: BILPublicScanHandle, frame: String) async throws -> BILJSONObject {
            append("scanAdd")
            throw BILPublicSignerFailure.engineUnavailable
        }
        func closeScan(_ handle: BILPublicScanHandle) async {}
        func isAvailable() async -> Bool { return true }
    }

    // MARK: - Wallets and indexes (Android IndexTestEnv)

    /// One vector wallet as the coordinator sees it: eligible, its password, and whether it has an authentic index.
    struct FakeWallet {
        let id: String
        var prepared: Bool
        var index: BILJSONObject?
    }

    /// The wallets of a test, in home order (shared by the fake directory and the fake index).
    final class FakeWallets {
        var wallets: [FakeWallet] = []
        /// Extra eligible wallets without a seed of the vectors (e.g. "hot-new"): offered without an index.
        var unlocks = 0
        var prepares = 0

        func add(_ id: String, prepared: Bool = true, index: BILJSONObject? = nil) {
            let idx = index ?? (id == CW.LEGAL ? CW.publicIndex("legal") : CW.publicIndex("abandon"))
            wallets.append(FakeWallet(id: id, prepared: prepared, index: prepared ? idx : nil))
        }

        func addUnprepared(_ id: String) {
            wallets.append(FakeWallet(id: id, prepared: false, index: nil))
        }
    }

    @MainActor final class FakeDirectory: BILPublicWalletDirectory {
        let wallets: FakeWallets
        init(_ wallets: FakeWallets) { self.wallets = wallets }

        func eligibleWalletIds() -> [String] { return wallets.wallets.map { $0.id } }
        func eligibility(walletId: String) -> BILPublicEligibility {
            return wallets.wallets.contains { $0.id == walletId } ? .eligible(.cold) : .notEligible(.unknownWallet)
        }
        func facts(walletId: String) -> BILPublicWalletFacts? { return nil }
        func seed(walletId: String, password: String) -> String? {
            wallets.unlocks += 1
            guard wallets.wallets.contains(where: { $0.id == walletId }), password == CW.password(walletId) else { return nil }
            return CW.seeds[walletId]
        }
        func allWalletIds() throws -> Set<String> { return Set(wallets.wallets.map { $0.id }) }
    }

    @MainActor final class FakeIndex: BILPublicIndexStoring {
        let wallets: FakeWallets
        /// What `prepare` answers for a wallet with a vector seed and the right password.
        var prepareResult: (String) -> BILPublicPrepareResult = { id in .ready(fingerprint: id == CW.LEGAL ? "B8688DF1" : "73C5DA0A") }
        init(_ wallets: FakeWallets) { self.wallets = wallets }

        func status(walletId: String) async -> BILPublicIndexStatus {
            guard let w = wallets.wallets.first(where: { $0.id == walletId }) else { return .notEligible }
            return w.prepared ? .ready(fingerprint: "73C5DA0A") : .missing
        }
        func load(walletId: String) async -> (status: BILPublicIndexStatus, index: BILJSONObject?) {
            let s = await status(walletId: walletId)
            return (s, wallets.wallets.first { $0.id == walletId }?.index)
        }
        func prepare(walletId: String, password: String) async -> BILPublicPrepareResult {
            wallets.prepares += 1
            guard let i = wallets.wallets.firstIndex(where: { $0.id == walletId }) else { return .notEligible }
            guard password == CW.password(walletId), CW.seeds[walletId] != nil else { return .failed(.noSecret, engineCode: nil) }
            let result = prepareResult(walletId)
            if case .ready = result {
                wallets.wallets[i].prepared = true
                wallets.wallets[i].index = walletId == CW.LEGAL ? CW.publicIndex("legal") : CW.publicIndex("abandon")
            }
            return result
        }
        func resolverInputs() async -> [BILJSONObject] {
            return wallets.wallets.map { w in
                var o = BILJSONObject()
                o.set("localWalletId", .string(w.id))
                if w.prepared, let index = w.index { o.set("publicIndex", .object(index)) }
                return o
            }
        }
    }

    // MARK: - Journal and memory

    /// The fields of the app's offline-signing record that these tests check, derived from what the coordinator hands the
    /// journal exactly as the app's `BILPublicSignRecords.of` derived them. Not ported (app code): the coin type, the fee
    /// line (`BILPublicFeeText`) and the counterparty role.
    struct Record {
        let answer: BILPublicAnsweredRequest
        var review: BILPublicReview { return answer.ready.review }
        var plan: BILPublicPlan { return answer.ready.plan }
        var action: String {
            return BILPublicEngineVocabulary.actionId(review.display?.action ?? review.title) ?? "generic"
        }
        var amount: String? { return review.display?.amount }
        var symbol: String? { return review.display?.symbol }
        var recipients: [String] { return review.display?.counterparty.map { [$0] } ?? [] }
        var signer: String? { return plan.tasks.count == 1 ? plan.tasks[0].displayAddresses.first : nil }
        var insight: BILSignatureInsight? { return answer.ready.insight }
        var messagePreview: String? {
            return action == "signMessage" && review.decodeStatus == .fullyDecoded ? review.display?.headline : nil
        }
        var requestKind: String? { return answer.info.transportType }
        var requestDigest: String { return plan.requestHash ?? "" }
        var txId: String? {
            let isTronTransaction = plan.chain == .tron && (answer.request.str("kind").map { BILJSONExact.equal($0, "transaction") } ?? false)
                && action != "verifyOwnership"
            return isTronTransaction ? plan.signingBytesDigest : nil
        }
        var resultKind: String { return answer.response.type }
        var resultFrames: Int { return answer.response.frames.count }
        var signatures: Int { return plan.tasks.count }
        var risk: BILSignatureRisk { return answer.ready.insight?.risk ?? answer.ready.policy.pageRisk }
        var acknowledged: Bool { return answer.ready.policy.requiresAcknowledgement && answer.acknowledged }
        var decode: String { return review.decodeStatus.rawValue }
        var walletIds: [String] { return plan.walletIds }
        var walletCount: Int { return plan.walletIds.count }
        var chain: String? { return plan.chain?.rawValue }
        var createdAtMs: Int64 { return Int64((answer.answeredAt.timeIntervalSince1970 * 1000).rounded(.down)) }
    }

    final class RecordingJournal: BILPublicAnswerJournaling {
        private(set) var records: [Record] = []
        func publicAnswered(_ answer: BILPublicAnsweredRequest) {
            records.append(Record(answer: answer))
        }
    }

    /// A fresh outpoint memory in a temporary folder.
    static func freshMemory() -> BILSignedOutpointMemory {
        return BILSignedOutpointMemory(fileURL: pubTempDir("coordinator-ovc").appendingPathComponent("signed_outpoints.json"))
    }

    /// A memory whose file reads (no conflicts) but whose `record` throws: one unrelated row at the order-stamp limit
    /// (`Int64.max / 2`, WP12 review #1: the next stamp would pass it, so `record` refuses and writes nothing).
    static func memoryWhoseRecordFails() -> BILSignedOutpointMemory {
        let url = pubTempDir("coordinator-ovc-limit").appendingPathComponent("signed_outpoints.json")
        let text = "{\"version\":1,\"rows\":[{\"k\":\"" + String(repeating: "ab", count: 16) + "\",\"t\":\"" + String(repeating: "cd", count: 16)
            + "\",\"s\":" + String(Int64.max / 2) + "}]}"
        try? Data(text.utf8).write(to: url)
        return BILSignedOutpointMemory(fileURL: url)
    }

    /// A memory whose file does not decode (D-30 corrupt: unavailable for the process, never overwritten).
    static func corruptMemory() -> BILSignedOutpointMemory {
        let url = pubTempDir("coordinator-ovc-corrupt").appendingPathComponent("signed_outpoints.json")
        try? Data("not a memory".utf8).write(to: url)
        return BILSignedOutpointMemory(fileURL: url)
    }

    /// Polls `condition` (main actor) every 20 ms for up to `seconds`; true once it holds.
    @MainActor static func waitUntil(seconds: Double = 10, _ condition: () -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while !condition() {
            if Date() > end { return false }
            await blockingWait(seconds: 0.02)
        }
        return true
    }

    // MARK: - TRON (Android PublicSignRound2InstrumentedTest)

    /// The engine-native request of a vector the engine reviewed (TronLink vectors: the mapped request).
    static func reviewedRequest(_ id: String) -> BILJSONObject {
        guard let r = SigningVectors.steps(id, "review").first?.request.obj("request") else {
            print("FAIL no reviewed request in vector \(id)")
            fatalError("harness fixture problem")
        }
        return r
    }

    /// The TRON address the signature of a one-entry TronLink transaction answer recovers to (Android
    /// `ownbitTrxOneIsFoundByItsAddressAndSigns`): the answer's entry = the request's `Transaction` ‖ `12 41` ‖ r ‖ s ‖ v, signed
    /// over sha256(raw_data). nil when the entry is not that shape.
    static func tronLinkSigner(answer: BILPublicResponseQr, request: BILJSONObject) -> String? {
        guard answer.frames.count == 1, let text = BILPublicTronLinkAnswer.scannedText(request),
              let rawHex = BILStrictJSON.parseObject(text)?.arr("hexList")?.first?.stringValue, let raw = BILPublicHex.decode(rawHex),
              let entry = BILStrictJSON.parseObject(answer.frames[0])?.arr("hexList")?.first?.stringValue,
              let signed = BILPublicHex.decode(entry), signed.count == raw.count + 2 + 65,
              Array(signed.prefix(raw.count)) == raw, signed[raw.count] == 0x12, signed[raw.count + 1] == 0x41,
              let rawData = request.obj("transaction")?.str("raw_data_hex").flatMap(BILPublicHex.decode) else { return nil }
        let sig = Array(signed.suffix(65))
        let v = Int(sig[64])
        guard let pub = BILSecp256k1.recoverPublicKey(digest: BILPublicHash.sha256(rawData), recId: v >= 27 ? v - 27 : v,
                                                      r: Array(sig[0..<32]), s: Array(sig[32..<64])) else { return nil }
        return BILPublicSignVerifier.tronAddress(uncompressed: pub)
    }

    /// The PSBT maps of a vector Bitcoin request (`request.psbt`, Base64).
    static func psbtMaps(_ request: BILJSONObject) -> BILPsbtMaps {
        guard let text = request.str("psbt"), let bytes = BILBase64Strict.decode(text), let maps = try? BILPsbtMaps.parse(bytes) else {
            print("FAIL request PSBT does not parse")
            fatalError("harness fixture problem")
        }
        return maps
    }

    // MARK: - Test environment

    /// A coordinator over the golden engine, the fake wallets / index, a recording journal and (by default) a fresh memory.
    @MainActor final class Env {
        let engine = ReplayEngine()
        let wallets = FakeWallets()
        lazy var directory = FakeDirectory(wallets)
        lazy var index = FakeIndex(wallets)
        let journal = RecordingJournal()
        var now = Date(timeIntervalSince1970: 1_760_000_000)
        var interpreted: [BILSignatureRequest] = []
        var insightProvider: ((BILSignatureRequest) -> BILSignatureInsight?)?

        func coordinator(memory: BILSignedOutpointMemory? = freshMemory(), journal: BILPublicAnswerJournaling? = nil,
                         timeout: TimeInterval = BILPublicSignCoordinator.signTimeout,
                         byteCount: ((BILJSONObject, [BILJSONObject]) -> Int)? = nil) -> BILPublicSignCoordinator {
            let deps = BILPublicSignCoordinator.Dependencies(
                engine: engine,
                index: index,
                wallets: directory,
                memory: memory,
                journal: journal ?? self.journal,
                interpret: { [unowned self] request in
                    self.interpreted.append(request)
                    return self.insightProvider?(request) ?? realInsight(request)
                },
                requestByteCount: byteCount ?? { BILPublicSignerEngine.resolveRequestByteCount(request: $0, wallets: $1) },
                now: { [unowned self] in self.now },
                signTimeout: timeout)
            return BILPublicSignCoordinator(deps)
        }
    }

    /// The app ran the real D43 interpreter (Security Center, with the bundled known-contract library) here. The
    /// interpreter is host code, not part of the package: no card unless a test installs `Env.insightProvider`.
    static func realInsight(_ request: BILSignatureRequest) -> BILSignatureInsight? {
        return nil
    }

    /// A stand-in card for the coordinator's D43 plumbing: a known contract (yellow) at `risk`.
    static func stubInsight(risk: BILSignatureRisk = .medium) -> BILSignatureInsight {
        return BILSignatureInsight(kind: BILSignatureKind.tokenTransfer.rawValue, risk: risk, title: BILSCText("SecurityCenter.t"),
                                   summary: BILSCText("SecurityCenter.s"), facts: [], warnings: [],
                                   contract: BILContractRef(address: "0xdac17f958d2ee523a2206206994597c13d831ec7", chain: "eip155:1",
                                                            role: "token", knownName: "Tether USD"),
                                   explain: [], standard: "ERC-20", functionSignature: "transfer(address,uint256)", steps: nil)
    }
}
