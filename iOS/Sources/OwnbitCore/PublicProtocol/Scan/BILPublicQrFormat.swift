//  BILPublicQrFormat.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Public protocol (cold signer) — pure prefix classification of public-protocol QR texts (BC-UR / BBQr / PSBT text,
//  TronLink's own JSON format, and every TokenPocket text, recognised only to be refused). Port of Android
//  `core/scanner/.../publicqr/PublicQrFormat.kt` (R4 §4) and of the scanner badge detail of
//  `feature/tools/.../scan/ScanDispatchViewModel.kt` `transportLabel()`.
//
//  C-GEN-17: every public prefix (`ur:` / `UR:`, `B$`, `cHNidP`, `70736274ff`, `{`, `tp:`, `<scheme>:<action>-version=`)
//  is disjoint from Ownbit's own `bb_*:` codes, `wc:`, `digiid:`, `eos:`, `ownbit_*` and payment URIs.
//
//  Kotlin semantics: the text is trimmed with Kotlin's whitespace set, lengths and indexes are UTF-16 code units, and every
//  comparison is exact (code units) — never Swift's canonical equivalence (`"\u{212A}" == "K"` in Swift).
//  Pure Foundation; nothing is decoded and nothing is logged.
//

import Foundation

/// What kind of public-protocol code a text is (Android `PublicQrKind`).
public enum BILPublicQrKind: CaseIterable {
    /// A single-part UR signing request: `ur:<type>/<body>` with a type of `BILPublicQrFormat.signRequestUrTypes`.
    case urSignRequest
    /// One part of a multi-part (animated, fountain-coded) UR signing request: `ur:<type>/<seq>-<count>/<body>`.
    case urPart
    /// One part of a BBQr PSBT (`B$` + encoding `H` / `2` / `Z` + file type `P`), static or animated.
    case bbqrPart
    /// A PSBT as Base64 text (`cHNidP…`).
    case psbtBase64
    /// A PSBT as hex text (`70736274ff…`, any case).
    case psbtHex
    /// Wrong direction: a pairing / watch-only export the other wallet scans.
    case pairingUr
    /// Wrong direction: a signature answer (`*-signature`).
    case signatureUr
    /// A UR of any other type, or a BBQr of another file type: a transport, but nothing the public protocol signs.
    case unsupportedUr
    /// A TronLink cold-wallet request in one QR (a JSON object with `hexList`); collected by the host, never the engine.
    case tronLinkRequest
    /// One numbered part (`cN` of `tN ≥ 2`) of a split TronLink request.
    case tronLinkPart
    /// Any TokenPocket text (owner 2026-10-13: never signed, refused with `err.tpUnsupported`).
    case tpUnsupported

    /// The transports of a signing request: the only kinds that pass the frame gate.
    public var isSigningRequest: Bool {
        return isEngineFrame || self == .tronLinkRequest || self == .tronLinkPart
    }

    /// The signing-request transports the engine's scan session collects (UR, BBQr, PSBT text).
    public var isEngineFrame: Bool {
        switch self {
        case .urSignRequest, .urPart, .bbqrPart, .psbtBase64, .psbtHex: return true
        default: return false
        }
    }

    /// A TronLink QR (one request or one part).
    public var isTronLink: Bool {
        return self == .tronLinkRequest || self == .tronLinkPart
    }

    /// A code meant for the other wallet (pairing export or signature answer): the "wrong direction" alert.
    public var isWrongDirection: Bool {
        return self == .pairingUr || self == .signatureUr
    }

    /// A UR text (`ur:` scheme), as opposed to BBQr or PSBT text.
    public var isUr: Bool {
        switch self {
        case .urSignRequest, .urPart, .pairingUr, .signatureUr, .unsupportedUr: return true
        default: return false
        }
    }
}

public enum BILPublicQrFormat {

    /// UR types the engine signs (`SIGNING_UR_TYPES` of the engine).
    public static let signRequestUrTypes: Set<String> = ["crypto-psbt", "psbt", "eth-sign-request", "sol-sign-request", "tron-sign-request"]

    /// Pairing / watch-only exports (BCR-2020-015 / Keystone names, their BCR-2023 names, `ur:bytes`).
    public static let pairingUrTypes: Set<String> = [
        "crypto-account", "crypto-hdkey", "crypto-multi-accounts", "crypto-output", "bytes",
        "account-descriptor", "hdkey", "output-descriptor",
    ]

    /// The public-protocol kind of `text` (Kotlin-trimmed first), or nil when it is not a public-protocol code (the rest of
    /// the Ownbit pipeline decides). First match wins: `ur:` (any case) → UR rules; `B$` → BBQr rules; `cHNidP` → PSBT
    /// Base64; `70736274ff` (any case) → PSBT hex; `{` → TronLink / TokenPocket legacy JSON (else nil); a TokenPocket
    /// text → `tpUnsupported`. Cost: prefix checks plus at most one strict JSON parse of ≤ 4,300 characters.
    public static func classify(_ text: String) -> BILPublicQrKind? {
        let t = BILKotlinText.trim(text)
        if BILScanText.hasPrefixIgnoringASCIICase(t, "ur:") { return classifyUr(t) }
        if BILPublicHex.hasASCIIPrefix(t, "B$") { return classifyBbqr(t) }
        if BILPublicHex.hasASCIIPrefix(t, "cHNidP") { return .psbtBase64 }
        if BILScanText.hasPrefixIgnoringASCIICase(t, "70736274ff") { return .psbtHex }
        if BILPublicHex.hasASCIIPrefix(t, "{") { return classifyJson(t) }
        if isTokenPocketText(t) { return .tpUnsupported }
        return nil
    }

    /// The lower-case UR type of a `ur:<type>/…` text (trimmed first), or nil: the first `/` after `ur:` ends a type of
    /// 1…64 UTF-16 units, lower-cased (Kotlin `lowercase(Locale.ROOT)`), every unit `[a-z0-9-]`.
    public static func urType(_ text: String) -> String? {
        let t = BILKotlinText.trim(text)
        guard BILScanText.hasPrefixIgnoringASCIICase(t, "ur:") else { return nil }
        let u = Array(t.utf16)
        guard let slash = BILScanText.firstIndex(of: 0x2F, in: u, from: 3) else { return nil }
        if slash <= 3 || slash - 3 > maxUrTypeLength { return nil }
        // Both ends of the slice are ASCII (`:` and `/`), so the cut never splits a surrogate pair.
        let type = String(decoding: u[3..<slash], as: UTF16.self).lowercased()
        for c in type.utf16 where !isUrTypeChar(c) {
            return nil
        }
        return type
    }

    /// The technical detail of the scanner's protocol badge (Android `transportLabel()`), built from the prefix only and
    /// never translated: "UR · <type>" for a signing UR type, "BBQr · PSBT", "PSBT", "TronLink"; nil for the other kinds
    /// (wrong direction, unsupported, TokenPocket).
    public static func scannerBadgeDetail(kind: BILPublicQrKind, text: String) -> String? {
        switch kind {
        case .urSignRequest, .urPart:
            guard let type = urType(text), signRequestUrTypes.contains(type) else { return nil }
            return "UR · " + type
        case .bbqrPart:
            return "BBQr · PSBT"
        case .psbtBase64, .psbtHex:
            return "PSBT"
        case .tronLinkRequest, .tronLinkPart:
            return "TronLink"
        case .pairingUr, .signatureUr, .unsupportedUr, .tpUnsupported:
            return nil
        }
    }

    // MARK: - Private

    /// Longer "types" are not UR types (the registry's longest is ~25 characters).
    private static let maxUrTypeLength = 64

    private static func classifyUr(_ t: String) -> BILPublicQrKind? {
        guard let type = urType(t) else { return nil }
        if signRequestUrTypes.contains(type) {
            return hasSequence(t, from: 3 + type.utf16.count + 1) ? .urPart : .urSignRequest
        }
        if pairingUrTypes.contains(type) { return .pairingUr }
        if BILScanText.hasASCIISuffix(type, "-signature") { return .signatureUr }
        return .unsupportedUr
    }

    /// `<digits>-<digits>/` starting at UTF-16 index `from` (the multi-part sequence component of BC-UR), followed by at
    /// least one more character.
    private static func hasSequence(_ t: String, from: Int) -> Bool {
        let u = Array(t.utf16)
        guard let slash = BILScanText.firstIndex(of: 0x2F, in: u, from: from), slash != u.count - 1 else { return false }
        let component = Array(u[from..<slash])
        guard let dash = component.firstIndex(of: 0x2D), dash > 0, dash != component.count - 1 else { return false }
        return component[0..<dash].allSatisfy(BILScanText.isDigit) && component[(dash + 1)...].allSatisfy(BILScanText.isDigit)
    }

    /// `B$` + `H` / `2` / `Z` + `P` → BBQr PSBT; + another upper-case file type → unsupported; else nil.
    private static func classifyBbqr(_ t: String) -> BILPublicQrKind? {
        let u = Array(t.utf16.prefix(4))
        guard u.count >= 4 else { return nil }
        guard u[2] == 0x48 || u[2] == 0x32 || u[2] == 0x5A else { return nil }       // H 2 Z
        if u[3] == 0x50 { return .bbqrPart }                                         // P
        if u[3] >= 0x41 && u[3] <= 0x5A { return .unsupportedUr }                    // A…Z
        return nil
    }

    /// A JSON object text: TronLink (`hexList`), TokenPocket's legacy hash-only JSON, else nil.
    private static func classifyJson(_ t: String) -> BILPublicQrKind? {
        if BILTronLinkQrFormat.looksLike(t) {
            // Malformed TronLink JSON is still TronLink: the gate then says malformed.
            return BILTronLinkQrFormat.parse(t)?.isPart == true ? .tronLinkPart : .tronLinkRequest
        }
        if isTokenPocketLegacyJson(t) { return .tpUnsupported }
        return nil
    }

    /// TokenPocket's old hash-only cold-wallet JSON: ≤ 4,300 characters, naming `coldWalletSign`, a strict JSON object
    /// whose `action` is the JSON string `"coldWalletSign"`.
    private static func isTokenPocketLegacyJson(_ t: String) -> Bool {
        if t.utf16.count > BILPublicFrameGate.maxFrameChars || !BILScanText.contains(t, tpLegacyAction) { return false }
        guard let json = BILStrictJSON.parseObject(t), let action = json["action"]?.stringValue else { return false }
        return BILJSONExact.equal(action, tpLegacyAction)
    }

    /// Any `tp:` text naming `protocol=TokenPocket`, or an action text matching
    /// `^[a-z]+:[A-Za-z0-9]+-version=[0-9.]{1,8}&protocol=TokenPocket&` at the start (Kotlin `containsMatchIn` with `^`,
    /// no multi-line flag). Payment URIs (`tron:T…?amount=…`) never carry this header.
    private static func isTokenPocketText(_ t: String) -> Bool {
        if BILPublicHex.hasASCIIPrefix(t, "tp:") && BILScanText.contains(t, "protocol=TokenPocket") { return true }
        return matchesTokenPocketAction(t)
    }

    /// The action-header regex of Android, matched by hand on UTF-16 units. Every repetition is followed by a character
    /// outside its class, so the greedy runs below are exactly the regex (no backtracking can change the outcome); linear
    /// on very long input.
    private static func matchesTokenPocketAction(_ t: String) -> Bool {
        guard let first = t.utf16.first, first >= 0x61 && first <= 0x7A else { return false }   // cheap exit
        let u = Array(t.utf16)
        var i = 0
        // [a-z]+
        let schemeStart = i
        while i < u.count && u[i] >= 0x61 && u[i] <= 0x7A { i += 1 }
        guard i > schemeStart, i < u.count, u[i] == 0x3A else { return false }       // :
        i += 1
        // [A-Za-z0-9]+
        let actionStart = i
        while i < u.count && BILScanText.isASCIIAlphanumeric(u[i]) { i += 1 }
        guard i > actionStart else { return false }
        // -version=
        guard BILScanText.matches(u, at: i, "-version=") else { return false }
        i += 9
        // [0-9.]{1,8}
        let versionStart = i
        while i < u.count && (BILScanText.isDigit(u[i]) || u[i] == 0x2E) { i += 1 }
        let versionLength = i - versionStart
        guard versionLength >= 1 && versionLength <= 8 else { return false }
        // &protocol=TokenPocket&
        return BILScanText.matches(u, at: i, "&protocol=TokenPocket&")
    }

    private static func isUrTypeChar(_ c: UInt16) -> Bool {
        return (c >= 0x61 && c <= 0x7A) || BILScanText.isDigit(c) || c == 0x2D
    }

    private static let tpLegacyAction = "coldWalletSign"
}

/// Code-unit text helpers of the scan area (Kotlin `startsWith` / `contains` / `indexOf` semantics; exact, ASCII
/// patterns only).
enum BILScanText {

    static func isDigit(_ c: UInt16) -> Bool {
        return c >= 0x30 && c <= 0x39
    }

    static func isASCIIAlphanumeric(_ c: UInt16) -> Bool {
        return isDigit(c) || (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A)
    }

    /// Kotlin `startsWith(prefix, ignoreCase = true)` for an ASCII `prefix` (only ASCII letters fold to each other).
    static func hasPrefixIgnoringASCIICase(_ s: String, _ prefix: String) -> Bool {
        let p = Array(prefix.utf16)
        var i = 0
        for c in s.utf16 {
            if i == p.count { return true }
            if lowerASCII(c) != lowerASCII(p[i]) { return false }
            i += 1
        }
        return i == p.count
    }

    /// Code-unit suffix test for an ASCII `suffix`.
    static func hasASCIISuffix(_ s: String, _ suffix: String) -> Bool {
        return s.utf8.reversed().starts(with: suffix.utf8.reversed())
    }

    /// Kotlin `String.contains(needle)` (exact code units; `needle` non-empty ASCII).
    static func contains(_ s: String, _ needle: String) -> Bool {
        let n = Array(needle.utf8)
        guard !n.isEmpty else { return true }
        let h = Array(s.utf8)
        guard h.count >= n.count else { return false }
        var i = 0
        while i + n.count <= h.count {
            if h[i] == n[0] {
                var k = 1
                while k < n.count && h[i + k] == n[k] { k += 1 }
                if k == n.count { return true }
            }
            i += 1
        }
        return false
    }

    /// Kotlin `indexOf(char, startIndex)` on UTF-16 units (a start past the end finds nothing).
    static func firstIndex(of unit: UInt16, in u: [UInt16], from: Int) -> Int? {
        var i = max(0, from)
        while i < u.count {
            if u[i] == unit { return i }
            i += 1
        }
        return nil
    }

    /// `u[at...]` starts with the ASCII `literal`.
    static func matches(_ u: [UInt16], at: Int, _ literal: String) -> Bool {
        let l = Array(literal.utf16)
        guard at >= 0, at + l.count <= u.count else { return false }
        for k in 0..<l.count where u[at + k] != l[k] {
            return false
        }
        return true
    }

    /// Exact equality of optional strings (code units).
    static func same(_ a: String?, _ b: String?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case (let x?, let y?): return BILJSONExact.equal(x, y)
        default: return false
        }
    }

    /// Exact element-wise equality of string lists.
    static func same(_ a: [String], _ b: [String]) -> Bool {
        guard a.count == b.count else { return false }
        for i in 0..<a.count where !BILJSONExact.equal(a[i], b[i]) {
            return false
        }
        return true
    }

    private static func lowerASCII(_ c: UInt16) -> UInt16 {
        return (c >= 0x41 && c <= 0x5A) ? c + 0x20 : c
    }
}
