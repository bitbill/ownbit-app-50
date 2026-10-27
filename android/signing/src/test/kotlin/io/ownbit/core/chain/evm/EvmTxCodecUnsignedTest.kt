// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.chain.evm

import org.junit.Test
import java.math.BigInteger
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull

/**
 * [EvmTxCodec.decodeUnsigned] (public protocol): the `signData` of an
 * `eth-sign-request`. Expected values come from ethers 6.17.0 (the library the public-protocol engine signs with:
 * `Transaction.from(…).unsignedSerialized` / `unsignedHash`); the type-2 and legacy digests are also the engine's
 * `signingBytesDigest` of the golden vectors `T8-flow-evm-eip1559` / `T8-flow-evm-legacy-eip155-bsc`.
 */
class EvmTxCodecUnsignedTest {

    @Test
    fun `EIP-1559 transaction of the golden vectors`() {
        val tx = EvmTxCodec.decodeUnsigned(hex(TYPE2))
        assertEquals(2, tx.type)
        assertEquals(1L, tx.chainId)
        assertEquals(BigInteger.ZERO, tx.nonce)
        assertNull(tx.gasPrice)
        assertEquals(BigInteger("1000000000"), tx.maxPriorityFeePerGas)
        assertEquals(BigInteger("2000000000"), tx.maxFeePerGas)
        assertEquals(BigInteger("2000000000"), tx.feePerGas)
        assertEquals(BigInteger.valueOf(21_000), tx.gasLimit)
        assertEquals("0x2222222222222222222222222222222222222222", tx.to)
        assertEquals(BigInteger.ONE, tx.value)
        assertEquals("0x", tx.dataHex)
        assertEquals(0, tx.accessListEntries)
        assertContentEquals(hex(TYPE2_HASH), tx.signingHash)
    }

    @Test
    fun `legacy EIP-155 transaction on BNB Smart Chain`() {
        val tx = EvmTxCodec.decodeUnsigned(hex(LEGACY_BSC))
        assertEquals(0, tx.type)
        assertEquals(56L, tx.chainId)
        assertEquals(BigInteger("1000000000"), tx.gasPrice)
        assertNull(tx.maxFeePerGas)
        assertEquals(BigInteger.valueOf(21_000), tx.gasLimit)
        assertContentEquals(hex(LEGACY_BSC_HASH), tx.signingHash)
    }

    @Test
    fun `legacy transaction with a two-byte chain id (HyperEVM 999)`() {
        val tx = EvmTxCodec.decodeUnsigned(hex(LEGACY_HYPE))
        assertEquals(999L, tx.chainId)
        assertContentEquals(hex(LEGACY_HYPE_HASH), tx.signingHash)
    }

    @Test
    fun `EIP-2930 transaction with an access list`() {
        val tx = EvmTxCodec.decodeUnsigned(hex(TYPE1))
        assertEquals(1, tx.type)
        assertEquals(56L, tx.chainId)
        assertEquals(BigInteger.valueOf(9), tx.nonce)
        assertEquals(BigInteger("3000000000"), tx.gasPrice)
        assertEquals(BigInteger.valueOf(60_000), tx.gasLimit)
        assertEquals("0x1111111111111111111111111111111111111111", tx.to)
        assertEquals(BigInteger.valueOf(5), tx.value)
        assertEquals("0xa9059cbb", tx.dataHex)
        assertEquals(1, tx.accessListEntries)
        assertContentEquals(hex(TYPE1_HASH), tx.signingHash)
    }

    @Test
    fun `contract creation has no recipient`() {
        val tx = EvmTxCodec.decodeUnsigned(hex(CREATE_ETC))
        assertEquals(61L, tx.chainId)
        assertNull(tx.to)
        assertEquals("0x6080604052", tx.dataHex)
        assertContentEquals(hex(CREATE_ETC_HASH), tx.signingHash)
    }

    @Test
    fun `signed, pre-EIP-155, blob and 7702 transactions are refused`() {
        // A signed legacy transaction (EIP-155 spec example): r and s are not zero.
        val signedLegacy = "f86c098504a817c800825208943535353535353535353535353535353535353535880de0b6b3a76400008025a028ef61340bd939bc2195fe537567866003e1a15d3c71ff63e1590620aa636276a067cbe9d8997f761aecb703304b3800ccf555c9f3dc64214b297fb1966a3b6d83"
        refused(signedLegacy, "already signed")
        // Pre-EIP-155: the 6-field legacy form (no chain id).
        refused("e080843b9aca0082520894" + "22".repeat(20) + "0180", "chain id")
        // Chain id 0 in the EIP-155 slot.
        refused("e380843b9aca0082520894" + "22".repeat(20) + "0180808080", "chain id")
        // Signed EIP-1559 transaction of the golden vectors (12 fields).
        refused(
            "02f86a0180843b9aca0084773594008252089422222222222222222222222222222222222222220180c080a09d23098d159bc90cdc19ded378c3fa30dd14e02071603a1f0f33887841ae0c4ea06e1701145900c62e3bf699be521fe500d6c19109a8b18fa573e682905e57d72d",
            "already signed",
        )
        refused("03" + TYPE2.substring(2), "unsupported transaction type 3")
        refused("04" + TYPE2.substring(2), "unsupported transaction type 4")
        refused("", "empty")
    }

    @Test
    fun `chain id bound - below 2^63 is accepted, 2^63 is refused`() {
        // TYPE2 with its one-byte chain id 01 replaced by an 8-byte one (list length e7 → ef).
        fun withChainId(hex8: String) = "02ef88$hex8" + TYPE2.substring(8)
        assertEquals(Long.MAX_VALUE, EvmTxCodec.decodeUnsigned(hex(withChainId("7fffffffffffffff"))).chainId)
        assertEquals(1L shl 62, EvmTxCodec.decodeUnsigned(hex(withChainId("4000000000000000"))).chainId)
        refused(withChainId("8000000000000000"), "chain id too large")
        // 2^64: a 9-byte chain id (list length f0).
        refused("02f089" + "01" + "00".repeat(8) + TYPE2.substring(8), "chain id too large")
    }

    @Test
    fun `non-canonical RLP, leading zeros and trailing bytes are refused`() {
        // Trailing byte after the list.
        refused(TYPE2 + "00", "trailing")
        // TYPE2 = 0x 02 e7 01 80 84… : the body after the list header starts at index 6, after the nonce at index 10.
        // The list length in long form although it is below 56 bytes: f8 27 instead of e7.
        refused("02f827" + TYPE2.substring(6), "non-canonical")
        // nonce 0 written as 81 00: a one-byte string below 0x80 must be the byte itself.
        refused("02e8018100" + TYPE2.substring(10), null)
        // nonce 7 with a leading zero byte (82 00 07).
        refused("02e901820007" + TYPE2.substring(10), "leading zero")
        // A 21-byte recipient.
        refused("02e80180843b9aca00847735940082520895" + "22".repeat(21) + "0180c0", "address")
    }

    @Test
    fun `every golden EVM transaction vector decodes to the engine's digest`() {
        for ((unsigned, digest) in listOf(TYPE2 to TYPE2_HASH, LEGACY_BSC to LEGACY_BSC_HASH, TYPE1 to TYPE1_HASH)) {
            assertContentEquals(hex(digest), EvmTxCodec.decodeUnsigned(hex(unsigned)).signingHash, unsigned)
        }
    }

    private fun refused(hexText: String, messagePart: String?) {
        val e = assertFailsWith<EvmTxCodec.DecodeException>(hexText) { EvmTxCodec.decodeUnsigned(hex(hexText)) }
        if (messagePart != null) {
            kotlin.test.assertTrue(messagePart in e.message.orEmpty(), "\"${e.message}\" should mention \"$messagePart\" ($hexText)")
        }
    }

    private fun hex(s: String): ByteArray = EvmHex.decode(if (s.startsWith("0x")) s else "0x$s") ?: error("bad hex $s")

    private companion object {
        const val TYPE2 = "0x02e70180843b9aca0084773594008252089422222222222222222222222222222222222222220180c0"
        const val TYPE2_HASH = "0x262c8a05d85c2095475edcc8fd0bee2f11aee8f90f6a5967107ded79974f6fe5"
        const val LEGACY_BSC = "0xe380843b9aca008252089422222222222222222222222222222222222222220180388080"
        const val LEGACY_BSC_HASH = "0xe5f220088849fe148dc9b56b6d4d4baa0187187a73a93c5465e04507078edfed"
        const val LEGACY_HYPE = "0xe1010182520894222222222222222222222222222222222222222280808203e78080"
        const val LEGACY_HYPE_HASH = "0x1830a758a650fba8e534d808249e45b0e5060cbc8991813550e997c22a91205c"
        const val TYPE1 =
            "0x01f85f380984b2d05e0082ea609411111111111111111111111111111111111111110584a9059cbbf838f7942222222222222222222222222222222222222222e1a00000000000000000000000000000000000000000000000000000000000000001"
        const val TYPE1_HASH = "0x5a2f83db0f061d3ed9a999fda50dc07776e491ba780b9256f1c733960a031b1a"
        const val CREATE_ETC = "0x02d13d030102830186a08080856080604052c0"
        const val CREATE_ETC_HASH = "0x405710b2b7131c2e005c3517956aac87aa0e8e9640ffa101220014dc0410cc4e"
    }
}
