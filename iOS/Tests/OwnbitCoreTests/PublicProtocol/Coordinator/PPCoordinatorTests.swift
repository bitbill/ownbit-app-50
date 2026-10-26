//  PPCoordinatorTests.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Port of the app harness suite `scripts/public-protocol/tests/coordinator` (main.swift) to XCTest.
//
//  main.swift — suite "coordinator" (WP19). Runs every group on the main actor (the coordinator's isolation) and prints
//  "coordinator-core: N ok, M FAIL".
//

import Foundation
import XCTest
@testable import OwnbitCore

/// The suite namespace (harness helpers are its static members).
enum PPCoordinatorSuite: PPSuite {}

final class PPCoordinatorTests: XCTestCase {
    func testCoordinator() throws {
        try ppRunSuite("coordinator") { try PPCoordinatorSuite.run() }
    }
}

extension PPCoordinatorSuite {

    /// The harness main.swift (nonisolated top-level code, as in the harness).
    static func run() throws {
        runAsync(timeout: 600) {
            await unitTests()
            await coordinatorTests()
            await round2Tests()
            if ProcessInfo.processInfo.environment["PUB_COORD_SKIP_REAL"] != "1" { await realEngineTests() }
        }
        pubSummary("coordinator-core")
    }
}
