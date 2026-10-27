// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.wallet.testing

import io.ownbit.core.crypto.biometric.BiometricAvailability
import io.ownbit.core.crypto.biometric.BiometricCapability
import io.ownbit.core.crypto.biometric.BiometricCapabilityChecker
import io.ownbit.core.crypto.biometric.BiometricKeyStore
import io.ownbit.core.crypto.biometric.BiometricStatus
import io.ownbit.core.crypto.biometric.CipherResult
import io.ownbit.core.crypto.biometric.KeySecurityLevel
import io.ownbit.core.crypto.biometric.KeyVerdict
import io.ownbit.core.crypto.pin.RecordCipher
import io.ownbit.core.crypto.util.MonotonicClock
import io.ownbit.core.crypto.util.SecureRandoms
import io.ownbit.core.crypto.util.WallClock
import java.nio.ByteBuffer
import java.security.AlgorithmParameters
import java.security.GeneralSecurityException
import java.security.Key
import java.security.Provider
import java.security.ProviderException
import java.security.SecureRandom
import java.security.spec.AlgorithmParameterSpec
import javax.crypto.Cipher
import javax.crypto.CipherSpi
import javax.crypto.IllegalBlockSizeException
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * Software stand-in for the Android Keystore auth-per-use keys: AES-256-GCM keys in memory whose ciphers **refuse every
 * data operation until a prompt "authenticated" them** ([authenticate] grants exactly one operation — auth-per-use),
 * like `IllegalBlockSizeException` caused by "Key user not authenticated" on a device.
 */
internal class FakeBiometricKeyStore : BiometricKeyStore {
    /** Verdict of the next [create] (a reject leaves nothing behind, like the real store). */
    var verdict: KeyVerdict = KeyVerdict.Accept(KeySecurityLevel.TEE)

    /** Answer of the negative probe. */
    var refuses = true

    /** [encryptCipher] / [decryptCipher] fail like a transient Keystore error. */
    var failInit = false

    val keys = LinkedHashMap<String, ByteArray>()
    private val invalidated = HashSet<String>()
    val created = ArrayList<String>()
    val deleted = ArrayList<String>()

    /** Lets the next unauthenticated-key operation through (a successful crypto-bound prompt). */
    fun authenticate() {
        Gate.tokens++
    }

    /** Enrolment changed / screen lock removed: the key exists but can never be used again. */
    fun invalidate(alias: String) {
        invalidated += alias
    }

    /** Keystore reset: every key gone. */
    fun wipeAll() {
        keys.clear()
    }

    override fun create(alias: String): KeyVerdict {
        delete(alias)
        val v = verdict
        if (v is KeyVerdict.Accept) {
            keys[alias] = SecureRandoms.bytes(32)
            created += alias
        }
        return v
    }

    override fun refusesUnauthenticatedUse(alias: String): Boolean = alias in keys && refuses

    override fun encryptCipher(alias: String): CipherResult = cipher(alias) { key ->
        Cipher.getInstance(TRANSFORMATION, PROVIDER).apply { init(Cipher.ENCRYPT_MODE, key) }
    }

    override fun decryptCipher(alias: String, iv: ByteArray): CipherResult = cipher(alias) { key ->
        Cipher.getInstance(TRANSFORMATION, PROVIDER).apply { init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, iv)) }
    }

    override fun delete(alias: String) {
        if (keys.remove(alias) != null) deleted += alias
        invalidated -= alias
    }

    override fun exists(alias: String): Boolean = alias in keys

    /**
     * Runs once at the next [aliases] call, after the list was taken and before it is returned (interleaves another
     * operation with a sweep that has just listed the keys).
     */
    var afterAliasesListed: (() -> Unit)? = null

    override fun aliases(prefix: String): List<String> {
        val listed = keys.keys.filter { it.startsWith(prefix) }
        afterAliasesListed?.let { hook ->
            afterAliasesListed = null
            hook()
        }
        return listed
    }

    private inline fun cipher(alias: String, make: (SecretKeySpec) -> Cipher): CipherResult {
        if (failInit) return CipherResult.Failed(ProviderException("keystore busy"))
        if (alias in invalidated) return CipherResult.Invalidated
        val raw = keys[alias] ?: return CipherResult.Missing
        return CipherResult.Ready(make(SecretKeySpec(raw, "AES")))
    }

    /** Per-process gate shared with [GatedAesGcmSpi] (the JCA instantiates the SPI by reflection). */
    object Gate {
        @Volatile var tokens: Int = 0
    }

    companion object {
        const val TRANSFORMATION = "AES/GCM/NoPadding"
        val PROVIDER: Provider = GatedProvider()
    }
}

/** JCA provider of [GatedAesGcmSpi] (OpenJDK does not require signed providers). */
@Suppress("DEPRECATION")
internal class GatedProvider : Provider("OwnbitFakeKeystore", 1.0, "auth-per-use AES-GCM for tests") {
    init {
        put("Cipher.AES/GCM/NoPadding", GatedAesGcmSpi::class.java.name)
    }
}

/**
 * AES-GCM whose first data operation (AAD, update or doFinal) consumes one [FakeBiometricKeyStore.Gate] token; without
 * a token it throws like an unauthenticated Keystore operation.
 */
class GatedAesGcmSpi : CipherSpi() {
    private val inner: Cipher = Cipher.getInstance("AES/GCM/NoPadding")
    private var authorized = false

    private fun gate() {
        if (authorized) return
        if (FakeBiometricKeyStore.Gate.tokens <= 0) throw IllegalBlockSizeException("Key user not authenticated")
        FakeBiometricKeyStore.Gate.tokens--
        authorized = true
    }

    override fun engineSetMode(mode: String?) = Unit
    override fun engineSetPadding(padding: String?) = Unit
    override fun engineGetBlockSize(): Int = 16
    override fun engineGetOutputSize(inputLen: Int): Int = inner.getOutputSize(inputLen)
    override fun engineGetIV(): ByteArray? = inner.iv
    override fun engineGetParameters(): AlgorithmParameters? = inner.parameters

    override fun engineInit(opmode: Int, key: Key, random: SecureRandom?) {
        authorized = false
        inner.init(opmode, key)
    }

    override fun engineInit(opmode: Int, key: Key, params: AlgorithmParameterSpec?, random: SecureRandom?) {
        authorized = false
        inner.init(opmode, key, params)
    }

    override fun engineInit(opmode: Int, key: Key, params: AlgorithmParameters?, random: SecureRandom?) {
        authorized = false
        inner.init(opmode, key, params)
    }

    override fun engineUpdateAAD(src: ByteArray, offset: Int, len: Int) {
        try {
            gate()
        } catch (e: IllegalBlockSizeException) {
            throw ProviderException("Key user not authenticated", e)
        }
        inner.updateAAD(src, offset, len)
    }

    override fun engineUpdateAAD(src: ByteBuffer) {
        val bytes = ByteArray(src.remaining()).also { src.get(it) }
        engineUpdateAAD(bytes, 0, bytes.size)
    }

    override fun engineUpdate(input: ByteArray, inputOffset: Int, inputLen: Int): ByteArray? {
        try {
            gate()
        } catch (e: IllegalBlockSizeException) {
            throw ProviderException("Key user not authenticated", e)
        }
        return inner.update(input, inputOffset, inputLen)
    }

    override fun engineUpdate(input: ByteArray, inputOffset: Int, inputLen: Int, output: ByteArray, outputOffset: Int): Int {
        try {
            gate()
        } catch (e: IllegalBlockSizeException) {
            throw ProviderException("Key user not authenticated", e)
        }
        return inner.update(input, inputOffset, inputLen, output, outputOffset)
    }

    override fun engineDoFinal(input: ByteArray?, inputOffset: Int, inputLen: Int): ByteArray {
        gate()
        return inner.doFinal(input ?: ByteArray(0), inputOffset, inputLen)
    }

    override fun engineDoFinal(input: ByteArray?, inputOffset: Int, inputLen: Int, output: ByteArray, outputOffset: Int): Int {
        gate()
        return inner.doFinal(input ?: ByteArray(0), inputOffset, inputLen, output, outputOffset)
    }
}

/** Mutable capability answer. */
internal class FakeCapabilityChecker(var status: BiometricStatus = STRONG_HW) : BiometricCapabilityChecker {
    var refreshes = 0

    override suspend fun status(): BiometricStatus = status

    override fun refresh() {
        refreshes++
    }

    companion object {
        val STRONG_HW = BiometricStatus(
            BiometricCapability.STRONG_HW,
            BiometricAvailability.AVAILABLE,
            BiometricAvailability.AVAILABLE,
            KeySecurityLevel.TEE,
        )
        val WEAK_ONLY = BiometricStatus(
            BiometricCapability.WEAK_ONLY,
            BiometricAvailability.AVAILABLE,
            BiometricAvailability.NONE_ENROLLED,
            null,
        )
    }
}

/** Wall + monotonic clock under test control. */
internal class TestClocks(var now: Long = 1_760_000_000_000L, var elapsed: Long = 10_000L) : WallClock, MonotonicClock {
    override fun nowMillis(): Long = now
    override fun elapsedMillis(): Long = elapsed

    fun advance(millis: Long) {
        now += millis
        elapsed += millis
    }
}

/** AES-GCM record cipher with an in-memory key; [broken] fails like a lost Keystore record key. */
internal class TestRecordCipher(private var key: ByteArray = SecureRandoms.bytes(32)) : RecordCipher {
    var broken = false
    var failWrites = false
    var keyDeletes = 0

    override fun encrypt(plaintext: ByteArray): ByteArray {
        if (broken || failWrites) throw GeneralSecurityException("key lost")
        val iv = SecureRandoms.bytes(12)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(128, iv))
        return iv + cipher.doFinal(plaintext)
    }

    override fun decrypt(blob: ByteArray): ByteArray {
        if (broken) throw GeneralSecurityException("key lost")
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(128, blob, 0, 12))
        return cipher.doFinal(blob, 12, blob.size - 12)
    }

    override fun deleteKey() {
        keyDeletes++
        key = SecureRandoms.bytes(32)
        broken = false
    }
}
