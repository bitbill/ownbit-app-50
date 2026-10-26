//  BILPublicHash.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Public protocol (cold signer): the hashes the native pre/post checks, the offline-sign records and the public index
//  use (design §3.2; R5 §3, §9). Pure: Foundation + CryptoKit + CryptoSwift only (macOS harness: tests/crypto/).
//  Never logs anything. (The app's `md5Hex`, used only for old wallets' md5 `seedHash`, is not part of this package.)
//

import Foundation
import CryptoKit
import CryptoSwift

enum BILPublicHash {

    /// SHA-256 (CryptoKit).
    static func sha256(_ d: [UInt8]) -> [UInt8] {
        return Array(CryptoKit.SHA256.hash(data: d))
    }

    /// Lower-case hex of SHA-256(d).
    static func sha256Hex(_ d: [UInt8]) -> String {
        return hex(sha256(d))
    }

    /// Lower-case hex of SHA-256 of the UTF-8 bytes of `s` (the same value as CryptoSwift `String.sha256()`, which the
    /// app's `seedHash` uses).
    static func sha256Hex(utf8 s: String) -> String {
        return sha256Hex(Array(s.utf8))
    }

    /// SHA-256(SHA-256(d)).
    static func sha256d(_ d: [UInt8]) -> [UInt8] {
        return sha256(sha256(d))
    }

    /// BIP-340 tagged hash: SHA-256(SHA-256(tag) ‖ SHA-256(tag) ‖ d); `tag` as UTF-8 (every tag in use is ASCII,
    /// e.g. "TapTweak", which Android encodes as US-ASCII).
    static func taggedHash(_ tag: String, _ d: [UInt8]) -> [UInt8] {
        let t = sha256(Array(tag.utf8))
        return sha256(t + t + d)
    }

    /// Keccak-256 (the original Keccak padding used by Ethereum / TRON, not FIPS SHA3-256); CryptoSwift.
    static func keccak256(_ d: [UInt8]) -> [UInt8] {
        return CryptoSwift.SHA3(variant: .keccak256).calculate(for: d)
    }

    /// RIPEMD-160(SHA-256(d)).
    static func hash160(_ d: [UInt8]) -> [UInt8] {
        return BILRipemd160.hash(sha256(d))
    }

    /// CRC-32 (IEEE 802.3, reflected, polynomial 0xEDB88320, init and final XOR 0xFFFFFFFF); CryptoSwift.
    static func crc32(_ d: [UInt8]) -> UInt32 {
        return CryptoSwift.Checksum.crc32(d)
    }

    /// EIP-191 personal-message digest: keccak256("\u{19}Ethereum Signed Message:\n" + decimal byte count ‖ m).
    static func eip191Digest(_ m: [UInt8]) -> [UInt8] {
        return keccak256(Array("\u{19}Ethereum Signed Message:\n".utf8) + Array(String(m.count).utf8) + m)
    }

    /// TIP-191 TRON message digest: keccak256("\u{19}TRON Signed Message:\n" + decimal byte count ‖ m)
    /// (Android `PublicSignVerifier.tip191Digest`, engine `tron.js`).
    static func tip191Digest(_ m: [UInt8]) -> [UInt8] {
        return keccak256(Array("\u{19}TRON Signed Message:\n".utf8) + Array(String(m.count).utf8) + m)
    }

    // MARK: - Private

    private static let hexDigits: [UInt8] = Array("0123456789abcdef".utf8)

    private static func hex(_ bytes: [UInt8]) -> String {
        var out = [UInt8]()
        out.reserveCapacity(bytes.count * 2)
        for b in bytes {
            out.append(hexDigits[Int(b >> 4)])
            out.append(hexDigits[Int(b & 0x0F)])
        }
        return String(decoding: out, as: UTF8.self)
    }
}
