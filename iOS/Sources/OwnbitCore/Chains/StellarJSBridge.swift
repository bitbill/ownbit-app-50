//  StellarJSBridge.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  XLM: addresses (SEP-0005; `isNew` selects the path the wallet uses, see the bundle), create-account / set-inflation /
//  payment signing. XLM tokens and multisig are in BILXrpXlmJSBridge.swift.
//  Bundle: stellarjs-lib-app.min.js in a JSContext with `window` defined as the global object. The app evaluated it in a
//  UIWebView's JSContext; stellar-base needs `window` to pick tweetnacl (otherwise it tries the stubbed sodium-native and
//  fails). The kept functions are deterministic (no randomness, no DOM), so the alias is equivalent.

import Foundation
import JavaScriptCore

/// Never change the order: shared with Android for offline signing.
public enum XLMTXType: Int {
    case createAccount
    case setInflation
    case payment
}

public final class StellarJSBridge: JSBridge, JSBridgeValidAddressProtocol {

    public static let shared = StellarJSBridge()

    override var contextScript: Resource? {
        return Resource(name: "stellarjs-lib-app.min", ext: "js", directory: "stellarjs-lib-bridge")
    }

    override var contextNeedsWindow: Bool {
        return true
    }

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

    public func getAddress(from publicKey: String, success: @escaping (String) -> Void, failure: @escaping (Error) -> Void) {
        callJSNonEmptyString("bridge.getXlmAddrFromPubKey('\(publicKey.jsEscaped)')", success: success, failure: failure)
    }

    public func getPublicKeyAndAddress(from privateKey: String, success: @escaping (_ publicKey: String, _ address: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callJSStrings("bridge.getPubAddrFromPrivkey('\(privateKey.jsEscaped)')", count: 2, success: { success($0[0], $0[1]) }, failure: failure)
    }

    /// → (public key hex, G… address). Wallets use isNew = true.
    public func getPublicKeyAndAddress(seed: String, isNew: Bool, success: @escaping (_ publicKey: String, _ address: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callJSStrings("bridge.getPubAddrFromSeedHex('\(seed.jsEscaped)', \(isNew))", count: 2, success: { success($0[0], $0[1]) }, failure: failure)
    }

    public func seedHexToPrivateHex(seedHex: String, isNew: Bool, success: @escaping (_ object: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callJSNonEmptyString("bridge.getPrivkeyFromSeedHex('\(seedHex.jsEscaped)', \(isNew))", success: success, failure: failure)
    }

    /// data: the operation JSON (see the bundle). success: (txId, signed envelope).
    public func buildTransaction(type: XLMTXType, privateKey: String, data: String, memo: String, success: @escaping (_ txID: String, _ txHex: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        let function: String
        switch type {
        case .createAccount: function = "buildCreateAccountTxWithPrivKey"
        case .setInflation:  function = "buildSetInflationTxWithPrivKey"
        case .payment:       function = "buildPaymentTxWithPrivKey"
        }
        let method = "bridge.\(function)('\(privateKey.jsEscaped)', '\(data.jsEscaped)', '\(memo.jsEscaped)')"
        callJSStrings(method, count: 2, success: { success($0[0], $0[1]) }, failure: failure)
    }

    /// xlmaddr: the wallet's G… address; the bundle signs with the SEP-0005 key, or with the older-path key when that is
    /// the one matching xlmaddr.
    public func buildTransaction(type: XLMTXType, seed: String, data: String, memo: String, xlmaddr: String, success: @escaping (_ txID: String, _ txHex: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        let function: String
        switch type {
        case .createAccount: function = "buildCreateAccountTxWithSeedHex"
        case .setInflation:  function = "buildSetInflationTxWithSeedHex"
        case .payment:       function = "buildPaymentTxWithSeedHex"
        }
        let method = "bridge.\(function)('\(seed.jsEscaped)', '\(data.jsEscaped)', '\(memo.jsEscaped)', '\(xlmaddr.jsEscaped)')"
        callJSStrings(method, count: 2, success: { success($0[0], $0[1]) }, failure: failure)
    }
}
