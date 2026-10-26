//  BILPublicSignInsight.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Public protocol (cold signer) — the D43 signature card of a public request (product decision 6; spec S§8.5; checklist
//  C-EVM-8; design §3.10, D-41, R5 §5). Port of Android `core/publicsigner/.../insight/PublicSignInsight.kt`
//  (b8c70c25): the **same** reading the WalletConnect sign page gives (`BILSignatureInterpreter` with the local
//  known-contract library — in the app `BILWCInsightSources.interpret`, called by the coordinator on the main thread) fed
//  with what the native pre-check decoded from the **exact signed bytes** (`BILVerifiedPayload`, whose digest the
//  pre-check bound to the plan), never from the engine's text or the request's claims. The card's contract notice
//  (known name = yellow, unknown = red, never green) comes with it.
//
//  Cards: EVM transactions **with calldata** (legacy / EIP-2930 / EIP-1559, contract creation included), EIP-712 typed
//  data, `personal_sign`, and TRON `TriggerSmartContract`. Nothing for plain transfers (no calldata), TRON transfers /
//  staking / TIP-191 messages (the interpreter reads TRON messages with Ownbit's WalletConnect sha256 rule, not
//  TIP-191), Bitcoin or Solana, and nothing for a plan with more than one task. The lookup chain is the request's chain
//  id (EVM: the signed bytes' chain id, equal to the request's after the pre-check; messages: the request's `chainId`,
//  else the domain's, else Ethereum). There is no dApp URL: the request's `origin` is not verified and never used for
//  trust. EVM `value` / `gas` are `0x` hex (`0x0` for zero, Android's form; the interpreter accepts both).
//
//  Never call `BILWCHistoryHooks` / `BILWCSignHistory` for public requests (the offline-sign journal records them).
//  Pure Foundation (+ the pure Security Center D43 models and `BILSignatureInterpreter.printableText`); macOS harness:
//  tests/verifier/. Never logs.
//

import Foundation

enum BILPublicSignInsight {

    /// The interpreter request of a verified single-task plan, the explanation page's raw data and the signing wallet's own
    /// addresses (the card's "you" rule); nil when the request gets no card.
    static func details(request: BILJSONObject, plan: BILPublicPlan, verified: BILVerifiedPayload) -> BILPublicInsightInput? {
        guard plan.tasks.count == 1 else { return nil }
        let task = plan.tasks[0]
        let account: String? = task.addresses.first.flatMap { $0.isEmpty ? nil : $0 }
        let own = task.displayAddresses
        let requestChainId: Int64? = request.long("chainId").flatMap { $0 > 0 ? $0 : nil }
        switch verified {
        case .evmTransaction(_, let tx):
            if tx.data.isEmpty { return nil }
            let value = BILUnsignedEvmTx.quantityHex(tx.value)
            // Keys in sorted order (Android `buildJsonObject` in that order, kotlinx compact text).
            let raw = BILStrictJSON.serialize(BILJSONObject([
                ("chainId", .string(String(tx.chainId))),
                ("data", .string(tx.dataHex)),
                ("from", .string(account ?? "")),
                ("gas", .string(BILUnsignedEvmTx.quantityHex(tx.gasLimit))),
                ("to", .string(tx.to ?? "")),
                ("value", .string(value)),
            ]))
            let signatureRequest = BILSignatureRequest(chain: "eip155:\(tx.chainId)", method: ethSignTransaction,
                                                       payload: .evmTransaction(from: account, to: tx.to, value: value, data: tx.dataHex),
                                                       dappUrl: nil, account: account)
            return BILPublicInsightInput(request: signatureRequest, raw: raw, ownAddresses: own)
        case .evmPersonal(let bytes):
            let message = "0x" + BILPublicHex.encode(bytes)
            let signatureRequest = BILSignatureRequest(chain: "eip155:\(requestChainId ?? ethereum)", method: personalSign,
                                                       payload: .evmPersonalSign(message: message), dappUrl: nil, account: account)
            return BILPublicInsightInput(request: signatureRequest, raw: readableMessage(message), ownAddresses: own)
        case .evmTypedData(let json, let domainChainId, _):
            let domain = domainChainId.flatMap { Int64($0) }.flatMap { $0 > 0 ? $0 : nil }
            let chainId = requestChainId ?? domain ?? ethereum
            let signatureRequest = BILSignatureRequest(chain: "eip155:\(chainId)", method: signTypedDataV4,
                                                       payload: .evmTypedData(json: json), dappUrl: nil, account: account)
            return BILPublicInsightInput(request: signatureRequest, raw: json, ownAddresses: own)
        case .tronTransaction(let raw, _, _, let contractType, _):
            if contractType != triggerSmartContract { return nil }
            let json = BILStrictJSON.serialize(BILJSONObject([
                ("raw_data_hex", .string(BILPublicHex.encode(raw))),
                ("txID", .string(BILPublicHash.sha256Hex(raw))),
            ]))
            let signatureRequest = BILSignatureRequest(chain: tronChain, method: tronSignTransaction,
                                                       payload: .tronTransaction(json: json), dappUrl: nil, account: account)
            return BILPublicInsightInput(request: signatureRequest, raw: json, ownAddresses: own)
        default:
            return nil
        }
    }

    /// The explanation page's text of a `personal_sign` message (Android `SignatureInterpreter.readableMessage(message,
    /// tron = false)`, the iOS WalletConnect page's `wcReadableMessage` rule): `0x` hex that decodes to printable UTF-8
    /// (`BILSignatureInterpreter.printableText`) → that text; anything else — not `0x…`, exactly 32 bytes (a hash), not
    /// hex, not printable — is returned as it is.
    static func readableMessage(_ hex0x: String) -> String {
        let trimmed = hex0x.trimmingCharacters(in: .whitespacesAndNewlines)
        guard BILPublicHex.hasASCIIPrefix(trimmed, "0x"), trimmed.unicodeScalars.count - 2 != 64 else { return hex0x }
        guard let bytes = BILPublicHex.decode(String(decoding: trimmed.utf8.dropFirst(2), as: UTF8.self)) else { return hex0x }
        return BILSignatureInterpreter.printableText(bytes) ?? hex0x
    }

    // MARK: - Private

    private static let ethereum: Int64 = 1
    private static let triggerSmartContract = 31
    private static let tronChain = "tron:0x2b6653dc"
    private static let ethSignTransaction = "eth_signTransaction"
    private static let personalSign = "personal_sign"
    private static let signTypedDataV4 = "eth_signTypedData_v4"
    private static let tronSignTransaction = "tron_signTransaction"
}
