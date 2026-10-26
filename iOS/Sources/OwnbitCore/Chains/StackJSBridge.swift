//  StackJSBridge.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  STX (Stacks): address from a private key (the app uses the ETH key of index 0,
//  EthereumJSBridge.seedHexToPrivateHex(indexNo: 0)), signing a STX transfer (nonce and fee given, so the builder never
//  asks a node).
//  Bundle: stxjs-new.js in a hidden web view (stx_index.html). sendToken reports on
//  `window.webkit.messageHandlers.transaction` (serialized transaction hex) and `.error`. The app also granted the page
//  universal file-URL access (for node requests); not here.
//
//  Differences from the app (no UI in this package): the app called `success("")` right away and delivered the real
//  result to whichever view controller was registered; here `success` is called once with the real result.

import Foundation

public final class StackJSBridge: JSBridge, JSBridgeValidAddressProtocol {

    public static let shared = StackJSBridge()

    override var webPage: Resource? {
        return Resource(name: "stx_index", ext: "html", directory: "stackjs-lib-bridge")
    }

    override var webMessageNames: [String] {
        return ["transaction", "error"]
    }

    public func validateAddress(address: String, success: @escaping () -> Void, failure: @escaping (_ error: String) -> Void) {
        callWebValidate("bridge.isAddress('\(address.jsEscaped)')", success: success, failure: failure)
    }

    /// privateKey: 64 (or 66 with the compression flag) hex characters → (address, address), as in the app.
    public func getPublicKeyAndAddress(privateKey: String, success: @escaping (_ publicKey: String, _ address: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callWebStrings("bridge.getAddressFromPrivateHex('\(privateKey.jsEscaped)')", count: 2, success: { success($0[0], $0[1]) }, failure: failure)
    }

    /// amount: micro-STX as a string, e.g. "111111112"; fee fixed at 5000 in the bundle. success gets the serialized
    /// transaction hex.
    public func buildTransaction(privateKey: String, toAddress: String, amount: String, memo: String, nonce: Int64, success: @escaping (_ txHash: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        let method = "bridge.sendToken('\(privateKey.jsEscaped)', '\(toAddress.jsEscaped)', '\(amount.jsEscaped)', '\(memo.jsEscaped)', \(nonce))"
        callWebForMessage(method, channels: ["transaction"], success: { _, body in success(body) }, failure: failure)
    }
}
