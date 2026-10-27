// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.crypto.bip39

/**
 * Why a mnemonic was rejected. Precedence (iOS `BILMnemonicIssue`):
 * [WordlistUnavailable] > [Empty] > [InvalidWords] > [InvalidCount] > [InvalidChecksum].
 */
sealed interface MnemonicIssue {
    /** The wordlist could not be loaded: **reject the import** (fail closed). */
    data object WordlistUnavailable : MnemonicIssue

    /** No words. */
    data object Empty : MnemonicIssue

    /**
     * Words not in any wordlist, or — when every word exists somewhere but no single language has them all —
     * the words that do not belong to the dominant language. Input order, duplicates removed.
     */
    class InvalidWords(val words: List<String>) : MnemonicIssue {
        override fun toString(): String = "InvalidWords(count=${words.size})"
        override fun equals(other: Any?): Boolean = other is InvalidWords && other.words == words
        override fun hashCode(): Int = words.hashCode()
    }

    /** Word count not in 12 / 15 / 18 / 21 / 24. */
    data class InvalidCount(val count: Int) : MnemonicIssue

    /** Every word is valid but the BIP39 checksum fails for every candidate language. */
    data object InvalidChecksum : MnemonicIssue
}

/**
 * Result of [Bip39Validator.check]. Carries recovery-phrase words: never log it (its `toString` is redacted).
 *
 * @property normalized words joined by a single ASCII space, lower-cased (`Locale.ROOT`) but **not** NFKD —
 *   this is the string to hand to JS (`validateMnemonic`, derivation) and to hash for duplicate detection.
 * @property words the tokens of [normalized].
 * @property invalidWords see [MnemonicIssue.InvalidWords] (empty when none).
 * @property language the language whose checksum passed; otherwise the best-matching language; null if unknown.
 * @property issue null when valid.
 */
class MnemonicCheckResult internal constructor(
    val normalized: String,
    val words: List<String>,
    val invalidWords: List<String>,
    val language: MnemonicLanguage?,
    val issue: MnemonicIssue?,
) {
    /** True when the local checks (wordlist, count, checksum) all pass. JS `validateMnemonic` is still final. */
    val isValid: Boolean get() = issue == null

    override fun toString(): String =
        "MnemonicCheckResult(words=${words.size}, invalid=${invalidWords.size}, language=$language, issue=$issue)"
}
