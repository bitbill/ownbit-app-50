# Ownbit core — Android

The part of Ownbit Android 5.x that touches private keys: **mnemonic generation and validation, key storage, key
derivation and signing**, as Kotlin library modules of one Gradle project. The code is the app's own, with the user
interface, the code that talks to servers and the app wiring (dependency injection, database, settings storage) left
out; where a kept class used one of those, it now takes a small interface instead (listed below).

[中文说明](#中文说明)

| Module | Package(s) | What |
|---|---|---|
| [`vault`](vault) | `io.ownbit.core.crypto.{obv2,kdf,keystore,hash,util,biometric,pin}`, `io.ownbit.core.wallet.{secret,api,manage,biometric}` | Ownbit Vault v2 (`OBV2:`) envelopes, scrypt, the Android Keystore device key, the wallet secret vault (open / seal / re-seal on password change), biometric quick send (a Class 3 auth-per-use Keystore key that wraps the wallet password) |
| [`mnemonic`](mnemonic) | `io.ownbit.core.crypto.bip39`, `io.ownbit.core.model.wallet`, `io.ownbit.core.wallet.{internal,imports}` | BIP39 validation over the 8 word lists, BIP39 passphrase rules, the import check order, and the key part of creating an HD wallet (mnemonic → seed → public keys → sealed envelopes) |
| [`jsengine`](jsengine) | `io.ownbit.core.jsengine` | The JavaScript engine (one hidden, hardened WebView page per bundle; every argument passed as JSON data), the typed chain bridges (mnemonic generation, derivation, message signing), chain key derivation, private-key import, the public-protocol signer bridge |
| [`signing`](signing) | `io.ownbit.core.chain.*` | Transaction signing through the bundles (BTC and the UTXO chains, EVM, TRON, SOL, TON, XRP, XLM, FIL, STX, ADA, multisig) and the native checks around it: strict reading of what a UTXO bundle signs, verification of the signed UTXO transaction, EVM / TRON codecs, the TRON pre-sign verifier |
| [`publicsigner`](publicsigner) | `io.ownbit.core.publicsigner`, `io.ownbit.core.scanner.publicqr` | The cold-wallet public protocol around the pinned engine: request / answer models, Ownbit's independent Kotlin checks before and after the engine signs (PSBT, BC-UR, EVM / TRON / Solana payloads), the signed-outpoint memory, TronLink requests, the signing policy |
| [`common`](common) | `io.ownbit.core.common.log` | The one logger (off by default; never logs secrets) |

Package names are the app's, so a file here can be matched with the app. Android 8.0 (API 26) or later.

## How the keys are stored (Ownbit Vault v2 on Android)

Mnemonic, BIP39 seed, BIP39 passphrase, private key and WIF are stored only as `OBV2:` envelopes
([`Obv2Envelope`](vault/src/main/kotlin/io/ownbit/core/crypto/obv2/Obv2Envelope.kt)). The format is the iOS one
([`WalletSecretCipher.swift`](../iOS/Sources/OwnbitCore/Vault/WalletSecretCipher.swift)), and the tests open the iOS
package's known-answer envelopes:

| | Android | iOS v2 |
|---|---|---|
| Envelope | `"OBV2:"` + base64(JSON `v, kdf, n, r, p, dklen, salt, bind, dkfp?, cipher, nonce, ct, tag`) | same |
| KDF | scrypt N = 32768, r = 8, p = 1, 32-byte key, 16-byte random salt; parameters read from the envelope on decryption | same |
| Cipher | AES-256-GCM, 12-byte random nonce, 16-byte tag | same |
| Device binding | AES key = HMAC-SHA256(device key, scrypt key) | same |
| Device key | a non-exportable 256-bit **Android Keystore** HMAC-SHA256 key (StrongBox when the device has one, else TEE), no user authentication, destroyed on uninstall, never in a backup; the app only asks the Keystore for HMACs with it | 32 random bytes in a `ThisDeviceOnly` keychain item |
| `dkfp` (device-key fingerprint) | first 8 bytes of HMAC-SHA256(device key, `"fp"`) — the Keystore key cannot be exported | first 8 bytes of SHA-256(device key) |
| Salt | a fresh salt for every envelope; the fields of a wallet are scrypted concurrently (at most 2 at a time) | one salt for the fields of one wallet, 60-second scrypt-key cache |
| Portable envelopes (`bind: "none"`) | read and written (no cloud backup on Android 5.0) | iCloud mnemonic backup |
| scrypt implementation | libsodium `crypto_pwhash_scryptsalsa208sha256_ll` (through JNA; checked against RFC 7914 at first use), BouncyCastle as fallback | libscrypt |

Both platforms derive the same AES key from the same password, salt and device key, so a portable envelope opens on
either; a device-bound envelope only opens where its device key lives (the two fingerprint schemes never meet). Further
rules, all in [`vault`](vault):

- **Write only what opens**: every envelope is decrypted again with the same password and compared before it is kept
  (`encryptVerified`, iOS `reencryptToV2`).
- **Integrity**: the SHA-256 of each plaintext (mnemonic, seed, private key, WIF) is stored at creation and checked on
  every open ([`SecretVault`](vault/src/main/kotlin/io/ownbit/core/wallet/secret/SecretVault.kt)); the BIP39 passphrase
  has no hash (low entropy: a hash would invite offline guessing) and opens only together with the mnemonic.
- **Wrong password vs. moved data**: decryption never creates a device key; a missing or replaced key is reported as
  "re-import the recovery phrase", not as a wrong password. Three wrong passwords in a row suggest re-importing.
- **Bounds**: parameters read from an envelope are refused beyond 256 MiB of scrypt memory, `p > 16` or `dklen > 64`.
- **Signing access**: [`WalletSecretAccess.withUnlocked`](vault/src/main/kotlin/io/ownbit/core/wallet/api/WalletSecretAccess.kt)
  decrypts what signing needs (never the passphrase — the seed already includes it), runs the block and zeroes the
  arrays afterwards. Secrets are `CharArray` / `ByteArray`, never logged.
- **Password change** ([`WalletPasswordChanger`](vault/src/main/kotlin/io/ownbit/core/wallet/manage/WalletPasswordChanger.kt)):
  decrypt with the old password, re-seal every field (self-checked) with the new one, replace all envelopes in one
  transaction; any failure leaves the old ones. Biometric quick send is turned off afterwards.

### Biometric quick send

Optional, per wallet, off by default ([`BiometricSendVault`](vault/src/main/kotlin/io/ownbit/core/wallet/biometric/BiometricSendVault.kt)).
It wraps the **wallet password** — never the mnemonic or the seed — with a per-wallet Android Keystore key:

- AES-256-GCM, randomized encryption, user authentication required for **every use** (`setUserAuthenticationParameters(0,
  AUTH_BIOMETRIC_STRONG)` on API 30+, validity −1 below), invalidated when biometrics are enrolled; StrongBox first.
- The key is accepted only when its real `KeyInfo` shows it in secure hardware (TEE / StrongBox), authentication enforced
  by that hardware, Class 3 biometrics only, no validity window, invalidated by enrolment, not valid while on body
  ([`KeyInfoRules`](vault/src/main/kotlin/io/ownbit/core/crypto/biometric/KeyInfoRules.kt)), **and** an encryption without
  a prompt is refused by the Keystore (negative probe). Otherwise the device is "strong biometrics, no hardware key" and
  quick send cannot be turned on ([`CapabilityClassifier`](vault/src/main/kotlin/io/ownbit/core/crypto/biometric/CapabilityClassifier.kt)).
- The password is bound to its wallet as GCM associated data, decrypted only by the `Cipher` of a successful
  `BiometricPrompt.CryptoObject`, checked against the wallet's envelopes, and handed out as a single-use
  [`BiometricGrant`](vault/src/main/kotlin/io/ownbit/core/wallet/biometric/BiometricGrant.kt) bound to the wallet and the
  digest of the confirmed content, valid 60 s and wiped when the app goes to the background.
- [`WalletAuthorizationPolicy`](vault/src/main/kotlin/io/ownbit/core/wallet/biometric/WalletAuthorizationPolicy.kt):
  only personal sends and multisig initiate / approve / execute / deploy may use it; a value at or above the user's
  threshold (default 1,000 USD), an
  unknown value or a missing / older-than-24-hours price needs the prompt **and** the password. Prices come from the
  host app ([`UsdQuotes`](vault/src/main/kotlin/io/ownbit/core/wallet/biometric/WalletAuthorizationPolicy.kt)).
- The wrapped passwords live in a file in `noBackupFilesDir`, encrypted with a separate non-authenticated Keystore key
  ([`QuickSendRepository`](vault/src/main/kotlin/io/ownbit/core/wallet/biometric/QuickSendRepository.kt)); an unreadable
  file reads as "all off".

## How mnemonics are made and checked

- **Generation** ([`BitcoinJsBridge.generateMnemonic`](jsengine/src/main/kotlin/io/ownbit/core/jsengine/bridge/BitcoinJsBridge.kt)):
  128 or 256 bits of entropy from `java.security.SecureRandom`, turned into English words by the bundled BIP39 code
  (`bip39.entropyToMnemonic`), then validated again. (iOS draws the entropy inside the bundle with
  `crypto.getRandomValues`; the words are made by the same code.)
- **Import check** ([`MnemonicImportCheck`](mnemonic/src/main/kotlin/io/ownbit/core/wallet/imports/MnemonicImportCheck.kt)):
  the native [`Bip39Validator`](mnemonic/src/main/kotlin/io/ownbit/core/crypto/bip39/Bip39Validator.kt) (all 8 BIP39 word
  lists, NFKD lookups, `Locale.ROOT` case folding, fails closed when the lists cannot be loaded) checks words and count;
  the bundle's `validateMnemonic` is the final checksum authority. A BIP39 passphrase must pass
  [`PassphraseRules`](mnemonic/src/main/kotlin/io/ownbit/core/model/wallet/PassphraseRules.kt) in both fields.
- **Seed and keys**: seed = BIP39(mnemonic, passphrase) in the bundle;
  [`HdWalletFactory`](mnemonic/src/main/kotlin/io/ownbit/core/wallet/internal/HdWalletFactory.kt) derives the BTC
  44/49/84 (and 86) chain keys, ETH, TRX and SOL, then seals mnemonic and seed;
  [`ChainKeyDerivation`](jsengine/src/main/kotlin/io/ownbit/core/jsengine/chain/ChainKeyDerivation.kt) has every other chain
  (TON and ADA derive from the words, so a passphrase wallet cannot use them).
- The word lists are [`js/bitcoinjs-lib-bridge/mnemonic_words.txt`](../js/bitcoinjs-lib-bridge/mnemonic_words.txt); the
  `mnemonic` build packages that file as the asset `bip39/mnemonic_words.txt` (no second copy is kept here).

## How signing works

Keys are derived and transactions are signed on the device by the JavaScript bundles of [`../js`](../js) — the same
files as iOS (table below) — each running in its own hidden System WebView page
([`WebViewJsEngine`](jsengine/src/main/kotlin/io/ownbit/core/jsengine/internal/WebViewJsEngine.kt)):

- The page is served from the app's assets through `WebViewAssetLoader` (`https://appassets.androidplatform.net/js/<id>/`,
  a local origin intercepted in the app; a missing asset answers 404, never the network). File and content access are
  off, there is no `addJavascriptInterface`; results come back through `WebViewCompat.addWebMessageListener`, accepted only
  from that origin and the main frame.
- **Arguments are data, never code** ([`JsArgs`](jsengine/src/main/kotlin/io/ownbit/core/jsengine/JsArgs.kt),
  [`JsProtocol`](jsengine/src/main/kotlin/io/ownbit/core/jsengine/internal/JsProtocol.kt)): a call is one JSON document
  `{id, fn, args}` embedded as a printable-ASCII JS string literal and `JSON.parse`d by the page's host shim; the function
  path must be dotted identifiers (no `__proto__` / `prototype` / `constructor`); numbers a JS double cannot hold exactly
  are refused (amounts travel as decimal strings). `JsCallSiteGuardTest` scans every source file of this project to keep
  it that way.
- Calls are serialized per bundle; a page whose call timed out, failed or was cancelled is torn down, so a late callback
  can never be credited to the next call. Logs carry function names and timings only.
- Signing needs no network: what a node would provide (nonce, block hash, sequence, UTXOs …) is passed in from Kotlin.
  Several bundles also contain network clients ([`js/README.md`](../js/README.md) lists them); the functions called here
  do not use them, except that the Cardano (AdaLite) bundle asks for the current slot to set the transaction's TTL and
  falls back to a time-based slot offline. The TRON node URL and the Solana RPC URL the bundles' constructors require
  are supplied by the host app — none is in this repository.
- Around the bundles: [`UtxoSignDatas`](signing/src/main/kotlin/io/ownbit/core/chain/utxo/UtxoSignDatas.kt) refuses any
  input or output number JavaScript could read differently from Kotlin; after signing,
  [`UtxoSignedTxVerifier`](signing/src/main/kotlin/io/ownbit/core/chain/utxo/UtxoSignedTxVerifier.kt) decodes the signed
  transaction and checks inputs, amounts, lock time and txid (iOS broadcasts what the bundle returns);
  [`TronTransactionVerifier`](signing/src/main/kotlin/io/ownbit/core/chain/tron/TronTransactionVerifier.kt) checks a
  node-built TRON transaction (recipient, amount, token, owner) before it is signed.
- The cold-wallet public protocol ([`publicsigner`](publicsigner)) reaches its engine (`js/pubsigner-lib-bridge/signer.js`)
  only through [`PublicSignerJsBridge`](jsengine/src/main/kotlin/io/ownbit/core/jsengine/bridge/PublicSignerJsBridge.kt):
  an allowlist of 11 operations, a fresh page for every operation that sees a seed or an untrusted request, discarded
  afterwards. [`PublicSignVerifier`](publicsigner/src/main/kotlin/io/ownbit/core/publicsigner/verify/PublicSignVerifier.kt)
  re-decodes the original QR bytes in Kotlin before signing and the engine's answer after it;
  [`SignedOutpointMemory`](publicsigner/src/main/kotlin/io/ownbit/core/publicsigner/verify/SignedOutpointMemory.kt)
  remembers (hashed) the amount of every Bitcoin input it signed and refuses a later request that claims another amount
  for the same input.

### The bundles in the app's assets

The app ships each bundle as `assets/js/<id>/<file>` (`<id>` = [`JsBundle.id`](jsengine/src/main/kotlin/io/ownbit/core/jsengine/JsBundle.kt)).
"Identical" = the `js/` file is the Android asset byte for byte; "placeholders" = the `js/` file is the Android asset
with the same-length placeholder replacements described in [`js/README.md`](../js/README.md) (build paths, third-party
API keys; the Android SHA-256 is the "app copy" value listed there). `JsBundleFilesTest` checks this table against `js/`.

| `assets/js/` | `js/` | | Android SHA-256 |
|---|---|---|---|
| `btc/bitcoinjs-lib-app.js` | `bitcoinjs-lib-bridge/bitcoinjs-lib-app.js` | identical | `bf27b88640bc4a57cef1c76ef9dbd3d0b3dd35b4b273e1a3948a0a6143da2829` |
| `btctaproot/btctaproot-lib-app.js` | `btctaprootjs-lib-bridge/btctaproot-lib-app.js` | identical | `6621d31db32a180247a3ea4a3e665be8a04933131b9e3721807a060ef447cce7` |
| `bch/bitcoincashjs-lib-app.min.js` | `bitcoincashjs-lib-bridge/bitcoincashjs-lib-app.min.js` | identical | `d6490cedd851235e38d2e0cf958f9ca921a18941e39e4ec0eeaa8fa686d2b56a` |
| `ltc/litecoinjs-lib-app.min.js` | `litecoinjs-lib-bridge/litecoinjs-lib-app.min.js` | placeholders | `8b6a70cb8750c954380ef2e15770cb8168a75c270805570bad1e424e957b4b2c` |
| `doge/dogecoinjs-lib-app.min.js` | `dogecoinjs-lib-bridge/dogecoinjs-lib-app.min.js` | placeholders | `05bac632734b854abf548ced0fb010597e80277eeb7b503798a0a3843c8bb6b5` |
| `dash/dashjs-lib-app.min.js` | `dashjs-lib-bridge/dashjs-lib-app.min.js` | placeholders | `189a1feff5dcb8461fd7c1e51b7e0b84eae2df2b0fe20b794fec9019f2170b06` |
| `dgb/digibytejs-lib-app.min.js` | `digibytejs-lib-bridge/digibytejs-lib-app.min.js` | placeholders | `a8061ff483198e22150470ef615b2d48df289d3189bbd7eb8f84e1dc59682647` |
| `zen/zenjs-lib-app.min.js` | `horizenjs-lib-bridge/zenjs-lib-app.min.js` | placeholders | `d1af677dc715785131f9a524b959aad27a15b2ee7c66647a44568432d47140c7` |
| `zec/zcashjs-lib-app-0251.js` | `zcashjs-lib-bridge/zcashjs-lib-app-0251.js` | placeholders | `cfcb522ec7817399f7b8c36130c8bef44e208269708913f2321bb370c23762c2` |
| `eth/ethereumjs-lib-app.min.js` | `ethereumjs-lib-bridge/ethereumjs-lib-app.min.js` | identical | `cac08c1f18addce23cfeeb43c38622461e5c19e66dc051432583e08b15d2398c` |
| `ethext/ethjs-ext-v2.js` | `ethereumjs-lib-bridge/ethjs-ext-v2.js` | identical | `fed30318b3d3db8bddb7509b872250509cfd378f987fd3323a18b02398b03fe0` |
| `trx/trxjs-lib-app.js` | `tronjs-lib-bridge/trxjs-lib-app.js` | placeholders | `a96d2a29c84a1581ade57c6d9ce7b4dc401f9d9ba1883c4418cb831d7af04d5f` |
| `ton/tonjs-new.js` | `tonjs-lib-bridge/tonjs-new.js` | placeholders | `f20283fde67edf64f211b8634b4aeb6dfc829a47a88254b279cc27360709b7a1` |
| `xrp/ripplejs-lib-app.min.js` | `ripplejs-lib-bridge/ripplejs-lib-app.min.js` | identical | `d63aec38eb87c445d102c660ac16954ccafdd6136244ecc8b5637be87a0b8be1` |
| `xlm/stellarjs-lib-app.min.js` | `stellarjs-lib-bridge/stellarjs-lib-app.min.js` | placeholders | `8c337981ccc221fc9b92fe3bfad0c42ba05ff982b22eff889eb80f17bdd84871` |
| `fil/filjs-lib-app.js` | `filejs-lib-bridge/filjs-lib-app.js` | identical | `6453e06454b002ad4ec0099631aba45f5182e45fe28981d8f9208a58cfb5917f` |
| `pubsigner/signer.js` | `pubsigner-lib-bridge/signer.js` | identical | `d89f76bdeec85d90fd88f07372100e9f4c07ab789530ac2bcffd52be536e7b05` |
| `sol/soljs-lib-app.js` | — (Android ships another build than iOS) | not published | `f865f5154fc8c8502fb99ad81734b4bf3a46e4f3e4e67a0bcb0b1f1bf205ef2d` |
| `stx/stxjs-new.js` | — (Android ships another build than iOS) | not published | `b2b785d426e2b4c8019d94d50d1517d59fd6d859519152ce3eb779074def7391` |
| `ada/shelley.bundle.js` | — (Android ships another build than iOS) | not published | `85beb27eb5373fa1dbc90555933535454a52d0b3c725e025fa1536f4782c5cc4` |
| `btcold/bitcoinjs-lib-app-old.js` | — (legacy BTC `3…` multisig signatures) | not published | `233f031f8a01aa7990d2131b194b2121914f98e951e279af25c42b00ff1f8123` |
| `trxmsg/xemjs-lib-app.js` | — (`tronSignMessage` for WalletConnect) | not published | `4cd41d35d3eaf1d7d6dbe8490ae29afee5c10bf299ffbdb6800efb363db16ff3` |

Besides the bundles, the app's `assets/js/` holds Ownbit's host shim `host/ownbit-host.js` (SHA-256
`935d746ba72aa4169757c6e595132dc394258f5ba4e6a2879342b36a85d82c3d`: the `JSON.parse` / function-path side of the
protocol above, no wallet or crypto logic) and one loader page `<id>/index.html` per directory (the shim, then the bundle,
under a Content-Security-Policy; the public-signer page has `connect-src 'none'`). They are not published here; a host
app using these modules provides them.

## Build and test

```bash
cd android
echo "sdk.dir=$HOME/Library/Android/sdk" > local.properties    # or set ANDROID_HOME
./gradlew build                                               # compile, lint, all JVM unit tests (debug + release)
./gradlew testDebugUnitTest                                   # JVM unit tests only
./gradlew :vault:connectedDebugAndroidTest                    # on a device: libsodium, Keystore device key, biometric keys
```

JDK 17 or later (tested with JDK 21), Android SDK 36. The tests read the bundles' table, the word lists and the
public-protocol golden data from [`../js`](../js) and [`../iOS/Tests/OwnbitCoreTests/PublicProtocol/Fixtures`](../iOS/Tests/OwnbitCoreTests/PublicProtocol/Fixtures)
(the same files iOS uses), and the iOS package's vault known-answer envelopes. Test vectors are public ones only (BIP39
"abandon … about", "legal winner …", "zoo … vote", "TREZOR", RFC 7914, BIP-322, ZIP 244 …). Tests that need the bundles
running in a WebView are part of the app, not of this repository.

## Using the modules

No dependency injection: every class has a plain constructor. A host app provides

- [`WalletSecretStore`](vault/src/main/kotlin/io/ownbit/core/wallet/secret/WalletSecretStore.kt) — where envelopes and
  hashes are kept (the app: Room);
- [`QuickSendEligibility`](vault/src/main/kotlin/io/ownbit/core/wallet/biometric/BiometricSendVault.kt) and
  [`UsdQuotes`](vault/src/main/kotlin/io/ownbit/core/wallet/biometric/WalletAuthorizationPolicy.kt) for biometric quick send;
- [`OutpointStore`](publicsigner/src/main/kotlin/io/ownbit/core/publicsigner/verify/OutpointStore.kt) for the
  signed-outpoint memory (an in-memory implementation is included);
- the TRON node / Solana RPC URLs of `TronJsBridge` / `SolanaTransactionSigner`, and the ZEC consensus-branch override of
  `JsUtxoTxSigner` (network configuration);
- the bundles of [`../js`](../js), the host shim and the loader pages under `assets/js/` as described above.

## Not included

- The user interface (Compose screens, prompts, strings) and the app wiring (Hilt modules, Room database, DataStore).
- Everything that talks to a server or a node: wallet registration, sync, balances, fees, UTXO / nonce fetching,
  broadcasting, prices, membership, push, analytics, WalletConnect. Also the app's TRON calls that ask a node to build a
  transaction (`preSendTx`, `extendTxForWc`) — `TronTransactionVerifier` is what checks such a transaction before signing.
- The app-lock PIN, address-book / contacts, and the parts of the public protocol that need the app's wallet tables
  (public index store, pairing export, scan session UI).
- The engines' instrumented tests (they run the bundles on a device inside the app).

## Licenses

[MIT](../LICENSE). No third-party source is vendored; dependencies come from Maven: Kotlin / kotlinx and AndroidX
(Apache-2.0), Bouncy Castle (`bcprov-jdk18on`, Bouncy Castle Licence, MIT-style), lazysodium-android (MPL-2.0; it
carries libsodium, ISC), JNA (Apache-2.0 / LGPL-2.1); for tests JUnit 4 (EPL-1.0), Robolectric (MIT), MockK
(Apache-2.0). The Gradle wrapper is Apache-2.0. Test data: [`zip_0244.json`](signing/src/test/resources/zcash/zip_0244.json)
is copied from [zcash/zcash-test-vectors](https://github.com/zcash/zcash-test-vectors) (MIT / Apache-2.0).

---

## 中文说明

Ownbit Android 5.x 中接触私钥的部分：**助记词生成与校验、密钥保管、密钥派生和签名**，整理成一个 Gradle 工程里的几个 Kotlin 库模块。代码就是 App
自己的代码，去掉了界面、与服务器通信的代码和 App 装配（依赖注入、数据库、设置存储）；保留的类原来用到这些的地方，改成了一个小接口。

- **模块**：`vault`（OBV2 密文格式、scrypt、Android Keystore 设备密钥、钱包密文的打开/封装/改密码重封装、生物识别快捷转账）、`mnemonic`
  （BIP39 八种词表校验、BIP39 passphrase 规则、导入校验顺序、新建 HD 钱包的密钥部分）、`jsengine`（JS 引擎和各链桥接）、`signing`
  （各链签名及签名前后的本地校验）、`publicsigner`（冷钱包公共协议的模型、签名前后的独立校验、已签输出点记忆、TronLink、签名策略）、`common`（日志）。
- **保管**：与 iOS v2 相同的 `OBV2:` 信封、相同参数（scrypt N=32768/r=8/p=1，AES-256-GCM），AES 密钥同样是 HMAC-SHA256(设备密钥, scrypt 密钥)。
  不同之处：设备密钥是**不可导出的 Android Keystore HMAC 密钥**（有 StrongBox 用 StrongBox，否则 TEE），所以 `dkfp` 指纹改为
  HMAC-SHA256(设备密钥, "fp") 的前 8 字节；每个信封各用一个随机盐（iOS 同一钱包的字段共用一个盐并缓存 60 秒）。测试用 iOS 包里的已知答案信封验证互通。
- **生物识别快捷转账**：每个钱包一把 Class 3、每次使用都要验证的硬件（TEE/StrongBox）AES 密钥，只包裹**钱包密码**（从不包裹助记词或种子）；
  只有 `KeyInfo` 检查和"未验证必须被拒"的反向探测都通过才允许开启；解出的密码一次性使用、60 秒有效、退到后台即清除；大额（默认 ≥1000 美元）、
  价值未知或价格过期时仍要输入密码。
- **助记词**：用 `java.security.SecureRandom` 取 128/256 位熵，由内置 BIP39 代码转成英文助记词并再次校验；导入时先本地词表校验，最后以 JS
  `validateMnemonic` 为准。词表就是 [`js/bitcoinjs-lib-bridge/mnemonic_words.txt`](../js/bitcoinjs-lib-bridge/mnemonic_words.txt)。
- **签名**：在本机由 [`../js`](../js) 里的签名库（与 iOS 相同的文件，对照表见上）在隐藏的 WebView 里派生密钥、签名；Kotlin 传给 JavaScript 的
  一律是 JSON 数据（`JsArgs`），不会拼进 JS 源码。签名函数不需要联网；TRON 节点、Solana RPC 地址由宿主 App 提供，本仓库里没有。
  JS 宿主脚本 `host/ownbit-host.js` 和各目录的加载页 `index.html` 没有放在这里。
- **构建与测试**：`cd android && ./gradlew build`（需要 Android SDK 36、JDK 17+）。测试数据都是公开向量。
- **不包含**：界面、与服务器/节点通信的一切代码（注册、同步、余额、手续费、广播、价格、会员、推送、WalletConnect 等）、App 锁 PIN、App 装配。
- **许可证**：MIT；第三方库通过 Maven 引用，未拷贝源码。
