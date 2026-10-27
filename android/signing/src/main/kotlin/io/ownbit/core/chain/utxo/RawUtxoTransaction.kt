// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.chain.utxo

import java.io.ByteArrayOutputStream
import java.security.MessageDigest

/**
 * Minimal decoder for the raw transactions the UTXO bundles produce: Bitcoin serialisation (BTC / BCH / LTC /
 * DOGE / DASH / DGB / ZEN, BIP144 segwit marker for BTC / LTC), Zcash overwinter/sapling v3/v4 headers (ZEC) and
 * Zcash v5 (ZIP 225 — parsed by [ZcashV5], transparent-only, txid per ZIP 244).
 * Only the transparent part is read (version, inputs, outputs, witnesses, lock time); ZEC v4 shielded fields after
 * the lock time are ignored.
 *
 * Used to compute the transaction id of hex-only JS results (iOS `BTCTransaction(hex:)` hashes the hex:
 * double SHA-256, reversed) and to check that a signed transaction spends / pays exactly what the user confirmed.
 *
 * @property version transaction version (without the ZEC overwinter flag).
 * @property overwintered ZEC overwinter/sapling header (`fOverwintered`).
 * @property versionGroupId ZEC version group id, 0 otherwise.
 * @property inputs inputs in order.
 * @property outputs outputs in order.
 * @property lockTime `nLockTime`.
 * @property hasWitness BIP144 serialisation.
 * @property txId transaction id (hex, display byte order; ZEC v5: the ZIP 244 digest, reversed).
 * @property consensusBranchId ZEC v5 `nConsensusBranchId`, 0 otherwise.
 * @property expiryHeight ZEC v5 `nExpiryHeight`, 0 otherwise.
 */
class RawUtxoTransaction private constructor(
    val version: Long,
    val overwintered: Boolean,
    val versionGroupId: Long,
    val inputs: List<Input>,
    val outputs: List<Output>,
    val lockTime: Long,
    val hasWitness: Boolean,
    val txId: String,
    val consensusBranchId: Long = 0L,
    val expiryHeight: Long = 0L,
) {
    /**
     * @property prevTxId spent transaction id (display byte order, lower-case hex).
     * @property prevVout spent output index.
     * @property scriptSig unlocking script.
     * @property sequence `nSequence` (0xfffffffd = BIP125 replaceable, 0xffffffff = final).
     * @property witness witness stack items (segwit inputs).
     */
    class Input(
        val prevTxId: String,
        val prevVout: Long,
        val scriptSig: ByteArray,
        val sequence: Long,
        val witness: List<ByteArray>,
    ) {
        /** `txid:vout`, the identity used by [io.ownbit.core.model.fee.Utxo.outpoint]. */
        val outpoint: String get() = "$prevTxId:$prevVout"
    }

    /**
     * @property value amount in the smallest unit.
     * @property script locking script.
     */
    class Output(val value: Long, val script: ByteArray) {
        /** `OP_RETURN <data>` output. */
        val isOpReturn: Boolean get() = script.isNotEmpty() && (script[0].toInt() and 0xff) == OP_RETURN

        /** Data pushed by an `OP_RETURN` output (single push), `null` otherwise. */
        val opReturnData: ByteArray?
            get() {
                if (!isOpReturn || script.size < 2) return null
                val op = script[1].toInt() and 0xff
                return when {
                    op in 1..75 -> script.copyOfRange(2, minOf(script.size, 2 + op))
                    op == 0x4c && script.size >= 3 -> {
                        val n = script[2].toInt() and 0xff
                        script.copyOfRange(3, minOf(script.size, 3 + n))
                    }
                    op == 0x4d && script.size >= 4 -> {
                        val n = (script[2].toInt() and 0xff) or ((script[3].toInt() and 0xff) shl 8)
                        script.copyOfRange(4, minOf(script.size, 4 + n))
                    }
                    else -> null
                }
            }
    }

    companion object {
        private const val OP_RETURN = 0x6a

        /** Sequence of RBF-enabled inputs (BIP125), what the BTC bundle writes without OP_RETURN. */
        const val SEQUENCE_RBF: Long = 0xfffffffdL

        /** Final sequence, what the BTC bundle writes when an OP_RETURN output is present. */
        const val SEQUENCE_FINAL: Long = 0xffffffffL

        /**
         * Parses [hex]. Returns `null` for anything that is not a complete transaction (trailing bytes are allowed
         * only for ZEC, whose shielded part follows the lock time).
         */
        fun decode(hex: String): RawUtxoTransaction? = try {
            parse(hexToBytes(hex.trim()))
        } catch (e: IllegalArgumentException) {
            null
        } catch (e: IndexOutOfBoundsException) {
            null
        }

        /** Double SHA-256 of [bytes], reversed and hex encoded (iOS `BTCTransaction(hex:)` / bitcore `tx.id`). */
        fun doubleSha256Reversed(bytes: ByteArray): String {
            val sha = MessageDigest.getInstance("SHA-256")
            val once = sha.digest(bytes)
            val twice = MessageDigest.getInstance("SHA-256").digest(once)
            return toHex(twice.reversedArray())
        }

        private fun parse(bytes: ByteArray): RawUtxoTransaction {
            val r = Reader(bytes)
            val header = r.u32()
            val overwintered = (header and 0x80000000L) != 0L
            val version = header and 0x7fffffffL
            val groupId = if (overwintered) r.u32() else 0L
            if (overwintered && version == 5L) return parseZcashV5(bytes)
            var witness = false
            if (!overwintered && r.peek() == 0 && r.peek(1) == 1) {
                r.skip(2)
                witness = true
            }
            val inputsStart = r.pos
            val inCount = r.varInt()
            require(inCount in 1..100_000) { "input count" }
            val inputs = ArrayList<Input>(inCount.toInt())
            val tmp = ArrayList<Triple<ByteArray, Long, Pair<ByteArray, Long>>>()
            repeat(inCount.toInt()) {
                val prev = r.bytes(32)
                val vout = r.u32()
                val script = r.bytes(r.varInt().toInt())
                val seq = r.u32()
                tmp += Triple(prev, vout, script to seq)
            }
            val outCount = r.varInt()
            require(outCount in 1..100_000) { "output count" }
            val outputs = ArrayList<Output>(outCount.toInt())
            repeat(outCount.toInt()) {
                val value = r.u64()
                val script = r.bytes(r.varInt().toInt())
                outputs += Output(value, script)
            }
            val outputsEnd = r.pos
            val witnesses = ArrayList<List<ByteArray>>()
            if (witness) {
                repeat(inCount.toInt()) {
                    val items = r.varInt().toInt()
                    witnesses += List(items) { r.bytes(r.varInt().toInt()) }
                }
            }
            val lockTimeStart = r.pos
            val lockTime = r.u32()
            if (!overwintered) require(r.remaining() == 0) { "trailing bytes" }
            tmp.forEachIndexed { i, (prev, vout, rest) ->
                inputs += Input(toHex(prev.reversedArray()), vout, rest.first, rest.second, witnesses.getOrElse(i) { emptyList() })
            }
            val txId = if (witness) {
                // BIP144 txid: version || inputs || outputs || locktime (no marker, flag or witnesses)
                val stripped = ByteArrayOutputStream()
                stripped.write(bytes, 0, 4)
                stripped.write(bytes, inputsStart, outputsEnd - inputsStart)
                stripped.write(bytes, lockTimeStart, 4)
                doubleSha256Reversed(stripped.toByteArray())
            } else {
                doubleSha256Reversed(bytes)
            }
            return RawUtxoTransaction(version, overwintered, groupId, inputs, outputs, lockTime, witness, txId)
        }

        /** ZEC v5 (transparent-only, [ZcashV5.parse]); txid per ZIP 244. */
        private fun parseZcashV5(bytes: ByteArray): RawUtxoTransaction {
            val tx = ZcashV5.parse(bytes) ?: throw IllegalArgumentException("zcash v5")
            require(tx.ins.size in 1..100_000) { "input count" }
            require(tx.outs.size in 1..100_000) { "output count" }
            return RawUtxoTransaction(
                version = 5L,
                overwintered = true,
                versionGroupId = ZcashV5.VERSION_GROUP_ID,
                inputs = tx.ins.map { Input(toHex(it.prevHash.reversedArray()), it.prevIndex, it.scriptSig, it.sequence, emptyList()) },
                outputs = tx.outs.map { Output(it.value, it.script) },
                lockTime = tx.lockTime,
                hasWitness = false,
                txId = ZcashV5.txid(tx),
                consensusBranchId = tx.branchId,
                expiryHeight = tx.expiryHeight,
            )
        }

        internal fun hexToBytes(hex: String): ByteArray {
            require(hex.length % 2 == 0 && hex.isNotEmpty()) { "hex length" }
            return ByteArray(hex.length / 2) { i ->
                val hi = Character.digit(hex[i * 2], 16)
                val lo = Character.digit(hex[i * 2 + 1], 16)
                require(hi >= 0 && lo >= 0) { "hex digit" }
                ((hi shl 4) or lo).toByte()
            }
        }

        internal fun toHex(bytes: ByteArray): String {
            val sb = StringBuilder(bytes.size * 2)
            for (b in bytes) {
                val v = b.toInt() and 0xff
                sb.append(HEX[v ushr 4]).append(HEX[v and 0x0f])
            }
            return sb.toString()
        }

        private const val HEX = "0123456789abcdef"
    }

    private class Reader(private val b: ByteArray) {
        var pos = 0
            private set

        fun peek(offset: Int = 0): Int = b[pos + offset].toInt() and 0xff
        fun skip(n: Int) {
            require(pos + n <= b.size) { "eof" }
            pos += n
        }
        fun remaining(): Int = b.size - pos
        fun u8(): Int = b[pos++].toInt() and 0xff
        fun u32(): Long {
            require(pos + 4 <= b.size) { "eof" }
            var v = 0L
            for (i in 0 until 4) v = v or ((b[pos + i].toLong() and 0xff) shl (8 * i))
            pos += 4
            return v
        }
        fun u64(): Long {
            require(pos + 8 <= b.size) { "eof" }
            var v = 0L
            for (i in 0 until 8) v = v or ((b[pos + i].toLong() and 0xff) shl (8 * i))
            pos += 8
            return v
        }
        fun varInt(): Long = when (val first = u8()) {
            0xfd -> (u8().toLong() or (u8().toLong() shl 8))
            0xfe -> u32()
            0xff -> u64()
            else -> first.toLong()
        }
        fun bytes(n: Int): ByteArray {
            require(n >= 0 && pos + n <= b.size) { "eof" }
            val out = b.copyOfRange(pos, pos + n)
            pos += n
            return out
        }
    }
}
