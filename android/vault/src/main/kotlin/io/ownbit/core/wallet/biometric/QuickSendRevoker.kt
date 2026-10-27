// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.wallet.biometric

/**
 * What the password changer (and, in the app, the re-import reset and the wallet deleter) call to turn a wallet's
 * biometric quick send off: [BiometricSendVault.disable] in the app, [NONE] where those classes run without biometrics.
 */
fun interface QuickSendRevoker {
    suspend fun revoke(walletId: String, reason: QuickSendOffReason)

    companion object {
        val NONE = QuickSendRevoker { _, _ -> }
    }
}
