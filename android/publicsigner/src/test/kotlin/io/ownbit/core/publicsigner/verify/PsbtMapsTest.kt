// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.publicsigner.verify

import io.ownbit.core.crypto.util.Hex
import io.ownbit.core.publicsigner.model.str
import io.ownbit.core.publicsigner.testing.SigningVectors
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.util.Base64
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

/**
 * [PsbtMaps]: every PSBT of the golden vectors parses and hashes to the engine's
 * `signingBytesDigest` (v0 and v2); malformed maps are refused; signing may only add the task keys' signatures.
 */
class PsbtMapsTest {

    private fun psbt(base64: String) = Base64.getDecoder().decode(base64)

    @Test fun `every vector PSBT hashes to the engine's signing digest (v0 and v2)`() {
        val versions = HashSet<Int>()
        var checked = 0
        for (id in SigningVectors.ids()) {
            val resolve = SigningVectors.steps(id, "resolveSigningPlan").singleOrNull()?.takeIf { it.ok } ?: continue
            if (resolve.result.str("status") != "ready" || resolve.result.str("chain") != "bitcoin") continue
            val request = resolve.request.getValue("request").jsonObject
            val maps = PsbtMaps.parse(psbt(request.getValue("psbt").jsonPrimitive.content))
            assertEquals(resolve.result.str("signingBytesDigest"), maps.unsignedTxDigest, id)
            versions += maps.version
            checked++
        }
        assertTrue(checked >= 20, "checked $checked")
        assertEquals(setOf(0, 2), versions, "both PSBT versions covered")
    }

    @Test fun `native vector 2 is a PSBT v2 rebuilt to the same unsigned transaction`() {
        val maps = PsbtMaps.parse(psbt(SigningVectors.steps("T7-native-bitcoin-psbt-2", "review").single().request.getValue("request").jsonObject.getValue("psbt").jsonPrimitive.content))
        assertEquals(2, maps.version)
        assertEquals(SigningVectors.plan("T7-native-bitcoin-psbt-2").signingBytesDigest, maps.unsignedTxDigest)
    }

    @Test fun `signing only adds the task keys' signatures, in every signed vector`() {
        for (id in SigningVectors.ids()) {
            val signs = SigningVectors.steps(id, "signPlanTask").filter { it.ok }
            if (signs.isEmpty() || signs.first().request.getValue("request").jsonObject.str("chain") != "bitcoin") continue
            val request = PsbtMaps.parse(psbt(signs.first().request.getValue("request").jsonObject.getValue("psbt").jsonPrimitive.content))
            val signed = PsbtMaps.parse(psbt(signs.last().result.getValue("psbt").jsonPrimitive.content))
            val plan = SigningVectors.plan(id)
            val diff = PsbtMaps.diff(request, signed, signersOf(plan.tasks))
            assertTrue(diff.ok, "$id: ${diff.problem}")
        }
    }

    @Test fun `a two-wallet PSBT needs both wallets' keys to explain the answer`() {
        val id = "T8-flow-psbt-two-wallets"
        val plan = SigningVectors.plan(id)
        assertEquals(2, plan.tasks.size)
        val request = PsbtMaps.parse(psbt(SigningVectors.request(id).getValue("psbt").jsonPrimitive.content))
        val signed = PsbtMaps.parse(psbt(SigningVectors.signResults(id).last().getValue("psbt").jsonPrimitive.content))
        assertTrue(PsbtMaps.diff(request, signed, signersOf(plan.tasks)).ok)
        assertFalse(PsbtMaps.diff(request, signed, signersOf(plan.tasks.take(1))).ok, "the second wallet's signature is not the first task's")
    }

    @Test fun `changed maps, removed entries and foreign signatures are refused`() {
        val id = "T8-flow-bitcoin-crypto-psbt"
        val plan = SigningVectors.plan(id)
        val signers = signersOf(plan.tasks)
        val requestBytes = psbt(SigningVectors.request(id).getValue("psbt").jsonPrimitive.content)
        val signedBytes = psbt(SigningVectors.finalResult(id).raw.getValue("psbt").jsonPrimitive.content)
        val request = PsbtMaps.parse(requestBytes)
        val signed = PsbtMaps.parse(signedBytes)
        assertTrue(PsbtMaps.diff(request, signed, signers).ok)

        // Nothing added.
        assertEquals("no signature added", PsbtMaps.diff(request, request, signers).problem)
        // An output map changed (one more unknown key).
        val outChanged = edit(signed) { maps -> maps.outputs[0] += entry("fc", "01") }
        assertFalse(PsbtMaps.diff(request, outChanged, signers).ok)
        // A global entry added.
        val globalChanged = edit(signed) { maps -> maps.global += entry("fc00", "02") }
        assertFalse(PsbtMaps.diff(request, globalChanged, signers).ok)
        // An unknown input entry the request had is gone.
        val requestWithUnknown = edit(request) { maps -> maps.inputs[0] += entry("fc01", "03") }
        assertFalse(PsbtMaps.diff(requestWithUnknown, signed, signers).ok, "a removed entry")
        // A signature of another key.
        val foreign = edit(signed) { maps -> maps.inputs[0] += entry("02" + "03" + "11".repeat(32), "3044") }
        assertFalse(PsbtMaps.diff(request, foreign, signers).ok)
        // A signature on an input the task does not sign.
        val otherInput = mapOf((signers.keys.max() + 1) to signers.values.first())
        assertFalse(PsbtMaps.diff(request, signed, otherInput).ok)
        // Any other new input entry (a final script).
        val finalized = edit(signed) { maps -> maps.inputs[0] += entry("07", "00") }
        assertFalse(PsbtMaps.diff(request, finalized, signers).ok)
    }

    @Test fun `output derivations give the change-index bound its paths`() {
        fun derivations(id: String) = PsbtMaps.parse(psbt(SigningVectors.request(id).getValue("psbt").jsonPrimitive.content)).outputDerivations()
        assertEquals(listOf("m/84'/0'/0'/1/999"), derivations("O-BTC-3-change-999").map { it.pathText })
        assertEquals(listOf("m/84'/0'/0'/1/1000"), derivations("O-BTC-3-change-1000").map { it.pathText })
        assertEquals("73c5da0a", derivations("O-BTC-3-change-1000").single().fingerprint)
        assertTrue(derivations("O-BTC-3-change-bip48").single().pathText.startsWith("m/48'/0'/0'/2'/"))
        // A Taproot BIP-32 entry (0x07) with 101 leaf hashes is still read (the engine takes it as a change candidate,
        // on a P2WPKH output too): the bound must see its path.
        val tap = derivations("O-BTC-3-change-taphashes").single()
        assertEquals("m/84'/0'/0'/1/2147483647", tap.pathText)
        assertTrue(tap.taproot)
        assertEquals("73c5da0a", tap.fingerprint)
        assertEquals(listOf("m/86'/0'/0'/1/5000"), derivations("O-BTC-3-change-taproot-taphashes").map { it.pathText })
    }

    @Test fun `a key-path signature without PSBT_IN_TAP_INTERNAL_KEY is the task key's when the prevout is its BIP-86 output`() {
        // BIP-86 test vector: abandon … about, m/86'/0'/0'/0/0 → bc1p5cyxnu… (output key a60869f0…).
        val internal = Hex.decode("cc8a4bc64d897bddc5fbc2f670f7a8ba0b386779106cf1223c6fc5d7cd6fc115")
        assertEquals("5120a60869f0dbcf1dc659c9cecbaf8050135ea9e8cdc487053f1dc6880949dc684c", Hex.encode(PsbtMaps.taprootOutputScript(internal)!!))
        for (id in listOf("O-BTC-5-taproot-no-internal-key", "O-BTC-5-taproot-no-derivation")) {
            val plan = SigningVectors.plan(id)
            val request = PsbtMaps.parse(psbt(SigningVectors.request(id).getValue("psbt").jsonPrimitive.content))
            val signed = PsbtMaps.parse(psbt(SigningVectors.finalResult(id).raw.getValue("psbt").jsonPrimitive.content))
            assertEquals(null, request.tapInternalKey(0), id)
            assertEquals(Hex.encode(PsbtMaps.taprootOutputScript(internal)!!), Hex.encode(request.prevoutScript(0)!!), "$id: the witness UTXO")
            assertTrue(request.keyPathOf(0, Hex.encode(internal)), id)
            val diff = PsbtMaps.diff(request, signed, signersOf(plan.tasks))
            assertTrue(diff.ok, "$id: ${diff.problem}")
            // Another key (the BIP-84 key of the same wallet) did not make that signature.
            val other = mapOf(0 to setOf("0330d54fd0dd420a6e5f8d3624f5f3482cae350f79d5f0753bf5beef9c2d91af3c"))
            assertEquals("input 0 unexpected entry 19", PsbtMaps.diff(request, signed, other).problem, id)
        }
        // With a nonWitnessUtxo the script is the named output of the full previous transaction (scure `getPrevOut`).
        val native = PsbtMaps.parse(psbt(SigningVectors.request("T8-flow-bitcoin-crypto-psbt").getValue("psbt").jsonPrimitive.content))
        val script = assertNotNull(native.prevoutScript(0))
        assertEquals(22, script.size)
        assertEquals("0014", Hex.encode(script).take(4), "P2WPKH")
        assertFalse(native.keyPathOf(0, Hex.encode(internal)))
        // Not a point on the curve.
        assertEquals(null, PsbtMaps.taprootOutputScript(ByteArray(32) { 0xff.toByte() }))
    }

    @Test fun `malformed PSBTs are refused`() {
        val good = minimalV0()
        PsbtMaps.parse(good)
        // Magic.
        assertFailsWith<PublicVerifyException> { PsbtMaps.parse(good.copyOf().also { it[0] = 0x71 }) }
        // Trailing byte after the last map.
        assertFailsWith<PublicVerifyException> { PsbtMaps.parse(good + byteArrayOf(0)) }
        // Truncated (the output map is missing).
        assertFailsWith<PublicVerifyException> { PsbtMaps.parse(good.copyOfRange(0, good.size - 1)) }
        // A duplicate global key.
        assertFailsWith<PublicVerifyException> { PsbtMaps.parse(build(listOf(entry("00", Hex.encode(TX)), entry("00", Hex.encode(TX))), listOf(emptyList()), listOf(emptyList()))) }
        // No unsigned transaction in a v0 PSBT.
        assertFailsWith<PublicVerifyException> { PsbtMaps.parse(build(listOf(entry("fc", "00")), listOf(emptyList()), listOf(emptyList()))) }
        // An unsigned transaction with a script sig.
        val withScriptSig = TX.copyOfRange(0, 41) + byteArrayOf(0x01, 0x51) + TX.copyOfRange(42, TX.size)
        assertFailsWith<PublicVerifyException> { PsbtMaps.parse(build(listOf(entry("00", Hex.encode(withScriptSig))), listOf(emptyList()), listOf(emptyList()))) }
        // v0 with a v2-only field.
        assertFailsWith<PublicVerifyException> { PsbtMaps.parse(build(listOf(entry("00", Hex.encode(TX)), entry("04", "01")), listOf(emptyList()), listOf(emptyList()))) }
        // A non-canonical compact size (key length 1 written as fd 01 00).
        val nonCanonical = MAGIC + byteArrayOf(0xfd.toByte(), 0x01, 0x00, 0x00) + compact(TX.size) + TX + byteArrayOf(0, 0, 0)
        assertFailsWith<PublicVerifyException> { PsbtMaps.parse(nonCanonical) }
        // Unknown version.
        assertFailsWith<PublicVerifyException> { PsbtMaps.parse(build(listOf(entry("00", Hex.encode(TX)), entry("fb", "01000000")), listOf(emptyList()), listOf(emptyList()))) }
        // A v2 PSBT without its counts.
        assertFailsWith<PublicVerifyException> { PsbtMaps.parse(build(listOf(entry("fb", "02000000"), entry("02", "02000000")), emptyList(), emptyList())) }
        // Larger than 128 KiB.
        assertFailsWith<PublicVerifyException> { PsbtMaps.parse(build(listOf(entry("00", Hex.encode(TX)), entry("fc02", "00".repeat(PsbtMaps.MAX_BYTES))), listOf(emptyList()), listOf(emptyList()))) }
    }

    @Test fun `the Bitcoin compact size reader is canonical`() {
        assertEquals(0xfcL to 1L, PsbtMaps.readCompact(byteArrayOf(0xfc.toByte()), 0))
        assertEquals(0xfdL to 3L, PsbtMaps.readCompact(byteArrayOf(0xfd.toByte(), 0xfd.toByte(), 0x00), 0))
        assertFailsWith<PublicVerifyException> { PsbtMaps.readCompact(byteArrayOf(0xfd.toByte(), 0xfc.toByte(), 0x00), 0) }
        assertFailsWith<PublicVerifyException> { PsbtMaps.readCompact(byteArrayOf(0xfe.toByte(), 0x00, 0x01, 0x00, 0x00), 0) }
    }

    // ---- helpers ------------------------------------------------------------------------------------------------

    private fun signersOf(tasks: List<io.ownbit.core.publicsigner.model.PublicTask>): Map<Int, Set<String>> {
        val out = HashMap<Int, MutableSet<String>>()
        for (task in tasks) for ((input, key) in PublicSignVerifier.targetsOf(task)) out.getOrPut(input) { HashSet() } += key
        return out
    }

    private class Editable(val global: MutableList<PsbtMaps.Entry>, val inputs: MutableList<MutableList<PsbtMaps.Entry>>, val outputs: MutableList<MutableList<PsbtMaps.Entry>>)

    private fun edit(maps: PsbtMaps, block: (Editable) -> Unit): PsbtMaps {
        val e = Editable(maps.global.toMutableList(), maps.inputs.map { it.toMutableList() }.toMutableList(), maps.outputs.map { it.toMutableList() }.toMutableList())
        block(e)
        return PsbtMaps.parse(build(e.global, e.inputs, e.outputs))
    }

    private fun entry(keyHex: String, valueHex: String) = PsbtMaps.Entry(Hex.decode(keyHex), Hex.decode(valueHex))

    private fun build(global: List<PsbtMaps.Entry>, inputs: List<List<PsbtMaps.Entry>>, outputs: List<List<PsbtMaps.Entry>>): ByteArray {
        val out = ByteArrayOutputStream()
        out.write(MAGIC)
        for (map in listOf(global) + inputs + outputs) {
            for (e in map) {
                out.write(compact(e.key.size))
                out.write(e.key)
                out.write(compact(e.value.size))
                out.write(e.value)
            }
            out.write(0)
        }
        return out.toByteArray()
    }

    private fun compact(n: Int): ByteArray = when {
        n < 0xfd -> byteArrayOf(n.toByte())
        n <= 0xffff -> byteArrayOf(0xfd.toByte(), n.toByte(), (n shr 8).toByte())
        else -> byteArrayOf(0xfe.toByte(), n.toByte(), (n shr 8).toByte(), (n shr 16).toByte(), (n shr 24).toByte())
    }

    private fun minimalV0(): ByteArray = build(listOf(entry("00", Hex.encode(TX))), listOf(emptyList()), listOf(emptyList()))

    private companion object {
        val MAGIC = byteArrayOf(0x70, 0x73, 0x62, 0x74, 0xff.toByte())

        /** version 2, one input (zero txid, index 0, empty script sig, sequence ffffffff), one P2WPKH output, locktime 0. */
        val TX: ByteArray = Hex.decode(
            "02000000" + "01" + "00".repeat(32) + "00000000" + "00" + "ffffffff" +
                "01" + "a086010000000000" + "16" + "0014" + "11".repeat(20) + "00000000",
        )
    }
}
