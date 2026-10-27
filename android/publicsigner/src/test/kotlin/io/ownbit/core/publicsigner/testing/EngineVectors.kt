// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.publicsigner.testing

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put

/**
 * The golden engine vectors (`pubsigner/vectors.json`, the iOS fixture: the pinned Ownbit-edition bundle run in Node,
 * 161 cases; served as JVM test resources by this module's build file). Real engine answers for the public
 * `abandon … about` and `legal winner …` wallets — never fund these addresses.
 */
object EngineVectors {

    private val root: JsonObject by lazy {
        val url = checkNotNull(javaClass.classLoader?.getResource("pubsigner/vectors.json")) { "pubsigner/vectors.json" }
        Json.parseToJsonElement(url.readText()).jsonObject
    }

    private val cases: List<JsonObject> by lazy { root.getValue("cases").jsonArray.map { it.jsonObject } }

    private val fixtures: JsonObject by lazy { root.getValue("fixtures").jsonObject }

    /** The BIP39 seed (hex) of the vector phrase [id] (`abandon`, `legal`, `zh-hans`). */
    fun seedHex(id: String): String = root.getValue("mnemonics").jsonArray.map { it.jsonObject }
        .single { it.str("id") == id }.str("seedHex")!!

    /** The engine's public index of the vector phrase [id] (`abandon`, `legal`, `abandonOwnbit`: Ownbit's TRON scheme). */
    fun publicIndex(id: String): JsonObject = fixtures.getValue("publicIndex.$id").jsonObject

    /**
     * `derivePublicIndex` of [seedHex] as the engine answered it, `null` for a seed without a vector. [tronScheme]
     * `"ownbit"` (100 TRON addresses): the `abandonOwnbit` fixture, which the vector case
     * `T2-derivePublicIndex-abandon-ownbit` derives from the `abandon` seed; `null` for any other seed or cache size.
     */
    fun derivePublicIndex(seedHex: String, tronScheme: String? = null, tronAddressCount: Int? = null): JsonObject? {
        if (tronScheme == null && tronAddressCount == null) {
            return standardIndex(seedHex)
        }
        val standard = standardIndex(seedHex) ?: return null
        val ownbit = publicIndex("abandonOwnbit")
        return ownbit.takeIf {
            tronScheme == "ownbit" && (tronAddressCount ?: 100) == 100 && NODE_KEYS.all { k -> standard[k] == ownbit[k] }
        }
    }

    private fun standardIndex(seedHex: String): JsonObject? = steps("derivePublicIndex")
        .firstOrNull { it.request.str("seed") == seedHex && "tronScheme" !in it.request }?.result

    /**
     * The engine's `refreshPublicIndex` (`derivePublicIndex` with `publicIndex`) of a vector [index] into Ownbit's TRON
     * scheme with 100 addresses: the `abandonOwnbit` fixture for the `abandon` nodes (the vector case refreshes
     * `publicIndex.abandon` to exactly this), `null` otherwise.
     */
    fun refreshPublicIndex(index: JsonObject, tronScheme: String, tronAddressCount: Int?): JsonObject? {
        val ownbit = publicIndex("abandonOwnbit")
        return ownbit.takeIf { tronScheme == "ownbit" && (tronAddressCount ?: 100) == 100 && NODE_KEYS.all { k -> index[k] == ownbit[k] } }
    }

    /**
     * `derivePublicAddresses` for [index] (a vector index) from the vector pages (T3b): [count] addresses from [start],
     * sliced out of a page that covers them; `null` when no vector page does.
     */
    fun derivePublicAddresses(index: JsonObject, chain: String, profile: String?, start: Int, count: Int): JsonObject? {
        val fixture = fixtureId(index, chain) ?: return null
        val page = steps("derivePublicAddresses").firstOrNull { step ->
            val r = step.request
            val pageStart = r.intOrNull("start") ?: 0
            val pageCount = r.intOrNull("count") ?: 20
            fixtureRef(r["publicIndex"]) == fixture && r.str("chain") == chain &&
                normalizedProfile(chain, r.str("profile")) == normalizedProfile(chain, profile) &&
                start >= pageStart && start + count <= pageStart + pageCount && step.result != null
        } ?: return null
        val pageStart = page.request.intOrNull("start") ?: 0
        val addresses = page.result!!.getValue("addresses").jsonArray
        val slice = addresses.drop(start - pageStart).take(count)
        return buildJsonObject {
            put("addresses", JsonArray(slice))
            if (chain != "solana") {
                put("hasMore", true)
                put("nextIndex", start + count)
            } else {
                put("hasMore", false)
            }
        }
    }

    /** `createPublicPairing` for [index] with `deviceName: Ownbit` (T3), `null` when no vector has this export. */
    fun createPublicPairing(index: JsonObject, chain: String, profile: String?, outputMode: String?, addressIndex: Int): JsonObject? {
        val fixture = fixtureId(index, chain) ?: return null
        return steps("createPublicPairing").firstOrNull { step ->
            val r = step.request
            fixtureRef(r["publicIndex"]) == fixture && r.str("chain") == chain && r.str("deviceName") == "Ownbit" &&
                normalizedProfile(chain, r.str("profile")) == normalizedProfile(chain, profile) &&
                r.str("outputMode") == outputMode && (r.intOrNull("index") ?: 0) == addressIndex && step.result != null
        }?.result
    }

    /** One `dispatch` step of the vectors. */
    class Step(val request: JsonObject, val response: JsonObject) {
        val result: JsonObject? get() = if (response["ok"]?.jsonPrimitive?.content == "true") response["result"]?.jsonObject else null
    }

    fun steps(operation: String): List<Step> = cases.flatMap { it.getValue("steps").jsonArray }.map { it.jsonObject }
        .map { Step(it.getValue("request").jsonObject, it.getValue("response").jsonObject) }
        .filter { it.request.str("operation") == operation }

    /**
     * The vector wallet of [index], by its key nodes (what the engine derives addresses from): an index whose caches
     * were altered still derives the vector addresses, like the real engine.
     */
    private fun fixtureId(index: JsonObject, chain: String): String? {
        val id = listOf("abandon", "legal").firstOrNull { id ->
            val fixture = publicIndex(id)
            NODE_KEYS.all { fixture[it] == index[it] }
        } ?: return null
        // Ownbit's TRON scheme changes only TRON #N ≥ 1: its own vector pages for TRON, the standard ones else.
        val ownbit = (index["tronScheme"] as? JsonPrimitive)?.content == "ownbit"
        return if (ownbit && chain == "tron" && id == "abandon") "abandonOwnbit" else id
    }

    private val NODE_KEYS = listOf("walletKeyId", "masterFingerprint", "bitcoinPublicNodes", "evmAccountNode", "tronAccountNode", "solanaPublicKeys")

    private fun fixtureRef(element: JsonElement?): String? =
        (element as? JsonObject)?.str("\$fixture")?.removePrefix("publicIndex.")

    private fun normalizedProfile(chain: String, profile: String?): String = profile ?: when (chain) {
        "bitcoin" -> "native"
        else -> "standard"
    }

    private fun JsonObject.str(key: String): String? = (this[key] as? JsonPrimitive)?.takeIf { it.isString }?.content

    private fun JsonObject.intOrNull(key: String): Int? = (this[key] as? JsonPrimitive)?.takeIf { !it.isString }?.int
}
