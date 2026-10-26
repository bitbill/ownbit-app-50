//  tools/js-bundles/xrp_ext.js — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//  Fragment inserted into the shipped bundle by patch_xrp.js (newlines removed). The patch script strips these leading
//  "//" lines first, so the inserted bytes are exactly the shipped ones.
var bilCodec=e("ripple-binary-codec");
function bilNeed(ok,msg){if(!ok)throw new Error(msg)}
function bilKp(pub,priv){return{privateKey:priv.toUpperCase(),publicKey:pub.toUpperCase()}}
function bilSeedKp(seedHex){var k=l(seedHex);return bilKp(k[0],k[1])}
function bilPrivKp(privHex){bilNeed("string"==typeof privHex&&privHex.length>=64,"invalid private key");var b=new c(privHex,"hex");33===b.length&&0===b[0]&&(b=b.slice(1,33));return bilKp(h(b),privHex)}
function bilIndexKp(seedHex,i){bilNeed("number"==typeof i&&i>=0&&i<2147483648&&Math.floor(i)===i,"invalid index");var k=s(seedHex).derive(i);return bilKp(k.publicKey.toString("hex"),k.privateKey.toString("hex"))}
function bilStr(v,name){bilNeed(null!=v&&""!==String(v),"missing "+name);return String(v)}
function bilSeq(v){var n=Number(v);bilNeed(n>0&&Math.floor(n)===n,"invalid sequence");return n}
function bilTag(tx,v){if(null==v||""===v)return;var n=Number(v);bilNeed(n>=0&&n<=4294967295&&Math.floor(n)===n,"invalid destinationTag");tx.DestinationTag=n}
function bilSign(txJSON,kp){var r=f.sign(txJSON,kp);return[r.id,r.signedTransaction]}
function bilTokenPayment(kp,data){var d=JSON.parse(data),tx={TransactionType:"Payment",Account:bilStr(d.account,"account"),Destination:bilStr(d.destination,"destination")};bilTag(tx,d.destinationTag);tx.Amount={currency:bilStr(d.currency,"currency"),issuer:bilStr(d.issuer,"issuer"),value:bilStr(d.value,"value")};null!=d.sendMax&&""!==d.sendMax&&(tx.SendMax={currency:tx.Amount.currency,issuer:tx.Amount.issuer,value:String(d.sendMax)});tx.Flags=2147483648;tx.Fee=bilStr(d.fee,"fee");tx.Sequence=bilSeq(d.sequence);return bilSign(JSON.stringify(tx),kp)}
function bilTrustSet(kp,data){var d=JSON.parse(data),tx={TransactionType:"TrustSet",Account:bilStr(d.account,"account"),LimitAmount:{currency:bilStr(d.currency,"currency"),issuer:bilStr(d.issuer,"issuer"),value:bilStr(d.limit,"limit")},Flags:2147614720,Fee:bilStr(d.fee,"fee"),Sequence:bilSeq(d.sequence)};return bilSign(JSON.stringify(tx),kp)}
function bilMultiSign(seedHex,jsonStr){var kp=bilSeedKp(seedHex),me=f.deriveAddress(kp.publicKey),tx=JSON.parse(jsonStr);tx.SigningPubKey="";var r=f.sign(JSON.stringify(tx),kp,{signAs:me}),dec=bilCodec.decode(r.signedTransaction);bilNeed(dec.Signers&&1===dec.Signers.length,"multisign failed");var sg=dec.Signers[0].Signer;bilNeed(sg.Account===me,"signer mismatch");return[sg.Account,String(sg.SigningPubKey).toUpperCase(),String(sg.TxnSignature).toUpperCase()]}
