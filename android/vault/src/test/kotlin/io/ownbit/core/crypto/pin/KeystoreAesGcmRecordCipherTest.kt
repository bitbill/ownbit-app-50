// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.crypto.pin

import io.ownbit.core.crypto.util.SecureRandoms
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import java.security.GeneralSecurityException
import java.security.KeyStoreException
import java.security.ProviderException
import javax.crypto.SecretKey
import javax.crypto.spec.SecretKeySpec

/**
 * [KeystoreAesGcmRecordCipher] on the JVM, with a software key slot in place of the Android Keystore alias: the record
 * layout, both key policies of [RecordCiphers.keystoreAesGcm] — `replaceUnusableKey = true` (replace mode:
 * an unusable key is replaced once and the write retried, a missing key is created) and `false` (the quick-send
 * store: an existing key entry is never deleted or replaced by the cipher, and no key is created once the key worked
 * through the cipher — one cipher instance stands for one process) — and [RecordCipher.deleteKey]. The real Keystore
 * runs in `DeviceCryptoInstrumentedTest`.
 */
class KeystoreAesGcmRecordCipherTest {

    /** Software stand-in for one Keystore alias; counts generations and deletions. */
    private class SoftwareKeySlot : RecordKeySlot {
        var key: SecretKey? = null

        /** An entry that is not a secret key (e.g. a key pair under the alias): [peek] returns `null`. */
        var foreign = false
        var generates = 0
        var deletes = 0
        var generateFailure: Exception? = null
        var deleteFailure: Exception? = null
        var peekFailure: Exception? = null

        /**
         * The Keystore answers "no entry" while the key is there: on API 26–30 a failed binder call makes `getKey` /
         * `containsAlias` return `null` / `false` instead of throwing.
         */
        var unanswered = false

        override fun peek(): SecretKey? {
            peekFailure?.let { throw it }
            return if (foreign || unanswered) null else key
        }

        override fun isOccupied(): Boolean = !unanswered && (foreign || key != null)

        override fun generate(): SecretKey {
            generateFailure?.let { throw it }
            generates++
            foreign = false
            return SecretKeySpec(SecureRandoms.bytes(32), "AES").also { key = it }
        }

        override fun delete() {
            deleteFailure?.let { throw it }
            deletes++
            foreign = false
            key = null
        }

        /** A key the cipher cannot use (stands in for "invalid key blob" after an OEM Keystore reset). */
        fun breakKey() {
            key = SecretKeySpec(ByteArray(7), "AES")
        }
    }

    private val aad = "io.ownbit.test.v1".toByteArray(Charsets.US_ASCII)
    private val hello = "hello".toByteArray()

    private fun cipher(slot: RecordKeySlot, replaceUnusableKey: Boolean, aad: ByteArray = this.aad) =
        KeystoreAesGcmRecordCipher(aad, replaceUnusableKey, slot)

    @Test
    fun `layout, round trip, random IV and tamper detection`() {
        val slot = SoftwareKeySlot()
        val cipher = cipher(slot, replaceUnusableKey = false)
        val blob = cipher.encrypt(hello)
        assertEquals(1.toByte(), blob[0])
        assertEquals(12, blob[1].toInt())
        assertEquals(2 + 12 + hello.size + 16, blob.size)
        assertArrayEquals(hello, cipher.decrypt(blob))
        assertFalse(blob.contentEquals(cipher.encrypt(hello)))

        val tampered = blob.copyOf().also { it[it.size - 1] = (it[it.size - 1].toInt() xor 1).toByte() }
        assertThrows(GeneralSecurityException::class.java) { cipher.decrypt(tampered) }
        assertThrows(GeneralSecurityException::class.java) { cipher(slot, false, "other".toByteArray()).decrypt(blob) }
        assertThrows(GeneralSecurityException::class.java) { cipher.decrypt(byteArrayOf(2) + blob.copyOfRange(1, blob.size)) }
        assertThrows(GeneralSecurityException::class.java) { cipher.decrypt(blob.copyOf(20)) }
        assertThrows(GeneralSecurityException::class.java) { cipher.decrypt(byteArrayOf(1)) }
    }

    @Test
    fun `first use creates the key in both modes, decrypt never creates one`() {
        for (replace in listOf(true, false)) {
            val slot = SoftwareKeySlot()
            val cipher = cipher(slot, replace)
            val e = assertThrows(GeneralSecurityException::class.java) { cipher.decrypt(ByteArray(40).also { it[0] = 1; it[1] = 12 }) }
            assertEquals("record key missing", e.message)
            assertEquals(0, slot.generates)
            assertArrayEquals(hello, cipher.decrypt(cipher.encrypt(hello)))
            assertEquals(1, slot.generates)
            assertEquals(0, slot.deletes)
            cipher.encrypt(hello)
            assertEquals("the key is reused", 1, slot.generates)
        }
    }

    @Test
    fun `replace mode - an unusable key is replaced once and the write retried`() {
        val slot = SoftwareKeySlot().apply { breakKey() }
        val cipher = KeystoreAesGcmRecordCipher(aad, replaceUnusableKey = true, slot = slot)
        val blob = cipher.encrypt(hello)
        assertEquals(1, slot.deletes)
        assertEquals(1, slot.generates)
        assertArrayEquals(hello, cipher.decrypt(blob))

        // An entry that is not a secret key is overwritten too (the way out of a broken alias).
        val foreign = SoftwareKeySlot().apply { foreign = true }
        assertArrayEquals(hello, cipher(foreign, true).let { it.decrypt(it.encrypt(hello)) })
        assertEquals(1, foreign.generates)
    }

    @Test
    fun `replace mode - when the retry fails too it throws (still fail closed)`() {
        val slot = SoftwareKeySlot().apply { breakKey(); generateFailure = KeyStoreException("keystore") }
        assertThrows(GeneralSecurityException::class.java) { cipher(slot, true).encrypt(hello) }
        assertEquals(1, slot.deletes)
        val provider = SoftwareKeySlot().apply { breakKey(); generateFailure = ProviderException("keystore") }
        assertThrows(GeneralSecurityException::class.java) { cipher(provider, true).encrypt(hello) }
    }

    @Test
    fun `replaceUnusableKey false - an unusable key is kept and encrypt throws`() {
        val slot = SoftwareKeySlot().apply { breakKey() }
        val broken = slot.key
        assertThrows(GeneralSecurityException::class.java) { cipher(slot, false).encrypt(hello) }
        assertEquals(0, slot.deletes)
        assertEquals(0, slot.generates)
        assertSame(broken, slot.key)
    }

    @Test
    fun `replaceUnusableKey false - an entry that is not a secret key is never overwritten`() {
        val slot = SoftwareKeySlot().apply { foreign = true }
        val e = assertThrows(GeneralSecurityException::class.java) { cipher(slot, false).encrypt(hello) }
        assertEquals("record key unusable", e.message)
        assertEquals(0, slot.generates)
        assertTrue(slot.isOccupied())
    }

    @Test
    fun `replaceUnusableKey false - a Keystore failure is thrown and touches nothing`() {
        val slot = SoftwareKeySlot()
        val cipher = cipher(slot, false)
        val blob = cipher.encrypt(hello)
        val key = slot.key
        slot.peekFailure = ProviderException("keystore busy")
        assertThrows(GeneralSecurityException::class.java) { cipher.encrypt(hello) }
        assertThrows(GeneralSecurityException::class.java) { cipher.decrypt(blob) }
        slot.peekFailure = null
        assertSame(key, slot.key)
        assertEquals(0, slot.deletes)
        assertArrayEquals("readable again", hello, cipher.decrypt(blob))
    }

    @Test
    fun `replaceUnusableKey false - once the key encrypted, a key entry that is gone is never created again`() {
        val slot = SoftwareKeySlot()
        val cipher = cipher(slot, false)
        val blob = cipher.encrypt(hello)
        assertEquals(1, slot.generates)

        // The entry is removed while the app runs (a Keystore reset): no new key that no stored blob decrypts with.
        slot.key = null
        val e = assertThrows(GeneralSecurityException::class.java) { cipher.encrypt(hello) }
        assertEquals("record key missing after use", e.message)
        assertThrows(GeneralSecurityException::class.java) { cipher.encrypt(hello) }
        assertEquals("no key created", 1, slot.generates)
        assertFalse(slot.isOccupied())
        assertEquals("record key missing", assertThrows(GeneralSecurityException::class.java) { cipher.decrypt(blob) }.message)

        // The next process (a new cipher, the key has not worked there) creates one at its first encryption.
        val next = cipher(slot, false)
        assertArrayEquals(hello, next.decrypt(next.encrypt(hello)))
        assertEquals(2, slot.generates)
    }

    @Test
    fun `replaceUnusableKey false - a Keystore that answers no key for a live one never gets it overwritten (API 26-30)`() {
        val slot = SoftwareKeySlot()
        val cipher = cipher(slot, false)
        val blob = cipher.encrypt(hello)
        val key = slot.key

        slot.unanswered = true // getKey → null, containsAlias → false: looks like a missing key
        assertThrows(GeneralSecurityException::class.java) { cipher.encrypt(hello) }
        assertThrows(GeneralSecurityException::class.java) { cipher.decrypt(blob) }
        assertEquals(1, slot.generates)
        assertEquals(0, slot.deletes)

        slot.unanswered = false // the daemon answers again: the same key, every blob still decrypts
        assertSame(key, slot.key)
        assertArrayEquals(hello, cipher.decrypt(blob))
        assertArrayEquals(hello, cipher.decrypt(cipher.encrypt(hello)))
        assertEquals(1, slot.generates)
    }

    @Test
    fun `replaceUnusableKey false - a decryption alone makes the key count as working, a failed one does not`() {
        val slot = SoftwareKeySlot()
        val blob = cipher(slot, false).encrypt(hello) // an earlier process
        val key = slot.key

        // A process that only read: its decryption worked, so a key that reads as missing later is not replaced.
        val reader = cipher(slot, false)
        assertArrayEquals(hello, reader.decrypt(blob))
        slot.unanswered = true
        assertThrows(GeneralSecurityException::class.java) { reader.encrypt(hello) }
        assertEquals(1, slot.generates)
        slot.unanswered = false
        assertSame(key, slot.key)

        // A process whose calls all failed (a blob of another key, a tampered one): the key never worked there, so a
        // missing key is still created by its first encryption (nothing could be read without one).
        val other = cipher(SoftwareKeySlot(), false).encrypt(hello)
        val failing = cipher(slot, false)
        assertThrows(GeneralSecurityException::class.java) { failing.decrypt(other) }
        assertThrows(GeneralSecurityException::class.java) { failing.decrypt(blob.copyOf(blob.size - 1)) }
        slot.key = null
        assertArrayEquals(hello, failing.decrypt(failing.encrypt(hello)))
        assertEquals(2, slot.generates)
    }

    @Test
    fun `replaceUnusableKey false - only a successful deleteKey lets a key that worked be created again`() {
        val slot = SoftwareKeySlot()
        val cipher = cipher(slot, false)
        cipher.encrypt(hello)

        slot.deleteFailure = KeyStoreException("keystore")
        assertThrows(GeneralSecurityException::class.java) { cipher.deleteKey() }
        slot.deleteFailure = null
        slot.key = null // gone anyway
        assertThrows(GeneralSecurityException::class.java) { cipher.encrypt(hello) }
        assertEquals("a failed delete is no permission", 1, slot.generates)

        cipher.deleteKey() // the owner found every blob lost
        assertArrayEquals(hello, cipher.decrypt(cipher.encrypt(hello)))
        assertEquals(2, slot.generates)
        // The new key worked: from now on it is kept the same way.
        slot.key = null
        assertThrows(GeneralSecurityException::class.java) { cipher.encrypt(hello) }
        assertEquals(2, slot.generates)
    }

    @Test
    fun `replace mode - a key entry that is gone is created again, also after the key worked`() {
        val slot = SoftwareKeySlot()
        val cipher = cipher(slot, true)
        cipher.encrypt(hello)
        slot.key = null
        assertArrayEquals(hello, cipher.decrypt(cipher.encrypt(hello)))
        assertEquals(2, slot.generates)
        slot.unanswered = true
        cipher.encrypt(hello)
        assertEquals("replace mode: the Keystore's answer decides", 3, slot.generates)
    }

    @Test
    fun `deleteKey - old blobs never decrypt again, the next encrypt makes a new key`() {
        val slot = SoftwareKeySlot()
        val cipher = cipher(slot, false)
        val old = cipher.encrypt(hello)
        cipher.deleteKey()
        assertEquals(1, slot.deletes)
        assertFalse(slot.isOccupied())
        assertEquals("record key missing", assertThrows(GeneralSecurityException::class.java) { cipher.decrypt(old) }.message)
        val new = cipher.encrypt(hello)
        assertEquals(2, slot.generates)
        assertThrows(GeneralSecurityException::class.java) { cipher.decrypt(old) }
        assertArrayEquals(hello, cipher.decrypt(new))
        // Deleting an unusable key is how the owner gets out of it.
        slot.breakKey()
        assertThrows(GeneralSecurityException::class.java) { cipher.encrypt(hello) }
        cipher.deleteKey()
        assertArrayEquals(hello, cipher.decrypt(cipher.encrypt(hello)))
    }

    @Test
    fun `deleteKey failures surface as GeneralSecurityException`() {
        val keystore = SoftwareKeySlot().apply { deleteFailure = KeyStoreException("keystore") }
        assertThrows(GeneralSecurityException::class.java) { cipher(keystore, false).deleteKey() }
        val provider = SoftwareKeySlot().apply { deleteFailure = ProviderException("keystore") }
        assertThrows(GeneralSecurityException::class.java) { cipher(provider, false).deleteKey() }
    }

    @Test
    fun `factory - the default replaces an unusable key, the option keeps it`() {
        assertTrue((RecordCiphers.keystoreAesGcm("a", aad) as KeystoreAesGcmRecordCipher).replacesUnusableKey)
        assertFalse((RecordCiphers.keystoreAesGcm("a", aad, replaceUnusableKey = false) as KeystoreAesGcmRecordCipher).replacesUnusableKey)
        assertTrue("the plain constructor", KeystoreAesGcmRecordCipher("a", aad).replacesUnusableKey)
    }

    @Test
    fun `interface default - a cipher without a stored key has nothing to delete`() {
        val plain = object : RecordCipher {
            override fun encrypt(plaintext: ByteArray) = plaintext.copyOf()
            override fun decrypt(blob: ByteArray) = blob.copyOf()
        }
        plain.deleteKey()
        assertArrayEquals(hello, plain.decrypt(plain.encrypt(hello)))
    }
}
