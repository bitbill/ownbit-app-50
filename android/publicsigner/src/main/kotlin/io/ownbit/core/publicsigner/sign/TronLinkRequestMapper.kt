// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.publicsigner.sign

import io.ownbit.core.chain.tron.TronAddressCodec
import io.ownbit.core.chain.tron.TronTransactionProto
import io.ownbit.core.crypto.util.Hex
import io.ownbit.core.publicsigner.scan.OtherWalletRequestException
import io.ownbit.core.publicsigner.scan.TronLinkRequest
import io.ownbit.core.publicsigner.text.PublicSignError
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonObject

/**
 * A TronLink request → the engine-native TRON request — the same code maps a scan, a
 * paste and the verifier's re-check of `transport.payloadBytes`, so what the engine reviews is bound to what was scanned:
 *
 * ```
 * transaction  {"chain":"tron","address":A,"kind":"transaction","transaction":{"raw_data_hex":R[,"signature":[…]]},
 *               "transport":{"type":"tronlink","payloadEncoding":"tronlink-json","payloadBytes":hex(bean),"tronlinkType":T}}
 * message      {"chain":"tron","address":A,"kind":"message","message":M,"encoding":"utf8"|"hex","transport":{…}}
 * ```
 * (`R` = `raw_data` of the one `Transaction` in `hexList`, read strictly by [TronTransactionProto]; `bean` = the request
 * object the answer echoes, [TronLinkRequest.bean].) The engine reviews, resolves (`protocolProfile: "tronlink"`) and
 * signs it as any TRON request; its Ownbit edition recognises the type-99 ownership placeholder by its exact bytes.
 *
 * Refused before the engine ([OtherWalletRequestException]):
 * - shielded (`type` 15, `alpha` / `tokenId`) → `err.tronlinkShielded`; a raw hash (101 / 17) → `err.tronlinkBlindHash`;
 *   a v1 message (98) → `err.tronlinkMessageV1`; more than one entry → `err.tronlinkMulti` (one transaction per request);
 * - `type` 99 without the placeholder, or the placeholder with another type → `err.integrity` (both must agree);
 * - no valid `T…` address, an entry that is not a strict `Transaction`, a bad message encoding → `err.qrMalformed`;
 *   an unknown type above 99 whose entry is not a transaction → `err.tronlinkType` (with the number).
 * Everything else (contract types, owner ≠ signer, existing signatures) is the engine's and the policy's to judge.
 */
object TronLinkRequestMapper {

    const val TRANSPORT_TYPE: String = "tronlink"
    const val PAYLOAD_ENCODING: String = "tronlink-json"

    /** TronLink's ownership check ("Pair cold wallet"). */
    const val TYPE_OWNERSHIP: Int = 99

    private const val TYPE_SHIELDED = 15
    private const val TYPE_TIP712_HASH = 101
    private const val TYPE_RAW_HASH = 17
    private const val TYPE_MESSAGE_V1 = 98
    private const val TYPE_MESSAGE_TEXT = 102
    private const val TYPE_MESSAGE_HEX = 103
    private const val TYPE_MESSAGE_BYTES = 104

    /** The engine's TRON message limit. */
    private const val MAX_MESSAGE_BYTES = 8_192

    /**
     * The placeholder names TronLink signs for its ownership check (iOS / Android builds); the engine's Ownbit edition
     * recognises exactly these bytes (`tron.js` `TRONLINK_OWNERSHIP_PROOFS`).
     */
    val OWNERSHIP_PROOF_NAMES: List<String> = listOf("TronLinkCustomContract", "ColdWalletOwnerVerifyContract")

    /** The engine-native request of [request] (see the class documentation). */
    fun map(request: TronLinkRequest): JsonObject {
        val type = request.type
        if (type == TYPE_SHIELDED || !request.alpha.isNullOrEmpty() || !request.tokenId.isNullOrEmpty()) {
            throw refused("publicprotocol_err_tronlinkshielded", "TRONLINK_SHIELDED")
        }
        if (type == TYPE_TIP712_HASH || type == TYPE_RAW_HASH) throw refused("publicprotocol_err_tronlinkblindhash", "TRONLINK_BLIND_HASH")
        if (type == TYPE_MESSAGE_V1) throw refused("publicprotocol_err_tronlinkmessagev1", "TRONLINK_MESSAGE_V1")
        if (request.hexList.size > 1) {
            throw refused("publicprotocol_err_tronlinkmulti", "TRONLINK_MULTI", args = listOf(request.hexList.size))
        }
        val address = request.address?.takeIf(::isTronAddress) ?: throw malformed()
        val entry = request.hexList.singleOrNull() ?: throw malformed()
        val payloadBytes = Hex.encode(request.bean.toString().toByteArray(Charsets.UTF_8))
        return when (type) {
            TYPE_MESSAGE_TEXT, TYPE_MESSAGE_HEX, TYPE_MESSAGE_BYTES -> {
                val (message, encoding) = message(type, entry)
                buildJsonObject {
                    put("chain", "tron")
                    put("address", address)
                    put("kind", "message")
                    put("message", message)
                    put("encoding", encoding)
                    transport(payloadBytes, type)
                }
            }
            else -> {
                // TronLink's transaction pages are types 0…99; an unknown type above 99 whose entry is not a
                // transaction is a page Ownbit does not know (a new message kind …): say so with its number.
                val notTransaction = { if (type > TYPE_OWNERSHIP) refused("publicprotocol_err_tronlinktype", "TRONLINK_TYPE", listOf(type)) else malformed() }
                val tx = entryBytes(entry) ?: throw notTransaction()
                val split = TronTransactionProto.split(tx) ?: throw notTransaction()
                val proof = ownershipProofName(split.raw) != null
                if (proof != (type == TYPE_OWNERSHIP)) {
                    throw OtherWalletRequestException(
                        OtherWalletRequestException.Kind.MALFORMED,
                        PublicSignError("publicprotocol_err_integrity", code = "INTEGRITY"),
                    )
                }
                buildJsonObject {
                    put("chain", "tron")
                    put("address", address)
                    put("kind", "transaction")
                    putJsonObject("transaction") {
                        put("raw_data_hex", Hex.encode(split.raw))
                        if (split.signatures.isNotEmpty()) put("signature", buildJsonArray { split.signatures.forEach { add(JsonPrimitive(Hex.encode(it))) } })
                    }
                    transport(payloadBytes, type)
                }
            }
        }
    }

    /**
     * The placeholder name when [raw] is exactly TronLink's ownership placeholder `raw_data = {contract:
     * [{ContractName: name}]}` (`5a <L> 22 <N> name`) for one of [OWNERSHIP_PROOF_NAMES], else `null`.
     */
    fun ownershipProofName(raw: ByteArray): String? = OWNERSHIP_PROOF_NAMES.firstOrNull { name ->
        val n = name.toByteArray(Charsets.US_ASCII)
        raw.contentEquals(byteArrayOf(0x5a, (n.size + 2).toByte(), 0x22, n.size.toByte()) + n)
    }

    /** The bytes of a transaction entry: lower- or upper-case hex of even length (no `0x`), else `null`. */
    fun entryBytes(entry: String): ByteArray? {
        if (entry.isEmpty() || entry.length % 2 != 0 || !entry.all(::isHexChar)) return null
        return Hex.decodeOrNull(entry.lowercase())
    }

    private fun kotlinx.serialization.json.JsonObjectBuilder.transport(payloadBytes: String, type: Int) {
        putJsonObject("transport") {
            put("type", TRANSPORT_TYPE)
            put("payloadEncoding", PAYLOAD_ENCODING)
            put("payloadBytes", payloadBytes)
            put("tronlinkType", type)
        }
    }

    /** (message, engine encoding) of a TIP-191 entry: 102 text (UTF-8), 103 hex (`0x` optional), 104 `b1,b2,…`. */
    private fun message(type: Int, entry: String): Pair<String, String> = when (type) {
        TYPE_MESSAGE_TEXT -> {
            val bytes = entry.toByteArray(Charsets.UTF_8).size
            if (bytes == 0 || bytes > MAX_MESSAGE_BYTES) throw malformed()
            entry to "utf8"
        }
        TYPE_MESSAGE_HEX -> {
            val hex = entry.removePrefix("0x").removePrefix("0X")
            val bytes = entryBytes(hex) ?: throw malformed()
            if (bytes.size > MAX_MESSAGE_BYTES) throw malformed()
            Hex.encode(bytes) to "hex"
        }
        else -> {
            val parts = entry.split(',')
            if (parts.size > MAX_MESSAGE_BYTES) throw malformed()
            val bytes = ByteArray(parts.size) { i ->
                val v = parts[i].trim().takeIf { it.matches(SIGNED_BYTE) }?.toIntOrNull() ?: throw malformed()
                if (v < -128 || v > 255) throw malformed()
                v.toByte()
            }
            Hex.encode(bytes) to "hex"
        }
    }

    private fun isTronAddress(address: String): Boolean =
        address.length == 34 && address.startsWith("T") && TronAddressCodec.toHex41(address) != null

    private fun isHexChar(c: Char): Boolean = c in '0'..'9' || c in 'a'..'f' || c in 'A'..'F'

    private val SIGNED_BYTE = Regex("^-?[0-9]{1,3}$")

    private fun refused(res: String, code: String, args: List<Any> = emptyList()) = OtherWalletRequestException(
        OtherWalletRequestException.Kind.UNSUPPORTED,
        PublicSignError(res, args = args, code = code),
    )

    private fun malformed() = OtherWalletRequestException(
        OtherWalletRequestException.Kind.MALFORMED,
        PublicSignError("publicprotocol_err_qrmalformed", code = "MALFORMED"),
    )
}
