//  ZcashTexAddressConverter.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  ZIP 320 TEX address (bech32m, hrp "tex", 20-byte key hash) → the transparent t1 address of the same key hash
//  (version 0x1C 0xB8, Base58Check). Used only to validate TEX recipients. Self-contained (own SHA-256), as in the app.

import Foundation

public final class ZcashTexAddressConverter {

    /// "" when `address` is not a valid TEX address.
    public static func texToT1(_ address: String) -> String {
        guard let decoded = Bech32m.decode(address),
              decoded.hrp == "tex",
              let pkh = convertBits(decoded.data, fromBits: 5, toBits: 8, pad: false),
              pkh.count == 20 else {
            return ""
        }

        let payload = [UInt8](arrayLiteral: 0x1C, 0xB8) + pkh
        return Base58Check.encode(payload)
    }
}

// MARK: - Bech32m

private enum Bech32m {

    private static let charset = Array("qpzry9x8gf2tvdw0s3jn54khce6mua7l")
    private static let generator: [UInt32] = [
        0x3b6a57b2,
        0x26508e6d,
        0x1ea119fa,
        0x3d4233dd,
        0x2a1462b3
    ]

    static func decode(_ bech: String) -> (hrp: String, data: [UInt8])? {
        let bech = bech.lowercased()

        guard bech.count >= 8,
              bech.count <= 90,
              let separatorIndex = bech.lastIndex(of: "1") else {
            return nil
        }

        let hrp = String(bech[..<separatorIndex])
        let dataPart = bech[bech.index(after: separatorIndex)...]

        guard !hrp.isEmpty, dataPart.count >= 6 else {
            return nil
        }

        var values: [UInt8] = []

        for char in dataPart {
            guard let index = charset.firstIndex(of: char) else {
                return nil
            }
            values.append(UInt8(index))
        }

        guard verifyChecksum(hrp: hrp, values: values) else {
            return nil
        }

        return (hrp, Array(values.dropLast(6)))
    }

    private static func verifyChecksum(hrp: String, values: [UInt8]) -> Bool {
        return polymod(hrpExpand(hrp) + values) == 0x2bc830a3
    }

    private static func hrpExpand(_ hrp: String) -> [UInt8] {
        var result: [UInt8] = []

        for scalar in hrp.unicodeScalars {
            result.append(UInt8(scalar.value >> 5))
        }

        result.append(0)

        for scalar in hrp.unicodeScalars {
            result.append(UInt8(scalar.value & 31))
        }

        return result
    }

    private static func polymod(_ values: [UInt8]) -> UInt32 {
        var chk: UInt32 = 1

        for value in values {
            let top = chk >> 25
            chk = ((chk & 0x1ffffff) << 5) ^ UInt32(value)

            for i in 0..<5 {
                if ((top >> UInt32(i)) & 1) == 1 {
                    chk ^= generator[i]
                }
            }
        }

        return chk
    }
}

// MARK: - Bit Conversion

private func convertBits(_ data: [UInt8], fromBits: Int, toBits: Int, pad: Bool) -> [UInt8]? {
    var acc = 0
    var bits = 0
    var ret: [UInt8] = []
    let maxv = (1 << toBits) - 1
    let maxAcc = (1 << (fromBits + toBits - 1)) - 1

    for value in data {
        let v = Int(value)

        if v < 0 || (v >> fromBits) != 0 {
            return nil
        }

        acc = ((acc << fromBits) | v) & maxAcc
        bits += fromBits

        while bits >= toBits {
            bits -= toBits
            ret.append(UInt8((acc >> bits) & maxv))
        }
    }

    if pad {
        if bits > 0 {
            ret.append(UInt8((acc << (toBits - bits)) & maxv))
        }
    } else {
        if bits >= fromBits {
            return nil
        }

        if ((acc << (toBits - bits)) & maxv) != 0 {
            return nil
        }
    }

    return ret
}

// MARK: - Base58Check

private enum Base58Check {

    private static let alphabet = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")

    static func encode(_ payload: [UInt8]) -> String {
        let checksum = Array(sha256(sha256(payload)).prefix(4))
        return base58Encode(payload + checksum)
    }

    private static func base58Encode(_ bytes: [UInt8]) -> String {
        var digits = [UInt8](repeating: 0, count: 1)

        for byte in bytes {
            var carry = Int(byte)

            for i in 0..<digits.count {
                carry += Int(digits[i]) << 8
                digits[i] = UInt8(carry % 58)
                carry /= 58
            }

            while carry > 0 {
                digits.append(UInt8(carry % 58))
                carry /= 58
            }
        }

        var result = ""

        for byte in bytes {
            if byte == 0 {
                result.append("1")
            } else {
                break
            }
        }

        for digit in digits.reversed() {
            result.append(alphabet[Int(digit)])
        }

        return result
    }
}

// MARK: - SHA256

private func sha256(_ data: [UInt8]) -> [UInt8] {
    var message = data
    let bitLength = UInt64(message.count * 8)

    message.append(0x80)

    while message.count % 64 != 56 {
        message.append(0x00)
    }

    message += [
        UInt8((bitLength >> 56) & 0xff),
        UInt8((bitLength >> 48) & 0xff),
        UInt8((bitLength >> 40) & 0xff),
        UInt8((bitLength >> 32) & 0xff),
        UInt8((bitLength >> 24) & 0xff),
        UInt8((bitLength >> 16) & 0xff),
        UInt8((bitLength >> 8) & 0xff),
        UInt8(bitLength & 0xff)
    ]

    var h0: UInt32 = 0x6a09e667
    var h1: UInt32 = 0xbb67ae85
    var h2: UInt32 = 0x3c6ef372
    var h3: UInt32 = 0xa54ff53a
    var h4: UInt32 = 0x510e527f
    var h5: UInt32 = 0x9b05688c
    var h6: UInt32 = 0x1f83d9ab
    var h7: UInt32 = 0x5be0cd19

    let k: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
        0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
        0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
        0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
        0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
        0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
        0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
        0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
        0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
    ]

    for chunkStart in stride(from: 0, to: message.count, by: 64) {
        let chunk = Array(message[chunkStart..<chunkStart + 64])
        var w = [UInt32](repeating: 0, count: 64)

        for i in 0..<16 {
            let j = i * 4
            w[i] =
                UInt32(chunk[j]) << 24 |
                UInt32(chunk[j + 1]) << 16 |
                UInt32(chunk[j + 2]) << 8 |
                UInt32(chunk[j + 3])
        }

        for i in 16..<64 {
            let s0 = rotateRight(w[i - 15], 7) ^ rotateRight(w[i - 15], 18) ^ (w[i - 15] >> 3)
            let s1 = rotateRight(w[i - 2], 17) ^ rotateRight(w[i - 2], 19) ^ (w[i - 2] >> 10)
            w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
        }

        var a = h0
        var b = h1
        var c = h2
        var d = h3
        var e = h4
        var f = h5
        var g = h6
        var h = h7

        for i in 0..<64 {
            let s1 = rotateRight(e, 6) ^ rotateRight(e, 11) ^ rotateRight(e, 25)
            let ch = (e & f) ^ ((~e) & g)
            let temp1 = h &+ s1 &+ ch &+ k[i] &+ w[i]
            let s0 = rotateRight(a, 2) ^ rotateRight(a, 13) ^ rotateRight(a, 22)
            let maj = (a & b) ^ (a & c) ^ (b & c)
            let temp2 = s0 &+ maj

            h = g
            g = f
            f = e
            e = d &+ temp1
            d = c
            c = b
            b = a
            a = temp1 &+ temp2
        }

        h0 = h0 &+ a
        h1 = h1 &+ b
        h2 = h2 &+ c
        h3 = h3 &+ d
        h4 = h4 &+ e
        h5 = h5 &+ f
        h6 = h6 &+ g
        h7 = h7 &+ h
    }

    var digest: [UInt8] = []

    for h in [h0, h1, h2, h3, h4, h5, h6, h7] {
        digest.append(UInt8((h >> 24) & 0xff))
        digest.append(UInt8((h >> 16) & 0xff))
        digest.append(UInt8((h >> 8) & 0xff))
        digest.append(UInt8(h & 0xff))
    }

    return digest
}

private func rotateRight(_ value: UInt32, _ bits: UInt32) -> UInt32 {
    return (value >> bits) | (value << (32 - bits))
}
