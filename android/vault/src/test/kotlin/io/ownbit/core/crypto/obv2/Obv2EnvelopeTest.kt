// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.crypto.obv2

import io.ownbit.core.crypto.kdf.Scrypt
import io.ownbit.core.crypto.kdf.ScryptParams
import io.ownbit.core.crypto.testing.FakeDeviceKeyManager
import io.ownbit.core.crypto.util.Hex
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.util.Base64

class Obv2EnvelopeTest {

    /** Cheap parameters for most tests; the default (N=32768) is covered by the iOS vector test. */
    private val fast = ScryptParams(n = 1024, r = 8, p = 1, dkLen = 32)
    /** BIP39 test vector ("abandon" × 11 + "about"). */
    private val mnemonic = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
    private val password = "correct horse battery staple"

    private fun envelope(keys: FakeDeviceKeyManager = FakeDeviceKeyManager()) =
        Obv2Envelope(keys, Scrypt.bouncyCastleOnly(Dispatchers.Default), Dispatchers.Default)

    private fun jsonOf(blob: String): JsonObject {
        assertTrue(blob.startsWith("OBV2:"))
        val raw = Base64.getDecoder().decode(blob.removePrefix("OBV2:")).toString(Charsets.UTF_8)
        return Json.parseToJsonElement(raw).jsonObject
    }

    private fun rebuild(blob: String, edit: (MutableMap<String, kotlinx.serialization.json.JsonElement>) -> Unit): String {
        val map = jsonOf(blob).toMutableMap()
        edit(map)
        return "OBV2:" + Base64.getEncoder().encodeToString(JsonObject(map).toString().toByteArray())
    }

    @Test
    fun roundTrip_deviceAndPortable() = runTest {
        val cipher = envelope()
        for (binding in Obv2Binding.entries) {
            val blob = cipher.encrypt(mnemonic, password.toCharArray(), binding, fast)
            assertTrue(Obv2Envelope.isObv2(blob))
            assertEquals(mnemonic, cipher.decryptToString(blob, password.toCharArray()))
            assertArrayEquals(mnemonic.toCharArray(), cipher.decryptToChars(blob, password.toCharArray()))
            assertTrue(cipher.verifyPassword(blob, password.toCharArray()))
        }
    }

    @Test
    fun envelopeJson_hasExactlyTheIosFields() = runTest {
        val cipher = envelope()
        val device = jsonOf(cipher.encrypt(mnemonic, password.toCharArray(), Obv2Binding.DEVICE, fast))
        assertEquals(
            setOf("v", "kdf", "n", "r", "p", "dklen", "salt", "bind", "dkfp", "cipher", "nonce", "ct", "tag"),
            device.keys,
        )
        assertEquals(2, device["v"]!!.jsonPrimitive.int)
        assertEquals("scrypt", device["kdf"]!!.jsonPrimitive.content)
        assertEquals("aes-256-gcm", device["cipher"]!!.jsonPrimitive.content)
        assertEquals("device", device["bind"]!!.jsonPrimitive.content)
        assertEquals(1024, device["n"]!!.jsonPrimitive.int)
        assertEquals(32, device["dklen"]!!.jsonPrimitive.int)
        assertEquals(32, device["salt"]!!.jsonPrimitive.content.length) // 16 bytes hex
        assertEquals(24, device["nonce"]!!.jsonPrimitive.content.length) // 12 bytes hex
        assertEquals(32, device["tag"]!!.jsonPrimitive.content.length) // 16 bytes hex
        assertEquals(16, device["dkfp"]!!.jsonPrimitive.content.length)
        assertEquals(mnemonic.length * 2, device["ct"]!!.jsonPrimitive.content.length)

        val portable = jsonOf(cipher.encrypt(mnemonic, password.toCharArray(), Obv2Binding.PORTABLE, fast))
        assertEquals("none", portable["bind"]!!.jsonPrimitive.content)
        assertFalse("dkfp is omitted, not null", "dkfp" in portable.keys)
    }

    @Test
    fun defaults_areIosParameters() = runTest {
        val blob = envelope().encrypt(mnemonic, password.toCharArray())
        val header = Obv2Envelope.header(blob)!!
        assertEquals(ScryptParams.WALLET_SECRET, header.params)
        assertEquals(Obv2Binding.DEVICE, header.binding)
    }

    @Test
    fun encryption_isRandomized() = runTest {
        val cipher = envelope()
        val a = cipher.encrypt(mnemonic, password.toCharArray(), Obv2Binding.DEVICE, fast)
        val b = cipher.encrypt(mnemonic, password.toCharArray(), Obv2Binding.DEVICE, fast)
        assertNotEquals(a, b)
        assertNotEquals(jsonOf(a)["salt"], jsonOf(b)["salt"])
        assertNotEquals(jsonOf(a)["nonce"], jsonOf(b)["nonce"])
    }

    @Test
    fun wrongPassword_returnsNull() = runTest {
        val cipher = envelope()
        for (binding in Obv2Binding.entries) {
            val blob = cipher.encrypt(mnemonic, password.toCharArray(), binding, fast)
            assertNull(cipher.decrypt(blob, "wrong".toCharArray()))
            assertEquals(Obv2DecryptResult.DecryptFailed, cipher.open(blob, "Correct horse battery staple".toCharArray()))
            assertEquals(Obv2DecryptResult.DecryptFailed, cipher.open(blob, CharArray(0)))
            assertFalse(cipher.verifyPassword(blob, "wrong".toCharArray()))
        }
    }

    @Test
    fun tamper_isDetected() = runTest {
        val cipher = envelope()
        for (binding in Obv2Binding.entries) {
            val blob = cipher.encrypt(mnemonic, password.toCharArray(), binding, fast)
            // iOS self-test style: flip a base64 character near the end.
            val chars = blob.toCharArray()
            chars[chars.size - 3] = if (chars[chars.size - 3] == 'A') 'B' else 'A'
            assertNull(cipher.decrypt(String(chars), password.toCharArray()))

            fun flipHex(field: String) = rebuild(blob) { map ->
                val hex = map[field]!!.jsonPrimitive.content
                val bytes = Hex.decode(hex)
                bytes[0] = (bytes[0].toInt() xor 1).toByte()
                map[field] = JsonPrimitive(Hex.encode(bytes))
            }
            for (field in listOf("ct", "tag", "nonce", "salt")) {
                assertEquals(field, Obv2DecryptResult.DecryptFailed, cipher.open(flipHex(field), password.toCharArray()))
            }
            // Downgrading the KDF cost changes the key -> GCM fails.
            val weaker = rebuild(blob) { it["n"] = JsonPrimitive(512) }
            assertEquals(Obv2DecryptResult.DecryptFailed, cipher.open(weaker, password.toCharArray()))
        }
    }

    @Test
    fun deviceBinding_missingKey_mismatchAndPortability() = runTest {
        val keys = FakeDeviceKeyManager()
        val cipher = envelope(keys)
        val device = cipher.encrypt(mnemonic, password.toCharArray(), Obv2Binding.DEVICE, fast)
        val portable = cipher.encrypt(mnemonic, password.toCharArray(), Obv2Binding.PORTABLE, fast)
        assertEquals(Obv2BindingStatus.OK, cipher.bindingStatus(device))
        assertEquals(Obv2BindingStatus.NOT_DEVICE_BOUND, cipher.bindingStatus(portable))
        assertEquals(Obv2BindingStatus.NOT_DEVICE_BOUND, cipher.bindingStatus("deadbeef"))
        assertEquals(Obv2BindingStatus.NOT_DEVICE_BOUND, cipher.bindingStatus(null))

        // "Another device": no key at all.
        val otherDevice = envelope(FakeDeviceKeyManager())
        val missing = otherDevice.open(device, password.toCharArray())
        assertEquals(Obv2DecryptResult.DeviceKeyUnavailable, missing)
        assertTrue(missing.needsRestore)
        assertEquals(Obv2BindingStatus.NEEDS_RESTORE, otherDevice.bindingStatus(device))
        // Portable envelopes open anywhere.
        assertEquals(mnemonic, otherDevice.decryptToString(portable, password.toCharArray()))

        // "Reinstalled": a different key exists.
        val replaced = envelope(FakeDeviceKeyManager(rawKey = ByteArray(32) { 9 }))
        assertEquals(Obv2DecryptResult.DeviceKeyMismatch, replaced.open(device, password.toCharArray()))
        assertEquals(Obv2BindingStatus.NEEDS_RESTORE, replaced.bindingStatus(device))

        // Broken keystore.
        keys.failing = true
        assertEquals(Obv2DecryptResult.DeviceKeyUnavailable, cipher.open(device, password.toCharArray()))
    }

    @Test
    fun decrypt_neverCreatesADeviceKey() = runTest {
        val keys = FakeDeviceKeyManager()
        val source = envelope()
        val blob = source.encrypt(mnemonic, password.toCharArray(), Obv2Binding.DEVICE, fast)
        envelope(keys).open(blob, password.toCharArray())
        assertNull(keys.rawKey)
        assertEquals(0, keys.created)
    }

    @Test
    fun deviceKeyWithoutFingerprint_stillOpens() = runTest {
        val keys = FakeDeviceKeyManager()
        val cipher = envelope(keys)
        val blob = cipher.encrypt(mnemonic, password.toCharArray(), Obv2Binding.DEVICE, fast)
        val noFp = rebuild(blob) { it.remove("dkfp") }
        assertEquals(mnemonic, cipher.decryptToString(noFp, password.toCharArray()))
        assertEquals(Obv2BindingStatus.OK, cipher.bindingStatus(noFp))
    }

    @Test
    fun parameters_areReadFromTheEnvelope() = runTest {
        val cipher = envelope()
        val custom = ScryptParams(n = 2048, r = 4, p = 2, dkLen = 32)
        val blob = cipher.encrypt(mnemonic, password.toCharArray(), Obv2Binding.DEVICE, custom)
        assertEquals(custom, Obv2Envelope.header(blob)!!.params)
        assertEquals(mnemonic, cipher.decryptToString(blob, password.toCharArray()))
    }

    @Test
    fun malformedEnvelopes_areRejected() = runTest {
        val cipher = envelope()
        val good = cipher.encrypt(mnemonic, password.toCharArray(), Obv2Binding.DEVICE, fast)
        val bad = listOf(
            "",
            "deadbeef",
            "OBV2:",
            "OBV2:!!!not-base64!!!",
            "OBV2:" + Base64.getEncoder().encodeToString("not json".toByteArray()),
            "OBV2:" + Base64.getEncoder().encodeToString("[]".toByteArray()),
            rebuild(good) { it["v"] = JsonPrimitive(3) },
            rebuild(good) { it["kdf"] = JsonPrimitive("pbkdf2") },
            rebuild(good) { it["cipher"] = JsonPrimitive("aes-128-ctr") },
            rebuild(good) { it["salt"] = JsonPrimitive("xyz") },
            rebuild(good) { it["nonce"] = JsonPrimitive("00") },
            rebuild(good) { it["tag"] = JsonPrimitive("0011") },
            rebuild(good) { it["n"] = JsonPrimitive(1000) },
            rebuild(good) { it["n"] = JsonPrimitive(1 shl 20) }, // 1 GiB of scrypt memory
            rebuild(good) { it.remove("ct") },
        )
        for (blob in bad) {
            assertEquals(blob, Obv2DecryptResult.BadEnvelope, cipher.open(blob, password.toCharArray()))
            assertNull(Obv2Envelope.header(blob))
        }
        assertFalse(Obv2Envelope.isObv2("deadbeef"))
        assertFalse(Obv2Envelope.isObv2(null))
    }

    @Test
    fun unknownJsonFields_areIgnored() = runTest {
        val cipher = envelope()
        val blob = cipher.encrypt(mnemonic, password.toCharArray(), Obv2Binding.PORTABLE, fast)
        val extended = rebuild(blob) { it["future"] = JsonPrimitive("x") }
        assertEquals(mnemonic, cipher.decryptToString(extended, password.toCharArray()))
    }

    @Test
    fun encrypt_rejectsEmptyPasswordAndBrokenKeystore() = runTest {
        try {
            envelope().encrypt(mnemonic, CharArray(0), Obv2Binding.DEVICE, fast)
            fail("expected Obv2Exception")
        } catch (e: Obv2Exception) {
            assertEquals(Obv2Exception.Reason.EMPTY_PASSWORD, e.reason)
        }
        try {
            envelope(FakeDeviceKeyManager(failing = true)).encrypt(mnemonic, password.toCharArray(), Obv2Binding.DEVICE, fast)
            fail("expected Obv2Exception")
        } catch (e: Obv2Exception) {
            assertEquals(Obv2Exception.Reason.DEVICE_KEY_UNAVAILABLE, e.reason)
        }
        // Portable does not need the device key.
        assertNotNull(envelope(FakeDeviceKeyManager(failing = true)).encrypt(mnemonic, password.toCharArray(), Obv2Binding.PORTABLE, fast))
    }

    @Test
    fun encryptVerified_selfChecks() = runTest {
        val cipher = envelope()
        val blob = cipher.encryptVerified(mnemonic, password.toCharArray(), Obv2Binding.DEVICE, fast)
        assertNotNull(blob)
        assertEquals(mnemonic, cipher.decryptToString(blob!!, password.toCharArray()))
        assertNull(cipher.encryptVerified("", password.toCharArray(), Obv2Binding.DEVICE, fast))
        assertNull(cipher.encryptVerified(mnemonic, CharArray(0), Obv2Binding.DEVICE, fast))
        // Keystore that can create but never read back (e.g. broken StrongBox): self-check must fail.
        val writeOnly = object : io.ownbit.core.crypto.keystore.DeviceKeyManager {
            val inner = FakeDeviceKeyManager()
            override fun peek() = null
            override fun getOrCreate() = inner.getOrCreate()
        }
        val broken = Obv2Envelope(writeOnly, Scrypt.bouncyCastleOnly(Dispatchers.Default), Dispatchers.Default)
        assertNull(broken.encryptVerified(mnemonic, password.toCharArray(), Obv2Binding.DEVICE, fast))
    }

    @Test
    fun unicodePlaintextAndPassword() = runTest {
        val cipher = envelope()
        val secret = "中文 Ünïcödé ελληνικά 🔑"
        val pwd = "密码Pässwörd!".toCharArray()
        val blob = cipher.encrypt(secret.toCharArray(), pwd, Obv2Binding.DEVICE, fast)
        assertEquals(secret, cipher.decryptToString(blob, "密码Pässwörd!".toCharArray()))
        // Not valid UTF-8 -> chars/string APIs return null, bytes API still works.
        val binary = byteArrayOf(0xC3.toByte(), 0x28)
        val binBlob = cipher.encrypt(binary, pwd, Obv2Binding.DEVICE, fast)
        assertArrayEquals(binary, cipher.decrypt(binBlob, pwd))
        assertNull(cipher.decryptToString(binBlob, pwd))
    }

    @Test
    fun opensEnvelopesProducedByTheIosCode() = runTest {
        // Produced with CryptoKit + JSONEncoder exactly as iOS WalletSecretCipher.encryptV2 (salt 000102…0f, N=1024,
        // nonce b0…bb, device key 1f1e…00); the plaintext is the BIP39 seed of the test vector.
        val iosDevice = "OBV2:eyJyIjo4LCJ0YWciOiIwMDZkMzIyYzlhMjVhYjVmOWNkODFkNGNhNjMwZjBiNyIsImRrZnAiOiI2OWM1NWM5MDAyZWI4YzdhIiwiYmluZCI6ImRldmljZSIsImRrbGVuIjozMiwibm9uY2UiOiJiMGIxYjJiM2I0YjViNmI3YjhiOWJhYmIiLCJwIjoxLCJjaXBoZXIiOiJhZXMtMjU2LWdjbSIsImN0IjoiNzAwMTg0NzY5Y2FlZTI5M2ViNWY2ZTg2YTk5NjE0OTg2YjFkOGM0YWE0NWM1ODc1ZTM0MGQ3MThkNWU3NWI5NzEwY2ZiMTAzN2UzMmJiNDFmN2VmMTkyNGJlZjViYWIwN2JiZjM4MTQ2YTkwYTBiNGRmNWYwYmE3NjFjMjI5NzlkNGZjNTM4OTE4NTZhZGM0NGRmYzU3MGI1NzVhMTE5ODg3YzI0N2I2ZjZjYjg2NzA5MmI4ZGM4YmFhZjNhY2FiZTEwMWM5MDVmZmZiZTM1Yzg2MWFiYzAyYWViMTYxNGZlZjNkNWI5NzJkODY4MjBjZjk0NGNmNTA4ZDQ0MDQ0OCIsInNhbHQiOiIwMDAxMDIwMzA0MDUwNjA3MDgwOTBhMGIwYzBkMGUwZiIsIm4iOjEwMjQsInYiOjIsImtkZiI6InNjcnlwdCJ9"

        val deviceKey = Hex.decode("1f1e1d1c1b1a191817161514131211100f0e0d0c0b0a09080706050403020100")
        val iosLikeKeystore = envelope(FakeDeviceKeyManager(rawKey = deviceKey, iosFingerprint = true))
        assertEquals(
            "5eb00bbddcf069084889a8ab9155568165f5c453ccb85e70811aaed6f6da5fc19a5ac40b389cd370d086206dec8aa6c43daea6690f20ad3d8d48b2d2ce9e38e4",
            iosLikeKeystore.decryptToString(iosDevice, "pässwörd-中文".toCharArray()),
        )
        // With the Android fingerprint scheme the same raw key is reported as a different device key.
        val androidScheme = envelope(FakeDeviceKeyManager(rawKey = deviceKey))
        assertEquals(Obv2DecryptResult.DeviceKeyMismatch, androidScheme.open(iosDevice, "pässwörd-中文".toCharArray()))
    }

    /**
     * The known-answer envelopes of the iOS package (`iOS/Tests/OwnbitCoreTests/Vault/WalletSecretCipherTests.swift`,
     * `testKnownAnswerVectors` and `testDecryptsEnvelopesWrittenByTheApp`): N = 32768, password "ownbit vault kat",
     * device key 2021…3f. Android opens both the portable and the device-bound ones (same AES key derivation).
     */
    @Test
    fun opensTheKnownAnswerEnvelopesOfTheIosPackage() = runTest {
        val katPassword = "ownbit vault kat"
        val iosDeviceKey = ByteArray(32) { (0x20 + it).toByte() }
        val ios = envelope(FakeDeviceKeyManager(rawKey = iosDeviceKey, iosFingerprint = true))
        val vectors = listOf(
            // fixed salt 000102…0f and nonce a0…ab (portable, device)
            "OBV2:eyJ0YWciOiIwYmQ2NDNkNTVmZjQxN2ZjMmJlYThmNDMyM2YxNjkxYyIsImtkZiI6InNjcnlwdCIsImRrbGVuIjozMiwic2FsdCI6IjAwMDEwMjAzMDQwNTA2MDcwODA5MGEwYjBjMGQwZTBmIiwiYmluZCI6Im5vbmUiLCJjdCI6IjA1YmZiN2VkYWZiM2ZkNDY1NjVhZmY1ZmYxMjBjODBiMmM5NGJhYjQ4MGI3OGJmMGIzYzY3OWJjYzNmYTI3NDlhMWYyMTE5M2I1Zjc2NDliNTU2Y2NlYmEzMTllMWY1ZjgxMGQ2ODRiNTYyZWY4Y2Y5NWIwNDA5MTU1ZDVhOGJhZDA3MmViNzJiYTdhYTg4OWQzMTVhMWMzNmU4ZjczN2ZlYjA4MWY5NWViN2IzODVjYmVkMjdkZmQxMyIsInAiOjEsImNpcGhlciI6ImFlcy0yNTYtZ2NtIiwibm9uY2UiOiJhMGExYTJhM2E0YTVhNmE3YThhOWFhYWIiLCJ2IjoyLCJyIjo4LCJuIjozMjc2OH0=",
            "OBV2:eyJka2ZwIjoiNzJkYmI3MzM2Yzc2NzgwMCIsInAiOjEsImJpbmQiOiJkZXZpY2UiLCJuIjozMjc2OCwibm9uY2UiOiJhMGExYTJhM2E0YTVhNmE3YThhOWFhYWIiLCJjaXBoZXIiOiJhZXMtMjU2LWdjbSIsImtkZiI6InNjcnlwdCIsImN0IjoiNDA5MDM2YjQ2YjhjNjQxNjcyNTg1NTM4Y2Y0YmFhMTA3YjA4NDJiMzBkZGEzYTZjNmQ0MjBmNTE0MDU4YWQ0NjFlNTU3ODBmOGIxM2EzZjA4MTE5OGJiODE1YjU3YThkYTg3YTFjNTAyNjY1MzdjNmIzMGVlMDcyMDc3YjJmOTBiZDRiODA5Y2YxMjI2ZjhlMDQwNTYxOGI1YTYyY2FkY2FjM2U2ZDJhZDY1MDMyYmIxOGI2ZjFhODY4IiwidGFnIjoiZDMyZDUwNjQ2ZDdkMGY2Nzg3ZDZmZWJmNTY3MjI5ZDEiLCJka2xlbiI6MzIsInNhbHQiOiIwMDAxMDIwMzA0MDUwNjA3MDgwOTBhMGIwYzBkMGUwZiIsInYiOjIsInIiOjh9",
            // written by the app's WalletSecretCipher.swift (random salt and nonce; portable, device)
            "OBV2:eyJ2IjoyLCJjdCI6ImExMThjODViMWU4NGVkMTA5ZDE3NjgwZTY5NjE3NGY1YTI1ZTcwYzYzZmMwODJmMzU2MjA5Y2UzNDRhNDQzMzc1ZDRlYjdkYTMyMTA0OTJkNWE5NmM4NzExZTg4YmEyZWVhMWM0ZThlMTk3Nzg5M2MwODRiMTY1ZjE4ODg3M2E0OWIyNzFiNjgzNGFiZmQ5NTg2ZjM3MzEwYTUyODFhN2YzNTRkMjYzOWFjNDMwYWM1M2Q3YTU3Y2UzZiIsInRhZyI6IjJhOWZhMTM4NmNkMTI0ODA2NDZkYTJlMDkxYmI2NTU4Iiwia2RmIjoic2NyeXB0IiwiZGtsZW4iOjMyLCJjaXBoZXIiOiJhZXMtMjU2LWdjbSIsInIiOjgsInAiOjEsInNhbHQiOiJlMzRlMmM1YzRjYTkyNjAyOTUwNDk3YzBhYjE1YzhkYiIsIm5vbmNlIjoiY2Q4ODIyMDVmMGRmNWJmNGQ2MmRhMTAxIiwibiI6MzI3NjgsImJpbmQiOiJub25lIn0=",
            "OBV2:eyJiaW5kIjoiZGV2aWNlIiwidiI6MiwicCI6MSwic2FsdCI6IjRjZTM1MTcyYjY3MTY1NjFmNzU1NjA0YzVjMDE0NTk2IiwiZGtsZW4iOjMyLCJjaXBoZXIiOiJhZXMtMjU2LWdjbSIsImtkZiI6InNjcnlwdCIsIm5vbmNlIjoiYWQyYmY5MDdiZDY4OWM0NGViNjNmNDNmIiwidGFnIjoiNmIwMjY5MTJmMmNmM2MyNjkxNjk0YjRkMjJmZDZjYTMiLCJjdCI6Ijc1Y2FiNmJiYjE3NzBlOGE2MzViN2FhZmRhM2VkNGYxNjU5YzdjOWE0Mzg2NTU4NzBlZGFlZmZiOTMzYzY5YzU3NzllOTUwNjA4ZDExMjA4OWRiYjU4NDM5NDUyZWNjMjc4NTgxMmE4MmFlNmY2M2I0NjNiZjQzMGQxOTU4YjM4MzhhZWM5OWU4ZDNjYzk5MzJhNDA4ODk1OTg2NjNmMmFkOTRmZDEzNDVhYjZmOTUwYzNhYjVkODc5YyIsImRrZnAiOiI3MmRiYjczMzZjNzY3ODAwIiwibiI6MzI3NjgsInIiOjh9",
        )
        for (blob in vectors) {
            assertEquals(mnemonic, ios.decryptToString(blob, katPassword.toCharArray()))
            assertEquals(Obv2DecryptResult.DecryptFailed, ios.open(blob, "ownbit vault KAT".toCharArray()))
        }
        assertEquals(Obv2BindingStatus.NOT_DEVICE_BOUND, ios.bindingStatus(vectors[0]))
        assertEquals(Obv2BindingStatus.OK, ios.bindingStatus(vectors[1]))
        // Another device (no key, or a different key) cannot open the device-bound ones; the portable ones open anywhere.
        assertEquals(Obv2DecryptResult.DeviceKeyUnavailable, envelope(FakeDeviceKeyManager()).open(vectors[1], katPassword.toCharArray()))
        assertEquals(mnemonic, envelope(FakeDeviceKeyManager()).decryptToString(vectors[2], katPassword.toCharArray()))
        assertEquals(Obv2BindingStatus.NEEDS_RESTORE, envelope(FakeDeviceKeyManager()).bindingStatus(vectors[3]))
    }
}
