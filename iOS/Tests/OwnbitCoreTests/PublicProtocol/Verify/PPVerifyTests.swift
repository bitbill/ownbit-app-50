//  PPVerifyTests.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Port of the app harness suite `scripts/public-protocol/tests/verify` (main.swift) to XCTest.
//
//  main.swift — suite "verify" (WP9, design §3.6 / §4 WP9): native verification primitives.
//  BILPsbtMaps, BILEvmTxCodec, BILTronRawData, BILSolanaMessageHeader, BILStrictCbor, BILSignatureUrCodec,
//  BILVerifiedPayload. Ports of Android PST:verify/{PsbtMapsTest, SolanaMessageHeaderTest, SignatureUrCodecTest,
//  WitnessOnlyPrevoutVerifierTest}.kt (PsbtMaps / header / codec parts), A:core/chain/…/evm/EvmTxCodecUnsignedTest.kt,
//  A:core/chain/…/tron/TronTransactionVerifierTest.kt (raw decode), plus sweeps over every golden vector
//  ($PUB_FIXTURES/vectors.json, keystone-tron-public.json) and edge cases of the Android readers.
//  Test code only: the vectors are read with JSONSerialization (only strings / booleans / small integers are used).
//

import Foundation
import XCTest
@testable import OwnbitCore

/// The suite namespace (harness helpers are its static members).
enum PPVerifySuite: PPSuite {}

final class PPVerifyTests: XCTestCase {
    func testVerify() throws {
        try ppRunSuite("verify") { try PPVerifySuite.run() }
    }
}

extension PPVerifySuite {

    // MARK: - Fixtures

    static let vectorsRoot: [String: Any] = {
        guard let root = (try? JSONSerialization.jsonObject(with: fixture("vectors.json"))) as? [String: Any] else {
            print("FAIL vectors.json is not a JSON object")
            exit(2)
        }
        return root
    }()

    static let caseList: [[String: Any]] = (vectorsRoot["cases"] as? [[String: Any]]) ?? []
    static var casesById = [String: [String: Any]]()
    struct Step {
        let request: [String: Any]
        let response: [String: Any]
        var op: String { return request["operation"] as? String ?? "" }
        var ok: Bool { return response["ok"] as? Bool ?? false }
        var result: [String: Any] { return response["result"] as? [String: Any] ?? [:] }
        var errorCode: String? { return (response["error"] as? [String: Any])?["code"] as? String }
        /// The engine-native request of the step (`request.request`).
        var engineRequest: [String: Any]? { return request["request"] as? [String: Any] }
    }
    static func steps(_ id: String, _ op: String? = nil) -> [Step] {
        let raw = (casesById[id]?["steps"] as? [[String: Any]]) ?? []
        let all = raw.map { Step(request: $0["request"] as? [String: Any] ?? [:], response: $0["response"] as? [String: Any] ?? [:]) }
        guard let op = op else { return all }
        return all.filter { $0.op == op }
    }
    static func scannedRequest(_ id: String) -> [String: Any]? {
        let s = steps(id).last { ($0.op == "scanAdd" || $0.op == "decodePayload") && $0.ok && ($0.result["complete"] as? Bool ?? false) }
        return s?.result["request"] as? [String: Any]
    }
    static func planRequest(_ id: String) -> [String: Any]? {
        return steps(id, "resolveSigningPlan").first?.engineRequest ?? steps(id, "review").first?.engineRequest
    }
    static func planJson(_ id: String) -> [String: Any]? {
        let s = steps(id, "resolveSigningPlan")
        return s.count == 1 ? s[0].result : nil
    }
    static func signResults(_ id: String) -> [[String: Any]] {
        return steps(id, "signPlanTask").filter { $0.ok }.map { $0.result }
    }
    static func encoded(_ id: String) -> [String: Any]? {
        return steps(id, "encodeResponse").first { $0.ok }?.result
    }
    static func frames(_ id: String) -> [String] {
        return encoded(id)?["frames"] as? [String] ?? []
    }
    static func tasks(_ plan: [String: Any]?) -> [[String: Any]] {
        return plan?["tasks"] as? [[String: Any]] ?? []
    }
    static func signersOf(_ tasks: [[String: Any]]) -> [Int: Set<String>] {
        var out = [Int: Set<String>]()
        for task in tasks {
            for target in (task["targets"] as? [[String: Any]]) ?? [] {
                guard let input = target["inputIndex"] as? Int, let key = target["publicKey"] as? String else { continue }
                out[input, default: []].insert(key)
            }
        }
        return out
    }
    static func b64(_ s: String?) -> [UInt8] {
        guard let s = s, let d = Data(base64Encoded: s) else { return [] }
        return [UInt8](d)
    }
    static func hx(_ s: String) -> [UInt8] {
        let t = s.hasPrefix("0x") ? String(s.dropFirst(2)) : s
        guard let b = BILPublicHex.decode(t) else { print("FAIL bad hex in test: \(s.prefix(20))"); exit(2) }
        return b
    }
    static func hexOf(_ b: [UInt8]) -> String { return BILPublicHex.encode(b) }
    static func repeatHex(_ unit: String, _ n: Int) -> String { return String(repeating: unit, count: n) }
    static func refusedWith(_ what: String, _ label: String, file: StaticString = #file, line: UInt = #line, _ body: () throws -> Void) {
        do {
            try body()
            t(false, "\(label): did not throw (expected \(what))", file: file, line: line)
        } catch let e as BILVerifyError {
            eq(e.what, what, label, file: file, line: line)
        } catch {
            t(false, "\(label): threw \(type(of: error)), expected BILVerifyError(\(what))", file: file, line: line)
        }
    }
    static func refused(_ label: String, file: StaticString = #file, line: UInt = #line, _ body: () throws -> Void) {
        throwsError(BILVerifyError.self, label, file: file, line: line, body)
    }
    indirect enum TC {
        case u(UInt64)
        case n(Int64)            // the value (negative)
        case b([UInt8])
        case t(String)
        case a([TC])
        case m([(TC, TC)])
        case tag(UInt64, TC)
        case bool(Bool)
        case null
    }
    static func cborHead(_ major: UInt8, _ n: UInt64) -> [UInt8] {
        let m = major << 5
        if n < 24 { return [m | UInt8(n)] }
        if n < 256 { return [m | 24, UInt8(n)] }
        if n < 65_536 { return [m | 25, UInt8(n >> 8), UInt8(n & 0xFF)] }
        if n < (1 << 32) { return [m | 26] + (0..<4).reversed().map { UInt8((n >> (8 * UInt64($0))) & 0xFF) } }
        return [m | 27] + (0..<8).reversed().map { UInt8((n >> (8 * UInt64($0))) & 0xFF) }
    }
    static func cbor(_ v: TC) -> [UInt8] {
        switch v {
        case .u(let x): return cborHead(0, x)
        case .n(let x): return cborHead(1, UInt64(-1 - x))
        case .b(let x): return cborHead(2, UInt64(x.count)) + x
        case .t(let s): let u = Array(s.utf8); return cborHead(3, UInt64(u.count)) + u
        case .a(let items): return items.reduce(cborHead(4, UInt64(items.count))) { $0 + cbor($1) }
        case .m(let pairs): return pairs.reduce(cborHead(5, UInt64(pairs.count))) { $0 + cbor($1.0) + cbor($1.1) }
        case .tag(let tag, let x): return cborHead(6, tag) + cbor(x)
        case .bool(let x): return [x ? 0xF5 : 0xF4]
        case .null: return [0xF6]
        }
    }
    static let testWords: [UInt8] = Array((
        "ableacidalsoapexaquaarchatomauntawayaxisbackbaldbarnbeltbetabiasbluebodybragbrewbulbbuzzcalmcashcatschefcity" +
        "clawcodecolacookcostcruxcurlcuspcyandarkdatadaysdelidicedietdoordowndrawdropdrumdulldutyeacheasyechoedge" +
        "epicevenexamexiteyesfactfairfernfigsfilmfishfizzflapflewfluxfoxyfreefrogfuelfundgalagamegeargemsgiftgirl" +
        "glowgoodgraygrimgurugushgyrohalfhanghardhawkheathelphighhillholyhopehornhutsicedideaidleinchinkyintoiris" +
        "ironitemjadejazzjoinjoltjowljudojugsjumpjunkjurykeepkenokeptkeyskickkilnkingkitekiwiknoblamblavalazyleaf" +
        "legsliarlimplionlistlogoloudloveluaulucklungmainmanymathmazememomenumeowmildmintmissmonknailnavyneednews" +
        "nextnoonnotenumbobeyoboeomitonyxopenovalowlspaidpartpeckplaypluspoempoolposepuffpumapurrquadquizraceramp" +
        "realredorichroadrockroofrubyruinrunsrustsafesagascarsetssilkskewslotsoapsolosongstubsurfswantacotasktaxi" +
        "tenttiedtimetinytoiltombtoystriptunatwinuglyundouniturgeuservastveryvetovialvibeviewvisavoidvowswallwand" +
        "warmwaspwavewaxywebswhatwhenwhizwolfworkyankyawnyellyogayurtzapszerozestzinczonezoom").utf8)
    static func bytewordsOf(_ bytes: [UInt8]) -> String {
        let crc = BILPublicHash.crc32(bytes)
        let all = bytes + [UInt8(crc >> 24), UInt8((crc >> 16) & 0xFF), UInt8((crc >> 8) & 0xFF), UInt8(crc & 0xFF)]
        var out = [UInt8]()
        for b in all { out.append(testWords[Int(b) * 4]); out.append(testWords[Int(b) * 4 + 3]) }
        return String(decoding: out, as: UTF8.self)
    }
    static func singleUr(_ type: String, _ cborBytes: [UInt8]) -> String {
        return "UR:" + type.uppercased() + "/" + bytewordsOf(cborBytes).uppercased()
    }
    static func multiUr(_ type: String, _ message: [UInt8], fragLen: Int, crcOverride: UInt64? = nil) -> [String] {
        let count = (message.count + fragLen - 1) / fragLen
        let crc = crcOverride ?? UInt64(BILPublicHash.crc32(message))
        var out = [String]()
        for i in 0..<count {
            var piece = Array(message[(i * fragLen)..<min(message.count, (i + 1) * fragLen)])
            while piece.count < fragLen { piece.append(0) }
            let part = cbor(.a([.u(UInt64(i + 1)), .u(UInt64(count)), .u(UInt64(message.count)), .u(crc), .b(piece)]))
            out.append("ur:\(type)/\(i + 1)-\(count)/" + bytewordsOf(part))
        }
        return out
    }
    static func signatureUr(_ type: String, _ requestId: String?, _ sig: [UInt8], extra: [(TC, TC)] = []) -> String {
        var pairs = [(TC, TC)]()
        if let id = requestId { pairs.append((.u(1), .tag(37, .b(hx(id))))) }
        pairs.append((.u(2), .b(sig)))
        pairs.append(contentsOf: extra)
        return singleUr(type, cbor(.m(pairs)))
    }
    static func compactBytes(_ n: Int) -> [UInt8] {
        if n < 0xFD { return [UInt8(n)] }
        if n <= 0xFFFF { return [0xFD, UInt8(n & 0xFF), UInt8(n >> 8)] }
        return [0xFE, UInt8(n & 0xFF), UInt8((n >> 8) & 0xFF), UInt8((n >> 16) & 0xFF), UInt8((n >> 24) & 0xFF)]
    }
    typealias KV = (key: [UInt8], value: [UInt8])
    static func kv(_ keyHex: String, _ valueHex: String) -> KV { return (hx(keyHex), hx(valueHex)) }
    static let psbtMagic: [UInt8] = [0x70, 0x73, 0x62, 0x74, 0xFF]
    static func buildPsbt(_ global: [KV], _ inputs: [[KV]], _ outputs: [[KV]]) -> [UInt8] {
        var out = psbtMagic
        for map in [global] + inputs + outputs {
            for e in map { out += compactBytes(e.key.count) + e.key + compactBytes(e.value.count) + e.value }
            out.append(0)
        }
        return out
    }
    static func entries(_ es: [BILPsbtMaps.Entry]) -> [KV] { return es.map { ($0.key, $0.value) } }
    static func editPsbt(_ maps: BILPsbtMaps, _ edit: (inout [KV], inout [[KV]], inout [[KV]]) -> Void) throws -> BILPsbtMaps {
        var g = entries(maps.global)
        var i = maps.inputs.map(entries)
        var o = maps.outputs.map(entries)
        edit(&g, &i, &o)
        return try BILPsbtMaps.parse(buildPsbt(g, i, o))
    }
    static let TX: [UInt8] = hx("02000000" + "01" + repeatHex("00", 32) + "00000000" + "00" + "ffffffff" +
                         "01" + "a086010000000000" + "16" + "0014" + repeatHex("11", 20) + "00000000")
    static func minimalV0() -> [UInt8] { return buildPsbt([(hx("00"), TX)], [[]], [[]]) }
    static func derivations(_ id: String) -> [BILPsbtMaps.OutputDerivation] {
        guard let maps = try? BILPsbtMaps.parse(b64(scannedRequest(id)?["psbt"] as? String)) else { return [] }
        return (try? maps.outputDerivations()) ?? []
    }
    static let v2Txid = repeatHex("ab", 32)
    static func v2Psbt(global extra: [KV] = [], inputs: [[KV]], outputs: [[KV]]? = nil, txVersion: String? = "02000000") -> [UInt8] {
        var g: [KV] = [kv("fb", "02000000")]
        if let v = txVersion { g.append(kv("02", v)) }
        g.append(kv("04", hexOf(compactBytes(inputs.count))))
        let outs = outputs ?? [[kv("03", "a086010000000000"), kv("04", "0014" + repeatHex("11", 20))]]
        g.append(kv("05", hexOf(compactBytes(outs.count))))
        return buildPsbt(g + extra, inputs, outs)
    }
    static func v2Input(index: String = "01000000", extra: [KV] = []) -> [KV] {
        return [kv("0e", v2Txid), kv("0f", index)] + extra
    }
    static func v2Expected(inputs: [(String, String)], lockTime: String) -> String {
        var s = "02000000" + hexOf(compactBytes(inputs.count))
        for (index, sequence) in inputs { s += v2Txid + index + "00" + sequence }
        return s + "01" + "a086010000000000" + "16" + "0014" + repeatHex("11", 20) + lockTime
    }
    static let wAmount = "a086010000000000"
    static let wHash = "c0cebcd6c3d3ca8c75dc5ec62ebe55330ef910e2"
    static let p2wpkhUtxo = "01011f" + wAmount + "16" + "0014" + wHash
    static func witnessUtxo(_ scriptHex: String) -> String {
        let script = hx(scriptHex)
        let value = wAmount + String(format: "%02x", script.count) + scriptHex
        return "0101" + String(format: "%02x", value.count / 2) + value
    }
    static func redeemScript(_ scriptHex: String) -> String { return "0104" + String(format: "%02x", scriptHex.count / 2) + scriptHex }
    static let o6Hex = hexOf(b64(planRequest("O-BTC-6-segwit-witness-only")?["psbt"] as? String))
    static func o6With(_ record: String) throws -> BILPsbtMaps {
        return try BILPsbtMaps.parse(hx(o6Hex.replacingOccurrences(of: p2wpkhUtxo, with: record)))
    }
    static let TYPE2 = "0x02e70180843b9aca0084773594008252089422222222222222222222222222222222222222220180c0"
    static func sub(_ s: String, _ from: Int) -> String { return String(s.dropFirst(from)) }   // Kotlin substring(from) on the 0x text
    static func evmRefused(_ hexText: String, _ what: String, _ label: String, file: StaticString = #file, line: UInt = #line) {
        refusedWith(what, label, file: file, line: line) { _ = try BILEvmTxCodec.decodeUnsigned(hexText.isEmpty ? [] : hx(hexText)) }
    }
    static func withChainId(_ hex8: String) -> String { return "02ef88" + hex8 + sub(TYPE2, 8) }
    static func pbKey(_ field: Int, _ wire: Int) -> [UInt8] {
        var v = UInt64(field << 3 | wire); var out = [UInt8]()
        repeat { var b = UInt8(v & 0x7F); v >>= 7; if v != 0 { b |= 0x80 }; out.append(b) } while v != 0
        return out
    }
    static func pbVarint(_ value: UInt64) -> [UInt8] {
        var v = value; var out = [UInt8]()
        repeat { var b = UInt8(v & 0x7F); v >>= 7; if v != 0 { b |= 0x80 }; out.append(b) } while v != 0
        return out
    }
    static func pbBytes(_ field: Int, _ b: [UInt8]) -> [UInt8] { return pbKey(field, 2) + pbVarint(UInt64(b.count)) + b }
    static func pbNum(_ field: Int, _ v: UInt64) -> [UInt8] { return pbKey(field, 0) + pbVarint(v) }
    static func contract(type: UInt64, url: String = "type.googleapis.com/protocol.TransferContract", value: [UInt8], permission: UInt64? = nil) -> [UInt8] {
        var c = pbNum(1, type) + pbBytes(2, pbBytes(1, Array(url.utf8)) + pbBytes(2, value))
        if let p = permission { c += pbNum(5, p) }
        return c
    }
    static func solMessage(_ id: String) -> [UInt8] {
        let s = steps(id).first { $0.op == "review" || $0.op == "resolveSigningPlan" }
        return b64(s?.engineRequest?["message"] as? String)
    }
    static func solParse(_ b: [UInt8]) -> BILSolanaMessageHeader? { return try? BILSolanaMessageHeader.parse(b) }
    static func solRefused(_ b: [UInt8], _ label: String, file: StaticString = #file, line: UInt = #line) {
        do {
            _ = try BILSolanaMessageHeader.parse(b)
            t(false, "\(label): did not throw", file: file, line: line)
        } catch BILSolanaMessageHeader.ParseError.malformed {
            t(true, label, file: file, line: line)
        } catch {
            t(false, "\(label): threw \(error)", file: file, line: line)
        }
    }

    /// The harness main.swift (nonisolated top-level code, as in the harness).
    static func run() throws {
        for c in caseList { if let id = c["id"] as? String { casesById[id] = c } }
        let allCaseIds: [String] = caseList.compactMap { $0["id"] as? String }

        /// Android `SigningVectors.request(id)`: the request of the last complete scan / paste.

        /// The request of the (single) resolveSigningPlan step, else of the first review step.

        /// Android `SigningVectors.answeredFlows`.
        let answeredFlows: [String] = allCaseIds.filter { id in
            let s = steps(id)
            return s.contains { $0.op == "encodeResponse" && $0.ok } && s.contains { $0.op == "signPlanTask" && $0.ok }
                && s.contains { $0.op == "resolveSigningPlan" } && !s.contains { $0.op == "review" && !$0.ok }
        }.sorted()

        /// input index → task public keys (Android `PublicSignVerifier.targetsOf`).

        /// Passes when `body` throws `BILVerifyError(what)` exactly.

        /// Passes when `body` throws any `BILVerifyError`.

        // MARK: - Test CBOR / UR writer (independent of the app code; port of Android TestUr)

        /// Minimal bytewords of `bytes` + big-endian CRC-32.

        /// Pure fountain parts (seq 1…count) of `message` with fragments of `fragLen` bytes (last one zero-padded).

        // MARK: - Test PSBT builder (port of PsbtMapsTest helpers)

        /// Rebuilds `maps` after `edit` (Android `edit(maps) { … }`).

        /// version 2, one input (zero txid, index 0, empty script sig, sequence ffffffff), one P2WPKH output, locktime 0.

        // =====================================================================================================================
        // MARK: - PSBT: compact sizes
        // =====================================================================================================================

        section("psbt.readCompact")
        eq(try BILPsbtMaps.readCompact([0xFC], 0).value, 0xFC, "fc → 252")
        eq(try BILPsbtMaps.readCompact([0xFC], 0).next, 1, "fc → next 1")
        eq(try BILPsbtMaps.readCompact([0xFD, 0xFD, 0x00], 0).value, 0xFD, "fd fd 00 → 253")
        eq(try BILPsbtMaps.readCompact([0xFD, 0xFD, 0x00], 0).next, 3, "fd fd 00 → next 3")
        refusedWith("compactSize.nonCanonical", "fd fc 00 non-canonical") { _ = try BILPsbtMaps.readCompact([0xFD, 0xFC, 0x00], 0) }
        refusedWith("compactSize.nonCanonical", "fe 00 01 00 00 non-canonical") { _ = try BILPsbtMaps.readCompact([0xFE, 0x00, 0x01, 0x00, 0x00], 0) }
        eq(try BILPsbtMaps.readCompact([0xFE, 0x00, 0x00, 0x02, 0x00], 0).value, 131_072, "fe 131072 is the cap")
        refusedWith("compactSize.nonCanonical", "fe 131073 above the cap") { _ = try BILPsbtMaps.readCompact([0xFE, 0x01, 0x00, 0x02, 0x00], 0) }
        refusedWith("compactSize.nonCanonical", "ff 8 bytes is always above the cap") { _ = try BILPsbtMaps.readCompact([0xFF, 0, 0, 0, 0, 1, 0, 0, 0], 0) }
        refusedWith("compactSize.truncated", "fd with one byte") { _ = try BILPsbtMaps.readCompact([0xFD, 0xFD], 0) }
        refusedWith("compactSize.truncated", "past the end") { _ = try BILPsbtMaps.readCompact([0x01], 1) }
        eq(try BILPsbtMaps.readCompact([0xAA, 0x05], 1).value, 5, "offset read")

        // =====================================================================================================================
        // MARK: - PSBT: every vector PSBT hashes to the engine's digest
        // =====================================================================================================================

        section("psbt.vectors.digest")
        var psbtVersions = Set<Int>()
        var psbtChecked = 0
        for id in allCaseIds {
            let resolves = steps(id, "resolveSigningPlan")
            guard resolves.count == 1, resolves[0].ok, resolves[0].result["status"] as? String == "ready",
                  resolves[0].result["chain"] as? String == "bitcoin", let request = resolves[0].engineRequest else { continue }
            do {
                let maps = try BILPsbtMaps.parse(b64(request["psbt"] as? String))
                eq(maps.unsignedTxDigest, resolves[0].result["signingBytesDigest"] as? String ?? "", "\(id): unsigned tx digest = signingBytesDigest")
                psbtVersions.insert(maps.version)
                psbtChecked += 1
                // Every input of an engine-ready PSBT names its outpoint and amount (R2-2 rule; the pre-check refuses otherwise).
                for i in 0..<maps.inputs.count {
                    t(maps.outpoint(i) != nil && maps.claimedAmount(i) != nil, "\(id): input \(i) outpoint + amount readable")
                    // Where an input carries both records they agree (amount and script, scure getPrevOut order).
                    if maps.hasFullPrevTx(i), let w = maps.inputs[i].first(where: { $0.type == 1 && $0.key.count == 1 })?.value, w.count > 8 {
                        var amount: UInt64 = 0
                        for k in stride(from: 7, through: 0, by: -1) { amount = (amount << 8) | UInt64(w[k]) }
                        eq(maps.claimedAmount(i), amount, "\(id): input \(i) full prev tx amount = witness utxo amount")
                        eq(maps.prevoutScript(i).map(hexOf), hexOf(Array(w[9...])), "\(id): input \(i) full prev tx script = witness utxo script")
                    }
                    // v0 and v2: the outpoint is the one in the unsigned transaction (v2: rebuilt; same 41-byte layout).
                    if let op = maps.outpoint(i) {
                        let at = 5 + 41 * i
                        eq(hexOf(op.txid), hexOf(Array(maps.unsignedTx[at..<(at + 32)])), "\(id): input \(i) txid as stored in the unsigned tx")
                    }
                }
            } catch {
                t(false, "\(id): PSBT parses (\(error))")
            }
        }
        t(psbtChecked >= 20, "checked \(psbtChecked) ready Bitcoin plans (≥ 20)")
        eq(psbtVersions, [0, 2], "both PSBT versions covered")

        do {
            let request = planRequest("T7-native-bitcoin-psbt-2")
            let maps = try BILPsbtMaps.parse(b64(request?["psbt"] as? String))
            eq(maps.version, 2, "T7-native-bitcoin-psbt-2 is a PSBT v2")
            eq(maps.unsignedTxDigest, planJson("T7-native-bitcoin-psbt-2")?["signingBytesDigest"] as? String ?? "", "v2 rebuilt to the plan digest")
        } catch {
            t(false, "T7-native-bitcoin-psbt-2 parses (\(error))")
        }

        // Engine `decoded` view of every PSBT answer: outpoints (display order) and output values equal the native read.
        section("psbt.vectors.decoded")
        var decodedChecked = 0
        for id in answeredFlows {
            guard let e = encoded(id), let payload = e["payload"] as? [String: Any], let decoded = payload["decoded"] as? [String: Any],
                  let tx = decoded["tx"] as? [String: Any], let vin = tx["vin"] as? [[String: Any]], let vout = tx["vout"] as? [[String: Any]],
                  let maps = try? BILPsbtMaps.parse(b64(payload["psbt_base64"] as? String)) else { continue }
            decodedChecked += 1
            eq(maps.inputs.count, vin.count, "\(id): input count = engine decode")
            eq(maps.outputs.count, vout.count, "\(id): output count = engine decode")
            for (i, input) in vin.enumerated() where i < maps.inputs.count {
                eq(maps.outpoint(i).map { hexOf($0.txid.reversed()) }, input["txid"] as? String, "\(id): input \(i) txid (display order)")
                eq(maps.outpoint(i).map { Int($0.vout) }, input["vout"] as? Int, "\(id): input \(i) vout")
            }
            for (i, output) in vout.enumerated() where i < maps.outputs.count {
                if let sats = output["value_sat"] as? Int, let script = (output["scriptPubKey"] as? [String: Any])?["hex"] as? String {
                    // locate output i in the unsigned tx: after the inputs (41 bytes each, empty script sigs)
                    var p = 4 + 1 + 41 * maps.inputs.count
                    p += 1                                  // output count (< 0xfd in every vector)
                    for _ in 0..<i {
                        let len = Int(maps.unsignedTx[p + 8])
                        p += 9 + len
                    }
                    var amount: UInt64 = 0
                    for k in stride(from: 7, through: 0, by: -1) { amount = (amount << 8) | UInt64(maps.unsignedTx[p + k]) }
                    eq(amount, UInt64(sats), "\(id): output \(i) value")
                    let len = Int(maps.unsignedTx[p + 8])
                    eq(hexOf(Array(maps.unsignedTx[(p + 9)..<(p + 9 + len)])), script, "\(id): output \(i) script")
                }
            }
        }
        t(decodedChecked >= 15, "engine-decoded PSBT answers checked: \(decodedChecked) (≥ 15)")

        // =====================================================================================================================
        // MARK: - PSBT: diff
        // =====================================================================================================================

        section("psbt.diff.vectors")
        var diffChecked = 0
        for id in allCaseIds {
            let signs = steps(id, "signPlanTask").filter { $0.ok }
            guard let first = signs.first, first.engineRequest?["chain"] as? String == "bitcoin", let last = signs.last else { continue }
            do {
                let request = try BILPsbtMaps.parse(b64(first.engineRequest?["psbt"] as? String))
                let signed = try BILPsbtMaps.parse(b64(last.result["psbt"] as? String))
                let diff = BILPsbtMaps.diff(request: request, response: signed, signers: signersOf(tasks(planJson(id))))
                t(diff.ok, "\(id): signing only adds the task keys' signatures (\(diff.problem ?? "ok"))")
                t(diff.addedSignatures >= 1, "\(id): at least one signature added")
                diffChecked += 1
            } catch {
                t(false, "\(id): request / signed PSBT parse (\(error))")
            }
        }
        t(diffChecked >= 20, "signed Bitcoin vectors diffed: \(diffChecked) (≥ 20)")

        do {
            let id = "T8-flow-psbt-two-wallets"
            let plan = planJson(id)
            eq(tasks(plan).count, 2, "two-wallet plan has 2 tasks")
            let request = try BILPsbtMaps.parse(b64(scannedRequest(id)?["psbt"] as? String))
            let signed = try BILPsbtMaps.parse(b64(signResults(id).last?["psbt"] as? String))
            t(BILPsbtMaps.diff(request: request, response: signed, signers: signersOf(tasks(plan))).ok, "two-wallet PSBT: both tasks' keys explain the answer")
            t(!BILPsbtMaps.diff(request: request, response: signed, signers: signersOf(Array(tasks(plan).prefix(1)))).ok,
              "two-wallet PSBT: the second wallet's signature is not the first task's")
        } catch {
            t(false, "two-wallet vectors parse (\(error))")
        }

        section("psbt.diff.tamper")
        do {
            let id = "T8-flow-bitcoin-crypto-psbt"
            let signers = signersOf(tasks(planJson(id)))
            let request = try BILPsbtMaps.parse(b64(scannedRequest(id)?["psbt"] as? String))
            let signed = try BILPsbtMaps.parse(b64(signResults(id).last?["psbt"] as? String))
            t(BILPsbtMaps.diff(request: request, response: signed, signers: signers).ok, "untouched answer ok")
            eq(BILPsbtMaps.diff(request: request, response: request, signers: signers).problem, "no signature added", "nothing added")
            eq(BILPsbtMaps.diff(request: request, response: request, signers: signers).addedSignatures, 0, "nothing added: 0")
            let outChanged = try editPsbt(signed) { _, _, o in o[0].append(kv("fc", "01")) }
            eq(BILPsbtMaps.diff(request: request, response: outChanged, signers: signers).problem, "output 0 map", "an output map changed")
            let globalChanged = try editPsbt(signed) { g, _, _ in g.append(kv("fc00", "02")) }
            eq(BILPsbtMaps.diff(request: request, response: globalChanged, signers: signers).problem, "global map", "a global entry added")
            let requestWithUnknown = try editPsbt(request) { _, i, _ in i[0].append(kv("fc01", "03")) }
            eq(BILPsbtMaps.diff(request: requestWithUnknown, response: signed, signers: signers).problem, "input 0 entry removed or changed",
               "an unknown input entry the request had is gone")
            let foreign = try editPsbt(signed) { _, i, _ in i[0].append(kv("02" + "03" + repeatHex("11", 32), "3044")) }
            eq(BILPsbtMaps.diff(request: request, response: foreign, signers: signers).problem, "input 0 unexpected entry 2", "a signature of another key")
            let otherInput = [(signers.keys.max() ?? 0) + 1: signers.values.first ?? []]
            t(!BILPsbtMaps.diff(request: request, response: signed, signers: otherInput).ok, "a signature on an input the task does not sign")
            let finalized = try editPsbt(signed) { _, i, _ in i[0].append(kv("07", "00")) }
            eq(BILPsbtMaps.diff(request: request, response: finalized, signers: signers).problem, "input 0 unexpected entry 7", "a final script")
            let changedValue = try editPsbt(signed) { _, i, _ in
                if let k = i[0].firstIndex(where: { $0.key == [0x01] }) { i[0][k].value[0] ^= 0x01 }
            }
            eq(BILPsbtMaps.diff(request: request, response: changedValue, signers: signers).problem, "input 0 entry removed or changed",
               "a changed witness utxo")
            refusedWith("psbt.trailing", "an extra output map the unsigned tx does not count") { _ = try editPsbt(signed) { _, _, o in o.append([]) } }
            // Upper-case signer keys are accepted (Android lower-cases them).
            var upper = [Int: Set<String>]()
            for (k, v) in signers { upper[k] = Set(v.map { $0.uppercased() }) }
            t(BILPsbtMaps.diff(request: request, response: signed, signers: upper).ok, "signer keys compared case-insensitively")
            // A PSBT v2 answer to a v0 request.
            let v2 = try BILPsbtMaps.parse(b64(planRequest("T7-native-bitcoin-psbt-2")?["psbt"] as? String))
            eq(BILPsbtMaps.diff(request: request, response: v2, signers: signers).problem, "version", "version differs")
        } catch {
            t(false, "tamper vectors (\(error))")
        }

        // =====================================================================================================================
        // MARK: - PSBT: output derivations, BIP-86 key path
        // =====================================================================================================================

        section("psbt.outputDerivations")
        eq(derivations("O-BTC-3-change-999").map { $0.pathText }, ["m/84'/0'/0'/1/999"], "change 999")
        eq(derivations("O-BTC-3-change-1000").map { $0.pathText }, ["m/84'/0'/0'/1/1000"], "change 1000")
        eq(derivations("O-BTC-3-change-1000").first?.fingerprint, "73c5da0a", "change 1000 fingerprint")
        eq(derivations("O-BTC-3-change-1000").first?.taproot, false, "change 1000 is BIP-32")
        eq(derivations("O-BTC-3-change-1000").first?.publicKey.count, 66, "BIP-32 derivation key = 33 bytes")
        t(derivations("O-BTC-3-change-bip48").count == 1 && derivations("O-BTC-3-change-bip48")[0].pathText.hasPrefix("m/48'/0'/0'/2'/"), "bip48 path")
        let tapHashes = derivations("O-BTC-3-change-taphashes")
        eq(tapHashes.count, 1, "taphashes: one derivation")
        eq(tapHashes.first?.pathText, "m/84'/0'/0'/1/2147483647", "taphashes: 101 leaf hashes still read")
        eq(tapHashes.first?.taproot, true, "taphashes: Taproot BIP-32")
        eq(tapHashes.first?.fingerprint, "73c5da0a", "taphashes: fingerprint")
        eq(tapHashes.first?.publicKey.count, 64, "Taproot derivation key = x-only")
        eq(derivations("O-BTC-3-change-taproot-taphashes").map { $0.pathText }, ["m/86'/0'/0'/1/5000"], "taproot taphashes")
        eq(BILPsbtMaps.pathText([0x8000_0054, 0x8000_0000, 0x8000_0000, 1, 5]), "m/84'/0'/0'/1/5", "pathText")
        eq(BILPsbtMaps.pathText([]), "m", "pathText root")
        eq(BILPsbtMaps.hardened, 0x8000_0000, "hardened bit = Android PsbtMaps.HARDENED")
        eq(BILPsbtMaps.pathText([0xFFFF_FFFF, 0x7FFF_FFFF, BILPsbtMaps.hardened, 0]), "m/2147483647'/2147483647/0'/0", "pathText bounds")
        do {
            // Malformed derivation entries are skipped; a non-canonical leaf-hash count throws.
            let out: [KV] = [kv("02" + "02" + repeatHex("22", 32), "73c5da0a54000080"),               // 33 + 1 = 34-byte key: ok
                             kv("02" + "02" + repeatHex("22", 31), "73c5da0a"),                          // 33-byte key: skipped
                             kv("02" + "03" + repeatHex("22", 32), "73c5da0a5400"),                      // ragged path: skipped
                             kv("07" + repeatHex("33", 32), "00" + "73c5da0a" + "05000000"),             // 0 leaf hashes, path [5]
                             kv("07" + repeatHex("44", 32), "01" + repeatHex("00", 32) + "73c5da0a"),    // 1 leaf hash, empty path
                             kv("07" + repeatHex("55", 32), "02" + repeatHex("00", 32) + "73c5da0a")]    // 2 hashes declared, 1 present: skipped
            let maps = try BILPsbtMaps.parse(buildPsbt([(hx("00"), TX)], [[]], [out]))
            let d = try maps.outputDerivations()
            eq(d.map { $0.pathText }, ["m/84'", "m/5", "m"], "derivation shapes")
            eq(d.map { $0.taproot }, [false, true, true], "derivation kinds")
            let bad = try BILPsbtMaps.parse(buildPsbt([(hx("00"), TX)], [[]], [[kv("07" + repeatHex("33", 32), "fd0100")]]))
            refusedWith("compactSize.nonCanonical", "non-canonical leaf-hash count throws") { _ = try bad.outputDerivations() }
        } catch {
            t(false, "derivation fixtures (\(error))")
        }

        section("psbt.keyPath")
        let bip86Internal = hx("cc8a4bc64d897bddc5fbc2f670f7a8ba0b386779106cf1223c6fc5d7cd6fc115")
        eq(BILSecp256k1.taprootOutputScript(xOnly: bip86Internal).map(hexOf), "5120a60869f0dbcf1dc659c9cecbaf8050135ea9e8cdc487053f1dc6880949dc684c",
           "BIP-86 vector output script")
        for id in ["O-BTC-5-taproot-no-internal-key", "O-BTC-5-taproot-no-derivation"] {
            do {
                let request = try BILPsbtMaps.parse(b64(scannedRequest(id)?["psbt"] as? String))
                let signed = try BILPsbtMaps.parse(b64(signResults(id).last?["psbt"] as? String))
                eq(request.tapInternalKey(0), nil, "\(id): no internal key")
                eq(request.prevoutScript(0).map(hexOf), BILSecp256k1.taprootOutputScript(xOnly: bip86Internal).map(hexOf), "\(id): the witness UTXO is the BIP-86 output")
                eq(request.prevoutKind(0), .witnessTaproot, "\(id): Taproot prevout")
                t(request.keyPathOf(0, xOnlyHex: hexOf(bip86Internal)), "\(id): key path of the task key")
                t(request.keyPathOf(0, xOnlyHex: hexOf(bip86Internal).uppercased()), "\(id): key path, upper-case key")
                let diff = BILPsbtMaps.diff(request: request, response: signed, signers: signersOf(tasks(planJson(id))))
                t(diff.ok, "\(id): diff ok (\(diff.problem ?? "ok"))")
                let other = [0: Set(["0330d54fd0dd420a6e5f8d3624f5f3482cae350f79d5f0753bf5beef9c2d91af3c"])]
                eq(BILPsbtMaps.diff(request: request, response: signed, signers: other).problem, "input 0 unexpected entry 19", "\(id): another key did not sign")
            } catch {
                t(false, "\(id) parses (\(error))")
            }
        }
        do {
            let native = try BILPsbtMaps.parse(b64(scannedRequest("T8-flow-bitcoin-crypto-psbt")?["psbt"] as? String))
            let script = native.prevoutScript(0) ?? []
            eq(script.count, 22, "full prev tx: P2WPKH script")
            eq(hexOf(Array(script.prefix(2))), "0014", "full prev tx: 0014")
            t(!native.keyPathOf(0, xOnlyHex: hexOf(bip86Internal)), "not a key path of an unrelated key")
            eq(native.prevoutKind(0), .fullPreviousTx, "full previous tx kind")
            t(!native.keyPathOf(0, xOnlyHex: "zz"), "bad hex key is never a key path")
            t(!native.keyPathOf(5, xOnlyHex: hexOf(bip86Internal)), "out-of-range input is never a key path")
            // Internal key named explicitly.
            let withInternal = try editPsbt(native) { _, i, _ in i[0].append(kv("17", hexOf(bip86Internal))) }
            eq(withInternal.tapInternalKey(0), hexOf(bip86Internal), "tapInternalKey read")
            t(withInternal.keyPathOf(0, xOnlyHex: hexOf(bip86Internal).uppercased()), "internal key compared case-insensitively")
        } catch {
            t(false, "native vector parses (\(error))")
        }
        eq(BILSecp256k1.taprootOutputScript(xOnly: [UInt8](repeating: 0xFF, count: 32)).map(hexOf), nil, "ff…ff is not on the curve")

        // =====================================================================================================================
        // MARK: - PSBT: malformed
        // =====================================================================================================================

        section("psbt.malformed")
        do {
            let good = minimalV0()
            let maps = try BILPsbtMaps.parse(good)
            eq(maps.version, 0, "minimal v0 parses")
            eq(hexOf(maps.unsignedTx), hexOf(TX), "v0 unsigned tx = global tx")
            eq(maps.outpoint(0)?.vout, 0, "minimal outpoint vout")
            eq(maps.claimedAmount(0), nil, "no utxo record → no amount")
            eq(maps.prevoutKind(0), .none, "no utxo record → none")
        } catch {
            t(false, "minimal v0 parses (\(error))")
        }
        var badMagic = minimalV0(); badMagic[0] = 0x71
        refusedWith("psbt.magic", "magic") { _ = try BILPsbtMaps.parse(badMagic) }
        refusedWith("psbt.trailing", "trailing byte") { _ = try BILPsbtMaps.parse(minimalV0() + [0]) }
        refusedWith("compactSize.truncated", "truncated (output map missing)") { _ = try BILPsbtMaps.parse(Array(minimalV0().dropLast())) }
        refusedWith("psbt.duplicateKey", "duplicate global key") { _ = try BILPsbtMaps.parse(buildPsbt([(hx("00"), TX), (hx("00"), TX)], [[]], [[]])) }
        refusedWith("psbt.unsignedTx", "no unsigned tx") { _ = try BILPsbtMaps.parse(buildPsbt([kv("fc", "00")], [[]], [[]])) }
        refusedWith("psbt.unsignedTx", "two unsigned-tx entries") { _ = try BILPsbtMaps.parse(buildPsbt([(hx("00"), TX), (hx("0001"), TX)], [[]], [[]])) }
        refusedWith("psbt.unsignedTx", "unsigned tx with a 2-byte key") { _ = try BILPsbtMaps.parse(buildPsbt([(hx("0001"), TX)], [[]], [[]])) }
        let withScriptSig = Array(TX[0..<41]) + [0x01, 0x51] + Array(TX[42...])
        refusedWith("psbt.tx.scriptSig", "unsigned tx with a script sig") { _ = try BILPsbtMaps.parse(buildPsbt([(hx("00"), withScriptSig)], [[]], [[]])) }
        refusedWith("psbt.v0.fields", "v0 with a v2 field 04") { _ = try BILPsbtMaps.parse(buildPsbt([(hx("00"), TX), kv("04", "01")], [[]], [[]])) }
        refusedWith("psbt.v0.fields", "v0 with a v2 field 02 under a longer key") { _ = try BILPsbtMaps.parse(buildPsbt([(hx("00"), TX), kv("0201", "01")], [[]], [[]])) }
        let nonCanonicalKey = psbtMagic + [0xFD, 0x01, 0x00, 0x00] + compactBytes(TX.count) + TX + [0, 0, 0]
        refusedWith("compactSize.nonCanonical", "key length 1 written as fd 01 00") { _ = try BILPsbtMaps.parse(nonCanonicalKey) }
        refusedWith("psbt.version", "version 1") { _ = try BILPsbtMaps.parse(buildPsbt([(hx("00"), TX), kv("fb", "01000000")], [[]], [[]])) }
        refusedWith("psbt.version", "version value of 3 bytes") { _ = try BILPsbtMaps.parse(buildPsbt([(hx("00"), TX), kv("fb", "000000")], [[]], [[]])) }
        refusedWith("psbt.v2.inputCount", "v2 without counts") { _ = try BILPsbtMaps.parse(buildPsbt([kv("fb", "02000000"), kv("02", "02000000")], [], [])) }
        refusedWith("psbt.size", "larger than 128 KiB") {
            _ = try BILPsbtMaps.parse(buildPsbt([(hx("00"), TX), (hx("fc02"), [UInt8](repeating: 0, count: BILPsbtMaps.maxBytes))], [[]], [[]]))
        }
        refusedWith("psbt.size", "5 bytes") { _ = try BILPsbtMaps.parse(psbtMagic) }
        refusedWith("compactSize.nonCanonical", "malformed key type (fd …) in a key") {
            _ = try BILPsbtMaps.parse(buildPsbt([(hx("00"), TX), kv("fd0000", "00")], [[]], [[]]))
        }
        var segwitTx = TX; segwitTx.insert(contentsOf: [0x00, 0x01], at: 4)
        refusedWith("psbt.tx.witness", "unsigned tx in segwit serialization") { _ = try BILPsbtMaps.parse(buildPsbt([(hx("00"), segwitTx)], [[]], [[]])) }
        var noInputs = TX; noInputs[4] = 0x00
        refusedWith("psbt.tx.witness", "zero inputs (reads as a segwit marker)") { _ = try BILPsbtMaps.parse(buildPsbt([(hx("00"), noInputs)], [[]], [[]])) }
        refusedWith("psbt.tx.trailing", "unsigned tx with a trailing byte") { _ = try BILPsbtMaps.parse(buildPsbt([(hx("00"), TX + [0])], [[]], [[]])) }
        refusedWith("psbt.tx.size", "unsigned tx shorter than 10 bytes") { _ = try BILPsbtMaps.parse(buildPsbt([kv("00", "020000000100")], [[]], [[]])) }
        refusedWith("psbt.truncated", "value longer than the PSBT") { _ = try BILPsbtMaps.parse(psbtMagic + [0x01, 0x00, 0x50, 0x00]) }

        // =====================================================================================================================
        // MARK: - PSBT: v2 rebuild (BIP-370 lock time)
        // =====================================================================================================================

        section("psbt.v2")
        do {
            var maps = try BILPsbtMaps.parse(v2Psbt(inputs: [v2Input()]))
            eq(hexOf(maps.unsignedTx), v2Expected(inputs: [("01000000", "ffffffff")], lockTime: "00000000"), "v2: no locks, no fallback → 0")
            eq(maps.outpoint(0), BILPsbtMaps.Outpoint(txid: hx(v2Txid), vout: 1), "v2 outpoint from PREVIOUS_TXID / OUTPUT_INDEX")
            maps = try BILPsbtMaps.parse(v2Psbt(global: [kv("03", "44332211")], inputs: [v2Input(extra: [kv("10", "fdffffff")])]))
            eq(hexOf(maps.unsignedTx), v2Expected(inputs: [("01000000", "fdffffff")], lockTime: "44332211"), "v2: fallback lock time, sequence")
            maps = try BILPsbtMaps.parse(v2Psbt(global: [kv("03", "44332211")],
                                                inputs: [v2Input(extra: [kv("12", "64000000")]), v2Input(index: "02000000", extra: [kv("12", "c8000000")])]))
            eq(hexOf(maps.unsignedTx), v2Expected(inputs: [("01000000", "ffffffff"), ("02000000", "ffffffff")], lockTime: "c8000000"), "v2: max height")
            maps = try BILPsbtMaps.parse(v2Psbt(inputs: [v2Input(extra: [kv("11", "0046c323"), kv("12", "64000000")]),
                                                         v2Input(index: "02000000", extra: [kv("11", "0027b929"), kv("12", "32000000")])]))
            eq(hexOf(maps.unsignedTx), v2Expected(inputs: [("01000000", "ffffffff"), ("02000000", "ffffffff")], lockTime: "64000000"),
               "v2: both kinds everywhere → height wins")
            maps = try BILPsbtMaps.parse(v2Psbt(inputs: [v2Input(extra: [kv("11", "0046c323")]),
                                                         v2Input(index: "02000000", extra: [kv("11", "8036be26"), kv("12", "05000000")])]))
            eq(hexOf(maps.unsignedTx), v2Expected(inputs: [("01000000", "ffffffff"), ("02000000", "ffffffff")], lockTime: "8036be26"),
               "v2: one input time-only → max time")
            // The minimum time lock is 500 000 000 (0x1dcd6500); 499 999 999 is refused below.
            _ = try BILPsbtMaps.parse(v2Psbt(inputs: [v2Input(extra: [kv("11", "0065cd1d")])]))
            t(true, "v2: time lock 500 000 000 accepted")
        } catch {
            t(false, "v2 fixtures parse (\(error))")
        }
        refusedWith("psbt.v2.locktime", "v2: height-only and time-only inputs") {
            _ = try BILPsbtMaps.parse(v2Psbt(inputs: [v2Input(extra: [kv("12", "64000000")]), v2Input(index: "02000000", extra: [kv("11", "0046c323")])]))
        }
        refusedWith("psbt.v2.timeLock", "v2: time lock 499 999 999") { _ = try BILPsbtMaps.parse(v2Psbt(inputs: [v2Input(extra: [kv("11", "ff64cd1d")])])) }
        refusedWith("psbt.v2.heightLock", "v2: height lock 0") { _ = try BILPsbtMaps.parse(v2Psbt(inputs: [v2Input(extra: [kv("12", "00000000")])])) }
        refusedWith("psbt.v2.heightLock", "v2: height lock 500 000 000") { _ = try BILPsbtMaps.parse(v2Psbt(inputs: [v2Input(extra: [kv("12", "0065cd1d")])])) }
        refusedWith("psbt.v2.previousTxid", "v2: no previous txid") { _ = try BILPsbtMaps.parse(v2Psbt(inputs: [[kv("0f", "01000000")]])) }
        refusedWith("psbt.v2.previousTxid", "v2: 31-byte txid") { _ = try BILPsbtMaps.parse(v2Psbt(inputs: [[kv("0e", repeatHex("ab", 31)), kv("0f", "01000000")]])) }
        refusedWith("psbt.v2.previousTxid", "v2: last 0x0e entry has a 2-byte key") {
            _ = try BILPsbtMaps.parse(v2Psbt(inputs: [v2Input(extra: [kv("0e01", v2Txid)])]))
        }
        refusedWith("psbt.v2.outputIndex", "v2: no output index") { _ = try BILPsbtMaps.parse(v2Psbt(inputs: [[kv("0e", v2Txid)]])) }
        refusedWith("psbt.v2.sequence", "v2: 3-byte sequence") { _ = try BILPsbtMaps.parse(v2Psbt(inputs: [v2Input(extra: [kv("10", "ffffff")])])) }
        refusedWith("psbt.v2.amount", "v2: 7-byte amount") {
            _ = try BILPsbtMaps.parse(v2Psbt(inputs: [v2Input()], outputs: [[kv("03", "a0860100000000"), kv("04", "0014" + repeatHex("11", 20))]]))
        }
        refusedWith("psbt.v2.script", "v2: no script") { _ = try BILPsbtMaps.parse(v2Psbt(inputs: [v2Input()], outputs: [[kv("03", "a086010000000000")]])) }
        refusedWith("psbt.v2.txVersion", "v2: no tx version") { _ = try BILPsbtMaps.parse(v2Psbt(inputs: [v2Input()], txVersion: nil)) }
        refusedWith("psbt.v2.fallbackLocktime", "v2: 2-byte fallback") { _ = try BILPsbtMaps.parse(v2Psbt(global: [kv("03", "0000")], inputs: [v2Input()])) }
        refusedWith("psbt.v2.unsignedTx", "v2 with an unsigned tx") { _ = try BILPsbtMaps.parse(v2Psbt(global: [(hx("00"), TX)], inputs: [v2Input()])) }
        refusedWith("psbt.compactValue", "v2: input count with a trailing byte") {
            _ = try BILPsbtMaps.parse(buildPsbt([kv("fb", "02000000"), kv("02", "02000000"), kv("04", "0100"), kv("05", "01")], [v2Input()],
                                                [[kv("03", "a086010000000000"), kv("04", "00")]]))
        }
        refusedWith("psbt.counts", "v2: 0 inputs") {
            _ = try BILPsbtMaps.parse(buildPsbt([kv("fb", "02000000"), kv("02", "02000000"), kv("04", "00"), kv("05", "01")], [],
                                                [[kv("03", "a086010000000000"), kv("04", "00")]]))
        }
        refusedWith("psbt.counts", "v2: 101 inputs") {
            _ = try BILPsbtMaps.parse(buildPsbt([kv("fb", "02000000"), kv("02", "02000000"), kv("04", "65"), kv("05", "01")], [], []))
        }

        // =====================================================================================================================
        // MARK: - PSBT: witness-only kinds (port of WitnessOnlyPrevoutVerifierTest, at the PsbtMaps level)
        // =====================================================================================================================

        section("psbt.witnessOnly")
        let hash160Of0014 = "a6b5888fddc8fa193dd353d10e5cd5a8eeab064e"       // RIPEMD160(SHA256(0014‖wHash)), Python hashlib
        let multisigRedeem = "5121" + "02" + repeatHex("33", 32) + "51ae"
        let hash160OfMultisig = "e719458d608da220fafbd696da2aa85f4c12060e"
        eq(hexOf(BILPublicHash.hash160(hx("0014" + wHash))), hash160Of0014, "hash160 reference (nested P2WPKH)")
        t(o6Hex.contains(p2wpkhUtxo), "the O-BTC-6 input carries the expected witness UTXO record")
        do {
            let o6 = try BILPsbtMaps.parse(hx(o6Hex))
            eq(o6.prevoutKind(0), .witnessSegwitV0, "O-BTC-6: P2WPKH witness-only")
            eq(o6.claimedAmount(0), 100_000, "O-BTC-6: amount from the witness UTXO")
            t(o6.outpoint(0) != nil, "O-BTC-6: outpoint")
            eq(try o6With(witnessUtxo("0014" + wHash)).prevoutKind(0), .witnessSegwitV0, "rebuilt record: same kind")
            eq(try o6With(witnessUtxo("0020" + repeatHex("44", 32))).prevoutKind(0), .witnessSegwitV0, "P2WSH")
            let nested = witnessUtxo("a914" + hash160Of0014 + "87") + redeemScript("0014" + wHash)
            eq(try o6With(nested).prevoutKind(0), .witnessSegwitV0, "P2SH-P2WPKH with its redeem script")
            eq(try o6With(witnessUtxo("5120" + repeatHex("11", 32))).prevoutKind(0), .witnessTaproot, "Taproot")
            eq(try o6With(witnessUtxo("76a914" + wHash + "88ac")).prevoutKind(0), .witnessLegacy, "P2PKH")
            eq(try o6With(witnessUtxo("a914" + hash160Of0014 + "87")).prevoutKind(0), .witnessLegacy, "bare P2SH (no redeem script)")
            let wrongHash = witnessUtxo("a914" + repeatHex("22", 20) + "87") + redeemScript("0014" + wHash)
            eq(try o6With(wrongHash).prevoutKind(0), .witnessLegacy, "P2SH with a redeem script of another hash")
            let notWitness = witnessUtxo("a914" + hash160OfMultisig + "87") + redeemScript(multisigRedeem)
            eq(try o6With(notWitness).prevoutKind(0), .witnessLegacy, "P2SH whose redeem script is not a v0 program")
            let removed = try o6With("")
            eq(removed.prevoutKind(0), .none, "no UTXO record → none")
            eq(removed.claimedAmount(0), nil, "no UTXO record → no amount")
            // A witness UTXO whose script length does not span the record.
            let ragged = try o6With("0101" + "1f" + wAmount + "17" + "0014" + wHash)
            eq(ragged.prevoutScript(0).map(hexOf), nil, "script length beyond the record → no script")
            eq(ragged.prevoutKind(0), .none, "unreadable script → none")
            eq(ragged.claimedAmount(0), 100_000, "the amount is still read")
            let over = try o6With("0101" + "1f" + "0140075af0750700" + "16" + "0014" + wHash)     // 21 million BTC + 1 sat
            eq(over.claimedAmount(0), nil, "amount above 21 million BTC → nil")
            let atCap = try o6With("0101" + "1f" + "0040075af0750700" + "16" + "0014" + wHash)    // exactly 2 100 000 000 000 000
            eq(atCap.claimedAmount(0), 2_100_000_000_000_000, "21 million BTC exactly")
        } catch {
            t(false, "O-BTC-6 mutations parse (\(error))")
        }
        do {
            let two = try BILPsbtMaps.parse(b64(planRequest("O-BTC-6-segwit-witness-only-2-inputs")?["psbt"] as? String))
            eq((0..<two.inputs.count).map { two.prevoutKind($0) }, [.witnessSegwitV0, .witnessSegwitV0], "O-BTC-6 2 inputs: both witness-only v0")
            let nested = try BILPsbtMaps.parse(b64(planRequest("O-BTC-8-nested-witness-only")?["psbt"] as? String))
            eq(nested.prevoutKind(0), .witnessSegwitV0, "O-BTC-8: nested SegWit witness-only")
            let legacy = try BILPsbtMaps.parse(b64(scannedRequest("O-BTC-7-legacy-witness-only")?["psbt"] as? String))
            eq(legacy.prevoutKind(0), .witnessLegacy, "O-BTC-7: legacy witness-only (engine PREVOUT)")
        } catch {
            t(false, "witness-only vectors parse (\(error))")
        }

        section("psbt.fullPrevTx")
        do {
            // A full previous transaction (PSBT_IN_NON_WITNESS_UTXO) in legacy and in segwit serialization: the amount and script
            // of the output the unsigned tx names (vout 1), like scure `getPrevOut`.
            let prevInputs = "01" + repeatHex("00", 32) + "00000000" + "00" + "ffffffff"
            let prevOutputs = "02" + "e803000000000000" + "16" + "0014" + repeatHex("11", 20) + "50c3000000000000" + "16" + "0014" + repeatHex("22", 20)
            let legacyPrev = "02000000" + prevInputs + prevOutputs + "00000000"
            let segwitPrev = "02000000" + "0001" + prevInputs + prevOutputs + "01" + "01" + "aa" + "00000000"
            func spending(_ prevHex: String, vout: String) -> [UInt8] {
                let tx = hx("02000000" + "01" + repeatHex("33", 32) + vout + "00" + "ffffffff" + "01" + "a086010000000000" + "16" + "0014" + repeatHex("11", 20) + "00000000")
                return buildPsbt([(hx("00"), tx)], [[(hx("00"), hx(prevHex))]], [[]])
            }
            for (label, prev) in [("legacy", legacyPrev), ("segwit", segwitPrev)] {
                let maps = try BILPsbtMaps.parse(spending(prev, vout: "01000000"))
                eq(maps.claimedAmount(0), 50_000, "\(label) prev tx: amount of vout 1")
                eq(maps.prevoutScript(0).map(hexOf), "0014" + repeatHex("22", 20), "\(label) prev tx: script of vout 1")
                eq(maps.prevoutKind(0), .fullPreviousTx, "\(label) prev tx: kind")
                eq(maps.outpoint(0), BILPsbtMaps.Outpoint(txid: hx(repeatHex("33", 32)), vout: 1), "\(label): outpoint as stored")
                let first = try BILPsbtMaps.parse(spending(prev, vout: "00000000"))
                eq(first.claimedAmount(0), 1_000, "\(label) prev tx: amount of vout 0")
                let beyond = try BILPsbtMaps.parse(spending(prev, vout: "02000000"))
                eq(beyond.claimedAmount(0), nil, "\(label) prev tx: vout ≥ output count → nil")
                eq(beyond.prevoutScript(0).map(hexOf), nil, "\(label) prev tx: vout ≥ output count → no script")
            }
            let truncated = try BILPsbtMaps.parse(spending(String(legacyPrev.dropLast(60)), vout: "01000000"))
            eq(truncated.claimedAmount(0), nil, "truncated prev tx → nil")
            eq(truncated.prevoutKind(0), .fullPreviousTx, "truncated prev tx is still a full-prev-tx kind (amount unreadable)")
            let tiny = try BILPsbtMaps.parse(spending("020000", vout: "00000000"))
            eq(tiny.claimedAmount(0), nil, "prev tx of 3 bytes → nil")
        } catch {
            t(false, "full prev tx fixtures (\(error))")
        }

        // =====================================================================================================================
        // MARK: - EVM: strict RLP, unsigned transactions (port of EvmTxCodecUnsignedTest)
        // =====================================================================================================================

        section("evm.unsigned")
        let TYPE2_HASH = "262c8a05d85c2095475edcc8fd0bee2f11aee8f90f6a5967107ded79974f6fe5"
        let LEGACY_BSC = "0xe380843b9aca008252089422222222222222222222222222222222222222220180388080"
        let LEGACY_BSC_HASH = "e5f220088849fe148dc9b56b6d4d4baa0187187a73a93c5465e04507078edfed"
        let LEGACY_HYPE = "0xe1010182520894222222222222222222222222222222222222222280808203e78080"
        let LEGACY_HYPE_HASH = "1830a758a650fba8e534d808249e45b0e5060cbc8991813550e997c22a91205c"
        let TYPE1 = "0x01f85f380984b2d05e0082ea609411111111111111111111111111111111111111110584a9059cbbf838f7942222222222222222222222222222222222222222e1a00000000000000000000000000000000000000000000000000000000000000001"
        let TYPE1_HASH = "5a2f83db0f061d3ed9a999fda50dc07776e491ba780b9256f1c733960a031b1a"
        let CREATE_ETC = "0x02d13d030102830186a08080856080604052c0"
        let CREATE_ETC_HASH = "405710b2b7131c2e005c3517956aac87aa0e8e9640ffa101220014dc0410cc4e"

        do {
            let tx = try BILEvmTxCodec.decodeUnsigned(hx(TYPE2))
            eq(tx.type, 2, "1559: type"); eq(tx.chainId, 1, "1559: chainId"); eq(tx.nonce, [], "1559: nonce 0")
            eq(tx.gasPrice, nil, "1559: no gasPrice"); eq(tx.maxPriorityFeePerGas, hx("3b9aca00"), "1559: priority fee")
            eq(tx.maxFeePerGas, hx("77359400"), "1559: max fee"); eq(tx.feePerGas, hx("77359400"), "1559: feePerGas")
            eq(tx.gasLimit, hx("5208"), "1559: gas 21000"); eq(tx.to, "0x2222222222222222222222222222222222222222", "1559: to")
            eq(tx.value, [1], "1559: value 1"); eq(tx.dataHex, "0x", "1559: no data"); eq(tx.accessListEntries, 0, "1559: no access list")
            eq(hexOf(tx.signingHash), TYPE2_HASH, "1559: signing hash")
            eq(BILUnsignedEvmTx.quantityHex(tx.value), "0x1", "quantityHex 1"); eq(BILUnsignedEvmTx.quantityHex([]), "0x0", "quantityHex 0")
            eq(BILUnsignedEvmTx.quantityHex(tx.gasLimit), "0x5208", "quantityHex gas")
            eq(BILUnsignedEvmTx.quantityHex([0x0f, 0xff]), "0xfff", "quantityHex drops the leading zero nibble")
            let bsc = try BILEvmTxCodec.decodeUnsigned(hx(LEGACY_BSC))
            eq(bsc.type, 0, "BSC legacy: type 0"); eq(bsc.chainId, 56, "BSC legacy: chainId 56")
            eq(bsc.gasPrice, hx("3b9aca00"), "BSC: gasPrice"); eq(bsc.maxFeePerGas, nil, "BSC: no max fee")
            eq(bsc.gasLimit, hx("5208"), "BSC: gas"); eq(hexOf(bsc.signingHash), LEGACY_BSC_HASH, "BSC: signing hash")
            let hype = try BILEvmTxCodec.decodeUnsigned(hx(LEGACY_HYPE))
            eq(hype.chainId, 999, "HyperEVM 999 (2-byte chain id)"); eq(hexOf(hype.signingHash), LEGACY_HYPE_HASH, "HyperEVM: signing hash")
            let t1 = try BILEvmTxCodec.decodeUnsigned(hx(TYPE1))
            eq(t1.type, 1, "2930: type"); eq(t1.chainId, 56, "2930: chainId"); eq(t1.nonce, [9], "2930: nonce")
            eq(t1.gasPrice, hx("b2d05e00"), "2930: gasPrice 3 gwei"); eq(t1.gasLimit, hx("ea60"), "2930: gas 60000")
            eq(t1.to, "0x1111111111111111111111111111111111111111", "2930: to"); eq(t1.value, [5], "2930: value")
            eq(t1.dataHex, "0xa9059cbb", "2930: data"); eq(t1.accessListEntries, 1, "2930: one access-list entry")
            eq(hexOf(t1.signingHash), TYPE1_HASH, "2930: signing hash")
            let create = try BILEvmTxCodec.decodeUnsigned(hx(CREATE_ETC))
            eq(create.chainId, 61, "ETC creation: chainId 61"); eq(create.to, nil, "creation: no recipient")
            eq(create.dataHex, "0x6080604052", "creation: init code"); eq(hexOf(create.signingHash), CREATE_ETC_HASH, "creation: signing hash")
        } catch {
            t(false, "EVM unsigned vectors decode (\(error))")
        }
        evmRefused("f86c098504a817c800825208943535353535353535353535353535353535353535880de0b6b3a76400008025a028ef61340bd939bc2195fe537567866003e1a15d3c71ff63e1590620aa636276a067cbe9d8997f761aecb703304b3800ccf555c9f3dc64214b297fb1966a3b6d83",
                   "evm.legacy.signed", "signed legacy (EIP-155 example)")
        evmRefused("e080843b9aca0082520894" + repeatHex("22", 20) + "0180", "evm.legacy.noChainId", "pre-EIP-155 6-field legacy")
        evmRefused("e380843b9aca0082520894" + repeatHex("22", 20) + "0180808080", "evm.chainId.zero", "chain id 0 in the EIP-155 slot")
        evmRefused("02f86a0180843b9aca0084773594008252089422222222222222222222222222222222222222220180c080a09d23098d159bc90cdc19ded378c3fa30dd14e02071603a1f0f33887841ae0c4ea06e1701145900c62e3bf699be521fe500d6c19109a8b18fa573e682905e57d72d",
                   "evm.type2.signed", "signed EIP-1559 (12 fields)")
        evmRefused("03" + sub(TYPE2, 4), "evm.type", "blob type 3")
        evmRefused("04" + sub(TYPE2, 4), "evm.type", "EIP-7702 type 4")
        evmRefused("", "evm.empty", "empty")
        evmRefused("00", "evm.type", "type 0x00")
        eq(try BILEvmTxCodec.decodeUnsigned(hx(withChainId("7fffffffffffffff"))).chainId, UInt64(Int64.max), "chain id 2^63 − 1 accepted")
        eq(try BILEvmTxCodec.decodeUnsigned(hx(withChainId("4000000000000000"))).chainId, UInt64(1) << 62, "chain id 2^62 accepted")
        evmRefused(withChainId("8000000000000000"), "evm.chainId.large", "chain id 2^63 refused")
        evmRefused("02f089" + "01" + repeatHex("00", 8) + sub(TYPE2, 8), "evm.chainId.large", "chain id 2^64 refused")
        evmRefused(sub(TYPE2, 2) + "00", "evm.rlp.trailing", "trailing byte")
        evmRefused("02f827" + sub(TYPE2, 6), "evm.rlp.nonCanonical", "long-form list length below 56")
        evmRefused("02e8018100" + sub(TYPE2, 10), "evm.rlp.singleByte", "nonce 0 as 81 00")
        evmRefused("02e901820007" + sub(TYPE2, 10), "evm.uint.leadingZero", "nonce with a leading zero")
        evmRefused("02e80180843b9aca00847735940082520895" + repeatHex("22", 21) + "0180c0", "evm.address", "21-byte recipient")
        // More strictness (iOS additions; Android refuses the same inputs).
        evmRefused("02c0", "evm.type2.fields", "type 2 with 0 fields")
        evmRefused("01c0", "evm.type1.fields", "type 1 with 0 fields")
        evmRefused("01cb" + repeatHex("80", 11), "evm.type1.signed", "type 1 with 11 fields")
        evmRefused("c0", "evm.legacy.fields", "legacy with 0 fields")
        evmRefused("0280", "evm.rlp.notList", "typed body is a byte string")
        evmRefused("02e7", "evm.rlp.range", "truncated list")
        evmRefused("02bc0102030405", "evm.rlp.length", "lenOfLen 5")
        evmRefused("02e70180843b9aca0084773594008252089422222222222222222222222222222222222222220180c1", "evm.rlp.range", "access list item past the end")
        evmRefused("02e8" + "c101" + sub(TYPE2, 8), "evm.bytes", "chain id as a list")
        evmRefused("02e80180843b9aca0084773594008252089422222222222222222222222222222222222222220180c180", "evm.accessList.entry", "access-list entry not a list")
        evmRefused("02ff" + "0000000100", "evm.rlp.length", "list lenOfLen 8")
        evmRefused("02e60180843b9aca00847735940082520894222222222222222222222222222222222222222201c0", "evm.type2.fields", "type 2 with 8 fields")
        do {
            // Access-list shapes: [[address(20), [slot(32)…]]].
            func type2(accessList: [UInt8]) -> [UInt8] {
                let fields: [[UInt8]] = [[0x01], [0x80], hx("843b9aca00"), hx("8477359400"), hx("825208"), [0x94] + hx(repeatHex("22", 20)), [0x01], [0x80], accessList]
                let payload = fields.reduce([], +)
                return [0x02] + (payload.count <= 55 ? [UInt8(0xC0 + payload.count)] : [0xF8, UInt8(payload.count)]) + payload
            }
            func rlpList(_ items: [[UInt8]]) -> [UInt8] {
                let p = items.reduce([], +)
                return (p.count <= 55 ? [UInt8(0xC0 + p.count)] : [0xF8, UInt8(p.count)]) + p
            }
            let address = [UInt8(0x94)] + hx(repeatHex("33", 20))
            let slot = [UInt8(0xA0)] + hx(repeatHex("44", 32))
            let ok = try BILEvmTxCodec.decodeUnsigned(type2(accessList: rlpList([rlpList([address, rlpList([slot, slot])]), rlpList([address, rlpList([])])])))
            eq(ok.accessListEntries, 2, "access list with 2 entries")
            refusedWith("evm.accessList.slot", "31-byte slot") {
                _ = try BILEvmTxCodec.decodeUnsigned(type2(accessList: rlpList([rlpList([address, rlpList([[0x9F] + hx(repeatHex("44", 31))])])])))
            }
            refusedWith("evm.accessList.entry", "19-byte address") {
                _ = try BILEvmTxCodec.decodeUnsigned(type2(accessList: rlpList([rlpList([[0x93] + hx(repeatHex("33", 19)), rlpList([])])])))
            }
            refusedWith("evm.accessList.slots", "slots not a list") {
                _ = try BILEvmTxCodec.decodeUnsigned(type2(accessList: rlpList([rlpList([address, slot])])))
            }
            refusedWith("evm.accessList", "access list is a byte string") { _ = try BILEvmTxCodec.decodeUnsigned(type2(accessList: [0x80])) }
            refusedWith("evm.bytes", "slot is a list") {
                _ = try BILEvmTxCodec.decodeUnsigned(type2(accessList: rlpList([rlpList([address, rlpList([rlpList([])])])])))
            }
            // A 33-byte integer.
            refusedWith("evm.uint.width", "33-byte value") {
                let fields: [[UInt8]] = [[0x01], [0x80], hx("843b9aca00"), hx("8477359400"), hx("825208"), [0x94] + hx(repeatHex("22", 20)),
                                         [0xA1] + hx("01" + repeatHex("00", 32)), [0x80], [0xC0]]
                _ = try BILEvmTxCodec.decodeUnsigned([0x02] + rlpList(fields))
            }
        } catch {
            t(false, "access-list fixtures (\(error))")
        }
        do {
            // Nesting bomb: 100 000 nested lists inside the data field of a legacy transaction. Refused, no stack overflow.
            var item: [UInt8] = [0xC0]
            for _ in 0..<100_000 {
                let n = item.count
                if n <= 55 { item = [UInt8(0xC0 + n)] + item }
                else if n <= 0xFF { item = [0xF8, UInt8(n)] + item }
                else if n <= 0xFFFF { item = [0xF9, UInt8(n >> 8), UInt8(n & 0xFF)] + item }
                else { item = [0xFA, UInt8(n >> 16), UInt8((n >> 8) & 0xFF), UInt8(n & 0xFF)] + item }
                if item.count > 400_000 { break }
            }
            let bomb = item
            refusedWith("evm.rlp.depth", "deeply nested RLP refused without recursion overflow") { _ = try BILEvmTxCodec.decodeUnsigned(bomb) }
            // 32 nested levels inside the transaction list are still decoded (and refused later by the field rules).
            var inner: [UInt8] = [0xC0]
            for _ in 0..<30 { inner = [UInt8(0xC0 + inner.count)] + inner }
            let fields: [[UInt8]] = [[0x80], hx("843b9aca00"), hx("825208"), [0x94] + hx(repeatHex("22", 20)), [0x01], inner, [0x01], [0x80], [0x80]]
            let payload = fields.reduce([], +)
            refusedWith("evm.bytes", "31 nested levels in a field: decoded, refused by the field rule") {
                _ = try BILEvmTxCodec.decodeUnsigned([0xF8, UInt8(payload.count)] + payload)
            }
        }
        eq(hexOf(BILEvmTxCodec.personalMessageDigest(Array("Ownbit public protocol fixture".utf8))),
           hexOf(BILPublicHash.eip191Digest(Array("Ownbit public protocol fixture".utf8))), "personalMessageDigest = EIP-191")

        // EVM vector sweep (basis of C-EVM-2): CBOR sign request → signData → unsigned tx; chain ids agree; digest = plan's.
        section("evm.vectors")
        var evmTxTypes = Set<Int>()
        var evmChecked = 0
        var evmPersonalChecked = 0
        for id in allCaseIds {
            guard let request = planRequest(id), request["chain"] as? String == "evm",
                  let transport = request["transport"] as? [String: Any], transport["type"] as? String == "eth-sign-request",
                  let payload = transport["payloadBytes"] as? String, let plan = planJson(id), plan["status"] as? String == "ready" else { continue }
            do {
                let cbor = try BILSignatureUrCodec.decodeSignRequest(type: "eth-sign-request", payload: hx(payload))
                let digest = plan["signingBytesDigest"] as? String ?? ""
                eq(cbor.dataType, transport["dataType"] as? Int, "\(id): CBOR key 3 = transport.dataType")
                eq(cbor.chainId.map { Int($0) }, request["chainId"] as? Int, "\(id): CBOR key 4 = request.chainId")
                eq(cbor.chainId.map { Int($0) }, transport["chainId"] as? Int, "\(id): CBOR key 4 = transport.chainId")
                eq(cbor.requestId.map(hexOf), transport["requestId"] as? String, "\(id): request id = transport.requestId")
                switch cbor.dataType ?? -1 {
                case 1, 4:
                    t(BILPublicHex.sameHex(request["transaction"] as? String, cbor.signData), "\(id): request.transaction = signData")
                    let tx = try BILEvmTxCodec.decodeUnsigned(cbor.signData)
                    evmTxTypes.insert(tx.type)
                    eq(cbor.dataType == 1, tx.type == 0, "\(id): dataType 1 ⇔ legacy")
                    eq(cbor.chainId.map { UInt64($0) }, tx.chainId, "\(id): signed bytes' chain id = request chain id")
                    let reviewed = (plan["review"] as? [String: Any]).flatMap { ($0["network"] as? [String: Any])?["chainId"] as? String }
                    eq(reviewed, String(tx.chainId), "\(id): signed bytes' chain id = reviewed network")
                    eq(hexOf(tx.signingHash), digest, "\(id): keccak(signData) = signingBytesDigest")
                    evmChecked += 1
                case 3:
                    t(BILPublicHex.sameHex(request["message"] as? String, cbor.signData), "\(id): request.message = signData")
                    eq(hexOf(BILEvmTxCodec.personalMessageDigest(cbor.signData)), digest, "\(id): EIP-191 digest = signingBytesDigest")
                    evmPersonalChecked += 1
                case 2:
                    t(BILVerifyText.strictUTF8(cbor.signData) != nil, "\(id): typed data is strict UTF-8")
                default:
                    t(false, "\(id): unexpected dataType")
                }
            } catch {
                t(false, "\(id): EVM request decodes (\(error))")
            }
        }
        t(evmChecked >= 10, "EVM transaction vectors checked: \(evmChecked)")
        t(evmPersonalChecked >= 3, "EVM personal vectors checked: \(evmPersonalChecked)")
        eq(evmTxTypes, [0, 2], "vector EVM tx types (type 1 covered by the 2930 constant above)")

        // =====================================================================================================================
        // MARK: - TRON raw data
        // =====================================================================================================================

        section("tron.raw.vectors")
        var tronChecked = 0
        /// Vectors whose contract owner is not the signing address (permission-member signing; the policy refuses them with
        /// err.tronOwner, Android `PublicSignPolicy.tronOwnerRefusal`).
        let ownerNotSigner: Set<String> = ["O-TRX-1-owner-not-signer", "T7-native-tron-transaction-9"]
        for id in allCaseIds {
            guard let request = planRequest(id), request["chain"] as? String == "tron", request["kind"] as? String == "transaction",
                  let plan = planJson(id), plan["status"] as? String == "ready" else { continue }
            let transport = request["transport"] as? [String: Any]
            let type = transport?["type"] as? String
            var raw: [UInt8]
            if type == "tron-sign-request" {
                guard let payload = transport?["payloadBytes"] as? String,
                      let cbor = try? BILSignatureUrCodec.decodeSignRequest(type: "tron-sign-request", payload: hx(payload)) else {
                    t(false, "\(id): TRON sign request decodes"); continue
                }
                eq(cbor.dataType, 1, "\(id): dataType 1")
                raw = cbor.signData
                t(BILPublicHex.sameHex((request["transaction"] as? [String: Any])?["raw_data_hex"] as? String, raw), "\(id): raw_data_hex = signData")
            } else if type == "tronlink" || type == nil {
                raw = hx(((request["transaction"] as? [String: Any])?["raw_data_hex"] as? String) ?? "")
            } else {
                continue                                            // TokenPocket: refused before the engine (D-26)
            }
            eq(BILPublicHash.sha256Hex(raw), plan["signingBytesDigest"] as? String ?? "", "\(id): sha256(raw) = signingBytesDigest")
            guard let decoded = BILTronRawData.decode(raw) else { t(false, "\(id): raw decodes"); continue }
            eq(decoded.contracts.count, 1, "\(id): exactly one contract")
            let placeholder = raw.first == 0x5A
            if placeholder {
                eq(decoded.contracts.first?.ownerHex41, nil, "\(id): ownership placeholder has no owner")
                eq(decoded.contracts.first?.type, 0, "\(id): ownership placeholder has no type")
                continue
            }
            guard let contract = decoded.contracts.first, let owner = contract.ownerHex41 else { t(false, "\(id): owner present"); continue }
            t(owner.count == 42 && owner.hasPrefix("41"), "\(id): owner is 41 + 20 bytes")
            let taskAddress = (tasks(plan).first?["addresses"] as? [String])?.first
            if ownerNotSigner.contains(id) {
                t(BILTronAddressCodec.base58(fromHex41: owner) != taskAddress, "\(id): owner is not the signer (policy refusal case)")
            } else {
                eq(BILTronAddressCodec.base58(fromHex41: owner), taskAddress, "\(id): owner = task address")
            }
            let urlName = contract.typeUrl.map { String($0.split(separator: ".").last ?? "") }
            switch contract.type {
            case 1: eq(urlName, "TransferContract", "\(id): TRX transfer type URL")
            case 31: eq(urlName, "TriggerSmartContract", "\(id): TRC-20 type URL")
            default: t(false, "\(id): unexpected contract type \(contract.type)")
            }
            t(!contract.value.isEmpty, "\(id): parameter value present")
            t(decoded.expiration != nil, "\(id): expiration present")
            tronChecked += 1
        }
        t(tronChecked >= 8, "TRON transaction vectors decoded: \(tronChecked)")

        section("tron.raw.edge")
        eq(BILTronRawData.decode([0x0A, 0x7F]), nil, "length beyond the end → nil (TronTransactionVerifierTest)")
        eq(BILTronRawData.decode([]), BILTronRawData(contracts: [], feeLimit: nil, data: nil, expiration: nil), "empty raw → no contracts")
        do {
            let keystone = (try? JSONSerialization.jsonObject(with: fixture("keystone-tron-public.json"))) as? [String: String] ?? [:]
            let raw = hx(keystone["rawDataHex"] ?? "")
            let d = BILTronRawData.decode(raw)
            eq(d?.contracts.count, 1, "Keystone raw: one contract")
            eq(d?.contracts.first?.type, 31, "Keystone raw: TriggerSmartContract")
            eq(d?.contracts.first?.ownerHex41, "41c79f045e4d48ad8dae00e6a6714dae1e000adfcd", "Keystone raw: owner")
            eq(d?.feeLimit, 1_000_000_000, "Keystone raw: fee limit")
        }
        // Hand-built raw data: 1 transfer contract, owner field 1.
        let ownerA = hx("41" + repeatHex("aa", 20))
        let ownerB = hx("41" + repeatHex("bb", 20))
        let transferValue = pbBytes(1, ownerA) + pbBytes(2, ownerB) + pbNum(3, 1_000_000)
        let baseRaw = pbBytes(1, [0x00, 0x01]) + pbBytes(4, hx(repeatHex("00", 8))) + pbNum(8, 1_700_000_000_000) +
            pbBytes(11, contract(type: 1, value: transferValue)) + pbNum(14, 1_699_999_999_000) + pbNum(18, 50_000_000)
        do {
            let d = BILTronRawData.decode(baseRaw)
            eq(d?.contracts.first?.ownerHex41, hexOf(ownerA), "owner = TransferContract field 1")
            eq(d?.contracts.first?.type, 1, "type 1")
            eq(d?.contracts.first?.typeUrl, "type.googleapis.com/protocol.TransferContract", "type URL")
            eq(d?.contracts.first?.permissionId, nil, "no permission id")
            eq(d?.contracts.first?.value, transferValue, "parameter value bytes")
            eq(d?.feeLimit, 50_000_000, "fee limit")
            eq(d?.expiration, 1_700_000_000_000, "expiration")
            eq(d?.data, nil, "no memo")
            let withMemo = BILTronRawData.decode(baseRaw + pbBytes(10, Array("memo".utf8)) + pbNum(77, 5) + pbBytes(78, [1, 2]))
            eq(withMemo?.data, Array("memo".utf8), "memo + unknown fields ignored")
            let asset = BILTronRawData.decode(pbBytes(11, contract(type: 2, value: pbBytes(1, Array("1002000".utf8)) + pbBytes(2, ownerB) + pbBytes(3, ownerA) + pbNum(4, 5))))
            eq(asset?.contracts.first?.ownerHex41, hexOf(ownerB), "TRANSFER_ASSET owner = field 2")
            let permissioned = BILTronRawData.decode(pbBytes(11, contract(type: 31, value: pbBytes(1, ownerA), permission: 2)))
            eq(permissioned?.contracts.first?.permissionId, 2, "permission id read")
            let two = BILTronRawData.decode(baseRaw + pbBytes(11, contract(type: 1, value: transferValue)))
            eq(two?.contracts.count, 2, "two contracts are both read (the verifier refuses)")
            let noOwner = BILTronRawData.decode(pbBytes(11, contract(type: 1, value: pbNum(1, 5))))
            eq(noOwner?.contracts.first?.ownerHex41, nil, "owner as a varint → nil (Android \"\")")
            let fixed = BILTronRawData.decode(pbKey(8, 1) + [1, 0, 0, 0, 0, 0, 0, 0] + pbKey(18, 5) + [2, 0, 0, 0])
            eq(fixed?.expiration, 1, "fixed64 accepted for a varint field")
            eq(fixed?.feeLimit, 2, "fixed32 accepted for a varint field")
            let lastWins = BILTronRawData.decode(pbNum(18, 1) + pbNum(18, 7))
            eq(lastWins?.feeLimit, 7, "last occurrence wins")
            let tenByte = BILTronRawData.decode(pbKey(8, 0) + [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x01])
            eq(tenByte?.expiration, -1, "10-byte varint (all ones) = −1")
            let bom = BILTronRawData.decode(pbBytes(11, contract(type: 1, url: "\u{FEFF}type.googleapis.com/protocol.TransferContract", value: transferValue)))
            eq(bom?.contracts.first?.typeUrl.map { Array($0.utf8.prefix(3)) }, [0xEF, 0xBB, 0xBF], "a BOM in the type URL is kept (T9 vector shape)")
            let lenient = BILTronRawData.decode(pbBytes(11, pbNum(1, 1) + pbBytes(2, pbBytes(1, [0x74, 0xFF, 0x75]) + pbBytes(2, transferValue))))
            eq(lenient?.contracts.first?.typeUrl, "t\u{FFFD}u", "invalid UTF-8 in the type URL is replaced, not refused")
            // Kotlin `(key ushr 3).toInt()`: a field number above 2^32 keeps its low 32 bits (here 11).
            let wide = BILTronRawData.decode(pbVarint((UInt64(1) << 32 | 11) << 3 | 2) + pbVarint(UInt64(contract(type: 1, value: transferValue).count)) +
                                             contract(type: 1, value: transferValue))
            eq(wide?.contracts.count, 1, "field number truncated to 32 bits")
            eq(BILTronRawData.decode(baseRaw + pbNum(0, 1)), nil, "field 0 → nil")
            eq(BILTronRawData.decode(pbKey(5, 3)), nil, "group wire type → nil")
            eq(BILTronRawData.decode(pbKey(5, 6) + [0]), nil, "wire type 6 → nil")
            eq(BILTronRawData.decode(pbNum(1, 5)), nil, "ref_block_bytes as a varint → nil")
            eq(BILTronRawData.decode(pbBytes(8, [1])), nil, "expiration as bytes → nil")
            eq(BILTronRawData.decode(pbNum(11, 1)), nil, "contract as a varint → nil")
            eq(BILTronRawData.decode(pbBytes(11, pbBytes(1, [1]))), nil, "contract type as bytes → nil")
            eq(BILTronRawData.decode(pbBytes(11, pbNum(2, 1))), nil, "contract parameter as a varint → nil")
            eq(BILTronRawData.decode(pbBytes(11, contract(type: 1, value: [0x0A, 0x7F]))), nil, "malformed parameter value → nil")
            eq(BILTronRawData.decode(pbKey(8, 0) + [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x81, 0x01]), nil, "11-byte varint → nil")
            eq(BILTronRawData.decode(pbKey(8, 0) + [0x80]), nil, "truncated varint → nil")
            eq(BILTronRawData.decode(pbKey(8, 1) + [1, 2, 3]), nil, "truncated fixed64 → nil")
            eq(BILTronRawData.decode(pbKey(10, 2) + pbVarint(UInt64.max) + [1]), nil, "length ≥ 2^63 → nil")
            eq(BILTronRawData.decode(pbKey(10, 2) + pbVarint(UInt64(Int64.max)) + [1]), nil, "length 2^63 − 1 → nil")
            // Ownership placeholder of O-TL-V1: {contract: [{ContractName: "TronLinkCustomContract"}]}.
            let proof = BILTronRawData.decode(hx("5a18221654726f6e4c696e6b437573746f6d436f6e7472616374"))
            eq(proof?.contracts.count, 1, "placeholder: one contract")
            eq(proof?.contracts.first, BILTronContract(type: 0, typeUrl: nil, value: [], permissionId: nil, ownerHex41: nil), "placeholder contract is empty")
        }

        // =====================================================================================================================
        // MARK: - Solana header (port of SolanaMessageHeaderTest)
        // =====================================================================================================================

        section("solana.header")
        let ABANDON_SOL = "f036276246a75b9de3349ed42b15e232f6518fc20f5fcd4f1d64e81f9bd258f7"
        do {
            let header = try BILSolanaMessageHeader.parse(solMessage("T8-flow-solana-transfer"))
            eq(header.version, .legacy, "legacy transfer: version")
            eq(header.requiredSignatures, 1, "legacy transfer: 1 signer")
            eq(header.keyCount, 3, "legacy transfer: 3 keys")
            eq(header.keyHex(0), ABANDON_SOL, "legacy transfer: fee payer = our key")
            eq(header.signerSlot(ABANDON_SOL), 0, "our key in slot 0")
            eq(header.signerSlot(ABANDON_SOL.uppercased()), 0, "slot lookup ignores case")
            eq(header.signerSlot(repeatHex("11", 32)), nil, "another key has no slot")
            eq(header.instructions.count, 1, "one instruction")
            eq(header.usesDurableNonce, false, "no durable nonce")
            eq(header.programIds.count, 1, "one program")
            let v0 = try BILSolanaMessageHeader.parse(solMessage("T7-native-solana-transaction-7"))
            eq(v0.version, .v0, "v0 message without lookup tables")
            eq(v0.signerSlot(ABANDON_SOL), 0, "v0: slot 0")
            let two = try BILSolanaMessageHeader.parse(solMessage("T7-native-solana-transaction-8"))
            eq(two.requiredSignatures, 2, "two required signers")
            eq(two.signerSlot(ABANDON_SOL), 1, "our key in slot 1")
            eq(try BILSolanaMessageHeader.parse(solMessage("O-SOL-1-durable-nonce")).usesDurableNonce, true, "durable nonce detected")
            do {
                _ = try BILSolanaMessageHeader.parse(solMessage("O-SOL-2-lookup-table"))
                t(false, "lookup tables refused")
            } catch BILSolanaMessageHeader.ParseError.lookupTables {
                t(true, "lookup tables refused (lookupTables)")
            }
        } catch {
            t(false, "Solana vectors parse (\(error))")
        }
        let solGood = solMessage("T8-flow-solana-transfer")
        t(solParse(solGood) != nil, "good message parses")
        solRefused(solGood + [0], "trailing byte")
        var sm = solGood; sm[0] = 0; solRefused(sm, "no required signer")
        sm = solGood; sm[1] = 1; solRefused(sm, "readonly signed ≥ required")
        sm = solGood; sm[2] = 3; solRefused(sm, "readonly unsigned > keys − required")
        sm = solGood; sm.replaceSubrange(36..<68, with: solGood[4..<36]); solRefused(sm, "duplicate static key")
        let solProgram = 4 + 3 * 32 + 32 + 1
        sm = solGood; sm[solProgram] = 0; solRefused(sm, "program is the required signer")
        sm = solGood; sm[solProgram] = 9; solRefused(sm, "unresolved program")
        sm = solGood; sm[0] = 0x81; solRefused(sm, "version 1")
        solRefused(Array(solGood[0..<3]) + [0x83, 0x00] + Array(solGood[4...]), "non-canonical length")
        solRefused(Array(solGood.dropLast()), "truncated")
        solRefused([UInt8](repeating: 1, count: BILSolanaMessageHeader.maxBytes + 1), "over the packet limit")
        solRefused([], "empty")
        do {
            // shortvec rules: 3 bytes max, third < 4, no terminating zero continuation.
            let keys = 2
            func msg(keyCountBytes: [UInt8]) -> [UInt8] {
                var m: [UInt8] = [0x01, 0x00, 0x01] + keyCountBytes
                for k in 0..<keys { m += [UInt8](repeating: UInt8(k + 1), count: 32) }
                m += [UInt8](repeating: 9, count: 32)            // blockhash
                m += [0x01, 0x01, 0x01, 0x00, 0x00]                // 1 instruction: program 1, 1 account [0], no data
                return m
            }
            t(solParse(msg(keyCountBytes: [0x02])) != nil, "shortvec 02")
            solRefused(msg(keyCountBytes: [0x82, 0x00]), "shortvec 82 00 (zero terminator)")
            solRefused(msg(keyCountBytes: [0x82, 0x80, 0x00]), "shortvec 3 bytes, zero terminator")
            solRefused(msg(keyCountBytes: [0x82, 0x80, 0x84]), "shortvec third byte ≥ 4")
            var v0msg: [UInt8] = [0x80] + msg(keyCountBytes: [0x02]) + [0x00]
            t(solParse(v0msg) != nil, "v0 with 0 lookup tables")
            v0msg[v0msg.count - 1] = 0x01
            do {
                _ = try BILSolanaMessageHeader.parse(v0msg + [0x00])     // lookup count 1 then garbage: LookupTables before trailing
                t(false, "lookup table before trailing check")
            } catch BILSolanaMessageHeader.ParseError.lookupTables {
                t(true, "lookup tables are reported before the trailing-byte check")
            } catch {
                t(false, "lookup table: \(error)")
            }
            // The lookup-table count is a canonical shortvec too: 80 00 (zero terminator) and 80 80 04 (third byte ≥ 4) are
            // malformed, not "no tables" / "tables".
            let v0base: [UInt8] = [0x80] + msg(keyCountBytes: [0x02])
            solRefused(v0base + [0x80, 0x00], "v0 lookup count 80 00")
            solRefused(v0base + [0x80, 0x80, 0x04], "v0 lookup count 80 80 04 (above u16)")
            do {
                _ = try BILSolanaMessageHeader.parse(v0base + [0x80, 0x80, 0x01])
                t(false, "v0 lookup count 16384")
            } catch BILSolanaMessageHeader.ParseError.lookupTables {
                t(true, "v0 lookup count 80 80 01 = 16384 tables → lookupTables")
            } catch {
                t(false, "v0 lookup count 16384: \(error)")
            }
            // Durable nonce needs the System program (32 zero bytes) and data 04 00 00 00.
            var nonce: [UInt8] = [0x01, 0x00, 0x01, 0x02] + [UInt8](repeating: 1, count: 32) + [UInt8](repeating: 0, count: 32)
            nonce += [UInt8](repeating: 9, count: 32) + [0x01, 0x01, 0x01, 0x00, 0x04, 0x04, 0x00, 0x00, 0x00]
            eq(solParse(nonce)?.usesDurableNonce, true, "AdvanceNonceAccount of the System program")
            var notNonce = nonce; notNonce[notNonce.count - 4] = 0x03
            eq(solParse(notNonce)?.usesDurableNonce, false, "other System instruction")
        }

        section("solana.offchain")
        t(BILSolanaMessageHeader.isValidOffchainMessage(Array("Ownbit public protocol fixture".utf8)), "plain text")
        t(BILSolanaMessageHeader.isValidOffchainMessage(Array("签名 ✓ line\nbreak\ttab".utf8)), "UTF-8 with LF and TAB")
        t(BILSolanaMessageHeader.isValidOffchainMessage(Array("a\r\nb".utf8)), "CR LF allowed")
        t(!BILSolanaMessageHeader.isValidOffchainMessage([]), "empty")
        t(BILSolanaMessageHeader.isValidOffchainMessage([UInt8](repeating: 0x61, count: 1024)), "1024 bytes")
        t(!BILSolanaMessageHeader.isValidOffchainMessage([UInt8](repeating: 0x61, count: 1025)), "1025 bytes")
        t(!BILSolanaMessageHeader.isValidOffchainMessage([0x01] + Array("abc".utf8)), "first byte < 0x20")
        t(!BILSolanaMessageHeader.isValidOffchainMessage([0x80, 0x41]), "first byte 0x80")
        t(!BILSolanaMessageHeader.isValidOffchainMessage(Array("abc\u{7}def".utf8)), "BEL")
        t(!BILSolanaMessageHeader.isValidOffchainMessage(Array("abc\u{7F}".utf8)), "DEL")
        t(!BILSolanaMessageHeader.isValidOffchainMessage(Array("abc\u{0B}".utf8)), "VT")
        t(!BILSolanaMessageHeader.isValidOffchainMessage(Array("abc\u{1F}".utf8)), "U+001F")
        t(!BILSolanaMessageHeader.isValidOffchainMessage([0x41, 0xC3, 0x28]), "malformed UTF-8")
        t(!BILSolanaMessageHeader.isValidOffchainMessage([0x41, 0xC0, 0x80]), "overlong NUL")
        t(!BILSolanaMessageHeader.isValidOffchainMessage([0x41, 0xED, 0xA0, 0x80]), "encoded surrogate")
        t(BILSolanaMessageHeader.isValidOffchainMessage(solMessage("T8-flow-solana-message")), "vector message")

        // Solana vector sweep: sign request ↔ request message, digest, header + slot / off-chain rule.
        section("solana.vectors")
        var solChecked = 0
        for id in allCaseIds {
            guard let request = planRequest(id), request["chain"] as? String == "solana",
                  let transport = request["transport"] as? [String: Any], transport["type"] as? String == "sol-sign-request",
                  let payload = transport["payloadBytes"] as? String, let plan = planJson(id), plan["status"] as? String == "ready" else { continue }
            do {
                let cbor = try BILSignatureUrCodec.decodeSignRequest(type: "sol-sign-request", payload: hx(payload))
                eq(cbor.signType, transport["signType"] as? Int, "\(id): CBOR key 6 = transport.signType")
                eq(cbor.dataType, cbor.signType, "\(id): dataType mirrors Android (key 6)")
                eq(cbor.chainId, nil, "\(id): no chain id")
                eq(cbor.requestId.map(hexOf), transport["requestId"] as? String, "\(id): request id")
                eq(hexOf(try BILSignatureUrCodec.base64(request["message"] as? String ?? "")), hexOf(cbor.signData), "\(id): base64(message) = signData")
                eq(BILPublicHash.sha256Hex(cbor.signData), plan["signingBytesDigest"] as? String ?? "", "\(id): sha256 = signingBytesDigest")
                let task = tasks(plan).first ?? [:]
                let key = (task["publicKeys"] as? [String])?.first ?? ""
                if cbor.signType == 1 {
                    let header = try BILSolanaMessageHeader.parse(cbor.signData)
                    let planSlot = ((task["targets"] as? [[String: Any]])?.first?["signerSlot"]) as? Int
                    eq(header.signerSlot(key), planSlot, "\(id): native slot = plan slot")
                } else {
                    t(BILSolanaMessageHeader.isValidOffchainMessage(cbor.signData), "\(id): off-chain message rule")
                }
                solChecked += 1
            } catch {
                t(false, "\(id): Solana request decodes (\(error))")
            }
        }
        t(solChecked >= 4, "Solana UR vectors checked: \(solChecked)")

        // =====================================================================================================================
        // MARK: - Strict CBOR
        // =====================================================================================================================

        section("cbor")
        eq(try BILStrictCbor.decode(hx("a201010202")), BILCbor.map([(.uint(1), .uint(1)), (.uint(2), .uint(2))]), "a201010202")
        refusedWith("cbor.duplicateKey", "duplicate key 1") { _ = try BILStrictCbor.decode(hx("a201010101")) }
        refusedWith("cbor.indefinite", "indefinite byte string") { _ = try BILStrictCbor.decode(hx("5f4101ff")) }
        refusedWith("cbor.trailing", "trailing byte") { _ = try BILStrictCbor.decode(hx("0101")) }
        refusedWith("cbor.integer", "beyond 2^53 − 1") { _ = try BILStrictCbor.decode(hx("1bffffffffffffffff")) }
        eq(try BILStrictCbor.decode(hx("0a")), .uint(10), "0a → 10")
        eq(try BILStrictCbor.decode(hx("1b001fffffffffffff")), .uint(9_007_199_254_740_991), "2^53 − 1 accepted")
        refusedWith("cbor.integer", "2^53") { _ = try BILStrictCbor.decode(hx("1b0020000000000000")) }
        eq(try BILStrictCbor.decode(hx("3b001ffffffffffffe")), .nint(-9_007_199_254_740_991), "−(2^53 − 1)")
        eq(try BILStrictCbor.decode(hx("20")), .nint(-1), "−1")
        eq(try BILStrictCbor.decode(hx("1801")), .uint(1), "non-minimal integer encoding accepted (engine / Android)")
        eq(try BILStrictCbor.decode(hx("f4")), .bool(false), "false"); eq(try BILStrictCbor.decode(hx("f5")), .bool(true), "true")
        eq(try BILStrictCbor.decode(hx("f6")), .null, "null")
        refusedWith("cbor.simple", "undefined f7") { _ = try BILStrictCbor.decode(hx("f7")) }
        refusedWith("cbor.simple", "half float") { _ = try BILStrictCbor.decode(hx("f93c00")) }
        refusedWith("cbor.simple", "simple(16)") { _ = try BILStrictCbor.decode(hx("f0")) }
        refusedWith("cbor.indefinite", "break byte") { _ = try BILStrictCbor.decode(hx("ff")) }
        refusedWith("cbor.indefinite", "info 28") { _ = try BILStrictCbor.decode(hx("1c")) }
        refusedWith("cbor.indefinite", "indefinite map") { _ = try BILStrictCbor.decode(hx("bf")) }
        eq(try BILStrictCbor.decode(hx("6461626364")), .text("abcd"), "text")
        refusedWith("cbor.utf8", "invalid UTF-8 text") { _ = try BILStrictCbor.decode(hx("62c328")) }
        refusedWith("cbor.utf8", "overlong UTF-8 text") { _ = try BILStrictCbor.decode(hx("62c080")) }
        eq(try BILStrictCbor.decode(hx("d82550" + repeatHex("11", 16))), .tag(37, .bytes(hx(repeatHex("11", 16)))), "tag 37 bytes")
        eq(try BILStrictCbor.decode(hx("83010203")), .array([.uint(1), .uint(2), .uint(3)]), "array")
        eq(try BILStrictCbor.decode(hx("a2616101616202")), .map([(.text("a"), .uint(1)), (.text("b"), .uint(2))]), "text keys")
        refusedWith("cbor.duplicateKey", "duplicate text key") { _ = try BILStrictCbor.decode(hx("a2616101616102")) }
        refusedWith("cbor.mapKey", "byte-string key") { _ = try BILStrictCbor.decode(hx("a1410101")) }
        refusedWith("cbor.mapKey", "array key") { _ = try BILStrictCbor.decode(hx("a18001")) }
        eq(try BILStrictCbor.decode(hx("a220010102")).mapPairs?.count, 2, "−1 and 1 are distinct keys")
        // Text keys are compared exactly: precomposed é and e + U+0301 are distinct keys (Swift == would merge them).
        eq(try BILStrictCbor.decode(cbor(.m([(.t("\u{E9}"), .u(1)), (.t("e\u{301}"), .u(2))]))).mapPairs?.count, 2, "canonically-equivalent text keys stay distinct")
        t(BILCbor.text("\u{E9}") != BILCbor.text("e\u{301}"), "BILCbor text equality is exact")
        refusedWith("cbor.truncated", "truncated byte string") { _ = try BILStrictCbor.decode(hx("4401")) }
        refusedWith("cbor.truncated", "truncated length") { _ = try BILStrictCbor.decode(hx("19ff")) }
        refusedWith("cbor.truncated", "empty input") { _ = try BILStrictCbor.decode([]) }
        refusedWith("cbor.array", "array length 20 001") { _ = try BILStrictCbor.decode(hx("994e21")) }
        refusedWith("cbor.map", "map length 10 001") { _ = try BILStrictCbor.decode(hx("b92711")) }
        do {
            var nested: [UInt8] = [0x00]
            for _ in 0..<24 { nested = [0x81] + nested }
            t((try? BILStrictCbor.decode(nested)) != nil, "depth 24 accepted")
            refusedWith("cbor.complexity", "depth 25 refused") { _ = try BILStrictCbor.decode([0x81] + nested) }
            var tags: [UInt8] = [0x00]
            for _ in 0..<25 { tags = [0xC1] + tags }
            refusedWith("cbor.complexity", "tags count as depth") { _ = try BILStrictCbor.decode(tags) }
            let many = [0x99, 0x4E, 0x1F] + [UInt8](repeating: 0x00, count: 19_999)            // array of 19 999 + itself = 20 000 nodes
            t((try? BILStrictCbor.decode(many)) != nil, "20 000 nodes accepted")
            let tooMany = [0x82, 0x99, 0x4E, 0x1F] + [UInt8](repeating: 0x00, count: 19_999) + [0x00]
            refusedWith("cbor.complexity", "20 002 nodes refused") { _ = try BILStrictCbor.decode(tooMany) }
        }
        eq(BILCbor.map([(.uint(1), .null), (.uint(2), .uint(5))]).get(1), nil, "get: a null value reads as absent (Kotlin map[k])")
        eq(BILCbor.map([(.uint(1), .null), (.uint(2), .uint(5))]).get(2), .uint(5), "get: present value")
        eq(BILCbor.map([(.nint(-3), .uint(7))]).get(-3), .uint(7), "get: negative key")
        eq(BILCbor.uint(3).get(1), nil, "get on a non-map")
        t(!"\(BILCbor.bytes([0xDE, 0xAD]))".contains("dead") && !"\(BILCbor.text("secret"))".contains("secret"), "BILCbor description has no content")

        // =====================================================================================================================
        // MARK: - UR, bytewords, signatures, PSBT answers (port of SignatureUrCodecTest)
        // =====================================================================================================================

        section("ur.bytewords")
        do {
            let all = (0..<256).map { UInt8($0) }
            eq(try BILSignatureUrCodec.bytewords(bytewordsOf(all)), all, "every byte round-trips through minimal bytewords")
            eq(try BILSignatureUrCodec.bytewords(bytewordsOf(all).uppercased()), all, "upper case")
            eq(try BILSignatureUrCodec.bytewords(bytewordsOf([0x42])), [0x42], "shortest (1 byte + CRC)")
            refusedWith("bytewords.length", "odd length") { _ = try BILSignatureUrCodec.bytewords(String(bytewordsOf([1, 2]).dropLast())) }
            refusedWith("bytewords.length", "8 letters (CRC only)") { _ = try BILSignatureUrCodec.bytewords(bytewordsOf([])) }
            let good = bytewordsOf([1, 2, 3])
            refusedWith("bytewords.checksum", "CRC mismatch") {
                let u = Array(good.utf8); var v = u; v[1] = u[1] == 0x65 ? 0x64 : 0x65         // ae (able=0x00) ↔ ad
                _ = try BILSignatureUrCodec.bytewords(String(decoding: v, as: UTF8.self))
            }
            refusedWith("bytewords.word", "no word is z…z") { _ = try BILSignatureUrCodec.bytewords("zz" + String(good.dropFirst(2))) }
            t(bytewordsOf([4]).hasPrefix("aa") && (try? BILSignatureUrCodec.bytewords(bytewordsOf([4]))) == [4], "aqua = aa = 0x04")
            refusedWith("bytewords.char", "a digit") { _ = try BILSignatureUrCodec.bytewords("a1" + String(good.dropFirst(2))) }
            refusedWith("bytewords.char", "non-ASCII letter") { _ = try BILSignatureUrCodec.bytewords("\u{E9}e" + String(good.dropFirst(2))) }
        }

        section("ur.frames")
        do {
            let msg = cbor(.m([(.u(2), .b([UInt8](repeating: 7, count: 65)))]))
            let single = singleUr("eth-signature", msg)
            eq(try BILSignatureUrCodec.decodeUr([single]).cbor, msg, "single part")
            eq(try BILSignatureUrCodec.decodeUr([single]).type, "eth-signature", "type lower-cased")
            eq(try BILSignatureUrCodec.decodeUr([single.lowercased()]).cbor, msg, "lower-case frame")
            eq(try BILSignatureUrCodec.decodeUr(["  \n" + single + "\u{2003}\u{1C}"]).cbor, msg, "Kotlin trim (incl. U+2003, U+001C)")
            refusedWith("ur.frame", "U+0085 is not Kotlin whitespace") { _ = try BILSignatureUrCodec.decodeUr([single + "\u{85}"]) }
            refusedWith("ur.frame", "trailing slash") { _ = try BILSignatureUrCodec.decodeUr([single + "/"]) }
            refusedWith("ur.frame", "digit in the body") { _ = try BILSignatureUrCodec.decodeUr([single + "1"]) }
            refusedWith("ur.frame", "no type") { _ = try BILSignatureUrCodec.decodeUr(["ur:/" + bytewordsOf(msg)]) }
            refusedWith("ur.frame", "type of 65 characters") { _ = try BILSignatureUrCodec.decodeUr(["ur:" + String(repeating: "a", count: 65) + "/" + bytewordsOf(msg)]) }
            eq(try BILSignatureUrCodec.decodeUr(["ur:" + String(repeating: "a", count: 64) + "/" + bytewordsOf(msg)]).type.count, 64, "type of 64 characters")
            refusedWith("ur.frame", "non-ASCII type") { _ = try BILSignatureUrCodec.decodeUr(["ur:\u{E9}th/" + bytewordsOf(msg)]) }
            refusedWith("ur.frame", "not a UR") { _ = try BILSignatureUrCodec.decodeUr(["ux:eth/" + bytewordsOf(msg)]) }
            refusedWith("ur.frames", "no frames") { _ = try BILSignatureUrCodec.decodeUr([]) }
            refusedWith("ur.frames", "2049 frames") { _ = try BILSignatureUrCodec.decodeUr([String](repeating: single, count: 2049)) }
            refusedWith("ur.single", "two single-part frames") { _ = try BILSignatureUrCodec.decodeUr([single, single]) }
            refusedWith("ur.type", "two types") { _ = try BILSignatureUrCodec.decodeUr([single, singleUr("sol-signature", msg)]) }

            let message = [UInt8]((0..<300).map { UInt8($0 & 0xFF) })
            let parts = multiUr("crypto-psbt", message, fragLen: 64)
            eq(parts.count, 5, "5 fragments")
            eq(try BILSignatureUrCodec.decodeUr(parts).cbor, message, "multi-part in order")
            eq(try BILSignatureUrCodec.decodeUr(parts.reversed() + [parts[2]]).cbor, message, "any order, identical repeat")
            refusedWith("ur.incomplete", "a fragment missing") { _ = try BILSignatureUrCodec.decodeUr(Array(parts.dropLast())) }
            refusedWith("ur.parts", "a single part among fragments") { _ = try BILSignatureUrCodec.decodeUr(parts + [singleUr("crypto-psbt", message)]) }
            refusedWith("ur.mixedPart", "seq > count") { _ = try BILSignatureUrCodec.decodeUr([parts[0].replacingOccurrences(of: "/1-5/", with: "/6-5/")]) }
            refusedWith("ur.sequence", "seq 0") { _ = try BILSignatureUrCodec.decodeUr([parts[0].replacingOccurrences(of: "/1-5/", with: "/0-5/")]) }
            refusedWith("ur.sequence", "count 2049") { _ = try BILSignatureUrCodec.decodeUr([parts[0].replacingOccurrences(of: "/1-5/", with: "/1-2049/")]) }
            refusedWith("ur.frame", "11-digit seq") { _ = try BILSignatureUrCodec.decodeUr([parts[0].replacingOccurrences(of: "/1-5/", with: "/00000000001-5/")]) }
            eq(try BILSignatureUrCodec.decodeUr([parts[0].replacingOccurrences(of: "/1-5/", with: "/0000000001-5/")] + Array(parts[1...])).cbor, message,
               "10-digit seq with leading zeros")
            refusedWith("ur.count", "frames disagree on the count") { _ = try BILSignatureUrCodec.decodeUr([parts[0], parts[1].replacingOccurrences(of: "/2-5/", with: "/2-6/")]) }
            refusedWith("ur.part.seq", "CBOR seq differs from the frame") { _ = try BILSignatureUrCodec.decodeUr([parts[0].replacingOccurrences(of: "/1-5/", with: "/2-5/")]) }
            let otherCrc = multiUr("crypto-psbt", message, fragLen: 64, crcOverride: 1)
            refusedWith("ur.part.mixed", "parts of two checksums") { _ = try BILSignatureUrCodec.decodeUr([parts[0], otherCrc[1]]) }
            refusedWith("ur.checksum", "wrong message checksum") { _ = try BILSignatureUrCodec.decodeUr(otherCrc) }
            var altered = message; altered[3] ^= 1
            let conflicting = multiUr("crypto-psbt", altered, fragLen: 64, crcOverride: UInt64(BILPublicHash.crc32(message)))
            refusedWith("ur.part.conflict", "a repeated seq with another fragment") { _ = try BILSignatureUrCodec.decodeUr(parts + [conflicting[0]]) }
            let shortFrag = "ur:crypto-psbt/1-2/" + bytewordsOf(cbor(.a([.u(1), .u(2), .u(70), .u(UInt64(BILPublicHash.crc32(Array(message[0..<70])))), .b(Array(message[0..<64]))])))
            let shortFrag2 = "ur:crypto-psbt/2-2/" + bytewordsOf(cbor(.a([.u(2), .u(2), .u(70), .u(UInt64(BILPublicHash.crc32(Array(message[0..<70])))), .b(Array(message[64..<70]))])))
            refusedWith("ur.part.size", "unequal fragment sizes") { _ = try BILSignatureUrCodec.decodeUr([shortFrag, shortFrag2]) }
            let tooMany = "ur:crypto-psbt/1-3/" + bytewordsOf(cbor(.a([.u(1), .u(3), .u(10), .u(0), .b([UInt8](repeating: 1, count: 10))])))
            let tooMany2 = "ur:crypto-psbt/2-3/" + bytewordsOf(cbor(.a([.u(2), .u(3), .u(10), .u(0), .b([UInt8](repeating: 1, count: 10))])))
            let tooMany3 = "ur:crypto-psbt/3-3/" + bytewordsOf(cbor(.a([.u(3), .u(3), .u(10), .u(0), .b([UInt8](repeating: 1, count: 10))])))
            refusedWith("ur.part.size", "more fragments than the length needs") { _ = try BILSignatureUrCodec.decodeUr([tooMany, tooMany2, tooMany3]) }
            let notArray = "ur:crypto-psbt/1-1/" + bytewordsOf(cbor(.m([(.u(1), .u(1))])))
            refusedWith("ur.part", "a part that is not a CBOR array") { _ = try BILSignatureUrCodec.decodeUr([notArray]) }
            let fourItems = "ur:crypto-psbt/1-1/" + bytewordsOf(cbor(.a([.u(1), .u(1), .u(1), .u(0)])))
            refusedWith("ur.part", "a part of 4 items") { _ = try BILSignatureUrCodec.decodeUr([fourItems]) }
            let zeroLen = "ur:crypto-psbt/1-1/" + bytewordsOf(cbor(.a([.u(1), .u(1), .u(0), .u(0), .b([1])])))
            refusedWith("ur.part.meta", "message length 0") { _ = try BILSignatureUrCodec.decodeUr([zeroLen]) }
            let negCrc = "ur:crypto-psbt/1-1/" + bytewordsOf(cbor(.a([.u(1), .u(1), .u(1), .n(-1), .b([1])])))
            refusedWith("ur.part.meta", "negative checksum") { _ = try BILSignatureUrCodec.decodeUr([negCrc]) }
            let emptyFrag = "ur:crypto-psbt/1-1/" + bytewordsOf(cbor(.a([.u(1), .u(1), .u(1), .u(0), .b([])])))
            refusedWith("ur.part.fragment", "empty fragment") { _ = try BILSignatureUrCodec.decodeUr([emptyFrag]) }
            refusedWith("ur.size", "single part above 131 072 bytes") {
                _ = try BILSignatureUrCodec.decodeUr([singleUr("bytes", [UInt8](repeating: 0x41, count: 131_073))])
            }
            eq(try BILSignatureUrCodec.decodeUr([singleUr("bytes", [UInt8](repeating: 0x41, count: 131_072))]).cbor.count, 131_072, "single part of 131 072 bytes")
        }

        section("ur.signatures.vectors")
        let signatureFlows = answeredFlows.filter { (encoded($0)?["type"] as? String ?? "").hasSuffix("-signature") }
        let psbtFlows = answeredFlows.filter { !(encoded($0)?["type"] as? String ?? "").hasSuffix("-signature") }
        t(signatureFlows.count >= 20, "signature answer flows: \(signatureFlows.count) (≥ 20)")
        for id in signatureFlows {
            do {
                let e = encoded(id) ?? [:]
                let answer = try BILSignatureUrCodec.decodeSignature(frames(id))
                eq(answer.type, e["type"] as? String ?? "", "\(id): type")
                let payload = e["payload"] as? [String: Any] ?? [:]
                eq(hexOf(answer.signature), payload["signature"] as? String ?? "", "\(id): signature = engine payload")
                eq(answer.requestId.map(hexOf), (payload["request-id"] as? [String: Any])?["uuid"] as? String, "\(id): request id = engine payload")
                eq(answer.requestId.map(hexOf), (scannedRequest(id)?["transport"] as? [String: Any])?["requestId"] as? String, "\(id): request id = transport")
            } catch {
                t(false, "\(id): signature answer decodes (\(error))")
            }
        }
        do {
            let answer = try BILSignatureUrCodec.decodeSignature(frames("O-RESP-1-imtoken-36-byte-id"))
            eq(answer.requestId?.count, 36, "imToken 36-byte request id echoed")
            let transportId = (scannedRequest("O-RESP-1-imtoken-36-byte-id")?["transport"] as? [String: Any])?["requestId"] as? String
            eq(answer.requestId.map(hexOf), transportId, "imToken id byte for byte")
            eq(transportId?.count, 72, "72 hex characters")
            // C-EVM-9 basis: the original request CBOR carries the same 36 bytes.
            let transport = scannedRequest("O-RESP-1-imtoken-36-byte-id")?["transport"] as? [String: Any]
            let request = try BILSignatureUrCodec.decodeSignRequest(type: transport?["type"] as? String ?? "", payload: hx(transport?["payloadBytes"] as? String ?? ""))
            eq(request.requestId.map(hexOf), transportId, "imToken request CBOR id = transport id (36 bytes)")
            eq(try BILSignatureUrCodec.decodeSignature(frames("T8-flow-evm-personal-without-request-id")).requestId, nil, "no request id → no key 1")
        } catch {
            t(false, "O-RESP-1 / no-id vectors (\(error))")
        }
        do {
            let animated = frames("T8-flow-evm-eip1559-animated-response")
            eq(animated.count, 3, "animated eth-signature: 3 frames")
            let inOrder = try BILSignatureUrCodec.decodeSignature(animated)
            let shuffled = try BILSignatureUrCodec.decodeSignature([animated[2], animated[0], animated[1], animated[0]])
            eq(inOrder.signature, shuffled.signature, "any order + a repeat")
            eq(hexOf(inOrder.signature), (encoded("T8-flow-evm-eip1559-animated-response")?["payload"] as? [String: Any])?["signature"] as? String ?? "",
               "animated signature = engine payload")
            refused("two of three frames") { _ = try BILSignatureUrCodec.decodeSignature(Array(animated.prefix(2))) }
            refusedWith("ur.mixedPart", "mixed fountain part /4-3/") {
                _ = try BILSignatureUrCodec.decodeUr([animated[0].replacingOccurrences(of: "/1-3/", with: "/4-3/")])
            }
        } catch {
            t(false, "animated answer (\(error))")
        }
        do {
            let keystone = (try? JSONSerialization.jsonObject(with: fixture("keystone-tron-public.json"))) as? [String: String] ?? [:]
            let answer = try BILSignatureUrCodec.decodeSignature([keystone["signatureUR"] ?? ""])
            eq(answer.type, "tron-signature", "Keystone TRON signature type")
            eq(answer.requestId.map(hexOf), keystone["requestId"], "Keystone request id")
            eq(hexOf(answer.signature), keystone["signatureHex"] ?? "", "Keystone signature")
            let ur = try BILSignatureUrCodec.decodeUr([keystone["requestUR"] ?? ""])
            eq(ur.type, "tron-sign-request", "Keystone request UR type")
            let request = try BILSignatureUrCodec.decodeSignRequest(type: ur.type, payload: ur.cbor)
            eq(hexOf(request.signData), keystone["rawDataHex"] ?? "", "Keystone request signData = raw data")
            eq(request.requestId.map(hexOf), keystone["requestId"], "Keystone request id in the request")
            eq(request.dataType, 1, "Keystone request dataType 1")
        } catch {
            t(false, "Keystone fixture (\(error))")
        }

        section("ur.signatures.refused")
        do {
            let id = "8f235e99e6e84044a51d51ec3ec942b0"
            let sig = [UInt8](repeating: 1, count: 65)
            eq(try BILSignatureUrCodec.decodeSignature([signatureUr("eth-signature", id, sig)]).signature, sig, "test signature UR decodes")
            eq(try BILSignatureUrCodec.decodeSignature([signatureUr("eth-signature", id, sig)]).requestId.map(hexOf), id, "test request id")
            refusedWith("signature.keys", "an extra key 3 (origin)") { _ = try BILSignatureUrCodec.decodeSignature([signatureUr("eth-signature", id, sig, extra: [(.u(3), .t("dapp"))])]) }
            refusedWith("signature.keys", "a negative key") { _ = try BILSignatureUrCodec.decodeSignature([signatureUr("eth-signature", id, sig, extra: [(.n(-1), .u(0))])]) }
            refusedWith("signature.keys", "a text key") { _ = try BILSignatureUrCodec.decodeSignature([signatureUr("eth-signature", id, sig, extra: [(.t("1"), .u(0))])]) }
            let noSig = singleUr("eth-signature", cbor(.m([(.u(1), .tag(37, .b(hx(id))))])))
            refusedWith("signature.value", "no signature") { _ = try BILSignatureUrCodec.decodeSignature([noSig]) }
            let textSig = singleUr("eth-signature", cbor(.m([(.u(2), .t("sig"))])))
            refusedWith("signature.value", "signature as text") { _ = try BILSignatureUrCodec.decodeSignature([textSig]) }
            let wrongTag = singleUr("eth-signature", cbor(.m([(.u(1), .tag(38, .b(hx(id)))), (.u(2), .b(sig))])))
            refusedWith("signature.requestId.tag", "request id under tag 38") { _ = try BILSignatureUrCodec.decodeSignature([wrongTag]) }
            let untagged = singleUr("eth-signature", cbor(.m([(.u(1), .b(hx(id))), (.u(2), .b(sig))])))
            refusedWith("signature.requestId", "untagged request id") { _ = try BILSignatureUrCodec.decodeSignature([untagged]) }
            let tagText = singleUr("eth-signature", cbor(.m([(.u(1), .tag(37, .t(id))), (.u(2), .b(sig))])))
            refusedWith("signature.requestId", "tag 37 around text") { _ = try BILSignatureUrCodec.decodeSignature([tagText]) }
            let nullId = singleUr("eth-signature", cbor(.m([(.u(1), .null), (.u(2), .b(sig))])))
            eq(try BILSignatureUrCodec.decodeSignature([nullId]).requestId, nil, "key 1 = null reads as no request id (Kotlin map get)")
            refusedWith("signature.type", "not a signature type") { _ = try BILSignatureUrCodec.decodeSignature([signatureUr("crypto-hdkey", id, sig)]) }
            refusedWith("signature.map", "not a map") { _ = try BILSignatureUrCodec.decodeSignature([singleUr("eth-signature", cbor(.b(sig)))]) }
            let good = signatureUr("eth-signature", id, sig)
            let gu = Array(good.utf16)
            var flipped = gu; flipped[gu.count - 12] = gu[gu.count - 12] == 0x41 ? 0x42 : 0x41
            refused("one bytewords letter changed: the CRC fails") { _ = try BILSignatureUrCodec.decodeSignature([String(decoding: flipped, as: UTF16.self)]) }
            refusedWith("ur.single", "two single-part frames") { _ = try BILSignatureUrCodec.decodeSignature([good, good]) }
            eq(try BILSignatureUrCodec.decodeSignature([signatureUr("sol-signature", nil, [UInt8](repeating: 2, count: 64))]).requestId, nil, "sol-signature without id")
        }

        section("ur.signRequest")
        do {
            let id = hx("9b1deb4d3b7d4bad9bdd2b0d7b3dcb6d")
            let signData = hx("0a0207902208")
            let eth = cbor(.m([(.u(1), .tag(37, .b(id))), (.u(2), .b(signData)), (.u(3), .u(4)), (.u(4), .u(1)), (.u(5), .tag(304, .m([]))), (.u(7), .t("x"))]))
            let r = try BILSignatureUrCodec.decodeSignRequest(type: "eth-sign-request", payload: eth)
            eq(r, BILSignatureUrCodec.SignRequest(requestId: id, signData: signData, dataType: 4, chainId: 1, signType: nil), "eth sign request")
            refusedWith("request.keys", "tron sign request with key 7") { _ = try BILSignatureUrCodec.decodeSignRequest(type: "tron-sign-request", payload: eth) }
            let anyTag = cbor(.m([(.u(1), .tag(99, .b(id))), (.u(2), .b(signData))]))
            eq(try BILSignatureUrCodec.decodeSignRequest(type: "tron-sign-request", payload: anyTag).requestId, id, "request id under any tag (Android)")
            let untaggedId = cbor(.m([(.u(1), .b(id)), (.u(2), .b(signData))]))
            eq(try BILSignatureUrCodec.decodeSignRequest(type: "tron-sign-request", payload: untaggedId).requestId, nil, "untagged key 1 → no request id")
            let negChain = cbor(.m([(.u(2), .b(signData)), (.u(3), .u(1)), (.u(4), .n(-5))]))
            eq(try BILSignatureUrCodec.decodeSignRequest(type: "eth-sign-request", payload: negChain).chainId, -5, "chain id as a Kotlin Long (negative kept)")
            let textType = cbor(.m([(.u(2), .b(signData)), (.u(3), .t("1"))]))
            eq(try BILSignatureUrCodec.decodeSignRequest(type: "eth-sign-request", payload: textType).dataType, nil, "dataType as text → nil")
            let sol = cbor(.m([(.u(2), .b(signData)), (.u(3), .u(9)), (.u(6), .u(2))]))
            let s = try BILSignatureUrCodec.decodeSignRequest(type: "sol-sign-request", payload: sol)
            eq(s.signType, 2, "Solana signType = key 6"); eq(s.dataType, 2, "Solana dataType = key 6 (Android)"); eq(s.chainId, nil, "Solana: no chain id")
            refusedWith("request.signData", "no sign data") { _ = try BILSignatureUrCodec.decodeSignRequest(type: "eth-sign-request", payload: cbor(.m([(.u(1), .tag(37, .b(id)))]))) }
            refusedWith("request.signData", "sign data null") { _ = try BILSignatureUrCodec.decodeSignRequest(type: "eth-sign-request", payload: cbor(.m([(.u(2), .null)]))) }
            refusedWith("request.keys", "key 0") { _ = try BILSignatureUrCodec.decodeSignRequest(type: "eth-sign-request", payload: cbor(.m([(.u(0), .u(1)), (.u(2), .b(signData))]))) }
            refusedWith("request.keys", "text key") { _ = try BILSignatureUrCodec.decodeSignRequest(type: "eth-sign-request", payload: cbor(.m([(.t("a"), .u(1)), (.u(2), .b(signData))]))) }
            refusedWith("request.map", "not a map") { _ = try BILSignatureUrCodec.decodeSignRequest(type: "eth-sign-request", payload: cbor(.b(signData))) }
            refusedWith("request.type", "unknown request type") { _ = try BILSignatureUrCodec.decodeSignRequest(type: "btc-sign-request", payload: cbor(.m([(.u(2), .b(signData))]))) }
            refusedWith("request.type", "type compared exactly (Kelvin sign)") {
                _ = try BILSignatureUrCodec.decodeSignRequest(type: "tron-sign-request\u{212A}", payload: cbor(.m([(.u(2), .b(signData))])))
            }
            refusedWith("cbor.trailing", "trailing byte after the map") { _ = try BILSignatureUrCodec.decodeSignRequest(type: "eth-sign-request", payload: cbor(.m([(.u(2), .b(signData))])) + [0]) }
        }
        // Every CBOR transport of the vectors: the native read of the original bytes equals the engine's request.
        var signRequestChecked = 0
        for id in allCaseIds {
            guard let request = planRequest(id), let transport = request["transport"] as? [String: Any],
                  transport["payloadEncoding"] as? String == "cbor", let type = transport["type"] as? String, type.hasSuffix("-sign-request"),
                  let payload = transport["payloadBytes"] as? String else { continue }
            do {
                let r = try BILSignatureUrCodec.decodeSignRequest(type: type, payload: hx(payload))
                eq(r.requestId.map(hexOf), transport["requestId"] as? String, "\(id): request id = transport.requestId")
                if type == "tron-sign-request" { eq(r.dataType, transport["dataType"] as? Int, "\(id): TRON dataType") }
                signRequestChecked += 1
            } catch {
                t(false, "\(id): sign request decodes (\(error))")
            }
        }
        t(signRequestChecked >= 30, "vector sign requests decoded: \(signRequestChecked)")

        section("ur.psbt")
        t(psbtFlows.count >= 15, "PSBT answer flows: \(psbtFlows.count) (≥ 15)")
        var psbtTypes = Set<String>()
        for id in psbtFlows {
            do {
                let e = encoded(id) ?? [:]
                let type = e["type"] as? String ?? ""
                psbtTypes.insert(type)
                let bytes = try BILSignatureUrCodec.decodePsbt(type: type, frames: frames(id))
                eq(BILBase64Strict.encode(bytes), (e["payload"] as? [String: Any])?["psbt_base64"] as? String ?? "", "\(id): \(type) answer = engine psbt_base64")
                eq(hexOf(bytes), hexOf(b64(signResults(id).last?["psbt"] as? String)), "\(id): answer = the last signPlanTask psbt")
            } catch {
                t(false, "\(id): PSBT answer decodes (\(error))")
            }
        }
        eq(psbtTypes, ["crypto-psbt", "psbt", "bbqr-psbt", "psbt-base64", "psbt-hex"], "every PSBT answer type covered")
        do {
            let bbqr = frames("T8-flow-bitcoin-bbqr-base32")
            t(bbqr.count > 1, "BBQr base32 answer has several parts")
            refusedWith("bbqr.incomplete", "BBQr: a part missing") { _ = try BILSignatureUrCodec.decodePsbt(type: "bbqr-psbt", frames: Array(bbqr.dropFirst())) }
            refusedWith("bbqr.header", "BBQr: a part of another header") {
                _ = try BILSignatureUrCodec.decodePsbt(type: "bbqr-psbt", frames: bbqr + [bbqr[0].replacingOccurrences(of: "B$2P", with: "B$HP")])
            }
            let bbqrBytes = try BILSignatureUrCodec.decodePsbt(type: "bbqr-psbt", frames: bbqr)
            eq(try BILSignatureUrCodec.decodePsbt(type: "bbqr-psbt", frames: bbqr.reversed()), bbqrBytes, "BBQr any order")
            eq(try BILSignatureUrCodec.decodePsbt(type: "bbqr-psbt", frames: bbqr + [bbqr[1]]), bbqrBytes, "BBQr identical repeat")
            let changed = String(bbqr[1].dropLast()) + (bbqr[1].hasSuffix("A") ? "B" : "A")
            refusedWith("bbqr.conflict", "BBQr: repeated index with other data") { _ = try BILSignatureUrCodec.decodePsbt(type: "bbqr-psbt", frames: bbqr + [changed]) }
            refusedWith("bbqr.frame", "BBQr: lower case") { _ = try BILSignatureUrCodec.decodePsbt(type: "bbqr-psbt", frames: [bbqr[0].lowercased()]) }
            refusedWith("bbqr.frame", "BBQr: file type T") { _ = try BILSignatureUrCodec.decodePsbt(type: "bbqr-psbt", frames: [bbqr[0].replacingOccurrences(of: "B$2P", with: "B$2T")]) }
            refusedWith("bbqr.frame", "BBQr: encoding Z") { _ = try BILSignatureUrCodec.decodePsbt(type: "bbqr-psbt", frames: [bbqr[0].replacingOccurrences(of: "B$2P", with: "B$ZP")]) }
            refusedWith("bbqr.frame", "BBQr: header only") { _ = try BILSignatureUrCodec.decodePsbt(type: "bbqr-psbt", frames: [String(bbqr[0].prefix(8))]) }
            refusedWith("bbqr.frame", "BBQr: trailing newline (not trimmed)") { _ = try BILSignatureUrCodec.decodePsbt(type: "bbqr-psbt", frames: [bbqr[0] + "\n"]) }
            refusedWith("bbqr.index", "BBQr: index ≥ total") { _ = try BILSignatureUrCodec.decodePsbt(type: "bbqr-psbt", frames: ["B$2P0101" + "AAAA"]) }
            refusedWith("bbqr.index", "BBQr: total 0") { _ = try BILSignatureUrCodec.decodePsbt(type: "bbqr-psbt", frames: ["B$2P0000" + "AAAA"]) }
            refusedWith("bbqr.frames", "BBQr: no frames") { _ = try BILSignatureUrCodec.decodePsbt(type: "bbqr-psbt", frames: []) }
            let hexFrames = frames("T8-flow-bitcoin-bbqr-hex")
            t(hexFrames.first?.hasPrefix("B$HP") == true, "BBQr hex answer")
            refusedWith("bbqr.hex", "BBQr H: odd hex") { _ = try BILSignatureUrCodec.decodePsbt(type: "bbqr-psbt", frames: ["B$HP0100" + "70736274FF0"]) }
            refusedWith("bbqr.hex", "BBQr H: non-hex letter") { _ = try BILSignatureUrCodec.decodePsbt(type: "bbqr-psbt", frames: ["B$HP0100" + "70736274FG"]) }
            eq(try BILSignatureUrCodec.decodePsbt(type: "bbqr-psbt", frames: ["B$HP0100" + "70736274FF00"]), hx("70736274ff00"), "BBQr H minimal")
            refusedWith("base32.padding", "Base32 \"AB\"") { _ = try BILSignatureUrCodec.base32("AB") }
            refusedWith("base32.char", "Base32 lower case") { _ = try BILSignatureUrCodec.base32("ab") }
            refusedWith("base32.char", "Base32 digit 8") { _ = try BILSignatureUrCodec.base32("A8") }
            eq(try BILSignatureUrCodec.base32("MZXW6YTBOI"), Array("foobar".utf8), "Base32 RFC 4648 vector")
            eq(try BILSignatureUrCodec.base32("MY"), Array("f".utf8), "Base32 one byte")
            eq(try BILSignatureUrCodec.base32(""), [], "Base32 empty")
            refusedWith("base32.padding", "Base32 5 leftover bits") { _ = try BILSignatureUrCodec.base32("MZXW6YTBOIA") }
            refusedWith("base64", "Base64 \"cHNidP8\"") { _ = try BILSignatureUrCodec.base64("cHNidP8") }
            eq(try BILSignatureUrCodec.base64("cHNidP8="), hx("70736274ff"), "Base64 padded")
            refusedWith("psbt.frames", "psbt-base64 with two frames") { _ = try BILSignatureUrCodec.decodePsbt(type: "psbt-base64", frames: ["cHNidP8A", "cHNidP8A"]) }
            refusedWith("psbt.hex", "psbt-hex with 0x") { _ = try BILSignatureUrCodec.decodePsbt(type: "psbt-hex", frames: ["0x70736274ff00"]) }
            refusedWith("psbt.magic", "psbt-hex without the magic") { _ = try BILSignatureUrCodec.decodePsbt(type: "psbt-hex", frames: ["70736274fe00"]) }
            refusedWith("psbt.magic", "4 bytes") { _ = try BILSignatureUrCodec.decodePsbt(type: "psbt-hex", frames: ["70736274"]) }
            refusedWith("psbt.type", "unknown PSBT transport") { _ = try BILSignatureUrCodec.decodePsbt(type: "bbqr-zlib", frames: ["x"]) }
            let psbtUr = singleUr("crypto-psbt", cbor(.b(hx("70736274ff00"))))
            eq(try BILSignatureUrCodec.decodePsbt(type: "crypto-psbt", frames: [psbtUr]), hx("70736274ff00"), "crypto-psbt UR")
            refusedWith("psbt.urType", "crypto-psbt frames under the psbt transport") { _ = try BILSignatureUrCodec.decodePsbt(type: "psbt", frames: [psbtUr]) }
            refusedWith("psbt.cbor", "a UR holding an array") { _ = try BILSignatureUrCodec.decodePsbt(type: "crypto-psbt", frames: [singleUr("crypto-psbt", cbor(.a([])))]) }
        }

        // =====================================================================================================================
        // MARK: - Verified payload, errors, text helpers
        // =====================================================================================================================

        section("payload")
        do {
            let tx = try BILEvmTxCodec.decodeUnsigned(hx(TYPE2))
            let maps = try BILPsbtMaps.parse(minimalV0())
            let header = try BILSolanaMessageHeader.parse(solGood)
            let raw = baseRaw
            let decoded = BILTronRawData.decode(raw) ?? BILTronRawData(contracts: [], feeLimit: nil, data: nil, expiration: nil)
            let payloads: [BILVerifiedPayload] = [
                .evmTransaction(signData: hx(TYPE2), tx: tx), .evmPersonal(Array("Ownbit public protocol fixture".utf8)),
                .evmTypedData(json: "{\"domain\":{\"chainId\":1}}", domainChainId: "1", hasDomainChainId: true),
                .tronTransaction(raw: raw, decoded: decoded, ownerHex41: hexOf(ownerA), contractType: 1, txProto: nil),
                .tronOwnershipProof(raw: raw, name: "TronLinkCustomContract", ownerHex41: hexOf(ownerA), txProto: raw), .tronMessage([1, 2, 3]),
                .solanaTransaction(bytes: solGood, header: header, signerSlot: 0), .solanaMessage([0x41]),
                .bitcoinPsbt(bytes: minimalV0(), maps: maps, witnessOnlyInputs: [0])]
            for p in payloads {
                let texts = ["\(p)", String(reflecting: p), { var s = ""; dump(p, to: &s); return s }()]
                for s in texts {
                    t(!s.contains("2222222222") && !s.contains("aaaaaaaa") && !s.contains("Ownbit") && !s.contains("chainId\"") && !s.contains("f03627"),
                      "payload text is log-safe: \(s.prefix(60))")
                }
            }
            eq(payloads[3].tronTxId, BILPublicHash.sha256Hex(raw), "tronTxId of a TRON transaction")
            eq(payloads[4].tronTxId, BILPublicHash.sha256Hex(raw), "tronTxId of an ownership proof")
            eq(payloads[1].tronTxId, nil, "no tronTxId for EVM")
            t(!"\(tx)".contains("2222") && !"\(maps)".contains("0000") && !"\(decoded)".contains("aaaa"), "decoder descriptions are log-safe")
            let entry = maps.global[0]
            t(!"\(entry)".contains(hexOf(TX).prefix(12)), "PSBT entry description is log-safe")
            let op = BILPsbtMaps.Outpoint(txid: hx(repeatHex("ab", 32)), vout: 3)
            t(!"\(op)".contains("abab"), "outpoint description is log-safe")
            let answer = BILSignatureUrCodec.SignatureAnswer(type: "eth-signature", requestId: [0xDE, 0xAD], signature: [0xBE, 0xEF])
            t(!"\(answer)".contains("dead") && !"\(answer)".contains("beef"), "signature answer description is log-safe")

            // Every decoder value type: description, String(reflecting:) and dump carry none of its content, and dump lists
            // no children (arrays would print as decimal bytes, which no hex check sees).
            func dumpText(_ v: Any) -> String { var s = ""; dump(v, to: &s); return s }
            func logSafe(_ v: Any, _ secrets: [String], _ label: String) {
                let texts = ["\(v)", String(reflecting: v), dumpText(v)].map { $0.lowercased() }
                let leaked = secrets.filter { $0.count >= 8 }.filter { secret in texts.contains { $0.contains(secret.lowercased()) } }
                t(leaked.isEmpty, "\(label): description / reflection / dump are log-safe")
                eq(dumpText(v).split(separator: "\n").count, 1, "\(label): dump has no children")
            }
            let to = tx.to.map { String($0.dropFirst(2)) } ?? ""
            t(to.count == 40, "TYPE2 has a recipient to look for")
            logSafe(tx, [to, hexOf(tx.signingHash)], "BILUnsignedEvmTx")
            let contractOf = decoded.contracts.first
            t(contractOf?.ownerHex41?.count == 42, "base raw has an owner to look for")
            logSafe(decoded, [contractOf?.ownerHex41 ?? "", contractOf?.typeUrl ?? "", hexOf(contractOf?.value ?? [])], "BILTronRawData")
            if let c = contractOf { logSafe(c, [c.ownerHex41 ?? "", c.typeUrl ?? "", hexOf(c.value)], "BILTronContract") }
            logSafe(header, (0..<header.keyCount).map { header.keyHex($0) }, "BILSolanaMessageHeader")
            t(!header.instructions.isEmpty, "Solana header has an instruction")
            if let ix = header.instructions.first { logSafe(ix, [hexOf(ix.data)], "Solana instruction") }
            let request = BILSignatureUrCodec.SignRequest(requestId: hx("deadbeefdeadbeef"), signData: hx("c0ffee11c0ffee11"), dataType: 1,
                                                          chainId: 1, signType: nil)
            logSafe(request, ["deadbeef", "c0ffee11"], "SignRequest")
            let longAnswer = BILSignatureUrCodec.SignatureAnswer(type: "eth-signature", requestId: hx("deadbeefdeadbeef"), signature: hx("c0ffee11c0ffee11"))
            logSafe(longAnswer, ["deadbeef", "c0ffee11"], "SignatureAnswer")
            logSafe(BILCbor.bytes(hx("deadbeefdeadbeef")), ["deadbeef"], "BILCbor bytes")
            logSafe(BILCbor.text("Ownbit secret text"), ["Ownbit secret"], "BILCbor text")
            logSafe(BILCbor.map([(.uint(1), .tag(37, .bytes(hx("deadbeefdeadbeef")))), (.text("signature"), .array([.uint(7)]))]),
                    ["deadbeef", "signature"], "BILCbor map")
            logSafe(entry, [hexOf(TX), String(hexOf(TX).prefix(12))], "PSBT entry")
            logSafe(op, [repeatHex("ab", 8)], "PSBT outpoint")
            logSafe(maps, [hexOf(TX)], "BILPsbtMaps")
            let derivation = BILPsbtMaps.OutputDerivation(outputIndex: 0, publicKey: "02" + repeatHex("ab", 32), fingerprint: "73c5da0a",
                                                          path: [0x8000_0054, 0x8000_0000, 0x8000_0000, 1, 5], taproot: false)
            logSafe(derivation, [derivation.publicKey, derivation.fingerprint, "m/84'/0'/0'/1/5", "2147483732"], "OutputDerivation")
            eq("\(derivation)", "OutputDerivation(output=0, taproot=false)", "OutputDerivation description")
            if let d = tapHashes.first { logSafe(d, [d.publicKey, d.fingerprint, d.pathText], "vector Taproot derivation") }
        }
        eq("\(BILVerifyError("psbt.magic"))", "Public protocol check failed: psbt.magic", "BILVerifyError description = Android message")
        eq(BILVerifyError(what: "x"), BILVerifyError("x"), "memberwise init(what:) kept")
        eq(BILCbor.uint(UInt64.max).integerValue, nil, "hand-built uint above Int64.max: no Long view (no trap)")
        eq(BILCbor.uint(UInt64(Int64.max)).integerValue, Int64.max, "uint Int64.max")
        eq(BILCbor.nint(Int64.min).integerValue, Int64.min, "nint value kept")
        t(BILCbor.map([(.uint(UInt64.max), .bool(true)), (.uint(2), .bool(false))]).get(2) == BILCbor.bool(false), "get skips a key without a Long view")
        t(BILVerifyText.equalsIgnoringCase("aBcD12", "AbCd12"), "equalsIgnoringCase ASCII")
        t(!BILVerifyText.equalsIgnoringCase("abc", "abcd"), "equalsIgnoringCase length")
        t(!BILVerifyText.equalsIgnoringCase("k", "\u{212A}"), "equalsIgnoringCase differs from Kotlin on purpose for non-hex text (Kelvin sign)")
        t(!BILVerifyText.equalsIgnoringCase("0x", "0\u{FF58}") && BILVerifyText.equalsIgnoringCase("0xAB", "0Xab"), "equalsIgnoringCase on 0x hex")
        t(!BILVerifyText.same("K", "\u{212A}") && ("K" == "\u{212A}"), "same() is exact where Swift == is not")
        eq(BILVerifyText.strictUTF8([0xEF, 0xBB, 0xBF, 0x41]), "\u{FEFF}A", "strict UTF-8 keeps a BOM")
        eq(BILVerifyText.strictUTF8([0xEF, 0xBF, 0xBD]), "\u{FFFD}", "a literal U+FFFD is valid")
        eq(BILVerifyText.strictUTF8([0xF4, 0x90, 0x80, 0x80]), nil, "above U+10FFFF")
        eq(BILVerifyText.strictUTF8([0xE2, 0x82]), nil, "truncated sequence")

        // MARK: - Performance smoke (informational): the largest vector PSBT diff and a 100-frame UR.
        section("perf")
        do {
            let id = "T8-flow-bitcoin-psbt-20-inputs"
            let start = Date()
            let request = try BILPsbtMaps.parse(b64(scannedRequest(id)?["psbt"] as? String ?? planRequest(id)?["psbt"] as? String))
            let signed = try BILPsbtMaps.parse(b64(signResults(id).last?["psbt"] as? String))
            let diff = BILPsbtMaps.diff(request: request, response: signed, signers: signersOf(tasks(planJson(id))))
            t(diff.ok, "20-input PSBT diff ok (\(diff.problem ?? "ok"))")
            eq(request.inputs.count, 20, "20 inputs")
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            let big = [UInt8]((0..<20_000).map { UInt8(truncatingIfNeeded: $0 * 7) })
            let urStart = Date()
            let parts = multiUr("crypto-psbt", big, fragLen: 200)
            eq(try BILSignatureUrCodec.decodeUr(parts).cbor, big, "100-fragment UR decodes")
            let urMs = Int(Date().timeIntervalSince(urStart) * 1000)
            print("verify: perf psbt20=\(ms)ms ur100=\(urMs)ms")
        } catch {
            t(false, "perf fixtures (\(error))")
        }

        pubSummary("verify (macOS)")
    }
}
