//  PPScanTronLinkTests.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Port of the app harness suite `scripts/public-protocol/tests/scan` (TronLinkTests.swift) to XCTest.
//
//  TronLinkTests.swift — TronLink frame / collector / mapper / answer codec / strict Transaction protobuf and the scan-side
//  error texts (ports of Android OtherWalletQrFormatsTest (TronLink part), OtherWalletCollectorsTest,
//  OtherWalletMappersTest, OtherWalletAnswersTest, OtherWalletErrorsTest; spec §13.2 #15).
//

import Foundation
import XCTest
import CryptoKit
@testable import OwnbitCore

extension PPScanSuite {

    private typealias V = OtherWalletVectors

    private static func hex(_ s: String) -> [UInt8] {
        return BILPublicHex.decode(s) ?? []
    }

    private static func frame(_ text: String) -> BILTronLinkFrame {
        guard let f = BILTronLinkQrFormat.parse(text) else {
            t(false, "not a TronLink frame: \(text.prefix(40))")
            return BILTronLinkFrame(json: BILJSONObject(), hexList: [], type: 0, address: nil, cN: nil, tN: nil, alpha: nil, tokenId: nil)
        }
        return f
    }

    /// TronLink's splitter (`SignTransactionNewModel.subSign`): `size`-character pieces of `h1&&&h2&&&…`.
    private static func tronLinkParts(_ entries: [String], type: Int, address: String = V.TRON_0, size: Int = 1000) -> [String] {
        let joined = Array(entries.map { $0 + "&&&" }.joined().utf16)
        let total = (joined.count + size - 1) / size
        return (1...total).map { i in
            var o = BILJSONObject()
            if i == 1 || i == total { o.set("address", .string(address)) }
            o.set("cN", .int(i))
            o.set("hexList", .array([.string(String(decoding: joined[((i - 1) * size)..<min(i * size, joined.count)], as: UTF16.self))]))
            o.set("tN", .int(total))
            o.set("type", .int(i == total ? type : 0))
            return BILStrictJSON.serialize(o)
        }
    }

    private static func tronLink(_ text: String) throws -> BILJSONObject {
        guard let f = BILTronLinkQrFormat.parse(text, maxChars: BILTronLinkQrFormat.maxRequestChars) else {
            throw BILOtherWalletRequestError.malformed(code: "TEST_NOT_TRONLINK")
        }
        return try BILTronLinkRequestMapper.map(BILTronLinkRequest.of(f))
    }

    private static func refusal(_ what: String, file: StaticString = #file, line: UInt = #line, _ body: () throws -> Void) -> BILOtherWalletRequestError? {
        do {
            try body()
            t(false, "\(what): did not throw", file: file, line: line)
        } catch let e as BILOtherWalletRequestError {
            return e
        } catch {
            t(false, "\(what): threw \(type(of: error))", file: file, line: line)
        }
        return nil
    }

    static func tronLinkTests() {
        let tlPhoto = #"{"amount":0,"address":"TMTjucQ73f32Yw4Xx8Gm1dH1mdFrFjn9Lb","amountStr":"0","type":99,"hexList":["0a1a5a18221654726f6e4c696e6b437573746f6d436f6e7472616374"]}"#

        section("tronlink frame: the owner's capture parses and keeps its key order")
        do {
            let f = frame(tlPhoto)
            eq(f.type, 99, "type")
            eq(f.address ?? "", "TMTjucQ73f32Yw4Xx8Gm1dH1mdFrFjn9Lb", "address")
            eq(f.hexList, ["0a1a5a18221654726f6e4c696e6b437573746f6d436f6e7472616374"], "hexList")
            t(!f.isPart, "not a part")
            eq(f.json.keys, ["amount", "address", "amountStr", "type", "hexList"], "key order")
            eq(BILStrictJSON.serialize(f.json), tlPhoto, "byte round trip")
            let android = #"{"address":"TUEZSdKsoDHQMeZwihtdoBiN46zxhGWYdH","cN":0,"hexList":["0a215a1f221d436f6c6457616c6c65744f776e6572566572696679436f6e7472616374"],"tN":0,"type":99}"#
            t(BILTronLinkQrFormat.parse(android)?.isPart == false, "Android shape is a single request")
            t(BILTronLinkQrFormat.parse(#"{"cN":1,"hexList":["a"],"type":1}"#)?.isPart == false, "cN 1 single request")
            t(BILTronLinkQrFormat.parse(#"{"cN":2,"hexList":["a"],"type":1}"#) == nil, "cN 2 single request")
            t(BILTronLinkQrFormat.parse(#"{"cN":2,"hexList":["a"],"tN":1}"#) == nil, "tN 1 with cN 2")
            t(BILTronLinkQrFormat.parse("  \n" + tlPhoto + "\n ") != nil, "trimmed")
            t(!f.description.contains("0a1a5a") && !f.description.contains("TMTju"), "description has no content")
            var dumped = ""
            dump(f, to: &dumped)
            t(!dumped.contains("0a1a5a") && !dumped.contains("TMTju") && !dumped.contains("amountStr"), "dump prints no content")
            t(Mirror(reflecting: f).children.isEmpty, "no mirror children")
        }

        section("tronlink frame: parts and what is not a TronLink frame")
        do {
            let part = BILTronLinkQrFormat.parse(#"{"address":"TUEZSdKsoDHQMeZwihtdoBiN46zxhGWYdH","cN":1,"hexList":["0a85&&&"],"tN":3,"type":0}"#)
            t(part?.isPart == true, "part")
            eq(part?.cN, 1, "cN")
            eq(part?.tN, 3, "tN")
            for (text, what) in [(#"{"cN":1,"hexList":["a","b"],"tN":2}"#, "a part carries one piece"),
                                 (#"{"cN":0,"hexList":["a"],"tN":2}"#, "cN 0 of a split request"),
                                 (#"{"cN":3,"hexList":["a"],"tN":2}"#, "cN above tN"),
                                 ("{}", "{}"),
                                 (#"{"hexList":"x","type":1}"#, "hexList string"),
                                 (#"{"hexList":[],"type":1}"#, "empty"),
                                 (#"{"hexList":[1],"type":1}"#, "number entry"),
                                 (#"{"hexList":["a"],"type":"1"}"#, "string type"),
                                 (#"{"hexList":["a"],"type":1.5}"#, "fraction"),
                                 (#"{"hexList":["a"],"type":-1}"#, "negative"),
                                 (#"{"hexList":["a"],"type":1e2}"#, "exponent"),
                                 (#"{"hexList":["a"],"type":01}"#, "leading zero (not strict JSON)"),
                                 (#"{"hexList":["a"],"type":2147483648}"#, "above Int32"),
                                 (#"{"hexList":["a"],"type":null}"#, "null type"),
                                 (#"{"hexList":["a"],"address":null}"#, "null address"),
                                 (#"{"hexList":["a"],"address":1}"#, "number address"),
                                 (#"{"hexList":["a"],"alpha":1}"#, "number alpha"),
                                 (#"{"hexList":["a"],"tokenId":true}"#, "bool tokenId"),
                                 (#"{"hexList":["a"],"cN":"1"}"#, "string cN"),
                                 (#"{"hexList":["a"],"hexList":["b"],"type":1}"#, "duplicate keys"),
                                 ("{\"hexList\":[" + Array(repeating: "\"a\"", count: 33).joined(separator: ",") + "]}", "33 entries"),
                                 ("[\"hexList\"]", "an array")] {
                t(BILTronLinkQrFormat.parse(text) == nil, what)
            }
            t(BILTronLinkQrFormat.parse(#"{"hexList":["a"],"type":2147483647}"#)?.type == 2147483647, "Int32.max type")
            t(BILTronLinkQrFormat.parse("{\"hexList\":[" + Array(repeating: "\"a\"", count: 32).joined(separator: ",") + "]}")?.hexList.count == 32, "32 entries")
            let big = "{\"hexList\":[\"" + String(repeating: "a", count: 4_300) + "\"],\"type\":1}"
            t(BILTronLinkQrFormat.parse(big) == nil, "one QR is at most 4300 characters")
            t(BILTronLinkQrFormat.parse(big, maxChars: BILTronLinkQrFormat.maxRequestChars) != nil, "a reassembled request may be larger")
            t(BILTronLinkQrFormat.looksLike(" {\"hexList\":1} "), "looksLike trims")
            t(!BILTronLinkQrFormat.looksLike("{\"hexlist\":1}"), "key is case-sensitive")
            t(!BILTronLinkQrFormat.looksLike("{"), "one char")
        }

        section("tronlink request: a part is not a request — of(part) fails closed (no trap), the mapper refuses it")
        do {
            let text = #"{"address":"TUEZSdKsoDHQMeZwihtdoBiN46zxhGWYdH","cN":1,"hexList":["0a1a5a18221654726f6e4c696e6b437573746f6d436f6e7472616374&&&"],"tN":2,"type":0}"#
            if let part = BILTronLinkQrFormat.parse(text, maxChars: BILTronLinkQrFormat.maxRequestChars) {
                t(part.isPart, "a part")
                let r = BILTronLinkRequest.of(part)
                eq(r.hexList, [], "no entries")
                t(!r.wasSplit, "not split")
                do {
                    _ = try BILTronLinkRequestMapper.map(r)
                    t(false, "mapped")
                } catch let e as BILOtherWalletRequestError {
                    eq(e.kind, .malformed, "malformed")
                    eq(e.error.code ?? "", "MALFORMED", "code")
                    eq(e.error.key, "PublicProtocol.err.qrMalformed", "text")
                } catch {
                    t(false, "error type \(type(of: error))")
                }
            } else {
                t(false, "the part parses")
            }
        }

        section("tronlink collector: a single QR completes at once and keeps the scanned object")
        do {
            let c = BILTronLinkCollector()
            if case .complete(let r)? = try? c.add(frame(V.V1_REQUEST)) {
                eq(BILStrictJSON.serialize(r.bean), V.V1_REQUEST, "bean")
                eq(r.type, 99, "type")
                t(!r.wasSplit, "not split")
                t(!r.description.contains(V.V1_ENTRY), "description has no content")
                var dumped = ""
                dump(r, to: &dumped)
                t(!dumped.contains(V.V1_ENTRY) && !dumped.contains(V.TRON_0) && !dumped.contains("hexList"), "dump prints no content")
                dumped = ""
                dump(BILTronLinkCollector.Step.complete(r), to: &dumped)
                t(!dumped.contains(V.V1_ENTRY), "dump of the step prints no content")
            } else {
                t(false, "single completes")
            }
            eq(c.received, 0, "a single QR is not stored")
        }

        section("tronlink collector: parts in any order, repeats ignored, the request rebuilt")
        do {
            let entry = "0a" + String(repeating: "ab", count: 1_200)
            let parts = tronLinkParts([entry], type: 14)
            eq(parts.count, 3, "3 parts")
            let c = BILTronLinkCollector()
            eq(try c.add(frame(parts[2])), .partial(received: 1, total: 3), "1/3")
            eq(try c.add(frame(parts[2])), .partial(received: 1, total: 3), "a repeat")
            eq(try c.add(frame(parts[0])), .partial(received: 2, total: 3), "2/3")
            if case .complete(let r)? = try? c.add(frame(parts[1])) {
                eq(r.hexList, [entry], "entry")
                eq(r.type, 14, "type")
                eq(r.address ?? "", V.TRON_0, "address")
                t(r.wasSplit, "split")
                eq(BILStrictJSON.serialize(r.bean), #"{"address":"\#(V.TRON_0)","type":14,"hexList":["\#(entry)"]}"#, "bean")
            } else {
                t(false, "complete")
            }
        }

        section("tronlink collector: bean keys (first-seen order, last part's type / alpha / tokenId)")
        do {
            let p1 = #"{"address":"\#(V.TRON_0)","cN":1,"extra":"x","hexList":["ab&&"],"tN":2,"type":0,"alpha":"q"}"#
            let p2 = #"{"cN":2,"hexList":["&"],"tN":2,"more":5,"type":7,"tokenId":""}"#
            let c = BILTronLinkCollector()
            _ = try? c.add(frame(p1))
            if case .complete(let r)? = try? c.add(frame(p2)) {
                eq(BILStrictJSON.serialize(r.bean), #"{"address":"\#(V.TRON_0)","extra":"x","type":7,"more":5,"tokenId":"","hexList":["ab"]}"#,
                   "alpha removed (not on the last part), type / tokenId from the last part, hexList last")
                eq(r.address ?? "", V.TRON_0, "address from part 1")
                t(r.alpha == nil, "alpha of the last part")
                eq(r.tokenId ?? "nil", "", "tokenId of the last part")
            } else {
                t(false, "complete")
            }
            // Address only on the last part.
            let q1 = #"{"cN":1,"hexList":["ab&&"],"tN":2,"type":0}"#
            let q2 = #"{"address":"\#(V.TRON_0)","cN":2,"hexList":["&"],"tN":2,"type":1}"#
            let c2 = BILTronLinkCollector()
            _ = try? c2.add(frame(q1))
            if case .complete(let r)? = try? c2.add(frame(q2)) {
                eq(r.address ?? "", V.TRON_0, "address of the last part")
                eq(BILStrictJSON.serialize(r.bean), #"{"type":1,"address":"\#(V.TRON_0)","hexList":["ab"]}"#, "address appended")
            } else {
                t(false, "complete 2")
            }
        }

        section("tronlink collector: parts of another request are refused")
        do {
            let a = tronLinkParts(["0a" + String(repeating: "ab", count: 700)], type: 1)
            let b = tronLinkParts(["0a" + String(repeating: "cd", count: 700)], type: 1)
            let c3 = tronLinkParts(["0a" + String(repeating: "ab", count: 1_600)], type: 1)
            let wrongLast = tronLinkParts(["0a" + String(repeating: "ab", count: 700)], type: 1, address: "TSeJkUh4Qv67VNFwY8LaAxERygNdy6NQZK")
            func other(_ what: String, _ first: String, _ second: String) {
                let c = BILTronLinkCollector()
                _ = try? c.add(frame(first))
                eq(refusal(what) { _ = try c.add(frame(second)) }?.kind, .otherRequest, what)
            }
            other("same cN, another piece", a[0], b[0])
            other("another part count", a[0], c3[2])
            other("first and last name different addresses", a[0], wrongLast[1])
            other("a single QR after a part", a[0], V.V1_REQUEST)
            let e = refusal("other text") { let c = BILTronLinkCollector(); _ = try c.add(frame(a[0])); _ = try c.add(frame(b[0])) }
            eq(e?.error.key ?? "", "PublicProtocol.scan.otherRequest", "text")
            eq(e?.error.code ?? "", "OTHER_REQUEST", "code")
            // Same piece but another object for the same cN (e.g. another type literal) is another request too.
            other("same piece, other object", #"{"cN":1,"hexList":["ab"],"tN":2,"type":0}"#, #"{"cN":1,"hexList":["ab"],"tN":2,"type":0,"x":1}"#)
            // A repeat with keys in another order is the same object (map equality).
            let c = BILTronLinkCollector()
            _ = try? c.add(frame(#"{"cN":1,"hexList":["ab"],"tN":2,"type":0}"#))
            eq(try c.add(frame(#"{"type":0,"tN":2,"hexList":["ab"],"cN":1}"#)), .partial(received: 1, total: 2), "reordered repeat")
            // Exact comparison: a canonically equivalent but different piece is another request.
            let c2 = BILTronLinkCollector()
            _ = try? c2.add(frame("{\"cN\":1,\"hexList\":[\"\u{00E9}\"],\"tN\":2}"))
            eq(refusal("decomposed twin") { _ = try c2.add(frame("{\"cN\":1,\"hexList\":[\"e\u{0301}\"],\"tN\":2}")) }?.kind, .otherRequest,
               "é precomposed vs decomposed are different pieces")
        }

        section("tronlink collector: limits and the join rule")
        do {
            eq(refusal("65 parts") { _ = try BILTronLinkCollector().add(frame(#"{"cN":1,"hexList":["ab"],"tN":65,"type":0}"#)) }?.kind, .tooLarge, "65 parts")
            let tl = refusal("65 parts code") { _ = try BILTronLinkCollector().add(frame(#"{"cN":1,"hexList":["ab"],"tN":65,"type":0}"#)) }
            eq(tl?.error.key ?? "", "PublicProtocol.err.tooLarge", "tooLarge key")
            eq(tl?.error.code ?? "", "LIMIT", "tooLarge code")
            t((try? BILTronLinkCollector().add(frame(#"{"cN":1,"hexList":["ab"],"tN":64,"type":0}"#))) != nil, "64 parts")
            let bigPiece = "{\"cN\":1,\"hexList\":[\"" + String(repeating: "a", count: 4_097) + "\"],\"tN\":2,\"type\":0}"
            eq(refusal("4097-char piece") { _ = try BILTronLinkCollector().add(frame(bigPiece)) }?.kind, .tooLarge, "4097-char piece")
            let okPiece = "{\"cN\":1,\"hexList\":[\"" + String(repeating: "a", count: 4_096) + "\"],\"tN\":2,\"type\":0}"
            t((try? BILTronLinkCollector().add(frame(okPiece))) != nil, "4096-char piece")
            // Two entries survive the join (the mapper refuses them later).
            let two = tronLinkParts(["0a" + String(repeating: "11", count: 400), "0a" + String(repeating: "22", count: 400)], type: 4)
            let c = BILTronLinkCollector()
            for p in two.dropLast() { _ = try? c.add(frame(p)) }
            if case .complete(let r)? = try? c.add(frame(two[two.count - 1])) { eq(r.hexList.count, 2, "2 entries") } else { t(false, "two complete") }
            // An empty entry (&&&&&&) is malformed.
            var empty = tronLinkParts(["0a" + String(repeating: "11", count: 600)], type: 1)
            empty[1] = empty[1].replacingOccurrences(of: "&&&\"]", with: "&&&&&&\"]")
            let c2 = BILTronLinkCollector()
            _ = try? c2.add(frame(empty[0]))
            let m = refusal("empty entry") { _ = try c2.add(frame(empty[1])) }
            eq(m?.kind, .malformed, "empty entry")
            eq(m?.error.key ?? "", "PublicProtocol.err.qrMalformed", "malformed key")
            eq(m?.error.code ?? "", "MALFORMED", "malformed code")
            // No trailing separator: one entry; the trailing one is dropped once.
            func joinOf(_ pieces: [String]) -> [String]? {
                let c = BILTronLinkCollector()
                var out: [String]?
                for (i, piece) in pieces.enumerated() {
                    let o = BILJSONObject([("cN", .int(i + 1)), ("hexList", .array([.string(piece)])), ("tN", .int(pieces.count))])
                    if case .complete(let r)? = try? c.add(frame(BILStrictJSON.serialize(o))) { out = r.hexList }
                }
                return out
            }
            eq(joinOf(["ab", "cd"]) ?? [], ["abcd"], "no separator")
            eq(joinOf(["ab&&&", "cd&&&"]) ?? [], ["ab", "cd"], "two entries")
            t(joinOf(["ab&&&", "&&&"]) == nil, "trailing empty after a dropped one is malformed")
            eq(joinOf(["a&&&&", "b"]) ?? [], ["a", "&b"], "Kotlin split is left to right, non-overlapping")
            t(joinOf(["&&&", "ab"]) == nil, "leading empty entry")
            // Joined over 131 072 characters: too large (33 pieces of 4096 = 135 168).
            let bigParts = (1...33).map { i -> String in
                BILStrictJSON.serialize(BILJSONObject([("cN", .int(i)), ("hexList", .array([.string(String(repeating: "a", count: 4_096))])), ("tN", .int(33))]))
            }
            let c3 = BILTronLinkCollector()
            var tooLarge: BILOtherWalletRequestError?
            for p in bigParts {
                do { _ = try c3.add(frame(p)) } catch let e as BILOtherWalletRequestError { tooLarge = e } catch {}
            }
            eq(tooLarge?.kind, .tooLarge, "joined > 131072")
        }

        section("tronlink mapper: V1 to V4 map to exactly the engine requests of the golden vectors")
        do {
            for (id, text) in [("O-TL-V1-ownership-ios", V.V1_REQUEST), ("O-TL-V3-trx-transfer", V.V3_REQUEST), ("O-TL-V4-tip191-message", V.V4_REQUEST)] {
                let expected = ScanFixtures.vectorRequest(id)
                t(expected != nil, "\(id) present")
                let mapped = try? tronLink(text)
                t(mapped != nil && mapped == expected, "\(id): mapped == vector request")
                eq(mapped.map { BILStrictJSON.serialize($0) } ?? "", expected.map { BILStrictJSON.serialize($0) } ?? "-", "\(id): byte-identical")
            }
            let v2 = try? tronLink(V.V2_REQUEST)
            t(v2?.obj("transaction") != nil && v2?.obj("transaction") == ScanFixtures.vectorRequest("O-TL-V2-ownership-android")?.obj("transaction"), "V2 transaction")
            eq(v2?.obj("transport")?.int("tronlinkType"), 99, "V2 tronlinkType")
            let payload = BILPublicHex.decode(v2?.obj("transport")?.str("payloadBytes") ?? "") ?? []
            eq(String(decoding: payload, as: UTF8.self), V.V2_REQUEST, "V2 payloadBytes = the scanned object")
            // A pretty-printed request maps to the compact bytes (re-serialised, not the scanned text).
            let pretty = "{\n  \"amount\": 0,\n  \"address\": \"\(V.TRON_0)\",\n  \"amountStr\": \"0\",\n  \"type\": 99,\n  \"hexList\": [\"\(V.V1_ENTRY)\"]\n}"
            t((try? tronLink(pretty)) == ScanFixtures.vectorRequest("O-TL-V1-ownership-ios"), "pretty-printed V1 maps like V1")
            // A big number literal is echoed as written.
            let bigNumber = #"{"amount":9007199254740993,"address":"\#(V.TRON_0)","type":1,"hexList":["\#(V.V3_ENTRY)"]}"#
            let bn = BILPublicHex.decode((try? tronLink(bigNumber))?.obj("transport")?.str("payloadBytes") ?? "") ?? []
            eq(String(decoding: bn, as: UTF8.self), bigNumber, "9007199254740993 echoed")
            // sha256(raw_data) of V1.
            let raw = hex(ScanFixtures.vectorRequest("O-TL-V1-ownership-ios")?.obj("transaction")?.str("raw_data_hex") ?? "")
            eq(pubHex(SHA256.hash(data: Data(raw))), "4306597447f1aa4dc115d7a753141f1f3a3ba0995f5f2ddb8d0fdb23b791cc96", "V1 sha256(raw_data)")
        }

        section("tronlink mapper: messages — text, hex and signed byte lists")
        do {
            func message(_ type: Int, _ entry: String) throws -> BILJSONObject {
                return try tronLink(#"{"address":"\#(V.TRON_0)","type":\#(type),"hexList":["\#(entry)"]}"#)
            }
            func pair(_ o: BILJSONObject?) -> String { return (o?.str("message") ?? "-") + " / " + (o?.str("encoding") ?? "-") }
            eq(pair(try? message(102, "hello ownbit")), "hello ownbit / utf8", "102")
            eq(pair(try? message(103, "0x68656C6C6F")), "68656c6c6f / hex", "103 0x")
            eq(pair(try? message(103, "0X68656C6C6F")), "68656c6c6f / hex", "103 0X")
            eq(pair(try? message(103, "68656c6c6f")), "68656c6c6f / hex", "103 no prefix")
            eq(pair(try? message(103, "0x0Xab")), "ab / hex", "103 0x then 0X removed")
            eq(pair(try? message(104, "-1,0,127,-128")), "ff007f80 / hex", "104")
            eq(pair(try? message(104, "255")), "ff / hex", "104 255")
            eq(pair(try? message(104, " 1 , 2 ")), "0102 / hex", "104 trims parts")
            eq(pair(try? message(102, " spaced ")), " spaced  / utf8", "102 not trimmed")
            let m = try? message(102, "hello ownbit")
            eq(m?.keys ?? [], ["chain", "address", "kind", "message", "encoding", "transport"], "message key order")
            eq(m?.obj("transport")?.keys ?? [], ["type", "payloadEncoding", "payloadBytes", "tronlinkType"], "transport key order")
            for (type, entry) in [(103, "0x123"), (103, "zz"), (103, "0x"), (104, "1,,2"), (104, "256"), (104, "-129"), (104, "1.5"),
                                  (104, "+1"), (104, "0001"), (104, ""), (102, "")] {
                let e = refusal("\(type) \(entry)") { _ = try message(type, entry) }
                eq(e?.error.key ?? "", "PublicProtocol.err.qrMalformed", "\(type) \(entry)")
                eq(e?.kind, .malformed, "\(type) \(entry) kind")
            }
            t((try? message(102, String(repeating: "a", count: 8_192))) != nil, "102 8192 bytes")
            t((try? message(102, String(repeating: "a", count: 8_193))) == nil, "102 8193 bytes")
            t((try? message(102, String(repeating: "é", count: 4_097))) == nil, "102 counts UTF-8 bytes")
            t((try? message(103, String(repeating: "ab", count: 8_192))) != nil, "103 8192 bytes")
            t((try? message(103, String(repeating: "ab", count: 8_193))) == nil, "103 8193 bytes")
            t((try? message(104, Array(repeating: "1", count: 8_192).joined(separator: ","))) != nil, "104 8192 parts")
            t((try? message(104, Array(repeating: "1", count: 8_193).joined(separator: ","))) == nil, "104 8193 parts")
        }

        section("tronlink mapper: refusals before the engine")
        do {
            func with(_ type: Int, _ entries: String = "\"\(V.V3_ENTRY)\"", extra: String = "") -> String {
                return #"{"address":"\#(V.TRON_0)","type":\#(type),"hexList":[\#(entries)]\#(extra)}"#
            }
            func key(_ text: String) -> String { return refusal(text) { _ = try tronLink(text) }?.error.key ?? "-" }
            eq(key(with(101, "\"" + String(repeating: "ab", count: 32) + "\"")), "PublicProtocol.err.tronlinkBlindHash", "101")
            eq(key(with(17)), "PublicProtocol.err.tronlinkBlindHash", "17")
            eq(key(with(98, "\"abcd\"")), "PublicProtocol.err.tronlinkMessageV1", "98")
            eq(key(with(15)), "PublicProtocol.err.tronlinkShielded", "15")
            eq(key(with(1, extra: ",\"alpha\":\"ab\"")), "PublicProtocol.err.tronlinkShielded", "alpha")
            eq(key(with(1, extra: ",\"tokenId\":\"1000001\"")), "PublicProtocol.err.tronlinkShielded", "tokenId")
            t((try? tronLink(with(1, extra: ",\"alpha\":\"\",\"tokenId\":\"\""))) != nil, "empty alpha / tokenId are not shielded")
            let codes = [(with(101, "\"ab\""), "TRONLINK_BLIND_HASH"), (with(98, "\"ab\""), "TRONLINK_MESSAGE_V1"), (with(15), "TRONLINK_SHIELDED")]
            for (text, code) in codes { eq(refusal(code) { _ = try tronLink(text) }?.error.code ?? "", code, code) }
            let multi = refusal("multi") { _ = try tronLink(with(4, "\"\(V.V3_ENTRY)\",\"\(V.V3_ENTRY)\"")) }
            eq(multi?.error.key ?? "", "PublicProtocol.err.tronlinkMulti", "multi")
            eq(multi?.error.args ?? [], [.int(2)], "multi args")
            eq(multi?.kind, .unsupported, "multi kind")
            eq(multi?.error.code ?? "", "TRONLINK_MULTI", "multi code")
            // Shielded is checked before multi, multi before the address.
            eq(key(#"{"type":15,"hexList":["a","b"]}"#), "PublicProtocol.err.tronlinkShielded", "order: shielded first")
            eq(key(#"{"type":1,"hexList":["a","b"]}"#), "PublicProtocol.err.tronlinkMulti", "order: multi before address")
            // Type 99 and the placeholder must agree.
            let i1 = refusal("99 with a transfer") { _ = try tronLink(with(99)) }
            eq(i1?.error.key ?? "", "PublicProtocol.err.integrity", "99 with a transfer")
            eq(i1?.kind, .malformed, "integrity kind")
            eq(i1?.error.code ?? "", "INTEGRITY", "integrity code")
            eq(key(with(1, "\"\(V.V1_ENTRY)\"")), "PublicProtocol.err.integrity", "placeholder with type 1")
            eq(key(with(150, "\"\(V.V1_ENTRY)\"")), "PublicProtocol.err.integrity", "placeholder with type 150")
            // An unknown page above 99 whose entry is not a transaction: named with its number.
            let unknown = refusal("150") { _ = try tronLink(with(150, "\"hello\"")) }
            eq(unknown?.error.key ?? "", "PublicProtocol.err.tronlinkType", "150")
            eq(unknown?.error.args ?? [], [.int(150)], "150 args")
            eq(unknown?.error.code ?? "", "TRONLINK_TYPE", "150 code")
            eq(unknown?.kind, .unsupported, "150 kind")
            eq(key(with(99, "\"hello\"")), "PublicProtocol.err.qrMalformed", "99 not a transaction → malformed (not > 99)")
            t((try? tronLink(with(150))) != nil, "150 with a real transaction maps (the engine judges)")
            for text in [#"{"type":1,"hexList":["\#(V.V3_ENTRY)"]}"#,
                         #"{"address":"TUEZSdKsoDHQMeZwihtdoBiN46zxhGWYdx","type":1,"hexList":["\#(V.V3_ENTRY)"]}"#,
                         #"{"address":"0x9858EfFD232B4033E47d90003D41EC34EcaEda94","type":1,"hexList":["\#(V.V3_ENTRY)"]}"#,
                         #"{"address":"41c8599111f29c1e1e061265b4af93ea1f274ad78a","type":1,"hexList":["\#(V.V3_ENTRY)"]}"#,
                         #"{"address":" \#(V.TRON_0)","type":1,"hexList":["\#(V.V3_ENTRY)"]}"#,
                         with(1, "\"\(V.V3_ENTRY)2a00\""), with(1, "\"0x\(V.V3_ENTRY)\""), with(1, "\"\(V.V3_ENTRY)0\""),
                         with(1, "\"\(V.V3_ENTRY) \""), with(1, "\"\""), with(1, "\"\(V.V3_ENTRY)1240\(String(V.V3_SIG.prefix(128)))\"")] {
                eq(refusal(text) { _ = try tronLink(text) }?.kind, .malformed, "malformed: \(text.prefix(50))")
            }
            let upper = try? tronLink(with(1, "\"\(V.V3_ENTRY.uppercased())\""))
            eq(upper?.obj("transaction")?.str("raw_data_hex") ?? "", String(V.V3_ENTRY.dropFirst(6)), "upper-case entry, lower-case raw")
        }

        section("tronlink mapper: a transaction that already carries signatures passes them on")
        do {
            let signed = V.V3_ENTRY + "1241" + V.V3_SIG
            let r = try? tronLink(#"{"address":"\#(V.TRON_0)","type":7,"hexList":["\#(signed)"]}"#)
            eq(r?.obj("transaction").map { BILStrictJSON.serialize($0["signature"] ?? .null) } ?? "", "[\"\(V.V3_SIG)\"]", "signature passed on")
            eq(r?.obj("transaction")?.str("raw_data_hex") ?? "", String(V.V3_ENTRY.dropFirst(6)), "raw")
            eq(r?.obj("transaction")?.keys ?? [], ["raw_data_hex", "signature"], "transaction keys")
            t(BILTronLinkRequestMapper.ownershipProofName(hex("5a18221654726f6e4c696e6b437573746f6d436f6e7472616374")) == "TronLinkCustomContract", "proof 1")
            t(BILTronLinkRequestMapper.ownershipProofName(hex("5a1f221d436f6c6457616c6c65744f776e6572566572696679436f6e7472616374")) == "ColdWalletOwnerVerifyContract", "proof 2")
            t(BILTronLinkRequestMapper.ownershipProofName(hex("5a0922074f776e62697458")) == nil, "other name")
            t(BILTronLinkRequestMapper.ownershipProofName(hex("5a18221654726f6e4c696e6b437573746f6d436f6e747261637400")) == nil, "trailing byte")
            t(BILTronLinkRequestMapper.entryBytes("") == nil, "empty entry")
            t(BILTronLinkRequestMapper.entryBytes("0x00") == nil, "0x entry")
            t(BILTronLinkRequestMapper.entryBytes("abc") == nil, "odd entry")
            eq(BILTronLinkRequestMapper.entryBytes("ABcd") ?? [], [0xab, 0xcd], "mixed case")
            t(BILTronLinkRequestMapper.entryBytes("ab\u{FF10}") == nil, "full-width digit")
        }

        section("tronlink answers: byte for byte the V1, V3 and V4 answers")
        do {
            func bean(_ text: String) -> BILJSONObject { return frame(text).json }
            let v1 = BILTronLinkAnswerCodec.signedTransaction(tx: hex(V.V1_ENTRY), signature: hex(V.V1_SIG))
            eq(v1.map { BILTronLinkAnswerCodec.encode(bean(V.V1_REQUEST), signed: [$0]) } ?? [], [V.V1_ANSWER], "V1 answer")
            eq(V.V1_ANSWER.utf16.count, 290, "290 chars")
            eq((v1 ?? "").utf16.count, 190, "190-char entry")
            let v3 = BILTronLinkAnswerCodec.signedTransaction(tx: hex(V.V3_ENTRY), signature: hex(V.V3_SIG))
            eq(v3.map { BILTronLinkAnswerCodec.encode(bean(V.V3_REQUEST), signed: [$0]) } ?? [], [V.V3_ANSWER], "V3 answer")
            let engineV4 = "99b4b65e883463501e600b497cf7293fe2ea7e143c5390a7d57162818a567f7762ef7b8a69a01a3654deb4c73e81263b29b151e3dd2ae91f464f3a3c2aac255001"
            eq(BILTronLinkAnswerCodec.signedMessage(signature: hex(engineV4)) ?? "", V.V4_MESSAGE_SIGNATURE, "V4 message signature")
            eq(BILTronLinkAnswerCodec.encode(bean(V.V4_REQUEST), signed: [V.V4_MESSAGE_SIGNATURE]), [V.V4_ANSWER], "V4 answer")
            eq(BILTronLinkAnswerCodec.encode(bean(V.V2_REQUEST), signed: ["ab"]), [#"{"address":"\#(V.TRON_0)","cN":0,"hexList":["ab"],"tN":0,"type":99}"#], "Android shape echoed")
            // answerBean keeps the position and every literal.
            let b = BILTronLinkAnswerCodec.answerBean(bean(#"{"a":1.50,"hexList":["x"],"z":9007199254740993}"#), signed: ["y", "w"])
            eq(BILStrictJSON.serialize(b), #"{"a":1.50,"hexList":["y","w"],"z":9007199254740993}"#, "answerBean in place")
            // Refused inputs never give a frame.
            eq(BILTronLinkAnswerCodec.encode(bean(V.V1_REQUEST), signed: []), [], "no entries")
            eq(BILTronLinkAnswerCodec.encode(bean(V.V1_REQUEST), signed: [""]), [], "empty entry")
            eq(BILTronLinkAnswerCodec.encode(bean(V.V1_REQUEST), signed: ["a&&&b"]), [], "entry with the separator")
            eq(BILTronLinkAnswerCodec.encode(BILJSONObject([("address", .string(V.TRON_0))]), signed: ["ab"]), [], "one QR needs hexList")
            // Signature checks.
            t(BILTronLinkAnswerCodec.signedMessage(signature: Array(hex(engineV4).prefix(64))) == nil, "64-byte signature")
            var rec2 = hex(engineV4); rec2[64] = 2
            t(BILTronLinkAnswerCodec.signedMessage(signature: rec2) == nil, "recId 2")
            var rec1 = hex(engineV4); rec1[64] = 1
            t(BILTronLinkAnswerCodec.signedMessage(signature: rec1)?.hasSuffix("1c") == true, "recId 1 → v 0x1c")
            t(BILTronLinkAnswerCodec.signedTransaction(tx: hex(V.V1_ENTRY), signature: Array(hex(V.V1_SIG).prefix(64))) == nil, "64-byte tx signature")
            t(BILTronLinkAnswerCodec.signedTransaction(tx: hex(V.V1_ENTRY) + [0x2a, 0x00], signature: hex(V.V1_SIG)) == nil, "not a strict tx")
        }

        section("tronlink answers: above 1000 characters, numbered parts in TronLink's field order")
        do {
            let request = frame(V.V3_REQUEST).json
            func entry(_ joinedLength: Int) -> String { return String(repeating: "a", count: joinedLength - 3) }
            eq(BILTronLinkAnswerCodec.encode(request, signed: [entry(999)]).count, 1, "999 → 1")
            eq(BILTronLinkAnswerCodec.encode(request, signed: [entry(1_000)]).count, 1, "exactly 1000 stays one code")
            let two = BILTronLinkAnswerCodec.encode(request, signed: [entry(1_001)])
            eq(two.count, 2, "1001 → 2")
            eq(two.first ?? "", #"{"address":"\#(V.TRON_0)","cN":1,"hexList":["\#(String(repeating: "a", count: 998))&&"],"tN":2,"type":0}"#, "part 1")
            eq(two.last ?? "", #"{"address":"\#(V.TRON_0)","cN":2,"hexList":["&"],"tN":2,"type":1}"#, "part 2")
            eq((try? BILTronLinkAnswerCodec.decode(two))?.hexList ?? [], [entry(1_001)], "decode 2")
            let three = BILTronLinkAnswerCodec.encode(request, signed: [entry(2_500)])
            eq(three.count, 3, "2500 → 3")
            t(BILStrictJSON.parseObject(three[1])?.contains("address") == false, "the middle part names no address")
            let back = try? BILTronLinkAnswerCodec.decode(three)
            eq(back?.hexList ?? [], [entry(2_500)], "decode 3")
            eq(back?.type, 1, "type")
            eq(back?.address ?? "", V.TRON_0, "address")
            // Two entries across parts.
            let pair = BILTronLinkAnswerCodec.encode(request, signed: [entry(600), entry(600)])
            eq(pair.count, 2, "2 entries in 2 parts")
            eq((try? BILTronLinkAnswerCodec.decode(pair))?.hexList ?? [], [entry(600), entry(600)], "2 entries back")
            // Type: the request's integer type on the last part; a string / fraction type → 0; no address → none.
            let noAddress = BILTronLinkAnswerCodec.encode(BILJSONObject([("type", .string("5")), ("hexList", .array([]))]), signed: [entry(1_500)])
            eq(noAddress.last ?? "", #"{"cN":2,"hexList":["\#(String(repeating: "a", count: 497))&&&"],"tN":2,"type":0}"#, "string type → 0, no address")
            let fraction = BILTronLinkAnswerCodec.encode(BILJSONObject([("type", .number("1.5")), ("hexList", .array([]))]), signed: [entry(1_500)])
            t(fraction.last?.hasSuffix(#""type":0}"#) == true, "fraction type → 0")
            let negative = BILTronLinkAnswerCodec.encode(BILJSONObject([("type", .number("-3")), ("hexList", .array([]))]), signed: [entry(1_500)])
            t(negative.last?.hasSuffix(#""type":-3}"#) == true, "negative type echoed (Kotlin toIntOrNull)")
            // Read back: missing part, frames after the last part, unreadable frame, nothing.
            t((try? BILTronLinkAnswerCodec.decode(Array(three.dropLast()))) == nil, "missing part")
            t((try? BILTronLinkAnswerCodec.decode([three[0], three[1], three[2], three[2]])) == nil, "frame after completion")
            t((try? BILTronLinkAnswerCodec.decode([three[0], "x", three[2]])) == nil, "unreadable frame")
            t((try? BILTronLinkAnswerCodec.decode([])) == nil, "no frames")
            do {
                _ = try BILTronLinkAnswerCodec.decode(Array(three.dropLast()))
            } catch let e as BILTronLinkAnswerCodec.DecodeError {
                eq(e.what, "incomplete answer", "incomplete reason")
                t(!e.description.contains("aaaa"), "decode error prints no content")
            } catch {
                t(false, "decode error type")
            }
            // A shuffled answer still decodes (the order rule is the verifier's: parse(frame[i]).cN == i + 1).
            eq((try? BILTronLinkAnswerCodec.decode([three[2], three[0], three[1]]))?.hexList ?? [], [entry(2_500)], "any order completing at the last frame")
            t((try? BILTronLinkAnswerCodec.decode([three[0], three[1], three[2], three[0]])) == nil, "a repeat after the completion refuses")
        }

        section("tron proto: strict Transaction split / encode / append")
        do {
            let v1 = hex(V.V1_ENTRY)
            let s1 = BILTronTransactionProto.split(v1)
            eq(s1?.raw ?? [], hex("5a18221654726f6e4c696e6b437573746f6d436f6e7472616374"), "V1 raw")
            eq(s1?.signatures.count, 0, "V1 no signatures")
            let s3 = BILTronTransactionProto.split(hex(V.V3_ENTRY))
            eq(s3?.raw ?? [], hex(String(V.V3_ENTRY.dropFirst(6))), "V3 raw (multi-byte length)")
            let appended = BILTronTransactionProto.appendSignature(hex(V.V3_ENTRY), hex(V.V3_SIG))
            eq(appended ?? [], hex(V.V3_ENTRY + "1241" + V.V3_SIG), "append = tx ‖ 12 41 ‖ sig")
            eq(BILTronTransactionProto.split(appended ?? [])?.signatures ?? [], [hex(V.V3_SIG)], "split reads the signature back")
            t(BILTronTransactionProto.split([]) == nil, "empty")
            t(BILTronTransactionProto.split([0x12, 0x00]) == nil, "field 2 first")
            t(BILTronTransactionProto.split([0x0a, 0x00]) == nil, "raw length 0")
            t(BILTronTransactionProto.split([0x0a, 0x02, 0x01]) == nil, "raw beyond the end")
            t(BILTronTransactionProto.split([0x0a, 0x81, 0x00, 0x01]) == nil, "non-minimal length")
            t(BILTronTransactionProto.split([0x0a, 0x80]) == nil, "unterminated varint")
            t(BILTronTransactionProto.split([0x0a, 0x80, 0x80, 0x80, 0x80, 0x80, 0x01]) == nil, "6-byte varint")
            t(BILTronTransactionProto.split([0x0a, 0xff, 0xff, 0xff, 0xff, 0x0f]) == nil, "length above Int32")
            t(BILTronTransactionProto.split(v1 + [0x0a, 0x01, 0x00]) == nil, "a second field 1")
            t(BILTronTransactionProto.split(v1 + [0x2a, 0x00]) == nil, "field 5 (ret)")
            t(BILTronTransactionProto.split(v1 + [0x12, 0x40] + [UInt8](repeating: 1, count: 64)) == nil, "64-byte signature")
            t(BILTronTransactionProto.split(v1 + [0x12, 0x41] + [UInt8](repeating: 1, count: 64)) == nil, "truncated signature")
            let sig = [UInt8](repeating: 7, count: 65)
            let with32 = (0..<32).reduce(v1) { acc, _ in acc + [0x12, 0x41] + sig }
            eq(BILTronTransactionProto.split(with32)?.signatures.count, 32, "32 signatures")
            t(BILTronTransactionProto.split(with32 + [0x12, 0x41] + sig) == nil, "33 signatures")
            t(BILTronTransactionProto.appendSignature(with32, sig) != nil, "append the 33rd (encode allows 33)")
            let raw65536 = [UInt8](repeating: 0x5a, count: 65_536)
            let big = BILTronTransactionProto.encode(raw: raw65536, signatures: [])
            eq(Array(big?.prefix(4) ?? []), [0x0a, 0x80, 0x80, 0x04], "65536 = 80 80 04")
            eq(BILTronTransactionProto.split(big ?? [])?.raw.count, 65_536, "max raw")
            t(BILTronTransactionProto.encode(raw: raw65536 + [0], signatures: []) == nil, "raw too large")
            t(BILTronTransactionProto.encode(raw: [], signatures: []) == nil, "raw empty")
            t(BILTronTransactionProto.encode(raw: [1], signatures: [[1]]) == nil, "short signature")
            t(BILTronTransactionProto.encode(raw: [1], signatures: Array(repeating: sig, count: 34)) == nil, "34 signatures")
            eq(BILTronTransactionProto.encode(raw: [0x01], signatures: [sig]) ?? [], [0x0a, 0x01, 0x01, 0x12, 0x41] + sig, "encode")
            eq(BILTronTransactionProto.encode(raw: [UInt8](repeating: 0, count: 127), signatures: []).map { Array($0.prefix(2)) } ?? [], [0x0a, 0x7f], "127 one byte")
            eq(BILTronTransactionProto.encode(raw: [UInt8](repeating: 0, count: 128), signatures: []).map { Array($0.prefix(3)) } ?? [], [0x0a, 0x80, 0x01], "128 two bytes")
            t(BILTronTransactionProto.appendSignature(v1, Array(sig.prefix(64))) == nil, "append a 64-byte signature")
            t(!(s1?.description.contains("5a18") ?? true), "split description prints sizes only")
            if let split = s1 {
                var dumped = ""
                dump(split, to: &dumped)
                eq(dumped.split(separator: "\n").count, 1, "split dump is one line (no bytes)")
                t(Mirror(reflecting: split).children.isEmpty, "split: no mirror children")
            } else {
                t(false, "v1 splits")
            }
        }

        section("scan errors: TokenPocket gets the one not-supported message (OtherWalletErrorsTest)")
        do {
            let texts = OtherWalletVectors.tpRequestFrames + [
                OtherWalletVectors.tpRequest, OtherWalletVectors.TP_ANSWER_HEADER,
                "ethereum:signTransaction-version=1.0&protocol=TokenPocket&network=ethereum&chain_id=1&data={}",
                "bitcoin:signTransaction-version=1.0&protocol=TokenPocket&data={}",
                "tron:signMessageV2-version=1.0&protocol=TokenPocket&data={}",
                "tron:signAndSendTransaction-version=1.0&protocol=TokenPocket&network=tron&chain_id=1&data={}",
                #"{"action":"coldWalletSign","signType":"tronSignTx","sign":"ab"}"#,
            ]
            for text in texts {
                let k = BILPublicQrFormat.classify(text)
                eq(k, .tpUnsupported, String(text.prefix(30)))
                let e = BILPublicScanErrors.unsupported(k)
                eq(e.key, "PublicProtocol.err.tpUnsupported", "tpUnsupported key")
                eq(e.code ?? "", "TP_UNSUPPORTED", "tpUnsupported code")
            }
            eq(BILPublicScanErrors.unsupported(.tpUnsupported), BILPublicSignerErrors.tpUnsupported, "TOKENPOCKET")
            eq(BILPublicScanErrors.unsupported(.unsupportedUr).key, "PublicProtocol.err.unsupportedUr", "unsupported UR")
            eq(BILPublicScanErrors.unsupported(.unsupportedUr).code ?? "", "UNSUPPORTED", "unsupported UR code")
            eq(BILPublicScanErrors.unsupported(nil).key, "PublicProtocol.err.unsupportedUr", "nil kind")
            eq(BILPublicScanErrors.wrongDirection(.signatureUr), "PublicProtocol.err.signatureCode", "signature")
            eq(BILPublicScanErrors.wrongDirection(.pairingUr), "PublicProtocol.err.pairingCode", "pairing")
            eq(BILPublicScanErrors.wrongDirection(nil), "PublicProtocol.err.pairingCode", "nil → pairing")
            let table: [(BILGateReason, BILPublicQrKind?, String?)] = [
                (.tooLarge, nil, "PublicProtocol.err.tooLarge"), (.sessionFull, nil, "PublicProtocol.err.tooLarge"),
                (.malformed, nil, "PublicProtocol.err.qrMalformed"), (.wrongDirection, .signatureUr, "PublicProtocol.err.signatureCode"),
                (.wrongDirection, .pairingUr, "PublicProtocol.err.pairingCode"), (.unsupported, .unsupportedUr, "PublicProtocol.err.unsupportedUr"),
                (.otherRequest, nil, "PublicProtocol.scan.otherRequest"), (.timedOut, nil, "PublicProtocol.err.scanTimeout"),
                (.empty, nil, nil), (.notPublic, nil, nil),
            ]
            for (reason, k, key) in table { eq(BILPublicScanErrors.scan(reason, kind: k), key, "scan(\(reason))") }
        }

        section("scan errors: every key exists in PublicProtocol.strings (en) with matching placeholders")
        do {
            let n = pubLoadStrings(tables: ["PublicProtocol"])
            t(n >= 17, "English test templates installed (\(n); the app loaded its full PublicProtocol.strings)")
            let keys = ["PublicProtocol.err.tooLarge", "PublicProtocol.err.qrMalformed", "PublicProtocol.err.pairingCode",
                        "PublicProtocol.err.signatureCode", "PublicProtocol.err.unsupportedUr", "PublicProtocol.scan.otherRequest",
                        "PublicProtocol.err.scanTimeout", "PublicProtocol.err.engineUnavailable", "PublicProtocol.err.tpUnsupported",
                        "PublicProtocol.err.tronlinkShielded", "PublicProtocol.err.tronlinkBlindHash", "PublicProtocol.err.tronlinkMessageV1",
                        "PublicProtocol.err.integrity"]
            for k in keys {
                let text = BILPublicText.string(k)
                t(text != k && !text.isEmpty, "\(k) resolves")
                t(!text.contains("%"), "\(k) has no placeholder")
            }
            eq(BILPublicSignError("PublicProtocol.err.tronlinkType", args: [.int(150)]).text,
               "Ownbit can't sign this TronLink request type (150) yet.", "tronlinkType with 150")
            eq(BILPublicSignError("PublicProtocol.err.tronlinkMulti", args: [.int(2)]).text,
               "This TronLink request holds 2 transactions. Ownbit signs only one transaction per request.", "tronlinkMulti with 2")
            t(!BILPublicText.string("PublicProtocol.err.tpUnsupported").contains("BitSigner"), "no BitSigner in the text")
            BILStubStrings.reset()
        }
    }
}
