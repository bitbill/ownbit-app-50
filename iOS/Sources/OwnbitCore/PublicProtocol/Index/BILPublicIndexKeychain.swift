//  BILPublicIndexKeychain.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Public protocol (cold signer): where the sealed public indexes live (spec §4.3, R2 §4, D-08). Android keeps them in a
//  Room table with a Keystore AES key; iOS uses two kinds of Keychain items, both kSecClassGenericPassword,
//  kSecAttrAccessibleWhenUnlockedThisDeviceOnly and not synchronizable:
//    - the AES-256 key: service `ownbit_public_index_v1`, account `key` (32 random bytes);
//    - one entry per wallet: service `io.ownbit.pubsigner.index.v1`, account = wallet id, value = the JSON envelope
//      (BILPublicIndexEnvelope).
//  The Security APIs are thread-safe: every method may run off the main thread (the repository reads and writes through
//  BILPublicBackground). Errors carry the OSStatus only; nothing here is logged.
//

import Foundation
import Security
import CryptoKit

/// A Keychain call failed with `status` (anything but "not found", which the API returns as nil / no-op).
public struct BILPublicKeychainError: Error, Equatable, CustomStringConvertible {
    public let status: OSStatus

    /// The stored AES key is not 32 bytes: unusable (the seal path replaces it once; every older entry then reads as
    /// NeedsRepair, as Android's `replaceUnusableKey`). Reads treat it as "key lost" (NeedsRepair), never as transient.
    public static let unusableKey = BILPublicKeychainError(status: errSecDecode)

    public var isUnusableKey: Bool {
        return status == errSecDecode
    }

    public var description: String {
        return "BILPublicKeychainError(\(status))"
    }
}

/// Storage of the public index entries and of their AES key (live: the Keychain; harness: an in-memory fake).
public protocol BILPublicIndexKeyStore: AnyObject {
    /// The entry of `walletId`; nil = errSecItemNotFound; any other failure throws (transient for the repository).
    func readEntry(walletId: String) throws -> Data?
    /// Update-or-add, WhenUnlockedThisDeviceOnly, not synchronizable.
    func writeEntry(walletId: String, data: Data) throws
    /// Removes the entry; not found is not an error.
    func deleteEntry(walletId: String) throws
    /// The wallet ids (accounts) of every entry; never includes the AES key item.
    func entryWalletIds() throws -> [String]
    /// The AES key; nil when it does not exist and `create` is false. A stored key of the wrong length throws
    /// `BILPublicKeychainError.unusableKey`. Creation races (errSecDuplicateItem) re-read the winner's key.
    func key(create: Bool) throws -> SymmetricKey?
    /// Deletes the key and creates a new one (seal time, after `unusableKey`).
    func replaceKey() throws -> SymmetricKey
}

public final class BILPublicIndexKeychain: BILPublicIndexKeyStore {

    public static let shared = BILPublicIndexKeychain()

    public static let keyService = "ownbit_public_index_v1", keyAccount = "key", entryService = "io.ownbit.pubsigner.index.v1"

    private static let keyLength = 32

    /// Serializes key creation / replacement inside this process (the Keychain itself is thread-safe).
    private let keyLock = NSLock()

    public init() {}

    // MARK: - Entries

    public func readEntry(walletId: String) throws -> Data? {
        var query = entryQuery(walletId)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw BILPublicKeychainError(status: status) }
        guard let data = out as? Data else { throw BILPublicKeychainError(status: errSecDecode) }
        return data
    }

    public func writeEntry(walletId: String, data: Data) throws {
        try upsert(entryQuery(walletId), data: data)
    }

    public func deleteEntry(walletId: String) throws {
        let status = SecItemDelete(entryQuery(walletId) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw BILPublicKeychainError(status: status) }
    }

    public func entryWalletIds() throws -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: BILPublicIndexKeychain.entryService,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var out: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess else { throw BILPublicKeychainError(status: status) }
        guard let rows = out as? [[String: Any]] else { throw BILPublicKeychainError(status: errSecDecode) }
        return rows.compactMap { $0[kSecAttrAccount as String] as? String }
    }

    // MARK: - AES key

    public func key(create: Bool) throws -> SymmetricKey? {
        if let existing = try readKey() { return existing }
        guard create else { return nil }
        keyLock.lock()
        defer { keyLock.unlock() }
        if let existing = try readKey() { return existing }
        let fresh = try BILPublicIndexKeychain.randomKey()
        let status = SecItemAdd(addAttributes(keyQuery(), data: fresh) as CFDictionary, nil)
        if status == errSecSuccess { return SymmetricKey(data: fresh) }
        if status == errSecDuplicateItem, let winner = try readKey() { return winner }   // another process won the race
        throw BILPublicKeychainError(status: status)
    }

    public func replaceKey() throws -> SymmetricKey {
        keyLock.lock()
        defer { keyLock.unlock() }
        let deleted = SecItemDelete(keyQuery() as CFDictionary)
        guard deleted == errSecSuccess || deleted == errSecItemNotFound else { throw BILPublicKeychainError(status: deleted) }
        let fresh = try BILPublicIndexKeychain.randomKey()
        let status = SecItemAdd(addAttributes(keyQuery(), data: fresh) as CFDictionary, nil)
        guard status == errSecSuccess else { throw BILPublicKeychainError(status: status) }
        return SymmetricKey(data: fresh)
    }

    // MARK: - Private

    private func readKey() throws -> SymmetricKey? {
        var query = keyQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw BILPublicKeychainError(status: status) }
        guard let data = out as? Data, data.count == BILPublicIndexKeychain.keyLength else { throw BILPublicKeychainError.unusableKey }
        return SymmetricKey(data: data)
    }

    private func entryQuery(_ walletId: String) -> [String: Any] {
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: BILPublicIndexKeychain.entryService,
            kSecAttrAccount as String: walletId,
        ]
    }

    private func keyQuery() -> [String: Any] {
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: BILPublicIndexKeychain.keyService,
            kSecAttrAccount as String: BILPublicIndexKeychain.keyAccount,
        ]
    }

    private func addAttributes(_ query: [String: Any], data: Data) -> [String: Any] {
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        add[kSecAttrSynchronizable as String] = false
        return add
    }

    /// Update-or-add (KeychainMnemonicStore.saveMnemonic pattern, without iCloud sync); an add race retries the update.
    private func upsert(_ query: [String: Any], data: Data) throws {
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let updated = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updated == errSecSuccess { return }
        guard updated == errSecItemNotFound else { throw BILPublicKeychainError(status: updated) }
        let added = SecItemAdd(addAttributes(query, data: data) as CFDictionary, nil)
        if added == errSecSuccess { return }
        if added == errSecDuplicateItem {
            let retried = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            if retried == errSecSuccess { return }
            throw BILPublicKeychainError(status: retried)
        }
        throw BILPublicKeychainError(status: added)
    }

    private static func randomKey() throws -> Data {
        var bytes = [UInt8](repeating: 0, count: keyLength)
        let status = SecRandomCopyBytes(kSecRandomDefault, keyLength, &bytes)
        guard status == errSecSuccess else { throw BILPublicKeychainError(status: status) }
        defer { for i in bytes.indices { bytes[i] = 0 } }
        return Data(bytes)
    }
}
