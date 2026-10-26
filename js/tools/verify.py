#!/usr/bin/env python3
#  tools/verify.py — Ownbit core (extracted from Ownbit iOS 5.x).
#  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
#  SPDX-License-Identifier: MIT
"""Checks js/ against the iOS app it was extracted from.

  python3 -I js/tools/verify.py --app <app>/components/JavaScriptBridge     full check (needs the app checkout)
  python3 -I js/tools/verify.py                                             repo-only checks

1. every vendor / loader / data file equals "app copy + tools/redact.py rules" byte for byte (for most files the rules
   change nothing: SHA-256 equal to the app); the files with redacted keys contain none of the app's key values;
2. every Ownbit-authored glue source equals the Ownbit entry module inside its shipped bundle (comments, whitespace and
   the browserify wrapper aside; plus the one documented removed line);
3. the network pattern finds nothing in Ownbit-authored files (glue sources, tools, loader pages); in vendor files it
   only counts matches;
4. every Ownbit-authored source file starts with the MIT header;
5. no file anywhere in js/ contains the build-machine path that tools/redact.py replaces;
6. no file anywhere in js/ contains the build user's name (any case, also inside longer words).
Exit status 0 = all good.
"""
import argparse
import hashlib
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
JS = os.path.dirname(HERE)
sys.dont_write_bytecode = True  # no __pycache__ in the repository
sys.path.insert(0, HERE)
import redact  # noqa: E402

# kind: vendor = third-party bundle (may contain Ownbit glue), byte-identical
#       vendor-redacted = vendor bundle changed by tools/redact.py (build-machine path and / or provider API keys)
#       loader = Ownbit's trivial HTML page that loads a bundle into WKWebView, byte-identical
#       data = third-party data file, byte-identical
#       glue = Ownbit-authored readable source of a bundle's entry module (header added), not loaded at runtime
FILES = {
    'adajs-lib-bridge/shelley.bundle.js': 'vendor',
    'adajs-lib-bridge/shelley_ada.html': 'vendor',
    'bitcoinjs-lib-bridge/bitcoinjs-lib-app.js': 'vendor',
    'bitcoinjs-lib-bridge/btc_index.html': 'loader',
    'bitcoinjs-lib-bridge/mnemonic_words.txt': 'data',
    'bitcoincashjs-lib-bridge/bitcoincashjs-lib-app.min.js': 'vendor',
    'btctaprootjs-lib-bridge/btctaproot-lib-app.js': 'vendor',
    'btctaprootjs-lib-bridge/btc_taproot_index.html': 'loader',
    'dashjs-lib-bridge/dashjs-lib-app.min.js': 'vendor-redacted',
    'dashjs-lib-bridge/index.js': 'glue',
    'digibytejs-lib-bridge/digibytejs-lib-app.min.js': 'vendor-redacted',
    'digibytejs-lib-bridge/index.js': 'glue',
    'dogecoinjs-lib-bridge/dogecoinjs-lib-app.min.js': 'vendor-redacted',
    'dogecoinjs-lib-bridge/index.js': 'glue',
    'ethereumjs-lib-bridge/ethereumjs-lib-app.min.js': 'vendor',
    'ethereumjs-lib-bridge/ethjs-ext-v2.js': 'vendor',
    'ethereumjs-lib-bridge/ethext_index.html': 'loader',
    'filejs-lib-bridge/filjs-lib-app.js': 'vendor',
    'filejs-lib-bridge/fil_index.html': 'loader',
    'horizenjs-lib-bridge/zenjs-lib-app.min.js': 'vendor-redacted',
    'horizenjs-lib-bridge/index.js': 'glue',
    'litecoinjs-lib-bridge/litecoinjs-lib-app.min.js': 'vendor-redacted',
    'pubsigner-lib-bridge/signer.js': 'vendor',
    'ripplejs-lib-bridge/ripplejs-lib-app.min.js': 'vendor',
    'soljs-lib-bridge/soljs-lib-app.js': 'vendor',
    'soljs-lib-bridge/sol_index.html': 'loader',
    'stackjs-lib-bridge/stxjs-new.js': 'vendor',
    'stackjs-lib-bridge/stx_index.html': 'loader',
    'stellarjs-lib-bridge/stellarjs-lib-app.min.js': 'vendor-redacted',
    'stellarjs-lib-bridge/index.js': 'glue',
    'tonjs-lib-bridge/tonjs-new.js': 'vendor-redacted',
    'tonjs-lib-bridge/ton_index.html': 'loader',
    'tronjs-lib-bridge/trxjs-lib-app.js': 'vendor-redacted',
    'tronjs-lib-bridge/trx_index.html': 'loader',
    'zcashjs-lib-bridge/zcashjs-lib-app-0251.js': 'vendor-redacted',
    'zcashjs-lib-bridge/zec_index.html': 'loader',
    'zcashjs-lib-bridge/index.js': 'glue',
}
# glue source -> its bundle; lines removed from the glue copy on purpose (secret logging)
GLUE = {
    'dashjs-lib-bridge/index.js': ('dashjs-lib-bridge/dashjs-lib-app.min.js', 1, []),
    'digibytejs-lib-bridge/index.js': ('digibytejs-lib-bridge/digibytejs-lib-app.min.js', 1, []),
    'dogecoinjs-lib-bridge/index.js': ('dogecoinjs-lib-bridge/dogecoinjs-lib-app.min.js', 1, []),
    'horizenjs-lib-bridge/index.js': ('horizenjs-lib-bridge/zenjs-lib-app.min.js', 81,
                                      ["console.log('privateKeys: ' + JSON.stringify(privateKeys));"]),
    'stellarjs-lib-bridge/index.js': ('stellarjs-lib-bridge/stellarjs-lib-app.min.js', 434, []),
    'zcashjs-lib-bridge/index.js': ('zcashjs-lib-bridge/zcashjs-lib-app-0251.js', 133, []),
}
# network pattern of the extraction brief, assembled so this file does not match itself
NET_TOKENS = [('fet' + 'ch(', 'fet' + r'ch\('), ('XMLHttp' + 'Request', 'XMLHttp' + 'Request'), ('http(s)://', 'https?' + '://'),
              ('ws(s)://', 'wss?' + '://'), ('ax' + 'ios', 'ax' + 'ios'), ('.aj' + 'ax', r'\.aj' + 'ax')]
NET = re.compile('|'.join(p for _, p in NET_TOKENS))
HEADER = re.compile(r'^(?:#![^\n]*\n)?(?://|#)  [^\n]+ — Ownbit core \(extracted from Ownbit iOS 5\.x\)\.\n'
                    r'(?://|#)  Copyright \(c\) 2017-2026 BITTOOL PTE\. LTD\.\n(?://|#)  SPDX-License-Identifier: MIT\n')
OWNBIT_TOOL_EXT = ('.js', '.py', '.sh')
THIRD_PARTY_TOOL_FILES = {'btc-taproot-js/package.json', 'btc-taproot-js/package-lock.json', 'btc-taproot-js/.gitignore',
                          'btc-taproot-js/test/bip322/README.md', 'btc-taproot-js/test/bip322/basic-test-vectors.json',
                          'btc-taproot-js/test/bip322/generated-test-vectors.json'}

failures = 0


def report(ok, label):
    global failures
    print(('ok   ' if ok else 'FAIL ') + label)
    if not ok:
        failures += 1


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def read(path):
    with open(path, 'rb') as f:
        return f.read()


def strip_header(text):
    m = HEADER.match(text)
    if not m:
        return None
    rest = text[m.end():]
    # the provenance notes that follow the header
    rest = re.sub(r'^(?://[^\n]*\n)*', '', rest)
    return rest


def norm(s):
    return re.sub(r'\s+', '', s)


def without_comments(s):
    s = re.sub(r'/\*.*?\*/', '', s, flags=re.S)
    return re.sub(r'(?m)^\s*//[^\n]*$', '', s)


def browserify_module(bundle, module_id):
    """Body of browserify module <module_id> (from its header to the next module header)."""
    header = re.compile(r'(?<![\w$])(\d+):\[function\(\w+,\w+,\w+\)\{')
    heads = list(header.finditer(bundle))
    for i, m in enumerate(heads):
        if int(m.group(1)) == module_id:
            end = heads[i + 1].start() if i + 1 < len(heads) else len(bundle)
            return bundle[m.end():end]
    return None


def tool_files():
    for root, dirs, files in os.walk(HERE):
        dirs[:] = [d for d in dirs if d not in ('node_modules', 'out')]
        for f in files:
            rel = os.path.relpath(os.path.join(root, f), HERE)
            yield rel


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--app', help='path to the app\'s components/JavaScriptBridge')
    args = ap.parse_args()

    # 0. the manifest is complete
    on_disk = set()
    for root, dirs, files in os.walk(JS):
        if os.path.abspath(root).startswith(HERE):
            continue
        for f in files:
            rel = os.path.relpath(os.path.join(root, f), JS)
            if rel not in ('README.md', 'HANDOFF.md'):
                on_disk.add(rel)
    report(on_disk == set(FILES), 'js/ holds exactly the %d files of the manifest (extra: %s, missing: %s)'
           % (len(FILES), sorted(on_disk - set(FILES)), sorted(set(FILES) - on_disk)))

    # 1. byte identity with the app
    if args.app:
        for rel, kind in sorted(FILES.items()):
            if kind == 'glue':
                continue
            app_path = os.path.join(args.app, rel)
            if not os.path.exists(app_path):
                report(False, '%s: missing in the app' % rel)
                continue
            mine, theirs = read(os.path.join(JS, rel)), read(app_path)
            expected = redact.redact(rel, theirs)
            if expected == theirs:
                report(kind != 'vendor-redacted' and mine == theirs, '%s == app copy  [%s]' % (rel, sha256(mine)[:16]))
                continue
            report(kind == 'vendor-redacted' and mine == expected,
                   '%s == app copy + redact rules  [app %s, repo %s, %d build paths]'
                   % (rel, sha256(theirs)[:16], sha256(mine)[:16], redact.build_path_count(theirs)))
            keys = _app_keys(rel, theirs.decode('utf-8'))
            if keys:
                leaked = [k for k in keys if k.encode() in mine]
                report(not leaked, '%s: none of the app\'s %d key values present' % (rel, len(keys)))

    # 2. glue sources == entry module of their bundle
    for rel, (bundle, module_id, removed) in sorted(GLUE.items()):
        text = read(os.path.join(JS, rel)).decode('utf-8')
        body = strip_header(text)
        if body is None:
            report(False, '%s: no MIT header' % rel)
            continue
        entry = browserify_module(read(os.path.join(JS, bundle)).decode('utf-8'), module_id)
        if entry is None:
            report(False, '%s: module %d not found in %s' % (rel, module_id, bundle))
            continue
        b = norm(without_comments(entry))
        for line in removed:
            b = b.replace(norm(line), '', 1)
        report(norm(without_comments(body)) in b,
               '%s == browserify module %d of %s (comments / whitespace / wrapper aside)' % (rel, module_id, bundle))

    # 3. network pattern
    ownbit = [os.path.join(JS, r) for r, k in FILES.items() if k in ('glue', 'loader')]
    ownbit += [os.path.join(HERE, r) for r in tool_files()
               if r.endswith(OWNBIT_TOOL_EXT) and r not in THIRD_PARTY_TOOL_FILES]
    hits = []
    for p in ownbit:
        for i, line in enumerate(read(p).decode('utf-8').split('\n'), 1):
            if NET.search(line):
                hits.append('%s:%d' % (os.path.relpath(p, JS), i))
    report(not hits, 'network pattern: no match in %d Ownbit-authored files %s' % (len(ownbit), hits[:10]))
    print('     vendor files, match counts (%s):' % ', '.join(n for n, _ in NET_TOKENS))
    for rel, kind in sorted(FILES.items()):
        if kind.startswith('vendor'):
            s = read(os.path.join(JS, rel)).decode('utf-8', 'replace')
            counts = [len(re.findall(p, s)) for _, p in NET_TOKENS]
            print('       %-50s %s' % (rel, ' / '.join(str(c) for c in counts)))

    # 4. headers
    headed = [os.path.join(JS, r) for r, k in FILES.items() if k == 'glue']
    headed += [os.path.join(HERE, r) for r in tool_files() if r.endswith(OWNBIT_TOOL_EXT) and r not in THIRD_PARTY_TOOL_FILES]
    missing = [os.path.relpath(p, JS) for p in headed if not HEADER.match(read(p).decode('utf-8'))]
    report(not missing, 'MIT header on %d Ownbit-authored source files %s' % (len(headed), missing))

    # 5. build-machine path gone everywhere (bundles, glue, tools, docs)
    left = []
    for root, dirs, files in os.walk(JS):
        dirs[:] = [d for d in dirs if d != 'node_modules']
        for f in files:
            p = os.path.join(root, f)
            if redact.build_path_count(read(p)):
                left.append(os.path.relpath(p, JS))
    report(not left, 'build-machine path: absent from every file in js/ %s' % left)

    # 6. build user's name gone everywhere (matched by its SHA-256; the name is not stored in this repository)
    named, scanned = [], 0
    for root, dirs, files in os.walk(JS):
        dirs[:] = [d for d in dirs if d != 'node_modules']
        for f in files:
            p = os.path.join(root, f)
            scanned += 1
            if redact.build_user_count(read(p)):
                named.append(os.path.relpath(p, JS))
    report(not named, 'build user name: absent from all %d files in js/ %s' % (scanned, named))

    print('ALL OK' if not failures else 'FAILED: %d' % failures)
    return 1 if failures else 0


def _app_keys(rel, text):
    """The key values in the app's copy (found by the same context as tools/redact.py; never printed)."""
    keys = []
    if rel == 'tronjs-lib-bridge/trxjs-lib-app.js':
        m = re.search(r'var tronGridApiKeys = \[([^\]]*)\];', text)
        keys += re.findall(r'"([0-9a-fA-F-]{36})"', m.group(1)) if m else []
        keys += re.findall(r'var tatumApiKey = "([^"]+)";', text)
    elif rel == 'tonjs-lib-bridge/tonjs-new.js':
        keys += re.findall(r"apiKey: '([0-9a-fA-F]{64})'", text)
    return keys


if __name__ == '__main__':
    sys.exit(main())
