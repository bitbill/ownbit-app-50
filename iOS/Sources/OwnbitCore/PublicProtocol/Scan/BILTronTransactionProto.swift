//  BILTronTransactionProto.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Public protocol (cold signer) — the outer `protocol.Transaction` protobuf of TRON, read and written **strictly** (the
//  TronLink cold-wallet format). Port of Android `core/chain/.../tron/TronTransactionProto.kt` (R4 §12). A TronLink request
//  carries each transaction as the hex of a full `Transaction` (`0a <len> raw_data [12 41 <65-byte signature>]*`); the
//  answer is the same bytes plus one appended signature.
//
//  `split` accepts exactly: field 1 (`raw_data`, 1…65,536 bytes) once and first, then only field 2 (`signature`, 65 bytes
//  each, at most 32), minimal length varints, nothing else and nothing after; it re-encodes what it read and requires byte
//  equality. Anything else — an unknown field (`ret` = 5 …), a second field 1, a signature of another length, a
//  non-minimal length — is nil, so what Ownbit signs (`sha256(raw_data)`) and answers can never differ from what another
//  parser reads. Pure Swift; no signing; nothing is logged.
//

import Foundation

enum BILTronTransactionProto {

    /// Largest `raw_data` (the engine's `hexToBytes(raw_data_hex, 65536)`).
    static let maxRawBytes = 65_536
    /// Most signatures a transaction may already carry.
    static let maxSignatures = 32
    /// Length of one TRON signature: `r(32) ‖ s(32) ‖ recId(1)`.
    static let signatureBytes = 65

    /// A `Transaction` split into its signed `raw` bytes and its existing `signatures` (each 65 bytes).
    struct Split: Equatable, CustomStringConvertible, CustomReflectable {
        let raw: [UInt8]
        let signatures: [[UInt8]]

        /// Sizes only.
        var description: String {
            return "BILTronTransactionProto.Split(raw: \(raw.count) bytes, signatures: \(signatures.count))"
        }

        /// No children: `dump` / `Mirror` show no raw or signature bytes.
        var customMirror: Mirror {
            return Mirror(self, children: [:])
        }
    }

    /// `tx` split strictly (see the file comment), or nil.
    static func split(_ tx: [UInt8]) -> Split? {
        guard !tx.isEmpty, tx[0] == tagRaw else { return nil }
        guard let (rawLength, afterRaw) = readLength(tx, at: 1) else { return nil }
        if rawLength < 1 || rawLength > maxRawBytes || afterRaw + rawLength > tx.count { return nil }
        let raw = Array(tx[afterRaw..<(afterRaw + rawLength)])
        var pos = afterRaw + rawLength
        var signatures = [[UInt8]]()
        while pos < tx.count {
            if tx[pos] != tagSignature { return nil }
            guard let (length, after) = readLength(tx, at: pos + 1) else { return nil }
            if length != signatureBytes || after + length > tx.count { return nil }
            signatures.append(Array(tx[after..<(after + length)]))
            if signatures.count > maxSignatures { return nil }
            pos = after + length
        }
        // Canonical only: what was read re-encodes to exactly the same bytes.
        guard let again = encode(raw: raw, signatures: signatures), again == tx else { return nil }
        return Split(raw: raw, signatures: signatures)
    }

    /// The `Transaction` bytes of `raw` and `signatures` (field 1, then one field 2 per signature), or nil unless `raw` is
    /// 1…65,536 bytes and there are at most 33 signatures of 65 bytes each (Android `require`).
    static func encode(raw: [UInt8], signatures: [[UInt8]]) -> [UInt8]? {
        guard !raw.isEmpty, raw.count <= maxRawBytes, signatures.count <= maxSignatures + 1,
              signatures.allSatisfy({ $0.count == signatureBytes }) else { return nil }
        var out = [UInt8]()
        out.reserveCapacity(raw.count + 8 + signatures.count * (signatureBytes + 2))
        out.append(tagRaw)
        writeLength(&out, raw.count)
        out.append(contentsOf: raw)
        for signature in signatures {
            out.append(tagSignature)
            writeLength(&out, signature.count)
            out.append(contentsOf: signature)
        }
        return out
    }

    /// `tx` (a strict `Transaction`) with `sig` (65 bytes) appended as one more field 2: exactly `tx ‖ 12 41 ‖ sig`
    /// (TronLink's `addSignature`); nil when `tx` is not strict or `sig` is not 65 bytes.
    static func appendSignature(_ tx: [UInt8], _ sig: [UInt8]) -> [UInt8]? {
        guard let s = split(tx), sig.count == signatureBytes else { return nil }
        return encode(raw: s.raw, signatures: s.signatures + [sig])
    }

    // MARK: - Private

    private static let tagRaw: UInt8 = 0x0a
    private static let tagSignature: UInt8 = 0x12

    /// A minimal (canonical) protobuf length varint at `at`: (value, next position); nil when absent, longer than 5
    /// bytes, not minimal (a multi-byte varint never ends with 0x00) or above `Int32.max`.
    private static func readLength(_ bytes: [UInt8], at: Int) -> (Int, Int)? {
        var value: Int64 = 0
        var shift: Int64 = 0
        var pos = at
        while true {
            if pos >= bytes.count || shift > 28 { return nil }
            let b = bytes[pos]
            pos += 1
            value |= Int64(b & 0x7f) << shift
            if b & 0x80 == 0 {
                if pos - at > 1 && b == 0 { return nil }
                break
            }
            shift += 7
        }
        if value > Int64(Int32.max) { return nil }
        return (Int(value), pos)
    }

    private static func writeLength(_ out: inout [UInt8], _ length: Int) {
        var v = length
        while v >= 0x80 {
            out.append(UInt8((v & 0x7f) | 0x80))
            v >>= 7
        }
        out.append(UInt8(v))
    }
}
