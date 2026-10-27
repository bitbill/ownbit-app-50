// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.jsengine.chain

import io.ownbit.core.jsengine.bridge.JsBridge
import io.ownbit.core.jsengine.internal.JsAssetsPathHandler
import org.junit.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class PureChainRulesTest {

    @Test
    fun `private key normalization and format gate follow iOS`() {
        assertEquals("abc", PrivateKeyImporter.normalize("0xabc"))
        assertEquals("abc", PrivateKeyImporter.normalize("  abc\n"))
        assertEquals("0xabc", PrivateKeyImporter.normalize(" 0xabc ")) // iOS strips 0x before trimming
        // Bidi controls of a paste from an RTL context (LRI / LRM … RLM / PDI) are removed first.
        assertEquals("abc", PrivateKeyImporter.normalize("\u2066\u200E0xabc\u200F\u2069"))
        assertEquals("L1abc", PrivateKeyImporter.normalize("\u202AL1\u061Cabc\u202C"))
        val hex = "0123456789ABCDEF".repeat(4)
        assertEquals(hex.lowercase(), PrivateKeyImporter.checkFormat(PrivateKeyChain.ETH, hex))
        assertEquals(hex.lowercase(), PrivateKeyImporter.checkFormat(PrivateKeyChain.TRX, "0x$hex"))
        assertNull(PrivateKeyImporter.checkFormat(PrivateKeyChain.ETH, "KwDiBf89QgGbjEhKnhXJuH7LrciVrZi3qYjgd9M7rFU73sVHnoWn"))
        assertNull(PrivateKeyImporter.checkFormat(PrivateKeyChain.ETH, hex.dropLast(1)))
        assertEquals("L1abc", PrivateKeyImporter.checkFormat(PrivateKeyChain.BTC, "L1abc"))
        assertNull(PrivateKeyImporter.checkFormat(PrivateKeyChain.BTC, hex))
        assertEquals("SABC", PrivateKeyImporter.checkFormat(PrivateKeyChain.XLM, "SABC"))
        assertNull(PrivateKeyImporter.checkFormat(PrivateKeyChain.XLM, "GABC"))
        assertEquals("T1", PrivateKeyImporter.checkFormat(PrivateKeyChain.LTC, "T1"))
        assertEquals("Q1", PrivateKeyImporter.checkFormat(PrivateKeyChain.DOGE, "Q1"))
        assertEquals("X1", PrivateKeyImporter.checkFormat(PrivateKeyChain.DASH, "X1"))
        assertEquals("K1", PrivateKeyImporter.checkFormat(PrivateKeyChain.ZEC, "K1"))
        assertNull(PrivateKeyImporter.checkFormat(PrivateKeyChain.ZEC, "5abc"))
        assertEquals("5abc", PrivateKeyImporter.checkFormat(PrivateKeyChain.DGB, "5abc"))
        assertNull(PrivateKeyImporter.checkFormat(PrivateKeyChain.DGB, ""))
    }

    @Test
    fun `message pre-encoding matches iOS`() {
        assertEquals("say _QUOTE_OWNBIT_hi_QUOTE_OWNBIT__NEWLINE_OWNBIT_bye", JsBridge.encodeMessageForJs("say \"hi\"\nbye"))
        assertEquals("abc", JsBridge.strip0x("0xabc"))
        assertEquals("abc", JsBridge.strip0x("0Xabc"))
        assertEquals("abc", JsBridge.strip0x("abc"))
    }

    @Test
    fun `asset handler only serves safe js paths`() {
        assertTrue(JsAssetsPathHandler.isSafe("btc/index.html"))
        assertTrue(JsAssetsPathHandler.isSafe("host/ownbit-host.js"))
        assertFalse(JsAssetsPathHandler.isSafe("../secret"))
        assertFalse(JsAssetsPathHandler.isSafe("btc/../../x"))
        assertFalse(JsAssetsPathHandler.isSafe("/abs"))
        assertFalse(JsAssetsPathHandler.isSafe("btc//x"))
        assertFalse(JsAssetsPathHandler.isSafe(""))
        assertEquals("text/html", JsAssetsPathHandler.mimeTypeOf("btc/index.html"))
        assertEquals("text/javascript", JsAssetsPathHandler.mimeTypeOf("btc/bitcoinjs-lib-app.js"))
        assertNull(JsAssetsPathHandler.mimeTypeOf("btc/readme.txt"))
    }
}
