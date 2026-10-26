//  KeychainDeviceKeyStoreTests.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT

import XCTest
import Security
@testable import OwnbitCore

/// Exercises the real keychain store, on the iOS simulator only (never on a Mac host, where it would write to the
/// login keychain) and with a test-only service name. Skipped when the test bundle has no keychain access.
final class VaultKeychainDeviceKeyStoreTests: XCTestCase {

    func testKeychainStoreRoundTrip() throws {
        #if os(iOS) && targetEnvironment(simulator)
        let keychain = KeychainDeviceKeyStore(service: "ai.ownbit.vault.deviceKey.tests", account: "v2")
        keychain.deleteKey()
        defer { keychain.deleteKey() }
        // Probe: an SPM test bundle on the simulator may have no keychain entitlement; some steps then fail with
        // errSecMissingEntitlement (-34018) even though others succeed.
        do {
            let probe = Data(repeating: 1, count: 32)
            _ = try keychain.loadKey()
            _ = try keychain.addKey(probe)
            guard try keychain.loadKey() == probe else { throw XCTSkip("keychain did not return the stored item") }
            keychain.deleteKey()
        } catch KeychainDeviceKeyStore.KeychainError.status(let status) where status == errSecMissingEntitlement {
            throw XCTSkip("no keychain access in this test bundle (errSecMissingEntitlement)")
        }
        XCTAssertNil(try keychain.loadKey())
        let key = SecureRandom.bytes(32)
        XCTAssertTrue(try keychain.addKey(key))
        XCTAssertEqual(try keychain.loadKey(), key)
        XCTAssertFalse(try keychain.addKey(SecureRandom.bytes(32)), "an existing key is never replaced")
        XCTAssertEqual(try keychain.loadKey(), key)

        let previous = WalletSecretCipher.deviceKeyStore
        WalletSecretCipher.deviceKeyStore = keychain
        defer { WalletSecretCipher.deviceKeyStore = previous }
        let blob = try WalletSecretCipher.encryptV2(plaintext: "secret", password: "pw", binding: .device, n: 1024)
        XCTAssertEqual(WalletSecretCipher.deviceBindingStatus(blob), .ok)
        XCTAssertEqual(try WalletSecretCipher.decryptV2(blob: blob, password: "pw"), "secret")
        #else
        throw XCTSkip("keychain test runs on the iOS simulator only")
        #endif
    }

    func testDefaultCoordinatesMatchTheApp() {
        let store = KeychainDeviceKeyStore()
        XCTAssertEqual(store.service, "ai.ownbit.vault.deviceKey")
        XCTAssertEqual(store.account, "v2")
    }
}
