//  DeviceKeyStore.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Where the 32-byte device key for `.device`-bound vault envelopes lives.
//
//  The default is the app's keychain item: generic password, service "ai.ownbit.vault.deviceKey", account "v2",
//  kSecAttrAccessibleWhenUnlockedThisDeviceOnly — never synced to iCloud Keychain, never in device backups,
//  never leaves this device. A different store can be injected (`WalletSecretCipher.deviceKeyStore`), e.g. an
//  in-memory one for unit tests that run without keychain entitlements.

import Foundation
import Security

/// Storage for the vault's device key. Implementations must be thread-safe.
public protocol DeviceKeyStore: AnyObject {

    /// The stored key, or nil when there is none yet.
    /// Throw for any other failure (locked device, missing entitlement, ...).
    func loadKey() throws -> Data?

    /// Stores `key` if no key exists yet. Returns true when it was stored, false when a key already existed
    /// (another thread won the race; the caller re-reads it). Throw for any other failure.
    func addKey(_ key: Data) throws -> Bool
}

/// The app's device-key keychain item.
public final class KeychainDeviceKeyStore: DeviceKeyStore {

    /// The app's keychain coordinates. Changing them on an existing install makes every `.device` envelope
    /// on that install undecryptable.
    public static let defaultService = "ai.ownbit.vault.deviceKey"
    public static let defaultAccount = "v2"

    public let service: String
    public let account: String

    public enum KeychainError: Error, Equatable {
        case status(OSStatus)
    }

    public init(service: String = KeychainDeviceKeyStore.defaultService,
                account: String = KeychainDeviceKeyStore.defaultAccount) {
        self.service = service
        self.account = account
    }

    public func loadKey() throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var out: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = out as? Data else { throw KeychainError.status(status) }
        return data
    }

    public func addKey(_ key: Data) throws -> Bool {
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: key,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let status = SecItemAdd(add as CFDictionary, nil)
        if status == errSecSuccess { return true }
        if status == errSecDuplicateItem { return false }
        throw KeychainError.status(status)
    }

    /// Removes the item. Destroys every `.device` envelope that depends on it — tests only.
    internal func deleteKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
