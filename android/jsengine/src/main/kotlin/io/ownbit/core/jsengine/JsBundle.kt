// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.jsengine

/**
 * One JavaScript bundle shipped in `assets/js/<id>/`, hosted by exactly one hidden WebView page.
 *
 * The bundle files are byte-for-byte copies of the old Android app (TON: of iOS); most are the same files as
 * `js/` at the root of this repository (see `android/README.md` for the mapping and SHA-256 values). Several chains
 * share a bundle (all EVM chains use [ETH] /
 * [ETH_EXT]; BCH addresses come from the [BTC] xpub and are only *converted* by [BCH]).
 *
 * @property id asset directory name under `assets/js/`; the host page is `js/<id>/index.html`.
 * @property readyGlobal global JS name that must exist once the page finished loading. Used as the
 *   readiness probe, so a missing / broken bundle fails fast instead of timing out on the first call.
 * @property callTimeoutMillis default per-call timeout for this bundle.
 */
enum class JsBundle(
    val id: String,
    val readyGlobal: String,
    val callTimeoutMillis: Long = DEFAULT_CALL_TIMEOUT_MILLIS,
) {
    /** bitcoinjs-lib: BIP39 mnemonic/seed, BTC xpubs (44/49/84), addresses, WIF, message signing, BTC/LTC helpers. */
    BTC("btc", "bridge"),

    /** bitcoincashjs-lib: CashAddr conversion, BCH address validation and signing. */
    BCH("bch", "bridge"),

    /** litecore: LTC xpubs / addresses / signing. */
    LTC("ltc", "bridge"),

    /** dogecore: DOGE xpubs / addresses / signing. */
    DOGE("doge", "bridge"),

    /** dashcore: DASH xpubs / addresses / signing. */
    DASH("dash", "bridge"),

    /** digibyte: DGB xpubs / addresses / signing / Digi-ID. */
    DGB("dgb", "bridge"),

    /** zcash (bitcore based): ZEC transparent xpubs / addresses / signing. */
    ZEC("zec", "bridge"),

    /** horizen: ZEN xpubs / addresses / signing. */
    ZEN("zen", "bridge"),

    /** ethereumjs (legacy, EIP-155): EVM derivation, legacy tx, multisig signatures, message signing. */
    ETH("eth", "bridge"),

    /** ethers v5 (EIP-1559 "ethjs-ext"): type-2 tx signing, multisig V3 spend/admin, ERC-1271 WalletConnect. */
    ETH_EXT("ethext", "bridge"),

    /** TronWeb: TRX addresses, tx pre-build (network), sign / multi-sign (async channels). */
    TRX("trx", "bridge"),

    /** @solana/web3.js: SOL address, (multisig) tx signing (async channels). */
    SOL("sol", "bridge"),

    /** @ton/ton + tonweb (copied from iOS): v4R2 address from mnemonic, TON / jetton signing (async). */
    TON("ton", "bridge", callTimeoutMillis = 60_000),

    /** ripple-lib: XRP keys / addresses / payment signing. */
    XRP("xrp", "bridge"),

    /** stellar-base: XLM keys (SEP-0005) / addresses / tx signing. */
    XLM("xlm", "bridge"),

    /** AdaLite shelley bundle: ADA address discovery from BIP39 entropy and tx signing (async channels). */
    ADA("ada", "getAdaAddress", callTimeoutMillis = 90_000),

    /** filecoin-signing-tools (JS build): FIL keys / addresses / message signing. */
    FIL("fil", "bridge"),

    /** @stacks/transactions: STX address from private key, token transfer signing (async). */
    STX("stx", "bridge"),

    /**
     * iOS `xemjs-lib-bridge/xemjs-lib-app.js` (elliptic, copied from iOS): despite the name its only export is
     * `tronSignMessage(privHex, message)` - sha256 of the UTF-8 message, canonical secp256k1 signature, `0x` + r‖s‖v -
     * used by WalletConnect `tron_signMessage` (iOS `XemJSBridge.tronSignMessage`). Not published in `js/`.
     */
    TRX_MESSAGE("trxmsg", "bridge"),

    /**
     * Old bitcoinjs-lib (old Android `qtum/bitcoinjs-lib-app-old.js`, byte-identical to iOS
     * `qtumjs-lib-bridge/bitcoinjs-lib-app-old.js`): only `bridge.getSignatureWithSeedHex(seed, signOrder, json,
     * redeemScript)` for legacy BTC `3…` (P2SH) multisigs (iOS `QtumJSBridge.getSignatureWithSeedHexForBTCOldMs3Address`).
     * Not published in `js/`.
     */
    BTC_OLD("btcold", "bridge"),

    /**
     * iOS `btctaprootjs-lib-bridge/btctaproot-lib-app.js` (esbuild IIFE of bitcoinjs-lib 6.1.8 +
     * bip32 4 + ecpair 2 + @bitcoinerlab/secp256k1): BTC Taproot (bc1p, BIP86 key-path) xpubs / addresses, BIP350
     * validation and the transactions that spend Taproot inputs (iOS `BTCTaprootJSBridge`). Needs `BigInt` and
     * `crypto.getRandomValues` (BIP340 aux randomness) — both present in the WebView page (secure origin). The first
     * load is slow (pure-JS secp256k1): prewarm it when a send has Taproot UTXOs. The old [BTC] bundle keeps doing
     * everything else. Typed bridge: [io.ownbit.core.jsengine.bridge.BitcoinTaprootJsBridge].
     */
    BTC_TAPROOT("btctaproot", "bridge", callTimeoutMillis = 60_000),

    /**
     * Public protocol (BC-UR / PSBT coin-level signing for third-party wallets): the **Ownbit edition** of the
     * BitSigner offline engine (`pubsigner/signer.js`, the same file as `js/pubsigner-lib-bridge/signer.js`; BitSigner
     * 95baad4 + `deviceName` option + EVM networks 999 / 61). One JSON
     * function, `BitSignerEngine.dispatch(requestJson)`; the operation allowlist lives in Kotlin. Needs Android System
     * WebView 91+ (syntax; the engine polyfills `Object.hasOwn` / `.at()`), `BigInt`, `crypto.getRandomValues`. Host
     * page with the strictest CSP (`connect-src 'none'`, no `unsafe-eval`).
     *
     * Isolated page: receives the seed and untrusted frames / requests. Never warmed; one operation class per page
     * (`restart()` before, `discardPage()` after, under the bridge mutex).
     */
    PUBLIC_SIGNER("pubsigner", "BitSignerEngine", callTimeoutMillis = 60_000),

    /**
     * Same assets as [PUBLIC_SIGNER], on its own page (pages are keyed by entry): only the device's own unsealed,
     * verified public index reaches it (`capabilities`, `derivePublicAddresses`, `createPublicPairing`), so it may stay
     * loaded between pairing exports. Never receives a seed or external input. Not warmed at start; released by the
     * idle sweep.
     */
    PUBLIC_SIGNER_PAIRING("pubsigner", "BitSignerEngine", callTimeoutMillis = 60_000),
    ;

    /** Path of the host page relative to the app-assets origin. */
    val hostPath: String get() = "js/$id/index.html"

    companion object {
        /** Default per-call timeout. */
        const val DEFAULT_CALL_TIMEOUT_MILLIS: Long = 30_000
    }
}
