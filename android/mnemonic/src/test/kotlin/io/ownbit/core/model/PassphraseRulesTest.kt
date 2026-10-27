// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.model

import io.ownbit.core.jsengine.chain.JsChain
import io.ownbit.core.model.format.TextLength
import io.ownbit.core.model.wallet.PassphraseIssue
import io.ownbit.core.model.wallet.PassphraseRules
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.CharBuffer

/** The BIP39 passphrase input rules (iOS `BILPassphrase`). */
class PassphraseRulesTest {

    private fun check(p: String) = PassphraseRules.check(p)
    private fun check(p: String, c: String) = PassphraseRules.check(p, c)

    @Test fun `empty first field`() {
        assertEquals(PassphraseIssue.EMPTY, check(""))
        assertEquals(PassphraseIssue.EMPTY, check("", "x"))
        assertEquals("passphrase_error_empty", PassphraseIssue.EMPTY.messageKey)
    }

    @Test fun `exactly 100 user-perceived characters are accepted, 101 are too long`() {
        val units = listOf(
            "a", // ASCII
            "中", // CJK
            "é", // e + combining acute = one character
            "🇨🇳", // flag (two regional indicators) = one character
            "😀", // emoji outside the BMP (surrogate pair) = one character
            "❤️", // emoji + variation selector (Mn) = one character
        )
        for (unit in units) {
            val ok = unit.repeat(100)
            assertEquals(100, TextLength.graphemes(ok))
            assertNull("100 × $unit", check(ok))
            assertNull(check(ok, ok))
            assertTrue(PassphraseRules.acceptsInput(ok))
            val long = unit.repeat(101)
            assertEquals("101 × $unit", PassphraseIssue.TOO_LONG, check(long))
            assertFalse("a 101-character paste is refused whole", PassphraseRules.acceptsInput(long))
        }
        assertEquals(100, PassphraseRules.MAX_GRAPHEMES)
        assertEquals("passphrase_error_too_long", PassphraseIssue.TOO_LONG.messageKey)
    }

    @Test fun `a ZWJ emoji family counts as one character but is rejected like on iOS (Cf)`() {
        val family = "👨‍👩‍👧‍👦"
        assertEquals(1, TextLength.graphemes(family))
        assertEquals(100, TextLength.graphemes(family.repeat(100)))
        assertTrue(PassphraseRules.acceptsInput(family.repeat(100)))
        assertFalse(PassphraseRules.acceptsInput(family.repeat(101)))
        assertEquals(PassphraseIssue.INVALID_CHARACTER, check(family))
        assertEquals("length is checked before characters", PassphraseIssue.TOO_LONG, check(family.repeat(101)))
    }

    @Test fun `control, format, line and paragraph separators and lone surrogates are invalid`() {
        val forbidden = listOf(
            "\n", "\r", "\t", "\u0000", "\u007F", "\u0085", // Cc
            " ", " ", // Zl / Zp
            "‍", "‌", "﻿", "‎", "‏", "­", "⁠", // Cf (iOS controlCharacters)
            "\uD800", "\uDC00", // unpaired surrogates (Android only)
        )
        for (ch in forbidden) {
            val p = "ab${ch}cd"
            assertEquals("U+%04X".format(ch[0].code), PassphraseIssue.INVALID_CHARACTER, check(p))
            assertEquals(PassphraseIssue.INVALID_CHARACTER, check(p, p))
            assertTrue(PassphraseRules.isForbiddenCodePoint(ch.codePointAt(0)))
        }
        // A lone surrogate at either end.
        assertEquals(PassphraseIssue.INVALID_CHARACTER, check("abc\uD83D"))
        assertEquals(PassphraseIssue.INVALID_CHARACTER, check("\uDE00abc"))
        assertEquals("passphrase_error_invalid", PassphraseIssue.INVALID_CHARACTER.messageKey)
    }

    @Test fun `ordinary text, spaces, punctuation and the vectors' characters are allowed`() {
        for (p in listOf(
            "TREZOR", "  trezor  ", "　x ", "a\"b'c\\d", "Ｔｒｅｚｏｒ", "Ä é ñ", "😀 中文 テスト 한국어",
            "'); throw new Error('x'); //", "x", "-",
        )) {
            assertNull(p, check(p))
        }
        assertFalse(PassphraseRules.isForbiddenCodePoint(' '.code))
        assertFalse(PassphraseRules.isForbiddenCodePoint(0x3000))
        assertFalse(PassphraseRules.isForbiddenCodePoint(0x1F600))
    }

    @Test fun `issues come in iOS order and the mismatch check is last`() {
        assertEquals(PassphraseIssue.EMPTY, check("", ""))
        assertEquals(PassphraseIssue.TOO_LONG, check("a".repeat(100) + "\n", "x"))
        assertEquals(PassphraseIssue.INVALID_CHARACTER, check("a\n", "b"))
        assertEquals(PassphraseIssue.MISMATCH, check("abc", "abd"))
        assertEquals(PassphraseIssue.MISMATCH, check("abc", ""))
        assertNull(check("abc", "abc"))
        assertEquals("passphrase_error_mismatch", PassphraseIssue.MISMATCH.messageKey)
    }

    @Test fun `the confirmation matches by canonical equivalence (Swift ==), not by case`() {
        val nfc = "Café Ångström"
        val nfd = "Café Ångström"
        assertNull(check(nfc, nfd))
        assertNull(check(nfd, nfc))
        assertEquals(PassphraseIssue.MISMATCH, check("trezor", "TREZOR"))
        assertEquals(PassphraseIssue.MISMATCH, check("TREZOR", "ＴＲＥＺＯＲ")) // compatibility (NFKD) is not canonical
        assertEquals(PassphraseIssue.MISMATCH, check("a b", "a  b"))
        assertEquals(PassphraseIssue.MISMATCH, check(" a", "a"))
    }

    @Test fun `char buffers over CharArrays are checked in place`() {
        val p = "TREZOR".toCharArray()
        val c = "TREZOR".toCharArray()
        assertNull(PassphraseRules.check(CharBuffer.wrap(p), CharBuffer.wrap(c)))
        c[0] = 't'
        assertEquals(PassphraseIssue.MISMATCH, PassphraseRules.check(CharBuffer.wrap(p), CharBuffer.wrap(c)))
    }

    @Test fun `edge whitespace is only a warning`() {
        for (p in listOf(" a", "a ", "　a", "a ", "\ta", "a ", " ")) {
            assertTrue(p, PassphraseRules.hasEdgeWhitespace(p))
        }
        for (p in listOf("", "a", "a b", "a　b", "a\nb")) {
            assertFalse(p, PassphraseRules.hasEdgeWhitespace(p))
        }
        // Not an error: the spaces are part of the passphrase.
        assertNull(check("  trezor  ", "  trezor  "))
        assertEquals(PassphraseIssue.MISMATCH, check("  trezor  ", "trezor"))
    }

    @Test fun `TON and ADA are unsupported in a passphrase wallet`() {
        for (c in JsChain.entries) {
            assertEquals(c.name, c == JsChain.TON || c == JsChain.ADA, PassphraseRules.isUnsupported(c))
        }
    }
}
