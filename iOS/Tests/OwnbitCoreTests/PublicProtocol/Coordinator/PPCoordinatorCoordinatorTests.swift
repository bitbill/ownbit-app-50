//  PPCoordinatorCoordinatorTests.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Port of the app harness suite `scripts/public-protocol/tests/coordinator` (CoordinatorTests.swift) to XCTest.
//
//  CoordinatorTests.swift — suite "coordinator" (WP19): port of Android PST:sign/PublicSignCoordinatorTest.kt over the
//  recorded engine answers of the golden vectors (ReplayEngine), the vector wallets (FakeIndex / FakeDirectory) and the
//  real verifier / policy / D43 interpreter (security plan S7, C-GEN-9…16, C-RESP-4, F9, F10; R5 §11).
//  iOS differences (design D-21): empty / wrong passwords are validated by the iOS password dialog, so the coordinator has
//  no `EmptyPassword` / `WrongPassword` outcomes; an empty password still unlocks nothing (`.failed`, state kept).
//

import Foundation
import XCTest
@testable import OwnbitCore

extension PPCoordinatorSuite {

    private static func frames(_ id: String) -> BILPublicInput {
        return .frames(SigningVectors.request(id))
    }

    @MainActor private static func readyState(_ c: BILPublicSignCoordinator, _ id: String, _ what: String) -> BILPublicSignReady? {
        if case .ready(let r) = c.state(id) { return r }
        t(false, "\(what): Ready expected, got \(stateName(c.state(id)))")
        return nil
    }

    static func stateName(_ s: BILPublicSignState) -> String {
        switch s {
        case .resolving: return "resolving"
        case .notReady(_, let status, _, _, _): return "notReady(\(status.rawValue))"
        case .ready: return "ready"
        case .answered: return "answered"
        case .refused(_, let e, _, let again): return "refused(\(e.key), \(e.code ?? "-"), again=\(again))"
        case .gone: return "gone"
        }
    }

    @MainActor static func refusedState(_ c: BILPublicSignCoordinator, _ id: String) -> (error: BILPublicSignError, review: BILPublicReview?, again: Bool)? {
        if case .refused(_, let e, let r, let again) = c.state(id) { return (e, r, again) }
        return nil
    }

    @MainActor static func failedError(_ o: BILPublicTaskOutcome) -> BILPublicSignError? {
        if case .failed(let e) = o { return e }
        return nil
    }

    @MainActor static func coordinatorTests() async {
        await evmEndToEnd()
        await twoWalletPsbt()
        await setupRequired()
        await opaqueNeedsCheckbox()
        await d43Card()
        await tronOwnerRefused()
        await refusalsAndForeignPlans()
        await preCheckRefusesDigest()
        await answerThatDoesNotVerify()
        await walletsChanged()
        await timeout()
        await discardAndEvict()
        await pastes()
        await changeBeyond999()
        await unmappedFailures()
        await planPassedBackUnchanged()
        await engineDownAndRisk()
        await notReadyReview()
        await cancelledPrepare()
        await mappedErrorPaths()
    }

    @MainActor private static func evmEndToEnd() async {
        section("EVM 1559 end to end")
        let env = Env()
        env.wallets.add(CW.ABANDON)
        let c = env.coordinator()
        guard let id = try? await c.prepare(frames("T8-flow-evm-eip1559")), let ready = readyState(c, id, "EVM") else { return }
        let plan = SigningVectors.plan("T8-flow-evm-eip1559")
        guard let task = plan.tasks.first else { t(false, "vector task"); return }
        eq(ready.nextTask?.id, task.id, "the next task is the plan's")
        t(ready.signatureNumber == 1 && ready.taskCount == 1, "signature 1 of 1")
        eq(ready.info.transportType, "eth-sign-request", "transport type")
        eq(ready.info.origin, "ownbit-vector", "the unverified origin, for display only")
        t(!ready.policy.requiresAcknowledgement, "no checkbox for a plain transfer")
        t(ready.insight == nil, "a plain transfer gets no D43 card")
        t(ready.signedBefore == nil, "not signed before")

        let empty = await c.signTask(id, taskId: task.id, password: "", riskAcknowledged: false)
        eq(failedError(empty)?.code, "EMPTY_PASSWORD", "an empty password unlocks nothing")
        eq(env.wallets.unlocks, 0, "no unlock for an empty password")
        if case .ready = c.state(id) {} else { t(false, "an empty password changes nothing") }

        let outcome = await c.signTask(id, taskId: task.id, password: CW.PASSWORD, riskAcknowledged: false)
        eq(outcome, .signed(taskId: task.id, nextTaskId: nil), "signed and answered")
        guard case .answered(_, _, _, let response) = c.state(id) else { t(false, "answered: \(stateName(c.state(id)))"); return }
        eq(response.frames, SigningVectors.response("T8-flow-evm-eip1559").frames, "the answer frames are the vector's")
        t(c.answer(id) == response, "answer(id) is the verified answer")
        eq(env.engine.log, ["reviewAndResolve", "signPlanTask:\(task.id):ack=false", "encodeResponse"], "engine calls")
        eq(env.journal.records.count, 1, "one offline-signing record")

        // C-GEN-15: single use.
        let again = await c.signTask(id, taskId: task.id, password: CW.PASSWORD, riskAcknowledged: false)
        eq(failedError(again)?.key, "PublicProtocol.err.alreadySigned", "an answered request cannot be signed again")
        eq(env.journal.records.count, 1, "no second record")
        // C-RESP-4: a new scan of the same request says when it was signed.
        eq(c.recent.signedAt(plan.requestHash ?? ""), env.now, "the recent hashes know it")
        guard let second = try? await c.prepare(frames("T8-flow-evm-eip1559")), let r2 = readyState(c, second, "again") else { return }
        eq(r2.signedBefore, env.now, "a new scan says when it was signed")
    }

    @MainActor private static func twoWalletPsbt() async {
        section("two-wallet PSBT")
        let env = Env()
        env.wallets.add(CW.ABANDON)
        env.wallets.add(CW.LEGAL)
        let c = env.coordinator()
        guard let id = try? await c.prepare(frames("T8-flow-psbt-two-wallets")), let ready = readyState(c, id, "PSBT") else { return }
        guard ready.plan.tasks.count == 2 else { t(false, "two tasks"); return }
        let first = ready.plan.tasks[0], second = ready.plan.tasks[1]
        eq([first.localWalletId, second.localWalletId], [CW.ABANDON, CW.LEGAL], "one task per wallet, home order")
        let outOfOrder = await c.signTask(id, taskId: second.id, password: CW.LEGAL_PASSWORD, riskAcknowledged: true)
        eq(failedError(outOfOrder)?.code, "TASK_ORDER", "tasks sign in plan order")
        let s1 = await c.signTask(id, taskId: first.id, password: CW.PASSWORD, riskAcknowledged: true)
        eq(s1, .signed(taskId: first.id, nextTaskId: second.id), "the first wallet signed")
        guard let partial = readyState(c, id, "partial") else { return }
        t(partial.hasPartialSignatures, "partial signatures")
        eq(partial.signatureNumber, 2, "signature 2 of 2")
        eq(partial.nextTask?.id, second.id, "next task")
        t(env.journal.records.isEmpty, "a partial signature is never handed out: no record")
        await c.resolveAgain(id)
        if let again = readyState(c, id, "no re-matching") { t(again.hasPartialSignatures, "no re-matching once a wallet signed") }
        let s2 = await c.signTask(id, taskId: second.id, password: CW.LEGAL_PASSWORD, riskAcknowledged: true)
        eq(s2, .signed(taskId: second.id, nextTaskId: nil), "the second wallet signed")
        guard case .answered(_, _, _, let response) = c.state(id) else { t(false, "answered"); return }
        eq(response.type, "crypto-psbt", "crypto-psbt answer")
        eq(response.frames, SigningVectors.response("T8-flow-psbt-two-wallets").frames, "the answer frames are the vector's")
        eq(env.journal.records.count, 1, "exactly one record after the last task")
        if let r = env.journal.records.first {
            eq(r.walletIds, [CW.ABANDON, CW.LEGAL], "record wallets")
            eq(r.walletCount, 2, "record wallet count")
            eq(r.signatures, 2, "record signatures")
            eq(r.acknowledged, ready.policy.requiresAcknowledgement, "acknowledged only when the checkbox was required and ticked")
            t(r.signer == nil, "no single signer for two tasks")
            eq(r.decode, ready.review.decodeStatus.rawValue, "decode status")
        }
        let again = await c.signTask(id, taskId: second.id, password: CW.LEGAL_PASSWORD, riskAcknowledged: true)
        t(failedError(again) != nil, "single use")
        eq(env.journal.records.count, 1, "no second record")
    }

    @MainActor private static func setupRequired() async {
        section("setupRequired")
        let env = Env()
        env.engine.planFor = { _, wallets, recorded in
            if wallets.contains(where: { $0["publicIndex"] == nil }) {
                return BILJSONObject([("version", .int(1)), ("status", .string("setupRequired")), ("message", .string("Wallet setup required")),
                                      ("tasks", .array([]))])
            }
            return recorded
        }
        env.wallets.add(CW.ABANDON, prepared: false)
        let c = env.coordinator()
        guard let id = try? await c.prepare(frames("T8-flow-evm-personal")) else { t(false, "prepared"); return }
        guard case .notReady(_, let status, let review, let setup, let message) = c.state(id) else {
            t(false, "notReady: \(stateName(c.state(id)))")
            return
        }
        eq(status, .setupRequired, "setupRequired")
        eq(setup, [CW.ABANDON], "only the unprepared wallets")
        t(review != nil, "the request is still shown")
        eq(message, "Wallet setup required", "the engine's English status text (details only)")
        let notOffered = await c.setupThenResolve(id, walletId: "not-offered", password: CW.PASSWORD)
        eq(notOffered, .notEligible, "a wallet the sheet did not offer")
        eq(env.wallets.prepares, 0, "nothing prepared for it")
        let prepared = await c.setupThenResolve(id, walletId: CW.ABANDON, password: CW.PASSWORD)
        eq(prepared, .ready(fingerprint: "73C5DA0A"), "prepared")
        guard let ready = readyState(c, id, "after setup"), let task = ready.plan.tasks.first else { return }
        let outcome = await c.signTask(id, taskId: task.id, password: CW.PASSWORD, riskAcknowledged: true)
        eq(outcome, .signed(taskId: task.id, nextTaskId: nil), "signed after the inline prepare")
        let twice = await c.setupThenResolve(id, walletId: CW.ABANDON, password: CW.PASSWORD)
        eq(twice, .notEligible, "no setup once the request is not setupRequired")
    }

    @MainActor private static func opaqueNeedsCheckbox() async {
        section("opaque request needs the checkbox")
        let env = Env()
        env.wallets.add(CW.ABANDON)
        let c = env.coordinator()
        guard let id = try? await c.prepare(frames("O-EVM-4-personal-hash")), let ready = readyState(c, id, "opaque"),
              let task = ready.plan.tasks.first else { return }
        t(ready.policy.requiresAcknowledgement, "the checkbox is required")
        let noAck = await c.signTask(id, taskId: task.id, password: CW.PASSWORD, riskAcknowledged: false)
        eq(noAck, .acknowledgementRequired, "nothing signed without it")
        eq(env.wallets.unlocks, 0, "no password was even checked")
        let ok = await c.signTask(id, taskId: task.id, password: CW.PASSWORD, riskAcknowledged: true)
        eq(ok, .signed(taskId: task.id, nextTaskId: nil), "signed with it")
        t(env.engine.log.contains("signPlanTask:\(task.id):ack=true"), "the engine gets riskAcknowledged = true")
        eq(env.journal.records.first?.acknowledged, true, "the record says the checkbox was ticked")
        eq(env.journal.records.first?.action, "signMessage", "record action signMessage")
        t(ready.review.display?.headline != nil && env.journal.records.first?.messagePreview == nil,
          "no message preview for an opaque message (only a fully decoded one)")
        // A fully decoded message keeps its headline as the preview.
        let env2 = Env()
        env2.wallets.add(CW.ABANDON)
        let c2 = env2.coordinator()
        if let id2 = try? await c2.prepare(frames("T8-flow-evm-personal")), let r2 = readyState(c2, id2, "personal"), let t2 = r2.plan.tasks.first {
            _ = await c2.signTask(id2, taskId: t2.id, password: CW.PASSWORD, riskAcknowledged: r2.policy.requiresAcknowledgement)
            eq(env2.journal.records.first?.messagePreview, "Ownbit public protocol fixture", "a fully decoded message's preview")
        }
    }

    @MainActor private static func d43Card() async {
        section("D43 card (USDT known)")
        let env = Env()
        env.wallets.add(CW.ABANDON)
        // The app read the card with its real interpreter; here a stand-in for EVM transactions proves the plumbing.
        env.insightProvider = { request in
            if case .evmTransaction = request.payload { return stubInsight() }
            return nil
        }
        let c = env.coordinator()
        guard let id = try? await c.prepare(frames("T8-flow-evm-erc20-transfer-usdt")), let ready = readyState(c, id, "USDT") else { return }
        guard let insight = ready.insight else { t(false, "a D43 card"); return }
        t(insight.contract?.isKnown == true, "the contract is known (yellow)")
        eq(env.interpreted.count, 1, "interpreted once")
        eq(env.interpreted.first?.chain, "eip155:1", "on Ethereum")
        t(ready.insightInput != nil, "the explanation page data")
        t(ready.policy.pageRisk.rank >= insight.risk.rank, "page risk ≥ the card's risk")
        guard let task = ready.plan.tasks.first else { return }
        _ = await c.signTask(id, taskId: task.id, password: CW.PASSWORD, riskAcknowledged: ready.policy.requiresAcknowledgement)
        t(env.journal.records.first?.insight != nil, "the record keeps the card the user saw")
        eq(env.journal.records.first?.risk, insight.risk, "record risk = the card's")
    }

    @MainActor private static func tronOwnerRefused() async {
        section("TRON owner ≠ signer refused before any password")
        let env = Env()
        env.wallets.add(CW.ABANDON)
        let c = env.coordinator()
        guard let id = try? await c.prepare(frames("O-TRX-1-owner-not-signer")), let refused = refusedState(c, id) else {
            t(false, "refused")
            return
        }
        eq(refused.error.key, "PublicProtocol.err.tronOwner", "err.tronOwner")
        eq(refused.error.args, [.text("TJRabPrwbZy45sbavfcjinPJC18kjpRTv8")], "the owner account")
        t(refused.review != nil, "the review is still shown")
        t(!refused.again, "no Match again")
        let taskId = SigningVectors.plan("O-TRX-1-owner-not-signer").tasks.first?.id ?? ""
        let o = await c.signTask(id, taskId: taskId, password: CW.PASSWORD, riskAcknowledged: true)
        eq(failedError(o)?.key, "PublicProtocol.err.tronOwner", "signing a refused request gives its error")
        eq(env.wallets.unlocks, 0, "nothing unlocked")
        t(env.journal.records.isEmpty, "a refusal records nothing")
    }

    @MainActor private static func refusalsAndForeignPlans() async {
        section("engine refusals, no wallet, foreign plans")
        let env = Env()
        env.engine.planFor = { request, _, recorded in
            guard request.str("kind") == "personal" else { return recorded }
            let tasks: [BILJSONValue] = (recorded.arr("tasks") ?? []).map { t in
                guard let o = t.objectValue else { return t }
                return .object(with(o, "localWalletId", .string("wallet-other")))
            }
            return with(recorded, "tasks", .array(tasks))
        }
        let c = env.coordinator()
        guard let none = try? await c.prepare(frames("T8-flow-evm-eip1559")) else { t(false, "prepared"); return }
        eq(refusedState(c, none)?.error.key, "PublicProtocol.err.noWallet", "no eligible wallet")
        t(refusedState(c, none)?.again == false, "no Match again without a wallet")
        eq(env.engine.log, [], "the engine never ran")
        env.wallets.add(CW.ABANDON)
        guard let network = try? await c.prepare(frames("T9-unsupported-network")), let refused = refusedState(c, network) else {
            t(false, "network refused")
            return
        }
        eq(refused.error.key, "PublicProtocol.err.networkUnsupported", "the engine refuses the network at review")
        eq(refused.error.code, "NETWORK", "code NETWORK")
        eq(refused.error.engineMessage, "Unsupported network", "the engine's English text (details only)")
        guard let foreign = try? await c.prepare(frames("T8-flow-evm-personal")) else { t(false, "foreign"); return }
        eq(refusedState(c, foreign)?.error.key, "PublicProtocol.err.integrity", "a plan naming a wallet never offered")
        eq(refusedState(c, foreign)?.error.code, "INTEGRITY", "code INTEGRITY")
        // A plan naming an offered wallet with another index identity.
        env.engine.planFor = { _, _, recorded in
            let tasks: [BILJSONValue] = (recorded.arr("tasks") ?? []).map { t in
                guard let o = t.objectValue else { return t }
                return .object(with(o, "walletKeyId", .string(String(repeating: "ab", count: 32))))
            }
            return with(recorded, "tasks", .array(tasks))
        }
        guard let otherKey = try? await c.prepare(frames("T8-flow-evm-eip1559")) else { t(false, "other key"); return }
        eq(refusedState(c, otherKey)?.error.code, "INTEGRITY", "another index identity than offered")
        // An engine review of another chain / without a 64-hex hash / without rows.
        env.engine.planFor = { _, _, recorded in recorded }
        for (what, edit) in [("chain", { (r: BILJSONObject) in with(r, "chain", .string("tron")) }),
                             ("requestHash", { (r: BILJSONObject) in with(r, "requestHash", .string("abc")) }),
                             ("fields", { (r: BILJSONObject) in with(r, "fields", .array([])) })] {
            env.engine.reviewFor = { _, recorded in edit(recorded) }
            guard let id = try? await c.prepare(frames("T8-flow-evm-eip1559")) else { t(false, what); return }
            eq(refusedState(c, id)?.error.code, "INTEGRITY", "an engine review with a bad \(what) is refused")
        }
        env.engine.reviewFor = { _, recorded in with(recorded, "canSign", .bool(false)) }
        guard let cannot = try? await c.prepare(frames("T8-flow-evm-eip1559")) else { t(false, "canSign"); return }
        eq(refusedState(c, cannot)?.error.key, "PublicProtocol.err.unsupported", "canSign false → err.unsupported")
        t(refusedState(c, cannot)?.review != nil, "with the engine review")
        env.engine.reviewFor = { _, recorded in recorded }
        env.engine.planFor = { _, _, recorded in with(recorded, "requestHash", .string(String(repeating: "cd", count: 32))) }
        guard let planHash = try? await c.prepare(frames("T8-flow-evm-eip1559")) else { t(false, "plan hash"); return }
        eq(refusedState(c, planHash)?.error.code, "INTEGRITY", "a plan of another request (malformed plan → integrity)")
        env.engine.planFor = { _, _, recorded in with(recorded, "planHash", .string("zz")) }
        guard let malformed = try? await c.prepare(frames("T8-flow-evm-eip1559")) else { t(false, "malformed"); return }
        eq(refusedState(c, malformed)?.error.code, "INTEGRITY", "a malformed plan → integrity")
        t(refusedState(c, malformed)?.review == nil, "… without a review")
    }

    @MainActor private static func preCheckRefusesDigest() async {
        section("the native pre-check refuses a plan that does not commit to the scanned bytes")
        let env = Env()
        env.engine.planFor = { _, _, recorded in withDigest(recorded, String(repeating: "00", count: 32)) }
        env.wallets.add(CW.ABANDON)
        let c = env.coordinator()
        guard let id = try? await c.prepare(frames("T8-flow-evm-eip1559")), let refused = refusedState(c, id) else { t(false, "refused"); return }
        eq(refused.error.key, "PublicProtocol.err.integrity", "err.integrity")
        eq(refused.error.code, "INTEGRITY", "code INTEGRITY")
        t(!refused.again, "no Match again")
        eq(env.wallets.unlocks, 0, "nothing unlocked")
    }

    @MainActor private static func answerThatDoesNotVerify() async {
        section("an answer that does not verify is never shown")
        let env = Env()
        env.engine.encodeFor = { _, _, _ in SigningVectors.encoded("T8-flow-evm-personal") ?? BILJSONObject() }
        env.wallets.add(CW.ABANDON)
        let c = env.coordinator()
        guard let id = try? await c.prepare(frames("T8-flow-evm-eip1559")), let ready = readyState(c, id, "EVM"),
              let task = ready.plan.tasks.first else { return }
        let o = await c.signTask(id, taskId: task.id, password: CW.PASSWORD, riskAcknowledged: false)
        eq(failedError(o)?.key, "PublicProtocol.err.verify", "err.verify")
        t(refusedState(c, id) != nil, "refused")
        t(c.answer(id) == nil, "no answer")
        eq(c.recent.count, 0, "nothing answered")
        t(env.journal.records.isEmpty, "an answer the post-check refuses leaves no record")
        // An engine refusal of the answer: err.verify with its code; a malformed answer: INTEGRITY.
        let env2 = Env()
        env2.engine.encodeFor = { _, _, _ in throw BILPublicSignerRefusal(code: "QR_PROTOCOL", engineMessage: "Unsupported response profile") }
        env2.wallets.add(CW.ABANDON)
        let c2 = env2.coordinator()
        if let id2 = try? await c2.prepare(frames("T8-flow-evm-eip1559")), let task2 = readyState(c2, id2, "EVM 2")?.plan.tasks.first {
            let o2 = await c2.signTask(id2, taskId: task2.id, password: CW.PASSWORD, riskAcknowledged: false)
            eq(failedError(o2)?.key, "PublicProtocol.err.verify", "an encodeResponse refusal → err.verify")
            eq(failedError(o2)?.code, "QR_PROTOCOL", "… with the engine code")
        }
        let env3 = Env()
        env3.engine.encodeFor = { _, _, _ in BILJSONObject([("type", .string("eth-signature")), ("frames", .array([]))]) }
        env3.wallets.add(CW.ABANDON)
        let c3 = env3.coordinator()
        if let id3 = try? await c3.prepare(frames("T8-flow-evm-eip1559")), let task3 = readyState(c3, id3, "EVM 3")?.plan.tasks.first {
            let o3 = await c3.signTask(id3, taskId: task3.id, password: CW.PASSWORD, riskAcknowledged: false)
            eq(failedError(o3)?.code, "INTEGRITY", "an answer without frames → err.verify / INTEGRITY")
            t(env3.journal.records.isEmpty, "no record")
        }
    }

    @MainActor private static func walletsChanged() async {
        section("wallet data changed after matching")
        let env = Env()
        env.wallets.add(CW.ABANDON)
        let c = env.coordinator()
        guard let id = try? await c.prepare(frames("T8-flow-evm-eip1559")), let task = readyState(c, id, "EVM")?.plan.tasks.first else { return }
        env.wallets.addUnprepared("hot-new")
        let o = await c.signTask(id, taskId: task.id, password: CW.PASSWORD, riskAcknowledged: false)
        eq(failedError(o)?.code, "WALLETS_CHANGED", "WALLETS_CHANGED")
        eq(refusedState(c, id)?.again, true, "Match again")
        eq(env.wallets.unlocks, 0, "nothing unlocked")
        await c.resolveAgain(id)
        guard readyState(c, id, "matched again") != nil else { return }
        let ok = await c.signTask(id, taskId: task.id, password: CW.PASSWORD, riskAcknowledged: false)
        eq(ok, .signed(taskId: task.id, nextTaskId: nil), "signs after matching again")
        // A prepared index (another identity) after matching also changes the snapshot.
        let env2 = Env()
        env2.wallets.add(CW.ABANDON)
        env2.wallets.add(CW.LEGAL, prepared: false)
        let c2 = env2.coordinator()
        guard let id2 = try? await c2.prepare(frames("T8-flow-evm-eip1559")), let task2 = readyState(c2, id2, "EVM 2")?.plan.tasks.first else { return }
        env2.wallets.wallets[1].prepared = true
        env2.wallets.wallets[1].index = CW.publicIndex("legal")
        let o2 = await c2.signTask(id2, taskId: task2.id, password: CW.PASSWORD, riskAcknowledged: false)
        eq(failedError(o2)?.code, "WALLETS_CHANGED", "an index prepared after matching")
    }

    @MainActor private static func timeout() async {
        section("a sign that takes too long fails without hanging, and can be retried")
        let env = Env()
        env.wallets.add(CW.ABANDON)
        let c = env.coordinator(timeout: 1)
        guard let id = try? await c.prepare(frames("T8-flow-evm-eip1559")), let task = readyState(c, id, "EVM")?.plan.tasks.first else { return }
        env.engine.signOverride = { _, _, _ in
            await blockingWait(seconds: 3)          // like a JavaScriptCore call: not interruptible
            throw BILPublicSignerFailure.malformedResponse
        }
        let started = Date()
        let o = await c.signTask(id, taskId: task.id, password: CW.PASSWORD, riskAcknowledged: false)
        let seconds = Date().timeIntervalSince(started)
        eq(failedError(o)?.code, "TIMEOUT", "TIMEOUT")
        eq(failedError(o)?.key, "PublicProtocol.err.engineUnavailable", "err.engineUnavailable")
        t(seconds < 2.5, "the bound holds while the engine is still busy (\(Int(seconds * 1000)) ms)")
        t(readyState(c, id, "after the timeout") != nil, "nothing signed; the user may try again")
        t(env.journal.records.isEmpty, "a sign that times out leaves no record")
        await blockingWait(seconds: 2.2)                // the late engine answer arrives and is dropped
        t(readyState(c, id, "after the late answer") != nil, "the late answer changes nothing")
        env.engine.signOverride = nil
        let retry = await c.signTask(id, taskId: task.id, password: CW.PASSWORD, riskAcknowledged: false)
        eq(retry, .signed(taskId: task.id, nextTaskId: nil), "the retry signs")
    }

    /// Waits `seconds` without reacting to cancellation (a stuck synchronous engine call).
    static func blockingWait(seconds: Double) async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().asyncAfter(deadline: .now() + seconds) { c.resume() }
        }
    }

    @MainActor private static func discardAndEvict() async {
        section("discarded and evicted requests are gone")
        let env = Env()
        env.wallets.add(CW.ABANDON)
        let c = env.coordinator()
        guard let id = try? await c.prepare(frames("T8-flow-evm-eip1559")), let task = readyState(c, id, "EVM")?.plan.tasks.first else { return }
        var seen: [String] = []
        let token = c.observe(id) { seen.append(stateName($0)) }
        c.discard(id)
        if case .gone = c.state(id) {} else { t(false, "discarded → gone") }
        eq(seen, ["ready", "gone"], "observers are told .gone")
        let o = await c.signTask(id, taskId: task.id, password: CW.PASSWORD, riskAcknowledged: false)
        eq(o, .gone, "signing a discarded request")
        t(c.answer(id) == nil, "no answer")
        token.cancel()
        guard let first = try? await c.prepare(frames("T8-flow-evm-eip1559")) else { t(false, "first"); return }
        for _ in 0..<BILPublicRequestStore.capacity { _ = try? await c.prepare(frames("T8-flow-evm-eip1559")) }
        if case .gone = c.state(first) {} else { t(false, "at most 8 requests in memory") }
        eq(c.store.count, BILPublicRequestStore.capacity, "8 kept")
        let evicted = await c.signTask(first, taskId: task.id, password: CW.PASSWORD, riskAcknowledged: false)
        eq(evicted, .gone, "the evicted request is gone")
        await c.resolveAgain(first)
        if case .gone = c.state(first) {} else { t(false, "resolveAgain of a gone id does nothing") }
        let setupGone = await c.setupThenResolve(first, walletId: CW.ABANDON, password: CW.PASSWORD)
        eq(setupGone, .notEligible, "setup of a gone id")
    }

    @MainActor private static func pastes() async {
        section("pasted text that is not a request never becomes one")
        let env = Env()
        let c = env.coordinator()
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
        let large = await refused(String(repeating: "a", count: BILPublicSignCoordinator.maxPasteBytes + 1))
        eq(large?.key, "PublicProtocol.err.tooLarge", "paste > 262 144 bytes → tooLarge")
        eq(large?.code, "LIMIT", "code LIMIT")
        let multibyte = await refused(String(repeating: "é", count: BILPublicSignCoordinator.maxPasteBytes / 2 + 1))
        eq(multibyte?.code, "LIMIT", "the limit counts UTF-8 bytes")
        let hello = await refused("hello")
        eq(hello?.key, "PublicProtocol.err.unsupportedUr", "paste \"hello\" → unsupportedUr")
        eq(c.store.count, 0, "nothing stored")
        eq(env.engine.log, ["decodePayload"], "only the decode of \"hello\" reached the engine")
        // A pasted request the engine decodes becomes one (the vector's decodePayload flow).
        if let step = SigningVectors.allSteps.first(where: { $0.op == "decodePayload" && $0.ok && $0.result?.bool("complete") == true }),
           let payload = step.request.str("payload") {
            env.wallets.add(CW.ABANDON)
            let id = try? await c.prepare(.pasted(payload))
            t(id != nil, "a decodable paste becomes a request")
        } else {
            t(false, "a vector decodePayload step")
        }
    }

    @MainActor private static func changeBeyond999() async {
        section("change beyond index 999 is shown as a normal output (C-BTC-7)")
        let env = Env()
        env.wallets.add(CW.ABANDON)
        let c = env.coordinator()
        guard let planReview = SigningVectors.plan("O-BTC-3-change-1000").review else { t(false, "plan review"); return }
        t(planReview.fields.contains { $0.label == "Output 2 ownership" }, "the plan's review calls output 2 change")
        eq(planReview.display?.note, "Change returns to your wallet", "… and leaves it out of the summary")
        guard let id = try? await c.prepare(frames("O-BTC-3-change-1000")), let beyond = readyState(c, id, "1000") else { return }
        t(beyond.policy.ackReasons.contains(.changeBeyondBound), "CHANGE_BEYOND_BOUND")
        t(beyond.policy.requiresAcknowledgement, "the checkbox")
        eq(beyond.policy.warnings.map { $0.key }, ["PublicProtocol.warn.changeIndex"], "warn.changeIndex")
        t(!beyond.review.fields.contains { $0.label.hasSuffix(" ownership") }, "no ownership labels in the shown review")
        t(beyond.review.display?.note == nil, "no \"change returns to your wallet\"")
        eq(beyond.review.display?.headline, "2 recipients · 0.00199 BTC", "both outputs counted as sent")
        t(beyond.review.fields.contains { $0.label == "Output 2" }, "Output 2 label present")
        eq(beyond.plan.requestHash, beyond.review.requestHash, "the same request")
        eq(beyond.policy.engineRisk, BILPublicSignPolicy.engineRisk(beyond.review.riskLevel), "the risk is judged on the review shown")
        guard let task = beyond.plan.tasks.first else { return }
        let noAck = await c.signTask(id, taskId: task.id, password: CW.PASSWORD, riskAcknowledged: false)
        eq(noAck, .acknowledgementRequired, "checkbox first")
        let ok = await c.signTask(id, taskId: task.id, password: CW.PASSWORD, riskAcknowledged: true)
        eq(ok, .signed(taskId: task.id, nextTaskId: nil), "signs with the checkbox")
        if case .answered(_, let review, _, _) = c.state(id) {
            t(!review.fields.contains { $0.label.hasSuffix(" ownership") }, "the answered page keeps the shown review")
        } else {
            t(false, "answered")
        }
        guard let hiddenId = try? await c.prepare(frames("O-BTC-3-change-taphashes")), let hidden = readyState(c, hiddenId, "taphashes") else { return }
        eq(hidden.policy.warnings.first?.args ?? [], [.int(2), .text("2147483647")], "taphashes vector args")
        t(hidden.policy.requiresAcknowledgement, "taphashes: checkbox")
        t(!hidden.review.fields.contains { $0.label.hasSuffix(" ownership") }, "taphashes: no ownership labels")
        t(hidden.review.display?.note == nil, "taphashes: no change note")
        guard let withinId = try? await c.prepare(frames("O-BTC-3-change-999")), let within = readyState(c, withinId, "999") else { return }
        t(!within.policy.ackReasons.contains(.changeBeyondBound), "999: the verified change stays")
        t(within.review.fields.contains { $0.label == "Output 2 ownership" }, "999: ownership label")
        eq(within.review.display?.note, "Change returns to your wallet", "999: change note")
    }

    private struct Unmapped: Error {}

    @MainActor private static func unmappedFailures() async {
        section("an unmapped failure ends matching or signing with an alert (C-GEN-16)")
        let env = Env()
        env.wallets.add(CW.ABANDON)
        let c = env.coordinator()
        env.engine.reviewOverride = { throw Unmapped() }
        guard let id = try? await c.prepare(frames("T8-flow-evm-eip1559")), let refused = refusedState(c, id) else { t(false, "refused"); return }
        eq(refused.error.code, "UNEXPECTED", "UNEXPECTED")
        eq(refused.error.key, "PublicProtocol.match.invalid.body", "match.invalid.body")
        t(refused.again, "Match again")
        env.engine.reviewOverride = nil
        await c.resolveAgain(id)
        guard let task = readyState(c, id, "matched again")?.plan.tasks.first else { return }
        env.engine.signOverride = { _, _, _ in throw Unmapped() }
        let o = await c.signTask(id, taskId: task.id, password: CW.PASSWORD, riskAcknowledged: false)
        eq(failedError(o)?.code, "UNEXPECTED", "signing: UNEXPECTED")
        t(readyState(c, id, "kept") != nil, "nothing was kept; the task may be tried again")
        env.engine.signOverride = nil
        let ok = await c.signTask(id, taskId: task.id, password: CW.PASSWORD, riskAcknowledged: false)
        eq(ok, .signed(taskId: task.id, nextTaskId: nil), "signs once the failure is gone")
        // An engine that cannot run while matching: Match again.
        let env2 = Env()
        env2.wallets.add(CW.ABANDON)
        env2.engine.reviewOverride = { throw BILPublicSignerFailure.engineUnavailable }
        let c2 = env2.coordinator()
        guard let id2 = try? await c2.prepare(frames("T8-flow-evm-eip1559")), let r2 = refusedState(c2, id2) else { t(false, "engine down"); return }
        eq(r2.error.key, "PublicProtocol.err.engineUnavailable", "engine down while matching → err.engineUnavailable")
        t(r2.again, "… with Match again")
    }

    @MainActor private static func planPassedBackUnchanged() async {
        section("a resolved plan is passed back to the engine unchanged")
        let env = Env()
        var resolved: BILJSONObject?
        env.engine.planFor = { _, _, recorded in
            resolved = recorded
            return recorded
        }
        env.wallets.add(CW.ABANDON)
        let c = env.coordinator()
        guard let id = try? await c.prepare(frames("T8-flow-solana-transfer")), let task = readyState(c, id, "SOL")?.plan.tasks.first else { return }
        let o = await c.signTask(id, taskId: task.id, password: CW.PASSWORD, riskAcknowledged: false)
        eq(o, .signed(taskId: task.id, nextTaskId: nil), "signed")
        eq(env.engine.signedPlans.count, 1, "one sign call")
        t(env.engine.signedPlans.first.map { BILStrictJSON.serialize($0) } == resolved.map { BILStrictJSON.serialize($0) },
          "byte for byte the resolver's plan")
    }

    @MainActor private static func engineDownAndRisk() async {
        section("engine down while signing / RISK refusal")
        let env = Env()
        env.wallets.add(CW.ABANDON)
        let c = env.coordinator()
        guard let id = try? await c.prepare(frames("T8-flow-evm-eip1559")), let task = readyState(c, id, "EVM")?.plan.tasks.first else { return }
        env.engine.signOverride = { _, _, _ in throw BILPublicSignerFailure.engineUnavailable }
        let down = await c.signTask(id, taskId: task.id, password: CW.PASSWORD, riskAcknowledged: false)
        eq(failedError(down)?.key, "PublicProtocol.err.engineUnavailable", "engine down → err.engineUnavailable")
        t(readyState(c, id, "kept") != nil, "state kept (retry possible)")
        env.engine.signOverride = { _, _, _ in throw BILPublicSignerRefusal(code: "RISK", engineMessage: "Risk acknowledgement required") }
        let risk = await c.signTask(id, taskId: task.id, password: CW.PASSWORD, riskAcknowledged: false)
        eq(failedError(risk)?.code, "RISK", "the engine insists on consent")
        t(readyState(c, id, "kept after RISK") != nil, "RISK keeps the page")
        env.engine.signOverride = { _, _, _ in throw BILPublicSignerRefusal(code: "SIGNER", engineMessage: "The decrypted wallet does not match the signing plan") }
        let signer = await c.signTask(id, taskId: task.id, password: CW.PASSWORD, riskAcknowledged: false)
        t(failedError(signer) != nil && refusedState(c, id)?.again == false, "another refusal ends the request")
        // A sign result of another request / task is never kept (R5 §1.6 step 6).
        for (what, edit) in [("another request", { (r: BILJSONObject) in with(r, "requestHash", .string(String(repeating: "ef", count: 32))) }),
                             ("another plan", { (r: BILJSONObject) in with(r, "planHash", .string(String(repeating: "ef", count: 32))) }),
                             ("another task", { (r: BILJSONObject) in with(with(r, "taskId", .string("other")), "completedTaskIds", .array([.string("other")])) }),
                             ("more completed tasks", { (r: BILJSONObject) in with(r, "completedTaskIds", .array([.string("x"), r["taskId"] ?? .null])) }),
                             ("another chain", { (r: BILJSONObject) in with(r, "chain", .string("tron")) }),
                             ("a malformed result", { (r: BILJSONObject) in without(r, "planHash") })] {
            let e = Env()
            e.wallets.add(CW.ABANDON)
            let cc = e.coordinator()
            guard let rid = try? await cc.prepare(frames("T8-flow-evm-eip1559")), let rtask = readyState(cc, rid, what)?.plan.tasks.first else { continue }
            let golden = SigningVectors.signResults("T8-flow-evm-eip1559").first ?? BILJSONObject()
            e.engine.signOverride = { _, _, _ in edit(golden) }
            let o = await cc.signTask(rid, taskId: rtask.id, password: CW.PASSWORD, riskAcknowledged: false)
            eq(failedError(o)?.code, "INTEGRITY", "\(what) → err.integrity")
            t(refusedState(cc, rid) != nil && cc.answer(rid) == nil, "\(what): refused, no answer")
            t(!e.engine.log.contains("encodeResponse"), "\(what): nothing encoded")
        }
        // A wallet without its secret (decrypt fails): NO_SECRET, no Match again.
        let env2 = Env()
        env2.wallets.add(CW.ABANDON)
        let c2 = env2.coordinator()
        guard let id2 = try? await c2.prepare(frames("T8-flow-evm-eip1559")), let task2 = readyState(c2, id2, "EVM 2")?.plan.tasks.first else { return }
        let noSecret = await c2.signTask(id2, taskId: task2.id, password: "not the wallet's", riskAcknowledged: false)
        eq(failedError(noSecret)?.code, "NO_SECRET", "no secret → NO_SECRET")
        eq(failedError(noSecret)?.key, "PublicProtocol.err.noWallet", "err.noWallet")
        eq(refusedState(c2, id2)?.again, false, "no Match again")
        eq(env2.engine.log.filter { $0.hasPrefix("signPlanTask") }.count, 0, "the engine never got a seed")
    }

    @MainActor private static func notReadyReview() async {
        section("a non-ready plan's review is shown when it reviews the same request")
        for (what, sameHash) in [("same request", true), ("another request", false)] {
            let env = Env()
            env.engine.planFor = { _, _, recorded in
                guard var review = recorded.obj("review") else { return recorded }
                review.set("title", .string("Plan review"))
                if !sameHash { review.set("requestHash", .string(String(repeating: "ab", count: 32))) }
                return BILJSONObject([("version", .int(1)), ("status", .string("noMatch")), ("message", .string("No local wallet")),
                                      ("review", .object(review)), ("tasks", .array([]))])
            }
            env.wallets.add(CW.ABANDON)
            let c = env.coordinator()
            guard let id = try? await c.prepare(frames("T8-flow-evm-eip1559")), case .notReady(_, let status, let review, let setup, _) = c.state(id) else {
                t(false, "\(what): notReady"); continue
            }
            eq(status, .noMatch, "\(what): noMatch")
            t(setup.isEmpty, "\(what): no setup wallets for noMatch")
            eq(review?.title == "Plan review", sameHash, "\(what): the plan's review only for the same request hash")
        }
    }

    @MainActor private static func cancelledPrepare() async {
        section("a cancelled prepare leaves no orphan request")
        let env = Env()
        env.wallets.add(CW.ABANDON)
        let c = env.coordinator()
        let gate = Gate()
        env.engine.reviewHook = { await gate.wait() }
        let task = Task { @MainActor () -> String? in try? await c.prepare(frames("T8-flow-evm-eip1559")) }
        while !env.engine.log.contains("reviewAndResolve") { await blockingWait(seconds: 0.02) }
        eq(c.store.count, 1, "the request is stored while it is matched")
        task.cancel()
        gate.open()
        let id = await task.value
        t(id == nil, "the cancelled prepare throws")
        eq(c.store.count, 0, "and leaves no orphan behind")
    }

    /// The setupRequired plan of `setupRequired()` while an offered wallet has no index.
    private static func setupRequiredPlan(_ wallets: [BILJSONObject], _ recorded: BILJSONObject) -> BILJSONObject {
        guard wallets.contains(where: { $0["publicIndex"] == nil }) else { return recorded }
        return BILJSONObject([("version", .int(1)), ("status", .string("setupRequired")), ("message", .string("Wallet setup required")),
                              ("tasks", .array([]))])
    }

    @MainActor private static func mappedErrorPaths() async {
        section("mapped error paths: cancellations, a non-ready request, engine down at paste / answer")
        // A paste while the engine cannot run (Android `JsException`): err.engineUnavailable; any other failure: qrMalformed.
        let env = Env()
        env.wallets.add(CW.ABANDON)
        let c = env.coordinator()
        func pasteError(_ failure: Error) async -> BILPublicSignError? {
            env.engine.decodeOverride = { _ in throw failure }
            defer { env.engine.decodeOverride = nil }
            do {
                _ = try await c.prepare(.pasted("ur:crypto-psbt/not-decoded"))
                return nil
            } catch let e as BILPublicPrepareError {
                return e.error
            } catch {
                return nil
            }
        }
        let down = await pasteError(BILPublicSignerFailure.engineUnavailable)
        eq(down?.key, "PublicProtocol.err.engineUnavailable", "a paste while the engine is down → err.engineUnavailable")
        let other = await pasteError(Unmapped())
        eq([other?.key ?? "-", other?.code ?? "-"], ["PublicProtocol.err.qrMalformed", "UNEXPECTED"], "an unmapped paste failure → qrMalformed / UNEXPECTED")
        eq(c.store.count, 0, "no request stored")

        // The engine cannot run when the answer is encoded (R5 §1.6 step 8): err.verify without a code, request ended.
        let env2 = Env()
        env2.wallets.add(CW.ABANDON)
        env2.engine.encodeFor = { _, _, _ in throw BILPublicSignerFailure.engineUnavailable }
        let c2 = env2.coordinator()
        if let id2 = try? await c2.prepare(frames("T8-flow-evm-eip1559")), let task2 = readyState(c2, id2, "EVM encode")?.plan.tasks.first {
            let o = await c2.signTask(id2, taskId: task2.id, password: CW.PASSWORD, riskAcknowledged: false)
            eq(failedError(o)?.key, "PublicProtocol.err.verify", "engine down at encodeResponse → err.verify")
            t(failedError(o) != nil && failedError(o)?.code == nil, "… without a code")
            t(refusedState(c2, id2)?.again == false && c2.answer(id2) == nil, "refused, no answer")
            t(env2.journal.records.isEmpty && c2.recent.count == 0, "nothing handed out")
        }

        // signTask cancelled while the engine signs: CANCELLED, state kept, the late answer dropped, a retry signs.
        let env3 = Env()
        env3.wallets.add(CW.ABANDON)
        let c3 = env3.coordinator()
        if let id3 = try? await c3.prepare(frames("T8-flow-evm-eip1559")), let task3 = readyState(c3, id3, "EVM cancel")?.plan.tasks.first {
            let gate = Gate()
            env3.engine.signHook = { _ in await gate.wait() }
            let signing = Task { @MainActor in
                await c3.signTask(id3, taskId: task3.id, password: CW.PASSWORD, riskAcknowledged: false)
            }
            let started = await waitUntil { env3.engine.log.contains { $0.hasPrefix("signPlanTask") } }
            t(started, "the engine is signing")
            signing.cancel()
            let cancelled = await signing.value
            gate.open()
            eq(failedError(cancelled)?.key, BILPublicSignerErrors.genericKey, "a cancelled sign → match.invalid.body")
            eq(failedError(cancelled)?.code, "CANCELLED", "… code CANCELLED")
            await blockingWait(seconds: 0.3)            // the late engine answer arrives and is dropped
            t(readyState(c3, id3, "after the cancel") != nil, "state kept")
            t(c3.answer(id3) == nil && env3.journal.records.isEmpty, "nothing answered, nothing recorded")
            env3.engine.signHook = nil
            let retry = await c3.signTask(id3, taskId: task3.id, password: CW.PASSWORD, riskAcknowledged: false)
            eq(retry, .signed(taskId: task3.id, nextTaskId: nil), "the retry signs")
        }

        // A request that is not Ready (setupRequired): signing it gives its status text, nothing unlocked.
        let env4 = Env()
        env4.engine.planFor = { _, wallets, recorded in setupRequiredPlan(wallets, recorded) }
        env4.wallets.add(CW.ABANDON, prepared: false)
        let c4 = env4.coordinator()
        guard let id4 = try? await c4.prepare(frames("T8-flow-evm-personal")), case .notReady(_, .setupRequired, _, _, _) = c4.state(id4) else {
            t(false, "setupRequired")
            return
        }
        let taskId = SigningVectors.plan("T8-flow-evm-personal").tasks.first?.id ?? "task"
        let notReady = await c4.signTask(id4, taskId: taskId, password: CW.PASSWORD, riskAcknowledged: true)
        eq(failedError(notReady)?.key, "PublicProtocol.match.setupRequired.body", "signing a setupRequired request → its status text")
        eq(env4.wallets.unlocks, 0, "nothing unlocked")

        // setupThenResolve cancelled while it waits for the request (a Match again holds it): .failed(.engine, CANCELLED).
        let gate = Gate()
        env4.engine.reviewHook = { await gate.wait() }
        let reviews = env4.engine.log.filter { $0 == "reviewAndResolve" }.count
        let again = Task { @MainActor in await c4.resolveAgain(id4) }
        let matching = await waitUntil { env4.engine.log.filter { $0 == "reviewAndResolve" }.count > reviews }
        t(matching, "Match again holds the request")
        let setup = Task { @MainActor in await c4.setupThenResolve(id4, walletId: CW.ABANDON, password: CW.PASSWORD) }
        let queued = await waitUntil { (c4.store.get(id4)?.lock.queuedCount ?? 0) == 1 }
        t(queued, "the inline Prepare waits for the request")
        setup.cancel()
        let cancelledSetup = await setup.value
        eq(cancelledSetup, .failed(.engine, engineCode: "CANCELLED"), "a cancelled inline Prepare → .failed(.engine, CANCELLED)")
        eq(env4.wallets.prepares, 0, "nothing prepared")
        env4.engine.reviewHook = nil
        gate.open()
        await again.value
        if case .notReady(_, .setupRequired, _, _, _) = c4.state(id4) {} else { t(false, "still setupRequired: \(stateName(c4.state(id4)))") }
    }
}
