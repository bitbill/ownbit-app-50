//  BILPublicFrameGate.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Public protocol (cold signer) — the gate in front of one public scan session (C-QR-1 / C-QR-2): every camera / album
//  text goes through `accept` before the engine sees it, so stray, wrong-direction and malformed codes never end the
//  engine session and one stray QR never wipes the progress of an animated code. Port of Android
//  `core/scanner/.../publicqr/PublicFrameGate.kt` (gate + `PublicFrameQueue`, R4 §7), checks in exactly Android's order.
//
//  Not thread-safe: one gate per scan session, used from one isolation domain. Pure Foundation + CryptoKit (SHA-256 of
//  the de-duplication text; the scanned text itself is never retained). Nothing is logged; descriptions print counts.
//

import Foundation
import CryptoKit

/// Why a text never reaches the engine (suggested texts in brackets).
public enum BILGateReason: Equatable {
    /// Blank text — ignore.
    case empty
    /// More than 16,384 raw UTF-8 bytes, more than 4,300 chars after trimming, or a code announcing too many parts
    /// [`err.tooLarge`].
    case tooLarge
    /// Not a public-protocol code (a stray QR, an address, a `bb_*:` code): ignore during a session.
    case notPublic
    /// A pairing export [`err.pairingCode`] or a signature answer [`err.signatureCode`].
    case wrongDirection
    /// Another UR / BBQr type [`err.unsupportedUr`]; any TokenPocket text [`err.tpUnsupported`].
    case unsupported
    /// Structure or alphabet of its kind violated [`err.qrMalformed`].
    case malformed
    /// A signing-request frame of another code than the running session; the gate **keeps** its session
    /// [`scan.otherRequest`].
    case otherRequest
    /// The session would exceed 2,048 distinct frames or 1 MiB of characters; the gate has reset [`err.tooLarge`].
    case sessionFull
    /// No new frame for 150 s; the gate has reset [`err.scanTimeout`].
    case timedOut

    /// The gate dropped its session: end the engine session as well.
    public var endsSession: Bool {
        return self == .sessionFull || self == .timedOut
    }
}

/// A frame to send to the engine scan session (`scanAdd`) exactly as given (`frame` = the trimmed text; a PSBT text also
/// without its whitespace). `startsSession`: the first frame of a new gate session (open a fresh engine session first).
/// `parts`: distinct frames accepted in this session, this one included.
struct BILGateAccepted: Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    let frame: String
    let kind: BILPublicQrKind
    let startsSession: Bool
    let parts: Int

    /// Never prints the frame.
    var description: String {
        return "BILGateAccepted(kind: \(kind), startsSession: \(startsSession), parts: \(parts), chars: \(frame.utf16.count))"
    }

    var debugDescription: String {
        return description
    }

    var customMirror: Mirror {
        return Mirror(self, children: [:])
    }

    /// Exact (code-unit) frame comparison.
    static func == (lhs: BILGateAccepted, rhs: BILGateAccepted) -> Bool {
        return BILJSONExact.equal(lhs.frame, rhs.frame) && lhs.kind == rhs.kind && lhs.startsSession == rhs.startsSession
            && lhs.parts == rhs.parts
    }
}

/// Outcome of `BILPublicFrameGate.accept` for one scanned text.
enum BILGateResult: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case accepted(BILGateAccepted)
    /// Already accepted in this session (animated codes loop): nothing to send.
    case duplicate
    /// Not for the engine; `kind` = the code's public kind when it is one.
    case rejected(BILGateReason, BILPublicQrKind?)

    var description: String {
        switch self {
        case .accepted(let a): return "accepted(" + a.description + ")"
        case .duplicate: return "duplicate"
        case .rejected(let reason, let kind): return "rejected(\(reason), \(kind.map { "\($0)" } ?? "nil"))"
        }
    }

    var debugDescription: String {
        return description
    }
}

final class BILPublicFrameGate: CustomStringConvertible {

    /// Raw camera text bound before anything else (BitSigner iOS `QRScanFrameGate.maximumBytes`).
    static let maxRawUTF8Bytes = 16_384
    /// UTF-16 units of one trimmed frame (engine `QR_LIMITS.frameChars`).
    static let maxFrameChars = 4_300
    /// Distinct frames of one session and the largest UR part count (engine `QR_LIMITS.frames`).
    static let maxFrames = 2_048
    /// Parts of one BBQr (two base-36 digits).
    static let maxBBQRFrames = 1_295
    /// UTF-16 units kept by one session (engine `QR_LIMITS.retainedChars`, 1 MiB).
    static let maxRetainedChars = 1_048_576
    /// Parts of one split TronLink request (`2 ≤ tN ≤ 64`).
    static let maxTronLinkParts = 64
    /// No-progress limit of a session: 2.5 min (Android parity; product decision).
    static let noProgressTimeoutMillis: Int64 = 150_000

    /// `clock`: monotonic milliseconds (does not count deep sleep, like Android's `System.nanoTime()`).
    init(clock: @escaping () -> Int64 = BILMonotonicClock.millis) {
        self.clock = clock
    }

    /// Distinct frames accepted in the running session (0 when none).
    var parts: Int {
        return seen.count
    }

    /// UTF-16 units of the accepted frames of the running session.
    var retainedChars: Int {
        return retained
    }

    /// `true` while a session runs (at least one frame accepted since the last reset).
    var isActive: Bool {
        return session != nil
    }

    /// The transport kind of the running session (the kind of its first frame), or nil.
    var sessionKind: BILPublicQrKind? {
        return session?.kind
    }

    /// Decides what to do with one scanned text (R4 §7 order: expiry, raw bytes, trim / empty, frame length, kind, wrong
    /// direction, unsupported, structure, other session, duplicate, second static code, session limits, accept).
    func accept(_ frame: String) -> BILGateResult {
        if session != nil && isExpired() {
            reset()
            return .rejected(.timedOut, nil)
        }
        if BILPublicFrameGate.exceedsUTF8Bytes(frame, BILPublicFrameGate.maxRawUTF8Bytes) { return .rejected(.tooLarge, nil) }
        let trimmed = BILKotlinText.trim(frame)
        if trimmed.isEmpty { return .rejected(.empty, nil) }
        if trimmed.utf16.count > BILPublicFrameGate.maxFrameChars { return .rejected(.tooLarge, nil) }

        guard let kind = BILPublicQrFormat.classify(trimmed) else { return .rejected(.notPublic, nil) }
        if kind.isWrongDirection { return .rejected(.wrongDirection, kind) }
        if !kind.isSigningRequest { return .rejected(.unsupported, kind) }

        let key: ParsedFrame
        switch parse(trimmed, kind) {
        case .bad(let reason): return .rejected(reason, kind)
        case .ok(let parsed): key = parsed
        }

        let running = session
        if let running = running, running != key.session { return .rejected(.otherRequest, kind) }
        let digest = BILPublicFrameGate.digest(key.dedupText)
        if seen.contains(digest) { return .duplicate }
        if let running = running, running.singleFrame { return .rejected(.otherRequest, kind) }

        let length = key.frame.utf16.count
        if seen.count >= BILPublicFrameGate.maxFrames || retained + length > BILPublicFrameGate.maxRetainedChars {
            reset()
            return .rejected(.sessionFull, kind)
        }
        let starts = running == nil
        if starts { session = key.session }
        seen.insert(digest)
        retained += length
        lastProgressAt = clock()
        return .accepted(BILGateAccepted(frame: key.frame, kind: kind, startsSession: starts, parts: seen.count))
    }

    /// Undoes an accepted frame that never reached the engine (dropped from a `BILPublicFrameQueue`, or its call was
    /// cancelled), so the next loop of the animated code can deliver it again. Unknown frames / other sessions are ignored.
    func forget(_ frame: String) {
        let trimmed = BILKotlinText.trim(frame)
        guard let kind = BILPublicQrFormat.classify(trimmed), case .ok(let parsed) = parse(trimmed, kind) else { return }
        guard let running = session, running == parsed.session else { return }
        if seen.remove(BILPublicFrameGate.digest(parsed.dedupText)) != nil {
            retained -= parsed.frame.utf16.count
            if seen.isEmpty { reset() }
        }
    }

    /// Ends the session: the next accepted frame starts a new one.
    func reset() {
        session = nil
        seen.removeAll()
        retained = 0
        lastProgressAt = 0
    }

    /// `true` when a session runs and no frame was accepted for more than 150 s (strictly greater).
    func isExpired() -> Bool {
        return session != nil && clock() - lastProgressAt > BILPublicFrameGate.noProgressTimeoutMillis
    }

    /// Counts only.
    var description: String {
        return "BILPublicFrameGate(parts: \(seen.count), active: \(session != nil))"
    }

    /// Android `exceedsUtf8Bytes`: `true` when `text` is longer than `limit` UTF-8 bytes, counting on UTF-16 units (a
    /// surrogate pair = 4 bytes, a lone surrogate = 3), stopping at the limit.
    static func exceedsUTF8Bytes(_ text: String, _ limit: Int) -> Bool {
        let u = text.utf16
        let n = u.count
        if n > limit { return true }          // ≥ 1 byte per unit
        if n * 3 <= limit { return false }    // ≤ 3 bytes per unit
        var bytes = 0
        var pendingHigh = false
        for c in u {
            if pendingHigh {
                pendingHigh = false
                if c >= 0xDC00 && c <= 0xDFFF {
                    bytes += 1                 // the pair's 4 bytes: 3 counted for the high unit + 1
                    if bytes > limit { return true }
                    continue
                }
            }
            if c < 0x80 {
                bytes += 1
            } else if c < 0x800 {
                bytes += 2
            } else {
                bytes += 3
                if c >= 0xD800 && c <= 0xDBFF { pendingHigh = true }
            }
            if bytes > limit { return true }
        }
        return false
    }

    // MARK: - Private

    private let clock: () -> Int64
    private var session: SessionKey?
    private var seen = Set<Data>()
    private var retained = 0
    private var lastProgressAt: Int64 = 0

    /// What identifies "the same code" across its frames.
    private struct SessionKey: Equatable {
        let kind: BILPublicQrKind
        let urType: String?
        let count: Int64
        let bbqrHeader: String?

        /// A session complete with its first frame (single-part UR, PSBT text, one-part BBQr, single TronLink request).
        var singleFrame: Bool {
            return count == 1 && kind != .urPart
        }

        static func == (lhs: SessionKey, rhs: SessionKey) -> Bool {
            return lhs.kind == rhs.kind && BILScanText.same(lhs.urType, rhs.urType) && lhs.count == rhs.count
                && BILScanText.same(lhs.bbqrHeader, rhs.bbqrHeader)
        }
    }

    private struct ParsedFrame {
        let frame: String
        let dedupText: String
        let session: SessionKey
    }

    private enum Parsed {
        case ok(ParsedFrame)
        case bad(BILGateReason)
    }

    private func parse(_ trimmed: String, _ kind: BILPublicQrKind) -> Parsed {
        switch kind {
        case .urSignRequest, .urPart: return parseUr(trimmed)
        case .bbqrPart: return parseBbqr(trimmed)
        case .psbtBase64: return parsePsbtText(trimmed, kind, BILPublicFrameGate.isBase64Char)
        case .psbtHex: return parsePsbtText(trimmed, kind, BILPublicFrameGate.isHexChar)
        case .tronLinkRequest, .tronLinkPart: return parseTronLink(trimmed)
        case .pairingUr, .signatureUr, .unsupportedUr, .tpUnsupported: return .bad(.unsupported)
        }
    }

    /// A single TronLink request is a session of one frame; a part fixes the session's part count (≤ 64). A different
    /// text for an accepted part number passes the gate (another digest); the collector refuses it as another request.
    private func parseTronLink(_ trimmed: String) -> Parsed {
        guard let frame = BILTronLinkQrFormat.parse(trimmed) else { return .bad(.malformed) }
        guard frame.isPart, let count = frame.tN else {
            return .ok(ParsedFrame(frame: trimmed, dedupText: trimmed,
                                   session: SessionKey(kind: .tronLinkRequest, urType: nil, count: 1, bbqrHeader: nil)))
        }
        if count > BILPublicFrameGate.maxTronLinkParts { return .bad(.tooLarge) }
        return .ok(ParsedFrame(frame: trimmed, dedupText: trimmed,
                               session: SessionKey(kind: .tronLinkPart, urType: nil, count: Int64(count), bbqrHeader: nil)))
    }

    /// `^[Uu][Rr]:([A-Za-z0-9-]{1,64})/(?:([0-9]{1,10})-([0-9]{1,10})/)?([A-Za-z]+)$` (whole string).
    private func parseUr(_ frame: String) -> Parsed {
        guard let m = BILKotlinText.wholeMatch(BILPublicFrameGate.urRegex, frame) else { return .bad(.malformed) }
        let ns = frame as NSString
        let type = ns.substring(with: m.range(at: 1)).lowercased()
        let key: SessionKey
        if m.range(at: 2).location == NSNotFound {
            key = SessionKey(kind: .urSignRequest, urType: type, count: 1, bbqrHeader: nil)
        } else {
            guard let seq = BILEngineJSON.integerValue(ns.substring(with: m.range(at: 2))),
                  let count = BILEngineJSON.integerValue(ns.substring(with: m.range(at: 3))) else { return .bad(.malformed) }
            if seq < 1 || seq > BILPublicFrameGate.maxUrSequence || count < 1 { return .bad(.malformed) }
            if count > Int64(BILPublicFrameGate.maxFrames) { return .bad(.tooLarge) }
            key = SessionKey(kind: .urPart, urType: type, count: count, bbqrHeader: nil)
        }
        // BC-UR is case-insensitive: "UR:CRYPTO-PSBT/1-3/…" and its lower-case twin are the same part (the regex
        // admits ASCII only, so ASCII upper-casing is Kotlin's `uppercase(Locale.ROOT)`).
        return .ok(ParsedFrame(frame: frame, dedupText: BILPublicFrameGate.upperASCII(frame), session: key))
    }

    /// `^B\$([H2Z])P([0-9A-Z]{2})([0-9A-Z]{2})([0-9A-Z]+)$`: base-36 total 1…1295, index < total; body upper-case hex of
    /// even length (`H`) or Base32 `[A-Z2-7]` (`2` / `Z`).
    private func parseBbqr(_ frame: String) -> Parsed {
        guard let m = BILKotlinText.wholeMatch(BILPublicFrameGate.bbqrRegex, frame) else { return .bad(.malformed) }
        let ns = frame as NSString
        let encoding = ns.substring(with: m.range(at: 1))
        guard let total = BILPublicFrameGate.base36(ns.substring(with: m.range(at: 2))),
              let index = BILPublicFrameGate.base36(ns.substring(with: m.range(at: 3))) else { return .bad(.malformed) }
        let body = Array(ns.substring(with: m.range(at: 4)).utf16)
        if total < 1 || total > BILPublicFrameGate.maxBBQRFrames || index >= total { return .bad(.malformed) }
        let alphabetOk: Bool
        if encoding == "H" {
            alphabetOk = body.count % 2 == 0 && body.allSatisfy { BILScanText.isDigit($0) || ($0 >= 0x41 && $0 <= 0x46) }
        } else {
            alphabetOk = body.allSatisfy { ($0 >= 0x41 && $0 <= 0x5A) || ($0 >= 0x32 && $0 <= 0x37) }
        }
        if !alphabetOk { return .bad(.malformed) }
        let header = ns.substring(to: BILPublicFrameGate.bbqrHeaderLength)
        return .ok(ParsedFrame(frame: frame, dedupText: frame,
                               session: SessionKey(kind: .bbqrPart, urType: nil, count: Int64(total), bbqrHeader: header)))
    }

    /// Line-wrapped PSBT text loses its Kotlin whitespace (engine `decodePayload` rule), then: every unit in the alphabet;
    /// Base64 also `length % 4 == 0` and `^[A-Za-z0-9+/]+={0,2}$`; hex even length.
    private func parsePsbtText(_ trimmed: String, _ kind: BILPublicQrKind, _ alphabet: (UInt16) -> Bool) -> Parsed {
        var units = Array(trimmed.utf16)
        if units.contains(where: BILKotlinText.isWhitespace) {
            units = units.filter { !BILKotlinText.isWhitespace($0) }   // whitespace units are never surrogates
        }
        if !units.allSatisfy(alphabet) { return .bad(.malformed) }
        let wellFormed: Bool
        if kind == .psbtBase64 {
            wellFormed = units.count % 4 == 0 && BILPublicFrameGate.hasBase64Padding(units)
        } else {
            wellFormed = units.count % 2 == 0
        }
        if !wellFormed { return .bad(.malformed) }
        let frame = String(decoding: units, as: UTF16.self)
        return .ok(ParsedFrame(frame: frame, dedupText: frame,
                               session: SessionKey(kind: kind, urType: nil, count: 1, bbqrHeader: nil)))
    }

    /// Largest BC-UR sequence number (`toUint32`).
    private static let maxUrSequence: Int64 = 0xFFFF_FFFF
    /// `B$` + encoding + file type + 2-digit total.
    private static let bbqrHeaderLength = 6

    private static let urRegex = BILPublicFrameGate.regex("^[Uu][Rr]:([A-Za-z0-9-]{1,64})/(?:([0-9]{1,10})-([0-9]{1,10})/)?([A-Za-z]+)$")
    private static let bbqrRegex = BILPublicFrameGate.regex("^B\\$([H2Z])P([0-9A-Z]{2})([0-9A-Z]{2})([0-9A-Z]+)$")

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // Constant patterns: a failure here is a programming error caught by the harness.
        return try! NSRegularExpression(pattern: pattern, options: [])
    }

    private static func isBase64Char(_ c: UInt16) -> Bool {
        return (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || BILScanText.isDigit(c) || c == 0x2B || c == 0x2F || c == 0x3D
    }

    private static func isHexChar(_ c: UInt16) -> Bool {
        return BILScanText.isDigit(c) || (c >= 0x61 && c <= 0x66) || (c >= 0x41 && c <= 0x46)
    }

    /// `^[A-Za-z0-9+/]+={0,2}$` over units that are already all of `[A-Za-z0-9+/=]`: a non-empty run without `=`
    /// followed by at most two `=`.
    private static func hasBase64Padding(_ units: [UInt16]) -> Bool {
        var end = units.count
        var pads = 0
        while end > 0 && units[end - 1] == 0x3D {
            end -= 1
            pads += 1
        }
        return pads <= 2 && end >= 1 && !units[0..<end].contains(0x3D)
    }

    /// Two characters of `[0-9A-Z]` as a base-36 number.
    private static func base36(_ s: String) -> Int? {
        var n = 0
        for c in s.utf16 {
            let d: Int
            if c >= 0x30 && c <= 0x39 {
                d = Int(c - 0x30)
            } else if c >= 0x41 && c <= 0x5A {
                d = Int(c - 0x41) + 10
            } else {
                return nil
            }
            n = n * 36 + d
        }
        return n
    }

    private static func upperASCII(_ s: String) -> String {
        let u = s.utf16.map { ($0 >= 0x61 && $0 <= 0x7A) ? $0 - 0x20 : $0 }
        return String(decoding: u, as: UTF16.self)
    }

    /// SHA-256 of the UTF-8 de-duplication text.
    private static func digest(_ text: String) -> Data {
        return Data(SHA256.hash(data: Data(text.utf8)))
    }
}

/// Frames accepted by a gate while the one engine call of the session runs (C-QR-2: one call in flight, at most
/// `capacity` waiting). FIFO; when full, the oldest waiting frame is dropped and handed back to the gate (`forget`) so the
/// next loop of the animated code delivers it again (a BBQr part is never lost for good). Not thread-safe.
final class BILPublicFrameQueue: CustomStringConvertible {

    /// C-QR-2 queue bound.
    static let defaultCapacity = 32

    let capacity: Int

    init(gate: BILPublicFrameGate, capacity: Int = BILPublicFrameQueue.defaultCapacity) {
        precondition(capacity >= 1, "BILPublicFrameQueue: capacity < 1")
        self.gate = gate
        self.capacity = capacity
    }

    /// Frames waiting.
    var count: Int {
        return waiting.count
    }

    /// Queues `f`. A frame that starts a new session clears what was waiting for the previous one. Returns the frame
    /// dropped to make room (already forgotten by the gate), or nil.
    @discardableResult
    func offer(_ f: BILGateAccepted) -> BILGateAccepted? {
        if f.startsSession { waiting.removeAll() }
        var dropped: BILGateAccepted?
        if waiting.count >= capacity {
            dropped = waiting.removeFirst()
        }
        if let d = dropped { gate.forget(d.frame) }
        waiting.append(f)
        return dropped
    }

    /// The next frame to send, or nil.
    func poll() -> BILGateAccepted? {
        return waiting.isEmpty ? nil : waiting.removeFirst()
    }

    /// Drops every waiting frame (session ended); the gate is reset separately.
    func clear() {
        waiting.removeAll()
    }

    /// Counts only.
    var description: String {
        return "BILPublicFrameQueue(count: \(waiting.count))"
    }

    private let gate: BILPublicFrameGate
    private var waiting = [BILGateAccepted]()
}
