// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.chain.utxo

import java.io.ByteArrayOutputStream

/** A minimal legacy (version 2, non-witness) transaction serializer for the verifier tests. */
internal object UtxoTestSerializer {
    fun serialize(inputs: List<Pair<String, Long>>, outputs: List<Pair<Long, ByteArray>>, lockTime: Long, sequence: Long): String {
        val b = ByteArrayOutputStream()
        fun u32(v: Long) { for (i in 0 until 4) b.write(((v shr (8 * i)) and 0xff).toInt()) }
        fun u64(v: Long) { for (i in 0 until 8) b.write(((v shr (8 * i)) and 0xff).toInt()) }
        fun varInt(v: Int) { require(v < 0xfd); b.write(v) }
        u32(2)
        varInt(inputs.size)
        for ((txid, vout) in inputs) {
            b.write(RawUtxoTransaction.hexToBytes(txid).reversedArray())
            u32(vout)
            varInt(0)
            u32(sequence)
        }
        varInt(outputs.size)
        for ((value, script) in outputs) {
            u64(value)
            varInt(script.size)
            b.write(script)
        }
        u32(lockTime)
        return RawUtxoTransaction.toHex(b.toByteArray())
    }
}
