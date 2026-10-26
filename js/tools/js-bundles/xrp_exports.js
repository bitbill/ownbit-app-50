//  tools/js-bundles/xrp_exports.js — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//  Fragment inserted into the shipped bundle by patch_xrp.js (newlines removed). The patch script strips these leading
//  "//" lines first, so the inserted bytes are exactly the shipped ones.
buildXrpTokenPaymentTxWithSeedHex:function(e,t){return bilTokenPayment(bilSeedKp(e),t)},buildXrpTokenPaymentTxWithPrivKey:function(e,t){return bilTokenPayment(bilPrivKp(e),t)},buildXrpTrustSetTxWithSeedHex:function(e,t){return bilTrustSet(bilSeedKp(e),t)},buildXrpTrustSetTxWithPrivKey:function(e,t){return bilTrustSet(bilPrivKp(e),t)},getPubAddrFromSeedHexIndex:function(e,t){var k=bilIndexKp(e,Number(t));return[k.publicKey,f.deriveAddress(k.publicKey)]},signXrpTxJsonWithSeedHexIndex:function(e,t,r){JSON.parse(r);return bilSign(r,bilIndexKp(e,Number(t)))},multiSignXrpTxJsonWithSeedHex:bilMultiSign,deriveAddressFromPubKey:function(e){bilNeed(/^0[23][0-9a-fA-F]{64}$/.test(e),"invalid public key");return f.deriveAddress(e)},
