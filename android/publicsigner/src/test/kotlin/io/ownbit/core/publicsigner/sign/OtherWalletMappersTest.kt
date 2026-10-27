// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.publicsigner.sign

import io.ownbit.core.publicsigner.model.obj
import io.ownbit.core.publicsigner.model.str
import io.ownbit.core.publicsigner.scan.OtherWalletRequestException
import io.ownbit.core.publicsigner.scan.TronLinkRequest
import io.ownbit.core.publicsigner.testing.OtherWalletVectors
import io.ownbit.core.publicsigner.testing.SigningVectors
import io.ownbit.core.scanner.publicqr.TronLinkQrFormat
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import org.junit.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

/**
 * [TronLinkRequestMapper]: the engine-native requests are exactly the golden vectors' (the
 * requests the pinned engine reviewed and signed), and every v1 refusal happens before the engine with
 * its own text. TokenPocket has no mapper (its requests are refused).
 */
class OtherWalletMappersTest {

    private fun vectorRequest(id: String): JsonObject =
        SigningVectors.steps(id).first { it.op == "review" || it.op == "resolveSigningPlan" }.request.getValue("request").jsonObject

    private fun tronLink(text: String): JsonObject =
        TronLinkRequestMapper.map(TronLinkRequest.of(TronLinkQrFormat.parse(text, TronLinkQrFormat.MAX_REQUEST_CHARS) ?: error("not TronLink")))

    private fun refusal(block: () -> Unit): OtherWalletRequestException = assertFailsWith { block() }

    @Test fun `TronLink V1 to V4 map to exactly the engine requests of the golden vectors`() {
        assertEquals(vectorRequest("O-TL-V1-ownership-ios"), tronLink(OtherWalletVectors.V1_REQUEST))
        assertEquals(vectorRequest("O-TL-V3-trx-transfer"), tronLink(OtherWalletVectors.V3_REQUEST))
        assertEquals(vectorRequest("O-TL-V4-tip191-message"), tronLink(OtherWalletVectors.V4_REQUEST))
        // V2 (Android's shape with cN / tN): the same placeholder rule; the transport carries the scanned object.
        val v2 = tronLink(OtherWalletVectors.V2_REQUEST)
        assertEquals(vectorRequest("O-TL-V2-ownership-android").obj("transaction"), v2.obj("transaction"))
        assertEquals(99, v2.obj("transport")!!["tronlinkType"].toString().toInt())
        assertEquals(OtherWalletVectors.V2_REQUEST, String(io.ownbit.core.crypto.util.Hex.decode(v2.obj("transport")!!.str("payloadBytes")!!)))
    }

    @Test fun `TronLink messages - text, hex and signed byte lists`() {
        fun message(type: Int, entry: String) = tronLink("""{"address":"${OtherWalletVectors.TRON_0}","type":$type,"hexList":["$entry"]}""")
        assertEquals("hello ownbit" to "utf8", message(102, "hello ownbit").let { it.str("message") to it.str("encoding") })
        assertEquals("68656c6c6f" to "hex", message(103, "0x68656C6C6F").let { it.str("message") to it.str("encoding") })
        assertEquals("ff007f80" to "hex", message(104, "-1,0,127,-128").let { it.str("message") to it.str("encoding") })
        assertEquals("ff" to "hex", message(104, "255").let { it.str("message") to it.str("encoding") })
        listOf(103 to "0x123", 103 to "zz", 104 to "1,,2", 104 to "256", 104 to "-129", 104 to "1.5", 102 to "").forEach { (type, entry) ->
            assertEquals("publicprotocol_err_qrmalformed", refusal { message(type, entry) }.error.message, "$type $entry")
        }
    }

    @Test fun `TronLink refusals before the engine`() {
        fun with(type: Int, entries: String = "\"${OtherWalletVectors.V3_ENTRY}\"", extra: String = "") =
            """{"address":"${OtherWalletVectors.TRON_0}","type":$type,"hexList":[$entries]$extra}"""
        assertEquals("publicprotocol_err_tronlinkblindhash", refusal { tronLink(with(101, "\"" + "ab".repeat(32) + "\"")) }.error.message)
        assertEquals("publicprotocol_err_tronlinkblindhash", refusal { tronLink(with(17)) }.error.message)
        assertEquals("publicprotocol_err_tronlinkmessagev1", refusal { tronLink(with(98, "\"abcd\"")) }.error.message)
        assertEquals("publicprotocol_err_tronlinkshielded", refusal { tronLink(with(15)) }.error.message)
        assertEquals("publicprotocol_err_tronlinkshielded", refusal { tronLink(with(1, extra = ",\"alpha\":\"ab\"")) }.error.message)
        assertEquals("publicprotocol_err_tronlinkshielded", refusal { tronLink(with(1, extra = ",\"tokenId\":\"1000001\"")) }.error.message)
        val multi = refusal { tronLink(with(4, "\"${OtherWalletVectors.V3_ENTRY}\",\"${OtherWalletVectors.V3_ENTRY}\"")) }
        assertEquals("publicprotocol_err_tronlinkmulti", multi.error.message)
        assertEquals(listOf<Any>(2), multi.error.args)
        assertEquals(OtherWalletRequestException.Kind.UNSUPPORTED, multi.kind)
        // Type 99 and the placeholder must agree.
        assertEquals("publicprotocol_err_integrity", refusal { tronLink(with(99)) }.error.message)
        assertEquals("publicprotocol_err_integrity", refusal { tronLink(with(1, "\"${OtherWalletVectors.V1_ENTRY}\"")) }.error.message)
        // An unknown page above 99 whose entry is not a transaction: named with its number.
        val unknown = refusal { tronLink(with(150, "\"hello\"")) }
        assertEquals("publicprotocol_err_tronlinktype", unknown.error.message)
        assertEquals(listOf<Any>(150), unknown.error.args)
        // Malformed: no / invalid address, an entry that is not a strict Transaction.
        listOf(
            """{"type":1,"hexList":["${OtherWalletVectors.V3_ENTRY}"]}""",
            """{"address":"TUEZSdKsoDHQMeZwihtdoBiN46zxhGWYdx","type":1,"hexList":["${OtherWalletVectors.V3_ENTRY}"]}""",
            """{"address":"0x9858EfFD232B4033E47d90003D41EC34EcaEda94","type":1,"hexList":["${OtherWalletVectors.V3_ENTRY}"]}""",
            with(1, "\"${OtherWalletVectors.V3_ENTRY}2a00\""),
            with(1, "\"0x${OtherWalletVectors.V3_ENTRY}\""),
            with(1, "\"${OtherWalletVectors.V3_ENTRY}0\""),
        ).forEach { assertEquals(OtherWalletRequestException.Kind.MALFORMED, refusal { tronLink(it) }.kind, it) }
    }

    @Test fun `a TronLink transaction that already carries signatures passes them on`() {
        val signed = OtherWalletVectors.V3_ENTRY + "1241" + OtherWalletVectors.V3_SIG
        val r = tronLink("""{"address":"${OtherWalletVectors.TRON_0}","type":7,"hexList":["$signed"]}""")
        assertEquals("[\"${OtherWalletVectors.V3_SIG}\"]", r.obj("transaction")!!["signature"].toString())
        assertEquals(OtherWalletVectors.V3_ENTRY.substring(6), r.obj("transaction")!!.str("raw_data_hex"))
    }
}
