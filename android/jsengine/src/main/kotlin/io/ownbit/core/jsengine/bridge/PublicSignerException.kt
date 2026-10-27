// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
// Declared in io.ownbit.core.jsengine although the file sits in bridge/: JsException is a sealed class, and Kotlin only allows its direct subclasses in the same package.
package io.ownbit.core.jsengine

/**
 * The public-protocol engine (`BitSignerEngine.dispatch`) refused a request:
 * `{"ok": false, "error": {"code", "message"}}`, or `io.ownbit.core.jsengine.bridge.PublicSignerJsBridge` refused it
 * before the engine with an engine code (`LIMIT` for an oversized request, `SCAN` for a scan session that has ended).
 *
 * [code] is a closed engine vocabulary (`engine_vocabulary.json` in the iOS test fixtures), reduced to `[A-Z0-9_]`, at most 80
 * characters, and is the only part that may be logged; [message] (what `toString()` and logs print) contains the code
 * only. [engineMessage] is the engine's controlled English text, at most 400 characters: show it only as technical
 * detail (through `UntrustedText`), never log it. The app's UI text comes from the code.
 *
 * @param bundle the page the refusal came from ([JsBundle.PUBLIC_SIGNER] unless a pairing operation failed).
 */
class PublicSignerException(
    code: String,
    engineMessage: String,
    override val bundle: JsBundle = JsBundle.PUBLIC_SIGNER,
) : JsException("Public signer refused the request: ${sanitizeCode(code)}") {

    /** Engine error code, e.g. `NETWORK`, `RISK`, `QR_PROTOCOL` (`[A-Z0-9_]{1,80}`; `UNKNOWN` if it had none). */
    val code: String = sanitizeCode(code)

    /** The engine's English message, at most [MAX_MESSAGE] characters (never cut inside a surrogate pair). */
    val engineMessage: String = bound(engineMessage, MAX_MESSAGE)

    companion object {
        /** iOS `SigningEngine.swift` bounds: `code.prefix(80)`, `message.prefix(400)`. */
        const val MAX_CODE: Int = 80
        const val MAX_MESSAGE: Int = 400

        private fun sanitizeCode(code: String): String =
            code.uppercase().filter { it in 'A'..'Z' || it in '0'..'9' || it == '_' }.take(MAX_CODE).ifEmpty { "UNKNOWN" }

        private fun bound(text: String, max: Int): String {
            if (text.length <= max) return text
            val end = if (Character.isHighSurrogate(text[max - 1])) max - 1 else max
            return text.substring(0, end)
        }
    }
}
