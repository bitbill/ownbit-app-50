//  BILPublicScanErrors.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Public protocol (cold signer) — the scan-side texts of Android `core/publicsigner/.../text/PublicSignerErrors.kt`
//  that WP1's `BILPublicSignerErrors` does not carry (design addendum A5): `scan(reason, kind)`, `wrongDirection(kind)`,
//  `unsupported(kind)`. Keys are full `PublicProtocol.*` keys (resolve with `BILPublicText`). Pure Foundation.
//

import Foundation

public enum BILPublicScanErrors {

    /// The text key of a scan-gate rejection: `tooLarge` / `sessionFull` → `err.tooLarge`; `malformed` → `err.qrMalformed`;
    /// `wrongDirection` → `wrongDirection(kind)`; `unsupported` → `err.unsupportedUr`; `otherRequest` →
    /// `scan.otherRequest`; `timedOut` → `err.scanTimeout`; `empty` / `notPublic` → nil (ignored during a session).
    public static func scan(_ reason: BILGateReason, kind: BILPublicQrKind? = nil) -> String? {
        switch reason {
        case .tooLarge, .sessionFull: return "PublicProtocol.err.tooLarge"
        case .malformed: return "PublicProtocol.err.qrMalformed"
        case .wrongDirection: return wrongDirection(kind)
        case .unsupported: return "PublicProtocol.err.unsupportedUr"
        case .otherRequest: return "PublicProtocol.scan.otherRequest"
        case .timedOut: return "PublicProtocol.err.scanTimeout"
        case .empty, .notPublic: return nil
        }
    }

    /// `err.signatureCode` for a signature answer (a UR `*-signature`), else `err.pairingCode` (a pairing export scanned as
    /// a request).
    public static func wrongDirection(_ kind: BILPublicQrKind?) -> String {
        return kind == .signatureUr ? "PublicProtocol.err.signatureCode" : "PublicProtocol.err.pairingCode"
    }

    /// The refusal of a recognised code that is not a request Ownbit signs (not a signing request, not the wrong
    /// direction): any TokenPocket text → `BILPublicSignerErrors.tpUnsupported`; a UR / BBQr of another type →
    /// `err.unsupportedUr` with code `UNSUPPORTED`.
    public static func unsupported(_ kind: BILPublicQrKind?) -> BILPublicSignError {
        if kind == .tpUnsupported { return BILPublicSignerErrors.tpUnsupported }
        return BILPublicSignError("PublicProtocol.err.unsupportedUr", code: "UNSUPPORTED")
    }
}
