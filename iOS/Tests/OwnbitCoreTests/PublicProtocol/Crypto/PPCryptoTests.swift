//  PPCryptoTests.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Port of the app harness suite `scripts/public-protocol/tests/crypto` (main.swift) to XCTest.
//
//  main.swift — crypto suite (WP2; design §3.2, §4 WP2; R5 §9).
//  Compiled by run.sh with the real app files Modules/PublicProtocol/Crypto/*.swift + CryptoSwift (built as a module).
//  Arguments: <reference vectors (reference.py output)> <golden vectors.json> <mode label, e.g. -Onone / -O>.
//  Mode "parallel-first" runs only the cold-start concurrency check (8 threads are the first BILSecp256k1 callers).
//  Self-contained in Wave 1 (no tests/support/*).
//

import Foundation
import XCTest
import CryptoKit
@testable import OwnbitCore

/// The suite namespace (harness helpers are its static members).
enum PPCryptoSuite: PPSuite {}

final class PPCryptoTests: XCTestCase {
    func testCrypto() throws {
        try ppRunSuite("crypto") { try PPCryptoSuite.run() }
    }
}

extension PPCryptoSuite {

    // MARK: - Mini test kit

    // (The harness's own mini kit — `oks` / `fails` / `t` — is PPSuite's `t`.)

    static func h(_ s: String) -> [UInt8] {
        if s == "-" { return [] }
        var out = [UInt8]()
        var it = Array(s.utf8)[...]
        func v(_ c: UInt8) -> UInt8 {
            switch c {
            case 0x30...0x39: return c - 0x30
            case 0x41...0x46: return c - 0x41 + 10
            case 0x61...0x66: return c - 0x61 + 10
            default: fatalError("bad hex in test data: \(s)")
            }
        }
        precondition(it.count % 2 == 0, "odd hex in test data: \(s)")
        while !it.isEmpty {
            out.append(v(it[it.startIndex]) << 4 | v(it[it.startIndex + 1]))
            it = it.dropFirst(2)
        }
        return out
    }

    static func hx(_ b: [UInt8]?) -> String {
        guard let b = b else { return "nil" }
        return b.map { String(format: "%02x", $0) }.joined()
    }

    static func ascii(_ s: String) -> [UInt8] { return Array(s.utf8) }

    /// Local base58 / base58check (the suite must not depend on WP1's codec).
    static func base58(_ bytes: [UInt8]) -> String {
        let alphabet = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
        var digits = [Int]()
        for b in bytes {
            var carry = Int(b)
            for i in 0..<digits.count {
                carry += digits[i] << 8
                digits[i] = carry % 58
                carry /= 58
            }
            while carry > 0 { digits.append(carry % 58); carry /= 58 }
        }
        var out = String(repeating: "1", count: bytes.prefix(while: { $0 == 0 }).count)
        for d in digits.reversed() { out.append(alphabet[d]) }
        return out
    }

    static func base58check(_ payload: [UInt8]) -> String {
        return base58(payload + Array(BILPublicHash.sha256d(payload)[0..<4]))
    }

    static func tronAddress(_ uncompressed: [UInt8]?) -> String? {
        guard let u = uncompressed, let a = BILSecp256k1.evmAddressBytes(uncompressed: u) else { return nil }
        return base58check([0x41] + a)
    }

    static func evmAddress(_ uncompressed: [UInt8]?) -> String? {
        guard let u = uncompressed, let a = BILSecp256k1.evmAddressBytes(uncompressed: u) else { return nil }
        return "0x" + hx(a)
    }

    static func millis(_ start: DispatchTime) -> Double {
        return Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
    }

    /// The harness took `<reference.txt> <vectors.json> <mode>` as arguments (run.sh ran it at -Onone, -O and in the
    /// "parallel-first" mode, each in a fresh process). Here: the reference vectors (reference.py output, md5 lines
    /// removed) and vectors.json are fixtures; one debug run.
    static let mode = "-Onone"
    static let refLines: [[String]] = fixtureText("crypto-reference.txt").split(separator: "\n").map { $0.split(separator: " ").map(String.init) }
    static let nBytes = h("fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141")
    static func ref(_ kind: String) -> [[String]] { return refLines.filter { $0.first == kind } }
    struct RecVector {
        let name: String
        let digest: [UInt8]
        let sig: [UInt8]       // r ‖ s (‖ v ignored)
        let recId: Int
        let key: String
        let evm: Bool
        var r: [UInt8] { return Array(sig[0..<32]) }
        var s: [UInt8] { return Array(sig[32..<64]) }
    }
    static func plusOne(_ b: [UInt8]) -> [UInt8] {
        var out = b
        var i = out.count - 1
        while i >= 0 { out[i] = out[i] &+ 1; if out[i] != 0 { break }; i -= 1 }
        return out
    }
    static func nMinus(_ v: [UInt8]) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: 32)
        var borrow = 0
        var i = 31
        while i >= 0 {
            var d = Int(nBytes[i]) - Int(v[i]) - borrow
            borrow = d < 0 ? 1 : 0
            if d < 0 { d += 256 }
            out[i] = UInt8(d)
            i -= 1
        }
        return out
    }
    static func sha256File(_ path: String) -> String? {
        guard let d = FileManager.default.contents(atPath: path) else { return nil }
        return SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined()
    }

    /// The harness main.swift (nonisolated top-level code, as in the harness).
    static func run() throws {
        // MARK: - Reference vectors (reference.py); reading them does not touch BILSecp256k1

        t(refLines.count > 1000, "reference vectors read (\(refLines.count) lines)")

        // MARK: - Parallel callers (the harness ran this first in its own process, on a cold G table and cache; in the shared
        // XCTest process another suite may have warmed them, so this is a plain concurrency check here)

        do {
            // Nothing above has called BILSecp256k1, so the lazy G table and the Taproot cache are both cold. The 8 threads are
            // released together and race the table's one-time build (even threads enter through a tweak, odd ones through a
            // recovery), then store into the cache concurrently: own key (a miss), the neighbour's key (a concurrent miss or a
            // hit), own key again (a hit). Every result is compared with the reference.
            let keys = ref("partweak")
            let sigs = ref("parrec")
            t(keys.count == 8 && sigs.count == 8, "parallel-first vector counts (\(keys.count), \(sigs.count))")
            if keys.count == 8 && sigs.count == 8 {
                let ready = DispatchSemaphore(value: 0)
                let go = DispatchSemaphore(value: 0)
                let done = DispatchSemaphore(value: 0)
                let badLock = NSLock()
                var bad = [String]()
                for i in 0..<8 {
                    let own = keys[i]
                    let next = keys[(i + 1) % 8]
                    let sig = sigs[i]
                    let thread = Thread {
                        ready.signal()
                        go.wait()
                        var problems = [String]()
                        func tweak(_ line: [String], _ what: String) {
                            if hx(BILSecp256k1.taprootOutputScript(xOnly: h(line[1]))) != line[2] { problems.append("thread \(i): \(what)") }
                        }
                        func recover() {
                            let q = BILSecp256k1.recoverPublicKey(digest: h(sig[1]), recId: Int(sig[4])!, r: h(sig[2]), s: h(sig[3]))
                            if hx(q) != sig[5] { problems.append("thread \(i): recovery") }
                        }
                        if i % 2 == 0 {
                            tweak(own, "own key (miss)")
                            recover()
                        } else {
                            recover()
                            tweak(own, "own key (miss)")
                        }
                        tweak(next, "neighbour's key")
                        tweak(own, "own key (hit)")
                        badLock.lock()
                        bad += problems
                        badLock.unlock()
                        done.signal()
                    }
                    thread.start()
                }
                for _ in 0..<8 { ready.wait() }
                for _ in 0..<8 { go.signal() }
                for _ in 0..<8 { done.wait() }
                for p in bad { print("  FAIL parallel-first \(p)") }
                t(bad.isEmpty, "parallel-first: 8 threads on the cold G table and cache agree with the reference")
                var cachedOk = 0
                for line in keys where hx(BILSecp256k1.taprootOutputScript(xOnly: h(line[1]))) == line[2] { cachedOk += 1 }
                t(cachedOk == 8, "parallel-first: the 8 scripts read back afterwards (\(cachedOk))")
            }
        }

        // MARK: - First secp256k1 call: one-time G-table build (+ one tweak), timed before anything else touches the curve

        let bip86Internal = h("cc8a4bc64d897bddc5fbc2f670f7a8ba0b386779106cf1223c6fc5d7cd6fc115")
        let bip86Script = "5120a60869f0dbcf1dc659c9cecbaf8050135ea9e8cdc487053f1dc6880949dc684c"
        let initStart = DispatchTime.now()
        let bip86First = BILSecp256k1.taprootOutputScript(xOnly: bip86Internal)
        let initMs = millis(initStart)
        t(hx(bip86First) == bip86Script, "BIP-86 vector (first call)")

        // MARK: - Performance (U7 budget): 100 recoveries and 100 tweaks, 100 different keys each, no cache hits

        let perfRec = ref("perfrec")
        let perfTweak = ref("perftweak")
        t(perfRec.count == 100 && perfTweak.count == 100, "perf vector counts")
        let recInputs = perfRec.map { (h($0[1]), Int($0[4])!, h($0[2]), h($0[3])) }
        let tweakInputs = perfTweak.map { h($0[1]) }
        var recOut = [[UInt8]?]()
        var tweakOut = [[UInt8]?]()
        let recStart = DispatchTime.now()
        for (digest, recId, r, s) in recInputs {
            recOut.append(BILSecp256k1.recoverPublicKey(digest: digest, recId: recId, r: r, s: s))
        }
        let recMs = millis(recStart)
        let tweakStart = DispatchTime.now()
        for x in tweakInputs { tweakOut.append(BILSecp256k1.taprootOutputScript(xOnly: x)) }
        let tweakMs = millis(tweakStart)
        var perfRecBad = 0
        for (i, line) in perfRec.enumerated() where hx(recOut[i]) != line[5] { perfRecBad += 1 }
        var perfTweakBad = 0
        for (i, line) in perfTweak.enumerated() where hx(tweakOut[i]) != line[2] { perfTweakBad += 1 }
        t(perfRecBad == 0, "perf recoveries equal the reference (\(perfRecBad) differ)")
        t(perfTweakBad == 0, "perf tweaks equal the reference (\(perfTweakBad) differ)")
        print("crypto: perf recover100=\(Int(recMs.rounded())) tweak100=\(Int(tweakMs.rounded())) init=\(Int(initMs.rounded())) (\(mode))")
        if mode == "-O" {
            t(tweakMs <= 1000, "budget: 100 Taproot tweaks <= 1 s at -O (was \(Int(tweakMs)) ms)")
        }

        // MARK: - Hashes

        t(BILPublicHash.sha256Hex([]) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "sha256 empty")
        t(hx(BILPublicHash.sha256(ascii("abc"))) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "sha256 abc")
        t(BILPublicHash.sha256Hex(utf8: "abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "sha256Hex utf8 abc")
        t(hx(BILPublicHash.keccak256([])) == "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470", "keccak256 empty")
        t(hx(BILPublicHash.keccak256(ascii("abc"))) == "4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45", "keccak256 abc")
        t(BILPublicHash.crc32(ascii("123456789")) == 0xCBF4_3926, "crc32 check value")
        t(BILPublicHash.crc32([]) == 0, "crc32 empty")
        // seedHash parity: the wallet's seedHash is the lower-case hex SHA-256 of the seed text's UTF-8 (the app: CryptoSwift
        // String.sha256(); here CryptoKit as the independent reference). The app's md5 parity check is not ported (no md5).
        for s in ["", "abc", "5eb00bbddcf069084889a8ab9155568165f5c453ccb85e70811aaed6f6da5fc19a5ac40b389cd370d086206dec8aa6c43daea6690f20ad3d8d48b2d2ce9e38e4", "é中文 seed", "\u{1F600}"] {
            t(BILPublicHash.sha256Hex(utf8: s) == SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined(),
              "sha256Hex(utf8:) == SHA-256 hex of the UTF-8 for \(s.prefix(8))")
        }
        // RIPEMD-160 reference vectors (Bosselaers' page) incl. one million "a".
        let ripemdVectors: [(String, String)] = [
            ("", "9c1185a5c5e9fc54612808977ee8f548b2258d31"),
            ("a", "0bdc9d2d256b3ee9daae347be6f4dc835a467ffe"),
            ("abc", "8eb208f7e05d987a9b044a8e98c6b087f15a0bfc"),
            ("message digest", "5d0689ef49d2fae572b881b123a85ffa21595f36"),
            ("abcdefghijklmnopqrstuvwxyz", "f71c27109c692c1b56bbdceb5b9d2865b3708dbc"),
            ("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq", "12a053384a9c0c88e405a06c27dcf49ada62eb2b"),
            ("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789", "b0e20b6e3116640286ed3a87a5713079b21f5189"),
            (String(repeating: "1234567890", count: 8), "9b752e45573d4b39f4dbd3323cab82bf63326bfb"),
            (String(repeating: "a", count: 1_000_000), "52783243c1697bdbe16d37f97f68f08325dc1528"),
        ]
        for (m, d) in ripemdVectors {
            t(hx(BILRipemd160.hash(ascii(m))) == d, "ripemd160 \(m.prefix(16))… (\(m.utf8.count) B)")
        }
        // hash160 of the BIP-84 key m/84'/0'/0'/0/0 of abandon … about (bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu).
        t(hx(BILPublicHash.hash160(h("0330d54fd0dd420a6e5f8d3624f5f3482cae350f79d5f0753bf5beef9c2d91af3c"))) == "c0cebcd6c3d3ca8c75dc5ec62ebe55330ef910e2", "hash160 BIP-84 key")
        let tapTag = BILPublicHash.sha256(ascii("TapTweak"))
        t(BILPublicHash.taggedHash("TapTweak", bip86Internal) == BILPublicHash.sha256(tapTag + tapTag + bip86Internal), "taggedHash = sha256(tag‖tag‖d)")
        t(BILPublicHash.sha256d(ascii("abc")) == BILPublicHash.sha256(BILPublicHash.sha256(ascii("abc"))), "sha256d")
        // EIP-191 / TIP-191 against the golden vectors (plan signingBytesDigest).
        t(hx(BILPublicHash.eip191Digest(ascii("Ownbit public protocol fixture"))) == "12daddf4bfade5f5469a47f9e3859f52e031085934a608030e562c78f1e98355", "EIP-191 T8-flow-evm-personal")
        t(hx(BILPublicHash.tip191Digest(ascii("hello ownbit"))) == "12ae7c647486530c0aea42451e314868fb81cc487c3bb2fdb166af948805d0a8", "TIP-191 O-TL-V4 hello ownbit")
        t(hx(BILPublicHash.tip191Digest(ascii("Ownbit public TRON message"))) == "677f0dfa15170a4376ab0d59d9300b8e96d56d2a56c00f8c60a9199e5c8d565b", "TIP-191 T8-flow-tron-message")
        t(BILPublicHash.eip191Digest(ascii("hello ownbit")) != BILPublicHash.tip191Digest(ascii("hello ownbit")), "EIP-191 != TIP-191")
        t(BILPublicHash.eip191Digest(ascii("hello ownbit")) == BILPublicHash.keccak256(ascii("\u{19}Ethereum Signed Message:\n12hello ownbit")), "EIP-191 prefix + decimal length")

        // Reference cross-checks (Python hashlib / zlib).
        var refHashBad = 0
        var refHashCount = 0
        for line in refLines {
            guard let kind = line.first else { continue }
            var ok = true
            switch kind {
            case "ripemd": ok = hx(BILRipemd160.hash(h(line[1]))) == line[2]
            case "hash160": ok = hx(BILPublicHash.hash160(h(line[1]))) == line[2]
            case "sha256": ok = BILPublicHash.sha256Hex(h(line[1])) == line[2]
            case "sha256d": ok = hx(BILPublicHash.sha256d(h(line[1]))) == line[2]
            case "crc32": ok = BILPublicHash.crc32(h(line[1])) == UInt32(line[2])!
            case "tagged": ok = hx(BILPublicHash.taggedHash(String(decoding: h(line[1]), as: UTF8.self), h(line[2]))) == line[3]
            case "note": print("  note: \(line.dropFirst().joined(separator: " "))"); continue
            default: continue
            }
            refHashCount += 1
            if !ok { refHashBad += 1; print("  FAIL reference \(kind) \(line[1].prefix(16))") }
        }
        t(refHashBad == 0, "reference hash cross-checks (\(refHashCount) lines)")
        t(refHashCount >= 400, "reference hash lines present (\(refHashCount))")
        // RIPEMD-160 random cross-checks need hashlib's ripemd160 (OpenSSL legacy provider); reference.py says so when absent.
        t(ref("ripemd").count == 137 || !ref("note").isEmpty, "reference RIPEMD-160 lines present (\(ref("ripemd").count))")

        // MARK: - Recovery: the 5 golden vectors of R5 §9 + TronLink V1 / V3 / V4

        let evmKey = "0237b0bb7a8288d38ed49a524b5dc98cff3eb5ca824c9f9dc0dfdb3d9cd600f299"
        let evmAddr = "0x9858effd232b4033e47d90003d41ec34ecaeda94"
        let tronKey = "03ff21f8e64d3a3c0198edfbb7afdc79be959432e92e2f8a1984bb436a414b8edc"
        let tron0 = "TUEZSdKsoDHQMeZwihtdoBiN46zxhGWYdH"

        // TronLink entries are `Transaction` protobufs: 0a <len varint> raw_data …; the signed digest is sha256(raw_data).
        let v1Entry = h("0a1a5a18221654726f6e4c696e6b437573746f6d436f6e7472616374")
        t(v1Entry[0] == 0x0A && Int(v1Entry[1]) == v1Entry.count - 2, "TronLink V1 entry layout")
        let v3Entry = h("0a85010a02ab122208010203040506070840e0dc94809e335a67080112630a2d747970652e676f6f676c65617069732e636f6d2f70726f746f636f6c2e5472616e73666572436f6e747261637412320a1541c8599111f29c1e1e061265b4af93ea1f274ad78a121541eca9bc828a3005b9a3b909f2cc5c2a54794de05f18c0843d70808891809e33")
        t(v3Entry[0] == 0x0A && v3Entry[1] == 0x85 && v3Entry[2] == 0x01 && v3Entry.count - 3 == 133, "TronLink V3 entry layout")

        let recVectors: [RecVector] = [
            RecVector(name: "T8-flow-evm-eip1559", digest: h("262c8a05d85c2095475edcc8fd0bee2f11aee8f90f6a5967107ded79974f6fe5"),
                      sig: h("9d23098d159bc90cdc19ded378c3fa30dd14e02071603a1f0f33887841ae0c4e6e1701145900c62e3bf699be521fe500d6c19109a8b18fa573e682905e57d72d00"),
                      recId: 0, key: evmKey, evm: true),
            RecVector(name: "O-EVM-1-legacy-etc (v 0x9d)", digest: h("d643f9b1dad82acbc1e697b0716440badf74eec6fa04d24ef2187ca0821aa590"),
                      sig: h("e2305058e4dad036faa325bedf3e0bb38d4457d692cd1cbb1d5263885339a7ca0794b59faa12a8bee9225e334ad2b600d725bc54d591948beeacbb284b0167799d"),
                      recId: (0x9d - 35 - 2 * 61) & 1, key: evmKey, evm: true),
            RecVector(name: "T8-flow-evm-personal (v 1c)", digest: h("12daddf4bfade5f5469a47f9e3859f52e031085934a608030e562c78f1e98355"),
                      sig: h("a6eafc096c566b20a0a283d19fe16c748591e1bf7c07447a26b6d9c4d9622f81140a6a4bd81b636d29f3da80dc21c29b3f6e01ce36c1019a7f4d228afcb56de71c"),
                      recId: 0x1c - 27, key: evmKey, evm: true),
            RecVector(name: "T8-flow-tron-trx-transfer", digest: h("2b4e75505adb4da63b985fa30cab925b334bf5c1432d547c79a780130f3423f5"),
                      sig: h("0b00682655dea28ca48e09034ec29f276380716bd604a0e5de99831a5510bace1913bc9c8268656f7e3bd798b3fc50f7e17b4716e071255900737019adc7e4eb00"),
                      recId: 0, key: tronKey, evm: false),
            RecVector(name: "T8-flow-tron-message", digest: h("677f0dfa15170a4376ab0d59d9300b8e96d56d2a56c00f8c60a9199e5c8d565b"),
                      sig: h("f655feb1ef4f8da80b5b9ebaff4bca87b9f1e429ed63631ed968765b117dffcc56fc3e32d32f60898ef6233b84c359e15278ee8b75aeadce277eb4ac6c359d4400"),
                      recId: 0, key: tronKey, evm: false),
            RecVector(name: "TronLink V1 ownership", digest: BILPublicHash.sha256(Array(v1Entry[2...])),
                      sig: h("c4e4c285fed57e138ab5be476870816067e34d7dbc0cc4eb04f54bc4bb681e3e76a0e0659627a6b78f5761b9d347e002e777570408d4a6ed30ed661f5582c3cd00"),
                      recId: 0, key: tronKey, evm: false),
            RecVector(name: "TronLink V3 transfer", digest: BILPublicHash.sha256(Array(v3Entry[3...])),
                      sig: h("bc7da2e91ff44a0bb59e401c90a790fc4c4b1538570986517a0238224c55f0a147ccb24b14f959e0cbdc26c274d7e25fa4bcd728739d91ec082dcb7ef5dcc36701"),
                      recId: 1, key: tronKey, evm: false),
            RecVector(name: "TronLink V4 TIP-191", digest: BILPublicHash.tip191Digest(ascii("hello ownbit")),
                      sig: h("99b4b65e883463501e600b497cf7293fe2ea7e143c5390a7d57162818a567f7762ef7b8a69a01a3654deb4c73e81263b29b151e3dd2ae91f464f3a3c2aac25501c"),
                      recId: 0x1c - 27, key: tronKey, evm: false),
        ]
        t(recVectors[1].recId == 0 && recVectors[2].recId == 1, "recId derivation from v (0x9d / 0x1c)")

        /// n − v for 0 < v < n (32-byte big-endian).

        for v in recVectors {
            let q = BILSecp256k1.recoverPublicKey(digest: v.digest, recId: v.recId, r: v.r, s: v.s)
            t(q?.count == 65 && q?.first == 0x04, "\(v.name): 65-byte 04 key")
            t(hx(q.flatMap { BILSecp256k1.compress(uncompressed: $0) }) == v.key, "\(v.name): compressed key")
            if v.evm {
                t(evmAddress(q) == evmAddr, "\(v.name): EVM address")
            } else {
                t(tronAddress(q) == tron0, "\(v.name): TRON address")
            }
            t(hx(BILSecp256k1.decompress(compressed: h(v.key))) == hx(q), "\(v.name): decompress(key) == recovered")
            // Tamper: one flipped byte of r / s / digest, or the other parity → never the task key.
            var r2 = v.r; r2[5] ^= 0x01
            let tr = BILSecp256k1.recoverPublicKey(digest: v.digest, recId: v.recId, r: r2, s: v.s)
            t(tr.flatMap { BILSecp256k1.compress(uncompressed: $0) }.map(hx) != v.key, "\(v.name): flipped r byte → other key / nil")
            var s2 = v.s; s2[31] ^= 0x80
            let ts = BILSecp256k1.recoverPublicKey(digest: v.digest, recId: v.recId, r: v.r, s: s2)
            t(ts != nil && ts.flatMap { BILSecp256k1.compress(uncompressed: $0) }.map(hx) != v.key, "\(v.name): flipped s byte → other key")
            var d2 = v.digest; d2[0] ^= 0x01
            let td = BILSecp256k1.recoverPublicKey(digest: d2, recId: v.recId, r: v.r, s: v.s)
            t(td != nil && td.flatMap { BILSecp256k1.compress(uncompressed: $0) }.map(hx) != v.key, "\(v.name): flipped digest byte → other key")
            let tp = BILSecp256k1.recoverPublicKey(digest: v.digest, recId: v.recId ^ 1, r: v.r, s: v.s)
            t(tp != nil && tp.flatMap { BILSecp256k1.compress(uncompressed: $0) }.map(hx) != v.key, "\(v.name): other parity → other key")
            // recId 2 / 3: x = r + n ≥ p for these r (r > p − n) → nil.
            t(BILSecp256k1.recoverPublicKey(digest: v.digest, recId: v.recId | 2, r: v.r, s: v.s) == nil, "\(v.name): recId \(v.recId | 2) → nil")
            t(BILSecp256k1.recoverPublicKey(digest: v.digest, recId: (v.recId ^ 1) | 2, r: v.r, s: v.s) == nil, "\(v.name): recId \((v.recId ^ 1) | 2) → nil")
            // No low-S rule: (r, n − s) with the other parity is the same key (ECDSA malleability; Android accepts both).
            let hs = BILSecp256k1.recoverPublicKey(digest: v.digest, recId: v.recId ^ 1, r: v.r, s: nMinus(v.s))
            t(hx(hs) == hx(q), "\(v.name): (r, n − s, parity ^ 1) recovers the same key (no low-S rule)")
            // Unsigned big-endian semantics: a leading zero byte does not change the integers.
            t(hx(BILSecp256k1.recoverPublicKey(digest: v.digest, recId: v.recId, r: [0] + v.r, s: [0, 0] + v.s)) == hx(q), "\(v.name): leading zero bytes ignored")
        }

        // Out-of-range inputs.
        let v0 = recVectors[0]
        let zero32 = [UInt8](repeating: 0, count: 32)
        let ff32 = [UInt8](repeating: 0xFF, count: 32)
        t(BILSecp256k1.recoverPublicKey(digest: v0.digest, recId: 0, r: zero32, s: v0.s) == nil, "r = 0 → nil")
        t(BILSecp256k1.recoverPublicKey(digest: v0.digest, recId: 0, r: v0.r, s: zero32) == nil, "s = 0 → nil")
        t(BILSecp256k1.recoverPublicKey(digest: v0.digest, recId: 0, r: [], s: v0.s) == nil, "r empty → nil")
        t(BILSecp256k1.recoverPublicKey(digest: v0.digest, recId: 0, r: nBytes, s: v0.s) == nil, "r = n → nil")
        t(BILSecp256k1.recoverPublicKey(digest: v0.digest, recId: 0, r: v0.r, s: nBytes) == nil, "s = n → nil")
        t(BILSecp256k1.recoverPublicKey(digest: v0.digest, recId: 0, r: plusOne(nBytes), s: v0.s) == nil, "r = n + 1 → nil")
        t(BILSecp256k1.recoverPublicKey(digest: v0.digest, recId: 0, r: v0.r, s: ff32) == nil, "s = 2^256 − 1 → nil")
        t(BILSecp256k1.recoverPublicKey(digest: v0.digest, recId: 0, r: [1] + v0.r, s: v0.s) == nil, "r ≥ 2^256 → nil")
        t(BILSecp256k1.recoverPublicKey(digest: Array(v0.digest[0..<31]), recId: 0, r: v0.r, s: v0.s) == nil, "31-byte digest → nil")
        t(BILSecp256k1.recoverPublicKey(digest: v0.digest + [0], recId: 0, r: v0.r, s: v0.s) == nil, "33-byte digest → nil")
        t(BILSecp256k1.recoverPublicKey(digest: v0.digest, recId: -1, r: v0.r, s: v0.s) == nil, "recId −1 → nil")
        t(BILSecp256k1.recoverPublicKey(digest: v0.digest, recId: 4, r: v0.r, s: v0.s) == nil, "recId 4 → nil")
        t(BILSecp256k1.recoverPublicKey(digest: v0.digest, recId: 27, r: v0.r, s: v0.s) == nil, "recId 27 (raw v) → nil")

        // Edge scalars against the reference's exact keys: e = 0 and e = n (u1 = 0: u1·G = ∞, Q = u2·R), e = n + 5 and
        // 2^256 − 1 (reduced mod n), s = 1 and s = n − 1, r = 1, recId 0 and 1, and s·R = e·G (Q = ∞ → nil).
        let edgeLines = ref("ecdsaedge")
        t(edgeLines.count == 12, "reference ecdsaedge count (\(edgeLines.count))")
        t(edgeLines.filter { $0[1] == hx(zero32) }.count == 3 && edgeLines.filter { $0[1] == hx(nBytes) }.count == 2, "edge lines cover e = 0 (3) and e = n (2)")
        t(edgeLines.filter { $0[5] == "nil" }.count == 1, "edge lines cover Q = ∞")
        for line in edgeLines {
            let q = BILSecp256k1.recoverPublicKey(digest: h(line[1]), recId: Int(line[4])!, r: h(line[2]), s: h(line[3]))
            t(hx(q) == line[5], "edge recovery e = \(line[1].prefix(8))… r = …\(line[2].suffix(6)) s = …\(line[3].suffix(6)) recId \(line[4]) → \(line[5].prefix(10))")
        }

        // Reference recoveries (Python, independent code): real signatures incl. high-S and e > n; recId 2 / 3; x off-curve.
        let ecdsaLines = ref("ecdsa")
        t(ecdsaLines.count == 40, "reference ecdsa count")
        var ecdsaBad = 0
        var sawRecId1 = false
        for line in ecdsaLines {
            let recId = Int(line[4])!
            if recId == 1 { sawRecId1 = true }
            let q = BILSecp256k1.recoverPublicKey(digest: h(line[1]), recId: recId, r: h(line[2]), s: h(line[3]))
            if hx(q) != line[5] { ecdsaBad += 1; print("  FAIL ecdsa \(line[1].prefix(16)) recId \(recId)") }
            // round trip through compress / decompress
            if let q = q, let c = BILSecp256k1.compress(uncompressed: q), hx(BILSecp256k1.decompress(compressed: c)) != hx(q) { ecdsaBad += 1 }
        }
        t(ecdsaBad == 0, "reference ECDSA recoveries (\(ecdsaLines.count))")
        t(sawRecId1, "reference ECDSA covers recId 1")
        let recid23 = ref("recid23")
        t(recid23.count == 4, "reference recId 2/3 count")
        for line in recid23 {
            let recId = Int(line[4])!
            t(recId >= 2, "recid23 line uses recId 2/3")
            let q = BILSecp256k1.recoverPublicKey(digest: h(line[1]), recId: recId, r: h(line[2]), s: h(line[3]))
            t(hx(q) == line[5], "recId \(recId) with x = r + n < p recovers the reference key")
            t(BILSecp256k1.recoverPublicKey(digest: h(line[1]), recId: recId & 1, r: h(line[2]), s: h(line[3])).map(hx) != line[5], "recId \(recId & 1) on the same r is another key / nil")
        }
        for line in ref("recnil") {
            t(BILSecp256k1.recoverPublicKey(digest: h(line[1]), recId: Int(line[4])!, r: h(line[2]), s: h(line[3])) == nil, "x = r off the curve → nil")
        }

        // MARK: - compress / decompress / evmAddressBytes

        for line in ref("point") {
            t(hx(BILSecp256k1.compress(uncompressed: h(line[2]))) == line[1], "compress reference point")
            t(hx(BILSecp256k1.decompress(compressed: h(line[1]))) == line[2], "decompress reference point")
        }
        for line in ref("offcurve") {
            t(BILSecp256k1.compress(uncompressed: h(line[1])) == nil, "compress off-curve point → nil")
        }
        let evmUncompressed = BILSecp256k1.decompress(compressed: h(evmKey))!
        t(BILSecp256k1.compress(uncompressed: [0x05] + Array(evmUncompressed[1...])) == nil, "compress wrong prefix → nil")
        t(BILSecp256k1.compress(uncompressed: Array(evmUncompressed[1...])) == nil, "compress 64 bytes → nil")
        t(BILSecp256k1.compress(uncompressed: [0x04] + ff32 + Array(evmUncompressed[33...])) == nil, "compress x ≥ p → nil")
        t(BILSecp256k1.compress(uncompressed: [0x04] + Array(evmUncompressed[1..<33]) + ff32) == nil, "compress y ≥ p → nil")
        t(BILSecp256k1.decompress(compressed: [0x04] + Array(h(evmKey)[1...])) == nil, "decompress prefix 04 → nil")
        t(BILSecp256k1.decompress(compressed: [0x02] + ff32) == nil, "decompress x ≥ p → nil")
        t(BILSecp256k1.decompress(compressed: Array(h(evmKey)[0..<32])) == nil, "decompress 32 bytes → nil")
        t(BILSecp256k1.decompress(compressed: h(evmKey) + [0]) == nil, "decompress 34 bytes → nil")
        let flipped = [h(evmKey)[0] ^ 0x01] + Array(h(evmKey)[1...])
        t(BILSecp256k1.decompress(compressed: flipped).map { $0[33..<65] } != evmUncompressed[33..<65], "decompress other parity → other y")
        t(evmAddress(evmUncompressed) == evmAddr, "evmAddressBytes 65 bytes")
        t(evmAddress(Array(evmUncompressed[1...])) == evmAddr, "evmAddressBytes 64 raw bytes")
        t(BILSecp256k1.evmAddressBytes(uncompressed: h(evmKey)) == nil, "evmAddressBytes 33 bytes → nil")
        t(BILSecp256k1.evmAddressBytes(uncompressed: []) == nil, "evmAddressBytes empty → nil")

        // MARK: - Taproot (BIP-86)

        t(hx(BILSecp256k1.taprootOutputScript(xOnly: bip86Internal)) == bip86Script, "BIP-86 vector (cached)")
        // The other two official BIP-86 vectors (abandon … about): m/86'/0'/0'/0/1 and m/86'/0'/0'/1/0.
        t(hx(BILSecp256k1.taprootOutputScript(xOnly: h("83dfe85a3151d2517290da461fe2815591ef69f2b18a2ce63f01697a8b313145")))
          == "5120a82f29944d65b86ae6b5e5cc75e294ead6c59391a1edc5e016e3498c67fc7bbb", "BIP-86 vector m/86'/0'/0'/0/1")
        t(hx(BILSecp256k1.taprootOutputScript(xOnly: h("399f1b2f4393f29a18c937859c5dd8a77350103157eb880f02e8c08214277cef")))
          == "5120882d74e5d0572d5a816cef0041a96b6c1de832f6f9676d9605c44d5e9a97d3dc", "BIP-86 vector m/86'/0'/0'/1/0")
        t(BILSecp256k1.taprootOutputScript(xOnly: ff32) == nil, "x = ff…ff (≥ p) → nil")
        t(BILSecp256k1.taprootOutputScript(xOnly: ff32) == nil, "x = ff…ff → nil (cached nil)")
        t(BILSecp256k1.taprootOutputScript(xOnly: Array(bip86Internal[0..<31])) == nil, "31-byte key → nil")
        t(BILSecp256k1.taprootOutputScript(xOnly: bip86Internal + [0]) == nil, "33-byte key → nil")
        t(BILSecp256k1.taprootOutputScript(xOnly: []) == nil, "empty key → nil")
        for line in ref("tweaknil") {
            t(BILSecp256k1.taprootOutputScript(xOnly: h(line[1])) == nil, "x off the curve → nil")
        }
        let tweakLines = ref("tweak")
        t(tweakLines.count == 30, "reference tweak count")
        var tweakBad = 0
        for line in tweakLines where hx(BILSecp256k1.taprootOutputScript(xOnly: h(line[1]))) != line[2] { tweakBad += 1 }
        for line in tweakLines where hx(BILSecp256k1.taprootOutputScript(xOnly: h(line[1]))) != line[2] { tweakBad += 1 }   // cache hits
        t(tweakBad == 0, "reference BIP-86 output scripts (\(tweakLines.count), uncached + cached)")
        // The x-only key of a recovered point is its X: the BIP-86 script of the task key of a Taproot input is then stable.
        t(BILSecp256k1.taprootOutputScript(xOnly: Array(evmUncompressed[1..<33]))?.count == 34, "taproot of a real key's x is 34 bytes")

        // Concurrency smoke on a warm table: concurrent recoveries + cache-hit reads (verification runs off-main). The cold
        // start (lazy-table race, concurrent cache stores) is the separate mode "parallel-first" (run.sh runs it).
        let group = DispatchGroup()
        let resultsLock = NSLock()
        var parallelBad = 0
        for i in 0..<8 {
            DispatchQueue.global().async(group: group) {
                let line = tweakLines[i]
                let ok = hx(BILSecp256k1.taprootOutputScript(xOnly: h(line[1]))) == line[2]
                    && hx(BILSecp256k1.recoverPublicKey(digest: recVectors[i % recVectors.count].digest, recId: recVectors[i % recVectors.count].recId,
                                                        r: recVectors[i % recVectors.count].r, s: recVectors[i % recVectors.count].s).flatMap { BILSecp256k1.compress(uncompressed: $0) }) == recVectors[i % recVectors.count].key
                resultsLock.lock(); if !ok { parallelBad += 1 }; resultsLock.unlock()
            }
        }
        group.wait()
        t(parallelBad == 0, "parallel callers on the warm table agree (recoveries + cache hits)")

        // MARK: - Golden sweep: every EVM / TRON signature of vectors.json recovers to its task key and result address

        let vectorsPath = fixtureURL("vectors.json").path
        if let data = FileManager.default.contents(atPath: vectorsPath),
           let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           let cases = root["cases"] as? [[String: Any]] {
            t(sha256File(vectorsPath) == "c9f1e1a29ef6c438638442dd10a03c038b66c31721259cb100312f3f83d46508", "vectors.json pin (SHA-256; the app pins md5 8cf425ba…)")
            // As Android PsbtMapsTest: in the two O-BTC-5 cases (no PSBT_IN_TAP_INTERNAL_KEY) the witness UTXO of input 0 is the
            // BIP-86 output of the task key, i.e. the request PSBT holds `22 ‖ taprootOutputScript(cc8a4bc6…)` (script length + script).
            let witnessUtxo = [UInt8(0x22)] + (BILSecp256k1.taprootOutputScript(xOnly: bip86Internal) ?? [])
            func holds(_ hay: [UInt8], _ needle: [UInt8]) -> Bool {
                guard needle.count > 1, hay.count >= needle.count else { return false }
                for i in 0...(hay.count - needle.count) where hay[i] == needle[0] && Array(hay[i..<(i + needle.count)]) == needle { return true }
                return false
            }
            var taprootPsbts = 0
            for c in cases {
                guard let id = c["id"] as? String, id == "O-BTC-5-taproot-no-internal-key" || id == "O-BTC-5-taproot-no-derivation" else { continue }
                let first = ((c["steps"] as? [[String: Any]]) ?? []).lazy
                    .compactMap { (($0["request"] as? [String: Any])?["request"] as? [String: Any])?["psbt"] as? String }.first
                let psbt = first.flatMap { Data(base64Encoded: $0) }.map { [UInt8]($0) } ?? []
                t(holds(psbt, witnessUtxo), "\(id): request PSBT's witness UTXO is the BIP-86 output of cc8a4bc6…")
                taprootPsbts += 1
            }
            t(taprootPsbts == 2, "golden vectors hold both O-BTC-5 Taproot cases (\(taprootPsbts))")
            var swept = 0
            var sweptBad = 0
            for c in cases {
                var tasks = [String: [String]]()          // task id → publicKeys
                for step in (c["steps"] as? [[String: Any]]) ?? [] {
                    let request = step["request"] as? [String: Any]
                    let response = step["response"] as? [String: Any]
                    guard let op = request?["operation"] as? String, response?["ok"] as? Bool == true,
                          let result = response?["result"] as? [String: Any] else { continue }
                    if op == "resolveSigningPlan" {
                        for task in (result["tasks"] as? [[String: Any]]) ?? [] {
                            if let id = task["id"] as? String, let keys = task["publicKeys"] as? [String] { tasks[id] = keys }
                        }
                    }
                    guard op == "signPlanTask", let chain = result["chain"] as? String, chain == "evm" || chain == "tron",
                          let sigHex = result["signature"] as? String, sigHex.count == 130,
                          var digestHex = result["digest"] as? String, let taskId = result["taskId"] as? String,
                          let address = result["address"] as? String else { continue }
                    if digestHex.hasPrefix("0x") { digestHex = String(digestHex.dropFirst(2)) }
                    let sig = h(sigHex)
                    let v = Int(sig[64])
                    let recId = v >= 27 ? v - 27 : v
                    swept += 1
                    let q = BILSecp256k1.recoverPublicKey(digest: h(digestHex), recId: recId, r: Array(sig[0..<32]), s: Array(sig[32..<64]))
                    let key = q.flatMap { BILSecp256k1.compress(uncompressed: $0) }.map(hx)
                    let keyOk = key != nil && (tasks[taskId] ?? []).map { $0.lowercased() }.contains(key!)
                    let addressOk = chain == "evm" ? evmAddress(q) == address.lowercased() : tronAddress(q) == address
                    if !(keyOk && addressOk) {
                        sweptBad += 1
                        print("  FAIL golden \(c["id"] as? String ?? "?") \(chain) task key \(keyOk) address \(addressOk)")
                    }
                }
            }
            t(swept == 36, "golden sweep found 36 EVM/TRON signatures (found \(swept))")
            t(sweptBad == 0, "golden sweep: every signature recovers to its task key and address")
            print("  golden sweep: \(swept) signatures, \(sweptBad) bad (\(vectorsPath))")
        } else {
            t(false, "cannot read golden vectors \(vectorsPath)")
        }

    }
}
