//  BILSCText.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Security Center: a reference to a localizable text (key + arguments). The model layer only produces it; the host
//  resolves it in the current language when it shows it. Pure Foundation.
//

import Foundation

/// `key` is the full Security Center key ("SecurityCenter.xxx"); `args` fill the `%@` / `%1$@` placeholders in order.
public struct BILSCText: Codable, Hashable {
    public let key: String
    public let args: [String]

    public init(_ key: String, _ args: [String] = []) {
        self.key = key
        self.args = args
    }
}
