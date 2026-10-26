//  BILPsbtMaps.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Public protocol (cold signer) — the key-value maps of a PSBT (BIP-174 v0 / BIP-370 v2), read natively and
//  independently of the engine that signs it (port of Android `PS:verify/PsbtMaps.kt`; R5 §3.4; C-BTC-3 / C-BTC-8).
//  Only structure is read — scripts and signatures are the engine's.
//
//  - `parse`: magic, global / input / output maps (canonical compact sizes ≤ 131 072, no duplicate keys, nothing after
//    the last map), ≤ `maxBytes`, 1…`maxInOut` inputs and outputs; v0 needs exactly the global unsigned transaction
//    (legacy serialization, empty script sigs), v2 the BIP-370 fields.
//  - `unsignedTx`: the bytes the engine's `signingBytesDigest` hashes (`sha256(tx.unsignedTx)` of `@scure/btc-signer`):
//    v0 the global transaction as given, v2 the transaction rebuilt with the BIP-370 lock-time rule.
//  - `outputDerivations`: BIP-32 / Taproot BIP-32 derivations of the outputs (the change-index bound).
//  - `diff`: what signing may change — signatures of the task keys on the task inputs, nothing else.
//
//  Pure (Foundation + the WP2 crypto helpers). Errors are `BILVerifyError` with log-safe check names; nothing logged.
//  Immutable after `parse`, so safe to share across threads. Call off-main (`BILPublicBackground.run`, design §1.4):
//  `keyPathOf` / `diff` may compute BIP-86 tweaks (`BILSecp256k1.taprootOutputScript`, cached per key).
//

import Foundation

public final class BILPsbtMaps: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {

    /// One key-value pair; `type` is the key type (the key's leading compact size).
    public struct Entry: Equatable, CustomStringConvertible, CustomReflectable {
        public let key: [UInt8]
        public let value: [UInt8]
        public let type: UInt64

        public var keyHex: String { return BILPublicHex.encode(key) }
        public var valueHex: String { return BILPublicHex.encode(value) }
        public var description: String { return "Entry(type=\(type))" }
        public var customMirror: Mirror { return Mirror(self, children: [:]) }
    }

    /// One previous output an input spends: the txid bytes **as stored** (internal order) and the output index.
    public struct Outpoint: Hashable, CustomStringConvertible, CustomReflectable {
        public let txid: [UInt8]
        public let vout: UInt32
        public var description: String { return "Outpoint(vout=\(vout))" }
        public var customMirror: Mirror { return Mirror(self, children: [:]) }
    }

    /// One output derivation: `publicKey` hex (33-byte compressed, or 32-byte x-only for Taproot), `fingerprint` 8 hex.
    /// Its description / mirror name only the output and the kind (iOS hardening; Android's data class prints all).
    public struct OutputDerivation: Equatable, CustomStringConvertible, CustomReflectable {
        public let outputIndex: Int
        public let publicKey: String
        public let fingerprint: String
        public let path: [UInt32]
        public let taproot: Bool

        /// `m/84'/0'/0'/1/5`.
        public var pathText: String { return BILPsbtMaps.pathText(path) }

        public var description: String { return "OutputDerivation(output=\(outputIndex), taproot=\(taproot))" }
        public var customMirror: Mirror { return Mirror(self, children: [:]) }
    }

    /// Where an input's amount comes from (R2-2): its full previous transaction, or only `witnessUtxo` — then what the
    /// output it spends is: SegWit v0 (P2WPKH, P2WSH, or P2SH wrapping a v0 program named by `PSBT_IN_REDEEM_SCRIPT`),
    /// Taproot, or anything else (legacy P2PKH / bare P2SH, whose signatures commit to no amount).
    public enum PrevoutKind: Equatable {
        case fullPreviousTx, witnessSegwitV0, witnessTaproot, witnessLegacy, none
    }

    /// Outcome of `diff`: `problem == nil` = only allowed signatures were added (at least one).
    public struct Diff: Equatable {
        public let addedSignatures: Int
        public let problem: String?
        public var ok: Bool { return problem == nil && addedSignatures > 0 }
    }

    /// Largest PSBT (engine `QR_LIMITS.payloadBytes`, C-BTC-10); also the cap of every compact size.
    public static let maxBytes = 131_072

    /// Inputs and outputs (engine `bitcoin.js`).
    public static let maxInOut = 100

    public let version: Int
    public let global: [Entry]
    public let inputs: [[Entry]]
    public let outputs: [[Entry]]
    public let unsignedTx: [UInt8]

    private init(version: Int, global: [Entry], inputs: [[Entry]], outputs: [[Entry]], unsignedTx: [UInt8]) {
        self.version = version
        self.global = global
        self.inputs = inputs
        self.outputs = outputs
        self.unsignedTx = unsignedTx
    }

    /// `sha256(unsignedTx)` in lower-case hex: the engine's `signingBytesDigest` for this PSBT.
    public var unsignedTxDigest: String { return BILPublicHash.sha256Hex(unsignedTx) }

    public var description: String { return "BILPsbtMaps(v\(version), \(inputs.count) in, \(outputs.count) out)" }
    public var debugDescription: String { return description }
    public var customMirror: Mirror { return Mirror(self, children: [:]) }

    // MARK: - Parse

    /// Parses `bytes`; throws `BILVerifyError` naming the broken part.
    public static func parse(_ bytes: [UInt8]) throws -> BILPsbtMaps {
        try BILVerifyError.check(bytes.count >= 6 && bytes.count <= maxBytes, "psbt.size")
        try BILVerifyError.check(Array(bytes[0..<5]) == magic, "psbt.magic")
        var reader = MapReader(bytes: bytes, pos: 5)
        let global = try reader.map()
        let g = lastByType(global)
        let version = try g[globalVersion].map { try u32Value($0, "psbt.version") } ?? 0
        let inputCount: Int
        let outputCount: Int
        let tx: [UInt8]?
        switch version {
        case 0:
            let unsigned = global.filter { $0.type == globalUnsignedTx }
            try BILVerifyError.check(unsigned.count == 1 && unsigned[0].key.count == 1, "psbt.unsignedTx")
            try BILVerifyError.check([globalTxVersion, globalFallbackLocktime, globalInputCount, globalOutputCount,
                                      globalTxModifiable].allSatisfy { g[$0] == nil }, "psbt.v0.fields")
            let counts = try txCounts(unsigned[0].value)
            inputCount = counts.inputs
            outputCount = counts.outputs
            tx = unsigned[0].value
        case 2:
            try BILVerifyError.check(g[globalUnsignedTx] == nil, "psbt.v2.unsignedTx")
            guard let inCount = g[globalInputCount] else { throw BILVerifyError("psbt.v2.inputCount") }
            inputCount = try compactValue(inCount)
            guard let outCount = g[globalOutputCount] else { throw BILVerifyError("psbt.v2.outputCount") }
            outputCount = try compactValue(outCount)
            tx = nil
        default:
            throw BILVerifyError("psbt.version")
        }
        try BILVerifyError.check(inputCount >= 1 && inputCount <= maxInOut && outputCount >= 1 && outputCount <= maxInOut, "psbt.counts")
        var inputs = [[Entry]]()
        for _ in 0..<inputCount { inputs.append(try reader.map()) }
        var outputs = [[Entry]]()
        for _ in 0..<outputCount { outputs.append(try reader.map()) }
        try BILVerifyError.check(reader.pos == bytes.count, "psbt.trailing")
        let unsignedTx = try tx ?? rebuildV2(g, inputs, outputs)
        return BILPsbtMaps(version: Int(version), global: global, inputs: inputs, outputs: outputs, unsignedTx: unsignedTx)
    }

    /// A canonical Bitcoin compact size at `at`: (value, next position). `fd` / `fe` / `ff` + 2 / 4 / 8 little-endian
    /// bytes, each at least `0xfd` / `0x10000` / `0x1_0000_0000`, and every value ≤ 131 072.
    public static func readCompact(_ b: [UInt8], _ at: Int) throws -> (value: UInt64, next: Int) {
        try BILVerifyError.check(at >= 0 && at < b.count, "compactSize.truncated")
        let first = b[at]
        let width: Int
        switch first {
        case 0xFD: width = 2
        case 0xFE: width = 4
        case 0xFF: width = 8
        default: return (UInt64(first), at + 1)
        }
        try BILVerifyError.check(at + 1 + width <= b.count, "compactSize.truncated")
        var value: UInt64 = 0
        for i in stride(from: width - 1, through: 0, by: -1) { value = (value << 8) | UInt64(b[at + 1 + i]) }
        let minimum: UInt64 = width == 2 ? 0xFD : (width == 4 ? 0x1_0000 : 0x1_0000_0000)
        try BILVerifyError.check(value >= minimum && value <= UInt64(maxBytes), "compactSize.nonCanonical")
        return (value, at + 1 + width)
    }

    // MARK: - Accessors

    /// Every BIP-32 (`0x02`) and Taproot BIP-32 (`0x07`) derivation of the outputs, in output order — every entry the
    /// engine's PSBT library parses, whatever its number of leaf hashes. Skipped: a `0x02` key that is not a 33-byte
    /// compressed key, and malformed entries the library refuses anyway. Throws for a non-canonical leaf-hash count
    /// (Android lets it escape as an unexpected error; the policy treats it as integrity / match again).
    public func outputDerivations() throws -> [OutputDerivation] {
        var out = [OutputDerivation]()
        for (index, map) in outputs.enumerated() {
            for e in map {
                switch e.type {
                case BILPsbtMaps.outBip32:
                    guard e.key.count == 34, e.value.count >= 4, (e.value.count - 4) % 4 == 0 else { continue }
                    out.append(OutputDerivation(outputIndex: index, publicKey: BILPublicHex.encode(Array(e.key[1..<34])),
                                                fingerprint: BILPublicHex.encode(Array(e.value[0..<4])),
                                                path: BILPsbtMaps.u32Path(e.value, 4), taproot: false))
                case BILPsbtMaps.outTapBip32:
                    guard e.key.count == 33, !e.value.isEmpty else { continue }
                    let (hashes, at) = try BILPsbtMaps.readCompact(e.value, 0)
                    let start = at + 32 * Int(hashes)
                    guard start + 4 <= e.value.count, (e.value.count - start - 4) % 4 == 0 else { continue }
                    out.append(OutputDerivation(outputIndex: index, publicKey: BILPublicHex.encode(Array(e.key[1..<33])),
                                                fingerprint: BILPublicHex.encode(Array(e.value[start..<(start + 4)])),
                                                path: BILPsbtMaps.u32Path(e.value, start + 4), taproot: true))
                default:
                    continue
                }
            }
        }
        return out
    }

    /// The internal key (`PSBT_IN_TAP_INTERNAL_KEY`, x-only hex) of input `i`, if any.
    public func tapInternalKey(_ i: Int) -> String? {
        guard i >= 0 && i < inputs.count else { return nil }
        return inputs[i].first { $0.type == BILPsbtMaps.inTapInternalKey && $0.key.count == 1 }?.valueHex
    }

    /// The script input `i` spends, read like `@scure/btc-signer` `getPrevOut`: the output of `PSBT_IN_NON_WITNESS_UTXO`
    /// named by the input's outpoint when present, else `PSBT_IN_WITNESS_UTXO`; nil when neither can be read.
    public func prevoutScript(_ i: Int) -> [UInt8]? {
        guard i >= 0 && i < inputs.count else { return nil }
        let map = inputs[i]
        do {
            if let full = map.first(where: { $0.type == BILPsbtMaps.inNonWitnessUtxo && $0.key.count == 1 }) {
                guard let vout = try outpointIndex(i) else { return nil }
                return try BILPsbtMaps.txOutput(full.value, vout)?.script
            }
            guard let utxo = map.first(where: { $0.type == BILPsbtMaps.inWitnessUtxo && $0.key.count == 1 })?.value else { return nil }
            let (length, at) = try BILPsbtMaps.readCompact(utxo, 8)
            if at + Int(length) != utxo.count { return nil }
            return Array(utxo[at..<utxo.count])
        } catch {
            return nil
        }
    }

    /// Input `i`'s outpoint (v0: the global transaction's input; v2: `PSBT_IN_PREVIOUS_TXID` / `OUTPUT_INDEX`).
    public func outpoint(_ i: Int) -> Outpoint? {
        guard i >= 0 && i < inputs.count else { return nil }
        do {
            if version == 2 {
                guard let txid = inputs[i].first(where: { $0.type == BILPsbtMaps.inPreviousTxid && $0.key.count == 1 && $0.value.count == 32 })?.value,
                      let vout = try outpointIndex(i) else { return nil }
                return Outpoint(txid: txid, vout: vout)
            }
            let (_, start) = try BILPsbtMaps.readCompact(unsignedTx, 4)
            let at = start + 41 * i
            guard at + 36 <= unsignedTx.count else { return nil }
            return Outpoint(txid: Array(unsignedTx[at..<(at + 32)]), vout: BILPsbtMaps.u32(unsignedTx, at + 32))
        } catch {
            return nil
        }
    }

    /// The amount (sats) input `i` claims to spend, read like `@scure/btc-signer` `getPrevOut` (the engine's fee):
    /// the output of `PSBT_IN_NON_WITNESS_UTXO` named by the outpoint when present, else the first 8 bytes of
    /// `PSBT_IN_WITNESS_UTXO`; nil when neither can be read or the value is above 21 million BTC.
    public func claimedAmount(_ i: Int) -> UInt64? {
        guard i >= 0 && i < inputs.count else { return nil }
        let map = inputs[i]
        do {
            let amount: UInt64?
            if let full = map.first(where: { $0.type == BILPsbtMaps.inNonWitnessUtxo && $0.key.count == 1 }) {
                guard let vout = try outpointIndex(i) else { return nil }
                amount = try BILPsbtMaps.txOutput(full.value, vout)?.amount
            } else {
                guard let utxo = map.first(where: { $0.type == BILPsbtMaps.inWitnessUtxo && $0.key.count == 1 })?.value else { return nil }
                amount = utxo.count < 9 ? nil : try BILPsbtMaps.u64(utxo, 0)
            }
            guard let value = amount, value <= BILPsbtMaps.maxSats else { return nil }
            return value
        } catch {
            return nil
        }
    }

    /// `true` when input `i` carries its full previous transaction (`PSBT_IN_NON_WITNESS_UTXO`).
    public func hasFullPrevTx(_ i: Int) -> Bool {
        guard i >= 0 && i < inputs.count else { return false }
        return inputs[i].contains { $0.type == BILPsbtMaps.inNonWitnessUtxo && $0.key.count == 1 }
    }

    /// `PrevoutKind` of input `i`.
    public func prevoutKind(_ i: Int) -> PrevoutKind {
        guard i >= 0 && i < inputs.count else { return .none }
        let map = inputs[i]
        if hasFullPrevTx(i) { return .fullPreviousTx }
        if !map.contains(where: { $0.type == BILPsbtMaps.inWitnessUtxo && $0.key.count == 1 }) { return .none }
        guard let script = prevoutScript(i) else { return .none }
        if BILPsbtMaps.isWitnessV0Program(script) { return .witnessSegwitV0 }
        if script.count == 34 && script[0] == 0x51 && script[1] == 0x20 { return .witnessTaproot }
        if BILPsbtMaps.isP2sh(script) {
            if let redeem = map.first(where: { $0.type == BILPsbtMaps.inRedeemScript && $0.key.count == 1 })?.value,
               BILPsbtMaps.isWitnessV0Program(redeem), BILPublicHash.hash160(redeem) == Array(script[2..<22]) {
                return .witnessSegwitV0
            }
            return .witnessLegacy
        }
        return .witnessLegacy
    }

    /// BIP-341 key-path spend of input `i` by the x-only key `xOnlyHex`: the input names it as its internal key
    /// (case-insensitive), or the script it spends is the key's BIP-86 output `OP_1 <Q>` (also without an internal
    /// key) — the engine's `keyPath` rule (`bitcoin.js` `signBitcoin`).
    public func keyPathOf(_ i: Int, xOnlyHex: String) -> Bool {
        if let internalKey = tapInternalKey(i), BILVerifyText.equalsIgnoringCase(internalKey, xOnlyHex) { return true }
        guard let key = BILPublicHex.decode(xOnlyHex), key.count == 32 else { return false }
        guard let script = prevoutScript(i) else { return false }
        return BILSecp256k1.taprootOutputScript(xOnly: key) == script
    }

    // MARK: - Diff

    /// Compares a signed PSBT (`response`) with the one the user reviewed (`request`): the global map and every output
    /// map identical as key → value sets; every input map keeps every entry and may only gain signatures of the task
    /// keys on the task inputs — `PARTIAL_SIG` (`02 ‖ pubkey`), `TAP_KEY_SIG` (a key-path spend by a task key:
    /// `keyPathOf`) or `TAP_SCRIPT_SIG` (`14 ‖ x-only ‖ leaf`). `signers`: input index → the task public keys allowed to
    /// sign it (33-byte compressed hex; Taproot compares their x-only part). `problem` texts are Android's.
    public static func diff(request: BILPsbtMaps, response: BILPsbtMaps, signers: [Int: Set<String>]) -> Diff {
        if request.version != response.version { return Diff(addedSignatures: 0, problem: "version") }
        if !sameSet(request.global, response.global) { return Diff(addedSignatures: 0, problem: "global map") }
        if request.outputs.count != response.outputs.count { return Diff(addedSignatures: 0, problem: "output count") }
        for i in 0..<request.outputs.count where !sameSet(request.outputs[i], response.outputs[i]) {
            return Diff(addedSignatures: 0, problem: "output \(i) map")
        }
        if request.inputs.count != response.inputs.count { return Diff(addedSignatures: 0, problem: "input count") }
        var added = 0
        for i in 0..<request.inputs.count {
            var before = [[UInt8]: [UInt8]]()
            for e in request.inputs[i] { before[e.key] = e.value }
            var after = [[UInt8]: [UInt8]]()
            for e in response.inputs[i] { after[e.key] = e.value }
            if after.count != response.inputs[i].count { return Diff(addedSignatures: 0, problem: "input \(i) duplicate key") }
            for (k, v) in before where after[k] != v {
                return Diff(addedSignatures: 0, problem: "input \(i) entry removed or changed")
            }
            let allowedTexts = (signers[i] ?? []).map { $0.lowercased() }
            let allowed = Set(allowedTexts.map { Array($0.utf8) })
            var allowedX = [String]()
            for text in Set(allowedTexts) {
                let units = Array(text.utf16)
                if units.count == 66 {
                    allowedX.append(String(decoding: units[2...], as: UTF16.self))
                } else if units.count == 64 {
                    allowedX.append(text)
                }
            }
            let allowedXBytes = Set(allowedX.map { Array($0.utf8) })
            for entry in response.inputs[i] {
                if before[entry.key] != nil { continue }
                let ok: Bool
                switch entry.type {
                case inPartialSig:
                    ok = entry.key.count == 34 && allowed.contains(Array(BILPublicHex.encode(Array(entry.key[1..<34])).utf8))
                case inTapKeySig:
                    ok = entry.key.count == 1 && allowedX.contains { request.keyPathOf(i, xOnlyHex: $0) }
                case inTapScriptSig:
                    ok = entry.key.count == 65 && allowedXBytes.contains(Array(BILPublicHex.encode(Array(entry.key[1..<33])).utf8))
                default:
                    ok = false
                }
                if !ok { return Diff(addedSignatures: added, problem: "input \(i) unexpected entry \(entry.type)") }
                added += 1
            }
        }
        return Diff(addedSignatures: added, problem: added == 0 ? "no signature added" : nil)
    }

    /// `m` + `/n` per level, `'` for hardened (value ≥ `hardened`, printed without the hardened bit).
    public static func pathText(_ p: [UInt32]) -> String {
        var text = "m"
        for v in p {
            text += "/" + String(v & ~hardened)
            if v >= hardened { text += "'" }
        }
        return text
    }

    // MARK: - Constants

    public static let magic: [UInt8] = [0x70, 0x73, 0x62, 0x74, 0xFF]

    /// The BIP-32 hardened bit, 2³¹ (Android `PsbtMaps.HARDENED`, which `PublicSignPolicy` uses for path proofs).
    public static let hardened: UInt32 = 0x8000_0000

    // BIP-174 / BIP-370 key types.
    private static let globalUnsignedTx: UInt64 = 0x00
    private static let globalTxVersion: UInt64 = 0x02
    private static let globalFallbackLocktime: UInt64 = 0x03
    private static let globalInputCount: UInt64 = 0x04
    private static let globalOutputCount: UInt64 = 0x05
    private static let globalTxModifiable: UInt64 = 0x06
    private static let globalVersion: UInt64 = 0xFB
    private static let inNonWitnessUtxo: UInt64 = 0x00
    private static let inWitnessUtxo: UInt64 = 0x01
    public static let inPartialSig: UInt64 = 0x02
    private static let inRedeemScript: UInt64 = 0x04
    private static let inPreviousTxid: UInt64 = 0x0E
    private static let inOutputIndex: UInt64 = 0x0F
    private static let inSequence: UInt64 = 0x10
    private static let inRequiredTimeLocktime: UInt64 = 0x11
    private static let inRequiredHeightLocktime: UInt64 = 0x12
    public static let inTapKeySig: UInt64 = 0x13
    public static let inTapScriptSig: UInt64 = 0x14
    private static let inTapInternalKey: UInt64 = 0x17
    private static let outBip32: UInt64 = 0x02
    private static let outAmount: UInt64 = 0x03
    private static let outScript: UInt64 = 0x04
    private static let outTapBip32: UInt64 = 0x07

    private static let locktimeThreshold: UInt32 = 500_000_000

    /// 21 million BTC in sats.
    private static let maxSats: UInt64 = 2_100_000_000_000_000

    // MARK: - Readers

    private struct MapReader {
        let bytes: [UInt8]
        var pos: Int

        mutating func map() throws -> [Entry] {
            var entries = [Entry]()
            var keys = Set<[UInt8]>()
            while true {
                let (keyLength, afterKeyLength) = try BILPsbtMaps.readCompact(bytes, pos)
                pos = afterKeyLength
                if keyLength == 0 { return entries }
                let key = try take(keyLength)
                let (valueLength, afterValueLength) = try BILPsbtMaps.readCompact(bytes, pos)
                pos = afterValueLength
                let value = try take(valueLength)
                try BILVerifyError.check(keys.insert(key).inserted, "psbt.duplicateKey")
                entries.append(try Entry(key: key, value: value))
            }
        }

        private mutating func take(_ n: UInt64) throws -> [UInt8] {
            try BILVerifyError.check(n <= UInt64(bytes.count - pos), "psbt.truncated")
            let end = pos + Int(n)
            let out = Array(bytes[pos..<end])
            pos = end
            return out
        }
    }

    /// Android `associateBy { it.type }`: the **last** entry of each key type.
    private static func lastByType(_ entries: [Entry]) -> [UInt64: Entry] {
        var out = [UInt64: Entry]()
        for e in entries { out[e.type] = e }
        return out
    }

    private static func sameSet(_ a: [Entry], _ b: [Entry]) -> Bool {
        return a.count == b.count && Set(a.map { [$0.key, $0.value] }) == Set(b.map { [$0.key, $0.value] })
    }

    private static func compactValue(_ e: Entry) throws -> Int {
        let (value, end) = try readCompact(e.value, 0)
        try BILVerifyError.check(end == e.value.count && e.key.count == 1, "psbt.compactValue")
        return Int(value)
    }

    private static func u32Value(_ e: Entry, _ what: String) throws -> UInt32 {
        try BILVerifyError.check(e.key.count == 1 && e.value.count == 4, what)
        return u32(e.value, 0)
    }

    /// Little-endian u32 at `at` (callers check the bounds).
    private static func u32(_ b: [UInt8], _ at: Int) -> UInt32 {
        return UInt32(b[at]) | UInt32(b[at + 1]) << 8 | UInt32(b[at + 2]) << 16 | UInt32(b[at + 3]) << 24
    }

    private static func u32Path(_ b: [UInt8], _ from: Int) -> [UInt32] {
        return stride(from: from, to: b.count, by: 4).map { u32(b, $0) }
    }

    /// Little-endian u64 at `at`.
    private static func u64(_ b: [UInt8], _ at: Int) throws -> UInt64 {
        try BILVerifyError.check(at >= 0 && at + 8 <= b.count, "u64.truncated")
        var v: UInt64 = 0
        for i in stride(from: 7, through: 0, by: -1) { v = (v << 8) | UInt64(b[at + i]) }
        return v
    }

    /// The output index of input `i`'s outpoint (v0: the global transaction; v2: `PSBT_IN_OUTPUT_INDEX`).
    private func outpointIndex(_ i: Int) throws -> UInt32? {
        if version == 2 {
            return inputs[i].first(where: { $0.type == BILPsbtMaps.inOutputIndex && $0.key.count == 1 && $0.value.count == 4 })
                .map { BILPsbtMaps.u32($0.value, 0) }
        }
        // v0: inputs of 41 bytes each after the count (txid, index, empty script sig, sequence; checked by parse).
        let (_, start) = try BILPsbtMaps.readCompact(unsignedTx, 4)
        let at = start + 41 * i + 32
        guard at + 4 <= unsignedTx.count else { return nil }
        return BILPsbtMaps.u32(unsignedTx, at)
    }

    /// `OP_0 <20 or 32 bytes>`: a SegWit v0 witness program (P2WPKH / P2WSH).
    private static func isWitnessV0Program(_ script: [UInt8]) -> Bool {
        return (script.count == 22 && script[0] == 0 && script[1] == 0x14) || (script.count == 34 && script[0] == 0 && script[1] == 0x20)
    }

    /// `OP_HASH160 <20> OP_EQUAL`.
    private static func isP2sh(_ script: [UInt8]) -> Bool {
        return script.count == 23 && script[0] == 0xA9 && script[1] == 0x14 && script[22] == 0x87
    }

    /// (amount, script) of output `vout` of the serialized transaction `tx` (legacy or segwit serialization).
    private static func txOutput(_ tx: [UInt8], _ vout: UInt32) throws -> (amount: UInt64, script: [UInt8])? {
        var at = 4
        try BILVerifyError.check(tx.count > at + 2, "prevTx.size")
        if tx[at] == 0 && tx[at + 1] == 1 { at += 2 }     // segwit marker + flag
        let (nIn, afterIn) = try readCompact(tx, at)
        at = afterIn
        for _ in 0..<Int(nIn) {
            try BILVerifyError.check(at + 36 <= tx.count, "prevTx.truncated")
            let (scriptLength, afterScript) = try readCompact(tx, at + 36)
            at = afterScript + Int(scriptLength) + 4
            try BILVerifyError.check(at <= tx.count, "prevTx.truncated")
        }
        let (nOut, afterOut) = try readCompact(tx, at)
        at = afterOut
        if UInt64(vout) >= nOut { return nil }
        for i in 0..<Int(nOut) {
            try BILVerifyError.check(at + 8 <= tx.count, "prevTx.truncated")
            let (scriptLength, afterScript) = try readCompact(tx, at + 8)
            let end = afterScript + Int(scriptLength)
            try BILVerifyError.check(end <= tx.count, "prevTx.truncated")
            if i == Int(vout) { return (try u64(tx, at), Array(tx[afterScript..<end])) }
            at = end
        }
        return nil
    }

    /// (inputs, outputs) of a v0 global transaction: legacy serialization, empty script sigs, no trailing bytes.
    private static func txCounts(_ tx: [UInt8]) throws -> (inputs: Int, outputs: Int) {
        try BILVerifyError.check(tx.count >= 10, "psbt.tx.size")
        var at = 4
        try BILVerifyError.check(tx[at] != 0, "psbt.tx.witness")    // a segwit marker: the unsigned tx has no witness
        let (nIn, afterIn) = try readCompact(tx, at)
        at = afterIn
        try BILVerifyError.check(nIn >= 1 && nIn <= UInt64(maxInOut), "psbt.tx.inputs")
        for _ in 0..<Int(nIn) {
            try BILVerifyError.check(at + 36 <= tx.count, "psbt.tx.truncated")
            at += 36
            let (scriptLength, afterScript) = try readCompact(tx, at)
            try BILVerifyError.check(scriptLength == 0, "psbt.tx.scriptSig")
            at = afterScript + 4
        }
        let (nOut, afterOut) = try readCompact(tx, at)
        at = afterOut
        try BILVerifyError.check(nOut >= 1 && nOut <= UInt64(maxInOut), "psbt.tx.outputs")
        for _ in 0..<Int(nOut) {
            try BILVerifyError.check(at + 8 <= tx.count, "psbt.tx.truncated")
            at += 8
            let (scriptLength, afterScript) = try readCompact(tx, at)
            at = afterScript + Int(scriptLength)
            try BILVerifyError.check(at <= tx.count, "psbt.tx.truncated")
        }
        try BILVerifyError.check(at + 4 == tx.count, "psbt.tx.trailing")
        return (Int(nIn), Int(nOut))
    }

    /// The unsigned transaction of a v2 PSBT, serialized like `@scure/btc-signer` `unsignedTx`: version, inputs
    /// (previous txid as stored, output index, empty script sig, sequence or `ffffffff`), outputs (amount, script),
    /// BIP-370 lock time (the largest required height lock when every constrained input allows heights, else the
    /// largest time lock; the fallback when no input is constrained).
    private static func rebuildV2(_ g: [UInt64: Entry], _ inputs: [[Entry]], _ outputs: [[Entry]]) throws -> [UInt8] {
        var out = [UInt8]()
        guard let versionEntry = g[globalTxVersion] else { throw BILVerifyError("psbt.v2.txVersion") }
        writeU32(&out, try u32Value(versionEntry, "psbt.v2.txVersion"))
        writeCompact(&out, inputs.count)
        var height: UInt32 = 0
        var time: UInt32 = 0
        var constrained = false
        var heightOk = true
        var timeOk = true
        for map in inputs {
            let m = lastByType(map)
            guard let txid = m[inPreviousTxid], txid.key.count == 1, txid.value.count == 32 else {
                throw BILVerifyError("psbt.v2.previousTxid")
            }
            guard let indexEntry = m[inOutputIndex] else { throw BILVerifyError("psbt.v2.outputIndex") }
            let index = try u32Value(indexEntry, "psbt.v2.outputIndex")
            let sequence = try m[inSequence].map { try u32Value($0, "psbt.v2.sequence") } ?? 0xFFFF_FFFF
            let requiredTime = try m[inRequiredTimeLocktime].map { try u32Value($0, "psbt.v2.timeLock") }
            let requiredHeight = try m[inRequiredHeightLocktime].map { try u32Value($0, "psbt.v2.heightLock") }
            if let t = requiredTime { try BILVerifyError.check(t >= locktimeThreshold, "psbt.v2.timeLock") }
            if let h = requiredHeight { try BILVerifyError.check(h >= 1 && h < locktimeThreshold, "psbt.v2.heightLock") }
            if requiredTime != nil || requiredHeight != nil {
                constrained = true
                if let h = requiredHeight { height = max(height, h) } else { heightOk = false }
                if let t = requiredTime { time = max(time, t) } else { timeOk = false }
            }
            out.append(contentsOf: txid.value)
            writeU32(&out, index)
            out.append(0)
            writeU32(&out, sequence)
        }
        writeCompact(&out, outputs.count)
        for map in outputs {
            let m = lastByType(map)
            guard let amount = m[outAmount], amount.key.count == 1, amount.value.count == 8 else { throw BILVerifyError("psbt.v2.amount") }
            guard let script = m[outScript], script.key.count == 1 else { throw BILVerifyError("psbt.v2.script") }
            out.append(contentsOf: amount.value)
            writeCompact(&out, script.value.count)
            out.append(contentsOf: script.value)
        }
        let fallback = try g[globalFallbackLocktime].map { try u32Value($0, "psbt.v2.fallbackLocktime") } ?? 0
        let lockTime: UInt32
        if !constrained {
            lockTime = fallback
        } else if heightOk {
            lockTime = height
        } else if timeOk {
            lockTime = time
        } else {
            throw BILVerifyError("psbt.v2.locktime")
        }
        writeU32(&out, lockTime)
        return out
    }

    private static func writeU32(_ out: inout [UInt8], _ v: UInt32) {
        for i in 0..<4 { out.append(UInt8(truncatingIfNeeded: v >> (8 * UInt32(i)))) }
    }

    private static func writeCompact(_ out: inout [UInt8], _ v: Int) {
        if v < 0xFD {
            out.append(UInt8(v))
        } else if v <= 0xFFFF {
            out.append(0xFD)
            out.append(UInt8(truncatingIfNeeded: v))
            out.append(UInt8(truncatingIfNeeded: v >> 8))
        } else {
            out.append(0xFE)
            writeU32(&out, UInt32(truncatingIfNeeded: v))
        }
    }
}

extension BILPsbtMaps.Entry {
    /// Android `Entry(key, value)`: `type` = the canonical compact size at the start of `key` (throws for a malformed
    /// key type, like Android's constructor).
    init(key: [UInt8], value: [UInt8]) throws {
        self.init(key: key, value: value, type: try BILPsbtMaps.readCompact(key, 0).value)
    }
}
