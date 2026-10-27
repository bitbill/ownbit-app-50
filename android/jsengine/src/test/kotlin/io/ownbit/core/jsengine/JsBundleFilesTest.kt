// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.jsengine

import org.junit.Test
import java.io.File
import java.security.MessageDigest
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * The bundles the Android engine loads (`assets/js/<JsBundle.id>/<file>` in the app) against the published files in
 * `../js` (the table of `android/README.md`):
 *
 * - [Relation.IDENTICAL]: the `js/` file is the Android asset, byte for byte;
 * - [Relation.REDACTED]: the `js/` file is the Android asset with the placeholder replacements of `js/tools/redact.py`
 *   (same length; the Android SHA-256 is the "app copy" SHA-256 that `js/README.md` lists for that file);
 * - [Relation.NOT_PUBLISHED]: Android ships another build than iOS; not in this repository (SHA-256 for reference).
 *
 * Besides the bundles, the app's `assets/js/` holds Ownbit's host shim (`host/ownbit-host.js`) and one loader page per
 * bundle directory (`<id>/index.html`); see `android/README.md`.
 */
class JsBundleFilesTest {

    enum class Relation { IDENTICAL, REDACTED, NOT_PUBLISHED }

    class Asset(val androidPath: String, val sha256: String, val bytes: Long, val jsPath: String?, val relation: Relation)

    private val js = File("../../js")

    @Test
    fun `identical bundles are the published files`() {
        for (a in ASSETS.filter { it.relation == Relation.IDENTICAL }) {
            val file = File(js, a.jsPath!!)
            assertTrue(file.isFile, "missing ${file.path}")
            assertEquals(a.sha256, sha256(file), a.androidPath)
            assertEquals(a.bytes, file.length(), a.androidPath)
        }
    }

    @Test
    fun `redacted bundles keep their length and js README lists the Android file as the app copy`() {
        val readme = File(js, "README.md").readText()
        for (a in ASSETS.filter { it.relation == Relation.REDACTED }) {
            val file = File(js, a.jsPath!!)
            assertTrue(file.isFile, "missing ${file.path}")
            assertEquals(a.bytes, file.length(), "${a.androidPath}: placeholders have the replaced string's length")
            val row = readme.lines().single { it.contains("| ${a.jsPath!!.substringAfter('/')} |") && it.startsWith("| ${a.jsPath.substringBefore('/')} ") }
            assertTrue("app copy `${a.sha256}`" in row, "${a.androidPath}: $row")
        }
    }

    @Test
    fun `unpublished bundles are not in js`() {
        val published = js.walkTopDown().filter { it.isFile && (it.extension == "js") }.map { sha256(it) }.toSet()
        for (a in ASSETS.filter { it.relation == Relation.NOT_PUBLISHED }) {
            assertTrue(a.sha256 !in published, "${a.androidPath} is published after all")
        }
    }

    @Test
    fun `every engine bundle has its files in the table`() {
        for (bundle in JsBundle.entries) {
            assertTrue(ASSETS.any { it.androidPath.startsWith("${bundle.id}/") }, "no file for ${bundle.id}")
        }
        assertEquals(ASSETS.size, ASSETS.map { it.androidPath }.toSet().size)
    }

    private fun sha256(file: File): String =
        MessageDigest.getInstance("SHA-256").digest(file.readBytes()).joinToString("") { "%02x".format(it) }

    companion object {
        val ASSETS: List<Asset> = listOf(
            Asset("ada/shelley.bundle.js", "85beb27eb5373fa1dbc90555933535454a52d0b3c725e025fa1536f4782c5cc4", 2914124, null, Relation.NOT_PUBLISHED),
            Asset("bch/bitcoincashjs-lib-app.min.js", "d6490cedd851235e38d2e0cf958f9ca921a18941e39e4ec0eeaa8fa686d2b56a", 1000285, "bitcoincashjs-lib-bridge/bitcoincashjs-lib-app.min.js", Relation.IDENTICAL),
            Asset("btc/bitcoinjs-lib-app.js", "bf27b88640bc4a57cef1c76ef9dbd3d0b3dd35b4b273e1a3948a0a6143da2829", 1892867, "bitcoinjs-lib-bridge/bitcoinjs-lib-app.js", Relation.IDENTICAL),
            Asset("btcold/bitcoinjs-lib-app-old.js", "233f031f8a01aa7990d2131b194b2121914f98e951e279af25c42b00ff1f8123", 1145028, null, Relation.NOT_PUBLISHED),
            Asset("btctaproot/btctaproot-lib-app.js", "6621d31db32a180247a3ea4a3e665be8a04933131b9e3721807a060ef447cce7", 845267, "btctaprootjs-lib-bridge/btctaproot-lib-app.js", Relation.IDENTICAL),
            Asset("dash/dashjs-lib-app.min.js", "189a1feff5dcb8461fd7c1e51b7e0b84eae2df2b0fe20b794fec9019f2170b06", 2526271, "dashjs-lib-bridge/dashjs-lib-app.min.js", Relation.REDACTED),
            Asset("dgb/digibytejs-lib-app.min.js", "a8061ff483198e22150470ef615b2d48df289d3189bbd7eb8f84e1dc59682647", 2246102, "digibytejs-lib-bridge/digibytejs-lib-app.min.js", Relation.REDACTED),
            Asset("doge/dogecoinjs-lib-app.min.js", "05bac632734b854abf548ced0fb010597e80277eeb7b503798a0a3843c8bb6b5", 1993434, "dogecoinjs-lib-bridge/dogecoinjs-lib-app.min.js", Relation.REDACTED),
            Asset("eth/ethereumjs-lib-app.min.js", "cac08c1f18addce23cfeeb43c38622461e5c19e66dc051432583e08b15d2398c", 1218028, "ethereumjs-lib-bridge/ethereumjs-lib-app.min.js", Relation.IDENTICAL),
            Asset("ethext/ethjs-ext-v2.js", "fed30318b3d3db8bddb7509b872250509cfd378f987fd3323a18b02398b03fe0", 1443786, "ethereumjs-lib-bridge/ethjs-ext-v2.js", Relation.IDENTICAL),
            Asset("fil/filjs-lib-app.js", "6453e06454b002ad4ec0099631aba45f5182e45fe28981d8f9208a58cfb5917f", 1314588, "filejs-lib-bridge/filjs-lib-app.js", Relation.IDENTICAL),
            Asset("ltc/litecoinjs-lib-app.min.js", "8b6a70cb8750c954380ef2e15770cb8168a75c270805570bad1e424e957b4b2c", 1686783, "litecoinjs-lib-bridge/litecoinjs-lib-app.min.js", Relation.REDACTED),
            Asset("pubsigner/signer.js", "d89f76bdeec85d90fd88f07372100e9f4c07ab789530ac2bcffd52be536e7b05", 1044192, "pubsigner-lib-bridge/signer.js", Relation.IDENTICAL),
            Asset("sol/soljs-lib-app.js", "f865f5154fc8c8502fb99ad81734b4bf3a46e4f3e4e67a0bcb0b1f1bf205ef2d", 2147771, null, Relation.NOT_PUBLISHED),
            Asset("stx/stxjs-new.js", "b2b785d426e2b4c8019d94d50d1517d59fd6d859519152ce3eb779074def7391", 389451, null, Relation.NOT_PUBLISHED),
            Asset("ton/tonjs-new.js", "f20283fde67edf64f211b8634b4aeb6dfc829a47a88254b279cc27360709b7a1", 2178953, "tonjs-lib-bridge/tonjs-new.js", Relation.REDACTED),
            Asset("trx/trxjs-lib-app.js", "a96d2a29c84a1581ade57c6d9ce7b4dc401f9d9ba1883c4418cb831d7af04d5f", 2597552, "tronjs-lib-bridge/trxjs-lib-app.js", Relation.REDACTED),
            Asset("trxmsg/xemjs-lib-app.js", "4cd41d35d3eaf1d7d6dbe8490ae29afee5c10bf299ffbdb6800efb363db16ff3", 929967, null, Relation.NOT_PUBLISHED),
            Asset("xlm/stellarjs-lib-app.min.js", "8c337981ccc221fc9b92fe3bfad0c42ba05ff982b22eff889eb80f17bdd84871", 1682877, "stellarjs-lib-bridge/stellarjs-lib-app.min.js", Relation.REDACTED),
            Asset("xrp/ripplejs-lib-app.min.js", "d63aec38eb87c445d102c660ac16954ccafdd6136244ecc8b5637be87a0b8be1", 1141105, "ripplejs-lib-bridge/ripplejs-lib-app.min.js", Relation.IDENTICAL),
            Asset("zec/zcashjs-lib-app-0251.js", "cfcb522ec7817399f7b8c36130c8bef44e208269708913f2321bb370c23762c2", 974916, "zcashjs-lib-bridge/zcashjs-lib-app-0251.js", Relation.REDACTED),
            Asset("zen/zenjs-lib-app.min.js", "d1af677dc715785131f9a524b959aad27a15b2ee7c66647a44568432d47140c7", 988854, "horizenjs-lib-bridge/zenjs-lib-app.min.js", Relation.REDACTED),
        )
    }
}
