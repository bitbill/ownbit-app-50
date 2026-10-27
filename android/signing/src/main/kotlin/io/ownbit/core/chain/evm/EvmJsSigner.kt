// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.chain.evm

import io.ownbit.core.jsengine.JsArgs
import io.ownbit.core.jsengine.JsBundle
import io.ownbit.core.jsengine.JsEngineManager
import io.ownbit.core.jsengine.JsResultFormatException
import io.ownbit.core.jsengine.JsResults
import io.ownbit.core.jsengine.bridge.EthereumJsBridge
import io.ownbit.core.model.coin.ErcType
import io.ownbit.core.wallet.api.UnlockedSecrets
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import java.math.BigInteger

/**
 * The key an EVM transaction / message is signed with: an HD seed + ETH account index (`m/44'/60'/0'/0/<index>`), or
 * the raw private key of a private-key wallet. Holds secrets as `String`s only because the JS bridge needs them;
 * create it inside `WalletSecretAccess.withUnlocked { … }` and drop it when the block ends. `toString` is redacted.
 */
sealed class EvmSigningKey {
    /** HD wallet: 128-hex BIP39 seed and the ETH address index. */
    class Seed(val seedHex: String, val index: Int) : EvmSigningKey() {
        override fun toString(): String = "EvmSigningKey.Seed(index=$index, <redacted>)"
    }

    /** Private-key wallet: 64 hex digits, no `0x`, lower case. */
    class PrivateKey(val hex: String) : EvmSigningKey() {
        override fun toString(): String = "EvmSigningKey.PrivateKey(<redacted>)"
    }

    companion object {
        private val HEX_64 = Regex("^[0-9a-f]{64}$")
        private val HEX_128 = Regex("^[0-9a-f]{128}$")

        /**
         * The EVM key inside [secrets] (iOS `wallet.decryptSeed` / `PrivateKeyWalletModel.decryptPrivateKey`):
         * the seed for HD wallets, else the hex private key of a BTC / ETH private-key wallet. `null` when the wallet
         * has no usable EVM key (watch wallets, XLM / LTC / … private keys).
         */
        fun from(secrets: UnlockedSecrets, index: Int): EvmSigningKey? {
            secrets.seedHex?.let { seed ->
                val hex = String(seed).trim().lowercase()
                return if (HEX_128.matches(hex)) Seed(hex, index) else null
            }
            secrets.privateKey?.let { key ->
                val hex = EvmHex.strip0x(String(key).trim()).lowercase()
                return if (HEX_64.matches(hex)) PrivateKey(hex) else null
            }
            return null
        }
    }
}

/**
 * Everything the JS bundles need to sign one EVM transaction (iOS `ETHTransactionBuilder.build(txBuildDatas:)`).
 *
 * @property to recipient (token transfers: the token receiver), `null` = contract creation.
 * @property amount smallest unit (wei / token units / ERC1155 count).
 * @property gasPrice wei; for type 2 the max fee per gas.
 * @property priority type-2 max priority fee per gas (wei).
 * @property data native calldata as passed to the bundle (`""` or lower-case `0x…`).
 * @property token token parameters, `null` for a native transfer.
 */
data class EvmJsTx(
    val network: EvmNetwork,
    val eip1559: Boolean,
    val to: String?,
    val amount: BigInteger,
    val nonce: Long,
    val gasLimit: Long,
    val gasPrice: BigInteger,
    val priority: BigInteger,
    val data: String,
    val token: EvmJsToken?,
)

/** Token part of [EvmJsTx]: contract, ERC standard, NFT id and the NFT `from` address (legacy bundle only). */
data class EvmJsToken(
    val contract: String,
    val ercType: ErcType,
    val tokenId: String,
    val addressFrom: String,
)

/** `[txHash, rawTx]` returned by every signing function. */
data class EvmJsSigned(val txHash: String, val rawTx: String)

/** Public half of an HD wallet's ETH account: the chain xpub `m/44'/60'/0'/0` and the account's address. */
data class EvmSeedAccount(val xpub: String, val address: String)

/**
 * The only place EVM JS signing calls are made, with the exact functions / argument types iOS uses
 * (`components/JavaScriptBridge/EthereumJSBridge.swift`, `EthereumClassicJSBridge.swift`,
 * `ethereumjs-lib-bridge/EthereumExtJsBridge.swift`):
 *
 * - EIP-1559 (`JsBundle.ETH_EXT`, iOS `ethjs-ext-v2.js`): `signEthTransactionBySeedHex|ByPrivateKey`,
 *   `signTokenTransactionBySeedHex|ByPrivateKey` — promises resolving to `[txHash, signedTx]` (they also post the
 *   same data on the `transaction` channel, which our engine ignores).
 * - Legacy EIP-155 (`JsBundle.ETH`): `buildEthTxBySeedHex` / `buildEthTransaction`, `buildTokenTxBySeedHex` /
 *   `buildTokenTransaction`, ETC `buildEtcTxBySeedHex` / `buildEtcTransaction` (chain id 61 inside).
 * - `signTypedData(privKey, json)` (ETH_EXT), `ownbitWcInfo` digest (ETH_EXT), `signEthereumMessage` /
 *   `getMessageSignAddress` (ETH, through [EthereumJsBridge]).
 *
 * Amounts, gas values and nonces are passed as decimal **strings** or numbers exactly where iOS does.
 */
class EvmJsSigner(
    private val engines: JsEngineManager,
    private val ethereum: EthereumJsBridge,
) {

    /** Signs [tx] with [key]; returns the bundle's `[txHash, rawTx]`. */
    suspend fun signTransaction(key: EvmSigningKey, tx: EvmJsTx): EvmJsSigned = when {
        tx.network.isEtc -> signEtc(key, tx)
        tx.eip1559 && tx.token == null -> signEip1559Native(key, tx)
        tx.eip1559 -> signEip1559Token(key, tx, tx.token!!)
        tx.token == null -> signLegacyNative(key, tx)
        else -> signLegacyToken(key, tx, tx.token)
    }

    // iOS EthereumExtJSBridge.buildEthTransaction(seedHex:… / privateKey:…)
    private suspend fun signEip1559Native(key: EvmSigningKey, tx: EvmJsTx): EvmJsSigned {
        val common = arrayOf<Any?>(
            tx.to,
            tx.amount.toString(),
            tx.gasLimit.toString(),
            tx.gasPrice.toString(),
            tx.priority.toString(),
            tx.network.chainId,
            tx.nonce,
            tx.data,
        )
        return when (key) {
            is EvmSigningKey.Seed -> ext("bridge.signEthTransactionBySeedHex", key.seedHex, key.index, *common)
            is EvmSigningKey.PrivateKey -> ext("bridge.signEthTransactionByPrivateKey", key.hex, *common)
        }
    }

    // iOS EthereumExtJSBridge.buildTokenTransaction(seedHex:… / privateKey:…)
    private suspend fun signEip1559Token(key: EvmSigningKey, tx: EvmJsTx, token: EvmJsToken): EvmJsSigned {
        val common = arrayOf<Any?>(
            token.contract,
            tx.to,
            tx.amount.toString(),
            tx.gasLimit.toString(),
            tx.gasPrice.toString(),
            tx.priority.toString(),
            tx.network.chainId,
            tx.nonce,
            token.tokenId,
            token.ercType.raw,
        )
        return when (key) {
            is EvmSigningKey.Seed -> ext("bridge.signTokenTransactionBySeedHex", key.seedHex, key.index, *common)
            is EvmSigningKey.PrivateKey -> ext("bridge.signTokenTransactionByPrivateKey", key.hex, *common)
        }
    }

    // iOS EthereumJSBridge.buildTransaction(amountWei:addressTo:nonce:seed|privateKey:…)
    private suspend fun signLegacyNative(key: EvmSigningKey, tx: EvmJsTx): EvmJsSigned {
        val tail = arrayOf<Any?>(
            tx.amount.toString(),
            tx.to,
            tx.nonce.toString(),
            tx.gasPrice.toString(),
            tx.gasLimit.toString(),
            tx.data,
            tx.network.chainId,
        )
        return when (key) {
            is EvmSigningKey.Seed -> legacy("bridge.buildEthTxBySeedHex", key.seedHex, key.index, *tail)
            is EvmSigningKey.PrivateKey -> legacy("bridge.buildEthTransaction", key.hex, *tail)
        }
    }

    // iOS EthereumJSBridge.buildETHTokenTransaction(…). The legacy bundle's createErc721/1155TokenData append
    // `tokenId.substr(2)` unpadded, i.e. they expect a `0x` + 64-hex word; iOS passes the stored id as is (a decimal id
    // yields broken calldata). NFT ids are therefore passed as that word.
    private suspend fun signLegacyToken(key: EvmSigningKey, tx: EvmJsTx, token: EvmJsToken): EvmJsSigned {
        val tokenId = if (token.ercType.isNft) legacyTokenIdWord(token.tokenId) else token.tokenId
        return signLegacyToken(key, tx, token, tokenId)
    }

    private suspend fun signLegacyToken(key: EvmSigningKey, tx: EvmJsTx, token: EvmJsToken, tokenId: String): EvmJsSigned = when (key) {
        is EvmSigningKey.Seed -> legacy(
            "bridge.buildTokenTxBySeedHex",
            key.seedHex,
            key.index,
            tx.amount.toString(),
            tx.to,
            tx.nonce.toString(),
            token.contract,
            tx.gasLimit.toString(),
            tx.gasPrice.toString(),
            token.ercType.raw,
            token.addressFrom,
            tokenId,
            tx.network.chainId,
        )
        is EvmSigningKey.PrivateKey -> legacy(
            "bridge.buildTokenTransaction",
            tx.amount.toString(),
            tx.to,
            tx.nonce.toString(),
            token.contract,
            tx.gasLimit.toString(),
            tx.gasPrice.toString(),
            key.hex,
            token.ercType.raw,
            token.addressFrom,
            tokenId,
            tx.network.chainId,
        )
    }


    // iOS EthereumClassicJSBridge.buildETCTransaction(…) — chain id 61 is fixed inside the bundle.
    private suspend fun signEtc(key: EvmSigningKey, tx: EvmJsTx): EvmJsSigned {
        val tail = arrayOf<Any?>(
            tx.amount.toString(),
            tx.to,
            tx.nonce.toString(),
            tx.gasPrice.toString(),
            tx.gasLimit.toString(),
            tx.data,
        )
        return when (key) {
            is EvmSigningKey.Seed -> legacy("bridge.buildEtcTxBySeedHex", key.seedHex, key.index, *tail)
            is EvmSigningKey.PrivateKey -> legacy("bridge.buildEtcTransaction", key.hex, *tail)
        }
    }

    /**
     * `bridge.signTypedData(privKey, typedDataJson)` of the iOS ethers bundle: EIP-712 signature (`0x` r‖s‖v, v 27/28).
     * `EIP712Domain` is removed from `types` inside the bundle before hashing.
     */
    suspend fun signTypedData(privateKeyHex: String, typedDataJson: String): String {
        val fn = "bridge.signTypedData"
        val result = engines.engine(JsBundle.ETH_EXT).call(fn, JsArgs.of(privateKeyHex, typedDataJson))
        return JsResults.nonEmptyString(result, JsBundle.ETH_EXT, fn)
    }

    /**
     * EIP-712 digest of [typedDataJson] computed by the same ethers code that signs it (`ownbitWcInfo(zero, 1,
     * "eth_signTypedData_v4", json).digest` = `_TypedDataEncoder.hash(domain, types − EIP712Domain, message)`).
     * Used to verify typed-data signatures without re-implementing EIP-712.
     */
    suspend fun typedDataDigest(typedDataJson: String): ByteArray {
        val fn = "bridge.ownbitWcInfo"
        val result = engines.engine(JsBundle.ETH_EXT)
            .call(fn, JsArgs.of(EvmHex.ZERO_ADDRESS, 1, "eth_signTypedData_v4", typedDataJson))
        val text = JsResults.nonEmptyString(result, JsBundle.ETH_EXT, fn)
        val digest = runCatching { Json.parseToJsonElement(text).jsonObject["digest"] as? JsonPrimitive }.getOrNull()?.content
        return digest?.let { EvmHex.decode(it) }?.takeIf { it.size == 32 }
            ?: throw JsResultFormatException(JsBundle.ETH_EXT, fn, "{digest}")
    }

    /** ETH private key (bare hex) of account [index] (`bridge.seedHexToPrivateHex`, iOS strips `0x`). Secret. */
    suspend fun privateKeyHex(key: EvmSigningKey): String = when (key) {
        is EvmSigningKey.Seed -> ethereum.getEthPrivateKeyHex(key.seedHex, key.index)
        is EvmSigningKey.PrivateKey -> key.hex
    }

    /** Checksummed address of [key] (seed: `seedHexToPubAddr`; private key: `getPubAddrFromPrivate`). */
    suspend fun address(key: EvmSigningKey): String = when (key) {
        is EvmSigningKey.Seed -> ethereum.getAccount(key.seedHex, key.index).address
        is EvmSigningKey.PrivateKey -> ethereum.getPublicKeyAndAddress(key.hex).address
    }

    /** Address of child [index] of the ETH chain xpub `m/44'/60'/0'/0` (`bridge.extPubKeyToPubAddr`). */
    suspend fun addressFromXpub(xpub: String, index: Int): String =
        ethereum.getAccountFromExtendedPublicKey(xpub, index).address

    /**
     * Chain xpub `m/44'/60'/0'/0` and checksummed address of ETH account [index] of [seedHex] (`bridge.seedHexToPubAddr`,
     * iOS `getPublicKeyAndAddress(seed:indexNo:)`). Public data only; [seedHex] is a secret.
     */
    suspend fun seedAccount(seedHex: String, index: Int): EvmSeedAccount =
        ethereum.getAccount(seedHex, index).let { EvmSeedAccount(xpub = it.extendedPublicKey, address = it.address) }

    /** `personal_sign` / `eth_sign` signature (iOS `EthereumJSBridge.signEthereumMessage`, message pre-encoded). */
    suspend fun signPersonalMessage(message: String, privateKeyHex: String): String =
        ethereum.signMessage(message, privateKeyHex)

    /** Lower-case signer of a `personal_sign` signature, `"0x"` when recovery fails (iOS `getMessageSignAddress`). */
    suspend fun recoverPersonalMessageSigner(message: String, signature: String): String =
        ethereum.recoverMessageSigner(message, signature)

    private suspend fun ext(function: String, vararg args: Any?): EvmJsSigned = signed(JsBundle.ETH_EXT, function, *args)

    private suspend fun legacy(function: String, vararg args: Any?): EvmJsSigned = signed(JsBundle.ETH, function, *args)

    private suspend fun signed(bundle: JsBundle, function: String, vararg args: Any?): EvmJsSigned {
        val result = engines.engine(bundle).call(function, JsArgs.of(*args))
        val values = JsResults.stringArray(result, bundle, function, minSize = 2)
        if (values[0].isEmpty() || values[1].isEmpty()) throw JsResultFormatException(bundle, function, "[txHash, rawTx]")
        return EvmJsSigned(txHash = values[0], rawTx = values[1])
    }

    internal companion object {
        /** `0x` + 64-hex word of an NFT id given in decimal or `0x` hex (as the legacy bundle expects). */
        fun legacyTokenIdWord(tokenId: String): String =
            EvmHex.parseTokenId(tokenId)?.let { "0x" + EvmHex.uintWord(it) } ?: tokenId
    }
}
