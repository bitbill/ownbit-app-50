//  BILXrpXlmJSBridge.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  XRP / XLM tokens and multisig: the newer functions of the XRP and XLM bundles (APP_CONTRACT 0.12 in the app; JS at the
//  end of ripplejs-lib-bridge/index.js and stellarjs-lib-bridge/index.js).
//  - Every argument is a JSON string literal (the older wrappers used '…' concatenation).
//  - The JS throws on any error; the bridge then gets `undefined` → failure. Results must be non-empty strings.
//  - Seeds and private keys only go into the JS engine; nothing is logged.

import Foundation
import JavaScriptCore

/// JSON argument helpers (the app's `BILJSArg`).
enum BILJSArg {
    /// Swift string → JS string literal (JSON escaping).
    static func str(_ s: String) -> String {
        return JSBridge.jsStringLiteral(s)
    }

    /// Dictionary → JSON text (sorted keys) → JS string literal (JS calls JSON.parse).
    static func json(_ dict: [String: Any]) -> String? {
        return JSBridge.jsJSONStringLiteral(dict)
    }

    /// The first `count` elements, all non-empty strings.
    static func strings(_ value: JSValue, count: Int) -> [String]? {
        guard let arr = value.toArray(), arr.count >= count else { return nil }
        let out = arr.prefix(count).compactMap { $0 as? String }
        return out.count == count && !out.contains(where: { $0.isEmpty }) ? out : nil
    }
}

// MARK: - XRP

extension RippleJSBridge {

    private func callPair(_ method: String, success: @escaping (_ first: String, _ second: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callJS(method: method, success: { result in
            guard let r = BILJSArg.strings(result, count: 2) else {
                failure(JSError.resultError)
                return
            }
            success(r[0], r[1])
        }, failure: failure)
    }

    private static func jsonFailure(_ failure: @escaping (_ error: Error) -> Void) {
        DispatchQueue.main.async { failure(JSError.resultError) }
    }

    /// Single-sig token Payment (contract 3.16.2). data keys: account / destination / destinationTag? / currency /
    /// issuer / value / sendMax? / fee / sequence. Pass privateKey for a private-key wallet, else seed. → (txId, blob).
    public func buildTokenPayment(seed: String? = nil, privateKey: String? = nil, data: [String: Any], success: @escaping (_ txID: String, _ txHex: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        guard let d = BILJSArg.json(data) else { RippleJSBridge.jsonFailure(failure); return }
        if let pk = privateKey {
            callPair("bridge.buildXrpTokenPaymentTxWithPrivKey(\(BILJSArg.str(pk)), \(d))", success: success, failure: failure)
        } else {
            callPair("bridge.buildXrpTokenPaymentTxWithSeedHex(\(BILJSArg.str(seed ?? "")), \(d))", success: success, failure: failure)
        }
    }

    /// Single-sig TrustSet (contract 3.16.1). data keys: account / currency / issuer / limit / fee / sequence.
    public func buildTrustSet(seed: String? = nil, privateKey: String? = nil, data: [String: Any], success: @escaping (_ txID: String, _ txHex: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        guard let d = BILJSArg.json(data) else { RippleJSBridge.jsonFailure(failure); return }
        if let pk = privateKey {
            callPair("bridge.buildXrpTrustSetTxWithPrivKey(\(BILJSArg.str(pk)), \(d))", success: success, failure: failure)
        } else {
            callPair("bridge.buildXrpTrustSetTxWithSeedHex(\(BILJSArg.str(seed ?? "")), \(d))", success: success, failure: failure)
        }
    }

    /// m/44'/144'/0'/0/index → (public key hex uppercase, r… address) (contract 4.1).
    public func pubAddr(seed: String, index: Int, success: @escaping (_ publicKey: String, _ address: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callPair("bridge.getPubAddrFromSeedHexIndex(\(BILJSArg.str(seed)), \(index))", success: success, failure: failure)
    }

    /// Signs a given tx_json as is with key `index` (multisig account activation, contract 4.5). → (txId, blob).
    public func signTxJson(seed: String, index: Int, txJson: String, success: @escaping (_ txID: String, _ blob: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callPair("bridge.signXrpTxJsonWithSeedHexIndex(\(BILJSArg.str(seed)), \(index), \(BILJSArg.str(txJson)))", success: success, failure: failure)
    }

    /// Multisig cosigner signature (contract 4.11.2) → (signer r… address, signingPubKey, txnSignature).
    public func multiSign(seed: String, jsonStr: String, success: @escaping (_ signer: String, _ signingPubKey: String, _ signature: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callJS(method: "bridge.multiSignXrpTxJsonWithSeedHex(\(BILJSArg.str(seed)), \(BILJSArg.str(jsonStr)))", success: { result in
            guard let r = BILJSArg.strings(result, count: 3) else {
                failure(JSError.resultError)
                return
            }
            success(r[0], r[1], r[2])
        }, failure: failure)
    }
}

// MARK: - XLM

extension StellarJSBridge {

    private func callPair(_ method: String, success: @escaping (_ first: String, _ second: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callJS(method: method, success: { result in
            guard let r = BILJSArg.strings(result, count: 2) else {
                failure(JSError.resultError)
                return
            }
            success(r[0], r[1])
        }, failure: failure)
    }

    private static func jsonFailure(_ failure: @escaping (_ error: Error) -> Void) {
        DispatchQueue.main.async { failure(JSError.resultError) }
    }

    /// Single-sig token payment (contract 3.16.4). data keys: accountId / sequence (string) / destination / amount
    /// (≤ 7 decimals) / assetCode / assetIssuer / maxTime?. → (txId, envelope).
    public func buildTokenPayment(seed: String? = nil, privateKey: String? = nil, data: [String: Any], memo: String, xlmaddr: String, success: @escaping (_ txID: String, _ txHex: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        guard let d = BILJSArg.json(data) else { StellarJSBridge.jsonFailure(failure); return }
        if let pk = privateKey {
            callPair("bridge.buildTokenPaymentTxWithPrivKey(\(BILJSArg.str(pk)), \(d), \(BILJSArg.str(memo)))", success: success, failure: failure)
        } else {
            callPair("bridge.buildTokenPaymentTxWithSeedHex(\(BILJSArg.str(seed ?? "")), \(d), \(BILJSArg.str(memo)), \(BILJSArg.str(xlmaddr)))", success: success, failure: failure)
        }
    }

    /// Single-sig change_trust (contract 3.16.3). data keys: accountId / sequence / assetCode / assetIssuer / limit
    /// ("922337203685.4775807" or "0").
    public func buildChangeTrust(seed: String? = nil, privateKey: String? = nil, data: [String: Any], xlmaddr: String, success: @escaping (_ txID: String, _ txHex: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        guard let d = BILJSArg.json(data) else { StellarJSBridge.jsonFailure(failure); return }
        if let pk = privateKey {
            callPair("bridge.buildChangeTrustTxWithPrivKey(\(BILJSArg.str(pk)), \(d))", success: success, failure: failure)
        } else {
            callPair("bridge.buildChangeTrustTxWithSeedHex(\(BILJSArg.str(seed ?? "")), \(d), \(BILJSArg.str(xlmaddr)))", success: success, failure: failure)
        }
    }

    /// SEP-0005 m/44'/148'/index' → (public key hex, G… address); index 0 is the multisig signer key (contract 5.1).
    public func pubAddr(seed: String, index: Int, success: @escaping (_ publicKey: String, _ address: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callPair("bridge.getPubAddrFromSeedHexIndex(\(BILJSArg.str(seed)), \(index))", success: success, failure: failure)
    }

    /// Multisig setup transaction (contract 5.5.1) → (hash hex, envelope base64).
    public func buildMsSetup(seed: String, index: Int, info: [String: Any], success: @escaping (_ hash: String, _ envelope: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        guard let d = BILJSArg.json(info) else { StellarJSBridge.jsonFailure(failure); return }
        callPair("bridge.buildMsSetupTxWithSeedHexIndex(\(BILJSArg.str(seed)), \(index), \(d))", success: success, failure: failure)
    }

    /// Unsigned multisig Transaction XDR (contract 5.7.1) → (hash hex, tx XDR base64). No keys involved.
    public func buildMsTxXdr(data: [String: Any], success: @escaping (_ hash: String, _ xdr: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        guard let d = BILJSArg.json(data) else { StellarJSBridge.jsonFailure(failure); return }
        callPair("bridge.buildMsTxXdr(\(d))", success: success, failure: failure)
    }

    /// Strict decode (contract 5.7.3) → JSON text (amount / limit as raw int64 strings).
    public func decodeMsTxXdr(_ xdr: String, success: @escaping (_ json: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callJS(method: "bridge.decodeMsTxXdr(\(BILJSArg.str(xdr)))", success: { result in
            guard result.isString, let s = result.toString(), !s.isEmpty else {
                failure(JSError.resultError)
                return
            }
            success(s)
        }, failure: failure)
    }

    /// Computes the hash locally and signs it with the signer key (contract 5.7.2) → (hash hex, signature base64).
    public func signMsTxXdr(seed: String, xdr: String, success: @escaping (_ hash: String, _ sig: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callPair("bridge.signMsTxXdrWithSeedHex(\(BILJSArg.str(seed)), \(BILJSArg.str(xdr)))", success: success, failure: failure)
    }
}
