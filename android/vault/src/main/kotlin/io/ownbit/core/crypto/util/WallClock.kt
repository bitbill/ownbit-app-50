// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.crypto.util

/**
 * Wall-clock time source (epoch milliseconds). Injected so time-based rules (PIN lockout) can be tested
 * with a fake clock.
 */
fun interface WallClock {
    /** Current time in milliseconds since the Unix epoch. */
    fun nowMillis(): Long
}

/** [WallClock] backed by [System.currentTimeMillis]. */
object SystemWallClock : WallClock {
    override fun nowMillis(): Long = System.currentTimeMillis()
}
