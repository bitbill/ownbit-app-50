//  JSEscapedTests.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  `String.jsEscaped` (the app's `bil_jsEscaped`) and the JSON literal helpers: exact output, JS round trips, and that an
//  injection string stays data.

import Foundation
import JavaScriptCore
import XCTest
@testable import OwnbitCore

final class JSEscapedTests: XCTestCase {

    func testEscapesExactlyTheSevenCharacters() {
        XCTAssertEqual("it's".jsEscaped, "it\\'s")
        XCTAssertEqual("a\"b".jsEscaped, "a\\\"b")
        XCTAssertEqual("a\\b".jsEscaped, "a\\\\b")
        XCTAssertEqual("end\\".jsEscaped, "end\\\\")
        XCTAssertEqual("l1\nl2".jsEscaped, "l1\\nl2")
        XCTAssertEqual("l1\r\nl2".jsEscaped, "l1\\r\\nl2")
        XCTAssertEqual("a\u{2028}b".jsEscaped, "a\\u2028b")
        XCTAssertEqual("a\u{2029}b".jsEscaped, "a\\u2029b")
        XCTAssertEqual("'); throw new Error('x'); ('".jsEscaped, "\\'); throw new Error(\\'x\\'); (\\'")
        XCTAssertEqual("\\'".jsEscaped, "\\\\\\'")
    }

    func testOrdinaryValuesAreUnchanged() {
        let values = [
            PassphraseVectors.abandon,
            "的 一 是 在 不 了 有 和 人 这 中 大",
            "c55257c360c07c72029aebc1b53c05ed0362ada38ead3e3e9efa3708e53495531f09a6987599d18264c1e1c92f2cf141630c7a3c4ab7c81b2f001698e7463b04",
            "xpub6DoiNh58QzMChactog5nemSuW95GCoQVZKanvH8XhGyXnvo7MCTWHwGZuAArsoU7DRbzRWitbMrXJztp6ffyo6dVY19Bv5igj1EgjhJHAKi",
            "bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu",
            "0x9858EfFD232B4033E47d90003D41EC34EcaEda94",
            "TAyDUYP5rcf56xFwrg8cU1qQwvnWpkeapM",
            "tab\tstays", "\u{1F511} emoji", "",
        ]
        for value in values {
            XCTAssertEqual(value.jsEscaped, value)
        }
    }

    /// Every escaped string, put in a single- or double-quoted literal, gives back exactly the original in JavaScript.
    func testRoundTripThroughJavaScriptCore() throws {
        let context = try XCTUnwrap(JSContext())
        let samples = [
            "plain", "it's", "a\"b", "back\\slash", "trailing\\", "\\x41\\u0041", "l1\nl2\rl3\r\n",
            "a\u{2028}b\u{2029}c", "'); throw new Error('x'); ('", "\"); throw new Error(\"x\"); (\"",
            "</script><script>alert(1)</script>", "nul\u{0}inside", "\u{FEFF}bom", "\u{1F680}\u{79D8}\u{5BC6}",
            "m/44'/60'/0'/0/0", "U\u{308}ni\u{308}co\u{308}de", "\t\u{0B}\u{0C}",
        ]
        for sample in samples {
            let single = context.evaluateScript("'\(sample.jsEscaped)'")
            XCTAssertEqual(single?.isString, true, sample.debugDescription)
            XCTAssertEqual(single?.toString(), sample, sample.debugDescription)
            let double = context.evaluateScript("\"\(sample.jsEscaped)\"")
            XCTAssertEqual(double?.toString(), sample, sample.debugDescription)
            let literal = context.evaluateScript(JSBridge.jsStringLiteral(sample))
            XCTAssertEqual(literal?.toString(), sample, sample.debugDescription)
        }
    }

    /// The injection string reaches the function as one argument and runs nothing.
    func testInjectionStaysData() throws {
        let context = try XCTUnwrap(JSContext())
        context.evaluateScript("var hit = false; var bridge = { echo: function (a, b) { return a + '|' + b; } };")
        let payload = "'); hit = true; ('"
        let result = context.evaluateScript("bridge.echo('\(payload.jsEscaped)', 'second')")
        XCTAssertEqual(result?.toString(), payload + "|second")
        XCTAssertEqual(context.evaluateScript("hit")?.toBool(), false)

        let doublePayload = "\"); hit = true; (\""
        let result2 = context.evaluateScript("bridge.echo(\"\(doublePayload.jsEscaped)\", \(JSBridge.jsStringLiteral(doublePayload)))")
        XCTAssertEqual(result2?.toString(), doublePayload + "|" + doublePayload)
        XCTAssertEqual(context.evaluateScript("hit")?.toBool(), false)
    }

    func testJSONHelpers() throws {
        // toJsonString port: compact, spaces removed
        XCTAssertEqual(JSBridge.jsonText(["02ab", "03cd"]), "[\"02ab\",\"03cd\"]")
        let dict = JSBridge.jsonText(["owners": ["0xa", "0xb"], "required": 2] as [String: Any])
        let parsed = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(dict.utf8)) as? [String: Any])
        XCTAssertEqual(parsed["owners"] as? [String], ["0xa", "0xb"])
        XCTAssertEqual(parsed["required"] as? Int, 2)
        XCTAssertFalse(dict.contains(" ") || dict.contains("\n"))

        // array literal = the same JS value as Swift's ["a", "b"] description
        let context = try XCTUnwrap(JSContext())
        let array = context.evaluateScript("(\(JSBridge.jsArrayLiteral(["0xa", "it's", "q\""])))")
        XCTAssertEqual(array?.toArray() as? [String], ["0xa", "it's", "q\""])

        // JSON object literal for the XRP / XLM functions: JS gets the JSON text, parses it back
        let literal = try XCTUnwrap(JSBridge.jsJSONStringLiteral(["memo": "it's \"x\"", "n": 1]))
        let roundTrip = context.evaluateScript("JSON.parse(\(literal)).memo")
        XCTAssertEqual(roundTrip?.toString(), "it's \"x\"")
    }

    func testWireAmount() {
        let failed = expectation(description: "NaN fails")
        XCTAssertEqual(JSBridge.wireAmount(NSDecimalNumber(string: "1.9"), failure: { _ in XCTFail("no failure") }), "1")
        XCTAssertEqual(JSBridge.wireAmount(NSDecimalNumber(string: "-1.5"), failure: { _ in XCTFail("no failure") }), "-1")
        XCTAssertEqual(JSBridge.wireAmount(NSDecimalNumber(string: "1000000000000000000000"), failure: { _ in XCTFail("no failure") }), "1000000000000000000000")
        XCTAssertNil(JSBridge.wireAmount(NSDecimalNumber.notANumber, failure: { _ in failed.fulfill() }))
        wait(for: [failed], timeout: 5)
    }

    func testZcashTexToT1() {
        // ZIP 320 example
        XCTAssertEqual(ZcashTexAddressConverter.texToT1("tex1s2rt77ggv6q989lr49rkgzmh5slsksa9khdgte"), "t1VmmGiyjVNeCjxDZzg7vZmd99WyzVby9yC")
        XCTAssertEqual(ZcashTexAddressConverter.texToT1("tex1s2rt77ggv6q989lr49rkgzmh5slsksa9khdgtf"), "")
        XCTAssertEqual(ZcashTexAddressConverter.texToT1("t1VmmGiyjVNeCjxDZzg7vZmd99WyzVby9yC"), "")
    }
}
