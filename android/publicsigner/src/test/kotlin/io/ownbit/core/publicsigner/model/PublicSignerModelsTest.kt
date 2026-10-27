// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.publicsigner.model

import io.ownbit.core.publicsigner.model.BtcAddressType
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import org.junit.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertSame
import kotlin.test.assertTrue

/**
 * The public-protocol models read real engine output (`models/engine-samples.json`: the pinned bundle in Node on the
 * `abandon … about` wallet; see its `_provenance`) and fail closed on anything malformed.
 */
class PublicSignerModelsTest {

    private val samples: JsonObject = Json.parseToJsonElement(
        checkNotNull(javaClass.classLoader?.getResource("models/engine-samples.json")).readText(),
    ).jsonObject

    private fun sample(name: String): JsonObject = checkNotNull(samples[name]?.jsonObject) { name }

    // ---- enums --------------------------------------------------------------------------------------------------

    @Test fun `wire values are the engine's`() {
        assertEquals(listOf("bitcoin", "evm", "tron", "solana"), PsChain.entries.map { it.wire })
        assertEquals(PsChain.SOLANA, PsChain.fromWire("solana"))
        assertNull(PsChain.fromWire("Bitcoin"))
        assertEquals(
            listOf("taproot", "native", "nested", "legacy", "multisig-native", "multisig-nested"),
            PsBitcoinProfile.entries.map { it.wire },
        )
        assertEquals(listOf("standard", "trust", "legacy"), PsSolanaProfile.entries.map { it.wire })
        assertEquals(listOf("accountXpub", "wallet", "address"), PsOutputMode.entries.map { it.wire })
    }

    @Test fun `bitcoin profiles follow Ownbit's order and paths`() {
        // Order: Taproot, Native SegWit, Nested SegWit, Legacy; default Native.
        assertEquals(
            listOf(PsBitcoinProfile.TAPROOT, PsBitcoinProfile.NATIVE, PsBitcoinProfile.NESTED, PsBitcoinProfile.LEGACY),
            PsBitcoinProfile.singleSig,
        )
        assertEquals(PsBitcoinProfile.NATIVE, PsBitcoinProfile.DEFAULT)
        assertEquals(listOf(PsBitcoinProfile.MULTISIG_NATIVE, PsBitcoinProfile.MULTISIG_NESTED), PsBitcoinProfile.multisig)
        assertEquals("m/84'/0'/0'/0/0", PsBitcoinProfile.NATIVE.firstAddressPath)
        assertNull(PsBitcoinProfile.MULTISIG_NESTED.firstAddressPath)
        assertEquals(BtcAddressType.NATIVE_SEGWIT, PsBitcoinProfile.NATIVE.ownbitAddressType)
        assertEquals(BtcAddressType.TAPROOT, PsBitcoinProfile.TAPROOT.ownbitAddressType)
        assertNull(PsBitcoinProfile.MULTISIG_NATIVE.ownbitAddressType)
        assertEquals(
            listOf("m/86'/0'/0'", "m/84'/0'/0'", "m/49'/0'/0'", "m/44'/0'/0'", "m/48'/0'/0'/2'", "m/48'/0'/0'/1'"),
            PsBitcoinProfile.entries.map { it.accountPath },
        )
        assertEquals(listOf("m/44'/501'/0'/0'", "m/44'/501'/0'", "m/44'/501'"), PsSolanaProfile.entries.map { it.path })
        assertTrue(PsSolanaProfile.STANDARD.matchesOwnbit && !PsSolanaProfile.TRUST.matchesOwnbit)
        assertTrue(PsOutputMode.ACCOUNT_XPUB.bearsKey && PsOutputMode.WALLET.bearsKey && !PsOutputMode.ADDRESS.bearsKey)
        assertEquals(DecodeStatus.OPAQUE, DecodeStatus.fromWire("somethingNew"))
        assertEquals(RiskLevel.HIGH, RiskLevel.fromWire(null))
        assertEquals(PlanStatus.INVALID, PlanStatus.fromWire("brandNew"))
        assertEquals(
            listOf("ready", "noMatch", "missingSigner", "ambiguous", "setupRequired", "invalid"),
            PlanStatus.entries.map { it.wire },
        )
    }

    // ---- pairing selection ------------------------------------------------------------------------------------

    @Test fun `pairing selections are always engine-valid with the stated defaults`() {
        assertEquals(PairingSelection(PsChain.BITCOIN, PsBitcoinProfile.NATIVE, outputMode = PsOutputMode.ACCOUNT_XPUB), PairingSelection.DEFAULT)
        assertEquals(PsOutputMode.WALLET, PairingSelection.defaultFor(PsChain.EVM).outputMode)
        assertEquals(PsOutputMode.ADDRESS, PairingSelection.defaultFor(PsChain.TRON).outputMode)
        assertEquals(PsSolanaProfile.STANDARD, PairingSelection.defaultFor(PsChain.SOLANA).solanaProfile)
        assertEquals(PsOutputMode.WALLET, PairingSelection.defaultFor(PsChain.SOLANA).outputMode)
        assertEquals("native", PairingSelection.DEFAULT.profileWire)
        assertNull(PairingSelection.defaultFor(PsChain.EVM).profileWire)
        assertNull(PairingSelection.defaultFor(PsChain.TRON).profileWire)

        // Refused combinations (the engine would refuse them too).
        assertFailsWith<IllegalArgumentException> { PairingSelection(PsChain.TRON, outputMode = PsOutputMode.WALLET) }
        assertFailsWith<IllegalArgumentException> {
            PairingSelection(PsChain.BITCOIN, PsBitcoinProfile.MULTISIG_NATIVE, outputMode = PsOutputMode.ADDRESS)
        }
        assertFailsWith<IllegalArgumentException> { PairingSelection(PsChain.EVM, outputMode = PsOutputMode.ACCOUNT_XPUB) }

        // Switching keeps what still applies and falls back to the default mode otherwise.
        val btcAddress = PairingSelection.DEFAULT.withOutputMode(PsOutputMode.ADDRESS)
        assertEquals(PsOutputMode.ADDRESS, btcAddress.outputMode)
        assertEquals(PsOutputMode.ACCOUNT_XPUB, btcAddress.withBitcoinProfile(PsBitcoinProfile.MULTISIG_NESTED).outputMode)
        assertEquals(PsOutputMode.ADDRESS, btcAddress.withChain(PsChain.EVM).outputMode)
        assertEquals(PsOutputMode.ADDRESS, btcAddress.withChain(PsChain.TRON).outputMode)
        val evmWallet = PairingSelection.defaultFor(PsChain.EVM)
        assertEquals(PsOutputMode.ACCOUNT_XPUB, evmWallet.withChain(PsChain.BITCOIN).outputMode)
        assertSame(evmWallet, evmWallet.withOutputMode(PsOutputMode.ACCOUNT_XPUB), "a mode that does not apply is ignored")
        // Profiles survive a round trip through another chain.
        val trust = PairingSelection.defaultFor(PsChain.SOLANA).withSolanaProfile(PsSolanaProfile.TRUST)
        assertEquals(PsSolanaProfile.TRUST, trust.withChain(PsChain.EVM).withChain(PsChain.SOLANA).solanaProfile)

        assertEquals(listOf(PsOutputMode.ACCOUNT_XPUB), PairingSelection.modesFor(PsChain.BITCOIN, PsBitcoinProfile.MULTISIG_NATIVE))
        assertEquals(listOf(PsOutputMode.ADDRESS), PairingSelection.modesFor(PsChain.TRON))
        assertTrue(trust.outsideOwnbitPaths)
        assertTrue(PairingSelection(PsChain.BITCOIN, PsBitcoinProfile.MULTISIG_NATIVE).outsideOwnbitPaths)
        assertFalse(PairingSelection.DEFAULT.outsideOwnbitPaths)
        assertTrue(PairingSelection.DEFAULT.bearsKey)
        assertFalse(PairingSelection.defaultFor(PsChain.TRON).bearsKey)
    }

    // ---- pairing QR ---------------------------------------------------------------------------------------------

    @Test fun `pairing results read with their payload view`() {
        val native = PublicPairingQr.fromEngine(sample("pairing_btcNative"), PairingSelection.DEFAULT, "73c5da0a", sameAsOwnbit = true)
        assertEquals("crypto-account", native.type)
        assertEquals(1, native.frames.size)
        assertTrue(native.frames.single().startsWith("UR:CRYPTO-ACCOUNT/"))
        assertEquals("bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu", native.address)
        assertEquals("m/84'/0'/0'", native.path)
        assertEquals("73C5DA0A", native.displayFingerprint)
        assertTrue(native.bearsKey && native.sameAsOwnbit && !native.isAnimated)
        assertEquals("Public account key. Receive and change addresses can be derived.", native.engineNote)
        val view = assertNotNull(native.payload)
        assertEquals(PublicPayloadView.Format.JSON, view.format)
        assertEquals(160, view.byteCount)
        assertEquals("crypto-account", view.qrType)
        assertTrue(view.isUr && !view.isPsbt)
        // Pretty, key-sorted, 2-space JSON: "master-fingerprint" sorts before "output-descriptors".
        assertTrue(view.text.startsWith("{\n  \"master-fingerprint\": 1942346250,\n  \"output-descriptors\": ["), view.text)

        val address = PublicPairingQr.fromEngine(
            sample("pairing_btcAddress"), PairingSelection.DEFAULT.withOutputMode(PsOutputMode.ADDRESS), "73C5DA0A", sameAsOwnbit = true,
        )
        assertEquals(listOf("bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu"), address.frames)
        assertEquals("m/84'/0'/0'/0/0", address.path)
        assertEquals("73c5da0a", address.masterFingerprint)
        assertFalse(address.bearsKey)
        assertEquals(PublicPayloadView(PublicPayloadView.Format.TEXT, address.address, 42, "address"), address.payload)

        val evm = PublicPairingQr.fromEngine(sample("pairing_evmWallet"), PairingSelection.defaultFor(PsChain.EVM), "73c5da0a", true)
        assertEquals("crypto-hdkey", evm.type)
        assertEquals("0x9858EfFD232B4033E47d90003D41EC34EcaEda94", evm.address)
        assertEquals("m/44'/60'/0'", evm.path)

        val tron = PublicPairingQr.fromEngine(sample("pairing_tron"), PairingSelection.defaultFor(PsChain.TRON), "73c5da0a", true)
        assertEquals("TUEZSdKsoDHQMeZwihtdoBiN46zxhGWYdH", tron.text)

        val sol = PublicPairingQr.fromEngine(sample("pairing_solWallet"), PairingSelection.defaultFor(PsChain.SOLANA), "73c5da0a", true)
        assertEquals("crypto-multi-accounts", sol.type)
        assertEquals("HAgk14JpMQLgt6rVgv7cBQFJWFto5Dqxi472uT3DKpqk", sol.address)

        val cosigner = PublicPairingQr.fromEngine(
            sample("pairing_btcCosigner"), PairingSelection(PsChain.BITCOIN, PsBitcoinProfile.MULTISIG_NATIVE), "73c5da0a", false,
        )
        assertEquals("m/48'/0'/0'/2'", cosigner.path)
        assertTrue(cosigner.engineNote!!.startsWith("Cosigner account key only."))
    }

    @Test fun `a pairing result that is not what was asked for is refused`() {
        val native = sample("pairing_btcNative")
        val taproot = PairingSelection.DEFAULT.withBitcoinProfile(PsBitcoinProfile.TAPROOT)
        assertEquals("pairing.profile", assertFailsWith<MalformedEngineResultException> { PublicPairingQr.fromEngine(native, taproot, "73c5da0a", false) }.what)
        val asAddress = PairingSelection.DEFAULT.withOutputMode(PsOutputMode.ADDRESS)
        assertEquals("pairing.outputMode", assertFailsWith<MalformedEngineResultException> { PublicPairingQr.fromEngine(native, asAddress, "73c5da0a", false) }.what)
        val noFrames = JsonObject(native + ("frames" to JsonArray(emptyList())))
        assertEquals("pairing.frames", assertFailsWith<MalformedEngineResultException> { PublicPairingQr.fromEngine(noFrames, PairingSelection.DEFAULT, "73c5da0a", false) }.what)
        assertFailsWith<MalformedEngineResultException> { PublicPairingQr.fromEngine(native, PairingSelection.DEFAULT, "73c5da", false) }
        // The exception message names the part only (safe to log), never payload content.
        val message = assertFailsWith<MalformedEngineResultException> { PublicPairingQr.fromEngine(noFrames, PairingSelection.DEFAULT, "73c5da0a", false) }.message!!
        assertEquals("Malformed engine result: pairing.frames", message)
    }

    @Test fun `the EVM address export at index N has the engine's address shape`() {
        val selection = PairingSelection.defaultFor(PsChain.EVM).withOutputMode(PsOutputMode.ADDRESS)
        val qr = PublicPairingQr.addressOnly(
            selection, "0x6Fac4D18c912343BF86fa7049364Dd4E424Ab9C0", "m/44'/60'/0'/0/1", addressIndex = 1, "73C5DA0A", sameAsOwnbit = true,
        )
        assertEquals(listOf("0x6Fac4D18c912343BF86fa7049364Dd4E424Ab9C0"), qr.frames)
        assertEquals("address", qr.type)
        assertEquals(1, qr.addressIndex)
        assertEquals(42, qr.payload!!.byteCount)
        assertFalse(qr.bearsKey)
        assertFailsWith<IllegalArgumentException> {
            PublicPairingQr.addressOnly(PairingSelection.defaultFor(PsChain.EVM), "0x1", "m", 0, "73c5da0a", false)
        }
        // The card's path is the exported address's own path.
        assertFailsWith<IllegalArgumentException> {
            PublicPairingQr.addressOnly(selection, "0x6Fac4D18c912343BF86fa7049364Dd4E424Ab9C0", "m/44'/60'/0'/0/0", 1, "73c5da0a", true)
        }
    }

    @Test fun `TRON exports address N in Ownbit's TRON scheme and key exports carry no index`() {
        // Round 2: TRON #0 = m/44'/195'/0'/0/0, #N >= 1 = Ownbit's TRX path (the ETH key m/44'/60'/0'/0/N).
        val tron = PairingSelection.defaultFor(PsChain.TRON)
        assertEquals(0, PublicPairingQr.fromEngine(sample("pairing_tron"), tron, "73c5da0a", true).addressIndex)
        assertEquals("m/44'/195'/0'/0/0", PublicPairingQr.tronPath(0))
        assertEquals("m/44'/60'/0'/0/1", PublicPairingQr.tronPath(1))
        val ownbit1 = PublicPairingQr.addressOnly(tron, "TL9gR3f4FgNa9VZAsPt6xuKXPrfWAUJ5MW", "m/44'/60'/0'/0/1", 1, "73c5da0a", false)
        assertEquals(1, ownbit1.addressIndex)
        // BitSigner's standard #1 is not an address of this scheme.
        assertFailsWith<IllegalArgumentException> {
            PublicPairingQr.addressOnly(tron, "TSeJkUh4Qv67VNFwY8LaAxERygNdy6NQZK", "m/44'/195'/0'/0/1", 1, "73c5da0a", false)
        }
        // An engine TRON export of another index than asked is refused, and the standard path for #1 too.
        val standardAt1 = JsonObject(sample("pairing_tron") + ("path" to JsonPrimitive("m/44'/195'/0'/0/1")))
        assertEquals("pairing.path", assertFailsWith<MalformedEngineResultException> { PublicPairingQr.fromEngine(standardAt1, tron, "73c5da0a", true) }.what)
        assertEquals("pairing.path", assertFailsWith<MalformedEngineResultException> { PublicPairingQr.fromEngine(standardAt1, tron, "73c5da0a", true, addressIndex = 1) }.what)
        val ownbitAt1 = JsonObject(sample("pairing_tron") + ("path" to JsonPrimitive("m/44'/60'/0'/0/1")))
        assertEquals(1, PublicPairingQr.fromEngine(ownbitAt1, tron, "73c5da0a", false, addressIndex = 1).addressIndex)
        assertEquals("pairing.path", assertFailsWith<MalformedEngineResultException> { PublicPairingQr.fromEngine(ownbitAt1, tron, "73c5da0a", true) }.what)
        // The engine exports EVM index 0 only: a result read as #N would show the wrong address.
        val evmAddress = PairingSelection.defaultFor(PsChain.EVM).withOutputMode(PsOutputMode.ADDRESS)
        val evmAt0 = buildJsonObject {
            put("type", "address"); put("text", "0x9858EfFD232B4033E47d90003D41EC34EcaEda94"); put("address", "0x9858EfFD232B4033E47d90003D41EC34EcaEda94")
            put("path", "m/44'/60'/0'/0/0"); put("profile", "standard"); put("outputMode", "address")
            putJsonArray("frames") { add(JsonPrimitive("0x9858EfFD232B4033E47d90003D41EC34EcaEda94")) }
        }
        assertEquals(0, PublicPairingQr.fromEngine(evmAt0, evmAddress, "73c5da0a", true).addressIndex)
        assertEquals("pairing.path", assertFailsWith<MalformedEngineResultException> {
            PublicPairingQr.fromEngine(evmAt0, evmAddress, "73c5da0a", true, addressIndex = 2)
        }.what)
        // Key exports are account nodes: never an address index.
        assertFailsWith<IllegalArgumentException> {
            PublicPairingQr.fromEngine(sample("pairing_evmWallet"), PairingSelection.defaultFor(PsChain.EVM), "73c5da0a", true, addressIndex = 3)
        }
    }

    // ---- scan -----------------------------------------------------------------------------------------------------

    @Test fun `scan statuses read complete and partial`() {
        val done = ScanProgress.fromEngine(sample("scan_evm"), parts = 1)
        assertTrue(done.complete)
        assertEquals(1f, done.progress)
        assertEquals(PsChain.EVM, done.chain)
        assertEquals("eth-sign-request", done.transportType)
        val psbt = ScanProgress.fromEngine(sample("scan_psbt"), parts = 1)
        assertEquals(PsChain.BITCOIN, psbt.chain)
        assertEquals("psbt-base64", psbt.transportType)

        val partial = ScanProgress.fromEngine(buildJsonObject { put("complete", false); put("progress", 0.4) }, parts = 3)
        assertFalse(partial.complete)
        assertEquals(0.4f, partial.progress)
        assertEquals(3, partial.parts)
        assertNull(partial.request)
        assertEquals(1f, ScanProgress.fromEngine(buildJsonObject { put("complete", false); put("progress", 7) }, 1).progress)
        assertEquals(0f, ScanProgress.fromEngine(buildJsonObject { put("complete", false) }, 0).progress)
        assertEquals(0f, ScanProgress.fromEngine(buildJsonObject { put("complete", false); put("progress", "0.5") }, 0).progress)

        assertEquals("scan.complete", assertFailsWith<MalformedEngineResultException> { ScanProgress.fromEngine(buildJsonObject { put("complete", "true") }, 1) }.what)
        assertEquals("scan.request", assertFailsWith<MalformedEngineResultException> { ScanProgress.fromEngine(buildJsonObject { put("complete", true) }, 1) }.what)
        val unknownChain = buildJsonObject { put("complete", true); put("request", buildJsonObject { put("chain", "cosmos") }) }
        assertEquals("scan.request.chain", assertFailsWith<MalformedEngineResultException> { ScanProgress.fromEngine(unknownChain, 1) }.what)
    }

    // ---- plan / review --------------------------------------------------------------------------------------------

    @Test fun `a ready plan reads its tasks and review`() {
        val raw = sample("plan_ready")
        val plan = PublicPlan.fromEngine(raw)
        assertTrue(plan.isReady)
        assertEquals(PsChain.EVM, plan.chain)
        assertEquals("a05ea69096eb986f75275407e4749ca938511775d67fed164e44f237d67efa57", plan.requestHash)
        assertEquals("fcfd49808c47be04fb89a92a48224691cafe01589555ef95b7133c7a15392475", plan.planHash)
        assertEquals("eth-sign-request", plan.protocolProfile)
        assertSame(raw, plan.raw, "the plan is passed back to signPlanTask unchanged")
        val task = plan.tasks.single()
        assertEquals("w1", task.localWalletId)
        assertEquals("95f7c3fcf6b598ef252e4ee3857f84e712d3264719314d8ccc1bbeceed2d9a34", task.walletKeyId)
        assertEquals(listOf("m/44'/60'/0'/0/0"), task.displayPaths)
        assertEquals(listOf("0x9858EfFD232B4033E47d90003D41EC34EcaEda94"), task.displayAddresses)
        assertEquals("ECDSA secp256k1", task.signatureAlgorithm)
        assertNull(task.signerSlot)
        assertEquals(listOf("w1"), plan.walletIds)
        assertSame(task, plan.task(task.id))

        val review = assertNotNull(plan.review)
        assertEquals("Sign Ethereum message", review.title)
        assertEquals(DecodeStatus.FULLY_DECODED, review.decodeStatus)
        assertEquals(RiskLevel.HIGH, review.riskLevel)
        assertTrue(review.requiresAcknowledgement, "high risk needs consent")
        assertEquals(ReviewNetwork("1", "Ethereum", "ETH"), review.network)
        assertEquals("Ethereum", review.networkName)
        assertEquals(5, review.fields.size)
        assertEquals(listOf(0, 1, 2, 3, 4), review.fields.map { it.index })
        assertEquals("Exact message bytes", review.fields.last().label)
        assertEquals(1, review.warnings.size)
        assertEquals("Sign Message", review.display?.action)

        val btc = PublicPlan.fromEngine(sample("plan_psbt"))
        assertEquals(PsChain.BITCOIN, btc.chain)
        assertEquals(listOf(0), btc.tasks.single().inputs)
        assertEquals("Send", btc.review!!.display!!.action)
        assertEquals("0.0009", btc.review!!.display!!.amount)
        // Every engine warning is kept, in order (none is dropped).
        assertEquals(2, btc.review!!.warnings.size)
        assertTrue(btc.review!!.warnings[1].startsWith("HIGH FEE:"))
    }

    @Test fun `failed plans keep their status, message and review`() {
        val noMatch = PublicPlan.fromEngine(sample("plan_noMatch"))
        assertEquals(PlanStatus.NO_MATCH, noMatch.status)
        assertEquals("No matching wallet", noMatch.message)
        assertTrue(noMatch.tasks.isEmpty())
        assertNull(noMatch.planHash)
        assertEquals("Sign Ethereum message", noMatch.review?.title)
        assertEquals(PsChain.EVM, noMatch.chain)
        assertEquals(PlanStatus.SETUP_REQUIRED, PublicPlan.fromEngine(sample("plan_setup")).status)
        val invalid = PublicPlan.fromEngine(buildJsonObject { put("version", 1); put("status", "invalid"); put("message", "x"); putJsonArray("tasks") {} })
        assertEquals(PlanStatus.INVALID, invalid.status)
        assertNull(invalid.review)
    }

    @Test fun `a malformed ready plan is refused`() {
        val raw = sample("plan_ready")
        fun broken(vararg change: Pair<String, kotlinx.serialization.json.JsonElement>) = JsonObject(raw + change)
        fun whatOf(json: JsonObject) = assertFailsWith<MalformedEngineResultException> { PublicPlan.fromEngine(json) }.what

        assertEquals("plan.planHash", whatOf(JsonObject(raw - "planHash")))
        assertEquals("plan.planHash", whatOf(broken("planHash" to JsonPrimitive("abc"))))
        assertEquals("plan.requestHash", whatOf(broken("requestHash" to JsonPrimitive(42))))
        assertEquals("plan.version", whatOf(broken("version" to JsonPrimitive(2))))
        assertEquals("plan.chain", whatOf(broken("chain" to JsonPrimitive("cosmos"))))
        assertEquals("plan.tasks", whatOf(broken("tasks" to JsonArray(emptyList()))))
        assertEquals("plan.tasks", whatOf(JsonObject(raw - "tasks")))
        val task = raw["tasks"]!! as JsonArray
        assertEquals("plan.task.id", whatOf(broken("tasks" to JsonArray(task + task))))
        assertEquals("plan.review", whatOf(JsonObject(raw - "review")))
        val otherReview = JsonObject(raw["review"]!!.jsonObject + ("requestHash" to JsonPrimitive("0".repeat(64))))
        assertEquals("plan.review", whatOf(broken("review" to otherReview)))
        val oneTask = task.single().jsonObject
        fun withTask(vararg change: Pair<String, kotlinx.serialization.json.JsonElement>) =
            broken("tasks" to JsonArray(listOf(JsonObject(oneTask + change))))
        assertEquals("task.walletKeyId", whatOf(withTask("walletKeyId" to JsonPrimitive("95f7"))))
        assertEquals("task.publicKeys", whatOf(withTask("publicKeys" to JsonArray(emptyList()))))
        assertEquals("task.paths", whatOf(withTask("paths" to JsonArray(emptyList()))))
        assertEquals("plan.task.chain", whatOf(withTask("chain" to JsonPrimitive("tron"))))
        // What is shown is what is signed: the review is of the plan's chain, and every task signs the plan's digest.
        val tronReview = JsonObject(raw["review"]!!.jsonObject + ("chain" to JsonPrimitive("tron")))
        assertEquals("plan.review.chain", whatOf(broken("review" to tronReview)))
        assertEquals("plan.signingBytesDigest", whatOf(JsonObject(raw - "signingBytesDigest")))
        assertEquals("plan.signingBytesDigest", whatOf(broken("signingBytesDigest" to JsonPrimitive("8d63"))))
        assertEquals("plan.task.signingBytesDigest", whatOf(withTask("signingBytesDigest" to JsonPrimitive("0".repeat(64)))))
        assertEquals(
            "8d632f824a7373c9edd31d7d39e6ecef7cb47708b0366f64e12384d0f3f95ebd",
            PublicPlan.fromEngine(broken("signingBytesDigest" to JsonPrimitive("8D632F824A7373C9EDD31D7D39E6ECEF7CB47708B0366F64E12384D0F3F95EBD"))).signingBytesDigest,
        )
        // A non-ready plan never carries tasks.
        assertEquals("plan.tasks", whatOf(JsonObject(sample("plan_noMatch") + ("tasks" to task))))
    }

    @Test fun `review texts are kept whole and statuses fail closed`() {
        val review = PublicReview.fromEngine(
            buildJsonObject {
                put("chain", "solana")
                putJsonArray("fields") {
                    add(buildJsonObject { put("label", "Instruction 2 · Recipient"); put("value", "x".repeat(5000)) })
                    add(buildJsonObject { put("label", "Count"); put("value", 3) })
                    add(JsonPrimitive("not a field"))
                }
                putJsonArray("warnings") { add(JsonPrimitive("w1")); add(JsonPrimitive("w2")) }
                put("decodeStatus", "notKnown")
            },
        )
        assertEquals(5000, review.fields[0].value.length, "values are never cut")
        assertEquals("Instruction 2", review.fields[0].group)
        assertEquals("Recipient", review.fields[0].shortLabel)
        assertEquals("3", review.fields[1].value)
        assertNull(review.fields[1].group)
        assertEquals(2, review.fields.size)
        assertEquals(listOf("w1", "w2"), review.warnings)
        assertEquals(DecodeStatus.OPAQUE, review.decodeStatus)
        assertEquals(RiskLevel.HIGH, review.riskLevel)
        assertTrue(review.requiresAcknowledgement)
        assertFalse(review.canSign)
        assertEquals("Solana", review.networkName)
        assertNull(review.display)
        assertNull(PublicReview.fromEngine(buildJsonObject { put("chain", "tron2") }).chain)
    }

    @Test fun `NFT display keys are bounded and read only with a known kind`() {
        val longLine = "1 ".repeat(200) + "to 0xRecipient (unrecognised recipient)"
        val give = (1..40).map { "item $it" }
        val raw = buildJsonObject {
            put("action", "Approve All NFTs")
            put("headline", "Seaport order for NFT #123")
            put("assetKind", "nftOrder")
            put("assetContract", "0xabc")
            put("tokenId", "123")
            putJsonArray("give") { give.forEach { add(JsonPrimitive(it)) } }
            putJsonArray("receive") { add(JsonPrimitive(longLine)); add(JsonPrimitive("  ")) }
            putJsonArray("others") { add(JsonPrimitive("a")); add(JsonPrimitive(5)) }
            put("assetContractLabel", "c".repeat(301))
        }
        val display = assertNotNull(PublicReviewDisplay.fromEngine(raw))
        assertEquals(ReviewAssetKind.NFT_ORDER, display.assetKind)
        assertEquals(31, display.give.lines.size)
        assertEquals(9, display.give.more)
        assertEquals(1, display.receive.lines.size, "blank lines are dropped")
        assertEquals(300, display.receive.lines.single().length)
        assertTrue(display.receive.lines.single().endsWith("(unrecognised recipient)") && "…" in display.receive.lines.single())
        assertTrue(display.others.isEmpty, "a list with a non-string is ignored whole")
        assertNull(display.assetContractLabel, "an over-long identifier is dropped, never cut")
        assertNull(display.summaryTokenId, "the headline already shows #123")
        assertTrue(display.showsAssetBox)
        assertEquals(
            listOf(PublicReviewDisplay.FlowKind.GIVE, PublicReviewDisplay.FlowKind.RECEIVE),
            display.flowSections.map { it.first },
        )

        // Unknown kind: no NFT key at all (fail closed), the original keys stay.
        val unknown = assertNotNull(PublicReviewDisplay.fromEngine(JsonObject(raw + ("assetKind" to JsonPrimitive("rwa")))))
        assertNull(unknown.assetKind)
        assertNull(unknown.assetContract)
        assertNull(unknown.tokenId)
        assertTrue(unknown.give.isEmpty && unknown.flowSections.isEmpty())
        assertEquals("Seaport order for NFT #123", unknown.headline)
        assertNull(PublicReviewDisplay.fromEngine(buildJsonObject { put("action", 1) }))
        assertNull(PublicReviewDisplay.fromEngine(null))

        assertTrue(PublicReviewDisplay.textShowsTokenId("Send NFT #1234", "1234"))
        assertFalse(PublicReviewDisplay.textShowsTokenId("Send NFT #12345", "1234"))
        assertTrue(PublicReviewDisplay.textShowsTokenId("#12345 and #1234.", "1234"))
        assertFalse(PublicReviewDisplay.textShowsTokenId("Give 2 items", ""))
        // A long line of emoji (surrogate pairs) is never cut inside a pair.
        val cut = PublicReviewDisplay.boundedLine("😀".repeat(200))
        assertTrue(cut.length <= PublicReviewDisplay.MAX_STRING_LENGTH)
        assertFalse(hasLoneSurrogate(cut), "lone surrogate in the cut line")
    }

    private fun hasLoneSurrogate(text: String): Boolean = text.indices.any { i ->
        val c = text[i]
        (c.isHighSurrogate() && (i + 1 >= text.length || !text[i + 1].isLowSurrogate())) ||
            (c.isLowSurrogate() && (i == 0 || !text[i - 1].isHighSurrogate()))
    }

    // ---- result / response ----------------------------------------------------------------------------------------

    @Test fun `sign results and response QR codes read`() {
        val result = PublicSignResult.fromEngine(sample("result_evm"))
        assertEquals(PsChain.EVM, result.chain)
        assertEquals("b06e4a4c057660dd15f68196328d17caf422032d0edbeba1acda1797f5fe74b2", result.taskId)
        assertEquals(listOf(result.taskId), result.completedTaskIds)
        assertSame(sample("result_evm"), result.raw)
        assertEquals("result.completedTaskIds", assertFailsWith<MalformedEngineResultException> {
            PublicSignResult.fromEngine(JsonObject(sample("result_evm") + ("completedTaskIds" to JsonArray(listOf(JsonPrimitive("other"))))))
        }.what)
        assertEquals("result.planHash", assertFailsWith<MalformedEngineResultException> {
            PublicSignResult.fromEngine(JsonObject(sample("result_evm") - "planHash"))
        }.what)
        assertEquals(PsChain.BITCOIN, PublicSignResult.fromEngine(sample("result_psbt")).chain)

        val evm = PublicResponseQr.fromEngine(sample("response_evm"))
        assertEquals("eth-signature", evm.type)
        assertTrue(evm.frames.single().startsWith("UR:ETH-SIGNATURE/"))
        assertFalse(evm.isAnimated || evm.isPsbt)
        assertEquals(89, evm.payload!!.byteCount)
        assertTrue("\"request-id\"" in evm.payload!!.text)

        val psbt = PublicResponseQr.fromEngine(sample("response_psbt"))
        assertEquals("psbt-base64", psbt.type)
        assertTrue(psbt.isPsbt && psbt.payload!!.isPsbt && !psbt.payload!!.isUr)
        assertTrue(psbt.text.startsWith("cHNidP"))

        assertFailsWith<MalformedEngineResultException> { PublicResponseQr.fromEngine(JsonObject(sample("response_evm") - "frames")) }
        val bbqr = PublicPayloadView.fromEngine(
            buildJsonObject {
                put("type", "bbqr-psbt"); put("payloadFormat", "hex"); put("payload", "70736274ff"); put("payloadBytes", 5)
                putJsonArray("frames") { add(JsonPrimitive("B\$HP0100ABCD")) }
            },
        )
        assertEquals("H", bbqr?.bbqrEncoding)
        assertNull(PublicPayloadView.fromEngine(buildJsonObject { put("payloadFormat", "json"); put("payload", "not an object") }))
        assertNull(PublicPayloadView.fromEngine(buildJsonObject { put("payloadFormat", "xml") }))
    }

}
