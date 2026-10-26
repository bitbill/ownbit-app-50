//  BILPublicIndexVerifier.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Public protocol (cold signer): the cross-check of a public index against Ownbit's own keys (spec §4.5, R2 §6; port of
//  Android core/publicsigner index/PublicIndexVerifier.kt). It compares what the engine derives from the index
//  (`derivePublicAddresses`, the derivation `createPublicPairing` uses) with what Ownbit's existing, independent bridges
//  derive from the wallet's stored keys (BILOwnbitAddressDeriving), and the index's own caches:
//
//    key                       engine                         Ownbit
//    bitcoin:legacy (anchor)   m/44'/0'/0'/0/0                BitcoinJSBridge.getAddresses(mainExtPublicKey)
//    bitcoin:nested / native   m/49'/… / m/84'/0'/0'/0/0      getAddresses_sw_p / _sw_d (stored xpub; missing → false)
//    bitcoin:taproot           m/86'/0'/0'/0/0                BTCTaprootJSBridge (hot wallets with Taproot keys only)
//    evm:0 (+ evm:N) (anchor)  m/44'/60'/0'/0/n               EthereumJSBridge(extPubKey, n) + the stored active address
//    tron:0 (anchor)           m/44'/195'/0'/0/0              trxAddress0, else address while TRX index is 0 (D-10)
//    tron:N (Ownbit scheme)    m/44'/60'/0'/0/N               the stored active TRX address
//    solana:standard           m/44'/501'/0'/0'               the stored SOL address (missing → false, no engine call)
//
//  Chains run in the order bitcoin, evm, tron, solana; the first that disagrees is the mismatch. Engine answers of the
//  wrong shape / path throw BILMalformedEngineResult; engine and bridge failures propagate (callers treat both as engine
//  failures, never as a mismatch). Independence rule: engine output is never fed into an Ownbit bridge. Nothing is logged
//  but the chain of a mismatch. Pure (engine contract + deriver protocol injected).
//

import Foundation

/// One check key and whether it ran and agreed (`false` = Ownbit holds nothing to compare with).
public struct BILPublicVerifyMatch: Equatable {
    public let key: String
    public let confirmed: Bool
}

/// Every comparison that could run agreed. `matches` in check order; `ownbitAddresses` = the agreed address per confirmed
/// key (the engine's spelling; EVM in EIP-55). The description never prints addresses (C-KEY-5).
public struct BILPublicVerifyMatches: Equatable, CustomStringConvertible {
    public let matches: [BILPublicVerifyMatch]
    public let ownbitAddresses: [String: String]

    /// The check `key` ran and agreed.
    public func confirmed(_ key: String) -> Bool {
        return matches.contains { BILJSONExact.equal($0.key, key) && $0.confirmed }
    }

    public var description: String {
        return "BILPublicVerifyMatches(" + matches.map { $0.key + "=" + ($0.confirmed ? "true" : "false") }.joined(separator: ",") + ")"
    }
}

public enum BILPublicVerifyResult: Equatable {
    case ok(BILPublicVerifyMatches)
    /// The engine and Ownbit disagree on the chain, or Ownbit's anchor of the chain is missing: store nothing, show no QR.
    case mismatch(BILPsChain)
}

/// Ownbit's existing address derivations over its stored keys (live: BILOwnbitAddressDeriver with 15 s timeouts).
/// Each returns the first receive address (`/0/0`, or ETH #`index`) or throws (never a guess).
@MainActor public protocol BILOwnbitAddressDeriving: AnyObject {
    func btcLegacy(xpub: String) async throws -> String
    func btcNested(xpub: String) async throws -> String
    func btcNative(xpub: String) async throws -> String
    func btcTaproot(xpub: String) async throws -> String
    func ethAddress(xpub: String, index: Int) async throws -> String
}

/// An Ownbit bridge did not answer (timeout), answered something unusable, or was given a key it must not receive.
/// The repository / pairing treat it as an engine-class failure, not as a key mismatch (R2 §6.2). Codes only.
public struct BILOwnbitAddressDeriveError: Error, Equatable, CustomStringConvertible {
    public let code: String
    public static let timeout = BILOwnbitAddressDeriveError(code: "BRIDGE_TIMEOUT")
    public static let badResult = BILOwnbitAddressDeriveError(code: "BRIDGE_RESULT")
    public static let bridgeFailed = BILOwnbitAddressDeriveError(code: "BRIDGE_FAILED")
    public static let badKey = BILOwnbitAddressDeriveError(code: "BRIDGE_KEY")

    public var description: String {
        return "BILOwnbitAddressDeriveError(" + code + ")"
    }
}

@MainActor public final class BILPublicIndexVerifier {

    private static let evmOrigin = "m/44'/60'/0'", tronOrigin = "m/44'/195'/0'", ownbitTronScheme = "ownbit"

    /// Bitcoin profiles Ownbit holds keys for, anchor (legacy) first (Android `BITCOIN_CHECKED`).
    private static let bitcoinChecked: [BILPsBitcoinProfile] = [.legacy, .nested, .native, .taproot]

    private let engine: BILPublicSignerEngining
    private let deriver: BILOwnbitAddressDeriving

    public init(engine: BILPublicSignerEngining, deriver: BILOwnbitAddressDeriving) {
        self.engine = engine
        self.deriver = deriver
    }

    /// Compares `index` (the device's own public index of `facts.walletId`) with the wallet's stored keys for `chains`.
    public func verify(index: BILJSONObject, facts: BILPublicWalletFacts, chains: Set<BILPsChain>) async throws -> BILPublicVerifyResult {
        var matches: [BILPublicVerifyMatch] = []
        var addresses: [String: String] = [:]
        for chain in BILPsChain.allCases where chains.contains(chain) {
            let agreed: Bool
            switch chain {
            case .bitcoin:
                agreed = try await verifyBitcoin(index, facts, &matches, &addresses)
            case .evm:
                agreed = try await verifyEvm(index, facts, &matches, &addresses)
            case .tron:
                agreed = try await verifyTron(index, facts, &matches, &addresses)
            case .solana:
                agreed = try await verifySolana(index, facts, &matches, &addresses)
            }
            if !agreed {
                BILPublicIndexVerifier.logMismatch(chain)
                return .mismatch(chain)
            }
        }
        return .ok(BILPublicVerifyMatches(matches: matches, ownbitAddresses: addresses))
    }

    /// The engine's address `start` of `chain` / `profile` (`derivePublicAddresses`, count 1), at exactly `expectedPath`.
    public func engineAddress(index: BILJSONObject, chain: BILPsChain, profile: String?, start: Int, expectedPath: String) async throws -> String {
        let result = try await engine.derivePublicAddresses(publicIndex: index, chain: chain.rawValue, profile: profile, start: start, count: 1)
        guard let first = result.arr("addresses")?.first?.objectValue else {
            throw BILMalformedEngineResult(what: "addresses." + chain.rawValue)
        }
        try BILEngineJSON.ensure(BILPublicIndexVerifier.same(first.str("path"), expectedPath) && first.int("index") == start
                                    && BILPublicIndexVerifier.same(first.str("chain"), chain.rawValue),
                                 "addresses." + chain.rawValue + ".path")
        guard let address = first.str("address"), !address.isEmpty else {
            throw BILMalformedEngineResult(what: "addresses." + chain.rawValue + ".address")
        }
        return address
    }

    // MARK: - Chains (Android verifyBitcoin / verifyEvm / verifyTron / verifySolana)

    private func verifyBitcoin(_ index: BILJSONObject, _ facts: BILPublicWalletFacts,
                               _ matches: inout [BILPublicVerifyMatch], _ addresses: inout [String: String]) async throws -> Bool {
        for profile in BILPublicIndexVerifier.bitcoinChecked {
            let key = BILPairingExportPolicy.bitcoinKey(profile)
            let stored: String?
            switch profile {
            case .legacy: stored = facts.legacyXpub
            case .nested: stored = facts.nestedXpub
            case .native: stored = facts.nativeXpub
            default: stored = facts.taprootXpub
            }
            guard let xpub = BILPublicWalletFacts.nonBlank(stored) else {
                if profile == .legacy { return false }          // anchor
                matches.append(BILPublicVerifyMatch(key: key, confirmed: false))
                continue
            }
            let ownbit: String
            switch profile {
            case .legacy: ownbit = try await deriver.btcLegacy(xpub: xpub)
            case .nested: ownbit = try await deriver.btcNested(xpub: xpub)
            case .native: ownbit = try await deriver.btcNative(xpub: xpub)
            default: ownbit = try await deriver.btcTaproot(xpub: xpub)
            }
            guard let path = profile.firstAddressPath else { throw BILMalformedEngineResult(what: "bitcoin.profile") }
            let derived = try await engineAddress(index: index, chain: .bitcoin, profile: profile.rawValue, start: 0, expectedPath: path)
            if !BILPublicIndexVerifier.same(derived, ownbit) { return false }
            matches.append(BILPublicVerifyMatch(key: key, confirmed: true))
            addresses[key] = derived
        }
        return true
    }

    private func verifyEvm(_ index: BILJSONObject, _ facts: BILPublicWalletFacts,
                           _ matches: inout [BILPublicVerifyMatch], _ addresses: inout [String: String]) async throws -> Bool {
        guard let xpub = BILPublicWalletFacts.nonBlank(facts.ethXpub) else { return false }      // anchor
        let current = max(0, facts.ethIndex)
        let checked = current > 0 ? [0, current] : [0]
        let stored = BILPublicWalletFacts.nonBlank(facts.ethAddress)
        for n in checked {
            let derived = try await engineAddress(index: index, chain: .evm, profile: nil, start: n,
                                                  expectedPath: BILPublicIndexVerifier.evmOrigin + "/0/" + String(n))
            let ownbit = try await deriver.ethAddress(xpub: xpub, index: n)
            if !BILPublicIndexVerifier.sameIgnoringASCIICase(derived, ownbit) { return false }
            // The stored active address is what Ownbit shows for #current.
            if n == current, let s = stored, !BILPublicIndexVerifier.sameIgnoringASCIICase(derived, s) { return false }
            let key = BILPairingExportPolicy.evmKey(n)
            matches.append(BILPublicVerifyMatch(key: key, confirmed: true))
            addresses[key] = derived
        }
        let cached = index.obj("evmDefaultAddress")?.str("address")
        guard let evm0 = addresses[BILPairingExportPolicy.evmKey(0)] else { return false }
        return cached == nil || BILPublicIndexVerifier.sameIgnoringASCIICase(cached ?? "", evm0)
    }

    private func verifyTron(_ index: BILJSONObject, _ facts: BILPublicWalletFacts,
                            _ matches: inout [BILPublicVerifyMatch], _ addresses: inout [String: String]) async throws -> Bool {
        // D-10 (Android order): trxAddress0 if set, else the active address while Ownbit is on TRX #0, else fail closed.
        let ownbit: String
        if let a0 = BILPublicWalletFacts.nonBlank(facts.trxAddress0) {
            ownbit = a0
        } else if let a = BILPublicWalletFacts.nonBlank(facts.trxAddress), facts.trxIndex == 0 {
            ownbit = a
        } else {
            return false
        }
        let derived = try await engineAddress(index: index, chain: .tron, profile: nil, start: 0,
                                              expectedPath: BILPublicIndexVerifier.tronOrigin + "/0/0")
        if !BILPublicIndexVerifier.same(derived, ownbit) { return false }
        let cache = index.arr("tronAddressIndex")
        if let cached = cache?.first?.objectValue?.str("address"), !BILPublicIndexVerifier.same(cached, derived) { return false }
        let key0 = BILPairingExportPolicy.tronKey(0)
        matches.append(BILPublicVerifyMatch(key: key0, confirmed: true))
        addresses[key0] = derived
        // Ownbit's scheme: the current TRX #N (> 0) is the ETH key #N in TRON encoding, the active stored address.
        let current = max(0, facts.trxIndex)
        if BILPublicIndexVerifier.same(index.str("tronScheme"), BILPublicIndexVerifier.ownbitTronScheme) && current > 0 {
            guard let stored = BILPublicWalletFacts.nonBlank(facts.trxAddress) else { return false }
            let derivedN = try await engineAddress(index: index, chain: .tron, profile: nil, start: current,
                                                   expectedPath: BILPublicIndexVerifier.evmOrigin + "/0/" + String(current))
            if !BILPublicIndexVerifier.same(derivedN, stored) { return false }
            if let all = cache, current < all.count,
               let cachedN = all[current].objectValue?.str("address"), !BILPublicIndexVerifier.same(cachedN, derivedN) {
                return false
            }
            let keyN = BILPairingExportPolicy.tronKey(current)
            matches.append(BILPublicVerifyMatch(key: keyN, confirmed: true))
            addresses[keyN] = derivedN
        }
        return true
    }

    private func verifySolana(_ index: BILJSONObject, _ facts: BILPublicWalletFacts,
                              _ matches: inout [BILPublicVerifyMatch], _ addresses: inout [String: String]) async throws -> Bool {
        let key = BILPairingExportPolicy.solanaStandardKey
        guard let stored = BILPublicWalletFacts.nonBlank(facts.solAddress) else {
            // SOL may be missing at creation: nothing to compare, nothing marked as Ownbit's, no engine call.
            matches.append(BILPublicVerifyMatch(key: key, confirmed: false))
            return true
        }
        let standard = BILPsSolanaProfile.standard
        let derived = try await engineAddress(index: index, chain: .solana, profile: standard.rawValue, start: 0, expectedPath: standard.path)
        if !BILPublicIndexVerifier.same(derived, stored) { return false }
        matches.append(BILPublicVerifyMatch(key: key, confirmed: true))
        addresses[key] = derived
        return true
    }

    // MARK: - Helpers

    /// Exact (code-unit) equality, as Kotlin `==` on strings.
    private static func same(_ a: String?, _ b: String?) -> Bool {
        guard let a = a, let b = b else { return a == nil && b == nil }
        return BILJSONExact.equal(a, b)
    }

    /// Kotlin `equals(ignoreCase = true)` for addresses: equal UTF-16 lengths and equal units after ASCII case folding
    /// (non-ASCII letters are compared exactly: stricter than Kotlin's Unicode folding, fails closed).
    private static func sameIgnoringASCIICase(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf16), y = Array(b.utf16)
        guard x.count == y.count else { return false }
        for (p, q) in zip(x, y) where p != q {
            let fp = (p >= 0x41 && p <= 0x5A) ? p + 0x20 : p
            let fq = (q >= 0x41 && q <= 0x5A) ? q + 0x20 : q
            if fp != fq { return false }
        }
        return true
    }

    private static func logMismatch(_ chain: BILPsChain) {
        switch chain {
        case .bitcoin: BILPublicLog.code("index", "KEYS_MISMATCH_BITCOIN")
        case .evm: BILPublicLog.code("index", "KEYS_MISMATCH_EVM")
        case .tron: BILPublicLog.code("index", "KEYS_MISMATCH_TRON")
        case .solana: BILPublicLog.code("index", "KEYS_MISMATCH_SOLANA")
        }
    }
}
