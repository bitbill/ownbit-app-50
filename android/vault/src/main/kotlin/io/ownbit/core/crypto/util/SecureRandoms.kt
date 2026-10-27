// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.crypto.util

import java.security.SecureRandom

/**
 * Cryptographically secure randomness. Backed by a single lazily created [SecureRandom] (on Android this is
 * the OpenSSL/`/dev/urandom` backed default provider — never seeded manually).
 */
object SecureRandoms {
    private val random: SecureRandom by lazy { SecureRandom() }

    /** Returns [size] random bytes. */
    fun bytes(size: Int): ByteArray {
        require(size >= 0) { "size must be >= 0" }
        return ByteArray(size).also { random.nextBytes(it) }
    }

    /** Uniform random int in `[0, bound)`. */
    fun nextInt(bound: Int): Int {
        require(bound > 0) { "bound must be > 0" }
        return random.nextInt(bound)
    }

    /**
     * Uniform random string of [length] characters drawn from [alphabet] (no modulo bias:
     * [SecureRandom.nextInt] with a bound is unbiased), e.g. the nonce of a biometric key alias.
     */
    fun string(length: Int, alphabet: String = LOWER_ALPHANUMERIC): String {
        require(length >= 0) { "length must be >= 0" }
        require(alphabet.isNotEmpty()) { "alphabet must not be empty" }
        val out = CharArray(length) { alphabet[random.nextInt(alphabet.length)] }
        return String(out)
    }

    /** `[a-z0-9]`. */
    const val LOWER_ALPHANUMERIC = "abcdefghijklmnopqrstuvwxyz0123456789"
}

/**
 * Compares two byte arrays in time that depends only on their lengths, not on their contents
 * (use for MACs, verifiers, tags). `null` equals only `null`.
 */
fun constantTimeEquals(a: ByteArray?, b: ByteArray?): Boolean {
    if (a === b) return true
    if (a == null || b == null) return false
    var diff = a.size xor b.size
    val n = minOf(a.size, b.size)
    for (i in 0 until n) {
        diff = diff or (a[i].toInt() xor b[i].toInt())
    }
    return diff == 0
}
