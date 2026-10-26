//  String+SHA256.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  The hash used by every "hash gate" in the vault (mnemonicHash, seedHash, privateKeyHash, wifHash).
//  Same output as CryptoSwift's `String.sha256()` that the app uses: lowercase hex of SHA-256 over the
//  UTF-8 bytes of the string.

import Foundation
import CryptoKit

extension String {

    /// Lowercase hex of SHA-256 over the UTF-8 bytes of the string (64 characters).
    /// `package`, not `public`: a host app that also imports CryptoSwift would otherwise get "ambiguous use of sha256()".
    package func sha256() -> String {
        return Data(SHA256.hash(data: Data(self.utf8))).hexString
    }
}
