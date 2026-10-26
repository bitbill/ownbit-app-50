//  BILPublicIndexTypes.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Result types of the sealed public index (spec §4.4): the wallet kind bound into the seal, the index status of a
//  wallet and the outcome of "Prepare". Port of Android core/publicsigner index/PublicIndexRepository.kt:54-116
//  (`IndexStatus`, `PrepareResult`) with the iOS additions of decision D-08. Pure Foundation.
//

import Foundation

/// The wallet kind of a public index entry. The raw value is part of the seal's additional authenticated data
/// (`io.ownbit.pubsigner.index.v1|<walletId>|<kind>`): an entry copied to a wallet of the other kind does not open.
public enum BILPublicWalletKind: Int {
    case normal = 0, cold = 1
}

/// The state of one wallet's public index (every read checks it; spec §4.4).
public enum BILPublicIndexStatus: Equatable {
    /// Stored, authentic (unsealed, current seed) and well-formed. `fingerprint`: master fingerprint, upper case (`73C5DA0A`).
    case ready(fingerprint: String)
    /// Never built (or the wallet was re-created): one password builds it ("Prepare").
    case missing
    /// An entry exists but cannot be trusted (tampered, made for another wallet / kind, key lost, malformed, seed hash
    /// changed). Never re-derived silently: "Prepare" again (`PublicProtocol.err.rebuildPublicData`).
    case needsRepair
    /// Not a public-protocol wallet, or no such wallet.
    case notEligible
    /// The engine cannot run on this device.
    case unavailable
    /// iOS only (D-08): the Keychain refused the read for a reason other than "not found" (e.g. -25308 while protected
    /// data is unavailable). Transient: never NeedsRepair, never deleted, never cached; the panel shows its loading
    /// state and re-reads later.
    case temporarilyUnreadable
}

/// Outcome of "Prepare" (one password → index derived, cross-checked, sealed, stored). Wrong / empty passwords are
/// handled by the iOS password dialog before this runs (D-21), so they have no case here.
public enum BILPublicPrepareResult: Equatable {
    public enum Failure: Equatable {
        /// The engine cannot load on this device.
        case engineUnavailable
        /// The engine (or an Ownbit bridge of the cross-check) failed or answered malformed.
        case engine
        /// Keychain / sealing failure.
        case storage
        /// The wallet has no seed on this device.
        case noSecret
        /// The unlocked seed is not the one the wallet was created with (`seedHash`).
        case seedMismatch
    }

    /// Stored; `fingerprint` as in `BILPublicIndexStatus.ready`.
    case ready(fingerprint: String)
    /// Not a public-protocol wallet (or it was deleted meanwhile).
    case notEligible
    /// The engine's keys do not match the wallet's stored addresses on that chain: nothing stored.
    case keysMismatch(BILPsChain)
    /// Nothing stored. `engineCode` is the engine's (sanitized, log-safe) error code when it refused.
    case failed(Failure, engineCode: String?)

    /// The text of the pairing panel's Prepare card (Android `PublicPairingViewModel` → `PrepareError.text()`):
    /// keysMismatch / seedMismatch → `pair.keysMismatch`; engine / engineUnavailable → `err.engineUnavailable`;
    /// storage / noSecret → `err.rebuildPublicData`; notEligible → `err.noWallet`; ready → nil.
    ///
    /// Not the review page's setup sheet: Android `PublicSignerErrors.prepare` maps seedMismatch →
    /// `err.rebuildPublicData` and noSecret → `err.noWallet` there.
    public var messageKey: String? {
        switch self {
        case .ready:
            return nil
        case .notEligible:
            return "PublicProtocol.err.noWallet"
        case .keysMismatch:
            return "PublicProtocol.pair.keysMismatch"
        case .failed(let failure, _):
            switch failure {
            case .seedMismatch:
                return "PublicProtocol.pair.keysMismatch"
            case .engine, .engineUnavailable:
                return "PublicProtocol.err.engineUnavailable"
            case .storage, .noSecret:
                return "PublicProtocol.err.rebuildPublicData"
            }
        }
    }
}
