//  BILTronRawData.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Public protocol (cold signer) — TRON `protocol.Transaction.raw` (`raw_data`) decoder for the native pre-check
//  (port of Android `A:core/chain/src/main/kotlin/io/ownbit/core/chain/tron/TronRawTransaction.kt` `TronRawData` /
//  `TronContract` / `ProtoReader`, :53-229; R5 §3.6). Independent on purpose: the D43 interpreter's `parseTronRaw`
//  (`Modules/SecurityCenter/Signing/BILSignatureInterpreter+Tron.swift`) is not reused.
//
//  Same leniency as Android's wire reader: varints ≤ 10 bytes (bits beyond 64 dropped), wire types 0 / 1 / 2 / 5,
//  field 0 refused, lengths within bounds, unknown fields ignored, the last occurrence of a field wins. A known field
//  of the wrong wire kind (bytes where a number belongs or the reverse) fails the whole decode, like Android's casts;
//  fixed64 / fixed32 values are accepted where a varint belongs. The contract parameter (`Any.value`) must itself be
//  well-formed protobuf. Owner field: TRANSFER_ASSET (2) field 2, every other type field 1.
//
//  Pure Foundation. Never logs.
//

import Foundation

/// One `protocol.Transaction.Contract` as the verifier needs it (Android `TronContract`, reduced to the fields the
/// policy / D43 inputs read). Absent fields are nil where Android has its defaults (`typeUrl` "", `permissionId` 0,
/// `ownerAddress` "").
public struct BILTronContract: Equatable, CustomStringConvertible, CustomReflectable {
    /// `ContractType` enum value (Kotlin `Long.toInt()`: low 32 bits, signed); 0 when absent.
    public let type: Int
    /// `parameter.type_url` decoded as (lenient) UTF-8 — a BOM is kept, invalid bytes are replaced with U+FFFD, never
    /// refused. For malformed input the number of U+FFFD may differ from Java's decoder (an encoded surrogate lead
    /// `ED A0…BF` gives one per byte here, one per sequence there); no decision ever reads this field.
    public let typeUrl: String?
    /// `parameter.value` (the contract's own protobuf), empty when absent.
    public let value: [UInt8]
    /// `permission_id` (low 32 bits, signed), nil when absent (Android: 0).
    public let permissionId: Int?
    /// Lower-case hex of the owner field (any length; the verifier requires 42 chars starting `41`), nil when the field
    /// is absent or not a byte string (Android: "").
    public let ownerHex41: String?

    public var description: String { return "BILTronContract(type=\(type))" }
    public var customMirror: Mirror { return Mirror(self, children: [:]) }
}

/// `protocol.Transaction.raw` (Android `TronRawData`): the contracts in order and the fields the policy reads.
public struct BILTronRawData: Equatable, CustomStringConvertible, CustomReflectable {
    public let contracts: [BILTronContract]
    /// `fee_limit` (SUN), nil when absent (Android: 0).
    public let feeLimit: Int64?
    /// `data` (the on-chain memo), nil when absent (Android: "").
    public let data: [UInt8]?
    /// `expiration` (epoch ms), nil when absent (Android: 0).
    public let expiration: Int64?

    public var description: String { return "BILTronRawData(\(contracts.count) contracts)" }
    /// No children: `dump` / reflection print the description only.
    public var customMirror: Mirror { return Mirror(self, children: [:]) }

    /// Decodes the protobuf bytes; nil when malformed (Android `decodeOrNull`).
    public static func decode(_ raw: [UInt8]) -> BILTronRawData? {
        do {
            var contracts = [BILTronContract]()
            var feeLimit: Int64? = nil
            var data: [UInt8]? = nil
            var expiration: Int64? = nil
            try BILTronProtoReader.forEachField(raw) { field, value in
                switch field {
                case 1, 4: _ = try value.bytes()              // ref_block_bytes / ref_block_hash
                case 8: expiration = try value.number()
                case 10: data = try value.bytes()
                case 11: contracts.append(try decodeContract(try value.bytes()))
                case 14: _ = try value.number()               // timestamp
                case 18: feeLimit = try value.number()
                default: break
                }
            }
            return BILTronRawData(contracts: contracts, feeLimit: feeLimit, data: data, expiration: expiration)
        } catch {
            return nil
        }
    }

    private static let transferAsset = 2

    private static func decodeContract(_ bytes: [UInt8]) throws -> BILTronContract {
        var type = 0
        var typeUrl: String? = nil
        var value = [UInt8]()
        var permissionId: Int? = nil
        try BILTronProtoReader.forEachField(bytes) { field, v in
            switch field {
            case 1:
                type = Int(Int32(truncatingIfNeeded: try v.number()))
            case 2:
                try BILTronProtoReader.forEachField(try v.bytes()) { f, pv in
                    switch f {
                    case 1: typeUrl = String(decoding: try pv.bytes(), as: UTF8.self)
                    case 2: value = try pv.bytes()
                    default: break
                    }
                }
            case 5:
                permissionId = Int(Int32(truncatingIfNeeded: try v.number()))
            default:
                break
            }
        }
        // Android `decodeParameter`: the parameter must be well-formed protobuf; the owner is read leniently.
        var fields = [Int: BILTronProtoReader.Value]()
        try BILTronProtoReader.forEachField(value) { f, v in fields[f] = v }
        let ownerField = type == transferAsset ? 2 : 1
        var owner: String? = nil
        if case .bytes(let b)? = fields[ownerField] { owner = BILPublicHex.encode(b) }
        return BILTronContract(type: type, typeUrl: typeUrl, value: value, permissionId: permissionId, ownerHex41: owner)
    }
}

/// Minimal protobuf wire-format reader (Android `ProtoReader`): varint / fixed64 / fixed32 as a number (Kotlin `Long`),
/// length-delimited as bytes. File-private (WP10 owns the strict `Transaction` codec).
fileprivate enum BILTronProtoReader {

    enum Value {
        case number(Int64)
        case bytes([UInt8])

        /// Android `value as Long` (throws for a byte string).
        func number() throws -> Int64 {
            guard case .number(let n) = self else { throw BILVerifyError("tron.proto.kind") }
            return n
        }

        /// Android `value as ByteArray` (throws for a number).
        func bytes() throws -> [UInt8] {
            guard case .bytes(let b) = self else { throw BILVerifyError("tron.proto.kind") }
            return b
        }
    }

    /// Calls `body` with (field number, value) for every field in order; throws for a malformed message.
    static func forEachField(_ bytes: [UInt8], _ body: (Int, Value) throws -> Void) throws {
        var pos = 0
        while pos < bytes.count {
            let key = try readVarint(bytes, &pos)
            let field = Int(Int32(truncatingIfNeeded: key >> 3))      // Kotlin `(key ushr 3).toInt()`
            try BILVerifyError.check(field > 0, "tron.proto.field")
            switch key & 7 {
            case 0:
                try body(field, .number(Int64(bitPattern: try readVarint(bytes, &pos))))
            case 1:
                try body(field, .number(try readFixed(bytes, &pos, 8)))
            case 2:
                let len = Int64(bitPattern: try readVarint(bytes, &pos))
                try BILVerifyError.check(len >= 0 && UInt64(len) <= UInt64(bytes.count - pos), "tron.proto.length")
                let end = pos + Int(len)
                let slice = Array(bytes[pos..<end])
                pos = end
                try body(field, .bytes(slice))
            case 5:
                try body(field, .number(try readFixed(bytes, &pos, 4)))
            default:
                throw BILVerifyError("tron.proto.wireType")
            }
        }
    }

    /// Up to 10 bytes (shift < 64); bits shifted beyond 64 are dropped (Kotlin `shl`).
    private static func readVarint(_ bytes: [UInt8], _ pos: inout Int) throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while true {
            try BILVerifyError.check(pos < bytes.count && shift < 64, "tron.proto.varint")
            let b = bytes[pos]
            pos += 1
            result |= UInt64(b & 0x7F) << shift
            if b & 0x80 == 0 { return result }
            shift += 7
        }
    }

    /// Little-endian fixed64 / fixed32 (fixed32 zero-extended).
    private static func readFixed(_ bytes: [UInt8], _ pos: inout Int, _ n: Int) throws -> Int64 {
        try BILVerifyError.check(n <= bytes.count - pos, "tron.proto.fixed")
        var result: UInt64 = 0
        for i in 0..<n { result |= UInt64(bytes[pos + i]) << (8 * UInt64(i)) }
        pos += n
        return Int64(bitPattern: result)
    }
}
