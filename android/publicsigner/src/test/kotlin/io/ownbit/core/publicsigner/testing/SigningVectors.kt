// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.publicsigner.testing

import io.mockk.coEvery
import io.ownbit.core.crypto.util.Hex
import io.ownbit.core.jsengine.PublicSignerException
import io.ownbit.core.jsengine.bridge.PublicSignerJsBridge
import io.ownbit.core.jsengine.bridge.ReviewAndPlan
import io.ownbit.core.publicsigner.model.PublicPlan
import io.ownbit.core.publicsigner.model.PublicResponseQr
import io.ownbit.core.publicsigner.model.PublicReview
import io.ownbit.core.publicsigner.model.PublicSignResult
import io.ownbit.core.publicsigner.sign.PublicSignSession
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.io.ByteArrayOutputStream
import java.util.zip.CRC32

/**
 * The signing flows of the golden vectors (`pubsigner/vectors.json`: the pinned Ownbit-edition engine run in Node):
 * scan → review → resolveSigningPlan → signPlanTask → encodeResponse, real engine answers for the public `abandon …
 * about` / `legal winner …` wallets (`wallet-abandon`, `wallet-legal`). Never fund these addresses.
 */
object SigningVectors {

    val root: JsonObject by lazy {
        val url = checkNotNull(javaClass.classLoader?.getResource("pubsigner/vectors.json")) { "pubsigner/vectors.json" }
        Json.parseToJsonElement(url.readText()).jsonObject
    }

    private val cases: Map<String, JsonObject> by lazy {
        root.getValue("cases").jsonArray.map { it.jsonObject }.associateBy { it.getValue("id").jsonPrimitive.content }
    }

    /** One `dispatch` step. */
    class Step(val request: JsonObject, val response: JsonObject) {
        val op: String get() = request.getValue("operation").jsonPrimitive.content
        val ok: Boolean get() = response["ok"]?.jsonPrimitive?.content == "true"
        val result: JsonObject get() = response.getValue("result").jsonObject
        val errorCode: String get() = response.getValue("error").jsonObject.getValue("code").jsonPrimitive.content
        val errorMessage: String get() = response.getValue("error").jsonObject.getValue("message").jsonPrimitive.content
        fun error(): PublicSignerException = PublicSignerException(errorCode, errorMessage)
    }

    fun ids(): Set<String> = cases.keys

    fun steps(id: String): List<Step> = cases.getValue(id).getValue("steps").jsonArray.map {
        val o = it.jsonObject
        Step(expand(o.getValue("request")).jsonObject, o.getValue("response").jsonObject)
    }

    fun steps(id: String, op: String): List<Step> = steps(id).filter { it.op == op }

    /** The request the flow decoded (last complete scan / paste). */
    fun request(id: String): JsonObject = steps(id).last {
        (it.op == "scanAdd" || it.op == "decodePayload") && it.ok && it.result["complete"]?.jsonPrimitive?.content == "true"
    }.result.getValue("request").jsonObject

    fun review(id: String): JsonObject = steps(id, "review").single().result
    fun planJson(id: String): JsonObject = steps(id, "resolveSigningPlan").single().result
    fun plan(id: String): PublicPlan = PublicPlan.fromEngine(planJson(id))
    fun signResults(id: String): List<JsonObject> = steps(id, "signPlanTask").filter { it.ok }.map { it.result }
    fun encoded(id: String): JsonObject = steps(id, "encodeResponse").single { it.ok }.result
    fun response(id: String): PublicResponseQr = PublicResponseQr.fromEngine(encoded(id))
    fun finalResult(id: String): PublicSignResult = PublicSignResult.fromEngine(signResults(id).last())

    /** A ready session of flow [id] (request + plan review + plan); the Kotlin pre-check is not run. */
    fun session(id: String, requestId: String = "req-$id"): PublicSignSession {
        val plan = plan(id)
        return PublicSignSession(requestId, request(id), plan.review!!, plan)
    }

    /** Flows that end with a verified answer (scan → … → encodeResponse, every step ok). */
    val answeredFlows: List<String> by lazy {
        cases.keys.filter { id ->
            val s = steps(id)
            s.any { it.op == "encodeResponse" && it.ok } && s.any { it.op == "signPlanTask" && it.ok } &&
                s.any { it.op == "resolveSigningPlan" } && s.none { it.op == "review" && !it.ok }
        }.sorted()
    }

    /** Wallet id of the vectors → BIP39 seed hex. */
    val seeds: Map<String, String> by lazy {
        val byPhrase = root.getValue("mnemonics").jsonArray.map { it.jsonObject }
            .associate { it.getValue("id").jsonPrimitive.content to it.getValue("seedHex").jsonPrimitive.content }
        root.getValue("wallets").jsonObject.mapValues { (_, phrase) -> byPhrase.getValue(phrase.jsonPrimitive.content) }
    }

    /** Replaces `{"$fixture": "publicIndex.abandon"}` references by the fixture. */
    fun expand(element: JsonElement): JsonElement = when (element) {
        is JsonObject -> {
            val ref = (element["\$fixture"] as? JsonPrimitive)?.content
            if (ref != null && element.size == 1) {
                root.getValue("fixtures").jsonObject.getValue(ref)
            } else {
                JsonObject(element.mapValues { expand(it.value) })
            }
        }
        is JsonArray -> JsonArray(element.map(::expand))
        else -> element
    }

    private val allSteps: List<Step> by lazy { cases.keys.flatMap(::steps) }

    /**
     * Stubs the signing operations of a mocked [bridge] with the recorded engine answers: `reviewAndResolve` (review +
     * plan of the same request; [planFor] may replace the plan, e.g. by the wallets offered), `signPlanTask` (the seed
     * must be the task wallet's, else `SIGNER`), `encodeResponse`, `decodePayload`. [log] records every call.
     */
    fun replay(
        bridge: PublicSignerJsBridge,
        log: MutableList<String> = ArrayList(),
        planFor: (request: JsonObject, wallets: JsonArray, recorded: JsonObject) -> JsonObject = { _, _, recorded -> recorded },
        reviewFor: (request: JsonObject, recorded: JsonObject) -> JsonObject = { _, recorded -> recorded },
        encodeFor: (request: JsonObject, result: JsonObject, recorded: JsonObject) -> JsonObject = { _, _, recorded -> recorded },
    ): MutableList<String> {
        coEvery { bridge.reviewAndResolve(any(), any()) } coAnswers {
            val request = firstArg<JsonObject>()
            val wallets = secondArg<JsonArray>()
            log += "reviewAndResolve"
            val review = allSteps.firstOrNull { it.op == "review" && it.request["request"] == request }
            if (review != null && !review.ok) throw review.error()
            val resolve = allSteps.first { it.op == "resolveSigningPlan" && it.request["request"] == request }
            ReviewAndPlan(review?.result?.let { reviewFor(request, it) }, planFor(request, wallets, resolve.result))
        }
        coEvery { bridge.signPlanTask(any(), any(), any(), any(), any(), any()) } coAnswers {
            val request = firstArg<JsonObject>()
            val plan = secondArg<JsonObject>()
            val taskId = thirdArg<String>()
            val seed = String(arg<CharArray>(3))
            val ack = arg<Boolean>(4)
            val previous = arg<JsonObject?>(5)
            log += "signPlanTask:$taskId:ack=$ack"
            fun same(s: Step) = s.op == "signPlanTask" && s.request["request"] == request && s.request["taskId"]?.jsonPrimitive?.content == taskId
            // The engine insists on consent only where it refused without it (RISK); otherwise the flag does not matter.
            if (!ack) allSteps.firstOrNull { same(it) && !it.ok && it.errorCode == "RISK" }?.let { throw it.error() }
            val step = allSteps.firstOrNull { s -> same(s) && s.ok && s.request["plan"] == plan && s.request["previousResult"] == previous }
                ?: allSteps.firstOrNull { same(it) && !it.ok }?.let { throw it.error() }
                ?: throw PublicSignerException("INTEGRITY", "The request or signing plan changed after review")
            if (step.request["seed"]?.jsonPrimitive?.content != seed) throw PublicSignerException("SIGNER", "The decrypted wallet does not match the signing plan")
            step.result
        }
        coEvery { bridge.encodeResponse(any(), any(), any()) } coAnswers {
            val request = firstArg<JsonObject>()
            val result = secondArg<JsonObject>()
            log += "encodeResponse"
            val step = allSteps.first { it.op == "encodeResponse" && it.request["request"] == request && it.request["result"] == result && it.ok }
            encodeFor(request, result, step.result)
        }
        coEvery { bridge.decodePayload(any()) } coAnswers {
            val payload = firstArg<String>()
            log += "decodePayload"
            val step = allSteps.firstOrNull { it.op == "decodePayload" && it.request["payload"]?.jsonPrimitive?.content == payload }
                ?: throw PublicSignerException("QR_PROTOCOL", "Unsupported signing QR format")
            if (!step.ok) throw step.error()
            step.result
        }
        return log
    }
}

/** Test-only CBOR writer and single-part BC-UR encoder (to build tampered answers). */
object TestUr {

    /** CBOR of: Long, ByteArray, String, List, Map (insertion order), [Tag], Boolean. */
    fun cbor(value: Any?): ByteArray {
        val out = ByteArrayOutputStream()
        write(out, value)
        return out.toByteArray()
    }

    class Tag(val tag: Long, val value: Any?)

    private fun head(out: ByteArrayOutputStream, major: Int, n: Long) {
        val m = major shl 5
        when {
            n < 24 -> out.write(m or n.toInt())
            n < 256 -> { out.write(m or 24); out.write(n.toInt()) }
            n < 65_536 -> { out.write(m or 25); out.write((n shr 8).toInt() and 0xFF); out.write(n.toInt() and 0xFF) }
            else -> { out.write(m or 26); for (s in intArrayOf(24, 16, 8, 0)) out.write((n shr s).toInt() and 0xFF) }
        }
    }

    private fun write(out: ByteArrayOutputStream, v: Any?) {
        when (v) {
            is Long -> head(out, 0, v)
            is Int -> head(out, 0, v.toLong())
            is ByteArray -> { head(out, 2, v.size.toLong()); out.write(v) }
            is String -> { val b = v.toByteArray(); head(out, 3, b.size.toLong()); out.write(b) }
            is List<*> -> { head(out, 4, v.size.toLong()); v.forEach { write(out, it) } }
            is Map<*, *> -> { head(out, 5, v.size.toLong()); v.forEach { (k, x) -> write(out, k); write(out, x) } }
            is Tag -> { head(out, 6, v.tag); write(out, v.value) }
            is Boolean -> out.write(if (v) 0xF5 else 0xF4)
            null -> out.write(0xF6)
            else -> error("unsupported ${v.javaClass}")
        }
    }

    private const val WORDS =
        "ableacidalsoapexaquaarchatomauntawayaxisbackbaldbarnbeltbetabiasbluebodybragbrewbulbbuzzcalmcashcatschefcity" +
            "clawcodecolacookcostcruxcurlcuspcyandarkdatadaysdelidicedietdoordowndrawdropdrumdulldutyeacheasyechoedge" +
            "epicevenexamexiteyesfactfairfernfigsfilmfishfizzflapflewfluxfoxyfreefrogfuelfundgalagamegeargemsgiftgirl" +
            "glowgoodgraygrimgurugushgyrohalfhanghardhawkheathelphighhillholyhopehornhutsicedideaidleinchinkyintoiris" +
            "ironitemjadejazzjoinjoltjowljudojugsjumpjunkjurykeepkenokeptkeyskickkilnkingkitekiwiknoblamblavalazyleaf" +
            "legsliarlimplionlistlogoloudloveluaulucklungmainmanymathmazememomenumeowmildmintmissmonknailnavyneednews" +
            "nextnoonnotenumbobeyoboeomitonyxopenovalowlspaidpartpeckplaypluspoempoolposepuffpumapurrquadquizraceramp" +
            "realredorichroadrockroofrubyruinrunsrustsafesagascarsetssilkskewslotsoapsolosongstubsurfswantacotasktaxi" +
            "tenttiedtimetinytoiltombtoystriptunatwinuglyundouniturgeuservastveryvetovialvibeviewvisavoidvowswallwand" +
            "warmwaspwavewaxywebswhatwhenwhizwolfworkyankyawnyellyogayurtzapszerozestzinczonezoom"

    /** Minimal bytewords of [bytes] + CRC-32. */
    fun bytewords(bytes: ByteArray): String {
        val crc = CRC32().apply { update(bytes) }.value
        val all = bytes + byteArrayOf((crc shr 24).toByte(), (crc shr 16).toByte(), (crc shr 8).toByte(), crc.toByte())
        return all.joinToString("") { b -> val i = b.toInt() and 0xFF; "${WORDS[i * 4]}${WORDS[i * 4 + 3]}" }
    }

    /** A single-part UR (upper case, like the engine's frames). */
    fun single(type: String, cbor: ByteArray): String = "UR:${type.uppercase()}/${bytewords(cbor).uppercase()}"

    /** A signature answer `{1: #6.37(id)?, 2: signature, …extra}`. */
    fun signature(type: String, requestId: String?, signature: ByteArray, extra: Map<Long, Any?> = emptyMap()): String {
        val map = LinkedHashMap<Any, Any?>()
        if (requestId != null) map[1L] = Tag(37, Hex.decode(requestId))
        map[2L] = signature
        map.putAll(extra)
        return single(type, cbor(map))
    }
}
