// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.jsengine.internal

import io.ownbit.core.jsengine.JsArgs
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import org.junit.Test
import java.math.BigDecimal
import java.math.BigInteger
import java.util.Locale
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNull
import kotlin.test.assertTrue

class JsProtocolTest {

    @Test
    fun `string literal is pure ASCII and escapes quotes backslashes and controls`() {
        val literal = JsProtocol.jsStringLiteral("a\"b\\c'd\n\r\t  é中😀</script>")
        assertTrue(literal.all { it.code in 0x20..0x7E }, literal)
        assertEquals(
            "\"a\\\"b\\\\c'd\\u000a\\u000d\\u0009\\u2028\\u2029\\u00e9\\u4e2d\\ud83d\\ude00</script>\"",
            literal,
        )
    }

    @Test
    fun `string literal round-trips through a JSON parser`() {
        // A double-quoted JS literal made of ASCII + \uXXXX escapes is also valid JSON.
        val original = "mnemonic with \"quotes\", \\slashes\\, newline\n and ユニコード 😀"
        val decoded = Json.parseToJsonElement(JsProtocol.jsStringLiteral(original)).jsonPrimitive.content
        assertEquals(original, decoded)
    }

    @Test
    fun `invoke script embeds the request only as a string literal`() {
        val script = JsProtocol.invokeScript(7, "bridge.getXpubkeys", JsArgs.of("ab'); alert(1); ('", 3, true))
        assertTrue(script.startsWith("window.__ownbitHost.invoke(\""))
        assertTrue(script.endsWith("\");0"))
        val literal = script.removePrefix("window.__ownbitHost.invoke(").removeSuffix(");0")
        val request = Json.parseToJsonElement(Json.parseToJsonElement(literal).jsonPrimitive.content).jsonObject
        assertEquals(7L, request["id"]!!.jsonPrimitive.long)
        assertEquals("bridge.getXpubkeys", request["fn"]!!.jsonPrimitive.content)
        val args = request["args"]!!.jsonArray
        assertEquals("ab'); alert(1); ('", args[0].jsonPrimitive.content)
        assertEquals(JsonPrimitive(3), args[1])
        assertEquals(JsonPrimitive(true), args[2])
    }

    @Test
    fun `invoke script numbers are canonical in every locale`() {
        val saved = Locale.getDefault()
        try {
            for (tag in listOf("de-DE", "ar", "ar-EG", "fr-FR", "tr-TR")) {
                Locale.setDefault(Locale.forLanguageTag(tag))
                val script = JsProtocol.invokeScript(
                    12345,
                    "bridge.f",
                    JsArgs.of(1234.5, BigDecimal("0.5"), 1234567L, BigInteger("9007199254740991"), "m/44'/0'/0'/0"),
                )
                assertTrue(script.all { it.code in 0x20..0x7E }, tag)
                val literal = script.removePrefix("window.__ownbitHost.invoke(").removeSuffix(");0")
                // The request JSON exactly as the page's JSON.parse receives it.
                val request = Json.parseToJsonElement(literal).jsonPrimitive.content
                assertEquals("{\"id\":12345,\"fn\":\"bridge.f\",\"args\":[1234.5,0.5,1234567,9007199254740991,\"m/44'/0'/0'/0\"]}", request, tag)
            }
        } finally {
            Locale.setDefault(saved)
        }
    }

    @Test
    fun `function paths are restricted to dotted identifiers`() {
        assertTrue(JsProtocol.isValidFunctionPath("bridge.getXpubkeys"))
        assertTrue(JsProtocol.isValidFunctionPath("bridge.bip39.entropyToMnemonic"))
        assertTrue(JsProtocol.isValidFunctionPath("getAdaAddress"))
        assertTrue(JsProtocol.isValidFunctionPath("__ownbitHost.ping"))
        assertFalse(JsProtocol.isValidFunctionPath("bridge.x()"))
        assertFalse(JsProtocol.isValidFunctionPath("bridge[0]"))
        assertFalse(JsProtocol.isValidFunctionPath(""))
        assertFalse(JsProtocol.isValidFunctionPath("a..b"))
        assertFalse(JsProtocol.isValidFunctionPath("bridge.constructor"))
        assertFalse(JsProtocol.isValidFunctionPath("x.__proto__.y"))
        assertFalse(JsProtocol.isValidFunctionPath("a;b"))
        assertFailsWith<IllegalArgumentException> { JsProtocol.invokeScript(1, "alert(1)", JsArgs.NONE) }
    }

    @Test
    fun `parses results`() {
        val ok = JsProtocol.parse("""{"t":"r","id":12,"ok":true,"v":["a","b"]}""")
        assertIs<JsProtocol.HostMessage.Result>(ok)
        assertEquals(12, ok.id)
        assertTrue(ok.ok)
        assertEquals(JsArgs.of("a", "b"), ok.value)
        assertNull(ok.error)

        val nullValue = JsProtocol.parse("""{"t":"r","id":1,"ok":true,"v":null}""")
        assertIs<JsProtocol.HostMessage.Result>(nullValue)
        assertEquals(JsonNull, nullValue.value)

        val failed = JsProtocol.parse("""{"t":"r","id":3,"ok":false,"e":"Error: boom"}""")
        assertIs<JsProtocol.HostMessage.Result>(failed)
        assertFalse(failed.ok)
        assertEquals("Error: boom", failed.error)
    }

    @Test
    fun `parses events`() {
        val event = JsProtocol.parse("""{"t":"e","ch":"pre","ok":true,"d":"obtransaction:{}"}""")
        assertIs<JsProtocol.HostMessage.Event>(event)
        assertEquals("pre", event.channel)
        assertTrue(event.ok)
        assertEquals("obtransaction:{}", event.payload)

        val failure = JsProtocol.parse("""{"t":"e","ch":"signed","ok":false,"d":"Error: x"}""")
        assertIs<JsProtocol.HostMessage.Event>(failure)
        assertFalse(failure.ok)
    }

    @Test
    fun `rejects malformed messages`() {
        assertNull(JsProtocol.parse("not json"))
        assertNull(JsProtocol.parse("[]"))
        assertNull(JsProtocol.parse("""{"t":"x"}"""))
        assertNull(JsProtocol.parse("""{"t":"r","ok":true}"""))
        assertNull(JsProtocol.parse("""{"t":"r","id":"a","ok":true}"""))
        assertNull(JsProtocol.parse("""{"t":"e","ok":true}"""))
    }

    @Test
    fun `result toString never contains the value`() {
        val secret = JsProtocol.HostMessage.Result(1, true, JsonPrimitive("seed"), null)
        assertFalse(secret.toString().contains("seed"))
        val event = JsProtocol.HostMessage.Event("transaction", true, "signedtx")
        assertFalse(event.toString().contains("signedtx"))
        assertIs<JsonObject>(Json.parseToJsonElement("{}"))
        assertIs<JsonArray>(JsArgs.NONE)
    }
}
