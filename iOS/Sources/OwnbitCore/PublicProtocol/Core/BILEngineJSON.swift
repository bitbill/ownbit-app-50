//  BILEngineJSON.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Public protocol (cold signer) — strictly typed readers over `BILJSONObject`. Port of Android
//  `core/publicsigner/.../model/EngineJson.kt`: a value of another JSON type reads as absent (a number is never a
//  string, a string is never a number, `1.0` and `true` are not integers), so a changed engine shape fails closed
//  instead of being coerced. Pure Foundation.
//

import Foundation

extension BILJSONObject {

    /// A JSON string only.
    public func str(_ k: String) -> String? {
        return self[k]?.stringValue
    }

    /// A number literal that is an integer (no fraction / exponent) within Int64.
    public func long(_ k: String) -> Int64? {
        guard let literal = self[k]?.numberLiteral else { return nil }
        return BILEngineJSON.integerValue(literal)
    }

    /// `long` within the Int32 range (Kotlin `Int`).
    public func int(_ k: String) -> Int? {
        guard let v = long(k), v >= Int64(Int32.min), v <= Int64(Int32.max) else { return nil }
        return Int(v)
    }

    /// A JSON bool only.
    public func bool(_ k: String) -> Bool? {
        return self[k]?.boolValue
    }

    public func obj(_ k: String) -> BILJSONObject? {
        return self[k]?.objectValue
    }

    public func arr(_ k: String) -> [BILJSONValue]? {
        return self[k]?.arrayValue
    }

    /// A list that is all strings, else nil (BitSigner `as? [String]`).
    public func strings(_ k: String) -> [String]? {
        guard let array = arr(k) else { return nil }
        var out = [String]()
        out.reserveCapacity(array.count)
        for element in array {
            guard let s = element.stringValue else { return nil }
            out.append(s)
        }
        return out
    }

    /// A list that is all integers within the Int32 range, else nil.
    public func ints(_ k: String) -> [Int]? {
        guard let array = arr(k) else { return nil }
        var out = [Int]()
        out.reserveCapacity(array.count)
        for element in array {
            guard let literal = element.numberLiteral,
                  let v = BILEngineJSON.integerValue(literal),
                  v >= Int64(Int32.min), v <= Int64(Int32.max) else { return nil }
            out.append(Int(v))
        }
        return out
    }
}

enum BILEngineJSON {

    /// Non-nil, exactly `2 * bytes` characters of `[0-9a-fA-F]` (Android `isHex`; `bytes == 0` accepts "").
    static func isHex(_ v: String?, bytes: Int) -> Bool {
        guard let v = v, bytes >= 0, v.utf16.count == bytes * 2 else { return false }
        for u in v.utf16 {
            switch u {
            case 0x30...0x39, 0x41...0x46, 0x61...0x66: continue
            default: return false
            }
        }
        return true
    }

    /// `^[0-9a-f]{64}$`.
    static func isLowerHex64(_ v: String?) -> Bool {
        guard let v = v, v.utf16.count == 64 else { return false }
        for u in v.utf16 {
            switch u {
            case 0x30...0x39, 0x61...0x66: continue
            default: return false
            }
        }
        return true
    }

    /// Android `ensureEngine`: throws `BILMalformedEngineResult(what)` unless `condition` holds. `what` names only the
    /// part that failed (never a payload, address or key).
    static func ensure(_ condition: Bool, _ what: @autoclosure () -> String) throws {
        if !condition {
            throw BILMalformedEngineResult(what: what())
        }
    }

    /// An integer literal (`-?[0-9]+`, no fraction / exponent) within Int64, else nil. Parsed by hand (accumulating
    /// negatively so that Int64.min fits) rather than through an `Int64(String…)` initializer, which an app extension
    /// (`BILThemeManager.swift` `Int64.init?(_:radix:)`) could shadow.
    static func integerValue(_ literal: String) -> Int64? {
        let units = Array(literal.utf8)
        var i = 0
        let negative = i < units.count && units[i] == 0x2D  // -
        if negative { i += 1 }
        guard i < units.count else { return nil }
        var acc: Int64 = 0                                  // ≤ 0
        while i < units.count {
            let c = units[i]
            guard c >= 0x30 && c <= 0x39 else { return nil }
            let (times10, o1) = acc.multipliedReportingOverflow(by: 10)
            let (next, o2) = times10.subtractingReportingOverflow(Int64(c - 0x30))
            if o1 || o2 { return nil }
            acc = next
            i += 1
        }
        if negative { return acc }
        return acc == Int64.min ? nil : -acc
    }
}

/// A result of the engine that does not have the shape this app relies on. The description names only the part that
/// failed — never a payload, address or key — so it may be logged. Callers treat it like an integrity failure.
public struct BILMalformedEngineResult: Error, CustomStringConvertible {
    public let what: String

    public var description: String {
        return "Malformed engine result: " + what
    }
}
