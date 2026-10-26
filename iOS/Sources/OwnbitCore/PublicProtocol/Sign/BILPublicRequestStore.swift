//  BILPublicRequestStore.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Public protocol (cold signer) — the in-memory hand-over of public requests between the scan / paste flow and the
//  review / result pages (design §2.1 WP19; port of Android core/publicsigner/.../sign/PublicRequestStore.kt, R5 §1.2):
//  at most `capacity` (8) entries — the oldest is dropped and its session ends (`.gone`) —, **never** written to disk or
//  passed as anything but its random id. After a restart the id is unknown and the page shows the request as gone.
//
//  An entry holds the request exactly as the engine decoded it, its observable state (the observers of
//  `BILPublicSignCoordinating.observe`), the coordinator's working data (session, wallet snapshot) and its own lock
//  (resolve / setup / sign of one request run one at a time). Main actor only (the coordinator's isolation). Pure
//  Foundation; prints ids only.
//

import Foundation

/// One public request in memory. Ids are random (never derived from the request).
@MainActor final class BILPublicRequestEntry {
    let id: String
    let request: BILJSONObject
    let info: BILPublicRequestInfo
    /// Serializes resolve / setup / sign of this request (FIFO, non-reentrant: never nest it).
    let lock = BILAsyncMutex()

    /// The signable session once the plan is ready (replaced after each task); nil otherwise.
    var session: BILPublicSignSession?
    /// Wallet id → wallet key id (nil without an authentic index) the plan was resolved with.
    var walletSnapshot = BILPublicWalletSnapshot.empty
    /// Removed from the store: every in-flight result for it is dropped (C-GEN-15).
    private(set) var discarded = false

    private(set) var state: BILPublicSignState

    init(id: String, request: BILJSONObject, info: BILPublicRequestInfo) {
        self.id = id
        self.request = request
        self.info = info
        self.state = .resolving(info)
    }

    /// Sets the state and tells every live observer (in subscription order). An observer that changes the state again
    /// while it is told (e.g. discards the request) wins: the older state is not delivered to the observers after it.
    func setState(_ newState: BILPublicSignState) {
        state = newState
        version &+= 1
        let current = version
        for observer in observers {
            guard version == current else { return }
            guard let token = observer.token, !token.isCancelled else { continue }
            observer.handler(newState)
        }
    }

    /// Adds an observer and calls it at once with the current state.
    func addObserver(_ handler: @escaping (BILPublicSignState) -> Void) -> BILPublicObservation {
        nextObserverId &+= 1
        let observerId = nextObserverId
        // The token runs its handler exactly once and always on the main thread (BILPublicObservation): the entry's
        // isolation. The closure is formed here, on the main actor.
        let token = BILPublicObservation { [weak self] in
            self?.removeObserver(observerId)
        }
        observers.append(Observer(id: observerId, token: token, handler: handler))
        handler(state)
        return token
    }

    /// Ends the entry (discard, eviction): no session, state `.gone` (told to the observers), every result for it dropped.
    func retire() {
        guard !discarded else { return }
        discarded = true
        session = nil
        setState(.gone)
    }

    var observerCount: Int {
        return observers.filter { $0.token.map { !$0.isCancelled } ?? false }.count
    }

    // MARK: - Private

    private struct Observer {
        let id: Int
        weak var token: BILPublicObservation?
        let handler: (BILPublicSignState) -> Void
    }

    private var observers: [Observer] = []
    private var nextObserverId = 0
    private var version = 0

    private func removeObserver(_ observerId: Int) {
        observers.removeAll { $0.id == observerId || $0.token == nil }
    }
}

extension BILPublicRequestEntry: CustomStringConvertible {
    nonisolated var description: String {
        return "BILPublicRequestEntry"
    }
}

/// The requests in memory, oldest first (Android `PublicRequestStore`).
@MainActor final class BILPublicRequestStore {

    /// Requests kept; the oldest one beyond it is dropped (its page shows the request as gone).
    static let capacity = 8

    /// A fresh random id (lower-case v4 UUID, Android `UUID.randomUUID().toString()`).
    nonisolated static func newId() -> String {
        return UUID().uuidString.lowercased()
    }

    private var entries: [BILPublicRequestEntry] = []

    init() {}

    /// Stores `entry` (newest) and retires the oldest entries beyond `capacity`; returns its id.
    @discardableResult
    func put(_ entry: BILPublicRequestEntry) -> String {
        entries.removeAll { BILJSONExact.equal($0.id, entry.id) }
        entries.append(entry)
        while entries.count > BILPublicRequestStore.capacity {
            entries.removeFirst().retire()
        }
        return entry.id
    }

    func get(_ id: String) -> BILPublicRequestEntry? {
        return entries.first { BILJSONExact.equal($0.id, id) }
    }

    /// Removes `id` and ends its session.
    @discardableResult
    func remove(_ id: String) -> BILPublicRequestEntry? {
        guard let i = entries.firstIndex(where: { BILJSONExact.equal($0.id, id) }) else { return nil }
        let entry = entries.remove(at: i)
        entry.retire()
        return entry
    }

    var count: Int {
        return entries.count
    }
}
