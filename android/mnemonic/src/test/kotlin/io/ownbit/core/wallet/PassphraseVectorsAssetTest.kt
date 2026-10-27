// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.wallet

import io.ownbit.core.model.wallet.PassphraseIssue
import io.ownbit.core.model.wallet.PassphraseRules
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Test
import java.io.File
import java.security.MessageDigest
import kotlin.test.assertEquals
import kotlin.test.assertNull

/**
 * The BIP39 passphrase vectors shared with iOS (`passphrase_vectors.json`, public
 * mnemonics only, every seed / address computed by an independent BIP39/BIP32/SLIP-10 implementation). In the app an
 * instrumented test derives every vector through the WebView engine; here the vectors the UI could produce pass
 * [PassphraseRules], while the `(bridge)` ones are refused by it (they only test the JS bridge).
 */
class PassphraseVectorsAssetTest {

    private val file = File("src/test/resources/passphrase_vectors.json")

    @Test fun `the vectors file is unchanged`() {
        val md5 = MessageDigest.getInstance("MD5").digest(file.readBytes()).joinToString("") { "%02x".format(it) }
        assertEquals("a4213c58b1f74fc6a77d5a93a68bea40", md5)
    }

    @Test fun `the vectors agree with the input rules`() {
        val vectors = Json.parseToJsonElement(file.readText()).jsonObject["vectors"]!!.jsonArray.map { it.jsonObject }
        assertEquals(15, vectors.size)
        for (v in vectors) {
            val name = v["name"]!!.jsonPrimitive.content
            val p = v["passphrase"]!!.jsonPrimitive.content
            // The JSON string and the listed scalars are the same value.
            val scalars = v["passphraseCodepoints"]!!.jsonArray.map { it.jsonPrimitive.content.removePrefix("U+").toInt(16) }
            assertEquals(scalars, p.codePoints().toArray().toList(), name)
            val expected = when {
                name.endsWith("(bridge)") -> PassphraseIssue.INVALID_CHARACTER
                p.isEmpty() -> PassphraseIssue.EMPTY
                else -> null
            }
            assertEquals(expected, PassphraseRules.check(p, p), name)
            if (expected == null) assertNull(PassphraseRules.check(p), name)
        }
    }
}
