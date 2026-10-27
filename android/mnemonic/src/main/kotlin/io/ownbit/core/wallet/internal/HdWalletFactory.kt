// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.wallet.internal

import io.ownbit.core.common.log.Log
import io.ownbit.core.crypto.hash.Hashes
import io.ownbit.core.crypto.util.Secrets
import io.ownbit.core.crypto.util.wipe
import io.ownbit.core.jsengine.bridge.BitcoinAddressType
import io.ownbit.core.jsengine.bridge.BitcoinExtendedPublicKeys
import io.ownbit.core.jsengine.bridge.EthereumAccount
import io.ownbit.core.jsengine.bridge.TaprootXpubs
import io.ownbit.core.jsengine.bridge.TronAddress
import io.ownbit.core.wallet.imports.PassphraseAddressKind
import io.ownbit.core.wallet.imports.PassphraseCheck
import io.ownbit.core.wallet.imports.PassphraseCheckRow
import io.ownbit.core.wallet.secret.SecretSealer
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope

/**
 * Public key material an HD wallet gets at creation / import (iOS `WalletModel.resetProperties(m:pwd:)`): the six
 * BTC chain xpubs, BTC legacy and native-segwit address 0, ETH account 0, TRX index 0 and SOL. [seedHex] is secret.
 */
class HdMaterial(
    val seedHex: String,
    val btc: BitcoinExtendedPublicKeys,
    val legacy0: String,
    val native0: String,
    val eth: EthereumAccount,
    val trx: TronAddress,
    /** `null` when the SOL bundle failed — tolerated like iOS (only BTC / ETH / TRX failures roll back). */
    val sol: String?,
    /**
     * BIP86 Taproot chain xpubs (iOS `prepareTaprootKeys`): only for standard-path personal hot wallets (see
     * [HdWalletFactory.derive]); `null` otherwise or when the Taproot bundle failed (tolerated, the wallet is
     * created without Taproot — the receive page can still enable it with the password).
     */
    val taproot: TaprootXpubs? = null,
) {
    override fun toString(): String = "HdMaterial(<redacted>)"
}

/**
 * Key derivation and sealing for new HD wallets (hot, cold, multisig personal wallets; mnemonic imports). Port of the
 * key part of iOS `WalletModel.resetProperties(m:pwd:needSave:resetPwdOnly:)`. (In the app the same class also builds
 * the database rows and the server registration of the public keys, which are not part of this repository.)
 *
 * A new wallet is: [KeyDeriver.generateMnemonic] → [derive] (seed + public keys) → [seal] (OBV2 envelopes of the
 * mnemonic and the seed under the wallet password) + [sha256Hex] of the mnemonic / seed as the integrity hashes the
 * vault checks ([io.ownbit.core.wallet.secret.StoredWalletSecrets]).
 */
class HdWalletFactory(
    private val keys: KeyDeriver,
    private val sealer: SecretSealer,
) {

    /**
     * iOS `resetProperties`: `mnemonicToSeedHex` → `getXPublicKeysForAll(seed, seedTypePath)` +
     * `getPublicKeyAndAddress(seed, indexNo: 0)` + TRX `m/44'/195'/0'/0/0` + SOL. BTC, ETH or TRX failing throws
     * (the wallet is not created); SOL failing is tolerated. Only BTC uses the custom path. [passphrase] = the BIP39
     * passphrase of a passphrase import (`null` for every other wallet): the seed, and so every key, is
     * BIP39(mnemonic, passphrase). The caller wipes it.
     */
    suspend fun derive(
        mnemonic: String,
        seedTypePath: String,
        withTaproot: Boolean = false,
        passphrase: CharArray? = null,
    ): HdMaterial = coroutineScope {
        val seedHex = keys.mnemonicToSeedHex(mnemonic, passphrase)
        // iOS runs the four derivations concurrently (DispatchGroup); the engines serialize per bundle.
        val btcJob = async {
            val btc = keys.bitcoinXpubs(seedHex, seedTypePath)
            check(btc.legacyMain.isNotEmpty() && btc.legacyChange.isNotEmpty()) { "BTC xpubs missing" }
            val legacy0 = keys.bitcoinAddresses(BitcoinAddressType.LEGACY, btc.legacyMain, 0, 0).single()
            val native0 = keys.bitcoinAddresses(BitcoinAddressType.NATIVE_SEGWIT, btc.nativeSegwitMain, 0, 0).single()
            Triple(btc, legacy0, native0)
        }
        val ethJob = async {
            keys.ethAccount(seedHex, 0).also {
                check(it.publicKey.isNotEmpty() && it.address.isNotEmpty()) { "ETH account missing" }
            }
        }
        val trxJob = async {
            keys.tronIndex0(seedHex).also {
                check(it.hexAddress.isNotEmpty() && it.base58Address.isNotEmpty()) { "TRX account missing" }
            }
        }
        val solJob = async {
            try {
                keys.solanaAddress(seedHex).takeIf { it.isNotEmpty() }
            } catch (e: kotlinx.coroutines.CancellationException) {
                throw e
            } catch (e: Exception) {
                null
            }
        }
        // iOS `prepareTaprootKeys`: new / restored standard BIP39 personal wallets get Taproot by default; a JS failure
        // never blocks the creation (only logged, keys = null).
        val taprootJob = async {
            if (!withTaproot || seedTypePath != STANDARD_SEED_TYPE_PATH) return@async null
            try {
                keys.taprootXpubs(seedHex)
            } catch (e: kotlinx.coroutines.CancellationException) {
                throw e
            } catch (e: Exception) {
                Log.w(TAG) { "Taproot xpubs for the new wallet failed: ${e.javaClass.simpleName}" }
                null
            }
        }
        val (btc, legacy0, native0) = btcJob.await()
        HdMaterial(seedHex, btc, legacy0, native0, ethJob.await(), trxJob.await(), solJob.await(), taprootJob.await())
    }

    /**
     * OBV2 envelopes of the mnemonic + seed (+ the BIP39 [passphrase] of a passphrase import); `null` when a self-check
     * failed.
     */
    suspend fun seal(
        walletId: String,
        mnemonic: CharArray,
        material: HdMaterial,
        password: CharArray,
        now: Long,
        passphrase: CharArray? = null,
    ) = sealer.sealHd(walletId, mnemonic, material.seedHex, password, now, passphrase)

    /**
     * The addresses of the passphrase "Check addresses" dialog (iOS `derivePassphrasePreview`), from the
     * same functions creation uses: BTC chain xpubs → receive address 0 of BIP86 (Taproot bundle) / 84 / 49 / 44, ETH
     * account 0, TRX index 0, SOL. Any address missing or failing throws (the whole check fails, like iOS).
     */
    suspend fun checkAddresses(seedHex: String): PassphraseCheck = coroutineScope {
        val btcJob = async {
            val btc = keys.bitcoinXpubs(seedHex, STANDARD_SEED_TYPE_PATH)
            Triple(
                keys.bitcoinAddresses(BitcoinAddressType.NATIVE_SEGWIT, btc.nativeSegwitMain, 0, 0).single(),
                keys.bitcoinAddresses(BitcoinAddressType.NESTED_SEGWIT, btc.nestedSegwitMain, 0, 0).single(),
                keys.bitcoinAddresses(BitcoinAddressType.LEGACY, btc.legacyMain, 0, 0).single(),
            )
        }
        val taprootJob = async {
            val receive = keys.taprootXpubs(seedHex).receive
            keys.bitcoinAddresses(BitcoinAddressType.TAPROOT, receive, 0, 0).single()
        }
        val ethJob = async { keys.ethAccount(seedHex, 0).address }
        val trxJob = async { keys.tronIndex0(seedHex).base58Address }
        val solJob = async { keys.solanaAddress(seedHex) }
        val (native, nested, legacy) = btcJob.await()
        val rows = listOf(
            PassphraseAddressKind.BTC_TAPROOT to taprootJob.await(),
            PassphraseAddressKind.BTC_NATIVE_SEGWIT to native,
            PassphraseAddressKind.BTC_NESTED_SEGWIT to nested,
            PassphraseAddressKind.BTC_LEGACY to legacy,
            PassphraseAddressKind.ETH to ethJob.await(),
            PassphraseAddressKind.TRX to trxJob.await(),
            PassphraseAddressKind.SOL to solJob.await(),
        ).map { (kind, address) ->
            check(address.isNotEmpty()) { "$kind address missing" }
            PassphraseCheckRow(kind, address)
        }
        PassphraseCheck(rows)
    }

    private companion object {
        const val TAG = "HdWalletFactory"

        /** iOS `getSeedTypePath()` of a standard BIP39 wallet (BIP86 exists only there). */
        const val STANDARD_SEED_TYPE_PATH = "0"
    }

    /** Lowercase hex sha256 of the UTF-8 bytes of [chars] (iOS `String.sha256()`), without a `String` copy. */
    fun sha256Hex(chars: CharArray): String {
        val bytes = Secrets.utf8(chars)
        return try {
            Hashes.sha256Hex(bytes)
        } finally {
            bytes.wipe()
        }
    }
}
