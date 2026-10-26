//  BILScanProgress.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Public protocol (cold signer) — the state of a public scan session after a frame (engine `scanAdd` /
//  `decodePayload`: `{complete, progress, request?}`). Port of Android `core/publicsigner/.../model/ScanProgress.kt`
//  (R4 §8). `progress` is display only (fountain codes estimate it; never used for a decision); `parts` is counted by the
//  host's gate, not by the engine. Pure Foundation; `description` never prints the request.
//

import Foundation

public struct BILScanProgress: Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    /// Every part arrived; `request` is the decoded signing request.
    public let complete: Bool
    /// 0…1, display only.
    public let progress: Float
    /// Distinct frames accepted so far in this session (shown as "%1$d parts").
    public let parts: Int
    /// The engine's normalized request object when `complete` (an untrusted input for the next steps), else nil.
    public let request: BILJSONObject?

    /// `complete` implies `request` (Android `require`; a programming error, asserted in DEBUG); `parts` ≥ 0.
    public init(complete: Bool, progress: Float, parts: Int, request: BILJSONObject?) {
        assert(!complete || request != nil, "BILScanProgress: a complete scan carries its request")
        assert(parts >= 0, "BILScanProgress: negative part count")
        self.complete = complete
        self.progress = progress
        self.parts = parts
        self.request = request
    }

    public static let empty = BILScanProgress(complete: false, progress: 0, parts: 0, request: nil)

    /// The request's chain (nil until complete, or for a chain this app does not know).
    public var chain: BILPsChain? {
        return BILPsChain.fromWire(request?.str("chain"))
    }

    /// The request's transport (`eth-sign-request`, `crypto-psbt`, `bbqr-psbt`, `psbt-base64`, `tronlink`, …).
    public var transportType: String? {
        return request?.obj("transport")?.str("type")
    }

    /// Android `copy(parts = n)`.
    public func with(parts: Int) -> BILScanProgress {
        return BILScanProgress(complete: complete, progress: progress, parts: parts, request: request)
    }

    /// Reads an engine scan status. Throws `BILMalformedEngineResult` when `complete` is not a JSON bool, or when a complete
    /// status has no request object of a known chain. Not complete: `progress` = a non-string value read as a number
    /// (NaN / missing / unreadable → 0), clamped to 0…1.
    public static func fromEngine(_ raw: BILJSONObject, parts: Int) throws -> BILScanProgress {
        guard let complete = raw.bool("complete") else { throw BILMalformedEngineResult(what: "scan.complete") }
        if !complete {
            var progress: Float = 0
            if let value = raw["progress"], value.stringValue == nil, let reported = number(value), !reported.isNaN {
                progress = reported < 0 ? 0 : (reported > 1 ? 1 : reported)
            }
            return BILScanProgress(complete: false, progress: progress, parts: parts, request: nil)
        }
        guard let request = raw.obj("request") else { throw BILMalformedEngineResult(what: "scan.request") }
        try BILEngineJSON.ensure(BILPsChain.fromWire(request.str("chain")) != nil, "scan.request.chain")
        return BILScanProgress(complete: true, progress: 1, parts: parts, request: request)
    }

    /// Counts only.
    public var description: String {
        return "BILScanProgress(complete: \(complete), parts: \(parts), request: \(request == nil ? "none" : "present"))"
    }

    public var debugDescription: String {
        return description
    }

    /// Kotlin `JsonPrimitive.content.toFloatOrNull()` of a non-string primitive: a number literal → its value (out of
    /// range → ±infinity, clamped by the caller); `true` / `false` / `null` and containers → nil.
    private static func number(_ value: BILJSONValue) -> Float? {
        guard let literal = value.numberLiteral else { return nil }
        return Float(literal)
    }
}
