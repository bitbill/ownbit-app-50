// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.publicsigner.model


/**
 * A Bitcoin export profile (engine `BITCOIN_PROFILES`, `src/public-index.js`). **Declaration order = Ownbit display
 * order** (the order of every BTC address-type list: Taproot, Native SegWit, Nested SegWit, Legacy), then the two
 * BIP48 cosigner profiles of the "Multisig" segment. The default selection is [NATIVE].
 *
 * @property wire the engine `profile` value.
 * @property accountPath the account node the export carries (`crypto-account` origin).
 * @property isMultisig a BIP48 cosigner key (account xpub only, no threshold / policy; never "change").
 * @property ownbitAddressType the Ownbit `BtcAddressType` with the same addresses (`chain_accounts` / `addresses`
 *   `addressType`), `null` for the BIP48 profiles Ownbit never shows. Whether *this* wallet uses it ("Used in this
 *   Ownbit wallet") is the wallet's own data (`btcAddressKinds`); cold wallets never hold Taproot.
 */
enum class PsBitcoinProfile(
    val wire: String,
    val accountPath: String,
    val isMultisig: Boolean,
    val ownbitAddressType: Int?,
) {
    TAPROOT("taproot", "m/86'/0'/0'", isMultisig = false, ownbitAddressType = BtcAddressType.TAPROOT),
    NATIVE("native", "m/84'/0'/0'", isMultisig = false, ownbitAddressType = BtcAddressType.NATIVE_SEGWIT),
    NESTED("nested", "m/49'/0'/0'", isMultisig = false, ownbitAddressType = BtcAddressType.NESTED_SEGWIT),
    LEGACY("legacy", "m/44'/0'/0'", isMultisig = false, ownbitAddressType = BtcAddressType.LEGACY),
    MULTISIG_NATIVE("multisig-native", "m/48'/0'/0'/2'", isMultisig = true, ownbitAddressType = null),
    MULTISIG_NESTED("multisig-nested", "m/48'/0'/0'/1'", isMultisig = true, ownbitAddressType = null),
    ;

    /** First receive address path (`/0/0`); the cosigner profiles have no single address. */
    val firstAddressPath: String? get() = if (isMultisig) null else "$accountPath/0/0"

    companion object {
        /** Default of the "Single-sig" segment (Ownbit's and the engine's default). */
        val DEFAULT: PsBitcoinProfile = NATIVE

        /** Default of the "Multisig" segment. */
        val DEFAULT_MULTISIG: PsBitcoinProfile = MULTISIG_NATIVE

        /** Single-sig profiles in Ownbit display order. */
        val singleSig: List<PsBitcoinProfile> = entries.filter { !it.isMultisig }

        /** BIP48 cosigner profiles (native first). */
        val multisig: List<PsBitcoinProfile> = entries.filter { it.isMultisig }

        fun fromWire(wire: String?): PsBitcoinProfile? = entries.firstOrNull { it.wire == wire }
    }
}

/**
 * A Solana preset (engine `SOLANA_PROFILES`). [STANDARD] is Ownbit's own SOL address and the default; [TRUST] and
 * [LEGACY] are other addresses Ownbit never shows (offered under "More paths" with the "not shown in Ownbit" warning).
 */
enum class PsSolanaProfile(val wire: String, val path: String) {
    STANDARD("standard", "m/44'/501'/0'/0'"),
    TRUST("trust", "m/44'/501'/0'"),
    LEGACY("legacy", "m/44'/501'"),
    ;

    /** The same address as Ownbit's SOL account. */
    val matchesOwnbit: Boolean get() = this == STANDARD

    companion object {
        val DEFAULT: PsSolanaProfile = STANDARD

        fun fromWire(wire: String?): PsSolanaProfile? = entries.firstOrNull { it.wire == wire }
    }
}

/**
 * What a pairing QR carries (engine `outputMode`).
 *
 * @property bearsKey the QR carries a public key node (account xpub / hd-key / multi-accounts): logs `XPUB_EXPORTED`;
 *   an address-only QR logs `watchQRShown` instead.
 */
enum class PsOutputMode(val wire: String, val bearsKey: Boolean) {
    /** BTC `ur:crypto-account` (one output descriptor). */
    ACCOUNT_XPUB("accountXpub", bearsKey = true),

    /** EVM `ur:crypto-hdkey` (EIP-4527) / Solana `ur:crypto-multi-accounts`. */
    WALLET("wallet", bearsKey = true),

    /** Plain address text. */
    ADDRESS("address", bearsKey = false),
    ;

    companion object {
        fun fromWire(wire: String?): PsOutputMode? = entries.firstOrNull { it.wire == wire }
    }
}
