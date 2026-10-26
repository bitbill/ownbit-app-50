//  tools/js-bundles/jsc.js — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT

// Load a bundle like the app does: bare global without require/module (JSContext); web=true adds window (UIWebView context, used by XLM)
const vm=require('vm'),fs=require('fs');
module.exports=function(file,web){const sb={console};if(web)sb.window=sb;vm.createContext(sb);vm.runInContext(fs.readFileSync(file,'utf8'),sb);return sb.bridge;};
