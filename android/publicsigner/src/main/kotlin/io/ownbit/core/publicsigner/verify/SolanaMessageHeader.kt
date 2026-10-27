// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.publicsigner.verify

import io.ownbit.core.crypto.util.Hex

/**
 * A Solana transaction message (legacy or v0) read by Kotlin, independently of the engine. Same
 * structural rules as the engine (`solana.js` `parseSolana`):
 * header sane (`0 < required ≤ keys ≤ 256`, `readonlySigned < required`, `readonlyUnsigned ≤ keys − required`),
 * unique static keys, 1–64 instructions whose program and account indexes resolve and whose program is not a required
 * signer, **no address lookup tables** in v0 ([LookupTables]), strict compact lengths, no trailing bytes, at most
 * [MAX_BYTES] bytes.
 *
 * @property requiredSignatures the first `requiredSignatures` keys sign; the fee payer is key 0.
 * @property usesDurableNonce the first instruction is the System program's `AdvanceNonceAccount` (the transaction
 *   does not expire: warning + acknowledgement).
 */
class SolanaMessageHeader private constructor(
    val version: Version,
    val requiredSignatures: Int,
    val readonlySigned: Int,
    val readonlyUnsigned: Int,
    private val keys: List<ByteArray>,
    val instructions: List<Instruction>,
) {
    enum class Version { LEGACY, V0 }

    class Instruction(val programIndex: Int, val accounts: IntArray, val data: ByteArray)

    /** Thrown for a v0 message that uses address lookup tables (`err.lookupTable`, engine `LOOKUP_TABLE`). */
    class LookupTables : RuntimeException("Solana address lookup tables are refused offline")

    val keyCount: Int get() = keys.size

    /** The static account key [index] as lower-case hex (32 bytes). */
    fun keyHex(index: Int): String = Hex.encode(keys[index])

    /** The required-signer slot of [publicKeyHex] (32-byte hex), or `null` when it is not a required signer. */
    fun signerSlot(publicKeyHex: String): Int? =
        (0 until requiredSignatures).firstOrNull { keyHex(it).equals(publicKeyHex, ignoreCase = true) }

    /** Distinct program ids (hex) in instruction order. */
    val programIds: List<String> get() = instructions.map { keyHex(it.programIndex) }.distinct()

    val usesDurableNonce: Boolean
        get() {
            val first = instructions.firstOrNull() ?: return false
            if (!keys[first.programIndex].all { it.toInt() == 0 }) return false // System program = 32 zero bytes
            val d = first.data
            return d.size == 4 && d[0].toInt() == ADVANCE_NONCE_ACCOUNT && d[1].toInt() == 0 && d[2].toInt() == 0 && d[3].toInt() == 0
        }

    override fun toString(): String = "SolanaMessageHeader($version, required=$requiredSignatures, keys=${keys.size}, ix=${instructions.size})"

    companion object {
        /** Network packet limit for a serialized transaction (engine `solana.js`). */
        const val MAX_BYTES: Int = 1_232

        private const val MAX_KEYS = 256
        private const val MAX_INSTRUCTIONS = 64
        private const val ADVANCE_NONCE_ACCOUNT = 4

        /** Parses [bytes]; fails with [PublicVerifyException] (structure) or [LookupTables]. */
        fun parse(bytes: ByteArray): SolanaMessageHeader {
            verifyCheck(bytes.isNotEmpty() && bytes.size <= MAX_BYTES) { "solana.size" }
            val r = Reader(bytes)
            var version = Version.LEGACY
            var required = r.u8()
            if (required and 0x80 != 0) {
                verifyCheck(required == 0x80) { "solana.version" }
                version = Version.V0
                required = r.u8()
            }
            val readonlySigned = r.u8()
            val readonlyUnsigned = r.u8()
            val keyCount = r.short()
            verifyCheck(
                required in 1..keyCount && readonlySigned < required && readonlyUnsigned <= keyCount - required && keyCount <= MAX_KEYS,
            ) { "solana.header" }
            val keys = List(keyCount) { r.take(32) }
            verifyCheck(keys.map { Hex.encode(it) }.toSet().size == keys.size) { "solana.duplicateKeys" }
            r.take(32) // recent blockhash or durable nonce
            val count = r.short()
            verifyCheck(count in 1..MAX_INSTRUCTIONS) { "solana.instructions" }
            val instructions = List(count) {
                val program = r.u8()
                val accounts = r.take(r.short()).map { it.toInt() and 0xFF }.toIntArray()
                val data = r.take(r.short())
                verifyCheck(program < keyCount && accounts.all { it < keyCount }) { "solana.unresolvedAccount" }
                verifyCheck(program >= required) { "solana.programSigner" }
                Instruction(program, accounts, data)
            }
            if (version == Version.V0 && r.short() != 0) throw LookupTables()
            verifyCheck(r.pos == bytes.size) { "solana.trailing" }
            return SolanaMessageHeader(version, required, readonlySigned, readonlyUnsigned, keys, instructions)
        }

        /**
         * The off-chain message rule (engine `parseSolana` kind `message`): 1–1024 bytes, first byte ≥ 0x20 and
         * not 0x80 (no transaction-header reinterpretation), strict UTF-8 without control characters (tab, LF and CR
         * allowed).
         */
        fun isValidOffchainMessage(bytes: ByteArray): Boolean {
            if (bytes.isEmpty() || bytes.size > 1024) return false
            val first = bytes[0].toInt() and 0xFF
            if (first < 0x20 || first == 0x80) return false
            val decoder = Charsets.UTF_8.newDecoder()
                .onMalformedInput(java.nio.charset.CodingErrorAction.REPORT)
                .onUnmappableCharacter(java.nio.charset.CodingErrorAction.REPORT)
            val text = try {
                decoder.decode(java.nio.ByteBuffer.wrap(bytes)).toString()
            } catch (e: java.nio.charset.CharacterCodingException) {
                return false
            }
            return text.none { c -> (c.code in 0x00..0x08) || c.code == 0x0B || c.code == 0x0C || (c.code in 0x0E..0x1F) || c.code == 0x7F }
        }
    }

    private class Reader(val bytes: ByteArray) {
        var pos = 0

        fun take(n: Int): ByteArray {
            verifyCheck(n >= 0 && pos + n <= bytes.size) { "solana.truncated" }
            return bytes.copyOfRange(pos, pos + n).also { pos += n }
        }

        fun u8(): Int = take(1)[0].toInt() and 0xFF

        /** Solana compact-u16 (shortvec), canonical only (engine `Reader.short`). */
        fun short(): Int {
            var n = 0
            var shift = 0
            for (i in 0 until 3) {
                val b = u8()
                verifyCheck(i < 2 || b < 4) { "solana.compactLength" }
                n = n or ((b and 0x7F) shl shift)
                if (b and 0x80 == 0) {
                    verifyCheck(i == 0 || b != 0) { "solana.compactLength" }
                    return n
                }
                shift += 7
            }
            throw PublicVerifyException("solana.compactLength")
        }
    }
}
