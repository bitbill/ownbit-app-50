//  BILUtxoSignDatas.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Strict reading of the numbers a UTXO `bb_sign:` request signs with (security review 2026-10-13 F01; port of Android
//  `A:core/chain/.../utxo/UtxoSignDatas.kt` + the key table of `UtxoChainProfile.kt` at b8c70c25; design D-31). The coin's
//  `TransactionBuilder` re-serializes `signDatas` with `JSONSerialization` and its JS bundle `JSON.parse`s the text, so a
//  value Swift reads one way can reach the bundle as another number: `"satoshis": 100000.0000000000000000001` is 100000 in
//  JS (a SegWit input would be signed for that amount), integers above 2^53 are rounded. Everything the app checks an input
//  or an output by (the signed-outpoint memory, the review page) must be the number the bundle signs.
//
//  Rules, per input (txid / index keys by `BILUtxoChainProfile.inputStyle`, amount `inputAmountKey`) and per output
//  (`outputAmountKey`):
//  - the txid is a JSON **string** of exactly 64 hex digits (no `0x`, no blanks);
//  - the index and every amount are JSON **number** tokens of plain decimal digits `0|[1-9][0-9]*` (no sign, fraction,
//    exponent or leading zero; a numeric string, a boolean, `null` or a missing key is refused), at most 19 characters,
//    the index in 0…0xFFFFFFFF, an amount in 0…2^53 − 1 (exact in JS);
//  - `inputs` is a non-empty array of objects, `outputs` an array of objects.
//  Anything else refuses the **whole** request (never "skip the input": a skipped input would still be signed).
//  `canonical` rewrites the values as read (txid lower case, integers as JSON integers); every other key is kept.
//  Pure Foundation (macOS-harness testable); never logs values.
//

import Foundation

/// The `signDatas` shape of one UTXO coin iOS cold-signs through `bb_sign:` (keys read from each coin's
/// `Modules/Public/Helper/*TransactionBuilder.swift` + the input classes it uses).
public struct BILUtxoChainProfile: Equatable {

    public enum InputStyle: Equatable {
        /// `BTCInput.toDictionary`: `txHash` / `index` (BTC).
        case btc
        /// `BCHInput.toDictionary` and subclasses: `txid` / `vout`.
        case script
    }

    /// iOS `CoinType` raw value.
    public let coinTypeRaw: Int
    public let inputStyle: InputStyle
    /// Amount key of the output dictionaries (`BTCOutput.amountKey`: "amount"; ZEN "satoshis").
    public let outputAmountKey: String
    /// Amount key of the input dictionaries (`BTCInput` / `BCHInput.amountKey()`: "satoshis").
    public let inputAmountKey: String

    public init(coinTypeRaw: Int, inputStyle: InputStyle, outputAmountKey: String = "amount", inputAmountKey: String = "satoshis") {
        self.coinTypeRaw = coinTypeRaw
        self.inputStyle = inputStyle
        self.outputAmountKey = outputAmountKey
        self.inputAmountKey = inputAmountKey
    }

    public var txidKey: String { return inputStyle == .btc ? "txHash" : "txid" }
    public var voutKey: String { return inputStyle == .btc ? "index" : "vout" }

    /// Android's 8 rows (BTC btc/amount; BCH, LTC, DOGE, DASH, DGB, ZEC script/amount; ZEN script/satoshis) by iOS
    /// `CoinType` raw value. Package difference (product decision: supported chains only): the app's iOS-only rows of coins
    /// outside the package's chain list — DCR (6, input amount "atoms"), Omni USDT (7), RVN (12), XZC (13), BSV (18) — are not
    /// here, so their requests are not checked by this rule (the package has no signer for them either).
    public static let all: [BILUtxoChainProfile] = [
        BILUtxoChainProfile(coinTypeRaw: 0, inputStyle: .btc),                                 // btc
        BILUtxoChainProfile(coinTypeRaw: 3, inputStyle: .script),                              // bch
        BILUtxoChainProfile(coinTypeRaw: 4, inputStyle: .script),                              // ltc
        BILUtxoChainProfile(coinTypeRaw: 8, inputStyle: .script),                              // dash
        BILUtxoChainProfile(coinTypeRaw: 9, inputStyle: .script),                              // doge
        BILUtxoChainProfile(coinTypeRaw: 10, inputStyle: .script),                             // dgb
        BILUtxoChainProfile(coinTypeRaw: 11, inputStyle: .script, outputAmountKey: "satoshis"),// zen
        BILUtxoChainProfile(coinTypeRaw: 19, inputStyle: .script),                             // zec
    ]

    /// BTC (`CoinType.btc`): the only coin that shares the signed-outpoint memory (D-31).
    public static let bitcoinCoinTypeRaw = 0

    /// nil = not a UTXO coin (no check).
    public static func of(coinTypeRaw: Int) -> BILUtxoChainProfile? {
        return all.first { $0.coinTypeRaw == coinTypeRaw }
    }
}

public enum BILUtxoSignDatas {

    /// Largest integer JS represents exactly (`Number.MAX_SAFE_INTEGER`).
    public static let maxSafeInteger: UInt64 = 9_007_199_254_740_991
    /// Largest output index of a transaction (`u32`).
    public static let maxVout: UInt64 = 0xFFFF_FFFF

    /// One input as the app and the bundle both read it: `txid` lower-case hex as explorers write it.
    public struct Input: Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
        public let txid: String
        public let vout: UInt32
        public let sats: UInt64

        /// Prints / dumps nothing of the outpoint or the amount (C-LOG-1).
        public var description: String { return "Input" }
        public var debugDescription: String { return description }
        public var customMirror: Mirror { return Mirror(self, children: [], displayStyle: .struct) }
    }

    /// The strictly read numbers of a request: its inputs in order and every output amount in order.
    public struct Numbers: Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
        public let inputs: [Input]
        public let outputAmounts: [UInt64]

        /// Prints / dumps nothing of the inputs or the amounts (C-LOG-1).
        public var description: String { return "Numbers" }
        public var debugDescription: String { return description }
        public var customMirror: Mirror { return Mirror(self, children: [], displayStyle: .struct) }
    }

    /// Strict inputs in order, or nil if any input (or the list) is not read exactly (rules above). Never "skip".
    public static func inputs(_ p: BILUtxoChainProfile, _ signDatas: BILJSONObject) -> [Input]? {
        guard let list = signDatas["inputs"]?.arrayValue, !list.isEmpty else { return nil }
        var out = [Input]()
        out.reserveCapacity(list.count)
        for element in list {
            guard let input = element.objectValue,
                  let txid = txid(input[p.txidKey]),
                  let vout = integer(input[p.voutKey], max: maxVout),
                  let sats = integer(input[p.inputAmountKey], max: maxSafeInteger) else { return nil }
            out.append(Input(txid: txid, vout: UInt32(vout), sats: sats))
        }
        return out
    }

    /// Inputs and output amounts read strictly (nil also when `outputs` is not an array of objects or an amount is not
    /// exact).
    public static func numbers(_ p: BILUtxoChainProfile, _ signDatas: BILJSONObject) -> Numbers? {
        guard let ins = inputs(p, signDatas), let list = signDatas["outputs"]?.arrayValue else { return nil }
        var amounts = [UInt64]()
        amounts.reserveCapacity(list.count)
        for element in list {
            guard let output = element.objectValue,
                  let amount = integer(output[p.outputAmountKey], max: maxSafeInteger) else { return nil }
            amounts.append(amount)
        }
        return Numbers(inputs: ins, outputAmounts: amounts)
    }

    /// `signDatas` with every input txid / vout / sats and every output amount rewritten as read (keys keep their
    /// position, all other keys untouched), or nil (also when outputs is not an array of objects).
    public static func canonical(_ p: BILUtxoChainProfile, _ signDatas: BILJSONObject) -> BILJSONObject? {
        guard let n = numbers(p, signDatas),
              let rawInputs = signDatas["inputs"]?.arrayValue, rawInputs.count == n.inputs.count,
              let rawOutputs = signDatas["outputs"]?.arrayValue, rawOutputs.count == n.outputAmounts.count else { return nil }
        var inputs = [BILJSONValue]()
        inputs.reserveCapacity(rawInputs.count)
        for (i, element) in rawInputs.enumerated() {
            guard var o = element.objectValue else { return nil }
            let read = n.inputs[i]
            o.set(p.txidKey, .string(read.txid))
            o.set(p.voutKey, .int(read.vout))
            o.set(p.inputAmountKey, .int(read.sats))
            inputs.append(.object(o))
        }
        var outputs = [BILJSONValue]()
        outputs.reserveCapacity(rawOutputs.count)
        for (i, element) in rawOutputs.enumerated() {
            guard var o = element.objectValue else { return nil }
            o.set(p.outputAmountKey, .int(n.outputAmounts[i]))
            outputs.append(.object(o))
        }
        var out = signDatas
        out.set("inputs", .array(inputs))
        out.set("outputs", .array(outputs))
        return out
    }

    /// Outpoint-memory claims of every canonical input (txid bytes reversed = transaction byte order); nil if the count
    /// differs from `inputCount` (the inputs the builder gets) or a txid does not decode.
    public static func claims(_ inputs: [Input], inputCount: Int) -> [BILSignedOutpointMemory.Claim]? {
        guard inputs.count == inputCount else { return nil }
        var out = [BILSignedOutpointMemory.Claim]()
        out.reserveCapacity(inputs.count)
        for input in inputs {
            guard let bytes = BILPublicHex.decode(input.txid), bytes.count == 32 else { return nil }
            out.append(BILSignedOutpointMemory.Claim(txid: Array(bytes.reversed()), vout: input.vout, sats: input.sats))
        }
        return out
    }

    /// The `[String: Any]` `signDatas` the iOS builders serialize, with the read numbers written in: input
    /// `txid` / `txHash` lower case, `vout` / `index`, input and output amounts as `NSNumber(value: Int64)` (so
    /// `JSONSerialization` writes integer tokens). Every other key untouched. nil when the dictionary's inputs / outputs
    /// are not arrays of objects of the same counts as `numbers`.
    public static func patched(_ signDatas: [String: Any], _ p: BILUtxoChainProfile, _ n: Numbers) -> [String: Any]? {
        guard let rawInputs = signDatas["inputs"] as? [Any], rawInputs.count == n.inputs.count,
              let rawOutputs = signDatas["outputs"] as? [Any], rawOutputs.count == n.outputAmounts.count else { return nil }
        var inputs = [[String: Any]]()
        inputs.reserveCapacity(rawInputs.count)
        for (i, element) in rawInputs.enumerated() {
            guard var d = element as? [String: Any] else { return nil }
            let read = n.inputs[i]
            d[p.txidKey] = read.txid
            d[p.voutKey] = NSNumber(value: Int64(read.vout))
            d[p.inputAmountKey] = NSNumber(value: Int64(read.sats))
            inputs.append(d)
        }
        var outputs = [[String: Any]]()
        outputs.reserveCapacity(rawOutputs.count)
        for (i, element) in rawOutputs.enumerated() {
            guard var d = element as? [String: Any] else { return nil }
            d[p.outputAmountKey] = NSNumber(value: Int64(n.outputAmounts[i]))
            outputs.append(d)
        }
        var out = signDatas
        out["inputs"] = inputs
        out["outputs"] = outputs
        return out
    }

    // MARK: - Private

    /// A JSON string of exactly 64 hex digits → lower case; anything else nil.
    private static func txid(_ value: BILJSONValue?) -> String? {
        guard let s = value?.stringValue else { return nil }
        let u = Array(s.utf8)
        guard u.count == 64 else { return nil }
        var lower = [UInt8]()
        lower.reserveCapacity(64)
        for c in u {
            switch c {
            case 0x30...0x39, 0x61...0x66: lower.append(c)
            case 0x41...0x46: lower.append(c + 0x20)
            default: return nil
            }
        }
        return String(decoding: lower, as: UTF8.self)
    }

    /// A JSON number token `0|[1-9][0-9]*` of at most 19 characters, value ≤ `max`; anything else nil.
    private static func integer(_ value: BILJSONValue?, max: UInt64) -> UInt64? {
        guard let literal = value?.numberLiteral else { return nil }
        let u = Array(literal.utf8)
        guard !u.isEmpty, u.count <= 19, u.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }) else { return nil }
        if u.count > 1 && u[0] == 0x30 { return nil }
        var acc: UInt64 = 0
        for c in u {
            acc = acc * 10 + UInt64(c - 0x30)          // ≤ 19 digits: fits UInt64
        }
        return acc <= max ? acc : nil
    }
}
