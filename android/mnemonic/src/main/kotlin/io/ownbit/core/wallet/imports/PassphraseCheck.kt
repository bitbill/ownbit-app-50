// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.wallet.imports

/**
 * Rows of the "Check addresses" dialog of a passphrase import, in display order (iOS `derivePassphrasePreview`): BTC Taproot (BIP86) / native SegWit (BIP84) / nested SegWit (BIP49) / legacy (BIP44)
 * receive address 0, then ETH (index 0), TRX, SOL.
 */
enum class PassphraseAddressKind { BTC_TAPROOT, BTC_NATIVE_SEGWIT, BTC_NESTED_SEGWIT, BTC_LEGACY, ETH, TRX, SOL }

/** One public address of the check dialog. */
data class PassphraseCheckRow(val kind: PassphraseAddressKind, val address: String)

/**
 * The first addresses of the passphrase seed, for the user to compare with the wallet they expect (a wrong passphrase
 * is simply another, empty wallet). Always 7 rows in [PassphraseAddressKind] order; public addresses only, no secret.
 */
data class PassphraseCheck(val rows: List<PassphraseCheckRow>) {

    /** Address of [kind]. */
    fun address(kind: PassphraseAddressKind): String = rows.first { it.kind == kind }.address
}
