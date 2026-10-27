// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.chain.xlm

/**
 * The Stellar operation a transaction carries — iOS `enum XLMTXType: Int` (`StellarJSBridge.swift`). The raw values
 * travel in `signDatas.buildType` of the offline-signing QR and must never change.
 */
enum class XlmTxType(val raw: Int, internal val jsSuffix: String) {
    /** `Operation.createAccount` — used when the destination account does not exist yet. */
    CREATE_ACCOUNT(0, "CreateAccount"),

    /** `Operation.setOptions({inflationDest})` — legacy; cold wallets still sign it. */
    SET_INFLATION(1, "SetInflation"),

    /** `Operation.payment` (native asset). */
    PAYMENT(2, "Payment"),
    ;

    companion object {
        fun fromRaw(raw: Long?): XlmTxType? = entries.firstOrNull { it.raw.toLong() == raw }
    }
}
