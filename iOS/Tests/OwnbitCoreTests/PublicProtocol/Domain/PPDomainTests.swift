//  PPDomainTests.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Port of the app harness suite `scripts/public-protocol/tests/domain` (main.swift) to XCTest.
//
//  Domain suite (WP5): BILPublicProtocolModels, BILPublicIndexTypes, BILPairingExportPolicy, BILCompatibleWallets,
//  BILPublicProtocolLinks, BILPublicEngineVocabulary, BILPublicFeeText — the real app sources compiled with this file.
//  Ports of Android PST:pairing/{PairingExportPolicyTest,CompatibleWalletsListTest}.kt, ui/CompatibleWalletsTest.kt (no-logo
//  part), links/{PublicProtocolLinksTest,PublicProtocolLinksL10nTest}.kt, text/{EngineVocabularyTest,PublicFeeTextTest}.kt,
//  plus design R2 §12 item 5, R3 §6.9 / §7.1 / §7.4 / §10.1, R5 §6 / §8, D-14.
//  Self-contained in Wave 1 (no tests/support): own tiny test kit. JSONSerialization is fine here (test code, not PP).
//  Inputs (paths from run.sh, environment):
//   PUB_VOCABULARY  engine_vocabulary.json        PUB_VECTORS  vectors.json (golden engine vectors)
//   PUB_STRINGS     public_protocol_strings.json  PUB_H5_EN    _pairing_protocols_en.html
//   PUB_COINTYPE    iOS Modules/Receive/Model/BILRecieveModel.swift (CoinType raw values)
//   PUB_ASSETS      iOS Assets.xcassets (one wallet_<id>.imageset per compatible wallet)
//

import Foundation
import XCTest
@testable import OwnbitCore

/// The suite namespace (harness helpers are its static members).
enum PPDomainSuite: PPSuite {}

final class PPDomainTests: XCTestCase {
    func testDomain() throws {
        try ppRunSuite("domain") { try PPDomainSuite.run() }
    }
}

extension PPDomainSuite {

    // MARK: - Test kit

    // (The harness's own `t` / `eq` / counters are PPSuite's.)

    /// Exact (UTF-8 byte) string equality.
    static func same(_ a: String?, _ b: String?) -> Bool {
        guard let a = a, let b = b else { return a == nil && b == nil }
        return Array(a.utf8) == Array(b.utf8)
    }

    /// The harness's raw result line; run.sh adds the iOS typecheck and the fee-app run and prints the suite line
    /// A fatal input problem (a fixture that does not read): stops the suite.
    static func fatal(_ message: String) -> Never {
        fatalError("domain: " + message)
    }

    static func env(_ name: String) -> String {
        guard let v = ProcessInfo.processInfo.environment[name], !v.isEmpty else {
            fatal("missing environment \(name)")
        }
        return v
    }

    static func loadJSON(_ path: String) -> Any {
        guard let data = FileManager.default.contents(atPath: path),
              let json = try? JSONSerialization.jsonObject(with: data, options: []) else {
            fatal("cannot read JSON \(path)")
        }
        return json
    }

    static func throwsError(_ body: () throws -> Void) -> Bool {
        do { try body(); return false } catch { return true }
    }

    /// Whole-string match like Kotlin `Regex.matches` for a pattern written with a final `$`.
    static func kotlinMatches(_ pattern: String, _ text: String) -> Bool {
        var p = pattern
        if p.hasSuffix("$") { p.removeLast(); p += "\\z" }
        guard let re = try? NSRegularExpression(pattern: p, options: []) else { return false }
        let full = NSRange(location: 0, length: text.utf16.count)
        guard let m = re.firstMatch(in: text, options: [.anchored], range: full) else { return false }
        return m.range.location == 0 && m.range.length == full.length
    }

    /// Distinct Android placeholders `%N$s` / `%N$d` of a string (Android test `placeholders(res)`).
    static func androidPlaceholders(_ s: String) -> Int {
        guard let re = try? NSRegularExpression(pattern: "%(\\d)\\$[sd]", options: []) else { return -1 }
        let ns = s as NSString
        let found = re.matches(in: s, options: [], range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
        return Set(found).count
    }

    /// Vocabulary-style placeholders `%N$s` (Kotlin `Regex("%(\\d)\\$s").findAll(text).count()`).
    static func vocabularyPlaceholders(_ s: String) -> Int {
        guard let re = try? NSRegularExpression(pattern: "%(\\d)\\$s", options: []) else { return -1 }
        return re.numberOfMatches(in: s, options: [], range: NSRange(location: 0, length: s.utf16.count))
    }

    // MARK: - Inputs

    static func object<T>(_ value: Any?, _ type: T.Type, _ what: String) -> T {
        guard let v = value as? T else { fatal("\(what) has an unexpected shape") }
        return v
    }
    static let vocabulary = object(loadJSON(fixtureURL("engine_vocabulary.json").path), [String: Any].self, "engine_vocabulary.json")
    /// The harness also read the app's strings JSON (`PUB_STRINGS`), the bundled H5 guide, the app's CoinType source and
    /// asset catalog; the package has none of them (no UI, no strings), so their checks are not ported.
    static let strings: [String: [String: Any]] = [:]
    static let vectors = object(loadJSON(fixtureURL("vectors.json").path), [String: Any].self, "vectors.json")
    static func english(_ key: String) -> String? {
        return strings[key]?["en"] as? String
    }
    /// The harness checked that `key` exists in the app's strings JSON with `placeholders` placeholders; no strings here.
    static func checkKey(_ key: String, placeholders: Int, _ context: String, line: UInt = #line) {}
    static func everySelection() -> [BILPairingSelection] {
        var out: [BILPairingSelection] = []
        for p in BILPsBitcoinProfile.allCases {
            for m in BILPairingSelection.modes(for: .bitcoin, bitcoinProfile: p) {
                out.append(BILPairingSelection(chain: .bitcoin, bitcoinProfile: p, outputMode: m)!)
            }
        }
        for m in BILPairingSelection.modes(for: .evm, bitcoinProfile: .native) {
            out.append(BILPairingSelection(chain: .evm, outputMode: m)!)
        }
        out.append(BILPairingSelection(chain: .tron)!)
        for p in BILPsSolanaProfile.allCases {
            for m in BILPairingSelection.modes(for: .solana, bitcoinProfile: .native) {
                out.append(BILPairingSelection(chain: .solana, solanaProfile: p, outputMode: m)!)
            }
        }
        return out
    }
    static func sel(_ chain: BILPsChain, _ btc: BILPsBitcoinProfile = .native, _ sol: BILPsSolanaProfile = .standard,
             _ mode: BILPsOutputMode? = nil) -> BILPairingSelection {
        return BILPairingSelection(chain: chain, bitcoinProfile: btc, solanaProfile: sol, outputMode: mode)!
    }
    static func plan(_ s: BILPairingSelection, _ f: BILWalletPairingFacts, tron: Int = 0) -> BILExportPlan {
        do {
            return try BILPairingExportPolicy.plan(s, facts: f, tronIndex: tron)
        } catch {
            t(false, "unexpected throw for \(s) tron \(tron)")
            return BILExportPlan(selection: s, call: .evmAddressAt(index: -1), addressIndex: -1, ownbitCheck: nil,
                                 requireOwnbitMatch: false, shownInOwnbit: false, notes: [], evmAccountN: -1, tronCurrentN: -1)
        }
    }

    /// The harness main.swift (nonisolated top-level code, as in the harness).
    static func run() throws {
        /// The English text of a `PublicProtocol.*` key of the strings JSON (nil = key missing).

        /// The key exists in the strings JSON and its English text has `placeholders` distinct placeholders.

        /// Every selection the engine accepts (Android `PairingExportPolicyTest.every()`).

        // MARK: - A. Models (PsChain / PsProfiles / PairingSelection)

        do {
            eq(BILPsChain.allCases, [.bitcoin, .evm, .tron, .solana], "chain picker order")
            eq(BILPsChain.allCases.map { $0.rawValue }, ["bitcoin", "evm", "tron", "solana"], "chain wires")
            eq(BILPsChain.allCases.map { $0.brandName }, ["Bitcoin", "EVM", "TRON", "Solana"], "brand names")
            eq(BILPsChain.fromWire("tron"), .tron, "fromWire tron")
            eq(BILPsChain.fromWire(nil), nil, "fromWire nil")
            for bad in ["Bitcoin", "bitcoin ", "", "btc", "TRON", "solana\n"] { eq(BILPsChain.fromWire(bad), nil, "fromWire \(bad.debugDescription)") }

            eq(BILPsBitcoinProfile.allCases, [.taproot, .native, .nested, .legacy, .multisigNative, .multisigNested], "profile order")
            eq(BILPsBitcoinProfile.allCases.map { $0.rawValue },
               ["taproot", "native", "nested", "legacy", "multisig-native", "multisig-nested"], "profile wires")
            eq(BILPsBitcoinProfile.allCases.map { $0.accountPath },
               ["m/86'/0'/0'", "m/84'/0'/0'", "m/49'/0'/0'", "m/44'/0'/0'", "m/48'/0'/0'/2'", "m/48'/0'/0'/1'"], "account paths")
            eq(BILPsBitcoinProfile.allCases.map { $0.firstAddressPath },
               ["m/86'/0'/0'/0/0", "m/84'/0'/0'/0/0", "m/49'/0'/0'/0/0", "m/44'/0'/0'/0/0", nil, nil], "first address paths")
            eq(BILPsBitcoinProfile.allCases.map { $0.isMultisig }, [false, false, false, false, true, true], "isMultisig")
            eq(BILPsBitcoinProfile.singleSig, [.taproot, .native, .nested, .legacy], "single-sig segment = Ownbit order")
            eq(BILPsBitcoinProfile.multisig, [.multisigNative, .multisigNested], "multisig segment")
            eq(BILPsBitcoinProfile.allCases.map { $0.titleKey },
               ["PublicProtocol.pair.profile.taproot", "PublicProtocol.pair.profile.native", "PublicProtocol.pair.profile.nested",
                "PublicProtocol.pair.profile.legacy", "PublicProtocol.pair.profile.msNative", "PublicProtocol.pair.profile.msNested"],
               "profile title keys")
            t(same(BILPsBitcoinProfile.taproot.detail, "BIP86 \u{00B7} bc1p\u{2026}"), "taproot detail")
            eq(BILPsBitcoinProfile.allCases.map { $0.detail },
               ["BIP86 · bc1p…", "BIP84 · bc1q…", "BIP49 · 3…", "BIP44 · 1…", "BIP48 · P2WSH", "BIP48 · P2SH-P2WSH"], "profile details")
            for p in BILPsBitcoinProfile.allCases { checkKey(p.titleKey, placeholders: 0, "profile \(p)") }

            eq(BILPsSolanaProfile.allCases, [.standard, .trust, .legacy], "solana order")
            eq(BILPsSolanaProfile.allCases.map { $0.path }, ["m/44'/501'/0'/0'", "m/44'/501'/0'", "m/44'/501'"], "solana paths")
            eq(BILPsSolanaProfile.allCases.map { $0.matchesOwnbit }, [true, false, false], "solana matchesOwnbit")
            eq(BILPsSolanaProfile.allCases.filter { $0.isMorePath }, [.trust, .legacy], "solana More paths")
            for p in BILPsSolanaProfile.allCases { checkKey(p.titleKey, placeholders: 0, "solana \(p)") }
            checkKey("PublicProtocol.pair.morePaths", placeholders: 0, "more paths heading")

            eq([BILPsOutputMode.accountXpub, .wallet, .address].map { $0.rawValue }, ["accountXpub", "wallet", "address"], "mode wires")
            eq([BILPsOutputMode.accountXpub, .wallet, .address].map { $0.bearsKey }, [true, true, false], "bearsKey")
            for m in [BILPsOutputMode.accountXpub, .wallet, .address] { checkKey(m.titleKey, placeholders: 0, "mode \(m)") }

            let d = BILPairingSelection.default
            eq(d.chain, .bitcoin, "default chain")
            eq(d.bitcoinProfile, .native, "default BTC profile")
            eq(d.outputMode, .accountXpub, "default mode")
            eq(d.profileWire, "native", "default profileWire")
            t(d.bearsKey, "default bears a key")
            eq(sel(.evm).outputMode, .wallet, "EVM default mode")
            eq(sel(.tron).outputMode, .address, "TRON default mode")
            eq(sel(.solana).solanaProfile, .standard, "SOL default profile")
            eq(sel(.solana).outputMode, .wallet, "SOL default mode")
            eq(sel(.bitcoin, .multisigNested).outputMode, .accountXpub, "BIP48 default mode")

            eq(BILPairingSelection.modes(for: .bitcoin, bitcoinProfile: .taproot), [.accountXpub, .address], "BTC single modes")
            eq(BILPairingSelection.modes(for: .bitcoin, bitcoinProfile: .multisigNative), [.accountXpub], "BTC multisig modes")
            eq(BILPairingSelection.modes(for: .evm, bitcoinProfile: .multisigNative), [.wallet, .address], "EVM modes")
            eq(BILPairingSelection.modes(for: .solana, bitcoinProfile: .native), [.wallet, .address], "SOL modes")
            eq(BILPairingSelection.modes(for: .tron, bitcoinProfile: .native), [.address], "TRON modes")
            t(BILPairingSelection(chain: .tron, outputMode: .wallet) == nil, "TRON wallet refused")
            t(BILPairingSelection(chain: .tron, outputMode: .accountXpub) == nil, "TRON xpub refused")
            t(BILPairingSelection(chain: .bitcoin, bitcoinProfile: .multisigNative, outputMode: .address) == nil, "BIP48 address refused")
            t(BILPairingSelection(chain: .bitcoin, outputMode: .wallet) == nil, "BTC wallet refused")
            t(BILPairingSelection(chain: .evm, outputMode: .accountXpub) == nil, "EVM xpub refused")
            t(BILPairingSelection(chain: .solana, outputMode: .accountXpub) == nil, "SOL xpub refused")

            // with…: keep the mode if allowed, else the chain's / profile's default; profiles survive chain switches.
            let btcAddress = d.with(outputMode: .address)
            eq(btcAddress.outputMode, .address, "BTC address mode")
            let ms = btcAddress.with(bitcoinProfile: .multisigNative)
            eq(ms.outputMode, .accountXpub, "multisig falls back to account XPUB")
            eq(ms.with(bitcoinProfile: .native).outputMode, .accountXpub, "back to single-sig keeps account XPUB")
            eq(btcAddress.with(bitcoinProfile: .legacy).outputMode, .address, "single-sig profile keeps address mode")
            let evmAddress = sel(.evm).with(outputMode: .address)
            eq(evmAddress.with(chain: .tron).outputMode, .address, "EVM address → TRON address")
            eq(sel(.evm).with(chain: .tron).outputMode, .address, "EVM wallet → TRON address (default)")
            eq(sel(.evm).with(chain: .tron).with(chain: .evm).outputMode, .address, "TRON → EVM keeps the allowed address mode")
            eq(sel(.tron).with(outputMode: .wallet), sel(.tron), "disallowed mode ignored")
            eq(sel(.solana).with(solanaProfile: .trust).with(outputMode: .address).with(solanaProfile: .legacy).outputMode, .address,
               "SOL profile switch keeps mode")
            let legacyKept = d.with(bitcoinProfile: .legacy).with(chain: .evm).with(chain: .solana).with(chain: .bitcoin)
            eq(legacyKept.bitcoinProfile, .legacy, "BTC profile kept across chains")
            eq(legacyKept.outputMode, .accountXpub, "BTC → EVM wallet → SOL wallet → BTC: account XPUB again")
            eq(d.with(chain: .evm).with(chain: .bitcoin).outputMode, .accountXpub, "EVM wallet → BTC account XPUB (default)")
            eq(sel(.solana, .native, .trust).with(chain: .evm).with(chain: .solana).solanaProfile, .trust, "SOL profile kept across chains")
            eq(sel(.evm).profileWire, nil, "EVM profileWire")
            eq(sel(.tron).profileWire, nil, "TRON profileWire")
            eq(sel(.solana, .native, .legacy).profileWire, "legacy", "SOL profileWire")
            eq(sel(.bitcoin, .multisigNested).profileWire, "multisig-nested", "BIP48 profileWire")
            eq(Set(everySelection() + everySelection()).count, everySelection().count, "Hashable selections")
            eq(everySelection().count, 19, "every selection count (BTC 10, EVM 2, TRON 1, SOL 6)")
            for s in everySelection() { t(s.availableModes.contains(s.outputMode), "\(s) mode allowed") }
        }

        // (B. Public coin ids vs the app's CoinType source: not ported, app code.)

        // MARK: - C. Index types

        do {
            let cases: [(BILPublicPrepareResult, String?)] = [
                (.ready(fingerprint: "73C5DA0A"), nil),
                (.notEligible, "PublicProtocol.err.noWallet"),
                (.keysMismatch(.evm), "PublicProtocol.pair.keysMismatch"),
                (.failed(.seedMismatch, engineCode: nil), "PublicProtocol.pair.keysMismatch"),
                (.failed(.engine, engineCode: "SEED"), "PublicProtocol.err.engineUnavailable"),
                (.failed(.engineUnavailable, engineCode: nil), "PublicProtocol.err.engineUnavailable"),
                (.failed(.storage, engineCode: nil), "PublicProtocol.err.rebuildPublicData"),
                (.failed(.noSecret, engineCode: nil), "PublicProtocol.err.rebuildPublicData"),
            ]
            for (r, key) in cases {
                eq(r.messageKey, key, "messageKey \(r)")
                if let key = key { checkKey(key, placeholders: 0, "prepare \(r)") }
            }
            t(BILPublicPrepareResult.failed(.engine, engineCode: "X") != .failed(.engine, engineCode: nil), "engine code compared")
            t(BILPublicIndexStatus.ready(fingerprint: "A") != .ready(fingerprint: "B"), "status fingerprint compared")
            t(BILPublicIndexStatus.temporarilyUnreadable != .needsRepair, "temporarilyUnreadable is its own state")
            eq(BILPublicWalletKind.normal.rawValue, 0, "kind normal raw")
            eq(BILPublicWalletKind.cold.rawValue, 1, "kind cold raw")
        }

        // MARK: - D. Export policy (PairingExportPolicyTest + R2 §12 item 5 + R3 §6.9)

        do {
            let cold = BILWalletPairingFacts(kind: .cold, btcProfilesInUse: [.legacy, .native], hasSolanaAddress: true)
            func coldWith(evm: Int = 0, tron: Int = 0, inUse: Set<BILPsBitcoinProfile>? = nil, sol: Bool = true) -> BILWalletPairingFacts {
                return BILWalletPairingFacts(kind: .cold, btcProfilesInUse: inUse ?? [.legacy, .native], hasTaprootKeys: false,
                                             evmIndex: evm, tronIndex: tron, hasSolanaAddress: sol)
            }

            // TRON exports the stepper's #N in Ownbit's scheme, checked against Ownbit's TRX #N.
            for trx in [0, 1, 7, 150] {
                for n in [0, 1, 7, 99] {
                    let p = plan(sel(.tron), coldWith(tron: trx), tron: n)
                    eq(p.call, .enginePairing(chain: .tron, profile: nil, mode: .address, index: n), "TRON call trx=\(trx) n=\(n)")
                    eq(p.addressIndex, n, "TRON addressIndex")
                    eq(p.ownbitCheck, "tron:\(n)", "TRON check key")
                    eq(p.ownbitCheck, BILPairingExportPolicy.tronKey(n), "tronKey")
                    t(p.requireOwnbitMatch && p.shownInOwnbit, "TRON require + shown")
                    var expected: [BILPairingNote] = [.addressOnly, n == 0 ? .tronIndex0 : .tronIndexN]
                    if n != trx { expected.append(.tronCurrentN) }
                    eq(p.notes, expected, "TRON notes trx=\(trx) n=\(n)")
                    eq(p.tronCurrentN, trx, "tronCurrentN")
                }
            }
            let fresh = plan(sel(.tron), coldWith(tron: 0), tron: 5)
            eq(fresh.notes, [.addressOnly, .tronIndexN, .tronCurrentN], "fresh wallet #5 notes")
            eq(fresh.tronCurrentN, 0, "fresh tronCurrentN")
            eq(BILPairingExportPolicy.tronDefaultIndex, 0, "TRON default index")
            eq(BILPairingExportPolicy.tronStepperMax, 99, "TRON stepper max")
            eq(plan(sel(.tron), cold, tron: BILPairingExportPolicy.tronDefaultIndex).addressIndex, 0, "default request #0")

            // Stepper range.
            eq(BILPairingExportPolicy.maxTronIndex(nil), 99, "maxTronIndex(nil)")
            eq(BILPairingExportPolicy.maxTronIndex(coldWith(tron: 7)), 99, "maxTronIndex(7)")
            eq(BILPairingExportPolicy.maxTronIndex(coldWith(tron: 150)), 150, "maxTronIndex(150)")
            eq(plan(sel(.tron), coldWith(tron: 150), tron: 150).addressIndex, 150, "TRON #150 with Ownbit #150")
            for (trx, n) in [(0, 100), (0, -1), (150, 151), (7, 1000)] {
                var thrown: Error?
                do { _ = try BILPairingExportPolicy.plan(sel(.tron), facts: coldWith(tron: trx), tronIndex: n) } catch { thrown = error }
                eq(thrown as? BILPairingExportPolicyError, .tronIndexOutOfRange, "TRON n=\(n) trx=\(trx) out of range")
            }
            // The TRON index is ignored (and never thrown on) by the other chains.
            t(!throwsError { _ = try BILPairingExportPolicy.plan(sel(.evm), facts: cold, tronIndex: 5000) }, "EVM ignores the TRON index")

            // No selection but TRON ever asks the engine for an address index other than 0.
            for evm in [0, 3, 999] {
                for trx in [0, 5] {
                    for s in everySelection() {
                        let p = plan(s, coldWith(evm: evm, tron: trx), tron: 5)
                        switch p.call {
                        case let .enginePairing(chain, _, mode, index):
                            eq(index, s.chain == .tron ? 5 : 0, "engine index \(s)")
                            eq(chain, s.chain, "engine chain \(s)")
                            eq(mode, s.outputMode, "engine mode \(s)")
                        case let .evmAddressAt(index):
                            t(s.chain == .evm && s.outputMode == .address, "evmAddressAt only for EVM address (\(s))")
                            eq(index, evm, "EVM address #N")
                        }
                        eq(p.selection, s, "plan selection")
                        if s.chain == .tron { eq(p.addressIndex, 5, "TRON addressIndex 5") }
                        if s.chain != .evm && s.chain != .tron { eq(p.addressIndex, 0, "addressIndex 0 for \(s)") }
                    }
                }
            }

            // EVM address mode exports Ownbit's current address #N.
            let evm7 = plan(sel(.evm, .native, .standard, .address), coldWith(evm: 7))
            eq(evm7.call, .evmAddressAt(index: 7), "EVM address #7 call")
            eq(evm7.addressIndex, 7, "EVM address #7 index")
            eq(evm7.ownbitCheck, "evm:7", "EVM address #7 check")
            t(evm7.requireOwnbitMatch && evm7.shownInOwnbit, "EVM address require + shown")
            eq(evm7.notes, [.addressOnly], "EVM address notes")
            eq(evm7.evmAccountN, 7, "EVM address evmAccountN")
            eq(plan(sel(.evm, .native, .standard, .address), cold).call, .evmAddressAt(index: 0), "EVM address #0")

            // EVM wallet mode: "Account N + 1" only when N > 0.
            let n0 = plan(sel(.evm), cold)
            eq(n0.call, .enginePairing(chain: .evm, profile: nil, mode: .wallet, index: 0), "EVM wallet call")
            eq(n0.ownbitCheck, "evm:0", "EVM wallet check")
            eq(n0.notes, [.accountKey], "EVM wallet N=0 notes")
            let n7 = plan(sel(.evm), coldWith(evm: 7))
            eq(n7.notes, [.accountKey, .evmAccountN], "EVM wallet N=7 notes")
            eq(n7.evmAccountN, 7, "EVM wallet evmAccountN")
            eq(n7.addressIndex, 0, "hd-key first address stays #0")
            eq(n7.ownbitCheck, "evm:0", "EVM wallet N=7 check")
            t(n7.requireOwnbitMatch, "EVM wallet require")

            // Bitcoin notes.
            let native = plan(BILPairingSelection.default, cold)
            eq(native.call, .enginePairing(chain: .bitcoin, profile: "native", mode: .accountXpub, index: 0), "BTC native call")
            eq(native.notes, [.accountKey, .usedInWallet, .btcPairEachType, .btcGapLimit], "BTC native notes")
            eq(native.ownbitCheck, "bitcoin:native", "BTC native check")
            t(!native.requireOwnbitMatch, "nested / native rows may be absent: mark dropped, not the QR")
            let legacyAddress = plan(sel(.bitcoin, .legacy, .standard, .address), cold)
            eq(legacyAddress.notes, [.addressOnly, .usedInWallet, .btcPairEachType], "legacy address notes")
            t(legacyAddress.requireOwnbitMatch, "legacy is the anchor every wallet has")
            eq(legacyAddress.call, .enginePairing(chain: .bitcoin, profile: "legacy", mode: .address, index: 0), "legacy address call")
            let nested = plan(sel(.bitcoin, .nested), coldWith(inUse: [.native]))
            eq(nested.notes, [.accountKey, .btcGapLimit], "nested with one type in use")
            t(nested.shownInOwnbit, "nested shown")

            // Taproot: not in Ownbit on a cold wallet; shown for a hot wallet with Taproot keys.
            let taprootCold = plan(sel(.bitcoin, .taproot), cold)
            t(!taprootCold.shownInOwnbit, "Taproot cold not shown")
            eq(taprootCold.ownbitCheck, nil, "Taproot cold no check")
            t(taprootCold.notes.contains(.notInOwnbit), "Taproot cold NOT_IN_OWNBIT")
            t(!taprootCold.notes.contains(.usedInWallet), "Taproot cold not used")
            let hot = BILWalletPairingFacts(kind: .normal, btcProfilesInUse: [.taproot, .native], hasTaprootKeys: true)
            let taprootHot = plan(sel(.bitcoin, .taproot), hot)
            t(taprootHot.shownInOwnbit, "Taproot hot shown")
            eq(taprootHot.ownbitCheck, "bitcoin:taproot", "Taproot hot check")
            eq(taprootHot.notes, [.accountKey, .usedInWallet, .btcPairEachType, .btcGapLimit], "Taproot hot notes")

            // BIP48 cosigner keys.
            for p in BILPsBitcoinProfile.multisig {
                let x = plan(sel(.bitcoin, p), cold)
                eq(x.call, .enginePairing(chain: .bitcoin, profile: p.rawValue, mode: .accountXpub, index: 0), "BIP48 call \(p)")
                eq(x.notes, [.cosigner, .notInOwnbit], "BIP48 notes \(p)")
                eq(x.ownbitCheck, nil, "BIP48 check \(p)")
                t(!x.shownInOwnbit && !x.requireOwnbitMatch, "BIP48 not shown / required \(p)")
            }
            // Android refuses BIP48 profiles / negative indexes in the facts; iOS normalizes them.
            let odd = BILWalletPairingFacts(kind: .cold, btcProfilesInUse: [.multisigNative, .native], evmIndex: -3, tronIndex: -1)
            eq(odd.btcProfilesInUse, [.native], "facts drop BIP48 profiles")
            eq(odd.evmIndex, 0, "facts negative EVM index → 0")
            eq(odd.tronIndex, 0, "facts negative TRON index → 0")
            eq(BILWalletPairingFacts(kind: .normal), BILWalletPairingFacts(kind: .normal, btcProfilesInUse: [], hasTaprootKeys: false,
                                                                           evmIndex: 0, tronIndex: 0, hasSolanaAddress: false), "facts defaults")

            // Solana.
            let standard = plan(sel(.solana), cold)
            eq(standard.call, .enginePairing(chain: .solana, profile: "standard", mode: .wallet, index: 0), "SOL standard call")
            eq(standard.ownbitCheck, "solana:standard", "SOL standard check")
            eq(standard.ownbitCheck, BILPairingExportPolicy.solanaStandardKey, "solanaStandardKey")
            eq(standard.notes, [.accountKey], "SOL standard notes")
            t(!standard.requireOwnbitMatch, "SOL never required")
            let noSol = plan(sel(.solana), coldWith(sol: false))
            eq(noSol.ownbitCheck, nil, "no SOL address → no check")
            t(noSol.shownInOwnbit, "no SOL address still shown")
            for p in [BILPsSolanaProfile.trust, .legacy] {
                let x = plan(sel(.solana, .native, p, .address), cold)
                eq(x.notes, [.addressOnly, .notInOwnbit], "SOL \(p) address notes")
                eq(x.ownbitCheck, nil, "SOL \(p) check")
                t(!x.shownInOwnbit, "SOL \(p) not shown")
                eq(x.call, .enginePairing(chain: .solana, profile: p.rawValue, mode: .address, index: 0), "SOL \(p) call")
            }

            // Invariants over every selection (cold and hot facts).
            for facts in [cold, hot, coldWith(evm: 4, tron: 3, inUse: [], sol: false)] {
                for s in everySelection() {
                    let p = plan(s, facts)
                    eq(!p.shownInOwnbit, p.notes.contains(.notInOwnbit), "!shown ⇔ NOT_IN_OWNBIT \(s)")
                    eq(s.bearsKey, p.notes.contains(.accountKey) || p.notes.contains(.cosigner), "bearsKey ⇔ key note \(s)")
                    eq(p.requireOwnbitMatch, s.chain == .evm || s.chain == .tron || (s.chain == .bitcoin && s.bitcoinProfile == .legacy),
                       "requireOwnbitMatch \(s)")
                    if p.requireOwnbitMatch { t(p.ownbitCheck != nil, "required check has a key \(s)") }
                }
            }

            // Notes banner filter (R3 §6.9).
            eq(BILPairingExportPolicy.bannerNotes(standard), [], "SOL wallet: account-key note dropped")
            eq(BILPairingExportPolicy.bannerNotes(plan(sel(.solana, .native, .trust, .address), cold)), [.addressOnly], "SOL trust address banner")
            eq(BILPairingExportPolicy.bannerNotes(plan(sel(.solana, .native, .trust), cold)), [], "SOL trust wallet banner")
            eq(BILPairingExportPolicy.bannerNotes(native), [.accountKey, .btcPairEachType, .btcGapLimit], "BTC native banner")
            eq(BILPairingExportPolicy.bannerNotes(fresh), [.addressOnly, .tronCurrentN], "TRON #5 banner")
            eq(BILPairingExportPolicy.bannerNotes(plan(sel(.tron), cold, tron: 0)), [.addressOnly], "TRON #0 on #0 banner")
            eq(BILPairingExportPolicy.bannerNotes(n7), [.accountKey, .evmAccountN], "EVM wallet N=7 banner")
            eq(BILPairingExportPolicy.bannerNotes(plan(sel(.bitcoin, .multisigNative), cold)), [.cosigner], "BIP48 banner")
            eq(BILPairingExportPolicy.bannerNotes(taprootCold), [.accountKey, .btcPairEachType, .btcGapLimit], "Taproot cold banner")

            // Note keys and check keys.
            let placeholdersOf: [BILPairingNote: Int] = [.evmAccountN: 2, .tronCurrentN: 1, .tronIndexN: 1]
            eq(BILPairingNote.allCases.count, 11, "11 notes")
            for note in BILPairingNote.allCases { checkKey(note.stringKey, placeholders: placeholdersOf[note] ?? 0, "note \(note)") }
            eq(BILPairingExportPolicy.bitcoinKey(.taproot), "bitcoin:taproot", "bitcoinKey")
            eq(BILPairingExportPolicy.bitcoinKey(.multisigNested), "bitcoin:multisig-nested", "bitcoinKey BIP48")
            eq(BILPairingExportPolicy.evmKey(7), "evm:7", "evmKey")
            eq(BILPairingExportPolicy.tronKey(0), "tron:0", "tronKey 0")
        }

        // (E. Compatible wallets and F. Links: UI catalog / bundled H5, not part of the package.)

        // MARK: - G. Engine vocabulary (EngineVocabularyTest, R5 §6)

        do {
            let V = BILPublicEngineVocabulary.self
            let engine = vocabulary["engine"] as? [String: Any]
            eq(V.engineSHA256, engine?["sha256"] as? String ?? "", "engine SHA-256 = vocabulary")
            // (The app also compared it with its strings JSON `_meta`; no strings here.)

            // Actions.
            let jsonActions = (vocabulary["actions"] as? [[String: Any]] ?? []).map { ($0["id"] as? String ?? "", $0["text"] as? String ?? "") }
            eq(V.actions.count, 26, "26 actions")
            eq(jsonActions.count, V.actions.count, "vocabulary action count")
            for (i, a) in V.actions.enumerated() where i < jsonActions.count {
                t(same(a.id, jsonActions[i].0) && same(a.text, jsonActions[i].1), "action \(i) = vocabulary (\(a.id))")
            }
            for a in V.actions {
                let l = V.localizedAction(a.text)
                t(l?.key == "PublicProtocol.action." + a.id && l?.safePrefix == false, "localizedAction \(a.text)")
                eq(V.actionId(a.text), a.id, "actionId \(a.text)")
                checkKey("PublicProtocol.action." + a.id, placeholders: 0, "action \(a.id)")
                let safe = V.localizedAction("Safe: " + a.text)
                t(safe?.key == "PublicProtocol.action." + a.id && safe?.safePrefix == true, "Safe: \(a.text)")
            }
            checkKey("PublicProtocol.action.generic", placeholders: 0, "generic action")
            t(V.localizedAction("Transfer SOL") == nil, "runtime action Transfer SOL stays verbatim")
            eq(V.actionId("Transfer SOL"), nil, "actionId Transfer SOL")
            eq(V.actionId("Safe: Send"), "send", "actionId Safe: Send")
            t(V.localizedAction("Safe: Native transfer") == nil, "Safe: unknown")
            t(V.localizedAction("Safe:Send") == nil, "Safe prefix needs the space")
            t(V.localizedAction("send") == nil, "case-sensitive")
            t(V.localizedAction("Send ") == nil, "exact text")
            t(V.localizedAction("Safe: Safe: Send") == nil, "one Safe prefix only")
            let prefixes = vocabulary["actionPrefixes"] as? [String] ?? []
            eq(prefixes, ["Safe: "], "vocabulary action prefixes")

            // Warnings (25 translated).
            let jsonWarnings = vocabulary["warnings"] as? [[String: Any]] ?? []
            let translated = jsonWarnings.filter { ($0["translate"] as? Bool) == true }
            eq(translated.count, 25, "25 translated warnings in the vocabulary")
            eq(V.warnings.count, 25, "25 warnings")
            eq(V.warnings.map { $0.id }, translated.map { $0["id"] as? String ?? "" }, "warning ids in vocabulary order")
            for (json, entry) in zip(translated, V.warnings) {
                t(same(entry.text, json["text"] as? String), "\(entry.id) text byte-exact")
                eq(V.toPattern(entry.text, digitArgs: []), json["pattern"] as? String ?? "", "\(entry.id) pattern")
                eq(vocabularyPlaceholders(entry.text), json["placeholders"] as? Int ?? -1, "\(entry.id) placeholders")
                eq(entry.key, "PublicProtocol.warn." + entry.id, "\(entry.id) key")
                checkKey(entry.key, placeholders: vocabularyPlaceholders(entry.text), "warning \(entry.id)")
                t(entry.digitArgs.isEmpty, "\(entry.id) has no digit args")
            }
            t(V.warnings.contains { $0.id == V.typedDataAnyChainId }, "typedDataAnyChain is translated")
            t(V.warnings.first { $0.id == "btcChangeVerified" }?.text.unicodeScalars.contains("\u{2019}") == true, "U+2019 kept")

            // Aliases.
            var byId: [String: [String: Any]] = [:]
            for w in jsonWarnings { if let id = w["id"] as? String { byId[id] = w } }
            eq(V.aliases.map { $0.id }, [V.durableNonceId, V.btcWitnessOnlyId, V.ownershipProofId], "alias ids")
            let ownbitOwn: Set<String> = ["PublicProtocol.warn.changeIndex", "PublicProtocol.warn.durableNonce", "PublicProtocol.warn.noChainId",
                                          "PublicProtocol.warn.tokenDecimals", "PublicProtocol.warn.btcWitnessOnly", "PublicProtocol.warn.ownershipProof"]
            for entry in V.aliases {
                guard let json = byId[entry.id] else { t(false, "\(entry.id) is a warning of the pinned engine"); continue }
                eq(json["translate"] as? Bool, false, "\(entry.id) not one of the 25")
                t(same(entry.text, json["text"] as? String), "\(entry.id) text byte-exact")
                eq(V.toPattern(entry.text, digitArgs: []), json["pattern"] as? String ?? "", "\(entry.id) pattern")
                eq(vocabularyPlaceholders(entry.text), json["placeholders"] as? Int ?? -1, "\(entry.id) placeholders")
                t(ownbitOwn.contains(entry.key), "\(entry.id) → \(entry.key) is one of Ownbit's own warnings")
                checkKey(entry.key, placeholders: 0, "alias \(entry.id)")
                let w = V.warning(entry.text)
                t(w?.id == entry.id && w?.key == entry.key && w?.args == [] && w?.severity == .warning, "warning(alias \(entry.id))")
                if let engineText = strings[entry.key]?["_engineText"] as? String {
                    t(same(engineText, entry.text), "\(entry.key) _engineText = alias text")
                }
            }
            eq(Set(jsonWarnings.compactMap { ($0["ownbitAlias"] as? Bool) == true ? $0["id"] as? String : nil }), Set(V.aliases.map { $0.id }),
               "alias set = vocabulary ownbitAlias")

            // Every warning and alias matches its own text (a pattern that does not compile would never match: shown in English).
            for e in V.warnings + V.aliases {
                let n = vocabularyPlaceholders(e.text)
                var sample = e.text.replacingOccurrences(of: "%%", with: "%")
                for i in 1...9 { sample = sample.replacingOccurrences(of: "%\(i)$s", with: "7") }
                let w = V.warning(sample)
                t(w?.id == e.id && w?.key == e.key && w?.args == Array(repeating: "7", count: n), "\(e.id) matches itself")
            }

            // Labels.
            let jsonLabels = vocabulary["labels"] as? [[String: Any]] ?? []
            eq(jsonLabels.count, 233, "233 vocabulary labels")
            var labelByText: [String: [String: Any]] = [:]
            for l in jsonLabels { if let text = l["text"] as? String { labelByText[text] = l } }
            eq(V.labels.count, 31, "31 keyed labels")
            for entry in V.labels {
                guard let json = labelByText[entry.text] else { t(false, "label \(entry.text) in the vocabulary"); continue }
                eq(V.toPattern(entry.text, digitArgs: []), json["pattern"] as? String ?? "", "label \(entry.id) pattern")
                eq(vocabularyPlaceholders(entry.text), json["placeholders"] as? Int ?? -1, "label \(entry.id) placeholders")
                let expectedKey = entry.id == "derivationPath" ? "PublicProtocol.pair.derivationPath" : "PublicProtocol.label." + entry.id
                eq(entry.key, expectedKey, "label \(entry.id) key")
                checkKey(entry.key, placeholders: vocabularyPlaceholders(entry.text), "label \(entry.id)")
                if let engineText = strings[entry.key]?["_engineText"] as? String {
                    t(same(engineText, entry.text), "\(entry.key) _engineText = label text")
                }
                for d in entry.digitArgs { t(entry.text.contains("%\(d)$s"), "\(entry.id) digit arg \(d) exists") }
            }
            // Every label key of the strings JSON is in the table (no key left unmapped).
            let labelKeys = Set(V.labels.map { $0.key })
            for key in strings.keys where key.hasPrefix("PublicProtocol.label.") { t(labelKeys.contains(key), "\(key) is mapped") }

            eq(V.label("Network"), "PublicProtocol.label.network", "label Network")
            eq(V.label("Derivation path"), "PublicProtocol.pair.derivationPath", "label Derivation path")
            eq(V.label("Input 3"), nil, "label() is for placeholder-free labels only")
            eq(V.label("network"), nil, "label exact")
            func ll(_ s: String) -> String {
                guard let r = V.localizedLabel(s) else { return "nil" }
                return r.key + " " + r.args.joined(separator: "|")
            }
            eq(ll("Input 3 sighash"), "PublicProtocol.label.inputSighash 3", "Input 3 sighash")
            eq(ll("Instruction 2 \u{00B7} Recipient"), "PublicProtocol.label.instruction 2|Recipient", "Instruction 2 · Recipient")
            eq(ll("Native amount (wei)"), "PublicProtocol.label.nativeAmountWei ", "Native amount (wei) wins over the template")
            eq(ll("Native amount (ETH)"), "PublicProtocol.label.nativeAmount ETH", "Native amount (ETH)")
            eq(ll("Output 2 ownership"), "nil", "a longer engine label is not half-translated")
            eq(ll("Input 1 multisig"), "nil", "Input 1 multisig")
            eq(ll("Input 3"), "PublicProtocol.label.input 3", "Input 3")
            eq(ll("Input x"), "nil", "index placeholders are digits only")
            eq(ll("Input \u{0663}"), "nil", "ASCII digits only")
            eq(ll("Maximum network fee (0.1 ETH)"), "PublicProtocol.label.maxNetworkFee 0.1 ETH", "template text arg")
            eq(ll("Network\n"), "nil", "whole text (no final newline)")
            eq(ll("Instruction 3 \u{00B7} Line\nTwo"), "PublicProtocol.label.instruction 3|Line\nTwo", "text arg spans lines")

            // Longest-template rule over all 233 vocabulary labels.
            let keyed = Dictionary(uniqueKeysWithValues: V.labels.map { ($0.text, $0) })
            let placeholderRe = try! NSRegularExpression(pattern: "%\\d\\$s", options: [])
            var localized = 0
            for label in jsonLabels {
                guard let text = label["text"] as? String else { continue }
                let ns = text as NSString
                let sample = placeholderRe.stringByReplacingMatches(in: text, options: [], range: NSRange(location: 0, length: ns.length),
                                                                    withTemplate: "7").replacingOccurrences(of: "%%", with: "%")
                let matching = jsonLabels.compactMap { l -> String? in
                    guard let lt = l["text"] as? String, let p = l["pattern"] as? String, kotlinMatches(p, sample) else { return nil }
                    return lt
                }
                let exact = matching.first { candidate in
                    guard same(candidate, sample), let entry = keyed[candidate] else { return false }
                    return vocabularyPlaceholders(entry.text) == 0
                }
                var longest: String?
                for m in matching where longest == nil || m.utf16.count > longest!.utf16.count { longest = m }
                guard let expected = exact ?? longest else { t(false, "\(sample) matches itself"); continue }
                let got = V.localizedLabel(sample)
                if let entry = keyed[expected] {
                    eq(got?.key, entry.key, "\"\(sample)\" → \"\(expected)\"")
                    localized += 1
                } else {
                    t(got == nil, "\"\(sample)\" is the unkeyed \"\(expected)\": verbatim")
                }
            }
            t(localized >= V.labels.count, "localized \(localized) ≥ \(V.labels.count)")

            // No warning of the golden vectors is dropped (localized or verbatim).
            var reviewWarnings: [String] = []
            for c in vectors["cases"] as? [[String: Any]] ?? [] {
                for step in c["steps"] as? [[String: Any]] ?? [] {
                    guard let request = step["request"] as? [String: Any], let op = request["operation"] as? String,
                          let response = step["response"] as? [String: Any], (response["ok"] as? Bool) == true,
                          let result = response["result"] as? [String: Any] else { continue }
                    let review: [String: Any]?
                    if op == "review" { review = result } else if op == "resolveSigningPlan" { review = result["review"] as? [String: Any] } else { review = nil }
                    reviewWarnings += review?["warnings"] as? [String] ?? []
                }
            }
            t(reviewWarnings.count > 100, "golden warnings \(reviewWarnings.count) > 100")
            var localizedIds = Set<String>()
            let entriesById = Dictionary(uniqueKeysWithValues: (V.warnings + V.aliases).map { ($0.id, $0) })
            for w in reviewWarnings {
                guard let mapped = V.warning(w) else { continue }
                localizedIds.insert(mapped.id)
                eq(mapped.args.count, entriesById[mapped.id].map { vocabularyPlaceholders($0.text) } ?? -1, "args of \(mapped.id)")
                eq(mapped.severity, V.severity(w), "severity of \(mapped.id)")
            }
            for id in ["btcOutputsShown", "evmMessageAuthorizes", "contractUnverified", "unlimitedApproval", "evmHighFee"] {
                t(localizedIds.contains(id), "golden corpus localizes \(id)")
            }
            let fee = V.warning("HIGH FEE: This transaction allows up to 0.06 HYPE in network fees. Check the gas settings in your other wallet.")
            t(fee?.id == "evmHighFee" && fee?.key == "PublicProtocol.warn.evmHighFee", "evmHighFee matched")
            eq(fee?.args ?? [], ["0.06 HYPE"], "HYPE fee args")
            eq(fee?.severity, .danger, "HYPE fee danger")
            eq(V.warning("HIGH FEE: This transaction allows up to 0.5 SOL in priority fees. Check the fee settings in your other wallet.")?.args ?? [],
               ["0.5"], "SOL fee args")
            t(V.warning("Some brand-new engine warning.") == nil, "unknown → verbatim")
            t(V.warning("UNLIMITED spending approval. Extra") == nil, "whole-text match only")
            t(V.warning("UNLIMITED spending approval.\n") == nil, "no final newline")
            eq(V.warning("UNLIMITED spending approval.")?.severity, .danger, "unlimited danger")
            eq(V.warning(V.warnings[0].text)?.severity, .warning, "btcOutputsShown warning")

            // Severity, decode badge, risk pill.
            eq(V.severity("HIGH RISK: x"), .danger, "HIGH RISK")
            eq(V.severity("unlimited spending approval."), .danger, "unlimited lower case")
            eq(V.severity("HIGH FEE: x"), .danger, "HIGH FEE")
            eq(V.severity("Contract identity \u{2026} not verified offline."), .warning, "plain warning")
            eq(V.severity("  \tHIGH RISK"), .danger, "leading whitespace trimmed")
            eq(V.severity("\u{3000}\u{1C}HIGH RISK"), .danger, "Kotlin whitespace (U+3000, U+001C) trimmed")
            eq(V.severity("\u{85}HIGH RISK"), .warning, "U+0085 is not Kotlin whitespace")
            eq(V.severity("h\u{0131}gh r\u{0131}sk"), .danger, "dotless i upper-cases to I (Locale.ROOT)")
            eq(V.severity("HIGHRISK"), .warning, "needs the space")
            eq(V.severity(""), .warning, "empty")
            eq(V.decodeStatusKey("fullyDecoded"), "PublicProtocol.decode.full", "decode full")
            eq(V.decodeStatusKey("partiallyDecoded"), "PublicProtocol.decode.partial", "decode partial")
            eq(V.decodeStatusKey("opaque"), "PublicProtocol.decode.none", "decode none")
            eq(V.decodeStatusKey("FullyDecoded"), "PublicProtocol.decode.none", "unknown decode → none")
            eq(V.riskPillKey("high"), "PublicProtocol.risk.high", "risk high")
            eq(V.riskPillKey("warning"), "PublicProtocol.risk.warning", "risk warning")
            eq(V.riskPillKey("normal"), nil, "risk normal")
            eq(V.riskPillKey("Normal"), "PublicProtocol.risk.high", "unknown risk fails closed")
            eq(vocabulary["decodeStatuses"] as? [String] ?? [], ["fullyDecoded", "partiallyDecoded", "opaque"], "vocabulary decode statuses")
            eq(Set(vocabulary["riskLevels"] as? [String] ?? []), Set(["normal", "warning", "high"]), "vocabulary risk levels")
            for key in ["PublicProtocol.decode.full", "PublicProtocol.decode.partial", "PublicProtocol.decode.none",
                        "PublicProtocol.risk.high", "PublicProtocol.risk.warning"] { checkKey(key, placeholders: 0, "badge \(key)") }

            // toPattern.
            eq(V.toPattern("Input %1$s", digitArgs: [1]), "^Input ([0-9]+)$", "digit placeholder")
            eq(V.toPattern("Input %1$s", digitArgs: []), "^Input ([\\s\\S]+?)$", "text placeholder")
            eq(V.toPattern("a.b%%c (x)", digitArgs: []), "^a\\.b%c \\(x\\)$", "escapes and %%")
            eq(V.toPattern(".*+?^${}()|[]\\", digitArgs: []), "^\\.\\*\\+\\?\\^\\$\\{\\}\\(\\)\\|\\[\\]\\\\$", "every special escaped")
            eq(V.toPattern("%0$s", digitArgs: []), "^%0\\$s$", "%0$s is not a placeholder")
        }

        // (H. Fee text: display formatting, not part of the package.)

    }
}
