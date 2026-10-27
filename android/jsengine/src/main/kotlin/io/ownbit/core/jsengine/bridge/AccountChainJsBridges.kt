// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.jsengine.bridge

import io.ownbit.core.jsengine.JsArgs
import io.ownbit.core.jsengine.JsBundle
import io.ownbit.core.jsengine.JsEngineManager
import io.ownbit.core.jsengine.JsEventSpec
import io.ownbit.core.jsengine.JsResultFormatException
import io.ownbit.core.jsengine.JsResults
import kotlinx.serialization.json.JsonPrimitive

/**
 * Typed bridge over `js/sol/soljs-lib-app.js` - derivation half of iOS `SolanaJSBridge.swift`.
 * Key path `m/44'/501'/0'/0'` (ed25519, SLIP-0010) from the BIP39 seed.
 */
class SolanaJsBridge(engines: JsEngineManager) : JsBridge(engines, JsBundle.SOL) {

    /**
     * `bridge.generateAccount(seedHex)`: base58 public key, which is also the address (iOS stores it in
     * both `publicKey` and `address`).
     */
    suspend fun getAddress(seedHex: String): String = nonEmptyString(BRIDGE + "generateAccount", seedHex)

    /** `bridge.isValidAddress(a)`: any valid base58 ed25519 public key. */
    suspend fun isValidAddress(address: String): Boolean = bool(BRIDGE + "isValidAddress", address)
}

/**
 * Typed bridge over `js/ton/tonjs-new.js` (copied from iOS) - derivation half of iOS `TonJSBridge.swift`.
 * TON does not use BIP44: `@ton/crypto` `mnemonicToWalletKey` consumes the BIP39 words directly and the
 * wallet is WalletContractV4 (v4R2), workchain 0.
 */
class TonJsBridge(engines: JsEngineManager) : JsBridge(engines, JsBundle.TON) {

    /**
     * `bridge.mnemonicToAddress(mnemonic)` (async). The bundle both resolves the Promise and posts the
     * iOS `address` callback with `"<nonBounceable>|<raw>|<publicKeyHex>"`; the awaited return value is
     * used here (same string).
     */
    suspend fun getWalletAddress(mnemonic: String): TonWalletAddress {
        val function = BRIDGE + "mnemonicToAddress"
        val parts = nonEmptyString(function, mnemonic).split('|').filter { it.isNotEmpty() }
        if (parts.size != 3) throw JsResultFormatException(bundle, function, "nonBounceable|raw|publicKey")
        return TonWalletAddress(nonBounceable = parts[0], raw = parts[1], publicKeyHex = parts[2])
    }

    /** `bridge.isAddress(a)`: parses as a user-friendly TON address (`Address.parseFriendly`). */
    suspend fun isAddress(address: String): Boolean = bool(BRIDGE + "isAddress", address)
}

/**
 * Typed bridge over `js/xrp/ripplejs-lib-app.min.js` - derivation half of iOS `RippleJSBridge.swift`
 * (key: BIP32 `m/44'/144'/0'/0` child 0 inside the bundle) plus the 2026-10 indexed derivation of iOS
 * `BILXrpXlmJSBridge.swift`. Signing (payments, tokens, TrustSet, multisig) is `:signing` `XrpJsSigner`.
 */
class RippleJsBridge(engines: JsEngineManager) : JsBridge(engines, JsBundle.XRP) {

    /** `bridge.getPubAddrFromSeedHex(seedHex)`: public key + `r...` address (iOS `updateWallet(seed:)`). */
    suspend fun getPublicKeyAndAddress(seedHex: String): PublicKeyAddress =
        publicKeyAddress(BRIDGE + "getPubAddrFromSeedHex", seedHex)

    /** `bridge.getPubAddrFromPrivkey(hex)`. */
    suspend fun getPublicKeyAndAddressFromPrivateKey(privateKeyHex: String): PublicKeyAddress =
        publicKeyAddress(BRIDGE + "getPubAddrFromPrivkey", privateKeyHex)

    /** `bridge.getPrivkeyFromSeedHex(seedHex)` (iOS `seedHexToPrivateHex`, export / signing key). Secret. */
    suspend fun getPrivateKeyHex(seedHex: String): String = nonEmptyString(BRIDGE + "getPrivkeyFromSeedHex", seedHex)

    /** `bridge.getXrpAddrFromPubKey(pub)`. */
    suspend fun getAddressFromPublicKey(publicKey: String): String =
        nonEmptyString(BRIDGE + "getXrpAddrFromPubKey", publicKey)

    /** `bridge.isAddress(a)`. */
    suspend fun isAddress(address: String): Boolean = bool(BRIDGE + "isAddress", address)

    // region 2026-10 additions (iOS `BILXrpXlmJSBridge.swift` `RippleJSBridge.pubAddr`)

    /**
     * `bridge.getPubAddrFromSeedHexIndex(seedHex, i)`: BIP32 `m/44'/144'/0'/0/i` → **upper-case** compressed public
     * key + `r...` address. `i = 0` is the account-multisig signer key (same key and address as
     * [getPublicKeyAndAddress], whose public key is lower case); `i > 0` derives a fresh multisig account (`rFresh`).
     * [index] travels as a JS number; the bundle throws `invalid index` outside `0 ≤ i < 2^31`. Secret input.
     */
    suspend fun getPublicKeyAndAddressAtIndex(seedHex: CharArray, index: Int): PublicKeyAddress {
        val values = nonEmptyStrings(BRIDGE + "getPubAddrFromSeedHexIndex", 2, seedHex, index)
        return PublicKeyAddress(publicKey = values[0], address = values[1])
    }

    /**
     * `bridge.deriveAddressFromPubKey(pubHex)`: the `r...` address of a 33-byte compressed secp256k1 key (hex, either
     * case); the bundle throws `invalid public key` for anything else. No secret - the watch side uses it to check
     * a cold wallet's signer / fresh keys (offline M1) and `Signer.SigningPubKey` (M3 / M4).
     */
    suspend fun deriveAddressFromPublicKey(publicKeyHex: String): String =
        nonEmptyString(BRIDGE + "deriveAddressFromPubKey", publicKeyHex)

    // endregion
}

/**
 * Typed bridge over `js/xlm/stellarjs-lib-app.min.js` - derivation half of iOS `StellarJSBridge.swift`, plus the
 * 2026-10 account-multisig functions of iOS `BILXrpXlmJSBridge.swift` (indexed derivation, setup, proposal XDR build /
 * decode / sign). New wallets use SEP-0005 (`m/44'/148'/0'`, `isNew = true`). Single-sig signing (payments, tokens,
 * change_trust) is `:signing` `XlmJsSigner`.
 */
class StellarJsBridge(engines: JsEngineManager) : JsBridge(engines, JsBundle.XLM) {

    /**
     * `bridge.getPubAddrFromSeedHex(seedHex, isNew)`: raw ed25519 public key hex + `G...` address.
     * iOS always passes `isNew = true` (SEP-0005).
     */
    suspend fun getPublicKeyAndAddress(seedHex: String, isNew: Boolean = true): PublicKeyAddress =
        publicKeyAddress(BRIDGE + "getPubAddrFromSeedHex", seedHex, isNew)

    /** `bridge.getPubAddrFromPrivkey(secret)`: from an `S...` secret seed (private-key import). */
    suspend fun getPublicKeyAndAddressFromPrivateKey(secret: String): PublicKeyAddress =
        publicKeyAddress(BRIDGE + "getPubAddrFromPrivkey", secret)

    /** `bridge.getPrivkeyFromSeedHex(seedHex, isNew)`: the `S...` secret (iOS `seedHexToPrivateHex`). Secret. */
    suspend fun getSecret(seedHex: String, isNew: Boolean = true): String =
        nonEmptyString(BRIDGE + "getPrivkeyFromSeedHex", seedHex, isNew)

    /** `bridge.getXlmAddrFromPubKey(pub)`. */
    suspend fun getAddressFromPublicKey(publicKey: String): String =
        nonEmptyString(BRIDGE + "getXlmAddrFromPubKey", publicKey)

    /** `bridge.isAddress(a)` (federation `name*domain` handling lives in [io.ownbit.core.jsengine.chain.AddressValidator]). */
    suspend fun isAddress(address: String): Boolean = bool(BRIDGE + "isAddress", address)

    // region 2026-10 account multisig (iOS `BILXrpXlmJSBridge.swift` `StellarJSBridge`)
    // JSON payloads go in as **text** (the bundle `JSON.parse`s them): sequences are decimal strings inside that text
    // (Stellar sequences exceed 2^53). Every function returns synchronously or throws.

    /**
     * `bridge.getPubAddrFromSeedHexIndex(seedHex, k)`: SEP-0005 `m/44'/148'/k'` → raw ed25519 public key hex (lower
     * case) + `G...` address. `k = 0` is the multisig signer key (= [getPublicKeyAndAddress] with `isNew = true`);
     * `k > 0` the fresh multisig account `G_fresh`. [k] travels as a JS number (`0 ≤ k < 2^31`). Secret input.
     */
    suspend fun getPublicKeyAndAddressAtIndex(seedHex: CharArray, k: Int): PublicKeyAddress {
        val values = nonEmptyStrings(BRIDGE + "getPubAddrFromSeedHexIndex", 2, seedHex, k)
        return PublicKeyAddress(publicKey = values[0], address = values[1])
    }

    /**
     * `bridge.buildMsSetupTxWithSeedHexIndex(seedHex, k, info)`: the setup transaction of `G_fresh`
     * (`k > 0`), signed by `G_fresh`, as `[hashHex, V0 envelope base64]`. [infoJson] keys: `address` (`G_fresh`),
     * `sequence` (string), `serverTime`, `maxTime?` (`serverTime + 60 … + 3600`, default `+ 600`), `perOpFee`
     * (100…100000), `requireNum`, `signers` (`G…` in server order), `trustAssets` (`[{code, issuer}]`, ≤ 5). Throws
     * `derived address mismatch` when `m/44'/148'/k'` is not `address`, and on any window / fee / signer problem.
     */
    suspend fun buildMsSetup(seedHex: CharArray, k: Int, infoJson: String): HashAndXdr {
        val values = nonEmptyStrings(BRIDGE + "buildMsSetupTxWithSeedHexIndex", 2, seedHex, k, infoJson)
        return HashAndXdr(hashHex = values[0], xdr = values[1])
    }

    /**
     * `bridge.buildMsTxXdr(data)`: the **unsigned** `Transaction` XDR (not an envelope) of a multisig
     * proposal, `[hashHex, txXdrBase64]`. [dataJson] keys: `source`, `sequence` (the chain value as a string; the
     * transaction uses `+ 1`), `fee` (100…100000), `maxTime`, `memoType` (`none` / `text` / `id`), `memo`, `opType`
     * (`payment` / `create_account` / `change_trust`), `destination`, `amount` (decimal, ≤ 7 places),
     * `assetCode` / `assetIssuer` (token), `limit` (change_trust). No secret: watch wallets may call it.
     */
    suspend fun buildMsTxXdr(dataJson: String): HashAndXdr {
        val values = nonEmptyStrings(BRIDGE + "buildMsTxXdr", 2, dataJson)
        return HashAndXdr(hashHex = values[0], xdr = values[1])
    }

    /**
     * `bridge.decodeMsTxXdr(txXdrBase64)`: the strict structural decode of a proposal `Transaction`
     * XDR, returned as the bundle's **JSON text** `{source, fee, seqNum, minTime, maxTime, memoType, memo, opType,
     * destination, assetCode, assetIssuer, amount, limit, hashHex}` (`fee` / `seqNum` strings, the times numbers,
     * `amount` / `limit` raw int64 strings). Throws `xdr_decode_error`, `trailing_bytes`, `precondition_type`,
     * `op_count`, `op_source_present`, `memo_type`, `asset_type`, `change_trust_limit` or `op_type`. Value rules (fee
     * range, `minTime`, the `maxTime` window) are the caller's. No secret.
     */
    suspend fun decodeMsTxXdr(txXdrBase64: String): String {
        val function = BRIDGE + "decodeMsTxXdr"
        val result = raw(function, txXdrBase64)
        // iOS `guard result.isString, …, !s.isEmpty`.
        if (result !is JsonPrimitive || !result.isString || result.content.isEmpty()) {
            throw JsResultFormatException(bundle, function, "JSON text")
        }
        return result.content
    }

    /**
     * `bridge.signMsTxXdrWithSeedHex(seedHex, txXdrBase64)`: decodes [txXdrBase64] with the same
     * whitelist as [decodeMsTxXdr], computes the hash locally and signs it with the signer key `m/44'/148'/0'` →
     * `[hashHex, signatureBase64 (88 chars)]`. There is no "sign an arbitrary hash" function. Secret input.
     */
    suspend fun signMsTxXdr(seedHex: CharArray, txXdrBase64: String): HashAndSig {
        val values = nonEmptyStrings(BRIDGE + "signMsTxXdrWithSeedHex", 2, seedHex, txXdrBase64)
        return HashAndSig(hashHex = values[0], signature = values[1])
    }

    // endregion
}

/**
 * Typed bridge over `js/ada/shelley.bundle.js` (AdaLite) - iOS `AdaJSBridge.swift`. The bundle exposes
 * plain globals (no `bridge.` prefix).
 */
class CardanoJsBridge(engines: JsEngineManager) : JsBridge(engines, JsBundle.ADA) {

    /**
     * `getAdaAddress(entropyHex)` (async): the bundle posts `address` = `"<shelley>:<legacy>"` or a
     * failure. [entropyHex] is the BIP39 entropy (`BitcoinJsBridge.mnemonicToEntropy`), exactly as iOS
     * `AdaWalletModel.updateAdaWallet`. Secret input.
     */
    suspend fun getAddresses(entropyHex: String): CardanoAddresses {
        val function = "getAdaAddress"
        val event = engine.callForEvent(function, JsArgs.of(entropyHex), JsEventSpec.of(ADDRESS_CHANNEL))
        val parts = event.payload.split(':').filter { it.isNotEmpty() }
        if (parts.size != 2) throw JsResultFormatException(bundle, function, "shelley:legacy")
        return CardanoAddresses(shelley = parts[0], legacy = parts[1])
    }

    /** `isAdaAddress(a)`. */
    suspend fun isAddress(address: String): Boolean = JsResults.truthy(engine.call("isAdaAddress", JsArgs.of(address)))

    private companion object {
        const val ADDRESS_CHANNEL = "address"
    }
}

/**
 * Typed bridge over `js/fil/filjs-lib-app.js` (filecoin-signing-tools) - derivation half of iOS
 * `FilJSBridge.swift` (path `m/44'/461'/0'/0/0` inside the bundle).
 */
class FilecoinJsBridge(engines: JsEngineManager) : JsBridge(engines, JsBundle.FIL) {

    /** `bridge.getPubAddrFromSeed(seedHex)`: public key hex + `f1...` address. */
    suspend fun getPublicKeyAndAddress(seedHex: String): PublicKeyAddress =
        publicKeyAddress(BRIDGE + "getPubAddrFromSeed", seedHex)

    /** `bridge.getPubAddrFromPrivKey(key)`. */
    suspend fun getPublicKeyAndAddressFromPrivateKey(privateKey: String): PublicKeyAddress =
        publicKeyAddress(BRIDGE + "getPubAddrFromPrivKey", privateKey)

    /** `bridge.getPrivKeyFromSeed(seedHex)` (iOS `getPrivKeyFromSeedHex`, export / signing key). Secret. */
    suspend fun getPrivateKey(seedHex: String): String = nonEmptyString(BRIDGE + "getPrivKeyFromSeed", seedHex)

    /** `bridge.isAddress(a)`. */
    suspend fun isAddress(address: String): Boolean = bool(BRIDGE + "isAddress", address)
}

/**
 * Typed bridge over `js/stx/stxjs-new.js` (@stacks/transactions) - derivation half of iOS
 * `StackJSBridge.swift`. iOS derives the STX key from the **ETH** key `m/44'/60'/0'/0/0`
 * (`StackWalletModel.updateWallet(seed:)`), see [io.ownbit.core.jsengine.chain.ChainKeyDerivation].
 */
class StacksJsBridge(engines: JsEngineManager) : JsBridge(engines, JsBundle.STX) {

    /** `bridge.getAddressFromPrivateHex(hex)`: returns `[address, address]` (iOS stores both as pubkey/address). */
    suspend fun getPublicKeyAndAddress(privateKeyHex: String): PublicKeyAddress =
        publicKeyAddress(BRIDGE + "getAddressFromPrivateHex", privateKeyHex)

    /** `bridge.isAddress(a)`: `S...` prefix and 38..44 chars (the bundle's own rule). */
    suspend fun isAddress(address: String): Boolean = bool(BRIDGE + "isAddress", address)
}
