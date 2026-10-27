// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.wallet.biometric

import io.ownbit.core.crypto.util.MonotonicClock
import io.ownbit.core.crypto.util.wipe
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import java.util.Collections
import java.util.concurrent.ConcurrentHashMap

/**
 * The wallet password unwrapped by one crypto-bound biometric prompt, bound to [walletId] and the [digest] of the
 * content the user confirmed. **Single use**, valid for [BiometricGrant.TTL_MILLIS] (monotonic clock), wiped when the
 * app goes to the background or it expires; never stored, never logged ([toString] is redacted).
 *
 * The only way to the password is [use], straight into the existing signing call (`withUnlocked` path). Re-check the
 * policy right before (`WalletAuthorizationPolicy.recheck`).
 */
class BiometricGrant internal constructor(
    val walletId: String,
    val digest: String,
    password: CharArray,
    private val deadline: Long,
    private val clock: MonotonicClock,
    private val onDone: (BiometricGrant) -> Unit = {},
) {
    private val lock = Any()
    private var chars: CharArray? = password
    private var used = false
    private var inUse = false

    /** Not used, not wiped, not expired. */
    fun isUsable(): Boolean = synchronized(lock) { chars != null && !used && clock.elapsedMillis() < deadline }

    /**
     * Runs [block] with the password once and wipes it afterwards (also when [block] throws). `null` without running
     * [block] when the grant was used, wiped or expired. The caller must not keep the array or a copy.
     */
    suspend fun <T> use(block: suspend (CharArray) -> T): T? {
        val password = synchronized(lock) {
            val current = chars
            if (current == null || used || clock.elapsedMillis() >= deadline) {
                wipeLocked()
                null
            } else {
                used = true
                inUse = true
                current
            }
        } ?: return null
        return try {
            block(password)
        } finally {
            synchronized(lock) {
                password.wipe()
                chars = null
                inUse = false
            }
            onDone(this)
        }
    }

    /**
     * Wipes the password (cancel, background, timeout, content changed). A [use] already running keeps its array until
     * it returns and wipes it then.
     */
    fun wipe() {
        val done = synchronized(lock) {
            used = true
            if (!inUse) wipeLocked()
            !inUse
        }
        if (done) onDone(this)
    }

    private fun wipeLocked() {
        chars?.wipe()
        chars = null
        used = true
    }

    override fun toString(): String = "BiometricGrant(walletId=$walletId, <redacted>)"

    companion object {
        /** A grant is usable for at most this long after the prompt. */
        const val TTL_MILLIS: Long = 60_000L
    }
}

/**
 * Issues [BiometricGrant]s and wipes every live one when the process goes to the background (a `true` → `false`
 * transition of `isForeground`, e.g. driven by `ProcessLifecycleOwner`) or when its time is up. Also holds the pending
 * [EnableTicket]s (their password copy while the enable prompt is open) under the same two rules ([trackEnable]): a
 * wiped ticket can no longer finish.
 */
class GrantRegistry(
    private val clock: MonotonicClock,
    private val scope: CoroutineScope,
    isForeground: StateFlow<Boolean>?,
) {

    private val live: MutableSet<BiometricGrant> = Collections.newSetFromMap(ConcurrentHashMap())
    private val tickets: MutableSet<EnableTicket> = Collections.newSetFromMap(ConcurrentHashMap())

    init {
        if (isForeground != null) {
            scope.launch {
                var wasForeground = isForeground.value
                isForeground.collect { now ->
                    if (wasForeground && !now) wipeAll()
                    wasForeground = now
                }
            }
        }
    }

    fun issue(walletId: String, digest: String, password: CharArray): BiometricGrant {
        val grant = BiometricGrant(
            walletId = walletId,
            digest = digest,
            password = password,
            deadline = clock.elapsedMillis() + BiometricGrant.TTL_MILLIS,
            clock = clock,
            onDone = { live.remove(it) },
        )
        live += grant
        scope.launch {
            delay(BiometricGrant.TTL_MILLIS)
            grant.wipe()
        }
        return grant
    }

    /**
     * Keeps [ticket] until [untrack]: its password copy is wiped when the app goes to the background or after
     * [ttlMillis], whichever comes first (the vault then refuses to finish it and deletes its key).
     */
    fun trackEnable(ticket: EnableTicket, ttlMillis: Long) {
        tickets += ticket
        scope.launch {
            delay(ttlMillis)
            ticket.wipe()
            tickets.remove(ticket)
        }
    }

    /** [ticket] finished or was cancelled (it wipes itself). */
    fun untrack(ticket: EnableTicket) {
        tickets.remove(ticket)
    }

    /** Wipes every live grant and every pending enable ticket's password (background; also tests). */
    fun wipeAll() {
        live.toList().forEach { it.wipe() }
        tickets.toList().forEach {
            it.wipe()
            tickets.remove(it)
        }
    }

    /** Live (not yet wiped) grants — tests. */
    val liveCount: Int get() = live.size

    /** Tracked pending enable tickets — tests. */
    val pendingTicketCount: Int get() = tickets.size
}
