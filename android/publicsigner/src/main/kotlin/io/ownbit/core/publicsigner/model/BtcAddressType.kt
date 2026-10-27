// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.publicsigner.model

/** Ownbit's BTC address script types, as the app stores them for a wallet's accounts and addresses. */
object BtcAddressType {
    /** P2PKH, m/44'. */
    const val LEGACY: Int = 0

    /** P2SH-P2WPKH, m/49' (iOS `BTC_SW_P`). */
    const val NESTED_SEGWIT: Int = 1

    /** P2WPKH bech32, m/84' (iOS `BTC_SW_D`). */
    const val NATIVE_SEGWIT: Int = 2

    /** P2TR key-path bech32m `bc1p…`, m/86' (iOS `BTC_SW_T`). */
    const val TAPROOT: Int = 3
}
