//  EthereumJSBridge.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  ETH and the EVM chains Ownbit supports (BSC / ARB / OP / BASE / AVAX / HYPE: same keys and addresses, `chainId` per
//  chain; ETC in EthereumClassicJSBridge.swift): addresses (m/44'/60'/0'/0/n), legacy (pre-EIP-1559) transactions and
//  token transfers (ERC-20 / 721 / 1155 by `tokenType`), Ownbit multisig contracts (deploy, cosigner signatures, spend),
//  personal_sign messages, the TRX key (m/44'/195'/0'/0/0). EIP-1559 transactions, typed data and WalletConnect
//  multisig signatures are in EthereumExtJSBridge.
//  Bundle: ethereumjs-lib-app.min.js in a JSContext.
//
//  Every string argument is escaped (`jsEscaped`, JSON for arrays / objects). The app left seeds, private keys, the
//  multisig spend / owner / signer arguments and the deploy arguments unescaped (hot-wallet values); they are escaped here
//  too, which changes nothing for hex / addresses.

import Foundation
import JavaScriptCore

/// `addressTo` value meaning "deploy a contract" (JS gets `null` as the recipient).
let DEPLOY_CONTRACT = "0x0"

public final class EthereumJSBridge: JSBridge, JSBridgeValidAddressProtocol {

    public static let shared = EthereumJSBridge()

    override var contextScript: Resource? {
        return Resource(name: "ethereumjs-lib-app.min", ext: "js", directory: "ethereumjs-lib-bridge")
    }

    /// Hex data is always lowercased and 0x-prefixed (empty stays empty).
    static func hexData(_ customData: String) -> String {
        var data = customData.lowercased()
        if data.count > 0, !data.hasPrefix("0x") {
            data = "0x" + data
        }
        return data
    }

    private static func stripped0x(_ s: String) -> String {
        if s.lowercased().hasPrefix("0x") {
            return String(s.suffix(s.count - 2))
        }
        return s
    }

    // MARK: - Addresses and keys

    public func getChecksumAddress(address: String, success: @escaping (_ checksumAddress: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callJSNonEmptyString("bridge.toChecksumAddress('\(address.jsEscaped)')", success: success, failure: failure)
    }

    /// m/44'/60'/0'/0/indexNo → (account xpub, public key, EIP-55 address).
    public func getPublicKeyAndAddress(seed: String, indexNo: Int, success: @escaping (_ extPubKey: String, _ publicKey: String, _ address: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        let path = "m/44'/60'/0'/0/" + String(indexNo)
        callJSStrings("bridge.seedHexToPubAddr('\(seed.jsEscaped)', \"\(path.jsEscaped)\")", count: 3, success: { success($0[0], $0[1], $0[2]) }, failure: failure)
    }

    /// Watch / cold side: the xpub from getPublicKeyAndAddress(seed:) → (public key, address) of `indexNo`.
    public func getPublicKeyAndAddress(extPubKey: String, indexNo: Int, success: @escaping (_ publicKey: String, _ address: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callJSStrings("bridge.extPubKeyToPubAddr('\(extPubKey.jsEscaped)', \(indexNo))", count: 2, success: { success($0[0], $0[1]) }, failure: failure)
    }

    /// ICAP (IBAN) → address.
    public func ibanToAddress(iban: String, success: @escaping (_ object: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callJSNonEmptyString("bridge.ibanToAddress('\(iban.jsEscaped)')", success: success, failure: failure)
    }

    public func addressToIban(address: String, success: @escaping (_ object: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callJSNonEmptyString("bridge.addressToIban('\(address.jsEscaped)')", success: success, failure: failure)
    }

    public func validateAddress(address: String, success: @escaping () -> Void, failure: @escaping (_ error: String) -> Void) {
        callJSValidate("bridge.isAddress('\(address.jsEscaped)')", success: success, failure: failure)
    }

    /// Private-key import (scanned / pasted text): → (public key, address).
    public func getPublicKeyAndAddress(from privateKey: String, success: @escaping (_ publicKey: String, _ address: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callJSStrings("bridge.getPubAddrFromPrivate('\(privateKey.jsEscaped)')", count: 2, success: { success($0[0], $0[1]) }, failure: failure)
    }

    /// m/44'/60'/0'/0/indexNo → private key hex without 0x.
    public func seedHexToPrivateHex(seedHex: String, indexNo: Int, success: @escaping (_ object: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        let path = "m/44'/60'/0'/0/" + String(indexNo)
        callJSNonEmptyString("bridge.seedHexToPrivateHex('\(seedHex.jsEscaped)', \"\(path.jsEscaped)\")", success: { success(EthereumJSBridge.stripped0x($0)) }, failure: failure)
    }

    /// TRX key: m/44'/195'/0'/0/0 → private key hex without 0x (TronJSBridge derives the address from it).
    public func seedHexToTrxPrivateKey(seedHex: String, success: @escaping (_ object: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        let path = "m/44'/195'/0'/0/" + String(0)
        callJSNonEmptyString("bridge.seedHexToPrivateHex('\(seedHex.jsEscaped)', \"\(path.jsEscaped)\")", success: { success(EthereumJSBridge.stripped0x($0)) }, failure: failure)
    }

    // MARK: - Transactions (legacy gas price)
    // chainId: 1 ETH, 56 BSC, 61 ETC, … amountWei is truncated to an integer string; NaN fails.

    public func buildTransaction(amountWei: NSDecimalNumber, addressTo: String, nonce: Int64, privateKey: String, gasPrice: Int64, gasLimit: Int64, customData: String = "", chainId: Int = 1, success: @escaping (_ txID: String, _ txHex: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        guard let amount = JSBridge.wireAmount(amountWei, failure: failure) else { return }
        let data = EthereumJSBridge.hexData(customData)
        let to = addressTo.lowercased() == DEPLOY_CONTRACT ? "null" : "'\(addressTo.jsEscaped)'"
        let method = "bridge.buildEthTransaction('\(privateKey.jsEscaped)', '\(amount)', \(to), '\(nonce)', '\(gasPrice)', '\(gasLimit)', '\(data.jsEscaped)', \(chainId))"
        callJSStrings(method, count: 2, success: { success($0[0], $0[1]) }, failure: failure)
    }

    public func buildTransaction(amountWei: NSDecimalNumber, addressTo: String, nonce: Int64, seed: String, indexNo: Int, gasPrice: Int64, gasLimit: Int64, customData: String = "", chainId: Int = 1, success: @escaping (_ txID: String, _ txHex: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        guard let amount = JSBridge.wireAmount(amountWei, failure: failure) else { return }
        let data = EthereumJSBridge.hexData(customData)
        let to = addressTo.lowercased() == DEPLOY_CONTRACT ? "null" : "'\(addressTo.jsEscaped)'"
        let method = "bridge.buildEthTxBySeedHex('\(seed.jsEscaped)', \(indexNo), '\(amount)', \(to), '\(nonce)', '\(gasPrice)', '\(gasLimit)', '\(data.jsEscaped)', \(chainId))"
        callJSStrings(method, count: 2, success: { success($0[0], $0[1]) }, failure: failure)
    }

    /// tokenType: the bundle's token kind (ERC-20 / 721 / 1155); tokenId for NFTs.
    public func buildETHTokenTransaction(amountWei: NSDecimalNumber, addressTo: String, nonce: Int64, privateKey: String, gasPrice: Int64, gasLimit: Int64, contractAddress: String, tokenType: Int16, addressFrom: String, tokenId: String, chainId: Int = 1, success: @escaping (_ txID: String, _ txHex: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        guard let amount = JSBridge.wireAmount(amountWei, failure: failure) else { return }
        let method = "bridge.buildTokenTransaction('\(amount)', '\(addressTo.jsEscaped)', '\(nonce)', '\(contractAddress.jsEscaped)', '\(gasLimit)', '\(gasPrice)', '\(privateKey.jsEscaped)', \(tokenType), '\(addressFrom.jsEscaped)', '\(tokenId.jsEscaped)', \(chainId))"
        callJSStrings(method, count: 2, success: { success($0[0], $0[1]) }, failure: failure)
    }

    public func buildETHTokenTransaction(amountWei: NSDecimalNumber, addressTo: String, nonce: Int64, seed: String, indexNo: Int, gasPrice: Int64, gasLimit: Int64, contractAddress: String, tokenType: Int16, addressFrom: String, tokenId: String, chainId: Int = 1, success: @escaping (_ txID: String, _ txHex: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        guard let amount = JSBridge.wireAmount(amountWei, failure: failure) else { return }
        let method = "bridge.buildTokenTxBySeedHex('\(seed.jsEscaped)', \(indexNo), '\(amount)', '\(addressTo.jsEscaped)', '\(nonce)', '\(contractAddress.jsEscaped)', '\(gasLimit)', '\(gasPrice)', \(tokenType), '\(addressFrom.jsEscaped)', '\(tokenId.jsEscaped)', \(chainId))"
        callJSStrings(method, count: 2, success: { success($0[0], $0[1]) }, failure: failure)
    }
}

// MARK: - Ownbit multisig contracts

extension EthereumJSBridge {

    /// Deploys an Ownbit multisig contract. apInt: 0 standard, 1 accident protection. success: (txHex, txHash) in the
    /// bundle's order.
    public func buildDeployContractTx(by seedHex: String, indexNo: Int, addresses: [String], requiredCount: Int, nonce: Int64, gasLimit: Int64, gasPrice: Int64, apInt: Int16, chainId: Int, success: @escaping (_ txHex: String, _ txHash: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        let constructorArgs = ["owners": addresses, "required": requiredCount, "accidentProtection": apInt] as [String: Any]
        let method = "bridge.buildDeployContractTxBySeedHex('\(JSBridge.jsonText(constructorArgs).jsEscaped)', '\(nonce)', '\(gasLimit)', '\(gasPrice)', '\(seedHex.jsEscaped)', \(indexNo), \(chainId))"
        callJSStrings(method, count: 2, success: { success($0[0], $0[1]) }, failure: failure)
    }

    public func buildDeployContractTxBy(privateKey: String, addresses: [String], requiredCount: Int, nonce: Int64, gasLimit: Int64, gasPrice: Int64, apInt: Int16, chainId: Int, success: @escaping (_ txHex: String, _ txHash: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        let constructorArgs = ["owners": addresses, "required": requiredCount, "accidentProtection": apInt] as [String: Any]
        let method = "bridge.buildDeployContractTx('\(JSBridge.jsonText(constructorArgs).jsEscaped)', '\(nonce)', '\(gasLimit)', '\(gasPrice)', '\(privateKey.jsEscaped)', \(chainId))"
        callJSStrings(method, count: 2, success: { success($0[0], $0[1]) }, failure: failure)
    }

    /// Enterprise multisig (owners + weighted signers), accidentProtection 3.
    public func buildDeployEnterpriseContractTx(by seedHex: String, indexNo: Int, owners: [String], signers: [String], weights: [Int16], ownerRequired: Int, signerRequired: Int, nonce: Int64, gasLimit: Int64, gasPrice: Int64, chainId: Int, success: @escaping (_ txHex: String, _ txHash: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        let apInt = 3 // 0: standard, 1: accident protection, 2: CA (not used), 3: enterprise
        let constructorArgs = ["owners": owners, "signers": signers, "weights": weights, "ownerRequired": ownerRequired, "signerRequired": signerRequired, "accidentProtection": apInt] as [String: Any]
        let method = "bridge.buildDeployEnterpriseContractTxBySeedHex('\(JSBridge.jsonText(constructorArgs).jsEscaped)', '\(nonce)', '\(gasLimit)', '\(gasPrice)', '\(seedHex.jsEscaped)', \(indexNo), \(chainId))"
        callJSStrings(method, count: 2, success: { success($0[0], $0[1]) }, failure: failure)
    }

    public func buildDeployEnterpriseContractTxBy(privateKey: String, owners: [String], signers: [String], weights: [Int16], ownerRequired: Int, signerRequired: Int, nonce: Int64, gasLimit: Int64, gasPrice: Int64, chainId: Int, success: @escaping (_ txHex: String, _ txHash: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        let apInt = 3
        let constructorArgs = ["owners": owners, "signers": signers, "weights": weights, "ownerRequired": ownerRequired, "signerRequired": signerRequired, "accidentProtection": apInt] as [String: Any]
        let method = "bridge.buildDeployEnterpriseContractTx('\(JSBridge.jsonText(constructorArgs).jsEscaped)', '\(nonce)', '\(gasLimit)', '\(gasPrice)', '\(privateKey.jsEscaped)', \(chainId))"
        callJSStrings(method, count: 2, success: { success($0[0], $0[1]) }, failure: failure)
    }

    /// Cosigner signature (v, r, s) for the first-generation contract.
    public func generateMultiSig(by seedHex: String, nonce: Int64, contractAddress: String, amountWei: NSDecimalNumber, destination: String, success: @escaping (_ v: String, _ r: String, _ s: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        guard let amount = JSBridge.wireAmount(amountWei, failure: failure) else { return }
        let method = "bridge.generateMultiSigBySeedHex('\(nonce)', '\(contractAddress.jsEscaped)', '\(amount)', '\(destination.jsEscaped)', '\(seedHex.jsEscaped)')"
        callVRS(method, success: success, failure: failure)
    }

    /// Ownbit-MS-Compound contract. Pass 0x0000000000000000000000000000000000000000 as erc20Contract for the native coin.
    public func generateMultiSigV2(by seedHex: String, msContractAddress: String, erc20Contract: String, destination: String, amountWei: NSDecimalNumber, nonce: Int64, chainId: Int, success: @escaping (_ v: String, _ r: String, _ s: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        guard let amount = JSBridge.wireAmount(amountWei, failure: failure) else { return }
        let method = "bridge.generateMultiSigBySeedHexV2('\(msContractAddress.jsEscaped)', '\(erc20Contract.jsEscaped)', '\(destination.jsEscaped)', '\(amount)', \(nonce), \(chainId), '\(seedHex.jsEscaped)')"
        callVRS(method, success: success, failure: failure)
    }

    /// Current contracts. ercType matters only when erc20Contract is an NFT. forceChainId (v10 / v11 / v21 contracts,
    /// `spendHashAlwaysHasChainId`): the chain ID is part of the message on every chain (V4 functions).
    public func generateMultiSigV3(by seedHex: String, msContractAddress: String, erc20Contract: String, ercType: Int16, destination: String, amountWei: NSDecimalNumber, nonce: Int64, chainId: Int, forceChainId: Bool = false, success: @escaping (_ v: String, _ r: String, _ s: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        guard let amount = JSBridge.wireAmount(amountWei, failure: failure) else { return }
        let function = forceChainId ? "generateMultiSigBySeedHexV4" : "generateMultiSigBySeedHexV3"
        let method = "bridge.\(function)('\(msContractAddress.jsEscaped)', '\(erc20Contract.jsEscaped)', \(ercType), '\(destination.jsEscaped)', '\(amount)', \(nonce), \(chainId), '\(seedHex.jsEscaped)')"
        callVRS(method, success: success, failure: failure)
    }

    public func generateMultiSigV3_changeOwners(by seedHex: String, msContractAddress: String, newOwners: [String], newOwnerRequired: Int16, nonce: Int64, chainId: Int, forceChainId: Bool = false, success: @escaping (_ v: String, _ r: String, _ s: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        let function = forceChainId ? "generateMultiSigBySeedHexV4_changeOwners" : "generateMultiSigBySeedHexV3_changeOwners"
        let method = "bridge.\(function)('\(msContractAddress.jsEscaped)', \(JSBridge.jsArrayLiteral(newOwners)), \(newOwnerRequired), \(nonce), \(chainId), '\(seedHex.jsEscaped)')"
        callVRS(method, success: success, failure: failure)
    }

    public func generateMultiSigV3_changeSigners(by seedHex: String, msContractAddress: String, newSigners: [String], newWeights: [Int16], newSignerRequired: Int16, nonce: Int64, chainId: Int, forceChainId: Bool = false, success: @escaping (_ v: String, _ r: String, _ s: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        let function = forceChainId ? "generateMultiSigBySeedHexV4_changeSigners" : "generateMultiSigBySeedHexV3_changeSigners"
        let method = "bridge.\(function)('\(msContractAddress.jsEscaped)', \(JSBridge.jsArrayLiteral(newSigners)), \(newWeights), \(newSignerRequired), \(nonce), \(chainId), '\(seedHex.jsEscaped)')"
        callVRS(method, success: success, failure: failure)
    }

    /// dApp / WalletConnect multisig: spend message for any destination + value + calldata. Message as V3:
    /// ms ‖ dest ‖ value(32) ‖ data ‖ spendNonce(32) ‖ [chainId(32) only when chainId > 1]; forceChainId: always (V4).
    public func generateMultiSigV3Generic(by seedHex: String, msContractAddress: String, destination: String, valueWei: NSDecimalNumber, dataHex: String, nonce: Int64, chainId: Int, forceChainId: Bool = false, success: @escaping (_ v: String, _ r: String, _ s: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        guard let value = JSBridge.wireAmount(valueWei, failure: failure) else { return }
        let function = forceChainId ? "generateMultiSigBySeedHexV4Generic" : "generateMultiSigBySeedHexV3Generic"
        let method = "bridge.\(function)('\(msContractAddress.jsEscaped)', '\(destination.jsEscaped)', '\(value)', '\(dataHex.jsEscaped)', \(nonce), \(chainId), '\(seedHex.jsEscaped)')"
        callVRS(method, success: success, failure: failure)
    }

    /// (v, r, s): the bundle's values stringified with Swift's "\(value)" as in the app (v is a number).
    private func callVRS(_ method: String, success: @escaping (_ v: String, _ r: String, _ s: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callJS(method: method, success: { result in
            guard let arr = result.toArray(), arr.count >= 3 else {
                failure(JSError.resultError)
                return
            }
            let r = arr.map { "\($0)" }
            success(r[0], r[1], r[2])
        }, failure: failure)
    }

    /// Spend from a multisig contract with the collected signatures. purpose: 0 normal send, 1-4 Compound, 9 arbitrary.
    /// success: (txHex, txHash) in the bundle's order.
    public func buildMSContractSpendTx(by seedHex: String, indexNo: Int, amountWei: NSDecimalNumber, destination: String, erc20ContractAddress: String, purpose: Int16 = 0, v: [String], r: [String], s: [String], nonce: Int64, contractAddress: String, gasLimit: Int64, gasPrice: Int64, chainId: Int, success: @escaping (_ txHex: String, _ txHash: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        guard let amount = JSBridge.wireAmount(amountWei, failure: failure) else { return }
        let method = "bridge.buildCallMSContractMdTxBySeedHex('\(destination.jsEscaped)', '\(erc20ContractAddress.jsEscaped)', '\(amount)', \(purpose),  '\(JSBridge.jsonText(v).jsEscaped)', '\(JSBridge.jsonText(r).jsEscaped)', '\(JSBridge.jsonText(s).jsEscaped)', '\(nonce)', '\(contractAddress.jsEscaped)', '\(gasLimit)', '\(gasPrice)', '\(seedHex.jsEscaped)', \(indexNo), \(chainId))"
        callJSStrings(method, count: 2, success: { success($0[0], $0[1]) }, failure: failure)
    }

    /// purpose 1 (Compound) needs the specific erc20ContractAddress; purpose 9: any 0x… there, 0x9 for the signature.
    public func buildMSContractSpendTxBy(privateKey: String, amountWei: NSDecimalNumber, destination: String, erc20ContractAddress: String, purpose: Int16 = 0, v: [String], r: [String], s: [String], nonce: Int64, contractAddress: String, gasLimit: Int64, gasPrice: Int64, chainId: Int, success: @escaping (_ txHex: String, _ txHash: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        guard let amount = JSBridge.wireAmount(amountWei, failure: failure) else { return }
        let method = "bridge.buildCallMSContractMdTx('\(destination.jsEscaped)', '\(erc20ContractAddress.jsEscaped)', '\(amount)', \(purpose), '\(JSBridge.jsonText(v).jsEscaped)', '\(JSBridge.jsonText(r).jsEscaped)', '\(JSBridge.jsonText(s).jsEscaped)', '\(nonce)', '\(contractAddress.jsEscaped)', '\(gasLimit)', '\(gasPrice)', '\(privateKey.jsEscaped)', \(chainId))"
        callJSStrings(method, count: 2, success: { success($0[0], $0[1]) }, failure: failure)
    }

    /// Current contracts (ercType instead of purpose).
    public func buildMSContractSpendTxV3(by seedHex: String, indexNo: Int, amountWei: NSDecimalNumber, destination: String, erc20ContractAddress: String, ercType: Int16, v: [String], r: [String], s: [String], nonce: Int64, contractAddress: String, gasLimit: Int64, gasPrice: Int64, chainId: Int, success: @escaping (_ txHex: String, _ txHash: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        guard let amount = JSBridge.wireAmount(amountWei, failure: failure) else { return }
        let method = "bridge.buildCallMSContractMdTxBySeedHexV3('\(destination.jsEscaped)', '\(erc20ContractAddress.jsEscaped)', '\(amount)', \(ercType), '\(JSBridge.jsonText(v).jsEscaped)', '\(JSBridge.jsonText(r).jsEscaped)', '\(JSBridge.jsonText(s).jsEscaped)', '\(nonce)', '\(contractAddress.jsEscaped)', '\(gasLimit)', '\(gasPrice)', '\(seedHex.jsEscaped)', \(indexNo), \(chainId))"
        callJSStrings(method, count: 2, success: { success($0[0], $0[1]) }, failure: failure)
    }

    public func buildMSContractSpendTxByV3(privateKey: String, amountWei: NSDecimalNumber, destination: String, erc20ContractAddress: String, ercType: Int16, v: [String], r: [String], s: [String], nonce: Int64, contractAddress: String, gasLimit: Int64, gasPrice: Int64, chainId: Int, success: @escaping (_ txHex: String, _ txHash: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        guard let amount = JSBridge.wireAmount(amountWei, failure: failure) else { return }
        let method = "bridge.buildCallMSContractMdTxV3('\(destination.jsEscaped)', '\(erc20ContractAddress.jsEscaped)', '\(amount)', \(ercType),  '\(JSBridge.jsonText(v).jsEscaped)', '\(JSBridge.jsonText(r).jsEscaped)', '\(JSBridge.jsonText(s).jsEscaped)', '\(nonce)', '\(contractAddress.jsEscaped)', '\(gasLimit)', '\(gasPrice)', '\(privateKey.jsEscaped)', \(chainId))"
        callJSStrings(method, count: 2, success: { success($0[0], $0[1]) }, failure: failure)
    }

    // MARK: - personal_sign

    /// The message should be trimmed beforehand. Fully escaped as a JS literal, so JS signs exactly the text shown
    /// (escape sequences such as `\x30\x78` are not decoded into other bytes).
    public func signEthereumMessage(message: String, privateKey: String, success: @escaping (_ object: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callJSNonEmptyString("bridge.signEthereumMessage(\"\(message.jsEscaped)\", \"\(privateKey.jsEscaped)\")", success: success, failure: failure)
    }

    /// Recovers the signer address (same escaping as signEthereumMessage).
    public func getMessageSignAddress(message: String, signature: String, success: @escaping (_ object: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callJSNonEmptyString("bridge.getMessageSignAddress(\"\(message.jsEscaped)\", \"\(signature.jsEscaped)\")", success: success, failure: failure)
    }
}
