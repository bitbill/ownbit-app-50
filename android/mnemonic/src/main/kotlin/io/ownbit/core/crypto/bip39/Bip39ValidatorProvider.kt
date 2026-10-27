// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.crypto.bip39

import android.content.Context
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.IOException

/**
 * App-wide [Bip39Validator], loaded once from the `bip39/mnemonic_words.txt` asset of this module.
 *
 * Loading rules:
 * - call [preload] at app start so the ~130 KB file is read off the main thread;
 * - when a decision is needed **now** (tapping "Next", the scanner's mnemonic interception) use [get] /
 *   [await]: if the preload has not finished they load synchronously instead of letting the input through;
 * - a load failure yields an unloaded validator (every check → [MnemonicIssue.WordlistUnavailable], i.e.
 *   reject) and is retried on the next call; only successful loads are cached.
 */
class Bip39ValidatorProvider(
    private val context: Context,
    private val ioDispatcher: CoroutineDispatcher,
) {
    @Volatile private var loaded: Bip39Validator? = null
    private val lock = Any()

    /** The validator, loading it synchronously if needed (a few ms). Avoid calling on the main thread. */
    fun get(): Bip39Validator {
        loaded?.let { return it }
        synchronized(lock) {
            loaded?.let { return it }
            val text = try {
                context.assets.open(Bip39Wordlists.ASSET_PATH).use { it.readBytes().toString(Charsets.UTF_8) }
            } catch (e: IOException) {
                null
            }
            val validator = Bip39Validator.fromWordlistText(text)
            if (validator.isLoaded) loaded = validator
            return validator
        }
    }

    /** [get] on the IO dispatcher. */
    suspend fun await(): Bip39Validator = loaded ?: withContext(ioDispatcher) { get() }

    /** The validator if it is already loaded, else null (for UI paths that must not block, e.g. live hints). */
    fun getIfLoaded(): Bip39Validator? = loaded

    /** Starts loading in [scope] (call once at app start). */
    fun preload(scope: CoroutineScope): Job = scope.launch(ioDispatcher) { get() }
}
