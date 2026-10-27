// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.chain.multisig

import io.ownbit.core.jsengine.JsArgs
import io.ownbit.core.jsengine.JsBundle
import io.ownbit.core.jsengine.JsEngineManager
import io.ownbit.core.jsengine.JsEventSpec
import io.ownbit.core.jsengine.JsResultFormatException
import io.ownbit.core.jsengine.JsResults
import io.ownbit.core.jsengine.bridge.EthereumJsBridge
import io.ownbit.core.jsengine.bridge.TronJsBridge
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonPrimitive
import java.math.BigInteger

/** `(v, r, s)` of a multisig message signature; `v` as the bundles return it (0 / 1). */
data class MultiSigSignature(val v: String, val r: String, val s: String)

/** A signed outer transaction: hash + raw hex (broadcast by `sendMsTx`). */
data class SignedEvmTx(val txHash: String, val rawTx: String)

/** `ownbitWcInfo` result. */
data class WcSignInfo(val digest: String, val wrapped: String, val deadline: Double)

/**
 * Typed calls of every multisig JS function iOS uses (iOS
 * `EthereumJSBridge.swift`, `EthereumExtJsBridge.swift`, `TronJSBridge.swift`, `SolanaJSBridge.swift`,
 * `BitcoinJSBridge.swift`, `LitecoinJSBridge.swift`, `BitcoinCashJSBridge.swift`, `ZcashJSBridge.swift`).
 *
 * Argument **types** follow iOS exactly (`'\(nonce)'` → string, `\(nonce)` → number). Secrets arrive as Strings that
 * the caller built inside `WalletSecretAccess.withUnlocked` and drops right after; nothing here logs arguments or
 * results.
 *
 * ETH_EXT / TRX follow the **iOS** bundles (`ethjs-ext-v2.js`, `trxjs-lib-app.js`): `signMultiSigSpendV3GenericTransaction*`,
 * JSON-string `ownbitWc*` results (the old-Android array shape is accepted too). The TRX functions that ask a node to
 * build or extend a transaction (`preSendTx`, `extendTxForWc`) are not part of this repository.
 */
class MultiSigJs(
    private val engines: JsEngineManager,
    private val ethereum: EthereumJsBridge,
    private val tron: TronJsBridge,
) {

    // region ETH legacy bundle (ethereumjs-lib-app.min.js)

    /** `m/44'/60'/0'/0/[index]` private key hex without `0x` (iOS `seedHexToPrivateHex(seedHex:indexNo:)`). */
    suspend fun ethPrivateKey(seedHex: String, index: Int): String = ethereum.getEthPrivateKeyHex(seedHex, index).removePrefix("0x")

    /** `0x` address of a private key (`getPubAddrFromPrivate`): the signer a TRX multisig signature must recover to. */
    suspend fun ethAddressOfPrivateKey(privateKeyHex: String): String = ethereum.getPublicKeyAndAddress(privateKeyHex).address

    /** Address of `xpub/[index]` (iOS `getPublicKeyAndAddress(extPubKey:indexNo:)`, e.g. the 889 deployer). */
    suspend fun ethAddressFromXpub(xpub: String, index: Int): String = ethereum.getAccountFromExtendedPublicKey(xpub, index).address

    /**
     * Spend message signature. [forceChainId] (= `MultiSigVersion.signsWithChainId`… for v10/11/21) selects the V4
     * entry (chain id always hashed); V3 hashes it only when `chainId > 1`.
     */
    suspend fun signSpendV3(
        seedHex: String, ms: String, erc20: String, ercType: Int, destination: String, amountWei: BigInteger,
        nonce: Long, chainId: Long, forceChainId: Boolean,
    ): MultiSigSignature = vrs(
        eth(if (forceChainId) "generateMultiSigBySeedHexV4" else "generateMultiSigBySeedHexV3",
            ms, erc20, ercType, destination, amountWei.toString(), nonce, chainId, seedHex),
    )

    /** dApp calldata spend message (`…V3Generic` / `…V4Generic`). */
    suspend fun signSpendGeneric(
        seedHex: String, ms: String, destination: String, valueWei: BigInteger, dataHex: String,
        nonce: Long, chainId: Long, forceChainId: Boolean,
    ): MultiSigSignature = vrs(
        eth(if (forceChainId) "generateMultiSigBySeedHexV4Generic" else "generateMultiSigBySeedHexV3Generic",
            ms, destination, valueWei.toString(), dataHex, nonce, chainId, seedHex),
    )

    /** Same as [signSpendGeneric] with a raw private key (`generateMultiSigByPrivateKeyV{3,4}Generic`, test vectors). */
    suspend fun signSpendGenericWithPrivateKey(
        privateKeyHex: String, ms: String, destination: String, valueWei: BigInteger, dataHex: String,
        nonce: Long, chainId: Long, forceChainId: Boolean,
    ): MultiSigSignature = vrs(
        eth(if (forceChainId) "generateMultiSigByPrivateKeyV4Generic" else "generateMultiSigByPrivateKeyV3Generic",
            ms, destination, valueWei.toString(), dataHex, nonce, chainId, privateKeyHex),
    )

    /** Contracts v3–v5 (Ownbit-MS-Compound, `generateMultiSigBySeedHexV2`). */
    suspend fun signSpendV2(
        seedHex: String, ms: String, erc20: String, destination: String, amountWei: BigInteger, nonce: Long, chainId: Long,
    ): MultiSigSignature = vrs(eth("generateMultiSigBySeedHexV2", ms, erc20, destination, amountWei.toString(), nonce, chainId, seedHex))

    /** Contracts < v3 (`generateMultiSigBySeedHex`, nonce as a string). */
    suspend fun signSpendV1(seedHex: String, nonce: Long, contract: String, amountWei: BigInteger, destination: String): MultiSigSignature =
        vrs(eth("generateMultiSigBySeedHex", nonce.toString(), contract, amountWei.toString(), destination, seedHex))

    /** Enterprise `changeOwners` config message (`…V3_changeOwners` / `…V4_changeOwners`). */
    suspend fun signChangeOwners(
        seedHex: String, ms: String, newOwners: List<String>, required: Int, configNonce: Long, chainId: Long, forceChainId: Boolean,
    ): MultiSigSignature = vrs(
        eth(if (forceChainId) "generateMultiSigBySeedHexV4_changeOwners" else "generateMultiSigBySeedHexV3_changeOwners",
            ms, newOwners, required, configNonce, chainId, seedHex),
    )

    /** Enterprise `changeSigners` config message. */
    suspend fun signChangeSigners(
        seedHex: String, ms: String, newSigners: List<String>, weights: List<Int>, required: Int, configNonce: Long,
        chainId: Long, forceChainId: Boolean,
    ): MultiSigSignature = vrs(
        eth(if (forceChainId) "generateMultiSigBySeedHexV4_changeSigners" else "generateMultiSigBySeedHexV3_changeSigners",
            ms, newSigners, weights, required, configNonce, chainId, seedHex),
    )

    /** Standard / accident-protection contract deployment (`buildDeployContractTxBySeedHex`, legacy tx). */
    suspend fun buildDeploy(
        seedHex: String, indexNo: Int, owners: List<String>, required: Int, accidentProtection: Int,
        nonce: Long, gasLimit: Long, gasPriceWei: BigInteger, chainId: Long,
    ): SignedEvmTx {
        val ctor = JsonObject(
            mapOf(
                "owners" to JsonArray(owners.map { JsonPrimitive(it) }),
                "required" to JsonPrimitive(required),
                "accidentProtection" to JsonPrimitive(accidentProtection),
            ),
        ).toString()
        return hashAndRaw(eth("buildDeployContractTxBySeedHex", ctor, nonce.toString(), gasLimit.toString(), gasPriceWei.toString(),
            seedHex, indexNo, chainId), "buildDeployContractTxBySeedHex")
    }

    /** Enterprise contract deployment (`accidentProtection = 3`). */
    suspend fun buildDeployEnterprise(
        seedHex: String, indexNo: Int, owners: List<String>, signers: List<String>, weights: List<Int>,
        ownerRequired: Int, signerRequired: Int, nonce: Long, gasLimit: Long, gasPriceWei: BigInteger, chainId: Long,
    ): SignedEvmTx {
        val ctor = JsonObject(
            mapOf(
                "owners" to JsonArray(owners.map { JsonPrimitive(it) }),
                "signers" to JsonArray(signers.map { JsonPrimitive(it) }),
                "weights" to JsonArray(weights.map { JsonPrimitive(it) }),
                "ownerRequired" to JsonPrimitive(ownerRequired),
                "signerRequired" to JsonPrimitive(signerRequired),
                "accidentProtection" to JsonPrimitive(ENTERPRISE_AP),
            ),
        ).toString()
        return hashAndRaw(eth("buildDeployEnterpriseContractTxBySeedHex", ctor, nonce.toString(), gasLimit.toString(),
            gasPriceWei.toString(), seedHex, indexNo, chainId), "buildDeployEnterpriseContractTxBySeedHex")
    }

    /** Legacy (EIP-155) plain tx, used for the keep-alive `active()` call (`buildEthTxBySeedHex`). */
    suspend fun buildLegacyTx(
        seedHex: String, indexNo: Int, amountWei: BigInteger, to: String, nonce: Long, gasPriceWei: BigInteger,
        gasLimit: Long, dataHex: String, chainId: Long,
    ): SignedEvmTx = hashAndRaw(eth("buildEthTxBySeedHex", seedHex, indexNo, amountWei.toString(), to, nonce.toString(),
        gasPriceWei.toString(), gasLimit.toString(), dataHex, chainId), "buildEthTxBySeedHex")

    /** Same as [buildLegacyTx] for private-key wallets (`buildEthTransaction`). */
    suspend fun buildLegacyTxWithPrivateKey(
        privateKeyHex: String, amountWei: BigInteger, to: String, nonce: Long, gasPriceWei: BigInteger,
        gasLimit: Long, dataHex: String, chainId: Long,
    ): SignedEvmTx = hashAndRaw(eth("buildEthTransaction", privateKeyHex, amountWei.toString(), to, nonce.toString(),
        gasPriceWei.toString(), gasLimit.toString(), dataHex, chainId), "buildEthTransaction")

    /** Contracts < v6 execute (`buildCallMSContractMdTx[BySeedHex]`, purpose 0 = send). v/r/s travel as JSON text. */
    suspend fun buildLegacySpend(
        key: SpendKey, destination: String, erc20: String, amountWei: BigInteger, sigs: EvmSigs,
        nonce: Long, contract: String, gasLimit: Long, gasPriceWei: BigInteger, chainId: Long,
    ): SignedEvmTx {
        val common = arrayOf<Any?>(destination, erc20, amountWei.toString(), 0, jsonText(sigs.vs), jsonText(sigs.rs),
            jsonText(sigs.ss), nonce.toString(), contract, gasLimit.toString(), gasPriceWei.toString())
        return when (key) {
            is SpendKey.Seed -> hashAndRaw(eth("buildCallMSContractMdTxBySeedHex", *common, key.seedHex, key.indexNo, chainId), "buildCallMSContractMdTxBySeedHex")
            is SpendKey.PrivateKey -> hashAndRaw(eth("buildCallMSContractMdTx", *common, key.privateKeyHex, chainId), "buildCallMSContractMdTx")
        }
    }

    /** v6+ execute as a legacy (type 1) tx — iOS keeps this for ERC-1155 (`ercType == 2`). */
    suspend fun buildSpendV3Legacy(
        key: SpendKey, destination: String, erc20: String, amountWei: BigInteger, ercType: Int, sigs: EvmSigs,
        nonce: Long, contract: String, gasLimit: Long, gasPriceWei: BigInteger, chainId: Long,
    ): SignedEvmTx {
        val common = arrayOf<Any?>(destination, erc20, amountWei.toString(), ercType, jsonText(sigs.vs), jsonText(sigs.rs),
            jsonText(sigs.ss), nonce.toString(), contract, gasLimit.toString(), gasPriceWei.toString())
        return when (key) {
            is SpendKey.Seed -> hashAndRaw(eth("buildCallMSContractMdTxBySeedHexV3", *common, key.seedHex, key.indexNo, chainId), "buildCallMSContractMdTxBySeedHexV3")
            is SpendKey.PrivateKey -> hashAndRaw(eth("buildCallMSContractMdTxV3", *common, key.privateKeyHex, chainId), "buildCallMSContractMdTxV3")
        }
    }

    // endregion

    // region ETH_EXT bundle (EIP-1559)

    /** v6+ spend as a type-2 tx (`signMultiSigSpendV3TransactionBy{SeedHex,PrivateKey}`). */
    suspend fun buildSpendV3(
        key: SpendKey, ms: String, erc20: String, destination: String, amountWei: BigInteger, sigs: EvmSigs, ercType: Int,
        gas: EvmGas, chainId: Long, nonce: Long,
    ): SignedEvmTx {
        val tail = arrayOf<Any?>(ms, erc20, destination, amountWei.toString(), sigs.vs, sigs.rs, sigs.ss, ercType,
            gas.limit.toString(), gas.priceWei.toString(), gas.priorityWei.toString(), chainId, nonce)
        return ext(key, "signMultiSigSpendV3Transaction", tail)
    }

    /** dApp calldata spend (`signMultiSigSpendV3GenericTransactionBy…`, iOS name). */
    suspend fun buildSpendGeneric(
        key: SpendKey, ms: String, destination: String, valueWei: BigInteger, dataHex: String, sigs: EvmSigs,
        gas: EvmGas, chainId: Long, nonce: Long,
    ): SignedEvmTx {
        val tail = arrayOf<Any?>(ms, destination, valueWei.toString(), dataHex, sigs.vs, sigs.rs, sigs.ss,
            gas.limit.toString(), gas.priceWei.toString(), gas.priorityWei.toString(), chainId, nonce)
        return ext(key, "signMultiSigSpendV3GenericTransaction", tail)
    }

    /** Enterprise `changeOwners` execution. */
    suspend fun buildChangeOwners(
        key: SpendKey, ms: String, newOwners: List<String>, required: Int, sigs: EvmSigs, gas: EvmGas, chainId: Long, nonce: Long,
    ): SignedEvmTx {
        val tail = arrayOf<Any?>(ms, newOwners, required, sigs.vs, sigs.rs, sigs.ss,
            gas.limit.toString(), gas.priceWei.toString(), gas.priorityWei.toString(), chainId, nonce)
        return ext(key, "signMultiSigChangeOwnersV3Transaction", tail)
    }

    /** Enterprise `changeSigners` execution. */
    suspend fun buildChangeSigners(
        key: SpendKey, ms: String, newSigners: List<String>, weights: List<Int>, required: Int, sigs: EvmSigs,
        gas: EvmGas, chainId: Long, nonce: Long,
    ): SignedEvmTx {
        val tail = arrayOf<Any?>(ms, newSigners, weights, required, sigs.vs, sigs.rs, sigs.ss,
            gas.limit.toString(), gas.priceWei.toString(), gas.priorityWei.toString(), chainId, nonce)
        return ext(key, "signMultiSigChangeSignersV3Transaction", tail)
    }

    /** `ownbitWcInfo(ms, chainId, method, payload)` — digest / wrapped hash / typed-data deadline. */
    suspend fun wcInfo(ms: String, chainId: Long, method: String, payload: String): WcSignInfo {
        val fn = "bridge.ownbitWcInfo"
        val r = engines.engine(JsBundle.ETH_EXT).call(fn, JsArgs.of(ms, chainId, method, payload))
        val obj = asObject(r)
        if (obj != null) {
            val digest = obj.text("digest") ?: throw JsResultFormatException(JsBundle.ETH_EXT, fn, "{digest,wrapped,deadline}")
            val wrapped = obj.text("wrapped") ?: throw JsResultFormatException(JsBundle.ETH_EXT, fn, "{digest,wrapped,deadline}")
            return WcSignInfo(digest, wrapped, (obj["deadline"] as? JsonPrimitive)?.doubleOrNull ?: 0.0)
        }
        val arr = r as? JsonArray ?: throw JsResultFormatException(JsBundle.ETH_EXT, fn, "{digest,wrapped,deadline}")
        if (arr.size < 2) throw JsResultFormatException(JsBundle.ETH_EXT, fn, "[digest, wrapped, deadline]")
        return WcSignInfo(arr[0].jsonPrimitive.content, arr[1].jsonPrimitive.content, arr.getOrNull(2)?.let { (it as? JsonPrimitive)?.doubleOrNull } ?: 0.0)
    }

    /**
     * `ownbitWcSign(privKey, ms, chainId, method, payload)`: raw ecsign of the contract's `getMessageHash(digest)`,
     * digest recomputed from [payload]. `v` is 0 / 1 (the server format).
     */
    suspend fun wcSign(privateKeyHex: String, ms: String, chainId: Long, method: String, payload: String): MultiSigSignature {
        val fn = "bridge.ownbitWcSign"
        val r = engines.engine(JsBundle.ETH_EXT).call(fn, JsArgs.of(privateKeyHex, ms, chainId, method, payload))
        val obj = asObject(r)
        if (obj != null) {
            val v = (obj["v"] as? JsonPrimitive)?.content ?: throw JsResultFormatException(JsBundle.ETH_EXT, fn, "{v,r,s,wrapped}")
            val rr = obj.text("r") ?: throw JsResultFormatException(JsBundle.ETH_EXT, fn, "{v,r,s,wrapped}")
            val ss = obj.text("s") ?: throw JsResultFormatException(JsBundle.ETH_EXT, fn, "{v,r,s,wrapped}")
            return MultiSigSignature(v.toBigDecimalOrNull()?.toInt()?.toString() ?: v, rr, ss)
        }
        val arr = r as? JsonArray ?: throw JsResultFormatException(JsBundle.ETH_EXT, fn, "{v,r,s,wrapped}")
        if (arr.size < 3) throw JsResultFormatException(JsBundle.ETH_EXT, fn, "[v, r, s, wrapped]")
        val v = arr[0].jsonPrimitive.content
        return MultiSigSignature(v.toBigDecimalOrNull()?.toInt()?.toString() ?: v, arr[1].jsonPrimitive.content, arr[2].jsonPrimitive.content)
    }

    // endregion

    // region TRX bundle

    /**
     * `multiSignTx` → this participant's signature hex. A transaction TronWeb refuses comes back on the `error` channel
     * at once; [timeoutMillis] bounds the wait otherwise.
     */
    suspend fun trxMultiSign(privateKeyHex: String, txJson: String, timeoutMillis: Long = TRX_TIMEOUT): String =
        engines.engine(JsBundle.TRX).callForEvent(
            "bridge.multiSignTx", JsArgs.of(tron.tronNode, privateKeyHex.removePrefix("0x"), txJson), JsEventSpec.of("multiSigned"), timeoutMillis,
        ).payload.also { if (it.isEmpty()) throw JsResultFormatException(JsBundle.TRX, "bridge.multiSignTx", "signature") }

    /** `signTx` → signed tx JSON (TRX multisig deploy / AccountPermissionUpdate). */
    suspend fun trxSign(privateKeyHex: String, txJson: String): String =
        engines.engine(JsBundle.TRX).callForEvent(
            "bridge.signTx", JsArgs.of(tron.tronNode, privateKeyHex.removePrefix("0x"), txJson), JsEventSpec.of("signed"), TRX_TIMEOUT,
        ).payload.also { if (it.isEmpty()) throw JsResultFormatException(JsBundle.TRX, "bridge.signTx", "signed tx") }

    /**
     * Drops the TRX page: `multiSignTx` leaves its key in the page's TronWeb (`tronWeb.setPrivateKey`, the bundle never
     * resets it), so a batch signer that held a key discards the page
     * when it closes. Returns at once; the page goes after the call in flight, the next TRX call loads a fresh one.
     */
    fun trxDiscardKeyPage() = engines.discardPage(JsBundle.TRX)

    // endregion

    // region SOL bundle

    /** `createMultisig` → `create_multisig:<tx>:<multisigPda>:<multisig>:<ranInt>` (owners colon-joined, old bundle). */
    suspend fun solCreateMultisig(
        provider: String, seedHex: String, owners: List<String>, threshold: Int, fee: Long, blockHash: String, height: Long, rent400: Long,
    ): SolCreateResult {
        val parts = sol("bridge.createMultisig", JsArgs.of(provider, seedHex, owners.joinToString(":"), threshold, fee, blockHash, height, rent400), 5)
        return SolCreateResult(parts[1], parts[2], parts[3], parts[4].toLongOrNull() ?: 0L)
    }

    /** `createMultisigTransactionForSol` → (tx, transaction account). */
    suspend fun solCreateTransaction(
        provider: String, seedHex: String, multisig: String, to: String, lamports: BigInteger, fee: Long, blockHash: String, height: Long, rent800: Long,
    ): Pair<String, String> {
        val p = sol("bridge.createMultisigTransactionForSol", JsArgs.of(provider, seedHex, multisig, to, lamports.toString(), fee, blockHash, height, rent800), 3)
        return p[1] to p[2]
    }

    /** `createMultisigTransactionForToken` → (tx, transaction account). */
    suspend fun solCreateTokenTransaction(
        provider: String, seedHex: String, multisig: String, mint: String, token2022: Boolean, to: String, amount: BigInteger,
        decimals: Int, fee: Long, blockHash: String, height: Long, rent800: Long,
    ): Pair<String, String> {
        val p = sol("bridge.createMultisigTransactionForToken",
            JsArgs.of(provider, seedHex, multisig, mint, token2022, to, amount.toString(), decimals, fee, blockHash, height, rent800), 3)
        return p[1] to p[2]
    }

    /** `approveMultisigTransaction` → approve tx. */
    suspend fun solApprove(provider: String, seedHex: String, multisig: String, transaction: String, fee: Long, blockHash: String, height: Long): String =
        sol("bridge.approveMultisigTransaction", JsArgs.of(provider, seedHex, multisig, transaction, fee, blockHash, height), 2)[1]

    /** `executeMultisigTransaction` → execute tx (native SOL: mint = 32 ones, iOS rule for mints shorter than 10 chars). */
    suspend fun solExecute(
        provider: String, seedHex: String, multisig: String, transaction: String, mint: String, token2022: Boolean, to: String,
        shouldCreateTokenAccount: Boolean, fee: Long, blockHash: String, height: Long,
    ): String {
        val m = if (mint.length < 10) SOL_NATIVE_MINT else mint
        return sol("bridge.executeMultisigTransaction",
            JsArgs.of(provider, seedHex, multisig, transaction, m, token2022, to, shouldCreateTokenAccount, fee, blockHash, height), 2)[1]
    }

    // endregion

    // region UTXO bundles

    /** BTC P2WSH co-sign (`getSignatureWithSeedHex(seed, 'signOrder', json, redeemScript)`). */
    suspend fun btcSignatures(seedHex: String, signOrder: Int, inputsOutputs: String, redeemScript: String): List<String> =
        stringList(JsBundle.BTC, "bridge.getSignatureWithSeedHex", JsArgs.of(seedHex, signOrder.toString(), inputsOutputs, redeemScript))

    /**
     * Legacy BTC `3…` (P2SH) multisig: `getSignatureWithSeedHex(seed, 'signOrder', json, redeemScript)` of the **old**
     * bitcoinjs bundle (iOS `QtumJSBridge.getSignatureWithSeedHexForBTCOldMs3Address`, all four arguments strings).
     */
    suspend fun btcOldP2shSignatures(seedHex: String, signOrder: Int, inputsOutputs: String, redeemScript: String): List<String> =
        stringList(JsBundle.BTC_OLD, "bridge.getSignatureWithSeedHex", JsArgs.of(seedHex, signOrder.toString(), inputsOutputs, redeemScript))

    /** `getPrivkeyFromSeedHex(seed, index)` of the BTC bundle (LTC / DOGE / DASH / DGB multisig key). */
    suspend fun btcPrivateKey(seedHex: String, index: Int = 0): String =
        JsResults.nonEmptyString(engines.engine(JsBundle.BTC).call("bridge.getPrivkeyFromSeedHex", JsArgs.of(seedHex, index)), JsBundle.BTC, "bridge.getPrivkeyFromSeedHex")

    /** `getWIFFromSeedHex(seed, "0", 0, false)` (ZEC multisig key). */
    suspend fun btcWif(seedHex: String, seedTypePath: String = "0", index: Int = 0, isChange: Boolean = false): String =
        JsResults.nonEmptyString(engines.engine(JsBundle.BTC).call("bridge.getWIFFromSeedHex", JsArgs.of(seedHex, seedTypePath, index, isChange)),
            JsBundle.BTC, "bridge.getWIFFromSeedHex")

    /** LTC / DOGE / DASH / DGB: `getSignatureWithPrivateKey(key, json, m, json pubKeys)`. */
    suspend fun bitcoreSignatures(bundle: JsBundle, privateKey: String, inputsOutputs: String, minRequired: Int, publicKeys: List<String>): List<String> =
        stringList(bundle, "bridge.getSignatureWithPrivateKey", JsArgs.of(privateKey, inputsOutputs, minRequired, jsonText(publicKeys)))

    /** BCH: `getSignatureWithSeedHex(seed, json, m, json pubKeys)`. */
    suspend fun bchSignatures(seedHex: String, inputsOutputs: String, minRequired: Int, publicKeys: List<String>): List<String> =
        stringList(JsBundle.BCH, "bridge.getSignatureWithSeedHex", JsArgs.of(seedHex, inputsOutputs, minRequired, jsonText(publicKeys)))

    /** ZEC: `getSignatureWithPrivateKey(wif, json, signOrder, redeemScript)`. */
    suspend fun zecSignatures(wif: String, inputsOutputs: String, signOrder: Int, redeemScript: String): List<String> =
        stringList(JsBundle.ZEC, "bridge.getSignatureWithPrivateKey", JsArgs.of(wif, inputsOutputs, signOrder, redeemScript))

    // endregion

    // region plumbing

    private suspend fun eth(fn: String, vararg args: Any?): JsonElement = engines.engine(JsBundle.ETH).call("bridge.$fn", JsArgs.of(*args))

    private suspend fun ext(key: SpendKey, base: String, tail: Array<Any?>): SignedEvmTx {
        val (fn, args) = when (key) {
            is SpendKey.Seed -> "bridge.${base}BySeedHex" to JsArgs.of(key.seedHex, key.indexNo, *tail)
            is SpendKey.PrivateKey -> "bridge.${base}ByPrivateKey" to JsArgs.of(key.privateKeyHex, *tail)
        }
        val payload = engines.engine(JsBundle.ETH_EXT).callForEvent(fn, args, JsEventSpec.of("transaction")).payload
        val i = payload.indexOf(':')
        if (i <= 0 || i == payload.length - 1) throw JsResultFormatException(JsBundle.ETH_EXT, fn, "txHash:signedTx")
        return SignedEvmTx(payload.substring(0, i), payload.substring(i + 1))
    }

    private fun vrs(result: JsonElement): MultiSigSignature {
        val arr = result as? JsonArray ?: throw JsResultFormatException(JsBundle.ETH, "generateMultiSig", "[v, r, s]")
        if (arr.size < 3) throw JsResultFormatException(JsBundle.ETH, "generateMultiSig", "[v, r, s]")
        // iOS: `"\(o)"` — numbers stringified (v may be a number).
        val parts = arr.take(3).map { e ->
            val p = e as? JsonPrimitive ?: throw JsResultFormatException(JsBundle.ETH, "generateMultiSig", "[v, r, s]")
            if (p is JsonNull) throw JsResultFormatException(JsBundle.ETH, "generateMultiSig", "[v, r, s]")
            if (!p.isString) p.content.toBigDecimalOrNull()?.stripTrailingZeros()?.toPlainString() ?: p.content else p.content
        }
        return MultiSigSignature(parts[0], parts[1], parts[2])
    }

    private fun hashAndRaw(result: JsonElement, fn: String): SignedEvmTx {
        val v = JsResults.stringArray(result, JsBundle.ETH, fn, minSize = 2)
        return SignedEvmTx(txHash = v[0], rawTx = v[1])
    }

    private suspend fun sol(fn: String, args: JsonArray, parts: Int): List<String> {
        val payload = engines.engine(JsBundle.SOL).callForEvent(fn, args, JsEventSpec.of("mstransaction"), SOL_TIMEOUT).payload
        val p = payload.split(':').filter { it.isNotEmpty() }
        if (p.size != parts) throw JsResultFormatException(JsBundle.SOL, fn, "$parts colon-separated parts")
        return p
    }

    private suspend fun stringList(bundle: JsBundle, fn: String, args: JsonArray): List<String> {
        val r = engines.engine(bundle).call(fn, args)
        val v = JsResults.stringArray(r, bundle, fn, minSize = 1)
        return v
    }

    private fun asObject(e: JsonElement): JsonObject? = when (e) {
        is JsonObject -> e
        is JsonPrimitive -> if (e.isString && e.content.trimStart().startsWith("{")) {
            runCatching { Json.parseToJsonElement(e.content) as? JsonObject }.getOrNull()
        } else {
            null
        }
        else -> null
    }

    private fun JsonObject.text(key: String): String? = (this[key] as? JsonPrimitive)?.contentOrNull

    // endregion

    /** Result of [solCreateMultisig]. */
    data class SolCreateResult(val hexTx: String, val multisigPda: String, val multisig: String, val ranInt: Long)

    companion object {
        /** accidentProtection value of enterprise contracts (0 standard, 1 accident protection, 2 CA, 3 enterprise). */
        const val ENTERPRISE_AP: Int = 3
        const val SOL_NATIVE_MINT: String = "11111111111111111111111111111111"
        private const val OB_PREFIX = "obtransaction:"
        /** Default wait of the TRX bundle's asynchronous calls (single proposals). */
        internal const val TRX_TIMEOUT = 60_000L
        private const val SOL_TIMEOUT = 60_000L

        /** iOS `[String].toJsonString()` for JSON-string arguments. */
        fun jsonText(values: List<String>): String = JsonArray(values.map { JsonPrimitive(it) }).toString()
    }
}

/** Key used for an outer transaction: HD seed + ETH index, or a private-key wallet's key. */
sealed interface SpendKey {
    class Seed(val seedHex: String, val indexNo: Int) : SpendKey {
        override fun toString(): String = "Seed(<redacted>, $indexNo)"
    }

    class PrivateKey(val privateKeyHex: String) : SpendKey {
        override fun toString(): String = "PrivateKey(<redacted>)"
    }
}

/** Collected `r / s / v` arrays for `spend()` (strings, as the server returns them). */
data class EvmSigs(val rs: List<String>, val ss: List<String>, val vs: List<String>)

/** Gas of an outer transaction (wei); [priorityWei] is ignored by legacy builders. */
data class EvmGas(val limit: Long, val priceWei: BigInteger, val priorityWei: BigInteger)
