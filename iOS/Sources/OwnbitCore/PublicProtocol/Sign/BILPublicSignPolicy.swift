//  BILPublicSignPolicy.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Public protocol (cold signer) — Ownbit's rules on top of the engine for a reviewed public request (spec S§8.2,
//  checklist C-GEN-11 / C-GEN-12, C-BTC-7, C-TRX-3, C-SOL-3; design §3.10, R5 §2). Port of Android
//  `core/publicsigner/.../sign/PublicSignPolicy.kt` (b8c70c25). Pure; `evaluate` is called once the native pre-check
//  passed, and `BILPublicPolicyResult.withInsight` when the D43 reading is known.
//
//  - Page risk = max(engine `riskLevel` (normal → low, warning → medium, high → high) of the review the page shows, the
//    D43 card's risk, Ownbit's own warnings).
//  - Acknowledgement (per request, never remembered): engine `partiallyDecoded` / `opaque`, page risk ≥ high, a Solana
//    durable nonce, a Bitcoin output to this wallet beyond index `maxChangeIndex`. Only then is `riskAcknowledged = true`
//    passed to the engine (it insists itself for partial / opaque).
//  - Hard refusals (no acknowledgement can override): a TRON transaction whose owner is not the signing address
//    (permission-member signing); a TronLink ownership check for another address than the signing one; a Bitcoin output
//    the engine marked as the wallet's without a path the native code can read (`err.integrity`, fail closed for
//    C-BTC-7); a Bitcoin input claiming another amount than this device already signed for the same outpoint
//    (`err.prevoutConflict`). Every other hard refusal is the engine's or the verifier's.
//  - No online rule: the public protocol never checks or warns about connectivity (product decision).
//
//  Strings are compared exactly (code units). Pure Foundation (+ the pure D43 risk type); macOS harness: tests/verifier/.
//  Never logs.
//

import Foundation

enum BILPublicSignPolicy {

    /// Highest receive / change index Ownbit treats as an ordinary address of the wallet (C-BTC-7).
    static let maxChangeIndex: UInt32 = 999

    /// Code of the outpoint-amount conflict refusal (a native code, not an engine one).
    static let prevoutConflictCode = "PREVOUT_CONFLICT"

    /// The engine's risk level on the D43 scale.
    static func engineRisk(_ l: BILRiskLevel) -> BILSignatureRisk {
        switch l {
        case .normal: return .low
        case .warning: return .medium
        case .high: return .high
        }
    }

    /// Evaluates a ready `plan` whose bytes the native pre-check decoded into `verified`; `review` is the plan's review.
    /// `outpointConflicts`: the Bitcoin inputs (0-based) whose claimed amount differs from one this device signed.
    /// `requestOnlyReview`: the engine's review of the request alone (no verified change). With an output beyond the
    /// bound (`.changeBeyondBound`) the page shows that review — every output a payment, so the Bitcoin HIGH FEE rule
    /// counts that output as sent — and the engine risk (pill, `.highRisk`) is taken from it, so the risk level, the HIGH
    /// FEE banner and the checkbox agree with what the page shows. The ownership proofs are always read from `review`.
    static func evaluate(review: BILPublicReview, plan: BILPublicPlan, verified: BILVerifiedPayload,
                         insightRisk: BILSignatureRisk? = nil, outpointConflicts: [Int] = [],
                         requestOnlyReview: BILPublicReview? = nil) -> BILPublicPolicyResult {
        var reasons = [BILPublicAckReason]()
        switch review.decodeStatus {
        case .partiallyDecoded: reasons.append(.partiallyDecoded)
        case .opaque: reasons.append(.opaque)
        case .fullyDecoded: break
        }
        var warnings = [BILPublicOwnbitWarning]()
        var refusal: BILPublicSignError? = nil
        switch verified {
        case .bitcoinPsbt(_, let maps, _):
            let beyond = changeBeyondBound(review: review, plan: plan, maps: maps)
            if let first = outpointConflicts.min() {
                refusal = BILPublicSignerErrors.prevoutConflict(inputNumber: first + 1)
            } else if let found = beyond {
                if !found.isEmpty { reasons.append(.changeBeyondBound) }
                warnings += found
            } else {
                refusal = BILPublicSignError(integrityKey, code: "CHANGE_PATH")
            }
        case .solanaTransaction(_, let header, _):
            if header.usesDurableNonce {
                // The consent is Ownbit's rule either way. The text: the engine says it too (shown with the same
                // `warn.durableNonce` string through the vocabulary alias); Ownbit's copy only when the engine did not.
                reasons.append(.durableNonce)
                if !engineSaid(review, BILPublicEngineVocabulary.durableNonceId) {
                    warnings.append(BILPublicOwnbitWarning(kind: .durableNonce, key: durableNonceKey, risk: .medium))
                }
            }
        case .evmTypedData(_, _, let hasDomainChainId):
            // The engine says it too (`typedDataAnyChain`, localized); Ownbit's text only when the engine did not.
            if !hasDomainChainId && !engineSaid(review, BILPublicEngineVocabulary.typedDataAnyChainId) {
                warnings.append(BILPublicOwnbitWarning(kind: .noChainId, key: noChainIdKey, risk: .medium))
            }
        case .tronTransaction(_, _, let ownerHex41, _, _):
            refusal = tronOwnerRefusal(ownerHex41: ownerHex41, plan: plan)
        case .tronOwnershipProof(_, _, let ownerHex41, _):
            // The placeholder proves the request's address: it must be the key that signs it (the engine checks it
            // too). Not a transaction, no risk, no checkbox (owner, R2-7).
            let signer = signingAddressHex41(plan)
            if signer == nil || !BILJSONExact.equal(signer!, ownerHex41) {
                refusal = BILPublicSignError(integrityKey, code: "TRON_PROOF_SIGNER")
            }
        default:
            break
        }
        let shown = reasons.contains(.changeBeyondBound) ? (requestOnlyReview ?? review) : review
        let engine = engineRisk(shown.riskLevel)
        if engine.rank >= BILSignatureRisk.high.rank { reasons.append(.highRisk) }
        return BILPublicPolicyResult(engineRisk: engine, insightRisk: nil, warnings: warnings, ackReasons: reasons, refusal: refusal)
            .withInsight(insightRisk)
    }

    /// C-TRX-3: the contract's owner must be the signing address; otherwise this is a permission-member signature, refused
    /// in 5.0.x (`err.tronOwner` with the owner's address: `base58(anyHex21:) ?? ownerHex`, design A7).
    static func tronOwnerRefusal(ownerHex41: String, plan: BILPublicPlan) -> BILPublicSignError? {
        if let signer = signingAddressHex41(plan), BILJSONExact.equal(signer, ownerHex41) { return nil }
        let owner = BILTronAddressCodec.base58(anyHex21: ownerHex41) ?? ownerHex41
        return BILPublicSignerErrors.tronOwner(owner)
    }

    /// C-BTC-7: outputs the engine proved to return to the signing wallet (its review adds `Output N ownership`, whose
    /// value ends with the proven path: `… public key, m/84'/0'/0'/1/i)`) at a single-sig path `m/{44,49,84,86}'/0'/0'/{0,1}/i`
    /// with `i > 999`. They are still the wallet's, but no wallet scans that far: warning + acknowledgement. The paths
    /// checked for each such output: the engine's proven path and every PSBT derivation of that output for a task
    /// wallet's fingerprint — so a derivation the native code does not read (or reads differently) can never hide an
    /// output beyond the bound. nil = the engine marked an output as the wallet's but neither its proof nor the PSBT gives
    /// a path the native code can read (fail closed: the request is refused). A PSBT whose output derivations cannot be
    /// read at all (a non-canonical leaf-hash count) is nil too (Android lets that escape as an unexpected error; both
    /// refuse).
    static func changeBeyondBound(review: BILPublicReview, plan: BILPublicPlan, maps: BILPsbtMaps) -> [BILPublicOwnbitWarning]? {
        var fingerprints = [String]()
        for task in plan.tasks {
            for fp in task.targetFingerprints where !fingerprints.contains(where: { BILJSONExact.equal($0, fp) }) {
                fingerprints.append(fp)
            }
        }
        guard let all = try? maps.outputDerivations() else { return nil }
        let derivations = all.filter { d in
            let fp = d.fingerprint.lowercased()
            return fingerprints.contains { BILJSONExact.equal($0, fp) }
        }
        var owned = [(number: Int, proof: String)]()
        for field in review.fields {
            guard let match = BILKotlinText.wholeMatch(ownershipLabel, field.label),
                  let number = kotlinInt(group(match, 1, in: field.label)) else { continue }
            if owned.contains(where: { $0.number == number }) { continue }
            owned.append((number, field.value))
        }
        var warnings = [BILPublicOwnbitWarning]()
        for (number, proof) in owned {
            var paths = [[UInt32]]()
            if let proven = provenPath(proof) { paths.append(proven) }
            paths += derivations.filter { $0.outputIndex + 1 == number }.map { $0.path }
            if paths.isEmpty { return nil }
            guard let beyond = paths.first(where: beyondBound), let index = beyond.last else { continue }
            warnings.append(BILPublicOwnbitWarning(kind: .changeIndex, key: changeIndexKey, args: [.int(number), .text(String(index))],
                                                   risk: .high))
        }
        return warnings
    }

    /// The path at the end of the engine's ownership proof (`Returns to the signing wallet (verified from its public key,
    /// m/84'/0'/0'/1/5)`), as BIP-32 indexes (hardened ones with `BILPsbtMaps.hardened`); nil when it ends otherwise or an
    /// index is ≥ 2³¹. Android `Regex(", (m(?:/[0-9]{1,10}'?){1,10})\\)$").find(proof)`, with Java's `$` (end of input
    /// or before a final line terminator).
    static func provenPath(_ proof: String) -> [UInt32]? {
        let range = NSRange(location: 0, length: proof.utf16.count)
        guard let match = provenPathPattern.firstMatch(in: proof, options: [], range: range),
              let text = group(match, 1, in: proof) else { return nil }
        var units = Array(text.utf16)
        guard units.count >= 2, units[0] == 0x6D, units[1] == 0x2F else { return nil }      // "m/"
        units.removeFirst(2)
        var out = [UInt32]()
        for part in String(decoding: units, as: UTF16.self).split(separator: "/", omittingEmptySubsequences: false) {
            var digits = Array(part.utf8)
            let hardened = digits.last == 0x27                                                 // "'"
            if hardened { digits.removeLast() }
            guard !digits.isEmpty, digits.count <= 10, digits.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }) else { return nil }
            var value: UInt64 = 0
            for d in digits { value = value * 10 + UInt64(d - 0x30) }
            guard value < UInt64(BILPsbtMaps.hardened) else { return nil }
            out.append(hardened ? UInt32(value) | BILPsbtMaps.hardened : UInt32(value))
        }
        return out
    }

    /// A single-sig receive / change path of account 0 whose address index is above `maxChangeIndex`:
    /// `m/{44,49,84,86}'/0'/0'/{0,1}/i`, `999 < i < 2³¹`.
    static func beyondBound(_ path: [UInt32]) -> Bool {
        guard path.count == 5 else { return false }
        let h = BILPsbtMaps.hardened
        let single = singleSigPurposes.contains(path[0]) && path[1] == h && path[2] == h
        return single && (path[3] == 0 || path[3] == 1) && path[4] < h && path[4] > maxChangeIndex
    }

    // MARK: - Private

    private static let integrityKey = "PublicProtocol.err.integrity"
    private static let changeIndexKey = "PublicProtocol.warn.changeIndex"
    private static let durableNonceKey = "PublicProtocol.warn.durableNonce"
    private static let noChainIdKey = "PublicProtocol.warn.noChainId"

    private static let singleSigPurposes: [UInt32] = [44, 49, 84, 86].map { $0 | BILPsbtMaps.hardened }

    /// Android `Regex("^Output ([0-9]+) ownership$")` used with `matchEntire` (whole label).
    private static let ownershipLabel: NSRegularExpression = {
        // A constant, valid pattern: a failure here is a programming error caught by the harness.
        return try! NSRegularExpression(pattern: "^Output ([0-9]+) ownership$", options: [])
    }()

    /// Android `PROVEN_PATH` with Java's non-multiline `$` spelled out (ICU's `$` would also accept U+000B / U+000C).
    private static let provenPathPattern: NSRegularExpression = {
        return try! NSRegularExpression(pattern: ", (m(?:/[0-9]{1,10}'?){1,10})\\)(?=(?:\\r\\n|[\\n\\r\\u0085\\u2028\\u2029])?\\z)",
                                        options: [])
    }()

    /// The lower-case `41…` hex of the plan's single task's first address (Android
    /// `plan.tasks.singleOrNull()?.addresses?.firstOrNull()?.let(TronAddressCodec::toHex41)`).
    private static func signingAddressHex41(_ plan: BILPublicPlan) -> String? {
        guard plan.tasks.count == 1, let address = plan.tasks[0].addresses.first else { return nil }
        return BILPublicSignVerifier.tronHex41(address)
    }

    /// The engine's review already carries the warning with vocabulary id `id` (localized on the page).
    private static func engineSaid(_ review: BILPublicReview, _ id: String) -> Bool {
        return review.warnings.contains { w in
            guard let found = BILPublicEngineVocabulary.warning(w) else { return false }
            return BILJSONExact.equal(found.id, id)
        }
    }

    /// Capture group `n` of `match` in `text`, nil when it did not participate.
    private static func group(_ match: NSTextCheckingResult, _ n: Int, in text: String) -> String? {
        let r = match.range(at: n)
        guard r.location != NSNotFound else { return nil }
        let units = Array(text.utf16)
        guard r.location >= 0, r.location + r.length <= units.count else { return nil }
        return String(decoding: units[r.location..<(r.location + r.length)], as: UTF16.self)
    }

    /// Kotlin `String.toIntOrNull()` of ASCII digits: nil above `Int32.max`.
    private static func kotlinInt(_ digits: String?) -> Int? {
        guard let d = digits, !d.isEmpty else { return nil }
        var value: Int64 = 0
        for c in d.utf8 {
            guard c >= 0x30 && c <= 0x39 else { return nil }
            value = value * 10 + Int64(c - 0x30)
            if value > Int64(Int32.max) { return nil }
        }
        return Int(value)
    }
}
