//  PPPairingFakes.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Port of the app harness suite `scripts/public-protocol/tests/pairing` (Fakes.swift) to XCTest.
//
//  Fakes.swift — suite "pairing" (WP14): the golden-vector engine (incl. `createPublicPairing`), Ownbit's bridges, the
//  wallet directory and an in-memory Keychain — the pairing graph of Android PST:testing/{PublicIndexFakes,IndexTestEnv,
//  EngineVectors}.kt — plus scripted service / index store, a recording logger and a virtual clock for the panel model.
//  Test code only (never compiled into the app). The real WP11 repository and verifier run on top of these fakes.
//

import Foundation
import XCTest
import CryptoKit
import Security
@testable import OwnbitCore

extension PPPairingSuite {

    /// Stands for the md5 entry of an envelope the app wrote (`[sha256, md5]`); the package has no md5 hash gate.
    static let legacyHash = "0123456789abcdef0123456789abcdef"

    // MARK: - Vector wallets (Android OwnbitVectors; never fund these addresses)

    enum OV {
        static let LEGACY_0 = "1LqBGSKuX5yYUonjxT5qGfpUsXKYYWeabA"
        static let NESTED_0 = "37VucYSaXLCAsxYyAPfbSi9eh4iEcbShgf"
        static let NATIVE_0 = "bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu"
        static let TAPROOT_0 = "bc1p5cyxnuxmeuwuvkwfem96lqzszd02n6xdcjrs20cac6yqjjwudpxqkedrcr"
        static let ETH_0 = "0x9858EfFD232B4033E47d90003D41EC34EcaEda94"
        static let ETH_7 = "0x593814d3309e2dF31D112824F0bb5aa7Cb0D7d47"
        static let TRX_0 = "TUEZSdKsoDHQMeZwihtdoBiN46zxhGWYdH"
        static let TRX_OWNBIT_1 = "TL9gR3f4FgNa9VZAsPt6xuKXPrfWAUJ5MW"
        static let TRX_STANDARD_1 = "TSeJkUh4Qv67VNFwY8LaAxERygNdy6NQZK"
        static let TRX_OWNBIT_99 = "TA3BzrCakatwmNMKrhP6FZnzQM52hoc8J8"
        static let TRX_OWNBIT_100 = "TLNVDDkvZW3ZeAirXtQ2Gxkpmph4366oiJ"
        static let SOL = "HAgk14JpMQLgt6rVgv7cBQFJWFto5Dqxi472uT3DKpqk"
        static let SOL_TRUST = "GjJyeC1r2RgkuoCWMyPYkCWSGSGLcz266EaAkLA27AhL"
        static let SOL_LEGACY = "D2PPQSYFe83nDzk96FqGumVU8JA7J8vj2Rhjc2oXzEi5"

        static let XPUB_LEGACY = "xpubLegacyAbandon"
        static let YPUB_NESTED = "ypubNestedAbandon"
        static let ZPUB_NATIVE = "zpubNativeAbandon"
        static let XPUB_TAPROOT = "xpubTaprootAbandon"
        static let XPUB_ETH = "xpubEthAbandon"
        static let XPUB_LEGACY_LEGAL = "xpubLegacyLegal"
        static let XPUB_ETH_LEGAL = "xpubEthLegal"
        static let OTHER_LEGACY_0 = "1JMqHeWNEmzUBUh5EPGCBHXz6ffhpJtaFh"
        static let ETH_0_LEGAL = "0x58A57ed9d8d624cBD12e2C467D34787555bB1b25"
    }

    // MARK: - Golden vectors (Android EngineVectors)

    final class Vectors {
        let root: BILJSONObject
        let cases: [BILJSONObject]
        let fixtures: BILJSONObject

        init(text: String) {
            guard let root = BILStrictJSON.parseObject(text, options: BILStrictJSON.Options(maxDepth: 512)),
                  let cases = root.arr("cases")?.compactMap({ $0.objectValue }), let fixtures = root.obj("fixtures") else {
                print("FAIL vectors.json does not parse")
                fatalError("harness fixture problem")
            }
            self.root = root
            self.cases = cases
            self.fixtures = fixtures
        }

        func seedHex(_ id: String) -> String {
            for m in root.arr("mnemonics") ?? [] {
                if let o = m.objectValue, o.str("id") == id, let s = o.str("seedHex") { return s }
            }
            print("FAIL no vector seed \(id)")
            fatalError("harness fixture problem")
        }

        func publicIndex(_ id: String) -> BILJSONObject {
            guard let o = fixtures.obj("publicIndex." + id) else {
                print("FAIL no fixture publicIndex.\(id)")
                fatalError("harness fixture problem")
            }
            return o
        }

        struct Step { let request: BILJSONObject; let response: BILJSONObject
            var result: BILJSONObject? { return response.bool("ok") == true ? response.obj("result") : nil }
        }

        func steps(_ op: String) -> [Step] {
            var out: [Step] = []
            for c in cases {
                for s in c.arr("steps") ?? [] {
                    guard let o = s.objectValue, let req = o.obj("request"), let resp = o.obj("response") else { continue }
                    if req.str("operation") == op { out.append(Step(request: req, response: resp)) }
                }
            }
            return out
        }

        /// The first step of vector case `id`.
        func caseStep(_ id: String) -> Step? {
            guard let c = cases.first(where: { $0.str("id") == id }), let s = c.arr("steps")?.first?.objectValue,
                  let req = s.obj("request"), let resp = s.obj("response") else { return nil }
            return Step(request: req, response: resp)
        }

        static let nodeKeys = ["walletKeyId", "masterFingerprint", "bitcoinPublicNodes", "evmAccountNode", "tronAccountNode", "solanaPublicKeys"]

        func sameNodes(_ a: BILJSONObject, _ b: BILJSONObject) -> Bool {
            return Vectors.nodeKeys.allSatisfy { a[$0] != nil && a[$0] == b[$0] }
        }

        func standardIndex(_ seed: String) -> BILJSONObject? {
            return steps("derivePublicIndex").first { $0.request.str("seed") == seed && !$0.request.contains("tronScheme") }?.result
        }

        func derivePublicIndex(_ seed: String, _ scheme: String?, _ count: Int?) -> BILJSONObject? {
            if scheme == nil && count == nil { return standardIndex(seed) }
            guard let standard = standardIndex(seed) else { return nil }
            let ownbit = publicIndex("abandonOwnbit")
            return scheme == "ownbit" && (count ?? 100) == 100 && sameNodes(standard, ownbit) ? ownbit : nil
        }

        func refreshPublicIndex(_ index: BILJSONObject, _ scheme: String, _ count: Int?) -> BILJSONObject? {
            let ownbit = publicIndex("abandonOwnbit")
            return scheme == "ownbit" && (count ?? 100) == 100 && sameNodes(index, ownbit) ? ownbit : nil
        }

        /// The vector wallet of `index` by its key nodes; Ownbit's TRON scheme changes only TRON (#N ≥ 1).
        private func fixtureId(_ index: BILJSONObject, _ chain: String) -> String? {
            guard let id = ["abandon", "legal"].first(where: { sameNodes(publicIndex($0), index) }) else { return nil }
            let ownbit = index.str("tronScheme") == "ownbit"
            return ownbit && chain == "tron" && id == "abandon" ? "abandonOwnbit" : id
        }

        private func normalized(_ chain: String, _ profile: String?) -> String {
            return profile ?? (chain == "bitcoin" ? "native" : "standard")
        }

        private func page(_ fixture: String, _ chain: String, _ profile: String?, _ start: Int, _ count: Int) -> [BILJSONValue]? {
            for step in steps("derivePublicAddresses") {
                let r = step.request
                let pageStart = r.int("start") ?? 0
                let pageCount = r.int("count") ?? 20
                guard r.obj("publicIndex")?.str("$fixture") == "publicIndex." + fixture, r.str("chain") == chain,
                      normalized(chain, r.str("profile")) == normalized(chain, profile),
                      start >= pageStart, start + count <= pageStart + pageCount, let result = step.result,
                      let all = result.arr("addresses") else { continue }
                return Array(all.dropFirst(start - pageStart).prefix(count))
            }
            return nil
        }

        /// `derivePublicAddresses` from the vector pages (T3b). EVM addresses with no EVM page (Ownbit TRX #99 / #100 come from
        /// EVM #99 / #100) are derived from the Ownbit-scheme TRON page of the same index, whose entries ARE the EVM key's
        /// addresses at `m/44'/60'/0'/0/N` TRON-encoded: re-encoded as EIP-55 (`synthesizedEvm`, checked against the real EVM
        /// page for #1 by the suite).
        func derivePublicAddresses(_ index: BILJSONObject, _ chain: String, _ profile: String?, _ start: Int, _ count: Int) -> BILJSONObject? {
            guard let fixture = fixtureId(index, chain) else { return nil }
            let slice: [BILJSONValue]
            if let real = page(fixture, chain, profile, start, count) {
                slice = real
            } else if chain == "evm", profile == nil, fixture == "abandon", let synthesized = synthesizedEvm(start, count) {
                slice = synthesized
            } else {
                return nil
            }
            return BILJSONObject([("addresses", .array(slice)), ("hasMore", .bool(chain != "solana")), ("nextIndex", .int(start + count))])
        }

        func synthesizedEvm(_ start: Int, _ count: Int) -> [BILJSONValue]? {
            guard let tron = page("abandonOwnbit", "tron", nil, start, count) else { return nil }
            var out: [BILJSONValue] = []
            for entry in tron {
                guard var o = entry.objectValue, let path = o.str("path"), path.hasPrefix("m/44'/60'/0'/0/"),
                      let address = o.str("address"), let hex = BILTronAddressCodec.hex41(fromBase58: address) else { return nil }
                o.set("chain", .string("evm"))
                o.set("address", .string(Vectors.eip55(String(hex.dropFirst(2)))))
                out.append(.object(o))
            }
            return out
        }

        /// EIP-55 checksum spelling of 40 hex digits.
        static func eip55(_ hex40: String) -> String {
            let lower = Array(hex40.lowercased().utf8)
            let hash = BILPublicHash.keccak256(lower)
            var out = "0x"
            for (i, c) in lower.enumerated() {
                let nibble = (hash[i / 2] >> (i % 2 == 0 ? 4 : 0)) & 0x0F
                let ch = Character(Unicode.Scalar(c))
                out.append(c >= 0x61 && c <= 0x66 && nibble >= 8 ? Character(String(ch).uppercased()) : ch)
            }
            return out
        }

        /// `createPublicPairing` with `deviceName: Ownbit` (T3); nil when no vector has this export.
        func createPublicPairing(_ index: BILJSONObject, _ chain: String, _ profile: String?, _ mode: String?, _ addressIndex: Int) -> BILJSONObject? {
            guard let fixture = fixtureId(index, chain) else { return nil }
            for step in steps("createPublicPairing") {
                let r = step.request
                // iOS never sends fragmentLength (D-03): the animated cases are not exports of the app.
                guard !r.contains("fragmentLength"), r.obj("publicIndex")?.str("$fixture") == "publicIndex." + fixture, r.str("chain") == chain,
                      r.str("deviceName") == "Ownbit", normalized(chain, r.str("profile")) == normalized(chain, profile),
                      r.str("outputMode") == mode, (r.int("index") ?? 0) == addressIndex, let result = step.result else { continue }
                return result
            }
            return nil
        }
    }

    // MARK: - Engine (Android VectorEngine)

    struct EngineCall: Equatable, CustomStringConvertible {
        let op: String
        var chain: String? = nil
        var profile: String? = nil
        var mode: String? = nil
        var index: Int? = nil

        var description: String {
            return op + "(" + [chain ?? "-", profile ?? "-", mode ?? "-", index.map { String($0) } ?? "-"].joined(separator: ",") + ")"
        }
    }

    final class FakeEngine: BILPublicSignerEngining, @unchecked Sendable {
        let vectors: Vectors
        private let lock = NSLock()
        private var _calls: [EngineCall] = []
        private var _refuse: [String: String] = [:]
        private var _failOnce: [String: BILPublicSignerFailure] = [:]
        private var _available = true
        private var _probeFailures = 0
        private var _addressOverride: [String: String] = [:]
        private var _pairingAddressOverride: String?
        private var _pairingPatch: ((BILJSONObject) -> BILJSONObject)?
        private var _indexesSeen: [BILJSONObject] = []
        private var _nthPatches: [String: (nth: Int, patch: (BILJSONObject) -> BILJSONObject)] = [:]
        private var _deriveCounts: [String: Int] = [:]

        init(_ vectors: Vectors) { self.vectors = vectors }

        private func locked<T>(_ body: () -> T) -> T { lock.lock(); defer { lock.unlock() }; return body() }

        var calls: [EngineCall] { return locked { _calls } }
        func count(_ op: String) -> Int { return calls.filter { $0.op == op }.count }
        func calls(_ op: String) -> [EngineCall] { return calls.filter { $0.op == op } }
        /// Calls other than the identity probe.
        var workCalls: [EngineCall] { return calls.filter { $0.op != "isAvailable" } }
        var available: Bool { get { return locked { _available } } set { locked { _available = newValue } } }
        /// The next `n` probes fail (then `available` decides) — Android's engine gate / iOS `-bil_debug_pub_engine_fail`.
        func failProbes(_ n: Int) { locked { _probeFailures = n } }
        func refuse(_ op: String, _ code: String?) { locked { _refuse[op] = code } }
        /// The next call of `op` fails once with `failure` (a JS failure, not a refusal).
        func failOnce(_ op: String, _ failure: BILPublicSignerFailure) { locked { _failOnce[op] = failure } }
        /// A lying engine: `derivePublicAddresses(chain, profile, start)` answers `address` as its first entry.
        func override(chain: String, profile: String?, start: Int, address: String?) {
            locked { _addressOverride[chain + "|" + (profile ?? "-") + "|" + String(start)] = address }
        }
        /// `createPublicPairing` answers this first address (engine inconsistent with its own address derivation).
        var pairingAddressOverride: String? { get { return locked { _pairingAddressOverride } } set { locked { _pairingAddressOverride = newValue } } }
        /// Any change to a `createPublicPairing` answer (malformed results).
        var pairingPatch: ((BILJSONObject) -> BILJSONObject)? { get { return locked { _pairingPatch } } set { locked { _pairingPatch = newValue } } }
        var indexesSeen: [BILJSONObject] { return locked { _indexesSeen } }
        func reset() { locked { _calls.removeAll(); _indexesSeen.removeAll(); _deriveCounts.removeAll() } }
        /// Only the `nth` (1-based, counted from now) `derivePublicAddresses(chain, profile, start)` call answers its first entry
        /// changed by `patch` (e.g. the cross-check's call stays honest, the export's call lies).
        func patchNth(chain: String, profile: String?, start: Int, nth: Int, _ patch: @escaping (BILJSONObject) -> BILJSONObject) {
            let key = chain + "|" + (profile ?? "-") + "|" + String(start)
            locked {
                _deriveCounts[key] = 0
                _nthPatches[key] = (nth, patch)
            }
        }

        private func record(_ c: EngineCall) throws {
            let (code, failure): (String?, BILPublicSignerFailure?) = locked {
                _calls.append(c)
                return (_refuse[c.op], _failOnce.removeValue(forKey: c.op))
            }
            if let f = failure { throw f }
            if let code = code { throw BILPublicSignerRefusal(code: code, engineMessage: "refused at address 1LqBGSKuX5yYUonjxT5qGfpUsXKYYWeabA") }
        }

        func capabilities() async throws -> BILJSONObject { throw BILPublicSignerFailure.invalidRequest }

        func derivePublicAddresses(publicIndex: BILJSONObject, chain: String, profile: String?, start: Int, count: Int) async throws -> BILJSONObject {
            try record(EngineCall(op: "derivePublicAddresses", chain: chain, profile: profile, index: start))
            locked { _indexesSeen.append(publicIndex) }
            guard let result = vectors.derivePublicAddresses(publicIndex, chain, profile, start, count) else {
                throw BILPublicSignerRefusal(code: "INDEX", engineMessage: "no vector page")
            }
            let key = chain + "|" + (profile ?? "-") + "|" + String(start)
            let nthPatch: ((BILJSONObject) -> BILJSONObject)? = locked {
                _deriveCounts[key, default: 0] += 1
                guard let p = _nthPatches[key], p.nth == _deriveCounts[key] else { return nil }
                return p.patch
            }
            if let patch = nthPatch, let first = result.arr("addresses")?.first?.objectValue {
                var patched = result
                patched.set("addresses", .array([.object(patch(first))]))
                return patched
            }
            guard let o = locked({ _addressOverride[key] }), var first = result.arr("addresses")?.first?.objectValue else { return result }
            first.set("address", .string(o))
            var patched = result
            patched.set("addresses", .array([.object(first)]))
            return patched
        }

        func createPublicPairing(publicIndex: BILJSONObject, chain: String, profile: String?, outputMode: String?, index: Int) async throws -> BILJSONObject {
            try record(EngineCall(op: "createPublicPairing", chain: chain, profile: profile, mode: outputMode, index: index))
            locked { _indexesSeen.append(publicIndex) }
            guard var result = vectors.createPublicPairing(publicIndex, chain, profile, outputMode, index) else {
                throw BILPublicSignerRefusal(code: "PROFILE", engineMessage: "no vector export")
            }
            if let a = pairingAddressOverride { result.set("address", .string(a)) }
            if let patch = pairingPatch { result = patch(result) }
            return result
        }

        func releasePairingContext() async {}

        func derivePublicIndex(seedHex: String, tronScheme: String?, tronAddressCount: Int?) async throws -> BILJSONObject {
            try record(EngineCall(op: "derivePublicIndex"))
            guard let index = vectors.derivePublicIndex(seedHex, tronScheme, tronAddressCount) else {
                throw BILPublicSignerRefusal(code: "SEED", engineMessage: "no vector for this seed")
            }
            return index
        }

        func refreshPublicIndex(publicIndex: BILJSONObject, tronScheme: String, tronAddressCount: Int?) async throws -> BILJSONObject {
            try record(EngineCall(op: "refreshPublicIndex"))
            guard let index = vectors.refreshPublicIndex(publicIndex, tronScheme, tronAddressCount) else {
                throw BILPublicSignerRefusal(code: "PUBLIC_INDEX", engineMessage: "no vector for this index")
            }
            return index
        }

        func signPlanTask(request: BILJSONObject, plan: BILJSONObject, taskId: String, seedHex: String,
                          riskAcknowledged: Bool, previousResult: BILJSONObject?) async throws -> BILJSONObject {
            throw BILPublicSignerFailure.invalidRequest
        }
        func decodePayload(_ payload: String) async throws -> BILJSONObject { throw BILPublicSignerFailure.invalidRequest }
        func reviewAndResolve(request: BILJSONObject, wallets: [BILJSONObject]) async throws -> BILPublicReviewAndPlan {
            throw BILPublicSignerFailure.invalidRequest
        }
        func encodeResponse(request: BILJSONObject, result: BILJSONObject) async throws -> BILJSONObject { throw BILPublicSignerFailure.invalidRequest }
        func openScan() async throws -> BILPublicScanHandle { throw BILPublicSignerFailure.invalidRequest }
        func scanAdd(_ handle: BILPublicScanHandle, frame: String) async throws -> BILJSONObject { throw BILPublicSignerFailure.invalidRequest }
        func closeScan(_ handle: BILPublicScanHandle) async {}

        func isAvailable() async -> Bool {
            return locked {
                _calls.append(EngineCall(op: "isAvailable"))
                if _probeFailures > 0 {
                    _probeFailures -= 1
                    return false
                }
                return _available
            }
        }
    }

    // MARK: - Ownbit bridges (Android OwnbitBridges)

    @MainActor final class FakeDeriver: BILOwnbitAddressDeriving {
        var bitcoinCalls: [String] = []
        var ethCalls: [String] = []
        var fail = false

        func btcLegacy(xpub: String) async throws -> String {
            bitcoinCalls.append("legacy|" + xpub)
            if fail { throw BILOwnbitAddressDeriveError.timeout }
            switch xpub {
            case OV.XPUB_LEGACY: return OV.LEGACY_0
            case OV.XPUB_LEGACY_LEGAL: return OV.OTHER_LEGACY_0
            default: return "1UnknownXpubAddress" + xpub
            }
        }
        func btcNested(xpub: String) async throws -> String {
            bitcoinCalls.append("nested|" + xpub)
            if fail { throw BILOwnbitAddressDeriveError.timeout }
            return xpub == OV.YPUB_NESTED ? OV.NESTED_0 : "3Unknown" + xpub
        }
        func btcNative(xpub: String) async throws -> String {
            bitcoinCalls.append("native|" + xpub)
            if fail { throw BILOwnbitAddressDeriveError.timeout }
            return xpub == OV.ZPUB_NATIVE ? OV.NATIVE_0 : "bc1qunknown" + xpub
        }
        func btcTaproot(xpub: String) async throws -> String {
            bitcoinCalls.append("taproot|" + xpub)
            if fail { throw BILOwnbitAddressDeriveError.timeout }
            return xpub == OV.XPUB_TAPROOT ? OV.TAPROOT_0 : "bc1pUnknown"
        }
        func ethAddress(xpub: String, index: Int) async throws -> String {
            ethCalls.append(xpub + "|" + String(index))
            if fail { throw BILOwnbitAddressDeriveError.timeout }
            if xpub == OV.XPUB_ETH && index == 0 { return OV.ETH_0.lowercased() }
            if xpub == OV.XPUB_ETH && index == 7 { return OV.ETH_7.lowercased() }
            if xpub == OV.XPUB_ETH_LEGAL && index == 0 { return OV.ETH_0_LEGAL.lowercased() }
            return "0x" + String(repeating: "ab", count: 20)
        }
    }

    // MARK: - Wallet directory (Android insertOwnbitWallet + walletDao / chainAccountDao / addressDao)

    struct FakeWallet {
        var traits: BILPublicSignerEligibility.Traits
        var facts: BILPublicWalletFacts
        var password: String
        var seed: String?
    }

    @MainActor final class FakeDirectory: BILPublicWalletDirectory {
        var wallets: [String: FakeWallet] = [:]
        var order: [String] = []

        func put(_ id: String, _ w: FakeWallet) {
            if wallets[id] == nil { order.append(id) }
            wallets[id] = w
        }
        func remove(_ id: String) {
            wallets[id] = nil
            order.removeAll { $0 == id }
        }

        func eligibleWalletIds() -> [String] {
            return order.filter { wallets[$0].map { BILPublicSignerEligibility.rule($0.traits).isEligible } ?? false }
        }
        func eligibility(walletId: String) -> BILPublicEligibility {
            guard let w = wallets[walletId] else { return .notEligible(.unknownWallet) }
            return BILPublicSignerEligibility.rule(w.traits)
        }
        func facts(walletId: String) -> BILPublicWalletFacts? {
            return wallets[walletId]?.facts
        }
        func seed(walletId: String, password: String) -> String? {
            guard let w = wallets[walletId], w.password == password else { return nil }
            return w.seed
        }
        func allWalletIds() throws -> Set<String> {
            return Set(wallets.keys)
        }
    }

    // MARK: - In-memory Keychain

    final class MemoryKeyStore: BILPublicIndexKeyStore, @unchecked Sendable {
        private let lock = NSLock()
        private var entries: [String: Data] = [:]
        private var keyData: Data?
        private var _readError: OSStatus?

        private func locked<T>(_ body: () throws -> T) rethrows -> T { lock.lock(); defer { lock.unlock() }; return try body() }

        /// Every entry read fails with this status (e.g. -25308 errSecInteractionNotAllowed while the device is locked).
        var readError: OSStatus? { get { return locked { _readError } } set { locked { _readError = newValue } } }

        func raw(_ id: String) -> Data? { return locked { entries[id] } }
        func setRaw(_ id: String, _ data: Data?) { locked { entries[id] = data } }
        func loseKey() { locked { keyData = nil } }

        func readEntry(walletId: String) throws -> Data? {
            return try locked {
                if let s = _readError { throw BILPublicKeychainError(status: s) }
                return entries[walletId]
            }
        }
        func writeEntry(walletId: String, data: Data) throws {
            locked { entries[walletId] = data }
        }
        func deleteEntry(walletId: String) throws {
            locked { entries[walletId] = nil }
        }
        func entryWalletIds() throws -> [String] {
            return locked { Array(entries.keys) }
        }
        func key(create: Bool) throws -> SymmetricKey? {
            return try locked {
                if let d = keyData {
                    guard d.count == 32 else { throw BILPublicKeychainError.unusableKey }
                    return SymmetricKey(data: d)
                }
                guard create else { return nil }
                let d = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
                keyData = d
                return SymmetricKey(data: d)
            }
        }
        func replaceKey() throws -> SymmetricKey {
            return locked {
                let d = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
                keyData = d
                return SymmetricKey(data: d)
            }
        }
    }

    // MARK: - Recording logger (Android `hooks = mockk<SecurityHooks>`)

    // (The app's pairing-log fakes — Security Center hooks of the pairing panel model — are not ported.)

    /// A host controller stand-in (`page` of the hooks).
    final class FakePage {}

    // MARK: - Environment (Android IndexTestEnv)

    enum Fx {
        static let NOW: TimeInterval = 1_760_000_000
        static let PASSWORD = "Passw0rd!x"
        static let W = "w0cold0001"

        static func traits(cold: Bool = true, multisig: Bool = false, watch: Bool = false, seed: Bool = true,
                           exists: Bool = true) -> BILPublicSignerEligibility.Traits {
            return BILPublicSignerEligibility.Traits(exists: exists, isMultisig: multisig, isObserver: watch, hasSeed: seed,
                                                     isPrivateKey: false, isMerchant: false, hasCustomPathMarker: false,
                                                     isElectrum: false, isCold: cold)
        }
    }

    @MainActor final class Env {
        let vectors: Vectors
        let engine: FakeEngine
        let deriver = FakeDeriver()
        let directory = FakeDirectory()
        let keys = MemoryKeyStore()
        let verifier: BILPublicIndexVerifier
        let repository: BILPublicIndexRepository
        let service: BILPublicPairingService

        init(_ vectors: Vectors) {
            self.vectors = vectors
            engine = FakeEngine(vectors)
            verifier = BILPublicIndexVerifier(engine: engine, deriver: deriver)
            repository = BILPublicIndexRepository(engine: engine, wallets: directory, keys: keys, verifier: verifier,
                                                  now: { Date(timeIntervalSince1970: Fx.NOW) })
            repository.orphanCleanupDelay = 0
            service = BILPublicPairingService(engine: engine, index: repository, wallets: directory,
                                              verifier: BILPublicIndexVerifier(engine: engine, deriver: deriver))
        }

        var abandonSeed: String { return vectors.seedHex("abandon") }

        /// The abandon wallet as Android `insertOwnbitWallet` stores it (iOS field names): BTC legacy + native in use
        /// (+ nested), ETH #`ethIndex`, TRX #`trxIndex` (#0 backed up in `trxAddress0`), SOL.
        func abandonFacts(_ id: String, cold: Bool = true, ethIndex: Int = 0, trxIndex: Int = 0, withTaproot: Bool = false,
                          nestedUsed: Bool = false, withSol: Bool = true) -> BILPublicWalletFacts {
            var inUse: [BILPsBitcoinProfile] = [.legacy, .native]
            if nestedUsed { inUse.append(.nested) }
            return BILPublicWalletFacts(walletId: id, kind: cold ? .cold : .normal,
                                        seedHash: BILPublicHash.sha256Hex(utf8: abandonSeed),
                                        legacyXpub: OV.XPUB_LEGACY, nestedXpub: OV.YPUB_NESTED, nativeXpub: OV.ZPUB_NATIVE,
                                        taprootXpub: withTaproot ? OV.XPUB_TAPROOT : nil,
                                        ethXpub: OV.XPUB_ETH, ethAddress: (ethIndex == 7 ? OV.ETH_7 : OV.ETH_0).lowercased(), ethIndex: ethIndex,
                                        trxAddress: trxIndex == 0 ? OV.TRX_0 : OV.TRX_OWNBIT_1, trxAddress0: OV.TRX_0, trxIndex: trxIndex,
                                        solAddress: withSol ? OV.SOL : nil,
                                        btcProfilesInUse: inUse)
        }

        func addWallet(_ id: String = Fx.W, cold: Bool = true, ethIndex: Int = 0, trxIndex: Int = 0, withTaproot: Bool = false,
                       nestedUsed: Bool = false, traits: BILPublicSignerEligibility.Traits? = nil) {
            directory.put(id, FakeWallet(traits: traits ?? Fx.traits(cold: cold),
                                         facts: abandonFacts(id, cold: cold, ethIndex: ethIndex, trxIndex: trxIndex, withTaproot: withTaproot,
                                                             nestedUsed: nestedUsed),
                                         password: Fx.PASSWORD, seed: abandonSeed))
        }

        /// The wallet, prepared through the real repository (index sealed in the memory Keychain); engine calls cleared.
        func prepared(_ id: String = Fx.W, cold: Bool = true, ethIndex: Int = 0, trxIndex: Int = 0, withTaproot: Bool = false,
                      nestedUsed: Bool = false) async -> Bool {
            addWallet(id, cold: cold, ethIndex: ethIndex, trxIndex: trxIndex, withTaproot: withTaproot, nestedUsed: nestedUsed)
            let r = await repository.prepare(walletId: id, password: Fx.PASSWORD)
            engine.reset()
            if case .ready = r { return true }
            print("FAIL prepare did not succeed: \(r)")
            return false
        }

        /// Changes the stored wallet facts (Android `accountDao.upsert`).
        func setFacts(_ id: String = Fx.W, _ change: (BILPublicWalletFacts) -> BILPublicWalletFacts) {
            guard var w = directory.wallets[id] else { return }
            w.facts = change(w.facts)
            directory.wallets[id] = w
        }

        /// Seals `index` for the wallet directly (an index stored by an older app version), with the wallet's seed hashes.
        func sealDirectly(_ id: String, kind: BILPublicWalletKind, index: BILJSONObject) throws {
            guard let key = try keys.key(create: true) else { return }
            let sealed = try BILPublicIndexSealer.seal(Data(BILStrictJSON.serialize(index).utf8), key: key, walletId: id, kind: kind)
            let envelope = BILPublicIndexEnvelope(formatVersion: 1,
                                                  seedHashes: [BILPublicHash.sha256Hex(utf8: abandonSeed), legacyHash],
                                                  createdAtMs: 1, sealed: BILBase64Strict.encode([UInt8](sealed)))
            keys.setRaw(id, envelope.encoded())
        }

    }

    /// Facts with fields changed (BILPublicWalletFacts is immutable).
    static func with(_ f: BILPublicWalletFacts, ethXpub: String?? = nil, ethAddress: String?? = nil, legacyXpub: String?? = nil,
              trxAddress: String?? = nil, trxIndex: Int? = nil) -> BILPublicWalletFacts {
        return BILPublicWalletFacts(walletId: f.walletId, kind: f.kind, seedHash: f.seedHash,
                                    legacyXpub: legacyXpub ?? f.legacyXpub, nestedXpub: f.nestedXpub,
                                    nativeXpub: f.nativeXpub, taprootXpub: f.taprootXpub,
                                    ethXpub: ethXpub ?? f.ethXpub, ethAddress: ethAddress ?? f.ethAddress, ethIndex: f.ethIndex,
                                    trxAddress: trxAddress ?? f.trxAddress, trxAddress0: f.trxAddress0,
                                    trxIndex: trxIndex ?? f.trxIndex, solAddress: f.solAddress,
                                    btcProfilesInUse: f.btcProfilesInUse)
    }

    // MARK: - Scripted service / index store (Android mockk<PublicPairingService> / mockk<PublicIndexRepository>)

    /// A value the test resolves later (Android `CompletableDeferred`); waiters that are never resolved stay suspended.
    @MainActor final class Pending<T> {
        private var value: T?
        private var waiters: [CheckedContinuation<T, Never>] = []

        func wait() async -> T {
            if let v = value { return v }
            return await withCheckedContinuation { (c: CheckedContinuation<T, Never>) in waiters.append(c) }
        }

        func resolve(_ v: T) {
            value = v
            let all = waiters
            waiters.removeAll()
            for c in all { c.resume(returning: v) }
        }
    }

    @MainActor final class ScriptedService: BILPublicPairingServicing {
        var factsResult: BILWalletPairingFacts? = BILWalletPairingFacts(kind: .cold)
        var handler: @MainActor (BILPairingSelection, Int) async throws -> BILPublicPairingQr
        private(set) var asked: [(selection: BILPairingSelection, tron: Int)] = []

        init(_ handler: @escaping @MainActor (BILPairingSelection, Int) async throws -> BILPublicPairingQr) {
            self.handler = handler
        }

        func facts(walletId: String) throws -> BILWalletPairingFacts {
            guard let f = factsResult else { throw BILPublicPairingError.notEligible }
            return f
        }

        func pairing(walletId: String, selection: BILPairingSelection, tronIndex: Int) async throws -> BILPublicPairingQr {
            asked.append((selection, tronIndex))
            return try await handler(selection, tronIndex)
        }

        func askedCount(_ sel: BILPairingSelection? = nil, tron: Int? = nil) -> Int {
            return asked.filter { (sel == nil || $0.selection == sel!) && (tron == nil || $0.tron == tron!) }.count
        }
    }

    @MainActor final class ScriptedIndex: BILPublicIndexStoring {
        var statusValue: BILPublicIndexStatus = .ready(fingerprint: "73C5DA0A")
        /// When set, answers `status` instead of `statusValue` (arg = the 1-based read number).
        var statusHandler: (@MainActor (Int) async -> BILPublicIndexStatus)?
        var prepareValue: BILPublicPrepareResult = .ready(fingerprint: "73C5DA0A")
        var onPrepare: (@MainActor () -> Void)?
        private(set) var statusReads = 0
        private(set) var prepares: [String] = []

        func status(walletId: String) async -> BILPublicIndexStatus {
            statusReads += 1
            if let h = statusHandler { return await h(statusReads) }
            return statusValue
        }
        func load(walletId: String) async -> (status: BILPublicIndexStatus, index: BILJSONObject?) {
            return (statusValue, nil)
        }
        func prepare(walletId: String, password: String) async -> BILPublicPrepareResult {
            prepares.append(password)
            onPrepare?()
            return prepareValue
        }
        func resolverInputs() async -> [BILJSONObject] { return [] }
    }

    /// The real repository with a hook run during `load` (the wallet changes while the index is read).
    @MainActor final class HookedIndex: BILPublicIndexStoring {
        let inner: BILPublicIndexStoring
        var onLoad: (@MainActor () -> Void)?
        init(_ inner: BILPublicIndexStoring) { self.inner = inner }
        func status(walletId: String) async -> BILPublicIndexStatus { return await inner.status(walletId: walletId) }
        func load(walletId: String) async -> (status: BILPublicIndexStatus, index: BILJSONObject?) {
            let r = await inner.load(walletId: walletId)
            onLoad?()
            return r
        }
        func prepare(walletId: String, password: String) async -> BILPublicPrepareResult {
            return await inner.prepare(walletId: walletId, password: password)
        }
        func resolverInputs() async -> [BILJSONObject] { return await inner.resolverInputs() }
    }

    // (The virtual clock of the pairing panel model's typed-index debounce is not ported: the model is UI.)

    // MARK: - Waiting

    /// Waits (letting tasks and the main run loop turn) until `condition` holds or `timeout` passes.
    @MainActor static func waitUntil(_ timeout: TimeInterval = 10, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return false }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return true
    }

    /// Lets pending main-actor tasks run for `seconds` (to prove that nothing more happens).
    @MainActor static func settle(_ seconds: TimeInterval = 0.15) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}
