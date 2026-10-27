// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.crypto.biometric

import android.app.KeyguardManager
import android.content.Context
import androidx.biometric.BiometricManager
import io.ownbit.core.common.log.Log
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.withContext

/**
 * [BiometricCapabilityChecker] on `KeyguardManager` + androidx `BiometricManager` + the probe key
 * [PROBE_ALIAS] (created like a quick-send key, inspected, negative-probed, deleted). Only an **accepted** probe is
 * cached for the process: a rejection or a failure is probed again at the next [status] (rare: only while Class 3
 * biometrics are available). [refresh] drops the cache.
 */
class AndroidBiometricCapabilityChecker(
    private val context: Context,
    private val keyStore: BiometricKeyStore,
    private val io: CoroutineDispatcher,
) : BiometricCapabilityChecker {

    @Volatile private var cachedProbe: CapabilityClassifier.Probe? = null
    private val probeLock = Any()

    override suspend fun status(): BiometricStatus = withContext(io) {
        try {
            val keyguard = context.getSystemService(KeyguardManager::class.java)
            val manager = BiometricManager.from(context)
            CapabilityClassifier.classify(
                deviceSecure = keyguard?.isDeviceSecure == true,
                weakCode = manager.canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_WEAK),
                strongCode = manager.canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_STRONG),
                probe = ::probe,
            )
        } catch (e: Exception) {
            Log.w(TAG) { "capability check failed: ${e.javaClass.simpleName}" }
            BiometricStatus.UNAVAILABLE
        }
    }

    override fun refresh() {
        cachedProbe = null
    }

    private fun probe(): CapabilityClassifier.Probe? {
        cachedProbe?.let { return it }
        synchronized(probeLock) {
            cachedProbe?.let { return it }
            val result = try {
                val verdict = keyStore.create(PROBE_ALIAS)
                val refuses = verdict is KeyVerdict.Accept && keyStore.refusesUnauthenticatedUse(PROBE_ALIAS)
                CapabilityClassifier.Probe(verdict, refuses)
            } catch (e: Exception) {
                Log.w(TAG) { "probe failed: ${e.javaClass.simpleName}" }
                null
            } finally {
                keyStore.delete(PROBE_ALIAS)
            }
            if (result?.accepted == true) cachedProbe = result
            return result
        }
    }

    companion object {
        private const val TAG = "BiometricCapability"

        /** Keystore alias of the throw-away probe key. */
        const val PROBE_ALIAS = "ownbit_bio_probe_v1"
    }
}
