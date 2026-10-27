// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.publicsigner.sign


/**
 * the request hashes this process answered, newest last, at most [CAPACITY] (least recently signed dropped).
 * The review page shows "You already signed this exact request (HH:mm)" for a hash in here; signing again still
 * needs a new scan and a new password. Memory only — never stored, gone with the process.
 */
class RecentRequestHashes() {

    private val signed = LinkedHashMap<String, Long>()

    /** Records that the request [requestHash] was answered at [atMillis]. */
    @Synchronized
    fun record(requestHash: String, atMillis: Long) {
        val key = requestHash.lowercase()
        signed.remove(key)
        signed[key] = atMillis
        while (signed.size > CAPACITY) signed.remove(signed.keys.first())
    }

    /** When [requestHash] was last answered, or `null`. */
    @Synchronized
    fun signedAt(requestHash: String): Long? = signed[requestHash.lowercase()]

    @Synchronized
    fun size(): Int = signed.size

    companion object {
        const val CAPACITY: Int = 16
    }
}
