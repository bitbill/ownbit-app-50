//  BILPublicProtocolModels.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Public protocol (coin-level pairing / signing for other wallets): what the "Pair with other wallets" tab exports
//  (chain, Bitcoin / Solana profile, output mode) and the public coin ids.
//  Port of Android core/publicsigner model/{PsChain,PsProfiles,PairingSelection}.kt (notes R2 §7.1). Pure Foundation:
//  no UIKit, no app types (compiled by the macOS harness scripts/public-protocol/tests/domain).
//

import Foundation

// MARK: - Chain

/// A chain family of the public protocol (the engine's `chain` values). Declaration order = the chain picker's order
/// (Bitcoin, EVM, TRON, Solana). Only these four exist (product decision: no other chains).
public enum BILPsChain: String, CaseIterable {
    case bitcoin, evm, tron, solana

    /// The name shown in the UI; brand / standard names are never translated.
    public var brandName: String {
        switch self {
        case .bitcoin: return "Bitcoin"
        case .evm: return "EVM"
        case .tron: return "TRON"
        case .solana: return "Solana"
        }
    }

    /// The chain of an engine value; nil for anything else (fail closed, never a default chain). Exact code-unit
    /// comparison (never Swift canonical equivalence).
    public static func fromWire(_ s: String?) -> BILPsChain? {
        guard let s = s else { return nil }
        return BILPsChain.allCases.first { BILPublicDomainText.same($0.rawValue, s) }
    }
}

// MARK: - Bitcoin profile

/// A Bitcoin export profile (engine `profile`). **Declaration order = Ownbit display order** (Taproot, Native SegWit,
/// Nested SegWit, Legacy), then the two BIP48 cosigner profiles of the "Multisig" segment. Raw value = engine wire.
public enum BILPsBitcoinProfile: String, CaseIterable {
    case taproot, native, nested, legacy, multisigNative = "multisig-native", multisigNested = "multisig-nested"

    /// The account node the export carries.
    public var accountPath: String {
        switch self {
        case .taproot: return "m/86'/0'/0'"
        case .native: return "m/84'/0'/0'"
        case .nested: return "m/49'/0'/0'"
        case .legacy: return "m/44'/0'/0'"
        case .multisigNative: return "m/48'/0'/0'/2'"
        case .multisigNested: return "m/48'/0'/0'/1'"
        }
    }

    /// A BIP48 cosigner key (account xpub only, no threshold / policy).
    public var isMultisig: Bool {
        return self == .multisigNative || self == .multisigNested
    }

    /// First receive address path (`<account>/0/0`); nil for the cosigner profiles (no single address).
    public var firstAddressPath: String? {
        return isMultisig ? nil : accountPath + "/0/0"
    }

    /// Option title (`PublicProtocol.pair.profile.*`; the single-sig ones equal iOS `segwit_option_4/3/2/1`).
    public var titleKey: String {
        switch self {
        case .taproot: return "PublicProtocol.pair.profile.taproot"
        case .native: return "PublicProtocol.pair.profile.native"
        case .nested: return "PublicProtocol.pair.profile.nested"
        case .legacy: return "PublicProtocol.pair.profile.legacy"
        case .multisigNative: return "PublicProtocol.pair.profile.msNative"
        case .multisigNested: return "PublicProtocol.pair.profile.msNested"
        }
    }

    /// Technical detail of the option (standard names, the same in every language; Android `ProfileDetails.bitcoin`).
    public var detail: String {
        switch self {
        case .taproot: return "BIP86 · bc1p…"
        case .native: return "BIP84 · bc1q…"
        case .nested: return "BIP49 · 3…"
        case .legacy: return "BIP44 · 1…"
        case .multisigNative: return "BIP48 · P2WSH"
        case .multisigNested: return "BIP48 · P2SH-P2WSH"
        }
    }

    /// "Single-sig" segment, Ownbit display order (default `.native`).
    public static let singleSig: [BILPsBitcoinProfile] = [.taproot, .native, .nested, .legacy]

    /// "Multisig" segment: BIP48 cosigner profiles, native first (default `.multisigNative`).
    public static let multisig: [BILPsBitcoinProfile] = [.multisigNative, .multisigNested]
}

// MARK: - Solana profile

/// A Solana preset (engine `profile`). `.standard` is Ownbit's own SOL address and the default; `.trust` / `.legacy`
/// are addresses Ownbit never shows (offered under "More paths" with the "not shown in Ownbit" warning).
public enum BILPsSolanaProfile: String, CaseIterable {
    case standard, trust, legacy

    public var path: String {
        switch self {
        case .standard: return "m/44'/501'/0'/0'"
        case .trust: return "m/44'/501'/0'"
        case .legacy: return "m/44'/501'"
        }
    }

    /// The same address as Ownbit's SOL account.
    public var matchesOwnbit: Bool {
        return self == .standard
    }

    /// Listed under the "More paths" heading of the option sheet (`PublicProtocol.pair.morePaths`).
    public var isMorePath: Bool {
        return !matchesOwnbit
    }

    public var titleKey: String {
        switch self {
        case .standard: return "PublicProtocol.pair.sol.standard"
        case .trust: return "PublicProtocol.pair.sol.trust"
        case .legacy: return "PublicProtocol.pair.sol.legacy"
        }
    }
}

// MARK: - Output mode

/// What a pairing QR carries (engine `outputMode`; raw value = wire).
public enum BILPsOutputMode: String {
    /// BTC `ur:crypto-account` (one output descriptor).
    case accountXpub
    /// EVM `ur:crypto-hdkey` (EIP-4527) / Solana `ur:crypto-multi-accounts`.
    case wallet
    /// Plain address text.
    case address

    /// The QR carries a public key node: the host logs `xpubExported`; an address-only QR logs `watchQRShown` (C-LOG-2).
    public var bearsKey: Bool {
        return self != .address
    }

    /// Segment title of the "Export as" row.
    public var titleKey: String {
        switch self {
        case .accountXpub: return "PublicProtocol.pair.mode.accountXpub"
        case .wallet: return "PublicProtocol.pair.mode.wallet"
        case .address: return "PublicProtocol.pair.mode.address"
        }
    }
}

// MARK: - Selection

/// What the "Pair with other wallets" tab exports: chain, its profile and the output mode. Always a combination the
/// engine accepts: the initializer refuses any other (nil), and the `with…` copies fall back to the chain's default
/// mode when the old one no longer applies. A value type, so it is also the stale-result key of the pairing panel
/// (together with the TRON index).
///
/// `bitcoinProfile` / `solanaProfile` are kept (but ignored) on the other chains, so switching back restores them.
public struct BILPairingSelection: Hashable {
    public let chain: BILPsChain
    public let bitcoinProfile: BILPsBitcoinProfile
    public let solanaProfile: BILPsSolanaProfile
    public let outputMode: BILPsOutputMode

    /// nil when `outputMode` is not one of `modes(for: chain, bitcoinProfile:)`; a nil mode = the default (first) one.
    public init?(chain: BILPsChain, bitcoinProfile: BILPsBitcoinProfile = .native, solanaProfile: BILPsSolanaProfile = .standard,
          outputMode: BILPsOutputMode? = nil) {
        let modes = BILPairingSelection.modes(for: chain, bitcoinProfile: bitcoinProfile)
        let mode = outputMode ?? modes[0]
        guard modes.contains(mode) else { return nil }
        self.chain = chain
        self.bitcoinProfile = bitcoinProfile
        self.solanaProfile = solanaProfile
        self.outputMode = mode
    }

    /// The selection the tab opens with on every entry (never remembered): Bitcoin · Native SegWit · account XPUB.
    public static let `default`: BILPairingSelection = BILPairingSelection(chain: .bitcoin)!

    /// Modes the engine accepts, default first: BTC single-sig account XPUB / address, BTC cosigner account XPUB only,
    /// EVM and Solana wallet / address, TRON address only.
    public static func modes(for chain: BILPsChain, bitcoinProfile: BILPsBitcoinProfile) -> [BILPsOutputMode] {
        switch chain {
        case .bitcoin:
            return bitcoinProfile.isMultisig ? [.accountXpub] : [.accountXpub, .address]
        case .evm, .solana:
            return [.wallet, .address]
        case .tron:
            return [.address]
        }
    }

    /// Output modes the user can pick for this selection, default first.
    public var availableModes: [BILPsOutputMode] {
        return BILPairingSelection.modes(for: chain, bitcoinProfile: bitcoinProfile)
    }

    /// The engine `profile` parameter: BTC / SOL profile wire, nil for EVM and TRON (engine default).
    public var profileWire: String? {
        switch chain {
        case .bitcoin: return bitcoinProfile.rawValue
        case .solana: return solanaProfile.rawValue
        case .evm, .tron: return nil
        }
    }

    /// The QR carries a key node (logs `xpubExported`) rather than one address (`watchQRShown`).
    public var bearsKey: Bool {
        return outputMode.bearsKey
    }

    /// Same selection on `chain`, with that chain's default mode when the current one does not apply there.
    public func with(chain: BILPsChain) -> BILPairingSelection {
        return normalized(chain: chain, bitcoinProfile: bitcoinProfile, solanaProfile: solanaProfile)
    }

    /// Same selection with `bitcoinProfile`; the mode falls back to the profile's default when needed.
    public func with(bitcoinProfile: BILPsBitcoinProfile) -> BILPairingSelection {
        return normalized(chain: chain, bitcoinProfile: bitcoinProfile, solanaProfile: solanaProfile)
    }

    public func with(solanaProfile: BILPsSolanaProfile) -> BILPairingSelection {
        return normalized(chain: chain, bitcoinProfile: bitcoinProfile, solanaProfile: solanaProfile)
    }

    /// Same selection with `outputMode` if allowed, else unchanged.
    public func with(outputMode: BILPsOutputMode) -> BILPairingSelection {
        guard availableModes.contains(outputMode) else { return self }
        return BILPairingSelection(chain: chain, bitcoinProfile: bitcoinProfile, solanaProfile: solanaProfile,
                                   outputMode: outputMode) ?? self
    }

    private func normalized(chain: BILPsChain, bitcoinProfile: BILPsBitcoinProfile,
                            solanaProfile: BILPsSolanaProfile) -> BILPairingSelection {
        let modes = BILPairingSelection.modes(for: chain, bitcoinProfile: bitcoinProfile)
        let mode = modes.contains(outputMode) ? outputMode : modes[0]
        // Never nil: `mode` is one of `modes`.
        return BILPairingSelection(chain: chain, bitcoinProfile: bitcoinProfile, solanaProfile: solanaProfile,
                                   outputMode: mode) ?? self
    }
}

// MARK: - Public coin ids

/// Ownbit's coin of a public request / record (icon, network name). Raw values = iOS `CoinType` raw values, so UI and
/// records map with `CoinType(rawValue: Int64(coin.rawValue))`. `.polygon` is iOS's "avax" slot (51), which Ownbit uses
/// for Polygon. Android `PublicReviewPresenter.networkCoin` / `OfflineSignRecord.publicCoinType` (R6 §3.2, R7 §4.6).
enum BILPublicCoin: Int {
    case btc = 0, ethereum = 1, etc = 5, trx = 25, bsc = 40, sol = 47, polygon = 51 /* iOS "avax" slot */,
         arb = 53, op = 55, base = 59, hype = 62

    /// The native coin of an EVM network by its EIP-155 chain id (decimal string, Kotlin `toLongOrNull()` rules:
    /// optional `+` / `-` sign, ASCII digits, Int64 range, no trimming): 1 ETH, 56 BSC, 61 ETC, 137 Polygon,
    /// 42161 ARB, 10 OP, 8453 BASE, 999 HYPE; anything else (Gnosis 100, Avalanche C 43114, nil, junk) → nil
    /// (generic mark + the engine's network name). Callers whose Android counterpart trims (the offline-sign record
    /// builder) trim before calling.
    static func native(evmChainId: String?) -> BILPublicCoin? {
        guard let text = evmChainId, let id = BILPublicDomainText.kotlinLong(text) else { return nil }
        switch id {
        case 1: return .ethereum
        case 56: return .bsc
        case 61: return .etc
        case 137: return .polygon
        case 42_161: return .arb
        case 10: return .op
        case 8_453: return .base
        case 999: return .hype
        default: return nil
        }
    }

    /// bitcoin → BTC, tron → TRX, solana → SOL, evm → `native(evmChainId:)`, nil chain → nil.
    static func of(chain: BILPsChain?, chainId: String?) -> BILPublicCoin? {
        guard let chain = chain else { return nil }
        switch chain {
        case .bitcoin: return .btc
        case .tron: return .trx
        case .solana: return .sol
        case .evm: return native(evmChainId: chainId)
        }
    }
}

// MARK: - Helpers shared by the Domain files

/// Exact-text helpers of the Domain files (they must not depend on Core, so the domain compiles on its own).
/// Domain-internal: only the files in `Modules/PublicProtocol/Domain/` use this; every other public-protocol file uses
/// `BILKotlinText` (WP1, `Core/BILKotlinText.swift`). `isKotlinWhitespace` must stay identical to
/// `BILKotlinText.isWhitespace` (same Kotlin `Char.isWhitespace` table); a fix to one is a fix to both.
enum BILPublicDomainText {
    /// Exact UTF-16 code-unit equality (never Swift canonical equivalence: "\u{212A}" KELVIN SIGN ≠ "K").
    static func same(_ a: String, _ b: String) -> Bool {
        return a.utf16.elementsEqual(b.utf16)
    }

    /// Kotlin `String.toLongOrNull()` for ASCII input: optional leading `+` / `-`, at least one digit, only `0-9`
    /// after it, within Int64. Non-ASCII digits (which Kotlin would accept) → nil (fail closed).
    static func kotlinLong(_ s: String) -> Int64? {
        let units = Array(s.utf16)
        guard !units.isEmpty else { return nil }
        var i = 0
        var negative = false
        if units[0] == 0x2B || units[0] == 0x2D {          // "+" / "-"
            guard units.count > 1 else { return nil }
            negative = units[0] == 0x2D
            i = 1
        }
        // Accumulated negatively (as Kotlin does) so that Int64.min parses.
        var value: Int64 = 0
        while i < units.count {
            let u = units[i]
            guard u >= 0x30 && u <= 0x39 else { return nil }
            let (m, o1) = value.multipliedReportingOverflow(by: 10)
            let (n, o2) = m.subtractingReportingOverflow(Int64(u - 0x30))
            if o1 || o2 { return nil }
            value = n
            i += 1
        }
        if negative { return value }
        let (p, o) = Int64(0).subtractingReportingOverflow(value)
        return o ? nil : p
    }

    /// Kotlin `Char.isWhitespace` (= Java `isWhitespace || isSpaceChar`): U+0009–U+000D, U+001C–U+001F, Zs (U+0020,
    /// U+00A0, U+1680, U+2000–U+200A, U+202F, U+205F, U+3000), U+2028, U+2029. Not U+0085 (R4 §3).
    static func isKotlinWhitespace(_ u: UInt16) -> Bool {
        switch u {
        case 0x09...0x0D, 0x1C...0x1F, 0x20, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000:
            return true
        default:
            return false
        }
    }

    /// Kotlin `trimStart()` (leading `isKotlinWhitespace` UTF-16 units removed).
    static func trimStart(_ s: String) -> String {
        let units = Array(s.utf16)
        var i = 0
        while i < units.count && isKotlinWhitespace(units[i]) { i += 1 }
        if i == 0 { return s }
        return String(decoding: units[i...], as: UTF16.self)
    }

    /// Kotlin `Regex.matchEntire` / `matches`: an anchored match covering the whole string (UTF-16 range).
    static func wholeMatch(_ re: NSRegularExpression, _ s: String) -> NSTextCheckingResult? {
        let full = NSRange(location: 0, length: s.utf16.count)
        guard let m = re.firstMatch(in: s, options: [.anchored], range: full),
              m.range.location == 0, m.range.length == full.length else { return nil }
        return m
    }

    /// Substring of `s` at an NSRange of a match (UTF-16 offsets); "" for a group that did not take part.
    static func group(_ m: NSTextCheckingResult, _ i: Int, in s: String) -> String {
        let r = m.range(at: i)
        guard r.location != NSNotFound else { return "" }
        let units = Array(s.utf16)
        return String(decoding: units[r.location..<(r.location + r.length)], as: UTF16.self)
    }
}
