#  tools/redact.py — Ownbit core (extracted from Ownbit iOS 5.x).
#  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
#  SPDX-License-Identifier: MIT
#
#  The only differences between the app's files and the copies in js/ (everything else is byte-identical):
#
#  1. Build-machine path. Some bundles embed npm package.json metadata ("_where": "<home>/…") from the machine they
#     were built on. Every "/Users/<that user>" (17 bytes) becomes "/build/ownbit-js0" (17 bytes), so offsets do not
#     move. The user name is not stored here: the rule recognises it by its SHA-256.
#     Any other whole-word occurrence of that 10-letter name (an author note in a code comment) becomes "ownbit dev"
#     (10 bytes).
#  2. Secrets. Two bundles carry third-party provider API keys inside the Ownbit glue. Each key is replaced by a
#     placeholder of the same length; the rule finds the keys by context and shape, never by value.
#
#  verify.py uses this module to prove "app file + these rules == repo file", byte for byte.
#  Usage as a tool:  python3 -I tools/redact.py <app file> <out file> <published path, e.g. tronjs-lib-bridge/trxjs-lib-app.js>
import hashlib
import re
import sys

# ---- 1. build-machine path ----
BUILD_USER_SHA256 = '50827c1f6e45ebf86a982c1826a7b28201f72bb083bbf3f94eb4d452c8db6dc9'
BUILD_PATH_PLACEHOLDER = b'/build/ownbit-js0'
_USER_PATH = re.compile(rb'/Users/([A-Za-z0-9._-]+)')


def _is_build_user(name):
    return hashlib.sha256(name).hexdigest() == BUILD_USER_SHA256


def _build_path(m):
    if not _is_build_user(m.group(1)):
        return m.group(0)
    if len(m.group(0)) != len(BUILD_PATH_PLACEHOLDER):
        raise ValueError('build path and placeholder differ in length')
    return BUILD_PATH_PLACEHOLDER


def build_path_count(data):
    """Number of build-machine paths in <data> (bytes)."""
    return sum(1 for m in _USER_PATH.finditer(data) if _is_build_user(m.group(1)))


NAME_PLACEHOLDER = b'ownbit dev'
_WORD = re.compile(rb'(?<![A-Za-z0-9])[A-Za-z]{10}(?![A-Za-z0-9])')
_LETTERS = re.compile(rb'[a-z]{10,}')


def _name(m):
    return NAME_PLACEHOLDER if _is_build_user(m.group(0).lower()) else m.group(0)


def build_user_count(data):
    """Occurrences of the build user's name anywhere in <data> (bytes), any case, also inside longer words."""
    n = 0
    for m in _LETTERS.finditer(data.lower()):
        run = m.group(0)
        n += sum(1 for i in range(len(run) - 9) if _is_build_user(run[i:i + 10]))
    return n


# ---- 2. provider API keys ----
def _key_list(m):
    keys = re.findall(r'"[0-9a-fA-F-]{36}"', m.group(2))
    body = m.group(2)
    for i, k in enumerate(keys, 1):
        body = body.replace(k, '"REDACTED-0000-0000-0000-%012d"' % i, 1)
    return m.group(1) + body + m.group(3)


def _key_literal(prefix):
    def fn(m):
        key = m.group(2)
        return m.group(1) + (prefix + '0' * len(key))[:len(key)] + m.group(3)
    return fn


# published path -> list of (pattern, replacement function, expected number of matches)
KEY_RULES = {
    'tronjs-lib-bridge/trxjs-lib-app.js': [
        (re.compile(r'(var tronGridApiKeys = \[)([^\]]*)(\];)'), _key_list, 1),
        (re.compile(r'(var tatumApiKey = ")(t-[0-9a-fA-F-]+)(";)'), _key_literal('t-REDACTED'), 1),
    ],
    'tonjs-lib-bridge/tonjs-new.js': [
        (re.compile(r"(new TonWeb\.HttpProvider\('[^']*', \{\s*apiKey: ')([0-9a-fA-F]{64})(')"), _key_literal('REDACTED'), 1),
    ],
}


def redact(published_path, data):
    """App file bytes -> repo file bytes."""
    data = _USER_PATH.sub(_build_path, data)
    data = _WORD.sub(_name, data)
    rules = KEY_RULES.get(published_path)
    if rules:
        text = data.decode('utf-8')
        for pattern, fn, expected in rules:
            text, n = pattern.subn(fn, text)
            if n != expected:
                raise ValueError('%s: rule %s matched %d times, expected %d' % (published_path, pattern.pattern, n, expected))
        data = text.encode('utf-8')
    return data


if __name__ == '__main__':
    src, dst, published = sys.argv[1], sys.argv[2], sys.argv[3]
    with open(src, 'rb') as f:
        data = f.read()
    out = redact(published, data)
    with open(dst, 'wb') as f:
        f.write(out)
    print('%s: %d bytes in, %d bytes out, %d build paths / %d name occurrences replaced, %s'
          % (published, len(data), len(out), build_path_count(data), build_user_count(data) - build_path_count(data),
             'changed' if out != data else 'unchanged'))
