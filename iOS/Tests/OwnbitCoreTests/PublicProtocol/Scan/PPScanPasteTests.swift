//  PPScanPasteTests.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Port of the app harness suite `scripts/public-protocol/tests/scan` (PasteTests.swift) to XCTest.
//
//  PasteTests.swift — BILPublicPasteRouting.otherWalletRequest (port of Android PublicSignCoordinator.otherWalletRequest
//  rules, R4 §16 step 3; spec §7.5 / §7.7 paste; TokenPocket paste refusal of OtherWalletErrorsTest / spec §13.2 #15).
//

import Foundation
import XCTest
@testable import OwnbitCore

extension PPScanSuite {

    private typealias V = OtherWalletVectors

    private static func paste(_ text: String) -> Result<BILJSONObject?, BILOtherWalletRequestError> {
        do {
            return .success(try BILPublicPasteRouting.otherWalletRequest(text))
        } catch let e as BILOtherWalletRequestError {
            return .failure(e)
        } catch {
            t(false, "paste threw \(type(of: error))")
            return .failure(.malformed(code: "TEST_UNEXPECTED"))
        }
    }

    private static func mapped(_ text: String) -> BILJSONObject? {
        if case .success(let o) = paste(text) { return o }
        return nil
    }

    private static func refusedWith(_ text: String) -> BILOtherWalletRequestError? {
        if case .failure(let e) = paste(text) { return e }
        return nil
    }

    private static func isNil(_ text: String) -> Bool {
        if case .success(let o) = paste(text) { return o == nil }
        return false
    }

    /// TronLink's splitter with `size`-character pieces.
    private static func parts(_ entry: String, type: Int, size: Int) -> [String] {
        let joined = Array((entry + "&&&").utf16)
        let total = (joined.count + size - 1) / size
        return (1...total).map { i in
            var o = BILJSONObject()
            if i == 1 || i == total { o.set("address", .string(V.TRON_0)) }
            o.set("cN", .int(i))
            o.set("hexList", .array([.string(String(decoding: joined[((i - 1) * size)..<min(i * size, joined.count)], as: UTF16.self))]))
            o.set("tN", .int(total))
            o.set("type", .int(i == total ? type : 0))
            return BILStrictJSON.serialize(o)
        }
    }

    static func pasteTests() {
        section("paste: one TronLink object (also pretty-printed)")
        eq(BILPublicPasteRouting.maxPasteBytes, 262_144, "262144")
        t(mapped(V.V1_REQUEST) != nil && mapped(V.V1_REQUEST) == ScanFixtures.vectorRequest("O-TL-V1-ownership-ios"), "V1")
        t(mapped("  \n" + V.V3_REQUEST + "\n") == ScanFixtures.vectorRequest("O-TL-V3-trx-transfer"), "V3 with whitespace")
        t(mapped(V.V4_REQUEST) == ScanFixtures.vectorRequest("O-TL-V4-tip191-message"), "V4")
        let pretty = "{\n  \"amount\" : 1,\n  \"address\" : \"\(V.TRON_0)\",\n  \"amountStr\" : \"1\",\n  \"type\" : 1,\n  \"hexList\" : [\n    \"\(V.V3_ENTRY)\"\n  ]\n}"
        t(mapped(pretty) == ScanFixtures.vectorRequest("O-TL-V3-trx-transfer"), "pretty-printed V3 maps to the compact bytes")
        // One object larger than a QR (≤ 131 072 characters) is accepted on paste.
        let pad = String(repeating: "x", count: 10_000)
        let large = #"{"address":"\#(V.TRON_0)","type":1,"note":"\#(pad)","hexList":["\#(V.V3_ENTRY)"]}"#
        t(mapped(large)?.obj("transaction")?.str("raw_data_hex") == String(V.V3_ENTRY.dropFirst(6)), "a 10 k-char object")
        eq(refusedWith(#"{"address":"\#(V.TRON_0)","type":1,"note":"\#(String(repeating: "x", count: 131_072))","hexList":["\#(V.V3_ENTRY)"]}"#)?.error.code ?? "",
           "INCOMPLETE", "over 131 072: no TronLink object → the one-QR line rule (4300) → INCOMPLETE")

        section("paste: TronLink parts one per line")
        let p = parts(V.V3_ENTRY, type: 1, size: 100)
        eq(p.count, 3, "3 parts")
        let joinedLines = p.joined(separator: "\n")
        let m = mapped(joinedLines)
        eq(m?.obj("transaction")?.str("raw_data_hex") ?? "", String(V.V3_ENTRY.dropFirst(6)), "parts in order")
        t(mapped([p[2], p[0], p[1]].joined(separator: "\r\n")) == m, "any order, CRLF")
        t(mapped("\n\n" + [p[0], "", "  " + p[1] + "  ", p[2]].joined(separator: "\r") + "\n") == m, "blank lines and spaces dropped, CR")
        t(mapped([p[0], p[0], p[1], p[2]].joined(separator: "\n")) == m, "a repeated part")
        let incomplete = refusedWith([p[0], p[1]].joined(separator: "\n"))
        eq(incomplete?.kind, .malformed, "a missing part")
        eq(incomplete?.error.key ?? "", "PublicProtocol.err.qrMalformed", "incomplete text")
        eq(incomplete?.error.code ?? "", "INCOMPLETE", "INCOMPLETE")
        let notAFrame = refusedWith([p[0], "hello", p[1], p[2]].joined(separator: "\n"))
        eq(notAFrame?.error.code ?? "", "INCOMPLETE", "a line that is not a TronLink frame")
        let other = parts("0a" + String(repeating: "cd", count: 200), type: 1, size: 100)
        let conflict = refusedWith([p[0], other[0]].joined(separator: "\n"))
        eq(conflict?.kind, .otherRequest, "parts of two requests")
        eq(conflict?.error.key ?? "", "PublicProtocol.scan.otherRequest", "collector text")
        // Two single objects on two lines: the second wins (Android collector quirk, kept).
        t(mapped(V.V1_REQUEST + "\n" + V.V4_REQUEST) == ScanFixtures.vectorRequest("O-TL-V4-tip191-message"), "second single wins")

        section("paste: refusals carry their own text and arguments")
        let typed = refusedWith(#"{"address":"\#(V.TRON_0)","type":150,"hexList":["hello"]}"#)
        eq(typed?.error.key ?? "", "PublicProtocol.err.tronlinkType", "150")
        eq(typed?.error.args ?? [], [.int(150)], "150 args")
        eq(refusedWith(#"{"address":"\#(V.TRON_0)","type":101,"hexList":["ab"]}"#)?.error.key ?? "", "PublicProtocol.err.tronlinkBlindHash", "101")
        eq(refusedWith(#"{"address":"\#(V.TRON_0)","type":4,"hexList":["\#(V.V3_ENTRY)","\#(V.V3_ENTRY)"]}"#)?.error.args ?? [], [.int(2)], "multi 2")

        section("paste: every TokenPocket text is refused before the engine")
        var tp = V.tpRequestFrames + [V.tpRequest, V.TP_ANSWER_HEADER,
                                      "ethereum:signTransaction-version=1.0&protocol=TokenPocket&network=ethereum&chain_id=1&data={}",
                                      "bitcoin:signTransaction-version=1.0&protocol=TokenPocket&data={}",
                                      "solana:signTransaction-version=1.0&protocol=TokenPocket&data={}",
                                      "tron:signMessageV2-version=1.0&protocol=TokenPocket&data={}",
                                      "tp:multiFragment-version=2.0&protocol=TokenPocket&data={}",
                                      "tp:anything&protocol=TokenPocket",
                                      #"{"action":"coldWalletSign","signType":"tronSignTx","sign":"ab"}"#]
        tp.append(V.tpRequestFrames.joined(separator: "\n"))                 // all frames, one per line
        tp.append("  " + V.tpRequest + "  \n")
        tp.append(V.tpRequest + String(repeating: "x", count: 300_000))      // any length (the coordinator bounds bytes first)
        for text in tp {
            let e = refusedWith(text)
            eq(e?.kind, .unsupported, "TokenPocket kind: \(text.prefix(30))")
            eq(e?.error, BILPublicSignerErrors.tpUnsupported, "err.tpUnsupported: \(text.prefix(30))")
        }
        // A TokenPocket line after a PSBT line is the engine's (classified by the first line).
        t(isNil("cHNidP8BAFICAAAAAQ==\n" + V.TP_ANSWER_HEADER), "first line decides")

        section("paste: everything else is left to the engine")
        for text in ["cHNidP8BAFICAAAAAQ==", "70736274ff0100", "ur:crypto-psbt/1-3/lpad\nur:crypto-psbt/2-3/lpao",
                     "UR:CRYPTO-HDKEY/PTAOWKAXHDCLAO", "ur:crypto-seed/oead", "B$2P0100AAAA", "hello", "", "   ",
                     #"{"name":"x"}"#, #"{"action":1}"#, "tron:TXYZopYRdj2D9XRtbG411XZZ3kM5VkAeBf?amount=1", "bb_sign:abc"] {
            t(isNil(text), "nil → decodePayload: \(text.prefix(30))")
        }
        for paste in ScanFixtures.pastes { t(isNil(paste), "engine paste fixture \(paste.prefix(20))") }
        // A TronLink-looking object that is not a valid frame: the first line classifies as TronLink → the collector path.
        eq(refusedWith(#"{"hexList":"x"}"#)?.error.code ?? "", "INCOMPLETE", "malformed TronLink JSON → INCOMPLETE")
        eq(refusedWith(#"{"cN":1,"hexList":["ab"],"tN":2}"#)?.error.code ?? "", "INCOMPLETE", "a lone part → INCOMPLETE")
    }
}
