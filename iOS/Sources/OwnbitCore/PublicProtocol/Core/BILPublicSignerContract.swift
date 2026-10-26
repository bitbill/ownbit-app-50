//  BILPublicSignerContract.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Public protocol (cold signer) — the engine contract (design §3.1): the protocol the engine host implements (WP7
//  `BILPublicSignerEngine`, faked in harnesses), the scan-session handle, and the refusal / failure types. Refusal
//  bounds are Android `PublicSignerException` (`core/jsengine/.../bridge/PublicSignerException.kt`, R1 §2.3).
//  Pure Foundation.
//

import Foundation

/// A scan session of the engine; `sessionId` is strictly increasing per process.
public struct BILPublicScanHandle: Hashable {
    public let sessionId: Int64
}

/// `review` + `resolveSigningPlan` of one request (UNTRUSTED context).
public struct BILPublicReviewAndPlan: Equatable {
    public let review: BILJSONObject
    public let plan: BILJSONObject
}

/// The engine refused a request (`{"ok":false,"error":{"code","message"}}`), or the host refused it before the
/// engine with an engine code (`LIMIT` for a request over 1,000,000 UTF-8 bytes, `SCAN` for no active scan session).
/// C-KEY-5: `code` is reduced to `[A-Z0-9_]{1,80}` and is the only part that may be logged; `engineMessage` is the
/// engine's English text (≤ 400 UTF-16 units) for the engine-details box only. `description` prints the code only.
public struct BILPublicSignerRefusal: Error, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    /// Sanitized `[A-Z0-9_]{1,80}`; "" → "UNKNOWN".
    public let code: String
    /// ≤ 400 UTF-16 units, never splits a surrogate pair.
    public let engineMessage: String

    /// Sanitizes `code` and bounds `engineMessage`.
    public init(code: String, engineMessage: String) {
        self.code = BILPublicSignerRefusal.sanitize(code)
        self.engineMessage = BILPublicSignerRefusal.bound(engineMessage)
    }

    public var description: String {
        return "Public signer refused the request: " + code
    }

    public var debugDescription: String {
        return description
    }

    /// Android `sanitizeCode`: upper-cased (locale-independent), only `A-Z 0-9 _` kept, first 80, "" → "UNKNOWN".
    public static func sanitize(_ code: String) -> String {
        var out = [UInt8]()
        for b in code.uppercased().utf8 {
            switch b {
            case 0x41...0x5A, 0x30...0x39, 0x5F:
                out.append(b)
            default:
                continue
            }
            if out.count == maxCodeLength { break }
        }
        return out.isEmpty ? "UNKNOWN" : String(decoding: out, as: UTF8.self)
    }

    /// Android `bound`: at most `max` UTF-16 units; a surrogate pair that would be cut is dropped whole.
    public static func bound(_ text: String, max: Int = 400) -> String {
        return BILKotlinText.prefix(text, utf16: max)
    }

    public static let maxCodeLength = 80

    public static let limitCode = "LIMIT", limitMessage = "Request exceeds one megabyte."
    public static let scanCode = "SCAN", scanMessage = "No scan session is active."
    public static let defaultCode = "SIGNING_FAILED", defaultMessage = "This request could not be signed."
}

/// The engine could not run or answered outside its contract. Shown as `PublicProtocol.err.engineUnavailable`.
public enum BILPublicSignerFailure: Error, Equatable, CustomStringConvertible {
    /// Bundle missing / SHA mismatch / JavaScriptCore failure / identity probe failed. Code "ENGINE_UNAVAILABLE".
    case engineUnavailable
    /// Bad envelope (JS exception, not a JSON object, `ok` not a bool, …). Code "ENGINE_FAILURE".
    case malformedResponse
    /// A programming error (e.g. a secret parameter on a non-SECRET operation). Code "INVALID_REQUEST".
    case invalidRequest

    public var code: String {
        switch self {
        case .engineUnavailable: return "ENGINE_UNAVAILABLE"
        case .malformedResponse: return "ENGINE_FAILURE"
        case .invalidRequest: return "INVALID_REQUEST"
        }
    }

    public var description: String {
        return "Public signer failure: " + code
    }
}

/// The only door to the public-protocol engine (implemented by WP7's actor; faked in harnesses). Every method throws
/// `BILPublicSignerRefusal` or `BILPublicSignerFailure`.
public protocol BILPublicSignerEngining: AnyObject {
    // PAIRING (warm context; only the device's own unsealed + cross-checked index; never a seed or external input)
    func capabilities() async throws -> BILJSONObject
    func derivePublicAddresses(publicIndex: BILJSONObject, chain: String, profile: String?, start: Int, count: Int) async throws -> BILJSONObject
    func createPublicPairing(publicIndex: BILJSONObject, chain: String, profile: String?, outputMode: String?, index: Int) async throws -> BILJSONObject
    func releasePairingContext() async
    // SECRET (fresh context per call)
    func derivePublicIndex(seedHex: String, tronScheme: String?, tronAddressCount: Int?) async throws -> BILJSONObject
    func refreshPublicIndex(publicIndex: BILJSONObject, tronScheme: String, tronAddressCount: Int?) async throws -> BILJSONObject
    func signPlanTask(request: BILJSONObject, plan: BILJSONObject, taskId: String, seedHex: String,
                      riskAcknowledged: Bool, previousResult: BILJSONObject?) async throws -> BILJSONObject
    // UNTRUSTED (fresh context per request)
    func decodePayload(_ payload: String) async throws -> BILJSONObject
    func reviewAndResolve(request: BILJSONObject, wallets: [BILJSONObject]) async throws -> BILPublicReviewAndPlan
    func encodeResponse(request: BILJSONObject, result: BILJSONObject) async throws -> BILJSONObject
    // SCAN (one context per session)
    func openScan() async throws -> BILPublicScanHandle
    func scanAdd(_ handle: BILPublicScanHandle, frame: String) async throws -> BILJSONObject
    func closeScan(_ handle: BILPublicScanHandle) async
    // Identity probe (R1 §2.4); success cached per process, failure not cached
    func isAvailable() async -> Bool
}
