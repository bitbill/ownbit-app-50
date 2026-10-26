//  BILPublicSignerErrors+Prepare.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Public protocol (cold signer) — the text of a failed "Prepare" in the setup sheet of the review page (design lead
//  addendum A4). Exact port of Android core/publicsigner/.../text/PublicSignerErrors.kt:127-139 (`prepare(result)`).
//  It differs from `BILPublicPrepareResult.messageKey`, which stays the pairing panel's Prepare-card text: here a seed
//  mismatch reads `err.rebuildPublicData` and a missing secret `err.noWallet`. Pure Foundation.
//

import Foundation

extension BILPublicSignerErrors {

    /// The setup-sheet text key of a failed Prepare; nil for `.ready`.
    /// - notEligible / failed(noSecret) → `PublicProtocol.err.noWallet`
    /// - keysMismatch → `PublicProtocol.pair.keysMismatch`
    /// - failed(engineUnavailable | engine) → `PublicProtocol.err.engineUnavailable`
    /// - failed(storage | seedMismatch) → `PublicProtocol.err.rebuildPublicData`
    /// Android's `EmptyPassword` / `WrongPassword` rows (the wallet password strings) have no iOS case: the iOS password
    /// dialog validates the password before Prepare runs (D-21).
    public static func prepare(_ r: BILPublicPrepareResult) -> String? {
        switch r {
        case .ready:
            return nil
        case .notEligible:
            return "PublicProtocol.err.noWallet"
        case .keysMismatch:
            return "PublicProtocol.pair.keysMismatch"
        case .failed(let failure, _):
            switch failure {
            case .engineUnavailable, .engine:
                return "PublicProtocol.err.engineUnavailable"
            case .storage, .seedMismatch:
                return "PublicProtocol.err.rebuildPublicData"
            case .noSecret:
                return "PublicProtocol.err.noWallet"
            }
        }
    }
}
