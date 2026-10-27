// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.model.format

import java.text.BreakIterator

/**
 * Character counting that matches Swift's `String.count` (user-perceived characters / grapheme clusters) as
 * closely as the platform allows. On Android `java.text.BreakIterator` is ICU-backed and grapheme-accurate.
 */
object TextLength {

    /**
     * Number of user-perceived characters in [text] (Swift `String.count`). A non-`String` [text] (e.g. a password's
     * `CharBuffer.wrap(chars)`) is read in place through [CharSequenceCharacterIterator], without a `String` copy.
     */
    fun graphemes(text: CharSequence): Int {
        if (text.isEmpty()) return 0
        val it = BreakIterator.getCharacterInstance()
        if (text is String) it.setText(text) else it.setText(CharSequenceCharacterIterator(text))
        var count = 0
        while (it.next() != BreakIterator.DONE) count++
        return count
    }

    /** UTF-8 byte length (Swift `text.utf8.count`), used by memo / tag limits. */
    fun utf8Bytes(text: String): Int = text.toByteArray(Charsets.UTF_8).size
}
