// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.crypto

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import io.ownbit.core.crypto.kdf.BouncyCastleScryptEngine
import io.ownbit.core.crypto.kdf.Scrypt
import io.ownbit.core.crypto.kdf.ScryptParams
import io.ownbit.core.crypto.kdf.SodiumScryptEngine
import io.ownbit.core.crypto.keystore.AndroidKeystoreDeviceKeyManager
import io.ownbit.core.crypto.obv2.Obv2Binding
import io.ownbit.core.crypto.obv2.Obv2BindingStatus
import io.ownbit.core.crypto.obv2.Obv2DecryptResult
import io.ownbit.core.crypto.obv2.Obv2Envelope
import io.ownbit.core.crypto.pin.KeystoreAesGcmRecordCipher
import io.ownbit.core.crypto.pin.RecordCipher
import io.ownbit.core.crypto.pin.RecordCiphers
import io.ownbit.core.crypto.util.Hex
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import org.junit.runner.RunWith
import java.security.GeneralSecurityException
import java.security.KeyPairGenerator
import java.security.KeyStore
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey

/**
 * On-device checks of the parts JVM unit tests cannot reach: libsodium through JNA, the Android Keystore device key
 * and the Keystore record cipher. Run with `./gradlew :vault:connectedDebugAndroidTest` on a device or emulator.
 */
@RunWith(AndroidJUnit4::class)
class DeviceCryptoInstrumentedTest {

    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Test
    fun libsodiumScrypt_matchesRfc7914AndBouncyCastle() {
        val sodium = SodiumScryptEngine()
        val rfc = sodium.derive("password".toByteArray(), "NaCl".toByteArray(), ScryptParams(1024, 8, 16, 64))
        assertEquals(
            "fdbabe1c9d3472007856e7190d01e9fe7c6ad7cbc8237830e77376634b373162" +
                "2eaf30d92e22a3886ff109279d9830dac727afb94a83ee6d8360cbdfa2cc0640",
            Hex.encode(rfc),
        )
        val salt = Hex.decode("000102030405060708090a0b0c0d0e0f")
        val pwd = "correct horse battery staple".toByteArray()
        assertArrayEquals(
            BouncyCastleScryptEngine.derive(pwd, salt, ScryptParams.WALLET_SECRET),
            sodium.derive(pwd, salt, ScryptParams.WALLET_SECRET),
        )
    }

    @Test
    fun productionScrypt_usesLibsodium() = runTest {
        val scrypt = Scrypt.nativeWithFallback()
        scrypt.derive("x".toByteArray(), ByteArray(16), ScryptParams(1024, 8, 1, 32))
        assertEquals("libsodium", scrypt.activeEngineName)
    }

    @Test
    fun keystoreDeviceKey_isStableAndNotRecreated() {
        val manager = AndroidKeystoreDeviceKeyManager()
        val key = manager.getOrCreate()
        val again = manager.peek()
        assertNotNull(again)
        val mac1 = key.hmacSha256("m".toByteArray())
        assertEquals(32, mac1.size)
        assertArrayEquals(mac1, again!!.hmacSha256("m".toByteArray()))
        assertEquals(key.fingerprint(), again.fingerprint())
        assertEquals(16, key.fingerprint().length)
    }

    @Test
    fun obv2_withRealKeystore() = runTest {
        val envelope = Obv2Envelope(AndroidKeystoreDeviceKeyManager(), Scrypt.nativeWithFallback(), Dispatchers.Default)
        val mnemonic = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
        val blob = envelope.encryptVerified(mnemonic, "Passw0rd!".toCharArray())
        assertNotNull(blob)
        assertEquals(mnemonic, envelope.decryptToString(blob!!, "Passw0rd!".toCharArray()))
        assertEquals(Obv2DecryptResult.DecryptFailed, envelope.open(blob, "passw0rd!".toCharArray()))
        assertEquals(Obv2BindingStatus.OK, envelope.bindingStatus(blob))
        val portable = envelope.encrypt(mnemonic, "Passw0rd!".toCharArray(), Obv2Binding.PORTABLE)
        assertEquals(Obv2BindingStatus.NOT_DEVICE_BOUND, envelope.bindingStatus(portable))
    }

    @Test
    fun keystoreRecordCipher_roundTripAndTamper() {
        val cipher = KeystoreAesGcmRecordCipher("ownbit_test_record_key", "aad".toByteArray())
        val blob = cipher.encrypt("hello".toByteArray())
        assertArrayEquals("hello".toByteArray(), cipher.decrypt(blob))
        blob[blob.size - 1] = (blob[blob.size - 1].toInt() xor 1).toByte()
        try {
            cipher.decrypt(blob)
            fail("tamper not detected")
        } catch (e: GeneralSecurityException) {
            // expected
        }
    }

    @Test
    fun keystoreRecordCipher_replacesUnusableKey() {
        val alias = "ownbit_test_record_key_unusable"
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        if (keyStore.containsAlias(alias)) keyStore.deleteEntry(alias)
        // An HMAC key under the alias cannot do AES-GCM: stands in for a corrupted / invalid key blob.
        KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_HMAC_SHA256, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_SIGN).build())
        }.generateKey()
        val cipher = KeystoreAesGcmRecordCipher(alias, "aad".toByteArray())
        val blob = cipher.encrypt("hello".toByteArray())
        assertArrayEquals("hello".toByteArray(), cipher.decrypt(blob))
        keyStore.deleteEntry(alias)
    }

    /** `replaceUnusableKey = false` (the password-strength store): the cipher never deletes or overwrites the entry. */
    @Test
    fun keystoreRecordCipher_keepsUnusableKeyWhenNotReplacing() {
        val alias = "ownbit_test_record_key_kept"
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        if (keyStore.containsAlias(alias)) keyStore.deleteEntry(alias)
        val cipher = RecordCiphers.keystoreAesGcm(alias, "aad".toByteArray(), replaceUnusableKey = false)
        try {
            KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_HMAC_SHA256, "AndroidKeyStore").apply {
                init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_SIGN).build())
            }.generateKey()
            assertEncryptRefused(cipher)
            assertEquals(KeyProperties.KEY_ALGORITHM_HMAC_SHA256, (keyStore.getKey(alias, null) as SecretKey).algorithm)

            // An entry that is not a secret key at all is not overwritten either.
            keyStore.deleteEntry(alias)
            KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, "AndroidKeyStore").apply {
                initialize(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_SIGN).setDigests(KeyProperties.DIGEST_SHA256).build())
            }.generateKeyPair()
            assertEncryptRefused(cipher)
            assertTrue(keyStore.entryInstanceOf(alias, KeyStore.PrivateKeyEntry::class.java))

            // Only the owner deletes it; the next encryption then creates a new AES key.
            cipher.deleteKey()
            assertFalse(keyStore.containsAlias(alias))
            val blob = cipher.encrypt("hello".toByteArray())
            assertArrayEquals("hello".toByteArray(), cipher.decrypt(blob))
            cipher.deleteKey()
            assertFalse(keyStore.containsAlias(alias))
        } finally {
            if (keyStore.containsAlias(alias)) keyStore.deleteEntry(alias)
        }
    }

    /**
     * `replaceUnusableKey = false`: once the key worked through the cipher, an entry
     * removed from the Keystore (a reset while the app runs) is not created again by it — only by a new cipher (the
     * next process) or after `deleteKey`. The replace-mode default still creates it.
     */
    @Test
    fun keystoreRecordCipher_noNewKeyOnceItWorkedWhenNotReplacing() {
        val alias = "ownbit_test_record_key_worked"
        val hello = "hello".toByteArray()
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        if (keyStore.containsAlias(alias)) keyStore.deleteEntry(alias)
        try {
            val cipher = RecordCiphers.keystoreAesGcm(alias, "aad".toByteArray(), replaceUnusableKey = false)
            val blob = cipher.encrypt(hello)
            keyStore.deleteEntry(alias)
            assertEncryptRefused(cipher)
            assertFalse("no key created where the key worked", keyStore.containsAlias(alias))

            // The next process creates one at its first encryption; the old blob stays unreadable.
            val next = RecordCiphers.keystoreAesGcm(alias, "aad".toByteArray(), replaceUnusableKey = false)
            assertArrayEquals(hello, next.decrypt(next.encrypt(hello)))
            assertTrue(keyStore.containsAlias(alias))
            try {
                next.decrypt(blob)
                fail("a blob of the removed key decrypted")
            } catch (e: GeneralSecurityException) {
                // expected
            }

            // The owner's deleteKey lets the first cipher create a key again.
            keyStore.deleteEntry(alias)
            cipher.deleteKey()
            assertArrayEquals(hello, cipher.decrypt(cipher.encrypt(hello)))

            // The replace-mode default: the same cipher creates a removed entry again.
            keyStore.deleteEntry(alias)
            val pin = KeystoreAesGcmRecordCipher(alias, "aad".toByteArray())
            pin.encrypt(hello)
            keyStore.deleteEntry(alias)
            assertArrayEquals(hello, pin.decrypt(pin.encrypt(hello)))
            assertTrue(keyStore.containsAlias(alias))
        } finally {
            if (keyStore.containsAlias(alias)) keyStore.deleteEntry(alias)
        }
    }

    private fun assertEncryptRefused(cipher: RecordCipher) {
        try {
            cipher.encrypt("hello".toByteArray())
            fail("an unusable key was used or replaced")
        } catch (e: GeneralSecurityException) {
            // expected
        }
    }
}
