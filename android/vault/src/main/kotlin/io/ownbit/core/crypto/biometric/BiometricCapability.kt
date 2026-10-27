// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.crypto.biometric

/**
 * What this device's biometrics may be used for. Never a vendor allow-list: only official APIs.
 *
 * - [NONE]: no secure screen lock, or no usable biometric at all (not enrolled, no hardware, temporarily unavailable…).
 * - [WEAK_ONLY]: Class 2 biometrics only — **app unlock only**, never a transaction.
 * - [STRONG_NO_HW_KEY]: Class 3 biometrics, but the probe key was not a hardware-backed (TEE / StrongBox) auth-per-use
 *   key whose authentication is enforced by secure hardware, or an unauthenticated use was not refused — unlock only.
 * - [STRONG_HW]: Class 3 biometrics **and** a probe key that passed [KeyInfoRules] and the negative probe. Biometric
 *   quick send still needs its own per-wallet key passing the same checks.
 */
enum class BiometricCapability { NONE, WEAK_ONLY, STRONG_NO_HW_KEY, STRONG_HW }

/** `BiometricManager.canAuthenticate` answer for one authenticator class (plus the screen-lock check). */
enum class BiometricAvailability {
    AVAILABLE,

    /** Hardware present, nothing enrolled: the app may offer the system enrolment screen. */
    NONE_ENROLLED,
    NO_HARDWARE,

    /** Hardware temporarily unavailable (or the status could not be determined). */
    HW_UNAVAILABLE,
    SECURITY_UPDATE_REQUIRED,

    /** `KeyguardManager.isDeviceSecure` is false: no PIN / pattern / password screen lock. */
    NO_SCREEN_LOCK,
    UNSUPPORTED,
}

/** Where a Keystore key lives. */
enum class KeySecurityLevel { STRONGBOX, TEE, SOFTWARE, UNKNOWN }

/**
 * Snapshot of the device's biometric capability. No secrets.
 *
 * @property weak availability of Class 2 (`BIOMETRIC_WEAK`) authentication
 * @property strong availability of Class 3 (`BIOMETRIC_STRONG`) authentication
 * @property keyLevel level of the accepted probe key ([BiometricCapability.STRONG_HW] only), for diagnostics
 */
data class BiometricStatus(
    val capability: BiometricCapability,
    val weak: BiometricAvailability,
    val strong: BiometricAvailability,
    val keyLevel: KeySecurityLevel?,
) {
    /** A secure screen lock (PIN / pattern / password) exists — the device credential can authenticate. */
    val deviceSecure: Boolean get() = weak != BiometricAvailability.NO_SCREEN_LOCK

    /** Biometrics may unlock the app ([BiometricCapability.WEAK_ONLY] or better). */
    val canUnlock: Boolean get() = capability != BiometricCapability.NONE

    /** The device may be used for biometric quick send ([BiometricCapability.STRONG_HW]). */
    val canAuthorizeTransactions: Boolean get() = capability == BiometricCapability.STRONG_HW

    companion object {
        /** Nothing usable (also the answer when the check itself failed). */
        val UNAVAILABLE = BiometricStatus(
            BiometricCapability.NONE,
            BiometricAvailability.UNSUPPORTED,
            BiometricAvailability.UNSUPPORTED,
            null,
        )
    }
}

/**
 * Capability detection. [status] runs off the main thread; the `BiometricManager` / screen-lock answers are read live
 * on every call, only the Keystore probe verdict is cached per process. [refresh] drops that cache (e.g. when a settings
 * page resumes, after the enrolment screen returns).
 */
interface BiometricCapabilityChecker {
    suspend fun status(): BiometricStatus

    fun refresh()
}
