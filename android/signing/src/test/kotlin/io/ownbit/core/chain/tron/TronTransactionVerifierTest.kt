// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.chain.tron

import org.junit.Test
import java.math.BigInteger
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Protobuf decoding of `raw_data_hex` and the pre-sign checks. */
class TronTransactionVerifierTest {

    @Test
    fun `address codec round trips the spec-07 TRX address`() {
        assertEquals(TronTx.OWNER_HEX, TronAddressCodec.toHex41(TronTx.OWNER))
        assertEquals(TronTx.OWNER, TronAddressCodec.toBase58(TronTx.OWNER_HEX))
        assertEquals(TronTx.OWNER_HEX, TronAddressCodec.toHex41(TronTx.OWNER_HEX.uppercase().replace("41C", "41c")))
        assertNull(TronAddressCodec.toHex41("TUEZSdKsoDHQMeZwihtdoBiN46zxhGWYdJ")) // checksum
        assertNull(TronAddressCodec.toHex41("0x9858EfFD232B4033E47d90003D41EC34EcaEda94"))
        assertEquals("a614f803b6fd780986a42c78ec9c7f77e6ded13c", TronAddressCodec.toHex41(TronTx.USDT)!!.drop(2))
    }

    @Test
    fun `decodes a TRX transfer`() {
        val tx = TronTransactionJson.parse(TronTx.transfer(amount = 1_234_567))!!
        assertTrue(tx.isTxIdConsistent)
        val c = tx.raw!!.contracts.single()
        assertEquals(TronContractType.TRANSFER, c.type)
        assertEquals("type.googleapis.com/protocol.TransferContract", c.typeUrl)
        assertEquals(TronTx.OWNER_HEX, c.ownerAddress)
        assertEquals(TronAddressCodec.toHex41(TronTx.TO), c.toAddress)
        assertEquals(BigInteger.valueOf(1_234_567), c.amount)
        assertEquals(TronTx.EXTENDED_EXPIRATION, tx.raw!!.expiration)
        assertEquals(TronTx.TIMESTAMP, tx.raw!!.timestamp)
        assertNull(TronTransactionVerifier.verifyTransfer(tx, TronTx.OWNER, TronTx.TO, BigInteger.valueOf(1_234_567), 0, ""))
    }

    @Test
    fun `rejects a swapped recipient, amount, owner or an unextended expiration`() {
        val tx = TronTransactionJson.parse(TronTx.transfer(amount = 5))!!
        assertEquals("recipient mismatch", TronTransactionVerifier.verifyTransfer(tx, TronTx.OWNER, TronTx.USDT, BigInteger.valueOf(5), 0, ""))
        assertEquals("amount mismatch", TronTransactionVerifier.verifyTransfer(tx, TronTx.OWNER, TronTx.TO, BigInteger.valueOf(6), 0, ""))
        assertEquals("owner mismatch", TronTransactionVerifier.verifyTransfer(tx, TronTx.TO, TronTx.TO, BigInteger.valueOf(5), 0, ""))
        assertEquals("not a TransferAssetContract", TronTransactionVerifier.verifyTransfer(tx, TronTx.OWNER, TronTx.TO, BigInteger.valueOf(5), 1, "1002000"))
        val short = TronTransactionJson.parse(TronTx.transfer(amount = 5, expiration = TronTx.TIMESTAMP + 60_000))!!
        assertEquals("expiration not extended", TronTransactionVerifier.verifyTransfer(short, TronTx.OWNER, TronTx.TO, BigInteger.valueOf(5), 0, ""))
    }

    @Test
    fun `rejects a txID that does not hash the raw data`() {
        val good = TronTx.transfer(amount = 5)
        val forged = good.replace(Regex("\"txID\":\"[0-9a-f]+\""), "\"txID\":\"${"00".repeat(32)}\"")
        val tx = TronTransactionJson.parse(forged)!!
        assertFalse(tx.isTxIdConsistent)
        assertEquals("txID does not match raw_data_hex", TronTransactionVerifier.verifyTransfer(tx, TronTx.OWNER, TronTx.TO, BigInteger.valueOf(5), 0, ""))
    }

    @Test
    fun `TRC10 and TRC20 transfers`() {
        val trc10 = TronTransactionJson.parse(TronTx.trc10(tokenId = "1002000", amount = 77))!!
        assertEquals("1002000", trc10.raw!!.contracts.single().assetName)
        assertNull(TronTransactionVerifier.verifyTransfer(trc10, TronTx.OWNER, TronTx.TO, BigInteger.valueOf(77), 1, "1002000"))
        assertEquals("token id mismatch", TronTransactionVerifier.verifyTransfer(trc10, TronTx.OWNER, TronTx.TO, BigInteger.valueOf(77), 1, "1000001"))

        val amount = BigInteger("123456789012345678901234567890")
        val trc20 = TronTransactionJson.parse(TronTx.trc20(amount = amount))!!
        assertNull(TronTransactionVerifier.verifyTransfer(trc20, TronTx.OWNER, TronTx.TO, amount, 2, TronTx.USDT))
        assertEquals("transfer data mismatch", TronTransactionVerifier.verifyTransfer(trc20, TronTx.OWNER, TronTx.TO, amount.add(BigInteger.ONE), 2, TronTx.USDT))
        assertEquals("token contract mismatch", TronTransactionVerifier.verifyTransfer(trc20, TronTx.OWNER, TronTx.TO, amount, 2, TronTx.TO))
        val greedy = TronTransactionJson.parse(TronTx.trc20(amount = amount, feeLimit = 1_000_000_000))!!
        assertEquals("unexpected fee limit", TronTransactionVerifier.verifyTransfer(greedy, TronTx.OWNER, TronTx.TO, amount, 2, TronTx.USDT))
    }

    @Test
    fun `TRC20 transfer data layout`() {
        val data = TronTransactionVerifier.trc20TransferData(TronAddressCodec.toHex41(TronTx.TO)!!, BigInteger.valueOf(1_000_000))
        assertEquals(8 + 64 + 64, data.length)
        assertTrue(data.startsWith("a9059cbb000000000000000000000000"))
        assertTrue(data.endsWith("00000000000f4240"))
    }

    @Test
    fun `staking transactions`() {
        val stake = TronTransactionJson.parse(TronTx.staking(54, "FreezeBalanceV2Contract", amount = 10_000_000, resource = 1))!!
        assertNull(TronTransactionVerifier.verifyStaking(stake, TronTx.OWNER, TronStakingOperation.STAKE, "", 10_000_000, forEnergy = true))
        assertEquals("resource mismatch", TronTransactionVerifier.verifyStaking(stake, TronTx.OWNER, TronStakingOperation.STAKE, "", 10_000_000, forEnergy = false))
        assertEquals("unexpected contract type", TronTransactionVerifier.verifyStaking(stake, TronTx.OWNER, TronStakingOperation.UNSTAKE, "", 10_000_000, true))

        val delegate = TronTransactionJson.parse(TronTx.staking(57, "DelegateResourceContract", amount = 5_000_000, resource = 0, receiver = TronTx.TO))!!
        assertNull(TronTransactionVerifier.verifyStaking(delegate, TronTx.OWNER, TronStakingOperation.DELEGATE, TronTx.TO, 5_000_000, false))
        assertEquals("receiver mismatch", TronTransactionVerifier.verifyStaking(delegate, TronTx.OWNER, TronStakingOperation.DELEGATE, TronTx.USDT, 5_000_000, false))

        val undelegate = TronTransactionJson.parse(TronTx.staking(58, "UnDelegateResourceContract", amount = 4_999_000, resource = 1, receiver = TronTx.TO))!!
        assertNull(TronTransactionVerifier.verifyStaking(undelegate, TronTx.OWNER, TronStakingOperation.UNDELEGATE, TronTx.TO, 5_000_000, true))

        val withdraw = TronTransactionJson.parse(TronTx.staking(56, "WithdrawExpireUnfreezeContract"))!!
        assertNull(TronTransactionVerifier.verifyStaking(withdraw, TronTx.OWNER, TronStakingOperation.WITHDRAW, "", 0, true))
    }

    @Test
    fun `walletconnect verdicts`() {
        val ok = TronTransactionJson.parse(TronTx.transfer(amount = 1))!!
        assertNull(TronTransactionVerifier.verifyForWalletConnect(ok, TronTx.OWNER))
        assertEquals("owner mismatch", TronTransactionVerifier.verifyForWalletConnect(ok, TronTx.TO))
        val perm = TronTransactionJson.parse(TronTx.permissionUpdate())!!
        assertEquals("permission update", TronTransactionVerifier.verifyForWalletConnect(perm, TronTx.OWNER))
        val signed = TronTransactionJson.parse(TronTx.signed(TronTx.transfer(amount = 1)))!!
        assertEquals(1, signed.signatures.size)
        assertEquals("already signed", TronTransactionVerifier.verifyForWalletConnect(signed, TronTx.OWNER))
    }

    @Test
    fun `malformed input`() {
        assertNull(TronTransactionJson.parse("not json"))
        val noHex = TronTransactionJson.parse("""{"txID":"00"}""")
        assertNotNull(noHex)
        assertNull(noHex.raw)
        assertNull(TronRawData.decodeOrNull(byteArrayOf(0x0a, 0x7f)))
    }

    @Test
    fun `base58 round trip keeps leading zeros`() {
        val bytes = byteArrayOf(0, 0, 1, 2, 3)
        assertEquals(bytes.toList(), Base58.decode(Base58.encode(bytes))!!.toList())
        assertEquals("11", Base58.encode(byteArrayOf(0, 0)))
        assertNull(Base58.decode("0OIl"))
    }
}
