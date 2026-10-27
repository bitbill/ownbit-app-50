// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.publicsigner.verify

import io.ownbit.core.crypto.util.Hex
import io.ownbit.core.publicsigner.testing.SigningVectors
import io.ownbit.core.publicsigner.model.str
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.test.runTest
import org.junit.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertTrue
import kotlin.time.Duration.Companion.seconds

/**
 * The signed-outpoint amount memory ([SignedOutpointMemory]) over an [InMemoryOutpointStore], and what [PsbtMaps] reads
 * for it ([PsbtMaps.outpoint], [PsbtMaps.claimedAmount], [PsbtMaps.prevoutKind]) on the golden witness-only PSBTs
 * (`O-BTC-6` BlueWallet shape, `O-BTC-7` legacy, `O-BTC-8` nested SegWit).
 */
class SignedOutpointMemoryTest {

    private val store = InMemoryOutpointStore()
    private var now = 1_000L
    private val memory = SignedOutpointMemory(store, Dispatchers.IO)

    private fun maps(id: String): PsbtMaps = PsbtMaps.parse(SignatureUrCodec.base64(SigningVectors.request(id).str("psbt")!!))

    @Test fun `key and tag derivation vectors`() {
        val txid = ByteArray(32) { 0x11 }
        val key0 = SignedOutpointMemory.key(txid, 0)
        assertEquals("485e7b262ee1424cf3667553bef3cceb", Hex.encode(key0))
        assertEquals("229e200c6ef2bb95bc68754029eb9400", Hex.encode(SignedOutpointMemory.key(txid, 1)))
        assertEquals("7a6186948d50d923eaeec24be8e29809", Hex.encode(SignedOutpointMemory.tag(key0, 100_000)))
        assertEquals("0f37f6a63f4287c326deb3c2c23b6b72", Hex.encode(SignedOutpointMemory.tag(key0, 100_001)))
    }

    @Test fun `PsbtMaps reads outpoints, claimed amounts and where they come from`() {
        val w1 = maps("O-BTC-6-segwit-witness-only")
        assertEquals(PsbtMaps.PrevoutKind.WITNESS_SEGWIT_V0, w1.prevoutKind(0))
        assertEquals(100_000L, w1.claimedAmount(0))
        assertFalse(w1.hasFullPrevTx(0))
        assertNotNull(w1.outpoint(0))
        assertEquals(PsbtMaps.PrevoutKind.WITNESS_LEGACY, maps("O-BTC-7-legacy-witness-only").prevoutKind(0))
        assertEquals(PsbtMaps.PrevoutKind.WITNESS_SEGWIT_V0, maps("O-BTC-8-nested-witness-only").prevoutKind(0))
        val full = maps("T8-flow-bitcoin-crypto-psbt")
        assertEquals(PsbtMaps.PrevoutKind.FULL_PREVIOUS_TX, full.prevoutKind(0))
        assertTrue(full.hasFullPrevTx(0))
        assertNotNull(full.claimedAmount(0))
        val two = maps("O-BTC-6-segwit-witness-only-2-inputs")
        assertEquals(listOf(PsbtMaps.PrevoutKind.WITNESS_SEGWIT_V0, PsbtMaps.PrevoutKind.WITNESS_SEGWIT_V0), two.inputs.indices.map(two::prevoutKind))
        assertFalse(two.outpoint(0) == two.outpoint(1))
        assertEquals(null, two.outpoint(5))
    }

    @Test fun `a remembered outpoint with another amount conflicts, the same amount does not`() = runTest(timeout = 30.seconds) {
        val w1 = maps("O-BTC-6-segwit-witness-only")
        assertEquals(emptyList(), memory.conflicts(w1), "nothing remembered yet")
        memory.record(w1, listOf(0))
        assertEquals(emptyList(), memory.conflicts(w1), "the same amount again")
        // The same outpoint claiming one satoshi more (only the witnessUtxo amount changes).
        val claimed = w1.claimedAmount(0)!!
        val bytes = SignatureUrCodec.base64(SigningVectors.request("O-BTC-6-segwit-witness-only").str("psbt")!!)
        val amountLe = Hex.encode(ByteArray(8) { i -> ((claimed ushr (8 * i)) and 0xFF).toByte() })
        val moreLe = Hex.encode(ByteArray(8) { i -> (((claimed + 1) ushr (8 * i)) and 0xFF).toByte() })
        val hex = Hex.encode(bytes)
        // Key 01 (PSBT_IN_WITNESS_UTXO), value length 0x1f (8-byte amount + P2WPKH script), then the amount.
        val at = hex.indexOf("01011f$amountLe")
        assertTrue(at > 0)
        val lying = PsbtMaps.parse(Hex.decode(hex.substring(0, at) + "01011f" + moreLe + hex.substring(at + 6 + 16)))
        assertEquals(claimed + 1, lying.claimedAmount(0))
        assertEquals(listOf(0), memory.conflicts(lying))
        // Nothing of the outpoint or the amount is stored in the clear.
        val rows = store.byKeys(listOf(Hex.encode(SignedOutpointMemory.key(w1.outpoint(0)!!.txid, w1.outpoint(0)!!.vout))))
        assertEquals(1, rows.size)
        assertFalse(Hex.encode(w1.outpoint(0)!!.txid) in rows.single().key + rows.single().tag)
    }

    @Test fun `at most 256 outpoints, the oldest go first`() = runTest(timeout = 60.seconds) {
        val w1 = maps("O-BTC-6-segwit-witness-only")
        memory.record(w1, listOf(0))
        val dao = store
        // 256 newer rows push it out.
        repeat(SignedOutpointMemory.CAPACITY) { i ->
            now += 1
            dao.record(listOf(OutpointRow("k$i", "t$i", now)), SignedOutpointMemory.CAPACITY)
        }
        assertEquals(SignedOutpointMemory.CAPACITY, dao.count())
        val k = Hex.encode(SignedOutpointMemory.key(w1.outpoint(0)!!.txid, w1.outpoint(0)!!.vout))
        assertTrue(dao.byKeys(listOf(k)).isEmpty())
    }

    /**
     * Eviction follows the order of signing, never the device clock — an offline phone's clock may go
     * back (no NTP, a reset after the battery ran flat, a manual date change). A full table stamped "later" must not
     * swallow every new outpoint.
     */
    @Test fun `a clock that went back never stops the memory from remembering`() = runTest(timeout = 60.seconds) {
        val dao = store
        val later = Long.MAX_VALUE / 4
        dao.record(List(SignedOutpointMemory.CAPACITY) { i -> OutpointRow("k$i", "t$i", later) }, SignedOutpointMemory.CAPACITY)
        val w1 = maps("O-BTC-6-segwit-witness-only")
        memory.record(w1, listOf(0))
        val k = Hex.encode(SignedOutpointMemory.key(w1.outpoint(0)!!.txid, w1.outpoint(0)!!.vout))
        assertEquals(1, dao.byKeys(listOf(k)).size, "the newest signature is remembered")
        assertEquals(SignedOutpointMemory.CAPACITY, dao.count())
        // And it conflicts at once with another amount for the same outpoint.
        assertEquals(emptyList(), memory.conflicts(w1))
    }

    /** One request may sign more inputs than [SignedOutpointMemory.CAPACITY] (several wallets): none of them is dropped. */
    @Test fun `a request with more inputs than the capacity keeps every one of them`() = runTest(timeout = 60.seconds) {
        val dao = store
        val big = SignedOutpointMemory.CAPACITY + 44
        dao.record(List(big) { i -> OutpointRow("k$i", "t$i", 0) }, SignedOutpointMemory.CAPACITY)
        assertEquals(big, dao.count(), "the request's own rows are never trimmed by itself")
        // The next request trims back to the capacity, keeping the newest.
        val w1 = maps("O-BTC-6-segwit-witness-only")
        memory.record(w1, listOf(0))
        assertEquals(SignedOutpointMemory.CAPACITY, dao.count())
        val k = Hex.encode(SignedOutpointMemory.key(w1.outpoint(0)!!.txid, w1.outpoint(0)!!.vout))
        assertEquals(1, dao.byKeys(listOf(k)).size)
        assertTrue(dao.byKeys(listOf("k${big - 1}")).isNotEmpty(), "the newest rows of the big request stay")
        assertTrue(dao.byKeys(listOf("k0")).isEmpty(), "its oldest go first")
    }

    /** Recording an outpoint again refreshes its place (it is the newest again). */
    @Test fun `recording an outpoint again makes it the newest`() = runTest(timeout = 60.seconds) {
        val dao = store
        val w1 = maps("O-BTC-6-segwit-witness-only")
        memory.record(w1, listOf(0))
        dao.record(List(SignedOutpointMemory.CAPACITY - 1) { i -> OutpointRow("k$i", "t$i", 0) }, SignedOutpointMemory.CAPACITY)
        memory.record(w1, listOf(0))
        dao.record(listOf(OutpointRow("new", "t", 0)), SignedOutpointMemory.CAPACITY)
        val k = Hex.encode(SignedOutpointMemory.key(w1.outpoint(0)!!.txid, w1.outpoint(0)!!.vout))
        assertEquals(1, dao.byKeys(listOf(k)).size, "refreshed, so k0 went instead")
        assertTrue(dao.byKeys(listOf("k0")).isEmpty())
    }
}
