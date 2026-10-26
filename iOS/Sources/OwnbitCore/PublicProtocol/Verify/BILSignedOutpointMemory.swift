//  BILSignedOutpointMemory.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Public protocol (cold signer) — the signed-outpoint amount memory (spec S§8.3a, C-OVC, F18; port of Android
//  `PS:verify/SignedOutpointMemory.kt` + `PublicSignerOutpointDao.kt`; design D-30, R5 §4). BIP-143 signatures of SegWit v0
//  inputs commit only to their own input's amount, so two requests over the same coins that each understate a different
//  amount could be combined (CVE-2020-14199). This memory remembers, per outpoint, a tag of the amount this device signed
//  for it; a later request claiming another amount for a remembered outpoint is a hard refusal (`err.prevoutConflict`).
//  Shared by both protocols (the public coordinator and the Ownbit-protocol `bb_sign:` BTC transfer, D-31); Bitcoin signing
//  of both runs one request at a time under `BILBitcoinSigningLock.shared` (check → sign → record).
//
//  Storage (D-30): `Application Support/PublicSigner/signed_outpoints.json`, `{"version":1,"rows":[{"k":…,"t":…,"s":…}]}`,
//  written atomically with `.completeFileProtection`, excluded from backup. Never in the clear: key = 16 bytes of
//  SHA-256("ownbit/ovc/v1/key" ‖ txid ‖ u32le(vout)), tag = 16 bytes of SHA-256("ownbit/ovc/v1/amt" ‖ key ‖ u64le(sats)).
//  At most 256 rows, evicted by a monotonic **order counter** (never a clock: an offline phone's clock may go back); one call
//  that records more than 256 distinct outpoints keeps all of its own rows (the next call trims back to 256).
//  - file absent → available and empty;
//  - a read error (data protection, I/O) → **transient**: unavailable for this access only, read again on the next one;
//  - a file that reads but does not decode → **corrupt**: unavailable for the rest of the process, `conflicts` / `record`
//    throw `Unavailable`, and the file is **never** overwritten or moved automatically (only DEBUG `resetForDebug()` moves it
//    aside; recovery is a product decision).
//  Never logs an outpoint, an amount, a key or a tag. Pure Foundation + CryptoKit (macOS-harness testable).
//

import Foundation
import CryptoKit

public final class BILSignedOutpointMemory {

    /// Outpoints remembered (Coldcard keeps 128).
    public static let capacity = 256

    /// The app's memory: `Application Support/PublicSigner/signed_outpoints.json`.
    public static let shared = BILSignedOutpointMemory(fileURL: BILSignedOutpointMemory.defaultFileURL)

    /// `Application Support/PublicSigner/signed_outpoints.json` (D-30).
    public static var defaultFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base.appendingPathComponent("PublicSigner", isDirectory: true).appendingPathComponent("signed_outpoints.json")
    }

    /// One input as a request states it: the outpoint ([txid] in the transaction's byte order — a PSBT's, or the reversed
    /// hex of an explorer transaction id —, [vout]) and the amount it claims ([sats]). A txid that is not 32 bytes is an
    /// unreadable claim: a conflict in `conflicts`, a failure in `record`.
    public struct Claim: Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
        public let txid: [UInt8]
        public let vout: UInt32
        public let sats: UInt64

        public init(txid: [UInt8], vout: UInt32, sats: UInt64) {
            self.txid = txid
            self.vout = vout
            self.sats = sats
        }

        /// Prints / dumps nothing of the outpoint or the amount (C-LOG-1).
        public var description: String { return "Claim" }
        public var debugDescription: String { return description }
        public var customMirror: Mirror { return Mirror(self, children: [], displayStyle: .struct) }
    }

    /// The memory cannot be read (transient: this access only; corrupt: the rest of the process) or written.
    public struct Unavailable: Error, CustomStringConvertible {
        public var description: String { return "Unavailable" }
    }

    public let fileURL: URL

    private struct Row {
        let tag: String
        let seq: Int64
    }

    private enum State {
        case notLoaded
        case loaded([String: Row])
        case corrupt
    }

    private let queue = DispatchQueue(label: "bil.pub.signedOutpoints")
    /// Only touched on `queue`.
    private var state = State.notLoaded

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    // MARK: - Key / tag (exact, R5 §4.1)

    private static let keyDomain = Array("ownbit/ovc/v1/key".utf8)
    private static let tagDomain = Array("ownbit/ovc/v1/amt".utf8)

    /// The 16-byte key of outpoint (`txid` as stored in the transaction, `vout`).
    public static func key(txid: [UInt8], vout: UInt32) -> [UInt8] {
        return sha256Prefix16(keyDomain + txid + le(UInt64(vout), bytes: 4))
    }

    /// The 16-byte tag of `sats` for `key`.
    public static func tag(key: [UInt8], sats: UInt64) -> [UInt8] {
        return sha256Prefix16(tagDomain + key + le(sats, bytes: 8))
    }

    // MARK: - API

    /// Absent file = available (and empty); a transient read error = `false` for this access only (read again next
    /// time); a corrupt file = `false` for the rest of the process (D-30).
    public var isAvailable: Bool {
        return queue.sync { loadOnQueue() != nil }
    }

    /// Indexes of `claims` (ascending) whose amount differs from the amount this device already signed for the same
    /// outpoint; a `nil` (unreadable) claim is a conflict. Throws `Unavailable` while the memory cannot be read.
    public func conflicts(_ claims: [Claim?]) throws -> [Int] {
        return try queue.sync { () throws -> [Int] in
            guard let rows = loadOnQueue() else { throw Unavailable() }
            var out = [Int]()
            for (i, claim) in claims.enumerated() {
                guard let c = claim, BILSignedOutpointMemory.isReadable(c) else {
                    out.append(i)
                    continue
                }
                let entry = BILSignedOutpointMemory.entry(c)
                if let stored = rows[entry.key], stored.tag != entry.tag {
                    out.append(i)
                }
            }
            return out
        }
    }

    /// Remembers the outpoint amounts of `claims` (the inputs this device signed), in order: each gets the next order
    /// stamp (a remembered outpoint is refreshed: newest again, with the new tag); then the newest
    /// max(256, distinct outpoints of this call) rows are kept. Nothing to record → returns without touching the file.
    /// Throws `Unavailable` while the memory cannot be read (a corrupt file is never overwritten), for an unreadable
    /// claim, and when the file cannot be written (the memory is then unchanged).
    public func record(_ claims: [Claim]) throws {
        guard !claims.isEmpty else { return }
        guard claims.allSatisfy(BILSignedOutpointMemory.isReadable) else { throw Unavailable() }
        try queue.sync { () throws -> Void in
            guard var rows = loadOnQueue() else { throw Unavailable() }
            let base = rows.values.map { $0.seq }.max() ?? 0
            var distinct = Set<String>()
            for (i, c) in claims.enumerated() {
                let entry = BILSignedOutpointMemory.entry(c)
                // Never trap, never write a stamp the reader would refuse (the file and the memory stay unchanged).
                let (seq, overflow) = base.addingReportingOverflow(1 + Int64(i))
                guard !overflow, seq <= BILSignedOutpointMemory.maxStamp else {
                    BILPublicLog.code("outpoints", "MEMORY_STAMP_LIMIT")
                    throw Unavailable()
                }
                rows[entry.key] = Row(tag: entry.tag, seq: seq)
                distinct.insert(entry.key)
            }
            let keep = max(BILSignedOutpointMemory.capacity, distinct.count)
            if rows.count > keep {
                let ordered = rows.sorted { a, b in
                    a.value.seq != b.value.seq ? a.value.seq > b.value.seq : a.key > b.key
                }
                rows = Dictionary(uniqueKeysWithValues: ordered.prefix(keep).map { ($0.key, $0.value) })
            }
            try writeOnQueue(rows)
            state = .loaded(rows)
        }
    }

    #if DEBUG
    /// DEBUG only: moves a corrupt file aside (`signed_outpoints.corrupt-<n>.json` next to it) so the memory starts
    /// empty again; does nothing for a readable or absent file.
    func resetForDebug() {
        queue.sync {
            if case .loaded = state { return }
            guard case .corrupt = readFileOnQueue() else { return }
            let dir = fileURL.deletingLastPathComponent()
            let stem = fileURL.deletingPathExtension().lastPathComponent
            var n = 1
            var target = dir.appendingPathComponent("\(stem).corrupt-\(n).json")
            while FileManager.default.fileExists(atPath: target.path) {
                n += 1
                target = dir.appendingPathComponent("\(stem).corrupt-\(n).json")
            }
            do {
                try FileManager.default.moveItem(at: fileURL, to: target)
                state = .notLoaded
            } catch {
                BILPublicLog.failure("outpoints", error)
            }
        }
    }

    /// DEBUG only (pubrecords): rows remembered, nil while unavailable. A count, never a row.
    var debugRowCount: Int? {
        return queue.sync { loadOnQueue()?.count }
    }
    #endif

    // MARK: - Private (queue)

    private enum ReadResult {
        case absent
        case rows([String: Row])
        case transient
        case corrupt
    }

    /// The rows, or nil while unavailable (transient → retried on the next access; corrupt → sticky).
    private func loadOnQueue() -> [String: Row]? {
        switch state {
        case .loaded(let rows):
            return rows
        case .corrupt:
            return nil
        case .notLoaded:
            switch readFileOnQueue() {
            case .absent:
                state = .loaded([:])
                return [:]
            case .rows(let rows):
                state = .loaded(rows)
                return rows
            case .transient:
                BILPublicLog.code("outpoints", "MEMORY_READ_TRANSIENT")
                return nil
            case .corrupt:
                BILPublicLog.code("outpoints", "MEMORY_CORRUPT")
                state = .corrupt
                return nil
            }
        }
    }

    private func readFileOnQueue() -> ReadResult {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else { return .absent }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            let ns = error as NSError
            if ns.domain == NSCocoaErrorDomain && ns.code == NSFileReadNoSuchFileError { return .absent }
            if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError,
               underlying.domain == NSPOSIXErrorDomain && underlying.code == Int(ENOENT) {
                return .absent
            }
            return .transient
        }
        guard let rows = BILSignedOutpointMemory.decode([UInt8](data)) else { return .corrupt }
        return .rows(rows)
    }

    private func writeOnQueue(_ rows: [String: Row]) throws {
        let fm = FileManager.default
        var dir = fileURL.deletingLastPathComponent()
        do {
            if !fm.fileExists(atPath: dir.path) {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
                var values = URLResourceValues()
                values.isExcludedFromBackup = true
                try? dir.setResourceValues(values)
            }
            let text = BILSignedOutpointMemory.encode(rows)
            try Data(text.utf8).write(to: fileURL, options: BILSignedOutpointMemory.writeOptions)
            var file = fileURL
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? file.setResourceValues(values)
        } catch {
            BILPublicLog.failure("outpoints", error)
            throw Unavailable()
        }
    }

    // MARK: - Private (pure)

    /// Atomic + complete data protection on iOS (D-30). macOS (the standalone test harness only) has no complete-protection
    /// class for a command-line process (the write fails with EPERM), so it writes atomically without it.
    private static var writeOptions: Data.WritingOptions {
        #if os(iOS)
        return [.atomic, .completeFileProtection]
        #else
        return [.atomic]
        #endif
    }

    private static func isReadable(_ c: Claim) -> Bool {
        return c.txid.count == 32
    }

    private static func entry(_ c: Claim) -> (key: String, tag: String) {
        let k = key(txid: c.txid, vout: c.vout)
        return (BILPublicHex.encode(k), BILPublicHex.encode(tag(key: k, sats: c.sats)))
    }

    private static func sha256Prefix16(_ bytes: [UInt8]) -> [UInt8] {
        return Array(Array(SHA256.hash(data: Data(bytes))).prefix(16))
    }

    private static func le(_ value: UInt64, bytes: Int) -> [UInt8] {
        return (0..<bytes).map { UInt8(truncatingIfNeeded: value >> (8 * UInt64($0))) }
    }

    /// `{"version":1,"rows":[…]}`, rows in recording order (ascending stamps).
    private static func encode(_ rows: [String: Row]) -> String {
        let ordered = rows.sorted { a, b in a.value.seq != b.value.seq ? a.value.seq < b.value.seq : a.key < b.key }
        var list = [BILJSONValue]()
        list.reserveCapacity(ordered.count)
        for (k, row) in ordered {
            list.append(.object(BILJSONObject([("k", .string(k)), ("t", .string(row.tag)), ("s", .int(row.seq))])))
        }
        return BILStrictJSON.serialize(.object(BILJSONObject([("version", .int(1)), ("rows", .array(list))])))
    }

    /// Largest order stamp a file may hold. The counter grows by the inputs signed, so a real file never gets near it; a
    /// bigger stamp is a damaged or edited file (corrupt, D-30), and `record` can never overflow the counter.
    private static let maxStamp = Int64.max / 2

    /// Strict reading (fail closed): version 1, every row `k` / `t` 32 lower-case hex, `s` an integer in 1…`maxStamp`,
    /// no key twice.
    private static func decode(_ bytes: [UInt8]) -> [String: Row]? {
        guard let root = BILStrictJSON.parse(utf8: bytes)?.objectValue,
              root["version"]?.numberLiteral == "1",
              let list = root["rows"]?.arrayValue else { return nil }
        var rows = [String: Row]()
        for item in list {
            guard let o = item.objectValue, o.count == 3,
                  let k = o["k"]?.stringValue, isLowerHex32(k),
                  let t = o["t"]?.stringValue, isLowerHex32(t),
                  let literal = o["s"]?.numberLiteral, let seq = BILEngineJSON.integerValue(literal), seq > 0, seq <= maxStamp,
                  rows[k] == nil else { return nil }
            rows[k] = Row(tag: t, seq: seq)
        }
        return rows
    }

    private static func isLowerHex32(_ s: String) -> Bool {
        let u = Array(s.utf8)
        return u.count == 32 && u.allSatisfy { ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x61 && $0 <= 0x66) }
    }
}

/// Bitcoin signing of both protocols, one request at a time (Android `SignedOutpointMemory.signing`): the public
/// coordinator holds it around check → sign → answered/record of each BTC task, the internal `bb_sign:` BTC transfer
/// around conflicts → build → record. FIFO, non-reentrant; use `withLockCancellable` (a cancelled waiter never runs).
public enum BILBitcoinSigningLock {
    public static let shared = BILAsyncMutex()
}

// MARK: - Internal bb_sign: BTC path (D-31)

extension BILBitcoinSigningLock {

    /// Why the internal BTC path gave no answer (texts: `BILUtxoSignDatas+Check.swift`).
    public enum Refusal: Equatable {
        /// An input claims another amount than this device signed for it (1-based input number) — nothing was built.
        case conflict(inputNumber: Int)
        /// The memory could not be read — nothing was built.
        case memoryUnavailable
        /// Built, but the inputs could not be remembered — the answer is discarded (no answer leaves the phone).
        case recordFailed
        /// The builder did not call back in time — a late result is discarded.
        case timedOut
    }

    public enum InternalOutcome<Answer, Failure: Error> {
        /// Built and remembered: hand the answer out.
        case answered(Answer)
        case refused(Refusal)
        /// The builder's own failure (shown as before).
        case buildFailed(Failure)
        /// The waiting task was cancelled (nothing ran).
        case cancelled
    }

    /// Safety bound on one internal BTC build (the lock is released if the JS builder never calls back).
    public static let internalBuildTimeout: TimeInterval = 120

    /// D-31, inside `lock` (after the password): `conflicts(claims)` → a conflict refuses with the first conflicting input
    /// (no build); `Unavailable` refuses (no build) → `build` (called on the main actor, at most once; its first callback
    /// wins) → `record(claims)`; a record failure discards the answer. `claims` = every canonical input (count checked
    /// by the caller, `BILUtxoSignDatas.claims`).
    @MainActor
    public static func signInternal<Answer, Failure: Error>(
        claims: [BILSignedOutpointMemory.Claim], memory: BILSignedOutpointMemory, lock: BILAsyncMutex = shared,
        timeout: TimeInterval = internalBuildTimeout,
        build: @escaping (_ done: @escaping (Result<Answer, Failure>) -> Void) -> Void
    ) async -> InternalOutcome<Answer, Failure> {
        do {
            return try await lock.withLockCancellable { () async -> InternalOutcome<Answer, Failure> in
                let conflicts: [Int]
                do {
                    conflicts = try memory.conflicts(claims.map { Optional($0) })
                } catch {
                    return .refused(.memoryUnavailable)
                }
                if let first = conflicts.min() {
                    BILPublicLog.code("sign", "PREVOUT_CONFLICT")
                    return .refused(.conflict(inputNumber: first + 1))
                }
                let built: Result<Answer, Failure>? = await withCheckedContinuation { (c: CheckedContinuation<Result<Answer, Failure>?, Never>) in
                    let race = BILInternalBuildRace<Result<Answer, Failure>>(c)
                    DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + timeout) { race.finish(nil) }
                    build { result in race.finish(result) }
                }
                guard let result = built else {
                    BILPublicLog.code("sign", "INTERNAL_BUILD_TIMEOUT")
                    return .refused(.timedOut)
                }
                switch result {
                case .failure(let error):
                    return .buildFailed(error)
                case .success(let answer):
                    do {
                        try memory.record(claims)
                    } catch {
                        BILPublicLog.code("sign", "OUTPOINT_MEMORY")
                        return .refused(.recordFailed)
                    }
                    return .answered(answer)
                }
            }
        } catch {
            return .cancelled
        }
    }
}

/// First of (builder callback, timer) resumes the continuation; the other is ignored (a late result is discarded).
private final class BILInternalBuildRace<T>: @unchecked Sendable {   // every access under `lock`
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T?, Never>?

    init(_ continuation: CheckedContinuation<T?, Never>) {
        self.continuation = continuation
    }

    func finish(_ value: T?) {
        lock.lock()
        let c = continuation
        continuation = nil
        lock.unlock()
        c?.resume(returning: value)
    }
}
