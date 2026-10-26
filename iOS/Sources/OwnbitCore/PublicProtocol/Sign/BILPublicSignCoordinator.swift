//  BILPublicSignCoordinator.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Public protocol (cold signer) — the signing flow for other wallets' requests (spec S§8.1, §8.4; checklist C-GEN-9…16,
//  C-RESP-1…4, C-OVC; design §3.17, R5 §1, §4.4–4.5). Port of Android
//  core/publicsigner/.../sign/PublicSignCoordinator.kt (b8c70c25):
//
//    prepare → (paste: decode) → review + resolve on one fresh engine context → engine-review checks → native pre-check →
//    D43 card → outpoint check → policy → review page → one password per task → `signPlanTask` (fresh context) → result
//    checks → (last task) `encodeResponse` or the native TronLink answer → native post-check → answer handed out.
//
//  - Matching (C-GEN-8 / C-GEN-9): the resolver gets every eligible wallet in home order (`resolverInputs`:
//    `{localWalletId, publicIndex}` only for an authentic index); too much for the bridge → `BILPublicResolverInput.fit`.
//    A ready plan must name only offered wallets, each with the identity of the index offered.
//  - Signing (C-GEN-10, C-GEN-14…16): tasks in plan order; the wallet unlocked is the task's; the wallets and their
//    indexes must be unchanged since matching (else "Match again"); the seed exists only inside the timed sign step and
//    the engine's single-call secret context; at most `signTimeout` per task (unlock + sign + answer + post-check; the
//    work returns values only and its late result is dropped); a result for a discarded request is dropped; an answered
//    request cannot be signed again (single use); every failure ends in a state / outcome — never a stuck HUD.
//  - Bitcoin (R2-2, D-30): every input is checked against the signed-outpoint memory at matching and again inside
//    `BILBitcoinSigningLock` (shared with the internal `bb_sign:` path) right before signing; check → sign → record of a
//    request's last task happen under that one lock. Unavailable memory: witness-only inputs are refused (`err.integrity`),
//    others proceed; a record failure withholds a witness-only answer (`err.verify`, `OUTPOINT_MEMORY`) and is ignored
//    otherwise.
//  - "交出回传" order of a verified answer (S§8.1): ① outpoint record → ② single-use session → ③ recent hashes →
//    ④ the offline-signing journal (`BILPublicAnswerJournaling.publicAnswered`, once; never changes the outcome) → ⑤ answered.
//  - TronLink (R2-7): answered natively (`BILPublicTronLinkAnswer`), then post-checked like every answer; TokenPocket texts
//    are refused before the engine (owner 2026-10-13).
//  - iOS: empty / wrong passwords are validated by the existing password dialog (D-21); the coordinator still never
//    unlocks for an empty password. No online condition anywhere (product decision; C-BOUND).
//
//  Main actor (Core Data wallet objects, D43 token lookup). Nothing of a session is written anywhere; logs carry only
//  codes (C-KEY-5). Pure Foundation (the app's wiring, `+Live.swift`, is not part of this package).
//

import Foundation

@MainActor public final class BILPublicSignCoordinator: BILPublicSignCoordinating {

    /// Bound of one task (unlock + engine context + `signPlanTask` (+ the answer and its post-check for the last task)).
    public nonisolated static let signTimeout: TimeInterval = 90
    /// Largest pasted text in UTF-8 bytes (BitSigner `importPayload`: 256 KiB).
    public nonisolated static let maxPasteBytes = 262_144
    /// The engine's resolver limit (`resolveSigningPlan`: at most 100 wallets).
    public nonisolated static let maxResolverWallets = BILPublicResolverInput.maxWallets

    public struct Dependencies {
        public var engine: BILPublicSignerEngining
        public var index: BILPublicIndexStoring
        public var wallets: BILPublicWalletDirectory
        /// nil / unavailable → D-30 (witness-only Bitcoin inputs are refused).
        public var memory: BILSignedOutpointMemory?
        public var journal: BILPublicAnswerJournaling?
        /// The D43 reading (live: `BILWCInsightSources.interpret`, main thread); nil = no card.
        public var interpret: (BILSignatureRequest) -> BILSignatureInsight?
        /// The UTF-8 size of the engine's resolver request (live: `BILPublicSignerEngine.resolveRequestByteCount`).
        public var requestByteCount: (BILJSONObject, [BILJSONObject]) -> Int
        public var now: () -> Date
        /// The per-task bound (additive; tests shorten it).
        public var signTimeout: TimeInterval = BILPublicSignCoordinator.signTimeout

        public init(engine: BILPublicSignerEngining, index: BILPublicIndexStoring, wallets: BILPublicWalletDirectory,
                    memory: BILSignedOutpointMemory?, journal: BILPublicAnswerJournaling?,
                    interpret: @escaping (BILSignatureRequest) -> BILSignatureInsight?,
                    requestByteCount: @escaping (BILJSONObject, [BILJSONObject]) -> Int = BILPublicSignerEngine.resolveRequestByteCount,
                    now: @escaping () -> Date = Date.init,
                    signTimeout: TimeInterval = BILPublicSignCoordinator.signTimeout) {
            self.engine = engine
            self.index = index
            self.wallets = wallets
            self.memory = memory
            self.journal = journal
            self.interpret = interpret
            self.requestByteCount = requestByteCount
            self.now = now
            self.signTimeout = signTimeout
        }
    }

    /// The requests in memory (8) and the recently answered hashes (16).
    let store: BILPublicRequestStore
    let recent: BILRecentRequestHashes

    private let deps: Dependencies

    public init(_ deps: Dependencies) {
        self.deps = deps
        self.store = BILPublicRequestStore()
        self.recent = BILRecentRequestHashes()
    }

    /// R5 §1.5: the resolver input within the bridge's limits, nil when it cannot fit (`err.tooManyWallets`).
    public func fitResolverInput(request: BILJSONObject, inputs: [BILJSONObject]) -> [BILJSONObject]? {
        return BILPublicResolverInput.fit(request: request, inputs: inputs, byteCount: deps.requestByteCount)
    }

    // MARK: - BILPublicSignCoordinating

    public func prepare(_ input: BILPublicInput) async throws -> String {
        let request: BILJSONObject
        switch input {
        case .frames(let r):
            request = r
        case .pasted(let text):
            request = try await decode(text)
        }
        let entry = BILPublicRequestEntry(id: BILPublicRequestStore.newId(), request: request, info: BILPublicRequestInfo.of(request))
        store.put(entry)
        do {
            try await entry.lock.withLockCancellable {
                try await self.resolveLocked(entry)
            }
        } catch {
            // Only a cancellation gets here: the caller never gets the id, so no orphan request is left behind.
            store.remove(entry.id)
            throw error
        }
        return entry.id
    }

    public func state(_ requestId: String) -> BILPublicSignState {
        return store.get(requestId)?.state ?? .gone
    }

    public func observe(_ requestId: String, _ onChange: @escaping (BILPublicSignState) -> Void) -> BILPublicObservation {
        guard let entry = store.get(requestId) else {
            onChange(.gone)
            return BILPublicObservation(onCancel: {})
        }
        return entry.addObserver(onChange)
    }

    /// "Match again": resolves the same request again with the current wallets (not once answered or partly signed).
    public func resolveAgain(_ requestId: String) async {
        guard let entry = store.get(requestId) else { return }
        do {
            try await entry.lock.withLockCancellable {
                switch entry.state {
                case .answered:
                    return
                case .ready(let ready) where ready.hasPartialSignatures:
                    return
                default:
                    try await self.resolveLocked(entry)
                }
            }
        } catch {
            BILPublicLog.code("sign", "RESOLVE_CANCELLED")
        }
    }

    /// The inline Prepare of a `setupRequired` request: prepares `walletId` (one of its `setupWalletIds`) with the password
    /// the dialog accepted, then — on success — matches again. `.notEligible` for a wallet the sheet did not offer.
    public func setupThenResolve(_ requestId: String, walletId: String, password: String) async -> BILPublicPrepareResult {
        guard let entry = store.get(requestId) else { return .notEligible }
        do {
            return try await entry.lock.withLockCancellable { () async throws -> BILPublicPrepareResult in
                guard case .notReady(_, let status, _, let setup, _) = entry.state, status == .setupRequired,
                      setup.contains(where: { BILJSONExact.equal($0, walletId) }) else { return .notEligible }
                let result = await self.deps.index.prepare(walletId: walletId, password: password)
                if case .ready = result, !entry.discarded {
                    try await self.resolveLocked(entry)
                }
                return result
            }
        } catch {
            BILPublicLog.code("sign", "SETUP_CANCELLED")
            return .failed(.engine, engineCode: "CANCELLED")
        }
    }

    public func signTask(_ requestId: String, taskId: String, password: String, riskAcknowledged: Bool) async -> BILPublicTaskOutcome {
        guard let entry = store.get(requestId) else { return .gone }
        do {
            return try await entry.lock.withLockCancellable { () async throws -> BILPublicTaskOutcome in
                try await self.signLocked(entry, taskId: taskId, password: password,
                                          riskAcknowledged: riskAcknowledged)
            }
        } catch is CancellationError {
            BILPublicLog.code("sign", "SIGN_CANCELLED")
            return entry.discarded ? .gone : .failed(BILPublicSignError(BILPublicSignerErrors.genericKey, code: "CANCELLED"))
        } catch {
            // C-GEN-16: an unmapped failure ends this attempt with an alert; the session only advances after a verified
            // step, so the task may be tried again.
            BILPublicLog.failure("sign", error)
            return entry.discarded ? .gone : .failed(BILPublicSignerErrors.unexpected)
        }
    }

    public func answer(_ requestId: String) -> BILPublicResponseQr? {
        return store.get(requestId)?.session?.response
    }

    /// Forgets `requestId` (reject, Done, leaving the page): an in-flight result for it is dropped.
    public func discard(_ requestId: String) {
        store.remove(requestId)
    }

    // MARK: - Prepare

    private func decode(_ text: String) async throws -> BILJSONObject {
        if text.utf8.count > BILPublicSignCoordinator.maxPasteBytes {
            throw BILPublicPrepareError(error: BILPublicSignError(Key.tooLarge, code: "LIMIT"))
        }
        do {
            if let mapped = try BILPublicPasteRouting.otherWalletRequest(text) {
                return mapped
            }
        } catch let refusal as BILOtherWalletRequestError {
            BILPublicLog.code("sign", refusal.error.code ?? "PASTE_REFUSED")
            throw BILPublicPrepareError(error: refusal.error)
        }
        let raw: BILJSONObject
        do {
            raw = try await deps.engine.decodePayload(text)
        } catch let refusal as BILPublicSignerRefusal {
            BILPublicLog.code("sign", refusal.code)
            throw BILPublicPrepareError(error: BILPublicSignerErrors.of(refusal))
        } catch let failure as BILPublicSignerFailure {
            BILPublicLog.code("sign", failure.code)
            throw BILPublicPrepareError(error: BILPublicSignerErrors.engineUnavailable)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            BILPublicLog.failure("sign", error)
            throw BILPublicPrepareError(error: BILPublicSignError(Key.qrMalformed, code: "UNEXPECTED"))
        }
        guard let progress = try? BILScanProgress.fromEngine(raw, parts: 0), let request = progress.request else {
            throw BILPublicPrepareError(error: BILPublicSignError(Key.qrMalformed))
        }
        return request
    }

    /// Review + resolve + checks of `entry`'s request; sets its state. Holds the entry's lock. Rethrows only a cancellation
    /// (after setting a "Match again" refusal).
    private func resolveLocked(_ entry: BILPublicRequestEntry) async throws {
        guard !entry.discarded else { return }
        let info = entry.info
        entry.session = nil
        entry.setState(.resolving(info))
        let next: BILPublicSignState
        do {
            next = try await resolution(entry)
        } catch is CancellationError {
            // Never leave the page on the "finding wallet" HUD: matching can be started again.
            if !entry.discarded {
                entry.setState(.refused(info: info, error: BILPublicSignError(BILPublicSignerErrors.genericKey, code: "CANCELLED"),
                                        review: nil, canMatchAgain: true))
            }
            throw CancellationError()
        } catch let refusal as BILPublicSignerRefusal {
            BILPublicLog.code("sign", refusal.code)
            next = .refused(info: info, error: BILPublicSignerErrors.of(refusal), review: nil, canMatchAgain: false)
        } catch let failure as BILPublicSignerFailure {
            BILPublicLog.code("sign", failure.code)
            next = .refused(info: info, error: BILPublicSignerErrors.engineUnavailable, review: nil, canMatchAgain: true)
        } catch is BILMalformedEngineResult {
            BILPublicLog.code("sign", "MALFORMED_ENGINE_RESULT")
            next = .refused(info: info, error: integrityError(), review: nil, canMatchAgain: false)
        } catch {
            // C-GEN-16: a failure nobody mapped ends matching with an alert instead of leaving the HUD up.
            BILPublicLog.failure("sign", error)
            next = .refused(info: info, error: BILPublicSignerErrors.unexpected, review: nil, canMatchAgain: true)
        }
        if entry.discarded { return }
        if case .ready = next {} else { entry.session = nil }
        entry.setState(next)
    }

    private func resolution(_ entry: BILPublicRequestEntry) async throws -> BILPublicSignState {
        let info = entry.info
        let request = entry.request
        let inputs = await deps.index.resolverInputs()
        try Task.checkCancellation()
        if inputs.isEmpty {
            return .refused(info: info, error: BILPublicSignError(Key.noWallet), review: nil, canMatchAgain: false)
        }
        guard let wallets = fitResolverInput(request: request, inputs: inputs) else {
            return .refused(info: info, error: BILPublicSignerErrors.tooManyWallets, review: nil, canMatchAgain: false)
        }
        let snapshot = BILPublicResolverInput.snapshot(of: inputs)
        entry.walletSnapshot = snapshot
        let result = try await deps.engine.reviewAndResolve(request: request, wallets: wallets)
        try Task.checkCancellation()
        let parsedReview = try? BILPublicReview.fromEngine(result.review)
        let requestChain = BILPsChain.fromWire(request.str("chain"))
        // BitSigner `AppStore.prepare` (R5 §1.4): a 64-hex commitment, the request's chain, at least one row.
        guard let engineReview = parsedReview, BILEngineJSON.isHex(engineReview.requestHash, bytes: 32),
              let reviewChain = engineReview.chain, reviewChain == requestChain, !engineReview.fields.isEmpty else {
            return integrity(info, parsedReview)
        }
        guard engineReview.canSign else {
            return .refused(info: info, error: BILPublicSignError(Key.unsupported), review: engineReview, canMatchAgain: false)
        }
        let plan = try BILPublicPlan.fromEngine(result.plan)
        if !plan.isReady {
            let setup = plan.status == .setupRequired ? snapshot.unpreparedWalletIds : []
            var shown = engineReview
            if let planReview = plan.review, BILVerifyText.equalsIgnoringCase(planReview.requestHash, engineReview.requestHash) {
                shown = planReview
            }
            return .notReady(info: info, status: plan.status, review: shown, setupWalletIds: setup, engineMessage: plan.message)
        }
        guard let planHash = plan.requestHash, BILVerifyText.equalsIgnoringCase(planHash, engineReview.requestHash) else {
            return integrity(info, engineReview)
        }
        // The plan names only wallets we offered, each with the identity of the index we offered.
        for task in plan.tasks {
            guard let offered = snapshot.walletKeyId(task.localWalletId), BILJSONExact.equal(offered, task.walletKeyId) else {
                return integrity(info, engineReview)
            }
        }
        // The plan's review adds facts proven with the matched wallets' keys (verified Bitcoin change): the "chosen review"
        // of both the pre-check and the policy (Android :480, lead addendum C5).
        var review = engineReview
        if let planReview = plan.review, planReview.chain == engineReview.chain, !planReview.fields.isEmpty {
            review = planReview
        }
        let reviewedChainId = review.network?.chainId
        let verdict = try await BILPublicBackground.run {
            BILPublicSignVerifier.pre(request: request, plan: plan, reviewedChainId: reviewedChainId)
        }
        let verified: BILVerifiedPayload
        switch verdict {
        case .refused(let reason, _):
            BILPublicLog.code("sign", reason.rawValue)
            return .refused(info: info, error: BILPublicSignError(BILPublicSignerErrors.verifierKey(reason.rawValue), code: reason.rawValue),
                            review: review, canMatchAgain: false)
        case .ok(let payload):
            guard let p = payload else {
                // Android: `session.verified!!` → an unmapped failure.
                BILPublicLog.code("sign", "PRE_NO_PAYLOAD")
                return .refused(info: info, error: BILPublicSignerErrors.unexpected, review: nil, canMatchAgain: true)
            }
            verified = p
        }
        let session = BILPublicSignSession(requestId: entry.id, request: request, review: review, plan: plan, verified: verified)
        let insightInput = BILPublicSignInsight.details(request: request, plan: plan, verified: verified)
        let insight = insightInput.flatMap { deps.interpret($0.request) }
        // R2-2: every input of a Bitcoin request against the amounts this device already signed for the same coins.
        var conflicts: [Int] = []
        if case .bitcoinPsbt(_, let maps, let witnessOnly) = verified {
            if let memory = deps.memory {
                do {
                    conflicts = try memory.conflicts(maps.outpointClaims())
                } catch {
                    // D-30: witness-only inputs need the memory (S§8.3a); the others' amounts are locked by the
                    // signature or by the full previous transaction.
                    BILPublicLog.code("sign", "OUTPOINT_MEMORY_UNAVAILABLE")
                    if !witnessOnly.isEmpty { return integrity(info, review) }
                }
            } else if !witnessOnly.isEmpty {
                BILPublicLog.code("sign", "OUTPOINT_MEMORY_MISSING")
                return integrity(info, review)
            }
        }
        // The request-only review: what the page shows when an output is beyond the change bound; the policy then takes the
        // engine risk from it, so the pill / HIGH FEE banner / checkbox match the shown review.
        let policy = BILPublicSignPolicy.evaluate(review: review, plan: plan, verified: verified, insightRisk: insight?.risk,
                                                  outpointConflicts: conflicts, requestOnlyReview: engineReview)
        if let refusal = policy.refusal {
            BILPublicLog.code("sign", refusal.code ?? "POLICY")
            return .refused(info: info, error: refusal, review: review, canMatchAgain: false)
        }
        // C-BTC-7: an output proven to be the wallet's beyond the index bound is a normal output: show the request-only
        // review (every output a payment, no change label).
        let shown = policy.ackReasons.contains(.changeBeyondBound) ? engineReview : review
        if !entry.discarded { entry.session = session }
        return .ready(BILPublicSignReady(info: info, review: shown, plan: plan, policy: policy, insight: insight,
                                         insightInput: insightInput, signedBefore: recent.signedAt(planHash), completedTaskIds: []))
    }

    // MARK: - Sign

    /// What the timed sign step produced (values only; applied by `signChecked` if the race against the bound was won).
    private enum SignStep {
        case noSeed
        case engineDown
        case unexpected
        case refused(BILPublicSignerRefusal)
        case malformedResult
        case foreignResult
        case partial(BILPublicSignResult)
        case answerFailed(BILPublicSignError)
        case postRefused(BILPublicSignVerifier.Reason)
        case verified(BILPublicSignResult, BILPublicResponseQr)
    }

    /// The engine call of one task with the wallet's seed (the only place it exists outside the engine's context).
    private enum EngineStep {
        case noSeed, engineDown, unexpected
        case refused(BILPublicSignerRefusal)
        case done(BILJSONObject)
    }

    private func signLocked(_ entry: BILPublicRequestEntry, taskId: String, password: String,
                            riskAcknowledged: Bool) async throws -> BILPublicTaskOutcome {
        if entry.discarded { return .gone }
        guard case .ready(let ready) = entry.state, let session = entry.session else { return .failed(notSignable(entry)) }
        guard let task = session.nextTask else { return .failed(BILPublicSignError(Key.alreadySigned)) }
        guard BILJSONExact.equal(task.id, taskId) else { return .failed(BILPublicSignError(Key.integrity, code: "TASK_ORDER")) }
        // iOS: the dialog never passes an empty password (D-21); never unlock for one (Android `EmptyPassword`, state kept).
        if password.isEmpty { return .failed(BILPublicSignError(Key.emptyPassword, code: "EMPTY_PASSWORD")) }
        if ready.policy.requiresAcknowledgement && !riskAcknowledged { return .acknowledgementRequired }
        // C-GEN-9 / BitSigner: the wallets and their indexes must be what the plan was resolved with.
        let inputs = await deps.index.resolverInputs()
        if BILPublicResolverInput.snapshot(of: inputs) != entry.walletSnapshot {
            BILPublicLog.code("sign", "WALLETS_CHANGED")
            return fail(entry, ready, BILPublicSignError(Key.integrity, code: "WALLETS_CHANGED"), canMatchAgain: !ready.hasPartialSignatures)
        }
        guard case .bitcoinPsbt(_, let maps, let witnessOnly)? = session.verified else {
            return try await signChecked(entry, ready, session, task, password, riskAcknowledged)
        }
        // R2-2: another request over the same coins may have been signed since this one was matched. Bitcoin requests sign
        // one at a time across this coordinator and the Ownbit protocol (check → sign → record), so two requests that claim
        // different amounts for one outpoint can never both pass this check before either is recorded.
        return try await BILBitcoinSigningLock.shared.withLockCancellable { () async throws -> BILPublicTaskOutcome in
            if entry.discarded { return .gone }
            var conflicts: [Int] = []
            if let memory = self.deps.memory {
                do {
                    conflicts = try memory.conflicts(maps.outpointClaims())
                } catch {
                    // D-30: only a BTC request without witness-only inputs can get here (amounts locked otherwise). A
                    // witness-only request reached Ready only after this same memory read at matching, and a memory that
                    // read keeps its rows for the process (`BILSignedOutpointMemory` never re-reads), so the refusal
                    // below is defensive: never sign witness-only inputs without the memory.
                    BILPublicLog.code("sign", "OUTPOINT_MEMORY_UNAVAILABLE")
                    if !witnessOnly.isEmpty {
                        return self.fail(entry, ready, self.integrityError(), canMatchAgain: false)
                    }
                }
            }
            if let first = conflicts.min() {
                BILPublicLog.code("sign", BILPublicSignPolicy.prevoutConflictCode)
                return self.fail(entry, ready, BILPublicSignerErrors.prevoutConflict(inputNumber: first + 1), canMatchAgain: false)
            }
            return try await self.signChecked(entry, ready, session, task, password, riskAcknowledged)
        }
    }

    /// Signs `task` within the bound and hands out the verified answer of the last task (`answered`, outside the bound:
    /// local writes only).
    private func signChecked(_ entry: BILPublicRequestEntry, _ ready: BILPublicSignReady, _ session: BILPublicSignSession,
                             _ task: BILPublicTask, _ password: String,
                             _ riskAcknowledged: Bool) async throws -> BILPublicTaskOutcome {
        let step: SignStep
        do {
            step = try await BILPublicTimeout.run(seconds: deps.signTimeout) {
                try await self.signAndAnswer(session: session, task: task, password: password,
                                             riskAcknowledged: riskAcknowledged)
            }
        } catch is BILPublicTimeout.Expired {
            BILPublicLog.code("sign", "TIMEOUT")
            return entry.discarded ? .gone : .failed(BILPublicSignerErrors.engineUnavailable.with(code: "TIMEOUT"))
        }
        if entry.discarded { return .gone }
        switch step {
        case .noSeed:
            return fail(entry, ready, BILPublicSignError(Key.noWallet, code: "NO_SECRET"), canMatchAgain: false)
        case .engineDown:
            return .failed(BILPublicSignerErrors.engineUnavailable)
        case .unexpected:
            return .failed(BILPublicSignerErrors.unexpected)
        case .refused(let refusal):
            BILPublicLog.code("sign", refusal.code)
            let error = BILPublicSignerErrors.of(refusal)
            // The engine insisted on consent the policy did not ask for: keep the page, ask for it.
            if BILJSONExact.equal(refusal.code, "RISK") { return .failed(error) }
            return fail(entry, ready, error, canMatchAgain: false)
        case .malformedResult, .foreignResult:
            BILPublicLog.code("sign", "RESULT_INTEGRITY")
            return fail(entry, ready, integrityError(), canMatchAgain: false)
        case .partial(let result):
            var signed = session
            signed.completedTaskIds.append(task.id)
            signed.lastResult = result
            entry.session = signed
            var next = ready
            next.completedTaskIds = signed.completedTaskIds
            entry.setState(.ready(next))
            return .signed(taskId: task.id, nextTaskId: signed.nextTask?.id)
        case .answerFailed(let error):
            BILPublicLog.code("sign", error.code ?? "ANSWER_FAILED")
            return fail(entry, ready, error, canMatchAgain: false)
        case .postRefused(let reason):
            BILPublicLog.code("sign", reason.rawValue)
            return fail(entry, ready, BILPublicSignError(Key.verify, code: reason.rawValue), canMatchAgain: false)
        case .verified(let result, let response):
            var signed = session
            signed.completedTaskIds.append(task.id)
            signed.lastResult = result
            return answered(entry, ready, signed, response, taskId: task.id, riskAcknowledged: riskAcknowledged)
        }
    }

    /// The timed work of one task: unlock + `signPlanTask`, the result checks, and for the last task the answer and its
    /// native post-check. Returns values only (never touches the entry): the caller applies them if the race was won.
    private func signAndAnswer(session: BILPublicSignSession, task: BILPublicTask, password: String,
                               riskAcknowledged: Bool) async throws -> SignStep {
        let raw: BILJSONObject
        switch try await signWithSeed(session: session, task: task, password: password,
                                      riskAcknowledged: riskAcknowledged) {
        case .noSeed: return .noSeed
        case .engineDown: return .engineDown
        case .unexpected: return .unexpected
        case .refused(let refusal): return .refused(refusal)
        case .done(let r): raw = r
        }
        guard let result = try? BILPublicSignResult.fromEngine(raw) else { return .malformedResult }
        let plan = session.plan
        let completed = session.completedTaskIds + [task.id]
        let belongs = result.chain == plan.chain && same(result.requestHash, plan.requestHash) && same(result.planHash, plan.planHash)
            && BILJSONExact.equal(result.taskId, task.id) && result.completedTaskIds.count == completed.count
            && zip(result.completedTaskIds, completed).allSatisfy { BILJSONExact.equal($0, $1) }
        guard belongs else { return .foreignResult }
        var signed = session
        signed.completedTaskIds = completed
        signed.lastResult = result
        if signed.nextTask != nil { return .partial(result) }
        // Last task: the answer in the request's own transport — the engine's encoder, or the native TronLink answer.
        let response: BILPublicResponseQr
        if let type = session.transportType, BILJSONExact.equal(type, BILTronLinkRequestMapper.transportType) {
            guard let verified = session.verified, let signature = BILPublicTronLinkAnswer.signature(of: result),
                  let answer = try? BILPublicTronLinkAnswer.response(request: session.request, verified: verified, signature: signature) else {
                return .answerFailed(BILPublicSignError(Key.verify, code: "ANSWER"))
            }
            response = answer
        } else {
            do {
                let encoded = try await deps.engine.encodeResponse(request: session.request, result: result.raw)
                response = try BILPublicResponseQr.fromEngine(encoded)
            } catch let refusal as BILPublicSignerRefusal {
                return .answerFailed(BILPublicSignError(Key.verify, code: refusal.code))
            } catch is BILPublicSignerFailure {
                return .answerFailed(BILPublicSignError(Key.verify))
            } catch is BILMalformedEngineResult {
                return .answerFailed(BILPublicSignError(Key.verify, code: "INTEGRITY"))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                return .unexpected
            }
        }
        let request = session.request
        let verified = session.verified
        let verdict = try await BILPublicBackground.run {
            BILPublicSignVerifier.post(request: request, plan: plan, verified: verified, result: result, response: response)
        }
        if case .refused(let reason, _) = verdict { return .postRefused(reason) }
        return .verified(result, response)
    }

    /// Unlocks the task's wallet (the password the dialog accepted) and runs `signPlanTask` on a fresh secret context. The
    /// seed lives only in this function.
    private func signWithSeed(session: BILPublicSignSession, task: BILPublicTask, password: String,
                              riskAcknowledged: Bool) async throws -> EngineStep {
        guard let seedHex = deps.wallets.seed(walletId: task.localWalletId, password: password) else {
            return .noSeed
        }
        do {
            return .done(try await deps.engine.signPlanTask(request: session.request, plan: session.plan.raw, taskId: task.id,
                                                            seedHex: seedHex, riskAcknowledged: riskAcknowledged,
                                                            previousResult: session.lastResult?.raw))
        } catch let refusal as BILPublicSignerRefusal {
            return .refused(refusal)
        } catch is BILPublicSignerFailure {
            BILPublicLog.code("sign", "ENGINE_DOWN")
            return .engineDown
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            BILPublicLog.failure("sign", error)
            return .unexpected
        }
    }

    /// Hands out a verified answer — the "交出回传" order (S§8.1): ① the signed-outpoint memory (a witness-only request gets
    /// no answer when it cannot be written), ② the single-use session, ③ the recent hashes, ④ the offline-signing record,
    /// ⑤ the answered state.
    private func answered(_ entry: BILPublicRequestEntry, _ ready: BILPublicSignReady, _ signed: BILPublicSignSession,
                          _ response: BILPublicResponseQr, taskId: String, riskAcknowledged: Bool) -> BILPublicTaskOutcome {
        if entry.discarded { return .gone }
        let plan = signed.plan
        if case .bitcoinPsbt(_, let maps, let witnessOnly)? = signed.verified, let memory = deps.memory {
            do {
                // Every input any task signed; an unreadable one is a record failure, never "skip" (design §3.10).
                guard let claims = maps.claims(forInputs: plan.tasks.flatMap { $0.inputs }) else {
                    throw BILSignedOutpointMemory.Unavailable()
                }
                try memory.record(claims)
            } catch {
                BILPublicLog.code("sign", "OUTPOINT_MEMORY")
                if !witnessOnly.isEmpty {
                    return fail(entry, ready, BILPublicSignError(Key.verify, code: "OUTPOINT_MEMORY"), canMatchAgain: false)
                }
            }
        }
        if entry.discarded { return .gone }
        var used = signed
        used.response = response
        entry.session = used
        let now = deps.now()
        recent.record(plan.requestHash ?? "", at: now)
        // R2-9: one offline-signing record per verified answer (never blocks, never changes the outcome). The app built
        // its record here (`BILPublicSignRecords.of`, same inputs); the package hands the inputs to the host's journal.
        deps.journal?.publicAnswered(BILPublicAnsweredRequest(info: entry.info, request: signed.request, ready: ready,
                                                              response: response, acknowledged: riskAcknowledged, answeredAt: now))
        entry.setState(.answered(info: entry.info, review: ready.review, plan: plan, response: response))
        return .signed(taskId: taskId, nextTaskId: nil)
    }

    /// Ends signing of `entry` with `error` (state → refused, partial results dropped).
    private func fail(_ entry: BILPublicRequestEntry, _ ready: BILPublicSignReady, _ error: BILPublicSignError,
                      canMatchAgain: Bool) -> BILPublicTaskOutcome {
        if entry.discarded { return .gone }
        entry.session = nil
        entry.setState(.refused(info: entry.info, error: error, review: ready.review, canMatchAgain: canMatchAgain))
        return .failed(error)
    }

    private func notSignable(_ entry: BILPublicRequestEntry) -> BILPublicSignError {
        switch entry.state {
        case .refused(_, let error, _, _):
            return error
        case .answered:
            return BILPublicSignError(Key.alreadySigned)
        case .notReady(_, let status, _, _, _):
            return BILPublicSignError(BILPublicSignerErrors.statusBodyKey(status.rawValue))
        default:
            return BILPublicSignError(Key.integrity)
        }
    }

    // MARK: - Helpers

    private enum Key {
        static let integrity = "PublicProtocol.err.integrity"
        static let verify = "PublicProtocol.err.verify"
        static let unsupported = "PublicProtocol.err.unsupported"
        static let alreadySigned = "PublicProtocol.err.alreadySigned"
        static let tooLarge = "PublicProtocol.err.tooLarge"
        static let qrMalformed = "PublicProtocol.err.qrMalformed"
        static let noWallet = "PublicProtocol.err.noWallet"
        /// The iOS wallet-password dialog's own text (`String.sendConfirmPasswordMessageEmpty`, table SendC).
        static let emptyPassword = "SendC.confirm.passwordMessageEmpty"
    }

    private func integrityError() -> BILPublicSignError {
        return BILPublicSignError(Key.integrity, code: "INTEGRITY")
    }

    private func integrity(_ info: BILPublicRequestInfo, _ review: BILPublicReview?) -> BILPublicSignState {
        BILPublicLog.code("sign", "INTEGRITY")
        return .refused(info: info, error: integrityError(), review: review, canMatchAgain: false)
    }

    /// Exact (code-unit) equality of hashes both parsers lower-case.
    private func same(_ a: String, _ b: String?) -> Bool {
        guard let b = b else { return false }
        return BILJSONExact.equal(a, b)
    }
}
