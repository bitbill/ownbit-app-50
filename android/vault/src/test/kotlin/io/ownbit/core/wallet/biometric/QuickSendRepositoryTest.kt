// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.wallet.biometric

import io.ownbit.core.wallet.testing.FakeBiometricKeyStore
import io.ownbit.core.wallet.testing.TestRecordCipher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Settings file: defaults OFF, persistence, iOS threshold options, fail-closed corruption, notices. */
class QuickSendRepositoryTest {

    @get:Rule val tmp = TemporaryFolder()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val keys = FakeBiometricKeyStore()
    private val cipher = TestRecordCipher()
    private val file get() = File(tmp.root, "biometric/quick_send.enc")

    private fun repo(c: TestRecordCipher = cipher) = QuickSendRepository(file, c, keys, Dispatchers.IO, scope)


    @After fun tearDown() {
        scope.cancel()
    }

    private fun record(id: String, alias: String = BiometricSendVault.ALIAS_PREFIX + id) =
        QuickSendRecord(id, alias, "000102030405060708090a0b", "00".repeat(20), "TEE", 1L)

    @Test fun `everything is off by default and the 14 iOS options are offered`() = runTest {
        val r = repo()
        assertEquals(QuickSendSettings(masterOn = false, thresholdUsd = 1_000L, enabledWalletIds = emptySet()), r.snapshot().settings)
        assertEquals(QuickSendSettings(), r.settings.value)
        assertEquals(
            listOf(0L, 100L, 200L, 500L, 1_000L, 2_000L, 5_000L, 10_000L, 20_000L, 50_000L, 100_000L, 200_000L, 500_000L, 1_000_000L),
            QuickSendThresholds.OPTIONS_USD,
        )
        assertFalse(file.exists(), "nothing written until something changes")
    }

    @Test fun `settings persist across a restart and only option values are accepted`() = runTest {
        val r = repo()
        assertTrue(r.setMaster(true))
        assertTrue(r.setThresholdUsd(5_000L))
        assertFalse(r.setThresholdUsd(1_234L))
        assertFalse(r.setThresholdUsd(-1L))
        assertTrue(r.putRecord(record("w1")).written)
        val again = repo()
        assertEquals(QuickSendSettings(true, 5_000L, setOf("w1")), again.snapshot().settings)
        // Unchanged values log nothing.
        assertTrue(again.setMaster(true))
        assertTrue(again.setThresholdUsd(5_000L))
        assertFalse(file.readBytes().decodeToString().contains("w1"), "the file is encrypted")
    }

    @Test fun `master off removes every record and deletes their keys`() = runTest {
        val r = repo()
        assertTrue(r.setMaster(true))
        keys.create(BiometricSendVault.ALIAS_PREFIX + "w1")
        keys.create(BiometricSendVault.ALIAS_PREFIX + "w2")
        r.putRecord(record("w1"))
        r.putRecord(record("w2"))
        assertTrue(r.setMaster(false))
        assertTrue(keys.keys.isEmpty())
        assertEquals(QuickSendSettings(), r.snapshot().settings)
    }

    @Test fun `a failed write changes nothing`() = runTest {
        val failing = TestRecordCipher().apply { failWrites = true }
        val r = repo(failing)
        assertFalse(r.setMaster(true))
        assertEquals(QuickSendSettings(), r.settings.value)
    }

    @Test fun `an unreadable file reads as all off and the next write starts over with a new record key`() = runTest {
        val r = repo()
        assertTrue(r.setMaster(true))
        r.putRecord(record("w1"))
        val lost = TestRecordCipher().apply { broken = true }
        val restarted = repo(lost)
        val snap = restarted.snapshot()
        assertTrue(snap.corrupt)
        assertEquals(QuickSendSettings(), snap.settings)
        assertTrue(restarted.setMaster(true))
        assertEquals(1, lost.keyDeletes)
        assertEquals(QuickSendSettings(masterOn = true), restarted.snapshot().settings)
        assertFalse(restarted.snapshot().corrupt)
    }

    @Test fun `garbage bytes are corrupt, not a crash`() = runTest {
        file.parentFile!!.mkdirs()
        file.writeBytes(ByteArray(40) { 3 })
        val r = repo()
        assertTrue(r.snapshot().corrupt)
        assertEquals(QuickSendSettings(), r.settings.value)
    }

    @Test fun `notices are kept only while the master switch is on and are consumed once`() = runTest {
        val r = repo()
        assertFalse(r.putRecord(record("w1")).written, "no wallet record without the master switch")
        r.removeRecord("w1", QuickSendOffReason.PASSWORD_CHANGED)
        assertNull(r.consumeNotice("w1"), "master off: no notice")
        assertTrue(r.setMaster(true))
        r.putRecord(record("w1"))
        r.removeRecord("w1", QuickSendOffReason.PASSWORD_CHANGED)
        assertEquals(QuickSendOffNotice("w1", QuickSendOffReason.PASSWORD_CHANGED), repo().consumeNotice("w1"), "persisted")
        val r2 = repo()
        assertNull(r2.consumeNotice("w1"))
        // Re-enabling clears a pending notice.
        r2.putRecord(record("w2"))
        r2.removeRecord("w2", QuickSendOffReason.INVALIDATED)
        r2.putRecord(record("w2"))
        assertNull(r2.consumeNotice("w2"))
    }

    @Test fun `putRecord reports the replaced alias`() = runTest {
        val r = repo()
        assertTrue(r.setMaster(true))
        assertNull(r.putRecord(record("w1", "a1")).replacedAlias)
        assertEquals("a1", r.putRecord(record("w1", "a2")).replacedAlias)
        assertEquals(listOf("a2"), r.snapshot().file.wallets.map { it.alias })
    }
}
