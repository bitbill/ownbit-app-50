//  tools/compare_bundles.js — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Behaviour check for every bundle that tools/redact.py changed: loads the app's original and this repository's copy
//  the way the Swift bridge does, calls derivation functions on the public BIP-39 vector "abandon x11 about", and
//  requires identical results.
//    JSContext bridges (LTC, DOGE, DASH, DGB, ZEN): a bare global, no `window`.
//    WKWebView / UIWebView bridges (ZEC, XLM, TRX, TON): `window` = the global, plus crypto / TextEncoder and a
//    `webkit.messageHandlers` stub that records what the page posts.
//  Nothing is sent anywhere; console output of the bundles is swallowed (some bundles log key material).
//
//  Usage: node compare_bundles.js <app>/components/JavaScriptBridge [<path to js/>]

const fs = require('fs');
const path = require('path');
const vm = require('vm');
const crypto = require('crypto');

const appDir = process.argv[2];
const jsDir = process.argv[3] || path.join(__dirname, '..');
if (!appDir) { console.error('usage: node compare_bundles.js <app JavaScriptBridge dir> [<js dir>]'); process.exit(2); }

const MNEMONIC = 'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
const SEED = '5eb00bbddcf069084889a8ab9155568165f5c453ccb85e70811aaed6f6da5fc19a5ac40b389cd370d086206dec8aa6c43daea6690f20ad3d8d48b2d2ce9e38e4';
const TEST_PRIVKEY = '0000000000000000000000000000000000000000000000000000000000000001'; // the generator point's key
const LOCAL_NODE = 'http' + '://127.0.0.1:1'; // TronWeb needs a syntactically valid node URL; none of the calls below uses it

const quiet = { log() {}, info() {}, warn() {}, error() {}, debug() {}, trace() {} };

function load(file, web) {
    const posted = [];
    const sandbox = { console: quiet };
    if (web) {
        Object.assign(sandbox, {
            crypto: crypto.webcrypto, TextEncoder, TextDecoder, setTimeout, clearTimeout, setInterval, clearInterval,
            URL, atob: s => Buffer.from(s, 'base64').toString('binary'), btoa: s => Buffer.from(s, 'binary').toString('base64'),
            navigator: { userAgent: 'compare_bundles' }, location: { href: 'file:///index.html', protocol: 'file:' },
        });
        sandbox.window = sandbox;
        sandbox.self = sandbox;
        sandbox.webkit = { messageHandlers: new Proxy({}, { get: (_, name) => ({ postMessage: b => posted.push([name, b]) }) }) };
    }
    vm.createContext(sandbox);
    vm.runInContext(fs.readFileSync(file, 'utf8'), sandbox, { filename: file });
    return { bridge: sandbox.bridge, posted };
}

const first = v => (Array.isArray(v) ? v[0] : String(v).split(/[,|\s]/)[0]);
const digest = v => crypto.createHash('sha256').update(JSON.stringify(v)).digest('hex').slice(0, 16);

const CASES = [
    ['litecoinjs-lib-bridge/litecoinjs-lib-app.min.js', false, b => {
        const x = b.getXpubkeysForAll(SEED);
        return { xpubs: x, receive0_1: b.getLtcContinuousAddrFromXpubkey(first(x), 0, 1), privkey0: digest(b.getPrivkeyFromSeedHex(SEED, 0, false)) };
    }],
    ['dogecoinjs-lib-bridge/dogecoinjs-lib-app.min.js', false, b => {
        const x = b.getXpubkeys(SEED);
        return { xpubs: x, receive0_1: b.getDogeContinuousAddrFromXpubkey(first(x), 0, 1), privkey0: digest(b.getPrivkeyFromSeedHex(SEED, 0, false)) };
    }],
    ['dashjs-lib-bridge/dashjs-lib-app.min.js', false, b => {
        const x = b.getXpubkeys(SEED);
        return { xpubs: x, receive0_1: b.getDshContinuousAddrFromXpubkey(first(x), 0, 1), privkey0: digest(b.getPrivkeyFromSeedHex(SEED, 0, false)) };
    }],
    ['digibytejs-lib-bridge/digibytejs-lib-app.min.js', false, b => {
        const x = b.getXpubkeys(SEED);
        return { xpubs: x, receive0_1: b.getDgbContinuousAddrFromXpubkey(first(x), 0, 1), privkey0: digest(b.getPrivkeyFromSeedHex(SEED, 0, false)) };
    }],
    ['horizenjs-lib-bridge/zenjs-lib-app.min.js', false, b => {
        const x = b.getXpubkeys(SEED);
        return { xpubs: x, receive0_1: b.getZenContinuousAddrFromXpubkey(first(x), 0, 1), privkey0: digest(b.getPrivkeyFromSeedHex(SEED, 0, false)) };
    }],
    ['zcashjs-lib-bridge/zcashjs-lib-app-0251.js', true, b => {
        const x = b.getXpubkeys(SEED);
        return { xpubs: x, receive0_1: b.getZecContinuousAddrFromXpubkey(first(x), 0, 1), wif0: digest(b.getWIFFromSeedHex(SEED, 0, false)) };
    }],
    ['stellarjs-lib-bridge/stellarjs-lib-app.min.js', true, b => {
        const seed = b.mnemonicToSeedHex(MNEMONIC, '');
        return { seedMatchesVector: seed === SEED, sep5_0: b.getPubAddrFromSeedHex(seed, true), index1: b.getPubAddrFromSeedHexIndex(seed, 1) };
    }],
    ['tronjs-lib-bridge/trxjs-lib-app.js', true, b => {
        const a = b.getAddress(LOCAL_NODE, TEST_PRIVKEY);
        return { address: a, fromHex: b.getBase58AddrFromHex(LOCAL_NODE, a[0]), valid: b.isAddress(LOCAL_NODE, a[1]) };
    }],
    ['tonjs-lib-bridge/tonjs-new.js', true, async (b, posted) => {
        const r = await b.mnemonicToAddress(MNEMONIC);
        return { address: r, posted: posted.filter(p => p[0] === 'address') };
    }],
];

(async () => {
    let failures = 0;
    for (const [rel, web, run] of CASES) {
        const results = [];
        for (const file of [path.join(appDir, rel), path.join(jsDir, rel)]) {
            const { bridge, posted } = load(file, web);
            results.push(JSON.stringify(await run(bridge, posted)));
        }
        const same = results[0] === results[1];
        if (!same) failures++;
        console.log((same ? 'ok   ' : 'FAIL ') + rel + (web ? '  [window shim]' : '  [bare JSContext-like global]'));
        console.log('       ' + results[1].slice(0, 400));
    }
    console.log(failures ? 'FAILED: ' + failures : 'ALL OK: app original and repo copy give identical results');
    process.exit(failures ? 1 : 0);
})().catch(e => { console.error('ERROR ' + (e && e.stack || e)); process.exit(1); });
