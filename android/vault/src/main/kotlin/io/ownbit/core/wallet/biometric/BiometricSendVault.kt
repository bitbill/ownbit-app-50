// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.wallet.biometric

import android.security.keystore.KeyPermanentlyInvalidatedException
import io.ownbit.core.common.log.Log
import io.ownbit.core.crypto.biometric.BiometricCapability
import io.ownbit.core.crypto.biometric.BiometricCapabilityChecker
import io.ownbit.core.crypto.biometric.BiometricKeyStore
import io.ownbit.core.crypto.biometric.BiometricStatus
import io.ownbit.core.crypto.biometric.CipherResult
import io.ownbit.core.crypto.biometric.KeySecurityLevel
import io.ownbit.core.crypto.biometric.KeyVerdict
import io.ownbit.core.crypto.hash.Hashes
import io.ownbit.core.crypto.util.Hex
import io.ownbit.core.crypto.util.MonotonicClock
import io.ownbit.core.crypto.util.SecureRandoms
import io.ownbit.core.crypto.util.Secrets
import io.ownbit.core.crypto.util.WallClock
import io.ownbit.core.crypto.util.wipe
import io.ownbit.core.wallet.WalletError
import io.ownbit.core.wallet.WalletResult
import io.ownbit.core.wallet.secret.SecretVault
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.withContext
import java.security.GeneralSecurityException
import java.security.ProviderException
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean
import javax.crypto.AEADBadTagException
import javax.crypto.Cipher

/** Result of [BiometricSendVault.beginEnable]. */
sealed interface EnableStart {
    /** Show the Class 3 prompt with [EnableTicket.cipher], then [BiometricSendVault.finishEnable] / `cancelEnable`. */
    class Ready(val ticket: EnableTicket) : EnableStart

    data object EmptyPassword : EnableStart

    /** Counted like every wallet-password dialog; [suggestReimport] after 3 in a row. */
    data class WrongPassword(val suggestReimport: Boolean) : EnableStart

    /** The device (or this wallet's own key) is not eligible for quick send: [status] says why. Nothing was stored. */
    data class NotEligible(val status: BiometricStatus) : EnableStart

    /** Wallet missing / not eligible / Keystore failure. Nothing was stored. */
    data object Failed : EnableStart
}

/**
 * An enable in progress: the wallet's new auth-per-use key exists and [cipher] is its ENCRYPT cipher for the prompt's
 * `CryptoObject`. Holds a copy of the verified password until [BiometricSendVault.finishEnable] /
 * [BiometricSendVault.cancelEnable] (single use; both wipe it). Never logged.
 */
class EnableTicket internal constructor(
    val walletId: String,
    internal val alias: String,
    password: CharArray,
    val cipher: Cipher,
    internal val level: KeySecurityLevel,
    internal val issuedAt: Long,
) {
    private val claimed = AtomicBoolean(false)
    private var password: CharArray? = password

    internal fun claim(): Boolean = claimed.compareAndSet(false, true)

    /**
     * UTF-8 copy of the password taken under the ticket's lock (a concurrent [wipe] can never hand out a half-zeroed
     * array); `null` once wiped (background, TTL, finish, cancel). The caller wipes the copy.
     */
    internal fun passwordUtf8(): ByteArray? = synchronized(this) { password?.let(Secrets::utf8) }

    /** Whether the password copy is gone (tests). */
    internal val isWiped: Boolean get() = synchronized(this) { password == null }

    /** Wipes the password copy; the ticket can no longer finish. Idempotent, any thread. */
    internal fun wipe() = synchronized(this) {
        password?.wipe()
        password = null
    }

    override fun toString(): String = "EnableTicket(walletId=$walletId)"
}

/** Result of [BiometricSendVault.beginUnlock]. */
sealed interface UnlockStart {
    /** Show the Class 3 prompt with [UnlockTicket.cipher], then [BiometricSendVault.completeUnlock] / `discard`. */
    class Ready(val ticket: UnlockTicket) : UnlockStart

    /** Quick send is not on for this wallet (or the master switch is off): use the password. */
    data object Off : UnlockStart

    /** The key was invalidated: quick send was just turned off for the wallet; show [notice], then the password. */
    data class TurnedOff(val notice: QuickSendOffNotice) : UnlockStart

    /** Keystore failure (possibly transient); quick send stays on. Use the password this time. */
    data object Failed : UnlockStart
}

/** A DECRYPT cipher of the wallet's key for the prompt (single use). No secret inside. */
class UnlockTicket internal constructor(
    val walletId: String,
    internal val ciphertext: ByteArray,
    val cipher: Cipher,
    internal val issuedAt: Long,
) {
    private val claimed = AtomicBoolean(false)

    internal fun claim(): Boolean = claimed.compareAndSet(false, true)

    override fun toString(): String = "UnlockTicket(walletId=$walletId)"
}

/** Result of [BiometricSendVault.completeUnlock]. */
sealed interface GrantResult {
    class Granted(val grant: BiometricGrant) : GrantResult

    /** Invalidated key / changed password: quick send was turned off for the wallet; show [notice], then the password. */
    data class TurnedOff(val notice: QuickSendOffNotice) : GrantResult

    /** Not authorised (wrong / reused ticket, Keystore refused, no secret): nothing unwrapped. Use the password. */
    data object Failed : GrantResult
}

/**
 * Which wallets may use biometric quick send (a stub interface over the app's wallet table): hot wallets with a
 * mnemonic — never watch or private-key wallets, never cold wallets (they sign offline, password only). `false` also
 * when the wallet does not exist (any more).
 */
fun interface QuickSendEligibility {
    suspend fun isEligible(walletId: String): Boolean
}

/**
 * Biometric quick send per wallet. Each enabled wallet has its own Class 3 auth-per-use AES-GCM key
 * ([BiometricKeyStore], StrongBox → TEE, invalidated by enrolment) that wraps the **wallet password** — never a copy of
 * the mnemonic / seed. The password is only unwrapped inside a crypto-bound prompt, verified against the wallet
 * (existing `SecretVault` path, no attempt counting) and handed out as a single-use [BiometricGrant]; the signing
 * itself stays the existing password path.
 *
 * Lifecycle: enable = password verified → key created + `KeyInfo` accepted + negative probe → prompt → encrypt →
 * persist (all or nothing; any failure deletes the new key). Disable = key + record deleted. The master switch off
 * deletes all ([QuickSendSettingsStore.setMaster]). Invalidated keys / a password that no longer opens the wallet turn
 * the wallet off automatically with a notice. Password change / reset and wallet deletion call [disable].
 */
class BiometricSendVault(
    private val repo: QuickSendRepository,
    private val keyStore: BiometricKeyStore,
    private val capability: BiometricCapabilityChecker,
    private val secrets: SecretVault,
    private val wallets: QuickSendEligibility,
    private val grants: GrantRegistry,
    private val monotonic: MonotonicClock,
    private val wallClock: WallClock,
    private val io: CoroutineDispatcher,
) {

    /**
     * Aliases of enables in progress (between [beginEnable] and the end of [finishEnable] / [cancelEnable]) → issue
     * time (monotonic). Registered **before** the key is created and removed by [finishEnable] only **after** the
     * record is stored, so a key is always either registered here or referenced by a stored record (or being
     * deleted): [reconcile] lists the keys before it reads the records and never sweeps the key of a live enable. An
     * entry older than [TICKET_TTL_MILLIS] is abandoned and swept. [finishEnable] only starts while its entry is still
     * here, so a sweep or [disableAll] before it makes it fail cleanly.
     */
    private val pendingEnables = ConcurrentHashMap<String, Long>()

    /**
     * Step 1 of turning [walletId] on (the caller checked the capability and asked for the password; the master
     * switch must be on — else [EnableStart.Failed], also at [finishEnable] when it went off meanwhile). Verifies
     * [password] with attempt counting, creates the wallet's key and checks it (KeyInfo + negative probe), and returns
     * the ENCRYPT cipher for the prompt. Keeps its own copy of the password; the caller still wipes [password].
     */
    suspend fun beginEnable(walletId: String, password: CharArray): EnableStart {
        val status = capability.status()
        if (!status.canAuthorizeTransactions) return EnableStart.NotEligible(status)
        // Wallet switches exist only under the master switch (iOS): master off = no record survives.
        if (!repo.snapshot().settings.masterOn) return EnableStart.Failed
        if (!wallets.isEligible(walletId)) return EnableStart.Failed
        if (password.isEmpty()) return EnableStart.EmptyPassword
        val field = secrets.verificationField(walletId) ?: return EnableStart.Failed
        when (val verified = secrets.use(walletId, password, setOf(field)) { WalletResult.Ok(Unit) }) {
            is WalletResult.Ok -> Unit
            is WalletResult.Err -> return when (val e = verified.error) {
                is WalletError.WrongPassword -> EnableStart.WrongPassword(e.suggestReimport)
                WalletError.EmptyPassword -> EnableStart.EmptyPassword
                else -> EnableStart.Failed
            }
        }
        val alias = newAlias(walletId)
        val issuedAt = monotonic.elapsedMillis()
        pendingEnables[alias] = issuedAt
        val notEligible = EnableStart.NotEligible(status.copy(capability = BiometricCapability.STRONG_NO_HW_KEY, keyLevel = null))
        val start = withContext(io) {
            val level = when (val verdict = keyStore.create(alias)) {
                is KeyVerdict.Reject -> {
                    capability.refresh()
                    return@withContext notEligible
                }
                is KeyVerdict.Accept -> verdict.level
            }
            if (!keyStore.refusesUnauthenticatedUse(alias)) {
                keyStore.delete(alias)
                capability.refresh()
                return@withContext notEligible
            }
            when (val c = keyStore.encryptCipher(alias)) {
                is CipherResult.Ready -> {
                    val ticket = EnableTicket(walletId, alias, password.copyOf(), c.cipher, level, issuedAt)
                    // The copy lives only while the prompt is open: wiped on background or after the ticket TTL.
                    grants.trackEnable(ticket, TICKET_TTL_MILLIS)
                    EnableStart.Ready(ticket)
                }
                else -> {
                    keyStore.delete(alias)
                    EnableStart.Failed
                }
            }
        }
        if (start !is EnableStart.Ready) pendingEnables.remove(alias)
        return start
    }

    /**
     * Step 2: [authenticated] is the cipher the successful Class 3 prompt returned (must be [EnableTicket.cipher]).
     * Encrypts the password and persists the record. `false` → nothing persisted, the key is deleted
     * (the switch stays off). The ticket is consumed and wiped either way.
     */
    suspend fun finishEnable(ticket: EnableTicket, authenticated: Cipher): Boolean {
        if (!ticket.claim()) return false
        try {
            // Still registered = not swept as abandoned and not removed by disableAll in the meantime. The entry stays
            // until the record is stored (finally below): a reconcile running meanwhile must not sweep the new key.
            val live = pendingEnables[ticket.alias] == ticket.issuedAt
            if (!live || authenticated !== ticket.cipher || monotonic.elapsedMillis() - ticket.issuedAt > TICKET_TTL_MILLIS) {
                withContext(io) { keyStore.delete(ticket.alias) }
                return false
            }
            // Wiped meanwhile (app went to the background, TTL): the enable is void — its key goes too.
            val bytes = ticket.passwordUtf8()
            if (bytes == null) {
                withContext(io) { keyStore.delete(ticket.alias) }
                return false
            }
            val sealed = try {
                withContext(io) {
                    authenticated.updateAAD(aad(ticket.walletId))
                    val ct = authenticated.doFinal(bytes)
                    val iv = authenticated.iv
                    if (iv == null || iv.size != GCM_IV_BYTES || ct.size != bytes.size + GCM_TAG_BYTES) null else iv to ct
                }
            } catch (e: Exception) {
                Log.w(TAG) { "enable encrypt failed: ${e.javaClass.simpleName}" }
                null
            } finally {
                bytes.wipe()
            }
            if (sealed == null || !repo.snapshot().settings.masterOn) {
                withContext(io) { keyStore.delete(ticket.alias) }
                return false
            }
            val record = QuickSendRecord(
                walletId = ticket.walletId,
                alias = ticket.alias,
                iv = Hex.encode(sealed.first),
                ct = Hex.encode(sealed.second),
                level = ticket.level.name,
                createdAtMillis = wallClock.nowMillis(),
            )
            val put = repo.putRecord(record)
            if (!put.written) {
                withContext(io) { keyStore.delete(ticket.alias) }
                return false
            }
            put.replacedAlias?.let { old -> withContext(io) { keyStore.delete(old) } }
            return true
        } finally {
            // Only now (record stored or the key deleted): see pendingEnables.
            pendingEnables.remove(ticket.alias, ticket.issuedAt)
            grants.untrack(ticket)
            ticket.wipe()
        }
    }

    /** The prompt was cancelled / failed: deletes the new key and wipes the password copy. */
    fun cancelEnable(ticket: EnableTicket) {
        if (ticket.claim()) {
            pendingEnables.remove(ticket.alias)
            keyStore.delete(ticket.alias)
        }
        grants.untrack(ticket)
        ticket.wipe()
    }

    /**
     * Turns [walletId] off: deletes its key (always, even if the record cannot be rewritten) and its record. For
     * [QuickSendOffReason.PASSWORD_CHANGED] / [QuickSendOffReason.PASSWORD_RESET] /
     * [QuickSendOffReason.INVALIDATED] a notice is kept for the next send. No-op when it was not on.
     */
    suspend fun disable(walletId: String, reason: QuickSendOffReason) {
        turnOff(walletId, reason, keepNotice = reason in PENDING_NOTICE_REASONS)
    }

    /** Turns every wallet off (keys + records); the master switch and threshold stay. */
    suspend fun disableAll(reason: QuickSendOffReason) {
        // Enables in progress fail too (their finishEnable finds no pending entry).
        pendingEnables.clear()
        val removed = repo.removeAll()
        withContext(io) {
            removed.forEach { keyStore.delete(it.alias) }
            keyStore.aliases(ALIAS_PREFIX).forEach { keyStore.delete(it) }
        }
    }

    /**
     * Security page open (and any time): deletes orphaned keys (never the key of an enable in progress, see
     * [pendingEnables]), drops records of wallets that are gone or not
     * eligible, and turns off wallets whose key is invalidated (init-only probe, no prompt). Returns the notices of
     * the wallets turned off for [QuickSendOffReason.INVALIDATED] (shown by the caller; not kept for the next send).
     */
    suspend fun reconcile(): List<QuickSendOffNotice> {
        val now = monotonic.elapsedMillis()
        // Keys and their in-flight state first, records second: an enable stores its record before it leaves
        // pendingEnables, so a listed key that is not pending (any more) is either in the records read below or a
        // real orphan. A live enable keeps its key; an abandoned one (older than the ticket TTL) is swept.
        val candidates = withContext(io) {
            keyStore.aliases(ALIAS_PREFIX).filter { alias ->
                val issuedAt = pendingEnables[alias]
                issuedAt == null || (now - issuedAt > TICKET_TTL_MILLIS && pendingEnables.remove(alias, issuedAt))
            }
        }
        val snapshot = repo.snapshot()
        val records = if (snapshot.corrupt) emptyList() else snapshot.file.wallets
        val known = records.mapTo(HashSet()) { it.alias }
        withContext(io) {
            for (alias in candidates) if (alias !in known) keyStore.delete(alias)
        }
        val notices = ArrayList<QuickSendOffNotice>()
        for (record in records) {
            if (!wallets.isEligible(record.walletId)) {
                turnOff(record.walletId, QuickSendOffReason.WALLET_DELETED, keepNotice = false)
                continue
            }
            val iv = Hex.decodeOrNull(record.iv)
            val probe = if (iv == null) CipherResult.Invalidated else withContext(io) { keyStore.decryptCipher(record.alias, iv) }
            when (probe) {
                CipherResult.Invalidated, CipherResult.Missing -> {
                    turnOff(record.walletId, QuickSendOffReason.INVALIDATED, keepNotice = false)
                    notices += QuickSendOffNotice(record.walletId, QuickSendOffReason.INVALIDATED)
                }
                is CipherResult.Ready, is CipherResult.Failed -> Unit
            }
        }
        return notices
    }

    /**
     * Step 1 of a biometric authorisation: the DECRYPT cipher of [walletId]'s key for the prompt. An invalidated /
     * missing key turns the wallet off here ([UnlockStart.TurnedOff]).
     */
    suspend fun beginUnlock(walletId: String): UnlockStart {
        val snapshot = repo.snapshot()
        if (snapshot.corrupt || !snapshot.file.masterOn) return UnlockStart.Off
        val record = snapshot.file.record(walletId) ?: return UnlockStart.Off
        // A record of a wallet that is gone or no longer eligible (e.g. a cold wallet enabled before cold wallets were
        // left out): dropped silently, the password signs (reconcile would drop it too).
        if (!wallets.isEligible(walletId)) {
            turnOff(walletId, QuickSendOffReason.WALLET_DELETED, keepNotice = false)
            return UnlockStart.Off
        }
        val iv = Hex.decodeOrNull(record.iv)
        val ct = Hex.decodeOrNull(record.ct)
        if (iv == null || ct == null || ct.size <= GCM_TAG_BYTES) return UnlockStart.TurnedOff(autoOff(walletId, QuickSendOffReason.CORRUPT))
        return when (val c = withContext(io) { keyStore.decryptCipher(record.alias, iv) }) {
            is CipherResult.Ready -> UnlockStart.Ready(UnlockTicket(walletId, ct, c.cipher, monotonic.elapsedMillis()))
            CipherResult.Invalidated, CipherResult.Missing ->
                UnlockStart.TurnedOff(autoOff(walletId, QuickSendOffReason.INVALIDATED))
            is CipherResult.Failed -> UnlockStart.Failed
        }
    }

    /**
     * Step 2: [authenticated] is the cipher the successful Class 3 prompt returned (must be [UnlockTicket.cipher]).
     * Unwraps the password, checks it against the wallet (no attempt counting) and returns a single-use grant bound to
     * [digest]. A password that no longer opens the wallet turns quick send off ([QuickSendOffReason.PASSWORD_CHANGED]).
     */
    suspend fun completeUnlock(ticket: UnlockTicket, authenticated: Cipher, digest: String): GrantResult {
        if (!ticket.claim()) return GrantResult.Failed
        if (authenticated !== ticket.cipher || monotonic.elapsedMillis() - ticket.issuedAt > TICKET_TTL_MILLIS) {
            return GrantResult.Failed
        }
        val walletId = ticket.walletId
        val plain = try {
            withContext(io) {
                authenticated.updateAAD(aad(walletId))
                authenticated.doFinal(ticket.ciphertext)
            }
        } catch (e: AEADBadTagException) {
            return GrantResult.TurnedOff(autoOff(walletId, QuickSendOffReason.INVALIDATED))
        } catch (e: KeyPermanentlyInvalidatedException) {
            return GrantResult.TurnedOff(autoOff(walletId, QuickSendOffReason.INVALIDATED))
        } catch (e: GeneralSecurityException) {
            Log.w(TAG) { "unwrap refused: ${e.javaClass.simpleName}" }
            return GrantResult.Failed
        } catch (e: ProviderException) {
            Log.w(TAG) { "unwrap refused: ${e.javaClass.simpleName}" }
            return GrantResult.Failed
        } catch (e: IllegalStateException) {
            Log.w(TAG) { "unwrap refused: ${e.javaClass.simpleName}" }
            return GrantResult.Failed
        }
        val password = try {
            Secrets.utf8Chars(plain)
        } finally {
            plain.wipe()
        } ?: return GrantResult.TurnedOff(autoOff(walletId, QuickSendOffReason.CORRUPT))
        val field = secrets.verificationField(walletId)
        if (field == null) {
            password.wipe()
            return GrantResult.Failed
        }
        when (val opened = secrets.open(walletId, password, setOf(field))) {
            is SecretVault.Opened.Ok -> opened.secrets.wipe()
            SecretVault.Opened.WrongPassword -> {
                password.wipe()
                return GrantResult.TurnedOff(autoOff(walletId, QuickSendOffReason.PASSWORD_CHANGED))
            }
            SecretVault.Opened.NoSecret, is SecretVault.Opened.Unavailable -> {
                password.wipe()
                return GrantResult.Failed
            }
        }
        return GrantResult.Granted(grants.issue(walletId, digest, password))
    }

    /** The prompt was not used (negative button, cancel, lockout): the ticket is consumed. */
    fun discard(ticket: UnlockTicket) {
        ticket.claim()
    }

    /** The pending automatic-off notice of [walletId], once (the next send shows it before the password dialog). */
    suspend fun consumeNotice(walletId: String): QuickSendOffNotice? = repo.consumeNotice(walletId)

    private suspend fun autoOff(walletId: String, reason: QuickSendOffReason): QuickSendOffNotice {
        turnOff(walletId, reason, keepNotice = false)
        return QuickSendOffNotice(walletId, reason)
    }

    private suspend fun turnOff(walletId: String, reason: QuickSendOffReason, keepNotice: Boolean) {
        val record = repo.snapshot().file.record(walletId)
        if (record != null) withContext(io) { keyStore.delete(record.alias) }
        repo.removeRecord(walletId, if (keepNotice) reason else null)
    }

    private fun newAlias(walletId: String): String =
        ALIAS_PREFIX + Hashes.sha256Hex(walletId).take(ALIAS_HASH_CHARS) + "_" + SecureRandoms.string(ALIAS_NONCE_CHARS)

    companion object {
        private const val TAG = "BiometricSendVault"

        /** Keystore alias prefix of the per-wallet keys (`<prefix><16 hex of sha256(walletId)>_<nonce>`). */
        const val ALIAS_PREFIX = "ownbit_bio_send_v1_"
        private const val ALIAS_HASH_CHARS = 16
        private const val ALIAS_NONCE_CHARS = 8
        private const val GCM_IV_BYTES = 12
        private const val GCM_TAG_BYTES = 16

        /** A ticket older than this (prompt left open) is refused. */
        const val TICKET_TTL_MILLIS: Long = 5 * 60_000L

        private val PENDING_NOTICE_REASONS = setOf(
            QuickSendOffReason.PASSWORD_CHANGED,
            QuickSendOffReason.PASSWORD_RESET,
            QuickSendOffReason.INVALIDATED,
        )

        /** GCM associated data binding a wrapped password to its wallet. */
        internal fun aad(walletId: String): ByteArray = ("ownbit.biosend.v1|$walletId").toByteArray(Charsets.UTF_8)
    }
}
