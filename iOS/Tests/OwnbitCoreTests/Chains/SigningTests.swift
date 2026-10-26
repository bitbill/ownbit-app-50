//  SigningTests.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Signing paths: the EIP-712 example of the EIP itself (known answer, through the web view's message channel),
//  personal_sign / Bitcoin message / BIP-322 round trips with a message full of characters that need escaping, and
//  deterministic EIP-1559 / Solana signatures (message-channel results). Keys: the public "abandon ×11 about" vectors and
//  the EIP-712 example key keccak256("cow").

import Foundation
import XCTest
@testable import OwnbitCore

final class SigningTests: XCTestCase {

    /// Contains every character `jsEscaped` handles, plus text that would be decoded if it reached JS unescaped.
    static let trickyMessage = "it's a \"test\"\nline 2\r\\x30\\x78 \u{2028}end'); throw 1; ('"

    private var vector: PassphraseVector { return PassphraseVectors.all[1] } // abandon … about, no passphrase

    // MARK: - EVM

    /// EIP-712 "Ether Mail" example from the EIP (private key keccak256("cow")).
    func testEIP712KnownAnswer() async throws {
        try ChainsTestSupport.useRepositoryJS(["ethereumjs-lib-bridge/ethext_index.html", "ethereumjs-lib-bridge/ethjs-ext-v2.js"])
        let typedData = """
        {"types":{"EIP712Domain":[{"name":"name","type":"string"},{"name":"version","type":"string"},{"name":"chainId","type":"uint256"},{"name":"verifyingContract","type":"address"}],"Person":[{"name":"name","type":"string"},{"name":"wallet","type":"address"}],"Mail":[{"name":"from","type":"Person"},{"name":"to","type":"Person"},{"name":"contents","type":"string"}]},"primaryType":"Mail","domain":{"name":"Ether Mail","version":"1","chainId":1,"verifyingContract":"0xCcCCccccCCCCcCCCCCCcCcCccCcCCCcCcccccccC"},"message":{"from":{"name":"Cow","wallet":"0xCD2a3d9F938E13CD947Ec05AbC7FE734Df8DD826"},"to":{"name":"Bob","wallet":"0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB"},"contents":"Hello, Bob!"}}
        """
        let signature: String = try await ChainsTestSupport.call(timeout: 300) { done in
            EthereumExtJSBridge.shared.signTypedData(privKey: "c85ef7d79691fe79573b1a7064c19c1a9819ebdbd1faaab1a8ec92344438aaf4", params: typedData, success: {
                done(.success($0))
            }, failure: { done(.failure($0)) })
        }
        XCTAssertEqual(signature.lowercased(), "0x4355c47d63924e8a72e509b65029052eb6c299d53a04e167c5775fd466751c9d07299936d304c153f6443dfa05f40ff007d72911b6f72307f996231605b915621c")
    }

    func testPersonalSignRoundTrip() async throws {
        try ChainsTestSupport.useRepositoryJS([ChainsTestSupport.ethereumJS])
        let v = vector
        let privateKey: String = try await ChainsTestSupport.call { done in
            EthereumJSBridge.shared.seedHexToPrivateHex(seedHex: v.seed, indexNo: 0, success: { done(.success($0)) }, failure: { done(.failure($0)) })
        }
        let signature: String = try await ChainsTestSupport.call { done in
            EthereumJSBridge.shared.signEthereumMessage(message: SigningTests.trickyMessage, privateKey: privateKey, success: { done(.success($0)) }, failure: { done(.failure($0)) })
        }
        XCTAssertEqual(signature.count, 132)
        let signer: String = try await ChainsTestSupport.call { done in
            EthereumJSBridge.shared.getMessageSignAddress(message: SigningTests.trickyMessage, signature: signature, success: { done(.success($0)) }, failure: { done(.failure($0)) })
        }
        XCTAssertEqual(signer.lowercased(), v.eth.lowercased())
        // a different text (what an unescaped "\x30\x78" would have become) does not verify
        let other: String = try await ChainsTestSupport.call { done in
            EthereumJSBridge.shared.getMessageSignAddress(message: "it's a \"test\"\nline 2\r0x", signature: signature, success: { done(.success($0)) }, failure: { done(.failure($0)) })
        }
        XCTAssertNotEqual(other.lowercased(), v.eth.lowercased())
    }

    /// EIP-1559 transfer through the `transaction` message channel; ECDSA (RFC 6979) is deterministic.
    func testEIP1559TransferIsDeterministic() async throws {
        try ChainsTestSupport.useRepositoryJS(["ethereumjs-lib-bridge/ethext_index.html", "ethereumjs-lib-bridge/ethjs-ext-v2.js"])
        let v = vector
        func sign() async throws -> (String, String) {
            return try await ChainsTestSupport.call(timeout: 300) { done in
                EthereumExtJSBridge.shared.buildEthTransaction(seedHex: v.seed, indexNo: 0, addressTo: PassphraseVectors.all[0].eth, amountWei: NSDecimalNumber(string: "1000000000000000"), nonce: 7, gasPrice: 30_000_000_000, gasPriority: 1_000_000_000, gasLimit: 21_000, chainId: 1, success: {
                    done(.success(($0, $1)))
                }, failure: { done(.failure($0)) })
            }
        }
        let first = try await sign()
        let second = try await sign()
        XCTAssertTrue(first.1.hasPrefix("0x02"), "type-2 transaction")
        XCTAssertEqual(first.0.count, 66)
        XCTAssertEqual(first.0, second.0)
        XCTAssertEqual(first.1, second.1)
    }

    // MARK: - BTC

    func testBitcoinMessageRoundTrip() async throws {
        try ChainsTestSupport.useRepositoryJS([ChainsTestSupport.bitcoinJS])
        let v = vector
        let wif: String = try await ChainsTestSupport.call { done in
            BitcoinJSBridge.shared.getWIFFromSeedHex(v.seed, seedTypePath: "0", index: 0, isChange: false, success: { done(.success($0)) }, failure: { done(.failure($0)) })
        }
        let signature: String = try await ChainsTestSupport.call { done in
            BitcoinJSBridge.shared.signMessage(wif: wif, address: v.btc44, message: SigningTests.trickyMessage, success: { done(.success($0)) }, failure: { done(.failure($0)) })
        }
        let valid: Bool = try await ChainsTestSupport.call { done in
            BitcoinJSBridge.shared.verifyMessageSignature(message: SigningTests.trickyMessage, address: v.btc44, signature: signature, success: { done(.success($0)) }, failure: { done(.failure($0)) })
        }
        XCTAssertTrue(valid)
        XCTAssertTrue(BTCTaprootJSBridge.isLegacyMessageSignature(signature))
    }

    func testBIP322RoundTrip() async throws {
        try ChainsTestSupport.useRepositoryJS([ChainsTestSupport.taprootPage, ChainsTestSupport.taprootJS])
        let v = vector
        let signature: String = try await ChainsTestSupport.call(timeout: 300) { done in
            BTCTaprootJSBridge.shared.signMessage(seedHex: v.seed, isChange: false, index: 0, address: v.btc86, message: SigningTests.trickyMessage, success: { done(.success($0)) }, failure: { done(.failure($0)) })
        }
        let result: BTCTaprootJSBridge.BIP322Result = try await ChainsTestSupport.call { done in
            BTCTaprootJSBridge.shared.verifyMessage(address: v.btc86, message: SigningTests.trickyMessage, signature: signature, success: { done(.success($0)) }, failure: { done(.failure($0)) })
        }
        XCTAssertEqual(result, .valid)
        XCTAssertFalse(BTCTaprootJSBridge.isLegacyMessageSignature(signature))
        // the wrong address for this key is refused before signing
        do {
            let _: String = try await ChainsTestSupport.call { done in
                BTCTaprootJSBridge.shared.signMessage(seedHex: v.seed, isChange: false, index: 0, address: PassphraseVectors.all[0].btc86, message: "x", success: { done(.success($0)) }, failure: { done(.failure($0)) })
            }
            XCTFail("signed for an address that is not this key's")
        } catch {
        }
    }

    // MARK: - TRX

    /// TRX transfer from TUEZSdKsoDHQMeZwihtdoBiN46zxhGWYdH (abandon … about, no passphrase); expected r ‖ s from the
    /// app's public-protocol fixtures (scripts/public-protocol/fixtures/native-vectors.json, vector 4, signatureV 27).
    /// TronWeb appends v as 27 + recovery id ("1B"); the fixture writes the recovery id ("00"). Goes through the `signed`
    /// and `multiSigned` message channels.
    func testTronSignKnownAnswer() async throws {
        try ChainsTestSupport.useRepositoryJS([ChainsTestSupport.ethereumJS, ChainsTestSupport.tronPage, ChainsTestSupport.tronJS])
        let txJson = """
        {"visible":false,"txID":"2b4e75505adb4da63b985fa30cab925b334bf5c1432d547c79a780130f3423f5","raw_data":{"ref_block_bytes":"0001","ref_block_hash":"0000000000000000","expiration":1800000060000,"contract":[{"parameter":{"value":{"owner_address":"41c8599111f29c1e1e061265b4af93ea1f274ad78a","to_address":"415cbdd86a2fa8dc4bddd8a8f69dba48572eec07fb","amount":1000000},"type_url":"type.googleapis.com/protocol.TransferContract"},"type":"TransferContract"}],"timestamp":1800000000000},"raw_data_hex":"0a0200012208000000000000000040e0f4f4c2b1345a67080112630a2d747970652e676f6f676c65617069732e636f6d2f70726f746f636f6c2e5472616e73666572436f6e747261637412320a1541c8599111f29c1e1e061265b4af93ea1f274ad78a1215415cbdd86a2fa8dc4bddd8a8f69dba48572eec07fb18c0843d7080a0f1c2b134"}
        """
        let expected = "0b00682655dea28ca48e09034ec29f276380716bd604a0e5de99831a5510bace1913bc9c8268656f7e3bd798b3fc50f7e17b4716e071255900737019adc7e4eb1b"
        let v = vector
        let privateKey: String = try await ChainsTestSupport.call { done in
            EthereumJSBridge.shared.seedHexToTrxPrivateKey(seedHex: v.seed, success: { done(.success($0)) }, failure: { done(.failure($0)) })
        }
        let signedJson: String = try await ChainsTestSupport.call { done in
            TronJSBridge.shared.buildTrxTransaction(privateKey: privateKey, txJson: txJson, success: { done(.success($0)) }, failure: { done(.failure($0)) })
        }
        let signed = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(signedJson.utf8)) as? [String: Any])
        XCTAssertEqual((signed["signature"] as? [String])?.map { $0.lowercased() }, [expected])
        XCTAssertEqual(signed["txID"] as? String, "2b4e75505adb4da63b985fa30cab925b334bf5c1432d547c79a780130f3423f5")

        let cosignature: String = try await ChainsTestSupport.call { done in
            TronJSBridge.shared.buildTrxSigForMultiSig(privateKey: privateKey, txJson: txJson, success: { done(.success($0)) }, failure: { done(.failure($0)) })
        }
        XCTAssertEqual(cosignature.lowercased(), expected)

        // another key than the owner's: TronWeb refuses, reported on the error channel
        do {
            let _: String = try await ChainsTestSupport.call { done in
                TronJSBridge.shared.buildTrxTransaction(privateKey: String(repeating: "11", count: 32), txJson: txJson, success: { done(.success($0)) }, failure: { done(.failure($0)) })
            }
            XCTFail("signed with a key that does not own the transaction")
        } catch JSBridge.JSError.scriptError {
        }
    }

    // MARK: - SOL

    /// Transfer through the `transaction` message channel (patched send path returns the signed transaction).
    func testSolanaTransferIsDeterministic() async throws {
        try ChainsTestSupport.useRepositoryJS([ChainsTestSupport.solanaPage, ChainsTestSupport.solanaJS])
        let v = vector
        func sign() async throws -> String {
            return try await ChainsTestSupport.call(timeout: 300) { done in
                SolanaJSBridge.shared.buildTransaction(seed: v.seed, toAddress: PassphraseVectors.all[0].sol, amount: "100000", fee: 0, recentBlockHash: "11111111111111111111111111111111", recentBlockHeight: 1, success: {
                    done(.success($0))
                }, failure: { done(.failure($0)) })
            }
        }
        let first = try await sign()
        let second = try await sign()
        XCTAssertNotNil(Data(base64Encoded: first), "base64 transaction")
        XCTAssertEqual(first, second)

        // the host-set RPC URL only reaches the Connection constructor: same signed transaction, still offline
        XCTAssertEqual(SolanaJSBridge.provider, JSBridge.offlineProviderPlaceholder)
        SolanaJSBridge.provider = "http://localhost:8899"
        defer { SolanaJSBridge.provider = JSBridge.offlineProviderPlaceholder }
        let withProvider = try await sign()
        XCTAssertEqual(withProvider, first)
    }
}
