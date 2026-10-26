//  BILPublicPairingService.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Public protocol (coin-level pairing): the exports of the "Pair with other wallets" tab (spec §5.2; port of Android
//  core/publicsigner pairing/PublicPairingService.kt, R2 §8). For every QR, in this order:
//
//  1. the wallet must be eligible and have an authentic stored index (BILPublicIndexStoring.load, which may convert an
//     older index to Ownbit's TRON scheme from its own public nodes; never derived here);
//  2. the index is cross-checked against the wallet's stored keys for the selected chain (BILPublicIndexVerifier; TRON
//     #N ≥ 1 also the EVM account node its addresses come from);
//  3. the export follows BILPairingExportPolicy (TRON #N of the stepper, EVM address mode at Ownbit's current #N, …), made
//     by the engine on the pairing page (device name "Ownbit");
//  4. the QR's first address must equal the address Ownbit confirmed in step 2 (else no QR); when it does, the QR is
//     marked "Same as in Ownbit". TRON #N ≥ 1 (R2-5): Ownbit's TRX address #N is the ETH key's address #N TRON-encoded,
//     so the QR must equal the TRON encoding of the verified EVM node's address #N, and the stored TRX row when Ownbit
//     currently uses #N; the index must be in Ownbit's TRON scheme.
//
//  Only the device's own unsealed, verified index ever reaches the engine. Nothing is logged but codes and type names.
//  Main actor (Core Data facts, existing bridges); pure (engine contract, index store, wallet directory and verifier are
//  injected; the app's live wiring, BILPublicPairingService+Live.swift, is not part of this package).
//

import Foundation

/// Why no pairing QR may be shown (log-safe: no key, address or seed in it).
/// - `notEligible`: not a public-protocol wallet (or deleted meanwhile) — the panel shows nothing.
/// - `notPrepared`: no index yet — the Prepare card (one password).
/// - `needsRepair`: the stored index cannot be trusted (or TRON #N needs Ownbit's scheme) — Prepare + `err.rebuildPublicData`.
/// - `keysMismatch(chain)`: the engine's address is not the address Ownbit holds (`pair.keysMismatch`): no QR.
/// - `engine(code)`: the engine (or an Ownbit bridge of the cross-check) failed (`err.engineUnavailable`); `code` = the
///   engine's refusal code. iOS: `BILPublicPairingService.indexUnreadableCode` = the Keychain refused the read for now
///   (D-08 `.temporarilyUnreadable`; the panel shows its loading state and reads again).
public enum BILPublicPairingError: Error, Equatable {
    case notEligible, notPrepared, needsRepair, keysMismatch(BILPsChain), engine(code: String?)
}

extension BILPublicPairingError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .notEligible: return "BILPublicPairingError(notEligible)"
        case .notPrepared: return "BILPublicPairingError(notPrepared)"
        case .needsRepair: return "BILPublicPairingError(needsRepair)"
        case .keysMismatch(let chain): return "BILPublicPairingError(keysMismatch " + chain.rawValue + ")"
        case .engine(let code): return "BILPublicPairingError(engine " + (code ?? "-") + ")"
        }
    }
}

@MainActor public protocol BILPublicPairingServicing: AnyObject {
    /// What Ownbit holds for the wallet that the export policy needs (local rows only). Throws `.notEligible` when the
    /// wallet does not exist.
    func facts(walletId: String) throws -> BILWalletPairingFacts
    /// The pairing QR of `selection`; on TRON the address #`tronIndex` (0 … `BILPairingExportPolicy.maxTronIndex`).
    /// Throws `BILPublicPairingError` when no QR may be shown, `BILPairingExportPolicyError.tronIndexOutOfRange` for an
    /// index outside the stepper's range (a programming error, never an engine call), `CancellationError` when cancelled.
    func pairing(walletId: String, selection: BILPairingSelection, tronIndex: Int) async throws -> BILPublicPairingQr
}

@MainActor public final class BILPublicPairingService: BILPublicPairingServicing {

    /// iOS (D-08): the engine code of `.engine` when the index could not be read for now (Keychain error other than "not
    /// found", e.g. -25308 while protected data is unavailable). Never shown as an engine failure by the panel model.
    /// Outside the engine's code space on purpose: a refusal code is always `[A-Z0-9_]{1,80}`
    /// (`BILPublicSignerRefusal.sanitize`), so no engine refusal can ever read as this marker (the ':' and the lower-case
    /// letters cannot survive the sanitizer).
    public nonisolated static let indexUnreadableCode = "ios:indexUnreadable"

    /// Ownbit's TRON address scheme of the public index (engine Ownbit edition, R2-5).
    private static let ownbitTronScheme = "ownbit"

    private let engine: BILPublicSignerEngining
    private let index: BILPublicIndexStoring
    private let wallets: BILPublicWalletDirectory
    private let verifier: BILPublicIndexVerifier

    public init(engine: BILPublicSignerEngining, index: BILPublicIndexStoring, wallets: BILPublicWalletDirectory,
         verifier: BILPublicIndexVerifier) {
        self.engine = engine
        self.index = index
        self.wallets = wallets
        self.verifier = verifier
    }

    // MARK: - BILPublicPairingServicing

    public func facts(walletId: String) throws -> BILWalletPairingFacts {
        guard let facts = wallets.facts(walletId: walletId) else { throw BILPublicPairingError.notEligible }
        return facts.pairingFacts
    }

    public func pairing(walletId: String, selection: BILPairingSelection, tronIndex: Int) async throws -> BILPublicPairingQr {
        guard wallets.eligibility(walletId: walletId).isEligible else { throw BILPublicPairingError.notEligible }
        let loaded = await index.load(walletId: walletId)
        try Task.checkCancellation()
        guard let publicIndex = loaded.index else {
            switch loaded.status {
            case .needsRepair: throw BILPublicPairingError.needsRepair
            case .notEligible: throw BILPublicPairingError.notEligible
            case .temporarilyUnreadable:
                BILPublicLog.code("pairing", "INDEX_UNREADABLE")
                throw BILPublicPairingError.engine(code: BILPublicPairingService.indexUnreadableCode)
            default: throw BILPublicPairingError.notPrepared
            }
        }
        // Fresh facts after the read (the cross-check compares with what Ownbit stores now).
        guard let facts = wallets.facts(walletId: walletId) else { throw BILPublicPairingError.notEligible }
        let plan = try BILPairingExportPolicy.plan(selection, facts: facts.pairingFacts, tronIndex: tronIndex)
        do {
            return try await export(walletId, publicIndex, facts, plan)
        } catch let e as CancellationError {
            throw e
        } catch let e as BILPublicPairingError {
            throw e
        } catch let refusal as BILPublicSignerRefusal {
            BILPublicLog.failure("pairing", refusal)
            throw BILPublicPairingError.engine(code: refusal.code)
        } catch let error where BILPublicPairingService.isEngineClass(error) {
            BILPublicLog.failure("pairing", error)
            throw BILPublicPairingError.engine(code: nil)
        }
    }

    // MARK: - Export (Android `export`)

    private func export(_ walletId: String, _ publicIndex: BILJSONObject, _ facts: BILPublicWalletFacts,
                        _ plan: BILExportPlan) async throws -> BILPublicPairingQr {
        let selection = plan.selection
        // TRON #N ≥ 1 comes from the index's EVM account node (Ownbit scheme): that node is cross-checked too.
        let tronN = selection.chain == .tron ? plan.addressIndex : 0
        let chains: Set<BILPsChain> = tronN > 0 ? [.evm, .tron] : [selection.chain]
        let ok: BILPublicVerifyMatches
        switch try await verifier.verify(index: publicIndex, facts: facts, chains: chains) {
        case .mismatch(let chain):
            throw BILPublicPairingError.keysMismatch(chain)
        case .ok(let matches):
            ok = matches
        }
        try Task.checkCancellation()
        guard let fingerprint = publicIndex.str("masterFingerprint") else {
            throw BILMalformedEngineResult(what: "publicIndex.masterFingerprint")
        }
        let qr: BILPublicPairingQr
        switch plan.call {
        case .enginePairing(let chain, let profile, let mode, let callIndex):
            // Android `check`: the policy never builds another call (a programming error → engine-class failure).
            try BILEngineJSON.ensure(chain == selection.chain && callIndex == plan.addressIndex && (callIndex == 0 || chain == .tron),
                                     "pairing.plan")
            if tronN > 0 && !BILPublicPairingService.same(publicIndex.str("tronScheme"), BILPublicPairingService.ownbitTronScheme) {
                // A standard-scheme index would export m/44'/195'/0'/0/N, which is not Ownbit's TRX #N: rebuild it.
                BILPublicLog.code("pairing", "TRON_NEEDS_OWNBIT_SCHEME")
                throw BILPublicPairingError.needsRepair
            }
            let raw = try await engine.createPublicPairing(publicIndex: publicIndex, chain: chain.rawValue, profile: profile,
                                                           outputMode: mode.rawValue, index: callIndex)
            qr = try BILPublicPairingQr.fromEngine(raw, selection: selection, fingerprint: fingerprint, addressIndex: plan.addressIndex)
        case .evmAddressAt(let n):
            qr = try await evmAddress(publicIndex, selection, n, fingerprint)
        }
        try Task.checkCancellation()
        let ownbit: String?
        if let key = plan.ownbitCheck {
            if ok.confirmed(key) {
                guard let address = ok.ownbitAddresses[key] else { throw BILMalformedEngineResult(what: "verify.addresses") }
                ownbit = address
            } else if tronN > 0 && BILPublicPairingService.same(key, BILPairingExportPolicy.tronKey(tronN)) {
                ownbit = try await ownbitTronAddress(walletId, publicIndex, ok, tronN)
            } else {
                ownbit = nil
            }
        } else {
            ownbit = nil
        }
        if plan.requireOwnbitMatch && ownbit == nil {
            throw BILPublicPairingError.keysMismatch(selection.chain)
        }
        if let expected = ownbit {
            let same = selection.chain == .evm ? BILPublicPairingService.sameIgnoringASCIICase(qr.address, expected)
                                               : BILJSONExact.equal(qr.address, expected)
            if !same {
                BILPublicLog.code("pairing", "QR_ADDRESS_DIFFERS")
                throw BILPublicPairingError.keysMismatch(selection.chain)
            }
        }
        return qr.with(sameAsOwnbit: ownbit != nil)
    }

    /// Ownbit's TRX address #`n` ≥ 1 (R2-5): the address #N of the index's EVM account node — verified against Ownbit's
    /// stored ETH key in `ok` — TRON-encoded ("41" + the 20 address bytes, base58check), as Ownbit derives its TRX #N from
    /// the ETH key (`TronWalletModel.useAddrOnIndexNo`). When Ownbit currently uses TRX #N, its stored row must be that
    /// same address. nil (no "Same as in Ownbit", no QR) when the EVM node was not confirmed.
    private func ownbitTronAddress(_ walletId: String, _ publicIndex: BILJSONObject, _ ok: BILPublicVerifyMatches,
                                   _ n: Int) async throws -> String? {
        guard ok.confirmed(BILPairingExportPolicy.evmKey(0)) else { return nil }
        let evm = try await evmNodeAddress(publicIndex, n)
        guard BILPublicPairingService.isEvmAddress(evm),
              let tron = BILTronAddressCodec.base58(fromHex41: "41" + String(evm.dropFirst(2)).lowercased()) else {
            throw BILMalformedEngineResult(what: "addresses.evm.address")
        }
        // Fresh row (Android re-reads the TRX account after the engine call).
        if let row = wallets.facts(walletId: walletId), row.trxIndex == n,
           let stored = BILPublicWalletFacts.nonBlank(row.trxAddress), !BILJSONExact.equal(stored, tron) {
            BILPublicLog.code("pairing", "TRX_ROW_DIFFERS")
            throw BILPublicPairingError.keysMismatch(.tron)
        }
        return tron
    }

    /// EVM address mode at Ownbit's #`n`: the engine's address of `m/44'/60'/0'/0/N`, rendered as the engine's address mode.
    private func evmAddress(_ publicIndex: BILJSONObject, _ selection: BILPairingSelection, _ n: Int,
                            _ fingerprint: String) async throws -> BILPublicPairingQr {
        let address = try await evmNodeAddress(publicIndex, n)
        let path = BILPublicPairingQr.evmPath(n)
        guard BILPublicPairingQr.isAddressOnlyValid(selection: selection, address: address, path: path, addressIndex: n) else {
            throw BILMalformedEngineResult(what: "addresses.evm.address")
        }
        return BILPublicPairingQr.addressOnly(selection: selection, address: address, path: path, addressIndex: n,
                                              fingerprint: fingerprint)
    }

    /// `derivePublicAddresses(index, "evm", nil, start: n, count: 1)`: the first entry must be at `m/44'/60'/0'/0/n` with
    /// `index == n` and carry a non-empty address (else malformed).
    private func evmNodeAddress(_ publicIndex: BILJSONObject, _ n: Int) async throws -> String {
        let result = try await engine.derivePublicAddresses(publicIndex: publicIndex, chain: BILPsChain.evm.rawValue,
                                                            profile: nil, start: n, count: 1)
        guard let first = result.arr("addresses")?.first?.objectValue else {
            throw BILMalformedEngineResult(what: "addresses.evm")
        }
        try BILEngineJSON.ensure(BILPublicPairingService.same(first.str("path"), BILPublicPairingQr.evmPath(n)) && first.int("index") == n,
                                 "addresses.evm.path")
        guard let address = first.str("address"), !address.isEmpty else {
            throw BILMalformedEngineResult(what: "addresses.evm.address")
        }
        return address
    }

    // MARK: - Helpers

    /// Engine, bridge and malformed-result failures (Android `PublicSignerException` / `JsException` /
    /// `MalformedEngineResultException` → ENGINE); an Ownbit bridge that failed or timed out is an engine-class failure,
    /// never a key mismatch (R2 §6.2).
    private nonisolated static func isEngineClass(_ error: Error) -> Bool {
        return error is BILPublicSignerFailure || error is BILMalformedEngineResult || error is BILOwnbitAddressDeriveError
            || error is BILPublicTimeout.Expired
    }

    /// `^0x[0-9a-fA-F]{40}$` over the whole text.
    private nonisolated static func isEvmAddress(_ s: String) -> Bool {
        let u = Array(s.utf8)
        guard u.count == 42, u[0] == 0x30, u[1] == 0x78 else { return false }
        for c in u[2...] {
            switch c {
            case 0x30...0x39, 0x41...0x46, 0x61...0x66: continue
            default: return false
            }
        }
        return true
    }

    /// Exact (code-unit) equality of optional texts (Kotlin `==`).
    private nonisolated static func same(_ a: String?, _ b: String?) -> Bool {
        guard let a = a, let b = b else { return a == nil && b == nil }
        return BILJSONExact.equal(a, b)
    }

    /// Kotlin `equals(ignoreCase = true)` for EVM addresses: equal UTF-16 lengths and equal units after ASCII case folding
    /// (non-ASCII letters compared exactly: stricter than Kotlin's Unicode folding, fails closed).
    private nonisolated static func sameIgnoringASCIICase(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf16), y = Array(b.utf16)
        guard x.count == y.count else { return false }
        for (p, q) in zip(x, y) where p != q {
            let fp = (p >= 0x41 && p <= 0x5A) ? p + 0x20 : p
            let fq = (q >= 0x41 && q <= 0x5A) ? q + 0x20 : q
            if fp != fq { return false }
        }
        return true
    }
}
