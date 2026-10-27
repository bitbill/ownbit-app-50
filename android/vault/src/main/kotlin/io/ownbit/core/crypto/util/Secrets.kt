// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.crypto.util

import java.nio.ByteBuffer
import java.nio.CharBuffer
import java.nio.charset.CharacterCodingException
import java.nio.charset.CodingErrorAction

/**
 * Helpers for handling secret material (passwords, PINs, mnemonics, seeds) in wipeable buffers.
 *
 * Kotlin/Java `String`s are immutable and cannot be cleared, so secret-handling APIs in this module take
 * `CharArray` / `ByteArray` and callers are expected to [wipe] them as soon as they are done. Every
 * intermediate buffer created by this module is wiped before the function returns.
 */
object Secrets {

    /**
     * UTF-8 encodes [chars] into an exact-size array. Unpaired surrogates are replaced with `?` — the same
     * result as `String(chars).toByteArray(Charsets.UTF_8)`, so both code paths derive identical keys.
     * The caller owns (and must wipe) the returned array.
     */
    fun utf8(chars: CharArray): ByteArray {
        val encoder = Charsets.UTF_8.newEncoder()
            .onMalformedInput(CodingErrorAction.REPLACE)
            .onUnmappableCharacter(CodingErrorAction.REPLACE)
        val buffer = encoder.encode(CharBuffer.wrap(chars))
        val out = ByteArray(buffer.remaining())
        buffer.get(out)
        buffer.wipeBacking()
        return out
    }

    /**
     * Strictly decodes UTF-8 [bytes] into a new `CharArray`; returns `null` when the bytes are not valid
     * UTF-8 (iOS `String(data:encoding: .utf8)` returns nil in the same case). The caller owns the result.
     */
    fun utf8Chars(bytes: ByteArray): CharArray? {
        val decoder = Charsets.UTF_8.newDecoder()
            .onMalformedInput(CodingErrorAction.REPORT)
            .onUnmappableCharacter(CodingErrorAction.REPORT)
        val buffer = try {
            decoder.decode(ByteBuffer.wrap(bytes))
        } catch (e: CharacterCodingException) {
            return null
        }
        val out = CharArray(buffer.remaining())
        buffer.get(out)
        if (buffer.hasArray()) buffer.array().fill('\u0000')
        return out
    }

    /** Strict UTF-8 decode into a `String` (for values that must become a String anyway, e.g. JS input). */
    fun utf8StringOrNull(bytes: ByteArray): String? {
        val chars = utf8Chars(bytes) ?: return null
        return try {
            String(chars)
        } finally {
            chars.wipe()
        }
    }

    /** Zero-fills every non-null array. */
    fun wipe(vararg arrays: ByteArray?) {
        for (a in arrays) a?.fill(0)
    }

    /** Zero-fills every non-null array. */
    fun wipe(vararg arrays: CharArray?) {
        for (a in arrays) a?.fill('\u0000')
    }

    private fun ByteBuffer.wipeBacking() {
        if (hasArray()) array().fill(0)
    }
}

/** Zero-fills this array in place. */
fun ByteArray.wipe() = fill(0)

/** Zero-fills this array in place. */
fun CharArray.wipe() = fill('\u0000')

/**
 * Runs [block] with this array and wipes it afterwards, even when [block] throws.
 */
inline fun <R> ByteArray.useAndWipe(block: (ByteArray) -> R): R = try {
    block(this)
} finally {
    wipe()
}

/**
 * Runs [block] with this array and wipes it afterwards, even when [block] throws.
 */
inline fun <R> CharArray.useAndWipe(block: (CharArray) -> R): R = try {
    block(this)
} finally {
    wipe()
}
