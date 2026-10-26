//  WalletSecretsTests.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT

import XCTest
@testable import OwnbitCore

final class VaultWalletSecretsTests: VaultTestCase {

    private let m = VaultFixtures.mnemonic
    private let seed = VaultFixtures.seedHex
    private let pwd = "wallet password 1"

    private func salt(_ blob: String?) -> String? {
        return blob.flatMap { WalletSecretCipher.envelope($0)?.salt }
    }

    // MARK: - Creating and reading

    func testEncryptWithoutPassphrase() throws {
        let s = try WalletSecrets.encrypt(mnemonic: m, seedHex: seed, password: pwd)
        XCTAssertEqual(s.mnemonicHash, m.sha256())
        XCTAssertEqual(s.seedHash, seed.sha256())
        XCTAssertNil(s.encryptedPassphrase)
        XCTAssertFalse(s.hasPassphrase)
        XCTAssertFalse(s.isWatchOnly)
        XCTAssertTrue(WalletSecretCipher.looksLikeV2(s.encryptedMnemonic))
        XCTAssertEqual(WalletSecretCipher.envelope(s.encryptedSeed!)?.bind, "device")
        XCTAssertEqual(salt(s.encryptedMnemonic), salt(s.encryptedSeed))

        XCTAssertEqual(s.decryptMnemonic(password: pwd), m)
        XCTAssertEqual(s.decryptSeed(password: pwd), seed)
        XCTAssertEqual(s.decryptPassphrase(password: pwd), "")
        XCTAssertTrue(s.checkPassword(pwd))

        XCTAssertNil(s.decryptMnemonic(password: "wrong"))
        XCTAssertNil(s.decryptSeed(password: "wrong"))
        XCTAssertFalse(s.checkPassword("wrong"))
        XCTAssertEqual(s.decryptPassphrase(password: "wrong"), "", "no passphrase: nothing to protect")
    }

    func testEncryptWithPassphrase() throws {
        let s = try WalletSecrets.encrypt(mnemonic: m, seedHex: VaultFixtures.seedHexTrezor, passphrase: "TREZOR",
                                          password: pwd)
        XCTAssertTrue(s.hasPassphrase)
        XCTAssertEqual(s.seedHash, VaultFixtures.seedHexTrezor.sha256())
        XCTAssertEqual(Set([salt(s.encryptedMnemonic), salt(s.encryptedSeed), salt(s.encryptedPassphrase)]).count, 1)
        let nonces = [s.encryptedMnemonic, s.encryptedSeed, s.encryptedPassphrase].compactMap {
            $0.flatMap { WalletSecretCipher.envelope($0)?.nonce }
        }
        XCTAssertEqual(Set(nonces).count, 3)
        XCTAssertEqual(s.decryptSeed(password: pwd), VaultFixtures.seedHexTrezor)
        XCTAssertEqual(s.decryptPassphrase(password: pwd), "TREZOR")
        XCTAssertNil(s.decryptPassphrase(password: "wrong"))
    }

    func testEncryptFailures() {
        XCTAssertThrowsError(try WalletSecrets.encrypt(mnemonic: m, seedHex: seed, password: "")) {
            XCTAssertEqual($0 as? WalletSecretsError, .encryptionFailed)
        }
        XCTAssertThrowsError(try WalletSecrets.encrypt(mnemonic: "", seedHex: seed, password: pwd))
        store.failAdds = true
        XCTAssertThrowsError(try WalletSecrets.encrypt(mnemonic: m, seedHex: seed, password: pwd)) {
            XCTAssertEqual($0 as? WalletSecretsError, .encryptionFailed)
        }
    }

    func testHashGates() throws {
        let s = try WalletSecrets.encrypt(mnemonic: m, seedHex: seed, password: pwd)
        var wrongHash = s
        wrongHash.mnemonicHash = "x".sha256()
        wrongHash.seedHash = "y".sha256()
        XCTAssertNil(wrongHash.decryptMnemonic(password: pwd), "GCM opens but the hash gate refuses")
        XCTAssertNil(wrongHash.decryptSeed(password: pwd))
        XCTAssertFalse(wrongHash.checkPassword(pwd))

        var noHash = s
        noHash.mnemonicHash = nil
        XCTAssertNil(noHash.decryptMnemonic(password: pwd))

        // Swapped fields: the seed envelope does not pass the mnemonic gate
        var swapped = s
        swapped.encryptedMnemonic = s.encryptedSeed
        XCTAssertNil(swapped.decryptMnemonic(password: pwd))
    }

    func testRawDecryptFieldIsV2Only() throws {
        XCTAssertNil(WalletSecrets.rawDecryptField(nil, password: pwd))
        XCTAssertNil(WalletSecrets.rawDecryptField("", password: pwd))
        XCTAssertNil(WalletSecrets.rawDecryptField("00ff00ff00ff00ff", password: pwd))
        let blob = try XCTUnwrap(WalletSecretCipher.reencryptToV2(plaintext: "x", password: pwd))
        XCTAssertEqual(WalletSecrets.rawDecryptField(blob, password: pwd), "x")
        XCTAssertNil(WalletSecrets.rawDecryptField(blob, password: "wrong"))
    }

    func testPrewarmCoversAllFields() throws {
        let s = try WalletSecrets.encrypt(mnemonic: m, seedHex: VaultFixtures.seedHexTrezor, passphrase: "TREZOR",
                                          password: pwd)
        WalletSecretCipher.clearKeyCache()
        s.prewarm(password: pwd)
        let start = WalletSecretCipher.scryptRunCount
        XCTAssertTrue(s.checkPassword(pwd))
        XCTAssertNotNil(s.decryptSeed(password: pwd))
        XCTAssertEqual(s.decryptPassphrase(password: pwd), "TREZOR")
        XCTAssertEqual(WalletSecretCipher.scryptRunCount, start, "one shared salt: one scrypt run covers every field")
    }

    func testEncryptSecretsInBackground() {
        let done = expectation(description: "completion")
        WalletSecrets.encryptSecretsInBackground(["a", "b"], password: pwd) { blobs in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual(blobs?.count, 2)
            XCTAssertEqual(blobs.flatMap { WalletSecrets.rawDecryptField($0[1], password: self.pwd) }, "b")
            done.fulfill()
        }
        wait(for: [done], timeout: 30)
    }

    func testCodableRoundTrip() throws {
        let s = try WalletSecrets.encrypt(mnemonic: m, seedHex: seed, password: pwd)
        let back = try JSONDecoder().decode(WalletSecrets.self, from: try JSONEncoder().encode(s))
        XCTAssertEqual(back, s)
        XCTAssertEqual(back.decryptMnemonic(password: pwd), m)
    }

    // MARK: - Device restore

    func testRequiresDeviceRestore() throws {
        let s = try WalletSecrets.encrypt(mnemonic: m, seedHex: seed, password: pwd)
        XCTAssertFalse(s.requiresDeviceRestore)
        WalletSecretCipher.deviceKeyStore = VaultMemoryKeyStore()          // new device, no key
        XCTAssertTrue(s.requiresDeviceRestore)
        XCTAssertFalse(s.checkPassword(pwd))
        WalletSecretCipher.deviceKeyStore = VaultMemoryKeyStore(key: Data(repeating: 9, count: 32))
        XCTAssertTrue(s.requiresDeviceRestore)
        WalletSecretCipher.deviceKeyStore = store
        XCTAssertFalse(s.requiresDeviceRestore)
        XCTAssertFalse(WalletSecrets(encryptedMnemonic: nil, encryptedSeed: nil, mnemonicHash: nil, seedHash: nil)
                        .requiresDeviceRestore)
    }

    // MARK: - Changing the password

    func testChangePassword() throws {
        let old = try WalletSecrets.encrypt(mnemonic: m, seedHex: seed, password: pwd)
        let new = try old.changingPassword(from: pwd, to: "new password 2")

        XCTAssertEqual(new.mnemonicHash, old.mnemonicHash)
        XCTAssertEqual(new.seedHash, old.seedHash)
        XCTAssertNotEqual(new.encryptedMnemonic, old.encryptedMnemonic)
        XCTAssertNotEqual(new.encryptedSeed, old.encryptedSeed)
        XCTAssertNil(new.encryptedPassphrase)
        XCTAssertEqual(salt(new.encryptedMnemonic), salt(new.encryptedSeed))
        XCTAssertNotEqual(salt(new.encryptedMnemonic), salt(old.encryptedMnemonic))

        XCTAssertEqual(new.decryptMnemonic(password: "new password 2"), m)
        XCTAssertEqual(new.decryptSeed(password: "new password 2"), seed)
        XCTAssertNil(new.decryptMnemonic(password: pwd))
        // The old value is untouched (the caller's rollback is "keep the old value")
        XCTAssertEqual(old.decryptMnemonic(password: pwd), m)
    }

    func testChangePasswordReencryptsPassphraseToo() throws {
        let old = try WalletSecrets.encrypt(mnemonic: m, seedHex: VaultFixtures.seedHexTrezor, passphrase: "TREZOR",
                                            password: pwd)
        let new = try old.changingPassword(from: pwd, to: "new password 3")
        XCTAssertNotEqual(new.encryptedPassphrase, old.encryptedPassphrase)
        XCTAssertEqual(Set([salt(new.encryptedMnemonic), salt(new.encryptedSeed), salt(new.encryptedPassphrase)]).count, 1)
        XCTAssertEqual(new.decryptPassphrase(password: "new password 3"), "TREZOR")
        XCTAssertNil(WalletSecrets.rawDecryptField(new.encryptedPassphrase, password: pwd))
    }

    func testChangePasswordErrors() throws {
        let s = try WalletSecrets.encrypt(mnemonic: m, seedHex: seed, password: pwd)
        XCTAssertThrowsError(try s.changingPassword(from: "wrong", to: "new")) {
            XCTAssertEqual($0 as? WalletSecretsError, .wrongPassword)
        }
        XCTAssertThrowsError(try s.changingPassword(from: pwd, to: "")) {
            XCTAssertEqual($0 as? WalletSecretsError, .encryptionFailed)
        }
        let watchOnly = WalletSecrets(encryptedMnemonic: nil, encryptedSeed: nil, mnemonicHash: nil, seedHash: nil)
        XCTAssertThrowsError(try watchOnly.changingPassword(from: pwd, to: "new")) {
            XCTAssertEqual($0 as? WalletSecretsError, .noSecrets)
        }
        var noSeed = s
        noSeed.encryptedSeed = nil
        XCTAssertThrowsError(try noSeed.changingPassword(from: pwd, to: "new")) {
            XCTAssertEqual($0 as? WalletSecretsError, .noSecrets)
        }
        // Passphrase envelope that the password cannot open
        var badPassphrase = s
        badPassphrase.encryptedPassphrase = try XCTUnwrap(WalletSecretCipher.reencryptToV2(plaintext: "p", password: "other"))
        XCTAssertThrowsError(try badPassphrase.changingPassword(from: pwd, to: "new")) {
            XCTAssertEqual($0 as? WalletSecretsError, .wrongPassword)
        }
    }

    // MARK: - Password reset from the mnemonic

    func testResetPasswordChecksTheSeed() throws {
        let s = try WalletSecrets.encrypt(mnemonic: m, seedHex: seed, password: pwd)
        // Same mnemonic + a passphrase is another wallet: refused before anything is re-encrypted
        XCTAssertThrowsError(try s.resettingPassword(mnemonic: m, seedHex: VaultFixtures.seedHexTrezor,
                                                     passphrase: "TREZOR", newPassword: "reset 1")) {
            XCTAssertEqual($0 as? WalletSecretsError, .seedMismatch)
        }
        let reset = try s.resettingPassword(mnemonic: m, seedHex: seed, newPassword: "reset 1")
        XCTAssertEqual(reset.decryptSeed(password: "reset 1"), seed)
        XCTAssertNil(reset.decryptSeed(password: pwd))
        XCTAssertEqual(reset.seedHash, s.seedHash)
    }

    // MARK: - Private-key wallets

    func testPrivateKeyWithWIF() throws {
        let pk = "0000000000000000000000000000000000000000000000000000000000000001"
        let wif = "KwDiBf89QgGbjEhKnhXJuH7LrciVrZi3qYjgd9M7rFU73sVHnoWn"
        let s = try PrivateKeySecrets.encrypt(privateKey: pk, wif: wif, password: pwd)
        XCTAssertEqual(s.privateKeyHash, pk.sha256())
        XCTAssertEqual(s.wifHash, wif.sha256())
        XCTAssertEqual(salt(s.encryptedPrivateKey), salt(s.encryptedWIF))
        XCTAssertEqual(s.decryptPrivateKey(password: pwd), pk)
        XCTAssertEqual(s.decryptWIF(password: pwd), wif)
        XCTAssertTrue(s.checkPassword(pwd))
        XCTAssertFalse(s.checkPassword("wrong"))
        XCTAssertNil(s.decryptWIF(password: "wrong"))
        XCTAssertFalse(s.isWatchOnly)
        XCTAssertFalse(s.requiresDeviceRestore)

        var wrongGate = s
        wrongGate.privateKeyHash = "z".sha256()
        XCTAssertNil(wrongGate.decryptPrivateKey(password: pwd))
    }

    func testPrivateKeyWithoutWIFAndAddingItLater() throws {
        let pk = "0000000000000000000000000000000000000000000000000000000000000001"
        let s = try PrivateKeySecrets.encrypt(privateKey: pk, wif: "", password: pwd)
        XCTAssertNil(s.encryptedWIF)
        XCTAssertEqual(s.wifHash, "".sha256())
        XCTAssertNil(s.decryptWIF(password: pwd))

        let wif = "KwDiBf89QgGbjEhKnhXJuH7LrciVrZi3qYjgd9M7rFU73sVHnoWn"
        XCTAssertNil(s.addingWIF(wif, password: "wrong"))
        let withWIF = try XCTUnwrap(s.addingWIF(wif, password: pwd))
        XCTAssertEqual(withWIF.decryptWIF(password: pwd), wif)
        XCTAssertEqual(withWIF.wifHash, wif.sha256())
        XCTAssertEqual(withWIF.encryptedPrivateKey, s.encryptedPrivateKey)
    }

    func testPrivateKeyDeviceRestoreAndPrewarm() throws {
        let s = try PrivateKeySecrets.encrypt(privateKey: "aa", wif: "bb", password: pwd)
        WalletSecretCipher.clearKeyCache()
        s.prewarm(password: pwd)
        let start = WalletSecretCipher.scryptRunCount
        XCTAssertTrue(s.checkPassword(pwd))
        XCTAssertEqual(s.decryptWIF(password: pwd), "bb")
        XCTAssertEqual(WalletSecretCipher.scryptRunCount, start)
        WalletSecretCipher.deviceKeyStore = VaultMemoryKeyStore()
        XCTAssertTrue(s.requiresDeviceRestore)
    }

    func testNormalizePrivateKey() {
        XCTAssertEqual(PrivateKeySecrets.normalize(privateKey: nil), "")
        XCTAssertEqual(PrivateKeySecrets.normalize(privateKey: "0xABCD"), "ABCD")
        XCTAssertEqual(PrivateKeySecrets.normalize(privateKey: "0Xabcd"), "abcd")
        XCTAssertEqual(PrivateKeySecrets.normalize(privateKey: "  ab\ncd \n"), "abcd")
        XCTAssertEqual(PrivateKeySecrets.normalize(privateKey: " 0xab"), "0xab", "prefix is only dropped at the very start")
    }

    // MARK: - Passphrase policy

    func testPassphraseValidation() {
        XCTAssertEqual(PassphrasePolicy.validationError(""), .empty)
        XCTAssertNil(PassphrasePolicy.validationError("TREZOR"))
        XCTAssertNil(PassphrasePolicy.validationError(" spaces are kept "))
        XCTAssertNil(PassphrasePolicy.validationError(String(repeating: "a", count: 100)))
        XCTAssertEqual(PassphrasePolicy.validationError(String(repeating: "a", count: 101)), .tooLong(maxLength: 100))
        XCTAssertNil(PassphrasePolicy.validationError(String(repeating: "🔑", count: 100)), "length counts characters")
        XCTAssertEqual(PassphrasePolicy.validationError("a\nb"), .invalidCharacter)
        XCTAssertEqual(PassphrasePolicy.validationError("a\tb"), .invalidCharacter)
        XCTAssertEqual(PassphrasePolicy.validationError("a\u{2028}b"), .invalidCharacter)
        XCTAssertEqual(PassphrasePolicy.validationError("a\u{2029}b"), .invalidCharacter)
    }

    func testPassphraseEdgeWhitespace() {
        XCTAssertFalse(PassphrasePolicy.hasEdgeWhitespace(""))
        XCTAssertFalse(PassphrasePolicy.hasEdgeWhitespace("a b"))
        XCTAssertTrue(PassphrasePolicy.hasEdgeWhitespace(" ab"))
        XCTAssertTrue(PassphrasePolicy.hasEdgeWhitespace("ab "))
        XCTAssertTrue(PassphrasePolicy.hasEdgeWhitespace("ab\u{3000}"))
    }

    func testWhichWalletsMayCarryAPassphrase() {
        XCTAssertTrue(PassphrasePolicy.allowsPassphrase(isMnemonicImport: true, isPersonalWallet: true,
                                                        isElectrumSeed: false, hasCustomDerivationPath: false))
        XCTAssertFalse(PassphrasePolicy.allowsPassphrase(isMnemonicImport: false, isPersonalWallet: true,
                                                         isElectrumSeed: false, hasCustomDerivationPath: false))
        XCTAssertFalse(PassphrasePolicy.allowsPassphrase(isMnemonicImport: true, isPersonalWallet: false,
                                                         isElectrumSeed: false, hasCustomDerivationPath: false))
        XCTAssertFalse(PassphrasePolicy.allowsPassphrase(isMnemonicImport: true, isPersonalWallet: true,
                                                         isElectrumSeed: true, hasCustomDerivationPath: false))
        XCTAssertFalse(PassphrasePolicy.allowsPassphrase(isMnemonicImport: true, isPersonalWallet: true,
                                                         isElectrumSeed: false, hasCustomDerivationPath: true))
        XCTAssertEqual(PassphrasePolicy.chainsIgnoringPassphrase, [.ton, .ton20Token, .ada])
    }
}
