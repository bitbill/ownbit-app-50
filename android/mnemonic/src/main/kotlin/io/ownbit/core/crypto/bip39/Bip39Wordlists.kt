// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.crypto.bip39

import java.text.Normalizer

/** BIP39 languages, in the order of the 2048-line blocks of `mnemonic_words.txt` (iOS `BILMnemonicLanguage`). */
enum class MnemonicLanguage {
    ENGLISH,
    CHINESE_SIMPLIFIED,
    JAPANESE,
    CHINESE_TRADITIONAL,
    SPANISH,
    KOREAN,
    FRENCH,
    ITALIAN,
}

/**
 * The 8 official BIP39 wordlists, parsed from the combined `mnemonic_words.txt` (8 × 2048 lines, block order
 * = [MnemonicLanguage]; the same file iOS and the old Android app ship — `js/bitcoinjs-lib-bridge/mnemonic_words.txt`
 * in this repository, SHA-256 `aad29f1e4cba8259f80e49ef0630e438af0c893e07a8d5a4e5b822085e71104a`).
 *
 * Words are stored NFKD-normalized (the file already is: all 2048 Korean words are decomposed jamo, and
 * hundreds of Japanese/Spanish/French words carry combining marks). Lookups must normalize their input with
 * [lookupKey] first, because input methods produce NFC.
 *
 * Immutable and thread-safe.
 */
class Bip39Wordlists private constructor(
    /** 8 lists of 2048 NFKD words, index == [MnemonicLanguage.ordinal]. */
    internal val lists: List<List<String>>,
    /** per language: NFKD word -> 11-bit index */
    internal val indexes: List<Map<String, Int>>,
    /** every word of every language (NFKD) */
    internal val allWords: Set<String>,
) {
    /** The 2048 words of [language] (NFKD). */
    fun words(language: MnemonicLanguage): List<String> = lists[language.ordinal]

    companion object {
        /** Words per language. */
        const val WORDS_PER_LANGUAGE = 2048

        /** Asset path of the combined wordlist file inside this module. */
        const val ASSET_PATH = "bip39/mnemonic_words.txt"

        /**
         * Parses the combined wordlist text (LF or CRLF, optional BOM). Returns `null` — i.e. "wordlist
         * unavailable", which must reject imports — unless there are exactly 8 × 2048 non-empty lines and no
         * duplicate inside a language block.
         */
        fun parse(text: String): Bip39Wordlists? {
            val languages = MnemonicLanguage.entries.size
            val lines = ArrayList<String>(languages * WORDS_PER_LANGUAGE)
            for (raw in text.split('\n')) {
                val word = raw.trim { it.isWhitespace() || it == '\uFEFF' || it == '\r' }
                if (word.isNotEmpty()) lines.add(lookupKey(word))
            }
            if (lines.size != languages * WORDS_PER_LANGUAGE) return null
            val lists = ArrayList<List<String>>(languages)
            val indexes = ArrayList<Map<String, Int>>(languages)
            val all = HashSet<String>(lines.size * 2)
            for (language in 0 until languages) {
                val list = lines.subList(language * WORDS_PER_LANGUAGE, (language + 1) * WORDS_PER_LANGUAGE).toList()
                val map = HashMap<String, Int>(WORDS_PER_LANGUAGE * 2)
                list.forEachIndexed { index, word -> map[word] = index }
                // A duplicated word inside one block means the file is damaged.
                if (map.size != WORDS_PER_LANGUAGE) return null
                lists.add(list)
                indexes.add(map)
                all.addAll(list)
            }
            return Bip39Wordlists(lists, indexes, all)
        }

        /** Normalization used for every wordlist lookup and checksum computation (NFKD). */
        fun lookupKey(word: String): String = Normalizer.normalize(word, Normalizer.Form.NFKD)
    }
}
