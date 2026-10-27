// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.wallet.secret

import java.util.concurrent.ConcurrentHashMap

/**
 * Consecutive wrong wallet-password attempts per wallet, in memory for the process lifetime: after 3 in a row the UI
 * suggests re-importing the recovery phrase. iOS keeps the count per password dialog; Android keeps it per wallet so the
 * hint survives re-opening the prompt. A correct password resets the count.
 *
 * Every password check of [SecretVault.use] goes through this tracker; UIs read the fields of
 * [io.ownbit.core.wallet.WalletError.WrongPassword] instead of counting themselves.
 */
class PasswordAttemptTracker {

    private val failures = ConcurrentHashMap<String, Int>()

    /** Records a wrong password for [walletId]; returns the new consecutive count. */
    fun recordFailure(walletId: String): Int = failures.merge(walletId, 1, Int::plus) ?: 1

    /** Forgets the failures of [walletId] (correct password, wallet deleted). */
    fun reset(walletId: String) {
        failures.remove(walletId)
    }

    /** Current consecutive wrong attempts of [walletId]. */
    fun attempts(walletId: String): Int = failures[walletId] ?: 0

    /** Whether the "re-import the mnemonic" hint must be shown after [attempts] consecutive failures. */
    fun suggestsReimport(attempts: Int): Boolean = attempts >= REIMPORT_HINT_THRESHOLD

    companion object {
        /** Consecutive wrong attempts after which the UI suggests re-importing the mnemonic. */
        const val REIMPORT_HINT_THRESHOLD: Int = 3
    }
}
