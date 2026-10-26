//  BILRecentRequestHashes.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Public protocol (cold signer) — C-RESP-4: the request hashes this process answered, newest last, at most `capacity`
//  (the least recently answered is dropped). The review page shows "You already signed this exact request (HH:mm)" for a
//  hash in here; signing again still needs a new scan and a new password. Memory only — never stored, gone with the
//  process. Port of Android core/publicsigner/.../sign/RecentRequestHashes.kt (design §2.1 WP19, R5 §1.2). Keys are the
//  lower-cased hashes, compared exactly (code units). Pure Foundation; thread-safe.
//

import Foundation

final class BILRecentRequestHashes {

    static let capacity = 16

    private let lock = NSLock()
    /// Oldest first.
    private var signed: [(hash: String, at: Date)] = []

    init() {}

    /// Records that the request `requestHash` was answered at `at` (an answered hash moves to the newest place).
    func record(_ requestHash: String, at: Date) {
        let key = requestHash.lowercased()
        lock.lock()
        defer { lock.unlock() }
        signed.removeAll { BILJSONExact.equal($0.hash, key) }
        signed.append((key, at))
        while signed.count > BILRecentRequestHashes.capacity {
            signed.removeFirst()
        }
    }

    /// When `requestHash` was last answered, or nil.
    func signedAt(_ requestHash: String) -> Date? {
        let key = requestHash.lowercased()
        lock.lock()
        defer { lock.unlock() }
        return signed.last { BILJSONExact.equal($0.hash, key) }?.at
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return signed.count
    }
}
