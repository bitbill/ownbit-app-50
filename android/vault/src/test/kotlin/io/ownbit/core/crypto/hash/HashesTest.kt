// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.crypto.hash

import io.ownbit.core.crypto.util.Hex
import io.ownbit.core.crypto.util.SecureRandoms
import io.ownbit.core.crypto.util.Secrets
import io.ownbit.core.crypto.util.constantTimeEquals
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class HashesTest {

    @Test
    fun md5_knownVectors() {
        assertEquals("d41d8cd98f00b204e9800998ecf8427e", Hashes.md5Hex(""))
        assertEquals("900150983cd24fb0d6963f7d28e17f72", Hashes.md5Hex("abc"))
    }

    @Test
    fun md5_hashesUtf8() {
        // md5("中文") over UTF-8 bytes e4b8ad e69687
        assertEquals(Hashes.md5Hex(byteArrayOf(0xe4.toByte(), 0xb8.toByte(), 0xad.toByte(), 0xe6.toByte(), 0x96.toByte(), 0x87.toByte())), Hashes.md5Hex("中文"))
    }

    @Test
    fun sha256_knownVectors() {
        assertEquals("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", Hashes.sha256Hex(""))
        assertEquals("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", Hashes.sha256Hex("abc"))
    }

    @Test
    fun sha512_knownVector() {
        assertEquals(
            "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a" +
                "2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f",
            Hashes.sha512Hex("abc"),
        )
    }

    @Test
    fun keccak256_isEthereumKeccakNotSha3() {
        assertEquals("c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470", Hashes.keccak256Hex(""))
        assertEquals("4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45", Hashes.keccak256Hex("abc"))
    }

    @Test
    fun hmacSha256_rfc4231Case2() {
        val mac = Hashes.hmacSha256("Jefe".toByteArray(), "what do ya want for nothing?".toByteArray())
        assertEquals("5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843", Hex.encode(mac))
    }

    @Test
    fun hmacSha512_rfc4231Case2() {
        val mac = Hashes.hmacSha512("Jefe".toByteArray(), "what do ya want for nothing?".toByteArray())
        assertEquals(
            "164b7a7bfcf819e2e395fbe73b56e0a387bd64222e831fd610270cd7ea250554" +
                "9758bf75c05a994a6d034f65f8f0e6fdcaeab1a34d4a6b4b636e070a38bce737",
            Hex.encode(mac),
        )
    }

    @Test
    fun hmac_acceptsEmptyKey() {
        assertEquals(
            "b613679a0814d9ec772f95d778c35fc5ff1697c493715653c6c712144292c5ad",
            Hex.encode(Hashes.hmacSha256(ByteArray(0), ByteArray(0))),
        )
    }

    @Test
    fun hex_roundTripAndValidation() {
        val bytes = SecureRandoms.bytes(33)
        assertArrayEquals(bytes, Hex.decode(Hex.encode(bytes)))
        assertArrayEquals(byteArrayOf(0x0A, 0xBC.toByte()), Hex.decode("0aBC"))
        assertNull(Hex.decodeOrNull("abc"))
        assertNull(Hex.decodeOrNull("zz"))
        assertNull(Hex.decodeOrNull("0x00"))
        assertEquals("", Hex.encode(ByteArray(0)))
    }

    @Test
    fun constantTimeEquals_semantics() {
        assertTrue(constantTimeEquals(byteArrayOf(1, 2, 3), byteArrayOf(1, 2, 3)))
        assertFalse(constantTimeEquals(byteArrayOf(1, 2, 3), byteArrayOf(1, 2, 4)))
        assertFalse(constantTimeEquals(byteArrayOf(1, 2, 3), byteArrayOf(1, 2)))
        assertFalse(constantTimeEquals(byteArrayOf(), null))
        assertTrue(constantTimeEquals(null, null))
    }

    @Test
    fun secureRandomString_usesAlphabet() {
        val s = SecureRandoms.string(11)
        assertEquals(11, s.length)
        assertTrue(s.all { it in SecureRandoms.LOWER_ALPHANUMERIC })
    }

    @Test
    fun secrets_utf8RoundTripAndStrictDecode() {
        val chars = "pässwörd-中文-🔑".toCharArray()
        val bytes = Secrets.utf8(chars)
        assertArrayEquals("pässwörd-中文-🔑".toByteArray(Charsets.UTF_8), bytes)
        assertArrayEquals(chars, Secrets.utf8Chars(bytes))
        assertNull(Secrets.utf8Chars(byteArrayOf(0xC3.toByte())))
        // Lone surrogate: same replacement as String.toByteArray.
        val lone = charArrayOf('a', '\uD800')
        assertArrayEquals(String(lone).toByteArray(Charsets.UTF_8), Secrets.utf8(lone))
    }
}
