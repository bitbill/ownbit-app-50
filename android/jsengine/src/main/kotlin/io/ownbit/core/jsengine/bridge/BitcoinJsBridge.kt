// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.jsengine.bridge

import io.ownbit.core.jsengine.JsBundle
import io.ownbit.core.jsengine.JsEngineManager
import io.ownbit.core.jsengine.JsResultFormatException
import io.ownbit.core.jsengine.JsResults
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import java.security.SecureRandom

/**
 * Typed bridge over `js/btc/bitcoinjs-lib-app.js` - mirrors iOS `BitcoinJSBridge.swift`.
 *
 * Also hosts the chain-independent BIP39 functions (mnemonic generation / validation, mnemonic ->
 * seed / entropy), exactly as iOS does. A BIP39 passphrase is used only by [mnemonicToSeedHex] for wallets imported
 * with one; creation and every other call are passphrase-less.
 *
 * `seedTypePath` is the iOS `WalletModel.getSeedTypePath()`: `"0"` for normal BIP39 wallets or a
 * custom derivation path such as `m/44'/0'/0'/0` (then legacy / 49 / 84 / change all use that path).
 * It must be a *string* - the bundle calls `seedType.indexOf('m')` on it.
 *
 * Transaction signing goes through the same engine from `:signing` (`io.ownbit.core.chain.utxo.JsUtxoTxSigner`).
 */
class BitcoinJsBridge(engines: JsEngineManager) : JsBridge(engines, JsBundle.BTC) {

    private val random = SecureRandom()

    // ---- BIP39 ----------------------------------------------------------------------------------

    /**
     * Generates a new English BIP39 mnemonic. Entropy comes from [SecureRandom]; the bundle's
     * `bip39.entropyToMnemonic` turns it into words (same word list / checksum / format as iOS
     * `generateMnemonicRandom`, which runs the same bip39 code on WebCrypto randomness). The result
     * is re-validated before it is returned. Secret - never log or persist outside OBV2.
     */
    suspend fun generateMnemonic(strength: MnemonicStrength = MnemonicStrength.WORDS_12): String {
        val entropy = ByteArray(strength.entropyBits / 8)
        random.nextBytes(entropy)
        val entropyHex = CharArray(entropy.size * 2)
        try {
            for (i in entropy.indices) {
                val v = entropy[i].toInt() and 0xFF
                entropyHex[i * 2] = HEX[v ushr 4]
                entropyHex[i * 2 + 1] = HEX[v and 0x0F]
            }
            val mnemonic = entropyToMnemonic(entropyHex)
            val words = mnemonic.split(' ')
            if (words.size != strength.wordCount || !validateMnemonic(mnemonic)) {
                throw JsResultFormatException(bundle, FN_ENTROPY_TO_MNEMONIC, "valid ${strength.wordCount}-word mnemonic")
            }
            return mnemonic
        } finally {
            entropy.fill(0)
            entropyHex.fill('0')
        }
    }

    /** `bridge.bip39.entropyToMnemonic(hex)` with the default (English) word list. */
    suspend fun entropyToMnemonic(entropyHex: CharArray): String = nonEmptyString(FN_ENTROPY_TO_MNEMONIC, entropyHex)

    /** `bridge.bip39.entropyToMnemonic(hex)` with the default (English) word list. */
    suspend fun entropyToMnemonic(entropyHex: String): String = nonEmptyString(FN_ENTROPY_TO_MNEMONIC, entropyHex)

    /**
     * `bridge.validateMnemonic(m)`: checksum-valid in any of the 8 bundled word lists (English,
     * Chinese simplified / traditional, Japanese, French, Italian, Korean, Spanish). This is the final
     * arbiter after the native `BILMnemonicValidator` port (`:mnemonic` `Bip39Validator`).
     */
    suspend fun validateMnemonic(mnemonic: String): Boolean = bool(BRIDGE + "validateMnemonic", mnemonic)

    /**
     * `bridge.mnemonicToSeedHex(m, passphrase, 0)` → `bip39.mnemonicToSeedSync(m, passphrase)`: BIP39 seed (PBKDF2,
     * NFKD inside the bundle), 128 hex chars. Secret. [passphrase] `null` = the empty passphrase (every wallet except a
     * passphrase import); it is passed verbatim as data through [io.ownbit.core.jsengine.JsArgs] (quotes,
     * backslashes, U+2028 … need no escaping) and never logged. The caller wipes it.
     */
    suspend fun mnemonicToSeedHex(mnemonic: String, passphrase: CharArray? = null): String =
        nonEmptyString(BRIDGE + "mnemonicToSeedHex", mnemonic, passphrase ?: "", SEED_TYPE_BIP39)

    /** `bridge.mnemonicToEntropy(m)` over the 8 word lists; `null` when no list matches. Secret. */
    suspend fun mnemonicToEntropy(mnemonic: String): String? =
        JsResults.stringOrNull(raw(BRIDGE + "mnemonicToEntropy", mnemonic), bundle, BRIDGE + "mnemonicToEntropy")
            ?.takeIf { it.isNotEmpty() }

    // ---- extended public keys -------------------------------------------------------------------

    /** `bridge.getBitcoinXPublicKeys(seedHex, path)`: legacy m/44' [main, change, root(account)]. */
    suspend fun getXPublicKeys(seedHex: String, seedTypePath: String = BIP39_SEED_TYPE_PATH): ExtendedPublicKeys =
        triple(BRIDGE + "getBitcoinXPublicKeys", seedHex, seedTypePath)

    /** `bridge.getBitcoinXPublicKeysForBIP49(seedHex, path)`: nested SegWit m/49' ypubs [main, change, root]. */
    suspend fun getXPublicKeysForBip49(seedHex: String, seedTypePath: String = BIP39_SEED_TYPE_PATH): ExtendedPublicKeys =
        triple(BRIDGE + "getBitcoinXPublicKeysForBIP49", seedHex, seedTypePath)

    /** `bridge.getBitcoinXPublicKeysForBIP84(seedHex, path)`: native SegWit m/84' zpubs [main, change, root]. */
    suspend fun getXPublicKeysForBip84(seedHex: String, seedTypePath: String = BIP39_SEED_TYPE_PATH): ExtendedPublicKeys =
        triple(BRIDGE + "getBitcoinXPublicKeysForBIP84", seedHex, seedTypePath)

    /** `bridge.getBitcoinXPublicKeysForAll(seedHex, path)`: the six chain-level keys stored at wallet creation. */
    suspend fun getXPublicKeysForAll(
        seedHex: String,
        seedTypePath: String = BIP39_SEED_TYPE_PATH,
    ): BitcoinExtendedPublicKeys {
        val v = strings(BRIDGE + "getBitcoinXPublicKeysForAll", 6, seedHex, seedTypePath)
        return BitcoinExtendedPublicKeys(
            legacyMain = v[0],
            legacyChange = v[1],
            nestedSegwitMain = v[2],
            nestedSegwitChange = v[3],
            nativeSegwitMain = v[4],
            nativeSegwitChange = v[5],
        )
    }

    /** `bridge.getBitcoinXPublicKeysForAllRoot(seedHex, path)`: account-level xpub / ypub / zpub ("export xpub"). */
    suspend fun getXPublicKeysForAllRoot(
        seedHex: String,
        seedTypePath: String = BIP39_SEED_TYPE_PATH,
    ): BitcoinRootExtendedPublicKeys {
        val v = strings(BRIDGE + "getBitcoinXPublicKeysForAllRoot", 3, seedHex, seedTypePath)
        return BitcoinRootExtendedPublicKeys(legacy = v[0], nestedSegwit = v[1], nativeSegwit = v[2])
    }

    /** `bridge.getBitcoinMasterXPublicKey(seedHex, path)`: legacy receive-chain xpub (md5 of it is the wallet lookup key). */
    suspend fun getMasterXPublicKey(seedHex: String, seedTypePath: String = BIP39_SEED_TYPE_PATH): String =
        nonEmptyString(BRIDGE + "getBitcoinMasterXPublicKey", seedHex, seedTypePath)

    /** `bridge.getBitcoinChangeXPublicKey(seedHex, path)`: legacy change-chain xpub. */
    suspend fun getChangeXPublicKey(seedHex: String, seedTypePath: String = BIP39_SEED_TYPE_PATH): String =
        nonEmptyString(BRIDGE + "getBitcoinChangeXPublicKey", seedHex, seedTypePath)

    // ---- addresses ------------------------------------------------------------------------------

    /**
     * Addresses of a chain-level extended key for indexes `fromIndex..toIndex` (**inclusive**), as
     * iOS `getAddresses` / `getAddresses_sw_p` / `getAddresses_sw_d`:
     * [BitcoinAddressType.LEGACY] takes the xpub, [BitcoinAddressType.NESTED_SEGWIT] the ypub,
     * [BitcoinAddressType.NATIVE_SEGWIT] the zpub.
     */
    suspend fun getAddresses(
        type: BitcoinAddressType,
        extendedPublicKey: String,
        fromIndex: Long,
        toIndex: Long,
    ): List<String> {
        require(fromIndex in 0..toIndex) { "invalid index range" }
        val function = when (type) {
            BitcoinAddressType.LEGACY -> BRIDGE + "getBitcoinContinuousAddressByMasterXPublicKey"
            BitcoinAddressType.NESTED_SEGWIT -> BRIDGE + "getBtcContinuousP2shP2wpkhAddrByXpubkey"
            BitcoinAddressType.NATIVE_SEGWIT -> BRIDGE + "getBtcContinuousP2wpkhAddrByXpubkey"
            BitcoinAddressType.TAPROOT -> throw IllegalArgumentException("Taproot addresses come from BitcoinTaprootJsBridge")
        }
        val expected = (toIndex - fromIndex + 1).toInt()
        return strings(function, expected, extendedPublicKey, fromIndex, toIndex)
    }

    /**
     * `bridge.validateAddress(a)`: base58check, or bech32 / bech32m via bitcoinjs `fromBech32` (BIP350: witness v0
     * bech32, v1+ bech32m — `bc1p` Taproot addresses validate, a bad bech32m checksum is rejected).
     */
    suspend fun validateAddress(address: String): Boolean = bool(BRIDGE + "validateAddress", address)

    /** `bridge.address3ToM(a)`: LTC P2SH `3...` -> `M...` (returns the input when not convertible). */
    suspend fun address3ToM(address: String): String = nonEmptyString(BRIDGE + "address3ToM", address)

    /** `bridge.getAddressFromPublicKey(pub)`: legacy P2PKH address. */
    suspend fun getAddressFromPublicKey(publicKey: String): String =
        nonEmptyString(BRIDGE + "getAddressFromPublicKey", publicKey)

    // ---- private keys ---------------------------------------------------------------------------

    /**
     * `bridge.getPrivKeyInfoFromPrivKey(k)`: `[isWIF, counterpart]`; `null` when the key is neither hex
     * nor a `5`/`K`/`L` WIF (the bundle returns `[]`).
     */
    suspend fun getPrivateKeyInfo(privateKey: String): BitcoinPrivateKeyInfo? {
        val function = BRIDGE + "getPrivKeyInfoFromPrivKey"
        val result = raw(function, privateKey) as? JsonArray
            ?: throw JsResultFormatException(bundle, function, "array")
        if (result.size < 2) return null
        val isWif = (result[0] as? JsonPrimitive)?.booleanOrNull
            ?: throw JsResultFormatException(bundle, function, "[boolean, string]")
        val counterpart = (result[1] as? JsonPrimitive)?.takeIf { it.isString }?.content
            ?: throw JsResultFormatException(bundle, function, "[boolean, string]")
        return BitcoinPrivateKeyInfo(isWif, counterpart)
    }

    /** `bridge.getPublicKeyAndArressFromPrivateKey(k)` (sic): public key + legacy address of a hex key or WIF. */
    suspend fun getPublicKeyAndAddress(privateKey: String): PublicKeyAddress =
        publicKeyAddress(BRIDGE + "getPublicKeyAndArressFromPrivateKey", privateKey)

    /** `bridge.getPublicKeyAndArressFromPrivateKeyForAll(k)` (sic): public key + 1/3/bc1 addresses (compressed keys). */
    suspend fun getPublicKeyAndAddresses(privateKey: String): BitcoinKeyAddresses {
        val v = strings(BRIDGE + "getPublicKeyAndArressFromPrivateKeyForAll", 4, privateKey)
        return BitcoinKeyAddresses(publicKey = v[0], legacy = v[1], nestedSegwit = v[2], nativeSegwit = v[3])
    }

    /** `bridge.getPrivkeyFromWIF(wif)`: hex private key. Secret. */
    suspend fun getPrivateKeyFromWif(wif: String): String = nonEmptyString(BRIDGE + "getPrivkeyFromWIF", wif)

    /**
     * WIF export of one address key (iOS `getWIFFromSeedHex*`): `bridge.getWIFFromSeedHex` /
     * `...ForBIP49` / `...ForBIP84` `(seedHex, path, index, isChange)`. Secret.
     */
    suspend fun getWifFromSeedHex(
        seedHex: String,
        type: BitcoinAddressType,
        index: Int,
        isChange: Boolean,
        seedTypePath: String = BIP39_SEED_TYPE_PATH,
    ): String {
        val function = when (type) {
            BitcoinAddressType.LEGACY -> BRIDGE + "getWIFFromSeedHex"
            BitcoinAddressType.NESTED_SEGWIT -> BRIDGE + "getWIFFromSeedHexForBIP49"
            BitcoinAddressType.NATIVE_SEGWIT -> BRIDGE + "getWIFFromSeedHexForBIP84"
            // Taproot keys stay inside the Taproot bundle (no WIF export).
            BitcoinAddressType.TAPROOT -> throw IllegalArgumentException("no WIF for Taproot")
        }
        return nonEmptyString(function, seedHex, seedTypePath, index, isChange)
    }

    /** `bridge.getWIFFromSeedHexForGeneral(seedHex, path, index)`, e.g. path `m/44'/2301'/0'/0`. Secret. */
    suspend fun getWifFromSeedHexForPath(seedHex: String, path: String, index: Int): String =
        nonEmptyString(BRIDGE + "getWIFFromSeedHexForGeneral", seedHex, path, index)

    // ---- message signing ------------------------------------------------------------------------

    /**
     * `bridge.signMessage(wif, address, message)` - Bitcoin signed message, base64 signature. The
     * signature flavour follows [address] (`bc1q` -> p2wpkh, `3` -> p2sh(p2wpkh), else legacy). A hex
     * private key is accepted in place of the WIF. The message must already be trimmed (as iOS).
     */
    suspend fun signMessage(wif: String, address: String, message: String): String =
        nonEmptyString(BRIDGE + "signMessage", wif, address, encodeMessageForJs(message))

    /** `bridge.verifyMessageSignature(message, address, signature)`. */
    suspend fun verifyMessageSignature(message: String, address: String, signature: String): Boolean =
        bool(BRIDGE + "verifyMessageSignature", encodeMessageForJs(message), address, signature)

    private suspend fun triple(function: String, seedHex: String, seedTypePath: String): ExtendedPublicKeys {
        val v = strings(function, 3, seedHex, seedTypePath)
        return ExtendedPublicKeys(main = v[0], change = v[1], root = v[2])
    }

    companion object {
        /** `seedTypePath` of a normal BIP39 wallet (iOS `String(getSeedType())` with seed type 0). */
        const val BIP39_SEED_TYPE_PATH: String = "0"

        /** `seedType` argument of `mnemonicToSeedHex` (0 = BIP39; Electrum is not supported). */
        const val SEED_TYPE_BIP39: Int = 0

        private const val FN_ENTROPY_TO_MNEMONIC = BRIDGE + "bip39.entropyToMnemonic"
        private val HEX = "0123456789abcdef".toCharArray()
    }
}
