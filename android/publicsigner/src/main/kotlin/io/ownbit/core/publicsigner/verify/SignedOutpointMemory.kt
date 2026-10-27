// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.publicsigner.verify

import io.ownbit.core.crypto.hash.Hashes
import io.ownbit.core.crypto.util.Hex
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

/**
 * The amounts this device signed for each Bitcoin outpoint (Coldcard's `OutptValueCache`): BIP-143
 * signatures of SegWit v0 inputs commit only to their own input's amount, so a coordinator could send two requests over
 * the same inputs that each understate a different amount (the fee looks small in both) and combine the two valid
 * signatures (CVE-2020-14199). Ownbit now signs SegWit v0 inputs that come with `witnessUtxo` only (BlueWallet …), with
 * `warn.btcWitnessOnly` — which promises exactly this memory: a later request claiming a **different** amount for a
 * remembered outpoint is a hard refusal (`err.prevoutConflict`).
 *
 * - [conflicts] before the review page offers Sign; [record] when the answer exists (every signed input, any type).
 * - **Both protocols**: the Ownbit protocol's personal BTC transfers (`bb_sign:`, `ColdSigner`) sign
 *   SegWit inputs from amounts the watch wallet claims as well, so they are checked and recorded here too ([Claim]) —
 *   else a compromised hot phone could send one request through each protocol and combine the two signatures. Bitcoin
 *   signing runs one request at a time across both ([signing]: check → sign → record).
 * - Persisted by the [OutpointStore] (in the app a Room table, survives restarts), at most [CAPACITY] outpoints, the last recorded
 *   (in the order of signing, never by the clock — an offline phone's clock may go back; a request that signs more
 *   than [CAPACITY] inputs keeps all of its own); never in
 *   the clear: key = 16 bytes of `SHA-256("ownbit/ovc/v1/key" ‖ txid ‖ u32le(vout))`, tag = 16 bytes of
 *   `SHA-256("ownbit/ovc/v1/amt" ‖ key ‖ u64le(sats))` ([key] / [tag]). Not tied to a wallet (an outpoint is the
 *   coins'). Residual risk: more than [CAPACITY] newer inputs, cleared app data, the same seed on another device.
 *
 * Never logs an outpoint or an amount.
 */
class SignedOutpointMemory(
    private val dao: OutpointStore,
    private val io: CoroutineDispatcher,
) {
    private val writes = Mutex()

    /**
     * Bitcoin signing of both protocols, one request at a time (the public coordinator and `ColdSigner`'s `bb_sign:`
     * BTC transfers): hold it from [conflicts] through the signature to [record], so two requests that claim different
     * amounts for one outpoint can never both pass the check before either is recorded.
     */
    val signing: Mutex = Mutex()

    /**
     * One input as a request states it: the outpoint ([txid] in the transaction's byte order — a PSBT's, or the reversed
     * hex of an explorer / RPC transaction id —, [vout]) and the amount it claims ([sats]).
     */
    class Claim(txid: ByteArray, val vout: Long, val sats: Long) {
        val txid: ByteArray = txid.copyOf()

        init {
            require(txid.size == 32 && vout in 0..0xFFFF_FFFFL && sats >= 0) { "claim" }
        }

        override fun toString(): String = "Claim"
    }

    /**
     * Input indexes of [maps] whose claimed amount differs from the amount this device already signed for the same
     * outpoint (ascending). An input whose outpoint or amount cannot be read counts as a conflict (fail closed; the
     * verifier refuses such a PSBT before this anyway).
     */
    suspend fun conflicts(maps: PsbtMaps): List<Int> = conflicts(maps.inputs.indices.map { i -> claim(maps, i) })

    /**
     * Indexes of [claims] whose amount differs from the amount this device already signed for the same outpoint
     * (ascending); a `null` (unreadable) claim counts as a conflict.
     */
    suspend fun conflicts(claims: List<Claim?>): List<Int> = withContext(io) {
        val entries = claims.mapIndexed { i, c -> i to c?.let(::entry) }
        val unreadable = entries.filter { it.second == null }.map { it.first }
        val known = entries.mapNotNull { (i, e) -> e?.let { i to it } }
        val stored = if (known.isEmpty()) emptyMap() else dao.byKeys(known.map { it.second.key }.distinct()).associate { it.key to it.tag }
        (unreadable + known.filter { (_, e) -> stored[e.key]?.let { it != e.tag } == true }.map { it.first }).sorted()
    }

    /** Remembers the outpoint amounts of [inputs] of [maps] (the inputs this device signed). */
    suspend fun record(maps: PsbtMaps, inputs: Collection<Int>) = record(inputs.distinct().sorted().mapNotNull { i -> claim(maps, i) })

    /** Remembers the outpoint amounts of [claims] (inputs this device signed), in order. */
    suspend fun record(claims: List<Claim>) {
        val rows = claims.map(::entry)
        if (rows.isEmpty()) return
        writes.withLock {
            withContext(io) {
                // The DAO stamps the order (in input order) inside its transaction.
                dao.record(rows.map { OutpointRow(it.key, it.tag, seq = 0) }, CAPACITY)
            }
        }
    }

    private class Entry(val key: String, val tag: String)

    private fun claim(maps: PsbtMaps, index: Int): Claim? {
        val outpoint = maps.outpoint(index) ?: return null
        val amount = maps.claimedAmount(index) ?: return null
        return try {
            Claim(outpoint.txid, outpoint.vout, amount)
        } catch (e: IllegalArgumentException) {
            null
        }
    }

    private fun entry(c: Claim): Entry {
        val k = key(c.txid, c.vout)
        return Entry(Hex.encode(k), Hex.encode(tag(k, c.sats)))
    }

    override fun toString(): String = "SignedOutpointMemory"

    companion object {
        /** Outpoints remembered (Coldcard keeps 128). */
        const val CAPACITY: Int = 256

        private val KEY_DOMAIN = "ownbit/ovc/v1/key".toByteArray(Charsets.US_ASCII)
        private val TAG_DOMAIN = "ownbit/ovc/v1/amt".toByteArray(Charsets.US_ASCII)

        /** The 16-byte key of outpoint ([txid] as stored in the transaction, [vout]). */
        fun key(txid: ByteArray, vout: Long): ByteArray {
            require(txid.size == 32 && vout in 0..0xFFFF_FFFFL) { "outpoint" }
            return Hashes.sha256(KEY_DOMAIN + txid + le(vout, 4)).copyOf(16)
        }

        /** The 16-byte tag of [sats] for [key]. */
        fun tag(key: ByteArray, sats: Long): ByteArray {
            require(key.size == 16 && sats >= 0) { "amount" }
            return Hashes.sha256(TAG_DOMAIN + key + le(sats, 8)).copyOf(16)
        }

        private fun le(value: Long, bytes: Int): ByteArray = ByteArray(bytes) { i -> ((value ushr (8 * i)) and 0xFF).toByte() }
    }
}
