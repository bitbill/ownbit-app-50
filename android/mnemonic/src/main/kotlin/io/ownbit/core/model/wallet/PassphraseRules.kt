// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.model.wallet

import io.ownbit.core.jsengine.chain.JsChain
import io.ownbit.core.model.format.TextLength
import java.text.Normalizer

/**
 * Why the BIP39 passphrase fields of the mnemonic import are refused (iOS `BILPassphrase.validationError` + the
 * two-field mismatch check). [messageKey] is the iOS string key.
 */
enum class PassphraseIssue(val messageKey: String) {
    /** Nothing typed in the first field. */
    EMPTY("passphrase_error_empty"),

    /** More than [PassphraseRules.MAX_GRAPHEMES] characters (format argument = that number). */
    TOO_LONG("passphrase_error_too_long"),

    /** A control / format character, U+2028 / U+2029 or an unpaired surrogate ([PassphraseRules.isForbiddenCodePoint]). */
    INVALID_CHARACTER("passphrase_error_invalid"),

    /** The confirmation differs from the first field. */
    MISMATCH("passphrase_error_mismatch"),
}

/**
 * BIP39 passphrase ("25th word") rules of the mnemonic import (iOS `WalletModel+Passphrase.swift` `BILPassphrase`;
 * `iOS/Sources/OwnbitCore/Vault/PassphrasePolicy.swift` in this repository). The passphrase itself is a secret: callers pass it as a `CharArray` view
 * (`CharBuffer.wrap`) where they can; nothing here keeps or logs it.
 */
object PassphraseRules {

    /** Longest accepted passphrase in user-perceived characters (iOS `maxLength`, Ledger uses the same). */
    const val MAX_GRAPHEMES: Int = 100

    /**
     * Checks the first field in iOS order: [PassphraseIssue.EMPTY] → [PassphraseIssue.TOO_LONG] (graphemes,
     * [TextLength.graphemes] = Swift `count`) → [PassphraseIssue.INVALID_CHARACTER]. Edge spaces are part of the
     * passphrase and never trimmed ([hasEdgeWhitespace] is a warning only).
     */
    fun check(passphrase: CharSequence): PassphraseIssue? {
        if (passphrase.isEmpty()) return PassphraseIssue.EMPTY
        if (TextLength.graphemes(passphrase) > MAX_GRAPHEMES) return PassphraseIssue.TOO_LONG
        if (containsForbidden(passphrase)) return PassphraseIssue.INVALID_CHARACTER
        return null
    }

    /**
     * [check] of the first field, then [PassphraseIssue.MISMATCH] when [confirmation] differs. Equality is canonical
     * equivalence like Swift `==` (both sides NFC-normalised), so an NFC field and an NFD field of the same text match;
     * a case difference is a mismatch. The seed is always computed from the first field as typed.
     */
    fun check(passphrase: CharSequence, confirmation: CharSequence): PassphraseIssue? {
        check(passphrase)?.let { return it }
        return if (canonicallyEqual(passphrase, confirmation)) null else PassphraseIssue.MISMATCH
    }

    /**
     * Input filter of both fields (iOS `shouldChangeCharactersIn`): an edit whose result [candidate] is longer than
     * [MAX_GRAPHEMES] is refused whole (a longer paste is not truncated).
     */
    fun acceptsInput(candidate: CharSequence): Boolean = TextLength.graphemes(candidate) <= MAX_GRAPHEMES

    /**
     * Whether the first or last code point is whitespace (iOS `CharacterSet.whitespaces` = Unicode Zs + U+0009):
     * shown as an orange warning only, the passphrase is used as typed.
     */
    fun hasEdgeWhitespace(passphrase: CharSequence): Boolean {
        if (passphrase.isEmpty()) return false
        val first = Character.codePointAt(passphrase, 0)
        val last = Character.codePointBefore(passphrase, passphrase.length)
        return isWhitespace(first) || isWhitespace(last)
    }

    /**
     * Characters a passphrase may not contain (iOS parity): `CharacterSet.controlCharacters` = Unicode
     * Cc ∪ Cf (so also ZWJ / ZWNJ / LRM / BOM / soft hyphen), U+2028, U+2029, and — Android only, a Swift string cannot
     * hold one — an unpaired surrogate (the JS engine would turn it into U+FFFD, a seed no other platform reproduces).
     */
    fun isForbiddenCodePoint(codePoint: Int): Boolean = when (Character.getType(codePoint).toByte()) {
        Character.CONTROL, Character.FORMAT, Character.SURROGATE -> true
        else -> codePoint == LINE_SEPARATOR || codePoint == PARAGRAPH_SEPARATOR
    }

    /**
     * Chains a passphrase wallet can never enable (iOS `BILPassphrase.unsupportedCoinTypes`): TON (with its Jettons) and
     * ADA derive their keys from the mnemonic **words**, not from the seed ([io.ownbit.core.jsengine.chain.ChainKeyDerivation]),
     * so the passphrase would not protect them.
     */
    fun isUnsupported(chain: JsChain): Boolean = chain == JsChain.TON || chain == JsChain.ADA

    private fun containsForbidden(text: CharSequence): Boolean {
        var i = 0
        while (i < text.length) {
            val cp = Character.codePointAt(text, i)
            if (isForbiddenCodePoint(cp)) return true
            i += Character.charCount(cp)
        }
        return false
    }

    private fun isWhitespace(codePoint: Int): Boolean =
        codePoint == TAB || Character.getType(codePoint).toByte() == Character.SPACE_SEPARATOR

    private fun canonicallyEqual(a: CharSequence, b: CharSequence): Boolean {
        if (a.length == b.length && a.indices.all { a[it] == b[it] }) return true
        return Normalizer.normalize(a, Normalizer.Form.NFC) == Normalizer.normalize(b, Normalizer.Form.NFC)
    }

    private const val TAB = 0x0009
    private const val LINE_SEPARATOR = 0x2028
    private const val PARAGRAPH_SEPARATOR = 0x2029
}
