// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.chain.utxo

import org.bouncycastle.crypto.digests.Blake2bDigest
import java.io.ByteArrayOutputStream

/**
 * Zcash v5 transactions of the transparent kind the wallet builds (ZIP 225 serialisation, ZIP 244 txid and
 * transparent signature digest) — a Kotlin re-computation used to **check** what the ZEC bundle returns
 * (`zcashjs-lib-app-0251.js`). Signing stays in the bundle; nothing here signs.
 *
 * The digests follow the reference implementation `zcash-test-vectors/zip_0244.py` and are checked against its
 * published vectors (`ZcashV5Test`). Shielded (Sapling / Orchard) parts are never produced by the wallet: [parse]
 * rejects them, and the digests take the Sapling / Orchard digests as parameters (the empty-bundle digests by default).
 */
object ZcashV5 {

    /** `fOverwintered | 5`. */
    const val HEADER: Long = 0x80000005L

    /** v5 `nVersionGroupId`. */
    const val VERSION_GROUP_ID: Long = 0x26A7270AL

    /** The only hash type the wallet signs with. */
    const val SIGHASH_ALL: Int = 1

    /**
     * One transparent input.
     *
     * @property prevHash spent txid in **internal** byte order (the serialised form; display order reversed).
     */
    class TxIn(val prevHash: ByteArray, val prevIndex: Long, val scriptSig: ByteArray, val sequence: Long) {
        init {
            require(prevHash.size == 32) { "prevHash" }
        }
    }

    /** One transparent output. */
    class TxOut(val value: Long, val script: ByteArray)

    /** A v5 transaction without shielded parts. */
    class Tx(
        val branchId: Long,
        val lockTime: Long,
        val expiryHeight: Long,
        val ins: List<TxIn>,
        val outs: List<TxOut>,
    )

    /** BLAKE2b-256 with a 16-byte personalisation. */
    fun blake2b256(personalization: ByteArray, data: ByteArray): ByteArray {
        require(personalization.size == 16) { "personalization must be 16 bytes" }
        val d = Blake2bDigest(null, 32, null, personalization)
        d.update(data, 0, data.size)
        return ByteArray(32).also { d.doFinal(it, 0) }
    }

    private fun blake(personalization: String, data: ByteArray): ByteArray =
        blake2b256(personalization.toByteArray(Charsets.US_ASCII), data)

    /** `BLAKE2b("ZTxIdSaplingHash", [])`: digest of a transaction without Sapling spends / outputs. */
    val EMPTY_SAPLING_DIGEST: ByteArray get() = blake("ZTxIdSaplingHash", ByteArray(0))

    /** `BLAKE2b("ZTxIdOrchardHash", [])`: digest of a transaction without Orchard actions. */
    val EMPTY_ORCHARD_DIGEST: ByteArray get() = blake("ZTxIdOrchardHash", ByteArray(0))

    /** T.1 header digest over `header || versionGroupId || branchId || lockTime || expiryHeight`. */
    fun headerDigest(branchId: Long, lockTime: Long, expiryHeight: Long): ByteArray =
        blake("ZTxIdHeadersHash", bytes { u32(HEADER); u32(VERSION_GROUP_ID); u32(branchId); u32(lockTime); u32(expiryHeight) })

    fun prevoutsDigest(tx: Tx): ByteArray = blake("ZTxIdPrevoutHash", bytes { tx.ins.forEach { write(it.prevHash); u32(it.prevIndex) } })

    fun sequenceDigest(tx: Tx): ByteArray = blake("ZTxIdSequencHash", bytes { tx.ins.forEach { u32(it.sequence) } })

    fun outputsDigest(tx: Tx): ByteArray = blake("ZTxIdOutputsHash", bytes { tx.outs.forEach { u64(it.value); varSlice(it.script) } })

    /** T.2 transparent digest of the txid (no amounts / scripts; empty bundle → the personalised empty hash). */
    fun transparentTxidDigest(tx: Tx): ByteArray =
        if (tx.ins.isEmpty() && tx.outs.isEmpty()) {
            blake("ZTxIdTranspaHash", ByteArray(0))
        } else {
            blake("ZTxIdTranspaHash", prevoutsDigest(tx) + sequenceDigest(tx) + outputsDigest(tx))
        }

    private fun rootDigest(tx: Tx, transparent: ByteArray, sapling: ByteArray, orchard: ByteArray): ByteArray {
        val personalization = "ZcashTxHash_".toByteArray(Charsets.US_ASCII) + bytes { u32(tx.branchId) }
        return blake2b256(personalization, headerDigest(tx.branchId, tx.lockTime, tx.expiryHeight) + transparent + sapling + orchard)
    }

    /** The txid digest in internal byte order (what the test vectors list). */
    fun txidDigest(tx: Tx, saplingDigest: ByteArray = EMPTY_SAPLING_DIGEST, orchardDigest: ByteArray = EMPTY_ORCHARD_DIGEST): ByteArray =
        rootDigest(tx, transparentTxidDigest(tx), saplingDigest, orchardDigest)

    /** The txid as nodes and explorers show it (byte-reversed hex) — iOS / the bundle send this as `txHash`. */
    fun txid(tx: Tx): String = RawUtxoTransaction.toHex(txidDigest(tx).reversedArray())

    /**
     * S.2 signature digest of transparent input [inIndex] for `SIGHASH_ALL`: every input's amount and spent
     * scriptPubKey are committed (a P2SH input commits the P2SH script, not the redeem script).
     *
     * @param amounts value of the output each input spends, in input order.
     * @param scriptPubKeys scriptPubKey of the output each input spends, in input order.
     */
    fun transparentSigDigest(
        tx: Tx,
        inIndex: Int,
        amounts: List<Long>,
        scriptPubKeys: List<ByteArray>,
        saplingDigest: ByteArray = EMPTY_SAPLING_DIGEST,
        orchardDigest: ByteArray = EMPTY_ORCHARD_DIGEST,
    ): ByteArray {
        require(amounts.size == tx.ins.size && scriptPubKeys.size == tx.ins.size) { "one amount / script per input" }
        val input = tx.ins[inIndex]
        val amountsDigest = blake("ZTxTrAmountsHash", bytes { amounts.forEach { u64(it) } })
        val scriptsDigest = blake("ZTxTrScriptsHash", bytes { scriptPubKeys.forEach { varSlice(it) } })
        val txinDigest = blake("Zcash___TxInHash", bytes {
            write(input.prevHash); u32(input.prevIndex); u64(amounts[inIndex]); varSlice(scriptPubKeys[inIndex]); u32(input.sequence)
        })
        val transparent = blake(
            "ZTxIdTranspaHash",
            byteArrayOf(SIGHASH_ALL.toByte()) + prevoutsDigest(tx) + amountsDigest + scriptsDigest + sequenceDigest(tx) +
                outputsDigest(tx) + txinDigest,
        )
        return rootDigest(tx, transparent, saplingDigest, orchardDigest)
    }

    /** ZIP 225 serialisation (no Sapling spends / outputs, no Orchard actions). */
    fun serialize(tx: Tx): ByteArray = bytes {
        u32(HEADER); u32(VERSION_GROUP_ID); u32(tx.branchId); u32(tx.lockTime); u32(tx.expiryHeight)
        compactSize(tx.ins.size.toLong())
        tx.ins.forEach { write(it.prevHash); u32(it.prevIndex); varSlice(it.scriptSig); u32(it.sequence) }
        compactSize(tx.outs.size.toLong())
        tx.outs.forEach { u64(it.value); varSlice(it.script) }
        write(byteArrayOf(0, 0, 0)) // nSpendsSapling, nOutputsSapling, nActionsOrchard
    }

    /** Parses a v5 transaction without shielded parts; `null` for anything else (incl. trailing bytes). */
    fun parse(bytes: ByteArray): Tx? = try {
        val r = Cursor(bytes)
        require(r.u32() == HEADER && r.u32() == VERSION_GROUP_ID) { "not v5" }
        val branchId = r.u32()
        val lockTime = r.u32()
        val expiry = r.u32()
        val ins = List(r.count()) { TxIn(r.take(32), r.u32(), r.take(r.count()), r.u32()) }
        val outs = List(r.count()) { TxOut(r.u64(), r.take(r.count())) }
        require(r.count() == 0 && r.count() == 0 && r.count() == 0) { "shielded parts" }
        require(r.atEnd()) { "trailing bytes" }
        Tx(branchId, lockTime, expiry, ins, outs)
    } catch (e: IllegalArgumentException) {
        null
    } catch (e: IndexOutOfBoundsException) {
        null
    }

    // --- byte helpers ---------------------------------------------------------------------------------------------

    private class Writer : ByteArrayOutputStream() {
        fun u32(v: Long) { for (i in 0 until 4) write(((v ushr (8 * i)) and 0xff).toInt()) }
        fun u64(v: Long) { for (i in 0 until 8) write(((v ushr (8 * i)) and 0xff).toInt()) }
        fun compactSize(n: Long) {
            when {
                n < 0xfd -> write(n.toInt())
                n <= 0xffff -> { write(0xfd); write((n and 0xff).toInt()); write(((n ushr 8) and 0xff).toInt()) }
                else -> { write(0xfe); u32(n) }
            }
        }
        fun varSlice(b: ByteArray) { compactSize(b.size.toLong()); write(b) }
    }

    private inline fun bytes(block: Writer.() -> Unit): ByteArray = Writer().apply(block).toByteArray()

    private class Cursor(private val b: ByteArray) {
        private var pos = 0
        fun take(n: Int): ByteArray {
            require(n >= 0 && pos + n <= b.size) { "eof" }
            return b.copyOfRange(pos, pos + n).also { pos += n }
        }
        fun u32(): Long {
            val x = take(4)
            var v = 0L
            for (i in 0 until 4) v = v or ((x[i].toLong() and 0xff) shl (8 * i))
            return v
        }
        fun u64(): Long {
            val x = take(8)
            var v = 0L
            for (i in 0 until 8) v = v or ((x[i].toLong() and 0xff) shl (8 * i))
            return v
        }
        fun count(): Int {
            val first = take(1)[0].toInt() and 0xff
            val n = when (first) {
                0xfd -> { val x = take(2); (x[0].toLong() and 0xff) or ((x[1].toLong() and 0xff) shl 8) }
                0xfe -> u32()
                0xff -> u64()
                else -> first.toLong()
            }
            require(n in 0..100_000) { "count" }
            return n.toInt()
        }
        fun atEnd(): Boolean = pos == b.size
    }
}
