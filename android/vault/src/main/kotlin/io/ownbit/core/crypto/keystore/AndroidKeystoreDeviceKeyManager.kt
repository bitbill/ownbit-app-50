// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.crypto.keystore

import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.security.GeneralSecurityException
import java.security.KeyStore
import java.security.ProviderException
import javax.crypto.KeyGenerator
import javax.crypto.Mac
import javax.crypto.SecretKey

/**
 * [DeviceKeyManager] backed by a non-exportable Android Keystore HMAC-SHA256 key (StrongBox when the
 * device has one, TEE otherwise). The key requires no user authentication, is never backed up and is
 * destroyed on uninstall — exactly like iOS' `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` device key.
 */
class AndroidKeystoreDeviceKeyManager() : DeviceKeyManager {

    private val lock = Any()

    override fun peek(): DeviceKey? = try {
        val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        (keyStore.getKey(ALIAS, null) as? SecretKey)?.let(::KeystoreDeviceKey)
    } catch (e: GeneralSecurityException) {
        throw DeviceKeyException("android keystore unavailable", e)
    } catch (e: java.io.IOException) {
        throw DeviceKeyException("android keystore unavailable", e)
    } catch (e: ProviderException) {
        throw DeviceKeyException("android keystore unavailable", e)
    }

    override fun getOrCreate(): DeviceKey = synchronized(lock) {
        peek() ?: generate()
    }

    private fun generate(): DeviceKey {
        val strongBox = Build.VERSION.SDK_INT >= Build.VERSION_CODES.P
        if (strongBox) {
            try {
                return KeystoreDeviceKey(generateKey(strongBox = true))
            } catch (e: ProviderException) {
                // StrongBoxUnavailableException (a ProviderException) or a late StrongBox failure:
                // fall through to the TEE-backed key.
            } catch (e: GeneralSecurityException) {
                // StrongBox rejected the key spec: fall through to the TEE-backed key.
            }
        }
        return try {
            KeystoreDeviceKey(generateKey(strongBox = false))
        } catch (e: GeneralSecurityException) {
            throw DeviceKeyException("device key generation failed", e)
        } catch (e: ProviderException) {
            throw DeviceKeyException("device key generation failed", e)
        }
    }

    private fun generateKey(strongBox: Boolean): SecretKey {
        val builder = KeyGenParameterSpec.Builder(
            ALIAS,
            KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY,
        ).setKeySize(KEY_SIZE_BITS)
        if (strongBox && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            builder.setIsStrongBoxBacked(true)
        }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_HMAC_SHA256, ANDROID_KEYSTORE)
        generator.init(builder.build())
        return generator.generateKey()
    }

    private class KeystoreDeviceKey(private val key: SecretKey) : DeviceKey {
        override fun hmacSha256(message: ByteArray): ByteArray = try {
            Mac.getInstance(HMAC_SHA256).run {
                init(key)
                doFinal(message)
            }
        } catch (e: GeneralSecurityException) {
            throw DeviceKeyException("device key HMAC failed", e)
        } catch (e: ProviderException) {
            throw DeviceKeyException("device key HMAC failed", e)
        }

        override fun toString(): String = "KeystoreDeviceKey"
    }

    companion object {
        private const val ANDROID_KEYSTORE = "AndroidKeyStore"
        private const val HMAC_SHA256 = "HmacSHA256"
        private const val KEY_SIZE_BITS = 256

        /** Keystore alias of the OBV2 device key. Changing it orphans every device-bound envelope. */
        const val ALIAS = "ownbit_vault_devicekey_v2"
    }
}
