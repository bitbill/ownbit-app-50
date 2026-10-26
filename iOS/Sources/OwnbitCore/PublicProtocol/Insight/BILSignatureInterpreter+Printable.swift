//  BILSignatureInterpreter+Printable.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  The one helper of the app's Security Center signature interpreter (`BILSignatureInterpreter+Message.swift`
//  `printableText`) that the public-protocol D43 card input uses (`BILPublicSignInsight.personalSignMessage`), copied
//  verbatim. The interpreter itself (the D43 reading with the local known-contract library) is not part of this
//  package: the host passes it as `BILPublicSignCoordinator.Dependencies.interpret`.
//

import Foundation

/// Namespace of the app's interpreter; only `printableText` is in this package.
enum BILSignatureInterpreter {

    /// The bytes as text when they are valid UTF-8 without NUL and at most 2 % control characters (C0 except tab / LF /
    /// CR, DEL, C1, U+FFFD); else nil.
    static func printableText(_ bytes: [UInt8]) -> String? {
        guard !bytes.isEmpty, let s = String(bytes: bytes, encoding: .utf8) else { return nil }
        var control = 0
        var total = 0
        for u in s.unicodeScalars {
            total += 1
            let v = u.value
            if v == 0 { return nil }
            if (v < 0x20 && v != 0x09 && v != 0x0a && v != 0x0d) || v == 0x7f || (v >= 0x80 && v < 0xa0) || v == 0xfffd { control += 1 }
        }
        return control * 50 <= total ? s : nil
    }
}
