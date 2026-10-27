// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.chain.tron

import org.junit.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull

/** [TronTransactionProto] against TronLink vectors (V1 / V2 / V3, byte-exact answers). */
class TronTransactionProtoTest {

    private fun hex(s: String): ByteArray = checkNotNull(s.hexToBytesOrNull())

    @Test fun `V1 V2 V3 split into raw_data and no signature`() {
        val v1 = assertNotNull(TronTransactionProto.split(hex(V1_ENTRY)))
        assertEquals(V1_RAW, v1.raw.toHex())
        assertEquals(0, v1.signatures.size)
        val v2 = assertNotNull(TronTransactionProto.split(hex(V2_ENTRY)))
        assertEquals(V2_RAW, v2.raw.toHex())
        val v3 = assertNotNull(TronTransactionProto.split(hex(V3_ENTRY)))
        assertEquals(V3_ENTRY.substring(6), v3.raw.toHex(), "0a 85 01: a two-byte length")
    }

    @Test fun `appending the signature gives the byte-exact TronLink answers`() {
        assertEquals(V1_ENTRY + "1241" + V1_SIG, TronTransactionProto.appendSignature(hex(V1_ENTRY), hex(V1_SIG)).toHex())
        assertEquals(V3_ENTRY + "1241" + V3_SIG, TronTransactionProto.appendSignature(hex(V3_ENTRY), hex(V3_SIG)).toHex())
        val signed = assertNotNull(TronTransactionProto.split(hex(V3_ENTRY + "1241" + V3_SIG)))
        assertContentEquals(hex(V3_SIG), signed.signatures.single())
        // A second signature goes after the first (multi-signature accounts).
        val twice = TronTransactionProto.appendSignature(hex(V3_ENTRY + "1241" + V3_SIG), hex(V1_SIG)).toHex()
        assertEquals(V3_ENTRY + "1241" + V3_SIG + "1241" + V1_SIG, twice)
    }

    @Test fun `anything but field 1 then field 2 signatures is malformed`() {
        // `ret` (field 5) after raw_data.
        assertNull(TronTransactionProto.split(hex(V1_ENTRY + "2a00")))
        // An unknown field before raw_data, and a second raw_data.
        assertNull(TronTransactionProto.split(hex("0800$V1_ENTRY")))
        assertNull(TronTransactionProto.split(hex(V1_ENTRY + V1_ENTRY)))
        // A signature of 64 bytes, a truncated one, trailing bytes.
        assertNull(TronTransactionProto.split(hex(V1_ENTRY + "1240" + V1_SIG.substring(2))))
        assertNull(TronTransactionProto.split(hex(V1_ENTRY + "1241" + V1_SIG.substring(2))))
        assertNull(TronTransactionProto.split(hex(V1_ENTRY + "1241" + V1_SIG + "00")))
        // A non-minimal length varint (0x1a written as 9a 00), an empty raw_data, nothing at all.
        assertNull(TronTransactionProto.split(hex("0a9a00" + V1_RAW)))
        assertNull(TronTransactionProto.split(hex("0a00")))
        assertNull(TronTransactionProto.split(ByteArray(0)))
        // raw_data length beyond the bytes.
        assertNull(TronTransactionProto.split(hex("0a1b$V1_RAW")))
    }

    @Test fun `encode and split round trip`() {
        val raw = hex(V3_ENTRY.substring(6))
        val tx = TronTransactionProto.encode(raw, listOf(hex(V3_SIG)))
        val split = assertNotNull(TronTransactionProto.split(tx))
        assertContentEquals(raw, split.raw)
        assertEquals(1, split.signatures.size)
    }

    private companion object {
        const val V1_RAW = "5a18221654726f6e4c696e6b437573746f6d436f6e7472616374"
        const val V1_ENTRY = "0a1a$V1_RAW"
        const val V1_SIG = "c4e4c285fed57e138ab5be476870816067e34d7dbc0cc4eb04f54bc4bb681e3e" +
            "76a0e0659627a6b78f5761b9d347e002e777570408d4a6ed30ed661f5582c3cd00"
        const val V2_RAW = "5a1f221d436f6c6457616c6c65744f776e6572566572696679436f6e7472616374"
        const val V2_ENTRY = "0a21$V2_RAW"
        const val V3_ENTRY = "0a85010a02ab122208010203040506070840e0dc94809e335a67080112630a2d747970652e676f6f676c65617069732e636f6d" +
            "2f70726f746f636f6c2e5472616e73666572436f6e747261637412320a1541c8599111f29c1e1e061265b4af93ea1f274ad78a121541eca9bc" +
            "828a3005b9a3b909f2cc5c2a54794de05f18c0843d70808891809e33"
        const val V3_SIG = "bc7da2e91ff44a0bb59e401c90a790fc4c4b1538570986517a0238224c55f0a147ccb24b14f959e0cbdc26c274d7e25fa4bcd728739d91ec082dcb7ef5dcc36701"
    }
}
