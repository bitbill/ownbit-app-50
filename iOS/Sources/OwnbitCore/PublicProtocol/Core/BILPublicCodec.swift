//  BILPublicCodec.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Public protocol (cold signer) — byte codecs: strict hex, Base58Check (Bitcoin alphabet), TRON base58 ↔ `41…` hex,
//  strict padded Base64. Pure Foundation + CryptoKit (SHA-256 for the checksums); no dependency on the Crypto WP.
//

import Foundation
import CryptoKit

enum BILPublicHex {

    /// Even length, `[0-9a-fA-F]` only, no prefix / whitespace ("" → []).
    static func decode(_ s: String) -> [UInt8]? {
        let u = Array(s.utf8)
        guard u.count % 2 == 0 else { return nil }
        var out = [UInt8]()
        out.reserveCapacity(u.count / 2)
        var i = 0
        while i < u.count {
            guard let hi = nibble(u[i]), let lo = nibble(u[i + 1]) else { return nil }
            out.append(hi << 4 | lo)
            i += 2
        }
        return out
    }

    /// Drops one leading "0x" / "0X", then `decode`.
    static func decodeOptional0x(_ s: String) -> [UInt8]? {
        if BILPublicHex.hasASCIIPrefix(s, "0x") || BILPublicHex.hasASCIIPrefix(s, "0X") {
            return decode(String(decoding: s.utf8.dropFirst(2), as: UTF8.self))
        }
        return decode(s)
    }

    /// Lower-case hex.
    static func encode(_ bytes: [UInt8]) -> String {
        var out = [UInt8]()
        out.reserveCapacity(bytes.count * 2)
        for b in bytes {
            out.append(digits[Int(b >> 4)])
            out.append(digits[Int(b & 0x0F)])
        }
        return String(decoding: out, as: UTF8.self)
    }

    /// Android `PublicSignVerifier.sameHex`: removes a "0x" prefix, then a "0X" prefix, and compares with the lower-case
    /// hex of `bytes` ignoring case. nil → false.
    static func sameHex(_ text: String?, _ bytes: [UInt8]) -> Bool {
        guard var hex = text else { return false }
        if hasASCIIPrefix(hex, "0x") { hex = String(decoding: hex.utf8.dropFirst(2), as: UTF8.self) }
        if hasASCIIPrefix(hex, "0X") { hex = String(decoding: hex.utf8.dropFirst(2), as: UTF8.self) }
        let expected = Array(encode(bytes).utf8)
        let actual = Array(hex.utf8)
        guard actual.count == expected.count else { return false }
        for i in 0..<actual.count {
            var c = actual[i]
            if c >= 0x41 && c <= 0x5A { c += 0x20 }   // ASCII upper → lower
            if c != expected[i] { return false }
        }
        return true
    }

    /// Code-unit prefix test (Kotlin `startsWith`), not Swift's `Character`-based `hasPrefix`.
    static func hasASCIIPrefix(_ s: String, _ prefix: String) -> Bool {
        return s.utf8.starts(with: prefix.utf8)
    }

    private static let digits: [UInt8] = Array("0123456789abcdef".utf8)

    private static func nibble(_ c: UInt8) -> UInt8? {
        switch c {
        case 0x30...0x39: return c - 0x30
        case 0x41...0x46: return c - 0x41 + 10
        case 0x61...0x66: return c - 0x61 + 10
        default: return nil
        }
    }
}

enum BILBase58Check {

    /// Base58 of `payload ‖ sha256d(payload)[0..<4]`.
    static func encode(_ payload: [UInt8]) -> String {
        return BILBase58.encode(payload + checksum(payload))
    }

    /// The payload without its checksum; nil on a bad character, fewer than 4 bytes or a wrong checksum.
    static func decode(_ text: String) -> [UInt8]? {
        guard let raw = BILBase58.decode(text), raw.count >= 4 else { return nil }
        let payload = Array(raw[0..<(raw.count - 4)])
        guard Array(raw[(raw.count - 4)...]) == checksum(payload) else { return nil }
        return payload
    }

    static func checksum(_ payload: [UInt8]) -> [UInt8] {
        let first = Array(SHA256.hash(data: Data(payload)))
        let second = Array(SHA256.hash(data: Data(first)))
        return Array(second[0..<4])
    }
}

/// Bitcoin-alphabet Base58 (Android `core/chain/.../tron/AccountChainSupport.kt` `Base58`).
enum BILBase58 {

    private static let alphabet: [UInt8] = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz".utf8)

    private static let indexes: [Int8] = {
        var t = [Int8](repeating: -1, count: 128)
        for (i, c) in alphabet.enumerated() {
            t[Int(c)] = Int8(i)
        }
        return t
    }()

    static func encode(_ bytes: [UInt8]) -> String {
        if bytes.isEmpty { return "" }
        var zeros = 0
        while zeros < bytes.count && bytes[zeros] == 0 { zeros += 1 }
        // Base-58 digits, little-endian.
        var digits = [UInt8]()
        digits.reserveCapacity(bytes.count * 138 / 100 + 1)
        for b in bytes[zeros...] {
            var carry = Int(b)
            for j in 0..<digits.count {
                carry += Int(digits[j]) << 8
                digits[j] = UInt8(carry % 58)
                carry /= 58
            }
            while carry > 0 {
                digits.append(UInt8(carry % 58))
                carry /= 58
            }
        }
        var out = [UInt8](repeating: alphabet[0], count: zeros)
        for d in digits.reversed() {
            out.append(alphabet[Int(d)])
        }
        return String(decoding: out, as: UTF8.self)
    }

    /// nil on an invalid character ("" → []).
    static func decode(_ text: String) -> [UInt8]? {
        let chars = Array(text.utf8)
        if chars.isEmpty { return [] }
        var zeros = 0
        while zeros < chars.count && chars[zeros] == alphabet[0] { zeros += 1 }
        // Base-256 bytes, little-endian.
        var bytes = [UInt8]()
        bytes.reserveCapacity(chars.count * 733 / 1000 + 1)
        for c in chars {
            guard c < 128, indexes[Int(c)] >= 0 else { return nil }
            var carry = Int(indexes[Int(c)])
            for j in 0..<bytes.count {
                carry += Int(bytes[j]) * 58
                bytes[j] = UInt8(carry & 0xFF)
                carry >>= 8
            }
            while carry > 0 {
                bytes.append(UInt8(carry & 0xFF))
                carry >>= 8
            }
        }
        return [UInt8](repeating: 0, count: zeros) + bytes.reversed()
    }
}

enum BILTronAddressCodec {

    /// The base58check `T…` form of a 42-hex `41…` address (an optional "0x" / "0X" prefix is dropped); nil otherwise.
    static func base58(fromHex41 hex: String) -> String? {
        guard let payload = BILPublicHex.decodeOptional0x(hex), payload.count == 21, payload[0] == 0x41 else {
            return nil
        }
        return BILBase58Check.encode(payload)
    }

    /// Android `TronAddressCodec.toBase58` (display text of a protobuf owner address, `PublicSignPolicy.tronOwnerRefusal`:
    /// `base58(anyHex21: owner) ?? owner`): the base58check form of **any** 21-byte payload, whatever its version byte;
    /// a "0x" prefix, then a "0X" prefix, is dropped (Android `hexToBytesOrNull`); nil unless 21 bytes of ASCII hex.
    /// `base58(fromHex41:)` stays the strict `41…` form.
    static func base58(anyHex21 hex: String) -> String? {
        var s = hex
        if BILPublicHex.hasASCIIPrefix(s, "0x") { s = String(decoding: s.utf8.dropFirst(2), as: UTF8.self) }
        if BILPublicHex.hasASCIIPrefix(s, "0X") { s = String(decoding: s.utf8.dropFirst(2), as: UTF8.self) }
        guard let payload = BILPublicHex.decode(s), payload.count == 21 else {
            return nil
        }
        return BILBase58Check.encode(payload)
    }

    /// Lower-case `41…` hex of a 34-character `T…` base58check address (25 bytes, version 0x41, valid checksum);
    /// nil otherwise.
    static func hex41(fromBase58 address: String) -> String? {
        guard address.utf16.count == 34, BILPublicHex.hasASCIIPrefix(address, "T"),
              let payload = BILBase58Check.decode(address), payload.count == 21, payload[0] == 0x41 else {
            return nil
        }
        return BILPublicHex.encode(payload)
    }

    static func isValid(_ address: String) -> Bool {
        return hex41(fromBase58: address) != nil
    }
}

enum BILBase64Strict {

    /// Strict padded Base64 (the engine's `b64`, Android `SignatureUrCodec.base64`):
    /// `^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$` over the whole text, then decoded.
    static func decode(_ s: String) -> [UInt8]? {
        let u = Array(s.utf8)
        guard u.count % 4 == 0 else { return nil }
        for (i, c) in u.enumerated() {
            if isAlphabet(c) { continue }
            // '=' only as the last one or two characters, never at the start of a 4-character group.
            guard c == 0x3D else { return nil }
            let fromEnd = u.count - i
            if fromEnd == 1 { continue }
            if fromEnd == 2 && u[u.count - 1] == 0x3D { continue }
            return nil
        }
        guard let data = Data(base64Encoded: s) else { return nil }
        return [UInt8](data)
    }

    static func encode(_ bytes: [UInt8]) -> String {
        return Data(bytes).base64EncodedString()
    }

    private static func isAlphabet(_ c: UInt8) -> Bool {
        switch c {
        case 0x41...0x5A, 0x61...0x7A, 0x30...0x39, 0x2B, 0x2F: return true
        default: return false
        }
    }
}
