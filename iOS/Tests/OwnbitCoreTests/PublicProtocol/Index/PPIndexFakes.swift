//  PPIndexFakes.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Port of the app harness suite `scripts/public-protocol/tests/index` (Fakes.swift) to XCTest.
//
//  Fakes.swift — suite "index" (WP11): the golden-vector engine, Ownbit's bridges, the wallet directory and an in-memory
//  Keychain, as Android's PST:testing/{PublicIndexFakes,IndexTestEnv,EngineVectors}.kt build them (design WP11 tests).
//  Test code only (never compiled into the app).
//

import Foundation
import XCTest
import CryptoKit
import Security
@testable import OwnbitCore

extension PPIndexSuite {

    /// Stands for the md5 entry of an envelope the app wrote (`[sha256, md5]`); 32 hex digits like an md5. The package has
    /// no md5 hash gate, so its value never matters.
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
        static let SOL = "HAgk14JpMQLgt6rVgv7cBQFJWFto5Dqxi472uT3DKpqk"
        static let SOL_TRUST = "GjJyeC1r2RgkuoCWMyPYkCWSGSGLcz266EaAkLA27AhL"

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
                exit(2)
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
            exit(2)
        }

        func publicIndex(_ id: String) -> BILJSONObject {
            guard let o = fixtures.obj("publicIndex." + id) else {
                print("FAIL no fixture publicIndex.\(id)")
                exit(2)
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

        func caseResult(_ id: String) -> BILJSONObject? {
            guard let c = cases.first(where: { $0.str("id") == id }), let s = c.arr("steps")?.first?.objectValue,
                  let resp = s.obj("response") else { return nil }
            return resp.bool("ok") == true ? resp.obj("result") : nil
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

        private func fixtureId(_ index: BILJSONObject, _ chain: String) -> String? {
            guard let id = ["abandon", "legal"].first(where: { sameNodes(publicIndex($0), index) }) else { return nil }
            let ownbit = index.str("tronScheme") == "ownbit"
            return ownbit && chain == "tron" && id == "abandon" ? "abandonOwnbit" : id
        }

        private func normalized(_ chain: String, _ profile: String?) -> String {
            return profile ?? (chain == "bitcoin" ? "native" : "standard")
        }

        func derivePublicAddresses(_ index: BILJSONObject, _ chain: String, _ profile: String?, _ start: Int, _ count: Int) -> BILJSONObject? {
            guard let fixture = fixtureId(index, chain) else { return nil }
            for step in steps("derivePublicAddresses") {
                let r = step.request
                let pageStart = r.int("start") ?? 0
                let pageCount = r.int("count") ?? 20
                guard r.obj("publicIndex")?.str("$fixture") == "publicIndex." + fixture, r.str("chain") == chain,
                      normalized(chain, r.str("profile")) == normalized(chain, profile),
                      start >= pageStart, start + count <= pageStart + pageCount, let result = step.result,
                      let all = result.arr("addresses") else { continue }
                let slice = Array(all.dropFirst(start - pageStart).prefix(count))
                return BILJSONObject([("addresses", .array(slice)), ("hasMore", .bool(chain != "solana")), ("nextIndex", .int(start + count))])
            }
            return nil
        }
    }

    // MARK: - Engine (Android VectorEngine)

    struct EngineCall: Equatable {
        let op: String
        var chain: String? = nil
        var profile: String? = nil
        var index: Int? = nil
        var tronScheme: String? = nil
        var count: Int? = nil
    }

    class FakeEngine: BILPublicSignerEngining {
        let vectors: Vectors
        private let lock = NSLock()
        private var _calls: [EngineCall] = []
        private var _refuse: [String: String] = [:]
        private var _available = true
        private var _addressOverride: [String: String] = [:]
        private var _deriveDelay: TimeInterval = 0
        private var _active = 0
        private var _maxActive = 0
        private var _refreshLie: ((BILJSONObject) -> BILJSONObject)?
        private var _deriveOverride: BILJSONObject?
        private var _indexesSeen: [BILJSONObject] = []

        init(_ vectors: Vectors) { self.vectors = vectors }

        private func locked<T>(_ body: () -> T) -> T { lock.lock(); defer { lock.unlock() }; return body() }

        var calls: [EngineCall] { return locked { _calls } }
        func count(_ op: String) -> Int { return calls.filter { $0.op == op }.count }
        var available: Bool { get { return locked { _available } } set { locked { _available = newValue } } }
        func refuse(_ op: String, _ code: String?) { locked { _refuse[op] = code } }
        func override(chain: String, profile: String?, start: Int, address: String?) {
            locked { _addressOverride[chain + "|" + (profile ?? "-") + "|" + String(start)] = address }
        }
        var deriveDelay: TimeInterval { get { return locked { _deriveDelay } } set { locked { _deriveDelay = newValue } } }
        var maxConcurrentDerive: Int { return locked { _maxActive } }
        var refreshLie: ((BILJSONObject) -> BILJSONObject)? { get { return locked { _refreshLie } } set { locked { _refreshLie = newValue } } }
        /// A lying engine: `derivePublicIndex` answers this index whatever scheme / count was asked.
        var deriveOverride: BILJSONObject? { get { return locked { _deriveOverride } } set { locked { _deriveOverride = newValue } } }
        var indexesSeen: [BILJSONObject] { return locked { _indexesSeen } }
        func reset() { locked { _calls.removeAll(); _indexesSeen.removeAll(); _maxActive = 0 } }

        private func record(_ c: EngineCall) -> String? {
            return locked { _calls.append(c); return _refuse[c.op] }
        }

        func capabilities() async throws -> BILJSONObject { throw BILPublicSignerFailure.invalidRequest }

        func derivePublicAddresses(publicIndex: BILJSONObject, chain: String, profile: String?, start: Int, count: Int) async throws -> BILJSONObject {
            if let code = record(EngineCall(op: "derivePublicAddresses", chain: chain, profile: profile, index: start)) {
                throw BILPublicSignerRefusal(code: code, engineMessage: "refused")
            }
            locked { _indexesSeen.append(publicIndex) }
            guard let result = vectors.derivePublicAddresses(publicIndex, chain, profile, start, count) else {
                throw BILPublicSignerRefusal(code: "INDEX", engineMessage: "no vector page")
            }
            let key = chain + "|" + (profile ?? "-") + "|" + String(start)
            guard let o = locked({ _addressOverride[key] }), var first = result.arr("addresses")?.first?.objectValue else { return result }
            first.set("address", .string(o))
            var patched = result
            patched.set("addresses", .array([.object(first)]))
            return patched
        }

        func createPublicPairing(publicIndex: BILJSONObject, chain: String, profile: String?, outputMode: String?, index: Int) async throws -> BILJSONObject {
            throw BILPublicSignerFailure.invalidRequest
        }

        /// `releasePairingContext()` calls (lead addendum D3, WP26: the end of an eager COLD build releases the warm context).
        private var _releases = 0
        private var _releaseDelay: TimeInterval = 0
        var releases: Int { return locked { _releases } }
        /// A busy engine actor: the release lands only after this delay.
        var releaseDelay: TimeInterval { get { return locked { _releaseDelay } } set { locked { _releaseDelay = newValue } } }

        func releasePairingContext() async {
            let delay = releaseDelay
            if delay > 0 {
                await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                    DispatchQueue.global().asyncAfter(deadline: .now() + delay) { c.resume() }
                }
            }
            locked { _releases += 1 }
        }

        func derivePublicIndex(seedHex: String, tronScheme: String?, tronAddressCount: Int?) async throws -> BILJSONObject {
            if let code = record(EngineCall(op: "derivePublicIndex", tronScheme: tronScheme, count: tronAddressCount)) {
                throw BILPublicSignerRefusal(code: code, engineMessage: "refused")
            }
            let delay = deriveDelay
            locked { _active += 1; _maxActive = max(_maxActive, _active) }
            defer { locked { _active -= 1 } }
            if delay > 0 {
                // Not cancellable, like the real engine's synchronous JavaScriptCore call: a cancelled build still gets its
                // answer, so only the repository's own cancellation checks can keep it from sealing.
                await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                    DispatchQueue.global().asyncAfter(deadline: .now() + delay) { c.resume() }
                }
            }
            if let lie = deriveOverride { return lie }
            guard let index = vectors.derivePublicIndex(seedHex, tronScheme, tronAddressCount) else {
                throw BILPublicSignerRefusal(code: "SEED", engineMessage: "no vector for this seed")
            }
            return index
        }

        func refreshPublicIndex(publicIndex: BILJSONObject, tronScheme: String, tronAddressCount: Int?) async throws -> BILJSONObject {
            if let code = record(EngineCall(op: "refreshPublicIndex", tronScheme: tronScheme, count: tronAddressCount)) {
                throw BILPublicSignerRefusal(code: code, engineMessage: "refused")
            }
            guard let index = vectors.refreshPublicIndex(publicIndex, tronScheme, tronAddressCount) else {
                throw BILPublicSignerRefusal(code: "PUBLIC_INDEX", engineMessage: "no vector for this index")
            }
            return refreshLie?(index) ?? index
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
            _ = record(EngineCall(op: "isAvailable"))
            return available
        }
    }

    // MARK: - Ownbit bridges (Android OwnbitBridges)

    @MainActor final class FakeDeriver: BILOwnbitAddressDeriving {
        var bitcoinCalls: [String] = []      // "<type>|<xpub>"
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

    // MARK: - Wallet directory (Android insertOwnbitWallet + walletDao)

    struct FakeWallet {
        var traits: BILPublicSignerEligibility.Traits
        var facts: BILPublicWalletFacts
        var password: String
        var seed: String?
    }

    @MainActor final class FakeDirectory: BILPublicWalletDirectory {
        var wallets: [String: FakeWallet] = [:]
        var order: [String] = []
        var allIdsError: Error?
        /// Wallets left out of `allWalletIds()` (a row not visible to the store fetch yet, e.g. a creation in progress).
        var unlistedIds = Set<String>()
        var seedCalls = 0
        /// `facts(walletId:)` reads per wallet, and a hook run on each read (to cancel a build at that exact point).
        var factsReads: [String: Int] = [:]
        var onFactsRead: ((String) -> Void)?

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
            factsReads[walletId, default: 0] += 1
            onFactsRead?(walletId)
            return wallets[walletId]?.facts
        }
        func seed(walletId: String, password: String) -> String? {
            seedCalls += 1
            guard let w = wallets[walletId], w.password == password else { return nil }
            return w.seed
        }
        func allWalletIds() throws -> Set<String> {
            if let e = allIdsError { throw e }
            return Set(wallets.keys).subtracting(unlistedIds)
        }
    }

    // MARK: - In-memory Keychain

    final class MemoryKeyStore: BILPublicIndexKeyStore, @unchecked Sendable {
        private let lock = NSLock()
        private var entries: [String: Data] = [:]
        private var keyData: Data?
        private var _readError: OSStatus?
        private var _keyReadError: OSStatus?
        private var _writeError: OSStatus?
        private var _listError: OSStatus?
        private(set) var keyCreates = 0
        private(set) var keyReplacements = 0

        private func locked<T>(_ body: () throws -> T) rethrows -> T { lock.lock(); defer { lock.unlock() }; return try body() }

        var readError: OSStatus? { get { return locked { _readError } } set { locked { _readError = newValue } } }
        var keyReadError: OSStatus? { get { return locked { _keyReadError } } set { locked { _keyReadError = newValue } } }
        var writeError: OSStatus? { get { return locked { _writeError } } set { locked { _writeError = newValue } } }
        var listError: OSStatus? { get { return locked { _listError } } set { locked { _listError = newValue } } }

        func raw(_ id: String) -> Data? { return locked { entries[id] } }
        func setRaw(_ id: String, _ data: Data?) { locked { entries[id] = data } }
        var ids: [String] { return locked { entries.keys.sorted() } }
        var rawKey: Data? { get { return locked { keyData } } set { locked { keyData = newValue } } }
        func loseKey() { locked { keyData = nil } }

        func readEntry(walletId: String) throws -> Data? {
            return try locked {
                if let s = _readError { throw BILPublicKeychainError(status: s) }
                return entries[walletId]
            }
        }
        func writeEntry(walletId: String, data: Data) throws {
            try locked {
                if let s = _writeError { throw BILPublicKeychainError(status: s) }
                entries[walletId] = data
            }
        }
        func deleteEntry(walletId: String) throws {
            locked { entries[walletId] = nil }
        }
        func entryWalletIds() throws -> [String] {
            return try locked {
                if let s = _listError { throw BILPublicKeychainError(status: s) }
                return Array(entries.keys)
            }
        }
        func key(create: Bool) throws -> SymmetricKey? {
            return try locked {
                if let s = _keyReadError { throw BILPublicKeychainError(status: s) }
                if let d = keyData {
                    guard d.count == 32 else { throw BILPublicKeychainError.unusableKey }
                    return SymmetricKey(data: d)
                }
                guard create else { return nil }
                let d = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
                keyData = d
                keyCreates += 1
                return SymmetricKey(data: d)
            }
        }
        func replaceKey() throws -> SymmetricKey {
            return locked {
                let d = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
                keyData = d
                keyReplacements += 1
                return SymmetricKey(data: d)
            }
        }
    }

    // MARK: - Environment (Android IndexTestEnv)

    /// Nonisolated test constants and trait builders.
    enum Fx {
        static let NOW: TimeInterval = 1_760_000_000          // seconds → createdAt 1760000000000 ms
        static let PASSWORD = "Passw0rd!x"

        static func traits(cold: Bool = true, multisig: Bool = false, watch: Bool = false, privateKey: Bool = false,
                           merchant: Bool = false, customPath: Bool = false, electrum: Bool = false, seed: Bool = true,
                           exists: Bool = true) -> BILPublicSignerEligibility.Traits {
            return BILPublicSignerEligibility.Traits(exists: exists, isMultisig: multisig, isObserver: watch, hasSeed: seed,
                                                     isPrivateKey: privateKey, isMerchant: merchant, hasCustomPathMarker: customPath,
                                                     isElectrum: electrum, isCold: cold)
        }
    }

    /// A value shared with closures that run on other threads (notification observers, dispatch queues).
    final class Box<T>: @unchecked Sendable {
        private let lock = NSLock()
        private var _value: T
        init(_ value: T) { _value = value }
        var value: T {
            get { lock.lock(); defer { lock.unlock() }; return _value }
            set { lock.lock(); _value = newValue; lock.unlock() }
        }
        func update(_ body: (inout T) -> Void) { lock.lock(); body(&_value); lock.unlock() }
    }

    @MainActor final class Env {
        static let PASSWORD = Fx.PASSWORD

        let vectors: Vectors
        let engine: FakeEngine
        let deriver = FakeDeriver()
        let directory = FakeDirectory()
        let keys = MemoryKeyStore()
        let verifier: BILPublicIndexVerifier
        let repository: BILPublicIndexRepository

        init(_ vectors: Vectors) {
            self.vectors = vectors
            engine = FakeEngine(vectors)
            verifier = BILPublicIndexVerifier(engine: engine, deriver: deriver)
            repository = BILPublicIndexRepository(engine: engine, wallets: directory, keys: keys, verifier: verifier,
                                                  now: { Date(timeIntervalSince1970: Fx.NOW) })
            repository.orphanCleanupDelay = 0
        }

        var abandonSeed: String { return vectors.seedHex("abandon") }
        var legalSeed: String { return vectors.seedHex("legal") }

        static func traits(cold: Bool = true, multisig: Bool = false, watch: Bool = false, privateKey: Bool = false,
                           merchant: Bool = false, customPath: Bool = false, electrum: Bool = false, seed: Bool = true,
                           exists: Bool = true) -> BILPublicSignerEligibility.Traits {
            return Fx.traits(cold: cold, multisig: multisig, watch: watch, privateKey: privateKey, merchant: merchant,
                             customPath: customPath, electrum: electrum, seed: seed, exists: exists)
        }

        /// The abandon wallet as `insertOwnbitWallet` stores it (iOS field names).
        func abandonFacts(_ id: String, cold: Bool = true, legal: Bool = false, ethIndex: Int = 0, trxIndex: Int = 0,
                          withSol: Bool = true, withTaproot: Bool = false, seedHash: String? = nil, trxAddress0: String? = OV.TRX_0) -> BILPublicWalletFacts {
            let ethAddress = (legal ? OV.ETH_0_LEGAL : (ethIndex == 7 ? OV.ETH_7 : OV.ETH_0)).lowercased()
            return BILPublicWalletFacts(walletId: id, kind: cold ? .cold : .normal,
                                        seedHash: seedHash ?? BILPublicHash.sha256Hex(utf8: abandonSeed),
                                        legacyXpub: legal ? OV.XPUB_LEGACY_LEGAL : OV.XPUB_LEGACY,
                                        nestedXpub: OV.YPUB_NESTED, nativeXpub: OV.ZPUB_NATIVE,
                                        taprootXpub: withTaproot ? OV.XPUB_TAPROOT : nil,
                                        ethXpub: legal ? OV.XPUB_ETH_LEGAL : OV.XPUB_ETH, ethAddress: ethAddress, ethIndex: ethIndex,
                                        trxAddress: trxIndex == 0 ? OV.TRX_0 : OV.TRX_OWNBIT_1, trxAddress0: trxAddress0, trxIndex: trxIndex,
                                        solAddress: withSol ? OV.SOL : nil,
                                        btcProfilesInUse: [.legacy, .native])
        }

        func addWallet(_ id: String, cold: Bool = true, seed: String? = nil, password: String = Fx.PASSWORD,
                       traits: BILPublicSignerEligibility.Traits? = nil, facts: BILPublicWalletFacts? = nil) {
            directory.put(id, FakeWallet(traits: traits ?? Env.traits(cold: cold), facts: facts ?? abandonFacts(id, cold: cold),
                                         password: password, seed: seed ?? abandonSeed))
        }

        func setFacts(_ id: String, _ change: (inout FakeWallet) -> Void) {
            guard var w = directory.wallets[id] else { return }
            change(&w)
            directory.wallets[id] = w
        }

        func envelope(_ id: String) -> BILPublicIndexEnvelope? {
            return keys.raw(id).flatMap { BILPublicIndexEnvelope.decode($0) }
        }
    }

    /// Facts with one field changed (BILPublicWalletFacts is immutable).
    static func with(_ f: BILPublicWalletFacts, walletId: String? = nil, kind: BILPublicWalletKind? = nil, seedHash: String?? = nil,
              legacyXpub: String?? = nil, nestedXpub: String?? = nil, nativeXpub: String?? = nil, taprootXpub: String?? = nil,
              ethXpub: String?? = nil, ethAddress: String?? = nil, ethIndex: Int? = nil, trxAddress: String?? = nil,
              trxAddress0: String?? = nil, trxIndex: Int? = nil, solAddress: String?? = nil) -> BILPublicWalletFacts {
        return BILPublicWalletFacts(walletId: walletId ?? f.walletId, kind: kind ?? f.kind, seedHash: seedHash ?? f.seedHash,
                                    legacyXpub: legacyXpub ?? f.legacyXpub, nestedXpub: nestedXpub ?? f.nestedXpub,
                                    nativeXpub: nativeXpub ?? f.nativeXpub, taprootXpub: taprootXpub ?? f.taprootXpub,
                                    ethXpub: ethXpub ?? f.ethXpub, ethAddress: ethAddress ?? f.ethAddress, ethIndex: ethIndex ?? f.ethIndex,
                                    trxAddress: trxAddress ?? f.trxAddress, trxAddress0: trxAddress0 ?? f.trxAddress0,
                                    trxIndex: trxIndex ?? f.trxIndex, solAddress: solAddress ?? f.solAddress,
                                    btcProfilesInUse: f.btcProfilesInUse)
    }

    /// Waits (turning the main run loop) until `condition` holds or `timeout` passes.
    @MainActor static func waitUntil(_ timeout: TimeInterval = 5, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return false }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return true
    }
}
