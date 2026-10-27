// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.jsengine.chain

import io.ownbit.core.jsengine.JsBundle

/**
 * The 24 mainnets Ownbit Android 5.0 supports, as seen by the JS layer. Downstream modules map
 * `CoinType` (tokens included) to the mainnet here: e.g. ERC20 -> [ETH], TRC20 -> [TRX], SPL -> [SOL],
 * jetton -> [TON], `avax` / `avax20Token` -> [POLYGON].
 *
 * @property derivationBundle bundle that produces this chain's keys / addresses.
 * @property isEvm uses the shared ETH account (`m/44'/60'/0'/0/N`) and EVM address rules.
 */
enum class JsChain(val derivationBundle: JsBundle, val isEvm: Boolean = false) {
    BTC(JsBundle.BTC),
    ETH(JsBundle.ETH, isEvm = true),
    BSC(JsBundle.ETH, isEvm = true),
    TRX(JsBundle.TRX),
    SOL(JsBundle.SOL),
    BASE(JsBundle.ETH, isEvm = true),
    ARB(JsBundle.ETH, isEvm = true),
    HYPE(JsBundle.ETH, isEvm = true),
    TON(JsBundle.TON),
    OP(JsBundle.ETH, isEvm = true),

    /** Polygon (iOS `CoinType.avax`, symbol MATIC, displayed POL). */
    POLYGON(JsBundle.ETH, isEvm = true),

    /** Uses the BTC legacy xpub; the BCH bundle only converts addresses to CashAddr. */
    BCH(JsBundle.BTC),
    LTC(JsBundle.LTC),
    ETC(JsBundle.ETH, isEvm = true),
    DASH(JsBundle.DASH),
    DOGE(JsBundle.DOGE),
    DGB(JsBundle.DGB),
    ZEN(JsBundle.ZEN),
    XRP(JsBundle.XRP),
    XLM(JsBundle.XLM),
    ZEC(JsBundle.ZEC),
    ADA(JsBundle.ADA),
    FIL(JsBundle.FIL),

    /** Keys come from the ETH index-0 private key, addresses from the STX bundle. */
    STX(JsBundle.STX),
}
