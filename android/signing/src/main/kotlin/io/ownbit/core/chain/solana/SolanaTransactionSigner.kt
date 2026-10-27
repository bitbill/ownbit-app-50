// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.chain.solana

import io.ownbit.core.jsengine.JsArgs
import io.ownbit.core.jsengine.JsBundle
import io.ownbit.core.jsengine.JsEngineManager
import io.ownbit.core.jsengine.JsEventSpec
import io.ownbit.core.jsengine.JsResultFormatException
import java.security.MessageDigest
import java.util.Base64

/**
 * Typed access to the SOL bundle's transfer functions (iOS `SolanaJSBridge.buildTransaction` /
 * `buildTokenTransaction`). The bundle's web3.js is patched: `sendAndConfirmTransaction` signs locally with the given
 * blockhash and `sendRawTransaction` hands the base64 wire transaction back on the `transaction` channel instead of
 * broadcasting (the app broadcasts it). No network is needed.
 *
 * Bundle quirk: web3.js remembers every signature of the page (`_blockhashInfo.transactionSignatures`) and loops
 * forever when the **identical** transaction is signed twice on the same page (same blockhash, amounts, recipient —
 * e.g. a retry). The page is therefore restarted before re-signing a transaction it already signed.
 */
class SolanaTransactionSigner(private val manager: JsEngineManager, initialProvider: String) {

    @Volatile
    private var provider: String = initialProvider.trim()

    private val signedOnPage = mutableSetOf<String>()

    /**
     * The RPC URL handed to the bundle (iOS `BILSettingManager.solanaProvider`): only used to construct the web3
     * `Connection` object; the patched bundle requests nothing while signing. Supplied by the host app — this
     * repository contains no RPC address.
     */
    val solanaProvider: String get() = provider

    /** Sets the provider; blank values are ignored. */
    fun setSolanaProvider(url: String) {
        val trimmed = url.trim()
        if (trimmed.isNotEmpty()) provider = trimmed
    }

    /**
     * `bridge.sendTransaction(provider, seedHex, to, lamports, fee, blockHash, lastValidBlockHeight)` → base64 signed
     * transaction. [computeUnitPrice] = microLamports per CU (`sol/getAccountInfoForSend.solFee`; 0 = none).
     */
    suspend fun signSolTransfer(
        seedHex: String,
        to: String,
        lamports: String,
        computeUnitPrice: Long,
        recentBlockHash: String,
        lastValidBlockHeight: Long,
    ): String = signOnce(
        "sendTransaction",
        JsArgs.of(provider, seedHex, to, lamports, computeUnitPrice, recentBlockHash, lastValidBlockHeight),
    )

    /**
     * `bridge.sendTokenTransaction(provider, seedHex, mint, token2022, to, amount, decimals, fee, blockHash, height,
     * shouldCreateTokenAccount)` → base64 signed transaction (`TransferChecked`, recipient ATA created first when
     * [createRecipientTokenAccount]).
     */
    suspend fun signTokenTransfer(
        seedHex: String,
        mint: String,
        token2022: Boolean,
        to: String,
        amount: String,
        decimals: Int,
        computeUnitPrice: Long,
        recentBlockHash: String,
        lastValidBlockHeight: Long,
        createRecipientTokenAccount: Boolean,
    ): String = signOnce(
        "sendTokenTransaction",
        JsArgs.of(
            provider, seedHex, mint, token2022, to, amount, decimals, computeUnitPrice, recentBlockHash,
            lastValidBlockHeight, createRecipientTokenAccount,
        ),
    )

    private suspend fun signOnce(function: String, args: kotlinx.serialization.json.JsonArray): String {
        // Fingerprint of the transaction parameters without the seed (argument 1): a false match only costs a reload.
        val publicArgs = kotlinx.serialization.json.JsonArray(args.filterIndexed { i, _ -> i != 1 })
        val digest = MessageDigest.getInstance("SHA-256").digest((function + publicArgs.toString()).toByteArray())
            .joinToString("") { "%02x".format(it) }
        synchronized(signedOnPage) {
            if (!signedOnPage.add(digest)) {
                signedOnPage.clear()
                signedOnPage.add(digest)
                manager.restart(JsBundle.SOL)
            }
        }
        val event = manager.engine(JsBundle.SOL).callForEvent("bridge.$function", args, JsEventSpec.of(CHANNEL_TRANSACTION))
        val payload = event.payload.trim().removePrefix("any:")
        if (payload.isEmpty() || runCatching { Base64.getDecoder().decode(payload) }.isFailure) {
            throw JsResultFormatException(JsBundle.SOL, function, "base64 transaction")
        }
        return payload
    }

    companion object {
        const val CHANNEL_TRANSACTION: String = "transaction"
    }
}
