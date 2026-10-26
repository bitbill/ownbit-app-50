//  BILPublicSignContracts.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Public protocol (cold signer) — the coordinator's contract types that the presenter, the pages and the scan router
//  compile against: input, request info, policy result, ready session, states, task outcomes, prepare error,
//  observation token and the coordinator protocol (design §3.5). Ports of Android
//  core/publicsigner/.../sign/PublicSignCoordinator.kt:61-197 (PublicInput, PublicRequestInfo, PublicSignState,
//  TaskOutcome, PublicPrepareException) and sign/PublicSignPolicy.kt:45-75 (AckReason, OwnbitWarning, Result).
//  Pure Foundation (+ the pure Security Center D43 models `BILSignatureRisk` / `BILSignatureRequest` /
//  `BILSignatureInsight`).
//

import Foundation

/// What `BILPublicSignCoordinating.prepare` starts from.
public enum BILPublicInput {
    /// A completed camera scan: the engine's decoded request (or the request the TronLink collector mapped).
    case frames(BILJSONObject)
    /// Pasted text (PSBT Base64 / hex, UR / BBQr frames one per line, a TronLink JSON), decoded by the coordinator.
    case pasted(String)
}

// C-KEY-5: an input names only its kind and size (Android `PublicInput.Frames/Pasted.toString`).
extension BILPublicInput: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        switch self {
        case .frames(let request): return "Frames(<\(request.count) keys>)"
        case .pasted(let text): return "Pasted(\(text.utf16.count) chars)"
        }
    }

    public var debugDescription: String {
        return description
    }

    public var customMirror: Mirror {
        return Mirror(self, children: [:])
    }
}

/// What the review / result pages show about a request regardless of its state: the chain, the transport (badge
/// detail, e.g. "UR · eth-sign-request") and the **unverified** origin ("Requested by (not verified)", rendered as
/// untrusted text, never used for trust).
public struct BILPublicRequestInfo: Equatable {
    /// Longest origin kept, in UTF-16 units (Android `MAX_ORIGIN`).
    public static let maxOrigin = 256

    public let chain: BILPsChain?
    public let transportType: String?
    public let origin: String?

    /// `chain` = `request.chain`, `transportType` = `request.transport.type`, `origin` = `request.transport.origin`
    /// cut to 256 UTF-16 units (a surrogate pair at the cut is dropped whole: Swift cannot hold half of one).
    public static func of(_ request: BILJSONObject) -> BILPublicRequestInfo {
        let transport = request.obj("transport")
        return BILPublicRequestInfo(chain: BILPsChain.fromWire(request.str("chain")),
                                    transportType: transport?.str("type"),
                                    origin: transport?.str("origin").map { BILKotlinText.prefix($0, utf16: maxOrigin) })
    }

    /// Exact (code units; design D-01).
    public static func == (lhs: BILPublicRequestInfo, rhs: BILPublicRequestInfo) -> Bool {
        return lhs.chain == rhs.chain && BILPublicModelText.sameOptional(lhs.transportType, rhs.transportType)
            && BILPublicModelText.sameOptional(lhs.origin, rhs.origin)
    }
}

/// Why the per-request checkbox is required (the text depends on the decode status, not on the reason).
public enum BILPublicAckReason: Hashable {
    case partiallyDecoded, opaque, highRisk, durableNonce, changeBeyondBound
}

/// An Ownbit (native) warning shown after the engine's (`PublicProtocol.warn.*`).
public struct BILPublicOwnbitWarning: Equatable {
    /// `tokenDecimals` has no trigger anywhere (Android keeps the kind; `warn.tokenDecimals` is never shown).
    public enum Kind: Equatable {
        case changeIndex, durableNonce, noChainId, tokenDecimals
    }

    public let kind: Kind
    /// Full key, e.g. "PublicProtocol.warn.changeIndex".
    public let key: String
    public let args: [BILTextArg]
    public let risk: BILSignatureRisk

    public init(kind: Kind, key: String, args: [BILTextArg] = [], risk: BILSignatureRisk) {
        self.kind = kind
        self.key = key
        self.args = args
        self.risk = risk
    }

    /// Exact (key and text arguments by code units; design D-01).
    public static func == (lhs: BILPublicOwnbitWarning, rhs: BILPublicOwnbitWarning) -> Bool {
        return lhs.kind == rhs.kind && BILPublicModelText.same(lhs.key, rhs.key) && BILPublicModelText.sameArgs(lhs.args, rhs.args)
            && lhs.risk == rhs.risk
    }
}

/// The policy verdict of one request (Android `PublicSignPolicy.Result`).
///
/// - `pageRisk` = max(engine risk of the shown review, the D43 card's risk, Ownbit's own warnings).
/// - `canSign` = no hard refusal; `requiresAcknowledgement` = signable and at least one reason.
/// - `ackReasons`: ordered, unique (first occurrence kept); equality ignores their order (Android `Set` equality).
public struct BILPublicPolicyResult: Equatable {
    public let engineRisk: BILSignatureRisk
    public let insightRisk: BILSignatureRisk?
    public let warnings: [BILPublicOwnbitWarning]
    public let ackReasons: [BILPublicAckReason]
    public let refusal: BILPublicSignError?

    public init(engineRisk: BILSignatureRisk, insightRisk: BILSignatureRisk?, warnings: [BILPublicOwnbitWarning],
         ackReasons: [BILPublicAckReason], refusal: BILPublicSignError?) {
        self.engineRisk = engineRisk
        self.insightRisk = insightRisk
        self.warnings = warnings
        var seen = Set<BILPublicAckReason>()
        self.ackReasons = ackReasons.filter { seen.insert($0).inserted }
        self.refusal = refusal
    }

    /// The risk shown once at the top of the page.
    public var pageRisk: BILSignatureRisk {
        var risk = engineRisk
        if let insight = insightRisk, insight.rank > risk.rank { risk = insight }
        for warning in warnings where warning.risk.rank > risk.rank {
            risk = warning.risk
        }
        return risk
    }

    public var canSign: Bool {
        return refusal == nil
    }

    /// The checkbox above "Sign with …" is required (and Sign stays disabled until it is checked).
    public var requiresAcknowledgement: Bool {
        return canSign && !ackReasons.isEmpty
    }

    /// This result with the D43 reading's `risk` (replacing the previous one): a high / critical reading adds
    /// `.highRisk` (once).
    public func withInsight(_ risk: BILSignatureRisk?) -> BILPublicPolicyResult {
        var reasons = ackReasons
        if let risk = risk, risk.rank >= BILSignatureRisk.high.rank { reasons.append(.highRisk) }
        return BILPublicPolicyResult(engineRisk: engineRisk, insightRisk: risk, warnings: warnings, ackReasons: reasons,
                                     refusal: refusal)
    }

    /// Reasons as a set (Android `Set<AckReason>`); warnings and the refusal exactly (code units; design D-01).
    public static func == (lhs: BILPublicPolicyResult, rhs: BILPublicPolicyResult) -> Bool {
        return lhs.engineRisk == rhs.engineRisk && lhs.insightRisk == rhs.insightRisk && lhs.warnings == rhs.warnings
            && Set(lhs.ackReasons) == Set(rhs.ackReasons) && BILPublicModelText.sameError(lhs.refusal, rhs.refusal)
    }
}

/// A D43 card's input: the interpreter `request`, the explanation page's `raw` data and the signing wallet's own
/// addresses for the card's "you" rule (Android `PublicSignInsight.Input`).
public struct BILPublicInsightInput {
    public let request: BILSignatureRequest
    public let raw: String
    public let ownAddresses: [String]
}

// C-KEY-5: the chain and the method only (Android `PublicSignInsight.Input.toString`).
extension BILPublicInsightInput: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        return "BILPublicInsightInput(\(request.chain), \(request.method))"
    }

    public var debugDescription: String {
        return description
    }

    public var customMirror: Mirror {
        return Mirror(self, children: [:])
    }
}

/// A signable request (Android `PublicSignState.Ready`). Rows come only from `review` (the plan's review; the
/// request-only engine review when `.changeBeyondBound` applies, so no output is labelled change); `policy` says which
/// warnings Ownbit adds, whether the checkbox is required and the page risk; `insight` is the D43 card read from the
/// signed bytes, `insightInput` its explanation-page data; `signedBefore` = when this exact request was answered
/// before in this process (C-RESP-4). Tasks are signed in plan order, one password each (`nextTask`).
public struct BILPublicSignReady {
    public let info: BILPublicRequestInfo
    /// The SHOWN review.
    public let review: BILPublicReview
    public let plan: BILPublicPlan
    public let policy: BILPublicPolicyResult
    public let insight: BILSignatureInsight?
    public let insightInput: BILPublicInsightInput?
    public let signedBefore: Date?
    public var completedTaskIds: [String]

    /// The first plan task not yet signed (exact id comparison), nil when every task is signed.
    public var nextTask: BILPublicTask? {
        return plan.tasks.first { !BILPublicModelText.contains(completedTaskIds, $0.id) }
    }

    /// "Signature n of m": 1-based number of `nextTask`.
    public var signatureNumber: Int {
        return completedTaskIds.count + 1
    }

    public var taskCount: Int {
        return plan.tasks.count
    }

    /// Rejecting now discards partial signatures (confirm first).
    public var hasPartialSignatures: Bool {
        return !completedTaskIds.isEmpty
    }
}

/// The state of one request (Android `PublicSignState`).
public enum BILPublicSignState {
    /// Decoding / matching (the clear HUD).
    case resolving(BILPublicRequestInfo)
    /// The engine matched no signable plan: `status` picks the card (`BILPublicSignerErrors.statusTitleKey` / `…BodyKey`).
    /// For `.setupRequired`, `setupWalletIds` lists only the eligible wallets without an authentic public index (home
    /// order) for the inline Prepare sheet; `engineMessage` is the engine's English status text (details only).
    case notReady(info: BILPublicRequestInfo, status: BILPlanStatus, review: BILPublicReview?, setupWalletIds: [String],
                  engineMessage: String?)
    /// Signable.
    case ready(BILPublicSignReady)
    /// Every task signed and the answer verified; the session is used up (single use).
    case answered(info: BILPublicRequestInfo, review: BILPublicReview, plan: BILPublicPlan, response: BILPublicResponseQr)
    /// Nothing can be signed (engine refusal, native verifier, Ownbit rule) or nothing was returned. `canMatchAgain`:
    /// matching may succeed after "Match again" (wallet data changed, engine could not start).
    case refused(info: BILPublicRequestInfo, error: BILPublicSignError, review: BILPublicReview?, canMatchAgain: Bool)
    /// Unknown or discarded id (replaced by a newer request, Done).
    case gone

    /// The engine's request commitment of the review the state shows (a new hash resets the consent): the review's
    /// `requestHash` for ready / answered, the optional review's for not-ready / refused, nil for resolving / gone
    /// (Android `PublicReviewPresenter` `requestHash` of each state).
    public var requestHash: String? {
        switch self {
        case .resolving, .gone:
            return nil
        case .notReady(_, _, let review, _, _):
            return review?.requestHash
        case .ready(let ready):
            return ready.review.requestHash
        case .answered(_, let review, _, _):
            return review.requestHash
        case .refused(_, _, let review, _):
            return review?.requestHash
        }
    }
}

/// Outcome of `BILPublicSignCoordinating.signTask`. Empty / wrong passwords never reach the coordinator (validated by
/// the iOS password dialog, D-21), so Android's `EmptyPassword` / `WrongPassword` have no case here.
public enum BILPublicTaskOutcome: Equatable {
    /// `taskId` signed; `nextTaskId` needs its own password, or nil → answered (show the result page).
    case signed(taskId: String, nextTaskId: String?)
    /// The checkbox is required and was not checked: nothing was unlocked.
    case acknowledgementRequired
    /// Nothing signed / nothing returned: the error to show. The state says whether signing can be retried.
    case failed(BILPublicSignError)
    /// The request is gone (discarded, replaced): close the page.
    case gone

    /// Exact (task ids and errors by code units; design D-01).
    public static func == (lhs: BILPublicTaskOutcome, rhs: BILPublicTaskOutcome) -> Bool {
        switch (lhs, rhs) {
        case let (.signed(a, nextA), .signed(b, nextB)):
            return BILPublicModelText.same(a, b) && BILPublicModelText.sameOptional(nextA, nextB)
        case (.acknowledgementRequired, .acknowledgementRequired), (.gone, .gone):
            return true
        case let (.failed(a), .failed(b)):
            return BILPublicModelText.sameError(a, b)
        default:
            return false
        }
    }
}

/// The input never became a request (paste that does not decode, too large, engine down). C-KEY-5: prints the code,
/// and reflection (`dump`, `Mirror`) shows no child (never the engine message or the arguments).
public struct BILPublicPrepareError: Error, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let error: BILPublicSignError

    public var description: String {
        return "BILPublicPrepareError(" + (error.code ?? error.key) + ")"
    }

    public var debugDescription: String {
        return description
    }

    public var customMirror: Mirror {
        return Mirror(self, children: [:])
    }

    /// Exact (code units; design D-01).
    public static func == (lhs: BILPublicPrepareError, rhs: BILPublicPrepareError) -> Bool {
        return BILPublicModelText.sameError(lhs.error, rhs.error)
    }
}

/// The token of one `observe` subscription: `cancel()` (or releasing the last reference) stops the deliveries.
/// `cancel()` is idempotent and thread-safe; `isCancelled` is true from its first call on. The coordinator's
/// `onCancel` handler runs exactly once and always on the main thread: synchronously when the token is cancelled (or
/// its last reference released, `deinit`) on the main thread, else enqueued on the main queue — so a main-actor
/// coordinator may touch its own state there. Deliveries stay the coordinator's: it checks `isCancelled` before each
/// one (the handler of an off-main cancel runs a little later).
public final class BILPublicObservation {
    private let lock = NSLock()
    private var handler: (() -> Void)?
    private var cancelled = false

    public init(onCancel: @escaping () -> Void) {
        handler = onCancel
    }

    public var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }

    public func cancel() {
        lock.lock()
        let run = handler
        handler = nil
        cancelled = true
        lock.unlock()
        guard let body = run else { return }
        if Thread.isMainThread {
            body()
        } else {
            DispatchQueue.main.async(execute: body)
        }
    }

    deinit {
        cancel()
    }
}

/// The public signing flow as the pages and the scan router use it (implemented by `BILPublicSignCoordinator`, WP19;
/// a DEBUG fixture coordinator in WP20). Request ids are random, never derived from the request; pages pass only the id.
@MainActor public protocol BILPublicSignCoordinating: AnyObject {
    /// Decodes / reviews / resolves `input`; returns the request id (its state says Ready / NotReady / Refused).
    /// Throws `BILPublicPrepareError` when pasted text does not become a request (nothing stored).
    func prepare(_ input: BILPublicInput) async throws -> String
    func state(_ requestId: String) -> BILPublicSignState
    /// Calls `onChange` immediately with the current state, then on every change (main thread) until cancelled.
    func observe(_ requestId: String, _ onChange: @escaping (BILPublicSignState) -> Void) -> BILPublicObservation
    /// "Match again": no-op when answered or ready with partial signatures.
    func resolveAgain(_ requestId: String) async
    /// The inline Prepare of a `.setupRequired` request, then a new match on success.
    func setupThenResolve(_ requestId: String, walletId: String, password: String) async -> BILPublicPrepareResult
    func signTask(_ requestId: String, taskId: String, password: String, riskAcknowledged: Bool) async -> BILPublicTaskOutcome
    /// The verified answer of an answered request, else nil.
    func answer(_ requestId: String) -> BILPublicResponseQr?
    func discard(_ requestId: String)
}
