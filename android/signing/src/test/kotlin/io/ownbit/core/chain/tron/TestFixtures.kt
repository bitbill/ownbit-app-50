// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.chain.tron

import java.io.ByteArrayOutputStream
import java.math.BigInteger

/** Builds TronWeb-shaped transaction JSON with a real protobuf `raw_data_hex` and a consistent `txID`. */
internal object TronTx {
    const val OWNER = "TUEZSdKsoDHQMeZwihtdoBiN46zxhGWYdH"
    const val OWNER_HEX = "41c8599111f29c1e1e061265b4af93ea1f274ad78a"
    const val TO = "TL9gR3f4FgNa9VZAsPt6xuKXPrfWAUJ5MW"
    const val USDT = "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t"
    const val TIMESTAMP = 1_758_800_000_000L
    const val EXTENDED_EXPIRATION = TIMESTAMP + 60_000 + 82_800_000

    fun transfer(
        from: String = OWNER,
        to: String = TO,
        amount: Long,
        expiration: Long = EXTENDED_EXPIRATION,
        data: ByteArray? = null,
    ): String {
        val value = bytesField(1, hex(from)) + bytesField(2, hex(to)) + varintField(3, amount)
        return json(raw(1, "protocol.TransferContract", value, expiration, data = data))
    }

    fun trc10(from: String = OWNER, to: String = TO, tokenId: String, amount: Long): String {
        val value = bytesField(1, tokenId.toByteArray()) + bytesField(2, hex(from)) + bytesField(3, hex(to)) + varintField(4, amount)
        return json(raw(2, "protocol.TransferAssetContract", value, EXTENDED_EXPIRATION))
    }

    fun trc20(from: String = OWNER, to: String = TO, contract: String = USDT, amount: BigInteger, feeLimit: Long = 150_000_000): String {
        val data = TronTransactionVerifier.trc20TransferData(TronAddressCodec.toHex41(to)!!, amount).hexToBytesOrNull()!!
        val value = bytesField(1, hex(from)) + bytesField(2, hex(contract)) + bytesField(4, data)
        return json(raw(31, "protocol.TriggerSmartContract", value, EXTENDED_EXPIRATION, feeLimit = feeLimit))
    }

    /** `approve(spender, amount)` on [contract] as TronWeb builds it for `preSendTx` type 20. */
    fun approve(from: String = OWNER, spender: String = TO, contract: String = USDT, amount: BigInteger = BigInteger.ZERO, feeLimit: Long = 150_000_000): String {
        val data = TronTransactionVerifier.trc20ApproveData(TronAddressCodec.toHex41(spender)!!, amount).hexToBytesOrNull()!!
        val value = bytesField(1, hex(from)) + bytesField(2, hex(contract)) + bytesField(4, data)
        return json(raw(31, "protocol.TriggerSmartContract", value, EXTENDED_EXPIRATION, feeLimit = feeLimit))
    }

    fun staking(type: Int, name: String, owner: String = OWNER, amount: Long = 0, resource: Int = 0, receiver: String? = null): String {
        val value = when (type) {
            54, 55 -> bytesField(1, hex(owner)) + varintField(2, amount) + varintField(3, resource.toLong())
            57, 58 -> bytesField(1, hex(owner)) + varintField(2, resource.toLong()) + varintField(3, amount) + bytesField(4, hex(receiver!!))
            else -> bytesField(1, hex(owner))
        }
        return json(raw(type, "protocol.$name", value, TIMESTAMP + 60_000))
    }

    fun permissionUpdate(owner: String = OWNER): String =
        json(raw(46, "protocol.AccountPermissionUpdateContract", bytesField(1, hex(owner)), TIMESTAMP + 60_000))

    fun rawHexOf(json: String): String = TronTransactionJson.parse(json)!!.rawDataHex

    private fun raw(type: Int, name: String, value: ByteArray, expiration: Long, feeLimit: Long = 0, data: ByteArray? = null): ByteArray {
        val any = bytesField(1, "type.googleapis.com/$name".toByteArray()) + bytesField(2, value)
        val contract = varintField(1, type.toLong()) + bytesField(2, any)
        var raw = bytesField(1, byteArrayOf(0x12, 0x34)) + bytesField(4, ByteArray(8) { it.toByte() }) +
            varintField(8, expiration)
        if (data != null) raw += bytesField(10, data)
        raw += bytesField(11, contract) + varintField(14, TIMESTAMP)
        if (feeLimit > 0) raw += varintField(18, feeLimit)
        return raw
    }

    private fun json(raw: ByteArray): String {
        val hex = raw.toHex()
        val txId = sha256(raw).toHex()
        return """{"visible":false,"txID":"$txId","raw_data":{"contract":[{"type":"X"}],"expiration":1},"raw_data_hex":"$hex"}"""
    }

    fun signed(unsignedJson: String, signature: String = "ab".repeat(65)): String =
        unsignedJson.removeSuffix("}") + ""","signature":["$signature"]}"""

    private fun hex(address: String): ByteArray = TronAddressCodec.toHex41(address)!!.hexToBytesOrNull()!!

    private fun varint(v: Long): ByteArray {
        val out = ByteArrayOutputStream()
        var x = v
        while (true) {
            if (x and 0x7fL.inv() == 0L) { out.write(x.toInt()); break }
            out.write(((x and 0x7f) or 0x80).toInt())
            x = x ushr 7
        }
        return out.toByteArray()
    }

    private fun varintField(field: Int, v: Long) = varint((field shl 3).toLong()) + varint(v)
    private fun bytesField(field: Int, b: ByteArray) = varint(((field shl 3) or 2).toLong()) + varint(b.size.toLong()) + b
}
