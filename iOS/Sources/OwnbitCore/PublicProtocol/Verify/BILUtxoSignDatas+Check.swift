//  BILUtxoSignDatas+Check.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  The F01 rule for Ownbit's own cold-signing request `bb_sign:` (design D-31), with plain values: the refusal checked
//  at the scanner and on the cold-sign page, the patch of the request's `signDatas` with the canonical numbers (so the
//  review page and the coin's transaction builder see exactly the checked values), the BTC claims of the signed-outpoint
//  memory, and the texts of the internal BTC path. Port of the app's `BILUtxoSignDatas+App.swift`, where the same
//  functions took the app's `TransactionBuildDatas` (only its `signDatas` dictionary is read or changed) and returned
//  localized texts; here the refusal is a value (`Refusal`) and its text goes through `BILPublicText` (host localizer).
//
//  The decoded request text is parsed with `BILStrictJSON`: duplicate keys, a lone surrogate escape or any non-RFC JSON
//  refuses a UTXO request. Messages (`signDatas.destination == "signMessage"`) and non-UTXO coins are not checked here.
//  Pure Foundation.
//

import Foundation

extension BILUtxoSignDatas {

    /// The Ownbit-protocol signing request prefix (app `String.observer_sign`).
    public static let ownbitSignPrefix = "bb_sign:"
    /// `signDatas.destination` of a message request (app `OFFLINE_SIGNMESSAGE`).
    public static let signMessageDestination = "signMessage"

    /// Why a UTXO `bb_sign:` request is refused before the password.
    public enum Refusal: Equatable {
        /// Not strict JSON, no `signDatas` object, or a number that is not exactly what the builder would sign.
        case incorrect
        /// BTC: input `inputNumber` (1-based) claims another amount than this device already signed for that outpoint.
        case prevoutConflict(inputNumber: Int)
        /// BTC: the signed-outpoint memory cannot be read (transient or corrupt).
        case memoryUnavailable

        /// The alert text (app: "QR code format or content is incorrect" from UI.strings, `err.prevoutConflict`,
        /// `String.sendConfirmBuildTxFailed`).
        public var text: String {
            switch self {
            case .incorrect: return BILUtxoSignDatas.refusalText
            case .prevoutConflict(let n): return BILBitcoinSigningLock.Refusal.conflict(inputNumber: n).text
            case .memoryUnavailable: return BILBitcoinSigningLock.Refusal.memoryUnavailable.text
            }
        }
    }

    /// The text of a request that contradicts itself (the app's existing "QR code format or content is incorrect").
    public static var refusalText: String {
        return BILPublicText.string("QR code format or content is incorrect")
    }

    /// nil = acceptable, or not a UTXO `bb_sign:` (messages are skipped); else why it is refused. `datasText` = the decoded
    /// request JSON (the text after `bb_sign:`, decompressed). BTC: also the memory pre-check against `memory` (no lock).
    /// Synchronous (a small file read for BTC).
    public static func refusalReason(qrcode: String, datasText: String, coinTypeRaw: Int,
                                     memory: BILSignedOutpointMemory = .shared) -> Refusal? {
        guard BILPublicHex.hasASCIIPrefix(qrcode, ownbitSignPrefix),
              let profile = BILUtxoChainProfile.of(coinTypeRaw: coinTypeRaw) else { return nil }
        guard let request = BILStrictJSON.parseObject(datasText), let signDatas = request.obj("signDatas") else {
            BILPublicLog.code("utxo", "UTXO_REQUEST_NOT_STRICT")
            return .incorrect
        }
        if signDatas.str("destination") == signMessageDestination { return nil }
        guard let n = numbers(profile, signDatas), canonical(profile, signDatas) != nil else {
            BILPublicLog.code("utxo", "UTXO_NUMBER_NOT_EXACT")
            return .incorrect
        }
        guard profile.coinTypeRaw == BILUtxoChainProfile.bitcoinCoinTypeRaw else { return nil }
        guard let claims = claims(n.inputs, inputCount: signDatas["inputs"]?.arrayValue?.count ?? -1) else {
            return .incorrect
        }
        do {
            let conflicts = try memory.conflicts(claims.map { Optional($0) })
            if let first = conflicts.min() {
                BILPublicLog.code("utxo", "PREVOUT_CONFLICT")
                return .prevoutConflict(inputNumber: first + 1)
            }
        } catch {
            return .memoryUnavailable
        }
        return nil
    }

    /// `refusalReason(…)?.text` (the app's `refusal(qrcode:datasText:coinTypeRaw:memory:)`).
    public static func refusal(qrcode: String, datasText: String, coinTypeRaw: Int,
                               memory: BILSignedOutpointMemory = .shared) -> String? {
        return refusalReason(qrcode: qrcode, datasText: datasText, coinTypeRaw: coinTypeRaw, memory: memory)?.text
    }

    /// The request's `signDatas` dictionary (as the app's builders read it, `JSONSerialization` of the decoded text) with
    /// `inputs[i].{txid|txHash, vout|index, satoshis|atoms}` and `outputs[i].<amountKey>` replaced by the canonical values
    /// (`NSNumber(value: Int64)`, lower-case txid); nil = refuse (show `refusalText`). Also returns the BTC claims of every
    /// input (empty for other coins, messages and non-UTXO coins, which come back unchanged). Call only for `bb_sign:`.
    public static func checked(signDatas builderSignDatas: [String: Any], datasText: String, coinTypeRaw: Int)
        -> (signDatas: [String: Any], claims: [BILSignedOutpointMemory.Claim])? {
        guard let profile = BILUtxoChainProfile.of(coinTypeRaw: coinTypeRaw) else { return (builderSignDatas, []) }
        if (builderSignDatas["destination"] as? String) == signMessageDestination { return (builderSignDatas, []) }
        guard let request = BILStrictJSON.parseObject(datasText), let signDatas = request.obj("signDatas"),
              let n = numbers(profile, signDatas), canonical(profile, signDatas) != nil,
              let patchedSignDatas = patched(builderSignDatas, profile, n) else {
            BILPublicLog.code("utxo", "UTXO_NUMBER_NOT_EXACT")
            return nil
        }
        guard profile.coinTypeRaw == BILUtxoChainProfile.bitcoinCoinTypeRaw else { return (patchedSignDatas, []) }
        let builderInputs = (patchedSignDatas["inputs"] as? [[String: Any]])?.count ?? -1
        guard let claims = claims(n.inputs, inputCount: builderInputs) else { return nil }
        return (patchedSignDatas, claims)
    }
}

extension BILBitcoinSigningLock.Refusal {

    /// The alert text: a conflict → `err.prevoutConflict` (1-based input); memory unreadable, not written, or the builder
    /// timed out → the app's `String.sendConfirmBuildTxFailed` (key `SendC.confirm.buildTxFailed`).
    public var text: String {
        switch self {
        case .conflict(let n):
            return BILPublicSignerErrors.prevoutConflict(inputNumber: n).text
        case .memoryUnavailable, .recordFailed, .timedOut:
            return BILPublicText.string("SendC.confirm.buildTxFailed")
        }
    }
}
