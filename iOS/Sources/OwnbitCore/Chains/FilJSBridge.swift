//  FilJSBridge.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  FIL (f1 secp256k1 addresses, m/44'/461'/0'/0/0): address, private-key export, signing a value transfer (gas values are
//  fixed in the bundle). Bundle: filjs-lib-app.js (Zondax filecoin-signing-tools) in a hidden web view (fil_index.html):
//  the bundle needs `window.crypto.getRandomValues`.

import Foundation

public final class FilJSBridge: JSBridge, JSBridgeValidAddressProtocol {

    public static let shared = FilJSBridge()

    override var webPage: Resource? {
        return Resource(name: "fil_index", ext: "html", directory: "filejs-lib-bridge")
    }

    public func validateAddress(address: String, success: @escaping () -> Void, failure: @escaping (_ error: String) -> Void) {
        callWebValidate("bridge.isAddress('\(address.jsEscaped)')", success: success, failure: failure)
    }

    public func getPublicKeyAndAddress(privKey: String, success: @escaping (_ publicKey: String, _ address: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callWebStrings("bridge.getPubAddrFromPrivKey('\(privKey.jsEscaped)')", count: 2, success: { success($0[0], $0[1]) }, failure: failure)
    }

    /// m/44'/461'/0'/0/0 → (public key hex, f1… address).
    public func getPublicKeyAndAddress(seedHex: String, success: @escaping (_ publicKey: String, _ address: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callWebStrings("bridge.getPubAddrFromSeed('\(seedHex.jsEscaped)')", count: 2, success: { success($0[0], $0[1]) }, failure: failure)
    }

    /// amount: attoFIL as a string. success gets the signed message JSON.
    public func buildTransaction(seedHex: String, to: String, amount: String, nonce: Int64, success: @escaping (_ hexTx: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callWebNonEmptyString("bridge.sendTxBySeed('\(seedHex.jsEscaped)', '\(to.jsEscaped)', '\(amount.jsEscaped)', \(nonce))", success: success, failure: failure)
    }

    public func buildTransaction(privateKey: String, to: String, amount: String, nonce: Int64, success: @escaping (_ hexTx: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callWebNonEmptyString("bridge.sendTxByPrivKey('\(privateKey.jsEscaped)', '\(to.jsEscaped)', '\(amount.jsEscaped)', \(nonce))", success: success, failure: failure)
    }

    /// Private-key export (hex).
    public func getPrivKeyFromSeedHex(seedHex: String, success: @escaping (_ multiSigAddress: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callWebNonEmptyString("bridge.getPrivKeyFromSeed('\(seedHex.jsEscaped)')", success: success, failure: failure)
    }
}
