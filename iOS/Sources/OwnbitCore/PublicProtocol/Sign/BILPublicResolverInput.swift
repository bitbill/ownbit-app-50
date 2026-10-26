//  BILPublicResolverInput.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Public protocol (cold signer) — the wallets offered to the engine's resolver and the identity snapshot the plan is
//  checked against (design §2.1 WP19, §3.17 `fitResolverInput`; R5 §1.4–1.5; port of Android
//  core/publicsigner/.../sign/PublicSignCoordinator.kt:542-608, `fitResolverInput` / `tronCacheCut` / `fits` / `snapshotOf`).
//
//  - `fit`: every eligible wallet (`[{localWalletId[, publicIndex]}]`, home order) when the resolver request fits the
//    bridge (≤ 100 wallets, ≤ 1,000,000 UTF-8 bytes of `{"operation":"resolveSigningPlan","request":…,"wallets":…}`, the
//    byte count measured exactly as the engine builds it); else first the TRON address caches cut to what the request
//    can use; still too large → only the unprepared wallets plus those whose master fingerprint is the request's
//    (`request.masterFingerprint`, lower-cased); still too large (or a request without a top-level fingerprint, e.g. a
//    PSBT) → nil (`err.tooManyWallets`).
//  - `tronCacheCut`: a request that does not read the TRON cache (another chain, or TRON with a key `path`) gets each
//    index with the first 100 addresses (the least the engine accepts); a TRON request naming an `address` (hex `41…`
//    converted to base58) only the wallets whose cache holds it, each cache up to that address (at least 100); nothing
//    else of an index changes (key positions kept); inputs without a cache stay.
//  - `snapshot`: wallet id → lower-cased `publicIndex.walletKeyId` (nil without an authentic index), in input order.
//
//  Pure Foundation; strings compared exactly (code units). Never logs.
//

import Foundation

/// Wallet id → wallet key id of its authentic index (nil without one), in the resolver input's (home) order. Equality is
/// Android's `Map` equality: the same ids with the same key ids, in any order (exact code units).
struct BILPublicWalletSnapshot: Equatable {
    let entries: [(walletId: String, walletKeyId: String?)]

    static let empty = BILPublicWalletSnapshot(entries: [])

    /// Whether `walletId` was offered (with or without an index).
    func contains(_ walletId: String) -> Bool {
        return entries.contains { BILJSONExact.equal($0.walletId, walletId) }
    }

    /// The wallet key id `walletId` was offered with; nil when it was offered without an index or not at all.
    func walletKeyId(_ walletId: String) -> String? {
        return entries.last { BILJSONExact.equal($0.walletId, walletId) }?.walletKeyId
    }

    /// The offered wallets without an authentic index, in order (the setupRequired sheet's wallets).
    var unpreparedWalletIds: [String] {
        return entries.filter { $0.walletKeyId == nil }.map { $0.walletId }
    }

    static func == (a: BILPublicWalletSnapshot, b: BILPublicWalletSnapshot) -> Bool {
        func normalized(_ s: BILPublicWalletSnapshot) -> [(String, String?)] {
            // Kotlin `toMap()`: the last entry of an id wins; then order-insensitive (sorted by UTF-8 bytes).
            var seen: [(String, String?)] = []
            for e in s.entries.reversed() where !seen.contains(where: { BILJSONExact.equal($0.0, e.walletId) }) {
                seen.append((e.walletId, e.walletKeyId))
            }
            return seen.sorted { Array($0.0.utf8).lexicographicallyPrecedes(Array($1.0.utf8)) }
        }
        let x = normalized(a), y = normalized(b)
        guard x.count == y.count else { return false }
        for (p, q) in zip(x, y) {
            guard BILJSONExact.equal(p.0, q.0) else { return false }
            switch (p.1, q.1) {
            case (nil, nil): continue
            case let (k?, l?) where BILJSONExact.equal(k, l): continue
            default: return false
            }
        }
        return true
    }
}

enum BILPublicResolverInput {

    /// The engine's resolver limit (`resolveSigningPlan`: at most 100 wallets; Android `MAX_RESOLVER_WALLETS`).
    static let maxWallets = 100
    /// The bridge's request limit in UTF-8 bytes (= `BILPublicSignerEngine.maxRequestBytes`, Android `MAX_REQUEST_BYTES`).
    static let maxRequestBytes = 1_000_000
    /// The least TRON cache the engine accepts (= `BILPublicIndexRepository.tronCacheMin`).
    static let tronCacheMin = 100

    /// The resolver input within the bridge's limits (see the file comment), or nil (`err.tooManyWallets`).
    /// `byteCount` = the UTF-8 size of the engine's resolver request (live: `BILPublicSignerEngine.resolveRequestByteCount`).
    static func fit(request: BILJSONObject, inputs: [BILJSONObject],
                    byteCount: (BILJSONObject, [BILJSONObject]) -> Int) -> [BILJSONObject]? {
        func fits(_ wallets: [BILJSONObject]) -> Bool {
            return wallets.count <= maxWallets && byteCount(request, wallets) <= maxRequestBytes
        }
        if fits(inputs) { return inputs }
        let cut = tronCacheCut(request: request, inputs: inputs)
        if fits(cut) { return cut }
        guard let fingerprint = request.str("masterFingerprint")?.lowercased() else { return nil }
        let filtered = cut.filter { element in
            guard let index = element.obj("publicIndex") else { return true }
            guard let own = index.str("masterFingerprint")?.lowercased() else { return false }
            return BILJSONExact.equal(own, fingerprint)
        }
        return fits(filtered) ? filtered : nil
    }

    /// `inputs` with each index's TRON address cache (`tronAddressIndex`) cut to what `request` can use (file comment).
    static func tronCacheCut(request: BILJSONObject, inputs: [BILJSONObject]) -> [BILJSONObject] {
        let wanted: String?
        if let chain = request.str("chain"), BILJSONExact.equal(chain, BILPsChain.tron.rawValue), request.str("path") == nil {
            wanted = request.str("address").map { a in
                guard isTronHexAddress(a) else { return a }
                let hex = BILPublicHex.hasASCIIPrefix(a, "0x") ? String(a.dropFirst(2)) : a
                return BILTronAddressCodec.base58(fromHex41: hex.lowercased()) ?? a
            }
        } else {
            wanted = nil
        }
        var out: [BILJSONObject] = []
        out.reserveCapacity(inputs.count)
        for element in inputs {
            guard let index = element.obj("publicIndex"), let cache = index.arr("tronAddressIndex") else {
                out.append(element)
                continue
            }
            let keep: Int
            if let address = wanted {
                guard let at = cache.firstIndex(where: { entry in
                    entry.objectValue?.str("address").map { BILJSONExact.equal($0, address) } ?? false
                }) else { continue }      // the request's address is not in this wallet's cache: not offered
                keep = max(at + 1, tronCacheMin)
            } else {
                keep = tronCacheMin
            }
            if cache.count <= keep {
                out.append(element)
            } else {
                var cutIndex = index
                cutIndex.set("tronAddressIndex", .array(Array(cache.prefix(keep))))
                var cutElement = element
                cutElement.set("publicIndex", .object(cutIndex))
                out.append(cutElement)
            }
        }
        return out
    }

    /// Wallet id → lower-cased wallet key id of the authentic index (nil without one), from the resolver input.
    static func snapshot(of inputs: [BILJSONObject]) -> BILPublicWalletSnapshot {
        return BILPublicWalletSnapshot(entries: inputs.compactMap { element in
            guard let id = element.str("localWalletId") else { return nil }
            return (id, element.obj("publicIndex")?.str("walletKeyId")?.lowercased())
        })
    }

    /// Android `TRON_HEX_ADDRESS` = `^(?:0x)?41[0-9a-fA-F]{40}$` (whole string; only a lower-case `0x` prefix).
    static func isTronHexAddress(_ s: String) -> Bool {
        var u = Array(s.utf8)
        if u.count >= 2, u[0] == 0x30, u[1] == 0x78 { u.removeFirst(2) }
        guard u.count == 42, u[0] == 0x34, u[1] == 0x31 else { return false }
        return u.dropFirst(2).allSatisfy { ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x41 && $0 <= 0x46) || ($0 >= 0x61 && $0 <= 0x66) }
    }
}
