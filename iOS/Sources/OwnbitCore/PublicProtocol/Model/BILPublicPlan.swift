//  BILPublicPlan.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Public protocol (cold signer) — a resolved signing plan (engine `resolveSigningPlan`), its tasks and status. Port of
//  Android core/publicsigner/.../model/PublicPlan.kt (design §3.5, R5 §1.1). A `ready` plan must be complete or it is
//  refused with `BILMalformedEngineResult(what)` (`what` names only the failed part — log-safe). The plan JSON stays in
//  memory only and is passed back to the engine as `raw`, unchanged (the engine re-checks its `planHash`). Pure
//  Foundation.
//

import Foundation

/// Status of a resolved signing plan. Each one has its own page state. Unknown values read as `.invalid` (fail closed).
public enum BILPlanStatus: String, CaseIterable {
    /// Exactly the listed tasks can sign.
    case ready
    /// No local wallet holds the requested key.
    case noMatch
    /// The request names no signer (no path / address / key / fingerprint).
    case missingSigner
    /// More than one local wallet matches (the same phrase twice).
    case ambiguous
    /// A wallet without a public index might match: prepare it (one password) and resolve again.
    case setupRequired
    /// The request is malformed or unsupported.
    case invalid

    public static func fromWire(_ s: String?) -> BILPlanStatus {
        return BILPublicModelText.wire(s, BILPlanStatus.self) ?? .invalid
    }
}

/// One signing task of a ready plan: one local wallet and the keys it signs with. A multi-wallet PSBT has one task per
/// wallet, each signed with its own password.
///
/// - `localWalletId`: the Ownbit wallet id the plan was resolved with (the unlocked wallet must equal it).
/// - `walletKeyId`: the engine's wallet identity (64 hex, lower-cased here); the engine re-checks it against the seed.
/// - `paths` / `publicKeys` / `addresses`: one entry per signing target (same order).
/// - `inputs`: BTC input indexes (0-based) this wallet signs (empty for the other chains).
/// - `signerSlot`: Solana required-signer slot of the key (`targets[0].signerSlot`), else nil.
/// - `raw`: the task exactly as the engine produced it (part of the plan that is passed back unchanged).
public struct BILPublicTask: Equatable {
    public let id: String
    public let localWalletId: String
    public let walletKeyId: String
    public let chain: BILPsChain
    public let paths: [String]
    public let publicKeys: [String]
    public let addresses: [String]
    public let inputs: [Int]
    public let signatureAlgorithm: String
    public let signingBytesDigest: String
    public let signerSlot: Int?
    public let raw: BILJSONObject

    /// Distinct non-empty addresses in engine order (the signing wallet card).
    public var displayAddresses: [String] {
        return BILPublicModelText.distinct(addresses.filter { !$0.isEmpty })
    }

    /// Distinct non-empty paths in engine order.
    public var displayPaths: [String] {
        return BILPublicModelText.distinct(paths.filter { !$0.isEmpty })
    }

    /// The object elements of `raw.targets`, in order (non-object elements skipped; Android `PublicSignPolicy`
    /// `targetFingerprints` reads them so).
    public var targets: [BILJSONObject] {
        return (raw.arr("targets") ?? []).compactMap { $0.objectValue }
    }

    /// `raw.targets[0]` when it is an object, else nil — the element the presenter's fingerprint and `signerSlot`
    /// read (Android `targets.firstOrNull() as? JsonObject`; differs from `targets.first` only for a malformed array).
    public var firstTarget: BILJSONObject? {
        return raw.arr("targets")?.first?.objectValue
    }

    /// Lower-cased string `masterFingerprint`s of the targets (Android `PublicSignPolicy.targetFingerprints`).
    public var targetFingerprints: Set<String> {
        return Set(targets.compactMap { $0.str("masterFingerprint")?.lowercased() })
    }

    /// Reads one engine task; throws `BILMalformedEngineResult` (`task.id`, `task.localWalletId`, `task.walletKeyId`,
    /// `task.chain`, `task.paths`, `task.publicKeys`) in Android's order.
    public static func fromEngine(_ raw: BILJSONObject) throws -> BILPublicTask {
        guard let id = raw.str("id"), !id.isEmpty else { throw BILMalformedEngineResult(what: "task.id") }
        guard let wallet = raw.str("localWalletId"), !wallet.isEmpty else {
            throw BILMalformedEngineResult(what: "task.localWalletId")
        }
        guard let keyId = raw.str("walletKeyId"), BILEngineJSON.isHex(keyId, bytes: 32) else {
            throw BILMalformedEngineResult(what: "task.walletKeyId")
        }
        guard let chain = BILPsChain.fromWire(raw.str("chain")) else { throw BILMalformedEngineResult(what: "task.chain") }
        guard let paths = raw.strings("paths"), !paths.isEmpty else { throw BILMalformedEngineResult(what: "task.paths") }
        guard let keys = raw.strings("publicKeys"), keys.count == paths.count else {
            throw BILMalformedEngineResult(what: "task.publicKeys")
        }
        let signerSlot = raw.arr("targets")?.first?.objectValue?.int("signerSlot")
        return BILPublicTask(
            id: id,
            localWalletId: wallet,
            walletKeyId: keyId.lowercased(),
            chain: chain,
            paths: paths,
            publicKeys: keys,
            addresses: raw.strings("addresses") ?? [],
            inputs: raw.ints("inputs") ?? [],
            signatureAlgorithm: raw.str("signatureAlgorithm") ?? "",
            signingBytesDigest: raw.str("signingBytesDigest") ?? "",
            signerSlot: signerSlot,
            raw: raw)
    }
}

/// A resolved signing plan (engine `resolveSigningPlan`).
///
/// - `message`: the engine's English status message of a non-ready plan (technical details only).
/// - `review`: the engine review (present for ready plans and for most failures), the only source of review rows.
/// - `requestHash` / `planHash` / `signingBytesDigest`: 64 lower-case hex for a ready plan; a non-ready plan carries
///   only the review's request hash (nil when empty).
/// - `protocolProfile`: the request transport (`eth-sign-request`, `crypto-psbt`, …).
/// - `raw`: passed back to the engine unchanged.
public struct BILPublicPlan: Equatable {
    /// Most tasks a plan may carry (Ownbit holds ≤ 50 wallets).
    public static let maxTasks = 64

    public let status: BILPlanStatus
    public let message: String?
    public let chain: BILPsChain?
    public let requestHash: String?
    public let planHash: String?
    public let payloadDigest: String?
    public let signingBytesDigest: String?
    public let protocolProfile: String?
    public let review: BILPublicReview?
    public let tasks: [BILPublicTask]
    public let raw: BILJSONObject

    public var isReady: Bool {
        return status == .ready
    }

    /// The wallets that sign, in task order (one task per wallet).
    public var walletIds: [String] {
        return BILPublicModelText.distinct(tasks.map { $0.localWalletId })
    }

    /// The task with this id (exact), else nil.
    public func task(_ id: String) -> BILPublicTask? {
        return tasks.first { BILPublicModelText.same($0.id, id) }
    }

    /// Reads an engine plan. A `ready` plan must be complete: version 1, 64-hex request and plan hashes, a known chain,
    /// a review of that chain whose request hash is the plan's (ASCII case-insensitive), a 64-hex signing digest,
    /// 1…`maxTasks` well-formed tasks of the plan's chain with unique ids, each signing that digest. A non-ready plan
    /// carries no tasks. Anything else throws `BILMalformedEngineResult` with Android's `what`
    /// (`plan.tasks`, `plan.version`, `plan.requestHash`, `plan.planHash`, `plan.chain`, `plan.review`,
    /// `plan.review.chain`, `plan.signingBytesDigest`, `plan.task`, `task.*`, `plan.task.id`, `plan.task.chain`,
    /// `plan.task.signingBytesDigest`), checked in Android's order.
    public static func fromEngine(_ raw: BILJSONObject) throws -> BILPublicPlan {
        let status = BILPlanStatus.fromWire(raw.str("status"))
        let review = try raw.obj("review").map { try BILPublicReview.fromEngine($0) }
        guard let taskObjects = raw.arr("tasks") else { throw BILMalformedEngineResult(what: "plan.tasks") }
        if status != .ready {
            try BILEngineJSON.ensure(taskObjects.isEmpty, "plan.tasks")
            let reviewHash = review?.requestHash
            return BILPublicPlan(
                status: status,
                message: raw.str("message"),
                chain: review?.chain,
                requestHash: (reviewHash?.isEmpty ?? true) ? nil : reviewHash,
                planHash: nil,
                payloadDigest: nil,
                signingBytesDigest: nil,
                protocolProfile: nil,
                review: review,
                tasks: [],
                raw: raw)
        }
        try BILEngineJSON.ensure(raw.int("version") == 1, "plan.version")
        guard let requestHash = raw.str("requestHash"), BILEngineJSON.isHex(requestHash, bytes: 32) else {
            throw BILMalformedEngineResult(what: "plan.requestHash")
        }
        guard let planHash = raw.str("planHash"), BILEngineJSON.isHex(planHash, bytes: 32) else {
            throw BILMalformedEngineResult(what: "plan.planHash")
        }
        guard let chain = BILPsChain.fromWire(raw.str("chain")) else { throw BILMalformedEngineResult(what: "plan.chain") }
        // What is shown is what is signed: the review describes this plan's request and chain, and the plan names the
        // exact digest every task signs (re-checked natively before the password, and by the engine when signing).
        guard let shownReview = review, BILPublicModelText.sameIgnoringASCIICase(shownReview.requestHash, requestHash) else {
            throw BILMalformedEngineResult(what: "plan.review")
        }
        try BILEngineJSON.ensure(shownReview.chain == chain, "plan.review.chain")
        guard let digest = raw.str("signingBytesDigest"), BILEngineJSON.isHex(digest, bytes: 32) else {
            throw BILMalformedEngineResult(what: "plan.signingBytesDigest")
        }
        try BILEngineJSON.ensure(taskObjects.count >= 1 && taskObjects.count <= maxTasks, "plan.tasks")
        var tasks = [BILPublicTask]()
        tasks.reserveCapacity(taskObjects.count)
        for element in taskObjects {
            guard let object = element.objectValue else { throw BILMalformedEngineResult(what: "plan.task") }
            tasks.append(try BILPublicTask.fromEngine(object))
        }
        try BILEngineJSON.ensure(BILPublicModelText.distinct(tasks.map { $0.id }).count == tasks.count, "plan.task.id")
        try BILEngineJSON.ensure(tasks.allSatisfy { $0.chain == chain }, "plan.task.chain")
        try BILEngineJSON.ensure(tasks.allSatisfy { BILPublicModelText.sameIgnoringASCIICase($0.signingBytesDigest, digest) },
                                 "plan.task.signingBytesDigest")
        return BILPublicPlan(
            status: status,
            message: nil,
            chain: chain,
            requestHash: requestHash.lowercased(),
            planHash: planHash.lowercased(),
            payloadDigest: raw.str("payloadDigest"),
            signingBytesDigest: digest.lowercased(),
            protocolProfile: raw.str("protocolProfile"),
            review: review,
            tasks: tasks,
            raw: raw)
    }
}
