// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.publicsigner.verify

import io.ownbit.core.crypto.hash.Hashes
import io.ownbit.core.crypto.util.Hex
import io.ownbit.core.publicsigner.model.obj
import io.ownbit.core.publicsigner.model.str
import io.ownbit.core.publicsigner.sign.PublicSignSession
import io.ownbit.core.publicsigner.testing.SigningVectors
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.bouncycastle.crypto.digests.RIPEMD160Digest
import org.junit.Test
import java.util.Base64
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertTrue

/**
 * Kotlin's own copy of the engine's PREVOUT rule ([PublicSignVerifier.pre], defense in depth): an input without
 * its previous transaction is accepted only when its `witnessUtxo` is a SegWit output — v0 (P2WPKH / P2WSH, or P2SH
 * wrapping a v0 program proven by `PSBT_IN_REDEEM_SCRIPT`), listed in [VerifiedPayload.BitcoinPsbt.witnessOnlyInputs]
 * for the outpoint memory — or Taproot. A legacy one (P2PKH, bare P2SH) is refused even if the engine let it through:
 * its signature commits to no amount at all. The PSBTs are `O-BTC-6` (BlueWallet shape) with only its input's UTXO
 * record changed — the unsigned transaction, and so the plan's digest, stay the same.
 */
class WitnessOnlyPrevoutVerifierTest {

    private val id = "O-BTC-6-segwit-witness-only"

    /** O-BTC-6's `PSBT_IN_WITNESS_UTXO` record: key `01 01`, a 31-byte value (100 000 sats, P2WPKH script). */
    private val p2wpkhUtxo = "01011f" + AMOUNT + "16" + "0014" + HASH

    /** O-BTC-6 with its input's UTXO record replaced by [record] (`""` drops it); request and CBOR payload both. */
    private fun withUtxoRecord(record: String): PublicSignSession {
        val s = SigningVectors.session(id)
        val psbt = Hex.encode(Base64.getDecoder().decode(s.request.str("psbt")!!))
        assertTrue(p2wpkhUtxo in psbt, "the O-BTC-6 input map changed")
        val mutated = Hex.decode(psbt.replace(p2wpkhUtxo, record))
        val transport = s.request.obj("transport")!!
        val request = JsonObject(
            s.request +
                ("psbt" to JsonPrimitive(Base64.getEncoder().encodeToString(mutated))) +
                ("transport" to JsonObject(transport + ("payloadBytes" to JsonPrimitive(Hex.encode(cborBytes(mutated)))))),
        )
        return s.copy(request = request)
    }

    /** A CBOR byte string (major type 2) of [bytes]. */
    private fun cborBytes(bytes: ByteArray): ByteArray = when {
        bytes.size < 256 -> byteArrayOf(0x58, bytes.size.toByte()) + bytes
        else -> byteArrayOf(0x59, (bytes.size shr 8).toByte(), bytes.size.toByte()) + bytes
    }

    /** A `PSBT_IN_WITNESS_UTXO` record of 100 000 sats paying to [scriptHex]. */
    private fun witnessUtxo(scriptHex: String): String {
        val script = Hex.decode(scriptHex)
        val value = AMOUNT + "%02x".format(script.size) + scriptHex
        return "0101" + "%02x".format(value.length / 2) + value
    }

    /** A `PSBT_IN_REDEEM_SCRIPT` record. */
    private fun redeemScript(scriptHex: String): String = "0104" + "%02x".format(scriptHex.length / 2) + scriptHex

    private fun hash160(hex: String): String {
        val sha = Hashes.sha256(Hex.decode(hex))
        val ripemd = RIPEMD160Digest()
        ripemd.update(sha, 0, sha.size)
        return Hex.encode(ByteArray(20).also { ripemd.doFinal(it, 0) })
    }

    private fun verified(s: PublicSignSession): VerifiedPayload.BitcoinPsbt =
        assertIs<VerifiedPayload.BitcoinPsbt>(assertIs<PublicSignVerifier.Verdict.Ok>(PublicSignVerifier.pre(s), "${PublicSignVerifier.pre(s)}").payload)

    private fun refusal(s: PublicSignSession): String = assertIs<PublicSignVerifier.Verdict.Refused>(PublicSignVerifier.pre(s)).detail

    @Test fun `a SegWit v0 input with witnessUtxo only is accepted and listed for the outpoint memory`() {
        assertEquals(listOf(0), verified(SigningVectors.session(id)).witnessOnlyInputs)
        // The same record rebuilt by the helpers: the mutation itself changes nothing.
        assertEquals(listOf(0), verified(withUtxoRecord(witnessUtxo("0014$HASH"))).witnessOnlyInputs)
        // P2SH wrapping a P2WPKH program, proven by the redeem script: nested SegWit v0.
        val nested = witnessUtxo("a914" + hash160("0014$HASH") + "87") + redeemScript("0014$HASH")
        assertEquals(listOf(0), verified(withUtxoRecord(nested)).witnessOnlyInputs)
        // Taproot binds every input amount: accepted, not a witness-only v0 input.
        assertEquals(emptyList(), verified(withUtxoRecord(witnessUtxo("5120" + "11".repeat(32)))).witnessOnlyInputs)
    }

    @Test fun `a legacy input with witnessUtxo only is refused by Kotlin itself`() {
        // P2PKH: its signature commits to no amount.
        assertEquals("bitcoin.prevout.legacy", refusal(withUtxoRecord(witnessUtxo("76a914" + HASH + "88ac"))))
        // P2SH without the redeem script that would prove a SegWit program: bare P2SH, legacy.
        assertEquals("bitcoin.prevout.legacy", refusal(withUtxoRecord(witnessUtxo("a914" + hash160("0014$HASH") + "87"))))
        // P2SH whose redeem script does not hash to the output, or is not a v0 witness program.
        val wrongHash = witnessUtxo("a914" + "22".repeat(20) + "87") + redeemScript("0014$HASH")
        assertEquals("bitcoin.prevout.legacy", refusal(withUtxoRecord(wrongHash)))
        val multisig = "5121" + "02" + "33".repeat(32) + "51ae"
        val notWitness = witnessUtxo("a914" + hash160(multisig) + "87") + redeemScript(multisig)
        assertEquals("bitcoin.prevout.legacy", refusal(withUtxoRecord(notWitness)))
    }

    @Test fun `an input that names no amount at all is refused`() {
        assertEquals("bitcoin.prevout", refusal(withUtxoRecord("")))
    }

    private companion object {
        /** 100 000 sats, u64 little-endian. */
        const val AMOUNT = "a086010000000000"

        /** HASH160 of the `abandon … about` key at `m/84'/0'/0'/0/0`. */
        const val HASH = "c0cebcd6c3d3ca8c75dc5ec62ebe55330ef910e2"
    }
}
