// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.jsengine

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Test
import java.math.BigInteger
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class JsArgsAndResultsTest {

    @Test
    fun `arguments keep their JSON types`() {
        val args = JsArgs.of(
            "0",
            0,
            5L,
            true,
            null,
            charArrayOf('a', 'b'),
            listOf("x", 1),
            mapOf("owners" to listOf("0xa"), "required" to 2),
            BigInteger("9007199254740991"),
        )
        assertEquals(JsonPrimitive("0"), args[0])
        assertEquals(JsonPrimitive(0), args[1])
        assertEquals(JsonPrimitive(5L), args[2])
        assertEquals(JsonPrimitive(true), args[3])
        assertEquals(JsonNull, args[4])
        assertEquals(JsonPrimitive("ab"), args[5])
        assertEquals(JsonArray(listOf(JsonPrimitive("x"), JsonPrimitive(1))), args[6])
        assertEquals(
            JsonObject(mapOf("owners" to JsonArray(listOf(JsonPrimitive("0xa"))), "required" to JsonPrimitive(2))),
            args[7],
        )
        assertEquals("[\"0\",0,5,true,null,\"ab\",[\"x\",1],{\"owners\":[\"0xa\"],\"required\":2},9007199254740991]", args.toString())
    }

    @Test
    fun `numbers a JS double cannot hold exactly are rejected`() {
        // Beyond Number.MAX_SAFE_INTEGER a JSON number silently changes value in JS (wei amounts!).
        assertFailsWith<IllegalArgumentException> { JsArgs.of(BigInteger("10000000000000000001")) }
        assertFailsWith<IllegalArgumentException> { JsArgs.of(JsArgs.MAX_SAFE_INTEGER + 1) }
        assertFailsWith<IllegalArgumentException> { JsArgs.of(-JsArgs.MAX_SAFE_INTEGER - 1) }
        assertFailsWith<IllegalArgumentException> { JsArgs.of(java.math.BigDecimal("1E18")) }
        assertFailsWith<IllegalArgumentException> { JsArgs.of(java.math.BigDecimal("0.12345678901234567891")) }
        // NaN / infinity are not JSON: the page could not parse the request and the call would hang.
        assertFailsWith<IllegalArgumentException> { JsArgs.of(Double.NaN) }
        assertFailsWith<IllegalArgumentException> { JsArgs.of(Float.POSITIVE_INFINITY) }
        // Exactly representable values pass and keep their numeric value.
        assertEquals("[9007199254740991,-9007199254740991,0.5,1.0E-8,21000.0,0.1]",
            JsArgs.of(
                JsArgs.MAX_SAFE_INTEGER,
                BigInteger.valueOf(-JsArgs.MAX_SAFE_INTEGER),
                java.math.BigDecimal("0.5"),
                java.math.BigDecimal("0.00000001"),
                java.math.BigDecimal("21000"),
                0.1,
            ).toString(),
        )
        // Nested values are checked too.
        assertFailsWith<IllegalArgumentException> { JsArgs.of(listOf(Long.MAX_VALUE)) }
    }

    @Test
    fun `unsupported argument types are rejected`() {
        assertFailsWith<IllegalArgumentException> { JsArgs.of(Any()) }
        assertFailsWith<IllegalArgumentException> { JsArgs.of(mapOf(1 to "a")) }
    }

    @Test
    fun `truthiness follows JavaScript`() {
        assertTrue(JsResults.truthy(JsonPrimitive(true)))
        assertFalse(JsResults.truthy(JsonPrimitive(false)))
        assertFalse(JsResults.truthy(JsonNull))
        assertFalse(JsResults.truthy(JsonPrimitive("")))
        assertTrue(JsResults.truthy(JsonPrimitive("x")))
        assertFalse(JsResults.truthy(JsonPrimitive(0)))
        assertTrue(JsResults.truthy(JsonPrimitive(2)))
        assertTrue(JsResults.truthy(JsonArray(emptyList())))
    }

    @Test
    fun `string results`() {
        assertEquals("abc", JsResults.string(JsonPrimitive("abc"), JsBundle.BTC, "f"))
        assertEquals("1", JsResults.string(JsonPrimitive(1), JsBundle.BTC, "f"))
        assertNull(JsResults.stringOrNull(JsonNull, JsBundle.BTC, "f"))
        assertFailsWith<JsResultFormatException> { JsResults.string(JsonNull, JsBundle.BTC, "f") }
        assertFailsWith<JsResultFormatException> { JsResults.nonEmptyString(JsonPrimitive(""), JsBundle.BTC, "f") }
        assertFailsWith<JsResultFormatException> { JsResults.string(JsonArray(emptyList()), JsBundle.BTC, "f") }
    }

    @Test
    fun `string array results`() {
        val array = JsArgs.of("a", "b", "c")
        assertEquals(listOf("a", "b", "c"), JsResults.stringArray(array, JsBundle.ETH, "f", 3))
        assertFailsWith<JsResultFormatException> { JsResults.stringArray(array, JsBundle.ETH, "f", 4) }
        assertFailsWith<JsResultFormatException> { JsResults.stringArray(JsArgs.of("a", 1), JsBundle.ETH, "f") }
        assertFailsWith<JsResultFormatException> { JsResults.stringArray(JsonPrimitive("a"), JsBundle.ETH, "f") }
    }

    @Test
    fun `non-empty string array results (iOS BILJSArg strings)`() {
        assertEquals(listOf("a", "b"), JsResults.nonEmptyStrings(JsArgs.of("a", "b", "c"), JsBundle.XRP, "f", 2))
        assertEquals(listOf("r", "P", "S"), JsResults.nonEmptyStrings(JsArgs.of("r", "P", "S"), JsBundle.XRP, "f", 3))
        // Elements after the first `size` are not looked at (iOS `arr.prefix(count)`), whatever their type.
        assertEquals(listOf("a", "b"), JsResults.nonEmptyStrings(JsArgs.of("a", "b", 1, null, ""), JsBundle.XRP, "f", 2))
        assertFailsWith<JsResultFormatException> { JsResults.nonEmptyStrings(JsArgs.of("a", null), JsBundle.XLM, "f", 2) }
        assertFailsWith<JsResultFormatException> { JsResults.nonEmptyStrings(JsArgs.of("a"), JsBundle.XRP, "f", 2) }
        assertFailsWith<JsResultFormatException> { JsResults.nonEmptyStrings(JsArgs.of("a", ""), JsBundle.XLM, "f", 2) }
        assertFailsWith<JsResultFormatException> { JsResults.nonEmptyStrings(JsArgs.of("", "b", "c"), JsBundle.XRP, "f", 3) }
        assertFailsWith<JsResultFormatException> { JsResults.nonEmptyStrings(JsArgs.of("a", 1), JsBundle.XLM, "f", 2) }
        assertFailsWith<JsResultFormatException> { JsResults.nonEmptyStrings(JsonPrimitive("a"), JsBundle.XLM, "f", 1) }
    }

    @Test
    fun `exception messages never carry JS text`() {
        val e = JsCallException(JsBundle.BTC, "bridge.mnemonicToSeedHex", "Error: abandon abandon")
        assertFalse(e.message!!.contains("abandon"))
        assertFalse(e.toString().contains("abandon"))
        val ev = JsEventFailureException(JsBundle.TRX, "bridge.signTx", "signed", "secret")
        assertFalse(ev.toString().contains("secret"))
        assertFalse(JsEvent("address", true, "UQsecretaddr").toString().contains("UQsecretaddr"))
    }

    @Test
    fun `event spec requires a success channel`() {
        assertFailsWith<IllegalArgumentException> { JsEventSpec(emptySet()) }
        assertEquals(setOf("error"), JsEventSpec.of("pre").failureChannels)
    }
}
