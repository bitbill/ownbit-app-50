// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.crypto.biometric

/**
 * The facts of a generated Keystore key that decide whether it may protect a wallet password, read from
 * `android.security.keystore.KeyInfo`. Plain values so the rules are testable on the JVM.
 *
 * @property sdkInt `Build.VERSION.SDK_INT` of the device
 * @property securityLevel `KeyInfo.getSecurityLevel()` (API 31+), `null` below
 * @property insideSecureHardware `KeyInfo.isInsideSecureHardware()` (deprecated on 31+, still filled)
 * @property authType `KeyInfo.getUserAuthenticationType()` (API 30+), `null` below
 * @property validitySeconds `KeyInfo.getUserAuthenticationValidityDurationSeconds()`; auth-per-use reads `0` on
 *   keystore2 (API 31+) and `-1` on older Keystores
 */
data class KeyInfoFacts(
    val sdkInt: Int,
    val securityLevel: Int?,
    val insideSecureHardware: Boolean,
    val userAuthRequired: Boolean,
    val authEnforcedBySecureHardware: Boolean,
    val authType: Int?,
    val validitySeconds: Int,
    val invalidatedByEnrollment: Boolean,
    val validWhileOnBody: Boolean,
)

/** Result of [KeyInfoRules.verdict] / `BiometricKeyStore.create`. */
sealed interface KeyVerdict {
    data class Accept(val level: KeySecurityLevel) : KeyVerdict

    /** [reason] is a short diagnostic tag (never secret), e.g. `"security_level=0"`. */
    data class Reject(val reason: String) : KeyVerdict
}

/**
 * Accepts a key only when **all** hold (a state that cannot be established never enables the feature):
 * - API 31+: security level TRUSTED_ENVIRONMENT or STRONGBOX (SOFTWARE, UNKNOWN, UNKNOWN_SECURE rejected); below:
 *   `isInsideSecureHardware`;
 * - user authentication required **and** enforced by secure hardware;
 * - API 30+: authentication type exactly `AUTH_BIOMETRIC_STRONG`;
 * - auth-per-use: validity `<= 0` (keystore2 reports `0`, the older Keystore `-1`; a positive timeout is rejected);
 * - invalidated by biometric enrolment; not valid while on body.
 */
object KeyInfoRules {

    /** `KeyProperties.SECURITY_LEVEL_TRUSTED_ENVIRONMENT`. */
    const val SECURITY_LEVEL_TRUSTED_ENVIRONMENT = 1

    /** `KeyProperties.SECURITY_LEVEL_STRONGBOX`. */
    const val SECURITY_LEVEL_STRONGBOX = 2

    /** `KeyProperties.AUTH_BIOMETRIC_STRONG`. */
    const val AUTH_BIOMETRIC_STRONG = 2

    private const val API_SECURITY_LEVEL = 31
    private const val API_AUTH_TYPE = 30

    fun verdict(f: KeyInfoFacts): KeyVerdict {
        val level = if (f.sdkInt >= API_SECURITY_LEVEL) {
            when (f.securityLevel) {
                SECURITY_LEVEL_TRUSTED_ENVIRONMENT -> KeySecurityLevel.TEE
                SECURITY_LEVEL_STRONGBOX -> KeySecurityLevel.STRONGBOX
                else -> return KeyVerdict.Reject("security_level=${f.securityLevel}")
            }
        } else {
            if (!f.insideSecureHardware) return KeyVerdict.Reject("not_secure_hardware")
            KeySecurityLevel.TEE
        }
        if (!f.userAuthRequired) return KeyVerdict.Reject("no_user_auth")
        if (!f.authEnforcedBySecureHardware) return KeyVerdict.Reject("auth_not_hw_enforced")
        if (f.sdkInt >= API_AUTH_TYPE && f.authType != AUTH_BIOMETRIC_STRONG) return KeyVerdict.Reject("auth_type=${f.authType}")
        if (f.validitySeconds > 0) return KeyVerdict.Reject("validity=${f.validitySeconds}")
        if (!f.invalidatedByEnrollment) return KeyVerdict.Reject("not_invalidated_by_enrollment")
        if (f.validWhileOnBody) return KeyVerdict.Reject("valid_while_on_body")
        return KeyVerdict.Accept(level)
    }
}
