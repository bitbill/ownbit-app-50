// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.common.log

/**
 * The only logger the core modules use.
 *
 * Never log mnemonics, seeds, private keys, passwords, PINs, or JS call arguments / results that carry them: the core
 * modules log function names, sizes, timings and exception class names only. Off by default; a host app turns it on
 * for debug builds (`Log.enabled = BuildConfig.DEBUG`).
 */
object Log {
    @Volatile
    @JvmStatic
    var enabled: Boolean = false

    inline fun d(tag: String, message: () -> String) {
        if (enabled) android.util.Log.d(tag, message())
    }

    inline fun w(tag: String, throwable: Throwable? = null, message: () -> String) {
        if (enabled) android.util.Log.w(tag, message(), throwable)
    }

    inline fun e(tag: String, throwable: Throwable? = null, message: () -> String) {
        if (enabled) android.util.Log.e(tag, message(), throwable)
    }
}
