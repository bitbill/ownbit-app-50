// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.crypto.util

/**
 * Lower-case hexadecimal encoding, matching iOS `String(format: "%02x")` output.
 *
 * Decoding accepts upper- and lower-case digits (iOS `UInt8(_, radix: 16)`), rejects odd lengths and any
 * non-hex character (no `0x` prefix, no whitespace).
 */
object Hex {
    private val DIGITS = "0123456789abcdef".toCharArray()

    /** Encodes [bytes] as lower-case hex. */
    fun encode(bytes: ByteArray): String = encode(bytes, 0, bytes.size)

    /** Encodes `bytes[offset until offset + length]` as lower-case hex. */
    fun encode(bytes: ByteArray, offset: Int, length: Int): String {
        require(offset >= 0 && length >= 0 && offset + length <= bytes.size) { "range out of bounds" }
        val out = CharArray(length * 2)
        for (i in 0 until length) {
            val v = bytes[offset + i].toInt() and 0xFF
            out[i * 2] = DIGITS[v ushr 4]
            out[i * 2 + 1] = DIGITS[v and 0x0F]
        }
        return String(out)
    }

    /** Decodes [hex]; returns `null` for odd length or non-hex characters. */
    fun decodeOrNull(hex: CharSequence): ByteArray? {
        if (hex.length % 2 != 0) return null
        val out = ByteArray(hex.length / 2)
        for (i in out.indices) {
            val hi = digit(hex[i * 2])
            val lo = digit(hex[i * 2 + 1])
            if (hi < 0 || lo < 0) return null
            out[i] = ((hi shl 4) or lo).toByte()
        }
        return out
    }

    /** Decodes [hex]; throws [IllegalArgumentException] for malformed input. */
    fun decode(hex: CharSequence): ByteArray =
        requireNotNull(decodeOrNull(hex)) { "malformed hex string" }

    private fun digit(c: Char): Int = when (c) {
        in '0'..'9' -> c - '0'
        in 'a'..'f' -> c - 'a' + 10
        in 'A'..'F' -> c - 'A' + 10
        else -> -1
    }
}
