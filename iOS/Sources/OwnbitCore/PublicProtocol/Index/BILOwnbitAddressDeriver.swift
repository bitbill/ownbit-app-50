//  BILOwnbitAddressDeriver.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Public protocol (cold signer): Ownbit's side of the index cross-check — the existing, independent address bridges over
//  the wallet's stored keys (spec §4.5, R2 §6.1–6.2): BitcoinJSBridge (BIP44 / 49 / 84 `/0/0`), BTCTaprootJSBridge (BIP86
//  `/0/0`), EthereumJSBridge (ETH #n). Several of these bridges never call back on an unexpected result, so every call is
//  wrapped in a resume-once continuation with a 15 s timeout; a timeout or bad answer throws BILOwnbitAddressDeriveError
//  (an engine-class failure for the callers, never a key mismatch). Only Ownbit's own stored keys go in (never engine
//  output); they are interpolated into JavaScript by the existing bridges, so anything but plain alphanumerics is refused
//  first. Main actor: the bridges are called on the main thread and answer there. Nothing is logged.
//

import Foundation

@MainActor public final class BILOwnbitAddressDeriver: BILOwnbitAddressDeriving {

    public static let shared = BILOwnbitAddressDeriver()

    /// Per bridge call (as BILImportWalletController.derivePassphrasePreview).
    public static let timeout: TimeInterval = 15

    public func btcLegacy(xpub: String) async throws -> String {
        try BILOwnbitAddressDeriver.checkKey(xpub)
        return try await BILOwnbitAddressDeriver.call { done in
            BitcoinJSBridge.shared.getAddresses(xpub: xpub, fromIndex: 0, toIndex: 0, success: { done(BILOwnbitAddressDeriver.single($0)) },
                                                failure: { _ in done(.failure(BILOwnbitAddressDeriveError.bridgeFailed)) })
        }
    }

    public func btcNested(xpub: String) async throws -> String {
        try BILOwnbitAddressDeriver.checkKey(xpub)
        return try await BILOwnbitAddressDeriver.call { done in
            BitcoinJSBridge.shared.getAddresses_sw_p(xpub: xpub, fromIndex: 0, toIndex: 0, success: { done(BILOwnbitAddressDeriver.single($0)) },
                                                     failure: { _ in done(.failure(BILOwnbitAddressDeriveError.bridgeFailed)) })
        }
    }

    public func btcNative(xpub: String) async throws -> String {
        try BILOwnbitAddressDeriver.checkKey(xpub)
        return try await BILOwnbitAddressDeriver.call { done in
            BitcoinJSBridge.shared.getAddresses_sw_d(xpub: xpub, fromIndex: 0, toIndex: 0, success: { done(BILOwnbitAddressDeriver.single($0)) },
                                                     failure: { _ in done(.failure(BILOwnbitAddressDeriveError.bridgeFailed)) })
        }
    }

    public func btcTaproot(xpub: String) async throws -> String {
        try BILOwnbitAddressDeriver.checkKey(xpub)
        return try await BILOwnbitAddressDeriver.call { done in
            BTCTaprootJSBridge.shared.getTaprootAddresses(xpub: xpub, from: 0, to: 0, success: { done(BILOwnbitAddressDeriver.single($0)) },
                                                          failure: { _ in done(.failure(BILOwnbitAddressDeriveError.bridgeFailed)) })
        }
    }

    public func ethAddress(xpub: String, index: Int) async throws -> String {
        try BILOwnbitAddressDeriver.checkKey(xpub)
        guard index >= 0 else { throw BILOwnbitAddressDeriveError.badKey }
        return try await BILOwnbitAddressDeriver.call { done in
            EthereumJSBridge.shared.getPublicKeyAndAddress(extPubKey: xpub, indexNo: index, success: { _, address in
                done(address.isEmpty ? .failure(BILOwnbitAddressDeriveError.badResult) : .success(address))
            }, failure: { _ in done(.failure(BILOwnbitAddressDeriveError.bridgeFailed)) })
        }
    }

    // MARK: - Private

    /// Stored extended keys are base58 (BTC) / alphanumeric; anything else (quotes, backslashes, whitespace…) never reaches
    /// a bridge that builds JavaScript source from it.
    private static func checkKey(_ key: String) throws {
        let units = Array(key.utf8)
        guard !units.isEmpty, units.count <= 512, units.allSatisfy({ (0x30...0x39).contains($0) || (0x41...0x5A).contains($0) || (0x61...0x7A).contains($0) }) else {
            throw BILOwnbitAddressDeriveError.badKey
        }
    }

    /// Exactly one address (from 0 to 0 inclusive).
    private static func single(_ object: Any) -> Result<String, Error> {
        guard let list = object as? [String], list.count == 1, let address = list.first, !address.isEmpty else {
            return .failure(BILOwnbitAddressDeriveError.badResult)
        }
        return .success(address)
    }

    /// Starts a bridge call on the main actor and waits for its first answer, or `timeout` (resume-once).
    private static func call(_ start: (@escaping (Result<String, Error>) -> Void) -> Void) async throws -> String {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            let once = BILOwnbitDeriveOnce(continuation)
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + timeout) {
                once.finish(.failure(BILOwnbitAddressDeriveError.timeout))
            }
            start { once.finish($0) }
        }
    }
}

/// Resumes its continuation exactly once (first of: the bridge's answer, the timeout).
private final class BILOwnbitDeriveOnce: @unchecked Sendable {   // every access under `lock`
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String, Error>?

    init(_ continuation: CheckedContinuation<String, Error>) {
        self.continuation = continuation
    }

    func finish(_ result: Result<String, Error>) {
        lock.lock()
        let c = continuation
        continuation = nil
        lock.unlock()
        c?.resume(with: result)
    }
}
