//  BILPublicIndexRepository.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Public protocol (cold signer): the public indexes (spec §4, C-IDX, C-GEN-9; port of Android core/publicsigner
//  index/PublicIndexRepository.kt + PublicIndexBuilderImpl.kt with the iOS decisions D-07…D-11): the engine's
//  `derivePublicIndex` output per eligible wallet (BTC / EVM / TRON account nodes, 100–1000 TRON addresses in Ownbit's
//  scheme, 3 Solana keys, master fingerprint, wallet key id — public keys only), so pairing and request matching need no
//  password.
//
//  Lifecycle (product decision 2026-10-12): COLD wallets are built at create / import while the seed is in memory
//  (`startEagerBuild`, failures swallowed); NORMAL wallets, and COLD wallets whose eager build failed, with one password
//  ("Prepare"). No online condition anywhere.
//
//  Every build: the seed must match the wallet's `seedHash` (sha256; an empty hash fails closed, D-08); the engine
//  builds the index in Ownbit's TRON scheme with exactly `tronAddressCount` addresses; it is cross-checked on every chain
//  (BILPublicIndexVerifier) and stored only if everything agrees; sealed with AES-GCM bound to wallet id + kind into the
//  Keychain with [sha256] of the seed. Package difference (product decision: no md5 hash gates): the app also accepted an
//  md5 `seedHash` of old wallets and stored [sha256, md5]; here only sha256 is computed and accepted (an envelope the app
//  wrote with [sha256, md5] still opens for a wallet whose `seedHash` is the sha256). Every read (`status`, `get`, `load`, `resolverInputs`) unseals, parses and
//  re-checks `seedHash` and the shape; anything off reads as NeedsRepair and is never re-derived without the user's
//  password; a Keychain read error other than "not found" is the transient `.temporarilyUnreadable` (never NeedsRepair,
//  never deleted, never cached). `load` / `resolverInputs` convert an older (standard-scheme or too short) index once to
//  Ownbit's TRON scheme from its own public nodes (spec §4.2a). One global write lock serializes builds, upgrades and seals.
//
//  Threading: main actor (Core Data facts, existing bridges); Keychain I/O, sealing and parsing run off the main thread via
//  BILPublicBackground. Seeds are borrowed (never kept, logged or copied beyond the engine call); index JSON is never
//  logged. Pure: engine contract, wallet directory, key store and verifier are injected (the app's live wiring,
//  BILPublicIndexRepository+Live.swift, is not part of this package).
//

import Foundation
import Security
import CryptoKit

extension Notification.Name {
    /// Posted on the main thread after a wallet's index entry was sealed or deleted; `object` = the wallet id (String).
    public static let publicIndexDidChange = Notification.Name("BILPublicIndexDidChange")
}

@MainActor public protocol BILPublicIndexStoring: AnyObject {
    /// The status of the wallet's index; awaits an in-flight eager build of that wallet (≤ `eagerTimeout` per foreground window).
    func status(walletId: String) async -> BILPublicIndexStatus
    /// The read status and the authentic index in Ownbit's TRON scheme (lazy upgrade); awaits an in-flight eager build.
    func load(walletId: String) async -> (status: BILPublicIndexStatus, index: BILJSONObject?)
    /// "Prepare" after the password dialog accepted the password(s): seed → derive → cross-check → seal → store.
    func prepare(walletId: String, password: String) async -> BILPublicPrepareResult
    /// `[{localWalletId[, publicIndex]}]` for every eligible wallet in home order; `publicIndex` only when authentic;
    /// awaits an in-flight eager build of each wallet (Android builds a COLD index before the creation returns).
    func resolverInputs() async -> [BILJSONObject]
}

@MainActor public final class BILPublicIndexRepository: BILPublicIndexStoring {

    /// Ownbit's TRON address scheme of the engine's Ownbit edition; the cache size bounds (engine `TRON_CACHE…_MAX`);
    /// the bound of an eager build and of a status / load waiting for it (Android `PUBLIC_INDEX_TIMEOUT_MILLIS`).
    /// Nonisolated (readable from any context; an additive relaxation of design §3.8's `static let`).
    public nonisolated static let tronScheme = "ownbit", tronCacheMin = 100, tronCacheMax = 1000, eagerTimeout: TimeInterval = 30

    private let engine: BILPublicSignerEngining
    private let wallets: BILPublicWalletDirectory
    private let keys: BILPublicIndexKeyStore
    private let verifier: BILPublicIndexVerifier
    private let now: () -> Date

    /// Serializes builds, upgrades and seals for every wallet (two "Prepare" taps, a creation racing a prepare).
    private let writes = BILAsyncMutex()

    /// The in-flight eager build per wallet (`token` tells a finished build from a newer one).
    private var inFlight: [String: (token: UInt64, task: Task<Void, Never>)] = [:]
    private var inFlightToken: UInt64 = 0

    /// The bound of an eager build and of a read waiting for it (`eagerTimeout`; harness: shorter).
    public var eagerBuildTimeout: TimeInterval = BILPublicIndexRepository.eagerTimeout

    /// `walletId + ":" + seedHash` of upgrades that failed in this process: not tried again until the app restarts.
    private var upgradeFailed = Set<String>()

    /// Orphan cleanup: delay after `scheduleOrphanCleanup()`; the notification that re-arms a skipped cleanup (live: the
    /// protected-data notification, set by the host); at most one completed cleanup per process.
    public var orphanCleanupDelay: TimeInterval = 5
    public var orphanRetryNotification: Notification.Name?
    private var orphanCleanupState = 0          // 0 idle, 1 scheduled / running / waiting for retry, 2 done
    private var orphanRetryObserver: NSObjectProtocol?

    public init(engine: BILPublicSignerEngining, wallets: BILPublicWalletDirectory, keys: BILPublicIndexKeyStore,
         verifier: BILPublicIndexVerifier, now: @escaping () -> Date = Date.init) {
        self.engine = engine
        self.wallets = wallets
        self.keys = keys
        self.verifier = verifier
        self.now = now
    }

    // MARK: - Shape and scheme rules (Android companion, verbatim)

    /// The master fingerprint (`73C5DA0A`, upper case) of a well-formed public index v1, else nil — Android `fingerprintOf`:
    /// version 1, 32-byte wallet key id, 4-byte fingerprint, 6 BTC nodes, EVM and TRON account nodes, 3 Solana keys; TRON
    /// addresses: exactly 100 without `tronScheme` (round-1 standard index), 100…1000 with `tronScheme == "ownbit"`, any
    /// other `tronScheme` value (incl. JSON null / a number) is not well formed. Strict typed readers (`1.0` / `true` ≠ 1).
    public nonisolated static func fingerprint(of index: BILJSONObject) -> String? {
        let fingerprint = index.str("masterFingerprint")
        let tron = index.arr("tronAddressIndex")?.count ?? -1
        let tronWellFormed: Bool
        if index["tronScheme"] == nil {
            tronWellFormed = tron == tronCacheMin
        } else if let scheme = index.str("tronScheme"), BILJSONExact.equal(scheme, tronScheme) {
            tronWellFormed = tron >= tronCacheMin && tron <= tronCacheMax
        } else {
            tronWellFormed = false
        }
        let wellFormed = index.int("version") == 1
            && BILEngineJSON.isHex(index.str("walletKeyId"), bytes: 32)
            && BILEngineJSON.isHex(fingerprint, bytes: 4)
            && index.arr("bitcoinPublicNodes")?.count == 6
            && index.obj("evmAccountNode") != nil
            && index.obj("tronAccountNode") != nil
            && tronWellFormed
            && index.arr("solanaPublicKeys")?.count == 3
        guard wellFormed, let fp = fingerprint else { return nil }
        return fp.uppercased()
    }

    /// An index that is not in Ownbit's TRON scheme, or whose TRON cache is shorter than `count`.
    public nonisolated static func needsUpgrade(_ index: BILJSONObject, count: Int) -> Bool {
        guard let scheme = index.str("tronScheme"), BILJSONExact.equal(scheme, tronScheme) else { return true }
        return (index.arr("tronAddressIndex")?.count ?? 0) < count
    }

    /// The engine built `index` in Ownbit's TRON scheme with exactly `count` TRON addresses (else malformed).
    public nonisolated static func ensureOwnbitScheme(_ index: BILJSONObject, count: Int) throws {
        guard let scheme = index.str("tronScheme"), BILJSONExact.equal(scheme, tronScheme),
              index.arr("tronAddressIndex")?.count == count else {
            throw BILMalformedEngineResult(what: "publicIndex.tronScheme")
        }
    }

    /// TRON addresses cached: Ownbit's current TRX index + 1, at least 100, at most 1000 (≈ 254 KB).
    public nonisolated static func tronAddressCount(trxIndex: Int) -> Int {
        let wanted = trxIndex >= Int.max - 1 ? Int.max : max(0, trxIndex) + 1
        return min(max(wanted, tronCacheMin), tronCacheMax)
    }

    // MARK: - Reads

    public func status(walletId: String) async -> BILPublicIndexStatus {
        await awaitEagerBuild(walletId)
        // Not-eligible wins over unavailable (Android "Not-eligible wins over unavailable").
        guard wallets.eligibility(walletId: walletId).isEligible else { return .notEligible }
        guard await engine.isAvailable() else { return .unavailable }
        return await read(walletId).status
    }

    public func load(walletId: String) async -> (status: BILPublicIndexStatus, index: BILJSONObject?) {
        await awaitEagerBuild(walletId)
        let r = await read(walletId)
        guard r.index != nil else { return (r.status, nil) }
        return (r.status, await current(walletId, r))
    }

    /// The unsealed, authentic public index of `walletId` (the only index any engine call may receive), or nil. No upgrade.
    /// Awaits an in-flight eager build of that wallet (≤ `eagerBuildTimeout` per foreground window, `awaitEagerBuild`).
    public func get(walletId: String) async -> BILJSONObject? {
        await awaitEagerBuild(walletId)
        return await read(walletId).index
    }

    public func resolverInputs() async -> [BILJSONObject] {
        var inputs: [BILJSONObject] = []
        for id in wallets.eligibleWalletIds() {
            // A request scanned right after a COLD creation must not miss the index being built (Android: built before
            // the creation returns; else the review page would ask for a password COLD wallets never need).
            await awaitEagerBuild(id)
            var entry = BILJSONObject()
            entry.set("localWalletId", .string(id))
            let r = await read(id)
            if r.index != nil, let index = await current(id, r) {
                entry.set("publicIndex", .object(index))
            }
            inputs.append(entry)
        }
        return inputs
    }

    // MARK: - Builds

    public func prepare(walletId: String, password: String) async -> BILPublicPrepareResult {
        guard wallets.eligibility(walletId: walletId).isEligible else { return .notEligible }
        // Engine first: an unusable engine never unlocks the wallet (Android: 0 unlocks).
        guard await engine.isAvailable() else { return .failed(.engineUnavailable, engineCode: nil) }
        guard let seedHex = wallets.seed(walletId: walletId, password: password) else {
            return .failed(.noSecret, engineCode: nil)
        }
        return await prepare(walletId: walletId, seedHex: seedHex)
    }

    /// Builds the index from a seed already in memory (shared by `prepare(password)` and the eager build). The seed is
    /// borrowed: never kept beyond the build.
    public func prepare(walletId: String, seedHex: String) async -> BILPublicPrepareResult {
        return await build(walletId, expectedKind: nil, seedHex: seedHex)
    }

    /// The eager build at COLD create / import (Android `PublicIndexBuilderImpl`, `EAGER_KINDS = {COLD}`): any other kind
    /// returns at once; the build runs in the background, bounded by `eagerBuildTimeout` (= `eagerTimeout`); every failure
    /// is swallowed (logged by code only) — the tab then shows "Prepare". `status` / `load` / `get` / `resolverInputs` of
    /// that wallet wait for it, so page B never shows "Prepare" for a build that is still running (D-09). On expiry, or
    /// when `forget` cancels it, a build still waiting for the write lock never derives, and one past the engine call
    /// never seals. At its end (any result) the warm PAIRING context is released unless a registered pairing panel is
    /// active (`registerPairingPanel`, lead addendum D3).
    /// Lead addendum G1 b: the build runs inside a system background task (`backgroundExecution`; begun here, ended exactly
    /// once — at the build's end, success or failure, or by the system's expiration handler, whichever comes first), so
    /// leaving the app right after a COLD create / import does not freeze it. The bound counts uptime, which goes on while
    /// iOS suspends the app: a bound that runs out while the app was in the background does not cancel the build — it goes
    /// on for a fresh bound, finishes and seals (`boundedEagerBuild`, EAGER_EXTENDED); a bound that runs out in the
    /// foreground gives it up as before (EAGER_TIMEOUT). The 90 s sign-task bound is not changed (the user signs again).
    public func startEagerBuild(walletId: String, kind: BILPublicWalletKind, seedHex: String) {
        guard kind == .cold else { return }
        inFlightToken &+= 1
        let token = inFlightToken
        let bound = eagerBuildTimeout
        let background = BILPublicEagerBackgroundTask(backgroundExecution, name: "BILPublicIndexEagerBuild")
        let task = Task { @MainActor in
            // The background task ends when this task does: after the result, the D3 release and the in-flight bookkeeping
            // below (or earlier, by the system's expiration handler; a second end is a no-op).
            defer { background.end() }
            let result = await self.boundedEagerBuild(walletId, kind: kind, seedHex: seedHex, bound: bound)
            switch result {
            case .ready, .notEligible:
                break
            default:
                BILPublicLog.code("index", "EAGER_NOT_BUILT")
            }
            // Lead addendum D3 (WP21 open issue 9): the build's engine probe / cross-check left a warm PAIRING context, and a
            // COLD import never reaches page B (whose Done / tabs host release it). Release it now unless a pairing panel is
            // using it; fire and forget, so a reader waiting for this build never waits for the engine actor too.
            if !self.isPairingPanelActive {
                let engine = self.engine
                Task {
                    await engine.releasePairingContext()
                }
            }
            if self.inFlight[walletId]?.token == token {
                self.inFlight[walletId] = nil
            }
        }
        inFlight[walletId] = (token, task)
    }

    // MARK: - Pairing panels (lead addendum D3)

    /// A registered pairing panel's owner (weak: the probe goes with it) and its "active" probe.
    private struct PairingPanelProbe {
        weak var owner: AnyObject?
        let isActive: @MainActor () -> Bool
    }
    private var pairingPanelProbes: [PairingPanelProbe] = []

    /// Pages A / B register their "Other wallets" tab here (`owner` = its tabs host, held weakly; `isActive` = the panel is
    /// activated and has not left): the end of an eager COLD build releases the warm PAIRING context only while no
    /// registered panel is active.
    public func registerPairingPanel(owner: AnyObject, isActive: @escaping @MainActor () -> Bool) {
        pairingPanelProbes = pairingPanelProbes.filter { $0.owner != nil }
        pairingPanelProbes.append(PairingPanelProbe(owner: owner, isActive: isActive))
    }

    /// A registered pairing panel whose owner is still alive is active.
    public var isPairingPanelActive: Bool {
        return pairingPanelProbes.contains { $0.owner != nil && $0.isActive() }
    }

    // MARK: - Deletion and orphan cleanup

    /// Deletes the wallet's entry now (main-actor callers: DEBUG, repair paths) and posts `.publicIndexDidChange`.
    public func deleteIndex(walletId: String) {
        forget(walletId: walletId)
        do {
            try keys.deleteEntry(walletId: walletId)
        } catch {
            BILPublicLog.code("index", "DELETE_FAILED")
        }
        NotificationCenter.default.post(name: .publicIndexDidChange, object: walletId)
    }

    /// The nonisolated deletion the host calls when it removes a wallet (the app: `deleteEntry(walletId:)` in +Live), callable from any thread: deletes the entry through
    /// `keys` (thread-safe), then on the main queue posts `.publicIndexDidChange` (object = walletId) and runs `onMain`.
    /// Errors other than not-found are logged by code only; never throws.
    public nonisolated static func deleteEntry(walletId: String, keys: BILPublicIndexKeyStore, onMain: @escaping () -> Void) {
        do {
            try keys.deleteEntry(walletId: walletId)
        } catch {
            BILPublicLog.code("index", "DELETE_FAILED")
        }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .publicIndexDidChange, object: walletId)
            onMain()
        }
    }

    /// Drops what the repository holds for a removed wallet: cancels its in-flight eager build (it checks cancellation
    /// while waiting for the write lock, before the engine call and before sealing, so a rolled-back creation leaves no
    /// entry) and its failed-upgrade marks.
    public func forget(walletId: String) {
        if let entry = inFlight.removeValue(forKey: walletId) {
            entry.task.cancel()
        }
        let prefix = walletId + ":"
        upgradeFailed = upgradeFailed.filter { !$0.hasPrefix(prefix) }
    }

    /// Launch orphan cleanup (spec §4.6; the Keychain survives uninstall): deferred by `orphanCleanupDelay`; deletes every
    /// entry whose wallet id is not in the store. Runs only on a throwing wallet-id fetch that succeeded (the directory also
    /// refuses while a store migration runs or protected data is unavailable — then it re-arms on
    /// `orphanRetryNotification`); never touches the AES key or an entry whose eager build is in flight.
    public func scheduleOrphanCleanup() {
        guard orphanCleanupState == 0 else { return }
        orphanCleanupState = 1
        let delay = orphanCleanupDelay
        Task { @MainActor in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            if self.orphanCleanupState != 2 {            // a pass completed meanwhile
                _ = await self.runOrphanCleanup()
            }
        }
    }

    /// One cleanup pass now; the wallet ids whose entries were deleted, or nil when it was skipped (wallet-id fetch or entry
    /// listing refused; re-armed on `orphanRetryNotification`).
    @discardableResult
    public func runOrphanCleanup() async -> [String]? {
        let walletIds: Set<String>
        do {
            walletIds = try wallets.allWalletIds()
        } catch {
            BILPublicLog.code("index", "ORPHAN_CLEANUP_SKIPPED")
            armOrphanRetry()
            return nil
        }
        let keys = self.keys
        let keep = Set(inFlight.keys)
        let removed: [String]
        do {
            removed = try await BILPublicBackground.run { () -> [String] in
                var gone: [String] = []
                for id in try keys.entryWalletIds() where !walletIds.contains(id) && !keep.contains(id) {
                    do {
                        try keys.deleteEntry(walletId: id)
                        gone.append(id)
                    } catch {
                        continue
                    }
                }
                return gone
            }
        } catch {
            BILPublicLog.code("index", "ORPHAN_CLEANUP_FAILED")      // listing refused (transient): try again later
            armOrphanRetry()
            return nil
        }
        orphanCleanupState = 2
        for id in removed {
            NotificationCenter.default.post(name: .publicIndexDidChange, object: id)
        }
        return removed
    }

    private func armOrphanRetry() {
        guard let name = orphanRetryNotification, orphanRetryObserver == nil else { return }
        orphanRetryObserver = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let observer = self.orphanRetryObserver else { return }
                NotificationCenter.default.removeObserver(observer)
                self.orphanRetryObserver = nil
                if self.orphanCleanupState != 2 {
                    _ = await self.runOrphanCleanup()
                }
            }
        }
    }

    // MARK: - Internals

    /// One read: the status, the authentic index and the envelope's seed hashes (for a re-seal that keeps them).
    private struct Read {
        let status: BILPublicIndexStatus
        var index: BILJSONObject? = nil
        var seedHashes: [String] = []

        static let notEligible = Read(status: .notEligible)
        static let missing = Read(status: .missing)
        static let needsRepair = Read(status: .needsRepair)
        static let unreadable = Read(status: .temporarilyUnreadable)
    }

    /// Android `read()` with the iOS Keychain / envelope rules (spec §4.4, D-08); facts on the main actor, I/O off it.
    private func read(_ walletId: String) async -> Read {
        guard case .eligible(let kind) = wallets.eligibility(walletId: walletId),
              let facts = wallets.facts(walletId: walletId) else {
            return .notEligible
        }
        let keys = self.keys
        let seedHash = facts.seedHash
        return (try? await BILPublicBackground.run {
            BILPublicIndexRepository.readEntry(keys: keys, walletId: walletId, kind: kind, seedHash: seedHash)
        }) ?? .unreadable
    }

    private nonisolated static func readEntry(keys: BILPublicIndexKeyStore, walletId: String, kind: BILPublicWalletKind,
                                              seedHash: String?) -> Read {
        let data: Data?
        do {
            data = try keys.readEntry(walletId: walletId)
        } catch {
            return .unreadable                                   // transient (e.g. -25308 while locked)
        }
        guard let stored = data else { return .missing }
        guard let envelope = BILPublicIndexEnvelope.decode(stored),
              envelope.formatVersion == BILPublicIndexSealer.formatVersion else {
            return .needsRepair
        }
        // A different seed is a different wallet; an empty seedHash never matches (fail closed, D-08). Package difference (no
        // md5 hash gates): only a sha256 seedHash (64 lower-case hex) can match — the app also accepted an old wallet's md5
        // `seedHash` against the md5 entry of the envelopes it wrote.
        guard let expected = seedHash, BILEngineJSON.isLowerHex64(expected),
              envelope.seedHashes.contains(where: { BILJSONExact.equal($0, expected) }) else {
            return .needsRepair
        }
        let key: SymmetricKey?
        do {
            key = try keys.key(create: false)
        } catch let e as BILPublicKeychainError where e.isUnusableKey {
            return .needsRepair                                  // the key is gone for good
        } catch {
            return .unreadable
        }
        guard let k = key, let combined = BILBase64Strict.decode(envelope.sealed),
              var plain = BILPublicIndexSealer.unseal(Data(combined), key: k, walletId: walletId, kind: kind) else {
            return .needsRepair
        }
        var bytes = [UInt8](plain)
        plain.resetBytes(in: 0..<plain.count)
        let parsed = BILStrictJSON.parse(utf8: bytes, options: .engine)?.objectValue
        for i in bytes.indices { bytes[i] = 0 }
        guard let index = parsed, let fingerprint = fingerprint(of: index) else { return .needsRepair }
        return Read(status: .ready(fingerprint: fingerprint), index: index, seedHashes: envelope.seedHashes)
    }

    /// Eligibility (and the expected kind, eager) → engine gate → the write lock → `storeLocked`.
    private func build(_ walletId: String, expectedKind: BILPublicWalletKind?, seedHex: String) async -> BILPublicPrepareResult {
        guard case .eligible(let kind) = wallets.eligibility(walletId: walletId),
              expectedKind == nil || expectedKind == kind else {
            return .notEligible
        }
        // Only a 128-hex seed ever reaches the engine (R2 §1.3).
        guard BILPublicSignerEligibility.isSeedHex(seedHex) else { return .failed(.noSecret, engineCode: nil) }
        guard await engine.isAvailable() else { return .failed(.engineUnavailable, engineCode: nil) }
        do {
            // Cancellable: a build cancelled while it waits (creation rolled back, eager bound expired) never runs.
            return try await writes.withLockCancellable {
                await self.storeLocked(walletId, kind: kind, seedHex: seedHex)
            }
        } catch {
            return .failed(.engine, engineCode: nil)
        }
    }

    /// Seed check → derive → shape → cross-check (all chains) → seal → store. Holds `writes`; maps every failure to a
    /// result (Android `storeLocked`). A mismatch leaves any previous entry untouched.
    private func storeLocked(_ walletId: String, kind: BILPublicWalletKind, seedHex: String) async -> BILPublicPrepareResult {
        // The wallet may have changed while this build waited for the lock.
        guard case .eligible(let k) = wallets.eligibility(walletId: walletId), k == kind,
              let facts = wallets.facts(walletId: walletId) else {
            return .notEligible
        }
        let sha = BILPublicHash.sha256Hex(utf8: seedHex)
        guard let expected = facts.seedHash, BILJSONExact.equal(sha, expected) else {
            BILPublicLog.code("index", "SEED_MISMATCH")
            return .failed(.seedMismatch, engineCode: nil)       // before any engine call
        }
        let count = BILPublicIndexRepository.tronAddressCount(trxIndex: facts.trxIndex)
        do {
            try Task.checkCancellation()                         // never hand the seed to the engine after the caller gave up
            let index = try await engine.derivePublicIndex(seedHex: seedHex, tronScheme: BILPublicIndexRepository.tronScheme,
                                                           tronAddressCount: count)
            guard let fingerprint = BILPublicIndexRepository.fingerprint(of: index) else {
                throw BILMalformedEngineResult(what: "publicIndex")
            }
            try BILPublicIndexRepository.ensureOwnbitScheme(index, count: count)
            // Fresh facts: the cross-check compares with what Ownbit stores now.
            guard case .eligible(let k2) = wallets.eligibility(walletId: walletId), k2 == kind,
                  let current = wallets.facts(walletId: walletId) else {
                return .notEligible
            }
            if case .mismatch(let chain) = try await verifier.verify(index: index, facts: current, chains: Set(BILPsChain.allCases)) {
                return .keysMismatch(chain)
            }
            try Task.checkCancellation()
            try await sealAndStore(walletId, kind: kind, seedHashes: [sha], index: index)
            return .ready(fingerprint: fingerprint)
        } catch let refusal as BILPublicSignerRefusal {
            BILPublicLog.failure("index", refusal)
            return .failed(.engine, engineCode: refusal.code)
        } catch let error where BILPublicIndexRepository.isEngineClass(error) {
            BILPublicLog.failure("index", error)
            return .failed(.engine, engineCode: nil)
        } catch {
            BILPublicLog.failure("index", error)
            return .failed(.storage, engineCode: nil)
        }
    }

    /// Engine / bridge / malformed-result failures (Android ENGINE); cancellation stores nothing and reads as engine too.
    private nonisolated static func isEngineClass(_ error: Error) -> Bool {
        return error is BILPublicSignerFailure || error is BILMalformedEngineResult || error is BILOwnbitAddressDeriveError
            || error is BILPublicTimeout.Expired || error is CancellationError
    }

    /// Seals `index` for the wallet and writes the envelope (an existing entry is replaced); posts `.publicIndexDidChange`.
    private func sealAndStore(_ walletId: String, kind: BILPublicWalletKind, seedHashes: [String], index: BILJSONObject) async throws {
        let keys = self.keys
        let createdAtMs = Int64((now().timeIntervalSince1970 * 1000).rounded(.down))
        let text = BILStrictJSON.serialize(index)
        try await BILPublicBackground.run {
            var plain = Data(text.utf8)
            defer { plain.resetBytes(in: 0..<plain.count) }
            var key: SymmetricKey
            do {
                guard let existing = try keys.key(create: true) else { throw BILPublicKeychainError(status: errSecItemNotFound) }
                key = existing
            } catch let e as BILPublicKeychainError where e.isUnusableKey {
                key = try keys.replaceKey()                      // Android replaceUnusableKey
            }
            let sealed = try BILPublicIndexSealer.seal(plain, key: key, walletId: walletId, kind: kind)
            let envelope = BILPublicIndexEnvelope(formatVersion: BILPublicIndexSealer.formatVersion, seedHashes: seedHashes,
                                                  createdAtMs: createdAtMs, sealed: BILBase64Strict.encode([UInt8](sealed)))
            try keys.writeEntry(walletId: walletId, data: envelope.encoded())
        }
        NotificationCenter.default.post(name: .publicIndexDidChange, object: walletId)
    }

    /// Android `current()`: the index in Ownbit's TRON scheme with a cache long enough for Ownbit's current TRX index. An
    /// older index is converted once from its own public nodes (`refreshPublicIndex`, no password) under the write lock,
    /// must keep its identity, is cross-checked on every chain and sealed again with the same seed hashes; any failure keeps
    /// the stored index (its TRON #0 still matches) and is not retried in this process.
    private func current(_ walletId: String, _ r: Read) async -> BILJSONObject? {
        guard let index = r.index else { return nil }
        guard let facts = wallets.facts(walletId: walletId) else { return index }
        let count = BILPublicIndexRepository.tronAddressCount(trxIndex: facts.trxIndex)
        if !BILPublicIndexRepository.needsUpgrade(index, count: count) { return index }
        let attempt = walletId + ":" + (facts.seedHash ?? "")
        if upgradeFailed.contains(attempt) { return index }
        return await writes.withLock { () -> BILJSONObject in
            // Another caller may have upgraded it meanwhile.
            let fresh = await self.read(walletId)
            guard let freshIndex = fresh.index else { return index }
            if !BILPublicIndexRepository.needsUpgrade(freshIndex, count: count) { return freshIndex }
            guard case .eligible(let kind) = self.wallets.eligibility(walletId: walletId),
                  let currentFacts = self.wallets.facts(walletId: walletId) else {
                return freshIndex
            }
            do {
                let upgraded = try await self.engine.refreshPublicIndex(publicIndex: freshIndex,
                                                                        tronScheme: BILPublicIndexRepository.tronScheme,
                                                                        tronAddressCount: count)
                try BILPublicIndexRepository.ensureOwnbitScheme(upgraded, count: count)
                let sameKeyId: Bool
                if let a = upgraded.str("walletKeyId"), let b = freshIndex.str("walletKeyId") {
                    sameKeyId = BILJSONExact.equal(a, b)
                } else {
                    sameKeyId = false
                }
                guard sameKeyId, BILPublicIndexRepository.fingerprint(of: upgraded) == BILPublicIndexRepository.fingerprint(of: freshIndex) else {
                    throw BILMalformedEngineResult(what: "publicIndex.identity")      // a lying engine
                }
                guard case .ok = try await self.verifier.verify(index: upgraded, facts: currentFacts, chains: Set(BILPsChain.allCases)) else {
                    throw BILMalformedEngineResult(what: "publicIndex.tron")
                }
                try Task.checkCancellation()
                try await self.sealAndStore(walletId, kind: kind, seedHashes: fresh.seedHashes, index: upgraded)
                return upgraded
            } catch is CancellationError {
                return freshIndex
            } catch {
                BILPublicLog.code("index", "UPGRADE_FAILED")
                self.upgradeFailed.insert(attempt)
                return freshIndex
            }
        }
    }

    // MARK: - Eager build in the background (lead addendum G1 b)

    /// System background time and the app's background state for the eager COLD build (the host's UIKit adapter; nil =
    /// no background task and never "in the background", the bound then behaves as before G1).
    public var backgroundExecution: BILPublicBackgroundExecution?

    /// The eager build under its bound. The build runs in its own task; each window of `bound` seconds races it. A window
    /// that runs out in the foreground gives the build up (EAGER_TIMEOUT: cancelled — still waiting for the write lock it
    /// never derives, past the engine call it never seals). A window that ran out while the app was in the background (it
    /// started there, the app is there now, or the app entered the background meanwhile: iOS suspends the app, the JS work
    /// is frozen while the uptime-based deadline goes on) lets the build go on for a fresh window instead (EAGER_EXTENDED),
    /// so it finishes and seals. Cancelling the caller (`forget`) cancels the build at once (the cancellation handler: a
    /// build inside the write lock must not reach the engine call after a removal).
    private func boundedEagerBuild(_ walletId: String, kind: BILPublicWalletKind, seedHex: String,
                                   bound: TimeInterval) async -> BILPublicPrepareResult {
        if Task.isCancelled { return .failed(.engine, engineCode: nil) }       // removed before it started: never starts
        let work = Task { @MainActor () -> BILPublicPrepareResult in
            return await self.build(walletId, expectedKind: kind, seedHex: seedHex)
        }
        let execution = backgroundExecution
        var entries = execution?.backgroundEntries ?? 0
        var startedInBackground = execution?.isInBackground ?? false
        return await withTaskCancellationHandler(operation: { () async -> BILPublicPrepareResult in
            while true {
                do {
                    return try await BILPublicTimeout.run(seconds: bound) {
                        return await work.value
                    }
                } catch is BILPublicTimeout.Expired {
                    let nowEntries = execution?.backgroundEntries ?? 0
                    let nowInBackground = execution?.isInBackground ?? false
                    if startedInBackground || nowInBackground || nowEntries != entries {
                        BILPublicLog.code("index", "EAGER_EXTENDED")
                        entries = nowEntries
                        startedInBackground = nowInBackground
                        continue
                    }
                    work.cancel()
                    BILPublicLog.code("index", "EAGER_TIMEOUT")
                    return .failed(.engine, engineCode: nil)
                } catch {
                    work.cancel()                                // the caller was cancelled (forget)
                    return .failed(.engine, engineCode: nil)
                }
            }
        }, onCancel: {
            work.cancel()
        })
    }

    /// Waits for an in-flight eager build of `walletId`, bounded like the build itself (lead addendum G1 b): each window of
    /// `eagerBuildTimeout` races the build; a window that ran out while the app was in the background (the wait started
    /// there, the app is there now, or the app entered the background meanwhile) waits a fresh window — the build is
    /// extended in the same case, so a reader waiting across a suspension gets the sealed index, not Missing. A window that
    /// ran out in the foreground stops waiting, as before; a cancelled reader stops at once.
    private func awaitEagerBuild(_ walletId: String) async {
        guard let entry = inFlight[walletId] else { return }
        let task = entry.task
        let execution = backgroundExecution
        var entries = execution?.backgroundEntries ?? 0
        var inBackground = execution?.isInBackground ?? false
        while true {
            do {
                _ = try await BILPublicTimeout.run(seconds: eagerBuildTimeout) {
                    await task.value
                }
                return
            } catch is BILPublicTimeout.Expired {
                let nowEntries = execution?.backgroundEntries ?? 0
                let nowInBackground = execution?.isInBackground ?? false
                guard inBackground || nowInBackground || nowEntries != entries else { return }
                entries = nowEntries
                inBackground = nowInBackground
            } catch {
                return                                           // the reader was cancelled
            }
        }
    }
}

// MARK: - Background execution of the eager build (lead addendum G1 b)

/// System background time and the app's background state, as the eager COLD build needs them. Main actor. Live:
/// the host's UIKit adapter (the app's `BILPublicLiveBackgroundExecution`); tests inject a fake.
@MainActor public protocol BILPublicBackgroundExecution: AnyObject {
    /// Starts a system background task (`beginBackgroundTask(withName:expirationHandler:)`); `expired` runs on main when the
    /// system ends the time first. nil when the system gives none.
    func beginTask(name: String, expired: @escaping @MainActor () -> Void) -> Int?
    /// Ends a task `beginTask` returned (`endBackgroundTask`).
    func endTask(_ id: Int)
    /// How many times the app has entered the background so far (never decreases).
    var backgroundEntries: Int { get }
    /// The app is in the background now.
    var isInBackground: Bool { get }
}

/// One eager build's system background task, ended exactly once: when the build ends (any result), or when the system's
/// expiration handler runs first (the build then goes on, suspended with the app if iOS suspends it).
@MainActor final class BILPublicEagerBackgroundTask {
    private let execution: BILPublicBackgroundExecution?
    private var id: Int?

    init(_ execution: BILPublicBackgroundExecution?, name: String) {
        self.execution = execution
        id = execution?.beginTask(name: name) { [weak self] in
            self?.end()
        }
    }

    /// Ends the task (a second call, or a call after the system's expiry, does nothing).
    func end() {
        guard let taskId = id else { return }
        id = nil
        execution?.endTask(taskId)
    }
}
