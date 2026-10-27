// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.chain.evm

/**
 * `signDatas.ethTxType` of an EVM transaction (iOS):
 *
 * - [EIP1559] (2) — default of every EVM send; signed by the ethers v5 bundle (`ethjs-ext-v2.js`).
 * - [LEGACY] (1) — forced by iOS for some flows (DeFi, balance management, multisig deploy); signed with the legacy
 *   `ethereumjs-lib-app.min.js` (EIP-155).
 * - [ABSENT] (0) — offline codes produced by old app versions have no field → legacy.
 *
 * Only exactly 2 selects the EIP-1559 bundle (iOS `if ethTxType == 2`). ETC always signs legacy.
 */
object EvmTxType {
    const val ABSENT: Int = 0
    const val LEGACY: Int = 1
    const val EIP1559: Int = 2

    /** iOS decision: `ethTxType == 2` → type-2 bundle, anything else → legacy bundle. ETC is always legacy. */
    fun usesEip1559(ethTxType: Int, network: EvmNetwork): Boolean = !network.isEtc && ethTxType == EIP1559
}
