//  EthereumClassicJSBridge.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  ETC transactions (same keys / addresses as ETH, same bundle). amountWei goes to JS as `NSDecimalNumber.stringValue`,
//  exactly as in the app (callers pass integers).

import Foundation

extension EthereumJSBridge {

    public func buildETCTransaction(amountWei: NSDecimalNumber, addressTo: String, nonce: Int64, seed: String, indexNo: Int, gasPrice: Int64, gasLimit: Int64, customData: String, success: @escaping (String, String) -> Void, failure: @escaping (Error) -> Void) {
        let method = "bridge.buildEtcTxBySeedHex('\(seed.jsEscaped)', \(indexNo), '\(amountWei.stringValue)', '\(addressTo.jsEscaped)', '\(nonce)', '\(gasPrice)', '\(gasLimit)', '\(customData.jsEscaped)')"
        callJSStrings(method, count: 2, success: { success($0[0], $0[1]) }, failure: failure)
    }

    public func buildETCTransaction(amountWei: NSDecimalNumber, addressTo: String, nonce: Int64, privateKey: String, gasPrice: Int64, gasLimit: Int64, customData: String, success: @escaping (String, String) -> Void, failure: @escaping (Error) -> Void) {
        let method = "bridge.buildEtcTransaction('\(privateKey.jsEscaped)', '\(amountWei.stringValue)', '\(addressTo.jsEscaped)', '\(nonce)', '\(gasPrice)', '\(gasLimit)', '\(customData.jsEscaped)')"
        callJSStrings(method, count: 2, success: { success($0[0], $0[1]) }, failure: failure)
    }
}
