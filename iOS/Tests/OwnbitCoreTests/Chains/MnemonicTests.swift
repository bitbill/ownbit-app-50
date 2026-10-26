//  MnemonicTests.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  The Mnemonic facade: generation (web view, window.crypto), the offline check, the BIP39 check, seeds with and without
//  a passphrase, and the passphrase coin rule.

import Foundation
import XCTest
@testable import OwnbitCore

final class MnemonicTests: XCTestCase {

    func testGenerateTwelveAndTwentyFourWords() async throws {
        try ChainsTestSupport.useRepositoryJS([ChainsTestSupport.bitcoinPage, ChainsTestSupport.bitcoinJS, ChainsTestSupport.wordlist])
        var seen = Set<String>()
        for count in Mnemonic.WordCount.allCases {
            let mnemonic = try await Mnemonic.generate(wordCount: count)
            let words = mnemonic.split(separator: " ")
            XCTAssertEqual(words.count, count.rawValue)
            XCTAssertTrue(words.allSatisfy { $0.allSatisfy { ("a"..."z").contains($0) } }, "English words only")
            XCTAssertNil(Mnemonic.check(mnemonic).issue)
            let normalized = try await Mnemonic.validate(mnemonic)
            XCTAssertEqual(normalized, mnemonic)
            XCTAssertTrue(seen.insert(mnemonic).inserted, "two generations must differ")
        }
    }

    func testOfflineCheck() throws {
        try ChainsTestSupport.useRepositoryJS([ChainsTestSupport.wordlist])
        XCTAssertTrue(BILMnemonicValidator.shared.isLoaded)

        let messy = "  ABANDON abandon\tabandon abandon abandon abandon\nabandon abandon abandon abandon abandon\u{3000}about "
        let ok = Mnemonic.check(messy)
        XCTAssertNil(ok.issue)
        XCTAssertEqual(ok.normalized, PassphraseVectors.abandon)
        XCTAssertEqual(ok.language, .english)

        let badChecksum = Array(repeating: "abandon", count: 12).joined(separator: " ")
        XCTAssertEqual(Mnemonic.check(badChecksum).issue, .invalidChecksum)

        XCTAssertEqual(Mnemonic.check("abandon abandon about").issue, .invalidCount(3))
        XCTAssertEqual(Mnemonic.check(PassphraseVectors.abandon.replacingOccurrences(of: "about", with: "abuot")).issue, .invalidWords(["abuot"]))
        XCTAssertEqual(Mnemonic.check("   ").issue, .empty)

        XCTAssertTrue(BILMnemonicValidator.shared.looksLikeMnemonic("1. " + PassphraseVectors.abandon))
        XCTAssertFalse(BILMnemonicValidator.shared.looksLikeMnemonic("{\"index\": 1, \"value\": \"abandon\"}"))
    }

    func testValidateUsesTheBundleCheckToo() async throws {
        try ChainsTestSupport.useRepositoryJS([ChainsTestSupport.bitcoinJS, ChainsTestSupport.wordlist])
        let normalized = try await Mnemonic.validate(" Legal winner thank year wave sausage worth useful legal winner thank yellow ")
        XCTAssertEqual(normalized, "legal winner thank year wave sausage worth useful legal winner thank yellow")
        do {
            _ = try await Mnemonic.validate(Array(repeating: "abandon", count: 12).joined(separator: " "))
            XCTFail("invalid checksum accepted")
        } catch Mnemonic.MnemonicError.invalid(let issue) {
            XCTAssertEqual(issue, .invalidChecksum)
        }
    }

    func testSeedWithAndWithoutPassphrase() async throws {
        try ChainsTestSupport.useRepositoryJS([ChainsTestSupport.bitcoinJS])
        for v in PassphraseVectors.all {
            let seed = try await Mnemonic.seedHex(mnemonic: v.mnemonic, passphrase: v.passphrase)
            XCTAssertEqual(seed, v.seed, "[\(v.name)]")
        }
        let noPassphrase = try await Mnemonic.seedHex(mnemonic: PassphraseVectors.abandon)
        XCTAssertEqual(noPassphrase, PassphraseVectors.all[1].seed)
    }

    func testPassphraseCoinRule() {
        XCTAssertEqual(Mnemonic.passphraseUnsupportedCoinTypes, [.ton, .ton20Token, .ada])
        for type in OwnbitCoinType.allCases {
            XCTAssertEqual(Mnemonic.isUnsupportedWithPassphrase(type), [.ton, .ton20Token, .ada].contains(type), "\(type)")
        }
    }
}
