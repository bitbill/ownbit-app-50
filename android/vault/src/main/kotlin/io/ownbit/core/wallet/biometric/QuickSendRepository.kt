// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.wallet.biometric

import android.content.Context
import io.ownbit.core.common.log.Log
import io.ownbit.core.crypto.biometric.BiometricKeyStore
import io.ownbit.core.crypto.pin.RecordCipher
import io.ownbit.core.crypto.pin.RecordCiphers
import io.ownbit.core.crypto.util.wipe
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.io.File
import java.security.GeneralSecurityException

/**
 * One wallet's wrapped password: `AES-GCM(auth-per-use key [alias], utf8(password), aad = "ownbit.biosend.v1|<id>")`.
 * [iv] / [ct] are hex. Never logged ([toString] is redacted).
 */
@Serializable
data class QuickSendRecord(
    @SerialName("id") val walletId: String,
    @SerialName("alias") val alias: String,
    @SerialName("iv") val iv: String,
    @SerialName("ct") val ct: String,
    /** `KeySecurityLevel` name of the key (diagnostics). */
    @SerialName("level") val level: String,
    @SerialName("at") val createdAtMillis: Long,
) {
    override fun toString(): String = "QuickSendRecord(walletId=$walletId, level=$level)"
}

/** The whole file (version 1). */
@Serializable
data class QuickSendFile(
    @SerialName("v") val version: Int = CURRENT_VERSION,
    @SerialName("master") val masterOn: Boolean = false,
    @SerialName("threshold") val thresholdUsd: Long = QuickSendThresholds.DEFAULT_USD,
    @SerialName("wallets") val wallets: List<QuickSendRecord> = emptyList(),
    /** walletId → [QuickSendOffReason] name of an automatic switch-off not shown yet (next send shows it once). */
    @SerialName("notices") val notices: Map<String, String> = emptyMap(),
) {
    fun record(walletId: String): QuickSendRecord? = wallets.firstOrNull { it.walletId == walletId }

    fun toSettings(): QuickSendSettings = QuickSendSettings(
        masterOn = masterOn,
        thresholdUsd = thresholdUsd,
        enabledWalletIds = wallets.mapTo(LinkedHashSet()) { it.walletId },
    )

    override fun toString(): String = "QuickSendFile(master=$masterOn, threshold=$thresholdUsd, wallets=${wallets.size})"

    companion object {
        const val CURRENT_VERSION = 1
    }
}

/** Snapshot for the vault / policy: [corrupt] = the file could not be read (everything reads as off). */
data class QuickSendSnapshot(val file: QuickSendFile, val corrupt: Boolean) {
    val settings: QuickSendSettings get() = if (corrupt) QuickSendSettings() else file.toSettings()
}

/**
 * [QuickSendSettingsStore] + the per-wallet records, in `noBackupFilesDir/biometric/quick_send.enc` (never backed
 * up; `allowBackup=false` anyway), encrypted with the non-auth Keystore record key `ownbit_bio_settings_v1`
 * (`RecordCiphers.keystoreAesGcm`, `replaceUnusableKey = false`). Written atomically (temp file + rename) under one
 * mutex.
 *
 * Unreadable file (lost / reset record key, corrupt bytes, unknown format) → [QuickSendSnapshot.corrupt]: every switch
 * reads as off (fail closed) until the next successful write, which first drops the unusable record key; the
 * per-wallet keys it referenced become orphans that `BiometricSendVault.reconcile` deletes.
 */
class QuickSendRepository(
    private val file: File,
    private val cipher: RecordCipher,
    private val keyStore: BiometricKeyStore,
    private val io: CoroutineDispatcher,
    scope: CoroutineScope,
) : QuickSendSettingsStore {

    /** The app's file (`noBackupFilesDir/biometric/quick_send.enc`) under the Keystore record key [KEY_ALIAS]. */
    constructor(
        context: Context,
        keyStore: BiometricKeyStore,
        io: CoroutineDispatcher,
        scope: CoroutineScope,
    ) : this(
        file = File(File(context.noBackupFilesDir, DIR), FILE_NAME),
        cipher = RecordCiphers.keystoreAesGcm(KEY_ALIAS, AAD, replaceUnusableKey = false),
        keyStore = keyStore,
        io = io,
        scope = scope,
    )

    private val mutex = Mutex()
    private var loaded: QuickSendSnapshot? = null
    private val _settings = MutableStateFlow(QuickSendSettings())
    override val settings: StateFlow<QuickSendSettings> = _settings.asStateFlow()

    init {
        scope.launch {
            try {
                snapshot()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                Log.w(TAG) { "initial load failed: ${e.javaClass.simpleName}" }
            }
        }
    }

    /** The current state (reads the file once per process). */
    suspend fun snapshot(): QuickSendSnapshot = mutex.withLock { loadLocked() }

    override suspend fun setMaster(on: Boolean): Boolean {
        var removed: List<QuickSendRecord> = emptyList()
        mutex.withLock {
            val current = loadLocked()
            if (!current.corrupt && current.file.masterOn == on) return true
            if (!on) removed = current.file.wallets
            val next = if (on) {
                current.file.copy(masterOn = true)
            } else {
                // Master off deletes every wallet's material; pending notices are moot.
                current.file.copy(masterOn = false, wallets = emptyList(), notices = emptyMap())
            }
            if (!writeLocked(next)) return false
        }
        // Material goes after the file no longer points to it (a failed write above changed nothing).
        withContext(io) { removed.forEach { keyStore.delete(it.alias) } }
        return true
    }

    override suspend fun setThresholdUsd(usd: Long): Boolean {
        if (!QuickSendThresholds.isOption(usd)) return false
        mutex.withLock {
            val current = loadLocked()
            if (!current.corrupt && current.file.thresholdUsd == usd) return true
            if (!writeLocked(current.file.copy(thresholdUsd = usd))) return false
        }
        return true
    }

    /**
     * Stores [record] (replacing the wallet's old one, whose alias is returned) and clears its pending notice. Refused
     * (`written = false`) while the master switch is off — checked under the same lock as [setMaster], so a record can
     * never survive "master off".
     */
    suspend fun putRecord(record: QuickSendRecord): PutResult = mutex.withLock {
        val current = loadLocked()
        if (current.corrupt || !current.file.masterOn) return@withLock PutResult(false, null)
        val old = current.file.record(record.walletId)
        val next = current.file.copy(
            wallets = current.file.wallets.filterNot { it.walletId == record.walletId } + record,
            notices = current.file.notices - record.walletId,
        )
        if (writeLocked(next)) PutResult(true, old?.alias?.takeIf { it != record.alias }) else PutResult(false, null)
    }

    /** Result of [putRecord]: [replacedAlias] = the previous key of the wallet, to delete. */
    data class PutResult(val written: Boolean, val replacedAlias: String?)

    /**
     * Removes [walletId]'s record and, when [notice] is set (and the master switch is on), remembers it for the next
     * send. Returns the removed record (or `null`); the write may fail — the caller deletes the key anyway.
     */
    suspend fun removeRecord(walletId: String, notice: QuickSendOffReason?): QuickSendRecord? = mutex.withLock {
        val current = loadLocked()
        val old = current.file.record(walletId)
        val notices = if (notice != null && current.file.masterOn && old != null) {
            current.file.notices + (walletId to notice.name)
        } else {
            current.file.notices - walletId
        }
        if (old == null && notices == current.file.notices) return@withLock null
        writeLocked(current.file.copy(wallets = current.file.wallets.filterNot { it.walletId == walletId }, notices = notices))
        old
    }

    /** Removes every record (keeps the master switch / threshold); returns them. */
    suspend fun removeAll(): List<QuickSendRecord> = mutex.withLock {
        val current = loadLocked()
        if (current.file.wallets.isEmpty() && current.file.notices.isEmpty()) return@withLock emptyList()
        writeLocked(current.file.copy(wallets = emptyList(), notices = emptyMap()))
        current.file.wallets
    }

    /** The pending automatic-off notice of [walletId] (removed: shown once). */
    suspend fun consumeNotice(walletId: String): QuickSendOffNotice? = mutex.withLock {
        val current = loadLocked()
        val raw = current.file.notices[walletId] ?: return@withLock null
        writeLocked(current.file.copy(notices = current.file.notices - walletId))
        val reason = QuickSendOffReason.entries.firstOrNull { it.name == raw } ?: return@withLock null
        if (current.file.masterOn) QuickSendOffNotice(walletId, reason) else null
    }

    private suspend fun loadLocked(): QuickSendSnapshot {
        loaded?.let { return it }
        val snap = withContext(io) { readFile() }
        loaded = snap
        _settings.value = snap.settings
        return snap
    }

    private fun readFile(): QuickSendSnapshot {
        if (!file.exists()) return QuickSendSnapshot(QuickSendFile(), corrupt = false)
        return try {
            val plain = cipher.decrypt(file.readBytes())
            try {
                val parsed = json.decodeFromString(QuickSendFile.serializer(), plain.toString(Charsets.UTF_8))
                if (parsed.version != QuickSendFile.CURRENT_VERSION) {
                    QuickSendSnapshot(QuickSendFile(), corrupt = true)
                } else {
                    val threshold = parsed.thresholdUsd.takeIf(QuickSendThresholds::isOption) ?: QuickSendThresholds.DEFAULT_USD
                    QuickSendSnapshot(parsed.copy(thresholdUsd = threshold), corrupt = false)
                }
            } finally {
                plain.wipe()
            }
        } catch (e: Exception) {
            // GeneralSecurityException (lost / reset key, tampering), IO, parse errors: fail closed.
            Log.w(TAG) { "quick send settings unreadable: ${e.javaClass.simpleName}" }
            QuickSendSnapshot(QuickSendFile(), corrupt = true)
        }
    }

    /** Writes [next]; on success it becomes the loaded state. `false` (state unchanged) on any failure. */
    private suspend fun writeLocked(next: QuickSendFile): Boolean {
        val wasCorrupt = loaded?.corrupt == true
        val ok = withContext(io) {
            try {
                if (wasCorrupt) {
                    // None of the old blobs can be read: drop the record key so a fresh one is created.
                    try {
                        cipher.deleteKey()
                    } catch (e: GeneralSecurityException) {
                        Log.w(TAG) { "record key not deleted: ${e.javaClass.simpleName}" }
                    }
                }
                val plain = json.encodeToString(QuickSendFile.serializer(), next).toByteArray(Charsets.UTF_8)
                val blob = try {
                    cipher.encrypt(plain)
                } finally {
                    plain.wipe()
                }
                file.parentFile?.mkdirs()
                val tmp = File(file.parentFile, file.name + ".tmp")
                tmp.writeBytes(blob)
                if (!tmp.renameTo(file)) {
                    tmp.delete()
                    throw java.io.IOException("rename failed")
                }
                true
            } catch (e: Exception) {
                Log.w(TAG) { "quick send settings not written: ${e.javaClass.simpleName}" }
                false
            }
        }
        if (ok) {
            val snap = QuickSendSnapshot(next, corrupt = false)
            loaded = snap
            _settings.value = snap.settings
        }
        return ok
    }

    companion object {
        private const val TAG = "QuickSendStore"
        const val DIR = "biometric"
        const val FILE_NAME = "quick_send.enc"

        /** Non-auth Keystore key of the file. */
        const val KEY_ALIAS = "ownbit_bio_settings_v1"
        private val AAD = "io.ownbit.biosend.settings.v1".toByteArray(Charsets.US_ASCII)

        private val json = Json {
            ignoreUnknownKeys = true
            encodeDefaults = true
        }
    }
}
