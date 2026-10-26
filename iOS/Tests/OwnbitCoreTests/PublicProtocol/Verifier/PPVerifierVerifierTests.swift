//  PPVerifierVerifierTests.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Port of the app harness suite `scripts/public-protocol/tests/verifier` (VerifierTests.swift) to XCTest.
//
//  VerifierTests.swift — BILPublicSignVerifier + BILPsbtMaps+Claims on the golden vectors (ports of Android
//  PST:verify/{PublicSignVerifierTest,OtherWalletVerifierTest,TronLinkSplitAnswerVerifierTest,
//  WitnessOnlyPrevoutVerifierTest}.kt, plus the R5 §3.9 tamper list, C-EVM-2 / C-EVM-9, the EIP-712 equivalence, the
//  `domain.chainId` reading, the TRON address codec and the outpoint claims).
//

import Foundation
import XCTest
@testable import OwnbitCore

extension PPVerifierSuite {

    typealias V = BILPublicSignVerifier

    // MARK: - Check helpers

    @discardableResult
    static func expectOk(_ v: V.Verdict, _ what: String, file: StaticString = #file, line: UInt = #line) -> BILVerifiedPayload? {
        t(v.isOk, "\(what): \(v)", file: file, line: line)
        return v.payload
    }

    /// A refusal with `reason` (and `detail` when given); returns the detail.
    @discardableResult
    static func expectRefused(_ v: V.Verdict, _ reason: V.Reason = .INTEGRITY, detail: String? = nil, _ what: String,
                       file: StaticString = #file, line: UInt = #line) -> String? {
        guard case .refused(let r, let d) = v else {
            t(false, "\(what): expected a refusal, got \(v)", file: file, line: line)
            return nil
        }
        t(r == reason, "\(what): reason \(r.rawValue) (\(d)), expected \(reason.rawValue)", file: file, line: line)
        if let expected = detail { eq(d, expected, "\(what): detail", file: file, line: line) }
        return d
    }

    static func kindName(_ p: BILVerifiedPayload) -> String {
        switch p {
        case .evmTransaction: return "EvmTransaction"
        case .evmPersonal: return "EvmPersonal"
        case .evmTypedData: return "EvmTypedData"
        case .tronTransaction: return "TronTransaction"
        case .tronOwnershipProof: return "TronOwnershipProof"
        case .tronMessage: return "TronMessage"
        case .solanaTransaction: return "SolanaTransaction"
        case .solanaMessage: return "SolanaMessage"
        case .bitcoinPsbt: return "BitcoinPsbt"
        }
    }

    /// `post` of vector flow `id` (Android `PublicSignVerifierTest.post`).
    static func postVector(_ id: String, response: BILPublicResponseQr? = nil, result: BILPublicSignResult? = nil) -> V.Verdict {
        return V.post(request: SigningVectors.request(id), plan: SigningVectors.plan(id), verified: SigningVectors.verified(id),
                      result: result ?? SigningVectors.finalResult(id), response: response ?? SigningVectors.response(id))
    }

    static func resultWith(_ id: String, _ key: String, _ value: String) -> BILPublicSignResult {
        return SigningVectors.resultOf(with(SigningVectors.finalResult(id).raw, key, .string(value)))
    }

    /// The first byte of the first output amount of a v0 PSBT's global unsigned transaction (Android `indexOfOutputValue`).
    static func indexOfOutputValue(_ psbt: [UInt8]) -> Int {
        var at = 7
        let first = Int(psbt[at])
        at += first < 0xFD ? 1 : 3
        let nIn = Int(psbt[at + 4])
        return at + 4 + 1 + nIn * (36 + 1 + 4) + 1
    }

    // MARK: - RLP (test-only encoder for synthetic EVM requests)

    static func rlpBytes(_ b: [UInt8]) -> [UInt8] {
        if b.count == 1 && b[0] < 0x80 { return b }
        if b.count < 56 { return [0x80 + UInt8(b.count)] + b }
        let len = minimalBytes(UInt64(b.count))
        return [0xB7 + UInt8(len.count)] + len + b
    }

    static func rlpUInt(_ n: UInt64) -> [UInt8] {
        return rlpBytes(minimalBytes(n))
    }

    static func rlpList(_ items: [[UInt8]]) -> [UInt8] {
        let payload = items.flatMap { $0 }
        if payload.count < 56 { return [0xC0 + UInt8(payload.count)] + payload }
        let len = minimalBytes(UInt64(payload.count))
        return [0xF7 + UInt8(len.count)] + len + payload
    }

    static func minimalBytes(_ n: UInt64) -> [UInt8] {
        var out = [UInt8]()
        var v = n
        while v > 0 {
            out.insert(UInt8(v & 0xFF), at: 0)
            v >>= 8
        }
        return out
    }

    // MARK: - Protobuf (test-only, for synthetic TRON raw data)

    static func protoVarint(_ n: UInt64) -> [UInt8] {
        var out = [UInt8]()
        var v = n
        repeat {
            let low = UInt8(v & 0x7F)
            v >>= 7
            out.append(v == 0 ? low : low | 0x80)
        } while v != 0
        return out
    }

    /// A length-delimited field `field` with `bytes`.
    static func protoBytesField(_ field: UInt64, _ bytes: [UInt8]) -> [UInt8] {
        return protoVarint(field << 3 | 2) + protoVarint(UInt64(bytes.count)) + bytes
    }

    /// The bytes of the first length-delimited field `field` of `message` (wire types 0 / 1 / 2 / 5 skipped), nil if absent.
    static func protoField(_ message: [UInt8], _ field: UInt64) -> [UInt8]? {
        var at = 0
        func varint() -> UInt64? {
            var value: UInt64 = 0
            var shift: UInt64 = 0
            while at < message.count && shift < 64 {
                let b = message[at]
                at += 1
                value |= UInt64(b & 0x7F) << shift
                if b & 0x80 == 0 { return value }
                shift += 7
            }
            return nil
        }
        while at < message.count {
            guard let key = varint() else { return nil }
            switch key & 7 {
            case 0: guard varint() != nil else { return nil }
            case 1: at += 8
            case 5: at += 4
            case 2:
                guard let length = varint(), at + Int(length) <= message.count else { return nil }
                if key >> 3 == field { return Array(message[at..<(at + Int(length))]) }
                at += Int(length)
            default: return nil
            }
        }
        return nil
    }

    // MARK: - PSBT (test-only serializer, to build tampered answers)

    static func compactSize(_ n: Int) -> [UInt8] {
        if n < 0xFD { return [UInt8(n)] }
        if n <= 0xFFFF { return [0xFD, UInt8(n & 0xFF), UInt8(n >> 8)] }
        return [0xFE, UInt8(n & 0xFF), UInt8((n >> 8) & 0xFF), UInt8((n >> 16) & 0xFF), UInt8((n >> 24) & 0xFF)]
    }

    /// The bytes of `maps` (magic, then each map as compact(key) ‖ key ‖ compact(value) ‖ value, `00` after each map), with
    /// `extra` entries appended to input map `input` or output map `output`.
    static func psbtBytes(_ maps: BILPsbtMaps, input: Int? = nil, output: Int? = nil, _ extra: [(key: [UInt8], value: [UInt8])] = []) -> [UInt8] {
        var out: [UInt8] = [0x70, 0x73, 0x62, 0x74, 0xFF]
        func write(_ entries: [(key: [UInt8], value: [UInt8])]) {
            for e in entries { out += compactSize(e.key.count) + e.key + compactSize(e.value.count) + e.value }
            out.append(0x00)
        }
        write(maps.global.map { (key: $0.key, value: $0.value) })
        for (i, map) in maps.inputs.enumerated() { write(map.map { (key: $0.key, value: $0.value) } + (i == input ? extra : [])) }
        for (i, map) in maps.outputs.enumerated() { write(map.map { (key: $0.key, value: $0.value) } + (i == output ? extra : [])) }
        return out
    }

    static func word(_ n: UInt64) -> String {
        let h = String(n, radix: 16)
        return String(repeating: "0", count: 64 - h.count) + h
    }

    static let ABANDON_ETH = "0x9858EfFD232B4033E47d90003D41EC34EcaEda94"
    static let UNISWAP_ROUTER = "0x66a9893cc07d91d95644aedd05d03f95e1dba8af"

    /// A synthetic EVM request + ready plan (Android `PublicSignInsightTest.syntheticEvm`): the signed bytes carry
    /// `txChainId`, the request / CBOR / transport `requestChainId`. `type`: 2 = EIP-1559 (default), 1 = EIP-2930
    /// (`01 ‖ rlp([chainId, nonce, gasPrice, gas, to, value, data, accessList])`), 0 = legacy EIP-155
    /// (`rlp([nonce, gasPrice, gas, to, value, data, chainId, 0, 0])`); `dataType`: CBOR key 3 (1 legacy, 4 typed).
    static func syntheticEvm(to: String, data: String, txChainId: UInt64 = 1, requestChainId: UInt64? = nil, cborChainId: UInt64? = nil,
                      type: UInt8 = 2, dataType: UInt64 = 4) -> (request: BILJSONObject, plan: BILPublicPlan) {
        let reqChain = requestChainId ?? txChainId
        let signData: [UInt8]
        switch type {
        case 0:
            signData = rlpList([rlpUInt(1), rlpUInt(1_000_000_000), rlpUInt(200_000), rlpBytes(hexBytes(to)), rlpUInt(0),
                                rlpBytes(hexBytes(data)), rlpUInt(txChainId), rlpUInt(0), rlpUInt(0)])
        case 1:
            signData = [0x01] + rlpList([rlpUInt(txChainId), rlpUInt(1), rlpUInt(1_000_000_000), rlpUInt(200_000),
                                         rlpBytes(hexBytes(to)), rlpUInt(0), rlpBytes(hexBytes(data)), rlpList([])])
        default:
            signData = [0x02] + rlpList([rlpUInt(txChainId), rlpUInt(1), rlpUInt(1_000_000_000), rlpUInt(2_000_000_000), rlpUInt(200_000),
                                         rlpBytes(hexBytes(to)), rlpUInt(0), rlpBytes(hexBytes(data)), rlpList([])])
        }
        let digest = BILPublicHex.encode(BILPublicHash.keccak256(signData))
        let id = [UInt8](repeating: 7, count: 16)
        let cbor = TestUr.cbor(.map([(.int(1), .tag(37, .bytes(id))), (.int(2), .bytes(signData)), (.int(3), .int(dataType)),
                                     (.int(4), .int(cborChainId ?? reqChain))]))
        let transport = BILJSONObject([
            ("type", .string("eth-sign-request")), ("payloadEncoding", .string("cbor")), ("payloadBytes", .string(BILPublicHex.encode(cbor))),
            ("requestId", .string(BILPublicHex.encode(id))), ("chainId", .int(reqChain)),
        ])
        let request = BILJSONObject([
            ("chain", .string("evm")), ("path", .string("m/44'/60'/0'/0/0")), ("kind", .string("transaction")),
            ("transaction", .string("0x" + BILPublicHex.encode(signData))), ("chainId", .int(reqChain)), ("transport", .object(transport)),
        ])
        let hash = repeatHex("ab", 32)
        let review = BILJSONObject([
            ("chain", .string("evm")), ("title", .string("Contract call")), ("requestHash", .string(hash)),
            ("fields", .array([.object(BILJSONObject([("label", .string("Network")), ("value", .string("Ethereum"))]))])),
            ("warnings", .array([])), ("canSign", .bool(true)), ("decodeStatus", .string("partiallyDecoded")), ("riskLevel", .string("warning")),
            ("network", .object(BILJSONObject([("chainId", .string(String(txChainId))), ("name", .string("Ethereum"))]))),
        ])
        let task = BILJSONObject([
            ("id", .string("task-1")), ("localWalletId", .string("wallet-abandon")),
            ("walletKeyId", .string("95f7c3fcf6b598ef252e4ee3857f84e712d3264719314d8ccc1bbeceed2d9a34")), ("chain", .string("evm")),
            ("paths", .array([.string("m/44'/60'/0'/0/0")])),
            ("publicKeys", .array([.string("0237b0bb7a8288d38ed49a524b5dc98cff3eb5ca824c9f9dc0dfdb3d9cd600f299")])),
            ("addresses", .array([.string(ABANDON_ETH)])), ("signingBytesDigest", .string(digest)),
        ])
        let plan = BILJSONObject([
            ("version", .int(1)), ("status", .string("ready")), ("requestHash", .string(hash)), ("planHash", .string(repeatHex("cd", 32))),
            ("chain", .string("evm")), ("signingBytesDigest", .string(digest)), ("review", .object(review)), ("tasks", .array([.object(task)])),
        ])
        return (request, SigningVectors.planOf(plan))
    }

    // MARK: - Tests

    static func verifierTests() {
        section("every answered vector flow passes pre and post (8 payload kinds)")
        var kinds = Set<String>()
        // Pinned: a lost (or new) vector flow must show up here, not be absorbed by a bound.
        eq(SigningVectors.answeredFlows.count, 64, "answered vector flows")
        for id in SigningVectors.answeredFlows {
            guard let payload = expectOk(SigningVectors.pre(id), "pre \(id)") else { continue }
            kinds.insert(kindName(payload))
            expectOk(postVector(id), "post \(id)")
        }
        eq(kinds, ["EvmTransaction", "EvmPersonal", "EvmTypedData", "TronTransaction", "TronMessage", "SolanaTransaction", "SolanaMessage",
                   "BitcoinPsbt"], "payload kinds of the answered flows")

        section("pre: EVM digest = keccak(signed bytes), chain id = reviewed network")
        do {
            let id = "T8-flow-evm-eip1559"
            let plan = SigningVectors.plan(id)
            if case .evmTransaction(_, let tx)? = SigningVectors.pre(id).payload {
                eq(tx.chainId, UInt64(1), "EIP-1559 chain id")
                eq(BILPublicHex.encode(tx.signingHash), plan.signingBytesDigest ?? "", "digest = keccak(signData)")
            } else {
                t(false, "EIP-1559 is an EVM transaction")
            }
            expectRefused(SigningVectors.pre(id, plan: SigningVectors.planOf(withDigest(SigningVectors.planJson(id), repeatHex("00", 32)))),
                          detail: "evm.digest", "plan digest 00×32")
            expectRefused(V.pre(request: SigningVectors.request(id), plan: plan, reviewedChainId: "56"), .CHAIN_MISMATCH,
                          detail: "evm.chainId.review", "review shows chain 56")
            expectRefused(V.pre(request: SigningVectors.request(id), plan: plan, reviewedChainId: nil), .CHAIN_MISMATCH,
                          detail: "evm.chainId.review", "review shows no chain id")
            let request = SigningVectors.request(id)
            let swapped = with(request, "transaction",
                               .string("0x02e70180843b9aca0084773594008252089422222222222222222222222222222222222222220280c0"))
            expectRefused(SigningVectors.pre(id, request: swapped), detail: "evm.transaction.differs", "engine request ≠ QR bytes")
            expectRefused(SigningVectors.pre(id, request: without(request, "transport")), detail: "request.transport", "no transport")
            let transport = request.obj("transport") ?? BILJSONObject()
            expectRefused(SigningVectors.pre(id, request: with(request, "transport", .object(without(transport, "type")))),
                          detail: "transport.type", "no transport type")
            expectRefused(SigningVectors.pre(id, request: with(request, "transport", .object(with(transport, "payloadBytes", .string("0xab"))))),
                          detail: "transport.payloadBytes", "payloadBytes with 0x")
            expectRefused(SigningVectors.pre(id, request: with(request, "transport", .object(with(transport, "payloadBytes", .number("1"))))),
                          detail: "transport.payloadBytes", "payloadBytes not a string")
            expectRefused(SigningVectors.pre(id, request: with(request, "chain", .string("tron"))), detail: "request.chain", "request chain ≠ plan")
            expectRefused(SigningVectors.pre(id, request: with(request, "kind", .string("personal"))), detail: "evm.kind", "kind ≠ dataType")
            expectRefused(SigningVectors.pre(id, request: with(request, "chainId", .string("1"))), detail: "evm.chainId.request",
                          "request chainId as a string (strict typing)")
            expectRefused(SigningVectors.pre(id, request: with(request, "transport", .object(with(transport, "payloadEncoding", .string("hex"))))),
                          detail: "evm.transport", "payloadEncoding not cbor")
            // A non-ready plan / two tasks on a non-Bitcoin chain.
            var notReady = SigningVectors.planJson(id)
            notReady.set("status", .string("noMatch"))
            notReady.set("tasks", .array([]))
            expectRefused(SigningVectors.pre(id, plan: SigningVectors.planOf(notReady)), detail: "plan.ready", "plan not ready")
            var two = SigningVectors.planJson(id)
            if let first = two.arr("tasks")?.first?.objectValue {
                two.set("tasks", .array([.object(first), .object(with(first, "id", .string("second-task")))]))
            }
            expectRefused(SigningVectors.pre(id, plan: SigningVectors.planOf(two)), detail: "plan.tasks", "two EVM tasks")
            // Log safety: a verdict prints its kind only.
            let text = String(describing: SigningVectors.pre(id))
            t(!text.contains("e70180843b9aca") && text.hasPrefix("Ok("), "verdict description has no payload bytes: \(text)")
        }

        section("C-EVM-2: request chain id ≠ unsigned-tx chain id → err.chainMismatch")
        do {
            let s = syntheticEvm(to: "0x" + repeatHex("22", 20), data: "a9059cbb" + word(1) + word(2), txChainId: 56, requestChainId: 1)
            let v = V.pre(request: s.request, plan: s.plan, reviewedChainId: "56")
            expectRefused(v, .CHAIN_MISMATCH, detail: "evm.chainId.request", "tx on 56, request / CBOR / transport say 1")
            eq(BILPublicSignerErrors.verifierKey("CHAIN_MISMATCH"), "PublicProtocol.err.chainMismatch", "CHAIN_MISMATCH → err.chainMismatch")
            let same = syntheticEvm(to: "0x" + repeatHex("22", 20), data: "a9059cbb" + word(1) + word(2), txChainId: 56)
            expectOk(V.pre(request: same.request, plan: same.plan, reviewedChainId: "56"), "tx, request and review all on 56")
            let cbor = syntheticEvm(to: "0x" + repeatHex("22", 20), data: "a9059cbb", txChainId: 1, requestChainId: 1, cborChainId: 56)
            expectRefused(V.pre(request: cbor.request, plan: cbor.plan, reviewedChainId: "1"), .INTEGRITY, detail: "evm.chainId.request",
                          "CBOR key 4 ≠ request chainId (QR ≠ engine request)")
        }

        section("pre: the CBOR dataType names the transaction type (1 = legacy, 4 = typed; EIP-2930 included)")
        do {
            let to = "0x" + repeatHex("22", 20)
            let eip2930 = syntheticEvm(to: to, data: "a9059cbb", type: 1, dataType: 4)
            if case .evmTransaction(_, let tx)? = expectOk(V.pre(request: eip2930.request, plan: eip2930.plan, reviewedChainId: "1"),
                                                           "EIP-2930 (type 1) with dataType 4") {
                eq(tx.type, 1, "EIP-2930 transaction type")
                eq(BILPublicHex.encode(tx.signingHash), eip2930.plan.signingBytesDigest ?? "", "EIP-2930 digest = keccak(signData)")
            } else {
                t(false, "EIP-2930 is an EVM transaction")
            }
            let legacy = syntheticEvm(to: to, data: "a9059cbb", type: 0, dataType: 1)
            if case .evmTransaction(_, let tx)? = expectOk(V.pre(request: legacy.request, plan: legacy.plan, reviewedChainId: "1"),
                                                           "legacy EIP-155 with dataType 1") {
                eq(tx.type, 0, "legacy transaction type")
            } else {
                t(false, "legacy is an EVM transaction")
            }
            let typedAsLegacy = syntheticEvm(to: to, data: "a9059cbb", type: 2, dataType: 1)
            expectRefused(V.pre(request: typedAsLegacy.request, plan: typedAsLegacy.plan, reviewedChainId: "1"), detail: "evm.dataType",
                          "EIP-1559 bytes declared dataType 1 (legacy)")
            let eip2930AsLegacy = syntheticEvm(to: to, data: "a9059cbb", type: 1, dataType: 1)
            expectRefused(V.pre(request: eip2930AsLegacy.request, plan: eip2930AsLegacy.plan, reviewedChainId: "1"), detail: "evm.dataType",
                          "EIP-2930 bytes declared dataType 1 (legacy)")
            let legacyAsTyped = syntheticEvm(to: to, data: "a9059cbb", type: 0, dataType: 4)
            expectRefused(V.pre(request: legacyAsTyped.request, plan: legacyAsTyped.plan, reviewedChainId: "1"), detail: "evm.dataType",
                          "legacy bytes declared dataType 4 (typed)")
        }

        section("pre: personal_sign, typed data, TRON and Solana digests")
        do {
            if case .evmPersonal? = SigningVectors.pre("T8-flow-evm-personal").payload {} else { t(false, "personal → EvmPersonal") }
            if case .evmTypedData(_, let chainId, let has)? = SigningVectors.pre("T8-flow-evm-typed-data").payload {
                t(has, "typed data has a domain chain id")
                t(chainId != nil, "typed data domain chain id read")
            } else {
                t(false, "typed data → EvmTypedData")
            }
            if case .evmTypedData(_, let chainId, let has)? = SigningVectors.pre("O-EVM-5-permit2-no-chain-id").payload {
                t(!has && chainId == nil, "Permit2 without domain chain id")
            } else {
                t(false, "O-EVM-5 → EvmTypedData")
            }
            if case .tronTransaction(_, _, let owner, let type, let proto)? = SigningVectors.pre("T8-flow-tron-trx-transfer").payload {
                eq(owner, "41c8599111f29c1e1e061265b4af93ea1f274ad78a", "TRON owner")
                eq(type, 1, "TRON TransferContract")
                t(proto == nil, "UR request has no TronLink proto")
            } else {
                t(false, "TRON transfer → TronTransaction")
            }
            if case .tronMessage? = SigningVectors.pre("T8-flow-tron-message").payload {} else { t(false, "TRON message → TronMessage") }
            if case .solanaTransaction(_, _, let slot)? = SigningVectors.pre("T8-flow-solana-transfer").payload {
                eq(slot, 0, "Solana signer slot")
            } else {
                t(false, "Solana transfer → SolanaTransaction")
            }
            if case .solanaMessage? = SigningVectors.pre("T8-flow-solana-message").payload {} else { t(false, "Solana message → SolanaMessage") }
            for id in ["T8-flow-evm-personal", "T8-flow-tron-trx-transfer", "T8-flow-tron-message", "T8-flow-solana-transfer",
                       "T8-flow-solana-message", "T8-flow-bitcoin-crypto-psbt"] {
                expectRefused(SigningVectors.pre(id, plan: SigningVectors.planOf(withDigest(SigningVectors.planJson(id), repeatHex("11", 32)))),
                              .INTEGRITY, "\(id): plan digest 11×32")
            }
            // EIP-712: the digest is the engine's (documented C-GEN-4 gap), the text is bound to the QR bytes.
            let typed = "T8-flow-evm-typed-data"
            expectOk(SigningVectors.pre(typed, plan: SigningVectors.planOf(withDigest(SigningVectors.planJson(typed), repeatHex("11", 32)))),
                     "typed data keeps the engine's digest")
            let typedRequest = SigningVectors.request(typed)
            if var td = typedRequest.obj("typedData") {
                td.set("primaryType", .string("Other"))
                expectRefused(SigningVectors.pre(typed, request: with(typedRequest, "typedData", .object(td))), detail: "evm.typedData.differs",
                              "engine typed data ≠ QR text")
            }
            expectRefused(SigningVectors.pre(typed, request: without(typedRequest, "typedData")), detail: "evm.typedData", "no typedData")
            // TRON: txID claimed by the request must be sha256(raw); kind must match.
            let tron = "T8-flow-tron-trx-transfer"
            let tronRequest = SigningVectors.request(tron)
            if let tx = tronRequest.obj("transaction") {
                expectRefused(SigningVectors.pre(tron, request: with(tronRequest, "transaction", .object(with(tx, "txID", .string(repeatHex("00", 32)))))),
                              detail: "tron.txID", "TRON txID ≠ sha256(raw)")
                // The vectors carry no txID; an upper-case copy of sha256(raw) is accepted (Android `equals(ignoreCase = true)`).
                let upper = BILPublicHash.sha256Hex(hexBytes(tx.str("raw_data_hex") ?? "")).uppercased()
                expectOk(SigningVectors.pre(tron, request: with(tronRequest, "transaction", .object(with(tx, "txID", .string(upper))))),
                         "TRON txID compared ignoring case")
                expectOk(SigningVectors.pre(tron, request: with(tronRequest, "transaction", .object(with(tx, "txID", .number("1"))))),
                         "a non-string txID is no txID (Android `str`), the digest still binds the raw data")
                expectRefused(SigningVectors.pre(tron, request: with(tronRequest, "transaction", .object(with(tx, "raw_data_hex", .string("0a00"))))),
                              detail: "tron.raw.differs", "TRON raw ≠ QR")
            }
            expectRefused(SigningVectors.pre(tron, request: with(tronRequest, "kind", .string("message"))), detail: "tron.kind", "TRON kind")
            // The contract's owner field must be a 21-byte `41…` address (same lengths, version byte 0x42 instead).
            if let tx = tronRequest.obj("transaction"), let rawHex = tx.str("raw_data_hex"),
               let id = tronRequest.obj("transport")?.str("requestId") {
                let owner = "41c8599111f29c1e1e061265b4af93ea1f274ad78a"
                t(rawHex.contains(owner), "TRON raw holds the owner")
                let raw = hexBytes(rawHex.replacingOccurrences(of: owner, with: "42" + String(owner.dropFirst(2))))
                let cbor = TestUr.cbor(.map([(.int(1), .tag(37, .bytes(hexBytes(id)))), (.int(2), .bytes(raw)), (.int(3), .int(1))]))
                let transport = with(tronRequest.obj("transport") ?? BILJSONObject(), "payloadBytes", .string(BILPublicHex.encode(cbor)))
                let request = with(with(tronRequest, "transaction", .object(with(tx, "raw_data_hex", .string(BILPublicHex.encode(raw))))),
                                   "transport", .object(transport))
                let plan = SigningVectors.planOf(withDigest(SigningVectors.planJson(tron), BILPublicHash.sha256Hex(raw)))
                expectRefused(V.pre(request: request, plan: plan, reviewedChainId: nil), detail: "tron.owner", "TRON owner not 41…")
                let ok = TestUr.cbor(.map([(.int(1), .tag(37, .bytes(hexBytes(id)))), (.int(2), .bytes(hexBytes(rawHex))), (.int(3), .int(1))]))
                let okRequest = with(tronRequest, "transport", .object(with(tronRequest.obj("transport") ?? BILJSONObject(), "payloadBytes",
                                                                             .string(BILPublicHex.encode(ok)))))
                expectOk(V.pre(request: okRequest, plan: SigningVectors.plan(tron), reviewedChainId: nil), "the same rebuilt CBOR with the real owner")
            }
            // Solana: the plan's signer slot must be the native one.
            let sol = "T8-flow-solana-transfer"
            var solPlan = SigningVectors.planJson(sol)
            if let task = solPlan.arr("tasks")?.first?.objectValue, let target = task.arr("targets")?.first?.objectValue {
                let moved = with(task, "targets", .array([.object(with(target, "signerSlot", .int(1)))]))
                solPlan.set("tasks", .array([.object(moved)]))
                expectRefused(SigningVectors.pre(sol, plan: SigningVectors.planOf(solPlan)), detail: "solana.signerSlot.plan",
                              "plan's Solana signer slot ≠ native")
            }
            let solRequest = SigningVectors.request(sol)
            expectRefused(SigningVectors.pre(sol, request: with(solRequest, "message", .string("cHNidP8"))), detail: "base64",
                          "Solana message not strict Base64")
        }

        section("pre: Kotlin single() on the task keys — refusal names (deviation 6)")
        do {
            let sol = "T8-flow-solana-transfer"
            let plan = SigningVectors.plan(sol)
            var json = SigningVectors.planJson(sol)
            if let task = json.arr("tasks")?.first?.objectValue, let path = plan.tasks.first?.paths.first, let key = plan.tasks.first?.publicKeys.first {
                json.set("tasks", .array([.object(with(with(task, "paths", .array([.string(path), .string(path)])), "publicKeys",
                                                       .array([.string(key), .string(key)])))]))
                expectRefused(SigningVectors.pre(sol, plan: SigningVectors.planOf(json)), detail: "IllegalArgumentException",
                              "two task keys (Android: IllegalArgumentException, caught)")
            }
            // No key at all: a parsed plan never has it (one key per non-empty path); built directly to name the refusal.
            if let t0 = plan.tasks.first {
                let bare = BILPublicTask(id: t0.id, localWalletId: t0.localWalletId, walletKeyId: t0.walletKeyId, chain: t0.chain, paths: t0.paths,
                                         publicKeys: [], addresses: t0.addresses, inputs: t0.inputs, signatureAlgorithm: t0.signatureAlgorithm,
                                         signingBytesDigest: t0.signingBytesDigest, signerSlot: t0.signerSlot, raw: t0.raw)
                let noKey = BILPublicPlan(status: plan.status, message: plan.message, chain: plan.chain, requestHash: plan.requestHash,
                                          planHash: plan.planHash, payloadDigest: plan.payloadDigest, signingBytesDigest: plan.signingBytesDigest,
                                          protocolProfile: plan.protocolProfile, review: plan.review, tasks: [bare], raw: plan.raw)
                expectRefused(SigningVectors.pre(sol, plan: noKey), detail: "NoSuchElementException",
                              "no task key (Kotlin NoSuchElementException; Android lets it escape)")
            }
        }

        section("pre: the request's message, kind and transport chain id are the QR's (R5 §3.1)")
        do {
            // The engine shows the request's text; the digest is over the QR bytes — only these checks tie the two together.
            let personal = "T8-flow-evm-personal"
            let personalRequest = SigningVectors.request(personal)
            expectRefused(SigningVectors.pre(personal, request: with(personalRequest, "message", .string("0x" + BILPublicHex.encode(Array("other".utf8))))),
                          detail: "evm.message.differs", "personal: the request's message ≠ the QR's")
            expectRefused(SigningVectors.pre(personal, request: with(personalRequest, "kind", .string("transaction"))), detail: "evm.kind",
                          "personal (dataType 3) with kind transaction")
            let tronMessage = "T8-flow-tron-message"
            expectRefused(SigningVectors.pre(tronMessage, request: with(SigningVectors.request(tronMessage), "message",
                                                                        .string(BILPublicHex.encode(Array("other".utf8))))),
                          detail: "tron.message.differs", "TRON message: the request's message ≠ the QR's")
            expectRefused(SigningVectors.pre("T8-flow-solana-transfer", request: with(SigningVectors.request("T8-flow-solana-transfer"), "kind",
                                                                                      .string("message"))),
                          detail: "solana.kind", "Solana transaction (signType 1) with kind message")
            expectRefused(SigningVectors.pre("T8-flow-solana-message", request: with(SigningVectors.request("T8-flow-solana-message"), "kind",
                                                                                     .string("transaction"))),
                          detail: "solana.kind", "Solana message (signType 2) with kind transaction")
            let evm = "T8-flow-evm-eip1559"
            let evmRequest = SigningVectors.request(evm)
            let evmTransport = evmRequest.obj("transport") ?? BILJSONObject()
            expectRefused(SigningVectors.pre(evm, request: with(evmRequest, "transport", .object(with(evmTransport, "chainId", .int(56))))),
                          .INTEGRITY, detail: "evm.chainId.request", "transport chainId 56, request / CBOR say 1")
        }

        section("pre: TRON / TronLink structure and Solana message validity")
        do {
            typealias W = OtherWalletVectors
            // A second `contract` (field 11) appended to raw_data: exactly one contract is signed.
            let tron = "T8-flow-tron-trx-transfer"
            let tronRequest = SigningVectors.request(tron)
            if let tx = tronRequest.obj("transaction"), let rawHex = tx.str("raw_data_hex"), let id = tronRequest.obj("transport")?.str("requestId"),
               let contract = protoField(hexBytes(rawHex), 11) {
                let raw = hexBytes(rawHex) + protoBytesField(11, contract)
                let cbor = TestUr.cbor(.map([(.int(1), .tag(37, .bytes(hexBytes(id)))), (.int(2), .bytes(raw)), (.int(3), .int(1))]))
                let transport = with(tronRequest.obj("transport") ?? BILJSONObject(), "payloadBytes", .string(BILPublicHex.encode(cbor)))
                let request = with(with(tronRequest, "transaction", .object(with(tx, "raw_data_hex", .string(BILPublicHex.encode(raw))))),
                                   "transport", .object(transport))
                let plan = SigningVectors.planOf(withDigest(SigningVectors.planJson(tron), BILPublicHash.sha256Hex(raw)))
                expectRefused(V.pre(request: request, plan: plan, reviewedChainId: nil), detail: "tron.contracts", "TRON UR: two contracts")
            } else {
                t(false, "TRON transfer raw data has a contract")
            }
            // The same in a TronLink entry.
            let v3 = "O-TL-V3-trx-transfer"
            let baseRaw = hexBytes(String(W.V3_ENTRY.dropFirst(6)))
            if let contract = protoField(baseRaw, 11), let proto = BILTronTransactionProto.encode(raw: baseRaw + protoBytesField(11, contract), signatures: []),
               let split = BILTronTransactionProto.split(proto) {
                let text = W.V3_REQUEST.replacingOccurrences(of: W.V3_ENTRY, with: BILPublicHex.encode(proto))
                let plan = SigningVectors.planOf(withDigest(SigningVectors.planJson(v3), BILPublicHash.sha256Hex(split.raw)))
                expectRefused(V.pre(request: tronLinkRequest(text), plan: plan, reviewedChainId: nil), detail: "tronlink.contracts",
                              "TronLink: two contracts")
            } else {
                t(false, "TronLink entry with two contracts")
            }
            // The ownership placeholder must not carry a signature yet (the mapper accepts it and lists the signature).
            let v1 = "O-TL-V1-ownership-ios"
            let signedText = W.V1_REQUEST.replacingOccurrences(of: W.V1_ENTRY, with: W.V1_ENTRY + "1241" + W.V1_SIG)
            let signedRequest = tronLinkRequest(signedText)
            t(signedRequest.obj("transaction")?.arr("signature")?.count == 1, "the mapper lists the placeholder's signature")
            expectRefused(V.pre(request: signedRequest, plan: SigningVectors.plan(v1), reviewedChainId: nil), detail: "tronlink.proof",
                          "TronLink ownership placeholder that is already signed")
            // A TronLink hex message (type 103): the engine-native request carries `encoding: hex`.
            let v4 = "O-TL-V4-tip191-message"
            let hexText = "{\"address\":\"\(W.TRON_0)\",\"type\":103,\"hexList\":[\"\(BILPublicHex.encode(Array("hello ownbit".utf8)))\"]}"
            let hexRequest = tronLinkRequest(hexText)
            eq(hexRequest.str("encoding") ?? "", "hex", "type 103 → encoding hex")
            let hexPlan = SigningVectors.planOf(withDigest(SigningVectors.planJson(v4),
                                                           BILPublicHex.encode(BILPublicHash.tip191Digest(Array("hello ownbit".utf8)))))
            if case .tronMessage(let m)? = expectOk(V.pre(request: hexRequest, plan: hexPlan, reviewedChainId: nil), "TronLink hex message") {
                eq(String(decoding: m, as: UTF8.self), "hello ownbit", "hex message bytes")
            } else {
                t(false, "TronLink hex message → TronMessage")
            }
            // A Solana off-chain message must be printable UTF-8 (first byte 0x01 is a transaction header, not text).
            let solMessage = "T8-flow-solana-message"
            let solRequest = SigningVectors.request(solMessage)
            let original = BILBase64Strict.decode(solRequest.str("message") ?? "") ?? []
            let bad: [UInt8] = [0x01, 0x61, 0x62, 0x63]
            let payload = solRequest.obj("transport")?.str("payloadBytes") ?? ""
            let oldHex = BILPublicHex.encode(TestUr.cbor(.bytes(original)))
            t(!original.isEmpty && payload.contains(oldHex), "the Solana CBOR holds the message bytes")
            let transport = with(solRequest.obj("transport") ?? BILJSONObject(), "payloadBytes",
                                 .string(payload.replacingOccurrences(of: oldHex, with: BILPublicHex.encode(TestUr.cbor(.bytes(bad))))))
            let request = with(with(solRequest, "message", .string(BILBase64Strict.encode(bad))), "transport", .object(transport))
            let plan = SigningVectors.planOf(withDigest(SigningVectors.planJson(solMessage), BILPublicHash.sha256Hex(bad)))
            expectRefused(V.pre(request: request, plan: plan, reviewedChainId: nil), detail: "solana.offchainMessage",
                          "Solana message 01 61 62 63 (not printable text)")
            // Control: the rebuilt CBOR with the original message still verifies.
            let same = with(solRequest.obj("transport") ?? BILJSONObject(), "payloadBytes",
                            .string(payload.replacingOccurrences(of: oldHex, with: BILPublicHex.encode(TestUr.cbor(.bytes(original))))))
            expectOk(SigningVectors.pre(solMessage, request: with(solRequest, "transport", .object(same))), "the same CBOR rebuilt")
        }

        section("pre: the request id to echo is the one of the QR bytes (O-RESP-1, C-EVM-9)")
        do {
            for id in ["O-RESP-1-imtoken-36-byte-id", "T8-flow-tron-trx-transfer", "T8-flow-solana-transfer", "T8-flow-evm-personal-without-request-id"] {
                expectOk(SigningVectors.pre(id), "\(id) request id")
            }
            let id = "O-RESP-1-imtoken-36-byte-id"
            let request = SigningVectors.request(id)
            let original = request.obj("transport")?.str("requestId") ?? ""
            eq(original.utf16.count, 72, "imToken's 36-byte id")
            // The same tampering on every transport with a request id: EVM (O-RESP-1), TRON UR and Solana.
            for flow in [id, "T8-flow-tron-trx-transfer", "T8-flow-solana-transfer"] {
                let flowRequest = SigningVectors.request(flow)
                let transport = flowRequest.obj("transport") ?? BILJSONObject()
                let flowId = transport.str("requestId") ?? ""
                t(!flowId.isEmpty, "\(flow) has a request id")
                func withId(_ value: String?) -> BILJSONObject {
                    let tr = value.map { with(transport, "requestId", .string($0)) } ?? without(transport, "requestId")
                    return with(flowRequest, "transport", .object(tr))
                }
                expectRefused(SigningVectors.pre(flow, request: withId(flowId + "00")), detail: "request.requestId", "\(flow): one byte more")
                expectRefused(SigningVectors.pre(flow, request: withId((flowId.hasPrefix("ff") ? "00" : "ff") + String(flowId.dropFirst(2)))),
                              detail: "request.requestId", "\(flow): first byte")
                expectRefused(SigningVectors.pre(flow, request: withId(nil)), detail: "request.requestId", "\(flow): id dropped from the engine request")
                expectRefused(SigningVectors.pre(flow, request: withId("zz")), detail: "transport.requestId", "\(flow): id not hex")
            }
            let none = "T8-flow-evm-personal-without-request-id"
            let noneRequest = SigningVectors.request(none)
            let added = with(noneRequest, "transport", .object(with(noneRequest.obj("transport") ?? BILJSONObject(), "requestId",
                                                                     .string(repeatHex("00", 16)))))
            expectRefused(SigningVectors.pre(none, request: added), detail: "request.requestId", "id added although the QR has none")
            // C-EVM-9: the answer echoes the 36-byte id; an altered id is not returned.
            expectOk(postVector(id), "O-RESP-1 answer echoes the 36-byte id")
            let signature = hexBytes(SigningVectors.finalResult(id).raw.str("qrSignature") ?? SigningVectors.finalResult(id).raw.str("signature") ?? "")
            let altered = "00" + String(original.dropFirst(2))
            let response = BILPublicResponseQr(type: "eth-signature", frames: [TestUr.signature("eth-signature", altered, signature)], payload: nil)
            expectRefused(postVector(id, response: response), .VERIFY, detail: "response.requestId", "answer with an altered id")
            eq(BILPublicSignerErrors.verifierKey("VERIFY"), "PublicProtocol.err.verify", "VERIFY → err.verify")
        }

        section("pre: a Solana lookup table is its own refusal")
        do {
            if let request = SigningVectors.steps("O-SOL-2-lookup-table", "resolveSigningPlan").first?.request.obj("request"),
               let message = request.str("message"), let bytes = BILBase64Strict.decode(message) {
                let plan = SigningVectors.planOf(withDigest(SigningVectors.planJson("T8-flow-solana-transfer"), BILPublicHash.sha256Hex(bytes)))
                expectRefused(V.pre(request: request, plan: plan, reviewedChainId: nil), .LOOKUP_TABLE, detail: "solana.lookupTables",
                              "v0 message with a lookup table")
                eq(BILPublicSignerErrors.verifierKey("LOOKUP_TABLE"), "PublicProtocol.err.lookupTable", "LOOKUP_TABLE → err.lookupTable")
            } else {
                t(false, "O-SOL-2 request present")
            }
        }

        section("post: another request id, an extra key, a missing id or a foreign signature are refused")
        do {
            let id = "T8-flow-evm-eip1559"
            let requestId = SigningVectors.request(id).obj("transport")?.str("requestId") ?? ""
            let signature = hexBytes(SigningVectors.finalResult(id).raw.str("qrSignature") ?? "")
            func answer(_ frame: String) -> BILPublicResponseQr {
                return BILPublicResponseQr(type: "eth-signature", frames: [frame], payload: nil)
            }
            expectOk(postVector(id, response: answer(TestUr.signature("eth-signature", requestId, signature))), "rebuilt answer")
            expectRefused(postVector(id, response: answer(TestUr.signature("eth-signature", "00" + String(requestId.dropFirst(2)), signature))),
                          .VERIFY, detail: "response.requestId", "other id")
            expectRefused(postVector(id, response: answer(TestUr.signature("eth-signature", nil, signature))), .VERIFY,
                          detail: "response.requestId", "no id")
            expectRefused(postVector(id, response: answer(TestUr.signature("eth-signature", requestId, signature, extra: [(.int(3), .text("origin"))]))),
                          .VERIFY, detail: "signature.keys", "extra key 3")
            expectRefused(postVector(id, response: answer(TestUr.signature("sol-signature", requestId, signature))), .VERIFY,
                          detail: "response.urType", "sol-signature UR")
            expectRefused(postVector(id, response: BILPublicResponseQr(type: "sol-signature", frames: [TestUr.signature("eth-signature", requestId, signature)],
                                                                       payload: nil)), .VERIFY, detail: "response.type", "answer type")
            var flipped = signature
            flipped[10] ^= 1
            let forged = resultWith(id, "qrSignature", BILPublicHex.encode(flipped))
            expectRefused(postVector(id, response: answer(TestUr.signature("eth-signature", requestId, flipped))), .VERIFY,
                          detail: "response.signature.result", "QR ≠ engine result")
            expectRefused(postVector(id, response: answer(TestUr.signature("eth-signature", requestId, flipped)), result: forged), .VERIFY,
                          detail: "evm.signature.signer", "forged result and QR")
            var wrongV = signature
            wrongV[64] = 1
            let wrongVResult = resultWith(id, "qrSignature", BILPublicHex.encode(wrongV))
            expectRefused(postVector(id, response: answer(TestUr.signature("eth-signature", requestId, wrongV)), result: wrongVResult), .VERIFY,
                          "v forced to 1")
            var v27 = signature
            v27[64] = 27
            expectRefused(postVector(id, response: answer(TestUr.signature("eth-signature", requestId, v27)),
                                     result: resultWith(id, "qrSignature", BILPublicHex.encode(v27))), .VERIFY, detail: "evm.signature.v",
                          "typed transaction with v 27")
            expectRefused(V.post(request: SigningVectors.request(id), plan: SigningVectors.plan(id), verified: nil,
                                 result: SigningVectors.finalResult(id), response: SigningVectors.response(id)), .VERIFY,
                          detail: "post.unverified", "post without the pre-check")
            expectRefused(postVector(id, result: resultWith(id, "requestHash", repeatHex("ab", 32))), .VERIFY, detail: "result.plan",
                          "result of another request")
        }

        section("post: EIP-155 legacy v (BSC 0x94, ETC 0x9d) and multi-byte v")
        do {
            for id in ["T8-flow-evm-legacy-eip155-bsc", "O-EVM-1-legacy-etc"] {
                expectOk(postVector(id), "\(id) legacy answer")
                let r = SigningVectors.finalResult(id)
                let sig = hexBytes(r.raw.str("qrSignature") ?? r.raw.str("signature") ?? "")
                let requestId = SigningVectors.request(id).obj("transport")?.str("requestId")
                var off = sig
                off[64] = off[64] &+ 2
                let response = BILPublicResponseQr(type: "eth-signature", frames: [TestUr.signature("eth-signature", requestId, off)], payload: nil)
                let key = r.raw.str("qrSignature") != nil ? "qrSignature" : "signature"
                expectRefused(postVector(id, response: response, result: resultWith(id, key, BILPublicHex.encode(off))), .VERIFY,
                              detail: "evm.signature.v", "\(id): v − 35 − 2·chainId = 2")
                var leadingZero = Array(sig[0..<64])
                leadingZero += [0x00, sig[64]]
                let lz = BILPublicResponseQr(type: "eth-signature", frames: [TestUr.signature("eth-signature", requestId, leadingZero)], payload: nil)
                expectRefused(postVector(id, response: lz, result: resultWith(id, key, BILPublicHex.encode(leadingZero))), .VERIFY,
                              detail: "evm.signature.v", "\(id): multi-byte v with a leading zero")
            }
        }

        section("post: a Solana answer with a 15-byte id, or a TRON signature of another key")
        do {
            let sol = "T8-flow-solana-transfer"
            let solSig = hexBytes(SigningVectors.finalResult(sol).raw.str("signature") ?? "")
            let solId = SigningVectors.request(sol).obj("transport")?.str("requestId") ?? ""
            expectRefused(postVector(sol, response: BILPublicResponseQr(type: "sol-signature", frames: [TestUr.signature("sol-signature", String(solId.dropFirst(2)), solSig)],
                                                                        payload: nil)), .VERIFY, detail: "response.requestId", "15-byte id")
            var badSol = solSig
            badSol[3] ^= 0x40
            expectRefused(postVector(sol, response: BILPublicResponseQr(type: "sol-signature", frames: [TestUr.signature("sol-signature", solId, badSol)], payload: nil),
                                     result: resultWith(sol, "signature", BILPublicHex.encode(badSol))), .VERIFY, detail: "solana.signature.verify",
                          "Ed25519 signature with a flipped bit")
            let tron = "T8-flow-tron-trx-transfer"
            let tronSig = hexBytes(SigningVectors.finalResult(tron).raw.str("signature") ?? "")
            var other = tronSig
            other[64] = 1 - other[64]
            let tronId = SigningVectors.request(tron).obj("transport")?.str("requestId")
            expectRefused(postVector(tron, response: BILPublicResponseQr(type: "tron-signature", frames: [TestUr.signature("tron-signature", tronId, other)], payload: nil),
                                     result: resultWith(tron, "signature", BILPublicHex.encode(other))), .VERIFY, "TRON: the other recovery id")
            // The TRON address of the recovered key (R5 §9 vector).
            if let pub = BILSecp256k1.recoverPublicKey(digest: hexBytes("2b4e75505adb4da63b985fa30cab925b334bf5c1432d547c79a780130f3423f5"), recId: 0,
                                                       r: Array(tronSig[0..<32]), s: Array(tronSig[32..<64])) {
                eq(V.tronAddress(uncompressed: pub) ?? "", "TUEZSdKsoDHQMeZwihtdoBiN46zxhGWYdH", "TRON vector key → TUEZ…")
            } else {
                t(false, "TRON vector signature recovers")
            }
        }

        section("post: a PSBT answer must be the result and differ only by the task signatures")
        do {
            let id = "T8-flow-bitcoin-crypto-psbt"
            let result = SigningVectors.finalResult(id)
            let signed = BILBase64Strict.decode(result.raw.str("psbt") ?? "") ?? []
            func answer(_ bytes: [UInt8]) -> BILPublicResponseQr {
                return BILPublicResponseQr(type: "crypto-psbt", frames: [TestUr.single("crypto-psbt", TestUr.cbor(.bytes(bytes)))], payload: nil)
            }
            expectOk(postVector(id, response: answer(signed)), "rebuilt crypto-psbt answer")
            let requestPsbt = BILBase64Strict.decode(SigningVectors.request(id).str("psbt") ?? "") ?? []
            expectRefused(postVector(id, response: answer(requestPsbt)), .VERIFY, detail: "response.psbt.result", "QR is the unsigned request")
            let unsignedResult = SigningVectors.resultOf(with(result.raw, "psbt", .string(BILBase64Strict.encode(requestPsbt))))
            expectRefused(postVector(id, response: answer(requestPsbt), result: unsignedResult), .VERIFY, detail: "response.psbt.diff",
                          "result and QR are the unsigned request: no signature added")
            var tampered = signed
            let at = indexOfOutputValue(tampered)
            tampered[at] = tampered[at] &+ 1
            let tamperedResult = SigningVectors.resultOf(with(result.raw, "psbt", .string(BILBase64Strict.encode(tampered))))
            expectRefused(postVector(id, response: answer(tampered), result: tamperedResult), .VERIFY, detail: "response.psbt.diff",
                          "output value changed (result and QR agree)")
            expectRefused(postVector(id, response: BILPublicResponseQr(type: "psbt-base64", frames: [BILBase64Strict.encode(signed)], payload: nil)),
                          .VERIFY, detail: "response.type", "another transport than the request's")
            // A static text PSBT answer above 1,800 characters must be animated crypto-psbt instead.
            let text = "T8-flow-bitcoin-psbt-base64-text"
            expectOk(postVector(text), "psbt-base64 answer")
            let textSigned = BILBase64Strict.decode(SigningVectors.finalResult(text).raw.str("psbt") ?? "") ?? []
            let long = BILPublicResponseQr(type: "psbt-base64", frames: [BILBase64Strict.encode(textSigned) + String(repeating: "A", count: 1_800)],
                                           payload: nil)
            expectRefused(postVector(text, response: long), .VERIFY, detail: "response.static", "static PSBT text > 1,800 characters")
            expectOk(postVector("T8-flow-bitcoin-psbt-base64-text-too-large"), "a large text request answered as crypto-psbt")
            // BBQr answers keep the request's encoding.
            let bbqr = "T8-flow-bitcoin-bbqr-hex"
            let bbqrResponse = SigningVectors.response(bbqr)
            let other = bbqrResponse.frames.map { f -> String in
                var u = Array(f.utf16)
                if u.count > 2 { u[2] = u[2] == 0x48 ? 0x32 : 0x48 }
                return String(decoding: u, as: UTF16.self)
            }
            expectRefused(postVector(bbqr, response: BILPublicResponseQr(type: bbqrResponse.type, frames: other, payload: nil)), .VERIFY,
                          detail: "response.bbqr.encoding", "BBQr answer in the other encoding")
        }

        section("post: the result must belong to the plan, every task in order")
        do {
            let id = "T8-flow-psbt-two-wallets"
            expectOk(postVector(id), "two-wallet PSBT")
            if let first = SigningVectors.signResults(id).first {
                expectRefused(postVector(id, result: SigningVectors.resultOf(first)), .VERIFY, detail: "result.tasks", "first task's result as final")
            }
            expectRefused(postVector(id, result: resultWith(id, "planHash", repeatHex("ab", 32))), .VERIFY, detail: "result.plan", "other plan hash")
        }

        section("post: a PSBT answer may sign only each task's own inputs (§13.2 #9, R5 §3.3)")
        do {
            // Task 1 signs input 0 with key 0330d5…, task 2 input 1 with key 02e1e8…: task 1's key on input 1 is refused.
            let id = "T8-flow-psbt-two-wallets"
            let plan = SigningVectors.plan(id)
            let targets = plan.tasks.map { V.targets(of: $0) }
            eq(targets.map { $0.map { $0.input } }, [[0], [1]], "task 1 signs input 0, task 2 input 1")
            let result = SigningVectors.finalResult(id)
            let signed = BILBase64Strict.decode(result.raw.str("psbt") ?? "") ?? []
            func answer(_ bytes: [UInt8]) -> BILPublicResponseQr {
                return BILPublicResponseQr(type: "crypto-psbt", frames: [TestUr.single("crypto-psbt", TestUr.cbor(.bytes(bytes)))], payload: nil)
            }
            if let maps = try? BILPsbtMaps.parse(signed), let firstKey = targets.first?.first?.publicKey {
                eq(psbtBytes(maps), signed, "test serializer round trip")
                expectOk(postVector(id, response: answer(psbtBytes(maps))), "re-serialized final PSBT")
                let r = [UInt8](repeating: 0x11, count: 32)
                let s = [UInt8](repeating: 0x22, count: 32)
                let der: [UInt8] = [0x30, 0x44, 0x02, 0x20] + r + [0x02, 0x20] + s + [0x01]      // a DER-shaped signature + SIGHASH_ALL
                let foreign = psbtBytes(maps, input: 1, [(key: [0x02] + hexBytes(firstKey), value: der)])
                let foreignResult = SigningVectors.resultOf(with(result.raw, "psbt", .string(BILBase64Strict.encode(foreign))))
                expectRefused(postVector(id, response: answer(foreign), result: foreignResult), .VERIFY, detail: "response.psbt.diff",
                              "task 1's key signs input 1 (another task's input)")
                let own = psbtBytes(maps, input: 0, [(key: [0x02] + hexBytes(targets[1][0].publicKey), value: der)])
                let ownResult = SigningVectors.resultOf(with(result.raw, "psbt", .string(BILBase64Strict.encode(own))))
                expectRefused(postVector(id, response: answer(own), result: ownResult), .VERIFY, detail: "response.psbt.diff",
                              "task 2's key signs input 0 (another task's input)")
            } else {
                t(false, "two-wallet final PSBT parses")
            }
        }

        witnessOnlyTests()
        tronLinkTests()
        tronLinkSplitTests()
        equivalenceTests()
        codecTests()
        claimTests()
    }

    // MARK: - Witness-only prevouts (port of WitnessOnlyPrevoutVerifierTest)

    private static let wAmount = "a086010000000000"
    private static let wHash = "c0cebcd6c3d3ca8c75dc5ec62ebe55330ef910e2"
    private static let hash160Of0014 = "a6b5888fddc8fa193dd353d10e5cd5a8eeab064e"       // RIPEMD160(SHA256(0014‖wHash)), Python hashlib
    private static let multisigRedeem = "5121" + "02" + repeatHex("33", 32) + "51ae"
    private static let hash160OfMultisig = "e719458d608da220fafbd696da2aa85f4c12060e"     // Python hashlib

    private static func witnessUtxo(_ scriptHex: String) -> String {
        let value = wAmount + String(format: "%02x", scriptHex.count / 2) + scriptHex
        return "0101" + String(format: "%02x", value.count / 2) + value
    }

    private static func redeemScript(_ scriptHex: String) -> String {
        return "0104" + String(format: "%02x", scriptHex.count / 2) + scriptHex
    }

    private static func cborBytes(_ b: [UInt8]) -> [UInt8] {
        return b.count < 256 ? [0x58, UInt8(b.count)] + b : [0x59, UInt8(b.count >> 8), UInt8(b.count & 0xFF)] + b
    }

    /// O-BTC-6 with its input's UTXO record replaced by `record` ("" drops it); request and CBOR payload both.
    private static func witnessRequest(_ record: String) -> BILJSONObject {
        let id = "O-BTC-6-segwit-witness-only"
        let request = SigningVectors.request(id)
        let psbt = BILPublicHex.encode(BILBase64Strict.decode(request.str("psbt") ?? "") ?? [])
        let p2wpkh = "01011f" + wAmount + "16" + "0014" + wHash
        t(psbt.contains(p2wpkh), "the O-BTC-6 input map is the expected one")
        let mutated = hexBytes(psbt.replacingOccurrences(of: p2wpkh, with: record))
        let transport = with(request.obj("transport") ?? BILJSONObject(), "payloadBytes", .string(BILPublicHex.encode(cborBytes(mutated))))
        return with(with(request, "psbt", .string(BILBase64Strict.encode(mutated))), "transport", .object(transport))
    }

    private static func witnessOnly(_ v: V.Verdict) -> [Int]? {
        if case .bitcoinPsbt(_, _, let w)? = v.payload { return w }
        return nil
    }

    static func witnessOnlyTests() {
        section("pre: witness-only prevouts (R2-2)")
        let id = "O-BTC-6-segwit-witness-only"
        eq(witnessOnly(SigningVectors.pre(id)) ?? [-1], [0], "O-BTC-6 input 0 is witness-only")
        eq(witnessOnly(SigningVectors.pre(id, request: witnessRequest(witnessUtxo("0014" + wHash)))) ?? [-1], [0], "rebuilt record")
        let nested = witnessUtxo("a914" + hash160Of0014 + "87") + redeemScript("0014" + wHash)
        eq(witnessOnly(SigningVectors.pre(id, request: witnessRequest(nested))) ?? [-1], [0], "nested P2SH-P2WPKH")
        eq(witnessOnly(SigningVectors.pre(id, request: witnessRequest(witnessUtxo("5120" + repeatHex("11", 32))))) ?? [-1], [], "Taproot: not listed")
        expectRefused(SigningVectors.pre(id, request: witnessRequest(witnessUtxo("76a914" + wHash + "88ac"))), detail: "bitcoin.prevout.legacy", "P2PKH")
        expectRefused(SigningVectors.pre(id, request: witnessRequest(witnessUtxo("a914" + hash160Of0014 + "87"))), detail: "bitcoin.prevout.legacy",
                      "bare P2SH")
        expectRefused(SigningVectors.pre(id, request: witnessRequest(witnessUtxo("a914" + repeatHex("22", 20) + "87") + redeemScript("0014" + wHash))),
                      detail: "bitcoin.prevout.legacy", "redeem hash mismatch")
        expectRefused(SigningVectors.pre(id, request: witnessRequest(witnessUtxo("a914" + hash160OfMultisig + "87") + redeemScript(multisigRedeem))),
                      detail: "bitcoin.prevout.legacy", "non-witness redeem script")
        expectRefused(SigningVectors.pre(id, request: witnessRequest("")), detail: "bitcoin.prevout", "no UTXO record")
        for other in ["O-BTC-6-segwit-witness-only-2-inputs", "O-BTC-8-nested-witness-only"] {
            t(!(witnessOnly(SigningVectors.pre(other)) ?? []).isEmpty, "\(other) lists witness-only inputs")
        }
        t((witnessOnly(SigningVectors.pre("T8-flow-bitcoin-crypto-psbt")) ?? [-1]).isEmpty, "full previous tx: none listed")
        // PSBT / plan binding.
        let request = SigningVectors.request(id)
        expectRefused(SigningVectors.pre(id, request: with(request, "psbt", .string(BILBase64Strict.encode(hexBytes("70736274ff00"))))),
                      detail: "bitcoin.psbt.differs", "engine PSBT ≠ QR")
        let transport = request.obj("transport") ?? BILJSONObject()
        expectRefused(SigningVectors.pre(id, request: with(request, "transport", .object(with(transport, "type", .string("psbt-hex"))))),
                      detail: "bitcoin.transport", "CBOR payload on a text transport")
        expectRefused(SigningVectors.pre(id, request: with(request, "transport", .object(with(transport, "payloadEncoding", .string("hex"))))),
                      detail: "bitcoin.payloadEncoding", "unknown payload encoding")
        var plan = SigningVectors.planJson(id)
        if let task = plan.arr("tasks")?.first?.objectValue {
            plan.set("tasks", .array([.object(with(task, "inputs", .array([.int(7)])))]))
            expectRefused(SigningVectors.pre(id, plan: SigningVectors.planOf(plan)), detail: "bitcoin.task.inputs", "task input out of range")
            if let target = task.arr("targets")?.first?.objectValue {
                var p2 = SigningVectors.planJson(id)
                p2.set("tasks", .array([.object(with(task, "targets", .array([.object(with(target, "inputIndex", .int(1)))])))]))
                expectRefused(SigningVectors.pre(id, plan: SigningVectors.planOf(p2)), detail: "bitcoin.task.targets", "target outside the task inputs")
            }
        }
    }

    // MARK: - TronLink (port of OtherWalletVerifierTest)

    static func tronLinkRequest(_ text: String) -> BILJSONObject {
        guard let frame = BILTronLinkQrFormat.parse(text), let mapped = try? BILTronLinkRequestMapper.map(BILTronLinkRequest.of(frame)) else {
            print("FAIL TronLink vector does not map")
            exit(2)
        }
        return mapped
    }

    static func tronLinkAnswer(_ request: String, _ entry: String) -> BILPublicResponseQr {
        guard let frame = BILTronLinkQrFormat.parse(request) else {
            print("FAIL TronLink vector does not parse")
            exit(2)
        }
        return BILPublicResponseQr(type: BILPublicResponseQr.tronLinkType, frames: BILTronLinkAnswerCodec.encode(frame.json, signed: [entry]), payload: nil)
    }

    static func tronLinkTests() {
        typealias W = OtherWalletVectors
        section("TronLink V1: the ownership placeholder before and after signing")
        do {
            let id = "O-TL-V1-ownership-ios"
            let plan = SigningVectors.plan(id)
            let request = tronLinkRequest(W.V1_REQUEST)
            let v = V.pre(request: request, plan: plan, reviewedChainId: plan.review?.network?.chainId)
            if case .tronOwnershipProof(_, let name, let owner, _)? = v.payload {
                eq(name, "TronLinkCustomContract", "proof name")
                eq(owner, "41c8599111f29c1e1e061265b4af93ea1f274ad78a", "proof owner")
            } else {
                t(false, "V1 → TronOwnershipProof: \(v)")
            }
            let result = SigningVectors.finalResult(id)
            let entry = W.V1_ENTRY + "1241" + W.V1_SIG
            func post(_ response: BILPublicResponseQr) -> V.Verdict {
                return V.post(request: request, plan: plan, verified: v.payload, result: result, response: response)
            }
            expectOk(post(tronLinkAnswer(W.V1_REQUEST, entry)), "V1 answer")
            eq(tronLinkAnswer(W.V1_REQUEST, entry).frames, [W.V1_ANSWER], "V1 answer byte for byte")
            expectRefused(post(tronLinkAnswer(W.V1_REQUEST, W.V1_ENTRY + "1241" + W.V3_SIG)), .VERIFY, detail: "response.tronlink.appended",
                          "another signature")
            let dropped = BILPublicResponseQr(type: BILPublicResponseQr.tronLinkType,
                                              frames: ["{\"address\":\"\(W.TRON_0)\",\"type\":99,\"hexList\":[\"\(entry)\"]}"], payload: nil)
            expectRefused(post(dropped), .VERIFY, detail: "response.tronlink.keys", "dropped keys")
            expectRefused(post(tronLinkAnswer(W.V1_REQUEST, entry + "1241" + W.V1_SIG)), .VERIFY, detail: "response.tronlink.signatures",
                          "second signature")
            expectRefused(post(BILPublicResponseQr(type: "tron-signature", frames: ["ur:x"], payload: nil)), .VERIFY, detail: "response.type",
                          "not a TronLink answer")
            // A changed value (amount) in the echoed object.
            let changed = BILPublicResponseQr(type: BILPublicResponseQr.tronLinkType,
                                              frames: [W.V1_ANSWER.replacingOccurrences(of: "\"amountStr\":\"0\"", with: "\"amountStr\":\"1\"")], payload: nil)
            expectRefused(post(changed), .VERIFY, detail: "response.tronlink.values", "changed echoed value")
            expectRefused(post(BILPublicResponseQr(type: BILPublicResponseQr.tronLinkType, frames: ["not json"], payload: nil)), .VERIFY,
                          detail: "response.tronlink.decode", "unreadable answer")
        }

        section("TronLink V3: a TRX transfer, and the request must be the scanned one")
        do {
            let id = "O-TL-V3-trx-transfer"
            let plan = SigningVectors.plan(id)
            let request = tronLinkRequest(W.V3_REQUEST)
            let v = V.pre(request: request, plan: plan, reviewedChainId: plan.review?.network?.chainId)
            if case .tronTransaction(_, _, _, let type, let proto)? = v.payload {
                eq(type, 1, "V3 contract type")
                eq(BILPublicHex.encode(proto ?? []), W.V3_ENTRY, "V3 TronLink proto")
            } else {
                t(false, "V3 → TronTransaction: \(v)")
            }
            let result = SigningVectors.finalResult(id)
            expectOk(V.post(request: request, plan: plan, verified: v.payload, result: result,
                            response: tronLinkAnswer(W.V3_REQUEST, W.V3_ENTRY + "1241" + W.V3_SIG)), "V3 answer")
            let transport = with(request.obj("transport") ?? BILJSONObject(), "tronlinkType", .int(7))
            expectRefused(V.pre(request: with(request, "transport", .object(transport)), plan: plan, reviewedChainId: plan.review?.network?.chainId),
                          detail: "tronlink.request.differs", "engine request ≠ scanned text")
            let badRecId = String(W.V3_SIG.dropLast(2)) + "00"
            expectRefused(V.post(request: request, plan: plan, verified: v.payload, result: result,
                                 response: tronLinkAnswer(W.V3_REQUEST, W.V3_ENTRY + "1241" + badRecId)), .VERIFY, detail: "response.tronlink.appended",
                          "wrong recovery byte")
            // The contract's owner field must be a `41…` address (same lengths, version byte 0x42 instead).
            let owner = "41c8599111f29c1e1e061265b4af93ea1f274ad78a"
            let badEntry = W.V3_ENTRY.replacingOccurrences(of: owner, with: "42" + String(owner.dropFirst(2)))
            let badText = W.V3_REQUEST.replacingOccurrences(of: W.V3_ENTRY, with: badEntry)
            if let frame = BILTronLinkQrFormat.parse(badText), let mapped = try? BILTronLinkRequestMapper.map(BILTronLinkRequest.of(frame)),
               let split = BILTronTransactionProto.split(hexBytes(badEntry)) {
                let badPlan = SigningVectors.planOf(withDigest(SigningVectors.planJson(id), BILPublicHash.sha256Hex(split.raw)))
                expectRefused(V.pre(request: mapped, plan: badPlan, reviewedChainId: nil), detail: "tronlink.owner", "TronLink owner not 41…")
            } else {
                t(false, "TronLink request with another owner byte maps")
            }
            // A part of a split request is never a request (B2: `!isPart` first).
            let part = "{\"address\":\"\(W.TRON_0)\",\"cN\":1,\"tN\":2,\"type\":1,\"hexList\":[\"\(W.V3_ENTRY)\"]}"
            let partTransport = with(request.obj("transport") ?? BILJSONObject(), "payloadBytes", .string(BILPublicHex.encode(Array(part.utf8))))
            expectRefused(V.pre(request: with(request, "transport", .object(partTransport)), plan: plan, reviewedChainId: nil),
                          detail: "tronlink.bean", "a TronLink part as the request")
            let shielded = "{\"address\":\"\(W.TRON_0)\",\"type\":15,\"hexList\":[\"\(W.V3_ENTRY)\"]}"
            let shieldedTransport = with(request.obj("transport") ?? BILJSONObject(), "payloadBytes", .string(BILPublicHex.encode(Array(shielded.utf8))))
            expectRefused(V.pre(request: with(request, "transport", .object(shieldedTransport)), plan: plan, reviewedChainId: nil),
                          detail: "tronlink.map", "a request the mapper refuses")
        }

        section("TronLink V4: a TIP-191 message answers 0x r s v")
        do {
            let id = "O-TL-V4-tip191-message"
            let plan = SigningVectors.plan(id)
            let request = tronLinkRequest(W.V4_REQUEST)
            let v = V.pre(request: request, plan: plan, reviewedChainId: plan.review?.network?.chainId)
            if case .tronMessage(let m)? = v.payload {
                eq(String(decoding: m, as: UTF8.self), "hello ownbit", "V4 message")
            } else {
                t(false, "V4 → TronMessage: \(v)")
            }
            let result = SigningVectors.finalResult(id)
            expectOk(V.post(request: request, plan: plan, verified: v.payload, result: result,
                            response: tronLinkAnswer(W.V4_REQUEST, W.V4_MESSAGE_SIGNATURE)), "V4 answer")
            let v27 = String(W.V4_MESSAGE_SIGNATURE.dropLast(2)) + "1b"
            expectRefused(V.post(request: request, plan: plan, verified: v.payload, result: result, response: tronLinkAnswer(W.V4_REQUEST, v27)),
                          .VERIFY, detail: "response.tronlink.message", "message with v 27")
        }

        section("a TRON request on TokenPocket's transport is refused before signing")
        do {
            let id = "O-TL-V3-trx-transfer"
            let request = tronLinkRequest(W.V3_REQUEST)
            let transport = BILJSONObject([
                ("type", .string("tokenpocket")), ("payloadEncoding", .string("tokenpocket-text")),
                ("payloadBytes", .string(BILPublicHex.encode(Array(W.tpRequest.utf8)))), ("origin", .string("TokenPocket")),
            ])
            let plan = SigningVectors.plan(id)
            expectRefused(V.pre(request: with(request, "transport", .object(transport)), plan: plan, reviewedChainId: plan.review?.network?.chainId),
                          detail: "tron.transport", "TokenPocket transport")
        }
    }

    // MARK: - TronLink split answers (port of TronLinkSplitAnswerVerifierTest)

    static func tronLinkSplitTests() {
        typealias W = OtherWalletVectors
        section("TronLink: a split answer above 1000 characters (numbered parts, in order)")
        // V3's raw_data with a 600-byte memo (field 10): the signed entry no longer fits one code.
        let baseRaw = hexBytes(String(W.V3_ENTRY.dropFirst(6)))
        let raw = baseRaw + [0x52, 0xD8, 0x04] + [UInt8](repeating: 0x41, count: 600)
        guard let txProto = BILTronTransactionProto.encode(raw: raw, signatures: []) else { t(false, "encode V3 + memo"); return }
        // A valid signature by some key over sha256(raw): take V3's (r, s) and recover the key it belongs to for this digest
        // (Android signs with a test key; the property checked is the same — the answer verifies for the task's key).
        let v3 = hexBytes(W.V3_SIG)
        let digest = BILPublicHash.sha256(raw)
        guard let pub = BILSecp256k1.recoverPublicKey(digest: digest, recId: 0, r: Array(v3[0..<32]), s: Array(v3[32..<64])),
              let address = V.tronAddress(uncompressed: pub) else { t(false, "recover a key for the split test"); return }
        let signature = Array(v3[0..<64]) + [0]
        guard let bean = BILTronLinkQrFormat.parse("{\"address\":\"\(address)\",\"type\":1,\"hexList\":[\"\(BILPublicHex.encode(txProto))\"]}",
                                                   maxChars: BILTronLinkQrFormat.maxRequestChars),
              let request = try? BILTronLinkRequestMapper.map(BILTronLinkRequest.of(bean)),
              let entry = BILTronLinkAnswerCodec.signedTransaction(tx: txProto, signature: signature) else { t(false, "split request"); return }
        let id = "O-TL-V3-trx-transfer"
        var planJson = SigningVectors.planJson(id)
        if let task = planJson.arr("tasks")?.first?.objectValue, let target = task.arr("targets")?.first?.objectValue {
            let newTask = with(with(task, "addresses", .array([.string(address)])), "targets", .array([.object(with(target, "address", .string(address)))]))
            planJson.set("tasks", .array([.object(newTask)]))
        }
        let plan = SigningVectors.planOf(planJson)
        guard let lastResult = SigningVectors.signResults(id).last else { t(false, "V3 result"); return }
        let result = SigningVectors.resultOf(with(lastResult, "signature", .string(BILPublicHex.encode(signature))))
        guard let decoded = BILTronRawData.decode(baseRaw), let owner = V.tronHex41(address) else { t(false, "split payload"); return }
        let verified = BILVerifiedPayload.tronTransaction(raw: raw, decoded: decoded, ownerHex41: owner, contractType: 1, txProto: txProto)
        func post(_ frames: [String]) -> V.Verdict {
            return V.post(request: request, plan: plan, verified: verified, result: result,
                          response: BILPublicResponseQr(type: BILPublicResponseQr.tronLinkType, frames: frames, payload: nil, signedTransaction: true))
        }
        let frames = BILTronLinkAnswerCodec.encode(bean.json, signed: [entry])
        t(frames.count >= 2, "the entry is \(entry.utf16.count) characters: \(frames.count) parts")
        expectOk(post(frames), "split answer verifies")
        for (i, frame) in frames.enumerated() {
            let part = BILTronLinkQrFormat.parse(frame)
            eq(part?.cN ?? -1, i + 1, "part \(i + 1) number")
            eq(part?.tN ?? -1, frames.count, "part \(i + 1) count")
            t(BILJSONExact.equal(part?.address ?? "<nil>", (i == 0 || i == frames.count - 1) ? address : "<nil>"), "part \(i + 1) address")
            eq(part?.type ?? -1, i == frames.count - 1 ? 1 : 0, "part \(i + 1) type")
        }
        expectRefused(post(frames.reversed()), .VERIFY, detail: "response.tronlink.order", "parts reversed")
        expectRefused(post(BILTronLinkAnswerCodec.encode(with(bean.json, "type", .int(7)), signed: [entry])), .VERIFY, detail: "response.tronlink.parts",
                      "other type")
        expectRefused(post(BILTronLinkAnswerCodec.encode(with(bean.json, "address", .string("TJRabPrwbZy45sbavfcjinPJC18kjpRTv8")), signed: [entry])),
                      .VERIFY, detail: "response.tronlink.parts", "other address")
        expectRefused(post(Array(frames.dropLast())), .VERIFY, detail: "response.tronlink.decode", "missing last part")
        expectRefused(post([BILStrictJSON.serialize(BILTronLinkAnswerCodec.answerBean(bean.json, signed: [entry]))]), .VERIFY,
                      detail: "response.tronlink.split", "the same entry in one code")
        if let forged = BILTronLinkAnswerCodec.signedTransaction(tx: txProto, signature: v3) {
            expectRefused(post(BILTronLinkAnswerCodec.encode(bean.json, signed: [forged])), .VERIFY, detail: "response.tronlink.appended",
                          "another key's signature in correct parts")
        }
    }

    // MARK: - EIP-712 equivalence

    static func equivalenceTests() {
        section("EIP-712 equivalence: exact decimals, key sets, strict types")
        func j(_ s: String) -> BILJSONValue {
            guard let v = BILStrictJSON.parse(s) else { print("FAIL bad JSON in test: \(s)"); exit(2) }
            return v
        }
        let cases: [(String, String, Bool)] = [
            ("1", "1.0", true), ("1", "1e0", true), ("10e-1", "1", true), ("1.50", "1.5", true), ("0", "-0", true), ("0.0", "0e5", true),
            ("123456789012345678901234567890", "1.23456789012345678901234567890e29", true),
            ("9007199254740993", "9007199254740992", false), ("1", "2", false), ("-1", "1", false),
            ("\"1\"", "1", false), ("\"1\"", "\"1\"", true), ("\"1.0\"", "\"1\"", false), ("true", "true", true), ("true", "false", false),
            ("true", "1", false), ("null", "null", true), ("null", "0", false), ("null", "\"\"", false),
            ("{\"a\":1,\"b\":[1,2]}", "{\"b\":[1.0,2],\"a\":1e0}", true), ("{\"a\":1}", "{\"a\":1,\"b\":2}", false),
            ("[1,2]", "[2,1]", false), ("[1]", "[1,1]", false), ("{}", "[]", false), ("{\"a\":null}", "{\"a\":0}", false),
            ("1e2147483648", "1e2147483648", true), ("1e2147483648", "1e2147483649", false), ("1e99999999999", "1e99999999999", true),
            ("1e2147483648", "10e2147483647", false), ("1e2147483647", "10e2147483646", true), ("1e-2147483648", "10e-2147483647", false) /* scale 2³¹: Java "Scale out of range" */,
            ("1e-2147483649", "10e-2147483648", false),
            ("{\"e\\u0301\":1}", "{\"\\u00e9\":1}", false), ("\"\\u00e9\"", "\"e\\u0301\"", false),
        ]
        for (a, b, expected) in cases {
            eq(V.equivalent(j(a), j(b)), expected, "equivalent(\(a), \(b))")
            eq(V.equivalent(j(b), j(a)), expected, "equivalent(\(b), \(a))")
        }

        section("EIP-712 domain.chainId as exact integer text (Android bigInteger)")
        let ids: [(BILJSONValue, String?)] = [
            (.number("1"), "1"), (.number("1.0"), "1"), (.number("1.5"), nil), (.number("1e2"), "100"), (.number("-3"), "-3"),
            (.string("0x1"), "1"), (.string("0X1F"), "31"), (.string(" 7 "), "7"), (.string("+3"), "3"), (.string("0x"), nil),
            (.string("0x-5"), "-5"), (.string("-0x5"), nil), (.string("0xＦ"), "15"), (.string("0x٣"), "3"), (.string("abc"), nil),
            (.string("0xffffffffffffffffffff"), "1208925819614629174706175"), (.bool(true), nil), (.null, nil), (.array([]), nil),
            (.number("1e4097"), nil), (.number("0e99"), "0"), (.string("1."), "1"), (.string(".5"), nil),
            (.string("0x" + String(repeating: "f", count: 4097)), nil) /* deviation 4: more than 4,096 hex digits */,
        ]
        for (value, expected) in ids {
            eq(V.exactIntegerText(value) ?? "nil", expected ?? "nil", "chainId \(String(BILStrictJSON.serialize(value).prefix(40)))")
        }
        // The bounds themselves: 4,096 hex / decimal digits are still read.
        t(V.exactIntegerText(.string("0x" + String(repeating: "f", count: 4096))) != nil, "chainId with 4,096 hex digits is read")
        eq(V.exactIntegerText(.number("1e4095"))?.utf16.count ?? 0, 4096, "chainId with 4,096 decimal digits is read")
    }

    // MARK: - TRON address codec, targets

    static func codecTests() {
        section("TRON address codec (Android TronAddressCodec.toHex41)")
        let hex = "41c8599111f29c1e1e061265b4af93ea1f274ad78a"
        eq(V.tronHex41("TUEZSdKsoDHQMeZwihtdoBiN46zxhGWYdH") ?? "nil", hex, "base58")
        eq(V.tronHex41("  TUEZSdKsoDHQMeZwihtdoBiN46zxhGWYdH\n") ?? "nil", hex, "trimmed")
        eq(V.tronHex41(hex.uppercased()) ?? "nil", hex, "41… hex, upper case")
        eq(V.tronHex41("0x" + hex) ?? "nil", hex, "0x41…")
        eq(V.tronHex41("0X41C8599111F29C1E1E061265B4AF93EA1F274AD78A") ?? "nil", hex, "0X41… upper case")
        t(V.tronHex41("TUEZSdKsoDHQMeZwihtdoBiN46zxhGWYdJ") == nil, "bad checksum")
        t(V.tronHex41("41" + repeatHex("zz", 20)) == nil, "41… not hex")
        t(V.tronHex41("") == nil, "empty")
        t(V.tronHex41("1111111111111111111111111111111111") == nil, "version byte not 0x41")
        eq(BILTronAddressCodec.base58(anyHex21: "415cbd" + String(repeating: "0", count: 36)) != nil, true, "owner base58 of any 21 bytes")
    }

    // MARK: - Outpoint claims

    static func claimTests() {
        section("PSBT outpoint claims + the signed-outpoint memory")
        guard case .bitcoinPsbt(_, let maps, _)? = SigningVectors.pre("O-BTC-6-segwit-witness-only").payload else {
            t(false, "O-BTC-6 maps"); return
        }
        let claims = maps.outpointClaims()
        eq(claims.count, maps.inputs.count, "one claim per input")
        if let c = claims.first ?? nil, let op = maps.outpoint(0) {
            eq(c.txid, op.txid, "txid as stored")
            eq(c.vout, op.vout, "vout")
            eq(c.sats, UInt64(100_000), "claimed amount")
            eq(String(describing: c), "Claim", "a claim prints nothing")
        } else {
            t(false, "input 0 claim")
        }
        eq(maps.claims(forInputs: [0, 0])?.count ?? -1, 1, "record claims: distinct inputs")
        t(maps.claims(forInputs: [0, 5]) == nil, "record claims: an out-of-range input fails the whole record")
        eq(maps.claims(forInputs: [])?.count ?? -1, 0, "record claims: nothing signed → nothing to record")
        guard case .bitcoinPsbt(_, let two, _)? = SigningVectors.pre("O-BTC-6-segwit-witness-only-2-inputs").payload else {
            t(false, "2-input maps"); return
        }
        let sorted = two.claims(forInputs: [1, 0]) ?? []
        eq(sorted.count, 2, "two inputs")
        if sorted.count == 2, let first = two.outpointClaims()[0] { eq(sorted[0], first, "claims in ascending input order") }

        let dir = pubTempDir("verifier-ovc")
        let memory = BILSignedOutpointMemory(fileURL: dir.appendingPathComponent("signed_outpoints.json"))
        eq((try? memory.conflicts(maps.outpointClaims())) ?? [-1], [], "empty memory: no conflict")
        let signed = SigningVectors.plan("O-BTC-6-segwit-witness-only").tasks.flatMap { $0.inputs }
        if let toRecord = maps.claims(forInputs: signed) {
            t((try? memory.record(toRecord)) != nil, "record the signed inputs")
        }
        eq((try? memory.conflicts(maps.outpointClaims())) ?? [-1], [], "same amounts again: no conflict")
        if let c = maps.outpointClaims()[0] {
            _ = try? memory.record([BILSignedOutpointMemory.Claim(txid: c.txid, vout: c.vout, sats: c.sats + 1)])
        }
        let conflicts = (try? memory.conflicts(maps.outpointClaims())) ?? []
        eq(conflicts, [0], "another amount for input 0 → conflict")
        let plan = SigningVectors.plan("O-BTC-6-segwit-witness-only")
        if let review = plan.review {
            let r = BILPublicSignPolicy.evaluate(review: review, plan: plan, verified: SigningVectors.verified("O-BTC-6-segwit-witness-only"),
                                                 outpointConflicts: conflicts)
            eq(r.refusal?.code ?? "", "PREVOUT_CONFLICT", "policy refuses the conflict")
            eq(r.refusal?.args ?? [], [.int(1)], "1-based input number")
        }
        try? FileManager.default.removeItem(at: dir)
    }
}
