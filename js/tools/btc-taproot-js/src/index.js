//  tools/btc-taproot-js/src/index.js — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//  Source of js/btctaprootjs-lib-bridge/btctaproot-lib-app.js (build.sh). Path names in the comments below are the app's.

// BTC Taproot bridge for Ownbit iOS (2026-09-26).
//
// BIP86 Taproot (bc1p) xpubs / addresses, and transactions that spend Taproot UTXOs (BIP341 key-path, BIP340 Schnorr).
// Bundled by build.sh into components/JavaScriptBridge/btctaprootjs-lib-bridge/btctaproot-lib-app.js (global `bridge`),
// loaded by BTCTaprootJSBridge.swift in a hidden WKWebView. The old bitcoinjs bundle is not touched: it keeps doing
// everything else (it can already pay *to* bc1p); this one is only used when a transaction spends Taproot inputs.
//
// Backend contract (BTC_SW_T): receive m/86'/0'/0'/0/i, change m/86'/0'/0'/1/i, key-path only (no script tree),
// xpubs at chain level with the standard xpub version (0x0488B21E). Private-key wallets: the bc1p address of the one key
// (btcAddress_sw_t in importPrikey), spent with buildTransactionWithPrivateKey.
//
// 2026-10-04: BIP-322 message signing / verification (see the section at the end).

import * as bitcoin from 'bitcoinjs-lib';
import * as ecc from '@bitcoinerlab/secp256k1';
import BIP32Factory from 'bip32';
import ECPairFactory from 'ecpair';
import { Buffer } from 'buffer';

bitcoin.initEccLib(ecc);
const bip32 = BIP32Factory(ecc);
const ECPair = ECPairFactory(ecc);
const network = bitcoin.networks.bitcoin;

const TAPROOT_RECEIVE_PATH = "m/86'/0'/0'/0";
const TAPROOT_CHANGE_PATH = "m/86'/0'/0'/1";

function toXOnly(pubkey) {
    return pubkey.length === 32 ? pubkey : pubkey.subarray(1, 33);
}

function rootFromSeed(seedHex) {
    return bip32.fromSeed(Buffer.from(seedHex, 'hex'), network);
}

function p2trForInternalKey(internalPubkey) {
    return bitcoin.payments.p2tr({ internalPubkey: internalPubkey, network: network });
}

/**
 * @param {String} seedHex
 * @return {Array} [xpub of m/86'/0'/0'/0, xpub of m/86'/0'/0'/1], standard "xpub" serialization
 */
export function getTaprootXpubs(seedHex) {
    const root = rootFromSeed(seedHex);
    return [
        root.derivePath(TAPROOT_RECEIVE_PATH).neutered().toBase58(),
        root.derivePath(TAPROOT_CHANGE_PATH).neutered().toBase58(),
    ];
}

/**
 * @param {String} xpub chain-level xpub (receive or change)
 * @return {Array} bc1p addresses for fromIndex...toIndex (inclusive)
 */
export function getTaprootAddresses(xpub, fromIndex, toIndex) {
    const node = bip32.fromBase58(xpub, network);
    const addresses = [];
    for (let i = fromIndex; i <= toIndex; i++) {
        addresses.push(p2trForInternalKey(toXOnly(node.derive(i).publicKey)).address);
    }
    return addresses;
}

/**
 * Any mainnet BTC address the network can pay to (P2PKH, P2SH, P2WPKH, P2WSH, P2TR / bech32m).
 */
export function validateAddress(address) {
    try {
        bitcoin.address.toOutputScript(address, network);
        return true;
    } catch (e) {
        return false;
    }
}

export function isTaprootAddress(address) {
    try {
        const decoded = bitcoin.address.fromBech32(address);
        return decoded.prefix === network.bech32 && decoded.version === 1 && decoded.data.length === 32;
    } catch (e) {
        return false;
    }
}

// The server's scriptPubKeyHex (when present) must be the script we derived for the key; otherwise don't sign.
function checkScript(input, script) {
    const expected = input['scriptPubKey'];
    if (expected && expected.toLowerCase() !== script.toString('hex')) {
        throw new Error('scriptPubKey mismatch for ' + input['txHash'] + ':' + input['index']);
    }
}

// Same for the UTXO's address (the server's addressTxt, sent for Taproot inputs): the key derived from
// addressType / addressIndex must give exactly that address (the server does not always send scriptPubKeyHex).
function checkAddress(input, address) {
    const expected = input['address'];
    if (expected && expected.toLowerCase() !== address.toLowerCase()) {
        throw new Error('address mismatch for ' + input['txHash'] + ':' + input['index']);
    }
}

/**
 * Taproot address of a single key (private-key wallets): key-path only, internal key = x-only public key
 * (the same for its compressed and uncompressed forms). The backend recomputes it from btcPublicKey.
 */
export function getTaprootAddressFromPublicKey(publicKeyHex) {
    return p2trForInternalKey(toXOnly(Buffer.from(publicKeyHex, 'hex'))).address;
}

// Private-key wallets: exactly the old bundle's ecpairFromPrivateKey rules, so non-Taproot inputs are signed with the
// same key the wallet's 1 / 3 / bc1q addresses were made from: a hex key is an UNCOMPRESSED key, otherwise a WIF (5 / K / L).
function keyPairFromPrivateKey(privateKey) {
    if (/^[0-9a-f]+$/i.test(privateKey)) {
        return ECPair.fromPrivateKey(Buffer.from(privateKey, 'hex'), { compressed: false, network: network });
    }
    return ECPair.fromWIF(privateKey, network);
}

// BIP341 key-path signer: key tweaked with the internal key only (no script tree); bip32 / ecpair negate for odd y
function tapTweakSigner(signer, internalPubkey) {
    return signer.tweak(bitcoin.crypto.taggedHash('TapTweak', internalPubkey));
}

/*
 * data: {
 *   inputs: [{ txHash, index, satoshis, segwit: "" | "P" | "D" | "T", isChange, bip39Index,
 *              txHex (legacy inputs), wif (non-Taproot inputs, seed wallets), scriptPubKey / address (optional, checked) }],
 *   outputs: [{ address, amount }], ophex (optional OP_RETURN data), locktime (optional)
 * }
 * Same transaction shape as the old bundle: PSBT (version 2), sequence 0xfffffffd (RBF) unless there is an OP_RETURN
 * (then 0xffffffff), the OP_RETURN output first, then the outputs; locktime when > 0.
 * keys.taproot(input) → { internalPubkey, signer }, keys.other(input) → ECPair.
 * Taproot inputs are signed per BIP341 key-path with SIGHASH_DEFAULT (64-byte Schnorr signature, witness = [sig]).
 */
function signTransaction(data, keys) {
    const inputs = data['inputs'];
    const outputs = data['outputs'];
    const hasOpReturn = !!(data['ophex'] && data['ophex'].length > 0);
    const sequence = hasOpReturn ? 0xffffffff : 0xfffffffd;

    const psbt = new bitcoin.Psbt({ network: network });
    if (data['locktime'] && data['locktime'] > 0) {
        psbt.setLocktime(data['locktime']);
    }

    const signers = inputs.map(function (input) {
        const base = { hash: input['txHash'], index: input['index'], sequence: sequence };
        if (input['segwit'] === 'T') {
            const key = keys.taproot(input);
            const payment = p2trForInternalKey(key.internalPubkey);
            checkScript(input, payment.output);
            checkAddress(input, payment.address);
            psbt.addInput(Object.assign(base, {
                witnessUtxo: { script: payment.output, value: input['satoshis'] },
                tapInternalKey: key.internalPubkey,
            }));
            return key.signer;
        }
        const keyPair = keys.other(input);
        if (input['segwit'] === 'P') {
            const payment = bitcoin.payments.p2sh({ redeem: bitcoin.payments.p2wpkh({ pubkey: keyPair.publicKey, network: network }), network: network });
            checkScript(input, payment.output);
            psbt.addInput(Object.assign(base, {
                witnessUtxo: { script: payment.output, value: input['satoshis'] },
                redeemScript: payment.redeem.output,
            }));
        } else if (input['segwit'] === 'D') {
            const payment = bitcoin.payments.p2wpkh({ pubkey: keyPair.publicKey, network: network });
            checkScript(input, payment.output);
            psbt.addInput(Object.assign(base, {
                witnessUtxo: { script: payment.output, value: input['satoshis'] },
            }));
        } else {
            // legacy: the full previous transaction (bitcoinjs checks it hashes to txHash)
            psbt.addInput(Object.assign(base, {
                nonWitnessUtxo: Buffer.from(input['txHex'], 'hex'),
            }));
        }
        return keyPair;
    });

    if (hasOpReturn) {
        psbt.addOutput({ script: bitcoin.payments.embed({ data: [Buffer.from(data['ophex'], 'hex')] }).output, value: 0 });
    }
    outputs.forEach(function (output) {
        psbt.addOutput({ address: output['address'], value: output['amount'] });
    });

    signers.forEach(function (signer, i) {
        psbt.signInput(i, signer);
    });
    psbt.finalizeAllInputs();
    const tx = psbt.extractTransaction();
    return [tx.getId(), tx.toHex()];
}

/**
 * Seed (HD) wallets: build and sign a transaction that spends Taproot inputs (possibly mixed with other input types).
 * Taproot inputs: key m/86'/0'/0'/{isChange ? 1 : 0}/{bip39Index} from the seed.
 * Other inputs: signed with the WIF the app got from the old bundle (input.wif), so their derivation rules stay there.
 * @return {Array} [txid, txHex]
 */
export function buildTransaction(seedHex, data) {
    let root = null;
    return signTransaction(JSON.parse(data), {
        taproot: function (input) {
            root = root || rootFromSeed(seedHex);
            const node = root.derivePath(input['isChange'] ? TAPROOT_CHANGE_PATH : TAPROOT_RECEIVE_PATH).derive(input['bip39Index']);
            const internalPubkey = toXOnly(node.publicKey);
            return { internalPubkey: internalPubkey, signer: tapTweakSigner(node, internalPubkey) };
        },
        other: function (input) {
            return ECPair.fromWIF(input['wif'], network);
        },
    });
}

/**
 * Private-key wallets: every input (1 / 3 / bc1q / bc1p address of the one key) is signed with that key;
 * Taproot inputs with it tweaked (internal key = its x-only public key).
 * @return {Array} [txid, txHex]
 */
export function buildTransactionWithPrivateKey(privateKey, data) {
    const keyPair = keyPairFromPrivateKey(privateKey);
    const internalPubkey = toXOnly(keyPair.publicKey);
    const tweaked = tapTweakSigner(keyPair, internalPubkey);
    return signTransaction(JSON.parse(data), {
        taproot: function () {
            return { internalPubkey: internalPubkey, signer: tweaked };
        },
        other: function () {
            return keyPair;
        },
    });
}

// ---------------------------------------------------------------------------------------------------------------------
// BIP-322 message signing (2026-10-04)
//
// The legacy "Bitcoin Signed Message" format (ECDSA + public key recovery, still done by the old bundle for 1 / 3 / bc1q)
// cannot express Taproot, so bc1p addresses sign and verify with BIP-322 (bitcoin/bips bip-0322, final 2026-04).
//
// Signing (Taproot only): the "simple" variant, key path, SIGHASH_DEFAULT (64-byte Schnorr signature) -- what
// bip322-js / UniSat / Xverse / Sparrow produce. The final BIP adds a variant prefix ("smp") to the encoded signature;
// most verifiers in use predate it, and the BIP tells verifiers to read an unprefixed signature as "simple", so we sign
// WITHOUT the prefix (BIP322_SIGNATURE_PREFIX).
// Verifying: "simple" (with or without "smp") for P2TR key path and P2WPKH; "full" ("ful") for those plus P2SH-P2WPKH
// and P2PKH. What needs a script interpreter (P2WSH, P2SH scripts, Taproot script path / annex) or the UTXO set
// ("pof", proof of funds) is reported as "unsupported", never as valid or invalid.
// Test vectors: test/bip322 (the BIP's own), run by test/vectors.js.
// ---------------------------------------------------------------------------------------------------------------------

const BIP322_SIGNATURE_PREFIX = '';   // '' (compatible with pre-2026 verifiers) or 'smp' (final BIP)
const OP_RETURN_SCRIPT = Buffer.from([0x6a]);

// sha256_tag("BIP0322-signed-message", message as UTF-8, no length prefix). bitcoin.crypto.taggedHash only knows BIP341 tags.
function bip322MessageHash(message) {
    const tag = bitcoin.crypto.sha256(Buffer.from('BIP0322-signed-message', 'utf8'));
    return bitcoin.crypto.sha256(Buffer.concat([tag, tag, Buffer.from(message, 'utf8')]));
}

function bip322ToSpend(scriptPubKey, message) {
    const tx = new bitcoin.Transaction();
    tx.version = 0;
    tx.locktime = 0;
    tx.addInput(Buffer.alloc(32, 0), 0xffffffff, 0, bitcoin.script.compile([bitcoin.opcodes.OP_0, bip322MessageHash(message)]));
    tx.addOutput(scriptPubKey, 0);
    return tx;
}

// to_sign with the default fields of the "simple" variant (version 0, locktime 0, sequence 0, empty scriptSig)
function bip322ToSign(toSpend) {
    const tx = new bitcoin.Transaction();
    tx.version = 0;
    tx.locktime = 0;
    tx.addInput(toSpend.getHash(), 0, 0);
    tx.addOutput(OP_RETURN_SCRIPT, 0);
    return tx;
}

function varIntBuffer(n) {
    if (n < 0xfd) return Buffer.from([n]);
    if (n <= 0xffff) {
        const b = Buffer.alloc(3);
        b[0] = 0xfd;
        b.writeUInt16LE(n, 1);
        return b;
    }
    const b = Buffer.alloc(5);
    b[0] = 0xfe;
    b.writeUInt32LE(n, 1);
    return b;
}

// witness stack, consensus-encoded: count, then each item with its length
function encodeWitness(stack) {
    const parts = [varIntBuffer(stack.length)];
    stack.forEach(function (item) {
        parts.push(varIntBuffer(item.length), item);
    });
    return Buffer.concat(parts);
}

// strict: canonical var-ints, every byte used; throws otherwise
function decodeWitness(buf) {
    let pos = 0;
    function readVarInt() {
        if (pos >= buf.length) throw new Error('truncated');
        const first = buf[pos++];
        if (first < 0xfd) return first;
        if (first === 0xff) throw new Error('var-int too large');
        const size = first === 0xfd ? 2 : 4;
        if (pos + size > buf.length) throw new Error('truncated');
        const n = size === 2 ? buf.readUInt16LE(pos) : buf.readUInt32LE(pos);
        pos += size;
        if ((size === 2 && n < 0xfd) || (size === 4 && n <= 0xffff)) throw new Error('non-canonical var-int');
        return n;
    }
    const count = readVarInt();
    const stack = [];
    for (let i = 0; i < count; i++) {
        const len = readVarInt();
        if (pos + len > buf.length) throw new Error('truncated');
        stack.push(buf.subarray(pos, pos + len));
        pos += len;
    }
    if (pos !== buf.length) throw new Error('trailing bytes');
    return stack;
}

// standard base64 only, canonical padding (Buffer.from(…, 'base64') alone accepts almost anything)
function decodeBase64Strict(text) {
    if (text.length === 0 || text.length % 4 !== 0 || !/^[A-Za-z0-9+/]+={0,2}$/.test(text)) return null;
    const buf = Buffer.from(text, 'base64');
    return buf.toString('base64') === text ? buf : null;
}

function scriptType(script) {
    if (script.length === 34 && script[0] === 0x51 && script[1] === 0x20) return 'p2tr';
    if (script.length === 22 && script[0] === 0x00 && script[1] === 0x14) return 'p2wpkh';
    if (script.length === 34 && script[0] === 0x00 && script[1] === 0x20) return 'p2wsh';
    if (script.length === 23 && script[0] === 0xa9 && script[1] === 0x14 && script[22] === 0x87) return 'p2sh';
    if (script.length === 25 && script[0] === 0x76 && script[1] === 0xa9 && script[2] === 0x14 && script[23] === 0x88 && script[24] === 0xac) return 'p2pkh';
    return 'other';
}

// ECDSA: strict DER (BIP66), SIGHASH_ALL only, low S
function checkEcdsa(sighash, signatureWithType, pubkey) {
    let decoded;
    try {
        decoded = bitcoin.script.signature.decode(signatureWithType);
    } catch (e) {
        return false;
    }
    if (decoded.hashType !== bitcoin.Transaction.SIGHASH_ALL || !ecc.isPoint(pubkey)) return false;
    return ecc.verify(sighash(decoded.hashType), pubkey, decoded.signature, true);
}

// the first input of to_sign against the address's script: 'valid' | 'invalid' | 'unsupported'
function bip322VerifyInput(toSign, script, type) {
    const input = toSign.ins[0];
    const witness = input.witness || [];
    if (type === 'p2tr') {
        if (input.script.length !== 0) return 'invalid';
        if (witness.length === 0) return 'invalid';
        const last = witness[witness.length - 1];
        if (witness.length >= 2 && last.length > 0 && last[0] === 0x50) return 'unsupported';   // annex
        if (witness.length !== 1) return 'unsupported';                                         // script path
        const sig = witness[0];
        let hashType;
        if (sig.length === 64) {
            hashType = bitcoin.Transaction.SIGHASH_DEFAULT;
        } else if (sig.length === 65 && sig[64] === bitcoin.Transaction.SIGHASH_ALL) {
            hashType = bitcoin.Transaction.SIGHASH_ALL;
        } else {
            return 'invalid';
        }
        const hash = toSign.hashForWitnessV1(0, [script], [0], hashType);
        return ecc.verifySchnorr(hash, script.subarray(2, 34), sig.subarray(0, 64)) ? 'valid' : 'invalid';
    }
    if (type === 'p2wpkh' || type === 'p2sh') {
        let program;
        if (type === 'p2sh') {
            const chunks = bitcoin.script.decompile(input.script);
            if (!chunks || chunks.length === 0 || !bitcoin.script.compile(chunks).equals(input.script)) return 'invalid';
            const redeem = chunks[chunks.length - 1];
            if (!Buffer.isBuffer(redeem) || !bitcoin.crypto.hash160(redeem).equals(script.subarray(2, 22))) return 'invalid';
            // only P2SH-P2WPKH; other redeem scripts (P2SH-P2WSH, multisig, …) need a script interpreter
            if (chunks.length !== 1 || redeem.length !== 22 || redeem[0] !== 0x00 || redeem[1] !== 0x14) return 'unsupported';
            program = redeem.subarray(2);
        } else {
            if (input.script.length !== 0) return 'invalid';
            program = script.subarray(2, 22);
        }
        if (witness.length !== 2 || witness[1].length !== 33) return 'invalid';
        if (!bitcoin.crypto.hash160(witness[1]).equals(program)) return 'invalid';
        const scriptCode = bitcoin.payments.p2pkh({ hash: program }).output;
        return checkEcdsa(function (hashType) {
            return toSign.hashForWitnessV0(0, scriptCode, 0, hashType);
        }, witness[0], witness[1]) ? 'valid' : 'invalid';
    }
    if (type === 'p2pkh') {
        if (witness.length !== 0) return 'invalid';
        const chunks = bitcoin.script.decompile(input.script);
        if (!chunks || chunks.length !== 2 || !Buffer.isBuffer(chunks[0]) || !Buffer.isBuffer(chunks[1])
            || !bitcoin.script.compile(chunks).equals(input.script)) return 'invalid';
        if (!bitcoin.crypto.hash160(chunks[1]).equals(script.subarray(3, 23))) return 'invalid';
        return checkEcdsa(function (hashType) {
            return toSign.hashForSignature(0, script, hashType);
        }, chunks[0], chunks[1]) ? 'valid' : 'invalid';
    }
    if (type === 'p2wsh') {
        // the witness script must at least be the one the address commits to; running it needs a script interpreter
        if (input.script.length !== 0 || witness.length === 0) return 'invalid';
        if (!bitcoin.crypto.sha256(witness[witness.length - 1]).equals(script.subarray(2, 34))) return 'invalid';
        return 'unsupported';
    }
    return 'unsupported';
}

function bip322SignTaproot(keyPair, expectedAddress, message) {
    const internalPubkey = toXOnly(keyPair.publicKey);
    const payment = p2trForInternalKey(internalPubkey);
    if (payment.address !== expectedAddress) {
        throw new Error('address mismatch');
    }
    const toSign = bip322ToSign(bip322ToSpend(payment.output, message));
    const hash = toSign.hashForWitnessV1(0, [payment.output], [0], bitcoin.Transaction.SIGHASH_DEFAULT);
    const signature = Buffer.from(tapTweakSigner(keyPair, internalPubkey).signSchnorr(hash));
    if (!ecc.verifySchnorr(hash, payment.output.subarray(2, 34), signature)) {
        throw new Error('signature self-check failed');
    }
    return BIP322_SIGNATURE_PREFIX + encodeWitness([signature]).toString('base64');
}

/**
 * Seed (HD) wallets: BIP-322 signature of a message with the Taproot address m/86'/0'/0'/{isChange ? 1 : 0}/{index}.
 * address must be that key's address (checked; a mismatch throws instead of signing with another key).
 * @return {String} base64 "simple" signature (witness stack), see BIP322_SIGNATURE_PREFIX
 */
export function signMessageBip322(seedHex, isChange, index, address, message) {
    if (!Number.isInteger(index) || index < 0 || index >= 0x80000000) {
        throw new Error('bad index');
    }
    const node = rootFromSeed(seedHex).derivePath(isChange ? TAPROOT_CHANGE_PATH : TAPROOT_RECEIVE_PATH).derive(index);
    return bip322SignTaproot(node, address, String(message));
}

/**
 * Private-key wallets: BIP-322 signature with the bc1p address of the one key (WIF, or hex as in keyPairFromPrivateKey).
 */
export function signMessageBip322WithPrivateKey(privateKey, address, message) {
    return bip322SignTaproot(keyPairFromPrivateKey(privateKey), address, String(message));
}

/**
 * BIP-322 verification of a signature for a mainnet address.
 * signature: "smp…" / unprefixed (simple), "ful…" (full), "pof…" (proof of funds: unsupported); whitespace is ignored.
 * @return {String} 'valid' | 'invalid' | 'unsupported' (cannot be checked here: script types, proof of funds, …)
 */
export function verifyMessageBip322(address, message, signature) {
    let script;
    try {
        script = bitcoin.address.toOutputScript(String(address), network);
    } catch (e) {
        return 'invalid';
    }
    const type = scriptType(script);
    let text = String(signature).replace(/\s+/g, '');
    let variant = 'smp';
    if (text.startsWith('smp')) {
        text = text.slice(3);
    } else if (text.startsWith('ful')) {
        variant = 'ful';
        text = text.slice(3);
    } else if (text.startsWith('pof')) {
        return 'unsupported';
    }
    const bytes = decodeBase64Strict(text);
    if (!bytes) return 'invalid';
    const toSpend = bip322ToSpend(script, String(message));
    let toSign;
    if (variant === 'smp') {
        // the simple variant exists only for native segwit addresses
        if (type !== 'p2tr' && type !== 'p2wpkh' && type !== 'p2wsh') return 'invalid';
        let witness;
        try {
            witness = decodeWitness(bytes);
        } catch (e) {
            return 'invalid';
        }
        toSign = bip322ToSign(toSpend);
        toSign.setWitness(0, witness);
    } else {
        try {
            toSign = bitcoin.Transaction.fromBuffer(bytes);
        } catch (e) {
            return 'invalid';
        }
        // exactly: one input spending to_spend:0, one OP_RETURN output of 0; version 0 or 2 (others: inconclusive)
        if (toSign.ins.length !== 1 || toSign.outs.length !== 1) return 'invalid';
        if (!toSign.ins[0].hash.equals(toSpend.getHash()) || toSign.ins[0].index !== 0) return 'invalid';
        if (toSign.outs[0].value !== 0 || !toSign.outs[0].script.equals(OP_RETURN_SCRIPT)) return 'invalid';
        if (toSign.version !== 0 && toSign.version !== 2) return 'unsupported';
    }
    return bip322VerifyInput(toSign, script, type);
}

/**
 * For tests and other implementations: [message hash, to_spend txid, to_sign txid] (hex) for an address and message.
 */
export function bip322Hashes(address, message) {
    const toSpend = bip322ToSpend(bitcoin.address.toOutputScript(String(address), network), String(message));
    return [bip322MessageHash(String(message)).toString('hex'), toSpend.getId(), bip322ToSign(toSpend).getId()];
}
