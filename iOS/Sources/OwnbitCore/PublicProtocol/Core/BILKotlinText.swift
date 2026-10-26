//  BILKotlinText.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Public protocol (cold signer) — Kotlin-compatible text helpers (R4 §3). Android counts and trims in UTF-16 code
//  units with Kotlin's `Char.isWhitespace`; every public-protocol limit and trim must do the same, never Swift
//  `Character` semantics or Foundation's `.whitespacesAndNewlines` (which includes U+0085 and excludes U+001C–U+001F).
//  Pure Foundation.
//

import Foundation

enum BILKotlinText {

    /// Kotlin `Char.isWhitespace()` = `Character.isWhitespace || Character.isSpaceChar`: U+0009–U+000D,
    /// U+001C–U+001F, general category Zs (U+0020, U+00A0, U+1680, U+2000–U+200A, U+202F, U+205F, U+3000),
    /// U+2028 (Zl), U+2029 (Zp). Not U+0085, not U+180E, not U+200B, not U+FEFF.
    static func isWhitespace(_ u: UInt16) -> Bool {
        switch u {
        case 0x0009...0x000D, 0x001C...0x001F, 0x0020, 0x00A0, 0x1680, 0x2000...0x200A,
             0x2028, 0x2029, 0x202F, 0x205F, 0x3000:
            return true
        default:
            return false
        }
    }

    /// Kotlin `String.trim()`: drops leading and trailing Kotlin whitespace (UTF-16 units).
    static func trim(_ s: String) -> String {
        let u = Array(s.utf16)
        var lo = 0
        var hi = u.count
        while lo < hi && isWhitespace(u[lo]) { lo += 1 }
        while hi > lo && isWhitespace(u[hi - 1]) { hi -= 1 }
        if lo == 0 && hi == u.count { return s }
        // Whitespace units are never surrogates, so the cut is always on a scalar boundary.
        return String(decoding: u[lo..<hi], as: UTF16.self)
    }

    /// Kotlin `String.lines()`: splits on "\r\n", "\n" and "\r" only (not U+2028 / U+0085); keeps empty lines,
    /// including a trailing one ("a\n" → ["a", ""], "" → [""]).
    static func lines(_ s: String) -> [String] {
        let u = Array(s.utf16)
        var out = [String]()
        var start = 0
        var i = 0
        while i < u.count {
            if u[i] == 0x0D {
                out.append(String(decoding: u[start..<i], as: UTF16.self))
                i += (i + 1 < u.count && u[i + 1] == 0x0A) ? 2 : 1
                start = i
            } else if u[i] == 0x0A {
                out.append(String(decoding: u[start..<i], as: UTF16.self))
                i += 1
                start = i
            } else {
                i += 1
            }
        }
        out.append(String(decoding: u[start..<u.count], as: UTF16.self))
        return out
    }

    /// Kotlin `String.split(separator)` (one non-empty delimiter, case-sensitive, no limit): exact code-unit matching,
    /// keeps empty pieces including trailing ones ("a,b," → ["a", "b", ""]). An empty separator returns `[s]`
    /// (Kotlin would split between every UTF-16 unit; no public-protocol caller does that).
    static func split(_ s: String, separator: String) -> [String] {
        let sep = Array(separator.utf16)
        guard !sep.isEmpty else { return [s] }
        let u = Array(s.utf16)
        var out = [String]()
        var start = 0
        var i = 0
        while i + sep.count <= u.count {
            var match = true
            for k in 0..<sep.count where u[i + k] != sep[k] {
                match = false
                break
            }
            if match {
                out.append(String(decoding: u[start..<i], as: UTF16.self))
                i += sep.count
                start = i
            } else {
                i += 1
            }
        }
        out.append(String(decoding: u[start..<u.count], as: UTF16.self))
        return out
    }

    /// Kotlin `String.length`: UTF-16 units.
    static func length(_ s: String) -> Int {
        return s.utf16.count
    }

    /// The first `n` UTF-16 units, never splitting a surrogate pair (a pair that would be cut is dropped whole).
    static func prefix(_ s: String, utf16 n: Int) -> String {
        let u = s.utf16
        if u.count <= n { return s }
        if n <= 0 { return "" }
        let units = Array(u)
        let end = (units[n - 1] >= 0xD800 && units[n - 1] <= 0xDBFF) ? n - 1 : n
        return String(decoding: units[0..<end], as: UTF16.self)
    }

    /// Kotlin `Regex.matchEntire` / `matches`: the whole string must match (with backtracking into alternatives, unlike
    /// an anchored first match). Implemented by matching `\A(?:pattern)\z` with the expression's options; ICU `$`
    /// alone would also match before a final line terminator.
    static func wholeMatch(_ re: NSRegularExpression, _ s: String) -> NSTextCheckingResult? {
        guard let whole = wholeExpression(for: re) else { return nil }
        let range = NSRange(location: 0, length: s.utf16.count)
        guard let m = whole.firstMatch(in: s, options: [.anchored], range: range),
              m.range.location == 0, m.range.length == range.length else { return nil }
        return m
    }

    // MARK: - Private

    private static let wholeCache: NSCache<NSString, NSRegularExpression> = {
        let c = NSCache<NSString, NSRegularExpression>()
        c.countLimit = 128
        return c
    }()

    private static func wholeExpression(for re: NSRegularExpression) -> NSRegularExpression? {
        let key = "\(re.options.rawValue)\u{0}\(re.pattern)" as NSString
        if let cached = wholeCache.object(forKey: key) {
            return cached
        }
        // In comment mode (option `.allowCommentsAndWhitespace` or an inline `(?x)`) a trailing `# comment` swallows
        // the appended `)\z` and the plain wrapper does not compile; it is then retried with the tail on its own line
        // (a newline ends the comment and is ignored as whitespace there). Outside comment mode nothing ends at a
        // newline, so the retry can only succeed where it is needed.
        let head = "\\A(?:" + re.pattern
        guard let whole = (try? NSRegularExpression(pattern: head + ")\\z", options: re.options))
            ?? (try? NSRegularExpression(pattern: head + "\n)\\z", options: re.options)) else {
            // A valid pattern that cannot be anchored (e.g. an unterminated `\Q`): fail closed, loudly in DEBUG.
            assertionFailure("BILKotlinText.wholeMatch: pattern cannot be anchored")
            return nil
        }
        wholeCache.setObject(whole, forKey: key)
        return whole
    }
}
