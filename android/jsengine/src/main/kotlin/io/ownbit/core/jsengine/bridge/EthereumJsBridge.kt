// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.jsengine.bridge

import io.ownbit.core.jsengine.JsBundle
import io.ownbit.core.jsengine.JsEngineManager

/**
 * Typed bridge over `js/eth/ethereumjs-lib-app.min.js` (legacy ethereumjs, EIP-155) - the derivation
 * half of iOS `EthereumJSBridge.swift`. Serves every EVM chain (ETH, BSC, ARB, BASE, OP, POLYGON,
 * HYPE, ETC): they all use the ETH key at `m/44'/60'/0'/0/N` and the same EIP-55 address.
 *
 * Also used for the TRX index-0 key (`m/44'/195'/0'/0/0`) and the STX key (ETH index 0), exactly as iOS.
 * Legacy / EIP-1559 transaction signing and multisig are in `:signing` (`io.ownbit.core.chain.evm.EvmJsSigner`).
 */
class EthereumJsBridge(engines: JsEngineManager) : JsBridge(engines, JsBundle.ETH) {

    /**
     * `bridge.seedHexToPubAddr(seedHex, "m/44'/60'/0'/0/<index>")`: chain-level xpub, public key and
     * checksummed address of ETH account [index] (iOS `getPublicKeyAndAddress(seed:indexNo:)`).
     */
    suspend fun getAccount(seedHex: String, index: Int = 0): EthereumAccount {
        require(index >= 0) { "index must be >= 0" }
        val v = strings(BRIDGE + "seedHexToPubAddr", 3, seedHex, ethPath(index))
        return EthereumAccount(extendedPublicKey = v[0], publicKey = v[1], address = v[2])
    }

    /**
     * `bridge.extPubKeyToPubAddr(xpub, index)`: public key + address of child [index] of the ETH chain
     * xpub (`m/44'/60'/0'/0`). Used for multi-address ETH, watch wallets and TRX index > 0.
     */
    suspend fun getAccountFromExtendedPublicKey(extendedPublicKey: String, index: Int): PublicKeyAddress {
        require(index >= 0) { "index must be >= 0" }
        return publicKeyAddress(BRIDGE + "extPubKeyToPubAddr", extendedPublicKey, index)
    }

    /**
     * `bridge.seedHexToPrivateHex(seedHex, path)` with the `0x` prefix removed (as iOS). Secret.
     */
    suspend fun getPrivateKeyHex(seedHex: String, path: String): String =
        strip0x(nonEmptyString(BRIDGE + "seedHexToPrivateHex", seedHex, path))

    /** ETH private key of account [index] (`m/44'/60'/0'/0/<index>`), no `0x`. Secret. */
    suspend fun getEthPrivateKeyHex(seedHex: String, index: Int = 0): String = getPrivateKeyHex(seedHex, ethPath(index))

    /** TRX private key of index 0 (`m/44'/195'/0'/0/0`, iOS `seedHexToTrxPrivateKey`), no `0x`. Secret. */
    suspend fun getTronPrivateKeyHex(seedHex: String): String = getPrivateKeyHex(seedHex, TRX_INDEX0_PATH)

    /** `bridge.getPubAddrFromPrivate(hex)`: public key + checksummed address of a private key (`0x` optional). */
    suspend fun getPublicKeyAndAddress(privateKeyHex: String): PublicKeyAddress =
        publicKeyAddress(BRIDGE + "getPubAddrFromPrivate", privateKeyHex)

    /** `bridge.toChecksumAddress(a)`: EIP-55 form. */
    suspend fun toChecksumAddress(address: String): String = nonEmptyString(BRIDGE + "toChecksumAddress", address)

    /** `bridge.isAddress(a)`: EVM address check used by every EVM chain in iOS `checkAddress`. */
    suspend fun isAddress(address: String): Boolean = bool(BRIDGE + "isAddress", address)

    /**
     * `bridge.signEthereumMessage(message, privateKeyHex)`: `personal_sign` style signature (rpc sig
     * hex). The private key must be bare hex without `0x` (the bundle hex-decodes it). The message must
     * already be trimmed (as iOS).
     */
    suspend fun signMessage(message: String, privateKeyHex: String): String =
        nonEmptyString(BRIDGE + "signEthereumMessage", encodeMessageForJs(message), strip0x(privateKeyHex))

    /**
     * `bridge.getMessageSignAddress(message, signature)`: recovers the signer as a **lower-case** `0x`
     * address (verify = case-insensitive compare); the bundle returns `"0x"` when recovery fails.
     */
    suspend fun recoverMessageSigner(message: String, signature: String): String =
        string(BRIDGE + "getMessageSignAddress", encodeMessageForJs(message), signature)

    companion object {
        /** TRX index-0 derivation path used by iOS `seedHexToTrxPrivateKey`. */
        const val TRX_INDEX0_PATH: String = "m/44'/195'/0'/0/0"

        /** `m/44'/60'/0'/0/<index>`. */
        fun ethPath(index: Int): String = "m/44'/60'/0'/0/$index"
    }
}
