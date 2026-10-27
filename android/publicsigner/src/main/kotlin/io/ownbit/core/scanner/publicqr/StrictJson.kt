// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.scanner.publicqr

import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject

/**
 * Strict JSON for the JSON-based QR formats of other wallets (TronLink; TokenPocket's legacy JSON, recognised to refuse): RFC 8259
 * syntax only (no comments, trailing commas, single quotes, unquoted keys, `NaN`, control characters in strings) and
 * **no duplicate key in any object** — two parsers that disagree on which duplicate wins could show one value and sign
 * another (parser differential). Nesting is bounded ([MAX_DEPTH]).
 *
 * The tree comes from kotlinx (`JsonObject` keeps key order and number literals exactly as written, which the answers
 * echo). Pure; nothing is logged.
 */
object StrictJson {

    /** Deepest nesting accepted. */
    const val MAX_DEPTH: Int = 32

    private val json = Json { isLenient = false }

    /** [text] as a JSON object, or `null` when it is not exactly one strict JSON object (see the class documentation). */
    fun parseObject(text: String): JsonObject? = parse(text) as? JsonObject

    /** [text] as one strict JSON value, or `null`. */
    fun parse(text: String): JsonElement? {
        if (!Validator(text).valid()) return null
        return try {
            json.parseToJsonElement(text)
        } catch (e: SerializationException) {
            null
        } catch (e: IllegalArgumentException) {
            null
        }
    }

    /** `true` when [text] is one strict JSON value without duplicate keys. */
    fun isStrict(text: String): Boolean = Validator(text).valid()

    private class Validator(private val s: String) {
        private var pos = 0

        fun valid(): Boolean = try {
            skipWs()
            value(0)
            skipWs()
            pos == s.length
        } catch (e: Bad) {
            false
        }

        private class Bad : RuntimeException() {
            override fun fillInStackTrace(): Throwable = this
        }

        private fun bad(): Nothing = throw Bad()

        private fun skipWs() {
            while (pos < s.length && (s[pos] == ' ' || s[pos] == '\t' || s[pos] == '\n' || s[pos] == '\r')) pos++
        }

        private fun value(depth: Int) {
            if (depth > MAX_DEPTH || pos >= s.length) bad()
            when (s[pos]) {
                '{' -> obj(depth + 1)
                '[' -> array(depth + 1)
                '"' -> string()
                't' -> literal("true")
                'f' -> literal("false")
                'n' -> literal("null")
                else -> number()
            }
        }

        private fun obj(depth: Int) {
            pos++ // {
            val keys = HashSet<String>()
            skipWs()
            if (pos < s.length && s[pos] == '}') {
                pos++
                return
            }
            while (true) {
                skipWs()
                if (pos >= s.length || s[pos] != '"') bad()
                if (!keys.add(string())) bad()
                skipWs()
                if (pos >= s.length || s[pos] != ':') bad()
                pos++
                skipWs()
                value(depth)
                skipWs()
                if (pos >= s.length) bad()
                when (s[pos]) {
                    ',' -> pos++
                    '}' -> {
                        pos++
                        return
                    }
                    else -> bad()
                }
            }
        }

        private fun array(depth: Int) {
            pos++ // [
            skipWs()
            if (pos < s.length && s[pos] == ']') {
                pos++
                return
            }
            while (true) {
                skipWs()
                value(depth)
                skipWs()
                if (pos >= s.length) bad()
                when (s[pos]) {
                    ',' -> pos++
                    ']' -> {
                        pos++
                        return
                    }
                    else -> bad()
                }
            }
        }

        /** Reads a string at `"` and returns its decoded value. */
        private fun string(): String {
            pos++ // "
            val out = StringBuilder()
            while (true) {
                if (pos >= s.length) bad()
                val c = s[pos++]
                when {
                    c == '"' -> return out.toString()
                    c == '\\' -> {
                        if (pos >= s.length) bad()
                        when (val e = s[pos++]) {
                            '"', '\\', '/' -> out.append(e)
                            'b' -> out.append('\b')
                            'f' -> out.append('\u000c')
                            'n' -> out.append('\n')
                            'r' -> out.append('\r')
                            't' -> out.append('\t')
                            'u' -> {
                                if (pos + 4 > s.length) bad()
                                val code = s.substring(pos, pos + 4).toIntOrNull(16) ?: bad()
                                if (!s.substring(pos, pos + 4).all { it in '0'..'9' || it in 'a'..'f' || it in 'A'..'F' }) bad()
                                out.append(code.toChar())
                                pos += 4
                            }
                            else -> bad()
                        }
                    }
                    c.code < 0x20 -> bad()
                    else -> out.append(c)
                }
            }
        }

        private fun literal(word: String) {
            if (!s.startsWith(word, pos)) bad()
            pos += word.length
        }

        private fun number() {
            val start = pos
            if (pos < s.length && s[pos] == '-') pos++
            if (pos >= s.length) bad()
            if (s[pos] == '0') {
                pos++
            } else if (s[pos] in '1'..'9') {
                while (pos < s.length && s[pos] in '0'..'9') pos++
            } else {
                bad()
            }
            if (pos < s.length && s[pos] == '.') {
                pos++
                val digits = pos
                while (pos < s.length && s[pos] in '0'..'9') pos++
                if (pos == digits) bad()
            }
            if (pos < s.length && (s[pos] == 'e' || s[pos] == 'E')) {
                pos++
                if (pos < s.length && (s[pos] == '+' || s[pos] == '-')) pos++
                val digits = pos
                while (pos < s.length && s[pos] in '0'..'9') pos++
                if (pos == digits) bad()
            }
            if (pos == start) bad()
        }
    }
}
