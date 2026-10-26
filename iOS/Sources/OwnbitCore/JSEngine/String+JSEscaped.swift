//  String+JSEscaped.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  How Swift strings are put into JavaScript source. Every bridge builds a JS call as text and evaluates it in a long-lived,
//  shared JS engine, so an unescaped quote in an input (an address or memo from a QR code, a pasted private key, a
//  passphrase) could inject code that rewrites `bridge.*` and leaks the next seed. Every string argument therefore goes
//  through one of these helpers. For ordinary values (hex, base58 / bech32 addresses, derivation paths, BIP39 words, JSON
//  without quotes in its values) the escaped text is byte-for-byte the input, so the JavaScript sees exactly what the app
//  always passed.

import Foundation

extension String {

    /// Escaped so it can be placed inside a single-quoted (or double-quoted) JavaScript string literal.
    /// Exact port of the app's `bil_jsEscaped`: `\` `'` `"` LF CR U+2028 U+2029 are escaped, everything else is copied
    /// unchanged, scalar by scalar. A valid mnemonic (lowercase letters / CJK / kana / hangul and spaces) is unchanged.
    public var jsEscaped: String {
        var escaped = ""
        escaped.reserveCapacity(count)
        for scalar in unicodeScalars {
            switch scalar {
            case "\\":        escaped += "\\\\"
            case "'":         escaped += "\\'"
            case "\"":        escaped += "\\\""
            case "\n":        escaped += "\\n"
            case "\r":        escaped += "\\r"
            case "\u{2028}":  escaped += "\\u2028"
            case "\u{2029}":  escaped += "\\u2029"
            default:          escaped.unicodeScalars.append(scalar)
            }
        }
        return escaped
    }
}

extension JSBridge {

    /// A complete, double-quoted JavaScript string literal (JSON string encoding), e.g. `"abc"`.
    /// Same as the app's `BILJSArg.str` / `TronJSBridge.jsQuoted` / `EthereumExtJSBridge.jsStringLiteral`.
    static func jsStringLiteral(_ value: String) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: [value], options: []),
           let array = String(data: data, encoding: .utf8), array.count >= 2 {
            return String(array.dropFirst().dropLast())
        }
        return "\"\""
    }

    /// Dictionary → JSON text (sorted keys) → JavaScript string literal; the JS side calls `JSON.parse`.
    /// Same as the app's `BILJSArg.json`. Nil when the dictionary is not valid JSON.
    static func jsJSONStringLiteral(_ dict: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(dict),
              let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return jsStringLiteral(text)
    }

    /// A JavaScript array literal of strings (JSON encoding), e.g. `["0xab","0xcd"]`. Replaces the app's
    /// `\(stringArray)` interpolation (Swift's `["0xab", "0xcd"]` description); the JavaScript value is the same.
    static func jsArrayLiteral(_ values: [String]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: values, options: []),
              let text = String(data: data, encoding: .utf8) else { return "[]" }
        return text
    }

    /// Port of the app's `Array.toJsonString()` / `Dictionary.toJsonString()`: pretty-printed JSON with every newline
    /// removed and, unless `withSpace`, every space removed (also inside values, exactly like the app). Empty string
    /// when the object is not valid JSON (the app crashed there).
    static func jsonText(_ object: Any, withSpace: Bool = false) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: .prettyPrinted),
              let text = String(data: data, encoding: .utf8) else { return "" }
        var compact = text.replacingOccurrences(of: "\n", with: "")
        if !withSpace {
            compact = compact.replacingOccurrences(of: " ", with: "")
        }
        return compact
    }

    /// Amount → integer string for JS (POSIX digits, truncated toward zero; port of the app's
    /// `BILNumberWire.integerString`). On NaN calls `failure(.resultError)` asynchronously on the main queue and returns
    /// nil: "0" or "NaN" is never passed to JavaScript.
    static func wireAmount(_ n: NSDecimalNumber, failure: @escaping (_ error: Error) -> Void) -> String? {
        if n != NSDecimalNumber.notANumber, !n.decimalValue.isNaN {
            let mode: NSDecimalNumber.RoundingMode = n.compare(NSDecimalNumber.zero) == .orderedAscending ? .up : .down
            let handler = NSDecimalNumberHandler(roundingMode: mode, scale: 0, raiseOnExactness: false,
                                                 raiseOnOverflow: false, raiseOnUnderflow: false, raiseOnDivideByZero: false)
            return n.rounding(accordingToBehavior: handler).stringValue
        }
        DispatchQueue.main.async {
            failure(JSError.resultError)
        }
        return nil
    }
}
