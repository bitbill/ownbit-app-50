//  DigibyteJSBridge.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  DGB: xpubs, addresses, signing, multisig cosigner signatures, Digi-ID message signing, WIF export.
//  Bundle: digibytejs-lib-app.min.js in a JSContext.

import Foundation
import JavaScriptCore

public final class DigibyteJSBridge: JSBridge, JSBridgeValidAddressProtocol, BILCoinMultipleAddressGeneratorProtocol {

    public static let shared = DigibyteJSBridge()

    override var contextScript: Resource? {
        return Resource(name: "digibytejs-lib-app.min", ext: "js", directory: "digibytejs-lib-bridge")
    }

    /// seedTypePath is ignored (the bundle uses its fixed paths).
    public func getXPublicKeys(seed: String, seedTypePath: String = "", success: @escaping (_ object: (mainPubkey: String, changePubkey: String, rootPubkey: String)) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callJSStrings("bridge.getXpubkeys('\(seed.jsEscaped)')", count: 3, success: { success(($0[0], $0[1], $0[2])) }, failure: failure)
    }

    public func validateAddress(address: String, success: @escaping () -> Void, failure: @escaping (_ error: String) -> Void) {
        callJSValidate("bridge.isAddress('\(address.jsEscaped)')", success: success, failure: failure)
    }

    /// Digi-ID: signs `uri` with the seed's Digi-ID key → (address, signature, callbackUrl). Posting the result to the
    /// callback is the host app's business (not part of this package).
    public func signMessageForDigiId(seedHex: String, uri: String, success: @escaping (_ address: String, _ signature: String, _ callbackUrl: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callJSStrings("bridge.signMessage('\(seedHex.jsEscaped)', '\(uri.jsEscaped)')", count: 3, success: { success($0[0], $0[1], $0[2]) }, failure: failure)
    }

    /// success gets [String].
    public func getAddresses(xpub: String, fromIndex: Int64 = 0, toIndex: Int64, success: @escaping (_ object: Any) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callJSStringArray("bridge.getDgbContinuousAddrFromXpubkey('\(xpub.jsEscaped)', \(fromIndex), \(toIndex))", success: { success($0) }, failure: failure)
    }

    public func buildTransaction(seedHex: String, inputsOutputs: String, success: @escaping (_ txHash: String, _ txHexString: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callJSStrings("bridge.buildDgbTransaction('\(seedHex.jsEscaped)', '\(inputsOutputs.jsEscaped)')", count: 2, success: { success($0[0], $0[1]) }, failure: failure)
    }

    public func buildTransaction(privateKey: String, inputsOutputs: String, success: @escaping (_ txHash: String, _ txHexString: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callJSStrings("bridge.buildDgbTxWithPrivateKey('\(privateKey.jsEscaped)', '\(inputsOutputs.jsEscaped)')", count: 2, success: { success($0[0], $0[1]) }, failure: failure)
    }

    public func getPublicKeyAndAddress(from privateKey: String, success: @escaping (_ publicKey: String, _ address: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callJSStrings("bridge.getPubkeyAndAddrFromPrivkey('\(privateKey.jsEscaped)')", count: 2, success: { success($0[0], $0[1]) }, failure: failure)
    }

    /// Multisig cosigner signatures with the seed's key; publicKeys are all cosigners' keys (JSON array in JS).
    public func getSignatureWithSeedHex(seedHex: String, inputsOutputs: String, minRequired: Int, publicKeys: [String], success: @escaping (_ signatures: [String]) -> Void, failure: @escaping (_ error: Error) -> Void) {
        let method = "bridge.getSignatureWithSeedHex('\(seedHex.jsEscaped)', '\(inputsOutputs.jsEscaped)', \(minRequired), '\(JSBridge.jsonText(publicKeys).jsEscaped)')"
        callJSStringArray(method, success: success, failure: failure)
    }

    public func getSignatureWithPrivateKey(priKey: String, inputsOutputs: String, minRequired: Int, publicKeys: [String], success: @escaping (_ signatures: [String]) -> Void, failure: @escaping (_ error: Error) -> Void) {
        let method = "bridge.getSignatureWithPrivateKey('\(priKey.jsEscaped)', '\(inputsOutputs.jsEscaped)', \(minRequired), '\(JSBridge.jsonText(publicKeys).jsEscaped)')"
        callJSStringArray(method, success: success, failure: failure)
    }

    public func getAddress(from publicKey: String, success: @escaping (String) -> Void, failure: @escaping (Error) -> Void) {
        callJSNonEmptyString("bridge.getDgbAddrFromPubKey('\(publicKey.jsEscaped)')", success: success, failure: failure)
    }

    /// Private-key export: WIF of receive / change address `index`.
    public func getWIFFromSeedHex(_ seedHex: String, index: Int, isChange: Bool, success: @escaping (_ multiSigAddress: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callJSNonEmptyString("bridge.getPrivkeyFromSeedHex('\(seedHex.jsEscaped)', \(index), \(isChange))", success: success, failure: failure)
    }
}
