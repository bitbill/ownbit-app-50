//  BILPublicPasteRouting.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Public protocol (cold signer) — the host-side pre-routing of a pasted text (entry page paste sheet), before any engine
//  call. Port of Android `PublicSignCoordinator.otherWalletRequest` (`PublicSignCoordinator.kt:384-414`, R4 §16 step 3):
//  a pasted TronLink request goes through the same collector and mapper as a scan; any TokenPocket text is refused
//  (owner 2026-10-13); everything else is left to the engine's `decodePayload` (the coordinator, WP19, which also applies
//  the `maxPasteBytes` bound and maps engine refusals). The pasted text lives only in memory; nothing is logged.
//

import Foundation

public enum BILPublicPasteRouting {

    /// UTF-8 bytes of a pasted text (larger → `err.tooLarge`, code `LIMIT`; checked by the coordinator before this).
    public static let maxPasteBytes = 262_144

    /// One TronLink object (also pretty-printed / multi-line; up to `BILTronLinkQrFormat.maxRequestChars`) or TronLink
    /// parts one per line → the mapped engine request; any TokenPocket text → throws `tpUnsupported`; incomplete parts
    /// (a line that is not a TronLink frame, or no complete request) → `err.qrMalformed` with code `INCOMPLETE`;
    /// otherwise nil (→ `decodePayload` of the original text). Throws `BILOtherWalletRequestError` (collector / mapper
    /// refusals propagate with their own text and arguments). Two single TronLink objects on two lines: the second wins
    /// (Android collector quirk, kept).
    public static func otherWalletRequest(_ text: String) throws -> BILJSONObject? {
        let trimmed = BILKotlinText.trim(text)
        if BILPublicHex.hasASCIIPrefix(trimmed, "{"),
           let frame = BILTronLinkQrFormat.parse(trimmed, maxChars: BILTronLinkQrFormat.maxRequestChars), !frame.isPart {
            return try BILTronLinkRequestMapper.map(BILTronLinkRequest.of(frame))
        }
        if BILPublicQrFormat.classify(trimmed) == .tpUnsupported {
            throw BILOtherWalletRequestError.tokenPocket
        }
        let lines = BILKotlinText.lines(trimmed).map(BILKotlinText.trim).filter { !$0.isEmpty }
        guard let first = lines.first, let kind = BILPublicQrFormat.classify(first) else { return nil }
        if kind.isTronLink {
            let collector = BILTronLinkCollector()
            var request: BILTronLinkRequest?
            for line in lines {
                guard let frame = BILTronLinkQrFormat.parse(line) else { throw BILOtherWalletRequestError.malformed(code: "INCOMPLETE") }
                if case .complete(let complete) = try collector.add(frame) {
                    request = complete
                }
            }
            guard let complete = request else { throw BILOtherWalletRequestError.malformed(code: "INCOMPLETE") }
            return try BILTronLinkRequestMapper.map(complete)
        }
        if kind == .tpUnsupported {
            throw BILOtherWalletRequestError.tokenPocket
        }
        return nil
    }
}
