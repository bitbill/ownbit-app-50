//  BILPublicSignerAvailability.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Public protocol (cold signer) — the engine identity rule of the first-use probe (design §3.4, D-05, R1 §2.4). Exact
//  port of Android `core/jsengine/.../PublicSignerAvailability.isExpectedEngine`: the shipped engine reports
//  `version == "1.0.0"` (JSON string), `offline == true` (JSON bool), the Ownbit edition's `deviceName` pairing option,
//  its round-2 `tronScheme` index option and the TronLink ownership check. Lists are read like Android's `strings()`:
//  the string elements of a JSON array (other elements ignored; a missing / non-array value = empty).
//
//  iOS has no WebView version gate (D-06): any probe failure means `PublicProtocol.err.engineUnavailable`. The probe
//  itself is `BILPublicSignerEngine.isAvailable()` (success cached, failure not). (The app's DEBUG-only forced probe
//  failures, launch argument `-bil_debug_pub_engine_fail`, are not part of this package.)
//  Pure Foundation.
//

import Foundation

enum BILPublicSignerAvailability {

    /// `capabilities.version` of the bundled engine.
    static let engineVersion = "1.0.0", tronSchemeOption = "tronScheme"

    /// The Ownbit edition's TronLink ownership check (`capabilities.tron.supported`).
    static let tronLinkOwnershipCheck = "TronLink ownership check (exact fixed placeholder)"

    /// The Ownbit edition's pairing option (`capabilities.pairingOptions`).
    private static let deviceNameOption = "deviceName"

    /// R1 §2.4: an older or foreign engine is never paired with this host code.
    static func isExpectedEngine(_ capabilities: BILJSONObject) -> Bool {
        guard let version = capabilities.str("version"), BILJSONExact.equal(version, engineVersion) else { return false }
        guard capabilities["offline"] == .bool(true) else { return false }
        let options = strings(capabilities["pairingOptions"])
        let indexOptions = strings(capabilities["publicIndexOptions"])
        let tron = strings(capabilities.obj("tron")?["supported"])
        return contains(options, deviceNameOption) && contains(indexOptions, tronSchemeOption)
            && contains(tron, tronLinkOwnershipCheck)
    }

    /// Android `strings(element)`: the JSON-string elements of an array; anything else → [].
    private static func strings(_ value: BILJSONValue?) -> [String] {
        guard let array = value?.arrayValue else { return [] }
        return array.compactMap { $0.stringValue }
    }

    /// Exact (code-unit) membership, like Kotlin `in`.
    private static func contains(_ list: [String], _ item: String) -> Bool {
        return list.contains { BILJSONExact.equal($0, item) }
    }
}
