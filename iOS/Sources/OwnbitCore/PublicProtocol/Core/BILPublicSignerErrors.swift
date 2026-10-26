//  BILPublicSignerErrors.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Public protocol (cold signer) — engine error codes, plan statuses and the host's own refusals → string keys.
//  Port of Android `core/publicsigner/.../text/PublicSignerErrors.kt` (spec §8.7, R5 §7): every code of the pinned
//  engine's vocabulary maps to a category; an unknown code reads as the generic "cannot be signed" (fail closed, never
//  a guess). The English engine text is secondary detail, never the headline. Comparisons are exact (code units).
//

import Foundation

public enum BILPublicSignerErrors {

    // MARK: - Keys

    private static let p = "PublicProtocol."
    /// Unknown code / generic failure.
    public static let genericKey = "PublicProtocol.match.invalid.body"

    /// Every engine code of `engine_vocabulary.json` (49) + the bridge's own `SIGNING_FAILED` / `UNKNOWN` → its key.
    public static let codes: [String: String] = [
        // The request names something this device does not hold.
        "FINGERPRINT": "PublicProtocol.err.notThisWallet",
        "INDEX": "PublicProtocol.err.notThisWallet",
        "PATH": "PublicProtocol.err.notThisWallet",
        "PROFILE": "PublicProtocol.err.notThisWallet",
        "SIGNER": "PublicProtocol.err.notThisWallet",
        // Network / chain.
        "NETWORK": "PublicProtocol.err.networkUnsupported",
        "CHAIN_ID": "PublicProtocol.err.chainMismatch",
        // Changed between review and signing.
        "INTEGRITY": "PublicProtocol.err.integrity",
        "PLAN": "PublicProtocol.err.integrity",
        "WALLET": "PublicProtocol.err.integrity",
        // Consent.
        "RISK": "PublicProtocol.err.confirmRisk",
        // Specific refusals with their own advice.
        "PREVOUT": "PublicProtocol.err.prevout",
        "SIGHASH": "PublicProtocol.err.sighash",
        "LOOKUP_TABLE": "PublicProtocol.err.lookupTable",
        "SIGNATURE": "PublicProtocol.err.verify",
        // Size.
        "LIMIT": "PublicProtocol.err.tooLarge",
        // Transport / encoding.
        "QR_PROTOCOL": "PublicProtocol.err.qrMalformed",
        "INVALID_REQUEST": "PublicProtocol.err.qrMalformed",
        "ENCODING": "PublicProtocol.err.qrMalformed",
        "TRUNCATED": "PublicProtocol.err.qrMalformed",
        // A scan session that ended (page released, no frame for too long).
        "SCAN": "PublicProtocol.err.scanTimeout",
        // The stored public data of a wallet.
        "PUBLIC_INDEX": "PublicProtocol.err.rebuildPublicData",
        "SEED": "PublicProtocol.err.rebuildPublicData",
        // The engine itself (an operation it does not know, a failure without a code).
        "OPERATION": "PublicProtocol.err.engineUnavailable",
        "SIGNING_FAILED": "PublicProtocol.err.engineUnavailable",
        "UNKNOWN": "PublicProtocol.err.engineUnavailable",
        // Content the offline engine does not sign.
        "ADDRESS": "PublicProtocol.err.unsupported",
        "AMOUNT": "PublicProtocol.err.unsupported",
        "CALLDATA": "PublicProtocol.err.unsupported",
        "CHAIN": "PublicProtocol.err.unsupported",
        "DESCRIPTOR": "PublicProtocol.err.unsupported",
        "ENTROPY": "PublicProtocol.err.unsupported",
        "FEE": "PublicProtocol.err.unsupported",
        "GAS": "PublicProtocol.err.unsupported",
        "INSTRUCTION": "PublicProtocol.err.unsupported",
        "INTEGER": "PublicProtocol.err.unsupported",
        "MESSAGE": "PublicProtocol.err.unsupported",
        "MNEMONIC": "PublicProtocol.err.unsupported",
        "OUTPOINT": "PublicProtocol.err.unsupported",
        "PASSPHRASE": "PublicProtocol.err.unsupported",
        "PERMISSION": "PublicProtocol.err.unsupported",
        "POLICY": "PublicProtocol.err.unsupported",
        "PRECISION": "PublicProtocol.err.unsupported",
        "PROTOBUF": "PublicProtocol.err.unsupported",
        "REQUEST": "PublicProtocol.err.unsupported",
        "RESOURCE": "PublicProtocol.err.unsupported",
        "SAFE_SCHEMA": "PublicProtocol.err.unsupported",
        "TOKEN_METADATA": "PublicProtocol.err.unsupported",
        "TRANSACTION": "PublicProtocol.err.unsupported",
        "TYPED_DATA": "PublicProtocol.err.unsupported",
        "UNSUPPORTED": "PublicProtocol.err.unsupported",
    ]

    // MARK: - Refinement messages (exact engine English)

    /// `UNSUPPORTED` messages of the engine's TRON parser for a contract it does not decode → `err.tronContractUnsupported`.
    public static let tronContractMessages: Set<String> = [
        "Unsupported TRON contract type. Its signed structure cannot be safely parsed.",
        "TRC10 value in a smart contract call is unsupported.",
        "Exactly one TRON contract is supported per transaction.",
    ]

    /// `QR_PROTOCOL` messages that mean "a frame of another code" (engine `QRCollector`) → `err.qrMixed`.
    public static let otherRequestMessages: Set<String> = [
        "Mixed UR fountain sessions",
        "Mixed UR types",
        "Multiple unrelated QR payloads",
        "Multiple static QR payloads",
        "Mixed BBQR encodings or counts",
        "Conflicting BBQR fragment",
    ]

    /// `QR_PROTOCOL` messages that mean "too large" (engine `QR_LIMITS` and payload bounds) → `err.tooLarge`.
    public static let tooLargeMessages: Set<String> = [
        "QR frame size exceeds limits",
        "QR scan memory limit exceeded",
        "Invalid QR frame count",
        "QR payload exceeds supported size",
        "Fountain sequence exceeds limits",
        "BBQR decompressed payload exceeds supported size",
        "File payload exceeds supported size",
        "Too many QR fragments",
        "Too many BBQR fragments",
        "JSON payload too large",
    ]

    /// `QR_PROTOCOL` messages that mean "not a signing request we sign" → `err.unsupportedUr`.
    public static let unsupportedUrMessages: Set<String> = [
        "Unsupported signing UR type",
        "Unsupported signing QR format",
    ]

    /// `SIGNATURE` / `TRANSACTION` messages that mean "already signed" → `err.alreadySigned`.
    public static let alreadySignedMessages: Set<String> = [
        "This wallet has already signed the transaction.",
        "This input already has the signer signature.",
        "This Taproot leaf already has the signer signature.",
        "Taproot key-path signature already exists.",
        "This Solana signer slot is already populated.",
        "Duplicate TRON signer.",
        "EVM transaction is already signed.",
    ]

    // MARK: - Mapping

    /// Android `of(PublicSignerException(code, message))`: the code is sanitized and the message bounded first, then
    /// refinements 1–6 in order, then `category`.
    public static func of(code: String, message: String) -> BILPublicSignError {
        return of(BILPublicSignerRefusal(code: code, engineMessage: message))
    }

    public static func of(_ refusal: BILPublicSignerRefusal) -> BILPublicSignError {
        return BILPublicSignError(refinedKey(refusal.code, refusal.engineMessage),
                                  code: refusal.code, engineMessage: refusal.engineMessage)
    }

    /// The headline key of an engine error code (`NETWORK`, `RISK`, …) or plan status wire (`noMatch`, …).
    /// `ready` and unknown values → "PublicProtocol.match.invalid.body".
    public static func category(_ codeOrStatus: String) -> String {
        guard isASCII(codeOrStatus) else { return genericKey }
        if nonReadyStatuses.contains(codeOrStatus) {
            return statusTitleKey(codeOrStatus)
        }
        if codeOrStatus == readyStatus {
            return genericKey
        }
        return codes[codeOrStatus] ?? genericKey
    }

    /// `PublicProtocol.match.<status>` for the five non-ready statuses; `ready` / unknown → `PublicProtocol.match.invalid`.
    public static func statusTitleKey(_ statusWire: String) -> String {
        guard isASCII(statusWire), nonReadyStatuses.contains(statusWire) else { return p + "match.invalid" }
        return p + "match." + statusWire
    }

    /// `PublicProtocol.match.<status>.body`; `ready` / `invalid` / unknown → `PublicProtocol.match.invalid.body`.
    public static func statusBodyKey(_ statusWire: String) -> String {
        guard isASCII(statusWire), nonReadyStatuses.contains(statusWire) else { return genericKey }
        return p + "match." + statusWire + ".body"
    }

    /// Native verifier reasons: INTEGRITY → err.integrity, CHAIN_MISMATCH → err.chainMismatch, LOOKUP_TABLE →
    /// err.lookupTable, VERIFY → err.verify; anything else → the generic text (fail closed).
    public static func verifierKey(_ reason: String) -> String {
        guard isASCII(reason) else { return genericKey }
        switch reason {
        case "INTEGRITY": return p + "err.integrity"
        case "CHAIN_MISMATCH": return p + "err.chainMismatch"
        case "LOOKUP_TABLE": return p + "err.lookupTable"
        case "VERIFY": return p + "err.verify"
        default: return genericKey
        }
    }

    // MARK: - Prebuilt host errors

    public static var engineUnavailable: BILPublicSignError {
        return BILPublicSignError(p + "err.engineUnavailable")
    }

    public static var noWallet: BILPublicSignError {
        return BILPublicSignError(p + "err.noWallet", code: "NO_WALLET")
    }

    public static var tooManyWallets: BILPublicSignError {
        return BILPublicSignError(p + "err.tooManyWallets", code: "TOO_MANY_WALLETS")
    }

    /// The one refusal of every TokenPocket text (owner 2026-10-13).
    public static var tpUnsupported: BILPublicSignError {
        return BILPublicSignError(p + "err.tpUnsupported", code: "TP_UNSUPPORTED")
    }

    /// Any unexpected failure: "This request cannot be signed. Nothing has been signed."
    public static var unexpected: BILPublicSignError {
        return BILPublicSignError(genericKey, code: "UNEXPECTED")
    }

    /// `inputNumber` is 1-based (Android `conflicts.min() + 1`).
    public static func prevoutConflict(inputNumber: Int) -> BILPublicSignError {
        return BILPublicSignError(p + "err.prevoutConflict", args: [.int(inputNumber)], code: "PREVOUT_CONFLICT")
    }

    /// The TRON account (base58) the transaction operates is not this wallet's address.
    public static func tronOwner(_ base58: String) -> BILPublicSignError {
        return BILPublicSignError(p + "err.tronOwner", args: [.text(base58)], code: "TRON_OWNER")
    }

    // MARK: - Private

    private static let readyStatus = "ready"
    private static let nonReadyStatuses: Set<String> = ["noMatch", "missingSigner", "ambiguous", "setupRequired", "invalid"]

    private static func refinedKey(_ code: String, _ message: String) -> String {
        if code == "UNSUPPORTED" && containsExactly(tronContractMessages, message) {
            return p + "err.tronContractUnsupported"
        }
        if code == "QR_PROTOCOL" && containsExactly(otherRequestMessages, message) {
            return p + "err.qrMixed"
        }
        if code == "QR_PROTOCOL" && containsExactly(tooLargeMessages, message) {
            return p + "err.tooLarge"
        }
        if code == "QR_PROTOCOL" && containsExactly(unsupportedUrMessages, message) {
            return p + "err.unsupportedUr"
        }
        if (code == "SIGNATURE" || code == "TRANSACTION") && containsExactly(alreadySignedMessages, message) {
            return p + "err.alreadySigned"
        }
        return category(code)
    }

    /// Exact (code-unit) membership; Swift `Set.contains` would also accept canonically equivalent text.
    private static func containsExactly(_ set: Set<String>, _ message: String) -> Bool {
        return set.contains { BILJSONExact.equal($0, message) }
    }

    /// ASCII text can only be canonically equivalent to itself, so dictionary / set lookups on it are exact.
    private static func isASCII(_ s: String) -> Bool {
        return s.utf8.allSatisfy { $0 < 0x80 }
    }
}
