//  TonJSBridge.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  TON (shown as GRAM in the app) + jettons: wallet v4R2 address from the mnemonic, signing TON and jetton transfers.
//  Keys come straight from the mnemonic (TON's own derivation, not the BIP39 seed), so a BIP39 passphrase does not apply:
//  see `MnemonicPassphrase.unsupportedCoinTypes`.
//  Bundle: tonjs-new.js in a hidden web view (ton_index.html). The bundle's send path is patched to return the signed
//  BOC instead of broadcasting it; results arrive on `window.webkit.messageHandlers.address`
//  ("<non-bounceable>|<raw>|<public key hex>"), `.transaction` ("<txHash>:<BOC base64>") and `.error`.
//
//  Differences from the app (no UI in this package): the app called `success("")` right away and delivered the real
//  result to whichever view controller was registered; here `success` is called once with the real result.

import Foundation

public final class TonJSBridge: JSBridge, JSBridgeValidAddressProtocol {

    public static let shared = TonJSBridge()

    override var webPage: Resource? {
        return Resource(name: "ton_index", ext: "html", directory: "tonjs-lib-bridge")
    }

    override var webMessageNames: [String] {
        return ["transaction", "address", "error"]
    }

    public func validateAddress(address: String, success: @escaping () -> Void, failure: @escaping (_ error: String) -> Void) {
        callWebValidate("bridge.isAddress('\(address.jsEscaped)')", success: success, failure: failure)
    }

    /// success gets the bundle's address message as is: "<non-bounceable address>|<raw address>|<public key hex>"
    /// (what the app stored as the TON address string).
    public func getAddressFromMnemonic(mnemonic: String, success: @escaping (_ address: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callWebForMessage("bridge.mnemonicToAddress('\(mnemonic.jsEscaped)')", channels: ["address"], success: { _, body in
            success(body)
        }, failure: failure)
    }

    /// TON transfer. amount in TON (e.g. "0.04"); nonce = wallet seqno; expireAt: unix seconds (0 = now + 60 s).
    /// success gets "<txHash>:<BOC base64>" (the app's `transaction` message, split by the caller).
    public func buildTonTransaction(mnemonic: String, toAddress: String, amount: String, nonce: Int64, memo: String, expireAt: Int64 = 0, success: @escaping (_ txHash: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        let method = "bridge.sendTonTx('\(mnemonic.jsEscaped)', '\(toAddress.jsEscaped)', '\(amount.jsEscaped)', \(nonce), '\(memo.jsEscaped)', \(expireAt))"
        callTransaction(method, success: success, failure: failure)
    }

    /// Jetton transfer. amount in token units (e.g. "0.15"), converted to base units with `jettonDecimals` and rounded
    /// down (the bundle needs an integer). senderJettonAddress: the sender's jetton wallet; receiverState: 0 / 1 / 2 picks
    /// the forward TON amount (see the bundle). success gets "<txHash>:<BOC base64>".
    public func buildTonTransaction(mnemonic: String, senderJettonAddress: String, toAddress: String, jettonToken: String, jettonDecimals: Int16, receiverState: Int16, amount: String, nonce: Int64, memo: String, expireAt: Int64 = 0, success: @escaping (_ txHash: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        let large = NSDecimalNumber(string: amount)
        guard large != .notANumber else { // NaN * 10^d raises NSDecimalNumberOverflowException
            DispatchQueue.main.async { failure(JSError.resultError) }
            return
        }
        let amountBig = TonJSBridge.basicUnits(large, decimals: jettonDecimals)
        let method = "bridge.sendTokenTx('\(mnemonic.jsEscaped)', '\(senderJettonAddress.jsEscaped)', '\(toAddress.jsEscaped)', '\(jettonToken.jsEscaped)', \(receiverState), '\(amountBig.stringValue)', \(nonce), '\(memo.jsEscaped)', \(expireAt))"
        callTransaction(method, success: success, failure: failure)
    }

    /// amount × 10^decimals rounded down to an integer (the app's CoinFormatLargeToBasicUnitDecimal + .down, scale 0).
    static func basicUnits(_ large: NSDecimalNumber, decimals: Int16) -> NSDecimalNumber {
        let noRaise = NSDecimalNumberHandler(roundingMode: .down, scale: 0, raiseOnExactness: false, raiseOnOverflow: false, raiseOnUnderflow: false, raiseOnDivideByZero: false)
        return large.multiplying(byPowerOf10: decimals).rounding(accordingToBehavior: noRaise)
    }

    private func callTransaction(_ method: String, success: @escaping (_ txHash: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callWebForMessage(method, channels: ["transaction"], success: { _, body in
            guard body.split(separator: ":").count == 2 else {
                failure(JSError.resultError)
                return
            }
            success(body)
        }, failure: failure)
    }
}
