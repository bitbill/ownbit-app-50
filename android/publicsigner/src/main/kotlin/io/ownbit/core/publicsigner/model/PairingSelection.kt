// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.publicsigner.model

/**
 * What the "Pair with other wallets" tab exports: the chain, its profile and the output mode. Always a combination the
 * engine accepts (`createPublicPairing`, `protocols.js`): the constructor refuses any other, and the `with…` copies
 * fall back to the chain's default mode when the old one no longer applies. A data class, so it is also the stale-result
 * key of the pairing panel (a result belongs to exactly one selection).
 *
 * Export policy that is *not* encoded here (it needs the wallet's data; `PairingExportPolicy`): TRON exports the
 * stepper's address #N in Ownbit's TRX scheme (#0 = `m/44'/195'/0'/0/0`, #N ≥ 1 = the ETH key `m/44'/60'/0'/0/N`,
 * TRON-encoded); the EVM address mode exports Ownbit's current ETH address #N.
 *
 * @property bitcoinProfile used when [chain] is [PsChain.BITCOIN] (kept, but ignored, on the other chains so that
 *   switching chains back restores it).
 * @property solanaProfile used when [chain] is [PsChain.SOLANA] (same rule).
 */
data class PairingSelection(
    val chain: PsChain,
    val bitcoinProfile: PsBitcoinProfile = PsBitcoinProfile.DEFAULT,
    val solanaProfile: PsSolanaProfile = PsSolanaProfile.DEFAULT,
    val outputMode: PsOutputMode = defaultMode(chain, bitcoinProfile),
) {
    init {
        require(outputMode in modesFor(chain, bitcoinProfile)) { "Unsupported pairing mode $outputMode for $chain" }
    }

    /** The engine `profile` parameter: BTC / SOL profile wire value, `null` for EVM and TRON (engine default). */
    val profileWire: String?
        get() = when (chain) {
            PsChain.BITCOIN -> bitcoinProfile.wire
            PsChain.SOLANA -> solanaProfile.wire
            PsChain.EVM, PsChain.TRON -> null
        }

    /** Output modes the user can pick for this selection, default first. */
    val availableModes: List<PsOutputMode> get() = modesFor(chain, bitcoinProfile)

    /** The QR carries a key node (logs `XPUB_EXPORTED`) rather than one address (`watchQRShown`). */
    val bearsKey: Boolean get() = outputMode.bearsKey

    /**
     * The exported addresses are not ones this Ownbit wallet type shows by default: the BIP48 cosigner profiles and the
     * Solana Trust / Legacy presets (always), plus BTC Taproot, which depends on the wallet (cold wallets never hold
     * it) and is therefore decided by the export policy, not here.
     */
    val outsideOwnbitPaths: Boolean
        get() = when (chain) {
            PsChain.BITCOIN -> bitcoinProfile.isMultisig
            PsChain.SOLANA -> !solanaProfile.matchesOwnbit
            PsChain.EVM, PsChain.TRON -> false
        }

    /** Same selection on [chain], with the chain's default mode when the current one does not apply there. */
    fun withChain(chain: PsChain): PairingSelection = copyNormalized(chain = chain)

    /** Same selection with [profile] (BTC); the mode falls back to the profile's default when needed. */
    fun withBitcoinProfile(profile: PsBitcoinProfile): PairingSelection = copyNormalized(bitcoinProfile = profile)

    fun withSolanaProfile(profile: PsSolanaProfile): PairingSelection = copyNormalized(solanaProfile = profile)

    /** Same selection with [mode] if allowed, else unchanged. */
    fun withOutputMode(mode: PsOutputMode): PairingSelection =
        if (mode in availableModes) copy(outputMode = mode) else this

    private fun copyNormalized(
        chain: PsChain = this.chain,
        bitcoinProfile: PsBitcoinProfile = this.bitcoinProfile,
        solanaProfile: PsSolanaProfile = this.solanaProfile,
    ): PairingSelection {
        val modes = modesFor(chain, bitcoinProfile)
        val mode = if (outputMode in modes) outputMode else modes.first()
        return PairingSelection(chain, bitcoinProfile, solanaProfile, mode)
    }

    companion object {
        /**
         * The selection the tab opens with (never remembered between visits): BTC Native SegWit, account xpub.
         * Per chain: BTC Native accountXpub, EVM wallet, TRON address, SOL Standard wallet.
         */
        val DEFAULT: PairingSelection = PairingSelection(PsChain.BITCOIN)

        /** The default selection of [chain]. */
        fun defaultFor(chain: PsChain): PairingSelection = PairingSelection(chain)

        /**
         * Modes the engine accepts, default first: BTC single-sig account xpub / address, BTC cosigner account xpub only,
         * EVM and SOL wallet / address, TRON address only.
         */
        fun modesFor(chain: PsChain, bitcoinProfile: PsBitcoinProfile = PsBitcoinProfile.DEFAULT): List<PsOutputMode> =
            when (chain) {
                PsChain.BITCOIN ->
                    if (bitcoinProfile.isMultisig) listOf(PsOutputMode.ACCOUNT_XPUB)
                    else listOf(PsOutputMode.ACCOUNT_XPUB, PsOutputMode.ADDRESS)
                PsChain.EVM, PsChain.SOLANA -> listOf(PsOutputMode.WALLET, PsOutputMode.ADDRESS)
                PsChain.TRON -> listOf(PsOutputMode.ADDRESS)
            }

        private fun defaultMode(chain: PsChain, bitcoinProfile: PsBitcoinProfile): PsOutputMode =
            modesFor(chain, bitcoinProfile).first()
    }
}
