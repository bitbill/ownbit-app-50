// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.crypto.kdf

import com.sun.jna.Library
import com.sun.jna.Native
import com.sun.jna.NativeLong
import org.bouncycastle.crypto.generators.SCrypt

/** One scrypt implementation. Implementations are blocking and thread-safe. */
interface ScryptEngine {
    /** Short name for diagnostics (never includes inputs). */
    val name: String

    /**
     * Derives `params.dkLen` bytes from [password] and [salt]. Does not modify the inputs.
     * @throws ScryptException when the implementation rejects the inputs or fails.
     */
    fun derive(password: ByteArray, salt: ByteArray, params: ScryptParams): ByteArray
}

/** Raised when a scrypt derivation fails. Never carries inputs. */
class ScryptException(message: String, cause: Throwable? = null) : Exception(message, cause)

/**
 * Pure-Java scrypt (BouncyCastle `SCrypt.generate`). Always available (JVM unit tests, devices where the
 * native library cannot load) but noticeably slower than libsodium for N=32768 on mid-range phones.
 */
object BouncyCastleScryptEngine : ScryptEngine {
    override val name: String = "bouncycastle"

    override fun derive(password: ByteArray, salt: ByteArray, params: ScryptParams): ByteArray = try {
        SCrypt.generate(password, salt, params.n, params.r, params.p, params.dkLen)
    } catch (e: IllegalArgumentException) {
        throw ScryptException("bouncycastle scrypt rejected parameters", e)
    }
}

/**
 * Native scrypt through libsodium's `crypto_pwhash_scryptsalsa208sha256_ll` — the raw scrypt function, same
 * output as BouncyCastle and iOS `libscrypt_scrypt`.
 *
 * `libsodium.so` comes from the lazysodium-android AAR (all ABIs). Lazysodium 5.1's Java API does not expose
 * the `_ll` function, so it is bound directly through JNA ([SodiumScryptLibrary]). The library is loaded
 * lazily; a load failure surfaces as an `Error`/exception from [derive], which [Scrypt] catches to fall back
 * to [BouncyCastleScryptEngine].
 */
class SodiumScryptEngine : ScryptEngine {
    override val name: String = "libsodium"

    private val library: SodiumScryptLibrary by lazy {
        Native.load("sodium", SodiumScryptLibrary::class.java).also {
            // Selects the CPU-specific implementations; 0 = initialized now, 1 = already initialized.
            check(it.sodium_init() >= 0) { "sodium_init failed" }
        }
    }

    override fun derive(password: ByteArray, salt: ByteArray, params: ScryptParams): ByteArray {
        val out = ByteArray(params.dkLen)
        val rc = library.crypto_pwhash_scryptsalsa208sha256_ll(
            password,
            NativeLong(password.size.toLong()),
            salt,
            NativeLong(salt.size.toLong()),
            params.n.toLong(),
            params.r,
            params.p,
            out,
            NativeLong(out.size.toLong()),
        )
        if (rc != 0) {
            out.fill(0)
            throw ScryptException("libsodium scrypt failed")
        }
        return out
    }
}

/**
 * JNA binding of the two libsodium functions used here. `size_t` is mapped to [NativeLong] (C `long` and
 * `size_t` have the same width on every Android ABI: ILP32 and LP64).
 */
@Suppress("FunctionName", "LocalVariableName")
internal interface SodiumScryptLibrary : Library {
    fun sodium_init(): Int

    /**
     * `int crypto_pwhash_scryptsalsa208sha256_ll(const uint8_t *passwd, size_t passwdlen,
     *   const uint8_t *salt, size_t saltlen, uint64_t N, uint32_t r, uint32_t p, uint8_t *buf, size_t buflen)`
     */
    fun crypto_pwhash_scryptsalsa208sha256_ll(
        passwd: ByteArray,
        passwdlen: NativeLong,
        salt: ByteArray,
        saltlen: NativeLong,
        N: Long,
        r: Int,
        p: Int,
        buf: ByteArray,
        buflen: NativeLong,
    ): Int
}
