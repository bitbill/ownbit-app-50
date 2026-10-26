//  PassphraseVectorTests.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Known answers from the app's BIP39 passphrase self-test (BILDebugPassphrase): the seed of every vector (passphrases
//  with quotes, backslashes, newlines, U+2028 and a JS injection string go through `jsEscaped` into the bundle), and for
//  "abandon ×11 about" with "TREZOR" and with no passphrase the first receive address of BTC BIP44 / 49 / 84 / 86, ETH,
//  TRX, SOL, XLM and XRP, computed by the same bridge functions the app uses to create wallets.

import Foundation
import XCTest
@testable import OwnbitCore

final class PassphraseVectorTests: XCTestCase {

    // MARK: - JSContext bundles

    func testSeedHexOfEveryVector() async throws {
        try ChainsTestSupport.useRepositoryJS([ChainsTestSupport.bitcoinJS])
        for v in PassphraseVectors.all {
            let seed: String = try await ChainsTestSupport.call { done in
                BitcoinJSBridge.shared.mnemonicToSeedHex(mnemonic: v.mnemonic, password: v.passphrase, seedType: SEEDTYPE_BIP39, success: {
                    done(.success(($0 as? String) ?? ""))
                }, failure: { done(.failure($0)) })
            }
            XCTAssertEqual(seed, v.seed, "[\(v.name)] seed")
        }
    }

    func testBitcoinLegacyNestedNative() async throws {
        try ChainsTestSupport.useRepositoryJS([ChainsTestSupport.bitcoinJS])
        for v in PassphraseVectors.abandonPair {
            let keys: (mainPubkey: String, changePubkey: String, extPubkeyBip49: String, changePubkeyBip49: String, extPubkeyBip84: String, changePubkeyBip84: String) =
                try await ChainsTestSupport.call { done in
                    BitcoinJSBridge.shared.getXPublicKeysForAll(seed: v.seed, seedTypePath: "0", success: { done(.success($0)) }, failure: { done(.failure($0)) })
                }
            let legacy: [String] = try await ChainsTestSupport.call { done in
                BitcoinJSBridge.shared.getAddresses(xpub: keys.mainPubkey, fromIndex: 0, toIndex: 1, success: { done(.success(($0 as? [String]) ?? [])) }, failure: { done(.failure($0)) })
            }
            let nested: [String] = try await ChainsTestSupport.call { done in
                BitcoinJSBridge.shared.getAddresses_sw_p(xpub: keys.extPubkeyBip49, fromIndex: 0, toIndex: 1, success: { done(.success(($0 as? [String]) ?? [])) }, failure: { done(.failure($0)) })
            }
            let native: [String] = try await ChainsTestSupport.call { done in
                BitcoinJSBridge.shared.getAddresses_sw_d(xpub: keys.extPubkeyBip84, fromIndex: 0, toIndex: 1, success: { done(.success(($0 as? [String]) ?? [])) }, failure: { done(.failure($0)) })
            }
            XCTAssertEqual(legacy.first, v.btc44, "[\(v.name)] BTC BIP44")
            XCTAssertEqual(nested.first, v.btc49, "[\(v.name)] BTC BIP49")
            XCTAssertEqual(native.first, v.btc84, "[\(v.name)] BTC BIP84")
        }
    }

    func testEthereum() async throws {
        try ChainsTestSupport.useRepositoryJS([ChainsTestSupport.ethereumJS])
        for v in PassphraseVectors.abandonPair {
            let account: (xpub: String, address: String) = try await ChainsTestSupport.call { done in
                EthereumJSBridge.shared.getPublicKeyAndAddress(seed: v.seed, indexNo: 0, success: { xpub, _, address in
                    done(.success((xpub, address)))
                }, failure: { done(.failure($0)) })
            }
            XCTAssertEqual(account.address, v.eth, "[\(v.name)] ETH")
            // the watch-side derivation from the account xpub gives the same address
            let fromXpub: String = try await ChainsTestSupport.call { done in
                EthereumJSBridge.shared.getPublicKeyAndAddress(extPubKey: account.xpub, indexNo: 0, success: { _, address in
                    done(.success(address))
                }, failure: { done(.failure($0)) })
            }
            XCTAssertEqual(fromXpub.lowercased(), v.eth.lowercased(), "[\(v.name)] ETH from xpub")
        }
    }

    func testRipple() async throws {
        try ChainsTestSupport.useRepositoryJS([ChainsTestSupport.rippleJS])
        for v in PassphraseVectors.abandonPair {
            let address: String = try await ChainsTestSupport.call { done in
                RippleJSBridge.shared.getPublicKeyAndAddress(seed: v.seed, success: { _, a in done(.success(a)) }, failure: { done(.failure($0)) })
            }
            XCTAssertEqual(address, v.xrp, "[\(v.name)] XRP")
        }
    }

    func testStellar() async throws {
        try ChainsTestSupport.useRepositoryJS([ChainsTestSupport.stellarJS])
        for v in PassphraseVectors.abandonPair {
            let address: String = try await ChainsTestSupport.call { done in
                StellarJSBridge.shared.getPublicKeyAndAddress(seed: v.seed, isNew: true, success: { _, a in done(.success(a)) }, failure: { done(.failure($0)) })
            }
            XCTAssertEqual(address, v.xlm, "[\(v.name)] XLM")
        }
    }

    // MARK: - Web view bundles

    func testBitcoinTaproot() async throws {
        try ChainsTestSupport.useRepositoryJS([ChainsTestSupport.taprootPage, ChainsTestSupport.taprootJS])
        for v in PassphraseVectors.abandonPair {
            let xpubs: (receive: String, change: String) = try await ChainsTestSupport.call { done in
                BTCTaprootJSBridge.shared.getTaprootXpubs(seedHex: v.seed, success: { done(.success(($0, $1))) }, failure: { done(.failure($0)) })
            }
            let addresses: [String] = try await ChainsTestSupport.call { done in
                BTCTaprootJSBridge.shared.getTaprootAddresses(xpub: xpubs.receive, from: 0, to: 0, success: { done(.success($0)) }, failure: { done(.failure($0)) })
            }
            XCTAssertEqual(addresses, [v.btc86], "[\(v.name)] BTC BIP86")
        }
    }

    func testTron() async throws {
        try ChainsTestSupport.useRepositoryJS([ChainsTestSupport.ethereumJS, ChainsTestSupport.tronPage, ChainsTestSupport.tronJS])
        for v in PassphraseVectors.abandonPair {
            let privateKey: String = try await ChainsTestSupport.call { done in
                EthereumJSBridge.shared.seedHexToTrxPrivateKey(seedHex: v.seed, success: { done(.success($0)) }, failure: { done(.failure($0)) })
            }
            let address: String = try await ChainsTestSupport.call { done in
                TronJSBridge.shared.getPublicKeyAndAddress(privateKey: privateKey, success: { _, a in done(.success(a)) }, failure: { done(.failure($0)) })
            }
            XCTAssertEqual(address, v.trx, "[\(v.name)] TRX")
        }
    }

    func testSolana() async throws {
        try ChainsTestSupport.useRepositoryJS([ChainsTestSupport.solanaPage, ChainsTestSupport.solanaJS])
        for v in PassphraseVectors.abandonPair {
            let address: String = try await ChainsTestSupport.call { done in
                SolanaJSBridge.shared.getPublicKeyAndAddress(seed: v.seed, success: { _, a in done(.success(a)) }, failure: { done(.failure($0)) })
            }
            XCTAssertEqual(address, v.sol, "[\(v.name)] SOL")
        }
    }
}
