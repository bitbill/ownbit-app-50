//  BILPublicPairingQr.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Public protocol (coin-level pairing): one pairing export as the "Pair with other wallets" tab shows it — the QR frames
//  plus everything the verification card needs (first address, path, format + bytes, master fingerprint, payload view).
//  Built from the engine's `createPublicPairing` result (`fromEngine`) or, for the EVM address mode at Ownbit's current
//  index N (the engine's pairing exports EVM #0 only), by the pairing service from `derivePublicAddresses` in the same
//  text format (`addressOnly`). Port of Android core/publicsigner model/PublicPairingQr.kt (design §3.11, R2 §8.3).
//  Pure Foundation.
//

import Foundation

/// - `selection`: what was asked for (with the TRON index, the panel's stale-result key).
/// - `type`: the engine `type` (`crypto-account`, `crypto-hdkey`, `crypto-multi-accounts` or `address`).
/// - `frames`: QR frames (upper-case UR, one frame for every pairing export today; more than one → animated).
/// - `text`: what "Copy" copies (frames joined by "\n", or the address).
/// - `address`: first address of the export (`/0/0`, EVM / TRON #`addressIndex`, SOL preset; "" for BIP48).
/// - `path`: exported path (account origin for key exports, the address path for the address mode).
/// - `addressIndex`: the exported address index (EVM address mode: Ownbit's current #N; TRON: the stepper's #N; else 0).
/// - `masterFingerprint`: 8 lower-case hex characters (shown upper-case, `displayFingerprint`).
/// - `engineNote`: the engine's English note, technical details only (the panel shows its own localized notes).
/// - `payload`: the decoded payload view; nil when the engine sent none.
/// - `sameAsOwnbit`: the exported first address equals the address Ownbit stores for this wallet, verified by the
///   cross-check before the QR is shown ("Same as in Ownbit").
///
/// Equality is exact (UTF-16 / UTF-8 code units, design D-01), never Swift's canonical equivalence.
public struct BILPublicPairingQr: Equatable {
    public let selection: BILPairingSelection
    public let type: String
    public let frames: [String]
    public let text: String
    public let address: String
    public let path: String
    public let addressIndex: Int
    public let masterFingerprint: String
    public let engineNote: String?
    public let payload: BILPublicPayloadView?
    public let sameAsOwnbit: Bool

    /// A key node (BTC account xpub incl. BIP48, EVM hd-key, SOL multi-accounts): logs `xpubExported` when shown; an
    /// address-only QR logs `watchQRShown` (C-LOG-2).
    public var bearsKey: Bool {
        return selection.outputMode.bearsKey
    }

    public var isAnimated: Bool {
        return frames.count > 1
    }

    /// Master fingerprint as displayed (`73C5DA0A`).
    public var displayFingerprint: String {
        return masterFingerprint.uppercased()
    }

    /// The same export with the "Same as in Ownbit" mark set as given (the service decides it after the cross-check).
    public func with(sameAsOwnbit: Bool) -> BILPublicPairingQr {
        return BILPublicPairingQr(selection: selection, type: type, frames: frames, text: text, address: address, path: path,
                                  addressIndex: addressIndex, masterFingerprint: masterFingerprint, engineNote: engineNote,
                                  payload: payload, sameAsOwnbit: sameAsOwnbit)
    }

    // MARK: - Paths

    /// EVM / TRON account origins (engine `EVM_ORIGIN`, `TRON_ORIGIN`); an address export is `<origin>/0/<index>`.
    public static let evmOrigin = "m/44'/60'/0'", tronOrigin = "m/44'/195'/0'"

    /// The path of TRON address #`index` in Ownbit's TRON scheme (round 2, R2-5): #0 = `m/44'/195'/0'/0/0`, #N ≥ 1 =
    /// Ownbit's TRX path, the ETH key `m/44'/60'/0'/0/N` (engine `tronAddressPath(ownbit, N)`).
    public static func tronPath(_ index: Int) -> String {
        return index == 0 ? tronOrigin + "/0/0" : evmOrigin + "/0/" + String(index)
    }

    /// The path of EVM address #`index` (`m/44'/60'/0'/0/N`).
    public static func evmPath(_ index: Int) -> String {
        return evmOrigin + "/0/" + String(index)
    }

    // MARK: - Builders

    /// Reads an engine `createPublicPairing` result for `selection` (`fingerprint` = the index's `masterFingerprint`).
    /// Throws `BILMalformedEngineResult` when it has no frames, its mode / profile differs from `selection`, an EVM /
    /// TRON address export is not the address at `addressIndex` (TRON #N ≥ 1 in Ownbit's scheme, `tronPath`), the
    /// fingerprint is not 4 bytes of hex, `type` is missing, or `addressIndex` is not allowed for the selection (only
    /// EVM / TRON address exports carry an index other than 0). `sameAsOwnbit` is false (the service sets it).
    public static func fromEngine(_ raw: BILJSONObject, selection: BILPairingSelection, fingerprint: String,
                           addressIndex: Int) throws -> BILPublicPairingQr {
        let frames = (raw.strings("frames") ?? []).filter { !$0.isEmpty }
        try BILEngineJSON.ensure(!frames.isEmpty, "pairing.frames")
        try BILEngineJSON.ensure(same(raw.str("outputMode"), selection.outputMode.rawValue), "pairing.outputMode")
        let profile = raw.str("profile")
        switch selection.chain {
        case .bitcoin:
            try BILEngineJSON.ensure(same(profile, selection.bitcoinProfile.rawValue), "pairing.profile")
        case .solana:
            try BILEngineJSON.ensure(same(profile, selection.solanaProfile.rawValue), "pairing.profile")
        case .evm, .tron:
            if selection.outputMode == .address {
                let path = selection.chain == .evm ? evmPath(addressIndex) : tronPath(addressIndex)
                try BILEngineJSON.ensure(same(raw.str("path"), path), "pairing.path")
            }
        }
        try BILEngineJSON.ensure(BILEngineJSON.isHex(fingerprint, bytes: 4), "pairing.masterFingerprint")
        guard let type = raw.str("type") else { throw BILMalformedEngineResult(what: "pairing.type") }
        // Android's model init: only address exports carry an index (EVM: Ownbit's current #N; TRON: the stepper's #N).
        try BILEngineJSON.ensure(isAllowed(addressIndex: addressIndex, selection: selection), "pairing.addressIndex")
        return BILPublicPairingQr(selection: selection,
                                  type: type,
                                  frames: frames,
                                  text: raw.str("text") ?? frames.joined(separator: "\n"),
                                  address: raw.str("address") ?? "",
                                  path: raw.str("path") ?? "",
                                  addressIndex: addressIndex,
                                  masterFingerprint: fingerprint.lowercased(),
                                  engineNote: raw.str("note"),
                                  payload: BILPublicPayloadView.fromEngine(raw),
                                  sameAsOwnbit: false)
    }

    /// An address-only export rendered without `createPublicPairing` (the EVM address mode at Ownbit's index N): the
    /// shape of the engine's address mode — `type` "address", one frame that is the address as the engine wrote it (EIP-55,
    /// no `ethereum:` prefix), `text` = the address, payload = the address text (`payloadFormat` text, UTF-8 byte count,
    /// `qrType` "address"), no engine note. For N = 0 it equals the vector `T3-pairing-evm-standard-address`.
    /// Callers pass a non-empty one-line address, the address mode, and `path` = the address path of `addressIndex`
    /// (the pairing service checks them before calling; `isAddressOnlyValid`).
    public static func addressOnly(selection: BILPairingSelection, address: String, path: String, addressIndex: Int,
                            fingerprint: String) -> BILPublicPairingQr {
        return BILPublicPairingQr(selection: selection,
                                  type: "address",
                                  frames: [address],
                                  text: address,
                                  address: address,
                                  path: path,
                                  addressIndex: addressIndex,
                                  masterFingerprint: fingerprint.lowercased(),
                                  engineNote: nil,
                                  payload: BILPublicPayloadView.text(address, qrType: "address"),
                                  sameAsOwnbit: false)
    }

    /// Android `addressOnly`'s preconditions (`require`): the address mode, a non-empty address without a line break, the
    /// address path of `addressIndex` on EVM / TRON, an allowed index.
    public static func isAddressOnlyValid(selection: BILPairingSelection, address: String, path: String, addressIndex: Int) -> Bool {
        guard selection.outputMode == .address, !address.isEmpty, !address.utf16.contains(0x0A),
              isAllowed(addressIndex: addressIndex, selection: selection) else {
            return false
        }
        switch selection.chain {
        case .evm: return same(path, evmPath(addressIndex))
        case .tron: return same(path, tronPath(addressIndex))
        case .bitcoin, .solana: return true
        }
    }

    // MARK: - Equality (exact)

    public static func == (lhs: BILPublicPairingQr, rhs: BILPublicPairingQr) -> Bool {
        return lhs.selection == rhs.selection
            && BILJSONExact.equal(lhs.type, rhs.type)
            && lhs.frames.count == rhs.frames.count
            && zip(lhs.frames, rhs.frames).allSatisfy { BILJSONExact.equal($0, $1) }
            && BILJSONExact.equal(lhs.text, rhs.text)
            && BILJSONExact.equal(lhs.address, rhs.address)
            && BILJSONExact.equal(lhs.path, rhs.path)
            && lhs.addressIndex == rhs.addressIndex
            && BILJSONExact.equal(lhs.masterFingerprint, rhs.masterFingerprint)
            && same(lhs.engineNote, rhs.engineNote)
            && lhs.payload == rhs.payload
            && lhs.sameAsOwnbit == rhs.sameAsOwnbit
    }

    // MARK: - Private

    /// `addressIndex >= 0 && (addressIndex == 0 || (chain ∈ {EVM, TRON} && mode == address))` (Android model init).
    private static func isAllowed(addressIndex: Int, selection: BILPairingSelection) -> Bool {
        guard addressIndex >= 0 else { return false }
        if addressIndex == 0 { return true }
        return (selection.chain == .evm || selection.chain == .tron) && selection.outputMode == .address
    }

    /// Exact optional equality (Kotlin `==` on `String?`).
    private static func same(_ a: String?, _ b: String?) -> Bool {
        guard let a = a, let b = b else { return a == nil && b == nil }
        return BILJSONExact.equal(a, b)
    }
}

/// Descriptions never print frames, addresses or the fingerprint (C-KEY-5): only the selection and the shape.
extension BILPublicPairingQr: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        return "BILPublicPairingQr(" + selection.chain.rawValue + "/" + selection.outputMode.rawValue + ", frames: "
            + String(frames.count) + ", index: " + String(addressIndex) + ", same: " + (sameAsOwnbit ? "true" : "false") + ")"
    }

    public var debugDescription: String {
        return description
    }
}
