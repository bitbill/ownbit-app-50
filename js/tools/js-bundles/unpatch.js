//  tools/js-bundles/unpatch.js — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Proves that the shipped XRP / XLM bundles are "original 2019/2020 bundle + the fragments in this folder" and nothing
//  else, without needing the app's git history:
//    1. remove exactly the bytes patch_xrp.js / patch_xlm.js insert -> the original bundles (md5 must match the values
//       recorded when the patch was made),
//    2. run patch_xrp.js / patch_xlm.js on them again -> must be byte-identical to the shipped bundles.
//  It also writes the fixtures test_xrp.js / test_xlm.js read from their working directory.
//
//  Usage: node unpatch.js <path to js/> <out dir>
//         (cd <out dir> && node <path to js/>/tools/js-bundles/test_xrp.js && node <path to js/>/tools/js-bundles/test_xlm.js)

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { execFileSync } = require('child_process');

const strip = t => t.replace(/^(?:\/\/[^\n]*\n)+/, '');
const md5 = b => crypto.createHash('md5').update(b).digest('hex');
const need = (ok, msg) => { if (!ok) throw new Error(msg); };
// what String.prototype.replace(anchor, replacement) actually inserts (same "$" rules as the patch scripts)
const expand = r => 'X'.replace('X', r);
// replace exactly one occurrence, no "$" interpretation
const once = (s, from, to, what) => {
    const parts = s.split(from);
    need(parts.length === 2, what + ': expected exactly one occurrence, found ' + (parts.length - 1));
    return parts.join(to);
};

const [jsDir, outDir] = process.argv.slice(2);
need(jsDir && outDir, 'usage: node unpatch.js <path to js/> <out dir>');
fs.mkdirSync(outDir, { recursive: true });

// md5 recorded when the patch was made (app files) and, for XLM, of this repository's copy, in which tools/redact.py
// replaced one build-machine path in package metadata and one author name in a comment (same lengths; outside the patched region)
const EXPECT = {
    xrpBefore: ['a597d4a4ba3ea2f368a9516dbc534f78'], xrpAfter: ['4fff6a157c0ba9e4561be579371d736c'],
    xlmBefore: ['6a8db0b631f13390d4941ee698f2eaa2', 'a3b1cd17232d08699619d456389cb05e'],
    xlmAfter: ['f0c276702951db21c7c10b6c6ed64db3', 'a77d1df464423311243212d2b46ad9d8'],
};
let failures = 0;
const check = (ok, label) => { console.log((ok ? 'ok   ' : 'FAIL ') + label); if (!ok) failures++; };

// ---- XRP ----
const xrpPath = path.join(jsDir, 'ripplejs-lib-bridge/ripplejs-lib-app.min.js');
const xrpShipped = fs.readFileSync(xrpPath, 'utf8');
const ext = strip(fs.readFileSync(path.join(__dirname, 'xrp_ext.js'), 'utf8')).replace(/\n/g, '');
const exp = strip(fs.readFileSync(path.join(__dirname, 'xrp_exports.js'), 'utf8')).replace(/\n/g, '');
const a = 'function p(e){return f.deriveAddress(e)}m.exports={generateMnemonicRandom:t,';
const b = '{bip32:12,bip39:13,buffer:29,"ripple-lib":347}],2:[';
const a2 = expand('function p(e){return f.deriveAddress(e)}' + ext + 'm.exports={' + exp + 'generateMnemonicRandom:t,');
const b2 = expand('{bip32:12,bip39:13,buffer:29,"ripple-binary-codec":123,"ripple-lib":347}],2:[');
const xrpOrig = once(once(xrpShipped, a2, a, 'XRP exports'), b2, b, 'XRP deps');
fs.writeFileSync(path.join(outDir, 'ripple.orig.min.js'), xrpOrig);
fs.writeFileSync(path.join(outDir, 'ripple.new.min.js'), xrpShipped);
check(EXPECT.xrpAfter.includes(md5(Buffer.from(xrpShipped))), 'XRP shipped md5 ' + md5(Buffer.from(xrpShipped)));
check(EXPECT.xrpBefore.includes(md5(Buffer.from(xrpOrig))), 'XRP original md5 ' + md5(Buffer.from(xrpOrig)));
execFileSync(process.execPath, [path.join(__dirname, 'patch_xrp.js'), path.join(outDir, 'ripple.orig.min.js'),
    path.join(outDir, 'ripple.repatched.min.js')], { stdio: 'ignore' });
check(fs.readFileSync(path.join(outDir, 'ripple.repatched.min.js')).equals(fs.readFileSync(xrpPath)),
    'patch_xrp.js(original) == shipped ripplejs-lib-app.min.js');

// ---- XLM ----
const xlmPath = path.join(jsDir, 'stellarjs-lib-bridge/stellarjs-lib-app.min.js');
const xlmShipped = fs.readFileSync(xlmPath, 'utf8');
const xlmExt = strip(fs.readFileSync(path.join(__dirname, 'xlm_ext.js'), 'utf8'));
const anchor = '}).call(this,require("buffer").Buffer)\n},{"bip32":5,"bip39":6,"buffer":437,"create-hmac":115,"stellar-base":399}]';
const xlmOrig = once(xlmShipped, expand(xlmExt + anchor), anchor, 'XLM entry');
fs.writeFileSync(path.join(outDir, 'stellar.orig.min.js'), xlmOrig);
fs.writeFileSync(path.join(outDir, 'stellar.new.min.js'), xlmShipped);
// test_xlm.js also needs StellarBase itself, to verify signatures independently
fs.writeFileSync(path.join(outDir, 'stellar.debug.js'), once(xlmOrig, anchor, 'module.exports.__SB=StellarBase;\n' + anchor, 'XLM debug'));
check(EXPECT.xlmAfter.includes(md5(Buffer.from(xlmShipped))), 'XLM shipped md5 ' + md5(Buffer.from(xlmShipped)));
check(EXPECT.xlmBefore.includes(md5(Buffer.from(xlmOrig))), 'XLM original md5 ' + md5(Buffer.from(xlmOrig)));
execFileSync(process.execPath, [path.join(__dirname, 'patch_xlm.js'), path.join(outDir, 'stellar.orig.min.js'),
    path.join(outDir, 'stellar.repatched.min.js')], { stdio: 'ignore' });
check(fs.readFileSync(path.join(outDir, 'stellar.repatched.min.js')).equals(fs.readFileSync(xlmPath)),
    'patch_xlm.js(original) == shipped stellarjs-lib-app.min.js');

console.log(failures ? 'FAILED: ' + failures : 'ALL OK');
process.exit(failures ? 1 : 0);
