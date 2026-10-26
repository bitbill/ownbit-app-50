//  PPScanGateTests.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Port of the app harness suite `scripts/public-protocol/tests/scan` (GateTests.swift) to XCTest.
//
//  GateTests.swift — the frame gate and queue (port of Android PublicFrameGateTest + the gate part of
//  OtherWalletQrFormatsTest), virtual clock.
//

import Foundation
import XCTest
@testable import OwnbitCore

extension PPScanSuite {

    private static func desc(_ r: BILGateResult) -> String { return r.description }

    /// A structurally valid multi-part UR frame of `length` chars (bytewords letters padded to the length).
    private static func urPart(_ seq: Int, _ count: Int, type: String = "crypto-psbt", length: Int = 0) -> String {
        let head = "ur:\(type)/\(seq)-\(count)/"
        let body = "lpad" + String(String(seq).unicodeScalars.map { Character(UnicodeScalar(UInt8(0x61) + UInt8($0.value - 0x30))) })
        let target = max(body.utf16.count, length - head.utf16.count)
        return head + body + String(repeating: "a", count: target - body.utf16.count)
    }

    private final class GateHarness {
        let clock = TestClock()
        lazy var gate = BILPublicFrameGate(clock: { [unowned self] in self.clock.now })

        init() { clock.now = 1_000 }

        @discardableResult
        func accepted(_ frame: String, file: StaticString = #file, line: UInt = #line) -> BILGateAccepted? {
            let r = gate.accept(frame)
            if case .accepted(let a) = r {
                t(true, "accepted \(frame.prefix(30))", file: file, line: line)
                return a
            }
            t(false, "\(frame.prefix(30)) → \(desc(r)) (expected accepted)", file: file, line: line)
            return nil
        }

        @discardableResult
        func rejected(_ frame: String, _ reason: BILGateReason, _ kind: BILPublicQrKind? = nil,
                      file: StaticString = #file, line: UInt = #line) -> Bool {
            return eq(gate.accept(frame), .rejected(reason, kind), "\(frame.prefix(30)) → rejected(\(reason))", file: file, line: line)
        }
    }

    static func gateTests() {
        section("gate: every engine scan case replays through the gate")
        do {
            let gateCatches: [String: BILGateResult] = [
                "T5-wrong-direction-pairing-ur": .rejected(.wrongDirection, .pairingUr),
                "T5-wrong-direction-signature-ur": .rejected(.wrongDirection, .signatureUr),
                "T5-mixed-types": .rejected(.otherRequest, .bbqrPart),
                "O-QR-1-foreign-part": .rejected(.otherRequest, .urPart),
                "T5-oversized-frame": .rejected(.tooLarge, nil),
            ]
            let engineOnly: Set<String> = ["T5-scan-bbqr-Z-bomb", "T5-no-session"]
            var frames = 0
            var completed = 0
            for c in ScanFixtures.scanCases {
                let clock = TestClock()
                let g = BILPublicFrameGate(clock: { clock.now })
                var seen = Set<String>()
                for (i, step) in c.steps.enumerated() {
                    let r = g.accept(step.frame)
                    frames += 1
                    if !step.ok && !engineOnly.contains(c.id) {
                        if let expected = gateCatches[c.id] {
                            eq(r, expected, "\(c.id) #\(i)")
                        } else {
                            t(false, "\(c.id) #\(i): engine refusal not caught by the gate: \(desc(r))")
                        }
                        continue
                    }
                    let key = BILScanText.hasPrefixIgnoringASCIICase(step.frame, "ur:") ? step.frame.uppercased() : step.frame
                    if seen.insert(key).inserted {
                        if case .accepted(let a) = r {
                            eq(a.frame, BILKotlinText.trim(step.frame), "\(c.id) #\(i) frame")
                            eq(a.startsSession, i == 0, "\(c.id) #\(i) startsSession")
                            eq(a.parts, seen.count, "\(c.id) #\(i) parts")
                        } else {
                            t(false, "\(c.id) #\(i): \(desc(r))")
                        }
                    } else {
                        eq(r, .duplicate, "\(c.id) #\(i) duplicate")
                    }
                    if step.complete { completed += 1 }
                }
            }
            t(frames >= 350, "frames: \(frames)")
            t(completed >= 60, "completed sessions: \(completed)")
            let ids = Set(ScanFixtures.scanCases.map { $0.id })
            t(gateCatches.keys.allSatisfy { ids.contains($0) }, "every gate-caught case exists")
        }

        section("gate: frame size limits")
        do {
            let h = GateHarness()
            let hex4300 = "70736274ff" + String(repeating: "00", count: 2145)
            eq(hex4300.utf16.count, 4300, "4300 chars")
            eq(h.accepted(hex4300)?.frame ?? "", hex4300, "4300 accepted")
            h.gate.reset()
            h.rejected(hex4300 + "0", .tooLarge)
            h.rejected("ur:crypto-psbt/1-3/" + String(repeating: "a", count: 4300), .tooLarge)
            eq(h.accepted("  \n\(hex4300)\n  ")?.frame ?? "", hex4300, "trimmed first")
            h.gate.reset()
            eq(h.accepted(hex4300 + String(repeating: " ", count: 16_384 - 4300))?.frame ?? "", hex4300, "16384 raw bytes")
            h.gate.reset()
            h.rejected(hex4300 + String(repeating: " ", count: 16_384 - 4300 + 1), .tooLarge)
            h.rejected(String(repeating: "é", count: 8_193), .tooLarge)
            h.rejected(String(repeating: "😀", count: 4_097), .tooLarge)
        }

        section("gate: UTF-8 byte counting")
        t(!BILPublicFrameGate.exceedsUTF8Bytes(String(repeating: "a", count: 10), 10), "a×10")
        t(BILPublicFrameGate.exceedsUTF8Bytes(String(repeating: "a", count: 11), 10), "a×11")
        t(!BILPublicFrameGate.exceedsUTF8Bytes(String(repeating: "é", count: 5), 10), "é×5")
        t(BILPublicFrameGate.exceedsUTF8Bytes(String(repeating: "é", count: 5) + "a", 10), "é×5+a")
        t(!BILPublicFrameGate.exceedsUTF8Bytes(String(repeating: "中", count: 3) + "a", 10), "中×3+a")
        t(BILPublicFrameGate.exceedsUTF8Bytes(String(repeating: "中", count: 4), 10), "中×4")
        t(!BILPublicFrameGate.exceedsUTF8Bytes(String(repeating: "😀", count: 2) + "aa", 10), "😀×2+aa")
        t(BILPublicFrameGate.exceedsUTF8Bytes(String(repeating: "😀", count: 3), 10), "😀×3")
        t(!BILPublicFrameGate.exceedsUTF8Bytes("a😀😀a", 10), "a😀😀a = 10")
        t(BILPublicFrameGate.exceedsUTF8Bytes("aa😀😀a", 10), "aa😀😀a = 11")
        for n in [0, 1, 100, 5_461, 5_462, 16_384] {
            let s = String(repeating: "中", count: n)
            eq(BILPublicFrameGate.exceedsUTF8Bytes(s, 16_384), s.utf8.count > 16_384, "中×\(n)")
        }

        section("gate: blank and non-public text never reach the engine")
        do {
            let h = GateHarness()
            h.rejected("", .empty)
            h.rejected(" \n\t ", .empty)
            for text in ["bb_sign:jVFLbtswFLyK", "wc:7f6e504b@2?relay-protocol=irn", "bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu",
                         "legal winner thank year wave sausage worth useful legal winner thank yellow", "https://example.com"] {
                h.rejected(text, .notPublic)
            }
            h.rejected("UR:CRYPTO-HDKEY/PTAOWKAXHDCLAO", .wrongDirection, .pairingUr)
            h.rejected("UR:ETH-SIGNATURE/OEADTPDAGDMY", .wrongDirection, .signatureUr)
            h.rejected("ur:crypto-seed/oeadgdstaslplabg", .unsupported, .unsupportedUr)
            h.rejected("B$2T0100AAAA", .unsupported, .unsupportedUr)
            t(!h.gate.isActive, "no session")
        }

        section("gate: UR structure and alphabet")
        do {
            let h = GateHarness()
            for frame in ["ur:eth-sign-request/oead1tpd", "ur:eth-sign-request/oead tpd", "ur:eth-sign-request/oead/tpd",
                          "ur:eth-sign-request/", "ur:crypto-psbt/0-3/lpad", "ur:crypto-psbt/1-0/lpad",
                          "ur:crypto-psbt/4294967296-3/lpad", "ur:crypto-psbt/12345678901-3/lpad", "ur:crypto-psbt/1-3/",
                          "ur:crypto-psbt/1-3/lpad-a"] {
                let r = h.gate.accept(frame)
                if case .rejected(.malformed, _) = r { t(true, frame) } else { t(false, "\(frame) → \(desc(r))") }
            }
            h.rejected("ur:crypto-psbt/1-2049/lpad", .tooLarge, .urPart)
            eq(h.accepted("ur:crypto-psbt/4294967295-2048/lpad")?.kind, .urPart, "max seq / count")
            h.gate.reset()
            eq(h.accepted("UR:ETH-SIGN-REQUEST/OEADTPDA")?.kind, .urSignRequest, "single UR")
            t(!h.gate.isExpired(), "not expired")
        }

        section("gate: BBQr header, index and alphabet")
        do {
            let h = GateHarness()
            for frame in ["B$HP0100ABC", "B$HP0100ABCG", "B$HP0100abcd", "B$2P0100ABC1", "B$2P0100ABC8", "B$ZP0100AB=",
                          "B$2P0000AAAA", "B$2P0101AAAA", "B$2P01", "B$2P0 00AAAA"] {
                let r = h.gate.accept(frame)
                if case .rejected(.malformed, _) = r { t(true, frame) } else { t(false, "\(frame) → \(desc(r))") }
            }
            eq(h.accepted("B$2PZZZYAAAA")?.parts, 1, "1295 parts, last index")
            eq(h.accepted("B$2PZZ00BBBB")?.parts, 2, "second part")
            h.gate.reset()
            eq(h.accepted("B$HP0100ABCDEF0123456789")?.kind, .bbqrPart, "hex body")
        }

        section("gate: PSBT text alphabet and line breaks")
        do {
            let h = GateHarness()
            for frame in ["cHNidP8B-A==", "cHNidP8BA", "cHNidP8BA===", "cHNidP8=BAA=", "70736274ff0", "70736274ff0g"] {
                let r = h.gate.accept(frame)
                if case .rejected(.malformed, _) = r { t(true, frame) } else { t(false, "\(frame) → \(desc(r))") }
            }
            eq(h.accepted("cHNidP8BAFIC\r\nAAAAAQ==\n")?.frame ?? "", "cHNidP8BAFICAAAAAQ==", "base64 without whitespace")
            h.gate.reset()
            eq(h.accepted("70736274FF 0100")?.frame ?? "", "70736274FF0100", "hex without whitespace")
            h.gate.reset()
            let r = h.gate.accept("cHNidP8BAFIC AAAA AQ= =x")
            if case .rejected(.malformed, _) = r { t(true, "padding inside") } else { t(false, "padding inside → \(desc(r))") }
            // Kotlin whitespace (U+2028, U+3000, U+001C) is removed too; U+0085 is not whitespace in Kotlin.
            eq(h.accepted("cHNidP8BAFIC\u{2028}AAAA\u{3000}AQ==\u{1C}")?.frame ?? "", "cHNidP8BAFICAAAAAQ==", "Kotlin whitespace removed")
            h.gate.reset()
            let r2 = h.gate.accept("cHNidP8BAFIC\u{85}AAAAAQ==")
            if case .rejected(.malformed, _) = r2 { t(true, "U+0085 is not whitespace") } else { t(false, "U+0085 → \(desc(r2))") }
        }

        section("gate: duplicates (UR case-insensitive)")
        do {
            let h = GateHarness()
            let first = h.accepted("UR:CRYPTO-PSBT/1-3/LPADAXCF")
            t(first?.startsSession == true, "starts")
            eq(h.gate.accept("UR:CRYPTO-PSBT/1-3/LPADAXCF"), .duplicate, "same text")
            eq(h.gate.accept("ur:crypto-psbt/1-3/lpadaxcf\n"), .duplicate, "lower-case twin")
            let second = h.accepted("UR:CRYPTO-PSBT/2-3/LPAOAXCF")
            t(second?.startsSession == false, "second does not start")
            eq(second?.parts, 2, "2 parts")
            eq(h.gate.parts, 2, "gate parts")
            h.gate.reset()
            h.accepted("B$2P0300AAAA")
            eq(h.gate.accept(" B$2P0300AAAA "), .duplicate, "BBQr duplicate")
        }

        section("gate: a session keeps to one code")
        do {
            let h = GateHarness()
            h.accepted(urPart(1, 20))
            h.rejected("B$2P0300AAAA", .otherRequest, .bbqrPart)
            h.rejected("cHNidP8BAFICAAAAAQ==", .otherRequest, .psbtBase64)
            h.rejected(urPart(2, 20, type: "psbt"), .otherRequest, .urPart)
            h.rejected(urPart(2, 7), .otherRequest, .urPart)
            h.rejected("ur:crypto-psbt/lpadaxcf", .otherRequest, .urSignRequest)
            h.rejected("bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu", .notPublic)
            h.rejected("UR:CRYPTO-ACCOUNT/OEADCYJKSKTNBK", .wrongDirection, .pairingUr)
            h.rejected("ur:crypto-psbt/2-20/lpad1", .malformed, .urPart)
            eq(h.accepted(urPart(2, 20).uppercased())?.parts, 2, "upper-case part of the same code")
            eq(h.accepted(urPart(29, 20))?.parts, 3, "fountain part beyond the count")
            eq(h.gate.sessionKind, .urPart, "session kind")
        }

        section("gate: single-frame codes are sessions of one")
        do {
            let h = GateHarness()
            h.accepted("ur:eth-sign-request/oeadtpdagdmycnhy")
            eq(h.gate.accept("UR:ETH-SIGN-REQUEST/OEADTPDAGDMYCNHY"), .duplicate, "repeat")
            h.rejected("ur:eth-sign-request/oeadtpdagdmycnhz", .otherRequest, .urSignRequest)
            h.rejected("ur:eth-sign-request/1-2/lpad", .otherRequest, .urPart)
            h.gate.reset()
            h.accepted("cHNidP8BAFICAAAAAQ==")
            h.rejected("cHNidP8BAFICAAAAAg==", .otherRequest, .psbtBase64)
            h.rejected("70736274ff0100", .otherRequest, .psbtHex)
            h.gate.reset()
            h.accepted("B$HP0100ABCD")
            h.rejected("B$HP0100ABCE", .otherRequest, .bbqrPart)
            h.gate.reset()
            h.accepted("B$HP0200ABCD")
            h.rejected("B$2P0201AAAA", .otherRequest, .bbqrPart)
            h.rejected("B$HP0301ABCD", .otherRequest, .bbqrPart)
            eq(h.accepted("B$HP0201ABCD")?.parts, 2, "same header")
        }

        section("gate: at most 2048 distinct frames")
        do {
            let h = GateHarness()
            var allAccepted = true
            for seq in 1...BILPublicFrameGate.maxFrames {
                if case .accepted = h.gate.accept(urPart(seq, BILPublicFrameGate.maxFrames)) { continue }
                allAccepted = false
            }
            t(allAccepted, "2048 accepted")
            eq(h.gate.parts, 2048, "2048 parts")
            eq(h.gate.accept(urPart(5, BILPublicFrameGate.maxFrames)), .duplicate, "duplicate at the limit")
            h.rejected(urPart(2049, BILPublicFrameGate.maxFrames), .sessionFull, .urPart)
            t(BILGateReason.sessionFull.endsSession, "sessionFull ends")
            t(!h.gate.isActive, "reset")
            eq(h.gate.parts, 0, "0 parts")
            t(h.accepted(urPart(1, 3))?.startsSession == true, "new session")
        }

        section("gate: at most one mebibyte retained")
        do {
            let h = GateHarness()
            let perFrame = BILPublicFrameGate.maxFrameChars
            let fit = BILPublicFrameGate.maxRetainedChars / perFrame
            eq(fit, 243, "243 frames of 4300")
            var ok = true
            for seq in 1...fit {
                let frame = urPart(seq, 300, length: perFrame)
                if frame.utf16.count != perFrame { ok = false }
                if case .accepted = h.gate.accept(frame) { continue }
                ok = false
            }
            t(ok, "243 full frames accepted")
            eq(h.gate.retainedChars, fit * perFrame, "retained chars")
            if case .accepted = h.gate.accept(urPart(fit + 1, 300)) { t(true, "a short frame still fits") } else { t(false, "short frame") }
            h.rejected(urPart(fit + 2, 300, length: perFrame), .sessionFull, .urPart)
            eq(h.gate.retainedChars, 0, "reset retained")
        }

        section("gate: no progress times out and resets")
        do {
            let h = GateHarness()
            h.accepted(urPart(1, 20))
            h.clock.now += BILPublicFrameGate.noProgressTimeoutMillis
            t(!h.gate.isExpired(), "exactly 150 000 ms is not expired")
            eq(h.gate.accept(urPart(1, 20)), .duplicate, "repeat is no progress")
            h.rejected("bb_sign:abc", .notPublic)
            h.clock.now += 1
            t(h.gate.isExpired(), "expired after 150 001 ms")
            h.rejected(urPart(2, 20), .timedOut)
            t(BILGateReason.timedOut.endsSession, "timedOut ends")
            t(!h.gate.isActive, "reset")
            t(!h.gate.isExpired(), "nothing to expire")
            let again = h.accepted(urPart(2, 20))
            t(again?.startsSession == true, "new session")
            eq(again?.parts, 1, "1 part")
            h.clock.now += BILPublicFrameGate.noProgressTimeoutMillis
            eq(h.accepted(urPart(3, 20))?.parts, 2, "progress moves the deadline")
            h.clock.now += BILPublicFrameGate.noProgressTimeoutMillis
            eq(h.accepted(urPart(4, 20))?.parts, 3, "again")
            h.gate.reset()
            h.clock.now += 10 * BILPublicFrameGate.noProgressTimeoutMillis
            t(!h.gate.isExpired(), "no session, no expiry")
            t(h.accepted("cHNidP8BAFICAAAAAQ==")?.startsSession == true, "starts")
            t(BILPublicFrameGate.noProgressTimeoutMillis < 3 * 60_000, "shorter than the 3-min page release")
        }

        section("gate: reset and forget")
        do {
            let h = GateHarness()
            h.accepted(urPart(1, 3))
            h.accepted(urPart(2, 3))
            h.gate.forget(urPart(2, 3).uppercased())
            eq(h.gate.parts, 1, "forgotten")
            eq(h.accepted(urPart(2, 3))?.parts, 2, "accepted again")
            h.gate.forget("bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu")
            h.gate.forget(urPart(9, 7))
            eq(h.gate.parts, 2, "unknown / other session ignored")
            h.gate.forget(urPart(1, 3))
            h.gate.forget(urPart(2, 3))
            t(!h.gate.isActive, "nothing left: session over")
            t(h.accepted(urPart(1, 3))?.startsSession == true, "starts again")
            h.gate.reset()
            eq(h.gate.parts, 0, "0 parts")
            t(h.gate.sessionKind == nil, "no kind")
            t(h.accepted("B$2P0300AAAA")?.startsSession == true, "BBQr starts")
        }

        section("gate: accepted frames are never printed")
        do {
            let h = GateHarness()
            let frame = "UR:ETH-SIGN-REQUEST/OEADTPDAGDMYCNHYNLVAVSFZFYONCAGYWPFMSOFWPF"
            let r = h.gate.accept(frame)
            h.gate.reset()
            for text in [r.description, String(describing: r), String(reflecting: r), "\(r)",
                         h.accepted("cHNidP8BAFICAAAAAQ==").map { String(reflecting: $0) } ?? "", h.gate.description] {
                t(!text.contains("OEADTPDA") && !text.contains("cHNidP"), "no frame content in \(text.prefix(40))")
            }
            t(r.description.contains("urSignRequest"), "names the kind")
            var dumped = ""
            if case .accepted(let a) = r { dump(a, to: &dumped) }
            t(!dumped.contains("OEADTPDA"), "dump prints no content")
        }

        section("gate: queue is bounded and drops the oldest back into the gate")
        do {
            let h = GateHarness()
            let queue = BILPublicFrameQueue(gate: h.gate)
            eq(queue.capacity, 32, "capacity 32")
            let first = h.accepted(urPart(1, 100))
            let waiting = (2...33).compactMap { h.accepted(urPart($0, 100)) }
            eq(waiting.count, 32, "32 waiting frames")
            t(queue.offer(waiting[0]) == nil, "offer 1")
            for w in waiting.dropFirst().dropLast() { t(queue.offer(w) == nil, "offer") }
            eq(queue.count, 31, "31")
            t(queue.offer(waiting[31]) == nil, "offer 32")
            eq(queue.count, 32, "32")
            let extra = h.accepted(urPart(34, 100))!
            let dropped = queue.offer(extra)
            eq(dropped, waiting[0], "oldest dropped")
            eq(queue.count, 32, "still 32")
            eq(h.gate.parts, 33, "dropped frame forgotten")
            if case .accepted = h.gate.accept(waiting[0].frame) { t(true, "dropped frame accepted again") } else { t(false, "dropped frame") }
            eq(queue.poll(), waiting[1], "FIFO 1")
            eq(queue.poll(), waiting[2], "FIFO 2")
            t(first?.frame != waiting[1].frame, "distinct")
            h.gate.reset()
            let fresh = h.accepted("cHNidP8BAFICAAAAAQ==")!
            t(queue.offer(fresh) == nil, "a new session clears the queue")
            eq(queue.count, 1, "1")
            eq(queue.poll(), fresh, "fresh")
            t(queue.poll() == nil, "empty")
            h.gate.reset()
            queue.offer(h.accepted(urPart(1, 2))!)
            queue.clear()
            eq(queue.count, 0, "cleared")
        }

        section("gate: TronLink frames and TokenPocket texts (OtherWalletQrFormatsTest)")
        do {
            let h = GateHarness()
            let tlPhoto = #"{"amount":0,"address":"TMTjucQ73f32Yw4Xx8Gm1dH1mdFrFjn9Lb","amountStr":"0","type":99,"hexList":["0a1a5a18221654726f6e4c696e6b437573746f6d436f6e7472616374"]}"#
            let tpFirst = #"tp:multiFragment-version=1.0&protocol=TokenPocket&data={"content":"tron:signTransaction-version=1.0&protocol=TokenPocket&network=tron&chain_id=11111&data={\"tx\":_587ca4c2","index":"0/10"}"#
            let single = h.accepted(tlPhoto)
            eq(single?.kind, .tronLinkRequest, "TronLink single")
            t(single?.startsSession == true, "starts")
            eq(h.gate.accept(tlPhoto), .duplicate, "duplicate")
            h.rejected(tpFirst, .unsupported, .tpUnsupported)
            t(h.gate.isActive, "TokenPocket leaves the session alone")
            h.gate.reset()
            let p1 = #"{"address":"TUEZSdKsoDHQMeZwihtdoBiN46zxhGWYdH","cN":1,"hexList":["ab"],"tN":2,"type":0}"#
            let other = #"{"address":"TUEZSdKsoDHQMeZwihtdoBiN46zxhGWYdH","cN":1,"hexList":["ab"],"tN":3,"type":0}"#
            eq(h.accepted(p1)?.kind, .tronLinkPart, "part")
            h.rejected(other, .otherRequest, .tronLinkPart)
            h.gate.reset()
            h.rejected(#"{"cN":1,"hexList":["ab"],"tN":65,"type":0}"#, .tooLarge, .tronLinkPart)
            h.rejected(#"{"hexList":"x"}"#, .malformed, .tronLinkRequest)
            for text in [#"tp:multiFragment-version=1.0&protocol=TokenPocket&data={"content":"c5a6fbdcb1121541c533c9e29b32cf7b3ef97aa3609c71c2ef5fb99918c0843d70f0dcc0929334\",\"txID\":\"8e8801_ab0d4e15","index":"8\/10"}"#,
                         "tron:signTransaction-version=1.0&protocol=TokenPocket&network=tron&chain_id=11111&data={}",
                         "tron:signTransactionSignature-version=1.0&protocol=TokenPocket&network=tron&chain_id=11111&data={}",
                         "ethereum:signTransaction-version=1.0&protocol=TokenPocket&network=ethereum&chain_id=1&data={}"] + OtherWalletVectors.tpRequestFrames {
                h.rejected(text, .unsupported, .tpUnsupported)
            }
            // The whole TokenPocket request (~3 kB) is refused as unsupported too (not too large, not public-other).
            h.rejected(OtherWalletVectors.tpRequest, .unsupported, .tpUnsupported)
            t(!h.gate.isActive, "TokenPocket never starts a session")
            // A conflicting text for an accepted part number passes the gate (the collector refuses it).
            h.accepted(p1)
            let p1b = #"{"address":"TUEZSdKsoDHQMeZwihtdoBiN46zxhGWYdH","cN":1,"hexList":["cd"],"tN":2,"type":0}"#
            eq(h.accepted(p1b)?.parts, 2, "another text for cN 1 passes the gate")
            // A single TronLink request is a session of one frame.
            h.gate.reset()
            h.accepted(OtherWalletVectors.V1_REQUEST)
            h.rejected(OtherWalletVectors.V3_REQUEST, .otherRequest, .tronLinkRequest)
        }
    }
}
