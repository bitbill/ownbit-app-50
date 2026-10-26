//  digibytejs-lib-bridge/index.js — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Readable source of the Ownbit entry module (browserify module 1) inside digibytejs-lib-app.min.js:
//  identical to it apart from comments, whitespace and the browserify wrapper. NOT loaded at runtime:
//  the Swift bridge loads digibytejs-lib-app.min.js itself. Kept for review only.

//var dgb = require('digibyte');
var dgb = require('litecore-lib-segwit');
//var bip32 = require('bip32');
var bip39 = require('bip39');
var wif = require('wif');
var Address = dgb.Address;
var Networks = dgb.Networks;
var HDPrivateKey = dgb.HDPrivateKey;
var HDPublicKey = dgb.HDPublicKey;
var PrivateKey = dgb.PrivateKey;
var PublicKey = dgb.PublicKey;
var Script = dgb.Script;
var bitcoin = require("bitcoinjs-lib");
var bitcoinMessage = require('bitcoinjs-message');

var DGB_MAINNET_PATH = "m/44'/20'/0'/0";
var DGB_MAINNET_CHANGE_PATH = "m/44'/20'/0'/1";
var DGB_MAINNET_ROOT_PATH = "m/44'/20'/0'";

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

function signMessage(seedHex, uri) {
    var a=uri.indexOf(':');
    var b=uri.indexOf('?');
    if ((a<0)||(b<0)) throw "Invalid uri";
    var url='https'+uri.substr(a,b-a);
    
    //calculate path
    var idIndex = String.fromCharCode(0)+String.fromCharCode(0)+String.fromCharCode(0)+String.fromCharCode(0);
    var hash=bitcoin.crypto.sha256(idIndex + url);
    var path="m/13'";
    for (var i=0;i<16;i+=4) {
        path+="/"+((hash[i+3]&0x7f)<<24|hash[i+2]<<16|hash[i+1]<<8|hash[i])+"'";
    }
    
    console.log("path:"+path)
    
    //var seed = Buffer.from(seedHex, 'hex')
    //var keys = bip32.fromSeed(seed).derivePath(path).keyPair;
    
    //var hd = bitcoin.HDNode.derivePath(path).keyPair;
    var hd = HDPrivateKey.fromSeed(seedHex, Networks.livenet).derive(path);
    //var keys = hd.keyPair;
    
    var addr = hd.publicKey.toAddress().toString();
    var priv = hd.privateKey.toBuffer();
    var sig = bitcoinMessage.sign(uri, priv, true, '\x19DigiByte Signed Message:\n')
    
    //var pre='\x18Bitcoin Signed Message:\n'+magicLength(uri)+uri;
    //var hash=bitcoin.crypto.hash256(pre);
    //var sig=keys.sign(hash).toCompact(1,true);
    //sig = btoa(String.fromCharCode.apply(null, sig));
    
    return [addr, sig.toString('base64'), url];
}

function magicLength(message) {
    var i=message.length;
    if (i < 0xfd) {
        return String.fromCharCode(i);
    } else {
        throw "Message to long";
    }
}

function generateMasterKeychain(seedHex) {
    return HDPrivateKey.fromSeed(seedHex, Networks.livenet).derive(DGB_MAINNET_PATH);
}

function generateChangeKeychain(seedHex) {
    return HDPrivateKey.fromSeed(seedHex, Networks.livenet).derive(DGB_MAINNET_CHANGE_PATH);
}

function generateRootKeychain(seedHex) {
    return HDPrivateKey.fromSeed(seedHex, Networks.livenet).derive(DGB_MAINNET_ROOT_PATH);
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
    return new Address(addr,  Networks.livenet, Address.PayToPublicKeyHash).toBuffer().slice(1).toString('hex');
}

function getScripthashFromAddr(addr) {
    return new Address(addr,  Networks.livenet, Address.PayToScriptHash).toBuffer().slice(1).toString('hex');
}

function getScripthashtwoFromAddr(addr) {
    return new Address(addr,  Networks.livenet, Address.PayToScriptHashTwo).toBuffer().slice(1).toString('hex');
}

function privateKeyFromKey(key) {
    var _wif = '';
    var _startWith = key.charAt(0);

    if(key.match(/^[0-9a-f]+$/i)) {
        var prvKey = new Buffer(key, 'hex');
        _wif = wif.encode(128, prvKey, false);
    } else if(_startWith === '5' || _startWith === 'K' || _startWith === 'L') {
        _wif = key;
    }

    return PrivateKey.fromWIF(_wif);
}


/**
 * @param {String} seedHex
 * @param {Number} index
 * @returns {String} An address generated from seedHex, index
 */
//function getDgbAddrFromSeedHex(seedHex, index) {
//    var keychain = generateMasterKeychain(seedHex);
//    return keychain.derive(index).publicKey.toAddress().toString();
//}

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
function getDgbAddrFromPubKey(pubkey) {
    pubkey = new PublicKey(pubkey);
    return pubkey.toAddress().toString();
    //return Address.fromPublicKey(pubkey, Networks.livenet).toString();
}


/**
 * @param {String} privkey
 * @returns {Array} [publicKey, address]
 */
function getPubkeyAndAddrFromPrivkey(privkey) {
    privkey = privateKeyFromKey(privkey);
    //return [privkey.publicKey.toString(),Address.fromPublicKey(privkey.publicKey, Networks.livenet).toString()];
    return [privkey.publicKey.toString(),privkey.toAddress().toString()];
}

/**
 * Instantiate an address from xpub, index
 *
 * @param {String} xpub
 * @param {Number} index
 * @returns {String} address
 */
function getDgbAddrFromXpubkey(xpub, index) {
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
function getDgbContinuousAddrFromXpubkey(xpub, fromIndex, toIndex) {
    var keychain = new HDPublicKey(xpub);
    var addresses = new Array();
    for (var i = fromIndex, j = 0; i <= toIndex; i++, j++) {
        addresses[j] = keychain.derive(i).publicKey.toAddress().toString();
    }
    return addresses;
}

/**
 * translate address start with 3 to address start with S.
 * @param {String} addrWithTree: address start with 3
 * @returns {String} address start with S
 */
function scriptAddrLegacy2New(addrWithTree) {
    var scriptHash = getScripthashtwoFromAddr(addrWithTree);
    console.log('scriptHash: ' + scriptHash);
    return Address.fromScriptHash(new Buffer(scriptHash, 'hex')).toString();
}

/**
 * build dgb tx with seedHex.
 * @param {String} seedHex
 * @param {String} data
 * @returns {Array}
 */
function buildDgbTransaction (seedHex, data) {
    data = JSON.parse(data);
    var inputs = data["inputs"];
    var outputs = data["outputs"];

    var keychain = generateMasterKeychain(seedHex);
    var changeKeychain = generateChangeKeychain(seedHex);
    var privateKeys = [];
    var tx = new dgb.Transaction();

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
 * build dgb tx with privateKey.
 * @param {String} privateKey hex
 * @param {String} data
 * @returns {Array}
 */
function buildDgbTxWithPrivateKey (privateKey, data) {
    data = JSON.parse(data);
    var inputs = data["inputs"];
    var outputs = data["outputs"];
    var privkey = privateKeyFromKey(privateKey);

    var tx = new dgb.Transaction();

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

/**
 * @param {String} seedHex
 * @param {Number} index
 * @returns {String} publicKey
 */
function getPublicKeyFromSeedHex(seedHex, index) {
    var keychain = generateMasterKeychain(seedHex);
    return keychain.derive(index).publicKey.toString('hex');
}

/**
 * generate multisig address with pubKeys.
 * @param {Number} m
 * @param {String|Array} pubKeys
 * @returns {String} multisig address
 */
function generateMultiSigAddr(m, pubKeys) {
    if(typeof pubKeys === 'string') {
        pubKeys = JSON.parse(pubKeys);
    }

    var address = new dgb.Address(pubKeys, m);
    return address.toString();
}

/**
 * generate multisig address with seedHexs.
 * @param {Number} m
 * @param {String|Array} seedHexs
 * @returns {String} multisig address
 */
function generateMSAddrFromSeedHexs(m, seedHexs) {
    if(typeof seedHexs === 'string') {
        seedHexs = JSON.parse(seedHexs);
    }

    var pubKeys = seedHexs.map(function (seedHex) { return getPublicKeyFromSeedHex(seedHex, 0) });
    return generateMultiSigAddr(m, pubKeys);
}

/**
 * generate multisig signature with seedHex.
 * @param {String} seedHex
 * @param {String} data
 * @param {Number} m
 * @param {String|Array} pubKeys
 * @returns {Array} multisig signature
 */
function getSignatureWithSeedHex(seedHex, data, m, pubKeys) {
    data = JSON.parse(data);
    var inputs = data["inputs"];
    var outputs = data["outputs"];
    var signatures = [];

    if(typeof pubKeys === 'string') {
        pubKeys = JSON.parse(pubKeys);
    }

    var privateKey = generateMasterKeychain(seedHex).derive(0).privateKey.toString('hex');

    var tx = new dgb.Transaction();

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

    // console.log('privateKey: ' + JSON.stringify(privateKey));
    var signatureObjs = tx.getSignatures(privateKey);
    console.log('signatureObjs: ' + JSON.stringify(signatureObjs));

    for (var _i2 = 0; _i2 < signatureObjs.length; _i2++) {
        signatures[_i2] = signatureObjs[_i2].signature.toString('hex');
    }

    console.log('signatures: ' + JSON.stringify(signatures));
    return signatures;
}

/**
 * generate multisig signature with privateKey.
 * @param {String} privateKey
 * @param {String} data
 * @param {Number} m
 * @param {String|Array} pubKeys
 * @returns {Array} multisig signature
 */
function getSignatureWithPrivateKey(privateKey, data, m, pubKeys) {
    data = JSON.parse(data);
    var inputs = data["inputs"];
    var outputs = data["outputs"];
    var signatures = [];

    if(typeof pubKeys === 'string') {
        pubKeys = JSON.parse(pubKeys);
    }

    var tx = new dgb.Transaction();

    console.log('multisig address: ' + new Address(pubKeys, m).toString());
    console.log('script hex: ' + new Script(new Address(pubKeys, m)).toHex());

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

    // console.log('privateKey: ' + JSON.stringify(privateKey));
    var signatureObjs = tx.getSignatures(privateKey);
    console.log('signatureObjs: ' + JSON.stringify(signatureObjs));

    for (var _i2 = 0; _i2 < signatureObjs.length; _i2++) {
        signatures[_i2] = signatureObjs[_i2].signature.toString('hex');
    }

    console.log('signatures: ' + JSON.stringify(signatures));
    return signatures;
}

function buildMultiSigTxWithSeedHexs(seedHexs, data, m, pubKeys) {
    data = JSON.parse(data);
    var inputs = data["inputs"];
    var outputs = data["outputs"];

    if(typeof pubKeys === 'string') {
        pubKeys = JSON.parse(pubKeys);
    }

    var privateKeys = seedHexs.map(function (seedHex) { return generateMasterKeychain(seedHex).derive(0).privateKey.toString('hex') });

    var tx = new dgb.Transaction();

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

    tx = tx.sign(privateKeys);
    // console.log('txid: ' + tx.id);

    return tx.toString();
}

function buildMultiSigTxWithPrivateKeys(privateKeys, data, m, pubKeys) {
    data = JSON.parse(data);
    var inputs = data["inputs"];
    var outputs = data["outputs"];

    if(typeof pubKeys === 'string') {
        pubKeys = JSON.parse(pubKeys);
    }

    var tx = new dgb.Transaction();

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

    tx = tx.sign(privateKeys);
    // console.log('txid: ' + tx.id);

    return tx.toString();
}


module.exports = {
    generateMnemonicRandom: generateMnemonicRandom,
    generateMnemonicRandomCN: generateMnemonicRandomCN,
    mnemonicToSeedHex: mnemonicToSeedHex,
    validateMnemonic: validateMnemonic,
    isAddress: isAddress,
    signMessage: signMessage,
    getMasterXpubkey: getMasterXpubkey,
    getChangeXpubkey: getChangeXpubkey,
    getXpubkeys: getXpubkeys,
    getPubkeyhashFromAddr: getPubkeyhashFromAddr,
    getScripthashFromAddr: getScripthashFromAddr,
    getScripthashtwoFromAddr: getScripthashtwoFromAddr,
    //getDgbAddrFromSeedHex: getDgbAddrFromSeedHex,
    getPrivkeyFromSeedHex: getPrivkeyFromSeedHex,
    getPubkeyFromPrivkey: getPubkeyFromPrivkey,
    getPubkeyFromSeedHex: getPubkeyFromSeedHex,
    getDgbAddrFromPubKey: getDgbAddrFromPubKey,
    getPubkeyAndAddrFromPrivkey: getPubkeyAndAddrFromPrivkey,
    getDgbAddrFromXpubkey: getDgbAddrFromXpubkey,
    getDgbContinuousAddrFromXpubkey: getDgbContinuousAddrFromXpubkey,
    scriptAddrLegacy2New: scriptAddrLegacy2New,
    buildDgbTransaction: buildDgbTransaction,
    buildDgbTxWithPrivateKey: buildDgbTxWithPrivateKey,
    generateMultiSigAddr: generateMultiSigAddr,
    generateMSAddrFromSeedHexs: generateMSAddrFromSeedHexs,
    getSignatureWithSeedHex: getSignatureWithSeedHex,
    getSignatureWithPrivateKey: getSignatureWithPrivateKey,
    buildMultiSigTxWithSeedHexs: buildMultiSigTxWithSeedHexs,
    buildMultiSigTxWithPrivateKeys: buildMultiSigTxWithPrivateKeys
};

