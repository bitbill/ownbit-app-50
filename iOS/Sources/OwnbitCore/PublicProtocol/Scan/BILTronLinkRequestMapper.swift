//  BILTronLinkRequestMapper.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Public protocol (cold signer) — a TronLink request → the engine-native TRON request. Port of Android
//  `core/publicsigner/.../sign/TronLinkRequestMapper.kt` (R4 §11). The same code maps a scan, a paste and the verifier's
//  re-check of `transport.payloadBytes`, so what the engine reviews is bound to what was scanned:
//
//    transaction  {"chain":"tron","address":A,"kind":"transaction","transaction":{"raw_data_hex":R[,"signature":[…]]},
//                  "transport":{"type":"tronlink","payloadEncoding":"tronlink-json","payloadBytes":hex(bean),"tronlinkType":T}}
//    message      {"chain":"tron","address":A,"kind":"message","message":M,"encoding":"utf8"|"hex","transport":{…}}
//
//  (`R` = `raw_data` of the one strict `Transaction` in `hexList`; `bean` = `BILTronLinkRequest.bean` re-serialized
//  compactly — byte-identical to Android, it enters `requestHash`.) Refused before the engine (`BILOtherWalletRequestError`,
//  product decisions R2-7), checks in Android's order: shielded → raw hash → v1 message → several entries → address →
//  message / transaction rules; `type` 99 ⇔ the exact ownership placeholder. Pure; nothing is logged.
//

import Foundation

enum BILTronLinkRequestMapper {

    static let transportType = "tronlink"
    static let payloadEncoding = "tronlink-json"
    /// TronLink's ownership check ("Pair cold wallet").
    static let typeOwnership = 99

    /// The placeholder names TronLink signs for its ownership check (iOS / Android builds); the engine's Ownbit edition
    /// recognises exactly these bytes.
    static let ownershipProofNames = ["TronLinkCustomContract", "ColdWalletOwnerVerifyContract"]

    /// The engine-native request of `request` (see the file comment); throws `BILOtherWalletRequestError`.
    static func map(_ request: BILTronLinkRequest) throws -> BILJSONObject {
        let type = request.type
        if type == typeShielded || !(request.alpha ?? "").isEmpty || !(request.tokenId ?? "").isEmpty {
            throw refused("PublicProtocol.err.tronlinkShielded", "TRONLINK_SHIELDED")
        }
        if type == typeTip712Hash || type == typeRawHash {
            throw refused("PublicProtocol.err.tronlinkBlindHash", "TRONLINK_BLIND_HASH")
        }
        if type == typeMessageV1 {
            throw refused("PublicProtocol.err.tronlinkMessageV1", "TRONLINK_MESSAGE_V1")
        }
        if request.hexList.count > 1 {
            throw refused("PublicProtocol.err.tronlinkMulti", "TRONLINK_MULTI", args: [.int(request.hexList.count)])
        }
        guard let address = request.address, isTronAddress(address) else { throw BILOtherWalletRequestError.malformed() }
        guard request.hexList.count == 1 else { throw BILOtherWalletRequestError.malformed() }
        let entry = request.hexList[0]
        let payloadBytes = BILPublicHex.encode(Array(BILStrictJSON.serialize(request.bean).utf8))

        if type == typeMessageText || type == typeMessageHex || type == typeMessageBytes {
            let (message, encoding) = try self.message(type, entry)
            return BILJSONObject([
                ("chain", .string("tron")),
                ("address", .string(address)),
                ("kind", .string("message")),
                ("message", .string(message)),
                ("encoding", .string(encoding)),
                ("transport", .object(transport(payloadBytes, type))),
            ])
        }
        // TronLink's transaction pages are types 0…99; an unknown type above 99 whose entry is not a transaction is a
        // page Ownbit does not know: say so with its number.
        let notTransaction: BILOtherWalletRequestError = type > typeOwnership
            ? refused("PublicProtocol.err.tronlinkType", "TRONLINK_TYPE", args: [.int(type)])
            : BILOtherWalletRequestError.malformed()
        guard let tx = entryBytes(entry), let split = BILTronTransactionProto.split(tx) else { throw notTransaction }
        let proof = ownershipProofName(split.raw) != nil
        if proof != (type == typeOwnership) {
            throw BILOtherWalletRequestError(kind: .malformed, error: BILPublicSignError("PublicProtocol.err.integrity", code: "INTEGRITY"))
        }
        var transaction = BILJSONObject([("raw_data_hex", .string(BILPublicHex.encode(split.raw)))])
        if !split.signatures.isEmpty {
            transaction.set("signature", .array(split.signatures.map { BILJSONValue.string(BILPublicHex.encode($0)) }))
        }
        return BILJSONObject([
            ("chain", .string("tron")),
            ("address", .string(address)),
            ("kind", .string("transaction")),
            ("transaction", .object(transaction)),
            ("transport", .object(transport(payloadBytes, type))),
        ])
    }

    /// The placeholder name when `raw` is exactly TronLink's ownership placeholder `raw_data = {contract:
    /// [{ContractName: name}]}` (`5a <N+2> 22 <N> name`) for one of `ownershipProofNames`, else nil.
    static func ownershipProofName(_ raw: [UInt8]) -> String? {
        for name in ownershipProofNames {
            let n = Array(name.utf8)
            if raw == [0x5a, UInt8(n.count + 2), 0x22, UInt8(n.count)] + n {
                return name
            }
        }
        return nil
    }

    /// The bytes of a transaction entry: non-empty lower- or upper-case hex of even length (no `0x`, no whitespace),
    /// else nil.
    static func entryBytes(_ entry: String) -> [UInt8]? {
        guard !entry.isEmpty else { return nil }
        return BILPublicHex.decode(entry)
    }

    // MARK: - Private

    private static let typeShielded = 15
    private static let typeTip712Hash = 101
    private static let typeRawHash = 17
    private static let typeMessageV1 = 98
    private static let typeMessageText = 102
    private static let typeMessageHex = 103
    private static let typeMessageBytes = 104

    /// The engine's TRON message limit.
    private static let maxMessageBytes = 8_192

    private static func transport(_ payloadBytes: String, _ type: Int) -> BILJSONObject {
        return BILJSONObject([
            ("type", .string(transportType)),
            ("payloadEncoding", .string(payloadEncoding)),
            ("payloadBytes", .string(payloadBytes)),
            ("tronlinkType", .int(type)),
        ])
    }

    /// (message, engine encoding) of a TIP-191 entry: 102 text (UTF-8, 1…8,192 bytes, not trimmed), 103 hex (`0x` then
    /// `0X` removed, even, ≤ 8,192 bytes, re-encoded lower case), 104 `b1,b2,…` (each Kotlin-trimmed part
    /// `^-?[0-9]{1,3}$` in −128…255, ≤ 8,192 parts).
    private static func message(_ type: Int, _ entry: String) throws -> (String, String) {
        switch type {
        case typeMessageText:
            let bytes = entry.utf8.count
            if bytes == 0 || bytes > maxMessageBytes { throw BILOtherWalletRequestError.malformed() }
            return (entry, "utf8")
        case typeMessageHex:
            var hex = entry
            if BILPublicHex.hasASCIIPrefix(hex, "0x") { hex = String(decoding: hex.utf8.dropFirst(2), as: UTF8.self) }
            if BILPublicHex.hasASCIIPrefix(hex, "0X") { hex = String(decoding: hex.utf8.dropFirst(2), as: UTF8.self) }
            guard let bytes = entryBytes(hex), bytes.count <= maxMessageBytes else { throw BILOtherWalletRequestError.malformed() }
            return (BILPublicHex.encode(bytes), "hex")
        default:
            let parts = BILKotlinText.split(entry, separator: ",")
            if parts.count > maxMessageBytes { throw BILOtherWalletRequestError.malformed() }
            var bytes = [UInt8]()
            bytes.reserveCapacity(parts.count)
            for part in parts {
                guard let v = signedByte(BILKotlinText.trim(part)), v >= -128, v <= 255 else { throw BILOtherWalletRequestError.malformed() }
                bytes.append(UInt8(truncatingIfNeeded: v))
            }
            return (BILPublicHex.encode(bytes), "hex")
        }
    }

    /// `^-?[0-9]{1,3}$` (whole text) as a number, else nil.
    private static func signedByte(_ s: String) -> Int? {
        var u = Array(s.utf8)
        var negative = false
        if let first = u.first, first == 0x2D {
            negative = true
            u.removeFirst()
        }
        guard (1...3).contains(u.count) else { return nil }
        var n = 0
        for c in u {
            guard c >= 0x30 && c <= 0x39 else { return nil }
            n = n * 10 + Int(c - 0x30)
        }
        return negative ? -n : n
    }

    /// 34 characters, `T…`, base58check of 25 bytes with version 0x41 and a valid double-SHA-256 checksum.
    private static func isTronAddress(_ address: String) -> Bool {
        return address.utf16.count == 34 && BILPublicHex.hasASCIIPrefix(address, "T")
            && BILTronAddressCodec.hex41(fromBase58: address) != nil
    }

    private static func refused(_ key: String, _ code: String, args: [BILTextArg] = []) -> BILOtherWalletRequestError {
        return BILOtherWalletRequestError(kind: .unsupported, error: BILPublicSignError(key, args: args, code: code))
    }
}
