// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.crypto

import android.content.pm.PackageManager
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import io.ownbit.core.crypto.biometric.AndroidBiometricCapabilityChecker
import io.ownbit.core.crypto.biometric.AndroidBiometricKeyStore
import io.ownbit.core.crypto.biometric.BiometricAvailability
import io.ownbit.core.crypto.biometric.BiometricCapability
import io.ownbit.core.crypto.biometric.CipherResult
import io.ownbit.core.crypto.biometric.KeyInfoRules
import io.ownbit.core.crypto.biometric.KeySecurityLevel
import io.ownbit.core.crypto.biometric.KeyVerdict
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Assume.assumeTrue
import org.junit.BeforeClass
import org.junit.FixMethodOrder
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.MethodSorters
import java.io.FileInputStream
import java.security.KeyStore

/**
 * The real Android Keystore behind biometric quick send. Needs a screen-lock PIN (set in [screenLock]) and an enrolled
 * Class 3 biometric (on an emulator: enrol a fingerprint in Settings with `adb emu finger touch 1`); without one the key
 * tests are skipped (assumption), not passed.
 *
 * Device-agnostic: on a device with a TEE / StrongBox the verdict is Accept and the capability STRONG_HW; on an emulator
 * whose Keystore reports `SECURITY_LEVEL_SOFTWARE` (0) the same code must answer Reject / STRONG_NO_HW_KEY ("software-only
 * key: quick send cannot be turned on"). Keys are generated with the production spec ([AndroidBiometricKeyStore.generate])
 * to read their facts even where [AndroidBiometricKeyStore.create] deletes them.
 *
 * Methods run in name order: `z_` removes the screen lock (which also deletes the enrolled fingerprints) and must be
 * last; enrol again before the next run.
 */
@RunWith(AndroidJUnit4::class)
@FixMethodOrder(MethodSorters.NAME_ASCENDING)
class BiometricKeystoreInstrumentedTest {

    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val store by lazy { AndroidBiometricKeyStore(context) }
    private val alias = "ownbit_bio_send_v1_instrumented"

    @After fun cleanUp() {
        store.delete(alias)
    }

    private suspend fun status() = AndroidBiometricCapabilityChecker(context, store, Dispatchers.IO).status()

    private suspend fun assumeStrongBiometric() {
        val s = status()
        assumeTrue("needs an enrolled Class 3 biometric; status=$s", s.strong == BiometricAvailability.AVAILABLE)
    }

    /** A key with the production spec, kept whatever its verdict. */
    private fun generated() = store.generate(alias, strongBox = false)

    @Test fun a_capabilityFollowsTheRealKeyFacts() = runTest {
        val s = status()
        Log.i(TAG, "capability: $s strongbox=${hasStrongBox()} sdk=${Build.VERSION.SDK_INT}")
        assertTrue("PIN set in @BeforeClass", s.deviceSecure)
        assumeStrongBiometric()
        val verdict = KeyInfoRules.verdict(store.facts(generated()))
        Log.i(TAG, "probe-equivalent verdict: $verdict")
        val expected = if (verdict is KeyVerdict.Accept) BiometricCapability.STRONG_HW else BiometricCapability.STRONG_NO_HW_KEY
        assertEquals(expected, s.capability)
        assertFalse(
            "the probe key is deleted",
            KeyStore.getInstance("AndroidKeyStore").apply { load(null) }.containsAlias(AndroidBiometricCapabilityChecker.PROBE_ALIAS),
        )
    }

    @Test fun b_createJudgesTheRealKeyInfo() = runTest {
        assumeStrongBiometric()
        val facts = store.facts(generated())
        Log.i(TAG, "key facts: $facts")
        // What the production spec yields on any device (hardware or not):
        assertTrue(facts.userAuthRequired)
        if (Build.VERSION.SDK_INT >= 30) assertEquals(KeyInfoRules.AUTH_BIOMETRIC_STRONG, facts.authType)
        assertTrue("auth-per-use", facts.validitySeconds <= 0)
        assertTrue(facts.invalidatedByEnrollment)
        assertFalse(facts.validWhileOnBody)

        val expected = KeyInfoRules.verdict(facts)
        val verdict = store.create(alias)
        Log.i(TAG, "create verdict: $verdict (rules: $expected)")
        when (verdict) {
            is KeyVerdict.Accept -> {
                assertTrue(expected is KeyVerdict.Accept)
                assertTrue(store.exists(alias))
                if (verdict.level != KeySecurityLevel.STRONGBOX) assertEquals(expected, verdict)
                assertTrue(facts.authEnforcedBySecureHardware)
            }
            is KeyVerdict.Reject -> {
                assertEquals(expected, verdict)
                assertFalse("a rejected key is deleted", store.exists(alias))
            }
        }
    }

    @Test fun c_negativeProbe_unauthenticatedUseIsRefused() = runTest {
        assumeStrongBiometric()
        generated()
        assertTrue(store.refusesUnauthenticatedUse(alias))
        // The same by hand: init works (auth-per-use), the operation itself is refused without a prompt.
        val cipher = (store.encryptCipher(alias) as CipherResult.Ready).cipher
        try {
            cipher.doFinal("secret".toByteArray())
            fail("an auth-per-use key encrypted without authentication")
        } catch (e: Exception) {
            Log.i(TAG, "refused as expected: ${e.javaClass.name} / ${e.cause?.javaClass?.name}")
        }
        assertTrue("init-only probe works without a prompt", store.decryptCipher(alias, ByteArray(12) { 1 }) is CipherResult.Ready)
    }

    @Test fun d_strongBoxOnlyWhenDeclared() = runTest {
        assumeStrongBiometric()
        when (val verdict = store.create(alias)) {
            is KeyVerdict.Accept -> if (!hasStrongBox()) assertEquals(KeySecurityLevel.TEE, verdict.level)
            is KeyVerdict.Reject -> Log.i(TAG, "no hardware key on this device: ${verdict.reason}")
        }
    }

    @Test fun e_deleteRemovesTheAliasAndMissingKeysReadAsMissing() = runTest {
        assumeStrongBiometric()
        generated()
        assertTrue(store.exists(alias))
        assertTrue(alias in store.aliases("ownbit_bio_send_v1_"))
        store.delete(alias)
        assertFalse(store.exists(alias))
        assertEquals(CipherResult.Missing, store.encryptCipher(alias))
        assertEquals(CipherResult.Missing, store.decryptCipher(alias, ByteArray(12)))
        store.delete(alias) // no-op, never throws
    }

    /** Last: removing the screen lock invalidates every auth-bound key (and deletes the fingerprints). */
    @Test fun z_removingTheScreenLockInvalidatesTheKey() = runTest {
        assumeStrongBiometric()
        generated()
        assertTrue(store.decryptCipher(alias, ByteArray(12)) is CipherResult.Ready)
        val out = shell("locksettings clear --old $PIN")
        Log.i(TAG, "locksettings clear: $out")
        val after = store.decryptCipher(alias, ByteArray(12))
        Log.i(TAG, "after lock removal: $after")
        assertTrue("$after", after == CipherResult.Invalidated || after == CipherResult.Missing)
        val enc = store.encryptCipher(alias)
        assertTrue("$enc", enc == CipherResult.Invalidated || enc == CipherResult.Missing)
        val s = status()
        assertEquals(BiometricCapability.NONE, s.capability)
        assertFalse(s.deviceSecure)
    }

    private fun hasStrongBox(): Boolean =
        Build.VERSION.SDK_INT >= 28 && context.packageManager.hasSystemFeature(PackageManager.FEATURE_STRONGBOX_KEYSTORE)

    companion object {
        private const val TAG = "BiometricKeystoreTest"
        private const val PIN = "1111"

        /** Runs [command] as the shell user (locksettings). */
        fun shell(command: String): String {
            val pfd: ParcelFileDescriptor = InstrumentationRegistry.getInstrumentation().uiAutomation.executeShellCommand(command)
            return FileInputStream(pfd.fileDescriptor).use { it.readBytes().decodeToString() }.also { pfd.close() }
        }

        @BeforeClass @JvmStatic fun screenLock() {
            // Already set → the command fails harmlessly.
            Log.i(TAG, "locksettings set-pin: " + shell("locksettings set-pin $PIN").trim())
        }
    }
}
