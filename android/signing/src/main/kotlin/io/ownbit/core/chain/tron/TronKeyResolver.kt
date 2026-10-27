// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.chain.tron

import io.ownbit.core.jsengine.bridge.EthereumJsBridge
import io.ownbit.core.wallet.api.UnlockedSecrets

/**
 * The TRX private key of a wallet, exactly as iOS picks it (`TRXTransactionBuilder.build(txBuildDatas:)`,
 * `BILETHTXAcceleratorController.signMessageWithSeed` / `signWcTxJsonWithSeed`):
 * - private-key wallet → its stored key (`0x` stripped);
 * - HD wallet, address index 0 → `m/44'/195'/0'/0/0` (`seedHexToTrxPrivateKey`);
 * - HD wallet, index N > 0 → the ETH key `m/44'/60'/0'/0/N` (`TronWalletModel.useAddrOnIndexNo`).
 *
 * The returned hex is a secret: keep it local to the signing call, never log it.
 */
internal class TronKeyResolver(private val ethereum: EthereumJsBridge) {

    /** `null` when [secrets] hold neither a seed nor a 32-byte hex private key. */
    suspend fun privateKeyHex(secrets: UnlockedSecrets, indexNo: Int): String? {
        val seed = secrets.seedHex
        if (seed != null && seed.isNotEmpty()) {
            val seedHex = String(seed)
            return if (indexNo > 0) ethereum.getEthPrivateKeyHex(seedHex, indexNo) else ethereum.getTronPrivateKeyHex(seedHex)
        }
        val pk = secrets.privateKey ?: return null
        val hex = String(pk).trim().removePrefix("0x").removePrefix("0X")
        return hex.takeIf { it.length == 64 && it.all { c -> Character.digit(c, 16) >= 0 } }
    }
}
