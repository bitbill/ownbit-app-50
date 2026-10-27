// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.jsengine.internal

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.longOrNull
import kotlinx.serialization.json.put

/**
 * Wire protocol between [WebViewJsEngine] and `assets/js/host/ownbit-host.js`. Pure functions, unit
 * tested on the JVM.
 */
internal object JsProtocol {

    /** Origin every host page is served from (WebViewAssetLoader default domain). */
    const val ORIGIN: String = "https://appassets.androidplatform.net"

    /** Name of the object injected by `WebViewCompat.addWebMessageListener`. */
    const val HOST_OBJECT: String = "OwnbitHost"

    /** Value `evaluateJavascript` reports when the invoke statement ran (`...;0`). */
    const val INVOKE_ACK: String = "0"

    private val FUNCTION_PATH = Regex("^[A-Za-z_$][\\w$]*(\\.[A-Za-z_$][\\w$]*)*$")
    private val FORBIDDEN_SEGMENTS = setOf("__proto__", "prototype", "constructor")

    private val json = Json { isLenient = false }

    /** `true` when [path] is a plain dotted identifier path the host shim will accept. */
    fun isValidFunctionPath(path: String): Boolean =
        FUNCTION_PATH.matches(path) && path.split('.').none { it in FORBIDDEN_SEGMENTS }

    /**
     * The statement passed to `evaluateJavascript`. The request JSON is embedded as a JS string
     * literal (never as code) and parsed with `JSON.parse` by the shim. The trailing `;0` makes the
     * statement's value a plain number so the WebView never tries to serialize a Promise.
     */
    fun invokeScript(id: Long, function: String, args: JsonArray): String {
        require(isValidFunctionPath(function)) { "invalid JS function path" }
        val request = buildJsonObject {
            put("id", id)
            put("fn", function)
            put("args", args)
        }.toString()
        return "window.__ownbitHost.invoke(" + jsStringLiteral(request) + ");0"
    }

    /**
     * Encodes [value] as a double-quoted JS string literal containing only printable ASCII: `"` and
     * `\` are backslash-escaped, everything else outside 0x20..0x7E (control characters, U+2028/2029,
     * non-ASCII, lone surrogates) becomes `\uXXXX`. The literal evaluates to exactly [value].
     */
    fun jsStringLiteral(value: String): String {
        val out = StringBuilder(value.length + 16)
        out.append('"')
        for (c in value) {
            when {
                c == '"' -> out.append("\\\"")
                c == '\\' -> out.append("\\\\")
                c.code in 0x20..0x7E -> out.append(c)
                else -> {
                    out.append("\\u")
                    val hex = c.code.toString(16)
                    repeat(4 - hex.length) { out.append('0') }
                    out.append(hex)
                }
            }
        }
        out.append('"')
        return out.toString()
    }

    /** A message posted by the host shim. */
    sealed interface HostMessage {
        /** Result of an `invoke`: [ok] with [value], or failure with [error] (`String(error)` in JS). */
        data class Result(val id: Long, val ok: Boolean, val value: JsonElement, val error: String?) : HostMessage {
            override fun toString(): String = "Result(id=$id, ok=$ok)"
        }

        /** Asynchronous bundle callback. */
        data class Event(val channel: String, val ok: Boolean, val payload: String) : HostMessage {
            override fun toString(): String = "Event(channel=$channel, ok=$ok)"
        }
    }

    /** Parses a message posted by the shim; `null` for anything malformed or unknown. */
    fun parse(message: String): HostMessage? {
        val obj = runCatching { json.parseToJsonElement(message) }.getOrNull() as? JsonObject ?: return null
        return when ((obj["t"] as? JsonPrimitive)?.contentOrNull) {
            "r" -> {
                val id = (obj["id"] as? JsonPrimitive)?.longOrNull ?: return null
                val ok = (obj["ok"] as? JsonPrimitive)?.booleanOrNull ?: return null
                HostMessage.Result(
                    id = id,
                    ok = ok,
                    value = obj["v"] ?: JsonNull,
                    error = (obj["e"] as? JsonPrimitive)?.contentOrNull,
                )
            }
            "e" -> {
                val channel = (obj["ch"] as? JsonPrimitive)?.contentOrNull ?: return null
                val ok = (obj["ok"] as? JsonPrimitive)?.booleanOrNull ?: return null
                val payload = (obj["d"] as? JsonPrimitive)?.contentOrNull ?: ""
                HostMessage.Event(channel, ok, payload)
            }
            else -> null
        }
    }
}
