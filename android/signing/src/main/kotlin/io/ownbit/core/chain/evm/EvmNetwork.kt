// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.chain.evm

/**
 * The eight EVM networks of Ownbit 5.0 and the parameters signing needs (the app's enum also carries coin types and
 * server routes, which are not part of this repository).
 *
 * - Chain ids: iOS `ETHTransactionBuilder.swift` (`ETHEREUM_CHAINID` 1, `BSC_CHAINID` 56, `ETC_CHAINID` 61,
 *   `AVAX_CHAINID` 137 — "AVAX is now Polygon", `ARB_CHAINID` 42161, `OP_CHAINID` 10, `BASE_CHAINID` 8453,
 *   `HYPE_CHAINID` 999).
 * - ETC always signs with the legacy `buildEtc*` functions (iOS `ETCTransactionBuilder.build`) regardless of the
 *   transaction type, and has no tokens.
 *
 * @property chainId EIP-155 chain id.
 */
enum class EvmNetwork(val chainId: Long) {
    ETH(1),
    BSC(56),
    POLYGON(137),
    ARB(42_161),
    OP(10),
    BASE(8_453),
    HYPE(999),
    ETC(61),
    ;

    /** ETC signs with `buildEtcTxBySeedHex` / `buildEtcTransaction` (chain id 61 inside the bundle), never type 2. */
    val isEtc: Boolean get() = this == ETC

    companion object {
        /** The network with EIP-155 [chainId], `null` if Ownbit does not support it. */
        fun ofChainId(chainId: Long): EvmNetwork? = entries.firstOrNull { it.chainId == chainId }
    }
}
