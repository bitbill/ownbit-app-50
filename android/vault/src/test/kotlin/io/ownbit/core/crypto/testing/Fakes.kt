// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.crypto.testing

import io.ownbit.core.crypto.hash.Hashes
import io.ownbit.core.crypto.keystore.DeviceKey
import io.ownbit.core.crypto.keystore.DeviceKeyException
import io.ownbit.core.crypto.keystore.DeviceKeyManager
import io.ownbit.core.crypto.util.Hex
import io.ownbit.core.crypto.util.MonotonicClock
import io.ownbit.core.crypto.util.SecureRandoms
import io.ownbit.core.crypto.util.WallClock

/**
 * Software stand-in for the Android Keystore device key.
 * @param iosFingerprint use iOS' `SHA256(deviceKey)[0..8]` fingerprint (to open envelopes produced by iOS code).
 */
class FakeDeviceKeyManager(
    var rawKey: ByteArray? = null,
    private val iosFingerprint: Boolean = false,
    var failing: Boolean = false,
) : DeviceKeyManager {
    var created = 0
        private set

    override fun peek(): DeviceKey? {
        if (failing) throw DeviceKeyException("keystore broken")
        return rawKey?.let { SoftwareDeviceKey(it, iosFingerprint) }
    }

    /** Synchronized like the Keystore implementation: concurrent first encryptions share one new key. */
    @Synchronized
    override fun getOrCreate(): DeviceKey {
        if (failing) throw DeviceKeyException("keystore broken")
        val key = rawKey ?: SecureRandoms.bytes(32).also {
            rawKey = it
            created++
        }
        return SoftwareDeviceKey(key, iosFingerprint)
    }
}

private class SoftwareDeviceKey(private val raw: ByteArray, private val iosFingerprint: Boolean) : DeviceKey {
    override fun hmacSha256(message: ByteArray): ByteArray = Hashes.hmacSha256(raw, message)

    override fun fingerprint(): String =
        if (iosFingerprint) Hex.encode(Hashes.sha256(raw), 0, 8) else super.fingerprint()
}

/**
 * Mutable wall + monotonic clock. [advance] is real time passing (both clocks move); [jumpWall] is the user
 * changing the date/time (only the wall clock moves); [reboot] restarts the monotonic clock.
 */
class FakeClock(
    var now: Long = 1_700_000_000_000L,
    var elapsed: Long = 3_600_000L,
) : WallClock, MonotonicClock {
    override fun nowMillis(): Long = now
    override fun elapsedMillis(): Long = elapsed

    fun advance(millis: Long) {
        require(millis >= 0) { "time only moves forward; use jumpWall for clock changes" }
        now += millis
        elapsed += millis
    }

    fun jumpWall(millis: Long) {
        now += millis
    }

    /** Device reboot after [downtimeMillis] powered off; the monotonic clock restarts at [bootElapsed]. */
    fun reboot(downtimeMillis: Long, bootElapsed: Long = 0L) {
        now += downtimeMillis
        elapsed = bootElapsed
    }
}
