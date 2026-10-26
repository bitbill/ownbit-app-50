//  BILPublicPayloadView.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Public protocol (cold signer) — what a QR code actually carries, decoded back by the engine from the frames it
//  produced (registry field names, byte strings as hex; a plain-text code is its own payload). Public keys / signatures
//  only, nothing secret. Shown in the "Payload" disclosure and the "Format" row of the pairing and result pages; nil
//  (no view) hides the disclosure. Port of Android core/publicsigner/.../model/PublicPayloadView.kt and
//  `PayloadDisclosureDefaults.title / summary` (ui/PayloadDisclosure.kt) (design §3.5, R3 §6.7, R6 §6.2). Pure Foundation.
//

import Foundation

/// - `text`: the payload as shown — pretty, key-sorted JSON (2-space indent) for `.json`, else the hex / text.
/// - `byteCount`: size of the encoded payload (CBOR bytes for a UR, UTF-8 bytes for text).
/// - `qrType`: the transport (`crypto-account`, `eth-signature`, `bbqr-psbt`, `psbt-base64`, `address`, `tronlink`, …).
/// - `bbqrEncoding`: `H` / `2` / `Z` for a BBQr code (3rd character of the first frame when it starts with `B$`), else nil.
public struct BILPublicPayloadView: Equatable {
    public enum Format: String, CaseIterable {
        case json, hex, text
    }

    public let format: Format
    public let text: String
    public let byteCount: Int
    public let qrType: String?
    public let bbqrEncoding: String?

    public init(format: Format, text: String, byteCount: Int, qrType: String?, bbqrEncoding: String? = nil) {
        self.format = format
        self.text = text
        self.byteCount = byteCount
        self.qrType = qrType
        self.bbqrEncoding = bbqrEncoding
    }

    /// A signed PSBT in any of its transports.
    public var isPsbt: Bool {
        guard let type = qrType else { return false }
        return BILPublicModelText.contains(BILPublicPayloadView.psbtTypes, type)
    }

    /// A UR (CBOR) transport rather than plain text / BBQr / another wallet's own JSON format (TronLink).
    public var isUr: Bool {
        guard let type = qrType else { return false }
        return !BILPublicModelText.contains(BILPublicPayloadView.notUrTypes, type)
    }

    /// Another wallet's own JSON answer (TronLink).
    public var isOtherWalletJson: Bool {
        guard let type = qrType else { return false }
        return BILPublicModelText.contains(BILPublicPayloadView.otherWalletJsonTypes, type)
    }

    /// The format name after "Payload · " (standard terms, never translated): "JSON" | "Hex" | "UTF-8".
    public var titleSuffix: String {
        switch format {
        case .json: return "JSON"
        case .hex: return "Hex"
        case .text: return "UTF-8"
        }
    }

    /// The transport line of the "Format" row (technical identifiers, the same in every language; bytes with en_US
    /// grouping and Latin digits, SI "B"): `ur:crypto-account · CBOR · 162 B`, `BBQr · PSBT (Base32) · 3,120 B`,
    /// `PSBT Base64 · 412 B`, `PSBT hex · 412 B`, `UTF-8 · 42 B` (an address, or no type), `TronLink · JSON · 1,412 B`.
    public var formatSummary: String {
        let bytes = BILPublicPayloadView.groupedBytes(byteCount)
        guard let type = qrType else { return "UTF-8 · " + bytes }
        if BILPublicModelText.same(type, "bbqr-psbt") {
            let encoding = bbqrEncoding.map { BILPublicModelText.same($0, "H") } == true ? "hex" : "Base32"
            return "BBQr · PSBT (" + encoding + ") · " + bytes
        }
        if BILPublicModelText.same(type, "psbt-base64") { return "PSBT Base64 · " + bytes }
        if BILPublicModelText.same(type, "psbt-hex") { return "PSBT hex · " + bytes }
        if BILPublicModelText.same(type, "address") { return "UTF-8 · " + bytes }
        if BILPublicModelText.same(type, BILPublicResponseQr.tronLinkType) { return "TronLink · JSON · " + bytes }
        return "ur:" + type + " · CBOR · " + bytes
    }

    /// The view of an engine result that carries `payloadFormat` / `payload` / `payloadBytes` / `type` / `frames`
    /// (pairing and response results); nil when the engine sent none or it is malformed (an unknown `payloadFormat`, a
    /// JSON payload that is not an object, an empty / non-string hex or text payload) — the disclosure is then hidden,
    /// the QR itself is unaffected. `byteCount` = `payloadBytes` (Int32) when present, else the UTF-8 size of `text`.
    public static func fromEngine(_ raw: BILJSONObject) -> BILPublicPayloadView? {
        guard let format = BILPublicModelText.wire(raw.str("payloadFormat"), Format.self) else { return nil }
        let text: String
        switch format {
        case .json:
            guard let payload = raw.obj("payload") else { return nil }
            text = prettyJson(payload)
        case .hex, .text:
            guard let payload = raw.str("payload"), !payload.isEmpty else { return nil }
            text = payload
        }
        let firstFrame = raw.strings("frames")?.first ?? ""
        return BILPublicPayloadView(format: format, text: text, byteCount: raw.int("payloadBytes") ?? text.utf8.count,
                                    qrType: raw.str("type"), bbqrEncoding: bbqrEncoding(ofFirstFrame: firstFrame))
    }

    /// A plain-text payload built natively (the EVM address-mode pairing code: `qrType` "address"): `.text`, the
    /// text as it is, `byteCount` = its UTF-8 size.
    public static func text(_ text: String, qrType: String) -> BILPublicPayloadView {
        return BILPublicPayloadView(format: .text, text: text, byteCount: text.utf8.count, qrType: qrType)
    }

    /// A JSON payload built natively — the TronLink answer (Android `PublicSignCoordinator.tronLinkAnswer`):
    /// `.json`, `prettyJson(object)`, `byteCount` = the UTF-8 size of the compact serialization.
    public static func json(_ object: BILJSONObject, qrType: String) -> BILPublicPayloadView {
        return BILPublicPayloadView(format: .json, text: prettyJson(object),
                                    byteCount: BILStrictJSON.serialize(object).utf8.count, qrType: qrType)
    }

    /// Pretty JSON with every object's keys sorted (UTF-16 order), 2-space indent (`BILStrictJSON.prettySorted`).
    public static func prettyJson(_ object: BILJSONObject) -> String {
        return BILStrictJSON.prettySorted(.object(object))
    }

    /// Exact (code units; design D-01).
    public static func == (lhs: BILPublicPayloadView, rhs: BILPublicPayloadView) -> Bool {
        return lhs.format == rhs.format && BILPublicModelText.same(lhs.text, rhs.text) && lhs.byteCount == rhs.byteCount
            && BILPublicModelText.sameOptional(lhs.qrType, rhs.qrType)
            && BILPublicModelText.sameOptional(lhs.bbqrEncoding, rhs.bbqrEncoding)
    }

    // MARK: - Internal

    public static let psbtTypes = ["crypto-psbt", "psbt", "bbqr-psbt", "psbt-base64", "psbt-hex"]
    public static let otherWalletJsonTypes = [BILPublicResponseQr.tronLinkType]
    public static let notUrTypes = ["address", "bbqr-psbt", "psbt-base64", "psbt-hex"] + otherWalletJsonTypes

    /// `String.format(Locale.US, "%,d B", n)`: comma grouping of 3, Latin digits, a leading "-" for a negative value.
    public static func groupedBytes(_ n: Int) -> String {
        let digits = Array(String(n.magnitude).utf8)
        var out = [UInt8]()
        out.reserveCapacity(digits.count + digits.count / 3 + 3)
        if n < 0 { out.append(0x2D) }
        for (i, d) in digits.enumerated() {
            if i > 0 && (digits.count - i) % 3 == 0 { out.append(0x2C) }
            out.append(d)
        }
        return String(decoding: out, as: UTF8.self) + " B"
    }

    /// The 3rd character of a first frame that starts with `B$` (and has one), else nil.
    private static func bbqrEncoding(ofFirstFrame frame: String) -> String? {
        let units = Array(frame.utf16)
        guard units.count > 2, units[0] == 0x42, units[1] == 0x24 else { return nil }   // "B$"
        // Android takes the UTF-16 unit at index 2; a surrogate there takes its whole scalar (Swift cannot hold half).
        var end = 3
        if BILPublicModelText.isHighSurrogate(units[2]) && units.count > 3 && BILPublicModelText.isLowSurrogate(units[3]) { end = 4 }
        return String(decoding: units[2..<end], as: UTF16.self)
    }
}
