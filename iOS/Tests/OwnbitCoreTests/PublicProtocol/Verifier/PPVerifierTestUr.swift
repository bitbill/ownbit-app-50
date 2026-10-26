//  PPVerifierTestUr.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Port of the app harness suite `scripts/public-protocol/tests/verifier` (TestUr.swift) to XCTest.
//
//  TestUr.swift — test-only CBOR writer and single-part BC-UR encoder, to build tampered answers (port of Android
//  `TestUr` in core/publicsigner/src/test/kotlin/io/ownbit/core/publicsigner/testing/SigningVectors.kt). Independent of
//  the app code (own word table, own CRC-32).
//

import Foundation
import XCTest
@testable import OwnbitCore

extension PPVerifierSuite {

    indirect enum TC {
        case int(UInt64)
        case bytes([UInt8])
        case text(String)
        case list([TC])
        case map([(TC, TC)])
        case tag(UInt64, TC)
        case bool(Bool)
        case null
    }

    enum TestUr {

        static func cbor(_ v: TC) -> [UInt8] {
            var out = [UInt8]()
            write(&out, v)
            return out
        }

        private static func head(_ out: inout [UInt8], _ major: UInt8, _ n: UInt64) {
            let m = major << 5
            if n < 24 {
                out.append(m | UInt8(n))
            } else if n < 256 {
                out += [m | 24, UInt8(n)]
            } else if n < 65_536 {
                out += [m | 25, UInt8(n >> 8), UInt8(n & 0xFF)]
            } else {
                out += [m | 26, UInt8((n >> 24) & 0xFF), UInt8((n >> 16) & 0xFF), UInt8((n >> 8) & 0xFF), UInt8(n & 0xFF)]
            }
        }

        private static func write(_ out: inout [UInt8], _ v: TC) {
            switch v {
            case .int(let n): head(&out, 0, n)
            case .bytes(let b): head(&out, 2, UInt64(b.count)); out += b
            case .text(let s): let b = Array(s.utf8); head(&out, 3, UInt64(b.count)); out += b
            case .list(let l): head(&out, 4, UInt64(l.count)); for x in l { write(&out, x) }
            case .map(let m): head(&out, 5, UInt64(m.count)); for (k, x) in m { write(&out, k); write(&out, x) }
            case .tag(let t, let x): head(&out, 6, t); write(&out, x)
            case .bool(let b): out.append(b ? 0xF5 : 0xF4)
            case .null: out.append(0xF6)
            }
        }

        private static let words: [UInt8] = Array((
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

        private static let crcTable: [UInt32] = (0..<256).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
            return c
        }

        static func crc32(_ bytes: [UInt8]) -> UInt32 {
            var c: UInt32 = 0xFFFF_FFFF
            for b in bytes { c = crcTable[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
            return c ^ 0xFFFF_FFFF
        }

        /// Minimal bytewords of `bytes` + CRC-32.
        static func bytewords(_ bytes: [UInt8]) -> String {
            let crc = crc32(bytes)
            let all = bytes + [UInt8(crc >> 24), UInt8((crc >> 16) & 0xFF), UInt8((crc >> 8) & 0xFF), UInt8(crc & 0xFF)]
            var out = [UInt8]()
            for b in all {
                let i = Int(b) * 4
                out.append(words[i])
                out.append(words[i + 3])
            }
            return String(decoding: out, as: UTF8.self)
        }

        /// A single-part UR (upper case, like the engine's frames).
        static func single(_ type: String, _ cborBytes: [UInt8]) -> String {
            return "UR:" + type.uppercased() + "/" + bytewords(cborBytes).uppercased()
        }

        /// A signature answer `{1: #6.37(id)?, 2: signature, …extra}`.
        static func signature(_ type: String, _ requestId: String?, _ signature: [UInt8], extra: [(TC, TC)] = []) -> String {
            var map = [(TC, TC)]()
            if let id = requestId { map.append((.int(1), .tag(37, .bytes(hexBytes(id))))) }
            map.append((.int(2), .bytes(signature)))
            map += extra
            return single(type, cbor(.map(map)))
        }
    }
}
