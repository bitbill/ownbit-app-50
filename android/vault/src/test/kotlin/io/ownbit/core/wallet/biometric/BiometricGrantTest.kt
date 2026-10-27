// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.wallet.biometric

import io.ownbit.core.wallet.testing.TestClocks
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.yield
import io.ownbit.core.crypto.biometric.KeySecurityLevel
import org.junit.After
import javax.crypto.Cipher
import org.junit.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Single use, 60 s on the monotonic clock, wiped on background / timeout, never printed. */
class BiometricGrantTest {

    private val clocks = TestClocks()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val foreground = MutableStateFlow(true)
    private val registry = GrantRegistry(clocks, scope, foreground)

    @After fun tearDown() = scope.cancel()

    private fun pwd() = "Passw0rd!x".toCharArray()

    @Test fun `single use and wiped afterwards, also when the block throws`() = runTest {
        val source = pwd()
        val grant = registry.issue("w1", "d", source)
        assertTrue(grant.isUsable())
        assertEquals("Passw0rd!x", grant.use { it.concatToString() })
        assertTrue(source.all { it == '\u0000' })
        assertFalse(grant.isUsable())
        assertNull(grant.use { "again" })

        val other = pwd()
        val throwing = registry.issue("w1", "d", other)
        runCatching { throwing.use { error("boom") } }
        assertTrue(other.all { it == '\u0000' })
        assertNull(throwing.use { "x" })
    }

    @Test fun `expires after 60 seconds of monotonic time`() = runTest {
        val source = pwd()
        val grant = registry.issue("w1", "d", source)
        clocks.advance(BiometricGrant.TTL_MILLIS - 1)
        assertTrue(grant.isUsable())
        clocks.advance(1)
        assertFalse(grant.isUsable())
        assertNull(grant.use { "late" })
        assertTrue(source.all { it == '\u0000' }, "an expired grant is wiped on access")
    }

    @Test fun `going to the background wipes every live grant`() = runTest {
        val a = pwd()
        val b = pwd()
        val ga = registry.issue("w1", "d", a)
        val gb = registry.issue("w2", "e", b)
        assertEquals(2, registry.liveCount)
        foreground.value = false
        withTimeout(5_000) { while (registry.liveCount > 0) yield() }
        assertFalse(ga.isUsable())
        assertFalse(gb.isUsable())
        assertTrue(a.all { it == '\u0000' } && b.all { it == '\u0000' })
        foreground.value = true
        assertTrue(registry.issue("w1", "d", pwd()).isUsable(), "new grants work again in the foreground")
    }

    @Test fun `a wipe during use leaves the running block its password and wipes it at the end`() = runTest {
        val source = pwd()
        val grant = registry.issue("w1", "d", source)
        val seen = grant.use { p ->
            grant.wipe()
            p.concatToString()
        }
        assertEquals("Passw0rd!x", seen)
        assertTrue(source.all { it == '\u0000' })
        assertFalse(grant.isUsable())
    }

    @Test fun `a pending enable ticket is wiped after its TTL and on background`() = runTest {
        val timed = GrantRegistry(clocks, backgroundScope, null)
        val ticket = ticket()
        timed.trackEnable(ticket, ttlMillis = 1_000L)
        advanceTimeBy(999L)
        runCurrent()
        assertFalse(ticket.isWiped)
        advanceTimeBy(2L)
        runCurrent()
        assertTrue(ticket.isWiped)
        assertEquals(0, timed.pendingTicketCount)

        val other = ticket()
        registry.trackEnable(other, ttlMillis = BiometricSendVault.TICKET_TTL_MILLIS)
        foreground.value = false
        withTimeout(5_000) { while (registry.pendingTicketCount > 0) yield() }
        assertTrue(other.isWiped)
    }

    private fun ticket() = EnableTicket(
        "w1", BiometricSendVault.ALIAS_PREFIX + "t", pwd(), Cipher.getInstance("AES/GCM/NoPadding"), KeySecurityLevel.TEE, 0L,
    )

    @Test fun `toString never shows the password`() {
        val grant = registry.issue("w1", "d", pwd())
        assertFalse(grant.toString().contains("Passw0rd"))
        grant.wipe()
        assertEquals(0, registry.liveCount)
    }
}
