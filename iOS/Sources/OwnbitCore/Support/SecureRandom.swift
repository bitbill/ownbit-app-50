//  SecureRandom.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT

import Foundation
import CryptoKit
import Security

/// Cryptographically secure random bytes from the system generator.
public enum SecureRandom {

    /// `n` random bytes. Uses `SecRandomCopyBytes`; if that ever reports an error, falls back to a
    /// CryptoKit random `SymmetricKey` of the same size (also the system CSPRNG), exactly like the app.
    public static func bytes(_ n: Int) -> Data {
        guard n > 0 else { return Data() }
        var data = Data(count: n)
        let status = data.withUnsafeMutableBytes { buffer -> OSStatus in
            guard let base = buffer.baseAddress else { return errSecAllocate }
            return SecRandomCopyBytes(kSecRandomDefault, n, base)
        }
        if status != errSecSuccess {
            data = SymmetricKey(size: SymmetricKeySize(bitCount: n * 8)).withUnsafeBytes { Data($0) }
        }
        return data
    }
}
