// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.jsengine.bridge

/** A public key (as the chain's bundle renders it) and the address derived from it. */
data class PublicKeyAddress(val publicKey: String, val address: String)

/**
 * Chain-level extended public keys of a BIP44-style UTXO chain: [main] = `m/44'/c'/0'/0` (receive),
 * [change] = `m/44'/c'/0'/1`, [root] = account level `m/44'/c'/0'` (what "export xpub" shows) when
 * the bundle returns it.
 */
data class ExtendedPublicKeys(val main: String, val change: String, val root: String?)

/**
 * The six chain-level BTC extended public keys iOS stores at wallet creation
 * (`bridge.getBitcoinXPublicKeysForAll`): legacy `m/44'` as xpub, nested SegWit `m/49'` as ypub,
 * native SegWit `m/84'` as zpub. With a custom path all six are derived from that single path.
 */
data class BitcoinExtendedPublicKeys(
    val legacyMain: String,
    val legacyChange: String,
    val nestedSegwitMain: String,
    val nestedSegwitChange: String,
    val nativeSegwitMain: String,
    val nativeSegwitChange: String,
)

/** Account-level BTC extended public keys (`m/44'/0'/0'` xpub, `m/49'` ypub, `m/84'` zpub). */
data class BitcoinRootExtendedPublicKeys(
    val legacy: String,
    val nestedSegwit: String,
    val nativeSegwit: String,
)

/**
 * BTC address flavours supported by Ownbit. The first three come from the old bitcoinjs bundle ([BitcoinJsBridge]);
 * [TAPROOT] only from [BitcoinTaprootJsBridge] — the old-bundle functions that take a type reject it.
 */
enum class BitcoinAddressType {
    /** P2PKH `1...`, m/44'. */
    LEGACY,

    /** P2SH-P2WPKH `3...`, m/49'. */
    NESTED_SEGWIT,

    /** P2WPKH `bc1q...`, m/84'. */
    NATIVE_SEGWIT,

    /** P2TR key-path `bc1p...`, m/86' (backend `BTC_SW_T`), served by [BitcoinTaprootJsBridge]. */
    TAPROOT,
}

/** Public key and all BTC addresses of one private key (`getPublicKeyAndArressFromPrivateKeyForAll`). */
data class BitcoinKeyAddresses(
    val publicKey: String,
    val legacy: String,
    val nestedSegwit: String,
    val nativeSegwit: String,
)

/**
 * Result of `bridge.getPrivKeyInfoFromPrivKey`: whether the input was a WIF, and the *other* encoding
 * (hex private key when the input was WIF, WIF when the input was hex). Secret - never log.
 */
class BitcoinPrivateKeyInfo(val isWif: Boolean, val counterpart: String) {
    override fun toString(): String = "BitcoinPrivateKeyInfo(isWif=$isWif, counterpart=<redacted>)"
}

/**
 * ETH account at `m/44'/60'/0'/0/N` as returned by `bridge.seedHexToPubAddr`: [extendedPublicKey] is
 * the chain-level xpub `m/44'/60'/0'/0` (shared by all indexes, stored for watch wallets and TRX
 * index > 0), [publicKey] the uncompressed 64-byte public key hex, [address] EIP-55 checksummed.
 */
data class EthereumAccount(
    val extendedPublicKey: String,
    val publicKey: String,
    val address: String,
)

/**
 * TRON address as returned by the TRX bundle: [hexAddress] is the `41...` hex form (iOS stores it in
 * `TronWalletModel.publicKey`), [base58Address] the `T...` form.
 */
data class TronAddress(val hexAddress: String, val base58Address: String)

/**
 * TON wallet (WalletContractV4 / v4R2, workchain 0) derived by `mnemonicToWalletKey`:
 * [nonBounceable] user-friendly `UQ...` address (iOS `tonWallet.address`), [raw] `0:<hex>` form
 * (iOS `tonWallet.publicKey`), [publicKeyHex] the ed25519 public key (iOS `tonRealPub`, used by TON
 * multisig).
 */
data class TonWalletAddress(val nonBounceable: String, val raw: String, val publicKeyHex: String)

/**
 * `[hashHex, xdrBase64]` of the XLM bundle's 2026-10 multisig functions: [hashHex] is the lower-case transaction hash
 * (`sha256(networkId ‖ ENVELOPE_TYPE_TX ‖ tx)`), [xdr] either the signed V0 `TransactionEnvelope`
 * (`buildMsSetupTxWithSeedHexIndex`) or the unsigned `Transaction` (`buildMsTxXdr`), base64.
 */
data class HashAndXdr(val hashHex: String, val xdr: String)

/**
 * `[hashHex, signatureBase64]` of `signMsTxXdrWithSeedHex`: the hash the bundle computed locally from the XDR and the
 * 64-byte ed25519 signature of the SEP-0005 signer key `m/44'/148'/0'` (88 base64 characters).
 */
data class HashAndSig(val hashHex: String, val signature: String)

/** Cardano addresses from the AdaLite bundle: [shelley] base address (`addr1...`) and [legacy] Byron address. */
data class CardanoAddresses(val shelley: String, val legacy: String)

/** Mnemonic length for wallet creation (English BIP39 word list, as iOS). */
enum class MnemonicStrength(val entropyBits: Int, val wordCount: Int) {
    /** 12 words / 128-bit entropy (default). */
    WORDS_12(128, 12),

    /** 24 words / 256-bit entropy. */
    WORDS_24(256, 24),
}
