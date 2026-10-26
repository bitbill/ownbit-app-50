//  tools/js-bundles/test_xrp.js — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//  Test vectors: BIP39 "abandon x11 about" seed (public) and the APP_CONTRACT 4.15 XRP vectors.

const assert=require('assert');
const load=f=>{delete require.cache[require.resolve(f)];return require(f)};
const L=require('./jsc.js');const O=L('./ripple.orig.min.js'), N=L('./ripple.new.min.js');
const seed='5eb00bbddcf069084889a8ab9155568165f5c453ccb85e70811aaed6f6da5fc19a5ac40b389cd370d086206dec8aa6c43daea6690f20ad3d8d48b2d2ce9e38e4';
let pass=0;const ok=(c,m)=>{assert(c,m);pass++;console.log('ok',m)};
// old exports unchanged
for(const k of Object.keys(O)) ok(typeof N[k]==='function','export kept '+k);
ok(JSON.stringify(N.getPubAddrFromSeedHex(seed))===JSON.stringify(O.getPubAddrFromSeedHex(seed)),'getPubAddrFromSeedHex same');
const nat=JSON.stringify({account:'rHsMGQEkVNJmpGWs8XUBoTBiAAbwxZN5v3',destination:'rPEPPER7kfTD9w2To4CQk6UCfuHM9c6GDY',destinationTag:1,amount:'1000',fee:'12',sequence:5});
ok(JSON.stringify(N.buildXrpPaymentTxWithSeedHex(seed,nat))===JSON.stringify(O.buildXrpPaymentTxWithSeedHex(seed,nat)),'native payment same');
// derivation
const d0=N.getPubAddrFromSeedHexIndex(seed,0), d1=N.getPubAddrFromSeedHexIndex(seed,1), d2=N.getPubAddrFromSeedHexIndex(seed,2830416);
ok(d0[0]==='031D68BC1A142E6766B2BDFB006CCFE135EF2E0E2E94ABB5CF5C9AB6104776FBAE'&&d0[1]==='rHsMGQEkVNJmpGWs8XUBoTBiAAbwxZN5v3','derive 0');
ok(d1[0]==='038BF420B5271ADA2D7479358FF98A29954CF18DC25155184AEAD05796DA737E89'&&d1[1]==='r3AgF9mMBFtaLhKcg96weMhbbEFLZ3mx17','derive 1');
ok(d2[0]==='0397DDF4C3C796A290BDD7CDE2A7F6C8081B8670222010DFA3D55F0B4018C9B6DE'&&d2[1]==='r3S7AdGba3ZapsPm8ouNWqgsKPmc8HpRwW','derive 2830416');
ok(N.deriveAddressFromPubKey(d2[0])===d2[1],'deriveAddressFromPubKey');
// X1
const x1='{"TransactionType":"Payment","Account":"r3S7AdGba3ZapsPm8ouNWqgsKPmc8HpRwW","Destination":"rPEPPER7kfTD9w2To4CQk6UCfuHM9c6GDY","DestinationTag":12345,"Amount":"25000000","Fee":"300","Sequence":98765004,"Flags":2147483648,"SigningPubKey":""}';
const r1=N.multiSignXrpTxJsonWithSeedHex(seed,x1);
ok(r1[0]==='rHsMGQEkVNJmpGWs8XUBoTBiAAbwxZN5v3'&&r1[1]==='031D68BC1A142E6766B2BDFB006CCFE135EF2E0E2E94ABB5CF5C9AB6104776FBAE','X1 signer');
ok(r1[2]==='304402202EF074F0AA3856E1FE6B005F50529A3D1E2FF17361E4F7DB05288E00AB642B3102204FA35336BD98759520EB894B10A6ADEAC23E5DA09A514C5BE7D1D8BB21895D83','X1 sig');
ok(N.multiSignXrpTxJsonWithSeedHex(seed,x1.replace('"25000000"','"25000001"'))[2]!==r1[2],'X1 tampered differs');
// X2
const x2='{"TransactionType":"Payment","Account":"r3S7AdGba3ZapsPm8ouNWqgsKPmc8HpRwW","Destination":"rPEPPER7kfTD9w2To4CQk6UCfuHM9c6GDY","DestinationTag":12345,"Amount":{"currency":"524C555344000000000000000000000000000000","issuer":"rMxCKbEDwqr76QuheSUMdEGf4B9xJ8m5De","value":"150.25"},"Fee":"300","Sequence":98765004,"Flags":2147483648,"SigningPubKey":""}';
ok(N.multiSignXrpTxJsonWithSeedHex(seed,x2)[2]==='3045022100F7B01C157950A7124659DF6CC9B4842136410BE00CDF64881305C62F802052F4022033D9C9652AAB20E9A4DCC22D6DD79E47A6496ECFB39FD2891493C5EEFE63A7EA','X2 sig');
// X3
const x3='{"TransactionType":"AccountSet","Account":"r3S7AdGba3ZapsPm8ouNWqgsKPmc8HpRwW","SetFlag":4,"Fee":"100","Sequence":98765003,"LastLedgerSequence":99000060}';
const r3=N.signXrpTxJsonWithSeedHexIndex(seed,2830416,x3);
ok(r3[0]==='AD94C162AAF0E364C7E4C70273EA0CE7490D5AABC56D91F33208D6B3D29500BB','X3 txId');
ok(r3[1]==='1200032405E308CB201B05E69EFC20210000000468400000000000006473210397DDF4C3C796A290BDD7CDE2A7F6C8081B8670222010DFA3D55F0B4018C9B6DE74473045022100853AA95F5C9EC93DFA43F84A80B763B6C117D4961F62D469DCCDBF4E35EBF76F02201F6DA598FEAE85896AB4FD43181A2D126DBFC81723DD2F36FE9E3607DAE72C9F8114519A9AABD595A647925306628F10D0234A91E2D2','X3 blob');
// token payment / trustset decode check
const codec=x=>x; 
const tp=N.buildXrpTokenPaymentTxWithSeedHex(seed,JSON.stringify({account:d0[1],destination:'rPEPPER7kfTD9w2To4CQk6UCfuHM9c6GDY',destinationTag:7,currency:'524C555344000000000000000000000000000000',issuer:'rMxCKbEDwqr76QuheSUMdEGf4B9xJ8m5De',value:'12.5',sendMax:'12.525',fee:'12',sequence:91234567}));
ok(tp.length===2&&/^[0-9A-F]{64}$/.test(tp[0]),'token payment built');
const priv=O.getPrivkeyFromSeedHex(seed);
const tp2=N.buildXrpTokenPaymentTxWithPrivKey(priv,JSON.stringify({account:d0[1],destination:'rPEPPER7kfTD9w2To4CQk6UCfuHM9c6GDY',destinationTag:7,currency:'524C555344000000000000000000000000000000',issuer:'rMxCKbEDwqr76QuheSUMdEGf4B9xJ8m5De',value:'12.5',sendMax:'12.525',fee:'12',sequence:91234567}));
ok(tp2[0]===tp[0],'privkey variant equals seed variant');
const ts=N.buildXrpTrustSetTxWithSeedHex(seed,JSON.stringify({account:d0[1],currency:'USD',issuer:'rhub8VRN55s94qWKDv6jmDy1pUykJzF3wq',limit:'1000000000000000',fee:'12',sequence:3}));
ok(ts[0]===N.buildXrpTrustSetTxWithPrivKey(priv,JSON.stringify({account:d0[1],currency:'USD',issuer:'rhub8VRN55s94qWKDv6jmDy1pUykJzF3wq',limit:'1000000000000000',fee:'12',sequence:3}))[0],'trustset built both');
let threw=false;try{N.buildXrpTokenPaymentTxWithSeedHex(seed,JSON.stringify({account:d0[1]}))}catch(e){threw=true}
ok(threw,'missing fields throw');
console.log(JSON.stringify({tp:tp[1].slice(0,80),ts:ts[1].slice(0,60)}));
console.log('PASS',pass);
