// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.crypto.bip39

import io.ownbit.core.crypto.testing.WordlistFixture
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Tolerant detection + the iOS structured-payload pre-filter. */
class LooksLikeMnemonicTest {
    private val validator = Bip39Validator.fromWordlistText(WordlistFixture.text)
    private val twelve = "legal winner thank year wave sausage worth useful legal winner thank yellow"
    private val twentyFour = (List(23) { "abandon" } + "art").joinToString(" ")

    @Test
    fun mustBeTrue() {
        val cases = listOf(
            twelve,
            twentyFour,
            twelve.uppercase().replace(" ", "\n"),
            twelve.split(" ").mapIndexed { i, w -> "${i + 1}. $w" }.joinToString(" "),
            twelve.split(" ").mapIndexed { i, w -> "#${i + 1}: $w" }.joinToString("\n"),
            twelve.replace(" ", ","),
            twelve.replace(" ", ", "),
            twelve.replace(" ", "; "),
            twelve.replace("thank", "thnak"), // one typo
            "$twelve extra", // appended passphrase-like word
            "的的的的的的的的的的的在",
            "的、的、的、的、的、的、的、的、的、的、的、在",
            "的，的，的，的，的，的，的，的，的，的，的，在",
            (List(11) { WordlistFixture.word(MnemonicLanguage.JAPANESE.ordinal, 0) } + WordlistFixture.word(MnemonicLanguage.JAPANESE.ordinal, 3)).joinToString("　"),
        )
        for (case in cases) assertTrue(case, validator.looksLikeMnemonic(case))
    }

    @Test
    fun mustBeFalse() {
        val jsonArray = (0 until 8).joinToString(",", "[", "]") { """{"index":$it,"value":1000}""" }
        val prettyJson = (0 until 8).joinToString(",\n", "{\n", "\n}") { """  "index$it": "value"""" }
        val keyValue = (1..14).joinToString(",") { "amount=$it" }
        val cases = listOf(
            jsonArray,
            prettyJson,
            keyValue,
            "bitcoin:bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu?amount=0.001&label=abandon",
            "bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu",
            "0x9858EfFD232B4033E47d90003D41EC34EcaEda94",
            "5eb00bbddcf069084889a8ab9155568165f5c453ccb85e70811aaed6f6da5fc19a5ac40b389cd370d086206dec8aa6c43daea6690f20ad3d8d48b2d2ce9e38e4",
            "The quick brown fox jumps over the lazy dog while the band plays a song at night",
            List(4) { twentyFour }.joinToString(" "), // too long
            "abandon abandon abandon", // too few
            "",
            // Our own QR payloads:
            """bb_watch:{"btcxpub":"xpub6CUGRUo","btcchanxpub":"xpub6CUGRUp","walletid":"abandon","ethxpub":"xpub","extra":""}""",
            """bb_mswatch:{"btcxpub":"x","btcchanxpub":"y","walletid":"z","ethpub":"a","ethaddr":"b"}""",
            "ethereum:0x9858EfFD232B4033E47d90003D41EC34EcaEda94@1?value=1e18",
        )
        for (case in cases) assertFalse(case, validator.looksLikeMnemonic(case))
    }

    @Test
    fun structuredPayloadPreFilter_isExactlyTheIosSet() {
        // iOS BILMnemonicValidator.structuredPayloadCharacters = "{}[]\"'/\\=_@<>|&%$^~+*?"
        for (c in "{}[]\"'/\\=_@<>|&%$^~+*?") {
            assertFalse("'$c' must veto", validator.looksLikeMnemonic("$twelve $c"))
        }
        // Characters outside the iOS set do not veto (a phrase pasted with them must still be hidden).
        for (c in listOf('`', '!', '#', ':', '(', ')', '-')) {
            assertTrue("'$c' must not veto", validator.looksLikeMnemonic("$twelve $c"))
        }
    }
}
