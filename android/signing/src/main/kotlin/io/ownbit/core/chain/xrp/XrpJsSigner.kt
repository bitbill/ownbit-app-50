// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.chain.xrp

import io.ownbit.core.jsengine.JsArgs
import io.ownbit.core.jsengine.JsBundle
import io.ownbit.core.jsengine.JsEngineManager
import io.ownbit.core.jsengine.JsResults

/**
 * Signing half of iOS `RippleJSBridge.swift` over `js/xrp/ripplejs-lib-app.min.js` (byte-identical to iOS):
 * `bridge.buildXrpPaymentTxWithSeedHex(seedHex, json)` / `bridge.buildXrpPaymentTxWithPrivKey(privHex, json)`.
 * The bundle builds `{TransactionType: "Payment", Account, Destination, DestinationTag, Amount, Flags: 2147483648,
 * Fee, Sequence}` from the JSON, signs it with the `m/44'/144'/0'/0/0` key (seed) and returns `[txId, signedBlob]`.
 * Deterministic (no timestamps), offline. Secrets travel as JSON arguments only and are never logged.
 */
internal class XrpJsSigner(private val engines: JsEngineManager) {

    /** Signs with the BIP39 seed of an HD wallet. */
    suspend fun signWithSeed(seedHex: CharArray, txJson: String): XrpSignature =
        sign("bridge.buildXrpPaymentTxWithSeedHex", seedHex, txJson)

    /** Signs with the hex private key of an XRP private-key wallet. */
    suspend fun signWithPrivateKey(privateKey: CharArray, txJson: String): XrpSignature =
        sign("bridge.buildXrpPaymentTxWithPrivKey", privateKey, txJson)

    private suspend fun sign(function: String, key: CharArray, txJson: String): XrpSignature {
        val result = engines.engine(JsBundle.XRP).call(function, JsArgs.of(key, txJson))
        val values = JsResults.stringArray(result, JsBundle.XRP, function, minSize = 2)
        return XrpSignature(txId = values[0], signedBlob = values[1])
    }

    // region 2026-10 additions (iOS `BILXrpXlmJSBridge.swift` `RippleJSBridge` extension)
    // `dataJson` / `txJson` / `jsonStr` are JSON **text** (the bundle `JSON.parse`s them). Results are checked like iOS
    // `BILJSArg.strings`: the expected number of non-empty strings.

    /**
     * Single-sig token payment, HD wallet: `bridge.buildXrpTokenPaymentTxWithSeedHex(seedHex, data)`.
     * [dataJson] keys: `account`, `destination`, `destinationTag?` (number), `currency` (3-char or 40-hex), `issuer`,
     * `value` (decimal string), `sendMax?` (decimal string), `fee` (drops string), `sequence` (number). The bundle
     * builds `Payment {Amount: {currency, issuer, value}, SendMax?, Flags: 2147483648}` (no `Paths`, never
     * `tfPartialPayment`) and signs with `m/44'/144'/0'/0/0`.
     */
    suspend fun signTokenPaymentWithSeed(seedHex: CharArray, dataJson: String): XrpSignature =
        pair("bridge.buildXrpTokenPaymentTxWithSeedHex", seedHex, dataJson)

    /** As [signTokenPaymentWithSeed] for an XRP private-key wallet (`bridge.buildXrpTokenPaymentTxWithPrivKey`). */
    suspend fun signTokenPaymentWithPrivateKey(privateKey: CharArray, dataJson: String): XrpSignature =
        pair("bridge.buildXrpTokenPaymentTxWithPrivKey", privateKey, dataJson)

    /**
     * Single-sig `TrustSet`, HD wallet: `bridge.buildXrpTrustSetTxWithSeedHex(seedHex, data)`.
     * [dataJson] keys: `account`, `currency`, `issuer`, `limit` (`"1000000000000000"` to add, `"0"` to remove), `fee`
     * (drops string), `sequence` (number). The bundle sets `Flags = 2147614720` (`tfFullyCanonicalSig | tfSetNoRipple`).
     */
    suspend fun signTrustSetWithSeed(seedHex: CharArray, dataJson: String): XrpSignature =
        pair("bridge.buildXrpTrustSetTxWithSeedHex", seedHex, dataJson)

    /** As [signTrustSetWithSeed] for an XRP private-key wallet (`bridge.buildXrpTrustSetTxWithPrivKey`). */
    suspend fun signTrustSetWithPrivateKey(privateKey: CharArray, dataJson: String): XrpSignature =
        pair("bridge.buildXrpTrustSetTxWithPrivKey", privateKey, dataJson)

    /**
     * Single signature of a server-built `tx_json` with the key `m/44'/144'/0'/0/[index]` (multisig activation and
     * its offline variant): `bridge.signXrpTxJsonWithSeedHexIndex(seedHex, i, txJson)`. The bundle signs the
     * transaction **unchanged** (only `SigningPubKey` / `TxnSignature` are added). [index] is a JS number.
     */
    suspend fun signTxJsonAtIndex(seedHex: CharArray, index: Int, txJson: String): XrpSignature =
        pair("bridge.signXrpTxJsonWithSeedHexIndex", seedHex, index, txJson)

    /**
     * Multisig signature of a proposal: `bridge.multiSignXrpTxJsonWithSeedHex(seedHex, jsonStr)`. The
     * bundle forces `SigningPubKey: ""`, signs as the signer key `m/44'/144'/0'/0/0` and throws `signer mismatch` when
     * the decoded `Signer.Account` is not that key's address. Returns upper-case hex.
     */
    suspend fun multiSign(seedHex: CharArray, jsonStr: String): XrpMultiSignature {
        val function = "bridge.multiSignXrpTxJsonWithSeedHex"
        val result = engines.engine(JsBundle.XRP).call(function, JsArgs.of(seedHex, jsonStr))
        val values = JsResults.nonEmptyStrings(result, JsBundle.XRP, function, size = 3)
        return XrpMultiSignature(account = values[0], signingPubKey = values[1], txnSignature = values[2])
    }

    private suspend fun pair(function: String, vararg args: Any?): XrpSignature {
        val result = engines.engine(JsBundle.XRP).call(function, JsArgs.of(*args))
        val values = JsResults.nonEmptyStrings(result, JsBundle.XRP, function, size = 2)
        return XrpSignature(txId = values[0], signedBlob = values[1])
    }

    // endregion
}

/** `[txId, signedTransaction]` of the XRP bundle: the hash (upper-case hex) and the signed blob (upper-case hex). */
internal data class XrpSignature(val txId: String, val signedBlob: String)

/**
 * `[rSigner, signingPubKey, txnSignature]` of `multiSignXrpTxJsonWithSeedHex`: the `Signer` entry this wallet adds to a
 * multisig proposal - [account] the signer's `r...` address, [signingPubKey] its compressed public key and
 * [txnSignature] the DER signature (both upper-case hex).
 */
internal data class XrpMultiSignature(val account: String, val signingPubKey: String, val txnSignature: String)
