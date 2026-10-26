//  zcashjs-lib-bridge/index.js — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Readable source of the Ownbit entry module (browserify module 133) inside zcashjs-lib-app-0251.js:
//  identical to it apart from comments, whitespace and the browserify wrapper. NOT loaded at runtime:
//  the Swift bridge loads zcashjs-lib-app-0251.js itself. Kept for review only.

var zec = require('bitgo-utxo-lib');
var wif = require('wif');

var ZCASH_MAINNET_PATH = "m/44'/133'/0'/0";
var ZCASH_MAINNET_CHANGE_PATH = "m/44'/133'/0'/1";
var ZCASH_MAINNET_ROOT_PATH = "m/44'/133'/0'";

/**
 * Checks if the given string is an address
 *
 * @method isAddress
 * @param {String} address the given HEX adress
 * @return {Boolean}
 */
function isAddress(address) {
    try {
        zec.address.toOutputScript(address, zec.networks.zcash);
        return true;
    } catch (e) {
        return false;
    }
}

/**
 * get master keychain with seedHex
 * @param {String} seedHex
 * @return {Object} master keychain
 */
function generateMasterKeychain(seedHex) {
    return zec.HDNode.fromSeedHex(seedHex, zec.networks.zcash).derivePath(ZCASH_MAINNET_PATH);
}

/**
 * get change keychain with seedHex
 * @param {String} seedHex
 * @return {Object} change keychain
 */
function generateChangeKeychain(seedHex) {
    return zec.HDNode.fromSeedHex(seedHex, zec.networks.zcash).derivePath(ZCASH_MAINNET_CHANGE_PATH);
}

function generateRootKeychain(seedHex) {
    return zec.HDNode.fromSeedHex(seedHex, zec.networks.zcash).derivePath(ZCASH_MAINNET_ROOT_PATH);
}

/**
 * get masterXpubkey
 * @param {String} seedHex
 * @return {String} masterXpubkey
 */
function getMasterXpubkey(seedHex) {
    var keychain = generateMasterKeychain(seedHex);
    return keychain.neutered().toBase58();
}

/**
 * get changeXpubkey
 * @param {String} seedHex
 * @return {String} changeXpubkey
 */
function getChangeXpubkey(seedHex) {
    var keychain = generateChangeKeychain(seedHex);
    return keychain.neutered().toBase58();
}

function getRootXpubkey(seedHex) {
    var keychain = generateRootKeychain(seedHex);
    return keychain.neutered().toBase58();
}

/**
 * get xpubkeys
 * @param {String} seedHex
 * @return {Array} xpubkeys, [masterXpubkey, changeXpubkey]
 */
function getXpubkeys(seedHex) {
    return [getMasterXpubkey(seedHex), getChangeXpubkey(seedHex), getRootXpubkey(seedHex)];
}

/**
 * @param {String} seedHex
 * @param {Number} index
 * @returns {String} An address generated from seedHex, index
 */
function getZecAddrFromSeedHex(seedHex, index) {
    var keychain = generateMasterKeychain(seedHex);
    return keychain.derive(index).getAddress();
}

/**
 * @param {String} privkey
 * @returns {String} publicKey
 */
function getPubkeyFromPrivkey(privkey) {
    var keyPair = ecpairFromPrivateKey(privkey);
    var pubKeyBuffer = keyPair.getPublicKeyBuffer();
    return pubKeyBuffer.toString('hex');
}

/**
 * Instantiate an address from a pubkey
 *
 * @param {String} pubkey
 * @returns {String} address
 */
function getZecAddrFromPubKey(pubkey) {
    var pubKeyBuffer = new Buffer(pubkey, 'hex');
    var keyPair = zec.ECPair.fromPublicKeyBuffer(pubKeyBuffer, zec.networks.zcash);
    return keyPair.getAddress();
}

/**
 * @param {String} privkey
 * @returns {Array} [publicKey, address]
 */
function getPubkeyAndAddrFromPrivkey(privkey) {
    var pubkey = getPubkeyFromPrivkey(privkey);
    var addr = getZecAddrFromPubKey(pubkey);
    return [pubkey, addr];
}

/**
 * Instantiate an address from xpub, index
 *
 * @param {String} xpub
 * @param {Number} index
 * @returns {String} address
 */
function getZecAddrFromXpubkey(xpub, index) {
    var node = zec.HDNode.fromBase58(xpub, zec.networks.zcash);
    return node.derive(index).getAddress();
}


/**
 * Instantiate an addresses from xpub, fromIndex, toIndex
 *
 * @param {String} xpub
 * @param {Number} fromIndex
 * @param {Number} toIndex
 * @returns {Array} addresses
 */
function getZecContinuousAddrFromXpubkey(xpub, fromIndex, toIndex) {
    var node = zec.HDNode.fromBase58(xpub, zec.networks.zcash);
    var addresses = new Array();
    for (var i = fromIndex, j = 0; i <= toIndex; i++, j++) {
        addresses[j] = node.derive(i).getAddress();
    }
    return addresses;
}

/**
 * build zec tx with seedHex.
 * @param {String} seedHex
 * @param {String} data
 * @returns {Array}
 */
function buildZecTransaction (seedHex, data) {
    data = JSON.parse(data);
    if (isZecV5(data)) {
        var v5Master = generateMasterKeychain(seedHex);
        var v5Change = generateChangeKeychain(seedHex);
        return buildZecV5Transaction(data, data["inputs"].map(function (input) {
            return (input["isChange"] ? v5Change : v5Master).derive(input["bip39Index"]).keyPair;
        }));
    }
    var inputs = data["inputs"];
    var outputs = data["outputs"];

    var keychain = generateMasterKeychain(seedHex);
    var changeKeychain = generateChangeKeychain(seedHex);
    var txb = new zec.TransactionBuilder(zecNetworkFor(data));
    txb.setVersion(4);
    txb.setVersionGroupId(0x892F2085);
    // txb.setExpiryHeight(499999999);
    var ecPairs = [];
    var vals = [];

    for (var i = 0; i < inputs.length; i++) {
        var input = inputs[i];
        txb.addInput(input["txid"], input["vout"]);
        var isChange = input["isChange"];
        vals[i] = input["satoshis"];
        ecPairs[i] = (isChange ? changeKeychain : keychain).derive(input["bip39Index"]);
    }

    for (var _i = 0; _i < outputs.length; _i++) {
        var output = outputs[_i];
        txb.addOutput(output["address"], output["amount"]);
    }

    for (var _i2 = ecPairs.length - 1; _i2 >= 0; _i2--) {
        txb.sign(_i2, ecPairs[_i2], null, null, vals[_i2]);
    }

    return [txb.build().getId(), txb.build().toHex()];
}

/**
 * build zec tx with privateKey.
 * @param {String} privateKey hex
 * @param {String} data
 * @returns {Array}
 */
function buildZecTxWithPrivateKey (privateKey, data) {
    data = JSON.parse(data);
    if (isZecV5(data)) {
        var v5Pair = ecpairFromPrivateKey(privateKey);
        return buildZecV5Transaction(data, data["inputs"].map(function () {
            return v5Pair;
        }));
    }
    var inputs = data["inputs"];
    var outputs = data["outputs"];

    var txb = new zec.TransactionBuilder(zecNetworkFor(data));
    txb.setVersion(4);
    txb.setVersionGroupId(0x892F2085);
    // txb.setExpiryHeight(499999999);
    var vals = [];

    var ecPair = ecpairFromPrivateKey(privateKey);

    for (var i = 0; i < inputs.length; i++) {
        var input = inputs[i];
        txb.addInput(input["txid"], input["vout"]);
        vals[i] = input["satoshis"];
    }

    for (var _i = 0; _i < outputs.length; _i++) {
        var output = outputs[_i];
        txb.addOutput(output["address"], output["amount"]);
    }

    for (var _i2 = inputs.length - 1; _i2 >= 0; _i2--) {
        txb.sign(_i2, ecPair, null, null,  vals[_i2]);
    }

    return [txb.build().getId(), txb.build().toHex()];
}

/**
 * get ecpair from privkey
 * @param {String} privateKey
 * @return {Object} ECPair
 */
function ecpairFromPrivateKey(privateKey) {
    var _wif = '';
    var _startWith = privateKey.charAt(0);

    if(privateKey.match(/^[0-9a-f]+$/i)) {
        var prvKey = new Buffer(privateKey, 'hex');
        _wif = wif.encode(zec.networks.zcash.wif, prvKey, false);
    } else if(_startWith === '5' || _startWith === 'K' || _startWith === 'L') {
        _wif = privateKey;
    }

    return zec.ECPair.fromWIF(_wif, zec.networks.zcash);
}

/**
 * get pubkey from seedHex
 * @param {String} seedHex
 * @param {Number} index
 * @return {String} pubkey
 */
//function getPublicKeyFromSeedHex(seedHex, index) {
//    var keyPair = generateMasterKeychain(seedHex).derive(index);
//    return keyPair.getPublicKeyBuffer().toString('hex');
//}

/**
 * get WIF from seedHex
 * @param {String} seedHex
 * @param {Number} index
 * @return {String} WIF
 */
function getWIFFromSeedHex(seedHex, index, change) {
    var hdnode = null;
    if (change) {
        hdnode = generateChangeKeychain(seedHex).derive(index);
    } else {
        hdnode = generateMasterKeychain(seedHex).derive(index);
    }
    return hdnode.keyPair.toWIF().toString('hex');
}

function getSignatureWithPrivateKey(privateKey, data, m, redeemScript) {
    data = JSON.parse(data);
    if (isZecV5(data)) {
        return getZecV5MultiSigSignatures(privateKey, data, redeemScript);
    }
    var inputs = data["inputs"];
    var outputs = data["outputs"];
    var signatures = [];
    
    var ecPair = ecpairFromPrivateKey(privateKey);
            
    var txb = new zec.TransactionBuilder(zecNetworkFor(data));
    txb.setVersion(4);
    txb.setVersionGroupId(0x892F2085);

    const hashType = zec.Transaction.SIGHASH_ALL;
   
            for (var i = 0; i < inputs.length; i++) {
                var input = inputs[i];
                txb.addInput(input["txid"], input["vout"]);
            }
            
            for (var _i = 0; _i < outputs.length; _i++) {
            var output = outputs[_i];
            txb.addOutput(output["address"], output["amount"]);
            }
            
            for (var _i2 = inputs.length - 1; _i2 >= 0; _i2--) {
                txb.sign(_i2, ecPair, Buffer.from(redeemScript, 'hex'), hashType, inputs[_i2]["satoshis"])
                
		signatures[_i2] =txb.inputs[_i2].signatures[m].toString('hex')
            }
            
            
    return signatures;
}



// ---------------------------------------------------------------------------------------------
// v5 交易（2026-09-26，为 NU7 准备）：NU7（主网目标 2026-11-05）起不再接受 v4 交易；v5 从 NU5 起一直有效。
// 只处理纯透明交易（没有 Sapling / Orchard 部分）：序列化按 ZIP 225，签名哈希 / txid 按 ZIP 244，
// 逐项对照 zcash-test-vectors 的参考实现 zip_0244.py。
// data.zecTxVersion === 5 时走这里；分支 ID / 过期高度 / 锁定时间也在 data 里（App 按 ZEC 当前高度写入），其余照旧 v4。
// ---------------------------------------------------------------------------------------------
var ZEC_V5_HEADER = (5 | 0x80000000) >>> 0; // fOverwintered | nVersion
var ZEC_V5_VERSION_GROUP_ID = 0x26A7270A;

function zecBlake2b(buf, personalization) {
    return zec.Transaction.prototype.getBlake2bHash(buf, personalization);
}

function zecU32(n) {
    var b = Buffer.alloc(4);
    b.writeUInt32LE(n >>> 0, 0);
    return b;
}

function zecU64(n) {
    if (typeof n !== 'number' || !isFinite(n) || n < 0 || Math.floor(n) !== n || n > Number.MAX_SAFE_INTEGER) {
        throw new Error('zec v5: bad amount ' + n);
    }
    var b = Buffer.alloc(8);
    b.writeUInt32LE(n % 0x100000000, 0);
    b.writeUInt32LE(Math.floor(n / 0x100000000), 4);
    return b;
}

function zecCompactSize(n) {
    if (n < 0xfd) {
        return Buffer.from([n]);
    }
    if (n <= 0xffff) {
        var b = Buffer.alloc(3);
        b[0] = 0xfd;
        b.writeUInt16LE(n, 1);
        return b;
    }
    var c = Buffer.alloc(5);
    c[0] = 0xfe;
    c.writeUInt32LE(n >>> 0, 1);
    return c;
}

function zecVarSlice(buf) {
    return Buffer.concat([zecCompactSize(buf.length), buf]);
}

function isZecV5(data) {
    return Number(data["zecTxVersion"]) === 5;
}

// v4 共识分支 ID 的单次覆盖（契约 0.12 / 1.8）：data.consensusBranchIdOverride（uint32 数字）只在 v4 时生效，
// 用一份复制的 network 代替 consensusBranchId[4]，不改全局表；v5 忽略（v5 的分支在 data.zecBranchId 里）。
function zecNetworkFor(data) {
    var base = zec.networks.zcash;
    var o = Number(data && data["consensusBranchIdOverride"]);
    if (!isFinite(o) || o <= 0 || o > 0xFFFFFFFF || Math.floor(o) !== o) {
        return base;
    }
    var net = Object.assign({}, base);
    net.consensusBranchId = Object.assign({}, base.consensusBranchId);
    net.consensusBranchId[4] = o >>> 0;
    return net;
}

function zecV5FromData(data) {
    var branchId = Number(data["zecBranchId"]);
    if (!(branchId > 0)) {
        throw new Error('zec v5: missing zecBranchId');
    }
    return {
        branchId: branchId >>> 0,
        lockTime: (Number(data["zecLockTime"]) || 0) >>> 0,
        expiryHeight: (Number(data["zecExpiryHeight"]) || 0) >>> 0,
        ins: data["inputs"].map(function (input) {
            if (!/^[0-9a-fA-F]{64}$/.test(input["txid"])) {
                throw new Error('zec v5: bad txid');
            }
            return {
                hash: Buffer.from(input["txid"], 'hex').reverse(),
                index: input["vout"] >>> 0,
                sequence: 0xffffffff,
                value: Number(input["satoshis"]),
                scriptPubKey: input["scriptPubKey"] || ''
            };
        }),
        outs: data["outputs"].map(function (output) {
            return {
                value: Number(output["amount"]),
                script: zec.address.toOutputScript(output["address"], zec.networks.zcash)
            };
        })
    };
}

function zecV5HeaderDigest(tx) {
    return zecBlake2b(Buffer.concat([zecU32(ZEC_V5_HEADER), zecU32(ZEC_V5_VERSION_GROUP_ID), zecU32(tx.branchId),
                                     zecU32(tx.lockTime), zecU32(tx.expiryHeight)]), 'ZTxIdHeadersHash');
}

function zecV5PrevoutsDigest(tx) {
    return zecBlake2b(Buffer.concat(tx.ins.map(function (input) {
        return Buffer.concat([input.hash, zecU32(input.index)]);
    })), 'ZTxIdPrevoutHash');
}

function zecV5SequenceDigest(tx) {
    return zecBlake2b(Buffer.concat(tx.ins.map(function (input) {
        return zecU32(input.sequence);
    })), 'ZTxIdSequencHash');
}

function zecV5OutputsDigest(tx) {
    return zecBlake2b(Buffer.concat(tx.outs.map(function (output) {
        return Buffer.concat([zecU64(output.value), zecVarSlice(output.script)]);
    })), 'ZTxIdOutputsHash');
}

// 头部 + 透明部分 + 空的 Sapling / Orchard 部分，个性化串 "ZcashTxHash_" + 分支 ID
function zecV5Digest(tx, transparentDigest) {
    var personalization = Buffer.concat([Buffer.from('ZcashTxHash_'), zecU32(tx.branchId)]);
    return zecBlake2b(Buffer.concat([zecV5HeaderDigest(tx), transparentDigest,
                                     zecBlake2b(Buffer.alloc(0), 'ZTxIdSaplingHash'),
                                     zecBlake2b(Buffer.alloc(0), 'ZTxIdOrchardHash')]), personalization);
}

// txid：和区块浏览器 / RPC 一样按字节反序显示
function zecV5Txid(tx) {
    var transparent = (tx.ins.length + tx.outs.length) > 0
        ? zecBlake2b(Buffer.concat([zecV5PrevoutsDigest(tx), zecV5SequenceDigest(tx), zecV5OutputsDigest(tx)]), 'ZTxIdTranspaHash')
        : zecBlake2b(Buffer.alloc(0), 'ZTxIdTranspaHash');
    return Buffer.from(zecV5Digest(tx, transparent)).reverse().toString('hex');
}

// 第 inIndex 个透明输入的签名哈希（SIGHASH_ALL）。spentScripts[i] 是第 i 个输入花掉的那个输出的 scriptPubKey：
// 所有输入的金额和 scriptPubKey 都要承诺进去；P2SH 输入用 P2SH 脚本本身，不是赎回脚本（和 v4 不一样）
function zecV5SigHash(tx, inIndex, spentScripts) {
    var input = tx.ins[inIndex];
    var amounts = zecBlake2b(Buffer.concat(tx.ins.map(function (i) {
        return zecU64(i.value);
    })), 'ZTxTrAmountsHash');
    var scripts = zecBlake2b(Buffer.concat(spentScripts.map(zecVarSlice)), 'ZTxTrScriptsHash');
    var txin = zecBlake2b(Buffer.concat([input.hash, zecU32(input.index), zecU64(input.value),
                                         zecVarSlice(spentScripts[inIndex]), zecU32(input.sequence)]), 'Zcash___TxInHash');
    var transparent = zecBlake2b(Buffer.concat([Buffer.from([zec.Transaction.SIGHASH_ALL]), zecV5PrevoutsDigest(tx), amounts,
                                                scripts, zecV5SequenceDigest(tx), zecV5OutputsDigest(tx), txin]), 'ZTxIdTranspaHash');
    return zecV5Digest(tx, transparent);
}

function zecV5Serialize(tx, scriptSigs) {
    var parts = [zecU32(ZEC_V5_HEADER), zecU32(ZEC_V5_VERSION_GROUP_ID), zecU32(tx.branchId), zecU32(tx.lockTime),
                 zecU32(tx.expiryHeight), zecCompactSize(tx.ins.length)];
    tx.ins.forEach(function (input, i) {
        parts.push(input.hash, zecU32(input.index), zecVarSlice(scriptSigs[i]), zecU32(input.sequence));
    });
    parts.push(zecCompactSize(tx.outs.length));
    tx.outs.forEach(function (output) {
        parts.push(zecU64(output.value), zecVarSlice(output.script));
    });
    parts.push(Buffer.from([0x00, 0x00, 0x00])); // nSpendsSapling, nOutputsSapling, nActionsOrchard
    return Buffer.concat(parts);
}

// 服务端给了 scriptPubKey 的，必须和按密钥 / 赎回脚本算出来的一样，不一样就不签
function zecV5CheckSpentScript(input, expected) {
    if (input.scriptPubKey && input.scriptPubKey.toLowerCase() !== expected.toString('hex')) {
        throw new Error('zec v5: scriptPubKey mismatch');
    }
}

// 普通转账：keyPairs[i] 是第 i 个输入的 ECPair，输入都是 P2PKH
function buildZecV5Transaction(data, keyPairs) {
    var tx = zecV5FromData(data);
    var spent = keyPairs.map(function (keyPair, i) {
        var script = zec.address.toOutputScript(keyPair.getAddress(), zec.networks.zcash);
        zecV5CheckSpentScript(tx.ins[i], script);
        return script;
    });
    var scriptSigs = tx.ins.map(function (input, i) {
        var sig = keyPairs[i].sign(zecV5SigHash(tx, i, spent)).toScriptSignature(zec.Transaction.SIGHASH_ALL);
        return zec.script.compile([sig, keyPairs[i].getPublicKeyBuffer()]);
    });
    return [zecV5Txid(tx), zecV5Serialize(tx, scriptSigs).toString('hex')];
}

// 多签：本人对每个输入的签名（DER + SIGHASH_ALL，和 v4 同样的格式），服务端按 signOrder 拼 scriptSig（OP_0 <签名…> <赎回脚本>）
function getZecV5MultiSigSignatures(privateKey, data, redeemScript) {
    var tx = zecV5FromData(data);
    var ecPair = ecpairFromPrivateKey(privateKey);
    var p2sh = zec.script.scriptHash.output.encode(zec.crypto.hash160(Buffer.from(redeemScript, 'hex')));
    var spent = tx.ins.map(function (input) {
        zecV5CheckSpentScript(input, p2sh);
        return p2sh;
    });
    return tx.ins.map(function (input, i) {
        return ecPair.sign(zecV5SigHash(tx, i, spent)).toScriptSignature(zec.Transaction.SIGHASH_ALL).toString('hex');
    });
}

module.exports = {
    isAddress: isAddress,
    getMasterXpubkey: getMasterXpubkey,
    getChangeXpubkey: getChangeXpubkey,
    getXpubkeys: getXpubkeys,
    getWIFFromSeedHex: getWIFFromSeedHex,
    getZecAddrFromSeedHex: getZecAddrFromSeedHex,
    getPubkeyFromPrivkey: getPubkeyFromPrivkey,
    getZecAddrFromPubKey: getZecAddrFromPubKey,
    getPubkeyAndAddrFromPrivkey: getPubkeyAndAddrFromPrivkey,
    getZecAddrFromXpubkey: getZecAddrFromXpubkey,
    getZecContinuousAddrFromXpubkey: getZecContinuousAddrFromXpubkey,
    buildZecTransaction: buildZecTransaction,
    buildZecTxWithPrivateKey: buildZecTxWithPrivateKey,
    getSignatureWithPrivateKey: getSignatureWithPrivateKey,
};
