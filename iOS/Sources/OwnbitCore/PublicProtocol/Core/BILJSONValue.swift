//  BILJSONValue.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Public protocol (cold signer) — one ordered, literal-preserving JSON model for every public-protocol JSON
//  (engine I/O, TronLink frames / answers, plan / review models, offline-sign history). Port of Android
//  `core/scanner/.../publicqr/StrictJson.kt` (strict validator) + kotlinx-serialization-json 1.7.3
//  `JsonElement.toString()` / `printQuoted` (compact serializer), see design §1.5 (D-01) and R4 §5.
//
//  Rules:
//  - Key order and number literals are kept exactly as parsed (`9007199254740993`, `1.50`).
//  - Keys and strings compare by exact Unicode scalars (code units), never by Swift canonical equivalence:
//    "é" (U+00E9) and "e" + U+0301 are two different keys / values, like Kotlin.
//  - Pure Foundation; nothing is logged.
//

import Foundation

/// One JSON value. Equality is kotlinx's: objects compare as maps (order-insensitive), arrays element-wise, numbers by
/// their literal (`1` ≠ `1.0`), strings by exact Unicode scalars, bools, null.
public indirect enum BILJSONValue: Equatable {
    case object(BILJSONObject)
    case array([BILJSONValue])
    case string(String)
    /// The number literal exactly as parsed or produced ("9007199254740993", "1.50").
    case number(String)
    case bool(Bool)
    case null

    /// `.number(String(v))`.
    public static func int<I: BinaryInteger>(_ v: I) -> BILJSONValue {
        return .number(String(v))
    }

    public var objectValue: BILJSONObject? {
        if case .object(let o) = self { return o }
        return nil
    }

    public var arrayValue: [BILJSONValue]? {
        if case .array(let a) = self { return a }
        return nil
    }

    /// Only `.string`.
    public var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    /// Only `.number`.
    public var numberLiteral: String? {
        if case .number(let n) = self { return n }
        return nil
    }

    /// Only `.bool`.
    public var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }

    public var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    /// Android `JsonElement.displayText()`: a string as it is, `null` → "", anything else in its compact JSON form.
    public var displayText: String {
        switch self {
        case .string(let s): return s
        case .null: return ""
        default: return BILStrictJSON.serialize(self)
        }
    }

    public static func == (lhs: BILJSONValue, rhs: BILJSONValue) -> Bool {
        switch (lhs, rhs) {
        case (.object(let a), .object(let b)): return a == b
        case (.array(let a), .array(let b)):
            guard a.count == b.count else { return false }
            for i in 0..<a.count where a[i] != b[i] { return false }
            return true
        case (.string(let a), .string(let b)): return BILJSONExact.equal(a, b)
        case (.number(let a), .number(let b)): return BILJSONExact.equal(a, b)
        case (.bool(let a), .bool(let b)): return a == b
        case (.null, .null): return true
        default: return false
        }
    }
}

/// An ordered JSON object with unique (exact) keys. `set` has `LinkedHashMap.put` semantics: an existing key keeps its
/// position, a new key is appended.
public struct BILJSONObject: Equatable {

    private var storage: [(key: String, value: BILJSONValue)] = []
    /// Exact-key → position, maintained only for larger objects (small ones are scanned linearly).
    private var index: [ExactKey: Int]? = nil

    private static let indexThreshold = 16

    public init() {}

    /// Precondition: keys unique (exact). A repeated key is a programming error (assertion in DEBUG); in release it
    /// follows `put` semantics (first position, last value).
    public init(_ entries: [(String, BILJSONValue)]) {
        storage.reserveCapacity(entries.count)
        for (k, v) in entries {
            assert(position(of: k) == nil, "BILJSONObject: duplicate key")
            set(k, v)
        }
    }

    /// Insertion order.
    public var entries: [(key: String, value: BILJSONValue)] {
        return storage
    }

    public var keys: [String] {
        return storage.map { $0.key }
    }

    public var count: Int {
        return storage.count
    }

    public var isEmpty: Bool {
        return storage.isEmpty
    }

    /// Exact key lookup; setting keeps the position of an existing key (or appends); setting `nil` removes the key.
    public subscript(key: String) -> BILJSONValue? {
        get {
            guard let i = position(of: key) else { return nil }
            return storage[i].value
        }
        set {
            if let v = newValue {
                set(key, v)
            } else {
                remove(key)
            }
        }
    }

    /// `LinkedHashMap.put` semantics.
    public mutating func set(_ key: String, _ value: BILJSONValue) {
        if let i = position(of: key) {
            storage[i].value = value
            return
        }
        storage.append((key: key, value: value))
        if index != nil {
            index?[ExactKey(key)] = storage.count - 1
        } else if storage.count > BILJSONObject.indexThreshold {
            rebuildIndex()
        }
    }

    public mutating func remove(_ key: String) {
        guard let i = position(of: key) else { return }
        storage.remove(at: i)
        if storage.count > BILJSONObject.indexThreshold {
            rebuildIndex()
        } else {
            index = nil
        }
    }

    public func contains(_ key: String) -> Bool {
        return position(of: key) != nil
    }

    /// A copy with `key` set (`put` semantics).
    public func appending(_ key: String, _ value: BILJSONValue) -> BILJSONObject {
        var copy = self
        copy.set(key, value)
        return copy
    }

    public static func == (lhs: BILJSONObject, rhs: BILJSONObject) -> Bool {
        guard lhs.storage.count == rhs.storage.count else { return false }
        for entry in lhs.storage {
            guard let other = rhs[entry.key], other == entry.value else { return false }
        }
        return true
    }

    // MARK: - Private

    private func position(of key: String) -> Int? {
        if let index = index {
            return index[ExactKey(key)]
        }
        for i in 0..<storage.count where BILJSONExact.equal(storage[i].key, key) {
            return i
        }
        return nil
    }

    private mutating func rebuildIndex() {
        var map = [ExactKey: Int](minimumCapacity: storage.count)
        for (i, e) in storage.enumerated() {
            map[ExactKey(e.key)] = i
        }
        index = map
    }

    /// A key compared and hashed by its exact UTF-8 bytes (= exact Unicode scalars), not by canonical equivalence.
    private struct ExactKey: Hashable {
        let text: String
        init(_ text: String) { self.text = text }

        static func == (lhs: ExactKey, rhs: ExactKey) -> Bool {
            return BILJSONExact.equal(lhs.text, rhs.text)
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(text.utf8.count)
            for b in text.utf8 {
                hasher.combine(b)
            }
        }
    }
}

// C-KEY-5, defence in depth: a tree can hold a seed request, a plan, a public index or a signed result, so printing
// one (`"\(x)"`, `String(describing:)`, `dump`, an assertion / error message, a value nested in another type's default
// description) shows only its kind. Where content is really needed (tests), print `BILStrictJSON.serialize(x)`.
extension BILJSONValue: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {

    public var description: String {
        switch self {
        case .object: return "BILJSONValue(object)"
        case .array: return "BILJSONValue(array)"
        case .string: return "BILJSONValue(string)"
        case .number: return "BILJSONValue(number)"
        case .bool: return "BILJSONValue(bool)"
        case .null: return "BILJSONValue(null)"
        }
    }

    public var debugDescription: String {
        return description
    }

    public var customMirror: Mirror {
        return Mirror(self, children: [:])
    }
}

extension BILJSONObject: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {

    public var description: String {
        return "BILJSONObject(\(count) keys)"
    }

    public var debugDescription: String {
        return description
    }

    public var customMirror: Mirror {
        return Mirror(self, children: [:])
    }
}

/// Exact (scalar / code-unit) string equality used by the JSON model.
public enum BILJSONExact {
    public static func equal(_ a: String, _ b: String) -> Bool {
        return a.utf8.elementsEqual(b.utf8)
    }
}

/// Strict RFC 8259 parsing (Android `StrictJson.Validator` + kotlinx tree) and kotlinx-compatible serialization.
public enum BILStrictJSON {

    public struct Options: Equatable {
        public var maxDepth: Int
        /// TronLink / TokenPocket / history / EIP-712 text (Android `StrictJson.MAX_DEPTH`).
        public static let strict = Options(maxDepth: 32)
        /// Engine responses (the engine caps its own requests at depth 32).
        public static let engine = Options(maxDepth: 64)
    }

    /// RFC 8259 only; no duplicate keys in any object; whitespace = SP/HT/LF/CR; depth rule of R4 §5.2;
    /// `\u` escapes leaving a lone surrogate → nil (D-27). The whole input must be consumed.
    public static func parse(_ text: String, options: Options = .strict) -> BILJSONValue? {
        var parser = Parser(units: Array(text.utf16), maxDepth: options.maxDepth)
        return parser.parseDocument()
    }

    /// nil unless `text` is exactly one strict JSON object.
    public static func parseObject(_ text: String, options: Options = .strict) -> BILJSONObject? {
        return parse(text, options: options)?.objectValue
    }

    /// Strict UTF-8 first (invalid / overlong / surrogate sequences → nil), then `parse`.
    public static func parse(utf8 bytes: [UInt8], options: Options = .strict) -> BILJSONValue? {
        let text = String(decoding: bytes, as: UTF8.self)
        // The decoder replaces every invalid sequence with U+FFFD, so a lossless round trip means valid UTF-8.
        guard text.utf8.elementsEqual(bytes) else { return nil }
        return parse(text, options: options)
    }

    /// Compact, byte-identical to kotlinx `JsonElement.toString()`: no spaces, `/` unescaped, non-ASCII raw, escapes
    /// only `"` `\` \b \f \n \r \t and other U+0000–U+001F as \u00xx (lower-case hex).
    public static func serialize(_ value: BILJSONValue) -> String {
        var out = [UInt8]()
        write(value, into: &out)
        return String(decoding: out, as: UTF8.self)
    }

    public static func serialize(_ object: BILJSONObject) -> String {
        return serialize(.object(object))
    }

    /// kotlinx `printQuoted`.
    public static func quote(_ s: String) -> String {
        var out = [UInt8]()
        writeQuoted(s, into: &out)
        return String(decoding: out, as: UTF8.self)
    }

    /// Display only (payload disclosure): keys sorted recursively by UTF-16 code units, 2-space indent, `": "`,
    /// empty containers `{}` / `[]`. Byte parity with Android is not required.
    public static func prettySorted(_ value: BILJSONValue) -> String {
        var out = [UInt8]()
        writePretty(value, indent: 0, into: &out)
        return String(decoding: out, as: UTF8.self)
    }

    // MARK: - Serializer

    private static func write(_ value: BILJSONValue, into out: inout [UInt8]) {
        switch value {
        case .object(let o):
            out.append(0x7B) // {
            var first = true
            for e in o.entries {
                if !first { out.append(0x2C) }
                first = false
                writeQuoted(e.key, into: &out)
                out.append(0x3A) // :
                write(e.value, into: &out)
            }
            out.append(0x7D) // }
        case .array(let a):
            out.append(0x5B) // [
            var first = true
            for v in a {
                if !first { out.append(0x2C) }
                first = false
                write(v, into: &out)
            }
            out.append(0x5D) // ]
        case .string(let s):
            writeQuoted(s, into: &out)
        case .number(let n):
            out.append(contentsOf: n.utf8)
        case .bool(let b):
            out.append(contentsOf: (b ? "true" : "false").utf8)
        case .null:
            out.append(contentsOf: "null".utf8)
        }
    }

    private static let hexDigits: [UInt8] = Array("0123456789abcdef".utf8)

    /// kotlinx `ESCAPE_STRINGS`: only bytes < 0x20, `"` and `\` are escaped; multi-byte UTF-8 sequences never contain
    /// bytes < 0x80, so they are copied raw (U+007F, U+2028, `/` raw).
    private static func writeQuoted(_ s: String, into out: inout [UInt8]) {
        out.append(0x22)
        for b in s.utf8 {
            switch b {
            case 0x22: out.append(0x5C); out.append(0x22)
            case 0x5C: out.append(0x5C); out.append(0x5C)
            case 0x09: out.append(0x5C); out.append(0x74) // \t
            case 0x08: out.append(0x5C); out.append(0x62) // \b
            case 0x0A: out.append(0x5C); out.append(0x6E) // \n
            case 0x0D: out.append(0x5C); out.append(0x72) // \r
            case 0x0C: out.append(0x5C); out.append(0x66) // \f
            case 0x00..<0x20:
                out.append(contentsOf: [0x5C, 0x75, 0x30, 0x30]) // \u00
                out.append(hexDigits[Int(b >> 4)])
                out.append(hexDigits[Int(b & 0x0F)])
            default:
                out.append(b)
            }
        }
        out.append(0x22)
    }

    private static func writePretty(_ value: BILJSONValue, indent: Int, into out: inout [UInt8]) {
        switch value {
        case .object(let o):
            if o.isEmpty {
                out.append(contentsOf: "{}".utf8)
                return
            }
            let sorted = o.entries.sorted { $0.key.utf16.lexicographicallyPrecedes($1.key.utf16) }
            out.append(contentsOf: "{\n".utf8)
            for (i, e) in sorted.enumerated() {
                out.append(contentsOf: [UInt8](repeating: 0x20, count: (indent + 1) * 2))
                writeQuoted(e.key, into: &out)
                out.append(contentsOf: ": ".utf8)
                writePretty(e.value, indent: indent + 1, into: &out)
                if i < sorted.count - 1 { out.append(0x2C) }
                out.append(0x0A)
            }
            out.append(contentsOf: [UInt8](repeating: 0x20, count: indent * 2))
            out.append(0x7D)
        case .array(let a):
            if a.isEmpty {
                out.append(contentsOf: "[]".utf8)
                return
            }
            out.append(contentsOf: "[\n".utf8)
            for (i, v) in a.enumerated() {
                out.append(contentsOf: [UInt8](repeating: 0x20, count: (indent + 1) * 2))
                writePretty(v, indent: indent + 1, into: &out)
                if i < a.count - 1 { out.append(0x2C) }
                out.append(0x0A)
            }
            out.append(contentsOf: [UInt8](repeating: 0x20, count: indent * 2))
            out.append(0x5D)
        default:
            write(value, into: &out)
        }
    }

    // MARK: - Parser (Android `StrictJson.Validator`, building the tree on the way; operates on UTF-16 units)

    private struct Parser {
        let s: [UInt16]
        let maxDepth: Int
        var pos = 0

        init(units: [UInt16], maxDepth: Int) {
            self.s = units
            self.maxDepth = maxDepth
        }

        private struct Bad: Error {}

        mutating func parseDocument() -> BILJSONValue? {
            do {
                skipWs()
                let v = try value(0)
                skipWs()
                return pos == s.count ? v : nil
            } catch {
                return nil
            }
        }

        private mutating func skipWs() {
            while pos < s.count {
                let c = s[pos]
                if c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D {
                    pos += 1
                } else {
                    return
                }
            }
        }

        private mutating func value(_ depth: Int) throws -> BILJSONValue {
            if depth > maxDepth || pos >= s.count { throw Bad() }
            switch s[pos] {
            case 0x7B: return .object(try object(depth + 1))      // {
            case 0x5B: return .array(try array(depth + 1))        // [
            case 0x22: return .string(try string())               // "
            case 0x74: try literal("true"); return .bool(true)    // t
            case 0x66: try literal("false"); return .bool(false)  // f
            case 0x6E: try literal("null"); return .null          // n
            default: return .number(try number())
            }
        }

        private mutating func object(_ depth: Int) throws -> BILJSONObject {
            pos += 1 // {
            var result = BILJSONObject()
            skipWs()
            if pos < s.count && s[pos] == 0x7D {
                pos += 1
                return result
            }
            while true {
                skipWs()
                if pos >= s.count || s[pos] != 0x22 { throw Bad() }
                let key = try string()
                if result.contains(key) { throw Bad() } // duplicate key (exact) in this object
                skipWs()
                if pos >= s.count || s[pos] != 0x3A { throw Bad() }
                pos += 1
                skipWs()
                let v = try value(depth)
                result.set(key, v)
                skipWs()
                if pos >= s.count { throw Bad() }
                switch s[pos] {
                case 0x2C: pos += 1
                case 0x7D:
                    pos += 1
                    return result
                default: throw Bad()
                }
            }
        }

        private mutating func array(_ depth: Int) throws -> [BILJSONValue] {
            pos += 1 // [
            var result = [BILJSONValue]()
            skipWs()
            if pos < s.count && s[pos] == 0x5D {
                pos += 1
                return result
            }
            while true {
                skipWs()
                result.append(try value(depth))
                skipWs()
                if pos >= s.count { throw Bad() }
                switch s[pos] {
                case 0x2C: pos += 1
                case 0x5D:
                    pos += 1
                    return result
                default: throw Bad()
                }
            }
        }

        /// Reads a string at `"` and returns its decoded value; a lone surrogate (only possible through `\u`) fails.
        private mutating func string() throws -> String {
            pos += 1 // "
            var out = [UInt16]()
            while true {
                if pos >= s.count { throw Bad() }
                let c = s[pos]
                pos += 1
                if c == 0x22 {
                    guard BILStrictJSON.isWellFormedUTF16(out) else { throw Bad() }
                    return String(decoding: out, as: UTF16.self)
                } else if c == 0x5C {
                    if pos >= s.count { throw Bad() }
                    let e = s[pos]
                    pos += 1
                    switch e {
                    case 0x22, 0x5C, 0x2F: out.append(e)        // " \ /
                    case 0x62: out.append(0x08)                 // b
                    case 0x66: out.append(0x0C)                 // f
                    case 0x6E: out.append(0x0A)                 // n
                    case 0x72: out.append(0x0D)                 // r
                    case 0x74: out.append(0x09)                 // t
                    case 0x75:                                  // u + exactly 4 hex digits
                        if pos + 4 > s.count { throw Bad() }
                        var code: UInt16 = 0
                        for k in 0..<4 {
                            guard let d = BILStrictJSON.hexValue(s[pos + k]) else { throw Bad() }
                            code = code << 4 | d
                        }
                        out.append(code)
                        pos += 4
                    default: throw Bad()
                    }
                } else if c < 0x20 {
                    throw Bad()
                } else {
                    out.append(c)
                }
            }
        }

        private mutating func literal(_ word: String) throws {
            let w = Array(word.utf16)
            if pos + w.count > s.count { throw Bad() }
            for k in 0..<w.count where s[pos + k] != w[k] {
                throw Bad()
            }
            pos += w.count
        }

        private static func isDigit(_ c: UInt16) -> Bool {
            return c >= 0x30 && c <= 0x39
        }

        private mutating func number() throws -> String {
            let start = pos
            if pos < s.count && s[pos] == 0x2D { pos += 1 } // -
            if pos >= s.count { throw Bad() }
            if s[pos] == 0x30 {
                pos += 1
            } else if s[pos] >= 0x31 && s[pos] <= 0x39 {
                while pos < s.count && Parser.isDigit(s[pos]) { pos += 1 }
            } else {
                throw Bad()
            }
            if pos < s.count && s[pos] == 0x2E { // .
                pos += 1
                let digits = pos
                while pos < s.count && Parser.isDigit(s[pos]) { pos += 1 }
                if pos == digits { throw Bad() }
            }
            if pos < s.count && (s[pos] == 0x65 || s[pos] == 0x45) { // e E
                pos += 1
                if pos < s.count && (s[pos] == 0x2B || s[pos] == 0x2D) { pos += 1 }
                let digits = pos
                while pos < s.count && Parser.isDigit(s[pos]) { pos += 1 }
                if pos == digits { throw Bad() }
            }
            if pos == start { throw Bad() }
            return String(decoding: s[start..<pos], as: UTF16.self)
        }
    }

    private static func hexValue(_ c: UInt16) -> UInt16? {
        switch c {
        case 0x30...0x39: return c - 0x30
        case 0x41...0x46: return c - 0x41 + 10
        case 0x61...0x66: return c - 0x61 + 10
        default: return nil
        }
    }

    /// `true` when every high surrogate is followed by a low surrogate and no low surrogate stands alone.
    private static func isWellFormedUTF16(_ units: [UInt16]) -> Bool {
        var i = 0
        while i < units.count {
            let u = units[i]
            if u >= 0xD800 && u <= 0xDBFF {
                guard i + 1 < units.count, units[i + 1] >= 0xDC00, units[i + 1] <= 0xDFFF else { return false }
                i += 2
            } else if u >= 0xDC00 && u <= 0xDFFF {
                return false
            } else {
                i += 1
            }
        }
        return true
    }
}
