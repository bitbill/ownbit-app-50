// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.wallet

import io.ownbit.core.crypto.bip39.Bip39Validator
import io.ownbit.core.crypto.hash.Hashes
import io.ownbit.core.crypto.kdf.Scrypt
import io.ownbit.core.crypto.keystore.DeviceKey
import io.ownbit.core.crypto.keystore.DeviceKeyManager
import io.ownbit.core.crypto.obv2.Obv2Envelope
import io.ownbit.core.crypto.testing.WordlistFixture
import io.ownbit.core.jsengine.bridge.BitcoinAddressType
import io.ownbit.core.jsengine.bridge.BitcoinExtendedPublicKeys
import io.ownbit.core.jsengine.bridge.EthereumAccount
import io.ownbit.core.jsengine.bridge.PublicKeyAddress
import io.ownbit.core.jsengine.bridge.TaprootXpubs
import io.ownbit.core.jsengine.bridge.TronAddress
import io.ownbit.core.jsengine.chain.ChainKeys
import io.ownbit.core.jsengine.chain.JsChain
import io.ownbit.core.model.wallet.PassphraseIssue
import io.ownbit.core.wallet.imports.MnemonicCheck
import io.ownbit.core.wallet.imports.MnemonicImportCheck
import io.ownbit.core.wallet.imports.MnemonicRejection
import io.ownbit.core.wallet.imports.PassphraseAddressKind
import io.ownbit.core.wallet.internal.HdWalletFactory
import io.ownbit.core.wallet.internal.KeyDeriver
import io.ownbit.core.wallet.secret.SecretSealer
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.test.runTest
import org.junit.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertIs
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.time.Duration.Companion.seconds

/**
 * The import check order (native word lists first, the bundle's checksum last) and the key part of wallet creation
 * (seed → public keys → sealed envelopes + integrity hashes), with a scripted [KeyDeriver] in place of the WebView
 * bundles (the real derivations run on a device; the passphrase vectors pin their results).
 */
class MnemonicCreationTest {

    private val validator = Bip39Validator.fromWordlistText(WordlistFixture.text)

    /** Answers like the bundles for the BIP39 test vector; records the calls. */
    private class ScriptedKeys(var checksumOk: Boolean = true, var failTaproot: Boolean = false) : KeyDeriver {
        val calls = mutableListOf<String>()
        override suspend fun generateMnemonic(wordCount: Int) = MNEMONIC.also { calls += "generate:$wordCount" }
        override suspend fun validateMnemonic(mnemonic: String) = checksumOk.also { calls += "validate" }
        override suspend fun mnemonicToSeedHex(mnemonic: String, passphrase: CharArray?) =
            (if (passphrase == null) SEED else SEED_TREZOR).also { calls += "seed" }
        override suspend fun masterXpub(seedHex: String, seedTypePath: String) = "xpub-main"
        override suspend fun bitcoinXpubs(seedHex: String, seedTypePath: String) =
            BitcoinExtendedPublicKeys("xpub44", "xpub44c", "ypub49", "ypub49c", "zpub84", "zpub84c")
        override suspend fun bitcoinAddresses(type: BitcoinAddressType, xpub: String, from: Long, to: Long) = listOf("addr-$type")
        override suspend fun taprootXpubs(seedHex: String): TaprootXpubs {
            if (failTaproot) throw IllegalStateException("bundle failed")
            return TaprootXpubs("xpub86", "xpub86c")
        }
        override suspend fun ethAccount(seedHex: String, index: Int) = EthereumAccount("xpub60", "04ab", "0x9858EfFD232B4033E47d90003D41EC34EcaEda94")
        override suspend fun ethAccountFromXpub(xpub: String, index: Int) = PublicKeyAddress("04ab", "0xabc")
        override suspend fun tronIndex0(seedHex: String) = TronAddress("41ab", "TUEZSdKsoDHQMeZwihtdoBiN46zxhGWYdH")
        override suspend fun tronFromEthXpub(ethXpub: String, index: Int) = TronAddress("41cd", "T2")
        override suspend fun solanaAddress(seedHex: String) = "HAgk14JpMQLgt6rVgv7cBQFJWFto5Dqxi472uT3DKpqk"
        override suspend fun deriveChain(chain: JsChain, seedHex: String, mnemonic: String?): ChainKeys =
            throw UnsupportedOperationException()
    }

    private class MemoryDeviceKeys : DeviceKeyManager {
        private var raw: ByteArray? = null
        override fun peek(): DeviceKey? = raw?.let(::key)
        @Synchronized override fun getOrCreate(): DeviceKey = key(raw ?: ByteArray(32) { 7 }.also { raw = it })
        private fun key(r: ByteArray) = object : DeviceKey {
            override fun hmacSha256(message: ByteArray) = Hashes.hmacSha256(r, message)
        }
    }

    @Test fun `the import check runs the word lists first and the bundle checksum last`() = runTest {
        val keys = ScriptedKeys()
        val check = MnemonicImportCheck({ validator }, keys)
        assertEquals(MnemonicRejection.EMPTY, (check.check("  ") as MnemonicCheck.Rejected).reason)
        assertEquals(MnemonicRejection.NO_SPACE, (check.check("abandon") as MnemonicCheck.Rejected).reason)
        val unknown = check.check("abandon abandn about") as MnemonicCheck.Rejected
        assertEquals(MnemonicRejection.UNKNOWN_WORDS, unknown.reason)
        assertEquals(listOf("abandn"), unknown.invalidWords)
        assertEquals(11, (check.check(MNEMONIC.substringBeforeLast(' ')) as MnemonicCheck.Rejected).wordCount)
        assertTrue(keys.calls.isEmpty(), "nothing reached the bundle yet")

        val accepted = assertIs<MnemonicCheck.Accepted>(check.check("  ABANDON abandon　abandon abandon abandon abandon abandon abandon abandon abandon abandon about "))
        assertEquals(MNEMONIC, accepted.normalized)
        assertEquals(listOf("validate"), keys.calls)
        keys.checksumOk = false
        assertEquals(MnemonicRejection.CHECKSUM, (check.check(MNEMONIC) as MnemonicCheck.Rejected).reason)

        val noLists = MnemonicImportCheck({ Bip39Validator.fromWordlistText(null) }, keys)
        assertEquals(MnemonicRejection.WORDLIST_UNAVAILABLE, (noLists.check(MNEMONIC) as MnemonicCheck.Rejected).reason)
    }

    @Test fun `a passphrase import checks both passphrase fields before the phrase`() = runTest {
        val check = MnemonicImportCheck({ validator }, ScriptedKeys())
        val mismatch = check.check(MNEMONIC, "TREZOR".toCharArray(), "trezor".toCharArray()) as MnemonicCheck.Rejected
        assertEquals(PassphraseIssue.MISMATCH, mismatch.passphraseIssue)
        val control = check.check(MNEMONIC, "a‍b".toCharArray(), "a‍b".toCharArray()) as MnemonicCheck.Rejected
        assertEquals(PassphraseIssue.INVALID_CHARACTER, control.passphraseIssue)
        assertIs<MnemonicCheck.Accepted>(check.check(MNEMONIC, "TREZOR".toCharArray(), "TREZOR".toCharArray()))
    }

    @Test fun `creation derives the public keys, seals mnemonic and seed and hashes them`() = runTest(timeout = 60.seconds) {
        val keys = ScriptedKeys()
        val obv2 = Obv2Envelope(MemoryDeviceKeys(), Scrypt.bouncyCastleOnly(), Dispatchers.Default)
        val factory = HdWalletFactory(keys, SecretSealer(obv2))
        val mnemonic = keys.generateMnemonic(12)
        val material = factory.derive(mnemonic, "0", withTaproot = true)
        assertEquals(SEED, material.seedHex)
        assertEquals("addr-LEGACY", material.legacy0)
        assertEquals("xpub86", material.taproot?.receive)
        val sealed = assertNotNull(factory.seal("w1", mnemonic.toCharArray(), material, "Passw0rd!x".toCharArray(), 1L))
        assertEquals(MNEMONIC, obv2.decryptToString(sealed.encryptedMnemonic!!, "Passw0rd!x".toCharArray()))
        assertEquals(SEED, obv2.decryptToString(sealed.encryptedSeed!!, "Passw0rd!x".toCharArray()))
        assertNull(sealed.encryptedPassphrase)
        assertEquals(Hashes.sha256Hex(MNEMONIC), factory.sha256Hex(MNEMONIC.toCharArray()))

        // A Taproot failure never blocks the creation; a custom path never gets Taproot.
        keys.failTaproot = true
        assertNull(factory.derive(mnemonic, "0", withTaproot = true).taproot)
        keys.failTaproot = false
        assertNull(factory.derive(mnemonic, "m/44'/0'/0'/0", withTaproot = true).taproot)
    }

    @Test fun `the passphrase address check lists the seven first addresses and fails as a whole`() = runTest {
        val keys = ScriptedKeys()
        val factory = HdWalletFactory(keys, SecretSealer(Obv2Envelope(MemoryDeviceKeys(), Scrypt.bouncyCastleOnly(), Dispatchers.Default)))
        val check = factory.checkAddresses(SEED_TREZOR)
        assertEquals(PassphraseAddressKind.entries, check.rows.map { it.kind })
        assertEquals("addr-TAPROOT", check.address(PassphraseAddressKind.BTC_TAPROOT))
        keys.failTaproot = true
        assertFailsWith<IllegalStateException> { factory.checkAddresses(SEED_TREZOR) }
    }

    private companion object {
        const val MNEMONIC = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
        const val SEED =
            "5eb00bbddcf069084889a8ab9155568165f5c453ccb85e70811aaed6f6da5fc19a5ac40b389cd370d086206dec8aa6c43daea6690f20ad3d8d48b2d2ce9e38e4"
        const val SEED_TREZOR =
            "c55257c360c07c72029aebc1b53c05ed0362ada38ead3e3e9efa3708e53495531f09a6987599d18264c1e1c92f2cf141630c7a3c4ab7c81b2f001698e7463b04"
    }
}
