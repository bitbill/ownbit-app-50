//  tools/btc-taproot-js/buffer-shim.js — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT

// esbuild --inject: bitcoinjs-lib / bip32 / ecpair expect a global Buffer (WKWebView has none)
export { Buffer } from 'buffer';
