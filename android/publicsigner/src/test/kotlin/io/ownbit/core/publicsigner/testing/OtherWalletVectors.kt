// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.publicsigner.testing

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/**
 * Round-2 vectors of the other wallets' own QR formats (public `abandon … about` wallet, TRON #0
 * `TUEZSdKsoDHQMeZwihtdoBiN46zxhGWYdH`; never fund it):
 *
 * - TronLink V1–V4: the QR texts TronLink sends and the answers Ownbit must give, byte for byte
 *   (signatures recorded from the pinned engine, cross-checked with two secp256k1 libraries); the engine side is the
 *   golden vectors `O-TL-V1-ownership-ios` … `O-TL-V4-tip191-message`.
 * - TokenPocket TP-V1 (`pubsigner/tokenpocket/tp-v1.json`): a real request message and its 10
 *   dynamic-QR frames — refused with `err.tpUnsupported` (TokenPocket is watch-only).
 */
object OtherWalletVectors {

    const val TRON_0 = "TUEZSdKsoDHQMeZwihtdoBiN46zxhGWYdH"

    // ---- TronLink ---------------------------------------------------------------------------------------------

    const val V1_ENTRY = "0a1a5a18221654726f6e4c696e6b437573746f6d436f6e7472616374"
    const val V1_SIG = "c4e4c285fed57e138ab5be476870816067e34d7dbc0cc4eb04f54bc4bb681e3e76a0e0659627a6b78f5761b9d347e002e777570408d4a6ed30ed661f5582c3cd00"
    const val V1_REQUEST = """{"amount":0,"address":"$TRON_0","amountStr":"0","type":99,"hexList":["$V1_ENTRY"]}"""
    const val V1_ANSWER = """{"amount":0,"address":"$TRON_0","amountStr":"0","type":99,"hexList":["${V1_ENTRY}1241$V1_SIG"]}"""

    const val V2_ENTRY = "0a215a1f221d436f6c6457616c6c65744f776e6572566572696679436f6e7472616374"
    const val V2_REQUEST = """{"address":"$TRON_0","cN":0,"hexList":["$V2_ENTRY"],"tN":0,"type":99}"""

    const val V3_ENTRY = "0a85010a02ab122208010203040506070840e0dc94809e335a67080112630a2d747970652e676f6f676c65617069732e636f6d" +
        "2f70726f746f636f6c2e5472616e73666572436f6e747261637412320a1541c8599111f29c1e1e061265b4af93ea1f274ad78a121541eca9bc" +
        "828a3005b9a3b909f2cc5c2a54794de05f18c0843d70808891809e33"
    const val V3_SIG = "bc7da2e91ff44a0bb59e401c90a790fc4c4b1538570986517a0238224c55f0a147ccb24b14f959e0cbdc26c274d7e25fa4bcd728739d91ec082dcb7ef5dcc36701"
    const val V3_REQUEST = """{"amount":1,"address":"$TRON_0","amountStr":"1","type":1,"hexList":["$V3_ENTRY"]}"""
    const val V3_ANSWER = """{"amount":1,"address":"$TRON_0","amountStr":"1","type":1,"hexList":["${V3_ENTRY}1241$V3_SIG"]}"""

    const val V4_REQUEST = """{"address":"$TRON_0","type":102,"hexList":["hello ownbit"]}"""
    const val V4_MESSAGE_SIGNATURE = "0x99b4b65e883463501e600b497cf7293fe2ea7e143c5390a7d57162818a567f7762ef7b8a69a01a3654deb4c73e81263b29b151e3dd2ae91f464f3a3c2aac25501c"
    const val V4_ANSWER = """{"address":"$TRON_0","type":102,"hexList":["$V4_MESSAGE_SIGNATURE"]}"""

    // ---- TokenPocket ------------------------------------------------------------------------------------------

    private val tp: JsonObject by lazy {
        val url = checkNotNull(javaClass.classLoader?.getResource("pubsigner/tokenpocket/tp-v1.json")) { "tp-v1.json" }
        Json.parseToJsonElement(url.readText()).jsonObject
    }

    val tpRequest: String get() = tp.getValue("request").jsonPrimitive.content
    val tpRequestFrames: List<String> get() = tp.getValue("requestFrames").jsonArray.map { it.jsonPrimitive.content }

    /** TokenPocket's answer header (a text meant for TokenPocket): refused like every TokenPocket text. */
    const val TP_ANSWER_HEADER = "tron:signTransactionSignature-version=1.0&protocol=TokenPocket&network=tron&chain_id=11111&data={}"
}
