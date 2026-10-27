// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.crypto.biometric

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyInfo
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import android.security.keystore.UserNotAuthenticatedException
import io.ownbit.core.common.log.Log
import java.security.GeneralSecurityException
import java.security.KeyStore
import java.security.ProviderException
import java.security.UnrecoverableKeyException
import javax.crypto.Cipher
import javax.crypto.IllegalBlockSizeException
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.GCMParameterSpec

/**
 * [BiometricKeyStore] on the Android Keystore. Key spec: AES-256-GCM, no padding, randomized encryption,
 * user authentication required, invalidated by biometric enrolment, `AUTH_BIOMETRIC_STRONG` with timeout 0 on API
 * 30+ (validity −1 below: auth-per-use, only Class 3 biometrics can release such keys). StrongBox is tried first when
 * the device declares `FEATURE_STRONGBOX_KEYSTORE`; any failure there falls back to the TEE. Logs carry exception
 * class names / verdict tags only.
 */
class AndroidBiometricKeyStore(
    private val context: Context,
) : BiometricKeyStore {

    private val lock = Any()

    override fun create(alias: String): KeyVerdict = synchronized(lock) { createLocked(alias) }

    private fun createLocked(alias: String): KeyVerdict {
        delete(alias)
        val strongBox = Build.VERSION.SDK_INT >= Build.VERSION_CODES.P &&
            context.packageManager.hasSystemFeature(PackageManager.FEATURE_STRONGBOX_KEYSTORE)
        var inStrongBox = false
        val key = try {
            if (strongBox) {
                try {
                    generate(alias, strongBox = true).also { inStrongBox = true }
                } catch (e: ProviderException) {
                    // StrongBoxUnavailableException is a ProviderException; late StrongBox failures too.
                    delete(alias)
                    generate(alias, strongBox = false)
                } catch (e: GeneralSecurityException) {
                    delete(alias)
                    generate(alias, strongBox = false)
                }
            } else {
                generate(alias, strongBox = false)
            }
        } catch (e: Exception) {
            Log.w(TAG) { "key generation failed: ${e.javaClass.simpleName}" }
            delete(alias)
            return KeyVerdict.Reject("generate:${e.javaClass.simpleName}")
        }
        val verdict = try {
            KeyInfoRules.verdict(facts(key))
        } catch (e: Exception) {
            KeyVerdict.Reject("keyinfo:${e.javaClass.simpleName}")
        }
        return when (verdict) {
            is KeyVerdict.Reject -> {
                Log.w(TAG) { "key rejected: ${verdict.reason}" }
                delete(alias)
                verdict
            }
            // KeyInfo cannot tell StrongBox from TEE below API 31: the successful StrongBox generation can.
            is KeyVerdict.Accept -> if (inStrongBox) KeyVerdict.Accept(KeySecurityLevel.STRONGBOX) else verdict
        }
    }

    override fun refusesUnauthenticatedUse(alias: String): Boolean {
        val key = try {
            loadKey(alias) ?: return false
        } catch (e: Exception) {
            return false
        }
        return try {
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.ENCRYPT_MODE, key)
            cipher.doFinal(ByteArray(PROBE_BYTES))
            Log.w(TAG) { "negative probe: unauthenticated use succeeded" }
            false
        } catch (e: UserNotAuthenticatedException) {
            true
        } catch (e: IllegalBlockSizeException) {
            causedByKeystore(e)
        } catch (e: Exception) {
            Log.w(TAG) { "negative probe inconclusive: ${e.javaClass.simpleName}" }
            false
        }
    }

    override fun encryptCipher(alias: String): CipherResult = cipher(alias) { key ->
        Cipher.getInstance(TRANSFORMATION).apply { init(Cipher.ENCRYPT_MODE, key) }
    }

    override fun decryptCipher(alias: String, iv: ByteArray): CipherResult = cipher(alias) { key ->
        Cipher.getInstance(TRANSFORMATION).apply { init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(TAG_BITS, iv)) }
    }

    override fun delete(alias: String) {
        try {
            val ks = keyStore()
            if (ks.containsAlias(alias)) ks.deleteEntry(alias)
        } catch (e: Exception) {
            Log.w(TAG) { "delete failed: ${e.javaClass.simpleName}" }
        }
    }

    override fun exists(alias: String): Boolean = try {
        keyStore().containsAlias(alias)
    } catch (e: Exception) {
        false
    }

    override fun aliases(prefix: String): List<String> = try {
        keyStore().aliases().toList().filter { it.startsWith(prefix) }
    } catch (e: Exception) {
        emptyList()
    }

    private inline fun cipher(alias: String, init: (SecretKey) -> Cipher): CipherResult = try {
        val key = loadKey(alias)
        if (key == null) CipherResult.Missing else CipherResult.Ready(init(key))
    } catch (e: KeyPermanentlyInvalidatedException) {
        CipherResult.Invalidated
    } catch (e: UnrecoverableKeyException) {
        CipherResult.Invalidated
    } catch (e: GeneralSecurityException) {
        Log.w(TAG) { "cipher init failed: ${e.javaClass.simpleName}" }
        CipherResult.Failed(e)
    } catch (e: ProviderException) {
        Log.w(TAG) { "cipher init failed: ${e.javaClass.simpleName}" }
        CipherResult.Failed(e)
    } catch (e: RuntimeException) {
        Log.w(TAG) { "cipher init failed: ${e.javaClass.simpleName}" }
        CipherResult.Failed(e)
    }

    private fun keyStore(): KeyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }

    internal fun loadKey(alias: String): SecretKey? = keyStore().getKey(alias, null) as? SecretKey

    /**
     * Generates the auth-per-use key under [alias] **without** judging it (instrumented tests read its facts on
     * software-only Keystores, where [create] deletes it at once). Production code uses [create].
     */
    internal fun generate(alias: String, strongBox: Boolean): SecretKey {
        val builder = KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
            .setKeySize(KEY_BITS)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setRandomizedEncryptionRequired(true)
            .setUserAuthenticationRequired(true)
            .setInvalidatedByBiometricEnrollment(true)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            builder.setUserAuthenticationParameters(0, KeyProperties.AUTH_BIOMETRIC_STRONG)
        } else {
            @Suppress("DEPRECATION")
            builder.setUserAuthenticationValidityDurationSeconds(-1)
        }
        if (strongBox && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) builder.setIsStrongBoxBacked(true)
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEYSTORE).run {
            init(builder.build())
            generateKey()
        }
    }

    /** The [KeyInfoFacts] of [key] (an AndroidKeyStore secret key). */
    internal fun facts(key: SecretKey): KeyInfoFacts {
        val info = SecretKeyFactory.getInstance(key.algorithm, ANDROID_KEYSTORE).getKeySpec(key, KeyInfo::class.java) as KeyInfo
        val sdk = Build.VERSION.SDK_INT
        return KeyInfoFacts(
            sdkInt = sdk,
            securityLevel = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) info.securityLevel else null,
            insideSecureHardware = @Suppress("DEPRECATION") info.isInsideSecureHardware,
            userAuthRequired = info.isUserAuthenticationRequired,
            authEnforcedBySecureHardware = info.isUserAuthenticationRequirementEnforcedBySecureHardware,
            authType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) info.userAuthenticationType else null,
            validitySeconds = info.userAuthenticationValidityDurationSeconds,
            invalidatedByEnrollment = info.isInvalidatedByBiometricEnrollment,
            validWhileOnBody = info.isUserAuthenticationValidWhileOnBody,
        )
    }

    /** `IllegalBlockSizeException` whose cause chain holds the Keystore's refusal (`android.security.KeyStoreException`). */
    private fun causedByKeystore(e: Throwable): Boolean {
        var c: Throwable? = e.cause
        var depth = 0
        while (c != null && depth < MAX_CAUSE_DEPTH) {
            if (c is UserNotAuthenticatedException) return true
            val name = c.javaClass.name
            if (name == "android.security.KeyStoreException" || name == "android.security.keystore.KeyStoreException") return true
            c = c.cause
            depth++
        }
        return false
    }

    companion object {
        private const val TAG = "BiometricKeyStore"
        private const val ANDROID_KEYSTORE = "AndroidKeyStore"
        private const val TRANSFORMATION = "AES/GCM/NoPadding"
        private const val KEY_BITS = 256
        private const val TAG_BITS = 128
        private const val PROBE_BYTES = 16
        private const val MAX_CAUSE_DEPTH = 8
    }
}
