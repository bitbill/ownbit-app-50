//  horizenjs-lib-bridge/index.js — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Readable source of the Ownbit entry module (browserify module 81) inside zenjs-lib-app.min.js:
//  identical to it apart from comments, whitespace and the browserify wrapper. NOT loaded at runtime:
//  the Swift bridge loads zenjs-lib-app.min.js itself. Kept for review only.
//  fromBase58Check / isValidAddr follow bitcoinjs-lib address.fromBase58Check (MIT).
//  Removed from this copy only: one console.log in buildZenTransaction that printed the private keys
//  (the shipped bundle still contains it). Nothing else differs.

//var zen = require('zencashjs');
var bip39 = require('bip39');
var bip32 = require('bip32');
var wif = require('wif');
var bs58check = require('bs58check');
var Address = require('./node_modules/zencashjs/lib/address.js');
var Config = require('./node_modules/zencashjs/lib/config');
var Transaction = require('./node_modules/zencashjs/lib/transaction');
var zcrypto = require('./node_modules/zencashjs/lib/crypto');

/*
var Address = zen.Address;
var Networks = zen.Networks;
var HDPrivateKey = zen.HDPrivateKey;
var HDPublicKey = zen.HDPublicKey;
var PrivateKey = zen.PrivateKey;
var PublicKey = zen.PublicKey;
 */

var ZEN_MAINNET_PATH = "m/44'/121'/0'/0";
var ZEN_MAINNET_CHANGE_PATH = "m/44'/121'/0'/1";
var ZEN_MAINNET_ROOT_PATH = "m/44'/121'/0'";

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
    return isValidAddr(address);
}

function generateMasterKeychain(seedHex) {
    return bip32.fromSeed(Buffer.from(seedHex, 'hex')).derivePath(ZEN_MAINNET_PATH);
}

function generateChangeKeychain(seedHex) {
    return bip32.fromSeed(Buffer.from(seedHex, 'hex')).derivePath(ZEN_MAINNET_CHANGE_PATH);
}

function generateRootKeychain(seedHex) {
    return bip32.fromSeed(Buffer.from(seedHex, 'hex')).derivePath(ZEN_MAINNET_ROOT_PATH);
}

function getMasterXpubkey(seedHex) {
    var keychain = generateMasterKeychain(seedHex);
    return keychain.neutered().toBase58();
}

function getChangeXpubkey(seedHex) {
    var keychain = generateChangeKeychain(seedHex);
    return keychain.neutered().toBase58();
}

function getRootXpubkey(seedHex) {
    var keychain = generateRootKeychain(seedHex);
    return keychain.neutered().toBase58();
}

function getXpubkeys(seedHex) {
    return new Array(getMasterXpubkey(seedHex), getChangeXpubkey(seedHex), getRootXpubkey(seedHex));
}

/**
 * @param {String} seedHex
 * @param {Number} index
 * @returns {String} An address generated from seedHex, index
 */
function getZenAddrFromSeedHex(seedHex, index) {
    var keychain = generateMasterKeychain(seedHex);
    var pubKey = keychain.derive(index).publicKey.toString('hex');
    return Address.pubKeyToAddr(pubKey);
}

function getPrivkeyFromSeedHex(seedHex, index, isChange) {
    var keychain = null;
    if(isChange){
        keychain = generateChangeKeychain(seedHex);
    }else{
        keychain = generateMasterKeychain(seedHex);
    }
    return wif.encode(128, keychain.derive(index).privateKey, true);
}

/**
 * @param {String} privkey
 * @returns {String} publicKey
 */
function getPubkeyFromPrivkey(privkey) {
    return Address.privKeyToPubKey(privkey);
}

/**
 * Instantiate an address from a pubkey
 *
 * @param {String} pubkey
 * @returns {String} address
 */
function getZenAddrFromPubKey(pubkey) {
    return Address.pubKeyToAddr(pubkey);
}

/**
 * @param {String} privkey
 * @returns {Array} [publicKey, address]
 */
function getPubkeyAndAddrFromPrivkey(privkey) {
    var pubkey = getPubkeyFromPrivkey(privkey);
    var addr = getZenAddrFromPubKey(pubkey);
    return [pubkey, addr];
}

/**
 * Instantiate an address from xpub, index
 *
 * @param {String} xpub
 * @param {Number} index
 * @returns {String} address
 */
function getZenAddrFromXpubkey(xpub, index) {
    var node = bip32.fromBase58(xpub);
    var pubKey = node.derive(index).publicKey.toString('hex');
    return Address.pubKeyToAddr(pubKey);
}


/**
 * Instantiate an addresses from xpub, fromIndex, toIndex
 *
 * @param {String} xpub
 * @param {Number} fromIndex
 * @param {Number} toIndex
 * @returns {Array} addresses
 */
function getZenContinuousAddrFromXpubkey(xpub, fromIndex, toIndex) {
    var node = bip32.fromBase58(xpub);
    var addresses = new Array();
    for (var i = fromIndex, j = 0; i <= toIndex; i++, j++) {
        var pubKey = node.derive(i).publicKey.toString('hex');
        addresses[j] = Address.pubKeyToAddr(pubKey);
    }
    return addresses;
}

/**
 * build zen tx with seedHex.
 * @param {String} seedHex
 * @param {String} data {inputs:[{
            txid: '196173ec34d22a52cc689a21d01dd33b633671cbe1141e7e66240c7f3b4ccf7b',
            vout: 0,
            scriptPubKey: '76a914da46f44467949ac9321b16402c32bbeede5e3e5f88ac20ebd78933082d25d56a47d471ee5d57793454cf3d2787f77c21f9964b02000000034f2902b4'
        }], outputs:[{address: 'znkz4JE6Y4m8xWoo4ryTnpxwBT5F7vFDgNf', satoshis: 100000}], blockHeight: '142091', blockHash: '00000001cf4e27ce1dd8028408ed0a48edd445ba388170c9468ba0d42fff3052',...}
 * @returns {Array}
 */
function buildZenTransaction (seedHex, data) {
    data = JSON.parse(data);
    var inputs = data["inputs"];
    var outputs = data["outputs"];

    var keychain = generateMasterKeychain(seedHex);
    var changeKeychain = generateChangeKeychain(seedHex);
    var privateKeys = [];

    console.log("inputs | outputs :" + JSON.stringify(inputs) + " | " + JSON.stringify(outputs));
    var txobj = Transaction.createRawTx(inputs, outputs, data["blockHeight"], data["blockHash"]);

    for (var i = 0; i < inputs.length; i++) {
        var input = inputs[i];
        var isChange = input["isChange"];
        privateKeys[i] = (isChange ? changeKeychain : keychain).derive(input["bip39Index"]).privateKey.toString('hex');
    }

    for (var _i = privateKeys.length - 1; _i >= 0; _i--) {
        txobj = Transaction.signTx(txobj, _i, privateKeys[_i], true); // @param {compressPubKey} compress public key before appending to scriptSig? (default false)
    }

    var serializeTx = Transaction.serializeTx(txobj);
    var txid = Buffer.from(zcrypto.sha256x2(Buffer.from(serializeTx, 'hex')), 'hex').reverse().toString('hex');
    console.log('txid: ' + txid);

    return [txid, serializeTx];
}

/**
 * build zen tx with privateKey.
 * @param {String} privateKey hex
 * @param {String} data
 * @returns {Array}
 */
function buildZenTxWithPrivateKey (privateKey, data) {
    data = JSON.parse(data);
    var inputs = data["inputs"];
    var outputs = data["outputs"];

    var txobj = Transaction.createRawTx(inputs, outputs, data["blockHeight"], data["blockHash"]);

    for (var _i = inputs.length - 1; _i >= 0; _i--) {
        txobj = Transaction.signTx(txobj, _i, privateKey, false); // @param {compressPubKey} compress public key before appending to scriptSig? (default false)
    }

    var serializeTx = Transaction.serializeTx(txobj);
    var txid = Buffer.from(zcrypto.sha256x2(Buffer.from(serializeTx, 'hex')), 'hex').reverse().toString('hex');
    console.log('txid: ' + txid);

    return [txid, serializeTx];
}

/**
 * get version and hash from address.
 * @param {String} address
 * @returns {Object}
 */
function fromBase58Check (address) {
    var payload = bs58check.decode(address)

    if (payload.length < 21) throw new TypeError(address + ' is too short')
    if (payload.length > 22) throw new TypeError(address + ' is too long')

    var multibyte = payload.length === 22
    var offset = multibyte ? 2 : 1

    var version = multibyte ? payload.readUInt16BE(0) : payload.readUInt8(0)
    var hash = payload.slice(offset)

    return { version: version, hash: hash }
}

/**
 * verify address.
 * @param {String} address
 * @param {Object=} network
 * @returns {Boolean}
 */
function isValidAddr (address, network) {
    network = network || Config.mainnet

    var decode
    try {
        decode = fromBase58Check(address)
        // console.log('decode: ' + JSON.stringify(decode))
        return decode && (decode.version === Buffer.from(network.pubKeyHash, 'hex').readUInt16BE(0) || decode.version === Buffer.from(network.scriptHash, 'hex').readUInt16BE(0))
    } catch (e) {
        return false
    }
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
    getZenAddrFromSeedHex: getZenAddrFromSeedHex,
    getPrivkeyFromSeedHex: getPrivkeyFromSeedHex,
    getPubkeyFromPrivkey: getPubkeyFromPrivkey,
    getZenAddrFromPubKey: getZenAddrFromPubKey,
    getPubkeyAndAddrFromPrivkey: getPubkeyAndAddrFromPrivkey,
    getZenAddrFromXpubkey: getZenAddrFromXpubkey,
    getZenContinuousAddrFromXpubkey: getZenContinuousAddrFromXpubkey,
    buildZenTransaction: buildZenTransaction,
    buildZenTxWithPrivateKey: buildZenTxWithPrivateKey,
};
