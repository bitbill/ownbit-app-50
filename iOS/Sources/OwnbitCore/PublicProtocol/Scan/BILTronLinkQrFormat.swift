//  BILTronLinkQrFormat.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Public protocol (cold signer) — one QR of TronLink's cold-wallet protocol: a JSON object
//  `{"address", "type", "hexList": [...], …}`, or one numbered part of a split one (`cN` 1-based of `tN` parts).
//  Port of Android `core/scanner/.../publicqr/TronLinkQrFormat.kt` (R4 §6). Strict JSON (`BILStrictJSON`: duplicate keys
//  refused, key order and number literals kept — the answer echoes the object). Pure Foundation; nothing is logged and
//  `description` prints counts only.
//

import Foundation

/// One parsed TronLink QR.
struct BILTronLinkFrame: Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// The object exactly as scanned (key order and number literals kept).
    let json: BILJSONObject
    /// The entries (a full `Transaction` protobuf as hex, a message, or — in a part — one piece of `h1&&&h2&&&…`).
    let hexList: [String]
    /// TronLink's page type (`0` when absent: the first parts of a split request carry none).
    let type: Int
    /// The account the request is for (single requests, first and last parts).
    let address: String?
    /// The part number / part count (`0` / `0` in an Android single request, absent on iOS).
    let cN: Int?
    let tN: Int?
    /// Shielded (TRC-z) fields, refused by the mapper.
    let alpha: String?
    let tokenId: String?

    /// One part of a split request (`tN ≥ 2`).
    var isPart: Bool {
        return (tN ?? 0) >= 2
    }

    /// Counts only (the request text is never printed).
    var description: String {
        return "BILTronLinkFrame(type: \(type), entries: \(hexList.count), cN: \(cN.map(String.init) ?? "nil"), tN: \(tN.map(String.init) ?? "nil"))"
    }

    var debugDescription: String {
        return description
    }

    /// No children: `dump` / `Mirror` show no entry, address or object.
    var customMirror: Mirror {
        return Mirror(self, children: [:])
    }

    /// Exact (code-unit) equality of every field; the object compares as a map (kotlinx).
    static func == (lhs: BILTronLinkFrame, rhs: BILTronLinkFrame) -> Bool {
        return lhs.json == rhs.json && BILScanText.same(lhs.hexList, rhs.hexList) && lhs.type == rhs.type
            && BILScanText.same(lhs.address, rhs.address) && lhs.cN == rhs.cN && lhs.tN == rhs.tN
            && BILScanText.same(lhs.alpha, rhs.alpha) && BILScanText.same(lhs.tokenId, rhs.tokenId)
    }
}

enum BILTronLinkQrFormat {

    /// Entries of one request (TronLink sends 1, 2 for "stake and vote").
    static let maxEntries = 32
    /// Characters (UTF-16 units) of a reassembled / pasted request (128 KiB, the collector's limit).
    static let maxRequestChars = 131_072

    /// `true` when `text` (trimmed) has the outer shape of a TronLink QR — a JSON object naming `"hexList"` (cheap).
    static func looksLike(_ text: String) -> Bool {
        let t = BILKotlinText.trim(text)
        let u = t.utf16
        guard u.count >= 2, u.first == 0x7B, u.last == 0x7D else { return false }   // { … }
        return BILScanText.contains(t, "\"hexList\"")
    }

    /// `text` (trimmed) as a TronLink frame, or nil: a strict JSON object of at most `maxChars` UTF-16 units (one QR:
    /// 4,300; a reassembled request: `maxRequestChars`) with `hexList` = 1…32 JSON strings, an integer `type` in
    /// `0…Int32.max` (absent → 0), an optional string `address`, integer `cN` / `tN` (a part, `tN ≥ 2`: `1 ≤ cN ≤ tN` and
    /// exactly one entry; a single request: `cN` absent, 0 or 1), optional strings `alpha` / `tokenId`. Other keys are
    /// kept (echoed) and ignored. A present key of the wrong type (`"address": null`, `"type": "1"`) → nil.
    static func parse(_ text: String, maxChars: Int = BILPublicFrameGate.maxFrameChars) -> BILTronLinkFrame? {
        let t = BILKotlinText.trim(text)
        if t.utf16.count > maxChars || !looksLike(t) { return nil }
        guard let json = BILStrictJSON.parseObject(t) else { return nil }
        guard let list = json["hexList"]?.arrayValue, !list.isEmpty, list.count <= maxEntries else { return nil }
        var entries = [String]()
        entries.reserveCapacity(list.count)
        for element in list {
            guard let s = element.stringValue else { return nil }
            entries.append(s)
        }
        var type = 0
        if let v = json["type"] {
            guard let n = int(v) else { return nil }
            type = n
        }
        var address: String?
        if let v = json["address"] {
            guard let s = v.stringValue else { return nil }
            address = s
        }
        var cN: Int?
        if let v = json["cN"] {
            guard let n = int(v) else { return nil }
            cN = n
        }
        var tN: Int?
        if let v = json["tN"] {
            guard let n = int(v) else { return nil }
            tN = n
        }
        if let parts = tN, parts >= 2 {
            // A part: its number and exactly one piece of the joined entries.
            guard let number = cN, number >= 1, number <= parts, entries.count == 1 else { return nil }
        } else if let number = cN, number > 1 {
            // A single request (Android writes cN = tN = 0; iOS omits both).
            return nil
        }
        var alpha: String?
        if let v = json["alpha"] {
            guard let s = v.stringValue else { return nil }
            alpha = s
        }
        var tokenId: String?
        if let v = json["tokenId"] {
            guard let s = v.stringValue else { return nil }
            tokenId = s
        }
        return BILTronLinkFrame(json: json, hexList: entries, type: type, address: address, cN: cN, tN: tN,
                                alpha: alpha, tokenId: tokenId)
    }

    /// A non-negative JSON integer literal that fits an `Int32` (no fraction, no exponent, no sign, no leading zero, ≤ 10
    /// digits); strings, bools and null are not integers.
    private static func int(_ value: BILJSONValue) -> Int? {
        guard let literal = value.numberLiteral else { return nil }
        let u = Array(literal.utf8)
        if u.isEmpty || u.count > 10 { return nil }
        if u.count > 1 && u[0] == 0x30 { return nil }
        var n: Int64 = 0
        for c in u {
            guard c >= 0x30 && c <= 0x39 else { return nil }
            n = n * 10 + Int64(c - 0x30)
        }
        return n <= Int64(Int32.max) ? Int(n) : nil
    }
}
