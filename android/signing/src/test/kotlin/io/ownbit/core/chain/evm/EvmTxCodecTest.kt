// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.chain.evm

import org.junit.Test
import java.math.BigInteger
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull

class EvmTxCodecTest {

    @Test
    fun `EIP-155 specification example decodes and recovers its sender`() {
        // EIP-155 example: nonce 9, gasPrice 20 gwei, gas 21000, to 0x3535…, value 1 ETH, chainId 1,
        // private key 0x4646…46 → 0x9d8A62f656a8d1615C1294fd71e9CFb3E4855A4F.
        val raw = "0xf86c098504a817c800825208943535353535353535353535353535353535353535880de0b6b3a76400008025a028ef61340bd939bc2195fe537567866003e1a15d3c71ff63e1590620aa636276a067cbe9d8997f761aecb703304b3800ccf555c9f3dc64214b297fb1966a3b6d83"
        val tx = EvmTxCodec.decodeSigned(raw)
        assertEquals(0, tx.type)
        assertEquals(1L, tx.chainId)
        assertEquals(BigInteger.valueOf(9), tx.nonce)
        assertEquals(BigInteger("20000000000"), tx.gasPrice)
        assertEquals(BigInteger.valueOf(21000), tx.gasLimit)
        assertEquals("0x3535353535353535353535353535353535353535", tx.to)
        assertEquals(BigInteger("1000000000000000000"), tx.value)
        assertEquals("0x", tx.dataHex)
        assertEquals("0x9d8A62f656a8d1615C1294fd71e9CFb3E4855A4F", tx.from)
    }

    @Test
    fun `legacy ETH vector of the bundle`() {
        val tx = EvmTxCodec.decodeSigned(EvmVectors.LEGACY_ETH_RAW)
        assertEquals(EvmVectors.LEGACY_ETH_HASH, tx.hash)
        assertEquals(0, tx.type)
        assertEquals(1L, tx.chainId)
        assertEquals(BigInteger.valueOf(7), tx.nonce)
        assertEquals(BigInteger("20000000000"), tx.gasPrice)
        assertEquals(BigInteger.valueOf(21000), tx.gasLimit)
        assertEquals(EvmVectors.ADDRESS1.lowercase(), tx.to)
        assertEquals(BigInteger("1000000000000000"), tx.value)
        assertEquals("0x", tx.dataHex)
        assertEquals(EvmVectors.ADDRESS0, tx.from)
    }

    @Test
    fun `legacy BSC vector with calldata carries chain id 56`() {
        val tx = EvmTxCodec.decodeSigned(EvmVectors.LEGACY_BSC_DATA_RAW)
        assertEquals(EvmVectors.LEGACY_BSC_DATA_HASH, tx.hash)
        assertEquals(56L, tx.chainId)
        assertEquals("0x68656c6c6f", tx.dataHex)
        assertEquals(BigInteger.valueOf(25600), tx.gasLimit)
        assertEquals(EvmVectors.ADDRESS0, tx.from)
    }

    @Test
    fun `legacy ERC20 vector is a transfer to the token contract`() {
        val tx = EvmTxCodec.decodeSigned(EvmVectors.LEGACY_TOKEN_RAW)
        assertEquals(EvmVectors.LEGACY_TOKEN_HASH, tx.hash)
        assertEquals(EvmVectors.USDT.lowercase(), tx.to)
        assertEquals(BigInteger.ZERO, tx.value)
        assertEquals(
            "0xa9059cbb" + EvmHex.addressWord(EvmVectors.ADDRESS1) + EvmHex.uintWord(BigInteger.valueOf(1_500_000)),
            tx.dataHex,
        )
        assertEquals(BigInteger.valueOf(8), tx.nonce)
        assertEquals(EvmVectors.ADDRESS0, tx.from)
    }

    @Test
    fun `ETC vector has chain id 61`() {
        val tx = EvmTxCodec.decodeSigned(EvmVectors.ETC_RAW)
        assertEquals(EvmVectors.ETC_HASH, tx.hash)
        assertEquals(61L, tx.chainId)
        assertEquals(BigInteger.valueOf(50000), tx.gasLimit)
        assertEquals(EvmVectors.ADDRESS0, tx.from)
    }

    @Test
    fun `EIP-1559 ETH vector`() {
        val tx = EvmTxCodec.decodeSigned(EvmVectors.EIP1559_ETH_RAW)
        assertEquals(EvmVectors.EIP1559_ETH_HASH, tx.hash)
        assertEquals(2, tx.type)
        assertEquals(1L, tx.chainId)
        assertEquals(BigInteger.valueOf(9), tx.nonce)
        assertEquals(BigInteger("30000000000"), tx.gasPrice)
        assertEquals(BigInteger("1500000000"), tx.maxPriorityFeePerGas)
        assertEquals(BigInteger.valueOf(25600), tx.gasLimit)
        assertEquals(EvmVectors.ADDRESS1.lowercase(), tx.to)
        assertEquals(BigInteger("1000000000000000"), tx.value)
        assertEquals(EvmVectors.ADDRESS0, tx.from)
    }

    @Test
    fun `EIP-1559 BASE vector with calldata`() {
        val tx = EvmTxCodec.decodeSigned(EvmVectors.EIP1559_BASE_DATA_RAW)
        assertEquals(EvmVectors.EIP1559_BASE_DATA_HASH, tx.hash)
        assertEquals(8453L, tx.chainId)
        assertEquals("0x68656c6c6f", tx.dataHex)
        assertEquals(EvmVectors.ADDRESS0, tx.from)
    }

    @Test
    fun `EIP-1559 ERC20 vector`() {
        val tx = EvmTxCodec.decodeSigned(EvmVectors.EIP1559_TOKEN_RAW)
        assertEquals(EvmVectors.EIP1559_TOKEN_HASH, tx.hash)
        assertEquals(2, tx.type)
        assertEquals(BigInteger.valueOf(10), tx.nonce)
        assertEquals(EvmVectors.USDT.lowercase(), tx.to)
        assertEquals(EvmVectors.ADDRESS0, tx.from)
    }

    @Test
    fun `typed data v4 signature recovers ETH account 0`() {
        val digest = EvmHex.decode(EvmVectors.TYPED_DATA_DIGEST)!!
        assertEquals(EvmVectors.ADDRESS0, EvmTxCodec.recoverSigner(digest, EvmVectors.TYPED_DATA_SIG))
    }

    @Test
    fun `personal_sign signatures (v 0 or 1) recover ETH account 0`() {
        val text = EvmTxCodec.personalMessageDigest("Hello Ownbit".toByteArray())
        assertEquals(EvmVectors.ADDRESS0, EvmTxCodec.recoverSigner(text, EvmVectors.PERSONAL_SIG))
        // A 0x… message is signed as bytes by the legacy bundle.
        val bytes = EvmTxCodec.personalMessageDigest(EvmHex.decode("0x48656c6c6f")!!)
        assertEquals(EvmVectors.ADDRESS0, EvmTxCodec.recoverSigner(bytes, EvmVectors.PERSONAL_HEX_SIG))
    }

    @Test
    fun `broken signatures and bytes are rejected`() {
        assertNull(EvmTxCodec.recoverSigner(ByteArray(32), "0x1234"))
        assertFailsWith<EvmTxCodec.DecodeException> { EvmTxCodec.decodeSigned("0x03aa") }
        assertFailsWith<EvmTxCodec.DecodeException> { EvmTxCodec.decodeSigned(EvmVectors.LEGACY_ETH_RAW + "00") }
        assertFailsWith<EvmTxCodec.DecodeException> { EvmTxCodec.decodeSigned("zz") }
    }

    @Test
    fun `rlp round trip`() {
        val items = listOf(
            EvmTxCodec.rlpEncodeUInt(BigInteger.ZERO),
            EvmTxCodec.rlpEncodeUInt(BigInteger.valueOf(0x7f)),
            EvmTxCodec.rlpEncodeUInt(BigInteger.valueOf(0x80)),
            EvmTxCodec.rlpEncodeBytes(ByteArray(60) { it.toByte() }),
        )
        val list = EvmTxCodec.rlpEncodeList(items)
        val decoded = EvmTxCodec.rlpDecode(list) as EvmTxCodec.RlpItem.Items
        assertEquals(4, decoded.items.size)
        assertContentEquals(ByteArray(0), (decoded.items[0] as EvmTxCodec.RlpItem.Bytes).bytes)
        assertContentEquals(byteArrayOf(0x7f), (decoded.items[1] as EvmTxCodec.RlpItem.Bytes).bytes)
        assertContentEquals(byteArrayOf(0x80.toByte()), (decoded.items[2] as EvmTxCodec.RlpItem.Bytes).bytes)
        assertContentEquals(ByteArray(60) { it.toByte() }, (decoded.items[3] as EvmTxCodec.RlpItem.Bytes).bytes)
        assertContentEquals(list, decoded.encoded)
    }
}
