// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.publicsigner.model

import kotlinx.serialization.json.JsonObject

/**
 * One pairing export as the panel shows it: the QR frames plus everything the verification card needs (first address,
 * path, format + bytes, master fingerprint, payload view). Built from the engine's `createPublicPairing` result
 * ([fromEngine]) or, for the EVM address mode at Ownbit's current index N (the engine exports index 0 only), by the
 * pairing service from `derivePublicAddresses` with the same text format ([addressOnly]).
 *
 * @property selection what was asked for (the stale-result key).
 * @property type the engine `type`: `crypto-account`, `crypto-hdkey`, `crypto-multi-accounts` or `address`.
 * @property frames QR frames (upper-case UR, 1 frame for every pairing export today; > 1 → animated).
 * @property text what "Copy" copies (frames joined by `\n`, or the address).
 * @property address first address of the export (`/0/0`, EVM / TRON #[addressIndex], SOL preset).
 * @property path exported path (account origin for key exports, the address path for address mode).
 * @property addressIndex the exported address index (EVM address mode: Ownbit's current #N; else 0).
 * @property masterFingerprint 8 lower-case hex chars of the wallet's master fingerprint (shown upper-case).
 * @property engineNote the engine's English note ("Public account key…", "Cosigner account key only…"), shown only in
 *   the technical details; the panel uses its own localized notes.
 * @property payload the decoded payload view, `null` when the engine sent none.
 * @property sameAsOwnbit the exported first address equals the address Ownbit stores for this wallet (verified by the
 *   cross-check before the QR is shown) — the "Same as in Ownbit" mark.
 */
data class PublicPairingQr(
    val selection: PairingSelection,
    val type: String,
    val frames: List<String>,
    val text: String,
    val address: String,
    val path: String,
    val addressIndex: Int,
    val masterFingerprint: String,
    val engineNote: String?,
    val payload: PublicPayloadView?,
    val sameAsOwnbit: Boolean,
) {
    init {
        require(frames.isNotEmpty()) { "A pairing QR has at least one frame" }
        require(addressIndex >= 0) { "Negative address index" }
        // Only address exports carry an index: EVM (Ownbit's current #N) and TRON (#N in Ownbit's TRON scheme, equal to
        // Ownbit's TRX #N). Key exports are account nodes.
        require(addressIndex == 0 || (selection.chain in INDEXED_CHAINS && selection.outputMode == PsOutputMode.ADDRESS)) {
            "Only EVM / TRON address exports have an index other than 0"
        }
    }

    val outputMode: PsOutputMode get() = selection.outputMode

    /** Logs `XPUB_EXPORTED` when shown (a key node), else `watchQRShown` (one address). */
    val bearsKey: Boolean get() = selection.bearsKey

    val isAnimated: Boolean get() = frames.size > 1

    /** Master fingerprint as displayed (`73C5DA0A`). */
    val displayFingerprint: String get() = masterFingerprint.uppercase()

    companion object {
        /** EVM / TRON account origins (engine `EVM_ORIGIN`, `TRON_ORIGIN`); an address export is `<origin>/0/<index>`. */
        private const val EVM_ORIGIN = "m/44'/60'/0'"
        private const val TRON_ORIGIN = "m/44'/195'/0'"

        private val INDEXED_CHAINS = setOf(PsChain.EVM, PsChain.TRON)

        /**
         * The path of TRON address #[index] in Ownbit's TRON scheme: #0 = `m/44'/195'/0'/0/0`, #N ≥ 1 =
         * Ownbit's TRX path, the ETH key `m/44'/60'/0'/0/N` (engine `tronAddressPath(ownbit, N)`).
         */
        fun tronPath(index: Int): String = if (index == 0) "$TRON_ORIGIN/0/0" else "$EVM_ORIGIN/0/$index"

        /**
         * Reads an engine `createPublicPairing` result. Fails with [MalformedEngineResultException] when it has no frames,
         * its mode / profile differs from [selection], or an EVM / TRON address export is not the address at
         * [addressIndex] (the engine must export exactly what was asked for; TRON #N ≥ 1 in Ownbit's scheme, [tronPath]).
         */
        fun fromEngine(
            raw: JsonObject,
            selection: PairingSelection,
            masterFingerprint: String,
            sameAsOwnbit: Boolean,
            addressIndex: Int = 0,
        ): PublicPairingQr {
            val frames = raw.strings("frames").orEmpty().filter { it.isNotEmpty() }
            ensureEngine(frames.isNotEmpty()) { "pairing.frames" }
            ensureEngine(raw.str("outputMode") == selection.outputMode.wire) { "pairing.outputMode" }
            val profile = raw.str("profile")
            when (selection.chain) {
                PsChain.BITCOIN -> ensureEngine(profile == selection.bitcoinProfile.wire) { "pairing.profile" }
                PsChain.SOLANA -> ensureEngine(profile == selection.solanaProfile.wire) { "pairing.profile" }
                PsChain.EVM, PsChain.TRON -> if (selection.outputMode == PsOutputMode.ADDRESS) {
                    val path = if (selection.chain == PsChain.EVM) "$EVM_ORIGIN/0/$addressIndex" else tronPath(addressIndex)
                    ensureEngine(raw.str("path") == path) { "pairing.path" }
                }
            }
            ensureEngine(isHex(masterFingerprint, 4)) { "pairing.masterFingerprint" }
            return PublicPairingQr(
                selection = selection,
                type = raw.str("type") ?: throw MalformedEngineResultException("pairing.type"),
                frames = frames,
                text = raw.str("text") ?: frames.joinToString("\n"),
                address = raw.str("address").orEmpty(),
                path = raw.str("path").orEmpty(),
                addressIndex = addressIndex,
                masterFingerprint = masterFingerprint.lowercase(),
                engineNote = raw.str("note"),
                payload = PublicPayloadView.fromEngine(raw),
                sameAsOwnbit = sameAsOwnbit,
            )
        }

        /**
         * An address-only export rendered without `createPublicPairing` (EVM address mode at Ownbit's index N): the same
         * shape as the engine's address mode — one frame that is the address, payload = the address text.
         */
        fun addressOnly(
            selection: PairingSelection,
            address: String,
            path: String,
            addressIndex: Int,
            masterFingerprint: String,
            sameAsOwnbit: Boolean,
        ): PublicPairingQr {
            require(selection.outputMode == PsOutputMode.ADDRESS) { "Address export needs the address mode" }
            require(address.isNotEmpty() && '\n' !in address) { "Invalid address" }
            when (selection.chain) {
                PsChain.EVM -> require(path == "$EVM_ORIGIN/0/$addressIndex") { "Path is not address #$addressIndex" }
                PsChain.TRON -> require(path == tronPath(addressIndex)) { "Path is not address #$addressIndex" }
                PsChain.BITCOIN, PsChain.SOLANA -> Unit
            }
            return PublicPairingQr(
                selection = selection,
                type = "address",
                frames = listOf(address),
                text = address,
                address = address,
                path = path,
                addressIndex = addressIndex,
                masterFingerprint = masterFingerprint.lowercase(),
                engineNote = null,
                payload = PublicPayloadView(
                    format = PublicPayloadView.Format.TEXT,
                    text = address,
                    byteCount = address.encodeToByteArray().size,
                    qrType = "address",
                ),
                sameAsOwnbit = sameAsOwnbit,
            )
        }
    }
}
