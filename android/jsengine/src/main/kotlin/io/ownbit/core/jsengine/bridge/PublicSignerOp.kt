// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.jsengine.bridge

/**
 * Which page of the public-protocol engine an operation may run on. The page decides the isolation [PublicSignerJsBridge] applies:
 *
 * - [PAIRING]: the warm `JsBundle.PUBLIC_SIGNER_PAIRING` page. Only the device's own, unsealed and verified public
 *   index reaches it; never a seed, never a scanned / pasted request.
 * - [SECRET]: receives the wallet seed. A fresh `JsBundle.PUBLIC_SIGNER` page for exactly one call, discarded in
 *   `finally`.
 * - [UNTRUSTED]: receives a request from another wallet. A fresh page per request (`review` + `resolveSigningPlan` of
 *   the same request may share it), discarded afterwards.
 * - [SCAN]: one camera session (`scanBegin` + its `scanAdd` frames) owns a fresh page; any other isolated operation ends
 *   the session first; the page is discarded when the session ends.
 */
enum class PublicSignerPage { PAIRING, SECRET, UNTRUSTED, SCAN }

/**
 * The allowlist of engine operations Ownbit may send to `BitSignerEngine.dispatch`. [wire] is the exact
 * `"operation"` value; nothing else ever reaches the engine (`JsCallSiteGuardTest` rule 8, `PublicSignerOpTest`).
 *
 * Deliberately absent (the engine has them, Ownbit never calls them): `decodeQR` (`scanBegin` / `scanAdd` and
 * `decodePayload` cover it), `mnemonic`, `validateMnemonic`, `wordlist` (Ownbit passes the stored seed, never a phrase;
 * the engine's phrase path is English-only), `deriveAccounts`, `deriveBitcoinCosigner`, `validateBitcoinPolicy`,
 * `sign` (unplanned signing), `encodeQR`, `createPairing`, `createWalletPairing` / `deriveWalletPublic` (wallet-level
 * pairing is out of scope).
 */
enum class PublicSignerOp(val wire: String, val page: PublicSignerPage) {
    CAPABILITIES("capabilities", PublicSignerPage.PAIRING),
    DERIVE_PUBLIC_ADDRESSES("derivePublicAddresses", PublicSignerPage.PAIRING),
    CREATE_PUBLIC_PAIRING("createPublicPairing", PublicSignerPage.PAIRING),
    DERIVE_PUBLIC_INDEX("derivePublicIndex", PublicSignerPage.SECRET),
    SIGN_PLAN_TASK("signPlanTask", PublicSignerPage.SECRET),
    SCAN_BEGIN("scanBegin", PublicSignerPage.SCAN),
    SCAN_ADD("scanAdd", PublicSignerPage.SCAN),
    DECODE_PAYLOAD("decodePayload", PublicSignerPage.UNTRUSTED),
    REVIEW("review", PublicSignerPage.UNTRUSTED),
    RESOLVE_SIGNING_PLAN("resolveSigningPlan", PublicSignerPage.UNTRUSTED),
    ENCODE_RESPONSE("encodeResponse", PublicSignerPage.UNTRUSTED),
    ;

    /** `true` only for the two operations whose request carries the wallet seed. */
    val carriesSeed: Boolean get() = page == PublicSignerPage.SECRET
}
