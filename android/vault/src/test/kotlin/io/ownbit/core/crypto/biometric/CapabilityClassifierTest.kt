// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.crypto.biometric

import io.ownbit.core.crypto.biometric.CapabilityClassifier.BIOMETRIC_ERROR_HW_UNAVAILABLE
import io.ownbit.core.crypto.biometric.CapabilityClassifier.BIOMETRIC_ERROR_NONE_ENROLLED
import io.ownbit.core.crypto.biometric.CapabilityClassifier.BIOMETRIC_ERROR_NO_HARDWARE
import io.ownbit.core.crypto.biometric.CapabilityClassifier.BIOMETRIC_ERROR_SECURITY_UPDATE_REQUIRED
import io.ownbit.core.crypto.biometric.CapabilityClassifier.BIOMETRIC_ERROR_UNSUPPORTED
import io.ownbit.core.crypto.biometric.CapabilityClassifier.BIOMETRIC_STATUS_UNKNOWN
import io.ownbit.core.crypto.biometric.CapabilityClassifier.BIOMETRIC_SUCCESS
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Screen lock → weak → strong → probe key (verdict + negative probe), over every `BiometricManager` code. */
class CapabilityClassifierTest {

    private val accept = CapabilityClassifier.Probe(KeyVerdict.Accept(KeySecurityLevel.TEE), refusesUnauthenticatedUse = true)
    private val strongBox = CapabilityClassifier.Probe(KeyVerdict.Accept(KeySecurityLevel.STRONGBOX), refusesUnauthenticatedUse = true)
    private val software = CapabilityClassifier.Probe(KeyVerdict.Reject("security_level=0"), refusesUnauthenticatedUse = false)
    private val notRefused = CapabilityClassifier.Probe(KeyVerdict.Accept(KeySecurityLevel.TEE), refusesUnauthenticatedUse = false)

    private val codes = listOf(
        BIOMETRIC_SUCCESS, BIOMETRIC_STATUS_UNKNOWN, BIOMETRIC_ERROR_UNSUPPORTED, BIOMETRIC_ERROR_HW_UNAVAILABLE,
        BIOMETRIC_ERROR_NONE_ENROLLED, BIOMETRIC_ERROR_NO_HARDWARE, BIOMETRIC_ERROR_SECURITY_UPDATE_REQUIRED, 999,
    )

    @Test fun availabilityMapping() {
        assertEquals(BiometricAvailability.AVAILABLE, CapabilityClassifier.availability(BIOMETRIC_SUCCESS))
        assertEquals(BiometricAvailability.NONE_ENROLLED, CapabilityClassifier.availability(BIOMETRIC_ERROR_NONE_ENROLLED))
        assertEquals(BiometricAvailability.NO_HARDWARE, CapabilityClassifier.availability(BIOMETRIC_ERROR_NO_HARDWARE))
        assertEquals(BiometricAvailability.HW_UNAVAILABLE, CapabilityClassifier.availability(BIOMETRIC_ERROR_HW_UNAVAILABLE))
        assertEquals(BiometricAvailability.HW_UNAVAILABLE, CapabilityClassifier.availability(BIOMETRIC_STATUS_UNKNOWN))
        assertEquals(BiometricAvailability.SECURITY_UPDATE_REQUIRED, CapabilityClassifier.availability(BIOMETRIC_ERROR_SECURITY_UPDATE_REQUIRED))
        assertEquals(BiometricAvailability.UNSUPPORTED, CapabilityClassifier.availability(BIOMETRIC_ERROR_UNSUPPORTED))
        assertEquals(BiometricAvailability.UNSUPPORTED, CapabilityClassifier.availability(999))
    }

    @Test fun noScreenLockIsNoneWhateverTheSensorSays() {
        for (weak in codes) for (strong in codes) {
            var probed = false
            val s = CapabilityClassifier.classify(false, weak, strong) { probed = true; accept }
            assertEquals(BiometricCapability.NONE, s.capability)
            assertEquals(BiometricAvailability.NO_SCREEN_LOCK, s.weak)
            assertFalse(s.deviceSecure)
            assertFalse(probed)
        }
    }

    @Test fun weakNotAvailableIsNone() {
        for (weak in codes - BIOMETRIC_SUCCESS) for (strong in codes) {
            val s = CapabilityClassifier.classify(true, weak, strong) { accept }
            assertEquals("weak $weak strong $strong", BiometricCapability.NONE, s.capability)
            assertEquals(CapabilityClassifier.availability(weak), s.weak)
            assertTrue(s.deviceSecure)
            assertFalse(s.canUnlock)
        }
    }

    @Test fun weakOnlyUnlocksButNeverAuthorizes() {
        for (strong in codes - BIOMETRIC_SUCCESS) {
            var probed = false
            val s = CapabilityClassifier.classify(true, BIOMETRIC_SUCCESS, strong) { probed = true; accept }
            assertEquals(BiometricCapability.WEAK_ONLY, s.capability)
            assertTrue(s.canUnlock)
            assertFalse(s.canAuthorizeTransactions)
            assertFalse("no probe key without Class 3", probed)
        }
    }

    @Test fun strongNeedsAnAcceptedProbeKeyThatRefusesUnauthenticatedUse() {
        val hw = CapabilityClassifier.classify(true, BIOMETRIC_SUCCESS, BIOMETRIC_SUCCESS) { accept }
        assertEquals(BiometricCapability.STRONG_HW, hw.capability)
        assertEquals(KeySecurityLevel.TEE, hw.keyLevel)
        assertTrue(hw.canAuthorizeTransactions)
        assertEquals(KeySecurityLevel.STRONGBOX, CapabilityClassifier.classify(true, 0, 0) { strongBox }.keyLevel)

        for (probe in listOf(software, notRefused, null)) {
            val s = CapabilityClassifier.classify(true, BIOMETRIC_SUCCESS, BIOMETRIC_SUCCESS) { probe }
            assertEquals(BiometricCapability.STRONG_NO_HW_KEY, s.capability)
            assertNull(s.keyLevel)
            assertTrue(s.canUnlock)
            assertFalse(s.canAuthorizeTransactions)
        }
    }

    @Test fun unavailableConstantIsFailClosed() {
        assertEquals(BiometricCapability.NONE, BiometricStatus.UNAVAILABLE.capability)
        assertFalse(BiometricStatus.UNAVAILABLE.canUnlock)
        assertFalse(BiometricStatus.UNAVAILABLE.canAuthorizeTransactions)
    }
}
