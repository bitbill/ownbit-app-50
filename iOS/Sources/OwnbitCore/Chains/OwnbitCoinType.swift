//  OwnbitCoinType.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  The coin types of the chains this package supports: the subset of the app's `CoinType` that Ownbit 5.0 shows by
//  default. Raw values are the app's (they are part of the offline-signing format shared with Android; never renumber).

import Foundation

public enum OwnbitCoinType: Int64, CaseIterable {
    case btc = 0
    case ethereum = 1
    case erc20Token = 2
    case bch = 3
    case ltc = 4
    case etc = 5
    case dash = 8
    case doge = 9
    case dgb = 10
    case zen = 11
    case xrp = 16
    case xlm = 17
    case zec = 19
    case trx = 25
    case trc20Token = 26
    case ada = 36
    case bsc = 40
    case bsc20Token = 41
    case fil = 46
    case sol = 47
    case spl20Token = 48
    case avax = 51
    case avax20Token = 52
    case arb = 53
    case arb20Token = 54
    case op = 55
    case op20Token = 56
    case stx = 57
    case ton = 58
    case base = 59
    case base20Token = 60
    case ton20Token = 61
    case hype = 62
    case hype20Token = 63
    case xrp20Token = 64
    case xlm20Token = 65
}
