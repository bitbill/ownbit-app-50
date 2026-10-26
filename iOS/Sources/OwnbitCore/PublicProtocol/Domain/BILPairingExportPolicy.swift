//  BILPairingExportPolicy.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  The export policy of the "Pair with other wallets" tab (spec §5.1, §5.3; pure, no I/O): which engine call makes the
//  pairing QR of a selection, which Ownbit address it must equal, and the notes the panel shows.
//  Port of Android core/publicsigner pairing/PairingExportPolicy.kt (rules verbatim, notes R2 §7.2–7.5) and the notes
//  banner filter of ui/PublicPairingPanel.kt:333-356 (R3 §6.9). Pure Foundation.
//

import Foundation

/// What Ownbit knows about the wallet a pairing export is made for (local rows only; built by the pairing service).
///
/// - `btcProfilesInUse`: single-sig Bitcoin profiles with receive addresses in this wallet ("Used in this Ownbit wallet").
/// - `hasTaprootKeys`: Ownbit holds this wallet's BIP86 keys (hot personal wallets; cold wallets never do).
/// - `evmIndex`: Ownbit's current ETH address index N (shared by every EVM chain).
/// - `tronIndex`: Ownbit's current TRX index N (the stepper reaches at least it).
/// - `hasSolanaAddress`: Ownbit has this wallet's SOL address (the standard preset).
public struct BILWalletPairingFacts: Equatable {
    public let kind: BILPublicWalletKind
    public let btcProfilesInUse: Set<BILPsBitcoinProfile>
    public let hasTaprootKeys: Bool
    public let evmIndex: Int
    public let tronIndex: Int
    public let hasSolanaAddress: Bool

    /// Android's initializer refuses BIP48 profiles in `btcProfilesInUse` and negative indexes (programming errors).
    /// iOS normalizes instead of crashing: BIP48 profiles are dropped (Ownbit never has their addresses) and a negative
    /// index reads as 0. That is the value Android's only builder produces for the same wallet
    /// (`PublicPairingService.facts`: single-sig profiles only; ETH / TRX row missing → 0, `indexNo.coerceAtLeast(0)`),
    /// so a builder may pass `lastIndexNo ?? -1` and get Android's result.
    public init(kind: BILPublicWalletKind, btcProfilesInUse: Set<BILPsBitcoinProfile> = [], hasTaprootKeys: Bool = false,
         evmIndex: Int = 0, tronIndex: Int = 0, hasSolanaAddress: Bool = false) {
        self.kind = kind
        self.btcProfilesInUse = btcProfilesInUse.filter { !$0.isMultisig }
        self.hasTaprootKeys = hasTaprootKeys
        self.evmIndex = max(0, evmIndex)
        self.tronIndex = max(0, tronIndex)
        self.hasSolanaAddress = hasSolanaAddress
    }
}

/// A note the pairing panel shows for an export (each maps to one `PublicProtocol.*` string).
enum BILPairingNote: CaseIterable {
    /// The QR carries an account key: the other wallet sees every address.
    case accountKey
    /// Address only, no key or path.
    case addressOnly
    /// One BIP48 cosigner key, no threshold / policy.
    case cosigner
    /// Ownbit does not show these addresses for this wallet (separate orange warning under the options).
    case notInOwnbit
    /// This Bitcoin address type has addresses in this wallet (tag on the profile row / sheet).
    case usedInWallet
    /// Ownbit uses ETH address #N > 0: add accounts up to Account N + 1 in the other wallet (args N, N + 1).
    case evmAccountN
    /// TRON #0: the same address in Ownbit and in every other wallet (inside the stepper card).
    case tronIndex0
    /// TRON #N ≥ 1: Ownbit's TRX address #N (inside the stepper card; arg N = the plan's `addressIndex`).
    case tronIndexN
    /// Ownbit currently uses TRON address #N (also #0) and another index is exported (arg N = `tronCurrentN`).
    case tronCurrentN
    /// The wallet uses several Bitcoin address types: pair each one.
    case btcPairEachType
    /// Third-party wallets scan about 20 unused addresses.
    case btcGapLimit

    var stringKey: String {
        switch self {
        case .accountKey: return "PublicProtocol.pair.note.accountKey"
        case .addressOnly: return "PublicProtocol.pair.note.addressOnly"
        case .cosigner: return "PublicProtocol.pair.note.cosigner"
        case .notInOwnbit: return "PublicProtocol.pair.notInOwnbit"
        case .usedInWallet: return "PublicProtocol.pair.usedInWallet"
        case .evmAccountN: return "PublicProtocol.pair.evmAccountN"
        case .tronIndex0: return "PublicProtocol.pair.tronIndex0"
        case .tronIndexN: return "PublicProtocol.pair.tronIndexN"
        case .tronCurrentN: return "PublicProtocol.pair.tronCurrentN"
        case .btcPairEachType: return "PublicProtocol.pair.btcPairEachType"
        case .btcGapLimit: return "PublicProtocol.pair.btcGapLimit"
        }
    }
}

/// How the export is produced.
///
/// - `enginePairing`: `createPublicPairing(index, chain, profile, outputMode, index)`. `index` is 0 except on TRON (the
///   only chain the engine exports another address index for; #N in the Ownbit TRON scheme). Android's initializer
///   refuses a non-zero index on another chain; the policy below never builds one.
/// - `evmAddressAt`: the EVM address mode at Ownbit's current address #N: `derivePublicAddresses(index, "evm",
///   start: N, count: 1)` rendered like the engine's address mode.
enum BILExportCall: Equatable {
    case enginePairing(chain: BILPsChain, profile: String?, mode: BILPsOutputMode, index: Int)
    case evmAddressAt(index: Int)
}

/// The export of one selection for one wallet.
///
/// - `addressIndex`: the exported address index (EVM address mode: Ownbit's #N; TRON: the stepper's #N; else 0).
/// - `ownbitCheck`: the check key whose Ownbit address the QR's first address must equal (nil = nothing to compare
///   with: BIP48, Solana Trust / Legacy, Taproot without Ownbit keys).
/// - `requireOwnbitMatch`: the export is refused unless `ownbitCheck` was confirmed (EVM, TRON, BTC Legacy); otherwise
///   an unconfirmed check only drops the "Same as in Ownbit" mark.
/// - `shownInOwnbit`: Ownbit shows the exported addresses for this wallet (else `.notInOwnbit`).
/// - `evmAccountN` / `tronCurrentN`: Ownbit's current ETH / TRX index (the N of `.evmAccountN` / `.tronCurrentN`).
struct BILExportPlan: Equatable {
    let selection: BILPairingSelection
    let call: BILExportCall
    let addressIndex: Int
    let ownbitCheck: String?
    let requireOwnbitMatch: Bool
    let shownInOwnbit: Bool
    let notes: [BILPairingNote]
    let evmAccountN: Int
    let tronCurrentN: Int
}

enum BILPairingExportPolicyError: Error, Equatable {
    /// TRON index outside 0 … `maxTronIndex(facts)` (a programming error of the caller; never an engine call).
    case tronIndexOutOfRange
}

enum BILPairingExportPolicy {

    /// The TRON address index the tab opens with (never remembered between visits).
    static let tronDefaultIndex = 0

    /// The stepper's upper end when Ownbit's own TRX index is lower: the public index caches TRON #0 … #99, so requests
    /// that name only an address (TronLink) find every address the stepper offers.
    static let tronStepperMax = 99

    /// The highest TRON index the stepper offers: #99, or Ownbit's current TRX index when it is higher.
    static func maxTronIndex(_ facts: BILWalletPairingFacts?) -> Int {
        return max(tronStepperMax, facts?.tronIndex ?? 0)
    }

    /// The export of `s` for a wallet described by `facts`. `tronIndex` = the stepper's TRON address #N (ignored on the
    /// other chains, which export index 0 or, in the EVM address mode, Ownbit's current #N).
    /// - Throws: `.tronIndexOutOfRange` when `tronIndex` is outside 0 … `maxTronIndex(facts)` on TRON.
    static func plan(_ s: BILPairingSelection, facts: BILWalletPairingFacts, tronIndex: Int) throws -> BILExportPlan {
        switch s.chain {
        case .bitcoin: return bitcoin(s, facts)
        case .evm: return evm(s, facts)
        case .tron: return try tron(s, facts, tronIndex)
        case .solana: return solana(s, facts)
        }
    }

    /// The notes of the info banner under the verification card, in plan order (Android `NotesBanner`): `.accountKey`
    /// except on Solana (one plain key, no xpub), `.addressOnly`, `.cosigner`, `.evmAccountN`, `.tronCurrentN`,
    /// `.btcPairEachType`, `.btcGapLimit`. `.notInOwnbit`, `.usedInWallet`, `.tronIndex0`, `.tronIndexN` are shown
    /// elsewhere (warning, profile row tag, stepper card). Texts are joined with "\n\n"; empty → no banner.
    static func bannerNotes(_ plan: BILExportPlan) -> [BILPairingNote] {
        return plan.notes.filter { note in
            switch note {
            case .accountKey: return plan.selection.chain != .solana
            case .addressOnly, .cosigner, .evmAccountN, .tronCurrentN, .btcPairEachType, .btcGapLimit: return true
            case .notInOwnbit, .usedInWallet, .tronIndex0, .tronIndexN: return false
            }
        }
    }

    // MARK: check keys (shared with the index cross-check)

    static func bitcoinKey(_ p: BILPsBitcoinProfile) -> String {
        return "bitcoin:" + p.rawValue
    }

    static func evmKey(_ n: Int) -> String {
        return "evm:" + String(n)
    }

    static func tronKey(_ n: Int) -> String {
        return "tron:" + String(n)
    }

    static let solanaStandardKey = "solana:standard"

    // MARK: per chain (Android `PairingExportPolicy.kt:198-301`)

    private static func tron(_ s: BILPairingSelection, _ facts: BILWalletPairingFacts, _ n: Int) throws -> BILExportPlan {
        guard n >= 0 && n <= maxTronIndex(facts) else { throw BILPairingExportPolicyError.tronIndexOutOfRange }
        var notes: [BILPairingNote] = [.addressOnly, n == 0 ? .tronIndex0 : .tronIndexN]
        // Ownbit shows only its current TRX address, also when that is #0 (a new wallet): say which one.
        if n != facts.tronIndex { notes.append(.tronCurrentN) }
        return BILExportPlan(selection: s,
                             call: .enginePairing(chain: .tron, profile: nil, mode: .address, index: n),
                             addressIndex: n,
                             ownbitCheck: tronKey(n),
                             requireOwnbitMatch: true,
                             shownInOwnbit: true,
                             notes: notes,
                             evmAccountN: 0,
                             tronCurrentN: facts.tronIndex)
    }

    /// Ownbit shows the addresses of Bitcoin `profile` for this wallet.
    private static func bitcoinShownInOwnbit(_ profile: BILPsBitcoinProfile, _ facts: BILWalletPairingFacts) -> Bool {
        if profile.isMultisig { return false }
        if profile == .taproot { return facts.hasTaprootKeys }
        return true
    }

    private static func bitcoin(_ s: BILPairingSelection, _ facts: BILWalletPairingFacts) -> BILExportPlan {
        let profile = s.bitcoinProfile
        let call = BILExportCall.enginePairing(chain: .bitcoin, profile: profile.rawValue, mode: s.outputMode, index: 0)
        if profile.isMultisig {
            return BILExportPlan(selection: s, call: call, addressIndex: 0, ownbitCheck: nil, requireOwnbitMatch: false,
                                 shownInOwnbit: false, notes: [.cosigner, .notInOwnbit], evmAccountN: 0, tronCurrentN: 0)
        }
        let shown = bitcoinShownInOwnbit(profile, facts)
        var notes: [BILPairingNote] = [s.outputMode == .address ? .addressOnly : .accountKey]
        if !shown { notes.append(.notInOwnbit) }
        if facts.btcProfilesInUse.contains(profile) { notes.append(.usedInWallet) }
        if facts.btcProfilesInUse.count > 1 { notes.append(.btcPairEachType) }
        if s.outputMode == .accountXpub { notes.append(.btcGapLimit) }
        return BILExportPlan(selection: s, call: call, addressIndex: 0,
                             ownbitCheck: shown ? bitcoinKey(profile) : nil,
                             requireOwnbitMatch: profile == .legacy,
                             shownInOwnbit: shown, notes: notes, evmAccountN: 0, tronCurrentN: 0)
    }

    private static func evm(_ s: BILPairingSelection, _ facts: BILWalletPairingFacts) -> BILExportPlan {
        let n = facts.evmIndex
        if s.outputMode == .address {
            return BILExportPlan(selection: s, call: .evmAddressAt(index: n), addressIndex: n, ownbitCheck: evmKey(n),
                                 requireOwnbitMatch: true, shownInOwnbit: true, notes: [.addressOnly],
                                 evmAccountN: n, tronCurrentN: 0)
        }
        return BILExportPlan(selection: s,
                             call: .enginePairing(chain: .evm, profile: nil, mode: .wallet, index: 0),
                             addressIndex: 0, ownbitCheck: evmKey(0), requireOwnbitMatch: true, shownInOwnbit: true,
                             notes: n > 0 ? [.accountKey, .evmAccountN] : [.accountKey],
                             evmAccountN: n, tronCurrentN: 0)
    }

    private static func solana(_ s: BILPairingSelection, _ facts: BILWalletPairingFacts) -> BILExportPlan {
        let profile = s.solanaProfile
        let shown = profile.matchesOwnbit
        var notes: [BILPairingNote] = [s.outputMode == .address ? .addressOnly : .accountKey]
        if !shown { notes.append(.notInOwnbit) }
        return BILExportPlan(selection: s,
                             call: .enginePairing(chain: .solana, profile: profile.rawValue, mode: s.outputMode, index: 0),
                             addressIndex: 0,
                             ownbitCheck: (shown && facts.hasSolanaAddress) ? solanaStandardKey : nil,
                             requireOwnbitMatch: false, shownInOwnbit: shown, notes: notes,
                             evmAccountN: 0, tronCurrentN: 0)
    }
}
