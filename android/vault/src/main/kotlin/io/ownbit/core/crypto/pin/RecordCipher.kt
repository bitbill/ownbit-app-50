// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.crypto.pin

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.io.IOException
import java.security.GeneralSecurityException
import java.security.KeyStore
import java.security.ProviderException
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Authenticated encryption of a small record file. In this repository: the biometric quick-send file
 * (`io.ownbit.core.wallet.biometric.QuickSendRepository`); in the app the same facility also protects the PIN app-lock
 * store (this package's name) and a few other local records, which are not part of this repository. Implementations
 * must fail with [GeneralSecurityException]/[IOException] on tampering or a lost key.
 */
interface RecordCipher {
    fun encrypt(plaintext: ByteArray): ByteArray
    fun decrypt(blob: ByteArray): ByteArray

    /**
     * Deletes the key: no blob encrypted so far can ever be decrypted again, and the next [encrypt] starts with a new
     * key (also a cipher that never creates one once its key worked, [RecordCiphers.keystoreAesGcm]). Only for an owner
     * that found that none of its blobs decrypts any more (the key is lost). Throws [GeneralSecurityException] when the
     * key could not be deleted. A cipher without a stored key does nothing (this default); an implementation that
     * holds a stored key must override it.
     */
    fun deleteKey() {}
}

/** Public factory of the app's record ciphers (the Keystore implementation itself stays internal). */
object RecordCiphers {
    /**
     * A non-exportable Android Keystore AES-256-GCM key under [alias] (created on first use), [aad] bound as GCM
     * associated data. A lost / invalidated key makes old blobs undecryptable ([GeneralSecurityException]); callers
     * treat that as "no data".
     *
     * [replaceUnusableKey] `true` (a record that is always rewritten whole): [RecordCipher.encrypt] replaces a key it
     * cannot use and retries once; a missing key is created. `false` (the quick-send file): the cipher never replaces
     * the key its blobs were made with on its own — [RecordCipher.encrypt] never deletes or overwrites an existing key
     * entry (it throws), and once an encryption or a decryption with the key succeeded through this cipher it never
     * creates a key either: a key entry that reads as missing
     * afterwards — removed by a Keystore reset while the app runs, or a failed binder call on API 26–30, where
     * `getKey` / `containsAlias` answer `null` / `false` for a live key — fails the encryption instead of being
     * replaced by a new key that no other blob decrypts with. Before that (the first use, a lost key at start) a
     * missing key is created. The owner calls [RecordCipher.deleteKey] once it knows that none of its blobs can be
     * read any more; the next encryption then creates a new key. The owner keeps one such cipher per process (that
     * is what "worked" counts in).
     */
    fun keystoreAesGcm(alias: String, aad: ByteArray, replaceUnusableKey: Boolean = true): RecordCipher =
        KeystoreAesGcmRecordCipher(alias, aad.copyOf(), replaceUnusableKey)
}

/**
 * [RecordCipher] using a non-exportable Android Keystore AES-256-GCM key (TEE). File layout:
 * `[version=1][ivLength][iv][ciphertext||tag]`, with [aad] bound as GCM associated data. The key lives in [slot] (one
 * Keystore alias; a software slot in JVM tests).
 */
internal class KeystoreAesGcmRecordCipher(
    private val aad: ByteArray,
    private val replaceUnusableKey: Boolean,
    private val slot: RecordKeySlot,
) : RecordCipher {

    constructor(alias: String, aad: ByteArray, replaceUnusableKey: Boolean = true) :
        this(aad, replaceUnusableKey, AndroidKeystoreKeySlot(alias))

    /** Whether [encrypt] replaces a key it cannot use ([RecordCiphers.keystoreAesGcm]). */
    internal val replacesUnusableKey: Boolean get() = replaceUnusableKey

    private val lock = Any()

    /**
     * An encryption or a decryption with the stored key succeeded through this cipher (since it was made, or since
     * the last [deleteKey]). Without [replaceUnusableKey] no key is created from then on ([getOrCreateKey]).
     */
    @Volatile private var keyWorked = false

    /**
     * Encrypts with the Keystore key, creating it on first use. With [replaceUnusableKey], if the
     * existing key is unusable (e.g. "invalid key blob" after an OEM Keystore reset) the key is replaced once and the
     * encryption retried: the record is being rewritten anyway, and without this a broken key would make the record
     * permanently unwritable (no way out of the fail-closed state). If the retry fails too, the old file stays
     * unreadable, i.e. still fail closed. Without it, the failure is thrown and the key entry is left as it is.
     */
    override fun encrypt(plaintext: ByteArray): ByteArray = synchronized(lock) {
        val blob = try {
            guard { encryptWith(getOrCreateKey(), plaintext) }
        } catch (e: GeneralSecurityException) {
            if (!replaceUnusableKey) throw e
            guard {
                slot.delete()
                encryptWith(getOrCreateKey(), plaintext)
            }
        }
        keyWorked = true
        blob
    }

    private fun encryptWith(key: SecretKey, plaintext: ByteArray): ByteArray {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, key)
        cipher.updateAAD(aad)
        val body = cipher.doFinal(plaintext)
        val iv = cipher.iv
        return ByteArray(2 + iv.size + body.size).also {
            it[0] = FORMAT_VERSION
            it[1] = iv.size.toByte()
            iv.copyInto(it, 2)
            body.copyInto(it, 2 + iv.size)
        }
    }

    override fun decrypt(blob: ByteArray): ByteArray = guard {
        if (blob.size < 2 || blob[0] != FORMAT_VERSION) throw GeneralSecurityException("unknown record format")
        val ivLength = blob[1].toInt() and 0xFF
        if (ivLength !in 12..16 || blob.size < 2 + ivLength + TAG_BYTES) {
            throw GeneralSecurityException("truncated record")
        }
        val key = slot.peek() ?: throw GeneralSecurityException("record key missing")
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(TAG_BYTES * 8, blob, 2, ivLength))
        cipher.updateAAD(aad)
        cipher.doFinal(blob, 2 + ivLength, blob.size - 2 - ivLength).also { keyWorked = true }
    }

    override fun deleteKey() = synchronized(lock) {
        guard { slot.delete() }
        keyWorked = false
    }

    /**
     * The stored key, or a new one when the slot is empty. Without [replaceUnusableKey] no key is created once the key
     * worked through this cipher (an empty slot then means a removed key or a Keystore that did not answer, never a
     * first use), and an entry that is not an AES key is kept and this fails; with it (the way out of a broken key), an
     * empty slot always gets a new key and a foreign entry is overwritten.
     */
    private fun getOrCreateKey(): SecretKey = synchronized(lock) {
        slot.peek() ?: run {
            if (!replaceUnusableKey) {
                if (keyWorked) throw GeneralSecurityException("record key missing after use")
                if (slot.isOccupied()) throw GeneralSecurityException("record key unusable")
            }
            slot.generate()
        }
    }

    /** Maps provider/runtime keystore failures to [GeneralSecurityException] so callers see one type. */
    private inline fun <T> guard(block: () -> T): T = try {
        block()
    } catch (e: ProviderException) {
        throw GeneralSecurityException("keystore failure", e)
    } catch (e: IOException) {
        throw GeneralSecurityException("keystore failure", e)
    }

    private companion object {
        const val TRANSFORMATION = "AES/GCM/NoPadding"
        const val TAG_BYTES = 16
        const val FORMAT_VERSION: Byte = 1
    }
}

/** Where a [KeystoreAesGcmRecordCipher] keeps its key. Failures are thrown as the Keystore throws them. */
internal interface RecordKeySlot {
    /** The stored AES key; `null` when the slot holds none (nothing, or an entry that is not a secret key). */
    fun peek(): SecretKey?

    /** Whether the slot holds any entry, also one [peek] does not return. */
    fun isOccupied(): Boolean

    /** Generates a new AES-256-GCM key into the slot, replacing any entry, and returns it. */
    fun generate(): SecretKey

    /** Removes the slot's entry, if any. */
    fun delete()
}

/** One Android Keystore alias, non-exportable AES-256-GCM with randomized encryption. */
internal class AndroidKeystoreKeySlot(private val alias: String) : RecordKeySlot {

    private fun keyStore(): KeyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }

    override fun peek(): SecretKey? = keyStore().getKey(alias, null) as? SecretKey

    override fun isOccupied(): Boolean = keyStore().containsAlias(alias)

    override fun generate(): SecretKey =
        KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEYSTORE).run {
            init(
                KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .setKeySize(256)
                    .setRandomizedEncryptionRequired(true)
                    .build(),
            )
            generateKey()
        }

    override fun delete() {
        val keyStore = keyStore()
        if (keyStore.containsAlias(alias)) keyStore.deleteEntry(alias)
    }

    private companion object {
        const val ANDROID_KEYSTORE = "AndroidKeyStore"
    }
}
