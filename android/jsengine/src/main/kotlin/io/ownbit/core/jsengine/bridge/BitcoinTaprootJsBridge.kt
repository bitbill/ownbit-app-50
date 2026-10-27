// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.jsengine.bridge

import io.ownbit.core.jsengine.JsBundle
import io.ownbit.core.jsengine.JsEngineManager
import io.ownbit.core.jsengine.JsResultFormatException
import io.ownbit.core.jsengine.JsResults
import java.util.Base64
import java.util.Locale

/**
 * The BIP86 chain-level Taproot extended public keys (standard `xpub` version, what the backend's `BTC_SW_T`
 * registration wants): [receive] = `m/86'/0'/0'/0`, [change] = `m/86'/0'/0'/1`.
 */
data class TaprootXpubs(val receive: String, val change: String)

/** A signed BTC transaction as the bundles return it (`[txid, txHex]`). */
class BitcoinSignedTx(val txId: String, val rawHex: String) {
    override fun toString(): String = "BitcoinSignedTx(txId=$txId, hex=<${rawHex.length} chars>)"
}

/**
 * Result of [BitcoinTaprootJsBridge.verifyMessageBip322] (iOS `BTCTaprootJSBridge.BIP322Result`).
 * [jsValue] is the string the bundle returns.
 */
enum class Bip322Verification(val jsValue: String) {
    VALID("valid"),
    INVALID("invalid"),

    /**
     * Cannot be checked here (P2WSH / P2SH scripts, Taproot script path or annex, proof of funds, a `full` transaction
     * version other than 0 / 2): the signature may well be valid, so this is **never** shown as "invalid".
     */
    UNSUPPORTED("unsupported"),
    ;

    companion object {
        /** The value for [jsValue], `null` for anything else. */
        fun of(jsValue: String): Bip322Verification? = entries.firstOrNull { it.jsValue == jsValue }
    }
}

/** `bridge.bip322Hashes(address, message)`: BIP-322 `message_hash`, `to_spend` txid and `to_sign` txid (hex). */
data class Bip322Hashes(val messageHash: String, val toSpendTxId: String, val toSignTxId: String)

/**
 * Typed bridge over `js/btctaproot/btctaproot-lib-app.js` (iOS `BTCTaprootJSBridge.swift`):
 * BTC Taproot (bc1p, BIP86 key-path only, no script tree).
 *
 * - xpubs / addresses of HD wallets ([getTaprootXpubs], [getTaprootAddresses]) and the one `tr(key)` address of a
 *   private-key wallet ([getTaprootAddressFromPublicKey]);
 * - BIP350 validation ([validateAddress], [isTaprootAddress]);
 * - transactions that spend at least one Taproot input: [buildTransaction] (seed wallets — every non-Taproot input
 *   carries the `wif` the **old** BTC bundle derived for it) and [buildTransactionWithPrivateKey] (private-key
 *   wallets — all inputs signed with the one key, Taproot inputs with it tweaked). Transactions without a Taproot
 *   input keep going through the old bundle (iOS `BTCTransactionBuilder.build`);
 * - BIP-322 message signing for bc1p addresses ([signMessageBip322], [signMessageBip322WithPrivateKey]) and BIP-322
 *   verification ([verifyMessageBip322], [bip322Hashes]). Legacy "Bitcoin Signed Message"
 *   signatures (1 / 3 / bc1q) stay with the old bundle ([BitcoinJsBridge.signMessage]); [isLegacyMessageSignature]
 *   tells the two formats apart.
 *
 * Result shapes are checked exactly like iOS (`xpub` prefixes, 62-char `bc1p` addresses, 64-char txid) so a broken
 * bundle can never hand out an address or a transaction the app did not expect. BIP340 signatures carry fresh
 * auxiliary randomness (`crypto.getRandomValues`): the same data signs to a different hex each time, with the same
 * txid.
 */
class BitcoinTaprootJsBridge(engines: JsEngineManager) : JsBridge(engines, JsBundle.BTC_TAPROOT) {

    /** `bridge.getTaprootXpubs(seedHex)` → receive / change chain xpubs (`m/86'/0'/0'/0`, `…/1`). */
    suspend fun getTaprootXpubs(seedHex: CharArray): TaprootXpubs {
        val function = BRIDGE + "getTaprootXpubs"
        val v = strings(function, 2, seedHex)
        if (!v[0].startsWith(XPUB_PREFIX) || !v[1].startsWith(XPUB_PREFIX)) {
            throw JsResultFormatException(bundle, function, "[xpub…, xpub…]")
        }
        return TaprootXpubs(receive = v[0], change = v[1])
    }

    /**
     * `bridge.getTaprootAddresses(xpub, from, to)`: the bc1p addresses `fromIndex..toIndex` (**inclusive**) of a
     * chain-level xpub (receive or change).
     */
    suspend fun getTaprootAddresses(xpub: String, fromIndex: Long, toIndex: Long): List<String> {
        require(fromIndex in 0..toIndex) { "invalid index range" }
        val function = BRIDGE + "getTaprootAddresses"
        val expected = (toIndex - fromIndex + 1).toInt()
        val v = strings(function, expected, xpub, fromIndex, toIndex)
        if (v.size != expected || !v.all(::looksLikeTaproot)) {
            throw JsResultFormatException(bundle, function, "$expected bc1p addresses")
        }
        return v
    }

    /**
     * `bridge.getTaprootAddressFromPublicKey(pub)`: the key-path `tr(key)` address of one public key (compressed or
     * uncompressed — the x coordinate is the internal key). Private-key wallets (`btcAddress_sw_t`).
     */
    suspend fun getTaprootAddressFromPublicKey(publicKeyHex: String): String {
        val function = BRIDGE + "getTaprootAddressFromPublicKey"
        val address = nonEmptyString(function, publicKeyHex)
        if (!looksLikeTaproot(address)) throw JsResultFormatException(bundle, function, "bc1p address")
        return address
    }

    /** `bridge.validateAddress(a)`: any mainnet address the network can pay to, BIP350 (bech32m for v1+). */
    suspend fun validateAddress(address: String): Boolean = bool(BRIDGE + "validateAddress", address)

    /** `bridge.isTaprootAddress(a)`: mainnet bech32m, witness v1, 32-byte program. */
    suspend fun isTaprootAddress(address: String): Boolean = bool(BRIDGE + "isTaprootAddress", address)

    /**
     * `bridge.buildTransaction(seedHex, dataJson)` — seed wallets, the transaction has Taproot inputs. [dataJson] is
     * the old bundle's `signDatas` (`inputs`, `outputs`, `ophex`, `locktime`) with `segwit: "T"` Taproot inputs
     * (plus the server's `address` / `scriptPubKey`, checked by the bundle) and a `wif` on every other input.
     * Secret arguments; the result is not.
     */
    suspend fun buildTransaction(seedHex: CharArray, dataJson: String): BitcoinSignedTx =
        signed(BRIDGE + "buildTransaction", seedHex, dataJson)

    /**
     * `bridge.buildTransactionWithPrivateKey(privateKey, dataJson)` — private-key wallets, the transaction has Taproot
     * inputs. [privateKey] is the same string the old bundle's `buildTransactionWithOnePrivateKey` gets (WIF, or hex =
     * an **uncompressed** key, old-bundle rule).
     */
    suspend fun buildTransactionWithPrivateKey(privateKey: CharArray, dataJson: String): BitcoinSignedTx =
        signed(BRIDGE + "buildTransactionWithPrivateKey", privateKey, dataJson)

    // ---- BIP-322 message signing ---------------------------------------------------------------------------------
    //
    // Every argument travels as JSON (JsArgs) and is JSON.parse'd in the page, so a message keeps its quotes, line
    // breaks and emoji byte for byte. Unlike the old bundle's signMessage / verifyMessageSignature, the Taproot bundle
    // does NOT undo the iOS `_QUOTE_OWNBIT_` / `_NEWLINE_OWNBIT_` pre-encoding: the message is passed as is (iOS passes
    // it through `JSONSerialization` too).

    /**
     * `bridge.signMessageBip322(seedHex, isChange, index, address, message)` — seed wallets: the BIP-322 "simple"
     * signature (key path, SIGHASH_DEFAULT, base64 witness without the `smp` prefix: 88 characters, `AU…`) of
     * [message] with the key `m/86'/0'/0'/{isChange ? 1 : 0}/index`. [address] is the bc1p address of that index: the
     * bundle derives the key's address and **refuses to sign** (`address mismatch`) when it differs. The signature is
     * self-checked in the bundle before it is returned. BIP340 auxiliary randomness: every call gives another valid
     * signature. [message] must already be trimmed (as the legacy path). Secret argument; the result is not.
     */
    suspend fun signMessageBip322(seedHex: CharArray, isChange: Boolean, index: Long, address: String, message: String): String {
        require(index in 0L until BIP32_HARDENED_OFFSET) { "invalid index" }
        return nonEmptyString(BRIDGE + "signMessageBip322", seedHex, isChange, index, address, message)
    }

    /**
     * `bridge.signMessageBip322WithPrivateKey(privateKey, address, message)` — private-key wallets: the BIP-322
     * signature with the one key's bc1p [address] (checked like [signMessageBip322]). [privateKey] is the string
     * [buildTransactionWithPrivateKey] gets (WIF, or hex = uncompressed — same x-only key).
     */
    suspend fun signMessageBip322WithPrivateKey(privateKey: CharArray, address: String, message: String): String =
        nonEmptyString(BRIDGE + "signMessageBip322WithPrivateKey", privateKey, address, message)

    /**
     * `bridge.verifyMessageBip322(address, message, signature)` — BIP-322 verification: `smp…` / unprefixed (simple)
     * for P2TR key path and P2WPKH, `ful…` (full) for those plus P2SH-P2WPKH and P2PKH; whitespace inside [signature]
     * is ignored by the bundle. Not a mainnet address → [Bip322Verification.INVALID]; what needs a script interpreter
     * or the UTXO set → [Bip322Verification.UNSUPPORTED].
     */
    suspend fun verifyMessageBip322(address: String, message: String, signature: String): Bip322Verification {
        val function = BRIDGE + "verifyMessageBip322"
        return Bip322Verification.of(string(function, address, message, signature))
            ?: throw JsResultFormatException(bundle, function, "'valid' | 'invalid' | 'unsupported'")
    }

    /** `bridge.bip322Hashes(address, message)` — the BIP's `tx_hashes` vectors (tests / other implementations). */
    suspend fun bip322Hashes(address: String, message: String): Bip322Hashes {
        val function = BRIDGE + "bip322Hashes"
        val v = strings(function, 3, address, message)
        if (v.size != 3 || !v.all(::isHash256Hex)) throw JsResultFormatException(bundle, function, "[3 × 64 hex]")
        return Bip322Hashes(messageHash = v[0], toSpendTxId = v[1], toSignTxId = v[2])
    }

    private suspend fun signed(function: String, key: CharArray, dataJson: String): BitcoinSignedTx {
        val v = JsResults.stringArray(raw(function, key, dataJson), bundle, function, minSize = 2)
        val txId = v[0]
        val hex = v[1]
        if (txId.length != TXID_LENGTH || hex.isEmpty()) throw JsResultFormatException(bundle, function, "[txid, hex]")
        return BitcoinSignedTx(txId, hex)
    }

    companion object {
        private const val XPUB_PREFIX = "xpub"
        private const val TXID_LENGTH = 64

        /** Non-hardened BIP32 indexes are `0 until 2^31` (the bundle refuses others: `bad index`). */
        private const val BIP32_HARDENED_OFFSET = 0x8000_0000L

        /** Size of a legacy (BIP137 / Electrum) message signature: header byte + r + s. */
        private const val LEGACY_SIGNATURE_BYTES = 65

        /** Header bytes of legacy signatures: 27–34 P2PKH, 35–38 P2SH-P2WPKH, 39–42 P2WPKH (BIP137). */
        private val LEGACY_SIGNATURE_HEADERS = 27..42

        private fun isHash256Hex(s: String): Boolean =
            s.length == TXID_LENGTH && s.all { it in '0'..'9' || it in 'a'..'f' }

        /**
         * iOS `BTCTaprootJSBridge.isLegacyMessageSignature`: a legacy "Bitcoin Signed Message"
         * signature — after removing all whitespace, standard base64 (length a multiple of 4) of exactly 65 bytes whose
         * first byte is 27…42. BIP-322 signatures never look like that: a simple one starts with the witness count
         * (1, 2, …), a full one with the transaction version, and `smp` / `ful` / `pof` prefixed ones do not decode
         * to 65 bytes.
         */
        fun isLegacyMessageSignature(signature: String): Boolean {
            val text = signature.filterNot(Char::isWhitespace)
            if (text.isEmpty() || text.length % 4 != 0) return false
            val bytes = try {
                Base64.getDecoder().decode(text)
            } catch (e: IllegalArgumentException) {
                return false
            }
            return bytes.size == LEGACY_SIGNATURE_BYTES && (bytes[0].toInt() and 0xff) in LEGACY_SIGNATURE_HEADERS
        }

        /** Length of a mainnet P2TR address (`bc1p` + 58 bech32m characters). */
        const val TAPROOT_ADDRESS_LENGTH: Int = 62

        /**
         * iOS `BTCTaprootJSBridge.isTaprootAddress` (no checksum check): lower-cased `bc1p` prefix and 62 characters.
         * Used to classify addresses the server already vouched for (UTXO `addressTxt`); user input is validated with
         * [validateAddress].
         */
        fun looksLikeTaproot(address: String): Boolean {
            val a = address.lowercase(Locale.ROOT)
            return a.startsWith("bc1p") && a.length == TAPROOT_ADDRESS_LENGTH
        }
    }
}
