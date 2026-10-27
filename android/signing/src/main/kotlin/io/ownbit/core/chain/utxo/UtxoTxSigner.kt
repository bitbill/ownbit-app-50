// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.chain.utxo

import io.ownbit.core.jsengine.JsArgs
import io.ownbit.core.jsengine.JsBundle
import io.ownbit.core.jsengine.JsEngineManager
import io.ownbit.core.jsengine.JsResults
import io.ownbit.core.jsengine.bridge.BitcoinTaprootJsBridge
import io.ownbit.core.chain.json.looseLong
import io.ownbit.core.chain.json.looseString
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject

/**
 * Key material handed to the UTXO bundles. Secrets stay [CharArray]s owned (and wiped) by the caller —
 * `WalletSecretAccess.withUnlocked` wipes them after the block — and become JS strings only inside [JsArgs].
 */
sealed interface UtxoSigningKey {
    /**
     * HD wallet: BIP39 seed hex and iOS `getSeedTypePath()` (`"0"`, `"1"` Electrum, or a custom `m/…` path; only
     * the BTC / BCH bundles read it).
     */
    class Seed(val seedHex: CharArray, val seedTypePath: String) : UtxoSigningKey {
        override fun toString(): String = "Seed(<redacted>, path=$seedTypePath)"
    }

    /** Private-key wallet: WIF or hex key exactly as iOS decrypts it (`decryptWIF` / `decryptPrivateKey`). */
    class PrivateKey(val key: CharArray) : UtxoSigningKey {
        override fun toString(): String = "PrivateKey(<redacted>)"
    }
}

/**
 * Result of a bundle build call.
 *
 * @property txId the id the bundle returned (`[txId, hex]` bundles), `null` for hex-only bundles (BCH / LTC).
 * @property rawHex signed transaction hex.
 */
class UtxoSignedRaw(val txId: String?, val rawHex: String) {
    override fun toString(): String = "UtxoSignedRaw(txId=$txId, hex=<${rawHex.length} chars>)"
}

/** Signs `signDatas` with the chain's bundle (an interface so engine logic is testable on the JVM). */
interface UtxoTxSigner {
    /**
     * Calls `bridge.build…Transaction` of [profile] with `signDatas` as a JSON **string** (iOS splices the
     * whitespace-free JSON into a `'…'` literal; the bundles `JSON.parse` it).
     *
     * @throws io.ownbit.core.jsengine.JsException when the bundle fails (message never contains arguments).
     */
    suspend fun sign(profile: UtxoChainProfile, signDatas: JsonObject, key: UtxoSigningKey): UtxoSignedRaw
}

/**
 * [UtxoTxSigner] over `:jsengine` — the calls of iOS `BitcoinJSBridge.buildTransaction`,
 * `BitcoinCashJSBridge.buildTransaction`, `LitecoinJSBridge` / `DogecoinJSBridge` / `DashJSBridge` /
 * `DigibyteJSBridge` / `HorizenJSBridge` / `ZcashJSBridge.buildTransaction` (seed and private-key variants), with the
 * same argument order and types.
 *
 * ZEC: the JSON given to the bundle carries the v4 consensus-branch override (iOS `ZcashJSBridge.withV4BranchOverride`,
 * [ZecSignFields.withV4BranchOverride]). The override is network configuration the host app supplies
 * ([zecV4BranchOverride]; `null` = the bundle's own id). The caller's `signDatas` object is not changed (the post-sign
 * verifier reads it).
 */
class JsUtxoTxSigner(
    private val engines: JsEngineManager,
    private val zecV4BranchOverride: () -> Long? = { null },
) : UtxoTxSigner {

    private val taproot = BitcoinTaprootJsBridge(engines)

    override suspend fun sign(profile: UtxoChainProfile, signDatas: JsonObject, key: UtxoSigningKey): UtxoSignedRaw {
        if (profile == UtxoChainProfile.BTC && hasTaprootInput(signDatas)) return signWithTaproot(signDatas, key)
        val json = if (profile == UtxoChainProfile.ZEC) {
            ZecSignFields.withV4BranchOverride(signDatas, zecV4BranchOverride()).toString()
        } else {
            signDatas.toString()
        }
        val (function, args) = when (key) {
            is UtxoSigningKey.Seed ->
                if (profile.buildWithSeedTakesPath) {
                    profile.buildWithSeedFunction to JsArgs.of(key.seedHex, key.seedTypePath, json)
                } else {
                    profile.buildWithSeedFunction to JsArgs.of(key.seedHex, json)
                }
            is UtxoSigningKey.PrivateKey -> profile.buildWithKeyFunction to JsArgs.of(key.key, json)
        }
        val result = engines.engine(profile.bundle).call(function, args)
        return if (profile.jsReturnsTxId) {
            val values = JsResults.stringArray(result, profile.bundle, function, minSize = 2)
            UtxoSignedRaw(txId = values[0], rawHex = values[1])
        } else {
            UtxoSignedRaw(txId = null, rawHex = JsResults.nonEmptyString(result, profile.bundle, function))
        }
    }

    /**
     * iOS `BTCTransactionBuilder.build` for a BTC transaction with at least one Taproot
     * (`segwit: "T"`) input — the whole transaction goes to the Taproot bundle (BIP341 signs over every input's amount
     * and script):
     * - seed wallets (iOS `buildTaprootTransaction`): each non-Taproot input gets the `wif` the **old** bundle derives
     *   for it (`getWIFFromSeedHex` / `…ForBIP49` / `…ForBIP84` with the same seed-type path, cached per
     *   type / branch / index — exactly the keys the old bundle would sign with), then `bridge.buildTransaction(seed,
     *   data)`; Taproot inputs are derived there at m/86'/0'/0'/{isChange}/{bip39Index};
     * - private-key wallets: `bridge.buildTransactionWithPrivateKey(key, data)` with the same key string the old bundle
     *   gets (WIF, or hex = uncompressed).
     * Transactions without a Taproot input never come here (old bundle, unchanged).
     */
    private suspend fun signWithTaproot(signDatas: JsonObject, key: UtxoSigningKey): UtxoSignedRaw {
        val signed = when (key) {
            is UtxoSigningKey.PrivateKey -> taproot.buildTransactionWithPrivateKey(key.key, signDatas.toString())
            is UtxoSigningKey.Seed -> {
                val wifs = HashMap<String, String>()
                val inputs = signDatas["inputs"]?.jsonArray.orEmpty().map { element ->
                    val input = element.jsonObject
                    val segwit = input["segwit"].looseString()
                    if (segwit == SEGWIT_TAPROOT) return@map input
                    val index = input["bip39Index"].looseLong()
                    val isChange = (input["isChange"] as? JsonPrimitive)?.booleanOrNull ?: false
                    val function = when (segwit) {
                        "P" -> "bridge.getWIFFromSeedHexForBIP49"
                        "D" -> "bridge.getWIFFromSeedHexForBIP84"
                        else -> "bridge.getWIFFromSeedHex"
                    }
                    val wif = wifs.getOrPut("$segwit|$isChange|$index") {
                        JsResults.nonEmptyString(
                            engines.engine(JsBundle.BTC).call(function, JsArgs.of(key.seedHex, key.seedTypePath, index, isChange)),
                            JsBundle.BTC,
                            function,
                        )
                    }
                    JsonObject(input + ("wif" to JsonPrimitive(wif)))
                }
                val data = JsonObject(signDatas + ("inputs" to JsonArray(inputs)))
                taproot.buildTransaction(key.seedHex, data.toString())
            }
        }
        return UtxoSignedRaw(txId = signed.txId, rawHex = signed.rawHex)
    }

    companion object {
        /** A BTC `signDatas` that spends at least one Taproot input (iOS `signInputs.contains { segwit == "T" }`). */
        fun hasTaprootInput(signDatas: JsonObject): Boolean =
            signDatas["inputs"]?.jsonArray.orEmpty().any { (it as? JsonObject)?.get("segwit").looseString() == SEGWIT_TAPROOT }

        /** `segwit` value of a Taproot (P2TR key-path) input in BTC `signDatas`. */
        const val SEGWIT_TAPROOT: String = "T"
    }
}
