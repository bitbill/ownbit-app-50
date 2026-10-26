#!/usr/bin/env python3
#  tools/btc-taproot-js/test/verify_raw.py — Ownbit core (extracted from Ownbit iOS 5.x).
#  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
#  SPDX-License-Identifier: MIT
"""Independent check (embit) of an already signed transaction against the outputs it spends.

Usage: python3 test/verify_raw.py <file.json>
  file.json = {"hex": "<signed tx>", "prevouts": [{"script": "<scriptPubKey hex>", "amount": <sats>}, ...]}  (same order as the inputs)

Every input is checked by the type of the script it spends, with embit's own sighash code:
P2TR key-path (SIGHASH_DEFAULT, 64-byte Schnorr against the output key), P2WPKH / P2SH-P2WPKH (BIP143), P2PKH (legacy).
Used for the app's dry-run signing with real server UTXOs (-bil_debug_screen taprootsend): nothing is broadcast.
"""
import json
import sys
from embit import ec, script, hashes
from embit.script import Script
from embit.transaction import Transaction, SIGHASH

d = json.load(open(sys.argv[1]))
tx = Transaction.parse(bytes.fromhex(d['hex']))
prev = d['prevouts']
spks = [Script(bytes.fromhex(p['script'])) for p in prev]
values = [p['amount'] for p in prev]
failures = 0


def check(label, ok):
    global failures
    if not ok:
        failures += 1
    print(('  ok   ' if ok else '  FAIL ') + label)


check('input count matches prevouts (%d)' % len(prev), len(tx.vin) == len(prev))
for i, vin in enumerate(tx.vin):
    s = spks[i].data
    tag = '%s:%d' % (vin.txid.hex()[:10], vin.vout)
    if len(s) == 34 and s[0] == 0x51 and s[1] == 0x20:
        items = vin.witness.items
        h = tx.sighash_taproot(i, script_pubkeys=spks, values=values, sighash=SIGHASH.DEFAULT)
        ok = len(items) == 1 and len(items[0]) == 64 and len(vin.script_sig.data) == 0 \
            and ec.PublicKey.from_xonly(s[2:]).schnorr_verify(ec.SchnorrSig.parse(items[0]), h)
        check('input %d %s P2TR key-path Schnorr valid (BIP341, all %d prevouts committed)' % (i, tag, len(prev)), ok)
    elif len(s) == 22 and s[0] == 0x00 and s[1] == 0x14:
        sig, pub = vin.witness.items
        pk = ec.PublicKey.parse(pub)
        h = tx.sighash_segwit(i, script.p2pkh(pk), values[i], sighash=SIGHASH.ALL)
        ok = hashes.hash160(pub) == s[2:] and sig[-1] == SIGHASH.ALL and pk.verify(ec.Signature.parse(sig[:-1]), h)
        check('input %d %s P2WPKH ECDSA valid (BIP143)' % (i, tag), ok)
    elif len(s) == 23 and s[0] == 0xa9 and s[1] == 0x14 and s[22] == 0x87:
        sig, pub = vin.witness.items
        pk = ec.PublicKey.parse(pub)
        redeem = script.p2wpkh(pk)
        h = tx.sighash_segwit(i, script.p2pkh(pk), values[i], sighash=SIGHASH.ALL)
        ok = hashes.hash160(redeem.data) == s[2:22] and vin.script_sig.data == bytes([len(redeem.data)]) + redeem.data \
            and sig[-1] == SIGHASH.ALL and pk.verify(ec.Signature.parse(sig[:-1]), h)
        check('input %d %s P2SH-P2WPKH ECDSA valid (BIP143)' % (i, tag), ok)
    elif len(s) == 25 and s[:3] == b'\x76\xa9\x14' and s[23:] == b'\x88\xac':
        ss = vin.script_sig.data
        sig = ss[1:1 + ss[0]]
        pub = ss[2 + ss[0]:]
        pk = ec.PublicKey.parse(pub)
        h = tx.sighash_legacy(i, spks[i], sighash=SIGHASH.ALL)
        ok = hashes.hash160(pub) == s[3:23] and sig[-1] == SIGHASH.ALL and pk.verify(ec.Signature.parse(sig[:-1]), h)
        check('input %d %s P2PKH ECDSA valid (legacy)' % (i, tag), ok)
    else:
        check('input %d %s unsupported script %s' % (i, tag, s.hex()), False)

print('fee = %d sats' % (sum(values) - sum(o.value for o in tx.vout)))
print('ALL OK' if failures == 0 else '%d FAILED' % failures)
sys.exit(1 if failures else 0)
