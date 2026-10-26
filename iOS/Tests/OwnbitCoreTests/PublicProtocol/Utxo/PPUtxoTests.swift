//  PPUtxoTests.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Port of the app harness suite `scripts/public-protocol/tests/utxo` (main.swift) to XCTest.
//
//  tests/utxo/main.swift (WP12) — F01 strict UTXO numbers of the internal bb_sign: (design D-31), the canonical
//  [String: Any] patch, the BTC claims and the internal BTC sign path under BILBitcoinSigningLock.
//  Ports Android UtxoSendEngineTest.signHandsTheBundleOnlyExactIntegers, OfflineRequestChecksTest
//  "UTXO inputs and outputs must be exact integers" and the three ColdSignerTest F01 cases (b8c70c25).
//

import Foundation
import XCTest
@testable import OwnbitCore

/// The suite namespace (harness helpers are its static members).
enum PPUtxoSuite: PPSuite {}

final class PPUtxoTests: XCTestCase {
    func testUtxo() throws {
        try ppRunSuite("utxo") { try PPUtxoSuite.run() }
    }
}

extension PPUtxoSuite {

    static let ab64 = String(repeating: "ab", count: 32)
    static let cd64 = String(repeating: "cd", count: 32)
    static let BTC = BILUtxoChainProfile.of(coinTypeRaw: 0)!
    static let LTC = BILUtxoChainProfile.of(coinTypeRaw: 4)!

    static func obj(_ text: String) -> BILJSONObject? { return BILStrictJSON.parseObject(text) }

    /// A BTC signDatas whose input #0 carries the raw JSON tokens (nil = key left out); input #1 and the output are fine.
    static func btc(satoshis: String? = "50000", index: String? = "0", txHash: String? = "\"\(ab64)\"", amount: String = "40000") -> String {
        var fields = [String]()
        if let t = txHash { fields.append("\"txHash\":\(t)") }
        if let i = index { fields.append("\"index\":\(i)") }
        if let s = satoshis { fields.append("\"satoshis\":\(s)") }
        fields += ["\"segwit\":\"D\"", "\"bip39Index\":0", "\"isChange\":false"]
        let second = "{\"txHash\":\"\(cd64)\",\"index\":1,\"satoshis\":20000,\"segwit\":\"D\",\"bip39Index\":1,\"isChange\":false}"
        return "{\"inputs\":[{\(fields.joined(separator: ","))},\(second)],\"outputs\":[{\"address\":\"bc1q\",\"amount\":\(amount)}],\"ophex\":\"\",\"locktime\":0}"
    }

    /// The whole decoded bb_sign: request around a signDatas text.
    static func request(_ signDatas: String, coinType: Int = 0) -> String {
        return "{\"signDatas\":\(signDatas),\"iAdds\":[\"bc1qfrom\"],\"oAdds\":[\"bc1q\"],\"amount\":40000,\"remark\":\"\",\"sID\":\"w1\",\"mID\":\"\",\"rID\":\"\",\"symbol\":\"BTC\",\"coinType\":\(coinType)}"
    }

    static let qr = "bb_sign:ignored-by-the-check"

    /// The two fields of the app's `TransactionBuildDatas` this check reads / patches (app type, not in the package).
    struct TransactionBuildDatas {
        var signDatas: [String: Any] = [:]
        var coinType: Int64 = 0
    }

    /// The app's `checkedBD(_:datasText:coinTypeRaw:)` over the package's plain-value API.
    static func checkedBD(_ bd: TransactionBuildDatas, datasText: String, coinTypeRaw: Int)
        -> (buildDatas: TransactionBuildDatas, claims: [BILSignedOutpointMemory.Claim])? {
        guard let r = BILUtxoSignDatas.checked(signDatas: bd.signDatas, datasText: datasText, coinTypeRaw: coinTypeRaw) else { return nil }
        var out = bd
        out.signDatas = r.signDatas
        return (out, r.claims)
    }

    /// The app's `sendConfirmBuildTxFailed` (key `SendC.confirm.buildTxFailed`) through the package's localizer.
    static var sendConfirmBuildTxFailed: String { return BILPublicText.string("SendC.confirm.buildTxFailed") }

    /// A TransactionBuildDatas as the app builds it from the decoded text (JSONSerialization → [String: Any]).
    static func buildDatas(_ requestText: String) -> TransactionBuildDatas? {
        guard let any = try? JSONSerialization.jsonObject(with: Data(requestText.utf8)),
              let dict = any as? [String: Any] else { return nil }
        var d = TransactionBuildDatas()
        d.signDatas = dict["signDatas"] as? [String: Any] ?? [:]
        d.coinType = (dict["coinType"] as? NSNumber)?.int64Value ?? 0
        return d
    }

    static func temp(_ name: String) -> URL {
        return pubTempDir("utxo-\(name)").appendingPathComponent("PublicSigner").appendingPathComponent("signed_outpoints.json")
    }

    @MainActor
    static func simulateSign(_ requestText: String, coinType: Int, memory: BILSignedOutpointMemory) async -> (calls: Int, outcome: String) {
        guard let bd = buildDatas(requestText) else { return (0, "not-json") }
        guard let checked = checkedBD(bd, datasText: requestText, coinTypeRaw: coinType) else { return (0, "refused") }
        var calls = 0
        let outcome: BILBitcoinSigningLock.InternalOutcome<String, NSError> =
            await BILBitcoinSigningLock.signInternal(claims: checked.claims, memory: memory) { done in
                calls += 1
                done(.success("answer"))
            }
        if case .answered = outcome { return (calls, "answered") }
        return (calls, "other")
    }
    struct FakeError: Error, Equatable { let code: Int }
    static func claim(_ b: UInt8, _ sats: UInt64, vout: UInt32 = 0) -> BILSignedOutpointMemory.Claim {
        return BILSignedOutpointMemory.Claim(txid: [UInt8](repeating: b, count: 32), vout: vout, sats: sats)
    }

    /// The harness main.swift (nonisolated top-level code, as in the harness).
    static func run() throws {
        pubLoadStrings(tables: ["PublicProtocol", "UI", "SendC"])

        // MARK: - Profile table (Android 8 rows + iOS-only) and the app sources it is read from

        section("profiles")
        do {
            let raws = BILUtxoChainProfile.all.map { $0.coinTypeRaw }
            eq(Set(raws).count, raws.count, "coin types distinct")
            eq(BTC.txidKey, "txHash", "BTC txid key"); eq(BTC.voutKey, "index", "BTC vout key")
            eq(BTC.inputAmountKey, "satoshis", "BTC input amount"); eq(BTC.outputAmountKey, "amount", "BTC output amount")
            eq(LTC.txidKey, "txid", "LTC txid key"); eq(LTC.voutKey, "vout", "LTC vout key")
            for raw in [3, 4, 8, 9, 10, 19] {
                let p = BILUtxoChainProfile.of(coinTypeRaw: raw)
                eq(p?.inputStyle, .script, "script style \(raw)")
                eq(p?.outputAmountKey, "amount", "output amount \(raw)")
                eq(p?.inputAmountKey, "satoshis", "input amount \(raw)")
            }
            eq(BILUtxoChainProfile.of(coinTypeRaw: 11)?.outputAmountKey, "satoshis", "ZEN output key satoshis")
            // Package: the app's rows of coins outside the supported-chain list (DCR 6, Omni USDT 7, RVN 12, XZC 13, BSV 18)
            // are not in the table.
            for raw in [6, 7, 12, 13, 18] {
                t(BILUtxoChainProfile.of(coinTypeRaw: raw) == nil, "excluded coin \(raw) has no row")
            }
            eq(Set(raws), Set([0, 3, 4, 8, 9, 10, 11, 19]), "BTC, BCH, LTC, DASH, DOGE, DGB, ZEN, ZEC")
            for raw in [1, 2, 5, 16, 17, 20, 25, 34, 47, 64, 65] {
                t(BILUtxoChainProfile.of(coinTypeRaw: raw) == nil, "not a UTXO coin: \(raw)")
            }
            // (The app also read its CoinType enum, review page and transaction builders from the app sources to prove the
            // table matches them; that is app code, not part of the package.)
        }

        // MARK: - Refused: the whole request (Android OfflineRequestChecksTest / UtxoSendEngineTest / ColdSignerTest)

        section("refused")
        var refusedCases: [(String, String)] = []
        for s in ["100000.0000000000000000001", "50000.0000000000000000001", "50000.5", "5e4", "1e5", "1E5", "100000.0", "\"100000\"",
                  "-1", "9007199254740992", "9007199254740993", "true", "null", "012", "12345678901234567890", "18446744073709551616", "[1]", "{}"] {
            refusedCases.append(("satoshis=\(s)", btc(satoshis: s)))
        }
        refusedCases.append(("satoshis missing", btc(satoshis: nil)))
        for i in ["0.0000000000000000001", "1.0000000000000000001", "0.5", "1.0", "4294967296", "\"0\"", "\"1\"", "12345678901234567890", "-0", "true"] {
            refusedCases.append(("index=\(i)", btc(index: i)))
        }
        refusedCases.append(("index missing", btc(index: nil)))
        for h in ["\"0x\(String(repeating: "ab", count: 31))\"", "1", "12", "\"\(String(repeating: "a", count: 63))\"", "\"\(String(repeating: "a", count: 65))\"",
                  "\"\(String(repeating: "ab", count: 31))a \"", "\" \(String(repeating: "ab", count: 31))a\"", "\"\(String(repeating: "gg", count: 32))\"", "null"] {
            refusedCases.append(("txHash=\(h.prefix(12))…", btc(txHash: h)))
        }
        refusedCases.append(("txHash missing", btc(txHash: nil)))
        for a in ["40000.0000000000000000001", "1.5", "\"40000\"", "-5", "4e4", "9007199254740992"] {
            refusedCases.append(("output amount=\(a)", btc(amount: a)))
        }
        refusedCases += [
            ("inputs empty", "{\"inputs\":[],\"outputs\":[]}"),
            ("inputs not an array", "{\"inputs\":{},\"outputs\":[]}"),
            ("input not an object", "{\"inputs\":[7],\"outputs\":[]}"),
            ("no inputs (Android outputs-only)", "{\"outputs\":\"\"}"),
            ("outputs missing", "{\"inputs\":[{\"txHash\":\"\(ab64)\",\"index\":0,\"satoshis\":1}]}"),
            ("outputs not an array", "{\"inputs\":[{\"txHash\":\"\(ab64)\",\"index\":0,\"satoshis\":1}],\"outputs\":\"\"}"),
            ("output not an object", "{\"inputs\":[{\"txHash\":\"\(ab64)\",\"index\":0,\"satoshis\":1}],\"outputs\":[1]}"),
            ("output amount missing", "{\"inputs\":[{\"txHash\":\"\(ab64)\",\"index\":0,\"satoshis\":1}],\"outputs\":[{\"address\":\"a\"}]}"),
            ("duplicate key in an input", "{\"inputs\":[{\"txHash\":\"\(ab64)\",\"index\":0,\"satoshis\":1,\"satoshis\":1}],\"outputs\":[]}"),
            ("duplicate key in signDatas", "{\"inputs\":[{\"txHash\":\"\(ab64)\",\"index\":0,\"satoshis\":1}],\"outputs\":[],\"outputs\":[]}"),
        ]

        /// The controller's flow (D-31): checked → (BTC) signInternal → build. Returns the builder calls.

        runAsync {
            let memory = BILSignedOutpointMemory(fileURL: temp("refused"))
            for (name, sd) in refusedCases {
                let refusedStrict: Bool = {
                    guard let o = obj(sd) else { return true }
                    return BILUtxoSignDatas.canonical(BTC, o) == nil
                }()
                t(refusedStrict, "refused (canonical nil): \(name)")
                let text = request(sd)
                eq(BILUtxoSignDatas.refusal(qrcode: qr, datasText: text, coinTypeRaw: 0, memory: memory), BILUtxoSignDatas.refusalText,
                   "home pre-check refuses: \(name)")
                if obj(sd) != nil, let o = obj(sd) {
                    t(BILUtxoSignDatas.inputs(BTC, o) == nil || BILUtxoSignDatas.numbers(BTC, o) == nil, "inputs/numbers nil: \(name)")
                }
                let r = await simulateSign(text, coinType: 0, memory: memory)
                // A text JSONSerialization cannot read is refused by the page earlier (no review); either way nothing is built.
                eq(r.calls, 0, "zero builder calls: \(name)")
            }
            eq(memory.debugRowCount, 0, "nothing recorded by refused requests")
        }

        // MARK: - Accepted + canonical values

        section("accepted")
        do {
            for (name, sd) in [("default", btc()), ("satoshis 0", btc(satoshis: "0")), ("satoshis 2^53-1", btc(satoshis: "9007199254740991")),
                               ("index u32 max", btc(index: "4294967295")), ("upper-case txid", btc(txHash: "\"\(ab64.uppercased())\"")),
                               ("whitespace around tokens", btc().replacingOccurrences(of: ":", with: " : "))] {
                let o = obj(sd)
                t(o.flatMap { BILUtxoSignDatas.canonical(BTC, $0) } != nil, "accepted: \(name)")
                eq(BILUtxoSignDatas.refusal(qrcode: qr, datasText: request(sd), coinTypeRaw: 0, memory: BILSignedOutpointMemory(fileURL: temp("acc"))), nil,
                   "home pre-check accepts: \(name)")
            }
            let max = obj(btc(satoshis: "9007199254740991", index: "4294967295"))!
            let ins = BILUtxoSignDatas.inputs(BTC, max)!
            eq(ins[0].sats, 9_007_199_254_740_991, "max safe sats read")
            eq(ins[0].vout, 4_294_967_295, "u32 max vout read")
            eq(ins.count, 2, "both inputs read")

            // Canonical text byte check: txid lower case, integers re-written, key positions kept, unknown keys untouched.
            let upper = "00112233445566778899AABBCCDDEEFF00112233445566778899AABBCCDDEEFF"
            let source = "{\"z\":1,\"inputs\":[{\"txHash\":\"\(upper)\",\"index\":1,\"x\":\"keep\",\"satoshis\":7}],\"outputs\":[{\"address\":\"a\",\"amount\":5,\"y\":[1,2.50]}],\"locktime\":0,\"note\":\"\\u00e9/\"}"
            let expected = "{\"z\":1,\"inputs\":[{\"txHash\":\"\(upper.lowercased())\",\"index\":1,\"x\":\"keep\",\"satoshis\":7}],\"outputs\":[{\"address\":\"a\",\"amount\":5,\"y\":[1,2.50]}],\"locktime\":0,\"note\":\"é/\"}"
            let canonical = BILUtxoSignDatas.canonical(BTC, obj(source)!)!
            eq(BILStrictJSON.serialize(canonical), expected, "canonical compact text")
            eq(canonical.keys, ["z", "inputs", "outputs", "locktime", "note"], "signDatas key order kept")
            eq(canonical["inputs"]?.arrayValue?.first?.objectValue?.keys ?? [], ["txHash", "index", "x", "satoshis"], "input key order kept")

            // Script style (Android LTC example), ZEN outputs, DCR atoms, Omni USDT.
            let ltc = "{\"inputs\":[{\"txid\":\"\(ab64)\",\"vout\":0,\"satoshis\":1.5}],\"outputs\":[{\"address\":\"L\",\"amount\":1}]}"
            t(BILUtxoSignDatas.canonical(LTC, obj(ltc)!) == nil, "LTC satoshis 1.5 refused")
            let ltcFixed = ltc.replacingOccurrences(of: "1.5", with: "2")
            t(BILUtxoSignDatas.canonical(LTC, obj(ltcFixed)!) != nil, "LTC fixed accepted")
            t(BILUtxoSignDatas.canonical(LTC, obj(btc())!) == nil, "LTC with BTC keys (txHash/index) refused")
            t(BILUtxoSignDatas.canonical(BTC, obj(ltcFixed)!) == nil, "BTC with script keys (txid/vout) refused")
            for raw in [3, 8, 9, 10, 19] {
                let p = BILUtxoChainProfile.of(coinTypeRaw: raw)!
                t(BILUtxoSignDatas.canonical(p, obj(ltcFixed)!) != nil, "script coin \(raw) accepts txid/vout/satoshis")
                eq(BILUtxoSignDatas.refusal(qrcode: qr, datasText: request(ltc, coinType: raw), coinTypeRaw: raw), BILUtxoSignDatas.refusalText,
                   "script coin \(raw) refuses 1.5")
            }
            let zen = BILUtxoChainProfile.of(coinTypeRaw: 11)!
            t(BILUtxoSignDatas.canonical(zen, obj(ltcFixed)!) == nil, "ZEN output under amount only: refused")
            let zenOK = "{\"inputs\":[{\"txid\":\"\(ab64)\",\"vout\":0,\"satoshis\":2}],\"outputs\":[{\"address\":\"z\",\"satoshis\":1}],\"blockHeight\":5}"
            eq(BILUtxoSignDatas.numbers(zen, obj(zenOK)!)?.outputAmounts ?? [], [1], "ZEN output satoshis read")
            t(BILUtxoSignDatas.canonical(zen, obj(zenOK.replacingOccurrences(of: "\"satoshis\":1}", with: "\"satoshis\":1.0}"))!) == nil, "ZEN output 1.0 refused")
        }

        // MARK: - Trees built in code (review WP12 #5): the token rule itself, not only BILStrictJSON's grammar

        section("literals")
        do {
            /// A BTC signDatas tree whose input #0 index / satoshis and output amount carry `.number` literals as given.
            func tree(index: String = "0", satoshis: String = "1", amount: String = "1") -> BILJSONObject {
                let input = BILJSONObject([("txHash", .string(ab64)), ("index", .number(index)), ("satoshis", .number(satoshis))])
                let output = BILJSONObject([("address", .string("bc1q")), ("amount", .number(amount))])
                return BILJSONObject([("inputs", .array([.object(input)])), ("outputs", .array([.object(output)]))])
            }
            t(BILUtxoSignDatas.canonical(BTC, tree()) != nil, "the plain tree is accepted")
            eq(BILUtxoSignDatas.numbers(BTC, tree(index: "10", satoshis: "1234567890123456", amount: "0"))?.outputAmounts ?? [], [0], "plain literals read")
            // non-canonical literals a JSON parser would never produce (leading zero, sign, blanks, empty, fraction / exponent forms)
            for lit in ["012", "00", "0012", "+1", "-0", "-1", " 1", "1 ", "", "1.", ".1", "1.0", "1e5", "0x1", "1_000", "\u{FF11}", "１２"] {
                t(BILUtxoSignDatas.canonical(BTC, tree(satoshis: lit)) == nil && BILUtxoSignDatas.inputs(BTC, tree(satoshis: lit)) == nil,
                  "satoshis literal \"\(lit)\" refused")
                t(BILUtxoSignDatas.canonical(BTC, tree(index: lit)) == nil && BILUtxoSignDatas.inputs(BTC, tree(index: lit)) == nil,
                  "index literal \"\(lit)\" refused")
                t(BILUtxoSignDatas.canonical(BTC, tree(amount: lit)) == nil && BILUtxoSignDatas.numbers(BTC, tree(amount: lit)) == nil,
                  "output amount literal \"\(lit)\" refused")
            }
            // 19 characters is the limit (leading-zero-free); 20 never reads
            t(BILUtxoSignDatas.inputs(BTC, tree(index: "0000000000000000001")) == nil, "19-char literal with leading zeros refused")
            t(BILUtxoSignDatas.inputs(BTC, tree(satoshis: "1000000000000000000")) == nil, "19 digits above 2^53 − 1 refused")
            t(BILUtxoSignDatas.inputs(BTC, tree(satoshis: "10000000000000000000")) == nil, "20 digits refused")
            // a string / bool / null value where a number belongs (tree built in code)
            for v in [BILJSONValue.string("1"), .bool(true), .null, .array([.number("1")])] {
                var o = tree().arr("inputs")![0].objectValue!
                o.set("satoshis", v)
                t(BILUtxoSignDatas.inputs(BTC, BILJSONObject([("inputs", .array([.object(o)])), ("outputs", .array([]))])) == nil, "non-number satoshis refused")
            }

            // Read values print and dump nothing (review WP12 #6).
            let n = BILUtxoSignDatas.numbers(BTC, tree(satoshis: "987654321", amount: "123456789"))!
            var printed = "\(n) \(String(reflecting: n)) \(n.inputs[0]) \(String(reflecting: n.inputs[0]))"
            dump(n, to: &printed)
            dump(n.inputs[0], to: &printed)
            t(!printed.contains("987654321") && !printed.contains("123456789") && !printed.contains("abab"), "numbers / inputs print and dump nothing")
        }

        // MARK: - Claims (every input, txid reversed)

        section("claims")
        do {
            let txid = (0..<32).map { String(format: "%02x", $0) }.joined()
            let ins = [BILUtxoSignDatas.Input(txid: txid, vout: 7, sats: 1234), BILUtxoSignDatas.Input(txid: ab64, vout: 0, sats: 1)]
            let claims = BILUtxoSignDatas.claims(ins, inputCount: 2)
            eq(claims?.count, 2, "one claim per input")
            eq(claims?.first?.txid ?? [], Array((0..<32).map { UInt8($0) }.reversed()), "txid bytes reversed (transaction order)")
            eq(claims?.first?.vout, 7, "vout kept"); eq(claims?.first?.sats, 1234, "sats kept")
            t(BILUtxoSignDatas.claims(ins, inputCount: 3) == nil, "count mismatch → nil")
            t(BILUtxoSignDatas.claims([BILUtxoSignDatas.Input(txid: "ab", vout: 0, sats: 1)], inputCount: 1) == nil, "short txid → nil")
        }

        // MARK: - The [String: Any] patch the builders re-serialize (integer tokens, never 100000.0 / 1e+05)

        section("patch")
        do {
            let upper = ab64.uppercased()
            let text = request(btc(satoshis: "100000", txHash: "\"\(upper)\""))
            let bd = buildDatas(text)!
            let checked = checkedBD(bd, datasText: text, coinTypeRaw: 0)
            t(checked != nil, "checked")
            let sd = checked?.buildDatas.signDatas ?? [:]
            let json = String(data: (try? JSONSerialization.data(withJSONObject: sd, options: [.sortedKeys])) ?? Data(), encoding: .utf8) ?? ""
            t(json.contains("\"satoshis\":100000"), "satoshis written as an integer token")
            t(!json.contains("100000.0") && !json.contains("e+") && !json.contains("E+"), "no fraction / exponent in the re-serialized text")
            t(json.contains("\"txHash\":\"\(ab64)\""), "txid lower case in what the builder serializes")
            t(json.contains("\"segwit\":\"D\"") && json.contains("\"isChange\":false") && json.contains("\"bip39Index\":0") && json.contains("\"ophex\":\"\""),
              "other keys untouched")
            let reparsed = obj(json).flatMap { BILUtxoSignDatas.numbers(BTC, $0) }
            eq(reparsed, obj(btc(satoshis: "100000")).flatMap { BILUtxoSignDatas.numbers(BTC, $0) }, "builder text carries the checked numbers")
            eq(checked?.claims.count, 2, "BTC claims of every input")

            // The patch is what JS parses: a dictionary holding doubles (100000.0) leaves as integers once patched.
            var weird = bd
            var inputs = weird.signDatas["inputs"] as? [[String: Any]] ?? []
            inputs[0]["satoshis"] = NSNumber(value: 100000.0 as Double)
            inputs[0]["index"] = NSNumber(value: 0.0 as Double)
            weird.signDatas["inputs"] = inputs
            weird.signDatas["outputs"] = [["address": "bc1q", "amount": NSNumber(value: 40000.0 as Double)]]
            let patched = checkedBD(weird, datasText: text, coinTypeRaw: 0)?.buildDatas.signDatas ?? [:]
            let pj = String(data: (try? JSONSerialization.data(withJSONObject: patched, options: [.sortedKeys])) ?? Data(), encoding: .utf8) ?? ""
            t(pj.contains("\"satoshis\":100000") && pj.contains("\"index\":0") && pj.contains("\"amount\":40000") && !pj.contains("."),
              "doubles in the dictionary are replaced by integer NSNumbers")
            let n = (patched["inputs"] as? [[String: Any]])?.first?["satoshis"] as? NSNumber
            eq(n.map { String(cString: $0.objCType) }, "q", "NSNumber(value: Int64)")

            // Dictionary and text disagree on the input count → refused (the claims must cover what the builder gets).
            var fewer = bd
            fewer.signDatas["inputs"] = Array((bd.signDatas["inputs"] as? [[String: Any]] ?? []).prefix(1))
            t(checkedBD(fewer, datasText: text, coinTypeRaw: 0) == nil, "input count mismatch → refused")

            // Not a UTXO coin / message: unchanged, no claims.
            let eth = request("{\"destination\":\"0xdead\",\"amount\":1.5,\"inputs\":\"junk\"}", coinType: 1)
            let ethBD = buildDatas(eth)!
            let ethChecked = checkedBD(ethBD, datasText: eth, coinTypeRaw: 1)
            t(ethChecked != nil && ethChecked!.claims.isEmpty, "ETH: unchecked")
            eq(BILUtxoSignDatas.refusal(qrcode: qr, datasText: eth, coinTypeRaw: 1), nil, "ETH: no refusal")
            let msg = request("{\"destination\":\"signMessage\",\"extraData\":\"hello\",\"inputs\":[],\"satoshis\":1.5}", coinType: 0)
            eq(BILUtxoSignDatas.refusal(qrcode: qr, datasText: msg, coinTypeRaw: 0), nil, "message request skipped")
            let msgChecked = checkedBD(buildDatas(msg)!, datasText: msg, coinTypeRaw: 0)
            t(msgChecked != nil && msgChecked!.claims.isEmpty, "message: unchanged, no claims")
            eq(BILUtxoSignDatas.refusal(qrcode: "bb_msinitiate:x", datasText: request(btc(satoshis: "1.5")), coinTypeRaw: 0), nil,
               "only bb_sign: is checked here")
            // Strict parse of the whole request text: duplicate keys / lone surrogate / not JSON refuse a UTXO request.
            eq(BILUtxoSignDatas.refusal(qrcode: qr, datasText: request(btc()).replacingOccurrences(of: "\"remark\":\"\"", with: "\"remark\":\"a\",\"remark\":\"b\""), coinTypeRaw: 0),
               BILUtxoSignDatas.refusalText, "duplicate top-level key refused")
            eq(BILUtxoSignDatas.refusal(qrcode: qr, datasText: request(btc()).replacingOccurrences(of: "\"remark\":\"\"", with: "\"remark\":\"\\ud800\""), coinTypeRaw: 0),
               BILUtxoSignDatas.refusalText, "lone surrogate escape refused")
            eq(BILUtxoSignDatas.refusal(qrcode: qr, datasText: "", coinTypeRaw: 0), BILUtxoSignDatas.refusalText, "undecodable text refused")
            eq(BILUtxoSignDatas.refusal(qrcode: qr, datasText: "{\"coinType\":0}", coinTypeRaw: 0), BILUtxoSignDatas.refusalText, "no signDatas refused")
            t(checkedBD(bd, datasText: "{not json", coinTypeRaw: 0) == nil, "checked refuses a non-strict text")
        }

        // MARK: - Stop condition: the encoders write integer tokens (iOS builders' dictionaries, Android fixtures)

        section("encoders")
        do {
            // iOS: BTCInput.toDictionary / BCHInput.toDictionary / BTCOutput.toDictionary shapes (Int, Int64, Bool, String),
            // serialized like BILSendModel.offlineTxSignString (JSONSerialization) — e.g. the DEBUG "offlinesample btc" payload.
            let btcInputs: [[String: Any]] = [["txHash": String(repeating: "a", count: 64), "index": 0, "satoshis": Int64(150_000), "segwit": "D", "isChange": false, "bip39Index": 0, "txHex": ""],
                                              ["txHash": String(repeating: "b", count: 64), "index": 1, "satoshis": Int64(60_000), "segwit": "T", "isChange": true, "bip39Index": 1, "txHex": "", "address": "bc1p", "scriptPubKey": "5120"]]
            let btcOutputs: [[String: Any]] = [["address": "1BitcoinEaterAddressDontSendf59kuE", "amount": Int64(100_000)], ["address": "bc1q", "amount": Int64(85_000)]]
            func payload(_ sd: [String: Any], coinType: Int) -> String {
                let p: [String: Any] = ["signDatas": sd, "iAdds": ["x"], "oAdds": ["y"], "amount": 120_000, "remark": "a/b \u{2014} é", "sID": "w", "mID": "", "rID": "", "symbol": "BTC", "coinType": coinType]
                return String(data: try! JSONSerialization.data(withJSONObject: p, options: .prettyPrinted), encoding: .utf8)!
            }
            eq(BILUtxoSignDatas.refusal(qrcode: qr, datasText: payload(["inputs": btcInputs, "outputs": btcOutputs, "ophex": "", "locktime": 0, "caStatus": 0, "decimals": 8], coinType: 0), coinTypeRaw: 0,
                                        memory: BILSignedOutpointMemory(fileURL: temp("enc"))), nil, "iOS BTC encoder (incl. Taproot input) accepted")
            let bch: [[String: Any]] = [["scriptPubKey": "76a9", "txid": String(repeating: "c", count: 64), "vout": 2, "bip39Index": 0, "isChange": false, "satoshis": Int64(5_000)]]
            for raw in [3, 4, 8, 9, 10, 19] {
                eq(BILUtxoSignDatas.refusal(qrcode: qr, datasText: payload(["inputs": bch, "outputs": [["address": "q", "amount": Int64(4_000)]]], coinType: raw), coinTypeRaw: raw),
                   nil, "iOS BCHInput-style encoder accepted (coin \(raw))")
            }
            eq(BILUtxoSignDatas.refusal(qrcode: qr, datasText: payload(["inputs": bch, "outputs": [["address": "z", "satoshis": Int64(4_000)]], "blockHeight": 1, "blockHash": "00"], coinType: 11), coinTypeRaw: 11),
               nil, "iOS ZEN encoder accepted")
            // Android ColdWalletFixtures.btcSignBody (kotlinx compact output).
            var androidInputs = [String]()
            for i in 0..<3 {
                let txHash = "9f2c1a" + String(format: "%058lx", i + 17)
                androidInputs.append("{\"txHash\":\"\(txHash)\",\"index\":\(i),\"bip39Index\":\(i),\"isChange\":false,\"satoshis\":\(40_000 + i * 1_000),\"segwit\":\"D\",\"txHex\":\"\"}")
            }
            let android = "{\"signDatas\":{\"inputs\":[\(androidInputs.joined(separator: ","))],\"outputs\":[{\"address\":\"bc1qr\",\"amount\":50000},{\"address\":\"bc1qs\",\"amount\":12345},{\"address\":\"bc1qc\",\"amount\":58000}],\"decimals\":8,\"ophex\":\"\",\"locktime\":0,\"caStatus\":0},\"coinType\":0,\"sID\":\"w\"}"
            eq(BILUtxoSignDatas.refusal(qrcode: qr, datasText: android, coinTypeRaw: 0, memory: BILSignedOutpointMemory(fileURL: temp("android"))), nil,
               "Android btcSignBody accepted")
        }

        // MARK: - BTC memory pre-check at the home scanner (before the password; no lock)

        section("btc pre-check")
        do {
            let url = temp("pre")
            let memory = BILSignedOutpointMemory(fileURL: url)
            let text = request(btc())
            eq(BILUtxoSignDatas.refusal(qrcode: qr, datasText: text, coinTypeRaw: 0, memory: memory), nil, "nothing remembered")
            let second = BILSignedOutpointMemory.Claim(txid: Array(BILPublicHex.decode(cd64)!.reversed()), vout: 1, sats: 20_001)
            try? memory.record([second])
            let want = BILPublicSignerErrors.prevoutConflict(inputNumber: 2).text
            t(want.contains("2"), "conflict text names input 2 (\(want))")
            eq(BILUtxoSignDatas.refusal(qrcode: qr, datasText: text, coinTypeRaw: 0, memory: memory), want, "conflict on input #2 → err.prevoutConflict(2)")
            eq(BILUtxoSignDatas.refusal(qrcode: qr, datasText: request(btc(), coinType: 0).replacingOccurrences(of: "20000", with: "20001"), coinTypeRaw: 0, memory: memory),
               nil, "same amount → no conflict")
            eq(BILUtxoSignDatas.refusal(qrcode: qr, datasText: request(btc().replacingOccurrences(of: "txHash", with: "txid").replacingOccurrences(of: "\"index\"", with: "\"vout\""), coinType: 4), coinTypeRaw: 4, memory: memory),
               nil, "LTC never reads the memory")
            let corruptURL = temp("pre-corrupt")
            try? FileManager.default.createDirectory(at: corruptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Data("{oops".utf8).write(to: corruptURL)
            eq(BILUtxoSignDatas.refusal(qrcode: qr, datasText: text, coinTypeRaw: 0, memory: BILSignedOutpointMemory(fileURL: corruptURL)),
               sendConfirmBuildTxFailed, "memory unavailable → sendConfirmBuildTxFailed")
            t(sendConfirmBuildTxFailed != "SendC.confirm.buildTxFailed", "SendC text loaded (\(sendConfirmBuildTxFailed))")
            eq(BILBitcoinSigningLock.Refusal.recordFailed.text, sendConfirmBuildTxFailed, "record failure text")
            eq(BILBitcoinSigningLock.Refusal.timedOut.text, sendConfirmBuildTxFailed, "timeout text")
        }

        // MARK: - Internal BTC sign path under the lock (fake builder + real memory)

        section("sign path")

        runAsync {
            let memory = BILSignedOutpointMemory(fileURL: temp("sign"))
            var calls = 0
            // success → exactly one record of every claim
            let ok: BILBitcoinSigningLock.InternalOutcome<String, FakeError> =
                await BILBitcoinSigningLock.signInternal(claims: [claim(1, 100), claim(2, 200)], memory: memory) { done in
                    calls += 1
                    done(.success("bb_tx:answer"))
                }
            if case .answered(let a) = ok { eq(a, "bb_tx:answer", "answered") } else { t(false, "answered") }
            eq(calls, 1, "one build"); eq(memory.debugRowCount, 2, "both inputs recorded")
            eq((try? memory.conflicts([claim(1, 101), claim(2, 200)])) ?? [], [0], "recorded amounts remembered")

            // conflict → refused before the build, 1-based input number (min + 1)
            let conflict: BILBitcoinSigningLock.InternalOutcome<String, FakeError> =
                await BILBitcoinSigningLock.signInternal(claims: [claim(9, 1), claim(2, 201), claim(1, 99)], memory: memory) { done in
                    calls += 1
                    done(.success("x"))
                }
            if case .refused(let r) = conflict { eq(r, .conflict(inputNumber: 2), "conflict on the 2nd input") } else { t(false, "conflict refused") }
            eq(calls, 1, "no build on a conflict")
            eq(memory.debugRowCount, 2, "nothing recorded on a conflict")

            // build failure → no record
            let failing: BILBitcoinSigningLock.InternalOutcome<String, FakeError> =
                await BILBitcoinSigningLock.signInternal(claims: [claim(3, 300)], memory: memory) { done in
                    calls += 1
                    done(.failure(FakeError(code: 7)))
                }
            if case .buildFailed(let e) = failing { eq(e, FakeError(code: 7), "builder error passed through") } else { t(false, "build failed") }
            eq(memory.debugRowCount, 2, "nothing recorded for a failed build")

            // memory unavailable (corrupt) → refused before the build
            let corruptURL = temp("sign-corrupt")
            try? FileManager.default.createDirectory(at: corruptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Data("[]".utf8).write(to: corruptURL)
            let before = calls
            let unavailable: BILBitcoinSigningLock.InternalOutcome<String, FakeError> =
                await BILBitcoinSigningLock.signInternal(claims: [claim(4, 1)], memory: BILSignedOutpointMemory(fileURL: corruptURL)) { done in
                    calls += 1
                    done(.success("x"))
                }
            if case .refused(let r) = unavailable { eq(r, .memoryUnavailable, "unavailable memory refused") } else { t(false, "unavailable refused") }
            eq(calls, before, "no build while the memory is unavailable")
            eq(BILBitcoinSigningLock.Refusal.memoryUnavailable.text, sendConfirmBuildTxFailed, "unavailable text")

            // record failure → no answer (the directory cannot be created: its parent is a plain file)
            let plain = pubTempDir("utxo-plain").appendingPathComponent("file")
            try? Data("x".utf8).write(to: plain)
            let unwritable = BILSignedOutpointMemory(fileURL: plain.appendingPathComponent("PublicSigner/signed_outpoints.json"))
            let recordFailure: BILBitcoinSigningLock.InternalOutcome<String, FakeError> =
                await BILBitcoinSigningLock.signInternal(claims: [claim(5, 1)], memory: unwritable) { done in
                    calls += 1
                    done(.success("bb_tx:must-not-leave"))
                }
            if case .refused(let r) = recordFailure { eq(r, .recordFailed, "record failure → no answer") } else { t(false, "record failure refused") }
            eq(BILBitcoinSigningLock.Refusal.recordFailed.text, sendConfirmBuildTxFailed, "record failure shows sendConfirmBuildTxFailed")

            // the builder never calls back → timed out, lock released, the late result discarded
            var late: ((Result<String, FakeError>) -> Void)?
            let started = Date()
            let stuck: BILBitcoinSigningLock.InternalOutcome<String, FakeError> =
                await BILBitcoinSigningLock.signInternal(claims: [claim(6, 1)], memory: memory, timeout: 0.3) { done in late = done }
            if case .refused(let r) = stuck { eq(r, .timedOut, "timeout refused") } else { t(false, "timeout") }
            t(Date().timeIntervalSince(started) < 3, "timeout at the deadline")
            late?(.success("late"))
            eq(memory.debugRowCount, 2, "a timed-out build records nothing (also after a late callback)")
            eq(BILBitcoinSigningLock.shared.queuedCount, 0, "lock queue empty after the timeout")
            let after: BILBitcoinSigningLock.InternalOutcome<String, FakeError> =
                await BILBitcoinSigningLock.signInternal(claims: [claim(7, 1)], memory: memory) { done in done(.success("next")) }
            if case .answered = after { t(true, "the lock was released") } else { t(false, "the lock was released") }

            // one request at a time: B (same outpoint, another amount) checks only after A recorded → conflict
            let mem2 = BILSignedOutpointMemory(fileURL: temp("serial"))
            var events = [String]()
            let a = Task { @MainActor () -> BILBitcoinSigningLock.InternalOutcome<String, FakeError> in
                await BILBitcoinSigningLock.signInternal(claims: [claim(8, 100)], memory: mem2) { done in
                    events.append("A-build")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { events.append("A-done"); done(.success("A")) }
                }
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
            let b = Task { @MainActor () -> BILBitcoinSigningLock.InternalOutcome<String, FakeError> in
                await BILBitcoinSigningLock.signInternal(claims: [claim(8, 101)], memory: mem2) { done in
                    events.append("B-build")
                    done(.success("B"))
                }
            }
            let ra = await a.value, rb = await b.value
            if case .answered = ra { t(true, "A answered") } else { t(false, "A answered") }
            if case .refused(let r) = rb { eq(r, .conflict(inputNumber: 1), "B refused: A's amount was recorded before B checked") } else { t(false, "B refused") }
            eq(events, ["A-build", "A-done"], "B never built")

            // a waiter cancelled while A holds the lock never runs
            let holder = Task { @MainActor () -> BILBitcoinSigningLock.InternalOutcome<String, FakeError> in
                await BILBitcoinSigningLock.signInternal(claims: [claim(10, 1)], memory: mem2) { done in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { done(.success("H")) }
                }
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
            var cancelledBuilt = false
            let waiter = Task { @MainActor () -> BILBitcoinSigningLock.InternalOutcome<String, FakeError> in
                await BILBitcoinSigningLock.signInternal(claims: [claim(11, 1)], memory: mem2) { done in
                    cancelledBuilt = true
                    done(.success("W"))
                }
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
            waiter.cancel()
            let rw = await waiter.value
            _ = await holder.value
            if case .cancelled = rw { t(true, "cancelled waiter → .cancelled") } else { t(false, "cancelled waiter → .cancelled") }
            t(!cancelledBuilt, "a cancelled waiter never builds")
        }

        pubSummary("utxo")
    }
}
