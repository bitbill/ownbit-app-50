//  PPIndexTests.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Port of the app harness suite `scripts/public-protocol/tests/index` (main.swift) to XCTest.
//
//  main.swift — suite "index" (WP11): eligibility, sealed public index, cross-check, lazy Ownbit-scheme upgrade,
//  deletion, orphan cleanup, eager COLD build (design WP11 block; ports of PST:eligibility/PublicSignerEligibilityTest,
//  PST:index/{PublicIndexRepositoryTest,PublicIndexVerifierTest,PublicIndexBuilderImplTest,PublicIndexOwnbitSchemeTest}).
//  Golden vectors from $PUB_FIXTURES/vectors.json (real engine answers). Prints "index: N ok, M FAIL".
//

import Foundation
import XCTest
import CryptoKit
import Security
@testable import OwnbitCore

/// The suite namespace (harness helpers are its static members).
enum PPIndexSuite: PPSuite {}

final class PPIndexTests: XCTestCase {
    func testIndex() throws {
        try ppRunSuite("index") { try PPIndexSuite.run() }
    }
}

extension PPIndexSuite {

    static let vectors = Vectors(text: fixtureText("vectors.json"))
    static let COLD = "xcold0000001", HOT = "hot01", OTHER = "xcold0000002"
    static let abandonIndex = vectors.publicIndex("abandon")
    static let ownbitIndex = vectors.publicIndex("abandonOwnbit")
    static let allChains = Set(BILPsChain.allCases)

    static func flipped(_ data: Data, at offset: Int) -> Data {
        var d = data
        d[d.startIndex + offset] ^= 0x01
        return d
    }

    /// Non-autoclosure checks for awaited values (an autoclosure cannot contain `await`).
    @discardableResult
    static func check(_ ok: Bool, _ what: String, file: StaticString = #file, line: UInt = #line) -> Bool {
        return t(ok, what, file: file, line: line)
    }
    @discardableResult
    static func same<T: Equatable>(_ actual: T, _ expected: T, _ what: String, file: StaticString = #file, line: UInt = #line) -> Bool {
        return eq(actual, expected, what, file: file, line: line)
    }

    // MARK: - A. Eligibility rule (PublicSignerEligibilityTest; D-07 / D-45)

    final class ConfusedEngine: FakeEngine {
        override func derivePublicAddresses(publicIndex: BILJSONObject, chain: String, profile: String?, start: Int, count: Int) async throws -> BILJSONObject {
            return try await super.derivePublicAddresses(publicIndex: publicIndex, chain: "bitcoin", profile: "native", start: 0, count: 1)
        }
    }
    final class PanelOwner {
        var active = false
    }
    @MainActor final class FakeBackgroundExecution: BILPublicBackgroundExecution {
        var refuse = false
        private(set) var begun: [String] = []
        private(set) var ended: [Int] = []
        private var expirations: [Int: @MainActor () -> Void] = [:]
        private(set) var lastId = 0
        var backgroundEntries = 0
        var isInBackground = false

        func beginTask(name: String, expired: @escaping @MainActor () -> Void) -> Int? {
            begun.append(name)
            if refuse { return nil }
            lastId += 1
            expirations[lastId] = expired
            return lastId
        }

        func endTask(_ id: Int) {
            ended.append(id)
        }

        /// The system's background time for task `id` ran out (iOS calls the expiration handler on main).
        func expire(_ id: Int) {
            expirations[id]?()
        }

        func enterBackground() {
            backgroundEntries += 1
            isInBackground = true
        }

        func enterForeground() {
            isInBackground = false
        }
    }
    static func logCount(_ code: String) -> Int {
        return PPStubLog.lines.filter { $0 == "error: PublicProtocol index: " + code }.count
    }

    /// The harness main.swift (nonisolated top-level code, as in the harness).
    static func run() throws {
        section("eligibility")
        do {
            typealias E = BILPublicSignerEligibility
            eq(E.rule(Fx.traits(cold: false)), .eligible(.normal), "normal (hot) personal wallet eligible")
            eq(E.rule(Fx.traits(cold: true)), .eligible(.cold), "cold personal wallet eligible")
            eq(E.rule(Fx.traits(exists: false)), .notEligible(.unknownWallet), "no wallet → unknownWallet")
            eq(E.rule(Fx.traits(cold: false, multisig: true)), .notEligible(.multisig), "hot multisig")
            eq(E.rule(Fx.traits(cold: true, multisig: true)), .notEligible(.multisig), "cold multisig")
            eq(E.rule(Fx.traits(cold: false, multisig: true, watch: true, seed: false)), .notEligible(.multisig), "watch multisig")
            eq(E.rule(Fx.traits(cold: true, multisig: true, customPath: true, electrum: true)), .notEligible(.multisig), "multisig decides first")
            eq(E.rule(Fx.traits(cold: false, watch: true, seed: false)), .notEligible(.watchOnly), "watch wallet")
            eq(E.rule(Fx.traits(cold: false, seed: false)), .notEligible(.watchOnly), "no seed on this device → watchOnly")
            eq(E.rule(Fx.traits(cold: false, privateKey: true, seed: false)), .notEligible(.privateKey), "private-key wallet keeps its reason without a seed")
            eq(E.rule(Fx.traits(cold: false, watch: true, privateKey: true, seed: false)), .notEligible(.watchOnly), "watch private-key wallet")
            eq(E.rule(Fx.traits(cold: false, merchant: true)), .notEligible(.merchant), "merchant wallet (D-45)")
            eq(E.rule(Fx.traits(cold: false, customPath: true)), .notEligible(.customPath), "custom path")
            eq(E.rule(Fx.traits(cold: true, customPath: true)), .notEligible(.customPath), "cold with a custom path → customPath")
            eq(E.rule(Fx.traits(cold: false, electrum: true)), .notEligible(.electrumSeed), "Electrum seed (hot)")
            eq(E.rule(Fx.traits(cold: true, electrum: true)), .notEligible(.electrumSeed), "Electrum seed (cold)")
            eq(E.rule(Fx.traits(cold: false, customPath: true, electrum: true)), .notEligible(.customPath), "custom path before Electrum")
            eq(E.rule(Fx.traits(cold: false, merchant: true, customPath: true)), .notEligible(.merchant), "merchant before custom path")
            t(BILPublicEligibility.eligible(.cold).isEligible && BILPublicEligibility.eligible(.cold).kind == .cold, "eligible kind")
            t(!BILPublicEligibility.notEligible(.multisig).isEligible && BILPublicEligibility.notEligible(.multisig).kind == nil, "not eligible: no kind")
            // Every combination of the 9 traits: only exists ∧ ¬multisig ∧ ¬observer ∧ ¬privateKey ∧ hasSeed ∧ ¬merchant ∧ ¬custom ∧ ¬electrum is eligible.
            var allOK = true
            for bits in 0..<512 {
                let b = { (i: Int) in bits & (1 << i) != 0 }
                let tr = BILPublicSignerEligibility.Traits(exists: b(0), isMultisig: b(1), isObserver: b(2), hasSeed: b(3), isPrivateKey: b(4),
                                                           isMerchant: b(5), hasCustomPathMarker: b(6), isElectrum: b(7), isCold: b(8))
                let expected = b(0) && !b(1) && !b(2) && !b(4) && b(3) && !b(5) && !b(6) && !b(7)
                let r = E.rule(tr)
                if r.isEligible != expected || (expected && r.kind != (b(8) ? .cold : .normal)) { allOK = false }
            }
            t(allOK, "eligible ⇔ exists, seed, no multisig / watch / private key / merchant / custom path / Electrum (512 combinations)")
            // No connectivity input exists (the Traits members are the contract).
            let labels = Mirror(reflecting: Fx.traits()).children.compactMap { $0.label }
            eq(labels, ["exists", "isMultisig", "isObserver", "hasSeed", "isPrivateKey", "isMerchant", "hasCustomPathMarker", "isElectrum", "isCold"],
               "traits: no online / network input")
            t(!labels.contains { $0.lowercased().contains("online") || $0.lowercased().contains("network") || $0.lowercased().contains("connect") },
              "eligibility has no online condition")

            let hex128 = String(repeating: "0123456789abcdef", count: 8)
            t(E.isSeedHex(hex128), "seed hex: 128 lower-case hex")
            t(E.isSeedHex(hex128.uppercased()), "seed hex: upper case accepted (engine is case-insensitive)")
            t(!E.isSeedHex(String(hex128.dropLast())), "seed hex: 127 refused")
            t(!E.isSeedHex(hex128 + "0"), "seed hex: 129 refused")
            t(!E.isSeedHex(String(hex128.dropLast()) + "g"), "seed hex: non-hex refused")
            t(!E.isSeedHex(String(hex128.dropLast()) + "\u{0661}"), "seed hex: Arabic-Indic digit refused")
            t(!E.isSeedHex(String(hex128.dropLast()) + "\u{FF10}"), "seed hex: full-width digit refused")
            t(!E.isSeedHex(""), "seed hex: empty refused")
            t(!E.isSeedHex("abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"), "a mnemonic is never a seed")
            t(E.isSeedHex(vectors.seedHex("abandon")) && E.isSeedHex(vectors.seedHex("zh-hans")), "vector seeds are seed hex")
        }

        // MARK: - B. Facts snapshot

        section("facts")
        runAsync { @MainActor in
            let env = Env(vectors)
            let f = BILPublicWalletFacts(walletId: "w", kind: .normal, seedHash: "", legacyXpub: "", nestedXpub: "n", nativeXpub: "",
                                         taprootXpub: "  ", ethXpub: "", ethAddress: "", ethIndex: -3, trxAddress: "", trxAddress0: "",
                                         trxIndex: -1, solAddress: "", btcProfilesInUse: [.legacy, .multisigNative, .taproot, .native, .nested])
            t(f.seedHash == nil && f.legacyXpub == nil && f.nativeXpub == nil && f.ethXpub == nil && f.ethAddress == nil, "\"\" normalized to nil")
            t(f.trxAddress == nil && f.trxAddress0 == nil && f.solAddress == nil && f.nestedXpub == "n", "\"\" normalized to nil (TRON / SOL), values kept")
            eq(f.ethIndex, 0, "negative ETH index → 0")
            eq(f.trxIndex, 0, "negative TRX index → 0")
            eq(f.btcProfilesInUse, [.taproot, .native, .nested, .legacy], "profiles in use: Ownbit order, single-sig only")
            eq(f.taprootXpub, "  ", "whitespace kept in the snapshot")
            let p = f.pairingFacts
            t(!p.hasTaprootKeys, "blank Taproot xpub → no Taproot keys")
            t(!p.hasSolanaAddress, "no SOL address")
            eq(p.btcProfilesInUse, [.taproot, .native, .nested, .legacy], "pairing facts profiles")
            let g = env.abandonFacts("x", cold: false, ethIndex: 7, trxIndex: 1, withTaproot: true)
            eq(g.pairingFacts, BILWalletPairingFacts(kind: .normal, btcProfilesInUse: [.legacy, .native], hasTaprootKeys: true, evmIndex: 7, tronIndex: 1,
                                                     hasSolanaAddress: true), "pairing facts of a hot Taproot wallet on ETH #7 / TRX #1")
            t(BILPublicWalletFacts.nonBlank(" \u{3000}\t") == nil && BILPublicWalletFacts.nonBlank("a") == "a" && BILPublicWalletFacts.nonBlank(nil) == nil,
              "Kotlin isNotBlank")
            // Android `!it.address.isNullOrBlank()`: a blank SOL address is no SOL address (as the cross-check treats it)
            let blankSol = with(g, solAddress: " \u{3000}\t")
            eq(blankSol.solAddress, " \u{3000}\t", "blank SOL address kept in the snapshot")
            t(!blankSol.pairingFacts.hasSolanaAddress, "blank SOL address → hasSolanaAddress false (Kotlin isNullOrBlank)")
            // descriptions never show keys, addresses, the seed hash or the wallet id (C-KEY-5)
            let d = env.abandonFacts("xcolddesc001", withTaproot: true)
            let texts = [String(describing: d), String(reflecting: d), "\(d)"]
            eq(texts, Array(repeating: "BILPublicWalletFacts(kind: cold)", count: 3), "facts description / debugDescription = kind only")
            let factSecrets = [d.walletId, d.seedHash ?? "-", OV.XPUB_LEGACY, OV.YPUB_NESTED, OV.ZPUB_NATIVE, OV.XPUB_TAPROOT, OV.XPUB_ETH,
                               OV.ETH_0.lowercased(), OV.TRX_0, OV.SOL]
            t(texts.allSatisfy { text in !factSecrets.contains { text.contains($0) } }, "no key / address / seed hash / wallet id in a facts description")
        }

        // MARK: - C. Sealer and envelope (PublicIndexSealer, spec §4.3)

        section("sealer")
        do {
            eq(String(decoding: BILPublicIndexSealer.aad(walletId: COLD, kind: .cold), as: UTF8.self), "io.ownbit.pubsigner.index.v1|xcold0000001|1", "AAD string (cold)")
            eq(String(decoding: BILPublicIndexSealer.aad(walletId: HOT, kind: .normal), as: UTF8.self), "io.ownbit.pubsigner.index.v1|hot01|0", "AAD string (normal)")
            eq(BILPublicIndexSealer.formatVersion, 1, "format version 1")
            let key = SymmetricKey(size: .bits256), other = SymmetricKey(size: .bits256)
            let plain = Data("x".utf8)
            let sealed = try BILPublicIndexSealer.seal(plain, key: key, walletId: COLD, kind: .cold)
            eq(sealed.count, 12 + 1 + 16, "combined = nonce ‖ ciphertext ‖ tag")
            eq(BILPublicIndexSealer.unseal(sealed, key: key, walletId: COLD, kind: .cold), plain, "seal → unseal round trip")
            t(BILPublicIndexSealer.unseal(sealed, key: key, walletId: COLD, kind: .normal) == nil, "other kind does not open")
            t(BILPublicIndexSealer.unseal(sealed, key: key, walletId: OTHER, kind: .cold) == nil, "other wallet id does not open")
            t(BILPublicIndexSealer.unseal(sealed, key: other, walletId: COLD, kind: .cold) == nil, "other key does not open")
            var tamperedAll = true
            for i in 0..<sealed.count where BILPublicIndexSealer.unseal(flipped(sealed, at: i), key: key, walletId: COLD, kind: .cold) != nil { tamperedAll = false }
            t(tamperedAll, "every flipped bit (nonce, ciphertext, tag) does not open")
            t(BILPublicIndexSealer.unseal(sealed.prefix(27), key: key, walletId: COLD, kind: .cold) == nil, "truncated does not open")
            t(BILPublicIndexSealer.unseal(Data(), key: key, walletId: COLD, kind: .cold) == nil, "empty does not open")
            let again = try BILPublicIndexSealer.seal(plain, key: key, walletId: COLD, kind: .cold)
            t(again != sealed, "random nonce: two seals differ")

            let env = BILPublicIndexEnvelope(formatVersion: 1, seedHashes: ["aa", "bb"], createdAtMs: 1_760_000_000_000, sealed: "AAEC")
            eq(String(decoding: env.encoded(), as: UTF8.self), #"{"formatVersion":1,"seedHashes":["aa","bb"],"createdAt":1760000000000,"sealed":"AAEC"}"#,
               "envelope bytes")
            eq(BILPublicIndexEnvelope.decode(env.encoded()), env, "envelope round trip")
            let envTexts = [String(describing: env), String(reflecting: env), "\(env)"]
            eq(envTexts, Array(repeating: "BILPublicIndexEnvelope(formatVersion: 1)", count: 3), "envelope description: format version only (no hashes, no sealed bytes)")
            func dec(_ s: String) -> BILPublicIndexEnvelope? { return BILPublicIndexEnvelope.decode(Data(s.utf8)) }
            t(dec(#"{"formatVersion":1,"seedHashes":[],"createdAt":0,"sealed":"","extra":{"x":1}}"#) != nil, "unknown keys ignored")
            eq(dec(#"{"formatVersion":2,"seedHashes":["a"],"createdAt":1,"sealed":"AA=="}"#)?.formatVersion, 2, "another format version decodes (the read refuses it)")
            let refused = [
                #"{"formatVersion":true,"seedHashes":["a"],"createdAt":1,"sealed":"AA=="}"#,
                #"{"formatVersion":1.0,"seedHashes":["a"],"createdAt":1,"sealed":"AA=="}"#,
                #"{"formatVersion":"1","seedHashes":["a"],"createdAt":1,"sealed":"AA=="}"#,
                #"{"formatVersion":1e0,"seedHashes":["a"],"createdAt":1,"sealed":"AA=="}"#,
                #"{"seedHashes":["a"],"createdAt":1,"sealed":"AA=="}"#,
                #"{"formatVersion":1,"seedHashes":"a","createdAt":1,"sealed":"AA=="}"#,
                #"{"formatVersion":1,"seedHashes":[1],"createdAt":1,"sealed":"AA=="}"#,
                #"{"formatVersion":1,"seedHashes":["a"],"createdAt":1.5,"sealed":"AA=="}"#,
                #"{"formatVersion":1,"seedHashes":["a"],"createdAt":1,"sealed":5}"#,
                #"{"formatVersion":1,"formatVersion":1,"seedHashes":["a"],"createdAt":1,"sealed":"AA=="}"#,
                #"[{"formatVersion":1,"seedHashes":["a"],"createdAt":1,"sealed":"AA=="}]"#,
                #"{"formatVersion":1,"seedHashes":["a"],"createdAt":1,"sealed":"AA=="} x"#,
                "",
            ]
            for (i, s) in refused.enumerated() { t(dec(s) == nil, "strict envelope refuses case \(i)") }
            t(BILPublicIndexEnvelope.decode(Data([0x7B, 0xFF, 0x7D])) == nil, "invalid UTF-8 refused")
        } catch {
            t(false, "sealer threw \(type(of: error))")
        }

        // MARK: - D. Shape and scheme rules (PublicIndexOwnbitSchemeTest "the index shape …")

        section("shape")
        do {
            typealias R = BILPublicIndexRepository
            eq(R.fingerprint(of: abandonIndex), "73C5DA0A", "standard index (100 TRON, no tronScheme) is well formed, upper case")
            eq(R.fingerprint(of: ownbitIndex), "73C5DA0A", "Ownbit-scheme index is well formed")
            eq(R.fingerprint(of: vectors.publicIndex("legal")), "B8688DF1", "legal index")
            func changed(_ base: BILJSONObject, _ key: String, _ value: BILJSONValue?) -> BILJSONObject {
                var o = base
                o[key] = value
                return o
            }
            let tron = ownbitIndex.arr("tronAddressIndex") ?? []
            t(R.fingerprint(of: changed(abandonIndex, "tronScheme", .string("other"))) == nil, "tronScheme \"other\" refused")
            t(R.fingerprint(of: changed(abandonIndex, "tronScheme", .null)) == nil, "tronScheme null refused (present ≠ absent)")
            t(R.fingerprint(of: changed(abandonIndex, "tronScheme", .int(1))) == nil, "tronScheme number refused")
            t(R.fingerprint(of: changed(ownbitIndex, "tronAddressIndex", .array(Array(tron.prefix(99))))) == nil, "Ownbit with 99 TRON refused")
            t(R.fingerprint(of: changed(abandonIndex, "tronAddressIndex", .array(tron + tron))) == nil, "standard with 200 TRON refused")
            let thousand = Array(repeating: tron[0], count: 1000)
            t(R.fingerprint(of: changed(ownbitIndex, "tronAddressIndex", .array(thousand))) == "73C5DA0A", "Ownbit with 1000 TRON accepted")
            t(R.fingerprint(of: changed(ownbitIndex, "tronAddressIndex", .array(thousand + [tron[0]]))) == nil, "Ownbit with 1001 TRON refused")
            t(R.fingerprint(of: changed(ownbitIndex, "version", .number("1.0"))) == nil, "version 1.0 is not 1")
            t(R.fingerprint(of: changed(ownbitIndex, "version", .bool(true))) == nil, "version true is not 1")
            t(R.fingerprint(of: changed(ownbitIndex, "version", .int(2))) == nil, "version 2 refused")
            t(R.fingerprint(of: changed(ownbitIndex, "walletKeyId", .string("95f7"))) == nil, "short walletKeyId refused")
            t(R.fingerprint(of: changed(ownbitIndex, "masterFingerprint", .string("73c5da0g"))) == nil, "non-hex fingerprint refused")
            t(R.fingerprint(of: changed(ownbitIndex, "bitcoinPublicNodes", .array(Array((ownbitIndex.arr("bitcoinPublicNodes") ?? []).prefix(5))))) == nil, "5 BTC nodes refused")
            t(R.fingerprint(of: changed(ownbitIndex, "evmAccountNode", nil)) == nil, "no EVM node refused")
            t(R.fingerprint(of: changed(ownbitIndex, "tronAccountNode", .string("x"))) == nil, "TRON node not an object refused")
            t(R.fingerprint(of: changed(ownbitIndex, "solanaPublicKeys", .array([]))) == nil, "no SOL keys refused")
            t(R.fingerprint(of: BILStrictJSON.parseObject(#"{"version":1,"masterFingerprint":"73c5da0a"}"#) ?? BILJSONObject()) == nil, "fingerprint-only object refused")
            t(R.needsUpgrade(abandonIndex, count: 100), "needsUpgrade(standard, 100)")
            t(!R.needsUpgrade(ownbitIndex, count: 100), "!needsUpgrade(ownbit, 100)")
            t(R.needsUpgrade(ownbitIndex, count: 101), "needsUpgrade(ownbit, 101)")
            t(R.needsUpgrade(changed(ownbitIndex, "tronScheme", .string("Ownbit")), count: 100), "scheme compared exactly")
            throwsError(BILMalformedEngineResult.self, "ensureOwnbitScheme: standard") { try R.ensureOwnbitScheme(abandonIndex, count: 100) }
            throwsError(BILMalformedEngineResult.self, "ensureOwnbitScheme: count differs") { try R.ensureOwnbitScheme(ownbitIndex, count: 101) }
            t((try? R.ensureOwnbitScheme(ownbitIndex, count: 100)) != nil, "ensureOwnbitScheme: ownbit 100")
            eq([0, 98, 99, 100, 500, 999, 1000, 5000, -7, Int.max].map { R.tronAddressCount(trxIndex: $0) }, [100, 100, 100, 101, 501, 1000, 1000, 1000, 100, 1000],
               "tronAddressCount = clamp(trx + 1, 100, 1000)")
            eq(R.tronScheme, "ownbit", "TRON scheme")
            t(R.tronCacheMin == 100 && R.tronCacheMax == 1000 && R.eagerTimeout == 30, "constants")
        }

        // MARK: - E. Verifier (PublicIndexVerifierTest)

        section("verifier")
        runAsync { @MainActor in
            let env = Env(vectors)
            let base = env.abandonFacts(COLD)
            @MainActor func verify(_ f: BILPublicWalletFacts, _ index: BILJSONObject = abandonIndex, _ chains: Set<BILPsChain> = allChains) async throws -> BILPublicVerifyResult {
                return try await env.verifier.verify(index: index, facts: f, chains: chains)
            }
            // the abandon wallet's index matches Ownbit's rows on every chain
            let r = try await verify(base)
            guard case .ok(let ok) = r else { t(false, "abandon cold wallet verifies"); return }
            eq(ok.matches, [BILPublicVerifyMatch(key: "bitcoin:legacy", confirmed: true), BILPublicVerifyMatch(key: "bitcoin:nested", confirmed: true),
                            BILPublicVerifyMatch(key: "bitcoin:native", confirmed: true), BILPublicVerifyMatch(key: "bitcoin:taproot", confirmed: false),
                            BILPublicVerifyMatch(key: "evm:0", confirmed: true), BILPublicVerifyMatch(key: "tron:0", confirmed: true),
                            BILPublicVerifyMatch(key: "solana:standard", confirmed: true)], "matches (cold: no Taproot keys)")
            eq(ok.ownbitAddresses, ["bitcoin:legacy": OV.LEGACY_0, "bitcoin:nested": OV.NESTED_0, "bitcoin:native": OV.NATIVE_0,
                                    "evm:0": OV.ETH_0, "tron:0": OV.TRX_0, "solana:standard": OV.SOL], "agreed addresses (EVM in EIP-55)")
            eq(env.deriver.bitcoinCalls, ["legacy|" + OV.XPUB_LEGACY, "nested|" + OV.YPUB_NESTED, "native|" + OV.ZPUB_NATIVE], "bridges asked with the stored xpubs")
            t(ok.confirmed("tron:0") && !ok.confirmed("bitcoin:taproot") && !ok.confirmed("evm:7"), "confirmed(key)")
            t(!String(describing: ok).contains(OV.LEGACY_0) && !String(describing: r).contains(OV.ETH_0), "no address in descriptions")
            t(env.engine.indexesSeen.allSatisfy { $0 == abandonIndex }, "only the given index reached the engine")

            // a hot wallet with Taproot keys is checked on Taproot too
            if case .ok(let hot)? = try? await verify(env.abandonFacts(COLD, cold: false, withTaproot: true), abandonIndex, [.bitcoin]) {
                t(hot.confirmed("bitcoin:taproot") && hot.ownbitAddresses["bitcoin:taproot"] == OV.TAPROOT_0, "hot Taproot confirmed")
            } else { t(false, "hot Taproot verifies") }
            // Ownbit's current ETH address #N is checked as well
            if case .ok(let e7)? = try? await verify(env.abandonFacts(COLD, ethIndex: 7), abandonIndex, [.evm]) {
                eq(e7.matches, [BILPublicVerifyMatch(key: "evm:0", confirmed: true), BILPublicVerifyMatch(key: "evm:7", confirmed: true)], "ETH #7: evm:0 and evm:7")
                eq(e7.ownbitAddresses["evm:7"], OV.ETH_7, "ETH #7 address")
            } else { t(false, "ETH #7 verifies") }

            // each chain's mismatch is caught
            same(try await verify(with(base, legacyXpub: OV.XPUB_LEGACY_LEGAL)), .mismatch(.bitcoin), "legacy xpub of another wallet")
            same(try await verify(with(base, nestedXpub: "ypubForged")), .mismatch(.bitcoin), "forged nested xpub")
            same(try await verify(with(base, nativeXpub: "zpubForged")), .mismatch(.bitcoin), "forged native xpub")
            same(try await verify(with(base, kind: .normal, taprootXpub: "xpubForgedTaproot")), .mismatch(.bitcoin), "forged Taproot xpub")
            same(try await verify(with(base, ethXpub: OV.XPUB_ETH_LEGAL)), .mismatch(.evm), "ETH xpub of another wallet")
            same(try await verify(with(base, ethAddress: OV.ETH_0_LEGAL)), .mismatch(.evm), "stored ETH address of another wallet")
            same(try await verify(with(base, trxAddress0: OV.TRX_STANDARD_1)), .mismatch(.tron), "TRX address0 = standard #1")
            same(try await verify(with(base, solAddress: OV.SOL_TRUST)), .mismatch(.solana), "SOL address = trust path")
            check((try? await verify(with(base, ethAddress: OV.ETH_0.uppercased().replacingOccurrences(of: "0X", with: "0x")))).map { if case .ok = $0 { return true }; return false } ?? false,
              "EVM compared ignoring case")

            // the index's own caches must agree with its nodes
            var badEvm = abandonIndex
            if var d = abandonIndex.obj("evmDefaultAddress") { d.set("address", .string(OV.ETH_0_LEGAL)); badEvm.set("evmDefaultAddress", .object(d)) }
            same(try await verify(base, badEvm, [.evm]), .mismatch(.evm), "bad evmDefaultAddress")
            var badTron = abandonIndex
            var tronArr = abandonIndex.arr("tronAddressIndex") ?? []
            if var t0 = tronArr.first?.objectValue { t0.set("address", .string(OV.TRX_STANDARD_1)); tronArr[0] = .object(t0); badTron.set("tronAddressIndex", .array(tronArr)) }
            same(try await verify(base, badTron, [.tron]), .mismatch(.tron), "bad tronAddressIndex[0]")

            // missing anchors fail closed, a missing SOL address is only skipped
            env.engine.reset()
            if case .ok(let noSol)? = try? await verify(with(base, solAddress: .some(nil))) {
                t(noSol.matches.contains(BILPublicVerifyMatch(key: "solana:standard", confirmed: false)) && noSol.ownbitAddresses["solana:standard"] == nil,
                  "no SOL → solana:standard false")
                eq(env.engine.calls.filter { $0.chain == "solana" }.count, 0, "no SOL → no engine SOL call")
            } else { t(false, "no SOL verifies") }
            same(try await verify(with(base, trxAddress: .some(nil), trxAddress0: .some(nil))), .mismatch(.tron), "no TRX row → mismatch")
            same(try await verify(with(base, ethXpub: .some(nil)), abandonIndex, [.evm]), .mismatch(.evm), "no ETH xpub → mismatch")
            same(try await verify(with(base, legacyXpub: .some(nil)), abandonIndex, [.bitcoin]), .mismatch(.bitcoin), "no BTC legacy → mismatch")
            same(try await verify(with(base, legacyXpub: "  "), abandonIndex, [.bitcoin]), .mismatch(.bitcoin), "blank legacy xpub = missing")
            if case .ok(let noNested)? = try? await verify(with(base, nestedXpub: .some(nil)), abandonIndex, [.bitcoin]) {
                t(!noNested.confirmed("bitcoin:nested") && noNested.confirmed("bitcoin:native"), "missing nested: false, chain still passes")
            } else { t(false, "missing nested verifies") }
            // D-10: TRON #0 source
            if case .ok? = try? await verify(with(base, trxAddress0: .some(nil)), abandonIndex, [.tron]) { t(true, "no trxAddress0 on TRX #0 → active address") }
            else { t(false, "no trxAddress0 on TRX #0 → active address") }
            same(try await verify(with(base, trxAddress: OV.TRX_OWNBIT_1, trxAddress0: .some(nil), trxIndex: 1), abandonIndex, [.tron]), .mismatch(.tron),
               "no trxAddress0 while on TRX #1 → fail closed")

            // Ownbit's TRX #1 is not the standard TRON #1 and is never compared on a standard index
            env.engine.reset()
            let standard1 = vectors.derivePublicAddresses(abandonIndex, "tron", nil, 1, 1)?.arr("addresses")?.first?.objectValue?.str("address")
            eq(standard1, OV.TRX_STANDARD_1, "engine TRON #1 (standard) = m/44'/195'/0'/0/1")
            if case .ok(let t1)? = try? await verify(env.abandonFacts(COLD, trxIndex: 1), abandonIndex, [.tron]) {
                eq(t1.matches, [BILPublicVerifyMatch(key: "tron:0", confirmed: true)], "standard index, TRX #1 active: only tron:0")
            } else { t(false, "standard index with TRX #1 verifies") }
            t(env.engine.calls.filter { $0.chain == "tron" && $0.index != 0 }.isEmpty, "never asks a standard index for TRON #N")

            // only the requested chains are checked
            env.engine.reset()
            env.deriver.bitcoinCalls = []
            _ = try await verify(base, abandonIndex, [.solana])
            eq(Set(env.engine.calls.compactMap { $0.chain }), ["solana"], "only SOLANA asked")
            t(env.deriver.bitcoinCalls.isEmpty, "no BTC bridge call")

            // an engine answer at the wrong path is malformed; engine / bridge failures propagate
            let confused = BILPublicIndexVerifier(engine: ConfusedEngine(vectors), deriver: env.deriver)
            do {
                _ = try await confused.verify(index: abandonIndex, facts: base, chains: [.bitcoin])
                t(false, "wrong path → malformed")
            } catch is BILMalformedEngineResult { t(true, "wrong path → BILMalformedEngineResult") }
            env.deriver.fail = true
            do {
                _ = try await verify(base, abandonIndex, [.bitcoin])
                t(false, "bridge failure propagates")
            } catch is BILOwnbitAddressDeriveError { t(true, "bridge failure propagates (not a mismatch)") }
            env.deriver.fail = false
            env.engine.refuse("derivePublicAddresses", "PUBLIC_INDEX")
            do {
                _ = try await verify(base, abandonIndex, [.evm])
                t(false, "engine refusal propagates")
            } catch let e as BILPublicSignerRefusal { eq(e.code, "PUBLIC_INDEX", "engine refusal propagates") }
            env.engine.refuse("derivePublicAddresses", nil)

            // the check keys
            eq(BILPairingExportPolicy.bitcoinKey(.native), "bitcoin:native", "bitcoinKey")
            eq(BILPairingExportPolicy.evmKey(7), "evm:7", "evmKey")
            eq(BILPairingExportPolicy.tronKey(0), "tron:0", "tronKey")
            eq(BILPairingExportPolicy.solanaStandardKey, "solana:standard", "solana key")
        }

        /// An engine that answers the Native SegWit page when asked for Legacy (Android "an engine answer at the wrong path").

        // MARK: - F. Repository (PublicIndexRepositoryTest)

        section("repository")
        runAsync { @MainActor in
            let env = Env(vectors)
            env.addWallet(COLD)
            let changes = Box<[String]>([])
            let observer = NotificationCenter.default.addObserver(forName: .publicIndexDidChange, object: nil, queue: nil) { n in
                if let id = n.object as? String { changes.update { $0.append(id + (Thread.isMainThread ? "@main" : "@bg")) } }
            }
            defer { NotificationCenter.default.removeObserver(observer) }

            // prepare builds, cross-checks, seals and stores the index
            same(await env.repository.status(walletId: COLD), .missing, "missing before prepare")
            env.engine.reset()
            same(await env.repository.prepare(walletId: COLD, password: Env.PASSWORD), .ready(fingerprint: "73C5DA0A"), "prepare → Ready")
            same(await env.repository.status(walletId: COLD), .ready(fingerprint: "73C5DA0A"), "status Ready")
            check(await env.repository.get(walletId: COLD) == ownbitIndex, "stored index = the engine's (deep equal)")
            let envl = env.envelope(COLD)
            eq(envl?.formatVersion, 1, "envelope formatVersion 1")
            eq(envl?.seedHashes, [BILPublicHash.sha256Hex(utf8: env.abandonSeed)], "seedHashes = [sha256] (the app wrote [sha256, md5]; no md5 here)")
            eq(envl?.createdAtMs, 1_760_000_000_000, "createdAt = now (ms)")
            let raw = String(decoding: env.keys.raw(COLD) ?? Data(), as: UTF8.self)
            let rawSealed = BILBase64Strict.decode(envl?.sealed ?? "").map { String(decoding: $0, as: Unicode.ASCII.self) } ?? ""
            t(["xpub", "73c5da0a", OV.TRX_0, "bitcoinPublicNodes", OV.ETH_0, OV.SOL].allSatisfy { !raw.contains($0) && !rawSealed.contains($0) },
              "no plaintext key / address / fingerprint in the stored bytes")
            eq(env.engine.count("derivePublicIndex"), 1, "exactly one derivation")
            eq(env.engine.calls.first { $0.op == "derivePublicIndex" }.map { [$0.tronScheme ?? "-", String($0.count ?? -1)] }, ["ownbit", "100"],
               "prepare asks for Ownbit's scheme, 100 addresses")
            eq(Set(env.engine.calls.compactMap { $0.chain }), ["bitcoin", "evm", "tron", "solana"], "cross-check on every chain")
            eq(env.directory.seedCalls, 1, "one seed access")
            t(changes.value.contains(COLD + "@main"), ".publicIndexDidChange posted on main after the seal")

            // a hot wallet prepares the same way
            env.addWallet(HOT, cold: false)
            same(await env.repository.prepare(walletId: HOT, password: Env.PASSWORD), .ready(fingerprint: "73C5DA0A"), "hot wallet → Ready")
            same(await env.repository.status(walletId: HOT), .ready(fingerprint: "73C5DA0A"), "hot status Ready")

            // ineligible wallets never get an index
            let before = env.engine.count("derivePublicIndex"), seedsBefore = env.directory.seedCalls
            env.addWallet("ms", traits: Env.traits(multisig: true))
            env.addWallet("watch", traits: Env.traits(cold: false, watch: true, seed: false))
            env.addWallet("custom", traits: Env.traits(cold: false, customPath: true))
            env.addWallet("electrum", traits: Env.traits(cold: false, electrum: true))
            env.addWallet("pk", traits: Env.traits(cold: false, privateKey: true, seed: false))
            env.addWallet("merchant", traits: Env.traits(cold: false, merchant: true))
            for id in ["ms", "watch", "custom", "electrum", "pk", "merchant", "absent"] {
                same(await env.repository.prepare(walletId: id, password: Env.PASSWORD), .notEligible, "prepare \(id) → notEligible")
                same(await env.repository.prepare(walletId: id, seedHex: env.abandonSeed), .notEligible, "prepare(seed) \(id) → notEligible")
                same(await env.repository.status(walletId: id), .notEligible, "status \(id) → notEligible")
                check(await env.repository.get(walletId: id) == nil, "get \(id) → nil")
            }
            eq(env.directory.seedCalls, seedsBefore, "ineligible: 0 seed accesses")
            eq(env.engine.count("derivePublicIndex"), before, "ineligible: 0 derivations")

            // resolver inputs list every eligible wallet once, in home order, with an index when authentic
            env.addWallet("hot02", cold: false)
            var inputs = await env.repository.resolverInputs()
            eq(inputs.map { $0.str("localWalletId") ?? "?" }, [COLD, HOT, "hot02"], "resolver: eligible wallets once, home order")
            t(inputs.first?.obj("publicIndex") == ownbitIndex && inputs.first?.keys == ["localWalletId", "publicIndex"], "resolver: authentic index attached")
            eq(inputs.last?.keys ?? [], ["localWalletId"], "resolver: no index yet → localWalletId only")

            // a cross-check mismatch stores nothing
            let mm = "xcoldmm00001"
            env.addWallet(mm, facts: with(env.abandonFacts(mm), ethXpub: OV.XPUB_ETH_LEGAL, ethAddress: OV.ETH_0_LEGAL.lowercased()))
            same(await env.repository.prepare(walletId: mm, password: Env.PASSWORD), .keysMismatch(.evm), "ETH xpub of another wallet → KeysMismatch(EVM)")
            t(env.keys.raw(mm) == nil, "mismatch: nothing stored")
            same(await env.repository.status(walletId: mm), .missing, "mismatch: status stays Missing")

            // a seed that is not the wallet's is refused before the engine
            let ws = "xcoldws00001"
            env.addWallet(ws, seed: env.legalSeed)
            let d0 = env.engine.count("derivePublicIndex")
            same(await env.repository.prepare(walletId: ws, password: Env.PASSWORD), .failed(.seedMismatch, engineCode: nil), "other seed → SEED_MISMATCH")
            eq(env.engine.count("derivePublicIndex"), d0, "seed mismatch: no engine call")
            t(env.keys.raw(ws) == nil, "seed mismatch: nothing stored")
            // iOS: an empty seedHash fails closed
            let eh = "xcoldeh00001"
            env.addWallet(eh, facts: with(env.abandonFacts(eh), seedHash: .some(nil)))
            same(await env.repository.prepare(walletId: eh, password: Env.PASSWORD), .failed(.seedMismatch, engineCode: nil), "empty seedHash → SEED_MISMATCH (D-08)")
            // a seed accessor that yields nothing / not seed hex
            let ns = "xcoldns00001"
            env.addWallet(ns)
            env.setFacts(ns) { $0.seed = nil }
            same(await env.repository.prepare(walletId: ns, password: Env.PASSWORD), .failed(.noSecret, engineCode: nil), "no seed → NO_SECRET")
            same(await env.repository.prepare(walletId: ns, seedHex: "abandon abandon"), .failed(.noSecret, engineCode: nil), "not seed hex → NO_SECRET, never the engine")

            // a tampered blob reads as needs repair, never re-derived
            let good = env.keys.raw(COLD) ?? Data()
            if let e = env.envelope(COLD), let sealedBytes = BILBase64Strict.decode(e.sealed) {
                var bytes = sealedBytes
                bytes[bytes.count / 2] ^= 0x01
                let bad = BILPublicIndexEnvelope(formatVersion: 1, seedHashes: e.seedHashes, createdAtMs: e.createdAtMs, sealed: BILBase64Strict.encode(bytes))
                env.keys.setRaw(COLD, bad.encoded())
            }
            let d1 = env.engine.count("derivePublicIndex")
            same(await env.repository.status(walletId: COLD), .needsRepair, "tampered → NeedsRepair")
            check(await env.repository.get(walletId: COLD) == nil, "tampered → get nil")
            let loaded = await env.repository.load(walletId: COLD)
            t(loaded.status == .needsRepair && loaded.index == nil, "tampered → load (NeedsRepair, nil)")
            eq(env.engine.count("derivePublicIndex"), d1, "no silent re-derive")
            inputs = await env.repository.resolverInputs()
            eq(inputs.first?.keys ?? [], ["localWalletId"], "tampered: resolver gets localWalletId only")
            same(await env.repository.prepare(walletId: COLD, password: Env.PASSWORD), .ready(fingerprint: "73C5DA0A"), "one password repairs it")
            same(await env.repository.status(walletId: COLD), .ready(fingerprint: "73C5DA0A"), "repaired → Ready")

            // a blob opens only for its own wallet id and kind
            env.addWallet(OTHER)
            env.keys.setRaw(OTHER, env.keys.raw(COLD))
            same(await env.repository.status(walletId: OTHER), .needsRepair, "entry copied to another wallet id → NeedsRepair")
            check(await env.repository.get(walletId: OTHER) == nil, "copied entry → get nil")
            env.setFacts(COLD) { $0.traits.isCold = false }
            same(await env.repository.status(walletId: COLD), .needsRepair, "kind cold → normal → NeedsRepair")
            env.setFacts(COLD) { $0.traits.isCold = true }
            same(await env.repository.status(walletId: COLD), .ready(fingerprint: "73C5DA0A"), "kind back → Ready")

            // a changed seed hash invalidates the index; an md5 seedHash is never accepted (package: no md5 hash gate)
            env.setFacts(COLD) { $0.facts = with($0.facts, seedHash: BILPublicHash.sha256Hex(utf8: env.legalSeed)) }
            same(await env.repository.status(walletId: COLD), .needsRepair, "seedHash changed → NeedsRepair")
            check(await env.repository.get(walletId: COLD) == nil, "seedHash changed → get nil")
            env.setFacts(COLD) { $0.facts = with($0.facts, seedHash: .some(nil)) }
            same(await env.repository.status(walletId: COLD), .needsRepair, "empty seedHash on read → NeedsRepair (fail closed)")
            let md = "xcoldmd50001"
            env.addWallet(md, facts: env.abandonFacts(md, seedHash: legacyHash))
            same(await env.repository.prepare(walletId: md, password: Env.PASSWORD), .failed(.seedMismatch, engineCode: nil),
                 "a wallet with an old (md5-length) seedHash does not prepare (the app accepted md5)")
            same(await env.repository.status(walletId: md), .missing, "…nothing stored")
            env.setFacts(md) { $0.facts = with($0.facts, seedHash: BILPublicHash.sha256Hex(utf8: env.abandonSeed)) }
            same(await env.repository.prepare(walletId: md, password: Env.PASSWORD), .ready(fingerprint: "73C5DA0A"), "with its sha256 seedHash it prepares")
            same(await env.repository.status(walletId: md), .ready(fingerprint: "73C5DA0A"), "→ Ready")
            env.setFacts(COLD) { $0.facts = env.abandonFacts(COLD) }
            env.keys.setRaw(COLD, good)
            same(await env.repository.status(walletId: COLD), .ready(fingerprint: "73C5DA0A"), "original entry Ready again")

            // a lost key reads as needs repair and one password rebuilds it
            env.keys.loseKey()
            same(await env.repository.status(walletId: COLD), .needsRepair, "lost key → NeedsRepair")
            same(await env.repository.status(walletId: HOT), .needsRepair, "lost key → every entry NeedsRepair")
            same(await env.repository.prepare(walletId: COLD, password: Env.PASSWORD), .ready(fingerprint: "73C5DA0A"), "prepare rebuilds with a new key")
            check(await env.repository.get(walletId: COLD) == ownbitIndex, "rebuilt index = the engine's")
            // an unusable (wrong length) key is replaced at seal time
            env.keys.rawKey = Data(repeating: 7, count: 16)
            same(await env.repository.status(walletId: COLD), .needsRepair, "unusable key → NeedsRepair (not transient)")
            let replaced = env.keys.keyReplacements
            same(await env.repository.prepare(walletId: COLD, password: Env.PASSWORD), .ready(fingerprint: "73C5DA0A"), "prepare with an unusable key → Ready")
            eq(env.keys.keyReplacements, replaced + 1, "unusable key replaced once")

            // an unknown format version or a malformed index needs repair
            if let e = env.envelope(COLD) {
                env.keys.setRaw(COLD, BILPublicIndexEnvelope(formatVersion: 2, seedHashes: e.seedHashes, createdAtMs: e.createdAtMs, sealed: e.sealed).encoded())
                same(await env.repository.status(walletId: COLD), .needsRepair, "formatVersion 2 → NeedsRepair")
                if let k = try? env.keys.key(create: false),   // Swift 5: try? flattens the optional
                   let notAnIndex = try? BILPublicIndexSealer.seal(Data(#"{"version":1,"masterFingerprint":"73c5da0a"}"#.utf8), key: k, walletId: COLD, kind: .cold) {
                    env.keys.setRaw(COLD, BILPublicIndexEnvelope(formatVersion: 1, seedHashes: e.seedHashes, createdAtMs: 1,
                                                                 sealed: BILBase64Strict.encode([UInt8](notAnIndex))).encoded())
                    same(await env.repository.status(walletId: COLD), .needsRepair, "authentic but not an index → NeedsRepair")
                    check(await env.repository.get(walletId: COLD) == nil, "not an index → get nil")
                    let dup = try? BILPublicIndexSealer.seal(Data(#"{"version":1,"version":1}"#.utf8), key: k, walletId: COLD, kind: .cold)
                    env.keys.setRaw(COLD, BILPublicIndexEnvelope(formatVersion: 1, seedHashes: e.seedHashes, createdAtMs: 1,
                                                                 sealed: BILBase64Strict.encode([UInt8](dup ?? Data()))).encoded())
                    same(await env.repository.status(walletId: COLD), .needsRepair, "duplicate keys in the sealed JSON → NeedsRepair")
                } else { t(false, "test key available") }
                env.keys.setRaw(COLD, Data("garbage".utf8))
                same(await env.repository.status(walletId: COLD), .needsRepair, "garbage entry → NeedsRepair")
                env.keys.setRaw(COLD, BILPublicIndexEnvelope(formatVersion: 1, seedHashes: e.seedHashes, createdAtMs: 1, sealed: "not base64!").encoded())
                same(await env.repository.status(walletId: COLD), .needsRepair, "sealed not base64 → NeedsRepair")
            }
            _ = await env.repository.prepare(walletId: COLD, password: Env.PASSWORD)

            // engine refusals and failures store nothing
            let rf = "xcoldrf00001"
            env.addWallet(rf)
            env.engine.refuse("derivePublicIndex", "SEED")
            same(await env.repository.prepare(walletId: rf, password: Env.PASSWORD), .failed(.engine, engineCode: "SEED"), "derive refused → Failed(ENGINE, SEED)")
            env.engine.refuse("derivePublicIndex", nil)
            env.engine.refuse("derivePublicAddresses", "PUBLIC_INDEX")
            same(await env.repository.prepare(walletId: rf, password: Env.PASSWORD), .failed(.engine, engineCode: "PUBLIC_INDEX"), "cross-check refused → Failed(ENGINE, PUBLIC_INDEX)")
            env.engine.refuse("derivePublicAddresses", nil)
            env.deriver.fail = true
            same(await env.repository.prepare(walletId: rf, password: Env.PASSWORD), .failed(.engine, engineCode: nil), "bridge timeout → Failed(ENGINE), not a mismatch")
            env.deriver.fail = false
            t(env.keys.raw(rf) == nil, "refusals: nothing stored")
            env.keys.writeError = errSecIO
            same(await env.repository.prepare(walletId: rf, password: Env.PASSWORD), .failed(.storage, engineCode: nil), "Keychain write failure → Failed(STORAGE)")
            env.keys.writeError = nil
            t(env.keys.raw(rf) == nil, "write failure: nothing stored")

            // the engine must answer in Ownbit's scheme with exactly the asked TRON count (spec §4.2 #4), checked before the cross-check
            let ly = "xcoldly00001"
            env.addWallet(ly)
            env.engine.deriveOverride = abandonIndex                // a lying engine: the standard (round-1) index for an Ownbit request
            env.engine.reset()
            same(await env.repository.prepare(walletId: ly, password: Env.PASSWORD), .failed(.engine, engineCode: nil),
                 "standard index for an Ownbit request → Failed(ENGINE)")
            t(env.keys.raw(ly) == nil, "lying engine (scheme): nothing stored")
            eq(env.engine.count("derivePublicAddresses"), 0, "lying engine (scheme): refused before the cross-check")
            let lc = "xcoldlc00001"
            env.addWallet(lc, facts: with(env.abandonFacts(lc), trxAddress: OV.TRX_OWNBIT_1, trxIndex: 150))
            env.engine.deriveOverride = ownbitIndex                 // Ownbit's scheme, but 100 addresses where 151 were asked
            env.engine.reset()
            same(await env.repository.prepare(walletId: lc, password: Env.PASSWORD), .failed(.engine, engineCode: nil),
                 "Ownbit index with another TRON count → Failed(ENGINE)")
            eq(env.engine.calls.first { $0.op == "derivePublicIndex" }?.count, 151, "TRX #150 asks for 151 addresses")
            eq(env.engine.count("derivePublicAddresses"), 0, "lying engine (count): refused before the cross-check")
            t(env.keys.raw(lc) == nil, "lying engine (count): nothing stored")
            env.engine.deriveOverride = nil

            // a wallet that stops being eligible while the engine derives is not sealed (re-checked after the derivation)
            let kc = "xcoldkc00001"
            env.addWallet(kc)
            env.engine.deriveDelay = 0.5
            env.engine.reset()
            async let changedLate = env.repository.prepare(walletId: kc, password: Env.PASSWORD)
            try? await Task.sleep(nanoseconds: 200_000_000)
            eq(env.engine.count("derivePublicIndex"), 1, "eligibility change lands while the engine derives")
            env.setFacts(kc) { $0.traits.isMultisig = true }
            same(await changedLate, .notEligible, "no longer eligible after the derivation → NotEligible")
            t(env.keys.raw(kc) == nil, "no longer eligible: nothing sealed")
            eq(env.engine.count("derivePublicAddresses"), 0, "no longer eligible: no cross-check")
            env.engine.deriveDelay = 0

            // without a usable engine the status says so and prepare does not unlock
            env.engine.available = false
            let seeds = env.directory.seedCalls, derives = env.engine.count("derivePublicIndex")
            same(await env.repository.status(walletId: COLD), .unavailable, "engine unavailable → Unavailable")
            same(await env.repository.prepare(walletId: COLD, password: Env.PASSWORD), .failed(.engineUnavailable, engineCode: nil), "prepare → Failed(ENGINE_UNAVAILABLE)")
            same(await env.repository.prepare(walletId: COLD, seedHex: env.abandonSeed), .failed(.engineUnavailable, engineCode: nil), "prepare(seed) → Failed(ENGINE_UNAVAILABLE)")
            eq(env.directory.seedCalls, seeds, "engine unavailable: 0 unlocks")
            eq(env.engine.count("derivePublicIndex"), derives, "engine unavailable: 0 derivations")
            same(await env.repository.status(walletId: "ms"), .notEligible, "not-eligible wins over unavailable")
            let ld = await env.repository.load(walletId: COLD)
            eq(ld.status, .ready(fingerprint: "73C5DA0A"), "load reads without the engine gate (Android)")
            env.engine.available = true

            // builds are serialized (one global write lock)
            let c1 = "xcoldcc00001", c2 = "xcoldcc00002"
            env.addWallet(c1)
            env.addWallet(c2)
            env.engine.deriveDelay = 0.2
            env.engine.reset()
            async let r1 = env.repository.prepare(walletId: c1, password: Env.PASSWORD)
            async let r2 = env.repository.prepare(walletId: c2, password: Env.PASSWORD)
            let both = await [r1, r2]
            eq(both, [.ready(fingerprint: "73C5DA0A"), .ready(fingerprint: "73C5DA0A")], "two concurrent prepares both Ready")
            eq(env.engine.maxConcurrentDerive, 1, "derivations never overlap")
            env.engine.deriveDelay = 0
        }

        // MARK: - G. Eager COLD build (PublicIndexBuilderImplTest, D-09)

        section("eager")
        runAsync { @MainActor in
            let env = Env(vectors)
            env.addWallet(COLD)
            env.engine.deriveDelay = 0.4
            env.repository.startEagerBuild(walletId: COLD, kind: .cold, seedHex: env.abandonSeed)
            // status right away waits for the in-flight build (page B never shows "Prepare" for it)
            same(await env.repository.status(walletId: COLD), .ready(fingerprint: "73C5DA0A"), "status awaits the eager build → Ready without a password")
            eq(env.directory.seedCalls, 0, "no seed access / password")
            t(env.keys.raw(COLD) != nil, "eager build stored the entry")
            env.engine.deriveDelay = 0
            // load also waits
            let c2 = "xcoldea00002"
            env.addWallet(c2)
            env.engine.deriveDelay = 0.3
            env.repository.startEagerBuild(walletId: c2, kind: .cold, seedHex: env.abandonSeed)
            let l = await env.repository.load(walletId: c2)
            t(l.status == .ready(fingerprint: "73C5DA0A") && l.index == ownbitIndex, "load awaits the eager build")
            env.engine.deriveDelay = 0

            // hot wallets are left for Prepare, other kinds are skipped quietly
            env.engine.reset()
            env.addWallet(HOT, cold: false)
            env.repository.startEagerBuild(walletId: HOT, kind: .normal, seedHex: env.abandonSeed)
            same(await env.repository.status(walletId: HOT), .missing, "NORMAL: no eager build (EAGER_KINDS = {COLD})")
            env.addWallet("ms", traits: Env.traits(multisig: true))
            env.repository.startEagerBuild(walletId: "ms", kind: .cold, seedHex: env.abandonSeed)
            _ = await env.repository.status(walletId: "ms")
            t(env.keys.raw("ms") == nil, "multisig: nothing stored, quietly")
            // the stored kind must match
            env.repository.startEagerBuild(walletId: HOT, kind: .cold, seedHex: env.abandonSeed)
            _ = await env.repository.status(walletId: HOT)
            t(env.keys.raw(HOT) == nil, "eager COLD for a NORMAL wallet → NotEligible, nothing stored")
            eq(env.engine.count("derivePublicIndex"), 0, "no derivation for skipped kinds")

            // a failed build is swallowed; creation never fails
            let f1 = "xcoldfa00001"
            env.addWallet(f1)
            env.engine.refuse("derivePublicIndex", "SEED")
            env.repository.startEagerBuild(walletId: f1, kind: .cold, seedHex: env.abandonSeed)
            same(await env.repository.status(walletId: f1), .missing, "engine refusal swallowed → Missing (Prepare card)")
            env.engine.refuse("derivePublicIndex", nil)
            env.repository.startEagerBuild(walletId: f1, kind: .cold, seedHex: env.legalSeed)
            same(await env.repository.status(walletId: f1), .missing, "wrong seed swallowed → Missing")
            t(env.keys.raw(f1) == nil, "failed eager builds store nothing")

            // a removed wallet's in-flight build is cancelled before it seals (forget, e.g. a creation rollback); the fake engine's
            // delay is not cancellable (like the synchronous JS call), so only the repository's checks stop the seal
            let rb = "xcoldrb00001"
            env.addWallet(rb)
            env.engine.deriveDelay = 0.5
            env.engine.reset()
            env.repository.startEagerBuild(walletId: rb, kind: .cold, seedHex: env.abandonSeed)
            try? await Task.sleep(nanoseconds: 100_000_000)
            eq(env.engine.count("derivePublicIndex"), 1, "forget lands while the engine derives")
            env.repository.forget(walletId: rb)
            try? await Task.sleep(nanoseconds: 900_000_000)
            t(env.keys.raw(rb) == nil, "forget cancels the in-flight build: nothing sealed")
            env.engine.deriveDelay = 0

            // an eager build past its bound (EAGER_TIMEOUT) is given up: the read stops waiting, the late build never seals
            let to = "xcoldto00001"
            env.addWallet(to)
            env.repository.eagerBuildTimeout = 0.2
            env.engine.deriveDelay = 0.6
            env.engine.reset()
            let timedStart = Date()
            env.repository.startEagerBuild(walletId: to, kind: .cold, seedHex: env.abandonSeed)
            same(await env.repository.status(walletId: to), .missing, "expired eager build → status Missing (Prepare card)")
            t(Date().timeIntervalSince(timedStart) < 0.5, "status waits at most the eager bound")
            try? await Task.sleep(nanoseconds: 900_000_000)
            t(PPStubLog.lines.contains("error: PublicProtocol index: EAGER_TIMEOUT"), "EAGER_TIMEOUT logged")
            eq(env.engine.count("derivePublicIndex"), 1, "the expired build did derive (engine not interruptible)")
            t(env.keys.raw(to) == nil, "an expired eager build never seals")
            env.repository.eagerBuildTimeout = BILPublicIndexRepository.eagerTimeout
            env.engine.deriveDelay = 0

            // a build cancelled while it waits for the write lock never derives: the seed never reaches the engine (Android Mutex)
            let pa = "xcoldpa00001", pb = "xcoldpb00001"
            env.addWallet(pa)
            env.addWallet(pb)
            env.engine.deriveDelay = 0.5
            env.engine.reset()
            async let holder = env.repository.prepare(walletId: pa, password: Env.PASSWORD)    // holds the lock ~0.5 s
            try? await Task.sleep(nanoseconds: 100_000_000)
            env.repository.startEagerBuild(walletId: pb, kind: .cold, seedHex: env.abandonSeed)              // queues behind it
            try? await Task.sleep(nanoseconds: 100_000_000)
            env.repository.forget(walletId: pb)                                                                // wallet removed
            same(await holder, .ready(fingerprint: "73C5DA0A"), "the lock holder completes")
            try? await Task.sleep(nanoseconds: 300_000_000)
            eq(env.engine.count("derivePublicIndex"), 1, "cancelled while waiting for the lock: no derivation")
            t(env.keys.raw(pb) == nil, "cancelled while waiting for the lock: nothing stored")
            eq(env.directory.factsReads[pb] ?? 0, 0, "cancelled while waiting for the lock: the locked body never ran")
            env.engine.deriveDelay = 0
            // cancelled after it got the lock, right before the engine call (bound expired / wallet removed at that moment)
            let pc = "xcoldpc00001"
            env.addWallet(pc)
            env.engine.reset()
            env.directory.onFactsRead = { id in
                if id == pc { env.repository.forget(walletId: pc) }
            }
            env.repository.startEagerBuild(walletId: pc, kind: .cold, seedHex: env.abandonSeed)
            check(await waitUntil(2) { (env.directory.factsReads[pc] ?? 0) > 0 }, "the build reached the locked body")
            try? await Task.sleep(nanoseconds: 200_000_000)
            env.directory.onFactsRead = nil
            eq(env.engine.count("derivePublicIndex"), 0, "cancelled inside the lock before the engine call: no derivation")
            t(env.keys.raw(pc) == nil, "cancelled inside the lock: nothing stored")

            // the resolver and get wait for an in-flight eager build too (Android builds before the creation returns)
            let rs = "xcoldrs00001"
            env.addWallet(rs)
            env.engine.deriveDelay = 0.3
            env.repository.startEagerBuild(walletId: rs, kind: .cold, seedHex: env.abandonSeed)
            let rsInputs = await env.repository.resolverInputs()
            t(rsInputs.first { $0.str("localWalletId") == rs }?.obj("publicIndex") == ownbitIndex, "resolverInputs awaits the eager build (index attached)")
            let gt = "xcoldgt00001"
            env.addWallet(gt)
            env.repository.startEagerBuild(walletId: gt, kind: .cold, seedHex: env.abandonSeed)
            check(await env.repository.get(walletId: gt) == ownbitIndex, "get awaits the eager build")
            env.engine.deriveDelay = 0

            // orphan cleanup never deletes the entry of a wallet whose eager build is in flight (row not listed yet)
            let ok1 = "xcoldok00001"
            env.addWallet(ok1)
            env.directory.unlistedIds = [ok1]
            env.keys.setRaw(ok1, Data("stale".utf8))
            env.engine.deriveDelay = 0.4
            env.repository.startEagerBuild(walletId: ok1, kind: .cold, seedHex: env.abandonSeed)
            let swept = await env.repository.runOrphanCleanup()
            t(swept != nil && !(swept ?? []).contains(ok1), "orphan cleanup skips a wallet whose eager build is in flight")
            eq(env.keys.raw(ok1), Data("stale".utf8), "in-flight wallet's entry kept by the cleanup")
            same(await env.repository.status(walletId: ok1), .ready(fingerprint: "73C5DA0A"), "the build then seals it")
            env.directory.unlistedIds = []
            env.engine.deriveDelay = 0
        }

        // MARK: - G2. The eager build releases its warm PAIRING context (lead addendum D3, WP26)

        /// A pairing panel's owner for `registerPairingPanel` (the tabs host in the app).

        section("eager-release")
        runAsync { @MainActor in
            let env = Env(vectors)
            let engine = env.engine
            @MainActor func build(_ id: String, refuse: Bool = false) async {
                env.addWallet(id)
                engine.refuse("derivePublicIndex", refuse ? "SEED" : nil)
                env.repository.startEagerBuild(walletId: id, kind: .cold, seedHex: env.abandonSeed)
                _ = await env.repository.status(walletId: id)
                engine.refuse("derivePublicIndex", nil)
            }

            // no pairing panel anywhere (COLD import → BILCreateWalletSuccessController): released at the end of the build
            await build("xcoldre00001")
            t(env.keys.raw("xcoldre00001") != nil, "eager build stored the entry")
            check(await waitUntil(2) { engine.releases == 1 }, "end of the eager build, no panel: the warm PAIRING context released once")
            // any result (the probe / cross-check may have created the context): a refused build releases too
            await build("xcoldre00002", refuse: true)
            check(await waitUntil(2) { engine.releases == 2 }, "a failed eager build releases too")
            t(!env.repository.isPairingPanelActive, "nothing registered → no active panel")

            // a registered panel that is active keeps the context; inactive / gone ones do not
            let owner = PanelOwner()
            env.repository.registerPairingPanel(owner: owner) { [weak owner] in owner?.active ?? false }
            t(!env.repository.isPairingPanelActive, "registered, not activated → not active")
            owner.active = true
            t(env.repository.isPairingPanelActive, "registered and activated → active")
            await build("xcoldre00003")
            try? await Task.sleep(nanoseconds: 300_000_000)
            eq(engine.releases, 2, "end of the eager build with an active pairing panel (page B tab 2): context kept")
            owner.active = false
            await build("xcoldre00004")
            check(await waitUntil(2) { engine.releases == 3 }, "the panel left (inactive again): released")

            // the probe is read when the build ends, not when it starts
            engine.deriveDelay = 0.3
            env.addWallet("xcoldre00005")
            env.repository.startEagerBuild(walletId: "xcoldre00005", kind: .cold, seedHex: env.abandonSeed)
            try? await Task.sleep(nanoseconds: 100_000_000)
            owner.active = true                                       // tab 2 opened while the build runs
            _ = await env.repository.status(walletId: "xcoldre00005")
            try? await Task.sleep(nanoseconds: 300_000_000)
            eq(engine.releases, 3, "a panel activated during the build keeps the context")
            env.addWallet("xcoldre00006")
            env.repository.startEagerBuild(walletId: "xcoldre00006", kind: .cold, seedHex: env.abandonSeed)
            try? await Task.sleep(nanoseconds: 100_000_000)
            owner.active = false                                      // the page went away during the build
            _ = await env.repository.status(walletId: "xcoldre00006")
            check(await waitUntil(2) { engine.releases == 4 }, "a panel that left during the build: released at its end")
            engine.deriveDelay = 0

            // a dead owner's probe counts for nothing, even if its closure would say "active"
            do {
                let gone = PanelOwner()
                env.repository.registerPairingPanel(owner: gone) { true }
            }
            t(!env.repository.isPairingPanelActive, "the owner is gone → its probe is ignored")
            await build("xcoldre00007")
            check(await waitUntil(2) { engine.releases == 5 }, "dead owner: released")
            owner.active = true
            t(env.repository.isPairingPanelActive, "a live owner registered earlier still counts")
            owner.active = false

            // fire and forget: a reader waiting for the build never waits for a busy engine actor's release too
            engine.releaseDelay = 1.0
            env.addWallet("xcoldre00008")
            let start = Date()
            env.repository.startEagerBuild(walletId: "xcoldre00008", kind: .cold, seedHex: env.abandonSeed)
            same(await env.repository.status(walletId: "xcoldre00008"), .ready(fingerprint: "73C5DA0A"), "status after the build")
            t(Date().timeIntervalSince(start) < 0.8, "status does not wait for the release")
            check(await waitUntil(3) { engine.releases == 6 }, "the release lands later")
            engine.releaseDelay = 0

            // an expired build (EAGER_TIMEOUT) still releases at its end
            env.repository.eagerBuildTimeout = 0.2
            engine.deriveDelay = 0.6
            env.addWallet("xcoldre00009")
            env.repository.startEagerBuild(walletId: "xcoldre00009", kind: .cold, seedHex: env.abandonSeed)
            same(await env.repository.status(walletId: "xcoldre00009"), .missing, "expired eager build → Missing")
            check(await waitUntil(2) { engine.releases == 7 }, "an expired eager build releases at its end too")
            try? await Task.sleep(nanoseconds: 700_000_000)        // the late engine answer comes back and is never sealed
            env.repository.eagerBuildTimeout = BILPublicIndexRepository.eagerTimeout
            engine.deriveDelay = 0

            // not COLD → no eager build → nothing released
            env.addWallet("hotre0001", cold: false)
            env.repository.startEagerBuild(walletId: "hotre0001", kind: .normal, seedHex: env.abandonSeed)
            _ = await env.repository.status(walletId: "hotre0001")
            try? await Task.sleep(nanoseconds: 200_000_000)
            eq(engine.releases, 7, "NORMAL: no eager build, nothing released")
        }

        // MARK: - G3. The eager build in the background (lead addendum G1 b, WP29)

        /// The system background time and the app's state (UIApplication in the app, BILPublicLiveBackgroundExecution).

        section("eager-background")
        runAsync { @MainActor in
            let env = Env(vectors)
            let bg = FakeBackgroundExecution()
            env.repository.backgroundExecution = bg
            @MainActor func pause(_ seconds: Double) async {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            }

            // the build runs inside one system background task, begun at the start and ended exactly once at its end
            env.addWallet("xcoldbg00001")
            env.engine.deriveDelay = 0.2
            env.repository.startEagerBuild(walletId: "xcoldbg00001", kind: .cold, seedHex: env.abandonSeed)
            eq(bg.begun, ["BILPublicIndexEagerBuild"], "background task begun synchronously when the build starts")
            eq(bg.ended, [], "… and still running while the build runs")
            same(await env.repository.status(walletId: "xcoldbg00001"), .ready(fingerprint: "73C5DA0A"), "the build seals (Ready)")
            check(await waitUntil(2) { bg.ended == [1] }, "background task ended once the build ended")
            await pause(0.2)
            eq(bg.ended, [1], "… exactly once")

            // a failed build ends its task too (once)
            env.addWallet("xcoldbg00002")
            env.engine.refuse("derivePublicIndex", "SEED")
            env.repository.startEagerBuild(walletId: "xcoldbg00002", kind: .cold, seedHex: env.abandonSeed)
            same(await env.repository.status(walletId: "xcoldbg00002"), .missing, "refused build → Missing")
            env.engine.refuse("derivePublicIndex", nil)
            check(await waitUntil(2) { bg.ended == [1, 2] }, "a failed build ends its background task")
            await pause(0.1)
            eq(bg.ended, [1, 2], "… exactly once")

            // no eager build → no background task
            env.addWallet("hotbg0001", cold: false)
            env.repository.startEagerBuild(walletId: "hotbg0001", kind: .normal, seedHex: env.abandonSeed)
            eq(bg.begun.count, 2, "NORMAL: no background task")

            // the system gives no background time: the build still runs, nothing to end
            bg.refuse = true
            env.addWallet("xcoldbg00003")
            env.repository.startEagerBuild(walletId: "xcoldbg00003", kind: .cold, seedHex: env.abandonSeed)
            same(await env.repository.status(walletId: "xcoldbg00003"), .ready(fingerprint: "73C5DA0A"), "no background time given: built anyway")
            await pause(0.1)
            eq(bg.begun.count, 3, "asked once")
            eq(bg.ended, [1, 2], "nothing ended for a refused task")
            bg.refuse = false

            // the system's background time runs out mid-build: the expiration handler ends the task at once, the build goes on
            env.addWallet("xcoldbg00004")
            env.engine.deriveDelay = 0.4
            env.repository.startEagerBuild(walletId: "xcoldbg00004", kind: .cold, seedHex: env.abandonSeed)
            let expiringId = bg.lastId
            await pause(0.1)
            bg.expire(expiringId)
            eq(bg.ended, [1, 2, expiringId], "expiration handler: the task is ended right away")
            same(await env.repository.status(walletId: "xcoldbg00004"), .ready(fingerprint: "73C5DA0A"), "the build goes on and seals after the expiry")
            await pause(0.2)
            eq(bg.ended, [1, 2, expiringId], "the end of the build does not end it a second time")
            bg.expire(expiringId)
            eq(bg.ended, [1, 2, expiringId], "a repeated expiry does not end it again")

            // bound runs out in the foreground (no background involved): given up as before, never seals, task ended once
            let timeouts0 = logCount("EAGER_TIMEOUT"), extended0 = logCount("EAGER_EXTENDED")
            env.repository.eagerBuildTimeout = 0.2
            env.engine.deriveDelay = 0.6
            env.addWallet("xcoldbg00005")
            env.repository.startEagerBuild(walletId: "xcoldbg00005", kind: .cold, seedHex: env.abandonSeed)
            let fgId = bg.lastId
            same(await env.repository.status(walletId: "xcoldbg00005"), .missing, "foreground expiry → Missing (Prepare card)")
            await pause(0.7)
            t(env.keys.raw("xcoldbg00005") == nil, "foreground expiry: never seals")
            eq(logCount("EAGER_TIMEOUT"), timeouts0 + 1, "EAGER_TIMEOUT logged")
            eq(logCount("EAGER_EXTENDED"), extended0, "not extended")
            eq(bg.ended.filter { $0 == fgId }.count, 1, "its background task ended once")

            // the app went to the background (and came back) while the bound ran: the build goes on and seals
            env.repository.eagerBuildTimeout = 0.45
            env.engine.deriveDelay = 0.6
            env.addWallet("xcoldbg00006")
            let started6 = Date()
            env.repository.startEagerBuild(walletId: "xcoldbg00006", kind: .cold, seedHex: env.abandonSeed)
            let bgId6 = bg.lastId
            await pause(0.1)
            bg.enterBackground()
            await pause(0.1)
            bg.enterForeground()
            await pause(0.32)                                            // the bound (0.45 s) has run out meanwhile
            t(Date().timeIntervalSince(started6) > 0.46, "past the first bound")
            let status6 = await env.repository.status(walletId: "xcoldbg00006")   // a reader after the extension waits for it
            same(status6, .ready(fingerprint: "73C5DA0A"), "background during the bound: the build went on and sealed (Ready)")
            t(env.keys.raw("xcoldbg00006") != nil, "entry stored")
            eq(logCount("EAGER_EXTENDED"), extended0 + 1, "EAGER_EXTENDED logged once")
            eq(logCount("EAGER_TIMEOUT"), timeouts0 + 1, "no EAGER_TIMEOUT for it")
            check(await waitUntil(2) { bg.ended.filter { $0 == bgId6 }.count == 1 }, "its background task ended once at the end")

            // still in the background when the bound runs out (the app was not suspended yet): extended too
            env.repository.eagerBuildTimeout = 0.4
            env.engine.deriveDelay = 0.5
            env.addWallet("xcoldbg00007")
            env.repository.startEagerBuild(walletId: "xcoldbg00007", kind: .cold, seedHex: env.abandonSeed)
            await pause(0.1)
            bg.enterBackground()
            check(await waitUntil(3) { env.keys.raw("xcoldbg00007") != nil }, "in the background at the bound: sealed")
            bg.enterForeground()
            eq(logCount("EAGER_EXTENDED"), extended0 + 2, "extended")

            // started while the app was already in the background (no new entry): extended
            env.repository.eagerBuildTimeout = 0.3
            env.engine.deriveDelay = 0.35
            bg.isInBackground = true
            env.addWallet("xcoldbg00008")
            env.repository.startEagerBuild(walletId: "xcoldbg00008", kind: .cold, seedHex: env.abandonSeed)
            await pause(0.1)
            bg.enterForeground()
            check(await waitUntil(3) { env.keys.raw("xcoldbg00008") != nil }, "started in the background: sealed")
            eq(logCount("EAGER_EXTENDED"), extended0 + 3, "extended")

            // started in the background, back in the foreground within the first bound, then stuck: extended once (it started
            // there), then given up after the fresh bound — the extension resets "started in the background"
            let timeouts13 = logCount("EAGER_TIMEOUT"), extended13 = logCount("EAGER_EXTENDED")
            env.repository.eagerBuildTimeout = 0.3
            env.engine.deriveDelay = 1.0
            bg.isInBackground = true
            env.addWallet("xcoldbg00013")
            let started13 = Date()
            env.repository.startEagerBuild(walletId: "xcoldbg00013", kind: .cold, seedHex: env.abandonSeed)
            let bgId13 = bg.lastId
            await pause(0.1)
            bg.enterForeground()
            check(await waitUntil(2) { logCount("EAGER_TIMEOUT") == timeouts13 + 1 }, "started in the background, then stuck in the foreground: EAGER_TIMEOUT")
            let elapsed13 = Date().timeIntervalSince(started13)
            t(elapsed13 > 0.55 && elapsed13 < 0.95, "… after the fresh bound (≈ 0.6 s; \(String(format: "%.2f", elapsed13)) s)")
            eq(logCount("EAGER_EXTENDED"), extended13 + 1, "exactly one extension")
            same(await env.repository.status(walletId: "xcoldbg00013"), .missing, "given up → Missing")
            await pause(0.6)                                             // the late engine answer comes back (1.0 s)
            t(env.keys.raw("xcoldbg00013") == nil, "given up: never seals")
            eq(bg.ended.filter { $0 == bgId13 }.count, 1, "its background task ended once")

            // a reader already waiting when the app goes to the background (and comes back) waits for the extended build
            // (awaitEagerBuild is bounded like the build): Ready, not the Missing of a reader that gave up at the first bound
            env.repository.eagerBuildTimeout = 0.45
            env.engine.deriveDelay = 0.6
            env.addWallet("xcoldbg00014")
            let extended14 = logCount("EAGER_EXTENDED")
            env.repository.startEagerBuild(walletId: "xcoldbg00014", kind: .cold, seedHex: env.abandonSeed)
            let reader14 = Task { @MainActor in await env.repository.status(walletId: "xcoldbg00014") }
            await pause(0.1)
            bg.enterBackground()
            await pause(0.1)
            bg.enterForeground()
            let status14 = await reader14.value
            same(status14, .ready(fingerprint: "73C5DA0A"), "a reader waiting across the background: Ready once the extended build sealed")
            eq(logCount("EAGER_EXTENDED"), extended14 + 1, "the build was extended")

            // a reader waiting in the foreground only still stops at its bound (the build started in the background, so it is
            // extended; the reader started in the foreground and saw no background: it reads Missing at its bound, as before)
            env.repository.eagerBuildTimeout = 0.3
            env.engine.deriveDelay = 0.5
            bg.isInBackground = true
            env.addWallet("xcoldbg00015")
            env.repository.startEagerBuild(walletId: "xcoldbg00015", kind: .cold, seedHex: env.abandonSeed)
            await pause(0.05)                                            // the build has started (in the background)
            bg.enterForeground()
            let started15 = Date()
            let status15 = await env.repository.status(walletId: "xcoldbg00015")
            let waited15 = Date().timeIntervalSince(started15)
            same(status15, .missing, "a foreground-only reader stops at its bound")
            t(waited15 > 0.25, "… after ≈ 0.3 s (\(String(format: "%.2f", waited15)) s)")
            check(await waitUntil(2) { env.keys.raw("xcoldbg00015") != nil }, "the build itself was extended and sealed")

            // extended once, then stuck in the foreground for a whole fresh bound: given up (a hung build stays bounded)
            let timeouts9 = logCount("EAGER_TIMEOUT"), extended9 = logCount("EAGER_EXTENDED")
            env.repository.eagerBuildTimeout = 0.3
            env.engine.deriveDelay = 1.0
            env.addWallet("xcoldbg00009")
            env.repository.startEagerBuild(walletId: "xcoldbg00009", kind: .cold, seedHex: env.abandonSeed)
            let bgId9 = bg.lastId
            await pause(0.1)
            bg.enterBackground()
            await pause(0.05)
            bg.enterForeground()
            check(await waitUntil(2) { logCount("EAGER_TIMEOUT") == timeouts9 + 1 }, "the fresh bound ran out in the foreground: EAGER_TIMEOUT")
            eq(logCount("EAGER_EXTENDED"), extended9 + 1, "after one extension")
            same(await env.repository.status(walletId: "xcoldbg00009"), .missing, "given up → Missing")
            await pause(0.8)                                             // the late engine answer comes back
            t(env.keys.raw("xcoldbg00009") == nil, "given up after the fresh bound: never seals")
            eq(bg.ended.filter { $0 == bgId9 }.count, 1, "its background task ended once")

            // two background visits → two extensions
            let extended10 = logCount("EAGER_EXTENDED"), timeouts10 = logCount("EAGER_TIMEOUT")
            env.repository.eagerBuildTimeout = 0.35
            env.engine.deriveDelay = 0.8
            env.addWallet("xcoldbg00010")
            env.repository.startEagerBuild(walletId: "xcoldbg00010", kind: .cold, seedHex: env.abandonSeed)
            await pause(0.05)
            bg.enterBackground()
            await pause(0.05)
            bg.enterForeground()
            await pause(0.35)                                            // first extension at 0.35 s
            bg.enterBackground()
            await pause(0.05)
            bg.enterForeground()                                         // second at 0.7 s; the build ends ≈ 0.8 s
            check(await waitUntil(3) { env.keys.raw("xcoldbg00010") != nil }, "two background visits: sealed")
            eq(logCount("EAGER_EXTENDED"), extended10 + 2, "extended twice")
            eq(logCount("EAGER_TIMEOUT"), timeouts10, "no timeout")

            // a removal (forget) while an extended build runs cancels it: nothing sealed, the task ended once
            let extended11 = logCount("EAGER_EXTENDED"), timeouts11 = logCount("EAGER_TIMEOUT")
            env.repository.eagerBuildTimeout = 0.2
            env.engine.deriveDelay = 0.6
            env.addWallet("xcoldbg00011")
            env.repository.startEagerBuild(walletId: "xcoldbg00011", kind: .cold, seedHex: env.abandonSeed)
            let bgId11 = bg.lastId
            await pause(0.05)
            bg.enterBackground()
            await pause(0.05)
            bg.enterForeground()
            check(await waitUntil(2) { logCount("EAGER_EXTENDED") == extended11 + 1 }, "extended")
            env.repository.forget(walletId: "xcoldbg00011")
            await pause(0.6)
            t(env.keys.raw("xcoldbg00011") == nil, "forget during the extension: never seals")
            eq(bg.ended.filter { $0 == bgId11 }.count, 1, "its background task ended once")
            eq(logCount("EAGER_TIMEOUT"), timeouts11, "a cancellation is not a timeout")

            // the end of an extended build still releases the warm PAIRING context (lead addendum D3)
            let releases0 = env.engine.releases
            env.repository.eagerBuildTimeout = 0.3
            env.engine.deriveDelay = 0.35
            env.addWallet("xcoldbg00012")
            env.repository.startEagerBuild(walletId: "xcoldbg00012", kind: .cold, seedHex: env.abandonSeed)
            await pause(0.05)
            bg.enterBackground()
            check(await waitUntil(3) { env.keys.raw("xcoldbg00012") != nil }, "extended build sealed")
            bg.enterForeground()
            check(await waitUntil(2) { env.engine.releases == releases0 + 1 }, "released at the end of the extended build")

            env.repository.eagerBuildTimeout = BILPublicIndexRepository.eagerTimeout
            env.engine.deriveDelay = 0
        }

        // the exactly-once box on its own
        section("eager-background-task")
        runAsync { @MainActor in
            let bg = FakeBackgroundExecution()
            let task = BILPublicEagerBackgroundTask(bg, name: "n")
            eq(bg.begun, ["n"], "begun with the name")
            task.end()
            task.end()
            eq(bg.ended, [1], "end twice → ended once")
            bg.expire(1)
            eq(bg.ended, [1], "expiry after the end → nothing")
            let expiring = BILPublicEagerBackgroundTask(bg, name: "n")
            bg.expire(2)
            expiring.end()
            eq(bg.ended, [1, 2], "expiry first, end later → ended once")
            let none = BILPublicEagerBackgroundTask(nil, name: "n")
            none.end()
            eq(bg.ended, [1, 2], "no background execution → nothing to end")
            bg.refuse = true
            let refused = BILPublicEagerBackgroundTask(bg, name: "n")
            refused.end()
            eq(bg.ended, [1, 2], "refused by the system → nothing to end")
        }

        // MARK: - H. Ownbit TRON scheme (PublicIndexOwnbitSchemeTest, spec §4.2a)

        section("ownbit-scheme")
        runAsync { @MainActor in
            let env = Env(vectors)
            @MainActor func storeRoundOne(_ id: String, index: BILJSONObject = abandonIndex) throws {
                guard let key = try env.keys.key(create: true) else { return }
                let sealed = try BILPublicIndexSealer.seal(Data(BILStrictJSON.serialize(index).utf8), key: key, walletId: id, kind: .cold)
                // An envelope as the app wrote it: [sha256, md5]; the second entry stands for the app's md5 (`legacyHash`).
                let hashes = [BILPublicHash.sha256Hex(utf8: env.abandonSeed), legacyHash]
                env.keys.setRaw(id, BILPublicIndexEnvelope(formatVersion: 1, seedHashes: hashes, createdAtMs: 5, sealed: BILBase64Strict.encode([UInt8](sealed))).encoded())
            }
            // prepare asks for Ownbit's scheme; cache[1] = Ownbit TRX #1
            env.addWallet(COLD)
            _ = await env.repository.prepare(walletId: COLD, password: Env.PASSWORD)
            let stored = await env.repository.get(walletId: COLD)
            eq(stored?.str("tronScheme"), "ownbit", "stored index in Ownbit's scheme")
            eq(stored?.arr("tronAddressIndex")?.count, 100, "100 TRON addresses")
            eq(stored?.arr("tronAddressIndex")?[1].objectValue?.str("address"), OV.TRX_OWNBIT_1, "#1 is Ownbit's TRX #1")
            t(stored?.arr("tronAddressIndex")?[1].objectValue?.str("address") != OV.TRX_STANDARD_1, "#1 is not the standard m/44'/195'/0'/0/1")

            // a round-1 index is converted once, cross-checked and sealed again (same seed hashes)
            let w1 = "xcoldr100001"
            env.addWallet(w1)
            try storeRoundOne(w1)
            env.engine.reset()
            let first = await env.repository.load(walletId: w1)
            eq(first.status, .ready(fingerprint: "73C5DA0A"), "a round-1 index is authentic")
            t(first.index == ownbitIndex, "load returns the converted index")
            eq(env.engine.count("refreshPublicIndex"), 1, "one refresh")
            t(env.engine.calls.contains { $0.op == "derivePublicAddresses" && $0.chain == "tron" }, "the converted index was cross-checked (TRON)")
            check(await env.repository.get(walletId: w1) == ownbitIndex, "stored again, sealed")
            eq(env.envelope(w1)?.seedHashes, [BILPublicHash.sha256Hex(utf8: env.abandonSeed), legacyHash], "re-sealed with the same seed hashes")
            let inputs = await env.repository.resolverInputs()
            t(inputs.first { $0.str("localWalletId") == w1 }?.obj("publicIndex") == ownbitIndex, "resolver gets the converted index")
            eq(env.engine.count("refreshPublicIndex"), 1, "converted once")

            // a conversion that fails keeps the round-1 index and is not retried
            let w2 = "xcoldr200001"
            env.addWallet(w2)
            try storeRoundOne(w2)
            env.engine.reset()
            env.engine.refuse("refreshPublicIndex", "PUBLIC_INDEX")
            check((await env.repository.resolverInputs()).first { $0.str("localWalletId") == w2 }?.obj("publicIndex") == abandonIndex, "refused conversion → round-1 index used")
            _ = await env.repository.resolverInputs()
            _ = await env.repository.load(walletId: w2)
            eq(env.engine.count("refreshPublicIndex"), 1, "a failed conversion is not retried in this process")
            check(await env.repository.get(walletId: w2) == abandonIndex, "round-1 index kept")
            env.engine.refuse("refreshPublicIndex", nil)

            // a lying engine (identity changed) is refused
            let w3 = "xcoldr300001"
            env.addWallet(w3)
            try storeRoundOne(w3)
            env.engine.refreshLie = { var o = $0; o.set("walletKeyId", .string(String(repeating: "ab", count: 32))); return o }
            check((await env.repository.load(walletId: w3)).index == abandonIndex, "refresh with another walletKeyId refused, round-1 kept")
            env.engine.refreshLie = { var o = $0; o.set("masterFingerprint", .string("b8688df1")); return o }
            let w4 = "xcoldr400001"
            env.addWallet(w4)
            try storeRoundOne(w4)
            check((await env.repository.load(walletId: w4)).index == abandonIndex, "refresh with another fingerprint refused")
            env.engine.refreshLie = { var o = $0; o.set("tronAddressIndex", .array(Array((o.arr("tronAddressIndex") ?? []).prefix(99)))); return o }
            let w5 = "xcoldr500001"
            env.addWallet(w5)
            try storeRoundOne(w5)
            check((await env.repository.load(walletId: w5)).index == abandonIndex, "refresh with 99 addresses refused (count)")
            env.engine.refreshLie = nil

            // Ownbit's current TRX #N needs a longer cache: TRX #150 → 151 (no vector) → kept, not retried
            let w6 = "xcoldr600001"
            env.addWallet(w6, facts: env.abandonFacts(w6))
            try storeRoundOne(w6, index: ownbitIndex)
            env.setFacts(w6) { $0.facts = with($0.facts, trxAddress: OV.TRX_OWNBIT_1, trxIndex: 150) }
            env.engine.reset()
            check((await env.repository.load(walletId: w6)).index == ownbitIndex, "too-short cache: refresh asked, failure keeps the stored index")
            eq(env.engine.calls.first { $0.op == "refreshPublicIndex" }?.count, 151, "refresh asks clamp(150 + 1, 100, 1000)")

            // Ownbit's current TRX address is cross-checked, a lying engine is refused
            let f1 = env.abandonFacts(COLD, trxIndex: 1)
            if case .ok(let ok)? = try? await env.verifier.verify(index: ownbitIndex, facts: f1, chains: allChains) {
                t(ok.confirmed("tron:1") && ok.ownbitAddresses["tron:1"] == OV.TRX_OWNBIT_1, "TRX #1 confirmed as tron:1")
            } else { t(false, "Ownbit index with TRX #1 verifies") }
            env.engine.override(chain: "tron", profile: nil, start: 1, address: OV.TRX_STANDARD_1)
            if case .mismatch(.tron)? = try? await env.verifier.verify(index: ownbitIndex, facts: f1, chains: allChains) { t(true, "lying engine (#1 = standard) → Mismatch(TRON)") }
            else { t(false, "lying engine (#1 = standard) → Mismatch(TRON)") }
            env.engine.override(chain: "tron", profile: nil, start: 1, address: nil)
            if case .ok(let ok)? = try? await env.verifier.verify(index: abandonIndex, facts: f1, chains: allChains) {
                t(!ok.confirmed("tron:1"), "a round-1 index never confirms tron:1")
            } else { t(false, "round-1 index with TRX #1 verifies") }
            // a stored TRX #N row that disagrees fails the whole wallet at Prepare (fail closed, spec §4.5)
            let w7 = "xcoldr700001"
            env.addWallet(w7, facts: with(env.abandonFacts(w7, trxIndex: 1), trxAddress: OV.TRX_STANDARD_1))
            same(await env.repository.prepare(walletId: w7, password: Env.PASSWORD), .keysMismatch(.tron), "TRX #1 row = standard address → KeysMismatch(TRON)")
            t(env.keys.raw(w7) == nil, "nothing stored")
            // a cached TRON #N that disagrees with the derivation
            var badCache = ownbitIndex
            var arr = ownbitIndex.arr("tronAddressIndex") ?? []
            if var e1 = arr[1].objectValue { e1.set("address", .string(OV.TRX_STANDARD_1)); arr[1] = .object(e1); badCache.set("tronAddressIndex", .array(arr)) }
            if case .mismatch(.tron)? = try? await env.verifier.verify(index: badCache, facts: f1, chains: [.tron]) { t(true, "cached TRON #1 ≠ derived → Mismatch(TRON)") }
            else { t(false, "cached TRON #1 ≠ derived → Mismatch(TRON)") }

            // the converted index is cross-checked on every chain (spec §4.2a step 3), not only TRON
            let w8 = "xcoldr800001"
            env.addWallet(w8, facts: with(env.abandonFacts(w8), ethXpub: OV.XPUB_ETH_LEGAL))
            try storeRoundOne(w8)
            env.engine.reset()
            check((await env.repository.load(walletId: w8)).index == abandonIndex, "conversion vs an EVM row of another wallet → refused, round-1 index used")
            eq(env.engine.count("refreshPublicIndex"), 1, "EVM-refused conversion: one refresh")
            t(env.engine.calls.contains { $0.op == "derivePublicAddresses" && $0.chain == "evm" }, "the conversion was cross-checked on EVM")
            _ = await env.repository.load(walletId: w8)
            eq(env.engine.count("refreshPublicIndex"), 1, "EVM-refused conversion: not retried")
            check(await env.repository.get(walletId: w8) == abandonIndex, "EVM-refused conversion: round-1 entry kept")

            // a failed conversion is remembered per wallet + seedHash; forget drops the marks
            let w9 = "xcoldr900001"
            env.addWallet(w9)
            try storeRoundOne(w9)
            env.engine.reset()
            env.engine.refuse("refreshPublicIndex", "PUBLIC_INDEX")
            _ = await env.repository.load(walletId: w9)
            _ = await env.repository.load(walletId: w9)
            eq(env.engine.count("refreshPublicIndex"), 1, "failed conversion: one try for this wallet + seedHash")
            env.setFacts(w9) { $0.facts = with($0.facts, seedHash: legacyHash) }   // in the envelope, but md5-length
            same((await env.repository.load(walletId: w9)).status, .needsRepair, "an md5 seedHash never reads the entry (the app accepted it)")
            eq(env.engine.count("refreshPublicIndex"), 1, "…and nothing is converted")
            _ = await env.repository.load(walletId: w9)
            eq(env.engine.count("refreshPublicIndex"), 1, "…not later either")
            env.setFacts(w9) { $0.facts = with($0.facts, seedHash: BILPublicHash.sha256Hex(utf8: env.abandonSeed)) }
            env.engine.refuse("refreshPublicIndex", nil)
            env.repository.forget(walletId: w9)
            check((await env.repository.load(walletId: w9)).index == ownbitIndex, "forget clears the failed-conversion marks → converted")
            eq(env.engine.count("refreshPublicIndex"), 2, "after forget: one more refresh")
        }

        // MARK: - I. Transient Keychain errors (D-08)

        section("transient")
        runAsync { @MainActor in
            let env = Env(vectors)
            env.addWallet(COLD)
            env.addWallet(HOT, cold: false)
            _ = await env.repository.prepare(walletId: COLD, password: Env.PASSWORD)
            _ = await env.repository.prepare(walletId: HOT, password: Env.PASSWORD)
            env.keys.readError = -25308                            // errSecInteractionNotAllowed (protected data unavailable)
            same(await env.repository.status(walletId: COLD), .temporarilyUnreadable, "read error -25308 → temporarilyUnreadable")
            let l = await env.repository.load(walletId: COLD)
            t(l.status == .temporarilyUnreadable && l.index == nil, "load → (temporarilyUnreadable, nil)")
            check(await env.repository.get(walletId: COLD) == nil, "get → nil")
            let inputs = await env.repository.resolverInputs()
            eq(inputs.map { $0.keys }, [["localWalletId"], ["localWalletId"]], "resolver inputs: localWalletId only while unreadable")
            t(env.keys.raw(COLD) != nil, "entry not deleted")
            same(await env.repository.runOrphanCleanup() ?? ["skipped"], [], "cleanup while reads fail: no orphan, nothing deleted")
            env.keys.readError = nil
            same(await env.repository.status(walletId: COLD), .ready(fingerprint: "73C5DA0A"), "not cached: the next read after recovery → Ready")
            env.keys.keyReadError = -25308
            same(await env.repository.status(walletId: COLD), .temporarilyUnreadable, "key read error → temporarilyUnreadable")
            env.keys.keyReadError = nil
            same(await env.repository.status(walletId: COLD), .ready(fingerprint: "73C5DA0A"), "key readable again → Ready")
            env.keys.readError = errSecItemNotFound
            // errSecItemNotFound from the store API means "no entry" only through the nil return; a thrown one is still transient
            same(await env.repository.status(walletId: COLD), .temporarilyUnreadable, "a thrown status is transient, never NeedsRepair")
            env.keys.readError = nil
        }

        // MARK: - J. Deletion and orphan cleanup (spec §4.6, C-IDX)

        section("deletion")
        runAsync { @MainActor in
            let env = Env(vectors)
            env.addWallet(COLD)
            env.addWallet(HOT, cold: false)
            _ = await env.repository.prepare(walletId: COLD, password: Env.PASSWORD)
            _ = await env.repository.prepare(walletId: HOT, password: Env.PASSWORD)
            let changes = Box<[String]>([])
            let observer = NotificationCenter.default.addObserver(forName: .publicIndexDidChange, object: nil, queue: nil) { n in
                if let id = n.object as? String { changes.update { $0.append(id + (Thread.isMainThread ? "@main" : "@bg")) } }
            }
            defer { NotificationCenter.default.removeObserver(observer) }

            env.repository.deleteIndex(walletId: HOT)
            t(env.keys.raw(HOT) == nil, "deleteIndex removes the entry")
            same(await env.repository.status(walletId: HOT), .missing, "deleted → Missing")
            t(changes.value.contains(HOT + "@main"), "deleteIndex posts .publicIndexDidChange")

            // deleteEntry from a background queue (BILWalletManager.remove may run off-main)
            let onMainRan = Box(false)
            let onMainThread = Box(false)
            let keys = env.keys
            let atPost = Box<[String]>([])           // what held when the notification was posted
            // object: nil + compare (the object filter matches by identity, a bridged String is not reliably the same object)
            let postObserver = NotificationCenter.default.addObserver(forName: .publicIndexDidChange, object: nil, queue: nil) { n in
                guard (n.object as? String) == COLD else { return }
                atPost.update { $0.append(keys.raw(COLD) == nil ? "entry-gone" : "entry-present") }
            }
            defer { NotificationCenter.default.removeObserver(postObserver) }
            DispatchQueue.global(qos: .utility).async {
                BILPublicIndexRepository.deleteEntry(walletId: COLD, keys: keys) {
                    onMainThread.value = Thread.isMainThread
                    onMainRan.value = true
                }
            }
            check(await waitUntil(5) { onMainRan.value }, "deleteEntry from a background queue completes")
            t(onMainThread.value, "its completion runs on main")
            t(env.keys.raw(COLD) == nil, "deleteEntry removed the entry")
            t(changes.value.contains(COLD + "@main"), "deleteEntry posted .publicIndexDidChange on main")
            eq(atPost.value, ["entry-gone"], "deleted before the post (the app's DEBUG deletion trace is not part of the package)")
            BILPublicIndexRepository.deleteEntry(walletId: "never-existed", keys: keys) {}
            check(await waitUntil(2) { changes.value.contains("never-existed@main") }, "deleting a missing entry is not an error")

            // orphan cleanup removes stray entries, keeps the wallets' and the key, never runs on a failed fetch
            _ = await env.repository.prepare(walletId: COLD, password: Env.PASSWORD)
            let keyBefore = env.keys.rawKey
            env.keys.setRaw("orphan-1", Data("x".utf8))
            env.keys.setRaw("orphan-2", env.keys.raw(COLD))
            env.directory.allIdsError = BILPublicKeychainError(status: -1)
            let skipped = await env.repository.runOrphanCleanup()
            t(skipped == nil, "fetch refused → cleanup skipped")
            eq(env.keys.ids, ["orphan-1", "orphan-2", COLD], "skipped cleanup deletes nothing")
            env.directory.allIdsError = nil
            env.keys.listError = -25308
            check(await env.repository.runOrphanCleanup() == nil, "listing refused → skipped, nothing deleted")
            eq(env.keys.ids, ["orphan-1", "orphan-2", COLD], "listing refused: entries kept")
            env.keys.listError = nil
            let removed = await env.repository.runOrphanCleanup()
            eq(Set(removed ?? []), ["orphan-1", "orphan-2"], "orphans removed")
            eq(env.keys.ids, [COLD], "the wallet's entry kept")
            t(env.keys.rawKey == keyBefore && keyBefore != nil, "the AES key is never deleted")
            t(changes.value.contains("orphan-1@main") && changes.value.contains("orphan-2@main"), "orphan deletions post .publicIndexDidChange")
            same(await env.repository.status(walletId: COLD), .ready(fingerprint: "73C5DA0A"), "wallet still Ready after cleanup")

            // a skipped scheduled cleanup re-arms on the retry notification (live: protected data available)
            let env2 = Env(vectors)
            env2.addWallet(COLD)
            env2.keys.setRaw("orphan-3", Data("x".utf8))
            env2.directory.allIdsError = BILPublicKeychainError(status: -1)
            let retry = Notification.Name("PubIndexTestProtectedDataAvailable")
            env2.repository.orphanRetryNotification = retry
            env2.repository.scheduleOrphanCleanup()
            try? await Task.sleep(nanoseconds: 200_000_000)
            eq(env2.keys.ids, ["orphan-3"], "scheduled cleanup skipped while the fetch is refused")
            env2.directory.allIdsError = nil
            NotificationCenter.default.post(name: retry, object: nil)
            check(await waitUntil(3) { env2.keys.ids.isEmpty }, "re-armed cleanup runs on the retry notification")
            env2.keys.setRaw("orphan-4", Data("x".utf8))
            env2.repository.scheduleOrphanCleanup()
            NotificationCenter.default.post(name: retry, object: nil)
            try? await Task.sleep(nanoseconds: 200_000_000)
            eq(env2.keys.ids, ["orphan-4"], "at most one completed cleanup per process (later schedule is a no-op)")
            let env3 = Env(vectors)
            env3.repository.orphanCleanupDelay = 0.3
            env3.repository.scheduleOrphanCleanup()
            check(await env3.repository.runOrphanCleanup() == [], "a manual pass completes first")
            env3.keys.setRaw("orphan-5", Data("x".utf8))
            try? await Task.sleep(nanoseconds: 600_000_000)
            eq(env3.keys.ids, ["orphan-5"], "the pending scheduled pass skips after a completed one")
        }

        // MARK: - K. Log hygiene (C-KEY-5)

        section("logs")
        do {
            let lines = PPStubLog.lines
            let secrets = [vectors.seedHex("abandon"), vectors.seedHex("legal"), String(vectors.seedHex("abandon").prefix(16)), Fx.PASSWORD,
                           OV.LEGACY_0, OV.NESTED_0, OV.NATIVE_0, OV.TAPROOT_0, OV.ETH_0, OV.ETH_0.lowercased(), OV.TRX_0, OV.TRX_OWNBIT_1,
                           OV.TRX_STANDARD_1, OV.SOL, "73C5DA0A", "73c5da0a", "xpub", "walletKeyId", COLD, HOT]
            t(!lines.isEmpty, "the repository logged its failures")
            t(lines.allSatisfy { line in !secrets.contains { line.contains($0) } }, "no seed / password / address / fingerprint / key / wallet id in any log line")
            let shape = try! NSRegularExpression(pattern: "^error: PublicProtocol index: [A-Za-z0-9_. <>,]+$")
            t(lines.allSatisfy { BILKotlinText.wholeMatch(shape, $0) != nil }, "every log line is \"PublicProtocol index: <code or type>\"")
            t(lines.contains("error: PublicProtocol index: KEYS_MISMATCH_EVM") && lines.contains("error: PublicProtocol index: SEED_MISMATCH"),
              "mismatch / seed-mismatch codes logged")
        }

        pubSummary("index")
    }
}
