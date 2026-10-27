// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.chain.tron

import java.math.BigInteger

/**
 * Pre-sign checks of TRON transactions built by someone else (the TronGrid / Tatum node through `preSendTx`, the
 * Ownbit backend for Stake 2.0, a dApp for WalletConnect). iOS signs these as they come; 5.0 additionally checks the
 * **decoded `raw_data_hex`** (what TronWeb actually signs, through `txID`) against what the user confirmed, so a
 * faulty or malicious node cannot swap the recipient / amount / token.
 *
 * Every function returns `null` when the transaction is acceptable, otherwise a short English reason (diagnostics,
 * not user-facing).
 */
object TronTransactionVerifier {

    /** TRC20 `transfer(address,uint256)` selector. */
    private const val TRANSFER_SELECTOR = "a9059cbb"

    /** TRC20 `approve(address,uint256)` selector. */
    private const val APPROVE_SELECTOR = "095ea7b3"

    /**
     * Unsigned transfer returned by `bridge.preSendTx` ("obtransaction:"): TRX (`assetType` 0) TransferContract,
     * TRC10 (1) TransferAssetContract, TRC20 (2) TriggerSmartContract `transfer(to, amount)` on [assetId], TRC20
     * approve (20) TriggerSmartContract `approve(to, amount)` on [assetId].
     * Also checks that the JS extended the expiration by 82,800 s (relative to the node's `timestamp`) and that a TRC20
     * `fee_limit` does not exceed the bundle default of 150 TRX.
     */
    fun verifyTransfer(
        tx: TronTransactionJson,
        from: String,
        to: String,
        amountMinor: BigInteger,
        assetType: Int,
        assetId: String,
    ): String? {
        val contract = singleContract(tx) ?: return integrityReason(tx)
        val raw = tx.raw ?: return "raw_data_hex missing"
        if (contract.ownerAddress != TronAddressCodec.toHex41(from)) return "owner mismatch"
        if (raw.timestamp > 0 && raw.expiration - raw.timestamp < TronRules.EXPIRATION_EXTENSION_MILLIS) {
            return "expiration not extended"
        }
        val toHex = TronAddressCodec.toHex41(to) ?: return "invalid recipient"
        return when (assetType) {
            TronRules.ASSET_TYPE_TRX -> when {
                contract.type != TronContractType.TRANSFER -> "not a TransferContract"
                contract.toAddress != toHex -> "recipient mismatch"
                contract.amount != amountMinor -> "amount mismatch"
                else -> null
            }
            TronRules.ASSET_TYPE_TRC10 -> when {
                contract.type != TronContractType.TRANSFER_ASSET -> "not a TransferAssetContract"
                contract.assetName != assetId -> "token id mismatch"
                contract.toAddress != toHex -> "recipient mismatch"
                contract.amount != amountMinor -> "amount mismatch"
                else -> null
            }
            TronRules.ASSET_TYPE_TRC20 -> when {
                contract.type != TronContractType.TRIGGER_SMART_CONTRACT -> "not a TriggerSmartContract"
                contract.contractAddress != TronAddressCodec.toHex41(assetId) -> "token contract mismatch"
                (contract.callValue ?: 0L) != 0L -> "unexpected call value"
                contract.callData != trc20TransferData(toHex, amountMinor) -> "transfer data mismatch"
                raw.feeLimit <= 0 || raw.feeLimit > TronRules.DEFAULT_FEE_LIMIT_SUN -> "unexpected fee limit"
                else -> null
            }
            // Approve check "revoke": approve(to, amount) on the contract [assetId] (amount 0 when revoking).
            TronRules.ASSET_TYPE_TRC20_APPROVE -> when {
                contract.type != TronContractType.TRIGGER_SMART_CONTRACT -> "not a TriggerSmartContract"
                contract.contractAddress != TronAddressCodec.toHex41(assetId) -> "token contract mismatch"
                (contract.callValue ?: 0L) != 0L -> "unexpected call value"
                contract.callData != trc20ApproveData(toHex, amountMinor) -> "approve data mismatch"
                raw.feeLimit <= 0 || raw.feeLimit > TronRules.DEFAULT_FEE_LIMIT_SUN -> "unexpected fee limit"
                else -> null
            }
            else -> "unsupported asset type"
        }
    }

    /**
     * Stake 2.0 transaction returned by `trx/getTxJsonForStakingV20` for [operation] (iOS `BILDelegationController`
     * `loadTransactionBuildConfigurationForTrx`). [amountSun] / [receiver] are what the user entered; the undelegate
     * amount is not compared (iOS passes the listed delegation balance and lets the server decide).
     */
    fun verifyStaking(
        tx: TronTransactionJson,
        owner: String,
        operation: TronStakingOperation,
        receiver: String,
        amountSun: Long,
        forEnergy: Boolean,
    ): String? {
        val contract = singleContract(tx) ?: return integrityReason(tx)
        if (contract.ownerAddress != TronAddressCodec.toHex41(owner)) return "owner mismatch"
        if (contract.type != operation.contractType) return "unexpected contract type"
        val resource = if (forEnergy) 1 else 0
        val amount = BigInteger.valueOf(amountSun)
        return when (operation) {
            TronStakingOperation.STAKE, TronStakingOperation.UNSTAKE -> when {
                contract.amount != amount -> "amount mismatch"
                contract.resource != resource -> "resource mismatch"
                else -> null
            }
            TronStakingOperation.WITHDRAW -> null
            TronStakingOperation.DELEGATE -> when {
                contract.amount != amount -> "amount mismatch"
                contract.resource != resource -> "resource mismatch"
                contract.toAddress != TronAddressCodec.toHex41(receiver) -> "receiver mismatch"
                else -> null
            }
            TronStakingOperation.UNDELEGATE -> when {
                contract.resource != resource -> "resource mismatch"
                contract.toAddress != TronAddressCodec.toHex41(receiver) -> "receiver mismatch"
                else -> null
            }
        }
    }

    /**
     * WalletConnect `tron_signTransaction`: consistent `txID`, decodable hex, every contract owned by [owner], and no
     * `AccountPermissionUpdateContract` in the **hex** (iOS only searches the JSON text, which a dApp controls).
     */
    fun verifyForWalletConnect(tx: TronTransactionJson, owner: String): String? {
        if (!tx.isTxIdConsistent) return "txID does not match raw_data_hex"
        val raw = tx.raw ?: return "raw_data_hex missing or invalid"
        if (raw.contracts.isEmpty()) return "no contract"
        val ownerHex = TronAddressCodec.toHex41(owner) ?: return "invalid owner"
        if (raw.contracts.any { it.type == TronContractType.ACCOUNT_PERMISSION_UPDATE }) return "permission update"
        if (raw.contracts.any { it.ownerAddress != ownerHex }) return "owner mismatch"
        if (tx.signatures.isNotEmpty()) return "already signed"
        return null
    }

    /** ABI data of TRC20 `approve(spenderHex41, amount)` as TronWeb encodes it. */
    fun trc20ApproveData(spenderHex41: String, amount: BigInteger): String {
        val spender20 = spenderHex41.removePrefix("41")
        return APPROVE_SELECTOR + spender20.padStart(64, '0') + amount.toString(16).padStart(64, '0')
    }

    /** ABI data of TRC20 `transfer(toHex41, amount)` as TronWeb encodes it. */
    fun trc20TransferData(toHex41: String, amount: BigInteger): String {
        val to20 = toHex41.removePrefix("41")
        return TRANSFER_SELECTOR + to20.padStart(64, '0') + amount.toString(16).padStart(64, '0')
    }

    private fun singleContract(tx: TronTransactionJson): TronContract? {
        if (!tx.isTxIdConsistent) return null
        return tx.raw?.contracts?.singleOrNull()
    }

    private fun integrityReason(tx: TronTransactionJson): String = when {
        !tx.isTxIdConsistent -> "txID does not match raw_data_hex"
        tx.raw == null -> "raw_data_hex missing or invalid"
        else -> "expected exactly one contract"
    }
}
