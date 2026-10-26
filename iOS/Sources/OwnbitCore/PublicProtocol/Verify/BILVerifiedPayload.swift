//  BILVerifiedPayload.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Public protocol (cold signer) — what the native pre-check decoded, with code independent of the engine, from the
//  **original QR bytes** a ready plan commits to (`transport.payloadBytes`): the facts the policy, the D43 card and the
//  post-check use (port of Android `PS:verify/PublicSignVerifier.kt` `VerifiedPayload`, :41-111; R5 §3.1). Also the
//  verify error (`PublicVerifyException` / `verifyCheck`, `PS:verify/SignatureUrCodec.kt:12-16`) and two small text
//  helpers shared by the Verify decoders. Public data only. Pure Foundation (macOS harness: tests/verify/).
//
//  Nothing here logs. Descriptions name only the kind and sizes (never bytes, addresses, amounts or keys), like
//  Android's `toString()` overrides.
//

import Foundation

/// A public-protocol payload that is not what it must be (C-RESP-2 / C-RESP-3, S §2.6; Android `PublicVerifyException`).
/// `what` names the check that failed — never a payload, key, address, amount or signature — so it may be logged.
/// Callers treat it as an integrity failure: nothing is shown as signed, nothing is returned.
struct BILVerifyError: Error, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    let what: String

    var description: String { return "Public protocol check failed: " + what }
    var debugDescription: String { return description }
}

extension BILVerifyError {
    init(_ what: String) {
        self.init(what: what)
    }

    /// Android `verifyCheck(condition) { what }`: throws `BILVerifyError(what)` when `condition` is false.
    static func check(_ condition: Bool, _ what: @autoclosure () -> String) throws {
        if !condition { throw BILVerifyError(what: what()) }
    }
}

/// Text helpers of the Verify decoders (exact, Android-compatible comparisons; strict UTF-8).
enum BILVerifyText {

    /// Strict UTF-8 (Java `CharsetDecoder` with `CodingErrorAction.REPORT`): nil for any malformed sequence (overlong
    /// forms, encoded surrogates, values above U+10FFFF, truncation). A BOM is kept as U+FEFF, as Java does.
    static func strictUTF8(_ bytes: [UInt8]) -> String? {
        let text = String(decoding: bytes, as: UTF8.self)
        // Every malformed sequence decodes to U+FFFD (EF BF BD), which never re-encodes to the original bytes.
        return text.utf8.elementsEqual(bytes) ? text : nil
    }

    /// ASCII-only case folding: equal UTF-16 lengths, each unit equal or equal after folding `A-Z` to `a-z`. Equal to
    /// Kotlin `String.equals(other, ignoreCase = true)` whenever one side is hex or `0x` hex (every Android call site:
    /// keys, txIDs, digests, addresses, request hashes — no non-ASCII character matches `0-9 a-f A-F x X` ignoring case
    /// on the JVM). **Not** a general replacement: for other text Java also folds a few non-ASCII characters to ASCII
    /// letters (`"k".equals("\u{212A}", ignoreCase = true)` is true there, false here).
    static func equalsIgnoringCase(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf16)
        let y = Array(b.utf16)
        guard x.count == y.count else { return false }
        for i in 0..<x.count where x[i] != y[i] {
            if foldASCII(x[i]) != foldASCII(y[i]) { return false }
        }
        return true
    }

    /// Exact code-unit equality (never Swift's canonical equivalence: `"\u{212A}" == "K"` is true in Swift).
    static func same(_ a: String, _ b: String) -> Bool {
        return a.utf8.elementsEqual(b.utf8)
    }

    private static func foldASCII(_ u: UInt16) -> UInt16 {
        return (u >= 0x41 && u <= 0x5A) ? u + 0x20 : u
    }
}

/// The pre-check's decode of the original QR bytes (Android `VerifiedPayload`). Produced only by
/// `BILPublicSignVerifier.pre` (WP13); consumed by the policy, the D43 inputs and the post-check.
public enum BILVerifiedPayload: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// EVM `eth-sign-request` dataType 1 / 4: `signData` decodes to `tx`; `keccak256(signData)` is the plan's digest.
    case evmTransaction(signData: [UInt8], tx: BILUnsignedEvmTx)
    /// EVM dataType 3 (`personal_sign`): the exact message bytes; the EIP-191 digest is the plan's.
    case evmPersonal([UInt8])
    /// EVM dataType 2 (EIP-712 v4): `json` = the exact UTF-8 text of the QR; `domainChainId` = `domain.chainId` as an
    /// exact decimal integer text (Android `BigInteger`; `"0x…"` strings converted, `1.0` → "1", `1.5` → nil) when the
    /// domain has one. The digest is the engine's (no native EIP-712 hasher; documented C-GEN-4 gap).
    case evmTypedData(json: String, domainChainId: String?, hasDomainChainId: Bool)
    /// TRON dataType 1 and TronLink transactions: `raw` = `raw_data` protobuf (`sha256(raw)` = txID = the plan's digest);
    /// one contract of `contractType` owned by `ownerHex41` (`41…`, lower case). `txProto` = the whole TronLink
    /// `Transaction` protobuf (raw + existing signatures), which its answer extends; nil for UR requests.
    case tronTransaction(raw: [UInt8], decoded: BILTronRawData, ownerHex41: String, contractType: Int, txProto: [UInt8]?)
    /// TronLink's ownership check (type 99): `raw` is exactly the fixed placeholder `{contract: [{ContractName: name}]}`;
    /// `ownerHex41` the address it proves; `txProto` the `Transaction` the answer extends.
    case tronOwnershipProof(raw: [UInt8], name: String, ownerHex41: String, txProto: [UInt8])
    /// TRON dataType 2 (TIP-191; TronLink types 102–104): the exact message bytes.
    case tronMessage([UInt8])
    /// Solana signType 1: the message bytes and their parsed header; the task key holds required slot `signerSlot`.
    case solanaTransaction(bytes: [UInt8], header: BILSolanaMessageHeader, signerSlot: Int)
    /// Solana signType 2: an off-chain text message (C-SOL-6).
    case solanaMessage([UInt8])
    /// A PSBT and its parsed maps; `sha256(unsigned tx)` is the plan's digest. `witnessOnlyInputs`: the SegWit v0 inputs
    /// whose amount comes only from `witnessUtxo` (R2-2) — the signed-outpoint memory must check them.
    case bitcoinPsbt(bytes: [UInt8], maps: BILPsbtMaps, witnessOnlyInputs: [Int])

    /// TRON transaction id (`sha256Hex(raw)`, Android `txId`) of a TRON transaction or ownership proof, else nil.
    public var tronTxId: String? {
        switch self {
        case .tronTransaction(let raw, _, _, _, _), .tronOwnershipProof(let raw, _, _, _):
            return BILPublicHash.sha256Hex(raw)
        default:
            return nil
        }
    }

    /// Kind and sizes only (Android `toString()`), never content.
    public var description: String {
        switch self {
        case .evmTransaction(_, let tx): return "EvmTransaction(type \(tx.type))"
        case .evmPersonal(let m): return "EvmPersonal(\(m.count) bytes)"
        case .evmTypedData(let json, _, let has): return "EvmTypedData(\(json.utf16.count) chars, chainId=\(has))"
        case .tronTransaction(_, _, _, let type, _): return "TronTransaction(type=\(type))"
        case .tronOwnershipProof: return "TronOwnershipProof"
        case .tronMessage(let m): return "TronMessage(\(m.count) bytes)"
        case .solanaTransaction(_, let header, _): return "SolanaTransaction(\(header))"
        case .solanaMessage(let b): return "SolanaMessage(\(b.count) bytes)"
        case .bitcoinPsbt(_, let maps, let witnessOnly): return "BitcoinPsbt(\(maps), witnessOnly=\(witnessOnly.count))"
        }
    }

    public var debugDescription: String { return description }

    /// No children: `dump` / reflection print the description only.
    public var customMirror: Mirror { return Mirror(self, children: [:]) }
}
