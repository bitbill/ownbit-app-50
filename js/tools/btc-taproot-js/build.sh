#!/bin/sh
#  tools/btc-taproot-js/build.sh — Ownbit core (extracted from Ownbit iOS 5.x).
#  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
#  SPDX-License-Identifier: MIT
# Builds js/btctaprootjs-lib-bridge/btctaproot-lib-app.js (global `bridge`) from src/index.js.
# Dependencies are pinned in package-lock.json: npm ci && sh build.sh
# Target Safari 14.1: the pure-JS secp256k1 (@noble) needs BigInt, and esbuild treats destructuring as unsafe before
# Safari 14.1 (WebKit bug) -- so the Taproot feature is iOS 14.5+.
set -e
cd "$(dirname "$0")"
OUT=../../btctaprootjs-lib-bridge   # js/btctaprootjs-lib-bridge in this repository
mkdir -p "$OUT"
npx esbuild src/index.js --bundle --format=iife --global-name=bridge --platform=browser --target=safari14.1 \
  --inject:./buffer-shim.js --inject:./process-shim.js --alias:stream=stream-browserify --define:global=globalThis --legal-comments=eof --minify-syntax \
  --outfile="$OUT/btctaproot-lib-app.js"
ls -la "$OUT/btctaproot-lib-app.js"
