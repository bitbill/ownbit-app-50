//  tools/js-bundles/xlm_ext.js — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//  Fragment inserted into the shipped bundle by patch_xlm.js (verbatim). The patch script strips these leading
//  "//" lines first, so the inserted bytes are exactly the shipped ones.

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

