//  BILPublicSignResult.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Public protocol (cold signer) — the result of one `signPlanTask` call and the answer QR (engine `encodeResponse`, or
//  the natively built TronLink answer). Port of Android core/publicsigner/.../model/PublicSignResult.kt (design §3.5).
//  Malformed shapes throw `BILMalformedEngineResult(what)` (log-safe part name). Pure Foundation.
//

import Foundation

/// The result of one `signPlanTask` call. `raw` is kept whole: it is the `previousResult` of the next task of a
/// multi-wallet PSBT and the `result` of `encodeResponse`. It holds only public data (a PSBT with partial signatures,
/// a signature) — never key material.
///
/// `completedTaskIds`: every task signed so far in this plan, this one last. Whether the result belongs to the reviewed
/// plan is the coordinator's / verifier's check.
public struct BILPublicSignResult: Equatable {
    public let chain: BILPsChain
    public let requestHash: String
    public let planHash: String
    public let taskId: String
    public let completedTaskIds: [String]
    public let raw: BILJSONObject

    /// Reads a `signPlanTask` result; throws unless it names a known chain (`result.chain`), 64-hex request / plan
    /// hashes (`result.requestHash`, `result.planHash`), its task (`result.taskId`, non-empty) and lists that task last
    /// in an all-strings `completedTaskIds` (`result.completedTaskIds`). Hashes are lower-cased.
    public static func fromEngine(_ raw: BILJSONObject) throws -> BILPublicSignResult {
        guard let chain = BILPsChain.fromWire(raw.str("chain")) else { throw BILMalformedEngineResult(what: "result.chain") }
        guard let requestHash = raw.str("requestHash"), BILEngineJSON.isHex(requestHash, bytes: 32) else {
            throw BILMalformedEngineResult(what: "result.requestHash")
        }
        guard let planHash = raw.str("planHash"), BILEngineJSON.isHex(planHash, bytes: 32) else {
            throw BILMalformedEngineResult(what: "result.planHash")
        }
        guard let taskId = raw.str("taskId"), !taskId.isEmpty else { throw BILMalformedEngineResult(what: "result.taskId") }
        guard let completed = raw.strings("completedTaskIds") else {
            throw BILMalformedEngineResult(what: "result.completedTaskIds")
        }
        try BILEngineJSON.ensure(completed.last.map { BILPublicModelText.same($0, taskId) } ?? false, "result.completedTaskIds")
        return BILPublicSignResult(chain: chain, requestHash: requestHash.lowercased(), planHash: planHash.lowercased(),
                                   taskId: taskId, completedTaskIds: completed, raw: raw)
    }
}

/// The answer QR, in the request's own transport: `crypto-psbt` / `psbt` / BBQr / static PSBT text for Bitcoin,
/// `eth-signature` / `sol-signature` / `tron-signature` otherwise; built natively: `tronlink` (TronLink's JSON,
/// numbered static parts above 1000 characters). Nothing here is broadcast: the other wallet finalizes and broadcasts.
///
/// - `frames`: QR frames (at least one); more than one → animated (250 ms per frame), except TronLink's numbered parts
///   (`isPaged`: a pager, TronLink reads them strictly in order).
/// - `payload`: the decoded payload view, nil when the engine sent none.
/// - `signedTransaction`: the code carries the whole signed transaction (TronLink), not only a signature
///   (`result.signedTransaction` instead of `result.signatureOnly`).
public struct BILPublicResponseQr: Equatable {
    /// The natively built answer type.
    public static let tronLinkType = "tronlink"

    public let type: String
    public let frames: [String]
    public let payload: BILPublicPayloadView?
    public let signedTransaction: Bool

    /// Callers pass at least one frame (Android `require(frames.isNotEmpty())`; checked in DEBUG builds only, the
    /// contract init does not throw). Natively built answers (the TronLink answer) go through `checked`, which throws
    /// instead; `fromEngine` uses it as well.
    public init(type: String, frames: [String], payload: BILPublicPayloadView?, signedTransaction: Bool = false) {
        assert(!frames.isEmpty, "A response QR has at least one frame")
        self.type = type
        self.frames = frames
        self.payload = payload
        self.signedTransaction = signedTransaction
    }

    /// The init with Android's `require(frames.isNotEmpty())` as a throw: `BILMalformedEngineResult(what:
    /// "response.frames")` when `frames` is empty, in DEBUG and release alike. On the TronLink answer path the
    /// coordinator maps this throw like Android's `IllegalArgumentException` there (`err.verify`, code `ANSWER`).
    public static func checked(type: String, frames: [String], payload: BILPublicPayloadView?,
                        signedTransaction: Bool = false) throws -> BILPublicResponseQr {
        try BILEngineJSON.ensure(!frames.isEmpty, "response.frames")
        return BILPublicResponseQr(type: type, frames: frames, payload: payload, signedTransaction: signedTransaction)
    }

    /// A TronLink answer (`result.tronlinkScanBack`).
    public var isTronLink: Bool {
        return BILPublicModelText.same(type, BILPublicResponseQr.tronLinkType)
    }

    /// TronLink numbered parts: shown one at a time with Previous / Next code, never animated.
    public var isPaged: Bool {
        return isTronLink && frames.count > 1
    }

    public var isAnimated: Bool {
        return frames.count > 1 && !isPaged
    }

    /// A signed PSBT (partial signatures only).
    public var isPsbt: Bool {
        return BILPublicModelText.contains(BILPublicPayloadView.psbtTypes, type)
    }

    /// What "Copy" copies: the single frame, or every frame on its own line.
    public var text: String {
        return frames.joined(separator: "\n")
    }

    /// Reads an `encodeResponse` result; throws without a non-empty string `type` (`response.type`) or without at
    /// least one non-empty frame (`response.frames`; empty frames are dropped, a non-string element drops them all).
    public static func fromEngine(_ raw: BILJSONObject) throws -> BILPublicResponseQr {
        guard let type = raw.str("type"), !type.isEmpty else { throw BILMalformedEngineResult(what: "response.type") }
        let frames = (raw.strings("frames") ?? []).filter { !$0.isEmpty }
        return try checked(type: type, frames: frames, payload: BILPublicPayloadView.fromEngine(raw), signedTransaction: false)
    }

    /// Exact (code units, frames element-wise; design D-01): a frame that differs only in its Unicode normalization is
    /// another QR code.
    public static func == (lhs: BILPublicResponseQr, rhs: BILPublicResponseQr) -> Bool {
        return BILPublicModelText.same(lhs.type, rhs.type) && BILPublicModelText.sameList(lhs.frames, rhs.frames)
            && lhs.payload == rhs.payload && lhs.signedTransaction == rhs.signedTransaction
    }
}
