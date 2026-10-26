//  BILPublicIndexSealer.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Public protocol (cold signer): AES-256-GCM sealing of a wallet's public index (C-IDX, spec §4.3; port of Android
//  core/publicsigner index/PublicIndexSealer.kt with CryptoKit) and the Keychain entry envelope around it.
//  The wallet is bound as associated data — `io.ownbit.pubsigner.index.v1|<walletId>|<kind raw>` — so a blob opens only for
//  the wallet id and kind it was made for: copied to another wallet, a changed kind, a flipped bit or a lost key all fail
//  `unseal` (nil), which the repository reports as NeedsRepair (never a silent re-derive). The index holds public keys
//  only but reveals every address of the wallet: never stored in clear, never logged.
//  Pure: Foundation + CryptoKit + the public-protocol strict JSON (macOS harness: tests/index/).
//

import Foundation
import CryptoKit

enum BILPublicIndexSealer {

    /// Version of what is sealed (the engine's index JSON, UTF-8); the envelope's `formatVersion`.
    static let formatVersion = 1, aadPrefix = "io.ownbit.pubsigner.index.v1"

    /// GCM associated data of `walletId`'s blob (Android `aad()` verbatim: `"$AAD_PREFIX|$walletId|${kind.raw}"`).
    static func aad(walletId: String, kind: BILPublicWalletKind) -> Data {
        return Data((aadPrefix + "|" + walletId + "|" + String(kind.rawValue)).utf8)
    }

    /// `AES.GCM.SealedBox.combined` (12-byte random nonce ‖ ciphertext ‖ 16-byte tag) of `plaintext`.
    static func seal(_ plaintext: Data, key: SymmetricKey, walletId: String, kind: BILPublicWalletKind) throws -> Data {
        let box = try AES.GCM.seal(plaintext, using: key, nonce: AES.GCM.Nonce(), authenticating: aad(walletId: walletId, kind: kind))
        guard let combined = box.combined else { throw CryptoKitError.incorrectParameterSize }
        return combined
    }

    /// The plaintext, or nil when the blob does not open for `walletId` / `kind` with `key` (tampered, other wallet / kind,
    /// other key, truncated).
    static func unseal(_ combined: Data, key: SymmetricKey, walletId: String, kind: BILPublicWalletKind) -> Data? {
        guard let box = try? AES.GCM.SealedBox(combined: combined) else { return nil }
        return try? AES.GCM.open(box, using: key, authenticating: aad(walletId: walletId, kind: kind))
    }
}

/// The value of a wallet's Keychain entry: `{"formatVersion":1,"seedHashes":[…],"createdAt":<epoch ms>,"sealed":"<base64>"}`.
/// `seedHashes` = [sha256] of the seed's UTF-8 as this package writes it (the app wrote [sha256, md5] because old wallets'
/// `seedHash` could still be md5; the package has no md5 gate, product decision); a read accepts the wallet's current
/// `seedHash` if it is one of them. Device-local format (no cross-platform byte parity). Decoding is strict: anything off
/// reads as NeedsRepair.
struct BILPublicIndexEnvelope: Equatable {
    let formatVersion: Int
    let seedHashes: [String]
    let createdAtMs: Int64
    /// Standard base64 (with padding) of the sealed box's `combined` bytes.
    let sealed: String

    func encoded() -> Data {
        let object = BILJSONObject([
            ("formatVersion", BILJSONValue.int(formatVersion)),
            ("seedHashes", .array(seedHashes.map { BILJSONValue.string($0) })),
            ("createdAt", BILJSONValue.int(createdAtMs)),
            ("sealed", .string(sealed)),
        ])
        return Data(BILStrictJSON.serialize(object).utf8)
    }

    /// Strict: valid UTF-8, RFC 8259 without duplicate keys (BILStrictJSON), a top-level object whose `formatVersion` and
    /// `createdAt` are integer literals (not `true`, `1.0`, `"1"`), `seedHashes` an array of strings, `sealed` a string.
    /// Unknown keys are ignored (the format version decides compatibility).
    static func decode(_ data: Data) -> BILPublicIndexEnvelope? {
        guard let object = BILStrictJSON.parse(utf8: [UInt8](data))?.objectValue,
              let version = object.long("formatVersion"), let created = object.long("createdAt"),
              let hashes = object.strings("seedHashes"), let sealed = object.str("sealed"),
              version >= Int64(Int.min), version <= Int64(Int.max) else {
            return nil
        }
        return BILPublicIndexEnvelope(formatVersion: Int(version), seedHashes: hashes, createdAtMs: created, sealed: sealed)
    }
}

/// Descriptions never show the seed hashes or the sealed bytes (C-KEY-5).
extension BILPublicIndexEnvelope: CustomStringConvertible, CustomDebugStringConvertible {
    var description: String {
        return "BILPublicIndexEnvelope(formatVersion: \(formatVersion))"
    }

    var debugDescription: String {
        return description
    }
}
