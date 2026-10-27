// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.publicsigner.sign

import io.ownbit.core.crypto.util.Hex
import io.ownbit.core.publicsigner.testing.OtherWalletVectors
import io.ownbit.core.scanner.publicqr.StrictJson
import io.ownbit.core.scanner.publicqr.TronLinkQrFormat
import kotlinx.serialization.json.JsonObject
import org.junit.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Ownbit's answers in the other wallets' own formats: [TronLinkAnswerCodec] (V1 / V3 / V4
 * byte-exact). Ownbit never answers TokenPocket (its requests are refused).
 */
class OtherWalletAnswersTest {

    private fun bean(text: String): JsonObject = TronLinkQrFormat.parse(text)!!.json

    @Test fun `TronLink answers are byte for byte the V1, V3 and V4 answers`() {
        val v1 = TronLinkAnswerCodec.signedTransaction(Hex.decode(OtherWalletVectors.V1_ENTRY), Hex.decode(OtherWalletVectors.V1_SIG))
        assertEquals(listOf(OtherWalletVectors.V1_ANSWER), TronLinkAnswerCodec.encode(bean(OtherWalletVectors.V1_REQUEST), listOf(v1)))
        assertEquals(290, OtherWalletVectors.V1_ANSWER.length)
        val v3 = TronLinkAnswerCodec.signedTransaction(Hex.decode(OtherWalletVectors.V3_ENTRY), Hex.decode(OtherWalletVectors.V3_SIG))
        assertEquals(listOf(OtherWalletVectors.V3_ANSWER), TronLinkAnswerCodec.encode(bean(OtherWalletVectors.V3_REQUEST), listOf(v3)))
        val engineV4 = "99b4b65e883463501e600b497cf7293fe2ea7e143c5390a7d57162818a567f7762ef7b8a69a01a3654deb4c73e81263b29b151e3dd2ae91f464f3a3c2aac255001"
        assertEquals(OtherWalletVectors.V4_MESSAGE_SIGNATURE, TronLinkAnswerCodec.signedMessage(Hex.decode(engineV4)))
        assertEquals(listOf(OtherWalletVectors.V4_ANSWER), TronLinkAnswerCodec.encode(bean(OtherWalletVectors.V4_REQUEST), listOf(OtherWalletVectors.V4_MESSAGE_SIGNATURE)))
        // Android's shape: every key echoed in its place (cN / tN stay 0).
        val android = TronLinkAnswerCodec.encode(bean(OtherWalletVectors.V2_REQUEST), listOf("ab"))
        assertEquals("""{"address":"${OtherWalletVectors.TRON_0}","cN":0,"hexList":["ab"],"tN":0,"type":99}""", android.single())
    }

    @Test fun `TronLink answers above 1000 characters go in numbered parts in TronLink's field order`() {
        val request = bean(OtherWalletVectors.V3_REQUEST)
        fun entry(joinedLength: Int) = "a".repeat(joinedLength - 3)
        assertEquals(1, TronLinkAnswerCodec.encode(request, listOf(entry(999))).size)
        assertEquals(1, TronLinkAnswerCodec.encode(request, listOf(entry(1_000))).size, "exactly 1000 stays one code (TronLink's splitter would show none)")
        val two = TronLinkAnswerCodec.encode(request, listOf(entry(1_001)))
        assertEquals(2, two.size)
        // 998 × "a" + "&&&": the cut falls inside the separator (TronLink joins the pieces as text).
        assertEquals("""{"address":"${OtherWalletVectors.TRON_0}","cN":1,"hexList":["${"a".repeat(998)}&&"],"tN":2,"type":0}""", two[0])
        assertEquals("""{"address":"${OtherWalletVectors.TRON_0}","cN":2,"hexList":["&"],"tN":2,"type":1}""", two[1])
        assertEquals(listOf(entry(1_001)), TronLinkAnswerCodec.decode(two).hexList)
        val three = TronLinkAnswerCodec.encode(request, listOf(entry(2_500)))
        assertEquals(3, three.size)
        assertTrue("address" !in StrictJson.parseObject(three[1])!!.keys, "the middle part names no address")
        // Read back with the scanner's parser and collector: the same entry.
        val back = TronLinkAnswerCodec.decode(three)
        assertEquals(listOf(entry(2_500)), back.hexList)
        assertEquals(1, back.type)
        assertEquals(OtherWalletVectors.TRON_0, back.address)
    }
}
