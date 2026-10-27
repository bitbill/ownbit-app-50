// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.wallet.biometric

import io.ownbit.core.crypto.biometric.BiometricCapability
import io.ownbit.core.crypto.biometric.KeySecurityLevel
import io.ownbit.core.crypto.biometric.KeyVerdict
import io.ownbit.core.wallet.WalletResult
import io.ownbit.core.wallet.api.UnlockResult
import io.ownbit.core.wallet.secret.SealedSecrets
import io.ownbit.core.wallet.secret.SecretField
import io.ownbit.core.wallet.testing.FakeBiometricKeyStore
import io.ownbit.core.wallet.testing.FakeCapabilityChecker
import io.ownbit.core.wallet.testing.VaultTestEnv
import io.ownbit.core.wallet.testing.VaultTestEnv.Companion.NEW_PASSWORD
import io.ownbit.core.wallet.testing.VaultTestEnv.Companion.PASSWORD
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.yield
import org.junit.After
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import javax.crypto.Cipher
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.time.Duration.Companion.seconds

/**
 * Quick-send lifecycle with the software Keystore stand-in whose ciphers refuse every operation until a prompt
 * "authenticated" them ([FakeBiometricKeyStore.authenticate]): enable all-or-nothing at each step, auth-per-use,
 * invalidation, stale password, password change / reset / delete, master off, reconcile, eligibility.
 */
@RunWith(RobolectricTestRunner::class)
class BiometricSendVaultTest {

    @get:Rule val tmp = TemporaryFolder()
    private lateinit var env: VaultTestEnv

    @Before fun setUp() {
        FakeBiometricKeyStore.Gate.tokens = 0
        env = VaultTestEnv(tmp.root)
    }

    @After fun tearDown() {
        env.close()
    }

    private suspend fun hotWallet(id: String = "alice01"): String = env.addHotWallet(id)

    private suspend fun masterOn() = assertTrue(env.quickSendRepo.setMaster(true))

    private suspend fun enable(id: String): Boolean {
        val ready = assertIs<EnableStart.Ready>(env.quickSend.beginEnable(id, PASSWORD))
        env.bioKeys.authenticate()
        return env.quickSend.finishEnable(ready.ticket, ready.ticket.cipher)
    }

    private suspend fun unlock(id: String, digest: String = "digest-1"): GrantResult {
        val ready = assertIs<UnlockStart.Ready>(env.quickSend.beginUnlock(id))
        env.bioKeys.authenticate()
        return env.quickSend.completeUnlock(ready.ticket, ready.ticket.cipher, digest)
    }

    private suspend fun record(id: String) = env.quickSendRepo.snapshot().file.record(id)

    @Test fun `enable wraps the wallet password and a later prompt unwraps exactly that password`() = runTest(timeout = 60.seconds) {
        val id = hotWallet()
        masterOn()
        assertTrue(enable(id))
        val rec = assertNotNull(record(id))
        assertTrue(rec.alias.startsWith(BiometricSendVault.ALIAS_PREFIX))
        assertTrue(env.bioKeys.exists(rec.alias))
        assertEquals(KeySecurityLevel.TEE.name, rec.level)
        assertEquals(setOf(id), env.quickSendRepo.settings.value.enabledWalletIds)
        // The stored blob is ciphertext of the password, never the password.
        assertFalse(env.quickSendFile.readBytes().decodeToString().contains(PASSWORD.concatToString()))

        val grant = assertIs<GrantResult.Granted>(unlock(id, "d1")).grant
        assertEquals(id, grant.walletId)
        assertEquals("d1", grant.digest)
        var seen: CharArray? = null
        val out = grant.use { pwd -> seen = pwd; pwd.concatToString() }
        assertEquals(PASSWORD.concatToString(), out)
        assertTrue(seen!!.all { it == '\u0000' }, "wiped after use")
        assertNull(grant.use { "again" }, "single use")
        assertEquals(0, env.attempts.attempts(id))
    }

    @Test fun `nothing is encrypted or decrypted before the prompt authenticated the cipher`() = runTest(timeout = 60.seconds) {
        val id = hotWallet()
        masterOn()
        val ready = assertIs<EnableStart.Ready>(env.quickSend.beginEnable(id, PASSWORD))
        // No prompt: the auth-per-use key refuses, so nothing is stored and the new key is gone.
        assertFalse(env.quickSend.finishEnable(ready.ticket, ready.ticket.cipher))
        assertNull(record(id))
        assertTrue(env.bioKeys.keys.isEmpty())

        assertTrue(enable(id))
        val unlock = assertIs<UnlockStart.Ready>(env.quickSend.beginUnlock(id))
        assertEquals(GrantResult.Failed, env.quickSend.completeUnlock(unlock.ticket, unlock.ticket.cipher, "d"))
        assertNotNull(record(id), "a refused prompt does not turn the wallet off")
    }

    @Test fun `auth-per-use - every unwrap needs its own prompt`() = runTest(timeout = 60.seconds) {
        val id = hotWallet()
        masterOn()
        assertTrue(enable(id))
        val first = assertIs<UnlockStart.Ready>(env.quickSend.beginUnlock(id))
        val second = assertIs<UnlockStart.Ready>(env.quickSend.beginUnlock(id))
        env.bioKeys.authenticate() // one touch
        assertIs<GrantResult.Granted>(env.quickSend.completeUnlock(first.ticket, first.ticket.cipher, "a"))
        assertEquals(GrantResult.Failed, env.quickSend.completeUnlock(second.ticket, second.ticket.cipher, "b"))
        // A ticket is single use, also after success.
        env.bioKeys.authenticate()
        assertEquals(GrantResult.Failed, env.quickSend.completeUnlock(first.ticket, first.ticket.cipher, "a"))
    }

    @Test fun `cancel at the prompt deletes the new key and keeps the switch off`() = runTest(timeout = 60.seconds) {
        val id = hotWallet()
        masterOn()
        val ready = assertIs<EnableStart.Ready>(env.quickSend.beginEnable(id, PASSWORD))
        assertEquals(1, env.bioKeys.keys.size)
        env.quickSend.cancelEnable(ready.ticket)
        assertTrue(env.bioKeys.keys.isEmpty())
        env.bioKeys.authenticate()
        assertFalse(env.quickSend.finishEnable(ready.ticket, ready.ticket.cipher), "a cancelled ticket is dead")
        assertNull(record(id))
        assertTrue(env.quickSendRepo.settings.value.enabledWalletIds.isEmpty())
    }

    @Test fun `finishing with another cipher or a stale ticket fails and deletes the key`() = runTest(timeout = 60.seconds) {
        val id = hotWallet()
        masterOn()
        val ready = assertIs<EnableStart.Ready>(env.quickSend.beginEnable(id, PASSWORD))
        val other = Cipher.getInstance("AES/GCM/NoPadding")
        assertFalse(env.quickSend.finishEnable(ready.ticket, other))
        assertTrue(env.bioKeys.keys.isEmpty())
        assertNull(record(id))

        val late = assertIs<EnableStart.Ready>(env.quickSend.beginEnable(id, PASSWORD))
        env.clocks.advance(BiometricSendVault.TICKET_TTL_MILLIS + 1)
        env.bioKeys.authenticate()
        assertFalse(env.quickSend.finishEnable(late.ticket, late.ticket.cipher))
        assertNull(record(id))
    }

    @Test fun `wrong and empty passwords never create a key and count like every password dialog`() = runTest(timeout = 60.seconds) {
        val id = hotWallet()
        masterOn()
        val wrong = "Wr0ng!pass".toCharArray()
        assertEquals(EnableStart.WrongPassword(false), env.quickSend.beginEnable(id, wrong))
        assertEquals(EnableStart.WrongPassword(false), env.quickSend.beginEnable(id, wrong))
        assertEquals(EnableStart.WrongPassword(true), env.quickSend.beginEnable(id, wrong))
        assertEquals(EnableStart.EmptyPassword, env.quickSend.beginEnable(id, CharArray(0)))
        assertEquals(3, env.attempts.attempts(id))
        assertTrue(env.bioKeys.created.isEmpty())
        assertTrue(enable(id))
        assertEquals(0, env.attempts.attempts(id), "the correct password resets the count")
    }

    @Test fun `device or key not eligible - nothing stored`() = runTest(timeout = 60.seconds) {
        val id = hotWallet()
        masterOn()
        env.bioCapability.status = FakeCapabilityChecker.WEAK_ONLY
        assertEquals(EnableStart.NotEligible(FakeCapabilityChecker.WEAK_ONLY), env.quickSend.beginEnable(id, PASSWORD))
        assertTrue(env.bioKeys.created.isEmpty())
        assertEquals(0, env.attempts.attempts(id), "not even the password is checked")

        env.bioCapability.status = FakeCapabilityChecker.STRONG_HW
        env.bioKeys.verdict = KeyVerdict.Reject("security_level=0")
        val rejected = assertIs<EnableStart.NotEligible>(env.quickSend.beginEnable(id, PASSWORD))
        assertEquals(BiometricCapability.STRONG_NO_HW_KEY, rejected.status.capability)
        assertTrue(env.bioKeys.keys.isEmpty())

        env.bioKeys.verdict = KeyVerdict.Accept(KeySecurityLevel.STRONGBOX)
        env.bioKeys.refuses = false // negative probe: an unauthenticated use went through
        assertIs<EnableStart.NotEligible>(env.quickSend.beginEnable(id, PASSWORD))
        assertTrue(env.bioKeys.keys.isEmpty(), "the key that failed the negative probe is deleted")
        assertNull(record(id))
        assertTrue(env.bioCapability.refreshes >= 2, "the cached capability is re-checked")

        env.bioKeys.refuses = true
        env.bioKeys.failInit = true
        assertEquals(EnableStart.Failed, env.quickSend.beginEnable(id, PASSWORD))
        assertTrue(env.bioKeys.keys.isEmpty())
    }

    @Test fun `only eligible wallets can be turned on`() = runTest(timeout = 60.seconds) {
        masterOn()
        val cold = hotWallet("xcold000001")
        env.makeIneligible(cold)
        assertEquals(EnableStart.Failed, env.quickSend.beginEnable(cold, PASSWORD))
        assertEquals(EnableStart.Failed, env.quickSend.beginEnable("nobody", PASSWORD))
        assertTrue(env.bioKeys.created.isEmpty())
    }

    @Test fun `a record of a wallet that became ineligible (cold) is dropped at the tap and by reconcile`() = runTest(timeout = 60.seconds) {
        val a = hotWallet("alice01")
        val b = hotWallet("bob0001")
        masterOn()
        assertTrue(enable(a))
        assertTrue(enable(b))
        val aliasA = record(a)!!.alias
        val aliasB = record(b)!!.alias
        // Stand-ins for records of wallets that are no longer eligible.
        env.makeIneligible(a)
        env.makeIneligible(b)
        assertEquals(UnlockStart.Off, env.quickSend.beginUnlock(a), "never biometric: the password signs")
        assertNull(record(a))
        assertFalse(env.bioKeys.exists(aliasA))
        assertNull(env.quickSendRepo.consumeNotice(a), "no notice for a wallet that cannot use it")
        assertTrue(env.quickSend.reconcile().isEmpty())
        assertNull(record(b))
        assertFalse(env.bioKeys.exists(aliasB))
        assertTrue(env.quickSendRepo.settings.value.enabledWalletIds.isEmpty())
    }

    @Test fun `turning one wallet off deletes only its key and record`() = runTest(timeout = 60.seconds) {
        val a = hotWallet("alice01")
        val b = hotWallet("bob0001")
        masterOn()
        assertTrue(enable(a))
        assertTrue(enable(b))
        val aliasA = record(a)!!.alias
        val aliasB = record(b)!!.alias
        env.quickSend.disable(a, QuickSendOffReason.USER)
        assertFalse(env.bioKeys.exists(aliasA))
        assertTrue(env.bioKeys.exists(aliasB))
        assertEquals(setOf(b), env.quickSendRepo.settings.value.enabledWalletIds)
        assertEquals(UnlockStart.Off, env.quickSend.beginUnlock(a))
        assertIs<GrantResult.Granted>(unlock(b))
        assertNull(env.quickSend.consumeNotice(a), "a user switch-off leaves no notice")
    }

    @Test fun `master off deletes every wallet's material and on again starts empty`() = runTest(timeout = 60.seconds) {
        val a = hotWallet("alice01")
        val b = hotWallet("bob0001")
        masterOn()
        assertTrue(enable(a))
        assertTrue(enable(b))
        assertTrue(env.quickSendRepo.setMaster(false))
        assertTrue(env.bioKeys.keys.isEmpty())
        assertEquals(QuickSendSettings(masterOn = false), env.quickSendRepo.settings.value)
        assertEquals(UnlockStart.Off, env.quickSend.beginUnlock(a))
        masterOn()
        assertTrue(env.quickSendRepo.settings.value.enabledWalletIds.isEmpty())
    }

    @Test fun `an invalidated or missing key turns the wallet off with a notice`() = runTest(timeout = 60.seconds) {
        val a = hotWallet("alice01")
        val b = hotWallet("bob0001")
        masterOn()
        assertTrue(enable(a))
        assertTrue(enable(b))
        env.bioKeys.invalidate(record(a)!!.alias)
        assertEquals(UnlockStart.TurnedOff(QuickSendOffNotice(a, QuickSendOffReason.INVALIDATED)), env.quickSend.beginUnlock(a))
        assertNull(record(a))
        assertTrue(env.bioKeys.exists(record(b)!!.alias), "the other wallet keeps its key")

        env.bioKeys.wipeAll() // Keystore reset
        assertEquals(UnlockStart.TurnedOff(QuickSendOffNotice(b, QuickSendOffReason.INVALIDATED)), env.quickSend.beginUnlock(b))
        assertTrue(env.quickSendRepo.settings.value.enabledWalletIds.isEmpty())
        assertTrue(env.quickSendRepo.settings.value.masterOn, "only the wallets go off")
    }

    @Test fun `a replaced key (bad tag) turns the wallet off`() = runTest(timeout = 60.seconds) {
        val id = hotWallet()
        masterOn()
        assertTrue(enable(id))
        env.bioKeys.keys[record(id)!!.alias] = ByteArray(32) { 7 }
        assertEquals(GrantResult.TurnedOff(QuickSendOffNotice(id, QuickSendOffReason.INVALIDATED)), unlock(id))
        assertNull(record(id))
    }

    @Test fun `a transient Keystore failure keeps quick send on`() = runTest(timeout = 60.seconds) {
        val id = hotWallet()
        masterOn()
        assertTrue(enable(id))
        env.bioKeys.failInit = true
        assertEquals(UnlockStart.Failed, env.quickSend.beginUnlock(id))
        assertNotNull(record(id))
    }

    @Test fun `password change turns quick send off and the next send shows the notice once`() = runTest(timeout = 60.seconds) {
        val id = hotWallet()
        masterOn()
        assertTrue(enable(id))
        val alias = record(id)!!.alias
        assertIs<WalletResult.Ok<Unit>>(env.passwordChanger.change(id, PASSWORD, NEW_PASSWORD, NEW_PASSWORD))
        assertNull(record(id))
        assertFalse(env.bioKeys.exists(alias))

        val request = AuthorizationRequest(id, TxKind.PERSONAL_SEND, emptyList(), "d")
        assertEquals(
            TxAuthStart.Password(QuickSendOffNotice(id, QuickSendOffReason.PASSWORD_CHANGED)),
            env.authorizer.start(request),
        )
        assertEquals(TxAuthStart.Password(null), env.authorizer.start(request), "shown once")
    }

    @Test fun `a wrapped password that no longer opens the wallet turns it off without counting an attempt`() = runTest(timeout = 60.seconds) {
        val id = hotWallet()
        masterOn()
        assertTrue(enable(id))
        // The password changed behind the vault's back (backstop): reseal with the new password.
        val resealed = env.secretAccess.withUnlocked(id, PASSWORD) { s ->
            env.sealer.reseal(id, mapOf(SecretField.MNEMONIC to s.mnemonic!!, SecretField.SEED to s.seedHex!!), NEW_PASSWORD, 2L)
        }
        env.store.replaceEnvelopes(assertNotNull(assertIs<UnlockResult.Success<SealedSecrets?>>(resealed).value))
        assertEquals(GrantResult.TurnedOff(QuickSendOffNotice(id, QuickSendOffReason.PASSWORD_CHANGED)), unlock(id))
        assertNull(record(id))
        assertEquals(0, env.attempts.attempts(id))
    }

    @Test fun `reconcile deletes orphan keys, drops vanished wallets and reports invalidated keys`() = runTest(timeout = 60.seconds) {
        val a = hotWallet("alice01")
        val b = hotWallet("bob0001")
        val c = hotWallet("carol01")
        masterOn()
        assertTrue(enable(a))
        assertTrue(enable(b))
        assertTrue(enable(c))
        env.bioKeys.create(BiometricSendVault.ALIAS_PREFIX + "orphan")
        env.bioKeys.create("someone_else_key")
        env.removeWallet(b) // gone without turning quick send off first
        env.bioKeys.invalidate(record(c)!!.alias)

        val notices = env.quickSend.reconcile()
        assertEquals(listOf(QuickSendOffNotice(c, QuickSendOffReason.INVALIDATED)), notices)
        assertEquals(setOf(a), env.quickSendRepo.settings.value.enabledWalletIds)
        assertEquals(setOf(record(a)!!.alias, "someone_else_key"), env.bioKeys.keys.keys.toSet())
        assertNull(env.quickSend.consumeNotice(c), "reported by reconcile, not again at the next send")
    }

    @Test fun `reconcile during an enable in progress keeps its key, an abandoned enable's key is swept`() = runTest(timeout = 60.seconds) {
        val id = hotWallet()
        masterOn()
        val live = assertIs<EnableStart.Ready>(env.quickSend.beginEnable(id, PASSWORD))
        val liveAlias = env.bioKeys.created.last()
        assertTrue(env.quickSend.reconcile().isEmpty())
        assertTrue(env.bioKeys.exists(liveAlias), "the in-flight key survives the orphan sweep")
        env.bioKeys.authenticate()
        assertTrue(env.quickSend.finishEnable(live.ticket, live.ticket.cipher))
        assertEquals(liveAlias, record(id)!!.alias)

        val abandoned = assertIs<EnableStart.Ready>(env.quickSend.beginEnable(id, PASSWORD))
        val abandonedAlias = env.bioKeys.created.last()
        env.clocks.advance(BiometricSendVault.TICKET_TTL_MILLIS + 1)
        env.quickSend.reconcile()
        assertFalse(env.bioKeys.exists(abandonedAlias), "older than the ticket TTL: swept")
        assertTrue(env.bioKeys.exists(liveAlias), "the stored wallet key stays")
        env.bioKeys.authenticate()
        assertFalse(env.quickSend.finishEnable(abandoned.ticket, abandoned.ticket.cipher))
        assertEquals(liveAlias, record(id)!!.alias)
    }

    @Test fun `an enable that finishes while reconcile sweeps keeps its new key`() = runTest(timeout = 60.seconds) {
        val id = hotWallet()
        masterOn()
        val ready = assertIs<EnableStart.Ready>(env.quickSend.beginEnable(id, PASSWORD))
        val alias = env.bioKeys.created.last()
        // The prompt's answer arrives while the Security page's reconcile runs (e.g. ON_RESUME after the prompt): the
        // whole finishEnable happens right after reconcile listed the keys (the new one still in flight then).
        env.bioKeys.afterAliasesListed = {
            env.bioKeys.authenticate()
            assertTrue(runBlocking { env.quickSend.finishEnable(ready.ticket, ready.ticket.cipher) })
        }
        assertTrue(env.quickSend.reconcile().isEmpty())
        assertEquals(alias, record(id)?.alias)
        assertTrue(env.bioKeys.exists(alias), "the key of the record just stored is not an orphan")
        assertIs<GrantResult.Granted>(unlock(id))
    }

    @Test fun `disableAll during an enable in progress makes it fail`() = runTest(timeout = 60.seconds) {
        val id = hotWallet()
        masterOn()
        val ready = assertIs<EnableStart.Ready>(env.quickSend.beginEnable(id, PASSWORD))
        env.quickSend.disableAll(QuickSendOffReason.USER)
        env.bioKeys.authenticate()
        assertFalse(env.quickSend.finishEnable(ready.ticket, ready.ticket.cipher))
        assertNull(record(id))
        assertTrue(env.bioKeys.keys.isEmpty())
    }

    @Test fun `re-enabling replaces the old key only once the new one is stored`() = runTest(timeout = 60.seconds) {
        val id = hotWallet()
        masterOn()
        assertTrue(enable(id))
        val first = record(id)!!.alias
        val retry = assertIs<EnableStart.Ready>(env.quickSend.beginEnable(id, PASSWORD))
        env.quickSend.cancelEnable(retry.ticket)
        assertEquals(first, record(id)!!.alias, "a cancelled re-enable keeps the working key")
        assertTrue(env.bioKeys.exists(first))
        assertTrue(enable(id))
        assertFalse(env.bioKeys.exists(first))
        assertIs<GrantResult.Granted>(unlock(id))
    }

    @Test fun `wallets can only be turned on under the master switch`() = runTest(timeout = 60.seconds) {
        val id = hotWallet()
        assertEquals(EnableStart.Failed, env.quickSend.beginEnable(id, PASSWORD))
        assertTrue(env.bioKeys.created.isEmpty())
        masterOn()
        val ready = assertIs<EnableStart.Ready>(env.quickSend.beginEnable(id, PASSWORD))
        assertTrue(env.quickSendRepo.setMaster(false)) // switched off while the prompt is open
        env.bioKeys.authenticate()
        assertFalse(env.quickSend.finishEnable(ready.ticket, ready.ticket.cipher))
        assertTrue(env.bioKeys.keys.isEmpty())
        assertNull(record(id))
    }

    @Test fun `going to the background wipes the password of an enable in progress - it can no longer finish`() = runTest(timeout = 60.seconds) {
        val id = hotWallet()
        masterOn()
        val ready = assertIs<EnableStart.Ready>(env.quickSend.beginEnable(id, PASSWORD))
        assertFalse(ready.ticket.isWiped)
        assertEquals(1, env.grants.pendingTicketCount)
        env.foreground.value = false
        withTimeout(5_000) { while (!ready.ticket.isWiped) yield() }
        assertEquals(0, env.grants.pendingTicketCount)
        env.foreground.value = true
        env.bioKeys.authenticate()
        assertFalse(env.quickSend.finishEnable(ready.ticket, ready.ticket.cipher))
        assertTrue(env.bioKeys.keys.isEmpty(), "the voided enable's key is deleted")
        assertNull(record(id))
    }

    @Test fun `a ticket whose password is gone fails cleanly and deletes its key`() = runTest(timeout = 60.seconds) {
        val id = hotWallet()
        masterOn()
        val ready = assertIs<EnableStart.Ready>(env.quickSend.beginEnable(id, PASSWORD))
        ready.ticket.wipe() // e.g. the TTL timer
        env.bioKeys.authenticate()
        assertFalse(env.quickSend.finishEnable(ready.ticket, ready.ticket.cipher))
        assertTrue(env.bioKeys.keys.isEmpty())
        assertNull(record(id))
    }

    @Test fun `a ticket older than the TTL at use is refused, wiped and its key deleted`() = runTest(timeout = 60.seconds) {
        val id = hotWallet()
        masterOn()
        val ready = assertIs<EnableStart.Ready>(env.quickSend.beginEnable(id, PASSWORD))
        env.clocks.advance(BiometricSendVault.TICKET_TTL_MILLIS + 1)
        env.bioKeys.authenticate()
        assertFalse(env.quickSend.finishEnable(ready.ticket, ready.ticket.cipher))
        assertTrue(ready.ticket.isWiped)
        assertTrue(env.bioKeys.keys.isEmpty())
        assertEquals(0, env.grants.pendingTicketCount)
        // Finished and cancelled tickets are untracked as well.
        val cancelled = assertIs<EnableStart.Ready>(env.quickSend.beginEnable(id, PASSWORD))
        env.quickSend.cancelEnable(cancelled.ticket)
        assertTrue(cancelled.ticket.isWiped)
        assertEquals(0, env.grants.pendingTicketCount)
    }

    @Test fun `disableAll keeps the master switch and deletes every key`() = runTest(timeout = 60.seconds) {
        val a = hotWallet("alice01")
        masterOn()
        assertTrue(enable(a))
        env.quickSend.disableAll(QuickSendOffReason.USER)
        assertTrue(env.bioKeys.keys.isEmpty())
        assertEquals(QuickSendSettings(masterOn = true), env.quickSendRepo.settings.value)
    }
}
