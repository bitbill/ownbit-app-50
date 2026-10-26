#!/usr/bin/env python3
#  tools/btc-taproot-js/test/verify.py — Ownbit core (extracted from Ownbit iOS 5.x).
#  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
#  SPDX-License-Identifier: MIT
"""Independent check of test/out/cases.json (written by vectors.js) with embit (pip install embit==0.8.0).

Derives every spent script itself from the seed (BIP86 key + tweak for Taproot, BIP84/49/44 for the others),
recomputes each input's sighash with embit's own BIP341 / BIP143 / legacy code and verifies every signature,
plus the transaction shape the app relies on (version 2, RBF sequence unless OP_RETURN, locktime, outputs).
"""
import json, os, sys
from embit import ec, bip32, script
from embit.transaction import Transaction, SIGHASH
from embit.networks import NETWORKS

HERE = os.path.dirname(os.path.abspath(__file__))
# 默认验 vectors.js 写的 out/cases.json；也可以传别的文件（同样格式），比如模拟器上 App 签出来的交易
data = json.load(open(sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, 'out/cases.json')))
seed = bytes.fromhex('5eb00bbddcf069084889a8ab9155568165f5c453ccb85e70811aaed6f6da5fc19a5ac40b389cd370d086206dec8aa6c43daea6690f20ad3d8d48b2d2ce9e38e4')
root = bip32.HDKey.from_seed(seed)
legacy_prev = Transaction.parse(bytes.fromhex(data['legacyPrevHex']))
net = NETWORKS['main']
failures = 0


def check(label, cond):
    global failures
    if not cond:
        failures += 1
    print(('  ok   ' if cond else '  FAIL ') + label)


def key_for(inp):
    change = 1 if inp['isChange'] else 0
    purpose = {'T': 86, 'D': 84, 'P': 49, '': 44}[inp['segwit']]
    return root.derive("m/%dh/0h/0h/%d/%d" % (purpose, change, inp['bip39Index']))


for case in data['cases']:
    print(case['name'])
    tx = Transaction.parse(bytes.fromhex(case['hex']))
    d = case['data']
    ins = d['inputs']
    has_op_return = bool(d.get('ophex'))
    check('version 2', tx.version == 2)
    check('locktime', tx.locktime == (d.get('locktime') or 0))
    check('sequence %s' % ('0xffffffff (OP_RETURN)' if has_op_return else '0xfffffffd (RBF)'),
          all(v.sequence == (0xffffffff if has_op_return else 0xfffffffd) for v in tx.vin))
    outs = list(tx.vout)
    if has_op_return:
        check('OP_RETURN output first', outs[0].value == 0 and outs[0].script_pubkey.data == bytes([0x6a, len(d['ophex']) // 2]) + bytes.fromhex(d['ophex']))
        outs = outs[1:]
    check('outputs match addresses / amounts',
          [(o.script_pubkey.data, o.value) for o in outs] == [(script.address_to_scriptpubkey(o['address']).data, o['amount']) for o in d['outputs']])

    # spent scripts / values, derived here independently
    spent, values, pubs = [], [], []
    for inp in ins:
        pk = key_for(inp).key.get_public_key()
        # the non-Taproot WIFs in the fixtures must be the same keys we derive here
        if inp['segwit'] != 'T':
            check('input %s key from the seed matches the fixture WIF' % inp['txHash'][:8], ec.PrivateKey.from_wif(inp['wif']).get_public_key().sec() == pk.sec())
        if inp['segwit'] == 'T':
            s = script.p2tr(pk)
        elif inp['segwit'] == 'D':
            s = script.p2wpkh(pk)
        elif inp['segwit'] == 'P':
            s = script.p2sh(script.p2wpkh(pk))
        else:
            s = legacy_prev.vout[inp['index']].script_pubkey
            check('legacy prevout is P2PKH of the derived key', s.data == script.p2pkh(pk).data)
        spent.append(s)
        values.append(inp['satoshis'])
        pubs.append(pk)

    for i, inp in enumerate(ins):
        vin = tx.vin[i]
        check('input %d prevout' % i, vin.txid.hex() == inp['txHash'] and vin.vout == inp['index'])
        if inp['segwit'] == 'T':
            items = vin.witness.items
            h = tx.sighash_taproot(i, script_pubkeys=spent, values=values, sighash=SIGHASH.DEFAULT)
            out_key = ec.PublicKey.from_xonly(spent[i].data[2:])
            ok = len(items) == 1 and len(items[0]) == 64 and out_key.schnorr_verify(ec.SchnorrSig.parse(items[0]), h)
            check('input %d Taproot key-path: 64-byte Schnorr sig valid for BIP341 sighash (SIGHASH_DEFAULT)' % i, ok)
            check('input %d Taproot: empty scriptSig' % i, len(vin.script_sig.data) == 0)
        elif inp['segwit'] in ('D', 'P'):
            sig, pub = vin.witness.items
            h = tx.sighash_segwit(i, script.p2pkh(pubs[i]), values[i], sighash=SIGHASH.ALL)
            ok = sig[-1] == SIGHASH.ALL and pub == pubs[i].sec() and pubs[i].verify(ec.Signature.parse(sig[:-1]), h)
            check('input %d %s: ECDSA valid for BIP143 sighash' % (i, 'P2WPKH' if inp['segwit'] == 'D' else 'P2SH-P2WPKH'), ok)
            if inp['segwit'] == 'P':
                check('input %d P2SH-P2WPKH scriptSig pushes the redeem script' % i, vin.script_sig.data == bytes([22]) + script.p2wpkh(pubs[i]).data)
        else:
            ss = vin.script_sig.data
            sig = ss[1:1 + ss[0]]
            pub = ss[2 + ss[0]:]
            h = tx.sighash_legacy(i, spent[i], sighash=SIGHASH.ALL)
            ok = sig[-1] == SIGHASH.ALL and pub == pubs[i].sec() and pubs[i].verify(ec.Signature.parse(sig[:-1]), h)
            check('input %d legacy P2PKH: ECDSA valid for legacy sighash' % i, ok)

print('ALL OK' if failures == 0 else '%d FAILED' % failures)
sys.exit(1 if failures else 0)
