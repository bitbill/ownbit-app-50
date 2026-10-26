//  BILPublicLog.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Public protocol (cold signer) — the only log sink of public-protocol code (C-KEY-5, C-LOG, design §1.7). A line
//  carries an area, a sanitized `[A-Z0-9_]{1,80}` code and / or an error's type name — never requests, frames, seeds,
//  passwords, addresses, amounts, public indexes, plans, results, engine messages or record contents.
//  Output goes to `BILPublicLog.sink`, which the host app sets (the app forwarded it to its DEBUG-only `bil_errorPrint`);
//  nil (the default) drops every line.
//

import Foundation

public enum BILPublicLog {

    /// Where the lines go (one already formatted line per call). Set once at launch, before any public-protocol work;
    /// nil = no logging. The lines never carry secrets or payload data (see above).
    public static var sink: ((String) -> Void)?

    /// "PublicProtocol <area>: <sanitized code>".
    static func code(_ area: StaticString, _ code: String) {
        emit(area, BILPublicSignerRefusal.sanitize(code))
    }

    /// "PublicProtocol <area>: <error type name>[ <sanitized code>]" — the code only for the public-protocol error types
    /// that carry one; never the error's message or payload.
    static func failure(_ area: StaticString, _ error: Error) {
        var text = typeName(error)
        if let c = knownCode(error) {
            text += " " + BILPublicSignerRefusal.sanitize(c)
        }
        emit(area, text)
    }

    // MARK: - Private

    private static func emit(_ area: StaticString, _ detail: String) {
        guard let sink = sink else { return }
        let line = "PublicProtocol " + area.description + ": " + detail
        sink(line)
    }

    private static func knownCode(_ error: Error) -> String? {
        if let e = error as? BILPublicSignerRefusal { return e.code }
        if let e = error as? BILPublicSignerFailure { return e.code }
        if let e = error as? BILPublicSignError { return e.code }
        if error is BILPublicTimeout.Expired { return "TIMEOUT" }
        return nil
    }

    /// `String(describing: type(of: error))`, limited to identifier-like characters (≤ 120).
    private static func typeName(_ error: Error) -> String {
        let raw = String(describing: type(of: error))
        var out = [UInt8]()
        for b in raw.utf8 {
            switch b {
            case 0x41...0x5A, 0x61...0x7A, 0x30...0x39, 0x5F, 0x2E, 0x3C, 0x3E, 0x2C, 0x20:
                out.append(b)
            default:
                continue
            }
            if out.count == 120 { break }
        }
        return out.isEmpty ? "Error" : String(decoding: out, as: UTF8.self)
    }
}
