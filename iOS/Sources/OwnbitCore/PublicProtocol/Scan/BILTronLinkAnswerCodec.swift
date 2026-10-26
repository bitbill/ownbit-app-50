//  BILTronLinkAnswerCodec.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Public protocol (cold signer) — Ownbit's answer to a TronLink request, built by the host (the engine's
//  `encodeResponse` has no TronLink profile). Port of Android `core/publicsigner/.../sign/TronLinkAnswerCodec.kt`
//  (R4 §13), byte-exact with the V1 / V3 / V4 vectors:
//
//  - the answer object = the request object (same keys, same order, same literals) with `hexList` replaced by the signed
//    entries (`answerBean`);
//  - a transaction entry = the request's `Transaction` bytes ‖ `12 41` ‖ `r ‖ s ‖ recId` (recId 0 / 1), lower-case hex
//    (`signedTransaction`); a message entry = `"0x" ‖ r ‖ s ‖ v`, v = 27 + recId (`signedMessage`);
//  - one QR when the entries, each followed by `&&&`, are at most 1,000 UTF-16 units (exactly 1,000 stays one QR), else
//    `tN = ⌈len / 1000⌉` numbered parts in TronLink's (Gson) field order `address` (first and last part), `cN`, `hexList`
//    (one 1,000-unit piece; a cut may fall inside `&&&`), `tN`, `type` (the request's on the last part, `0` before).
//
//  `decode` reads frames back with the same parser and collector the scanner uses (the verifier's post-check). Pure;
//  nothing is logged.
//

import Foundation

enum BILTronLinkAnswerCodec {

    /// UTF-16 units of one part's piece (TronLink `QR_LIMIT_SIZE`).
    static let partChars = 1_000

    /// Why `decode` refused the frames (log-safe: names the step only, never content).
    struct DecodeError: Error, Equatable, CustomStringConvertible {
        let what: String
        var description: String {
            return "TronLink answer not readable: " + what
        }
    }

    /// The answer object: `bean` with `hexList` = `signed`, in place (key order and every other value kept). `bean` must be
    /// a TronLink request object (it has `hexList`); otherwise it is returned unchanged (Android refuses it with `require`;
    /// `encode` then returns no frame).
    static func answerBean(_ bean: BILJSONObject, signed: [String]) -> BILJSONObject {
        guard bean.contains(hexListKey) else { return bean }
        var out = bean
        out.set(hexListKey, .array(signed.map { BILJSONValue.string($0) }))
        return out
    }

    /// The QR frames of the answer to `bean` with `signed` entries (see the file comment). Returns `[]` — never a frame —
    /// where Android's `require`s throw: `signed` empty, an entry empty or containing `&&&`, or (one QR) `bean` without
    /// `hexList`.
    static func encode(_ bean: BILJSONObject, signed: [String]) -> [String] {
        guard !signed.isEmpty,
              !signed.contains(where: { $0.isEmpty || BILScanText.contains($0, BILTronLinkCollector.separator) }) else { return [] }
        let joined = signed.map { $0 + BILTronLinkCollector.separator }.joined()
        let units = Array(joined.utf16)
        if units.count <= partChars {
            guard bean.contains(hexListKey) else { return [] }
            return [BILStrictJSON.serialize(answerBean(bean, signed: signed))]
        }
        let address = bean["address"]?.stringValue
        let type = integerType(bean["type"]) ?? 0
        let total = (units.count + partChars - 1) / partChars
        var frames = [String]()
        frames.reserveCapacity(total)
        for i in 1...total {
            // The entries are hex / `0x…` ASCII, so a cut never splits a surrogate pair; any other text would be split
            // by UTF-16 units exactly like Kotlin's `substring`.
            let piece = String(decoding: units[((i - 1) * partChars)..<min(i * partChars, units.count)], as: UTF16.self)
            var part = BILJSONObject()
            if let a = address, i == 1 || i == total { part.set("address", .string(a)) }
            part.set("cN", .int(i))
            part.set(hexListKey, .array([.string(piece)]))
            part.set("tN", .int(total))
            part.set("type", .int(i == total ? type : 0))
            frames.append(BILStrictJSON.serialize(part))
        }
        return frames
    }

    /// `tx ‖ 12 41 ‖ signature` as lower-case hex (`tx` a strict `Transaction`, `signature` 65 bytes), else nil.
    static func signedTransaction(tx: [UInt8], signature: [UInt8]) -> String? {
        guard let signed = BILTronTransactionProto.appendSignature(tx, signature) else { return nil }
        return BILPublicHex.encode(signed)
    }

    /// `"0x" ‖ r ‖ s ‖ v` with v = 27 + recId of a 65-byte `r ‖ s ‖ recId` signature (recId 0 or 1), else nil.
    static func signedMessage(signature: [UInt8]) -> String? {
        guard signature.count == BILTronTransactionProto.signatureBytes else { return nil }
        let recId = signature[64]
        guard recId == 0 || recId == 1 else { return nil }
        return "0x" + BILPublicHex.encode(Array(signature[0..<64])) + BILPublicHex.encode([27 + recId])
    }

    /// The answer `frames` read back as one TronLink request (single-QR parser, then the collector); throws
    /// `DecodeError` for no frames, an unreadable frame, a completion before the last frame or an incomplete answer, and
    /// the collector's `BILOtherWalletRequestError` for conflicting parts.
    static func decode(_ frames: [String]) throws -> BILTronLinkRequest {
        guard !frames.isEmpty else { throw DecodeError(what: "no frames") }
        let collector = BILTronLinkCollector()
        var complete: BILTronLinkRequest?
        for (i, frame) in frames.enumerated() {
            guard let parsed = BILTronLinkQrFormat.parse(frame) else { throw DecodeError(what: "frame") }
            if case .complete(let request) = try collector.add(parsed) {
                guard i == frames.count - 1 else { throw DecodeError(what: "frames after the last part") }
                complete = request
            }
        }
        guard let request = complete else { throw DecodeError(what: "incomplete answer") }
        return request
    }

    // MARK: - Private

    private static let hexListKey = "hexList"

    /// Android `(bean["type"] as? JsonPrimitive)?.takeIf { !it.isString }?.content?.toIntOrNull()`: a number literal that
    /// is a whole Int32 (sign allowed); a string, bool, null, fraction or exponent → nil.
    private static func integerType(_ value: BILJSONValue?) -> Int? {
        guard let literal = value?.numberLiteral, let n = BILEngineJSON.integerValue(literal),
              n >= Int64(Int32.min), n <= Int64(Int32.max) else { return nil }
        return Int(n)
    }
}
