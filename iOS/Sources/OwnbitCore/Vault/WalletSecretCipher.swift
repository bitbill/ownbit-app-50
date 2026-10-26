//  WalletSecretCipher.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Ownbit Vault v2: how wallet secrets (mnemonic, BIP39 seed, BIP39 passphrase, private key, WIF) are encrypted
//  at rest. This file only turns "plaintext string <-> envelope string"; it knows nothing about wallets and never
//  stores a password.
//
//    KDF       scrypt, N = 32768, r = 8, p = 1, dkLen = 32, random 16-byte salt (parameters stored in the envelope)
//    cipher    AES-256-GCM, random 12-byte nonce per envelope, 16-byte tag
//    binding   .device   — AES key = HMAC-SHA256(key: deviceKey, message: scryptKey). The device key is 32 random
//                          bytes in a ThisDeviceOnly keychain item (see DeviceKeyStore), so a copied envelope
//                          cannot be brute-forced off the device, however weak the password.
//              .portable — AES key = scryptKey. Used for cloud backups, which must restore on a new device; they
//                          rely on the strength of the backup password (the app derives that password; how is not
//                          part of this package).
//
//  Envelope string: "OBV2:" + base64(JSON), JSON fields
//    v (2), kdf ("scrypt"), n, r, p, dklen, salt (hex), bind ("none" | "device"),
//    dkfp (hex of the first 8 bytes of SHA-256(deviceKey); only when bind == "device"),
//    cipher ("aes-256-gcm"), nonce (hex), ct (hex), tag (hex).
//  Hex is lowercase; base64 is standard with padding and no line breaks. Nothing in the envelope is secret.
//
//  Rules
//    1. A writer only keeps an envelope after an in-place round trip (encrypt -> decrypt == plaintext) passed;
//       `reencryptToV2` returns nil otherwise and the caller must keep what it had.
//    2. Decryption is authenticated by the GCM tag: wrong password, tampered envelope or missing device key all fail.
//    3. The fields of one wallet are encrypted together with ONE salt (one scrypt run per password entry) and a
//       fresh nonce each; a 60-second in-memory scrypt cache makes "check password, then decrypt seed, then decrypt
//       passphrase" cost a single scrypt run.
//
//  Device migration: `.device` envelopes are bound to this device's key. Restoring a full device backup onto a new
//  phone does not carry the key over, so those envelopes cannot be opened there (`deviceBindingStatus` returns
//  `.needRestore`); the user restores from a `.portable` cloud backup or re-imports the mnemonic.

import Foundation
import CryptoKit
#if canImport(UIKit) && !os(watchOS)
import UIKit
#endif

public enum WalletSecretCipher {

    /// Prefix of every v2 envelope ("Ownbit Vault v2").
    public static let v2Prefix = "OBV2:"

    /// How the AES key is bound.
    public enum Binding: String {
        /// scrypt only; decryptable anywhere with the password (cloud backups).
        case portable
        /// scrypt + this device's key; decryptable only on this device (local storage).
        case device
    }

    public enum CipherError: Error, Equatable {
        case badEnvelope
        case kdfFailed
        /// No device key on this device (typically a new device restored from a full backup).
        case deviceKeyUnavailable
        /// A device key exists but it is not the one the envelope was written with.
        case deviceKeyMismatch
        case selfCheckFailed
        /// Wrong password or tampered envelope.
        case decryptFailed
    }

    /// Binding state of an envelope relative to this device. Needs no password (the envelope is plain JSON).
    public enum DeviceBindingStatus: Equatable {
        /// Not a v2 envelope, or a `.portable` one.
        case notDeviceBound
        /// `.device` envelope and this device holds the matching device key.
        case ok
        /// `.device` envelope but this device does not hold that key: restore from a cloud backup or re-import.
        case needRestore
    }

    // MARK: - Parameters

    // N = 2^15: about 70 ms per derivation in a Release build on a recent iPhone/Mac (about 2.6x that in a Debug
    // build). It runs on every unlock, so it is kept moderate; the random salt defeats precomputation and the device
    // binding is what protects weak PINs. Parameters live in the envelope, so they can change without touching
    // existing envelopes.
    public static let defaultN = 32768
    public static let defaultR = 8
    public static let defaultP = 1
    static let dkLen = 32       // AES-256
    static let saltLen = 16
    static let nonceLen = 12    // standard 96-bit GCM nonce

    // MARK: - Device key store

    private static let storeLock = NSLock()
    private static var _deviceKeyStore: DeviceKeyStore = KeychainDeviceKeyStore()

    /// Where the device key is kept. Defaults to the app's keychain item (`KeychainDeviceKeyStore()`).
    /// Set it once at start-up if you need something else; tests inject an in-memory store.
    public static var deviceKeyStore: DeviceKeyStore {
        get { storeLock.lock(); defer { storeLock.unlock() }; return _deviceKeyStore }
        set { storeLock.lock(); _deviceKeyStore = newValue; storeLock.unlock() }
    }

    // MARK: - Envelope

    /// Self-describing envelope. All fields are public information; the only secrets are the password and the
    /// device key. Field names and the optional `dkfp` (omitted when nil) are part of the stored format.
    struct Envelope: Codable, Equatable {
        var v: Int          // version, 2
        var kdf: String     // "scrypt"
        var n: Int
        var r: Int
        var p: Int
        var dklen: Int
        var salt: String    // hex
        var bind: String    // "none" | "device"
        var dkfp: String?   // device key fingerprint, only for bind == "device"
        var cipher: String  // "aes-256-gcm"
        var nonce: String   // hex
        var ct: String      // hex, ciphertext
        var tag: String     // hex, GCM tag
    }

    // MARK: - Detection

    /// True when `blob` is a v2 envelope (starts with "OBV2:").
    public static func looksLikeV2(_ blob: String?) -> Bool {
        guard let blob = blob else { return false }
        return blob.hasPrefix(v2Prefix)
    }

    // MARK: - Encrypt / decrypt

    /// Plaintext -> v2 envelope.
    /// - Parameters:
    ///   - binding: `.device` for local storage (default), `.portable` for cloud backups.
    ///   - salt: nil generates a fresh 16-byte salt. Pass the same salt for the fields of one wallet
    ///     (see `reencryptToV2(plaintexts:password:binding:)`).
    /// - Throws: `CipherError` (`.kdfFailed` for an empty password).
    public static func encryptV2(plaintext: String,
                                 password: String,
                                 binding: Binding = .device,
                                 salt: Data? = nil,
                                 n: Int = defaultN,
                                 r: Int = defaultR,
                                 p: Int = defaultP) throws -> String {
        return try encryptV2(plaintext: plaintext, password: password, binding: binding,
                             salt: salt, nonce: nil, n: n, r: r, p: p)
    }

    /// Test seam: same as the public `encryptV2` but with an optional fixed nonce (known-answer tests).
    static func encryptV2(plaintext: String,
                          password: String,
                          binding: Binding,
                          salt: Data?,
                          nonce fixedNonce: Data?,
                          n: Int,
                          r: Int,
                          p: Int) throws -> String {
        guard !password.isEmpty else { throw CipherError.kdfFailed }
        let salt = salt ?? SecureRandom.bytes(saltLen)
        guard let scryptKey = derivedKey(password: password, salt: salt, n: n, r: r, p: p, dklen: dkLen) else {
            throw CipherError.kdfFailed
        }
        var dkfp: String? = nil
        let keyData: Data
        switch binding {
        case .portable:
            keyData = scryptKey
        case .device:
            let dk = try deviceKey(create: true)
            keyData = hmacKey(scryptKey: scryptKey, deviceKey: dk)
            dkfp = deviceKeyFingerprint(dk)
        }
        let key = SymmetricKey(data: keyData)
        let nonceData = fixedNonce ?? SecureRandom.bytes(nonceLen)
        let nonce = try AES.GCM.Nonce(data: nonceData)
        guard let ptData = plaintext.data(using: .utf8) else { throw CipherError.decryptFailed }
        let sealed = try AES.GCM.seal(ptData, using: key, nonce: nonce)

        let env = Envelope(v: 2, kdf: "scrypt", n: n, r: r, p: p, dklen: dkLen,
                           salt: salt.hexString, bind: (binding == .device ? "device" : "none"),
                           dkfp: dkfp,
                           cipher: "aes-256-gcm",
                           nonce: nonceData.hexString, ct: Data(sealed.ciphertext).hexString,
                           tag: Data(sealed.tag).hexString)
        guard let json = try? JSONEncoder().encode(env) else { throw CipherError.badEnvelope }
        return v2Prefix + json.base64EncodedString()
    }

    /// v2 envelope -> plaintext.
    /// - Parameter useCache: false runs scrypt again even when a cached key exists (write-time round trip checks:
    ///   proves the envelope opens without the cache).
    /// - Throws: `.badEnvelope`, `.kdfFailed`, `.deviceKeyUnavailable`, `.deviceKeyMismatch`, `.decryptFailed`.
    public static func decryptV2(blob: String, password: String, useCache: Bool = true) throws -> String {
        guard let env = envelope(blob), env.v == 2, env.kdf == "scrypt", env.cipher == "aes-256-gcm" else {
            throw CipherError.badEnvelope
        }
        guard let saltData = envelopeHex(env.salt),
              let nonceData = envelopeHex(env.nonce),
              let ctData = envelopeHex(env.ct),
              let tagData = envelopeHex(env.tag) else {
            throw CipherError.badEnvelope
        }
        guard let scryptKey = derivedKey(password: password, salt: saltData, n: env.n, r: env.r, p: env.p,
                                         dklen: env.dklen, useCache: useCache) else {
            throw CipherError.kdfFailed
        }
        let keyData: Data
        if env.bind == "device" {
            // Decryption never creates a device key: no key here means this is another device.
            guard let dk = try deviceKeyPeek() else { throw CipherError.deviceKeyUnavailable }
            if let fp = env.dkfp, fp != deviceKeyFingerprint(dk) { throw CipherError.deviceKeyMismatch }
            keyData = hmacKey(scryptKey: scryptKey, deviceKey: dk)
        } else {
            keyData = scryptKey
        }
        let key = SymmetricKey(data: keyData)
        do {
            let box = try AES.GCM.SealedBox(nonce: try AES.GCM.Nonce(data: nonceData),
                                            ciphertext: ctData, tag: tagData)
            let pt = try AES.GCM.open(box, using: key)
            guard let s = String(data: pt, encoding: .utf8) else { throw CipherError.decryptFailed }
            return s
        } catch {
            throw CipherError.decryptFailed
        }
    }

    // MARK: - Writing with an in-place self-check

    /// Encrypts one secret (fresh salt) and returns the envelope only if it decrypts back to `plaintext` without the
    /// scrypt cache. Nil otherwise: the caller must keep what it had and must not write anything.
    public static func reencryptToV2(plaintext: String, password: String, binding: Binding = .device) -> String? {
        guard !plaintext.isEmpty, !password.isEmpty else { return nil }
        do {
            let blob = try encryptV2(plaintext: plaintext, password: password, binding: binding)
            let roundTrip = try decryptV2(blob: blob, password: password, useCache: false)
            guard roundTrip == plaintext else { return nil }
            return blob
        } catch {
            return nil
        }
    }

    /// Encrypts the fields of one wallet together: one shared salt (one scrypt run), a fresh nonce per field, and a
    /// round-trip check per field (the first one re-derives without the cache, proving the envelopes still open
    /// after the cache expires). Any empty input or any failure returns nil for the whole group.
    public static func reencryptToV2(plaintexts: [String], password: String, binding: Binding = .device) -> [String]? {
        guard !plaintexts.isEmpty, !password.isEmpty, !plaintexts.contains(where: { $0.isEmpty }) else { return nil }
        let salt = SecureRandom.bytes(saltLen)
        var out: [String] = []
        for pt in plaintexts {
            guard let blob = try? encryptV2(plaintext: pt, password: password, binding: binding, salt: salt),
                  (try? decryptV2(blob: blob, password: password, useCache: !out.isEmpty)) == pt else { return nil }
            out.append(blob)
        }
        return out
    }

    /// Runs the scrypt this envelope needs (call it on a background queue) so the decryption that follows on the main
    /// thread hits the cache. Does nothing for non-v2 / unparsable input. Does not decrypt, does not touch the
    /// device key.
    public static func prewarm(blob: String?, password: String) {
        guard let blob = blob, !password.isEmpty, let env = envelope(blob),
              env.v == 2, env.kdf == "scrypt",
              let salt = envelopeHex(env.salt) else { return }
        _ = derivedKey(password: password, salt: salt, n: env.n, r: env.r, p: env.p, dklen: env.dklen)
    }

    // MARK: - Short-lived scrypt cache
    //
    // Memory only. An entry expires 60 s after its last use; at most 16 entries (least recently used goes first);
    // cleared as soon as the app enters the background. The cache key is SHA-256(params | salt | 0x00 | password);
    // the password itself is not stored.

    private static let keyCacheTTL: TimeInterval = 60
    private static let keyCacheLimit = 16
    private static let keyCacheLock = NSLock()
    private static var keyCache: [Data: (key: Data, lastUsed: Date)] = [:]
    #if canImport(UIKit) && !os(watchOS)
    private static let keyCacheObserver: NSObjectProtocol? = NotificationCenter.default.addObserver(
        forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil) { _ in
            WalletSecretCipher.clearKeyCache()
        }
    #else
    private static let keyCacheObserver: NSObjectProtocol? = nil
    #endif

    /// Test seams: the cache clock and the number of real scrypt runs.
    static var now: () -> Date = { Date() }
    private(set) static var scryptRunCount = 0

    /// Drops every cached scrypt key (done automatically when the app enters the background).
    public static func clearKeyCache() {
        keyCacheLock.lock()
        keyCache.removeAll()
        keyCacheLock.unlock()
    }

    private static func runScrypt(password: String, salt: Data, n: Int, r: Int, p: Int, dklen: Int) -> Data? {
        keyCacheLock.lock()
        scryptRunCount += 1
        keyCacheLock.unlock()
        guard let key = Scrypt.derive(password: password, salt: salt, dkLen: dklen, n: n, r: r, p: p),
              key.count == dklen else { return nil }
        return key
    }

    private static func derivedKey(password: String, salt: Data, n: Int, r: Int, p: Int, dklen: Int,
                                   useCache: Bool = true) -> Data? {
        guard useCache else {
            return runScrypt(password: password, salt: salt, n: n, r: r, p: p, dklen: dklen)
        }
        _ = keyCacheObserver
        var material = Data("\(n)|\(r)|\(p)|\(dklen)|".utf8)
        material.append(salt)
        material.append(0)
        material.append(Data(password.utf8))
        let cacheKey = Data(SHA256.hash(data: material))
        let time = now()
        keyCacheLock.lock()
        keyCache = keyCache.filter { time.timeIntervalSince($0.value.lastUsed) < keyCacheTTL }
        if let hit = keyCache[cacheKey] {
            keyCache[cacheKey] = (hit.key, time)
            keyCacheLock.unlock()
            return hit.key
        }
        keyCacheLock.unlock()
        guard let key = runScrypt(password: password, salt: salt, n: n, r: r, p: p, dklen: dklen) else { return nil }
        keyCacheLock.lock()
        if keyCache.count >= keyCacheLimit,
           let oldest = keyCache.min(by: { $0.value.lastUsed < $1.value.lastUsed })?.key {
            keyCache.removeValue(forKey: oldest)
        }
        keyCache[cacheKey] = (key, now())
        keyCacheLock.unlock()
        return key
    }

    // MARK: - Device key

    /// Reads the device key without creating one. Nil when there is none; throws when the store fails or holds
    /// something that is not a 32-byte key.
    private static func deviceKeyPeek() throws -> Data? {
        let stored: Data?
        do {
            stored = try deviceKeyStore.loadKey()
        } catch {
            throw CipherError.deviceKeyUnavailable
        }
        guard let key = stored else { return nil }
        guard key.count == dkLen else { throw CipherError.deviceKeyUnavailable }
        return key
    }

    /// The device key: 32 random bytes. With `create`, generates and stores one when none exists (encryption path).
    private static func deviceKey(create: Bool) throws -> Data {
        if let existing = try deviceKeyPeek() { return existing }
        guard create else { throw CipherError.deviceKeyUnavailable }
        let newKey = SecureRandom.bytes(dkLen)
        let added: Bool
        do {
            added = try deviceKeyStore.addKey(newKey)
        } catch {
            throw CipherError.deviceKeyUnavailable
        }
        if added { return newKey }
        if let raced = try deviceKeyPeek() { return raced }   // lost a race: use the winner's key
        throw CipherError.deviceKeyUnavailable
    }

    /// True when this device already holds a (well-formed) device key.
    public static func deviceKeyExists() -> Bool {
        return ((try? deviceKeyPeek()) ?? nil) != nil
    }

    /// `.device` AES key = HMAC-SHA256(key: deviceKey, message: scryptKey). Both inputs are 256-bit high-entropy.
    private static func hmacKey(scryptKey: Data, deviceKey: Data) -> Data {
        let mac = HMAC<SHA256>.authenticationCode(for: scryptKey, using: SymmetricKey(data: deviceKey))
        return Data(mac)
    }

    /// Device key fingerprint: hex of the first 8 bytes of SHA-256(deviceKey). Does not reveal the key.
    static func deviceKeyFingerprint(_ dk: Data) -> String {
        let h = SHA256.hash(data: dk)
        return Data(h.prefix(8)).hexString
    }

    /// Binding state of `blob` relative to this device (no password needed).
    public static func deviceBindingStatus(_ blob: String?) -> DeviceBindingStatus {
        guard let blob = blob, let env = envelope(blob), env.bind == "device" else { return .notDeviceBound }
        guard let dk = (try? deviceKeyPeek()) ?? nil else { return .needRestore }
        if let fp = env.dkfp, fp != deviceKeyFingerprint(dk) { return .needRestore }
        return .ok
    }

    // MARK: - Self-test

    /// Round trips for both bindings, wrong password and tampering rejected, the single-field and group writers, and
    /// the binding status. Uses the configured device key store (creates the device key if missing).
    /// Returns nil when everything passed, otherwise a description of the first failure.
    public static func runSelfTest() -> String? {
        let pt = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
        let pwd = "vault self-test password"

        for binding in [Binding.portable, Binding.device] {
            let tag = binding.rawValue
            guard let blob = try? encryptV2(plaintext: pt, password: pwd, binding: binding) else { return "\(tag): encrypt failed" }
            guard looksLikeV2(blob) else { return "\(tag): prefix missing" }
            guard let back = try? decryptV2(blob: blob, password: pwd), back == pt else { return "\(tag): roundtrip mismatch" }
            guard let blob2 = try? encryptV2(plaintext: pt, password: pwd, binding: binding), blob2 != blob else { return "\(tag): not randomized" }
            if (try? decryptV2(blob: blob, password: "wrong")) != nil { return "\(tag): wrong password accepted" }
            var t = Array(blob); if t.count > 10 { t[t.count - 3] = t[t.count - 3] == "A" ? "B" : "A" }
            if (try? decryptV2(blob: String(t), password: pwd)) != nil { return "\(tag): tamper not detected" }
        }

        // Single field writer
        guard let single = reencryptToV2(plaintext: pt, password: pwd),
              (try? decryptV2(blob: single, password: pwd)) == pt else { return "reencrypt self-check failed" }

        // One wallet's fields together: one salt, distinct nonces, all open without the cache, wrong password rejected
        let parts = [pt, "00ff00ff00ff", "my passphrase"]
        guard let group = reencryptToV2(plaintexts: parts, password: pwd), group.count == parts.count else { return "group encrypt failed" }
        for (i, b) in group.enumerated() where (try? decryptV2(blob: b, password: pwd, useCache: false)) != parts[i] {
            return "group roundtrip \(i) failed"
        }
        let salts = Set(group.compactMap { envelope($0)?.salt })
        let nonces = Set(group.compactMap { envelope($0)?.nonce })
        if salts.count != 1 || nonces.count != parts.count { return "group should share salt, not nonce" }
        if (try? decryptV2(blob: group[1], password: "wrong")) != nil { return "group: wrong password accepted" }

        // Binding status: .device is .ok here; .portable and non-v2 are .notDeviceBound
        guard let dblob = try? encryptV2(plaintext: pt, password: pwd, binding: .device) else { return "binding status setup failed" }
        if deviceBindingStatus(dblob) != .ok { return "device binding status should be ok" }
        guard let pblob = try? encryptV2(plaintext: pt, password: pwd, binding: .portable) else { return "portable setup failed" }
        if deviceBindingStatus(pblob) != .notDeviceBound { return "portable should be notDeviceBound" }
        if deviceBindingStatus("deadbeef") != .notDeviceBound { return "non-v2 should be notDeviceBound" }
        return nil
    }

    // MARK: - Helpers

    /// Parses the JSON envelope of a v2 blob (no validation of its values).
    static func envelope(_ blob: String) -> Envelope? {
        guard blob.hasPrefix(v2Prefix),
              let json = Data(base64Encoded: String(blob.dropFirst(v2Prefix.count))) else { return nil }
        return try? JSONDecoder().decode(Envelope.self, from: json)
    }

    /// Hex decoder for envelope fields: an exact port of the app's parser (even length, each pair parsed with
    /// `UInt8(_:radix: 16)`, no `0x` prefix), kept separate from `Data(hexString:)` so envelope parsing stays
    /// identical to the app.
    static func envelopeHex(_ hex: String) -> Data? {
        let chars = Array(hex)
        guard chars.count % 2 == 0 else { return nil }
        var out = Data(capacity: chars.count / 2)
        var i = 0
        while i < chars.count {
            guard let b = UInt8(String(chars[i...i + 1]), radix: 16) else { return nil }
            out.append(b)
            i += 2
        }
        return out
    }
}
