//  PPScanSessionTests.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Port of the app harness suite `scripts/public-protocol/tests/scan` (SessionTests.swift) to XCTest.
//
//  SessionTests.swift — BILPublicScanSession with a scripted engine and a virtual clock (port of Android
//  PublicScanSessionTest + the TronLink / TokenPocket session rules of PublicScanRound2RoutingTest that belong to the
//  session; R4 §18 items 5–6).
//

import Foundation
import XCTest
@testable import OwnbitCore

extension PPScanSuite {

    private typealias V = OtherWalletVectors

    /// Non-autoclosure checks: arguments may contain `await` (TestKit's `t` / `eq` take autoclosures, which cannot).
    @discardableResult
    private static func check(_ ok: Bool, _ what: String, file: StaticString = #file, line: UInt = #line) -> Bool {
        return t(ok, what, file: file, line: line)
    }

    @discardableResult
    private static func same<T: Equatable>(_ actual: T, _ expected: T, _ what: String, file: StaticString = #file, line: UInt = #line) -> Bool {
        return eq(actual, expected, what, file: file, line: line)
    }

    @MainActor
    private static func expectScanError(_ what: String, file: StaticString = #file, line: UInt = #line,
                                 _ body: () async throws -> Void) async -> BILPublicScanError? {
        do {
            try await body()
            check(false, "\(what): did not throw", file: file, line: line)
        } catch let e as BILPublicScanError {
            return e
        } catch {
            check(false, "\(what): threw \(type(of: error))", file: file, line: line)
        }
        return nil
    }

    @MainActor
    private static func makeSession(_ engine: FakeScanEngine, _ clock: TestClock = TestClock()) -> BILPublicScanSession {
        return BILPublicScanSession(engine: engine, clock: { clock.now })
    }

    @MainActor
    static func sessionTests() async {
        let psbt = "T8-flow-bitcoin-crypto-psbt"
        let psbtFrames = ScanFixtures.scanFrames(psbt)
        check(psbtFrames.count >= 2, "\(psbt) has 2 frames")
        guard psbtFrames.count >= 2 else { return }
        let first = psbtFrames[0], second = psbtFrames[1]

        section("session: an animated crypto-psbt completes; repeats and stray texts never reach the engine")
        do {
            let engine = FakeScanEngine()
            let answers = ScanFixtures.scanAnswers(psbt)
            engine.answer = { f in
                guard let a = answers[f] else { throw BILPublicSignerFailure.malformedResponse }
                return a
            }
            let s = makeSession(engine)
            check(!s.isActive, "idle")
            same(s.progress, .empty, "empty progress")
            let p1 = try? await s.add(first)
            check(p1?.complete == false, "first part not complete")
            same(p1?.parts, 1, "1 part")
            same(engine.handles.count, 1, "the first part opened one engine session")
            same(try? await s.add(first), p1, "a repeat changes nothing")
            same(try? await s.add("hello"), p1, "not a public code: ignored")
            same(try? await s.add("   "), p1, "blank: ignored")
            same(try? await s.add("bb_sign:abc"), p1, "an Ownbit code inside the session API: ignored")
            let pairing = await expectScanError("pairing") {
                _ = try await s.add("ur:crypto-hdkey/oyaxhdcxlkahssqzwfvslofzoxwkrewngotktbmwjkwdcmnefsaaehrlolkskncnktlbaypkvoonhknt")
            }
            same(pairing?.reason, .wrongDirection, "wrong direction")
            same(pairing?.messageKey ?? "", "PublicProtocol.err.pairingCode", "pairing text")
            same(pairing?.endsSession, false, "does not end the session")
            same(pairing?.kind, .pairingUr, "kind")
            let signature = await expectScanError("signature") { _ = try await s.add("UR:ETH-SIGNATURE/OEADTPDAGDMY") }
            same(signature?.messageKey ?? "", "PublicProtocol.err.signatureCode", "signature text")
            let unsupported = await expectScanError("seed UR") { _ = try await s.add("ur:crypto-seed/oeadgdstaslplabg") }
            same(unsupported?.reason, .unsupported, "unsupported UR")
            same(unsupported?.messageKey ?? "", "PublicProtocol.err.unsupportedUr", "unsupported text")
            check(unsupported?.error == nil && unsupported?.endsSession == false, "unsupported UR keeps the session, no TokenPocket error")
            let malformed = await expectScanError("malformed part") { _ = try await s.add("ur:crypto-psbt/2-20/lpad1") }
            same(malformed?.reason, .malformed, "malformed")
            same(malformed?.endsSession, false, "malformed keeps the session")
            let big = await expectScanError("too large") { _ = try await s.add("ur:crypto-psbt/1-3/" + String(repeating: "a", count: 4_300)) }
            same(big?.reason, .tooLarge, "too large")
            same(big?.endsSession, false, "too large keeps the session")
            check(s.isActive, "a stray code in view does not end the scan")
            same(engine.handles.first?.frames ?? [], [first], "the engine saw only real frames")
            let done = try? await s.add(second)
            check(done?.complete == true, "complete")
            check(done?.request != nil && done?.request == ScanFixtures.request(psbt), "the request of the vectors")
            same(done?.chain, .bitcoin, "chain")
            same(done?.transportType ?? "", "crypto-psbt", "transport")
            same(done?.parts, 2, "2 parts")
            check(!s.isActive, "the session ends with the request")
            same(s.progress, .empty, "progress reset")
            same(engine.handles.first?.frames ?? [], [first, second], "frames in order")
            check(!engine.calls.contains("closeScan"), "the engine ended its own session on completion (no close)")
        }

        section("session: the engine's mixed-session refusal reads as another request and resets")
        do {
            let engine = FakeScanEngine()
            engine.answer = { f in
                if f == second { throw BILPublicSignerRefusal(code: "QR_PROTOCOL", engineMessage: "Mixed UR fountain sessions") }
                return FakeScanEngine.progress(0.3)
            }
            let s = makeSession(engine)
            _ = try? await s.add(first)
            let e = await expectScanError("mixed") { _ = try await s.add(second) }
            same(e?.reason, .otherRequest, "other request")
            same(e?.messageKey ?? "", "PublicProtocol.scan.otherRequest", "text")
            same(e?.endsSession, true, "ends")
            same(e?.code ?? "", "QR_PROTOCOL", "code")
            check(!s.isActive, "reset")
            engine.answer = { _ in FakeScanEngine.progress(0.3) }
            _ = try? await s.add(second)
            same(engine.handles.count, 2, "a fresh engine session")
        }

        section("session: a frame of another code (gate) ends the session too")
        do {
            let engine = FakeScanEngine()
            let s = makeSession(engine)
            _ = try? await s.add(first)
            let other = ScanFixtures.scanFrames("T8-flow-evm-eip1559")
            same(other.count, 1, "single-frame EVM request")
            let e = await expectScanError("other code") { _ = try await s.add(other.first ?? "") }
            same(e?.reason, .otherRequest, "other request")
            same(e?.endsSession, true, "ends")
            same(e?.kind, .urSignRequest, "kind")
            check(!s.isActive, "reset")
            check(await eventually { engine.handles.first?.closed == true }, "the engine session is closed")
        }

        section("session: no progress for 150 s — the session times out")
        do {
            let engine = FakeScanEngine()
            let clock = TestClock()
            let s = makeSession(engine, clock)
            _ = try? await s.add(first)
            clock.now += 149_000
            check(!s.expireIfIdle(), "not yet")
            clock.now += 2_000
            check(s.expireIfIdle(), "expired")
            check(await eventually { engine.handles.first?.closed == true }, "engine session closed")
            check(!s.isActive, "reset")
            check(!s.expireIfIdle(), "nothing to expire")
            _ = try? await s.add(first)
            clock.now += 151_000
            let e = await expectScanError("late frame") { _ = try await s.add(second) }
            same(e?.reason, .timedOut, "timed out")
            same(e?.messageKey ?? "", "PublicProtocol.err.scanTimeout", "text")
            same(e?.endsSession, true, "ends")
            check(await eventually { engine.handles.count == 2 && engine.handles[1].closed }, "second engine session closed")
            same(engine.handles.count, 2, "the late part opened nothing")
            same(engine.handles.last?.frames ?? [], [first], "the late part never reached the engine")
        }

        section("session: engine failures end the session with their text")
        do {
            let engine = FakeScanEngine()
            let s = makeSession(engine)
            func failWith(_ error: Error) async -> BILPublicScanError? {
                engine.answer = { _ in throw error }
                return await expectScanError("fail \(type(of: error))") { _ = try await s.add(first) }
            }
            same(await failWith(BILPublicSignerRefusal(code: "SCAN", engineMessage: "No scan session is active."))?.reason, .timedOut, "SCAN")
            same(await failWith(BILPublicSignerRefusal(code: "QR_PROTOCOL", engineMessage: "QR scan memory limit exceeded"))?.reason, .tooLarge, "memory")
            same(await failWith(BILPublicSignerRefusal(code: "LIMIT", engineMessage: "Request exceeds one megabyte."))?.reason, .tooLarge, "LIMIT")
            same(await failWith(BILPublicSignerRefusal(code: "QR_PROTOCOL", engineMessage: "UR checksum failure"))?.reason, .malformed, "checksum")
            same(await failWith(BILPublicSignerRefusal(code: "QR_PROTOCOL", engineMessage: "Unsupported signing UR type"))?.reason, .unsupported, "unsupported UR")
            same(await failWith(BILPublicSignerRefusal(code: "QR_PROTOCOL", engineMessage: "Conflicting BBQR fragment"))?.reason, .otherRequest, "conflicting BBQr")
            same(await failWith(BILPublicSignerRefusal(code: "QR_PROTOCOL", engineMessage: "Mixed UR types "))?.reason, .malformed, "exact message match only")
            let tooLargeText = await failWith(BILPublicSignerRefusal(code: "QR_PROTOCOL", engineMessage: "Too many BBQR fragments"))
            same(tooLargeText?.messageKey ?? "", "PublicProtocol.err.tooLarge", "scan path maps to 5 texts (not err.qrMixed)")
            let down = await failWith(BILPublicSignerFailure.malformedResponse)
            same(down?.reason, .engineUnavailable, "JS failure")
            same(down?.messageKey ?? "", "PublicProtocol.err.engineUnavailable", "engine text")
            same(down?.endsSession, true, "ends")
            same(await failWith(BILPublicSignerFailure.engineUnavailable)?.reason, .engineUnavailable, "engine unavailable")
            same(await failWith(BILPublicSignerRefusal(code: "QR_PROTOCOL", engineMessage: "Invalid UR frame"))?.code ?? "", "QR_PROTOCOL", "code kept")
            check(!s.isActive, "ended")
            let unmapped = await failWith(NSError(domain: "x", code: 1))
            same(unmapped?.reason, .engineUnavailable, "unmapped")
            same(unmapped?.endsSession, true, "unmapped ends")
            check(!s.isActive, "ended")
            engine.answer = { _ in FakeScanEngine.progress(0.4) }
            same((try? await s.add(first))?.parts, 1, "the next frame is processed, not queued forever")
            same(engine.handles.last?.frames ?? [], [first], "a fresh engine session got it")
            // A malformed engine status ends the session as malformed.
            let s2 = makeSession(engine)
            engine.answer = { _ in BILJSONObject([("progress", .number("0.5"))]) }
            let m = await expectScanError("no complete") { _ = try await s2.add(first) }
            same(m?.reason, .malformed, "missing complete → malformed")
            engine.answer = { _ in BILJSONObject([("complete", .bool(true)), ("request", .object(BILJSONObject([("chain", .string("cosmos"))])))]) }
            let m2 = await expectScanError("unknown chain") { _ = try await s2.add(first) }
            same(m2?.reason, .malformed, "unknown chain → malformed")
            check(!s2.isActive, "ended")
        }

        section("session: frames arriving during an engine call wait in the queue and are fed in order")
        do {
            let frames = ScanFixtures.scanFrames("T5-scan-bbqr-H")
            same(frames.count, 5, "5 BBQr frames")
            let engine = FakeScanEngine()
            engine.answer = { _ in FakeScanEngine.progress(0.2) }
            let latch = TestLatch()
            engine.latch = latch
            let s = makeSession(engine)
            let firstCall = Task { @MainActor in try await s.add(frames[0]) }
            check(await eventually { engine.waiting == 1 }, "the first call is in flight")
            same((try? await s.add(frames[1]))?.parts, 2, "queued 2")
            same((try? await s.add(frames[2]))?.parts, 3, "queued 3")
            same((try? await s.add(frames[2]))?.parts, 3, "a repeat of a waiting part")
            same(engine.calls.filter { $0 == "scanAdd" }.count, 1, "one call in flight")
            latch.release()
            let last = try? await firstCall.value
            same(engine.handles.first?.frames ?? [], [frames[0], frames[1], frames[2]], "fed in order")
            same(last?.parts, 3, "parts")
            same(engine.handles.count, 1, "one engine session")
        }

        section("session: a cancelled call forgets its frame so the next loop delivers it again")
        do {
            let frames = ScanFixtures.scanFrames("T5-scan-bbqr-H")
            let engine = FakeScanEngine()
            engine.answer = { _ in FakeScanEngine.progress(0.2) }
            let latch = TestLatch()
            engine.latch = latch
            let s = makeSession(engine)
            let job = Task { @MainActor in try await s.add(frames[0]) }
            check(await eventually { engine.waiting == 1 }, "in flight")
            _ = try? await s.add(frames[1])
            job.cancel()
            let result = await job.result
            if case .failure(let error) = result { check(error is CancellationError, "cancelled") } else { check(false, "cancelled job returned") }
            same(engine.handles.first?.frames ?? ["x"], [], "nothing reached the engine")
            check(!s.isActive, "both frames forgotten: nothing left")
            latch.release()
            _ = try? await s.add(frames[0])
            _ = try? await s.add(frames[1])
            same(engine.handles.last?.frames ?? [], [frames[0], frames[1]], "both accepted again and sent")
            same(engine.handles.count, 2, "a fresh engine session for the restarted gate session")
        }

        section("session: a caller already cancelled when its engine session opened never sends its frame")
        do {
            let frames = ScanFixtures.scanFrames("T5-scan-bbqr-H")
            let engine = FakeScanEngine()
            let s = makeSession(engine)
            engine.answer = { _ in FakeScanEngine.progress(0.2) }
            let job = Task { @MainActor () -> BILScanProgress in
                withUnsafeCurrentTask { $0?.cancel() }
                return try await s.add(frames[0])
            }
            let r = await job.result
            if case .failure(let error) = r { check(error is CancellationError, "cancellation surfaces") } else { check(false, "no cancellation") }
            same(engine.calls, ["openScan"], "no scanAdd for a cancelled caller")
            check(!s.isActive, "the frame was forgotten")
            same((try? await s.add(frames[0]))?.parts, 1, "accepted again")
            same(engine.handles.last?.frames ?? [], [frames[0]], "sent once, by the next delivery")
        }

        section("session: a caller cancelled while openScan is in flight (engine ignores cancellation) never sends its frame")
        do {
            let frames = ScanFixtures.scanFrames("T5-scan-bbqr-H")
            let engine = FakeScanEngine()
            engine.answer = { _ in FakeScanEngine.progress(0.2) }
            let opening = TestLatch(honoursCancellation: false)
            engine.openLatch = opening
            let s = makeSession(engine)
            let job = Task { @MainActor in try await s.add(frames[0]) }
            check(await eventually { engine.openWaiting == 1 }, "openScan in flight")
            _ = try? await s.add(frames[1])                     // queued behind the open
            job.cancel()
            opening.release()
            let r = await job.result
            if case .failure(let error) = r { check(error is CancellationError, "cancelled") } else { check(false, "cancelled job returned") }
            same(engine.calls, ["openScan"], "openScan only: no scanAdd after the cancellation")
            same(engine.handles.first?.frames ?? ["x"], [], "nothing reached the engine")
            check(!s.isActive, "the frame and the queued one were forgotten")
            same((try? await s.add(frames[0]))?.parts, 1, "accepted again")
            same((try? await s.add(frames[1]))?.parts, 2, "the queued one too")
            same(engine.handles.count, 2, "a fresh engine session for the restarted gate session")
            same(engine.handles.first?.closed, true, "the session opened for the cancelled caller is closed")
            same(engine.handles.last?.frames ?? [], [frames[0], frames[1]], "both sent once, in order")
        }

        section("session: a call that returns after the caller was cancelled is treated as cancelled")
        do {
            let frames = ScanFixtures.scanFrames("T5-scan-bbqr-H")
            let engine = FakeScanEngine()
            engine.answer = { _ in FakeScanEngine.progress(0.2) }
            // The engine ignores cancellation (like a synchronous JS call) and returns normally.
            let adding = TestLatch(honoursCancellation: false)
            engine.latch = adding
            let s = makeSession(engine)
            let job = Task { @MainActor in try await s.add(frames[0]) }
            check(await eventually { engine.waiting == 1 }, "scanAdd in flight")
            job.cancel()
            adding.release()
            let r = await job.result
            if case .failure(let error) = r { check(error is CancellationError, "cancellation surfaces") } else { check(false, "no cancellation") }
            same(engine.handles.first?.frames ?? [], [frames[0]], "the engine got the frame (its call ran to the end)")
            check(!s.isActive, "the frame was forgotten")
            same(s.progress, .empty, "its result was not applied")
            same((try? await s.add(frames[0]))?.parts, 1, "accepted again")
        }

        section("session: close ends the engine session; the next part opens a new one")
        do {
            let engine = FakeScanEngine()
            let s = makeSession(engine)
            _ = try? await s.add(first)
            s.close()
            check(await eventually { engine.handles.first?.closed == true }, "closed")
            check(!s.isActive, "not active")
            same(s.progress.parts, 0, "0 parts")
            _ = try? await s.add(first)
            same(engine.handles.count, 2, "new engine session")
            same(BILPublicQrFormat.classify(first), .urPart, "an animated part")
            s.close()
            s.close()
            check(!s.isActive, "close is idempotent")
        }

        section("session (WP7 rules): the deferred close of a closed session never ends the next one")
        do {
            let engine = FakeScanEngine()
            engine.realistic = true
            let answers = ScanFixtures.scanAnswers(psbt)
            engine.answer = { f in
                guard let a = answers[f] else { throw BILPublicSignerFailure.malformedResponse }
                return a
            }
            let s = makeSession(engine)
            check((try? await s.add(first))?.complete == false, "first part")
            same(engine.activeSessionId, 1, "engine session 1 active")
            let closing = TestLatch()
            engine.closeLatch = closing
            s.close()
            check(await eventually { engine.closeWaiting == 1 }, "the close of session 1 is deferred")
            let p = try? await s.add(first)
            check(p?.complete == false, "a new scan starts while the old close is pending")
            same(engine.handles.count, 2, "engine session 2 opened")
            same(engine.activeSessionId, 2, "session 2 active")
            closing.release()
            check(await eventually { engine.closeWaiting == 0 }, "the deferred close ran")
            same(engine.calls.filter { $0 == "closeScan" }.count, 1, "one close (of session 1)")
            same(engine.activeSessionId, 2, "the stale close left session 2 alone")
            same(engine.handles.last?.closed, false, "session 2 open")
            let done = try? await s.add(second)
            check(done?.complete == true, "session 2 completes")
            check(done?.request != nil && done?.request == ScanFixtures.request(psbt), "the request of the vectors")
            same(engine.handles.last?.frames ?? [], [first, second], "session 2 got both frames")
            same(engine.activeSessionId, nil, "completion ended the engine session")
        }

        section("session (WP7 rules): a frame for a superseded engine session reads SCAN → timed out; the other session goes on")
        do {
            let engine = FakeScanEngine()
            engine.realistic = true
            let answers = ScanFixtures.scanAnswers(psbt)
            engine.answer = { f in
                guard let a = answers[f] else { throw BILPublicSignerFailure.malformedResponse }
                return a
            }
            let s1 = makeSession(engine)
            let s2 = makeSession(engine)
            check((try? await s1.add(first))?.complete == false, "s1 first part")
            check((try? await s2.add(first))?.complete == false, "s2 first part supersedes s1's engine session")
            same(engine.activeSessionId, 2, "session 2 active")
            same(engine.handles.first?.closed, true, "session 1 ended by the new openScan")
            let e = await expectScanError("superseded") { _ = try await s1.add(second) }
            same(e?.reason, .timedOut, "SCAN → timed out")
            same(e?.code ?? "", "SCAN", "code SCAN")
            same(e?.messageKey ?? "", "PublicProtocol.err.scanTimeout", "text")
            same(e?.endsSession, true, "ends")
            check(!s1.isActive, "s1 reset")
            same(engine.handles.first?.frames ?? [], [first], "the superseded frame never reached the engine")
            check(await eventually { engine.calls.contains("closeScan") }, "s1's deferred stale close ran")
            same(engine.activeSessionId, 2, "the stale close is a no-op")
            let done = try? await s2.add(second)
            check(done?.complete == true, "s2 completes")
            check(done?.request != nil && done?.request == ScanFixtures.request(psbt), "s2: the request of the vectors")
        }

        section("session (WP7 rules): 200 rounds of add → close → new session → 2 parts, no error")
        do {
            let engine = FakeScanEngine()
            engine.realistic = true
            let answers = ScanFixtures.scanAnswers(psbt)
            engine.answer = { f in
                guard let a = answers[f] else { throw BILPublicSignerFailure.malformedResponse }
                return a
            }
            let s = makeSession(engine)
            var errors = 0
            var completed = 0
            for _ in 0..<200 {
                do {
                    _ = try await s.add(first)
                    s.close()
                    _ = try await s.add(first)
                    if try await s.add(second).complete { completed += 1 }
                } catch {
                    errors += 1
                    s.close()
                }
            }
            same(errors, 0, "no error in 200 rounds")
            same(completed, 200, "every round completed")
            check(await eventually { engine.calls.filter { $0 == "closeScan" }.count == 200 }, "every deferred close ran")
            same(engine.activeSessionId, nil, "no engine session left")
        }

        section("session: close while a call is in flight drops its result")
        do {
            let frames = ScanFixtures.scanFrames("T5-scan-bbqr-H")
            let engine = FakeScanEngine()
            engine.answer = { _ in FakeScanEngine.progress(0.2) }
            let latch = TestLatch()
            engine.latch = latch
            let s = makeSession(engine)
            let call = Task { @MainActor in try await s.add(frames[0]) }
            check(await eventually { engine.waiting == 1 }, "in flight")
            _ = try? await s.add(frames[1])
            s.close()
            latch.release()
            let r = try? await call.value
            same(r, .empty, "the late result is dropped")
            check(!s.isActive, "closed")
            same(engine.handles.first?.frames ?? [], [frames[0]], "the queued frame never ran")
        }

        section("session: TronLink — owner capture completes without any engine call")
        do {
            let engine = FakeScanEngine()
            let s = makeSession(engine)
            let done = try? await s.add(V.V1_REQUEST)
            check(done?.complete == true, "complete")
            same(done?.progress, 1, "progress 1")
            same(done?.parts, 1, "1 part")
            check(done?.request != nil && done?.request == ScanFixtures.vectorRequest("O-TL-V1-ownership-ios"), "the engine-native request")
            same(done?.transportType ?? "", "tronlink", "transport tronlink")
            same(done?.chain, .tron, "chain tron")
            same(done?.request?.obj("transaction")?.str("raw_data_hex") ?? "", "5a18221654726f6e4c696e6b437573746f6d436f6e7472616374", "raw")
            same(engine.calls, [], "no engine call, no scan context")
            check(!s.isActive, "ended")
        }

        section("session: TronLink parts (any order, repeats) complete through the collector")
        do {
            let engine = FakeScanEngine()
            let s = makeSession(engine)
            let joined = Array((V.V3_ENTRY + "&&&").utf16)
            let size = 100
            let total = (joined.count + size - 1) / size
            let parts: [String] = (1...total).map { i in
                var o = BILJSONObject()
                if i == 1 || i == total { o.set("address", .string(V.TRON_0)) }
                o.set("cN", .int(i))
                o.set("hexList", .array([.string(String(decoding: joined[((i - 1) * size)..<min(i * size, joined.count)], as: UTF16.self))]))
                o.set("tN", .int(total))
                o.set("type", .int(i == total ? 1 : 0))
                return BILStrictJSON.serialize(o)
            }
            same(parts.count, 3, "3 parts")
            let p1 = try? await s.add(parts[2])
            check(p1?.complete == false, "partial")
            same(p1?.parts, 1, "1 part")
            check(abs((p1?.progress ?? 0) - 1.0 / 3.0) < 0.0001, "progress 1/3")
            check(s.isActive, "active")
            same(try? await s.add(parts[2]), p1, "repeat")
            let p2 = try? await s.add(parts[0])
            same(p2?.parts, 2, "2 parts")
            let done = try? await s.add(parts[1])
            check(done?.complete == true, "complete")
            same(done?.parts, 3, "3 parts")
            same(done?.request?.obj("transaction")?.str("raw_data_hex") ?? "", String(V.V3_ENTRY.dropFirst(6)), "raw of the joined entry")
            let bean = String(decoding: BILPublicHex.decode(done?.request?.obj("transport")?.str("payloadBytes") ?? "") ?? [], as: UTF8.self)
            same(bean, #"{"address":"\#(V.TRON_0)","type":1,"hexList":["\#(V.V3_ENTRY)"]}"#, "payloadBytes = the reassembled bean")
            same(done?.request?.obj("transport")?.int("tronlinkType"), 1, "tronlinkType")
            same(engine.calls, [], "no engine call")
            check(!s.isActive, "ended")
        }

        section("session: TronLink refusals end the session with their own text and arguments")
        do {
            let engine = FakeScanEngine()
            let s = makeSession(engine)
            let blind = await expectScanError("101") {
                _ = try await s.add(#"{"address":"\#(V.TRON_0)","type":101,"hexList":["\#(String(repeating: "ab", count: 32))"]}"#)
            }
            same(blind?.reason, .unsupported, "unsupported")
            same(blind?.messageKey ?? "", "PublicProtocol.err.tronlinkBlindHash", "blind hash text")
            same(blind?.code ?? "", "TRONLINK_BLIND_HASH", "code")
            same(blind?.endsSession, true, "ends")
            same(blind?.kind, .tronLinkRequest, "kind")
            let typed = await expectScanError("150") { _ = try await s.add(#"{"address":"\#(V.TRON_0)","type":150,"hexList":["hello"]}"#) }
            same(typed?.messageKey ?? "", "PublicProtocol.err.tronlinkType", "type text")
            same(typed?.args ?? [], [.int(150)], "type 150 argument")
            _ = pubLoadStrings(tables: ["PublicProtocol"])
            same(typed?.text ?? "", "Ownbit can't sign this TronLink request type (150) yet.", "shown with its number")
            BILStubStrings.reset()
            let integrity = await expectScanError("99 transfer") { _ = try await s.add(#"{"address":"\#(V.TRON_0)","type":99,"hexList":["\#(V.V3_ENTRY)"]}"#) }
            same(integrity?.reason, .malformed, "integrity is a malformed-kind refusal")
            same(integrity?.messageKey ?? "", "PublicProtocol.err.integrity", "integrity text")
            let noAddress = await expectScanError("no address") { _ = try await s.add(#"{"type":1,"hexList":["\#(V.V3_ENTRY)"]}"#) }
            same(noAddress?.messageKey ?? "", "PublicProtocol.err.qrMalformed", "no address → malformed")
            same(noAddress?.code ?? "", "MALFORMED", "code MALFORMED")
            let gateMalformed = await expectScanError("bad TronLink JSON") { _ = try await s.add(#"{"hexList":"x"}"#) }
            same(gateMalformed?.reason, .malformed, "gate malformed")
            same(gateMalformed?.endsSession, false, "gate malformed keeps a session")
            same(engine.calls, [], "no engine call")
            // A conflicting part (collector) ends the session as another request.
            let a1 = #"{"address":"\#(V.TRON_0)","cN":1,"hexList":["ab"],"tN":2,"type":0}"#
            let b1 = #"{"address":"\#(V.TRON_0)","cN":1,"hexList":["cd"],"tN":2,"type":0}"#
            _ = try? await s.add(a1)
            check(s.isActive, "a part started a session")
            let conflict = await expectScanError("conflict") { _ = try await s.add(b1) }
            same(conflict?.reason, .otherRequest, "collector conflict")
            same(conflict?.messageKey ?? "", "PublicProtocol.scan.otherRequest", "text")
            same(conflict?.code ?? "", "OTHER_REQUEST", "code")
            same(conflict?.endsSession, true, "ends")
            check(!s.isActive, "reset")
            // Another part count (gate) ends it too.
            _ = try? await s.add(a1)
            let otherCount = await expectScanError("tN change") {
                _ = try await s.add(#"{"address":"\#(V.TRON_0)","cN":2,"hexList":["ab"],"tN":3,"type":0}"#)
            }
            same(otherCount?.reason, .otherRequest, "tN change")
            check(!s.isActive, "reset")
            // A new session after a refusal starts a new collector (no stale pieces).
            _ = try? await s.add(a1)
            let restart = await expectScanError("ab is not a transaction") {
                _ = try await s.add(#"{"address":"\#(V.TRON_0)","cN":2,"hexList":["&&&"],"tN":2,"type":1}"#)
            }
            same(restart?.reason, .malformed, "one byte is not a Transaction, type 1 ≤ 99 → malformed")
            same(restart?.messageKey ?? "", "PublicProtocol.err.qrMalformed", "malformed text")
            same(restart?.code ?? "", "MALFORMED", "code MALFORMED")
            same(restart?.endsSession, true, "ends")
            same(restart?.kind, .tronLinkPart, "kind of the completing part")
            check(!s.isActive, "reset")
            let tooMany = await expectScanError("65 parts") { _ = try await s.add(#"{"cN":1,"hexList":["ab"],"tN":65,"type":0}"#) }
            same(tooMany?.reason, .tooLarge, "65 parts → too large at the gate")
            same(tooMany?.endsSession, false, "gate too large keeps the session")
            same(engine.calls, [], "still no engine call")
        }

        section("session: TokenPocket — every text refused, the running session untouched, no engine call")
        do {
            let tpTexts = V.tpRequestFrames + [V.tpRequest, V.TP_ANSWER_HEADER,
                                               "ethereum:signTransaction-version=1.0&protocol=TokenPocket&network=ethereum&chain_id=1&data={}",
                                               "bitcoin:signTransaction-version=1.0&protocol=TokenPocket&data={}",
                                               "solana:signTransaction-version=1.0&protocol=TokenPocket&data={}",
                                               "tron:signMessageV2-version=1.0&protocol=TokenPocket&data={}",
                                               "tp:multiFragment-version=2.0&protocol=TokenPocket&data={}",
                                               #"{"action":"coldWalletSign","signType":"tronSignTx","sign":"ab"}"#]
            // Idle scanner.
            let engine = FakeScanEngine()
            let s = makeSession(engine)
            for text in tpTexts {
                let e = await expectScanError("TP idle") { _ = try await s.add(text) }
                same(e?.reason, .unsupported, "unsupported")
                same(e?.kind, .tpUnsupported, "kind")
                same(e?.messageKey ?? "", "PublicProtocol.err.tpUnsupported", "tpUnsupported text")
                same(e?.code ?? "", "TP_UNSUPPORTED", "code")
                same(e?.endsSession, false, "never ends a session")
                same(e?.error, BILPublicSignerErrors.tpUnsupported, "the TokenPocket error")
                same(e?.args ?? [.int(1)], [], "no arguments")
                check(!s.isActive, "never starts a session")
                same(s.progress, .empty, "no progress")
            }
            same(engine.calls, [], "engine zero calls (idle)")
            // During an animated scan.
            let engine2 = FakeScanEngine()
            let s2 = makeSession(engine2)
            let answers = ScanFixtures.scanAnswers(psbt)
            engine2.answer = { f in
                guard let a = answers[f] else { throw BILPublicSignerFailure.malformedResponse }
                return a
            }
            let p1 = try? await s2.add(first)
            let callsBefore = engine2.calls
            for text in tpTexts {
                let e = await expectScanError("TP mid-session") { _ = try await s2.add(text) }
                same(e?.messageKey ?? "", "PublicProtocol.err.tpUnsupported", "mid-session text")
                same(e?.endsSession, false, "mid-session keeps the scan")
                check(s2.isActive, "session still active")
                same(s2.progress, p1 ?? .empty, "parts unchanged")
            }
            same(engine2.calls, callsBefore, "TokenPocket made no engine call mid-session")
            check((try? await s2.add(second))?.complete == true, "the animated scan still completes")
        }

        section("session: every completing vector scan replays through gate + session (engine answers by frame)")
        do {
            var replayed = 0
            for c in ScanFixtures.scanCases where c.steps.allSatisfy({ $0.ok }) && c.steps.last?.complete == true {
                let engine = FakeScanEngine()
                let answers = ScanFixtures.scanAnswers(c.id)
                engine.answer = { f in
                    guard let a = answers[f] else { throw BILPublicSignerFailure.malformedResponse }
                    return a
                }
                let s = makeSession(engine)
                var last: BILScanProgress?
                var failed = false
                var sent = [String]()
                var seen = Set<String>()
                for step in c.steps {
                    let key = BILScanText.hasPrefixIgnoringASCIICase(step.frame, "ur:") ? step.frame.uppercased() : step.frame
                    if seen.insert(key).inserted { sent.append(BILKotlinText.trim(step.frame)) }
                    do { last = try await s.add(step.frame) } catch { failed = true; break }
                    if last?.complete == true { break }
                }
                check(!failed, "\(c.id): no error")
                check(last?.complete == true, "\(c.id): completes")
                check(last?.request != nil && last?.request == c.steps.last?.result?.obj("request"), "\(c.id): the vector request")
                same(engine.handles.count, 1, "\(c.id): one engine session")
                same(engine.handles.first?.frames ?? [], sent, "\(c.id): the engine saw each distinct frame once, in order")
                check(!s.isActive, "\(c.id): session reset")
                replayed += 1
            }
            check(replayed >= 50, "replayed completing scans: \(replayed)")
            // The shuffled animated fixture with duplicates (O-QR-1).
            check(ScanFixtures.scanCases.contains { $0.id == "O-QR-1-animated-shuffled" }, "O-QR-1 present")
        }

        section("session: descriptions never carry content")
        do {
            let e = BILPublicScanError(reason: .unsupported, kind: .tpUnsupported, endsSession: false, code: "TP_UNSUPPORTED",
                                       error: BILPublicSignerErrors.tpUnsupported)
            same(e.description, "Public scan: unsupported TP_UNSUPPORTED", "scan error description")
            let p = BILScanProgress(complete: true, progress: 1, parts: 2, request: BILJSONObject([("chain", .string("tron")), ("address", .string(V.TRON_0))]))
            check(!p.description.contains(V.TRON_0) && !String(reflecting: p).contains(V.TRON_0), "progress description")
            let r = BILOtherWalletRequestError.otherRequest
            same(r.description, "Other wallet request refused: OTHER_REQUEST", "other wallet error description")
            let secret = "secret engine text"
            let withText = BILPublicSignError("PublicProtocol.err.tronlinkType", args: [.int(150)], code: "TRONLINK_TYPE", engineMessage: secret)
            let scanError = BILPublicScanError(reason: .unsupported, kind: .tronLinkRequest, endsSession: true, code: "TRONLINK_TYPE", error: withText)
            var dumped = ""
            dump(scanError, to: &dumped)
            check(!dumped.contains(secret) && !dumped.contains("150") && !dumped.contains("tronlinkType"), "scan error dump prints no content")
            check(Mirror(reflecting: scanError).children.isEmpty, "scan error: no mirror children")
            dumped = ""
            dump(BILOtherWalletRequestError(kind: .unsupported, error: withText), to: &dumped)
            check(!dumped.contains(secret) && !dumped.contains("150"), "other wallet error dump prints no content")
            dumped = ""
            dump(p, to: &dumped)
            check(!dumped.contains(V.TRON_0), "progress dump prints no request content")
        }
    }

    static func progressTests() {
        section("progress: fromEngine")
        func p(_ text: String) -> BILScanProgress? { return BILStrictJSON.parseObject(text).flatMap { try? BILScanProgress.fromEngine($0, parts: 3) } }
        same(p(#"{"complete":false,"progress":0.25}"#)?.progress, 0.25, "0.25")
        same(p(#"{"complete":false,"progress":0.25}"#)?.parts, 3, "parts from the gate")
        same(p(#"{"complete":false,"progress":1.5}"#)?.progress, 1, "clamped high")
        same(p(#"{"complete":false,"progress":-2}"#)?.progress, 0, "clamped low")
        same(p(#"{"complete":false,"progress":"0.5"}"#)?.progress, 0, "a string is not a progress")
        same(p(#"{"complete":false,"progress":true}"#)?.progress, 0, "a bool is not a progress")
        same(p(#"{"complete":false,"progress":null}"#)?.progress, 0, "null")
        same(p(#"{"complete":false}"#)?.progress, 0, "missing")
        same(p(#"{"complete":false,"progress":1e400}"#)?.progress, 1, "infinity clamped")
        same(p(#"{"complete":false,"progress":{}}"#)?.progress, 0, "an object")
        check(p(#"{"progress":0.5}"#) == nil, "complete missing")
        check(p(#"{"complete":"false"}"#) == nil, "complete not a bool")
        check(p(#"{"complete":true}"#) == nil, "complete without request")
        check(p(#"{"complete":true,"request":{"chain":"cosmos"}}"#) == nil, "unknown chain")
        check(p(#"{"complete":true,"request":{"chain":"TRON"}}"#) == nil, "chain is case-sensitive")
        let done = p(#"{"complete":true,"progress":0.2,"request":{"chain":"evm","transport":{"type":"eth-sign-request"}}}"#)
        same(done?.progress, 1, "complete → 1")
        same(done?.chain, .evm, "chain")
        same(done?.transportType ?? "", "eth-sign-request", "transport")
        same(BILScanProgress.empty.parts, 0, "empty")
        check(BILScanProgress.empty.chain == nil && BILScanProgress.empty.transportType == nil, "empty has no chain")
        do {
            _ = try BILScanProgress.fromEngine(BILJSONObject(), parts: 0)
            check(false, "throws")
        } catch let e as BILMalformedEngineResult {
            same(e.what, "scan.complete", "what")
        } catch {
            check(false, "error type")
        }
    }
}
