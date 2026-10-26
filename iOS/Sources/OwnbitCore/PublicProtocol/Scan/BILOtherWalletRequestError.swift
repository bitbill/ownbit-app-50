//  BILOtherWalletRequestError.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Public protocol (cold signer) — a request in another wallet's own QR format (TronLink; any TokenPocket text, owner
//  2026-10-13) that Ownbit cannot read or does not sign, refused **before** the engine by the host's collector / mapper /
//  paste routing. Port of Android `core/publicsigner/.../scan/OtherWalletRequestException.kt`. `error` is the text to show
//  (with its arguments, e.g. TronLink's type number); `kind` how the scan session reports it. `description` prints the
//  code only (C-KEY-5).
//

import Foundation

public struct BILOtherWalletRequestError: Error, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {

    public enum Kind: Equatable {
        /// Not readable as the format says (structure, hex, JSON, address).
        case malformed
        /// Readable, but not signed by Ownbit v1 (shielded, raw hashes, v1 messages, several transactions, TokenPocket …).
        case unsupported
        /// Parts of two different requests (a conflicting part, another part count, another address).
        case otherRequest
        /// Beyond the collector's limits.
        case tooLarge
    }

    public let kind: Kind
    public let error: BILPublicSignError

    public var description: String {
        return "Other wallet request refused: " + (error.code ?? "")
    }

    public var debugDescription: String {
        return description
    }

    /// No children: `dump` / `Mirror` show no arguments or engine text.
    public var customMirror: Mirror {
        return Mirror(self, children: [:])
    }

    // MARK: - Prebuilt refusals (codes as in Android)

    /// `scan.otherRequest`, code `OTHER_REQUEST`.
    public static var otherRequest: BILOtherWalletRequestError {
        return BILOtherWalletRequestError(kind: .otherRequest,
                                          error: BILPublicSignError("PublicProtocol.scan.otherRequest", code: "OTHER_REQUEST"))
    }

    /// `err.tooLarge`, code `LIMIT`.
    public static var tooLarge: BILOtherWalletRequestError {
        return BILOtherWalletRequestError(kind: .tooLarge, error: BILPublicSignError("PublicProtocol.err.tooLarge", code: "LIMIT"))
    }

    /// `err.qrMalformed` with `code` (`MALFORMED`; the paste path uses `INCOMPLETE`).
    public static func malformed(code: String = "MALFORMED") -> BILOtherWalletRequestError {
        return BILOtherWalletRequestError(kind: .malformed, error: BILPublicSignError("PublicProtocol.err.qrMalformed", code: code))
    }

    /// Any TokenPocket text: `err.tpUnsupported`, code `TP_UNSUPPORTED`.
    public static var tokenPocket: BILOtherWalletRequestError {
        return BILOtherWalletRequestError(kind: .unsupported, error: BILPublicSignerErrors.tpUnsupported)
    }
}
