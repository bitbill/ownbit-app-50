//  PPVerifierTests.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Port of the app harness suite `scripts/public-protocol/tests/verifier` (main.swift) to XCTest.
//
//  main.swift — the verifier suite (WP13): BILPublicSignVerifier, BILPsbtMaps+Claims, BILPublicSignPolicy and
//  BILPublicSignInsight on the golden vectors ($PUB_FIXTURES/vectors.json, tp-v1.json) with the real D43 interpreter.
//  Prints failures and "verifier (macOS): N ok, M FAIL" (exit 1 on any failure). PUB_TEST_VERBOSE=1 prints every check.
//

import Foundation
import XCTest
@testable import OwnbitCore

/// The suite namespace (harness helpers are its static members).
enum PPVerifierSuite: PPSuite {}

final class PPVerifierTests: XCTestCase {
    func testVerifier() throws {
        try ppRunSuite("verifier") { try PPVerifierSuite.run() }
    }
}

extension PPVerifierSuite {

    static let started = Date()

    /// The harness main.swift (nonisolated top-level code, as in the harness).
    static func run() throws {
        verifierTests()
        policyTests()
        // (insightTests — the D43 card read by the app's Security Center interpreter and known-contract library — is not
        // ported: the interpreter is host code, `BILPublicSignCoordinator.Dependencies.interpret`.)
        print(String(format: "verifier: %.1f s", Date().timeIntervalSince(started)))
    }
}
