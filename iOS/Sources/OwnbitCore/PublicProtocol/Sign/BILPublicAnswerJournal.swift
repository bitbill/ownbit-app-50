//  BILPublicAnswerJournal.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Public protocol (cold signer) — the coordinator's hand-off to the host's offline-signing history (answer step ④ of
//  `BILPublicSignCoordinator.answered`, once per verified answer; it never blocks and never changes the outcome).
//
//  In the app the coordinator built the history record itself (`BILPublicSignRecords.of(info:request:ready:response:
//  acknowledged:now:)` → `BILOfflineSignRecord`, handed to `BILOfflineSignJournaling.publicAnswered`). That record and its
//  storage are app persistence and are not part of this package: the host gets the same inputs here and builds its own
//  record. Never put a request JSON, PSBT, frame or signature into a persistent record (the app's record kept only what
//  the review page showed).
//

import Foundation

/// The inputs of the app's offline-signing record of one verified public-protocol answer.
public struct BILPublicAnsweredRequest {
    /// The request's facts (transport, origin, chain) as the coordinator read them at `prepare`.
    public let info: BILPublicRequestInfo
    /// The request exactly as the engine decoded it (memory only — do not store it).
    public let request: BILJSONObject
    /// The reviewed, signable state the answer was made from (review, plan, policy, D43 card).
    public let ready: BILPublicSignReady
    /// The verified answer in the request's own transport.
    public let response: BILPublicResponseQr
    /// The risk checkbox was required and ticked.
    public let acknowledged: Bool
    /// `Dependencies.now()` when the answer was handed out.
    public let answeredAt: Date
}

/// The host's offline-signing history (the app's `BILOfflineSignJournal`).
public protocol BILPublicAnswerJournaling: AnyObject {
    /// Called on the coordinator's actor (main) exactly once per verified answer. Must return quickly; errors are the
    /// journal's own business (the answer is already handed out).
    func publicAnswered(_ answer: BILPublicAnsweredRequest)
}
