// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.publicsigner.scan

import io.ownbit.core.publicsigner.testing.OtherWalletVectors
import io.ownbit.core.scanner.publicqr.TronLinkQrFormat
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import org.junit.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertTrue

/** [TronLinkCollector]. TokenPocket requests are refused (no collector). */
class OtherWalletCollectorsTest {

    /** TronLink's splitter (`SignTransactionNewModel.subSign`): 1000-character pieces of `h1&&&h2&&&…`. */
    private fun tronLinkParts(entries: List<String>, type: Int, address: String = OtherWalletVectors.TRON_0, size: Int = 1000): List<String> {
        val joined = entries.joinToString("") { "$it&&&" }
        val total = (joined.length + size - 1) / size
        return (1..total).map { i ->
            buildJsonObject {
                if (i == 1 || i == total) put("address", address)
                put("cN", i)
                put("hexList", JsonArray(listOf(JsonPrimitive(joined.substring((i - 1) * size, minOf(i * size, joined.length))))))
                put("tN", total)
                put("type", if (i == total) type else 0)
            }.toString()
        }
    }

    private fun frame(text: String) = TronLinkQrFormat.parse(text) ?: error("not a TronLink frame")

    @Test fun `a single TronLink QR completes at once and keeps the scanned object`() {
        val step = assertIs<TronLinkCollector.Step.Complete>(TronLinkCollector().add(frame(OtherWalletVectors.V1_REQUEST)))
        assertEquals(OtherWalletVectors.V1_REQUEST, step.request.bean.toString())
        assertEquals(99, step.request.type)
        assertFalse(step.request.wasSplit)
    }

    @Test fun `TronLink parts in any order, repeats ignored, the joined request rebuilt`() {
        val entry = "0a" + "ab".repeat(1_200)
        val parts = tronLinkParts(listOf(entry), type = 14)
        assertEquals(3, parts.size)
        val collector = TronLinkCollector()
        assertEquals(TronLinkCollector.Step.Partial(1, 3), collector.add(frame(parts[2])))
        assertEquals(TronLinkCollector.Step.Partial(1, 3), collector.add(frame(parts[2])), "a repeat")
        assertEquals(TronLinkCollector.Step.Partial(2, 3), collector.add(frame(parts[0])))
        val done = assertIs<TronLinkCollector.Step.Complete>(collector.add(frame(parts[1])))
        assertEquals(listOf(entry), done.request.hexList)
        assertEquals(14, done.request.type)
        assertEquals(OtherWalletVectors.TRON_0, done.request.address)
        assertTrue(done.request.wasSplit)
        assertEquals("""{"address":"${OtherWalletVectors.TRON_0}","type":14,"hexList":["$entry"]}""", done.request.bean.toString())
    }

    @Test fun `TronLink parts of another request are refused`() {
        val a = tronLinkParts(listOf("0a" + "ab".repeat(700)), type = 1)
        val b = tronLinkParts(listOf("0a" + "cd".repeat(700)), type = 1)
        fun other(block: () -> Unit) = assertEquals(OtherWalletRequestException.Kind.OTHER_REQUEST, assertFailsWith<OtherWalletRequestException> { block() }.kind)
        // The same part number with another piece.
        TronLinkCollector().apply { add(frame(a[0])); other { add(frame(b[0])) } }
        // Another part count.
        val c = tronLinkParts(listOf("0a" + "ab".repeat(1_600)), type = 1)
        TronLinkCollector().apply { add(frame(a[0])); other { add(frame(c[2])) } }
        // First and last part name different addresses.
        val wrongLast = tronLinkParts(listOf("0a" + "ab".repeat(700)), type = 1, address = "TSeJkUh4Qv67VNFwY8LaAxERygNdy6NQZK")
        TronLinkCollector().apply { add(frame(a[0])); other { add(frame(wrongLast[1])) } }
        // A single QR after a part.
        TronLinkCollector().apply { add(frame(a[0])); other { add(frame(OtherWalletVectors.V1_REQUEST)) } }
    }

    @Test fun `TronLink limits and the join rule`() {
        val tooMany = """{"cN":1,"hexList":["ab"],"tN":65,"type":0}"""
        assertEquals(OtherWalletRequestException.Kind.TOO_LARGE, assertFailsWith<OtherWalletRequestException> { TronLinkCollector().add(frame(tooMany)) }.kind)
        val bigPiece = """{"cN":1,"hexList":["${"a".repeat(4_097)}"],"tN":2,"type":0}"""
        assertEquals(OtherWalletRequestException.Kind.TOO_LARGE, assertFailsWith<OtherWalletRequestException> { TronLinkCollector().add(frame(bigPiece)) }.kind)
        // Two entries survive the join (the mapper refuses them later: one transaction per request).
        val two = tronLinkParts(listOf("0a" + "11".repeat(400), "0a" + "22".repeat(400)), type = 4)
        val collector = TronLinkCollector()
        two.dropLast(1).forEach { collector.add(frame(it)) }
        assertEquals(2, assertIs<TronLinkCollector.Step.Complete>(collector.add(frame(two.last()))).request.hexList.size)
        // An empty entry (`&&&&&&`) is malformed.
        val empty = tronLinkParts(listOf("0a" + "11".repeat(600)), type = 1).toMutableList()
        empty[1] = empty[1].replace("&&&\"]", "&&&&&&\"]")
        val c2 = TronLinkCollector()
        c2.add(frame(empty[0]))
        assertEquals(OtherWalletRequestException.Kind.MALFORMED, assertFailsWith<OtherWalletRequestException> { c2.add(frame(empty[1])) }.kind)
    }
}
