// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.chain.utxo

import org.bouncycastle.asn1.ASN1Integer
import org.bouncycastle.asn1.ASN1Sequence
import org.bouncycastle.crypto.digests.RIPEMD160Digest
import org.bouncycastle.crypto.ec.CustomNamedCurves
import org.bouncycastle.crypto.params.ECDomainParameters
import org.bouncycastle.crypto.params.ECPublicKeyParameters
import org.bouncycastle.crypto.signers.ECDSASigner
import org.junit.Test
import java.security.MessageDigest
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

/**
 * Independent check of what the shipped ZEC bundle (`zcashjs-lib-app-0251.js`) signs for the two v5 cases of an iOS
 * debug screen (the data iOS compared byte-for-byte between the simulator and Node).
 *
 * The expected values ([ZecV5Vectors]) were produced by running the shipped bundle in Node 20 with exactly that data
 * (seed of the public BIP39 vector `abandon ×11 about`; for the multisig case a debug test key that is not published
 * here — only its public keys, in the redeem script, are needed to verify); in the app an emulator test asserts the
 * Android WebView returns the same bytes. Here, without JS, the results
 * are re-checked with [ZcashV5] (whose digests match the official `zip_0244` vectors, see [ZcashV5Test]):
 * v5 header / version group / branch id, the ZIP 244 txid, and every ECDSA signature against its ZIP 244
 * SIGHASH_ALL digest (P2PKH spends commit the P2PKH script, P2SH spends the P2SH script — not the redeem script).
 */
class ZecBundleV5VectorsTest {

    private fun hex(s: String) = RawUtxoTransaction.hexToBytes(s)
    private fun ByteArray.hex() = RawUtxoTransaction.toHex(this)

    private val curve = CustomNamedCurves.getByName("secp256k1")
    private val domain = ECDomainParameters(curve.curve, curve.g, curve.n, curve.h)

    private fun sha256(b: ByteArray) = MessageDigest.getInstance("SHA-256").digest(b)
    private fun hash160(b: ByteArray): ByteArray {
        val d = RIPEMD160Digest()
        val s = sha256(b)
        d.update(s, 0, s.size)
        return ByteArray(20).also { d.doFinal(it, 0) }
    }

    private fun p2pkh(pubKey: ByteArray) = hex("76a914") + hash160(pubKey) + hex("88ac")
    private fun p2sh(redeem: ByteArray) = hex("a914") + hash160(redeem) + hex("87")

    /** DER + sighash byte → verifies (low-s not required) against [digest]. */
    private fun verifies(pubKey: ByteArray, sigWithHashType: ByteArray, digest: ByteArray): Boolean {
        assertEquals(ZcashV5.SIGHASH_ALL, sigWithHashType.last().toInt() and 0xff, "SIGHASH_ALL byte")
        val der = ASN1Sequence.getInstance(sigWithHashType.copyOf(sigWithHashType.size - 1))
        val r = (der.getObjectAt(0) as ASN1Integer).value
        val s = (der.getObjectAt(1) as ASN1Integer).value
        val signer = ECDSASigner()
        signer.init(false, ECPublicKeyParameters(curve.curve.decodePoint(pubKey), domain))
        return signer.verifySignature(digest, r, s)
    }

    /** Pushes of a P2PKH scriptSig: `<sig> <pubkey>`. */
    private fun pushes(script: ByteArray): List<ByteArray> {
        val out = mutableListOf<ByteArray>()
        var p = 0
        while (p < script.size) {
            val n = script[p].toInt() and 0xff
            require(n in 1..75) { "direct pushes only" }
            out += script.copyOfRange(p + 1, p + 1 + n)
            p += 1 + n
        }
        return out
    }

    private fun checkSingleSig(rawHex: String, txid: String, branchId: Long, lockTime: Long, expiry: Long, amounts: List<Long>) {
        val tx = assertNotNull(ZcashV5.parse(hex(rawHex)), "a transparent-only v5 transaction")
        assertTrue(rawHex.startsWith("050000800a27a726"), "header 0x80000005 + versionGroupId 0x26A7270A")
        assertEquals(branchId, tx.branchId)
        assertEquals(lockTime, tx.lockTime)
        assertEquals(expiry, tx.expiryHeight)
        assertEquals(txid, ZcashV5.txid(tx), "bundle txid = ZIP 244 digest (reversed)")
        assertEquals(txid, RawUtxoTransaction.decode(rawHex)!!.txId)
        assertEquals(ZecV5Vectors.OUTPUT_SCRIPTS, tx.outs.map { it.script.hex() })
        assertEquals(listOf(1_000_000L, 470_000L), tx.outs.map { it.value })
        val keys = tx.ins.map { pushes(it.scriptSig).also { p -> assertEquals(2, p.size) } }
        val spent = keys.map { p2pkh(it[1]) }
        for ((i, k) in keys.withIndex()) {
            assertEquals(0xffffffffL, tx.ins[i].sequence)
            val digest = ZcashV5.transparentSigDigest(tx, i, amounts, spent)
            assertTrue(verifies(k[1], k[0], digest), "input $i signature commits to the ZIP 244 digest")
            val otherBranch = if (tx.branchId == 0x5437f330L) 0x37a5165bL else 0x5437f330L
            val other = ZcashV5.Tx(otherBranch, tx.lockTime, tx.expiryHeight, tx.ins, tx.outs)
            assertTrue(!verifies(k[1], k[0], ZcashV5.transparentSigDigest(other, i, amounts, spent)), "branch id is committed")
        }
    }

    @Test
    fun `seed wallet v5 send (iOS debug data) is a valid ZIP 225 or 244 transaction`() {
        checkSingleSig(ZecV5Vectors.SINGLE_HEX, ZecV5Vectors.SINGLE_TXID, 933_566_043L, 0, 0, listOf(250_000L, 1_234_567L))
        // bip39Index 0 receive and 3 change: two different keys
        val tx = ZcashV5.parse(hex(ZecV5Vectors.SINGLE_HEX))!!
        assertTrue(!pushes(tx.ins[0].scriptSig)[1].contentEquals(pushes(tx.ins[1].scriptSig)[1]))
    }

    @Test
    fun `private-key wallet signs the same transaction id as the seed with the same key`() {
        checkSingleSig(ZecV5Vectors.PRIVATE_KEY_HEX, ZecV5Vectors.SINGLE_TXID, 933_566_043L, 0, 0, listOf(250_000L, 1_234_567L))
    }

    @Test
    fun `branch id, expiry height and lock time come from the sign data`() {
        checkSingleSig(ZecV5Vectors.NU62_HEX, ZecV5Vectors.NU62_TXID, 0x5437f330L, 3_499_000L, 3_500_000L, listOf(250_000L, 1_234_567L))
    }

    @Test
    fun `v4 fallback (no zec fields) stays a sapling v4 transaction`() {
        val tx = assertNotNull(RawUtxoTransaction.decode(ZecV5Vectors.V4_HEX))
        assertTrue(tx.overwintered)
        assertEquals(4L, tx.version)
        assertEquals(0x892F2085L, tx.versionGroupId)
        assertEquals(ZecV5Vectors.V4_TXID, tx.txId, "v4 txid = double SHA-256 of the serialisation")
    }

    @Test
    fun `2-of-3 multisig v5 signatures commit to the P2SH script of every input`() {
        val redeem = hex(ZecV5Vectors.MULTISIG_REDEEM)
        val pubKey0 = redeem.copyOfRange(2, 35) // signOrder 0 = first key of the redeem script
        val p2sh = p2sh(redeem)
        assertEquals(ZecV5Vectors.MULTISIG_P2SH, p2sh.hex(), "the scriptPubKey the server may send")
        val tx = ZcashV5.Tx(
            branchId = 933_566_043L,
            lockTime = 0,
            expiryHeight = 0,
            ins = ZecV5Vectors.MULTISIG_OUTPOINTS.map { (txid, vout) -> ZcashV5.TxIn(hex(txid).reversedArray(), vout, ByteArray(0), 0xffffffffL) },
            outs = ZecV5Vectors.MULTISIG_OUTPUT_SCRIPTS.zip(listOf(400_000L, 190_000L)) { s, v -> ZcashV5.TxOut(v, hex(s)) },
        )
        val amounts = listOf(500_000L, 70_000L, 30_000L)
        val spent = List(3) { p2sh }
        assertEquals(3, ZecV5Vectors.MULTISIG_SIGNATURES.size)
        for ((i, sig) in ZecV5Vectors.MULTISIG_SIGNATURES.withIndex()) {
            assertTrue(verifies(pubKey0, hex(sig), ZcashV5.transparentSigDigest(tx, i, amounts, spent)), "input $i")
            // the redeem script instead of the P2SH script (the v4 rule) must not verify
            assertTrue(!verifies(pubKey0, hex(sig), ZcashV5.transparentSigDigest(tx, i, amounts, List(3) { redeem })), "input $i vs redeem")
        }
        // the v4 signatures of the same proposal are different (a v4 co-signer cannot complete a v5 proposal)
        assertTrue(ZecV5Vectors.MULTISIG_SIGNATURES_V4.zip(ZecV5Vectors.MULTISIG_SIGNATURES).none { (a, b) -> a == b })
    }

    @Test
    fun `the output scripts are those of the iOS test addresses`() {
        // t1evUDHw… (P2PKH) and t3KGYh… (P2SH of the test redeem script) of the iOS debug data
        assertEquals("76a914e6e56224f71b7445427074c38666ef4f3408ba2688ac", ZecV5Vectors.OUTPUT_SCRIPTS[0])
        assertEquals(ZecV5Vectors.MULTISIG_P2SH, ZecV5Vectors.OUTPUT_SCRIPTS[1])
        assertEquals(ZecV5Vectors.MULTISIG_P2SH, p2sh(hex(ZecV5Vectors.MULTISIG_REDEEM)).hex())
    }
}

/**
 * The iOS `BILDebugZec` v5 data and what the shipped bundle returns for it (Node 20, `require` of
 * `zec/zcashjs-lib-app-0251.js`, deterministic RFC 6979 signatures). Shared by the
 * JVM check above and the emulator test.
 */
object ZecV5Vectors {
    /** BIP39 seed of `abandon ×11 about` (public test vector). */
    const val SEED: String = "5eb00bbddcf069084889a8ab9155568165f5c453ccb85e70811aaed6f6da5fc1" +
        "9a5ac40b389cd370d086206dec8aa6c43daea6690f20ad3d8d48b2d2ce9e38e4"

    /** iOS `BILDebugZec.run()` `v5Single` (NU6.3 branch id 0x37a5165b = 933566043). */
    const val SINGLE_DATA: String = """{"zecTxVersion":5,"zecBranchId":933566043,"zecExpiryHeight":0,"zecLockTime":0,"inputs":[{"txid":"24d3e087bfe0c15f606db97836449852a44414f98f425301fb08affb3d64c11c","vout":0,"satoshis":250000,"bip39Index":0,"isChange":false,"scriptPubKey":""},{"txid":"50f6096d18f5436cd23d8b3eb782f58fa619e912a4f426b65f981402e2a95eb6","vout":7,"satoshis":1234567,"bip39Index":3,"isChange":true,"scriptPubKey":""}],"outputs":[{"address":"t1evUDHwrkA1py7AswqKZHKENx4jRm6SFep","amount":1000000},{"address":"t3KGYhWbLNcnLkc6L9T7daw4nTw7a7W5fG5","amount":470000}]}"""
    const val SINGLE_TXID: String = "2bfbf54c538b9cf85fee3c9111e6e10bcab25380268e3c7df810f28f2fe5df23"
    const val SINGLE_HEX: String = "050000800a27a7265b16a5370000000000000000021cc1643dfbaf08fb0153428ff91444a45298443678b96d605fc1e0bf87e0d324000000006a4730440220140fefa1c54b176d1cebe8f18b5c1d997729c8a1e7ecc33b5fdf7663c0a684870220779d997bbbdc3250d90f29dd263f8ec95055a1eec42ef8e44915061515bc979d012103db98d8f87716269ed31879aef19bdadbc869a9ea67729e36332d023b916cbcc9ffffffffb65ea9e20214985fb626f4a412e919a68ff582b73e8b3dd26c43f5186d09f650070000006b483045022100fab02dc10efbd539bd611d8f8e51d9fc84488b4cde250db599fa2a0459ed5e40022008241335ebc15ed1d79a0f863652fc7e14736f981e125d935f0b4ff0738de71a012102171762a7fce06ab4f64d2c41e11dc525596e6cfabfd77f936626c9046894ee53ffffffff0240420f00000000001976a914e6e56224f71b7445427074c38666ef4f3408ba2688acf02b07000000000017a91407bd85e414f210b01ac3b0ccd1dfb922eaab831287000000"

    /** [SINGLE_DATA] with both inputs from receive key #0 (a private-key wallet spends one key). */
    const val PRIVATE_KEY_DATA: String = """{"zecTxVersion":5,"zecBranchId":933566043,"zecExpiryHeight":0,"zecLockTime":0,"inputs":[{"txid":"24d3e087bfe0c15f606db97836449852a44414f98f425301fb08affb3d64c11c","vout":0,"satoshis":250000,"bip39Index":0,"isChange":false,"scriptPubKey":""},{"txid":"50f6096d18f5436cd23d8b3eb782f58fa619e912a4f426b65f981402e2a95eb6","vout":7,"satoshis":1234567,"bip39Index":0,"isChange":false,"scriptPubKey":""}],"outputs":[{"address":"t1evUDHwrkA1py7AswqKZHKENx4jRm6SFep","amount":1000000},{"address":"t3KGYhWbLNcnLkc6L9T7daw4nTw7a7W5fG5","amount":470000}]}"""

    /** WIF of ZEC receive key #0 of [SEED] (`getWIFFromSeedHex(seed, 0, false)`, public test vector). */
    const val WIF0: String = "KzEVy5oaBPhVPxH43bUg1g1zTv5Jitvc9nZesqqqc18Edi4bHQbu"

    /** `buildZecTxWithPrivateKey(WIF0, PRIVATE_KEY_DATA)` = `buildZecTransaction(SEED, PRIVATE_KEY_DATA)`. */
    const val PRIVATE_KEY_HEX: String = "050000800a27a7265b16a5370000000000000000021cc1643dfbaf08fb0153428ff91444a45298443678b96d605fc1e0bf87e0d324000000006b483045022100ecbe85b9eedf6f612151bb08a948c73631207c13408ae13019009f4f2cc260dc02202650e755ed1ce2b633bb15441b57ee8f95a5a58c727d88dab1b879640ff5a5ae012103db98d8f87716269ed31879aef19bdadbc869a9ea67729e36332d023b916cbcc9ffffffffb65ea9e20214985fb626f4a412e919a68ff582b73e8b3dd26c43f5186d09f650070000006a47304402207b805f6d9d49271ba243425f12ec8d03411f5e9397a96c4574ebbeea405a077802207db8f3fb1593b7aa055af93a2447f70c0672a3926c3c6bdc20e583afc35f2a6e012103db98d8f87716269ed31879aef19bdadbc869a9ea67729e36332d023b916cbcc9ffffffff0240420f00000000001976a914e6e56224f71b7445427074c38666ef4f3408ba2688acf02b07000000000017a91407bd85e414f210b01ac3b0ccd1dfb922eaab831287000000"

    /** [SINGLE_DATA] with the NU6.2 branch id, expiry height 3 500 000 and lock time 3 499 000. */
    const val NU62_DATA: String = """{"zecTxVersion":5,"zecBranchId":1412952880,"zecExpiryHeight":3500000,"zecLockTime":3499000,"inputs":[{"txid":"24d3e087bfe0c15f606db97836449852a44414f98f425301fb08affb3d64c11c","vout":0,"satoshis":250000,"bip39Index":0,"isChange":false,"scriptPubKey":""},{"txid":"50f6096d18f5436cd23d8b3eb782f58fa619e912a4f426b65f981402e2a95eb6","vout":7,"satoshis":1234567,"bip39Index":3,"isChange":true,"scriptPubKey":""}],"outputs":[{"address":"t1evUDHwrkA1py7AswqKZHKENx4jRm6SFep","amount":1000000},{"address":"t3KGYhWbLNcnLkc6L9T7daw4nTw7a7W5fG5","amount":470000}]}"""
    const val NU62_TXID: String = "0f61e817aa9d54db4871afaae204be418429386cf1ab659d967356d57336f2ed"
    const val NU62_HEX: String = "050000800a27a72630f33754f8633500e0673500021cc1643dfbaf08fb0153428ff91444a45298443678b96d605fc1e0bf87e0d324000000006a47304402204ba61dc79c81b5f7afc2f07c4dae8fc0cf2f7ab32bc58cb81603d5c7e7c7830d02204acc5908eb555886ea555958397337c0adc0af16c6b8291f75ce8ab697189edb012103db98d8f87716269ed31879aef19bdadbc869a9ea67729e36332d023b916cbcc9ffffffffb65ea9e20214985fb626f4a412e919a68ff582b73e8b3dd26c43f5186d09f650070000006b483045022100ef1306aded44398d75004a12b0d08deb334abf9fc6079f1b905340f7f8642b3302203d89f675538118b05032b418c09f0e471c6490d35d7da2bdc87da3b1a65acc80012102171762a7fce06ab4f64d2c41e11dc525596e6cfabfd77f936626c9046894ee53ffffffff0240420f00000000001976a914e6e56224f71b7445427074c38666ef4f3408ba2688acf02b07000000000017a91407bd85e414f210b01ac3b0ccd1dfb922eaab831287000000"

    /** [SINGLE_DATA] without the four zec fields: the bundle's sapling v4 transaction. */
    const val V4_DATA: String = """{"inputs":[{"txid":"24d3e087bfe0c15f606db97836449852a44414f98f425301fb08affb3d64c11c","vout":0,"satoshis":250000,"bip39Index":0,"isChange":false,"scriptPubKey":""},{"txid":"50f6096d18f5436cd23d8b3eb782f58fa619e912a4f426b65f981402e2a95eb6","vout":7,"satoshis":1234567,"bip39Index":3,"isChange":true,"scriptPubKey":""}],"outputs":[{"address":"t1evUDHwrkA1py7AswqKZHKENx4jRm6SFep","amount":1000000},{"address":"t3KGYhWbLNcnLkc6L9T7daw4nTw7a7W5fG5","amount":470000}]}"""
    const val V4_TXID: String = "397ea34fa49f7533e42508282cb624173e360ecacd5ea4aa95d22cf104496fc3"
    const val V4_HEX: String = "0400008085202f89021cc1643dfbaf08fb0153428ff91444a45298443678b96d605fc1e0bf87e0d324000000006b483045022100b7fe19a2e037992ea82f552dd599a00673d9f68a24ac59a7a93bf2527e7bb7fc0220342d5fbe5a169b4680ee9c75febec841213ee3345753f142b20b405d09f38db4012103db98d8f87716269ed31879aef19bdadbc869a9ea67729e36332d023b916cbcc9ffffffffb65ea9e20214985fb626f4a412e919a68ff582b73e8b3dd26c43f5186d09f650070000006a473044022066b474b1010905b68dd820b5a24219dddb9494ac28ffa5e10fd010e386c91b1402205d7dea2af3816e912345c6a7433e0d155a29783d9bdf1f8f01d54e0ea7507a89012102171762a7fce06ab4f64d2c41e11dc525596e6cfabfd77f936626c9046894ee53ffffffff0240420f00000000001976a914e6e56224f71b7445427074c38666ef4f3408ba2688acf02b07000000000017a91407bd85e414f210b01ac3b0ccd1dfb922eaab83128700000000000000000000000000000000000000"

    val OUTPUT_SCRIPTS: List<String> = listOf(
        "76a914e6e56224f71b7445427074c38666ef4f3408ba2688ac",
        "a91407bd85e414f210b01ac3b0ccd1dfb922eaab831287",
    )

    /** iOS debug screen `v5Multi` (2-of-3, signOrder 0). */
    const val MULTISIG_DATA: String = """{"zecTxVersion":5,"zecBranchId":933566043,"zecExpiryHeight":0,"zecLockTime":0,"inputs":[{"txid":"f44c2dfda97846e20fa6a6da5829a8589d7b1e26794192f5a252db46ab6b0820","vout":0,"satoshis":500000,"scriptPubKey":""},{"txid":"bf9ecc5dae097b3ba5791e265603f24f99fec997bbc7382fefbfdfe9f8f94551","vout":1,"satoshis":70000,"scriptPubKey":"a91407bd85e414f210b01ac3b0ccd1dfb922eaab831287"},{"txid":"50f0aa6d082625d6ccb3fbf56457d50202c1653519f50789d02d38ffb7a013d2","vout":4,"satoshis":30000,"bip39Index":0,"isChange":false}],"outputs":[{"address":"t1TccjmfQNpgPdF6E4uUomNUCDhv4wnvKkH","amount":400000},{"address":"t3KGYhWbLNcnLkc6L9T7daw4nTw7a7W5fG5","amount":190000}]}"""

    /** [MULTISIG_DATA] without the zec fields (the v4 proposal of the same spend). */
    const val MULTISIG_V4_DATA: String = """{"inputs":[{"txid":"f44c2dfda97846e20fa6a6da5829a8589d7b1e26794192f5a252db46ab6b0820","vout":0,"satoshis":500000,"scriptPubKey":""},{"txid":"bf9ecc5dae097b3ba5791e265603f24f99fec997bbc7382fefbfdfe9f8f94551","vout":1,"satoshis":70000,"scriptPubKey":"a91407bd85e414f210b01ac3b0ccd1dfb922eaab831287"},{"txid":"50f0aa6d082625d6ccb3fbf56457d50202c1653519f50789d02d38ffb7a013d2","vout":4,"satoshis":30000,"bip39Index":0,"isChange":false}],"outputs":[{"address":"t1TccjmfQNpgPdF6E4uUomNUCDhv4wnvKkH","amount":400000},{"address":"t3KGYhWbLNcnLkc6L9T7daw4nTw7a7W5fG5","amount":190000}]}"""

    const val MULTISIG_REDEEM: String = "522102f9586eefcd79fda3f036375f9cdb3d90a22654c44b197e7ab206fb2e0702c6c2210259b53fb865f084642f18bfc3407c2dc25aedf4ccfc57de900855372776db71452103e469dd9997421f62694688e888f7297dedafda3728f7b8a18b8408896541c34053ae"
    const val MULTISIG_P2SH: String = "a91407bd85e414f210b01ac3b0ccd1dfb922eaab831287"

    val MULTISIG_OUTPOINTS: List<Pair<String, Long>> = listOf(
        "f44c2dfda97846e20fa6a6da5829a8589d7b1e26794192f5a252db46ab6b0820" to 0L,
        "bf9ecc5dae097b3ba5791e265603f24f99fec997bbc7382fefbfdfe9f8f94551" to 1L,
        "50f0aa6d082625d6ccb3fbf56457d50202c1653519f50789d02d38ffb7a013d2" to 4L,
    )

    /** t1TccjmfQNpgPdF6E4uUomNUCDhv4wnvKkH (P2PKH), t3KGYh… (P2SH). */
    val MULTISIG_OUTPUT_SCRIPTS: List<String> = listOf(
        "76a914" + "6adba1105579beb752cbc6b91546442f82d855dc" + "88ac",
        "a91407bd85e414f210b01ac3b0ccd1dfb922eaab831287",
    )

    val MULTISIG_SIGNATURES: List<String> = listOf(
        "304402207c382654bddf9bbb3d40d3ce5295cabcf1248ade12e0c174885e6c4efcf66cc10220737cbe335fb9e92688634d1fea2a94c37bb450aab5318b612ce6e86d0e75d2c901",
        "30440220783bb6d34b4ab9b43b1d7077a3cf719b6e3ddfb60c7550ab07c460e6ac73d4ae02207efb8030441eace0b2f95bb8798cf61f94fa25a75e74feb52c96295367862e1001",
        "3045022100b28b859df2262e4da8a56ad76a651c039b83b68df123a698de2b9b47f5d261df022057b68b270e50bbf43ee8dec57ed636d89f2add15651cc4820c0191330674575f01",
    )

    val MULTISIG_SIGNATURES_V4: List<String> = listOf(
        "3045022100ac13802a1bba6662101d97fd175b4c969f97dd161926dcd9943cd808004cb2e70220793880a940bc8d9fbbe6dd00e5e98af6219de6a53203e5718b5bf7b8411db7ce01",
        "304402202e3861a503a27674bde17507c168e2f2377ff7a84f6cc819f2a2dd56391889ae02205152a077245c5665cf620136233dc12bfd1f2058254d28f03cc96914083808a001",
        "304402204c0fb09628020017d2c131eb806bf743d5a7d51791c5a0044120aec92322179b02203663a2bf0c1c99dbccda2443c3770c697ee75ee408583d7841a7748e1d63966601",
    )
}
