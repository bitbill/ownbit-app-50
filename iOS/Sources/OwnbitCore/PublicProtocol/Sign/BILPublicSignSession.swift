//  BILPublicSignSession.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Public protocol (cold signer) — one reviewed, signable request (design §2.1 WP19; port of Android
//  core/publicsigner/.../sign/PublicSignSession.kt): the request exactly as the engine decoded it (passed back to the
//  engine unchanged), the review the plan was checked with, the ready plan, what the native pre-check verified on the
//  original bytes, and the signing progress. An immutable snapshot: the coordinator replaces it after each task.
//  Memory only — never stored, never a navigation argument; nothing in it is secret (public keys, signatures, a PSBT).
//  Pure Foundation. Prints ids and counts only (C-KEY-5).
//

import Foundation

struct BILPublicSignSession {
    let requestId: String
    let request: BILJSONObject
    /// The review the plan was checked with (the plan's review, or the engine's request-only review).
    let review: BILPublicReview
    let plan: BILPublicPlan
    /// The native decode of the bytes the plan commits to (`BILPublicSignVerifier.pre`); nil only while the session is built.
    var verified: BILVerifiedPayload?
    /// The tasks signed so far, in plan order.
    var completedTaskIds: [String]
    /// The latest `signPlanTask` result (the next task's `previousResult`, the `encodeResponse` input).
    var lastResult: BILPublicSignResult?
    /// The verified answer once every task signed (single use, C-GEN-15).
    var response: BILPublicResponseQr?

    init(requestId: String, request: BILJSONObject, review: BILPublicReview, plan: BILPublicPlan,
         verified: BILVerifiedPayload? = nil, completedTaskIds: [String] = [], lastResult: BILPublicSignResult? = nil,
         response: BILPublicResponseQr? = nil) {
        self.requestId = requestId
        self.request = request
        self.review = review
        self.plan = plan
        self.verified = verified
        self.completedTaskIds = completedTaskIds
        self.lastResult = lastResult
        self.response = response
    }

    var chain: BILPsChain? {
        return plan.chain
    }

    /// The request transport (`eth-sign-request`, `crypto-psbt`, `bbqr-psbt`, `psbt-base64`, `tronlink`, …).
    var transportType: String? {
        return request.obj("transport")?.str("type")
    }

    /// The next task to sign (plan order, exact id comparison), nil when every task signed.
    var nextTask: BILPublicTask? {
        return plan.tasks.first { task in !completedTaskIds.contains { BILJSONExact.equal($0, task.id) } }
    }

    var isComplete: Bool {
        return nextTask == nil
    }

    /// The witness-only SegWit v0 inputs of a Bitcoin request (they need the signed-outpoint memory), else [].
    var witnessOnlyInputs: [Int] {
        if case .bitcoinPsbt(_, _, let inputs)? = verified { return inputs }
        return []
    }
}

// C-KEY-5: ids and counts only (Android `PublicSignSession.toString`).
extension BILPublicSignSession: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    var description: String {
        return "BILPublicSignSession(" + requestId + ", " + (plan.chain?.rawValue ?? "-") + ", tasks=" + String(plan.tasks.count)
            + ", done=" + String(completedTaskIds.count) + ", answered=" + String(response != nil) + ")"
    }

    var debugDescription: String {
        return description
    }

    var customMirror: Mirror {
        return Mirror(self, children: [:])
    }
}
