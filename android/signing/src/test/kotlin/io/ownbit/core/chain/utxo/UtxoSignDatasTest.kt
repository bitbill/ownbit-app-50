// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.chain.utxo

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import org.junit.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull

/**
 * What a UTXO bundle signs must be the numbers Kotlin checked ([UtxoSignDatas]), and the signed transaction must spend
 * and pay exactly what was asked ([UtxoSignedTxVerifier]).
 */
class UtxoSignDatasTest {

    private val txA = "24d3e087bfe0c15f606db97836449852a44414f98f425301fb08affb3d64c11c"
    private val txB = "50f6096d18f5436cd23d8b3eb782f58fa619e912a4f426b65f981402e2a95eb6"
    private val p2pkh = RawUtxoTransaction.hexToBytes("76a914" + "11".repeat(20) + "88ac")

    private fun json(text: String): JsonObject = Json.parseToJsonElement(text).jsonObject

    private fun btc(satoshis: String = "250000", index: String = "0", txid: String = "\"$txA\"", amount: String = "100000") = json(
        """{"inputs":[{"txHash":$txid,"index":$index,"bip39Index":0,"isChange":false,"satoshis":$satoshis,"segwit":"D"}],
           "outputs":[{"address":"bc1q","amount":$amount}],"decimals":8,"ophex":"","locktime":0,"caStatus":0}""",
    )

    @Test
    fun `exact integers are read and the canonical text carries exactly them`() {
        val read = assertNotNull(UtxoSignDatas.inputs(UtxoChainProfile.BTC, btc(txid = "\"${txA.uppercase()}\"")))
        assertEquals(listOf(Triple(txA, 0L, 250_000L)), read.map { Triple(it.txid, it.vout, it.satoshis) })
        val canonical = assertNotNull(UtxoSignDatas.canonical(UtxoChainProfile.BTC, btc(txid = "\"${txA.uppercase()}\"")))
        val input = canonical["inputs"]!!.jsonArray[0].jsonObject
        assertEquals("\"$txA\"", input["txHash"].toString(), "lower-case txid")
        assertEquals("\"D\"", input["segwit"].toString(), "other keys are kept")
        assertEquals(UtxoSignDatas.MAX_SAFE_INTEGER, UtxoSignDatas.inputs(UtxoChainProfile.BTC, btc(satoshis = "9007199254740991"))!![0].satoshis)
    }

    @Test
    fun `anything JS could read as another number refuses the whole request`() {
        for (bad in listOf("100000.0000000000000000001", "1e5", "-1", "0100", "\"250000\"", "true", "null", "9007199254740992")) {
            assertNull(UtxoSignDatas.inputs(UtxoChainProfile.BTC, btc(satoshis = bad)), "satoshis $bad")
            assertNull(UtxoSignDatas.canonical(UtxoChainProfile.BTC, btc(amount = bad)), "amount $bad")
        }
        assertNull(UtxoSignDatas.inputs(UtxoChainProfile.BTC, btc(index = "4294967296")), "vout above u32")
        assertNull(UtxoSignDatas.inputs(UtxoChainProfile.BTC, btc(txid = "\"0x$txA\"")), "txid with 0x")
        assertNull(UtxoSignDatas.inputs(UtxoChainProfile.BTC, btc(txid = "\"${txA.drop(2)}\"")), "short txid")
        assertNull(UtxoSignDatas.inputs(UtxoChainProfile.BTC, json("""{"inputs":[],"outputs":[]}""")), "no inputs")
        // The other chains use txid / vout.
        val ltc = json("""{"inputs":[{"scriptPubKey":"","txid":"$txB","vout":7,"satoshis":5}],"outputs":[{"address":"L","amount":4}]}""")
        assertEquals(7L, UtxoSignDatas.inputs(UtxoChainProfile.LTC, ltc)!![0].vout)
        assertNull(UtxoSignDatas.inputs(UtxoChainProfile.BTC, ltc), "BTC keys are txHash / index")
    }

    @Test
    fun `the verifier accepts exactly the requested inputs, amounts and lock time`() {
        val request = json(
            """{"inputs":[{"txHash":"$txA","index":0,"satoshis":250000},{"txHash":"$txB","index":7,"satoshis":1234567}],
               "outputs":[{"address":"a","amount":1000000},{"address":"b","amount":470000}],"ophex":"","locktime":800000}""",
        )
        val inputs = listOf(txA to 0L, txB to 7L)
        val good = UtxoTestSerializer.serialize(inputs, listOf(1_000_000L to p2pkh, 470_000L to p2pkh), 800_000, 0xfffffffeL)
        val txId = RawUtxoTransaction.decode(good)!!.txId
        assertEquals(txId, UtxoSignedTxVerifier.verify(UtxoChainProfile.BTC, request, UtxoSignedRaw(txId, good)))
        assertEquals(txId, UtxoSignedTxVerifier.verify(UtxoChainProfile.BTC, request, UtxoSignedRaw(null, good)), "hex-only bundles")

        val wrongAmount = UtxoTestSerializer.serialize(inputs, listOf(1_000_001L to p2pkh, 470_000L to p2pkh), 800_000, 0xfffffffeL)
        val wrongOrder = UtxoTestSerializer.serialize(inputs.reversed(), listOf(1_000_000L to p2pkh, 470_000L to p2pkh), 800_000, 0xfffffffeL)
        val wrongLock = UtxoTestSerializer.serialize(inputs, listOf(1_000_000L to p2pkh, 470_000L to p2pkh), 0, 0xfffffffeL)
        for (hex in listOf(wrongAmount, wrongOrder, wrongLock)) {
            assertNull(UtxoSignedTxVerifier.verify(UtxoChainProfile.BTC, request, UtxoSignedRaw(null, hex)))
        }
        assertNull(UtxoSignedTxVerifier.verify(UtxoChainProfile.BTC, request, UtxoSignedRaw("00".repeat(32), good)), "txid of another hex")
        assertNull(UtxoSignedTxVerifier.verify(UtxoChainProfile.BTC, request, UtxoSignedRaw(null, "zz")), "not a transaction")
    }

    @Test
    fun `a BTC OP_RETURN comes first and must carry the requested data`() {
        val request = json("""{"inputs":[{"txHash":"$txA","index":0,"satoshis":5000}],"outputs":[{"address":"a","amount":4000}],"ophex":"cafe","locktime":0}""")
        val opReturn = RawUtxoTransaction.hexToBytes("6a02cafe")
        val good = UtxoTestSerializer.serialize(listOf(txA to 0L), listOf(0L to opReturn, 4_000L to p2pkh), 0, 0xffffffffL)
        assertNotNull(UtxoSignedTxVerifier.verify(UtxoChainProfile.BTC, request, UtxoSignedRaw(null, good)))
        val other = UtxoTestSerializer.serialize(listOf(txA to 0L), listOf(0L to RawUtxoTransaction.hexToBytes("6a02beef"), 4_000L to p2pkh), 0, 0xffffffffL)
        assertNull(UtxoSignedTxVerifier.verify(UtxoChainProfile.BTC, request, UtxoSignedRaw(null, other)))
    }
}
