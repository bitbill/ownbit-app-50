//  BILPublicWalletFacts.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Public protocol (cold signer): a main-actor snapshot of what the public index needs from one Ownbit wallet (R2 §6.2,
//  §8.1) — taken once per operation, so the repository, the cross-check and the pairing service never touch Core Data
//  objects across an `await` — and the directory protocol that produces it (the host implements it over its wallet store;
//  the app's Core Data adapter BILPublicWalletDirectory+App.swift is not part of this package). Pure Foundation.
//

import Foundation

/// Ownbit's own stored keys and addresses of one wallet. `""` is normalized to nil everywhere (R2 §6.2: "treat "" as
/// missing"); whitespace-only values are kept but count as blank for the cross-check (Kotlin `isNotBlank`).
public struct BILPublicWalletFacts: Equatable {
    public let walletId: String
    /// Cold / normal (`isColdWallet`); the AAD kind of the sealed index.
    public let kind: BILPublicWalletKind
    /// The wallet's `seedHash`: lower-case hex SHA-256 of the UTF-8 of its 128-hex seed (nil / empty fails closed, D-08).
    public let seedHash: String?
    /// BIP44 account xpub (`mainExtPublicKey`), the Bitcoin anchor of the cross-check.
    public let legacyXpub: String?
    /// BIP49 (`btc_sw_pWallet.extendedPublicKey`).
    public let nestedXpub: String?
    /// BIP84 (`btc_sw_dWallet.extendedPublicKey`).
    public let nativeXpub: String?
    /// BIP86 receive xpub (`btc_sw_tWallet.extendedPublicKey`; hot wallets only).
    public let taprootXpub: String?
    /// ETH extended public key (`ethereumWallet.extendedPublicKey`).
    public let ethXpub: String?
    /// The stored active ETH address (#`ethIndex`).
    public let ethAddress: String?
    /// Ownbit's current ETH address index (`ethereumWallet.lastIndexNo`, ≥ 0; 0 without an ETH wallet).
    public let ethIndex: Int
    /// The stored active TRX address (#`trxIndex`: #0 = `m/44'/195'/0'/0/0`, #N ≥ 1 = ETH key #N in TRON encoding).
    public let trxAddress: String?
    /// The backup of TRX #0, set on the first switch away from #0 (`trxAddress0`).
    public let trxAddress0: String?
    /// Ownbit's current TRX address index (`tronWallet.lastIndexNo`, ≥ 0; 0 without a TRX wallet).
    public let trxIndex: Int
    /// The stored SOL address (may be missing: SOL failure does not fail creation).
    public let solAddress: String?
    /// Single-sig Bitcoin profiles with at least one receive address, in Ownbit order (taproot, native, nested, legacy).
    public let btcProfilesInUse: [BILPsBitcoinProfile]

    public init(walletId: String, kind: BILPublicWalletKind, seedHash: String?,
         legacyXpub: String?, nestedXpub: String?, nativeXpub: String?, taprootXpub: String?,
         ethXpub: String?, ethAddress: String?, ethIndex: Int,
         trxAddress: String?, trxAddress0: String?, trxIndex: Int, solAddress: String?,
         btcProfilesInUse: [BILPsBitcoinProfile]) {
        func nonEmpty(_ s: String?) -> String? {
            guard let s = s, !s.isEmpty else { return nil }
            return s
        }
        self.walletId = walletId
        self.kind = kind
        self.seedHash = nonEmpty(seedHash)
        self.legacyXpub = nonEmpty(legacyXpub)
        self.nestedXpub = nonEmpty(nestedXpub)
        self.nativeXpub = nonEmpty(nativeXpub)
        self.taprootXpub = nonEmpty(taprootXpub)
        self.ethXpub = nonEmpty(ethXpub)
        self.ethAddress = nonEmpty(ethAddress)
        self.ethIndex = max(0, ethIndex)
        self.trxAddress = nonEmpty(trxAddress)
        self.trxAddress0 = nonEmpty(trxAddress0)
        self.trxIndex = max(0, trxIndex)
        self.solAddress = nonEmpty(solAddress)
        let order: [BILPsBitcoinProfile] = [.taproot, .native, .nested, .legacy]
        self.btcProfilesInUse = order.filter { btcProfilesInUse.contains($0) }
    }

    /// The export-policy facts (Android `PublicPairingService.facts`, R2 §8.1): `hasTaprootKeys` = the Taproot receive xpub
    /// is not blank, `hasSolanaAddress` = the SOL address is not blank (Kotlin `isNullOrBlank`; so "shown in Ownbit" ⇔ the
    /// cross-check can compare it).
    public var pairingFacts: BILWalletPairingFacts {
        return BILWalletPairingFacts(kind: kind,
                                     btcProfilesInUse: Set(btcProfilesInUse),
                                     hasTaprootKeys: BILPublicWalletFacts.nonBlank(taprootXpub) != nil,
                                     evmIndex: ethIndex,
                                     tronIndex: trxIndex,
                                     hasSolanaAddress: BILPublicWalletFacts.nonBlank(solAddress) != nil)
    }

    /// Kotlin `takeIf { it.isNotBlank() }` (Kotlin whitespace set, BILKotlinText).
    public static func nonBlank(_ s: String?) -> String? {
        guard let s = s, !BILKotlinText.trim(s).isEmpty else { return nil }
        return s
    }
}

/// Descriptions never show the keys, addresses or seed hash (C-KEY-5; Android `WalletKey.toString()`).
extension BILPublicWalletFacts: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        return "BILPublicWalletFacts(kind: \(kind))"
    }

    public var debugDescription: String {
        return description
    }
}

/// Ownbit's wallets as the public index sees them (main actor: Core Data main context).
@MainActor public protocol BILPublicWalletDirectory: AnyObject {
    /// Ids of the eligible wallets, in home order.
    func eligibleWalletIds() -> [String]
    /// The eligibility of `walletId` (`.notEligible(.unknownWallet)` when it does not exist).
    func eligibility(walletId: String) -> BILPublicEligibility
    /// The snapshot of `walletId`, nil when it does not exist.
    func facts(walletId: String) -> BILPublicWalletFacts?
    /// The seed accessor of "Prepare" and of signing: the wallet's BIP39 seed as 128 hex characters, unlocked with the
    /// password the host's password dialog already accepted; nil = no secret. The seed is borrowed: the caller hands it to
    /// one engine call and drops it. (The app also took the second password of its retired double encryption; not here.)
    func seed(walletId: String, password: String) -> String?
    /// Every wallet id in the store, from a fetch that throws on failure (never "[] on error": orphan cleanup would wipe
    /// every index); also throws while the store is not safe to read (migration running, protected data unavailable).
    func allWalletIds() throws -> Set<String>
}
