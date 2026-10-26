//  tools/js-bundles/test_xlm.js — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//  Test vectors: SEP-0005 test mnemonic 1 (public) and the APP_CONTRACT 5.10 XLM vectors.

const assert=require('assert');
const L=require('./jsc.js');const O=L('./stellar.orig.min.js',true);const N=L('./stellar.new.min.js',true);const D=L('./stellar.debug.js',true);const SB=D.__SB;
let pass=0;const ok=(c,m)=>{assert(c,m);pass++;console.log('ok',m)};
for(const k of Object.keys(O)) ok(typeof N[k]==='function','export kept '+k);
const seed=N.mnemonicToSeedHex('illness spike retreat truth genius clock brain pass fit cave bargain toe','');
ok(seed===O.mnemonicToSeedHex('illness spike retreat truth genius clock brain pass fit cave bargain toe',''),'seed same');
ok(JSON.stringify(N.getPubAddrFromSeedHex(seed,true))===JSON.stringify(O.getPubAddrFromSeedHex(seed,true)),'getPubAddrFromSeedHex same');
const g=k=>N.getPubAddrFromSeedHexIndex(seed,k)[1];
ok(g(0)==='GDRXE2BQUC3AZNPVFSCEZ76NJ3WWL25FYFK6RGZGIEKWE4SOOHSUJUJ6','derive 0');
ok(g(1)==='GBAW5XGWORWVFE2XTJYDTLDHXTY2Q2MO73HYCGB3XMFMQ562Q2W2GJQX','derive 1');
ok(g(2)==='GAY5PRAHJ2HIYBYCLZXTHID6SPVELOOYH2LBPH3LD4RUMXUW3DOYTLXW','derive 2');
ok(g(0)===N.getPubAddrFromSeedHex(seed,true)[1],'k=0 equals SEP5 single-sig key');
// vector 3 setup
const info={address:g(1),sequence:'236293450399596544',serverTime:1791338400,perOpFee:1000,requireNum:2,signers:[g(0),g(2),g(3)],trustAssets:[{code:'USDC',issuer:'GA5ZSEJYB37JRC5AVCIA5MOP4RHTM335X2KGX3IHOJAPP5RE34K4KZVN'}],maxTime:1791339000};
ok(g(3)==='GAOD5NRAEORFE34G5D4EOSKIJB6V4Z2FGPBCJNQI6MNICVITE6CSYIAE','derive 3');
const st=N.buildMsSetupTxWithSeedHexIndex(seed,1,JSON.stringify(info));
ok(st[0]==='d7489cda29b45c6d15aeefeb1a1c2b43a854bad95b079dfe34c7a7d7bbe34539','V3 hash');
ok(st[1]==='AAAAAEFu3NZ0bVKTV5pwOaxnvPGoaY7+z4EYO7sKyHfahq2jAAATiANHe6Ql0cABAAAAAQAAAAAAAAAAAAAAAGrFqfgAAAAAAAAABQAAAAAAAAAGAAAAAVVTREMAAAAAO5kROA7+mIugqJAOsc/kTzZvfb6Ua+0HckD39iTfFcV//////////wAAAAAAAAAFAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABAAAAAONyaDCgtgy19SyETP/NTu1l66XBVeibJkEVYnJOceVEAAAAAQAAAAAAAAAFAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABAAAAADHXxAdOjowHAl5vM6B+k+pFudg+lhefax8jRl6W2N2JAAAAAQAAAAAAAAAFAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABAAAAABw+tiAjolJvhuj4R0lISH1eZ0UzwiS2CPMagVUTJ4UsAAAAAQAAAAAAAAAFAAAAAAAAAAAAAAAAAAAAAQAAAAAAAAABAAAAAgAAAAEAAAACAAAAAQAAAAIAAAAAAAAAAAAAAAAAAAAB2oatowAAAEADQT9Y3mOWskVwXB/SJTTRgBUumOaKIhM/URZtroesUOf1L/rTpJ7aOENze0pdyKaM6B6AE00bu0MdVKXehTsF','V3 envelope byte-identical');
let t=false;try{N.buildMsSetupTxWithSeedHexIndex(seed,2,JSON.stringify(info))}catch(e){t=/mismatch/.test(e.message)}ok(t,'setup rejects wrong k');
t=false;try{N.buildMsSetupTxWithSeedHexIndex(seed,1,JSON.stringify(Object.assign({},info,{maxTime:1791338400+4000})))}catch(e){t=true}ok(t,'setup rejects maxTime window');
// vector 1/2 decode
const v1='AAAAACkNZ+7HpcsDD4FHvKUxht122jDgSwP1wWXxdsde/PF/AAAAZAPc5kEAAAABAAAAAQAAAAAAAAAAAAAAAGrFgKcAAAAAAAAAAQAAAAAAAAAGAAAAAVVTREMAAAAAO5kROA7+mIugqJAOsc/kTzZvfb6Ua+0HckD39iTfFcV//////////wAAAAA=';
const d1=JSON.parse(N.decodeMsTxXdr(v1));
ok(d1.hashHex==='9f681dc85da957b098d1ebf46aa98ec1fc439d94860c71150202a15a97ba8e01'&&d1.fee==='100'&&d1.seqNum==='278350443837390849'&&d1.minTime===0&&d1.maxTime===1791328423&&d1.memoType==='none'&&d1.opType==='change_trust'&&d1.assetCode==='USDC'&&d1.assetIssuer==='GA5ZSEJYB37JRC5AVCIA5MOP4RHTM335X2KGX3IHOJAPP5RE34K4KZVN'&&d1.limit==='9223372036854775807'&&d1.source==='GAUQ2Z7OY6S4WAYPQFD3ZJJRQ3OXNWRQ4BFQH5OBMXYXNR267TYX6IO5','V1 decode');
ok(SB.Keypair.fromPublicKey(d1.source).verify(Buffer.from(d1.hashHex,'hex'),Buffer.from('8cF2tVsX7pvaouRhgbrPVlcD0Xccr8RQBYXknQYAEFMfIHEXn2UQ0M4r1sBxa2mEfL2DNwBaQGgvwdHIZr8fCQ==','base64')),'V1 sig verifies');
const v2='AAAAAB0UIon+KeQHmVBPZDlB0Y9d12+NTK+mskrug9xwBmEZAA9CQALNWAQABLv/AAAAAQAAAAAxmxw9AAAAAGrFqi8AAAABAAAACTk5ODI4MTQxNwAAAAAAAAEAAAAAAAAAAQAAAAD6kQqM/i5Jumr0iYptV4X66Z7VK3kiqNDtdKVLFg5pCwAAAAFVU0RDAAAAADuZETgO/piLoKiQDrHP5E82b32+lGvtB3JA9/Yk3xXFAAAAAAMX7mAAAAAA';
const d2=JSON.parse(N.decodeMsTxXdr(v2));
ok(d2.hashHex==='0611bf3261435bb3939d6e57d8b21aa8ddb08bcdfcdadb2da024ff20fdd923ff'&&d2.fee==='1000000'&&d2.seqNum==='201914332504964095'&&d2.minTime===832248893&&d2.maxTime===1791339055&&d2.memoType==='text'&&d2.memo==='998281417'&&d2.opType==='payment'&&d2.destination==='GD5JCCUM7YXETOTK6SEYU3KXQX5OTHWVFN4SFKGQ5V2KKSYWBZUQWMWT'&&d2.amount==='51900000','V2 decode');
ok(SB.Keypair.fromPublicKey(d2.source).verify(Buffer.from(d2.hashHex,'hex'),Buffer.from('+56h/5CbnmeKarAbKMsHcB2XyQsJfUAiCheQQl0KvT+7q5ZTEbtZ3JzPLBd2lp2YwMdrIa/j74r50I16KIzMCg==','base64')),'V2 sig verifies');
// tamper 1 byte -> hash changes
const b=Buffer.from(v2,'base64');b[b.length-10]^=1;const d2t=JSON.parse(N.decodeMsTxXdr(b.toString('base64')));
ok(d2t.hashHex!==d2.hashHex,'tamper changes hash');
t=false;try{N.decodeMsTxXdr(v1+'AAAA')}catch(e){t=true}
t=false;try{N.decodeMsTxXdr(Buffer.concat([Buffer.from(v1,'base64'),Buffer.alloc(4)]).toString('base64'))}catch(e){t=e.message==='trailing_bytes'}ok(t,'trailing bytes rejected');
t=false;try{N.decodeMsTxXdr(st[1])}catch(e){t=true}ok(t,'envelope rejected by decode');
// build/decode/sign roundtrip
const xdr=N.buildMsTxXdr(JSON.stringify({source:g(1),sequence:'236293450399596547',fee:'1000',maxTime:1791597600,memoType:'text',memo:'invoice 42',opType:'payment',destination:'GD5JCCUM7YXETOTK6SEYU3KXQX5OTHWVFN4SFKGQ5V2KKSYWBZUQWMWT',amount:'2.5'}));
const dx=JSON.parse(N.decodeMsTxXdr(xdr[1]));
ok(dx.hashHex===xdr[0]&&dx.seqNum==='236293450399596548'&&dx.amount==='25000000'&&dx.memo==='invoice 42'&&dx.fee==='1000'&&dx.assetCode==='','buildMsTxXdr roundtrip');
const sg=N.signMsTxXdrWithSeedHex(seed,xdr[1]);
ok(sg[0]===xdr[0]&&sg[1].length===88&&SB.Keypair.fromPublicKey(g(0)).verify(Buffer.from(sg[0],'hex'),Buffer.from(sg[1],'base64')),'signMsTxXdr verifies with signer key');
const xct=N.buildMsTxXdr(JSON.stringify({source:g(1),sequence:'5',fee:'1000',maxTime:1791597600,memoType:'none',opType:'change_trust',assetCode:'yUSDC',assetIssuer:'GDGTVWSM4MGS4T7Z6W4RPWOCHE2I6RDFCIFZGS3DOA63LWQTRNZNTTFF'}));
const dct=JSON.parse(N.decodeMsTxXdr(xct[1]));ok(dct.opType==='change_trust'&&dct.assetCode==='yUSDC'&&dct.limit==='9223372036854775807','change_trust alphanum12 keeps case');
const xca=N.buildMsTxXdr(JSON.stringify({source:g(1),sequence:'5',fee:'1000',maxTime:1791597600,memoType:'id',memo:'18446744073709551615',opType:'create_account',destination:g(2),amount:'1'}));
const dca=JSON.parse(N.decodeMsTxXdr(xca[1]));ok(dca.opType==='create_account'&&dca.amount==='10000000'&&dca.memoType==='id'&&dca.memo==='18446744073709551615','create_account + memo id');
// single-sig token payment & change trust
const addr=N.getPubAddrFromSeedHex(seed,true)[1];
const tp=N.buildTokenPaymentTxWithSeedHex(seed,JSON.stringify({accountId:addr,sequence:'100',destination:g(2),amount:'100.0000000',assetCode:'USDC',assetIssuer:'GA5ZSEJYB37JRC5AVCIA5MOP4RHTM335X2KGX3IHOJAPP5RE34K4KZVN'}),'hi',addr);
ok(tp.length===2&&/^[0-9a-f]{64}$/.test(tp[0]),'token payment built');
const tp2=N.buildTokenPaymentTxWithSeedHex(seed,JSON.stringify({accountId:addr,sequence:'100',destination:g(2),amount:'1',assetCode:'USDC',assetIssuer:'GA5ZSEJYB37JRC5AVCIA5MOP4RHTM335X2KGX3IHOJAPP5RE34K4KZVN',maxTime:1791339000}),'',addr);
const env=SB.xdr.TransactionEnvelope.fromXDR(tp2[1],'base64');ok(env.tx().timeBounds().maxTime().toString()==='1791339000','maxTime honored');
const priv=N.getPrivkeyFromSeedHex(seed,true);
const ct=N.buildChangeTrustTxWithSeedHex(seed,JSON.stringify({accountId:addr,sequence:'100',assetCode:'USDC',assetIssuer:'GA5ZSEJYB37JRC5AVCIA5MOP4RHTM335X2KGX3IHOJAPP5RE34K4KZVN',limit:'0',maxTime:1791339000}),addr);
const ct2=N.buildChangeTrustTxWithPrivKey(priv,JSON.stringify({accountId:addr,sequence:'100',assetCode:'USDC',assetIssuer:'GA5ZSEJYB37JRC5AVCIA5MOP4RHTM335X2KGX3IHOJAPP5RE34K4KZVN',limit:'0',maxTime:1791339000}));
ok(ct[0]===ct2[0],'change trust seed == privkey');
const cte=SB.xdr.TransactionEnvelope.fromXDR(ct[1],'base64');ok(cte.tx().memo().switch().name==='memoNone','change trust no memo');
console.log('PASS',pass);
