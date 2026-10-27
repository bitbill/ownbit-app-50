// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.model.format

import java.text.CharacterIterator

/**
 * A [CharacterIterator] reading a [CharSequence] in place (the JDK only ships `StringCharacterIterator`, which needs a
 * `String`). Lets [TextLength.graphemes] count a password held in a `CharArray` (`CharBuffer.wrap(chars)`) without
 * copying it into an immutable `String` that could not be wiped.
 */
class CharSequenceCharacterIterator(
    private val text: CharSequence,
    private val begin: Int = 0,
    private val end: Int = text.length,
) : CharacterIterator {

    private var pos: Int = begin

    init {
        require(begin in 0..end && end <= text.length) { "invalid range" }
    }

    override fun first(): Char {
        pos = begin
        return current()
    }

    override fun last(): Char {
        pos = if (end > begin) end - 1 else end
        return current()
    }

    override fun current(): Char = if (pos in begin until end) text[pos] else CharacterIterator.DONE

    override fun next(): Char {
        if (pos < end - 1) {
            pos++
            return text[pos]
        }
        pos = end
        return CharacterIterator.DONE
    }

    override fun previous(): Char {
        if (pos <= begin) return CharacterIterator.DONE
        pos--
        return text[pos]
    }

    override fun setIndex(position: Int): Char {
        require(position in begin..end) { "invalid position" }
        pos = position
        return current()
    }

    override fun getBeginIndex(): Int = begin

    override fun getEndIndex(): Int = end

    override fun getIndex(): Int = pos

    /** Shares the same [text] (never copies it). */
    override fun clone(): Any = CharSequenceCharacterIterator(text, begin, end).also { it.pos = pos }
}
