//  BILRipemd160.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Public protocol (cold signer): RIPEMD-160 for the native PSBT checks (`hash160` of nested-SegWit redeem scripts,
//  R5 §3.4). iOS has no native RIPEMD-160 (R5 §9), so this is a plain implementation of the reference algorithm
//  (Dobbertin, Bosselaers, Preneel 1996). Public data only; pure Foundation (macOS harness: tests/crypto/).
//

import Foundation

enum BILRipemd160 {

    /// RIPEMD-160 of `d` (20 bytes).
    static func hash(_ d: [UInt8]) -> [UInt8] {
        var h0: UInt32 = 0x6745_2301
        var h1: UInt32 = 0xEFCD_AB89
        var h2: UInt32 = 0x98BA_DCFE
        var h3: UInt32 = 0x1032_5476
        var h4: UInt32 = 0xC3D2_E1F0

        // MD4-style padding: 0x80, zeros up to 56 mod 64, then the bit length as a little-endian UInt64.
        var message = d
        let bitLength = UInt64(d.count) &* 8
        message.append(0x80)
        while message.count % 64 != 56 { message.append(0) }
        for i in 0..<8 { message.append(UInt8(truncatingIfNeeded: bitLength >> (8 * UInt64(i)))) }

        var x = [UInt32](repeating: 0, count: 16)
        var offset = 0
        while offset < message.count {
            for i in 0..<16 {
                let b = offset + 4 * i
                x[i] = UInt32(message[b]) | (UInt32(message[b + 1]) << 8) | (UInt32(message[b + 2]) << 16) | (UInt32(message[b + 3]) << 24)
            }
            var al = h0, bl = h1, cl = h2, dl = h3, el = h4
            var ar = h0, br = h1, cr = h2, dr = h3, er = h4
            for j in 0..<80 {
                let round = j >> 4
                var t = rotl(al &+ f(round, bl, cl, dl) &+ x[rl[j]] &+ kl[round], sl[j]) &+ el
                al = el; el = dl; dl = rotl(cl, 10); cl = bl; bl = t
                t = rotl(ar &+ f(4 - round, br, cr, dr) &+ x[rr[j]] &+ kr[round], sr[j]) &+ er
                ar = er; er = dr; dr = rotl(cr, 10); cr = br; br = t
            }
            let t = h1 &+ cl &+ dr
            h1 = h2 &+ dl &+ er
            h2 = h3 &+ el &+ ar
            h3 = h4 &+ al &+ br
            h4 = h0 &+ bl &+ cr
            h0 = t
            offset += 64
        }

        var out = [UInt8]()
        out.reserveCapacity(20)
        for word in [h0, h1, h2, h3, h4] {
            out.append(UInt8(truncatingIfNeeded: word))
            out.append(UInt8(truncatingIfNeeded: word >> 8))
            out.append(UInt8(truncatingIfNeeded: word >> 16))
            out.append(UInt8(truncatingIfNeeded: word >> 24))
        }
        return out
    }

    // MARK: - Private

    @inline(__always)
    private static func rotl(_ v: UInt32, _ n: UInt32) -> UInt32 {
        return (v << n) | (v >> (32 - n))
    }

    /// The five boolean functions; the left line uses them in order 0…4, the right line in order 4…0.
    @inline(__always)
    private static func f(_ round: Int, _ x: UInt32, _ y: UInt32, _ z: UInt32) -> UInt32 {
        switch round {
        case 0: return x ^ y ^ z
        case 1: return (x & y) | (~x & z)
        case 2: return (x | ~y) ^ z
        case 3: return (x & z) | (y & ~z)
        default: return x ^ (y | ~z)
        }
    }

    private static let kl: [UInt32] = [0x0000_0000, 0x5A82_7999, 0x6ED9_EBA1, 0x8F1B_BCDC, 0xA953_FD4E]
    private static let kr: [UInt32] = [0x50A2_8BE6, 0x5C4D_D124, 0x6D70_3EF3, 0x7A6D_76E9, 0x0000_0000]

    /// Message word selection, left line.
    private static let rl: [Int] = [
        0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
        7, 4, 13, 1, 10, 6, 15, 3, 12, 0, 9, 5, 2, 14, 11, 8,
        3, 10, 14, 4, 9, 15, 8, 1, 2, 7, 0, 6, 13, 11, 5, 12,
        1, 9, 11, 10, 0, 8, 12, 4, 13, 3, 7, 15, 14, 5, 6, 2,
        4, 0, 5, 9, 7, 12, 2, 10, 14, 1, 3, 8, 11, 6, 15, 13,
    ]
    /// Message word selection, right line.
    private static let rr: [Int] = [
        5, 14, 7, 0, 9, 2, 11, 4, 13, 6, 15, 8, 1, 10, 3, 12,
        6, 11, 3, 7, 0, 13, 5, 10, 14, 15, 8, 12, 4, 9, 1, 2,
        15, 5, 1, 3, 7, 14, 6, 9, 11, 8, 12, 2, 10, 0, 4, 13,
        8, 6, 4, 1, 3, 11, 15, 0, 5, 12, 2, 13, 9, 7, 10, 14,
        12, 15, 10, 4, 1, 5, 8, 7, 6, 2, 13, 14, 0, 3, 9, 11,
    ]
    /// Rotation amounts, left line.
    private static let sl: [UInt32] = [
        11, 14, 15, 12, 5, 8, 7, 9, 11, 13, 14, 15, 6, 7, 9, 8,
        7, 6, 8, 13, 11, 9, 7, 15, 7, 12, 15, 9, 11, 7, 13, 12,
        11, 13, 6, 7, 14, 9, 13, 15, 14, 8, 13, 6, 5, 12, 7, 5,
        11, 12, 14, 15, 14, 15, 9, 8, 9, 14, 5, 6, 8, 6, 5, 12,
        9, 15, 5, 11, 6, 8, 13, 12, 5, 12, 13, 14, 11, 8, 5, 6,
    ]
    /// Rotation amounts, right line.
    private static let sr: [UInt32] = [
        8, 9, 9, 11, 13, 15, 15, 5, 7, 7, 8, 11, 14, 14, 12, 6,
        9, 13, 15, 7, 12, 8, 9, 11, 7, 7, 12, 7, 6, 15, 13, 11,
        9, 7, 15, 11, 8, 6, 6, 14, 12, 13, 5, 14, 13, 13, 7, 5,
        15, 5, 8, 11, 14, 14, 6, 14, 6, 9, 12, 9, 12, 5, 15, 8,
        8, 5, 12, 9, 12, 5, 14, 6, 8, 13, 6, 5, 15, 13, 11, 11,
    ]
}
