//  BitcoinCashJSBridge.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  BCH: signing (single-sig and multisig), CashAddr conversion, address validation.
//  Bundle: bitcoincashjs-lib-app.min.js in a JSContext.

import Foundation
import JavaScriptCore

public final class BitcoinCashJSBridge: JSBridge, JSBridgeValidAddressProtocol {

    public static let shared = BitcoinCashJSBridge()

    override var contextScript: Resource? {
        return Resource(name: "bitcoincashjs-lib-app.min", ext: "js", directory: "bitcoincashjs-lib-bridge")
    }

    /// success gets the bundle's result as a String (the signed transaction, see the bundle).
    public func buildTransaction(seedHex: String, seedTypePath: String, inputsOutputs: String, success: @escaping (_ object: Any) -> Void, failure: @escaping (_ error: Error) -> Void) {
        let method = "bridge.buildBchTransaction('\(seedHex.jsEscaped)', \"\(seedTypePath.jsEscaped)\", '\(inputsOutputs.jsEscaped)')"
        callString(method, success: success, failure: failure)
    }

    public func buildTransaction(privateKey: String, inputsOutputs: String, success: @escaping (_ object: Any) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callString("bridge.buildBchTxWithPrivateKey('\(privateKey.jsEscaped)', '\(inputsOutputs.jsEscaped)')", success: success, failure: failure)
    }

    /// Legacy address → CashAddr.
    public func translateToNewAddress(address: String, success: @escaping (_ object: Any) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callString("bridge.toCashaddr('\(address.jsEscaped)')", success: success, failure: failure)
    }

    public func validateAddress(address: String, success: @escaping () -> Void, failure: @escaping (_ error: String) -> Void) {
        callJSValidate("bridge.isAddress('\(address.jsEscaped)')", success: success, failure: failure)
    }

    /// Multisig cosigner signatures with the seed's key; publicKeys are all cosigners' keys (JSON array in JS).
    public func getSignatureWithHex(hex: String, inputsOutputs: String, minRequired: Int, publicKeys: [String], success: @escaping (_ signatures: [String]) -> Void, failure: @escaping (_ error: Error) -> Void) {
        let method = "bridge.getSignatureWithSeedHex('\(hex.jsEscaped)', '\(inputsOutputs.jsEscaped)', \(minRequired), '\(JSBridge.jsonText(publicKeys).jsEscaped)')"
        callJSStringArray(method, success: success, failure: failure)
    }

    public func getSignatureWithPrivateKey(priKey: String, inputsOutputs: String, minRequired: Int, publicKeys: [String], success: @escaping (_ signatures: [String]) -> Void, failure: @escaping (_ error: Error) -> Void) {
        let method = "bridge.getSignatureWithPrivateKey('\(priKey.jsEscaped)', '\(inputsOutputs.jsEscaped)', \(minRequired), '\(JSBridge.jsonText(publicKeys).jsEscaped)')"
        callJSStringArray(method, success: success, failure: failure)
    }

    private func callString(_ method: String, success: @escaping (_ object: Any) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callJS(method: method, success: { result in
            guard let s = result.toString() else {
                failure(JSError.resultError)
                return
            }
            success(s)
        }, failure: failure)
    }
}
