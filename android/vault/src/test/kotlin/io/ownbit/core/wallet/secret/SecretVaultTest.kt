// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.wallet.secret

import io.ownbit.core.crypto.obv2.Obv2Envelope
import io.ownbit.core.wallet.WalletError
import io.ownbit.core.wallet.WalletResult
import io.ownbit.core.wallet.api.UnlockResult
import io.ownbit.core.wallet.api.UnlockedSecrets
import io.ownbit.core.wallet.testing.VaultTestEnv
import io.ownbit.core.wallet.testing.VaultTestEnv.Companion.MNEMONIC
import io.ownbit.core.wallet.testing.VaultTestEnv.Companion.NEW_PASSWORD
import io.ownbit.core.wallet.testing.VaultTestEnv.Companion.PASSWORD
import io.ownbit.core.wallet.testing.VaultTestEnv.Companion.SEED_HEX
import io.ownbit.core.wallet.testing.VaultTestEnv.Companion.SEED_HEX_TREZOR
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.time.Duration.Companion.seconds

/**
 * The wallet secret vault over OBV2 envelopes: what signing may open, the integrity-hash gate, the passphrase rule,
 * attempt counting, wiping, a lost device key, and the all-or-nothing password change.
 */
class SecretVaultTest {

    @get:Rule val tmp = TemporaryFolder()
    private val env by lazy { VaultTestEnv(tmp.root) }

    @After fun tearDown() = env.close()

    @Test fun `every secret is stored only as a device-bound OBV2 envelope`() = runTest(timeout = 60.seconds) {
        val id = env.addHotWallet("alice01")
        val row = env.store.rows.getValue(id)
        for (envelope in listOf(row.encryptedMnemonic!!, row.encryptedSeed!!)) {
            assertTrue(Obv2Envelope.isObv2(envelope))
            assertFalse(envelope.contains("abandon"))
            assertEquals(io.ownbit.core.crypto.obv2.Obv2Binding.DEVICE, Obv2Envelope.header(envelope)!!.binding)
        }
        assertNull(row.encryptedPassphrase)
    }

    @Test fun `withUnlocked opens mnemonic and seed, never the passphrase, and wipes them after the block`() = runTest(timeout = 60.seconds) {
        val id = env.addHotWallet("alice01", passphrase = "TREZOR".toCharArray())
        var seen: UnlockedSecrets? = null
        val result = env.secretAccess.withUnlocked(id, PASSWORD) { s ->
            seen = s
            assertEquals(MNEMONIC, String(s.mnemonic!!))
            assertEquals(SEED_HEX_TREZOR, String(s.seedHex!!))
            assertNull(s.passphrase, "signing never gets the passphrase: the seed already includes it")
            "signed"
        }
        assertEquals(UnlockResult.Success("signed"), result)
        assertTrue(seen!!.mnemonic!!.all { it == '\u0000' } && seen!!.seedHex!!.all { it == '\u0000' }, "wiped")
    }

    @Test fun `the passphrase opens only together with the mnemonic`() = runTest(timeout = 60.seconds) {
        val id = env.addHotWallet("alice01", passphrase = "TREZOR".toCharArray())
        assertFailsWith<IllegalArgumentException> { env.vault.open(id, PASSWORD, setOf(SecretField.PASSPHRASE)) }
        val opened = assertIs<SecretVault.Opened.Ok>(env.vault.open(id, PASSWORD, setOf(SecretField.MNEMONIC, SecretField.PASSPHRASE)))
        assertEquals("TREZOR", String(opened.secrets.passphrase!!))
        opened.secrets.wipe()
    }

    @Test fun `wrong passwords are counted, the empty one is not, and a correct one resets the count`() = runTest(timeout = 60.seconds) {
        val id = env.addHotWallet("alice01")
        val verifier = WalletPasswordVerifier(env.vault)
        assertEquals(WalletResult.Err(WalletError.WrongPassword(1, false)), verifier.verify(id, "nope".toCharArray()))
        assertEquals(WalletResult.Err(WalletError.WrongPassword(2, false)), verifier.verify(id, "nope".toCharArray()))
        assertEquals(WalletResult.Err(WalletError.EmptyPassword), verifier.verify(id, CharArray(0)))
        assertEquals(WalletResult.Err(WalletError.WrongPassword(3, true)), verifier.verify(id, "nope".toCharArray()), "re-import hint")
        assertEquals(WalletResult.Ok(Unit), verifier.verify(id, PASSWORD))
        assertEquals(0, env.attempts.attempts(id))
        assertTrue(env.secretAccess.verifyPassword(id, PASSWORD))
        assertFalse(env.secretAccess.verifyPassword(id, NEW_PASSWORD))
        assertEquals(UnlockResult.WrongPassword, env.secretAccess.withUnlocked(id, NEW_PASSWORD) { })
    }

    @Test fun `a plaintext that does not match its stored hash is refused`() = runTest(timeout = 60.seconds) {
        val id = env.addHotWallet("alice01")
        val row = env.store.rows.getValue(id)
        env.store.rows[id] = StoredWalletSecrets(
            walletId = id,
            encryptedMnemonic = row.encryptedMnemonic,
            encryptedSeed = row.encryptedSeed,
            mnemonicHash = row.mnemonicHash,
            seedHash = "00".repeat(32),
        )
        val result = env.secretAccess.withUnlocked(id, PASSWORD) { "never" }
        assertIs<UnlockResult.Failed>(result)
        assertEquals(0, env.attempts.attempts(id), "not a password problem")
    }

    @Test fun `watch wallets have no secret and a lost device key is not a wrong password`() = runTest(timeout = 60.seconds) {
        env.store.rows["watch01"] = StoredWalletSecrets("watch01")
        assertEquals(UnlockResult.NoSecret, env.secretAccess.withUnlocked("watch01", PASSWORD) { })
        assertNull(env.vault.verificationField("watch01"))

        val id = env.addHotWallet("alice01")
        env.deviceKeys.rawKey = null // app data restored onto another phone: the Keystore key did not come along
        val verifier = WalletPasswordVerifier(env.vault)
        assertIs<WalletError.SecretUnavailable>((verifier.verify(id, PASSWORD) as WalletResult.Err).error)
        assertEquals(0, env.attempts.attempts(id))
    }

    @Test fun `password change re-seals every envelope, keeps the hashes and turns quick send off`() = runTest(timeout = 60.seconds) {
        val id = env.addHotWallet("alice01", passphrase = "TREZOR".toCharArray())
        val before = env.store.rows.getValue(id)
        assertEquals(WalletResult.Ok(Unit), env.passwordChanger.change(id, PASSWORD, NEW_PASSWORD, NEW_PASSWORD))
        val after = env.store.rows.getValue(id)
        assertTrue(after.encryptedMnemonic != before.encryptedMnemonic && after.encryptedSeed != before.encryptedSeed)
        assertNotNull(after.encryptedPassphrase, "the passphrase envelope moves along")
        assertEquals(before.mnemonicHash, after.mnemonicHash)
        assertFalse(env.secretAccess.verifyPassword(id, PASSWORD))
        val opened = assertIs<SecretVault.Opened.Ok>(
            env.vault.open(id, NEW_PASSWORD, setOf(SecretField.MNEMONIC, SecretField.SEED, SecretField.PASSPHRASE)),
        )
        assertEquals(SEED_HEX_TREZOR, String(opened.secrets.seedHex!!))
        assertEquals("TREZOR", String(opened.secrets.passphrase!!))
        opened.secrets.wipe()
    }

    @Test fun `password change checks its inputs and is all or nothing`() = runTest(timeout = 60.seconds) {
        val id = env.addHotWallet("alice01")
        val changer = env.passwordChanger
        assertEquals(WalletResult.Err(WalletError.EmptyPassword), changer.change(id, CharArray(0), NEW_PASSWORD, NEW_PASSWORD))
        assertEquals(WalletResult.Err(WalletError.PasswordMismatch), changer.change(id, PASSWORD, NEW_PASSWORD, PASSWORD))
        assertEquals(WalletResult.Err(WalletError.SameAsOldPassword), changer.change(id, PASSWORD, PASSWORD, PASSWORD))
        assertEquals(WalletResult.Err(WalletError.WrongPassword(1, false)), changer.change(id, "nope".toCharArray(), NEW_PASSWORD, NEW_PASSWORD))
        assertEquals(WalletResult.Err(WalletError.WalletNotFound("nobody")), changer.change("nobody", PASSWORD, NEW_PASSWORD, NEW_PASSWORD))

        val before = env.store.rows.getValue(id).encryptedMnemonic
        env.store.failWrites = true
        assertIs<WalletError.Storage>((changer.change(id, PASSWORD, NEW_PASSWORD, NEW_PASSWORD) as WalletResult.Err).error)
        assertEquals(before, env.store.rows.getValue(id).encryptedMnemonic, "old envelopes untouched")
        env.store.failWrites = false
        assertTrue(env.secretAccess.verifyPassword(id, PASSWORD))
        env.withSeed(id) { assertEquals(SEED_HEX, it) }
    }

    private suspend fun VaultTestEnv.withSeed(id: String, block: (String) -> Unit) {
        assertIs<UnlockResult.Success<Unit>>(secretAccess.withUnlocked(id, PASSWORD) { block(String(it.seedHex!!)) })
    }
}
