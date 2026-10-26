//  EthereumExtJSBridge.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  EVM, ethers-based (ETH / BSC / ARB / OP / BASE / AVAX / HYPE by chainId): EIP-1559 (type 2) transactions and token
//  transfers, Ownbit multisig spend / change-owners / change-signers (current contracts), EIP-712 typed data, and the
//  WalletConnect / ERC-1271 multisig signatures (v10 / v11 / v21 contracts).
//  Bundle: ethjs-ext-v2.js in a hidden web view (ethext_index.html). Its signing functions are `async` and report on
//  `window.webkit.messageHandlers.transaction` ("<txHash>:<signedTx>"), `.signTypedData` (signature) and `.error`.
//
//  Differences from the app (no UI in this package): the app called `success("", "")` right away and delivered the real
//  result to whichever view controller was registered; here `success` is called once with the real result, and an
//  `error` message calls `failure(.scriptError(message))`. One asynchronous call at a time per bridge (`.busy`).

import Foundation

public final class EthereumExtJSBridge: JSBridge {

    public static let shared = EthereumExtJSBridge()

    override var webPage: Resource? {
        return Resource(name: "ethext_index", ext: "html", directory: "ethereumjs-lib-bridge")
    }

    override var webMessageNames: [String] {
        return ["transaction", "signTypedData", "error"]
    }

    /// Waits for the "transaction" message: "<txHash>:<signedTx>" → success(txHash, signedTx).
    private func callTransaction(_ method: String, success: @escaping (_ txID: String, _ txHex: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callWebForMessage(method, channels: ["transaction"], success: { _, body in
            let parts = body.split(separator: ":")
            guard parts.count == 2 else {
                failure(JSError.resultError)
                return
            }
            success(String(parts[0]), String(parts[1]))
        }, failure: failure)
    }

    /// A function that returns its result directly (a string).
    private func callWebValue(_ method: String, success: @escaping (_ value: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callWeb(method: method, success: { result in
            guard let s = result as? String else {
                failure(JSError.resultError)
                return
            }
            success(s)
        }, failure: failure)
    }

    private static func lit(_ s: String) -> String {
        return JSBridge.jsStringLiteral(s)
    }

    // MARK: - Multisig WalletConnect / ERC-1271 (v10 / v11 / v21)

    /// digest / wrapped (the contract's getMessageHash) / signature deadline of the typed data. For display and countdown.
    public func ownbitWcInfo(msContractAddress: String, chainId: Int, method: String, payload: String, success: @escaping (_ digest: String, _ wrapped: String, _ deadline: TimeInterval) -> Void, failure: @escaping (_ error: Error) -> Void) {
        let js = "bridge.ownbitWcInfo(\(Self.lit(msContractAddress)), \(chainId), \(Self.lit(method)), \(Self.lit(payload)))"
        callWebValue(js, success: { value in
            guard let data = value.data(using: .utf8),
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let digest = obj["digest"] as? String, let wrapped = obj["wrapped"] as? String else {
                failure(JSError.resultError)
                return
            }
            let deadline = (obj["deadline"] as? NSNumber)?.doubleValue ?? 0
            success(digest, wrapped, deadline)
        }, failure: failure)
    }

    /// Raw signature over getMessageHash(digest); the digest is recomputed from `payload`, never taken from outside.
    /// v is 0 / 1 (as the server stores it).
    public func ownbitWcSign(privKey: String, msContractAddress: String, chainId: Int, method: String, payload: String, success: @escaping (_ v: String, _ r: String, _ s: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        let js = "bridge.ownbitWcSign(\(Self.lit(privKey)), \(Self.lit(msContractAddress)), \(chainId), \(Self.lit(method)), \(Self.lit(payload)))"
        callWebValue(js, success: { value in
            guard let data = value.data(using: .utf8),
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let v = obj["v"] as? NSNumber, let r = obj["r"] as? String, let s = obj["s"] as? String else {
                failure(JSError.resultError)
                return
            }
            success("\(v.intValue)", r, s)
        }, failure: failure)
    }

    /// Recovers the signer address from (v, r, s); "0x" on failure (from JS).
    public func ownbitWcRecover(msContractAddress: String, chainId: Int, method: String, payload: String, v: String, r: String, s: String, success: @escaping (_ address: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        let js = "bridge.ownbitWcRecover(\(Self.lit(msContractAddress)), \(chainId), \(Self.lit(method)), \(Self.lit(payload)), \(Self.lit(v)), \(Self.lit(r)), \(Self.lit(s)))"
        callWebValue(js, success: success, failure: failure)
    }

    // MARK: - EIP-712

    /// params: the typed-data JSON (eth_signTypedData_v4). success gets the signature.
    public func signTypedData(privKey: String, params: String, success: @escaping (_ sig: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        let method = "bridge.signTypedData(\(Self.lit(privKey)), \(Self.lit(params)))"
        callWebForMessage(method, channels: ["signTypedData"], success: { _, body in
            success(body)
        }, failure: failure)
    }

    // MARK: - EIP-1559 transactions
    // gasPrice = maxFeePerGas, gasPriority = maxPriorityFeePerGas (wei). success: (txHash, signed transaction hex).

    public func buildEthTransaction(privateKey: String, addressTo: String, amountWei: NSDecimalNumber, nonce: Int64, gasPrice: Int64, gasPriority: Int64, gasLimit: Int64, customData: String = "", chainId: Int, success: @escaping (_ txID: String, _ txHex: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        guard let amount = JSBridge.wireAmount(amountWei, failure: failure) else { return }
        let data = EthereumJSBridge.hexData(customData)
        let to = addressTo.lowercased() == DEPLOY_CONTRACT ? "null" : "'\(addressTo.jsEscaped)'"
        let method = "bridge.signEthTransactionByPrivateKey('\(privateKey.jsEscaped)', \(to), '\(amount)', '\(gasLimit)', '\(gasPrice)', '\(gasPriority)', \(chainId), \(nonce), '\(data.jsEscaped)')"
        callTransaction(method, success: success, failure: failure)
    }

    public func buildEthTransaction(seedHex: String, indexNo: Int, addressTo: String, amountWei: NSDecimalNumber, nonce: Int64, gasPrice: Int64, gasPriority: Int64, gasLimit: Int64, customData: String = "", chainId: Int, success: @escaping (_ txID: String, _ txHex: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        guard let amount = JSBridge.wireAmount(amountWei, failure: failure) else { return }
        let data = EthereumJSBridge.hexData(customData)
        let to = addressTo.lowercased() == DEPLOY_CONTRACT ? "null" : "'\(addressTo.jsEscaped)'"
        let method = "bridge.signEthTransactionBySeedHex('\(seedHex.jsEscaped)', \(indexNo), \(to), '\(amount)', '\(gasLimit)', '\(gasPrice)', '\(gasPriority)', \(chainId), \(nonce), '\(data.jsEscaped)')"
        callTransaction(method, success: success, failure: failure)
    }

    /// ercType: token kind (ERC-20 / 721 / 1155); tokenId for NFTs.
    public func buildTokenTransaction(privateKey: String, addressTo: String, amountWei: NSDecimalNumber, nonce: Int64, gasPrice: Int64, gasPriority: Int64, gasLimit: Int64, contractAddress: String, ercType: Int16, tokenId: String, chainId: Int, success: @escaping (_ txID: String, _ txHex: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        guard let amount = JSBridge.wireAmount(amountWei, failure: failure) else { return }
        let method = "bridge.signTokenTransactionByPrivateKey('\(privateKey.jsEscaped)', '\(contractAddress.jsEscaped)', '\(addressTo.jsEscaped)', '\(amount)', '\(gasLimit)', '\(gasPrice)', '\(gasPriority)', \(chainId), \(nonce), '\(tokenId.jsEscaped)', \(ercType))"
        callTransaction(method, success: success, failure: failure)
    }

    public func buildTokenTransaction(seedHex: String, indexNo: Int, addressTo: String, amountWei: NSDecimalNumber, nonce: Int64, gasPrice: Int64, gasPriority: Int64, gasLimit: Int64, contractAddress: String, ercType: Int16, tokenId: String, chainId: Int, success: @escaping (_ txID: String, _ txHex: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        guard let amount = JSBridge.wireAmount(amountWei, failure: failure) else { return }
        let method = "bridge.signTokenTransactionBySeedHex('\(seedHex.jsEscaped)', \(indexNo), '\(contractAddress.jsEscaped)', '\(addressTo.jsEscaped)', '\(amount)', '\(gasLimit)', '\(gasPrice)', '\(gasPriority)', \(chainId), \(nonce), '\(tokenId.jsEscaped)', \(ercType))"
        callTransaction(method, success: success, failure: failure)
    }

    // MARK: - Multisig (current contracts), EIP-1559 outer transaction

    public func buildMSContractSpendTxByV3(privateKey: String, multisigAddress: String, erc20ContractAddress: String, destination: String, amountWei: NSDecimalNumber, ercType: Int16, v: [String], r: [String], s: [String], nonce: Int64, gasLimit: Int64, gasPrice: Int64, gasPriority: Int64, chainId: Int, success: @escaping (_ txID: String, _ txHex: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        guard let amount = JSBridge.wireAmount(amountWei, failure: failure) else { return }
        let method = "bridge.signMultiSigSpendV3TransactionByPrivateKey('\(privateKey.jsEscaped)', '\(multisigAddress.jsEscaped)', '\(erc20ContractAddress.jsEscaped)', '\(destination.jsEscaped)', '\(amount)',  \(JSBridge.jsonText(v)), \(JSBridge.jsonText(r)), \(JSBridge.jsonText(s)), \(ercType), '\(gasLimit)', '\(gasPrice)', '\(gasPriority)', \(chainId), \(nonce))"
        callTransaction(method, success: success, failure: failure)
    }

    public func buildMSContractSpendTxByV3(seedHex: String, indexNo: Int, multisigAddress: String, erc20ContractAddress: String, destination: String, amountWei: NSDecimalNumber, ercType: Int16, v: [String], r: [String], s: [String], nonce: Int64, gasLimit: Int64, gasPrice: Int64, gasPriority: Int64, chainId: Int, success: @escaping (_ txID: String, _ txHex: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        guard let amount = JSBridge.wireAmount(amountWei, failure: failure) else { return }
        let method = "bridge.signMultiSigSpendV3TransactionBySeedHex('\(seedHex.jsEscaped)', \(indexNo), '\(multisigAddress.jsEscaped)', '\(erc20ContractAddress.jsEscaped)', '\(destination.jsEscaped)', '\(amount)',  \(JSBridge.jsonText(v)), \(JSBridge.jsonText(r)), \(JSBridge.jsonText(s)), \(ercType), '\(gasLimit)', '\(gasPrice)', '\(gasPriority)', \(chainId), \(nonce))"
        callTransaction(method, success: success, failure: failure)
    }

    /// dApp / WalletConnect multisig: spend() with any destination + value + calldata.
    public func buildMSContractSpendTxV3Generic(privateKey: String, multisigAddress: String, destination: String, valueWei: NSDecimalNumber, dataHex: String, v: [String], r: [String], s: [String], nonce: Int64, gasLimit: Int64, gasPrice: Int64, gasPriority: Int64, chainId: Int, success: @escaping (_ txID: String, _ txHex: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        guard let value = JSBridge.wireAmount(valueWei, failure: failure) else { return }
        let method = "bridge.signMultiSigSpendV3GenericTransactionByPrivateKey('\(privateKey.jsEscaped)', '\(multisigAddress.jsEscaped)', '\(destination.jsEscaped)', '\(value)', '\(dataHex.jsEscaped)', \(JSBridge.jsonText(v)), \(JSBridge.jsonText(r)), \(JSBridge.jsonText(s)), '\(gasLimit)', '\(gasPrice)', '\(gasPriority)', \(chainId), \(nonce))"
        callTransaction(method, success: success, failure: failure)
    }

    public func buildMSContractSpendTxV3Generic(seedHex: String, indexNo: Int, multisigAddress: String, destination: String, valueWei: NSDecimalNumber, dataHex: String, v: [String], r: [String], s: [String], nonce: Int64, gasLimit: Int64, gasPrice: Int64, gasPriority: Int64, chainId: Int, success: @escaping (_ txID: String, _ txHex: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        guard let value = JSBridge.wireAmount(valueWei, failure: failure) else { return }
        let method = "bridge.signMultiSigSpendV3GenericTransactionBySeedHex('\(seedHex.jsEscaped)', \(indexNo), '\(multisigAddress.jsEscaped)', '\(destination.jsEscaped)', '\(value)', '\(dataHex.jsEscaped)', \(JSBridge.jsonText(v)), \(JSBridge.jsonText(r)), \(JSBridge.jsonText(s)), '\(gasLimit)', '\(gasPrice)', '\(gasPriority)', \(chainId), \(nonce))"
        callTransaction(method, success: success, failure: failure)
    }

    public func buildMSContractChangeOwnersTxByV3(privateKey: String, multisigAddress: String, newOwners: [String], newOwnerRequired: Int16, v: [String], r: [String], s: [String], nonce: Int64, gasLimit: Int64, gasPrice: Int64, gasPriority: Int64, chainId: Int, success: @escaping (_ txID: String, _ txHex: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        let method = "bridge.signMultiSigChangeOwnersV3TransactionByPrivateKey('\(privateKey.jsEscaped)', '\(multisigAddress.jsEscaped)', \(JSBridge.jsArrayLiteral(newOwners)), \(newOwnerRequired), \(JSBridge.jsonText(v)), \(JSBridge.jsonText(r)), \(JSBridge.jsonText(s)), '\(gasLimit)', '\(gasPrice)', '\(gasPriority)', \(chainId), \(nonce))"
        callTransaction(method, success: success, failure: failure)
    }

    public func buildMSContractChangeOwnersTxByV3(seedHex: String, indexNo: Int, multisigAddress: String, newOwners: [String], newOwnerRequired: Int16, v: [String], r: [String], s: [String], nonce: Int64, gasLimit: Int64, gasPrice: Int64, gasPriority: Int64, chainId: Int, success: @escaping (_ txID: String, _ txHex: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        let method = "bridge.signMultiSigChangeOwnersV3TransactionBySeedHex('\(seedHex.jsEscaped)', \(indexNo), '\(multisigAddress.jsEscaped)', \(JSBridge.jsArrayLiteral(newOwners)), \(newOwnerRequired), \(JSBridge.jsonText(v)), \(JSBridge.jsonText(r)), \(JSBridge.jsonText(s)), '\(gasLimit)', '\(gasPrice)', '\(gasPriority)', \(chainId), \(nonce))"
        callTransaction(method, success: success, failure: failure)
    }

    public func buildMSContractChangeSignersTxByV3(privateKey: String, multisigAddress: String, newSigners: [String], newWeights: [Int16], newSignerRequired: Int16, v: [String], r: [String], s: [String], nonce: Int64, gasLimit: Int64, gasPrice: Int64, gasPriority: Int64, chainId: Int, success: @escaping (_ txID: String, _ txHex: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        let method = "bridge.signMultiSigChangeSignersV3TransactionByPrivateKey('\(privateKey.jsEscaped)', '\(multisigAddress.jsEscaped)', \(JSBridge.jsArrayLiteral(newSigners)), \(newWeights), \(newSignerRequired), \(JSBridge.jsonText(v)), \(JSBridge.jsonText(r)), \(JSBridge.jsonText(s)), '\(gasLimit)', '\(gasPrice)', '\(gasPriority)', \(chainId), \(nonce))"
        callTransaction(method, success: success, failure: failure)
    }

    public func buildMSContractChangeSignersTxByV3(seedHex: String, indexNo: Int, multisigAddress: String, newSigners: [String], newWeights: [Int16], newSignerRequired: Int16, v: [String], r: [String], s: [String], nonce: Int64, gasLimit: Int64, gasPrice: Int64, gasPriority: Int64, chainId: Int, success: @escaping (_ txID: String, _ txHex: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        let method = "bridge.signMultiSigChangeSignersV3TransactionBySeedHex('\(seedHex.jsEscaped)', \(indexNo), '\(multisigAddress.jsEscaped)', \(JSBridge.jsArrayLiteral(newSigners)), \(newWeights), \(newSignerRequired), \(JSBridge.jsonText(v)), \(JSBridge.jsonText(r)), \(JSBridge.jsonText(s)), '\(gasLimit)', '\(gasPrice)', '\(gasPriority)', \(chainId), \(nonce))"
        callTransaction(method, success: success, failure: failure)
    }
}
