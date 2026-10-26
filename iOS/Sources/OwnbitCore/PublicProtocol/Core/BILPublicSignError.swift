//  BILPublicSignError.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Public protocol (cold signer) — a public-protocol failure as the UI shows it (Android `PublicSignError`): the
//  localized text of `key` with `args`, and — for the "Signing engine details (English)" box only — the engine `code`
//  and its bounded English `engineMessage` (render as untrusted text, never log it). C-KEY-5: `description` prints the
//  code only.
//

import Foundation

public struct BILPublicSignError: Error, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    /// Full key, e.g. "PublicProtocol.err.integrity".
    public let key: String
    public let args: [BILTextArg]
    /// Engine / host code for logs and the engine-details box.
    public let code: String?
    /// Bounded English, engine-details box only.
    public let engineMessage: String?

    public init(_ key: String, args: [BILTextArg] = [], code: String? = nil, engineMessage: String? = nil) {
        self.key = key
        self.args = args
        self.code = code
        self.engineMessage = engineMessage
    }

    /// `BILPublicText.format(key, args)`.
    public var text: String {
        return BILPublicText.format(key, args)
    }

    /// "BILPublicSignError(<code ?? key>)" — never the engine message or the arguments.
    public var description: String {
        return "BILPublicSignError(" + (code ?? key) + ")"
    }

    public var debugDescription: String {
        return description
    }

    /// A copy with `code` replaced.
    public func with(code: String?) -> BILPublicSignError {
        return BILPublicSignError(key, args: args, code: code, engineMessage: engineMessage)
    }
}
