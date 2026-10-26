//  tools/btc-taproot-js/test/vectors.js — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//  Vectors: BIP39 "abandon x11 about" seed, BIP86 and BIP-322 published vectors (all public).

// Tests for the built bundle (js/btctaprootjs-lib-bridge/btctaproot-lib-app.js), loaded the way
// WKWebView loads it (plain script in a fresh global, no Node require). Writes test/out/cases.json for verify.py, which
// checks every signature with an independent library (embit).
// Run: npm test   (then: python3 test/verify.py, with embit installed)
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const assert = require('assert');
const bitcoin = require('bitcoinjs-lib');           // only to build fake previous transactions / keys for the fixtures
const ecc = require('@bitcoinerlab/secp256k1');
const bip32 = require('bip32').default(ecc);
bitcoin.initEccLib(ecc);   // the test's own bitcoinjs (fixtures only) needs it for p2tr

const bundlePath = path.join(__dirname, '../../../btctaprootjs-lib-bridge/btctaproot-lib-app.js');
const sandbox = { TextEncoder, TextDecoder, crypto: require('crypto').webcrypto, console };
vm.createContext(sandbox);
vm.runInContext(fs.readFileSync(bundlePath, 'utf8'), sandbox);
const bridge = sandbox.bridge;

// BIP39 test vector "abandon ×11 about" (public; the backend's self-test vectors use it too)
const seedHex = '5eb00bbddcf069084889a8ab9155568165f5c453ccb85e70811aaed6f6da5fc19a5ac40b389cd370d086206dec8aa6c43daea6690f20ad3d8d48b2d2ce9e38e4';
let failures = 0;
function check(name, fn) {
    try { fn(); console.log('  ok   ' + name); } catch (e) { failures++; console.log('  FAIL ' + name + ': ' + e.message); }
}

console.log('BIP86 (backend self-test vectors)');
const [xpub0, xpub1] = bridge.getTaprootXpubs(seedHex);
check('m/86\'/0\'/0\'/0 xpub', () => assert.strictEqual(xpub0, 'xpub6EmR4gT2Lt7tseJfws6sm6Mvkc1yEoF6WiZS7Ppxj39xqy8VbCbCenCsWmFnwupZoq1Mq1EnAQtq38bb8RnwAE5epc965k8cjqKpi8NNGZY'));
check('m/86\'/0\'/0\'/1 xpub', () => assert.strictEqual(xpub1, 'xpub6EmR4gT2Lt7tvAFNteXrigLhA3FQtwkCrkfZri9p7n9ggSQQkhQNUDhnTS2epuDHmuDAtKLTbMr27NeyM6UEz831o4d8KSFa5oHodvs4pqj'));
check('/0/0 and /0/1', () => assert.deepStrictEqual(Array.from(bridge.getTaprootAddresses(xpub0, 0, 1)),
    ['bc1p5cyxnuxmeuwuvkwfem96lqzszd02n6xdcjrs20cac6yqjjwudpxqkedrcr', 'bc1p4qhjn9zdvkux4e44uhx8tc55attvtyu358kutcqkudyccelu0was9fqzwh']));
check('/1/0', () => assert.deepStrictEqual(Array.from(bridge.getTaprootAddresses(xpub1, 0, 0)), ['bc1p3qkhfews2uk44qtvauqyr2ttdsw7svhkl9nkm9s9c3x4ax5h60wqwruhk7']));

console.log('address validation (BIP350)');
const valid = ['bc1p5cyxnuxmeuwuvkwfem96lqzszd02n6xdcjrs20cac6yqjjwudpxqkedrcr', 'bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu',
    '1LqBGSKuX5yYUonjxT5qGfpUsXKYYWeabA', '37VucYSaXLCAsxYyAPfbSi9eh4iEcbShgf'];
const invalid = [
    'bc1p5cyxnuxmeuwuvkwfem96lqzszd02n6xdcjrs20cac6yqjjwudpxqkedrcs', // bad checksum
    'bc1pw508d6qejxtdg4y5r3zarvary0c5xw7kw508d6qejxtdg4y5r3zarvary0c5xw7kw5rljs90', // v1 with 40-byte program: payable? (future) -> must not be treated as Taproot
    'tb1p5cyxnuxmeuwuvkwfem96lqzszd02n6xdcjrs20cac6yqjjwudpxqkedrcr', // testnet hrp
    'bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4x', // bech32m checksum on v0 (BIP350 invalid)
    'hello'];
valid.forEach(a => check('valid ' + a.slice(0, 14) + '…', () => assert.strictEqual(bridge.validateAddress(a), true)));
check('isTaprootAddress(bc1p…)', () => assert.strictEqual(bridge.isTaprootAddress(valid[0]), true));
check('isTaprootAddress(bc1q…) is false', () => assert.strictEqual(bridge.isTaprootAddress(valid[1]), false));
invalid.slice(0, 1).concat(invalid.slice(2)).forEach(a => check('invalid ' + a.slice(0, 14) + '…', () => assert.strictEqual(bridge.validateAddress(a), false)));
check('v1 program that is not 32 bytes is not Taproot', () => assert.strictEqual(bridge.isTaprootAddress(invalid[1]), false));

// fixtures: keys for the other input types from the same seed (the app gets these WIFs from the old bundle)
const root = bip32.fromSeed(Buffer.from(seedHex, 'hex'));
const wif = p => root.derivePath(p).toWIF();
const legacyKey = root.derivePath("m/44'/0'/0'/0/2");
const legacyAddr = bitcoin.payments.p2pkh({ pubkey: legacyKey.publicKey }).address;
function fakePrevTx(script, value) {
    const t = new bitcoin.Transaction();
    t.version = 2;
    t.addInput(Buffer.alloc(32, 7), 0);
    t.addOutput(Buffer.alloc(1, 0x6a), 1);  // filler
    t.addOutput(script, value);
    return t;
}
const legacyPrev = fakePrevTx(bitcoin.address.toOutputScript(legacyAddr), 123456);
const txid = n => require('crypto').createHash('sha256').update('prev-' + n).digest('hex');

const cases = [];
function build(name, data, expectError) {
    try {
        const [id, hex] = bridge.buildTransaction(seedHex, JSON.stringify(data));
        if (expectError) { failures++; console.log('  FAIL ' + name + ': expected an error'); return; }
        const tx = bitcoin.Transaction.fromHex(hex);
        check(name + ': txid', () => assert.strictEqual(tx.getId(), id));
        cases.push({ name, data, txid: id, hex });
    } catch (e) {
        if (expectError) { console.log('  ok   ' + name + ': refused (' + e.message.slice(0, 60) + ')'); return; }
        failures++; console.log('  FAIL ' + name + ': ' + e.message);
    }
}
console.log('transactions');
build('taproot only', {
    inputs: [{ txHash: txid(1), index: 0, satoshis: 250000, segwit: 'T', isChange: false, bip39Index: 0, scriptPubKey: '5120a60869f0dbcf1dc659c9cecbaf8050135ea9e8cdc487053f1dc6880949dc684c' }],
    outputs: [{ address: 'bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu', amount: 200000 }, { address: 'bc1p3qkhfews2uk44qtvauqyr2ttdsw7svhkl9nkm9s9c3x4ax5h60wqwruhk7', amount: 49000 }],
});
build('mixed T + D + P + legacy', {
    inputs: [
        { txHash: txid(2), index: 1, satoshis: 70000, segwit: 'T', isChange: true, bip39Index: 0 },
        { txHash: txid(3), index: 0, satoshis: 80000, segwit: 'D', isChange: false, bip39Index: 0, wif: wif("m/84'/0'/0'/0/0") },
        { txHash: txid(4), index: 2, satoshis: 90000, segwit: 'P', isChange: true, bip39Index: 1, wif: wif("m/49'/0'/0'/1/1") },
        { txHash: legacyPrev.getId(), index: 1, satoshis: 123456, segwit: '', isChange: false, bip39Index: 2, wif: legacyKey.toWIF(), txHex: legacyPrev.toHex() },
    ],
    outputs: [{ address: '37VucYSaXLCAsxYyAPfbSi9eh4iEcbShgf', amount: 300000 }, { address: 'bc1p5cyxnuxmeuwuvkwfem96lqzszd02n6xdcjrs20cac6yqjjwudpxqkedrcr', amount: 60000 }],
});
build('op_return + locktime', {
    inputs: [{ txHash: txid(5), index: 3, satoshis: 50000, segwit: 'T', isChange: false, bip39Index: 1 }],
    outputs: [{ address: '1LqBGSKuX5yYUonjxT5qGfpUsXKYYWeabA', amount: 40000 }], ophex: '6f776e626974', locktime: 900000,
});
build('Taproot input with its own address (addressTxt) is signed', {
    inputs: [{ txHash: txid(7), index: 1, satoshis: 60000, segwit: 'T', isChange: false, bip39Index: 1, address: 'bc1p4qhjn9zdvkux4e44uhx8tc55attvtyu358kutcqkudyccelu0was9fqzwh' }],
    outputs: [{ address: 'bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu', amount: 50000 }],
});
build('address mismatch must be refused (index 0 key, index 1 address)', {
    inputs: [{ txHash: txid(8), index: 0, satoshis: 60000, segwit: 'T', isChange: false, bip39Index: 0, address: 'bc1p4qhjn9zdvkux4e44uhx8tc55attvtyu358kutcqkudyccelu0was9fqzwh' }],
    outputs: [{ address: 'bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu', amount: 50000 }],
}, true);
build('scriptPubKey mismatch must be refused', {
    inputs: [{ txHash: txid(6), index: 0, satoshis: 50000, segwit: 'T', isChange: false, bip39Index: 0, scriptPubKey: '5120' + '00'.repeat(32) }],
    outputs: [{ address: '1LqBGSKuX5yYUonjxT5qGfpUsXKYYWeabA', amount: 40000 }],
}, true);

// Private-key wallets: the bc1p address of one key, and transactions signed with that one key.
// Each case is written as out/pk-<n>.json ({hex, prevouts}) for test/verify_raw.py (embit) to check every signature.
console.log('private-key wallets');
const ECPairLib = require('ecpair').ECPairFactory(ecc);
const trKey = root.derivePath("m/86'/0'/0'/0/0");   // BIP86 /0/0: tr(its key) is the official vector address
check('address of a compressed public key (tr(key) = BIP86 /0/0 vector)', () => assert.strictEqual(
    bridge.getTaprootAddressFromPublicKey(trKey.publicKey.toString('hex')), 'bc1p5cyxnuxmeuwuvkwfem96lqzszd02n6xdcjrs20cac6yqjjwudpxqkedrcr'));
const trKeyUncompressed = ECPairLib.fromPrivateKey(trKey.privateKey, { compressed: false });
check('same address from the uncompressed form of that key', () => assert.strictEqual(
    bridge.getTaprootAddressFromPublicKey(trKeyUncompressed.publicKey.toString('hex')), 'bc1p5cyxnuxmeuwuvkwfem96lqzszd02n6xdcjrs20cac6yqjjwudpxqkedrcr'));
const pkFiles = [];
function buildPK(name, privateKey, data, prevouts, expectError) {
    try {
        const [id, hex] = bridge.buildTransactionWithPrivateKey(privateKey, JSON.stringify(data));
        if (expectError) { failures++; console.log('  FAIL ' + name + ': expected an error'); return; }
        const tx = bitcoin.Transaction.fromHex(hex);
        check(name + ': txid, locktime ' + (data.locktime || 0), () => { assert.strictEqual(tx.getId(), id); assert.strictEqual(tx.locktime, data.locktime || 0); });
        const file = path.join(__dirname, 'out/pk-' + pkFiles.length + '.json');
        pkFiles.push({ file, body: JSON.stringify({ name, hex, prevouts, privateKey, data }) });
    } catch (e) {
        if (expectError) { console.log('  ok   ' + name + ': refused (' + e.message.slice(0, 60) + ')'); return; }
        failures++; console.log('  FAIL ' + name + ': ' + e.message);
    }
}
// compressed WIF: one key, all four address types (as a private-key wallet has them)
const pkC = root.derivePath("m/44'/0'/0'/0/7");
const pkCPub = pkC.publicKey;
const pkCTr = bitcoin.payments.p2tr({ internalPubkey: pkCPub.subarray(1, 33) });
const pkCD = bitcoin.payments.p2wpkh({ pubkey: pkCPub });
const pkCP = bitcoin.payments.p2sh({ redeem: bitcoin.payments.p2wpkh({ pubkey: pkCPub }) });
const pkCL = bitcoin.payments.p2pkh({ pubkey: pkCPub });
const pkCPrev = fakePrevTx(pkCL.output, 77777);
check('bridge address of that key', () => assert.strictEqual(bridge.getTaprootAddressFromPublicKey(pkCPub.toString('hex')), pkCTr.address));
buildPK('compressed WIF: T + D + P + legacy, locktime', pkC.toWIF(), {
    inputs: [
        { txHash: txid(21), index: 0, satoshis: 40000, segwit: 'T', isChange: false, bip39Index: 0, address: pkCTr.address },
        { txHash: txid(22), index: 1, satoshis: 50000, segwit: 'D', isChange: false, bip39Index: 0 },
        { txHash: txid(23), index: 2, satoshis: 60000, segwit: 'P', isChange: false, bip39Index: 0 },
        { txHash: pkCPrev.getId(), index: 1, satoshis: 77777, segwit: '', isChange: false, bip39Index: 0, txHex: pkCPrev.toHex() },
    ],
    outputs: [{ address: pkCTr.address, amount: 200000 }], locktime: 910000,
}, [{ script: pkCTr.output.toString('hex'), amount: 40000 }, { script: pkCD.output.toString('hex'), amount: 50000 },
    { script: pkCP.output.toString('hex'), amount: 60000 }, { script: pkCL.output.toString('hex'), amount: 77777 }]);
// hex key: the old bundle treats it as UNCOMPRESSED (legacy address of the uncompressed key); Taproot uses its x-only key
const pkU = ECPairLib.fromPrivateKey(root.derivePath("m/44'/0'/0'/0/8").privateKey, { compressed: false });
const pkUTr = bitcoin.payments.p2tr({ internalPubkey: pkU.publicKey.subarray(1, 33) });
const pkUL = bitcoin.payments.p2pkh({ pubkey: pkU.publicKey });
const pkUPrev = fakePrevTx(pkUL.output, 55555);
buildPK('hex (uncompressed) key: T + legacy', pkU.privateKey.toString('hex'), {
    inputs: [
        { txHash: txid(24), index: 3, satoshis: 30000, segwit: 'T', isChange: false, bip39Index: 0, address: pkUTr.address },
        { txHash: pkUPrev.getId(), index: 1, satoshis: 55555, segwit: '', isChange: false, bip39Index: 0, txHex: pkUPrev.toHex() },
    ],
    outputs: [{ address: '1LqBGSKuX5yYUonjxT5qGfpUsXKYYWeabA', amount: 80000 }],
}, [{ script: pkUTr.output.toString('hex'), amount: 30000 }, { script: pkUL.output.toString('hex'), amount: 55555 }]);
buildPK('Taproot input of another key must be refused', pkC.toWIF(), {
    inputs: [{ txHash: txid(25), index: 0, satoshis: 40000, segwit: 'T', isChange: false, bip39Index: 0, address: pkUTr.address }],
    outputs: [{ address: pkCTr.address, amount: 30000 }],
}, [], true);

// BIP-322 message signing (2026-10-04): the BIP's own vectors (test/bip322, bitcoin/bips d77863f) and our Taproot signer
console.log('BIP-322: official vectors');
const basic322 = require('./bip322/basic-test-vectors.json');
const generated322 = require('./bip322/generated-test-vectors.json');
basic322.tx_hashes.forEach((v, i) => check('message hash, to_spend, to_sign #' + i + ' ' + JSON.stringify(v.message).slice(0, 20),
    () => assert.deepStrictEqual(Array.from(bridge.bip322Hashes(v.address, v.message)), [v.message_hash, v.to_spend_tx_hash, v.to_sign_tx_hash])));
// valid where the verifier can check the script; 'unsupported' (never valid / invalid) where it needs a script interpreter
const checkable322 = type => /^(p2tr|p2wpkh|p2pkh|p2sh-p2wpkh)$/.test(type);
[['basic simple', basic322.simple], ['generated simple', generated322.simple], ['generated full', generated322.full]].forEach(([name, list]) =>
    list.forEach(v => v.bip322_signatures.forEach((sig, j) => {
        const expected = checkable322(v.type) ? 'valid' : 'unsupported';
        check(name + ' ' + v.type + ' #' + j + ' → ' + expected, () => assert.strictEqual(bridge.verifyMessageBip322(v.address, v.message, sig), expected));
        // signatures made before the final BIP have no "smp" prefix; both forms must verify the same
        if (sig.startsWith('smp')) {
            check(name + ' ' + v.type + ' #' + j + ' without prefix → ' + expected, () => assert.strictEqual(bridge.verifyMessageBip322(v.address, v.message, sig.slice(3)), expected));
        } else if (!sig.startsWith('ful')) {
            check(name + ' ' + v.type + ' #' + j + ' with "smp" → ' + expected, () => assert.strictEqual(bridge.verifyMessageBip322(v.address, v.message, 'smp' + sig), expected));
        }
    })));
generated322.proof_of_funds.forEach(v => v.bip322_signatures.forEach(sig => check('proof of funds ' + v.type + ' → unsupported',
    () => assert.strictEqual(bridge.verifyMessageBip322(v.address, v.message, sig), 'unsupported'))));
basic322.error.concat(generated322.error).forEach(v => {
    const uncheckable = /p2wsh|multisig|time-lock/.test(v.description);
    check('error → ' + (uncheckable ? 'not valid' : 'invalid') + ': ' + v.description, () => {
        const r = bridge.verifyMessageBip322(v.address, v.message, v.signature);
        if (uncheckable) assert.notStrictEqual(r, 'valid'); else assert.strictEqual(r, 'invalid');
    });
});

console.log('BIP-322: our Taproot signer');
const msg322 = 'Ownbit BIP-322 ✓ 测试 \u{1F604}';
const tr00 = 'bc1p5cyxnuxmeuwuvkwfem96lqzszd02n6xdcjrs20cac6yqjjwudpxqkedrcr', tr01 = 'bc1p4qhjn9zdvkux4e44uhx8tc55attvtyu358kutcqkudyccelu0was9fqzwh';
const tr10 = 'bc1p3qkhfews2uk44qtvauqyr2ttdsw7svhkl9nkm9s9c3x4ax5h60wqwruhk7';
let sig322 = '';
check('seed /0/0: unprefixed simple signature, one 64-byte Schnorr signature (SIGHASH_DEFAULT)', () => {
    sig322 = bridge.signMessageBip322(seedHex, false, 0, tr00, msg322);
    const raw = Buffer.from(sig322, 'base64');
    assert.ok(raw.length === 66 && raw[0] === 1 && raw[1] === 64, sig322);
});
check('…verifies', () => assert.strictEqual(bridge.verifyMessageBip322(tr00, msg322, sig322), 'valid'));
check('…also with the "smp" prefix and with line breaks pasted in', () => {
    assert.strictEqual(bridge.verifyMessageBip322(tr00, msg322, 'smp' + sig322), 'valid');
    assert.strictEqual(bridge.verifyMessageBip322(tr00, msg322, sig322.slice(0, 30) + '\n' + sig322.slice(30) + ' '), 'valid');
});
check('wrong message → invalid', () => assert.strictEqual(bridge.verifyMessageBip322(tr00, msg322 + '.', sig322), 'invalid'));
check('another address → invalid', () => assert.strictEqual(bridge.verifyMessageBip322(tr01, msg322, sig322), 'invalid'));
check('one bit flipped → invalid', () => {
    const raw = Buffer.from(sig322, 'base64');
    raw[20] ^= 1;
    assert.strictEqual(bridge.verifyMessageBip322(tr00, msg322, raw.toString('base64')), 'invalid');
});
check('"ful" prefix on a simple signature → invalid', () => assert.strictEqual(bridge.verifyMessageBip322(tr00, msg322, 'ful' + sig322), 'invalid'));
check('randomized (BIP340 aux) signatures differ and all verify', () => {
    const again = bridge.signMessageBip322(seedHex, false, 0, tr00, msg322);
    assert.notStrictEqual(again, sig322);
    assert.strictEqual(bridge.verifyMessageBip322(tr00, msg322, again), 'valid');
});
check('/0/1 and change /1/0', () => {
    assert.strictEqual(bridge.verifyMessageBip322(tr01, msg322, bridge.signMessageBip322(seedHex, false, 1, tr01, msg322)), 'valid');
    assert.strictEqual(bridge.verifyMessageBip322(tr10, msg322, bridge.signMessageBip322(seedHex, true, 0, tr10, msg322)), 'valid');
});
check('empty message', () => assert.strictEqual(bridge.verifyMessageBip322(tr00, '', bridge.signMessageBip322(seedHex, false, 0, tr00, '')), 'valid'));
check('key / address mismatch is refused, not signed', () => assert.throws(() => bridge.signMessageBip322(seedHex, false, 0, tr01, msg322), /address mismatch/));
check('bad index is refused', () => assert.throws(() => bridge.signMessageBip322(seedHex, false, -1, tr00, msg322), /bad index/));
basic322.simple.concat(generated322.simple).filter(v => v.type === 'p2tr').forEach(v =>
    check('private key (WIF) of the BIP\'s ' + v.address.slice(0, 12) + '… signs, and it verifies',
        () => assert.strictEqual(bridge.verifyMessageBip322(v.address, v.message, bridge.signMessageBip322WithPrivateKey(v.private_keys[0], v.address, v.message)), 'valid')));
check('hex private key (uncompressed rule): same x-only key, same bc1p', () => {
    const hexKey = root.derivePath("m/86'/0'/0'/0/0").privateKey.toString('hex');
    assert.strictEqual(bridge.verifyMessageBip322(tr00, msg322, bridge.signMessageBip322WithPrivateKey(hexKey, tr00, msg322)), 'valid');
});
check('a legacy (65-byte recoverable) signature is not a BIP-322 signature', () =>
    assert.strictEqual(bridge.verifyMessageBip322('bc1q9vza2e8x573nczrlzms0wvx3gsqjx7vavgkx0l', '', 'H' + 'A'.repeat(87)), 'invalid'));

fs.mkdirSync(path.join(__dirname, 'out'), { recursive: true });
fs.writeFileSync(path.join(__dirname, 'out/cases.json'), JSON.stringify({ cases, legacyPrevHex: legacyPrev.toHex() }, null, 1));
pkFiles.forEach(f => fs.writeFileSync(f.file, f.body));
console.log('private-key cases for verify_raw.py: ' + pkFiles.map(f => path.relative(path.join(__dirname, '..'), f.file)).join(' '));
console.log(failures ? failures + ' FAILED' : 'ALL OK (signatures: run verify.py)');
process.exit(failures ? 1 : 0);
