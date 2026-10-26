//  BILTronLinkCollector.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Public protocol (cold signer) — reassembles one TronLink request from its QR frames, pure host code, never the engine.
//  Port of Android `core/publicsigner/.../scan/TronLinkCollector.kt` (R4 §10). A single QR completes at once. Parts
//  (`cN` of `tN`, 2 ≤ `tN` ≤ 64) may come in any order; a repeat is ignored. Refused as another request: the same `cN`
//  with another text, another `tN`, a single QR after a part, first and last parts naming different addresses. Limits: one
//  piece ≤ 4,096 UTF-16 units, the joined text ≤ 131,072. Not thread-safe; one per scan / paste. Nothing is logged.
//

import Foundation

/// A complete TronLink request, from one QR or reassembled from its parts.
struct BILTronLinkRequest: Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// The object the answer echoes: the scanned JSON of a single QR as it is; for a split request the reassembled one
    /// (`address` of part 1 — else of the last part —, `type` / `alpha` / `tokenId` of the last part, every other key of
    /// the parts in first-seen order, `cN` / `tN` removed, `hexList` = the joined entries, last).
    let bean: BILJSONObject
    /// The entries (transactions as hex of a full `Transaction`, or the message of a message type).
    let hexList: [String]
    /// TronLink's page type.
    let type: Int
    /// The account the request is for (nil when TronLink sent none: refused by the mapper).
    let address: String?
    let alpha: String?
    let tokenId: String?
    /// It came in numbered parts.
    let wasSplit: Bool

    /// The request of one complete (unsplit) QR. A part is not a request: callers check `isPart` first (Android
    /// `require(!frame.isPart)`); a part still fails closed here, never traps: it yields a request with no entries, which
    /// every consumer refuses (the mapper as malformed).
    static func of(_ frame: BILTronLinkFrame) -> BILTronLinkRequest {
        return BILTronLinkRequest(bean: frame.json, hexList: frame.isPart ? [] : frame.hexList, type: frame.type,
                                  address: frame.address, alpha: frame.alpha, tokenId: frame.tokenId, wasSplit: false)
    }

    /// Counts only.
    var description: String {
        return "BILTronLinkRequest(type: \(type), entries: \(hexList.count), split: \(wasSplit))"
    }

    var debugDescription: String {
        return description
    }

    /// No children: `dump` / `Mirror` show no entry, address or bean.
    var customMirror: Mirror {
        return Mirror(self, children: [:])
    }

    /// Exact (code-unit) equality; the bean compares as a map (kotlinx).
    static func == (lhs: BILTronLinkRequest, rhs: BILTronLinkRequest) -> Bool {
        return lhs.bean == rhs.bean && BILScanText.same(lhs.hexList, rhs.hexList) && lhs.type == rhs.type
            && BILScanText.same(lhs.address, rhs.address) && BILScanText.same(lhs.alpha, rhs.alpha)
            && BILScanText.same(lhs.tokenId, rhs.tokenId) && lhs.wasSplit == rhs.wasSplit
    }
}

final class BILTronLinkCollector: CustomStringConvertible {

    /// The result of `add`.
    enum Step: Equatable {
        /// `received` of `total` parts so far.
        case partial(received: Int, total: Int)
        case complete(BILTronLinkRequest)
    }

    /// Parts of one request (the gate's `maxTronLinkParts`).
    static let maxParts = 64
    /// UTF-16 units of one part's piece (TronLink cuts at 1000).
    static let maxPieceChars = 4_096
    /// TronLink's entry separator.
    static let separator = "&&&"

    init() {}

    /// Parts received so far (0 before the first).
    var received: Int {
        return pieces.count
    }

    /// Adds one frame; throws `BILOtherWalletRequestError` for a frame of another request or beyond the limits.
    func add(_ frame: BILTronLinkFrame) throws -> Step {
        if !frame.isPart {
            if !pieces.isEmpty { throw BILOtherWalletRequestError.otherRequest }
            return .complete(BILTronLinkRequest.of(frame))
        }
        // A part always carries both numbers and exactly one piece (BILTronLinkQrFormat.parse).
        guard let tN = frame.tN, let cN = frame.cN, frame.hexList.count == 1 else { throw BILOtherWalletRequestError.malformed() }
        if tN > BILTronLinkCollector.maxParts { throw BILOtherWalletRequestError.tooLarge }
        if total != 0 && tN != total { throw BILOtherWalletRequestError.otherRequest }
        let piece = frame.hexList[0]
        if piece.utf16.count > BILTronLinkCollector.maxPieceChars { throw BILOtherWalletRequestError.tooLarge }
        if let seen = pieces[cN] {
            if !BILJSONExact.equal(seen.hexList[0], piece) || seen.json != frame.json { throw BILOtherWalletRequestError.otherRequest }
            return .partial(received: pieces.count, total: total)
        }
        total = tN
        pieces[cN] = frame
        if pieces.count < total { return .partial(received: pieces.count, total: total) }
        return .complete(try join())
    }

    /// Counts only.
    var description: String {
        return "BILTronLinkCollector(received: \(pieces.count), total: \(total))"
    }

    // MARK: - Private

    /// Keys TronLink writes on the last part only (`type` is `0` on the others).
    private static let lastPartKeys = ["type", "alpha", "tokenId"]

    private var total = 0
    private var pieces = [Int: BILTronLinkFrame]()

    private func join() throws -> BILTronLinkRequest {
        var ordered = [BILTronLinkFrame]()
        ordered.reserveCapacity(total)
        for n in 1...total {
            guard let part = pieces[n] else { throw BILOtherWalletRequestError.malformed() }
            ordered.append(part)
        }
        guard let first = ordered.first, let last = ordered.last else { throw BILOtherWalletRequestError.malformed() }
        // TronLink writes the address on the first and the last part: they must agree.
        if let a = first.address, let b = last.address, !BILJSONExact.equal(a, b) { throw BILOtherWalletRequestError.otherRequest }
        var joined = ""
        var joinedLength = 0
        for part in ordered {
            let piece = part.hexList[0]
            joined += piece
            joinedLength += piece.utf16.count
            if joinedLength > BILTronLinkQrFormat.maxRequestChars { throw BILOtherWalletRequestError.tooLarge }
        }
        var entries = BILKotlinText.split(joined, separator: BILTronLinkCollector.separator)
        if entries.count > 1 && entries[entries.count - 1].isEmpty { entries.removeLast() }
        if entries.isEmpty || entries.contains(where: { $0.isEmpty }) || entries.count > BILTronLinkQrFormat.maxEntries {
            throw BILOtherWalletRequestError.malformed()
        }
        let address = first.address ?? last.address
        var bean = BILJSONObject()
        for part in ordered {
            for entry in part.json.entries {
                if BILJSONExact.equal(entry.key, "cN") || BILJSONExact.equal(entry.key, "tN") || BILJSONExact.equal(entry.key, "hexList")
                    || bean.contains(entry.key) {
                    continue
                }
                bean.set(entry.key, entry.value)
            }
        }
        // The fields of the request itself come from where TronLink writes them.
        if let a = address { bean.set("address", .string(a)) }
        for key in BILTronLinkCollector.lastPartKeys {
            if let value = last.json[key] {
                bean.set(key, value)
            } else {
                bean.remove(key)
            }
        }
        bean.set("hexList", .array(entries.map { BILJSONValue.string($0) }))
        return BILTronLinkRequest(bean: bean, hexList: entries, type: last.type, address: address, alpha: last.alpha,
                                  tokenId: last.tokenId, wasSplit: true)
    }
}
