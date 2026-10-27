// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.crypto.biometric

/**
 * Pure classification of the device's biometric capability (JVM-testable): screen lock → weak → strong → probe key.
 *
 * `BiometricManager` codes are mapped by [availability]; [probe] is only run when Class 3 biometrics are available and
 * answers the probe key's verdict plus the negative probe (`null` = the probe could not run).
 */
object CapabilityClassifier {

    /** `BiometricManager.BIOMETRIC_SUCCESS`. */
    const val BIOMETRIC_SUCCESS = 0

    /** `BiometricManager.BIOMETRIC_STATUS_UNKNOWN`. */
    const val BIOMETRIC_STATUS_UNKNOWN = -1

    /** `BiometricManager.BIOMETRIC_ERROR_UNSUPPORTED`. */
    const val BIOMETRIC_ERROR_UNSUPPORTED = -2

    /** `BiometricManager.BIOMETRIC_ERROR_HW_UNAVAILABLE`. */
    const val BIOMETRIC_ERROR_HW_UNAVAILABLE = 1

    /** `BiometricManager.BIOMETRIC_ERROR_NONE_ENROLLED`. */
    const val BIOMETRIC_ERROR_NONE_ENROLLED = 11

    /** `BiometricManager.BIOMETRIC_ERROR_NO_HARDWARE`. */
    const val BIOMETRIC_ERROR_NO_HARDWARE = 12

    /** `BiometricManager.BIOMETRIC_ERROR_SECURITY_UPDATE_REQUIRED`. */
    const val BIOMETRIC_ERROR_SECURITY_UPDATE_REQUIRED = 15

    /** Result of the probe key (step 4). */
    data class Probe(val verdict: KeyVerdict, val refusesUnauthenticatedUse: Boolean) {
        val accepted: Boolean get() = verdict is KeyVerdict.Accept && refusesUnauthenticatedUse
    }

    /** Maps a `BiometricManager.canAuthenticate` answer; an unknown status is "temporarily unavailable". */
    fun availability(code: Int): BiometricAvailability = when (code) {
        BIOMETRIC_SUCCESS -> BiometricAvailability.AVAILABLE
        BIOMETRIC_ERROR_NONE_ENROLLED -> BiometricAvailability.NONE_ENROLLED
        BIOMETRIC_ERROR_NO_HARDWARE -> BiometricAvailability.NO_HARDWARE
        BIOMETRIC_ERROR_HW_UNAVAILABLE, BIOMETRIC_STATUS_UNKNOWN -> BiometricAvailability.HW_UNAVAILABLE
        BIOMETRIC_ERROR_SECURITY_UPDATE_REQUIRED -> BiometricAvailability.SECURITY_UPDATE_REQUIRED
        else -> BiometricAvailability.UNSUPPORTED
    }

    fun classify(
        deviceSecure: Boolean,
        weakCode: Int,
        strongCode: Int,
        probe: () -> Probe?,
    ): BiometricStatus {
        if (!deviceSecure) {
            return BiometricStatus(
                BiometricCapability.NONE,
                BiometricAvailability.NO_SCREEN_LOCK,
                BiometricAvailability.NO_SCREEN_LOCK,
                null,
            )
        }
        val weak = availability(weakCode)
        val strong = availability(strongCode)
        if (weak != BiometricAvailability.AVAILABLE) {
            // A Class 3 sensor is also Class 2: a strong-only answer cannot exist; stay conservative.
            return BiometricStatus(BiometricCapability.NONE, weak, strong, null)
        }
        if (strong != BiometricAvailability.AVAILABLE) {
            return BiometricStatus(BiometricCapability.WEAK_ONLY, weak, strong, null)
        }
        val result = probe()
        if (result == null || !result.accepted) {
            return BiometricStatus(BiometricCapability.STRONG_NO_HW_KEY, weak, strong, null)
        }
        return BiometricStatus(BiometricCapability.STRONG_HW, weak, strong, (result.verdict as KeyVerdict.Accept).level)
    }
}
