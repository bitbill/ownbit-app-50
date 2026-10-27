// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.crypto.bip39

import java.security.MessageDigest
import java.text.BreakIterator
import java.util.Locale

/**
 * Offline BIP39 mnemonic validation — Kotlin port of iOS `BILMnemonicValidator`
 * (`iOS/Sources/OwnbitCore/Mnemonic/BILMnemonicValidator.swift`) with three Android pitfalls handled:
 *
 * 1. **NFKD**: wordlist lookups and the checksum use NFKD ([Bip39Wordlists.lookupKey]); outputs
 *    ([MnemonicCheckResult.normalized], invalid words) keep the input's form.
 * 2. **Locale.ROOT** lower-casing (Turkish dotless-i safe).
 * 3. **Fail closed**: when the wordlist is unavailable every [check] reports
 *    [MnemonicIssue.WordlistUnavailable] and [looksLikeMnemonic] is false.
 *
 * The checksum here is only the **local hint**; the final authority for import remains the JS bundle's
 * `validateMnemonic` (iOS behaviour — Electrum phrases stay unsupported).
 *
 * Pure JVM, immutable, thread-safe, no logging. Obtain the app instance from [Bip39ValidatorProvider];
 * tests can build one from text with [fromWordlistText].
 */
class Bip39Validator(private val wordlists: Bip39Wordlists?) {

    /** True only when all 8 × 2048 words were loaded. */
    val isLoaded: Boolean get() = wordlists != null

    // region normalize

    /**
     * Tokenizes [raw] exactly like iOS `tokens(_:)`: every Unicode blank (tab, CR/LF, U+3000, NBSP, BOM…) is a
     * separator (Android: bidi controls too, see [isSeparator]); lower-cased with `Locale.ROOT`; if every
     * non-separator character is a Han ideograph the text is split per character (Chinese mnemonics are typed without
     * spaces).
     */
    fun tokens(raw: String): List<String> {
        val spaced = StringBuilder(raw.length)
        var allHan = true
        var hasContent = false
        var i = 0
        while (i < raw.length) {
            val cp = raw.codePointAt(i)
            if (isSeparator(cp)) {
                spaced.append(' ')
            } else {
                spaced.appendCodePoint(cp)
                hasContent = true
                if (allHan && !isHan(cp)) allHan = false
            }
            i += Character.charCount(cp)
        }
        if (!hasContent) return emptyList()
        val pieces = spaced.toString().lowercase(Locale.ROOT).split(' ').filter { it.isNotEmpty() }
        if (allHan) return pieces.flatMap { it.codePointStrings() }
        return pieces
    }

    /** Tokens joined by one ASCII space (see [MnemonicCheckResult.normalized]). */
    fun normalize(raw: String): String = tokens(raw).joinToString(" ")

    // endregion

    // region check

    /** True when [word] (a single token) is in any of the 8 wordlists. */
    fun contains(word: String): Boolean {
        val lists = wordlists ?: return false
        val tokens = tokens(word)
        return tokens.size == 1 && Bip39Wordlists.lookupKey(tokens[0]) in lists.allWords
    }

    /**
     * Full local check. Issue precedence: wordlist unavailable > empty > invalid words > invalid count >
     * invalid checksum. Simplified/Traditional Chinese share ~1,300 characters, so the checksum is tried for
     * **every** language that contains all words.
     */
    fun check(raw: String): MnemonicCheckResult {
        val words = tokens(raw)
        val normalized = words.joinToString(" ")
        fun result(
            invalidWords: List<String> = emptyList(),
            language: MnemonicLanguage? = null,
            issue: MnemonicIssue?,
        ) = MnemonicCheckResult(normalized, words, invalidWords, language, issue)

        val lists = wordlists ?: return result(issue = MnemonicIssue.WordlistUnavailable)
        if (words.isEmpty()) return result(issue = MnemonicIssue.Empty)

        val keys = words.map(Bip39Wordlists::lookupKey)
        val languageCount = lists.indexes.size
        val matchCounts = IntArray(languageCount)
        for (key in keys) {
            for (language in 0 until languageCount) {
                if (lists.indexes[language].containsKey(key)) matchCounts[language]++
            }
        }
        // Languages that contain ALL words.
        val candidates = (0 until languageCount).filter { matchCounts[it] == words.size }

        var invalidWords = words.filterIndexed { index, _ -> keys[index] !in lists.allWords }.distinct()
        if (invalidWords.isEmpty() && candidates.isEmpty()) {
            // Every word exists somewhere but the phrase mixes languages: report the words that do not belong
            // to the dominant language (first language with the highest count, as iOS).
            var dominant = 0
            for (language in 0 until languageCount) {
                if (matchCounts[language] > matchCounts[dominant]) dominant = language
            }
            invalidWords = words.filterIndexed { index, _ -> !lists.indexes[dominant].containsKey(keys[index]) }.distinct()
            return result(
                invalidWords = invalidWords,
                language = MnemonicLanguage.entries[dominant],
                issue = MnemonicIssue.InvalidWords(invalidWords),
            )
        }

        // First language that knows every word, else the one that knows most of them.
        var bestGuess = candidates.firstOrNull()?.let { MnemonicLanguage.entries[it] }
        if (bestGuess == null) {
            val most = matchCounts.max()
            if (most > 0) bestGuess = MnemonicLanguage.entries[matchCounts.indexOfFirst { it == most }]
        }

        if (invalidWords.isNotEmpty()) {
            return result(invalidWords, bestGuess, MnemonicIssue.InvalidWords(invalidWords))
        }
        if (words.size !in VALID_WORD_COUNTS) {
            return result(language = bestGuess, issue = MnemonicIssue.InvalidCount(words.size))
        }
        for (language in candidates) {
            if (checksumPasses(keys, lists.indexes[language])) {
                return result(language = MnemonicLanguage.entries[language], issue = null)
            }
        }
        return result(language = bestGuess, issue = MnemonicIssue.InvalidChecksum)
    }

    /** Standard BIP39: 11 bits per word; the last ENT/32 bits equal the first bits of SHA-256(entropy). */
    private fun checksumPasses(keys: List<String>, index: Map<String, Int>): Boolean {
        val totalBits = keys.size * 11
        val checksumBits = totalBits / 33
        val entropyBytes = (totalBits - checksumBits) / 8
        if (checksumBits <= 0 || checksumBits > 8) return false
        val bytes = ByteArray((totalBits + 7) / 8)
        var bitOffset = 0
        for (key in keys) {
            val wordIndex = index[key] ?: return false
            for (bit in 0 until 11) {
                if ((wordIndex shr (10 - bit)) and 1 == 1) {
                    bytes[bitOffset / 8] = (bytes[bitOffset / 8].toInt() or (0x80 ushr (bitOffset % 8))).toByte()
                }
                bitOffset++
            }
        }
        // ENT is a multiple of 32 bits, so the checksum starts on a byte boundary.
        if (entropyBytes >= bytes.size) return false
        val shift = 8 - checksumBits
        val expected = (bytes[entropyBytes].toInt() and 0xFF) ushr shift
        val hash = MessageDigest.getInstance("SHA-256").digest(bytes.copyOf(entropyBytes))
        val actual = (hash[0].toInt() and 0xFF) ushr shift
        bytes.fill(0)
        hash.fill(0)
        return actual == expected
    }

    // endregion

    // region suggestions

    /**
     * English words starting with [prefix] (trimmed, lower-cased with `Locale.ROOT`), in wordlist order,
     * at most [limit]. Empty when the wordlist is unavailable or the prefix is blank.
     */
    fun englishSuggestions(prefix: String, limit: Int = SUGGESTION_LIMIT): List<String> {
        val lists = wordlists ?: return emptyList()
        if (limit <= 0) return emptyList()
        val lowered = Bip39Wordlists.lookupKey(
            prefix.trim { it.isWhitespace() || it == '\uFEFF' }.lowercase(Locale.ROOT),
        )
        if (lowered.isEmpty()) return emptyList()
        val out = ArrayList<String>(limit)
        for (word in lists.lists[MnemonicLanguage.ENGLISH.ordinal]) {
            if (word.startsWith(lowered)) {
                out.add(word)
                if (out.size >= limit) break
            }
        }
        return out
    }

    // endregion

    // region looksLikeMnemonic

    /**
     * Whether [raw] looks like a recovery phrase — used by the scanner / paste paths to avoid echoing one back
     * to the screen. Deliberately tolerant (numbering, comma lists, one typo, Chinese without spaces) but with
     * the iOS pre-filter that keeps structured payloads (JSON, URIs, key=value, base64…) out: longer than
     * [LOOSE_MAX_LENGTH] characters or containing any of `{ } [ ] " ' / \ = _ @ < > | & % $ ^ ~ + * ?` → false
     * (exactly the iOS set). False when the wordlist is unavailable.
     *
     * Rule: at least 12 tokens AND (≥ 11 consecutive wordlist words OR ≥ 80 % wordlist words).
     */
    fun looksLikeMnemonic(raw: String): Boolean {
        val lists = wordlists ?: return false
        if (raw.length > LOOSE_MAX_LENGTH * 8) return false
        if (raw.length > LOOSE_MAX_LENGTH && graphemeCount(raw) > LOOSE_MAX_LENGTH) return false
        if (raw.any { it in STRUCTURED_PAYLOAD_CHARACTERS }) return false
        val words = looseTokens(raw)
        if (words.size < 12) return false
        var validCount = 0
        var run = 0
        var longestRun = 0
        for (word in words) {
            if (Bip39Wordlists.lookupKey(word) in lists.allWords) {
                validCount++
                run++
                if (run > longestRun) longestRun = run
            } else {
                run = 0
            }
        }
        return longestRun >= 11 || validCount * 5 >= words.size * 4
    }

    /** Like [tokens] but also splits on `, ;，；、。` and strips non-letters around every piece (`1.`, `#3:`). */
    private fun looseTokens(raw: String): List<String> {
        val pieces = ArrayList<String>()
        val current = StringBuilder()
        val lowered = raw.lowercase(Locale.ROOT)
        var i = 0
        fun flush() {
            val word = trimNonLetters(current.toString())
            if (word.isNotEmpty()) pieces.add(word)
            current.setLength(0)
        }
        while (i < lowered.length) {
            val cp = lowered.codePointAt(i)
            if (isSeparator(cp) || cp in LOOSE_EXTRA_SEPARATORS) flush() else current.appendCodePoint(cp)
            i += Character.charCount(cp)
        }
        flush()
        val allHan = pieces.all { piece -> piece.codePoints().allMatch { isHan(it) } }
        if (allHan) return pieces.flatMap { it.codePointStrings() }
        return pieces
    }

    private fun trimNonLetters(piece: String): String {
        var start = 0
        var end = piece.length
        while (start < end) {
            val cp = piece.codePointAt(start)
            if (isLetterOrMark(cp)) break
            start += Character.charCount(cp)
        }
        while (end > start) {
            val cp = piece.codePointBefore(end)
            if (isLetterOrMark(cp)) break
            end -= Character.charCount(cp)
        }
        return piece.substring(start, end)
    }

    // endregion

    companion object {
        /** Accepted word counts. */
        val VALID_WORD_COUNTS: Set<Int> = setOf(12, 15, 18, 21, 24)

        /** Default number of suggestions (iOS `mnemonicSuggestionLimit`). */
        const val SUGGESTION_LIMIT = 12

        /** [looksLikeMnemonic] ignores anything longer (24 numbered, comma-separated words stay well below). */
        const val LOOSE_MAX_LENGTH = 600

        /** iOS `structuredPayloadCharacters`, character for character. */
        private const val STRUCTURED_PAYLOAD_CHARACTERS = "{}[]\"'/\\=_@<>|&%$^~+*?"

        private val LOOSE_EXTRA_SEPARATORS = setOf(
            ','.code, ';'.code, 0xFF0C, 0xFF1B, 0x3001, 0x3002, 0x3000, 0xFEFF,
        )

        /** Builds a validator from the combined wordlist text (fails closed on malformed text). */
        fun fromWordlistText(text: String?): Bip39Validator = Bip39Validator(text?.let(Bip39Wordlists::parse))

        /**
         * iOS `CharacterSet.whitespacesAndNewlines` (Unicode Z* + U+0009…U+000D + U+0085) plus U+3000, the BOM
         * U+FEFF and the Unicode bidi controls ([isBidiControl]).
         */
        internal fun isSeparator(cp: Int): Boolean {
            if (cp in 0x09..0x0D || cp == 0x85 || cp == 0x3000 || cp == 0xFEFF) return true
            if (isBidiControl(cp)) return true
            return when (Character.getType(cp).toByte()) {
                Character.SPACE_SEPARATOR, Character.LINE_SEPARATOR, Character.PARAGRAPH_SEPARATOR -> true
                else -> false
            }
        }

        /**
         * ALM, LRM / RLM, LRE…RLO and LRI…PDI: invisible, never part of a word, but text pasted from a right-to-left
         * context (Arabic UI, 5.0.1) can carry them around the words. Android addition — iOS keeps them inside the
         * token, which turns a correct word into an "invalid" one that looks identical.
         */
        internal fun isBidiControl(cp: Int): Boolean =
            cp == 0x061C || cp == 0x200E || cp == 0x200F || cp in 0x202A..0x202E || cp in 0x2066..0x2069

        /** CJK Unified Ideographs, Extension A, Compatibility Ideographs, Extension B… + Compatibility Supplement. */
        internal fun isHan(cp: Int): Boolean =
            cp in 0x4E00..0x9FFF || cp in 0x3400..0x4DBF || cp in 0xF900..0xFAFF || cp in 0x20000..0x2FA1F

        /** iOS `CharacterSet.letters`: general categories L* and M*. */
        private fun isLetterOrMark(cp: Int): Boolean = when (Character.getType(cp).toByte()) {
            Character.UPPERCASE_LETTER, Character.LOWERCASE_LETTER, Character.TITLECASE_LETTER,
            Character.MODIFIER_LETTER, Character.OTHER_LETTER,
            Character.NON_SPACING_MARK, Character.ENCLOSING_MARK, Character.COMBINING_SPACING_MARK,
            -> true
            else -> false
        }

        private fun String.codePointStrings(): List<String> {
            val out = ArrayList<String>(length)
            var i = 0
            while (i < length) {
                val cp = codePointAt(i)
                out.add(String(Character.toChars(cp)))
                i += Character.charCount(cp)
            }
            return out
        }

        /** Number of user-perceived characters (Swift `String.count`). */
        internal fun graphemeCount(text: String): Int {
            val it = BreakIterator.getCharacterInstance(Locale.ROOT)
            it.setText(text)
            var count = 0
            while (it.next() != BreakIterator.DONE) count++
            return count
        }
    }
}
