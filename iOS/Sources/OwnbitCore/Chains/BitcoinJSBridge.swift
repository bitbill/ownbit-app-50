//  BitcoinJSBridge.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  BTC (legacy / P2SH-SegWit / native SegWit; Taproot is BTCTaprootJSBridge) and BIP39: mnemonic generation, mnemonic →
//  seed (with optional passphrase), account xpubs, addresses, WIF export, signing (single-sig and multisig), message
//  signing. Bundle: bitcoinjs-lib-app.js in a JSContext; `generateMnemonic` runs in a hidden web view (btc_index.html)
//  because `bridge.generateMnemonicRandom` takes its entropy from `window.crypto.getRandomValues`.
//
//  Every string argument is escaped with `jsEscaped` (the app already did this for external strings; seeds and paths
//  are now escaped too — a no-op for hex and `m/44'/…` paths, which is all a caller should pass).

import Foundation
import JavaScriptCore

/// `seedType` of `mnemonicToSeedHex`: 0 = BIP39, 1 = Electrum.
public let SEEDTYPE_BIP39: Int = 0
public let SEEDTYPE_ELECTRUM: Int = 1

public final class BitcoinJSBridge: JSBridge, JSBridgeValidAddressProtocol, BILCoinMultipleAddressGeneratorProtocol {

    /// Word lists for `generateMnemonic(language:)`: the index `bridge.generateMnemonicRandom` takes.
    /// The app only offers `english` (0) when creating a wallet.
    public enum MnemonicLanguage: Int, CaseIterable {
        case english = 0
        case chineseSimplified = 1
        case chineseTraditional = 2
        case japanese = 3
        case french = 4
        case italian = 5
        case korean = 6
        case spanish = 7
    }

    public static let shared = BitcoinJSBridge()

    override var contextScript: Resource? {
        return Resource(name: "bitcoinjs-lib-app", ext: "js", directory: "bitcoinjs-lib-bridge")
    }

    override var webPage: Resource? {
        return Resource(name: "btc_index", ext: "html", directory: "bitcoinjs-lib-bridge")
    }

    // MARK: - Mnemonic

    /// entropy: 128 (12 words) … 256 (24 words); language: `MnemonicLanguage` raw value. success gets a non-empty String.
    /// Needs the web environment: the randomness comes from `window.crypto.getRandomValues`.
    public func generateMnemonic(entropy: Int = 128, language: Int = 0, success: @escaping (_ object: Any) -> Void, failure: @escaping (_ error: Error) -> Void) {
        // Strict: anything but a non-empty string fails; never build a wallet from an odd value.
        callWebNonEmptyString("bridge.generateMnemonicRandom(\(entropy), \(language))", success: { success($0) }, failure: failure)
    }

    /// seedType must be 0 (BIP39) or 1 (Electrum). password = BIP39 passphrase ("" for none). success gets the seed hex.
    public func mnemonicToSeedHex(mnemonic: String, password: String = "", seedType: Int, success: @escaping (_ object: Any) -> Void, failure: @escaping (_ error: Error) -> Void) {
        let method = "bridge.mnemonicToSeedHex('\(mnemonic.jsEscaped)', '\(password.jsEscaped)', \(seedType))"
        callJSString(method, success: success, failure: failure)
    }

    public func mnemonicToEntropy(mnemonic: String, success: @escaping (_ object: Any) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callJSString("bridge.mnemonicToEntropy('\(mnemonic.jsEscaped)')", success: success, failure: failure)
    }

    /// Electrum seed version byte (1 = Electrum legacy, 16 = Electrum SegWit); success gets an Int32.
    public func electrumMnemonicType(mnemonic: String, success: @escaping (_ object: Any) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callJS(method: "bridge.getElectrumMnemonicType('\(mnemonic.jsEscaped)')", success: { result in
            success(result.toInt32())
        }, failure: failure)
    }

    /// BIP39 validity (word list + checksum) in any of the 8 word lists; success gets a Bool.
    public func validateMnemonic(mnemonic: String, success: @escaping (_ object: Any) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callJS(method: "bridge.validateMnemonic('\(mnemonic.jsEscaped)')", success: { result in
            success(result.toBool())
        }, failure: failure)
    }

    private func callJSString(_ method: String, success: @escaping (_ object: Any) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callJS(method: method, success: { result in
            guard let s = result.toString() else {
                failure(JSError.resultError)
                return
            }
            success(s)
        }, failure: failure)
    }

    // MARK: - Addresses

    public func validateAddress(address: String, success: @escaping () -> Void, failure: @escaping (_ error: String) -> Void) {
        callJSValidate("bridge.validateAddress('\(address.jsEscaped)')", success: success, failure: failure)
    }

    /// Legacy (1…) addresses fromIndex...toIndex (inclusive) of a chain-level xpub. success gets [String].
    public func getAddresses(xpub: String, fromIndex: Int64 = 0, toIndex: Int64, success: @escaping (_ object: Any) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callAddresses("bridge.getBitcoinContinuousAddressByMasterXPublicKey('\(xpub.jsEscaped)', \(fromIndex), \(toIndex))", success: success, failure: failure)
    }

    /// Native SegWit (bc1q…) addresses. success gets [String].
    public func getAddresses_sw_d(xpub: String, fromIndex: Int64 = 0, toIndex: Int64, success: @escaping (_ object: Any) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callAddresses("bridge.getBtcContinuousP2wpkhAddrByXpubkey('\(xpub.jsEscaped)', \(fromIndex), \(toIndex))", success: success, failure: failure)
    }

    /// P2SH-SegWit (3…) addresses. success gets [String].
    public func getAddresses_sw_p(xpub: String, fromIndex: Int64 = 0, toIndex: Int64, success: @escaping (_ object: Any) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callAddresses("bridge.getBtcContinuousP2shP2wpkhAddrByXpubkey('\(xpub.jsEscaped)', \(fromIndex), \(toIndex))", success: success, failure: failure)
    }

    private func callAddresses(_ method: String, success: @escaping (_ object: Any) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callJS(method: method, success: { result in
            guard let a = result.toArray() as? [String] else {
                failure(JSError.resultError)
                return
            }
            success(a)
        }, failure: failure)
    }

    // MARK: - Extended public keys
    // seedTypePath: "0" for a standard BIP39 wallet, or the Electrum type / custom path the wallet was imported with.

    public func getXPublicKeys_sw_d(seed: String, seedTypePath: String, success: @escaping (_ object: (mainPubkey: String, changePubkey: String, rootPubkey: String)) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callJSStrings("bridge.getBitcoinXPublicKeysForBIP84('\(seed.jsEscaped)', \"\(seedTypePath.jsEscaped)\")", count: 3, success: { success(($0[0], $0[1], $0[2])) }, failure: failure)
    }

    public func getXPublicKeys_sw_p(seed: String, seedTypePath: String, success: @escaping (_ object: (mainPubkey: String, changePubkey: String, rootPubkey: String)) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callJSStrings("bridge.getBitcoinXPublicKeysForBIP49('\(seed.jsEscaped)', \"\(seedTypePath.jsEscaped)\")", count: 3, success: { success(($0[0], $0[1], $0[2])) }, failure: failure)
    }

    public func getXPublicKeys(seed: String, seedTypePath: String, success: @escaping (_ object: (mainPubkey: String, changePubkey: String, rootPubkey: String)) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callJSStrings("bridge.getBitcoinXPublicKeys('\(seed.jsEscaped)', \"\(seedTypePath.jsEscaped)\")", count: 3, success: { success(($0[0], $0[1], $0[2])) }, failure: failure)
    }

    /// BIP44 / BIP49 / BIP84 receive and change xpubs in one call.
    public func getXPublicKeysForAll(seed: String, seedTypePath: String, success: @escaping (_ object: (mainPubkey: String, changePubkey: String, extPubkeyBip49: String, changePubkeyBip49: String, extPubkeyBip84: String, changePubkeyBip84: String)) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callJSStrings("bridge.getBitcoinXPublicKeysForAll('\(seed.jsEscaped)', \"\(seedTypePath.jsEscaped)\")", count: 6, success: { r in
            success((r[0], r[1], r[2], r[3], r[4], r[5]))
        }, failure: failure)
    }

    /// Account-level xpubs for BIP44 / BIP49 / BIP84 (xpub export).
    public func getXPublicKeysForAllRoot(seed: String, seedTypePath: String, success: @escaping (_ object: (rootPubkey: String, rootPubkeyBip49: String, rootPubkeyBip84: String)) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callJSStrings("bridge.getBitcoinXPublicKeysForAllRoot('\(seed.jsEscaped)', \"\(seedTypePath.jsEscaped)\")", count: 3, success: { success(($0[0], $0[1], $0[2])) }, failure: failure)
    }

    public func getMasterXPublicKey(seed: String, seedTypePath: String, success: @escaping (_ object: Any) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callJSString("bridge.getBitcoinMasterXPublicKey('\(seed.jsEscaped)', \"\(seedTypePath.jsEscaped)\")", success: success, failure: failure)
    }

    public func getChangeXPublicKey(seed: String, seedTypePath: String, success: @escaping (_ object: Any) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callJSString("bridge.getBitcoinChangeXPublicKey('\(seed.jsEscaped)', \"\(seedTypePath.jsEscaped)\")", success: success, failure: failure)
    }

    public func getMasterXPublicKey(mnemonic: String, seedType: Int, seedTypePath: String, success: @escaping (_ object: Any) -> Void, failure: @escaping (_ error: Error) -> Void) {
        mnemonicToSeedHex(mnemonic: mnemonic, seedType: seedType, success: { seedHex in
            self.getMasterXPublicKey(seed: (seedHex as? String) ?? "", seedTypePath: seedTypePath, success: success, failure: failure)
        }, failure: failure)
    }

    // MARK: - Signing

    /// inputsOutputs: the sign-data JSON (inputs / outputs / ophex / locktime …, see the bundle). success: (txId, txHex).
    public func buildTransaction(seedHex: String, seedTypePath: String, inputsOutputs: String, success: @escaping (_ object: (txId: String, txHex: String)) -> Void, failure: @escaping (_ error: Error) -> Void) {
        let method = "bridge.buildTransaction('\(seedHex.jsEscaped)', \"\(seedTypePath.jsEscaped)\", '\(inputsOutputs.jsEscaped)')"
        callJSStrings(method, count: 2, success: { success(($0[0], $0[1])) }, failure: failure)
    }

    /// Private-key wallet: every input signed with this key (WIF, or hex = uncompressed key, the bundle's rule).
    public func buildTransaction(privateKey: String, inputsOutputs: String, success: @escaping (_ object: (txId: String, txHex: String)) -> Void, failure: @escaping (_ error: Error) -> Void) {
        let method = "bridge.buildTransactionWithOnePrivateKey('\(privateKey.jsEscaped)', '\(inputsOutputs.jsEscaped)')"
        callJSStrings(method, count: 2, success: { success(($0[0], $0[1])) }, failure: failure)
    }

    /// Multisig: this cosigner's signatures for every input (cosigner key `multiSigIndex` of the seed, see the bundle).
    public func getSignatureWithSeedHex(seedHex: String, multiSigIndex: Int, inputsOutputs: String, redeemScript: String, success: @escaping (_ signatures: [String]) -> Void, failure: @escaping (_ error: Error) -> Void) {
        let method = "bridge.getSignatureWithSeedHex('\(seedHex.jsEscaped)', '\(multiSigIndex)', '\(inputsOutputs.jsEscaped)', '\(redeemScript.jsEscaped)')"
        callJSStringArray(method, success: success, failure: failure)
    }

    /// Multisig: the cosigner private key of the seed at `index`.
    public func getPrivatekeyFromSeedHex(_ seedHex: String, index: Int = 0, success: @escaping (_ privateKey: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callJSNonEmptyString("bridge.getPrivkeyFromSeedHex('\(seedHex.jsEscaped)', \(index))", success: success, failure: failure)
    }

    // MARK: - Keys

    public func getPublicKeyAndAddress(from privateKey: String, success: @escaping (_ publicKey: String, _ address: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callJSStrings("bridge.getPublicKeyAndArressFromPrivateKey('\(privateKey.jsEscaped)')", count: 2, success: { success($0[0], $0[1]) }, failure: failure)
    }

    /// Private-key import: public key, legacy (1…), P2SH-SegWit (3…) and native SegWit (bc1…) addresses.
    public func getPublicKeyAndAddressForAll(from privateKey: String, success: @escaping (_ publicKey: String, _ address: String, _ address3: String, _ addressbc1: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callJSStrings("bridge.getPublicKeyAndArressFromPrivateKeyForAll('\(privateKey.jsEscaped)')", count: 4, success: { r in
            success(r[0], r[1], r[2], r[3])
        }, failure: failure)
    }

    /// Private-key export: WIF of receive (isChange false) / change address `index`, BIP44.
    public func getWIFFromSeedHex(_ seedHex: String, seedTypePath: String, index: Int, isChange: Bool, success: @escaping (_ multiSigAddress: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callJSNonEmptyString("bridge.getWIFFromSeedHex('\(seedHex.jsEscaped)', \"\(seedTypePath.jsEscaped)\", \(index), \(isChange))", success: success, failure: failure)
    }

    /// Same for BIP49 (P2SH-SegWit).
    public func getWIFFromSeedHexForBIP49(_ seedHex: String, seedTypePath: String, index: Int, isChange: Bool, success: @escaping (_ multiSigAddress: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callJSNonEmptyString("bridge.getWIFFromSeedHexForBIP49('\(seedHex.jsEscaped)', \"\(seedTypePath.jsEscaped)\", \(index), \(isChange))", success: success, failure: failure)
    }

    /// Same for BIP84 (native SegWit).
    public func getWIFFromSeedHexForBIP84(_ seedHex: String, seedTypePath: String, index: Int, isChange: Bool, success: @escaping (_ multiSigAddress: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callJSNonEmptyString("bridge.getWIFFromSeedHexForBIP84('\(seedHex.jsEscaped)', \"\(seedTypePath.jsEscaped)\", \(index), \(isChange))", success: success, failure: failure)
    }

    /// privateKey: WIF or hex → (isWIF, privateKey).
    public func getPrivKeyInfoFromPrivateKey(_ privateKey: String, success: @escaping (_ isWIF: Bool, _ privateKey: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callJS(method: "bridge.getPrivKeyInfoFromPrivKey('\(privateKey.jsEscaped)')", success: { result in
            guard let arr = result.toArray(), arr.count >= 2, let a = arr[0] as? Bool, let b = arr[1] as? String else {
                failure(JSError.resultError)
                return
            }
            success(a, b)
        }, failure: failure)
    }

    public func getAddress(from publicKey: String, success: @escaping (String) -> Void, failure: @escaping (Error) -> Void) {
        callJSNonEmptyString("bridge.getAddressFromPublicKey('\(publicKey.jsEscaped)')", success: success, failure: failure)
    }

    public func getPrivkeyFromWIF(wif: String, success: @escaping (String) -> Void, failure: @escaping (Error) -> Void) {
        callJSNonEmptyString("bridge.getPrivkeyFromWIF('\(wif.jsEscaped)')", success: success, failure: failure)
    }

    /// LTC: P2SH address with the old 3… version byte → the M… form.
    public func address3ToM(address: String, success: @escaping (String) -> Void, failure: @escaping (Error) -> Void) {
        callJSNonEmptyString("bridge.address3ToM('\(address.jsEscaped)')", success: success, failure: failure)
    }

    // MARK: - Message signing ("Bitcoin Signed Message"; bc1p addresses use BIP-322 in BTCTaprootJSBridge)

    /// The message should be trimmed beforehand. The whole message is escaped as a JS literal, so the bytes signed are the
    /// text shown (escape sequences such as `\x41` are not decoded by JS).
    public func signMessage(wif: String, address: String, message: String, success: @escaping (_ object: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callJSNonEmptyString("bridge.signMessage('\(wif.jsEscaped)', '\(address.jsEscaped)', \"\(message.jsEscaped)\")", success: success, failure: failure)
    }

    public func verifyMessageSignature(message: String, address: String, signature: String, success: @escaping (_ object: Bool) -> Void, failure: @escaping (_ error: Error) -> Void) {
        let method = "bridge.verifyMessageSignature(\"\(message.jsEscaped)\", '\(address.jsEscaped)', '\(signature.jsEscaped)')"
        callJS(method: method, success: { result in
            success(result.toBool())
        }, failure: failure)
    }
}
