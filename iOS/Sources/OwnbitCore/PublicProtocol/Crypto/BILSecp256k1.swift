//  BILSecp256k1.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Public protocol (cold signer): verification-only secp256k1 for the native post-check (design D-29, §3.2; R5 §9).
//
//  Ports of Android `EvmTxCodec.recoverPublicKey` (core/chain/.../evm/EvmTxCodec.kt:447-463, BouncyCastle) and
//  `PsbtMaps.taprootOutputScript` (core/publicsigner/.../verify/PsbtMaps.kt:326-339). Only public data goes through
//  here (digests, signatures, public keys), so there is no constant-time requirement. Arithmetic is CryptoSwift
//  `CS.BigUInt` in Jacobian coordinates (one inversion per result), a fixed 4-bit window table for G (built once per
//  process) and a 4-bit window for other points; independent of the engine's JavaScript curve code. Everything is
//  behind these static functions, so swapping in libsecp256k1 (`secp256k1_ecdsa_recover`,
//  `secp256k1_ec_pubkey_tweak_add`) stays local to this file. Pure: Foundation + CryptoSwift (macOS harness:
//  tests/crypto/). Never logs anything.
//

import Foundation
import CryptoSwift

/// Cost: CPU-heavy. Debug build (-Onone, M-series Mac): ≈ 135 ms per `recoverPublicKey`, ≈ 40 ms per uncached
/// `taprootOutputScript`, plus ≈ 0.8 s once per process for the G table (built by the first `recoverPublicKey` /
/// `taprootOutputScript`); Release (-O): ≈ 5 ms, ≈ 1.3 ms and ≈ 30 ms. Devices are slower. Call these two off-main via
/// `BILPublicBackground.run { }` (design §1.4); `compress` / `decompress` / `evmAddressBytes` are cheap. All functions
/// are pure and thread-safe.
enum BILSecp256k1 {

    /// SEC 1 v2 §4.1.6 public-key recovery over a 32-byte `digest` (Android `EvmTxCodec.recoverPublicKey`).
    /// `r` / `s` are unsigned big-endian integers (as `BigInteger(1, bytes)`); `recId` 0…3. Returns the uncompressed key
    /// `04 ‖ X ‖ Y` (65 bytes), or nil when: the digest is not 32 bytes, recId is outside 0…3, r or s is outside
    /// [1, n − 1] (no low-S rule), x = r + (recId / 2)·n is not below p, x is not on the curve, or the result is the
    /// point at infinity.
    static func recoverPublicKey(digest: [UInt8], recId: Int, r: [UInt8], s: [UInt8]) -> [UInt8]? {
        guard digest.count == 32, recId >= 0, recId <= 3 else { return nil }
        let rv = U(Data(r))
        let sv = U(Data(s))
        guard rv > C.zero, rv < C.n, sv > C.zero, sv < C.n else { return nil }
        let x = (recId >> 1) == 1 ? rv + C.n : rv
        guard x < C.p, let point = liftX(x, odd: (recId & 1) == 1) else { return nil }
        // BouncyCastle also requires n·R == ∞; secp256k1 has cofactor 1, so every curve point satisfies it.
        guard let rInv = rv.inverse(C.n) else { return nil }
        let e = U(Data(digest)) % C.n
        let u1 = e == C.zero ? C.zero : ((C.n - e) * rInv) % C.n         // −e·r⁻¹ mod n
        let u2 = (sv * rInv) % C.n                                    //  s·r⁻¹ mod n
        guard let u1G = mulG(u1) else { return nil }
        guard let a = toAffine(add(u1G, mul(point, u2))) else { return nil }
        return [0x04] + bytes32(a.x) + bytes32(a.y)
    }

    /// `04 ‖ X ‖ Y` (65 bytes, a point on the curve) → `02|03 ‖ X` (33 bytes); nil for any other input.
    static func compress(uncompressed: [UInt8]) -> [UInt8]? {
        guard uncompressed.count == 65, uncompressed[0] == 0x04 else { return nil }
        let xBytes = Array(uncompressed[1..<33])
        let x = U(Data(xBytes))
        let y = U(Data(Array(uncompressed[33..<65])))
        guard isOnCurve(x, y) else { return nil }
        return [y[bitAt: 0] ? 0x03 : 0x02] + xBytes
    }

    /// `02|03 ‖ X` (33 bytes) → `04 ‖ X ‖ Y` (65 bytes); nil when the prefix is wrong, X ≥ p or X is not on the curve.
    static func decompress(compressed: [UInt8]) -> [UInt8]? {
        guard compressed.count == 33, compressed[0] == 0x02 || compressed[0] == 0x03 else { return nil }
        let xBytes = Array(compressed[1..<33])
        guard let point = liftX(U(Data(xBytes)), odd: compressed[0] == 0x03) else { return nil }
        return [0x04] + xBytes + bytes32(point.y)
    }

    /// keccak256(X ‖ Y)[12..<32]: the 20 address bytes of EVM (`0x…`) and TRON (`41 ‖ …`). Accepts the 65-byte form
    /// (first byte dropped, not checked — as Android `EvmTxCodec.publicKeyToAddress`) or the raw 64 bytes; nil otherwise.
    static func evmAddressBytes(uncompressed: [UInt8]) -> [UInt8]? {
        let raw: [UInt8]
        switch uncompressed.count {
        case 65: raw = Array(uncompressed[1..<65])
        case 64: raw = uncompressed
        default: return nil
        }
        return Array(BILPublicHash.keccak256(raw)[12..<32])
    }

    /// BIP-86 / BIP-341 key-path output script of the x-only key: `51 20 ‖ x(Q)`, Q = lift_x(x) + t·G,
    /// t = int(taggedHash("TapTweak", x)) (empty script tree). nil when the key is not 32 bytes, x ≥ p, x is not on the
    /// curve, t ≥ n or Q = ∞. Cached per key (the PSBT diff may ask for the same key on up to 100 inputs).
    static func taprootOutputScript(xOnly: [UInt8]) -> [UInt8]? {
        guard xOnly.count == 32 else { return nil }
        if let hit = TapCache.shared.lookup(xOnly) { return hit.script }
        let script = computeTaprootOutputScript(xOnly)
        TapCache.shared.store(xOnly, script)
        return script
    }

    // MARK: - Curve

    private typealias U = CS.BigUInt

    private struct Affine {
        let x: U
        let y: U
    }

    /// Jacobian (X, Y, Z) ↔ affine (X/Z², Y/Z³); Z == 0 is the point at infinity.
    private struct Jacobian {
        var x: U
        var y: U
        var z: U
        var isInfinity: Bool { return z == C.zero }
        static let infinity = Jacobian(x: U(1), y: U(1), z: U(0))
        init(x: U, y: U, z: U) {
            self.x = x
            self.y = y
            self.z = z
        }
        init(_ a: Affine) {
            self.init(x: a.x, y: a.y, z: U(1))
        }
    }

    private enum C {
        static let p = hexConstant("FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F")
        static let n = hexConstant("FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141")
        static let g = Affine(x: hexConstant("79BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798"),
                              y: hexConstant("483ADA7726A3C4655DA4FBFC0E1108A8FD17B448A68554199C47D08FFB10D4B8"))
        /// (p + 1) / 4: p ≡ 3 (mod 4), so a square root of a quadratic residue a is a^((p+1)/4).
        static let sqrtExponent = (p + U(1)) / U(4)
        static let seven = U(7)
        static let zero = U(0)

        /// Fixed curve constants (the vectors of tests/crypto/ fail at once if one were mistyped).
        private static func hexConstant(_ text: String) -> U {
            return U(text, radix: 16)!
        }
    }

    // MARK: Field arithmetic mod p (operands always reduced)

    private static func fAdd(_ a: U, _ b: U) -> U {
        let s = a + b
        return s >= C.p ? s - C.p : s
    }

    private static func fSub(_ a: U, _ b: U) -> U {
        return a >= b ? a - b : (a + C.p) - b
    }

    private static func fMul(_ a: U, _ b: U) -> U {
        return (a * b) % C.p
    }

    private static func fSqr(_ a: U) -> U {
        return (a * a) % C.p
    }

    private static func fTwice(_ a: U) -> U {
        return fAdd(a, a)
    }

    private static func isOnCurve(_ x: U, _ y: U) -> Bool {
        guard x < C.p, y < C.p else { return false }
        return fSqr(y) == fAdd(fMul(fSqr(x), x), C.seven)
    }

    /// The curve point with this x and the requested y parity (BouncyCastle `decodePoint(02|03 ‖ x)`); nil when x ≥ p
    /// or x³ + 7 is not a square.
    private static func liftX(_ x: U, odd: Bool) -> Affine? {
        guard x < C.p else { return nil }
        let y2 = fAdd(fMul(fSqr(x), x), C.seven)
        let root = y2.power(C.sqrtExponent, modulus: C.p)
        guard fSqr(root) == y2 else { return nil }
        if root[bitAt: 0] == odd { return Affine(x: x, y: root) }
        guard root != C.zero else { return nil }
        return Affine(x: x, y: C.p - root)
    }

    // MARK: Group law (a = 0)

    /// 2·P: S = 4·X·Y², M = 3·X², X' = M² − 2S, Y' = M·(S − X') − 8·Y⁴, Z' = 2·Y·Z.
    private static func dbl(_ pt: Jacobian) -> Jacobian {
        if pt.isInfinity || pt.y == C.zero { return .infinity }
        let yy = fSqr(pt.y)
        let s = fTwice(fTwice(fMul(pt.x, yy)))
        let xx = fSqr(pt.x)
        let m = fAdd(fTwice(xx), xx)
        let x3 = fSub(fSqr(m), fTwice(s))
        let y3 = fSub(fMul(m, fSub(s, x3)), fTwice(fTwice(fTwice(fSqr(yy)))))
        let z3 = fTwice(fMul(pt.y, pt.z))
        return Jacobian(x: x3, y: y3, z: z3)
    }

    /// P + Q (both Jacobian).
    private static func add(_ p1: Jacobian, _ p2: Jacobian) -> Jacobian {
        if p1.isInfinity { return p2 }
        if p2.isInfinity { return p1 }
        let z1z1 = fSqr(p1.z)
        let z2z2 = fSqr(p2.z)
        let u1 = fMul(p1.x, z2z2)
        let u2 = fMul(p2.x, z1z1)
        let s1 = fMul(fMul(p1.y, p2.z), z2z2)
        let s2 = fMul(fMul(p2.y, p1.z), z1z1)
        let h = fSub(u2, u1)
        let r = fSub(s2, s1)
        if h == C.zero { return r == C.zero ? dbl(p1) : .infinity }
        let hh = fSqr(h)
        let hhh = fMul(h, hh)
        let v = fMul(u1, hh)
        let x3 = fSub(fSub(fSqr(r), hhh), fTwice(v))
        let y3 = fSub(fMul(r, fSub(v, x3)), fMul(s1, hhh))
        let z3 = fMul(fMul(p1.z, p2.z), h)
        return Jacobian(x: x3, y: y3, z: z3)
    }

    /// P + Q with Q affine (Z = 1).
    private static func addMixed(_ p1: Jacobian, _ q: Affine) -> Jacobian {
        if p1.isInfinity { return Jacobian(q) }
        let z1z1 = fSqr(p1.z)
        let u2 = fMul(q.x, z1z1)
        let s2 = fMul(fMul(q.y, p1.z), z1z1)
        let h = fSub(u2, p1.x)
        let r = fSub(s2, p1.y)
        if h == C.zero { return r == C.zero ? dbl(p1) : .infinity }
        let hh = fSqr(h)
        let hhh = fMul(h, hh)
        let v = fMul(p1.x, hh)
        let x3 = fSub(fSub(fSqr(r), hhh), fTwice(v))
        let y3 = fSub(fMul(r, fSub(v, x3)), fMul(p1.y, hhh))
        let z3 = fMul(p1.z, h)
        return Jacobian(x: x3, y: y3, z: z3)
    }

    private static func toAffine(_ pt: Jacobian) -> Affine? {
        guard !pt.isInfinity, let zInv = pt.z.inverse(C.p) else { return nil }
        let zInv2 = fSqr(zInv)
        return Affine(x: fMul(pt.x, zInv2), y: fMul(pt.y, fMul(zInv2, zInv)))
    }

    /// Nibble `i` (0 = least significant) of a scalar below 2^256, from its 32-byte big-endian form.
    @inline(__always)
    private static func nibble(_ k: [UInt8], _ i: Int) -> Int {
        let byte = k[31 - (i >> 1)]
        return Int((i & 1) == 0 ? byte & 0x0F : byte >> 4)
    }

    /// k·G for 0 ≤ k < 2^256 with the fixed table (64 mixed additions, no doublings). nil only if the table could not
    /// be built (cannot happen: no entry is ∞), so callers fail closed instead of trapping on an index or, worse,
    /// treating a missing k·G as ∞ (which would turn a recovery into u2·R and a tweak into the untweaked key).
    private static func mulG(_ k: U) -> Jacobian? {
        if k == C.zero { return .infinity }
        let table = gTable
        guard table.count == 64 * 15 else { return nil }
        let kb = bytes32(k)
        var acc = Jacobian.infinity
        for i in 0..<64 {
            let d = nibble(kb, i)
            if d != 0 { acc = addMixed(acc, table[i * 15 + d - 1]) }
        }
        return acc
    }

    /// k·P for 0 ≤ k < 2^256, 4-bit fixed window.
    private static func mul(_ pt: Affine, _ k: U) -> Jacobian {
        if k == C.zero { return .infinity }
        var multiples = [Jacobian(pt)]                     // multiples[j − 1] = j·P
        multiples.reserveCapacity(15)
        for _ in 2...15 { multiples.append(addMixed(multiples[multiples.count - 1], pt)) }
        let kb = bytes32(k)
        var acc = Jacobian.infinity
        var i = 63
        while i >= 0 {
            if !acc.isInfinity { acc = dbl(dbl(dbl(dbl(acc)))) }
            let d = nibble(kb, i)
            if d != 0 { acc = add(acc, multiples[d - 1]) }
            i -= 1
        }
        return acc
    }

    /// gTable[i·15 + j − 1] = j·16^i·G (i 0…63, j 1…15), affine; built once per process (thread-safe lazy static).
    /// No entry is ∞ (every j·16^i < n).
    private static let gTable: [Affine] = {
        var points = [Jacobian]()
        points.reserveCapacity(64 * 15)
        var base = Jacobian(C.g)
        for _ in 0..<64 {
            var acc = base
            points.append(acc)
            for _ in 2...15 {
                acc = add(acc, base)
                points.append(acc)
            }
            base = dbl(dbl(dbl(dbl(base))))
        }
        return batchToAffine(points)
    }()

    /// Montgomery's simultaneous inversion: one field inversion for all Z (none may be zero). [] when the product has
    /// no inverse (cannot happen for the G table; `mulG` then returns nil).
    private static func batchToAffine(_ points: [Jacobian]) -> [Affine] {
        guard !points.isEmpty else { return [] }
        var prefix = [U]()
        prefix.reserveCapacity(points.count)
        var running = U(1)
        for pt in points {
            running = fMul(running, pt.z)
            prefix.append(running)
        }
        guard var inv = running.inverse(C.p) else { return [] }
        var out = [Affine](repeating: C.g, count: points.count)
        var i = points.count - 1
        while i >= 0 {
            let zInv = i == 0 ? inv : fMul(inv, prefix[i - 1])
            inv = fMul(inv, points[i].z)
            let zInv2 = fSqr(zInv)
            out[i] = Affine(x: fMul(points[i].x, zInv2), y: fMul(points[i].y, fMul(zInv2, zInv)))
            i -= 1
        }
        return out
    }

    // MARK: Taproot

    private static func computeTaprootOutputScript(_ xOnly: [UInt8]) -> [UInt8]? {
        guard let internalKey = liftX(U(Data(xOnly)), odd: false) else { return nil }
        let t = U(Data(BILPublicHash.taggedHash("TapTweak", xOnly)))
        guard t < C.n, let tG = mulG(t) else { return nil }
        guard let q = toAffine(addMixed(tG, internalKey)) else { return nil }
        return [0x51, 0x20] + bytes32(q.x)
    }

    /// Bounded, lock-protected cache of `taprootOutputScript` results (public data; nil results cached too).
    private final class TapCache {
        struct Entry {
            let script: [UInt8]?
        }
        static let shared = TapCache()
        private static let capacity = 4096
        private let lock = NSLock()
        private var entries = [[UInt8]: Entry]()

        func lookup(_ key: [UInt8]) -> Entry? {
            lock.lock()
            defer { lock.unlock() }
            return entries[key]
        }

        func store(_ key: [UInt8], _ script: [UInt8]?) {
            lock.lock()
            defer { lock.unlock() }
            if entries.count >= TapCache.capacity { entries.removeAll(keepingCapacity: true) }
            entries[key] = Entry(script: script)
        }
    }

    // MARK: Bytes

    /// Big-endian, left-padded to 32 bytes (values here are always below 2^256).
    private static func bytes32(_ v: U) -> [UInt8] {
        let raw = [UInt8](v.serialize())
        if raw.count >= 32 { return Array(raw.suffix(32)) }
        return [UInt8](repeating: 0, count: 32 - raw.count) + raw
    }
}
