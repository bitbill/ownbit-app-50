// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.wallet.biometric


/** First step of authorising a signing operation ([TxAuthorizer.start]). */
sealed interface TxAuthStart {
    /** The existing password dialog; show [notice] first when set (quick send was turned off automatically). */
    data class Password(val notice: QuickSendOffNotice?) : TxAuthStart

    /**
     * Show the Class 3 prompt with [UnlockTicket.cipher]; on success `BiometricSendVault.completeUnlock`. With
     * [thenPassword] (value `>=` threshold / unknown value) the grant is wiped unused and the password dialog follows;
     * otherwise the grant signs after `WalletAuthorizationPolicy.recheck`.
     */
    data class Biometric(val ticket: UnlockTicket, val thenPassword: Boolean) : TxAuthStart
}

/** [WalletAuthorizationPolicy.decide] + [BiometricSendVault.beginUnlock] in one call for the signing pages. */
class TxAuthorizer(
    private val policy: WalletAuthorizationPolicy,
    private val vault: BiometricSendVault,
) {
    suspend fun start(r: AuthorizationRequest): TxAuthStart =
        when (val decision = policy.decide(r)) {
            is AuthorizationDecision.PasswordOnly -> TxAuthStart.Password(
                if (decision.reason == PasswordReason.WALLET_OFF) vault.consumeNotice(r.walletId) else null,
            )
            AuthorizationDecision.BiometricOnly, AuthorizationDecision.BiometricThenPassword ->
                when (val unlock = vault.beginUnlock(r.walletId)) {
                    is UnlockStart.Ready ->
                        TxAuthStart.Biometric(unlock.ticket, thenPassword = decision == AuthorizationDecision.BiometricThenPassword)
                    is UnlockStart.TurnedOff -> TxAuthStart.Password(unlock.notice)
                    UnlockStart.Off, UnlockStart.Failed -> TxAuthStart.Password(null)
                }
        }
}
