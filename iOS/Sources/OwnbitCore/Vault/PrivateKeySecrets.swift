//  PrivateKeySecrets.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  The encrypted secrets of a private-key wallet as plain values, and the app's rules for them:
//    · the private key and (when there is one) its WIF are encrypted together with the wallet password:
//      one v2 group (`.device` binding, shared salt, fresh nonce each, round-trip checked);
//    · hash gates: `privateKey.sha256() == privateKeyHash`, `wif.sha256() == wifHash`;
//    · the password check of a private-key wallet is "the private key decrypts and passes its gate";
//    · private-key wallets have no password change (the app does not offer one).

import Foundation

public struct PrivateKeySecrets: Equatable, Hashable, Codable, Sendable {

    /// v2 envelope of the private key as imported (hex, or WIF when the user imported a WIF).
    public var encryptedPrivateKey: String?
    /// v2 envelope of the WIF; nil when none was stored.
    public var encryptedWIF: String?
    /// `privateKey.sha256()`
    public var privateKeyHash: String?
    /// `wif.sha256()` (the app stores it even for an empty WIF).
    public var wifHash: String?

    public init(encryptedPrivateKey: String?, encryptedWIF: String?, privateKeyHash: String?, wifHash: String?) {
        self.encryptedPrivateKey = encryptedPrivateKey
        self.encryptedWIF = encryptedWIF
        self.privateKeyHash = privateKeyHash
        self.wifHash = wifHash
    }

    /// No private key stored: a watch-only private-key wallet (the app's `isObserverMode`).
    public var isWatchOnly: Bool {
        return encryptedPrivateKey == nil
    }

    // MARK: - Creating

    /// Encrypts an imported private key (and its WIF, "" for none) with `password`.
    /// - Throws: `WalletSecretsError.encryptionFailed`, `.verificationFailed`.
    public static func encrypt(privateKey: String, wif: String, password: String) throws -> PrivateKeySecrets {
        let plain = wif.isEmpty ? [privateKey] : [privateKey, wif]
        guard let blobs = WalletSecrets.encryptSecrets(plain, password: password), blobs.count == plain.count else {
            throw WalletSecretsError.encryptionFailed
        }
        let secrets = PrivateKeySecrets(encryptedPrivateKey: blobs[0],
                                        encryptedWIF: wif.isEmpty ? nil : blobs[1],
                                        privateKeyHash: privateKey.sha256(),
                                        wifHash: wif.sha256())
        guard secrets.decryptPrivateKey(password: password) == privateKey,
              wif.isEmpty || secrets.decryptWIF(password: password) == wif else {
            throw WalletSecretsError.verificationFailed
        }
        return secrets
    }

    /// Adds a WIF that was derived later (older imports stored none): verifies `password` through the private key's
    /// gate, then encrypts the WIF on its own (fresh salt), as the app does. Nil on a wrong password or failure.
    public func addingWIF(_ wif: String, password: String) -> PrivateKeySecrets? {
        guard decryptPrivateKey(password: password) != nil,
              let blob = WalletSecrets.encryptSecrets([wif], password: password)?.first else { return nil }
        var updated = self
        updated.encryptedWIF = blob
        updated.wifHash = wif.sha256()
        return updated
    }

    // MARK: - Reading

    /// The private key, or nil when the password is wrong (hash gate: `sha256() == privateKeyHash`).
    public func decryptPrivateKey(password: String) -> String? {
        guard let s = WalletSecrets.rawDecryptField(encryptedPrivateKey, password: password),
              s.sha256() == privateKeyHash else { return nil }
        return s
    }

    /// The WIF, or nil when none is stored or the password is wrong (hash gate: `sha256() == wifHash`).
    public func decryptWIF(password: String) -> String? {
        guard encryptedWIF != nil,
              let s = WalletSecrets.rawDecryptField(encryptedWIF, password: password),
              s.sha256() == wifHash else { return nil }
        return s
    }

    /// The app's password check for private-key wallets.
    public func checkPassword(_ password: String) -> Bool {
        return decryptPrivateKey(password: password) != nil
    }

    /// Runs the scrypt for `password` ahead of time (background queue) so the checks that follow hit the cache.
    public func prewarm(password: String) {
        WalletSecretCipher.prewarm(blob: encryptedPrivateKey, password: password)
    }

    /// The key / WIF are `.device`-bound to a device key this device does not hold. No password needed.
    public var requiresDeviceRestore: Bool {
        return [encryptedPrivateKey, encryptedWIF].contains { WalletSecretCipher.deviceBindingStatus($0) == .needRestore }
    }

    // MARK: - Input

    /// The app's clean-up of a typed / pasted private key before import: drops one leading `0x` / `0X`, trims
    /// whitespace and newlines at both ends, removes any remaining "\n".
    public static func normalize(privateKey: String?) -> String {
        guard var key = privateKey else { return "" }
        if key.hasPrefix("0x") || key.hasPrefix("0X") {
            key.removeFirst(2)
        }
        key = key.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: "")
        return key
    }
}
