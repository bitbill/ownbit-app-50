//  BILPublicSignerOp.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Public protocol (cold signer) — the allowlist of engine operations (C-KEY-3, design §3.4). Port of Android
//  `core/jsengine/.../bridge/PublicSignerOp.kt`: the raw value is the exact `"operation"` of the request; nothing else
//  ever reaches `signer.js`. Deliberately absent (the engine has them, Ownbit never calls them): the phrase / wordlist
//  helpers, unplanned signing, account / cosigner / policy derivation, QR encode / decode, wallet-level pairing.
//
//  Guard rule 3 (tests/guard/guard.py): this file holds exactly the 11 string literals below, in this order, and no
//  other string literal. Pure Foundation.
//

import Foundation

/// Which engine context an operation may run on (design D-02, Android `PublicSignerPage`):
/// - `pairing`: the one warm context; only the device's own unsealed and cross-checked public index, never a seed or
///   external input.
/// - `secret`: receives the wallet seed; a fresh context for exactly one call, dropped afterwards.
/// - `untrusted`: receives another wallet's request; a fresh context per request (`review` + `resolveSigningPlan` of
///   the same request share it), dropped afterwards.
/// - `scan`: one camera session (`scanBegin` + its `scanAdd` frames) owns a fresh context until the session ends.
enum BILPublicSignerPage {
    case pairing, secret, untrusted, scan
}

/// The 11 operations Ownbit may send to the engine, in Android's order.
enum BILPublicSignerOp: String, CaseIterable {
    case capabilities = "capabilities"
    case derivePublicAddresses = "derivePublicAddresses"
    case createPublicPairing = "createPublicPairing"
    case derivePublicIndex = "derivePublicIndex"
    case signPlanTask = "signPlanTask"
    case scanBegin = "scanBegin"
    case scanAdd = "scanAdd"
    case decodePayload = "decodePayload"
    case review = "review"
    case resolveSigningPlan = "resolveSigningPlan"
    case encodeResponse = "encodeResponse"

    var page: BILPublicSignerPage {
        switch self {
        case .capabilities, .derivePublicAddresses, .createPublicPairing:
            return .pairing
        case .derivePublicIndex, .signPlanTask:
            return .secret
        case .scanBegin, .scanAdd:
            return .scan
        case .decodePayload, .review, .resolveSigningPlan, .encodeResponse:
            return .untrusted
        }
    }

    /// `true` only for the two operations whose request carries the wallet seed.
    var carriesSeed: Bool {
        return page == .secret
    }
}
