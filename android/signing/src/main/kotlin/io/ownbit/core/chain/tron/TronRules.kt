// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.chain.tron

/** The TRON constants signing and verification use (iOS `BILTRXSendModel.swift`, the TRX bundle's defaults). */
object TronRules {
    /** iOS `ASSET_TYPE_TRX`. */
    const val ASSET_TYPE_TRX: Int = 0

    /** iOS `ASSET_TYPE_TRC10`. */
    const val ASSET_TYPE_TRC10: Int = 1

    /** iOS `ASSET_TYPE_TRC20`. */
    const val ASSET_TYPE_TRC20: Int = 2

    /** TRC20 `approve` (balance management), built by the same bundle function. */
    const val ASSET_TYPE_TRC20_APPROVE: Int = 20

    /** The bundle's TRC20 `fee_limit` (150 TRX in SUN). */
    const val DEFAULT_FEE_LIMIT_SUN: Long = 150_000_000

    /** The bundle extends every transaction's expiration by 23 h (`_extendTx`). */
    const val EXPIRATION_EXTENSION_SECONDS: Long = 82_800
    const val EXPIRATION_EXTENSION_MILLIS: Long = EXPIRATION_EXTENSION_SECONDS * 1000
}
