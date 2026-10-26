//  PPVerifierPolicyTests.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Port of the app harness suite `scripts/public-protocol/tests/verifier` (PolicyTests.swift) to XCTest.
//
//  PolicyTests.swift — BILPublicSignPolicy on the golden vectors (ports of Android
//  PST:sign/{PublicSignPolicyTest,PublicSignPolicyRound2Test}.kt, R5 §2), plus the proven-path / bound / label edge cases.
//

import Foundation
import XCTest
@testable import OwnbitCore

extension PPVerifierSuite {

    private typealias P = BILPublicSignPolicy

    private static func evaluate(_ id: String, insight: BILSignatureRisk? = nil) -> BILPublicPolicyResult {
        let plan = SigningVectors.plan(id)
        guard let review = plan.review else { print("FAIL no review in \(id)"); exit(2) }
        return P.evaluate(review: review, plan: plan, verified: SigningVectors.verified(id), insightRisk: insight)
    }

    private static func path(_ purpose: UInt32, _ coin: UInt32, _ account: UInt32, _ branch: UInt32, _ index: UInt32) -> [UInt32] {
        let h = BILPsbtMaps.hardened
        return [purpose | h, coin | h, account | h, branch, index]
    }

    private static func review(_ id: String) -> BILPublicReview {
        guard let r = SigningVectors.plan(id).review else { print("FAIL no review in \(id)"); exit(2) }
        return r
    }

    static func policyTests() {
        section("policy: a plain transfer needs no acknowledgement")
        do {
            let r = evaluate("T8-flow-evm-eip1559")
            t(r.canSign, "can sign")
            t(!r.requiresAcknowledgement, "no checkbox")
            eq(r.pageRisk, .low, "page risk low")
            t(r.warnings.isEmpty, "no Ownbit warning")
        }

        section("policy: risk merge — the highest of engine, D43 card and Ownbit warnings")
        do {
            let r = evaluate("T8-flow-evm-eip1559")
            eq(r.withInsight(.medium).pageRisk, .medium, "medium card")
            t(!r.withInsight(.medium).requiresAcknowledgement, "a medium card needs no consent")
            eq(r.withInsight(.critical).pageRisk, .critical, "critical card")
            eq(r.withInsight(.high).ackReasons, [.highRisk], "a high D43 reading needs consent")
            eq(P.engineRisk(.normal), .low, "normal → low")
            eq(P.engineRisk(.warning), .medium, "warning → medium")
            eq(P.engineRisk(.high), .high, "high → high")
            let approve = evaluate("T8-flow-evm-erc20-unlimited-approve", insight: .low)
            eq(approve.pageRisk, .high, "engine high wins over a low card")
            eq(Set(approve.ackReasons), [.highRisk], "unlimited approval needs consent")
        }

        section("policy: opaque and partially decoded requests need consent with their own reason")
        do {
            let opaque = evaluate("O-EVM-4-personal-hash")
            eq(review("O-EVM-4-personal-hash").decodeStatus, .opaque, "O-EVM-4 is opaque")
            eq(Set(opaque.ackReasons), [.opaque, .highRisk], "opaque + high risk")
            t(opaque.requiresAcknowledgement, "opaque needs consent")
            t(evaluate("T8-flow-evm-unknown-contract-call").ackReasons.contains(.opaque), "unknown contract call is opaque")
            let id = "T8-flow-evm-eip1559"
            let partial = P.evaluate(review: reviewCopy(review(id), decodeStatus: .partiallyDecoded), plan: SigningVectors.plan(id),
                                     verified: SigningVectors.verified(id))
            eq(Set(partial.ackReasons), [.partiallyDecoded], "partially decoded")
        }

        section("policy: BTC HIGH FEE (engine rule, C-BTC-4 host part) → engine risk high → consent")
        for id in SigningVectors.answeredFlows where id.hasPrefix("O-BTC-2-") {
            let rv = review(id)
            let highFee = rv.warnings.contains { BILPublicEngineVocabulary.severity($0) == .danger && $0.hasPrefix("HIGH FEE") }
            let r = evaluate(id)
            eq(r.ackReasons.contains(.highRisk), highFee, "\(id): HIGH_RISK consent iff the engine says HIGH FEE")
            eq(r.engineRisk, highFee ? .high : .medium, "\(id): engine risk")
            t(r.canSign, "\(id): a consent question, not a refusal")
            if id.hasSuffix("-above") { t(highFee, "\(id): above the threshold is HIGH FEE") }
            if id.hasSuffix("-at") { t(!highFee, "\(id): at the threshold is not HIGH FEE") }
        }

        section("policy: a Solana durable nonce — consent, and the warning once (the engine's, localized)")
        do {
            let id = "O-SOL-1-durable-nonce"
            let r = evaluate(id)
            eq(Set(r.ackReasons), [.durableNonce], "durable nonce reason")
            t(r.requiresAcknowledgement, "durable nonce needs consent")
            let engine = review(id).warnings.compactMap { BILPublicEngineVocabulary.warning($0) }
                .filter { BILJSONExact.equal($0.id, BILPublicEngineVocabulary.durableNonceId) }
            eq(engine.count, 1, "the engine says it")
            eq(engine.first?.key ?? "", "PublicProtocol.warn.durableNonce", "shown with warn.durableNonce")
            t(!r.warnings.contains { $0.kind == .durableNonce }, "no duplicate of the engine warning")
            eq(r.pageRisk, .medium, "the engine's Solana review is a warning anyway")
            let bare = P.evaluate(review: reviewCopy(review(id), warnings: []), plan: SigningVectors.plan(id), verified: SigningVectors.verified(id))
            eq(bare.warnings.count, 1, "Ownbit says it itself without the engine text")
            eq(bare.warnings.first?.kind ?? .tokenDecimals, .durableNonce, "kind durableNonce")
            eq(bare.warnings.first?.key ?? "", "PublicProtocol.warn.durableNonce", "key warn.durableNonce")
            eq(bare.warnings.first?.risk ?? .low, .medium, "risk medium")
            eq(Set(bare.ackReasons), [.durableNonce], "consent stays")
            t(!evaluate("T8-flow-solana-transfer").ackReasons.contains(.durableNonce), "an ordinary transfer has no durable nonce")
        }

        section("policy: change at index 1000 is a normal output with a warning, 999 is change (C-BTC-7)")
        do {
            let beyond = evaluate("O-BTC-3-change-1000")
            t(beyond.ackReasons.contains(.changeBeyondBound), "beyond bound: \(beyond.ackReasons)")
            eq(beyond.warnings.count, 1, "one warning")
            eq(beyond.warnings.first?.key ?? "", "PublicProtocol.warn.changeIndex", "warn.changeIndex")
            eq(beyond.warnings.first?.args ?? [], [.int(2), .text("1000")], "output 2, address index 1000")
            eq(beyond.warnings.first?.kind ?? .tokenDecimals, .changeIndex, "kind changeIndex")
            eq(beyond.pageRisk, .high, "page risk high")
            t(review("O-BTC-3-change-1000").fields.contains { BILJSONExact.equal($0.label, "Output 2 ownership") }, "engine proved output 2")
            let within = evaluate("O-BTC-3-change-999")
            t(!within.ackReasons.contains(.changeBeyondBound), "999 is change")
            t(within.warnings.isEmpty, "999: no warning")
            t(evaluate("O-BTC-3-change-bip48").warnings.isEmpty, "BIP48: never change")
            t(P.beyondBound(path(84, 0, 0, 1, 1000)), "84'/0'/0'/1/1000 beyond")
            t(!P.beyondBound(path(84, 0, 0, 1, 999)), "…/999 within")
            t(!P.beyondBound(path(84, 0, 1, 1, 5000)), "another account is not Ownbit's")
            t(!P.beyondBound([48 | BILPsbtMaps.hardened, BILPsbtMaps.hardened, BILPsbtMaps.hardened, 2 | BILPsbtMaps.hardened, 0, 1000]), "BIP48 6 levels")
            t(P.beyondBound(path(44, 0, 0, 0, 1000)) && P.beyondBound(path(49, 0, 0, 0, 1000)) && P.beyondBound(path(86, 0, 0, 1, 1000)),
              "44' / 49' / 86' purposes")
            t(!P.beyondBound(path(45, 0, 0, 0, 1000)), "purpose 45' is not single-sig")
            t(!P.beyondBound(path(84, 1, 0, 0, 1000)), "testnet coin")
            t(!P.beyondBound(path(84, 0, 0, 2, 1000)), "branch 2")
            t(!P.beyondBound([84 | BILPsbtMaps.hardened, BILPsbtMaps.hardened, BILPsbtMaps.hardened, 1 | BILPsbtMaps.hardened, 1000]), "hardened branch")
            t(!P.beyondBound(path(84, 0, 0, 1, 0x8000_0005)), "hardened index")
            t(P.beyondBound(path(84, 0, 0, 1, 0x7FFF_FFFF)), "index 2³¹ − 1")
            eq(P.maxChangeIndex, UInt32(999), "MAX_CHANGE_INDEX")
        }

        section("policy: beyond the bound the engine risk is the shown request-only review's")
        do {
            let id = "O-BTC-3-change-1000"
            let plan = SigningVectors.plan(id)
            let planReview = review(id)
            let highFee = "HIGH FEE: Fee exceeds 0.01 BTC, or exceeds half of the amount sent (and 0.0001 BTC). Verify it carefully."
            let proven = reviewCopy(planReview, warnings: planReview.warnings + [highFee], riskLevel: .high)
            let requestOnly = reviewCopy(planReview, fields: planReview.fields.filter { !$0.label.hasSuffix(" ownership") }, riskLevel: .warning)
            let r = P.evaluate(review: proven, plan: plan, verified: SigningVectors.verified(id), requestOnlyReview: requestOnly)
            eq(Set(r.ackReasons), [.changeBeyondBound], "no HIGH_RISK for a banner the page does not show")
            eq(r.engineRisk, .medium, "engine risk from the request-only review")
            eq(r.pageRisk, .high, "the change-index warning keeps the page high")
            eq(r.warnings.first?.args ?? [], [.int(2), .text("1000")], "the bound is still read from the plan's proof")
            let shownHigh = P.evaluate(review: planReview, plan: plan, verified: SigningVectors.verified(id),
                                       requestOnlyReview: reviewCopy(requestOnly, warnings: requestOnly.warnings + [highFee], riskLevel: .high))
            eq(Set(shownHigh.ackReasons), [.changeBeyondBound, .highRisk], "shown review with HIGH FEE")
            eq(shownHigh.engineRisk, .high, "engine risk high")
            let w = "O-BTC-3-change-999"
            let within = P.evaluate(review: reviewCopy(review(w), riskLevel: .high), plan: SigningVectors.plan(w), verified: SigningVectors.verified(w),
                                    requestOnlyReview: reviewCopy(review(w), riskLevel: .warning))
            eq(within.engineRisk, .high, "within the bound the request-only review is ignored")
            eq(Set(within.ackReasons), [.highRisk], "within: HIGH_RISK")
        }

        section("policy: change listed only as a Taproot derivation with 101 leaf hashes is still bound")
        for (id, index) in [("O-BTC-3-change-taphashes", "2147483647"), ("O-BTC-3-change-taproot-taphashes", "5000")] {
            let rv = review(id)
            t(rv.fields.contains { BILJSONExact.equal($0.label, "Output 2 ownership") }, "\(id): output 2 proven")
            eq(rv.display?.note ?? "", "Change returns to your wallet", "\(id): summary note")
            let r = evaluate(id)
            t(r.ackReasons.contains(.changeBeyondBound), "\(id): beyond bound")
            eq(r.warnings.first?.args ?? [], [.int(2), .text(index)], "\(id): args")
            eq(r.warnings.count, 1, "\(id): one warning")
            eq(r.pageRisk, .high, "\(id): page risk")
            t(r.canSign && r.requiresAcknowledgement, "\(id): signable with consent")
        }

        section("policy: the engine's own proof enforces the bound, whatever the PSBT says")
        do {
            let id = "O-BTC-3-change-1000"
            let plan = SigningVectors.plan(id)
            let rv = review(id)
            guard case .bitcoinPsbt(_, let bare, _) = SigningVectors.verified("T8-flow-bitcoin-crypto-psbt") else { t(false, "bare maps"); return }
            t((try? bare.outputDerivations())?.isEmpty ?? false, "the other vector's PSBT has no output derivation")
            eq(P.changeBeyondBound(review: rv, plan: plan, maps: bare)?.first?.args ?? [], [.int(2), .text("1000")], "proven path counts")
            let w = "O-BTC-3-change-999"
            eq(P.changeBeyondBound(review: review(w), plan: SigningVectors.plan(w), maps: bare)?.count ?? -1, 0, "999: none")
            let provenValue = rv.fields.first { BILJSONExact.equal($0.label, "Output 2 ownership") }?.value ?? ""
            eq(P.provenPath(provenValue) ?? [], path(84, 0, 0, 1, 1000), "proven path m/84'/0'/0'/1/1000")
            t(P.provenPath("Returns to the signing wallet") == nil, "no path")
            t(P.provenPath("Returns to the signing wallet (verified from its public key, m/84'/0'/0'/1/2147483648)") == nil, "index ≥ 2³¹")
            let garbled = reviewCopy(rv, fields: rv.fields.map { f in
                BILJSONExact.equal(f.label, "Output 2 ownership") ? BILReviewField(index: f.index, label: f.label, value: "Returns to the signing wallet") : f
            })
            eq(P.evaluate(review: garbled, plan: plan, verified: SigningVectors.verified(id)).warnings.first?.args ?? [], [.int(2), .text("1000")],
               "an unreadable proof: the PSBT derivation decides")
            let refused = P.evaluate(review: garbled, plan: plan, verified: SigningVectors.verified("T8-flow-bitcoin-crypto-psbt"))
            eq(refused.refusal?.key ?? "", "PublicProtocol.err.integrity", "no path anywhere → err.integrity")
            eq(refused.refusal?.code ?? "", "CHANGE_PATH", "code CHANGE_PATH")
            t(!refused.canSign && !refused.requiresAcknowledgement, "a hard refusal, not a consent question")
        }

        section("policy: output derivations that cannot be read → CHANGE_PATH, or the conflict first (deviation 2)")
        do {
            // A Taproot output derivation (0x07) whose leaf-hash count is the non-canonical compact `fd 05 00`: the PSBT
            // parses, `outputDerivations()` throws, `changeBeyondBound` is nil (Android lets the exception escape; both refuse).
            let id = "O-BTC-3-change-1000"
            let plan = SigningVectors.plan(id)
            guard case .bitcoinPsbt(_, let maps, let witnessOnly) = SigningVectors.verified(id) else { t(false, "O-BTC-3 maps"); return }
            let key: [UInt8] = [0x07] + [UInt8](repeating: 0x33, count: 32)
            let value: [UInt8] = [0xFD, 0x05, 0x00] + [0x73, 0xC5, 0xDA, 0x0A] + [0x56, 0x00, 0x00, 0x80, 0x00, 0x00, 0x00, 0x80]
            let bytes = psbtBytes(maps, output: 0, [(key: key, value: value)])
            guard let tampered = try? BILPsbtMaps.parse(bytes) else { t(false, "the tampered PSBT parses"); return }
            t((try? tampered.outputDerivations()) == nil, "outputDerivations() throws for a non-canonical leaf-hash count")
            t(P.changeBeyondBound(review: review(id), plan: plan, maps: tampered) == nil, "changeBeyondBound → nil")
            let verified = BILVerifiedPayload.bitcoinPsbt(bytes: bytes, maps: tampered, witnessOnlyInputs: witnessOnly)
            let refused = P.evaluate(review: review(id), plan: plan, verified: verified)
            eq(refused.refusal?.code ?? "", "CHANGE_PATH", "code CHANGE_PATH")
            eq(refused.refusal?.key ?? "", "PublicProtocol.err.integrity", "err.integrity")
            t(!refused.canSign && !refused.requiresAcknowledgement, "a hard refusal, not a consent question")
            let conflict = P.evaluate(review: review(id), plan: plan, verified: verified, outpointConflicts: [0])
            eq(conflict.refusal?.code ?? "", "PREVOUT_CONFLICT", "with a conflict: PREVOUT_CONFLICT first")
            eq(conflict.refusal?.args ?? [], [.int(1)], "input 1")
        }

        section("policy: proven-path regex (Java find + $) and ownership labels (matchEntire)")
        do {
            let base = "Returns to the signing wallet (verified from its public key, m/84'/0'/0'/1/5)"
            eq(P.provenPath(base) ?? [], path(84, 0, 0, 1, 5), "plain")
            eq(P.provenPath(base + "\n") ?? [], path(84, 0, 0, 1, 5), "Java $ before a final \\n")
            eq(P.provenPath(base + "\r\n") ?? [], path(84, 0, 0, 1, 5), "Java $ before a final \\r\\n")
            eq(P.provenPath(base + "\u{2028}") ?? [], path(84, 0, 0, 1, 5), "Java $ before a final U+2028")
            t(P.provenPath(base + "\u{000B}") == nil, "U+000B is not a Java line terminator")
            t(P.provenPath(base + "\n\n") == nil, "two final line breaks")
            t(P.provenPath(base + " ") == nil, "trailing text")
            t(P.provenPath("x, m/1/2)") == [1, 2], "minimal")
            t(P.provenPath("x, m/12345678901)") == nil, "11-digit index")
            t(P.provenPath("x, m/4294967295)") == nil, "index ≥ 2³¹ (10 digits)")
            eq(P.provenPath("a, m/1), b, m/2'/3)") ?? [], [2 | BILPsbtMaps.hardened, 3], "the match at the end")
            t(P.provenPath(", m/" + Array(repeating: "1", count: 11).joined(separator: "/") + ")") == nil, "more than 10 levels")
            eq(P.provenPath(", m/" + Array(repeating: "1", count: 10).joined(separator: "/") + ")")?.count ?? 0, 10, "10 levels")
            t(P.provenPath(", m/٣)") == nil, "ASCII digits only")
            // Labels: whole match, Int32 numbers, first of a number kept.
            let id = "O-BTC-3-change-999"
            let rv = review(id)
            let extra = rv.fields + [
                BILReviewField(index: 100, label: "Output 99999999999 ownership", value: "x, m/84'/0'/0'/1/5000)"),
                BILReviewField(index: 101, label: "Output 2 ownership\n", value: "x, m/84'/0'/0'/1/5000)"),
                BILReviewField(index: 102, label: "output 3 ownership", value: "x, m/84'/0'/0'/1/5000)"),
            ]
            eq(P.changeBeyondBound(review: reviewCopy(rv, fields: extra), plan: SigningVectors.plan(id), maps: bareMaps())?.count ?? -1, 0,
               "labels that are not exactly \"Output N ownership\" (Int32 N) are ignored")
            let dup = rv.fields + [BILReviewField(index: 103, label: "Output 2 ownership", value: "x, m/84'/0'/0'/1/5000)")]
            eq(P.changeBeyondBound(review: reviewCopy(rv, fields: dup), plan: SigningVectors.plan(id), maps: bareMaps())?.count ?? -1, 0,
               "a second \"Output 2 ownership\" is ignored (first kept)")
            let first = [BILReviewField(index: 0, label: "Output 2 ownership", value: "x, m/84'/0'/0'/1/5000)")] + rv.fields
            eq(P.changeBeyondBound(review: reviewCopy(rv, fields: first), plan: SigningVectors.plan(id), maps: bareMaps())?.first?.args ?? [],
               [.int(2), .text("5000")], "the first \"Output 2 ownership\" decides")
        }

        section("policy: TRON — the owner must be the signer, and no checkbox lifts that (C-TRX-3)")
        do {
            t(evaluate("T8-flow-tron-trc20-transfer").refusal == nil, "own TRC-20 transfer")
            let member = evaluate("O-TRX-1-owner-not-signer")
            eq(member.refusal?.key ?? "", "PublicProtocol.err.tronOwner", "err.tronOwner")
            eq(member.refusal?.args ?? [], [.text("TJRabPrwbZy45sbavfcjinPJC18kjpRTv8")], "the contract's owner")
            eq(member.refusal?.code ?? "", "TRON_OWNER", "code TRON_OWNER")
            t(!member.canSign, "cannot sign")
            t(!member.requiresAcknowledgement, "not a consent question")
            t(!member.withInsight(.high).canSign, "a card does not lift it")
            eq(P.tronOwnerRefusal(ownerHex41: "41" + repeatHex("zz", 20), plan: SigningVectors.plan("T8-flow-tron-trx-transfer"))?.args ?? [],
               [.text("41" + repeatHex("zz", 20))], "an owner that is not hex is shown as it is")
        }

        section("policy: typed data without a chain id — the engine's warning is enough")
        do {
            let id = "O-EVM-5-permit2-no-chain-id"
            let r = evaluate(id)
            t(review(id).warnings.contains { BILPublicEngineVocabulary.warning($0).map { BILJSONExact.equal($0.id, BILPublicEngineVocabulary.typedDataAnyChainId) } ?? false },
              "the engine warns typedDataAnyChain")
            t(!r.warnings.contains { $0.kind == .noChainId }, "no duplicate")
            let bare = P.evaluate(review: reviewCopy(review(id), warnings: []), plan: SigningVectors.plan(id), verified: SigningVectors.verified(id))
            eq(bare.warnings.first?.key ?? "", "PublicProtocol.warn.noChainId", "Ownbit's warn.noChainId")
            eq(bare.warnings.first?.risk ?? .low, .medium, "risk medium")
            t(evaluate("T8-flow-evm-typed-data").warnings.isEmpty, "typed data with a chain id: nothing")
        }

        section("policy round 2: an outpoint amount conflict is a hard refusal no checkbox can override")
        do {
            let id = "O-BTC-6-segwit-witness-only"
            let plan = SigningVectors.plan(id)
            let verified = SigningVectors.verified(id)
            if case .bitcoinPsbt(_, _, let w) = verified { eq(w, [0], "witness-only input 0") } else { t(false, "O-BTC-6 PSBT") }
            let ok = P.evaluate(review: review(id), plan: plan, verified: verified)
            t(ok.canSign, "no conflict: signable")
            t(!ok.requiresAcknowledgement, "owner: a warning only, no checkbox for witness-only amounts")
            let conflict = P.evaluate(review: review(id), plan: plan, verified: verified, outpointConflicts: [0])
            t(!conflict.canSign, "conflict: refused")
            t(!conflict.requiresAcknowledgement, "not a consent question")
            eq(conflict.refusal?.code ?? "", P.prevoutConflictCode, "PREVOUT_CONFLICT")
            eq(conflict.refusal?.key ?? "", "PublicProtocol.err.prevoutConflict", "err.prevoutConflict")
            eq(conflict.refusal?.args ?? [], [.int(1)], "1-based input number, an Int for %1$ld")
            eq(P.evaluate(review: review(id), plan: plan, verified: verified, outpointConflicts: [3, 1]).refusal?.args ?? [], [.int(2)],
               "the smallest conflicting input")
            let priority = P.evaluate(review: reviewCopy(review("O-BTC-3-change-1000")), plan: SigningVectors.plan("O-BTC-3-change-1000"),
                                      verified: SigningVectors.verified("O-BTC-3-change-1000"), outpointConflicts: [0])
            eq(priority.refusal?.code ?? "", "PREVOUT_CONFLICT", "a conflict wins over the change bound")
        }

        section("policy round 2: TronLink's ownership check is signed without a checkbox, only by the address it proves")
        do {
            let id = "O-TL-V1-ownership-ios"
            let plan = SigningVectors.plan(id)
            let request = tronLinkRequest(OtherWalletVectors.V1_REQUEST)
            let v = V.pre(request: request, plan: plan, reviewedChainId: plan.review?.network?.chainId)
            guard case .tronOwnershipProof(let raw, let name, _, let proto)? = v.payload else { t(false, "V1 proof: \(v)"); return }
            let r = P.evaluate(review: review(id), plan: plan, verified: v.payload!)
            t(r.refusal == nil, "the proof by its own address")
            t(!r.requiresAcknowledgement, "no checkbox")
            let other = BILVerifiedPayload.tronOwnershipProof(raw: raw, name: name, ownerHex41: "41" + repeatHex("00", 20), txProto: proto)
            eq(P.evaluate(review: review(id), plan: plan, verified: other).refusal?.code ?? "", "TRON_PROOF_SIGNER", "another address")
            eq(P.evaluate(review: review(id), plan: plan, verified: other).refusal?.key ?? "", "PublicProtocol.err.integrity", "err.integrity")
        }

        section("policy: no online rule anywhere (product decision)")
        do {
            // Checked on the source by run.sh (verifier-rules); here: the policy input has no connectivity parameter at all.
            let r = evaluate("T8-flow-bitcoin-crypto-psbt")
            t(r.canSign, "a plain PSBT is signable offline")
        }
    }

    /// Maps of a PSBT without output derivations (the change bound then comes from the proofs alone).
    private static func bareMaps() -> BILPsbtMaps {
        guard case .bitcoinPsbt(_, let maps, _) = SigningVectors.verified("T8-flow-bitcoin-crypto-psbt") else { print("FAIL bare maps"); exit(2) }
        return maps
    }
}
