// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.chain.utxo

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import org.junit.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * ZIP 225 / ZIP 244 re-computation ([ZcashV5]) against the official test vectors of the Zcash reference implementation
 * (`zcash-test-vectors/test-vectors/json/zip_0244.json`, copied verbatim into the test resources), and the ZEC checks
 * of [RawUtxoTransaction] / [UtxoSignedTxVerifier].
 */
class ZcashV5Test {

    private fun hex(s: String) = RawUtxoTransaction.hexToBytes(s)
    private fun ByteArray.hex() = RawUtxoTransaction.toHex(this)

    // --- official vectors ------------------------------------------------------------------------------------------

    private class Vector(
        val tx: ByteArray,
        val txid: String,
        val amounts: List<Long>,
        val scriptPubKeys: List<ByteArray>,
        val transparentInput: Int?,
        val sighashAll: String?,
    )

    private fun vectors(): List<Vector> {
        val text = javaClass.getResourceAsStream("/zcash/zip_0244.json")!!.bufferedReader().readText()
        val rows = Json.parseToJsonElement(text).jsonArray.drop(2).map { it.jsonArray }
        return rows.map { r ->
            Vector(
                tx = hex(r[0].jsonPrimitive.content),
                txid = r[1].jsonPrimitive.content,
                amounts = r[3].jsonArray.map { it.jsonPrimitive.long },
                scriptPubKeys = r[4].jsonArray.map { e -> e.jsonPrimitive.content.let { if (it.isEmpty()) ByteArray(0) else hex(it) } },
                transparentInput = r[5].takeUnless { it is JsonNull }?.jsonPrimitive?.content?.toInt(),
                sighashAll = r[7].takeUnless { it is JsonNull }?.jsonPrimitive?.content,
            )
        }
    }

    /**
     * Test-only full ZIP 225 parser: the transparent part becomes a [ZcashV5.Tx] (checked with the production digests),
     * the Sapling / Orchard digests are computed here with the ZIP 244 rules so every vector can be used.
     */
    private class Parsed(val tx: ZcashV5.Tx, val sapling: ByteArray, val orchard: ByteArray)

    private fun parseFull(b: ByteArray): Parsed {
        var p = 0
        fun take(n: Int) = b.copyOfRange(p, p + n).also { p += n }
        fun u32(): Long { val x = take(4); var v = 0L; for (i in 0 until 4) v = v or ((x[i].toLong() and 0xff) shl (8 * i)); return v }
        fun u64(): Long { val x = take(8); var v = 0L; for (i in 0 until 8) v = v or ((x[i].toLong() and 0xff) shl (8 * i)); return v }
        fun cs(): Int {
            val f = take(1)[0].toInt() and 0xff
            return when (f) {
                0xfd -> { val x = take(2); (x[0].toInt() and 0xff) or ((x[1].toInt() and 0xff) shl 8) }
                0xfe -> u32().toInt()
                else -> f
            }
        }
        fun blake(p16: String, data: ByteArray) = ZcashV5.blake2b256(p16.toByteArray(), data)
        fun cat(parts: List<ByteArray>) = parts.fold(ByteArray(0)) { a, x -> a + x }

        assertEquals(ZcashV5.HEADER, u32())
        assertEquals(ZcashV5.VERSION_GROUP_ID, u32())
        val branch = u32(); val lock = u32(); val expiry = u32()
        val ins = List(cs()) { ZcashV5.TxIn(take(32), u32(), take(cs()), u32()) }
        val outs = List(cs()) { ZcashV5.TxOut(u64(), take(cs())) }
        val nSpends = cs(); val spends = List(nSpends) { take(96) }
        val nOutputs = cs(); val sOuts = List(nOutputs) { take(756) }
        val valueBalance = if (nSpends + nOutputs > 0) take(8) else ByteArray(0)
        val anchor = if (nSpends > 0) take(32) else ByteArray(0)
        take(192 * nSpends); take(64 * nSpends); take(192 * nOutputs)
        if (nSpends + nOutputs > 0) take(64)
        val nActions = cs(); val actions = List(nActions) { take(820) }
        var flags = ByteArray(0); var vbOrchard = ByteArray(0); var anchorOrchard = ByteArray(0)
        if (nActions > 0) {
            flags = take(1); vbOrchard = take(8); anchorOrchard = take(32); take(cs()); take(64 * nActions); take(64)
        }
        assertEquals(b.size, p, "whole transaction parsed")

        val sapling = if (nSpends + nOutputs == 0) {
            blake("ZTxIdSaplingHash", ByteArray(0))
        } else {
            val spendsDigest = if (nSpends == 0) blake("ZTxIdSSpendsHash", ByteArray(0)) else blake(
                "ZTxIdSSpendsHash",
                blake("ZTxIdSSpendCHash", cat(spends.map { it.copyOfRange(32, 64) })) +
                    blake("ZTxIdSSpendNHash", cat(spends.map { it.copyOfRange(0, 32) + anchor + it.copyOfRange(64, 96) })),
            )
            val outputsDigest = if (nOutputs == 0) blake("ZTxIdSOutputHash", ByteArray(0)) else blake(
                "ZTxIdSOutputHash",
                blake("ZTxIdSOutC__Hash", cat(sOuts.map { it.copyOfRange(32, 96) + it.copyOfRange(96, 148) })) +
                    blake("ZTxIdSOutM__Hash", cat(sOuts.map { it.copyOfRange(148, 660) })) +
                    blake("ZTxIdSOutN__Hash", cat(sOuts.map { it.copyOfRange(0, 32) + it.copyOfRange(660, 756) })),
            )
            blake("ZTxIdSaplingHash", spendsDigest + outputsDigest + valueBalance)
        }
        val orchard = if (nActions == 0) {
            blake("ZTxIdOrchardHash", ByteArray(0))
        } else {
            blake(
                "ZTxIdOrchardHash",
                blake("ZTxIdOrcActCHash", cat(actions.map { it.copyOfRange(32, 64) + it.copyOfRange(96, 212) })) +
                    blake("ZTxIdOrcActMHash", cat(actions.map { it.copyOfRange(212, 724) })) +
                    blake("ZTxIdOrcActNHash", cat(actions.map { it.copyOfRange(0, 32) + it.copyOfRange(64, 96) + it.copyOfRange(724, 820) })) +
                    flags + vbOrchard + anchorOrchard,
            )
        }
        return Parsed(ZcashV5.Tx(branch, lock, expiry, ins, outs), sapling, orchard)
    }

    @Test
    fun `txid digests match the ZIP 244 reference vectors`() {
        val all = vectors()
        assertEquals(10, all.size)
        for ((i, v) in all.withIndex()) {
            val parsed = parseFull(v.tx)
            assertEquals(v.txid, ZcashV5.txidDigest(parsed.tx, parsed.sapling, parsed.orchard).hex(), "vector $i txid")
        }
    }

    @Test
    fun `transparent SIGHASH_ALL digests match the ZIP 244 reference vectors`() {
        var checked = 0
        for ((i, v) in vectors().withIndex()) {
            val input = v.transparentInput ?: continue
            val expected = v.sighashAll ?: continue
            val parsed = parseFull(v.tx)
            val digest = ZcashV5.transparentSigDigest(parsed.tx, input, v.amounts, v.scriptPubKeys, parsed.sapling, parsed.orchard)
            assertEquals(expected, digest.hex(), "vector $i sighash_all")
            checked++
        }
        assertEquals(6, checked)
    }

    // --- the wallet's transparent-only transactions ------------------------------------------------------------------

    private val p2pkh = hex("76a914" + "11".repeat(20) + "88ac")

    private fun sample(branch: Long = 0x37a5165bL, lock: Long = 0, expiry: Long = 0) = ZcashV5.Tx(
        branchId = branch,
        lockTime = lock,
        expiryHeight = expiry,
        ins = listOf(
            ZcashV5.TxIn(hex("aa".repeat(32)), 0, hex("00"), 0xffffffffL),
            ZcashV5.TxIn(hex("bb".repeat(32)), 7, ByteArray(0), 0xffffffffL),
        ),
        outs = listOf(ZcashV5.TxOut(1_000_000, p2pkh), ZcashV5.TxOut(470_000, p2pkh)),
    )

    @Test
    fun `serialize and parse round-trip, shielded parts and trailing bytes are refused`() {
        val raw = ZcashV5.serialize(sample(expiry = 12, lock = 34))
        assertTrue(raw.hex().startsWith("050000800a27a7265b16a537" + "22000000" + "0c000000"))
        assertTrue(raw.hex().endsWith("000000"))
        val back = assertNotNull(ZcashV5.parse(raw))
        assertEquals(0x37a5165bL, back.branchId)
        assertEquals(34L, back.lockTime)
        assertEquals(12L, back.expiryHeight)
        assertEquals(listOf(0L, 7L), back.ins.map { it.prevIndex })
        assertEquals(listOf(1_000_000L, 470_000L), back.outs.map { it.value })
        assertNull(ZcashV5.parse(raw + byteArrayOf(0)))
        assertNull(ZcashV5.parse(raw.copyOf(raw.size - 3) + byteArrayOf(1, 0, 0)), "a Sapling spend count")
        assertNull(ZcashV5.parse(raw.copyOf(raw.size - 1)))
    }

    @Test
    fun `txid is the reversed ZIP 244 digest and ignores the scriptSigs`() {
        val tx = sample()
        assertEquals(ZcashV5.txidDigest(tx).reversedArray().hex(), ZcashV5.txid(tx))
        val unsigned = ZcashV5.Tx(tx.branchId, 0, 0, tx.ins.map { ZcashV5.TxIn(it.prevHash, it.prevIndex, ByteArray(0), it.sequence) }, tx.outs)
        assertEquals(ZcashV5.txid(tx), ZcashV5.txid(unsigned), "v5 txids do not commit to signatures")
        assertTrue(ZcashV5.txid(tx) != ZcashV5.txid(sample(branch = 0x5437f330L)), "the branch id is committed")
    }

    @Test
    fun `RawUtxoTransaction decodes v5 with header fields and the ZIP 244 txid`() {
        val tx = sample(expiry = 5, lock = 6)
        val raw = assertNotNull(RawUtxoTransaction.decode(ZcashV5.serialize(tx).hex()))
        assertTrue(raw.overwintered)
        assertEquals(5L, raw.version)
        assertEquals(ZcashV5.VERSION_GROUP_ID, raw.versionGroupId)
        assertEquals(0x37a5165bL, raw.consensusBranchId)
        assertEquals(5L, raw.expiryHeight)
        assertEquals(6L, raw.lockTime)
        assertEquals(ZcashV5.txid(tx), raw.txId)
        assertEquals(listOf("aa".repeat(32).chunked(2).reversed().joinToString("") + ":0", "bb".repeat(32) + ":7"), raw.inputs.map { it.outpoint })
        assertEquals(listOf(1_000_000L, 470_000L), raw.outputs.map { it.value })
    }

    // --- post-sign verification ---------------------------------------------------------------------------------------

    private class In(val txHash: String, val vout: Int, val bip39Index: Int, val satoshi: Long, val isChange: Boolean)
    private class Out(val address: String, val satoshi: Long)

    private val inputs = listOf(
        In("24d3e087bfe0c15f606db97836449852a44414f98f425301fb08affb3d64c11c", 0, 0, 250_000, false),
        In("50f6096d18f5436cd23d8b3eb782f58fa619e912a4f426b65f981402e2a95eb6", 7, 3, 1_234_567, true),
    )
    private val outputs = listOf(Out("t1evUDHwrkA1py7AswqKZHKENx4jRm6SFep", 1_000_000), Out("t3KGYhWbLNcnLkc6L9T7daw4nTw7a7W5fG5", 470_000))

    /** The ZEC `signDatas` the app's assembler writes (iOS `BCHInput.toDictionary`), plus the v5 [fields]. */
    private fun signDatas(fields: JsonObject?): JsonObject {
        val base = Json.parseToJsonElement(
            buildString {
                append("{\"inputs\":[")
                append(inputs.joinToString(",") {
                    "{\"scriptPubKey\":\"\",\"txid\":\"${it.txHash}\",\"vout\":${it.vout},\"bip39Index\":${it.bip39Index}," +
                        "\"isChange\":${it.isChange},\"satoshis\":${it.satoshi}}"
                })
                append("],\"outputs\":[")
                append(outputs.joinToString(",") { "{\"address\":\"${it.address}\",\"amount\":${it.satoshi}}" })
                append("],\"decimals\":8}")
            },
        ) as JsonObject
        return ZecSignFields.merge(base, fields)
    }

    /** What a correct bundle returns for [signDatas] (scripts are not compared by the verifier). */
    private fun bundleV5(branch: Long, expiry: Long = 0, lock: Long = 0): UtxoSignedRaw {
        val tx = ZcashV5.Tx(
            branch, lock, expiry,
            inputs.map { ZcashV5.TxIn(hex(it.txHash).reversedArray(), it.vout.toLong(), hex("00"), 0xffffffffL) },
            outputs.map { ZcashV5.TxOut(it.satoshi, p2pkh) },
        )
        return UtxoSignedRaw(ZcashV5.txid(tx), ZcashV5.serialize(tx).hex())
    }

    @Test
    fun `sign data carries the four iOS v5 fields`() {
        val d = signDatas(ZecSignFields.v5(933_566_043L))
        assertEquals("""{"zecTxVersion":5,"zecBranchId":933566043,"zecExpiryHeight":0,"zecLockTime":0}""",
            JsonObject(ZecSignFields.KEYS.associateWith { d[it]!! }).toString())
        assertEquals(5, ZecSignFields.txVersion(d))
        assertEquals(4, ZecSignFields.txVersion(signDatas(null)))
        assertIs<JsonArray>(d["inputs"])
    }

    @Test
    fun `verifier accepts the requested v5 transaction and returns its txid`() {
        val raw = bundleV5(0x37a5165bL)
        val r = UtxoSignedTxVerifier.verify(UtxoChainProfile.ZEC, signDatas(ZecSignFields.v5(0x37a5165bL)), raw)
        assertEquals(raw.txId!!, r)
    }

    @Test
    fun `verifier refuses a v5 transaction with another branch id, lock time, expiry or txid`() {
        val d = signDatas(ZecSignFields.v5(0x37a5165bL))
        assertNull(UtxoSignedTxVerifier.verify(UtxoChainProfile.ZEC, d, bundleV5(0x5437f330L)))
        assertNull(UtxoSignedTxVerifier.verify(UtxoChainProfile.ZEC, d, bundleV5(0x37a5165bL, expiry = 1)))
        assertNull(UtxoSignedTxVerifier.verify(UtxoChainProfile.ZEC, d, bundleV5(0x37a5165bL, lock = 1)))
        val good = bundleV5(0x37a5165bL)
        assertNull(UtxoSignedTxVerifier.verify(UtxoChainProfile.ZEC, d, UtxoSignedRaw("00".repeat(32), good.rawHex)))
    }

    @Test
    fun `verifier refuses a format other than the requested one`() {
        // v5 returned for a v4 request (no zec fields) …
        assertNull(UtxoSignedTxVerifier.verify(UtxoChainProfile.ZEC, signDatas(null), bundleV5(0x37a5165bL)))
        // … and a plain (non-overwintered) transaction for a v5 request.
        val legacy = UtxoTestSerializer.serialize(inputs.map { it.txHash to it.vout.toLong() }, outputs.map { it.satoshi to p2pkh }, 0, 0xffffffffL)
        val legacyRaw = UtxoSignedRaw(RawUtxoTransaction.decode(legacy)!!.txId, legacy)
        assertNull(UtxoSignedTxVerifier.verify(UtxoChainProfile.ZEC, signDatas(ZecSignFields.v5(0x37a5165bL)), legacyRaw))
    }
}
