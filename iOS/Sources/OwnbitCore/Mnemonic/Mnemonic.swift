//  Mnemonic.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  A small facade over BitcoinJSBridge / BILMnemonicValidator for the mnemonic steps of a wallet, done the way the app
//  does them:
//  · generate: a new BIP39 English mnemonic of 12 or 24 words (the app's only choices) from
//    `bridge.generateMnemonicRandom`, whose entropy comes from the web view's `window.crypto.getRandomValues`;
//  · check: the import page's offline check (word lists, count, checksum) with BILMnemonicValidator, then the bundle's
//    `validateMnemonic`;
//  · seed: BIP39 seed hex (PBKDF2-HMAC-SHA512, 2048 rounds, salt "mnemonic" + passphrase, NFKD in the bundle) with an
//    optional passphrase;
//  · the passphrase coin rule: chains whose keys come straight from the mnemonic (TON + jettons, ADA) ignore a BIP39
//    passphrase, so a passphrase wallet must not offer them. Passphrase input checks live in `PassphrasePolicy` (Vault).

import Foundation

public enum Mnemonic {

    public enum WordCount: Int, CaseIterable {
        case twelve = 12
        case twentyFour = 24

        /// Entropy bits passed to `bridge.generateMnemonicRandom`.
        public var entropyBits: Int {
            switch self {
            case .twelve: return 128
            case .twentyFour: return 256
            }
        }
    }

    public enum MnemonicError: Error, Equatable {
        /// The offline check failed (word list, count, checksum, or the word list file is missing).
        case invalid(BILMnemonicIssue)
        /// The bundle's BIP39 check said no.
        case rejectedByBIP39
        /// The bridge returned something that isn't a seed / mnemonic.
        case unexpectedResult
    }

    /// A new English BIP39 mnemonic (words separated by single spaces).
    public static func generate(wordCount: WordCount = .twelve) async throws -> String {
        let raw: String = try await withBridge { done in
            BitcoinJSBridge.shared.generateMnemonic(entropy: wordCount.entropyBits, language: BitcoinJSBridge.MnemonicLanguage.english.rawValue, success: { object in
                done(.success((object as? String) ?? ""))
            }, failure: { done(.failure($0)) })
        }
        // As the app: the ideographic space of the Japanese list becomes a normal space.
        let mnemonic = raw.replacingOccurrences(of: "\u{3000}", with: " ")
        guard mnemonic.split(separator: " ").count == wordCount.rawValue else {
            throw MnemonicError.unexpectedResult
        }
        return mnemonic
    }

    /// The offline check of the import page (normalizes the input; see BILMnemonicCheckResult.normalized).
    public static func check(_ raw: String) -> BILMnemonicCheckResult {
        return BILMnemonicValidator.shared.check(raw)
    }

    /// Offline check, then the bundle's BIP39 check (any of its 8 word lists). Returns the normalized mnemonic that the
    /// app goes on with (seed, hashes). Electrum seeds are not BIP39 and fail here (see
    /// BitcoinJSBridge.electrumMnemonicType for the app's Electrum import).
    public static func validate(_ raw: String) async throws -> String {
        let result = check(raw)
        if let issue = result.issue {
            throw MnemonicError.invalid(issue)
        }
        let isValid: Bool = try await withBridge { done in
            BitcoinJSBridge.shared.validateMnemonic(mnemonic: result.normalized, success: { object in
                done(.success((object as? Bool) ?? false))
            }, failure: { done(.failure($0)) })
        }
        guard isValid else {
            throw MnemonicError.rejectedByBIP39
        }
        return result.normalized
    }

    /// BIP39 seed (128 hex characters) of `mnemonic` with `passphrase` ("" = none). The mnemonic is used as given
    /// (pass the normalized one from `validate`).
    public static func seedHex(mnemonic: String, passphrase: String = "") async throws -> String {
        let seed: String = try await withBridge { done in
            BitcoinJSBridge.shared.mnemonicToSeedHex(mnemonic: mnemonic, password: passphrase, seedType: SEEDTYPE_BIP39, success: { object in
                done(.success((object as? String) ?? ""))
            }, failure: { done(.failure($0)) })
        }
        guard seed.count == 128, Data(hexString: seed) != nil else {
            throw MnemonicError.unexpectedResult
        }
        return seed
    }

    // MARK: - Passphrase coin rule (WalletModel+Passphrase.swift in the app)

    /// Coins derived straight from the mnemonic, ignoring a BIP39 passphrase: a passphrase wallet must not add them.
    public static let passphraseUnsupportedCoinTypes: Set<OwnbitCoinType> = [.ton, .ton20Token, .ada]

    public static func isUnsupportedWithPassphrase(_ type: OwnbitCoinType) -> Bool {
        return passphraseUnsupportedCoinTypes.contains(type)
    }

    // MARK: - Private

    /// Runs a bridge call and waits for its (single) completion.
    private static func withBridge<T>(_ start: @escaping (_ done: @escaping (Result<T, Error>) -> Void) -> Void) async throws -> T {
        return try await withCheckedThrowingContinuation { continuation in
            start { result in
                continuation.resume(with: result)
            }
        }
    }
}
