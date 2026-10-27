// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.wallet.testing

import io.ownbit.core.crypto.hash.Hashes
import io.ownbit.core.crypto.kdf.Scrypt
import io.ownbit.core.crypto.obv2.Obv2Envelope
import io.ownbit.core.crypto.testing.FakeDeviceKeyManager
import io.ownbit.core.wallet.biometric.BiometricSendVault
import io.ownbit.core.wallet.biometric.GrantRegistry
import io.ownbit.core.wallet.biometric.QuickSendEligibility
import io.ownbit.core.wallet.biometric.QuickSendRepository
import io.ownbit.core.wallet.biometric.QuickSendRevoker
import io.ownbit.core.wallet.biometric.TxAuthorizer
import io.ownbit.core.wallet.biometric.UsdQuotes
import io.ownbit.core.wallet.biometric.WalletAuthorizationPolicy
import io.ownbit.core.wallet.manage.WalletPasswordChanger
import io.ownbit.core.wallet.secret.PasswordAttemptTracker
import io.ownbit.core.wallet.secret.SealedSecrets
import io.ownbit.core.wallet.secret.SecretSealer
import io.ownbit.core.wallet.secret.SecretVault
import io.ownbit.core.wallet.secret.StoredWalletSecrets
import io.ownbit.core.wallet.secret.WalletSecretAccessImpl
import io.ownbit.core.wallet.secret.WalletSecretStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableStateFlow
import java.io.File
import java.util.concurrent.ConcurrentHashMap

/** In-memory [WalletSecretStore]; [failWrites] makes [replaceEnvelopes] throw (nothing written). */
internal class InMemoryWalletSecretStore : WalletSecretStore {
    val rows = ConcurrentHashMap<String, StoredWalletSecrets>()
    var failWrites = false

    override suspend fun read(walletId: String): StoredWalletSecrets? = rows[walletId]

    override suspend fun replaceEnvelopes(sealed: SealedSecrets) {
        if (failWrites) throw IllegalStateException("disk full")
        val old = rows[sealed.walletId] ?: throw IllegalStateException("no wallet")
        rows[sealed.walletId] = StoredWalletSecrets(
            walletId = old.walletId,
            encryptedMnemonic = sealed.encryptedMnemonic,
            encryptedSeed = sealed.encryptedSeed,
            encryptedPrivateKey = sealed.encryptedPrivateKey,
            encryptedWif = sealed.encryptedWif,
            encryptedPassphrase = sealed.encryptedPassphrase,
            mnemonicHash = old.mnemonicHash,
            seedHash = old.seedHash,
            privateKeyHash = old.privateKeyHash,
            wifHash = old.wifHash,
            privateKeyCoinType = old.privateKeyCoinType,
        )
    }
}

/**
 * The vault wired for JVM tests: software device key, BouncyCastle scrypt with the production parameters, the
 * software Keystore stand-in for the biometric keys, and a temp-dir quick-send file.
 */
internal class VaultTestEnv(dir: File) {
    val deviceKeys = FakeDeviceKeyManager()
    val obv2 = Obv2Envelope(deviceKeys, Scrypt.bouncyCastleOnly(), Dispatchers.Default)
    val store = InMemoryWalletSecretStore()
    val attempts = PasswordAttemptTracker()
    val vault = SecretVault(store, obv2, attempts)
    val sealer = SecretSealer(obv2)
    val secretAccess = WalletSecretAccessImpl(vault)

    val clocks = TestClocks()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    val bioKeys = FakeBiometricKeyStore()
    val bioCapability = FakeCapabilityChecker()
    val foreground = MutableStateFlow(true)
    val quickSendFile = File(dir, "biometric/quick_send.enc")
    val quickSendRepo = QuickSendRepository(quickSendFile, TestRecordCipher(), bioKeys, Dispatchers.IO, scope)
    val grants = GrantRegistry(clocks, scope, foreground)
    private val ineligible = ConcurrentHashMap.newKeySet<String>()
    val eligibility = QuickSendEligibility { id -> store.rows[id]?.encryptedMnemonic != null && id !in ineligible }
    val quickSend = BiometricSendVault(
        quickSendRepo, bioKeys, bioCapability, vault, eligibility, grants, clocks, clocks, Dispatchers.IO,
    )
    val policy = WalletAuthorizationPolicy(quickSendRepo, bioCapability, UsdQuotes { null }, clocks)
    val authorizer = TxAuthorizer(policy, quickSend)
    val passwordChanger = WalletPasswordChanger(store, vault, sealer, QuickSendRevoker { id, reason -> quickSend.disable(id, reason) })

    /** A hot HD wallet with the BIP39 test vector, sealed under [password] (and optionally a BIP39 passphrase). */
    suspend fun addHotWallet(id: String, password: CharArray = PASSWORD, passphrase: CharArray? = null): String {
        val seed = if (passphrase == null) SEED_HEX else SEED_HEX_TREZOR
        val sealed = requireNotNull(sealer.sealHd(id, MNEMONIC.toCharArray(), seed, password, 1L, passphrase))
        store.rows[id] = StoredWalletSecrets(
            walletId = id,
            encryptedMnemonic = sealed.encryptedMnemonic,
            encryptedSeed = sealed.encryptedSeed,
            encryptedPassphrase = sealed.encryptedPassphrase,
            mnemonicHash = Hashes.sha256Hex(MNEMONIC),
            seedHash = Hashes.sha256Hex(seed),
        )
        return id
    }

    /** A wallet that is no longer eligible for quick send (e.g. became a cold wallet). */
    fun makeIneligible(id: String) {
        ineligible += id
    }

    /** The wallet row is gone. */
    fun removeWallet(id: String) {
        store.rows.remove(id)
    }

    fun close() {
        scope.cancel()
    }

    companion object {
        /** BIP39 test vector and its seeds (empty passphrase / "TREZOR"). */
        const val MNEMONIC = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
        const val SEED_HEX =
            "5eb00bbddcf069084889a8ab9155568165f5c453ccb85e70811aaed6f6da5fc19a5ac40b389cd370d086206dec8aa6c43daea6690f20ad3d8d48b2d2ce9e38e4"
        const val SEED_HEX_TREZOR =
            "c55257c360c07c72029aebc1b53c05ed0362ada38ead3e3e9efa3708e53495531f09a6987599d18264c1e1c92f2cf141630c7a3c4ab7c81b2f001698e7463b04"

        val PASSWORD: CharArray get() = "Passw0rd!x".toCharArray()
        val NEW_PASSWORD: CharArray get() = "N3wPassw0rd?".toCharArray()
    }
}
