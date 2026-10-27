// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.crypto.bip39

import io.ownbit.core.crypto.hash.Hashes
import io.ownbit.core.crypto.testing.WordlistFixture
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.BeforeClass
import org.junit.Test
import java.text.Normalizer
import java.util.Locale

class Bip39ValidatorTest {

    companion object {
        lateinit var validator: Bip39Validator

        @BeforeClass
        @JvmStatic
        fun load() {
            validator = Bip39Validator.fromWordlistText(WordlistFixture.text)
        }

        /** 12-word all-zero-entropy vector of a language: word[0] × 11 + word[3] (checksum nibble 0b0011). */
        fun zero12(block: Int, separator: String = " "): String =
            (List(11) { WordlistFixture.word(block, 0) } + WordlistFixture.word(block, 3)).joinToString(separator)

        /** 24-word all-zero-entropy vector: word[0] × 23 + word[102] (8-bit checksum 0x66). */
        fun zero24(block: Int): String =
            (List(23) { WordlistFixture.word(block, 0) } + WordlistFixture.word(block, 102)).joinToString(" ")
    }

    @Test
    fun wordlistAsset_isTheIosFile() {
        assertEquals(
            "aad29f1e4cba8259f80e49ef0630e438af0c893e07a8d5a4e5b822085e71104a",
            Hashes.sha256Hex(WordlistFixture.file.readBytes()),
        )
        assertTrue(validator.isLoaded)
    }

    // region rule table

    @Test
    fun englishVectors() {
        val about = validator.check("abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about")
        assertTrue(about.isValid)
        assertEquals(MnemonicLanguage.ENGLISH, about.language)
        assertTrue(validator.check("legal winner thank year wave sausage worth useful legal winner thank yellow").isValid)
        assertTrue(validator.check((List(23) { "abandon" } + "art").joinToString(" ")).isValid)
        assertEquals(MnemonicIssue.InvalidChecksum, validator.check(List(12) { "abandon" }.joinToString(" ")).issue)
    }

    @Test
    fun koreanNfcInput_isNormalizedToNfkdForLookup() {
        val nfd = zero12(MnemonicLanguage.KOREAN.ordinal)
        val nfc = Normalizer.normalize(nfd, Normalizer.Form.NFC)
        assertTrue("fixture really is NFC", nfc != nfd)
        val result = validator.check(nfc)
        assertTrue(result.issue.toString(), result.isValid)
        assertEquals(MnemonicLanguage.KOREAN, result.language)
        // NFKD is only used for lookups: the output keeps the input's (NFC) form.
        assertEquals(nfc, result.normalized)
    }

    @Test
    fun chineseWithoutSpaces_isSplitPerCharacter() {
        val words = zero12(MnemonicLanguage.CHINESE_SIMPLIFIED.ordinal, separator = "")
        assertEquals("的的的的的的的的的的的在", words)
        val result = validator.check(words)
        assertTrue(result.isValid)
        assertEquals(12, result.words.size)
        assertEquals("的 的 的 的 的 的 的 的 的 的 的 在", result.normalized)
        // Shared characters: first language whose checksum passes.
        assertEquals(MnemonicLanguage.CHINESE_SIMPLIFIED, result.language)
        assertTrue(validator.check("的 的 的 的 的 的 的 的 的 的 的 在").isValid)
    }

    @Test
    fun turkishDefaultLocale_doesNotBreakLowercasing() {
        val saved = Locale.getDefault()
        try {
            Locale.setDefault(Locale.forLanguageTag("tr-TR"))
            val upper = "LEGAL WINNER THANK YEAR WAVE SAUSAGE WORTH USEFUL LEGAL WINNER THANK YELLOW"
            assertTrue("default lower-casing would produce a dotless i", upper.lowercase(Locale.getDefault()).contains('ı'))
            val result = validator.check(upper)
            assertTrue(result.issue.toString(), result.isValid)
            assertEquals("legal winner thank year wave sausage worth useful legal winner thank yellow", result.normalized)
        } finally {
            Locale.setDefault(saved)
        }
    }

    @Test
    fun wordlistUnavailable_rejects() {
        for (broken in listOf(
            Bip39Validator.fromWordlistText(null),
            Bip39Validator.fromWordlistText(""),
            // one line missing
            Bip39Validator.fromWordlistText(WordlistFixture.lines.drop(1).joinToString("\n")),
            // duplicate inside a block
            Bip39Validator.fromWordlistText((listOf(WordlistFixture.lines[1]) + WordlistFixture.lines.drop(1)).joinToString("\n")),
        )) {
            assertFalse(broken.isLoaded)
            val result = broken.check("abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about")
            assertEquals(MnemonicIssue.WordlistUnavailable, result.issue)
            assertFalse(result.isValid)
            assertFalse(broken.looksLikeMnemonic("abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"))
            assertTrue(broken.englishSuggestions("ab").isEmpty())
            assertFalse(broken.contains("abandon"))
        }
    }

    // endregion

    @Test
    fun allEightLanguages_zeroEntropyVectors() {
        for (language in MnemonicLanguage.entries) {
            val r12 = validator.check(zero12(language.ordinal))
            assertTrue("$language 12: ${r12.issue}", r12.isValid)
            val r24 = validator.check(zero24(language.ordinal))
            assertTrue("$language 24: ${r24.issue}", r24.isValid)
            if (language != MnemonicLanguage.CHINESE_TRADITIONAL) {
                // Traditional's first words are shared with Simplified, which is tried first.
                assertEquals(language, r12.language)
            }
            // Wrong checksum word.
            val wrong = (List(11) { WordlistFixture.word(language.ordinal, 0) } + WordlistFixture.word(language.ordinal, 4)).joinToString(" ")
            assertEquals("$language", MnemonicIssue.InvalidChecksum, validator.check(wrong).issue)
        }
    }

    @Test
    fun wordlistFileCrlfAndBom_areAccepted() {
        val crlf = "﻿" + WordlistFixture.lines.joinToString("\r\n") + "\r\n"
        assertTrue(Bip39Validator.fromWordlistText(crlf).isLoaded)
    }

    @Test
    fun japaneseIdeographicSpaceSeparator() {
        val jp = zero12(MnemonicLanguage.JAPANESE.ordinal, separator = "　")
        val result = validator.check(Normalizer.normalize(jp, Normalizer.Form.NFC))
        assertTrue(result.isValid)
        assertEquals(MnemonicLanguage.JAPANESE, result.language)
        assertFalse(result.normalized.contains('　'))
        assertEquals(11, result.normalized.count { it == ' ' })
    }

    @Test
    fun separatorsAreNormalized() {
        val messy = "﻿  ABANDON\tabandon\r\nabandon abandon　abandon  abandon\nabandon abandon abandon abandon abandon About \n"
        val result = validator.check(messy)
        assertTrue(result.isValid)
        assertEquals("abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about", result.normalized)
        assertEquals(result.normalized, validator.normalize(messy))
    }

    @Test
    fun bidiControls_areSeparators() {
        val plain = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
        // LRI … PDI around the phrase, LRM / RLM / ALM around words (a paste from an RTL context).
        val pasted = "\u2066\u200Eabandon\u200E abandon\u200F abandon\u061C " +
            "abandon abandon abandon abandon abandon abandon abandon abandon \u202Aabout\u202C\u2069"
        val result = validator.check(pasted)
        assertTrue(result.issue.toString(), result.isValid)
        assertEquals(plain, result.normalized)
        // Without spaces the controls alone separate the words.
        assertEquals(listOf("abandon", "about"), validator.tokens("abandon\u200Fabout"))
        val saved = Locale.getDefault()
        try {
            Locale.setDefault(Locale.forLanguageTag("ar"))
            assertEquals(plain, validator.check(pasted).normalized)
        } finally {
            Locale.setDefault(saved)
        }
    }

    @Test
    fun issuesAndPrecedence() {
        assertEquals(MnemonicIssue.Empty, validator.check("").issue)
        assertEquals(MnemonicIssue.Empty, validator.check(" \n\t　").issue)

        val typo = validator.check("abandon abandn abandon abandon abandon abandon abandon abandon abandon abandon abandon abuot")
        assertEquals(MnemonicIssue.InvalidWords(listOf("abandn", "abuot")), typo.issue)
        assertEquals(listOf("abandn", "abuot"), typo.invalidWords)
        assertEquals(MnemonicLanguage.ENGLISH, typo.language)

        // invalid words win over count
        assertEquals(MnemonicIssue.InvalidWords(listOf("xyz")), validator.check("abandon xyz").issue)
        // duplicates removed, input order kept
        assertEquals(listOf("zzz", "yyy"), validator.check("zzz abandon yyy zzz").invalidWords)

        assertEquals(MnemonicIssue.InvalidCount(11), validator.check(List(11) { "abandon" }.joinToString(" ")).issue)
        assertEquals(MnemonicIssue.InvalidCount(13), validator.check(List(13) { "abandon" }.joinToString(" ")).issue)
    }

    @Test
    fun mixedLanguages_reportWordsOutsideTheDominantLanguage() {
        val english = WordlistFixture.lines.subList(0, 2048)
        val others = WordlistFixture.lines.subList(2048, WordlistFixture.lines.size).toSet()
        // "abandon" is also a French word, so pick English words that exist in no other list.
        val englishOnly = english.filter { it !in others }.take(11)
        val spanishOnly = WordlistFixture.lines
            .subList(MnemonicLanguage.SPANISH.ordinal * 2048, (MnemonicLanguage.SPANISH.ordinal + 1) * 2048)
            .first { it !in english && Normalizer.normalize(it, Normalizer.Form.NFC) == it }
        val result = validator.check((englishOnly + spanishOnly).joinToString(" "))
        assertEquals(MnemonicLanguage.ENGLISH, result.language)
        assertEquals(MnemonicIssue.InvalidWords(listOf(spanishOnly)), result.issue)
    }

    @Test
    fun containsAndSuggestions() {
        assertTrue(validator.contains("abandon"))
        assertTrue(validator.contains(" ABANDON "))
        assertTrue(validator.contains(Normalizer.normalize(WordlistFixture.word(MnemonicLanguage.KOREAN.ordinal, 0), Normalizer.Form.NFC)))
        assertFalse(validator.contains("abandon about"))
        assertFalse(validator.contains("bitcoin"))

        assertEquals(listOf("abandon", "ability", "able", "about", "above", "absent", "absorb", "abstract", "absurd", "abuse", "access", "accident"), validator.englishSuggestions("a"))
        assertEquals(listOf("abandon"), validator.englishSuggestions("ABAN"))
        assertEquals(listOf("zebra", "zero"), validator.englishSuggestions("ze", limit = 2))
        assertTrue(validator.englishSuggestions("").isEmpty())
        assertTrue(validator.englishSuggestions("qqq").isEmpty())
        assertTrue(validator.englishSuggestions("a", limit = 0).isEmpty())
    }

    @Test
    fun resultToString_neverContainsWords() {
        val result = validator.check("legal winner thank year wave sausage worth useful legal winner thank yellow")
        assertFalse(result.toString().contains("legal"))
        assertFalse(validator.check("legal winnr").toString().contains("winnr"))
        assertNull(result.issue)
    }
}
