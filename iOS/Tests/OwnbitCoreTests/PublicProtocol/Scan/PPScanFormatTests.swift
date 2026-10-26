//  PPScanFormatTests.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Port of the app harness suite `scripts/public-protocol/tests/scan` (FormatTests.swift) to XCTest.
//
//  FormatTests.swift — classification (port of Android PublicQrFormatTest, OtherWalletQrFormatsTest classification /
//  TokenPocket / strict JSON parts, ScanPayloadClassifierTest public section) + scanner badge detail + C-GEN-17.
//

import Foundation
import XCTest
@testable import OwnbitCore

extension PPScanSuite {

    private static func kind(_ text: String) -> BILPublicQrKind? {
        return BILPublicQrFormat.classify(text)
    }

    private static func name(_ k: BILPublicQrKind?) -> String {
        return k.map { "\($0)" } ?? "nil"
    }

    static func formatTests() {
        section("format: sign-request URs single and multi-part")
        for type in BILPublicQrFormat.signRequestUrTypes.sorted() {
            eq(name(kind("ur:\(type)/oeadtpdagdmycnhy")), "urSignRequest", type)
            eq(name(kind("UR:\(type.uppercased())/OEADTPDAGDMYCNHY")), "urSignRequest", type)
            eq(name(kind("ur:\(type)/1-3/lpadaxcfad")), "urPart", type)
            eq(name(kind("UR:\(type.uppercased())/29-20/LPCSCAB")), "urPart", type)
        }
        eq(name(kind("  Ur:Crypto-Psbt/7-20/LPATBBCF\n")), "urPart", "mixed case + whitespace")
        eq(name(kind("ur:crypto-psbt/1-3")), "urSignRequest", "no second slash")
        eq(name(kind("ur:crypto-psbt/a-3/lpad")), "urSignRequest", "non-digit seq")
        eq(name(kind("ur:crypto-psbt/1-/lpad")), "urSignRequest", "empty count")
        eq(name(kind("ur:crypto-psbt/1-3/")), "urSignRequest", "slash is the last char")
        eq(name(kind("ur:crypto-psbt/-3/lpad")), "urSignRequest", "dash first")

        section("format: wrong direction and unsupported URs")
        for type in BILPublicQrFormat.pairingUrTypes.sorted() {
            eq(name(kind("ur:\(type)/oeadcyjksktnbk")), "pairingUr", type)
            eq(name(kind("UR:\(type.uppercased())/1-2/OEADCY")), "pairingUr", type)
        }
        for type in ["eth-signature", "sol-signature", "tron-signature", "btc-signature", "cosmos-signature"] {
            eq(name(kind("UR:\(type.uppercased())/OEADTPDAGD")), "signatureUr", type)
        }
        for type in ["crypto-seed", "seed", "crypto-bip39", "crypto-eckey", "cosmos-sign-request", "btc-sign-request", "x"] {
            eq(name(kind("ur:\(type)/oeadtpdagd")), "unsupportedUr", type)
        }

        section("format: not a UR")
        for text in ["ur:", "ur:crypto-psbt", "ur:/oead", "ur:crypto_psbt/oead", "ur:crypto psbt/oead",
                     "ur:" + String(repeating: "a", count: 65) + "/oead", "your:crypto-psbt/oead", "xur:crypto-psbt/oead"] {
            t(kind(text) == nil, "not a UR: \(text.prefix(30))")
        }
        t(BILPublicQrFormat.urType("crypto-psbt/oead") == nil, "urType without scheme")
        eq(BILPublicQrFormat.urType(" UR:CRYPTO-PSBT/1-2/LPAD ") ?? "nil", "crypto-psbt", "urType trims and lower-cases")
        eq(BILPublicQrFormat.urType("ur:" + String(repeating: "a", count: 64) + "/oead") ?? "nil", String(repeating: "a", count: 64), "64-char type")
        // Kotlin lower-cases with Locale.ROOT before the ASCII check: the Kelvin sign (U+212A) becomes "k".
        eq(BILPublicQrFormat.urType("ur:\u{212A}/oead") ?? "nil", "k", "Kelvin sign lower-cases like Kotlin")
        t(BILPublicQrFormat.urType("ur:\u{0130}x/oead") == nil, "dotted capital I lower-cases to two units (not a type char)")

        section("format: BBQr")
        for encoding in ["H", "2", "Z"] {
            eq(name(kind("B$\(encoding)P0100ABCD")), "bbqrPart", "B$\(encoding)P")
            for fileType in ["T", "J", "C", "U", "X", "B"] {
                eq(name(kind("B$\(encoding)\(fileType)0100ABCD")), "unsupportedUr", "\(encoding)\(fileType)")
            }
        }
        t(kind("B$") == nil, "B$")
        t(kind("B$H") == nil, "B$H")
        t(kind("B$XP0100AB") == nil, "unknown encoding")
        t(kind("B$Hp0100AB") == nil, "file type is upper-case")
        t(kind("b$2P0100AB") == nil, "BBQr is case-sensitive")
        eq(name(kind("B$2P")), "bbqrPart", "B$2P (the gate says malformed)")

        section("format: PSBT text")
        eq(name(kind("cHNidP8BAFICAAAAAQ==")), "psbtBase64", "base64")
        eq(name(kind("\n cHNidP8BAFIC\nAAAAAQ==\n")), "psbtBase64", "base64 wrapped")
        t(kind("chnidp8BAFICAAAAAQ==") == nil, "base64 is case-sensitive")
        eq(name(kind("70736274ff01005202")), "psbtHex", "hex")
        eq(name(kind("70736274FF01005202")), "psbtHex", "HEX")
        t(kind("70736274f") == nil, "short hex")
        t(kind("0x70736274ff0100") == nil, "0x hex")

        section("format: everything else is not public")
        let others = [
            "", "   ", "bb_sign:abc", "bb_watch:{}", "bb_tx:abc", "wc:7f6e504bfad60b48@2?relay-protocol=irn",
            "bitcoin:1BoatSLRHtKNngkdXEeobR76b53LETtpyT?amount=0.1", "bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu",
            "0x9858EfFD232B4033E47d90003D41EC34EcaEda94", "TUEZSdKsoDHQMeZwihtdoBiN46zxhGWYdH",
            "HAgk14JpMQLgt6rVgv7cBQFJWFto5Dqxi472uT3DKpqk", "https://example.com", "digiid://example.com/cb",
            "legal winner thank year wave sausage worth useful legal winner thank yellow", "hello world",
            "ownbit://www.ownbit.io/contact?id=rabc",
            "xpub6CUGRUonZSQ4TWtTMmzXdrXDtypWKiKrhko4egpiMZbpiaQL2jkwSB1icqYh2cfDfVxdx4df189oLKnC5fSwqPfgyP3hooxujYzAu3fDVmz",
        ]
        for text in others { t(kind(text) == nil, "not public: \(text.prefix(30))") }

        section("format: kind flags")
        let engine: [BILPublicQrKind] = [.urSignRequest, .urPart, .bbqrPart, .psbtBase64, .psbtHex]
        let kotlin: [BILPublicQrKind] = [.tronLinkRequest, .tronLinkPart]
        let ur: [BILPublicQrKind] = [.urSignRequest, .urPart, .pairingUr, .signatureUr, .unsupportedUr]
        eq(BILPublicQrKind.allCases.count, 11, "11 kinds")
        for k in BILPublicQrKind.allCases {
            eq(k.isSigningRequest, engine.contains(k) || kotlin.contains(k), "\(k) isSigningRequest")
            eq(k.isEngineFrame, engine.contains(k), "\(k) isEngineFrame")
            eq(k.isWrongDirection, k == .pairingUr || k == .signatureUr, "\(k) isWrongDirection")
            eq(k.isUr, ur.contains(k), "\(k) isUr")
            eq(k.isTronLink, kotlin.contains(k), "\(k) isTronLink")
            t(!(k.isSigningRequest && k.isWrongDirection), "\(k) never both")
        }

        section("format: huge input is classified by its prefix only")
        let start = Date()
        eq(name(kind("ur:crypto-psbt/1-9/" + String(repeating: "a", count: 2_000_000))), "urPart", "2 M chars UR")
        t(kind(String(repeating: "x", count: 2_000_000)) == nil, "2 M x")
        t(kind(String(repeating: "a", count: 2_000_000)) == nil, "2 M a (TokenPocket action scan stays linear)")
        t(Date().timeIntervalSince(start) < 20, "huge inputs classify quickly")

        section("format: golden vectors of the pinned engine")
        var checked = 0
        for c in ScanFixtures.scanCases {
            for step in c.steps {
                let actual = kind(step.frame)
                switch c.id {
                case "T5-oversized-frame": t(actual == nil, c.id)
                case "T5-wrong-direction-pairing-ur": eq(name(actual), "pairingUr", c.id)
                case "T5-wrong-direction-signature-ur": eq(name(actual), "signatureUr", c.id)
                default: eq(name(actual), name(ScanFixtures.expectedTransportKind(step.frame)), c.id)
                }
                checked += 1
            }
        }
        t(checked >= 350, "scan frames checked: \(checked)")
        eq(ScanFixtures.pastes.count, 4, "4 pastes")
        for paste in ScanFixtures.pastes { t(kind(paste)?.isSigningRequest == true, "paste \(paste.prefix(20))") }
        var pairingUrs = 0
        for (type, frame) in ScanFixtures.pairingFrames {
            if type == "address" {
                t(kind(frame) == nil, "an address export is not a public code")
            } else {
                eq(name(kind(frame)), "pairingUr", type)
                pairingUrs += 1
            }
        }
        t(pairingUrs >= 15, "pairing URs: \(pairingUrs)")
        var signatures = 0
        for (type, frames) in ScanFixtures.responses {
            for frame in frames {
                let expected: BILPublicQrKind?
                switch type {
                case "eth-signature", "sol-signature", "tron-signature": expected = .signatureUr
                default: expected = ScanFixtures.expectedTransportKind(frame)   // a signed PSBT looks like a request
                }
                eq(name(kind(frame)), name(expected), "response \(type)")
                if expected == .signatureUr { signatures += 1 }
            }
        }
        t(signatures >= 30, "signature frames: \(signatures)")
        let keystone = ScanFixtures.keystoneTron
        eq(name(kind(keystone["requestUR"] ?? "")), "urSignRequest", "keystone request")
        eq(name(kind(keystone["signatureUR"] ?? "")), "signatureUr", "keystone signature")
        for frame in ScanFixtures.evmPublicUiFrames { eq(name(kind(frame)), "urSignRequest", "evm-public-ui") }

        section("format: every public fixture is a public code (≥ 500)")
        var all = [String]()
        for c in ScanFixtures.scanCases where c.id != "T5-oversized-frame" { all += c.steps.map { $0.frame } }
        all += ScanFixtures.pastes
        all += ScanFixtures.pairingFrames.filter { $0.type != "address" }.map { $0.frame }
        for r in ScanFixtures.responses { all += r.frames }
        all += ScanFixtures.evmPublicUiFrames
        all += keystone.filter { $0.key.hasSuffix("UR") }.map { $0.value }
        t(all.count >= 500, "fixtures: \(all.count)")
        var publicCount = 0
        for text in all where kind("  " + text + "\n") != nil { publicCount += 1 }
        eq(publicCount, all.count, "every fixture text (with surrounding whitespace) classifies as public")

        section("format: classifier cases with surrounding whitespace (ScanPayloadClassifierTest)")
        let cases: [(String, String)] = [
            ("ur:eth-sign-request/oeadtpdagdmycnhynlva", "urSignRequest"),
            ("UR:SOL-SIGN-REQUEST/OLADTPDAGDMYCNHY", "urSignRequest"),
            ("ur:tron-sign-request/oladtpdagdmycnhy", "urSignRequest"),
            ("UR:CRYPTO-PSBT/1-3/LPADAXCFADWTCYDK", "urPart"),
            ("ur:psbt/2-3/lpaoaxcfad", "urPart"),
            ("B$2P0300OBZWE5H7AEAFEAQAAAAAD2IP6C", "bbqrPart"),
            ("B$HP010070736274FF01005202", "bbqrPart"),
            ("B$ZP01005XA3CDIAAACABMGRT4XJ", "bbqrPart"),
            ("cHNidP8BAFICAAAAAekP8Koj3Yg9KuehyjwZqkAW", "psbtBase64"),
            ("70736274ff0100520200000001e90ff0aa23dd88", "psbtHex"),
            ("UR:CRYPTO-ACCOUNT/OEADCYJKSKTNBKAOLY", "pairingUr"),
            ("UR:CRYPTO-HDKEY/PTAOWKAXHDCLAOWDVERO", "pairingUr"),
            ("UR:CRYPTO-MULTI-ACCOUNTS/OXADCYJKSKTN", "pairingUr"),
            ("UR:ETH-SIGNATURE/OEADTPDAGDMYCNHYNLVA", "signatureUr"),
            ("ur:tron-signature/oeadtpdagdmycnhy", "signatureUr"),
            ("ur:crypto-seed/oeadgdstaslplabg", "unsupportedUr"),
            ("B$2T0100AAAA", "unsupportedUr"),
            (#"{"amount":0,"address":"TMTjucQ73f32Yw4Xx8Gm1dH1mdFrFjn9Lb","amountStr":"0","type":99,"hexList":["0a1a5a18221654726f6e4c696e6b437573746f6d436f6e7472616374"]}"#, "tronLinkRequest"),
            (#"tp:multiFragment-version=1.0&protocol=TokenPocket&data={"content":"e73666572436f6e7472616374_1462fb50","index":"3\/5"}"#, "tpUnsupported"),
            ("tron:signTransactionSignature-version=1.0&protocol=TokenPocket&network=tron&chain_id=11111&data={}", "tpUnsupported"),
        ]
        for (text, k) in cases { eq(name(kind("  \(text)\n")), k, String(text.prefix(30))) }

        section("format: C-GEN-17 — Ownbit's own codes are never public")
        let ownbitPrefixes = ["bb_watch:", "bb_addcoin:", "bb_sign:", "bb_tx:", "bb_tx2:", "bb_signresult:", "bb_member:", "bb_mswatch:",
                              "bb_msinitiate:", "bb_msconfirm:", "bb_msdeploy:", "bb_msexecute:", "bb_txmsinitiate:", "bb_txmsconfirm:",
                              "bb_txmsdeploy:", "bb_txmsexecute:", "bb_txca:", "bb_amskey:", "bb_txamskey:", "bb_amsdeploy:",
                              "bb_txamsdeploy:", "bb_amsinitiate:", "bb_txamsinitiate:", "bb_amsconfirm:", "bb_txamsconfirm:",
                              "digiid:", "eos:new_eos_account-?", "eos:new_eos_a-?", "wc:", "ownbit_weblogin:", "ownbit_qrcodeid:"]
        for p in ownbitPrefixes {
            for body in ["", "abc", "cHNidP8BAFICAAAAAQ==", "ur:crypto-psbt/1-3/lpad", "{\"hexList\":[\"ab\"]}", "B$2P0100AAAA",
                         "tp:x&protocol=TokenPocket", "tron:signTransaction-version=1.0&protocol=TokenPocket&"] {
                t(kind(p + body) == nil, "never public: \(p)\(body.prefix(12))")
            }
        }
        t(kind("EOS" + String(repeating: "a", count: 50)) == nil, "EOS new account")
        t(kind("bb_sign2:cHNidP8BAFICAAAAAQ==") == nil, "bb_sign2:")
        for uri in ["bitcoin:bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu?amount=0.5", "tron:TXYZopYRdj2D9XRtbG411XZZ3kM5VkAeBf?amount=1",
                    "ethereum:0x9858EfFD232B4033E47d90003D41EC34EcaEda94@1?value=1", "solana:HAgk14JpMQLgt6rVgv7cBQFJWFto5Dqxi472uT3DKpqk?amount=1"] {
            t(kind(uri) == nil, "payment URI not public: \(uri.prefix(20))")
        }
        // A 12-word phrase after "ur: " is the scanner's mnemonic interception, never a UR (no type before "/").
        t(kind("ur: legal winner thank year wave sausage worth useful legal winner thank yellow") == nil, "ur: <12 words> is not a UR")

        section("format: round-2 texts")
        let tlPhoto = #"{"amount":0,"address":"TMTjucQ73f32Yw4Xx8Gm1dH1mdFrFjn9Lb","amountStr":"0","type":99,"hexList":["0a1a5a18221654726f6e4c696e6b437573746f6d436f6e7472616374"]}"#
        eq(name(kind(tlPhoto)), "tronLinkRequest", "TronLink capture")
        eq(name(kind(#"{"cN":2,"hexList":["abc"],"tN":3,"type":0}"#)), "tronLinkPart", "TronLink part")
        eq(name(kind(#"{"hexList":"x"}"#)), "tronLinkRequest", "malformed TronLink JSON is still TronLink")
        t(kind(#"{"name":"x"}"#) == nil, "other JSON")
        t(kind(#"{"action":"other"}"#) == nil, "other action")
        t(kind(#"{"action":1,"x":"coldWalletSign"}"#) == nil, "non-string action is not TokenPocket")
        t(kind("{\"action\":\"coldWalletSign\"," + "\"pad\":\"" + String(repeating: "a", count: 4_300) + "\"}") == nil,
          "legacy JSON over 4300 chars is not recognised")
        t(kind(#"{"action":"coldWalletSign","action":"coldWalletSign"}"#) == nil, "legacy JSON must be strict")
        t(kind("bb_sign:abc") == nil, "bb_sign")
        t(kind("tron:TXYZopYRdj2D9XRtbG411XZZ3kM5VkAeBf?amount=1") == nil, "tron payment URI")
        t(kind("TUEZSdKsoDHQMeZwihtdoBiN46zxhGWYdH") == nil, "TRON address")
        // Code-unit prefix / suffix tests (Kotlin), not Swift graphemes: "{" + U+0301 still starts with "{".
        eq(name(kind("{\u{0301}\"hexList\":[\"a\"]}")), "tronLinkRequest", "a combining mark after { keeps the { prefix")
        eq(name(kind("{\"hexList\":[\"a\"]}\u{0301}")), "nil", "a combining mark after } is not TronLink's shape")

        section("format: TokenPocket texts (owner 2026-10-13)")
        let tpPhoto1 = #"tp:multiFragment-version=1.0&protocol=TokenPocket&data={"content":"c5a6fbdcb1121541c533c9e29b32cf7b3ef97aa3609c71c2ef5fb99918c0843d70f0dcc0929334\",\"txID\":\"8e8801_ab0d4e15","index":"8\/10"}"#
        let tpPhoto2 = #"tp:multiFragment-version=1.0&protocol=TokenPocket&data={"content":"e73666572436f6e747261637412320a15417e0ed463557e9ebbec146a1f91afdec5a6fbdcb1121541c533c9e29b3_1462fb50","index":"3\/5"}"#
        let tpFirst = #"tp:multiFragment-version=1.0&protocol=TokenPocket&data={"content":"tron:signTransaction-version=1.0&protocol=TokenPocket&network=tron&chain_id=11111&data={\"tx\":_587ca4c2","index":"0/10"}"#
        var tpTexts = [tpPhoto1, tpPhoto2, tpFirst,
                       "tp:multiFragment-version=2.0&protocol=TokenPocket&data={}",
                       "tron:signTransaction-version=1.0&protocol=TokenPocket&network=tron&chain_id=11111&data={}",
                       "tron:signTransactionSignature-version=1.0&protocol=TokenPocket&network=tron&chain_id=11111&data={}",
                       "tron:signMessageV2-version=1.0&protocol=TokenPocket&data={}",
                       "tron:signAndSendTransaction-version=1.0&protocol=TokenPocket&network=tron&chain_id=1&data={}",
                       "ethereum:signTransaction-version=1.0&protocol=TokenPocket&network=ethereum&chain_id=1&data={}",
                       "bitcoin:signTransaction-version=1.0&protocol=TokenPocket&network=btc&data={}",
                       "solana:signTransaction-version=1.0&protocol=TokenPocket&data={}",
                       "tp:other-text&protocol=TokenPocket",
                       #"{"action":"coldWalletSign","signType":"tronSignTx","sign":"abcd"}"#,
                       OtherWalletVectors.tpRequest, OtherWalletVectors.TP_ANSWER_HEADER]
        tpTexts += OtherWalletVectors.tpRequestFrames
        eq(OtherWalletVectors.tpRequestFrames.count, 10, "tp-v1 has 10 request frames")
        for text in tpTexts {
            let k = kind(text)
            eq(name(k), "tpUnsupported", String(text.prefix(40)))
            t(!(k?.isSigningRequest ?? true) && !(k?.isWrongDirection ?? true) && !(k?.isEngineFrame ?? true), "never signed: \(text.prefix(30))")
            t(BILPublicQrFormat.scannerBadgeDetail(kind: .tpUnsupported, text: text) == nil, "no badge detail for TokenPocket")
        }
        // Header near-misses are not TokenPocket.
        for text in ["tron:signTransaction-version=1.0&protocol=TokenPocket", "Tron:signTransaction-version=1.0&protocol=TokenPocket&",
                     "tron:sign_Transaction-version=1.0&protocol=TokenPocket&", "tron:signTransaction-version=1.0.0.0.0&protocol=TokenPocket&",
                     "tron:signTransaction-version=&protocol=TokenPocket&", "tp:multiFragment-version=1.0&protocol=tokenpocket&",
                     "xtp:multiFragment&protocol=TokenPocket", "tron:-version=1&protocol=TokenPocket&", ":x-version=1&protocol=TokenPocket&"] {
            t(kind(text) == nil, "not TokenPocket: \(text)")
        }
        eq(name(kind(" tron:x-version=1&protocol=TokenPocket&x")), "tpUnsupported", "trimmed first")
        eq(name(kind("tron:signTransaction-version=12345678&protocol=TokenPocket&")), "tpUnsupported", "8-char version")
        t(kind("tron:signTransaction-version=123456789&protocol=TokenPocket&") == nil, "9-char version")
        eq(name(kind(String(repeating: "a", count: 5_000) + ":x-version=1&protocol=TokenPocket&")), "tpUnsupported",
           "a long scheme still matches (exact regex semantics)")

        section("format: scanner badge detail")
        eq(BILPublicQrFormat.scannerBadgeDetail(kind: .urPart, text: "ur:crypto-psbt/1-3/lpad") ?? "nil", "UR · crypto-psbt", "UR part")
        eq(BILPublicQrFormat.scannerBadgeDetail(kind: .urSignRequest, text: " UR:ETH-SIGN-REQUEST/OEAD ") ?? "nil", "UR · eth-sign-request", "UR single")
        t(BILPublicQrFormat.scannerBadgeDetail(kind: .urSignRequest, text: "ur:crypto-seed/oead") == nil, "UR type not signable → nil")
        eq(BILPublicQrFormat.scannerBadgeDetail(kind: .bbqrPart, text: "B$2P0100AAAA") ?? "nil", "BBQr · PSBT", "BBQr")
        eq(BILPublicQrFormat.scannerBadgeDetail(kind: .psbtBase64, text: "cHNidP8BAFICAAAAAQ==") ?? "nil", "PSBT", "base64")
        eq(BILPublicQrFormat.scannerBadgeDetail(kind: .psbtHex, text: "70736274ff00") ?? "nil", "PSBT", "hex")
        eq(BILPublicQrFormat.scannerBadgeDetail(kind: .tronLinkRequest, text: tlPhoto) ?? "nil", "TronLink", "TronLink")
        eq(BILPublicQrFormat.scannerBadgeDetail(kind: .tronLinkPart, text: "{}") ?? "nil", "TronLink", "TronLink part")
        for k in [BILPublicQrKind.pairingUr, .signatureUr, .unsupportedUr, .tpUnsupported] {
            t(BILPublicQrFormat.scannerBadgeDetail(kind: k, text: "ur:crypto-psbt/oead") == nil, "\(k) has no badge detail")
        }

        section("format: strict JSON as the TronLink / TokenPocket formats use it")
        t(BILStrictJSON.parseObject(#"{"a":1,"b":[true,false,null],"c":{"d":"é\/"}}"#) != nil, "accepted")
        for bad in [#"{"a":1,"a":2}"#, #"{"a":{"b":1,"b":1}}"#, #"{"a":1,"a":2}"#, #"{"a":1,}"#, "{a:1}", "{'a':1}",
                    #"{"a":NaN}"#, #"{"a":01}"#, "{\"a\":\"x\ty\"}", #"{"a":1} {"b":2}"#, "[1]",
                    String(repeating: "[", count: 40) + String(repeating: "]", count: 40)] {
            t(BILStrictJSON.parseObject(bad) == nil, "refused: \(bad.prefix(30))")
        }
        eq(BILStrictJSON.parseObject(#"{"amount":9007199254740993,"x":1.50}"#).map { BILStrictJSON.serialize($0) } ?? "nil",
           #"{"amount":9007199254740993,"x":1.50}"#, "number literals kept")
    }
}
