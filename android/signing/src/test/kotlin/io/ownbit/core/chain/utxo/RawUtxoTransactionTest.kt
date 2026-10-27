// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.chain.utxo

import org.junit.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Vectors generated independently with Python `hashlib` (double SHA-256, BIP144 stripped serialisation). */
class RawUtxoTransactionTest {

    private val legacy = "0100000002" +
        "aa".repeat(32) + "00000000" + "020102" + "ffffffff" +
        "cd" + "bb".repeat(31) + "07000000" + "00" + "fdffffff" +
        "02" + "60ea000000000000" + "1976a914" + "11".repeat(20) + "88ac" +
        "ca44000000000000" + "160014" + "22".repeat(20) +
        "00000000"

    private val segwit = "02000000" + "0001" + "02" +
        "aa".repeat(32) + "00000000" + "020102" + "ffffffff" +
        "cd" + "bb".repeat(31) + "07000000" + "00" + "fdffffff" +
        "02" + "60ea000000000000" + "1976a914" + "11".repeat(20) + "88ac" +
        "ca44000000000000" + "160014" + "22".repeat(20) +
        "02" + "03010203" + "0104" + "00" +
        "f4010000"

    private val zec = "04000080" + "85202f89" + "01" +
        "aa".repeat(32) + "00000000" + "020102" + "ffffffff" +
        "02" + "0000000000000000" + "066a04deadbeef" +
        "60ea000000000000" + "1976a914" + "11".repeat(20) + "88ac" +
        "00000000" + "00000000" + "0000000000000000" + "000000"

    @Test
    fun decodesLegacyTransaction() {
        val tx = assertNotNull(RawUtxoTransaction.decode(legacy))
        assertEquals("bd0ffb12ee08a3f452966e45c01231f0527cc656379a9bc32f9fdd313692c320", tx.txId)
        assertEquals(1, tx.version)
        assertFalse(tx.hasWitness)
        assertEquals(listOf("aa".repeat(32) + ":0", "bb".repeat(31) + "cd:7"), tx.inputs.map { it.outpoint })
        assertEquals(listOf(0xffffffffL, RawUtxoTransaction.SEQUENCE_RBF), tx.inputs.map { it.sequence })
        assertContentEquals(byteArrayOf(1, 2), tx.inputs[0].scriptSig)
        assertEquals(listOf(60_000L, 17_610L), tx.outputs.map { it.value })
        assertEquals(0, tx.lockTime)
    }

    @Test
    fun decodesSegwitTransactionAndStripsWitnessForTxId() {
        val tx = assertNotNull(RawUtxoTransaction.decode(segwit))
        assertTrue(tx.hasWitness)
        assertEquals("00852f12c57d90dd3d4262fbc10bb86203e05f6e5db147fa9e3a39143eca599e", tx.txId)
        assertEquals(2, tx.inputs[0].witness.size)
        assertEquals(0, tx.inputs[1].witness.size)
        assertEquals(500, tx.lockTime)
    }

    @Test
    fun decodesZcashSaplingHeaderAndOpReturn() {
        val tx = assertNotNull(RawUtxoTransaction.decode(zec))
        assertTrue(tx.overwintered)
        assertEquals(4, tx.version)
        assertEquals(0x892F2085L, tx.versionGroupId)
        assertEquals("bfa75952560f125160cb852ce3768fca7f033bd5ee7953a7d0eb36d3d96663aa", tx.txId)
        assertTrue(tx.outputs[0].isOpReturn)
        assertEquals("deadbeef", RawUtxoTransaction.toHex(tx.outputs[0].opReturnData!!))
        assertEquals(60_000, tx.outputs[1].value)
    }

    @Test
    fun rejectsTruncatedOrPaddedHex() {
        assertNull(RawUtxoTransaction.decode(legacy.dropLast(2)))
        assertNull(RawUtxoTransaction.decode(legacy + "00"))
        assertNull(RawUtxoTransaction.decode("zz"))
        assertNull(RawUtxoTransaction.decode(""))
    }
}
