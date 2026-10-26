//  PPVerifierVectors.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Port of the app harness suite `scripts/public-protocol/tests/verifier` (Vectors.swift) to XCTest.
//
//  Vectors.swift — the signing flows of the golden vectors as the verifier suite needs them (port of Android
//  core/publicsigner/src/test/kotlin/io/ownbit/core/publicsigner/testing/SigningVectors.kt, the parts the verifier /
//  policy / insight tests use). Read from $PUB_FIXTURES/vectors.json with the app's own strict JSON parser (engine
//  options); `{"$fixture": name}` references expanded. Never edited.
//

import Foundation
import XCTest
@testable import OwnbitCore

extension PPVerifierSuite {

    enum SigningVectors {

        struct Step {
            let caseId: String
            let request: BILJSONObject
            let response: BILJSONObject
            var op: String { return request.str("operation") ?? "" }
            var ok: Bool { return response.bool("ok") == true }
            var result: BILJSONObject? { return response.obj("result") }
        }

        static let root: BILJSONObject = {
            guard let o = BILStrictJSON.parseObject(fixtureText("vectors.json"), options: .engine) else {
                print("FAIL vectors.json does not parse with BILStrictJSON (engine options)")
                exit(2)
            }
            return o
        }()

        private static let fixtures: BILJSONObject = root.obj("fixtures") ?? BILJSONObject()

        static func expand(_ v: BILJSONValue) -> BILJSONValue {
            switch v {
            case .object(let o):
                if o.count == 1, let ref = o.str("$fixture"), let f = fixtures[ref] { return f }
                var out = BILJSONObject()
                for e in o.entries { out.set(e.key, expand(e.value)) }
                return .object(out)
            case .array(let a):
                return .array(a.map(expand))
            default:
                return v
            }
        }

        static let allSteps: [Step] = {
            var out = [Step]()
            for c in root.arr("cases") ?? [] {
                guard let co = c.objectValue, let id = co.str("id") else { continue }
                for s in co.arr("steps") ?? [] {
                    guard let so = s.objectValue, let req = so["request"].map(expand)?.objectValue, let resp = so.obj("response") else { continue }
                    out.append(Step(caseId: id, request: req, response: resp))
                }
            }
            return out
        }()

        static let ids: [String] = {
            var seen = [String]()
            for s in allSteps where !seen.contains(s.caseId) { seen.append(s.caseId) }
            return seen
        }()

        static func steps(_ id: String, _ op: String? = nil) -> [Step] {
            return allSteps.filter { $0.caseId == id && (op == nil || $0.op == op!) }
        }

        /// The request the flow decoded (last complete scan / paste).
        static func request(_ id: String) -> BILJSONObject {
            guard let r = steps(id).last(where: { ($0.op == "scanAdd" || $0.op == "decodePayload") && $0.ok && $0.result?.bool("complete") == true })?
                .result?.obj("request") else {
                print("FAIL no decoded request in vector \(id)")
                exit(2)
            }
            return r
        }

        static func planJson(_ id: String) -> BILJSONObject {
            guard let p = steps(id, "resolveSigningPlan").first?.result else {
                print("FAIL no plan in vector \(id)")
                exit(2)
            }
            return p
        }

        static func plan(_ id: String) -> BILPublicPlan {
            return planOf(planJson(id))
        }

        static func planOf(_ json: BILJSONObject) -> BILPublicPlan {
            do {
                return try BILPublicPlan.fromEngine(json)
            } catch {
                print("FAIL plan does not parse: \(error)")
                exit(2)
            }
        }

        static func signResults(_ id: String) -> [BILJSONObject] {
            return steps(id, "signPlanTask").filter { $0.ok }.compactMap { $0.result }
        }

        static func resultOf(_ json: BILJSONObject) -> BILPublicSignResult {
            do {
                return try BILPublicSignResult.fromEngine(json)
            } catch {
                print("FAIL result does not parse: \(error)")
                exit(2)
            }
        }

        static func finalResult(_ id: String) -> BILPublicSignResult {
            guard let last = signResults(id).last else {
                print("FAIL no sign result in vector \(id)")
                exit(2)
            }
            return resultOf(last)
        }

        static func encoded(_ id: String) -> BILJSONObject? {
            return steps(id, "encodeResponse").first(where: { $0.ok })?.result
        }

        static func response(_ id: String) -> BILPublicResponseQr {
            guard let e = encoded(id), let r = try? BILPublicResponseQr.fromEngine(e) else {
                print("FAIL no response in vector \(id)")
                exit(2)
            }
            return r
        }

        /// Flows that end with a verified answer (scan → … → encodeResponse, every step ok; Android `answeredFlows`).
        static let answeredFlows: [String] = {
            return ids.filter { id in
                let s = steps(id)
                return s.contains { $0.op == "encodeResponse" && $0.ok } && s.contains { $0.op == "signPlanTask" && $0.ok }
                    && s.contains { $0.op == "resolveSigningPlan" } && !s.contains { $0.op == "review" && !$0.ok }
            }.sorted()
        }()

        /// `pre` with the plan's reviewed chain id (Android `PublicSignVerifierTest.pre`).
        static func pre(_ id: String, request: BILJSONObject? = nil, plan: BILPublicPlan? = nil) -> BILPublicSignVerifier.Verdict {
            let p = plan ?? self.plan(id)
            return BILPublicSignVerifier.pre(request: request ?? self.request(id), plan: p, reviewedChainId: p.review?.network?.chainId)
        }

        /// The verified payload of flow `id` (exits when pre refuses: a harness error).
        static func verified(_ id: String, request: BILJSONObject? = nil, plan: BILPublicPlan? = nil) -> BILVerifiedPayload {
            let v = pre(id, request: request, plan: plan)
            guard let payload = v.payload else {
                print("FAIL pre-check of \(id) refused: \(v)")
                exit(2)
            }
            return payload
        }
    }

    // MARK: - JSON edit helpers (Kotlin `JsonObject(map + (k to v))` / `JsonObject(map - k)`)

    static func with(_ o: BILJSONObject, _ key: String, _ value: BILJSONValue) -> BILJSONObject {
        return o.appending(key, value)
    }

    static func without(_ o: BILJSONObject, _ key: String) -> BILJSONObject {
        var copy = o
        copy.remove(key)
        return copy
    }

    /// A plan JSON whose `signingBytesDigest` (and every task's) is `digest` (Android `withDigest`).
    static func withDigest(_ plan: BILJSONObject, _ digest: String) -> BILJSONObject {
        let tasks: [BILJSONValue] = (plan.arr("tasks") ?? []).map { t in
            guard let o = t.objectValue else { return t }
            return .object(with(o, "signingBytesDigest", .string(digest)))
        }
        return with(with(plan, "signingBytesDigest", .string(digest)), "tasks", .array(tasks))
    }

    /// A copy of `review` with the given parts replaced (Kotlin `review.copy(...)`).
    static func reviewCopy(_ r: BILPublicReview, fields: [BILReviewField]? = nil, warnings: [String]? = nil,
                    decodeStatus: BILDecodeStatus? = nil, riskLevel: BILRiskLevel? = nil) -> BILPublicReview {
        return BILPublicReview(chain: r.chain, title: r.title, summary: r.summary, fields: fields ?? r.fields, warnings: warnings ?? r.warnings,
                               requestHash: r.requestHash, canSign: r.canSign, decodeStatus: decodeStatus ?? r.decodeStatus,
                               riskLevel: riskLevel ?? r.riskLevel, network: r.network, display: r.display, asset: r.asset, raw: r.raw)
    }

    static func hexBytes(_ s: String) -> [UInt8] {
        guard let b = BILPublicHex.decodeOptional0x(s) else {
            print("FAIL bad hex in test: \(s.prefix(20))")
            exit(2)
        }
        return b
    }

    static func repeatHex(_ unit: String, _ n: Int) -> String {
        return String(repeating: unit, count: n)
    }
}
