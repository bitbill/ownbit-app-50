//  WalletSecrets.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  The encrypted secrets of one mnemonic wallet (personal, multisig member or cold wallet) as plain values, and the
//  app's rules for them. Persistence is the host's job: this type never saves anything.
//
//  Rules (same as the app):
//    · mnemonic, BIP39 seed (hex) and the optional BIP39 passphrase are encrypted together with the wallet password:
//      one v2 group (`.device` binding, one shared salt, a fresh nonce each, round-trip checked);
//    · "hash gates": a decrypted mnemonic / seed only counts when its `sha256()` equals the stored mnemonicHash /
//      seedHash — that is what makes a wrong password fail even before GCM would;
//    · the passphrase has NO hash (it is low-entropy; a hash would invite offline guessing); it is released only
//      after the mnemonic hash gate passed with the same password;
//    · signing always uses the seed; the passphrase is kept only to show it back to the user;
//    · a password change re-encrypts all of the wallet's secrets together and only counts after the new envelopes
//      decrypt to the same plaintexts through the normal read path; anything else leaves the wallet as it was.

import Foundation

public enum WalletSecretsError: Error, Equatable {
    /// The wallet holds no secrets (watch-only), nothing to re-encrypt. The app shows "try later".
    case noSecrets
    /// The password does not open the secrets. The app shows "wrong password".
    case wrongPassword
    /// v2 encryption failed (e.g. the device key could not be stored). The app shows "try later".
    case encryptionFailed
    /// The new envelopes did not read back through the normal read path. Nothing was changed.
    case verificationFailed
    /// Password reset from the mnemonic: the recomputed seed is not this wallet's seed (e.g. a different
    /// BIP39 passphrase). Nothing was changed.
    case seedMismatch
}

public struct WalletSecrets: Equatable, Hashable, Codable, Sendable {

    /// v2 envelope of the mnemonic.
    public var encryptedMnemonic: String?
    /// v2 envelope of the BIP39 seed, hex (`BIP39(mnemonic, passphrase)`). Nil means a watch-only wallet.
    public var encryptedSeed: String?
    /// v2 envelope of the BIP39 passphrase; nil or "" when the wallet has none.
    public var encryptedPassphrase: String?
    /// `mnemonic.sha256()`
    public var mnemonicHash: String?
    /// `seedHex.sha256()`
    public var seedHash: String?

    public init(encryptedMnemonic: String?,
                encryptedSeed: String?,
                encryptedPassphrase: String? = nil,
                mnemonicHash: String?,
                seedHash: String?) {
        self.encryptedMnemonic = encryptedMnemonic
        self.encryptedSeed = encryptedSeed
        self.encryptedPassphrase = encryptedPassphrase
        self.mnemonicHash = mnemonicHash
        self.seedHash = seedHash
    }

    /// The wallet was imported with a BIP39 passphrase.
    public var hasPassphrase: Bool {
        return !(encryptedPassphrase ?? "").isEmpty
    }

    /// No seed stored: a watch-only wallet (the app's `isObserverMode`).
    public var isWatchOnly: Bool {
        return encryptedSeed == nil
    }

    // MARK: - Creating

    /// Encrypts a new (created or imported) wallet's secrets with `password`.
    /// - Parameters:
    ///   - seedHex: `BIP39(mnemonic, passphrase)` as hex, computed by the caller (the BIP39 bridge).
    ///   - passphrase: "" for none (the seed is then exactly the classic one). See `PassphrasePolicy` for which
    ///     wallets may carry one.
    /// - Throws: `.encryptionFailed`, `.verificationFailed`.
    public static func encrypt(mnemonic: String, seedHex: String, passphrase: String = "",
                               password: String) throws -> WalletSecrets {
        let plain = passphrase.isEmpty ? [mnemonic, seedHex] : [mnemonic, seedHex, passphrase]
        guard let blobs = encryptSecrets(plain, password: password), blobs.count == plain.count else {
            throw WalletSecretsError.encryptionFailed
        }
        let secrets = WalletSecrets(encryptedMnemonic: blobs[0],
                                    encryptedSeed: blobs[1],
                                    encryptedPassphrase: passphrase.isEmpty ? nil : blobs[2],
                                    mnemonicHash: mnemonic.sha256(),
                                    seedHash: seedHex.sha256())
        guard secrets.reads(mnemonic: mnemonic, seedHex: seedHex, passphrase: passphrase.isEmpty ? nil : passphrase,
                            password: password) else {
            throw WalletSecretsError.verificationFailed
        }
        return secrets
    }

    /// Several secrets of one wallet under one password: one v2 group (shared salt, `.device` binding), each envelope
    /// round-trip checked. Nil on any failure or any empty input.
    ///
    /// The app falls back to its pre-v2 format when v2 fails; this package has no other format, so it fails instead.
    public static func encryptSecrets(_ plaintexts: [String], password: String) -> [String]? {
        return WalletSecretCipher.reencryptToV2(plaintexts: plaintexts, password: password, binding: .device)
    }

    /// `encryptSecrets` on a background queue (scrypt stays off the main thread); `completion` runs on the main queue.
    public static func encryptSecretsInBackground(_ plaintexts: [String], password: String,
                                                  completion: @escaping ([String]?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let blobs = encryptSecrets(plaintexts, password: password)
            DispatchQueue.main.async { completion(blobs) }
        }
    }

    // MARK: - Reading

    /// Decrypts one v2 envelope; nil for a wrong password, a tampered or non-v2 blob, or a missing device key.
    /// Does NOT apply a hash gate — use the `decrypt…` methods for wallet fields.
    public static func rawDecryptField(_ blob: String?, password: String) -> String? {
        guard let blob = blob, !blob.isEmpty, WalletSecretCipher.looksLikeV2(blob) else { return nil }
        return try? WalletSecretCipher.decryptV2(blob: blob, password: password)
    }

    /// The mnemonic, or nil when the password is wrong (hash gate: `sha256() == mnemonicHash`).
    public func decryptMnemonic(password: String) -> String? {
        guard let mnemonic = WalletSecrets.rawDecryptField(encryptedMnemonic, password: password),
              mnemonic.sha256() == mnemonicHash else { return nil }
        return mnemonic
    }

    /// The seed hex, or nil when the password is wrong (hash gate: `sha256() == seedHash`).
    public func decryptSeed(password: String) -> String? {
        guard let seed = WalletSecrets.rawDecryptField(encryptedSeed, password: password),
              seed.sha256() == seedHash else { return nil }
        return seed
    }

    /// The BIP39 passphrase: "" when the wallet has none, nil when the password is wrong. The passphrase has no hash
    /// of its own, so the password is first checked through the mnemonic's hash gate.
    public func decryptPassphrase(password: String) -> String? {
        guard hasPassphrase else { return "" }
        guard decryptMnemonic(password: password) != nil else { return nil }
        return WalletSecrets.rawDecryptField(encryptedPassphrase, password: password)
    }

    /// The app's password check for mnemonic wallets: the mnemonic decrypts and passes its hash gate.
    public func checkPassword(_ password: String) -> Bool {
        return decryptMnemonic(password: password) != nil
    }

    /// Runs the scrypt for `password` ahead of time (call on a background queue) so that `checkPassword` and the
    /// seed / passphrase decryptions that follow hit the cache. All fields share one salt, so one run covers them.
    public func prewarm(password: String) {
        WalletSecretCipher.prewarm(blob: encryptedMnemonic, password: password)
    }

    /// The mnemonic / seed are `.device`-bound to a device key this device does not hold (e.g. a new phone restored
    /// from a full backup). The app then tells the user to restore from the cloud backup or re-import the mnemonic
    /// instead of reporting a wrong password. No password needed.
    public var requiresDeviceRestore: Bool {
        return [encryptedSeed, encryptedMnemonic].contains { WalletSecretCipher.deviceBindingStatus($0) == .needRestore }
    }

    // MARK: - Changing the password

    /// Re-encrypts all of this wallet's secrets (mnemonic, seed and, if present, passphrase) from `oldPassword` to
    /// `newPassword`, together in one v2 group, and returns the new value only after it reads back the same plaintexts
    /// through the normal read path. `self` is never modified: on any error, or if persisting the result fails, the
    /// caller simply keeps the old value (the app's rollback). Hashes are unchanged (the plaintexts are unchanged).
    /// - Throws: `.noSecrets`, `.wrongPassword`, `.encryptionFailed`, `.verificationFailed`.
    public func changingPassword(from oldPassword: String, to newPassword: String) throws -> WalletSecrets {
        guard !isWatchOnly, let oldMnemonicBlob = encryptedMnemonic, !oldMnemonicBlob.isEmpty else {
            throw WalletSecretsError.noSecrets
        }
        // Opening with the old password is the password check.
        guard let mnemonic = decryptMnemonic(password: oldPassword),
              let seed = decryptSeed(password: oldPassword) else {
            throw WalletSecretsError.wrongPassword
        }
        var passphrase: String? = nil
        if hasPassphrase {
            guard let p = WalletSecrets.rawDecryptField(encryptedPassphrase, password: oldPassword) else {
                throw WalletSecretsError.wrongPassword
            }
            passphrase = p
        }
        let plain = [mnemonic, seed] + (passphrase.map { [$0] } ?? [])
        guard let blobs = WalletSecrets.encryptSecrets(plain, password: newPassword), blobs.count == plain.count else {
            throw WalletSecretsError.encryptionFailed
        }
        var updated = self
        updated.encryptedMnemonic = blobs[0]
        updated.encryptedSeed = blobs[1]
        if passphrase != nil { updated.encryptedPassphrase = blobs[2] }

        guard updated.reads(mnemonic: mnemonic, seedHex: seed, passphrase: passphrase, password: newPassword) else {
            throw WalletSecretsError.verificationFailed
        }
        return updated
    }

    /// Password reset by re-entering the mnemonic (and the same passphrase, if any): the seed recomputed by the caller
    /// must be this wallet's seed — the same mnemonic with a different passphrase is a different wallet — before
    /// anything is re-encrypted. The caller has already matched the wallet by `mnemonicHash`.
    /// - Throws: `.seedMismatch`, plus the errors of `encrypt(mnemonic:seedHex:passphrase:password:)`.
    public func resettingPassword(mnemonic: String, seedHex: String, passphrase: String = "",
                                  newPassword: String) throws -> WalletSecrets {
        if let oldSeedHash = seedHash, !oldSeedHash.isEmpty, oldSeedHash != seedHex.sha256() {
            throw WalletSecretsError.seedMismatch
        }
        return try WalletSecrets.encrypt(mnemonic: mnemonic, seedHex: seedHex, passphrase: passphrase,
                                         password: newPassword)
    }

    // MARK: - Private

    /// Reads every field back through the normal read path and compares with the expected plaintexts.
    private func reads(mnemonic: String, seedHex: String, passphrase: String?, password: String) -> Bool {
        guard decryptMnemonic(password: password) == mnemonic,
              decryptSeed(password: password) == seedHex else { return false }
        if let passphrase = passphrase {
            return WalletSecrets.rawDecryptField(encryptedPassphrase, password: password) == passphrase
        }
        return true
    }
}
