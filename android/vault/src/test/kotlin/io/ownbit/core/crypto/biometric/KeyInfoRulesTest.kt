// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.crypto.biometric

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Only a hardware-backed (TEE / StrongBox), hardware-enforced, Class-3-only, auth-per-use key that
 * is invalidated by enrolment is accepted — over API 26 / 28 / 30 / 31 / 34 × every security level × auth flags ×
 * validity −1 / 0 / 30 × enrolment flag.
 */
class KeyInfoRulesTest {

    private val SOFTWARE = 0
    private val TEE = KeyInfoRules.SECURITY_LEVEL_TRUSTED_ENVIRONMENT
    private val STRONGBOX = KeyInfoRules.SECURITY_LEVEL_STRONGBOX
    private val UNKNOWN_SECURE = -1
    private val UNKNOWN = -2
    private val AUTH_DEVICE_CREDENTIAL = 1
    private val AUTH_BOTH = 3

    /** A key exactly as created by `AndroidBiometricKeyStore` on [sdk] (keystore2 reports validity 0, older -1). */
    private fun good(sdk: Int, level: Int = TEE) = KeyInfoFacts(
        sdkInt = sdk,
        securityLevel = if (sdk >= 31) level else null,
        insideSecureHardware = true,
        userAuthRequired = true,
        authEnforcedBySecureHardware = true,
        authType = if (sdk >= 30) KeyInfoRules.AUTH_BIOMETRIC_STRONG else null,
        validitySeconds = if (sdk >= 31) 0 else -1,
        invalidatedByEnrollment = true,
        validWhileOnBody = false,
    )

    private val apis = listOf(26, 28, 30, 31, 34)

    @Test fun acceptsAGoodKeyOnEveryApi() {
        for (sdk in apis) {
            assertEquals("api $sdk", KeyVerdict.Accept(KeySecurityLevel.TEE), KeyInfoRules.verdict(good(sdk)))
        }
        assertEquals(KeyVerdict.Accept(KeySecurityLevel.STRONGBOX), KeyInfoRules.verdict(good(31, STRONGBOX)))
        assertEquals(KeyVerdict.Accept(KeySecurityLevel.STRONGBOX), KeyInfoRules.verdict(good(34, STRONGBOX)))
    }

    @Test fun securityLevelOn31AndLater() {
        for (sdk in listOf(31, 34)) {
            for (level in listOf(SOFTWARE, UNKNOWN_SECURE, UNKNOWN, 7)) {
                assertReject("api $sdk level $level", good(sdk, level))
            }
            assertReject("api $sdk level null", good(sdk).copy(securityLevel = null))
            // isInsideSecureHardware is not trusted on 31+: the level decides.
            assertEquals(KeyVerdict.Accept(KeySecurityLevel.TEE), KeyInfoRules.verdict(good(sdk).copy(insideSecureHardware = false)))
        }
    }

    @Test fun secureHardwareBefore31() {
        for (sdk in listOf(26, 28, 30)) {
            assertReject("api $sdk software", good(sdk).copy(insideSecureHardware = false))
            // A level reported below 31 (impossible) is ignored.
            assertEquals(KeyVerdict.Accept(KeySecurityLevel.TEE), KeyInfoRules.verdict(good(sdk).copy(securityLevel = SOFTWARE)))
        }
    }

    @Test fun userAuthenticationMustBeRequiredAndHardwareEnforced() {
        for (sdk in apis) {
            assertReject("api $sdk no auth", good(sdk).copy(userAuthRequired = false))
            assertReject("api $sdk not hw enforced", good(sdk).copy(authEnforcedBySecureHardware = false))
        }
    }

    @Test fun class3BiometricsOnlyFrom30() {
        for (sdk in listOf(30, 31, 34)) {
            assertReject("api $sdk credential", good(sdk).copy(authType = AUTH_DEVICE_CREDENTIAL))
            assertReject("api $sdk both", good(sdk).copy(authType = AUTH_BOTH))
            assertReject("api $sdk none", good(sdk).copy(authType = 0))
            assertReject("api $sdk null", good(sdk).copy(authType = null))
        }
        // Below 30 the type is not reported: auth-per-use keys can only be released by Class 3 biometrics there.
        for (sdk in listOf(26, 28)) {
            assertEquals(KeyVerdict.Accept(KeySecurityLevel.TEE), KeyInfoRules.verdict(good(sdk).copy(authType = null)))
        }
    }

    @Test fun authPerUseOnly() {
        for (sdk in apis) {
            for (validity in listOf(-1, 0)) {
                assertEquals("api $sdk validity $validity", KeyVerdict.Accept(KeySecurityLevel.TEE), KeyInfoRules.verdict(good(sdk).copy(validitySeconds = validity)))
            }
            for (validity in listOf(1, 30, 3600)) assertReject("api $sdk validity $validity", good(sdk).copy(validitySeconds = validity))
        }
    }

    @Test fun invalidatedByEnrollmentAndNotOnBody() {
        for (sdk in apis) {
            assertReject("api $sdk enrolment", good(sdk).copy(invalidatedByEnrollment = false))
            assertReject("api $sdk on body", good(sdk).copy(validWhileOnBody = true))
        }
    }

    @Test fun rejectReasonsNameTheRuleNotAValue() {
        val reason = (KeyInfoRules.verdict(good(34, SOFTWARE)) as KeyVerdict.Reject).reason
        assertEquals("security_level=0", reason)
    }

    private fun assertReject(message: String, facts: KeyInfoFacts) {
        assertTrue(message, KeyInfoRules.verdict(facts) is KeyVerdict.Reject)
    }
}
