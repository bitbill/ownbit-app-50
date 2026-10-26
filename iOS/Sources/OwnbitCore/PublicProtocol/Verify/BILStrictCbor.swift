//  BILStrictCbor.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Public protocol (cold signer) — strict CBOR reader for the native checks: the engine's `readCBOR` rules
//  (`protocols.js`), ported from Android `PS:verify/SignatureUrCodec.kt:306-398` (`object Cbor`; R5 §3.8):
//  definite lengths only, depth ≤ 24, ≤ 20 000 items, integers within ±(2⁵³ − 1) (checked before shifting), byte /
//  text strings (strict UTF-8), arrays ≤ 20 000, maps ≤ 10 000 pairs with integer or text keys and no duplicates, tags,
//  `true` / `false` / `null` (no floats, no other simple values); no trailing bytes. Minimal integer encoding is
//  **not** required (Android / engine). Pure Foundation.
//

import Foundation

/// One strict-CBOR item. Android represents integers of both signs as `Long`; here major type 0 is `.uint` and major
/// type 1 is `.nint` holding the value `−1 − n` (both within ±(2⁵³ − 1)); `integerValue` gives the Kotlin `Long` view.
/// Equality is exact (text compared by code units, maps by their pairs in order, never Swift canonical equivalence).
indirect enum BILCbor: Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    case uint(UInt64)
    case nint(Int64)
    case bytes([UInt8])
    case text(String)
    case array([BILCbor])
    /// Pairs in encoding order; keys are `.uint`, `.nint` or `.text` and unique.
    case map([(BILCbor, BILCbor)])
    case tag(UInt64, BILCbor)
    case bool(Bool)
    case null

    static func == (lhs: BILCbor, rhs: BILCbor) -> Bool {
        switch (lhs, rhs) {
        case let (.uint(a), .uint(b)): return a == b
        case let (.nint(a), .nint(b)): return a == b
        case let (.bytes(a), .bytes(b)): return a == b
        case let (.text(a), .text(b)): return a.utf8.elementsEqual(b.utf8)
        case let (.array(a), .array(b)): return a == b
        case let (.map(a), .map(b)):
            guard a.count == b.count else { return false }
            for i in 0..<a.count where !(a[i].0 == b[i].0 && a[i].1 == b[i].1) { return false }
            return true
        case let (.tag(t1, v1), .tag(t2, v2)): return t1 == t2 && v1 == v2
        case let (.bool(a), .bool(b)): return a == b
        case (.null, .null): return true
        default: return false
        }
    }

    /// Kotlin `as? Long`: the value of `.uint` / `.nint`, else nil (also nil for a hand-built `.uint` above
    /// `Int64.max`, which no Kotlin `Long` holds; decoded values are ≤ 2⁵³ − 1).
    var integerValue: Int64? {
        switch self {
        case .uint(let v): return Int64(exactly: v)
        case .nint(let v): return v
        default: return nil
        }
    }

    /// Kotlin `as? ByteArray`.
    var bytesValue: [UInt8]? {
        if case .bytes(let b) = self { return b }
        return nil
    }

    /// Kotlin `as? String`.
    var textValue: String? {
        if case .text(let s) = self { return s }
        return nil
    }

    /// Kotlin `as? List<*>`.
    var arrayValue: [BILCbor]? {
        if case .array(let a) = self { return a }
        return nil
    }

    /// Kotlin `as? Map<*, *>` (pairs in encoding order).
    var mapPairs: [(BILCbor, BILCbor)]? {
        if case .map(let m) = self { return m }
        return nil
    }

    /// Kotlin `map[key]` with an integer key on a decoded map: the value of the pair whose key is the integer `key`
    /// (`.uint` or `.nint`), and nil when there is none **or the value is CBOR null** (Kotlin's `get` returns null for
    /// both). nil when `self` is not a map.
    func get(_ key: Int64) -> BILCbor? {
        guard case .map(let pairs) = self else { return nil }
        for (k, v) in pairs where k.integerValue == key {
            if case .null = v { return nil }
            return v
        }
        return nil
    }

    /// Kind only (never content).
    var description: String {
        switch self {
        case .uint: return "BILCbor(uint)"
        case .nint: return "BILCbor(nint)"
        case .bytes(let b): return "BILCbor(bytes \(b.count))"
        case .text: return "BILCbor(text)"
        case .array(let a): return "BILCbor(array \(a.count))"
        case .map(let m): return "BILCbor(map \(m.count))"
        case .tag: return "BILCbor(tag)"
        case .bool: return "BILCbor(bool)"
        case .null: return "BILCbor(null)"
        }
    }

    var debugDescription: String { return description }

    /// No children: `dump` / reflection print the description only.
    var customMirror: Mirror { return Mirror(self, children: [:]) }
}

enum BILStrictCbor {
    static let maxDepth = 24
    static let maxNodes = 20_000
    static let maxMapPairs = 10_000
    static let maxSafeInteger: UInt64 = 9_007_199_254_740_991

    /// Decodes exactly one item spanning all of `bytes`; throws `BILVerifyError` (`cbor.*`) on any rule above.
    static func decode(_ bytes: [UInt8]) throws -> BILCbor {
        var reader = Reader(bytes: bytes)
        let value = try reader.item(0)
        try BILVerifyError.check(reader.pos == bytes.count, "cbor.trailing")
        return value
    }

    // MARK: - Private

    private enum KeyID: Hashable {
        case int(Int64)
        case text([UInt8])
    }

    private struct Reader {
        let bytes: [UInt8]
        var pos = 0
        var nodes = 0

        init(bytes: [UInt8]) {
            self.bytes = bytes
        }

        mutating func take(_ n: UInt64) throws -> [UInt8] {
            try BILVerifyError.check(n <= UInt64(bytes.count - pos), "cbor.truncated")
            let end = pos + Int(n)
            let out = Array(bytes[pos..<end])
            pos = end
            return out
        }

        mutating func item(_ depth: Int) throws -> BILCbor {
            nodes += 1
            try BILVerifyError.check(depth <= BILStrictCbor.maxDepth && nodes <= BILStrictCbor.maxNodes, "cbor.complexity")
            let first = try take(1)[0]
            let major = first >> 5
            let info = first & 31
            try BILVerifyError.check(info <= 27, "cbor.indefinite")
            if major == 7 {
                switch info {
                case 20: return .bool(false)
                case 21: return .bool(true)
                case 22: return .null
                default: throw BILVerifyError("cbor.simple")
                }
            }
            var size = UInt64(info)
            if info >= 24 {
                size = 0
                let width = UInt64(1) << UInt64(info - 24)
                for b in try take(width) {
                    try BILVerifyError.check(size >> 55 == 0, "cbor.integer")
                    size = (size << 8) | UInt64(b)
                }
            }
            try BILVerifyError.check(size <= BILStrictCbor.maxSafeInteger, "cbor.integer")
            switch major {
            case 0:
                return .uint(size)
            case 1:
                return .nint(-1 - Int64(size))
            case 2:
                return .bytes(try take(size))
            case 3:
                let raw = try take(size)
                guard let text = BILVerifyText.strictUTF8(raw) else { throw BILVerifyError("cbor.utf8") }
                return .text(text)
            case 4:
                try BILVerifyError.check(size <= UInt64(BILStrictCbor.maxNodes), "cbor.array")
                var items = [BILCbor]()
                items.reserveCapacity(Int(min(size, UInt64(bytes.count - pos))))
                for _ in 0..<Int(size) { items.append(try item(depth + 1)) }
                return .array(items)
            case 5:
                try BILVerifyError.check(size <= UInt64(BILStrictCbor.maxMapPairs), "cbor.map")
                var pairs = [(BILCbor, BILCbor)]()
                var seen = Set<KeyID>()
                for _ in 0..<Int(size) {
                    let key = try item(depth + 1)
                    let id: KeyID
                    switch key {
                    case .uint, .nint: id = .int(key.integerValue ?? 0)
                    case .text(let s): id = .text(Array(s.utf8))
                    default: throw BILVerifyError("cbor.mapKey")
                    }
                    try BILVerifyError.check(seen.insert(id).inserted, "cbor.duplicateKey")
                    pairs.append((key, try item(depth + 1)))
                }
                return .map(pairs)
            case 6:
                return .tag(size, try item(depth + 1))
            default:
                throw BILVerifyError("cbor.type")
            }
        }
    }
}
