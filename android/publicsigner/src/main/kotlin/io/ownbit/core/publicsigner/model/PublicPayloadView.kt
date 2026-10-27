// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.publicsigner.model

import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * What a QR code actually carries, decoded back by the engine from the frames it produced (`describeQR`,
 * `protocols.js`; BitSigner `QRPayloadView`): registry field names, byte strings as hex, a plain-text code is its own
 * payload. Public keys / signatures only, nothing secret. Shown in the "Payload" disclosure of the pairing and result
 * pages; `null` (no view) hides the disclosure.
 *
 * @property text the payload as shown: pretty, key-sorted JSON (2-space indent) for [Format.JSON], else the hex / text.
 * @property byteCount size of the encoded payload (CBOR bytes for a UR, UTF-8 bytes for text).
 * @property qrType the transport (`crypto-account`, `eth-signature`, `bbqr-psbt`, `psbt-base64`, `address`, …).
 * @property bbqrEncoding `H` / `2` / `Z` for a BBQr code, else `null`.
 */
data class PublicPayloadView(
    val format: Format,
    val text: String,
    val byteCount: Int,
    val qrType: String?,
    val bbqrEncoding: String? = null,
) {
    enum class Format(val wire: String) { JSON("json"), HEX("hex"), TEXT("text") }

    /** A signed PSBT in any of its transports. */
    val isPsbt: Boolean get() = qrType in PSBT_TYPES

    /** A UR (CBOR) transport rather than plain text / BBQr / another wallet's own JSON format (TronLink). */
    val isUr: Boolean get() = qrType != null && qrType !in NOT_UR

    /** Another wallet's own JSON answer (TronLink). */
    val isOtherWalletJson: Boolean get() = qrType in OTHER_WALLET_JSON

    companion object {
        private val PSBT_TYPES = setOf("crypto-psbt", "psbt", "bbqr-psbt", "psbt-base64", "psbt-hex")
        private val OTHER_WALLET_JSON = setOf(PublicResponseQr.TRONLINK)
        private val NOT_UR = setOf("address", "bbqr-psbt", "psbt-base64", "psbt-hex") + OTHER_WALLET_JSON

        @OptIn(ExperimentalSerializationApi::class)
        private val pretty = Json { prettyPrint = true; prettyPrintIndent = "  " }

        /**
         * The view of an engine result that carries `payloadFormat` / `payload` / `payloadBytes` / `type` / `frames`
         * (pairing and response results); `null` when the engine sent none or it is malformed (BitSigner parity: the
         * disclosure is then hidden, the QR itself is unaffected).
         */
        fun fromEngine(raw: JsonObject): PublicPayloadView? {
            val format = Format.entries.firstOrNull { it.wire == raw.str("payloadFormat") } ?: return null
            val text = when (format) {
                Format.JSON -> prettyJson(raw.obj("payload") ?: return null)
                Format.HEX, Format.TEXT -> raw.str("payload")?.takeIf { it.isNotEmpty() } ?: return null
            }
            val firstFrame = raw.strings("frames")?.firstOrNull().orEmpty()
            return PublicPayloadView(
                format = format,
                text = text,
                byteCount = raw.int("payloadBytes") ?: text.encodeToByteArray().size,
                qrType = raw.str("type"),
                bbqrEncoding = if (firstFrame.startsWith("B$") && firstFrame.length > 2) firstFrame[2].toString() else null,
            )
        }

        /** Pretty JSON with every object's keys sorted (BitSigner `.sortedKeys`, `.prettyPrinted`). */
        fun prettyJson(value: JsonObject): String = pretty.encodeToString(JsonElement.serializer(), sorted(value))

        private fun sorted(element: JsonElement): JsonElement = when (element) {
            is JsonObject -> JsonObject(element.entries.sortedBy { it.key }.associate { it.key to sorted(it.value) })
            is JsonArray -> JsonArray(element.map(::sorted))
            is JsonPrimitive -> element
        }
    }
}
