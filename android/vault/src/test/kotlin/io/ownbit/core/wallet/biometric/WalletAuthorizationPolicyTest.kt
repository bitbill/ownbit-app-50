// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.wallet.biometric

import io.ownbit.core.crypto.biometric.BiometricAvailability
import io.ownbit.core.crypto.biometric.BiometricCapability
import io.ownbit.core.crypto.biometric.BiometricStatus
import io.ownbit.core.wallet.biometric.AuthorizationDecision.BiometricOnly
import io.ownbit.core.wallet.biometric.AuthorizationDecision.BiometricThenPassword
import io.ownbit.core.wallet.biometric.AuthorizationDecision.PasswordOnly
import io.ownbit.core.wallet.testing.FakeBiometricKeyStore
import io.ownbit.core.wallet.testing.FakeCapabilityChecker
import io.ownbit.core.wallet.testing.TestClocks
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
import java.math.BigDecimal
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue

/**
 * Rule order and value rules: `< limit` biometric only, `>= limit` biometric then password,
 * threshold 0 / no price / stale price / unknown value never "small", batches by their sum (BigDecimal), every TxKind,
 * master / wallet switches and a live capability drop. Plus the final-path [WalletAuthorizationPolicy.recheck].
 */
class WalletAuthorizationPolicyTest {

    @get:Rule val tmp = TemporaryFolder()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val clocks = TestClocks()
    private val keys = FakeBiometricKeyStore()
    private val capability = FakeCapabilityChecker()
    private val prices = TestQuotes()
    private val cipher = TestRecordCipher()
    private val repo by lazy { QuickSendRepository(File(tmp.root, "qs.enc"), cipher, keys, Dispatchers.IO, scope) }
    private val policy by lazy { WalletAuthorizationPolicy(repo, capability, prices, clocks) }

    @After fun tearDown() = scope.cancel()

    private val now get() = clocks.now

    /** Mainnets priced by symbol, tokens by chain + lower-case contract (the app's price-book rule, simplified). */
    private class TestQuotes : UsdQuotes {
        var quotes: Map<String, UsdQuote> = emptyMap()
        override fun quote(outflow: AssetOutflow): UsdQuote? =
            quotes[outflow.contract?.let { "${outflow.chain}:${it.lowercase()}" } ?: outflow.symbol]

        fun set(map: Map<String, UsdQuote>) {
            quotes = map
        }
    }

    private fun book(vararg quotes: Pair<String, String>, at: Long = now) =
        quotes.associate { (k, v) -> k to UsdQuote(BigDecimal(v), at) }

    private fun btc(amount: String) = AssetOutflow("BTC", "BTC", null, BigDecimal(amount))
    private fun eth(amount: String) = AssetOutflow("ETH", "ETH", null, BigDecimal(amount))
    private fun usdt(amount: String) =
        AssetOutflow("ETH", "USDT", "0xdAC17F958D2ee523a2206206994597C13D831ec7", BigDecimal(amount))

    private val usdtKey = "ETH:0xdac17f958d2ee523a2206206994597c13d831ec7"

    private suspend fun ready(threshold: Long = 1_000L, wallet: String = "w1") {
        assertTrue(repo.setMaster(true))
        assertTrue(repo.setThresholdUsd(threshold))
        assertTrue(repo.putRecord(QuickSendRecord(wallet, BiometricSendVault.ALIAS_PREFIX + "x", "00", "00", "TEE", 1L)).written)
    }

    private fun request(outflows: List<AssetOutflow>?, kind: TxKind = TxKind.PERSONAL_SEND, wallet: String = "w1", digest: String = "d") =
        AuthorizationRequest(wallet, kind, outflows, digest)

    @Test fun `switches and kind come before any value rule`() = runTest {
        prices.set(book("BTC" to "100"))
        assertEquals(PasswordOnly(PasswordReason.FEATURE_OFF), policy.decide(request(listOf(btc("1")))))
        assertTrue(repo.setMaster(true))
        assertEquals(PasswordOnly(PasswordReason.WALLET_OFF), policy.decide(request(listOf(btc("1")))))
        ready()
        assertEquals(PasswordOnly(PasswordReason.WALLET_OFF), policy.decide(request(listOf(btc("1")), wallet = "other")))
        for (kind in TxKind.entries) {
            val expected = if (kind.biometricAllowed) BiometricOnly else PasswordOnly(PasswordReason.KIND_NOT_ALLOWED)
            assertEquals(expected, policy.decide(request(listOf(btc("1")), kind = kind)), kind.name)
        }
        assertEquals(
            setOf(TxKind.PERSONAL_SEND, TxKind.MULTISIG_INITIATE, TxKind.MULTISIG_APPROVE, TxKind.MULTISIG_BATCH, TxKind.MULTISIG_EXECUTE, TxKind.MULTISIG_DEPLOY),
            TxKind.entries.filter { it.biometricAllowed }.toSet(),
            "kinds that may use biometrics",
        )
    }

    @Test fun `a live capability drop falls back to the password`() = runTest {
        ready()
        prices.set(book("BTC" to "100"))
        for (cap in listOf(BiometricCapability.NONE, BiometricCapability.WEAK_ONLY, BiometricCapability.STRONG_NO_HW_KEY)) {
            capability.status = BiometricStatus(cap, BiometricAvailability.AVAILABLE, BiometricAvailability.NONE_ENROLLED, null)
            assertEquals(PasswordOnly(PasswordReason.DEVICE_NOT_ELIGIBLE), policy.decide(request(listOf(btc("1")))), cap.name)
        }
    }

    @Test fun `value below, at and above the threshold - at the limit needs the password`() = runTest {
        ready(threshold = 1_000L)
        prices.set(book("BTC" to "50000"))
        assertEquals(BiometricOnly, policy.decide(request(listOf(btc("0.01999998")))))
        assertEquals(BiometricThenPassword, policy.decide(request(listOf(btc("0.02")))), "exactly 1,000 USD")
        assertEquals(BiometricThenPassword, policy.decide(request(listOf(btc("0.0200000001")))))
        assertEquals(BiometricOnly, policy.decide(request(listOf(btc("0.019999999999999999")))), "BigDecimal, no rounding up")
    }

    @Test fun `threshold 0, unknown value, negative amounts, missing or stale prices are never small`() = runTest {
        ready(threshold = 0L)
        prices.set(book("BTC" to "1"))
        assertEquals(BiometricThenPassword, policy.decide(request(listOf(btc("0.00000001")))), "0 = everything is large")
        assertTrue(repo.setThresholdUsd(1_000L))
        assertEquals(BiometricThenPassword, policy.decide(request(null)), "outflows unknown")
        assertEquals(BiometricThenPassword, policy.decide(request(listOf(btc("-1")))))
        assertEquals(BiometricThenPassword, policy.decide(request(listOf(eth("0.01")))), "no ETH price")
        assertEquals(BiometricThenPassword, policy.decide(request(listOf(usdt("1")))), "token without its contract price")
        prices.set(book("BTC" to "1", usdtKey to "1", at = now - QuickSendRules.MAX_PRICE_AGE_MILLIS - 1))
        assertEquals(BiometricThenPassword, policy.decide(request(listOf(btc("1")))), "stale quote")
        prices.set(book("BTC" to "1", usdtKey to "1", at = now - QuickSendRules.MAX_PRICE_AGE_MILLIS))
        assertEquals(BiometricOnly, policy.decide(request(listOf(btc("1"), usdt("5")))))
        prices.set(book("BTC" to "1").mapValues { it.value.copy(isUsable = false) })
        assertEquals(BiometricThenPassword, policy.decide(request(listOf(btc("1")))), "unusable quote")
    }

    @Test fun `batches and multi-asset transfers are judged by their sum`() = runTest {
        ready(threshold = 1_000L)
        prices.set(book("BTC" to "50000", "ETH" to "2500", usdtKey to "1"))
        val items = listOf(btc("0.01"), eth("0.1"), usdt("249.99")) // 500 + 250 + 249.99
        assertEquals(BiometricOnly, policy.decide(request(items, kind = TxKind.MULTISIG_BATCH)))
        assertEquals(BiometricThenPassword, policy.decide(request(items + usdt("0.01"), kind = TxKind.MULTISIG_BATCH)), "sum = 1,000")
        // Each item alone is small; together they are not (iOS judges per item, Android by the sum).
        val many = List(5) { btc("0.004") } // 5 × 200
        assertEquals(BiometricThenPassword, policy.decide(request(many, kind = TxKind.MULTISIG_BATCH)))
        // Zero amounts move nothing and need no price; an empty list is worth 0.
        assertEquals(BiometricOnly, policy.decide(request(listOf(eth("0"), btc("0.001")))))
        assertEquals(BiometricOnly, policy.decide(request(emptyList())))
    }

    @Test fun `recheck needs the same wallet, the same content, a live grant and a still-small value`() = runTest {
        ready(threshold = 1_000L)
        prices.set(book("BTC" to "50000"))
        val r = request(listOf(btc("0.01")), digest = "abc")
        val registry = GrantRegistry(clocks, scope, null)
        fun grant(wallet: String = "w1", digest: String = "abc") = registry.issue(wallet, digest, "Passw0rd!x".toCharArray())

        assertTrue(policy.recheck(grant(), r))
        assertFalse(policy.recheck(grant(digest = "other"), r), "content changed")
        assertFalse(policy.recheck(grant(wallet = "w2"), r), "another wallet")
        val used = grant()
        used.use { }
        assertFalse(policy.recheck(used, r), "used")
        val expiring = grant()
        clocks.advance(BiometricGrant.TTL_MILLIS)
        assertFalse(policy.recheck(expiring, r), "expired")
        val fresh = grant()
        prices.set(book("BTC" to "100000", at = clocks.now))
        assertFalse(policy.recheck(fresh, r), "price moved the value to the limit")
        prices.set(book("BTC" to "50000", at = clocks.now))
        assertTrue(policy.recheck(fresh, r))
        assertTrue(repo.setMaster(false))
        assertFalse(policy.recheck(fresh, r), "switched off meanwhile")
    }

    @Test fun `an unreadable settings file is all off`() = runTest {
        ready()
        prices.set(book("BTC" to "1"))
        val broken = TestRecordCipher().apply { broken = true }
        val restarted = QuickSendRepository(File(tmp.root, "qs.enc"), broken, keys, Dispatchers.IO, scope)
        val p = WalletAuthorizationPolicy(restarted, capability, prices, clocks)
        assertEquals(PasswordOnly(PasswordReason.FEATURE_OFF), p.decide(request(listOf(btc("1")))))
        assertEquals(QuickSendSettings(), restarted.snapshot().settings)
    }

    @Test fun `digest is canonical - order, null and separators matter`() {
        val a = AuthorizationDigest.of("w1", "BTC", "addr", "0.1")
        assertEquals(a, AuthorizationDigest.of("w1", "BTC", "addr", "0.1"))
        assertEquals(64, a.length)
        assertNotEquals(a, AuthorizationDigest.of("w1", "BTC", "0.1", "addr"))
        assertNotEquals(AuthorizationDigest.of("a", null), AuthorizationDigest.of("a", ""))
        assertNotEquals(AuthorizationDigest.of("ab", "c"), AuthorizationDigest.of("a", "bc"))
        assertNotEquals(AuthorizationDigest.of("a\u0000b"), AuthorizationDigest.of("a", "b"))
    }
}
