//  VaultTestSupport.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT

import Foundation
import XCTest
@testable import OwnbitCore

/// In-memory device key store, so the vault tests never touch the keychain (no entitlements needed).
final class VaultMemoryKeyStore: DeviceKeyStore {
    private let lock = NSLock()
    private var key: Data?
    var failLoads = false
    var failAdds = false
    /// Simulates losing the creation race: `addKey` stores this key instead and reports "already existed".
    var raceWinner: Data?
    private(set) var addCount = 0

    init(key: Data? = nil) { self.key = key }

    var storedKey: Data? {
        lock.lock(); defer { lock.unlock() }
        return key
    }

    func loadKey() throws -> Data? {
        lock.lock(); defer { lock.unlock() }
        if failLoads { throw NSError(domain: "VaultMemoryKeyStore", code: -34018) }
        return key
    }

    func addKey(_ newKey: Data) throws -> Bool {
        lock.lock(); defer { lock.unlock() }
        if failAdds { throw NSError(domain: "VaultMemoryKeyStore", code: -25308) }
        addCount += 1
        if key != nil { return false }
        if let winner = raceWinner {
            key = winner
            return false
        }
        key = newKey
        return true
    }
}

/// Base class: a fresh in-memory device key store and an empty scrypt cache for every test.
class VaultTestCase: XCTestCase {

    var store: VaultMemoryKeyStore!

    override func setUp() {
        super.setUp()
        store = VaultMemoryKeyStore()
        WalletSecretCipher.deviceKeyStore = store
        WalletSecretCipher.now = { Date() }
        WalletSecretCipher.clearKeyCache()
    }

    override func tearDown() {
        WalletSecretCipher.clearKeyCache()
        WalletSecretCipher.now = { Date() }
        WalletSecretCipher.deviceKeyStore = VaultMemoryKeyStore()   // never leave a test store holding a key around
        store = nil
        super.tearDown()
    }

    /// Rebuilds an envelope string after editing its JSON fields.
    func rebuild(_ blob: String, _ edit: (inout WalletSecretCipher.Envelope) -> Void) -> String {
        guard var env = WalletSecretCipher.envelope(blob) else {
            XCTFail("not an envelope")
            return blob
        }
        edit(&env)
        let json = try! JSONEncoder().encode(env)
        return WalletSecretCipher.v2Prefix + json.base64EncodedString()
    }
}

enum VaultFixtures {
    /// BIP39 test vector mnemonic ("abandon" x 11 + "about") and its seed with the empty passphrase.
    static let mnemonic = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
    static let seedHex = "5eb00bbddcf069084889a8ab9155568165f5c453ccb85e70811aaed6f6da5fc19a5ac40b389cd370d086206dec8aa6c43daea6690f20ad3d8d48b2d2ce9e38e4"
    /// Same mnemonic with the BIP39 test-vector passphrase "TREZOR".
    static let seedHexTrezor = "c55257c360c07c72029aebc1b53c05ed0362ada38ead3e3e9efa3708e53495531f09a6987599d18264c1e1c92f2cf141630c7a3c4ab7c81b2f001698e7463b04"

    static let password = "ownbit vault kat"
    static let salt = Data((0x00..<0x10).map { UInt8($0) })      // 000102…0f
    static let nonce = Data((0xa0..<0xac).map { UInt8($0) })     // a0a1…ab
    static let deviceKey = Data((0x20..<0x40).map { UInt8($0) }) // 2021…3f
}
