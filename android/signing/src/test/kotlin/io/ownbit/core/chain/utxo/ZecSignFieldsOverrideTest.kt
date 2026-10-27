// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.chain.utxo

import io.mockk.coEvery
import io.mockk.every
import io.mockk.mockk
import io.mockk.slot
import io.ownbit.core.jsengine.JsBundle
import io.ownbit.core.jsengine.JsEngine
import io.ownbit.core.jsengine.JsEngineManager
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertSame

/**
 * iOS `ZcashJSBridge.withV4BranchOverride`: the v4 consensus-branch override reaches the ZEC bundle only — v4 data
 * only, never from the incoming data, never into the server's or the caller's JSON.
 */
class ZecSignFieldsOverrideTest {

    private val nu7 = 0x77190ad9L
    private val v4 = Json.parseToJsonElement(
        """{"inputs":[{"txid":"aa","vout":0,"satoshis":150000}],"outputs":[{"address":"t1dest","amount":100000}]}""",
    ).jsonObject
    private val v5 = ZecSignFields.merge(v4, ZecSignFields.v5(0x37a5165bL))

    @Test
    fun `the override is added to v4 data only, as a JSON number`() {
        val out = ZecSignFields.withV4BranchOverride(v4, nu7)
        assertEquals(JsonPrimitive(nu7), out[ZecSignFields.V4_BRANCH_OVERRIDE])
        assertFalse(out[ZecSignFields.V4_BRANCH_OVERRIDE]!!.jsonPrimitive.isString)
        assertEquals(v4, JsonObject(out - ZecSignFields.V4_BRANCH_OVERRIDE), "nothing else changes")
        // v5 carries its branch in zecBranchId; null = the bundle's own id.
        assertEquals(v5, ZecSignFields.withV4BranchOverride(v5, nu7))
        assertSame(v4, ZecSignFields.withV4BranchOverride(v4, null))
        // The bundle's own v4 id is not passed (same signature; the shipped bundle's key paths reject any override).
        assertSame(v4, ZecSignFields.withV4BranchOverride(v4, ZecSignFields.BUNDLE_V4_BRANCH_ID))
        assertEquals(0x37a5165bL, ZecSignFields.BUNDLE_V4_BRANCH_ID)
    }

    @Test
    fun `an incoming override is always removed`() {
        val planted = JsonObject(v4 + (ZecSignFields.V4_BRANCH_OVERRIDE to JsonPrimitive(0x12345678L)))
        assertEquals(v4, ZecSignFields.withV4BranchOverride(planted, null))
        assertEquals(v4, ZecSignFields.withV4BranchOverride(planted, ZecSignFields.BUNDLE_V4_BRANCH_ID))
        assertEquals(JsonPrimitive(nu7), ZecSignFields.withV4BranchOverride(planted, nu7)[ZecSignFields.V4_BRANCH_OVERRIDE])
        val plantedV5 = JsonObject(v5 + (ZecSignFields.V4_BRANCH_OVERRIDE to JsonPrimitive(0x12345678L)))
        assertEquals(v5, ZecSignFields.withV4BranchOverride(plantedV5, nu7))
        // Never one of the keys carried to the server.
        assertFalse(ZecSignFields.V4_BRANCH_OVERRIDE in ZecSignFields.KEYS)
        assertNull(ZecSignFields.carry(planted)[ZecSignFields.V4_BRANCH_OVERRIDE])
    }

    // --- single-sig signer --------------------------------------------------------------------------------------------

    private val engine = mockk<JsEngine>()
    private val engines = mockk<JsEngineManager>().also { every { it.engine(any()) } returns engine }
    private val sent = mutableListOf<JsonArray>()

    init {
        every { engine.bundle } returns JsBundle.ZEC
        val args = slot<JsonArray>()
        coEvery { engine.call(any(), capture(args), any()) } answers {
            sent += args.captured
            JsonArray(listOf(JsonPrimitive("txid"), JsonPrimitive("00")))
        }
    }

    /** The JSON text the bundle got (last argument). */
    private fun bundleJson(): JsonObject = Json.parseToJsonElement((sent.last().last() as JsonPrimitive).content).jsonObject

    /** The host app's override provider; counts reads. */
    private class Override(private val value: Long?) : () -> Long? {
        var calls = 0
        override fun invoke(): Long? = value.also { calls++ }
    }

    private fun network(override: Long?) = Override(override)

    @Test
    fun `JsUtxoTxSigner passes the override for ZEC v4 only and leaves the caller's object alone`() = runTest {
        val signer = JsUtxoTxSigner(engines, network(nu7))
        val seed = UtxoSigningKey.Seed("00".toCharArray(), "0")
        val copy = JsonObject(v4)
        signer.sign(UtxoChainProfile.ZEC, copy, seed)
        assertEquals(JsonPrimitive(nu7), bundleJson()[ZecSignFields.V4_BRANCH_OVERRIDE])
        assertEquals(v4, copy, "the post-sign verifier reads the untouched sign data")
        // Private-key wallets: same rule.
        signer.sign(UtxoChainProfile.ZEC, v4, UtxoSigningKey.PrivateKey("KzEV".toCharArray()))
        assertEquals(JsonPrimitive(nu7), bundleJson()[ZecSignFields.V4_BRANCH_OVERRIDE])
        // v5 → nothing added.
        signer.sign(UtxoChainProfile.ZEC, v5, seed)
        assertEquals(v5, bundleJson())
        // Without an override (no NU7, no zecBranchId) the JSON is unchanged.
        JsUtxoTxSigner(engines, network(null)).sign(UtxoChainProfile.ZEC, v4, seed)
        assertEquals(v4, bundleJson())
    }

    @Test
    fun `JsUtxoTxSigner never adds the override for other chains`() = runTest {
        val zec = network(nu7)
        val signer = JsUtxoTxSigner(engines, zec)
        val ltc = Json.parseToJsonElement("""{"inputs":[],"outputs":[]}""").jsonObject
        // (the fake bundle answers [txId, hex]; LTC returns hex only — only the arguments matter here)
        runCatching { signer.sign(UtxoChainProfile.LTC, ltc, UtxoSigningKey.Seed("00".toCharArray(), "0")) }
        assertEquals(ltc, bundleJson())
        assertEquals(0, zec.calls, "the ZEC state is not even read")
    }
}
