//  PPOutpointsTests.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Port of the app harness suite `scripts/public-protocol/tests/outpoints` (main.swift) to XCTest.
//
//  tests/outpoints/main.swift (WP12) — BILSignedOutpointMemory (design D-30; Android SignedOutpointMemoryTest).
//

import Foundation
import XCTest
import CryptoKit
@testable import OwnbitCore

/// The suite namespace (harness helpers are its static members).
enum PPOutpointsSuite: PPSuite {}

final class PPOutpointsTests: XCTestCase {
    func testOutpoints() throws {
        try ppRunSuite("outpoints") { try PPOutpointsSuite.run() }
    }
}

extension PPOutpointsSuite {

    static func claim(_ i: Int, sats: UInt64, vout: UInt32 = 0) -> BILSignedOutpointMemory.Claim {
        // 32 distinct bytes per i (txid = sha256 of the index)
        let txid = Array(SHA256.hash(data: Data("txid-\(i)".utf8)))
        return BILSignedOutpointMemory.Claim(txid: txid, vout: vout, sats: sats)
    }

    static func fileURL(_ name: String) -> URL {
        return pubTempDir("outpoints-\(name)").appendingPathComponent("PublicSigner").appendingPathComponent("signed_outpoints.json")
    }

    static func write(_ text: String, to url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data(text.utf8).write(to: url)
    }

    static func sha(_ url: URL) -> String {
        guard let d = try? Data(contentsOf: url) else { return "-" }
        return pubHex(SHA256.hash(data: d))
    }

    static func conflicts(_ m: BILSignedOutpointMemory, _ c: [BILSignedOutpointMemory.Claim?]) -> [Int]? {
        return try? m.conflicts(c)
    }

    /// Forgotten = a different amount no longer conflicts.
    static func remembered(_ m: BILSignedOutpointMemory, _ i: Int, sats: UInt64) -> Bool {
        return conflicts(m, [claim(i, sats: sats + 1)]) == [0]
    }

    // MARK: - Key / tag (exact vectors, R5 §4.1)

    /// The harness main.swift (nonisolated top-level code, as in the harness).
    static func run() throws {
        section("vectors")
        do {
            let txid = [UInt8](repeating: 0x11, count: 32)
            let key0 = BILSignedOutpointMemory.key(txid: txid, vout: 0)
            eq(pubHex(key0), "485e7b262ee1424cf3667553bef3cceb", "key vout 0")
            eq(pubHex(BILSignedOutpointMemory.key(txid: txid, vout: 1)), "229e200c6ef2bb95bc68754029eb9400", "key vout 1")
            eq(pubHex(BILSignedOutpointMemory.tag(key: key0, sats: 100_000)), "7a6186948d50d923eaeec24be8e29809", "tag 100000")
            eq(pubHex(BILSignedOutpointMemory.tag(key: key0, sats: 100_001)), "0f37f6a63f4287c326deb3c2c23b6b72", "tag 100001")
            eq(BILSignedOutpointMemory.capacity, 256, "capacity 256")
            eq(BILSignedOutpointMemory.defaultFileURL.lastPathComponent, "signed_outpoints.json", "file name")
            eq(BILSignedOutpointMemory.defaultFileURL.deletingLastPathComponent().lastPathComponent, "PublicSigner", "folder")
            t(BILSignedOutpointMemory.defaultFileURL.path.contains("Application Support"), "under Application Support")
            t(!"\(claim(1, sats: 1))".contains("sats") && "\(BILSignedOutpointMemory.Unavailable())" == "Unavailable", "descriptions print nothing")
            var dumped = ""
            dump(claim(1, sats: 123_456_789), to: &dumped)
            let reflected = String(reflecting: claim(1, sats: 123_456_789))
            t(!dumped.contains("123456789") && !dumped.contains("txid") && !reflected.contains("123456789"), "a claim dumps nothing of its content")
        }

        // MARK: - Conflicts

        section("conflicts")
        do {
            let url = fileURL("conflicts")
            let m = BILSignedOutpointMemory(fileURL: url)
            t(m.isAvailable, "absent file = available")
            eq(conflicts(m, [claim(1, sats: 100)]), [], "absent file = empty")
            t(!FileManager.default.fileExists(atPath: url.path), "reading never creates the file")
            try? m.record([])
            t(!FileManager.default.fileExists(atPath: url.path), "an empty record writes nothing")
            t((try? m.record([claim(1, sats: 100), claim(2, sats: 200)])) != nil, "record")
            eq(conflicts(m, [claim(1, sats: 100), claim(2, sats: 200)]), [], "same amounts: no conflict")
            eq(conflicts(m, [claim(1, sats: 101)]), [0], "another amount: conflict")
            eq(conflicts(m, [nil, claim(1, sats: 100), claim(2, sats: 1), claim(3, sats: 7)]), [0, 2], "nil claim = conflict; ascending")
            let short = BILSignedOutpointMemory.Claim(txid: [1, 2, 3], vout: 0, sats: 1)
            eq(conflicts(m, [short]), [0], "unreadable txid = conflict")
            throwsError(BILSignedOutpointMemory.Unavailable.self, "record of an unreadable claim throws") { try m.record([short]) }
            eq(conflicts(m, [claim(1, sats: 100, vout: 1)]), [], "another vout is another outpoint")
            // Persisted; nothing in the clear.
            let again = BILSignedOutpointMemory(fileURL: url)
            eq(conflicts(again, [claim(1, sats: 101)]), [0], "persisted across instances")
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            t(!text.contains(pubHex(claim(1, sats: 0).txid)) && !text.contains(pubHex(claim(1, sats: 0).txid.reversed())), "no txid in the file")
            t(!text.contains("\"100\"") && !text.contains(":100,") && !text.contains(":100}"), "no amount in the file")
            let root = BILStrictJSON.parseObject(text)
            eq(root?.keys ?? [], ["version", "rows"], "file shape")
            eq(root?["version"]?.numberLiteral, "1", "version 1")
            eq(root?["rows"]?.arrayValue?.count, 2, "two rows")
            eq(root?["rows"]?.arrayValue?.first?.objectValue?.keys ?? [], ["k", "t", "s"], "row keys")
            eq(root?["rows"]?.arrayValue?.map { $0.objectValue?["s"]?.numberLiteral ?? "" } ?? [], ["1", "2"], "order stamps in input order")
            let excluded = (try? url.resourceValues(forKeys: [.isExcludedFromBackupKey]))?.isExcludedFromBackup ?? false
            t(excluded, "file excluded from backup")
            let dirExcluded = (try? url.deletingLastPathComponent().resourceValues(forKeys: [.isExcludedFromBackupKey]))?.isExcludedFromBackup ?? false
            t(dirExcluded, "folder excluded from backup")
            // The same outpoint twice in one call: the later amount wins.
            let m2 = BILSignedOutpointMemory(fileURL: fileURL("twice"))
            try? m2.record([claim(5, sats: 1), claim(5, sats: 2)])
            eq(conflicts(m2, [claim(5, sats: 2)]), [], "later claim of the same outpoint wins")
            eq(m2.debugRowCount, 1, "one row per outpoint")
        }

        // MARK: - Eviction by the order counter

        section("capacity")
        do {
            let m = BILSignedOutpointMemory(fileURL: fileURL("cap"))
            try? m.record([claim(0, sats: 10)])
            for i in 1...256 { try? m.record([claim(i, sats: 10)]) }
            eq(m.debugRowCount, 256, "at most 256")
            t(!remembered(m, 0, sats: 10), "256 newer outpoints push the oldest out")
            t(remembered(m, 1, sats: 10) && remembered(m, 256, sats: 10), "the newest 256 stay")

            // A clock that went back cannot matter: stamps are an order counter. A full table stamped far "later" still takes
            // the next signature.
            let url = fileURL("later")
            var rows = [String]()
            for i in 0..<256 {
                let k = String(format: "%032lx", i), tg = String(repeating: "0", count: 32)
                rows.append("{\"k\":\"\(k)\",\"t\":\"\(tg)\",\"s\":\(Int64.max / 4 + Int64(i))}")
            }
            write("{\"version\":1,\"rows\":[\(rows.joined(separator: ","))]}", to: url)
            let later = BILSignedOutpointMemory(fileURL: url)
            t(later.isAvailable, "a full table with huge stamps reads")
            try? later.record([claim(900, sats: 5)])
            eq(later.debugRowCount, 256, "still 256")
            t(remembered(later, 900, sats: 5), "the newest signature is remembered")

            // One call with more than 256 outpoints keeps all of them; the next call trims back to 256, newest first.
            let big = BILSignedOutpointMemory(fileURL: fileURL("big"))
            try? big.record((0..<300).map { claim(1000 + $0, sats: 1) })
            eq(big.debugRowCount, 300, "a 300-input call keeps all its rows")
            try? big.record([claim(5000, sats: 1)])
            eq(big.debugRowCount, 256, "next call trims to 256")
            t(remembered(big, 5000, sats: 1), "the new one stays")
            t(remembered(big, 1299, sats: 1), "the newest of the big call stays")
            t(!remembered(big, 1000, sats: 1), "its oldest go first")

            // Recording an outpoint again makes it the newest.
            let refresh = BILSignedOutpointMemory(fileURL: fileURL("refresh"))
            try? refresh.record([claim(1, sats: 1)])
            for i in 0..<255 { try? refresh.record([claim(100 + i, sats: 1)]) }
            try? refresh.record([claim(1, sats: 1)])
            try? refresh.record([claim(9999, sats: 1)])
            t(remembered(refresh, 1, sats: 1), "refreshed outpoint kept")
            t(!remembered(refresh, 100, sats: 1), "the oldest of the others went instead")
            eq(refresh.debugRowCount, 256, "256 rows")
        }

        // MARK: - Corrupt / transient / reset (D-30)

        section("unavailable")
        do {
            let corruptTexts = ["{garbage", "[]", "", "{\"version\":2,\"rows\":[]}", "{\"version\":\"1\",\"rows\":[]}", "{\"version\":1}",
                                "{\"version\":1,\"rows\":[{\"k\":\"\(String(repeating: "A", count: 32))\",\"t\":\"\(String(repeating: "0", count: 32))\",\"s\":1}]}",
                                "{\"version\":1,\"rows\":[{\"k\":\"\(String(repeating: "a", count: 31))\",\"t\":\"\(String(repeating: "0", count: 32))\",\"s\":1}]}",
                                "{\"version\":1,\"rows\":[{\"k\":\"\(String(repeating: "a", count: 32))\",\"t\":\"\(String(repeating: "0", count: 32))\",\"s\":0}]}",
                                "{\"version\":1,\"rows\":[{\"k\":\"\(String(repeating: "a", count: 32))\",\"t\":\"\(String(repeating: "0", count: 32))\",\"s\":1.5}]}",
                                "{\"version\":1,\"rows\":[{\"k\":\"\(String(repeating: "a", count: 32))\",\"t\":\"\(String(repeating: "0", count: 32))\",\"s\":1,\"x\":1}]}",
                                "{\"version\":1,\"rows\":[{\"k\":\"\(String(repeating: "a", count: 32))\",\"t\":\"\(String(repeating: "0", count: 32))\",\"s\":1},{\"k\":\"\(String(repeating: "a", count: 32))\",\"t\":\"\(String(repeating: "1", count: 32))\",\"s\":2}]}",
                                "{\"version\":1,\"version\":1,\"rows\":[]}",
                                "{\"version\":1,\"rows\":[]} x",
                                // order stamps no real counter reaches (review WP12 #1: Int64.max used to trap in `record`)
                                "{\"version\":1,\"rows\":[{\"k\":\"\(String(repeating: "a", count: 32))\",\"t\":\"\(String(repeating: "b", count: 32))\",\"s\":9223372036854775807}]}",
                                "{\"version\":1,\"rows\":[{\"k\":\"\(String(repeating: "a", count: 32))\",\"t\":\"\(String(repeating: "b", count: 32))\",\"s\":4611686018427387904}]}",
                                "{\"version\":1,\"rows\":[{\"k\":\"\(String(repeating: "a", count: 32))\",\"t\":\"\(String(repeating: "b", count: 32))\",\"s\":9223372036854775808}]}"]
            for (n, text) in corruptTexts.enumerated() {
                let url = fileURL("corrupt\(n)")
                write(text, to: url)
                let before = sha(url)
                let m = BILSignedOutpointMemory(fileURL: url)
                t(!m.isAvailable, "corrupt #\(n) → unavailable")
                throwsError(BILSignedOutpointMemory.Unavailable.self, "corrupt #\(n): conflicts throws") { _ = try m.conflicts([claim(1, sats: 1)]) }
                throwsError(BILSignedOutpointMemory.Unavailable.self, "corrupt #\(n): record throws") { try m.record([claim(1, sats: 1)]) }
                eq(sha(url), before, "corrupt #\(n): file bytes unchanged after a record attempt")
            }
            // The largest stamp a file may hold reads, but the next stamp would pass it: `record` throws (no trap, no write).
            let edge = fileURL("stamp-edge")
            let edgeKey = pubHex(BILSignedOutpointMemory.key(txid: claim(1, sats: 0).txid, vout: 0))
            let edgeTag = pubHex(BILSignedOutpointMemory.tag(key: BILSignedOutpointMemory.key(txid: claim(1, sats: 0).txid, vout: 0), sats: 10))
            write("{\"version\":1,\"rows\":[{\"k\":\"\(edgeKey)\",\"t\":\"\(edgeTag)\",\"s\":4611686018427387903}]}", to: edge)
            let edgeBefore = sha(edge)
            let atEdge = BILSignedOutpointMemory(fileURL: edge)
            t(atEdge.isAvailable, "stamp Int64.max / 2 reads")
            eq(conflicts(atEdge, [claim(1, sats: 10), claim(1, sats: 11)]), [1], "its row is checked")
            throwsError(BILSignedOutpointMemory.Unavailable.self, "a stamp past the limit: record throws") { try atEdge.record([claim(2, sats: 1)]) }
            eq(sha(edge), edgeBefore, "stamp limit: file bytes unchanged")
            eq(atEdge.debugRowCount, 1, "stamp limit: memory unchanged")
            // Corrupt is sticky for the process (instance); a repaired file is read by a new instance.
            let url = fileURL("sticky")
            write("{nope", to: url)
            let m = BILSignedOutpointMemory(fileURL: url)
            t(!m.isAvailable, "corrupt")
            write("{\"version\":1,\"rows\":[]}", to: url)
            t(!m.isAvailable, "still unavailable after the file was repaired (process-level)")
            t(BILSignedOutpointMemory(fileURL: url).isAvailable, "a new instance reads the repaired file")

            // resetForDebug moves the corrupt file aside (DEBUG only).
            let r = fileURL("reset")
            write("not json", to: r)
            let reset = BILSignedOutpointMemory(fileURL: r)
            t(!reset.isAvailable, "before reset: unavailable")
            reset.resetForDebug()
            let dir = r.deletingLastPathComponent()
            t(FileManager.default.fileExists(atPath: dir.appendingPathComponent("signed_outpoints.corrupt-1.json").path), "moved to …corrupt-1.json")
            t(reset.isAvailable && conflicts(reset, [claim(1, sats: 1)]) == [], "after reset: available and empty")
            t((try? reset.record([claim(1, sats: 1)])) != nil, "after reset: records again")
            write("still not json", to: r)
            let reset2 = BILSignedOutpointMemory(fileURL: r)
            reset2.resetForDebug()
            t(FileManager.default.fileExists(atPath: dir.appendingPathComponent("signed_outpoints.corrupt-2.json").path), "second reset → …corrupt-2.json")
            let good = BILSignedOutpointMemory(fileURL: r)
            good.resetForDebug()
            t(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("signed_outpoints.corrupt-3.json").path), "a readable / absent file is never moved")

            // A read error (here: no read permission) is transient: unavailable for that access only.
            let tr = fileURL("transient")
            let writer = BILSignedOutpointMemory(fileURL: tr)
            try? writer.record([claim(7, sats: 70)])
            let transient = BILSignedOutpointMemory(fileURL: tr)
            try? FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: tr.path)
            if (try? Data(contentsOf: tr)) == nil {
                t(!transient.isAvailable, "read error → unavailable")
                throwsError(BILSignedOutpointMemory.Unavailable.self, "read error: conflicts throws") { _ = try transient.conflicts([claim(7, sats: 1)]) }
                throwsError(BILSignedOutpointMemory.Unavailable.self, "read error: record throws") { try transient.record([claim(8, sats: 1)]) }
                try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: tr.path)
                t(transient.isAvailable, "next access reads again (transient)")
                eq(conflicts(transient, [claim(7, sats: 71)]), [0], "rows read after the transient error")
            } else {
                try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: tr.path)
                t(true, "transient read error not simulable here (running with read override)")
            }
        }

        // MARK: - Concurrency (one serial queue)

        section("threads")
        do {
            let m = BILSignedOutpointMemory(fileURL: fileURL("threads"))
            DispatchQueue.concurrentPerform(iterations: 64) { i in
                try? m.record([claim(20_000 + i, sats: UInt64(i))])
                _ = try? m.conflicts([claim(20_000 + i, sats: UInt64(i))])
            }
            eq(m.debugRowCount, 64, "64 concurrent records")
            eq(conflicts(m, (0..<64).map { claim(20_000 + $0, sats: UInt64($0)) }), [], "all remembered")
            let fresh = BILSignedOutpointMemory(fileURL: m.fileURL)
            eq(fresh.debugRowCount, 64, "file holds all 64")
        }

        pubSummary("outpoints")
    }
}
