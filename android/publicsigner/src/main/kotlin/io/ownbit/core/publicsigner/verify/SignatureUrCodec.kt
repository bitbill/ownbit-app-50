// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.publicsigner.verify

import io.ownbit.core.crypto.util.Hex
import java.util.Locale
import java.util.zip.CRC32

/**
 * A public-protocol payload that is not what it must be. [what] names the part that
 * failed — never a payload, key, address or signature — so it may be logged. Callers treat it as an integrity
 * failure: nothing is shown as signed, nothing is returned.
 */
class PublicVerifyException(val what: String) : RuntimeException("Public protocol check failed: $what")

internal fun verifyCheck(condition: Boolean, what: () -> String) {
    if (!condition) throw PublicVerifyException(what())
}

/**
 * Independent Kotlin decoding of the QR frames the engine produced (`SignatureUrCodec`): Ownbit does
 * not take the engine's word for what a response QR carries — it decodes the frames itself and checks them against
 * the signing plan ([PublicSignVerifier.post]).
 *
 * - BC-UR (BCR-2020-005) with **minimal** bytewords and the CRC-32 checksum; a single-part UR or the `seqLen` pure
 *   fountain parts `encodeWhole()` produces (`ur:<type>/<seq>-<count>/…`, `seq ≤ count`; mixed parts are refused —
 *   the engine never shows them).
 * - `eth-signature` / `sol-signature` / `tron-signature` (Keystone registry): a CBOR map `{1: #6.37(request-id),
 *   2: signature}` and nothing else.
 * - A signed PSBT in the request's own transport: `crypto-psbt` / `psbt` UR, BBQr `H` / `2`, PSBT Base64 / hex text.
 *
 * Also reads the original request CBOR (`transport.payloadBytes`) for [PublicSignVerifier.pre]. Pure Kotlin, nothing
 * logged.
 */
object SignatureUrCodec {

    /** A decoded UR: its lower-case [type] and the CBOR bytes it carries. */
    class Ur(val type: String, val cbor: ByteArray) {
        override fun toString(): String = "Ur($type, ${cbor.size} bytes)"
    }

    /** A decoded signature answer. [requestId] is `null` when the map has no key 1. */
    class SignatureUr(val type: String, val requestId: ByteArray?, val signature: ByteArray) {
        override fun toString(): String = "SignatureUr($type, id=${requestId?.size ?: 0} bytes, signature=${signature.size} bytes)"
    }

    /** UR types of the signature answers. */
    val SIGNATURE_TYPES: Set<String> = setOf("eth-signature", "sol-signature", "tron-signature")

    /** Most frames of one decoded UR (engine `QR_LIMITS.frames`). */
    private const val MAX_FRAMES = 2_048

    /** Largest decoded payload (engine `QR_LIMITS.payloadBytes`). */
    private const val MAX_PAYLOAD = 131_072

    /**
     * Decodes [frames] into one UR: one single-part frame, or the pure fountain parts of one message (any order,
     * repeats allowed when identical). Fails with [PublicVerifyException].
     */
    fun decodeUr(frames: List<String>): Ur {
        verifyCheck(frames.isNotEmpty() && frames.size <= MAX_FRAMES) { "ur.frames" }
        val parsed = frames.map(::parseUrFrame)
        val type = parsed.first().type
        verifyCheck(parsed.all { it.type == type }) { "ur.type" }
        if (parsed.first().seq == null) {
            verifyCheck(parsed.size == 1) { "ur.single" }
            val body = bytewords(parsed.first().body)
            verifyCheck(body.isNotEmpty() && body.size <= MAX_PAYLOAD) { "ur.size" }
            return Ur(type, body)
        }
        verifyCheck(parsed.all { it.seq != null }) { "ur.parts" }
        val count = parsed.first().count!!
        verifyCheck(parsed.all { it.count == count }) { "ur.count" }
        val fragments = arrayOfNulls<ByteArray>(count)
        var messageLength = -1L
        var checksum = -1L
        for (part in parsed) {
            val seq = part.seq!!
            verifyCheck(seq in 1..count) { "ur.seq" }
            val cbor = Cbor.decode(bytewords(part.body)) as? List<*> ?: throw PublicVerifyException("ur.part")
            verifyCheck(cbor.size == 5) { "ur.part" }
            val partSeq = cbor[0] as? Long
            val partCount = cbor[1] as? Long
            val length = cbor[2] as? Long
            val sum = cbor[3] as? Long
            val fragment = cbor[4] as? ByteArray
            verifyCheck(partSeq == seq.toLong() && partCount == count.toLong()) { "ur.part.seq" }
            verifyCheck(length != null && length in 1..MAX_PAYLOAD && sum != null && sum in 0..0xFFFF_FFFFL) { "ur.part.meta" }
            verifyCheck(fragment != null && fragment.isNotEmpty()) { "ur.part.fragment" }
            verifyCheck(messageLength == -1L || (messageLength == length && checksum == sum)) { "ur.part.mixed" }
            messageLength = length!!
            checksum = sum!!
            val previous = fragments[seq - 1]
            verifyCheck(previous == null || previous.contentEquals(fragment)) { "ur.part.conflict" }
            fragments[seq - 1] = fragment
        }
        verifyCheck(fragments.all { it != null }) { "ur.incomplete" }
        val fragmentLength = fragments[0]!!.size
        verifyCheck(fragments.all { it!!.size == fragmentLength }) { "ur.part.size" }
        verifyCheck((messageLength + fragmentLength - 1) / fragmentLength == count.toLong()) { "ur.part.size" }
        val joined = ByteArray(count * fragmentLength)
        fragments.forEachIndexed { i, f -> f!!.copyInto(joined, i * fragmentLength) }
        val message = joined.copyOfRange(0, messageLength.toInt())
        verifyCheck(crc32(message) == checksum) { "ur.checksum" }
        return Ur(type, message)
    }

    /**
     * The signature answer in [frames]: a UR of a [SIGNATURE_TYPES] type whose CBOR is a map with key 2
     * (a byte string) and optionally key 1 (`#6.37` byte string, the request id) — nothing else.
     */
    fun decodeSignature(frames: List<String>): SignatureUr {
        val ur = decodeUr(frames)
        verifyCheck(ur.type in SIGNATURE_TYPES) { "signature.type" }
        val map = Cbor.decode(ur.cbor) as? Map<*, *> ?: throw PublicVerifyException("signature.map")
        verifyCheck(map.keys.all { it == 1L || it == 2L }) { "signature.keys" }
        val signature = map[2L] as? ByteArray ?: throw PublicVerifyException("signature.value")
        val id = map[1L]?.let { tagged ->
            val t = tagged as? Cbor.Tagged ?: throw PublicVerifyException("signature.requestId")
            verifyCheck(t.tag == UUID_TAG) { "signature.requestId.tag" }
            t.value as? ByteArray ?: throw PublicVerifyException("signature.requestId")
        }
        return SignatureUr(ur.type, id, signature)
    }

    /**
     * The PSBT bytes a signed-PSBT answer of transport [type] carries: `crypto-psbt` / `psbt` (UR holding a CBOR byte
     * string), `bbqr-psbt` (BBQr `H` hex or `2` Base32, every part once), `psbt-base64` / `psbt-hex` (one text frame).
     */
    fun decodePsbt(type: String, frames: List<String>): ByteArray {
        val bytes = when (type) {
            "crypto-psbt", "psbt" -> {
                val ur = decodeUr(frames)
                verifyCheck(ur.type == type) { "psbt.urType" }
                Cbor.decode(ur.cbor) as? ByteArray ?: throw PublicVerifyException("psbt.cbor")
            }
            "bbqr-psbt" -> decodeBbqr(frames)
            "psbt-base64" -> {
                verifyCheck(frames.size == 1) { "psbt.frames" }
                base64(frames.single())
            }
            "psbt-hex" -> {
                verifyCheck(frames.size == 1) { "psbt.frames" }
                Hex.decodeOrNull(frames.single()) ?: throw PublicVerifyException("psbt.hex")
            }
            else -> throw PublicVerifyException("psbt.type")
        }
        verifyCheck(bytes.size in 5..MAX_PAYLOAD && bytes.copyOfRange(0, 5).contentEquals(PSBT_MAGIC)) { "psbt.magic" }
        return bytes
    }

    /**
     * The `signData` (key 2) of an original `*-sign-request` CBOR ([payloadBytes] = `transport.payloadBytes`), with
     * the other keys the Kotlin checks read: EVM `3` dataType / `4` chainId, TRON `3` dataType, Solana `6` signType.
     */
    fun decodeSignRequest(type: String, payloadBytes: ByteArray): SignRequestCbor {
        val map = Cbor.decode(payloadBytes) as? Map<*, *> ?: throw PublicVerifyException("request.map")
        val maxKey = if (type == "eth-sign-request") 7L else 6L
        verifyCheck(map.keys.all { it is Long && it in 1..maxKey }) { "request.keys" }
        val signData = map[2L] as? ByteArray ?: throw PublicVerifyException("request.signData")
        val requestId = (map[1L] as? Cbor.Tagged)?.value as? ByteArray
        return when (type) {
            "eth-sign-request" -> SignRequestCbor(signData, map[3L] as? Long, map[4L] as? Long, requestId)
            "tron-sign-request" -> SignRequestCbor(signData, map[3L] as? Long, null, requestId)
            "sol-sign-request" -> SignRequestCbor(signData, map[6L] as? Long, null, requestId)
            else -> throw PublicVerifyException("request.type")
        }
    }

    /** What [decodeSignRequest] reads: the signed bytes, the data / sign type, the EVM chain id, the request id. */
    class SignRequestCbor(val signData: ByteArray, val dataType: Long?, val chainId: Long?, val requestId: ByteArray?) {
        override fun toString(): String = "SignRequestCbor(${signData.size} bytes, dataType=$dataType, chainId=$chainId)"
    }

    // ---- UR text ----------------------------------------------------------------------------------------------------

    private class UrFrame(val type: String, val seq: Int?, val count: Int?, val body: String)

    private val UR_FRAME = Regex("^[Uu][Rr]:([A-Za-z0-9-]{1,64})/(?:([0-9]{1,10})-([0-9]{1,10})/)?([A-Za-z]+)$")

    private fun parseUrFrame(frame: String): UrFrame {
        val m = UR_FRAME.matchEntire(frame.trim()) ?: throw PublicVerifyException("ur.frame")
        val type = m.groupValues[1].lowercase(Locale.ROOT)
        if (m.groupValues[2].isEmpty()) return UrFrame(type, null, null, m.groupValues[4])
        val seq = m.groupValues[2].toLong()
        val count = m.groupValues[3].toLong()
        verifyCheck(seq in 1..0xFFFF_FFFFL && count in 1..MAX_FRAMES.toLong()) { "ur.sequence" }
        // Only the pure fragments (seq ≤ count) are accepted: they are what the engine's encodeWhole() emits.
        verifyCheck(seq <= count) { "ur.mixedPart" }
        return UrFrame(type, seq.toInt(), count.toInt(), m.groupValues[4])
    }

    /** Minimal bytewords (two letters per byte, any case) → bytes, after checking and removing the CRC-32. */
    internal fun bytewords(text: String): ByteArray {
        verifyCheck(text.length % 2 == 0 && text.length >= 10) { "bytewords.length" }
        val lower = text.lowercase(Locale.ROOT)
        val out = ByteArray(lower.length / 2)
        for (i in out.indices) {
            val first = lower[i * 2]
            val last = lower[i * 2 + 1]
            verifyCheck(first in 'a'..'z' && last in 'a'..'z') { "bytewords.char" }
            val value = MINIMAL_LOOKUP[(first - 'a') * 26 + (last - 'a')]
            verifyCheck(value >= 0) { "bytewords.word" }
            out[i] = value.toByte()
        }
        val body = out.copyOfRange(0, out.size - 4)
        val sum = ((out[out.size - 4].toLong() and 0xFF) shl 24) or ((out[out.size - 3].toLong() and 0xFF) shl 16) or
            ((out[out.size - 2].toLong() and 0xFF) shl 8) or (out[out.size - 1].toLong() and 0xFF)
        verifyCheck(crc32(body) == sum) { "bytewords.checksum" }
        return body
    }

    /**
     * The 256 bytewords (BCR-2020-012), four letters each; a minimal byteword is its first and last letter, which are
     * unique (the same table as `@ngraveio/bc-ur` `bytewords.js` used by the engine).
     */
    private const val BYTEWORDS: String =
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

    private val MINIMAL_LOOKUP: IntArray = IntArray(26 * 26) { -1 }.also { table ->
        check(BYTEWORDS.length == 256 * 4) { "bytewords table" }
        for (i in 0 until 256) {
            val word = BYTEWORDS.substring(i * 4, i * 4 + 4)
            val slot = (word[0] - 'a') * 26 + (word[3] - 'a')
            check(table[slot] == -1) { "bytewords collision" }
            table[slot] = i
        }
    }

    // ---- BBQr / Base32 / Base64 ---------------------------------------------------------------------------------

    private val BBQR = Regex("^B\\$([H2])P([0-9A-Z]{2})([0-9A-Z]{2})([0-9A-Z]+)$")

    private fun decodeBbqr(frames: List<String>): ByteArray {
        verifyCheck(frames.isNotEmpty()) { "bbqr.frames" }
        var header: String? = null
        var total = 0
        val parts = HashMap<Int, String>()
        for (frame in frames) {
            val m = BBQR.matchEntire(frame) ?: throw PublicVerifyException("bbqr.frame")
            val h = frame.substring(0, 6)
            verifyCheck(header == null || header == h) { "bbqr.header" }
            header = h
            total = m.groupValues[2].toInt(36)
            val index = m.groupValues[3].toInt(36)
            verifyCheck(total in 1..1295 && index < total) { "bbqr.index" }
            val previous = parts.put(index, m.groupValues[4])
            verifyCheck(previous == null || previous == m.groupValues[4]) { "bbqr.conflict" }
        }
        verifyCheck(parts.size == total) { "bbqr.incomplete" }
        val joined = buildString { for (i in 0 until total) append(parts.getValue(i)) }
        return if (header!![2] == 'H') {
            Hex.decodeOrNull(joined)?.takeIf { joined.none { it in 'a'..'f' } } ?: throw PublicVerifyException("bbqr.hex")
        } else {
            base32(joined)
        }
    }

    /** RFC 4648 Base32 without padding (BBQr `2`); trailing bits must be zero. */
    internal fun base32(text: String): ByteArray {
        val out = java.io.ByteArrayOutputStream(text.length * 5 / 8)
        var buffer = 0L
        var bits = 0
        for (c in text) {
            val v = when (c) {
                in 'A'..'Z' -> c - 'A'
                in '2'..'7' -> c - '2' + 26
                else -> throw PublicVerifyException("base32.char")
            }
            buffer = (buffer shl 5) or v.toLong()
            bits += 5
            if (bits >= 8) {
                bits -= 8
                out.write(((buffer shr bits) and 0xFF).toInt())
            }
        }
        verifyCheck(bits < 5 && (buffer and ((1L shl bits) - 1)) == 0L) { "base32.padding" }
        return out.toByteArray()
    }

    /** Strict padded Base64 (the engine's `b64`). */
    internal fun base64(text: String): ByteArray {
        verifyCheck(BASE64.matches(text)) { "base64" }
        return try {
            java.util.Base64.getDecoder().decode(text)
        } catch (e: IllegalArgumentException) {
            throw PublicVerifyException("base64")
        }
    }

    private val BASE64 = Regex("^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$")

    internal fun crc32(bytes: ByteArray): Long = CRC32().apply { update(bytes) }.value

    private const val UUID_TAG = 37L
    private val PSBT_MAGIC = byteArrayOf(0x70, 0x73, 0x62, 0x74, 0xff.toByte())
}

/**
 * Strict CBOR reader for the public-protocol checks (the engine's `readCBOR` rules, `protocols.js`): definite lengths
 * only, depth ≤ 24, ≤ 20 000 items, integers within ±2⁵³ − 1, byte / text strings (valid UTF-8), arrays, maps with
 * integer or text keys and no duplicates, tags, `true` / `false` / `null`; no trailing bytes.
 *
 * Values: `Long`, `ByteArray`, `String`, `List<Any?>`, `Map<Any, Any?>` (insertion order), [Tagged], `Boolean`, `null`.
 */
internal object Cbor {

    class Tagged(val tag: Long, val value: Any?)

    private const val MAX_DEPTH = 24
    private const val MAX_NODES = 20_000
    private const val MAX_SAFE = 9_007_199_254_740_991L

    fun decode(bytes: ByteArray): Any? {
        val reader = Reader(bytes)
        val value = reader.item(0)
        verifyCheck(reader.pos == bytes.size) { "cbor.trailing" }
        return value
    }

    private class Reader(val bytes: ByteArray) {
        var pos = 0
        var nodes = 0

        fun take(n: Long): ByteArray {
            verifyCheck(n >= 0 && pos + n <= bytes.size) { "cbor.truncated" }
            val out = bytes.copyOfRange(pos, pos + n.toInt())
            pos += n.toInt()
            return out
        }

        fun item(depth: Int): Any? {
            verifyCheck(depth <= MAX_DEPTH && ++nodes <= MAX_NODES) { "cbor.complexity" }
            val first = take(1)[0].toInt() and 0xFF
            val major = first ushr 5
            val info = first and 31
            verifyCheck(info <= 27) { "cbor.indefinite" }
            if (major == 7) {
                return when (info) {
                    20 -> false
                    21 -> true
                    22 -> null
                    else -> throw PublicVerifyException("cbor.simple")
                }
            }
            var size = info.toLong()
            if (info >= 24) {
                size = 0
                val width = 1 shl (info - 24)
                for (b in take(width.toLong())) {
                    verifyCheck(size ushr 55 == 0L) { "cbor.integer" }
                    size = (size shl 8) or (b.toLong() and 0xFF)
                }
            }
            verifyCheck(size in 0..MAX_SAFE) { "cbor.integer" }
            return when (major) {
                0 -> size
                1 -> -1 - size
                2 -> take(size)
                3 -> {
                    val raw = take(size)
                    val decoder = Charsets.UTF_8.newDecoder()
                        .onMalformedInput(java.nio.charset.CodingErrorAction.REPORT)
                        .onUnmappableCharacter(java.nio.charset.CodingErrorAction.REPORT)
                    try {
                        decoder.decode(java.nio.ByteBuffer.wrap(raw)).toString()
                    } catch (e: java.nio.charset.CharacterCodingException) {
                        throw PublicVerifyException("cbor.utf8")
                    }
                }
                4 -> {
                    verifyCheck(size <= MAX_NODES) { "cbor.array" }
                    List(size.toInt()) { item(depth + 1) }
                }
                5 -> {
                    verifyCheck(size <= 10_000) { "cbor.map" }
                    val map = LinkedHashMap<Any, Any?>()
                    repeat(size.toInt()) {
                        val key = item(depth + 1)
                        verifyCheck(key is Long || key is String) { "cbor.mapKey" }
                        verifyCheck(!map.containsKey(key)) { "cbor.duplicateKey" }
                        map[key!!] = item(depth + 1)
                    }
                    map
                }
                6 -> Tagged(size, item(depth + 1))
                else -> throw PublicVerifyException("cbor.type")
            }
        }
    }
}
