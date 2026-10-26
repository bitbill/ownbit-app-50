//  BILPublicTronLinkAnswer.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Public protocol (cold signer) — Ownbit's answer QR to a TronLink request (round 2, R2-7), built natively because the
//  engine's `encodeResponse` has no TronLink profile (design §3.17; port of Android
//  core/publicsigner/.../sign/PublicSignCoordinator.kt:815-842, `tronLinkAnswer` / `otherWalletText`):
//
//  - the request bean = the scanned TronLink text (`request.transport.payloadBytes`, hex of its UTF-8) read back with the
//    scanner's own parser (`BILTronLinkQrFormat`, request size limit; the mapper wrote it, a reassembled split request
//    has no `cN` / `tN`); anything unreadable, or a bean without `hexList`, is refused;
//  - the entry = the request's `Transaction` ‖ `12 41` ‖ the engine's 65-byte signature (a transaction or TronLink's
//    ownership placeholder), or `0x` ‖ r ‖ s ‖ v for a TIP-191 message (`BILTronLinkAnswerCodec`);
//  - frames = one QR or TronLink's numbered parts (`BILTronLinkAnswerCodec.encode`); the payload disclosure is the answer
//    object as JSON ("Payload · JSON", byte count of the compact text); `signedTransaction` for a TRON transaction.
//
//  Every failure throws `BILPublicTronLinkAnswer.Failure` (log-safe check name); the coordinator maps it to `err.verify`,
//  code `ANSWER` (Android's `IllegalArgumentException` there). The answer is still post-checked by the native verifier
//  before it is shown. Pure Foundation; never logs.
//

import Foundation

enum BILPublicTronLinkAnswer {

    /// Why no answer could be built (names the step only, never content).
    struct Failure: Error, Equatable, CustomStringConvertible {
        let what: String
        var description: String {
            return "TronLink answer not built: " + what
        }
    }

    /// The TronLink answer of `request` (an engine-native TRON request the TronLink mapper produced) for the verified
    /// payload `verified` and the engine's 65-byte `signature` (`r ‖ s ‖ recId`).
    static func response(request: BILJSONObject, verified: BILVerifiedPayload, signature: [UInt8]) throws -> BILPublicResponseQr {
        guard let text = scannedText(request) else { throw Failure(what: "tronlink request") }
        guard let frame = BILTronLinkQrFormat.parse(text, maxChars: BILTronLinkQrFormat.maxRequestChars) else {
            throw Failure(what: "tronlink request")
        }
        let bean = frame.json
        guard bean.contains("hexList") else { throw Failure(what: "tronlink request") }
        let entry: String?
        let signedTransaction: Bool
        switch verified {
        case .tronTransaction(_, _, _, _, let txProto):
            guard let tx = txProto else { throw Failure(what: "txProto") }
            entry = BILTronLinkAnswerCodec.signedTransaction(tx: tx, signature: signature)
            signedTransaction = true
        case .tronOwnershipProof(_, _, _, let txProto):
            entry = BILTronLinkAnswerCodec.signedTransaction(tx: txProto, signature: signature)
            signedTransaction = false
        case .tronMessage:
            entry = BILTronLinkAnswerCodec.signedMessage(signature: signature)
            signedTransaction = false
        default:
            throw Failure(what: "tronlink payload")
        }
        guard let signed = entry else { throw Failure(what: "signature") }
        let frames = BILTronLinkAnswerCodec.encode(bean, signed: [signed])
        guard !frames.isEmpty else { throw Failure(what: "frames") }
        let answer = BILTronLinkAnswerCodec.answerBean(bean, signed: [signed])
        let view = BILPublicPayloadView.json(answer, qrType: BILPublicResponseQr.tronLinkType)
        do {
            return try BILPublicResponseQr.checked(type: BILPublicResponseQr.tronLinkType, frames: frames, payload: view,
                                                   signedTransaction: signedTransaction)
        } catch {
            throw Failure(what: "frames")
        }
    }

    /// The engine's signature of a `signPlanTask` result (`result.signature`, plain hex), or nil.
    static func signature(of result: BILPublicSignResult) -> [UInt8]? {
        return result.raw.str("signature").flatMap(BILPublicHex.decode)
    }

    /// The scanned text of a TronLink request (`transport.payloadBytes`, the hex of its UTF-8 bytes; malformed UTF-8 is
    /// replaced like Kotlin's `String(bytes, UTF_8)`).
    static func scannedText(_ request: BILJSONObject) -> String? {
        guard let hex = request.obj("transport")?.str("payloadBytes"), let bytes = BILPublicHex.decode(hex) else { return nil }
        return String(decoding: bytes, as: UTF8.self)
    }
}
