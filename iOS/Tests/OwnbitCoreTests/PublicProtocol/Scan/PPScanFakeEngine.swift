//  PPScanFakeEngine.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Port of the app harness suite `scripts/public-protocol/tests/scan` (FakeEngine.swift) to XCTest.
//
//  FakeEngine.swift — a scripted engine for the scan-session tests (Android PublicScanSessionTest's FakeHandle + mocked
//  bridge): records every scan context and the frames it received, answers with `answer`, optionally holds every
//  `scanAdd` / `openScan` / `closeScan` on a latch, and counts every engine call (TokenPocket / TronLink must make none).
//  `realistic = true` adds WP7's scan-session rules (`BILPublicSignerEngine` openScan / scanAdd / closeScan): one active
//  session; `openScan` ends the previous one; `scanAdd` on a closed / superseded handle → `SCAN` (no frame recorded);
//  a stale `closeScan` is a no-op; a `complete` answer ends the session.
//

import Foundation
import XCTest
@testable import OwnbitCore

extension PPScanSuite {

    /// A gate every waiting call passes once `release()` is called; a waiting task that is cancelled throws
    /// `CancellationError` (like kotlinx `CompletableDeferred.await`) — unless `honoursCancellation` is false (like a
    /// synchronous JS call that runs to its end): then it waits for `release()` regardless.
    final class TestLatch {
        private let lock = NSLock()
        private var isOpen = false
        private var waiters = [Int: CheckedContinuation<Void, Error>]()
        private var nextId = 0
        private let honoursCancellation: Bool

        init(honoursCancellation: Bool = true) {
            self.honoursCancellation = honoursCancellation
        }

        /// nil when the latch is open; else a fresh waiter id.
        private func enter() -> Int? {
            lock.lock()
            defer { lock.unlock() }
            if isOpen { return nil }
            let id = nextId
            nextId += 1
            return id
        }

        func wait() async throws {
            guard let id = enter() else { return }
            if !honoursCancellation {
                try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                    self.lock.lock()
                    if self.isOpen {
                        self.lock.unlock()
                        c.resume()
                    } else {
                        self.waiters[id] = c
                        self.lock.unlock()
                    }
                }
                return
            }
            try await withTaskCancellationHandler(operation: {
                try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                    self.lock.lock()
                    if self.isOpen {
                        self.lock.unlock()
                        c.resume()
                    } else if Task.isCancelled {
                        self.lock.unlock()
                        c.resume(throwing: CancellationError())
                    } else {
                        self.waiters[id] = c
                        self.lock.unlock()
                    }
                }
            }, onCancel: {
                self.lock.lock()
                let c = self.waiters.removeValue(forKey: id)
                self.lock.unlock()
                c?.resume(throwing: CancellationError())
            })
        }

        func release() {
            lock.lock()
            isOpen = true
            let all = Array(waiters.values)
            waiters.removeAll()
            lock.unlock()
            for c in all { c.resume() }
        }
    }

    final class FakeScanEngine: BILPublicSignerEngining {

        final class Context {
            let sessionId: Int64
            var frames = [String]()
            var closed = false
            init(_ id: Int64) { sessionId = id }
        }

        private let lock = NSLock()
        private var contexts = [Context]()
        private var _calls = [String]()
        private var _waiting = 0
        private var _answer: (String) throws -> BILJSONObject = { _ in FakeScanEngine.progress(0.5) }
        private var _latch: TestLatch?
        private var _openLatch: TestLatch?
        private var _closeLatch: TestLatch?
        private var _openWaiting = 0
        private var _closeWaiting = 0
        private var _realistic = false
        private var active: Int64?

        static func progress(_ p: Double) -> BILJSONObject {
            return BILJSONObject([("complete", .bool(false)), ("progress", .number(String(p)))])
        }

        var answer: (String) throws -> BILJSONObject {
            get { lock.lock(); defer { lock.unlock() }; return _answer }
            set { lock.lock(); _answer = newValue; lock.unlock() }
        }

        /// Set → every later `scanAdd` waits for `latch.release()` before it records its frame.
        var latch: TestLatch? {
            get { lock.lock(); defer { lock.unlock() }; return _latch }
            set { lock.lock(); _latch = newValue; lock.unlock() }
        }

        /// Set → every later `openScan` waits for `openLatch.release()` after it created its context.
        var openLatch: TestLatch? {
            get { lock.lock(); defer { lock.unlock() }; return _openLatch }
            set { lock.lock(); _openLatch = newValue; lock.unlock() }
        }

        /// Set → every later `closeScan` waits for `closeLatch.release()` before it closes anything.
        var closeLatch: TestLatch? {
            get { lock.lock(); defer { lock.unlock() }; return _closeLatch }
            set { lock.lock(); _closeLatch = newValue; lock.unlock() }
        }

        /// WP7's scan-session rules (see the file comment).
        var realistic: Bool {
            get { lock.lock(); defer { lock.unlock() }; return _realistic }
            set { lock.lock(); _realistic = newValue; lock.unlock() }
        }

        /// The active session (realistic mode).
        var activeSessionId: Int64? { lock.lock(); defer { lock.unlock() }; return active }

        var handles: [Context] { lock.lock(); defer { lock.unlock() }; return contexts }
        /// Every engine call, by operation name, in order.
        var calls: [String] { lock.lock(); defer { lock.unlock() }; return _calls }
        var waiting: Int { lock.lock(); defer { lock.unlock() }; return _waiting }
        var openWaiting: Int { lock.lock(); defer { lock.unlock() }; return _openWaiting }
        var closeWaiting: Int { lock.lock(); defer { lock.unlock() }; return _closeWaiting }

        /// Runs `body` holding the lock (synchronous, so the async methods never touch the lock themselves).
        private func locked<T>(_ body: () throws -> T) rethrows -> T {
            lock.lock()
            defer { lock.unlock() }
            return try body()
        }

        private func record(_ op: String) {
            locked { _calls.append(op) }
        }

        /// Waits on `latch` (when set), counting the waiter in `counter` meanwhile.
        private func pass(_ latch: TestLatch?, _ counter: ReferenceWritableKeyPath<FakeScanEngine, Int>) async throws {
            guard let l = latch else { return }
            locked { self[keyPath: counter] += 1 }
            defer { locked { self[keyPath: counter] -= 1 } }
            try await l.wait()
        }

        // SCAN
        func openScan() async throws -> BILPublicScanHandle {
            let (c, l): (Context, TestLatch?) = locked {
                _calls.append("openScan")
                if _realistic { endActiveLocked() }
                let c = Context(Int64(contexts.count + 1))
                contexts.append(c)
                if _realistic { active = c.sessionId }
                return (c, _openLatch)
            }
            try await pass(l, \FakeScanEngine._openWaiting)
            return BILPublicScanHandle(sessionId: c.sessionId)
        }

        func scanAdd(_ handle: BILPublicScanHandle, frame: String) async throws -> BILJSONObject {
            record("scanAdd")
            try await pass(latch, \FakeScanEngine._waiting)
            let a: (String) throws -> BILJSONObject = try locked {
                if _realistic && active != handle.sessionId {
                    throw BILPublicSignerRefusal(code: BILPublicSignerRefusal.scanCode, engineMessage: BILPublicSignerRefusal.scanMessage)
                }
                contexts.first { $0.sessionId == handle.sessionId }?.frames.append(frame)
                return _answer
            }
            do {
                let answer = try a(frame)
                if answer["complete"] == .bool(true) { endIfActive(handle) }
                return answer
            } catch {
                endIfActive(handle)
                throw error
            }
        }

        func closeScan(_ handle: BILPublicScanHandle) async {
            record("closeScan")
            try? await pass(closeLatch, \FakeScanEngine._closeWaiting)
            locked {
                if !_realistic || active == handle.sessionId {
                    contexts.first { $0.sessionId == handle.sessionId }?.closed = true
                    if _realistic { active = nil }
                }
            }
        }

        /// Realistic mode: any error and a completed request end the session `handle` if it is still the active one.
        private func endIfActive(_ handle: BILPublicScanHandle) {
            locked {
                if _realistic && active == handle.sessionId { endActiveLocked() }
            }
        }

        private func endActiveLocked() {
            if let id = active { contexts.first { $0.sessionId == id }?.closed = true }
            active = nil
        }

        // Everything else: the scan area never calls it.
        func capabilities() async throws -> BILJSONObject { record("capabilities"); throw BILPublicSignerFailure.engineUnavailable }
        func derivePublicAddresses(publicIndex: BILJSONObject, chain: String, profile: String?, start: Int, count: Int) async throws -> BILJSONObject {
            record("derivePublicAddresses"); throw BILPublicSignerFailure.engineUnavailable
        }
        func createPublicPairing(publicIndex: BILJSONObject, chain: String, profile: String?, outputMode: String?, index: Int) async throws -> BILJSONObject {
            record("createPublicPairing"); throw BILPublicSignerFailure.engineUnavailable
        }
        func releasePairingContext() async { record("releasePairingContext") }
        func derivePublicIndex(seedHex: String, tronScheme: String?, tronAddressCount: Int?) async throws -> BILJSONObject {
            record("derivePublicIndex"); throw BILPublicSignerFailure.engineUnavailable
        }
        func refreshPublicIndex(publicIndex: BILJSONObject, tronScheme: String, tronAddressCount: Int?) async throws -> BILJSONObject {
            record("refreshPublicIndex"); throw BILPublicSignerFailure.engineUnavailable
        }
        func signPlanTask(request: BILJSONObject, plan: BILJSONObject, taskId: String, seedHex: String,
                          riskAcknowledged: Bool, previousResult: BILJSONObject?) async throws -> BILJSONObject {
            record("signPlanTask"); throw BILPublicSignerFailure.engineUnavailable
        }
        func decodePayload(_ payload: String) async throws -> BILJSONObject { record("decodePayload"); throw BILPublicSignerFailure.engineUnavailable }
        func reviewAndResolve(request: BILJSONObject, wallets: [BILJSONObject]) async throws -> BILPublicReviewAndPlan {
            record("reviewAndResolve"); throw BILPublicSignerFailure.engineUnavailable
        }
        func encodeResponse(request: BILJSONObject, result: BILJSONObject) async throws -> BILJSONObject {
            record("encodeResponse"); throw BILPublicSignerFailure.engineUnavailable
        }
        func isAvailable() async -> Bool { record("isAvailable"); return true }
    }

    /// Polls `condition` (on the main actor) for up to `seconds`; the fire-and-forget engine closes need a moment.
    @MainActor
    static func eventually(_ seconds: Double = 2, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition() {
            if Date() > deadline { return false }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        return true
    }

    /// A mutable virtual clock.
    final class TestClock {
        var now: Int64 = 0
        func read() -> Int64 { return now }
    }
}
