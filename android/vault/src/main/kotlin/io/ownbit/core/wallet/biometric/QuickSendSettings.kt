// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.wallet.biometric

import kotlinx.coroutines.flow.StateFlow

/**
 * Biometric quick send settings (no secrets). Everything is OFF by default. [enabledWalletIds] are the
 * wallets whose password is currently wrapped by their own auth-per-use Keystore key.
 *
 * @property thresholdUsd large-transfer protection (iOS `reminder_threshold`): global, whole USD; a transaction worth
 *   this much or more needs the wallet password too (`>=`). `0` = everything is "large".
 */
data class QuickSendSettings(
    val masterOn: Boolean = false,
    val thresholdUsd: Long = QuickSendThresholds.DEFAULT_USD,
    val enabledWalletIds: Set<String> = emptySet(),
)

/** The iOS large-transfer-protection options (`BILLargeAssetsReminder`), in USD. */
object QuickSendThresholds {
    const val DEFAULT_USD: Long = 1_000L

    /** The 14 iOS options in display order (0 = every transfer is "large"). */
    val OPTIONS_USD: List<Long> = listOf(
        0L, 100L, 200L, 500L, 1_000L, 2_000L, 5_000L, 10_000L, 20_000L, 50_000L, 100_000L, 200_000L, 500_000L, 1_000_000L,
    )

    /** Whether [usd] is one of [OPTIONS_USD]. */
    fun isOption(usd: Long): Boolean = usd in OPTIONS_USD
}

/**
 * The persisted quick-send settings (`noBackupFilesDir/biometric/quick_send.enc`, encrypted with a non-auth Keystore
 * record key). [settings] starts with the defaults and follows the file once it was read; an unreadable file reads
 * as "all off" (fail closed).
 */
interface QuickSendSettingsStore {
    val settings: StateFlow<QuickSendSettings>

    /**
     * Master switch. Turning it **off** deletes every wallet's Keystore key and wrapped password: a later "on" starts
     * with every wallet off. `false` when the file could not be written (nothing changed).
     */
    suspend fun setMaster(on: Boolean): Boolean

    /**
     * Sets the threshold; only [QuickSendThresholds.OPTIONS_USD] values are accepted. The caller has done the checks
     * (biometric prompt; wallet password when raising it while a wallet is enabled). `false` when refused / not
     * written.
     */
    suspend fun setThresholdUsd(usd: Long): Boolean
}

/** Why a wallet's quick send was turned off. [wireName] goes to the security log (`reason` flag). */
enum class QuickSendOffReason(val wireName: String) {
    /** The user turned the wallet's switch off. */
    USER("user"),

    /** The master switch went off (every wallet). */
    MASTER_OFF("master_off"),

    /** The Keystore key is gone or permanently invalidated (enrolment changed, screen lock removed, Keystore reset). */
    INVALIDATED("invalidated"),

    /** The wallet password was changed (the wrapped one no longer opens the wallet). */
    PASSWORD_CHANGED("password_changed"),

    /** The wallet password was reset by importing the mnemonic / key again. */
    PASSWORD_RESET("password_reset"),

    /** The wallet was deleted (or is no longer eligible). */
    WALLET_DELETED("wallet_deleted"),

    /** The stored record could not be read. */
    CORRUPT("corrupt"),
}

/** A notice to show once: [walletId]'s quick send was turned off automatically for [reason]. */
data class QuickSendOffNotice(val walletId: String, val reason: QuickSendOffReason)
