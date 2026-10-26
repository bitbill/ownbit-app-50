//  BILPsbtMaps+Claims.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Public protocol (cold signer) — the signed-outpoint memory's claims of a PSBT (spec S§8.3a, C-OVC; design §3.10, D-30;
//  R5 §4.2; Android `PS:verify/SignedOutpointMemory.kt` `claim(maps, index)` / `conflicts(maps)` / `record(maps, inputs)`):
//  one claim per input = the outpoint (txid **as stored** in the transaction, vout) and the amount the PSBT claims for it.
//  Pure Foundation (macOS harness: tests/verifier/). Never logs; a claim prints nothing of its content.
//

import Foundation

extension BILPsbtMaps {

    /// One claim per input, in input order (`BILSignedOutpointMemory.conflicts`): nil when the input's outpoint or amount
    /// cannot be read (the memory counts that as a conflict — fail closed; the pre-check refuses such a PSBT anyway).
    public func outpointClaims() -> [BILSignedOutpointMemory.Claim?] {
        return (0..<inputs.count).map { claim(ofInput: $0) }
    }

    /// The claims to record after signing: every signed input (`inputs`, distinct, ascending — Android
    /// `inputs.distinct().sorted()`). nil when any of them is unreadable or out of range — the caller treats it as a
    /// record failure, never as "skip that input" (design §3.10; cannot happen after the pre-check, which refuses a PSBT
    /// with an unreadable input). An empty `inputs` gives `[]` (nothing to record).
    public func claims(forInputs inputs: [Int]) -> [BILSignedOutpointMemory.Claim]? {
        var out = [BILSignedOutpointMemory.Claim]()
        for index in Array(Set(inputs)).sorted() {
            guard let c = claim(ofInput: index) else { return nil }
            out.append(c)
        }
        return out
    }

    /// Android `SignedOutpointMemory.claim(maps, index)`: the outpoint and the claimed amount of input `index`, nil when
    /// either cannot be read or the txid is not 32 bytes (Android's `Claim` precondition).
    private func claim(ofInput index: Int) -> BILSignedOutpointMemory.Claim? {
        guard index >= 0, index < self.inputs.count, let outpoint = outpoint(index), outpoint.txid.count == 32,
              let amount = claimedAmount(index) else { return nil }
        return BILSignedOutpointMemory.Claim(txid: outpoint.txid, vout: outpoint.vout, sats: amount)
    }
}
