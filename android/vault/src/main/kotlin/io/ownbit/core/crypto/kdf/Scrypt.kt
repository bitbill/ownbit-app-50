// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.crypto.kdf

import io.ownbit.core.crypto.util.Hex
import io.ownbit.core.crypto.util.constantTimeEquals
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import kotlinx.coroutines.withContext

/**
 * scrypt with a native-first strategy: [primary] (libsodium) when it loads **and** passes a known-answer
 * self-test, otherwise [fallback] (BouncyCastle). Both produce identical output; the choice only affects
 * speed.
 *
 * - [derive] (suspend) runs on [dispatcher] (`Dispatchers.Default` in the app: KDFs never run on the main
 *   thread) and at most [maxConcurrent] derivations run at once (each N=32768/r=8 derivation
 *   needs 32 MiB).
 * - [deriveBlocking] is for callers already on a background thread.
 *
 * Construct via [Scrypt.nativeWithFallback] in production and [Scrypt.bouncyCastleOnly] in JVM tests.
 */
class Scrypt(
    private val primary: ScryptEngine?,
    private val fallback: ScryptEngine = BouncyCastleScryptEngine,
    private val dispatcher: CoroutineDispatcher = Dispatchers.Default,
    maxConcurrent: Int = 2,
) {
    private val permits = Semaphore(maxConcurrent)

    /** null = not probed yet, true = usable, false = permanently disabled for this process. */
    @Volatile private var primaryUsable: Boolean? = if (primary == null) false else null
    private val probeLock = Any()

    /** Name of the engine that will serve the next derivation (diagnostics only). */
    val activeEngineName: String
        get() = if (primaryUsable != false && primary != null) primary.name else fallback.name

    /**
     * Derives a key off the calling thread. The caller owns (and should wipe) the result; inputs are not
     * modified.
     * @throws ScryptException if every engine fails.
     */
    suspend fun derive(password: ByteArray, salt: ByteArray, params: ScryptParams): ByteArray =
        permits.withPermit {
            withContext(dispatcher) { deriveBlocking(password, salt, params) }
        }

    /**
     * Blocking variant of [derive]. Never call on the main thread.
     * @throws ScryptException if every engine fails.
     */
    fun deriveBlocking(password: ByteArray, salt: ByteArray, params: ScryptParams): ByteArray {
        val native = usablePrimary()
        if (native != null) {
            try {
                return native.derive(password, salt, params)
            } catch (e: ScryptException) {
                // Native rejected this call (e.g. allocation failure): answer it with the fallback.
            } catch (e: LinkageError) {
                primaryUsable = false
            } catch (e: RuntimeException) {
                primaryUsable = false
            }
        }
        return fallback.derive(password, salt, params)
    }

    private fun usablePrimary(): ScryptEngine? {
        val engine = primary ?: return null
        when (primaryUsable) {
            true -> return engine
            false -> return null
            null -> Unit
        }
        synchronized(probeLock) {
            if (primaryUsable == null) primaryUsable = passesKnownAnswerTest(engine)
            return if (primaryUsable == true) engine else null
        }
    }

    companion object {
        /** RFC 7914 §12 vector 2: scrypt("password", "NaCl", N=1024, r=8, p=16, dkLen=64). */
        private val KAT_PASSWORD = "password".toByteArray(Charsets.US_ASCII)
        private val KAT_SALT = "NaCl".toByteArray(Charsets.US_ASCII)
        private val KAT_PARAMS = ScryptParams(n = 1024, r = 8, p = 16, dkLen = 64)
        private val KAT_EXPECTED = Hex.decode(
            "fdbabe1c9d3472007856e7190d01e9fe7c6ad7cbc8237830e77376634b373162" +
                "2eaf30d92e22a3886ff109279d9830dac727afb94a83ee6d8360cbdfa2cc0640",
        )

        /** Runs the RFC 7914 known-answer test against [engine]; any failure or mismatch disables it. */
        internal fun passesKnownAnswerTest(engine: ScryptEngine): Boolean = try {
            constantTimeEquals(engine.derive(KAT_PASSWORD, KAT_SALT, KAT_PARAMS), KAT_EXPECTED)
        } catch (e: LinkageError) {
            false
        } catch (e: Exception) {
            false
        }

        /** Production instance: libsodium first, BouncyCastle fallback. */
        fun nativeWithFallback(dispatcher: CoroutineDispatcher = Dispatchers.Default): Scrypt =
            Scrypt(primary = SodiumScryptEngine(), fallback = BouncyCastleScryptEngine, dispatcher = dispatcher)

        /** BouncyCastle only (JVM unit tests, or when native code must be avoided). */
        fun bouncyCastleOnly(dispatcher: CoroutineDispatcher = Dispatchers.Default): Scrypt =
            Scrypt(primary = null, fallback = BouncyCastleScryptEngine, dispatcher = dispatcher)
    }
}
