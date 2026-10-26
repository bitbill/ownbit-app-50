//  WalletSecretCipherTests.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT

import XCTest
@testable import OwnbitCore

final class VaultWalletSecretCipherTests: VaultTestCase {

    typealias Cipher = WalletSecretCipher

    /// Cheap scrypt cost for tests that are not about the parameters themselves.
    private let fastN = 1024
    private let pt = VaultFixtures.mnemonic
    private let pwd = "test password 1"

    private func encrypt(_ text: String, _ password: String, _ binding: Cipher.Binding, salt: Data? = nil) throws -> String {
        return try Cipher.encryptV2(plaintext: text, password: password, binding: binding, salt: salt, n: fastN)
    }

    // MARK: - Round trips

    func testRoundTripPortableAndDevice() throws {
        for binding in [Cipher.Binding.portable, .device] {
            let blob = try encrypt(pt, pwd, binding)
            XCTAssertTrue(blob.hasPrefix("OBV2:"))
            XCTAssertTrue(Cipher.looksLikeV2(blob))
            XCTAssertEqual(try Cipher.decryptV2(blob: blob, password: pwd), pt)
            XCTAssertEqual(try Cipher.decryptV2(blob: blob, password: pwd, useCache: false), pt)

            let env = try XCTUnwrap(Cipher.envelope(blob))
            XCTAssertEqual(env.v, 2)
            XCTAssertEqual(env.kdf, "scrypt")
            XCTAssertEqual(env.cipher, "aes-256-gcm")
            XCTAssertEqual(env.n, fastN)
            XCTAssertEqual(env.r, 8)
            XCTAssertEqual(env.p, 1)
            XCTAssertEqual(env.dklen, 32)
            XCTAssertEqual(env.salt.count, 32)
            XCTAssertEqual(env.nonce.count, 24)
            XCTAssertEqual(env.tag.count, 32)
            XCTAssertEqual(env.bind, binding == .device ? "device" : "none")
            XCTAssertEqual(env.dkfp != nil, binding == .device)
        }
    }

    func testDefaultParameters() throws {
        let blob = try Cipher.encryptV2(plaintext: "x", password: pwd, binding: .portable)
        let env = try XCTUnwrap(Cipher.envelope(blob))
        XCTAssertEqual([env.n, env.r, env.p, env.dklen], [32768, 8, 1, 32])
        XCTAssertEqual(try Cipher.decryptV2(blob: blob, password: pwd), "x")
    }

    func testUnicodePlaintextAndPassword() throws {
        let text = "助记词 測試 émoji 🔑 \u{0}end"
        let password = "密码 пароль 🔒"
        let blob = try encrypt(text, password, .device)
        XCTAssertEqual(try Cipher.decryptV2(blob: blob, password: password), text)
    }

    func testEncryptionIsRandomized() throws {
        let a = try XCTUnwrap(Cipher.envelope(try encrypt(pt, pwd, .portable)))
        let b = try XCTUnwrap(Cipher.envelope(try encrypt(pt, pwd, .portable)))
        XCTAssertNotEqual(a.salt, b.salt)
        XCTAssertNotEqual(a.nonce, b.nonce)
        XCTAssertNotEqual(a.ct, b.ct)
    }

    func testEmptyPasswordCannotEncrypt() {
        XCTAssertThrowsError(try encrypt(pt, "", .portable)) { XCTAssertEqual($0 as? Cipher.CipherError, .kdfFailed) }
        XCTAssertNil(Cipher.reencryptToV2(plaintext: pt, password: ""))
        XCTAssertNil(Cipher.reencryptToV2(plaintext: "", password: pwd))
    }

    func testLooksLikeV2() {
        XCTAssertFalse(Cipher.looksLikeV2(nil))
        XCTAssertFalse(Cipher.looksLikeV2(""))
        XCTAssertFalse(Cipher.looksLikeV2("deadbeef"))
        XCTAssertTrue(Cipher.looksLikeV2("OBV2:"))
    }

    // MARK: - Rejection

    func testWrongPasswordRejected() throws {
        for binding in [Cipher.Binding.portable, .device] {
            let blob = try encrypt(pt, pwd, binding)
            XCTAssertThrowsError(try Cipher.decryptV2(blob: blob, password: "wrong")) {
                XCTAssertEqual($0 as? Cipher.CipherError, .decryptFailed)
            }
            XCTAssertThrowsError(try Cipher.decryptV2(blob: blob, password: ""))
        }
    }

    func testTamperingRejected() throws {
        for binding in [Cipher.Binding.portable, .device] {
            let blob = try encrypt(pt, pwd, binding)
            func flip(_ hex: String) -> String {
                var c = Array(hex)
                c[0] = c[0] == "0" ? "1" : "0"
                return String(c)
            }
            let tampered = [
                rebuild(blob) { $0.ct = flip($0.ct) },
                rebuild(blob) { $0.tag = flip($0.tag) },
                rebuild(blob) { $0.nonce = flip($0.nonce) },
                rebuild(blob) { $0.salt = flip($0.salt) },
                rebuild(blob) { $0.n = self.fastN * 2 },
                rebuild(blob) { $0.bind = (binding == .device ? "none" : "device") },
            ]
            for t in tampered {
                XCTAssertThrowsError(try Cipher.decryptV2(blob: t, password: pwd))
            }
            // A changed base64 character near the end (the app's self-test tamper)
            var chars = Array(blob)
            chars[chars.count - 3] = chars[chars.count - 3] == "A" ? "B" : "A"
            XCTAssertThrowsError(try Cipher.decryptV2(blob: String(chars), password: pwd))
        }
    }

    func testMalformedEnvelopes() throws {
        let blob = try encrypt(pt, pwd, .portable)
        let bad = [
            "deadbeef",
            "OBV2:",
            "OBV2:!!!not base64!!!",
            "OBV2:" + Data("{}".utf8).base64EncodedString(),
            String(blob.dropFirst(5)),                       // no prefix
            rebuild(blob) { $0.v = 3 },
            rebuild(blob) { $0.kdf = "pbkdf2" },
            rebuild(blob) { $0.cipher = "aes-256-cbc" },
            rebuild(blob) { $0.salt = "xyz" },
            rebuild(blob) { $0.ct = "0" },
        ]
        for b in bad {
            XCTAssertThrowsError(try Cipher.decryptV2(blob: b, password: pwd)) {
                XCTAssertEqual($0 as? Cipher.CipherError, .badEnvelope, b)
            }
        }
    }

    // MARK: - Writers with self-check

    func testReencryptSingle() throws {
        let blob = try XCTUnwrap(Cipher.reencryptToV2(plaintext: pt, password: pwd))
        XCTAssertEqual(try Cipher.decryptV2(blob: blob, password: pwd, useCache: false), pt)
        XCTAssertEqual(Cipher.envelope(blob)?.bind, "device")
        let portable = try XCTUnwrap(Cipher.reencryptToV2(plaintext: pt, password: pwd, binding: .portable))
        XCTAssertEqual(Cipher.envelope(portable)?.bind, "none")
    }

    func testGroupSharesSaltWithDistinctNonces() throws {
        let parts = [pt, VaultFixtures.seedHex, "TREZOR"]
        let group = try XCTUnwrap(Cipher.reencryptToV2(plaintexts: parts, password: pwd))
        XCTAssertEqual(group.count, 3)
        let envs = group.compactMap { Cipher.envelope($0) }
        XCTAssertEqual(Set(envs.map { $0.salt }).count, 1)
        XCTAssertEqual(Set(envs.map { $0.nonce }).count, 3)
        Cipher.clearKeyCache()
        for (i, blob) in group.enumerated() {
            XCTAssertEqual(try Cipher.decryptV2(blob: blob, password: pwd, useCache: false), parts[i])
        }
        XCTAssertThrowsError(try Cipher.decryptV2(blob: group[1], password: "wrong"))

        // A second group gets a new salt
        let other = try XCTUnwrap(Cipher.reencryptToV2(plaintexts: parts, password: pwd))
        XCTAssertNotEqual(Cipher.envelope(other[0])?.salt, envs[0].salt)
    }

    func testGroupRunsScryptTwice() throws {
        // One run for the shared salt (then cached) + one fresh run for the first field's no-cache check.
        let before = Cipher.scryptRunCount
        _ = try XCTUnwrap(Cipher.reencryptToV2(plaintexts: ["a", "b", "c"], password: pwd, binding: .portable))
        XCTAssertEqual(Cipher.scryptRunCount - before, 2)
    }

    func testGroupRejectsEmptyInput() {
        XCTAssertNil(Cipher.reencryptToV2(plaintexts: [], password: pwd))
        XCTAssertNil(Cipher.reencryptToV2(plaintexts: ["a", ""], password: pwd))
        XCTAssertNil(Cipher.reencryptToV2(plaintexts: ["a"], password: ""))
    }

    func testGroupFailsWhenDeviceKeyCannotBeStored() {
        store.failAdds = true
        XCTAssertNil(Cipher.reencryptToV2(plaintexts: ["a", "b"], password: pwd))
        XCTAssertNotNil(Cipher.reencryptToV2(plaintexts: ["a", "b"], password: pwd, binding: .portable))
    }

    // MARK: - scrypt cache

    func testCacheHitReturnsSameResultWithoutScrypt() throws {
        let blob = try encrypt(pt, pwd, .portable)
        Cipher.clearKeyCache()
        let start = Cipher.scryptRunCount
        let first = try Cipher.decryptV2(blob: blob, password: pwd)
        XCTAssertEqual(Cipher.scryptRunCount, start + 1)
        let second = try Cipher.decryptV2(blob: blob, password: pwd)
        XCTAssertEqual(Cipher.scryptRunCount, start + 1, "second decryption must hit the cache")
        XCTAssertEqual(first, pt)
        XCTAssertEqual(second, first)
        // useCache: false always derives again
        XCTAssertEqual(try Cipher.decryptV2(blob: blob, password: pwd, useCache: false), pt)
        XCTAssertEqual(Cipher.scryptRunCount, start + 2)
    }

    func testWrongPasswordFailsWithWarmCache() throws {
        for binding in [Cipher.Binding.portable, .device] {
            let blob = try encrypt(pt, pwd, binding)
            XCTAssertEqual(try Cipher.decryptV2(blob: blob, password: pwd), pt)       // warm for the right password
            for _ in 0..<2 {                                                          // and for the wrong one
                XCTAssertThrowsError(try Cipher.decryptV2(blob: blob, password: "wrong")) {
                    XCTAssertEqual($0 as? Cipher.CipherError, .decryptFailed)
                }
            }
            XCTAssertEqual(try Cipher.decryptV2(blob: blob, password: pwd), pt)
        }
    }

    func testCacheExpiresSixtySecondsAfterLastUse() throws {
        var t = Date(timeIntervalSince1970: 1_000_000)
        Cipher.now = { t }
        let blob = try encrypt(pt, pwd, .portable)       // cached at t
        let start = Cipher.scryptRunCount
        t += 59
        _ = try Cipher.decryptV2(blob: blob, password: pwd)
        XCTAssertEqual(Cipher.scryptRunCount, start, "hit at +59 s (and refreshes last use)")
        t += 59
        _ = try Cipher.decryptV2(blob: blob, password: pwd)
        XCTAssertEqual(Cipher.scryptRunCount, start, "hit 59 s after the last use")
        t += 60
        _ = try Cipher.decryptV2(blob: blob, password: pwd)
        XCTAssertEqual(Cipher.scryptRunCount, start + 1, "expired 60 s after the last use")
    }

    func testCacheKeepsAtMostSixteenEntries() throws {
        var t = Date(timeIntervalSince1970: 2_000_000)
        Cipher.now = { t }
        var blobs: [String] = []
        for i in 0..<17 {
            t += 1
            blobs.append(try encrypt("field \(i)", pwd, .portable))   // each has its own salt -> own cache entry
        }
        let start = Cipher.scryptRunCount
        _ = try Cipher.decryptV2(blob: blobs[16], password: pwd)
        XCTAssertEqual(Cipher.scryptRunCount, start, "newest entry is cached")
        _ = try Cipher.decryptV2(blob: blobs[0], password: pwd)
        XCTAssertEqual(Cipher.scryptRunCount, start + 1, "oldest entry was evicted")
    }

    func testClearKeyCache() throws {
        let blob = try encrypt(pt, pwd, .portable)
        let start = Cipher.scryptRunCount
        Cipher.clearKeyCache()
        _ = try Cipher.decryptV2(blob: blob, password: pwd)
        XCTAssertEqual(Cipher.scryptRunCount, start + 1)
    }

    func testPrewarmFillsTheCache() throws {
        let blob = try encrypt(pt, pwd, .device)
        Cipher.clearKeyCache()
        Cipher.prewarm(blob: blob, password: pwd)
        let start = Cipher.scryptRunCount
        XCTAssertEqual(try Cipher.decryptV2(blob: blob, password: pwd), pt)
        XCTAssertEqual(Cipher.scryptRunCount, start)
        // No-ops
        Cipher.prewarm(blob: nil, password: pwd)
        Cipher.prewarm(blob: "deadbeef", password: pwd)
        Cipher.prewarm(blob: blob, password: "")
        XCTAssertEqual(Cipher.scryptRunCount, start)
    }

    // MARK: - Device binding

    func testDeviceKeyCreatedOnceAndReused() throws {
        XCTAssertFalse(Cipher.deviceKeyExists())
        _ = try encrypt(pt, pwd, .portable)
        XCTAssertFalse(Cipher.deviceKeyExists(), "portable never creates the device key")
        let a = try encrypt(pt, pwd, .device)
        XCTAssertTrue(Cipher.deviceKeyExists())
        let key = try XCTUnwrap(store.storedKey)
        XCTAssertEqual(key.count, 32)
        let b = try encrypt(pt, pwd, .device)
        XCTAssertEqual(store.storedKey, key)
        XCTAssertEqual(store.addCount, 1)
        XCTAssertEqual(Cipher.envelope(a)?.dkfp, Cipher.deviceKeyFingerprint(key))
        XCTAssertEqual(Cipher.envelope(b)?.dkfp, Cipher.deviceKeyFingerprint(key))
    }

    func testLosingTheCreationRaceUsesTheWinnersKey() throws {
        let winner = Data(repeating: 0x42, count: 32)
        store.raceWinner = winner
        let blob = try encrypt(pt, pwd, .device)
        XCTAssertEqual(Cipher.envelope(blob)?.dkfp, Cipher.deviceKeyFingerprint(winner))
        XCTAssertEqual(try Cipher.decryptV2(blob: blob, password: pwd), pt)
    }

    func testBindingStatusOk() throws {
        let blob = try encrypt(pt, pwd, .device)
        XCTAssertEqual(Cipher.deviceBindingStatus(blob), .ok)
        // An envelope without a fingerprint is still ok when the key opens it (dkfp is optional in the format)
        let noFp = rebuild(blob) { $0.dkfp = nil }
        XCTAssertEqual(Cipher.deviceBindingStatus(noFp), .ok)
        XCTAssertEqual(try Cipher.decryptV2(blob: noFp, password: pwd), pt)
    }

    func testBindingStatusNotDeviceBound() throws {
        XCTAssertEqual(Cipher.deviceBindingStatus(try encrypt(pt, pwd, .portable)), .notDeviceBound)
        XCTAssertEqual(Cipher.deviceBindingStatus(nil), .notDeviceBound)
        XCTAssertEqual(Cipher.deviceBindingStatus(""), .notDeviceBound)
        XCTAssertEqual(Cipher.deviceBindingStatus("deadbeef"), .notDeviceBound)
        XCTAssertEqual(Cipher.deviceBindingStatus("OBV2:garbage"), .notDeviceBound)
    }

    func testBindingStatusNeedRestoreWithFakeFingerprint() throws {
        let blob = try encrypt(pt, pwd, .device)
        let fake = rebuild(blob) { $0.dkfp = "0000000000000000" }
        XCTAssertEqual(Cipher.deviceBindingStatus(fake), .needRestore)
        XCTAssertThrowsError(try Cipher.decryptV2(blob: fake, password: pwd)) {
            XCTAssertEqual($0 as? Cipher.CipherError, .deviceKeyMismatch)
        }
    }

    func testBindingStatusNeedRestoreOnAnotherDevice() throws {
        let blob = try encrypt(pt, pwd, .device)

        // Another device: a different device key
        WalletSecretCipher.deviceKeyStore = VaultMemoryKeyStore(key: Data(repeating: 7, count: 32))
        XCTAssertEqual(Cipher.deviceBindingStatus(blob), .needRestore)
        XCTAssertThrowsError(try Cipher.decryptV2(blob: blob, password: pwd)) {
            XCTAssertEqual($0 as? Cipher.CipherError, .deviceKeyMismatch)
        }

        // A device with no device key at all (fresh restore)
        WalletSecretCipher.deviceKeyStore = VaultMemoryKeyStore()
        XCTAssertEqual(Cipher.deviceBindingStatus(blob), .needRestore)
        XCTAssertFalse(Cipher.deviceKeyExists())
        XCTAssertThrowsError(try Cipher.decryptV2(blob: blob, password: pwd)) {
            XCTAssertEqual($0 as? Cipher.CipherError, .deviceKeyUnavailable)
        }
        XCTAssertFalse(Cipher.deviceKeyExists(), "decryption never creates a device key")

        // Back on the original device
        WalletSecretCipher.deviceKeyStore = store
        XCTAssertEqual(Cipher.deviceBindingStatus(blob), .ok)
        XCTAssertEqual(try Cipher.decryptV2(blob: blob, password: pwd), pt)
    }

    func testStoreFailures() throws {
        let blob = try encrypt(pt, pwd, .device)
        store.failLoads = true
        XCTAssertEqual(Cipher.deviceBindingStatus(blob), .needRestore)
        XCTAssertFalse(Cipher.deviceKeyExists())
        XCTAssertThrowsError(try Cipher.decryptV2(blob: blob, password: pwd)) {
            XCTAssertEqual($0 as? Cipher.CipherError, .deviceKeyUnavailable)
        }
        XCTAssertThrowsError(try encrypt(pt, pwd, .device)) {
            XCTAssertEqual($0 as? Cipher.CipherError, .deviceKeyUnavailable)
        }
        store.failLoads = false

        // A stored key of the wrong size is unusable
        WalletSecretCipher.deviceKeyStore = VaultMemoryKeyStore(key: Data(repeating: 1, count: 16))
        XCTAssertFalse(Cipher.deviceKeyExists())
        XCTAssertThrowsError(try encrypt(pt, pwd, .device)) {
            XCTAssertEqual($0 as? Cipher.CipherError, .deviceKeyUnavailable)
        }
    }

    // MARK: - Known answers and app compatibility

    /// Fixed salt / nonce / device key through the internal seam. Expected ct / tag were computed independently:
    /// scrypt key with Python `hashlib.scrypt`, device key with Python `hmac` (HMAC-SHA256), AES-256-GCM with
    /// CryptoSwift 1.8.0 (not CryptoKit).
    func testKnownAnswerVectors() throws {
        store = VaultMemoryKeyStore(key: VaultFixtures.deviceKey)
        WalletSecretCipher.deviceKeyStore = store
        let expected: [(Cipher.Binding, String, String, String?)] = [
            (.portable,
             "05bfb7edafb3fd46565aff5ff120c80b2c94bab480b78bf0b3c679bcc3fa2749a1f21193b5f7649b556cceba319e1f5f810d684b562ef8cf95b0409155d5a8bad072eb72ba7aa889d315a1c36e8f737feb081f95eb7b385cbed27dfd13",
             "0bd643d55ff417fc2bea8f4323f1691c", nil),
            (.device,
             "409036b46b8c641672585538cf4baa107b0842b30dda3a6c6d420f514058ad461e55780f8b13a3f081198bb815b57a8da87a1c50266537c6b30ee072077b2f90bd4b809cf1226f8e0405618b5a62cadcac3e6d2ad65032bb18b6f1a868",
             "d32d50646d7d0f6787d6febf567229d1", "72dbb7336c767800"),
        ]
        for (binding, ct, tag, dkfp) in expected {
            let blob = try Cipher.encryptV2(plaintext: VaultFixtures.mnemonic, password: VaultFixtures.password,
                                            binding: binding, salt: VaultFixtures.salt, nonce: VaultFixtures.nonce,
                                            n: 32768, r: 8, p: 1)
            let env = try XCTUnwrap(Cipher.envelope(blob))
            XCTAssertEqual(env, Cipher.Envelope(v: 2, kdf: "scrypt", n: 32768, r: 8, p: 1, dklen: 32,
                                                salt: "000102030405060708090a0b0c0d0e0f",
                                                bind: binding == .device ? "device" : "none", dkfp: dkfp,
                                                cipher: "aes-256-gcm", nonce: "a0a1a2a3a4a5a6a7a8a9aaab",
                                                ct: ct, tag: tag), binding.rawValue)
            XCTAssertEqual(try Cipher.decryptV2(blob: blob, password: VaultFixtures.password, useCache: false),
                           VaultFixtures.mnemonic)
        }
        // The same vectors as stored strings (JSON key order is not significant)
        let stored = [
            "OBV2:eyJ0YWciOiIwYmQ2NDNkNTVmZjQxN2ZjMmJlYThmNDMyM2YxNjkxYyIsImtkZiI6InNjcnlwdCIsImRrbGVuIjozMiwic2FsdCI6IjAwMDEwMjAzMDQwNTA2MDcwODA5MGEwYjBjMGQwZTBmIiwiYmluZCI6Im5vbmUiLCJjdCI6IjA1YmZiN2VkYWZiM2ZkNDY1NjVhZmY1ZmYxMjBjODBiMmM5NGJhYjQ4MGI3OGJmMGIzYzY3OWJjYzNmYTI3NDlhMWYyMTE5M2I1Zjc2NDliNTU2Y2NlYmEzMTllMWY1ZjgxMGQ2ODRiNTYyZWY4Y2Y5NWIwNDA5MTU1ZDVhOGJhZDA3MmViNzJiYTdhYTg4OWQzMTVhMWMzNmU4ZjczN2ZlYjA4MWY5NWViN2IzODVjYmVkMjdkZmQxMyIsInAiOjEsImNpcGhlciI6ImFlcy0yNTYtZ2NtIiwibm9uY2UiOiJhMGExYTJhM2E0YTVhNmE3YThhOWFhYWIiLCJ2IjoyLCJyIjo4LCJuIjozMjc2OH0=",
            "OBV2:eyJka2ZwIjoiNzJkYmI3MzM2Yzc2NzgwMCIsInAiOjEsImJpbmQiOiJkZXZpY2UiLCJuIjozMjc2OCwibm9uY2UiOiJhMGExYTJhM2E0YTVhNmE3YThhOWFhYWIiLCJjaXBoZXIiOiJhZXMtMjU2LWdjbSIsImtkZiI6InNjcnlwdCIsImN0IjoiNDA5MDM2YjQ2YjhjNjQxNjcyNTg1NTM4Y2Y0YmFhMTA3YjA4NDJiMzBkZGEzYTZjNmQ0MjBmNTE0MDU4YWQ0NjFlNTU3ODBmOGIxM2EzZjA4MTE5OGJiODE1YjU3YThkYTg3YTFjNTAyNjY1MzdjNmIzMGVlMDcyMDc3YjJmOTBiZDRiODA5Y2YxMjI2ZjhlMDQwNTYxOGI1YTYyY2FkY2FjM2U2ZDJhZDY1MDMyYmIxOGI2ZjFhODY4IiwidGFnIjoiZDMyZDUwNjQ2ZDdkMGY2Nzg3ZDZmZWJmNTY3MjI5ZDEiLCJka2xlbiI6MzIsInNhbHQiOiIwMDAxMDIwMzA0MDUwNjA3MDgwOTBhMGIwYzBkMGUwZiIsInYiOjIsInIiOjh9",
        ]
        for blob in stored {
            XCTAssertEqual(try Cipher.decryptV2(blob: blob, password: VaultFixtures.password), VaultFixtures.mnemonic)
        }
    }

    /// Envelopes produced by the app's own WalletSecretCipher.swift (random salt and nonce; the `.device` one with
    /// device key 2021…3f). The app file was compiled for macOS with only three edits: no `import UIKit`, a plain
    /// notification name for the background observer, and a hook that supplies that device key instead of the
    /// keychain.
    func testDecryptsEnvelopesWrittenByTheApp() throws {
        store = VaultMemoryKeyStore(key: VaultFixtures.deviceKey)
        WalletSecretCipher.deviceKeyStore = store
        let portable = "OBV2:eyJ2IjoyLCJjdCI6ImExMThjODViMWU4NGVkMTA5ZDE3NjgwZTY5NjE3NGY1YTI1ZTcwYzYzZmMwODJmMzU2MjA5Y2UzNDRhNDQzMzc1ZDRlYjdkYTMyMTA0OTJkNWE5NmM4NzExZTg4YmEyZWVhMWM0ZThlMTk3Nzg5M2MwODRiMTY1ZjE4ODg3M2E0OWIyNzFiNjgzNGFiZmQ5NTg2ZjM3MzEwYTUyODFhN2YzNTRkMjYzOWFjNDMwYWM1M2Q3YTU3Y2UzZiIsInRhZyI6IjJhOWZhMTM4NmNkMTI0ODA2NDZkYTJlMDkxYmI2NTU4Iiwia2RmIjoic2NyeXB0IiwiZGtsZW4iOjMyLCJjaXBoZXIiOiJhZXMtMjU2LWdjbSIsInIiOjgsInAiOjEsInNhbHQiOiJlMzRlMmM1YzRjYTkyNjAyOTUwNDk3YzBhYjE1YzhkYiIsIm5vbmNlIjoiY2Q4ODIyMDVmMGRmNWJmNGQ2MmRhMTAxIiwibiI6MzI3NjgsImJpbmQiOiJub25lIn0="
        let device = "OBV2:eyJiaW5kIjoiZGV2aWNlIiwidiI6MiwicCI6MSwic2FsdCI6IjRjZTM1MTcyYjY3MTY1NjFmNzU1NjA0YzVjMDE0NTk2IiwiZGtsZW4iOjMyLCJjaXBoZXIiOiJhZXMtMjU2LWdjbSIsImtkZiI6InNjcnlwdCIsIm5vbmNlIjoiYWQyYmY5MDdiZDY4OWM0NGViNjNmNDNmIiwidGFnIjoiNmIwMjY5MTJmMmNmM2MyNjkxNjk0YjRkMjJmZDZjYTMiLCJjdCI6Ijc1Y2FiNmJiYjE3NzBlOGE2MzViN2FhZmRhM2VkNGYxNjU5YzdjOWE0Mzg2NTU4NzBlZGFlZmZiOTMzYzY5YzU3NzllOTUwNjA4ZDExMjA4OWRiYjU4NDM5NDUyZWNjMjc4NTgxMmE4MmFlNmY2M2I0NjNiZjQzMGQxOTU4YjM4MzhhZWM5OWU4ZDNjYzk5MzJhNDA4ODk1OTg2NjNmMmFkOTRmZDEzNDVhYjZmOTUwYzNhYjVkODc5YyIsImRrZnAiOiI3MmRiYjczMzZjNzY3ODAwIiwibiI6MzI3NjgsInIiOjh9"
        XCTAssertEqual(try Cipher.decryptV2(blob: portable, password: VaultFixtures.password), VaultFixtures.mnemonic)
        XCTAssertEqual(try Cipher.decryptV2(blob: device, password: VaultFixtures.password), VaultFixtures.mnemonic)
        XCTAssertEqual(Cipher.deviceBindingStatus(portable), .notDeviceBound)
        XCTAssertEqual(Cipher.deviceBindingStatus(device), .ok)
        XCTAssertThrowsError(try Cipher.decryptV2(blob: device, password: "wrong"))
    }

    // MARK: - Self-test

    func testRunSelfTestPasses() {
        XCTAssertNil(Cipher.runSelfTest())
    }
}
