//  PPCoreTests.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Port of the app harness suite `scripts/public-protocol/tests/core` (main.swift) to XCTest.
//
//  main.swift — tests/core (WP1): strict JSON, typed readers, Kotlin text, codecs, texts, error mapping, refusal
//  bounds, log hygiene, concurrency primitives, engine contract. Self-contained in Wave 1 (own `t` helper and stubs).
//  Fixtures: PUB_VOCAB (engine_vocabulary.json) and PUB_STRINGS_JSON (public_protocol_strings.json), resolved by run.sh.
//  Output ends with "core: N ok, M FAIL".
//

import Foundation
import XCTest
@testable import OwnbitCore

/// The suite namespace (harness helpers are its static members).
enum PPCoreSuite: PPSuite {}

final class PPCoreTests: XCTestCase {
    func testCore() throws {
        try ppRunSuite("core") { try PPCoreSuite.run() }
    }
}

extension PPCoreSuite {

    // MARK: - Helpers (the harness's own mini kit is PPSuite's `t` / `eq` / `section` / `runAsync`)

    /// Failure text of a value: JSON trees print only their kind (C-KEY-5 redaction), so show their serialization.
    static func show(_ x: Any) -> String {
        if let v = x as? BILJSONValue { return BILStrictJSON.serialize(v) }
        if let o = x as? BILJSONObject { return BILStrictJSON.serialize(o) }
        return "\(x)"
    }

    /// A synchronous, thread-blocking sleep (stands in for a stuck JavaScriptCore call inside async work).
    static func blockingSleep(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    final class Box<T> {
        private let lock = NSLock()
        private var v: T
        init(_ v: T) { self.v = v }
        var value: T {
            get { lock.lock(); defer { lock.unlock() }; return v }
            set { lock.lock(); v = newValue; lock.unlock() }
        }
        func mutate(_ f: (inout T) -> Void) {
            lock.lock(); f(&v); lock.unlock()
        }
    }

    static func parse(_ s: String) -> BILJSONValue? { return BILStrictJSON.parse(s) }
    static func obj(_ s: String) -> BILJSONObject? { return BILStrictJSON.parseObject(s) }
    static func ser(_ v: BILJSONValue) -> String { return BILStrictJSON.serialize(v) }
    static func scalars(_ s: String) -> [UInt32] { return s.unicodeScalars.map { $0.value } }

    /// The harness read `PUB_VOCAB` (engine_vocabulary.json) and `PUB_STRINGS_JSON` (the app's strings JSON) from the
    /// environment; the package ships the vocabulary as a fixture and no strings table.
    static func loadJSON(_ envName: String) -> BILJSONValue? {
        guard envName == "PUB_VOCAB" else { return nil }
        return BILStrictJSON.parse(utf8: [UInt8](fixture("engine_vocabulary.json")), options: .engine)
    }

    /// The harness's `bil_localized` / `bil_ui_localized` stubs (core/Stubs.swift) as the package's localizer hook:
    /// `PublicProtocol.*` / `SecurityCenter.*` / `SendC.*` keys from `table` (else the key), any other key → "UI(<key>)".
    enum CoreTestStrings {
        static var table: [String: String] = [:] {
            didSet { install() }
        }

        static func install() {
            let current = table
            BILPublicText.localize = { key in
                let routed = ["PublicProtocol.", "SecurityCenter.", "SendC."].contains { key.hasPrefix($0) }
                return routed ? (current[key] ?? key) : "UI(" + key + ")"
            }
        }
    }

    /// The harness's `bil_errorPrint` capture: the `BILPublicLog` lines since the last call.
    enum CoreTestLog {
        static func take() -> [String] {
            let lines = PPStubLog.lines.map { $0.hasPrefix("error: ") ? String($0.dropFirst(7)) : $0 }
            PPStubLog.reset()
            return lines
        }
    }

    /// The English templates of the app's `PublicProtocol.strings` that the text checks below format (test data only; the
    /// package ships no strings table). `%N$s` → `%N$@`, `%N$d` → `%N$ld` as the app's generator writes them.
    static let englishTemplates: [String: String] = [
        "PublicProtocol.err.integrity": "The request changed or is inconsistent. Nothing was signed. Scan it again.",
        "PublicProtocol.err.prevoutConflict": "Input %1$ld claims a different amount than a request this device already signed for the same coins. This may be an attempt to make you pay a huge fee, so Ownbit won't sign it. Create a new transaction in your other wallet.",
        "PublicProtocol.err.tronOwner": "This transaction is for account %1$@, not this wallet's address.",
        "PublicProtocol.err.tronlinkMulti": "This TronLink request holds %1$ld transactions. Ownbit signs only one transaction per request.",
    ]

    // MARK: - Strict JSON: accept / reject (R4 §5.3, Android OtherWalletQrFormatsTest)

    actor CoreFakeEngine: BILPublicSignerEngining {
        private var nextSession: Int64 = 0
        func capabilities() async throws -> BILJSONObject { return BILJSONObject([("v", .int(1))]) }
        func derivePublicAddresses(publicIndex: BILJSONObject, chain: String, profile: String?, start: Int, count: Int) async throws -> BILJSONObject { return BILJSONObject() }
        func createPublicPairing(publicIndex: BILJSONObject, chain: String, profile: String?, outputMode: String?, index: Int) async throws -> BILJSONObject { return BILJSONObject() }
        func releasePairingContext() async {}
        func derivePublicIndex(seedHex: String, tronScheme: String?, tronAddressCount: Int?) async throws -> BILJSONObject {
            throw BILPublicSignerRefusal(code: "seed", engineMessage: "fake")
        }
        func refreshPublicIndex(publicIndex: BILJSONObject, tronScheme: String, tronAddressCount: Int?) async throws -> BILJSONObject { return publicIndex }
        func signPlanTask(request: BILJSONObject, plan: BILJSONObject, taskId: String, seedHex: String,
                          riskAcknowledged: Bool, previousResult: BILJSONObject?) async throws -> BILJSONObject {
            throw BILPublicSignerFailure.engineUnavailable
        }
        func decodePayload(_ payload: String) async throws -> BILJSONObject { return BILJSONObject() }
        func reviewAndResolve(request: BILJSONObject, wallets: [BILJSONObject]) async throws -> BILPublicReviewAndPlan {
            return BILPublicReviewAndPlan(review: request, plan: BILJSONObject())
        }
        func encodeResponse(request: BILJSONObject, result: BILJSONObject) async throws -> BILJSONObject { return result }
        func openScan() async throws -> BILPublicScanHandle {
            nextSession += 1
            return BILPublicScanHandle(sessionId: nextSession)
        }
        func scanAdd(_ handle: BILPublicScanHandle, frame: String) async throws -> BILJSONObject {
            throw BILPublicSignerRefusal(code: BILPublicSignerRefusal.scanCode, engineMessage: BILPublicSignerRefusal.scanMessage)
        }
        func closeScan(_ handle: BILPublicScanHandle) async {}
        func isAvailable() async -> Bool { return true }
    }

    /// The harness main.swift (nonisolated top-level code, as in the harness).
    static func run() throws {
        section("strict JSON accept / reject")
        do {
            let accepted = obj("{\"a\":1,\"b\":[true,false,null],\"c\":{\"d\":\"é\\/\"}}")
            t(accepted != nil, "Android accepted sample")
            eq(accepted?.obj("c")?.str("d") ?? "-", "é/", "escaped slash decoded")
            t(obj("{\"a\":1,\"a\":2}") == nil, "duplicate key")
            t(obj("{\"a\":{\"b\":1,\"b\":1}}") == nil, "nested duplicate key")
            t(obj("{\"a\":1,\"\\u0061\":2}") == nil, "escaped twin is the same key")
            t(obj("{\"a\":1,}") == nil, "trailing comma")
            t(obj("{a:1}") == nil, "unquoted key")
            t(obj("{'a':1}") == nil, "single quotes")
            t(obj("{\"a\":NaN}") == nil, "NaN")
            t(obj("{\"a\":01}") == nil, "leading zero")
            t(obj("{\"a\":\"x\ty\"}") == nil, "raw control character")
            t(obj("{\"a\":1} {\"b\":2}") == nil, "two values")
            t(obj("[1]") == nil && parse("[1]") != nil, "not an object (but a value)")
            t(obj(String(repeating: "[", count: 40) + String(repeating: "]", count: 40)) == nil, "too deep")
            t(parse(String(repeating: "[", count: 40) + String(repeating: "]", count: 40)) == nil, "too deep (parse)")
            // Depth rule exactly as Android's Validator: n nested containers around a scalar are accepted iff n <= 32;
            // the innermost container being empty allows one more level (its members are never parsed).
            t(parse(String(repeating: "[", count: 32) + "1" + String(repeating: "]", count: 32)) != nil, "32 levels + scalar")
            t(parse(String(repeating: "[", count: 33) + "1" + String(repeating: "]", count: 33)) == nil, "33 levels + scalar")
            t(parse(String(repeating: "[", count: 33) + String(repeating: "]", count: 33)) != nil, "33 empty levels (Android quirk)")
            t(parse(String(repeating: "[", count: 34) + String(repeating: "]", count: 34)) == nil, "34 empty levels")
            t(BILStrictJSON.parse(String(repeating: "[", count: 64) + "1" + String(repeating: "]", count: 64), options: .engine) != nil, "engine: 64")
            t(BILStrictJSON.parse(String(repeating: "[", count: 65) + "1" + String(repeating: "]", count: 65), options: .engine) == nil, "engine: 65")
            t(parse(String(repeating: "{\"a\":", count: 32) + "1" + String(repeating: "}", count: 32)) != nil, "32 nested objects")
            t(parse(String(repeating: "{\"a\":", count: 33) + "1" + String(repeating: "}", count: 33)) == nil, "33 nested objects")

            let rejects = ["", " ", "{", "}", "{\"a\":1}x", "{\"a\":tru}", "{\"a\":truex}", "{\"a\":-}", "{\"a\":1.}", "{\"a\":.5}",
                           "{\"a\":+1}", "{\"a\":1e}", "{\"a\":1e+}", "{\"a\":\"\\x\"}", "{\"a\":\"\\u12\"}", "{\"a\":\"\\u+123\"}",
                           "{\"a\":\"\\u12G4\"}", "{\"a\":\"abc", "{\"a\" 1}", "{,}", "[1,]", "[,1]", "{\"a\":1,,\"b\":2}",
                           "\u{FEFF}{}", "{\"a\":1}\u{00A0}", "\u{0B}{}", "{\"a\":True}", "{\"a\":undefined}", "{\"a\":Infinity}",
                           "{\"a\":-01}", "{\"a\":0x10}", "//c\n{}", "{\"a\":\"\u{0}\"}", "{\"a\":\"\u{1F}\"}", "[1 2]", "{\"a\"}",
                           "{\"a\":}", "\"abc", "nul", "[\"\\\"]"]
            for r in rejects {
                t(parse(r) == nil, "reject \(scalars(r).prefix(12))")
            }
            let accepts: [(String, BILJSONValue)] = [
                (" \t\n\r{\"a\" : [ 1 , 2 ] }\r\n", .object(BILJSONObject([("a", .array([.number("1"), .number("2")]))]))),
                ("true", .bool(true)), ("false", .bool(false)), ("null", .null), ("-0", .number("-0")), ("1E+2", .number("1E+2")),
                ("-1.5e-3", .number("-1.5e-3")), ("0.0", .number("0.0")), ("\"\\u00e9\"", .string("é")), ("\"\\u00E9\"", .string("é")),
                ("\"\\uD83D\\uDE00\"", .string("😀")), ("\"😀\"", .string("😀")), ("[]", .array([])), ("{}", .object(BILJSONObject())),
                ("\"\\b\\f\\n\\r\\t\\\"\\\\\\/\"", .string("\u{8}\u{C}\n\r\t\"\\/")), ("\"\u{7F}\u{2028}\"", .string("\u{7F}\u{2028}")),
            ]
            for (text, expected) in accepts {
                let v = parse(text)
                t(v != nil && v! == expected, "accept \(scalars(text).prefix(12))")
            }
        }

        section("lone surrogates (D-27)")
        do {
            t(obj("{\"a\":\"\\uD800\"}") == nil, "lone high")
            t(obj("{\"a\":\"\\uDC00\"}") == nil, "lone low")
            t(obj("{\"a\":\"\\uD800x\"}") == nil, "high + BMP")
            t(obj("{\"a\":\"\\uDE00\\uD83D\"}") == nil, "reversed pair")
            t(obj("{\"\\uD800\":1}") == nil, "lone surrogate key")
            t(obj("{\"a\":\"\\uD83D\\uDE00\"}")?.str("a") == "😀", "valid escaped pair")
            t(obj("{\"a\":\"\\uD83D😀\"}") == nil, "escaped high + raw pair")
        }

        section("number literals and round trips")
        do {
            let text = "{\"amount\":9007199254740993,\"x\":1.50}"
            let o = obj(text)
            eq(o.map { BILStrictJSON.serialize($0) } ?? "-", text, "literal round trip")
            eq(o?["amount"]?.numberLiteral ?? "-", "9007199254740993", "big literal kept")
            eq(o?["x"]?.numberLiteral ?? "-", "1.50", "fraction literal kept")
            let tlPhoto = "{\"amount\":0,\"address\":\"TMTjucQ73f32Yw4Xx8Gm1dH1mdFrFjn9Lb\",\"amountStr\":\"0\",\"type\":99,\"hexList\":[\"0a1a5a18221654726f6e4c696e6b437573746f6d436f6e7472616374\"]}"
            let tl = obj(tlPhoto)
            eq(tl?.keys ?? [], ["amount", "address", "amountStr", "type", "hexList"], "TronLink owner capture key order")
            eq(tl.map { BILStrictJSON.serialize($0) } ?? "-", tlPhoto, "TronLink owner capture round trip")
            let gson = "{\"address\":\"TUEZSdKsoDHQMeZwihtdoBiN46zxhGWYdH\",\"cN\":0,\"hexList\":[\"0a215a1f221d436f6c6457616c6c65744f776e6572566572696679436f6e7472616374\"],\"tN\":0,\"type\":99}"
            eq(obj(gson).map { BILStrictJSON.serialize($0) } ?? "-", gson, "Android Gson shape round trip")
            // Re-serialisation of decoded content (kotlinx): escapes are normalised.
            eq(obj("{\"a\":\"\\/\\u00e9\\n\\u001F\"}").map { BILStrictJSON.serialize($0) } ?? "-", "{\"a\":\"/é\\n\\u001f\"}", "re-serialised escapes")
            eq(ser(.object(BILJSONObject([("b", .number("1")), ("a", .array([.null, .bool(false), .string("x")]))]))),
               "{\"b\":1,\"a\":[null,false,\"x\"]}", "compact, insertion order")
            eq(ser(.int(Int64.min)), "-9223372036854775808", "int(Int64.min)")
            eq(BILJSONValue.int(UInt8(7)), .number("7"), "int(UInt8)")
        }

        section("kotlinx escaping table")
        do {
            var expected = [String]()
            for c in 0..<0x20 {
                switch c {
                case 0x08: expected.append("\\b")
                case 0x09: expected.append("\\t")
                case 0x0A: expected.append("\\n")
                case 0x0C: expected.append("\\f")
                case 0x0D: expected.append("\\r")
                default: expected.append(String(format: "\\u%04x", c))
                }
            }
            for c in 0..<0x20 {
                let s = String(UnicodeScalar(UInt8(c)))
                eq(BILStrictJSON.quote(s), "\"" + expected[c] + "\"", "escape U+\(String(format: "%04X", c))")
            }
            eq(BILStrictJSON.quote("\u{1F}"), "\"\\u001f\"", "\\u001f lower-case")
            eq(BILStrictJSON.quote("/"), "\"/\"", "slash raw")
            eq(BILStrictJSON.quote("\u{2028}\u{2029}"), "\"\u{2028}\u{2029}\"", "U+2028 raw")
            eq(BILStrictJSON.quote("\u{7F}"), "\"\u{7F}\"", "U+007F raw")
            eq(BILStrictJSON.quote("\"\\"), "\"\\\"\\\\\"", "quote and backslash")
            eq(BILStrictJSON.quote("é😀中"), "\"é😀中\"", "non-ASCII raw")
            eq(BILStrictJSON.quote(""), "\"\"", "empty")
        }

        section("exact scalar equality and keys")
        do {
            let pre = "\u{E9}", dec = "e\u{301}"
            t(pre == dec, "(Swift itself treats them as equal)")
            t(BILJSONValue.string(pre) != BILJSONValue.string(dec), "é precomposed ≠ decomposed")
            let o = obj("{\"\u{E9}\":1,\"e\u{301}\":2}")
            eq(o?.count ?? 0, 2, "both keys kept (distinct in Kotlin)")
            eq(o?[pre]?.numberLiteral ?? "-", "1", "exact lookup precomposed")
            eq(o?[dec]?.numberLiteral ?? "-", "2", "exact lookup decomposed")
            t(obj("{\"a\":1,\"b\":2}") == obj("{\"b\":2,\"a\":1}"), "objects compare as maps")
            t(parse("1") != parse("1.0"), "1 ≠ 1.0")
            t(parse("\"1\"") != parse("1"), "string ≠ number")
            t(parse("[1,2]") != parse("[2,1]"), "arrays ordered")
            t(obj("{\"a\":1}") != obj("{\"a\":1,\"b\":2}"), "different sizes")
            // A large object (index path) still detects duplicates and looks up exactly.
            var big = "{"
            for i in 0..<100 { big += "\"k\(i)\":\(i)," }
            eq(obj(big + "\"k50\":0}") == nil, true, "duplicate in a 101-key object")
            let bigObj = obj(big + "\"\(dec)\":1,\"\(pre)\":2}")
            eq(bigObj?.count ?? 0, 102, "102 keys")
            eq(bigObj?[pre]?.numberLiteral ?? "-", "2", "indexed exact lookup")
            eq(bigObj?["k99"]?.numberLiteral ?? "-", "99", "indexed lookup")
        }

        section("BILJSONObject mutation")
        do {
            var o = BILJSONObject([("a", .number("1")), ("b", .number("2")), ("c", .number("3"))])
            o.set("b", .string("x"))
            eq(o.keys, ["a", "b", "c"], "set keeps position")
            o["d"] = .null
            eq(o.keys, ["a", "b", "c", "d"], "set appends")
            o["a"] = nil
            eq(o.keys, ["b", "c", "d"], "nil removes")
            o.remove("zz")
            eq(o.count, 3, "remove absent is a no-op")
            let p = o.appending("b", .bool(true)).appending("e", .bool(false))
            eq(p.keys, ["b", "c", "d", "e"], "appending = put")
            eq(o["b"], .string("x"), "appending does not mutate")
            t(p.contains("e") && !p.contains("E"), "contains exact")
            var many = BILJSONObject()
            for i in 0..<40 { many.set("k\(i)", .int(i)) }
            many.remove("k0")
            many.set("k5", .string("five"))
            many.set("new", .null)
            eq(many.keys.first ?? "-", "k1", "large: remove first")
            eq(many["k5"], .string("five"), "large: set keeps value")
            eq(many.keys.last ?? "-", "new", "large: append")
            eq(many.count, 40, "large: count")
            for i in 1..<40 { t(many.contains("k\(i)"), "large contains k\(i)") }
            t(BILJSONObject().isEmpty, "isEmpty")
        }

        section("displayText / prettySorted / utf8")
        do {
            eq(BILJSONValue.string("a\"b").displayText, "a\"b", "string as is")
            eq(BILJSONValue.null.displayText, "", "null empty")
            eq(BILJSONValue.number("1.50").displayText, "1.50", "number literal")
            eq(BILJSONValue.bool(true).displayText, "true", "bool")
            eq(parse("{\"a\":[1,\"x\"]}")!.displayText, "{\"a\":[1,\"x\"]}", "object compact")
            let pretty = BILStrictJSON.prettySorted(parse("{\"b\":1,\"a\":{},\"B\":[],\"😀\":[1,{\"z\":null,\"y\":\"q\"}],\"\u{FF5E}\":true}")!)
            let expected = "{\n  \"B\": [],\n  \"a\": {},\n  \"b\": 1,\n  \"😀\": [\n    1,\n    {\n      \"y\": \"q\",\n      \"z\": null\n    }\n  ],\n  \"\u{FF5E}\": true\n}"
            eq(pretty, expected, "prettySorted (UTF-16 order: U+1F600 before U+FF5E)")
            eq(BILStrictJSON.parse(utf8: Array("{\"a\":\"é\"}".utf8))?.objectValue?.str("a") ?? "-", "é", "utf8 valid")
            t(BILStrictJSON.parse(utf8: [0x7B, 0xFF, 0x7D]) == nil, "utf8 invalid byte")
            t(BILStrictJSON.parse(utf8: [0x22, 0xC0, 0xAF, 0x22]) == nil, "utf8 overlong")
            t(BILStrictJSON.parse(utf8: [0x22, 0xED, 0xA0, 0x80, 0x22]) == nil, "utf8 encoded surrogate")
            t(BILStrictJSON.parse(utf8: [0x22, 0xE2, 0x82, 0x22]) == nil, "utf8 truncated sequence")
            t(BILStrictJSON.parse(utf8: [0x22, 0xEF, 0xBF, 0xBD, 0x22]) == .string("\u{FFFD}"), "utf8 literal U+FFFD is valid")
        }

        section("JSON trees never print their content (C-KEY-5)")
        do {
            let secret = "5eed5eed5eed"
            let o = BILJSONObject([("seedHex", .string(secret)), ("n", .number("123456789")), ("list", .array([.string(secret)]))])
            let v = BILJSONValue.object(o)
            eq("\(v)", "BILJSONValue(object)", "interpolation shows the kind only")
            eq(String(describing: o), "BILJSONObject(3 keys)", "object description: key count only")
            eq(String(reflecting: v), "BILJSONValue(object)", "debugDescription")
            eq(String(reflecting: o), "BILJSONObject(3 keys)", "object debugDescription")
            eq([BILJSONValue.string(secret), .number("7"), .bool(true), .null, .array([])].map { "\($0)" },
               ["BILJSONValue(string)", "BILJSONValue(number)", "BILJSONValue(bool)", "BILJSONValue(null)", "BILJSONValue(array)"],
               "every kind")
            var dumped = ""
            dump(v, to: &dumped)
            dump(o, to: &dumped)
            let nested = BILPublicReviewAndPlan(review: o, plan: o)
            let printed = [dumped, "\(nested)", String(reflecting: nested), "\([v])", "\(Optional(v) as Any)",
                           "\(["k": v])", "\(Mirror(reflecting: v).children.count)"]
            t(printed.allSatisfy { !$0.contains(secret) && !$0.contains("seedHex") && !$0.contains("123456789") },
              "dump / nested / collections / optionals do not show keys or values")
            eq(Mirror(reflecting: o).children.count, 0, "no reflected children")
            t(BILStrictJSON.serialize(v).contains(secret), "explicit serialization still has the content")
        }

        section("real fixtures parse like Foundation")
        do {
            // The vocabulary (119 KB) and the strings JSON (572 KB, all scripts): every string / key equals JSONSerialization's.
            func compare(_ mine: BILJSONValue, _ theirs: Any) -> Bool {
                switch mine {
                case .object(let o):
                    guard let d = theirs as? [String: Any], d.count == o.count else { return false }
                    for e in o.entries {
                        guard let v = d[e.key], compare(e.value, v) else { return false }
                    }
                    return true
                case .array(let a):
                    guard let b = theirs as? [Any], b.count == a.count else { return false }
                    for i in 0..<a.count where !compare(a[i], b[i]) { return false }
                    return true
                case .string(let s):
                    guard let b = theirs as? String else { return false }
                    return BILJSONExact.equal(s, b)
                case .number(let n):
                    guard let b = theirs as? NSNumber, let d = Double(n) else { return false }
                    return b.doubleValue == d
                case .bool(let v):
                    guard let b = theirs as? NSNumber else { return false }
                    return b.boolValue == v
                case .null:
                    return theirs is NSNull
                }
            }
            for env in ["PUB_VOCAB"] {
                let data = fixture("engine_vocabulary.json")
                let mine = BILStrictJSON.parse(utf8: [UInt8](data), options: .engine)
                let theirs = try? JSONSerialization.jsonObject(with: data, options: [])
                t(mine != nil && theirs != nil && compare(mine!, theirs!), "\(env): same tree as JSONSerialization")
                let text = String(decoding: data, as: UTF8.self)
                let again = mine.map { BILStrictJSON.parse(BILStrictJSON.serialize($0), options: .engine) }
                t(again != nil && again! == mine, "\(env): serialize → parse is identity")
                t(text.utf8.count == data.count, "\(env): utf8")
            }
        }

        // MARK: - Typed readers (Android EngineJson.kt)

        section("typed readers")
        do {
            let o = obj("{\"a\":1,\"b\":1.0,\"c\":true,\"d\":\"1\",\"e\":2147483648,\"f\":-2147483648,\"g\":9223372036854775807,\"h\":9223372036854775808,\"i\":1e3,\"j\":-0,\"k\":null,\"l\":[\"x\",\"y\"],\"m\":[\"x\",1],\"n\":[1,2],\"o\":[1,2.0],\"p\":[2147483648],\"q\":{\"r\":1},\"s\":-9223372036854775808,\"t\":-9223372036854775809}")!
            eq(o.int("a"), 1, "int 1")
            t(o.int("b") == nil && o.long("b") == nil, "1.0 is not an int")
            t(o.int("c") == nil && o.long("c") == nil, "true is not an int")
            t(o.int("d") == nil, "\"1\" is not an int")
            t(o.int("e") == nil, "2^31 not Int32")
            eq(o.long("e"), 2147483648, "long 2^31")
            eq(o.int("f"), -2147483648, "Int32.min")
            eq(o.long("g"), Int64.max, "Int64.max")
            t(o.long("h") == nil, "above Int64")
            eq(o.long("s"), Int64.min, "Int64.min")
            t(o.long("t") == nil, "below Int64")
            t(o.long("i") == nil, "exponent literal is not an integer (design §3.1)")
            eq(o.long("j"), 0, "-0")
            t(o.long("k") == nil && o.str("k") == nil && o.bool("k") == nil, "null is nothing")
            eq(o.bool("c"), true, "bool")
            t(o.bool("a") == nil, "1 is not a bool")
            eq(o.str("d"), "1", "str")
            t(o.str("a") == nil, "number is not a string")
            eq(o.strings("l") ?? [], ["x", "y"], "strings")
            t(o.strings("m") == nil, "mixed strings → nil")
            eq(o.ints("n") ?? [], [1, 2], "ints")
            t(o.ints("o") == nil, "2.0 in ints → nil")
            t(o.ints("p") == nil, "2^31 in ints → nil")
            t(o.obj("q")?.int("r") == 1 && o.obj("l") == nil && o.arr("q") == nil && o.arr("l")?.count == 2, "obj / arr exact types")
            t(o.str("missing") == nil && o.int("missing") == nil, "missing")
            let ints: [(String, Int64?)] = [("0", 0), ("-0", 0), ("00", 0), ("7", 7), ("-7", -7), ("9223372036854775807", Int64.max),
                ("-9223372036854775808", Int64.min), ("9223372036854775808", nil), ("-9223372036854775809", nil),
                ("99999999999999999999", nil), ("", nil), ("-", nil), ("+1", nil), (" 1", nil), ("1 ", nil), ("12a", nil),
                ("1.0", nil), ("1e3", nil), ("１", nil)]
            for (lit, expected) in ints {
                t(BILEngineJSON.integerValue(lit) == expected, "integerValue \(lit.debugDescription)")
            }
            t(BILEngineJSON.isHex("abCD", bytes: 2), "isHex mixed case")
            t(!BILEngineJSON.isHex("abc", bytes: 2), "isHex wrong length")
            t(!BILEngineJSON.isHex("0xab", bytes: 2), "isHex prefix")
            t(!BILEngineJSON.isHex(nil, bytes: 1), "isHex nil")
            t(BILEngineJSON.isHex("", bytes: 0), "isHex empty (Android)")
            t(!BILEngineJSON.isHex("zz", bytes: 1), "isHex non-hex")
            t(!BILEngineJSON.isHex("１２", bytes: 1), "isHex full-width digits")
            t(BILEngineJSON.isLowerHex64(String(repeating: "a1", count: 32)), "lowerHex64")
            t(!BILEngineJSON.isLowerHex64(String(repeating: "A1", count: 32)), "lowerHex64 upper")
            t(!BILEngineJSON.isLowerHex64(String(repeating: "a", count: 63)), "lowerHex64 63")
            eq(BILMalformedEngineResult(what: "plan.version").description, "Malformed engine result: plan.version", "malformed description")
            do {
                try BILEngineJSON.ensure(false, "frames")
                t(false, "ensure throws")
            } catch let e as BILMalformedEngineResult {
                eq(e.what, "frames", "ensure what")
            } catch {
                t(false, "ensure type")
            }
            t((try? BILEngineJSON.ensure(true, "x")) != nil, "ensure passes")
        }

        // MARK: - Kotlin text (R4 §3)

        section("Kotlin whitespace / trim / lines / split / prefix / regex")
        do {
            let yes: [UInt16] = [0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x1C, 0x1D, 0x1E, 0x1F, 0x20, 0xA0, 0x1680, 0x2000, 0x2007, 0x200A,
                                 0x2028, 0x2029, 0x202F, 0x205F, 0x3000]
            let no: [UInt16] = [0x85, 0x180E, 0x200B, 0xFEFF, 0x61, 0x1B, 0x08, 0x00, 0x7F, 0x2060, 0xD800]
            for u in yes { t(BILKotlinText.isWhitespace(u), "whitespace U+\(String(format: "%04X", u))") }
            for u in no { t(!BILKotlinText.isWhitespace(u), "not whitespace U+\(String(format: "%04X", u))") }
            // Exhaustive over the BMP against Unicode data: Zs ∪ {U+0009–000D, U+001C–001F, U+2028, U+2029}.
            var mismatches = 0
            for u in 0...0xFFFF {
                var expected = (0x09...0x0D).contains(u) || (0x1C...0x1F).contains(u) || u == 0x2028 || u == 0x2029
                if let sc = Unicode.Scalar(UInt32(u)), sc.properties.generalCategory == .spaceSeparator { expected = true }
                if BILKotlinText.isWhitespace(UInt16(u)) != expected { mismatches += 1 }
            }
            eq(mismatches, 0, "exhaustive BMP whitespace set")
            eq(BILKotlinText.trim("\u{1C}\u{2028} a b \u{3000}\t"), "a b", "trim Kotlin set")
            eq(scalars(BILKotlinText.trim("\u{85}x\u{85}")), [0x85, 0x78, 0x85], "trim keeps U+0085")
            eq(scalars(BILKotlinText.trim(" \u{301}x")), [0x301, 0x78], "trim exact scalars (combining mark kept)")
            eq(BILKotlinText.trim(""), "", "trim empty")
            eq(BILKotlinText.trim(" \n "), "", "trim all whitespace")
            eq(BILKotlinText.lines("a\r\nb\nc\rd"), ["a", "b", "c", "d"], "lines CRLF / LF / CR")
            eq(BILKotlinText.lines("a\n"), ["a", ""], "lines trailing empty")
            eq(BILKotlinText.lines(""), [""], "lines empty")
            eq(BILKotlinText.lines("\r\n\r\n"), ["", "", ""], "lines CRLF CRLF")
            eq(BILKotlinText.lines("\n\r"), ["", "", ""], "lines LF CR")
            eq(BILKotlinText.lines("a\u{2028}b\u{85}c"), ["a\u{2028}b\u{85}c"], "lines ignore U+2028 / U+0085")
            eq(BILKotlinText.split("a,b,,", separator: ","), ["a", "b", "", ""], "split keeps empties")
            eq(BILKotlinText.split("abc", separator: ","), ["abc"], "split no match")
            eq(BILKotlinText.split("a&&&b&&&", separator: "&&&"), ["a", "b", ""], "split multi-char")
            eq(BILKotlinText.split("", separator: ","), [""], "split empty")
            eq(BILKotlinText.split("aaaa", separator: "aa"), ["", "", ""], "split non-overlapping")
            eq(BILKotlinText.split("xe\u{301}y", separator: "\u{E9}").count, 1, "split exact (no canonical match)")
            eq(BILKotlinText.length("😀a"), 3, "length UTF-16")
            eq(BILKotlinText.prefix("ab😀", utf16: 3), "ab", "prefix drops a cut pair")
            eq(BILKotlinText.prefix("ab😀", utf16: 4), "ab😀", "prefix whole pair")
            eq(BILKotlinText.prefix("abc", utf16: 0), "", "prefix 0")
            eq(BILKotlinText.prefix("abc", utf16: 10), "abc", "prefix longer")
            let alt = try! NSRegularExpression(pattern: "a|ab")
            t(BILKotlinText.wholeMatch(alt, "ab") != nil, "wholeMatch backtracks into alternatives")
            let digits = try! NSRegularExpression(pattern: "^[0-9]+$")
            t(BILKotlinText.wholeMatch(digits, "123\n") == nil, "wholeMatch rejects a final newline")
            t(BILKotlinText.wholeMatch(digits, "123") != nil, "wholeMatch")
            let letters = try! NSRegularExpression(pattern: "([a-z]+)-([0-9]+)")
            t(BILKotlinText.wholeMatch(letters, "abc1") == nil, "wholeMatch partial")
            let m = BILKotlinText.wholeMatch(letters, "ab-12")
            eq(m.map { ("ab-12" as NSString).substring(with: $0.range(at: 2)) } ?? "-", "12", "wholeMatch keeps capture groups")
            t(BILKotlinText.wholeMatch(letters, "😀ab-12") == nil, "wholeMatch UTF-16 range")
            // Comment mode: a trailing `# comment` must not swallow the anchor (review WP1 #5).
            let commented = try! NSRegularExpression(pattern: "a | ab   # alternatives (note)", options: [.allowCommentsAndWhitespace])
            t(BILKotlinText.wholeMatch(commented, "ab") != nil, "wholeMatch: comment-mode option + trailing comment")
            t(BILKotlinText.wholeMatch(commented, "a") != nil, "wholeMatch: comment mode, first alternative")
            t(BILKotlinText.wholeMatch(commented, "abc") == nil && BILKotlinText.wholeMatch(commented, "ab\n") == nil,
              "wholeMatch: comment mode still whole-string")
            let inlineX = try! NSRegularExpression(pattern: "(?x) [0-9]+ - [a-z]+ # digits, dash, letters")
            t(BILKotlinText.wholeMatch(inlineX, "12-ab") != nil, "wholeMatch: inline (?x) + trailing comment")
            t(BILKotlinText.wholeMatch(inlineX, "12 - ab") == nil && BILKotlinText.wholeMatch(inlineX, "12-ab\n") == nil,
              "wholeMatch: inline (?x) whole-string, pattern spaces ignored")
            let xNoComment = try! NSRegularExpression(pattern: "a | ab", options: [.allowCommentsAndWhitespace])
            t(BILKotlinText.wholeMatch(xNoComment, "ab") != nil && BILKotlinText.wholeMatch(xNoComment, "a b") == nil,
              "wholeMatch: comment mode without a comment")
            let literalHash = try! NSRegularExpression(pattern: "a#b|c")
            t(BILKotlinText.wholeMatch(literalHash, "a#b") != nil && BILKotlinText.wholeMatch(literalHash, "c") != nil,
              "wholeMatch: '#' is literal outside comment mode")
        }

        // MARK: - Codecs

        section("hex / base58check / TRON / base64")
        do {
            eq(BILPublicHex.decode("00ff") ?? [], [0, 255], "hex decode")
            t(BILPublicHex.decode("0xff") == nil, "hex prefix refused")
            t(BILPublicHex.decode("abc") == nil, "hex odd")
            t(BILPublicHex.decode(" ff") == nil, "hex whitespace")
            t(BILPublicHex.decode("gg") == nil, "hex non-hex")
            eq(BILPublicHex.decode("FF") ?? [], [255], "hex upper")
            eq(BILPublicHex.decode("") ?? [1], [], "hex empty")
            eq(BILPublicHex.decodeOptional0x("0Xff") ?? [], [255], "0X prefix")
            eq(BILPublicHex.decodeOptional0x("ff") ?? [], [255], "no prefix")
            t(BILPublicHex.decodeOptional0x("0x0xff") == nil, "only one prefix dropped")
            eq(BILPublicHex.encode([0x00, 0xAB, 0xFF]), "00abff", "hex encode lower")
            t(BILPublicHex.sameHex("0xABcd", [0xAB, 0xCD]), "sameHex case-insensitive")
            t(BILPublicHex.sameHex("0x0Xabcd", [0xAB, 0xCD]), "sameHex removes 0x then 0X (Android)")
            t(!BILPublicHex.sameHex("abce", [0xAB, 0xCD]), "sameHex differs")
            t(!BILPublicHex.sameHex(nil, [0xAB]), "sameHex nil")
            t(!BILPublicHex.sameHex("0xabcd ", [0xAB, 0xCD]), "sameHex trailing space")
            t(BILPublicHex.sameHex("", []), "sameHex empty")

            let tuez = "TUEZSdKsoDHQMeZwihtdoBiN46zxhGWYdH"
            let tuezHex = "41c8599111f29c1e1e061265b4af93ea1f274ad78a"   // = native-vectors.json owner_address
            eq(BILTronAddressCodec.hex41(fromBase58: tuez) ?? "-", tuezHex, "TRON base58 → hex41")
            eq(BILTronAddressCodec.base58(fromHex41: tuezHex) ?? "-", tuez, "hex41 → base58")
            eq(BILTronAddressCodec.base58(fromHex41: "0x" + tuezHex.uppercased()) ?? "-", tuez, "0x + upper hex41 → base58")
            t(BILTronAddressCodec.hex41(fromBase58: "TUEZSdKsoDHQMeZwihtdoBiN46zxhGWYdx") == nil, "bad checksum")
            t(!BILTronAddressCodec.isValid("TUEZSdKsoDHQMeZwihtdoBiN46zxhGWYdx"), "isValid bad checksum")
            t(BILTronAddressCodec.isValid(tuez) && BILTronAddressCodec.isValid("TMTjucQ73f32Yw4Xx8Gm1dH1mdFrFjn9Lb"), "isValid")
            eq(BILTronAddressCodec.hex41(fromBase58: "TMTjucQ73f32Yw4Xx8Gm1dH1mdFrFjn9Lb") ?? "-", "417e0ed463557e9ebbec146a1f91afdec5a6fbdcb1", "TronLink photo address")
            t(BILTronAddressCodec.base58(fromHex41: "42" + tuezHex.dropFirst(2)) == nil, "hex41 must start 41")
            t(BILTronAddressCodec.base58(fromHex41: tuezHex + "00") == nil, "hex41 length")
            // Android TronAddressCodec.toBase58: any 21-byte payload (review WP1 #3).
            eq(BILTronAddressCodec.base58(anyHex21: tuezHex) ?? "-", tuez, "anyHex21: 41… as fromHex41")
            eq(BILTronAddressCodec.base58(anyHex21: "0x0X" + tuezHex.uppercased()) ?? "-", tuez, "anyHex21: removes 0x then 0X (Android)")
            let a0Hex = "a0" + tuezHex.dropFirst(2)
            let a0 = BILTronAddressCodec.base58(anyHex21: String(a0Hex))
            t(a0 != nil && a0 != tuez, "anyHex21: other version byte still encoded")
            eq(a0.flatMap { BILBase58Check.decode($0) } ?? [], BILPublicHex.decode(String(a0Hex)) ?? [9], "anyHex21: base58check of the payload")
            t(BILTronAddressCodec.base58(fromHex41: String(a0Hex)) == nil, "fromHex41 stays strict for the same payload")
            t(BILTronAddressCodec.base58(anyHex21: String(tuezHex.dropLast(2))) == nil, "anyHex21: 20 bytes")
            t(BILTronAddressCodec.base58(anyHex21: tuezHex + "00") == nil, "anyHex21: 22 bytes")
            t(BILTronAddressCodec.base58(anyHex21: " " + tuezHex) == nil && BILTronAddressCodec.base58(anyHex21: "") == nil,
              "anyHex21: no trimming, empty")
            t(BILTronAddressCodec.hex41(fromBase58: String(tuez.dropLast())) == nil, "33 chars")
            t(BILTronAddressCodec.hex41(fromBase58: " " + tuez) == nil, "no trimming")
            t(BILTronAddressCodec.hex41(fromBase58: "1BvBMSEYstWetqTFn5Au4m4GFg7xJaNVN2") == nil, "Bitcoin address is not TRON")
            eq(BILBase58Check.decode("1BvBMSEYstWetqTFn5Au4m4GFg7xJaNVN2")?.count ?? 0, 21, "base58check Bitcoin payload")
            eq(BILBase58Check.decode("1BvBMSEYstWetqTFn5Au4m4GFg7xJaNVN2")?.first ?? 9, 0, "version byte 0")
            eq(BILBase58Check.encode(BILBase58Check.decode("1BvBMSEYstWetqTFn5Au4m4GFg7xJaNVN2") ?? []), "1BvBMSEYstWetqTFn5Au4m4GFg7xJaNVN2", "base58check round trip")
            t(BILBase58Check.decode("0OIl") == nil, "invalid base58 chars")
            t(BILBase58Check.decode("1") == nil, "too short for a checksum")
            eq(BILBase58.encode(Array("Hello World!".utf8)), "2NEpo7TZRRrLZSi2U", "base58 known vector")
            eq(BILBase58.encode([0, 0, 1]), "112", "base58 leading zeros")
            eq(BILBase58.decode("112") ?? [], [0, 0, 1], "base58 decode leading zeros")
            eq(BILBase58.decode("") ?? [9], [], "base58 empty")
            eq(BILBase58.encode([]), "", "base58 encode empty")
            eq(BILBase58.decode("1111") ?? [], [0, 0, 0, 0], "base58 all zeros")
            t(BILBase58.decode("é") == nil && BILBase58.decode("I") == nil && BILBase58.decode("0") == nil, "base58 invalid chars")
            var rng = SystemRandomNumberGenerator()
            var roundTrips = 0
            for n in 0..<64 {
                var bytes = (0..<n).map { _ in UInt8.random(in: 0...255, using: &rng) }
                if n % 3 == 0 && n > 0 { bytes[0] = 0 }
                if BILBase58.decode(BILBase58.encode(bytes)) == bytes && BILBase58Check.decode(BILBase58Check.encode(bytes)) == bytes {
                    roundTrips += 1
                }
            }
            eq(roundTrips, 64, "base58 / base58check random round trips")

            t(BILBase64Strict.decode("cHNidP8") == nil, "cHNidP8 (unpadded) refused")
            eq(BILBase64Strict.decode("cHNidP8=") ?? [], [0x70, 0x73, 0x62, 0x74, 0xFF], "PSBT magic")
            eq(BILBase64Strict.decode("") ?? [9], [], "empty")
            eq(BILBase64Strict.decode("QQ==") ?? [], [0x41], "QQ==")
            eq(BILBase64Strict.decode("QR==") ?? [], [0x41], "non-zero pad bits accepted (Java decoder)")
            eq(BILBase64Strict.decode("QUJD") ?? [], Array("ABC".utf8), "QUJD")
            eq(BILBase64Strict.decode("QUI=") ?? [], Array("AB".utf8), "QUI=")
            for bad in ["Q===", "=QQQ", "QQ=Q", "QQ==\n", " QQ==", "QQ", "-_-_", "QQ==QQ==", "Q", "QUJD=", "QU I="] {
                t(BILBase64Strict.decode(bad) == nil, "base64 refuses \(bad.debugDescription)")
            }
            let bytes: [UInt8] = Array(0...255)
            eq(BILBase64Strict.decode(BILBase64Strict.encode(bytes)) ?? [], bytes, "base64 round trip")
        }

        // MARK: - Texts

        section("BILPublicText")
        do {
            var en = englishTemplates
            en["SecurityCenter.pb_row_time"] = "Time"
            en["Test.fmt.mixed"] = "a %1$@ b"
            en["Test.fmt.seq"] = "%@ has %ld (%d) 100%%"
            CoreTestStrings.table = en
            eq(BILPublicText.string("PublicProtocol.err.integrity"), en["PublicProtocol.err.integrity"] ?? "?", "PublicProtocol table")
            eq(BILPublicText.string("SecurityCenter.pb_row_time"), "Time", "SecurityCenter table")
            eq(BILPublicText.string("Done"), "UI(Done)", "other keys → UI.strings")
            eq(BILPublicText.string("PublicProtocolX.y"), "UI(PublicProtocolX.y)", "prefix needs the dot")
            let conflict = BILPublicSignerErrors.prevoutConflict(inputNumber: 1234567).text
            t(conflict.hasPrefix("Input 1234567 claims"), "prevoutConflict text, Latin digits, no grouping: \(conflict.prefix(30))")
            let owner = BILPublicSignerErrors.tronOwner("TUEZSdKsoDHQMeZwihtdoBiN46zxhGWYdH").text
            eq(owner, "This transaction is for account TUEZSdKsoDHQMeZwihtdoBiN46zxhGWYdH, not this wallet's address.", "tronOwner text")
            eq(BILPublicText.format("PublicProtocol.err.tronlinkMulti", [.int(3)]).hasPrefix("This TronLink request holds 3 transactions."), true, "%1$ld")
            eq(BILPublicText.format("PublicProtocol.err.integrity", []), en["PublicProtocol.err.integrity"] ?? "?", "no args → as is")
            _ = CoreTestLog.take()
            eq(BILPublicText.format("Test.fmt.mixed", [.int(1)]), "UI(Test.fmt.mixed)", "UI key routing for unknown prefix")
            eq(BILPublicText.format("PublicProtocol.err.tronOwner", [.int(1)]), en["PublicProtocol.err.tronOwner"] ?? "?", "type mismatch → unformatted, no crash")
            eq(BILPublicText.format("PublicProtocol.err.tronOwner", [.text("a"), .int(2)]), "This transaction is for account a, not this wallet's address.", "extra args ignored")
            eq(BILPublicText.format("PublicProtocol.err.prevoutConflict", [.text("x")]), en["PublicProtocol.err.prevoutConflict"] ?? "?", "%ld with text → unformatted")
            eq(CoreTestLog.take(), ["PublicProtocol text: FORMAT_MISMATCH", "PublicProtocol text: FORMAT_MISMATCH"], "mismatch logged as a code only")
            CoreTestStrings.table = ["PublicProtocol.t.seq": "%@ has %ld (%d) 100%%", "PublicProtocol.t.missing": "%2$@",
                                     "PublicProtocol.t.wide": "%1$d|%1$ld|%2$d", "PublicProtocol.t.wideSeq": "%d items, %@ (%d)",
                                     "PublicProtocol.t.pct": "%1$ld%%d %%%1$d", "PublicProtocol.t.bad": "%1$d %1$@",
                                     "SendC.confirm.passwordMessageWrong": "Wrong password", "SendC.t.fmt": "%1$@ / %2$d"]
            eq(BILPublicText.format("PublicProtocol.t.seq", [.text("x"), .int(-5), .int(7)]), "x has -5 (7) 100%", "sequential + %%")
            eq(BILPublicText.format("PublicProtocol.t.missing", [.text("x")]), "%2$@", "missing argument → unformatted")
            // %d with a 64-bit Int prints the whole value, like Java's %d (review WP1 #9).
            eq(BILPublicText.format("PublicProtocol.t.wide", [.int(5_000_000_000), .int(Int.min)]),
               "5000000000|5000000000|\(Int.min)", "%N$d widened to %N$ld")
            eq(BILPublicText.format("PublicProtocol.t.wideSeq", [.int(-5_000_000_000), .text("x"), .int(Int(Int32.max) + 1)]),
               "-5000000000 items, x (2147483648)", "sequential %d widened")
            eq(BILPublicText.format("PublicProtocol.t.pct", [.int(3)]), "3%d %3", "%% before d is not a conversion")
            _ = CoreTestLog.take()
            eq(BILPublicText.format("PublicProtocol.t.bad", [.int(1)]), "%1$d %1$@", "widening never applies to a mismatch")
            eq(CoreTestLog.take(), ["PublicProtocol text: FORMAT_MISMATCH"], "mismatch logged")
            // SendC.* keys (reused `.sendConfirm*` texts, design §3.19) come from SendC.strings, not UI.strings (review WP1 #4).
            eq(BILPublicText.string("SendC.confirm.passwordMessageWrong"), "Wrong password", "SendC table")
            eq(BILPublicText.format("SendC.t.fmt", [.text("a"), .int(5_000_000_000)]), "a / 5000000000", "SendC format")
            eq(BILPublicText.string("SendCX.y"), "UI(SendCX.y)", "SendC prefix needs the dot")
            eq(BILPublicText.string("sendc_confirm_x"), "UI(sendc_confirm_x)", "Android-style name is not a SendC key")
            CoreTestStrings.table = en
        }

        // MARK: - Refusal bounds / failure

        section("refusal bounds and sanitizing (R1 §2.3)")
        do {
            let m399 = String(repeating: "m", count: 399)
            eq(BILPublicSignerRefusal(code: "X", engineMessage: m399 + "😀").engineMessage, m399, "m×399 + 😀 → m×399")
            eq(BILPublicSignerRefusal.bound(String(repeating: "m", count: 400)).utf16.count, 400, "400 kept")
            eq(BILPublicSignerRefusal.bound(String(repeating: "m", count: 401)).utf16.count, 400, "401 → 400")
            eq(BILPublicSignerRefusal.bound(String(repeating: "😀", count: 200)), String(repeating: "😀", count: 200), "200 pairs kept")
            eq(BILPublicSignerRefusal.bound(String(repeating: "😀", count: 201)), String(repeating: "😀", count: 200), "201 pairs → 200")
            eq(BILPublicSignerRefusal.bound("m" + String(repeating: "😀", count: 200)), "m" + String(repeating: "😀", count: 199), "odd offset")
            eq(BILPublicSignerRefusal(code: "bad_code !", engineMessage: "").code, "BAD_CODE", "bad_code ! → BAD_CODE")
            eq(BILPublicSignerRefusal(code: "", engineMessage: "").code, "UNKNOWN", "empty → UNKNOWN")
            eq(BILPublicSignerRefusal.sanitize("!!!"), "UNKNOWN", "nothing left → UNKNOWN")
            eq(BILPublicSignerRefusal.sanitize(String(repeating: "A", count: 100)).count, 80, "80 max")
            eq(BILPublicSignerRefusal.sanitize("straße"), "STRASSE", "full upper-case mapping")
            eq(BILPublicSignerRefusal.sanitize("qr-protocol"), "QRPROTOCOL", "dash dropped")
            eq(BILPublicSignerRefusal.sanitize("é_x"), "_X", "non-ASCII dropped")
            let r = BILPublicSignerRefusal(code: "RISK", engineMessage: "SECRET-ENGINE-TEXT")
            eq(r.description, "Public signer refused the request: RISK", "refusal description")
            t(!"\(r)".contains("SECRET") && !String(reflecting: r).contains("SECRET") && !"\(r as Error)".contains("SECRET"), "message never printed")
            eq(BILPublicSignerRefusal.limitCode + "/" + BILPublicSignerRefusal.limitMessage, "LIMIT/Request exceeds one megabyte.", "LIMIT")
            eq(BILPublicSignerRefusal.scanCode + "/" + BILPublicSignerRefusal.scanMessage, "SCAN/No scan session is active.", "SCAN")
            eq(BILPublicSignerRefusal.defaultCode + "/" + BILPublicSignerRefusal.defaultMessage, "SIGNING_FAILED/This request could not be signed.", "default")
            eq(BILPublicSignerFailure.engineUnavailable.code, "ENGINE_UNAVAILABLE", "failure code 1")
            eq(BILPublicSignerFailure.malformedResponse.code, "ENGINE_FAILURE", "failure code 2")
            eq(BILPublicSignerFailure.invalidRequest.code, "INVALID_REQUEST", "failure code 3")
            eq("\(BILPublicSignerFailure.malformedResponse)", "Public signer failure: ENGINE_FAILURE", "failure description")
        }

        // MARK: - Error mapping (Android PublicSignerErrorsTest / OtherWalletErrorsTest)

        section("error mapping")
        do {
            let generic = "PublicProtocol.match.invalid.body"
            var vocabCodes = [String]()
            var vocabMessages = Set<String>()
            var vocabStatuses = [String]()
            if let v = loadJSON("PUB_VOCAB")?.objectValue {
                for c in v.arr("errorCodes") ?? [] {
                    guard let o = c.objectValue, let code = o.str("code") else { continue }
                    vocabCodes.append(code)
                    for m in o.strings("messages") ?? [] { vocabMessages.insert(m) }
                }
                for s in v.arr("planStatuses") ?? [] {
                    if let w = s.objectValue?.str("status") { vocabStatuses.append(w) }
                }
            }
            eq(vocabCodes.count, 49, "vocabulary has 49 error codes")
            let unmapped = vocabCodes.filter { BILPublicSignerErrors.codes[$0] == nil }
            eq(unmapped, [], "every engine code is mapped")
            eq(Set(BILPublicSignerErrors.codes.keys).subtracting(vocabCodes).subtracting(["SIGNING_FAILED", "UNKNOWN"]), Set<String>(), "no stale codes")
            for c in vocabCodes { t(BILPublicSignerErrors.category(c) != generic, "known code \(c) is not generic") }
            let table: [String: String] = [
                "NETWORK": "err.networkUnsupported", "CHAIN_ID": "err.chainMismatch", "SIGNER": "err.notThisWallet",
                "FINGERPRINT": "err.notThisWallet", "INTEGRITY": "err.integrity", "PLAN": "err.integrity", "RISK": "err.confirmRisk",
                "PREVOUT": "err.prevout", "SIGHASH": "err.sighash", "LOOKUP_TABLE": "err.lookupTable", "LIMIT": "err.tooLarge",
                "QR_PROTOCOL": "err.qrMalformed", "PUBLIC_INDEX": "err.rebuildPublicData", "SIGNATURE": "err.verify",
                "UNSUPPORTED": "err.unsupported", "SCAN": "err.scanTimeout", "SEED": "err.rebuildPublicData",
                "OPERATION": "err.engineUnavailable", "SIGNING_FAILED": "err.engineUnavailable", "UNKNOWN": "err.engineUnavailable",
                "MNEMONIC": "err.unsupported", "TRUNCATED": "err.qrMalformed", "WALLET": "err.integrity",
            ]
            for (code, key) in table { eq(BILPublicSignerErrors.category(code), "PublicProtocol." + key, "category \(code)") }
            eq(BILPublicSignerErrors.category("SOMETHING_NEW"), generic, "unknown → generic (fail closed)")
            eq(BILPublicSignerErrors.category("network"), generic, "codes are case-sensitive")
            eq(BILPublicSignerErrors.category("NETWOR\u{212A}"), generic, "Kelvin sign is not K (exact)")
            // Statuses.
            eq(Set(vocabStatuses), Set(["ready", "noMatch", "missingSigner", "ambiguous", "setupRequired", "invalid"]), "statuses = vocabulary")
            eq(BILPublicSignerErrors.category("noMatch"), "PublicProtocol.match.noMatch", "category noMatch")
            eq(BILPublicSignerErrors.category("setupRequired"), "PublicProtocol.match.setupRequired", "category setupRequired")
            eq(BILPublicSignerErrors.category("ready"), generic, "category ready → generic (Android)")
            for s in ["noMatch", "missingSigner", "ambiguous", "setupRequired", "invalid"] {
                eq(BILPublicSignerErrors.category(s), BILPublicSignerErrors.statusTitleKey(s), "title = category \(s)")
                t(BILPublicSignerErrors.statusBodyKey(s) != BILPublicSignerErrors.statusTitleKey(s), "body ≠ title \(s)")
            }
            eq(BILPublicSignerErrors.statusTitleKey("ready"), "PublicProtocol.match.invalid", "ready title → match.invalid (D-23)")
            eq(BILPublicSignerErrors.statusTitleKey("bogus"), "PublicProtocol.match.invalid", "unknown title")
            eq(BILPublicSignerErrors.statusBodyKey("ambiguous"), "PublicProtocol.match.ambiguous.body", "ambiguous body")
            eq(BILPublicSignerErrors.statusBodyKey("invalid"), generic, "invalid body")
            eq(BILPublicSignerErrors.statusBodyKey("ready"), generic, "ready body")
            eq(BILPublicSignerErrors.statusBodyKey("bogus"), generic, "unknown body")
            // Refinements.
            func of(_ c: String, _ m: String) -> BILPublicSignError { return BILPublicSignerErrors.of(code: c, message: m) }
            eq(of("QR_PROTOCOL", "Mixed UR fountain sessions").key, "PublicProtocol.err.qrMixed", "qrMixed")
            eq(of("QR_PROTOCOL", "QR scan memory limit exceeded").key, "PublicProtocol.err.tooLarge", "tooLarge")
            eq(of("QR_PROTOCOL", "Unsupported signing UR type").key, "PublicProtocol.err.unsupportedUr", "unsupportedUr")
            eq(of("QR_PROTOCOL", "UR checksum failure").key, "PublicProtocol.err.qrMalformed", "qrMalformed")
            eq(of("QR_PROTOCOL", "Mixed UR types ").key, "PublicProtocol.err.qrMalformed", "exact message only")
            eq(of("qr_protocol", "Mixed UR types").key, "PublicProtocol.err.qrMixed", "code sanitized before refining")
            eq(of("SIGNATURE", "This wallet has already signed the transaction.").key, "PublicProtocol.err.alreadySigned", "alreadySigned SIGNATURE")
            eq(of("TRANSACTION", "EVM transaction is already signed.").key, "PublicProtocol.err.alreadySigned", "alreadySigned TRANSACTION")
            eq(of("SIGNATURE", "Signature verification failed.").key, "PublicProtocol.err.verify", "verify")
            eq(of("NETWORK", "This wallet has already signed the transaction.").key, "PublicProtocol.err.networkUnsupported", "refinement needs its code")
            eq(of("UNSUPPORTED", "Unsupported TRON contract type. Its signed structure cannot be safely parsed.").key, "PublicProtocol.err.tronContractUnsupported", "TRON vote")
            eq(of("UNSUPPORTED", "TRC10 value in a smart contract call is unsupported.").key, "PublicProtocol.err.tronContractUnsupported", "TRC10")
            eq(of("UNSUPPORTED", "Something else").key, "PublicProtocol.err.unsupported", "other UNSUPPORTED")
            let e = of("NETWORK", "Unsupported network")
            eq(e.code ?? "-", "NETWORK", "code kept")
            eq(e.engineMessage ?? "-", "Unsupported network", "engine message kept")
            eq(e.description, "BILPublicSignError(NETWORK)", "only the code is printed")
            eq(BILPublicSignerErrors.of(BILPublicSignerRefusal(code: "", engineMessage: "x")).key, "PublicProtocol.err.engineUnavailable", "UNKNOWN")
            let lists = BILPublicSignerErrors.otherRequestMessages.union(BILPublicSignerErrors.tooLargeMessages)
                .union(BILPublicSignerErrors.unsupportedUrMessages).union(BILPublicSignerErrors.alreadySignedMessages)
                .union(BILPublicSignerErrors.tronContractMessages)
            eq(lists.subtracting(vocabMessages), Set<String>(), "refinement lists are real engine messages")
            // Verifier reasons.
            eq(BILPublicSignerErrors.verifierKey("INTEGRITY"), "PublicProtocol.err.integrity", "verifier INTEGRITY")
            eq(BILPublicSignerErrors.verifierKey("CHAIN_MISMATCH"), "PublicProtocol.err.chainMismatch", "verifier CHAIN_MISMATCH")
            eq(BILPublicSignerErrors.verifierKey("LOOKUP_TABLE"), "PublicProtocol.err.lookupTable", "verifier LOOKUP_TABLE")
            eq(BILPublicSignerErrors.verifierKey("VERIFY"), "PublicProtocol.err.verify", "verifier VERIFY")
            eq(BILPublicSignerErrors.verifierKey("LOO\u{212A}UP_TABLE"), generic, "verifier exact")
            eq(BILPublicSignerErrors.verifierKey("OTHER"), generic, "verifier unknown")
            // Prebuilt host errors.
            let pre: [(BILPublicSignError, String, String?, [BILTextArg])] = [
                (BILPublicSignerErrors.engineUnavailable, "PublicProtocol.err.engineUnavailable", nil, []),
                (BILPublicSignerErrors.noWallet, "PublicProtocol.err.noWallet", "NO_WALLET", []),
                (BILPublicSignerErrors.tooManyWallets, "PublicProtocol.err.tooManyWallets", "TOO_MANY_WALLETS", []),
                (BILPublicSignerErrors.tpUnsupported, "PublicProtocol.err.tpUnsupported", "TP_UNSUPPORTED", []),
                (BILPublicSignerErrors.unexpected, generic, "UNEXPECTED", []),
                (BILPublicSignerErrors.prevoutConflict(inputNumber: 3), "PublicProtocol.err.prevoutConflict", "PREVOUT_CONFLICT", [.int(3)]),
                (BILPublicSignerErrors.tronOwner("TX"), "PublicProtocol.err.tronOwner", "TRON_OWNER", [.text("TX")]),
            ]
            for (err, key, code, args) in pre {
                t(err.key == key && err.code == code && err.args == args && err.engineMessage == nil, "prebuilt \(key)")
            }
            // Every key this file can produce exists in the strings JSON, with matching placeholder types.
            var produced = Set(BILPublicSignerErrors.codes.values)
            for k in ["err.tronContractUnsupported", "err.qrMixed", "err.tooLarge", "err.unsupportedUr", "err.alreadySigned",
                      "err.integrity", "err.chainMismatch", "err.lookupTable", "err.verify"] { produced.insert("PublicProtocol." + k) }
            for (err, _, _, _) in pre { produced.insert(err.key) }
            for s in ["noMatch", "missingSigner", "ambiguous", "setupRequired", "invalid", "ready"] {
                produced.insert(BILPublicSignerErrors.statusTitleKey(s))
                produced.insert(BILPublicSignerErrors.statusBodyKey(s))
            }
            let table2 = CoreTestStrings.table
            // (The app also checked that every produced key exists in its strings JSON; the package ships no strings.)
            t(!produced.isEmpty, "produced keys collected")
            t((table2["PublicProtocol.err.prevoutConflict"] ?? "").contains("%1$ld"), "prevoutConflict placeholder is %1$ld (.int)")
            t((table2["PublicProtocol.err.tronOwner"] ?? "").contains("%1$@"), "tronOwner placeholder is %1$@ (.text)")
            // BILPublicSignError basics.
            let s = BILPublicSignError("PublicProtocol.err.verify", code: nil, engineMessage: "SECRET")
            eq(s.description, "BILPublicSignError(PublicProtocol.err.verify)", "description = key without code")
            t(!String(reflecting: s).contains("SECRET") && !"\(s as Error)".contains("SECRET"), "engine message never printed")
            let w = s.with(code: "TIMEOUT")
            t(w.code == "TIMEOUT" && w.key == s.key && w.engineMessage == "SECRET" && w.args == s.args, "with(code:)")
            t(s != w && s == BILPublicSignError("PublicProtocol.err.verify", engineMessage: "SECRET"), "Equatable")
        }

        // MARK: - Log hygiene (C-KEY-5)

        section("BILPublicLog")
        do {
            _ = CoreTestLog.take()
            BILPublicLog.code("engine", "risk!")
            BILPublicLog.code("scan", "")
            BILPublicLog.failure("sign", BILPublicSignerRefusal(code: "RISK", engineMessage: "SECRET-ENGINE-TEXT"))
            BILPublicLog.failure("sign", BILMalformedEngineResult(what: "SECRET.what"))
            BILPublicLog.failure("sign", BILPublicTimeout.Expired())
            BILPublicLog.failure("index", NSError(domain: "SECRET-DOMAIN", code: 7, userInfo: [NSLocalizedDescriptionKey: "SECRET"]))
            BILPublicLog.failure("sign", BILPublicSignError("PublicProtocol.err.verify", code: "network x", engineMessage: "SECRET"))
            BILPublicLog.failure("sign", BILPublicSignerFailure.engineUnavailable)
            BILPublicLog.failure("sign", BILPublicSignError("PublicProtocol.err.verify"))
            let lines = CoreTestLog.take()
            eq(lines, [
                "PublicProtocol engine: RISK",
                "PublicProtocol scan: UNKNOWN",
                "PublicProtocol sign: BILPublicSignerRefusal RISK",
                "PublicProtocol sign: BILMalformedEngineResult",
                "PublicProtocol sign: Expired TIMEOUT",
                "PublicProtocol index: NSError",
                "PublicProtocol sign: BILPublicSignError NETWORKX",
                "PublicProtocol sign: BILPublicSignerFailure ENGINE_UNAVAILABLE",
                "PublicProtocol sign: BILPublicSignError",
            ], "log lines carry area + type + code only")
            t(!lines.joined().contains("SECRET"), "no secret in any log line")
        }

        // MARK: - Concurrency

        section("BILPublicTimeout")
        runAsync {
            // Blocked work (a synchronous 3 s sleep, like a stuck JavaScriptCore call): Expired arrives on time.
            let finished = Box(false)
            let start = Date()
            do {
                let v: Int = try await BILPublicTimeout.run(seconds: 0.2) {
                    blockingSleep(3)
                    finished.value = true
                    return 42
                }
                t(false, "blocked work must time out (got \(v))")
            } catch is BILPublicTimeout.Expired {
                let elapsed = Date().timeIntervalSince(start)
                t(elapsed < 2.5, "Expired while the work is still blocked (\(String(format: "%.2f", elapsed)) s)")
                t(!finished.value, "work still running at expiry")
            } catch {
                t(false, "unexpected error \(type(of: error))")
            }
            // Let the late value arrive: it must be dropped (a second resume would abort the process).
            try? await Task.sleep(nanoseconds: 3_200_000_000)
            t(finished.value, "late work completed and its value was dropped")

            // Fast work returns its value immediately (the timer does not delay it).
            let s2 = Date()
            let fast: Int? = try? await BILPublicTimeout.run(seconds: 5) { return 7 }
            eq(fast ?? -1, 7, "fast value")
            t(Date().timeIntervalSince(s2) < 2.5, "fast value not delayed by the 5 s timer")

            // Async work that finishes before the deadline.
            let slowOk: String? = try? await BILPublicTimeout.run(seconds: 2) {
                try await Task.sleep(nanoseconds: 100_000_000)
                return "ok"
            }
            eq(slowOk ?? "-", "ok", "async work within the deadline")

            // Work errors propagate.
            do {
                let _: Int = try await BILPublicTimeout.run(seconds: 1) { throw BILPublicSignerFailure.invalidRequest }
                t(false, "error must propagate")
            } catch let e as BILPublicSignerFailure {
                eq(e, .invalidRequest, "error propagated")
            } catch {
                t(false, "wrong error \(type(of: error))")
            }

            // Expiry cancels cooperative work.
            let sawCancel = Box(false)
            do {
                let _: Int = try await BILPublicTimeout.run(seconds: 0.1) {
                    do {
                        try await Task.sleep(nanoseconds: 2_000_000_000)
                    } catch {
                        sawCancel.value = true
                        throw error
                    }
                    return 1
                }
                t(false, "must expire")
            } catch {
                t(error is BILPublicTimeout.Expired, "Expired (cooperative work)")
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
            t(sawCancel.value, "expiry cancelled the work task")

            // Cancelling the caller cancels the work and throws CancellationError promptly.
            let workCancelled = Box(false)
            let outer = Task { () -> String in
                do {
                    let _: Int = try await BILPublicTimeout.run(seconds: 10) {
                        do {
                            try await Task.sleep(nanoseconds: 5_000_000_000)
                        } catch {
                            workCancelled.value = true
                            throw error
                        }
                        return 1
                    }
                    return "value"
                } catch is CancellationError {
                    return "cancelled"
                } catch {
                    return "other"
                }
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
            let s3 = Date()
            outer.cancel()
            let outcome = await outer.value
            eq(outcome, "cancelled", "caller cancellation → CancellationError")
            t(Date().timeIntervalSince(s3) < 2.5, "cancellation is prompt (work would sleep 5 s)")
            try? await Task.sleep(nanoseconds: 100_000_000)
            t(workCancelled.value, "caller cancellation cancelled the work")

            // Already-cancelled caller: CancellationError, and the work never starts (review WP1 #2).
            var preOutcomes = [String: Int]()
            let preStarted = Box(0)
            for _ in 0..<50 {
                let pre = Task { () -> String in
                    while !Task.isCancelled { await Task.yield() }
                    do {
                        let _: Int = try await BILPublicTimeout.run(seconds: 10) {
                            preStarted.mutate { $0 += 1 }
                            return 1
                        }
                        return "value"
                    } catch is CancellationError {
                        return "cancelled"
                    } catch {
                        return "other"
                    }
                }
                pre.cancel()
                let outcome = await pre.value
                preOutcomes[outcome, default: 0] += 1
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
            eq(preOutcomes, ["cancelled": 50], "already-cancelled caller → CancellationError (50 runs)")
            eq(preStarted.value, 0, "work never started for an already-cancelled caller")

            // The expiry is decided at the deadline even when every cooperative-pool thread is blocked (review WP1 #6): the
            // timer runs on GCD; the decision is observed through the work's cancellation handler, which `finish` runs
            // synchronously on the deciding thread.
            let workReady = Box(false)
            let cancelledAfter = Box(-1.0)
            let raceStart = Box(Date())
            let saturated = Task.detached { () -> String in
                raceStart.value = Date()
                do {
                    let _: Int = try await BILPublicTimeout.run(seconds: 0.25) {
                        try await withTaskCancellationHandler(operation: {
                            workReady.value = true
                            try await Task.sleep(nanoseconds: 3_000_000_000)
                            return 1
                        }, onCancel: {
                            cancelledAfter.value = Date().timeIntervalSince(raceStart.value)
                        })
                    }
                    return "value"
                } catch is BILPublicTimeout.Expired {
                    return "expired"
                } catch {
                    return "other"
                }
            }
            while !workReady.value { try? await Task.sleep(nanoseconds: 1_000_000) }
            let width = max(2, ProcessInfo.processInfo.activeProcessorCount)
            let blockers = (0..<width).map { _ in Task.detached { blockingSleep(1.5) } }
            let saturatedOutcome = await saturated.value
            for b in blockers { await b.value }
            eq(saturatedOutcome, "expired", "saturated pool: Expired")
            t(cancelledAfter.value >= 0.2 && cancelledAfter.value < 1.0,
              "saturated pool: race decided at the deadline (\(String(format: "%.2f", cancelledAfter.value)) s, \(width) blockers × 1.5 s)")

            // Stress: many concurrent races, each resumes exactly once with the work's own value or Expired.
            let results = Box([(Int, Int)]())
            await withTaskGroup(of: Void.self) { group in
                for i in 0..<200 {
                    group.addTask {
                        let v: Int? = try? await BILPublicTimeout.run(seconds: i % 2 == 0 ? 0.001 : 5) {
                            if i % 3 == 0 { try await Task.sleep(nanoseconds: 2_000_000) }
                            return i
                        }
                        results.mutate { $0.append((i, v ?? -1)) }
                    }
                }
            }
            eq(results.value.count, 200, "200 races resumed exactly once")
            t(results.value.allSatisfy { pair in pair.0 % 2 == 1 ? pair.1 == pair.0 : (pair.1 == pair.0 || pair.1 == -1) },
              "every race delivered its own value (or Expired on the 1 ms deadline)")
        }

        section("BILAsyncMutex")
        runAsync {
            let mutex = BILAsyncMutex()
            let order = Box([Int]())
            let gate = Box(false)
            let holding = Box(false)
            let holder = Task {
                await mutex.withLock {
                    holding.value = true
                    while !gate.value { try? await Task.sleep(nanoseconds: 1_000_000) }
                    order.mutate { $0.append(0) }
                }
            }
            while !holding.value { try? await Task.sleep(nanoseconds: 1_000_000) }
            var tasks = [Task<Void, Never>]()
            for i in 1...100 {
                tasks.append(Task {
                    await mutex.withLock {
                        order.mutate { $0.append(i) }
                    }
                })
                // Launch the next task only once this one is queued, so arrival order is known.
                var spins = 0
                while mutex.queuedCount < i && spins < 20_000 {
                    try? await Task.sleep(nanoseconds: 100_000)
                    spins += 1
                }
            }
            eq(mutex.queuedCount, 100, "100 tasks queued behind the holder")
            gate.value = true
            await holder.value
            for task in tasks { await task.value }
            eq(order.value, Array(0...100), "FIFO order under 100 concurrent tasks")
            eq(mutex.queuedCount, 0, "queue drained")

            // Mutual exclusion with suspension inside the critical section.
            let inside = Box(0)
            let maxInside = Box(0)
            let counter = Box(0)
            await withTaskGroup(of: Void.self) { group in
                for _ in 0..<100 {
                    group.addTask {
                        await mutex.withLock {
                            inside.mutate { $0 += 1 }
                            maxInside.mutate { $0 = max($0, inside.value) }
                            let read = counter.value
                            await Task.yield()
                            try? await Task.sleep(nanoseconds: 100_000)
                            counter.value = read + 1
                            inside.mutate { $0 -= 1 }
                        }
                    }
                }
            }
            eq(counter.value, 100, "no lost update")
            eq(maxInside.value, 1, "one task inside at a time")

            // Errors thrown inside release the lock.
            do {
                try await mutex.withLock { throw BILPublicSignerFailure.malformedResponse }
                t(false, "throws")
            } catch {
                t(error as? BILPublicSignerFailure == .malformedResponse, "error passes through")
            }
            let after: Int = await mutex.withLock { return 5 }
            eq(after, 5, "lock released after a throw")
        }

        section("BILAsyncMutex cancellation (review WP1 #1)")
        runAsync {
            /// Starts a task that holds `m` until `gate` opens; returns once it holds the lock.
            func hold(_ m: BILAsyncMutex, _ gate: Box<Bool>) async -> Task<Void, Never> {
                let holding = Box(false)
                let task = Task.detached {
                    await m.withLock {
                        holding.value = true
                        while !gate.value { try? await Task.sleep(nanoseconds: 1_000_000) }
                    }
                }
                while !holding.value { try? await Task.sleep(nanoseconds: 1_000_000) }
                return task
            }
            func waitQueued(_ m: BILAsyncMutex, _ n: Int) async {
                var spins = 0
                while m.queuedCount < n && spins < 20_000 {
                    try? await Task.sleep(nanoseconds: 100_000)
                    spins += 1
                }
            }

            // A waiter cancelled while queued leaves the queue at once, never runs its body, and the lock stays consistent.
            let m = BILAsyncMutex()
            let gate = Box(false)
            let holder = await hold(m, gate)
            let ran = Box([String]())
            let waiter = Task.detached { () -> String in
                do {
                    try await m.withLockCancellable { ran.mutate { $0.append("cancelled-waiter") } }
                    return "ran"
                } catch is CancellationError {
                    return "cancelled"
                } catch {
                    return "other"
                }
            }
            await waitQueued(m, 1)
            eq(m.queuedCount, 1, "cancellable waiter queued")
            let c0 = Date()
            waiter.cancel()
            let waiterOutcome = await waiter.value
            eq(waiterOutcome, "cancelled", "cancelled waiter → CancellationError")
            t(Date().timeIntervalSince(c0) < 1.0, "cancelled waiter leaves while the holder still holds the lock")
            eq(m.queuedCount, 0, "cancelled waiter removed from the queue")
            gate.value = true
            await holder.value
            let next: Int = await m.withLock { return 9 }
            eq(next, 9, "lock free after holder release")
            eq(ran.value, [], "cancelled waiter's body never ran")

            // FIFO of the others is kept when a middle waiter is cancelled.
            let gate2 = Box(false)
            let holder2 = await hold(m, gate2)
            let order = Box([String]())
            let a = Task.detached { await m.withLock { order.mutate { $0.append("A") } } }
            await waitQueued(m, 1)
            let b = Task.detached { () -> Void in _ = try? await m.withLockCancellable { order.mutate { $0.append("B") } } }
            await waitQueued(m, 2)
            let c = Task.detached { () -> Void in _ = try? await m.withLockCancellable { order.mutate { $0.append("C") } } }
            await waitQueued(m, 3)
            let d = Task.detached { await m.withLock { order.mutate { $0.append("D") } } }
            await waitQueued(m, 4)
            b.cancel()
            await b.value
            eq(m.queuedCount, 3, "only the cancelled waiter left")
            gate2.value = true
            await holder2.value
            await a.value
            await c.value
            await d.value
            eq(order.value, ["A", "C", "D"], "FIFO kept around a cancelled waiter")

            // An already-cancelled task never runs the body, even when the lock is free, and leaves the lock free.
            let preRan = Box(false)
            let pre = Task.detached { () -> String in
                while !Task.isCancelled { await Task.yield() }
                do {
                    try await m.withLockCancellable { preRan.value = true }
                    return "ran"
                } catch is CancellationError {
                    return "cancelled"
                } catch {
                    return "other"
                }
            }
            pre.cancel()
            let preOutcome = await pre.value
            eq(preOutcome, "cancelled", "already-cancelled task → CancellationError")
            t(!preRan.value, "already-cancelled task: body not run")
            let free: Int = await m.withLock { return 1 }
            eq(free, 1, "lock still free")

            // Plain withLock is not cancellable: a cancelled waiter still runs its body in turn (documented behaviour).
            let gate3 = Box(false)
            let holder3 = await hold(m, gate3)
            let plainSawCancel = Box<Bool?>(nil)
            let plain = Task.detached { await m.withLock { plainSawCancel.value = Task.isCancelled } }
            await waitQueued(m, 1)
            plain.cancel()
            try? await Task.sleep(nanoseconds: 20_000_000)
            eq(m.queuedCount, 1, "withLock waiter stays queued after cancellation")
            gate3.value = true
            await holder3.value
            await plain.value
            eq(plainSawCancel.value ?? false, true, "withLock: cancelled waiter ran its body (sees isCancelled)")

            // Stress: 200 cancellable waiters, half cancelled at random moments while the lock keeps changing hands. Every
            // task resumes exactly once, bodies never overlap, every non-cancelled task runs, the queue drains.
            let inside = Box(0)
            let overlap = Box(false)
            let bodies = Box(0)
            let gate4 = Box(false)
            let holder4 = await hold(m, gate4)
            var stress = [Task<String, Never>]()
            for i in 0..<200 {
                stress.append(Task.detached { () -> String in
                    do {
                        try await m.withLockCancellable {
                            inside.mutate { $0 += 1; if $0 > 1 { overlap.value = true } }
                            bodies.mutate { $0 += 1 }
                            if i % 7 == 0 { await Task.yield() }
                            inside.mutate { $0 -= 1 }
                        }
                        return "ran"
                    } catch is CancellationError {
                        return "cancelled"
                    } catch {
                        return "other"
                    }
                })
            }
            await waitQueued(m, 150)
            gate4.value = true
            for (i, task) in stress.enumerated() where i % 2 == 1 {
                task.cancel()
                if i % 10 == 1 { await Task.yield() }
            }
            await holder4.value
            var tally = [String: Int]()
            for (i, task) in stress.enumerated() {
                let r = await task.value
                tally[r, default: 0] += 1
                if i % 2 == 0 && r != "ran" { tally["evenNotRun", default: 0] += 1 }
            }
            eq((tally["ran"] ?? 0) + (tally["cancelled"] ?? 0), 200, "stress: every task resumed exactly once (\(tally))")
            eq(tally["evenNotRun"] ?? 0, 0, "stress: every non-cancelled task ran")
            eq(bodies.value, tally["ran"] ?? -1, "stress: body count = ran count")
            t(!overlap.value, "stress: bodies never overlap")
            eq(m.queuedCount, 0, "stress: queue drained")
            let last: Int = await m.withLock { return 2 }
            eq(last, 2, "stress: lock free at the end")
        }

        section("clock / background")
        runAsync {
            let a = BILMonotonicClock.millis()
            try? await Task.sleep(nanoseconds: 60_000_000)
            let b = BILMonotonicClock.millis()
            t(b - a >= 50 && b - a < 5000, "monotonic millis advance (\(b - a))")
            let onMain: Bool? = try? await BILPublicBackground.run { return Thread.isMainThread }
            eq(onMain ?? true, false, "background work off the main thread")
            let v: Int? = try? await BILPublicBackground.run { return 6 * 7 }
            eq(v ?? 0, 42, "background value")
            do {
                let _: Int = try await BILPublicBackground.run { throw BILPublicSignerFailure.engineUnavailable }
                t(false, "background error")
            } catch {
                t(error as? BILPublicSignerFailure == .engineUnavailable, "background error propagates")
            }
        }

        // MARK: - Engine contract is implementable (WP7 actor, harness fakes)

        section("engine contract")
        runAsync {
            let engine: BILPublicSignerEngining = CoreFakeEngine()
            let available = await engine.isAvailable()
            t(available, "actor conforms and is callable through the protocol")
            let h1 = try? await engine.openScan()
            let h2 = try? await engine.openScan()
            t(h1 != nil && h2 != nil && h1!.sessionId < h2!.sessionId && h1 != h2, "scan handles increase, Hashable")
            do {
                _ = try await engine.derivePublicIndex(seedHex: "00", tronScheme: nil, tronAddressCount: nil)
                t(false, "fake refuses")
            } catch let r as BILPublicSignerRefusal {
                eq(r.code, "SEED", "refusal code sanitized")
                eq(BILPublicSignerErrors.of(r).key, "PublicProtocol.err.rebuildPublicData", "SEED → rebuildPublicData")
            } catch {
                t(false, "wrong error")
            }
            do {
                _ = try await engine.scanAdd(h1!, frame: "x")
            } catch let r as BILPublicSignerRefusal {
                eq(BILPublicSignerErrors.of(r).key, "PublicProtocol.err.scanTimeout", "SCAN → scanTimeout")
            } catch {
                t(false, "wrong error")
            }
            let rp = try? await engine.reviewAndResolve(request: BILJSONObject([("a", .int(1))]), wallets: [])
            t(rp == BILPublicReviewAndPlan(review: BILJSONObject([("a", .int(1))]), plan: BILJSONObject()), "BILPublicReviewAndPlan Equatable")
        }

    }
}
