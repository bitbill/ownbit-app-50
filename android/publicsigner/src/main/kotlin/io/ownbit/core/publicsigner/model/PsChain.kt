// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.publicsigner.model

/**
 * A chain family of the public protocol (the engine's `chain` values; BitSigner `Chain`). Declaration order is the
 * chain picker's order (BTC, EVM, TRON, SOL). Only these four exist in v1.
 *
 * @property wire the engine value (`chain` in requests, plans, results and pairing calls).
 * @property brandName the name shown in the UI; brand / standard names are never translated.
 */
enum class PsChain(val wire: String, val brandName: String) {
    BITCOIN("bitcoin", "Bitcoin"),
    EVM("evm", "EVM"),
    TRON("tron", "TRON"),
    SOLANA("solana", "Solana"),
    ;

    companion object {
        /** The chain of an engine value; `null` for anything else (fail closed, never a default chain). */
        fun fromWire(wire: String?): PsChain? = entries.firstOrNull { it.wire == wire }
    }
}
