//  BILSolanaMessageHeader.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Public protocol (cold signer) — a Solana transaction message (legacy or v0) read natively, independently of the
//  engine (port of Android `PS:verify/SolanaMessageHeader.kt`; R5 §3.7; C-SOL-1 / C-SOL-2 / C-SOL-3 / C-SOL-5 /
//  C-SOL-6). Same structural rules as the engine (`solana.js` `parseSolana`): header sane (`0 < required ≤ keys ≤
//  256`, `readonlySigned < required`, `readonlyUnsigned ≤ keys − required`), unique static keys, 1–64 instructions
//  whose program and account indexes resolve and whose program is not a required signer, **no address lookup tables**
//  in v0 (`ParseError.lookupTables`, thrown before the trailing-byte check), canonical compact lengths (shortvec), no
//  trailing bytes, at most 1232 bytes. Also the off-chain message rule (incl. Android's control-character rule,
//  R5 (D) 1).
//
//  Pure Foundation. Never logs.
//

import Foundation

public struct BILSolanaMessageHeader: Equatable, CustomStringConvertible, CustomReflectable {
    public enum Version: Equatable { case legacy, v0 }

    /// One compiled instruction: program key index, account key indexes, data.
    public struct Instruction: Equatable, CustomStringConvertible, CustomReflectable {
        public let programIndex: Int
        public let accounts: [Int]
        public let data: [UInt8]

        public var description: String { return "Instruction(\(accounts.count) accounts, data \(data.count) bytes)" }
        public var customMirror: Mirror { return Mirror(self, children: [:]) }
    }

    public enum ParseError: Error, Equatable, CustomStringConvertible {
        /// A v0 message that uses address lookup tables (`err.lookupTable`, engine `LOOKUP_TABLE`).
        case lookupTables
        /// Any structural failure; the payload is a log-safe check name (`solana.*`).
        case malformed(String)

        public var description: String {
            switch self {
            case .lookupTables: return "Solana address lookup tables are refused offline"
            case .malformed(let what): return "Public protocol check failed: " + what
            }
        }
    }

    /// Network packet limit for a serialized transaction (engine `solana.js`).
    public static let maxBytes = 1_232

    public let version: Version
    /// The first `requiredSignatures` keys sign; the fee payer is key 0.
    public let requiredSignatures: Int
    /// The static account keys (32 bytes each), in message order.
    public let keys: [[UInt8]]
    /// The first instruction is the System program's `AdvanceNonceAccount` (the transaction does not expire:
    /// warning + acknowledgement, C-SOL-3).
    public let usesDurableNonce: Bool
    public let readonlySigned: Int
    public let readonlyUnsigned: Int
    public let instructions: [Instruction]

    public var keyCount: Int { return keys.count }

    /// The static account key `index` as lower-case hex.
    public func keyHex(_ index: Int) -> String { return BILPublicHex.encode(keys[index]) }

    /// The required-signer slot of `keyHex` (32-byte hex, any case), or nil when it is not a required signer.
    public func signerSlot(_ keyHex: String) -> Int? {
        for i in 0..<requiredSignatures where BILVerifyText.equalsIgnoringCase(self.keyHex(i), keyHex) { return i }
        return nil
    }

    /// Distinct program ids (hex) in instruction order.
    public var programIds: [String] {
        var out = [String]()
        for ix in instructions {
            let id = keyHex(ix.programIndex)
            if !out.contains(id) { out.append(id) }
        }
        return out
    }

    public var description: String {
        return "BILSolanaMessageHeader(\(version), required=\(requiredSignatures), keys=\(keys.count), ix=\(instructions.count))"
    }

    /// No children: `dump` / reflection print the description only.
    public var customMirror: Mirror { return Mirror(self, children: [:]) }

    /// Parses `bytes`; throws `ParseError.malformed(what)` (structure) or `.lookupTables`.
    public static func parse(_ bytes: [UInt8]) throws -> BILSolanaMessageHeader {
        try check(!bytes.isEmpty && bytes.count <= maxBytes, "solana.size")
        var r = Reader(bytes: bytes)
        var version = Version.legacy
        var required = try r.u8()
        if required & 0x80 != 0 {
            try check(required == 0x80, "solana.version")
            version = .v0
            required = try r.u8()
        }
        let readonlySigned = try r.u8()
        let readonlyUnsigned = try r.u8()
        let keyCount = try r.short()
        try check(required >= 1 && required <= keyCount && readonlySigned < required &&
                  readonlyUnsigned <= keyCount - required && keyCount <= maxKeys, "solana.header")
        var keys = [[UInt8]]()
        for _ in 0..<keyCount { keys.append(try r.take(32)) }
        try check(Set(keys).count == keys.count, "solana.duplicateKeys")
        _ = try r.take(32)                                  // recent blockhash or durable nonce
        let count = try r.short()
        try check(count >= 1 && count <= maxInstructions, "solana.instructions")
        var instructions = [Instruction]()
        for _ in 0..<count {
            let program = try r.u8()
            let accountCount = try r.short()
            let accounts = try r.take(accountCount).map { Int($0) }
            let dataLength = try r.short()
            let data = try r.take(dataLength)
            try check(program < keyCount && accounts.allSatisfy { $0 < keyCount }, "solana.unresolvedAccount")
            try check(program >= required, "solana.programSigner")
            instructions.append(Instruction(programIndex: program, accounts: accounts, data: data))
        }
        if version == .v0 {
            let lookupCount = try r.short()
            if lookupCount != 0 { throw ParseError.lookupTables }
        }
        try check(r.pos == bytes.count, "solana.trailing")
        var durable = false
        if let first = instructions.first, keys[first.programIndex].allSatisfy({ $0 == 0 }) {   // System program = 32 zero bytes
            durable = first.data == [advanceNonceAccount, 0, 0, 0]
        }
        return BILSolanaMessageHeader(version: version, requiredSignatures: required, keys: keys, usesDurableNonce: durable,
                                      readonlySigned: readonlySigned, readonlyUnsigned: readonlyUnsigned,
                                      instructions: instructions)
    }

    /// The off-chain message rule (C-SOL-6, engine `parseSolana` kind `message`): 1–1024 bytes, first byte ≥ 0x20 and
    /// not 0x80 (no transaction-header reinterpretation), strict UTF-8 without control characters U+0000–U+0008,
    /// U+000B, U+000C, U+000E–U+001F, U+007F (tab, LF and CR allowed).
    public static func isValidOffchainMessage(_ bytes: [UInt8]) -> Bool {
        if bytes.isEmpty || bytes.count > 1024 { return false }
        let first = bytes[0]
        if first < 0x20 || first == 0x80 { return false }
        guard BILVerifyText.strictUTF8(bytes) != nil else { return false }
        // In valid UTF-8 every byte below 0x80 is its own character, so a byte scan is exact.
        return !bytes.contains { b in b <= 0x08 || b == 0x0B || b == 0x0C || (b >= 0x0E && b <= 0x1F) || b == 0x7F }
    }

    // MARK: - Private

    private static let maxKeys = 256
    private static let maxInstructions = 64
    private static let advanceNonceAccount: UInt8 = 4

    private static func check(_ condition: Bool, _ what: @autoclosure () -> String) throws {
        if !condition { throw ParseError.malformed(what()) }
    }

    private struct Reader {
        let bytes: [UInt8]
        var pos = 0

        init(bytes: [UInt8]) {
            self.bytes = bytes
        }

        mutating func take(_ n: Int) throws -> [UInt8] {
            try BILSolanaMessageHeader.check(n >= 0 && n <= bytes.count - pos, "solana.truncated")
            let out = Array(bytes[pos..<(pos + n)])
            pos += n
            return out
        }

        mutating func u8() throws -> Int {
            return Int(try take(1)[0])
        }

        /// Solana compact-u16 (shortvec), canonical only (engine `Reader.short`): ≤ 3 bytes, the third < 4, a
        /// terminating continuation byte is not 0.
        mutating func short() throws -> Int {
            var n = 0
            var shift = 0
            for i in 0..<3 {
                let b = try u8()
                try BILSolanaMessageHeader.check(i < 2 || b < 4, "solana.compactLength")
                n |= (b & 0x7F) << shift
                if b & 0x80 == 0 {
                    try BILSolanaMessageHeader.check(i == 0 || b != 0, "solana.compactLength")
                    return n
                }
                shift += 7
            }
            throw ParseError.malformed("solana.compactLength")
        }
    }
}
