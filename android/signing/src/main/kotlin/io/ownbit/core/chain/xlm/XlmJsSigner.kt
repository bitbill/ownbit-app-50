// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.chain.xlm

import io.ownbit.core.jsengine.JsArgs
import io.ownbit.core.jsengine.JsBundle
import io.ownbit.core.jsengine.JsEngineManager
import io.ownbit.core.jsengine.JsResults

/**
 * Signing half of iOS `StellarJSBridge.swift` over `js/xlm/stellarjs-lib-app.min.js` (byte-identical to iOS):
 *
 * - HD wallets: `bridge.build{CreateAccount|SetInflation|Payment}TxWithSeedHex(seedHex, json, memo, xlmaddr)` — the
 *   bundle derives the SEP-0005 key (`m/44'/148'/0'`) and falls back to the legacy key when `xlmaddr` (the wallet's
 *   own address) matches that one instead;
 * - private-key wallets: `bridge.build…TxWithPrivKey(secret, json, memo)` (`S…` secret or raw hex seed).
 *
 * The bundle uses the public network passphrase, `StellarBase.BASE_FEE`, a text memo (`Memo.text`, ≤ 28 bytes or it
 * throws) and `setTimeout(300)` (time bounds = now … now + 300 s, so signatures are not reproducible), and returns
 * `[txHashHex, envelopeXdrBase64]`.
 */
internal class XlmJsSigner(private val engines: JsEngineManager) {

    suspend fun signWithSeed(type: XlmTxType, seedHex: CharArray, txJson: String, memo: String, ownAddress: String): XlmSignature =
        sign("bridge.build${type.jsSuffix}TxWithSeedHex", seedHex, txJson, memo, ownAddress)

    suspend fun signWithPrivateKey(type: XlmTxType, secret: CharArray, txJson: String, memo: String): XlmSignature =
        sign("bridge.build${type.jsSuffix}TxWithPrivKey", secret, txJson, memo)

    private suspend fun sign(function: String, vararg args: Any?): XlmSignature {
        val result = engines.engine(JsBundle.XLM).call(function, JsArgs.of(*args))
        val values = JsResults.stringArray(result, JsBundle.XLM, function, minSize = 2)
        return XlmSignature(txHash = values[0], envelopeXdr = values[1])
    }

    // region 2026-10 tokens (iOS `BILXrpXlmJSBridge.swift` `StellarJSBridge` extension)
    // `dataJson` is JSON **text** (the bundle `JSON.parse`s it); `sequence` is a decimal string inside it. Unlike the
    // native functions above, `maxTime?` (unix seconds) sets the time bounds `(0, maxTime)` instead of `setTimeout(300)`
    // and `fee?` (stroops) replaces `BASE_FEE`. Results are checked like iOS `BILJSArg.strings` (two non-empty strings).

    /**
     * Token payment, HD wallet: `bridge.buildTokenPaymentTxWithSeedHex(seedHex, data, memo, xlmaddr)`. [dataJson] keys:
     * `accountId`, `sequence`, `destination` (`G…`), `amount` (decimal, ≤ 7 places), `assetCode`, `assetIssuer`,
     * `maxTime?`, `fee?`. [memo] is a text memo (≤ 28 bytes); [ownAddress] selects the SEP-0005 or legacy key as in
     * [signWithSeed].
     */
    suspend fun signTokenPaymentWithSeed(seedHex: CharArray, dataJson: String, memo: String, ownAddress: String): XlmSignature =
        pair("bridge.buildTokenPaymentTxWithSeedHex", seedHex, dataJson, memo, ownAddress)

    /** Token payment, private-key wallet: `bridge.buildTokenPaymentTxWithPrivKey(secret, data, memo)` (no `xlmaddr`). */
    suspend fun signTokenPaymentWithPrivateKey(secret: CharArray, dataJson: String, memo: String): XlmSignature =
        pair("bridge.buildTokenPaymentTxWithPrivKey", secret, dataJson, memo)

    /**
     * `change_trust`, HD wallet: `bridge.buildChangeTrustTxWithSeedHex(seedHex, data, xlmaddr)` (no memo). [dataJson]
     * keys: `accountId`, `sequence`, `assetCode`, `assetIssuer`, `limit` (`"922337203685.4775807"` to add - also the
     * default when absent - or `"0"` to remove), `maxTime?`, `fee?`.
     */
    suspend fun signChangeTrustWithSeed(seedHex: CharArray, dataJson: String, ownAddress: String): XlmSignature =
        pair("bridge.buildChangeTrustTxWithSeedHex", seedHex, dataJson, ownAddress)

    /** `change_trust`, private-key wallet: `bridge.buildChangeTrustTxWithPrivKey(secret, data)`. */
    suspend fun signChangeTrustWithPrivateKey(secret: CharArray, dataJson: String): XlmSignature =
        pair("bridge.buildChangeTrustTxWithPrivKey", secret, dataJson)

    private suspend fun pair(function: String, vararg args: Any?): XlmSignature {
        val result = engines.engine(JsBundle.XLM).call(function, JsArgs.of(*args))
        val values = JsResults.nonEmptyStrings(result, JsBundle.XLM, function, size = 2)
        return XlmSignature(txHash = values[0], envelopeXdr = values[1])
    }

    // endregion

    // region the accounts the single-sig functions sign for (see XlmSigningAccount)

    /**
     * The `G…` account of an HD seed's single-sig key, derived inside the JS engine: [sep0005] the SEP-0005 key
     * `m/44'/148'/0'` (the `…WithSeedHex` functions' first choice — and this wallet's account-multisig signer), else
     * the legacy key they fall back to when `xlmaddr` is its address. `bridge.getPubAddrFromSeedHex(seedHex, isNew)` →
     * `[rawPublicKeyHex, G…]`. Secret input.
     */
    suspend fun seedAccount(seedHex: CharArray, sep0005: Boolean): String =
        account("bridge.getPubAddrFromSeedHex", seedHex, sep0005)

    /** The `G…` account of a private key (`S…` secret or raw hex seed): `bridge.getPubAddrFromPrivkey(secret)`. Secret input. */
    suspend fun privateKeyAccount(secret: CharArray): String = account("bridge.getPubAddrFromPrivkey", secret)

    private suspend fun account(function: String, vararg args: Any?): String {
        val result = engines.engine(JsBundle.XLM).call(function, JsArgs.of(*args))
        return JsResults.nonEmptyStrings(result, JsBundle.XLM, function, size = 2)[1]
    }

    // endregion
}

/** `[hash, xdr]` of the XLM bundle: lower-case hex tx hash and the base64 `TransactionEnvelope` XDR. */
internal data class XlmSignature(val txHash: String, val envelopeXdr: String)
