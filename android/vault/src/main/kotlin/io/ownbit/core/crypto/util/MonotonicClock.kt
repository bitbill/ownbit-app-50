// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.crypto.util

import android.os.SystemClock

/**
 * Monotonic time source (milliseconds since boot, including deep sleep). Unlike [WallClock] it cannot be moved
 * by the user changing the date/time settings, so security timers (PIN lockout) measure elapsed time with it.
 * It restarts from 0 after a reboot.
 */
fun interface MonotonicClock {
    /** Milliseconds since boot (`SystemClock.elapsedRealtime()` on Android). */
    fun elapsedMillis(): Long
}

/** [MonotonicClock] backed by [SystemClock.elapsedRealtime]. */
object SystemMonotonicClock : MonotonicClock {
    override fun elapsedMillis(): Long = SystemClock.elapsedRealtime()
}
