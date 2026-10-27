// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.chain.tron

/**
 * The outer `protocol.Transaction` protobuf of TRON, read and written **strictly** (the TronLink cold-wallet
 * format of the public protocol). A TronLink request carries each transaction as the hex of a full
 * `Transaction` (`0a <len> raw_data [12 41 <65-byte signature>]*`); the cold wallet answers with the same bytes plus one
 * appended signature.
 *
 * [split] accepts exactly: field 1 (`raw_data`, length-delimited) once and first, then only field 2 (`signature`,
 * length-delimited, 65 bytes each, at most [MAX_SIGNATURES]), canonical (minimal) length varints, nothing else and
 * nothing after. Anything else — an unknown field (`ret` = 5 …), a second field 1, a signature of another length, a
 * non-minimal length — is `null` (malformed), so what Ownbit signs (`sha256(raw_data)`) and what it answers can never
 * differ from what another parser reads. [split] re-encodes what it read and requires byte equality.
 *
 * Pure Kotlin, no signing, nothing logged.
 */
object TronTransactionProto {

    /** Largest `raw_data` (the engine's `hexToBytes(raw_data_hex, 65536)`). */
    const val MAX_RAW_BYTES: Int = 65_536

    /** Most signatures a transaction may already carry (TRON permission keys are at most 32 + 1). */
    const val MAX_SIGNATURES: Int = 32

    /** Length of one TRON signature: `r(32) ‖ s(32) ‖ recId(1)`. */
    const val SIGNATURE_BYTES: Int = 65

    private const val TAG_RAW: Int = 0x0a
    private const val TAG_SIGNATURE: Int = 0x12

    /** A `Transaction` split into its signed [raw] bytes and its existing [signatures] (each [SIGNATURE_BYTES]). */
    class Split(val raw: ByteArray, val signatures: List<ByteArray>) {
        override fun toString(): String = "TronTransactionProto.Split(raw=${raw.size} bytes, signatures=${signatures.size})"
    }

    /** [tx] split strictly (see the class documentation), or `null` when it is not exactly that shape. */
    fun split(tx: ByteArray): Split? {
        var pos = 0
        if (tx.isEmpty() || (tx[0].toInt() and 0xff) != TAG_RAW) return null
        pos++
        val (rawLength, afterRaw) = readLength(tx, pos) ?: return null
        if (rawLength < 1 || rawLength > MAX_RAW_BYTES || afterRaw + rawLength > tx.size) return null
        val raw = tx.copyOfRange(afterRaw, afterRaw + rawLength)
        pos = afterRaw + rawLength
        val signatures = ArrayList<ByteArray>()
        while (pos < tx.size) {
            if ((tx[pos].toInt() and 0xff) != TAG_SIGNATURE) return null
            val (length, after) = readLength(tx, pos + 1) ?: return null
            if (length != SIGNATURE_BYTES || after + length > tx.size) return null
            signatures += tx.copyOfRange(after, after + length)
            if (signatures.size > MAX_SIGNATURES) return null
            pos = after + length
        }
        val split = Split(raw, signatures)
        // Canonical only: what was read re-encodes to exactly the same bytes.
        return split.takeIf { encode(raw, signatures).contentEquals(tx) }
    }

    /** The `Transaction` bytes of [raw] and [signatures] (field 1, then one field 2 per signature). */
    fun encode(raw: ByteArray, signatures: List<ByteArray>): ByteArray {
        require(raw.isNotEmpty() && raw.size <= MAX_RAW_BYTES) { "raw_data size" }
        require(signatures.size <= MAX_SIGNATURES + 1 && signatures.all { it.size == SIGNATURE_BYTES }) { "signatures" }
        val out = java.io.ByteArrayOutputStream(raw.size + 8 + signatures.size * (SIGNATURE_BYTES + 2))
        out.write(TAG_RAW)
        writeLength(out, raw.size)
        out.write(raw)
        for (signature in signatures) {
            out.write(TAG_SIGNATURE)
            writeLength(out, signature.size)
            out.write(signature)
        }
        return out.toByteArray()
    }

    /**
     * [tx] (a well-formed `Transaction`, [split] not `null`) with [signature] appended as one more field 2: exactly
     * `tx ‖ 12 41 ‖ signature` (TronLink's `addSignature`).
     */
    fun appendSignature(tx: ByteArray, signature: ByteArray): ByteArray {
        val split = requireNotNull(split(tx)) { "not a strict TRON Transaction" }
        require(signature.size == SIGNATURE_BYTES) { "signature size" }
        return encode(split.raw, split.signatures + signature)
    }

    /** A minimal (canonical) protobuf length varint at [at]: (value, next position), `null` when absent or not minimal. */
    private fun readLength(bytes: ByteArray, at: Int): Pair<Int, Int>? {
        var value = 0L
        var shift = 0
        var pos = at
        while (true) {
            if (pos >= bytes.size || shift > 28) return null
            val b = bytes[pos++].toInt() and 0xff
            value = value or ((b and 0x7f).toLong() shl shift)
            if (b and 0x80 == 0) {
                // Minimal: no trailing zero group (a multi-byte varint never ends with 0x00).
                if (pos - at > 1 && b == 0) return null
                break
            }
            shift += 7
        }
        if (value > Int.MAX_VALUE) return null
        return value.toInt() to pos
    }

    private fun writeLength(out: java.io.ByteArrayOutputStream, length: Int) {
        var v = length
        while (v >= 0x80) {
            out.write((v and 0x7f) or 0x80)
            v = v ushr 7
        }
        out.write(v)
    }
}
