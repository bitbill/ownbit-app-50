//  PPPairingTests.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Port of the app harness suite `scripts/public-protocol/tests/pairing` (main.swift) to XCTest.
//
//  main.swift — suite "pairing" (WP14, design §4 WP14 / §3.11): BILPublicPairingQr, BILPublicPairingService and
//  BILPublicPairingModel, ported from Android PST:pairing/PublicPairingServiceTest.kt, PST:ui/PublicPairingViewModelTest.kt
//  (+ the model parts of PST:ui/PublicPairingPanelTest.kt), R2 §12 items 6–7, R3 §12, spec §13.2 #6 / #7, F3–F5, F13, F15,
//  C-LOG-2, plus the iOS additions (D-08 transient index reads, D-16 retry, store-change refresh, stop()).
//  The real WP11 repository + cross-check verifier run over the golden-vector engine (Fakes.swift).
//

import Foundation
import XCTest
@testable import OwnbitCore

/// The suite namespace (harness helpers are its static members).
enum PPPairingSuite: PPSuite {}

final class PPPairingTests: XCTestCase {
    func testPairing() throws {
        try ppRunSuite("pairing") { try PPPairingSuite.run() }
    }
}

extension PPPairingSuite {

    static let vectors = Vectors(text: fixtureText("vectors.json"))
    static let abandon = vectors.publicIndex("abandon")
    static let abandonOwnbit = vectors.publicIndex("abandonOwnbit")
    static let W = Fx.W

    static func sel(_ chain: BILPsChain, _ btc: BILPsBitcoinProfile = .native, sol: BILPsSolanaProfile = .standard,
             _ mode: BILPsOutputMode? = nil) -> BILPairingSelection {
        return BILPairingSelection(chain: chain, bitcoinProfile: btc, solanaProfile: sol, outputMode: mode)!
    }

    static func sel(_ chain: BILPsChain, _ mode: BILPsOutputMode) -> BILPairingSelection {
        return BILPairingSelection(chain: chain, outputMode: mode)!
    }

    /// The QR the engine makes for `selection` from the vector index (Android `PublicPairingQr.fromEngine(EngineVectors…)`).
    static func vectorQr(_ s: BILPairingSelection, index: BILJSONObject = abandon, tron: Int = 0, same: Bool = true) -> BILPublicPairingQr {
        guard let raw = vectors.createPublicPairing(index, s.chain.rawValue, s.profileWire, s.outputMode.rawValue, tron),
              let qr = try? BILPublicPairingQr.fromEngine(raw, selection: s, fingerprint: "73c5da0a", addressIndex: tron) else {
            print("FAIL no vector QR for \(s)")
            fatalError("harness fixture problem")
        }
        return qr.with(sameAsOwnbit: same)
    }

    static func vectorFrames(_ s: BILPairingSelection, index: BILJSONObject = abandonOwnbit, tron: Int = 0) -> [String] {
        return vectors.createPublicPairing(index, s.chain.rawValue, s.profileWire, s.outputMode.rawValue, tron)?.strings("frames") ?? []
    }

    /// Strings of `qr` that must equal (exact code units).
    static func sameStrings(_ a: [String], _ b: [String]) -> Bool {
        return a.count == b.count && zip(a, b).allSatisfy { BILJSONExact.equal($0, $1) }
    }

    /// `t` / `eq` with plain (non-autoclosure) arguments, so the caller may `await` inside them.
    @discardableResult
    static func tv(_ condition: Bool, _ what: String, file: StaticString = #file, line: UInt = #line) -> Bool {
        return t(condition, what, file: file, line: line)
    }

    @discardableResult
    static func eqv<T: Equatable>(_ actual: T, _ expected: T, _ what: String, file: StaticString = #file, line: UInt = #line) -> Bool {
        return eq(actual, expected, what, file: file, line: line)
    }

    // MARK: - A. BILPublicPairingQr (pure)

    @MainActor static func pairingError(_ env: Env, _ s: BILPairingSelection, tron: Int = 0, id: String = W) async -> Error? {
        do {
            _ = try await env.service.pairing(walletId: id, selection: s, tronIndex: tron)
            return nil
        } catch {
            return error
        }
    }
    @MainActor static func reason(_ e: Error?) -> BILPublicPairingError? {
        return e as? BILPublicPairingError
    }
    @MainActor static func run(_ name: String, _ body: @MainActor () async throws -> Void) async {
        section(name)
        do {
            try await body()
        } catch {
            t(false, name + " — threw \(type(of: error)): \(error)")
        }
    }
    @MainActor static func serviceTests() async throws {
        await run("service: every B1 export of the abandon cold wallet") {
            let env = Env(vectors)
            tv(await env.prepared(), "prepared")
            let cases: [(BILPairingSelection, String, String, Bool)] = [
                (.default, OV.NATIVE_0, "m/84'/0'/0'", true),
                (sel(.bitcoin, .native, .address), OV.NATIVE_0, "m/84'/0'/0'/0/0", true),
                (sel(.bitcoin, .nested), OV.NESTED_0, "m/49'/0'/0'", true),
                (sel(.bitcoin, .legacy), OV.LEGACY_0, "m/44'/0'/0'", true),
                (sel(.bitcoin, .legacy, .address), OV.LEGACY_0, "m/44'/0'/0'/0/0", true),
                // Cold wallets never hold Taproot: exported (BitSigner parity) but never "Same as in Ownbit".
                (sel(.bitcoin, .taproot), OV.TAPROOT_0, "m/86'/0'/0'", false),
                (sel(.bitcoin, .multisigNative), "", "m/48'/0'/0'/2'", false),
                (sel(.bitcoin, .multisigNested), "", "m/48'/0'/0'/1'", false),
                (sel(.evm), OV.ETH_0, "m/44'/60'/0'", true),
                (sel(.evm, .address), OV.ETH_0, "m/44'/60'/0'/0/0", true),
                (sel(.tron), OV.TRX_0, "m/44'/195'/0'/0/0", true),
                (sel(.solana), OV.SOL, "m/44'/501'/0'/0'", true),
                (sel(.solana, .address), OV.SOL, "m/44'/501'/0'/0'", true),
                (sel(.solana, sol: .trust), OV.SOL_TRUST, "m/44'/501'/0'", false),
                (sel(.solana, sol: .legacy), OV.SOL_LEGACY, "m/44'/501'", false),
            ]
            eq(cases.count, 15, "15 exports")
            for (s, address, path, same) in cases {
                let name = "\(s.chain.rawValue)/\(s.profileWire ?? "-")/\(s.outputMode.rawValue)"
                let qr = try await env.service.pairing(walletId: W, selection: s, tronIndex: 0)
                eq(qr.selection, s, name + " selection")
                eq(qr.address, address, name + " first address")
                eq(qr.path, path, name + " path")
                eq(qr.sameAsOwnbit, same, name + " Same as in Ownbit")
                eq(qr.displayFingerprint, "73C5DA0A", name + " fingerprint")
                eq(qr.addressIndex, 0, name + " index 0")
                // F4: the frames are the pinned engine's, byte for byte (device name "Ownbit"); the EVM address mode
                // (rendered from derivePublicAddresses) equals the engine's own #0 export too.
                let vector = vectors.createPublicPairing(abandonOwnbit, s.chain.rawValue, s.profileWire, s.outputMode.rawValue, 0)!
                t(sameStrings(qr.frames, vectorFrames(s)), name + " frames = vector frames")
                eq(qr.payload, BILPublicPayloadView.fromEngine(vector), name + " payload = vector payload")
            }
            t(!env.engine.indexesSeen.isEmpty && env.engine.indexesSeen.allSatisfy { $0 == abandonOwnbit },
              "only the device's own stored index reached the engine")
            t(env.engine.calls("createPublicPairing").filter { $0.chain == "evm" || $0.chain == "tron" }.allSatisfy { $0.profile == nil },
              "EVM / TRON exports omit profile (Android bridge, D-13)")
            eq(env.engine.count("derivePublicIndex"), 0, "pairing never derives an index")
        }

        await run("service: the EVM hd-key names Ownbit") {
            let env = Env(vectors)
            _ = await env.prepared()
            let qr = try await env.service.pairing(walletId: W, selection: sel(.evm), tronIndex: 0)
            eq(qr.type, "crypto-hdkey", "type")
            t(qr.bearsKey, "bears a key")
            eq(qr.payload?.format, .json, "JSON payload")
            let text = qr.payload?.text ?? ""
            t(text.contains("\"Ownbit\"") && !text.contains("BitSigner"), "payload names Ownbit, never BitSigner")
        }

        await run("service: EVM address mode exports Ownbit's current address #N") {
            let env = Env(vectors)
            _ = await env.prepared(ethIndex: 7)
            let qr = try await env.service.pairing(walletId: W, selection: sel(.evm, .address), tronIndex: 0)
            eq(qr.address, OV.ETH_7, "ETH #7")
            eq(qr.frames, [OV.ETH_7], "frames [ETH_7]")
            eq(qr.path, "m/44'/60'/0'/0/7", "path /0/7")
            eq(qr.addressIndex, 7, "index 7")
            t(qr.sameAsOwnbit, "Same as in Ownbit")
            eq(qr.type, "address", "type address")
            eq(qr.payload, BILPublicPayloadView(format: .text, text: OV.ETH_7, byteCount: 42, qrType: "address"), "payload")
            eq(env.engine.count("createPublicPairing"), 0, "the engine's pairing exports EVM #0 only")
            t(env.engine.calls.contains(EngineCall(op: "derivePublicAddresses", chain: "evm", profile: nil, index: 7)), "derivePublicAddresses(evm, 7)")
            let wallet = try await env.service.pairing(walletId: W, selection: sel(.evm), tronIndex: 0)
            eq(wallet.address, OV.ETH_0, "the wallet export still starts at #0")
            let plan = try BILPairingExportPolicy.plan(sel(.evm), facts: try env.service.facts(walletId: W), tronIndex: 0)
            t(plan.notes.contains(.evmAccountN), "wallet export notes Account N + 1")
        }

        await run("service: TRON #0 standard path, #1 = Ownbit's TRX #1") {
            let env = Env(vectors)
            _ = await env.prepared()
            let tron = sel(.tron)
            let q0 = try await env.service.pairing(walletId: W, selection: tron, tronIndex: 0)
            eq(q0.address, OV.TRX_0, "#0 address")
            eq(q0.path, "m/44'/195'/0'/0/0", "#0 path")
            eq(q0.addressIndex, 0, "#0 index")
            t(q0.sameAsOwnbit, "#0 same")
            let q1 = try await env.service.pairing(walletId: W, selection: tron, tronIndex: 1)
            eq(q1.address, OV.TRX_OWNBIT_1, "#1 = Ownbit's TRX #1")
            t(q1.address != OV.TRX_STANDARD_1, "#1 is not the standard m/44'/195'/0'/0/1")
            eq(q1.path, "m/44'/60'/0'/0/1", "#1 path")
            eq(q1.addressIndex, 1, "#1 index")
            eq(q1.frames, [q1.address], "#1 frames [address]")
            t(q1.sameAsOwnbit, "#1 same (TRON encoding of the verified EVM node's #1)")
            eq(env.engine.calls("createPublicPairing"),
               [EngineCall(op: "createPublicPairing", chain: "tron", profile: nil, mode: "address", index: 0),
                EngineCall(op: "createPublicPairing", chain: "tron", profile: nil, mode: "address", index: 1)], "createPublicPairing calls")
            t(env.engine.calls.contains(EngineCall(op: "derivePublicAddresses", chain: "evm", profile: nil, index: 1)), "Ownbit's TRX #1 from the EVM node")
            eq(try env.service.facts(walletId: W).kind, .cold, "facts kind cold")
            // Ownbit on TRX #1: the stored row is the address too.
            env.setFacts { with($0, trxAddress: .some(OV.TRX_OWNBIT_1), trxIndex: 1) }
            eq(try env.service.facts(walletId: W).tronIndex, 1, "facts tronIndex 1")
            tv(try await env.service.pairing(walletId: W, selection: tron, tronIndex: 1).sameAsOwnbit, "#1 same with the stored row")
            let facts1 = try env.service.facts(walletId: W)
            t(!(try BILPairingExportPolicy.plan(tron, facts: facts1, tronIndex: 1).notes.contains(.tronCurrentN)), "no tronCurrentN on #1")
            t(try BILPairingExportPolicy.plan(tron, facts: facts1, tronIndex: 0).notes.contains(.tronCurrentN), "#0 while Ownbit uses #1: choose #1")
            // Outside the stepper (Ownbit's TRX #1 < 99): a programming error, never an engine call with that index.
            env.engine.reset()
            let e = await pairingError(env, tron, tron: 100)
            t(e is BILPairingExportPolicyError, "#100 with TRX #1 → out of range (\(String(describing: e)))")
            let e2 = await pairingError(env, tron, tron: -1)
            t(e2 is BILPairingExportPolicyError, "#-1 → out of range")
            eq(env.engine.count("createPublicPairing"), 0, "no export outside the range")
        }

        await run("service: TRON #99 (the stepper's top)") {
            let env = Env(vectors)
            _ = await env.prepared()
            // The synthesized EVM page (fake) equals the real EVM vector page where both exist.
            let real1 = vectors.derivePublicAddresses(abandon, "evm", nil, 1, 1)?.arr("addresses")?.first?.objectValue?.str("address")
            let synth1 = vectors.synthesizedEvm(1, 1)?.first?.objectValue?.str("address")
            t(real1 != nil && real1 == synth1, "fake: EVM #1 from the Ownbit TRON page == the real EVM vector #1")
            let q99 = try await env.service.pairing(walletId: W, selection: sel(.tron), tronIndex: 99)
            eq(q99.address, OV.TRX_OWNBIT_99, "#99 address")
            eq(q99.path, "m/44'/60'/0'/0/99", "#99 path")
            eq(q99.addressIndex, 99, "#99 index")
            t(q99.sameAsOwnbit, "#99 same")
            t(sameStrings(q99.frames, vectorFrames(sel(.tron), tron: 99)), "#99 frames = vector")
            t(env.engine.calls.contains(EngineCall(op: "createPublicPairing", chain: "tron", profile: nil, mode: "address", index: 99)), "export #99")
            t(env.engine.calls.contains(EngineCall(op: "derivePublicAddresses", chain: "evm", profile: nil, index: 99)), "EVM node #99")
            let plan = try BILPairingExportPolicy.plan(sel(.tron), facts: try env.service.facts(walletId: W), tronIndex: 99)
            eq(plan.notes, [.addressOnly, .tronIndexN, .tronCurrentN], "#99 notes")
            let e = await pairingError(env, sel(.tron), tron: 100)
            t(e is BILPairingExportPolicyError, "#100 with TRX #0 → out of range")
        }

        await run("service: TRON #N — a lying EVM derivation or a disagreeing TRX row shows no QR") {
            let env = Env(vectors)
            _ = await env.prepared()
            let tron = sel(.tron)
            env.engine.override(chain: "evm", profile: nil, start: 1, address: OV.ETH_7)
            eqv(reason(await pairingError(env, tron, tron: 1)), .keysMismatch(.tron), "lying EVM #1 → KEYS_MISMATCH(TRON)")
            env.engine.override(chain: "evm", profile: nil, start: 1, address: nil)
            env.setFacts { with($0, trxAddress: .some(OV.TRX_STANDARD_1), trxIndex: 1) }
            eqv(reason(await pairingError(env, tron, tron: 1)), .keysMismatch(.tron), "stored TRX #1 = standard address → KEYS_MISMATCH")
            env.setFacts { with($0, trxAddress: .some(OV.TRX_0), trxIndex: 0) }
            tv(try await env.service.pairing(walletId: W, selection: tron, tronIndex: 0).sameAsOwnbit, "#0 unaffected")
            // The engine's EVM #1 is not a 20-byte hex address → engine-class failure.
            env.engine.override(chain: "evm", profile: nil, start: 1, address: "0x123")
            eqv(reason(await pairingError(env, tron, tron: 1)), .engine(code: nil), "malformed EVM #1 → ENGINE")
        }

        await run("service: round-1 index whose conversion fails — #0 exported, #1 needs repair") {
            let env = Env(vectors)
            env.addWallet()
            try env.sealDirectly(W, kind: .cold, index: abandon)
            env.engine.refuse("refreshPublicIndex", "PUBLIC_INDEX")
            let tron = sel(.tron)
            let q0 = try await env.service.pairing(walletId: W, selection: tron, tronIndex: 0)
            eq(q0.address, OV.TRX_0, "#0 address (same in both schemes)")
            eq(q0.path, "m/44'/195'/0'/0/0", "#0 path")
            t(q0.sameAsOwnbit, "#0 same")
            eqv(reason(await pairingError(env, tron, tron: 1)), .needsRepair, "#1 → NEEDS_REPAIR")
            t(!env.engine.calls("createPublicPairing").contains { ($0.index ?? 0) != 0 }, "never an export with index ≠ 0: \(env.engine.calls)")
            t(env.engine.indexesSeen.allSatisfy { $0 == abandon }, "only the stored round-1 index reached the engine")
        }

        await run("service: a hot wallet's Taproot export is Ownbit's") {
            let env = Env(vectors)
            _ = await env.prepared(cold: false, withTaproot: true)
            let qr = try await env.service.pairing(walletId: W, selection: sel(.bitcoin, .taproot), tronIndex: 0)
            eq(qr.address, OV.TAPROOT_0, "Taproot #0")
            t(qr.sameAsOwnbit, "same")
            eq(try env.service.facts(walletId: W).kind, .normal, "hot = normal")
            t(try env.service.facts(walletId: W).hasTaprootKeys, "hasTaprootKeys")
        }

        await run("service: a stored key that does not match shows no QR") {
            let env = Env(vectors)
            _ = await env.prepared()
            env.setFacts { with($0, ethXpub: .some(OV.XPUB_ETH_LEGAL)) }
            eqv(reason(await pairingError(env, sel(.evm))), .keysMismatch(.evm), "ETH xpub of another wallet → KEYS_MISMATCH(EVM)")
            eq(env.engine.count("createPublicPairing"), 0, "nothing exported")
            tv(try await env.service.pairing(walletId: W, selection: sel(.tron), tronIndex: 0).sameAsOwnbit, "TRON unaffected")
            env.setFacts { with($0, legacyXpub: .some(OV.XPUB_LEGACY_LEGAL)) }
            eqv(reason(await pairingError(env, .default)), .keysMismatch(.bitcoin), "legacy xpub of another wallet → KEYS_MISMATCH(BITCOIN)")
        }

        await run("service: an engine export whose address is not the verified one") {
            let env = Env(vectors)
            _ = await env.prepared()
            env.engine.pairingAddressOverride = OV.NESTED_0
            eqv(reason(await pairingError(env, .default)), .keysMismatch(.bitcoin), "BTC native export ≠ verified → KEYS_MISMATCH")
            env.engine.pairingAddressOverride = nil
            tv(!(try await env.service.pairing(walletId: W, selection: sel(.bitcoin, .multisigNative), tronIndex: 0).sameAsOwnbit),
              "BIP48 has nothing to compare: exported, no mark")
            // EVM compares ignoring case (Android equals(ignoreCase)); a different address is refused.
            env.engine.pairingAddressOverride = OV.ETH_0.lowercased()
            tv(try await env.service.pairing(walletId: W, selection: sel(.evm), tronIndex: 0).sameAsOwnbit, "EVM lower-case spelling still same")
            env.engine.pairingAddressOverride = OV.ETH_7
            eqv(reason(await pairingError(env, sel(.evm))), .keysMismatch(.evm), "EVM other address → KEYS_MISMATCH")
            env.engine.pairingAddressOverride = OV.TRX_OWNBIT_1
            eqv(reason(await pairingError(env, sel(.tron))), .keysMismatch(.tron), "TRON other address → KEYS_MISMATCH")
            env.engine.pairingAddressOverride = OV.SOL_TRUST
            eqv(reason(await pairingError(env, sel(.solana))), .keysMismatch(.solana), "SOL standard other address → KEYS_MISMATCH")
            env.engine.pairingAddressOverride = nil
        }

        await run("service: no index, a damaged index or an ineligible wallet") {
            let env = Env(vectors)
            env.addWallet()
            eqv(reason(await pairingError(env, .default)), .notPrepared, "no index → NOT_PREPARED")
            _ = await env.repository.prepare(walletId: W, password: Fx.PASSWORD)
            env.keys.loseKey()
            eqv(reason(await pairingError(env, .default)), .needsRepair, "lost key → NEEDS_REPAIR")
            env.addWallet("ms", traits: Fx.traits(multisig: true))
            eqv(reason(await pairingError(env, .default, id: "ms")), .notEligible, "multisig → NOT_ELIGIBLE")
            eqv(reason(await pairingError(env, .default, id: "absent")), .notEligible, "absent → NOT_ELIGIBLE")
            env.addWallet("watch", traits: Fx.traits(watch: true, seed: false))
            eqv(reason(await pairingError(env, .default, id: "watch")), .notEligible, "watch-only → NOT_ELIGIBLE")
            eq(env.engine.count("createPublicPairing"), 0, "no export")
            t(throwsErrorSync { _ = try env.service.facts(walletId: "absent") }, "facts of an absent wallet → notEligible")
        }

        await run("service: engine refusals and failures") {
            let env = Env(vectors)
            _ = await env.prepared()
            PPStubLog.reset()
            env.engine.refuse("createPublicPairing", "PROFILE")
            let e = await pairingError(env, .default)
            eq(reason(e), .engine(code: "PROFILE"), "refusal → ENGINE with the code")
            let text = "\(String(describing: e)) \(String(reflecting: e as Any))"
            t(!text.contains(OV.NATIVE_0) && !text.contains("1Lq") && !text.contains("refused at"), "no address / engine message in the error")
            env.engine.refuse("createPublicPairing", nil)
            env.engine.failOnce("createPublicPairing", .malformedResponse)
            eqv(reason(await pairingError(env, .default)), .engine(code: nil), "JS failure → ENGINE")
            env.engine.pairingPatch = { var o = $0; o["frames"] = nil; return o }
            eqv(reason(await pairingError(env, .default)), .engine(code: nil), "malformed export → ENGINE")
            env.engine.pairingPatch = { var o = $0; o.set("outputMode", .string("address")); return o }
            eqv(reason(await pairingError(env, .default)), .engine(code: nil), "export of another mode → ENGINE")
            env.engine.pairingPatch = nil
            env.deriver.fail = true
            eqv(reason(await pairingError(env, .default)), .engine(code: nil), "Ownbit bridge timeout → ENGINE, not a mismatch")
            env.deriver.fail = false
            env.engine.refuse("derivePublicAddresses", "INDEX")
            eqv(reason(await pairingError(env, .default)), .engine(code: "INDEX"), "cross-check refusal → ENGINE with the code")
            env.engine.refuse("derivePublicAddresses", nil)
            env.engine.refuse("createPublicPairing", "index_unreadable")
            eqv(reason(await pairingError(env, .default)), .engine(code: "INDEX_UNREADABLE"),
                "a refusal coded like the D-08 log code → ENGINE with the sanitized code, not the D-08 marker")
            env.engine.refuse("createPublicPairing", nil)
            // Log hygiene: codes and type names only.
            let lines = PPStubLog.lines.filter { $0.contains("PublicProtocol pairing") }
            t(!lines.isEmpty, "the failures were logged")
            for l in lines {
                t(!l.contains("1Lq") && !l.contains("bc1") && !l.contains("0x") && !l.contains("refused") && !l.contains("73c5da0a")
                    && !l.lowercased().contains("xpub"), "log line is code-only: \(l)")
            }
        }

        await run("service: transient Keychain error, cancellation") {
            let env = Env(vectors)
            _ = await env.prepared()
            env.keys.readError = -25308
            eqv(reason(await pairingError(env, .default)), .engine(code: BILPublicPairingService.indexUnreadableCode),
               "D-08: temporarily unreadable → ENGINE(D-08 marker), never NOT_PREPARED / NEEDS_REPAIR")
            // The marker is outside the engine's code space (review WP14 #4): no refusal code can ever equal it.
            let marker = BILPublicPairingService.indexUnreadableCode
            t(BILPublicSignerRefusal.sanitize(marker) != marker, "the D-08 marker is not a sanitized engine code")
            for code in ["INDEX_UNREADABLE", "index_unreadable", "Index-Unreadable", marker, marker.uppercased(), ""] {
                t(BILPublicSignerRefusal(code: code, engineMessage: "").code != marker, "a refusal coded \(code) never reads as the D-08 marker")
            }
            t(env.keys.raw(W) != nil, "the entry is kept")
            env.keys.readError = nil
            tv(try await env.service.pairing(walletId: W, selection: .default, tronIndex: 0).sameAsOwnbit, "readable again → QR")
            env.engine.reset()
            let task = Task { @MainActor in
                try await env.service.pairing(walletId: W, selection: .default, tronIndex: 0)
            }
            task.cancel()
            do {
                _ = try await task.value
                t(false, "a cancelled export finished")
            } catch {
                t(error is CancellationError, "a cancelled export throws CancellationError (\(type(of: error)))")
            }
            eq(env.engine.count("createPublicPairing"), 0, "a cancelled export never reaches createPublicPairing")
            eq(env.engine.workCalls.count, 0, "nor the cross-check (cancellation is checked right after the index read)")
        }

        await run("service: EVM address mode — the export's own address is checked") {
            let env = Env(vectors)
            _ = await env.prepared()
            let evmAddress = sel(.evm, .address)
            // Call 1 = the cross-check (honest), call 2 = the export (lies).
            env.engine.patchNth(chain: "evm", profile: nil, start: 0, nth: 2) { var o = $0; o.set("address", .string(OV.ETH_7)); return o }
            eqv(reason(await pairingError(env, evmAddress)), .keysMismatch(.evm), "export ≠ verified EVM #0 → KEYS_MISMATCH(EVM)")
            env.engine.patchNth(chain: "evm", profile: nil, start: 0, nth: 2) { var o = $0; o.set("address", .string(OV.ETH_0.lowercased())); return o }
            let lower = try await env.service.pairing(walletId: W, selection: evmAddress, tronIndex: 0)
            tv(lower.sameAsOwnbit && lower.frames == [OV.ETH_0.lowercased()], "a lower-case spelling is the same address (ignoring case), shown as the engine wrote it")
            env.engine.patchNth(chain: "evm", profile: nil, start: 0, nth: 2) { var o = $0; o.set("address", .string("0xab\ncd")); return o }
            eqv(reason(await pairingError(env, evmAddress)), .engine(code: nil), "an address with a line break → ENGINE")
            env.engine.patchNth(chain: "evm", profile: nil, start: 0, nth: 2) { var o = $0; o.set("address", .string("")); return o }
            eqv(reason(await pairingError(env, evmAddress)), .engine(code: nil), "an empty address → ENGINE")
            env.engine.patchNth(chain: "evm", profile: nil, start: 0, nth: 2) { var o = $0; o.set("path", .string("m/44'/60'/0'/0/1")); return o }
            eqv(reason(await pairingError(env, evmAddress)), .engine(code: nil), "another path → ENGINE")
            env.engine.patchNth(chain: "evm", profile: nil, start: 0, nth: 2) { var o = $0; o.set("index", .int(1)); return o }
            eqv(reason(await pairingError(env, evmAddress)), .engine(code: nil), "another index → ENGINE")
            tv(try await env.service.pairing(walletId: W, selection: evmAddress, tronIndex: 0).sameAsOwnbit, "honest again → QR")
        }

        await run("service: the wallet goes away while its index is read") {
            let env = Env(vectors)
            _ = await env.prepared()
            let hooked = HookedIndex(env.repository)
            let service = BILPublicPairingService(engine: env.engine, index: hooked, wallets: env.directory, verifier: env.verifier)
            hooked.onLoad = { env.directory.remove(W) }
            do {
                _ = try await service.pairing(walletId: W, selection: .default, tronIndex: 0)
                t(false, "exported for a removed wallet")
            } catch let e as BILPublicPairingError {
                eq(e, .notEligible, "removed during the read → NOT_ELIGIBLE")
            }
            eq(env.engine.count("createPublicPairing"), 0, "no export")
        }

        await run("service: facts come from the wallet's own rows") {
            let env = Env(vectors)
            _ = await env.prepared(ethIndex: 7, nestedUsed: true)
            let facts = try env.service.facts(walletId: W)
            eq(facts.btcProfilesInUse, [.native, .nested, .legacy], "in use")
            t(!facts.hasTaprootKeys, "no Taproot keys")
            eq(facts.evmIndex, 7, "evmIndex")
            t(facts.hasSolanaAddress, "SOL present")
            eq(facts.kind, .cold, "cold")
            let plan = try BILPairingExportPolicy.plan(sel(.bitcoin, .nested), facts: facts, tronIndex: 0)
            t(plan.notes.contains(.usedInWallet) && plan.notes.contains(.btcPairEachType), "nested plan notes")
            env.setFacts { f in BILPublicWalletFacts(walletId: f.walletId, kind: f.kind, seedHash: f.seedHash, legacyXpub: f.legacyXpub,
                                                     nestedXpub: f.nestedXpub, nativeXpub: f.nativeXpub, taprootXpub: "  ",
                                                     ethXpub: f.ethXpub, ethAddress: f.ethAddress, ethIndex: f.ethIndex,
                                                     trxAddress: f.trxAddress, trxAddress0: f.trxAddress0, trxIndex: f.trxIndex,
                                                     solAddress: " ", btcProfilesInUse: f.btcProfilesInUse) }
            let blank = try env.service.facts(walletId: W)
            t(!blank.hasTaprootKeys && !blank.hasSolanaAddress, "blank Taproot xpub / SOL address count as missing (Kotlin isNotBlank)")
        }
    }
    @MainActor static func throwsErrorSync(_ body: () throws -> Void) -> Bool {
        do {
            try body()
            return false
        } catch let e as BILPublicPairingError {
            return e == .notEligible
        } catch {
            return false
        }
    }
    // (C. BILPublicPairingModel — the pairing panel's view model — is not ported: UI state, not part of the package.)

    /// The harness main.swift (nonisolated top-level code, as in the harness).
    static func run() throws {
        section("qr.fromEngine every T3 vector")
        do {
            var checked = 0
            for c in vectors.cases {
                guard let id = c.str("id"), id.hasPrefix("T3-pairing-"), let step = c.arr("steps")?.first?.objectValue,
                      let req = step.obj("request"), let resp = step.obj("response"), resp.bool("ok") == true,
                      let raw = resp.obj("result"), let chain = BILPsChain.fromWire(req.str("chain")) else { continue }
                let profile = req.str("profile")
                let mode = BILPsOutputMode(rawValue: raw.str("outputMode") ?? "")
                let s = BILPairingSelection(chain: chain,
                                            bitcoinProfile: chain == .bitcoin ? BILPsBitcoinProfile(rawValue: profile ?? "native") ?? .native : .native,
                                            solanaProfile: chain == .solana ? BILPsSolanaProfile(rawValue: profile ?? "standard") ?? .standard : .standard,
                                            outputMode: mode)
                guard let selection = s else { t(false, "\(id): selection"); continue }
                let n = req.int("index") ?? 0
                let ownbitScheme = req.obj("publicIndex")?.str("$fixture") == "publicIndex.abandonOwnbit"
                let standardTronN = chain == .tron && n > 0 && !ownbitScheme
                do {
                    let qr = try BILPublicPairingQr.fromEngine(raw, selection: selection, fingerprint: "73C5DA0A", addressIndex: n)
                    t(!standardTronN, "\(id): a standard-path TRON #N is never accepted")
                    t(sameStrings(qr.frames, raw.strings("frames") ?? []), "\(id): frames")
                    eq(qr.type, raw.str("type") ?? "", "\(id): type")
                    eq(qr.text, raw.str("text") ?? "", "\(id): text")
                    eq(qr.address, raw.str("address") ?? "", "\(id): address")
                    eq(qr.path, raw.str("path") ?? "", "\(id): path")
                    eq(qr.addressIndex, n, "\(id): addressIndex")
                    eq(qr.masterFingerprint, "73c5da0a", "\(id): fingerprint stored lower-case")
                    eq(qr.displayFingerprint, "73C5DA0A", "\(id): displayed upper-case")
                    eq(qr.payload, BILPublicPayloadView.fromEngine(raw), "\(id): payload view")
                    t(qr.payload != nil, "\(id): payload present")
                    eq(qr.engineNote, raw.str("note"), "\(id): engine note")
                    t(!qr.sameAsOwnbit, "\(id): never marked by the model itself")
                    eq(qr.bearsKey, selection.outputMode != .address, "\(id): bearsKey")
                    eq(qr.isAnimated, qr.frames.count > 1, "\(id): isAnimated")
                    checked += 1
                } catch {
                    t(standardTronN, "\(id): refused only for a standard-path TRON #N (\(error))")
                }
            }
            t(checked >= 26, "at least 26 T3 vector exports parse (\(checked))")
            // The animated vector (fragmentLength, never sent by iOS) still parses as an animated QR.
            if let raw = vectors.caseStep("T3-pairing-animated-bitcoin")?.result {
                let qr = try? BILPublicPairingQr.fromEngine(raw, selection: .default, fingerprint: "73c5da0a", addressIndex: 0)
                eq(qr?.isAnimated, true, "animated vector: isAnimated")
                eq(qr?.frames.count, 4, "animated vector: 4 frames")
            } else {
                t(false, "animated vector present")
            }
        }

        section("qr.fromEngine refusals")
        do {
            let base = vectors.createPublicPairing(abandon, "bitcoin", "native", "accountXpub", 0)!
            let evmAddr = vectors.createPublicPairing(abandon, "evm", nil, "address", 0)!
            let tron1 = vectors.createPublicPairing(abandonOwnbit, "tron", nil, "address", 1)!
            let sol = vectors.createPublicPairing(abandon, "solana", "trust", "wallet", 0)!
            func refused(_ what: String, _ raw: BILJSONObject, _ s: BILPairingSelection, fp: String = "73c5da0a", index: Int = 0, expect: String) {
                do {
                    _ = try BILPublicPairingQr.fromEngine(raw, selection: s, fingerprint: fp, addressIndex: index)
                    t(false, what + " — accepted")
                } catch let e as BILMalformedEngineResult {
                    eq(e.what, expect, what)
                } catch {
                    t(false, what + " — threw \(type(of: error))")
                }
            }
            func patched(_ raw: BILJSONObject, _ key: String, _ value: BILJSONValue?) -> BILJSONObject {
                var o = raw
                o[key] = value
                return o
            }
            refused("no frames", patched(base, "frames", nil), .default, expect: "pairing.frames")
            refused("empty frames only", patched(base, "frames", .array([.string(""), .string("")])), .default, expect: "pairing.frames")
            refused("a non-string frame", patched(base, "frames", .array([.string("UR:X"), .int(1)])), .default, expect: "pairing.frames")
            refused("other output mode", base, sel(.bitcoin, .native, .address), expect: "pairing.outputMode")
            refused("output mode missing", patched(base, "outputMode", nil), .default, expect: "pairing.outputMode")
            refused("other BTC profile", base, sel(.bitcoin, .nested), expect: "pairing.profile")
            refused("BTC profile missing", patched(base, "profile", nil), .default, expect: "pairing.profile")
            refused("other SOL profile", sol, sel(.solana, sol: .legacy, .wallet), expect: "pairing.profile")
            refused("EVM address at another index", evmAddr, sel(.evm, .address), index: 3, expect: "pairing.path")
            refused("TRON #1 at the standard path", patched(tron1, "path", .string("m/44'/195'/0'/0/1")), sel(.tron), index: 1, expect: "pairing.path")
            refused("TRON #1 answered for #2", tron1, sel(.tron), index: 2, expect: "pairing.path")
            refused("fingerprint not hex", base, .default, fp: "73c5da0g", expect: "pairing.masterFingerprint")
            refused("fingerprint 3 bytes", base, .default, fp: "73c5da", expect: "pairing.masterFingerprint")
            refused("type missing", patched(base, "type", nil), .default, expect: "pairing.type")
            refused("type not a string", patched(base, "type", .int(1)), .default, expect: "pairing.type")
            refused("index on a BTC export", base, .default, index: 1, expect: "pairing.addressIndex")
            refused("negative index", evmAddr, sel(.evm, .address), index: -1, expect: "pairing.path")
            // EVM wallet export (no path check) with an index → the model's index rule.
            let evmWallet = vectors.createPublicPairing(abandon, "evm", nil, "wallet", 0)!
            refused("index on an EVM wallet export", evmWallet, sel(.evm), index: 2, expect: "pairing.addressIndex")
        }

        section("qr.fromEngine defaults")
        do {
            var raw = vectors.createPublicPairing(abandon, "bitcoin", "native", "accountXpub", 0)!
            raw["text"] = nil
            raw["address"] = nil
            raw["path"] = nil
            raw["note"] = nil
            raw.set("frames", .array([.string("A"), .string(""), .string("B")]))
            raw["payloadFormat"] = nil
            let qr = try? BILPublicPairingQr.fromEngine(raw, selection: .default, fingerprint: "73C5DA0A", addressIndex: 0)
            eq(qr?.frames, ["A", "B"], "empty frames dropped")
            eq(qr?.text, "A\nB", "text = frames joined by \\n")
            eq(qr?.address, "", "address default \"\"")
            eq(qr?.path, "", "path default \"\"")
            t(qr?.engineNote == nil, "no note")
            t(qr != nil && qr?.payload == nil, "no payload view without payloadFormat")
            eq(qr?.isAnimated, true, "2 frames → animated")
            t(qr?.bearsKey == true, "account xpub bears a key")
        }

        section("qr.paths / addressOnly / equality")
        do {
            eq(BILPublicPairingQr.tronPath(0), "m/44'/195'/0'/0/0", "TRON #0 path")
            eq(BILPublicPairingQr.tronPath(1), "m/44'/60'/0'/0/1", "TRON #1 = Ownbit's ETH-key path")
            eq(BILPublicPairingQr.tronPath(99), "m/44'/60'/0'/0/99", "TRON #99")
            eq(BILPublicPairingQr.evmPath(7), "m/44'/60'/0'/0/7", "EVM #7")
            let s = sel(.evm, .address)
            let a = BILPublicPairingQr.addressOnly(selection: s, address: OV.ETH_0, path: "m/44'/60'/0'/0/0", addressIndex: 0, fingerprint: "73C5DA0A")
            let engine = try? BILPublicPairingQr.fromEngine(vectors.caseStep("T3-pairing-evm-standard-address")!.result!, selection: s,
                                                            fingerprint: "73c5da0a", addressIndex: 0)
            eq(a, engine, "EVM address #0 rendered natively == the engine's own address export (vector)")
            eq(a.payload, BILPublicPayloadView(format: .text, text: OV.ETH_0, byteCount: 42, qrType: "address"), "payload TEXT 42 B address")
            eq(a.type, "address", "type address")
            eq(a.frames, [OV.ETH_0], "one frame = the EIP-55 address, no prefix")
            t(!a.bearsKey && !a.isAnimated && a.engineNote == nil && !a.sameAsOwnbit, "address-only shape")
            t(BILPublicPairingQr.isAddressOnlyValid(selection: s, address: OV.ETH_7, path: "m/44'/60'/0'/0/7", addressIndex: 7), "valid #7")
            t(!BILPublicPairingQr.isAddressOnlyValid(selection: s, address: OV.ETH_7, path: "m/44'/60'/0'/0/6", addressIndex: 7), "wrong path")
            t(!BILPublicPairingQr.isAddressOnlyValid(selection: s, address: "", path: "m/44'/60'/0'/0/0", addressIndex: 0), "empty address")
            t(!BILPublicPairingQr.isAddressOnlyValid(selection: s, address: "0xab\ncd", path: "m/44'/60'/0'/0/0", addressIndex: 0), "line break")
            t(!BILPublicPairingQr.isAddressOnlyValid(selection: sel(.evm), address: OV.ETH_0, path: "m/44'/60'/0'/0/0", addressIndex: 0), "wallet mode")
            t(!BILPublicPairingQr.isAddressOnlyValid(selection: s, address: OV.ETH_0, path: "m/44'/60'/0'/0/-1", addressIndex: -1), "negative index")
            t(BILPublicPairingQr.isAddressOnlyValid(selection: sel(.tron), address: OV.TRX_OWNBIT_1, path: "m/44'/60'/0'/0/1", addressIndex: 1), "TRON #1")
            t(!BILPublicPairingQr.isAddressOnlyValid(selection: sel(.tron), address: OV.TRX_STANDARD_1, path: "m/44'/195'/0'/0/1", addressIndex: 1), "TRON #1 standard path")
            // Exact equality (code units, never canonical equivalence).
            let k = BILPublicPairingQr.addressOnly(selection: s, address: "\u{212A}", path: "m/44'/60'/0'/0/0", addressIndex: 0, fingerprint: "73c5da0a")
            let kk = BILPublicPairingQr.addressOnly(selection: s, address: "K", path: "m/44'/60'/0'/0/0", addressIndex: 0, fingerprint: "73c5da0a")
            t(k != kk, "KELVIN SIGN ≠ K")
            let e1 = BILPublicPairingQr.addressOnly(selection: s, address: "e\u{301}", path: "p", addressIndex: 0, fingerprint: "73c5da0a")
            let e2 = BILPublicPairingQr.addressOnly(selection: s, address: "\u{E9}", path: "p", addressIndex: 0, fingerprint: "73c5da0a")
            t(e1 != e2, "decomposed ≠ precomposed")
            let marked = a.with(sameAsOwnbit: true)
            t(marked.sameAsOwnbit && marked != a && marked.with(sameAsOwnbit: false) == a, "with(sameAsOwnbit:) changes only the mark")
            let d = "\(marked)" + String(reflecting: marked)
            t(!d.contains(OV.ETH_0) && !d.lowercased().contains("73c5da0a") && !d.contains("m/44"), "description has no address / fingerprint / path")
        }

        // MARK: - B. BILPublicPairingService (Android PublicPairingServiceTest)

        /// One named group of async checks: a thrown error counts as one failure of that group only (the next groups still run).

        /// `facts` throws `BILPublicPairingError.notEligible` (sync helper).

        // MARK: - C. BILPublicPairingModel (Android PublicPairingViewModelTest)

        /// Waits for the current request of `s` to have a QR or an error; returns the current QR.

        /// An index store whose `prepare` waits for `gate` (the second-prepare-while-preparing case).

        runAsync(timeout: 600) {
            try await serviceTests()
        }

        section("log hygiene (whole suite)")
        do {
            let lines = PPStubLog.lines.filter { $0.contains("PublicProtocol pairing") || $0.contains("PublicProtocol index") }
            let addresses = [OV.LEGACY_0, OV.NESTED_0, OV.NATIVE_0, OV.TAPROOT_0, OV.ETH_0, OV.ETH_7, OV.TRX_0, OV.TRX_OWNBIT_1, OV.SOL, W]
            for l in lines {
                t(!addresses.contains { l.contains($0) || l.lowercased().contains($0.lowercased()) } && !l.contains("refused at"),
                  "no address / wallet id / engine message in: \(l)")
            }
        }

        pubSummary("pairing")
    }
}
