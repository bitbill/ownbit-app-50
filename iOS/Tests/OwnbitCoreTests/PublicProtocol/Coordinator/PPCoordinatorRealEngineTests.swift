//  PPCoordinatorRealEngineTests.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Port of the app harness suite `scripts/public-protocol/tests/coordinator` (RealEngineTests.swift) to XCTest.
//
//  RealEngineTests.swift — suite "coordinator" (WP19): a few end-to-end flows through the coordinator with the **real**
//  engine host (WP7's `BILPublicSignerEngine` over the pinned signer.js, `PUB_SIGNER_JS`) instead of the recorded
//  answers: matching, the native pre-check, signing with the vector wallets' seeds and the native post-check — the answer
//  frames must equal the golden vectors (deterministic signatures). Plus the resolver byte count of the real request
//  builder, Ownbit's TRX #1 by address / by path (Android PublicSignRound2InstrumentedTest), and two Bitcoin requests that
//  claim different amounts for one outpoint signed at the same time (check → sign → record under one lock, R2-2).
//

import Foundation
import XCTest
@testable import OwnbitCore

extension PPCoordinatorSuite {

    @MainActor static func realEngineTests() async {
        section("real engine")
        // The harness took `PUB_SIGNER_JS`; here the package's js/pubsigner-lib-bridge/signer.js (SHA-pinned).
        guard let url = signerJSURL() else { t(false, "js/pubsigner-lib-bridge/signer.js present"); return }
        let engine = BILPublicSignerEngine(sourceURL: url, pinned: true)
        let available = await engine.isAvailable()
        t(available, "the pinned engine runs")
        guard available else { return }

        // The byte count is the UTF-8 size of the request text the engine builds.
        let request = SigningVectors.request("T8-flow-evm-eip1559")
        let wallets = [BILJSONObject([("localWalletId", .string(CW.ABANDON)), ("publicIndex", .object(CW.publicIndex("abandon")))])]
        let expected = BILStrictJSON.serialize(BILJSONObject([("operation", .string("resolve" + "SigningPlan")), ("request", .object(request)),
                                                              ("wallets", .array(wallets.map { .object($0) }))]))
        eq(BILPublicSignerEngine.resolveRequestByteCount(request: request, wallets: wallets), expected.utf8.count,
           "resolveRequestByteCount = the UTF-8 size of the resolver request")

        for id in ["T8-flow-evm-eip1559", "T8-flow-bitcoin-crypto-psbt", "O-BTC-6-segwit-witness-only", "T8-flow-solana-transfer",
                   "T8-flow-tron-trc20-transfer"] {
            await realFlow(engine, id, input: .frames(SigningVectors.request(id)), expected: SigningVectors.response(id).frames)
        }
        await realFlow(engine, "T8-flow-psbt-two-wallets", input: .frames(SigningVectors.request("T8-flow-psbt-two-wallets")),
                       expected: SigningVectors.response("T8-flow-psbt-two-wallets").frames, legal: true)
        await realFlow(engine, "TronLink V3", input: .pasted(OtherWalletVectors.V3_REQUEST), expected: [OtherWalletVectors.V3_ANSWER])
        await realFlow(engine, "TronLink V4", input: .pasted(OtherWalletVectors.V4_REQUEST), expected: [OtherWalletVectors.V4_ANSWER])
        await ownbitTrxOneReal(engine)
        await bitcoinConflictUnderOneLock(engine)
    }

    /// A coordinator over `engine`, the fake wallets / index of `env`, a fresh (or the given) memory and `env`'s journal.
    @MainActor private static func realCoordinator(_ engine: BILPublicSignerEngining, _ env: Env,
                                            memory: BILSignedOutpointMemory = freshMemory()) -> BILPublicSignCoordinator {
        let deps = BILPublicSignCoordinator.Dependencies(
            engine: engine, index: env.index, wallets: env.directory, memory: memory, journal: env.journal,
            interpret: { realInsight($0) },
            requestByteCount: { BILPublicSignerEngine.resolveRequestByteCount(request: $0, wallets: $1) },
            now: { Date() })
        return BILPublicSignCoordinator(deps)
    }

    @MainActor private static func realFlow(_ engine: BILPublicSignerEngine, _ what: String, input: BILPublicInput, expected: [String],
                                     legal: Bool = false, index: String = "abandon") async {
        let env = Env()
        env.wallets.add(CW.ABANDON, index: CW.publicIndex(index))
        if legal { env.wallets.add(CW.LEGAL) }
        let c = realCoordinator(engine, env)
        guard let id = try? await c.prepare(input) else { t(false, "\(what): prepared"); return }
        guard case .ready(let ready) = c.state(id) else { t(false, "\(what): ready, got \(stateName(c.state(id)))"); return }
        var task = ready.nextTask
        while let next = task {
            let o = await c.signTask(id, taskId: next.id, password: CW.password(next.localWalletId),
                                     riskAcknowledged: ready.policy.requiresAcknowledgement)
            guard case .signed(_, let following) = o else { t(false, "\(what): signed, got \(o)"); return }
            task = following.flatMap { f in ready.plan.tasks.first { $0.id == f } }
        }
        guard case .answered(_, _, _, let response) = c.state(id) else { t(false, "\(what): answered"); return }
        eq(response.frames, expected, "\(what): real engine answer = the golden answer (post-checked natively)")
        eq(env.journal.records.count, 1, "\(what): one record")
    }

    /// Android `ownbitTrxOneIsFoundByItsAddressAndSigns` on the real engine: the address-only TronLink request (O-TRX-2) is
    /// matched to the wallet whose index has the Ownbit TRON scheme and signs with TRX #1 (the answer = the native TronLink
    /// answer of the vector's signature, which recovers to TRX #1); the path request O-TRX-3 answers the vector's frames; the
    /// round-1 standard index has no TRX #1 (O-TRX-2-standard-index-no-match).
    @MainActor private static func ownbitTrxOneReal(_ engine: BILPublicSignerEngine) async {
        let id2 = "O-TRX-2-ownbit-scheme-address-only"
        let mapped = reviewedRequest(id2)
        guard let text = BILPublicTronLinkAnswer.scannedText(mapped),
              let signature = SigningVectors.signResults(id2).first?.str("signature").flatMap(BILPublicHex.decode),
              let golden = try? BILPublicTronLinkAnswer.response(request: mapped, verified: SigningVectors.verified(id2, request: mapped),
                                                                signature: signature) else {
            t(false, "O-TRX-2 golden answer")
            return
        }
        eq(tronLinkSigner(answer: golden, request: mapped), CW.TRX_OWNBIT_1, "O-TRX-2: the vector signature recovers to TRX #1")
        await realFlow(engine, "O-TRX-2 (TRX #1 by address, TronLink)", input: .pasted(text), expected: golden.frames, index: "abandonOwnbit")
        await realFlow(engine, "O-TRX-3 (TRX #1 by path)", input: .frames(SigningVectors.request("O-TRX-3-ownbit-scheme-path-request")),
                       expected: SigningVectors.response("O-TRX-3-ownbit-scheme-path-request").frames, index: "abandonOwnbit")
        let env = Env()
        env.wallets.add(CW.ABANDON)
        let c = realCoordinator(engine, env)
        guard let id = try? await c.prepare(.pasted(text)) else { t(false, "O-TRX-2 standard index: prepared"); return }
        if case .notReady(_, .noMatch, _, _, _) = c.state(id) {
            t(true, "O-TRX-2 with the standard index: no match")
        } else {
            t(false, "O-TRX-2 with the standard index: noMatch expected, got \(stateName(c.state(id)))")
        }
    }

    /// R2-2 / S§8.1 (Android `witnessOnlySegwitSignsIsRememberedAndAConflictIsRefused` + the round-2 concurrency test): A =
    /// O-BTC-6 as vectored, B = the same PSBT whose input 0 claims one satoshi more (`01011f ‖ u64le(amount)`), both pasted
    /// as Base64 and both Ready on an empty memory. A signs (held at the engine); B is started meanwhile. B must check the
    /// memory only after A recorded its amounts — so B is refused (`err.prevoutConflict`, input 1) and never signed. Checking
    /// outside the shared lock (B checks while A signs, then waits only for the signing) would sign B.
    @MainActor private static func bitcoinConflictUnderOneLock(_ engine: BILPublicSignerEngine) async {
        section("real engine: two amounts for one outpoint — check → sign → record under one lock")
        let request = SigningVectors.request("O-BTC-6-segwit-witness-only")
        let maps = psbtMaps(request)
        guard let text = request.str("psbt"), let bytes = BILBase64Strict.decode(text), let claimed = maps.claimedAmount(0),
              let outpoint = maps.outpoint(0) else { t(false, "O-BTC-6 PSBT"); return }
        let hex = BILPublicHex.encode(bytes)
        let pattern = "01011f" + le64Hex(claimed)
        guard hex.components(separatedBy: pattern).count == 2, let range = hex.range(of: pattern),
              let lyingBytes = BILPublicHex.decode(hex.replacingCharacters(in: range, with: "01011f" + le64Hex(claimed + 1))) else {
            t(false, "exactly one witness UTXO of input 0's amount")
            return
        }
        let lying = Data(lyingBytes).base64EncodedString()
        let gated = GatedEngine(engine)
        let env = Env()
        env.wallets.add(CW.ABANDON)
        let memory = freshMemory()
        let c = realCoordinator(gated, env, memory: memory)
        guard let a = try? await c.prepare(.pasted(text)), case .ready(let ra) = c.state(a), let taskA = ra.plan.tasks.first else {
            t(false, "A ready")
            return
        }
        guard let b = try? await c.prepare(.pasted(lying)) else { t(false, "B prepared"); return }
        guard case .ready(let rb) = c.state(b), let taskB = rb.plan.tasks.first else {
            t(false, "B ready on an empty memory, got \(stateName(c.state(b)))")
            return
        }
        let lyingClaim = BILSignedOutpointMemory.Claim(txid: outpoint.txid, vout: outpoint.vout, sats: claimed + 1)
        eq((try? memory.conflicts([lyingClaim])) ?? [-1], [], "nothing remembered yet")

        let first = Task { @MainActor in await c.signTask(a, taskId: taskA.id, password: CW.PASSWORD, riskAcknowledged: true) }
        let aSigning = await waitUntil { gated.signCount == 1 }
        t(aSigning, "A is signing (held at the engine)")
        let second = Task { @MainActor in await c.signTask(b, taskId: taskB.id, password: CW.PASSWORD, riskAcknowledged: true) }
        let bQueued = await waitUntil { BILBitcoinSigningLock.shared.queuedCount == 1 }
        await blockingWait(seconds: 0.3)            // B would check (and pass) now if it were not serialized behind A
        t(bQueued && BILBitcoinSigningLock.shared.queuedCount == 1, "B waits on the shared Bitcoin lock while A holds it")
        eq(gated.signCount, 1, "only A reached the engine")
        gated.gate.open()
        let oa = await first.value
        let ob = await second.value
        eq(oa, .signed(taskId: taskA.id, nextTaskId: nil), "A signed and answered")
        eq(failedError(ob)?.code, "PREVOUT_CONFLICT", "B checked after A recorded: PREVOUT_CONFLICT")
        eq(failedError(ob)?.key, "PublicProtocol.err.prevoutConflict", "err.prevoutConflict")
        eq(failedError(ob)?.args ?? [], [.int(1)], "input 1")
        eq(refusedState(c, b)?.again, false, "B refused, no Match again")
        eq(gated.signCount, 1, "B never reached the engine")
        eq(env.wallets.unlocks, 1, "only A's wallet was unlocked")
        eq(env.journal.records.count, 1, "one answer, one record")
        eq((try? memory.conflicts([lyingClaim])) ?? [-1], [0], "A's amount is remembered")
    }

    /// `v` as 8 little-endian bytes, lower-case hex.
    private static func le64Hex(_ v: UInt64) -> String {
        return BILPublicHex.encode((0..<8).map { UInt8(truncatingIfNeeded: v >> (8 * UInt64($0))) })
    }

    /// The real engine with a count of `signPlanTask` calls; the first one waits for `gate` before it reaches the engine.
    final class GatedEngine: BILPublicSignerEngining {
        let inner: BILPublicSignerEngining
        let gate = Gate()
        private let lock = NSLock()
        private var signs = 0

        init(_ inner: BILPublicSignerEngining) {
            self.inner = inner
        }

        var signCount: Int {
            lock.lock()
            defer { lock.unlock() }
            return signs
        }

        func signPlanTask(request: BILJSONObject, plan: BILJSONObject, taskId: String, seedHex: String,
                          riskAcknowledged: Bool, previousResult: BILJSONObject?) async throws -> BILJSONObject {
            lock.lock()
            signs += 1
            let first = signs == 1
            lock.unlock()
            if first { await gate.wait() }
            return try await inner.signPlanTask(request: request, plan: plan, taskId: taskId, seedHex: seedHex,
                                                riskAcknowledged: riskAcknowledged, previousResult: previousResult)
        }

        func capabilities() async throws -> BILJSONObject { return try await inner.capabilities() }
        func derivePublicAddresses(publicIndex: BILJSONObject, chain: String, profile: String?, start: Int, count: Int) async throws -> BILJSONObject {
            return try await inner.derivePublicAddresses(publicIndex: publicIndex, chain: chain, profile: profile, start: start, count: count)
        }
        func createPublicPairing(publicIndex: BILJSONObject, chain: String, profile: String?, outputMode: String?, index: Int) async throws -> BILJSONObject {
            return try await inner.createPublicPairing(publicIndex: publicIndex, chain: chain, profile: profile, outputMode: outputMode, index: index)
        }
        func releasePairingContext() async { await inner.releasePairingContext() }
        func derivePublicIndex(seedHex: String, tronScheme: String?, tronAddressCount: Int?) async throws -> BILJSONObject {
            return try await inner.derivePublicIndex(seedHex: seedHex, tronScheme: tronScheme, tronAddressCount: tronAddressCount)
        }
        func refreshPublicIndex(publicIndex: BILJSONObject, tronScheme: String, tronAddressCount: Int?) async throws -> BILJSONObject {
            return try await inner.refreshPublicIndex(publicIndex: publicIndex, tronScheme: tronScheme, tronAddressCount: tronAddressCount)
        }
        func decodePayload(_ payload: String) async throws -> BILJSONObject { return try await inner.decodePayload(payload) }
        func reviewAndResolve(request: BILJSONObject, wallets: [BILJSONObject]) async throws -> BILPublicReviewAndPlan {
            return try await inner.reviewAndResolve(request: request, wallets: wallets)
        }
        func encodeResponse(request: BILJSONObject, result: BILJSONObject) async throws -> BILJSONObject {
            return try await inner.encodeResponse(request: request, result: result)
        }
        func openScan() async throws -> BILPublicScanHandle { return try await inner.openScan() }
        func scanAdd(_ handle: BILPublicScanHandle, frame: String) async throws -> BILJSONObject { return try await inner.scanAdd(handle, frame: frame) }
        func closeScan(_ handle: BILPublicScanHandle) async { await inner.closeScan(handle) }
        func isAvailable() async -> Bool { return await inner.isAvailable() }
    }
}
