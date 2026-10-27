// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.crypto.kdf

import io.ownbit.core.crypto.util.Hex
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ScryptTest {

    @Test
    fun bouncyCastle_rfc7914Vector1() {
        val out = BouncyCastleScryptEngine.derive(ByteArray(0), ByteArray(0), ScryptParams(16, 1, 1, 64))
        assertEquals(
            "77d6576238657b203b19ca42c18a0497f16b4844e3074ae8dfdffa3fede21442" +
                "fcd0069ded0948f8326a753a0fc81f17e8d3e0fb2e0d3628cf35e20c38d18906",
            Hex.encode(out),
        )
    }

    @Test
    fun bouncyCastle_rfc7914Vector3() {
        val out = BouncyCastleScryptEngine.derive(
            "pleaseletmein".toByteArray(),
            "SodiumChloride".toByteArray(),
            ScryptParams(16384, 8, 1, 64),
        )
        assertEquals(
            "7023bdcb3afd7348461c06cd81fd38ebfda8fbba904f8e3ea9b543f6545da1f2" +
                "d5432955613f0fcf62d49705242a9af9e61e85dc0d651e40dfcf017b45575887",
            Hex.encode(out),
        )
    }

    @Test
    fun bouncyCastle_rfc7914Vector2_isTheKnownAnswerTest() {
        val out = BouncyCastleScryptEngine.derive("password".toByteArray(), "NaCl".toByteArray(), ScryptParams(1024, 8, 16, 64))
        assertEquals(
            "fdbabe1c9d3472007856e7190d01e9fe7c6ad7cbc8237830e77376634b373162" +
                "2eaf30d92e22a3886ff109279d9830dac727afb94a83ee6d8360cbdfa2cc0640",
            Hex.encode(out),
        )
        assertTrue(Scrypt.passesKnownAnswerTest(BouncyCastleScryptEngine))
    }

    @Test
    fun walletSecretParams_matchPythonHashlib() {
        // python: hashlib.scrypt(b'correct horse battery staple', salt=bytes(range(16)), n=32768, r=8, p=1, dklen=32)
        val out = BouncyCastleScryptEngine.derive(
            "correct horse battery staple".toByteArray(),
            Hex.decode("000102030405060708090a0b0c0d0e0f"),
            ScryptParams.WALLET_SECRET,
        )
        assertEquals("7a8e34241db898d59175c696538c417467a975ffe569068425f16188d3159c58", Hex.encode(out))
    }

    @Test
    fun facade_fallsBackWhenPrimaryCannotLoad() = runTest {
        val broken = object : ScryptEngine {
            override val name = "broken"
            override fun derive(password: ByteArray, salt: ByteArray, params: ScryptParams): ByteArray =
                throw UnsatisfiedLinkError("no libsodium")
        }
        val scrypt = Scrypt(broken, BouncyCastleScryptEngine)
        val out = scrypt.derive("password".toByteArray(), "NaCl".toByteArray(), ScryptParams(1024, 8, 16, 64))
        assertTrue(Hex.encode(out).startsWith("fdbabe1c"))
        assertEquals("bouncycastle", scrypt.activeEngineName)
    }

    @Test
    fun facade_disablesPrimaryThatFailsKnownAnswerTest() {
        var calls = 0
        val wrong = object : ScryptEngine {
            override val name = "wrong"
            override fun derive(password: ByteArray, salt: ByteArray, params: ScryptParams): ByteArray {
                calls++
                return ByteArray(params.dkLen) { 7 }
            }
        }
        val scrypt = Scrypt(wrong, BouncyCastleScryptEngine)
        val out = scrypt.deriveBlocking(ByteArray(0), ByteArray(0), ScryptParams(16, 1, 1, 64))
        assertTrue(Hex.encode(out).startsWith("77d65762"))
        assertEquals(1, calls) // only the self-test ran
        scrypt.deriveBlocking(ByteArray(0), ByteArray(0), ScryptParams(16, 1, 1, 64))
        assertEquals(1, calls)
    }

    @Test
    fun facade_usesHealthyPrimary() {
        var calls = 0
        val healthy = object : ScryptEngine {
            override val name = "healthy"
            override fun derive(password: ByteArray, salt: ByteArray, params: ScryptParams): ByteArray {
                calls++
                return BouncyCastleScryptEngine.derive(password, salt, params)
            }
        }
        val scrypt = Scrypt(healthy, BouncyCastleScryptEngine)
        scrypt.deriveBlocking(ByteArray(0), ByteArray(0), ScryptParams(16, 1, 1, 64))
        assertEquals(2, calls) // self-test + real call
        assertEquals("healthy", scrypt.activeEngineName)
    }

    @Test
    fun params_validation() {
        assertTrue(ScryptParams.isAcceptable(32768, 8, 1, 32))
        assertTrue(ScryptParams.isAcceptable(262144, 8, 1, 32)) // 256 MiB: the upper bound
        assertFalse(ScryptParams.isAcceptable(524288, 8, 1, 32))
        assertFalse(ScryptParams.isAcceptable(1000, 8, 1, 32)) // not a power of two
        assertFalse(ScryptParams.isAcceptable(1, 8, 1, 32))
        assertFalse(ScryptParams.isAcceptable(1024, 0, 1, 32))
        assertFalse(ScryptParams.isAcceptable(1024, 8, 0, 32))
        assertFalse(ScryptParams.isAcceptable(1024, 8, 1, 0))
        assertFalse(ScryptParams.isAcceptable(1024, 8, 1, 65))
        assertFalse(ScryptParams.isAcceptable(1024, 8, 17, 32))
    }
}
