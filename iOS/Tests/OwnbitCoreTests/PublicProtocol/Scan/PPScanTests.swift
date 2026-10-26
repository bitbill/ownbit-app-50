//  PPScanTests.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Port of the app harness suite `scripts/public-protocol/tests/scan` (main.swift) to XCTest.
//
//  main.swift — scan suite (WP10): classification, frame gate + queue, TronLink codecs / collector / mapper / answers,
//  strict TRON Transaction, scan session (fake engine, virtual clock), paste pre-routing, TokenPocket refusal.
//  Prints "scan: N ok, M FAIL".
//

import Foundation
import XCTest
@testable import OwnbitCore

/// The suite namespace (harness helpers are its static members).
enum PPScanSuite: PPSuite {}

final class PPScanTests: XCTestCase {
    func testScan() throws {
        try ppRunSuite("scan") { try PPScanSuite.run() }
    }
}

extension PPScanSuite {

    /// The harness main.swift (nonisolated top-level code, as in the harness).
    static func run() throws {
        formatTests()
        gateTests()
        tronLinkTests()
        progressTests()
        pasteTests()
        runAsync(timeout: 300) { await sessionTests() }
        pubSummary("scan")
    }
}
