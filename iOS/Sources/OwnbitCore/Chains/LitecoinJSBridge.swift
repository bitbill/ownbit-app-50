//  LitecoinJSBridge.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  LTC: xpubs, addresses, signing, multisig cosigner signatures, WIF export.
//  Bundle: litecoinjs-lib-app.min.js in a JSContext.

import Foundation
import JavaScriptCore

public final class LitecoinJSBridge: JSBridge, JSBridgeValidAddressProtocol, BILCoinMultipleAddressGeneratorProtocol {

    public static let shared = LitecoinJSBridge()

    override var contextScript: Resource? {
        return Resource(name: "litecoinjs-lib-app.min", ext: "js", directory: "litecoinjs-lib-bridge")
    }

    /// seedTypePath is ignored (the bundle uses its fixed paths).
    public func getXPublicKeys(seed: String, seedTypePath: String = "", success: @escaping (_ object: (mainPubkey: String, changePubkey: String, rootPubkey: String)) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callJSStrings("bridge.getXpubkeysForAll('\(seed.jsEscaped)')", count: 3, success: { success(($0[0], $0[1], $0[2])) }, failure: failure)
    }

    public func validateAddress(address: String, success: @escaping () -> Void, failure: @escaping (_ error: String) -> Void) {
        callJSValidate("bridge.isAddress('\(address.jsEscaped)')", success: success, failure: failure)
    }

    /// success gets [String].
    public func getAddresses(xpub: String, fromIndex: Int64 = 0, toIndex: Int64, success: @escaping (_ object: Any) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callJSStringArray("bridge.getLtcContinuousAddrFromXpubkey('\(xpub.jsEscaped)', \(fromIndex), \(toIndex))", success: { success($0) }, failure: failure)
    }

    /// success gets the bundle's result as a String (see the bundle).
    public func buildTransaction(seedHex: String, inputsOutputs: String, success: @escaping (_ object: Any) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callString("bridge.buildLtcTransaction('\(seedHex.jsEscaped)', '\(inputsOutputs.jsEscaped)')", success: success, failure: failure)
    }

    public func buildTransaction(privateKey: String, inputsOutputs: String, success: @escaping (_ object: Any) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callString("bridge.buildLtcTxWithPrivateKey('\(privateKey.jsEscaped)', '\(inputsOutputs.jsEscaped)')", success: success, failure: failure)
    }

    public func getPublicKeyAndAddress(from privateKey: String, success: @escaping (_ publicKey: String, _ address: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callJSStrings("bridge.getPubkeyAndAddrFromPrivkey('\(privateKey.jsEscaped)')", count: 2, success: { success($0[0], $0[1]) }, failure: failure)
    }

    public func getSignatureWithPrivateKey(priKey: String, inputsOutputs: String, minRequired: Int, publicKeys: [String], success: @escaping (_ signatures: [String]) -> Void, failure: @escaping (_ error: Error) -> Void) {
        let method = "bridge.getSignatureWithPrivateKey('\(priKey.jsEscaped)', '\(inputsOutputs.jsEscaped)', \(minRequired), '\(JSBridge.jsonText(publicKeys).jsEscaped)')"
        callJSStringArray(method, success: success, failure: failure)
    }

    public func getAddress(from publicKey: String, success: @escaping (String) -> Void, failure: @escaping (Error) -> Void) {
        callJSNonEmptyString("bridge.getLtcAddrFromPubKey('\(publicKey.jsEscaped)')", success: success, failure: failure)
    }

    /// Private-key export: WIF of receive / change address `index`.
    public func getWIFFromSeedHex(_ seedHex: String, index: Int, isChange: Bool, success: @escaping (_ multiSigAddress: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callJSNonEmptyString("bridge.getPrivkeyFromSeedHex('\(seedHex.jsEscaped)', \(index), \(isChange))", success: success, failure: failure)
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
