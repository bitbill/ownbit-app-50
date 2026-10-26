//  BILEvmTxCodec.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Public protocol (cold signer) — strict RLP and the **unsigned** EVM transaction an `eth-sign-request` asks to sign
//  (dataType 1 legacy RLP, dataType 4 typed transaction), read natively and independently of the engine (port of
//  Android `A:core/chain/src/main/kotlin/io/ownbit/core/chain/evm/EvmTxCodec.kt` :35-124 (RLP) and :260-428
//  (`decodeUnsigned`); R5 §3.5; C-EVM-1 / C-EVM-2 / C-GEN-4). Nothing here signs or recovers (recovery is
//  `BILSecp256k1`, WP2).
//
//  iOS-only hardening: RLP lists may nest at most `maxListDepth` levels (Android's decoder is unbounded). A valid
//  unsigned transaction nests 4 (transaction → access list → entry → storage keys) and `decodeUnsigned` refuses every
//  deeper shape anyway, so no input Android accepts is refused; the bound only keeps attacker-controlled nesting from
//  exhausting a 512 KiB cooperative-thread stack.
//
//  Pure (Foundation + WP2 hashes). Errors are `BILVerifyError` (`evm.*`, log-safe); nothing logged.
//

import Foundation

/// A decoded **unsigned** transaction (Android `EvmTxCodec.UnsignedEvmTx`). Integers are the minimal big-endian bytes
/// of the RLP (no leading zero byte; empty = 0).
public struct BILUnsignedEvmTx: Equatable, CustomStringConvertible, CustomReflectable {
    /// 0 = legacy EIP-155, 1 = EIP-2930, 2 = EIP-1559.
    public let type: Int
    /// Always > 0 and < 2⁶³ (pre-EIP-155 transactions are refused).
    public let chainId: UInt64
    public let nonce: [UInt8]
    public let gasLimit: [UInt8]
    /// Lower-case `0x` recipient, nil for contract creation.
    public let to: String?
    public let value: [UInt8]
    public let data: [UInt8]
    /// keccak-256 of the exact input bytes: the digest the signature commits to (equal to ethers `unsignedHash`
    /// exactly because the input must be canonical).
    public let signingHash: [UInt8]
    /// Legacy / type-1 gas price, nil for type 2.
    public let gasPrice: [UInt8]?
    /// Type-2 fees, nil otherwise.
    public let maxPriorityFeePerGas: [UInt8]?
    public let maxFeePerGas: [UInt8]?
    /// Number of access-list entries (types 1 and 2; 0 for legacy).
    public let accessListEntries: Int

    /// `0x` lower-case calldata (`0x` when empty).
    public var dataHex: String { return "0x" + BILPublicHex.encode(data) }

    /// The fee per gas the transaction allows: `maxFeePerGas` (type 2) or `gasPrice` (minimal bytes; empty = 0).
    public var feePerGas: [UInt8] { return maxFeePerGas ?? gasPrice ?? [] }

    /// Android `"0x" + BigInteger.toString(16)` of a minimal big-endian integer: `0x0` for zero, no leading zeros
    /// (the D43 request's `value` / `gas`, D-41).
    public static func quantityHex(_ minimal: [UInt8]) -> String {
        var hex = BILPublicHex.encode(minimal)
        while hex.hasPrefix("0") { hex.removeFirst() }
        return "0x" + (hex.isEmpty ? "0" : hex)
    }

    public var description: String { return "BILUnsignedEvmTx(type \(type), data \(data.count) bytes)" }
    /// No children: `dump` / reflection print the description only.
    public var customMirror: Mirror { return Mirror(self, children: [:]) }
}

enum BILEvmTxCodec {

    /// Deepest list nesting accepted by the RLP decoder (iOS-only bound; see the file comment).
    static let maxListDepth = 32

    /// Decodes the unsigned transaction `bytes` (types 0 / 1 / 2) with **strict** rules, so that what is read is exactly
    /// what the signature commits to:
    /// - canonical RLP only (every length minimal, no single byte below `0x80` wrapped, no trailing bytes) — checked by
    ///   re-encoding the decoded tree and comparing it with the body;
    /// - integers without leading zero bytes (`0` = the empty string), at most 32 bytes; `chainId` > 0 and < 2⁶³;
    /// - `to` empty (contract creation) or 20 bytes; access list = `[[address(20), [slot(32)…]]…]`;
    /// - legacy: exactly the 9 EIP-155 fields `[nonce, gasPrice, gas, to, value, data, chainId, 0, 0]` (the 6-field
    ///   pre-EIP-155 form has no chain id and is refused);
    /// - type 1: 8 fields, type 2: 9 fields (a signed typed transaction has 3 more and is refused);
    /// - every other first byte (blob type 3, EIP-7702 type 4, unknown) is refused.
    static func decodeUnsigned(_ bytes: [UInt8]) throws -> BILUnsignedEvmTx {
        try BILVerifyError.check(!bytes.isEmpty, "evm.empty")
        let first = bytes[0]
        let type: Int
        let body: [UInt8]
        if first >= 0xC0 {
            type = 0
            body = bytes
        } else if first == 0x01 || first == 0x02 {
            type = Int(first)
            body = Array(bytes[1...])
        } else {
            throw BILVerifyError("evm.type")
        }
        let item = try rlpDecode(body)
        guard case .list(let f) = item else { throw BILVerifyError("evm.rlp.notList") }
        try BILVerifyError.check(canonical(item) == body, "evm.rlp.nonCanonical")
        let hash = BILPublicHash.keccak256(bytes)
        switch type {
        case 0:
            if f.count != 9 {
                throw BILVerifyError(f.count == 6 ? "evm.legacy.noChainId" : "evm.legacy.fields")
            }
            try BILVerifyError.check(try strictUint(f[7]).isEmpty, "evm.legacy.signed")
            try BILVerifyError.check(try strictUint(f[8]).isEmpty, "evm.legacy.signed")
            let chainId = try chainIdValue(f[6])
            let nonce = try strictUint(f[0])
            let gasPrice = try strictUint(f[1])
            let gasLimit = try strictUint(f[2])
            let to = try address(f[3])
            let value = try strictUint(f[4])
            let data = try bytesOf(f[5])
            return BILUnsignedEvmTx(type: 0, chainId: chainId, nonce: nonce, gasLimit: gasLimit, to: to, value: value,
                                    data: data, signingHash: hash, gasPrice: gasPrice, maxPriorityFeePerGas: nil,
                                    maxFeePerGas: nil, accessListEntries: 0)
        case 1:
            if f.count != 8 {
                throw BILVerifyError(f.count == 11 ? "evm.type1.signed" : "evm.type1.fields")
            }
            let chainId = try chainIdValue(f[0])
            let nonce = try strictUint(f[1])
            let gasPrice = try strictUint(f[2])
            let gasLimit = try strictUint(f[3])
            let to = try address(f[4])
            let value = try strictUint(f[5])
            let data = try bytesOf(f[6])
            let entries = try accessList(f[7])
            return BILUnsignedEvmTx(type: 1, chainId: chainId, nonce: nonce, gasLimit: gasLimit, to: to, value: value,
                                    data: data, signingHash: hash, gasPrice: gasPrice, maxPriorityFeePerGas: nil,
                                    maxFeePerGas: nil, accessListEntries: entries)
        default:
            if f.count != 9 {
                throw BILVerifyError(f.count == 12 ? "evm.type2.signed" : "evm.type2.fields")
            }
            let chainId = try chainIdValue(f[0])
            let nonce = try strictUint(f[1])
            let maxPriority = try strictUint(f[2])
            let maxFee = try strictUint(f[3])
            let gasLimit = try strictUint(f[4])
            let to = try address(f[5])
            let value = try strictUint(f[6])
            let data = try bytesOf(f[7])
            let entries = try accessList(f[8])
            return BILUnsignedEvmTx(type: 2, chainId: chainId, nonce: nonce, gasLimit: gasLimit, to: to, value: value,
                                    data: data, signingHash: hash, gasPrice: nil, maxPriorityFeePerGas: maxPriority,
                                    maxFeePerGas: maxFee, accessListEntries: entries)
        }
    }

    /// EIP-191 `personal_sign` digest of raw message bytes: keccak("\u{19}Ethereum Signed Message:\n" + len ‖ msg).
    static func personalMessageDigest(_ m: [UInt8]) -> [UInt8] {
        return BILPublicHash.eip191Digest(m)
    }

    // MARK: - RLP

    private indirect enum Rlp {
        case bytes([UInt8])
        case list([Rlp])
    }

    /// One RLP item that must span all of `input`.
    private static func rlpDecode(_ input: [UInt8]) throws -> Rlp {
        let (item, end) = try decodeAt(input, 0, depth: 0)
        try BILVerifyError.check(end == input.count, "evm.rlp.trailing")
        return item
    }

    private static func decodeAt(_ src: [UInt8], _ pos: Int, depth: Int) throws -> (Rlp, Int) {
        try BILVerifyError.check(pos < src.count, "evm.rlp.end")
        let prefix = Int(src[pos])
        if prefix < 0x80 {
            return (.bytes([src[pos]]), pos + 1)
        }
        if prefix <= 0xB7 {
            let len = prefix - 0x80
            let start = pos + 1
            try checkRange(src, start, len)
            let bytes = Array(src[start..<(start + len)])
            try BILVerifyError.check(!(len == 1 && bytes[0] < 0x80), "evm.rlp.singleByte")
            return (.bytes(bytes), start + len)
        }
        if prefix <= 0xBF {
            let lenOfLen = prefix - 0xB7
            let len = try readLength(src, pos + 1, lenOfLen)
            let start = pos + 1 + lenOfLen
            try checkRange(src, start, len)
            return (.bytes(Array(src[start..<(start + len)])), start + len)
        }
        try BILVerifyError.check(depth < maxListDepth, "evm.rlp.depth")
        let payloadStart: Int
        let len: Int
        if prefix <= 0xF7 {
            payloadStart = pos + 1
            len = prefix - 0xC0
        } else {
            let lenOfLen = prefix - 0xF7
            payloadStart = pos + 1 + lenOfLen
            len = try readLength(src, pos + 1, lenOfLen)
        }
        try checkRange(src, payloadStart, len)
        var items = [Rlp]()
        var p = payloadStart
        let end = payloadStart + len
        while p < end {
            let (item, next) = try decodeAt(src, p, depth: depth + 1)
            items.append(item)
            p = next
        }
        try BILVerifyError.check(p == end, "evm.rlp.overrun")
        return (.list(items), end)
    }

    /// Big-endian length of 1…4 bytes, ≤ Int32.max (Android `readLength`).
    private static func readLength(_ src: [UInt8], _ pos: Int, _ lenOfLen: Int) throws -> Int {
        try BILVerifyError.check(lenOfLen >= 1 && lenOfLen <= 4, "evm.rlp.length")
        try checkRange(src, pos, lenOfLen)
        var len: Int64 = 0
        for i in 0..<lenOfLen { len = (len << 8) | Int64(src[pos + i]) }
        try BILVerifyError.check(len <= Int64(Int32.max), "evm.rlp.length")
        return Int(len)
    }

    private static func checkRange(_ src: [UInt8], _ start: Int, _ len: Int) throws {
        try BILVerifyError.check(len >= 0 && start >= 0 && start <= src.count && len <= src.count - start, "evm.rlp.range")
    }

    /// The canonical encoding of a decoded tree (equal to the source exactly when the source was canonical).
    private static func canonical(_ item: Rlp) -> [UInt8] {
        switch item {
        case .bytes(let b):
            if b.count == 1 && b[0] < 0x80 { return b }
            return lengthPrefix(b.count, 0x80) + b
        case .list(let items):
            var payload = [UInt8]()
            for child in items { payload.append(contentsOf: canonical(child)) }
            return lengthPrefix(payload.count, 0xC0) + payload
        }
    }

    private static func lengthPrefix(_ len: Int, _ offset: Int) -> [UInt8] {
        if len <= 55 { return [UInt8(offset + len)] }
        var lenBytes = [UInt8]()
        var v = len
        while v > 0 {
            lenBytes.insert(UInt8(v & 0xFF), at: 0)
            v >>= 8
        }
        return [UInt8(offset + 55 + lenBytes.count)] + lenBytes
    }

    // MARK: - Fields

    private static func bytesOf(_ item: Rlp) throws -> [UInt8] {
        guard case .bytes(let b) = item else { throw BILVerifyError("evm.bytes") }
        return b
    }

    /// A canonical unsigned integer: no leading zero byte, at most 256 bits.
    private static func strictUint(_ item: Rlp) throws -> [UInt8] {
        let b = try bytesOf(item)
        try BILVerifyError.check(b.isEmpty || b[0] != 0, "evm.uint.leadingZero")
        try BILVerifyError.check(b.count <= 32, "evm.uint.width")
        return b
    }

    /// `chainId` > 0 and bit length < 64 (fits a positive Int64, as Android's `Long`).
    private static func chainIdValue(_ item: Rlp) throws -> UInt64 {
        let b = try strictUint(item)
        try BILVerifyError.check(!b.isEmpty, "evm.chainId.zero")
        try BILVerifyError.check(b.count < 8 || (b.count == 8 && b[0] < 0x80), "evm.chainId.large")
        var v: UInt64 = 0
        for x in b { v = (v << 8) | UInt64(x) }
        return v
    }

    /// Validates an EIP-2930 access list and returns its entry count.
    private static func accessList(_ item: Rlp) throws -> Int {
        guard case .list(let entries) = item else { throw BILVerifyError("evm.accessList") }
        for entry in entries {
            guard case .list(let pair) = entry else { throw BILVerifyError("evm.accessList.entry") }
            if pair.count != 2 { throw BILVerifyError("evm.accessList.entry") }
            if try bytesOf(pair[0]).count != 20 { throw BILVerifyError("evm.accessList.entry") }
            guard case .list(let slots) = pair[1] else { throw BILVerifyError("evm.accessList.slots") }
            for slot in slots {
                try BILVerifyError.check(try bytesOf(slot).count == 32, "evm.accessList.slot")
            }
        }
        return entries.count
    }

    private static func address(_ item: Rlp) throws -> String? {
        let b = try bytesOf(item)
        if b.isEmpty { return nil }
        try BILVerifyError.check(b.count == 20, "evm.address")
        return "0x" + BILPublicHex.encode(b)
    }
}
