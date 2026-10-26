//  BILPublicSignerEligibility.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Public protocol (cold signer): which wallets take part (spec §3, design D-07 / D-45). Port of Android
//  core/publicsigner eligibility/PublicSignerEligibility.kt (`of(kind, customPath, electrumType)`) on iOS wallet traits.
//  One rule decides the "Pair with other wallets" tab, whether a public index is built (eager or "Prepare"), which wallets
//  the resolver may match, and "no eligible wallet" when scanning. There is no connectivity input anywhere.
//  Pure Foundation. The host fills `Traits` from its wallet model (the app's adapter BILPublicSignerEligibility+App.swift
//  is not part of this package).
//

import Foundation

/// Whether a wallet takes part in the public protocol.
public enum BILPublicEligibility: Equatable {

    /// Why a wallet is not eligible: the first rule of `BILPublicSignerEligibility.rule` that matches.
    public enum Reason: Equatable {
        /// No such wallet (deleted meanwhile, or no id).
        case unknownWallet
        /// An Ownbit multisig wallet (hot, cold or watch): its seed is a cosigner.
        case multisig
        /// A watch wallet, or a wallet whose seed is not on this device.
        case watchOnly
        /// One private key, no chain code: no account key to export.
        case privateKey
        /// A merchant wallet (iOS only, spec F2; Android has no merchant kind).
        case merchant
        /// A wallet with a custom derivation path: its addresses are not on the standard paths.
        case customPath
        /// An Electrum-seed wallet (Electrum derivation, not BIP39 / BIP44).
        case electrumSeed
    }

    /// Eligible; the kind decides the AAD of its sealed index and whether it is built at creation (COLD only).
    case eligible(BILPublicWalletKind)
    case notEligible(Reason)

    public var isEligible: Bool {
        if case .eligible = self { return true }
        return false
    }

    /// The kind of an eligible wallet, nil otherwise.
    public var kind: BILPublicWalletKind? {
        if case .eligible(let k) = self { return k }
        return nil
    }
}

/// The eligibility rule (product decision 2026-10-12, OQ-2; iOS mapping R2 §1.2): personal HD wallets — NORMAL (hot) and
/// COLD — with a seed on this device, standard paths and a BIP39 seed. BIP39-passphrase wallets are eligible (they need
/// nothing beyond the seed accessor; no trait exists for them on purpose).
public enum BILPublicSignerEligibility {

    /// What of a wallet decides its eligibility (a snapshot; the adapter fills it from a `WalletModel` on the main actor).
    public struct Traits: Equatable {
        /// The wallet exists and has a non-empty id.
        public var exists: Bool
        /// `MultiSigWalletModel` (any multisig: hot, cold, watch).
        public var isMultisig: Bool
        /// `isObserverMode` (a private-key wallet: no private key stored).
        public var isObserver: Bool
        /// A non-empty `encryptedSeed`.
        public var hasSeed: Bool
        /// `PrivateKeyWalletModel`.
        public var isPrivateKey: Bool
        /// `MerchantWalletModel`.
        public var isMerchant: Bool
        /// `extraStr` holds the custom-path marker (`;customized_path_start;`), whatever path follows (D-11: stricter
        /// than `getSeedTypePath() == "0"`, which a custom path written as "0" would pass).
        public var hasCustomPathMarker: Bool
        /// `getSeedType() != 0` (Electrum legacy / segwit seed).
        public var isElectrum: Bool
        /// `isColdWallet` (cold wallet id and not a watch wallet).
        public var isCold: Bool

        public init(exists: Bool, isMultisig: Bool, isObserver: Bool, hasSeed: Bool, isPrivateKey: Bool, isMerchant: Bool,
                    hasCustomPathMarker: Bool, isElectrum: Bool, isCold: Bool) {
            self.exists = exists
            self.isMultisig = isMultisig
            self.isObserver = isObserver
            self.hasSeed = hasSeed
            self.isPrivateKey = isPrivateKey
            self.isMerchant = isMerchant
            self.hasCustomPathMarker = hasCustomPathMarker
            self.isElectrum = isElectrum
            self.isCold = isCold
        }
    }

    /// D-07 precedence, first match wins: unknown → multisig → watch → private key → no seed (watch) → merchant →
    /// custom-path marker → Electrum → eligible (kind cold / normal). A private-key wallet keeps its own reason although it
    /// has no seed (its secret is the key); the reason is informational only (every not-eligible wallet looks the same).
    public static func rule(_ t: Traits) -> BILPublicEligibility {
        if !t.exists { return .notEligible(.unknownWallet) }
        if t.isMultisig { return .notEligible(.multisig) }
        if t.isObserver { return .notEligible(.watchOnly) }
        if t.isPrivateKey { return .notEligible(.privateKey) }
        if !t.hasSeed { return .notEligible(.watchOnly) }
        if t.isMerchant { return .notEligible(.merchant) }
        if t.hasCustomPathMarker { return .notEligible(.customPath) }
        if t.isElectrum { return .notEligible(.electrumSeed) }
        return .eligible(t.isCold ? .cold : .normal)
    }

    /// A seed string the engine accepts: exactly 128 hex characters (`keys.js` is case-insensitive). Anything else is
    /// treated as "no secret" — never sent to the engine (R2 §1.3).
    public static func isSeedHex(_ s: String) -> Bool {
        let units = Array(s.utf16)
        guard units.count == 128 else { return false }
        for u in units {
            switch u {
            case 0x30...0x39, 0x41...0x46, 0x61...0x66:
                continue
            default:
                return false
            }
        }
        return true
    }
}
