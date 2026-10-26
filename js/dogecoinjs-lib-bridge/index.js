//  dogecoinjs-lib-bridge/index.js — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Readable source of the Ownbit entry module (browserify module 1) inside dogecoinjs-lib-app.min.js:
//  identical to it apart from comments, whitespace and the browserify wrapper. NOT loaded at runtime:
//  the Swift bridge loads dogecoinjs-lib-app.min.js itself. Kept for review only.

var doge = require('dogecore-lib');
var bip39 = require('bip39');
var wif = require('wif');
var bs58check = require('bs58check');
var Address = doge.Address;
var Networks = doge.Networks;
var HDPrivateKey = doge.HDPrivateKey;
var HDPublicKey = doge.HDPublicKey;
var PrivateKey = doge.PrivateKey;
var PublicKey = doge.PublicKey;
var PublicKey = doge.PublicKey;
var Script = doge.Script;

var DOGE_MAINNET_PATH = "m/44'/3'/0'/0";
var DOGE_MAINNET_CHANGE_PATH = "m/44'/3'/0'/1";
var DOGE_MAINNET_ROOT_PATH = "m/44'/3'/0'";

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
    return Address.isValid(address, Networks.livenet);
}

function generateMasterKeychain(seedHex) {
    return HDPrivateKey.fromSeed(seedHex, Networks.livenet).derive(DOGE_MAINNET_PATH);
}

function generateChangeKeychain(seedHex) {
    return HDPrivateKey.fromSeed(seedHex, Networks.livenet).derive(DOGE_MAINNET_CHANGE_PATH);
}

function generateRootKeychain(seedHex) {
    return HDPrivateKey.fromSeed(seedHex, Networks.livenet).derive(DOGE_MAINNET_ROOT_PATH);
}

function getMasterXpubkey(seedHex) {
    var keychain = generateMasterKeychain(seedHex);
    return keychain.xpubkey;
}

function getChangeXpubkey(seedHex) {
    var keychain = generateChangeKeychain(seedHex);
    return keychain.xpubkey;
}

function getXpubkeys(seedHex) {
    return new Array(getMasterXpubkey(seedHex), getChangeXpubkey(seedHex), generateRootKeychain(seedHex).xpubkey);
}

function getPubkeyhashFromAddr(addr) {
    return new Address(addr, 'livenet', 'pubkeyhash').toBuffer().slice(1).toString('hex');
}

function getScripthashFromAddr(addr) {
    return new Address(addr, 'livenet', 'scripthash').toBuffer().slice(1).toString('hex');
}

/**
 * @param {String} seedHex
 * @param {Number} index
 * @returns {String} An address generated from seedHex, index
 */
function getDogeAddrFromSeedHex(seedHex, index) {
    var keychain = generateMasterKeychain(seedHex);
    return keychain.derive(index).publicKey.toAddress().toString();
}

/**
 * @param {String} seedHex
 * @param {Number} index
 * @returns {String} publicKey
 */
function getPubkeyFromSeedHex(seedHex, index) {
    var keychain = generateMasterKeychain(seedHex);
    return keychain.derive(index).publicKey.toString();
}

/**
 * @param {String} seedHex
 * @param {Number} index
 * @returns {String} privateKey
 */
function getPrivkeyFromSeedHex(seedHex, index, isChange) {
    var keychain = null;
    if(isChange){
        keychain = generateChangeKeychain(seedHex);
    }else{
        keychain = generateMasterKeychain(seedHex);
    }
    return keychain.derive(index).privateKey.toWIF();
}

/**
 * @param {String} privkey
 * @returns {String} publicKey
 */
function getPubkeyFromPrivkey(privkey) {
    var privateKey = new PrivateKey(new Buffer(privkey, 'hex'));
    return privateKey.publicKey.toString();
}

/**
 * Instantiate an address from a pubkey
 *
 * @param {String} pubkey
 * @returns {String} address
 */
function getDogeAddrFromPubKey(pubkey) {
    pubkey = new PublicKey(pubkey);
    return Address.fromPublicKey(pubkey, Networks.livenet).toString();
}

/**
 * @param {String} privkey
 * @returns {Array} [publicKey, address]
 */
/*
function getPubkeyAndAddrFromPrivkey(privkey) {
    var pubkey = getPubkeyFromPrivkey(privkey);
    var addr = getDogeAddrFromPubKey(pubkey);
    return [pubkey, addr];
}
 */

function privateKeyFromKey(key) {
    var _wif = '';
    var _startWith = key.charAt(0);
    
    if(key.match(/^[0-9a-f]+$/i)) {
        var prvKey = new Buffer(key, 'hex');
        _wif = wif.encode(0x9e, prvKey, false);
    } else if(_startWith === '6' || _startWith === 'Q') {
        _wif = key;
    }
    return PrivateKey.fromWIF(_wif);
}


function getPubkeyAndAddrFromPrivkey(privkey) {
    privkey = privateKeyFromKey(privkey);
    return [privkey.publicKey.toString(),Address.fromPublicKey(privkey.publicKey, Networks.livenet).toString()];
}

/**
 * Instantiate an address from xpub, index
 *
 * @param {String} xpub
 * @param {Number} index
 * @returns {String} address
 */
function getDogeAddrFromXpubkey(xpub, index) {
    var keychain = new HDPublicKey(xpub);
    return keychain.derive(index).publicKey.toAddress().toString();
}


/**
 * Instantiate an addresses from xpub, fromIndex, toIndex
 *
 * @param {String} xpub
 * @param {Number} fromIndex
 * @param {Number} toIndex
 * @returns {Array} addresses
 */
function getDogeContinuousAddrFromXpubkey(xpub, fromIndex, toIndex) {
    var keychain = new HDPublicKey(xpub);
    var addresses = new Array();
    for (var i = fromIndex, j = 0; i <= toIndex; i++, j++) {
        addresses[j] = keychain.derive(i).publicKey.toAddress().toString();
    }
    return addresses;
}

/**
 * build doge tx with seedHex.
 * @param {String} seedHex
 * @param {String} data
 * @returns {Array}
 */
function buildDogeTransaction (seedHex, data) {
    data = JSON.parse(data);
    var inputs = data["inputs"];
    var outputs = data["outputs"];

    var keychain = generateMasterKeychain(seedHex);
    var changeKeychain = generateChangeKeychain(seedHex);
    var privateKeys = [];
    var tx = new doge.Transaction();

    for (var i = 0; i < inputs.length; i++) {
        var input = inputs[i];
        tx.from({
            txId: input.txid,
            outputIndex: input.vout,
            script: input.scriptPubKey,
            satoshis: input.satoshis
        });
        var isChange = input["isChange"];
        privateKeys[i] = (isChange ? changeKeychain : keychain).derive(input["bip39Index"]).privateKey.toString();
    }

    for (var _i = 0; _i < outputs.length; _i++) {
        var output = outputs[_i];
        tx = tx.to(output["address"], output["amount"]);
    }

    // console.log('privateKeys: ' + JSON.stringify(privateKeys));
    tx = tx.sign(privateKeys);
    // console.log('txid: ' + tx.id);
    return [tx.id, tx.toString()];
}

/**
 * build doge tx with privateKey.
 * @param {String} privateKey hex
 * @param {String} data
 * @returns {Array}
 */
function buildDogeTxWithPrivateKey (privateKey, data) {
    data = JSON.parse(data);
    var inputs = data["inputs"];
    var outputs = data["outputs"];
    //var privkey = new PrivateKey(new Buffer(privateKey, 'hex'));
    
    var privkey = privateKeyFromKey(privateKey);

    var tx = new doge.Transaction();

    for (var i = 0; i < inputs.length; i++) {
        var input = inputs[i];
        tx.from({
            txId: input.txid,
            outputIndex: input.vout,
            script: input.scriptPubKey,
            satoshis: input.satoshis
        });
    }

    for (var _i = 0; _i < outputs.length; _i++) {
        var output = outputs[_i];
        tx = tx.to(output["address"], output["amount"]);
    }

    tx = tx.sign(privkey);
    // console.log('txid: ' + tx.id);
    return [tx.id, tx.toString()];
}

function getSignatureWithPrivateKey(privateKey, data, m, pubKeys) {
    data = JSON.parse(data);
    var inputs = data["inputs"];
    var outputs = data["outputs"];
    var signatures = [];
    
    if(typeof pubKeys === 'string') {
        pubKeys = JSON.parse(pubKeys);
    }
    
    var tx = new doge.Transaction();
    
    for (var i = 0; i < inputs.length; i++) {
        var input = inputs[i];
        tx.from({
                txId: input.txid,
                outputIndex: input.vout,
                script: new Script(new Address(pubKeys, m)).toHex(),
                satoshis: input.satoshis
                }, pubKeys, m);
    }
    
    for (var _i = 0; _i < outputs.length; _i++) {
        var output = outputs[_i];
        tx = tx.to(output["address"], output["amount"]);
    }
    
    var signatureObjs = tx.getSignatures(privateKey);
    
    for (var _i2 = 0; _i2 < signatureObjs.length; _i2++) {
        signatures[_i2] = signatureObjs[_i2].signature.toString('hex');
    }
    
    return signatures;
}

module.exports = {
    generateMnemonicRandom: generateMnemonicRandom,
    generateMnemonicRandomCN: generateMnemonicRandomCN,
    mnemonicToSeedHex: mnemonicToSeedHex,
    validateMnemonic: validateMnemonic,
    isAddress: isAddress,
    getMasterXpubkey: getMasterXpubkey,
    getChangeXpubkey: getChangeXpubkey,
    getXpubkeys: getXpubkeys,
    getPubkeyhashFromAddr: getPubkeyhashFromAddr,
    getScripthashFromAddr: getScripthashFromAddr,
    getDogeAddrFromSeedHex: getDogeAddrFromSeedHex,
    getPrivkeyFromSeedHex: getPrivkeyFromSeedHex,
    getPubkeyFromPrivkey: getPubkeyFromPrivkey,
    getPubkeyFromSeedHex: getPubkeyFromSeedHex,
    getDogeAddrFromPubKey: getDogeAddrFromPubKey,
    getPubkeyAndAddrFromPrivkey: getPubkeyAndAddrFromPrivkey,
    getDogeAddrFromXpubkey: getDogeAddrFromXpubkey,
    getDogeContinuousAddrFromXpubkey: getDogeContinuousAddrFromXpubkey,
    buildDogeTransaction: buildDogeTransaction,
    buildDogeTxWithPrivateKey: buildDogeTxWithPrivateKey,
    getSignatureWithPrivateKey: getSignatureWithPrivateKey
};
