// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.publicsigner.verify

import io.ownbit.core.chain.evm.EvmTxCodec
import io.ownbit.core.chain.tron.TronAddressCodec
import io.ownbit.core.chain.tron.TronRawData
import io.ownbit.core.chain.tron.TronTransactionProto
import io.ownbit.core.crypto.hash.Hashes
import io.ownbit.core.crypto.util.Hex
import io.ownbit.core.publicsigner.model.PsChain
import io.ownbit.core.publicsigner.model.PublicPlan
import io.ownbit.core.publicsigner.model.PublicResponseQr
import io.ownbit.core.publicsigner.model.PublicSignResult
import io.ownbit.core.publicsigner.model.PublicTask
import io.ownbit.core.publicsigner.model.arr
import io.ownbit.core.publicsigner.model.int
import io.ownbit.core.publicsigner.model.long
import io.ownbit.core.publicsigner.model.obj
import io.ownbit.core.publicsigner.model.str
import io.ownbit.core.publicsigner.scan.OtherWalletRequestException
import io.ownbit.core.publicsigner.scan.TronLinkCollector
import io.ownbit.core.publicsigner.scan.TronLinkRequest
import io.ownbit.core.publicsigner.sign.PublicSignSession
import io.ownbit.core.publicsigner.sign.TronLinkAnswerCodec
import io.ownbit.core.publicsigner.sign.TronLinkRequestMapper
import io.ownbit.core.scanner.publicqr.TronLinkQrFormat
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.bouncycastle.math.ec.rfc8032.Ed25519
import java.math.BigInteger

/**
 * What [PublicSignVerifier.pre] decoded, with independent Kotlin code, from the **original QR bytes** the plan commits
 * to (`transport.payloadBytes`, re-checked against the engine's request): the facts the policy, the signature-insight card and
 * the post check use. Public data only.
 */
sealed interface VerifiedPayload {

    /** EVM `eth-sign-request` dataType 1 / 4: [signData] decodes to [tx]; `keccak256(signData)` is the plan's digest. */
    class EvmTransaction(val signData: ByteArray, val tx: EvmTxCodec.UnsignedEvmTx) : VerifiedPayload {
        override fun toString(): String = "EvmTransaction($tx)"
    }

    /** EVM dataType 3 (`personal_sign`): the exact [message] bytes; the EIP-191 digest is the plan's. */
    class EvmPersonal(val message: ByteArray) : VerifiedPayload {
        override fun toString(): String = "EvmPersonal(${message.size} bytes)"
    }

    /**
     * EVM dataType 2 (EIP-712 v4): [json] = the exact UTF-8 text of the QR; [domainChainId] = `domain.chainId` when
     * the domain has one (else the signature is valid on any chain). The digest is the engine's (no Kotlin hasher).
     */
    class EvmTypedData(val json: String, val domainChainId: BigInteger?, val hasDomainChainId: Boolean) : VerifiedPayload {
        override fun toString(): String = "EvmTypedData(${json.length} chars, chainId=${hasDomainChainId})"
    }

    /**
     * TRON dataType 1 (and the TronLink transactions): [raw] = `raw_data` protobuf, `sha256(raw)` = the
     * txID and the plan's digest; one contract of [contractType] owned by [ownerHex41] (`41…`, lower case). [txProto]:
     * the whole `Transaction` protobuf TronLink sent (`raw_data` + existing signatures), which its answer extends.
     */
    class TronTransaction(
        val raw: ByteArray,
        val decoded: TronRawData,
        val ownerHex41: String,
        val contractType: Int,
        val txProto: ByteArray? = null,
    ) : VerifiedPayload {
        val txId: String get() = Hashes.sha256Hex(raw)
        override fun toString(): String = "TronTransaction(type=$contractType)"
    }

    /**
     * TronLink's ownership check (type 99): [raw] is exactly the fixed placeholder `{contract:
     * [{ContractName: [name]}]}` — no contract type, parameter, reference block or expiration, never a valid on-chain
     * transaction; `sha256(raw)` is the plan's digest; [ownerHex41] the address it proves; [txProto] the `Transaction`
     * the answer extends.
     */
    class TronOwnershipProof(val raw: ByteArray, val name: String, val ownerHex41: String, val txProto: ByteArray) : VerifiedPayload {
        val txId: String get() = Hashes.sha256Hex(raw)
        override fun toString(): String = "TronOwnershipProof($name)"
    }

    /** TRON dataType 2 (TIP-191; TronLink types 102–104): the exact [message] bytes. */
    class TronMessage(val message: ByteArray) : VerifiedPayload {
        override fun toString(): String = "TronMessage(${message.size} bytes)"
    }

    /** Solana signType 1: the message [bytes] and its parsed [header]; the task key holds required slot [signerSlot]. */
    class SolanaTransaction(val bytes: ByteArray, val header: SolanaMessageHeader, val signerSlot: Int) : VerifiedPayload {
        override fun toString(): String = "SolanaTransaction($header, slot=$signerSlot)"
    }

    /** Solana signType 2: an off-chain text message. */
    class SolanaMessage(val bytes: ByteArray) : VerifiedPayload {
        override fun toString(): String = "SolanaMessage(${bytes.size} bytes)"
    }

    /**
     * A PSBT ([bytes], parsed [maps]); `sha256(unsigned tx)` is the plan's digest. [witnessOnlyInputs]: the SegWit v0
     * inputs whose amount comes only from `witnessUtxo` (no previous transaction) — the outpoint-amount memory
     * ([SignedOutpointMemory]) must check them.
     */
    class BitcoinPsbt(val bytes: ByteArray, val maps: PsbtMaps, val witnessOnlyInputs: List<Int> = emptyList()) : VerifiedPayload {
        override fun toString(): String = "BitcoinPsbt($maps, witnessOnly=${witnessOnlyInputs.size})"
    }
}

/**
 * Defense in depth around the engine: the engine is the only parser that decides what is signed; Kotlin re-checks with independent code and refuses on any
 * disagreement — before the password ([pre]) and before the answer is shown ([post]). Nothing here signs.
 *
 * Pre (on the original bytes `B` = `transport.payloadBytes` and the ready plan): `B` decodes to exactly the request the
 * engine reviewed (signData / PSBT equal, EVM chain id equal, request id equal), and Kotlin recomputes
 * `plan.signingBytesDigest` where it can — EVM transaction `keccak256(signData)` (strict [EvmTxCodec.decodeUnsigned];
 * its chain id must be the reviewed network's), `personal_sign` EIP-191, TRON `sha256(raw_data)` / TIP-191, Solana
 * `sha256(message)` with the task key in a required signer slot and no lookup table, Bitcoin `sha256(unsigned tx)`
 * ([PsbtMaps]). EIP-712 keeps the engine's digest (no Kotlin hasher); the text is still bound to the QR bytes.
 *
 * Post (on the final result and the response frames, decoded by [SignatureUrCodec]): the result belongs to this plan
 * (hashes, every task in order); the answer is the request's own transport; a signature answer is
 * `{1: request id (exactly the request's), 2: signature}` and the signature verifies for the task key over the digest
 * (secp256k1 recovery for EVM / TRON with the expected `v`, Ed25519 for Solana); a PSBT answer equals the engine's
 * result and differs from the reviewed PSBT only by signatures of the task keys on the task inputs.
 */
object PublicSignVerifier {

    sealed interface Verdict {
        /** Every check agreed. [payload] is the pre-check's decode (`null` from [post]). */
        data class Ok(val payload: VerifiedPayload?) : Verdict

        /** Refused: [reason] picks the text, [detail] names the failed check (log-safe, no payload). */
        data class Refused(val reason: Reason, val detail: String) : Verdict
    }

    enum class Reason {
        /** The request / plan / result / answer are inconsistent (`err.integrity`). */
        INTEGRITY,

        /** The chain id of the signed bytes differs from the request or the reviewed network (`err.chainMismatch`). */
        CHAIN_MISMATCH,

        /** A Solana v0 message with address lookup tables (`err.lookupTable`). */
        LOOKUP_TABLE,

        /** The produced signature or answer does not verify (`err.verify`, nothing returned). */
        VERIFY,
    }

    // ---- pre ----------------------------------------------------------------------------------------------------

    /** [pre] of a session being built (its review / plan / request; `session.verified` is ignored). */
    fun pre(session: PublicSignSession): Verdict = pre(session.request, session.plan, session.review.network?.chainId)

    /**
     * Pre-sign checks of [request] (the engine's decoded request) against the ready [plan]. [reviewedChainId] is the EVM
     * chain id the review shows (`review.network.chainId`).
     */
    fun pre(request: JsonObject, plan: PublicPlan, reviewedChainId: String?): Verdict = guarded(Reason.INTEGRITY) {
        verifyCheck(plan.isReady && plan.tasks.isNotEmpty()) { "plan.ready" }
        val chain = PsChain.fromWire(request.str("chain"))
        verifyCheck(chain != null && chain == plan.chain) { "request.chain" }
        verifyCheck(chain == PsChain.BITCOIN || plan.tasks.size == 1) { "plan.tasks" }
        val digest = plan.signingBytesDigest ?: throw PublicVerifyException("plan.digest")
        val transport = request.obj("transport") ?: throw PublicVerifyException("request.transport")
        val type = transport.str("type") ?: throw PublicVerifyException("transport.type")
        val payloadBytes = transport.str("payloadBytes")?.let(Hex::decodeOrNull) ?: throw PublicVerifyException("transport.payloadBytes")
        val payload = when (chain!!) {
            PsChain.BITCOIN -> preBitcoin(request, transport, type, payloadBytes, digest, plan)
            PsChain.EVM -> return@guarded preEvm(request, transport, type, payloadBytes, digest, reviewedChainId)
            PsChain.TRON -> when (type) {
                TronLinkRequestMapper.TRANSPORT_TYPE -> preTronLink(request, transport, payloadBytes, digest)
                else -> preTron(request, type, payloadBytes, digest)
            }
            PsChain.SOLANA -> return@guarded preSolana(request, type, payloadBytes, digest, plan.tasks.single())
        }
        Verdict.Ok(payload)
    }

    private fun preBitcoin(
        request: JsonObject,
        transport: JsonObject,
        type: String,
        payloadBytes: ByteArray,
        digest: String,
        plan: PublicPlan,
    ): VerifiedPayload {
        val psbt = when (transport.str("payloadEncoding")) {
            "cbor" -> {
                verifyCheck(type == "crypto-psbt" || type == "psbt") { "bitcoin.transport" }
                Cbor.decode(payloadBytes) as? ByteArray ?: throw PublicVerifyException("bitcoin.cbor")
            }
            "psbt" -> {
                verifyCheck(type in PSBT_TEXT_TYPES || type == "bbqr-psbt") { "bitcoin.transport" }
                payloadBytes
            }
            else -> throw PublicVerifyException("bitcoin.payloadEncoding")
        }
        val fromRequest = request.str("psbt")?.let(SignatureUrCodec::base64) ?: throw PublicVerifyException("bitcoin.psbt")
        verifyCheck(fromRequest.contentEquals(psbt)) { "bitcoin.psbt.differs" }
        val maps = PsbtMaps.parse(psbt)
        verifyCheck(maps.unsignedTxDigest == digest) { "bitcoin.digest" }
        for (task in plan.tasks) {
            verifyCheck(task.inputs.isNotEmpty() && task.inputs.all { it in maps.inputs.indices }) { "bitcoin.task.inputs" }
            verifyCheck(targetsOf(task).all { (input, _) -> input in task.inputs }) { "bitcoin.task.targets" }
        }
        // Defense in depth (the engine's own PREVOUT rule): an input without its previous transaction must spend
        // a SegWit (v0 or Taproot) output — a legacy input's signature commits to no amount at all — and must name its
        // amount and outpoint.
        val witnessOnly = ArrayList<Int>()
        for (i in maps.inputs.indices) {
            verifyCheck(maps.outpoint(i) != null && maps.claimedAmount(i) != null) { "bitcoin.prevout" }
            when (maps.prevoutKind(i)) {
                PsbtMaps.PrevoutKind.FULL_PREVIOUS_TX, PsbtMaps.PrevoutKind.WITNESS_TAPROOT -> Unit
                PsbtMaps.PrevoutKind.WITNESS_SEGWIT_V0 -> witnessOnly += i
                PsbtMaps.PrevoutKind.WITNESS_LEGACY, PsbtMaps.PrevoutKind.NONE -> throw PublicVerifyException("bitcoin.prevout.legacy")
            }
        }
        return VerifiedPayload.BitcoinPsbt(psbt, maps, witnessOnly)
    }

    private fun preEvm(
        request: JsonObject,
        transport: JsonObject,
        type: String,
        payloadBytes: ByteArray,
        digest: String,
        reviewedChainId: String?,
    ): Verdict {
        verifyCheck(type == "eth-sign-request" && transport.str("payloadEncoding") == "cbor") { "evm.transport" }
        val cbor = SignatureUrCodec.decodeSignRequest(type, payloadBytes)
        checkRequestId(request, cbor)
        val requestChainId = request.long("chainId")
        verifyCheck(cbor.chainId == requestChainId && transport.long("chainId") == requestChainId) { "evm.chainId.request" }
        return when (cbor.dataType) {
            1L, 4L -> {
                verifyCheck(request.str("kind") == "transaction") { "evm.kind" }
                verifyCheck(sameHex(request.str("transaction"), cbor.signData)) { "evm.transaction.differs" }
                val tx = try {
                    EvmTxCodec.decodeUnsigned(cbor.signData)
                } catch (e: EvmTxCodec.DecodeException) {
                    throw PublicVerifyException("evm.transaction.decode")
                }
                verifyCheck((cbor.dataType == 1L) == (tx.type == 0)) { "evm.dataType" }
                if (requestChainId != null && requestChainId != tx.chainId) {
                    return Verdict.Refused(Reason.CHAIN_MISMATCH, "evm.chainId.request")
                }
                if (reviewedChainId != tx.chainId.toString()) return Verdict.Refused(Reason.CHAIN_MISMATCH, "evm.chainId.review")
                verifyCheck(Hex.encode(tx.signingHash) == digest) { "evm.digest" }
                Verdict.Ok(VerifiedPayload.EvmTransaction(cbor.signData, tx))
            }
            3L -> {
                verifyCheck(request.str("kind") == "personal") { "evm.kind" }
                verifyCheck(sameHex(request.str("message"), cbor.signData)) { "evm.message.differs" }
                verifyCheck(Hex.encode(EvmTxCodec.personalMessageDigest(cbor.signData)) == digest) { "evm.digest" }
                Verdict.Ok(VerifiedPayload.EvmPersonal(cbor.signData))
            }
            2L -> {
                verifyCheck(request.str("kind") == "typedData") { "evm.kind" }
                val text = strictUtf8(cbor.signData) ?: throw PublicVerifyException("evm.typedData.utf8")
                val parsed = try {
                    Json.parseToJsonElement(text) as? JsonObject
                } catch (e: SerializationException) {
                    null
                } catch (e: IllegalArgumentException) {
                    null
                } ?: throw PublicVerifyException("evm.typedData.json")
                val engine = request.obj("typedData") ?: throw PublicVerifyException("evm.typedData")
                verifyCheck(equivalent(parsed, engine)) { "evm.typedData.differs" }
                val domain = parsed.obj("domain")
                val rawChainId = domain?.get("chainId")
                Verdict.Ok(VerifiedPayload.EvmTypedData(text, rawChainId?.let(::bigInteger), rawChainId != null && rawChainId != JsonNull))
            }
            else -> throw PublicVerifyException("evm.dataType")
        }
    }

    private fun preTron(request: JsonObject, type: String, payloadBytes: ByteArray, digest: String): VerifiedPayload {
        verifyCheck(type == "tron-sign-request") { "tron.transport" }
        val cbor = SignatureUrCodec.decodeSignRequest(type, payloadBytes)
        checkRequestId(request, cbor)
        return when (cbor.dataType) {
            1L -> {
                verifyCheck(request.str("kind") == "transaction") { "tron.kind" }
                val tx = request.obj("transaction") ?: throw PublicVerifyException("tron.transaction")
                verifyCheck(sameHex(tx.str("raw_data_hex"), cbor.signData)) { "tron.raw.differs" }
                val txId = Hashes.sha256Hex(cbor.signData)
                tx.str("txID")?.let { verifyCheck(it.equals(txId, ignoreCase = true)) { "tron.txID" } }
                verifyCheck(txId == digest) { "tron.digest" }
                val decoded = TronRawData.decodeOrNull(cbor.signData) ?: throw PublicVerifyException("tron.raw.decode")
                val contract = decoded.contracts.singleOrNull() ?: throw PublicVerifyException("tron.contracts")
                verifyCheck(contract.ownerAddress.length == 42 && contract.ownerAddress.startsWith("41")) { "tron.owner" }
                VerifiedPayload.TronTransaction(cbor.signData, decoded, contract.ownerAddress.lowercase(), contract.type)
            }
            2L -> {
                verifyCheck(request.str("kind") == "message") { "tron.kind" }
                verifyCheck(sameHex(request.str("message"), cbor.signData)) { "tron.message.differs" }
                verifyCheck(Hex.encode(tip191Digest(cbor.signData)) == digest) { "tron.digest" }
                VerifiedPayload.TronMessage(cbor.signData)
            }
            else -> throw PublicVerifyException("tron.dataType")
        }
    }

    /**
     * TronLink: the scanned request object (`payloadBytes`, UTF-8 JSON) is parsed with the scanner's
     * parser and mapped again with the same mapper — the result must be exactly the request the engine reviewed — then
     * its one entry is read strictly: `sha256(raw_data)` is the plan's digest; the type-99 placeholder becomes a
     * [VerifiedPayload.TronOwnershipProof] (its address = the request's), any other transaction a
     * [VerifiedPayload.TronTransaction] with exactly one contract; a TIP-191 message's digest is the plan's.
     */
    private fun preTronLink(request: JsonObject, transport: JsonObject, payloadBytes: ByteArray, digest: String): VerifiedPayload {
        verifyCheck(transport.str("payloadEncoding") == TronLinkRequestMapper.PAYLOAD_ENCODING) { "tronlink.payloadEncoding" }
        val text = strictUtf8(payloadBytes) ?: throw PublicVerifyException("tronlink.utf8")
        val frame = TronLinkQrFormat.parse(text, TronLinkQrFormat.MAX_REQUEST_CHARS)?.takeIf { !it.isPart }
            ?: throw PublicVerifyException("tronlink.bean")
        val mapped = try {
            TronLinkRequestMapper.map(TronLinkRequest.of(frame))
        } catch (e: OtherWalletRequestException) {
            throw PublicVerifyException("tronlink.map")
        }
        verifyCheck(mapped == request) { "tronlink.request.differs" }
        val address = request.str("address") ?: throw PublicVerifyException("tronlink.address")
        val ownerHex41 = TronAddressCodec.toHex41(address) ?: throw PublicVerifyException("tronlink.address")
        if (request.str("kind") == "message") {
            val message = messageBytes(request) ?: throw PublicVerifyException("tronlink.message")
            verifyCheck(Hex.encode(tip191Digest(message)) == digest) { "tronlink.digest" }
            return VerifiedPayload.TronMessage(message)
        }
        verifyCheck(request.str("kind") == "transaction") { "tronlink.kind" }
        val txProto = TronLinkRequestMapper.entryBytes(frame.hexList.single()) ?: throw PublicVerifyException("tronlink.entry")
        val split = TronTransactionProto.split(txProto) ?: throw PublicVerifyException("tronlink.entry")
        verifyCheck(sameHex(request.obj("transaction")?.str("raw_data_hex"), split.raw)) { "tronlink.raw.differs" }
        verifyCheck(Hashes.sha256Hex(split.raw) == digest) { "tronlink.digest" }
        val proof = TronLinkRequestMapper.ownershipProofName(split.raw)
        if (proof != null) {
            verifyCheck(frame.type == TronLinkRequestMapper.TYPE_OWNERSHIP && split.signatures.isEmpty()) { "tronlink.proof" }
            return VerifiedPayload.TronOwnershipProof(split.raw, proof, ownerHex41, txProto)
        }
        val decoded = TronRawData.decodeOrNull(split.raw) ?: throw PublicVerifyException("tronlink.raw.decode")
        val contract = decoded.contracts.singleOrNull() ?: throw PublicVerifyException("tronlink.contracts")
        verifyCheck(contract.ownerAddress.length == 42 && contract.ownerAddress.startsWith("41")) { "tronlink.owner" }
        return VerifiedPayload.TronTransaction(split.raw, decoded, contract.ownerAddress.lowercase(), contract.type, txProto)
    }

    /** The bytes of an engine-native TRON message request (`encoding` utf8 / hex). */
    private fun messageBytes(request: JsonObject): ByteArray? {
        val message = request.str("message") ?: return null
        return when (request.str("encoding")) {
            "utf8" -> message.toByteArray(Charsets.UTF_8)
            "hex", null -> Hex.decodeOrNull(message.removePrefix("0x"))
            else -> null
        }?.takeIf { it.isNotEmpty() }
    }

    private fun preSolana(request: JsonObject, type: String, payloadBytes: ByteArray, digest: String, task: PublicTask): Verdict {
        verifyCheck(type == "sol-sign-request") { "solana.transport" }
        val cbor = SignatureUrCodec.decodeSignRequest(type, payloadBytes)
        checkRequestId(request, cbor)
        val fromRequest = request.str("message")?.let(SignatureUrCodec::base64) ?: throw PublicVerifyException("solana.message")
        verifyCheck(fromRequest.contentEquals(cbor.signData)) { "solana.message.differs" }
        verifyCheck(Hashes.sha256Hex(cbor.signData) == digest) { "solana.digest" }
        val key = task.publicKeys.single()
        return when (cbor.dataType) {
            1L -> {
                verifyCheck(request.str("kind") == "transaction") { "solana.kind" }
                val header = try {
                    SolanaMessageHeader.parse(cbor.signData)
                } catch (e: SolanaMessageHeader.LookupTables) {
                    return Verdict.Refused(Reason.LOOKUP_TABLE, "solana.lookupTables")
                }
                val slot = header.signerSlot(key) ?: throw PublicVerifyException("solana.signerSlot")
                task.signerSlot?.let { verifyCheck(it == slot) { "solana.signerSlot.plan" } }
                Verdict.Ok(VerifiedPayload.SolanaTransaction(cbor.signData, header, slot))
            }
            2L -> {
                verifyCheck(request.str("kind") == "message") { "solana.kind" }
                verifyCheck(SolanaMessageHeader.isValidOffchainMessage(cbor.signData)) { "solana.offchainMessage" }
                Verdict.Ok(VerifiedPayload.SolanaMessage(cbor.signData))
            }
            else -> throw PublicVerifyException("solana.signType")
        }
    }

    // ---- post ---------------------------------------------------------------------------------------------------

    /** [post] of a session whose every task signed ([result] = the last task's result). */
    fun post(session: PublicSignSession, result: PublicSignResult, response: PublicResponseQr): Verdict =
        post(session.request, session.plan, session.verified, result, response)

    /** Post-sign checks of the final [result] and the [response] frames (see the class documentation). */
    fun post(
        request: JsonObject,
        plan: PublicPlan,
        verified: VerifiedPayload?,
        result: PublicSignResult,
        response: PublicResponseQr,
    ): Verdict = guarded(Reason.VERIFY) {
        verifyCheck(verified != null) { "post.unverified" }
        verifyCheck(result.chain == plan.chain && result.requestHash == plan.requestHash && result.planHash == plan.planHash) { "result.plan" }
        verifyCheck(result.completedTaskIds == plan.tasks.map { it.id } && result.taskId == plan.tasks.last().id) { "result.tasks" }
        val transport = request.obj("transport") ?: throw PublicVerifyException("request.transport")
        val requestType = transport.str("type") ?: throw PublicVerifyException("transport.type")
        when {
            verified is VerifiedPayload.BitcoinPsbt -> postBitcoin(transport, requestType, plan, verified, result, response)
            requestType == TronLinkRequestMapper.TRANSPORT_TYPE -> postTronLink(transport, plan.tasks.single(), verified!!, result, response)
            else -> postSignature(transport, requestType, plan.tasks.single(), plan, verified!!, result, response)
        }
        Verdict.Ok(null)
    }

    /**
     * TronLink: Ownbit's own frames read back with the scanner's parser and collector; the answer
     * object has exactly the request object's keys in the same order and the same values except `hexList`; its one
     * entry is the request's `Transaction` ‖ `12 41` ‖ the engine's signature (exactly one signature added, recId 0 / 1)
     * recovering over `sha256(raw_data)` to the task address — or, for a message, `0x` ‖ r ‖ s ‖ v (v 27 / 28)
     * recovering over TIP-191. One QR up to 1000 characters of entries, numbered parts above (in `cN` order, the
     * request's address and type).
     */
    private fun postTronLink(transport: JsonObject, task: PublicTask, verified: VerifiedPayload, result: PublicSignResult, response: PublicResponseQr) {
        verifyCheck(response.type == TronLinkRequestMapper.TRANSPORT_TYPE) { "response.type" }
        val text = transport.str("payloadBytes")?.let(Hex::decodeOrNull)?.let(::strictUtf8) ?: throw PublicVerifyException("transport.payloadBytes")
        val request = TronLinkQrFormat.parse(text, TronLinkQrFormat.MAX_REQUEST_CHARS) ?: throw PublicVerifyException("tronlink.bean")
        val answer = try {
            TronLinkAnswerCodec.decode(response.frames)
        } catch (e: Exception) {
            throw PublicVerifyException("response.tronlink.decode")
        }
        val entry = answer.hexList.singleOrNull() ?: throw PublicVerifyException("response.tronlink.entries")
        val joinedLength = entry.length + TronLinkCollector.SEPARATOR.length
        verifyCheck((response.frames.size == 1) == (joinedLength <= TronLinkAnswerCodec.PART_CHARS)) { "response.tronlink.split" }
        if (response.frames.size == 1) {
            verifyCheck(answer.bean.keys.toList() == request.json.keys.toList()) { "response.tronlink.keys" }
            verifyCheck(request.json.keys.all { it == "hexList" || answer.bean[it] == request.json[it] }) { "response.tronlink.values" }
        } else {
            verifyCheck(answer.address == request.address && answer.type == request.type) { "response.tronlink.parts" }
            // The pager shows the codes in list order and TronLink reads them strictly in order (part 1 first, then
            // the next): the collector reassembles any order, so the order is checked here.
            verifyCheck(response.frames.withIndex().all { (i, frame) -> TronLinkQrFormat.parse(frame)?.cN == i + 1 }) { "response.tronlink.order" }
        }
        val signature = engineSignature(result) ?: throw PublicVerifyException("result.signature")
        verifyCheck(signature.size == TronTransactionProto.SIGNATURE_BYTES) { "tron.signature.size" }
        val recId = signature[64].toInt() and 0xFF
        verifyCheck(recId == 0 || recId == 1) { "tron.signature.v" }
        val address = task.addresses.firstOrNull() ?: throw PublicVerifyException("task.address")
        val digest = when (verified) {
            is VerifiedPayload.TronTransaction, is VerifiedPayload.TronOwnershipProof -> {
                val (proto, raw) = when (verified) {
                    is VerifiedPayload.TronTransaction -> (verified.txProto ?: throw PublicVerifyException("tronlink.txProto")) to verified.raw
                    else -> (verified as VerifiedPayload.TronOwnershipProof).txProto to verified.raw
                }
                val answered = TronLinkRequestMapper.entryBytes(entry) ?: throw PublicVerifyException("response.tronlink.entry")
                val before = TronTransactionProto.split(proto) ?: throw PublicVerifyException("tronlink.txProto")
                val after = TronTransactionProto.split(answered) ?: throw PublicVerifyException("response.tronlink.entry")
                verifyCheck(after.raw.contentEquals(raw) && after.signatures.size == before.signatures.size + 1) { "response.tronlink.signatures" }
                verifyCheck(answered.contentEquals(TronTransactionProto.appendSignature(proto, signature))) { "response.tronlink.appended" }
                Hashes.sha256(raw)
            }
            is VerifiedPayload.TronMessage -> {
                verifyCheck(entry == TronLinkAnswerCodec.signedMessage(signature)) { "response.tronlink.message" }
                tip191Digest(verified.message)
            }
            else -> throw PublicVerifyException("post.chain")
        }
        verifyCheck(recoversToTron(digest, recId, signature, address)) { "tron.signature.signer" }
    }

    /** The engine's signature of a TRON result (`r ‖ s ‖ recId`). */
    private fun engineSignature(result: PublicSignResult): ByteArray? = result.raw.str("signature")?.let(Hex::decodeOrNull)

    private fun recoversToTron(digest: ByteArray, recId: Int, sig: ByteArray, address: String): Boolean {
        val pub = EvmTxCodec.recoverPublicKey(digest, recId, BigInteger(1, sig.copyOfRange(0, 32)), BigInteger(1, sig.copyOfRange(32, 64)))
            ?: return false
        return tronAddress(pub) == address
    }

    private fun postSignature(
        transport: JsonObject,
        requestType: String,
        task: PublicTask,
        plan: PublicPlan,
        verified: VerifiedPayload,
        result: PublicSignResult,
        response: PublicResponseQr,
    ) {
        verifyCheck(requestType.endsWith(SIGN_REQUEST_SUFFIX)) { "response.requestType" }
        val expected = requestType.removeSuffix(SIGN_REQUEST_SUFFIX) + SIGNATURE_SUFFIX
        verifyCheck(response.type == expected) { "response.type" }
        val answer = SignatureUrCodec.decodeSignature(response.frames)
        verifyCheck(answer.type == expected) { "response.urType" }
        val requestId = transport.str("requestId")?.let { Hex.decodeOrNull(it) ?: throw PublicVerifyException("transport.requestId") }
        verifyCheck((requestId == null && answer.requestId == null) || (requestId != null && requestId.contentEquals(answer.requestId))) {
            "response.requestId"
        }
        val engineSignature = (result.raw.str("qrSignature") ?: result.raw.str("signature"))?.let(Hex::decodeOrNull)
        verifyCheck(engineSignature != null && engineSignature.contentEquals(answer.signature)) { "response.signature.result" }
        val sig = answer.signature
        val address = task.addresses.firstOrNull() ?: throw PublicVerifyException("task.address")
        when (verified) {
            is VerifiedPayload.EvmTransaction -> {
                verifyCheck(sig.size in 65..73) { "evm.signature.size" }
                val v = BigInteger(1, sig.copyOfRange(64, sig.size))
                verifyCheck(sig.size == 65 || sig[64].toInt() != 0) { "evm.signature.v" }
                val recId = if (verified.tx.type == 0) {
                    v.subtract(BigInteger.valueOf(35)).subtract(BigInteger.valueOf(verified.tx.chainId).shiftLeft(1))
                } else {
                    verifyCheck(sig.size == 65) { "evm.signature.v" }
                    v
                }
                verifyCheck(recId == BigInteger.ZERO || recId == BigInteger.ONE) { "evm.signature.v" }
                verifyCheck(recoversTo(verified.tx.signingHash, recId.toInt(), sig, address)) { "evm.signature.signer" }
            }
            is VerifiedPayload.EvmPersonal, is VerifiedPayload.EvmTypedData -> {
                verifyCheck(sig.size == 65) { "evm.signature.size" }
                val v = sig[64].toInt() and 0xFF
                verifyCheck(v == 27 || v == 28) { "evm.signature.v" }
                val digest = if (verified is VerifiedPayload.EvmPersonal) {
                    EvmTxCodec.personalMessageDigest(verified.message)
                } else {
                    Hex.decodeOrNull(plan.signingBytesDigest.orEmpty()) ?: throw PublicVerifyException("evm.digest")
                }
                verifyCheck(recoversTo(digest, v - 27, sig, address)) { "evm.signature.signer" }
            }
            is VerifiedPayload.TronTransaction, is VerifiedPayload.TronMessage -> {
                verifyCheck(sig.size == 65) { "tron.signature.size" }
                val recId = sig[64].toInt() and 0xFF
                verifyCheck(recId == 0 || recId == 1) { "tron.signature.v" }
                val digest = if (verified is VerifiedPayload.TronTransaction) Hashes.sha256(verified.raw) else tip191Digest((verified as VerifiedPayload.TronMessage).message)
                val pub = EvmTxCodec.recoverPublicKey(
                    digest, recId, BigInteger(1, sig.copyOfRange(0, 32)), BigInteger(1, sig.copyOfRange(32, 64)),
                ) ?: throw PublicVerifyException("tron.signature.recover")
                verifyCheck(tronAddress(pub) == address) { "tron.signature.signer" }
            }
            is VerifiedPayload.SolanaTransaction, is VerifiedPayload.SolanaMessage -> {
                verifyCheck(sig.size == Ed25519.SIGNATURE_SIZE) { "solana.signature.size" }
                val key = Hex.decodeOrNull(task.publicKeys.single())?.takeIf { it.size == Ed25519.PUBLIC_KEY_SIZE }
                    ?: throw PublicVerifyException("solana.publicKey")
                val message = if (verified is VerifiedPayload.SolanaTransaction) verified.bytes else (verified as VerifiedPayload.SolanaMessage).bytes
                val ok = try {
                    Ed25519.verify(sig, 0, key, 0, message, 0, message.size)
                } catch (e: RuntimeException) {
                    false
                }
                verifyCheck(ok) { "solana.signature.verify" }
            }
            is VerifiedPayload.BitcoinPsbt, is VerifiedPayload.TronOwnershipProof -> throw PublicVerifyException("post.chain")
        }
    }

    private fun postBitcoin(
        transport: JsonObject,
        requestType: String,
        plan: PublicPlan,
        verified: VerifiedPayload.BitcoinPsbt,
        result: PublicSignResult,
        response: PublicResponseQr,
    ) {
        val expectedTypes = when (requestType) {
            "crypto-psbt", "psbt", "bbqr-psbt" -> setOf(requestType)
            "psbt-base64", "psbt-hex" -> setOf(requestType, "crypto-psbt")
            else -> throw PublicVerifyException("response.requestType")
        }
        verifyCheck(response.type in expectedTypes) { "response.type" }
        if (response.type in PSBT_TEXT_TYPES) verifyCheck(response.frames.size == 1 && response.frames.single().length <= STATIC_PSBT_MAX_CHARS) { "response.static" }
        if (requestType == "bbqr-psbt") {
            val encoding = if (transport.str("encoding") == "H") 'H' else '2'
            verifyCheck(response.frames.all { it.length > 2 && it[2] == encoding }) { "response.bbqr.encoding" }
        }
        val answered = SignatureUrCodec.decodePsbt(response.type, response.frames)
        val signed = result.raw.str("psbt")?.let(SignatureUrCodec::base64) ?: throw PublicVerifyException("result.psbt")
        verifyCheck(answered.contentEquals(signed)) { "response.psbt.result" }
        val signers = HashMap<Int, MutableSet<String>>()
        for (task in plan.tasks) for ((input, key) in targetsOf(task)) signers.getOrPut(input) { HashSet() } += key.lowercase()
        val diff = PsbtMaps.diff(verified.maps, PsbtMaps.parse(answered), signers)
        verifyCheck(diff.ok) { "response.psbt.diff" }
    }

    // ---- helpers ------------------------------------------------------------------------------------------------

    /**
     * The request id the answer must echo (`transport.requestId`, which [post] compares with the
     * answer QR) is the one of the original QR bytes, read by Kotlin — absent in both or byte-equal — so the echo is
     * bound to what was scanned, not only to the engine's decoded request.
     */
    private fun checkRequestId(request: JsonObject, cbor: SignatureUrCodec.SignRequestCbor) {
        val text = request.obj("transport")?.str("requestId")
        val fromTransport = text?.let { Hex.decodeOrNull(it) ?: throw PublicVerifyException("transport.requestId") }
        val fromQr = cbor.requestId
        verifyCheck((fromQr == null && fromTransport == null) || (fromQr != null && fromTransport != null && fromQr.contentEquals(fromTransport))) {
            "request.requestId"
        }
    }

    /** (input index, public key hex) of every target of a Bitcoin [task] (engine `task.targets`). */
    internal fun targetsOf(task: PublicTask): List<Pair<Int, String>> =
        (task.raw.arr("targets") ?: JsonArray(emptyList())).mapNotNull { element ->
            val target = element as? JsonObject ?: return@mapNotNull null
            val input = target.int("inputIndex") ?: return@mapNotNull null
            val key = target.str("publicKey") ?: return@mapNotNull null
            input to key
        }

    /** TIP-191: `keccak256("\x19TRON Signed Message:\n" + len + message)` (engine `tron.js`). */
    internal fun tip191Digest(message: ByteArray): ByteArray =
        Hashes.keccak256("\u0019TRON Signed Message:\n${message.size}".toByteArray(Charsets.UTF_8) + message)

    /** The TRON base58 address of an uncompressed secp256k1 public key. */
    internal fun tronAddress(uncompressed: ByteArray): String? {
        val evm = EvmTxCodec.publicKeyToAddress(uncompressed)
        return TronAddressCodec.toBase58("41" + evm.removePrefix("0x").lowercase())
    }

    private fun recoversTo(digest: ByteArray, recId: Int, sig: ByteArray, address: String): Boolean {
        val recovered = EvmTxCodec.recoverAddress(digest, recId, BigInteger(1, sig.copyOfRange(0, 32)), BigInteger(1, sig.copyOfRange(32, 64)))
        return recovered != null && recovered.equals(address, ignoreCase = true)
    }

    private fun sameHex(text: String?, bytes: ByteArray): Boolean {
        val hex = text?.removePrefix("0x")?.removePrefix("0X") ?: return false
        return hex.equals(Hex.encode(bytes), ignoreCase = true)
    }

    private fun strictUtf8(bytes: ByteArray): String? = try {
        Charsets.UTF_8.newDecoder()
            .onMalformedInput(java.nio.charset.CodingErrorAction.REPORT)
            .onUnmappableCharacter(java.nio.charset.CodingErrorAction.REPORT)
            .decode(java.nio.ByteBuffer.wrap(bytes)).toString()
    } catch (e: java.nio.charset.CharacterCodingException) {
        null
    }

    /** JSON equality where numbers compare by value (the engine re-serialises the typed data it parsed). */
    internal fun equivalent(a: JsonElement, b: JsonElement): Boolean = when {
        a is JsonObject && b is JsonObject -> a.keys == b.keys && a.keys.all { equivalent(a.getValue(it), b.getValue(it)) }
        a is JsonArray && b is JsonArray -> a.size == b.size && a.indices.all { equivalent(a[it], b[it]) }
        a is JsonNull || b is JsonNull -> a == b
        a is JsonPrimitive && b is JsonPrimitive -> when {
            a.isString || b.isString -> a.isString == b.isString && a.content == b.content
            else -> {
                val x = a.content.toBigDecimalOrNull()
                val y = b.content.toBigDecimalOrNull()
                if (x != null && y != null) x.compareTo(y) == 0 else a.content == b.content
            }
        }
        else -> false
    }

    private fun bigInteger(element: JsonElement): BigInteger? {
        val p = element as? JsonPrimitive ?: return null
        val text = p.content.trim().lowercase()
        return when {
            p.isString && text.startsWith("0x") -> text.substring(2).toBigIntegerOrNull(16)
            else -> text.toBigDecimalOrNull()?.let { runCatching { it.toBigIntegerExact() }.getOrNull() }
        }
    }

    private inline fun guarded(failure: Reason, block: () -> Verdict): Verdict = try {
        block()
    } catch (e: PublicVerifyException) {
        Verdict.Refused(failure, e.what)
    } catch (e: IllegalArgumentException) {
        Verdict.Refused(failure, e.javaClass.simpleName)
    } catch (e: IndexOutOfBoundsException) {
        Verdict.Refused(failure, e.javaClass.simpleName)
    }

    private const val SIGN_REQUEST_SUFFIX = "-sign-request"
    private const val SIGNATURE_SUFFIX = "-signature"

    /** A static PSBT text answer stays static up to this length, else it goes out as animated `crypto-psbt` (engine). */
    private const val STATIC_PSBT_MAX_CHARS = 1_800

    private val PSBT_TEXT_TYPES = setOf("psbt-base64", "psbt-hex")
}
