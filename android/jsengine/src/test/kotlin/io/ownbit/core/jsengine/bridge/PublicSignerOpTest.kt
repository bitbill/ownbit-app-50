// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.jsengine.bridge

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Test
import java.io.File
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * [PublicSignerOp] is exactly the production allowlist (11 operations, each on its page class), and it is checked
 * against the engine that ships (`js/pubsigner-lib-bridge/signer.js`): every allow-listed operation is one the vendored engine's
 * `execute` switch knows, and every engine operation outside the allowlist is one of the documented exclusions (a new
 * engine operation fails here until it is classified).
 */
class PublicSignerOpTest {

    @Test
    fun `the allowlist is the 11 operations with their page classes`() {
        assertEquals(
            listOf(
                "capabilities" to PublicSignerPage.PAIRING,
                "derivePublicAddresses" to PublicSignerPage.PAIRING,
                "createPublicPairing" to PublicSignerPage.PAIRING,
                "derivePublicIndex" to PublicSignerPage.SECRET,
                "signPlanTask" to PublicSignerPage.SECRET,
                "scanBegin" to PublicSignerPage.SCAN,
                "scanAdd" to PublicSignerPage.SCAN,
                "decodePayload" to PublicSignerPage.UNTRUSTED,
                "review" to PublicSignerPage.UNTRUSTED,
                "resolveSigningPlan" to PublicSignerPage.UNTRUSTED,
                "encodeResponse" to PublicSignerPage.UNTRUSTED,
            ),
            PublicSignerOp.entries.map { it.wire to it.page },
        )
        assertEquals(PublicSignerOp.entries.size, PublicSignerOp.entries.map { it.wire }.toSet().size, "wire names are unique")
    }

    @Test
    fun `only the two SECRET operations carry a seed`() {
        assertEquals(
            setOf(PublicSignerOp.DERIVE_PUBLIC_INDEX, PublicSignerOp.SIGN_PLAN_TASK),
            PublicSignerOp.entries.filter { it.carriesSeed }.toSet(),
        )
    }

    @Test
    fun `excluded engine operations are not reachable`() {
        val wires = PublicSignerOp.entries.map { it.wire }.toSet()
        for (excluded in EXCLUDED + "execute" + "sign") assertTrue(excluded !in wires, "$excluded must not be allow-listed")
    }

    @Test
    fun `the allowlist and the exclusions cover every operation of the shipped engine`() {
        val bundle = File("../../js/pubsigner-lib-bridge/signer.js")
        assertTrue(bundle.isFile, "engine bundle not found at ${bundle.absolutePath}")
        // The minified bundle's operation switch: `switch(…,e.operation){case"…":…default:throw …}`.
        val execute = bundle.readText().substringAfter("e.operation){").substringBefore("default:throw")
        val engineOps = Regex("""case"([A-Za-z]+)":""").findAll(execute).map { it.groupValues[1] }.toSet()
        assertTrue(engineOps.size >= 20, "engine operations not found: $engineOps")
        val wires = PublicSignerOp.entries.map { it.wire }.toSet()
        assertEquals(emptySet(), wires - engineOps, "allow-listed operations the engine does not know")
        assertEquals(EXCLUDED.toSet(), engineOps - wires, "engine operations that are neither allowed nor documented as excluded")
    }

    @Test
    fun `the golden vectors use only allow-listed operations plus one unknown-operation refusal`() {
        val vectors = Json.parseToJsonElement(File(VECTORS).readText()).jsonObject
        val used = vectors.getValue("cases").jsonArray.flatMap { case ->
            case.jsonObject.getValue("steps").jsonArray.map { it.jsonObject.getValue("request").jsonObject.getValue("operation").jsonPrimitive.content }
        }.toSet()
        assertEquals(PublicSignerOp.entries.map { it.wire }.toSet() + "noSuchOperation", used)
    }

    private companion object {
        const val VECTORS = "../../iOS/Tests/OwnbitCoreTests/PublicProtocol/Fixtures/vectors.json"

        /** Never reachable (the engine's execute switch; `deriveWalletPublic` aliases `derivePublicIndex`). */
        val EXCLUDED = listOf(
            "decodeQR", "mnemonic", "validateMnemonic", "wordlist", "deriveAccounts", "deriveBitcoinCosigner",
            "validateBitcoinPolicy", "sign", "encodeQR", "createPairing", "createWalletPairing", "deriveWalletPublic",
        )
    }
}
