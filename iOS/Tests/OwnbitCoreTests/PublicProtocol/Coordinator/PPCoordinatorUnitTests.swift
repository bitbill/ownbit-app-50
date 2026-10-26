//  PPCoordinatorUnitTests.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Port of the app harness suite `scripts/public-protocol/tests/coordinator` (UnitTests.swift) to XCTest.
//
//  UnitTests.swift — suite "coordinator" (WP19): the pure helpers of the coordinator — recent hashes (Android
//  RecentRequestHashes), the request store and its observers (PublicRequestStore + the observe contract of §3.5), the
//  wallet snapshot, the resolver input fitting (PublicSignCoordinatorTest "too many wallets" ×2, R5 §1.5), the TronLink
//  answer (OtherWalletAnswersTest through the coordinator's builder) and the session value.
//

import Foundation
import XCTest
@testable import OwnbitCore

extension PPCoordinatorSuite {

    @MainActor static func unitTests() async {
        recentHashTests()
        storeTests()
        observerTests()
        snapshotTests()
        resolverInputTests()
        tronLinkAnswerTests()
        sessionTests()
    }

    // MARK: - Recent hashes (C-RESP-4)

    @MainActor private static func recentHashTests() {
        section("recent hashes")
        let r = BILRecentRequestHashes()
        let t0 = Date(timeIntervalSince1970: 1_000)
        t(r.signedAt("aa") == nil, "nothing answered yet")
        r.record("ABCD", at: t0)
        eq(r.signedAt("abcd"), t0, "keys are lower-cased")
        eq(r.signedAt("AbCd"), t0, "lookups are lower-cased")
        for i in 0..<16 { r.record("h\(i)", at: t0.addingTimeInterval(Double(i))) }
        eq(r.count, BILRecentRequestHashes.capacity, "at most 16 hashes")
        t(r.signedAt("abcd") == nil, "the least recently answered is dropped")
        r.record("h0", at: t0.addingTimeInterval(100))
        r.record("new", at: t0)
        t(r.signedAt("h0") != nil, "re-recording moves a hash to the newest place")
        t(r.signedAt("h1") == nil, "… so the next oldest goes")
        eq(r.signedAt("h0"), t0.addingTimeInterval(100), "the latest time is kept")
        eq(r.count, 16, "still 16")
        // Re-recording a hash never takes two places: three more answers of the newest hash evict nothing.
        let q = BILRecentRequestHashes()
        for i in 0..<16 { q.record("q\(i)", at: t0) }
        for _ in 0..<3 { q.record("q15", at: t0) }
        eq(q.count, 16, "a re-recorded hash keeps one place")
        t(q.signedAt("q0") != nil, "… so the oldest stays")
    }

    // MARK: - Store

    @MainActor private static func storeTests() {
        section("request store")
        let store = BILPublicRequestStore()
        let request = BILJSONObject([("chain", .string("evm"))])
        var entries: [BILPublicRequestEntry] = []
        for _ in 0..<(BILPublicRequestStore.capacity + 1) {
            let e = BILPublicRequestEntry(id: BILPublicRequestStore.newId(), request: request, info: BILPublicRequestInfo.of(request))
            store.put(e)
            entries.append(e)
        }
        eq(store.count, 8, "capacity 8")
        t(store.get(entries[0].id) == nil, "the oldest entry is dropped")
        t(entries[0].discarded, "… and retired")
        if case .gone = entries[0].state {} else { t(false, "an evicted entry is gone") }
        t(entries[0].session == nil, "an evicted entry has no session")
        t(store.get(entries[8].id) === entries[8], "the newest is kept")
        let removed = store.remove(entries[3].id)
        t(removed === entries[3] && entries[3].discarded, "remove retires the entry")
        t(store.remove(entries[3].id) == nil, "removing twice is a no-op")
        eq(store.count, 7, "7 left")
        let id = BILPublicRequestStore.newId()
        t(id.count == 36 && id == id.lowercased() && UUID(uuidString: id) != nil, "ids are random lower-case UUIDs")
        t(BILPublicRequestStore.newId() != id, "ids are random")
        t(store.get(id.uppercased()) == nil && store.get(entries[8].id.uppercased()) == nil, "ids are compared exactly")
        eq(String(describing: entries[8]), "BILPublicRequestEntry", "an entry prints no content")
    }

    @MainActor private static func observerTests() {
        section("observers")
        let request = BILJSONObject([("chain", .string("evm"))])
        let info = BILPublicRequestInfo.of(request)
        let e = BILPublicRequestEntry(id: "r1", request: request, info: info)
        var a: [String] = []
        var b: [String] = []
        func name(_ s: BILPublicSignState) -> String {
            switch s {
            case .resolving: return "resolving"
            case .notReady: return "notReady"
            case .ready: return "ready"
            case .answered: return "answered"
            case .refused: return "refused"
            case .gone: return "gone"
            }
        }
        let tokenA = e.addObserver { a.append(name($0)) }
        eq(a, ["resolving"], "an observer is told the current state at once")
        var tokenB: BILPublicObservation? = e.addObserver { b.append(name($0)) }
        e.setState(.refused(info: info, error: BILPublicSignerErrors.unexpected, review: nil, canMatchAgain: true))
        eq(a, ["resolving", "refused"], "every change is told")
        eq(b, ["resolving", "refused"], "to every observer")
        tokenB = nil
        _ = tokenB
        e.setState(.resolving(info))
        eq(b, ["resolving", "refused"], "releasing the token stops the deliveries")
        tokenA.cancel()
        e.setState(.gone)
        eq(a, ["resolving", "refused", "resolving"], "a cancelled observer is not told")
        eq(e.observerCount, 0, "no live observer left")

        // An observer that changes the state while it is told (e.g. discards the request): the later observers get only the
        // newest state, never the older one after it.
        let f = BILPublicRequestEntry(id: "r2", request: request, info: info)
        var first: [String] = []
        var second: [String] = []
        let t1 = f.addObserver { s in
            first.append(name(s))
            if case .refused = s { f.retire() }
        }
        let t2 = f.addObserver { second.append(name($0)) }
        f.setState(.refused(info: info, error: BILPublicSignerErrors.unexpected, review: nil, canMatchAgain: false))
        eq(first, ["resolving", "refused", "gone"], "the re-entrant observer sees both")
        eq(second, ["resolving", "gone"], "the next observer sees only the newest state")
        _ = (t1, t2)

        // The coordinator's observe: unknown ids are gone at once.
        let c = Env().coordinator()
        var unknown: [String] = []
        let tok = c.observe("nope") { unknown.append(name($0)) }
        eq(unknown, ["gone"], "observing an unknown id delivers .gone")
        tok.cancel()
    }

    // MARK: - Snapshot

    @MainActor private static func snapshotTests() {
        section("wallet snapshot")
        func input(_ id: String, _ keyId: String?) -> BILJSONObject {
            var o = BILJSONObject()
            o.set("localWalletId", .string(id))
            if let k = keyId {
                o.set("publicIndex", .object(BILJSONObject([("walletKeyId", .string(k))])))
            }
            return o
        }
        let a = BILPublicResolverInput.snapshot(of: [input("w1", "AABB"), input("w2", nil), input("w3", "ccdd")])
        eq(a.walletKeyId("w1"), "aabb", "key ids are lower-cased")
        t(a.walletKeyId("w2") == nil && a.contains("w2"), "an unprepared wallet is offered without a key id")
        t(a.walletKeyId("w9") == nil && !a.contains("w9"), "an unknown wallet is not offered")
        eq(a.unpreparedWalletIds, ["w2"], "unprepared wallets in input order")
        let b = BILPublicResolverInput.snapshot(of: [input("w3", "CCDD"), input("w1", "aabb"), input("w2", nil)])
        t(a == b, "equality ignores the order (Android Map equality)")
        t(a != BILPublicResolverInput.snapshot(of: [input("w1", "aabb"), input("w2", nil)]), "a missing wallet differs")
        t(a != BILPublicResolverInput.snapshot(of: [input("w1", "aabb"), input("w2", "11"), input("w3", "ccdd")]), "a new index differs")
        t(a != BILPublicResolverInput.snapshot(of: [input("w1", "aabb"), input("w2", nil), input("w3", "ccde")]), "another key id differs")
        t(a != BILPublicResolverInput.snapshot(of: [input("w1", "aabb"), input("w2", nil), input("w3", "ccdd"), input("hot-new", nil)]),
          "an added wallet differs")
        let decomposed = BILPublicResolverInput.snapshot(of: [input("e\u{301}", nil)])
        t(decomposed != BILPublicResolverInput.snapshot(of: [input("\u{e9}", nil)]), "wallet ids are compared exactly (code units)")
        t(BILPublicWalletSnapshot.empty == BILPublicResolverInput.snapshot(of: []), "empty")
    }

    // MARK: - Resolver input (R5 §1.5)

    @MainActor private static func resolverInputTests() {
        section("resolver input")
        t(BILPublicResolverInput.isTronHexAddress("41" + String(repeating: "a", count: 40)), "41… hex")
        t(BILPublicResolverInput.isTronHexAddress("0x41" + String(repeating: "F", count: 40)), "0x41… hex")
        t(!BILPublicResolverInput.isTronHexAddress("0X41" + String(repeating: "a", count: 40)), "only a lower-case 0x prefix")
        t(!BILPublicResolverInput.isTronHexAddress("41" + String(repeating: "a", count: 39)), "41 + 39 hex")
        t(!BILPublicResolverInput.isTronHexAddress("41" + String(repeating: "a", count: 40) + "\n"), "no final newline (whole string)")
        t(!BILPublicResolverInput.isTronHexAddress("42" + String(repeating: "a", count: 40)), "version 41 only")
        eq(BILPublicSignCoordinator.maxResolverWallets, 100, "100 wallets")
        eq(BILPublicResolverInput.maxRequestBytes, BILPublicSignerEngine.maxRequestBytes, "the bridge's request limit")
        eq(BILPublicResolverInput.tronCacheMin, BILPublicIndexRepository.tronCacheMin, "the least TRON cache")

        let c = Env().coordinator()
        // Android `too many wallets - only the request's fingerprint (and unprepared wallets) are offered`.
        let abandon = CW.publicIndex("abandon")
        let legal = CW.publicIndex("legal")
        func w(_ id: String, _ index: BILJSONObject?) -> BILJSONObject {
            var o = BILJSONObject()
            o.set("localWalletId", .string(id))
            if let i = index { o.set("publicIndex", .object(i)) }
            return o
        }
        var inputs: [BILJSONObject] = (0..<40).map { w("legal-\($0)", legal) }
        inputs.append(w(CW.ABANDON, abandon))
        inputs += (0..<3).map { w("unprepared-\($0)", nil) }
        let evm = SigningVectors.request("T8-flow-evm-eip1559")
        let fitted = c.fitResolverInput(request: evm, inputs: inputs)
        eq(fitted?.compactMap { $0.str("localWalletId") } ?? [], [CW.ABANDON, "unprepared-0", "unprepared-1", "unprepared-2"],
           "only the request's fingerprint and the unprepared wallets")
        t(BILPublicSignerEngine.resolveRequestByteCount(request: evm, wallets: inputs) > BILPublicResolverInput.maxRequestBytes,
          "41 indexes exceed the bridge limit")
        let psbt = SigningVectors.request("T8-flow-bitcoin-crypto-psbt")
        t(c.fitResolverInput(request: psbt, inputs: inputs) == nil, "a PSBT names its fingerprints only inside the PSBT: tooManyWallets")
        let small = Array(inputs.suffix(4))
        t(c.fitResolverInput(request: psbt, inputs: small) == small, "small sets go through unchanged")
        // 101 small wallets: over the engine's count.
        let many = (0..<101).map { w("u-\($0)", nil) }
        t(c.fitResolverInput(request: evm, inputs: many) == nil, "101 wallets never fit (no fingerprint filter helps unprepared ones)")
        t(c.fitResolverInput(request: evm, inputs: Array(many.prefix(100))) != nil, "100 fit")

        // Android `too many wallets - the TRON address cache is cut to what the request can use`.
        let ownbit = CW.publicIndex("abandonOwnbit")
        let cache = ownbit.arr("tronAddressIndex") ?? []
        func address(_ i: Int) -> String {
            return "T" + String(format: "%033d", i)
        }
        func grown(_ n: Int) -> BILJSONObject {
            var entries: [BILJSONValue] = []
            for i in 0..<n {
                if i < cache.count {
                    entries.append(cache[i])
                } else {
                    var e = cache[i % cache.count].objectValue ?? BILJSONObject()
                    e.set("index", .int(i))
                    e.set("address", .string(address(i)))
                    entries.append(.object(e))
                }
            }
            var o = ownbit
            o.set("tronAddressIndex", .array(entries))
            return o
        }
        let big = grown(1_000)
        var tronInputs: [BILJSONObject] = (0..<4).map { w("high-\($0)", big) }
        tronInputs.append(w("unprepared", nil))
        t(BILStrictJSON.serialize(.array(tronInputs.map { .object($0) })).utf8.count > BILPublicResolverInput.maxRequestBytes,
          "four 1000-address indexes exceed the bridge limit")
        let cutFit = c.fitResolverInput(request: psbt, inputs: tronInputs)
        eq(cutFit?.compactMap { $0.str("localWalletId") } ?? [], ["high-0", "high-1", "high-2", "high-3", "unprepared"],
           "they no longer refuse a PSBT")
        for (k, element) in (cutFit ?? []).prefix(4).enumerated() {
            let index = element.obj("publicIndex")
            t(index?.arr("tronAddressIndex") == cache, "high-\(k): the 100 addresses the engine requires")
            var restA = index ?? BILJSONObject(), restB = big
            restA.remove("tronAddressIndex"); restB.remove("tronAddressIndex")
            t(restA == restB, "high-\(k): nothing else changes")
            t(index?.keys == big.keys, "high-\(k): key order kept")
        }
        var withOther = tronInputs
        withOther.append(w("other", grown(100)))
        var tron = BILJSONObject()
        tron.set("chain", .string("tron")); tron.set("address", .string(address(777))); tron.set("kind", .string("transaction"))
        let byAddress = c.fitResolverInput(request: tron, inputs: withOther)
        eq(byAddress?.compactMap { $0.str("localWalletId") } ?? [], ["high-0", "high-1", "high-2", "high-3", "unprepared"],
           "a TRON request by address: only the wallets whose cache holds it (and the unprepared ones)")
        let kept = byAddress?.first?.obj("publicIndex")?.arr("tronAddressIndex") ?? []
        eq(kept.count, 778, "each cache up to that address")
        eq(kept.last?.objectValue?.str("address"), address(777), "… ending at the address")
        let crowded = (0..<5).map { w("high-\($0)", big) }
        var t999 = BILJSONObject()
        t999.set("chain", .string("tron")); t999.set("address", .string(address(999)))
        t(c.fitResolverInput(request: t999, inputs: crowded) == nil, "still too large (five wallets hold #999): tooManyWallets")
        let smallTron = Array(tronInputs.prefix(2))
        t(c.fitResolverInput(request: psbt, inputs: smallTron) == smallTron, "a request that fits is never changed")
        // TRON with a key path: the cache is not looked up → 100 addresses each.
        var withPath = tron
        withPath.set("path", .string("m/44'/195'/0'/0/0"))
        let cutPath = BILPublicResolverInput.tronCacheCut(request: withPath, inputs: tronInputs)
        eq(cutPath.count, 5, "a TRON request with a path keeps every wallet")
        eq(cutPath.first?.obj("publicIndex")?.arr("tronAddressIndex")?.count, 100, "… with 100 addresses")
        // A hex 41… address is looked up as its base58 form.
        if let hex = BILTronAddressCodec.hex41(fromBase58: CW_TRON_0) {
            var byHex = BILJSONObject()
            byHex.set("chain", .string("tron")); byHex.set("address", .string("0x" + hex.uppercased()))
            let hexCut = BILPublicResolverInput.tronCacheCut(request: byHex, inputs: [w("a", ownbit), w("b", legal)])
            eq(hexCut.compactMap { $0.str("localWalletId") }, ["a"], "a hex address is converted to base58 for the lookup")
        } else {
            t(false, "TRON #0 converts to hex")
        }
    }

    private static let CW_TRON_0 = "TUEZSdKsoDHQMeZwihtdoBiN46zxhGWYdH"

    // MARK: - TronLink answer (OtherWalletAnswersTest through the coordinator's builder)

    @MainActor private static func tronLinkAnswerTests() {
        section("TronLink answer")
        func answer(_ text: String, _ vector: String) -> BILPublicResponseQr? {
            let request = tronLinkRequest(text)
            let plan = SigningVectors.planOf(SigningVectors.steps(vector, "resolveSigningPlan").first?.result ?? BILJSONObject())
            let pre = BILPublicSignVerifier.pre(request: request, plan: plan, reviewedChainId: plan.review?.network?.chainId)
            guard let verified = pre.payload, let raw = SigningVectors.signResults(vector).last,
                  let signature = BILPublicTronLinkAnswer.signature(of: SigningVectors.resultOf(raw)) else {
                t(false, "\(vector): pre-check / signature")
                return nil
            }
            return try? BILPublicTronLinkAnswer.response(request: request, verified: verified, signature: signature)
        }
        let v1 = answer(OtherWalletVectors.V1_REQUEST, "O-TL-V1-ownership-ios")
        eq(v1?.frames ?? [], [OtherWalletVectors.V1_ANSWER], "V1 ownership answer byte for byte")
        eq(v1?.type, "tronlink", "type tronlink")
        t(v1?.signedTransaction == false, "the ownership placeholder is not a signed transaction")
        eq(v1?.payload?.format, .json, "Payload · JSON")
        eq(v1?.payload?.byteCount, OtherWalletVectors.V1_ANSWER.utf8.count, "byte count of the compact answer")
        eq(v1?.payload?.qrType, "tronlink", "payload qr type")
        let v3 = answer(OtherWalletVectors.V3_REQUEST, "O-TL-V3-trx-transfer")
        eq(v3?.frames ?? [], [OtherWalletVectors.V3_ANSWER], "V3 transfer answer byte for byte")
        t(v3?.signedTransaction == true, "a TRON transaction answer carries the signed transaction")
        let v4 = answer(OtherWalletVectors.V4_REQUEST, "O-TL-V4-tip191-message")
        eq(v4?.frames ?? [], [OtherWalletVectors.V4_ANSWER], "V4 TIP-191 message answer byte for byte")
        t(v4?.signedTransaction == false, "a message answer is not a transaction")

        // Failures: each a Failure (→ err.verify / ANSWER in the coordinator).
        let request = tronLinkRequest(OtherWalletVectors.V3_REQUEST)
        let plan = SigningVectors.plan("O-TL-V3-trx-transfer")
        guard let verified = BILPublicSignVerifier.pre(request: request, plan: plan, reviewedChainId: nil).payload else {
            t(false, "V3 pre-check")
            return
        }
        let sig = SigningVectors.signResults("O-TL-V3-trx-transfer").last.flatMap { BILPublicTronLinkAnswer.signature(of: SigningVectors.resultOf($0)) } ?? []
        throwsError(BILPublicTronLinkAnswer.Failure.self, "a 64-byte signature is refused") {
            _ = try BILPublicTronLinkAnswer.response(request: request, verified: verified, signature: Array(sig.prefix(64)))
        }
        throwsError(BILPublicTronLinkAnswer.Failure.self, "a request without payloadBytes is refused") {
            _ = try BILPublicTronLinkAnswer.response(request: without(request, "transport"), verified: verified, signature: sig)
        }
        var badTransport = request.obj("transport") ?? BILJSONObject()
        badTransport.set("payloadBytes", .string(BILPublicHex.encode(Array("not json".utf8))))
        throwsError(BILPublicTronLinkAnswer.Failure.self, "a payload that is no TronLink request is refused") {
            _ = try BILPublicTronLinkAnswer.response(request: with(request, "transport", .object(badTransport)), verified: verified, signature: sig)
        }
        throwsError(BILPublicTronLinkAnswer.Failure.self, "a non-TRON payload is refused") {
            _ = try BILPublicTronLinkAnswer.response(request: request, verified: .evmPersonal([1, 2]), signature: sig)
        }
        throwsError(BILPublicTronLinkAnswer.Failure.self, "a TRON transaction without its Transaction bytes is refused") {
            if case .tronTransaction(let raw, let decoded, let owner, let type, _) = verified {
                _ = try BILPublicTronLinkAnswer.response(request: request, verified: .tronTransaction(raw: raw, decoded: decoded, ownerHex41: owner,
                                                                                                        contractType: type, txProto: nil),
                                                         signature: sig)
            } else {
                throw BILPublicTronLinkAnswer.Failure(what: "not a transaction")
            }
        }
        var withSig = BILJSONObject()
        withSig.set("signature", .string("0x" + BILPublicHex.encode(sig)))
        t(BILPublicTronLinkAnswer.signature(of: resultWith(withSig)) == nil, "a 0x-prefixed signature is not read (Android Hex.decodeOrNull)")
        eq(String(describing: BILPublicTronLinkAnswer.Failure(what: "signature")), "TronLink answer not built: signature", "a failure prints its step only")
    }

    /// A sign result with `raw` fields merged into a vector result (only `raw` matters for the signature reader).
    private static func resultWith(_ extra: BILJSONObject) -> BILPublicSignResult {
        var raw = SigningVectors.signResults("O-TL-V3-trx-transfer").last ?? BILJSONObject()
        for e in extra.entries { raw.set(e.key, e.value) }
        return SigningVectors.resultOf(raw)
    }

    // MARK: - Session

    @MainActor private static func sessionTests() {
        section("session")
        let plan = SigningVectors.plan("T8-flow-psbt-two-wallets")
        guard let review = plan.review, plan.tasks.count == 2 else {
            t(false, "two-wallet plan")
            return
        }
        var s = BILPublicSignSession(requestId: "req-1", request: SigningVectors.request("T8-flow-psbt-two-wallets"), review: review, plan: plan)
        eq(s.nextTask?.id, plan.tasks[0].id, "plan order")
        eq(s.transportType, "crypto-psbt", "transport")
        s.completedTaskIds = [plan.tasks[0].id]
        eq(s.nextTask?.id, plan.tasks[1].id, "the next task")
        t(!s.isComplete, "not complete")
        s.completedTaskIds.append(plan.tasks[1].id)
        t(s.nextTask == nil && s.isComplete, "complete")
        t(s.witnessOnlyInputs.isEmpty, "no verified payload: no witness-only inputs")
        let text = String(describing: s)
        t(text.hasPrefix("BILPublicSignSession(req-1, bitcoin, tasks=2, done=2, answered=false"), "prints ids and counts (\(text))")
        var dumped = ""
        dump(s, to: &dumped)
        t(!dumped.contains("psbt") && !dumped.contains(review.requestHash), "dump shows no content")
    }
}
