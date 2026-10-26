//  tools/btc-taproot-js/process-shim.js — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT

// esbuild --inject: readable-stream (via wif -> bs58check -> create-hash) references a global `process`
export { default as process } from 'process/browser.js';
