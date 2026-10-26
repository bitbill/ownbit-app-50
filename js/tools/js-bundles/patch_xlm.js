//  tools/js-bundles/patch_xlm.js — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//  Usage: node patch_xlm.js <original bundle> <patched bundle>  (see js/README.md, "Reproducing the patched XRP / XLM bundles")

const fs=require('fs');
let s=fs.readFileSync(process.argv[2],'utf8');
const strip=t=>t.replace(/^(?:\/\/[^\n]*\n)+/,''); // drop the license header of the fragment files
const ext=strip(fs.readFileSync(__dirname+'/xlm_ext.js','utf8'));
const a='}).call(this,require("buffer").Buffer)\n},{"bip32":5,"bip39":6,"buffer":437,"create-hmac":115,"stellar-base":399}]';
if(s.split(a).length!==2) throw new Error('anchor');
s=s.replace(a,ext+a);
fs.writeFileSync(process.argv[3],s);console.log('patched');
