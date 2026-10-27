// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.chain.tron

import io.ownbit.core.chain.json.looseString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import java.math.BigInteger

/**
 * A TRON transaction JSON as TronWeb produces it (`{visible, txID, raw_data, raw_data_hex[, signature]}`), with its
 * `raw_data_hex` decoded from protobuf (`protocol.Transaction.raw`).
 *
 * The node / dApp / backend builds these objects; TronWeb signs `txID` (= sha256 of `raw_data_hex`), i.e. the **hex**,
 * never the JSON `raw_data`. Everything the wallet checks before signing is therefore read from the decoded hex
 * ([raw]) — a JSON that disagrees with its hex cannot smuggle a different transfer past the confirmation.
 *
 * Pure Kotlin (no signing): used for the pre-sign verification of [TronTransactionVerifier] and for WalletConnect
 * display ([TronWcSigner.inspect]).
 */
class TronTransactionJson private constructor(
    /** The parsed JSON object (key order and number literals preserved). */
    val json: JsonObject,
    /** `txID` as given (lower-case hex expected). */
    val txId: String,
    /** `raw_data_hex` as given. */
    val rawDataHex: String,
    /** Decoded [rawDataHex], `null` when it is missing or not valid protobuf. */
    val raw: TronRawData?,
) {
    /** `true` when `txID == sha256(raw_data_hex)` (the hash TronWeb signs is the one of the bytes we decoded). */
    val isTxIdConsistent: Boolean
        get() {
            val bytes = rawDataHex.hexToBytesOrNull() ?: return false
            return rawDataHex.isNotEmpty() && sha256(bytes).toHex().equals(txId, ignoreCase = true)
        }

    /** Signatures already attached (hex strings). */
    val signatures: List<String>
        get() = (json["signature"] as? kotlinx.serialization.json.JsonArray)?.map { it.looseString() }.orEmpty()

    companion object {
        private val lenient = Json { ignoreUnknownKeys = true; isLenient = true }

        /** Parses [text]; `null` when it is not a JSON object. A missing / invalid hex yields [raw] = `null`. */
        fun parse(text: String): TronTransactionJson? {
            val obj = runCatching { lenient.parseToJsonElement(text.trim()) as? JsonObject }.getOrNull() ?: return null
            val hex = obj["raw_data_hex"].looseString()
            val raw = hex.hexToBytesOrNull()?.takeIf { it.isNotEmpty() }?.let { TronRawData.decodeOrNull(it) }
            return TronTransactionJson(obj, obj["txID"].looseString(), hex, raw)
        }
    }
}

/** `protocol.Transaction.raw`. Times in epoch milliseconds, amounts in SUN. */
data class TronRawData(
    val refBlockBytes: String,
    val refBlockHash: String,
    val expiration: Long,
    val timestamp: Long,
    val feeLimit: Long,
    /** `raw_data.data` (TRX on-chain memo) as hex, "" when absent. */
    val dataHex: String,
    val contracts: List<TronContract>,
) {
    companion object {
        /** Decodes the protobuf bytes, `null` when malformed. */
        fun decodeOrNull(bytes: ByteArray): TronRawData? = runCatching { decode(bytes) }.getOrNull()

        private fun decode(bytes: ByteArray): TronRawData {
            var refBlockBytes = ""
            var refBlockHash = ""
            var expiration = 0L
            var timestamp = 0L
            var feeLimit = 0L
            var data = ""
            val contracts = mutableListOf<TronContract>()
            ProtoReader(bytes).forEachField { field, value ->
                when (field) {
                    1 -> refBlockBytes = (value as ByteArray).toHex()
                    4 -> refBlockHash = (value as ByteArray).toHex()
                    8 -> expiration = value as Long
                    10 -> data = (value as ByteArray).toHex()
                    11 -> contracts += TronContract.decode(value as ByteArray)
                    14 -> timestamp = value as Long
                    18 -> feeLimit = value as Long
                }
            }
            return TronRawData(refBlockBytes, refBlockHash, expiration, timestamp, feeLimit, data, contracts)
        }
    }
}

/**
 * One `protocol.Transaction.Contract`, with the parameter decoded for the contract types the wallet builds or must
 * recognise. Addresses are hex with the `41` prefix, lower-case.
 */
data class TronContract(
    /** `ContractType` enum value (see [TronContractType]). */
    val type: Int,
    /** `parameter.type_url`, e.g. `type.googleapis.com/protocol.TransferContract`. */
    val typeUrl: String,
    val permissionId: Int,
    val ownerAddress: String,
    /** Transfer / TRC10 recipient, or the resource receiver of (un)delegations. */
    val toAddress: String? = null,
    /** TRX / TRC10 amount, frozen / unfrozen / delegated balance. */
    val amount: BigInteger? = null,
    /** TRC10 `asset_name` (the token id text). */
    val assetName: String? = null,
    /** TriggerSmartContract target. */
    val contractAddress: String? = null,
    val callValue: Long? = null,
    /** TriggerSmartContract call data, hex. */
    val callData: String? = null,
    /** Stake 2.0 `ResourceCode` (0 bandwidth, 1 energy). */
    val resource: Int? = null,
) {
    internal companion object {
        fun decode(bytes: ByteArray): TronContract {
            var type = 0
            var typeUrl = ""
            var value = ByteArray(0)
            var permissionId = 0
            ProtoReader(bytes).forEachField { field, v ->
                when (field) {
                    1 -> type = (v as Long).toInt()
                    2 -> ProtoReader(v as ByteArray).forEachField { f, pv ->
                        when (f) {
                            1 -> typeUrl = String(pv as ByteArray, Charsets.UTF_8)
                            2 -> value = pv as ByteArray
                        }
                    }
                    5 -> permissionId = (v as Long).toInt()
                }
            }
            return decodeParameter(type, typeUrl, permissionId, value)
        }

        private fun decodeParameter(type: Int, typeUrl: String, permissionId: Int, value: ByteArray): TronContract {
            val fields = mutableMapOf<Int, Any>()
            ProtoReader(value).forEachField { f, v -> fields[f] = v }
            fun bytesHex(f: Int): String? = (fields[f] as? ByteArray)?.toHex()
            fun long(f: Int): Long = fields[f] as? Long ?: 0L
            fun bigLong(f: Int): BigInteger = BigInteger.valueOf(long(f))
            val base = TronContract(type, typeUrl, permissionId, ownerAddress = "")
            return when (type) {
                TronContractType.TRANSFER -> base.copy(
                    ownerAddress = bytesHex(1).orEmpty(), toAddress = bytesHex(2), amount = bigLong(3),
                )
                TronContractType.TRANSFER_ASSET -> base.copy(
                    assetName = (fields[1] as? ByteArray)?.let { String(it, Charsets.UTF_8) },
                    ownerAddress = bytesHex(2).orEmpty(), toAddress = bytesHex(3), amount = bigLong(4),
                )
                TronContractType.TRIGGER_SMART_CONTRACT -> base.copy(
                    ownerAddress = bytesHex(1).orEmpty(), contractAddress = bytesHex(2), callValue = long(3),
                    callData = bytesHex(4).orEmpty(),
                )
                TronContractType.FREEZE_BALANCE_V2, TronContractType.UNFREEZE_BALANCE_V2 -> base.copy(
                    ownerAddress = bytesHex(1).orEmpty(), amount = bigLong(2), resource = long(3).toInt(),
                )
                TronContractType.DELEGATE_RESOURCE, TronContractType.UNDELEGATE_RESOURCE -> base.copy(
                    ownerAddress = bytesHex(1).orEmpty(), resource = long(2).toInt(), amount = bigLong(3),
                    toAddress = bytesHex(4),
                )
                // Every other contract type (incl. AccountPermissionUpdateContract, WithdrawExpireUnfreeze,
                // VoteWitness …) starts with owner_address = 1.
                else -> base.copy(ownerAddress = bytesHex(1).orEmpty())
            }
        }
    }
}

/** `protocol.Transaction.Contract.ContractType` values used by the wallet. */
object TronContractType {
    const val TRANSFER: Int = 1
    const val TRANSFER_ASSET: Int = 2
    const val TRIGGER_SMART_CONTRACT: Int = 31
    const val ACCOUNT_PERMISSION_UPDATE: Int = 46
    const val FREEZE_BALANCE_V2: Int = 54
    const val UNFREEZE_BALANCE_V2: Int = 55
    const val WITHDRAW_EXPIRE_UNFREEZE: Int = 56
    const val DELEGATE_RESOURCE: Int = 57
    const val UNDELEGATE_RESOURCE: Int = 58
}

/** Minimal protobuf wire-format reader (varint, 64-bit, length-delimited, 32-bit). */
internal class ProtoReader(private val bytes: ByteArray) {
    private var pos = 0

    /** Calls [block] with (field number, value): `Long` for varint / fixed, `ByteArray` for length-delimited. */
    fun forEachField(block: (Int, Any) -> Unit) {
        while (pos < bytes.size) {
            val key = readVarint()
            val field = (key ushr 3).toInt()
            require(field > 0) { "bad field" }
            when ((key and 7L).toInt()) {
                0 -> block(field, readVarint())
                1 -> block(field, readFixed(8))
                2 -> {
                    val len = readVarint()
                    require(len >= 0 && pos + len <= bytes.size) { "bad length" }
                    block(field, bytes.copyOfRange(pos, pos + len.toInt()))
                    pos += len.toInt()
                }
                5 -> block(field, readFixed(4))
                else -> throw IllegalArgumentException("unsupported wire type")
            }
        }
    }

    private fun readVarint(): Long {
        var result = 0L
        var shift = 0
        while (true) {
            require(pos < bytes.size && shift < 64) { "truncated varint" }
            val b = bytes[pos++].toInt() and 0xff
            result = result or ((b and 0x7f).toLong() shl shift)
            if (b and 0x80 == 0) return result
            shift += 7
        }
    }

    private fun readFixed(n: Int): Long {
        require(pos + n <= bytes.size) { "truncated fixed" }
        var result = 0L
        for (i in 0 until n) result = result or ((bytes[pos + i].toLong() and 0xff) shl (8 * i))
        pos += n
        return result
    }
}

/** TRON address helpers (base58check ↔ hex `41…`), pure Kotlin. */
object TronAddressCodec {
    /** `41…` hex (lower-case) of a base58 `T…` or hex address; `null` when invalid (bad checksum / length). */
    fun toHex41(address: String): String? {
        val a = address.trim()
        if (a.length == 42 && a.startsWith("41") && a.hexToBytesOrNull() != null) return a.lowercase()
        if (a.length == 44 && a.startsWith("0x41", ignoreCase = true)) return a.substring(2).lowercase()
        val decoded = Base58.decode(a) ?: return null
        if (decoded.size != 25) return null
        val payload = decoded.copyOfRange(0, 21)
        val checksum = sha256(sha256(payload)).copyOfRange(0, 4)
        if (!checksum.contentEquals(decoded.copyOfRange(21, 25)) || payload[0] != 0x41.toByte()) return null
        return payload.toHex()
    }

    /** Base58check `T…` form of a `41…` hex address; `null` when not 21 bytes. */
    fun toBase58(hex41: String): String? {
        val payload = hex41.hexToBytesOrNull()?.takeIf { it.size == 21 } ?: return null
        return Base58.encode(payload + sha256(sha256(payload)).copyOfRange(0, 4))
    }
}
