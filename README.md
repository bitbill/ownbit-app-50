# Ownbit core

From version 5.0, the part of Ownbit that touches private keys is open source: **mnemonic generation, key storage,
key derivation and signing**. This repository contains that code, as it is used by the Ownbit iOS app, plus the
JavaScript signing bundles both apps load. The user interface and the code that talks to Ownbit's servers are not part
of it.

[中文说明](#中文说明)

| Directory | What |
|---|---|
| [`iOS/`](iOS) | Swift package `OwnbitCore` (iOS 15+): the encrypted key vault, mnemonic generation and validation, the JavaScript engine and chain bridges, and the cold-wallet public-protocol signer |
| [`js/`](js) | The JavaScript bundles that derive keys and sign transactions, with their SHA-256 and the libraries inside each one ([`js/README.md`](js/README.md)) |
| [`android/`](android) | Reserved for the Android 5.0 core |

## How Ownbit protects your keys

**Mnemonic generation.** A new mnemonic (12 or 24 words, BIP39) is generated inside the bundled BIP39 code from the
operating system's secure random generator (`crypto.getRandomValues`). The seed is BIP39(mnemonic, passphrase), with an
optional BIP39 passphrase for imported wallets.

**Storage (Ownbit Vault v2).** The mnemonic, the seed and the passphrase (or a private key and its WIF) are stored only
encrypted, never in plain text, and never leave the device except inside a backup the user creates:

| | |
|---|---|
| Key derivation | scrypt, N = 32768, r = 8, p = 1, 32-byte key, random 16-byte salt per wallet |
| Encryption | AES-256-GCM, random 12-byte nonce for every field, authenticated (a wrong password or a modified record is rejected) |
| Device binding | on the phone, the AES key is HMAC-SHA256(device key, scrypt key). The device key is 32 random bytes in a keychain item that never syncs and is never included in device backups, so a copied wallet database cannot be brute-forced elsewhere, however weak the password |
| Cloud backup | the optional iCloud mnemonic backup uses the same format without the device key ("portable"), so it can be restored on a new phone with the password |
| Format | self-describing envelope `OBV2:` + base64(JSON) with all parameters, so they can be raised later without breaking existing data |

Mnemonic wallets created before 5.1 are upgraded to this format the first time their password is entered; a cloud
backup is written in this format the next time it is backed up.
The full specification is at the top of [`WalletSecretCipher.swift`](iOS/Sources/OwnbitCore/Vault/WalletSecretCipher.swift).

**Signing.** Keys are derived from the seed and transactions are signed on the device, by the bundles in [`js/`](js)
running in the app's JavaScript engine (JavaScriptCore / WKWebView). Every value Swift passes into JavaScript is escaped
([`jsEscaped`](iOS/Sources/OwnbitCore/JSEngine)). The cold-wallet public protocol
([`PublicProtocol/`](iOS/Sources/OwnbitCore/PublicProtocol)) parses and verifies signing requests from other wallets
before anything is signed, and remembers the amount of every Bitcoin input it has signed, refusing a later request
that claims a different amount for the same input.

## Supported chains

BTC (legacy, P2SH-SegWit, native SegWit, Taproot, multisig) · ETH and the EVM chains BSC, Arbitrum, Optimism, Base,
Avalanche, HyperEVM (tokens, multisig) · ETC · TRON (TRC-20, multisig) · Solana (SPL) · BCH · LTC · DOGE · DASH · DGB ·
ZEN · ZEC · XRP (tokens) · XLM (tokens) · TON (jettons) · ADA · FIL · STX · the cold-wallet public protocol.

## Build and test

```bash
cd iOS
xcodebuild build -scheme OwnbitCore -destination 'generic/platform=iOS Simulator'
xcodebuild test  -scheme OwnbitCore -destination 'platform=iOS Simulator,name=iPhone 16'
```

The tests read the JavaScript bundles from [`js/`](js) and the public-protocol golden data from
`iOS/Tests/OwnbitCoreTests/PublicProtocol/Fixtures`. Test vectors are public ones only (BIP39 "abandon … about",
"TREZOR", RFC 7914 …).

To use the package in an app, bundle the files of [`js/`](js) and set `JSBridge.resourceBundle` to the bundle that holds
them.

## Checking the bundles against the app

[`js/README.md`](js/README.md) lists the SHA-256 of every JavaScript file. They are the same files as in the Ownbit app,
except where a third-party provider API key or a local build path was replaced with a placeholder of the same length
(listed there; [`js/tools/verify.py`](js/tools) checks it).

## Security

Please report vulnerabilities privately — see [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE). Third-party code keeps its own license: libscrypt ([`iOS/Sources/CLibscrypt/LICENSE`](iOS/Sources/CLibscrypt/LICENSE))
and the libraries bundled in [`js/`](js) (listed in [`js/README.md`](js/README.md)).

---

## 中文说明

从 5.0 版本起，Ownbit 接触私钥的核心代码开源：**助记词生成、密钥保管、密钥派生和签名**。本仓库就是 Ownbit iOS App 使用的这部分代码，
以及两个 App 共用的 JavaScript 签名库。界面代码和与 Ownbit 服务器通信的代码不在其中。

- **助记词**：在内置的 BIP39 代码里用系统安全随机数（`crypto.getRandomValues`）生成 12 / 24 个词；种子 = BIP39(助记词, passphrase)。
- **保管（Ownbit Vault v2）**：助记词、种子、passphrase（私钥钱包是私钥和 WIF）只以密文保存：scrypt（N=32768、r=8、p=1，每个钱包随机 16 字节盐）
  + AES-256-GCM（每段随机 nonce，带完整性校验）。手机上再混入一把只存本机、不同步、不进整机备份的设备密钥，
  所以钱包数据库被拷走也无法在别处暴力破解；iCloud 助记词备份用同样的格式但不绑设备，换手机可以凭密码恢复。5.1 之前创建的助记词钱包在第一次输入密码时自动升级，
  iCloud 备份在下次重新备份时换成新格式。
- **签名**：在本机由 [`js/`](js) 里的签名库派生密钥、签名；Swift 传给 JavaScript 的值一律转义。冷钱包公共协议在签名前解析、校验其他钱包发来的请求。
- **币种**：见上方 Supported chains。
- **许可证**：MIT。漏洞请按 [SECURITY.md](SECURITY.md) 私下报告。
