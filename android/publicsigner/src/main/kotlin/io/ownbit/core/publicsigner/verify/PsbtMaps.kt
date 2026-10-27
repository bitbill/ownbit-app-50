// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.publicsigner.verify

import io.ownbit.core.crypto.hash.Hashes
import io.ownbit.core.crypto.util.Hex
import org.bouncycastle.crypto.ec.CustomNamedCurves
import java.math.BigInteger

/**
 * The key-value maps of a PSBT (BIP-174 v0 / BIP-370 v2), read by Kotlin independently of the engine that signs it.
 * Only structure is read — scripts and signatures are the engine's.
 *
 * - [parse]: magic, global / input / output maps (canonical compact sizes, no duplicate keys, nothing after the last
 *   map), ≤ [MAX_BYTES] bytes, 1…[MAX_IN_OUT] inputs and outputs; v0 needs exactly the global unsigned transaction
 *   (legacy serialization, empty script sigs), v2 the BIP-370 fields.
 * - [unsignedTx]: the bytes the engine's `signingBytesDigest` hashes (`sha256(tx.unsignedTx)` of `@scure/btc-signer`):
 *   v0 the global transaction as given, v2 the transaction rebuilt from the per-input / per-output fields with the
 *   BIP-370 lock-time rule.
 * - [outputDerivations]: the BIP-32 / Taproot BIP-32 derivations of the outputs (the change-index bound).
 * - [diff]: what signing may change — signatures added for the task keys on the task inputs, nothing else.
 */
class PsbtMaps private constructor(
    val version: Int,
    val global: List<Entry>,
    val inputs: List<List<Entry>>,
    val outputs: List<List<Entry>>,
    val unsignedTx: ByteArray,
) {
    /** One key-value pair; [type] is the key type (the key's leading compact size). */
    class Entry(val key: ByteArray, val value: ByteArray) {
        val type: Long = readCompact(key, 0).first

        internal val keyHex: String get() = Hex.encode(key)
        internal val valueHex: String get() = Hex.encode(value)

        override fun toString(): String = "Entry(type=$type)"
    }

    /** One output derivation: [publicKey] hex (33-byte compressed, or 32-byte x-only for Taproot), [fingerprint] 8 hex. */
    data class OutputDerivation(
        val outputIndex: Int,
        val publicKey: String,
        val fingerprint: String,
        val path: List<Long>,
        val taproot: Boolean,
    ) {
        /** `m/84'/0'/0'/1/5`. */
        val pathText: String get() = "m" + path.joinToString("") { "/" + (it and 0x7FFF_FFFF) + if (it >= HARDENED) "'" else "" }
    }

    /** `sha256(unsignedTx)` in lower-case hex: the engine's `signingBytesDigest` for this PSBT. */
    val unsignedTxDigest: String get() = Hashes.sha256Hex(unsignedTx)

    /**
     * Every BIP-32 (`0x02`) and Taproot BIP-32 (`0x07`) derivation of the outputs, in output order — every entry the
     * engine's PSBT library (`@scure/btc-signer`) parses, whatever its number of leaf hashes (the engine takes either
     * kind as a change candidate on any output). Skipped: a `0x02` key that is not a 33-byte compressed key (the
     * engine compares compressed keys only, so it can never prove such an output), and entries the library refuses
     * anyway (the whole PSBT is then refused before review). The change-index bound also reads the engine's own proof
     * ([io.ownbit.core.publicsigner.sign.PublicSignPolicy]), so a skipped entry can never hide an output.
     */
    fun outputDerivations(): List<OutputDerivation> = outputs.flatMapIndexed { index, map ->
        map.mapNotNull { e ->
            when (e.type) {
                OUT_BIP32 -> {
                    if (e.key.size != 34 || e.value.size < 4 || (e.value.size - 4) % 4 != 0) return@mapNotNull null
                    OutputDerivation(index, Hex.encode(e.key, 1, 33), Hex.encode(e.value, 0, 4), u32Path(e.value, 4), taproot = false)
                }
                OUT_TAP_BIP32 -> {
                    if (e.key.size != 33 || e.value.isEmpty()) return@mapNotNull null
                    val (hashes, at) = readCompact(e.value, 0)
                    val start = at + 32 * hashes
                    if (start + 4 > e.value.size || (e.value.size - start - 4) % 4 != 0L) return@mapNotNull null
                    OutputDerivation(index, Hex.encode(e.key, 1, 32), Hex.encode(e.value, start.toInt(), 4), u32Path(e.value, start.toInt() + 4), taproot = true)
                }
                else -> null
            }
        }
    }

    /** The internal key (`PSBT_IN_TAP_INTERNAL_KEY`, x-only hex) of input [index], if any. */
    fun tapInternalKey(index: Int): String? =
        inputs.getOrNull(index)?.firstOrNull { it.type == IN_TAP_INTERNAL_KEY && it.key.size == 1 }?.valueHex

    /**
     * The script input [index] spends, read like `@scure/btc-signer` `getPrevOut` (what the engine signs against): the
     * output of `PSBT_IN_NON_WITNESS_UTXO` named by the input's outpoint when present, else `PSBT_IN_WITNESS_UTXO`;
     * `null` when neither can be read.
     */
    fun prevoutScript(index: Int): ByteArray? {
        val map = inputs.getOrNull(index) ?: return null
        return try {
            val full = map.firstOrNull { it.type == IN_NON_WITNESS_UTXO && it.key.size == 1 }
            if (full != null) {
                txOutputScript(full.value, outpointIndex(index) ?: return null)
            } else {
                val utxo = map.firstOrNull { it.type == IN_WITNESS_UTXO && it.key.size == 1 }?.value ?: return null
                val (length, at) = readCompact(utxo, 8)
                if (at + length != utxo.size.toLong()) null else utxo.copyOfRange(at.toInt(), utxo.size)
            }
        } catch (e: PublicVerifyException) {
            null
        }
    }

    /** One previous output an input spends: the txid bytes **as stored** (internal order) and the output index. */
    class Outpoint(val txid: ByteArray, val vout: Long) {
        override fun equals(other: Any?): Boolean = other is Outpoint && vout == other.vout && txid.contentEquals(other.txid)
        override fun hashCode(): Int = 31 * txid.contentHashCode() + vout.hashCode()
        override fun toString(): String = "Outpoint(vout=$vout)"
    }

    /**
     * Where an input's amount comes from: its full previous transaction, or only `witnessUtxo` — then what the
     * output it spends is: SegWit v0 (P2WPKH, P2WSH, or P2SH wrapping a v0 witness program named by
     * `PSBT_IN_REDEEM_SCRIPT`), Taproot, or anything else (legacy P2PKH / bare P2SH: their signatures commit to no
     * amount, so they always need the previous transaction).
     */
    enum class PrevoutKind { FULL_PREVIOUS_TX, WITNESS_SEGWIT_V0, WITNESS_TAPROOT, WITNESS_LEGACY, NONE }

    /** Input [index]'s outpoint (v0: the global transaction's input; v2: `PSBT_IN_PREVIOUS_TXID` / `OUTPUT_INDEX`). */
    fun outpoint(index: Int): Outpoint? {
        if (index !in inputs.indices) return null
        return try {
            if (version == 2) {
                val m = inputs[index]
                val txid = m.firstOrNull { it.type == IN_PREVIOUS_TXID && it.key.size == 1 && it.value.size == 32 }?.value ?: return null
                Outpoint(txid.copyOf(), outpointIndex(index) ?: return null)
            } else {
                val (_, start) = readCompact(unsignedTx, 4)
                val at = start.toInt() + 41 * index
                Outpoint(unsignedTx.copyOfRange(at, at + 32), u32(unsignedTx, at + 32))
            }
        } catch (e: PublicVerifyException) {
            null
        }
    }

    /**
     * The amount (sats) input [index] claims to spend, read like `@scure/btc-signer` `getPrevOut` (the engine's fee):
     * the output of `PSBT_IN_NON_WITNESS_UTXO` named by the outpoint when present, else `PSBT_IN_WITNESS_UTXO`; `null`
     * when neither can be read.
     */
    fun claimedAmount(index: Int): Long? {
        val map = inputs.getOrNull(index) ?: return null
        return try {
            val full = map.firstOrNull { it.type == IN_NON_WITNESS_UTXO && it.key.size == 1 }
            val amount = if (full != null) {
                txOutput(full.value, outpointIndex(index) ?: return null)?.first
            } else {
                val utxo = map.firstOrNull { it.type == IN_WITNESS_UTXO && it.key.size == 1 }?.value ?: return null
                if (utxo.size < 9) null else u64(utxo, 0)
            }
            amount?.takeIf { it in 0..MAX_SATS }
        } catch (e: PublicVerifyException) {
            null
        }
    }

    /** `true` when input [index] carries its full previous transaction (`PSBT_IN_NON_WITNESS_UTXO`). */
    fun hasFullPrevTx(index: Int): Boolean = inputs.getOrNull(index)?.any { it.type == IN_NON_WITNESS_UTXO && it.key.size == 1 } == true

    /** [PrevoutKind] of input [index]. */
    fun prevoutKind(index: Int): PrevoutKind {
        val map = inputs.getOrNull(index) ?: return PrevoutKind.NONE
        if (hasFullPrevTx(index)) return PrevoutKind.FULL_PREVIOUS_TX
        if (map.none { it.type == IN_WITNESS_UTXO && it.key.size == 1 }) return PrevoutKind.NONE
        val script = prevoutScript(index) ?: return PrevoutKind.NONE
        return when {
            isWitnessV0Program(script) -> PrevoutKind.WITNESS_SEGWIT_V0
            script.size == 34 && script[0] == 0x51.toByte() && script[1] == 0x20.toByte() -> PrevoutKind.WITNESS_TAPROOT
            isP2sh(script) -> {
                val redeem = map.firstOrNull { it.type == IN_REDEEM_SCRIPT && it.key.size == 1 }?.value
                if (redeem != null && isWitnessV0Program(redeem) && hash160(redeem).contentEquals(script.copyOfRange(2, 22))) {
                    PrevoutKind.WITNESS_SEGWIT_V0
                } else {
                    PrevoutKind.WITNESS_LEGACY
                }
            }
            else -> PrevoutKind.WITNESS_LEGACY
        }
    }

    /** The output index of input [index]'s outpoint (v0: the global transaction; v2: `PSBT_IN_OUTPUT_INDEX`). */
    private fun outpointIndex(index: Int): Long? {
        if (version == 2) return inputs[index].firstOrNull { it.type == IN_OUTPUT_INDEX && it.key.size == 1 && it.value.size == 4 }?.let { u32(it.value, 0) }
        // v0: inputs of 41 bytes each after the count (txid, index, empty script sig, sequence; checked by parse).
        val (_, start) = readCompact(unsignedTx, 4)
        return u32(unsignedTx, start.toInt() + 41 * index + 32)
    }

    /**
     * BIP-341 key-path spend of [index] by the x-only key [xOnly] (hex): the input names it as its internal key, or the
     * script it spends is the key's BIP-86 output `OP_1 <Q>` (also without an internal key) — the engine's `keyPath`
     * rule (`bitcoin.js` `signBitcoin`).
     */
    internal fun keyPathOf(index: Int, xOnly: String): Boolean {
        if (tapInternalKey(index)?.equals(xOnly, ignoreCase = true) == true) return true
        val key = Hex.decodeOrNull(xOnly)?.takeIf { it.size == 32 } ?: return false
        val script = prevoutScript(index) ?: return false
        return taprootOutputScript(key)?.contentEquals(script) == true
    }

    override fun toString(): String = "PsbtMaps(v$version, ${inputs.size} in, ${outputs.size} out)"

    /** Outcome of [diff]: `null` [problem] = only allowed signatures were added (at least one). */
    data class Diff(val addedSignatures: Int, val problem: String?) {
        val ok: Boolean get() = problem == null && addedSignatures > 0
    }

    companion object {
        /** Largest PSBT (engine `QR_LIMITS.payloadBytes`). */
        const val MAX_BYTES: Int = 131_072

        /** Inputs and outputs (engine `bitcoin.js`). */
        const val MAX_IN_OUT: Int = 100

        internal const val HARDENED: Long = 0x8000_0000L

        // BIP-174 / BIP-370 key types.
        private const val GLOBAL_UNSIGNED_TX = 0x00L
        private const val GLOBAL_TX_VERSION = 0x02L
        private const val GLOBAL_FALLBACK_LOCKTIME = 0x03L
        private const val GLOBAL_INPUT_COUNT = 0x04L
        private const val GLOBAL_OUTPUT_COUNT = 0x05L
        private const val GLOBAL_TX_MODIFIABLE = 0x06L
        private const val GLOBAL_VERSION = 0xFBL
        private const val IN_NON_WITNESS_UTXO = 0x00L
        private const val IN_WITNESS_UTXO = 0x01L
        private const val IN_REDEEM_SCRIPT = 0x04L
        internal const val IN_PARTIAL_SIG = 0x02L
        internal const val IN_TAP_KEY_SIG = 0x13L
        internal const val IN_TAP_SCRIPT_SIG = 0x14L
        private const val IN_PREVIOUS_TXID = 0x0EL
        private const val IN_OUTPUT_INDEX = 0x0FL
        private const val IN_SEQUENCE = 0x10L
        private const val IN_REQUIRED_TIME_LOCKTIME = 0x11L
        private const val IN_REQUIRED_HEIGHT_LOCKTIME = 0x12L
        private const val IN_TAP_INTERNAL_KEY = 0x17L
        private const val OUT_BIP32 = 0x02L
        private const val OUT_AMOUNT = 0x03L
        private const val OUT_SCRIPT = 0x04L
        private const val OUT_TAP_BIP32 = 0x07L

        private const val LOCKTIME_THRESHOLD = 500_000_000L
        private val MAGIC = byteArrayOf(0x70, 0x73, 0x62, 0x74, 0xff.toByte())

        /** Parses [bytes]; fails with [PublicVerifyException] naming the broken part. */
        fun parse(bytes: ByteArray): PsbtMaps {
            verifyCheck(bytes.size in 6..MAX_BYTES) { "psbt.size" }
            verifyCheck(bytes.copyOfRange(0, 5).contentEquals(MAGIC)) { "psbt.magic" }
            val reader = MapReader(bytes, 5)
            val global = reader.map()
            val g = global.associateBy { it.type }
            val version = g[GLOBAL_VERSION]?.let { u32Value(it, "psbt.version") } ?: 0L
            val inputCount: Int
            val outputCount: Int
            val tx: ByteArray?
            when (version) {
                0L -> {
                    val unsigned = global.singleOrNull { it.type == GLOBAL_UNSIGNED_TX }
                    verifyCheck(unsigned != null && unsigned.key.size == 1) { "psbt.unsignedTx" }
                    verifyCheck(listOf(GLOBAL_TX_VERSION, GLOBAL_FALLBACK_LOCKTIME, GLOBAL_INPUT_COUNT, GLOBAL_OUTPUT_COUNT, GLOBAL_TX_MODIFIABLE).none { it in g }) {
                        "psbt.v0.fields"
                    }
                    val counts = txCounts(unsigned!!.value)
                    inputCount = counts.first
                    outputCount = counts.second
                    tx = unsigned.value
                }
                2L -> {
                    verifyCheck(GLOBAL_UNSIGNED_TX !in g) { "psbt.v2.unsignedTx" }
                    inputCount = compactValue(g[GLOBAL_INPUT_COUNT] ?: throw PublicVerifyException("psbt.v2.inputCount"))
                    outputCount = compactValue(g[GLOBAL_OUTPUT_COUNT] ?: throw PublicVerifyException("psbt.v2.outputCount"))
                    tx = null
                }
                else -> throw PublicVerifyException("psbt.version")
            }
            verifyCheck(inputCount in 1..MAX_IN_OUT && outputCount in 1..MAX_IN_OUT) { "psbt.counts" }
            val inputs = List(inputCount) { reader.map() }
            val outputs = List(outputCount) { reader.map() }
            verifyCheck(reader.pos == bytes.size) { "psbt.trailing" }
            val unsignedTx = tx ?: rebuildV2(g, inputs, outputs)
            return PsbtMaps(version.toInt(), global, inputs, outputs, unsignedTx)
        }

        /**
         * Compares a signed PSBT ([response]) with the one the user reviewed ([request]): the global map and every output
         * map must be identical as key → value sets; every input map must keep every entry and may only gain
         * signatures of the task keys on the task inputs — `PARTIAL_SIG` (`0x02 ‖ pubkey`), `TAP_KEY_SIG` (a key-path
         * spend by a task key: [keyPathOf]) or `TAP_SCRIPT_SIG` (`0x14 ‖ x-only ‖ leaf`). [signers]: input index →
         * the task public keys allowed to sign it (33-byte compressed hex; Taproot compares their x-only part).
         */
        fun diff(request: PsbtMaps, response: PsbtMaps, signers: Map<Int, Set<String>>): Diff {
            if (request.version != response.version) return Diff(0, "version")
            if (!sameSet(request.global, response.global)) return Diff(0, "global map")
            if (request.outputs.size != response.outputs.size) return Diff(0, "output count")
            request.outputs.zip(response.outputs).forEachIndexed { i, (a, b) -> if (!sameSet(a, b)) return Diff(0, "output $i map") }
            if (request.inputs.size != response.inputs.size) return Diff(0, "input count")
            var added = 0
            for (i in request.inputs.indices) {
                val before = request.inputs[i].associate { it.keyHex to it.valueHex }
                val after = response.inputs[i].associate { it.keyHex to it.valueHex }
                if (after.size != response.inputs[i].size) return Diff(0, "input $i duplicate key")
                for ((k, v) in before) if (after[k] != v) return Diff(0, "input $i entry removed or changed")
                val allowed = signers[i].orEmpty().map { it.lowercase() }.toSet()
                val allowedX = allowed.mapNotNull { if (it.length == 66) it.substring(2) else if (it.length == 64) it else null }.toSet()
                for (entry in response.inputs[i]) {
                    if (entry.keyHex in before) continue
                    val ok = when (entry.type) {
                        IN_PARTIAL_SIG -> entry.key.size == 34 && Hex.encode(entry.key, 1, 33) in allowed
                        IN_TAP_KEY_SIG -> entry.key.size == 1 && allowedX.any { request.keyPathOf(i, it) }
                        IN_TAP_SCRIPT_SIG -> entry.key.size == 65 && Hex.encode(entry.key, 1, 32) in allowedX
                        else -> false
                    }
                    if (!ok) return Diff(added, "input $i unexpected entry ${entry.type}")
                    added++
                }
            }
            return Diff(added, if (added == 0) "no signature added" else null)
        }

        /**
         * The BIP-86 output script `OP_1 <Q>` of the x-only key [xOnly]: `Q = lift_x(P) + int(hashTapTweak(P))·G`
         * (BIP-341, empty script tree); `null` for a key that is not on the curve.
         */
        internal fun taprootOutputScript(xOnly: ByteArray): ByteArray? {
            if (xOnly.size != 32) return null
            val p = try {
                SECP256K1.curve.decodePoint(byteArrayOf(0x02) + xOnly)
            } catch (e: IllegalArgumentException) {
                return null
            }
            val tag = Hashes.sha256("TapTweak".toByteArray(Charsets.US_ASCII))
            val t = BigInteger(1, Hashes.sha256(tag + tag + xOnly))
            if (t >= SECP256K1.n) return null
            val q = p.add(SECP256K1.g.multiply(t)).normalize()
            if (q.isInfinity) return null
            return byteArrayOf(0x51, 0x20) + q.affineXCoord.encoded
        }

        /** The script of output [vout] of the serialized transaction [tx] (legacy or segwit serialization). */
        private fun txOutputScript(tx: ByteArray, vout: Long): ByteArray? = txOutput(tx, vout)?.second

        /** `OP_0 <20 or 32 bytes>`: a SegWit v0 witness program (P2WPKH / P2WSH). */
        private fun isWitnessV0Program(script: ByteArray): Boolean =
            (script.size == 22 && script[0] == 0.toByte() && script[1] == 0x14.toByte()) ||
                (script.size == 34 && script[0] == 0.toByte() && script[1] == 0x20.toByte())

        /** RIPEMD-160(SHA-256(data)). */
        private fun hash160(data: ByteArray): ByteArray {
            val ripemd = org.bouncycastle.crypto.digests.RIPEMD160Digest()
            val sha = Hashes.sha256(data)
            ripemd.update(sha, 0, sha.size)
            return ByteArray(ripemd.digestSize).also { ripemd.doFinal(it, 0) }
        }

        /** `OP_HASH160 <20> OP_EQUAL`. */
        private fun isP2sh(script: ByteArray): Boolean =
            script.size == 23 && script[0] == 0xa9.toByte() && script[1] == 0x14.toByte() && script[22] == 0x87.toByte()

        /** Largest amount (21 million BTC in sats). */
        private const val MAX_SATS: Long = 2_100_000_000_000_000L

        /** (amount, script) of output [vout] of the serialized transaction [tx] (legacy or segwit serialization). */
        private fun txOutput(tx: ByteArray, vout: Long): Pair<Long, ByteArray>? {
            var at = 4
            verifyCheck(tx.size > at + 2) { "prevTx.size" }
            if (tx[at].toInt() == 0 && tx[at + 1].toInt() == 1) at += 2 // segwit marker + flag
            val (nIn, afterIn) = readCompact(tx, at)
            at = afterIn.toInt()
            repeat(nIn.toInt()) {
                verifyCheck(at + 36 <= tx.size) { "prevTx.truncated" }
                val (scriptLength, afterScript) = readCompact(tx, at + 36)
                at = (afterScript + scriptLength + 4).toInt()
                verifyCheck(at <= tx.size) { "prevTx.truncated" }
            }
            val (nOut, afterOut) = readCompact(tx, at)
            at = afterOut.toInt()
            if (vout !in 0 until nOut) return null
            for (i in 0 until nOut) {
                verifyCheck(at + 8 <= tx.size) { "prevTx.truncated" }
                val (scriptLength, afterScript) = readCompact(tx, at + 8)
                val end = afterScript + scriptLength
                verifyCheck(end <= tx.size) { "prevTx.truncated" }
                if (i == vout) return u64(tx, at) to tx.copyOfRange(afterScript.toInt(), end.toInt())
                at = end.toInt()
            }
            return null
        }

        private val SECP256K1 = CustomNamedCurves.getByName("secp256k1")

        private fun sameSet(a: List<Entry>, b: List<Entry>): Boolean =
            a.size == b.size && a.map { it.keyHex to it.valueHex }.toSet() == b.map { it.keyHex to it.valueHex }.toSet()

        // ---- readers --------------------------------------------------------------------------------------------

        private class MapReader(val bytes: ByteArray, var pos: Int) {
            fun map(): List<Entry> {
                val entries = ArrayList<Entry>()
                val keys = HashSet<String>()
                while (true) {
                    val (keyLength, afterKeyLength) = readCompact(bytes, pos)
                    pos = afterKeyLength.toInt()
                    if (keyLength == 0L) return entries
                    val key = take(keyLength)
                    val (valueLength, afterValueLength) = readCompact(bytes, pos)
                    pos = afterValueLength.toInt()
                    val value = take(valueLength)
                    verifyCheck(keys.add(Hex.encode(key))) { "psbt.duplicateKey" }
                    entries += Entry(key, value)
                }
            }

            private fun take(n: Long): ByteArray {
                verifyCheck(n >= 0 && pos + n <= bytes.size) { "psbt.truncated" }
                return bytes.copyOfRange(pos, pos + n.toInt()).also { pos += n.toInt() }
            }
        }

        /** A canonical Bitcoin compact size at [at]: (value, next position). */
        internal fun readCompact(bytes: ByteArray, at: Int): Pair<Long, Long> {
            verifyCheck(at < bytes.size) { "compactSize.truncated" }
            val first = bytes[at].toInt() and 0xFF
            val width = when (first) {
                0xFD -> 2
                0xFE -> 4
                0xFF -> 8
                else -> return first.toLong() to (at + 1).toLong()
            }
            verifyCheck(at + 1 + width <= bytes.size) { "compactSize.truncated" }
            var value = 0L
            for (i in width - 1 downTo 0) value = (value shl 8) or (bytes[at + 1 + i].toLong() and 0xFF)
            val minimum = when (width) {
                2 -> 0xFDL
                4 -> 0x1_0000L
                else -> 0x1_0000_0000L
            }
            verifyCheck(value >= minimum && value <= MAX_BYTES) { "compactSize.nonCanonical" }
            return value to (at + 1 + width).toLong()
        }

        private fun compactValue(e: Entry): Int {
            val (value, end) = readCompact(e.value, 0)
            verifyCheck(end == e.value.size.toLong() && e.key.size == 1) { "psbt.compactValue" }
            return value.toInt()
        }

        private fun u32Value(e: Entry, what: String): Long {
            verifyCheck(e.key.size == 1 && e.value.size == 4) { what }
            return u32(e.value, 0)
        }

        private fun u32(b: ByteArray, at: Int): Long =
            (b[at].toLong() and 0xFF) or ((b[at + 1].toLong() and 0xFF) shl 8) or
                ((b[at + 2].toLong() and 0xFF) shl 16) or ((b[at + 3].toLong() and 0xFF) shl 24)

        private fun u32Path(b: ByteArray, from: Int): List<Long> = (from until b.size step 4).map { u32(b, it) }

        /** Little-endian u64 at [at] (an amount; values above `Long.MAX_VALUE` read negative and are refused by callers). */
        private fun u64(b: ByteArray, at: Int): Long {
            verifyCheck(at + 8 <= b.size) { "u64.truncated" }
            var v = 0L
            for (i in 7 downTo 0) v = (v shl 8) or (b[at + i].toLong() and 0xFF)
            return v
        }

        /** (inputs, outputs) of a v0 global transaction: legacy serialization, empty script sigs, no trailing bytes. */
        private fun txCounts(tx: ByteArray): Pair<Int, Int> {
            verifyCheck(tx.size >= 10) { "psbt.tx.size" }
            var at = 4
            verifyCheck(tx[at].toInt() != 0) { "psbt.tx.witness" } // a segwit marker: the unsigned tx has no witness
            val (nIn, afterIn) = readCompact(tx, at)
            at = afterIn.toInt()
            verifyCheck(nIn in 1..MAX_IN_OUT.toLong()) { "psbt.tx.inputs" }
            repeat(nIn.toInt()) {
                verifyCheck(at + 36 <= tx.size) { "psbt.tx.truncated" }
                at += 36
                val (scriptLength, afterScript) = readCompact(tx, at)
                verifyCheck(scriptLength == 0L) { "psbt.tx.scriptSig" }
                at = afterScript.toInt() + 4
            }
            val (nOut, afterOut) = readCompact(tx, at)
            at = afterOut.toInt()
            verifyCheck(nOut in 1..MAX_IN_OUT.toLong()) { "psbt.tx.outputs" }
            repeat(nOut.toInt()) {
                verifyCheck(at + 8 <= tx.size) { "psbt.tx.truncated" }
                at += 8
                val (scriptLength, afterScript) = readCompact(tx, at)
                at = (afterScript + scriptLength).toInt()
                verifyCheck(at <= tx.size) { "psbt.tx.truncated" }
            }
            verifyCheck(at + 4 == tx.size) { "psbt.tx.trailing" }
            return nIn.toInt() to nOut.toInt()
        }

        /**
         * The unsigned transaction of a v2 PSBT, serialized like `@scure/btc-signer` `unsignedTx`: version, inputs
         * (previous txid as stored, output index, empty script sig, sequence or `0xffffffff`), outputs (amount, script),
         * BIP-370 lock time (the largest required height lock when every constrained input allows heights, else the
         * largest time lock; the fallback when no input is constrained).
         */
        private fun rebuildV2(g: Map<Long, Entry>, inputs: List<List<Entry>>, outputs: List<List<Entry>>): ByteArray {
            val out = java.io.ByteArrayOutputStream()
            val version = g[GLOBAL_TX_VERSION]?.let { u32Value(it, "psbt.v2.txVersion") } ?: throw PublicVerifyException("psbt.v2.txVersion")
            writeU32(out, version)
            writeCompact(out, inputs.size.toLong())
            var height = 0L
            var time = 0L
            var constrained = false
            var heightOk = true
            var timeOk = true
            for (map in inputs) {
                val m = map.associateBy { it.type }
                val txid = m[IN_PREVIOUS_TXID]?.takeIf { it.key.size == 1 && it.value.size == 32 }
                    ?: throw PublicVerifyException("psbt.v2.previousTxid")
                val index = m[IN_OUTPUT_INDEX]?.let { u32Value(it, "psbt.v2.outputIndex") } ?: throw PublicVerifyException("psbt.v2.outputIndex")
                val sequence = m[IN_SEQUENCE]?.let { u32Value(it, "psbt.v2.sequence") } ?: 0xFFFF_FFFFL
                val requiredTime = m[IN_REQUIRED_TIME_LOCKTIME]?.let { u32Value(it, "psbt.v2.timeLock") }
                val requiredHeight = m[IN_REQUIRED_HEIGHT_LOCKTIME]?.let { u32Value(it, "psbt.v2.heightLock") }
                if (requiredTime != null) verifyCheck(requiredTime >= LOCKTIME_THRESHOLD) { "psbt.v2.timeLock" }
                if (requiredHeight != null) verifyCheck(requiredHeight in 1 until LOCKTIME_THRESHOLD) { "psbt.v2.heightLock" }
                if (requiredTime != null || requiredHeight != null) {
                    constrained = true
                    if (requiredHeight != null) height = maxOf(height, requiredHeight) else heightOk = false
                    if (requiredTime != null) time = maxOf(time, requiredTime) else timeOk = false
                }
                out.write(txid.value)
                writeU32(out, index)
                out.write(0)
                writeU32(out, sequence)
            }
            writeCompact(out, outputs.size.toLong())
            for (map in outputs) {
                val m = map.associateBy { it.type }
                val amount = m[OUT_AMOUNT]?.takeIf { it.key.size == 1 && it.value.size == 8 } ?: throw PublicVerifyException("psbt.v2.amount")
                val script = m[OUT_SCRIPT]?.takeIf { it.key.size == 1 } ?: throw PublicVerifyException("psbt.v2.script")
                out.write(amount.value)
                writeCompact(out, script.value.size.toLong())
                out.write(script.value)
            }
            val fallback = g[GLOBAL_FALLBACK_LOCKTIME]?.let { u32Value(it, "psbt.v2.fallbackLocktime") } ?: 0L
            val lockTime = when {
                !constrained -> fallback
                heightOk -> height
                timeOk -> time
                else -> throw PublicVerifyException("psbt.v2.locktime")
            }
            writeU32(out, lockTime)
            return out.toByteArray()
        }

        private fun writeU32(out: java.io.ByteArrayOutputStream, v: Long) {
            for (i in 0 until 4) out.write(((v shr (8 * i)) and 0xFF).toInt())
        }

        private fun writeCompact(out: java.io.ByteArrayOutputStream, v: Long) {
            when {
                v < 0xFD -> out.write(v.toInt())
                v <= 0xFFFF -> {
                    out.write(0xFD)
                    out.write((v and 0xFF).toInt())
                    out.write(((v shr 8) and 0xFF).toInt())
                }
                else -> {
                    out.write(0xFE)
                    writeU32(out, v)
                }
            }
        }
    }
}
