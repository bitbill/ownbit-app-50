// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.publicsigner.verify

import io.ownbit.core.publicsigner.model.str
import io.ownbit.core.publicsigner.testing.SigningVectors
import kotlinx.serialization.json.jsonObject
import org.junit.Test
import java.util.Base64
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * [SolanaMessageHeader]: the messages of the golden vectors parse like the
 * engine reads them (legacy, v0, two required signers, durable nonce); lookup tables and broken headers are refused.
 */
class SolanaMessageHeaderTest {

    private fun message(id: String): ByteArray {
        val request = SigningVectors.steps(id).first { it.op == "review" || it.op == "resolveSigningPlan" }.request.getValue("request").jsonObject
        return Base64.getDecoder().decode(request.str("message")!!)
    }

    @Test fun `a legacy transfer - fee payer, our key in slot 0, programs`() {
        val header = SolanaMessageHeader.parse(message("T8-flow-solana-transfer"))
        assertEquals(SolanaMessageHeader.Version.LEGACY, header.version)
        assertEquals(1, header.requiredSignatures)
        assertEquals(3, header.keyCount)
        assertEquals(ABANDON_SOL, header.keyHex(0))
        assertEquals(0, header.signerSlot(ABANDON_SOL))
        assertNull(header.signerSlot("11".repeat(32)))
        assertEquals(1, header.instructions.size)
        assertFalse(header.usesDurableNonce)
    }

    @Test fun `a v0 message without lookup tables`() {
        val header = SolanaMessageHeader.parse(message("T7-native-solana-transaction-7"))
        assertEquals(SolanaMessageHeader.Version.V0, header.version)
        assertEquals(0, header.signerSlot(ABANDON_SOL))
    }

    @Test fun `two required signers - our key in slot 1`() {
        val header = SolanaMessageHeader.parse(message("T7-native-solana-transaction-8"))
        assertEquals(2, header.requiredSignatures)
        assertEquals(1, header.signerSlot(ABANDON_SOL))
    }

    @Test fun `a durable nonce is detected (first instruction AdvanceNonceAccount)`() {
        assertTrue(SolanaMessageHeader.parse(message("O-SOL-1-durable-nonce")).usesDurableNonce)
    }

    @Test fun `address lookup tables are refused`() {
        assertFailsWith<SolanaMessageHeader.LookupTables> { SolanaMessageHeader.parse(message("O-SOL-2-lookup-table")) }
    }

    @Test fun `broken headers, keys and instructions are refused`() {
        val good = message("T8-flow-solana-transfer")
        SolanaMessageHeader.parse(good)
        fun refused(bytes: ByteArray) = assertFailsWith<PublicVerifyException> { SolanaMessageHeader.parse(bytes) }
        refused(good + byteArrayOf(0)) // trailing byte
        refused(good.copyOf().also { it[0] = 0 }) // no required signer
        refused(good.copyOf().also { it[1] = 1 }) // readonly signed ≥ required
        refused(good.copyOf().also { it[2] = 3 }) // readonly unsigned > keys − required
        refused(good.copyOf().also { good.copyInto(it, 36, 4, 36) }) // duplicate static key
        val program = 4 + 3 * 32 + 32 + 1
        refused(good.copyOf().also { it[program] = 0 }) // program is the required signer
        refused(good.copyOf().also { it[program] = 9 }) // unresolved program
        refused(good.copyOf().also { it[0] = 0x81.toByte() }) // version 1
        refused(good.copyOfRange(0, 3) + byteArrayOf(0x83.toByte(), 0x00) + good.copyOfRange(4, good.size)) // non-canonical length
        refused(good.copyOfRange(0, good.size - 1)) // truncated
        refused(ByteArray(SolanaMessageHeader.MAX_BYTES + 1) { 1 }) // over the packet limit
    }

    @Test fun `off-chain messages - printable UTF-8, never a transaction header`() {
        assertTrue(SolanaMessageHeader.isValidOffchainMessage("Ownbit public protocol fixture".toByteArray()))
        assertTrue(SolanaMessageHeader.isValidOffchainMessage("签名 ✓ line\nbreak\ttab".toByteArray()))
        assertFalse(SolanaMessageHeader.isValidOffchainMessage(ByteArray(0)))
        assertFalse(SolanaMessageHeader.isValidOffchainMessage(ByteArray(1025) { 'a'.code.toByte() }))
        assertFalse(SolanaMessageHeader.isValidOffchainMessage(byteArrayOf(0x01) + "abc".toByteArray()))
        assertFalse(SolanaMessageHeader.isValidOffchainMessage(byteArrayOf(0x80.toByte(), 0x41)))
        assertFalse(SolanaMessageHeader.isValidOffchainMessage("abc\u0007def".toByteArray()))
        assertFalse(SolanaMessageHeader.isValidOffchainMessage(byteArrayOf(0x41, 0xC3.toByte(), 0x28)))
        assertTrue(SolanaMessageHeader.isValidOffchainMessage(message("T8-flow-solana-message")))
    }

    private companion object {
        /** The standard Solana key of `abandon … about` (`m/44'/501'/0'/0'`). */
        const val ABANDON_SOL = "f036276246a75b9de3349ed42b15e232f6518fc20f5fcd4f1d64e81f9bd258f7"
    }
}
