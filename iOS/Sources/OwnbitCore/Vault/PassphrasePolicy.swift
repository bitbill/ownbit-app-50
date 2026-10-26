//  PassphrasePolicy.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  The app's rules for BIP39 passphrases ("25th word"):
//    · offered only when IMPORTING a mnemonic, and only into a personal wallet (online import = personal hot wallet,
//      offline import of an external mnemonic = personal cold wallet). Not for created wallets, multisig, merchant or
//      private-key wallets, Electrum seeds or custom derivation paths;
//    · a mistyped passphrase is simply another (empty) wallet and cannot be detected: the app asks for it twice and
//      shows the first BTC / ETH / TRX addresses before importing;
//    · stored only encrypted, with the wallet password, next to the mnemonic (see `WalletSecrets`); no hash of it;
//    · the seed is BIP39(mnemonic, passphrase), computed once at import; signing uses the seed only;
//    · the same mnemonic with and without a passphrase are two different wallets (tell them apart by seedHash);
//    · chains whose keys are derived straight from the mnemonic instead of the seed would silently ignore the
//      passphrase, so a passphrase wallet must not add them (`chainsIgnoringPassphrase`);
//    · not included in cloud mnemonic backups, no "verify mnemonic" step.

import Foundation

public enum PassphrasePolicy {

    /// Maximum length in characters (BIP39 sets none; 100 like Ledger).
    public static let maxLength = 100

    /// Chains whose keys come straight from the mnemonic, ignoring the passphrase: TON (shown as GRAM, including its
    /// jettons) and ADA. A passphrase wallet must not offer them. Single source: `Mnemonic.passphraseUnsupportedCoinTypes`.
    public static var chainsIgnoringPassphrase: Set<OwnbitCoinType> { Mnemonic.passphraseUnsupportedCoinTypes }

    public enum ValidationError: Error, Equatable {
        case empty
        case tooLong(maxLength: Int)
        /// Control characters (newline, tab, ...) or U+2028 / U+2029: cannot be typed, only pasted.
        case invalidCharacter
    }

    /// Whether the import flow may offer a passphrase for this wallet.
    /// - Parameters:
    ///   - isMnemonicImport: importing an existing mnemonic (not creating a new wallet, not a private key).
    ///   - isPersonalWallet: a personal hot or personal cold wallet (not multisig, not merchant).
    ///   - isElectrumSeed: an Electrum seed instead of BIP39.
    ///   - hasCustomDerivationPath: the user chose a custom derivation path.
    public static func allowsPassphrase(isMnemonicImport: Bool, isPersonalWallet: Bool,
                                        isElectrumSeed: Bool, hasCustomDerivationPath: Bool) -> Bool {
        return isMnemonicImport && isPersonalWallet && !isElectrumSeed && !hasCustomDerivationPath
    }

    /// Input check: not empty, at most `maxLength` characters, no control characters. Leading / trailing spaces are
    /// NOT removed — they are part of the passphrase (warn with `hasEdgeWhitespace`).
    public static func validationError(_ passphrase: String) -> ValidationError? {
        if passphrase.isEmpty {
            return .empty
        }
        if passphrase.count > maxLength {
            return .tooLong(maxLength: maxLength)
        }
        if passphrase.unicodeScalars.contains(where: {
            CharacterSet.controlCharacters.contains($0) || $0 == "\u{2028}" || $0 == "\u{2029}"
        }) {
            return .invalidCharacter
        }
        return nil
    }

    /// True when the passphrase starts or ends with a space-like character (worth a warning).
    public static func hasEdgeWhitespace(_ passphrase: String) -> Bool {
        guard let first = passphrase.unicodeScalars.first, let last = passphrase.unicodeScalars.last else { return false }
        return CharacterSet.whitespaces.contains(first) || CharacterSet.whitespaces.contains(last)
    }
}
