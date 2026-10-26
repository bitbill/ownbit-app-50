//  stellarjs-lib-bridge/index.js — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Readable source of the Ownbit entry module (browserify module 434) inside stellarjs-lib-app.min.js:
//  identical to it apart from comments, whitespace and the browserify wrapper. NOT loaded at runtime:
//  the Swift bridge loads stellarjs-lib-app.min.js itself. Kept for review only.
//  derivePath / getMasterKeyFromSeed / CKDPriv (SEP-0005 ed25519 derivation) follow the ed25519-hd-key package (MIT).

// Source of the entry module inside stellarjs-lib-app.min.js (browserify standalone, global `bridge`).
// 2026-10: regenerated from the shipped bundle (the old index.js was out of date) + the APP_CONTRACT.md 0.12 additions at the end.
// The bundle is patched in place (scripts/js-bundles/patch_xlm.js), so every existing export keeps the exact same code.

const StellarBase = require('stellar-base');

const bip39 = require('bip39');
const bip32 = require('bip32');

const STELLAR_MAINNET_PATH = "m/44'/148'/0'/0";
const STELLAR_MAINNET_CHANGE_PATH = "m/44'/148'/0'/1";
const STELLAR_MAINNET_PATH_NEW = "m/44'/148'/0'";

// generate a random mnemonic, entropy: strength, wordlist: word list
function generateMnemonicRandom(entropy, wordlist) {
    // Generate a random mnemonic (uses crypto.randomBytes under the hood), defaults to 128-bits of entropy
    return bip39.generateMnemonic(entropy, null, wordlist);
}

// generate a random mnemonic, entropy: strength,
function generateMnemonicRandomCN(entropy) {
    return generateMnemonicRandom(entropy, bip39.wordlists.chinese_simplified);
}

function mnemonicToSeedHex(mnemonic, password) {
    return bip39.mnemonicToSeedHex(mnemonic, password);
}

function validateMnemonic(mnemonic) {
    return bip39.validateMnemonic(mnemonic, bip39.wordlists.chinese_simplified) || bip39.validateMnemonic(mnemonic, bip39.wordlists.english);
}

/**
 * Checks if the given string is an address
 *
 * @method isAddress
 * @param {String} address the given HEX adress
 * @return {Boolean}
 */
function isAddress(address) {
    return StellarBase.StrKey.isValidEd25519PublicKey(address);
}

/* use bip32 start ---> */
const bip32Network = {
    wif: 0x80,
    bip32: {
        public: 0x0488b21e,
        private: 0x0488ade4
    }
};

function generateMasterKeychain(seedHex, path) {
    return bip32.fromSeed(Buffer.from(seedHex, 'hex'), bip32Network).derivePath(path || STELLAR_MAINNET_PATH);
}

function generateMasterKeychain_NEW(seedHex, path) {
    return bip32.fromSeed(Buffer.from(seedHex, 'hex'), bip32Network).derivePath(path || STELLAR_MAINNET_PATH_NEW);
}

function generateChangeKeychain(seedHex, path) {
    return bip32.fromSeed(Buffer.from(seedHex, 'hex'), bip32Network).derivePath(path || STELLAR_MAINNET_CHANGE_PATH);
}

/* <--- use bip32 end */

/**
 * Generate ed25519 key pair
 *
 * @param seed
 * @returns {Object} object with generated pub and prv
 */
function generateKeypair(seed) {
    const pair = seed ? StellarBase.Keypair.fromRawEd25519Seed(seed) : StellarBase.Keypair.random();
    return {
        pub: pair.publicKey(),
        prv: pair.secret()
    };
}

/**
 * Get encoded ed25519 public key from raw data
 *
 * @param pub {String} Raw public key
 * @returns {String} Encoded public key
 */
function getPubFromRaw(pub) {
    return StellarBase.StrKey.encodeEd25519PublicKey(Buffer.from(pub, 'hex'));
}

/**
 * Get encoded ed25519 private key from raw data
 *
 * @param prv {String} Raw private key
 * @returns {String} Encoded private key
 */
function getPrvFromRaw(prv) {
    return StellarBase.StrKey.encodeEd25519SecretSeed(Buffer.from(prv, 'hex'));
}

/**
 * Return boolean indicating whether input is valid public key for the coin.
 *
 * @param {String} pub the pub to be checked
 * @returns {Boolean} is it valid?
 */
function isValidPub(pub) {
    return StellarBase.StrKey.isValidEd25519PublicKey(pub);
}

/**
 * Return boolean indicating whether input is valid private key for the coin
 *
 * @param {String} prv the prv to be checked
 * @returns {Boolean} is it valid?
 */
function isValidPrv(prv) {
    return StellarBase.StrKey.isValidEd25519SecretSeed(prv);
}

/**
 * @param {String} seedHex
 * @returns {String} privateKey
 */
function getPrivkeyFromSeedHex(seedHex, isNew) {
    let keypair = getKeypairFromSeedHex(seedHex, isNew);
    //return keypair.rawSecretKey().toString('hex');
    //fixed by ownbit dev
    return keypair.secret();
}

/**
 * @param {String} seedHex
 * @returns {Array} [pub, address]
 */
function getPubAddrFromSeedHex(seedHex, isNew) {
    let kp = getKeypairFromSeedHex(seedHex, isNew);
    let rawPubKey = kp.rawPublicKey().toString('hex');
    let address = kp.publicKey();
    
    return [rawPubKey, address];
}

/**
 * @param {String} seedHex
 * @returns {Keypair} keypair
 * isNew = true for sep-0005
 */
function getKeypairFromSeedHex(seedHex, isNew) {
    if(isNew) {
        const data = derivePath(STELLAR_MAINNET_PATH_NEW, seedHex);
        
        return StellarBase.Keypair.fromRawEd25519Seed(data.key);
    }
    
    let hd = generateMasterKeychain(seedHex).derive(0);
    // console.log('hd.privateKey: ' + hd.privateKey.toString('hex'));
    return StellarBase.Keypair.fromRawEd25519Seed(hd.privateKey);
}

/**
 * @param {String|Buffer} privkey
 * @returns {String} publicKey
 */
function getPubkeyFromPrivkey(privkey) {
    let keypair = getKeypairFromPrivkey(privkey);
    return keypair.rawPublicKey().toString('hex');
}

/**
 * Instantiate an address from a pubkey
 *
 * @param {String} pubkey
 * @returns {String} address
 */
function getXlmAddrFromPubKey(pubkey) {
    return getPubFromRaw(pubkey);
}

/**
 * @param {String} privkey
 * @returns {Array} [pub, address]
 */
function getPubAddrFromPrivkey(privkey) {
    let pubkey = getPubkeyFromPrivkey(privkey);
    let address = getXlmAddrFromPubKey(pubkey);

    return [pubkey, address];
}

/**
 * @param {String} privkey
 * @returns {Keypair} keypair
 */
function getKeypairFromPrivkey(privkey) {
    // Stellar's Ed25519 public keys start with a G, while private keys start with an S
    if(typeof privkey === 'string') {
        if(privkey.startsWith('S')) {
            return StellarBase.Keypair.fromSecret(privkey);
        } else {
            privkey = Buffer.from(privkey, 'hex');
        }
    }

    return StellarBase.Keypair.fromRawEd25519Seed(privkey);
}

/**
 * @param {String} secret
 * @returns {Array} [pub, priv, address]
 */
function getKeypairAddrFromSecret(secret) {
    let keypair = StellarBase.Keypair.fromSecret(secret);
    let pubkey = keypair.publicKey();
    let privkey = keypair.secret();
    return [pubkey, keypair.rawPublicKey().toString('hex'), privkey, keypair.rawSecretKey().toString('hex'), pubkey];
}

/**
 * @param {String} rawSecret
 * @returns {Array} [pub, priv, address]
 */
function getKeypairAddrFromRawSecret(rawSecret) {
    let keypair = StellarBase.Keypair.fromRawEd25519Seed(new Buffer(rawSecret, 'hex'));
    let pubkey = keypair.publicKey();
    let privkey = keypair.secret();
    return [pubkey, keypair.rawPublicKey().toString('hex'), privkey, keypair.rawSecretKey().toString('hex'), pubkey];
}

/**
 * build xlm create account tx with privateKey.
 * @param {String} privateKey hex
 * @param {String} data
 * @param {String} memo text
 * @returns {Array}
 */
function buildCreateAccountTxWithPrivKey(privateKey, data, memo) {
    data = JSON.parse(data);

    StellarBase.Network.usePublicNetwork();

    memo = StellarBase.Memo.text(memo||'');
    let account=new StellarBase.Account(data['accountId'], data['sequence']);

    let txBuilder = new StellarBase.TransactionBuilder(account, {memo: memo, fee: StellarBase.BASE_FEE})
        .addOperation(StellarBase.Operation.createAccount({
            destination: data['destination'],
            startingBalance: data['startingBalance']
        }))
        .setTimeout(300)
        .build();

    let keypair = getKeypairFromPrivkey(privateKey);
    // console.log('buildCreateAccountTxWithPrivKey keypair: ' + JSON.stringify(keypair));
    txBuilder.sign(keypair);

    // console.log('buildCreateAccountTxWithPrivKey tx: ' + JSON.stringify(txBuilder));
    // console.log('buildCreateAccountTxWithPrivKey tx hash: ' + txBuilder.hash().toString('hex'));
    // console.log('buildCreateAccountTxWithPrivKey tx hex: ' + txBuilder.toEnvelope().toXDR('base64'));
    return [txBuilder.hash().toString('hex'), txBuilder.toEnvelope().toXDR('base64')];
}

/**
 * build xlm set-inflation tx with privateKey.
 * @param {String} privateKey hex
 * @param {String} data
 * @param {String} memo text
 * @returns {Array}
 */
function buildSetInflationTxWithPrivKey(privateKey, data, memo) {
    data = JSON.parse(data);

    StellarBase.Network.usePublicNetwork();

    memo = StellarBase.Memo.text(memo||'');
    let account=new StellarBase.Account(data['accountId'], data['sequence']);

    let txBuilder = new StellarBase.TransactionBuilder(account, {memo: memo, fee: StellarBase.BASE_FEE})
    // add a set-inflation operation to the transaction
        .addOperation(StellarBase.Operation.setOptions({
            inflationDest: data['inflationDest']
        }))
        .setTimeout(300)
        .build();

    let keypair = getKeypairFromPrivkey(privateKey);
    // console.log('buildSetInflationTxWithPrivKey keypair: ' + JSON.stringify(keypair));
    txBuilder.sign(keypair);

    // console.log('buildSetInflationTxWithPrivKey tx: ' + JSON.stringify(txBuilder));
    console.log('buildSetInflationTxWithPrivKey tx hash: ' + txBuilder.hash().toString('hex'));
    console.log('buildSetInflationTxWithPrivKey tx hex: ' + txBuilder.toEnvelope().toXDR('base64'));
    return [txBuilder.hash().toString('hex'), txBuilder.toEnvelope().toXDR('base64')];
}

/**
 * build xlm payment tx with privateKey.
 * @param {String} privateKey hex
 * @param {String} data
 * @param {String} memo text
 * @returns {Array}
 */
function buildPaymentTxWithPrivKey(privateKey, data, memo) {
    data = JSON.parse(data);

    StellarBase.Network.usePublicNetwork();

    memo = StellarBase.Memo.text(memo||'');
    let account=new StellarBase.Account(data['accountId'], data['sequence']);

    let txBuilder = new StellarBase.TransactionBuilder(account, {memo: memo, fee: StellarBase.BASE_FEE})
    // add a payment operation to the transaction
        .addOperation(StellarBase.Operation.payment({
            destination: data['destination'],
            asset: StellarBase.Asset.native(),
            amount: data['amount']
        }))
        .setTimeout(300)
        .build();

    let keypair = getKeypairFromPrivkey(privateKey);
    // console.log('buildPaymentTxWithPrivKey keypair: ' + JSON.stringify(keypair));
    txBuilder.sign(keypair);

    // console.log('buildPaymentTxWithPrivKey tx: ' + JSON.stringify(txBuilder));
    // console.log('buildPaymentTxWithPrivKey tx hash: ' + txBuilder.hash().toString('hex'));
    // console.log('buildPaymentTxWithPrivKey tx hex: ' + txBuilder.toEnvelope().toXDR('base64'));
    return [txBuilder.hash().toString('hex'), txBuilder.toEnvelope().toXDR('base64')];
}

/**
 * build xlm create account tx with seedHex.
 * @param {String} seedHex
 * @param {String} data
 * @param {String} memo text
 * @returns {Array}
 */
function buildCreateAccountTxWithSeedHex(seedHex, data, memo, xlmaddr) {
    data = JSON.parse(data);

    StellarBase.Network.usePublicNetwork();

    memo = StellarBase.Memo.text(memo||'');
    let account=new StellarBase.Account(data['accountId'], data['sequence']);

    let txBuilder = new StellarBase.TransactionBuilder(account, {memo: memo, fee: StellarBase.BASE_FEE})
        .addOperation(StellarBase.Operation.createAccount({
            destination: data['destination'],
            startingBalance: data['startingBalance']
        }))
        .setTimeout(300)
        .build();

    var keypair = getKeypairFromSeedHex(seedHex, true);
    if(xlmaddr != undefined && keypair.publicKey() != xlmaddr) {
        var keypair2 = getKeypairFromSeedHex(seedHex, false);
        if(keypair2.publicKey() == xlmaddr) {
            keypair = keypair2
        }
    }
    // console.log('buildCreateAccountTxWithPrivKey keypair: ' + JSON.stringify(keypair));
    txBuilder.sign(keypair);

    // console.log('buildCreateAccountTxWithPrivKey tx: ' + JSON.stringify(txBuilder));
    // console.log('buildCreateAccountTxWithPrivKey tx hash: ' + txBuilder.hash().toString('hex'));
    // console.log('buildCreateAccountTxWithPrivKey tx hex: ' + txBuilder.toEnvelope().toXDR('base64'));
    return [txBuilder.hash().toString('hex'), txBuilder.toEnvelope().toXDR('base64')];
}

/**
 * build xlm set-inflation tx with seedHex.
 * @param {String} seedHex
 * @param {String} data
 * @param {String} memo text
 * @returns {Array}
 */
function buildSetInflationTxWithSeedHex(seedHex, data, memo, xlmaddr) {
    data = JSON.parse(data);

    StellarBase.Network.usePublicNetwork();

    memo = StellarBase.Memo.text(memo||'');
    let account=new StellarBase.Account(data['accountId'], data['sequence']);

    let txBuilder = new StellarBase.TransactionBuilder(account, {memo: memo, fee: StellarBase.BASE_FEE})
    // add a set-inflation operation to the transaction
        .addOperation(StellarBase.Operation.setOptions({
            inflationDest: data['inflationDest']
        }))
        .setTimeout(300)
        .build();

    let keypair = getKeypairFromSeedHex(seedHex, true);
    if(xlmaddr != undefined && keypair.publicKey() != xlmaddr) {
        var keypair2 = getKeypairFromSeedHex(seedHex, false);
        if(keypair2.publicKey() == xlmaddr) {
            keypair = keypair2
        }
    }
    // console.log('buildSetInflationTxWithPrivKey keypair: ' + JSON.stringify(keypair));
    txBuilder.sign(keypair);

    // console.log('buildSetInflationTxWithPrivKey tx: ' + JSON.stringify(txBuilder));
    // console.log('buildSetInflationTxWithPrivKey tx hash: ' + txBuilder.hash().toString('hex'));
    // console.log('buildSetInflationTxWithPrivKey tx hex: ' + txBuilder.toEnvelope().toXDR('base64'));
    return [txBuilder.hash().toString('hex'), txBuilder.toEnvelope().toXDR('base64')];
}

/**
 * build xlm payment tx with privateKey.
 * @param {String} seedHex
 * @param {String} data
 * @param {String} memo text
 * @returns {Array}
 */
function buildPaymentTxWithSeedHex(seedHex, data, memo, xlmaddr) {
    data = JSON.parse(data);

    StellarBase.Network.usePublicNetwork();

    memo = StellarBase.Memo.text(memo||'');
    let account=new StellarBase.Account(data['accountId'], data['sequence']);

    let txBuilder = new StellarBase.TransactionBuilder(account, {memo: memo, fee: StellarBase.BASE_FEE})
    // add a payment operation to the transaction
        .addOperation(StellarBase.Operation.payment({
            destination: data['destination'],
            asset: StellarBase.Asset.native(),
            amount: data['amount']
        }))
        .setTimeout(300)
        .build();

    let keypair = getKeypairFromSeedHex(seedHex, true);
    if(xlmaddr != undefined && keypair.publicKey() != xlmaddr) {
        var keypair2 = getKeypairFromSeedHex(seedHex, false);
        if(keypair2.publicKey() == xlmaddr) {
            keypair = keypair2
        }
    }
    // console.log('buildPaymentTxWithPrivKey keypair: ' + JSON.stringify(keypair));
    txBuilder.sign(keypair);

    // console.log('buildPaymentTxWithPrivKey tx: ' + JSON.stringify(txBuilder));
    // console.log('buildPaymentTxWithPrivKey tx hash: ' + txBuilder.hash().toString('hex'));
    // console.log('buildPaymentTxWithPrivKey tx hex: ' + txBuilder.toEnvelope().toXDR('base64'));
    return [txBuilder.hash().toString('hex'), txBuilder.toEnvelope().toXDR('base64')];
}


module.exports = {
    generateMnemonicRandom: generateMnemonicRandom,
    generateMnemonicRandomCN: generateMnemonicRandomCN,
    mnemonicToSeedHex: mnemonicToSeedHex,
    validateMnemonic: validateMnemonic,
    isAddress: isAddress,
    getPubkeyFromPrivkey: getPubkeyFromPrivkey,
    getXlmAddrFromPubKey: getXlmAddrFromPubKey,
    getPubAddrFromPrivkey: getPubAddrFromPrivkey,
    getPrivkeyFromSeedHex: getPrivkeyFromSeedHex,
    getPubAddrFromSeedHex: getPubAddrFromSeedHex,
    getKeypairAddrFromSecret: getKeypairAddrFromSecret,
    getKeypairAddrFromRawSecret: getKeypairAddrFromRawSecret,
    buildCreateAccountTxWithPrivKey: buildCreateAccountTxWithPrivKey,
    buildSetInflationTxWithPrivKey: buildSetInflationTxWithPrivKey,
    buildPaymentTxWithPrivKey: buildPaymentTxWithPrivKey,
    buildCreateAccountTxWithSeedHex: buildCreateAccountTxWithSeedHex,
    buildSetInflationTxWithSeedHex: buildSetInflationTxWithSeedHex,
    buildPaymentTxWithSeedHex: buildPaymentTxWithSeedHex,
};

//conforms to sep-0005
const createHmac = require("create-hmac");

const ED25519_CURVE = 'ed25519 seed';
const HARDENED_OFFSET = 0x80000000;

const derivePath = (path, seed) => {
    if (!isValidPath(path)) {
        throw new Error('Invalid derivation path');
    }
    const { key, chainCode } = getMasterKeyFromSeed(seed);
    const segments = path
    .split('/')
    .slice(1)
    .map(replaceDerive)
    .map(el => parseInt(el, 10));
    return segments.reduce(
                           (parentKeys, segment) =>
                           CKDPriv(parentKeys, segment + HARDENED_OFFSET),
                           { key, chainCode }
                           );
};

const getMasterKeyFromSeed = (seed) => {
    const hmac = createHmac('sha512', ED25519_CURVE);
    const I = hmac.update(Buffer.from(seed, 'hex')).digest();
    const IL = I.slice(0, 32);
    const IR = I.slice(32);
    return {
    key: IL,
    chainCode: IR,
    };
};

const CKDPriv = ({ key, chainCode }, index) => {
    const indexBuffer = Buffer.allocUnsafe(4);
    indexBuffer.writeUInt32BE(index, 0);
    const data = Buffer.concat([Buffer.alloc(1, 0), key, indexBuffer]);
    const I = createHmac('sha512', chainCode)
    .update(data)
    .digest();
    const IL = I.slice(0, 32);
    const IR = I.slice(32);
    return {
    key: IL,
    chainCode: IR,
    };
};

const replaceDerive = (val) => val.replace("'", '');
const pathRegex = new RegExp("^m(\\/[0-9]+')+$");
const isValidPath = (path) => {
    if (!pathRegex.test(path)) {
        return false;
    }
    return !path
    .split('/')
    .slice(1)
    .map(replaceDerive)
    .some(isNaN);
};



/* ---- 2026-10 additions (APP_CONTRACT.md 0.12): XLM tokens + account multisig. Existing exports above are unchanged. ---- */
const BIL_PUBNET_PASSPHRASE = 'Public Global Stellar Network ; September 2015';
const BIL_MAX_TRUST_LIMIT = '922337203685.4775807';

function bilNeed(ok, msg) {
    if (!ok) throw new Error(msg);
}

function bilUsePubnet() {
    StellarBase.Network.usePublicNetwork();
    bilNeed(StellarBase.Network.current().networkPassphrase() === BIL_PUBNET_PASSPHRASE, 'network passphrase mismatch');
}

// same key choice as buildPaymentTxWithSeedHex: SEP-0005 first, legacy key only when it matches xlmaddr
function bilSingleSigKeypair(seedHex, xlmaddr) {
    let keypair = getKeypairFromSeedHex(seedHex, true);
    if (xlmaddr != undefined && keypair.publicKey() != xlmaddr) {
        const keypair2 = getKeypairFromSeedHex(seedHex, false);
        if (keypair2.publicKey() == xlmaddr) {
            keypair = keypair2;
        }
    }
    return keypair;
}

// SEP-0005 m/44'/148'/k' (k = 0 is the multisig signer key)
function bilIndexKeypair(seedHex, k) {
    k = Number(k);
    bilNeed(Number.isInteger(k) && k >= 0 && k < 2147483648, 'invalid index');
    return StellarBase.Keypair.fromRawEd25519Seed(derivePath("m/44'/148'/" + k + "'", seedHex).key);
}

function bilAsset(code, issuer) {
    bilNeed(typeof code === 'string' && /^[A-Za-z0-9]{1,12}$/.test(code), 'invalid asset code');
    bilNeed(StellarBase.StrKey.isValidEd25519PublicKey(issuer), 'invalid asset issuer');
    return new StellarBase.Asset(code, issuer);
}

function bilAccount(id, sequence) {
    bilNeed(StellarBase.StrKey.isValidEd25519PublicKey(id), 'invalid account');
    bilNeed(typeof sequence === 'string' && /^[0-9]+$/.test(sequence), 'invalid sequence');
    return new StellarBase.Account(id, sequence);
}

function bilDecimal(v, name) {
    bilNeed(typeof v === 'string' && /^[0-9]+(\.[0-9]{1,7})?$/.test(v), 'invalid ' + name);
    return v;
}

function bilMaxTime(v) {
    if (v === undefined || v === null || v === '') return null;
    const n = Number(v);
    bilNeed(Number.isInteger(n) && n > 0, 'invalid maxTime');
    return n;
}

function bilSingleSigBuilder(data, memo) {
    const opts = {fee: data['fee'] ? Number(data['fee']) : StellarBase.BASE_FEE};
    if (memo !== null) opts.memo = memo;
    const maxTime = bilMaxTime(data['maxTime']);
    if (maxTime) opts.timebounds = {minTime: 0, maxTime: maxTime};
    return {builder: new StellarBase.TransactionBuilder(bilAccount(data['accountId'], String(data['sequence'])), opts), timed: !!maxTime};
}

function bilFinishSingle(b, keypair) {
    const tx = (b.timed ? b.builder : b.builder.setTimeout(300)).build();
    tx.sign(keypair);
    return [tx.hash().toString('hex'), tx.toEnvelope().toXDR('base64')];
}

function bilTokenPayment(keypair, data, memo) {
    data = JSON.parse(data);
    bilUsePubnet();
    const b = bilSingleSigBuilder(data, StellarBase.Memo.text(memo || ''));
    bilNeed(StellarBase.StrKey.isValidEd25519PublicKey(data['destination']), 'invalid destination');
    b.builder.addOperation(StellarBase.Operation.payment({
        destination: data['destination'],
        asset: bilAsset(data['assetCode'], data['assetIssuer']),
        amount: bilDecimal(data['amount'], 'amount')
    }));
    return bilFinishSingle(b, keypair);
}

function bilChangeTrust(keypair, data) {
    data = JSON.parse(data);
    bilUsePubnet();
    const b = bilSingleSigBuilder(data, null);
    b.builder.addOperation(StellarBase.Operation.changeTrust({
        asset: bilAsset(data['assetCode'], data['assetIssuer']),
        limit: bilDecimal(data['limit'] === undefined ? BIL_MAX_TRUST_LIMIT : data['limit'], 'limit')
    }));
    return bilFinishSingle(b, keypair);
}

function buildTokenPaymentTxWithSeedHex(seedHex, data, memo, xlmaddr) {
    return bilTokenPayment(bilSingleSigKeypair(seedHex, xlmaddr), data, memo);
}

function buildTokenPaymentTxWithPrivKey(privateKey, data, memo) {
    return bilTokenPayment(getKeypairFromPrivkey(privateKey), data, memo);
}

function buildChangeTrustTxWithSeedHex(seedHex, data, xlmaddr) {
    return bilChangeTrust(bilSingleSigKeypair(seedHex, xlmaddr), data);
}

function buildChangeTrustTxWithPrivKey(privateKey, data) {
    return bilChangeTrust(getKeypairFromPrivkey(privateKey), data);
}

function getPubAddrFromSeedHexIndex(seedHex, k) {
    const kp = bilIndexKeypair(seedHex, k);
    return [kp.rawPublicKey().toString('hex'), kp.publicKey()];
}

// 5.5.1 setup: 0..5 change_trust, N set_options signer, 1 set_options master 0 + thresholds M
function buildMsSetupTxWithSeedHexIndex(seedHex, k, info) {
    info = JSON.parse(info);
    bilUsePubnet();
    const fresh = bilIndexKeypair(seedHex, k);
    bilNeed(Number(k) > 0, 'invalid index');
    bilNeed(fresh.publicKey() === info['address'], 'derived address mismatch');
    const serverTime = Number(info['serverTime']);
    bilNeed(Number.isInteger(serverTime) && serverTime > 0, 'invalid serverTime');
    const maxTime = bilMaxTime(info['maxTime']) || serverTime + 600;
    bilNeed(maxTime >= serverTime + 60 && maxTime <= serverTime + 3600, 'invalid maxTime');
    const perOpFee = Number(info['perOpFee']);
    bilNeed(Number.isInteger(perOpFee) && perOpFee >= 100 && perOpFee <= 100000, 'invalid perOpFee');
    const signers = info['signers'];
    bilNeed(Array.isArray(signers) && signers.length >= 1 && signers.length <= 20, 'invalid signers');
    const m = Number(info['requireNum']);
    bilNeed(Number.isInteger(m) && m >= 1 && m <= signers.length, 'invalid requireNum');
    const trustAssets = info['trustAssets'] || [];
    bilNeed(Array.isArray(trustAssets) && trustAssets.length <= 5, 'invalid trustAssets');

    const b = new StellarBase.TransactionBuilder(bilAccount(info['address'], String(info['sequence'])), {
        fee: perOpFee,
        timebounds: {minTime: 0, maxTime: maxTime}
    });
    const seen = {};
    trustAssets.forEach(a => {
        const key = a['code'] + '-' + a['issuer'];
        bilNeed(!seen[key], 'duplicate trust asset');
        seen[key] = true;
        b.addOperation(StellarBase.Operation.changeTrust({asset: bilAsset(a['code'], a['issuer'])}));
    });
    const seenSigner = {};
    signers.forEach(g => {
        bilNeed(StellarBase.StrKey.isValidEd25519PublicKey(g) && g !== info['address'] && !seenSigner[g], 'invalid signer');
        seenSigner[g] = true;
        b.addOperation(StellarBase.Operation.setOptions({signer: {ed25519PublicKey: g, weight: 1}}));
    });
    b.addOperation(StellarBase.Operation.setOptions({masterWeight: 0, lowThreshold: m, medThreshold: m, highThreshold: m}));
    const tx = b.build();
    tx.sign(fresh);
    return [tx.hash().toString('hex'), tx.toEnvelope().toXDR('base64')];
}

function bilMemo(type, memo) {
    if (type === undefined || type === null || type === '' || type === 'none') return StellarBase.Memo.none();
    if (type === 'text') {
        bilNeed(typeof memo === 'string' && Buffer.byteLength(memo, 'utf8') <= 28, 'invalid memo');
        return StellarBase.Memo.text(memo);
    }
    if (type === 'id') {
        bilNeed(typeof memo === 'string' && /^[0-9]{1,20}$/.test(memo), 'invalid memo');
        return StellarBase.Memo.id(memo);
    }
    throw new Error('invalid memoType');
}

// 5.7.1: unsigned Transaction XDR (tx.tx.toXDR, not the envelope)
function buildMsTxXdr(data) {
    data = JSON.parse(data);
    bilUsePubnet();
    const fee = Number(data['fee']);
    bilNeed(Number.isInteger(fee) && fee >= 100 && fee <= 100000, 'invalid fee');
    const maxTime = bilMaxTime(data['maxTime']);
    bilNeed(!!maxTime, 'invalid maxTime');
    const b = new StellarBase.TransactionBuilder(bilAccount(data['source'], String(data['sequence'])), {
        fee: fee,
        timebounds: {minTime: 0, maxTime: maxTime},
        memo: bilMemo(data['memoType'], data['memo'])
    });
    const opType = data['opType'];
    if (opType === 'payment') {
        bilNeed(StellarBase.StrKey.isValidEd25519PublicKey(data['destination']), 'invalid destination');
        const asset = data['assetCode'] ? bilAsset(data['assetCode'], data['assetIssuer']) : StellarBase.Asset.native();
        b.addOperation(StellarBase.Operation.payment({destination: data['destination'], asset: asset, amount: bilDecimal(data['amount'], 'amount')}));
    } else if (opType === 'create_account') {
        bilNeed(StellarBase.StrKey.isValidEd25519PublicKey(data['destination']), 'invalid destination');
        b.addOperation(StellarBase.Operation.createAccount({destination: data['destination'], startingBalance: bilDecimal(data['amount'], 'amount')}));
    } else if (opType === 'change_trust') {
        b.addOperation(StellarBase.Operation.changeTrust({
            asset: bilAsset(data['assetCode'], data['assetIssuer']),
            limit: bilDecimal(data['limit'] === undefined ? BIL_MAX_TRUST_LIMIT : data['limit'], 'limit')
        }));
    } else {
        throw new Error('invalid opType');
    }
    const tx = b.build();
    return [tx.hash().toString('hex'), tx.tx.toXDR('base64')];
}

function bilAssetFields(xdrAsset) {
    const t = xdrAsset.switch().name;
    if (t === 'assetTypeNative') return {assetCode: '', assetIssuer: ''};
    bilNeed(t === 'assetTypeCreditAlphanum4' || t === 'assetTypeCreditAlphanum12', 'asset_type');
    const a = StellarBase.Asset.fromOperation(xdrAsset);
    return {assetCode: a.getCode(), assetIssuer: a.getIssuer()};
}

// strict structural whitelist (5.7.1); server-side value rules (fee range, minTime 0, maxTime window) are checked by the caller
function bilDecodeTx(txXdrBase64) {
    bilNeed(typeof txXdrBase64 === 'string' && txXdrBase64.length > 0, 'xdr_decode_error');
    bilUsePubnet();
    let txx;
    try {
        txx = StellarBase.xdr.Transaction.fromXDR(txXdrBase64, 'base64');
    } catch (e) {
        throw new Error('xdr_decode_error');
    }
    bilNeed(txx.toXDR('base64') === txXdrBase64, 'trailing_bytes');
    bilNeed(txx.ext().switch() === 0, 'xdr_decode_error');
    const tb = txx.timeBounds();
    bilNeed(!!tb, 'precondition_type');
    const ops = txx.operations();
    bilNeed(ops.length === 1, 'op_count');
    bilNeed(!ops[0].sourceAccount(), 'op_source_present');
    const tx = new StellarBase.Transaction(new StellarBase.xdr.TransactionEnvelope({tx: txx, signatures: []}));
    const out = {
        source: tx.source,
        fee: String(txx.fee()),
        seqNum: txx.seqNum().toString(),
        minTime: Number(tb.minTime().toString()),
        maxTime: Number(tb.maxTime().toString()),
        memoType: 'none', memo: '',
        opType: '', destination: '', assetCode: '', assetIssuer: '', amount: '', limit: '',
        hashHex: tx.hash().toString('hex')
    };
    const memo = txx.memo();
    const mt = memo.switch().name;
    if (mt === 'memoText') {
        out.memoType = 'text';
        out.memo = Buffer.from(memo.text()).toString('utf8');
    } else if (mt === 'memoId') {
        out.memoType = 'id';
        out.memo = memo.id().toString();
    } else {
        bilNeed(mt === 'memoNone', 'memo_type');
    }
    const body = ops[0].body();
    const ot = body.switch().name;
    if (ot === 'createAccount') {
        const v = body.createAccountOp();
        out.opType = 'create_account';
        out.destination = StellarBase.StrKey.encodeEd25519PublicKey(v.destination().ed25519());
        out.amount = v.startingBalance().toString();
    } else if (ot === 'payment') {
        const v = body.paymentOp();
        out.opType = 'payment';
        out.destination = StellarBase.StrKey.encodeEd25519PublicKey(v.destination().ed25519());
        const af = bilAssetFields(v.asset());
        out.assetCode = af.assetCode;
        out.assetIssuer = af.assetIssuer;
        out.amount = v.amount().toString();
    } else if (ot === 'changeTrust') {
        const v = body.changeTrustOp();
        out.opType = 'change_trust';
        const af = bilAssetFields(v.line());
        bilNeed(af.assetCode !== '', 'asset_type');
        out.assetCode = af.assetCode;
        out.assetIssuer = af.assetIssuer;
        out.limit = v.limit().toString();
        bilNeed(out.limit !== '0', 'change_trust_limit');
    } else {
        throw new Error('op_type');
    }
    return {tx: tx, out: out};
}

// amount / limit are raw int64 strings (stroops, or token units x 10^7)
function decodeMsTxXdr(txXdrBase64) {
    return JSON.stringify(bilDecodeTx(txXdrBase64).out);
}

// 5.7.2: hash computed locally from the XDR, signed with the signer key m/44'/148'/0'. No "sign arbitrary hash" function.
function signMsTxXdrWithSeedHex(seedHex, txXdrBase64) {
    const d = bilDecodeTx(txXdrBase64);
    const hash = d.tx.hash();
    const sig = bilIndexKeypair(seedHex, 0).sign(hash).toString('base64');
    bilNeed(sig.length === 88, 'sign failed');
    return [hash.toString('hex'), sig];
}

Object.assign(module.exports, {
    buildTokenPaymentTxWithSeedHex: buildTokenPaymentTxWithSeedHex,
    buildTokenPaymentTxWithPrivKey: buildTokenPaymentTxWithPrivKey,
    buildChangeTrustTxWithSeedHex: buildChangeTrustTxWithSeedHex,
    buildChangeTrustTxWithPrivKey: buildChangeTrustTxWithPrivKey,
    getPubAddrFromSeedHexIndex: getPubAddrFromSeedHexIndex,
    buildMsSetupTxWithSeedHexIndex: buildMsSetupTxWithSeedHexIndex,
    buildMsTxXdr: buildMsTxXdr,
    decodeMsTxXdr: decodeMsTxXdr,
    signMsTxXdrWithSeedHex: signMsTxXdrWithSeedHex,
});

