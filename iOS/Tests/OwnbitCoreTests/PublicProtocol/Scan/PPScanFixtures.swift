//  PPScanFixtures.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Port of the app harness suite `scripts/public-protocol/tests/scan` (Fixtures.swift) to XCTest.
//
//  Fixtures.swift — the golden vectors of the pinned engine as the scan suite needs them (port of the test helpers
//  `PublicFixtures` in Android PublicQrFormatTest.kt and `SigningVectors.steps/request` in SigningVectors.kt).
//  Read from $PUB_FIXTURES with the app's own strict JSON parser (engine options); never edited.
//

import Foundation
import XCTest
@testable import OwnbitCore

extension PPScanSuite {

    enum ScanFixtures {

        struct Step {
            let caseId: String
            let request: BILJSONObject
            let response: BILJSONObject
            var op: String { return request.str("operation") ?? "" }
            var ok: Bool { return response.bool("ok") == true }
            var result: BILJSONObject? { return response.obj("result") }
            var errorCode: String? { return response.obj("error")?.str("code") }
            var errorMessage: String? { return response.obj("error")?.str("message") }
        }

        /// One `scanAdd`: the frame and the engine's answer.
        struct ScanStep {
            let frame: String
            let ok: Bool
            let complete: Bool
            let error: String?
            let result: BILJSONObject?
        }

        struct ScanCase {
            let id: String
            let steps: [ScanStep]
        }

        static let root: BILJSONObject = {
            guard let o = BILStrictJSON.parseObject(fixtureText("vectors.json"), options: .engine) else {
                print("FAIL vectors.json does not parse with BILStrictJSON (engine options)")
                exit(2)
            }
            return o
        }()

        private static let fixtures: BILJSONObject = root.obj("fixtures") ?? BILJSONObject()

        /// `{"$fixture": name}` → the shared fixture (SigningVectors.expand).
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

        /// Every dispatch step in file order.
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

        static func steps(_ id: String, _ op: String? = nil) -> [Step] {
            return allSteps.filter { $0.caseId == id && (op == nil || $0.op == op!) }
        }

        /// The request the flow decoded (last complete scan / paste).
        static func request(_ id: String) -> BILJSONObject? {
            return steps(id).last(where: { ($0.op == "scanAdd" || $0.op == "decodePayload") && $0.ok && $0.result?.bool("complete") == true })?
                .result?.obj("request")
        }

        /// The engine request of the first review / resolve step (OtherWalletMappersTest.vectorRequest).
        static func vectorRequest(_ id: String) -> BILJSONObject? {
            return steps(id).first(where: { $0.op == "review" || $0.op == "resolveSigningPlan" })?.request.obj("request")
        }

        /// The scanAdd steps of every case, grouped by case in first-appearance order.
        static let scanCases: [ScanCase] = {
            var order = [String]()
            var map = [String: [ScanStep]]()
            for s in allSteps where s.op == "scanAdd" {
                let complete = s.ok && s.result?.bool("complete") == true
                let step = ScanStep(frame: s.request.str("frame") ?? "", ok: s.ok, complete: complete,
                                    error: s.ok ? nil : s.errorMessage, result: s.result)
                if map[s.caseId] == nil { order.append(s.caseId) }
                map[s.caseId, default: []].append(step)
            }
            return order.map { ScanCase(id: $0, steps: map[$0] ?? []) }
        }()

        static func scanFrames(_ id: String) -> [String] {
            return steps(id, "scanAdd").compactMap { $0.request.str("frame") }
        }

        /// The engine answer of each frame of a scan case.
        static func scanAnswers(_ id: String) -> [String: BILJSONObject] {
            var out = [String: BILJSONObject]()
            for s in steps(id, "scanAdd") {
                if let f = s.request.str("frame"), let r = s.result { out[f] = r }
            }
            return out
        }

        /// `decodePayload` inputs (paste: PSBT Base64 / hex text, UR lines).
        static var pastes: [String] {
            return allSteps.filter { $0.op == "decodePayload" }.compactMap { $0.request.str("payload") }
        }

        /// `createPublicPairing` outputs as (type, frame).
        static var pairingFrames: [(type: String, frame: String)] {
            var out = [(type: String, frame: String)]()
            for s in allSteps where s.op == "createPublicPairing" && s.ok {
                guard let r = s.result, let type = r.str("type"), let frames = r.strings("frames") else { continue }
                for f in frames { out.append((type, f)) }
            }
            return out
        }

        /// `encodeResponse` outputs as (type, frames).
        static var responses: [(type: String, frames: [String])] {
            var out = [(type: String, frames: [String])]()
            for s in allSteps where s.op == "encodeResponse" && s.ok {
                guard let r = s.result, let type = r.str("type"), let frames = r.strings("frames") else { continue }
                out.append((type, frames))
            }
            return out
        }

        /// keystone-tron-public.json string values.
        static var keystoneTron: [String: String] {
            guard let o = BILStrictJSON.parseObject(fixtureText("keystone-tron-public.json"), options: .engine) else { return [:] }
            var out = [String: String]()
            for e in o.entries { if let s = e.value.stringValue { out[e.key] = s } }
            return out
        }

        /// The request frames of evm-public-ui.json.
        static var evmPublicUiFrames: [String] {
            return BILStrictJSON.parseObject(fixtureText("evm-public-ui.json"), options: .engine)?.strings("frames") ?? []
        }

        private static let urPartPrefix = try! NSRegularExpression(pattern: "^ur:[a-z-]+/\\d+-\\d+/", options: [.caseInsensitive])

        /// The kind a signing-request transport frame must get, from its plain shape (independent of BILPublicQrFormat).
        static func expectedTransportKind(_ frame: String) -> BILPublicQrKind? {
            let t = BILKotlinText.trim(frame)
            let lower = t.lowercased()
            if t.hasPrefix("B$") { return .bbqrPart }
            if t.hasPrefix("cHNidP") { return .psbtBase64 }
            if lower.hasPrefix("70736274ff") { return .psbtHex }
            if lower.hasPrefix("ur:") {
                let r = NSRange(location: 0, length: (t as NSString).length)
                return urPartPrefix.firstMatch(in: t, options: [.anchored], range: r) != nil ? .urPart : .urSignRequest
            }
            return nil
        }
    }
}
