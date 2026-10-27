// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.chain.evm

import io.ownbit.core.model.coin.ErcType
import org.junit.Test
import java.math.BigDecimal
import java.math.BigInteger
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class EvmHexAndNetworkTest {

    @Test
    fun `custom data validation follows iOS ETHTransactionBuilder validate`() {
        assertTrue(EvmHex.isValidCustomData("0xabcd"))
        assertTrue(EvmHex.isValidCustomData("ABCD"))
        assertTrue(EvmHex.isValidCustomData("0xA9059CBB"))
        assertFalse(EvmHex.isValidCustomData("0x"))
        assertFalse(EvmHex.isValidCustomData("abc"))
        assertFalse(EvmHex.isValidCustomData("0xabc"))
        assertFalse(EvmHex.isValidCustomData("0xzz"))
        assertFalse(EvmHex.isValidCustomData("hello"))
    }

    @Test
    fun `calldata is lower-cased and prefixed like iOS customData0x`() {
        assertEquals("", EvmHex.normalizeCalldata(null))
        assertEquals("", EvmHex.normalizeCalldata(""))
        assertEquals("", EvmHex.normalizeCalldata("0x"))
        assertEquals("0xabcd", EvmHex.normalizeCalldata("ABCD"))
        assertEquals("0xabcd", EvmHex.normalizeCalldata("0xAbCd"))
    }

    @Test
    fun `hex quantities match iOS toHexStringWith0x and hexStringToDecimal`() {
        assertEquals("0x0", EvmHex.toHex0x(BigInteger.ZERO))
        assertEquals("0xde0b6b3a7640000", EvmHex.toHex0x(BigInteger("1000000000000000000")))
        assertEquals(BigInteger("1000000000000000000"), EvmHex.parseHexQuantity("0xDE0B6B3A7640000"))
        assertEquals(BigInteger.valueOf(0x5208), EvmHex.parseHexQuantity("5208"))
        assertEquals(BigInteger.ZERO, EvmHex.parseHexQuantity(""))
        assertEquals(BigInteger.ZERO, EvmHex.parseHexQuantity("0x"))
        assertNull(EvmHex.parseHexQuantity("0xg1"))
    }

    @Test
    fun `address checks use EIP-55`() {
        assertTrue(EvmHex.isAddress("0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed"))
        assertTrue(EvmHex.isAddress("0x5aaeb6053f3e94c9b9a09f33669435e7ef1beaed"))
        assertTrue(EvmHex.isAddress("0x5AAEB6053F3E94C9B9A09F33669435E7EF1BEAED"))
        assertFalse(EvmHex.isAddress("0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAeD"))
        assertFalse(EvmHex.isAddress("5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed"))
        assertFalse(EvmHex.isAddress("0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeA"))
        assertEquals(EvmVectors.ADDRESS0, EvmHex.toChecksumAddress(EvmVectors.ADDRESS0.lowercase()))
    }

    @Test
    fun `amount conversions truncate like NumberFormatter down`() {
        assertEquals(BigInteger("1500000"), EvmHex.toMinor(BigDecimal("1.5"), 6))
        assertEquals(BigInteger("1234567"), EvmHex.toMinor(BigDecimal("1.2345679"), 6))
        assertEquals(BigDecimal("0.001"), EvmHex.fromMinor(BigInteger("1000000000000000"), 18))
        assertEquals(BigDecimal.ZERO, EvmHex.fromMinor(BigInteger.ZERO, 18))
        assertEquals(BigDecimal("30"), EvmHex.weiToGwei(BigInteger("30000000000")))
    }

    @Test
    fun `networks carry the iOS chain ids`() {
        val expected = mapOf(
            EvmNetwork.ETH to 1L, EvmNetwork.BSC to 56L, EvmNetwork.ETC to 61L, EvmNetwork.POLYGON to 137L,
            EvmNetwork.ARB to 42161L, EvmNetwork.OP to 10L, EvmNetwork.BASE to 8453L, EvmNetwork.HYPE to 999L,
        )
        for ((network, id) in expected) {
            assertEquals(id, network.chainId, network.name)
            assertEquals(network, EvmNetwork.ofChainId(id))
        }
        assertEquals(EvmNetwork.entries.toSet(), expected.keys)
        assertNull(EvmNetwork.ofChainId(43114))
        assertTrue(EvmNetwork.ETC.isEtc)
        assertFalse(EvmNetwork.ETH.isEtc)
    }

    @Test
    fun `legacy NFT token ids become a 32-byte word`() {
        assertEquals("0x" + "0".repeat(62) + "4d", EvmJsSigner.legacyTokenIdWord("77"))
        assertEquals("0x" + "0".repeat(62) + "4d", EvmJsSigner.legacyTokenIdWord("0x4d"))
        assertEquals("not-a-number", EvmJsSigner.legacyTokenIdWord("not-a-number"))
    }

    @Test
    fun `NFT ids parse like ethers BigNumber`() {
        assertEquals(BigInteger.valueOf(77), EvmHex.parseTokenId("77"))
        assertEquals(BigInteger.valueOf(77), EvmHex.parseTokenId("0x4D"))
        assertNull(EvmHex.parseTokenId(""))
        assertNull(EvmHex.parseTokenId("0x"))
        assertNull(EvmHex.parseTokenId("-1"))
        assertNull(EvmHex.parseTokenId("seven"))
    }

    @Test
    fun `token transfer calldata equals what both bundles encode`() {
        val id = "77"
        val a0 = EvmVectors.ADDRESS0
        val a1 = EvmVectors.ADDRESS1
        fun data(raw: String) = EvmTxCodec.decodeSigned(raw).dataHex
        assertEquals(data(EvmVectors.EIP1559_TOKEN_RAW), EvmHex.tokenTransferData(ErcType.ERC20, a0, a1, BigInteger.valueOf(1_500_000), "", legacyBundle = false))
        assertEquals(data(EvmVectors.LEGACY_TOKEN_RAW), EvmHex.tokenTransferData(ErcType.ERC20, a0, a1, BigInteger.valueOf(1_500_000), "", legacyBundle = true))
        assertEquals(data(EvmVectors.EIP1559_721_RAW), EvmHex.tokenTransferData(ErcType.ERC721, a0, a1, BigInteger.ONE, id, legacyBundle = false))
        assertEquals(data(EvmVectors.LEGACY_721_RAW), EvmHex.tokenTransferData(ErcType.ERC721, a0, a1, BigInteger.ONE, id, legacyBundle = true))
        assertEquals(data(EvmVectors.EIP1559_1155_RAW), EvmHex.tokenTransferData(ErcType.ERC1155, a0, a1, BigInteger.valueOf(5), id, legacyBundle = false))
        // The legacy bundle appends one more zero word after the empty `bytes`.
        assertEquals(data(EvmVectors.LEGACY_1155_RAW), EvmHex.tokenTransferData(ErcType.ERC1155, a0, a1, BigInteger.valueOf(5), id, legacyBundle = true))
        assertNull(EvmHex.tokenTransferData(ErcType.ERC721, a0, a1, BigInteger.ONE, "x", legacyBundle = false))
        // All four NFT vectors are signed by ETH #0.
        for (raw in listOf(EvmVectors.EIP1559_721_RAW, EvmVectors.EIP1559_1155_RAW, EvmVectors.LEGACY_721_RAW, EvmVectors.LEGACY_1155_RAW)) {
            assertEquals(a0, EvmTxCodec.decodeSigned(raw).from)
        }
    }

    @Test
    fun `ethTxType decision is iOS if-equal-2`() {
        assertTrue(EvmTxType.usesEip1559(2, EvmNetwork.ETH))
        assertFalse(EvmTxType.usesEip1559(1, EvmNetwork.ETH))
        assertFalse(EvmTxType.usesEip1559(0, EvmNetwork.BSC))
        assertFalse(EvmTxType.usesEip1559(2, EvmNetwork.ETC))
    }
}
