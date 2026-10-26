//  TronJSBridge.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  TRX (+ TRC-10 / TRC-20, TRX multisig): addresses from a private key (the key itself comes from
//  EthereumJSBridge.seedHexToTrxPrivateKey, m/44'/195'/0'/0/0), hex ↔ base58 addresses, signing a transaction JSON, and a
//  multisig cosigner signature.
//  Bundle: trxjs-lib-app.js (TronWeb) in a hidden web view (trx_index.html). Signing is asynchronous and reported on
//  `window.webkit.messageHandlers.signed` (signed transaction JSON), `.multiSigned` (signature hex) and `.error`.
//
//  Every bundle function takes a full-node URL first: `TronJSBridge.provider` (host-settable; default the loopback
//  `JSBridge.offlineProviderPlaceholder`; the app passed its TRON node). TronWeb won't construct without one, but none of
//  the functions here contacts the node: `trx.sign`, `trx.multiSign` (no permission lookup) and the address helpers are
//  local, so they work offline with the default.
//
//  Not included, because they never touch a key: `getTrxTxJson` (bridge.preSendTx: builds an unsigned transaction on
//  the node) and `extendTxForWc` (TronWeb extendExpiration: the node recomputes the txID of an unsigned transaction).
//  The app enabled `allowUniversalAccessFromFileURLs` on this page only for those node requests; not here.
//  Not included (contract account, deprecated): `buildTrxTransactionForCa`.
//
//  Differences from the app (no UI in this package): the app called `success("")` right away and delivered the real
//  result to whichever view controller was registered; here `success` is called once with the real result.

import Foundation

public final class TronJSBridge: JSBridge, JSBridgeValidAddressProtocol {

    public static let shared = TronJSBridge()

    override var webPage: Resource? {
        return Resource(name: "trx_index", ext: "html", directory: "tronjs-lib-bridge")
    }

    override var webMessageNames: [String] {
        return ["signed", "multiSigned", "error"]
    }

    /// Full-node URL passed as `tronNode` to every bundle function (JSON-escaped). The bundle creates its TronWeb
    /// instance once, on the first call, with the URL given then (as in the app): set it before the first call. Never
    /// hard-code a server URL in this package.
    public static var provider: String = JSBridge.offlineProviderPlaceholder

    private static var node: String {
        return JSBridge.jsStringLiteral(provider)
    }

    private static func stripped0x(_ privateKey: String) -> String {
        if privateKey.hasPrefix("0x") {
            return String(privateKey.dropFirst(2))
        }
        return privateKey
    }

    public func validateAddress(address: String, success: @escaping () -> Void, failure: @escaping (_ error: String) -> Void) {
        callWebValidate("bridge.isAddress(\(Self.node), \(JSBridge.jsStringLiteral(address)))", success: success, failure: failure)
    }

    /// Private key (hex, optional 0x) → (hex address 41…, base58 address T…).
    public func getPublicKeyAndAddress(privateKey: String, success: @escaping (_ publicKey: String, _ address: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        let pk = Self.stripped0x(privateKey)
        callWebStrings("bridge.getAddress(\(Self.node), \(JSBridge.jsStringLiteral(pk)))", count: 2, success: { success($0[0], $0[1]) }, failure: failure)
    }

    /// hexAddr like 0x14808db8…e50782ad / 41… → (hex address, base58 address T…).
    public func getBase58AddressFromHex(hexAddr: String, success: @escaping (_ publicKey: String, _ address: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callWebStrings("bridge.getBase58AddrFromHex(\(Self.node), \(JSBridge.jsStringLiteral(hexAddr)))", count: 2, success: { success($0[0], $0[1]) }, failure: failure)
    }

    /// Signs a transaction JSON (TronWeb format, built elsewhere). The key must match the owner address in the
    /// transaction. success gets the signed transaction JSON (the app's `signed` channel).
    public func buildTrxTransaction(privateKey: String, txJson: String, success: @escaping (_ txHash: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        let pk = Self.stripped0x(privateKey)
        let method = "bridge.signTx(\(Self.node), \(JSBridge.jsStringLiteral(pk)), \(JSBridge.jsStringLiteral(txJson)))"
        callWebForMessage(method, channels: ["signed"], success: { _, body in success(body) }, failure: failure)
    }

    /// Multisig cosigner: signs the transaction JSON and returns only this key's signature (hex; the app's `multiSigned`
    /// channel). The permission ID must already be in the transaction (TronWeb is not asked to look it up).
    public func buildTrxSigForMultiSig(privateKey: String, txJson: String, success: @escaping (_ txHash: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        let pk = Self.stripped0x(privateKey)
        let method = "bridge.multiSignTx(\(Self.node), \(JSBridge.jsStringLiteral(pk)), \(JSBridge.jsStringLiteral(txJson)))"
        callWebForMessage(method, channels: ["multiSigned"], success: { _, body in success(body) }, failure: failure)
    }
}
