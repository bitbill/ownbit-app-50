//  SolanaJSBridge.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  SOL (+ SPL / Token-2022, Ownbit SOL multisig): address (m/44'/501'/0', ed25519 / SLIP-10), signing transfers and the
//  multisig program's create / propose / approve / execute transactions. The caller supplies the recent blockhash,
//  block height, fee and rent amounts.
//  Bundle: soljs-lib-app.js in a hidden web view (sol_index.html). The bundle's send path is patched to return the
//  serialized signed transaction instead of broadcasting it; results arrive on
//  `window.webkit.messageHandlers.transaction` ("any:<base64 tx>"), `.mstransaction` ("<method>:<base64 tx>[:…]") and
//  `.error`.
//
//  Every bundle function takes an RPC URL first: `SolanaJSBridge.provider` (host-settable; default the loopback
//  `JSBridge.offlineProviderPlaceholder`; the app passed its Solana RPC node). The bundle only constructs a Connection with
//  it: the "send" functions are named after `sendAndConfirmTransaction`, but in the shipped bundle that path is patched to
//  return the signed transaction without fetching a blockhash or submitting anything (blockhash, height, fee and rent
//  come from the caller; token accounts are derived locally), so every function here signs offline with any provider
//  value and the host submits the returned transaction itself, as the app does.
//
//  Differences from the app (no UI in this package): the app called `success("")` right away and delivered the real
//  result to whichever view controller was registered; here `success` is called once with the real result (closure types
//  changed where the result has more than one part).

import Foundation

public final class SolanaJSBridge: JSBridge, JSBridgeValidAddressProtocol {

    public static let shared = SolanaJSBridge()

    override var webPage: Resource? {
        return Resource(name: "sol_index", ext: "html", directory: "soljs-lib-bridge")
    }

    override var webMessageNames: [String] {
        return ["transaction", "mstransaction", "error"]
    }

    /// RPC URL passed as `solanaProvider` to every bundle function (escaped). Not contacted by any function here (see the
    /// file header). If it equals the bundle's own default RPC URL, the bundle reuses one global Connection, whose
    /// signature cache makes signing the very same transaction a second time loop forever; any other value gets a fresh
    /// Connection per call. Never hard-code a server URL in this package.
    public static var provider: String = JSBridge.offlineProviderPlaceholder

    private static var providerArgument: String {
        return "'\(provider.jsEscaped)'"
    }

    /// Splits a message body on ":" and checks the part count (base64 and base58 have no ':').
    private static func parts(_ body: String, count: Int) -> [String]? {
        let parts = body.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        return parts.count == count ? parts : nil
    }

    private func callTransaction(_ method: String, success: @escaping (_ hexTx: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callWebForMessage(method, channels: ["transaction"], success: { _, body in
            guard let p = SolanaJSBridge.parts(body, count: 2) else {
                failure(JSError.resultError)
                return
            }
            success(p[1])
        }, failure: failure)
    }

    /// Waits for an `mstransaction` message "<expectedMethod>:…" with `count` parts.
    private func callMultisig(_ method: String, expect expectedMethod: String, count: Int, success: @escaping (_ parts: [String]) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callWebForMessage(method, channels: ["mstransaction"], success: { _, body in
            guard let p = SolanaJSBridge.parts(body, count: count), p[0] == expectedMethod else {
                failure(JSError.resultError)
                return
            }
            success(p)
        }, failure: failure)
    }

    public func validateAddress(address: String, success: @escaping () -> Void, failure: @escaping (_ error: String) -> Void) {
        callWebValidate("bridge.isValidAddress('\(address.jsEscaped)')", success: success, failure: failure)
    }

    /// m/44'/501'/0' → (public key base58, address); both are the same string, as in the app.
    public func getPublicKeyAndAddress(seed: String, success: @escaping (_ publicKey: String, _ address: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        callWebNonEmptyString("bridge.generateAccount('\(seed.jsEscaped)')", success: { success($0, $0) }, failure: failure)
    }

    /// amount: lamports as a string, e.g. "100000"; fee: micro-lamports per compute unit (0 = none).
    /// success gets the signed transaction (base64).
    public func buildTransaction(seed: String, toAddress: String, amount: String, fee: Int64, recentBlockHash: String, recentBlockHeight: Int64, success: @escaping (_ txHash: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        let method = "bridge.sendTransaction(\(Self.providerArgument), '\(seed.jsEscaped)', '\(toAddress.jsEscaped)', '\(amount.jsEscaped)', \(fee), '\(recentBlockHash.jsEscaped)', \(recentBlockHeight))"
        callTransaction(method, success: success, failure: failure)
    }

    /// amount: token base units as a string. shouldCreateTokenAccount: also create the recipient's associated account.
    /// success gets the signed transaction (base64).
    public func buildTokenTransaction(seed: String, tokenMint: String, token2022: Bool, toAddress: String, amount: String, decimals: Int16, fee: Int64, recentBlockHash: String, recentBlockHeight: Int64, shouldCreateTokenAccount: Bool, success: @escaping (_ txHash: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        let method = "bridge.sendTokenTransaction(\(Self.providerArgument), '\(seed.jsEscaped)', '\(tokenMint.jsEscaped)', \(token2022), '\(toAddress.jsEscaped)', '\(amount.jsEscaped)', \(decimals), \(fee), '\(recentBlockHash.jsEscaped)', \(recentBlockHeight), \(shouldCreateTokenAccount))"
        callTransaction(method, success: success, failure: failure)
    }

    /// Creates an Ownbit SOL multisig (threshold of owners). The multisig key is derived from the seed with a random
    /// index (JS). success: (signed transaction base64, multisig PDA, multisig account, random index).
    /// threshold outside 1...owners.count fails (the app silently returned).
    public func createMultisig(seed: String, owners: [String], threshold: Int16, fee: Int64, recentBlockHash: String, recentBlockHeight: Int64, rentExemption400: Int64, success: @escaping (_ hexTx: String, _ multisigPda: String, _ multisig: String, _ ranInt: Int64) -> Void, failure: @escaping (_ error: Error) -> Void) {
        guard threshold >= 1, threshold <= owners.count else {
            DispatchQueue.main.async { failure(JSError.resultError) }
            return
        }
        let method = "bridge.createMultisig(\(Self.providerArgument), '\(seed.jsEscaped)', \(JSBridge.jsArrayLiteral(owners)), \(threshold),  \(fee), '\(recentBlockHash.jsEscaped)', \(recentBlockHeight), \(rentExemption400))"
        callMultisig(method, expect: "create_multisig", count: 5, success: { p in
            success(p[1], p[2], p[3], Int64(p[4]) ?? 0)
        }, failure: failure)
    }

    /// Proposes a SOL transfer from the multisig. success: (signed transaction base64, proposal transaction account).
    public func createMultisigTransactionForSol(seed: String, multisig: String, toAddress: String, amount: String, fee: Int64, recentBlockHash: String, recentBlockHeight: Int64, rentExemption800: Int64, success: @escaping (_ hexTx: String, _ transactionAccount: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        let method = "bridge.createMultisigTransactionForSol(\(Self.providerArgument), '\(seed.jsEscaped)', '\(multisig.jsEscaped)', '\(toAddress.jsEscaped)', '\(amount.jsEscaped)', \(fee), '\(recentBlockHash.jsEscaped)', \(recentBlockHeight), \(rentExemption800))"
        callMultisig(method, expect: "create_transaction", count: 3, success: { p in success(p[1], p[2]) }, failure: failure)
    }

    /// Proposes a token transfer from the multisig. success: (signed transaction base64, proposal transaction account).
    public func createMultisigTransactionForToken(seed: String, multisig: String, tokenMint: String, token2022: Bool, toAddress: String, amount: String, decimals: Int16, fee: Int64, recentBlockHash: String, recentBlockHeight: Int64, rentExemption800: Int64, success: @escaping (_ hexTx: String, _ transactionAccount: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        let method = "bridge.createMultisigTransactionForToken(\(Self.providerArgument), '\(seed.jsEscaped)', '\(multisig.jsEscaped)', '\(tokenMint.jsEscaped)', \(token2022), '\(toAddress.jsEscaped)', '\(amount.jsEscaped)', \(decimals), \(fee), '\(recentBlockHash.jsEscaped)', \(recentBlockHeight), \(rentExemption800))"
        callMultisig(method, expect: "create_transaction", count: 3, success: { p in success(p[1], p[2]) }, failure: failure)
    }

    /// Approves a proposal. success gets the signed transaction (base64).
    public func approveMultisigTransaction(seed: String, multisig: String, transaction: String, fee: Int64, recentBlockHash: String, recentBlockHeight: Int64, success: @escaping (_ txHash: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        let method = "bridge.approveMultisigTransaction(\(Self.providerArgument), '\(seed.jsEscaped)', '\(multisig.jsEscaped)', '\(transaction.jsEscaped)', \(fee), '\(recentBlockHash.jsEscaped)', \(recentBlockHeight))"
        callMultisig(method, expect: "approve", count: 2, success: { p in success(p[1]) }, failure: failure)
    }

    /// Executes an approved proposal. tokenMint shorter than 10 characters means SOL (the system program ID is passed).
    /// success gets the signed transaction (base64).
    public func executeMultisigTransaction(seed: String, multisig: String, transaction: String, tokenMint: String, token2022: Bool, toAddress: String, shouldCreateTokenAccount: Bool, fee: Int64, recentBlockHash: String, recentBlockHeight: Int64, success: @escaping (_ txHash: String) -> Void, failure: @escaping (_ error: Error) -> Void) {
        var mint = tokenMint
        if mint.count < 10 {
            mint = "11111111111111111111111111111111"
        }
        let method = "bridge.executeMultisigTransaction(\(Self.providerArgument), '\(seed.jsEscaped)', '\(multisig.jsEscaped)', '\(transaction.jsEscaped)', '\(mint.jsEscaped)', \(token2022), '\(toAddress.jsEscaped)', \(shouldCreateTokenAccount), \(fee), '\(recentBlockHash.jsEscaped)', \(recentBlockHeight))"
        callMultisig(method, expect: "execute_transaction", count: 2, success: { p in success(p[1]) }, failure: failure)
    }
}
