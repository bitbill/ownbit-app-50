// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.wallet.imports

import io.ownbit.core.crypto.bip39.Bip39Validator
import io.ownbit.core.crypto.bip39.MnemonicIssue
import io.ownbit.core.model.wallet.PassphraseIssue
import io.ownbit.core.model.wallet.PassphraseRules
import io.ownbit.core.wallet.internal.KeyDeriver
import java.nio.CharBuffer

/** Why a recovery phrase was rejected on import (iOS `BILImportWalletController.nextAction`). */
enum class MnemonicRejection {
    /** Empty input. */
    EMPTY,

    /** The BIP39 word lists could not be loaded: import is refused (fail closed). */
    WORDLIST_UNAVAILABLE,

    /** Only one token (no space). */
    NO_SPACE,

    /** Words not in any list ([MnemonicCheck.Rejected.invalidWords]). */
    UNKNOWN_WORDS,

    /** Word count not 12/15/18/21/24 ([MnemonicCheck.Rejected.wordCount]). */
    WORD_COUNT,

    /** The JS `validateMnemonic` checksum check failed (Electrum phrases are not supported). */
    CHECKSUM,

    /** A BIP39 passphrase was given but the passphrase fields are refused ([MnemonicCheck.Rejected.passphraseIssue]). */
    PASSPHRASE,
}

/** Result of [MnemonicImportCheck.check]. Carries recovery-phrase material: `toString` is redacted. */
sealed interface MnemonicCheck {
    /** [normalized] is the phrase to derive from: tokens joined by one space, lower case (`Locale.ROOT`), not NFKD. */
    class Accepted(val normalized: String) : MnemonicCheck {
        override fun toString(): String = "Accepted(<redacted>)"
    }

    /** [invalidWords] / [wordCount] / [passphraseIssue] are for the message only — never log them. */
    class Rejected(
        val reason: MnemonicRejection,
        val invalidWords: List<String> = emptyList(),
        val wordCount: Int = 0,
        val passphraseIssue: PassphraseIssue? = null,
    ) : MnemonicCheck {
        override fun toString(): String = "Rejected(reason=$reason, wordCount=$wordCount)"
    }
}

/**
 * The checks a typed or scanned recovery phrase passes before anything is derived from it, in iOS order: the native
 * word-list checks of [Bip39Validator] (word lists loaded, not empty, more than one token, every word known, word
 * count), then the bundle's `validateMnemonic` as the final checksum authority. With a BIP39 passphrase, the two
 * passphrase fields must pass [PassphraseRules] first, and the phrase must be BIP39 (the JS check) — Electrum phrases
 * have another algorithm. (In the app this is the first step of the import service; duplicate detection and the server
 * lookup that follow are not part of this repository.)
 */
class MnemonicImportCheck(
    private val validator: suspend () -> Bip39Validator,
    private val keys: KeyDeriver,
) {

    /**
     * Checks [text]; [passphrase] / [confirmation] are the two passphrase fields of a passphrase import (`null` for a
     * normal import). The caller owns and wipes the arrays.
     */
    suspend fun check(text: String, passphrase: CharArray? = null, confirmation: CharArray? = null): MnemonicCheck {
        if (passphrase != null) {
            PassphraseRules.check(CharBuffer.wrap(passphrase), CharBuffer.wrap(confirmation ?: CharArray(0)))?.let {
                return MnemonicCheck.Rejected(MnemonicRejection.PASSPHRASE, passphraseIssue = it)
            }
        }
        val check = validator().check(text)
        if (check.issue == MnemonicIssue.WordlistUnavailable) return MnemonicCheck.Rejected(MnemonicRejection.WORDLIST_UNAVAILABLE)
        if (check.issue == MnemonicIssue.Empty) return MnemonicCheck.Rejected(MnemonicRejection.EMPTY)
        val normalized = check.normalized
        if (!normalized.contains(' ')) return MnemonicCheck.Rejected(MnemonicRejection.NO_SPACE)
        if (check.invalidWords.isNotEmpty()) {
            return MnemonicCheck.Rejected(MnemonicRejection.UNKNOWN_WORDS, invalidWords = check.invalidWords)
        }
        if (check.words.size !in Bip39Validator.VALID_WORD_COUNTS) {
            return MnemonicCheck.Rejected(MnemonicRejection.WORD_COUNT, wordCount = check.words.size)
        }
        if (!keys.validateMnemonic(normalized)) return MnemonicCheck.Rejected(MnemonicRejection.CHECKSUM)
        return MnemonicCheck.Accepted(normalized)
    }
}
