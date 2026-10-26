//  PPCoordinatorRound2Tests.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Port of the app harness suite `scripts/public-protocol/tests/coordinator` (Round2Tests.swift) to XCTest.
//
//  Round2Tests.swift — suite "coordinator" (WP19): ports of Android PST:sign/PublicSignCoordinatorRound2Test.kt and
//  PublicSignCoordinatorJournalTest.kt — TronLink V1 / V3 / V4 answered natively byte for byte (no `encodeResponse`),
//  pasted TronLink texts and TokenPocket refusals, the signed-outpoint memory of witness-only SegWit inputs (incl. the
//  D-30 answer-step write failure, an unavailable memory at prepare, and serialized Bitcoin signing), and the
//  offline-signing journal (exactly once per handed-out answer; never changes the outcome).
//

import Foundation
import XCTest
@testable import OwnbitCore

extension PPCoordinatorSuite {

    @MainActor static func round2Tests() async {
        await tronLinkV1()
        await tronLinkV3V4()
        await pastedOtherWallets()
        await ownbitTrxOne()
        await witnessOnly()
        await conflictAfterMatching()
        await bitcoinOneAtATime()
        await noMemory()
        await memoryRecordFailure()
        await journalTests()
    }

    /// A TronLink request scanned through the real scan session (its collector + mapper; no engine involved).
    @MainActor private static func scanned(_ engine: ReplayEngine, _ text: String) async -> BILPublicInput? {
        let session = BILPublicScanSession(engine: engine)
        do {
            let progress = try await session.add(text)
            guard progress.complete, let request = progress.request else {
                t(false, "the scan session completed the TronLink request")
                return nil
            }
            return .frames(request)
        } catch {
            t(false, "scan refused: \(error)")
            return nil
        }
    }

    @MainActor private static func signOnly(_ c: BILPublicSignCoordinator, _ id: String, ack: Bool = false, _ what: String) async -> BILPublicResponseQr? {
        guard case .ready(let ready) = c.state(id), let task = ready.plan.tasks.first else {
            t(false, "\(what): ready, got \(stateName(c.state(id)))")
            return nil
        }
        let o = await c.signTask(id, taskId: task.id, password: CW.PASSWORD, riskAcknowledged: ack)
        eq(o, .signed(taskId: task.id, nextTaskId: nil), "\(what): signed")
        if case .answered(_, _, _, let response) = c.state(id) { return response }
        t(false, "\(what): answered, got \(stateName(c.state(id)))")
        return nil
    }

    @MainActor private static func tronLinkV1() async {
        section("TronLink V1 ownership check")
        let env = Env()
        env.wallets.add(CW.ABANDON)
        let c = env.coordinator()
        guard let input = await scanned(env.engine, OtherWalletVectors.V1_REQUEST), let id = try? await c.prepare(input),
              case .ready(let ready) = c.state(id) else { t(false, "V1 ready"); return }
        eq(ready.info.transportType, "tronlink", "transport tronlink")
        eq(ready.review.display?.action, "Verify Ownership", "action")
        t(!ready.policy.requiresAcknowledgement, "owner R2-7: no checkbox for the fixed placeholder")
        t(ready.insight == nil, "no D43 card")
        guard let response = await signOnly(c, id, "V1") else { return }
        eq(response.frames, [OtherWalletVectors.V1_ANSWER], "answered byte for byte")
        eq(response.type, "tronlink", "type tronlink")
        t(!response.signedTransaction, "not a signed transaction")
        t(!env.engine.log.contains("encodeResponse"), "the TronLink answer is built natively")
        guard let r = env.journal.records.first, env.journal.records.count == 1 else { t(false, "one record"); return }
        eq(r.action, "verifyOwnership", "record action")
        eq(r.resultKind, "tronlink", "record result kind")
        eq(r.requestKind, "tronlink", "record request kind")
        t(r.txId == nil, "the placeholder's hash is not a transaction id")
        eq(r.walletIds, [CW.ABANDON], "record wallets")
        eq(r.chain, "tron", "record chain")
    }

    @MainActor private static func tronLinkV3V4() async {
        section("TronLink V3 transfer and V4 TIP-191 message")
        let env = Env()
        env.wallets.add(CW.ABANDON)
        let c = env.coordinator()
        guard let v3in = await scanned(env.engine, OtherWalletVectors.V3_REQUEST), let v3 = try? await c.prepare(v3in),
              let tx = await signOnly(c, v3, "V3") else { return }
        eq(tx.frames, [OtherWalletVectors.V3_ANSWER], "V3 answer")
        t(tx.signedTransaction, "a signed transaction")
        guard let r3 = env.journal.records.last else { t(false, "V3 record"); return }
        eq(r3.txId, "21b3521910cf55ece01973626b70e23d398d9aca8cddf00730e2c9076004723c", "record txId = the TRON txID")
        eq([r3.action, r3.amount ?? "-", r3.symbol ?? "-"], ["send", "1", "TRX"], "send 1 TRX")
        eq(r3.requestDigest, SigningVectors.plan("O-TL-V3-trx-transfer").requestHash ?? "", "digest = requestHash")
        t(r3.messagePreview == nil, "no message preview for a transfer")
        t(!r3.acknowledged, "not acknowledged (no checkbox)")
        eq(r3.signer, OtherWalletVectors.TRON_0, "the single task's signing address")
        eq(r3.recipients.count, 1, "one counterparty")
        eq(r3.decode, "fullyDecoded", "decode status")

        guard let v4in = await scanned(env.engine, OtherWalletVectors.V4_REQUEST), let v4 = try? await c.prepare(v4in),
              case .ready(let r4ready) = c.state(v4) else { t(false, "V4 ready"); return }
        t(r4ready.policy.requiresAcknowledgement, "a message is high risk")
        guard let message = await signOnly(c, v4, ack: true, "V4") else { return }
        eq(message.frames, [OtherWalletVectors.V4_ANSWER], "V4 answer")
        guard let r4 = env.journal.records.last else { t(false, "V4 record"); return }
        eq([r4.action, r4.messagePreview ?? "-"], ["signMessage", "hello ownbit"], "signMessage / preview")
        t(r4.acknowledged, "acknowledged")
        eq(env.journal.records.count, 2, "two records")
        t(!env.engine.log.contains("encodeResponse"), "encodeResponse never called for TronLink")
    }

    @MainActor private static func pastedOtherWallets() async {
        section("pasted TronLink texts; every TokenPocket text refused before the engine")
        let env = Env()
        env.wallets.add(CW.ABANDON)
        let c = env.coordinator()
        func state(_ text: String) async -> String {
            guard let id = try? await c.prepare(.pasted(text)) else { return "prepare failed" }
            return stateName(c.state(id))
        }
        let v3 = await state(OtherWalletVectors.V3_REQUEST)
        eq(v3, "ready", "a pasted TronLink request")
        let pretty = await state(OtherWalletVectors.V1_REQUEST.replacingOccurrences(of: ",", with: ",\n  "))
        eq(pretty, "ready", "a pretty-printed TronLink object")
        func refused(_ text: String) async -> BILPublicSignError? {
            do {
                _ = try await c.prepare(.pasted(text))
                return nil
            } catch let e as BILPublicPrepareError {
                return e.error
            } catch {
                return nil
            }
        }
        let calls = env.engine.log.count
        var texts = [OtherWalletVectors.tpRequestFrames.joined(separator: "\n"),
                     OtherWalletVectors.tpRequestFrames.dropFirst().joined(separator: "\n"),
                     OtherWalletVectors.tpRequest,
                     OtherWalletVectors.TP_ANSWER_HEADER,
                     #"{"action":"coldWalletSign","signType":"tronSignTx","sign":"ab"}"#]
        t(!OtherWalletVectors.tpRequestFrames.isEmpty, "tp-v1 frames")
        for text in texts {
            let e = await refused(text)
            eq(e?.key, "PublicProtocol.err.tpUnsupported", "TokenPocket text refused (\(text.prefix(30)))")
            eq(e?.code, "TP_UNSUPPORTED", "code TP_UNSUPPORTED")
        }
        texts.removeAll()
        eq(env.engine.log.count, calls, "no TokenPocket text reaches the engine")
        let blind = await refused(#"{"address":"\#(OtherWalletVectors.TRON_0)","type":101,"hexList":["\#(String(repeating: "ab", count: 32))"]}"#)
        eq(blind?.key, "PublicProtocol.err.tronlinkBlindHash", "type 101 → err.tronlinkBlindHash")
        let incomplete = await refused(#"{"address":"\#(OtherWalletVectors.TRON_0)","cN":1,"hexList":["0a"],"tN":2,"type":0}"#)
        eq(incomplete?.code, "INCOMPLETE", "an incomplete split request → err.qrMalformed / INCOMPLETE")
        eq(c.store.count, 2, "only the two TronLink requests were stored")
    }

    /// Android PublicSignRound2InstrumentedTest.ownbitTrxOneIsFoundByItsAddressAndSigns (O-TRX-2: a TronLink TRX transfer from
    /// Ownbit's TRX #1, address only) and the path form O-TRX-3, on the wallet whose index has the Ownbit TRON scheme.
    @MainActor private static func ownbitTrxOne() async {
        section("Ownbit TRX #1 found by its address (O-TRX-2, TronLink) and by its path (O-TRX-3)")
        let env = Env()
        env.wallets.add(CW.ABANDON, index: CW.publicIndex("abandonOwnbit"))
        let c = env.coordinator()
        let mapped = reviewedRequest("O-TRX-2-ownbit-scheme-address-only")
        guard let text = BILPublicTronLinkAnswer.scannedText(mapped) else { t(false, "O-TRX-2 TronLink text"); return }
        eq(tronLinkRequest(text), mapped, "the pasted TronLink text maps to the reviewed request")
        guard let id = try? await c.prepare(.pasted(text)), case .ready(let ready) = c.state(id) else {
            t(false, "O-TRX-2 ready")
            return
        }
        eq(ready.plan.tasks.map { $0.localWalletId }, [CW.ABANDON], "one task, the Ownbit-scheme wallet")
        t(ready.plan.tasks.first?.addresses.contains(CW.TRX_OWNBIT_1) == true, "the task signs for TRX #1")
        guard let answer = await signOnly(c, id, ack: ready.policy.requiresAcknowledgement, "O-TRX-2") else { return }
        t(answer.isTronLink && answer.signedTransaction, "a TronLink signed transaction")
        eq(tronLinkSigner(answer: answer, request: mapped), CW.TRX_OWNBIT_1, "the answer's signature recovers to TRX #1")
        t(!env.engine.log.contains("encodeResponse"), "answered natively")

        let path = SigningVectors.request("O-TRX-3-ownbit-scheme-path-request")
        guard let id3 = try? await c.prepare(.frames(path)), case .ready(let r3) = c.state(id3) else { t(false, "O-TRX-3 ready"); return }
        t(r3.plan.tasks.count == 1 && r3.plan.tasks.first?.addresses.contains(CW.TRX_OWNBIT_1) == true, "O-TRX-3: TRX #1 by its path")
        guard let answer3 = await signOnly(c, id3, ack: r3.policy.requiresAcknowledgement, "O-TRX-3") else { return }
        eq(answer3.frames, SigningVectors.response("O-TRX-3-ownbit-scheme-path-request").frames, "O-TRX-3: answer frames = the vector's")
        eq(env.journal.records.count, 2, "two records")
        eq(env.journal.records.first?.signer, CW.TRX_OWNBIT_1, "record signer = TRX #1")
    }

    @MainActor private static func witnessOnly() async {
        section("witness-only SegWit inputs")
        let env = Env()
        env.wallets.add(CW.ABANDON)
        let memory = freshMemory()
        let c = env.coordinator(memory: memory)
        let request = SigningVectors.request("O-BTC-6-segwit-witness-only")
        guard let first = try? await c.prepare(.frames(request)), case .ready(let ready) = c.state(first) else { t(false, "ready"); return }
        t(ready.review.warnings.contains { $0.hasPrefix("Input amounts of SegWit v0 inputs") }, "the witness-only warning is shown")
        guard let response = await signOnly(c, first, ack: ready.policy.requiresAcknowledgement, "O-BTC-6") else { return }
        eq(response.frames, SigningVectors.response("O-BTC-6-segwit-witness-only").frames, "answer frames = the vector's")
        let maps = psbtMaps(request)
        eq((try? memory.conflicts(maps.outpointClaims())) ?? [-1], [], "the same amounts again: no conflict")
        guard let second = try? await c.prepare(.frames(request)) else { t(false, "again"); return }
        eq(stateName(c.state(second)), "ready", "re-prepare is Ready")
        // Another request claimed another amount for the same coins earlier: hard refusal.
        guard let outpoint = maps.outpoint(0), let amount = maps.claimedAmount(0) else { t(false, "claim"); return }
        try? memory.record([BILSignedOutpointMemory.Claim(txid: outpoint.txid, vout: outpoint.vout, sats: amount + 1)])
        guard let third = try? await c.prepare(.frames(request)), let refused = refusedState(c, third) else { t(false, "refused"); return }
        eq(refused.error.code, "PREVOUT_CONFLICT", "PREVOUT_CONFLICT")
        eq(refused.error.key, "PublicProtocol.err.prevoutConflict", "err.prevoutConflict")
        eq(refused.error.args, [.int(1)], "input 1")
        t(!refused.again, "no Match again, no checkbox bypass")
    }

    @MainActor private static func conflictAfterMatching() async {
        section("a conflict that appears after matching is refused at signing")
        let env = Env()
        env.wallets.add(CW.ABANDON)
        let memory = freshMemory()
        let c = env.coordinator(memory: memory)
        let request = SigningVectors.request("O-BTC-6-segwit-witness-only")
        guard let id = try? await c.prepare(.frames(request)), case .ready(let ready) = c.state(id), let task = ready.plan.tasks.first else {
            t(false, "ready")
            return
        }
        let maps = psbtMaps(request)
        guard let outpoint = maps.outpoint(0) else { t(false, "outpoint"); return }
        try? memory.record([BILSignedOutpointMemory.Claim(txid: outpoint.txid, vout: outpoint.vout, sats: 1)])
        let o = await c.signTask(id, taskId: task.id, password: CW.PASSWORD, riskAcknowledged: true)
        eq(failedError(o)?.code, "PREVOUT_CONFLICT", "refused at signing")
        eq(env.wallets.unlocks, 0, "nothing unlocked")
        t(env.journal.records.isEmpty, "nothing answered, nothing recorded")
        t(!env.engine.log.contains { $0.hasPrefix("signPlanTask") }, "the engine never signed")
    }

    @MainActor private static func bitcoinOneAtATime() async {
        section("Bitcoin requests sign one at a time (check → sign → record)")
        let env = Env()
        env.wallets.add(CW.ABANDON)
        let memory = freshMemory()
        let c = env.coordinator(memory: memory)
        let request = SigningVectors.request("O-BTC-6-segwit-witness-only")
        let maps = psbtMaps(request)
        guard let a = try? await c.prepare(.frames(request)), let b = try? await c.prepare(.frames(request)),
              case .ready(let ra) = c.state(a), case .ready(let rb) = c.state(b),
              let taskA = ra.plan.tasks.first, let taskB = rb.plan.tasks.first,
              let outpoint = maps.outpoint(0), let amount = maps.claimedAmount(0) else { t(false, "two ready requests"); return }
        env.engine.clearLog()
        let gate = Gate()
        var events: [String] = []
        var recordedBeforeB: Bool?
        var signs = 0
        env.engine.signHook = { _ in
            signs += 1
            if signs == 1 {
                events.append("sign A")
                await gate.wait()
            } else {
                events.append("sign B")
                // A's outpoints are remembered before B is even checked: another amount for them conflicts now.
                let conflict = try? memory.conflicts([BILSignedOutpointMemory.Claim(txid: outpoint.txid, vout: outpoint.vout, sats: amount + 1)])
                recordedBeforeB = conflict == [0]
            }
        }
        let first = Task { @MainActor in await c.signTask(a, taskId: taskA.id, password: CW.PASSWORD, riskAcknowledged: true) }
        while events.isEmpty { await blockingWait(seconds: 0.02) }
        let second = Task { @MainActor in await c.signTask(b, taskId: taskB.id, password: CW.PASSWORD, riskAcknowledged: true) }
        await blockingWait(seconds: 0.5)            // B would check and sign now if nothing serialized it
        eq(events, ["sign A"], "B waits while A holds the Bitcoin signing lock")
        eq(BILBitcoinSigningLock.shared.queuedCount, 1, "B is queued on the shared lock")
        gate.open()
        let oa = await first.value
        let ob = await second.value
        eq(oa, .signed(taskId: taskA.id, nextTaskId: nil), "A signed")
        eq(ob, .signed(taskId: taskB.id, nextTaskId: nil), "B signed (same amounts: no conflict)")
        eq(events, ["sign A", "sign B"], "one after the other")
        eq(recordedBeforeB, true, "A's record happened before B's check and sign")
        eq(env.journal.records.count, 2, "two answers, two records")
    }

    /// A one-shot latch.
    final class Gate {
        private let lock = NSLock()
        private var opened = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func wait() async {
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                lock.lock()
                if opened {
                    lock.unlock()
                    c.resume()
                } else {
                    waiters.append(c)
                    lock.unlock()
                }
            }
        }

        func open() {
            lock.lock()
            opened = true
            let all = waiters
            waiters.removeAll()
            lock.unlock()
            all.forEach { $0.resume() }
        }
    }

    @MainActor private static func noMemory() async {
        section("the warning promises the memory: without it witness-only inputs are refused")
        for (what, memory) in [("no memory", nil), ("corrupt memory", corruptMemory())] as [(String, BILSignedOutpointMemory?)] {
            let env = Env()
            env.wallets.add(CW.ABANDON)
            let c = env.coordinator(memory: memory)
            guard let id = try? await c.prepare(frames2("O-BTC-6-segwit-witness-only")) else { t(false, what); return }
            eq(refusedState(c, id)?.error.code, "INTEGRITY", "\(what): witness-only → err.integrity")
            eq(refusedState(c, id)?.error.key, "PublicProtocol.err.integrity", "\(what): err.integrity")
            guard let full = try? await c.prepare(frames2("T8-flow-bitcoin-crypto-psbt")), case .ready(let ready) = c.state(full) else {
                t(false, "\(what): a PSBT with its previous transactions is Ready")
                return
            }
            t(true, "\(what): a PSBT with its previous transactions does not need it")
            guard let response = await signOnly(c, full, ack: ready.policy.requiresAcknowledgement, "\(what) full prev tx") else { continue }
            eq(response.frames, SigningVectors.response("T8-flow-bitcoin-crypto-psbt").frames, "\(what): answered (amounts locked by the signature)")
            eq(env.journal.records.count, 1, "\(what): one record")
        }
        if let corrupt = Optional(corruptMemory()) {
            t(!corrupt.isAvailable, "a corrupt memory is unavailable")
            let bytes = try? Data(contentsOf: corrupt.fileURL)
            let env = Env()
            env.wallets.add(CW.ABANDON)
            let c = env.coordinator(memory: corrupt)
            if let full = try? await c.prepare(frames2("T8-flow-bitcoin-crypto-psbt")), case .ready(let r) = c.state(full) {
                _ = await signOnly(c, full, ack: r.policy.requiresAcknowledgement, "corrupt memory, full prev tx")
            }
            eq(try? Data(contentsOf: corrupt.fileURL), bytes, "a corrupt file is never overwritten")
        }
    }

    private static func frames2(_ id: String) -> BILPublicInput {
        return .frames(SigningVectors.request(id))
    }

    @MainActor private static func memoryRecordFailure() async {
        section("outpoint memory failure at the answer step (S§8.1 ①, D-30)")
        let env = Env()
        env.wallets.add(CW.ABANDON)
        let memory = memoryWhoseRecordFails()
        t(memory.isAvailable, "the memory reads")
        let c = env.coordinator(memory: memory)
        guard let id = try? await c.prepare(frames2("O-BTC-6-segwit-witness-only")), case .ready(let ready) = c.state(id),
              let task = ready.plan.tasks.first else { t(false, "ready"); return }
        let o = await c.signTask(id, taskId: task.id, password: CW.PASSWORD, riskAcknowledged: true)
        eq(failedError(o)?.key, "PublicProtocol.err.verify", "witness-only + record failure → err.verify")
        eq(failedError(o)?.code, "OUTPOINT_MEMORY", "code OUTPOINT_MEMORY")
        t(refusedState(c, id) != nil, "refused, not answered")
        t(c.answer(id) == nil, "no response")
        t(env.journal.records.isEmpty, "no journal call")
        t(c.recent.signedAt(ready.plan.requestHash ?? "") == nil && c.recent.count == 0, "the request hash is not in the LRU")
        // The same failing memory + a full-previous-transaction request: answered.
        guard let full = try? await c.prepare(frames2("T8-flow-bitcoin-crypto-psbt")), case .ready(let r2) = c.state(full) else {
            t(false, "full prev tx ready")
            return
        }
        guard let response = await signOnly(c, full, ack: r2.policy.requiresAcknowledgement, "full prev tx") else { return }
        t(!response.frames.isEmpty, "answered")
        eq(env.journal.records.count, 1, "one journal call")
        eq(env.journal.records.first?.requestKind, "crypto-psbt", "BTC record kind")
    }

    @MainActor private static func journalTests() async {
        section("journal: exactly once per handed-out answer")
        // (The app also ran its real offline-signing journal / history here — a failing one over a read-only folder and a
        // readable one; that persistence is host code. The package's part: exactly one hand-off per answer, none for a
        // refusal, and the inputs the record is built from.)
        let env2 = Env()
        env2.wallets.add(CW.ABANDON)
        let c2 = env2.coordinator()
        if let refusedId = try? await c2.prepare(frames2("O-TRX-1-owner-not-signer")) {
            t(refusedState(c2, refusedId) != nil, "a refusal")
        }
        guard let btc = try? await c2.prepare(frames2("T8-flow-bitcoin-crypto-psbt")), case .ready(let ready) = c2.state(btc) else {
            t(false, "BTC ready")
            return
        }
        _ = await signOnly(c2, btc, ack: ready.policy.requiresAcknowledgement, "BTC")
        let records = env2.journal.records
        eq(records.count, 1, "a refusal records nothing; the answer exactly one")
        if let r = records.first {
            eq([r.chain ?? "-", r.requestKind ?? "-"], ["bitcoin", "crypto-psbt"], "bitcoin / crypto-psbt")
            eq(r.requestDigest, SigningVectors.plan("T8-flow-bitcoin-crypto-psbt").requestHash ?? "", "digest = requestHash")
            eq(r.resultFrames, SigningVectors.response("T8-flow-bitcoin-crypto-psbt").frames.count, "result frames")
            eq(r.createdAtMs, Int64((env2.now.timeIntervalSince1970 * 1000).rounded(.down)), "created at the answer time")
        }

        // Two-wallet PSBT discarded between its tasks: no record. Discarded while the answer is made: gone, no record.
        let env3 = Env()
        env3.wallets.add(CW.ABANDON)
        env3.wallets.add(CW.LEGAL)
        let c3 = env3.coordinator()
        if let id = try? await c3.prepare(frames2("T8-flow-psbt-two-wallets")), case .ready(let r) = c3.state(id), r.plan.tasks.count == 2 {
            let s1 = await c3.signTask(id, taskId: r.plan.tasks[0].id, password: CW.PASSWORD, riskAcknowledged: true)
            eq(s1, .signed(taskId: r.plan.tasks[0].id, nextTaskId: r.plan.tasks[1].id), "first task")
            c3.discard(id)
            let s2 = await c3.signTask(id, taskId: r.plan.tasks[1].id, password: CW.LEGAL_PASSWORD, riskAcknowledged: true)
            eq(s2, .gone, "discarded between tasks")
            t(env3.journal.records.isEmpty && c3.recent.count == 0, "no record, nothing recent")
        } else {
            t(false, "two-wallet ready")
        }
        let env4 = Env()
        env4.wallets.add(CW.ABANDON)
        let c4 = env4.coordinator()
        var discard: () -> Void = {}
        env4.engine.encodeHook = { discard() }
        if let id = try? await c4.prepare(frames2("T8-flow-evm-eip1559")), case .ready(let r) = c4.state(id), let task = r.plan.tasks.first {
            discard = { c4.discard(id) }
            let o = await c4.signTask(id, taskId: task.id, password: CW.PASSWORD, riskAcknowledged: false)
            eq(o, .gone, "discarded while the answer is made")
            t(env4.journal.records.isEmpty && c4.recent.count == 0, "no record, nothing recent")
        } else {
            t(false, "EVM ready")
        }
    }
}
