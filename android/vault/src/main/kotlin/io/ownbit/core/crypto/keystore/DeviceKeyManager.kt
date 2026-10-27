// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.crypto.keystore

import io.ownbit.core.crypto.util.Hex

/**
 * The per-install device key used to bind OBV2 envelopes to this device.
 *
 * Implementations never expose key material: the only operation is HMAC-SHA256 with the key.
 */
interface DeviceKey {
    /** HMAC-SHA256(key = device key, message). */
    fun hmacSha256(message: ByteArray): ByteArray

    /**
     * Public, non-secret fingerprint written into device-bound envelopes (`dkfp`, 16 hex chars) to tell
     * "wrong password" apart from "this envelope was bound to another device key".
     *
     * Android: first 8 bytes of `HMAC-SHA256(deviceKey, "fp")` (the Keystore key is not exportable, so iOS'
     * `SHA256(deviceKey)[0..8]` cannot be computed). Device-bound envelopes are never portable across
     * devices, let alone platforms, so the two schemes never meet.
     */
    fun fingerprint(): String = Hex.encode(hmacSha256(FINGERPRINT_MESSAGE), 0, FINGERPRINT_BYTES)

    companion object {
        /** Message HMAC'ed to build [fingerprint]. */
        val FINGERPRINT_MESSAGE: ByteArray = "fp".toByteArray(Charsets.US_ASCII)

        /** Fingerprint length in bytes (hex length is twice this). */
        const val FINGERPRINT_BYTES = 8
    }
}

/**
 * Access to the device key.
 *
 * Encryption uses [getOrCreate]; decryption uses [peek] and must **not** create a key: a missing key means
 * the app data was restored/moved without its Keystore (or the Keystore was wiped), which the UI reports as
 * "re-import your recovery phrase" rather than "wrong password".
 */
interface DeviceKeyManager {
    /**
     * Returns the existing key, or `null` if none exists.
     * @throws DeviceKeyException when the key store itself cannot be read.
     */
    fun peek(): DeviceKey?

    /**
     * Returns the existing key or creates one.
     * @throws DeviceKeyException when the key cannot be loaded or generated.
     */
    fun getOrCreate(): DeviceKey

    /** True when a key exists (errors count as "no key"). */
    fun exists(): Boolean = try {
        peek() != null
    } catch (e: DeviceKeyException) {
        false
    }
}

/** Device-key failure. Never carries key material. */
class DeviceKeyException(message: String, cause: Throwable? = null) : Exception(message, cause)
