//  BILPublicConcurrency.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Public protocol (cold signer) — concurrency primitives (design §1.4): a FIFO async mutex (actor isolation alone is
//  not a lock: actors are reentrant at every `await`), a timeout that does not wait for stuck work (a synchronous
//  JavaScriptCore call cannot be interrupted; a task group would wait for it), a monotonic clock and an off-main
//  runner for pure verification work. Pure Foundation.
//

import Foundation

/// FIFO, **non-reentrant** async mutex: never nest `withLock` / `withLockCancellable` of the same mutex (that
/// deadlocks). Waiters are resumed in arrival order; the lock is handed directly to the next waiter (no barging).
public final class BILAsyncMutex {

    private enum Waiter {
        case plain(CheckedContinuation<Void, Never>)
        case cancellable(UInt64, CheckedContinuation<Void, Error>)

        var cancellableId: UInt64? {
            if case .cancellable(let id, _) = self { return id }
            return nil
        }

        func grant() {
            switch self {
            case .plain(let c): c.resume()
            case .cancellable(_, let c): c.resume()
            }
        }
    }

    private let lock = NSLock()
    private var locked = false
    private var waiters: [Waiter] = []
    private var lastWaiterId: UInt64 = 0

    public init() {}

    /// Runs `body` while holding the lock. **Not cancellable**: a task cancelled while it waits still gets the lock in
    /// its turn and runs `body` (start `body` with `try Task.checkCancellation()` when that matters, or use
    /// `withLockCancellable`).
    public func withLock<T>(_ body: () async throws -> T) async rethrows -> T {
        await acquire()
        defer { release() }
        return try await body()
    }

    /// Like `withLock`, but a cancelled task never starts `body` (kotlinx `Mutex.withLock`, which is cancellable while
    /// waiting; stricter only in that an already-cancelled task does not take a free lock either): cancelled before or
    /// while waiting → it leaves the queue (FIFO order of the others unchanged) and throws `CancellationError`;
    /// cancelled while the lock is being handed to it → it passes the lock on and throws. Once `body` has started,
    /// cancellation is `body`'s own business. Use it for the per-request lock and `BILBitcoinSigningLock` (design §1.4).
    public func withLockCancellable<T>(_ body: () async throws -> T) async throws -> T {
        try await acquireCancellable()
        defer { release() }
        return try await body()
    }

    /// Tasks waiting for the lock (diagnostics / tests).
    public var queuedCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return waiters.count
    }

    private func acquire() async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            lock.lock()
            if !locked {
                locked = true
                lock.unlock()
                c.resume()
            } else {
                waiters.append(.plain(c))
                lock.unlock()
            }
        }
    }

    private func acquireCancellable() async throws {
        let id = nextWaiterId()
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                lock.lock()
                // The cancelled flag is set before any cancellation handler runs, and the handler needs `lock`:
                // either this check sees the cancellation or the handler finds the queued waiter.
                if Task.isCancelled {
                    lock.unlock()
                    c.resume(throwing: CancellationError())
                } else if !locked {
                    locked = true
                    lock.unlock()
                    c.resume()
                } else {
                    waiters.append(.cancellable(id, c))
                    lock.unlock()
                }
            }
        }, onCancel: {
            self.cancelWaiter(id)
        })
        if Task.isCancelled {           // cancelled while the lock was being handed over: pass it on
            release()
            throw CancellationError()
        }
    }

    private func nextWaiterId() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        lastWaiterId &+= 1
        return lastWaiterId
    }

    /// Removes a still-queued cancellable waiter and resumes it with `CancellationError`; does nothing when the waiter
    /// is not queued (not yet enqueued — it then sees `Task.isCancelled` — or already the owner).
    private func cancelWaiter(_ id: UInt64) {
        lock.lock()
        guard let i = waiters.firstIndex(where: { $0.cancellableId == id }) else {
            lock.unlock()
            return
        }
        let waiter = waiters.remove(at: i)
        lock.unlock()
        if case .cancellable(_, let c) = waiter {
            c.resume(throwing: CancellationError())
        }
    }

    private func release() {
        lock.lock()
        if waiters.isEmpty {
            locked = false
            lock.unlock()
            return
        }
        let next = waiters.removeFirst() // the lock stays held: ownership passes to `next`
        lock.unlock()
        next.grant()
    }
}

enum BILPublicTimeout {

    struct Expired: Error, CustomStringConvertible {
        var description: String {
            return "Expired"
        }
    }

    /// Runs `work` in an unstructured task raced against a GCD timer; whichever finishes first resumes the caller
    /// exactly once. On expiry the race is decided at the deadline — even while `work` is still blocked, and without
    /// needing the main actor or a free cooperative-pool thread (the timer fires on a global dispatch queue) — the work
    /// task is cancelled (cooperatively) and its late value is discarded. Cancelling the caller cancels the work and
    /// throws `CancellationError`; an already-cancelled caller never starts the work. Work closures must return values
    /// and never mutate shared state: the caller applies a result only if the race was won.
    static func run<T>(seconds: TimeInterval, _ work: @escaping () async throws -> T) async throws -> T {
        let race = BILPublicTimeoutRace<T>()
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<T, Error>) in
                race.begin(c, seconds: seconds, work: work)
            }
        }, onCancel: {
            race.finish(.failure(CancellationError()))
        })
    }
}

/// The resume-once box of `BILPublicTimeout.run`.
private final class BILPublicTimeoutRace<T> {

    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?
    private var early: Result<T, Error>?
    private var done = false
    private var worker: Task<Void, Never>?
    private var timer: DispatchWorkItem?

    func begin(_ c: CheckedContinuation<T, Error>, seconds: TimeInterval, work: @escaping () async throws -> T) {
        lock.lock()
        if let early = early {          // cancelled before the race started
            self.early = nil
            lock.unlock()
            c.resume(with: early)
            return
        }
        continuation = c
        lock.unlock()

        let delay = max(0, min(seconds, 86_400))    // NaN → 0
        let worker = Task.detached(priority: Task.currentPriority) { [self] in
            do {
                let value = try await work()
                self.finish(.success(value))
            } catch {
                self.finish(.failure(error))
            }
        }
        // Weak: once the caller has resumed nobody needs the race; a cancelled item stays queued until its deadline.
        let timer = DispatchWorkItem { [weak self] in
            self?.finish(.failure(BILPublicTimeout.Expired()))
        }

        lock.lock()
        if done {                       // already decided (instant work / cancellation)
            lock.unlock()
            worker.cancel()
            return
        }
        self.worker = worker
        self.timer = timer
        lock.unlock()
        // A `finish` between the unlock and here cancels `timer` first; a cancelled item never runs.
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delay, execute: timer)
    }

    /// Resumes the caller with `result` unless the race was already decided. Returns `true` if this call decided it.
    @discardableResult
    func finish(_ result: Result<T, Error>) -> Bool {
        lock.lock()
        if done {
            lock.unlock()
            return false
        }
        done = true
        let c = continuation
        continuation = nil
        if c == nil {
            early = result
        }
        let pendingWorker = worker
        let pendingTimer = timer
        worker = nil
        timer = nil
        lock.unlock()
        pendingTimer?.cancel()
        pendingWorker?.cancel()
        c?.resume(with: result)
        return true
    }
}

/// Milliseconds of `DispatchTime` uptime (monotonic; does not count deep sleep).
public enum BILMonotonicClock {
    public static func millis() -> Int64 {
        return Int64(DispatchTime.now().uptimeNanoseconds / 1_000_000)
    }
}

enum BILPublicBackground {
    /// Runs pure, value-typed work off the main thread (`Task.detached(priority: .userInitiated)`).
    static func run<T>(_ work: @escaping () throws -> T) async throws -> T {
        return try await Task.detached(priority: .userInitiated) {
            return try work()
        }.value
    }
}
