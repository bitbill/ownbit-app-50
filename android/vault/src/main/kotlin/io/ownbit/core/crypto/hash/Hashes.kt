// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.crypto.hash

import io.ownbit.core.crypto.util.Hex
import org.bouncycastle.crypto.Digest
import org.bouncycastle.crypto.digests.KeccakDigest
import org.bouncycastle.crypto.digests.SHA256Digest
import org.bouncycastle.crypto.digests.SHA512Digest
import org.bouncycastle.crypto.macs.HMac
import org.bouncycastle.crypto.params.KeyParameter
import java.security.MessageDigest

/**
 * Hash / MAC primitives used across the core modules (secret integrity hashes, EVM / TRON codecs, PSBT checks…).
 *
 * - `*Hex(String)` overloads hash the UTF-8 bytes of the string and return lower-case hex — the same as
 *   iOS `String.md5()` / `String.sha256()`, which operate on `utf8` data.
 * - Keccak-256 is the **original Keccak** (Ethereum), not NIST SHA3-256.
 * - HMAC accepts empty keys (BouncyCastle), unlike `javax.crypto.spec.SecretKeySpec`.
 */
object Hashes {

    /** MD5 digest. */
    fun md5(data: ByteArray): ByteArray = MessageDigest.getInstance("MD5").digest(data)

    /** Lower-case hex MD5 of [data]. */
    fun md5Hex(data: ByteArray): String = Hex.encode(md5(data))

    /** Lower-case hex MD5 of the UTF-8 bytes of [text]. */
    fun md5Hex(text: String): String = md5Hex(text.toByteArray(Charsets.UTF_8))

    /** SHA-256 digest. */
    fun sha256(data: ByteArray): ByteArray = MessageDigest.getInstance("SHA-256").digest(data)

    /** Lower-case hex SHA-256 of [data]. */
    fun sha256Hex(data: ByteArray): String = Hex.encode(sha256(data))

    /** Lower-case hex SHA-256 of the UTF-8 bytes of [text]. */
    fun sha256Hex(text: String): String = sha256Hex(text.toByteArray(Charsets.UTF_8))

    /** SHA-512 digest. */
    fun sha512(data: ByteArray): ByteArray = MessageDigest.getInstance("SHA-512").digest(data)

    /** Lower-case hex SHA-512 of [data]. */
    fun sha512Hex(data: ByteArray): String = Hex.encode(sha512(data))

    /** Lower-case hex SHA-512 of the UTF-8 bytes of [text]. */
    fun sha512Hex(text: String): String = sha512Hex(text.toByteArray(Charsets.UTF_8))

    /** Keccak-256 (Ethereum flavour). */
    fun keccak256(data: ByteArray): ByteArray = digest(KeccakDigest(256), data)

    /** Lower-case hex Keccak-256 of [data]. */
    fun keccak256Hex(data: ByteArray): String = Hex.encode(keccak256(data))

    /** Lower-case hex Keccak-256 of the UTF-8 bytes of [text]. */
    fun keccak256Hex(text: String): String = keccak256Hex(text.toByteArray(Charsets.UTF_8))

    /** HMAC-SHA256(key, data). */
    fun hmacSha256(key: ByteArray, data: ByteArray): ByteArray = hmac(SHA256Digest(), key, data)

    /** HMAC-SHA512(key, data). */
    fun hmacSha512(key: ByteArray, data: ByteArray): ByteArray = hmac(SHA512Digest(), key, data)

    private fun digest(digest: Digest, data: ByteArray): ByteArray {
        digest.update(data, 0, data.size)
        return ByteArray(digest.digestSize).also { digest.doFinal(it, 0) }
    }

    private fun hmac(digest: Digest, key: ByteArray, data: ByteArray): ByteArray {
        val mac = HMac(digest)
        mac.init(KeyParameter(key))
        mac.update(data, 0, data.size)
        val out = ByteArray(mac.macSize)
        mac.doFinal(out, 0)
        // HMac keeps ipad/opad key state internally; reset() re-derives from the key, so scrub via a zero key.
        mac.init(KeyParameter(ByteArray(key.size)))
        return out
    }
}
