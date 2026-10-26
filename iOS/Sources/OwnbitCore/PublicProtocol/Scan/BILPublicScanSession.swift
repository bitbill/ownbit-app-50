//  BILPublicScanSession.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Public protocol (cold signer) — one camera scan of a public-protocol request (animated UR / BBQr parts, a static code,
//  or TronLink's own QR), the contract around the engine scan session (C-QR-1 / C-QR-2 / C-QR-4). Port of Android
//  `core/publicsigner/.../scan/PublicScanSession.kt` (R4 §9):
//
//  - one `BILPublicFrameGate` per session in front of the engine; a frame that starts a gate session opens a fresh engine
//    session first (`openScan`, then `scanAdd`);
//  - repeats, blank and non-public texts never reach the engine and change nothing;
//  - one engine call in flight: frames accepted meanwhile wait in a `BILPublicFrameQueue` (32); a frame dropped from it, or
//    whose call was cancelled, goes back to `gate.forget` so the code's next loop delivers it again;
//  - gate rejections become a `BILPublicScanError`: `sessionFull` / `timedOut` / `otherRequest` end the session (and the
//    engine's); stray codes (`wrongDirection`, `unsupported`, `malformed`, `tooLarge`) leave a running session alone;
//    a TokenPocket text is refused with `err.tpUnsupported` and never touches the session;
//  - any engine refusal ends the session: the engine's mixed-session messages read as `otherRequest`, size limits as
//    `tooLarge`, an ended engine session (`SCAN`) as `timedOut`, anything else as `malformed`; a JS / bridge failure or
//    any other error as `engineUnavailable` (C-GEN-16: `busy` is never left set);
//  - TronLink frames pass the same gate but never reach the engine: this session's `BILTronLinkCollector` reassembles
//    them and `BILTronLinkRequestMapper` maps the completed request to the engine-native TRON request;
//  - completion returns the request (`complete`) and resets the session; `expireIfIdle` polls the 150 s limit.
//
//  iOS: `@MainActor` (scanner delivery is on main); Android's `synchronized` sections are the main-actor stretches between
//  suspension points, so the epoch checks after every `await` are the same as Android's. Frames are never logged (engine
//  codes and error type names only).
//

import Foundation

/// Something the user should be told about a scanned code. `endsSession`: the session was reset (the next accepted frame
/// starts a new one); otherwise the running session continues (a stray code in view). `code`: the engine code when the
/// engine refused the frame, or the host refusal's code (log-safe). `error`: the exact refusal of a TronLink request or of
/// any TokenPocket text, when there is one (its own text and arguments win).
public struct BILPublicScanError: Error, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {

    public enum Reason: Equatable {
        case tooLarge, malformed, wrongDirection, unsupported, otherRequest, timedOut, engineUnavailable
    }

    public let reason: Reason
    public let kind: BILPublicQrKind?
    public let endsSession: Bool
    public let code: String?
    public let error: BILPublicSignError?

    public init(reason: Reason, kind: BILPublicQrKind? = nil, endsSession: Bool, code: String? = nil, error: BILPublicSignError? = nil) {
        self.reason = reason
        self.kind = kind
        self.endsSession = endsSession
        self.code = code
        self.error = error
    }

    /// `error.key` when set, else: tooLarge → `err.tooLarge`, malformed → `err.qrMalformed`, wrongDirection →
    /// `err.signatureCode` / `err.pairingCode` by kind, unsupported → `err.unsupportedUr`, otherRequest →
    /// `scan.otherRequest`, timedOut → `err.scanTimeout`, engineUnavailable → `err.engineUnavailable`.
    public var messageKey: String {
        if let e = error { return e.key }
        switch reason {
        case .tooLarge: return "PublicProtocol.err.tooLarge"
        case .malformed: return "PublicProtocol.err.qrMalformed"
        case .wrongDirection: return BILPublicScanErrors.wrongDirection(kind)
        case .unsupported: return "PublicProtocol.err.unsupportedUr"
        case .otherRequest: return "PublicProtocol.scan.otherRequest"
        case .timedOut: return "PublicProtocol.err.scanTimeout"
        case .engineUnavailable: return "PublicProtocol.err.engineUnavailable"
        }
    }

    /// The arguments of `messageKey` (e.g. TronLink's type number).
    public var args: [BILTextArg] {
        return error?.args ?? []
    }

    /// The localized text to show (never the scanned content).
    public var text: String {
        return BILPublicText.format(messageKey, args)
    }

    /// The reason and code only.
    public var description: String {
        return "Public scan: \(reason)" + (code.map { " " + $0 } ?? "")
    }

    public var debugDescription: String {
        return description
    }

    /// No children: `dump` / `Mirror` show no arguments or engine text.
    public var customMirror: Mirror {
        return Mirror(self, children: [:])
    }
}

@MainActor
public final class BILPublicScanSession {

    public init(engine: BILPublicSignerEngining, clock: @escaping () -> Int64 = BILMonotonicClock.millis) {
        self.engine = engine
        let gate = BILPublicFrameGate(clock: clock)
        self.gate = gate
        self.queue = BILPublicFrameQueue(gate: gate)
    }

    /// The latest progress of the running session (`BILScanProgress.empty` when none).
    public var progress: BILScanProgress {
        return current
    }

    /// A session is running (at least one part accepted since the last reset).
    public var isActive: Bool {
        return gate.isActive
    }

    /// Feeds one scanned `frame`. Returns the progress (unchanged for repeats and ignored texts; `complete` with the
    /// request when this frame completed it). Throws `BILPublicScanError` for what the user should be told, and
    /// `CancellationError` when the calling task was cancelled during its engine call (the frame is then forgotten).
    public func add(_ frame: String) async throws -> BILScanProgress {
        let start: BILGateAccepted
        switch gate.accept(frame) {
        case .duplicate:
            return current
        case .rejected(let reason, let kind):
            if let e = rejected(reason, kind) { throw e }
            return current
        case .accepted(let accepted):
            if !accepted.kind.isEngineFrame { return try addOtherWallet(accepted) }
            if busy {
                queue.offer(accepted)
                current = current.with(parts: gate.parts)
                return current
            }
            busy = true
            start = accepted
        }
        return try await drain(start, epoch)
    }

    /// Resets the session when it made no progress for 150 s; `true` → show `err.scanTimeout`.
    public func expireIfIdle() -> Bool {
        if !gate.isExpired() { return false }
        endSession()
        return true
    }

    /// Ends the session and its engine context; the next accepted frame starts a new one.
    public func close() {
        endSession()
    }

    // MARK: - Private

    private let engine: BILPublicSignerEngining
    private let gate: BILPublicFrameGate
    private let queue: BILPublicFrameQueue
    private var handle: BILPublicScanHandle?
    private var tronLink: BILTronLinkCollector?
    private var busy = false
    private var epoch: Int64 = 0
    private var current = BILScanProgress.empty

    private func rejected(_ reason: BILGateReason, _ kind: BILPublicQrKind?) -> BILPublicScanError? {
        let mapped: BILPublicScanError.Reason
        switch reason {
        case .empty, .notPublic: return nil
        case .tooLarge, .sessionFull: mapped = .tooLarge
        case .malformed: mapped = .malformed
        case .wrongDirection: mapped = .wrongDirection
        case .unsupported: mapped = .unsupported
        case .otherRequest: mapped = .otherRequest
        case .timedOut: mapped = .timedOut
        }
        let ends = reason.endsSession || reason == .otherRequest
        if ends { endSession() }
        // A TokenPocket text: Ownbit does not sign TokenPocket's requests (one message, recommending TronLink).
        let error: BILPublicSignError? = (mapped == .unsupported && kind == .tpUnsupported) ? BILPublicSignerErrors.tpUnsupported : nil
        return BILPublicScanError(reason: mapped, kind: kind, endsSession: ends, code: error?.code, error: error)
    }

    /// A TronLink frame the gate accepted: into this session's collector; when the request is complete, mapped to the
    /// engine-native request and the session reset. Never touches the engine.
    private func addOtherWallet(_ accepted: BILGateAccepted) throws -> BILScanProgress {
        do {
            guard accepted.kind.isTronLink else { throw ended(.unsupported) }
            guard let frame = BILTronLinkQrFormat.parse(accepted.frame) else { throw ended(.malformed) }
            let collector: BILTronLinkCollector
            if !accepted.startsSession, let existing = tronLink {
                collector = existing
            } else {
                collector = BILTronLinkCollector()
                tronLink = collector
            }
            switch try collector.add(frame) {
            case .partial(let received, let total):
                current = BILScanProgress(complete: false, progress: total > 0 ? Float(received) / Float(total) : 0,
                                          parts: gate.parts, request: nil)
                return current
            case .complete(let request):
                let mapped = try BILTronLinkRequestMapper.map(request)
                let parts = gate.parts
                endSession()
                return BILScanProgress(complete: true, progress: 1, parts: parts, request: mapped)
            }
        } catch let e as BILOtherWalletRequestError {
            BILPublicLog.code("scan", e.error.code ?? "OTHER_WALLET")
            endSession()
            throw BILPublicScanError(reason: BILPublicScanSession.reason(of: e.kind), kind: accepted.kind, endsSession: true,
                                     code: e.error.code, error: e.error)
        } catch let e as BILPublicScanError {
            throw e
        } catch {
            // C-GEN-16: an unmapped failure of the host path ends the session as malformed, never escapes as is.
            BILPublicLog.failure("scan", error)
            throw ended(.malformed)
        }
    }

    private func drain(_ start: BILGateAccepted, _ myEpoch: Int64) async throws -> BILScanProgress {
        var next = start
        while true {
            let frame = next
            let raw: BILJSONObject
            do {
                guard let h = try await engineHandle(for: frame, myEpoch) else { return current }   // closed meanwhile
                // Kotlin parity (prompt cancellation): a caller cancelled while the engine session opened never sends
                // its frame (Android's suspending `openScan` throws on resume, so `add` is never called) …
                try Task.checkCancellation()
                raw = try await engine.scanAdd(h, frame: frame.frame)
                // … and a cancelled caller never sees the result of its call.
                try Task.checkCancellation()
            } catch let e as CancellationError {
                if epoch == myEpoch {
                    gate.forget(frame.frame)
                    while let waiting = queue.poll() {
                        gate.forget(waiting.frame)
                    }
                    busy = false
                    current = current.with(parts: gate.parts)
                }
                throw e
            } catch let e as BILPublicSignerRefusal {
                BILPublicLog.failure("scan", e)
                throw ended(myEpoch, BILPublicScanSession.engineReason(e), e.code)
            } catch let e as BILPublicSignerFailure {
                BILPublicLog.failure("scan", e)
                throw ended(myEpoch, .engineUnavailable, nil)
            } catch {
                // C-GEN-16: an unmapped failure ends the session (and frees `busy`) instead of leaving every later frame
                // queued behind a call that will never finish.
                BILPublicLog.failure("scan", error)
                throw ended(myEpoch, .engineUnavailable, nil)
            }
            if epoch != myEpoch { return current }   // closed meanwhile: drop
            let progress: BILScanProgress
            do {
                progress = try BILScanProgress.fromEngine(raw, parts: gate.parts)
            } catch {
                BILPublicLog.failure("scan", error)
                throw ended(.malformed)
            }
            if progress.complete {
                // The engine ended its scan session with the request; reset the gate for the next request.
                handle = nil
                endSession()
                return progress
            }
            current = progress
            guard let waiting = queue.poll() else {
                busy = false
                return progress
            }
            next = waiting
        }
    }

    /// The engine session for `frame`: a fresh one when the gate started a session (or none is open); nil when the
    /// session was closed while it opened.
    private func engineHandle(for frame: BILGateAccepted, _ myEpoch: Int64) async throws -> BILPublicScanHandle? {
        if !frame.startsSession, let existing = handle { return existing }
        if let previous = handle {
            handle = nil
            await engine.closeScan(previous)
        }
        let opened = try await engine.openScan()
        if epoch != myEpoch {
            await engine.closeScan(opened)
            return nil
        }
        handle = opened
        return opened
    }

    /// The error of a failed engine step; ends the session unless it was already closed meanwhile.
    private func ended(_ myEpoch: Int64, _ reason: BILPublicScanError.Reason, _ code: String?) -> BILPublicScanError {
        if epoch != myEpoch { return BILPublicScanError(reason: reason, endsSession: true, code: code) }
        endSession()
        return BILPublicScanError(reason: reason, endsSession: true, code: code)
    }

    /// Ends the session now and returns the error to throw.
    private func ended(_ reason: BILPublicScanError.Reason) -> BILPublicScanError {
        endSession()
        return BILPublicScanError(reason: reason, endsSession: true)
    }

    /// Resets everything: engine session closed (C-QR-4), gate reset, queue cleared, in-flight results dropped.
    private func endSession() {
        if let h = handle {
            let engine = self.engine
            Task { await engine.closeScan(h) }   // a stale close of a superseded session is a no-op in the engine
        }
        handle = nil
        tronLink = nil
        queue.clear()
        gate.reset()
        busy = false
        epoch += 1
        current = BILScanProgress.empty
    }

    private static func reason(of kind: BILOtherWalletRequestError.Kind) -> BILPublicScanError.Reason {
        switch kind {
        case .malformed: return .malformed
        case .unsupported: return .unsupported
        case .otherRequest: return .otherRequest
        case .tooLarge: return .tooLarge
        }
    }

    /// Android `engineReason`: only 5 texts on the scan path (D-25); the full `BILPublicSignerErrors.of` table is for
    /// paste / prepare.
    private static func engineReason(_ e: BILPublicSignerRefusal) -> BILPublicScanError.Reason {
        if e.code == "QR_PROTOCOL" {
            if containsExactly(BILPublicSignerErrors.otherRequestMessages, e.engineMessage) { return .otherRequest }
            if containsExactly(BILPublicSignerErrors.tooLargeMessages, e.engineMessage) { return .tooLarge }
            if containsExactly(BILPublicSignerErrors.unsupportedUrMessages, e.engineMessage) { return .unsupported }
        }
        if e.code == BILPublicSignerRefusal.limitCode { return .tooLarge }
        if e.code == BILPublicSignerRefusal.scanCode { return .timedOut }
        return .malformed
    }

    /// Exact (code-unit) membership.
    private static func containsExactly(_ set: Set<String>, _ message: String) -> Bool {
        return set.contains { BILJSONExact.equal($0, message) }
    }
}
