// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.crypto.obv2

import io.ownbit.core.crypto.kdf.Scrypt
import io.ownbit.core.crypto.kdf.ScryptException
import io.ownbit.core.crypto.kdf.ScryptParams
import io.ownbit.core.crypto.keystore.DeviceKey
import io.ownbit.core.crypto.keystore.DeviceKeyException
import io.ownbit.core.crypto.keystore.DeviceKeyManager
import io.ownbit.core.crypto.util.Hex
import io.ownbit.core.crypto.util.SecureRandoms
import io.ownbit.core.crypto.util.Secrets
import io.ownbit.core.crypto.util.constantTimeEquals
import io.ownbit.core.crypto.util.wipe
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.withContext
import java.security.GeneralSecurityException
import javax.crypto.AEADBadTagException
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * OBV2 secret envelope — the only at-rest format for mnemonics, seeds, BIP39 passphrases, private keys and WIFs.
 * Port of iOS `WalletSecretCipher` v2 (same envelope, same parameters, same AES key derivation):
 *
 * ```
 * "OBV2:" + base64(JSON{v:2, kdf:"scrypt", n, r, p, dklen, salt(hex16), bind:"device"|"none", dkfp?,
 *                       cipher:"aes-256-gcm", nonce(hex12), ct(hex), tag(hex16)})
 * scryptKey = scrypt(utf8(password), salt, N=32768, r=8, p=1, dkLen=32)
 * aesKey    = bind == device ? HMAC-SHA256(deviceKey, scryptKey) : scryptKey
 * ct||tag   = AES-256-GCM(aesKey, random 12-byte nonce, utf8(plaintext))
 * ```
 *
 * - Decryption reads every parameter from the envelope (never hard-coded) and authenticates with the GCM
 *   tag: wrong password, tampering and a missing/replaced device key all fail (`null` from [decrypt],
 *   a specific [Obv2DecryptResult] from [open]). "Verify password" == "can it be opened" ([verifyPassword]).
 * - Every operation (scrypt, Keystore HMAC, AES-GCM) runs on the injected [dispatcher]
 *   (`Dispatchers.Default`); every function is `suspend` and main-safe.
 * - Differences from iOS, both invisible in the envelope format: every envelope gets its own random salt (iOS shares
 *   one salt between the fields of a wallet and caches the scrypt key for 60 s), and the device-key fingerprint
 *   `dkfp` is `HMAC-SHA256(deviceKey, "fp")[0..8]` because the Keystore key cannot be exported ([DeviceKey.fingerprint]).
 * - Secrets are handled as `CharArray`/`ByteArray`. This class wipes every buffer it creates; the caller
 *   still owns (and must wipe) the arrays it passes in and the plaintext it receives.
 * - Nothing here logs.
 */
class Obv2Envelope(
    private val deviceKeys: DeviceKeyManager,
    private val scrypt: Scrypt,
    private val dispatcher: CoroutineDispatcher,
) {

    /**
     * Encrypts [plaintext] bytes (normally UTF-8 text) under [password].
     *
     * @param binding [Obv2Binding.DEVICE] for local storage (default); [Obv2Binding.PORTABLE] only for data
     *   that must be decryptable on another device.
     * @param params scrypt parameters written into the envelope (default iOS N=32768/r=8/p=1/32).
     * @return the `OBV2:` envelope string.
     * @throws Obv2Exception when the password is empty, the KDF fails, the device key is unavailable or
     *   AES-GCM fails.
     */
    suspend fun encrypt(
        plaintext: ByteArray,
        password: CharArray,
        binding: Obv2Binding = Obv2Binding.DEVICE,
        params: ScryptParams = ScryptParams.WALLET_SECRET,
    ): String = withContext(dispatcher) { encryptInternal(plaintext, password, binding, params) }

    private suspend fun encryptInternal(
        plaintext: ByteArray,
        password: CharArray,
        binding: Obv2Binding,
        params: ScryptParams,
    ): String {
        if (password.isEmpty()) throw Obv2Exception(Obv2Exception.Reason.EMPTY_PASSWORD)
        if (binding == Obv2Binding.PORTABLE && params.dkLen != AES_256_KEY_BYTES) {
            throw Obv2Exception(Obv2Exception.Reason.KDF_FAILED)
        }
        val salt = SecureRandoms.bytes(Obv2Format.SALT_BYTES)
        val deviceKey = if (binding == Obv2Binding.DEVICE) {
            try {
                deviceKeys.getOrCreate()
            } catch (e: DeviceKeyException) {
                throw Obv2Exception(Obv2Exception.Reason.DEVICE_KEY_UNAVAILABLE, e)
            }
        } else {
            null
        }
        val scryptKey = deriveScryptKey(password, salt, params)
            ?: throw Obv2Exception(Obv2Exception.Reason.KDF_FAILED)
        var aesKey: ByteArray? = null
        try {
            val fingerprint: String?
            if (deviceKey != null) {
                try {
                    aesKey = deviceKey.hmacSha256(scryptKey)
                    fingerprint = deviceKey.fingerprint()
                } catch (e: DeviceKeyException) {
                    throw Obv2Exception(Obv2Exception.Reason.DEVICE_KEY_UNAVAILABLE, e)
                }
            } else {
                aesKey = scryptKey.copyOf()
                fingerprint = null
            }
            val nonce = SecureRandoms.bytes(Obv2Format.NONCE_BYTES)
            val sealed = try {
                aesGcm(Cipher.ENCRYPT_MODE, aesKey, nonce).doFinal(plaintext)
            } catch (e: GeneralSecurityException) {
                throw Obv2Exception(Obv2Exception.Reason.ENCRYPTION_FAILED, e)
            }
            val ctLength = sealed.size - Obv2Format.TAG_BYTES
            val model = Obv2EnvelopeJson(
                v = Obv2Format.VERSION,
                kdf = Obv2Format.KDF,
                n = params.n,
                r = params.r,
                p = params.p,
                dklen = params.dkLen,
                salt = Hex.encode(salt),
                bind = binding.wire,
                dkfp = fingerprint,
                cipher = Obv2Format.CIPHER,
                nonce = Hex.encode(nonce),
                ct = Hex.encode(sealed, 0, ctLength),
                tag = Hex.encode(sealed, ctLength, Obv2Format.TAG_BYTES),
            )
            return Obv2Format.encode(model)
        } finally {
            scryptKey.wipe()
            aesKey?.wipe()
        }
    }

    /** [encrypt] for text held in a `CharArray` (UTF-8 encoded; the temporary bytes are wiped). */
    suspend fun encrypt(
        plaintext: CharArray,
        password: CharArray,
        binding: Obv2Binding = Obv2Binding.DEVICE,
        params: ScryptParams = ScryptParams.WALLET_SECRET,
    ): String {
        val bytes = Secrets.utf8(plaintext)
        return try {
            encrypt(bytes, password, binding, params)
        } finally {
            bytes.wipe()
        }
    }

    /** [encrypt] for text that is already a `String` (e.g. a seed hex returned by JS). */
    suspend fun encrypt(
        plaintext: String,
        password: CharArray,
        binding: Obv2Binding = Obv2Binding.DEVICE,
        params: ScryptParams = ScryptParams.WALLET_SECRET,
    ): String {
        val bytes = plaintext.toByteArray(Charsets.UTF_8)
        return try {
            encrypt(bytes, password, binding, params)
        } finally {
            bytes.wipe()
        }
    }

    /**
     * Encrypts and immediately decrypts the result, returning the envelope only if the round trip reproduces
     * [plaintext] exactly (iOS `reencryptToV2` self-check). Returns `null` on any failure, so callers never
     * persist an envelope they cannot open — used by create/import and change-password flows.
     */
    suspend fun encryptVerified(
        plaintext: ByteArray,
        password: CharArray,
        binding: Obv2Binding = Obv2Binding.DEVICE,
        params: ScryptParams = ScryptParams.WALLET_SECRET,
    ): String? {
        if (plaintext.isEmpty() || password.isEmpty()) return null
        val envelope = try {
            encrypt(plaintext, password, binding, params)
        } catch (e: Obv2Exception) {
            return null
        }
        val result = open(envelope, password)
        return try {
            if (result is Obv2DecryptResult.Success && constantTimeEquals(result.plaintext, plaintext)) envelope else null
        } finally {
            (result as? Obv2DecryptResult.Success)?.plaintext?.wipe()
        }
    }

    /** [encryptVerified] for text held in a `CharArray`. */
    suspend fun encryptVerified(
        plaintext: CharArray,
        password: CharArray,
        binding: Obv2Binding = Obv2Binding.DEVICE,
        params: ScryptParams = ScryptParams.WALLET_SECRET,
    ): String? {
        val bytes = Secrets.utf8(plaintext)
        return try {
            encryptVerified(bytes, password, binding, params)
        } finally {
            bytes.wipe()
        }
    }

    /** [encryptVerified] for text that is already a `String`. */
    suspend fun encryptVerified(
        plaintext: String,
        password: CharArray,
        binding: Obv2Binding = Obv2Binding.DEVICE,
        params: ScryptParams = ScryptParams.WALLET_SECRET,
    ): String? {
        val bytes = plaintext.toByteArray(Charsets.UTF_8)
        return try {
            encryptVerified(bytes, password, binding, params)
        } finally {
            bytes.wipe()
        }
    }

    /**
     * Decrypts [envelope] and reports exactly why it failed. The caller must wipe
     * [Obv2DecryptResult.Success.plaintext].
     */
    suspend fun open(envelope: String, password: CharArray): Obv2DecryptResult =
        withContext(dispatcher) { openInternal(envelope, password) }

    private suspend fun openInternal(envelope: String, password: CharArray): Obv2DecryptResult {
        val parsed = Obv2Format.parse(envelope) ?: return Obv2DecryptResult.BadEnvelope
        var deviceKey: DeviceKey? = null
        if (parsed.header.binding == Obv2Binding.DEVICE) {
            // Never create a key while decrypting: a missing key means the device changed.
            deviceKey = try {
                deviceKeys.peek()
            } catch (e: DeviceKeyException) {
                null
            } ?: return Obv2DecryptResult.DeviceKeyUnavailable
            val expected = parsed.header.deviceKeyFingerprint
            if (expected != null) {
                val actual = try {
                    deviceKey.fingerprint()
                } catch (e: DeviceKeyException) {
                    return Obv2DecryptResult.DeviceKeyUnavailable
                }
                if (!expected.equals(actual, ignoreCase = true)) return Obv2DecryptResult.DeviceKeyMismatch
            }
        }
        // encrypt() never accepts an empty password, so it can never open anything.
        if (password.isEmpty()) return Obv2DecryptResult.DecryptFailed
        val scryptKey = deriveScryptKey(password, parsed.salt, parsed.header.params)
            ?: return Obv2DecryptResult.KdfFailed
        var aesKey: ByteArray? = null
        try {
            aesKey = if (deviceKey != null) {
                try {
                    deviceKey.hmacSha256(scryptKey)
                } catch (e: DeviceKeyException) {
                    return Obv2DecryptResult.DeviceKeyUnavailable
                }
            } else {
                scryptKey.copyOf()
            }
            val sealed = parsed.ciphertext + parsed.tag
            return try {
                Obv2DecryptResult.Success(aesGcm(Cipher.DECRYPT_MODE, aesKey, parsed.nonce).doFinal(sealed))
            } catch (e: AEADBadTagException) {
                Obv2DecryptResult.DecryptFailed
            } catch (e: GeneralSecurityException) {
                Obv2DecryptResult.DecryptFailed
            } finally {
                sealed.wipe()
            }
        } finally {
            scryptKey.wipe()
            aesKey?.wipe()
        }
    }

    /**
     * Decrypts [envelope]; `null` on wrong password, tampering, missing/replaced device key or a malformed
     * envelope (iOS `decryptV2` semantics). The caller must wipe the result.
     */
    suspend fun decrypt(envelope: String, password: CharArray): ByteArray? =
        (open(envelope, password) as? Obv2DecryptResult.Success)?.plaintext

    /** [decrypt] returning UTF-8 text as a `CharArray` (null also when the plaintext is not valid UTF-8). */
    suspend fun decryptToChars(envelope: String, password: CharArray): CharArray? {
        val bytes = decrypt(envelope, password) ?: return null
        return try {
            Secrets.utf8Chars(bytes)
        } finally {
            bytes.wipe()
        }
    }

    /**
     * [decrypt] returning a `String`. Only for values that must become a String anyway (e.g. JS bridge
     * arguments); prefer [decryptToChars].
     */
    suspend fun decryptToString(envelope: String, password: CharArray): String? {
        val bytes = decrypt(envelope, password) ?: return null
        return try {
            Secrets.utf8StringOrNull(bytes)
        } finally {
            bytes.wipe()
        }
    }

    /** True when [password] opens [envelope] (the plaintext is wiped immediately). */
    suspend fun verifyPassword(envelope: String, password: CharArray): Boolean {
        val result = open(envelope, password)
        (result as? Obv2DecryptResult.Success)?.plaintext?.wipe()
        return result is Obv2DecryptResult.Success
    }

    /**
     * Binding status of [envelope] relative to this device, without a password (iOS
     * `deviceBindingStatus`). [Obv2BindingStatus.NEEDS_RESTORE] means: tell the user to re-import the
     * recovery phrase instead of "wrong password".
     */
    suspend fun bindingStatus(envelope: String?): Obv2BindingStatus =
        withContext(dispatcher) { bindingStatusInternal(envelope) }

    private fun bindingStatusInternal(envelope: String?): Obv2BindingStatus {
        val parsed = Obv2Format.parse(envelope) ?: return Obv2BindingStatus.NOT_DEVICE_BOUND
        if (parsed.header.binding != Obv2Binding.DEVICE) return Obv2BindingStatus.NOT_DEVICE_BOUND
        val key = try {
            deviceKeys.peek()
        } catch (e: DeviceKeyException) {
            null
        } ?: return Obv2BindingStatus.NEEDS_RESTORE
        val expected = parsed.header.deviceKeyFingerprint ?: return Obv2BindingStatus.OK
        val actual = try {
            key.fingerprint()
        } catch (e: DeviceKeyException) {
            return Obv2BindingStatus.NEEDS_RESTORE
        }
        return if (expected.equals(actual, ignoreCase = true)) Obv2BindingStatus.OK else Obv2BindingStatus.NEEDS_RESTORE
    }

    private suspend fun deriveScryptKey(password: CharArray, salt: ByteArray, params: ScryptParams): ByteArray? {
        val pwBytes = Secrets.utf8(password)
        return try {
            scrypt.derive(pwBytes, salt, params)
        } catch (e: ScryptException) {
            null
        } finally {
            pwBytes.wipe()
        }
    }

    private fun aesGcm(mode: Int, key: ByteArray, nonce: ByteArray): Cipher =
        Cipher.getInstance(AES_GCM).apply {
            init(mode, SecretKeySpec(key, "AES"), GCMParameterSpec(Obv2Format.TAG_BYTES * 8, nonce))
        }

    companion object {
        /** Envelope prefix ("Ownbit Vault v2"). */
        const val PREFIX: String = Obv2Format.PREFIX

        private const val AES_GCM = "AES/GCM/NoPadding"
        private const val AES_256_KEY_BYTES = 32

        /** O(1) format check (iOS `looksLikeV2`): true when [blob] starts with `OBV2:`. */
        fun isObv2(blob: String?): Boolean = blob != null && blob.startsWith(PREFIX)

        /** Parses the public header of [blob]; null when it is not a well-formed OBV2 envelope. */
        fun header(blob: String?): Obv2Header? = Obv2Format.parse(blob)?.header
    }
}

/** Result of [Obv2Envelope.open]. */
sealed interface Obv2DecryptResult {
    /** Decrypted bytes; the receiver owns and must wipe [plaintext]. */
    class Success(val plaintext: ByteArray) : Obv2DecryptResult {
        override fun toString(): String = "Success(<redacted>)"
    }

    /** Not an OBV2 envelope, or malformed / unsupported parameters. */
    data object BadEnvelope : Obv2DecryptResult

    /** Wrong password or tampered ciphertext (GCM authentication failed). */
    data object DecryptFailed : Obv2DecryptResult

    /** Device-bound envelope but this device has no device key (app data moved / Keystore wiped). */
    data object DeviceKeyUnavailable : Obv2DecryptResult

    /** Device-bound envelope written with a different device key (fingerprint mismatch). */
    data object DeviceKeyMismatch : Obv2DecryptResult

    /** The scrypt derivation itself failed (e.g. out of memory). */
    data object KdfFailed : Obv2DecryptResult
}

/** True when the failure should be presented as "re-import your recovery phrase" rather than "wrong password". */
val Obv2DecryptResult.needsRestore: Boolean
    get() = this is Obv2DecryptResult.DeviceKeyUnavailable || this is Obv2DecryptResult.DeviceKeyMismatch

/** Binding of an envelope relative to the current device (iOS `DeviceBindingStatus`). */
enum class Obv2BindingStatus {
    /** Not OBV2, or a portable envelope. */
    NOT_DEVICE_BOUND,

    /** Device-bound and this device holds the matching key. */
    OK,

    /** Device-bound but the key is missing or different: re-import required. */
    NEEDS_RESTORE,
}

/** Encryption failure. Never carries secrets. */
class Obv2Exception(val reason: Reason, cause: Throwable? = null) : Exception("OBV2 encryption failed: $reason", cause) {
    /** Failure reason. */
    enum class Reason { EMPTY_PASSWORD, KDF_FAILED, DEVICE_KEY_UNAVAILABLE, ENCRYPTION_FAILED }
}
