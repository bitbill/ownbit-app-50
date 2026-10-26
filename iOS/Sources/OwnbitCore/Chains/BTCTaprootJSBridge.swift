//  BTCTaprootJSBridge.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  BTC Taproot (bc1p, BIP86, key path only).
//  - Bundle btctaproot-lib-app.js (bitcoinjs-lib 6 + @bitcoinerlab/secp256k1) in a hidden web view (btc_taproot_index.html):
//    signing nonces come from `window.crypto`. The legacy bitcoinjs bundle is untouched.
//  - Taproot xpubs (m/86'/0'/0'/0 and /1, standard xpub version bytes), bc1p addresses, transactions that spend at least
//    one Taproot UTXO (other inputs may be mixed in: their WIFs come from BitcoinJSBridge.getWIFFromSeedHex* by the usual
//    path rules and are passed in the data; only the WIF is used here).
//  - Private-key wallets: the bc1p address of that key, and spending it (whole transaction signed with that key).
//  - BIP-322 message signing / verification for bc1p.
//  Arguments are JSON-encoded one by one into JS literals (strings are escaped by the JSON encoder), as in the app.

import Foundation

public final class BTCTaprootJSBridge: JSBridge, BILCoinMultipleAddressGeneratorProtocol {

    public static let shared = BTCTaprootJSBridge()

    /// The app hid Taproot below iOS 14.5 (the bundle uses BigInt and Safari 14.1 syntax). This package requires iOS 15.
    public static var isSupported: Bool {
        return true
    }

    /// Mainnet Taproot address (bech32m, witness v1, 32-byte program): 62 characters, starts with bc1p.
    public static func isTaprootAddress(_ address: String) -> Bool {
        let a = address.lowercased()
        return a.hasPrefix("bc1p") && a.count == 62
    }

    override var webPage: Resource? {
        return Resource(name: "btc_taproot_index", ext: "html", directory: "btctaprootjs-lib-bridge")
    }

    /// Load early (the app did this on the send page when Taproot UTXOs were present): the first load takes seconds.
    public func preload() {
        preloadWeb()
    }

    /// One JSON literal per argument (strings escaped by the encoder), never raw string concatenation.
    private static func jsLiteral(_ value: Any) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: .fragmentsAllowed) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// bridge.<function>(args…)
    private func call(_ function: String, _ args: [Any], success: @escaping (_ result: Any?) -> Void, failure: @escaping (_ error: Error) -> Void) {
        var literals: [String] = []
        for arg in args {
            guard let literal = BTCTaprootJSBridge.jsLiteral(arg) else {
                DispatchQueue.main.async { failure(JSError.resultError) }
                return
            }
            literals.append(literal)
        }
        callWeb(method: "bridge.\(function)(\(literals.joined(separator: ",")))", success: success, failure: failure)
    }

    // MARK: - Taproot API

    /// BIP86 chain-level xpubs: receive m/86'/0'/0'/0, change m/86'/0'/0'/1 (standard xpub version bytes).
    public func getTaprootXpubs(seedHex: String, success: @escaping (_ receive: String, _ change: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        call("getTaprootXpubs", [seedHex], success: { result in
            guard let arr = result as? [Any], arr.count >= 2, let receive = arr[0] as? String, let change = arr[1] as? String,
                  receive.hasPrefix("xpub"), change.hasPrefix("xpub") else {
                failure(JSError.resultError)
                return
            }
            success(receive, change)
        }, failure: failure)
    }

    /// bc1p addresses from...to (inclusive) of a chain-level xpub.
    public func getTaprootAddresses(xpub: String, from: Int64, to: Int64, success: @escaping (_ addresses: [String]) -> Void, failure: @escaping (_ error: Error) -> Void) {
        guard from >= 0, from <= to else {
            DispatchQueue.main.async { failure(JSError.resultError) }
            return
        }
        call("getTaprootAddresses", [xpub, from, to], success: { result in
            guard let arr = result as? [String], arr.count == Int(to - from + 1), arr.allSatisfy({ BTCTaprootJSBridge.isTaprootAddress($0) }) else {
                failure(JSError.resultError)
                return
            }
            success(arr)
        }, failure: failure)
    }

    /// Builds and signs a transaction with at least one Taproot input. `data` has the same inputs / outputs / ophex /
    /// locktime as BitcoinJSBridge.buildTransaction; inputs with segwit = "T" are Taproot (may carry the server's
    /// scriptPubKey, checked in JS), every other input carries its WIF. success: (txId, txHex).
    public func buildTransaction(seedHex: String, data: String, success: @escaping (_ object: (txId: String, txHex: String)) -> Void, failure: @escaping (_ error: Error) -> Void) {
        call("buildTransaction", [seedHex, data], success: { result in
            guard let arr = result as? [Any], arr.count >= 2, let txId = arr[0] as? String, let txHex = arr[1] as? String,
                  txId.count == 64, !txHex.isEmpty else {
                failure(JSError.resultError)
                return
            }
            success((txId, txHex))
        }, failure: failure)
    }

    /// Private-key wallet: the Taproot address of a public key (compressed or not; the x coordinate is used).
    public func getTaprootAddress(publicKey: String, success: @escaping (_ address: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        call("getTaprootAddressFromPublicKey", [publicKey], success: { result in
            guard let address = result as? String, BTCTaprootJSBridge.isTaprootAddress(address) else {
                failure(JSError.resultError)
                return
            }
            success(address)
        }, failure: failure)
    }

    /// Private-key wallet with Taproot inputs: `privateKey` is the same string given to
    /// BitcoinJSBridge.buildTransaction(privateKey:) (WIF, or hex = uncompressed key by the legacy bundle's rule); every
    /// input is signed with it, Taproot inputs with the tweaked key.
    public func buildTransaction(privateKey: String, data: String, success: @escaping (_ object: (txId: String, txHex: String)) -> Void, failure: @escaping (_ error: Error) -> Void) {
        call("buildTransactionWithPrivateKey", [privateKey, data], success: { result in
            guard let arr = result as? [Any], arr.count >= 2, let txId = arr[0] as? String, let txHex = arr[1] as? String,
                  txId.count == 64, !txHex.isEmpty else {
                failure(JSError.resultError)
                return
            }
            success((txId, txHex))
        }, failure: failure)
    }

    // MARK: - BIP-322 message signing

    /// The legacy "Bitcoin Signed Message" format (ECDSA with public-key recovery) can't express Taproot, so bc1p uses
    /// BIP-322: simple format, key path, SIGHASH_DEFAULT, without the "smp" prefix (most verifiers don't accept it yet;
    /// verification accepts both). Details at the end of the bundle's source.
    public enum BIP322Result: String {
        case valid, invalid
        /// Can't be checked here (scripts such as multisig, proof-of-funds format): not the same as "invalid".
        case unsupported
    }

    /// Mnemonic wallet: signs with the key of m/86'/0'/0'/{isChange ? 1 : 0}/{index}. `address` is that key's address;
    /// JS re-derives it and refuses to sign if it doesn't match.
    public func signMessage(seedHex: String, isChange: Bool, index: Int64, address: String, message: String, success: @escaping (_ signature: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        call("signMessageBip322", [seedHex, isChange, index, address, message], success: { result in
            guard let signature = result as? String, !signature.isEmpty else {
                failure(JSError.resultError)
                return
            }
            success(signature)
        }, failure: failure)
    }

    /// Private-key wallet: signs for that key's bc1p address (privateKey as in buildTransaction(privateKey:)).
    public func signMessage(privateKey: String, address: String, message: String, success: @escaping (_ signature: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        call("signMessageBip322WithPrivateKey", [privateKey, address, message], success: { result in
            guard let signature = result as? String, !signature.isEmpty else {
                failure(JSError.resultError)
                return
            }
            success(signature)
        }, failure: failure)
    }

    /// BIP-322 verification: simple (with or without "smp") / full ("ful"); Taproot and bc1q single-sig; 3… / 1… only in
    /// the full format.
    public func verifyMessage(address: String, message: String, signature: String, success: @escaping (_ result: BIP322Result) -> Void, failure: @escaping (_ error: Error) -> Void) {
        call("verifyMessageBip322", [address, message, signature], success: { result in
            guard let raw = result as? String, let r = BIP322Result(rawValue: raw) else {
                failure(JSError.resultError)
                return
            }
            success(r)
        }, failure: failure)
    }

    /// A legacy (BIP137 / Electrum) signature: base64 of exactly 65 bytes whose first byte is 27...42. A BIP-322 signature
    /// never looks like that (simple starts with the witness count 1 / 2, full with the tx version; smp / ful / pof
    /// prefixed ones don't decode to 65 bytes).
    public static func isLegacyMessageSignature(_ signature: String) -> Bool {
        let text = signature.components(separatedBy: .whitespacesAndNewlines).joined()
        guard let data = Data(base64Encoded: text), data.count == 65, let header = data.first else { return false }
        return (27...42).contains(header)
    }

    // MARK: - BILCoinMultipleAddressGeneratorProtocol

    /// Standard BIP39 wallets only (seedTypePath "0"); Electrum / custom-path wallets have no Taproot.
    public func getXPublicKeys(seed: String, seedTypePath: String, success: @escaping (_ object: (mainPubkey: String, changePubkey: String, rootPubkey: String)) -> Void, failure: @escaping (_ error: Error) -> Void) {
        guard seedTypePath == "0" else {
            DispatchQueue.main.async { failure(JSError.resultError) }
            return
        }
        getTaprootXpubs(seedHex: seed, success: { receive, change in
            success((receive, change, ""))
        }, failure: failure)
    }

    public func getAddresses(xpub: String, fromIndex: Int64, toIndex: Int64, success: @escaping (_ object: Any) -> Void, failure: @escaping (_ error: Error) -> Void) {
        getTaprootAddresses(xpub: xpub, from: fromIndex, to: toIndex, success: { success($0) }, failure: failure)
    }

    /// Not used for Taproot: a private-key wallet's bc1p address comes from getTaprootAddress(publicKey:).
    public func getPublicKeyAndAddress(from privateKey: String, success: @escaping (_ publicKey: String, _ address: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        DispatchQueue.main.async { failure(JSError.resultError) }
    }

    public func getAddress(from publicKey: String, success: @escaping (_ object: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        getTaprootAddress(publicKey: publicKey, success: success, failure: failure)
    }
}
