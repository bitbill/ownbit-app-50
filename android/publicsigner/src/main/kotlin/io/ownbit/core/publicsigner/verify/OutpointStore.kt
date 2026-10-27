// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.publicsigner.verify

import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.util.concurrent.ConcurrentHashMap

/**
 * One remembered outpoint of [SignedOutpointMemory]: [key] = hashed outpoint, [tag] = hashed amount (both lower-case
 * hex, never in the clear), [seq] = the order it was (last) recorded in — never a clock (an offline phone's clock may
 * go back).
 */
data class OutpointRow(val key: String, val tag: String, val seq: Long)

/**
 * Storage of [SignedOutpointMemory] (a stub interface: the app keeps the rows in a Room table, not part of this
 * repository). Deliberately not tied to a wallet: an outpoint belongs to the coins.
 */
interface OutpointStore {
    /** The rows of [keys] (those remembered). */
    suspend fun byKeys(keys: List<String>): List<OutpointRow>

    /**
     * Records [rows] atomically as the newest, in list order (their own [OutpointRow.seq] is replaced by the next
     * counter values; a remembered key is refreshed), then keeps the [capacity] newest rows — but never fewer than
     * [rows]: one request that signs more inputs than [capacity] keeps all of its own.
     */
    suspend fun record(rows: List<OutpointRow>, capacity: Int)

    /** Rows stored (tests, diagnostics). */
    suspend fun count(): Int
}

/** [OutpointStore] in memory (tests, or a host that keeps the memory only for the process lifetime). */
class InMemoryOutpointStore : OutpointStore {
    private val rows = ConcurrentHashMap<String, OutpointRow>()
    private val lock = Mutex()

    override suspend fun byKeys(keys: List<String>): List<OutpointRow> = keys.mapNotNull { rows[it] }

    override suspend fun record(rows: List<OutpointRow>, capacity: Int) = lock.withLock {
        if (rows.isEmpty()) return@withLock
        val base = this.rows.values.maxOfOrNull { it.seq } ?: 0L
        rows.forEachIndexed { i, row -> this.rows[row.key] = row.copy(seq = base + 1 + i) }
        val keep = maxOf(capacity, rows.distinctBy { it.key }.size)
        val newest = this.rows.values.sortedWith(compareByDescending<OutpointRow> { it.seq }.thenByDescending { it.key }).take(keep)
        this.rows.keys.retainAll(newest.map { it.key }.toSet())
    }

    override suspend fun count(): Int = rows.size
}
