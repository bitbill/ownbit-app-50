//  Data+Hex.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT

import Foundation

extension Data {

    /// Parses a hex string. Accepts upper- or lowercase digits and an optional `0x` / `0X` prefix.
    /// Returns nil for an odd number of digits or any non-hex character (no whitespace, no signs).
    /// An empty string (or a bare `0x`) gives empty data.
    public init?(hexString: String) {
        var chars = Array(hexString.utf8)[...]
        if chars.count >= 2, chars[chars.startIndex] == UInt8(ascii: "0"),
           chars[chars.startIndex + 1] == UInt8(ascii: "x") || chars[chars.startIndex + 1] == UInt8(ascii: "X") {
            chars = chars.dropFirst(2)
        }
        guard chars.count % 2 == 0 else { return nil }
        var out = Data(capacity: chars.count / 2)
        var i = chars.startIndex
        while i < chars.endIndex {
            guard let high = Data.hexNibble(chars[i]), let low = Data.hexNibble(chars[i + 1]) else { return nil }
            out.append(high << 4 | low)
            i += 2
        }
        self = out
    }

    /// Lowercase hex, two digits per byte, no prefix.
    public var hexString: String {
        let digits: [UInt8] = Array("0123456789abcdef".utf8)
        var chars = [UInt8]()
        chars.reserveCapacity(count * 2)
        for b in self {
            chars.append(digits[Int(b >> 4)])
            chars.append(digits[Int(b & 0x0f)])
        }
        return String(decoding: chars, as: UTF8.self)
    }

    private static func hexNibble(_ c: UInt8) -> UInt8? {
        switch c {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): return c - UInt8(ascii: "0")
        case UInt8(ascii: "a")...UInt8(ascii: "f"): return c - UInt8(ascii: "a") + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"): return c - UInt8(ascii: "A") + 10
        default: return nil
        }
    }
}
