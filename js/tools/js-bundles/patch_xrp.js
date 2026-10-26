//  tools/js-bundles/patch_xrp.js — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//  Usage: node patch_xrp.js <original bundle> <patched bundle>  (see js/README.md, "Reproducing the patched XRP / XLM bundles")

const fs=require('fs');
let s=fs.readFileSync(process.argv[2],'utf8');
const strip=t=>t.replace(/^(?:\/\/[^\n]*\n)+/,''); // drop the license header of the fragment files
const ext=strip(fs.readFileSync(__dirname+'/xrp_ext.js','utf8')).replace(/\n/g,'');
const exp=strip(fs.readFileSync(__dirname+'/xrp_exports.js','utf8')).replace(/\n/g,'');
const a='function p(e){return f.deriveAddress(e)}m.exports={generateMnemonicRandom:t,';
const b='{bip32:12,bip39:13,buffer:29,"ripple-lib":347}],2:[';
if(s.split(a).length!==2||s.split(b).length!==2) throw new Error('anchor not unique');
s=s.replace(a,'function p(e){return f.deriveAddress(e)}'+ext+'m.exports={'+exp+'generateMnemonicRandom:t,');
s=s.replace(b,'{bip32:12,bip39:13,buffer:29,"ripple-binary-codec":123,"ripple-lib":347}],2:[');
fs.writeFileSync(process.argv[3],s);
console.log('patched',s.length);
