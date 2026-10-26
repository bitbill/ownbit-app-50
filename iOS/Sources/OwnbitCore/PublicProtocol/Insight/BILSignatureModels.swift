//  BILSignatureModels.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  The data model of the app's Security Center signature interpretation (the "D43 card"; app file
//  `Modules/SecurityCenter/Signing/BILSignatureModels.swift`, comments translated). The public-protocol coordinator builds
//  a `BILSignatureRequest` from the natively verified signed bytes (`BILPublicSignInsight`), hands it to the host's
//  interpreter (`BILPublicSignCoordinator.Dependencies.interpret`) and takes the page risk from the returned
//  `BILSignatureInsight` (`BILPublicSignPolicy`). The interpreter itself and its known-contract library are app code and
//  not part of this package. Not included either: the WalletConnect sign-page adapter `BILSignatureRequest.fromSignPage`
//  and the history helpers `isApproval` / `isUnlimited`.
//
//  Only local parse results, never a raw payload: the app persists insights in its signing history, so nothing secret
//  may appear here beyond the calldata / message preview (a signing request itself carries no secret; messages are
//  only previewed). Pure Foundation.
//

import Foundation

// MARK: - Request

/// One signing request as the interpreter reads it.
public struct BILSignatureRequest {
    public enum Payload {
        case evmTransaction(from: String?, to: String?, value: String?, data: String?)
        /// As given (hex or text).
        case evmPersonalSign(message: String)
        /// `eth_sign`: usually a 32-byte hash.
        case evmEthSign(data: String)
        /// `eth_signTypedData*`: the typed-data JSON text.
        case evmTypedData(json: String)
        /// A TRON transaction JSON (an outer wrapper is accepted too).
        case tronTransaction(json: String)
        case tronMessage(message: String)
    }

    /// CAIP-2: "eip155:1" / "tron:0x2b6653dc"; "1" / "tron" are accepted too.
    public let chain: String
    /// personal_sign / eth_sendTransaction / tron_signTransaction …
    public let method: String
    public let payload: Payload
    public let dappUrl: String?
    /// The signing account (EVM 0x… / TRON T…); an EVM transaction defaults to `from`.
    public let account: String?

    public init(chain: String, method: String, payload: Payload, dappUrl: String? = nil, account: String? = nil) {
        self.chain = chain
        self.method = method
        self.payload = payload
        self.dappUrl = dappUrl
        self.account = account
    }
}

// MARK: - Risk

public enum BILSignatureRisk: String, Codable, Comparable, CaseIterable {
    case low, medium, high, critical

    public var rank: Int {
        switch self {
        case .low: return 0
        case .medium: return 1
        case .high: return 2
        case .critical: return 3
        }
    }

    public static func < (lhs: BILSignatureRisk, rhs: BILSignatureRisk) -> Bool { lhs.rank < rhs.rank }

    /// The risk pill text.
    public var label: BILSCText {
        switch self {
        case .low: return BILSCText("SecurityCenter.sig_risk_low")
        case .medium: return BILSCText("SecurityCenter.sig_risk_medium")
        case .high: return BILSCText("SecurityCenter.sig_risk_high")
        case .critical: return BILSCText("SecurityCenter.sig_risk_critical")
        }
    }
}

// MARK: - Contract / facts

/// A contract reference: `address` in display form (EVM EIP-55 or lower case, TRON base58); `known*` come from the local
/// known-contract library.
public struct BILContractRef: Codable, Hashable {
    public let address: String
    /// The normalized chain: "eip155:1" / "tron".
    public let chain: String
    /// spender / operator / token / target / verifyingContract / recipient …
    public let role: String
    public let knownName: String?
    public let knownProtocol: String?
    public let knownCategory: String?

    public init(address: String, chain: String, role: String, knownName: String? = nil, knownProtocol: String? = nil, knownCategory: String? = nil) {
        self.address = address
        self.chain = chain
        self.role = role
        self.knownName = knownName
        self.knownProtocol = knownProtocol
        self.knownCategory = knownCategory
    }

    /// Found in the known-contract library → yellow notice; otherwise red.
    public var isKnown: Bool { (knownName ?? "").isEmpty == false }
}

public struct BILSignatureFact: Codable {
    public enum Kind: String, Codable { case text, address, amount, date, code }

    public let label: BILSCText
    /// The raw display value: amount = "1.5 USDC" (POSIX decimal, no grouping); date = unix seconds; address = display
    /// form; anything else as is.
    public let value: String
    public let kind: Kind
    public let contract: BILContractRef?
    /// A note ("unlimited", "expired", "this is your address", "raw units" …) shown under or next to the value.
    public let note: BILSCText?
    /// A value that needs localizing (yes / no, energy / bandwidth, CALL / DELEGATECALL, unlimited USDC …); shown instead
    /// of `value` when present.
    public let valueText: BILSCText?
    /// The risk of this row on its own (the UI may color the value by it); nil = normal.
    public let level: BILSignatureRisk?
    /// The raw integer (an amount's smallest unit, a date's seconds), for the "raw data" view.
    public let raw: String?

    public init(label: BILSCText, value: String, kind: Kind, contract: BILContractRef? = nil,
                note: BILSCText? = nil, valueText: BILSCText? = nil, level: BILSignatureRisk? = nil, raw: String? = nil) {
        self.label = label
        self.value = value
        self.kind = kind
        self.contract = contract
        self.note = note
        self.valueText = valueText
        self.level = level
        self.raw = raw
    }
}

/// Step-wise content: batch calls, Universal Router commands, Seaport offer / consideration lists.
public struct BILSignatureStep: Codable {
    public let title: BILSCText
    public let facts: [BILSignatureFact]
    public let risk: BILSignatureRisk

    public init(title: BILSCText, facts: [BILSignatureFact], risk: BILSignatureRisk) {
        self.title = title
        self.facts = facts
        self.risk = risk
    }
}

// MARK: - Insight

/// The interpreter's reading of one request.
public struct BILSignatureInsight: Codable {
    /// `BILSignatureKind.rawValue`.
    public let kind: String
    public let risk: BILSignatureRisk
    /// E.g. "Token approval · unlimited".
    public let title: BILSCText
    /// One or two plain sentences.
    public let summary: BILSCText
    public let facts: [BILSignatureFact]
    public let warnings: [BILSCText]
    /// The main counterparty contract; nil = no yellow / red contract notice.
    public let contract: BILContractRef?
    /// The explanation page's paragraphs: what this is / what signing does / what to check.
    public let explain: [BILSCText]
    /// "EIP-2612" / "Permit2" / "EIP-4361" / "ERC-20" …
    public let standard: String?
    public let functionSignature: String?
    public let steps: [BILSignatureStep]?

    public init(kind: String, risk: BILSignatureRisk, title: BILSCText, summary: BILSCText, facts: [BILSignatureFact],
                warnings: [BILSCText], contract: BILContractRef?, explain: [BILSCText], standard: String?,
                functionSignature: String?, steps: [BILSignatureStep]?) {
        self.kind = kind
        self.risk = risk
        self.title = title
        self.summary = summary
        self.facts = facts
        self.warnings = warnings
        self.contract = contract
        self.explain = explain
        self.standard = standard
        self.functionSignature = functionSignature
        self.steps = steps
    }

    public var kindValue: BILSignatureKind? { BILSignatureKind(rawValue: kind) }
}

/// The values of `BILSignatureInsight.kind` (the UI picks its icon by it).
public enum BILSignatureKind: String, CaseIterable {
    // Approvals
    /// ERC-20 / TRC-20 approve, increaseAllowance, on-chain permit, Permit2 approve.
    case approve
    /// Allowance set to zero / revoked / decreased.
    case revoke
    /// setApprovalForAll(true).
    case nftApproveAll
    /// ERC-777 operator, Compound allow, Aave credit delegation.
    case delegation
    /// EIP-2612 / DAI / NFT permit (off-chain signature).
    case permit
    /// Permit2 PermitSingle / PermitBatch (off-chain signature).
    case permit2
    /// Permit2 SignatureTransfer (one-time transfer signature).
    case permit2Transfer
    /// EIP-3009 TransferWithAuthorization signature.
    case transferAuthorization
    // Transfers
    /// Native coin transfer (value, no data).
    case transfer
    case tokenTransfer
    case nftTransfer
    // DeFi
    case swap
    /// UniswapX / CoW / 1inch limit-order signature.
    case swapOrder
    /// On-chain order approval (Seaport validate, CoW setPreSignature).
    case orderApproval
    case orderCancel
    case liquidity
    case lending
    case staking
    case unstaking
    case claim
    case wrap
    case bridge
    /// multicall / Multicall3 / smart-account execute / MultiSend.
    case batch
    // Account and contract administration
    case safeTx
    /// Safe owner / module / guard / threshold changes.
    case accountAdmin
    case ownership
    case upgrade
    /// TRON resource delegation.
    case resourceDelegation
    case vote
    /// TRON AccountPermissionUpdate.
    case tronPermission
    // NFT markets
    /// Seaport fulfill (buy / match).
    case nftTrade
    /// Seaport / Blur / LooksRare listing signature.
    case nftListing
    // Structured data / messages
    /// Any other EIP-712.
    case typedData
    case hyperliquid
    /// SIWE.
    case login
    /// Plain text.
    case message
    /// Unreadable binary / hex.
    case rawMessage
    /// A 32-byte hash.
    case blindHash
    case ethSign
    // Fallbacks
    /// Unknown selector.
    case contractCall
    /// Calldata that cannot be parsed.
    case unknownContractCall
    case contractDeploy
    case tronUnknown
}
