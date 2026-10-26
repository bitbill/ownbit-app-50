//  PPPairingStubs.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Port of the app harness suite `scripts/public-protocol/tests/pairing` (Stubs.swift) to XCTest.
//
//  Stubs.swift — suite "pairing" (WP14): the Security Center hooks the live BILPublicPairingLog forwards to (the real
//  file needs the whole Security Center store graph). Signatures verbatim; the bodies record the calls so the suite can
//  check what the live log passes on. Test code only.
//

import Foundation
import XCTest
@testable import OwnbitCore

extension PPPairingSuite {

    /// One forwarded hook call ("xpub" / "watchqr", wallet id, coin, page identity).
    struct HookCall: Equatable {
        let kind: String
        let walletId: String?
        let coin: String?
        let page: ObjectIdentifier?
    }

    enum HookRecorder {
        private static let lock = NSLock()
        private static var storage: [HookCall] = []
        static var calls: [HookCall] {
            lock.lock(); defer { lock.unlock() }
            return storage
        }
        static func reset() {
            lock.lock(); storage.removeAll(); lock.unlock()
        }
        static func append(_ c: HookCall) {
            lock.lock(); storage.append(c); lock.unlock()
        }
    }

    // from Modules/SecurityCenter/Core/BILSecurityCenterHooks.swift:27
    enum BILSecurityCenterHooks {
        // from :73
        static func xpubExported(walletId: String?, coin: String?, page: AnyObject? = nil) {
            HookRecorder.append(HookCall(kind: "xpub", walletId: walletId, coin: coin, page: page.map { ObjectIdentifier($0) }))
        }

        // from :79
        static func watchQRShown(walletId: String?, page: AnyObject? = nil) {
            HookRecorder.append(HookCall(kind: "watchqr", walletId: walletId, coin: nil, page: page.map { ObjectIdentifier($0) }))
        }
    }
}
