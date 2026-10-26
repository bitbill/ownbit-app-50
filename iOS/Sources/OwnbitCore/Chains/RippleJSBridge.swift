//  RippleJSBridge.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  XRP: addresses (m/44'/144'/0'/0/0; other indexes and XRP tokens / multisig in BILXrpXlmJSBridge.swift), Payment
//  signing. Bundle: ripplejs-lib-app.min.js in a JSContext.

import Foundation
import JavaScriptCore

public final class RippleJSBridge: JSBridge, JSBridgeValidAddressProtocol {

    public static let shared = RippleJSBridge()

    override var contextScript: Resource? {
        return Resource(name: "ripplejs-lib-app.min", ext: "js", directory: "ripplejs-lib-bridge")
    }

    /// BIP39 seed from this bundle's own bip39 (same result as BitcoinJSBridge.mnemonicToSeedHex).
    public func mnemonicToSeedHex(mnemonic: String, password: String = "", success: @escaping (_ object: Any) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callJS(method: "bridge.mnemonicToSeedHex('\(mnemonic.jsEscaped)', '\(password.jsEscaped)')", success: { result in
            guard let s = result.toString() else {
                failure(JSError.resultError)
                return
            }
            success(s)
        }, failure: failure)
    }

    public func validateAddress(address: String, success: @escaping () -> Void, failure: @escaping (_ error: String) -> Void) {
        callJSValidate("bridge.isAddress('\(address.jsEscaped)')", success: success, failure: failure)
    }

    public func getXPublicKeys(seed: String, success: @escaping (_ object: (mainPubkey: String, changePubkey: String)) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callJSStrings("bridge.getXpubkeys('\(seed.jsEscaped)')", count: 2, success: { success(($0[0], $0[1])) }, failure: failure)
    }

    public func getAddress(from publicKey: String, success: @escaping (String) -> Void, failure: @escaping (Error) -> Void) {
        callJSNonEmptyString("bridge.getXrpAddrFromPubKey('\(publicKey.jsEscaped)')", success: success, failure: failure)
    }

    public func getPublicKeyAndAddress(from privateKey: String, success: @escaping (_ publicKey: String, _ address: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callJSStrings("bridge.getPubAddrFromPrivkey('\(privateKey.jsEscaped)')", count: 2, success: { success($0[0], $0[1]) }, failure: failure)
    }

    /// m/44'/144'/0'/0/0 → (public key hex, r… address).
    public func getPublicKeyAndAddress(seed: String, success: @escaping (_ publicKey: String, _ address: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callJSStrings("bridge.getPubAddrFromSeedHex('\(seed.jsEscaped)')", count: 2, success: { success($0[0], $0[1]) }, failure: failure)
    }

    public func seedHexToPrivateHex(seedHex: String, success: @escaping (_ object: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callJSNonEmptyString("bridge.getPrivkeyFromSeedHex('\(seedHex.jsEscaped)')", success: success, failure: failure)
    }

    /// data: the Payment JSON (see the bundle). success: (txId, signed blob).
    public func buildTransaction(privateKey: String, data: String, success: @escaping (_ txID: String, _ txHex: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callJSStrings("bridge.buildXrpPaymentTxWithPrivKey('\(privateKey.jsEscaped)', '\(data.jsEscaped)')", count: 2, success: { success($0[0], $0[1]) }, failure: failure)
    }

    public func buildTransaction(seed: String, data: String, success: @escaping (_ txID: String, _ txHex: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callJSStrings("bridge.buildXrpPaymentTxWithSeedHex('\(seed.jsEscaped)', '\(data.jsEscaped)')", count: 2, success: { success($0[0], $0[1]) }, failure: failure)
    }
}
