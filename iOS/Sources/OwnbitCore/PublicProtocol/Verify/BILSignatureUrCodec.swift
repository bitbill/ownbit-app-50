//  BILSignatureUrCodec.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Public protocol (cold signer) — native decoding of the QR frames the engine produced and of the original request
//  CBOR (port of Android `PS:verify/SignatureUrCodec.kt`; R5 §3.8). Ownbit does not take the engine's word for what a
//  response QR carries: it decodes the frames itself and the verifier (WP13) checks them against the signing plan.
//
//  - BC-UR (BCR-2020-005) with **minimal** bytewords and the CRC-32 checksum; one single-part UR, or the pure fountain
//    parts `encodeWhole()` produces (`ur:<type>/<seq>-<count>/…`, `seq ≤ count`; mixed parts are refused).
//  - `eth-signature` / `sol-signature` / `tron-signature`: a CBOR map `{1: #6.37(request-id), 2: signature}` and
//    nothing else (C-RESP-2).
//  - A signed PSBT in the request's own transport: `crypto-psbt` / `psbt` UR, BBQr `H` / `2`, PSBT Base64 / hex text.
//  - The `*-sign-request` CBOR of `transport.payloadBytes` (pre-check).
//
//  Frame syntax is checked by hand-written scanners equivalent to Android's whole-input regexes (ASCII classes only).
//  Every failure is a `BILVerifyError` with a log-safe check name. Pure Foundation; nothing logged.
//

import Foundation

enum BILSignatureUrCodec {

    /// What `decodeSignRequest` reads from an original `*-sign-request` CBOR (Android `SignRequestCbor`): the signed
    /// bytes (key 2), the request id (key 1 when it is a tag — any tag number — around a byte string), and:
    /// EVM `dataType` = key 3, `chainId` = key 4; TRON `dataType` = key 3; Solana `signType` = key 6 — and, exactly as
    /// Android's single `dataType` field, `dataType` = key 6 for Solana too. Integers are Kotlin `Long`s (`.uint` or
    /// `.nint`); a key holding anything else reads nil.
    struct SignRequest: Equatable, CustomStringConvertible, CustomReflectable {
        let requestId: [UInt8]?
        let signData: [UInt8]
        let dataType: Int?
        let chainId: Int64?
        let signType: Int?

        var description: String {
            return "SignRequest(\(signData.count) bytes, dataType=\(dataType.map(String.init) ?? "nil"))"
        }

        /// No children: `dump` / reflection print the description only.
        var customMirror: Mirror { return Mirror(self, children: [:]) }
    }

    /// A decoded signature answer (C-RESP-2); `requestId` nil when the map has no key 1 (or key 1 is CBOR null).
    struct SignatureAnswer: Equatable, CustomStringConvertible, CustomReflectable {
        let type: String
        let requestId: [UInt8]?
        let signature: [UInt8]

        var description: String {
            return "SignatureAnswer(\(type), id=\(requestId?.count ?? 0) bytes, signature=\(signature.count) bytes)"
        }

        /// No children: `dump` / reflection print the description only.
        var customMirror: Mirror { return Mirror(self, children: [:]) }
    }

    /// UR types of the signature answers.
    static let signatureTypes: [String] = ["eth-signature", "sol-signature", "tron-signature"]

    /// Most frames of one decoded UR (engine `QR_LIMITS.frames`).
    static let maxFrames = 2_048

    /// Largest decoded payload (engine `QR_LIMITS.payloadBytes`).
    static let maxPayload = 131_072

    /// Decodes `frames` into one UR: one single-part frame, or the pure fountain parts of one message (any order,
    /// repeats allowed when identical). Returns the lower-case UR type and the CBOR bytes it carries.
    static func decodeUr(_ frames: [String]) throws -> (type: String, cbor: [UInt8]) {
        try BILVerifyError.check(!frames.isEmpty && frames.count <= maxFrames, "ur.frames")
        let parsed = try frames.map(parseUrFrame)
        let type = parsed[0].type
        try BILVerifyError.check(parsed.allSatisfy { $0.type == type }, "ur.type")
        guard let count = parsed[0].count else {
            try BILVerifyError.check(parsed.count == 1, "ur.single")
            let body = try bytewords(parsed[0].body)
            try BILVerifyError.check(!body.isEmpty && body.count <= maxPayload, "ur.size")
            return (type, body)
        }
        try BILVerifyError.check(parsed.allSatisfy { $0.seq != nil }, "ur.parts")
        try BILVerifyError.check(parsed.allSatisfy { $0.count == count }, "ur.count")
        var fragments = [[UInt8]?](repeating: nil, count: count)
        var messageLength: Int64 = -1
        var checksum: Int64 = -1
        for part in parsed {
            let seq = part.seq ?? 0
            try BILVerifyError.check(seq >= 1 && seq <= count, "ur.seq")
            guard let cbor = try BILStrictCbor.decode(bytewords(part.body)).arrayValue else { throw BILVerifyError("ur.part") }
            try BILVerifyError.check(cbor.count == 5, "ur.part")
            let partSeq = cbor[0].integerValue
            let partCount = cbor[1].integerValue
            let length = cbor[2].integerValue
            let sum = cbor[3].integerValue
            let fragment = cbor[4].bytesValue
            try BILVerifyError.check(partSeq == Int64(seq) && partCount == Int64(count), "ur.part.seq")
            guard let len = length, len >= 1, len <= Int64(maxPayload), let crc = sum, crc >= 0, crc <= 0xFFFF_FFFF else {
                throw BILVerifyError("ur.part.meta")
            }
            guard let piece = fragment, !piece.isEmpty else { throw BILVerifyError("ur.part.fragment") }
            try BILVerifyError.check(messageLength == -1 || (messageLength == len && checksum == crc), "ur.part.mixed")
            messageLength = len
            checksum = crc
            if let previous = fragments[seq - 1] {
                try BILVerifyError.check(previous == piece, "ur.part.conflict")
            }
            fragments[seq - 1] = piece
        }
        var pieces = [[UInt8]]()
        pieces.reserveCapacity(count)
        for f in fragments {
            guard let piece = f else { throw BILVerifyError("ur.incomplete") }
            pieces.append(piece)
        }
        let fragmentLength = pieces[0].count
        try BILVerifyError.check(pieces.allSatisfy { $0.count == fragmentLength }, "ur.part.size")
        try BILVerifyError.check((messageLength + Int64(fragmentLength) - 1) / Int64(fragmentLength) == Int64(count), "ur.part.size")
        var joined = [UInt8]()
        joined.reserveCapacity(count * fragmentLength)
        for piece in pieces { joined.append(contentsOf: piece) }
        let message = Array(joined[0..<Int(messageLength)])
        try BILVerifyError.check(Int64(BILPublicHash.crc32(message)) == checksum, "ur.checksum")
        return (type, message)
    }

    /// The `signData` (key 2) of an original `*-sign-request` CBOR (`payload` = `transport.payloadBytes`) with the
    /// other keys the native checks read. Every key must be an integer in 1…7 (`eth-sign-request`) or 1…6 (others).
    static func decodeSignRequest(type: String, payload: [UInt8]) throws -> SignRequest {
        let root = try BILStrictCbor.decode(payload)
        guard let pairs = root.mapPairs else { throw BILVerifyError("request.map") }
        let isEth = BILVerifyText.same(type, "eth-sign-request")
        let maxKey: UInt64 = isEth ? 7 : 6
        try BILVerifyError.check(pairs.allSatisfy { pair in
            if case .uint(let k) = pair.0 { return k >= 1 && k <= maxKey }
            return false
        }, "request.keys")
        guard let signData = root.get(2)?.bytesValue else { throw BILVerifyError("request.signData") }
        var requestId: [UInt8]? = nil
        if case .tag(_, let value)? = root.get(1) { requestId = value.bytesValue }
        let key3 = root.get(3)?.integerValue.map { Int($0) }
        if isEth {
            return SignRequest(requestId: requestId, signData: signData, dataType: key3, chainId: root.get(4)?.integerValue, signType: nil)
        }
        if BILVerifyText.same(type, "tron-sign-request") {
            return SignRequest(requestId: requestId, signData: signData, dataType: key3, chainId: nil, signType: nil)
        }
        if BILVerifyText.same(type, "sol-sign-request") {
            let key6 = root.get(6)?.integerValue.map { Int($0) }
            return SignRequest(requestId: requestId, signData: signData, dataType: key6, chainId: nil, signType: key6)
        }
        throw BILVerifyError("request.type")
    }

    /// The signature answer in `frames` (C-RESP-2): a UR of a `signatureTypes` type whose CBOR is a map with key 2 (a
    /// byte string) and optionally key 1 (`#6.37` byte string, the request id) — nothing else.
    static func decodeSignature(_ frames: [String]) throws -> SignatureAnswer {
        let ur = try decodeUr(frames)
        try BILVerifyError.check(signatureTypes.contains { BILVerifyText.same($0, ur.type) }, "signature.type")
        let root = try BILStrictCbor.decode(ur.cbor)
        guard let pairs = root.mapPairs else { throw BILVerifyError("signature.map") }
        try BILVerifyError.check(pairs.allSatisfy { pair in
            if case .uint(let k) = pair.0 { return k == 1 || k == 2 }
            return false
        }, "signature.keys")
        guard let signature = root.get(2)?.bytesValue else { throw BILVerifyError("signature.value") }
        var requestId: [UInt8]? = nil
        if let tagged = root.get(1) {
            guard case .tag(let tag, let value) = tagged else { throw BILVerifyError("signature.requestId") }
            try BILVerifyError.check(tag == uuidTag, "signature.requestId.tag")
            guard let id = value.bytesValue else { throw BILVerifyError("signature.requestId") }
            requestId = id
        }
        return SignatureAnswer(type: ur.type, requestId: requestId, signature: signature)
    }

    /// The PSBT bytes a signed-PSBT answer of transport `type` carries: `crypto-psbt` / `psbt` (UR holding a CBOR byte
    /// string), `bbqr-psbt` (BBQr `H` hex or `2` Base32, every part once), `psbt-base64` / `psbt-hex` (one text frame).
    /// The result is 5…131 072 bytes and starts with the PSBT magic.
    static func decodePsbt(type: String, frames: [String]) throws -> [UInt8] {
        let bytes: [UInt8]
        if BILVerifyText.same(type, "crypto-psbt") || BILVerifyText.same(type, "psbt") {
            let ur = try decodeUr(frames)
            try BILVerifyError.check(BILVerifyText.same(ur.type, type), "psbt.urType")
            guard let psbt = try BILStrictCbor.decode(ur.cbor).bytesValue else { throw BILVerifyError("psbt.cbor") }
            bytes = psbt
        } else if BILVerifyText.same(type, "bbqr-psbt") {
            bytes = try decodeBbqr(frames)
        } else if BILVerifyText.same(type, "psbt-base64") {
            try BILVerifyError.check(frames.count == 1, "psbt.frames")
            bytes = try base64(frames[0])
        } else if BILVerifyText.same(type, "psbt-hex") {
            try BILVerifyError.check(frames.count == 1, "psbt.frames")
            guard let hex = BILPublicHex.decode(frames[0]) else { throw BILVerifyError("psbt.hex") }
            bytes = hex
        } else {
            throw BILVerifyError("psbt.type")
        }
        try BILVerifyError.check(bytes.count >= 5 && bytes.count <= maxPayload && Array(bytes[0..<5]) == psbtMagic, "psbt.magic")
        return bytes
    }

    /// Minimal bytewords (two letters per byte — first and last letter of the word — any case) → bytes, after
    /// checking and removing the big-endian CRC-32 (IEEE) of the last 4 bytes. Even length ≥ 10 (UTF-16 units).
    static func bytewords(_ text: String) throws -> [UInt8] {
        let length = text.utf16.count
        try BILVerifyError.check(length % 2 == 0 && length >= 10, "bytewords.length")
        let lower = Array(text.lowercased().utf16)       // Kotlin `lowercase(Locale.ROOT)`
        var out = [UInt8]()
        out.reserveCapacity(lower.count / 2)
        var i = 0
        while i + 1 < lower.count {
            let first = lower[i]
            let last = lower[i + 1]
            try BILVerifyError.check(first >= 0x61 && first <= 0x7A && last >= 0x61 && last <= 0x7A, "bytewords.char")
            let value = minimalLookup[Int(first - 0x61) * 26 + Int(last - 0x61)]
            try BILVerifyError.check(value >= 0, "bytewords.word")
            out.append(UInt8(value))
            i += 2
        }
        try BILVerifyError.check(out.count >= 4, "bytewords.length")
        let body = Array(out[0..<(out.count - 4)])
        let n = out.count
        let sum = UInt32(out[n - 4]) << 24 | UInt32(out[n - 3]) << 16 | UInt32(out[n - 2]) << 8 | UInt32(out[n - 1])
        try BILVerifyError.check(BILPublicHash.crc32(body) == sum, "bytewords.checksum")
        return body
    }

    /// RFC 4648 Base32 without padding (BBQr `2`): `A–Z`, `2–7` only; the leftover bits must be fewer than 5 and zero.
    static func base32(_ s: String) throws -> [UInt8] {
        var out = [UInt8]()
        out.reserveCapacity(s.utf16.count * 5 / 8)
        var buffer: UInt64 = 0
        var bits = 0
        for c in s.utf16 {
            let v: UInt64
            switch c {
            case 0x41...0x5A: v = UInt64(c - 0x41)
            case 0x32...0x37: v = UInt64(c - 0x32 + 26)
            default: throw BILVerifyError("base32.char")
            }
            buffer = (buffer << 5) | v
            bits += 5
            if bits >= 8 {
                bits -= 8
                out.append(UInt8(truncatingIfNeeded: buffer >> UInt64(bits)))
            }
        }
        try BILVerifyError.check(bits < 5 && (buffer & ((UInt64(1) << UInt64(bits)) - 1)) == 0, "base32.padding")
        return out
    }

    /// Strict padded Base64 (the engine's `b64`, Android `SignatureUrCodec.base64`): `BILBase64Strict.decode` or
    /// `BILVerifyError("base64")` (`"cHNidP8"` is refused).
    static func base64(_ s: String) throws -> [UInt8] {
        guard let bytes = BILBase64Strict.decode(s) else { throw BILVerifyError("base64") }
        return bytes
    }

    // MARK: - UR frames

    private struct UrFrame {
        let type: String
        let seq: Int?
        let count: Int?
        let body: String
    }

    /// Android `UR_FRAME.matchEntire(frame.trim())` with
    /// `^[Uu][Rr]:([A-Za-z0-9-]{1,64})/(?:([0-9]{1,10})-([0-9]{1,10})/)?([A-Za-z]+)$`; the type is lower-cased;
    /// `1 ≤ seq ≤ 0xFFFFFFFF`, `1 ≤ count ≤ 2048` and only pure fragments (`seq ≤ count`).
    private static func parseUrFrame(_ frame: String) throws -> UrFrame {
        let u = Array(BILKotlinText.trim(frame).utf16)
        guard u.count >= 6,
              u[0] == 0x55 || u[0] == 0x75, u[1] == 0x52 || u[1] == 0x72, u[2] == 0x3A else { throw BILVerifyError("ur.frame") }
        var i = 3
        let typeStart = i
        while i < u.count && isTypeUnit(u[i]) { i += 1 }
        let typeLength = i - typeStart
        guard typeLength >= 1, typeLength <= 64, i < u.count, u[i] == 0x2F else { throw BILVerifyError("ur.frame") }
        let type = String(decoding: u[typeStart..<i].map { foldASCII($0) }, as: UTF16.self)
        i += 1
        var seqDigits: ArraySlice<UInt16>? = nil
        var countDigits: ArraySlice<UInt16>? = nil
        if i < u.count && isDigitUnit(u[i]) {
            let seqStart = i
            while i < u.count && isDigitUnit(u[i]) { i += 1 }
            guard i - seqStart <= 10, i < u.count, u[i] == 0x2D else { throw BILVerifyError("ur.frame") }
            seqDigits = u[seqStart..<i]
            i += 1
            let countStart = i
            while i < u.count && isDigitUnit(u[i]) { i += 1 }
            guard i - countStart >= 1, i - countStart <= 10, i < u.count, u[i] == 0x2F else { throw BILVerifyError("ur.frame") }
            countDigits = u[countStart..<i]
            i += 1
        }
        let bodyStart = i
        while i < u.count && isLetterUnit(u[i]) { i += 1 }
        guard i == u.count, i > bodyStart else { throw BILVerifyError("ur.frame") }
        let body = String(decoding: u[bodyStart..<i], as: UTF16.self)
        guard let s = seqDigits, let c = countDigits else { return UrFrame(type: type, seq: nil, count: nil, body: body) }
        let seq = decimal(s)
        let count = decimal(c)
        try BILVerifyError.check(seq >= 1 && seq <= 0xFFFF_FFFF && count >= 1 && count <= Int64(maxFrames), "ur.sequence")
        // Only the pure fragments (seq ≤ count) are accepted: they are what the engine's encodeWhole() emits.
        try BILVerifyError.check(seq <= count, "ur.mixedPart")
        return UrFrame(type: type, seq: Int(seq), count: Int(count), body: body)
    }

    // MARK: - BBQr

    /// Android `decodeBbqr`: every frame matches `^B\$([H2])P([0-9A-Z]{2})([0-9A-Z]{2})([0-9A-Z]+)$` (not trimmed);
    /// one header (the first 6 characters) for all frames; total (base 36) 1…1295, index < total; a repeated index
    /// carries the same data; every index present; joined in index order; `H` = upper-case hex, `2` = Base32.
    private static func decodeBbqr(_ frames: [String]) throws -> [UInt8] {
        try BILVerifyError.check(!frames.isEmpty, "bbqr.frames")
        var header: [UInt16]? = nil
        var total = 0
        var parts = [Int: [UInt16]]()
        for frame in frames {
            let u = Array(frame.utf16)
            guard u.count >= 9, u[0] == 0x42, u[1] == 0x24, u[2] == 0x48 || u[2] == 0x32, u[3] == 0x50,
                  u[4...].allSatisfy(isBbqrUnit) else { throw BILVerifyError("bbqr.frame") }
            let h = Array(u[0..<6])
            try BILVerifyError.check(header == nil || header! == h, "bbqr.header")
            header = h
            total = base36(u[4], u[5])
            let index = base36(u[6], u[7])
            try BILVerifyError.check(total >= 1 && total <= 1295 && index < total, "bbqr.index")
            let data = Array(u[8...])
            if let previous = parts[index] {
                try BILVerifyError.check(previous == data, "bbqr.conflict")
            }
            parts[index] = data
        }
        try BILVerifyError.check(parts.count == total, "bbqr.incomplete")
        var joined = [UInt16]()
        for i in 0..<total {
            guard let part = parts[i] else { throw BILVerifyError("bbqr.incomplete") }
            joined.append(contentsOf: part)
        }
        let text = String(decoding: joined, as: UTF16.self)
        if header?[2] == 0x48 {
            guard let hex = BILPublicHex.decode(text) else { throw BILVerifyError("bbqr.hex") }
            return hex
        }
        return try base32(text)
    }

    // MARK: - Tables and character classes

    private static let uuidTag: UInt64 = 37
    private static let psbtMagic: [UInt8] = [0x70, 0x73, 0x62, 0x74, 0xFF]

    /// The 256 bytewords (BCR-2020-012), four letters each; a minimal byteword is its first and last letter, which are
    /// unique (the same table as `@ngraveio/bc-ur` `bytewords.js` used by the engine).
    private static let bytewordsTable: String =
        "ableacidalsoapexaquaarchatomauntawayaxisbackbaldbarnbeltbetabiasbluebodybragbrewbulbbuzzcalmcashcatschefcity" +
        "clawcodecolacookcostcruxcurlcuspcyandarkdatadaysdelidicedietdoordowndrawdropdrumdulldutyeacheasyechoedge" +
        "epicevenexamexiteyesfactfairfernfigsfilmfishfizzflapflewfluxfoxyfreefrogfuelfundgalagamegeargemsgiftgirl" +
        "glowgoodgraygrimgurugushgyrohalfhanghardhawkheathelphighhillholyhopehornhutsicedideaidleinchinkyintoiris" +
        "ironitemjadejazzjoinjoltjowljudojugsjumpjunkjurykeepkenokeptkeyskickkilnkingkitekiwiknoblamblavalazyleaf" +
        "legsliarlimplionlistlogoloudloveluaulucklungmainmanymathmazememomenumeowmildmintmissmonknailnavyneednews" +
        "nextnoonnotenumbobeyoboeomitonyxopenovalowlspaidpartpeckplaypluspoempoolposepuffpumapurrquadquizraceramp" +
        "realredorichroadrockroofrubyruinrunsrustsafesagascarsetssilkskewslotsoapsolosongstubsurfswantacotasktaxi" +
        "tenttiedtimetinytoiltombtoystriptunatwinuglyundouniturgeuservastveryvetovialvibeviewvisavoidvowswallwand" +
        "warmwaspwavewaxywebswhatwhenwhizwolfworkyankyawnyellyogayurtzapszerozestzinczonezoom"

    /// (first − 'a') · 26 + (last − 'a') → byte, −1 for no word. The table is checked by the harness (256 words,
    /// 1024 letters, no collision).
    private static let minimalLookup: [Int] = {
        var table = [Int](repeating: -1, count: 26 * 26)
        let letters = Array(bytewordsTable.utf8)
        guard letters.count == 256 * 4 else { return table }
        for i in 0..<256 {
            let slot = Int(letters[i * 4] - 0x61) * 26 + Int(letters[i * 4 + 3] - 0x61)
            if table[slot] != -1 { return [Int](repeating: -1, count: 26 * 26) }   // collision: refuse everything
            table[slot] = i
        }
        return table
    }()

    private static func isTypeUnit(_ c: UInt16) -> Bool {
        return isLetterUnit(c) || isDigitUnit(c) || c == 0x2D
    }

    private static func isLetterUnit(_ c: UInt16) -> Bool {
        return (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A)
    }

    private static func isDigitUnit(_ c: UInt16) -> Bool {
        return c >= 0x30 && c <= 0x39
    }

    private static func isBbqrUnit(_ c: UInt16) -> Bool {
        return (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x5A)
    }

    private static func foldASCII(_ c: UInt16) -> UInt16 {
        return (c >= 0x41 && c <= 0x5A) ? c + 0x20 : c
    }

    /// 1…10 ASCII digits → value (≤ 9 999 999 999, fits Int64).
    private static func decimal(_ digits: ArraySlice<UInt16>) -> Int64 {
        var v: Int64 = 0
        for d in digits { v = v * 10 + Int64(d - 0x30) }
        return v
    }

    /// Two characters of `[0-9A-Z]` → base-36 value (0…1295).
    private static func base36(_ a: UInt16, _ b: UInt16) -> Int {
        return digit36(a) * 36 + digit36(b)
    }

    private static func digit36(_ c: UInt16) -> Int {
        return c <= 0x39 ? Int(c - 0x30) : Int(c - 0x41) + 10
    }
}
