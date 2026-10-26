//  BILPublicText.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Public protocol (cold signer) — string access for public-protocol texts (design §3.19). The package ships no string
//  tables: every text is a key (`PublicProtocol.*`, `SecurityCenter.*`, `SendC.*` or an existing app `UI.strings` key)
//  that the host app resolves through `BILPublicText.localize` (the app looked `PublicProtocol.*` / `SecurityCenter.*` /
//  `SendC.*` up in the table named by the first key component and any other key in `UI.strings`). Default: the key
//  itself. Placeholders: `%N$@` (String) / `%N$ld` (Int), formatted without a locale (Latin digits, no grouping). Never
//  invents a text.
//

import Foundation

/// One argument of a localized text: data such as an address (`%N$@`) or a number (`%N$ld`).
public enum BILTextArg: Equatable {
    case text(String)
    case int(Int)
}

public enum BILPublicText {

    /// The host's localizer: full key → text in the app language (the app: `PublicProtocol.*` / `SecurityCenter.*` /
    /// `SendC.*` → the table named by the prefix, any other key → `UI.strings`). Set once at launch. Default: identity.
    public static var localize: (String) -> String = { $0 }

    /// The localized template of `key` (through `localize`).
    public static func string(_ key: String) -> String {
        return localize(key)
    }

    /// `String(format:)` without a locale (Latin digits): `.text` → `NSString` for `%N$@`, `.int` → `Int` for `%N$ld`.
    /// With no arguments the text is returned as it is (like Android `getString(id)`). A template whose placeholders do
    /// not fit the arguments (count / type) is never handed to `String(format:)` (that could crash on `%@` with an
    /// integer): it is returned unformatted and the mismatch is logged as a code. `%d` / `%N$d` are formatted as
    /// `%ld` / `%N$ld` (the argument is a 64-bit `Int`; plain `%d` would print only its low 32 bits — Java's `%d` prints
    /// the whole value).
    public static func format(_ key: String, _ args: [BILTextArg]) -> String {
        let raw = string(key)
        if args.isEmpty { return raw }
        guard let template = fittedTemplate(raw, args) else {
            BILPublicLog.code("text", "FORMAT_MISMATCH")
            return raw
        }
        let values: [CVarArg] = args.map { arg -> CVarArg in
            switch arg {
            case .text(let s): return s as NSString
            case .int(let n): return n
            }
        }
        return String(format: template, locale: nil, arguments: values)
    }

    // MARK: - Private

    /// `template` with every `%d` / `%N$d` widened to `%ld` / `%N$ld`, or nil unless every conversion is `%%`,
    /// `%@` / `%N$@` (needs `.text`) or `%d` / `%ld` / `%N$d` / `%N$ld` (needs `.int`), each refers to an existing
    /// argument, and positional / sequential forms are not mixed.
    private static func fittedTemplate(_ template: String, _ args: [BILTextArg]) -> String? {
        let u = Array(template.utf8)
        var widenAt = [Int]()           // byte offsets of a bare `d` conversion
        var i = 0
        var sequential = 0
        var sawPositional = false
        var sawSequential = false
        while i < u.count {
            guard u[i] == 0x25 else { // %
                i += 1
                continue
            }
            i += 1
            guard i < u.count else { return nil }
            if u[i] == 0x25 { // %%
                i += 1
                continue
            }
            var index: Int
            var digits = 0
            var n = 0
            while i < u.count && u[i] >= 0x30 && u[i] <= 0x39 && digits < 3 {
                n = n * 10 + Int(u[i] - 0x30)
                digits += 1
                i += 1
            }
            if digits > 0 {
                guard i < u.count, u[i] == 0x24, n >= 1 else { return nil } // $
                i += 1
                index = n - 1
                sawPositional = true
            } else {
                index = sequential
                sequential += 1
                sawSequential = true
            }
            guard i < u.count else { return nil }
            let wantsText: Bool
            if u[i] == 0x40 { // @
                wantsText = true
                i += 1
            } else if u[i] == 0x64 { // d
                wantsText = false
                widenAt.append(i)
                i += 1
            } else if u[i] == 0x6C, i + 1 < u.count, u[i + 1] == 0x64 { // ld
                wantsText = false
                i += 2
            } else {
                return nil
            }
            guard index < args.count else { return nil }
            switch args[index] {
            case .text: if !wantsText { return nil }
            case .int: if wantsText { return nil }
            }
        }
        if sawPositional && sawSequential { return nil }
        if widenAt.isEmpty { return template }
        var out = [UInt8]()
        out.reserveCapacity(u.count + widenAt.count)
        var from = 0
        for at in widenAt {
            out.append(contentsOf: u[from..<at])
            out.append(0x6C) // l
            from = at
        }
        out.append(contentsOf: u[from...])
        return String(decoding: out, as: UTF8.self)
    }
}
