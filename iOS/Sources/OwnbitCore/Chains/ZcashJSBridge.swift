//  ZcashJSBridge.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  ZEC (transparent t1 addresses; TEX addresses are converted to t1 for validation): xpubs, addresses, signing v4 / v5
//  (ZIP 225 / 244, chosen by `zecTxVersion` in the sign data), multisig cosigner signatures, WIF export.
//  Bundle: zcashjs-lib-app-0251.js in a hidden web view (zec_index.html): signing needs `window.crypto.getRandomValues`.

import Foundation

public final class ZcashJSBridge: JSBridge, JSBridgeValidAddressProtocol, BILCoinMultipleAddressGeneratorProtocol {

    public static let shared = ZcashJSBridge()

    /// v4 signing only: the consensus branch ID handed to the bundle as `consensusBranchIdOverride` (contract 0.12 / 1.8 in
    /// the app). The app sets it from its own rules (NU7 activation height, or the branch ID its server configuration
    /// gives); nil = the bundle's default. It goes into this JS call only. Not added to v5 sign data (`zecTxVersion` = 5),
    /// which carries its own `zecBranchId`.
    public static var v4BranchIdOverride: UInt32?

    override var webPage: Resource? {
        return Resource(name: "zec_index", ext: "html", directory: "zcashjs-lib-bridge")
    }

    /// seedTypePath is ignored (the bundle uses its fixed paths).
    public func getXPublicKeys(seed: String, seedTypePath: String = "", success: @escaping (_ object: (mainPubkey: String, changePubkey: String, rootPubkey: String)) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callWebStrings("bridge.getXpubkeys('\(seed.jsEscaped)')", count: 3, success: { success(($0[0], $0[1], $0[2])) }, failure: failure)
    }

    /// TEX (tex1…) addresses are validated as the t1 address of the same key hash.
    public func validateAddress(address: String, success: @escaping () -> Void, failure: @escaping (_ error: String) -> Void) {
        let rawAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        var validateAddress = rawAddress
        if rawAddress.lowercased().hasPrefix("tex1t") {
            let t1Address = ZcashTexAddressConverter.texToT1(rawAddress)
            guard !t1Address.isEmpty else {
                DispatchQueue.main.async { failure(JSBridge.invalidAddressMessage) }
                return
            }
            validateAddress = t1Address
        }
        callWebValidate("bridge.isAddress('\(validateAddress.jsEscaped)')", success: success, failure: failure)
    }

    /// success gets [String].
    public func getAddresses(xpub: String, fromIndex: Int64 = 0, toIndex: Int64, success: @escaping (_ object: Any) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callWebStringArray("bridge.getZecContinuousAddrFromXpubkey('\(xpub.jsEscaped)', \(fromIndex), \(toIndex))", success: { success($0) }, failure: failure)
    }

    /// Adds `consensusBranchIdOverride` to v4 sign data when `v4BranchIdOverride` is set (unchanged otherwise).
    private func withV4BranchOverride(_ inputsOutputs: String) -> String {
        guard let override = ZcashJSBridge.v4BranchIdOverride,
              let data = inputsOutputs.data(using: .utf8),
              var dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return inputsOutputs
        }
        if (dict["zecTxVersion"] as? NSNumber)?.intValue == 5 || (dict["zecTxVersion"] as? String) == "5" {
            return inputsOutputs
        }
        dict["consensusBranchIdOverride"] = NSNumber(value: override)
        guard let out = try? JSONSerialization.data(withJSONObject: dict), let s = String(data: out, encoding: .utf8) else {
            return inputsOutputs
        }
        return s
    }

    public func buildTransaction(seedHex: String, inputsOutputs: String, success: @escaping (_ txHash: String, _ txHexString: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        let inputsOutputs = withV4BranchOverride(inputsOutputs)
        callWebStrings("bridge.buildZecTransaction('\(seedHex.jsEscaped)', '\(inputsOutputs.jsEscaped)')", count: 2, success: { success($0[0], $0[1]) }, failure: failure)
    }

    public func buildTransaction(privateKey: String, inputsOutputs: String, success: @escaping (_ txHash: String, _ txHexString: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        let inputsOutputs = withV4BranchOverride(inputsOutputs)
        callWebStrings("bridge.buildZecTxWithPrivateKey('\(privateKey.jsEscaped)', '\(inputsOutputs.jsEscaped)')", count: 2, success: { success($0[0], $0[1]) }, failure: failure)
    }

    public func getPublicKeyAndAddress(from privateKey: String, success: @escaping (_ publicKey: String, _ address: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callWebStrings("bridge.getPubkeyAndAddrFromPrivkey('\(privateKey.jsEscaped)')", count: 2, success: { success($0[0], $0[1]) }, failure: failure)
    }

    public func getAddress(from publicKey: String, success: @escaping (String) -> Void, failure: @escaping (Error) -> Void) {
        callWebNonEmptyString("bridge.getZecAddrFromPubKey('\(publicKey.jsEscaped)')", success: success, failure: failure)
    }

    /// Private-key export: WIF of receive / change address `index`.
    public func getWIFFromSeedHex(_ seedHex: String, index: Int, isChange: Bool, success: @escaping (_ multiSigAddress: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callWebNonEmptyString("bridge.getWIFFromSeedHex('\(seedHex.jsEscaped)', \(index), \(isChange))", success: success, failure: failure)
    }

    /// Multisig cosigner signatures; signOrder = this cosigner's position, redeemScript = the multisig script.
    public func getSignatureWithPrivateKey(priKey: String, inputsOutputs: String, signOrder: Int, redeemScript: String, success: @escaping (_ signatures: [String]) -> Void, failure: @escaping (_ error: Error) -> Void) {
        let inputsOutputs = withV4BranchOverride(inputsOutputs)
        let method = "bridge.getSignatureWithPrivateKey('\(priKey.jsEscaped)', '\(inputsOutputs.jsEscaped)', \(signOrder), '\(redeemScript.jsEscaped)')"
        callWebStringArray(method, success: success, failure: failure)
    }
}
