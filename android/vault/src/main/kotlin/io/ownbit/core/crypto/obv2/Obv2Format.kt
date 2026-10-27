// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.crypto.obv2

import io.ownbit.core.crypto.kdf.ScryptParams
import io.ownbit.core.crypto.util.Hex
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.Json
import java.util.Base64

/**
 * Wire model of the OBV2 envelope JSON — field names, types and meaning exactly as iOS
 * `WalletSecretCipher.Envelope` (`iOS/Sources/OwnbitCore/Vault/WalletSecretCipher.swift`). Every field is public
 * information; the secrets are the password and the device key.
 */
@Serializable
internal data class Obv2EnvelopeJson(
    @SerialName("v") val v: Int,
    @SerialName("kdf") val kdf: String,
    @SerialName("n") val n: Int,
    @SerialName("r") val r: Int,
    @SerialName("p") val p: Int,
    @SerialName("dklen") val dklen: Int,
    /** hex, 16 random bytes */
    @SerialName("salt") val salt: String,
    /** "device" | "none" */
    @SerialName("bind") val bind: String,
    /** device-key fingerprint, present only when bind == "device"; omitted (not null) otherwise */
    @SerialName("dkfp") val dkfp: String? = null,
    /** "aes-256-gcm" */
    @SerialName("cipher") val cipher: String,
    /** hex, 12 random bytes */
    @SerialName("nonce") val nonce: String,
    /** hex ciphertext (without tag) */
    @SerialName("ct") val ct: String,
    /** hex, 16-byte GCM tag */
    @SerialName("tag") val tag: String,
)

/** Key binding of an envelope. */
enum class Obv2Binding(internal val wire: String) {
    /** scrypt + device key (HMAC). Local storage — always use this for data at rest. */
    DEVICE("device"),

    /**
     * scrypt only; decryptable on any device with the password. iOS uses it for cloud backups; Android 5.0
     * has no cloud backup, but the format is supported for interoperability.
     */
    PORTABLE("none"),
}

/**
 * Public header of an envelope (everything but salt/nonce/ciphertext), for diagnostics and binding checks.
 */
data class Obv2Header(
    val version: Int,
    val params: ScryptParams,
    val binding: Obv2Binding,
    /** `dkfp` value; null for portable envelopes or device envelopes written without one. */
    val deviceKeyFingerprint: String?,
)

/** A fully validated, decoded envelope. */
internal class Obv2Parsed(
    val header: Obv2Header,
    val salt: ByteArray,
    val nonce: ByteArray,
    val ciphertext: ByteArray,
    val tag: ByteArray,
)

internal object Obv2Format {
    const val PREFIX = "OBV2:"
    const val VERSION = 2
    const val KDF = "scrypt"
    const val CIPHER = "aes-256-gcm"
    const val SALT_BYTES = 16
    const val NONCE_BYTES = 12
    const val TAG_BYTES = 16

    val json = Json {
        ignoreUnknownKeys = true
        explicitNulls = false
        encodeDefaults = false
    }

    fun encode(model: Obv2EnvelopeJson): String {
        val bytes = json.encodeToString(Obv2EnvelopeJson.serializer(), model).toByteArray(Charsets.UTF_8)
        return PREFIX + Base64.getEncoder().encodeToString(bytes)
    }

    /**
     * Decodes and validates [blob]; returns null for anything malformed (wrong prefix, base64, JSON, version,
     * kdf/cipher names, hex fields, lengths, or scrypt parameters outside [ScryptParams.isAcceptable]).
     */
    fun parse(blob: String?): Obv2Parsed? {
        if (blob == null || !blob.startsWith(PREFIX)) return null
        val raw = try {
            Base64.getDecoder().decode(blob.substring(PREFIX.length))
        } catch (e: IllegalArgumentException) {
            return null
        }
        val model = try {
            json.decodeFromString(Obv2EnvelopeJson.serializer(), raw.toString(Charsets.UTF_8))
        } catch (e: SerializationException) {
            return null
        } catch (e: IllegalArgumentException) {
            return null
        }
        if (model.v != VERSION || model.kdf != KDF || model.cipher != CIPHER) return null
        if (!ScryptParams.isAcceptable(model.n, model.r, model.p, model.dklen)) return null
        val salt = Hex.decodeOrNull(model.salt) ?: return null
        val nonce = Hex.decodeOrNull(model.nonce) ?: return null
        val ct = Hex.decodeOrNull(model.ct) ?: return null
        val tag = Hex.decodeOrNull(model.tag) ?: return null
        if (salt.isEmpty() || nonce.size != NONCE_BYTES || tag.size != TAG_BYTES) return null
        // iOS: anything but "device" is treated as scrypt-only.
        val binding = if (model.bind == Obv2Binding.DEVICE.wire) Obv2Binding.DEVICE else Obv2Binding.PORTABLE
        // A portable key is the scrypt output itself, so it must be a valid AES key length.
        if (binding == Obv2Binding.PORTABLE && model.dklen !in AES_KEY_SIZES) return null
        val header = Obv2Header(
            version = model.v,
            params = ScryptParams(model.n, model.r, model.p, model.dklen),
            binding = binding,
            deviceKeyFingerprint = model.dkfp,
        )
        return Obv2Parsed(header, salt, nonce, ct, tag)
    }

    private val AES_KEY_SIZES = setOf(16, 24, 32)
}
