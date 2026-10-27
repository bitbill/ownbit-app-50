// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.chain.utxo

import io.ownbit.core.jsengine.JsBundle

/**
 * What differs between the eight UTXO chains of 5.0 (BTC, BCH, LTC, DOGE, DASH, DGB, ZEN, ZEC) when **signing**, taken
 * from the iOS builders and their JS bridges (the app's enum also carries coin types, server routes and confirm-page
 * capabilities, which are not part of this repository):
 *
 * | chain | iOS builder | input dictionary | output amount key | JS (seed / key) | JS result |
 * |---|---|---|---|---|---|
 * | BTC | `BTCTransactionBuilder` | `BTCInput.toDictionary` | `amount` | `buildTransaction(seed, path, json)` / `buildTransactionWithOnePrivateKey` | `[txId, hex]` |
 * | BCH | `BCHTransactionBuilder` (inherits BTC `txSignDatas`) | `BCHInput.toDictionary` | `amount` | `buildBchTransaction(seed, path, json)` / `buildBchTxWithPrivateKey` | `hex` |
 * | LTC | `LTCTransactionBuilder` | `BCHInput` | `amount` | `buildLtcTransaction(seed, json)` / `buildLtcTxWithPrivateKey` | `hex` |
 * | DOGE | `DOGETransactionBuilder` | `DOGEInput` (= `BCHInput`) | `amount` | `buildDogeTransaction` / `buildDogeTxWithPrivateKey` | `[txId, hex]` |
 * | DASH | `DASHTransactionBuilder` | `DASHInput` | `amount` | `buildDshTransaction` / `buildDshTxWithPrivateKey` | `[txId, hex]` |
 * | DGB | `DGBTransactionBuilder` | `DGBInput` | `amount` | `buildDgbTransaction` / `buildDgbTxWithPrivateKey` | `[txId, hex]` |
 * | ZEN | `ZENTransactionBuilder` (+ `blockHeight` / `blockHash`) | `ZENInput` | **`satoshis`** | `buildZenTransaction` / `buildZenTxWithPrivateKey` | `[txId, hex]` |
 * | ZEC | `ZECTransactionBuilder` | `BCHInput` | `amount` | `buildZecTransaction` / `buildZecTxWithPrivateKey` | `[txId, hex]` |
 *
 * @property bundle JS bundle that signs.
 * @property buildWithSeedFunction global JS function for HD wallets.
 * @property buildWithSeedTakesPath whether that function takes iOS `getSeedTypePath()` (BTC / BCH only).
 * @property buildWithKeyFunction global JS function for private-key wallets.
 * @property jsReturnsTxId `[txId, hex]` (true) or a plain hex string (false, iOS then hashes the hex itself).
 * @property inputStyle shape of the input dictionaries of `signDatas`.
 * @property outputAmountKey key of the amount in the output dictionaries (`amount`, ZEN `satoshis`).
 * @property btcStyleSignDatas `signDatas` also carries `ophex`, `locktime` and `caStatus` (BTC `txSignDatas`,
 *   inherited by BCH).
 */
enum class UtxoChainProfile(
    val bundle: JsBundle,
    val buildWithSeedFunction: String,
    val buildWithSeedTakesPath: Boolean,
    val buildWithKeyFunction: String,
    val jsReturnsTxId: Boolean,
    val inputStyle: InputStyle,
    val outputAmountKey: String,
    val btcStyleSignDatas: Boolean,
) {
    BTC(
        JsBundle.BTC, "bridge.buildTransaction", true, "bridge.buildTransactionWithOnePrivateKey", true,
        InputStyle.BTC, "amount", true,
    ),
    BCH(
        JsBundle.BCH, "bridge.buildBchTransaction", true, "bridge.buildBchTxWithPrivateKey", false,
        InputStyle.SCRIPT, "amount", true,
    ),
    LTC(
        JsBundle.LTC, "bridge.buildLtcTransaction", false, "bridge.buildLtcTxWithPrivateKey", false,
        InputStyle.SCRIPT, "amount", false,
    ),
    DOGE(
        JsBundle.DOGE, "bridge.buildDogeTransaction", false, "bridge.buildDogeTxWithPrivateKey", true,
        InputStyle.SCRIPT, "amount", false,
    ),
    DASH(
        JsBundle.DASH, "bridge.buildDshTransaction", false, "bridge.buildDshTxWithPrivateKey", true,
        InputStyle.SCRIPT, "amount", false,
    ),
    DGB(
        JsBundle.DGB, "bridge.buildDgbTransaction", false, "bridge.buildDgbTxWithPrivateKey", true,
        InputStyle.SCRIPT, "amount", false,
    ),
    ZEN(
        JsBundle.ZEN, "bridge.buildZenTransaction", false, "bridge.buildZenTxWithPrivateKey", true,
        InputStyle.SCRIPT, "satoshis", false,
    ),
    ZEC(
        JsBundle.ZEC, "bridge.buildZecTransaction", false, "bridge.buildZecTxWithPrivateKey", true,
        InputStyle.SCRIPT, "amount", false,
    ),
    ;

    /** Shape of the per-input dictionary in `signDatas.inputs`. */
    enum class InputStyle {
        /** iOS `BTCInput.toDictionary`: `txHash, index, bip39Index, isChange, satoshis, segwit ("P"/"D"/"T"/""), txHex`. */
        BTC,

        /** iOS `BCHInput.toDictionary`: `scriptPubKey, txid, vout, bip39Index, isChange, satoshis`. */
        SCRIPT,
    }
}
