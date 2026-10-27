// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.crypto.biometric

import javax.crypto.Cipher

/** A cipher for one auth-per-use key, initialised but not yet authenticated. */
sealed interface CipherResult {
    /** Hand [cipher] to `BiometricPrompt.CryptoObject`; only after the prompt succeeded may it be used. */
    class Ready(val cipher: Cipher) : CipherResult

    /**
     * The key can never be used again (`KeyPermanentlyInvalidatedException` — enrolment changed, screen lock removed —
     * or `UnrecoverableKeyException`): turn the feature off for its owner.
     */
    data object Invalidated : CipherResult

    /** No key under the alias (deleted, Keystore reset). Treated like [Invalidated] by the owner. */
    data object Missing : CipherResult

    /** Any other Keystore failure (possibly transient). Never logged with values. */
    data class Failed(val cause: Throwable) : CipherResult
}

/**
 * Per-alias AES-256-GCM keys that require **Class 3 biometric authentication for every use**: created
 * StrongBox first, then TEE; accepted only when [KeyInfoRules] accepts the real `KeyInfo`, otherwise deleted again.
 * Every method may run on any thread (Keystore calls block: call off the main thread).
 */
interface BiometricKeyStore {
    /** Creates (replacing any old entry) the key under [alias]; [KeyVerdict.Reject] → nothing is left under [alias]. */
    fun create(alias: String): KeyVerdict

    /**
     * Negative probe: `true` only when an ENCRYPT operation **without** authentication is refused by the Keystore
     * (`UserNotAuthenticatedException`, or `IllegalBlockSizeException` caused by a Keystore error). `false` when it
     * succeeded or failed for any other reason (not provable).
     */
    fun refusesUnauthenticatedUse(alias: String): Boolean

    /** An ENCRYPT cipher of [alias] for a `CryptoObject`. */
    fun encryptCipher(alias: String): CipherResult

    /** A DECRYPT cipher of [alias] with the GCM [iv] used at encryption. */
    fun decryptCipher(alias: String, iv: ByteArray): CipherResult

    /** Deletes [alias] (no-op when absent; never throws). */
    fun delete(alias: String)

    /** Whether [alias] exists (errors read as `false`). */
    fun exists(alias: String): Boolean

    /** Every alias starting with [prefix] (cleanup of orphaned keys); empty on errors. */
    fun aliases(prefix: String): List<String> = emptyList()
}
