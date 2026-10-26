//  AdaJSBridge.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  ADA (Cardano Shelley, AdaLite-based): address from the BIP39 entropy (BitcoinJSBridge.mnemonicToEntropy), signing a
//  transfer from given UTXOs. Keys come from the entropy, not the BIP39 seed, so a BIP39 passphrase does not apply:
//  see `MnemonicPassphrase.unsupportedCoinTypes`.
//  Bundle: shelley.bundle.js in a hidden web view (shelley_ada.html); the functions are page globals (no `bridge.`).
//  Results arrive on `window.webkit.messageHandlers.address` ("<base address>:<legacy address>"), `.transaction`
//  ("<signed tx body hex>:<txHash>") and `.error`.
//
//  Differences from the app (no UI in this package): the app called `success("")` right away and delivered the real
//  result to whichever view controller was registered; here `success` is called once with the real result.

import Foundation

public final class AdaJSBridge: JSBridge, JSBridgeValidAddressProtocol {

    public static let shared = AdaJSBridge()

    override var webPage: Resource? {
        return Resource(name: "shelley_ada", ext: "html", directory: "adajs-lib-bridge")
    }

    override var webMessageNames: [String] {
        return ["transaction", "address", "error"]
    }

    public func validateAddress(address: String, success: @escaping () -> Void, failure: @escaping (_ error: String) -> Void) {
        callWebValidate("isAdaAddress('\(address.jsEscaped)')", success: success, failure: failure)
    }

    /// success gets the bundle's address message as is: "<base address>:<legacy address>" (index 20 of the AdaLite
    /// discovery, what the app stored as the ADA address string).
    public func getAddressFromEntropy(entropy: String, success: @escaping (_ address: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callWebForMessage("getAdaAddress('\(entropy.jsEscaped)')", channels: ["address"], success: { _, body in
            success(body)
        }, failure: failure)
    }

    /// amount in lovelace; inputsOutputs: JSON with the "utxo" list; myAddress: change address (must not be empty).
    /// success gets "<signed tx body hex>:<txHash>" (the app's `transaction` message, split by the caller).
    public func buildTransaction(entropy: String, myAddress: String, toAddress: String, amount: Int64, inputsOutputs: String, success: @escaping (_ txHash: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        guard !myAddress.isEmpty else { // the bundle returns without any message
            DispatchQueue.main.async { failure(JSError.resultError) }
            return
        }
        let method = "sendTx('\(entropy.jsEscaped)', '\(myAddress.jsEscaped)', '\(toAddress.jsEscaped)', \(amount), '\(inputsOutputs.jsEscaped)')"
        callWebForMessage(method, channels: ["transaction"], success: { _, body in
            guard body.split(separator: ":").count == 2 else {
                failure(JSError.resultError)
                return
            }
            success(body)
        }, failure: failure)
    }
}
