//  BILPublicSignVerifier.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Public protocol (cold signer) — defense in depth around the engine (spec S§8.3, checklist C-GEN-4 / C-GEN-5, C-BTC-4 /
//  C-BTC-8, C-EVM-2 / C-EVM-9, C-TRX-9, C-RESP-1…3; design §3.10, R5 §3.1–3.3). Port of Android
//  `core/publicsigner/.../verify/PublicSignVerifier.kt` (b8c70c25). The engine is the only parser that decides what is
//  signed; this file re-checks with independent native code and refuses on any disagreement — before the password
//  (`pre`) and before the answer is shown (`post`). Nothing here signs.
//
//  Pre (on the original bytes B = `transport.payloadBytes` and the ready plan): B decodes to exactly the request the
//  engine reviewed (signData / PSBT equal, EVM chain id equal, request id equal), and the native code recomputes
//  `plan.signingBytesDigest` where it can — EVM transaction `keccak256(signData)` (strict `BILEvmTxCodec.decodeUnsigned`;
//  its chain id must be the reviewed network's), `personal_sign` EIP-191, TRON `sha256(raw_data)` / TIP-191, Solana
//  `sha256(message)` with the task key in a required signer slot and no lookup table, Bitcoin `sha256(unsigned tx)`
//  (`BILPsbtMaps`). EIP-712 keeps the engine's digest (no native hasher; the documented C-GEN-4 gap); the text is still
//  bound to the QR bytes.
//
//  Post (on the final result and the response frames): the result belongs to this plan (hashes, every task in order);
//  the answer is in the request's own transport; a signature answer is `{1: request id (exactly the request's), 2:
//  signature}` and the signature verifies for the task key over the digest (secp256k1 recovery for EVM / TRON with the
//  expected `v`, Ed25519 for Solana); a PSBT answer equals the engine's result and differs from the reviewed PSBT only by
//  signatures of the task keys on the task inputs; a TronLink answer is Ownbit's own frames read back.
//
//  Every refusal names only a log-safe check (`detail`, Android's `PublicVerifyException.what`), never payload data.
//  String comparisons are exact (code units), never Swift canonical equivalence. Pure: Foundation + CryptoKit (Ed25519)
//  + the Core / Crypto / Verify / Scan files it uses (macOS harness: tests/verifier/). CPU-heavy (secp256k1 recovery,
//  BIP-86 tweaks in the PSBT diff): call `pre` / `post` off-main (design §1.4, `BILPublicBackground.run`). Never logs.
//

import Foundation
import CryptoKit

public enum BILPublicSignVerifier {

    /// Why a check refused (the text: `BILPublicSignerErrors.verifierKey(reason.rawValue)`).
    public enum Reason: String {
        /// The request / plan / result / answer are inconsistent (`err.integrity`).
        case INTEGRITY
        /// The chain id of the signed bytes differs from the request or the reviewed network (`err.chainMismatch`).
        case CHAIN_MISMATCH
        /// A Solana v0 message with address lookup tables (`err.lookupTable`).
        case LOOKUP_TABLE
        /// The produced signature or answer does not verify (`err.verify`, nothing returned).
        case VERIFY
    }

    public enum Verdict {
        /// Every check agreed. The payload is the pre-check's decode (nil from `post`).
        case ok(BILVerifiedPayload?)
        /// Refused: `reason` picks the text, `detail` names the failed check (log-safe, no payload).
        case refused(Reason, detail: String)
    }

    // MARK: - Pre

    /// Pre-sign checks of `request` (the engine's decoded request) against the ready `plan`. `reviewedChainId` is the EVM
    /// chain id the review shows (`review.network.chainId`). Any failed check → `.refused(.INTEGRITY, …)` unless a
    /// more specific reason applies (`CHAIN_MISMATCH`, `LOOKUP_TABLE`).
    public static func pre(request: BILJSONObject, plan: BILPublicPlan, reviewedChainId: String?) -> Verdict {
        return guarded(.INTEGRITY) {
            try BILVerifyError.check(plan.isReady && !plan.tasks.isEmpty, "plan.ready")
            let chain = BILPsChain.fromWire(request.str("chain"))
            try BILVerifyError.check(chain != nil && chain == plan.chain, "request.chain")
            try BILVerifyError.check(chain == .bitcoin || plan.tasks.count == 1, "plan.tasks")
            guard let digest = plan.signingBytesDigest else { throw BILVerifyError("plan.digest") }
            guard let transport = request.obj("transport") else { throw BILVerifyError("request.transport") }
            guard let type = transport.str("type") else { throw BILVerifyError("transport.type") }
            guard let payloadBytes = transport.str("payloadBytes").flatMap({ BILPublicHex.decode($0) }) else {
                throw BILVerifyError("transport.payloadBytes")
            }
            switch chain {
            case .bitcoin?:
                return .ok(try preBitcoin(request, transport, type, payloadBytes, digest, plan))
            case .evm?:
                return try preEvm(request, transport, type, payloadBytes, digest, reviewedChainId)
            case .tron?:
                if same(type, BILTronLinkRequestMapper.transportType) {
                    return .ok(try preTronLink(request, transport, payloadBytes, digest))
                }
                return .ok(try preTron(request, type, payloadBytes, digest))
            case .solana?:
                return try preSolana(request, type, payloadBytes, digest, plan.tasks[0])
            case nil:
                throw BILVerifyError("request.chain")
            }
        }
    }

    private static func preBitcoin(_ request: BILJSONObject, _ transport: BILJSONObject, _ type: String,
                                   _ payloadBytes: [UInt8], _ digest: String, _ plan: BILPublicPlan) throws -> BILVerifiedPayload {
        let psbt: [UInt8]
        let encoding = transport.str("payloadEncoding")
        if same(encoding, "cbor") {
            try BILVerifyError.check(same(type, "crypto-psbt") || same(type, "psbt"), "bitcoin.transport")
            guard let bytes = try BILStrictCbor.decode(payloadBytes).bytesValue else { throw BILVerifyError("bitcoin.cbor") }
            psbt = bytes
        } else if same(encoding, "psbt") {
            try BILVerifyError.check(isPsbtTextType(type) || same(type, "bbqr-psbt"), "bitcoin.transport")
            psbt = payloadBytes
        } else {
            throw BILVerifyError("bitcoin.payloadEncoding")
        }
        guard let text = request.str("psbt") else { throw BILVerifyError("bitcoin.psbt") }
        let fromRequest = try BILSignatureUrCodec.base64(text)
        try BILVerifyError.check(fromRequest == psbt, "bitcoin.psbt.differs")
        let maps = try BILPsbtMaps.parse(psbt)
        try BILVerifyError.check(same(maps.unsignedTxDigest, digest), "bitcoin.digest")
        for task in plan.tasks {
            try BILVerifyError.check(!task.inputs.isEmpty && task.inputs.allSatisfy { $0 >= 0 && $0 < maps.inputs.count },
                                     "bitcoin.task.inputs")
            try BILVerifyError.check(targets(of: task).allSatisfy { task.inputs.contains($0.input) }, "bitcoin.task.targets")
        }
        // R2-2 (defense in depth, the engine's own PREVOUT rule): an input without its previous transaction must spend a
        // SegWit (v0 or Taproot) output — a legacy input's signature commits to no amount at all — and must name its
        // amount and outpoint.
        var witnessOnly = [Int]()
        for i in 0..<maps.inputs.count {
            try BILVerifyError.check(maps.outpoint(i) != nil && maps.claimedAmount(i) != nil, "bitcoin.prevout")
            switch maps.prevoutKind(i) {
            case .fullPreviousTx, .witnessTaproot:
                break
            case .witnessSegwitV0:
                witnessOnly.append(i)
            case .witnessLegacy, .none:
                throw BILVerifyError("bitcoin.prevout.legacy")
            }
        }
        return .bitcoinPsbt(bytes: psbt, maps: maps, witnessOnlyInputs: witnessOnly)
    }

    private static func preEvm(_ request: BILJSONObject, _ transport: BILJSONObject, _ type: String, _ payloadBytes: [UInt8],
                               _ digest: String, _ reviewedChainId: String?) throws -> Verdict {
        try BILVerifyError.check(same(type, "eth-sign-request") && same(transport.str("payloadEncoding"), "cbor"), "evm.transport")
        let cbor = try BILSignatureUrCodec.decodeSignRequest(type: type, payload: payloadBytes)
        try checkRequestId(request, cbor)
        let requestChainId = request.long("chainId")
        try BILVerifyError.check(cbor.chainId == requestChainId && transport.long("chainId") == requestChainId, "evm.chainId.request")
        switch cbor.dataType {
        case 1?, 4?:
            try BILVerifyError.check(same(request.str("kind"), "transaction"), "evm.kind")
            try BILVerifyError.check(BILPublicHex.sameHex(request.str("transaction"), cbor.signData), "evm.transaction.differs")
            let tx: BILUnsignedEvmTx
            do {
                tx = try BILEvmTxCodec.decodeUnsigned(cbor.signData)
            } catch {
                throw BILVerifyError("evm.transaction.decode")
            }
            try BILVerifyError.check((cbor.dataType == 1) == (tx.type == 0), "evm.dataType")
            if let r = requestChainId, r < 0 || UInt64(r) != tx.chainId {
                return .refused(.CHAIN_MISMATCH, detail: "evm.chainId.request")
            }
            if !same(reviewedChainId, String(tx.chainId)) {
                return .refused(.CHAIN_MISMATCH, detail: "evm.chainId.review")
            }
            try BILVerifyError.check(same(BILPublicHex.encode(tx.signingHash), digest), "evm.digest")
            return .ok(.evmTransaction(signData: cbor.signData, tx: tx))
        case 3?:
            try BILVerifyError.check(same(request.str("kind"), "personal"), "evm.kind")
            try BILVerifyError.check(BILPublicHex.sameHex(request.str("message"), cbor.signData), "evm.message.differs")
            try BILVerifyError.check(same(BILPublicHex.encode(BILEvmTxCodec.personalMessageDigest(cbor.signData)), digest), "evm.digest")
            return .ok(.evmPersonal(cbor.signData))
        case 2?:
            try BILVerifyError.check(same(request.str("kind"), "typedData"), "evm.kind")
            guard let text = BILVerifyText.strictUTF8(cbor.signData) else { throw BILVerifyError("evm.typedData.utf8") }
            // iOS: the app's strict parser (duplicate keys refused, design D-01) where Android's kotlinx tree keeps the
            // last duplicate — stricter, fails closed.
            guard let parsed = BILStrictJSON.parseObject(text, options: .strict) else { throw BILVerifyError("evm.typedData.json") }
            guard let engine = request.obj("typedData") else { throw BILVerifyError("evm.typedData") }
            try BILVerifyError.check(equivalent(.object(parsed), .object(engine)), "evm.typedData.differs")
            let rawChainId = parsed.obj("domain")?["chainId"]
            let has = rawChainId.map { !$0.isNull } ?? false
            return .ok(.evmTypedData(json: text, domainChainId: rawChainId.flatMap(exactIntegerText), hasDomainChainId: has))
        default:
            throw BILVerifyError("evm.dataType")
        }
    }

    private static func preTron(_ request: BILJSONObject, _ type: String, _ payloadBytes: [UInt8], _ digest: String) throws -> BILVerifiedPayload {
        try BILVerifyError.check(same(type, "tron-sign-request"), "tron.transport")
        let cbor = try BILSignatureUrCodec.decodeSignRequest(type: type, payload: payloadBytes)
        try checkRequestId(request, cbor)
        switch cbor.dataType {
        case 1?:
            try BILVerifyError.check(same(request.str("kind"), "transaction"), "tron.kind")
            guard let tx = request.obj("transaction") else { throw BILVerifyError("tron.transaction") }
            try BILVerifyError.check(BILPublicHex.sameHex(tx.str("raw_data_hex"), cbor.signData), "tron.raw.differs")
            let txId = BILPublicHash.sha256Hex(cbor.signData)
            if let claimed = tx.str("txID") {
                try BILVerifyError.check(BILVerifyText.equalsIgnoringCase(claimed, txId), "tron.txID")
            }
            try BILVerifyError.check(same(txId, digest), "tron.digest")
            guard let decoded = BILTronRawData.decode(cbor.signData) else { throw BILVerifyError("tron.raw.decode") }
            guard decoded.contracts.count == 1 else { throw BILVerifyError("tron.contracts") }
            let contract = decoded.contracts[0]
            let owner = contract.ownerHex41 ?? ""
            try BILVerifyError.check(isOwnerHex41(owner), "tron.owner")
            return .tronTransaction(raw: cbor.signData, decoded: decoded, ownerHex41: owner.lowercased(),
                                    contractType: contract.type, txProto: nil)
        case 2?:
            try BILVerifyError.check(same(request.str("kind"), "message"), "tron.kind")
            try BILVerifyError.check(BILPublicHex.sameHex(request.str("message"), cbor.signData), "tron.message.differs")
            try BILVerifyError.check(same(BILPublicHex.encode(BILPublicHash.tip191Digest(cbor.signData)), digest), "tron.digest")
            return .tronMessage(cbor.signData)
        default:
            throw BILVerifyError("tron.dataType")
        }
    }

    /// TronLink (r2-tronlink §5.5): the scanned request object (`payloadBytes`, UTF-8 JSON) is parsed with the scanner's
    /// parser and mapped again with the same mapper — the result must be exactly the request the engine reviewed — then
    /// its one entry is read strictly: `sha256(raw_data)` is the plan's digest; the type-99 placeholder becomes a
    /// `.tronOwnershipProof` (its address = the request's), any other transaction a `.tronTransaction` with exactly one
    /// contract; a TIP-191 message's digest is the plan's. A part is refused before the mapper (`!isPart`, design B2).
    private static func preTronLink(_ request: BILJSONObject, _ transport: BILJSONObject, _ payloadBytes: [UInt8],
                                    _ digest: String) throws -> BILVerifiedPayload {
        try BILVerifyError.check(same(transport.str("payloadEncoding"), BILTronLinkRequestMapper.payloadEncoding), "tronlink.payloadEncoding")
        guard let text = BILVerifyText.strictUTF8(payloadBytes) else { throw BILVerifyError("tronlink.utf8") }
        guard let frame = BILTronLinkQrFormat.parse(text, maxChars: BILTronLinkQrFormat.maxRequestChars), !frame.isPart else {
            throw BILVerifyError("tronlink.bean")
        }
        let mapped: BILJSONObject
        do {
            mapped = try BILTronLinkRequestMapper.map(BILTronLinkRequest.of(frame))
        } catch is BILOtherWalletRequestError {
            throw BILVerifyError("tronlink.map")
        }
        try BILVerifyError.check(mapped == request, "tronlink.request.differs")
        guard let address = request.str("address"), let ownerHex41 = tronHex41(address) else { throw BILVerifyError("tronlink.address") }
        if same(request.str("kind"), "message") {
            guard let message = messageBytes(request) else { throw BILVerifyError("tronlink.message") }
            try BILVerifyError.check(same(BILPublicHex.encode(BILPublicHash.tip191Digest(message)), digest), "tronlink.digest")
            return .tronMessage(message)
        }
        try BILVerifyError.check(same(request.str("kind"), "transaction"), "tronlink.kind")
        let entry = try single(frame.hexList)
        guard let txProto = BILTronLinkRequestMapper.entryBytes(entry) else { throw BILVerifyError("tronlink.entry") }
        guard let split = BILTronTransactionProto.split(txProto) else { throw BILVerifyError("tronlink.entry") }
        try BILVerifyError.check(BILPublicHex.sameHex(request.obj("transaction")?.str("raw_data_hex"), split.raw), "tronlink.raw.differs")
        try BILVerifyError.check(same(BILPublicHash.sha256Hex(split.raw), digest), "tronlink.digest")
        if let proof = BILTronLinkRequestMapper.ownershipProofName(split.raw) {
            try BILVerifyError.check(frame.type == BILTronLinkRequestMapper.typeOwnership && split.signatures.isEmpty, "tronlink.proof")
            return .tronOwnershipProof(raw: split.raw, name: proof, ownerHex41: ownerHex41, txProto: txProto)
        }
        guard let decoded = BILTronRawData.decode(split.raw) else { throw BILVerifyError("tronlink.raw.decode") }
        guard decoded.contracts.count == 1 else { throw BILVerifyError("tronlink.contracts") }
        let contract = decoded.contracts[0]
        let owner = contract.ownerHex41 ?? ""
        try BILVerifyError.check(isOwnerHex41(owner), "tronlink.owner")
        return .tronTransaction(raw: split.raw, decoded: decoded, ownerHex41: owner.lowercased(), contractType: contract.type,
                                txProto: txProto)
    }

    /// The bytes of an engine-native TRON message request (`encoding` utf8 / hex / absent), non-empty, else nil.
    private static func messageBytes(_ request: BILJSONObject) -> [UInt8]? {
        guard let message = request.str("message") else { return nil }
        let encoding = request.str("encoding")
        let bytes: [UInt8]?
        if same(encoding, "utf8") {
            bytes = Array(message.utf8)
        } else if encoding == nil || same(encoding, "hex") {
            var hex = message
            if BILPublicHex.hasASCIIPrefix(hex, "0x") { hex = String(decoding: hex.utf8.dropFirst(2), as: UTF8.self) }
            bytes = BILPublicHex.decode(hex)
        } else {
            bytes = nil
        }
        guard let b = bytes, !b.isEmpty else { return nil }
        return b
    }

    private static func preSolana(_ request: BILJSONObject, _ type: String, _ payloadBytes: [UInt8], _ digest: String,
                                  _ task: BILPublicTask) throws -> Verdict {
        try BILVerifyError.check(same(type, "sol-sign-request"), "solana.transport")
        let cbor = try BILSignatureUrCodec.decodeSignRequest(type: type, payload: payloadBytes)
        try checkRequestId(request, cbor)
        guard let message = request.str("message") else { throw BILVerifyError("solana.message") }
        let fromRequest = try BILSignatureUrCodec.base64(message)
        try BILVerifyError.check(fromRequest == cbor.signData, "solana.message.differs")
        try BILVerifyError.check(same(BILPublicHash.sha256Hex(cbor.signData), digest), "solana.digest")
        let key = try single(task.publicKeys)
        switch cbor.dataType {
        case 1?:
            try BILVerifyError.check(same(request.str("kind"), "transaction"), "solana.kind")
            let header: BILSolanaMessageHeader
            do {
                header = try BILSolanaMessageHeader.parse(cbor.signData)
            } catch BILSolanaMessageHeader.ParseError.lookupTables {
                return .refused(.LOOKUP_TABLE, detail: "solana.lookupTables")
            }
            guard let slot = header.signerSlot(key) else { throw BILVerifyError("solana.signerSlot") }
            if let planned = task.signerSlot {
                try BILVerifyError.check(planned == slot, "solana.signerSlot.plan")
            }
            return .ok(.solanaTransaction(bytes: cbor.signData, header: header, signerSlot: slot))
        case 2?:
            try BILVerifyError.check(same(request.str("kind"), "message"), "solana.kind")
            try BILVerifyError.check(BILSolanaMessageHeader.isValidOffchainMessage(cbor.signData), "solana.offchainMessage")
            return .ok(.solanaMessage(cbor.signData))
        default:
            throw BILVerifyError("solana.signType")
        }
    }

    // MARK: - Post

    /// Post-sign checks of the final `result` (the last task's) and the `response` frames against the reviewed `request`,
    /// the `plan` and the pre-check's `verified` decode. Any failed check → `.refused(.VERIFY, …)`.
    public static func post(request: BILJSONObject, plan: BILPublicPlan, verified: BILVerifiedPayload?,
                     result: BILPublicSignResult, response: BILPublicResponseQr) -> Verdict {
        return guarded(.VERIFY) {
            guard let verified = verified else { throw BILVerifyError("post.unverified") }
            try BILVerifyError.check(result.chain == plan.chain && sameOptional(result.requestHash, plan.requestHash)
                                     && sameOptional(result.planHash, plan.planHash), "result.plan")
            guard let last = plan.tasks.last else { throw BILVerifyError("result.tasks") }
            try BILVerifyError.check(sameList(result.completedTaskIds, plan.tasks.map { $0.id }) && same(result.taskId, last.id),
                                     "result.tasks")
            guard let transport = request.obj("transport") else { throw BILVerifyError("request.transport") }
            guard let requestType = transport.str("type") else { throw BILVerifyError("transport.type") }
            if case .bitcoinPsbt(_, let maps, _) = verified {
                try postBitcoin(transport, requestType, plan, maps, result, response)
            } else if same(requestType, BILTronLinkRequestMapper.transportType) {
                try postTronLink(transport, try single(plan.tasks), verified, result, response)
            } else {
                try postSignature(transport, requestType, try single(plan.tasks), plan, verified, result, response)
            }
            return .ok(nil)
        }
    }

    /// TronLink (r2-tronlink §5.5): Ownbit's own frames read back with the scanner's parser and collector; the answer
    /// object has exactly the request object's keys in the same order and the same values except `hexList`; its one
    /// entry is the request's `Transaction` ‖ `12 41` ‖ the engine's signature (exactly one signature added, recId 0 / 1)
    /// recovering over `sha256(raw_data)` to the task address — or, for a message, `0x` ‖ r ‖ s ‖ v (v 27 / 28)
    /// recovering over TIP-191. One QR up to 1000 characters of entries, numbered parts above (in `cN` order, the
    /// request's address and type).
    private static func postTronLink(_ transport: BILJSONObject, _ task: BILPublicTask, _ verified: BILVerifiedPayload,
                                     _ result: BILPublicSignResult, _ response: BILPublicResponseQr) throws {
        try BILVerifyError.check(same(response.type, BILPublicResponseQr.tronLinkType), "response.type")
        guard let bytes = transport.str("payloadBytes").flatMap({ BILPublicHex.decode($0) }),
              let text = BILVerifyText.strictUTF8(bytes) else { throw BILVerifyError("transport.payloadBytes") }
        guard let requestFrame = BILTronLinkQrFormat.parse(text, maxChars: BILTronLinkQrFormat.maxRequestChars) else {
            throw BILVerifyError("tronlink.bean")
        }
        let answer: BILTronLinkRequest
        do {
            answer = try BILTronLinkAnswerCodec.decode(response.frames)
        } catch {
            throw BILVerifyError("response.tronlink.decode")
        }
        guard answer.hexList.count == 1 else { throw BILVerifyError("response.tronlink.entries") }
        let entry = answer.hexList[0]
        let joinedLength = entry.utf16.count + BILTronLinkCollector.separator.utf16.count
        try BILVerifyError.check((response.frames.count == 1) == (joinedLength <= BILTronLinkAnswerCodec.partChars), "response.tronlink.split")
        if response.frames.count == 1 {
            try BILVerifyError.check(sameList(answer.bean.keys, requestFrame.json.keys), "response.tronlink.keys")
            try BILVerifyError.check(requestFrame.json.keys.allSatisfy { key in
                same(key, "hexList") || answer.bean[key] == requestFrame.json[key]
            }, "response.tronlink.values")
        } else {
            try BILVerifyError.check(sameOptional(answer.address, requestFrame.address) && answer.type == requestFrame.type,
                                     "response.tronlink.parts")
            // The pager shows the codes in list order and TronLink reads them strictly in order (part 1 first, then the
            // next): the collector reassembles any order, so the order is checked here.
            try BILVerifyError.check(response.frames.enumerated().allSatisfy { pair in
                BILTronLinkQrFormat.parse(pair.element)?.cN == pair.offset + 1
            }, "response.tronlink.order")
        }
        guard let signature = result.raw.str("signature").flatMap({ BILPublicHex.decode($0) }) else {
            throw BILVerifyError("result.signature")
        }
        try BILVerifyError.check(signature.count == BILTronTransactionProto.signatureBytes, "tron.signature.size")
        let recId = Int(signature[64])
        try BILVerifyError.check(recId == 0 || recId == 1, "tron.signature.v")
        guard let address = task.addresses.first else { throw BILVerifyError("task.address") }
        let digest: [UInt8]
        switch verified {
        case .tronTransaction(let raw, _, _, _, let txProto):
            guard let proto = txProto else { throw BILVerifyError("tronlink.txProto") }
            try checkTronLinkEntry(entry, proto: proto, raw: raw, signature: signature)
            digest = BILPublicHash.sha256(raw)
        case .tronOwnershipProof(let raw, _, _, let proto):
            try checkTronLinkEntry(entry, proto: proto, raw: raw, signature: signature)
            digest = BILPublicHash.sha256(raw)
        case .tronMessage(let message):
            let expected = BILTronLinkAnswerCodec.signedMessage(signature: signature)
            try BILVerifyError.check(sameOptional(entry, expected), "response.tronlink.message")
            digest = BILPublicHash.tip191Digest(message)
        default:
            throw BILVerifyError("post.chain")
        }
        try BILVerifyError.check(recoversToTron(digest, recId, signature, address), "tron.signature.signer")
    }

    /// The answered entry extends the request's `Transaction` `proto` by exactly the engine's `signature`.
    private static func checkTronLinkEntry(_ entry: String, proto: [UInt8], raw: [UInt8], signature: [UInt8]) throws {
        guard let answered = BILTronLinkRequestMapper.entryBytes(entry) else { throw BILVerifyError("response.tronlink.entry") }
        guard let before = BILTronTransactionProto.split(proto) else { throw BILVerifyError("tronlink.txProto") }
        guard let after = BILTronTransactionProto.split(answered) else { throw BILVerifyError("response.tronlink.entry") }
        try BILVerifyError.check(after.raw == raw && after.signatures.count == before.signatures.count + 1, "response.tronlink.signatures")
        try BILVerifyError.check(answered == BILTronTransactionProto.appendSignature(proto, signature), "response.tronlink.appended")
    }

    private static func postSignature(_ transport: BILJSONObject, _ requestType: String, _ task: BILPublicTask, _ plan: BILPublicPlan,
                                      _ verified: BILVerifiedPayload, _ result: BILPublicSignResult,
                                      _ response: BILPublicResponseQr) throws {
        let suffix = Array(signRequestSuffix.utf16)
        let typeUnits = Array(requestType.utf16)
        try BILVerifyError.check(typeUnits.count >= suffix.count && Array(typeUnits.suffix(suffix.count)) == suffix, "response.requestType")
        let expected = String(decoding: typeUnits.prefix(typeUnits.count - suffix.count), as: UTF16.self) + signatureSuffix
        try BILVerifyError.check(same(response.type, expected), "response.type")
        let answer = try BILSignatureUrCodec.decodeSignature(response.frames)
        try BILVerifyError.check(same(answer.type, expected), "response.urType")
        var requestId: [UInt8]? = nil
        if let text = transport.str("requestId") {
            guard let id = BILPublicHex.decode(text) else { throw BILVerifyError("transport.requestId") }
            requestId = id
        }
        try BILVerifyError.check((requestId == nil && answer.requestId == nil) || (requestId != nil && requestId == answer.requestId),
                                 "response.requestId")
        let engineSignature = (result.raw.str("qrSignature") ?? result.raw.str("signature")).flatMap { BILPublicHex.decode($0) }
        try BILVerifyError.check(engineSignature != nil && engineSignature! == answer.signature, "response.signature.result")
        let sig = answer.signature
        guard let address = task.addresses.first else { throw BILVerifyError("task.address") }
        switch verified {
        case .evmTransaction(_, let tx):
            try BILVerifyError.check(sig.count >= 65 && sig.count <= 73, "evm.signature.size")
            try BILVerifyError.check(sig.count == 65 || sig[64] != 0, "evm.signature.v")
            let v = Array(sig[64...])
            let recId: Int?
            if tx.type == 0 {
                recId = legacyRecoveryId(v: v, chainId: tx.chainId)
            } else {
                try BILVerifyError.check(sig.count == 65, "evm.signature.v")
                recId = (v[0] == 0 || v[0] == 1) ? Int(v[0]) : nil
            }
            guard let id = recId else { throw BILVerifyError("evm.signature.v") }
            try BILVerifyError.check(recoversToEvm(tx.signingHash, id, sig, address), "evm.signature.signer")
        case .evmPersonal, .evmTypedData:
            try BILVerifyError.check(sig.count == 65, "evm.signature.size")
            let v = Int(sig[64])
            try BILVerifyError.check(v == 27 || v == 28, "evm.signature.v")
            let digest: [UInt8]
            if case .evmPersonal(let message) = verified {
                digest = BILEvmTxCodec.personalMessageDigest(message)
            } else {
                guard let d = BILPublicHex.decode(plan.signingBytesDigest ?? "") else { throw BILVerifyError("evm.digest") }
                digest = d
            }
            try BILVerifyError.check(recoversToEvm(digest, v - 27, sig, address), "evm.signature.signer")
        case .tronTransaction, .tronMessage:
            try BILVerifyError.check(sig.count == 65, "tron.signature.size")
            let recId = Int(sig[64])
            try BILVerifyError.check(recId == 0 || recId == 1, "tron.signature.v")
            let digest: [UInt8]
            if case .tronTransaction(let raw, _, _, _, _) = verified {
                digest = BILPublicHash.sha256(raw)
            } else if case .tronMessage(let message) = verified {
                digest = BILPublicHash.tip191Digest(message)
            } else {
                throw BILVerifyError("post.chain")
            }
            guard let pub = BILSecp256k1.recoverPublicKey(digest: digest, recId: recId, r: Array(sig[0..<32]), s: Array(sig[32..<64])) else {
                throw BILVerifyError("tron.signature.recover")
            }
            try BILVerifyError.check(sameOptional(tronAddress(uncompressed: pub), address), "tron.signature.signer")
        case .solanaTransaction(let message, _, _), .solanaMessage(let message):
            try BILVerifyError.check(sig.count == 64, "solana.signature.size")
            guard let key = BILPublicHex.decode(try single(task.publicKeys)), key.count == 32 else {
                throw BILVerifyError("solana.publicKey")
            }
            try BILVerifyError.check(ed25519Verify(signature: sig, message: message, publicKey: key), "solana.signature.verify")
        case .bitcoinPsbt, .tronOwnershipProof:
            throw BILVerifyError("post.chain")
        }
    }

    private static func postBitcoin(_ transport: BILJSONObject, _ requestType: String, _ plan: BILPublicPlan, _ maps: BILPsbtMaps,
                                    _ result: BILPublicSignResult, _ response: BILPublicResponseQr) throws {
        let expectedTypes: [String]
        if same(requestType, "crypto-psbt") || same(requestType, "psbt") || same(requestType, "bbqr-psbt") {
            expectedTypes = [requestType]
        } else if isPsbtTextType(requestType) {
            expectedTypes = [requestType, "crypto-psbt"]
        } else {
            throw BILVerifyError("response.requestType")
        }
        try BILVerifyError.check(expectedTypes.contains { same($0, response.type) }, "response.type")
        if isPsbtTextType(response.type) {
            try BILVerifyError.check(response.frames.count == 1 && response.frames[0].utf16.count <= staticPsbtMaxChars, "response.static")
        }
        if same(requestType, "bbqr-psbt") {
            let encoding: UInt16 = same(transport.str("encoding"), "H") ? 0x48 : 0x32      // "H" : "2"
            try BILVerifyError.check(response.frames.allSatisfy { frame in
                let u = Array(frame.utf16)
                return u.count > 2 && u[2] == encoding
            }, "response.bbqr.encoding")
        }
        let answered = try BILSignatureUrCodec.decodePsbt(type: response.type, frames: response.frames)
        guard let text = result.raw.str("psbt") else { throw BILVerifyError("result.psbt") }
        let signed = try BILSignatureUrCodec.base64(text)
        try BILVerifyError.check(answered == signed, "response.psbt.result")
        var signers = [Int: Set<String>]()
        for task in plan.tasks {
            for target in targets(of: task) {
                signers[target.input, default: []].insert(target.publicKey.lowercased())
            }
        }
        let diff = BILPsbtMaps.diff(request: maps, response: try BILPsbtMaps.parse(answered), signers: signers)
        try BILVerifyError.check(diff.ok, "response.psbt.diff")
    }

    // MARK: - EIP-712 equivalence

    /// JSON equality where numbers compare by value (the engine re-serialises the typed data it parsed; Android
    /// `PublicSignVerifier.equivalent`): objects have the same key sets (exact keys, order-insensitive) and equivalent
    /// values; arrays the same size and equivalent elements; null equals only null; if either primitive is a string both
    /// must be strings with exactly the same content; other primitives compare as exact decimals (`1` == `1.0` == `1e0`,
    /// Java `BigDecimal.compareTo`, no `Double` / `Decimal`), else by their literal text.
    public static func equivalent(_ a: BILJSONValue, _ b: BILJSONValue) -> Bool {
        switch (a, b) {
        case (.object(let x), .object(let y)):
            guard x.count == y.count else { return false }
            for entry in x.entries {
                guard let other = y[entry.key], equivalent(entry.value, other) else { return false }
            }
            return true
        case (.array(let x), .array(let y)):
            guard x.count == y.count else { return false }
            for i in 0..<x.count where !equivalent(x[i], y[i]) { return false }
            return true
        case (.null, _), (_, .null):
            return a.isNull && b.isNull
        case (.object, _), (_, .object), (.array, _), (_, .array):
            return false
        default:
            break
        }
        // Both are primitives (string / number / bool).
        if a.stringValue != nil || b.stringValue != nil {
            guard let x = a.stringValue, let y = b.stringValue else { return false }
            return same(x, y)
        }
        let x = primitiveContent(a)
        let y = primitiveContent(b)
        if let dx = exactDecimal(x), let dy = exactDecimal(y) { return dx == dy }
        return same(x, y)
    }

    // MARK: - Shared helpers (internal: the policy and the harness use them)

    /// (input index, public key hex) of every target of a Bitcoin task (engine `task.targets`; Android `targetsOf`):
    /// object elements with an Int `inputIndex` and a string `publicKey`, others skipped.
    public static func targets(of task: BILPublicTask) -> [(input: Int, publicKey: String)] {
        var out = [(input: Int, publicKey: String)]()
        for element in task.raw.arr("targets") ?? [] {
            guard let target = element.objectValue, let input = target.int("inputIndex"), let key = target.str("publicKey") else { continue }
            out.append((input, key))
        }
        return out
    }

    /// Android `TronAddressCodec.toHex41`: lower-case `41…` hex of a base58 `T…` address or of a `41…` / `0x41…` hex
    /// address (Kotlin-trimmed); nil when invalid (bad checksum / length / version). The hex forms accept ASCII hex only
    /// (Android's `Character.digit` would also take other scripts' digits, which no TRON address or owner field has).
    public static func tronHex41(_ address: String) -> String? {
        let a = BILKotlinText.trim(address)
        let units = Array(a.utf16)
        if units.count == 42 && BILPublicHex.hasASCIIPrefix(a, "41") && BILPublicHex.decode(a) != nil {
            return a.lowercased()
        }
        if units.count == 44 {
            let head = units[0..<4].map { $0 >= 0x41 && $0 <= 0x5A ? $0 + 0x20 : $0 }
            if head == Array("0x41".utf16) {
                return String(decoding: units[2...], as: UTF16.self).lowercased()
            }
        }
        guard let decoded = BILBase58.decode(a), decoded.count == 25 else { return nil }
        let payload = Array(decoded[0..<21])
        guard BILBase58Check.checksum(payload) == Array(decoded[21..<25]), payload[0] == 0x41 else { return nil }
        return BILPublicHex.encode(payload)
    }

    /// The TRON base58 address of an uncompressed (65-byte) secp256k1 public key (Android `tronAddress`).
    public static func tronAddress(uncompressed: [UInt8]) -> String? {
        guard let evm = BILSecp256k1.evmAddressBytes(uncompressed: uncompressed), evm.count == 20 else { return nil }
        return BILBase58Check.encode([0x41] + evm)
    }

    // MARK: - Private

    private static let signRequestSuffix = "-sign-request"
    private static let signatureSuffix = "-signature"
    /// A static PSBT text answer stays static up to this length, else it goes out as animated `crypto-psbt` (engine).
    private static let staticPsbtMaxChars = 1_800
    private static let psbtTextTypes = ["psbt-base64", "psbt-hex"]
    /// Longest exact integer text `domain.chainId` is turned into (a chain id above this is never usable; Android's
    /// `BigInteger` result for such a value is ignored by its only reader, the D43 lookup chain, which needs 0 < id < 2⁶³).
    private static let maxIntegerDigits = 4_096

    /// Android `guarded(failure)`: a failed check (`BILVerifyError`, a Solana parse error) refuses with its name; any
    /// other error refuses with its type name (Android maps `IllegalArgumentException` / `IndexOutOfBoundsException`
    /// so; the remaining ones cannot arise from these decoders).
    private static func guarded(_ failure: Reason, _ body: () throws -> Verdict) -> Verdict {
        do {
            return try body()
        } catch let e as BILVerifyError {
            return .refused(failure, detail: e.what)
        } catch BILSolanaMessageHeader.ParseError.malformed(let what) {
            return .refused(failure, detail: what)
        } catch {
            return .refused(failure, detail: String(describing: type(of: error)))
        }
    }

    /// C-RESP-2 / O-RESP-1: the request id the answer must echo (`transport.requestId`, which `post` compares with the
    /// answer QR) is the one of the original QR bytes, read natively — absent in both or byte-equal — so the echo is bound
    /// to what was scanned, not only to the engine's decoded request.
    private static func checkRequestId(_ request: BILJSONObject, _ cbor: BILSignatureUrCodec.SignRequest) throws {
        var fromTransport: [UInt8]? = nil
        if let text = request.obj("transport")?.str("requestId") {
            guard let id = BILPublicHex.decode(text) else { throw BILVerifyError("transport.requestId") }
            fromTransport = id
        }
        let fromQr = cbor.requestId
        try BILVerifyError.check((fromQr == nil && fromTransport == nil) || (fromQr != nil && fromTransport != nil && fromQr! == fromTransport!),
                                 "request.requestId")
    }

    /// Kotlin `List.single()`: more than one element is Android's `IllegalArgumentException` (refused under that name, as
    /// `guarded` does there); an empty list is Kotlin's `NoSuchElementException`, which Android's `guarded` does not catch
    /// (its coordinator then ends matching as UNEXPECTED) — refused here under that name. Not reachable from a parsed
    /// plan (`task.paths` non-empty, one key per path) or a mapped TronLink request (exactly one entry).
    private static func single<T>(_ list: [T]) throws -> T {
        guard list.count == 1 else { throw BILVerifyError(list.isEmpty ? "NoSuchElementException" : "IllegalArgumentException") }
        return list[0]
    }

    /// A protobuf owner field Android accepts: 42 characters starting "41".
    private static func isOwnerHex41(_ owner: String) -> Bool {
        return owner.utf16.count == 42 && BILPublicHex.hasASCIIPrefix(owner, "41")
    }

    private static func isPsbtTextType(_ type: String) -> Bool {
        return psbtTextTypes.contains { same($0, type) }
    }

    /// EIP-155 legacy `v` (1…9 big-endian bytes, no leading zero beyond the first) − 35 − 2·chainId, when that is 0 or 1.
    private static func legacyRecoveryId(v: [UInt8], chainId: UInt64) -> Int? {
        guard !v.isEmpty, v.count <= 16 else { return nil }
        // v as a 128-bit value (hi, lo).
        var hi: UInt64 = 0
        var lo: UInt64 = 0
        for byte in v {
            hi = (hi << 8) | (lo >> 56)
            lo = (lo << 8) | UInt64(byte)
        }
        // base = 2·chainId + 35 as (hi, lo); chainId < 2⁶³ so 2·chainId fits 64 bits.
        let doubled = chainId.multipliedReportingOverflow(by: 2)
        var baseHi: UInt64 = doubled.overflow ? 1 : 0
        let sum = doubled.partialValue.addingReportingOverflow(35)
        let baseLo = sum.partialValue
        if sum.overflow { baseHi += 1 }
        for recId in 0...1 {
            let candidate = baseLo.addingReportingOverflow(UInt64(recId))
            let candidateHi = baseHi + (candidate.overflow ? 1 : 0)
            if candidate.partialValue == lo && candidateHi == hi { return recId }
        }
        return nil
    }

    /// Recovery over `digest` with `recId` gives the EVM address `address` (ASCII case-insensitive, Android
    /// `equals(ignoreCase = true)` on a checksummed address).
    private static func recoversToEvm(_ digest: [UInt8], _ recId: Int, _ sig: [UInt8], _ address: String) -> Bool {
        guard let pub = BILSecp256k1.recoverPublicKey(digest: digest, recId: recId, r: Array(sig[0..<32]), s: Array(sig[32..<64])),
              let evm = BILSecp256k1.evmAddressBytes(uncompressed: pub) else { return false }
        return BILVerifyText.equalsIgnoringCase("0x" + BILPublicHex.encode(evm), address)
    }

    private static func recoversToTron(_ digest: [UInt8], _ recId: Int, _ sig: [UInt8], _ address: String) -> Bool {
        guard let pub = BILSecp256k1.recoverPublicKey(digest: digest, recId: recId, r: Array(sig[0..<32]), s: Array(sig[32..<64])) else {
            return false
        }
        return sameOptional(tronAddress(uncompressed: pub), address)
    }

    private static func ed25519Verify(signature: [UInt8], message: [UInt8], publicKey: [UInt8]) -> Bool {
        guard let key = try? Curve25519.Signing.PublicKey(rawRepresentation: Data(publicKey)) else { return false }
        return key.isValidSignature(Data(signature), for: Data(message))
    }

    // Exact (code-unit) string helpers.
    private static func same(_ a: String, _ b: String) -> Bool {
        return BILJSONExact.equal(a, b)
    }

    private static func same(_ a: String?, _ b: String) -> Bool {
        guard let x = a else { return false }
        return BILJSONExact.equal(x, b)
    }

    private static func sameOptional(_ a: String?, _ b: String?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (x?, y?): return BILJSONExact.equal(x, y)
        default: return false
        }
    }

    private static func sameList(_ a: [String], _ b: [String]) -> Bool {
        guard a.count == b.count else { return false }
        for i in 0..<a.count where !BILJSONExact.equal(a[i], b[i]) { return false }
        return true
    }

    // MARK: - Exact decimals (Java BigDecimal semantics)

    /// A decimal value: `negative`, significant `digits` without leading / trailing zeros (empty = zero) and the
    /// position of the decimal point (value = 0.d₁d₂… × 10^`point`). Two values are equal iff these are.
    private struct ExactDecimal: Equatable {
        let negative: Bool
        let digits: [UInt8]
        let point: Int64
    }

    /// The content of a primitive as kotlinx's `JsonPrimitive.content` (number literal, `true` / `false`).
    private static func primitiveContent(_ v: BILJSONValue) -> String {
        switch v {
        case .string(let s): return s
        case .number(let n): return n
        case .bool(let b): return b ? "true" : "false"
        case .null: return "null"
        default: return ""
        }
    }

    /// Kotlin `String.toBigDecimalOrNull()` (Java float grammar screen, then `new BigDecimal`): `[+-]?` digits with an
    /// optional `.` (at least one digit), optional `[eE][+-]?digits` with at most 10 significant exponent digits, the
    /// exponent and the scale within `Int32`; ASCII digits only. nil otherwise.
    private static func exactDecimal(_ text: String) -> ExactDecimal? {
        let u = Array(text.utf8)
        var i = 0
        var negative = false
        if i < u.count && (u[i] == 0x2B || u[i] == 0x2D) {
            negative = u[i] == 0x2D
            i += 1
        }
        var whole = [UInt8]()
        while i < u.count && u[i] >= 0x30 && u[i] <= 0x39 {
            whole.append(u[i] - 0x30)
            i += 1
        }
        var fraction = [UInt8]()
        if i < u.count && u[i] == 0x2E {
            i += 1
            while i < u.count && u[i] >= 0x30 && u[i] <= 0x39 {
                fraction.append(u[i] - 0x30)
                i += 1
            }
        }
        guard !whole.isEmpty || !fraction.isEmpty else { return nil }
        var exponent: Int64 = 0
        if i < u.count && (u[i] == 0x65 || u[i] == 0x45) {
            i += 1
            var expNegative = false
            if i < u.count && (u[i] == 0x2B || u[i] == 0x2D) {
                expNegative = u[i] == 0x2D
                i += 1
            }
            var expDigits = [UInt8]()
            while i < u.count && u[i] >= 0x30 && u[i] <= 0x39 {
                expDigits.append(u[i] - 0x30)
                i += 1
            }
            guard !expDigits.isEmpty else { return nil }
            // Java parseExp: leading zeros are skipped only while more than 10 digits remain; more than 10 → invalid.
            var start = 0
            while expDigits.count - start > 10 && expDigits[start] == 0 { start += 1 }
            guard expDigits.count - start <= 10 else { return nil }
            for d in expDigits[start...] { exponent = exponent * 10 + Int64(d) }
            if expNegative { exponent = -exponent }
            // Java: `if ((int) exp != exp) throw` — the exponent itself must fit an Int32.
            guard exponent >= Int64(Int32.min) && exponent <= Int64(Int32.max) else { return nil }
        }
        guard i == u.count else { return nil }
        let scale = Int64(fraction.count) - exponent
        guard scale >= Int64(Int32.min) && scale <= Int64(Int32.max) else { return nil }
        let all = whole + fraction                          // value = all × 10^(−scale)
        guard let first = all.firstIndex(where: { $0 != 0 }) else {
            return ExactDecimal(negative: false, digits: [], point: 0)
        }
        let last = all.lastIndex(where: { $0 != 0 }) ?? first
        let significant = Array(all[first...last])
        let trailing = Int64(all.count - 1 - last)
        return ExactDecimal(negative: negative, digits: significant, point: Int64(significant.count) + trailing - scale)
    }

    /// Android `bigInteger(element)` (the EIP-712 `domain.chainId`) as exact decimal integer text: a primitive's
    /// content, Kotlin-trimmed and lower-cased; a string starting `0x` → hexadecimal (`toBigIntegerOrNull(16)`); else the
    /// exact decimal if it is an integer (`toBigIntegerExact`: `1.0` → "1", `1.5` → nil). nil for objects / arrays /
    /// anything unreadable, and for integers of more than 4,096 digits (never a usable chain id; see `maxIntegerDigits`).
    public static func exactIntegerText(_ element: BILJSONValue) -> String? {
        switch element {
        case .object, .array:
            return nil
        default:
            break
        }
        let text = BILKotlinText.trim(primitiveContent(element)).lowercased()
        if element.stringValue != nil && BILPublicHex.hasASCIIPrefix(text, "0x") {
            return hexIntegerText(Array(text.utf16.dropFirst(2)))
        }
        guard let d = exactDecimal(text) else { return nil }
        if d.digits.isEmpty { return "0" }
        guard d.point >= Int64(d.digits.count), d.point <= Int64(maxIntegerDigits) else { return nil }
        let zeros = [UInt8](repeating: 0x30, count: Int(d.point) - d.digits.count)
        return (d.negative ? "-" : "") + String(decoding: d.digits.map { $0 + 0x30 } + zeros, as: UTF8.self)
    }

    /// Kotlin `String.toBigIntegerOrNull(16)` (a leading `-`, then `Character.digit(c, 16)` per UTF-16 unit: ASCII and
    /// full-width hex letters, any BMP decimal digit) as decimal text.
    private static func hexIntegerText(_ units: [UInt16]) -> String? {
        guard !units.isEmpty else { return nil }
        let negative = units.count > 1 && units[0] == 0x2D
        let digitUnits = negative ? Array(units.dropFirst()) : units
        var values = [UInt32]()
        values.reserveCapacity(digitUnits.count)
        for unit in digitUnits {
            guard let v = javaHexDigit(unit) else { return nil }
            values.append(v)
        }
        guard values.count <= maxIntegerDigits else { return nil }
        // Base-16 digits → base 10⁹ limbs (little-endian).
        var limbs: [UInt64] = [0]
        for v in values {
            var carry = UInt64(v)
            for k in 0..<limbs.count {
                let x = limbs[k] * 16 + carry
                limbs[k] = x % 1_000_000_000
                carry = x / 1_000_000_000
            }
            while carry > 0 {
                limbs.append(carry % 1_000_000_000)
                carry /= 1_000_000_000
            }
        }
        while limbs.count > 1 && limbs.last == 0 { limbs.removeLast() }
        var text = String(limbs[limbs.count - 1])
        for k in stride(from: limbs.count - 2, through: 0, by: -1) {
            let part = String(limbs[k])
            text += String(repeating: "0", count: 9 - part.count) + part
        }
        if text == "0" { return "0" }
        return (negative ? "-" : "") + text
    }

    /// Java `Character.digit(unit, 16)` for a UTF-16 unit, nil when it is not a digit of radix 16.
    private static func javaHexDigit(_ unit: UInt16) -> UInt32? {
        switch unit {
        case 0x30...0x39: return UInt32(unit - 0x30)
        case 0x41...0x46: return UInt32(unit - 0x41 + 10)
        case 0x61...0x66: return UInt32(unit - 0x61 + 10)
        case 0xFF21...0xFF26: return UInt32(unit - 0xFF21 + 10)
        case 0xFF41...0xFF46: return UInt32(unit - 0xFF41 + 10)
        case 0xD800...0xDFFF: return nil
        default:
            guard unit >= 0x80, let scalar = Unicode.Scalar(unit),
                  scalar.properties.generalCategory == .decimalNumber,
                  let value = scalar.properties.numericValue, value >= 0, value <= 9 else { return nil }
            return UInt32(value)
        }
    }
}

// C-KEY-5: a verdict names its reason and check only (the payload prints its kind, never content).
extension BILPublicSignVerifier.Verdict: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        switch self {
        case .ok(let payload): return "Ok(" + (payload.map { $0.description } ?? "nil") + ")"
        case .refused(let reason, let detail): return "Refused(" + reason.rawValue + ", " + detail + ")"
        }
    }

    public var debugDescription: String {
        return description
    }

    public var customMirror: Mirror {
        return Mirror(self, children: [:])
    }

    /// The pre-check's decode of an `.ok` verdict (nil for `.refused` and for `post`'s `.ok(nil)`).
    var payload: BILVerifiedPayload? {
        if case .ok(let p) = self { return p }
        return nil
    }

    var isOk: Bool {
        if case .ok = self { return true }
        return false
    }

    /// The refusal reason, nil for `.ok`.
    var reason: BILPublicSignVerifier.Reason? {
        if case .refused(let r, _) = self { return r }
        return nil
    }

    /// The failed check's log-safe name, nil for `.ok`.
    var detail: String? {
        if case .refused(_, let d) = self { return d }
        return nil
    }
}
