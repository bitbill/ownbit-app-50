// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.chain.utxo

import io.ownbit.core.chain.json.looseLong
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/**
 * The ZEC v5 fields of a sign-data JSON (iOS `BILZecNetwork.v5SignFields()`): the ZEC bundle
 * signs a v5 transaction only when `zecTxVersion == 5` (`Number(data.zecTxVersion) === 5`), with the consensus
 * branch id, expiry height and lock time given here; without them it signs v4 as before.
 *
 * Normal sends merge them into `signDatas` at build time; a multisig **initiator** adds them to a new proposal when
 * proposals are v5; co-signers and offline signers copy them from the proposal ([carry]) and never decide themselves.
 */
object ZecSignFields {
    const val TX_VERSION: String = "zecTxVersion"
    const val BRANCH_ID: String = "zecBranchId"
    const val EXPIRY_HEIGHT: String = "zecExpiryHeight"
    const val LOCK_TIME: String = "zecLockTime"

    /** All four keys, in iOS order. */
    val KEYS: List<String> = listOf(TX_VERSION, BRANCH_ID, EXPIRY_HEIGHT, LOCK_TIME)

    /** `{"zecTxVersion":5,"zecBranchId":<decimal>,"zecExpiryHeight":0,"zecLockTime":0}` (no expiry, no lock, as v4). */
    fun v5(branchId: Long): JsonObject = buildJsonObject {
        put(TX_VERSION, 5)
        put(BRANCH_ID, branchId)
        put(EXPIRY_HEIGHT, 0)
        put(LOCK_TIME, 0)
    }

    /** [signDatas] with [fields] merged on top (iOS `merge { _, new in new }`). */
    fun merge(signDatas: JsonObject, fields: JsonObject?): JsonObject =
        if (fields == null || fields.isEmpty()) signDatas else JsonObject(signDatas + fields)

    /** The transaction version [signDatas] asks the bundle for: 5 with `zecTxVersion == 5`, else 4. */
    fun txVersion(signDatas: JsonObject): Int = if (signDatas[TX_VERSION].looseLong() == 5L) 5 else 4

    /** The `zec*` fields present in a stored proposal's sign data, unchanged (co-signing follows the proposal). */
    fun carry(from: JsonObject): Map<String, JsonElement> = KEYS.mapNotNull { k -> from[k]?.let { k to it } }.toMap()

    /**
     * The bundle's optional v4 consensus branch id `data.consensusBranchIdOverride`, a uint32
     * JSON number. **JS only** — never part of [KEYS] / [carry], never in a server request or a QR.
     */
    const val V4_BRANCH_OVERRIDE: String = "consensusBranchIdOverride"

    /**
     * The v4 consensus branch id built into the shipped ZEC bundle (`networks.zcash.consensusBranchId[4]`, NU6.3, from
     * block 3,428,143; `zcashjs-lib-app-0251.js`, md5 `a395a6fd…`, pinned by `JsBundleIntegrityTest`). Revisit together
     * with the bundle.
     */
    const val BUNDLE_V4_BRANCH_ID: Long = 0x37a5165bL

    /**
     * The copy of [signDatas] handed to the ZEC bundle (iOS `ZcashJSBridge.withV4BranchOverride`): any incoming
     * [V4_BRANCH_OVERRIDE] is removed first (a server answer or a scanned QR never chooses it; co-signers
     * ignore it; iOS does not strip), then [override] is added for **v4** data only ([txVersion] 4) — v5 data carries its
     * branch in `zecBranchId`.
     *
     * An [override] equal to [BUNDLE_V4_BRANCH_ID] is not passed: the bundle signs with that id anyway, and the shipped
     * bundle rejects any override on its private-key and multisig paths (`ECPair.fromWIF(wif, networks.zcash)` vs the
     * copied network → "Inconsistent network"; reported to iOS). The signatures are the same as iOS's whenever iOS's
     * succeed; a different [override] is still passed (the seed path honours it; the two other paths then fail locally
     * instead of signing with a branch the node rejects).
     *
     * @param override [io.ownbit.core.data.zec.ZecNetworkSnapshot.v4BranchIdOverride] (NU7 id, else getConfig2
     *   `zecBranchId`, else `null` = the bundle's own id).
     */
    fun withV4BranchOverride(signDatas: JsonObject, override: Long?): JsonObject {
        val stripped = if (V4_BRANCH_OVERRIDE in signDatas) JsonObject(signDatas - V4_BRANCH_OVERRIDE) else signDatas
        if (override == null || override == BUNDLE_V4_BRANCH_ID || txVersion(stripped) != 4) return stripped
        return JsonObject(stripped + (V4_BRANCH_OVERRIDE to JsonPrimitive(override)))
    }
}
