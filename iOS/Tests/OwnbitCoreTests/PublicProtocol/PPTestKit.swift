//  PPTestKit.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  The mini test kit of the public-protocol suites, on top of XCTest. The suites are ports of the app's standalone
//  swiftc harness (`scripts/public-protocol/tests/<suite>/`, one executable per suite with top-level checks): every suite
//  is an enum namespace (`PP<Suite>Suite: PPSuite`) whose static members are the harness helpers, and one XCTestCase
//  runs it. The checks keep the harness spelling (`t`, `eq`, `throwsError`, `section`, `runAsync`, `fixture…`) as static
//  members of `PPSuite`, so suite code resolves them before any module-level name of the shared test target.
//
//  - A failed check is an `XCTFail` at the check's file / line, prefixed with the current section.
//  - Fixtures live next to this file in `Fixtures/` (located through `#filePath`, so no resource declaration is needed;
//    public test vectors only).
//  - `BILPublicLog` lines are captured (`PPStubLog`) so suites can prove that no payload is ever logged.
//

import Foundation
import XCTest
@testable import OwnbitCore

/// A suite namespace: `enum PPXyzSuite: PPSuite { … }`.
protocol PPSuite {}

/// Counters and the current section of the running suite (one suite runs at a time).
enum PPTestState {
    private static let lock = NSLock()
    private static var okCount = 0
    private static var failCount = 0
    private static var currentSection = ""

    static func record(_ ok: Bool, _ what: String, _ file: StaticString, _ line: UInt) {
        lock.lock()
        if ok { okCount += 1 } else { failCount += 1 }
        let section = currentSection
        lock.unlock()
        if !ok {
            XCTFail((section.isEmpty ? "" : "[\(section)] ") + what, file: file, line: line)
        }
    }

    static func setSection(_ name: String) {
        lock.lock(); currentSection = name; lock.unlock()
    }

    static var counts: (ok: Int, fail: Int) {
        lock.lock(); defer { lock.unlock() }
        return (okCount, failCount)
    }

    /// Starts a suite: counters reset, log capture installed.
    static func begin() {
        lock.lock(); okCount = 0; failCount = 0; currentSection = ""; lock.unlock()
        PPStubLog.install()
    }
}

/// Every line `BILPublicLog` wrote while a suite runs, as the app's `bil_errorPrint` stub recorded them ("error: …").
enum PPStubLog {
    private static let lock = NSLock()
    private static var storage: [String] = []

    static var lines: [String] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }

    static func reset() {
        lock.lock(); storage.removeAll(); lock.unlock()
    }

    static func install() {
        reset()
        BILPublicLog.sink = { line in
            PPStubLog.lock.lock()
            PPStubLog.storage.append("error: " + line)
            PPStubLog.lock.unlock()
        }
    }
}

extension PPSuite {

    /// Starts a named group of checks; failures carry the name.
    static func section(_ name: String) {
        PPTestState.setSection(name)
    }

    /// One check: passes when `condition` is true.
    @discardableResult
    static func t(_ condition: @autoclosure () throws -> Bool, _ what: @autoclosure () -> String,
                  file: StaticString = #filePath, line: UInt = #line) -> Bool {
        let ok: Bool
        do { ok = try condition() } catch {
            PPTestState.record(false, "\(what()) — threw \(type(of: error))", file, line)
            return false
        }
        PPTestState.record(ok, what(), file, line)
        return ok
    }

    /// Equality check that prints both values on failure.
    @discardableResult
    static func eq<T: Equatable>(_ actual: @autoclosure () throws -> T, _ expected: @autoclosure () -> T,
                                 _ what: @autoclosure () -> String, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        let a: T
        do { a = try actual() } catch {
            PPTestState.record(false, "\(what()) — threw \(type(of: error))", file, line)
            return false
        }
        let e = expected()
        let ok = a == e
        PPTestState.record(ok, ok ? what() : "\(what()): got \(String(reflecting: a)), expected \(String(reflecting: e))", file, line)
        return ok
    }

    /// Passes when `body` throws (an error of type `E`).
    @discardableResult
    static func throwsError<E: Error>(_ type: E.Type, _ what: @autoclosure () -> String, file: StaticString = #filePath,
                                      line: UInt = #line, _ body: () throws -> Void) -> Bool {
        do {
            try body()
            PPTestState.record(false, "\(what()) — did not throw", file, line)
            return false
        } catch is E {
            PPTestState.record(true, what(), file, line)
            return true
        } catch {
            PPTestState.record(false, "\(what()) — threw \(Swift.type(of: error)), expected \(E.self)", file, line)
            return false
        }
    }

    /// The harness printed "<suite>: N ok, M FAIL" here; `ppRunSuite` reports instead.
    static func pubSummary(_ suite: String) {}

    /// Checks so far in this suite.
    static var pubCounts: (ok: Int, fail: Int) {
        return PPTestState.counts
    }

    // MARK: Fixtures

    /// `Fixtures/` next to this file.
    static func fixturesDirectory() -> URL {
        return URL(fileURLWithPath: "\(#filePath)").deletingLastPathComponent().appendingPathComponent("Fixtures", isDirectory: true)
    }

    static func fixtureURL(_ name: String) -> URL {
        return fixturesDirectory().appendingPathComponent(name)
    }

    /// Bytes of a fixture; a missing fixture is a failed check (and empty data).
    static func fixture(_ name: String, file: StaticString = #filePath, line: UInt = #line) -> Data {
        guard let data = try? Data(contentsOf: fixtureURL(name)) else {
            PPTestState.record(false, "fixture not readable: \(name)", file, line)
            return Data()
        }
        return data
    }

    /// UTF-8 text of a fixture.
    static func fixtureText(_ name: String, file: StaticString = #filePath, line: UInt = #line) -> String {
        return String(decoding: fixture(name, file: file, line: line), as: UTF8.self)
    }

    // MARK: Async

    /// Runs async test code to completion from synchronous suite code. The main run loop keeps turning while it waits,
    /// so work hopping to the main actor / main queue still runs. A thrown error or the timeout is one failed check.
    static func runAsync(timeout: TimeInterval = 120, file: StaticString = #filePath, line: UInt = #line,
                         _ body: @escaping () async throws -> Void) {
        let box = PPAsyncBox()
        Task {
            do {
                try await body()
            } catch {
                PPTestState.record(false, "runAsync body threw \(type(of: error)): \(error)", file, line)
            }
            box.finish()
        }
        let deadline = Date().addingTimeInterval(timeout)
        while !box.isFinished {
            if Date() > deadline {
                PPTestState.record(false, "runAsync timed out after \(timeout) s", file, line)
                return
            }
            _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
    }

    // MARK: Helpers

    /// A fresh temporary directory.
    static func pubTempDir(_ prefix: String = "pubtest") -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Installs `PPEnglish.templates` as the localizer (any other key reads as itself) and returns how many keys it holds
    /// (the harness returned the number of keys it loaded from the app's tables; `lproj` / `tables` are ignored here).
    @discardableResult
    static func pubLoadStrings(lproj: String = "en", tables: [String]) -> Int {
        let table = PPEnglish.templates
        BILPublicText.localize = { table[$0] ?? $0 }
        return table.count
    }

    /// Lower-case hex of bytes (test output only).
    static func pubHex<S: Sequence>(_ bytes: S) -> String where S.Element == UInt8 {
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// `js/pubsigner-lib-bridge/signer.js` of this repository (the JS part of the package), nil when it is not there.
    static func signerJSURL() -> URL? {
        // Tests/OwnbitCoreTests/PublicProtocol/PPTestKit.swift → <repo>/js/pubsigner-lib-bridge/signer.js
        let repo = URL(fileURLWithPath: "\(#filePath)").deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = repo.appendingPathComponent("js/pubsigner-lib-bridge/signer.js")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}

/// The harness loaded the app's real `<lproj>.lproj/PublicProtocol.strings` for a few text checks (`pubLoadStrings`); the
/// package ships no strings tables, so the suites get this English subset instead (test data only: the app's en texts of
/// the keys those checks format, placeholders as the app's generator writes them, `%N$s` → `%N$@`, `%N$d` → `%N$ld`).
enum PPEnglish {
    static let templates: [String: String] = [
        "PublicProtocol.err.tooLarge": "The QR code data is larger than supported.",
        "PublicProtocol.err.qrMalformed": "The QR code is malformed or incomplete.",
        "PublicProtocol.err.pairingCode": "This is a pairing code for a watch-only wallet, not a signing request.",
        "PublicProtocol.err.signatureCode": "This is a signature for your other wallet, not a signing request. Scan it with the wallet that created the request.",
        "PublicProtocol.err.unsupportedUr": "This QR code type can't be signed here.",
        "PublicProtocol.scan.otherRequest": "This part belongs to another QR code. Scan again.",
        "PublicProtocol.err.scanTimeout": "Scanning stopped making progress. Start again.",
        "PublicProtocol.err.engineUnavailable": "The signing engine couldn't start. Restart Ownbit and try again.",
        "PublicProtocol.err.tpUnsupported": "Ownbit doesn't sign TokenPocket's own requests. To sign TRON with Ownbit, use TronLink (recommended). For EVM, add Ownbit to TokenPocket as a cold wallet by scanning the EVM “Wallet” code.",
        "PublicProtocol.err.tronlinkShielded": "Ownbit can't sign shielded (TRC-z) TRON transactions.",
        "PublicProtocol.err.tronlinkBlindHash": "TronLink asks Ownbit to sign a hash it can't read. Ownbit never signs hashes it can't check.",
        "PublicProtocol.err.tronlinkMessageV1": "TronLink asks for an old-format (v1) message signature. Ownbit signs only TRON messages in the current format (v2).",
        "PublicProtocol.err.integrity": "The request changed or is inconsistent. Nothing was signed. Scan it again.",
        "PublicProtocol.err.tronlinkType": "Ownbit can't sign this TronLink request type (%1$ld) yet.",
        "PublicProtocol.err.tronlinkMulti": "This TronLink request holds %1$ld transactions. Ownbit signs only one transaction per request.",
        "PublicProtocol.err.prevoutConflict": "Input %1$ld claims a different amount than a request this device already signed for the same coins. This may be an attempt to make you pay a huge fee, so Ownbit won't sign it. Create a new transaction in your other wallet.",
        "PublicProtocol.err.tronOwner": "This transaction is for account %1$@, not this wallet's address.",
        // The app's UI.strings / SendC.strings texts of the internal `bb_sign:` UTXO refusals.
        "QR code format or content is incorrect": "QR code format or content is incorrect",
        "SendC.confirm.buildTxFailed": "Transaction is failed",
    ]
}

/// The harness's `BILStubStrings`: `reset()` puts the identity localizer back.
enum BILStubStrings {
    static func reset() {
        BILPublicText.localize = { $0 }
    }
}

/// The resume flag of `runAsync`.
final class PPAsyncBox {
    private let lock = NSLock()
    private var finished = false
    var isFinished: Bool { lock.lock(); defer { lock.unlock() }; return finished }
    func finish() { lock.lock(); finished = true; lock.unlock() }
}

/// Runs one suite as one XCTest and reports its check counts.
func ppRunSuite(_ name: String, file: StaticString = #filePath, line: UInt = #line, _ body: () throws -> Void) rethrows {
    PPTestState.begin()
    defer { BILPublicText.localize = { $0 } }
    try body()
    let c = PPTestState.counts
    print("\(name): \(c.ok) ok, \(c.fail) FAIL")
    if c.ok == 0 && c.fail == 0 {
        XCTFail("\(name): no check ran", file: file, line: line)
    }
}
