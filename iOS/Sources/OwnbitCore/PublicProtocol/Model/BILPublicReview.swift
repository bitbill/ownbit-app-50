//  BILPublicReview.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Public protocol (cold signer) — the engine review of one request (`review` / `plan.review`): fields, warnings,
//  decode status, risk level, network, the structured display headline and the recognised asset. Port of Android
//  core/publicsigner/.../model/PublicReview.kt (design §3.5, R6 §3 inputs). Review rows on the pages come only from
//  this object (C-DISP); everything in it is untrusted English text from the request's decoder (render it through
//  `BILUntrustedText`, addresses LTR). Pure Foundation.
//
//  Exactness: every rule here compares strings by UTF-16 code units (Kotlin `String.equals` / `indexOf`), never by
//  Swift canonical equivalence, and every length is a UTF-16 length. `==` is exact too (design D-01): the small value
//  types below spell it out field by field with `BILPublicModelText` (a synthesized `==` would treat "é" and
//  "e\u{301}" as equal); `BILPublicReview.==` is exact because it includes `raw` (exact JSON equality).
//

import Foundation

/// How completely the engine decoded what will be signed (engine `decodeStatus`). Unknown values read as `.opaque`.
public enum BILDecodeStatus: String, CaseIterable {
    case fullyDecoded, partiallyDecoded, opaque

    public static func fromWire(_ s: String?) -> BILDecodeStatus {
        return BILPublicModelText.wire(s, BILDecodeStatus.self) ?? .opaque
    }
}

/// The engine's risk level (`riskLevel`). Unknown values read as `.high` (fail closed).
public enum BILRiskLevel: String, CaseIterable {
    case normal, warning, high

    public static func fromWire(_ s: String?) -> BILRiskLevel {
        return BILPublicModelText.wire(s, BILRiskLevel.self) ?? .high
    }
}

/// One "label: value" row of the engine review. Labels and values are the engine's English text (labels are
/// localized by the presenter where the vocabulary knows them); values are shown whole, never cut (what is shown is
/// what is signed). `index` keeps the engine order (the position in the engine's `fields` array).
public struct BILReviewField: Equatable {
    public let index: Int
    public let label: String
    public let value: String

    /// The group of "Instruction 2 · Recipient" ("Instruction 2"), else nil (split at the first " · ").
    public var group: String? {
        let units = Array(label.utf16)
        guard let at = BILPublicModelText.indexOf(BILReviewField.groupSeparator, in: units, from: 0) else { return nil }
        return String(decoding: units[0..<at], as: UTF16.self)
    }

    /// The label without its group.
    public var shortLabel: String {
        let units = Array(label.utf16)
        guard let at = BILPublicModelText.indexOf(BILReviewField.groupSeparator, in: units, from: 0) else { return label }
        return String(decoding: units[(at + BILReviewField.groupSeparator.count)...], as: UTF16.self)
    }

    /// " · " (space, U+00B7 MIDDLE DOT, space); matched by code units (U+0387 GREEK ANO TELEIA, which Swift treats as
    /// canonically equal to U+00B7, is not a separator — as on Android).
    private static let groupSeparator: [UInt16] = [0x20, 0xB7, 0x20]

    /// Exact (code units).
    public static func == (lhs: BILReviewField, rhs: BILReviewField) -> Bool {
        return lhs.index == rhs.index && BILPublicModelText.same(lhs.label, rhs.label) && BILPublicModelText.same(lhs.value, rhs.value)
    }
}

/// Network context the engine reports for this exact request (EVM chain id + name; BTC / TRON / SOL name only).
public struct BILReviewNetwork: Equatable {
    public let chainId: String?
    public let name: String
    public let symbol: String?

    /// Exact (code units).
    public static func == (lhs: BILReviewNetwork, rhs: BILReviewNetwork) -> Bool {
        return BILPublicModelText.sameOptional(lhs.chainId, rhs.chainId) && BILPublicModelText.same(lhs.name, rhs.name)
            && BILPublicModelText.sameOptional(lhs.symbol, rhs.symbol)
    }
}

/// Token the engine recognised from its bundled registry (engine `asset`). Amounts are decimal strings, never floating
/// point. Read as a whole: a missing required key drops the asset.
public struct BILReviewAsset: Equatable {
    public let chainFamily: String
    public let chainId: String?
    public let assetAddress: String
    public let name: String
    public let symbol: String
    public let decimals: Int
    public let tokenProgram: String?
    public let rawAmount: String?
    public let displayAmount: String?

    /// Android `PublicReview.asset(raw)`: chainFamily, assetAddress, name, symbol (strings) and decimals (Int32) are
    /// required; nil otherwise.
    public static func fromEngine(_ raw: BILJSONObject) -> BILReviewAsset? {
        guard let chainFamily = raw.str("chainFamily"),
              let assetAddress = raw.str("assetAddress"),
              let name = raw.str("name"),
              let symbol = raw.str("symbol"),
              let decimals = raw.int("decimals") else { return nil }
        return BILReviewAsset(chainFamily: chainFamily, chainId: raw.str("chainId"), assetAddress: assetAddress, name: name,
                              symbol: symbol, decimals: decimals, tokenProgram: raw.str("tokenProgram"),
                              rawAmount: raw.str("rawAmount"), displayAmount: raw.str("displayAmount"))
    }

    /// Exact (code units).
    public static func == (lhs: BILReviewAsset, rhs: BILReviewAsset) -> Bool {
        return BILPublicModelText.same(lhs.chainFamily, rhs.chainFamily) && BILPublicModelText.sameOptional(lhs.chainId, rhs.chainId)
            && BILPublicModelText.same(lhs.assetAddress, rhs.assetAddress) && BILPublicModelText.same(lhs.name, rhs.name)
            && BILPublicModelText.same(lhs.symbol, rhs.symbol) && lhs.decimals == rhs.decimals
            && BILPublicModelText.sameOptional(lhs.tokenProgram, rhs.tokenProgram)
            && BILPublicModelText.sameOptional(lhs.rawAmount, rhs.rawAmount)
            && BILPublicModelText.sameOptional(lhs.displayAmount, rhs.displayAmount)
    }
}

/// What an NFT-aware review is about (engine `display.assetKind`); unknown values are ignored with every NFT key.
public enum BILReviewAssetKind: String, CaseIterable {
    /// The method only exists for NFTs, or the NFT status is proven.
    case nft
    /// Ambiguous: a selector shared by ERC-20 and ERC-721, or a 0-decimal SPL transfer of 1.
    case nftOrToken
    /// ERC-1155: IDs may be fungible, never presented as an NFT.
    case multiToken
    /// A marketplace order signature (Seaport, LooksRare, Blur).
    case nftOrder

    public static func fromWire(_ s: String?) -> BILReviewAssetKind? {
        return BILPublicModelText.wire(s, BILReviewAssetKind.self)
    }
}

/// A bounded list of marketplace order lines ("You give" / "You receive" / "Also paid out"): at most
/// `BILPublicReviewDisplay.maxListLines` lines are kept; `more` counts the ones left out (the page shows a localized
/// "+N more (see Details)" line; the full values stay in the details).
public struct BILFlowLines: Equatable {
    public let lines: [String]
    public let more: Int

    public var isEmpty: Bool {
        return lines.isEmpty
    }

    public static let empty = BILFlowLines(lines: [], more: 0)

    /// Exact (code units, element-wise).
    public static func == (lhs: BILFlowLines, rhs: BILFlowLines) -> Bool {
        return BILPublicModelText.sameList(lhs.lines, rhs.lines) && lhs.more == rhs.more
    }
}

/// The three order lists of an NFT order review, in reading order.
public enum BILFlowKind {
    case give, receive, others
}

/// The structured headline the engine builds from the parsed signing bytes (`review.display`). The original keys are
/// read leniently; the NFT keys are type-checked, size-bounded and read only together with a recognised `assetKind`
/// (fail closed: no kind → no NFT box at all). Amounts are decimal strings.
///
/// `action` is the engine action (`Send`, `Approve All NFTs`, …), mapped to a localized label by the vocabulary.
public struct BILPublicReviewDisplay: Equatable {
    /// Most order lines kept per list (the last slot becomes the "+N more" count).
    public static let maxListLines = 32
    /// Longest identifier kept (UTF-16 units); longer list lines are cut in the middle.
    public static let maxStringLength = 300

    public let action: String
    public let amount: String?
    public let symbol: String?
    public let headline: String?
    public let counterpartyLabel: String?
    public let counterparty: String?
    public let fee: String?
    public let note: String?
    public let assetKind: BILReviewAssetKind?
    public let assetContract: String?
    public let assetContractLabel: String?
    public let tokenId: String?
    public let give: BILFlowLines
    public let receive: BILFlowLines
    public let others: BILFlowLines

    public init(action: String, amount: String? = nil, symbol: String? = nil, headline: String? = nil,
         counterpartyLabel: String? = nil, counterparty: String? = nil, fee: String? = nil, note: String? = nil,
         assetKind: BILReviewAssetKind? = nil, assetContract: String? = nil, assetContractLabel: String? = nil,
         tokenId: String? = nil, give: BILFlowLines = .empty, receive: BILFlowLines = .empty, others: BILFlowLines = .empty) {
        self.action = action
        self.amount = amount
        self.symbol = symbol
        self.headline = headline
        self.counterpartyLabel = counterpartyLabel
        self.counterparty = counterparty
        self.fee = fee
        self.note = note
        self.assetKind = assetKind
        self.assetContract = assetContract
        self.assetContractLabel = assetContractLabel
        self.tokenId = tokenId
        self.give = give
        self.receive = receive
        self.others = others
    }

    public var isNft: Bool {
        return assetKind != nil
    }

    /// The full token ID when neither the headline nor the amount already shows it as `#<id>` (then the summary shows
    /// it separately); nil otherwise.
    public var summaryTokenId: String? {
        guard let id = tokenId else { return nil }
        if !isNft { return nil }
        let texts = [headline, amount].compactMap { $0 }
        let shown = texts.contains { BILPublicReviewDisplay.textShowsTokenId($0, id) }
        return shown ? nil : id
    }

    /// The summary shows the contract / token ID box.
    public var showsAssetBox: Bool {
        return isNft && (assetContract != nil || summaryTokenId != nil)
    }

    /// Non-empty order lists in reading order (give, receive, others); NFT reviews only.
    public var flowSections: [(kind: BILFlowKind, lines: BILFlowLines)] {
        if !isNft { return [] }
        let all: [(kind: BILFlowKind, lines: BILFlowLines)] = [(kind: .give, lines: give), (kind: .receive, lines: receive),
                                                               (kind: .others, lines: others)]
        return all.filter { !$0.lines.isEmpty }
    }

    /// Reads `review.display`; nil when absent or without a string `action`.
    public static func fromEngine(_ raw: BILJSONObject?) -> BILPublicReviewDisplay? {
        guard let raw = raw, let action = raw.str("action") else { return nil }
        let amount = raw.str("amount"), symbol = raw.str("symbol"), headline = raw.str("headline")
        let counterpartyLabel = raw.str("counterpartyLabel"), counterparty = raw.str("counterparty")
        let fee = raw.str("fee"), note = raw.str("note")
        guard let kind = BILReviewAssetKind.fromWire(raw.str("assetKind")) else {
            return BILPublicReviewDisplay(action: action, amount: amount, symbol: symbol, headline: headline,
                                          counterpartyLabel: counterpartyLabel, counterparty: counterparty, fee: fee, note: note)
        }
        return BILPublicReviewDisplay(action: action, amount: amount, symbol: symbol, headline: headline,
                                      counterpartyLabel: counterpartyLabel, counterparty: counterparty, fee: fee, note: note,
                                      assetKind: kind,
                                      assetContract: boundedValue(raw["assetContract"]),
                                      assetContractLabel: boundedValue(raw["assetContractLabel"]),
                                      tokenId: boundedValue(raw["tokenId"]),
                                      give: boundedLines(raw["give"]),
                                      receive: boundedLines(raw["receive"]),
                                      others: boundedLines(raw["others"]))
    }

    /// An identifier is shown whole or not at all: a non-string, blank (Kotlin whitespace only) or over-long
    /// (> 300 UTF-16 units) value is dropped, never cut.
    public static func boundedValue(_ value: BILJSONValue?) -> String? {
        guard let text = value?.stringValue else { return nil }
        if BILPublicModelText.isBlank(text) || text.utf16.count > maxStringLength { return nil }
        return text
    }

    /// A list is all strings or ignored. Blank lines are dropped, an over-long line is cut in the middle (start and
    /// end stay), more than `maxListLines` lines keep the first `maxListLines − 1` and count the rest.
    public static func boundedLines(_ value: BILJSONValue?) -> BILFlowLines {
        guard let array = value?.arrayValue else { return .empty }
        var strings = [String]()
        strings.reserveCapacity(array.count)
        for element in array {
            guard let s = element.stringValue else { return .empty }
            strings.append(s)
        }
        let lines = strings.filter { !BILPublicModelText.isBlank($0) }.map(boundedLine)
        if lines.count <= maxListLines { return BILFlowLines(lines: lines, more: 0) }
        let shown = Array(lines.prefix(maxListLines - 1))
        return BILFlowLines(lines: shown, more: lines.count - shown.count)
    }

    /// Cuts an over-long line in the middle with "…": the amount (start) and the recipient (end) both stay. Never
    /// splits a surrogate pair (an emoji in an NFT name) at either cut. Lengths in UTF-16 units.
    public static func boundedLine(_ line: String) -> String {
        let units = Array(line.utf16)
        if units.count <= maxStringLength { return line }
        let head = (maxStringLength - 1) / 2
        var start = Array(units[0..<head])
        if let last = start.last, BILPublicModelText.isHighSurrogate(last) { start.removeLast() }
        let tailCount = maxStringLength - 1 - head
        var end = Array(units[(units.count - tailCount)...])
        if let first = end.first, BILPublicModelText.isLowSurrogate(first) { end.removeFirst() }
        return String(decoding: start, as: UTF16.self) + "\u{2026}" + String(decoding: end, as: UTF16.self)
    }

    /// True when `text` shows the whole `id` the way the engine writes IDs: `#<id>` not followed by another ASCII digit
    /// (`#12345` does not show token 1234). Code-unit search.
    public static func textShowsTokenId(_ text: String, _ id: String) -> Bool {
        if id.isEmpty { return false }
        let hay = Array(text.utf16)
        let needle = [UInt16(0x23)] + Array(id.utf16)        // "#" + id
        var from = 0
        while true {
            guard let at = BILPublicModelText.indexOf(needle, in: hay, from: from) else { return false }
            let end = at + needle.count
            if end == hay.count || !(hay[end] >= 0x30 && hay[end] <= 0x39) { return true }
            from = end
        }
    }

    /// Exact (code units), every key.
    public static func == (lhs: BILPublicReviewDisplay, rhs: BILPublicReviewDisplay) -> Bool {
        typealias T = BILPublicModelText
        return T.same(lhs.action, rhs.action) && T.sameOptional(lhs.amount, rhs.amount) && T.sameOptional(lhs.symbol, rhs.symbol)
            && T.sameOptional(lhs.headline, rhs.headline) && T.sameOptional(lhs.counterpartyLabel, rhs.counterpartyLabel)
            && T.sameOptional(lhs.counterparty, rhs.counterparty) && T.sameOptional(lhs.fee, rhs.fee)
            && T.sameOptional(lhs.note, rhs.note) && lhs.assetKind == rhs.assetKind
            && T.sameOptional(lhs.assetContract, rhs.assetContract) && T.sameOptional(lhs.assetContractLabel, rhs.assetContractLabel)
            && T.sameOptional(lhs.tokenId, rhs.tokenId) && lhs.give == rhs.give && lhs.receive == rhs.receive
            && lhs.others == rhs.others
    }
}

/// The engine review of one request (`review` / `plan.review`).
///
/// - `chain`: nil for a chain this app does not know (the plan is then not signable).
/// - `warnings`: every engine warning, in order — never filtered or truncated; unknown ones are shown verbatim in English.
/// - `requestHash`: the engine's hash of the normalized request (the "request fingerprint"); "" when absent.
/// - `canSign`: the engine's own flag (true for every reviewed request today).
/// - `raw`: the review object exactly as the engine produced it.
public struct BILPublicReview: Equatable {
    public let chain: BILPsChain?
    public let title: String
    public let summary: String
    public let fields: [BILReviewField]
    public let warnings: [String]
    public let requestHash: String
    public let canSign: Bool
    public let decodeStatus: BILDecodeStatus
    public let riskLevel: BILRiskLevel
    public let network: BILReviewNetwork?
    public let display: BILPublicReviewDisplay?
    public let asset: BILReviewAsset?
    public let raw: BILJSONObject

    /// The consent rule of the review alone: incompletely decoded or high-risk requests need an explicit per-request
    /// checkbox before signing (the merged rule is `BILPublicPolicyResult.requiresAcknowledgement`).
    public var requiresAcknowledgement: Bool {
        return decodeStatus != .fullyDecoded || riskLevel == .high
    }

    /// The network name to show: the engine's network, else its "Network" field, else the chain's brand name, else "".
    public var networkName: String {
        if let network = network { return network.name }
        if let field = fields.first(where: { BILPublicModelText.same($0.label, "Network") }) { return field.value }
        return chain?.brandName ?? ""
    }

    /// Reads an engine review object. Lenient like Android (missing texts read as empty, non-object fields are
    /// skipped, non-string values read as their JSON text), fail closed on status / risk; never throws today (the
    /// signature is the design's — the coordinator checks requestHash / chain / fields itself, R5 §1.4).
    public static func fromEngine(_ raw: BILJSONObject) throws -> BILPublicReview {
        var fields = [BILReviewField]()
        for (i, element) in (raw.arr("fields") ?? []).enumerated() {
            guard let field = element.objectValue else { continue }
            fields.append(BILReviewField(index: i, label: field.str("label") ?? "", value: field["value"]?.displayText ?? ""))
        }
        let warnings = (raw.arr("warnings") ?? []).map { $0.displayText }
        var network: BILReviewNetwork?
        if let n = raw.obj("network"), let name = n.str("name") {
            network = BILReviewNetwork(chainId: n.str("chainId"), name: name, symbol: n.str("symbol"))
        }
        return BILPublicReview(
            chain: BILPsChain.fromWire(raw.str("chain")),
            title: raw.str("title") ?? "",
            summary: raw.str("summary") ?? "",
            fields: fields,
            warnings: warnings,
            requestHash: raw.str("requestHash") ?? "",
            canSign: raw.bool("canSign") ?? false,
            decodeStatus: BILDecodeStatus.fromWire(raw.str("decodeStatus")),
            riskLevel: BILRiskLevel.fromWire(raw.str("riskLevel")),
            network: network,
            display: BILPublicReviewDisplay.fromEngine(raw.obj("display")),
            asset: raw.obj("asset").flatMap { BILReviewAsset.fromEngine($0) },
            raw: raw)
    }
}

// MARK: - Shared exact-text helpers of the Model files

/// Kotlin-compatible string rules used by the engine-result models (code-unit equality, ASCII case folding, Kotlin
/// `isBlank`, UTF-16 search) and the exact `==` of the Model value types.
///
/// Model-private by intent (Swift has no folder scope, hence `internal`): it is **not** a §3 contract and may change
/// with the Model files. Other work packages use WP1's `BILJSONExact.equal` (exact string equality) and
/// `BILKotlinText` (Kotlin text rules) instead.
enum BILPublicModelText {

    /// Exact equality (Kotlin `String.equals`; never Swift canonical equivalence) = WP1's `BILJSONExact.equal`, so the
    /// models and the JSON tree agree by construction. (Its UTF-8 compare equals a UTF-16 code-unit compare for every
    /// Swift `String`: a lone surrogate is repaired to U+FFFD when the string is made.)
    static func same(_ a: String, _ b: String) -> Bool {
        return BILJSONExact.equal(a, b)
    }

    /// `same` for optionals: both nil, or both present and exactly equal.
    static func sameOptional(_ a: String?, _ b: String?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (x?, y?): return same(x, y)
        default: return false
        }
    }

    /// Element-wise `same` (Kotlin `List<String>` equality).
    static func sameList(_ a: [String], _ b: [String]) -> Bool {
        return a.count == b.count && zip(a, b).allSatisfy { same($0, $1) }
    }

    /// Element-wise exact equality of text arguments (`.text` by code units, `.int` by value; any other case — none
    /// today — by its own `==`).
    static func sameArgs(_ a: [BILTextArg], _ b: [BILTextArg]) -> Bool {
        guard a.count == b.count else { return false }
        for (x, y) in zip(a, b) {
            switch (x, y) {
            case let (.text(p), .text(q)):
                if !same(p, q) { return false }
            default:
                if x != y { return false }
            }
        }
        return true
    }

    /// Exact equality of optional sign errors: `BILPublicSignError.==` (WP1, every field) and, on top of it, its texts
    /// by code units (key, arguments, code, engine message).
    static func sameError(_ a: BILPublicSignError?, _ b: BILPublicSignError?) -> Bool {
        switch (a, b) {
        case (nil, nil):
            return true
        case let (x?, y?):
            return x == y && same(x.key, y.key) && sameArgs(x.args, y.args) && sameOptional(x.code, y.code)
                && sameOptional(x.engineMessage, y.engineMessage)
        default:
            return false
        }
    }

    /// Kotlin `equals(other, ignoreCase = true)` for the hex identifiers it is used on: same UTF-16 length and every
    /// unit equal after ASCII case folding (a non-ASCII unit must match exactly).
    static func sameIgnoringASCIICase(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf16), y = Array(b.utf16)
        guard x.count == y.count else { return false }
        for i in 0..<x.count where fold(x[i]) != fold(y[i]) {
            return false
        }
        return true
    }

    /// `s` is one of `items` (exact).
    static func contains(_ items: [String], _ s: String) -> Bool {
        return items.contains { same($0, s) }
    }

    /// Kotlin `distinct()` (first occurrence kept, exact equality).
    static func distinct(_ items: [String]) -> [String] {
        var seen = Set<[UInt16]>()
        var out = [String]()
        for s in items where seen.insert(Array(s.utf16)).inserted {
            out.append(s)
        }
        return out
    }

    /// Kotlin `CharSequence.isBlank()`: empty or only Kotlin whitespace (UTF-16 units).
    static func isBlank(_ s: String) -> Bool {
        return s.utf16.allSatisfy { BILKotlinText.isWhitespace($0) }
    }

    /// The case of `E` whose raw value equals `s` exactly; nil for nil / unknown.
    static func wire<E: RawRepresentable & CaseIterable>(_ s: String?, _ type: E.Type) -> E? where E.RawValue == String {
        guard let s = s else { return nil }
        return E.allCases.first { same($0.rawValue, s) }
    }

    /// Kotlin `indexOf(needle, from)` on UTF-16 units; nil when absent.
    static func indexOf(_ needle: [UInt16], in hay: [UInt16], from: Int) -> Int? {
        if needle.isEmpty { return from <= hay.count ? max(from, 0) : nil }
        var i = max(from, 0)
        while i + needle.count <= hay.count {
            var match = true
            for k in 0..<needle.count where hay[i + k] != needle[k] {
                match = false
                break
            }
            if match { return i }
            i += 1
        }
        return nil
    }

    static func isHighSurrogate(_ u: UInt16) -> Bool {
        return u >= 0xD800 && u <= 0xDBFF
    }

    static func isLowSurrogate(_ u: UInt16) -> Bool {
        return u >= 0xDC00 && u <= 0xDFFF
    }

    private static func fold(_ u: UInt16) -> UInt16 {
        return (u >= 0x41 && u <= 0x5A) ? u + 0x20 : u
    }
}
