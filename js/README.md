# js/ — the JavaScript engines behind OwnbitCore's chain bridges

Ownbit derives keys and addresses and signs transactions for most chains inside JavaScript bundles that the Swift
bridges (`iOS/Sources/OwnbitCore/Chains/`) load into a `JSContext` or a hidden `WKWebView`. This folder holds exactly the
files Ownbit iOS 5.x ships for the chains Ownbit 5.0 supports, under the same directory and file names (the bridges load
them by name), plus readable sources and the tools that reproduce the bundles Ownbit patched or built itself.

* **Vendor bundles are the app's files** (SHA-256 below). They are browserify / esbuild / webpack builds of
  third-party libraries; most of them also contain Ownbit's glue as their entry module (see "Where the Ownbit glue is").
  The extraction edited no code. Two kinds of string were replaced, each by a placeholder of exactly the same length, so every
  offset stays put (`tools/redact.py` holds the rules; `tools/verify.py` proves "app file + rules == repo file"):
  * third-party provider API keys in the Ownbit glue of two bundles (`trxjs-lib-app.js`, `tonjs-new.js`) were replaced
    with placeholders (`REDACTED…`); no signing path uses them;
  * the build machine's home path in npm package metadata (`"_where": "…"`) of seven bundles became
    `/build/ownbit-js0`, and the same user name in one code comment of the XLM glue became `ownbit dev`.
  Loading the app's original and the repo copy side by side gives identical results (`tools/compare_bundles.js`, below).
* **Ownbit-authored readable glue** (`index.js` in six folders) is published only where it is provably the source of the
  shipped entry module. These files are for review: no bridge loads them at runtime.

## What a host app has to bundle

Every file in the table whose "Loaded by" column names a bridge, plus `bitcoinjs-lib-bridge/mnemonic_words.txt`. Each
loader page (`*.html`) must sit in the same directory as the bundle it references (`<script src="…">` is relative;
the bridges call `loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())`). Do **not** bundle the
`index.js` glue sources or `tools/`: they are not needed at runtime, and six files named `index.js` would collide in a
flattened app bundle.

## Files

Kinds: **vendor** = third-party bundle, byte-identical (may contain Ownbit glue); **redacted** = vendor bundle with the
placeholder replacements above (the app's SHA-256 is given too);
**loader** = Ownbit's trivial HTML page that loads a bundle into `WKWebView`, byte-identical; **data** = third-party data,
byte-identical; **glue** = Ownbit-authored readable source, MIT header added. Library versions are given where the bundle
text records them ("n/r" = not recorded in the bundle).
Network column: the JavaScript may talk to third-party nodes (public blockchain RPC / API providers); that is
intended. Ownbit's own servers are only ever called from the native iOS / Android code, and OwnbitCore's Swift side
never calls them. The column says which network code a bundle contains and whether the Ownbit glue uses it.

| Directory | File | Bytes | SHA-256 | Kind | Loaded by | Upstream libraries identified in the bundle | Network (third-party nodes) |
|---|---|---:|---|---|---|---|---|
| adajs-lib-bridge | shelley.bundle.js | 2914389 | `cd95e68439d1134db5d5271d2af7c032e5a4d2b6b1c7804eb0a1e767aa63d058` | vendor (AdaLite frontend, Ownbit-patched) | AdaJSBridge via shelley_ada.html | AdaLite 5.2.13 web-wallet frontend (webpack, incl. its Cardano crypto / serialization code), @sentry/browser 5.22.3, tslib | AdaLite's own backend client (its server URL is empty in shelley_ada.html) and an error-reporting transport (DSN empty); the Ownbit glue drives AdaLite's `loadWallet` / `discoverAllAddresses` / `prepareTxPlan` — whether those contact a node was not traced (see HANDOFF) |
| adajs-lib-bridge | shelley_ada.html | 1514 | `b7de53aa65bfe0e731b3ac92a4249ae03c7414b4559be813d11d554a283fbc4c` | vendor (AdaLite app shell) | AdaJSBridge | AdaLite config `data-config` (server URL / DSN blanked by Ownbit) | no code; AdaLite's app-shell config (its public web-app token, one URL in a banner text) |
| bitcoinjs-lib-bridge | bitcoinjs-lib-app.js | 1892867 | `bf27b88640bc4a57cef1c76ef9dbd3d0b3dd35b4b273e1a3948a0a6143da2829` | vendor + Ownbit glue | BitcoinJSBridge (JSContext) and btc_index.html (WKWebView, for `generateMnemonicRandom`) | bitcoinjs-lib (6.x API: `initEccLib`, p2tr), bip39, bip32, ecpair, @noble/secp256k1, @noble/hashes, @scure/base, bitcoinjs-message, bip174, wif, bs58check, crypto-browserify (elliptic 6.5.5 / 6.5.3); n/r otherwise | none (URLs only in comments) |
| bitcoinjs-lib-bridge | btc_index.html | 192 | `5633c7e676314f29413e49f68378ab21804768bd698f40da935ddb7b147233dc` | loader | BitcoinJSBridge | — | none |
| bitcoinjs-lib-bridge | mnemonic_words.txt | 140561 | `aad29f1e4cba8259f80e49ef0630e438af0c893e07a8d5a4e5b822085e71104a` | data (the 8 BIP-39 wordlists, 2048 lines each) | mnemonic validation (app: `BILMnemonicValidator`), not a JS bridge | BIP-39 wordlists | none |
| bitcoincashjs-lib-bridge | bitcoincashjs-lib-app.min.js | 1000285 | `d6490cedd851235e38d2e0cf958f9ca921a18941e39e4ec0eeaa8fa686d2b56a` | vendor + Ownbit glue (minified, hand-edited) | BitcoinCashJSBridge (JSContext) | bitcoincashjs 0.1.10 (Bitbill fork), cashaddrjs, bip32, wif, bs58check, bigi 1.4.2, tiny-secp256k1, elliptic 6.4.1 / 3.0.3 | none |
| btctaprootjs-lib-bridge | btctaproot-lib-app.js | 845267 | `6621d31db32a180247a3ea4a3e665be8a04933131b9e3721807a060ef447cce7` | vendor + Ownbit glue (esbuild; rebuilt byte-identical from `tools/btc-taproot-js`) | BTCTaprootJSBridge via btc_taproot_index.html | bitcoinjs-lib 6.1.8, bip32 4.0.0, ecpair 2.1.0, @bitcoinerlab/secp256k1 1.2.0, @noble/curves 1.9.7, @noble/hashes 1.8.0, bip174 2.1.1, buffer 6.0.3 (from `tools/btc-taproot-js/package-lock.json`) | none |
| btctaprootjs-lib-bridge | btc_taproot_index.html | 299 | `079ecd07502647f7774590077690d96eae39bc9c900c8ae11196ad57793479b8` | loader | BTCTaprootJSBridge | — | none |
| dashjs-lib-bridge | dashjs-lib-app.min.js | 2526271 | `8b3b220f274168131e354cd5c35243039769229254ede76aad0cbfd7fca35f66` | redacted: build path (app copy `189a1feff5dcb8461fd7c1e51b7e0b84eae2df2b0fe20b794fec9019f2170b06`); vendor + Ownbit glue | DashJSBridge (JSContext) | @dashevo/dashcore-lib 0.16.10, @dashevo/x11-hash-js, bip39, wif, bs58check, elliptic 6.4.1 | none |
| dashjs-lib-bridge | index.js | 10433 | `5f77e8eb65220112d167a233148ead96fb90684f12ee0625b7bcc36fb1d54d05` | glue — modified: MIT header added (app copy `c0b48a7b4db5eb3d254b0c502840783f9be1098535a87223d2b6aadd62ff0e98`); no network code to remove | not loaded (source of module 1 of dashjs-lib-app.min.js) | — | none |
| digibytejs-lib-bridge | digibytejs-lib-app.min.js | 2246102 | `11928f2710fd8b467bd0661518afb4462633fe9dfaa5fd1f15196a6bd699ac21` | redacted: build path (app copy `a8061ff483198e22150470ef615b2d48df289d3189bbd7eb8f84e1dc59682647`); vendor + Ownbit glue | DigibyteJSBridge (JSContext) | litecore-lib-segwit 1.0.10, bitcoinjs-lib (3.x/4.x era), bitcoinjs-message, bip39, wif, elliptic 6.4.x | none |
| digibytejs-lib-bridge | index.js | 17433 | `ee6b60580d8959308d5a16e93e770a18bd513517c534c0e8007b8b0484f995ca` | glue — modified: MIT header added (app copy `d04196edf6cb1c523be49ee7ac6b580a85b71786fbcaf13937790b11075c8031`); no network code to remove | not loaded (source of module 1) | — | none (`signMessage` builds a Digi-ID callback URL string but sends nothing) |
| dogecoinjs-lib-bridge | dogecoinjs-lib-app.min.js | 1993434 | `a3fe770bf06459aa295c7e9b060f78256ffeccc26bfcf02f6d23c02265ab3d3e` | redacted: build path (app copy `05bac632734b854abf548ced0fb010597e80277eeb7b503798a0a3843c8bb6b5`); vendor + Ownbit glue | DogecoinJSBridge (JSContext) | dogecore-lib 0.14.0, bip39, wif, bs58check, scryptsy, elliptic 6.4.1 / 3.0.3 | none |
| dogecoinjs-lib-bridge | index.js | 10210 | `904e66526237ca7a7b4f2f8440ad25fa0b005e0f21841b7cecb9733c14a31530` | glue — modified: MIT header added (app copy `a67bf70dd00f941dd2411bc3be2fd3902866428bddcd8ec326f466f4a83c22d4`); no network code to remove | not loaded (source of module 1) | — | none |
| ethereumjs-lib-bridge | ethereumjs-lib-app.min.js | 1218028 | `cac08c1f18addce23cfeeb43c38622461e5c19e66dc051432583e08b15d2398c` | vendor + Ownbit glue (minified, hand-edited) | EthereumJSBridge (JSContext; also EthereumClassicJSBridge) | web3 0.19.1, ethereumjs-tx, ethereumjs-util, ethereumjs-wallet, ethereumjs-abi, ethereumjs-icap, hdkey, keythereum, bip39, crypto-js, scrypt.js, eosjs-ecc, bigi 1.4.2, elliptic 6.4.0 | web3 HttpProvider (XMLHttpRequest) — not used by the glue (no provider is set) |
| ethereumjs-lib-bridge | ethjs-ext-v2.js | 1443786 | `fed30318b3d3db8bddb7509b872250509cfd378f987fd3323a18b02398b03fe0` | vendor + Ownbit glue | EthereumExtJsBridge via ethext_index.html | ethers 5.8.0 (@ethersproject/* 5.8.0), elliptic 6.6.1, scrypt-js, aes-js | ethers providers (JSON-RPC / WebSocket and hosted-node providers with ethers' public default keys) — not used by the glue (Wallet / signing / ABI / hashing only) |
| ethereumjs-lib-bridge | ethext_index.html | 198 | `7a90c738fa399d0545997541fe98c043db80a1d6a992b8d78ea07c058743962b` | loader | EthereumExtJsBridge | — | none |
| filejs-lib-bridge | filjs-lib-app.js | 1314588 | `6453e06454b002ad4ec0099631aba45f5182e45fe28981d8f9208a58cfb5917f` | vendor + Ownbit glue | FilJSBridge via fil_index.html | @zondax/filecoin-signing-tools (pure-JS build), bip32, bip39, blakejs, borc, ipld-dag-cbor, secp256k1, elliptic 6.5.4 | none |
| filejs-lib-bridge | fil_index.html | 190 | `3b4839905cd3e5ef6f6af7e1b6368b5372a8981dd77eab37e07f0123459b987d` | loader | FilJSBridge | — | none |
| horizenjs-lib-bridge | zenjs-lib-app.min.js | 988854 | `c580b5b4ad47c8c83db46f97d33b62b9a3add521a84f83666d0ea84d5c5d4f34` | redacted: build path (app copy `d1af677dc715785131f9a524b959aad27a15b2ee7c66647a44568432d47140c7`); vendor + Ownbit glue | HorizenJSBridge (JSContext) | zencashjs (address / config / transaction / crypto), bip32, bip39, wif, bs58check, elliptic 6.4.x | none |
| horizenjs-lib-bridge | index.js | 9978 | `dd3b7f9eb7e535528dc66f274fac5eab94e6fe1c72349a8943b305c02d0b6563` | glue — modified: MIT header added, one `console.log` of private keys removed (app copy `778dc7df3d527fa235e7f790db72f46a1c03e0808006996e1cadbe2c00485a0a`); no network code to remove | not loaded (source of module 81) | — | none |
| litecoinjs-lib-bridge | litecoinjs-lib-app.min.js | 1686783 | `e822f99bf7e3dd3c03d7ab3dea9d5a6c6cb336fe4b3df6459978c3e6b29ed2f9` | redacted: build path (app copy `8b6a70cb8750c954380ef2e15770cb8168a75c270805570bad1e424e957b4b2c`); vendor + Ownbit glue | LitecoinJSBridge (JSContext) | litecore-lib-segwit 1.0.10, bs58check, wif, elliptic 6.4.x | none |
| pubsigner-lib-bridge | signer.js | 1044192 | `d89f76bdeec85d90fd88f07372100e9f4c07ab789530ac2bcffd52be536e7b05` | vendor (BitSigner 1.0.0 offline engine, Ownbit edition; SHA-256 pinned by the engine) | BILPublicSignerEngine (JSContext) | BitSigner 95baad4 + ownbit-edition patch (esbuild): @scure/bip39, @scure/bip32, @scure/base, @noble/curves, @noble/hashes, buffer, safe-buffer | none (5 URLs in license comments) |
| ripplejs-lib-bridge | ripplejs-lib-app.min.js | 1141105 | `d63aec38eb87c445d102c660ac16954ccafdd6136244ecc8b5637be87a0b8be1` | vendor + Ownbit glue (2019 bundle + 2026 patch, reproducible from `tools/js-bundles`) | RippleJSBridge (JSContext) | ripple-lib (RippleAPI), ripple-keypairs, ripple-binary-codec, ripple-address-codec, ripple-hashes, bip32, bip39, ws, https-proxy-agent, elliptic 6.4.0 / 5.2.1 | ripple-lib server connection (WebSocket) — not used by the glue (`new RippleAPI()` without a server; offline signing) |
| soljs-lib-bridge | soljs-lib-app.js | 2150836 | `a246bda1f98b3a0b906f8ab4abfe630c022d69cfa91ee8f3721ca35629d5f49e` | vendor + Ownbit glue | SolanaJSBridge via sol_index.html | @solana/web3.js (patched by Ownbit, see "Where the Ownbit glue is"), @solana/spl-token (Token-2022 aware), tweetnacl, ed25519-hd-key, buffer-layout, @solana/buffer-layout, borsh, jayson, rpc-websockets, superstruct, elliptic 6.5.4 / 6.5.3 | @solana/web3.js `Connection` (JSON-RPC over HTTP, WebSocket) — neutralised by Ownbit's patches: the glue's transaction functions sign offline and return the signed transaction (base64) to Swift; the app submits it. Blockhash and block height come from Swift; nothing is requested (read, not executed) |
| soljs-lib-bridge | sol_index.html | 246 | `5bffe7d7abfe8ffc7249d05fe54869819d38ceb805d83cc5935829445d2c9389` | loader | SolanaJSBridge | — | none |
| stackjs-lib-bridge | stxjs-new.js | 389660 | `26632d6ad8e87056f33d7101f75a2df24a357fa23d9873a08c29557f4c618307` | vendor + Ownbit glue | StackJSBridge via stx_index.html | @stacks/transactions, @stacks/network, @stacks/common, @noble/secp256k1, @noble/hashes, c32check, cross-fetch | @stacks/network fetch — not used by the glue (`sendToken` passes nonce and fee, so nothing is fetched; `broadcastTransaction` is imported, never called) |
| stackjs-lib-bridge | stx_index.html | 186 | `b4e06315f8a479258609ee1bfe087542a705e3f09451c679af2683df5c309d2e` | loader | StackJSBridge | — | none |
| stellarjs-lib-bridge | stellarjs-lib-app.min.js | 1682877 | `291abfa772dc7590623906fb4dc56fc350e5d8a6470ce94b46b6fb59ad51f5b4` | redacted: build path and author name (app copy `8c337981ccc221fc9b92fe3bfad0c42ba05ff982b22eff889eb80f17bdd84871`); vendor + Ownbit glue (2020 bundle + 2026 patch, reproducible from `tools/js-bundles`) | StellarJSBridge (UIWebView JSContext) | stellar-base, js-xdr, tweetnacl, bip32, bip39, create-hmac, lodash, core-js, elliptic 6.4.1 | none (stellar-base has no HTTP client) |
| stellarjs-lib-bridge | index.js | 31804 | `bab0507aff2cd4a59670ec5591cc411c1c73613b27edfae55085b6eb6b950c9e` | glue — modified: MIT header added, author name in one comment replaced (app copy `cb64f47b5455d8241498a9179c6ac785c2203c31561ebd4dc2ffd36da221b556`); no network code to remove | not loaded (source of module 434) | — | none |
| tonjs-lib-bridge | tonjs-new.js | 2178953 | `87f5bd38a235085024665eb0156cf6f882b8c408a3049e01fd3227ba18c051d2` | vendor + Ownbit glue, redacted: provider API key (app copy `f20283fde67edf64f211b8634b4aeb6dfc829a47a88254b279cc27360709b7a1`) | TonJSBridge via ton_index.html | tonweb 0.0.66 (its `HttpProvider.sendBoc` patched by Ownbit), tonweb-mnemonic, @ton/ton, @ton/core, @ton/crypto, axios | tonweb `HttpProvider` for a third-party TON API (API key replaced with a placeholder), @ton/ton client, axios — the glue builds the provider, but `sendBoc` is patched to hand the signed BOC to `window.ownbitRetTx` (Swift), so signing does not go out (read, not executed) |
| tonjs-lib-bridge | ton_index.html | 242 | `dd879ea89bb94fbbfbb8ca2b3e1d8f3d608ad7ada1b4d72e9f837a9c57282beb` | loader | TonJSBridge | — | none |
| tronjs-lib-bridge | trxjs-lib-app.js | 2597552 | `721bdb84242949655110f74018be27219d7315281d3213882f7ee1663ed84a8a` | vendor + Ownbit glue, redacted: provider API keys (app copy `a96d2a29c84a1581ade57c6d9ce7b4dc401f9d9ba1883c4418cb831d7af04d5f`) | TronJSBridge via trx_index.html | tronweb 5.3.1 (bundles ethers 6.8.0), @ethersproject/* 5.7.0, axios, @noble/curves, @noble/hashes, @tronweb3/google-protobuf, validator 13.11.0, elliptic 6.5.3 | TronWeb `HttpProvider` (axios) — **used**: `preSendTx` builds unsigned transactions on third-party TRON nodes, `extendTxForWc` (`extendExpiration`) asks a node for the new txID; `getAddress`, `getBase58AddrFromHex`, `isAddress`, `signTx`, `signTxCa`, `multiSignTx` are offline |
| tronjs-lib-bridge | trx_index.html | 190 | `09c3dcb260f641003dff3dd5f82f1597b00867606c65f641cbdb203d1ec0adb8` | loader | TronJSBridge | — | none |
| zcashjs-lib-bridge | zcashjs-lib-app-0251.js | 974916 | `5a819cf6747a83c20c7a8c21bdfdad003d5192d5898dad8b18342fd7c0a51117` | redacted: build path (app copy `cfcb522ec7817399f7b8c36130c8bef44e208269708913f2321bb370c23762c2`); vendor + Ownbit glue | ZcashJSBridge via zec_index.html | bitgo-utxo-lib (Zcash), blake2b / blake2b-wasm, wif, bigi 1.4.2, elliptic 6.4.1 | none |
| zcashjs-lib-bridge | index.js | 19144 | `64587ecf7a27471f4e444f20a393fa122a20a0178f08e30d425278aeb043556e` | glue — modified: MIT header added (app copy `b37f19e6acf0e7dbddec78741ab11045434f5778d9d7ecc4ca921f22b85178ae`); no network code to remove | not loaded (source of module 133) | — | none |
| zcashjs-lib-bridge | zec_index.html | 255 | `9710924856a26263af59f9d3615eba6cb0dca9bd6a52ca1fa489c713c062921e` | loader | ZcashJSBridge | — | none |

Network pattern counts in vendor files (`tools/verify.py`, pattern `fetch(` / `XMLHttpRequest` / `http(s)://` / `ws(s)://` /
`axios` / `.ajax`; most `http(s)://` hits are URLs in comments and package metadata):

| File | fetch( | XMLHttpRequest | http(s):// | ws(s):// | axios | .ajax |
|---|---:|---:|---:|---:|---:|---:|
| adajs-lib-bridge/shelley.bundle.js | 6 | 19 | 363 | 0 | 0 | 0 |
| adajs-lib-bridge/shelley_ada.html | 0 | 0 | 1 | 0 | 0 | 0 |
| bitcoincashjs-lib-bridge/bitcoincashjs-lib-app.min.js | 0 | 0 | 20 | 0 | 0 | 0 |
| bitcoinjs-lib-bridge/bitcoinjs-lib-app.js | 0 | 0 | 67 | 0 | 0 | 0 |
| btctaprootjs-lib-bridge/btctaproot-lib-app.js | 0 | 0 | 9 | 0 | 0 | 0 |
| dashjs-lib-bridge/dashjs-lib-app.min.js | 0 | 0 | 174 | 0 | 0 | 0 |
| digibytejs-lib-bridge/digibytejs-lib-app.min.js | 0 | 0 | 178 | 0 | 0 | 0 |
| dogecoinjs-lib-bridge/dogecoinjs-lib-app.min.js | 0 | 0 | 165 | 0 | 0 | 0 |
| ethereumjs-lib-bridge/ethereumjs-lib-app.min.js | 0 | 18 | 9 | 0 | 0 | 0 |
| ethereumjs-lib-bridge/ethjs-ext-v2.js | 18 | 0 | 54 | 0 | 0 | 0 |
| filejs-lib-bridge/filjs-lib-app.js | 0 | 0 | 59 | 0 | 0 | 0 |
| horizenjs-lib-bridge/zenjs-lib-app.min.js | 0 | 0 | 45 | 0 | 0 | 0 |
| litecoinjs-lib-bridge/litecoinjs-lib-app.min.js | 0 | 0 | 166 | 0 | 0 | 0 |
| pubsigner-lib-bridge/signer.js | 0 | 0 | 5 | 0 | 0 | 0 |
| ripplejs-lib-bridge/ripplejs-lib-app.min.js | 1 | 3 | 134 | 2 | 0 | 0 |
| soljs-lib-bridge/soljs-lib-app.js | 2 | 0 | 94 | 2 | 0 | 0 |
| stackjs-lib-bridge/stxjs-new.js | 2 | 1 | 28 | 0 | 0 | 0 |
| stellarjs-lib-bridge/stellarjs-lib-app.min.js | 0 | 0 | 73 | 0 | 0 | 0 |
| tonjs-lib-bridge/tonjs-new.js | 2 | 3 | 60 | 0 | 65 | 0 |
| tronjs-lib-bridge/trxjs-lib-app.js | 0 | 3 | 149 | 0 | 19 | 0 |
| zcashjs-lib-bridge/zcashjs-lib-app-0251.js | 0 | 0 | 65 | 0 | 0 | 0 |

The same pattern finds nothing in the 34 Ownbit-authored files (the six glue sources, the nine loader pages, `tools/`).

## Where the Ownbit glue is inside each bundle

The functions the Swift bridges call (`bridge.<name>(…)`) are Ownbit's code inside the bundles:

| Bundle | Ownbit glue |
|---|---|
| bitcoinjs-lib-app.js | browserify module 1, lines 1–1067 (readable, babel output) |
| btctaproot-lib-app.js | `// src/index.js` section from line 18327 to the license comments; source: `tools/btc-taproot-js/src/index.js` |
| bitcoincashjs-lib-app.min.js | module 1, bytes 743–6145 (minified) |
| litecoinjs-lib-app.min.js | module 1, lines 1–601 |
| dogecoinjs-lib-app.min.js / dashjs-lib-app.min.js / digibytejs-lib-app.min.js | module 1 (lines 1–337 / 1–339 / 1–570); readable source: `index.js` |
| zenjs-lib-app.min.js | module 81, lines 29185–29478; readable source: `index.js` |
| zcashjs-lib-app-0251.js | module 133, lines 20803–21350; readable source: `index.js` |
| ethereumjs-lib-app.min.js | module 1, lines 1–300 (minified) |
| ethjs-ext-v2.js | module 1, lines 1–566 (readable) |
| trxjs-lib-app.js | module 1, lines 1–380 (readable), plus Ownbit's patch of TronWeb `trx.sign`: signing with a key that does not own the transaction throws `"obtransaction:" + unsigned tx`, which `preSendTx` uses to get node-built unsigned transactions back without signing or sending them (line 23113) |
| soljs-lib-app.js | module 1, lines 1–691 (readable, babel output), plus Ownbit's patches of @solana/web3.js: `Connection.sendTransaction` no longer fetches a blockhash (lines 19588–19590 commented out; the glue sets `recentBlockhash` / `lastValidBlockHeight` from Swift), `sendRawTransaction` returns the base64 transaction instead of sending it (line 19626), `sendAndConfirmTransaction` returns before confirming (line 15365), `getBlockHeight` returns early (line 18922) |
| ripplejs-lib-app.min.js | module 1, bytes 717–6523 (minified; the 2026 additions are `tools/js-bundles/xrp_ext.js` + `xrp_exports.js`) |
| stellarjs-lib-app.min.js | module 434, lines 52871–53712; readable source: `index.js` (2026 additions = `tools/js-bundles/xlm_ext.js`) |
| tonjs-new.js | module 1, lines 1–232 (readable), plus Ownbit's patch of tonweb `HttpProvider.sendBoc`: it hands the signed BOC to `window.ownbitRetTx` (Swift) instead of sending it |
| filjs-lib-app.js | module 1, lines 1–100 (readable) |
| stxjs-new.js | module 67, lines 12060–12127 (readable) |
| shelley.bundle.js | appended after `//# sourceMappingURL=frontend.bundle.js.map` (lines 75502–75557: `isAdaAddress`, `getAdaAddress`, `sendTx`), plus inline edits in AdaLite's code (e.g. `prepareTxPlan` signs and posts the transaction to `webkit.messageHandlers`) |
| signer.js | the whole file is the BitSigner engine (Ownbit edition); rebuilt from BitSigner sources, not from this repository |

## Verifying

```bash
python3 -I js/tools/verify.py --app <ios checkout>/wallet-ios-core/wallet-ios-core/components/JavaScriptBridge
python3 -I js/tools/verify.py            # without the app: manifest, glue == bundle module, network pattern, headers, no build path
node js/tools/compare_bundles.js <ios checkout>/wallet-ios-core/wallet-ios-core/components/JavaScriptBridge
```

`verify.py` checks: the folder holds exactly the files above; every vendor / loader / data file equals "app copy +
`tools/redact.py` rules" byte for byte (unchanged files: the app's SHA-256), and the files with replaced keys contain none
of the app's key values; each glue source equals its bundle's entry module (comments, whitespace and the browserify
wrapper aside, plus the one removed log line); the network pattern finds nothing in Ownbit-authored files; every
Ownbit-authored source file has the MIT header; neither the build-machine path nor the build user's name occurs in any
file of `js/` (the name is matched by its SHA-256 and not stored).

`compare_bundles.js` loads, for each of the nine bundles `redact.py` changes, the app's original and the repo copy the
way the bridge does (a bare global like `JSContext` for LTC / DOGE / DASH / DGB / ZEN; a `window` shim with crypto,
`TextEncoder` and a `webkit.messageHandlers` stub for ZEC / XLM / TRX / TON), and compares the results of: xpubs, first
two receive addresses and a digest of the index-0 private key / WIF of the BIP-39 vector "abandon x11 about" (UTXO
chains); `mnemonicToSeedHex`, the SEP-0005 account 0 and index-1 keys (XLM); `getAddress` / `getBase58AddrFromHex` /
`isAddress` for private key 1 (TRX); `mnemonicToAddress` with the posted message (TON). All nine were identical, and the
values match the published vectors (e.g. LTC `LUWPbpM43E2p…`, DOGE `DBus3bamQjgJ…`, XLM `GB3JDWCQJCWM…`).

Last run against the app (2026-10-26): `verify.py` `ALL OK`, `compare_bundles.js` `ALL OK`.

## Reproducing the patched XRP / XLM bundles

The shipped `ripplejs-lib-app.min.js` (2019) and `stellarjs-lib-app.min.js` (2020) had no lockfile, so the 2026 additions
(XRP tokens / multisig, XLM tokens / account multisig) were inserted into each bundle's entry module in place
(`tools/js-bundles/patch_xrp.js`, `patch_xlm.js`; fragments `xrp_ext.js`, `xrp_exports.js`, `xlm_ext.js`). Every
pre-existing export keeps its exact code. `unpatch.js` proves this without the app's git history:

```bash
node js/tools/js-bundles/unpatch.js js /tmp/bundles      # rebuilds the originals, checks md5, re-patch == shipped
cd /tmp/bundles && node <repo>/js/tools/js-bundles/test_xrp.js && node <repo>/js/tools/js-bundles/test_xlm.js
```

Result here: both originals match the md5 recorded when the patch was made (XRP `a597d4a4…`; XLM `6a8db0b6…` for the
app's file, `a3b1cd17…` for this repo's copy, which carries the replaced build path and author name — outside the
patched region), re-patching gives the shipped bytes, `test_xrp.js` PASS 34, `test_xlm.js` PASS 44. The fragment files carry the MIT header; the patch scripts strip those
leading `//` lines before inserting, so the inserted bytes are unchanged.

## Rebuilding the Taproot bundle

```bash
cd js/tools/btc-taproot-js && npm ci && sh build.sh      # writes js/btctaprootjs-lib-bridge/btctaproot-lib-app.js
npm test                                                 # BIP86 / BIP341 / BIP-322 vectors; python3 test/verify.py checks with embit
```

The build is deterministic: rebuilt here offline (esbuild 0.28.2, the locked dependency tree) it is byte-identical to
the shipped bundle, MIT header in `src/index.js` included (esbuild drops ordinary comments). `npm test` passes;
`test/verify.py` (embit) was not run here.

## Not included

* Glue sources that are **not** what ships (stale or test variants): `bitcoinjs-lib-bridge/index.js`,
  `bitcoincashjs-lib-bridge/index.js`, `litecoinjs-lib-bridge/index.js`, `ethereumjs-lib-bridge/index.js` and `util.js`,
  `ripplejs-lib-bridge/index.js`, `soljs-lib-bridge/sol_index.js`, `tonjs-lib-bridge/ton_index.js`,
  `filejs-lib-bridge/fil_index.js`, `stackjs-lib-bridge/stx_index.js`. The shipped glue for these chains is inside the
  bundles (table above).
* Files no supported bridge loads: `ethext-lib-bridge/*`, `ethereumjs-lib-app.js` (non-minified), `stellarjs-lib-app.js`,
  `ada.bundle.js` / `ada.html`, `eth_index.html` (test page), the loader pages whose bridges evaluate the bundle directly
  (`bch_index.html`, `ltc_index.html`, `doge.html`, `dash.html`, `dgb.html`, `zen.html`, `ripple.html`, `stellar.html`),
  `index_android.html`, and the help / UI pages (`_*.html`).
* Every bridge of a chain Ownbit 5.0 does not support.

Licenses: Ownbit-authored files are MIT (see the root `LICENSE`). Vendor bundles keep their own licenses (each bundle
carries the license comments of the libraries it contains); the BIP-322 vectors in `tools/btc-taproot-js/test/bip322` are
CC0.
