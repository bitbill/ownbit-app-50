// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.crypto.testing

import java.io.File

/** The published word-list file (unit tests run with the module directory as working directory). */
object WordlistFixture {
    val file = File("../../js/bitcoinjs-lib-bridge/mnemonic_words.txt")
    val text: String by lazy { file.readText(Charsets.UTF_8) }
    val lines: List<String> by lazy { text.split('\n').filter { it.isNotEmpty() } }

    /** Word [index] of language block [block] exactly as stored in the file (NFKD). */
    fun word(block: Int, index: Int): String = lines[block * 2048 + index]
}
