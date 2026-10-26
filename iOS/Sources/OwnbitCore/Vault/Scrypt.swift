//  Scrypt.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  scrypt (RFC 7914) through the bundled libscrypt C code (target CLibscrypt).
//  Port of the app's `BILKeyStoreManager.calculate(pwd:salt:dklen:N:R:P:)`: the password is fed in as its
//  UTF-8 bytes, the salt as raw bytes.

import Foundation
import CLibscrypt

public enum Scrypt {

    /// scrypt(password, salt, N, r, p, dkLen).
    ///
    /// Returns nil when an argument is out of range (empty `dkLen`, non-positive N / r / p) — like the app — and
    /// also when libscrypt itself rejects the parameters (N not a power of two greater than 1, r·p ≥ 2^30, out of
    /// memory). For the parameters Ownbit writes (N = 32768, r = 8, p = 1, dkLen = 32) libscrypt never rejects them.
    public static func derive(password: String, salt: Data, dkLen: Int, n: Int, r: Int, p: Int) -> Data? {
        guard dkLen > 0, n > 0, r > 0, p > 0,
              r <= Int(UInt32.max), p <= Int(UInt32.max) else { return nil }
        let pwdBytes = Array(password.utf8)
        let saltBytes = Array(salt)
        var out = Data(count: dkLen)
        let rc: Int32 = out.withUnsafeMutableBytes { buffer -> Int32 in
            guard let base = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return -1 }
            return libscrypt_scrypt(pwdBytes, pwdBytes.count,
                                    saltBytes, saltBytes.count,
                                    UInt64(n), UInt32(r), UInt32(p),
                                    base, dkLen)
        }
        guard rc == 0 else { return nil }
        return out
    }
}
