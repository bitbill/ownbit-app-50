(function(f){if(typeof exports==="object"&&typeof module!=="undefined"){module.exports=f()}else if(typeof define==="function"&&define.amd){define([],f)}else{var g;if(typeof window!=="undefined"){g=window}else if(typeof global!=="undefined"){g=global}else if(typeof self!=="undefined"){g=self}else{g=this}g.bridge = f()}})(function(){var define,module,exports;return (function(){function r(e,n,t){function o(i,f){if(!n[i]){if(!e[i]){var c="function"==typeof require&&require;if(!f&&c)return c(i,!0);if(u)return u(i,!0);var a=new Error("Cannot find module '"+i+"'");throw a.code="MODULE_NOT_FOUND",a}var p=n[i]={exports:{}};e[i][0].call(p.exports,function(r){var n=e[i][1][r];return o(n||r)},p,p.exports,r,e,n,t)}return n[i].exports}for(var u="function"==typeof require&&require,i=0;i<t.length;i++)o(t[i]);return o}return r})()({1:[function(require,module,exports){
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.output = exports.exists = exports.hash = exports.bytes = exports.bool = exports.number = void 0;
function number(n) {
    if (!Number.isSafeInteger(n) || n < 0)
        throw new Error(`Wrong positive integer: ${n}`);
}
exports.number = number;
function bool(b) {
    if (typeof b !== 'boolean')
        throw new Error(`Expected boolean, not ${b}`);
}
exports.bool = bool;
function bytes(b, ...lengths) {
    if (!(b instanceof Uint8Array))
        throw new TypeError('Expected Uint8Array');
    if (lengths.length > 0 && !lengths.includes(b.length))
        throw new TypeError(`Expected Uint8Array of length ${lengths}, not of length=${b.length}`);
}
exports.bytes = bytes;
function hash(hash) {
    if (typeof hash !== 'function' || typeof hash.create !== 'function')
        throw new Error('Hash should be wrapped by utils.wrapConstructor');
    number(hash.outputLen);
    number(hash.blockLen);
}
exports.hash = hash;
function exists(instance, checkFinished = true) {
    if (instance.destroyed)
        throw new Error('Hash instance has been destroyed');
    if (checkFinished && instance.finished)
        throw new Error('Hash#digest() has already been called');
}
exports.exists = exists;
function output(out, instance) {
    bytes(out);
    const min = instance.outputLen;
    if (out.length < min) {
        throw new Error(`digestInto() expects output buffer of length at least ${min}`);
    }
}
exports.output = output;
const assert = {
    number,
    bool,
    bytes,
    hash,
    exists,
    output,
};
exports.default = assert;

},{}],2:[function(require,module,exports){
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.SHA2 = void 0;
const _assert_js_1 = require("./_assert.js");
const utils_js_1 = require("./utils.js");
// Polyfill for Safari 14
function setBigUint64(view, byteOffset, value, isLE) {
    if (typeof view.setBigUint64 === 'function')
        return view.setBigUint64(byteOffset, value, isLE);
    const _32n = BigInt(32);
    const _u32_max = BigInt(0xffffffff);
    const wh = Number((value >> _32n) & _u32_max);
    const wl = Number(value & _u32_max);
    const h = isLE ? 4 : 0;
    const l = isLE ? 0 : 4;
    view.setUint32(byteOffset + h, wh, isLE);
    view.setUint32(byteOffset + l, wl, isLE);
}
// Base SHA2 class (RFC 6234)
class SHA2 extends utils_js_1.Hash {
    constructor(blockLen, outputLen, padOffset, isLE) {
        super();
        this.blockLen = blockLen;
        this.outputLen = outputLen;
        this.padOffset = padOffset;
        this.isLE = isLE;
        this.finished = false;
        this.length = 0;
        this.pos = 0;
        this.destroyed = false;
        this.buffer = new Uint8Array(blockLen);
        this.view = (0, utils_js_1.createView)(this.buffer);
    }
    update(data) {
        _assert_js_1.default.exists(this);
        const { view, buffer, blockLen } = this;
        data = (0, utils_js_1.toBytes)(data);
        const len = data.length;
        for (let pos = 0; pos < len;) {
            const take = Math.min(blockLen - this.pos, len - pos);
            // Fast path: we have at least one block in input, cast it to view and process
            if (take === blockLen) {
                const dataView = (0, utils_js_1.createView)(data);
                for (; blockLen <= len - pos; pos += blockLen)
                    this.process(dataView, pos);
                continue;
            }
            buffer.set(data.subarray(pos, pos + take), this.pos);
            this.pos += take;
            pos += take;
            if (this.pos === blockLen) {
                this.process(view, 0);
                this.pos = 0;
            }
        }
        this.length += data.length;
        this.roundClean();
        return this;
    }
    digestInto(out) {
        _assert_js_1.default.exists(this);
        _assert_js_1.default.output(out, this);
        this.finished = true;
        // Padding
        // We can avoid allocation of buffer for padding completely if it
        // was previously not allocated here. But it won't change performance.
        const { buffer, view, blockLen, isLE } = this;
        let { pos } = this;
        // append the bit '1' to the message
        buffer[pos++] = 0b10000000;
        this.buffer.subarray(pos).fill(0);
        // we have less than padOffset left in buffer, so we cannot put length in current block, need process it and pad again
        if (this.padOffset > blockLen - pos) {
            this.process(view, 0);
            pos = 0;
        }
        // Pad until full block byte with zeros
        for (let i = pos; i < blockLen; i++)
            buffer[i] = 0;
        // Note: sha512 requires length to be 128bit integer, but length in JS will overflow before that
        // You need to write around 2 exabytes (u64_max / 8 / (1024**6)) for this to happen.
        // So we just write lowest 64 bits of that value.
        setBigUint64(view, blockLen - 8, BigInt(this.length * 8), isLE);
        this.process(view, 0);
        const oview = (0, utils_js_1.createView)(out);
        const len = this.outputLen;
        // NOTE: we do division by 4 later, which should be fused in single op with modulo by JIT
        if (len % 4)
            throw new Error('_sha2: outputLen should be aligned to 32bit');
        const outLen = len / 4;
        const state = this.get();
        if (outLen > state.length)
            throw new Error('_sha2: outputLen bigger than state');
        for (let i = 0; i < outLen; i++)
            oview.setUint32(4 * i, state[i], isLE);
    }
    digest() {
        const { buffer, outputLen } = this;
        this.digestInto(buffer);
        const res = buffer.slice(0, outputLen);
        this.destroy();
        return res;
    }
    _cloneInto(to) {
        to || (to = new this.constructor());
        to.set(...this.get());
        const { blockLen, buffer, length, finished, destroyed, pos } = this;
        to.length = length;
        to.pos = pos;
        to.finished = finished;
        to.destroyed = destroyed;
        if (length % blockLen)
            to.buffer.set(buffer);
        return to;
    }
}
exports.SHA2 = SHA2;

},{"./_assert.js":1,"./utils.js":9}],3:[function(require,module,exports){
"use strict";

Object.defineProperty(exports, "__esModule", {
  value: true
});
exports.add = exports.toBig = exports.split = exports.fromBig = void 0;
const U32_MASK64 = BigInt(2 ** 32 - 1);

const _32n = BigInt(32); // We are not using BigUint64Array, because they are extremely slow as per 2022


function fromBig(n, le = false) {
  if (le) return {
    h: Number(n & U32_MASK64),
    l: Number(n >> _32n & U32_MASK64)
  };
  return {
    h: Number(n >> _32n & U32_MASK64) | 0,
    l: Number(n & U32_MASK64) | 0
  };
}

exports.fromBig = fromBig;

function split(lst, le = false) {
  let Ah = new Uint32Array(lst.length);
  let Al = new Uint32Array(lst.length);

  for (let i = 0; i < lst.length; i++) {
    const {
      h,
      l
    } = fromBig(lst[i], le);
    [Ah[i], Al[i]] = [h, l];
  }

  return [Ah, Al];
}

exports.split = split;

const toBig = (h, l) => BigInt(h >>> 0) << _32n | BigInt(l >>> 0);

exports.toBig = toBig; // for Shift in [0, 32)

const shrSH = (h, l, s) => h >>> s;

const shrSL = (h, l, s) => h << 32 - s | l >>> s; // Right rotate for Shift in [1, 32)


const rotrSH = (h, l, s) => h >>> s | l << 32 - s;

const rotrSL = (h, l, s) => h << 32 - s | l >>> s; // Right rotate for Shift in (32, 64), NOTE: 32 is special case.


const rotrBH = (h, l, s) => h << 64 - s | l >>> s - 32;

const rotrBL = (h, l, s) => h >>> s - 32 | l << 64 - s; // Right rotate for shift===32 (just swaps l&h)


const rotr32H = (h, l) => l;

const rotr32L = (h, l) => h; // Left rotate for Shift in [1, 32)


const rotlSH = (h, l, s) => h << s | l >>> 32 - s;

const rotlSL = (h, l, s) => l << s | h >>> 32 - s; // Left rotate for Shift in (32, 64), NOTE: 32 is special case.


const rotlBH = (h, l, s) => l << s - 32 | h >>> 64 - s;

const rotlBL = (h, l, s) => h << s - 32 | l >>> 64 - s; // JS uses 32-bit signed integers for bitwise operations which means we cannot
// simple take carry out of low bit sum by shift, we need to use division.
// Removing "export" has 5% perf penalty -_-


function add(Ah, Al, Bh, Bl) {
  const l = (Al >>> 0) + (Bl >>> 0);
  return {
    h: Ah + Bh + (l / 2 ** 32 | 0) | 0,
    l: l | 0
  };
}

exports.add = add; // Addition with more than 2 elements

const add3L = (Al, Bl, Cl) => (Al >>> 0) + (Bl >>> 0) + (Cl >>> 0);

const add3H = (low, Ah, Bh, Ch) => Ah + Bh + Ch + (low / 2 ** 32 | 0) | 0;

const add4L = (Al, Bl, Cl, Dl) => (Al >>> 0) + (Bl >>> 0) + (Cl >>> 0) + (Dl >>> 0);

const add4H = (low, Ah, Bh, Ch, Dh) => Ah + Bh + Ch + Dh + (low / 2 ** 32 | 0) | 0;

const add5L = (Al, Bl, Cl, Dl, El) => (Al >>> 0) + (Bl >>> 0) + (Cl >>> 0) + (Dl >>> 0) + (El >>> 0);

const add5H = (low, Ah, Bh, Ch, Dh, Eh) => Ah + Bh + Ch + Dh + Eh + (low / 2 ** 32 | 0) | 0; // prettier-ignore


const u64 = {
  fromBig,
  split,
  toBig: exports.toBig,
  shrSH,
  shrSL,
  rotrSH,
  rotrSL,
  rotrBH,
  rotrBL,
  rotr32H,
  rotr32L,
  rotlSH,
  rotlSL,
  rotlBH,
  rotlBL,
  add,
  add3L,
  add3H,
  add4L,
  add4H,
  add5H,
  add5L
};
exports.default = u64;

},{}],4:[function(require,module,exports){
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.crypto = void 0;
exports.crypto = {
    node: undefined,
    web: typeof self === 'object' && 'crypto' in self ? self.crypto : undefined,
};

},{}],5:[function(require,module,exports){
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.hmac = void 0;
const _assert_js_1 = require("./_assert.js");
const utils_js_1 = require("./utils.js");
// HMAC (RFC 2104)
class HMAC extends utils_js_1.Hash {
    constructor(hash, _key) {
        super();
        this.finished = false;
        this.destroyed = false;
        _assert_js_1.default.hash(hash);
        const key = (0, utils_js_1.toBytes)(_key);
        this.iHash = hash.create();
        if (typeof this.iHash.update !== 'function')
            throw new TypeError('Expected instance of class which extends utils.Hash');
        this.blockLen = this.iHash.blockLen;
        this.outputLen = this.iHash.outputLen;
        const blockLen = this.blockLen;
        const pad = new Uint8Array(blockLen);
        // blockLen can be bigger than outputLen
        pad.set(key.length > blockLen ? hash.create().update(key).digest() : key);
        for (let i = 0; i < pad.length; i++)
            pad[i] ^= 0x36;
        this.iHash.update(pad);
        // By doing update (processing of first block) of outer hash here we can re-use it between multiple calls via clone
        this.oHash = hash.create();
        // Undo internal XOR && apply outer XOR
        for (let i = 0; i < pad.length; i++)
            pad[i] ^= 0x36 ^ 0x5c;
        this.oHash.update(pad);
        pad.fill(0);
    }
    update(buf) {
        _assert_js_1.default.exists(this);
        this.iHash.update(buf);
        return this;
    }
    digestInto(out) {
        _assert_js_1.default.exists(this);
        _assert_js_1.default.bytes(out, this.outputLen);
        this.finished = true;
        this.iHash.digestInto(out);
        this.oHash.update(out);
        this.oHash.digestInto(out);
        this.destroy();
    }
    digest() {
        const out = new Uint8Array(this.oHash.outputLen);
        this.digestInto(out);
        return out;
    }
    _cloneInto(to) {
        // Create new instance without calling constructor since key already in state and we don't know it.
        to || (to = Object.create(Object.getPrototypeOf(this), {}));
        const { oHash, iHash, finished, destroyed, blockLen, outputLen } = this;
        to = to;
        to.finished = finished;
        to.destroyed = destroyed;
        to.blockLen = blockLen;
        to.outputLen = outputLen;
        to.oHash = oHash._cloneInto(to.oHash);
        to.iHash = iHash._cloneInto(to.iHash);
        return to;
    }
    destroy() {
        this.destroyed = true;
        this.oHash.destroy();
        this.iHash.destroy();
    }
}
/**
 * HMAC: RFC2104 message authentication code.
 * @param hash - function that would be used e.g. sha256
 * @param key - message key
 * @param message - message data
 */
const hmac = (hash, key, message) => new HMAC(hash, key).update(message).digest();
exports.hmac = hmac;
exports.hmac.create = (hash, key) => new HMAC(hash, key);

},{"./_assert.js":1,"./utils.js":9}],6:[function(require,module,exports){
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.ripemd160 = exports.RIPEMD160 = void 0;
const _sha2_js_1 = require("./_sha2.js");
const utils_js_1 = require("./utils.js");
// https://homes.esat.kuleuven.be/~bosselae/ripemd160.html
// https://homes.esat.kuleuven.be/~bosselae/ripemd160/pdf/AB-9601/AB-9601.pdf
const Rho = new Uint8Array([7, 4, 13, 1, 10, 6, 15, 3, 12, 0, 9, 5, 2, 14, 11, 8]);
const Id = Uint8Array.from({ length: 16 }, (_, i) => i);
const Pi = Id.map((i) => (9 * i + 5) % 16);
let idxL = [Id];
let idxR = [Pi];
for (let i = 0; i < 4; i++)
    for (let j of [idxL, idxR])
        j.push(j[i].map((k) => Rho[k]));
const shifts = [
    [11, 14, 15, 12, 5, 8, 7, 9, 11, 13, 14, 15, 6, 7, 9, 8],
    [12, 13, 11, 15, 6, 9, 9, 7, 12, 15, 11, 13, 7, 8, 7, 7],
    [13, 15, 14, 11, 7, 7, 6, 8, 13, 14, 13, 12, 5, 5, 6, 9],
    [14, 11, 12, 14, 8, 6, 5, 5, 15, 12, 15, 14, 9, 9, 8, 6],
    [15, 12, 13, 13, 9, 5, 8, 6, 14, 11, 12, 11, 8, 6, 5, 5],
].map((i) => new Uint8Array(i));
const shiftsL = idxL.map((idx, i) => idx.map((j) => shifts[i][j]));
const shiftsR = idxR.map((idx, i) => idx.map((j) => shifts[i][j]));
const Kl = new Uint32Array([0x00000000, 0x5a827999, 0x6ed9eba1, 0x8f1bbcdc, 0xa953fd4e]);
const Kr = new Uint32Array([0x50a28be6, 0x5c4dd124, 0x6d703ef3, 0x7a6d76e9, 0x00000000]);
// The rotate left (circular left shift) operation for uint32
const rotl = (word, shift) => (word << shift) | (word >>> (32 - shift));
// It's called f() in spec.
function f(group, x, y, z) {
    if (group === 0)
        return x ^ y ^ z;
    else if (group === 1)
        return (x & y) | (~x & z);
    else if (group === 2)
        return (x | ~y) ^ z;
    else if (group === 3)
        return (x & z) | (y & ~z);
    else
        return x ^ (y | ~z);
}
// Temporary buffer, not used to store anything between runs
const BUF = new Uint32Array(16);
class RIPEMD160 extends _sha2_js_1.SHA2 {
    constructor() {
        super(64, 20, 8, true);
        this.h0 = 0x67452301 | 0;
        this.h1 = 0xefcdab89 | 0;
        this.h2 = 0x98badcfe | 0;
        this.h3 = 0x10325476 | 0;
        this.h4 = 0xc3d2e1f0 | 0;
    }
    get() {
        const { h0, h1, h2, h3, h4 } = this;
        return [h0, h1, h2, h3, h4];
    }
    set(h0, h1, h2, h3, h4) {
        this.h0 = h0 | 0;
        this.h1 = h1 | 0;
        this.h2 = h2 | 0;
        this.h3 = h3 | 0;
        this.h4 = h4 | 0;
    }
    process(view, offset) {
        for (let i = 0; i < 16; i++, offset += 4)
            BUF[i] = view.getUint32(offset, true);
        // prettier-ignore
        let al = this.h0 | 0, ar = al, bl = this.h1 | 0, br = bl, cl = this.h2 | 0, cr = cl, dl = this.h3 | 0, dr = dl, el = this.h4 | 0, er = el;
        // Instead of iterating 0 to 80, we split it into 5 groups
        // And use the groups in constants, functions, etc. Much simpler
        for (let group = 0; group < 5; group++) {
            const rGroup = 4 - group;
            const hbl = Kl[group], hbr = Kr[group]; // prettier-ignore
            const rl = idxL[group], rr = idxR[group]; // prettier-ignore
            const sl = shiftsL[group], sr = shiftsR[group]; // prettier-ignore
            for (let i = 0; i < 16; i++) {
                const tl = (rotl(al + f(group, bl, cl, dl) + BUF[rl[i]] + hbl, sl[i]) + el) | 0;
                al = el, el = dl, dl = rotl(cl, 10) | 0, cl = bl, bl = tl; // prettier-ignore
            }
            // 2 loops are 10% faster
            for (let i = 0; i < 16; i++) {
                const tr = (rotl(ar + f(rGroup, br, cr, dr) + BUF[rr[i]] + hbr, sr[i]) + er) | 0;
                ar = er, er = dr, dr = rotl(cr, 10) | 0, cr = br, br = tr; // prettier-ignore
            }
        }
        // Add the compressed chunk to the current hash value
        this.set((this.h1 + cl + dr) | 0, (this.h2 + dl + er) | 0, (this.h3 + el + ar) | 0, (this.h4 + al + br) | 0, (this.h0 + bl + cr) | 0);
    }
    roundClean() {
        BUF.fill(0);
    }
    destroy() {
        this.destroyed = true;
        this.buffer.fill(0);
        this.set(0, 0, 0, 0, 0);
    }
}
exports.RIPEMD160 = RIPEMD160;
/**
 * RIPEMD-160 - a hash function from 1990s.
 * @param message - msg that would be hashed
 */
exports.ripemd160 = (0, utils_js_1.wrapConstructor)(() => new RIPEMD160());

},{"./_sha2.js":2,"./utils.js":9}],7:[function(require,module,exports){
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.sha224 = exports.sha256 = void 0;
const _sha2_js_1 = require("./_sha2.js");
const utils_js_1 = require("./utils.js");
// Choice: a ? b : c
const Chi = (a, b, c) => (a & b) ^ (~a & c);
// Majority function, true if any two inpust is true
const Maj = (a, b, c) => (a & b) ^ (a & c) ^ (b & c);
// Round constants:
// first 32 bits of the fractional parts of the cube roots of the first 64 primes 2..311)
// prettier-ignore
const SHA256_K = new Uint32Array([
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
]);
// Initial state (first 32 bits of the fractional parts of the square roots of the first 8 primes 2..19):
// prettier-ignore
const IV = new Uint32Array([
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
]);
// Temporary buffer, not used to store anything between runs
// Named this way because it matches specification.
const SHA256_W = new Uint32Array(64);
class SHA256 extends _sha2_js_1.SHA2 {
    constructor() {
        super(64, 32, 8, false);
        // We cannot use array here since array allows indexing by variable
        // which means optimizer/compiler cannot use registers.
        this.A = IV[0] | 0;
        this.B = IV[1] | 0;
        this.C = IV[2] | 0;
        this.D = IV[3] | 0;
        this.E = IV[4] | 0;
        this.F = IV[5] | 0;
        this.G = IV[6] | 0;
        this.H = IV[7] | 0;
    }
    get() {
        const { A, B, C, D, E, F, G, H } = this;
        return [A, B, C, D, E, F, G, H];
    }
    // prettier-ignore
    set(A, B, C, D, E, F, G, H) {
        this.A = A | 0;
        this.B = B | 0;
        this.C = C | 0;
        this.D = D | 0;
        this.E = E | 0;
        this.F = F | 0;
        this.G = G | 0;
        this.H = H | 0;
    }
    process(view, offset) {
        // Extend the first 16 words into the remaining 48 words w[16..63] of the message schedule array
        for (let i = 0; i < 16; i++, offset += 4)
            SHA256_W[i] = view.getUint32(offset, false);
        for (let i = 16; i < 64; i++) {
            const W15 = SHA256_W[i - 15];
            const W2 = SHA256_W[i - 2];
            const s0 = (0, utils_js_1.rotr)(W15, 7) ^ (0, utils_js_1.rotr)(W15, 18) ^ (W15 >>> 3);
            const s1 = (0, utils_js_1.rotr)(W2, 17) ^ (0, utils_js_1.rotr)(W2, 19) ^ (W2 >>> 10);
            SHA256_W[i] = (s1 + SHA256_W[i - 7] + s0 + SHA256_W[i - 16]) | 0;
        }
        // Compression function main loop, 64 rounds
        let { A, B, C, D, E, F, G, H } = this;
        for (let i = 0; i < 64; i++) {
            const sigma1 = (0, utils_js_1.rotr)(E, 6) ^ (0, utils_js_1.rotr)(E, 11) ^ (0, utils_js_1.rotr)(E, 25);
            const T1 = (H + sigma1 + Chi(E, F, G) + SHA256_K[i] + SHA256_W[i]) | 0;
            const sigma0 = (0, utils_js_1.rotr)(A, 2) ^ (0, utils_js_1.rotr)(A, 13) ^ (0, utils_js_1.rotr)(A, 22);
            const T2 = (sigma0 + Maj(A, B, C)) | 0;
            H = G;
            G = F;
            F = E;
            E = (D + T1) | 0;
            D = C;
            C = B;
            B = A;
            A = (T1 + T2) | 0;
        }
        // Add the compressed chunk to the current hash value
        A = (A + this.A) | 0;
        B = (B + this.B) | 0;
        C = (C + this.C) | 0;
        D = (D + this.D) | 0;
        E = (E + this.E) | 0;
        F = (F + this.F) | 0;
        G = (G + this.G) | 0;
        H = (H + this.H) | 0;
        this.set(A, B, C, D, E, F, G, H);
    }
    roundClean() {
        SHA256_W.fill(0);
    }
    destroy() {
        this.set(0, 0, 0, 0, 0, 0, 0, 0);
        this.buffer.fill(0);
    }
}
// Constants from https://nvlpubs.nist.gov/nistpubs/FIPS/NIST.FIPS.180-4.pdf
class SHA224 extends SHA256 {
    constructor() {
        super();
        this.A = 0xc1059ed8 | 0;
        this.B = 0x367cd507 | 0;
        this.C = 0x3070dd17 | 0;
        this.D = 0xf70e5939 | 0;
        this.E = 0xffc00b31 | 0;
        this.F = 0x68581511 | 0;
        this.G = 0x64f98fa7 | 0;
        this.H = 0xbefa4fa4 | 0;
        this.outputLen = 28;
    }
}
/**
 * SHA2-256 hash function
 * @param message - data that would be hashed
 */
exports.sha256 = (0, utils_js_1.wrapConstructor)(() => new SHA256());
exports.sha224 = (0, utils_js_1.wrapConstructor)(() => new SHA224());

},{"./_sha2.js":2,"./utils.js":9}],8:[function(require,module,exports){
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.sha384 = exports.sha512_256 = exports.sha512_224 = exports.sha512 = exports.SHA512 = void 0;
const _sha2_js_1 = require("./_sha2.js");
const _u64_js_1 = require("./_u64.js");
const utils_js_1 = require("./utils.js");
// Round contants (first 32 bits of the fractional parts of the cube roots of the first 80 primes 2..409):
// prettier-ignore
const [SHA512_Kh, SHA512_Kl] = _u64_js_1.default.split([
    '0x428a2f98d728ae22', '0x7137449123ef65cd', '0xb5c0fbcfec4d3b2f', '0xe9b5dba58189dbbc',
    '0x3956c25bf348b538', '0x59f111f1b605d019', '0x923f82a4af194f9b', '0xab1c5ed5da6d8118',
    '0xd807aa98a3030242', '0x12835b0145706fbe', '0x243185be4ee4b28c', '0x550c7dc3d5ffb4e2',
    '0x72be5d74f27b896f', '0x80deb1fe3b1696b1', '0x9bdc06a725c71235', '0xc19bf174cf692694',
    '0xe49b69c19ef14ad2', '0xefbe4786384f25e3', '0x0fc19dc68b8cd5b5', '0x240ca1cc77ac9c65',
    '0x2de92c6f592b0275', '0x4a7484aa6ea6e483', '0x5cb0a9dcbd41fbd4', '0x76f988da831153b5',
    '0x983e5152ee66dfab', '0xa831c66d2db43210', '0xb00327c898fb213f', '0xbf597fc7beef0ee4',
    '0xc6e00bf33da88fc2', '0xd5a79147930aa725', '0x06ca6351e003826f', '0x142929670a0e6e70',
    '0x27b70a8546d22ffc', '0x2e1b21385c26c926', '0x4d2c6dfc5ac42aed', '0x53380d139d95b3df',
    '0x650a73548baf63de', '0x766a0abb3c77b2a8', '0x81c2c92e47edaee6', '0x92722c851482353b',
    '0xa2bfe8a14cf10364', '0xa81a664bbc423001', '0xc24b8b70d0f89791', '0xc76c51a30654be30',
    '0xd192e819d6ef5218', '0xd69906245565a910', '0xf40e35855771202a', '0x106aa07032bbd1b8',
    '0x19a4c116b8d2d0c8', '0x1e376c085141ab53', '0x2748774cdf8eeb99', '0x34b0bcb5e19b48a8',
    '0x391c0cb3c5c95a63', '0x4ed8aa4ae3418acb', '0x5b9cca4f7763e373', '0x682e6ff3d6b2b8a3',
    '0x748f82ee5defb2fc', '0x78a5636f43172f60', '0x84c87814a1f0ab72', '0x8cc702081a6439ec',
    '0x90befffa23631e28', '0xa4506cebde82bde9', '0xbef9a3f7b2c67915', '0xc67178f2e372532b',
    '0xca273eceea26619c', '0xd186b8c721c0c207', '0xeada7dd6cde0eb1e', '0xf57d4f7fee6ed178',
    '0x06f067aa72176fba', '0x0a637dc5a2c898a6', '0x113f9804bef90dae', '0x1b710b35131c471b',
    '0x28db77f523047d84', '0x32caab7b40c72493', '0x3c9ebe0a15c9bebc', '0x431d67c49c100d4c',
    '0x4cc5d4becb3e42b6', '0x597f299cfc657e2a', '0x5fcb6fab3ad6faec', '0x6c44198c4a475817'
].map(n => BigInt(n)));
// Temporary buffer, not used to store anything between runs
const SHA512_W_H = new Uint32Array(80);
const SHA512_W_L = new Uint32Array(80);
class SHA512 extends _sha2_js_1.SHA2 {
    constructor() {
        super(128, 64, 16, false);
        // We cannot use array here since array allows indexing by variable which means optimizer/compiler cannot use registers.
        // Also looks cleaner and easier to verify with spec.
        // Initial state (first 32 bits of the fractional parts of the square roots of the first 8 primes 2..19):
        // h -- high 32 bits, l -- low 32 bits
        this.Ah = 0x6a09e667 | 0;
        this.Al = 0xf3bcc908 | 0;
        this.Bh = 0xbb67ae85 | 0;
        this.Bl = 0x84caa73b | 0;
        this.Ch = 0x3c6ef372 | 0;
        this.Cl = 0xfe94f82b | 0;
        this.Dh = 0xa54ff53a | 0;
        this.Dl = 0x5f1d36f1 | 0;
        this.Eh = 0x510e527f | 0;
        this.El = 0xade682d1 | 0;
        this.Fh = 0x9b05688c | 0;
        this.Fl = 0x2b3e6c1f | 0;
        this.Gh = 0x1f83d9ab | 0;
        this.Gl = 0xfb41bd6b | 0;
        this.Hh = 0x5be0cd19 | 0;
        this.Hl = 0x137e2179 | 0;
    }
    // prettier-ignore
    get() {
        const { Ah, Al, Bh, Bl, Ch, Cl, Dh, Dl, Eh, El, Fh, Fl, Gh, Gl, Hh, Hl } = this;
        return [Ah, Al, Bh, Bl, Ch, Cl, Dh, Dl, Eh, El, Fh, Fl, Gh, Gl, Hh, Hl];
    }
    // prettier-ignore
    set(Ah, Al, Bh, Bl, Ch, Cl, Dh, Dl, Eh, El, Fh, Fl, Gh, Gl, Hh, Hl) {
        this.Ah = Ah | 0;
        this.Al = Al | 0;
        this.Bh = Bh | 0;
        this.Bl = Bl | 0;
        this.Ch = Ch | 0;
        this.Cl = Cl | 0;
        this.Dh = Dh | 0;
        this.Dl = Dl | 0;
        this.Eh = Eh | 0;
        this.El = El | 0;
        this.Fh = Fh | 0;
        this.Fl = Fl | 0;
        this.Gh = Gh | 0;
        this.Gl = Gl | 0;
        this.Hh = Hh | 0;
        this.Hl = Hl | 0;
    }
    process(view, offset) {
        // Extend the first 16 words into the remaining 64 words w[16..79] of the message schedule array
        for (let i = 0; i < 16; i++, offset += 4) {
            SHA512_W_H[i] = view.getUint32(offset);
            SHA512_W_L[i] = view.getUint32((offset += 4));
        }
        for (let i = 16; i < 80; i++) {
            // s0 := (w[i-15] rightrotate 1) xor (w[i-15] rightrotate 8) xor (w[i-15] rightshift 7)
            const W15h = SHA512_W_H[i - 15] | 0;
            const W15l = SHA512_W_L[i - 15] | 0;
            const s0h = _u64_js_1.default.rotrSH(W15h, W15l, 1) ^ _u64_js_1.default.rotrSH(W15h, W15l, 8) ^ _u64_js_1.default.shrSH(W15h, W15l, 7);
            const s0l = _u64_js_1.default.rotrSL(W15h, W15l, 1) ^ _u64_js_1.default.rotrSL(W15h, W15l, 8) ^ _u64_js_1.default.shrSL(W15h, W15l, 7);
            // s1 := (w[i-2] rightrotate 19) xor (w[i-2] rightrotate 61) xor (w[i-2] rightshift 6)
            const W2h = SHA512_W_H[i - 2] | 0;
            const W2l = SHA512_W_L[i - 2] | 0;
            const s1h = _u64_js_1.default.rotrSH(W2h, W2l, 19) ^ _u64_js_1.default.rotrBH(W2h, W2l, 61) ^ _u64_js_1.default.shrSH(W2h, W2l, 6);
            const s1l = _u64_js_1.default.rotrSL(W2h, W2l, 19) ^ _u64_js_1.default.rotrBL(W2h, W2l, 61) ^ _u64_js_1.default.shrSL(W2h, W2l, 6);
            // SHA256_W[i] = s0 + s1 + SHA256_W[i - 7] + SHA256_W[i - 16];
            const SUMl = _u64_js_1.default.add4L(s0l, s1l, SHA512_W_L[i - 7], SHA512_W_L[i - 16]);
            const SUMh = _u64_js_1.default.add4H(SUMl, s0h, s1h, SHA512_W_H[i - 7], SHA512_W_H[i - 16]);
            SHA512_W_H[i] = SUMh | 0;
            SHA512_W_L[i] = SUMl | 0;
        }
        let { Ah, Al, Bh, Bl, Ch, Cl, Dh, Dl, Eh, El, Fh, Fl, Gh, Gl, Hh, Hl } = this;
        // Compression function main loop, 80 rounds
        for (let i = 0; i < 80; i++) {
            // S1 := (e rightrotate 14) xor (e rightrotate 18) xor (e rightrotate 41)
            const sigma1h = _u64_js_1.default.rotrSH(Eh, El, 14) ^ _u64_js_1.default.rotrSH(Eh, El, 18) ^ _u64_js_1.default.rotrBH(Eh, El, 41);
            const sigma1l = _u64_js_1.default.rotrSL(Eh, El, 14) ^ _u64_js_1.default.rotrSL(Eh, El, 18) ^ _u64_js_1.default.rotrBL(Eh, El, 41);
            //const T1 = (H + sigma1 + Chi(E, F, G) + SHA256_K[i] + SHA256_W[i]) | 0;
            const CHIh = (Eh & Fh) ^ (~Eh & Gh);
            const CHIl = (El & Fl) ^ (~El & Gl);
            // T1 = H + sigma1 + Chi(E, F, G) + SHA512_K[i] + SHA512_W[i]
            // prettier-ignore
            const T1ll = _u64_js_1.default.add5L(Hl, sigma1l, CHIl, SHA512_Kl[i], SHA512_W_L[i]);
            const T1h = _u64_js_1.default.add5H(T1ll, Hh, sigma1h, CHIh, SHA512_Kh[i], SHA512_W_H[i]);
            const T1l = T1ll | 0;
            // S0 := (a rightrotate 28) xor (a rightrotate 34) xor (a rightrotate 39)
            const sigma0h = _u64_js_1.default.rotrSH(Ah, Al, 28) ^ _u64_js_1.default.rotrBH(Ah, Al, 34) ^ _u64_js_1.default.rotrBH(Ah, Al, 39);
            const sigma0l = _u64_js_1.default.rotrSL(Ah, Al, 28) ^ _u64_js_1.default.rotrBL(Ah, Al, 34) ^ _u64_js_1.default.rotrBL(Ah, Al, 39);
            const MAJh = (Ah & Bh) ^ (Ah & Ch) ^ (Bh & Ch);
            const MAJl = (Al & Bl) ^ (Al & Cl) ^ (Bl & Cl);
            Hh = Gh | 0;
            Hl = Gl | 0;
            Gh = Fh | 0;
            Gl = Fl | 0;
            Fh = Eh | 0;
            Fl = El | 0;
            ({ h: Eh, l: El } = _u64_js_1.default.add(Dh | 0, Dl | 0, T1h | 0, T1l | 0));
            Dh = Ch | 0;
            Dl = Cl | 0;
            Ch = Bh | 0;
            Cl = Bl | 0;
            Bh = Ah | 0;
            Bl = Al | 0;
            const All = _u64_js_1.default.add3L(T1l, sigma0l, MAJl);
            Ah = _u64_js_1.default.add3H(All, T1h, sigma0h, MAJh);
            Al = All | 0;
        }
        // Add the compressed chunk to the current hash value
        ({ h: Ah, l: Al } = _u64_js_1.default.add(this.Ah | 0, this.Al | 0, Ah | 0, Al | 0));
        ({ h: Bh, l: Bl } = _u64_js_1.default.add(this.Bh | 0, this.Bl | 0, Bh | 0, Bl | 0));
        ({ h: Ch, l: Cl } = _u64_js_1.default.add(this.Ch | 0, this.Cl | 0, Ch | 0, Cl | 0));
        ({ h: Dh, l: Dl } = _u64_js_1.default.add(this.Dh | 0, this.Dl | 0, Dh | 0, Dl | 0));
        ({ h: Eh, l: El } = _u64_js_1.default.add(this.Eh | 0, this.El | 0, Eh | 0, El | 0));
        ({ h: Fh, l: Fl } = _u64_js_1.default.add(this.Fh | 0, this.Fl | 0, Fh | 0, Fl | 0));
        ({ h: Gh, l: Gl } = _u64_js_1.default.add(this.Gh | 0, this.Gl | 0, Gh | 0, Gl | 0));
        ({ h: Hh, l: Hl } = _u64_js_1.default.add(this.Hh | 0, this.Hl | 0, Hh | 0, Hl | 0));
        this.set(Ah, Al, Bh, Bl, Ch, Cl, Dh, Dl, Eh, El, Fh, Fl, Gh, Gl, Hh, Hl);
    }
    roundClean() {
        SHA512_W_H.fill(0);
        SHA512_W_L.fill(0);
    }
    destroy() {
        this.buffer.fill(0);
        this.set(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
    }
}
exports.SHA512 = SHA512;
class SHA512_224 extends SHA512 {
    constructor() {
        super();
        // h -- high 32 bits, l -- low 32 bits
        this.Ah = 0x8c3d37c8 | 0;
        this.Al = 0x19544da2 | 0;
        this.Bh = 0x73e19966 | 0;
        this.Bl = 0x89dcd4d6 | 0;
        this.Ch = 0x1dfab7ae | 0;
        this.Cl = 0x32ff9c82 | 0;
        this.Dh = 0x679dd514 | 0;
        this.Dl = 0x582f9fcf | 0;
        this.Eh = 0x0f6d2b69 | 0;
        this.El = 0x7bd44da8 | 0;
        this.Fh = 0x77e36f73 | 0;
        this.Fl = 0x04c48942 | 0;
        this.Gh = 0x3f9d85a8 | 0;
        this.Gl = 0x6a1d36c8 | 0;
        this.Hh = 0x1112e6ad | 0;
        this.Hl = 0x91d692a1 | 0;
        this.outputLen = 28;
    }
}
class SHA512_256 extends SHA512 {
    constructor() {
        super();
        // h -- high 32 bits, l -- low 32 bits
        this.Ah = 0x22312194 | 0;
        this.Al = 0xfc2bf72c | 0;
        this.Bh = 0x9f555fa3 | 0;
        this.Bl = 0xc84c64c2 | 0;
        this.Ch = 0x2393b86b | 0;
        this.Cl = 0x6f53b151 | 0;
        this.Dh = 0x96387719 | 0;
        this.Dl = 0x5940eabd | 0;
        this.Eh = 0x96283ee2 | 0;
        this.El = 0xa88effe3 | 0;
        this.Fh = 0xbe5e1e25 | 0;
        this.Fl = 0x53863992 | 0;
        this.Gh = 0x2b0199fc | 0;
        this.Gl = 0x2c85b8aa | 0;
        this.Hh = 0x0eb72ddc | 0;
        this.Hl = 0x81c52ca2 | 0;
        this.outputLen = 32;
    }
}
class SHA384 extends SHA512 {
    constructor() {
        super();
        // h -- high 32 bits, l -- low 32 bits
        this.Ah = 0xcbbb9d5d | 0;
        this.Al = 0xc1059ed8 | 0;
        this.Bh = 0x629a292a | 0;
        this.Bl = 0x367cd507 | 0;
        this.Ch = 0x9159015a | 0;
        this.Cl = 0x3070dd17 | 0;
        this.Dh = 0x152fecd8 | 0;
        this.Dl = 0xf70e5939 | 0;
        this.Eh = 0x67332667 | 0;
        this.El = 0xffc00b31 | 0;
        this.Fh = 0x8eb44a87 | 0;
        this.Fl = 0x68581511 | 0;
        this.Gh = 0xdb0c2e0d | 0;
        this.Gl = 0x64f98fa7 | 0;
        this.Hh = 0x47b5481d | 0;
        this.Hl = 0xbefa4fa4 | 0;
        this.outputLen = 48;
    }
}
exports.sha512 = (0, utils_js_1.wrapConstructor)(() => new SHA512());
exports.sha512_224 = (0, utils_js_1.wrapConstructor)(() => new SHA512_224());
exports.sha512_256 = (0, utils_js_1.wrapConstructor)(() => new SHA512_256());
exports.sha384 = (0, utils_js_1.wrapConstructor)(() => new SHA384());

},{"./_sha2.js":2,"./_u64.js":3,"./utils.js":9}],9:[function(require,module,exports){
"use strict";
/*! noble-hashes - MIT License (c) 2022 Paul Miller (paulmillr.com) */

Object.defineProperty(exports, "__esModule", {
  value: true
});
exports.randomBytes = exports.wrapConstructorWithOpts = exports.wrapConstructor = exports.checkOpts = exports.Hash = exports.concatBytes = exports.toBytes = exports.utf8ToBytes = exports.asyncLoop = exports.nextTick = exports.hexToBytes = exports.bytesToHex = exports.isLE = exports.rotr = exports.createView = exports.u32 = exports.u8 = void 0; // The import here is via the package name. This is to ensure
// that exports mapping/resolution does fall into place.

const crypto_1 = require("@noble/hashes/crypto"); // Cast array to different type


const u8 = arr => new Uint8Array(arr.buffer, arr.byteOffset, arr.byteLength);

exports.u8 = u8;

const u32 = arr => new Uint32Array(arr.buffer, arr.byteOffset, Math.floor(arr.byteLength / 4));

exports.u32 = u32; // Cast array to view

const createView = arr => new DataView(arr.buffer, arr.byteOffset, arr.byteLength);

exports.createView = createView; // The rotate right (circular right shift) operation for uint32

const rotr = (word, shift) => word << 32 - shift | word >>> shift;

exports.rotr = rotr;
exports.isLE = new Uint8Array(new Uint32Array([0x11223344]).buffer)[0] === 0x44; // There is almost no big endian hardware, but js typed arrays uses platform specific endianness.
// So, just to be sure not to corrupt anything.

if (!exports.isLE) throw new Error('Non little-endian hardware is not supported');
const hexes = Array.from({
  length: 256
}, (v, i) => i.toString(16).padStart(2, '0'));
/**
 * @example bytesToHex(Uint8Array.from([0xde, 0xad, 0xbe, 0xef]))
 */

function bytesToHex(uint8a) {
  // pre-caching improves the speed 6x
  if (!(uint8a instanceof Uint8Array)) throw new Error('Uint8Array expected');
  let hex = '';

  for (let i = 0; i < uint8a.length; i++) {
    hex += hexes[uint8a[i]];
  }

  return hex;
}

exports.bytesToHex = bytesToHex;
/**
 * @example hexToBytes('deadbeef')
 */

function hexToBytes(hex) {
  if (typeof hex !== 'string') {
    throw new TypeError('hexToBytes: expected string, got ' + typeof hex);
  }

  if (hex.length % 2) throw new Error('hexToBytes: received invalid unpadded hex');
  const array = new Uint8Array(hex.length / 2);

  for (let i = 0; i < array.length; i++) {
    const j = i * 2;
    const hexByte = hex.slice(j, j + 2);
    const byte = Number.parseInt(hexByte, 16);
    if (Number.isNaN(byte) || byte < 0) throw new Error('Invalid byte sequence');
    array[i] = byte;
  }

  return array;
}

exports.hexToBytes = hexToBytes; // There is no setImmediate in browser and setTimeout is slow. However, call to async function will return Promise
// which will be fullfiled only on next scheduler queue processing step and this is exactly what we need.

const nextTick = async () => {};

exports.nextTick = nextTick; // Returns control to thread each 'tick' ms to avoid blocking

async function asyncLoop(iters, tick, cb) {
  let ts = Date.now();

  for (let i = 0; i < iters; i++) {
    cb(i); // Date.now() is not monotonic, so in case if clock goes backwards we return return control too

    const diff = Date.now() - ts;
    if (diff >= 0 && diff < tick) continue;
    await (0, exports.nextTick)();
    ts += diff;
  }
}

exports.asyncLoop = asyncLoop;

function utf8ToBytes(str) {
  if (typeof str !== 'string') {
    throw new TypeError(`utf8ToBytes expected string, got ${typeof str}`);
  }

  return new TextEncoder().encode(str);
}

exports.utf8ToBytes = utf8ToBytes;

function toBytes(data) {
  if (typeof data === 'string') data = utf8ToBytes(data);
  if (!(data instanceof Uint8Array)) throw new TypeError(`Expected input type is Uint8Array (got ${typeof data})`);
  return data;
}

exports.toBytes = toBytes;
/**
 * Concats Uint8Array-s into one; like `Buffer.concat([buf1, buf2])`
 * @example concatBytes(buf1, buf2)
 */

function concatBytes(...arrays) {
  if (!arrays.every(a => a instanceof Uint8Array)) throw new Error('Uint8Array list expected');
  if (arrays.length === 1) return arrays[0];
  const length = arrays.reduce((a, arr) => a + arr.length, 0);
  const result = new Uint8Array(length);

  for (let i = 0, pad = 0; i < arrays.length; i++) {
    const arr = arrays[i];
    result.set(arr, pad);
    pad += arr.length;
  }

  return result;
}

exports.concatBytes = concatBytes; // For runtime check if class implements interface

class Hash {
  // Safe version that clones internal state
  clone() {
    return this._cloneInto();
  }

}

exports.Hash = Hash; // Check if object doens't have custom constructor (like Uint8Array/Array)

const isPlainObject = obj => Object.prototype.toString.call(obj) === '[object Object]' && obj.constructor === Object;

function checkOpts(defaults, opts) {
  if (opts !== undefined && (typeof opts !== 'object' || !isPlainObject(opts))) throw new TypeError('Options should be object or undefined');
  const merged = Object.assign(defaults, opts);
  return merged;
}

exports.checkOpts = checkOpts;

function wrapConstructor(hashConstructor) {
  const hashC = message => hashConstructor().update(toBytes(message)).digest();

  const tmp = hashConstructor();
  hashC.outputLen = tmp.outputLen;
  hashC.blockLen = tmp.blockLen;

  hashC.create = () => hashConstructor();

  return hashC;
}

exports.wrapConstructor = wrapConstructor;

function wrapConstructorWithOpts(hashCons) {
  const hashC = (msg, opts) => hashCons(opts).update(toBytes(msg)).digest();

  const tmp = hashCons({});
  hashC.outputLen = tmp.outputLen;
  hashC.blockLen = tmp.blockLen;

  hashC.create = opts => hashCons(opts);

  return hashC;
}

exports.wrapConstructorWithOpts = wrapConstructorWithOpts;
/**
 * Secure PRNG
 */

function randomBytes(bytesLength = 32) {
  if (crypto_1.crypto.web) {
    return crypto_1.crypto.web.getRandomValues(new Uint8Array(bytesLength));
  } else if (crypto_1.crypto.node) {
    return new Uint8Array(crypto_1.crypto.node.randomBytes(bytesLength).buffer);
  } else {
    throw new Error("The environment doesn't have randomBytes function");
  }
}

exports.randomBytes = randomBytes;

},{"@noble/hashes/crypto":4}],10:[function(require,module,exports){
"use strict";
/*! noble-secp256k1 - MIT License (c) 2019 Paul Miller (paulmillr.com) */
Object.defineProperty(exports, "__esModule", { value: true });
exports.utils = exports.schnorr = exports.verify = exports.signSync = exports.sign = exports.getSharedSecret = exports.recoverPublicKey = exports.getPublicKey = exports.Signature = exports.Point = exports.CURVE = void 0;
const nodeCrypto = require("crypto");
const _0n = BigInt(0);
const _1n = BigInt(1);
const _2n = BigInt(2);
const _3n = BigInt(3);
const _8n = BigInt(8);
const CURVE = Object.freeze({
    a: _0n,
    b: BigInt(7),
    P: BigInt('0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffefffffc2f'),
    n: BigInt('0xfffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141'),
    h: _1n,
    Gx: BigInt('55066263022277343669578718895168534326250603453777594175500187360389116729240'),
    Gy: BigInt('32670510020758816978083085130507043184471273380659243275938904335757337482424'),
    beta: BigInt('0x7ae96a2b657c07106e64479eac3434e99cf0497512f58995c1396c28719501ee'),
});
exports.CURVE = CURVE;
const divNearest = (a, b) => (a + b / _2n) / b;
const endo = {
    beta: BigInt('0x7ae96a2b657c07106e64479eac3434e99cf0497512f58995c1396c28719501ee'),
    splitScalar(k) {
        const { n } = CURVE;
        const a1 = BigInt('0x3086d221a7d46bcde86c90e49284eb15');
        const b1 = -_1n * BigInt('0xe4437ed6010e88286f547fa90abfe4c3');
        const a2 = BigInt('0x114ca50f7a8e2f3f657c1108d9d44cfd8');
        const b2 = a1;
        const POW_2_128 = BigInt('0x100000000000000000000000000000000');
        const c1 = divNearest(b2 * k, n);
        const c2 = divNearest(-b1 * k, n);
        let k1 = mod(k - c1 * a1 - c2 * a2, n);
        let k2 = mod(-c1 * b1 - c2 * b2, n);
        const k1neg = k1 > POW_2_128;
        const k2neg = k2 > POW_2_128;
        if (k1neg)
            k1 = n - k1;
        if (k2neg)
            k2 = n - k2;
        if (k1 > POW_2_128 || k2 > POW_2_128) {
            throw new Error('splitScalarEndo: Endomorphism failed, k=' + k);
        }
        return { k1neg, k1, k2neg, k2 };
    },
};
const fieldLen = 32;
const groupLen = 32;
const hashLen = 32;
const compressedLen = fieldLen + 1;
const uncompressedLen = 2 * fieldLen + 1;
function weierstrass(x) {
    const { a, b } = CURVE;
    const x2 = mod(x * x);
    const x3 = mod(x2 * x);
    return mod(x3 + a * x + b);
}
const USE_ENDOMORPHISM = CURVE.a === _0n;
class ShaError extends Error {
    constructor(message) {
        super(message);
    }
}
function assertJacPoint(other) {
    if (!(other instanceof JacobianPoint))
        throw new TypeError('JacobianPoint expected');
}
class JacobianPoint {
    constructor(x, y, z) {
        this.x = x;
        this.y = y;
        this.z = z;
    }
    static fromAffine(p) {
        if (!(p instanceof Point)) {
            throw new TypeError('JacobianPoint#fromAffine: expected Point');
        }
        if (p.equals(Point.ZERO))
            return JacobianPoint.ZERO;
        return new JacobianPoint(p.x, p.y, _1n);
    }
    static toAffineBatch(points) {
        const toInv = invertBatch(points.map((p) => p.z));
        return points.map((p, i) => p.toAffine(toInv[i]));
    }
    static normalizeZ(points) {
        return JacobianPoint.toAffineBatch(points).map(JacobianPoint.fromAffine);
    }
    equals(other) {
        assertJacPoint(other);
        const { x: X1, y: Y1, z: Z1 } = this;
        const { x: X2, y: Y2, z: Z2 } = other;
        const Z1Z1 = mod(Z1 * Z1);
        const Z2Z2 = mod(Z2 * Z2);
        const U1 = mod(X1 * Z2Z2);
        const U2 = mod(X2 * Z1Z1);
        const S1 = mod(mod(Y1 * Z2) * Z2Z2);
        const S2 = mod(mod(Y2 * Z1) * Z1Z1);
        return U1 === U2 && S1 === S2;
    }
    negate() {
        return new JacobianPoint(this.x, mod(-this.y), this.z);
    }
    double() {
        const { x: X1, y: Y1, z: Z1 } = this;
        const A = mod(X1 * X1);
        const B = mod(Y1 * Y1);
        const C = mod(B * B);
        const x1b = X1 + B;
        const D = mod(_2n * (mod(x1b * x1b) - A - C));
        const E = mod(_3n * A);
        const F = mod(E * E);
        const X3 = mod(F - _2n * D);
        const Y3 = mod(E * (D - X3) - _8n * C);
        const Z3 = mod(_2n * Y1 * Z1);
        return new JacobianPoint(X3, Y3, Z3);
    }
    add(other) {
        assertJacPoint(other);
        const { x: X1, y: Y1, z: Z1 } = this;
        const { x: X2, y: Y2, z: Z2 } = other;
        if (X2 === _0n || Y2 === _0n)
            return this;
        if (X1 === _0n || Y1 === _0n)
            return other;
        const Z1Z1 = mod(Z1 * Z1);
        const Z2Z2 = mod(Z2 * Z2);
        const U1 = mod(X1 * Z2Z2);
        const U2 = mod(X2 * Z1Z1);
        const S1 = mod(mod(Y1 * Z2) * Z2Z2);
        const S2 = mod(mod(Y2 * Z1) * Z1Z1);
        const H = mod(U2 - U1);
        const r = mod(S2 - S1);
        if (H === _0n) {
            if (r === _0n) {
                return this.double();
            }
            else {
                return JacobianPoint.ZERO;
            }
        }
        const HH = mod(H * H);
        const HHH = mod(H * HH);
        const V = mod(U1 * HH);
        const X3 = mod(r * r - HHH - _2n * V);
        const Y3 = mod(r * (V - X3) - S1 * HHH);
        const Z3 = mod(Z1 * Z2 * H);
        return new JacobianPoint(X3, Y3, Z3);
    }
    subtract(other) {
        return this.add(other.negate());
    }
    multiplyUnsafe(scalar) {
        const P0 = JacobianPoint.ZERO;
        if (typeof scalar === 'bigint' && scalar === _0n)
            return P0;
        let n = normalizeScalar(scalar);
        if (n === _1n)
            return this;
        if (!USE_ENDOMORPHISM) {
            let p = P0;
            let d = this;
            while (n > _0n) {
                if (n & _1n)
                    p = p.add(d);
                d = d.double();
                n >>= _1n;
            }
            return p;
        }
        let { k1neg, k1, k2neg, k2 } = endo.splitScalar(n);
        let k1p = P0;
        let k2p = P0;
        let d = this;
        while (k1 > _0n || k2 > _0n) {
            if (k1 & _1n)
                k1p = k1p.add(d);
            if (k2 & _1n)
                k2p = k2p.add(d);
            d = d.double();
            k1 >>= _1n;
            k2 >>= _1n;
        }
        if (k1neg)
            k1p = k1p.negate();
        if (k2neg)
            k2p = k2p.negate();
        k2p = new JacobianPoint(mod(k2p.x * endo.beta), k2p.y, k2p.z);
        return k1p.add(k2p);
    }
    precomputeWindow(W) {
        const windows = USE_ENDOMORPHISM ? 128 / W + 1 : 256 / W + 1;
        const points = [];
        let p = this;
        let base = p;
        for (let window = 0; window < windows; window++) {
            base = p;
            points.push(base);
            for (let i = 1; i < 2 ** (W - 1); i++) {
                base = base.add(p);
                points.push(base);
            }
            p = base.double();
        }
        return points;
    }
    wNAF(n, affinePoint) {
        if (!affinePoint && this.equals(JacobianPoint.BASE))
            affinePoint = Point.BASE;
        const W = (affinePoint && affinePoint._WINDOW_SIZE) || 1;
        if (256 % W) {
            throw new Error('Point#wNAF: Invalid precomputation window, must be power of 2');
        }
        let precomputes = affinePoint && pointPrecomputes.get(affinePoint);
        if (!precomputes) {
            precomputes = this.precomputeWindow(W);
            if (affinePoint && W !== 1) {
                precomputes = JacobianPoint.normalizeZ(precomputes);
                pointPrecomputes.set(affinePoint, precomputes);
            }
        }
        let p = JacobianPoint.ZERO;
        let f = JacobianPoint.BASE;
        const windows = 1 + (USE_ENDOMORPHISM ? 128 / W : 256 / W);
        const windowSize = 2 ** (W - 1);
        const mask = BigInt(2 ** W - 1);
        const maxNumber = 2 ** W;
        const shiftBy = BigInt(W);
        for (let window = 0; window < windows; window++) {
            const offset = window * windowSize;
            let wbits = Number(n & mask);
            n >>= shiftBy;
            if (wbits > windowSize) {
                wbits -= maxNumber;
                n += _1n;
            }
            const offset1 = offset;
            const offset2 = offset + Math.abs(wbits) - 1;
            const cond1 = window % 2 !== 0;
            const cond2 = wbits < 0;
            if (wbits === 0) {
                f = f.add(constTimeNegate(cond1, precomputes[offset1]));
            }
            else {
                p = p.add(constTimeNegate(cond2, precomputes[offset2]));
            }
        }
        return { p, f };
    }
    multiply(scalar, affinePoint) {
        let n = normalizeScalar(scalar);
        let point;
        let fake;
        if (USE_ENDOMORPHISM) {
            const { k1neg, k1, k2neg, k2 } = endo.splitScalar(n);
            let { p: k1p, f: f1p } = this.wNAF(k1, affinePoint);
            let { p: k2p, f: f2p } = this.wNAF(k2, affinePoint);
            k1p = constTimeNegate(k1neg, k1p);
            k2p = constTimeNegate(k2neg, k2p);
            k2p = new JacobianPoint(mod(k2p.x * endo.beta), k2p.y, k2p.z);
            point = k1p.add(k2p);
            fake = f1p.add(f2p);
        }
        else {
            const { p, f } = this.wNAF(n, affinePoint);
            point = p;
            fake = f;
        }
        return JacobianPoint.normalizeZ([point, fake])[0];
    }
    toAffine(invZ) {
        const { x, y, z } = this;
        const is0 = this.equals(JacobianPoint.ZERO);
        if (invZ == null)
            invZ = is0 ? _8n : invert(z);
        const iz1 = invZ;
        const iz2 = mod(iz1 * iz1);
        const iz3 = mod(iz2 * iz1);
        const ax = mod(x * iz2);
        const ay = mod(y * iz3);
        const zz = mod(z * iz1);
        if (is0)
            return Point.ZERO;
        if (zz !== _1n)
            throw new Error('invZ was invalid');
        return new Point(ax, ay);
    }
}
JacobianPoint.BASE = new JacobianPoint(CURVE.Gx, CURVE.Gy, _1n);
JacobianPoint.ZERO = new JacobianPoint(_0n, _1n, _0n);
function constTimeNegate(condition, item) {
    const neg = item.negate();
    return condition ? neg : item;
}
const pointPrecomputes = new WeakMap();
class Point {
    constructor(x, y) {
        this.x = x;
        this.y = y;
    }
    _setWindowSize(windowSize) {
        this._WINDOW_SIZE = windowSize;
        pointPrecomputes.delete(this);
    }
    hasEvenY() {
        return this.y % _2n === _0n;
    }
    static fromCompressedHex(bytes) {
        const isShort = bytes.length === 32;
        const x = bytesToNumber(isShort ? bytes : bytes.subarray(1));
        if (!isValidFieldElement(x))
            throw new Error('Point is not on curve');
        const y2 = weierstrass(x);
        let y = sqrtMod(y2);
        const isYOdd = (y & _1n) === _1n;
        if (isShort) {
            if (isYOdd)
                y = mod(-y);
        }
        else {
            const isFirstByteOdd = (bytes[0] & 1) === 1;
            if (isFirstByteOdd !== isYOdd)
                y = mod(-y);
        }
        const point = new Point(x, y);
        point.assertValidity();
        return point;
    }
    static fromUncompressedHex(bytes) {
        const x = bytesToNumber(bytes.subarray(1, fieldLen + 1));
        const y = bytesToNumber(bytes.subarray(fieldLen + 1, fieldLen * 2 + 1));
        const point = new Point(x, y);
        point.assertValidity();
        return point;
    }
    static fromHex(hex) {
        const bytes = ensureBytes(hex);
        const len = bytes.length;
        const header = bytes[0];
        if (len === fieldLen)
            return this.fromCompressedHex(bytes);
        if (len === compressedLen && (header === 0x02 || header === 0x03)) {
            return this.fromCompressedHex(bytes);
        }
        if (len === uncompressedLen && header === 0x04)
            return this.fromUncompressedHex(bytes);
        throw new Error(`Point.fromHex: received invalid point. Expected 32-${compressedLen} compressed bytes or ${uncompressedLen} uncompressed bytes, not ${len}`);
    }
    static fromPrivateKey(privateKey) {
        return Point.BASE.multiply(normalizePrivateKey(privateKey));
    }
    static fromSignature(msgHash, signature, recovery) {
        const { r, s } = normalizeSignature(signature);
        if (![0, 1, 2, 3].includes(recovery))
            throw new Error('Cannot recover: invalid recovery bit');
        const h = truncateHash(ensureBytes(msgHash));
        const { n } = CURVE;
        const radj = recovery === 2 || recovery === 3 ? r + n : r;
        const rinv = invert(radj, n);
        const u1 = mod(-h * rinv, n);
        const u2 = mod(s * rinv, n);
        const prefix = recovery & 1 ? '03' : '02';
        const R = Point.fromHex(prefix + numTo32bStr(radj));
        const Q = Point.BASE.multiplyAndAddUnsafe(R, u1, u2);
        if (!Q)
            throw new Error('Cannot recover signature: point at infinify');
        Q.assertValidity();
        return Q;
    }
    toRawBytes(isCompressed = false) {
        return hexToBytes(this.toHex(isCompressed));
    }
    toHex(isCompressed = false) {
        const x = numTo32bStr(this.x);
        if (isCompressed) {
            const prefix = this.hasEvenY() ? '02' : '03';
            return `${prefix}${x}`;
        }
        else {
            return `04${x}${numTo32bStr(this.y)}`;
        }
    }
    toHexX() {
        return this.toHex(true).slice(2);
    }
    toRawX() {
        return this.toRawBytes(true).slice(1);
    }
    assertValidity() {
        const msg = 'Point is not on elliptic curve';
        const { x, y } = this;
        if (!isValidFieldElement(x) || !isValidFieldElement(y))
            throw new Error(msg);
        const left = mod(y * y);
        const right = weierstrass(x);
        if (mod(left - right) !== _0n)
            throw new Error(msg);
    }
    equals(other) {
        return this.x === other.x && this.y === other.y;
    }
    negate() {
        return new Point(this.x, mod(-this.y));
    }
    double() {
        return JacobianPoint.fromAffine(this).double().toAffine();
    }
    add(other) {
        return JacobianPoint.fromAffine(this).add(JacobianPoint.fromAffine(other)).toAffine();
    }
    subtract(other) {
        return this.add(other.negate());
    }
    multiply(scalar) {
        return JacobianPoint.fromAffine(this).multiply(scalar, this).toAffine();
    }
    multiplyAndAddUnsafe(Q, a, b) {
        const P = JacobianPoint.fromAffine(this);
        const aP = a === _0n || a === _1n || this !== Point.BASE ? P.multiplyUnsafe(a) : P.multiply(a);
        const bQ = JacobianPoint.fromAffine(Q).multiplyUnsafe(b);
        const sum = aP.add(bQ);
        return sum.equals(JacobianPoint.ZERO) ? undefined : sum.toAffine();
    }
}
exports.Point = Point;
Point.BASE = new Point(CURVE.Gx, CURVE.Gy);
Point.ZERO = new Point(_0n, _0n);
function sliceDER(s) {
    return Number.parseInt(s[0], 16) >= 8 ? '00' + s : s;
}
function parseDERInt(data) {
    if (data.length < 2 || data[0] !== 0x02) {
        throw new Error(`Invalid signature integer tag: ${bytesToHex(data)}`);
    }
    const len = data[1];
    const res = data.subarray(2, len + 2);
    if (!len || res.length !== len) {
        throw new Error(`Invalid signature integer: wrong length`);
    }
    if (res[0] === 0x00 && res[1] <= 0x7f) {
        throw new Error('Invalid signature integer: trailing length');
    }
    return { data: bytesToNumber(res), left: data.subarray(len + 2) };
}
function parseDERSignature(data) {
    if (data.length < 2 || data[0] != 0x30) {
        throw new Error(`Invalid signature tag: ${bytesToHex(data)}`);
    }
    if (data[1] !== data.length - 2) {
        throw new Error('Invalid signature: incorrect length');
    }
    const { data: r, left: sBytes } = parseDERInt(data.subarray(2));
    const { data: s, left: rBytesLeft } = parseDERInt(sBytes);
    if (rBytesLeft.length) {
        throw new Error(`Invalid signature: left bytes after parsing: ${bytesToHex(rBytesLeft)}`);
    }
    return { r, s };
}
class Signature {
    constructor(r, s) {
        this.r = r;
        this.s = s;
        this.assertValidity();
    }
    static fromCompact(hex) {
        const arr = hex instanceof Uint8Array;
        const name = 'Signature.fromCompact';
        if (typeof hex !== 'string' && !arr)
            throw new TypeError(`${name}: Expected string or Uint8Array`);
        const str = arr ? bytesToHex(hex) : hex;
        if (str.length !== 128)
            throw new Error(`${name}: Expected 64-byte hex`);
        return new Signature(hexToNumber(str.slice(0, 64)), hexToNumber(str.slice(64, 128)));
    }
    static fromDER(hex) {
        const arr = hex instanceof Uint8Array;
        if (typeof hex !== 'string' && !arr)
            throw new TypeError(`Signature.fromDER: Expected string or Uint8Array`);
        const { r, s } = parseDERSignature(arr ? hex : hexToBytes(hex));
        return new Signature(r, s);
    }
    static fromHex(hex) {
        return this.fromDER(hex);
    }
    assertValidity() {
        const { r, s } = this;
        if (!isWithinCurveOrder(r))
            throw new Error('Invalid Signature: r must be 0 < r < n');
        if (!isWithinCurveOrder(s))
            throw new Error('Invalid Signature: s must be 0 < s < n');
    }
    hasHighS() {
        const HALF = CURVE.n >> _1n;
        return this.s > HALF;
    }
    normalizeS() {
        return this.hasHighS() ? new Signature(this.r, mod(-this.s, CURVE.n)) : this;
    }
    toDERRawBytes() {
        return hexToBytes(this.toDERHex());
    }
    toDERHex() {
        const sHex = sliceDER(numberToHexUnpadded(this.s));
        const rHex = sliceDER(numberToHexUnpadded(this.r));
        const sHexL = sHex.length / 2;
        const rHexL = rHex.length / 2;
        const sLen = numberToHexUnpadded(sHexL);
        const rLen = numberToHexUnpadded(rHexL);
        const length = numberToHexUnpadded(rHexL + sHexL + 4);
        return `30${length}02${rLen}${rHex}02${sLen}${sHex}`;
    }
    toRawBytes() {
        return this.toDERRawBytes();
    }
    toHex() {
        return this.toDERHex();
    }
    toCompactRawBytes() {
        return hexToBytes(this.toCompactHex());
    }
    toCompactHex() {
        return numTo32bStr(this.r) + numTo32bStr(this.s);
    }
}
exports.Signature = Signature;
function concatBytes(...arrays) {
    if (!arrays.every((b) => b instanceof Uint8Array))
        throw new Error('Uint8Array list expected');
    if (arrays.length === 1)
        return arrays[0];
    const length = arrays.reduce((a, arr) => a + arr.length, 0);
    const result = new Uint8Array(length);
    for (let i = 0, pad = 0; i < arrays.length; i++) {
        const arr = arrays[i];
        result.set(arr, pad);
        pad += arr.length;
    }
    return result;
}
const hexes = Array.from({ length: 256 }, (v, i) => i.toString(16).padStart(2, '0'));
function bytesToHex(uint8a) {
    if (!(uint8a instanceof Uint8Array))
        throw new Error('Expected Uint8Array');
    let hex = '';
    for (let i = 0; i < uint8a.length; i++) {
        hex += hexes[uint8a[i]];
    }
    return hex;
}
const POW_2_256 = BigInt('0x10000000000000000000000000000000000000000000000000000000000000000');
function numTo32bStr(num) {
    if (typeof num !== 'bigint')
        throw new Error('Expected bigint');
    if (!(_0n <= num && num < POW_2_256))
        throw new Error('Expected number 0 <= n < 2^256');
    return num.toString(16).padStart(64, '0');
}
function numTo32b(num) {
    const b = hexToBytes(numTo32bStr(num));
    if (b.length !== 32)
        throw new Error('Error: expected 32 bytes');
    return b;
}
function numberToHexUnpadded(num) {
    const hex = num.toString(16);
    return hex.length & 1 ? `0${hex}` : hex;
}
function hexToNumber(hex) {
    if (typeof hex !== 'string') {
        throw new TypeError('hexToNumber: expected string, got ' + typeof hex);
    }
    return BigInt(`0x${hex}`);
}
function hexToBytes(hex) {
    if (typeof hex !== 'string') {
        throw new TypeError('hexToBytes: expected string, got ' + typeof hex);
    }
    if (hex.length % 2)
        throw new Error('hexToBytes: received invalid unpadded hex' + hex.length);
    const array = new Uint8Array(hex.length / 2);
    for (let i = 0; i < array.length; i++) {
        const j = i * 2;
        const hexByte = hex.slice(j, j + 2);
        const byte = Number.parseInt(hexByte, 16);
        if (Number.isNaN(byte) || byte < 0)
            throw new Error('Invalid byte sequence');
        array[i] = byte;
    }
    return array;
}
function bytesToNumber(bytes) {
    return hexToNumber(bytesToHex(bytes));
}
function ensureBytes(hex) {
    return hex instanceof Uint8Array ? Uint8Array.from(hex) : hexToBytes(hex);
}
function normalizeScalar(num) {
    if (typeof num === 'number' && Number.isSafeInteger(num) && num > 0)
        return BigInt(num);
    if (typeof num === 'bigint' && isWithinCurveOrder(num))
        return num;
    throw new TypeError('Expected valid private scalar: 0 < scalar < curve.n');
}
function mod(a, b = CURVE.P) {
    const result = a % b;
    return result >= _0n ? result : b + result;
}
function pow2(x, power) {
    const { P } = CURVE;
    let res = x;
    while (power-- > _0n) {
        res *= res;
        res %= P;
    }
    return res;
}
function sqrtMod(x) {
    const { P } = CURVE;
    const _6n = BigInt(6);
    const _11n = BigInt(11);
    const _22n = BigInt(22);
    const _23n = BigInt(23);
    const _44n = BigInt(44);
    const _88n = BigInt(88);
    const b2 = (x * x * x) % P;
    const b3 = (b2 * b2 * x) % P;
    const b6 = (pow2(b3, _3n) * b3) % P;
    const b9 = (pow2(b6, _3n) * b3) % P;
    const b11 = (pow2(b9, _2n) * b2) % P;
    const b22 = (pow2(b11, _11n) * b11) % P;
    const b44 = (pow2(b22, _22n) * b22) % P;
    const b88 = (pow2(b44, _44n) * b44) % P;
    const b176 = (pow2(b88, _88n) * b88) % P;
    const b220 = (pow2(b176, _44n) * b44) % P;
    const b223 = (pow2(b220, _3n) * b3) % P;
    const t1 = (pow2(b223, _23n) * b22) % P;
    const t2 = (pow2(t1, _6n) * b2) % P;
    const rt = pow2(t2, _2n);
    const xc = (rt * rt) % P;
    if (xc !== x)
        throw new Error('Cannot find square root');
    return rt;
}
function invert(number, modulo = CURVE.P) {
    if (number === _0n || modulo <= _0n) {
        throw new Error(`invert: expected positive integers, got n=${number} mod=${modulo}`);
    }
    let a = mod(number, modulo);
    let b = modulo;
    let x = _0n, y = _1n, u = _1n, v = _0n;
    while (a !== _0n) {
        const q = b / a;
        const r = b % a;
        const m = x - u * q;
        const n = y - v * q;
        b = a, a = r, x = u, y = v, u = m, v = n;
    }
    const gcd = b;
    if (gcd !== _1n)
        throw new Error('invert: does not exist');
    return mod(x, modulo);
}
function invertBatch(nums, p = CURVE.P) {
    const scratch = new Array(nums.length);
    const lastMultiplied = nums.reduce((acc, num, i) => {
        if (num === _0n)
            return acc;
        scratch[i] = acc;
        return mod(acc * num, p);
    }, _1n);
    const inverted = invert(lastMultiplied, p);
    nums.reduceRight((acc, num, i) => {
        if (num === _0n)
            return acc;
        scratch[i] = mod(acc * scratch[i], p);
        return mod(acc * num, p);
    }, inverted);
    return scratch;
}
function bits2int_2(bytes) {
    const delta = bytes.length * 8 - groupLen * 8;
    const num = bytesToNumber(bytes);
    return delta > 0 ? num >> BigInt(delta) : num;
}
function truncateHash(hash, truncateOnly = false) {
    const h = bits2int_2(hash);
    if (truncateOnly)
        return h;
    const { n } = CURVE;
    return h >= n ? h - n : h;
}
let _sha256Sync;
let _hmacSha256Sync;
class HmacDrbg {
    constructor(hashLen, qByteLen) {
        this.hashLen = hashLen;
        this.qByteLen = qByteLen;
        if (typeof hashLen !== 'number' || hashLen < 2)
            throw new Error('hashLen must be a number');
        if (typeof qByteLen !== 'number' || qByteLen < 2)
            throw new Error('qByteLen must be a number');
        this.v = new Uint8Array(hashLen).fill(1);
        this.k = new Uint8Array(hashLen).fill(0);
        this.counter = 0;
    }
    hmac(...values) {
        return exports.utils.hmacSha256(this.k, ...values);
    }
    hmacSync(...values) {
        return _hmacSha256Sync(this.k, ...values);
    }
    checkSync() {
        if (typeof _hmacSha256Sync !== 'function')
            throw new ShaError('hmacSha256Sync needs to be set');
    }
    incr() {
        if (this.counter >= 1000)
            throw new Error('Tried 1,000 k values for sign(), all were invalid');
        this.counter += 1;
    }
    async reseed(seed = new Uint8Array()) {
        this.k = await this.hmac(this.v, Uint8Array.from([0x00]), seed);
        this.v = await this.hmac(this.v);
        if (seed.length === 0)
            return;
        this.k = await this.hmac(this.v, Uint8Array.from([0x01]), seed);
        this.v = await this.hmac(this.v);
    }
    reseedSync(seed = new Uint8Array()) {
        this.checkSync();
        this.k = this.hmacSync(this.v, Uint8Array.from([0x00]), seed);
        this.v = this.hmacSync(this.v);
        if (seed.length === 0)
            return;
        this.k = this.hmacSync(this.v, Uint8Array.from([0x01]), seed);
        this.v = this.hmacSync(this.v);
    }
    async generate() {
        this.incr();
        let len = 0;
        const out = [];
        while (len < this.qByteLen) {
            this.v = await this.hmac(this.v);
            const sl = this.v.slice();
            out.push(sl);
            len += this.v.length;
        }
        return concatBytes(...out);
    }
    generateSync() {
        this.checkSync();
        this.incr();
        let len = 0;
        const out = [];
        while (len < this.qByteLen) {
            this.v = this.hmacSync(this.v);
            const sl = this.v.slice();
            out.push(sl);
            len += this.v.length;
        }
        return concatBytes(...out);
    }
}
function isWithinCurveOrder(num) {
    return _0n < num && num < CURVE.n;
}
function isValidFieldElement(num) {
    return _0n < num && num < CURVE.P;
}
function kmdToSig(kBytes, m, d, lowS = true) {
    const { n } = CURVE;
    const k = truncateHash(kBytes, true);
    if (!isWithinCurveOrder(k))
        return;
    const kinv = invert(k, n);
    const q = Point.BASE.multiply(k);
    const r = mod(q.x, n);
    if (r === _0n)
        return;
    const s = mod(kinv * mod(m + d * r, n), n);
    if (s === _0n)
        return;
    let sig = new Signature(r, s);
    let recovery = (q.x === sig.r ? 0 : 2) | Number(q.y & _1n);
    if (lowS && sig.hasHighS()) {
        sig = sig.normalizeS();
        recovery ^= 1;
    }
    return { sig, recovery };
}
function normalizePrivateKey(key) {
    let num;
    if (typeof key === 'bigint') {
        num = key;
    }
    else if (typeof key === 'number' && Number.isSafeInteger(key) && key > 0) {
        num = BigInt(key);
    }
    else if (typeof key === 'string') {
        if (key.length !== 2 * groupLen)
            throw new Error('Expected 32 bytes of private key');
        num = hexToNumber(key);
    }
    else if (key instanceof Uint8Array) {
        if (key.length !== groupLen)
            throw new Error('Expected 32 bytes of private key');
        num = bytesToNumber(key);
    }
    else {
        throw new TypeError('Expected valid private key');
    }
    if (!isWithinCurveOrder(num))
        throw new Error('Expected private key: 0 < key < n');
    return num;
}
function normalizePublicKey(publicKey) {
    if (publicKey instanceof Point) {
        publicKey.assertValidity();
        return publicKey;
    }
    else {
        return Point.fromHex(publicKey);
    }
}
function normalizeSignature(signature) {
    if (signature instanceof Signature) {
        signature.assertValidity();
        return signature;
    }
    try {
        return Signature.fromDER(signature);
    }
    catch (error) {
        return Signature.fromCompact(signature);
    }
}
function getPublicKey(privateKey, isCompressed = false) {
    return Point.fromPrivateKey(privateKey).toRawBytes(isCompressed);
}
exports.getPublicKey = getPublicKey;
function recoverPublicKey(msgHash, signature, recovery, isCompressed = false) {
    return Point.fromSignature(msgHash, signature, recovery).toRawBytes(isCompressed);
}
exports.recoverPublicKey = recoverPublicKey;
function isProbPub(item) {
    const arr = item instanceof Uint8Array;
    const str = typeof item === 'string';
    const len = (arr || str) && item.length;
    if (arr)
        return len === compressedLen || len === uncompressedLen;
    if (str)
        return len === compressedLen * 2 || len === uncompressedLen * 2;
    if (item instanceof Point)
        return true;
    return false;
}
function getSharedSecret(privateA, publicB, isCompressed = false) {
    if (isProbPub(privateA))
        throw new TypeError('getSharedSecret: first arg must be private key');
    if (!isProbPub(publicB))
        throw new TypeError('getSharedSecret: second arg must be public key');
    const b = normalizePublicKey(publicB);
    b.assertValidity();
    return b.multiply(normalizePrivateKey(privateA)).toRawBytes(isCompressed);
}
exports.getSharedSecret = getSharedSecret;
function bits2int(bytes) {
    const slice = bytes.length > fieldLen ? bytes.slice(0, fieldLen) : bytes;
    return bytesToNumber(slice);
}
function bits2octets(bytes) {
    const z1 = bits2int(bytes);
    const z2 = mod(z1, CURVE.n);
    return int2octets(z2 < _0n ? z1 : z2);
}
function int2octets(num) {
    return numTo32b(num);
}
function initSigArgs(msgHash, privateKey, extraEntropy) {
    if (msgHash == null)
        throw new Error(`sign: expected valid message hash, not "${msgHash}"`);
    const h1 = ensureBytes(msgHash);
    const d = normalizePrivateKey(privateKey);
    const seedArgs = [int2octets(d), bits2octets(h1)];
    if (extraEntropy != null) {
        if (extraEntropy === true)
            extraEntropy = exports.utils.randomBytes(fieldLen);
        const e = ensureBytes(extraEntropy);
        if (e.length !== fieldLen)
            throw new Error(`sign: Expected ${fieldLen} bytes of extra data`);
        seedArgs.push(e);
    }
    const seed = concatBytes(...seedArgs);
    const m = bits2int(h1);
    return { seed, m, d };
}
function finalizeSig(recSig, opts) {
    const { sig, recovery } = recSig;
    const { der, recovered } = Object.assign({ canonical: true, der: true }, opts);
    const hashed = der ? sig.toDERRawBytes() : sig.toCompactRawBytes();
    return recovered ? [hashed, recovery] : hashed;
}
async function sign(msgHash, privKey, opts = {}) {
    const { seed, m, d } = initSigArgs(msgHash, privKey, opts.extraEntropy);
    const drbg = new HmacDrbg(hashLen, groupLen);
    await drbg.reseed(seed);
    let sig;
    while (!(sig = kmdToSig(await drbg.generate(), m, d, opts.canonical)))
        await drbg.reseed();
    return finalizeSig(sig, opts);
}
exports.sign = sign;
function signSync(msgHash, privKey, opts = {}) {
    const { seed, m, d } = initSigArgs(msgHash, privKey, opts.extraEntropy);
    const drbg = new HmacDrbg(hashLen, groupLen);
    drbg.reseedSync(seed);
    let sig;
    while (!(sig = kmdToSig(drbg.generateSync(), m, d, opts.canonical)))
        drbg.reseedSync();
    return finalizeSig(sig, opts);
}
exports.signSync = signSync;
const vopts = { strict: true };
function verify(signature, msgHash, publicKey, opts = vopts) {
    let sig;
    try {
        sig = normalizeSignature(signature);
        msgHash = ensureBytes(msgHash);
    }
    catch (error) {
        return false;
    }
    const { r, s } = sig;
    if (opts.strict && sig.hasHighS())
        return false;
    const h = truncateHash(msgHash);
    let P;
    try {
        P = normalizePublicKey(publicKey);
    }
    catch (error) {
        return false;
    }
    const { n } = CURVE;
    const sinv = invert(s, n);
    const u1 = mod(h * sinv, n);
    const u2 = mod(r * sinv, n);
    const R = Point.BASE.multiplyAndAddUnsafe(P, u1, u2);
    if (!R)
        return false;
    const v = mod(R.x, n);
    return v === r;
}
exports.verify = verify;
function schnorrChallengeFinalize(ch) {
    return mod(bytesToNumber(ch), CURVE.n);
}
class SchnorrSignature {
    constructor(r, s) {
        this.r = r;
        this.s = s;
        this.assertValidity();
    }
    static fromHex(hex) {
        const bytes = ensureBytes(hex);
        if (bytes.length !== 64)
            throw new TypeError(`SchnorrSignature.fromHex: expected 64 bytes, not ${bytes.length}`);
        const r = bytesToNumber(bytes.subarray(0, 32));
        const s = bytesToNumber(bytes.subarray(32, 64));
        return new SchnorrSignature(r, s);
    }
    assertValidity() {
        const { r, s } = this;
        if (!isValidFieldElement(r) || !isWithinCurveOrder(s))
            throw new Error('Invalid signature');
    }
    toHex() {
        return numTo32bStr(this.r) + numTo32bStr(this.s);
    }
    toRawBytes() {
        return hexToBytes(this.toHex());
    }
}
function schnorrGetPublicKey(privateKey) {
    return Point.fromPrivateKey(privateKey).toRawX();
}
class InternalSchnorrSignature {
    constructor(message, privateKey, auxRand = exports.utils.randomBytes()) {
        if (message == null)
            throw new TypeError(`sign: Expected valid message, not "${message}"`);
        this.m = ensureBytes(message);
        const { x, scalar } = this.getScalar(normalizePrivateKey(privateKey));
        this.px = x;
        this.d = scalar;
        this.rand = ensureBytes(auxRand);
        if (this.rand.length !== 32)
            throw new TypeError('sign: Expected 32 bytes of aux randomness');
    }
    getScalar(priv) {
        const point = Point.fromPrivateKey(priv);
        const scalar = point.hasEvenY() ? priv : CURVE.n - priv;
        return { point, scalar, x: point.toRawX() };
    }
    initNonce(d, t0h) {
        return numTo32b(d ^ bytesToNumber(t0h));
    }
    finalizeNonce(k0h) {
        const k0 = mod(bytesToNumber(k0h), CURVE.n);
        if (k0 === _0n)
            throw new Error('sign: Creation of signature failed. k is zero');
        const { point: R, x: rx, scalar: k } = this.getScalar(k0);
        return { R, rx, k };
    }
    finalizeSig(R, k, e, d) {
        return new SchnorrSignature(R.x, mod(k + e * d, CURVE.n)).toRawBytes();
    }
    error() {
        throw new Error('sign: Invalid signature produced');
    }
    async calc() {
        const { m, d, px, rand } = this;
        const tag = exports.utils.taggedHash;
        const t = this.initNonce(d, await tag(TAGS.aux, rand));
        const { R, rx, k } = this.finalizeNonce(await tag(TAGS.nonce, t, px, m));
        const e = schnorrChallengeFinalize(await tag(TAGS.challenge, rx, px, m));
        const sig = this.finalizeSig(R, k, e, d);
        if (!(await schnorrVerify(sig, m, px)))
            this.error();
        return sig;
    }
    calcSync() {
        const { m, d, px, rand } = this;
        const tag = exports.utils.taggedHashSync;
        const t = this.initNonce(d, tag(TAGS.aux, rand));
        const { R, rx, k } = this.finalizeNonce(tag(TAGS.nonce, t, px, m));
        const e = schnorrChallengeFinalize(tag(TAGS.challenge, rx, px, m));
        const sig = this.finalizeSig(R, k, e, d);
        if (!schnorrVerifySync(sig, m, px))
            this.error();
        return sig;
    }
}
async function schnorrSign(msg, privKey, auxRand) {
    return new InternalSchnorrSignature(msg, privKey, auxRand).calc();
}
function schnorrSignSync(msg, privKey, auxRand) {
    return new InternalSchnorrSignature(msg, privKey, auxRand).calcSync();
}
function initSchnorrVerify(signature, message, publicKey) {
    const raw = signature instanceof SchnorrSignature;
    const sig = raw ? signature : SchnorrSignature.fromHex(signature);
    if (raw)
        sig.assertValidity();
    return {
        ...sig,
        m: ensureBytes(message),
        P: normalizePublicKey(publicKey),
    };
}
function finalizeSchnorrVerify(r, P, s, e) {
    const R = Point.BASE.multiplyAndAddUnsafe(P, normalizePrivateKey(s), mod(-e, CURVE.n));
    if (!R || !R.hasEvenY() || R.x !== r)
        return false;
    return true;
}
async function schnorrVerify(signature, message, publicKey) {
    try {
        const { r, s, m, P } = initSchnorrVerify(signature, message, publicKey);
        const e = schnorrChallengeFinalize(await exports.utils.taggedHash(TAGS.challenge, numTo32b(r), P.toRawX(), m));
        return finalizeSchnorrVerify(r, P, s, e);
    }
    catch (error) {
        return false;
    }
}
function schnorrVerifySync(signature, message, publicKey) {
    try {
        const { r, s, m, P } = initSchnorrVerify(signature, message, publicKey);
        const e = schnorrChallengeFinalize(exports.utils.taggedHashSync(TAGS.challenge, numTo32b(r), P.toRawX(), m));
        return finalizeSchnorrVerify(r, P, s, e);
    }
    catch (error) {
        if (error instanceof ShaError)
            throw error;
        return false;
    }
}
exports.schnorr = {
    Signature: SchnorrSignature,
    getPublicKey: schnorrGetPublicKey,
    sign: schnorrSign,
    verify: schnorrVerify,
    signSync: schnorrSignSync,
    verifySync: schnorrVerifySync,
};
Point.BASE._setWindowSize(8);
const crypto = {
    node: nodeCrypto,
    web: typeof self === 'object' && 'crypto' in self ? self.crypto : undefined,
};
const TAGS = {
    challenge: 'BIP0340/challenge',
    aux: 'BIP0340/aux',
    nonce: 'BIP0340/nonce',
};
const TAGGED_HASH_PREFIXES = {};
exports.utils = {
    bytesToHex,
    hexToBytes,
    concatBytes,
    mod,
    invert,
    isValidPrivateKey(privateKey) {
        try {
            normalizePrivateKey(privateKey);
            return true;
        }
        catch (error) {
            return false;
        }
    },
    _bigintTo32Bytes: numTo32b,
    _normalizePrivateKey: normalizePrivateKey,
    hashToPrivateKey: (hash) => {
        hash = ensureBytes(hash);
        const minLen = groupLen + 8;
        if (hash.length < minLen || hash.length > 1024) {
            throw new Error(`Expected valid bytes of private key as per FIPS 186`);
        }
        const num = mod(bytesToNumber(hash), CURVE.n - _1n) + _1n;
        return numTo32b(num);
    },
    randomBytes: (bytesLength = 32) => {
        if (crypto.web) {
            return crypto.web.getRandomValues(new Uint8Array(bytesLength));
        }
        else if (crypto.node) {
            const { randomBytes } = crypto.node;
            return Uint8Array.from(randomBytes(bytesLength));
        }
        else {
            throw new Error("The environment doesn't have randomBytes function");
        }
    },
    randomPrivateKey: () => exports.utils.hashToPrivateKey(exports.utils.randomBytes(groupLen + 8)),
    precompute(windowSize = 8, point = Point.BASE) {
        const cached = point === Point.BASE ? point : new Point(point.x, point.y);
        cached._setWindowSize(windowSize);
        cached.multiply(_3n);
        return cached;
    },
    sha256: async (...messages) => {
        if (crypto.web) {
            const buffer = await crypto.web.subtle.digest('SHA-256', concatBytes(...messages));
            return new Uint8Array(buffer);
        }
        else if (crypto.node) {
            const { createHash } = crypto.node;
            const hash = createHash('sha256');
            messages.forEach((m) => hash.update(m));
            return Uint8Array.from(hash.digest());
        }
        else {
            throw new Error("The environment doesn't have sha256 function");
        }
    },
    hmacSha256: async (key, ...messages) => {
        if (crypto.web) {
            const ckey = await crypto.web.subtle.importKey('raw', key, { name: 'HMAC', hash: { name: 'SHA-256' } }, false, ['sign']);
            const message = concatBytes(...messages);
            const buffer = await crypto.web.subtle.sign('HMAC', ckey, message);
            return new Uint8Array(buffer);
        }
        else if (crypto.node) {
            const { createHmac } = crypto.node;
            const hash = createHmac('sha256', key);
            messages.forEach((m) => hash.update(m));
            return Uint8Array.from(hash.digest());
        }
        else {
            throw new Error("The environment doesn't have hmac-sha256 function");
        }
    },
    sha256Sync: undefined,
    hmacSha256Sync: undefined,
    taggedHash: async (tag, ...messages) => {
        let tagP = TAGGED_HASH_PREFIXES[tag];
        if (tagP === undefined) {
            const tagH = await exports.utils.sha256(Uint8Array.from(tag, (c) => c.charCodeAt(0)));
            tagP = concatBytes(tagH, tagH);
            TAGGED_HASH_PREFIXES[tag] = tagP;
        }
        return exports.utils.sha256(tagP, ...messages);
    },
    taggedHashSync: (tag, ...messages) => {
        if (typeof _sha256Sync !== 'function')
            throw new ShaError('sha256Sync is undefined, you need to set it');
        let tagP = TAGGED_HASH_PREFIXES[tag];
        if (tagP === undefined) {
            const tagH = _sha256Sync(Uint8Array.from(tag, (c) => c.charCodeAt(0)));
            tagP = concatBytes(tagH, tagH);
            TAGGED_HASH_PREFIXES[tag] = tagP;
        }
        return _sha256Sync(tagP, ...messages);
    },
    _JacobianPoint: JacobianPoint,
};
Object.defineProperties(exports.utils, {
    sha256Sync: {
        configurable: false,
        get() {
            return _sha256Sync;
        },
        set(val) {
            if (!_sha256Sync)
                _sha256Sync = val;
        },
    },
    hmacSha256Sync: {
        configurable: false,
        get() {
            return _hmacSha256Sync;
        },
        set(val) {
            if (!_hmacSha256Sync)
                _hmacSha256Sync = val;
        },
    },
});

},{"crypto":58}],11:[function(require,module,exports){
"use strict";

Object.defineProperty(exports, "__esModule", {
  value: true
});
exports.alloc = alloc;
exports.equals = equals;
exports.readUInt16BE = readUInt16BE;
exports.readUInt16LE = readUInt16LE;
exports.readUInt32BE = readUInt32BE;
exports.readUInt32LE = readUInt32LE;
exports.readUInt8 = readUInt8;
exports.writeUInt16BE = writeUInt16BE;
exports.writeUInt16LE = writeUInt16LE;
exports.writeUInt32BE = writeUInt32BE;
exports.writeUInt32LE = writeUInt32LE;
exports.writeUInt8 = writeUInt8;

function equals(a, b) {
  if (a.byteLength !== b.byteLength) return false;

  for (let i = 0; i < a.byteLength; i++) {
    if (a[i] !== b[i]) return false;
  }

  return true;
}

function alloc(length, value) {
  const a = new Uint8Array(length);

  for (let i = 0; i < length; i++) {
    a[i] = value;
  }

  return a;
}

function readUInt16BE(source, offset) {
  return (source[offset + 0] << 8 | source[offset + 1]) >>> 0;
}

function writeUInt16BE(source, value, offset) {
  source[offset + 0] = value >>> 8;
  source[offset + 1] = value >>> 0;
}

function readUInt8(source, offset) {
  return source[offset];
}

function writeUInt8(destination, value, offset) {
  destination[offset] = value;
}

function readUInt16LE(source, offset) {
  return source[offset + 0] << 0 >>> 0 | source[offset + 1] << 8 >>> 0;
}

function writeUInt16LE(destination, value, offset) {
  destination[offset + 0] = value & 255;
  value >>>= 8;
  destination[offset + 1] = value & 255;
}

function readUInt32BE(source, offset) {
  return source[offset] * 2 ** 24 + source[offset + 1] * 2 ** 16 + source[offset + 2] * 2 ** 8 + source[offset + 3];
}

function writeUInt32BE(destination, value, offset) {
  destination[offset + 3] = value;
  value >>>= 8;
  destination[offset + 2] = value;
  value >>>= 8;
  destination[offset + 1] = value;
  value >>>= 8;
  destination[offset] = value;
}

function readUInt32LE(source, offset) {
  return source[offset + 0] << 0 >>> 0 | source[offset + 1] << 8 >>> 0 | source[offset + 2] << 16 >>> 0 | source[offset + 3] << 24 >>> 0;
}

function writeUInt32LE(destination, value, offset) {
  destination[offset + 0] = value & 255;
  value >>>= 8;
  destination[offset + 1] = value & 255;
  value >>>= 8;
  destination[offset + 2] = value & 255;
  value >>>= 8;
  destination[offset + 3] = value & 255;
}

},{}],12:[function(require,module,exports){
"use strict";

Object.defineProperty(exports, "__esModule", {
  value: true
});
exports.config = void 0;
const config = {
  network: {
    layer1: 'placeholder'
  },
  logLevel: 'debug'
};
exports.config = config;

},{}],13:[function(require,module,exports){
"use strict";

Object.defineProperty(exports, "__esModule", {
  value: true
});
exports.TransactionVersion = exports.PeerNetworkID = exports.PRIVATE_KEY_UNCOMPRESSED_LENGTH = exports.PRIVATE_KEY_COMPRESSED_LENGTH = exports.ChainID = exports.BLOCKSTACK_DEFAULT_GAIA_HUB_URL = void 0;
var ChainID;
exports.ChainID = ChainID;

(function (ChainID) {
  ChainID[ChainID["Testnet"] = 2147483648] = "Testnet";
  ChainID[ChainID["Mainnet"] = 1] = "Mainnet";
})(ChainID || (exports.ChainID = ChainID = {}));

var TransactionVersion;
exports.TransactionVersion = TransactionVersion;

(function (TransactionVersion) {
  TransactionVersion[TransactionVersion["Mainnet"] = 0] = "Mainnet";
  TransactionVersion[TransactionVersion["Testnet"] = 128] = "Testnet";
})(TransactionVersion || (exports.TransactionVersion = TransactionVersion = {}));

var PeerNetworkID;
exports.PeerNetworkID = PeerNetworkID;

(function (PeerNetworkID) {
  PeerNetworkID[PeerNetworkID["Mainnet"] = 385875968] = "Mainnet";
  PeerNetworkID[PeerNetworkID["Testnet"] = 4278190080] = "Testnet";
})(PeerNetworkID || (exports.PeerNetworkID = PeerNetworkID = {}));

const PRIVATE_KEY_COMPRESSED_LENGTH = 33;
exports.PRIVATE_KEY_COMPRESSED_LENGTH = PRIVATE_KEY_COMPRESSED_LENGTH;
const PRIVATE_KEY_UNCOMPRESSED_LENGTH = 32;
exports.PRIVATE_KEY_UNCOMPRESSED_LENGTH = PRIVATE_KEY_UNCOMPRESSED_LENGTH;
const BLOCKSTACK_DEFAULT_GAIA_HUB_URL = 'https://hub.blockstack.org';
exports.BLOCKSTACK_DEFAULT_GAIA_HUB_URL = BLOCKSTACK_DEFAULT_GAIA_HUB_URL;

},{}],14:[function(require,module,exports){
"use strict";

Object.defineProperty(exports, "__esModule", {
  value: true
});
exports.ValidationError = exports.SignatureVerificationError = exports.RemoteServiceError = exports.PreconditionFailedError = exports.PayloadTooLargeError = exports.NotEnoughProofError = exports.NotEnoughFundsError = exports.NoSessionDataError = exports.MissingParameterError = exports.LoginFailedError = exports.InvalidStateError = exports.InvalidParameterError = exports.InvalidDIDError = exports.InvalidAmountError = exports.GaiaHubError = exports.FailedDecryptionError = exports.ERROR_CODES = exports.DoesNotExist = exports.ConflictError = exports.BlockstackError = exports.BadPathError = void 0;
const ERROR_CODES = {
  MISSING_PARAMETER: 'missing_parameter',
  REMOTE_SERVICE_ERROR: 'remote_service_error',
  INVALID_STATE: 'invalid_state',
  NO_SESSION_DATA: 'no_session_data',
  DOES_NOT_EXIST: 'does_not_exist',
  FAILED_DECRYPTION_ERROR: 'failed_decryption_error',
  INVALID_DID_ERROR: 'invalid_did_error',
  NOT_ENOUGH_FUNDS_ERROR: 'not_enough_error',
  INVALID_AMOUNT_ERROR: 'invalid_amount_error',
  LOGIN_FAILED_ERROR: 'login_failed',
  SIGNATURE_VERIFICATION_ERROR: 'signature_verification_failure',
  CONFLICT_ERROR: 'conflict_error',
  NOT_ENOUGH_PROOF_ERROR: 'not_enough_proof_error',
  BAD_PATH_ERROR: 'bad_path_error',
  VALIDATION_ERROR: 'validation_error',
  PAYLOAD_TOO_LARGE_ERROR: 'payload_too_large_error',
  PRECONDITION_FAILED_ERROR: 'precondition_failed_error',
  UNKNOWN: 'unknown'
};
exports.ERROR_CODES = ERROR_CODES;
Object.freeze(ERROR_CODES);

class BlockstackError extends Error {
  constructor(error) {
    super();
    let message = error.message;
    let bugDetails = `Error Code: ${error.code}`;
    let stack = this.stack;

    if (!stack) {
      try {
        throw new Error();
      } catch (e) {
        stack = e.stack;
      }
    } else {
      bugDetails += `Stack Trace:\n${stack}`;
    }

    message += `\nIf you believe this exception is caused by a bug in stacks.js,
      please file a bug report: https://github.com/blockstack/stacks.js/issues\n\n${bugDetails}`;
    this.message = message;
    this.code = error.code;
    this.parameter = error.parameter ? error.parameter : undefined;
  }

  toString() {
    return `${super.toString()}
    code: ${this.code} param: ${this.parameter ? this.parameter : 'n/a'}`;
  }

}

exports.BlockstackError = BlockstackError;

class InvalidParameterError extends BlockstackError {
  constructor(parameter, message = '') {
    super({
      code: ERROR_CODES.MISSING_PARAMETER,
      message,
      parameter
    });
    this.name = 'MissingParametersError';
  }

}

exports.InvalidParameterError = InvalidParameterError;

class MissingParameterError extends BlockstackError {
  constructor(parameter, message = '') {
    super({
      code: ERROR_CODES.MISSING_PARAMETER,
      message,
      parameter
    });
    this.name = 'MissingParametersError';
  }

}

exports.MissingParameterError = MissingParameterError;

class RemoteServiceError extends BlockstackError {
  constructor(response, message = '') {
    super({
      code: ERROR_CODES.REMOTE_SERVICE_ERROR,
      message
    });
    this.response = response;
  }

}

exports.RemoteServiceError = RemoteServiceError;

class InvalidDIDError extends BlockstackError {
  constructor(message = '') {
    super({
      code: ERROR_CODES.INVALID_DID_ERROR,
      message
    });
    this.name = 'InvalidDIDError';
  }

}

exports.InvalidDIDError = InvalidDIDError;

class NotEnoughFundsError extends BlockstackError {
  constructor(leftToFund) {
    const message = `Not enough UTXOs to fund. Left to fund: ${leftToFund}`;
    super({
      code: ERROR_CODES.NOT_ENOUGH_FUNDS_ERROR,
      message
    });
    this.leftToFund = leftToFund;
    this.name = 'NotEnoughFundsError';
    this.message = message;
  }

}

exports.NotEnoughFundsError = NotEnoughFundsError;

class InvalidAmountError extends BlockstackError {
  constructor(fees, specifiedAmount) {
    const message = `Not enough coin to fund fees transaction fees. Fees would be ${fees},` + ` specified spend is  ${specifiedAmount}`;
    super({
      code: ERROR_CODES.INVALID_AMOUNT_ERROR,
      message
    });
    this.specifiedAmount = specifiedAmount;
    this.fees = fees;
    this.name = 'InvalidAmountError';
    this.message = message;
  }

}

exports.InvalidAmountError = InvalidAmountError;

class LoginFailedError extends BlockstackError {
  constructor(reason) {
    const message = `Failed to login: ${reason}`;
    super({
      code: ERROR_CODES.LOGIN_FAILED_ERROR,
      message
    });
    this.message = message;
    this.name = 'LoginFailedError';
  }

}

exports.LoginFailedError = LoginFailedError;

class SignatureVerificationError extends BlockstackError {
  constructor(reason) {
    const message = `Failed to verify signature: ${reason}`;
    super({
      code: ERROR_CODES.SIGNATURE_VERIFICATION_ERROR,
      message
    });
    this.message = message;
    this.name = 'SignatureVerificationError';
  }

}

exports.SignatureVerificationError = SignatureVerificationError;

class FailedDecryptionError extends BlockstackError {
  constructor(message = 'Unable to decrypt cipher object.') {
    super({
      code: ERROR_CODES.FAILED_DECRYPTION_ERROR,
      message
    });
    this.message = message;
    this.name = 'FailedDecryptionError';
  }

}

exports.FailedDecryptionError = FailedDecryptionError;

class InvalidStateError extends BlockstackError {
  constructor(message) {
    super({
      code: ERROR_CODES.INVALID_STATE,
      message
    });
    this.message = message;
    this.name = 'InvalidStateError';
  }

}

exports.InvalidStateError = InvalidStateError;

class NoSessionDataError extends BlockstackError {
  constructor(message) {
    super({
      code: ERROR_CODES.INVALID_STATE,
      message
    });
    this.message = message;
    this.name = 'NoSessionDataError';
  }

}

exports.NoSessionDataError = NoSessionDataError;

class GaiaHubError extends BlockstackError {
  constructor(error, response) {
    super(error);

    if (response) {
      this.hubError = {
        statusCode: response.status,
        statusText: response.statusText
      };

      if (typeof response.body === 'string') {
        this.hubError.message = response.body;
      } else if (typeof response.body === 'object') {
        Object.assign(this.hubError, response.body);
      }
    }
  }

}

exports.GaiaHubError = GaiaHubError;

class DoesNotExist extends GaiaHubError {
  constructor(message, response) {
    super({
      message,
      code: ERROR_CODES.DOES_NOT_EXIST
    }, response);
    this.name = 'DoesNotExist';
  }

}

exports.DoesNotExist = DoesNotExist;

class ConflictError extends GaiaHubError {
  constructor(message, response) {
    super({
      message,
      code: ERROR_CODES.CONFLICT_ERROR
    }, response);
    this.name = 'ConflictError';
  }

}

exports.ConflictError = ConflictError;

class NotEnoughProofError extends GaiaHubError {
  constructor(message, response) {
    super({
      message,
      code: ERROR_CODES.NOT_ENOUGH_PROOF_ERROR
    }, response);
    this.name = 'NotEnoughProofError';
  }

}

exports.NotEnoughProofError = NotEnoughProofError;

class BadPathError extends GaiaHubError {
  constructor(message, response) {
    super({
      message,
      code: ERROR_CODES.BAD_PATH_ERROR
    }, response);
    this.name = 'BadPathError';
  }

}

exports.BadPathError = BadPathError;

class ValidationError extends GaiaHubError {
  constructor(message, response) {
    super({
      message,
      code: ERROR_CODES.VALIDATION_ERROR
    }, response);
    this.name = 'ValidationError';
  }

}

exports.ValidationError = ValidationError;

class PayloadTooLargeError extends GaiaHubError {
  constructor(message, response, maxUploadByteSize) {
    super({
      message,
      code: ERROR_CODES.PAYLOAD_TOO_LARGE_ERROR
    }, response);
    this.name = 'PayloadTooLargeError';
    this.maxUploadByteSize = maxUploadByteSize;
  }

}

exports.PayloadTooLargeError = PayloadTooLargeError;

class PreconditionFailedError extends GaiaHubError {
  constructor(message, response) {
    super({
      message,
      code: ERROR_CODES.PRECONDITION_FAILED_ERROR
    }, response);
    this.name = 'PreconditionFailedError';
  }

}

exports.PreconditionFailedError = PreconditionFailedError;

},{}],15:[function(require,module,exports){
"use strict";

Object.defineProperty(exports, "__esModule", {
  value: true
});

var _config = require("./config");

Object.keys(_config).forEach(function (key) {
  if (key === "default" || key === "__esModule") return;
  if (key in exports && exports[key] === _config[key]) return;
  Object.defineProperty(exports, key, {
    enumerable: true,
    get: function () {
      return _config[key];
    }
  });
});

var _errors = require("./errors");

Object.keys(_errors).forEach(function (key) {
  if (key === "default" || key === "__esModule") return;
  if (key in exports && exports[key] === _errors[key]) return;
  Object.defineProperty(exports, key, {
    enumerable: true,
    get: function () {
      return _errors[key];
    }
  });
});

var _logger = require("./logger");

Object.keys(_logger).forEach(function (key) {
  if (key === "default" || key === "__esModule") return;
  if (key in exports && exports[key] === _logger[key]) return;
  Object.defineProperty(exports, key, {
    enumerable: true,
    get: function () {
      return _logger[key];
    }
  });
});

var _utils = require("./utils");

Object.keys(_utils).forEach(function (key) {
  if (key === "default" || key === "__esModule") return;
  if (key in exports && exports[key] === _utils[key]) return;
  Object.defineProperty(exports, key, {
    enumerable: true,
    get: function () {
      return _utils[key];
    }
  });
});

var _constants = require("./constants");

Object.keys(_constants).forEach(function (key) {
  if (key === "default" || key === "__esModule") return;
  if (key in exports && exports[key] === _constants[key]) return;
  Object.defineProperty(exports, key, {
    enumerable: true,
    get: function () {
      return _constants[key];
    }
  });
});

var _signatures = require("./signatures");

Object.keys(_signatures).forEach(function (key) {
  if (key === "default" || key === "__esModule") return;
  if (key in exports && exports[key] === _signatures[key]) return;
  Object.defineProperty(exports, key, {
    enumerable: true,
    get: function () {
      return _signatures[key];
    }
  });
});

var _keys = require("./keys");

Object.keys(_keys).forEach(function (key) {
  if (key === "default" || key === "__esModule") return;
  if (key in exports && exports[key] === _keys[key]) return;
  Object.defineProperty(exports, key, {
    enumerable: true,
    get: function () {
      return _keys[key];
    }
  });
});

var _buffer = require("./buffer");

Object.keys(_buffer).forEach(function (key) {
  if (key === "default" || key === "__esModule") return;
  if (key in exports && exports[key] === _buffer[key]) return;
  Object.defineProperty(exports, key, {
    enumerable: true,
    get: function () {
      return _buffer[key];
    }
  });
});

},{"./buffer":11,"./config":12,"./constants":13,"./errors":14,"./keys":16,"./logger":17,"./signatures":18,"./utils":19}],16:[function(require,module,exports){
"use strict";

Object.defineProperty(exports, "__esModule", {
  value: true
});
exports.privateKeyToBytes = privateKeyToBytes;

var _utils = require("./utils");

function privateKeyToBytes(privateKey) {
  const privateKeyBuffer = typeof privateKey === 'string' ? (0, _utils.hexToBytes)(privateKey) : privateKey;

  if (privateKeyBuffer.length != 32 && privateKeyBuffer.length != 33) {
    throw new Error(`Improperly formatted private-key. Private-key byte length should be 32 or 33. Length provided: ${privateKeyBuffer.length}`);
  }

  if (privateKeyBuffer.length == 33 && privateKeyBuffer[32] !== 1) {
    throw new Error('Improperly formatted private-key. 33 bytes indicate compressed key, but the last byte must be == 01');
  }

  return privateKeyBuffer;
}

},{"./utils":19}],17:[function(require,module,exports){
"use strict";

Object.defineProperty(exports, "__esModule", {
  value: true
});
exports.Logger = void 0;

var _config = require("./config");

const levels = ['debug', 'info', 'warn', 'error', 'none'];
const levelToInt = {};
const intToLevel = {};

for (let index = 0; index < levels.length; index++) {
  const level = levels[index];
  levelToInt[level] = index;
  intToLevel[index] = level;
}

class Logger {
  static error(message) {
    if (!this.shouldLog('error')) return;
    console.error(this.logMessage('error', message));
  }

  static warn(message) {
    if (!this.shouldLog('warn')) return;
    console.warn(this.logMessage('warn', message));
  }

  static info(message) {
    if (!this.shouldLog('info')) return;
    console.log(this.logMessage('info', message));
  }

  static debug(message) {
    if (!this.shouldLog('debug')) return;
    console.log(this.logMessage('debug', message));
  }

  static logMessage(level, message) {
    return `[${level.toUpperCase()}] ${message}`;
  }

  static shouldLog(level) {
    const currentLevel = levelToInt[_config.config.logLevel];
    return currentLevel <= levelToInt[level];
  }

}

exports.Logger = Logger;

},{"./config":12}],18:[function(require,module,exports){
"use strict";

Object.defineProperty(exports, "__esModule", {
  value: true
});
exports.parseRecoverableSignatureVrs = parseRecoverableSignatureVrs;
exports.signatureRsvToVrs = signatureRsvToVrs;
exports.signatureVrsToRsv = signatureVrsToRsv;

var _utils = require("./utils");

const COORDINATE_BYTES = 32;

function parseRecoverableSignatureVrs(signature) {
  if (signature.length < COORDINATE_BYTES * 2 * 2 + 1) {
    throw new Error('Invalid signature');
  }

  const recoveryIdHex = signature.slice(0, 2);
  const r = signature.slice(2, 2 + COORDINATE_BYTES * 2);
  const s = signature.slice(2 + COORDINATE_BYTES * 2);
  return {
    recoveryId: (0, _utils.hexToInt)(recoveryIdHex),
    r,
    s
  };
}

function signatureVrsToRsv(signature) {
  return signature.slice(2) + signature.slice(0, 2);
}

function signatureRsvToVrs(signature) {
  return signature.slice(-2) + signature.slice(0, -2);
}

},{"./utils":19}],19:[function(require,module,exports){
(function (global){(function (){
"use strict";

Object.defineProperty(exports, "__esModule", {
  value: true
});
exports.BLOCKSTACK_HANDLER = void 0;
exports.asciiToBytes = asciiToBytes;
exports.bigIntToBytes = bigIntToBytes;
exports.bytesToAscii = bytesToAscii;
exports.bytesToHex = bytesToHex;
exports.bytesToUtf8 = bytesToUtf8;
exports.concatArray = concatArray;
exports.concatBytes = concatBytes;
exports.fromTwos = fromTwos;
exports.getAesCbcOutputLength = getAesCbcOutputLength;
exports.getBase64OutputLength = getBase64OutputLength;
exports.getGlobalObject = getGlobalObject;
exports.getGlobalObjects = getGlobalObjects;
exports.getGlobalScope = getGlobalScope;
exports.hexToBigInt = hexToBigInt;
exports.hexToBytes = hexToBytes;
exports.hexToInt = hexToInt;
exports.intToBigInt = intToBigInt;
exports.intToBytes = intToBytes;
exports.intToHex = intToHex;
exports.isInstance = isInstance;
exports.isLaterVersion = isLaterVersion;
exports.isSameOriginAbsoluteUrl = isSameOriginAbsoluteUrl;
exports.makeUUID4 = makeUUID4;
exports.megabytesToBytes = megabytesToBytes;
exports.nextHour = nextHour;
exports.nextMonth = nextMonth;
exports.nextYear = nextYear;
exports.octetsToBytes = octetsToBytes;
exports.toTwos = toTwos;
exports.updateQueryStringParameter = updateQueryStringParameter;
exports.utf8ToBytes = utf8ToBytes;
exports.with0x = with0x;

var _logger = require("./logger");

const BLOCKSTACK_HANDLER = 'blockstack';
exports.BLOCKSTACK_HANDLER = BLOCKSTACK_HANDLER;

function nextYear() {
  return new Date(new Date().setFullYear(new Date().getFullYear() + 1));
}

function nextMonth() {
  return new Date(new Date().setMonth(new Date().getMonth() + 1));
}

function nextHour() {
  return new Date(new Date().setHours(new Date().getHours() + 1));
}

function megabytesToBytes(megabytes) {
  if (!Number.isFinite(megabytes)) {
    return 0;
  }

  return Math.floor(megabytes * 1024 * 1024);
}

function getAesCbcOutputLength(inputByteLength) {
  const cipherTextLength = (Math.floor(inputByteLength / 16) + 1) * 16;
  return cipherTextLength;
}

function getBase64OutputLength(inputByteLength) {
  const encodedLength = Math.ceil(inputByteLength / 3) * 4;
  return encodedLength;
}

function updateQueryStringParameter(uri, key, value) {
  const re = new RegExp(`([?&])${key}=.*?(&|$)`, 'i');
  const separator = uri.indexOf('?') !== -1 ? '&' : '?';

  if (uri.match(re)) {
    return uri.replace(re, `$1${key}=${value}$2`);
  } else {
    return `${uri}${separator}${key}=${value}`;
  }
}

function isLaterVersion(v1, v2) {
  if (v1 === undefined || v1 === '') {
    v1 = '0.0.0';
  }

  if (v2 === undefined || v1 === '') {
    v2 = '0.0.0';
  }

  const v1tuple = v1.split('.').map(x => parseInt(x, 10));
  const v2tuple = v2.split('.').map(x => parseInt(x, 10));

  for (let index = 0; index < v2.length; index++) {
    if (index >= v1.length) {
      v2tuple.push(0);
    }

    if (v1tuple[index] < v2tuple[index]) {
      return false;
    }
  }

  return true;
}

function makeUUID4() {
  let d = new Date().getTime();

  if (typeof performance !== 'undefined' && typeof performance.now === 'function') {
    d += performance.now();
  }

  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, c => {
    const r = (d + Math.random() * 16) % 16 | 0;
    d = Math.floor(d / 16);
    return (c === 'x' ? r : r & 0x3 | 0x8).toString(16);
  });
}

function isSameOriginAbsoluteUrl(uri1, uri2) {
  try {
    const parsedUri1 = new URL(uri1);
    const parsedUri2 = new URL(uri2);
    const port1 = parseInt(parsedUri1.port || '0', 10) | 0 || (parsedUri1.protocol === 'https:' ? 443 : 80);
    const port2 = parseInt(parsedUri2.port || '0', 10) | 0 || (parsedUri2.protocol === 'https:' ? 443 : 80);
    const match = {
      scheme: parsedUri1.protocol === parsedUri2.protocol,
      hostname: parsedUri1.hostname === parsedUri2.hostname,
      port: port1 === port2,
      absolute: (uri1.includes('http://') || uri1.includes('https://')) && (uri2.includes('http://') || uri2.includes('https://'))
    };
    return match.scheme && match.hostname && match.port && match.absolute;
  } catch (error) {
    console.log(error);
    console.log('Parsing error in same URL origin check');
    return false;
  }
}

function getGlobalScope() {
  if (typeof self !== 'undefined') {
    return self;
  }

  if (typeof window !== 'undefined') {
    return window;
  }

  if (typeof global !== 'undefined') {
    return global;
  }

  throw new Error('Unexpected runtime environment - no supported global scope (`window`, `self`, `global`) available');
}

function getAPIUsageErrorMessage(scopeObject, apiName, usageDesc) {
  if (usageDesc) {
    return `Use of '${usageDesc}' requires \`${apiName}\` which is unavailable on the '${scopeObject}' object within the currently executing environment.`;
  } else {
    return `\`${apiName}\` is unavailable on the '${scopeObject}' object within the currently executing environment.`;
  }
}

function getGlobalObject(name, {
  throwIfUnavailable,
  usageDesc,
  returnEmptyObject
} = {}) {
  let globalScope = undefined;

  try {
    globalScope = getGlobalScope();

    if (globalScope) {
      const obj = globalScope[name];

      if (obj) {
        return obj;
      }
    }
  } catch (error) {
    _logger.Logger.error(`Error getting object '${name}' from global scope '${globalScope}': ${error}`);
  }

  if (throwIfUnavailable) {
    const errMsg = getAPIUsageErrorMessage(globalScope, name.toString(), usageDesc);

    _logger.Logger.error(errMsg);

    throw new Error(errMsg);
  }

  if (returnEmptyObject) {
    return {};
  }

  return undefined;
}

function getGlobalObjects(names, {
  throwIfUnavailable,
  usageDesc,
  returnEmptyObject
} = {}) {
  let globalScope;

  try {
    globalScope = getGlobalScope();
  } catch (error) {
    _logger.Logger.error(`Error getting global scope: ${error}`);

    if (throwIfUnavailable) {
      const errMsg = getAPIUsageErrorMessage(globalScope, names[0].toString(), usageDesc);

      _logger.Logger.error(errMsg);

      throw errMsg;
    } else if (returnEmptyObject) {
      globalScope = {};
    }
  }

  const result = {};

  for (let i = 0; i < names.length; i++) {
    const name = names[i];

    try {
      if (globalScope) {
        const obj = globalScope[name];

        if (obj) {
          result[name] = obj;
        } else if (throwIfUnavailable) {
          const errMsg = getAPIUsageErrorMessage(globalScope, name.toString(), usageDesc);

          _logger.Logger.error(errMsg);

          throw new Error(errMsg);
        } else if (returnEmptyObject) {
          result[name] = {};
        }
      }
    } catch (error) {
      if (throwIfUnavailable) {
        const errMsg = getAPIUsageErrorMessage(globalScope, name.toString(), usageDesc);

        _logger.Logger.error(errMsg);

        throw new Error(errMsg);
      }
    }
  }

  return result;
}

function intToBytes(value, signed, byteLength) {
  return bigIntToBytes(intToBigInt(value, signed), byteLength);
}

function intToBigInt(value, signed) {
  let parsedValue = value;

  if (typeof parsedValue === 'number') {
    if (!Number.isInteger(parsedValue)) {
      throw new RangeError(`Invalid value. Values of type 'number' must be an integer.`);
    }

    if (parsedValue > Number.MAX_SAFE_INTEGER) {
      throw new RangeError(`Invalid value. Values of type 'number' must be less than or equal to ${Number.MAX_SAFE_INTEGER}. For larger values, try using a BigInt instead.`);
    }

    return BigInt(parsedValue);
  }

  if (typeof parsedValue === 'string') {
    if (parsedValue.toLowerCase().startsWith('0x')) {
      let hex = parsedValue.slice(2);
      hex = hex.padStart(hex.length + hex.length % 2, '0');
      parsedValue = hexToBytes(hex);
    } else {
      try {
        return BigInt(parsedValue);
      } catch (error) {
        if (error instanceof SyntaxError) {
          throw new RangeError(`Invalid value. String integer '${parsedValue}' is not finite.`);
        }
      }
    }
  }

  if (typeof parsedValue === 'bigint') {
    return parsedValue;
  }

  if (parsedValue instanceof Uint8Array) {
    if (signed) {
      const bn = fromTwos(BigInt(`0x${bytesToHex(parsedValue)}`), BigInt(parsedValue.byteLength * 8));
      return BigInt(bn.toString());
    } else {
      return BigInt(`0x${bytesToHex(parsedValue)}`);
    }
  }

  if (parsedValue != null && typeof parsedValue === 'object' && parsedValue.constructor.name === 'BN') {
    return BigInt(parsedValue.toString());
  }

  throw new TypeError(`Invalid value type. Must be a number, bigint, integer-string, hex-string, or Uint8Array.`);
}

function with0x(value) {
  return value.startsWith('0x') ? value : `0x${value}`;
}

function hexToBigInt(hex) {
  if (typeof hex !== 'string') throw new TypeError(`hexToBigInt: expected string, got ${typeof hex}`);
  return BigInt(`0x${hex}`);
}

function intToHex(integer, lengthBytes = 8) {
  const value = typeof integer === 'bigint' ? integer : intToBigInt(integer, false);
  return value.toString(16).padStart(lengthBytes * 2, '0');
}

function hexToInt(hex) {
  return parseInt(hex, 16);
}

function bigIntToBytes(value, length = 16) {
  const hex = intToHex(value, length);
  return hexToBytes(hex);
}

function toTwos(value, width) {
  if (value < -(BigInt(1) << width - BigInt(1)) || (BigInt(1) << width - BigInt(1)) - BigInt(1) < value) {
    throw `Unable to represent integer in width: ${width}`;
  }

  if (value >= BigInt(0)) {
    return BigInt(value);
  }

  return value + (BigInt(1) << width);
}

function nthBit(value, n) {
  return value & BigInt(1) << n;
}

function fromTwos(value, width) {
  if (nthBit(value, width - BigInt(1))) {
    return value - (BigInt(1) << width);
  }

  return value;
}

const hexes = Array.from({
  length: 256
}, (_, i) => i.toString(16).padStart(2, '0'));

function bytesToHex(uint8a) {
  if (!(uint8a instanceof Uint8Array)) throw new Error('Uint8Array expected');
  let hex = '';

  for (const u of uint8a) {
    hex += hexes[u];
  }

  return hex;
}

function hexToBytes(hex) {
  if (typeof hex !== 'string') {
    throw new TypeError(`hexToBytes: expected string, got ${typeof hex}`);
  }

  const paddedHex = hex.length % 2 ? `0${hex}` : hex;
  const array = new Uint8Array(paddedHex.length / 2);

  for (let i = 0; i < array.length; i++) {
    const j = i * 2;
    const hexByte = paddedHex.slice(j, j + 2);
    const byte = Number.parseInt(hexByte, 16);
    if (Number.isNaN(byte) || byte < 0) throw new Error('Invalid byte sequence');
    array[i] = byte;
  }

  return array;
}

function utf8ToBytes(str) {
  return new TextEncoder().encode(str);
}

function bytesToUtf8(arr) {
  return new TextDecoder().decode(arr);
}

function asciiToBytes(str) {
  const byteArray = [];

  for (let i = 0; i < str.length; i++) {
    byteArray.push(str.charCodeAt(i) & 0xff);
  }

  return new Uint8Array(byteArray);
}

function bytesToAscii(arr) {
  return String.fromCharCode.apply(null, arr);
}

function isNotOctet(octet) {
  return !Number.isInteger(octet) || octet < 0 || octet > 255;
}

function octetsToBytes(numbers) {
  if (numbers.some(isNotOctet)) throw new Error('Some values are invalid bytes.');
  return new Uint8Array(numbers);
}

function concatBytes(...arrays) {
  if (!arrays.every(a => a instanceof Uint8Array)) throw new Error('Uint8Array list expected');
  if (arrays.length === 1) return arrays[0];
  const length = arrays.reduce((a, arr) => a + arr.length, 0);
  const result = new Uint8Array(length);

  for (let i = 0, pad = 0; i < arrays.length; i++) {
    const arr = arrays[i];
    result.set(arr, pad);
    pad += arr.length;
  }

  return result;
}

function concatArray(elements) {
  return concatBytes(...elements.map(e => {
    if (typeof e === 'number') return octetsToBytes([e]);
    if (e instanceof Array) return octetsToBytes(e);
    return e;
  }));
}

function isInstance(object, type) {
  return object instanceof type || object?.constructor?.name?.toLowerCase() === type.name;
}

}).call(this)}).call(this,typeof global !== "undefined" ? global : typeof self !== "undefined" ? self : typeof window !== "undefined" ? window : {})
},{"./logger":17}],20:[function(require,module,exports){
"use strict";

Object.defineProperty(exports, "__esModule", {
  value: true
});
exports.createApiKeyMiddleware = createApiKeyMiddleware;
exports.createFetchFn = createFetchFn;
exports.fetchWrapper = fetchWrapper;
exports.getFetchOptions = void 0;
exports.hostMatches = hostMatches;
exports.setFetchOptions = void 0;

require("cross-fetch/polyfill");

const defaultFetchOpts = {
  referrerPolicy: 'origin',
  headers: {
    'x-hiro-product': 'stacksjs'
  }
};

const getFetchOptions = () => {
  return defaultFetchOpts;
};

exports.getFetchOptions = getFetchOptions;

const setFetchOptions = ops => {
  return Object.assign(defaultFetchOpts, ops);
};

exports.setFetchOptions = setFetchOptions;

async function fetchWrapper(input, init) {
  const fetchOpts = {};
  Object.assign(fetchOpts, defaultFetchOpts, init);
  const fetchResult = await fetch(input, fetchOpts);
  return fetchResult;
}

function hostMatches(host, pattern) {
  if (typeof pattern === 'string') return pattern === host;
  return pattern.exec(host);
}

function createApiKeyMiddleware({
  apiKey,
  host = /(.*)api(.*)(\.stacks\.co|\.hiro\.so)$/i,
  httpHeader = 'x-api-key'
}) {
  return {
    pre: context => {
      const reqUrl = new URL(context.url);
      if (!hostMatches(reqUrl.host, host)) return;
      const headers = new Headers(context.init.headers);
      headers.set(httpHeader, apiKey);
      context.init.headers = headers;
    }
  };
}

function argsForCreateFetchFn(args) {
  let fetchLib = fetchWrapper;
  let middlewares = [];

  if (args.length > 0 && typeof args[0] === 'function') {
    fetchLib = args.shift();
  }

  if (args.length > 0) {
    middlewares = args;
  }

  return {
    fetchLib,
    middlewares
  };
}

function createFetchFn(...args) {
  const {
    fetchLib,
    middlewares
  } = argsForCreateFetchFn(args);

  const fetchFn = async (url, init) => {
    let fetchParams = {
      url,
      init: init ?? {}
    };

    for (const middleware of middlewares) {
      if (typeof middleware.pre === 'function') {
        const result = await Promise.resolve(middleware.pre({
          fetch: fetchLib,
          ...fetchParams
        }));
        fetchParams = result ?? fetchParams;
      }
    }

    let response = await fetchLib(fetchParams.url, fetchParams.init);

    for (const middleware of middlewares) {
      if (typeof middleware.post === 'function') {
        const result = await Promise.resolve(middleware.post({
          fetch: fetchLib,
          url: fetchParams.url,
          init: fetchParams.init,
          response: response?.clone() ?? response
        }));
        response = result ?? response;
      }
    }

    return response;
  };

  return fetchFn;
}

},{"cross-fetch/polyfill":65}],21:[function(require,module,exports){
"use strict";

Object.defineProperty(exports, "__esModule", {
  value: true
});

var _fetch = require("./fetch");

Object.keys(_fetch).forEach(function (key) {
  if (key === "default" || key === "__esModule") return;
  if (key in exports && exports[key] === _fetch[key]) return;
  Object.defineProperty(exports, key, {
    enumerable: true,
    get: function () {
      return _fetch[key];
    }
  });
});

var _network = require("./network");

Object.keys(_network).forEach(function (key) {
  if (key === "default" || key === "__esModule") return;
  if (key in exports && exports[key] === _network[key]) return;
  Object.defineProperty(exports, key, {
    enumerable: true,
    get: function () {
      return _network[key];
    }
  });
});

},{"./fetch":20,"./network":22}],22:[function(require,module,exports){
"use strict";

Object.defineProperty(exports, "__esModule", {
  value: true
});
exports.StacksTestnet = exports.StacksNetworks = exports.StacksNetwork = exports.StacksMocknet = exports.StacksMainnet = exports.StacksDevnet = exports.HIRO_TESTNET_DEFAULT = exports.HIRO_MOCKNET_DEFAULT = exports.HIRO_MAINNET_DEFAULT = void 0;

var _common = require("@stacks/common");

var _fetch = require("./fetch");

const HIRO_MAINNET_DEFAULT = 'https://api.mainnet.hiro.so';
exports.HIRO_MAINNET_DEFAULT = HIRO_MAINNET_DEFAULT;
const HIRO_TESTNET_DEFAULT = 'https://api.testnet.hiro.so';
exports.HIRO_TESTNET_DEFAULT = HIRO_TESTNET_DEFAULT;
const HIRO_MOCKNET_DEFAULT = 'http://localhost:3999';
exports.HIRO_MOCKNET_DEFAULT = HIRO_MOCKNET_DEFAULT;
const StacksNetworks = ['mainnet', 'testnet', 'devnet', 'mocknet'];
exports.StacksNetworks = StacksNetworks;

class StacksNetwork {
  constructor(networkConfig) {
    this.version = _common.TransactionVersion.Mainnet;
    this.chainId = _common.ChainID.Mainnet;
    this.bnsLookupUrl = 'https://api.mainnet.hiro.so';
    this.broadcastEndpoint = '/v2/transactions';
    this.transferFeeEstimateEndpoint = '/v2/fees/transfer';
    this.transactionFeeEstimateEndpoint = '/v2/fees/transaction';
    this.accountEndpoint = '/v2/accounts';
    this.contractAbiEndpoint = '/v2/contracts/interface';
    this.readOnlyFunctionCallEndpoint = '/v2/contracts/call-read';

    this.isMainnet = () => this.version === _common.TransactionVersion.Mainnet;

    this.getBroadcastApiUrl = () => `${this.coreApiUrl}${this.broadcastEndpoint}`;

    this.getTransferFeeEstimateApiUrl = () => `${this.coreApiUrl}${this.transferFeeEstimateEndpoint}`;

    this.getTransactionFeeEstimateApiUrl = () => `${this.coreApiUrl}${this.transactionFeeEstimateEndpoint}`;

    this.getAccountApiUrl = address => `${this.coreApiUrl}${this.accountEndpoint}/${address}?proof=0`;

    this.getAccountExtendedBalancesApiUrl = address => `${this.coreApiUrl}/extended/v1/address/${address}/balances`;

    this.getAbiApiUrl = (address, contract) => `${this.coreApiUrl}${this.contractAbiEndpoint}/${address}/${contract}`;

    this.getReadOnlyFunctionCallApiUrl = (contractAddress, contractName, functionName) => `${this.coreApiUrl}${this.readOnlyFunctionCallEndpoint}/${contractAddress}/${contractName}/${encodeURIComponent(functionName)}`;

    this.getInfoUrl = () => `${this.coreApiUrl}/v2/info`;

    this.getBlockTimeInfoUrl = () => `${this.coreApiUrl}/extended/v1/info/network_block_times`;

    this.getPoxInfoUrl = () => `${this.coreApiUrl}/v2/pox`;

    this.getRewardsUrl = (address, options) => {
      let url = `${this.coreApiUrl}/extended/v1/burnchain/rewards/${address}`;

      if (options) {
        url = `${url}?limit=${options.limit}&offset=${options.offset}`;
      }

      return url;
    };

    this.getRewardsTotalUrl = address => `${this.coreApiUrl}/extended/v1/burnchain/rewards/${address}/total`;

    this.getRewardHoldersUrl = (address, options) => {
      let url = `${this.coreApiUrl}/extended/v1/burnchain/reward_slot_holders/${address}`;

      if (options) {
        url = `${url}?limit=${options.limit}&offset=${options.offset}`;
      }

      return url;
    };

    this.getStackerInfoUrl = (contractAddress, contractName) => `${this.coreApiUrl}${this.readOnlyFunctionCallEndpoint}
    ${contractAddress}/${contractName}/get-stacker-info`;

    this.getDataVarUrl = (contractAddress, contractName, dataVarName) => `${this.coreApiUrl}/v2/data_var/${contractAddress}/${contractName}/${dataVarName}?proof=0`;

    this.getMapEntryUrl = (contractAddress, contractName, mapName) => `${this.coreApiUrl}/v2/map_entry/${contractAddress}/${contractName}/${mapName}?proof=0`;

    this.coreApiUrl = networkConfig.url;
    this.fetchFn = networkConfig.fetchFn ?? (0, _fetch.createFetchFn)();
  }

  getNameInfo(fullyQualifiedName) {
    const nameLookupURL = `${this.bnsLookupUrl}/v1/names/${fullyQualifiedName}`;
    return this.fetchFn(nameLookupURL).then(resp => {
      if (resp.status === 404) {
        throw new Error('Name not found');
      } else if (resp.status !== 200) {
        throw new Error(`Bad response status: ${resp.status}`);
      } else {
        return resp.json();
      }
    }).then(nameInfo => {
      if (nameInfo.address) {
        return Object.assign({}, nameInfo, {
          address: nameInfo.address
        });
      } else {
        return nameInfo;
      }
    });
  }

}

exports.StacksNetwork = StacksNetwork;

StacksNetwork.fromName = networkName => {
  switch (networkName) {
    case 'mainnet':
      return new StacksMainnet();

    case 'testnet':
      return new StacksTestnet();

    case 'devnet':
      return new StacksDevnet();

    case 'mocknet':
      return new StacksMocknet();

    default:
      throw new Error(`Invalid network name provided. Must be one of the following: ${StacksNetworks.join(', ')}`);
  }
};

StacksNetwork.fromNameOrNetwork = network => {
  if (typeof network !== 'string' && 'version' in network) {
    return network;
  }

  return StacksNetwork.fromName(network);
};

class StacksMainnet extends StacksNetwork {
  constructor(opts) {
    super({
      url: opts?.url ?? HIRO_MAINNET_DEFAULT,
      fetchFn: opts?.fetchFn
    });
    this.version = _common.TransactionVersion.Mainnet;
    this.chainId = _common.ChainID.Mainnet;
  }

}

exports.StacksMainnet = StacksMainnet;

class StacksTestnet extends StacksNetwork {
  constructor(opts) {
    super({
      url: opts?.url ?? HIRO_TESTNET_DEFAULT,
      fetchFn: opts?.fetchFn
    });
    this.version = _common.TransactionVersion.Testnet;
    this.chainId = _common.ChainID.Testnet;
  }

}

exports.StacksTestnet = StacksTestnet;

class StacksMocknet extends StacksNetwork {
  constructor(opts) {
    super({
      url: opts?.url ?? HIRO_MOCKNET_DEFAULT,
      fetchFn: opts?.fetchFn
    });
    this.version = _common.TransactionVersion.Testnet;
    this.chainId = _common.ChainID.Testnet;
  }

}

exports.StacksMocknet = StacksMocknet;
const StacksDevnet = StacksMocknet;
exports.StacksDevnet = StacksDevnet;

},{"./fetch":20,"@stacks/common":15}],23:[function(require,module,exports){
"use strict";

Object.defineProperty(exports, "__esModule", {
  value: true
});
exports.createMultiSigSpendingCondition = createMultiSigSpendingCondition;
exports.createSingleSigSpendingCondition = createSingleSigSpendingCondition;
exports.createSponsoredAuth = createSponsoredAuth;
exports.createStandardAuth = createStandardAuth;
exports.deserializeAuthorization = deserializeAuthorization;
exports.deserializeMultiSigSpendingCondition = deserializeMultiSigSpendingCondition;
exports.deserializeSingleSigSpendingCondition = deserializeSingleSigSpendingCondition;
exports.deserializeSpendingCondition = deserializeSpendingCondition;
exports.emptyMessageSignature = emptyMessageSignature;
exports.getFee = getFee;
exports.intoInitialSighashAuth = intoInitialSighashAuth;
exports.isSingleSig = isSingleSig;
exports.makeSigHashPreSign = makeSigHashPreSign;
exports.nextSignature = nextSignature;
exports.nextVerification = nextVerification;
exports.serializeAuthorization = serializeAuthorization;
exports.serializeMultiSigSpendingCondition = serializeMultiSigSpendingCondition;
exports.serializeSingleSigSpendingCondition = serializeSingleSigSpendingCondition;
exports.serializeSpendingCondition = serializeSpendingCondition;
exports.setFee = setFee;
exports.setNonce = setNonce;
exports.setSponsor = setSponsor;
exports.setSponsorNonce = setSponsorNonce;
exports.verifyOrigin = verifyOrigin;

var _common = require("@stacks/common");

var _constants = require("./constants");

var _utils = require("./utils");

var _signature = require("./signature");

var _types = require("./types");

var _keys = require("./keys");

var _errors = require("./errors");

function emptyMessageSignature() {
  return {
    type: _constants.StacksMessageType.MessageSignature,
    data: (0, _common.bytesToHex)(new Uint8Array(_constants.RECOVERABLE_ECDSA_SIG_LENGTH_BYTES))
  };
}

function createSingleSigSpendingCondition(hashMode, pubKey, nonce, fee) {
  const signer = (0, _types.addressFromPublicKeys)(0, hashMode, 1, [(0, _keys.createStacksPublicKey)(pubKey)]).hash160;
  const keyEncoding = (0, _keys.isCompressed)((0, _keys.createStacksPublicKey)(pubKey)) ? _constants.PubKeyEncoding.Compressed : _constants.PubKeyEncoding.Uncompressed;
  return {
    hashMode,
    signer,
    nonce: (0, _common.intToBigInt)(nonce, false),
    fee: (0, _common.intToBigInt)(fee, false),
    keyEncoding,
    signature: emptyMessageSignature()
  };
}

function createMultiSigSpendingCondition(hashMode, numSigs, pubKeys, nonce, fee) {
  const stacksPublicKeys = pubKeys.map(_keys.createStacksPublicKey);
  const signer = (0, _types.addressFromPublicKeys)(0, hashMode, numSigs, stacksPublicKeys).hash160;
  return {
    hashMode,
    signer,
    nonce: (0, _common.intToBigInt)(nonce, false),
    fee: (0, _common.intToBigInt)(fee, false),
    fields: [],
    signaturesRequired: numSigs
  };
}

function isSingleSig(condition) {
  return 'signature' in condition;
}

function clearCondition(condition) {
  const cloned = (0, _utils.cloneDeep)(condition);
  cloned.nonce = 0;
  cloned.fee = 0;

  if (isSingleSig(cloned)) {
    cloned.signature = emptyMessageSignature();
  } else {
    cloned.fields = [];
  }

  return { ...cloned,
    nonce: BigInt(0),
    fee: BigInt(0)
  };
}

function serializeSingleSigSpendingCondition(condition) {
  const bytesArray = [condition.hashMode, (0, _common.hexToBytes)(condition.signer), (0, _common.intToBytes)(condition.nonce, false, 8), (0, _common.intToBytes)(condition.fee, false, 8), condition.keyEncoding, (0, _signature.serializeMessageSignature)(condition.signature)];
  return (0, _common.concatArray)(bytesArray);
}

function serializeMultiSigSpendingCondition(condition) {
  const bytesArray = [condition.hashMode, (0, _common.hexToBytes)(condition.signer), (0, _common.intToBytes)(condition.nonce, false, 8), (0, _common.intToBytes)(condition.fee, false, 8)];
  const fields = (0, _types.createLPList)(condition.fields);
  bytesArray.push((0, _types.serializeLPList)(fields));
  const numSigs = new Uint8Array(2);
  (0, _common.writeUInt16BE)(numSigs, condition.signaturesRequired, 0);
  bytesArray.push(numSigs);
  return (0, _common.concatArray)(bytesArray);
}

function deserializeSingleSigSpendingCondition(hashMode, bytesReader) {
  const signer = (0, _common.bytesToHex)(bytesReader.readBytes(20));
  const nonce = BigInt(`0x${(0, _common.bytesToHex)(bytesReader.readBytes(8))}`);
  const fee = BigInt(`0x${(0, _common.bytesToHex)(bytesReader.readBytes(8))}`);
  const keyEncoding = bytesReader.readUInt8Enum(_constants.PubKeyEncoding, n => {
    throw new _errors.DeserializationError(`Could not parse ${n} as PubKeyEncoding`);
  });

  if (hashMode === _constants.AddressHashMode.SerializeP2WPKH && keyEncoding != _constants.PubKeyEncoding.Compressed) {
    throw new _errors.DeserializationError('Failed to parse singlesig spending condition: incomaptible hash mode and key encoding');
  }

  const signature = (0, _signature.deserializeMessageSignature)(bytesReader);
  return {
    hashMode,
    signer,
    nonce,
    fee,
    keyEncoding,
    signature
  };
}

function deserializeMultiSigSpendingCondition(hashMode, bytesReader) {
  const signer = (0, _common.bytesToHex)(bytesReader.readBytes(20));
  const nonce = BigInt('0x' + (0, _common.bytesToHex)(bytesReader.readBytes(8)));
  const fee = BigInt('0x' + (0, _common.bytesToHex)(bytesReader.readBytes(8)));
  const fields = (0, _types.deserializeLPList)(bytesReader, _constants.StacksMessageType.TransactionAuthField).values;
  let haveUncompressed = false;
  let numSigs = 0;

  for (const field of fields) {
    switch (field.contents.type) {
      case _constants.StacksMessageType.PublicKey:
        if (!(0, _keys.isCompressed)(field.contents)) haveUncompressed = true;
        break;

      case _constants.StacksMessageType.MessageSignature:
        if (field.pubKeyEncoding === _constants.PubKeyEncoding.Uncompressed) haveUncompressed = true;
        numSigs += 1;
        if (numSigs === 65536) throw new _errors.VerificationError('Failed to parse multisig spending condition: too many signatures');
        break;
    }
  }

  const signaturesRequired = bytesReader.readUInt16BE();
  if (haveUncompressed && hashMode === _constants.AddressHashMode.SerializeP2SH) throw new _errors.VerificationError('Uncompressed keys are not allowed in this hash mode');
  return {
    hashMode,
    signer,
    nonce,
    fee,
    fields,
    signaturesRequired
  };
}

function serializeSpendingCondition(condition) {
  if (isSingleSig(condition)) {
    return serializeSingleSigSpendingCondition(condition);
  }

  return serializeMultiSigSpendingCondition(condition);
}

function deserializeSpendingCondition(bytesReader) {
  const hashMode = bytesReader.readUInt8Enum(_constants.AddressHashMode, n => {
    throw new _errors.DeserializationError(`Could not parse ${n} as AddressHashMode`);
  });

  if (hashMode === _constants.AddressHashMode.SerializeP2PKH || hashMode === _constants.AddressHashMode.SerializeP2WPKH) {
    return deserializeSingleSigSpendingCondition(hashMode, bytesReader);
  } else {
    return deserializeMultiSigSpendingCondition(hashMode, bytesReader);
  }
}

function makeSigHashPreSign(curSigHash, authType, fee, nonce) {
  const hashLength = 32 + 1 + 8 + 8;
  const sigHash = curSigHash + (0, _common.bytesToHex)(new Uint8Array([authType])) + (0, _common.bytesToHex)((0, _common.intToBytes)(fee, false, 8)) + (0, _common.bytesToHex)((0, _common.intToBytes)(nonce, false, 8));

  if ((0, _common.hexToBytes)(sigHash).byteLength !== hashLength) {
    throw Error('Invalid signature hash length');
  }

  return (0, _utils.txidFromData)((0, _common.hexToBytes)(sigHash));
}

function makeSigHashPostSign(curSigHash, pubKey, signature) {
  const hashLength = 32 + 1 + _constants.RECOVERABLE_ECDSA_SIG_LENGTH_BYTES;
  const pubKeyEncoding = (0, _keys.isCompressed)(pubKey) ? _constants.PubKeyEncoding.Compressed : _constants.PubKeyEncoding.Uncompressed;
  const sigHash = curSigHash + (0, _utils.leftPadHex)(pubKeyEncoding.toString(16)) + signature.data;
  const sigHashBytes = (0, _common.hexToBytes)(sigHash);

  if (sigHashBytes.byteLength > hashLength) {
    throw Error('Invalid signature hash length');
  }

  return (0, _utils.txidFromData)(sigHashBytes);
}

function nextSignature(curSigHash, authType, fee, nonce, privateKey) {
  const sigHashPreSign = makeSigHashPreSign(curSigHash, authType, fee, nonce);
  const signature = (0, _keys.signWithKey)(privateKey, sigHashPreSign);
  const publicKey = (0, _keys.getPublicKey)(privateKey);
  const nextSigHash = makeSigHashPostSign(sigHashPreSign, publicKey, signature);
  return {
    nextSig: signature,
    nextSigHash
  };
}

function nextVerification(initialSigHash, authType, fee, nonce, pubKeyEncoding, signature) {
  const sigHashPreSign = makeSigHashPreSign(initialSigHash, authType, fee, nonce);
  const publicKey = (0, _keys.createStacksPublicKey)((0, _keys.publicKeyFromSignatureVrs)(sigHashPreSign, signature, pubKeyEncoding));
  const nextSigHash = makeSigHashPostSign(sigHashPreSign, publicKey, signature);
  return {
    pubKey: publicKey,
    nextSigHash
  };
}

function newInitialSigHash() {
  const spendingCondition = createSingleSigSpendingCondition(_constants.AddressHashMode.SerializeP2PKH, '', 0, 0);
  spendingCondition.signer = (0, _types.createEmptyAddress)().hash160;
  spendingCondition.keyEncoding = _constants.PubKeyEncoding.Compressed;
  spendingCondition.signature = emptyMessageSignature();
  return spendingCondition;
}

function verify(condition, initialSigHash, authType) {
  if (isSingleSig(condition)) {
    return verifySingleSig(condition, initialSigHash, authType);
  } else {
    return verifyMultiSig(condition, initialSigHash, authType);
  }
}

function verifySingleSig(condition, initialSigHash, authType) {
  const {
    pubKey,
    nextSigHash
  } = nextVerification(initialSigHash, authType, condition.fee, condition.nonce, condition.keyEncoding, condition.signature);
  const addrBytes = (0, _types.addressFromPublicKeys)(0, condition.hashMode, 1, [pubKey]).hash160;
  if (addrBytes !== condition.signer) throw new _errors.VerificationError(`Signer hash does not equal hash of public key(s): ${addrBytes} != ${condition.signer}`);
  return nextSigHash;
}

function verifyMultiSig(condition, initialSigHash, authType) {
  const publicKeys = [];
  let curSigHash = initialSigHash;
  let haveUncompressed = false;
  let numSigs = 0;

  for (const field of condition.fields) {
    let foundPubKey;

    switch (field.contents.type) {
      case _constants.StacksMessageType.PublicKey:
        if (!(0, _keys.isCompressed)(field.contents)) haveUncompressed = true;
        foundPubKey = field.contents;
        break;

      case _constants.StacksMessageType.MessageSignature:
        if (field.pubKeyEncoding === _constants.PubKeyEncoding.Uncompressed) haveUncompressed = true;
        const {
          pubKey,
          nextSigHash
        } = nextVerification(curSigHash, authType, condition.fee, condition.nonce, field.pubKeyEncoding, field.contents);
        curSigHash = nextSigHash;
        foundPubKey = pubKey;
        numSigs += 1;
        if (numSigs === 65536) throw new _errors.VerificationError('Too many signatures');
        break;
    }

    publicKeys.push(foundPubKey);
  }

  if (numSigs !== condition.signaturesRequired) throw new _errors.VerificationError('Incorrect number of signatures');
  if (haveUncompressed && condition.hashMode === _constants.AddressHashMode.SerializeP2SH) throw new _errors.VerificationError('Uncompressed keys are not allowed in this hash mode');
  const addrBytes = (0, _types.addressFromPublicKeys)(0, condition.hashMode, condition.signaturesRequired, publicKeys).hash160;
  if (addrBytes !== condition.signer) throw new _errors.VerificationError(`Signer hash does not equal hash of public key(s): ${addrBytes} != ${condition.signer}`);
  return curSigHash;
}

function createStandardAuth(spendingCondition) {
  return {
    authType: _constants.AuthType.Standard,
    spendingCondition
  };
}

function createSponsoredAuth(spendingCondition, sponsorSpendingCondition) {
  return {
    authType: _constants.AuthType.Sponsored,
    spendingCondition,
    sponsorSpendingCondition: sponsorSpendingCondition ? sponsorSpendingCondition : createSingleSigSpendingCondition(_constants.AddressHashMode.SerializeP2PKH, '0'.repeat(66), 0, 0)
  };
}

function intoInitialSighashAuth(auth) {
  if (auth.spendingCondition) {
    switch (auth.authType) {
      case _constants.AuthType.Standard:
        return createStandardAuth(clearCondition(auth.spendingCondition));

      case _constants.AuthType.Sponsored:
        return createSponsoredAuth(clearCondition(auth.spendingCondition), newInitialSigHash());

      default:
        throw new _errors.SigningError('Unexpected authorization type for signing');
    }
  }

  throw new Error('Authorization missing SpendingCondition');
}

function verifyOrigin(auth, initialSigHash) {
  switch (auth.authType) {
    case _constants.AuthType.Standard:
      return verify(auth.spendingCondition, initialSigHash, _constants.AuthType.Standard);

    case _constants.AuthType.Sponsored:
      return verify(auth.spendingCondition, initialSigHash, _constants.AuthType.Standard);

    default:
      throw new _errors.SigningError('Invalid origin auth type');
  }
}

function setFee(auth, amount) {
  switch (auth.authType) {
    case _constants.AuthType.Standard:
      const spendingCondition = { ...auth.spendingCondition,
        fee: (0, _common.intToBigInt)(amount, false)
      };
      return { ...auth,
        spendingCondition
      };

    case _constants.AuthType.Sponsored:
      const sponsorSpendingCondition = { ...auth.sponsorSpendingCondition,
        fee: (0, _common.intToBigInt)(amount, false)
      };
      return { ...auth,
        sponsorSpendingCondition
      };
  }
}

function getFee(auth) {
  switch (auth.authType) {
    case _constants.AuthType.Standard:
      return auth.spendingCondition.fee;

    case _constants.AuthType.Sponsored:
      return auth.sponsorSpendingCondition.fee;
  }
}

function setNonce(auth, nonce) {
  const spendingCondition = { ...auth.spendingCondition,
    nonce: (0, _common.intToBigInt)(nonce, false)
  };
  return { ...auth,
    spendingCondition
  };
}

function setSponsorNonce(auth, nonce) {
  const sponsorSpendingCondition = { ...auth.sponsorSpendingCondition,
    nonce: (0, _common.intToBigInt)(nonce, false)
  };
  return { ...auth,
    sponsorSpendingCondition
  };
}

function setSponsor(auth, sponsorSpendingCondition) {
  const sc = { ...sponsorSpendingCondition,
    nonce: (0, _common.intToBigInt)(sponsorSpendingCondition.nonce, false),
    fee: (0, _common.intToBigInt)(sponsorSpendingCondition.fee, false)
  };
  return { ...auth,
    sponsorSpendingCondition: sc
  };
}

function serializeAuthorization(auth) {
  const bytesArray = [];
  bytesArray.push(auth.authType);

  switch (auth.authType) {
    case _constants.AuthType.Standard:
      bytesArray.push(serializeSpendingCondition(auth.spendingCondition));
      break;

    case _constants.AuthType.Sponsored:
      bytesArray.push(serializeSpendingCondition(auth.spendingCondition));
      bytesArray.push(serializeSpendingCondition(auth.sponsorSpendingCondition));
      break;
  }

  return (0, _common.concatArray)(bytesArray);
}

function deserializeAuthorization(bytesReader) {
  const authType = bytesReader.readUInt8Enum(_constants.AuthType, n => {
    throw new _errors.DeserializationError(`Could not parse ${n} as AuthType`);
  });
  let spendingCondition;

  switch (authType) {
    case _constants.AuthType.Standard:
      spendingCondition = deserializeSpendingCondition(bytesReader);
      return createStandardAuth(spendingCondition);

    case _constants.AuthType.Sponsored:
      spendingCondition = deserializeSpendingCondition(bytesReader);
      const sponsorSpendingCondition = deserializeSpendingCondition(bytesReader);
      return createSponsoredAuth(spendingCondition, sponsorSpendingCondition);
  }
}

},{"./constants":43,"./errors":45,"./keys":47,"./signature":52,"./types":56,"./utils":57,"@stacks/common":15}],24:[function(require,module,exports){
"use strict";

Object.defineProperty(exports, "__esModule", {
  value: true
});
exports.broadcastRawTransaction = broadcastRawTransaction;
exports.broadcastTransaction = broadcastTransaction;
exports.callReadOnlyFunction = callReadOnlyFunction;
exports.estimateContractDeploy = estimateContractDeploy;
exports.estimateContractFunctionCall = estimateContractFunctionCall;
exports.estimateTransaction = estimateTransaction;
exports.estimateTransactionByteLength = estimateTransactionByteLength;
exports.estimateTransactionFeeWithFallback = estimateTransactionFeeWithFallback;
exports.estimateTransfer = estimateTransfer;
exports.estimateTransferUnsafe = estimateTransferUnsafe;
exports.getAbi = getAbi;
exports.getContractMapEntry = getContractMapEntry;
exports.getNonce = getNonce;
exports.makeContractCall = makeContractCall;
exports.makeContractDeploy = makeContractDeploy;
exports.makeContractFungiblePostCondition = makeContractFungiblePostCondition;
exports.makeContractNonFungiblePostCondition = makeContractNonFungiblePostCondition;
exports.makeContractSTXPostCondition = makeContractSTXPostCondition;
exports.makeSTXTokenTransfer = makeSTXTokenTransfer;
exports.makeStandardFungiblePostCondition = makeStandardFungiblePostCondition;
exports.makeStandardNonFungiblePostCondition = makeStandardNonFungiblePostCondition;
exports.makeStandardSTXPostCondition = makeStandardSTXPostCondition;
exports.makeUnsignedContractCall = makeUnsignedContractCall;
exports.makeUnsignedContractDeploy = makeUnsignedContractDeploy;
exports.makeUnsignedSTXTokenTransfer = makeUnsignedSTXTokenTransfer;
exports.sponsorTransaction = sponsorTransaction;

var _common = require("@stacks/common");

var _network = require("@stacks/network");

var _c32check = require("c32check");

var _authorization = require("./authorization");

var _clarity = require("./clarity");

var _constants = require("./constants");

var _contractAbi = require("./contract-abi");

var _errors = require("./errors");

var _keys = require("./keys");

var _payload = require("./payload");

var _postcondition = require("./postcondition");

var _postconditionTypes = require("./postcondition-types");

var _signer = require("./signer");

var _transaction = require("./transaction");

var _types = require("./types");

var _utils = require("./utils");

async function getNonce(address, network) {
  const derivedNetwork = _network.StacksNetwork.fromNameOrNetwork(network ?? new _network.StacksMainnet());

  const url = derivedNetwork.getAccountApiUrl(address);
  const response = await derivedNetwork.fetchFn(url);

  if (!response.ok) {
    let msg = '';

    try {
      msg = await response.text();
    } catch (error) {}

    throw new Error(`Error fetching nonce. Response ${response.status}: ${response.statusText}. Attempted to fetch ${url} and failed with the message: "${msg}"`);
  }

  const responseText = await response.text();
  const result = JSON.parse(responseText);
  return BigInt(result.nonce);
}

async function estimateTransfer(transaction, network) {
  if (transaction.payload.payloadType !== _constants.PayloadType.TokenTransfer) {
    throw new Error(`Transaction fee estimation only possible with ${_constants.PayloadType[_constants.PayloadType.TokenTransfer]} transactions. Invoked with: ${_constants.PayloadType[transaction.payload.payloadType]}`);
  }

  return estimateTransferUnsafe(transaction, network);
}

async function estimateTransferUnsafe(transaction, network) {
  const requestHeaders = {
    Accept: 'application/text'
  };
  const fetchOptions = {
    method: 'GET',
    headers: requestHeaders
  };

  const derivedNetwork = _network.StacksNetwork.fromNameOrNetwork(network ?? deriveNetwork(transaction));

  const url = derivedNetwork.getTransferFeeEstimateApiUrl();
  const response = await derivedNetwork.fetchFn(url, fetchOptions);

  if (!response.ok) {
    let msg = '';

    try {
      msg = await response.text();
    } catch (error) {}

    throw new Error(`Error estimating transaction fee. Response ${response.status}: ${response.statusText}. Attempted to fetch ${url} and failed with the message: "${msg}"`);
  }

  const feeRateResult = await response.text();
  const txBytes = BigInt(transaction.serialize().byteLength);
  const feeRate = BigInt(feeRateResult);
  return feeRate * txBytes;
}

async function estimateTransaction(transactionPayload, estimatedLen, network) {
  const options = {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      transaction_payload: (0, _common.bytesToHex)((0, _payload.serializePayload)(transactionPayload)),
      ...(estimatedLen ? {
        estimated_len: estimatedLen
      } : {})
    })
  };

  const derivedNetwork = _network.StacksNetwork.fromNameOrNetwork(network ?? new _network.StacksMainnet());

  const url = derivedNetwork.getTransactionFeeEstimateApiUrl();
  const response = await derivedNetwork.fetchFn(url, options);

  if (!response.ok) {
    const body = await response.text().then(str => {
      try {
        return JSON.parse(str);
      } catch (error) {
        return str;
      }
    });

    if (body?.reason === 'NoEstimateAvailable' || typeof body === 'string' && body.includes('NoEstimateAvailable')) {
      throw new _errors.NoEstimateAvailableError(body?.reason_data?.message ?? '');
    }

    throw new Error(`Error estimating transaction fee. Response ${response.status}: ${response.statusText}. Attempted to fetch ${url} and failed with the message: "${body}"`);
  }

  const data = await response.json();
  return data.estimations;
}

async function broadcastTransaction(transaction, network, attachment) {
  const rawTx = transaction.serialize();

  const derivedNetwork = _network.StacksNetwork.fromNameOrNetwork(network ?? deriveNetwork(transaction));

  const url = derivedNetwork.getBroadcastApiUrl();
  return broadcastRawTransaction(rawTx, url, attachment, derivedNetwork.fetchFn);
}

async function broadcastRawTransaction(rawTx, url, attachment, fetchFn = (0, _network.createFetchFn)()) {
  const options = {
    method: 'POST',
    headers: {
      'Content-Type': attachment ? 'application/json' : 'application/octet-stream'
    },
    body: attachment ? JSON.stringify({
      tx: (0, _common.bytesToHex)(rawTx),
      attachment: (0, _common.bytesToHex)(attachment)
    }) : rawTx
  };
  const response = await fetchFn(url, options);

  if (!response.ok) {
    try {
      return await response.json();
    } catch (e) {
      throw Error(`Failed to broadcast transaction: ${e.message}`);
    }
  }

  const text = await response.text();
  const txid = text.replace(/["]+/g, '');
  if (!(0, _utils.validateTxId)(txid)) throw new Error(text);
  return {
    txid
  };
}

async function getAbi(address, contractName, network) {
  const options = {
    method: 'GET'
  };

  const derivedNetwork = _network.StacksNetwork.fromNameOrNetwork(network);

  const url = derivedNetwork.getAbiApiUrl(address, contractName);
  const response = await derivedNetwork.fetchFn(url, options);

  if (!response.ok) {
    const msg = await response.text().catch(() => '');
    throw new Error(`Error fetching contract ABI for contract "${contractName}" at address ${address}. Response ${response.status}: ${response.statusText}. Attempted to fetch ${url} and failed with the message: "${msg}"`);
  }

  return JSON.parse(await response.text());
}

function deriveNetwork(transaction) {
  switch (transaction.version) {
    case _constants.TransactionVersion.Mainnet:
      return new _network.StacksMainnet();

    case _constants.TransactionVersion.Testnet:
      return new _network.StacksTestnet();
  }
}

async function makeUnsignedSTXTokenTransfer(txOptions) {
  const defaultOptions = {
    fee: BigInt(0),
    nonce: BigInt(0),
    network: new _network.StacksMainnet(),
    memo: '',
    sponsored: false
  };
  const options = Object.assign(defaultOptions, txOptions);
  const payload = (0, _payload.createTokenTransferPayload)(options.recipient, options.amount, options.memo);
  let authorization = null;
  let spendingCondition = null;

  if ('publicKey' in options) {
    spendingCondition = (0, _authorization.createSingleSigSpendingCondition)(_constants.AddressHashMode.SerializeP2PKH, options.publicKey, options.nonce, options.fee);
  } else {
    spendingCondition = (0, _authorization.createMultiSigSpendingCondition)(_constants.AddressHashMode.SerializeP2SH, options.numSignatures, options.publicKeys, options.nonce, options.fee);
  }

  if (options.sponsored) {
    authorization = (0, _authorization.createSponsoredAuth)(spendingCondition);
  } else {
    authorization = (0, _authorization.createStandardAuth)(spendingCondition);
  }

  const network = _network.StacksNetwork.fromNameOrNetwork(options.network);

  const transaction = new _transaction.StacksTransaction(network.version, authorization, payload, undefined, undefined, options.anchorMode, network.chainId);

  if (txOptions.fee === undefined || txOptions.fee === null) {
    const fee = await estimateTransactionFeeWithFallback(transaction, network);
    transaction.setFee(fee);
  }

  if (txOptions.nonce === undefined || txOptions.nonce === null) {
    const addressVersion = options.network.version === _constants.TransactionVersion.Mainnet ? _constants.AddressVersion.MainnetSingleSig : _constants.AddressVersion.TestnetSingleSig;
    const senderAddress = (0, _c32check.c32address)(addressVersion, transaction.auth.spendingCondition.signer);
    const txNonce = await getNonce(senderAddress, options.network);
    transaction.setNonce(txNonce);
  }

  return transaction;
}

async function makeSTXTokenTransfer(txOptions) {
  if ('senderKey' in txOptions) {
    const publicKey = (0, _keys.publicKeyToString)((0, _keys.getPublicKey)((0, _keys.createStacksPrivateKey)(txOptions.senderKey)));
    const options = (0, _utils.omit)(txOptions, 'senderKey');
    const transaction = await makeUnsignedSTXTokenTransfer({
      publicKey,
      ...options
    });
    const privKey = (0, _keys.createStacksPrivateKey)(txOptions.senderKey);
    const signer = new _signer.TransactionSigner(transaction);
    signer.signOrigin(privKey);
    return transaction;
  } else {
    const options = (0, _utils.omit)(txOptions, 'signerKeys');
    const transaction = await makeUnsignedSTXTokenTransfer(options);
    const signer = new _signer.TransactionSigner(transaction);
    let pubKeys = txOptions.publicKeys;

    for (const key of txOptions.signerKeys) {
      const pubKey = (0, _keys.pubKeyfromPrivKey)(key);
      pubKeys = pubKeys.filter(pk => pk !== (0, _common.bytesToHex)(pubKey.data));
      signer.signOrigin((0, _keys.createStacksPrivateKey)(key));
    }

    for (const key of pubKeys) {
      signer.appendOrigin((0, _keys.publicKeyFromBytes)((0, _common.hexToBytes)(key)));
    }

    return transaction;
  }
}

async function estimateContractDeploy(transaction, network) {
  if (transaction.payload.payloadType !== _constants.PayloadType.SmartContract && transaction.payload.payloadType !== _constants.PayloadType.VersionedSmartContract) {
    throw new Error(`Contract deploy fee estimation only possible with ${_constants.PayloadType[_constants.PayloadType.SmartContract]} transactions. Invoked with: ${_constants.PayloadType[transaction.payload.payloadType]}`);
  }

  const requestHeaders = {
    Accept: 'application/text'
  };
  const fetchOptions = {
    method: 'GET',
    headers: requestHeaders
  };

  const derivedNetwork = _network.StacksNetwork.fromNameOrNetwork(network ?? deriveNetwork(transaction));

  const url = derivedNetwork.getTransferFeeEstimateApiUrl();
  const response = await derivedNetwork.fetchFn(url, fetchOptions);

  if (!response.ok) {
    const msg = await response.text().catch(() => '');
    throw new Error(`Error estimating contract deploy fee. Response ${response.status}: ${response.statusText}. Attempted to fetch ${url} and failed with the message: "${msg}"`);
  }

  const feeRateResult = await response.text();
  const txBytes = (0, _common.intToBigInt)(transaction.serialize().byteLength, false);
  const feeRate = (0, _common.intToBigInt)(feeRateResult, false);
  return feeRate * txBytes;
}

async function makeContractDeploy(txOptions) {
  if ('senderKey' in txOptions) {
    const publicKey = (0, _keys.publicKeyToString)((0, _keys.getPublicKey)((0, _keys.createStacksPrivateKey)(txOptions.senderKey)));
    const options = (0, _utils.omit)(txOptions, 'senderKey');
    const transaction = await makeUnsignedContractDeploy({
      publicKey,
      ...options
    });
    const privKey = (0, _keys.createStacksPrivateKey)(txOptions.senderKey);
    const signer = new _signer.TransactionSigner(transaction);
    signer.signOrigin(privKey);
    return transaction;
  } else {
    const options = (0, _utils.omit)(txOptions, 'signerKeys');
    const transaction = await makeUnsignedContractDeploy(options);
    const signer = new _signer.TransactionSigner(transaction);
    let pubKeys = txOptions.publicKeys;

    for (const key of txOptions.signerKeys) {
      const pubKey = (0, _keys.pubKeyfromPrivKey)(key);
      pubKeys = pubKeys.filter(pk => pk !== (0, _common.bytesToHex)(pubKey.data));
      signer.signOrigin((0, _keys.createStacksPrivateKey)(key));
    }

    for (const key of pubKeys) {
      signer.appendOrigin((0, _keys.publicKeyFromBytes)((0, _common.hexToBytes)(key)));
    }

    return transaction;
  }
}

async function makeUnsignedContractDeploy(txOptions) {
  const defaultOptions = {
    fee: BigInt(0),
    nonce: BigInt(0),
    network: new _network.StacksMainnet(),
    postConditionMode: _constants.PostConditionMode.Deny,
    sponsored: false,
    clarityVersion: _constants.ClarityVersion.Clarity2
  };
  const options = Object.assign(defaultOptions, txOptions);
  const payload = (0, _payload.createSmartContractPayload)(options.contractName, options.codeBody, options.clarityVersion);
  let authorization = null;
  let spendingCondition = null;

  if ('publicKey' in options) {
    spendingCondition = (0, _authorization.createSingleSigSpendingCondition)(_constants.AddressHashMode.SerializeP2PKH, options.publicKey, options.nonce, options.fee);
  } else {
    spendingCondition = (0, _authorization.createMultiSigSpendingCondition)(_constants.AddressHashMode.SerializeP2SH, options.numSignatures, options.publicKeys, options.nonce, options.fee);
  }

  if (options.sponsored) {
    authorization = (0, _authorization.createSponsoredAuth)(spendingCondition);
  } else {
    authorization = (0, _authorization.createStandardAuth)(spendingCondition);
  }

  const network = _network.StacksNetwork.fromNameOrNetwork(options.network);

  const postConditions = [];

  if (options.postConditions && options.postConditions.length > 0) {
    options.postConditions.forEach(postCondition => {
      postConditions.push(postCondition);
    });
  }

  const lpPostConditions = (0, _types.createLPList)(postConditions);
  const transaction = new _transaction.StacksTransaction(network.version, authorization, payload, lpPostConditions, options.postConditionMode, options.anchorMode, network.chainId);

  if (txOptions.fee === undefined || txOptions.fee === null) {
    const fee = await estimateTransactionFeeWithFallback(transaction, network);
    transaction.setFee(fee);
  }

  if (txOptions.nonce === undefined || txOptions.nonce === null) {
    const addressVersion = options.network.version === _constants.TransactionVersion.Mainnet ? _constants.AddressVersion.MainnetSingleSig : _constants.AddressVersion.TestnetSingleSig;
    const senderAddress = (0, _c32check.c32address)(addressVersion, transaction.auth.spendingCondition.signer);
    const txNonce = await getNonce(senderAddress, options.network);
    transaction.setNonce(txNonce);
  }

  return transaction;
}

async function estimateContractFunctionCall(transaction, network) {
  if (transaction.payload.payloadType !== _constants.PayloadType.ContractCall) {
    throw new Error(`Contract call fee estimation only possible with ${_constants.PayloadType[_constants.PayloadType.ContractCall]} transactions. Invoked with: ${_constants.PayloadType[transaction.payload.payloadType]}`);
  }

  const requestHeaders = {
    Accept: 'application/text'
  };
  const fetchOptions = {
    method: 'GET',
    headers: requestHeaders
  };

  const derivedNetwork = _network.StacksNetwork.fromNameOrNetwork(network ?? deriveNetwork(transaction));

  const url = derivedNetwork.getTransferFeeEstimateApiUrl();
  const response = await derivedNetwork.fetchFn(url, fetchOptions);

  if (!response.ok) {
    const msg = await response.text().catch(() => '');
    throw new Error(`Error estimating contract call fee. Response ${response.status}: ${response.statusText}. Attempted to fetch ${url} and failed with the message: "${msg}"`);
  }

  const feeRateResult = await response.text();
  const txBytes = (0, _common.intToBigInt)(transaction.serialize().byteLength, false);
  const feeRate = (0, _common.intToBigInt)(feeRateResult, false);
  return feeRate * txBytes;
}

async function makeUnsignedContractCall(txOptions) {
  const defaultOptions = {
    fee: BigInt(0),
    nonce: BigInt(0),
    network: new _network.StacksMainnet(),
    postConditionMode: _constants.PostConditionMode.Deny,
    sponsored: false
  };
  const options = Object.assign(defaultOptions, txOptions);
  const payload = (0, _payload.createContractCallPayload)(options.contractAddress, options.contractName, options.functionName, options.functionArgs);

  if (options?.validateWithAbi) {
    let abi;

    if (typeof options.validateWithAbi === 'boolean') {
      if (options?.network) {
        abi = await getAbi(options.contractAddress, options.contractName, options.network);
      } else {
        throw new Error('Network option must be provided in order to validate with ABI');
      }
    } else {
      abi = options.validateWithAbi;
    }

    (0, _contractAbi.validateContractCall)(payload, abi);
  }

  let spendingCondition = null;
  let authorization = null;

  if ('publicKey' in options) {
    spendingCondition = (0, _authorization.createSingleSigSpendingCondition)(_constants.AddressHashMode.SerializeP2PKH, options.publicKey, options.nonce, options.fee);
  } else {
    spendingCondition = (0, _authorization.createMultiSigSpendingCondition)(_constants.AddressHashMode.SerializeP2SH, options.numSignatures, options.publicKeys, options.nonce, options.fee);
  }

  if (options.sponsored) {
    authorization = (0, _authorization.createSponsoredAuth)(spendingCondition);
  } else {
    authorization = (0, _authorization.createStandardAuth)(spendingCondition);
  }

  const network = _network.StacksNetwork.fromNameOrNetwork(options.network);

  const postConditions = [];

  if (options.postConditions && options.postConditions.length > 0) {
    options.postConditions.forEach(postCondition => {
      postConditions.push(postCondition);
    });
  }

  const lpPostConditions = (0, _types.createLPList)(postConditions);
  const transaction = new _transaction.StacksTransaction(network.version, authorization, payload, lpPostConditions, options.postConditionMode, options.anchorMode, network.chainId);

  if (txOptions.fee === undefined || txOptions.fee === null) {
    const fee = await estimateTransactionFeeWithFallback(transaction, network);
    transaction.setFee(fee);
  }

  if (txOptions.nonce === undefined || txOptions.nonce === null) {
    const addressVersion = network.version === _constants.TransactionVersion.Mainnet ? _constants.AddressVersion.MainnetSingleSig : _constants.AddressVersion.TestnetSingleSig;
    const senderAddress = (0, _c32check.c32address)(addressVersion, transaction.auth.spendingCondition.signer);
    const txNonce = await getNonce(senderAddress, network);
    transaction.setNonce(txNonce);
  }

  return transaction;
}

async function makeContractCall(txOptions) {
  if ('senderKey' in txOptions) {
    const publicKey = (0, _keys.publicKeyToString)((0, _keys.getPublicKey)((0, _keys.createStacksPrivateKey)(txOptions.senderKey)));
    const options = (0, _utils.omit)(txOptions, 'senderKey');
    const transaction = await makeUnsignedContractCall({
      publicKey,
      ...options
    });
    const privKey = (0, _keys.createStacksPrivateKey)(txOptions.senderKey);
    const signer = new _signer.TransactionSigner(transaction);
    signer.signOrigin(privKey);
    return transaction;
  } else {
    const options = (0, _utils.omit)(txOptions, 'signerKeys');
    const transaction = await makeUnsignedContractCall(options);
    const signer = new _signer.TransactionSigner(transaction);
    let pubKeys = txOptions.publicKeys;

    for (const key of txOptions.signerKeys) {
      const pubKey = (0, _keys.pubKeyfromPrivKey)(key);
      pubKeys = pubKeys.filter(pk => pk !== (0, _common.bytesToHex)(pubKey.data));
      signer.signOrigin((0, _keys.createStacksPrivateKey)(key));
    }

    for (const key of pubKeys) {
      signer.appendOrigin((0, _keys.publicKeyFromBytes)((0, _common.hexToBytes)(key)));
    }

    return transaction;
  }
}

function makeStandardSTXPostCondition(address, conditionCode, amount) {
  return (0, _postcondition.createSTXPostCondition)((0, _postconditionTypes.createStandardPrincipal)(address), conditionCode, amount);
}

function makeContractSTXPostCondition(address, contractName, conditionCode, amount) {
  return (0, _postcondition.createSTXPostCondition)((0, _postconditionTypes.createContractPrincipal)(address, contractName), conditionCode, amount);
}

function makeStandardFungiblePostCondition(address, conditionCode, amount, assetInfo) {
  return (0, _postcondition.createFungiblePostCondition)((0, _postconditionTypes.createStandardPrincipal)(address), conditionCode, amount, assetInfo);
}

function makeContractFungiblePostCondition(address, contractName, conditionCode, amount, assetInfo) {
  return (0, _postcondition.createFungiblePostCondition)((0, _postconditionTypes.createContractPrincipal)(address, contractName), conditionCode, amount, assetInfo);
}

function makeStandardNonFungiblePostCondition(address, conditionCode, assetInfo, assetId) {
  return (0, _postcondition.createNonFungiblePostCondition)((0, _postconditionTypes.createStandardPrincipal)(address), conditionCode, assetInfo, assetId);
}

function makeContractNonFungiblePostCondition(address, contractName, conditionCode, assetInfo, assetId) {
  return (0, _postcondition.createNonFungiblePostCondition)((0, _postconditionTypes.createContractPrincipal)(address, contractName), conditionCode, assetInfo, assetId);
}

async function callReadOnlyFunction(readOnlyFunctionOptions) {
  const defaultOptions = {
    network: new _network.StacksMainnet()
  };
  const options = Object.assign(defaultOptions, readOnlyFunctionOptions);
  const {
    contractName,
    contractAddress,
    functionName,
    functionArgs,
    senderAddress
  } = options;

  const network = _network.StacksNetwork.fromNameOrNetwork(options.network);

  const url = network.getReadOnlyFunctionCallApiUrl(contractAddress, contractName, functionName);
  const args = functionArgs.map(arg => (0, _utils.cvToHex)(arg));
  const body = JSON.stringify({
    sender: senderAddress,
    arguments: args
  });
  const response = await network.fetchFn(url, {
    method: 'POST',
    body,
    headers: {
      'Content-Type': 'application/json'
    }
  });

  if (!response.ok) {
    const msg = await response.text().catch(() => '');
    throw new Error(`Error calling read-only function. Response ${response.status}: ${response.statusText}. Attempted to fetch ${url} and failed with the message: "${msg}"`);
  }

  return response.json().then(responseJson => (0, _utils.parseReadOnlyResponse)(responseJson));
}

async function getContractMapEntry(getContractMapEntryOptions) {
  const defaultOptions = {
    network: new _network.StacksMainnet()
  };
  const {
    contractAddress,
    contractName,
    mapName,
    mapKey,
    network
  } = Object.assign(defaultOptions, getContractMapEntryOptions);

  const derivedNetwork = _network.StacksNetwork.fromNameOrNetwork(network);

  const url = derivedNetwork.getMapEntryUrl(contractAddress, contractName, mapName);
  const serializedKeyBytes = (0, _clarity.serializeCV)(mapKey);
  const serializedKeyHex = '0x' + (0, _common.bytesToHex)(serializedKeyBytes);
  const fetchOptions = {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Accept: 'application/json'
    },
    body: JSON.stringify(serializedKeyHex)
  };
  const response = await derivedNetwork.fetchFn(url, fetchOptions);

  if (!response.ok) {
    const msg = await response.text().catch(() => '');
    throw new Error(`Error fetching map entry for map "${mapName}" in contract "${contractName}" at address ${contractAddress}, using map key "${serializedKeyHex}". Response ${response.status}: ${response.statusText}. Attempted to fetch ${url} and failed with the message: "${msg}"`);
  }

  const responseBody = await response.text();
  const responseJson = JSON.parse(responseBody);

  if (!responseJson.data) {
    throw new Error(`Error fetching map entry for map "${mapName}" in contract "${contractName}" at address ${contractAddress}, using map key "${serializedKeyHex}". Response ${response.status}: ${response.statusText}. Attempted to fetch ${url} and failed with the response: "${responseBody}"`);
  }

  let deserializedCv;

  try {
    deserializedCv = (0, _clarity.deserializeCV)(responseJson.data);
  } catch (error) {
    throw new Error(`Error deserializing Clarity value "${responseJson.data}": ${error}`);
  }

  return deserializedCv;
}

async function sponsorTransaction(sponsorOptions) {
  const defaultOptions = {
    fee: 0,
    sponsorNonce: 0,
    sponsorAddressHashmode: _constants.AddressHashMode.SerializeP2PKH,
    network: sponsorOptions.transaction.version === _constants.TransactionVersion.Mainnet ? new _network.StacksMainnet() : new _network.StacksTestnet()
  };
  const options = Object.assign(defaultOptions, sponsorOptions);

  const network = _network.StacksNetwork.fromNameOrNetwork(options.network);

  const sponsorPubKey = (0, _keys.pubKeyfromPrivKey)(options.sponsorPrivateKey);

  if (sponsorOptions.fee === undefined || sponsorOptions.fee === null) {
    let txFee = 0;

    switch (options.transaction.payload.payloadType) {
      case _constants.PayloadType.TokenTransfer:
      case _constants.PayloadType.SmartContract:
      case _constants.PayloadType.VersionedSmartContract:
      case _constants.PayloadType.ContractCall:
        const estimatedLen = estimateTransactionByteLength(options.transaction);

        try {
          txFee = (await estimateTransaction(options.transaction.payload, estimatedLen, network))[1].fee;
        } catch (e) {
          throw e;
        }

        break;

      default:
        throw new Error(`Sponsored transactions not supported for transaction type ${_constants.PayloadType[options.transaction.payload.payloadType]}`);
    }

    options.transaction.setFee(txFee);
    options.fee = txFee;
  }

  if (sponsorOptions.sponsorNonce === undefined || sponsorOptions.sponsorNonce === null) {
    const addressVersion = network.version === _constants.TransactionVersion.Mainnet ? _constants.AddressVersion.MainnetSingleSig : _constants.AddressVersion.TestnetSingleSig;
    const senderAddress = (0, _keys.publicKeyToAddress)(addressVersion, sponsorPubKey);
    const sponsorNonce = await getNonce(senderAddress, network);
    options.sponsorNonce = sponsorNonce;
  }

  const sponsorSpendingCondition = (0, _authorization.createSingleSigSpendingCondition)(options.sponsorAddressHashmode, (0, _keys.publicKeyToString)(sponsorPubKey), options.sponsorNonce, options.fee);
  options.transaction.setSponsor(sponsorSpendingCondition);
  const privKey = (0, _keys.createStacksPrivateKey)(options.sponsorPrivateKey);

  const signer = _signer.TransactionSigner.createSponsorSigner(options.transaction, sponsorSpendingCondition);

  signer.signSponsor(privKey);
  return signer.transaction;
}

function estimateTransactionByteLength(transaction) {
  const hashMode = transaction.auth.spendingCondition.hashMode;
  const multiSigHashModes = [_constants.AddressHashMode.SerializeP2SH, _constants.AddressHashMode.SerializeP2WSH];

  if (multiSigHashModes.includes(hashMode)) {
    const multiSigSpendingCondition = transaction.auth.spendingCondition;
    const existingSignatures = multiSigSpendingCondition.fields.filter(field => field.contents.type === _constants.StacksMessageType.MessageSignature).length;
    const totalSignatureLength = (multiSigSpendingCondition.signaturesRequired - existingSignatures) * (_constants.RECOVERABLE_ECDSA_SIG_LENGTH_BYTES + 1);
    return transaction.serialize().byteLength + totalSignatureLength;
  } else {
    return transaction.serialize().byteLength;
  }
}

async function estimateTransactionFeeWithFallback(transaction, network) {
  try {
    const estimatedLen = estimateTransactionByteLength(transaction);
    return (await estimateTransaction(transaction.payload, estimatedLen, network))[1].fee;
  } catch (error) {
    if (error instanceof _errors.NoEstimateAvailableError) {
      return await estimateTransferUnsafe(transaction, network);
    }

    throw error;
  }
}

},{"./authorization":23,"./clarity":30,"./constants":43,"./contract-abi":44,"./errors":45,"./keys":47,"./payload":48,"./postcondition":51,"./postcondition-types":50,"./signer":53,"./transaction":55,"./types":56,"./utils":57,"@stacks/common":15,"@stacks/network":21,"c32check":63}],25:[function(require,module,exports){
"use strict";

Object.defineProperty(exports, "__esModule", {
  value: true
});
exports.BytesReader = void 0;
exports.isEnum = isEnum;

var _common = require("@stacks/common");

function createEnumChecker(enumVariable) {
  const enumValues = Object.values(enumVariable).filter(v => typeof v === 'number');
  const enumValueSet = new Set(enumValues);
  return value => enumValueSet.has(value);
}

const enumCheckFunctions = new Map();

function isEnum(enumVariable, value) {
  const checker = enumCheckFunctions.get(enumVariable);

  if (checker !== undefined) {
    return checker(value);
  }

  const newChecker = createEnumChecker(enumVariable);
  enumCheckFunctions.set(enumVariable, newChecker);
  return isEnum(enumVariable, value);
}

class BytesReader {
  constructor(arr) {
    this.consumed = 0;
    this.source = arr;
  }

  readBytes(length) {
    const view = this.source.subarray(this.consumed, this.consumed + length);
    this.consumed += length;
    return view;
  }

  readUInt32BE() {
    return (0, _common.readUInt32BE)(this.readBytes(4), 0);
  }

  readUInt8() {
    return (0, _common.readUInt8)(this.readBytes(1), 0);
  }

  readUInt16BE() {
    return (0, _common.readUInt16BE)(this.readBytes(2), 0);
  }

  readBigUIntLE(length) {
    const bytes = this.readBytes(length).slice().reverse();
    const hex = (0, _common.bytesToHex)(bytes);
    return BigInt(`0x${hex}`);
  }

  readBigUIntBE(length) {
    const bytes = this.readBytes(length);
    const hex = (0, _common.bytesToHex)(bytes);
    return BigInt(`0x${hex}`);
  }

  get readOffset() {
    return this.consumed;
  }

  set readOffset(val) {
    this.consumed = val;
  }

  get internalBytes() {
    return this.source;
  }

  readUInt8Enum(enumVariable, invalidEnumErrorFormatter) {
    const num = this.readUInt8();

    if (isEnum(enumVariable, num)) {
      return num;
    }

    throw invalidEnumErrorFormatter(num);
  }

}

exports.BytesReader = BytesReader;

},{"@stacks/common":15}],26:[function(require,module,exports){
"use strict";

Object.defineProperty(exports, "__esModule", {
  value: true
});
exports.ok = exports.none = exports.list = exports.int = exports.error = exports.deserialize = exports.contractPrincipal = exports.bufferFromUtf8 = exports.bufferFromHex = exports.bufferFromAscii = exports.buffer = exports.bool = exports.address = void 0;
Object.defineProperty(exports, "prettyPrint", {
  enumerable: true,
  get: function () {
    return _prettyPrint.prettyPrint;
  }
});
exports.principal = principal;
exports.uint = exports.tuple = exports.stringUtf8 = exports.stringAscii = exports.standardPrincipal = exports.some = exports.serialize = void 0;

var _common = require("@stacks/common");

var _clarity = require("./clarity");

var _prettyPrint = require("./clarity/prettyPrint");

const bool = _clarity.boolCV;
exports.bool = bool;
const int = _clarity.intCV;
exports.int = int;
const uint = _clarity.uintCV;
exports.uint = uint;

function principal(address) {
  const [addr, name] = address.split('.');
  return name ? (0, _clarity.contractPrincipalCV)(addr, name) : (0, _clarity.standardPrincipalCV)(addr);
}

const address = principal;
exports.address = address;
const contractPrincipal = _clarity.contractPrincipalCV;
exports.contractPrincipal = contractPrincipal;
const standardPrincipal = _clarity.standardPrincipalCV;
exports.standardPrincipal = standardPrincipal;
const list = _clarity.listCV;
exports.list = list;
const stringAscii = _clarity.stringAsciiCV;
exports.stringAscii = stringAscii;
const stringUtf8 = _clarity.stringUtf8CV;
exports.stringUtf8 = stringUtf8;
const buffer = _clarity.bufferCV;
exports.buffer = buffer;

const bufferFromHex = hex => (0, _clarity.bufferCV)((0, _common.hexToBytes)(hex));

exports.bufferFromHex = bufferFromHex;

const bufferFromAscii = ascii => (0, _clarity.bufferCV)((0, _common.asciiToBytes)(ascii));

exports.bufferFromAscii = bufferFromAscii;

const bufferFromUtf8 = utf8 => (0, _clarity.bufferCV)((0, _common.utf8ToBytes)(utf8));

exports.bufferFromUtf8 = bufferFromUtf8;
const none = _clarity.noneCV;
exports.none = none;
const some = _clarity.someCV;
exports.some = some;
const ok = _clarity.responseOkCV;
exports.ok = ok;
const error = _clarity.responseErrorCV;
exports.error = error;
const tuple = _clarity.tupleCV;
exports.tuple = tuple;
const serialize = _clarity.serializeCV;
exports.serialize = serialize;
const deserialize = _clarity.deserializeCV;
exports.deserialize = deserialize;

},{"./clarity":30,"./clarity/prettyPrint":31,"@stacks/common":15}],27:[function(require,module,exports){
"use strict";

Object.defineProperty(exports, "__esModule", {
  value: true
});
exports.cvToJSON = cvToJSON;
exports.cvToString = cvToString;
exports.cvToValue = cvToValue;
exports.getCVTypeString = getCVTypeString;
exports.isClarityType = isClarityType;

var _principalCV = require("./types/principalCV");

var _constants = require("./constants");

var _common = require("@stacks/common");

function cvToString(val, encoding = 'hex') {
  switch (val.type) {
    case _constants.ClarityType.BoolTrue:
      return 'true';

    case _constants.ClarityType.BoolFalse:
      return 'false';

    case _constants.ClarityType.Int:
      return val.value.toString();

    case _constants.ClarityType.UInt:
      return `u${val.value.toString()}`;

    case _constants.ClarityType.Buffer:
      if (encoding === 'tryAscii') {
        const str = (0, _common.bytesToAscii)(val.buffer);

        if (/[ -~]/.test(str)) {
          return JSON.stringify(str);
        }
      }

      return `0x${(0, _common.bytesToHex)(val.buffer)}`;

    case _constants.ClarityType.OptionalNone:
      return 'none';

    case _constants.ClarityType.OptionalSome:
      return `(some ${cvToString(val.value, encoding)})`;

    case _constants.ClarityType.ResponseErr:
      return `(err ${cvToString(val.value, encoding)})`;

    case _constants.ClarityType.ResponseOk:
      return `(ok ${cvToString(val.value, encoding)})`;

    case _constants.ClarityType.PrincipalStandard:
    case _constants.ClarityType.PrincipalContract:
      return (0, _principalCV.principalToString)(val);

    case _constants.ClarityType.List:
      return `(list ${val.list.map(v => cvToString(v, encoding)).join(' ')})`;

    case _constants.ClarityType.Tuple:
      return `(tuple ${Object.keys(val.data).map(key => `(${key} ${cvToString(val.data[key], encoding)})`).join(' ')})`;

    case _constants.ClarityType.StringASCII:
      return `"${val.data}"`;

    case _constants.ClarityType.StringUTF8:
      return `u"${val.data}"`;
  }
}

function cvToValue(val, strictJsonCompat = false) {
  switch (val.type) {
    case _constants.ClarityType.BoolTrue:
      return true;

    case _constants.ClarityType.BoolFalse:
      return false;

    case _constants.ClarityType.Int:
    case _constants.ClarityType.UInt:
      if (strictJsonCompat) {
        return val.value.toString();
      }

      return val.value;

    case _constants.ClarityType.Buffer:
      return `0x${(0, _common.bytesToHex)(val.buffer)}`;

    case _constants.ClarityType.OptionalNone:
      return null;

    case _constants.ClarityType.OptionalSome:
      return cvToJSON(val.value);

    case _constants.ClarityType.ResponseErr:
      return cvToJSON(val.value);

    case _constants.ClarityType.ResponseOk:
      return cvToJSON(val.value);

    case _constants.ClarityType.PrincipalStandard:
    case _constants.ClarityType.PrincipalContract:
      return (0, _principalCV.principalToString)(val);

    case _constants.ClarityType.List:
      return val.list.map(v => cvToJSON(v));

    case _constants.ClarityType.Tuple:
      const result = {};
      Object.keys(val.data).forEach(key => {
        result[key] = cvToJSON(val.data[key]);
      });
      return result;

    case _constants.ClarityType.StringASCII:
      return val.data;

    case _constants.ClarityType.StringUTF8:
      return val.data;
  }
}

function cvToJSON(val) {
  switch (val.type) {
    case _constants.ClarityType.ResponseErr:
      return {
        type: getCVTypeString(val),
        value: cvToValue(val, true),
        success: false
      };

    case _constants.ClarityType.ResponseOk:
      return {
        type: getCVTypeString(val),
        value: cvToValue(val, true),
        success: true
      };

    default:
      return {
        type: getCVTypeString(val),
        value: cvToValue(val, true)
      };
  }
}

function getCVTypeString(val) {
  switch (val.type) {
    case _constants.ClarityType.BoolTrue:
    case _constants.ClarityType.BoolFalse:
      return 'bool';

    case _constants.ClarityType.Int:
      return 'int';

    case _constants.ClarityType.UInt:
      return 'uint';

    case _constants.ClarityType.Buffer:
      return `(buff ${val.buffer.length})`;

    case _constants.ClarityType.OptionalNone:
      return '(optional none)';

    case _constants.ClarityType.OptionalSome:
      return `(optional ${getCVTypeString(val.value)})`;

    case _constants.ClarityType.ResponseErr:
      return `(response UnknownType ${getCVTypeString(val.value)})`;

    case _constants.ClarityType.ResponseOk:
      return `(response ${getCVTypeString(val.value)} UnknownType)`;

    case _constants.ClarityType.PrincipalStandard:
    case _constants.ClarityType.PrincipalContract:
      return 'principal';

    case _constants.ClarityType.List:
      return `(list ${val.list.length} ${val.list.length ? getCVTypeString(val.list[0]) : 'UnknownType'})`;

    case _constants.ClarityType.Tuple:
      return `(tuple ${Object.keys(val.data).map(key => `(${key} ${getCVTypeString(val.data[key])})`).join(' ')})`;

    case _constants.ClarityType.StringASCII:
      return `(string-ascii ${(0, _common.asciiToBytes)(val.data).length})`;

    case _constants.ClarityType.StringUTF8:
      return `(string-utf8 ${(0, _common.utf8ToBytes)(val.data).length})`;
  }
}

function isClarityType(input, withType) {
  return input.type === withType;
}

},{"./constants":28,"./types/principalCV":38,"@stacks/common":15}],28:[function(require,module,exports){
"use strict";

Object.defineProperty(exports, "__esModule", {
  value: true
});
exports.ClarityType = void 0;
var ClarityType;
exports.ClarityType = ClarityType;

(function (ClarityType) {
  ClarityType[ClarityType["Int"] = 0] = "Int";
  ClarityType[ClarityType["UInt"] = 1] = "UInt";
  ClarityType[ClarityType["Buffer"] = 2] = "Buffer";
  ClarityType[ClarityType["BoolTrue"] = 3] = "BoolTrue";
  ClarityType[ClarityType["BoolFalse"] = 4] = "BoolFalse";
  ClarityType[ClarityType["PrincipalStandard"] = 5] = "PrincipalStandard";
  ClarityType[ClarityType["PrincipalContract"] = 6] = "PrincipalContract";
  ClarityType[ClarityType["ResponseOk"] = 7] = "ResponseOk";
  ClarityType[ClarityType["ResponseErr"] = 8] = "ResponseErr";
  ClarityType[ClarityType["OptionalNone"] = 9] = "OptionalNone";
  ClarityType[ClarityType["OptionalSome"] = 10] = "OptionalSome";
  ClarityType[ClarityType["List"] = 11] = "List";
  ClarityType[ClarityType["Tuple"] = 12] = "Tuple";
  ClarityType[ClarityType["StringASCII"] = 13] = "StringASCII";
  ClarityType[ClarityType["StringUTF8"] = 14] = "StringUTF8";
})(ClarityType || (exports.ClarityType = ClarityType = {}));

},{}],29:[function(require,module,exports){
"use strict";

Object.defineProperty(exports, "__esModule", {
  value: true
});
exports.default = deserializeCV;

var _ = require(".");

var _bytesReader = require("../bytesReader");

var _types = require("../types");

var _errors = require("../errors");

var _stringCV = require("./types/stringCV");

var _common = require("@stacks/common");

function deserializeCV(serializedClarityValue) {
  let bytesReader;

  if (typeof serializedClarityValue === 'string') {
    const hasHexPrefix = serializedClarityValue.slice(0, 2).toLowerCase() === '0x';
    bytesReader = new _bytesReader.BytesReader((0, _common.hexToBytes)(hasHexPrefix ? serializedClarityValue.slice(2) : serializedClarityValue));
  } else if (serializedClarityValue instanceof Uint8Array) {
    bytesReader = new _bytesReader.BytesReader(serializedClarityValue);
  } else {
    bytesReader = serializedClarityValue;
  }

  const type = bytesReader.readUInt8Enum(_.ClarityType, n => {
    throw new _errors.DeserializationError(`Cannot recognize Clarity Type: ${n}`);
  });

  switch (type) {
    case _.ClarityType.Int:
      return (0, _.intCV)(bytesReader.readBytes(16));

    case _.ClarityType.UInt:
      return (0, _.uintCV)(bytesReader.readBytes(16));

    case _.ClarityType.Buffer:
      const bufferLength = bytesReader.readUInt32BE();
      return (0, _.bufferCV)(bytesReader.readBytes(bufferLength));

    case _.ClarityType.BoolTrue:
      return (0, _.trueCV)();

    case _.ClarityType.BoolFalse:
      return (0, _.falseCV)();

    case _.ClarityType.PrincipalStandard:
      const sAddress = (0, _types.deserializeAddress)(bytesReader);
      return (0, _.standardPrincipalCVFromAddress)(sAddress);

    case _.ClarityType.PrincipalContract:
      const cAddress = (0, _types.deserializeAddress)(bytesReader);
      const contractName = (0, _types.deserializeLPString)(bytesReader);
      return (0, _.contractPrincipalCVFromAddress)(cAddress, contractName);

    case _.ClarityType.ResponseOk:
      return (0, _.responseOkCV)(deserializeCV(bytesReader));

    case _.ClarityType.ResponseErr:
      return (0, _.responseErrorCV)(deserializeCV(bytesReader));

    case _.ClarityType.OptionalNone:
      return (0, _.noneCV)();

    case _.ClarityType.OptionalSome:
      return (0, _.someCV)(deserializeCV(bytesReader));

    case _.ClarityType.List:
      const listLength = bytesReader.readUInt32BE();
      const listContents = [];

      for (let i = 0; i < listLength; i++) {
        listContents.push(deserializeCV(bytesReader));
      }

      return (0, _.listCV)(listContents);

    case _.ClarityType.Tuple:
      const tupleLength = bytesReader.readUInt32BE();
      const tupleContents = {};

      for (let i = 0; i < tupleLength; i++) {
        const clarityName = (0, _types.deserializeLPString)(bytesReader).content;

        if (clarityName === undefined) {
          throw new _errors.DeserializationError('"content" is undefined');
        }

        tupleContents[clarityName] = deserializeCV(bytesReader);
      }

      return (0, _.tupleCV)(tupleContents);

    case _.ClarityType.StringASCII:
      const asciiStrLen = bytesReader.readUInt32BE();
      const asciiStr = (0, _common.bytesToAscii)(bytesReader.readBytes(asciiStrLen));
      return (0, _stringCV.stringAsciiCV)(asciiStr);

    case _.ClarityType.StringUTF8:
      const utf8StrLen = bytesReader.readUInt32BE();
      const utf8Str = (0, _common.bytesToUtf8)(bytesReader.readBytes(utf8StrLen));
      return (0, _stringCV.stringUtf8CV)(utf8Str);

    default:
      throw new _errors.DeserializationError('Unable to deserialize Clarity Value from Uint8Array. Could not find valid Clarity Type.');
  }
}

},{".":30,"../bytesReader":25,"../errors":45,"../types":56,"./types/stringCV":40,"@stacks/common":15}],30:[function(require,module,exports){
"use strict";

Object.defineProperty(exports, "__esModule", {
  value: true
});
Object.defineProperty(exports, "ClarityType", {
  enumerable: true,
  get: function () {
    return _constants.ClarityType;
  }
});
Object.defineProperty(exports, "boolCV", {
  enumerable: true,
  get: function () {
    return _booleanCV.boolCV;
  }
});
Object.defineProperty(exports, "bufferCV", {
  enumerable: true,
  get: function () {
    return _bufferCV.bufferCV;
  }
});
Object.defineProperty(exports, "bufferCVFromString", {
  enumerable: true,
  get: function () {
    return _bufferCV.bufferCVFromString;
  }
});
Object.defineProperty(exports, "contractPrincipalCV", {
  enumerable: true,
  get: function () {
    return _principalCV.contractPrincipalCV;
  }
});
Object.defineProperty(exports, "contractPrincipalCVFromAddress", {
  enumerable: true,
  get: function () {
    return _principalCV.contractPrincipalCVFromAddress;
  }
});
Object.defineProperty(exports, "contractPrincipalCVFromStandard", {
  enumerable: true,
  get: function () {
    return _principalCV.contractPrincipalCVFromStandard;
  }
});
Object.defineProperty(exports, "cvToJSON", {
  enumerable: true,
  get: function () {
    return _clarityValue.cvToJSON;
  }
});
Object.defineProperty(exports, "cvToString", {
  enumerable: true,
  get: function () {
    return _clarityValue.cvToString;
  }
});
Object.defineProperty(exports, "cvToValue", {
  enumerable: true,
  get: function () {
    return _clarityValue.cvToValue;
  }
});
Object.defineProperty(exports, "deserializeCV", {
  enumerable: true,
  get: function () {
    return _deserialize.default;
  }
});
Object.defineProperty(exports, "falseCV", {
  enumerable: true,
  get: function () {
    return _booleanCV.falseCV;
  }
});
Object.defineProperty(exports, "getCVTypeString", {
  enumerable: true,
  get: function () {
    return _clarityValue.getCVTypeString;
  }
});
Object.defineProperty(exports, "intCV", {
  enumerable: true,
  get: function () {
    return _intCV.intCV;
  }
});
Object.defineProperty(exports, "isClarityType", {
  enumerable: true,
  get: function () {
    return _clarityValue.isClarityType;
  }
});
Object.defineProperty(exports, "listCV", {
  enumerable: true,
  get: function () {
    return _listCV.listCV;
  }
});
Object.defineProperty(exports, "noneCV", {
  enumerable: true,
  get: function () {
    return _optionalCV.noneCV;
  }
});
Object.defineProperty(exports, "optionalCVOf", {
  enumerable: true,
  get: function () {
    return _optionalCV.optionalCVOf;
  }
});
Object.defineProperty(exports, "principalCV", {
  enumerable: true,
  get: function () {
    return _principalCV.principalCV;
  }
});
Object.defineProperty(exports, "principalToString", {
  enumerable: true,
  get: function () {
    return _principalCV.principalToString;
  }
});
Object.defineProperty(exports, "responseErrorCV", {
  enumerable: true,
  get: function () {
    return _responseCV.responseErrorCV;
  }
});
Object.defineProperty(exports, "responseOkCV", {
  enumerable: true,
  get: function () {
    return _responseCV.responseOkCV;
  }
});
Object.defineProperty(exports, "serializeCV", {
  enumerable: true,
  get: function () {
    return _serialize.serializeCV;
  }
});
Object.defineProperty(exports, "someCV", {
  enumerable: true,
  get: function () {
    return _optionalCV.someCV;
  }
});
Object.defineProperty(exports, "standardPrincipalCV", {
  enumerable: true,
  get: function () {
    return _principalCV.standardPrincipalCV;
  }
});
Object.defineProperty(exports, "standardPrincipalCVFromAddress", {
  enumerable: true,
  get: function () {
    return _principalCV.standardPrincipalCVFromAddress;
  }
});
Object.defineProperty(exports, "stringAsciiCV", {
  enumerable: true,
  get: function () {
    return _stringCV.stringAsciiCV;
  }
});
Object.defineProperty(exports, "stringCV", {
  enumerable: true,
  get: function () {
    return _stringCV.stringCV;
  }
});
Object.defineProperty(exports, "stringUtf8CV", {
  enumerable: true,
  get: function () {
    return _stringCV.stringUtf8CV;
  }
});
Object.defineProperty(exports, "trueCV", {
  enumerable: true,
  get: function () {
    return _booleanCV.trueCV;
  }
});
Object.defineProperty(exports, "tupleCV", {
  enumerable: true,
  get: function () {
    return _tupleCV.tupleCV;
  }
});
Object.defineProperty(exports, "uintCV", {
  enumerable: true,
  get: function () {
    return _intCV.uintCV;
  }
});

var _clarityValue = require("./clarityValue");

var _constants = require("./constants");

var _booleanCV = require("./types/booleanCV");

var _intCV = require("./types/intCV");

var _bufferCV = require("./types/bufferCV");

var _optionalCV = require("./types/optionalCV");

var _responseCV = require("./types/responseCV");

var _principalCV = require("./types/principalCV");

var _listCV = require("./types/listCV");

var _tupleCV = require("./types/tupleCV");

var _stringCV = require("./types/stringCV");

var _serialize = require("./serialize");

var _deserialize = _interopRequireDefault(require("./deserialize"));

function _interopRequireDefault(obj) { return obj && obj.__esModule ? obj : { default: obj }; }

},{"./clarityValue":27,"./constants":28,"./deserialize":29,"./serialize":32,"./types/booleanCV":33,"./types/bufferCV":34,"./types/intCV":35,"./types/listCV":36,"./types/optionalCV":37,"./types/principalCV":38,"./types/responseCV":39,"./types/stringCV":40,"./types/tupleCV":41}],31:[function(require,module,exports){
"use strict";

Object.defineProperty(exports, "__esModule", {
  value: true
});
exports.prettyPrint = prettyPrint;

var _common = require("@stacks/common");

var _ = require(".");

function formatSpace(space, depth, end = false) {
  if (!space) return ' ';
  return `\n${' '.repeat(space * (depth - (end ? 1 : 0)))}`;
}

function formatList(cv, space, depth = 1) {
  if (cv.list.length === 0) return '(list)';
  const spaceBefore = formatSpace(space, depth, false);
  const endSpace = space ? formatSpace(space, depth, true) : '';
  const items = cv.list.map(v => prettyPrintWithDepth(v, space, depth)).join(spaceBefore);
  return `(list${spaceBefore}${items}${endSpace})`;
}

function formatTuple(cv, space, depth = 1) {
  if (Object.keys(cv.data).length === 0) return '{}';
  const items = [];

  for (const [key, value] of Object.entries(cv.data)) {
    items.push(`${key}: ${prettyPrintWithDepth(value, space, depth)}`);
  }

  const spaceBefore = formatSpace(space, depth, false);
  const endSpace = formatSpace(space, depth, true);
  return `{${spaceBefore}${items.sort().join(`,${spaceBefore}`)}${endSpace}}`;
}

function exhaustiveCheck(param) {
  throw new Error(`invalid clarity value type: ${param}`);
}

function prettyPrintWithDepth(cv, space = 0, depth) {
  if (cv.type === _.ClarityType.BoolFalse) return 'false';
  if (cv.type === _.ClarityType.BoolTrue) return 'true';
  if (cv.type === _.ClarityType.Int) return cv.value.toString();
  if (cv.type === _.ClarityType.UInt) return `u${cv.value.toString()}`;
  if (cv.type === _.ClarityType.StringASCII) return `"${cv.data}"`;
  if (cv.type === _.ClarityType.StringUTF8) return `u"${cv.data}"`;
  if (cv.type === _.ClarityType.PrincipalContract) return `'${(0, _.principalToString)(cv)}`;
  if (cv.type === _.ClarityType.PrincipalStandard) return `'${(0, _.principalToString)(cv)}`;
  if (cv.type === _.ClarityType.Buffer) return `0x${(0, _common.bytesToHex)(cv.buffer)}`;
  if (cv.type === _.ClarityType.OptionalNone) return 'none';
  if (cv.type === _.ClarityType.OptionalSome) return `(some ${prettyPrintWithDepth(cv.value, space, depth)})`;
  if (cv.type === _.ClarityType.ResponseOk) return `(ok ${prettyPrintWithDepth(cv.value, space, depth)})`;
  if (cv.type === _.ClarityType.ResponseErr) return `(err ${prettyPrintWithDepth(cv.value, space, depth)})`;

  if (cv.type === _.ClarityType.List) {
    return formatList(cv, space, depth + 1);
  }

  if (cv.type === _.ClarityType.Tuple) {
    return formatTuple(cv, space, depth + 1);
  }

  exhaustiveCheck(cv);
}

function prettyPrint(cv, space = 0) {
  return prettyPrintWithDepth(cv, space, 0);
}

},{".":30,"@stacks/common":15}],32:[function(require,module,exports){
"use strict";

Object.defineProperty(exports, "__esModule", {
  value: true
});
exports.serializeCV = serializeCV;

var _common = require("@stacks/common");

var _types = require("../types");

var _postconditionTypes = require("../postcondition-types");

var _constants = require("./constants");

var _errors = require("../errors");

var _constants2 = require("../constants");

function bytesWithTypeID(typeId, bytes) {
  return (0, _common.concatArray)([typeId, bytes]);
}

function serializeBoolCV(value) {
  return new Uint8Array([value.type]);
}

function serializeOptionalCV(cv) {
  if (cv.type === _constants.ClarityType.OptionalNone) {
    return new Uint8Array([cv.type]);
  } else {
    return bytesWithTypeID(cv.type, serializeCV(cv.value));
  }
}

function serializeBufferCV(cv) {
  const length = new Uint8Array(4);
  (0, _common.writeUInt32BE)(length, cv.buffer.length, 0);
  return bytesWithTypeID(cv.type, (0, _common.concatBytes)(length, cv.buffer));
}

function serializeIntCV(cv) {
  const bytes = (0, _common.bigIntToBytes)((0, _common.toTwos)(cv.value, BigInt(_constants2.CLARITY_INT_SIZE)), _constants2.CLARITY_INT_BYTE_SIZE);
  return bytesWithTypeID(cv.type, bytes);
}

function serializeUIntCV(cv) {
  const bytes = (0, _common.bigIntToBytes)(cv.value, _constants2.CLARITY_INT_BYTE_SIZE);
  return bytesWithTypeID(cv.type, bytes);
}

function serializeStandardPrincipalCV(cv) {
  return bytesWithTypeID(cv.type, (0, _types.serializeAddress)(cv.address));
}

function serializeContractPrincipalCV(cv) {
  return bytesWithTypeID(cv.type, (0, _common.concatBytes)((0, _types.serializeAddress)(cv.address), (0, _types.serializeLPString)(cv.contractName)));
}

function serializeResponseCV(cv) {
  return bytesWithTypeID(cv.type, serializeCV(cv.value));
}

function serializeListCV(cv) {
  const bytesArray = [];
  const length = new Uint8Array(4);
  (0, _common.writeUInt32BE)(length, cv.list.length, 0);
  bytesArray.push(length);

  for (const value of cv.list) {
    const serializedValue = serializeCV(value);
    bytesArray.push(serializedValue);
  }

  return bytesWithTypeID(cv.type, (0, _common.concatArray)(bytesArray));
}

function serializeTupleCV(cv) {
  const bytesArray = [];
  const length = new Uint8Array(4);
  (0, _common.writeUInt32BE)(length, Object.keys(cv.data).length, 0);
  bytesArray.push(length);
  const lexicographicOrder = Object.keys(cv.data).sort((a, b) => a.localeCompare(b));

  for (const key of lexicographicOrder) {
    const nameWithLength = (0, _postconditionTypes.createLPString)(key);
    bytesArray.push((0, _types.serializeLPString)(nameWithLength));
    const serializedValue = serializeCV(cv.data[key]);
    bytesArray.push(serializedValue);
  }

  return bytesWithTypeID(cv.type, (0, _common.concatArray)(bytesArray));
}

function serializeStringCV(cv, encoding) {
  const bytesArray = [];
  const str = encoding == 'ascii' ? (0, _common.asciiToBytes)(cv.data) : (0, _common.utf8ToBytes)(cv.data);
  const len = new Uint8Array(4);
  (0, _common.writeUInt32BE)(len, str.length, 0);
  bytesArray.push(len);
  bytesArray.push(str);
  return bytesWithTypeID(cv.type, (0, _common.concatArray)(bytesArray));
}

function serializeStringAsciiCV(cv) {
  return serializeStringCV(cv, 'ascii');
}

function serializeStringUtf8CV(cv) {
  return serializeStringCV(cv, 'utf8');
}

function serializeCV(value) {
  switch (value.type) {
    case _constants.ClarityType.BoolTrue:
    case _constants.ClarityType.BoolFalse:
      return serializeBoolCV(value);

    case _constants.ClarityType.OptionalNone:
    case _constants.ClarityType.OptionalSome:
      return serializeOptionalCV(value);

    case _constants.ClarityType.Buffer:
      return serializeBufferCV(value);

    case _constants.ClarityType.UInt:
      return serializeUIntCV(value);

    case _constants.ClarityType.Int:
      return serializeIntCV(value);

    case _constants.ClarityType.PrincipalStandard:
      return serializeStandardPrincipalCV(value);

    case _constants.ClarityType.PrincipalContract:
      return serializeContractPrincipalCV(value);

    case _constants.ClarityType.ResponseOk:
    case _constants.ClarityType.ResponseErr:
      return serializeResponseCV(value);

    case _constants.ClarityType.List:
      return serializeListCV(value);

    case _constants.ClarityType.Tuple:
      return serializeTupleCV(value);

    case _constants.ClarityType.StringASCII:
      return serializeStringAsciiCV(value);

    case _constants.ClarityType.StringUTF8:
      return serializeStringUtf8CV(value);

    default:
      throw new _errors.SerializationError('Unable to serialize. Invalid Clarity Value.');
  }
}

},{"../constants":43,"../errors":45,"../postcondition-types":50,"../types":56,"./constants":28,"@stacks/common":15}],33:[function(require,module,exports){
"use strict";

Object.defineProperty(exports, "__esModule", {
  value: true
});
exports.trueCV = exports.falseCV = exports.boolCV = void 0;

var _constants = require("../constants");

const trueCV = () => ({
  type: _constants.ClarityType.BoolTrue
});

exports.trueCV = trueCV;

const falseCV = () => ({
  type: _constants.ClarityType.BoolFalse
});

exports.falseCV = falseCV;

const boolCV = bool => bool ? trueCV() : falseCV();

exports.boolCV = boolCV;

},{"../constants":28}],34:[function(require,module,exports){
"use strict";

Object.defineProperty(exports, "__esModule", {
  value: true
});
exports.bufferCVFromString = exports.bufferCV = void 0;

var _common = require("@stacks/common");

var _constants = require("../constants");

const bufferCV = buffer => {
  if (buffer.length > 1000000) {
    throw new Error('Cannot construct clarity buffer that is greater than 1MB');
  }

  return {
    type: _constants.ClarityType.Buffer,
    buffer
  };
};

exports.bufferCV = bufferCV;

const bufferCVFromString = str => bufferCV((0, _common.utf8ToBytes)(str));

exports.bufferCVFromString = bufferCVFromString;

},{"../constants":28,"@stacks/common":15}],35:[function(require,module,exports){
"use strict";

Object.defineProperty(exports, "__esModule", {
  value: true
});
exports.uintCV = exports.intCV = void 0;

var _common = require("@stacks/common");

var _constants = require("../constants");

const MAX_U128 = BigInt('0xffffffffffffffffffffffffffffffff');
const MIN_U128 = BigInt(0);
const MAX_I128 = BigInt('0x7fffffffffffffffffffffffffffffff');
const MIN_I128 = BigInt('-170141183460469231731687303715884105728');

const intCV = value => {
  const bigInt = (0, _common.intToBigInt)(value, true);

  if (bigInt > MAX_I128) {
    throw new RangeError(`Cannot construct clarity integer from value greater than ${MAX_I128}`);
  } else if (bigInt < MIN_I128) {
    throw new RangeError(`Cannot construct clarity integer form value less than ${MIN_I128}`);
  }

  return {
    type: _constants.ClarityType.Int,
    value: bigInt
  };
};

exports.intCV = intCV;

const uintCV = value => {
  const bigInt = (0, _common.intToBigInt)(value, false);

  if (bigInt < MIN_U128) {
    throw new RangeError('Cannot construct unsigned clarity integer from negative value');
  } else if (bigInt > MAX_U128) {
    throw new RangeError(`Cannot construct unsigned clarity integer greater than ${MAX_U128}`);
  }

  return {
    type: _constants.ClarityType.UInt,
    value: bigInt
  };
};

exports.uintCV = uintCV;

},{"../constants":28,"@stacks/common":15}],36:[function(require,module,exports){
"use strict";

Object.defineProperty(exports, "__esModule", {
  value: true
});
exports.listCV = listCV;

var _constants = require("../constants");

function listCV(values) {
  return {
    type: _constants.ClarityType.List,
    list: values
  };
}

},{"../constants":28}],37:[function(require,module,exports){
"use strict";

Object.defineProperty(exports, "__esModule", {
  value: true
});
exports.noneCV = noneCV;
exports.optionalCVOf = optionalCVOf;
exports.someCV = someCV;

var _constants = require("../constants");

function noneCV() {
  return {
    type: _constants.ClarityType.OptionalNone
  };
}

function someCV(value) {
  return {
    type: _constants.ClarityType.OptionalSome,
    value
  };
}

function optionalCVOf(value) {
  if (value) {
    return someCV(value);
  } else {
    return noneCV();
  }
}

},{"../constants":28}],38:[function(require,module,exports){
"use strict";

Object.defineProperty(exports, "__esModule", {
  value: true
});
exports.contractPrincipalCV = contractPrincipalCV;
exports.contractPrincipalCVFromAddress = contractPrincipalCVFromAddress;
exports.contractPrincipalCVFromStandard = contractPrincipalCVFromStandard;
exports.principalCV = principalCV;
exports.principalToString = principalToString;
exports.standardPrincipalCV = standardPrincipalCV;
exports.standardPrincipalCVFromAddress = standardPrincipalCVFromAddress;

var _common = require("@stacks/common");

var _common2 = require("../../common");

var _postconditionTypes = require("../../postcondition-types");

var _constants = require("../constants");

function principalToString(principal) {
  if (principal.type === _constants.ClarityType.PrincipalStandard) {
    return (0, _common2.addressToString)(principal.address);
  } else if (principal.type === _constants.ClarityType.PrincipalContract) {
    const address = (0, _common2.addressToString)(principal.address);
    return `${address}.${principal.contractName.content}`;
  } else {
    throw new Error(`Unexpected principal data: ${JSON.stringify(principal)}`);
  }
}

function principalCV(principal) {
  if (principal.includes('.')) {
    const [address, contractName] = principal.split('.');
    return contractPrincipalCV(address, contractName);
  } else {
    return standardPrincipalCV(principal);
  }
}

function standardPrincipalCV(addressString) {
  const addr = (0, _postconditionTypes.createAddress)(addressString);
  return {
    type: _constants.ClarityType.PrincipalStandard,
    address: addr
  };
}

function standardPrincipalCVFromAddress(address) {
  return {
    type: _constants.ClarityType.PrincipalStandard,
    address
  };
}

function contractPrincipalCV(addressString, contractName) {
  const addr = (0, _postconditionTypes.createAddress)(addressString);
  const lengthPrefixedContractName = (0, _postconditionTypes.createLPString)(contractName);
  return contractPrincipalCVFromAddress(addr, lengthPrefixedContractName);
}

function contractPrincipalCVFromAddress(address, contractName) {
  if ((0, _common.utf8ToBytes)(contractName.content).byteLength >= 128) {
    throw new Error('Contract name must be less than 128 bytes');
  }

  return {
    type: _constants.ClarityType.PrincipalContract,
    address,
    contractName
  };
}

function contractPrincipalCVFromStandard(sp, contractName) {
  const lengthPrefixedContractName = (0, _postconditionTypes.createLPString)(contractName);
  return {
    type: _constants.ClarityType.PrincipalContract,
    address: sp.address,
    contractName: lengthPrefixedContractName
  };
}

},{"../../common":42,"../../postcondition-types":50,"../constants":28,"@stacks/common":15}],39:[function(require,module,exports){
"use strict";

Object.defineProperty(exports, "__esModule", {
  value: true
});
exports.responseErrorCV = responseErrorCV;
exports.responseOkCV = responseOkCV;

var _constants = require("../constants");

function responseErrorCV(value) {
  return {
    type: _constants.ClarityType.ResponseErr,
    value
  };
}

function responseOkCV(value) {
  return {
    type: _constants.ClarityType.ResponseOk,
    value
  };
}

},{"../constants":28}],40:[function(require,module,exports){
"use strict";

Object.defineProperty(exports, "__esModule", {
  value: true
});
exports.stringUtf8CV = exports.stringCV = exports.stringAsciiCV = void 0;

var _constants = require("../constants");

const stringAsciiCV = data => {
  return {
    type: _constants.ClarityType.StringASCII,
    data
  };
};

exports.stringAsciiCV = stringAsciiCV;

const stringUtf8CV = data => {
  return {
    type: _constants.ClarityType.StringUTF8,
    data
  };
};

exports.stringUtf8CV = stringUtf8CV;

const stringCV = (data, encoding) => {
  switch (encoding) {
    case 'ascii':
      return stringAsciiCV(data);

    case 'utf8':
      return stringUtf8CV(data);
  }
};

exports.stringCV = stringCV;

},{"../constants":28}],41:[function(require,module,exports){
"use strict";

Object.defineProperty(exports, "__esModule", {
  value: true
});
exports.tupleCV = tupleCV;

var _constants = require("../constants");

var _utils = require("../../utils");

function tupleCV(data) {
  for (const key in data) {
    if (!(0, _utils.isClarityName)(key)) {
      throw new Error(`"${key}" is not a valid Clarity name`);
    }
  }

  return {
    type: _constants.ClarityType.Tuple,
    data
  };
}

},{"../../utils":57,"../constants":28}],42:[function(require,module,exports){
"use strict";

Object.defineProperty(exports, "__esModule", {
  value: true
});
exports.addressFromVersionHash = addressFromVersionHash;
exports.addressHashModeToVersion = addressHashModeToVersion;
exports.addressToString = addressToString;
exports.createMessageSignature = createMessageSignature;

var _constants = require("./constants");

var _c32check = require("c32check");

var _common = require("@stacks/common");

function createMessageSignature(signature) {
  const length = (0, _common.hexToBytes)(signature).byteLength;

  if (length != _constants.RECOVERABLE_ECDSA_SIG_LENGTH_BYTES) {
    throw Error('Invalid signature');
  }

  return {
    type: _constants.StacksMessageType.MessageSignature,
    data: signature
  };
}

function addressHashModeToVersion(hashMode, txVersion) {
  switch (hashMode) {
    case _constants.AddressHashMode.SerializeP2PKH:
      switch (txVersion) {
        case _constants.TransactionVersion.Mainnet:
          return _constants.AddressVersion.MainnetSingleSig;

        case _constants.TransactionVersion.Testnet:
          return _constants.AddressVersion.TestnetSingleSig;

        default:
          throw new Error(`Unexpected txVersion ${JSON.stringify(txVersion)} for hashMode ${hashMode}`);
      }

    case _constants.AddressHashMode.SerializeP2SH:
    case _constants.AddressHashMode.SerializeP2WPKH:
    case _constants.AddressHashMode.SerializeP2WSH:
      switch (txVersion) {
        case _constants.TransactionVersion.Mainnet:
          return _constants.AddressVersion.MainnetMultiSig;

        case _constants.TransactionVersion.Testnet:
          return _constants.AddressVersion.TestnetMultiSig;

        default:
          throw new Error(`Unexpected txVersion ${JSON.stringify(txVersion)} for hashMode ${hashMode}`);
      }

    default:
      throw new Error(`Unexpected hashMode ${JSON.stringify(hashMode)}`);
  }
}

function addressFromVersionHash(version, hash) {
  return {
    type: _constants.StacksMessageType.Address,
    version,
    hash160: hash
  };
}

function addressToString(address) {
  return (0, _c32check.c32address)(address.version, address.hash160);
}

},{"./constants":43,"@stacks/common":15,"c32check":63}],43:[function(require,module,exports){
"use strict";

Object.defineProperty(exports, "__esModule", {
  value: true
});
exports.UNCOMPRESSED_PUBKEY_LENGTH_BYTES = exports.TxRejectedReason = exports.TransactionVersion = exports.StacksMessageType = exports.RECOVERABLE_ECDSA_SIG_LENGTH_BYTES = exports.PubKeyEncoding = exports.PostConditionType = exports.PostConditionPrincipalID = exports.PostConditionMode = exports.PayloadType = exports.NonFungibleConditionCode = exports.MEMO_MAX_LENGTH_BYTES = exports.MAX_STRING_LENGTH_BYTES = exports.FungibleConditionCode = exports.DEFAULT_TRANSACTION_VERSION = exports.DEFAULT_CORE_NODE_API_URL = exports.DEFAULT_CHAIN_ID = exports.ClarityVersion = exports.ChainID = exports.COMPRESSED_PUBKEY_LENGTH_BYTES = exports.COINBASE_BYTES_LENGTH = exports.CLARITY_INT_SIZE = exports.CLARITY_INT_BYTE_SIZE = exports.AuthType = exports.AssetType = exports.AnchorModeNames = exports.AnchorMode = exports.AddressVersion = exports.AddressHashMode = void 0;
exports.anchorModeFromNameOrValue = anchorModeFromNameOrValue;
exports.whenMessageType = whenMessageType;
var ChainID;
exports.ChainID = ChainID;

(function (ChainID) {
  ChainID[ChainID["Testnet"] = 2147483648] = "Testnet";
  ChainID[ChainID["Mainnet"] = 1] = "Mainnet";
})(ChainID || (exports.ChainID = ChainID = {}));

const DEFAULT_CHAIN_ID = ChainID.Mainnet;
exports.DEFAULT_CHAIN_ID = DEFAULT_CHAIN_ID;
const MAX_STRING_LENGTH_BYTES = 128;
exports.MAX_STRING_LENGTH_BYTES = MAX_STRING_LENGTH_BYTES;
const CLARITY_INT_SIZE = 128;
exports.CLARITY_INT_SIZE = CLARITY_INT_SIZE;
const CLARITY_INT_BYTE_SIZE = 16;
exports.CLARITY_INT_BYTE_SIZE = CLARITY_INT_BYTE_SIZE;
const COINBASE_BYTES_LENGTH = 32;
exports.COINBASE_BYTES_LENGTH = COINBASE_BYTES_LENGTH;
const RECOVERABLE_ECDSA_SIG_LENGTH_BYTES = 65;
exports.RECOVERABLE_ECDSA_SIG_LENGTH_BYTES = RECOVERABLE_ECDSA_SIG_LENGTH_BYTES;
const COMPRESSED_PUBKEY_LENGTH_BYTES = 32;
exports.COMPRESSED_PUBKEY_LENGTH_BYTES = COMPRESSED_PUBKEY_LENGTH_BYTES;
const UNCOMPRESSED_PUBKEY_LENGTH_BYTES = 64;
exports.UNCOMPRESSED_PUBKEY_LENGTH_BYTES = UNCOMPRESSED_PUBKEY_LENGTH_BYTES;
const MEMO_MAX_LENGTH_BYTES = 34;
exports.MEMO_MAX_LENGTH_BYTES = MEMO_MAX_LENGTH_BYTES;
const DEFAULT_CORE_NODE_API_URL = 'https://api.mainnet.hiro.so';
exports.DEFAULT_CORE_NODE_API_URL = DEFAULT_CORE_NODE_API_URL;
var StacksMessageType;
exports.StacksMessageType = StacksMessageType;

(function (StacksMessageType) {
  StacksMessageType[StacksMessageType["Address"] = 0] = "Address";
  StacksMessageType[StacksMessageType["Principal"] = 1] = "Principal";
  StacksMessageType[StacksMessageType["LengthPrefixedString"] = 2] = "LengthPrefixedString";
  StacksMessageType[StacksMessageType["MemoString"] = 3] = "MemoString";
  StacksMessageType[StacksMessageType["AssetInfo"] = 4] = "AssetInfo";
  StacksMessageType[StacksMessageType["PostCondition"] = 5] = "PostCondition";
  StacksMessageType[StacksMessageType["PublicKey"] = 6] = "PublicKey";
  StacksMessageType[StacksMessageType["LengthPrefixedList"] = 7] = "LengthPrefixedList";
  StacksMessageType[StacksMessageType["Payload"] = 8] = "Payload";
  StacksMessageType[StacksMessageType["MessageSignature"] = 9] = "MessageSignature";
  StacksMessageType[StacksMessageType["StructuredDataSignature"] = 10] = "StructuredDataSignature";
  StacksMessageType[StacksMessageType["TransactionAuthField"] = 11] = "TransactionAuthField";
})(StacksMessageType || (exports.StacksMessageType = StacksMessageType = {}));

function whenMessageType(messageType) {
  return messageTypeMap => messageTypeMap[messageType];
}

var PayloadType;
exports.PayloadType = PayloadType;

(function (PayloadType) {
  PayloadType[PayloadType["TokenTransfer"] = 0] = "TokenTransfer";
  PayloadType[PayloadType["SmartContract"] = 1] = "SmartContract";
  PayloadType[PayloadType["VersionedSmartContract"] = 6] = "VersionedSmartContract";
  PayloadType[PayloadType["ContractCall"] = 2] = "ContractCall";
  PayloadType[PayloadType["PoisonMicroblock"] = 3] = "PoisonMicroblock";
  PayloadType[PayloadType["Coinbase"] = 4] = "Coinbase";
  PayloadType[PayloadType["CoinbaseToAltRecipient"] = 5] = "CoinbaseToAltRecipient";
})(PayloadType || (exports.PayloadType = PayloadType = {}));

var ClarityVersion;
exports.ClarityVersion = ClarityVersion;

(function (ClarityVersion) {
  ClarityVersion[ClarityVersion["Clarity1"] = 1] = "Clarity1";
  ClarityVersion[ClarityVersion["Clarity2"] = 2] = "Clarity2";
})(ClarityVersion || (exports.ClarityVersion = ClarityVersion = {}));

var AnchorMode;
exports.AnchorMode = AnchorMode;

(function (AnchorMode) {
  AnchorMode[AnchorMode["OnChainOnly"] = 1] = "OnChainOnly";
  AnchorMode[AnchorMode["OffChainOnly"] = 2] = "OffChainOnly";
  AnchorMode[AnchorMode["Any"] = 3] = "Any";
})(AnchorMode || (exports.AnchorMode = AnchorMode = {}));

const AnchorModeNames = ['onChainOnly', 'offChainOnly', 'any'];
exports.AnchorModeNames = AnchorModeNames;
const AnchorModeMap = {
  [AnchorModeNames[0]]: AnchorMode.OnChainOnly,
  [AnchorModeNames[1]]: AnchorMode.OffChainOnly,
  [AnchorModeNames[2]]: AnchorMode.Any,
  [AnchorMode.OnChainOnly]: AnchorMode.OnChainOnly,
  [AnchorMode.OffChainOnly]: AnchorMode.OffChainOnly,
  [AnchorMode.Any]: AnchorMode.Any
};

function anchorModeFromNameOrValue(mode) {
  if (mode in AnchorModeMap) return AnchorModeMap[mode];
  throw new Error(`Invalid anchor mode "${mode}", must be one of: ${AnchorModeNames.join(', ')}`);
}

var TransactionVersion;
exports.TransactionVersion = TransactionVersion;

(function (TransactionVersion) {
  TransactionVersion[TransactionVersion["Mainnet"] = 0] = "Mainnet";
  TransactionVersion[TransactionVersion["Testnet"] = 128] = "Testnet";
})(TransactionVersion || (exports.TransactionVersion = TransactionVersion = {}));

const DEFAULT_TRANSACTION_VERSION = TransactionVersion.Mainnet;
exports.DEFAULT_TRANSACTION_VERSION = DEFAULT_TRANSACTION_VERSION;
var PostConditionMode;
exports.PostConditionMode = PostConditionMode;

(function (PostConditionMode) {
  PostConditionMode[PostConditionMode["Allow"] = 1] = "Allow";
  PostConditionMode[PostConditionMode["Deny"] = 2] = "Deny";
})(PostConditionMode || (exports.PostConditionMode = PostConditionMode = {}));

var PostConditionType;
exports.PostConditionType = PostConditionType;

(function (PostConditionType) {
  PostConditionType[PostConditionType["STX"] = 0] = "STX";
  PostConditionType[PostConditionType["Fungible"] = 1] = "Fungible";
  PostConditionType[PostConditionType["NonFungible"] = 2] = "NonFungible";
})(PostConditionType || (exports.PostConditionType = PostConditionType = {}));

var AuthType;
exports.AuthType = AuthType;

(function (AuthType) {
  AuthType[AuthType["Standard"] = 4] = "Standard";
  AuthType[AuthType["Sponsored"] = 5] = "Sponsored";
})(AuthType || (exports.AuthType = AuthType = {}));

var AddressHashMode;
exports.AddressHashMode = AddressHashMode;

(function (AddressHashMode) {
  AddressHashMode[AddressHashMode["SerializeP2PKH"] = 0] = "SerializeP2PKH";
  AddressHashMode[AddressHashMode["SerializeP2SH"] = 1] = "SerializeP2SH";
  AddressHashMode[AddressHashMode["SerializeP2WPKH"] = 2] = "SerializeP2WPKH";
  AddressHashMode[AddressHashMode["SerializeP2WSH"] = 3] = "SerializeP2WSH";
})(AddressHashMode || (exports.AddressHashMode = AddressHashMode = {}));

var AddressVersion;
exports.AddressVersion = AddressVersion;

(function (AddressVersion) {
  AddressVersion[AddressVersion["MainnetSingleSig"] = 22] = "MainnetSingleSig";
  AddressVersion[AddressVersion["MainnetMultiSig"] = 20] = "MainnetMultiSig";
  AddressVersion[AddressVersion["TestnetSingleSig"] = 26] = "TestnetSingleSig";
  AddressVersion[AddressVersion["TestnetMultiSig"] = 21] = "TestnetMultiSig";
})(AddressVersion || (exports.AddressVersion = AddressVersion = {}));

var PubKeyEncoding;
exports.PubKeyEncoding = PubKeyEncoding;

(function (PubKeyEncoding) {
  PubKeyEncoding[PubKeyEncoding["Compressed"] = 0] = "Compressed";
  PubKeyEncoding[PubKeyEncoding["Uncompressed"] = 1] = "Uncompressed";
})(PubKeyEncoding || (exports.PubKeyEncoding = PubKeyEncoding = {}));

var FungibleConditionCode;
exports.FungibleConditionCode = FungibleConditionCode;

(function (FungibleConditionCode) {
  FungibleConditionCode[FungibleConditionCode["Equal"] = 1] = "Equal";
  FungibleConditionCode[FungibleConditionCode["Greater"] = 2] = "Greater";
  FungibleConditionCode[FungibleConditionCode["GreaterEqual"] = 3] = "GreaterEqual";
  FungibleConditionCode[FungibleConditionCode["Less"] = 4] = "Less";
  FungibleConditionCode[FungibleConditionCode["LessEqual"] = 5] = "LessEqual";
})(FungibleConditionCode || (exports.FungibleConditionCode = FungibleConditionCode = {}));

var NonFungibleConditionCode;
exports.NonFungibleConditionCode = NonFungibleConditionCode;

(function (NonFungibleConditionCode) {
  NonFungibleConditionCode[NonFungibleConditionCode["Sends"] = 16] = "Sends";
  NonFungibleConditionCode[NonFungibleConditionCode["DoesNotSend"] = 17] = "DoesNotSend";
})(NonFungibleConditionCode || (exports.NonFungibleConditionCode = NonFungibleConditionCode = {}));

var PostConditionPrincipalID;
exports.PostConditionPrincipalID = PostConditionPrincipalID;

(function (PostConditionPrincipalID) {
  PostConditionPrincipalID[PostConditionPrincipalID["Origin"] = 1] = "Origin";
  PostConditionPrincipalID[PostConditionPrincipalID["Standard"] = 2] = "Standard";
  PostConditionPrincipalID[PostConditionPrincipalID["Contract"] = 3] = "Contract";
})(PostConditionPrincipalID || (exports.PostConditionPrincipalID = PostConditionPrincipalID = {}));

var AssetType;
exports.AssetType = AssetType;

(function (AssetType) {
  AssetType[AssetType["STX"] = 0] = "STX";
  AssetType[AssetType["Fungible"] = 1] = "Fungible";
  AssetType[AssetType["NonFungible"] = 2] = "NonFungible";
})(AssetType || (exports.AssetType = AssetType = {}));

var TxRejectedReason;
exports.TxRejectedReason = TxRejectedReason;

(function (TxRejectedReason) {
  TxRejectedReason["Serialization"] = "Serialization";
  TxRejectedReason["Deserialization"] = "Deserialization";
  TxRejectedReason["SignatureValidation"] = "SignatureValidation";
  TxRejectedReason["FeeTooLow"] = "FeeTooLow";
  TxRejectedReason["BadNonce"] = "BadNonce";
  TxRejectedReason["NotEnoughFunds"] = "NotEnoughFunds";
  TxRejectedReason["NoSuchContract"] = "NoSuchContract";
  TxRejectedReason["NoSuchPublicFunction"] = "NoSuchPublicFunction";
  TxRejectedReason["BadFunctionArgument"] = "BadFunctionArgument";
  TxRejectedReason["ContractAlreadyExists"] = "ContractAlreadyExists";
  TxRejectedReason["PoisonMicroblocksDoNotConflict"] = "PoisonMicroblocksDoNotConflict";
  TxRejectedReason["PoisonMicroblockHasUnknownPubKeyHash"] = "PoisonMicroblockHasUnknownPubKeyHash";
  TxRejectedReason["PoisonMicroblockIsInvalid"] = "PoisonMicroblockIsInvalid";
  TxRejectedReason["BadAddressVersionByte"] = "BadAddressVersionByte";
  TxRejectedReason["NoCoinbaseViaMempool"] = "NoCoinbaseViaMempool";
  TxRejectedReason["ServerFailureNoSuchChainTip"] = "ServerFailureNoSuchChainTip";
  TxRejectedReason["TooMuchChaining"] = "TooMuchChaining";
  TxRejectedReason["ConflictingNonceInMempool"] = "ConflictingNonceInMempool";
  TxRejectedReason["BadTransactionVersion"] = "BadTransactionVersion";
  TxRejectedReason["TransferRecipientCannotEqualSender"] = "TransferRecipientCannotEqualSender";
  TxRejectedReason["TransferAmountMustBePositive"] = "TransferAmountMustBePositive";
  TxRejectedReason["ServerFailureDatabase"] = "ServerFailureDatabase";
  TxRejectedReason["EstimatorError"] = "EstimatorError";
  TxRejectedReason["TemporarilyBlacklisted"] = "TemporarilyBlacklisted";
  TxRejectedReason["ServerFailureOther"] = "ServerFailureOther";
})(TxRejectedReason || (exports.TxRejectedReason = TxRejectedReason = {}));

},{}],44:[function(require,module,exports){
"use strict";

Object.defineProperty(exports, "__esModule", {
  value: true
});
exports.ClarityAbiTypeId = void 0;
exports.abiFunctionToString = abiFunctionToString;
exports.encodeClarityValue = encodeClarityValue;
exports.getTypeString = getTypeString;
exports.getTypeUnion = getTypeUnion;
exports.isClarityAbiTuple = exports.isClarityAbiStringUtf8 = exports.isClarityAbiStringAscii = exports.isClarityAbiResponse = exports.isClarityAbiPrimitive = exports.isClarityAbiOptional = exports.isClarityAbiList = exports.isClarityAbiBuffer = void 0;
exports.parseToCV = parseToCV;
exports.validateContractCall = validateContractCall;

var _utils = require("./utils");

var _clarity = require("./clarity");

var _errors = require("./errors");

var _stringCV = require("./clarity/types/stringCV");

var _common = require("@stacks/common");

var ClarityAbiTypeId;
exports.ClarityAbiTypeId = ClarityAbiTypeId;

(function (ClarityAbiTypeId) {
  ClarityAbiTypeId[ClarityAbiTypeId["ClarityAbiTypeUInt128"] = 1] = "ClarityAbiTypeUInt128";
  ClarityAbiTypeId[ClarityAbiTypeId["ClarityAbiTypeInt128"] = 2] = "ClarityAbiTypeInt128";
  ClarityAbiTypeId[ClarityAbiTypeId["ClarityAbiTypeBool"] = 3] = "ClarityAbiTypeBool";
  ClarityAbiTypeId[ClarityAbiTypeId["ClarityAbiTypePrincipal"] = 4] = "ClarityAbiTypePrincipal";
  ClarityAbiTypeId[ClarityAbiTypeId["ClarityAbiTypeNone"] = 5] = "ClarityAbiTypeNone";
  ClarityAbiTypeId[ClarityAbiTypeId["ClarityAbiTypeBuffer"] = 6] = "ClarityAbiTypeBuffer";
  ClarityAbiTypeId[ClarityAbiTypeId["ClarityAbiTypeResponse"] = 7] = "ClarityAbiTypeResponse";
  ClarityAbiTypeId[ClarityAbiTypeId["ClarityAbiTypeOptional"] = 8] = "ClarityAbiTypeOptional";
  ClarityAbiTypeId[ClarityAbiTypeId["ClarityAbiTypeTuple"] = 9] = "ClarityAbiTypeTuple";
  ClarityAbiTypeId[ClarityAbiTypeId["ClarityAbiTypeList"] = 10] = "ClarityAbiTypeList";
  ClarityAbiTypeId[ClarityAbiTypeId["ClarityAbiTypeStringAscii"] = 11] = "ClarityAbiTypeStringAscii";
  ClarityAbiTypeId[ClarityAbiTypeId["ClarityAbiTypeStringUtf8"] = 12] = "ClarityAbiTypeStringUtf8";
  ClarityAbiTypeId[ClarityAbiTypeId["ClarityAbiTypeTraitReference"] = 13] = "ClarityAbiTypeTraitReference";
})(ClarityAbiTypeId || (exports.ClarityAbiTypeId = ClarityAbiTypeId = {}));

const isClarityAbiPrimitive = val => typeof val === 'string';

exports.isClarityAbiPrimitive = isClarityAbiPrimitive;

const isClarityAbiBuffer = val => val.buffer !== undefined;

exports.isClarityAbiBuffer = isClarityAbiBuffer;

const isClarityAbiStringAscii = val => val['string-ascii'] !== undefined;

exports.isClarityAbiStringAscii = isClarityAbiStringAscii;

const isClarityAbiStringUtf8 = val => val['string-utf8'] !== undefined;

exports.isClarityAbiStringUtf8 = isClarityAbiStringUtf8;

const isClarityAbiResponse = val => val.response !== undefined;

exports.isClarityAbiResponse = isClarityAbiResponse;

const isClarityAbiOptional = val => val.optional !== undefined;

exports.isClarityAbiOptional = isClarityAbiOptional;

const isClarityAbiTuple = val => val.tuple !== undefined;

exports.isClarityAbiTuple = isClarityAbiTuple;

const isClarityAbiList = val => val.list !== undefined;

exports.isClarityAbiList = isClarityAbiList;

function getTypeUnion(val) {
  if (isClarityAbiPrimitive(val)) {
    if (val === 'uint128') {
      return {
        id: ClarityAbiTypeId.ClarityAbiTypeUInt128,
        type: val
      };
    } else if (val === 'int128') {
      return {
        id: ClarityAbiTypeId.ClarityAbiTypeInt128,
        type: val
      };
    } else if (val === 'bool') {
      return {
        id: ClarityAbiTypeId.ClarityAbiTypeBool,
        type: val
      };
    } else if (val === 'principal') {
      return {
        id: ClarityAbiTypeId.ClarityAbiTypePrincipal,
        type: val
      };
    } else if (val === 'trait_reference') {
      return {
        id: ClarityAbiTypeId.ClarityAbiTypeTraitReference,
        type: val
      };
    } else if (val === 'none') {
      return {
        id: ClarityAbiTypeId.ClarityAbiTypeNone,
        type: val
      };
    } else {
      throw new Error(`Unexpected Clarity ABI type primitive: ${JSON.stringify(val)}`);
    }
  } else if (isClarityAbiBuffer(val)) {
    return {
      id: ClarityAbiTypeId.ClarityAbiTypeBuffer,
      type: val
    };
  } else if (isClarityAbiResponse(val)) {
    return {
      id: ClarityAbiTypeId.ClarityAbiTypeResponse,
      type: val
    };
  } else if (isClarityAbiOptional(val)) {
    return {
      id: ClarityAbiTypeId.ClarityAbiTypeOptional,
      type: val
    };
  } else if (isClarityAbiTuple(val)) {
    return {
      id: ClarityAbiTypeId.ClarityAbiTypeTuple,
      type: val
    };
  } else if (isClarityAbiList(val)) {
    return {
      id: ClarityAbiTypeId.ClarityAbiTypeList,
      type: val
    };
  } else if (isClarityAbiStringAscii(val)) {
    return {
      id: ClarityAbiTypeId.ClarityAbiTypeStringAscii,
      type: val
    };
  } else if (isClarityAbiStringUtf8(val)) {
    return {
      id: ClarityAbiTypeId.ClarityAbiTypeStringUtf8,
      type: val
    };
  } else {
    throw new Error(`Unexpected Clarity ABI type: ${JSON.stringify(val)}`);
  }
}

function encodeClarityValue(input, val) {
  let union;

  if (input.id !== undefined) {
    union = input;
  } else {
    union = getTypeUnion(input);
  }

  switch (union.id) {
    case ClarityAbiTypeId.ClarityAbiTypeUInt128:
      return (0, _clarity.uintCV)(val);

    case ClarityAbiTypeId.ClarityAbiTypeInt128:
      return (0, _clarity.intCV)(val);

    case ClarityAbiTypeId.ClarityAbiTypeBool:
      if (val === 'false' || val === '0') return (0, _clarity.falseCV)();else if (val === 'true' || val === '1') return (0, _clarity.trueCV)();else throw new Error(`Unexpected Clarity bool value: ${JSON.stringify(val)}`);

    case ClarityAbiTypeId.ClarityAbiTypePrincipal:
      if (val.includes('.')) {
        const [addr, name] = val.split('.');
        return (0, _clarity.contractPrincipalCV)(addr, name);
      } else {
        return (0, _clarity.standardPrincipalCV)(val);
      }

    case ClarityAbiTypeId.ClarityAbiTypeTraitReference:
      const [addr, name] = val.split('.');
      return (0, _clarity.contractPrincipalCV)(addr, name);

    case ClarityAbiTypeId.ClarityAbiTypeNone:
      return (0, _clarity.noneCV)();

    case ClarityAbiTypeId.ClarityAbiTypeBuffer:
      return (0, _clarity.bufferCV)((0, _common.utf8ToBytes)(val));

    case ClarityAbiTypeId.ClarityAbiTypeStringAscii:
      return (0, _stringCV.stringAsciiCV)(val);

    case ClarityAbiTypeId.ClarityAbiTypeStringUtf8:
      return (0, _stringCV.stringUtf8CV)(val);

    case ClarityAbiTypeId.ClarityAbiTypeResponse:
      throw new _errors.NotImplementedError(`Unsupported encoding for Clarity type: ${union.id}`);

    case ClarityAbiTypeId.ClarityAbiTypeOptional:
      throw new _errors.NotImplementedError(`Unsupported encoding for Clarity type: ${union.id}`);

    case ClarityAbiTypeId.ClarityAbiTypeTuple:
      throw new _errors.NotImplementedError(`Unsupported encoding for Clarity type: ${union.id}`);

    case ClarityAbiTypeId.ClarityAbiTypeList:
      throw new _errors.NotImplementedError(`Unsupported encoding for Clarity type: ${union.id}`);

    default:
      throw new Error(`Unexpected Clarity type ID: ${JSON.stringify(union)}`);
  }
}

function getTypeString(val) {
  if (isClarityAbiPrimitive(val)) {
    if (val === 'int128') {
      return 'int';
    } else if (val === 'uint128') {
      return 'uint';
    }

    return val;
  } else if (isClarityAbiBuffer(val)) {
    return `(buff ${val.buffer.length})`;
  } else if (isClarityAbiStringAscii(val)) {
    return `(string-ascii ${val['string-ascii'].length})`;
  } else if (isClarityAbiStringUtf8(val)) {
    return `(string-utf8 ${val['string-utf8'].length})`;
  } else if (isClarityAbiResponse(val)) {
    return `(response ${getTypeString(val.response.ok)} ${getTypeString(val.response.error)})`;
  } else if (isClarityAbiOptional(val)) {
    return `(optional ${getTypeString(val.optional)})`;
  } else if (isClarityAbiTuple(val)) {
    return `(tuple ${val.tuple.map(t => `(${t.name} ${getTypeString(t.type)})`).join(' ')})`;
  } else if (isClarityAbiList(val)) {
    return `(list ${val.list.length} ${getTypeString(val.list.type)})`;
  } else {
    throw new Error(`Type string unsupported for Clarity type: ${JSON.stringify(val)}`);
  }
}

function abiFunctionToString(func) {
  const access = func.access === 'read_only' ? 'read-only' : func.access;
  return `(define-${access} (${func.name} ${func.args.map(arg => `(${arg.name} ${getTypeString(arg.type)})`).join(' ')}))`;
}

function matchType(cv, abiType) {
  const union = getTypeUnion(abiType);

  switch (cv.type) {
    case _clarity.ClarityType.BoolTrue:
    case _clarity.ClarityType.BoolFalse:
      return union.id === ClarityAbiTypeId.ClarityAbiTypeBool;

    case _clarity.ClarityType.Int:
      return union.id === ClarityAbiTypeId.ClarityAbiTypeInt128;

    case _clarity.ClarityType.UInt:
      return union.id === ClarityAbiTypeId.ClarityAbiTypeUInt128;

    case _clarity.ClarityType.Buffer:
      return union.id === ClarityAbiTypeId.ClarityAbiTypeBuffer && union.type.buffer.length >= cv.buffer.length;

    case _clarity.ClarityType.StringASCII:
      return union.id === ClarityAbiTypeId.ClarityAbiTypeStringAscii && union.type['string-ascii'].length >= cv.data.length;

    case _clarity.ClarityType.StringUTF8:
      return union.id === ClarityAbiTypeId.ClarityAbiTypeStringUtf8 && union.type['string-utf8'].length >= cv.data.length;

    case _clarity.ClarityType.OptionalNone:
      return union.id === ClarityAbiTypeId.ClarityAbiTypeNone || union.id === ClarityAbiTypeId.ClarityAbiTypeOptional;

    case _clarity.ClarityType.OptionalSome:
      return union.id === ClarityAbiTypeId.ClarityAbiTypeOptional && matchType(cv.value, union.type.optional);

    case _clarity.ClarityType.ResponseErr:
      return union.id === ClarityAbiTypeId.ClarityAbiTypeResponse && matchType(cv.value, union.type.response.error);

    case _clarity.ClarityType.ResponseOk:
      return union.id === ClarityAbiTypeId.ClarityAbiTypeResponse && matchType(cv.value, union.type.response.ok);

    case _clarity.ClarityType.PrincipalContract:
      return union.id === ClarityAbiTypeId.ClarityAbiTypePrincipal || union.id === ClarityAbiTypeId.ClarityAbiTypeTraitReference;

    case _clarity.ClarityType.PrincipalStandard:
      return union.id === ClarityAbiTypeId.ClarityAbiTypePrincipal;

    case _clarity.ClarityType.List:
      return union.id == ClarityAbiTypeId.ClarityAbiTypeList && union.type.list.length >= cv.list.length && cv.list.every(val => matchType(val, union.type.list.type));

    case _clarity.ClarityType.Tuple:
      if (union.id == ClarityAbiTypeId.ClarityAbiTypeTuple) {
        const tuple = (0, _utils.cloneDeep)(cv.data);

        for (let i = 0; i < union.type.tuple.length; i++) {
          const abiTupleEntry = union.type.tuple[i];
          const key = abiTupleEntry.name;
          const val = tuple[key];

          if (val) {
            if (!matchType(val, abiTupleEntry.type)) {
              return false;
            }

            delete tuple[key];
          } else {
            return false;
          }
        }

        return true;
      } else {
        return false;
      }

    default:
      return false;
  }
}

function validateContractCall(payload, abi) {
  const filtered = abi.functions.filter(fn => fn.name === payload.functionName.content);

  if (filtered.length === 1) {
    const abiFunc = filtered[0];
    const abiArgs = abiFunc.args;

    if (payload.functionArgs.length !== abiArgs.length) {
      throw new Error(`Clarity function expects ${abiArgs.length} argument(s) but received ${payload.functionArgs.length}`);
    }

    for (let i = 0; i < payload.functionArgs.length; i++) {
      const payloadArg = payload.functionArgs[i];
      const abiArg = abiArgs[i];

      if (!matchType(payloadArg, abiArg.type)) {
        const argNum = i + 1;
        throw new Error(`Clarity function \`${payload.functionName.content}\` expects argument ${argNum} to be of type ${getTypeString(abiArg.type)}, not ${(0, _clarity.getCVTypeString)(payloadArg)}`);
      }
    }

    return true;
  } else if (filtered.length === 0) {
    throw new Error(`ABI doesn't contain a function with the name ${payload.functionName.content}`);
  } else {
    throw new Error(`Malformed ABI. Contains multiple functions with the name ${payload.functionName.content}`);
  }
}

function parseToCV(input, type) {
  const typeString = getTypeString(type);

  if (isClarityAbiPrimitive(type)) {
    if (type === 'uint128') {
      return (0, _clarity.uintCV)(input);
    } else if (type === 'int128') {
      return (0, _clarity.intCV)(input);
    } else if (type === 'bool') {
      if (input.toLowerCase() === 'true') {
        return (0, _clarity.trueCV)();
      } else if (input.toLowerCase() === 'false') {
        return (0, _clarity.falseCV)();
      } else {
        throw new Error(`Invalid bool value: ${input}`);
      }
    } else if (type === 'principal') {
      if (input.includes('.')) {
        const [address, contractName] = input.split('.');
        return (0, _clarity.contractPrincipalCV)(address, contractName);
      } else {
        return (0, _clarity.standardPrincipalCV)(input);
      }
    } else {
      throw new Error(`Contract function contains unsupported Clarity ABI type: ${typeString}`);
    }
  } else if (isClarityAbiBuffer(type)) {
    const inputLength = (0, _common.utf8ToBytes)(input).byteLength;

    if (inputLength > type.buffer.length) {
      throw new Error(`Input exceeds specified buffer length limit of ${type.buffer.length}`);
    }

    return (0, _clarity.bufferCVFromString)(input);
  } else if (isClarityAbiResponse(type)) {
    throw new Error(`Contract function contains unsupported Clarity ABI type: ${typeString}`);
  } else if (isClarityAbiOptional(type)) {
    throw new Error(`Contract function contains unsupported Clarity ABI type: ${typeString}`);
  } else if (isClarityAbiTuple(type)) {
    throw new Error(`Contract function contains unsupported Clarity ABI type: ${typeString}`);
  } else if (isClarityAbiList(type)) {
    throw new Error(`Contract function contains unsupported Clarity ABI type: ${typeString}`);
  } else {
    throw new Error(`Contract function contains unsupported Clarity ABI type: ${typeString}`);
  }
}

},{"./clarity":30,"./clarity/types/stringCV":40,"./errors":45,"./utils":57,"@stacks/common":15}],45:[function(require,module,exports){
"use strict";

Object.defineProperty(exports, "__esModule", {
  value: true
});
exports.VerificationError = exports.SigningError = exports.SerializationError = exports.NotImplementedError = exports.NoEstimateAvailableError = exports.DeserializationError = void 0;

class TransactionError extends Error {
  constructor(message) {
    super(message);
    this.message = message;
    this.name = this.constructor.name;

    if (Error.captureStackTrace) {
      Error.captureStackTrace(this, this.constructor);
    }
  }

}

class SerializationError extends TransactionError {
  constructor(message) {
    super(message);
  }

}

exports.SerializationError = SerializationError;

class DeserializationError extends TransactionError {
  constructor(message) {
    super(message);
  }

}

exports.DeserializationError = DeserializationError;

class NoEstimateAvailableError extends TransactionError {
  constructor(message) {
    super(message);
  }

}

exports.NoEstimateAvailableError = NoEstimateAvailableError;

class NotImplementedError extends TransactionError {
  constructor(message) {
    super(message);
  }

}

exports.NotImplementedError = NotImplementedError;

class SigningError extends TransactionError {
  constructor(message) {
    super(message);
  }

}

exports.SigningError = SigningError;

class VerificationError extends TransactionError {
  constructor(message) {
    super(message);
  }

}

exports.VerificationError = VerificationError;

},{}],46:[function(require,module,exports){
"use strict";

Object.defineProperty(exports, "__esModule", {
  value: true
});
var _exportNames = {
  emptyMessageSignature: true,
  isSingleSig: true,
  BytesReader: true,
  Cl: true,
  isCoinbasePayload: true,
  isContractCallPayload: true,
  isPoisonPayload: true,
  isSmartContractPayload: true,
  isTokenTransferPayload: true,
  serializePayload: true,
  Pc: true,
  createFungiblePostCondition: true,
  createNonFungiblePostCondition: true,
  createSTXPostCondition: true,
  StacksTransaction: true,
  deserializeTransaction: true
};
Object.defineProperty(exports, "BytesReader", {
  enumerable: true,
  get: function () {
    return _bytesReader.BytesReader;
  }
});
exports.Pc = exports.Cl = void 0;
Object.defineProperty(exports, "StacksTransaction", {
  enumerable: true,
  get: function () {
    return _transaction.StacksTransaction;
  }
});
Object.defineProperty(exports, "createFungiblePostCondition", {
  enumerable: true,
  get: function () {
    return _postcondition.createFungiblePostCondition;
  }
});
Object.defineProperty(exports, "createNonFungiblePostCondition", {
  enumerable: true,
  get: function () {
    return _postcondition.createNonFungiblePostCondition;
  }
});
Object.defineProperty(exports, "createSTXPostCondition", {
  enumerable: true,
  get: function () {
    return _postcondition.createSTXPostCondition;
  }
});
Object.defineProperty(exports, "deserializeTransaction", {
  enumerable: true,
  get: function () {
    return _transaction.deserializeTransaction;
  }
});
Object.defineProperty(exports, "emptyMessageSignature", {
  enumerable: true,
  get: function () {
    return _authorization.emptyMessageSignature;
  }
});
Object.defineProperty(exports, "isCoinbasePayload", {
  enumerable: true,
  get: function () {
    return _payload.isCoinbasePayload;
  }
});
Object.defineProperty(exports, "isContractCallPayload", {
  enumerable: true,
  get: function () {
    return _payload.isContractCallPayload;
  }
});
Object.defineProperty(exports, "isPoisonPayload", {
  enumerable: true,
  get: function () {
    return _payload.isPoisonPayload;
  }
});
Object.defineProperty(exports, "isSingleSig", {
  enumerable: true,
  get: function () {
    return _authorization.isSingleSig;
  }
});
Object.defineProperty(exports, "isSmartContractPayload", {
  enumerable: true,
  get: function () {
    return _payload.isSmartContractPayload;
  }
});
Object.defineProperty(exports, "isTokenTransferPayload", {
  enumerable: true,
  get: function () {
    return _payload.isTokenTransferPayload;
  }
});
Object.defineProperty(exports, "serializePayload", {
  enumerable: true,
  get: function () {
    return _payload.serializePayload;
  }
});

var _authorization = require("./authorization");

Object.keys(_authorization).forEach(function (key) {
  if (key === "default" || key === "__esModule") return;
  if (Object.prototype.hasOwnProperty.call(_exportNames, key)) return;
  if (key in exports && exports[key] === _authorization[key]) return;
  Object.defineProperty(exports, key, {
    enumerable: true,
    get: function () {
      return _authorization[key];
    }
  });
});

var _builders = require("./builders");

Object.keys(_builders).forEach(function (key) {
  if (key === "default" || key === "__esModule") return;
  if (Object.prototype.hasOwnProperty.call(_exportNames, key)) return;
  if (key in exports && exports[key] === _builders[key]) return;
  Object.defineProperty(exports, key, {
    enumerable: true,
    get: function () {
      return _builders[key];
    }
  });
});

var _bytesReader = require("./bytesReader");

var Cl_1 = _interopRequireWildcard(require("./cl"));

exports.Cl = Cl_1;

var _clarity = require("./clarity");

Object.keys(_clarity).forEach(function (key) {
  if (key === "default" || key === "__esModule") return;
  if (Object.prototype.hasOwnProperty.call(_exportNames, key)) return;
  if (key in exports && exports[key] === _clarity[key]) return;
  Object.defineProperty(exports, key, {
    enumerable: true,
    get: function () {
      return _clarity[key];
    }
  });
});

var _common = require("./common");

Object.keys(_common).forEach(function (key) {
  if (key === "default" || key === "__esModule") return;
  if (Object.prototype.hasOwnProperty.call(_exportNames, key)) return;
  if (key in exports && exports[key] === _common[key]) return;
  Object.defineProperty(exports, key, {
    enumerable: true,
    get: function () {
      return _common[key];
    }
  });
});

var _constants = require("./constants");

Object.keys(_constants).forEach(function (key) {
  if (key === "default" || key === "__esModule") return;
  if (Object.prototype.hasOwnProperty.call(_exportNames, key)) return;
  if (key in exports && exports[key] === _constants[key]) return;
  Object.defineProperty(exports, key, {
    enumerable: true,
    get: function () {
      return _constants[key];
    }
  });
});

var _contractAbi = require("./contract-abi");

Object.keys(_contractAbi).forEach(function (key) {
  if (key === "default" || key === "__esModule") return;
  if (Object.prototype.hasOwnProperty.call(_exportNames, key)) return;
  if (key in exports && exports[key] === _contractAbi[key]) return;
  Object.defineProperty(exports, key, {
    enumerable: true,
    get: function () {
      return _contractAbi[key];
    }
  });
});

var _keys = require("./keys");

Object.keys(_keys).forEach(function (key) {
  if (key === "default" || key === "__esModule") return;
  if (Object.prototype.hasOwnProperty.call(_exportNames, key)) return;
  if (key in exports && exports[key] === _keys[key]) return;
  Object.defineProperty(exports, key, {
    enumerable: true,
    get: function () {
      return _keys[key];
    }
  });
});

var _payload = require("./payload");

var Pc_1 = _interopRequireWildcard(require("./pc"));

exports.Pc = Pc_1;

var _postcondition = require("./postcondition");

var _postconditionTypes = require("./postcondition-types");

Object.keys(_postconditionTypes).forEach(function (key) {
  if (key === "default" || key === "__esModule") return;
  if (Object.prototype.hasOwnProperty.call(_exportNames, key)) return;
  if (key in exports && exports[key] === _postconditionTypes[key]) return;
  Object.defineProperty(exports, key, {
    enumerable: true,
    get: function () {
      return _postconditionTypes[key];
    }
  });
});

var _signature = require("./signature");

Object.keys(_signature).forEach(function (key) {
  if (key === "default" || key === "__esModule") return;
  if (Object.prototype.hasOwnProperty.call(_exportNames, key)) return;
  if (key in exports && exports[key] === _signature[key]) return;
  Object.defineProperty(exports, key, {
    enumerable: true,
    get: function () {
      return _signature[key];
    }
  });
});

var _signer = require("./signer");

Object.keys(_signer).forEach(function (key) {
  if (key === "default" || key === "__esModule") return;
  if (Object.prototype.hasOwnProperty.call(_exportNames, key)) return;
  if (key in exports && exports[key] === _signer[key]) return;
  Object.defineProperty(exports, key, {
    enumerable: true,
    get: function () {
      return _signer[key];
    }
  });
});

var _structuredDataSignature = require("./structuredDataSignature");

Object.keys(_structuredDataSignature).forEach(function (key) {
  if (key === "default" || key === "__esModule") return;
  if (Object.prototype.hasOwnProperty.call(_exportNames, key)) return;
  if (key in exports && exports[key] === _structuredDataSignature[key]) return;
  Object.defineProperty(exports, key, {
    enumerable: true,
    get: function () {
      return _structuredDataSignature[key];
    }
  });
});

var _transaction = require("./transaction");

var _types = require("./types");

Object.keys(_types).forEach(function (key) {
  if (key === "default" || key === "__esModule") return;
  if (Object.prototype.hasOwnProperty.call(_exportNames, key)) return;
  if (key in exports && exports[key] === _types[key]) return;
  Object.defineProperty(exports, key, {
    enumerable: true,
    get: function () {
      return _types[key];
    }
  });
});

var _utils = require("./utils");

Object.keys(_utils).forEach(function (key) {
  if (key === "default" || key === "__esModule") return;
  if (Object.prototype.hasOwnProperty.call(_exportNames, key)) return;
  if (key in exports && exports[key] === _utils[key]) return;
  Object.defineProperty(exports, key, {
    enumerable: true,
    get: function () {
      return _utils[key];
    }
  });
});

function _getRequireWildcardCache(nodeInterop) { if (typeof WeakMap !== "function") return null; var cacheBabelInterop = new WeakMap(); var cacheNodeInterop = new WeakMap(); return (_getRequireWildcardCache = function (nodeInterop) { return nodeInterop ? cacheNodeInterop : cacheBabelInterop; })(nodeInterop); }

function _interopRequireWildcard(obj, nodeInterop) { if (!nodeInterop && obj && obj.__esModule) { return obj; } if (obj === null || typeof obj !== "object" && typeof obj !== "function") { return { default: obj }; } var cache = _getRequireWildcardCache(nodeInterop); if (cache && cache.has(obj)) { return cache.get(obj); } var newObj = {}; var hasPropertyDescriptor = Object.defineProperty && Object.getOwnPropertyDescriptor; for (var key in obj) { if (key !== "default" && Object.prototype.hasOwnProperty.call(obj, key)) { var desc = hasPropertyDescriptor ? Object.getOwnPropertyDescriptor(obj, key) : null; if (desc && (desc.get || desc.set)) { Object.defineProperty(newObj, key, desc); } else { newObj[key] = obj[key]; } } } newObj.default = obj; if (cache) { cache.set(obj, newObj); } return newObj; }

},{"./authorization":23,"./builders":24,"./bytesReader":25,"./cl":26,"./clarity":30,"./common":42,"./constants":43,"./contract-abi":44,"./keys":47,"./payload":48,"./pc":49,"./postcondition":51,"./postcondition-types":50,"./signature":52,"./signer":53,"./structuredDataSignature":54,"./transaction":55,"./types":56,"./utils":57}],47:[function(require,module,exports){
"use strict";

Object.defineProperty(exports, "__esModule", {
  value: true
});
exports.compressPublicKey = compressPublicKey;
exports.createStacksPrivateKey = createStacksPrivateKey;
exports.createStacksPublicKey = createStacksPublicKey;
exports.deserializePublicKey = deserializePublicKey;
exports.getAddressFromPrivateKey = getAddressFromPrivateKey;
exports.getAddressFromPublicKey = getAddressFromPublicKey;
exports.getPublicKey = getPublicKey;
exports.isCompressed = isCompressed;
exports.makeRandomPrivKey = makeRandomPrivKey;
exports.privateKeyToString = privateKeyToString;
exports.pubKeyfromPrivKey = pubKeyfromPrivKey;
exports.publicKeyFromBytes = publicKeyFromBytes;
exports.publicKeyFromSignatureRsv = publicKeyFromSignatureRsv;
exports.publicKeyFromSignatureVrs = publicKeyFromSignatureVrs;
exports.publicKeyToAddress = publicKeyToAddress;
exports.publicKeyToString = publicKeyToString;
exports.serializePublicKey = serializePublicKey;
exports.signMessageHashRsv = signMessageHashRsv;
exports.signWithKey = signWithKey;

var _hmac = require("@noble/hashes/hmac");

var _sha = require("@noble/hashes/sha256");

var _secp256k = require("@noble/secp256k1");

var _common = require("@stacks/common");

var _c32check = require("c32check");

var _common2 = require("./common");

var _constants = require("./constants");

var _utils = require("./utils");

_secp256k.utils.hmacSha256Sync = (key, ...msgs) => {
  const h = _hmac.hmac.create(_sha.sha256, key);

  msgs.forEach(msg => h.update(msg));
  return h.digest();
};

function getAddressFromPrivateKey(privateKey, transactionVersion = _constants.TransactionVersion.Mainnet) {
  const pubKey = pubKeyfromPrivKey(privateKey);
  return getAddressFromPublicKey(pubKey.data, transactionVersion);
}

function getAddressFromPublicKey(publicKey, transactionVersion = _constants.TransactionVersion.Mainnet) {
  publicKey = typeof publicKey === 'string' ? publicKey : (0, _common.bytesToHex)(publicKey);
  const addrVer = (0, _common2.addressHashModeToVersion)(_constants.AddressHashMode.SerializeP2PKH, transactionVersion);
  const addr = (0, _common2.addressFromVersionHash)(addrVer, (0, _utils.hashP2PKH)((0, _common.hexToBytes)(publicKey)));
  const addrString = (0, _common2.addressToString)(addr);
  return addrString;
}

function createStacksPublicKey(key) {
  return {
    type: _constants.StacksMessageType.PublicKey,
    data: (0, _common.hexToBytes)(key)
  };
}

function publicKeyFromSignatureVrs(messageHash, messageSignature, pubKeyEncoding = _constants.PubKeyEncoding.Compressed) {
  const parsedSignature = (0, _common.parseRecoverableSignatureVrs)(messageSignature.data);
  const signature = new _secp256k.Signature((0, _common.hexToBigInt)(parsedSignature.r), (0, _common.hexToBigInt)(parsedSignature.s));

  const point = _secp256k.Point.fromSignature(messageHash, signature, parsedSignature.recoveryId);

  const compressed = pubKeyEncoding === _constants.PubKeyEncoding.Compressed;
  return point.toHex(compressed);
}

function publicKeyFromSignatureRsv(messageHash, messageSignature, pubKeyEncoding = _constants.PubKeyEncoding.Compressed) {
  return publicKeyFromSignatureVrs(messageHash, { ...messageSignature,
    data: (0, _common.signatureRsvToVrs)(messageSignature.data)
  }, pubKeyEncoding);
}

function publicKeyFromBytes(data) {
  return {
    type: _constants.StacksMessageType.PublicKey,
    data
  };
}

function isCompressed(key) {
  return !(0, _common.bytesToHex)(key.data).startsWith('04');
}

function publicKeyToString(key) {
  return (0, _common.bytesToHex)(key.data);
}

function serializePublicKey(key) {
  return key.data.slice();
}

function pubKeyfromPrivKey(privateKey) {
  const privKey = createStacksPrivateKey(privateKey);
  const publicKey = (0, _secp256k.getPublicKey)(privKey.data.slice(0, 32), privKey.compressed);
  return createStacksPublicKey((0, _common.bytesToHex)(publicKey));
}

function compressPublicKey(publicKey) {
  const hex = typeof publicKey === 'string' ? publicKey : (0, _common.bytesToHex)(publicKey);

  const compressed = _secp256k.Point.fromHex(hex).toHex(true);

  return createStacksPublicKey(compressed);
}

function deserializePublicKey(bytesReader) {
  const fieldId = bytesReader.readUInt8();
  const keyLength = fieldId === 4 ? _constants.UNCOMPRESSED_PUBKEY_LENGTH_BYTES : _constants.COMPRESSED_PUBKEY_LENGTH_BYTES;
  return publicKeyFromBytes((0, _common.concatArray)([fieldId, bytesReader.readBytes(keyLength)]));
}

function createStacksPrivateKey(key) {
  const data = (0, _common.privateKeyToBytes)(key);
  const compressed = data.length == _common.PRIVATE_KEY_COMPRESSED_LENGTH;
  return {
    data,
    compressed
  };
}

function makeRandomPrivKey() {
  return createStacksPrivateKey(_secp256k.utils.randomPrivateKey());
}

function signWithKey(privateKey, messageHash) {
  const [rawSignature, recoveryId] = (0, _secp256k.signSync)(messageHash, privateKey.data.slice(0, 32), {
    canonical: true,
    recovered: true
  });

  if (recoveryId == null) {
    throw new Error('No signature recoveryId received');
  }

  const recoveryIdHex = (0, _common.intToHex)(recoveryId, 1);

  const recoverableSignatureString = recoveryIdHex + _secp256k.Signature.fromHex(rawSignature).toCompactHex();

  return (0, _common2.createMessageSignature)(recoverableSignatureString);
}

function signMessageHashRsv({
  messageHash,
  privateKey
}) {
  const messageSignature = signWithKey(privateKey, messageHash);
  return { ...messageSignature,
    data: (0, _common.signatureVrsToRsv)(messageSignature.data)
  };
}

function getPublicKey(privateKey) {
  return pubKeyfromPrivKey(privateKey.data);
}

function privateKeyToString(privateKey) {
  return (0, _common.bytesToHex)(privateKey.data);
}

function publicKeyToAddress(version, publicKey) {
  return (0, _c32check.c32address)(version, (0, _common.bytesToHex)((0, _utils.hash160)(publicKey.data)));
}

},{"./common":42,"./constants":43,"./utils":57,"@noble/hashes/hmac":5,"@noble/hashes/sha256":7,"@noble/secp256k1":10,"@stacks/common":15,"c32check":63}],48:[function(require,module,exports){
"use strict";

Object.defineProperty(exports, "__esModule", {
  value: true
});
exports.createCoinbasePayload = createCoinbasePayload;
exports.createContractCallPayload = createContractCallPayload;
exports.createPoisonPayload = createPoisonPayload;
exports.createSmartContractPayload = createSmartContractPayload;
exports.createTokenTransferPayload = createTokenTransferPayload;
exports.deserializePayload = deserializePayload;
exports.isCoinbasePayload = isCoinbasePayload;
exports.isContractCallPayload = isContractCallPayload;
exports.isPoisonPayload = isPoisonPayload;
exports.isSmartContractPayload = isSmartContractPayload;
exports.isTokenTransferPayload = isTokenTransferPayload;
exports.serializePayload = serializePayload;

var _common = require("@stacks/common");

var _constants = require("./constants");

var _clarity = require("./clarity/");

var _principalCV = require("./clarity/types/principalCV");

var _postconditionTypes = require("./postcondition-types");

var _types = require("./types");

function isTokenTransferPayload(p) {
  return p.payloadType === _constants.PayloadType.TokenTransfer;
}

function isContractCallPayload(p) {
  return p.payloadType === _constants.PayloadType.ContractCall;
}

function isSmartContractPayload(p) {
  return p.payloadType === _constants.PayloadType.SmartContract;
}

function isPoisonPayload(p) {
  return p.payloadType === _constants.PayloadType.PoisonMicroblock;
}

function isCoinbasePayload(p) {
  return p.payloadType === _constants.PayloadType.Coinbase;
}

function createTokenTransferPayload(recipient, amount, memo) {
  if (typeof recipient === 'string') {
    recipient = (0, _principalCV.principalCV)(recipient);
  }

  if (typeof memo === 'string') {
    memo = (0, _types.createMemoString)(memo);
  }

  return {
    type: _constants.StacksMessageType.Payload,
    payloadType: _constants.PayloadType.TokenTransfer,
    recipient,
    amount: (0, _common.intToBigInt)(amount, false),
    memo: memo ?? (0, _types.createMemoString)('')
  };
}

function createContractCallPayload(contractAddress, contractName, functionName, functionArgs) {
  if (typeof contractAddress === 'string') {
    contractAddress = (0, _postconditionTypes.createAddress)(contractAddress);
  }

  if (typeof contractName === 'string') {
    contractName = (0, _postconditionTypes.createLPString)(contractName);
  }

  if (typeof functionName === 'string') {
    functionName = (0, _postconditionTypes.createLPString)(functionName);
  }

  return {
    type: _constants.StacksMessageType.Payload,
    payloadType: _constants.PayloadType.ContractCall,
    contractAddress,
    contractName,
    functionName,
    functionArgs
  };
}

function createSmartContractPayload(contractName, codeBody, clarityVersion) {
  if (typeof contractName === 'string') {
    contractName = (0, _postconditionTypes.createLPString)(contractName);
  }

  if (typeof codeBody === 'string') {
    codeBody = (0, _types.codeBodyString)(codeBody);
  }

  if (typeof clarityVersion === 'number') {
    return {
      type: _constants.StacksMessageType.Payload,
      payloadType: _constants.PayloadType.VersionedSmartContract,
      clarityVersion,
      contractName,
      codeBody
    };
  }

  return {
    type: _constants.StacksMessageType.Payload,
    payloadType: _constants.PayloadType.SmartContract,
    contractName,
    codeBody
  };
}

function createPoisonPayload() {
  return {
    type: _constants.StacksMessageType.Payload,
    payloadType: _constants.PayloadType.PoisonMicroblock
  };
}

function createCoinbasePayload(coinbaseBytes, altRecipient) {
  if (coinbaseBytes.byteLength != _constants.COINBASE_BYTES_LENGTH) {
    throw Error(`Coinbase buffer size must be ${_constants.COINBASE_BYTES_LENGTH} bytes`);
  }

  if (altRecipient != undefined) {
    return {
      type: _constants.StacksMessageType.Payload,
      payloadType: _constants.PayloadType.CoinbaseToAltRecipient,
      coinbaseBytes,
      recipient: altRecipient
    };
  }

  return {
    type: _constants.StacksMessageType.Payload,
    payloadType: _constants.PayloadType.Coinbase,
    coinbaseBytes
  };
}

function serializePayload(payload) {
  const bytesArray = [];
  bytesArray.push(payload.payloadType);

  switch (payload.payloadType) {
    case _constants.PayloadType.TokenTransfer:
      bytesArray.push((0, _clarity.serializeCV)(payload.recipient));
      bytesArray.push((0, _common.intToBytes)(payload.amount, false, 8));
      bytesArray.push((0, _types.serializeStacksMessage)(payload.memo));
      break;

    case _constants.PayloadType.ContractCall:
      bytesArray.push((0, _types.serializeStacksMessage)(payload.contractAddress));
      bytesArray.push((0, _types.serializeStacksMessage)(payload.contractName));
      bytesArray.push((0, _types.serializeStacksMessage)(payload.functionName));
      const numArgs = new Uint8Array(4);
      (0, _common.writeUInt32BE)(numArgs, payload.functionArgs.length, 0);
      bytesArray.push(numArgs);
      payload.functionArgs.forEach(arg => {
        bytesArray.push((0, _clarity.serializeCV)(arg));
      });
      break;

    case _constants.PayloadType.SmartContract:
      bytesArray.push((0, _types.serializeStacksMessage)(payload.contractName));
      bytesArray.push((0, _types.serializeStacksMessage)(payload.codeBody));
      break;

    case _constants.PayloadType.VersionedSmartContract:
      bytesArray.push(payload.clarityVersion);
      bytesArray.push((0, _types.serializeStacksMessage)(payload.contractName));
      bytesArray.push((0, _types.serializeStacksMessage)(payload.codeBody));
      break;

    case _constants.PayloadType.PoisonMicroblock:
      break;

    case _constants.PayloadType.Coinbase:
      bytesArray.push(payload.coinbaseBytes);
      break;

    case _constants.PayloadType.CoinbaseToAltRecipient:
      bytesArray.push(payload.coinbaseBytes);
      bytesArray.push((0, _clarity.serializeCV)(payload.recipient));
      break;
  }

  return (0, _common.concatArray)(bytesArray);
}

function deserializePayload(bytesReader) {
  const payloadType = bytesReader.readUInt8Enum(_constants.PayloadType, n => {
    throw new Error(`Cannot recognize PayloadType: ${n}`);
  });

  switch (payloadType) {
    case _constants.PayloadType.TokenTransfer:
      const recipient = (0, _clarity.deserializeCV)(bytesReader);
      const amount = (0, _common.intToBigInt)(bytesReader.readBytes(8), false);
      const memo = (0, _types.deserializeMemoString)(bytesReader);
      return createTokenTransferPayload(recipient, amount, memo);

    case _constants.PayloadType.ContractCall:
      const contractAddress = (0, _types.deserializeAddress)(bytesReader);
      const contractCallName = (0, _types.deserializeLPString)(bytesReader);
      const functionName = (0, _types.deserializeLPString)(bytesReader);
      const functionArgs = [];
      const numberOfArgs = bytesReader.readUInt32BE();

      for (let i = 0; i < numberOfArgs; i++) {
        const clarityValue = (0, _clarity.deserializeCV)(bytesReader);
        functionArgs.push(clarityValue);
      }

      return createContractCallPayload(contractAddress, contractCallName, functionName, functionArgs);

    case _constants.PayloadType.SmartContract:
      const smartContractName = (0, _types.deserializeLPString)(bytesReader);
      const codeBody = (0, _types.deserializeLPString)(bytesReader, 4, 100000);
      return createSmartContractPayload(smartContractName, codeBody);

    case _constants.PayloadType.VersionedSmartContract:
      {
        const clarityVersion = bytesReader.readUInt8Enum(_constants.ClarityVersion, n => {
          throw new Error(`Cannot recognize ClarityVersion: ${n}`);
        });
        const smartContractName = (0, _types.deserializeLPString)(bytesReader);
        const codeBody = (0, _types.deserializeLPString)(bytesReader, 4, 100000);
        return createSmartContractPayload(smartContractName, codeBody, clarityVersion);
      }

    case _constants.PayloadType.PoisonMicroblock:
      return createPoisonPayload();

    case _constants.PayloadType.Coinbase:
      const coinbaseBytes = bytesReader.readBytes(_constants.COINBASE_BYTES_LENGTH);
      return createCoinbasePayload(coinbaseBytes);

    case _constants.PayloadType.CoinbaseToAltRecipient:
      const coinbaseToAltRecipientBuffer = bytesReader.readBytes(_constants.COINBASE_BYTES_LENGTH);
      const altRecipient = (0, _clarity.deserializeCV)(bytesReader);
      return createCoinbasePayload(coinbaseToAltRecipientBuffer, altRecipient);
  }
}

},{"./clarity/":30,"./clarity/types/principalCV":38,"./constants":43,"./postcondition-types":50,"./types":56,"@stacks/common":15}],49:[function(require,module,exports){
"use strict";

Object.defineProperty(exports, "__esModule", {
  value: true
});
exports.principal = principal;

var _builders = require("./builders");

var _constants = require("./constants");

var _postconditionTypes = require("./postcondition-types");

function principal(principal) {
  if (isContractIdString(principal)) {
    const [address, name] = parseContractId(principal);
    return new PartialPcWithPrincipal(address, name);
  }

  return new PartialPcWithPrincipal(principal, undefined);
}

class PartialPcWithPrincipal {
  constructor(address, contractName) {
    this.address = address;
    this.contractName = contractName;
  }

  willSendEq(amount) {
    return new PartialPcFtWithCode(this.address, amount, _constants.FungibleConditionCode.Equal, this.contractName);
  }

  willSendLte(amount) {
    return new PartialPcFtWithCode(this.address, amount, _constants.FungibleConditionCode.LessEqual, this.contractName);
  }

  willSendLt(amount) {
    return new PartialPcFtWithCode(this.address, amount, _constants.FungibleConditionCode.Less, this.contractName);
  }

  willSendGte(amount) {
    return new PartialPcFtWithCode(this.address, amount, _constants.FungibleConditionCode.GreaterEqual, this.contractName);
  }

  willSendGt(amount) {
    return new PartialPcFtWithCode(this.address, amount, _constants.FungibleConditionCode.Greater, this.contractName);
  }

  willSendAsset() {
    return new PartialPcNftWithCode(this.address, _constants.NonFungibleConditionCode.Sends, this.contractName);
  }

  willNotSendAsset() {
    return new PartialPcNftWithCode(this.address, _constants.NonFungibleConditionCode.DoesNotSend, this.contractName);
  }

}

class PartialPcFtWithCode {
  constructor(address, amount, code, contractName) {
    this.address = address;
    this.amount = amount;
    this.code = code;
    this.contractName = contractName;
  }

  ustx() {
    if (this.contractName) {
      return (0, _builders.makeContractSTXPostCondition)(this.address, this.contractName, this.code, this.amount);
    }

    return (0, _builders.makeStandardSTXPostCondition)(this.address, this.code, this.amount);
  }

  ft(contractId, tokenName) {
    const [address, name] = parseContractId(contractId);

    if (this.contractName) {
      return (0, _builders.makeContractFungiblePostCondition)(this.address, this.contractName, this.code, this.amount, (0, _postconditionTypes.createAssetInfo)(address, name, tokenName));
    }

    return (0, _builders.makeStandardFungiblePostCondition)(this.address, this.code, this.amount, (0, _postconditionTypes.createAssetInfo)(address, name, tokenName));
  }

}

class PartialPcNftWithCode {
  constructor(principal, code, contractName) {
    this.principal = principal;
    this.code = code;
    this.contractName = contractName;
  }

  nft(...args) {
    const {
      contractAddress,
      contractName,
      tokenName,
      assetId
    } = getNftArgs(...args);

    if (this.contractName) {
      return (0, _builders.makeContractNonFungiblePostCondition)(this.principal, this.contractName, this.code, (0, _postconditionTypes.createAssetInfo)(contractAddress, contractName, tokenName), assetId);
    }

    return (0, _builders.makeStandardNonFungiblePostCondition)(this.principal, this.code, (0, _postconditionTypes.createAssetInfo)(contractAddress, contractName, tokenName), assetId);
  }

}

function parseContractId(contractId) {
  const [address, name] = contractId.split('.');
  if (!address || !name) throw new Error(`Invalid contract identifier: ${contractId}`);
  return [address, name];
}

function parseNft(nftAssetName) {
  const [principal, tokenName] = nftAssetName.split('::');
  if (!principal || !tokenName) throw new Error(`Invalid fully-qualified nft asset name: ${nftAssetName}`);
  const [address, name] = parseContractId(principal);
  return {
    contractAddress: address,
    contractName: name,
    tokenName
  };
}

function isContractIdString(value) {
  return value.includes('.');
}

function getNftArgs(...args) {
  if (args.length === 2) {
    const [assetName, assetId] = args;
    return { ...parseNft(assetName),
      assetId
    };
  }

  const [contractId, tokenName, assetId] = args;
  const [address, name] = parseContractId(contractId);
  return {
    contractAddress: address,
    contractName: name,
    tokenName,
    assetId
  };
}

},{"./builders":24,"./constants":43,"./postcondition-types":50}],50:[function(require,module,exports){
"use strict";

Object.defineProperty(exports, "__esModule", {
  value: true
});
exports.createAddress = createAddress;
exports.createAssetInfo = createAssetInfo;
exports.createContractPrincipal = createContractPrincipal;
exports.createLPString = createLPString;
exports.createStandardPrincipal = createStandardPrincipal;
exports.parseAssetInfoString = parseAssetInfoString;
exports.parsePrincipalString = parsePrincipalString;

var _constants = require("./constants");

var _c32check = require("c32check");

var _utils = require("./utils");

function parseAssetInfoString(id) {
  const [assetAddress, assetContractName, assetTokenName] = id.split(/\.|::/);
  const assetInfo = createAssetInfo(assetAddress, assetContractName, assetTokenName);
  return assetInfo;
}

function createLPString(content, lengthPrefixBytes, maxLengthBytes) {
  const prefixLength = lengthPrefixBytes || 1;
  const maxLength = maxLengthBytes || _constants.MAX_STRING_LENGTH_BYTES;

  if ((0, _utils.exceedsMaxLengthBytes)(content, maxLength)) {
    throw new Error(`String length exceeds maximum bytes ${maxLength}`);
  }

  return {
    type: _constants.StacksMessageType.LengthPrefixedString,
    content,
    lengthPrefixBytes: prefixLength,
    maxLengthBytes: maxLength
  };
}

function createAssetInfo(addressString, contractName, assetName) {
  return {
    type: _constants.StacksMessageType.AssetInfo,
    address: createAddress(addressString),
    contractName: createLPString(contractName),
    assetName: createLPString(assetName)
  };
}

function createAddress(c32AddressString) {
  const addressData = (0, _c32check.c32addressDecode)(c32AddressString);
  return {
    type: _constants.StacksMessageType.Address,
    version: addressData[0],
    hash160: addressData[1]
  };
}

function parsePrincipalString(principalString) {
  if (principalString.includes('.')) {
    const [address, contractName] = principalString.split('.');
    return createContractPrincipal(address, contractName);
  } else {
    return createStandardPrincipal(principalString);
  }
}

function createContractPrincipal(addressString, contractName) {
  const addr = createAddress(addressString);
  const name = createLPString(contractName);
  return {
    type: _constants.StacksMessageType.Principal,
    prefix: _constants.PostConditionPrincipalID.Contract,
    address: addr,
    contractName: name
  };
}

function createStandardPrincipal(addressString) {
  const addr = createAddress(addressString);
  return {
    type: _constants.StacksMessageType.Principal,
    prefix: _constants.PostConditionPrincipalID.Standard,
    address: addr
  };
}

},{"./constants":43,"./utils":57,"c32check":63}],51:[function(require,module,exports){
"use strict";

Object.defineProperty(exports, "__esModule", {
  value: true
});
exports.createFungiblePostCondition = createFungiblePostCondition;
exports.createNonFungiblePostCondition = createNonFungiblePostCondition;
exports.createSTXPostCondition = createSTXPostCondition;

var _common = require("@stacks/common");

var _constants = require("./constants");

var _postconditionTypes = require("./postcondition-types");

function createSTXPostCondition(principal, conditionCode, amount) {
  if (typeof principal === 'string') {
    principal = (0, _postconditionTypes.parsePrincipalString)(principal);
  }

  return {
    type: _constants.StacksMessageType.PostCondition,
    conditionType: _constants.PostConditionType.STX,
    principal,
    conditionCode,
    amount: (0, _common.intToBigInt)(amount, false)
  };
}

function createFungiblePostCondition(principal, conditionCode, amount, assetInfo) {
  if (typeof principal === 'string') {
    principal = (0, _postconditionTypes.parsePrincipalString)(principal);
  }

  if (typeof assetInfo === 'string') {
    assetInfo = (0, _postconditionTypes.parseAssetInfoString)(assetInfo);
  }

  return {
    type: _constants.StacksMessageType.PostCondition,
    conditionType: _constants.PostConditionType.Fungible,
    principal,
    conditionCode,
    amount: (0, _common.intToBigInt)(amount, false),
    assetInfo
  };
}

function createNonFungiblePostCondition(principal, conditionCode, assetInfo, assetName) {
  if (typeof principal === 'string') {
    principal = (0, _postconditionTypes.parsePrincipalString)(principal);
  }

  if (typeof assetInfo === 'string') {
    assetInfo = (0, _postconditionTypes.parseAssetInfoString)(assetInfo);
  }

  return {
    type: _constants.StacksMessageType.PostCondition,
    conditionType: _constants.PostConditionType.NonFungible,
    principal,
    conditionCode,
    assetInfo,
    assetName
  };
}

},{"./constants":43,"./postcondition-types":50,"@stacks/common":15}],52:[function(require,module,exports){
"use strict";

Object.defineProperty(exports, "__esModule", {
  value: true
});
exports.AuthFieldType = void 0;
exports.createTransactionAuthField = createTransactionAuthField;
exports.deserializeMessageSignature = deserializeMessageSignature;
exports.deserializeTransactionAuthField = deserializeTransactionAuthField;
exports.serializeMessageSignature = serializeMessageSignature;
exports.serializeTransactionAuthField = serializeTransactionAuthField;

var _errors = require("./errors");

var _constants = require("./constants");

var _keys = require("./keys");

var _common = require("./common");

var _common2 = require("@stacks/common");

var AuthFieldType;
exports.AuthFieldType = AuthFieldType;

(function (AuthFieldType) {
  AuthFieldType[AuthFieldType["PublicKeyCompressed"] = 0] = "PublicKeyCompressed";
  AuthFieldType[AuthFieldType["PublicKeyUncompressed"] = 1] = "PublicKeyUncompressed";
  AuthFieldType[AuthFieldType["SignatureCompressed"] = 2] = "SignatureCompressed";
  AuthFieldType[AuthFieldType["SignatureUncompressed"] = 3] = "SignatureUncompressed";
})(AuthFieldType || (exports.AuthFieldType = AuthFieldType = {}));

function deserializeMessageSignature(bytesReader) {
  return (0, _common.createMessageSignature)((0, _common2.bytesToHex)(bytesReader.readBytes(_constants.RECOVERABLE_ECDSA_SIG_LENGTH_BYTES)));
}

function createTransactionAuthField(pubKeyEncoding, contents) {
  return {
    pubKeyEncoding,
    type: _constants.StacksMessageType.TransactionAuthField,
    contents
  };
}

function deserializeTransactionAuthField(bytesReader) {
  const authFieldType = bytesReader.readUInt8Enum(AuthFieldType, n => {
    throw new _errors.DeserializationError(`Could not read ${n} as AuthFieldType`);
  });

  switch (authFieldType) {
    case AuthFieldType.PublicKeyCompressed:
      return createTransactionAuthField(_constants.PubKeyEncoding.Compressed, (0, _keys.deserializePublicKey)(bytesReader));

    case AuthFieldType.PublicKeyUncompressed:
      return createTransactionAuthField(_constants.PubKeyEncoding.Uncompressed, (0, _keys.deserializePublicKey)(bytesReader));

    case AuthFieldType.SignatureCompressed:
      return createTransactionAuthField(_constants.PubKeyEncoding.Compressed, deserializeMessageSignature(bytesReader));

    case AuthFieldType.SignatureUncompressed:
      return createTransactionAuthField(_constants.PubKeyEncoding.Uncompressed, deserializeMessageSignature(bytesReader));

    default:
      throw new Error(`Unknown auth field type: ${JSON.stringify(authFieldType)}`);
  }
}

function serializeMessageSignature(messageSignature) {
  return (0, _common2.hexToBytes)(messageSignature.data);
}

function serializeTransactionAuthField(field) {
  const bytesArray = [];

  switch (field.contents.type) {
    case _constants.StacksMessageType.PublicKey:
      if (field.pubKeyEncoding == _constants.PubKeyEncoding.Compressed) {
        bytesArray.push(AuthFieldType.PublicKeyCompressed);
        bytesArray.push((0, _keys.serializePublicKey)(field.contents));
      } else {
        bytesArray.push(AuthFieldType.PublicKeyUncompressed);
        bytesArray.push((0, _keys.serializePublicKey)((0, _keys.compressPublicKey)(field.contents.data)));
      }

      break;

    case _constants.StacksMessageType.MessageSignature:
      if (field.pubKeyEncoding == _constants.PubKeyEncoding.Compressed) {
        bytesArray.push(AuthFieldType.SignatureCompressed);
      } else {
        bytesArray.push(AuthFieldType.SignatureUncompressed);
      }

      bytesArray.push(serializeMessageSignature(field.contents));
      break;
  }

  return (0, _common2.concatArray)(bytesArray);
}

},{"./common":42,"./constants":43,"./errors":45,"./keys":47,"@stacks/common":15}],53:[function(require,module,exports){
"use strict";

Object.defineProperty(exports, "__esModule", {
  value: true
});
exports.TransactionSigner = void 0;

var _authorization = require("./authorization");

var _utils = require("./utils");

var _constants = require("./constants");

var _errors = require("./errors");

class TransactionSigner {
  constructor(transaction) {
    this.transaction = transaction;
    this.sigHash = transaction.signBegin();
    this.originDone = false;
    this.checkOversign = true;
    this.checkOverlap = true;
    const spendingCondition = transaction.auth.spendingCondition;

    if (spendingCondition && !(0, _authorization.isSingleSig)(spendingCondition)) {
      if (spendingCondition.fields.filter(field => field.contents.type === _constants.StacksMessageType.MessageSignature).length >= spendingCondition.signaturesRequired) {
        throw new Error('SpendingCondition has more signatures than are expected');
      }

      spendingCondition.fields.forEach(field => {
        if (field.contents.type === _constants.StacksMessageType.MessageSignature) {
          const signature = field.contents;
          const nextVerify = (0, _authorization.nextVerification)(this.sigHash, transaction.auth.authType, spendingCondition.fee, spendingCondition.nonce, _constants.PubKeyEncoding.Compressed, signature);
          this.sigHash = nextVerify.nextSigHash;
        }
      });
    }
  }

  static createSponsorSigner(transaction, spendingCondition) {
    if (transaction.auth.authType != _constants.AuthType.Sponsored) {
      throw new _errors.SigningError('Cannot add sponsor to non-sponsored transaction');
    }

    const tx = (0, _utils.cloneDeep)(transaction);
    tx.setSponsor(spendingCondition);
    const originSigHash = tx.verifyOrigin();
    const signer = new this(tx);
    signer.originDone = true;
    signer.sigHash = originSigHash;
    signer.checkOversign = true;
    signer.checkOverlap = true;
    return signer;
  }

  signOrigin(privateKey) {
    if (this.checkOverlap && this.originDone) {
      throw new _errors.SigningError('Cannot sign origin after sponsor key');
    }

    if (this.transaction.auth === undefined) {
      throw new _errors.SigningError('"transaction.auth" is undefined');
    }

    if (this.transaction.auth.spendingCondition === undefined) {
      throw new _errors.SigningError('"transaction.auth.spendingCondition" is undefined');
    }

    if (!(0, _authorization.isSingleSig)(this.transaction.auth.spendingCondition)) {
      const spendingCondition = this.transaction.auth.spendingCondition;

      if (this.checkOversign && spendingCondition.fields.filter(field => field.contents.type === _constants.StacksMessageType.MessageSignature).length >= spendingCondition.signaturesRequired) {
        throw new Error('Origin would have too many signatures');
      }
    }

    const nextSighash = this.transaction.signNextOrigin(this.sigHash, privateKey);
    this.sigHash = nextSighash;
  }

  appendOrigin(publicKey) {
    if (this.checkOverlap && this.originDone) {
      throw Error('Cannot append public key to origin after sponsor key');
    }

    if (this.transaction.auth === undefined) {
      throw new Error('"transaction.auth" is undefined');
    }

    if (this.transaction.auth.spendingCondition === undefined) {
      throw new Error('"transaction.auth.spendingCondition" is undefined');
    }

    this.transaction.appendPubkey(publicKey);
  }

  signSponsor(privateKey) {
    if (this.transaction.auth === undefined) {
      throw new _errors.SigningError('"transaction.auth" is undefined');
    }

    if (this.transaction.auth.authType !== _constants.AuthType.Sponsored) {
      throw new _errors.SigningError('"transaction.auth.authType" is not AuthType.Sponsored');
    }

    const nextSighash = this.transaction.signNextSponsor(this.sigHash, privateKey);
    this.sigHash = nextSighash;
    this.originDone = true;
  }

  getTxInComplete() {
    return (0, _utils.cloneDeep)(this.transaction);
  }

  resume(transaction) {
    this.transaction = (0, _utils.cloneDeep)(transaction);
    this.sigHash = transaction.signBegin();
  }

}

exports.TransactionSigner = TransactionSigner;

},{"./authorization":23,"./constants":43,"./errors":45,"./utils":57}],54:[function(require,module,exports){
"use strict";

Object.defineProperty(exports, "__esModule", {
  value: true
});
exports.STRUCTURED_DATA_PREFIX = void 0;
exports.decodeStructuredDataSignature = decodeStructuredDataSignature;
exports.encodeStructuredData = encodeStructuredData;
exports.hashStructuredData = hashStructuredData;
exports.signStructuredData = signStructuredData;

var _sha = require("@noble/hashes/sha256");

var _common = require("@stacks/common");

var _clarity = require("./clarity");

var _constants = require("./constants");

var _keys = require("./keys");

const STRUCTURED_DATA_PREFIX = new Uint8Array([0x53, 0x49, 0x50, 0x30, 0x31, 0x38]);
exports.STRUCTURED_DATA_PREFIX = STRUCTURED_DATA_PREFIX;

function hashStructuredData(structuredData) {
  return (0, _sha.sha256)((0, _clarity.serializeCV)(structuredData));
}

const hash256BytesLength = 32;

function isDomain(value) {
  if (value.type !== _clarity.ClarityType.Tuple) return false;
  if (!['name', 'version', 'chain-id'].every(key => key in value.data)) return false;
  if (!['name', 'version'].every(key => value.data[key].type === _clarity.ClarityType.StringASCII)) return false;
  if (value.data['chain-id'].type !== _clarity.ClarityType.UInt) return false;
  return true;
}

function encodeStructuredData({
  message,
  domain
}) {
  const structuredDataHash = hashStructuredData(message);

  if (!isDomain(domain)) {
    throw new Error("domain parameter must be a valid domain of type TupleCV with keys 'name', 'version', 'chain-id' with respective types StringASCII, StringASCII, UInt");
  }

  const domainHash = hashStructuredData(domain);
  return (0, _common.concatBytes)(STRUCTURED_DATA_PREFIX, domainHash, structuredDataHash);
}

function decodeStructuredDataSignature(signature) {
  const encodedMessageBytes = typeof signature === 'string' ? (0, _common.utf8ToBytes)(signature) : signature;
  const domainHash = encodedMessageBytes.slice(STRUCTURED_DATA_PREFIX.length, STRUCTURED_DATA_PREFIX.length + hash256BytesLength);
  const messageHash = encodedMessageBytes.slice(STRUCTURED_DATA_PREFIX.length + hash256BytesLength);
  return {
    domainHash,
    messageHash
  };
}

function signStructuredData({
  message,
  domain,
  privateKey
}) {
  const structuredDataHash = (0, _common.bytesToHex)((0, _sha.sha256)(encodeStructuredData({
    message,
    domain
  })));
  const {
    data
  } = (0, _keys.signMessageHashRsv)({
    messageHash: structuredDataHash,
    privateKey
  });
  return {
    data,
    type: _constants.StacksMessageType.StructuredDataSignature
  };
}

},{"./clarity":30,"./constants":43,"./keys":47,"@noble/hashes/sha256":7,"@stacks/common":15}],55:[function(require,module,exports){
"use strict";

Object.defineProperty(exports, "__esModule", {
  value: true
});
exports.StacksTransaction = void 0;
exports.deserializeTransaction = deserializeTransaction;

var _common = require("@stacks/common");

var _constants = require("./constants");

var _authorization = require("./authorization");

var _signature = require("./signature");

var _utils = require("./utils");

var _payload = require("./payload");

var _types = require("./types");

var _keys = require("./keys");

var _bytesReader = require("./bytesReader");

var _errors = require("./errors");

class StacksTransaction {
  constructor(version, auth, payload, postConditions, postConditionMode, anchorMode, chainId) {
    this.version = version;
    this.auth = auth;

    if ('amount' in payload) {
      this.payload = { ...payload,
        amount: (0, _common.intToBigInt)(payload.amount, false)
      };
    } else {
      this.payload = payload;
    }

    this.chainId = chainId ?? _constants.DEFAULT_CHAIN_ID;
    this.postConditionMode = postConditionMode ?? _constants.PostConditionMode.Deny;
    this.postConditions = postConditions ?? (0, _types.createLPList)([]);

    if (anchorMode) {
      this.anchorMode = (0, _constants.anchorModeFromNameOrValue)(anchorMode);
    } else {
      switch (payload.payloadType) {
        case _constants.PayloadType.Coinbase:
        case _constants.PayloadType.CoinbaseToAltRecipient:
        case _constants.PayloadType.PoisonMicroblock:
          {
            this.anchorMode = _constants.AnchorMode.OnChainOnly;
            break;
          }

        case _constants.PayloadType.ContractCall:
        case _constants.PayloadType.SmartContract:
        case _constants.PayloadType.VersionedSmartContract:
        case _constants.PayloadType.TokenTransfer:
          {
            this.anchorMode = _constants.AnchorMode.Any;
            break;
          }
      }
    }
  }

  signBegin() {
    const tx = (0, _utils.cloneDeep)(this);
    tx.auth = (0, _authorization.intoInitialSighashAuth)(tx.auth);
    return tx.txid();
  }

  verifyBegin() {
    const tx = (0, _utils.cloneDeep)(this);
    tx.auth = (0, _authorization.intoInitialSighashAuth)(tx.auth);
    return tx.txid();
  }

  verifyOrigin() {
    return (0, _authorization.verifyOrigin)(this.auth, this.verifyBegin());
  }

  signNextOrigin(sigHash, privateKey) {
    if (this.auth.spendingCondition === undefined) {
      throw new Error('"auth.spendingCondition" is undefined');
    }

    if (this.auth.authType === undefined) {
      throw new Error('"auth.authType" is undefined');
    }

    return this.signAndAppend(this.auth.spendingCondition, sigHash, _constants.AuthType.Standard, privateKey);
  }

  signNextSponsor(sigHash, privateKey) {
    if (this.auth.authType === _constants.AuthType.Sponsored) {
      return this.signAndAppend(this.auth.sponsorSpendingCondition, sigHash, _constants.AuthType.Sponsored, privateKey);
    } else {
      throw new Error('"auth.sponsorSpendingCondition" is undefined');
    }
  }

  appendPubkey(publicKey) {
    const cond = this.auth.spendingCondition;

    if (cond && !(0, _authorization.isSingleSig)(cond)) {
      const compressed = (0, _keys.isCompressed)(publicKey);
      cond.fields.push((0, _signature.createTransactionAuthField)(compressed ? _constants.PubKeyEncoding.Compressed : _constants.PubKeyEncoding.Uncompressed, publicKey));
    } else {
      throw new Error(`Can't append public key to a singlesig condition`);
    }
  }

  signAndAppend(condition, curSigHash, authType, privateKey) {
    const {
      nextSig,
      nextSigHash
    } = (0, _authorization.nextSignature)(curSigHash, authType, condition.fee, condition.nonce, privateKey);

    if ((0, _authorization.isSingleSig)(condition)) {
      condition.signature = nextSig;
    } else {
      const compressed = (0, _common.bytesToHex)(privateKey.data).endsWith('01');
      condition.fields.push((0, _signature.createTransactionAuthField)(compressed ? _constants.PubKeyEncoding.Compressed : _constants.PubKeyEncoding.Uncompressed, nextSig));
    }

    return nextSigHash;
  }

  txid() {
    const serialized = this.serialize();
    return (0, _utils.txidFromData)(serialized);
  }

  setSponsor(sponsorSpendingCondition) {
    if (this.auth.authType != _constants.AuthType.Sponsored) {
      throw new _errors.SigningError('Cannot sponsor sign a non-sponsored transaction');
    }

    this.auth = (0, _authorization.setSponsor)(this.auth, sponsorSpendingCondition);
  }

  setFee(amount) {
    this.auth = (0, _authorization.setFee)(this.auth, amount);
  }

  setNonce(nonce) {
    this.auth = (0, _authorization.setNonce)(this.auth, nonce);
  }

  setSponsorNonce(nonce) {
    if (this.auth.authType != _constants.AuthType.Sponsored) {
      throw new _errors.SigningError('Cannot sponsor sign a non-sponsored transaction');
    }

    this.auth = (0, _authorization.setSponsorNonce)(this.auth, nonce);
  }

  serialize() {
    if (this.version === undefined) {
      throw new _errors.SerializationError('"version" is undefined');
    }

    if (this.chainId === undefined) {
      throw new _errors.SerializationError('"chainId" is undefined');
    }

    if (this.auth === undefined) {
      throw new _errors.SerializationError('"auth" is undefined');
    }

    if (this.anchorMode === undefined) {
      throw new _errors.SerializationError('"anchorMode" is undefined');
    }

    if (this.payload === undefined) {
      throw new _errors.SerializationError('"payload" is undefined');
    }

    const bytesArray = [];
    bytesArray.push(this.version);
    const chainIdBytes = new Uint8Array(4);
    (0, _common.writeUInt32BE)(chainIdBytes, this.chainId, 0);
    bytesArray.push(chainIdBytes);
    bytesArray.push((0, _authorization.serializeAuthorization)(this.auth));
    bytesArray.push(this.anchorMode);
    bytesArray.push(this.postConditionMode);
    bytesArray.push((0, _types.serializeLPList)(this.postConditions));
    bytesArray.push((0, _payload.serializePayload)(this.payload));
    return (0, _common.concatArray)(bytesArray);
  }

}

exports.StacksTransaction = StacksTransaction;

function deserializeTransaction(tx) {
  let bytesReader;

  if (typeof tx === 'string') {
    if (tx.slice(0, 2).toLowerCase() === '0x') {
      bytesReader = new _bytesReader.BytesReader((0, _common.hexToBytes)(tx.slice(2)));
    } else {
      bytesReader = new _bytesReader.BytesReader((0, _common.hexToBytes)(tx));
    }
  } else if (tx instanceof Uint8Array) {
    bytesReader = new _bytesReader.BytesReader(tx);
  } else {
    bytesReader = tx;
  }

  const version = bytesReader.readUInt8Enum(_constants.TransactionVersion, n => {
    throw new Error(`Could not parse ${n} as TransactionVersion`);
  });
  const chainId = bytesReader.readUInt32BE();
  const auth = (0, _authorization.deserializeAuthorization)(bytesReader);
  const anchorMode = bytesReader.readUInt8Enum(_constants.AnchorMode, n => {
    throw new Error(`Could not parse ${n} as AnchorMode`);
  });
  const postConditionMode = bytesReader.readUInt8Enum(_constants.PostConditionMode, n => {
    throw new Error(`Could not parse ${n} as PostConditionMode`);
  });
  const postConditions = (0, _types.deserializeLPList)(bytesReader, _constants.StacksMessageType.PostCondition);
  const payload = (0, _payload.deserializePayload)(bytesReader);
  return new StacksTransaction(version, auth, payload, postConditions, postConditionMode, anchorMode, chainId);
}

},{"./authorization":23,"./bytesReader":25,"./constants":43,"./errors":45,"./keys":47,"./payload":48,"./signature":52,"./types":56,"./utils":57,"@stacks/common":15}],56:[function(require,module,exports){
"use strict";

Object.defineProperty(exports, "__esModule", {
  value: true
});
exports.addressFromHashMode = addressFromHashMode;
exports.addressFromPublicKeys = addressFromPublicKeys;
exports.codeBodyString = codeBodyString;
exports.createEmptyAddress = createEmptyAddress;
exports.createLPList = createLPList;
exports.createMemoString = createMemoString;
exports.deserializeAddress = deserializeAddress;
exports.deserializeAssetInfo = deserializeAssetInfo;
exports.deserializeLPList = deserializeLPList;
exports.deserializeLPString = deserializeLPString;
exports.deserializeMemoString = deserializeMemoString;
exports.deserializePostCondition = deserializePostCondition;
exports.deserializePrincipal = deserializePrincipal;
exports.deserializeStacksMessage = deserializeStacksMessage;
exports.serializeAddress = serializeAddress;
exports.serializeAssetInfo = serializeAssetInfo;
exports.serializeLPList = serializeLPList;
exports.serializeLPString = serializeLPString;
exports.serializeMemoString = serializeMemoString;
exports.serializePostCondition = serializePostCondition;
exports.serializePrincipal = serializePrincipal;
exports.serializeStacksMessage = serializeStacksMessage;

var _common = require("@stacks/common");

var _constants = require("./constants");

var _keys = require("./keys");

var _utils = require("./utils");

var _postconditionTypes = require("./postcondition-types");

var _payload = require("./payload");

var _errors = require("./errors");

var _signature = require("./signature");

var _common2 = require("./common");

var _clarity = require("./clarity");

function serializeStacksMessage(message) {
  switch (message.type) {
    case _constants.StacksMessageType.Address:
      return serializeAddress(message);

    case _constants.StacksMessageType.Principal:
      return serializePrincipal(message);

    case _constants.StacksMessageType.LengthPrefixedString:
      return serializeLPString(message);

    case _constants.StacksMessageType.MemoString:
      return serializeMemoString(message);

    case _constants.StacksMessageType.AssetInfo:
      return serializeAssetInfo(message);

    case _constants.StacksMessageType.PostCondition:
      return serializePostCondition(message);

    case _constants.StacksMessageType.PublicKey:
      return (0, _keys.serializePublicKey)(message);

    case _constants.StacksMessageType.LengthPrefixedList:
      return serializeLPList(message);

    case _constants.StacksMessageType.Payload:
      return (0, _payload.serializePayload)(message);

    case _constants.StacksMessageType.TransactionAuthField:
      return (0, _signature.serializeTransactionAuthField)(message);

    case _constants.StacksMessageType.MessageSignature:
      return (0, _signature.serializeMessageSignature)(message);
  }
}

function deserializeStacksMessage(bytesReader, type, listType) {
  switch (type) {
    case _constants.StacksMessageType.Address:
      return deserializeAddress(bytesReader);

    case _constants.StacksMessageType.Principal:
      return deserializePrincipal(bytesReader);

    case _constants.StacksMessageType.LengthPrefixedString:
      return deserializeLPString(bytesReader);

    case _constants.StacksMessageType.MemoString:
      return deserializeMemoString(bytesReader);

    case _constants.StacksMessageType.AssetInfo:
      return deserializeAssetInfo(bytesReader);

    case _constants.StacksMessageType.PostCondition:
      return deserializePostCondition(bytesReader);

    case _constants.StacksMessageType.PublicKey:
      return (0, _keys.deserializePublicKey)(bytesReader);

    case _constants.StacksMessageType.Payload:
      return (0, _payload.deserializePayload)(bytesReader);

    case _constants.StacksMessageType.LengthPrefixedList:
      if (!listType) {
        throw new _errors.DeserializationError('No List Type specified');
      }

      return deserializeLPList(bytesReader, listType);

    case _constants.StacksMessageType.MessageSignature:
      return (0, _signature.deserializeMessageSignature)(bytesReader);

    default:
      throw new Error('Could not recognize StacksMessageType');
  }
}

function createEmptyAddress() {
  return {
    type: _constants.StacksMessageType.Address,
    version: _constants.AddressVersion.MainnetSingleSig,
    hash160: '0'.repeat(40)
  };
}

function addressFromHashMode(hashMode, txVersion, data) {
  const version = (0, _common2.addressHashModeToVersion)(hashMode, txVersion);
  return (0, _common2.addressFromVersionHash)(version, data);
}

function addressFromPublicKeys(version, hashMode, numSigs, publicKeys) {
  if (publicKeys.length === 0) {
    throw Error('Invalid number of public keys');
  }

  if (hashMode === _constants.AddressHashMode.SerializeP2PKH || hashMode === _constants.AddressHashMode.SerializeP2WPKH) {
    if (publicKeys.length !== 1 || numSigs !== 1) {
      throw Error('Invalid number of public keys or signatures');
    }
  }

  if (hashMode === _constants.AddressHashMode.SerializeP2WPKH || hashMode === _constants.AddressHashMode.SerializeP2WSH) {
    for (let i = 0; i < publicKeys.length; i++) {
      if (!(0, _keys.isCompressed)(publicKeys[i])) {
        throw Error('Public keys must be compressed for segwit');
      }
    }
  }

  switch (hashMode) {
    case _constants.AddressHashMode.SerializeP2PKH:
      return (0, _common2.addressFromVersionHash)(version, (0, _utils.hashP2PKH)(publicKeys[0].data));

    case _constants.AddressHashMode.SerializeP2WPKH:
      return (0, _common2.addressFromVersionHash)(version, (0, _utils.hashP2WPKH)(publicKeys[0].data));

    case _constants.AddressHashMode.SerializeP2SH:
      return (0, _common2.addressFromVersionHash)(version, (0, _utils.hashP2SH)(numSigs, publicKeys.map(_keys.serializePublicKey)));

    case _constants.AddressHashMode.SerializeP2WSH:
      return (0, _common2.addressFromVersionHash)(version, (0, _utils.hashP2WSH)(numSigs, publicKeys.map(_keys.serializePublicKey)));
  }
}

function serializeAddress(address) {
  const bytesArray = [];
  bytesArray.push((0, _common.hexToBytes)((0, _common.intToHex)(address.version, 1)));
  bytesArray.push((0, _common.hexToBytes)(address.hash160));
  return (0, _common.concatArray)(bytesArray);
}

function deserializeAddress(bytesReader) {
  const version = (0, _common.hexToInt)((0, _common.bytesToHex)(bytesReader.readBytes(1)));
  const data = (0, _common.bytesToHex)(bytesReader.readBytes(20));
  return {
    type: _constants.StacksMessageType.Address,
    version,
    hash160: data
  };
}

function serializePrincipal(principal) {
  const bytesArray = [];
  bytesArray.push(principal.prefix);
  bytesArray.push(serializeAddress(principal.address));

  if (principal.prefix === _constants.PostConditionPrincipalID.Contract) {
    bytesArray.push(serializeLPString(principal.contractName));
  }

  return (0, _common.concatArray)(bytesArray);
}

function deserializePrincipal(bytesReader) {
  const prefix = bytesReader.readUInt8Enum(_constants.PostConditionPrincipalID, n => {
    throw new _errors.DeserializationError(`Unexpected Principal payload type: ${n}`);
  });
  const address = deserializeAddress(bytesReader);

  if (prefix === _constants.PostConditionPrincipalID.Standard) {
    return {
      type: _constants.StacksMessageType.Principal,
      prefix,
      address
    };
  }

  const contractName = deserializeLPString(bytesReader);
  return {
    type: _constants.StacksMessageType.Principal,
    prefix,
    address,
    contractName
  };
}

function serializeLPString(lps) {
  const bytesArray = [];
  const contentBytes = (0, _common.utf8ToBytes)(lps.content);
  const length = contentBytes.byteLength;
  bytesArray.push((0, _common.hexToBytes)((0, _common.intToHex)(length, lps.lengthPrefixBytes)));
  bytesArray.push(contentBytes);
  return (0, _common.concatArray)(bytesArray);
}

function deserializeLPString(bytesReader, prefixBytes, maxLength) {
  prefixBytes = prefixBytes ? prefixBytes : 1;
  const length = (0, _common.hexToInt)((0, _common.bytesToHex)(bytesReader.readBytes(prefixBytes)));
  const content = (0, _common.bytesToUtf8)(bytesReader.readBytes(length));
  return (0, _postconditionTypes.createLPString)(content, prefixBytes, maxLength ?? 128);
}

function codeBodyString(content) {
  return (0, _postconditionTypes.createLPString)(content, 4, 100000);
}

function createMemoString(content) {
  if (content && (0, _utils.exceedsMaxLengthBytes)(content, _constants.MEMO_MAX_LENGTH_BYTES)) {
    throw new Error(`Memo exceeds maximum length of ${_constants.MEMO_MAX_LENGTH_BYTES} bytes`);
  }

  return {
    type: _constants.StacksMessageType.MemoString,
    content
  };
}

function serializeMemoString(memoString) {
  const bytesArray = [];
  const contentBytes = (0, _common.utf8ToBytes)(memoString.content);
  const paddedContent = (0, _utils.rightPadHexToLength)((0, _common.bytesToHex)(contentBytes), _constants.MEMO_MAX_LENGTH_BYTES * 2);
  bytesArray.push((0, _common.hexToBytes)(paddedContent));
  return (0, _common.concatArray)(bytesArray);
}

function deserializeMemoString(bytesReader) {
  const content = (0, _common.bytesToUtf8)(bytesReader.readBytes(_constants.MEMO_MAX_LENGTH_BYTES));
  return {
    type: _constants.StacksMessageType.MemoString,
    content
  };
}

function serializeAssetInfo(info) {
  const bytesArray = [];
  bytesArray.push(serializeAddress(info.address));
  bytesArray.push(serializeLPString(info.contractName));
  bytesArray.push(serializeLPString(info.assetName));
  return (0, _common.concatArray)(bytesArray);
}

function deserializeAssetInfo(bytesReader) {
  return {
    type: _constants.StacksMessageType.AssetInfo,
    address: deserializeAddress(bytesReader),
    contractName: deserializeLPString(bytesReader),
    assetName: deserializeLPString(bytesReader)
  };
}

function createLPList(values, lengthPrefixBytes) {
  return {
    type: _constants.StacksMessageType.LengthPrefixedList,
    lengthPrefixBytes: lengthPrefixBytes || 4,
    values
  };
}

function serializeLPList(lpList) {
  const list = lpList.values;
  const bytesArray = [];
  bytesArray.push((0, _common.hexToBytes)((0, _common.intToHex)(list.length, lpList.lengthPrefixBytes)));

  for (const l of list) {
    bytesArray.push(serializeStacksMessage(l));
  }

  return (0, _common.concatArray)(bytesArray);
}

function deserializeLPList(bytesReader, type, lengthPrefixBytes) {
  const length = (0, _common.hexToInt)((0, _common.bytesToHex)(bytesReader.readBytes(lengthPrefixBytes || 4)));
  const l = [];

  for (let index = 0; index < length; index++) {
    switch (type) {
      case _constants.StacksMessageType.Address:
        l.push(deserializeAddress(bytesReader));
        break;

      case _constants.StacksMessageType.LengthPrefixedString:
        l.push(deserializeLPString(bytesReader));
        break;

      case _constants.StacksMessageType.MemoString:
        l.push(deserializeMemoString(bytesReader));
        break;

      case _constants.StacksMessageType.AssetInfo:
        l.push(deserializeAssetInfo(bytesReader));
        break;

      case _constants.StacksMessageType.PostCondition:
        l.push(deserializePostCondition(bytesReader));
        break;

      case _constants.StacksMessageType.PublicKey:
        l.push((0, _keys.deserializePublicKey)(bytesReader));
        break;

      case _constants.StacksMessageType.TransactionAuthField:
        l.push((0, _signature.deserializeTransactionAuthField)(bytesReader));
        break;
    }
  }

  return createLPList(l, lengthPrefixBytes);
}

function serializePostCondition(postCondition) {
  const bytesArray = [];
  bytesArray.push(postCondition.conditionType);
  bytesArray.push(serializePrincipal(postCondition.principal));

  if (postCondition.conditionType === _constants.PostConditionType.Fungible || postCondition.conditionType === _constants.PostConditionType.NonFungible) {
    bytesArray.push(serializeAssetInfo(postCondition.assetInfo));
  }

  if (postCondition.conditionType === _constants.PostConditionType.NonFungible) {
    bytesArray.push((0, _clarity.serializeCV)(postCondition.assetName));
  }

  bytesArray.push(postCondition.conditionCode);

  if (postCondition.conditionType === _constants.PostConditionType.STX || postCondition.conditionType === _constants.PostConditionType.Fungible) {
    if (postCondition.amount > BigInt('0xffffffffffffffff')) throw new _errors.SerializationError('The post-condition amount may not be larger than 8 bytes');
    bytesArray.push((0, _common.intToBytes)(postCondition.amount, false, 8));
  }

  return (0, _common.concatArray)(bytesArray);
}

function deserializePostCondition(bytesReader) {
  const postConditionType = bytesReader.readUInt8Enum(_constants.PostConditionType, n => {
    throw new _errors.DeserializationError(`Could not read ${n} as PostConditionType`);
  });
  const principal = deserializePrincipal(bytesReader);
  let conditionCode;
  let assetInfo;
  let amount;

  switch (postConditionType) {
    case _constants.PostConditionType.STX:
      conditionCode = bytesReader.readUInt8Enum(_constants.FungibleConditionCode, n => {
        throw new _errors.DeserializationError(`Could not read ${n} as FungibleConditionCode`);
      });
      amount = BigInt(`0x${(0, _common.bytesToHex)(bytesReader.readBytes(8))}`);
      return {
        type: _constants.StacksMessageType.PostCondition,
        conditionType: _constants.PostConditionType.STX,
        principal,
        conditionCode,
        amount
      };

    case _constants.PostConditionType.Fungible:
      assetInfo = deserializeAssetInfo(bytesReader);
      conditionCode = bytesReader.readUInt8Enum(_constants.FungibleConditionCode, n => {
        throw new _errors.DeserializationError(`Could not read ${n} as FungibleConditionCode`);
      });
      amount = BigInt(`0x${(0, _common.bytesToHex)(bytesReader.readBytes(8))}`);
      return {
        type: _constants.StacksMessageType.PostCondition,
        conditionType: _constants.PostConditionType.Fungible,
        principal,
        conditionCode,
        amount,
        assetInfo
      };

    case _constants.PostConditionType.NonFungible:
      assetInfo = deserializeAssetInfo(bytesReader);
      const assetName = (0, _clarity.deserializeCV)(bytesReader);
      conditionCode = bytesReader.readUInt8Enum(_constants.NonFungibleConditionCode, n => {
        throw new _errors.DeserializationError(`Could not read ${n} as FungibleConditionCode`);
      });
      return {
        type: _constants.StacksMessageType.PostCondition,
        conditionType: _constants.PostConditionType.NonFungible,
        principal,
        conditionCode,
        assetInfo,
        assetName
      };
  }
}

},{"./clarity":30,"./common":42,"./constants":43,"./errors":45,"./keys":47,"./payload":48,"./postcondition-types":50,"./signature":52,"./utils":57,"@stacks/common":15}],57:[function(require,module,exports){
"use strict";

Object.defineProperty(exports, "__esModule", {
  value: true
});
exports.cloneDeep = cloneDeep;
exports.cvToHex = cvToHex;
exports.hashP2WSH = exports.hashP2WPKH = exports.hashP2SH = exports.hashP2PKH = exports.hash160 = exports.exceedsMaxLengthBytes = void 0;
exports.hexToCV = hexToCV;
exports.isClarityName = isClarityName;
exports.leftPadHexToLength = exports.leftPadHex = void 0;
exports.omit = omit;
exports.validateTxId = exports.validateStacksAddress = exports.txidFromData = exports.txidFromBytes = exports.rightPadHexToLength = exports.randomBytes = exports.parseReadOnlyResponse = void 0;
Object.defineProperty(exports, "verifySignature", {
  enumerable: true,
  get: function () {
    return _secp256k.verify;
  }
});

var _ripemd = require("@noble/hashes/ripemd160");

var _sha = require("@noble/hashes/sha256");

var _sha2 = require("@noble/hashes/sha512");

var _secp256k = require("@noble/secp256k1");

var _common = require("@stacks/common");

var _c32check = require("c32check");

var _lodash = _interopRequireDefault(require("lodash.clonedeep"));

var _clarity = require("./clarity");

function _interopRequireDefault(obj) { return obj && obj.__esModule ? obj : { default: obj }; }

const randomBytes = bytesLength => _secp256k.utils.randomBytes(bytesLength);

exports.randomBytes = randomBytes;

const leftPadHex = hexString => hexString.length % 2 == 0 ? hexString : `0${hexString}`;

exports.leftPadHex = leftPadHex;

const leftPadHexToLength = (hexString, length) => hexString.padStart(length, '0');

exports.leftPadHexToLength = leftPadHexToLength;

const rightPadHexToLength = (hexString, length) => hexString.padEnd(length, '0');

exports.rightPadHexToLength = rightPadHexToLength;

const exceedsMaxLengthBytes = (string, maxLengthBytes) => string ? (0, _common.utf8ToBytes)(string).length > maxLengthBytes : false;

exports.exceedsMaxLengthBytes = exceedsMaxLengthBytes;

function cloneDeep(obj) {
  return (0, _lodash.default)(obj);
}

function omit(obj, prop) {
  const clone = cloneDeep(obj);
  delete clone[prop];
  return clone;
}

const hash160 = input => {
  return (0, _ripemd.ripemd160)((0, _sha.sha256)(input));
};

exports.hash160 = hash160;

const txidFromData = data => {
  return (0, _common.bytesToHex)((0, _sha2.sha512_256)(data));
};

exports.txidFromData = txidFromData;
const txidFromBytes = txidFromData;
exports.txidFromBytes = txidFromBytes;

const hashP2PKH = input => {
  return (0, _common.bytesToHex)(hash160(input));
};

exports.hashP2PKH = hashP2PKH;

const hashP2WPKH = input => {
  const keyHash = hash160(input);
  const redeemScript = (0, _common.concatBytes)(new Uint8Array([0]), new Uint8Array([keyHash.length]), keyHash);
  const redeemScriptHash = hash160(redeemScript);
  return (0, _common.bytesToHex)(redeemScriptHash);
};

exports.hashP2WPKH = hashP2WPKH;

const hashP2SH = (numSigs, pubKeys) => {
  if (numSigs > 15 || pubKeys.length > 15) {
    throw Error('P2SH multisig address can only contain up to 15 public keys');
  }

  const bytesArray = [];
  bytesArray.push(80 + numSigs);
  pubKeys.forEach(pubKey => {
    bytesArray.push(pubKey.length);
    bytesArray.push(pubKey);
  });
  bytesArray.push(80 + pubKeys.length);
  bytesArray.push(174);
  const redeemScript = (0, _common.concatArray)(bytesArray);
  const redeemScriptHash = hash160(redeemScript);
  return (0, _common.bytesToHex)(redeemScriptHash);
};

exports.hashP2SH = hashP2SH;

const hashP2WSH = (numSigs, pubKeys) => {
  if (numSigs > 15 || pubKeys.length > 15) {
    throw Error('P2WSH multisig address can only contain up to 15 public keys');
  }

  const scriptArray = [];
  scriptArray.push(80 + numSigs);
  pubKeys.forEach(pubKey => {
    scriptArray.push(pubKey.length);
    scriptArray.push(pubKey);
  });
  scriptArray.push(80 + pubKeys.length);
  scriptArray.push(174);
  const script = (0, _common.concatArray)(scriptArray);
  const digest = (0, _sha.sha256)(script);
  const bytesArray = [];
  bytesArray.push(0);
  bytesArray.push(digest.length);
  bytesArray.push(digest);
  const redeemScript = (0, _common.concatArray)(bytesArray);
  const redeemScriptHash = hash160(redeemScript);
  return (0, _common.bytesToHex)(redeemScriptHash);
};

exports.hashP2WSH = hashP2WSH;

function isClarityName(name) {
  const regex = /^[a-zA-Z]([a-zA-Z0-9]|[-_!?+<>=/*])*$|^[-+=/*]$|^[<>]=?$/;
  return regex.test(name) && name.length < 128;
}

function cvToHex(cv) {
  const serialized = (0, _clarity.serializeCV)(cv);
  return `0x${(0, _common.bytesToHex)(serialized)}`;
}

function hexToCV(hex) {
  return (0, _clarity.deserializeCV)(hex);
}

const parseReadOnlyResponse = response => {
  if (response.okay) return hexToCV(response.result);
  throw new Error(response.cause);
};

exports.parseReadOnlyResponse = parseReadOnlyResponse;

const validateStacksAddress = stacksAddress => {
  try {
    (0, _c32check.c32addressDecode)(stacksAddress);
    return true;
  } catch (e) {
    return false;
  }
};

exports.validateStacksAddress = validateStacksAddress;

const validateTxId = txid => {
  if (txid === 'success') return true;
  const value = (0, _common.with0x)(txid).toLowerCase();
  if (value.length !== 66) return false;
  return (0, _common.with0x)(BigInt(value).toString(16).padStart(64, '0')) === value;
};

exports.validateTxId = validateTxId;

},{"./clarity":30,"@noble/hashes/ripemd160":6,"@noble/hashes/sha256":7,"@noble/hashes/sha512":8,"@noble/secp256k1":10,"@stacks/common":15,"c32check":63,"lodash.clonedeep":66}],58:[function(require,module,exports){

},{}],59:[function(require,module,exports){
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.c32ToB58 = exports.b58ToC32 = exports.c32addressDecode = exports.c32address = exports.versions = void 0;
const checksum_1 = require("./checksum");
const base58check = require("./base58check");
const utils_1 = require("@noble/hashes/utils");
exports.versions = {
    mainnet: {
        p2pkh: 22,
        p2sh: 20, // 'M'
    },
    testnet: {
        p2pkh: 26,
        p2sh: 21, // 'N'
    },
};
// address conversion : bitcoin to stacks
const ADDR_BITCOIN_TO_STACKS = {};
ADDR_BITCOIN_TO_STACKS[0] = exports.versions.mainnet.p2pkh;
ADDR_BITCOIN_TO_STACKS[5] = exports.versions.mainnet.p2sh;
ADDR_BITCOIN_TO_STACKS[111] = exports.versions.testnet.p2pkh;
ADDR_BITCOIN_TO_STACKS[196] = exports.versions.testnet.p2sh;
// address conversion : stacks to bitcoin
const ADDR_STACKS_TO_BITCOIN = {};
ADDR_STACKS_TO_BITCOIN[exports.versions.mainnet.p2pkh] = 0;
ADDR_STACKS_TO_BITCOIN[exports.versions.mainnet.p2sh] = 5;
ADDR_STACKS_TO_BITCOIN[exports.versions.testnet.p2pkh] = 111;
ADDR_STACKS_TO_BITCOIN[exports.versions.testnet.p2sh] = 196;
/**
 * Make a c32check address with the given version and hash160
 * The only difference between a c32check string and c32 address
 * is that the letter 'S' is pre-pended.
 * @param {number} version - the address version number
 * @param {string} hash160hex - the hash160 to encode (must be a hash160)
 * @returns {string} the address
 */
function c32address(version, hash160hex) {
    if (!hash160hex.match(/^[0-9a-fA-F]{40}$/)) {
        throw new Error('Invalid argument: not a hash160 hex string');
    }
    const c32string = (0, checksum_1.c32checkEncode)(version, hash160hex);
    return `S${c32string}`;
}
exports.c32address = c32address;
/**
 * Decode a c32 address into its version and hash160
 * @param {string} c32addr - the c32check-encoded address
 * @returns {[number, string]} a tuple with the version and hash160
 */
function c32addressDecode(c32addr) {
    if (c32addr.length <= 5) {
        throw new Error('Invalid c32 address: invalid length');
    }
    if (c32addr[0] != 'S') {
        throw new Error('Invalid c32 address: must start with "S"');
    }
    return (0, checksum_1.c32checkDecode)(c32addr.slice(1));
}
exports.c32addressDecode = c32addressDecode;
/*
 * Convert a base58check address to a c32check address.
 * Try to convert the version number if one is not given.
 * @param {string} b58check - the base58check encoded address
 * @param {number} version - the version number, if not inferred from the address
 * @returns {string} the c32 address with the given version number (or the
 *   semantically-equivalent c32 version number, if not given)
 */
function b58ToC32(b58check, version = -1) {
    const addrInfo = base58check.decode(b58check);
    const hash160String = (0, utils_1.bytesToHex)(addrInfo.data);
    const addrVersion = parseInt((0, utils_1.bytesToHex)(addrInfo.prefix), 16);
    let stacksVersion;
    if (version < 0) {
        stacksVersion = addrVersion;
        if (ADDR_BITCOIN_TO_STACKS[addrVersion] !== undefined) {
            stacksVersion = ADDR_BITCOIN_TO_STACKS[addrVersion];
        }
    }
    else {
        stacksVersion = version;
    }
    return c32address(stacksVersion, hash160String);
}
exports.b58ToC32 = b58ToC32;
/*
 * Convert a c32check address to a base58check address.
 * @param {string} c32string - the c32check address
 * @param {number} version - the version number, if not inferred from the address
 * @returns {string} the base58 address with the given version number (or the
 *    semantically-equivalent bitcoin version number, if not given)
 */
function c32ToB58(c32string, version = -1) {
    const addrInfo = c32addressDecode(c32string);
    const stacksVersion = addrInfo[0];
    const hash160String = addrInfo[1];
    let bitcoinVersion;
    if (version < 0) {
        bitcoinVersion = stacksVersion;
        if (ADDR_STACKS_TO_BITCOIN[stacksVersion] !== undefined) {
            bitcoinVersion = ADDR_STACKS_TO_BITCOIN[stacksVersion];
        }
    }
    else {
        bitcoinVersion = version;
    }
    let prefix = bitcoinVersion.toString(16);
    if (prefix.length === 1) {
        prefix = `0${prefix}`;
    }
    return base58check.encode(hash160String, prefix);
}
exports.c32ToB58 = c32ToB58;

},{"./base58check":60,"./checksum":61,"@noble/hashes/utils":9}],60:[function(require,module,exports){
/*
 * From https://github.com/wzbg/base58check
 * @Author: zyc
 * @Date:   2016-09-11 23:36:05
 */
'use strict';
Object.defineProperty(exports, "__esModule", { value: true });
exports.decode = exports.encode = void 0;
const sha256_1 = require("@noble/hashes/sha256");
const utils_1 = require("@noble/hashes/utils");
const basex = require("base-x");
const ALPHABET = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
function encode(data, prefix = '00') {
    const dataBytes = typeof data === 'string' ? (0, utils_1.hexToBytes)(data) : data;
    const prefixBytes = typeof prefix === 'string' ? (0, utils_1.hexToBytes)(prefix) : data;
    if (!(dataBytes instanceof Uint8Array) || !(prefixBytes instanceof Uint8Array)) {
        throw new TypeError('Argument must be of type Uint8Array or string');
    }
    const checksum = (0, sha256_1.sha256)((0, sha256_1.sha256)(new Uint8Array([...prefixBytes, ...dataBytes])));
    return basex(ALPHABET).encode([...prefixBytes, ...dataBytes, ...checksum.slice(0, 4)]);
}
exports.encode = encode;
function decode(string) {
    const bytes = basex(ALPHABET).decode(string);
    const prefixBytes = bytes.slice(0, 1);
    const dataBytes = bytes.slice(1, -4);
    // todo: for better performance replace spread with `concatBytes` method
    const checksum = (0, sha256_1.sha256)((0, sha256_1.sha256)(new Uint8Array([...prefixBytes, ...dataBytes])));
    bytes.slice(-4).forEach((check, index) => {
        if (check !== checksum[index]) {
            throw new Error('Invalid checksum');
        }
    });
    return { prefix: prefixBytes, data: dataBytes };
}
exports.decode = decode;

},{"@noble/hashes/sha256":7,"@noble/hashes/utils":9,"base-x":64}],61:[function(require,module,exports){
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.c32checkDecode = exports.c32checkEncode = void 0;
const sha256_1 = require("@noble/hashes/sha256");
const utils_1 = require("@noble/hashes/utils");
const encoding_1 = require("./encoding");
/**
 * Get the c32check checksum of a hex-encoded string
 * @param {string} dataHex - the hex string
 * @returns {string} the c32 checksum, as a bin-encoded string
 */
function c32checksum(dataHex) {
    const dataHash = (0, sha256_1.sha256)((0, sha256_1.sha256)((0, utils_1.hexToBytes)(dataHex)));
    const checksum = (0, utils_1.bytesToHex)(dataHash.slice(0, 4));
    return checksum;
}
/**
 * Encode a hex string as a c32check string.  This is a lot like how
 * base58check works in Bitcoin-land, but this algorithm uses the
 * z-base-32 alphabet instead of the base58 alphabet.  The algorithm
 * is as follows:
 * * calculate the c32checksum of version + data
 * * c32encode version + data + c32checksum
 * @param {number} version - the version string (between 0 and 31)
 * @param {string} data - the data to encode
 * @returns {string} the c32check representation
 */
function c32checkEncode(version, data) {
    if (version < 0 || version >= 32) {
        throw new Error('Invalid version (must be between 0 and 31)');
    }
    if (!data.match(/^[0-9a-fA-F]*$/)) {
        throw new Error('Invalid data (not a hex string)');
    }
    data = data.toLowerCase();
    if (data.length % 2 !== 0) {
        data = `0${data}`;
    }
    let versionHex = version.toString(16);
    if (versionHex.length === 1) {
        versionHex = `0${versionHex}`;
    }
    const checksumHex = c32checksum(`${versionHex}${data}`);
    const c32str = (0, encoding_1.c32encode)(`${data}${checksumHex}`);
    return `${encoding_1.c32[version]}${c32str}`;
}
exports.c32checkEncode = c32checkEncode;
/*
 * Decode a c32check string back into its version and data payload.  This is
 * a lot like how base58check works in Bitcoin-land, but this algorithm uses
 * the z-base-32 alphabet instead of the base58 alphabet.  The algorithm
 * is as follows:
 * * extract the version, data, and checksum
 * * verify the checksum matches c32checksum(version + data)
 * * return data
 * @param {string} c32data - the c32check-encoded string
 * @returns {array} [version (number), data (string)].  The returned data
 * will be a hex string.  Throws an exception if the checksum does not match.
 */
function c32checkDecode(c32data) {
    c32data = (0, encoding_1.c32normalize)(c32data);
    const dataHex = (0, encoding_1.c32decode)(c32data.slice(1));
    const versionChar = c32data[0];
    const version = encoding_1.c32.indexOf(versionChar);
    const checksum = dataHex.slice(-8);
    let versionHex = version.toString(16);
    if (versionHex.length === 1) {
        versionHex = `0${versionHex}`;
    }
    if (c32checksum(`${versionHex}${dataHex.substring(0, dataHex.length - 8)}`) !== checksum) {
        throw new Error('Invalid c32check string: checksum mismatch');
    }
    return [version, dataHex.substring(0, dataHex.length - 8)];
}
exports.c32checkDecode = c32checkDecode;

},{"./encoding":62,"@noble/hashes/sha256":7,"@noble/hashes/utils":9}],62:[function(require,module,exports){
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.c32decode = exports.c32normalize = exports.c32encode = exports.c32 = void 0;
const utils_1 = require("@noble/hashes/utils");
exports.c32 = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
const hex = '0123456789abcdef';
/**
 * Encode a hex string as a c32 string.  Note that the hex string is assumed
 * to be big-endian (and the resulting c32 string will be as well).
 * @param {string} inputHex - the input to encode
 * @param {number} minLength - the minimum length of the c32 string
 * @returns {string} the c32check-encoded representation of the data, as a string
 */
function c32encode(inputHex, minLength) {
    // must be hex
    if (!inputHex.match(/^[0-9a-fA-F]*$/)) {
        throw new Error('Not a hex-encoded string');
    }
    if (inputHex.length % 2 !== 0) {
        inputHex = `0${inputHex}`;
    }
    inputHex = inputHex.toLowerCase();
    let res = [];
    let carry = 0;
    for (let i = inputHex.length - 1; i >= 0; i--) {
        if (carry < 4) {
            const currentCode = hex.indexOf(inputHex[i]) >> carry;
            let nextCode = 0;
            if (i !== 0) {
                nextCode = hex.indexOf(inputHex[i - 1]);
            }
            // carry = 0, nextBits is 1, carry = 1, nextBits is 2
            const nextBits = 1 + carry;
            const nextLowBits = nextCode % (1 << nextBits) << (5 - nextBits);
            const curC32Digit = exports.c32[currentCode + nextLowBits];
            carry = nextBits;
            res.unshift(curC32Digit);
        }
        else {
            carry = 0;
        }
    }
    let C32leadingZeros = 0;
    for (let i = 0; i < res.length; i++) {
        if (res[i] !== '0') {
            break;
        }
        else {
            C32leadingZeros++;
        }
    }
    res = res.slice(C32leadingZeros);
    const zeroPrefix = new TextDecoder().decode((0, utils_1.hexToBytes)(inputHex)).match(/^\u0000*/);
    const numLeadingZeroBytesInHex = zeroPrefix ? zeroPrefix[0].length : 0;
    for (let i = 0; i < numLeadingZeroBytesInHex; i++) {
        res.unshift(exports.c32[0]);
    }
    if (minLength) {
        const count = minLength - res.length;
        for (let i = 0; i < count; i++) {
            res.unshift(exports.c32[0]);
        }
    }
    return res.join('');
}
exports.c32encode = c32encode;
/*
 * Normalize a c32 string
 * @param {string} c32input - the c32-encoded input string
 * @returns {string} the canonical representation of the c32 input string
 */
function c32normalize(c32input) {
    // must be upper-case
    // replace all O's with 0's
    // replace all I's and L's with 1's
    return c32input.toUpperCase().replace(/O/g, '0').replace(/L|I/g, '1');
}
exports.c32normalize = c32normalize;
/*
 * Decode a c32 string back into a hex string.  Note that the c32 input
 * string is assumed to be big-endian (and the resulting hex string will
 * be as well).
 * @param {string} c32input - the c32-encoded input to decode
 * @param {number} minLength - the minimum length of the output hex string (in bytes)
 * @returns {string} the hex-encoded representation of the data, as a string
 */
function c32decode(c32input, minLength) {
    c32input = c32normalize(c32input);
    // must result in a c32 string
    if (!c32input.match(`^[${exports.c32}]*$`)) {
        throw new Error('Not a c32-encoded string');
    }
    const zeroPrefix = c32input.match(`^${exports.c32[0]}*`);
    const numLeadingZeroBytes = zeroPrefix ? zeroPrefix[0].length : 0;
    let res = [];
    let carry = 0;
    let carryBits = 0;
    for (let i = c32input.length - 1; i >= 0; i--) {
        if (carryBits === 4) {
            res.unshift(hex[carry]);
            carryBits = 0;
            carry = 0;
        }
        const currentCode = exports.c32.indexOf(c32input[i]) << carryBits;
        const currentValue = currentCode + carry;
        const currentHexDigit = hex[currentValue % 16];
        carryBits += 1;
        carry = currentValue >> 4;
        if (carry > 1 << carryBits) {
            throw new Error('Panic error in decoding.');
        }
        res.unshift(currentHexDigit);
    }
    // one last carry
    res.unshift(hex[carry]);
    if (res.length % 2 === 1) {
        res.unshift('0');
    }
    let hexLeadingZeros = 0;
    for (let i = 0; i < res.length; i++) {
        if (res[i] !== '0') {
            break;
        }
        else {
            hexLeadingZeros++;
        }
    }
    res = res.slice(hexLeadingZeros - (hexLeadingZeros % 2));
    let hexStr = res.join('');
    for (let i = 0; i < numLeadingZeroBytes; i++) {
        hexStr = `00${hexStr}`;
    }
    if (minLength) {
        const count = minLength * 2 - hexStr.length;
        for (let i = 0; i < count; i += 2) {
            hexStr = `00${hexStr}`;
        }
    }
    return hexStr;
}
exports.c32decode = c32decode;

},{"@noble/hashes/utils":9}],63:[function(require,module,exports){
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.b58ToC32 = exports.c32ToB58 = exports.versions = exports.c32normalize = exports.c32addressDecode = exports.c32address = exports.c32checkDecode = exports.c32checkEncode = exports.c32decode = exports.c32encode = void 0;
const encoding_1 = require("./encoding");
Object.defineProperty(exports, "c32encode", { enumerable: true, get: function () { return encoding_1.c32encode; } });
Object.defineProperty(exports, "c32decode", { enumerable: true, get: function () { return encoding_1.c32decode; } });
Object.defineProperty(exports, "c32normalize", { enumerable: true, get: function () { return encoding_1.c32normalize; } });
const checksum_1 = require("./checksum");
Object.defineProperty(exports, "c32checkEncode", { enumerable: true, get: function () { return checksum_1.c32checkEncode; } });
Object.defineProperty(exports, "c32checkDecode", { enumerable: true, get: function () { return checksum_1.c32checkDecode; } });
const address_1 = require("./address");
Object.defineProperty(exports, "c32address", { enumerable: true, get: function () { return address_1.c32address; } });
Object.defineProperty(exports, "c32addressDecode", { enumerable: true, get: function () { return address_1.c32addressDecode; } });
Object.defineProperty(exports, "c32ToB58", { enumerable: true, get: function () { return address_1.c32ToB58; } });
Object.defineProperty(exports, "b58ToC32", { enumerable: true, get: function () { return address_1.b58ToC32; } });
Object.defineProperty(exports, "versions", { enumerable: true, get: function () { return address_1.versions; } });

},{"./address":59,"./checksum":61,"./encoding":62}],64:[function(require,module,exports){
'use strict'
// base-x encoding / decoding
// Copyright (c) 2018 base-x contributors
// Copyright (c) 2014-2018 The Bitcoin Core developers (base58.cpp)
// Distributed under the MIT software license, see the accompanying
// file LICENSE or http://www.opensource.org/licenses/mit-license.php.
function base (ALPHABET) {
  if (ALPHABET.length >= 255) { throw new TypeError('Alphabet too long') }
  var BASE_MAP = new Uint8Array(256)
  for (var j = 0; j < BASE_MAP.length; j++) {
    BASE_MAP[j] = 255
  }
  for (var i = 0; i < ALPHABET.length; i++) {
    var x = ALPHABET.charAt(i)
    var xc = x.charCodeAt(0)
    if (BASE_MAP[xc] !== 255) { throw new TypeError(x + ' is ambiguous') }
    BASE_MAP[xc] = i
  }
  var BASE = ALPHABET.length
  var LEADER = ALPHABET.charAt(0)
  var FACTOR = Math.log(BASE) / Math.log(256) // log(BASE) / log(256), rounded up
  var iFACTOR = Math.log(256) / Math.log(BASE) // log(256) / log(BASE), rounded up
  function encode (source) {
    if (source instanceof Uint8Array) {
    } else if (ArrayBuffer.isView(source)) {
      source = new Uint8Array(source.buffer, source.byteOffset, source.byteLength)
    } else if (Array.isArray(source)) {
      source = Uint8Array.from(source)
    }
    if (!(source instanceof Uint8Array)) { throw new TypeError('Expected Uint8Array') }
    if (source.length === 0) { return '' }
        // Skip & count leading zeroes.
    var zeroes = 0
    var length = 0
    var pbegin = 0
    var pend = source.length
    while (pbegin !== pend && source[pbegin] === 0) {
      pbegin++
      zeroes++
    }
        // Allocate enough space in big-endian base58 representation.
    var size = ((pend - pbegin) * iFACTOR + 1) >>> 0
    var b58 = new Uint8Array(size)
        // Process the bytes.
    while (pbegin !== pend) {
      var carry = source[pbegin]
            // Apply "b58 = b58 * 256 + ch".
      var i = 0
      for (var it1 = size - 1; (carry !== 0 || i < length) && (it1 !== -1); it1--, i++) {
        carry += (256 * b58[it1]) >>> 0
        b58[it1] = (carry % BASE) >>> 0
        carry = (carry / BASE) >>> 0
      }
      if (carry !== 0) { throw new Error('Non-zero carry') }
      length = i
      pbegin++
    }
        // Skip leading zeroes in base58 result.
    var it2 = size - length
    while (it2 !== size && b58[it2] === 0) {
      it2++
    }
        // Translate the result into a string.
    var str = LEADER.repeat(zeroes)
    for (; it2 < size; ++it2) { str += ALPHABET.charAt(b58[it2]) }
    return str
  }
  function decodeUnsafe (source) {
    if (typeof source !== 'string') { throw new TypeError('Expected String') }
    if (source.length === 0) { return new Uint8Array() }
    var psz = 0
        // Skip and count leading '1's.
    var zeroes = 0
    var length = 0
    while (source[psz] === LEADER) {
      zeroes++
      psz++
    }
        // Allocate enough space in big-endian base256 representation.
    var size = (((source.length - psz) * FACTOR) + 1) >>> 0 // log(58) / log(256), rounded up.
    var b256 = new Uint8Array(size)
        // Process the characters.
    while (source[psz]) {
            // Decode character
      var carry = BASE_MAP[source.charCodeAt(psz)]
            // Invalid character
      if (carry === 255) { return }
      var i = 0
      for (var it3 = size - 1; (carry !== 0 || i < length) && (it3 !== -1); it3--, i++) {
        carry += (BASE * b256[it3]) >>> 0
        b256[it3] = (carry % 256) >>> 0
        carry = (carry / 256) >>> 0
      }
      if (carry !== 0) { throw new Error('Non-zero carry') }
      length = i
      psz++
    }
        // Skip leading zeroes in b256.
    var it4 = size - length
    while (it4 !== size && b256[it4] === 0) {
      it4++
    }
    var vch = new Uint8Array(zeroes + (size - it4))
    var j = zeroes
    while (it4 !== size) {
      vch[j++] = b256[it4++]
    }
    return vch
  }
  function decode (string) {
    var buffer = decodeUnsafe(string)
    if (buffer) { return buffer }
    throw new Error('Non-base' + BASE + ' character')
  }
  return {
    encode: encode,
    decodeUnsafe: decodeUnsafe,
    decode: decode
  }
}
module.exports = base

},{}],65:[function(require,module,exports){
(function(self) {

var irrelevant = (function (exports) {

  var support = {
    searchParams: 'URLSearchParams' in self,
    iterable: 'Symbol' in self && 'iterator' in Symbol,
    blob:
      'FileReader' in self &&
      'Blob' in self &&
      (function() {
        try {
          new Blob();
          return true
        } catch (e) {
          return false
        }
      })(),
    formData: 'FormData' in self,
    arrayBuffer: 'ArrayBuffer' in self
  };

  function isDataView(obj) {
    return obj && DataView.prototype.isPrototypeOf(obj)
  }

  if (support.arrayBuffer) {
    var viewClasses = [
      '[object Int8Array]',
      '[object Uint8Array]',
      '[object Uint8ClampedArray]',
      '[object Int16Array]',
      '[object Uint16Array]',
      '[object Int32Array]',
      '[object Uint32Array]',
      '[object Float32Array]',
      '[object Float64Array]'
    ];

    var isArrayBufferView =
      ArrayBuffer.isView ||
      function(obj) {
        return obj && viewClasses.indexOf(Object.prototype.toString.call(obj)) > -1
      };
  }

  function normalizeName(name) {
    if (typeof name !== 'string') {
      name = String(name);
    }
    if (/[^a-z0-9\-#$%&'*+.^_`|~]/i.test(name)) {
      throw new TypeError('Invalid character in header field name')
    }
    return name.toLowerCase()
  }

  function normalizeValue(value) {
    if (typeof value !== 'string') {
      value = String(value);
    }
    return value
  }

  // Build a destructive iterator for the value list
  function iteratorFor(items) {
    var iterator = {
      next: function() {
        var value = items.shift();
        return {done: value === undefined, value: value}
      }
    };

    if (support.iterable) {
      iterator[Symbol.iterator] = function() {
        return iterator
      };
    }

    return iterator
  }

  function Headers(headers) {
    this.map = {};

    if (headers instanceof Headers) {
      headers.forEach(function(value, name) {
        this.append(name, value);
      }, this);
    } else if (Array.isArray(headers)) {
      headers.forEach(function(header) {
        this.append(header[0], header[1]);
      }, this);
    } else if (headers) {
      Object.getOwnPropertyNames(headers).forEach(function(name) {
        this.append(name, headers[name]);
      }, this);
    }
  }

  Headers.prototype.append = function(name, value) {
    name = normalizeName(name);
    value = normalizeValue(value);
    var oldValue = this.map[name];
    this.map[name] = oldValue ? oldValue + ', ' + value : value;
  };

  Headers.prototype['delete'] = function(name) {
    delete this.map[normalizeName(name)];
  };

  Headers.prototype.get = function(name) {
    name = normalizeName(name);
    return this.has(name) ? this.map[name] : null
  };

  Headers.prototype.has = function(name) {
    return this.map.hasOwnProperty(normalizeName(name))
  };

  Headers.prototype.set = function(name, value) {
    this.map[normalizeName(name)] = normalizeValue(value);
  };

  Headers.prototype.forEach = function(callback, thisArg) {
    for (var name in this.map) {
      if (this.map.hasOwnProperty(name)) {
        callback.call(thisArg, this.map[name], name, this);
      }
    }
  };

  Headers.prototype.keys = function() {
    var items = [];
    this.forEach(function(value, name) {
      items.push(name);
    });
    return iteratorFor(items)
  };

  Headers.prototype.values = function() {
    var items = [];
    this.forEach(function(value) {
      items.push(value);
    });
    return iteratorFor(items)
  };

  Headers.prototype.entries = function() {
    var items = [];
    this.forEach(function(value, name) {
      items.push([name, value]);
    });
    return iteratorFor(items)
  };

  if (support.iterable) {
    Headers.prototype[Symbol.iterator] = Headers.prototype.entries;
  }

  function consumed(body) {
    if (body.bodyUsed) {
      return Promise.reject(new TypeError('Already read'))
    }
    body.bodyUsed = true;
  }

  function fileReaderReady(reader) {
    return new Promise(function(resolve, reject) {
      reader.onload = function() {
        resolve(reader.result);
      };
      reader.onerror = function() {
        reject(reader.error);
      };
    })
  }

  function readBlobAsArrayBuffer(blob) {
    var reader = new FileReader();
    var promise = fileReaderReady(reader);
    reader.readAsArrayBuffer(blob);
    return promise
  }

  function readBlobAsText(blob) {
    var reader = new FileReader();
    var promise = fileReaderReady(reader);
    reader.readAsText(blob);
    return promise
  }

  function readArrayBufferAsText(buf) {
    var view = new Uint8Array(buf);
    var chars = new Array(view.length);

    for (var i = 0; i < view.length; i++) {
      chars[i] = String.fromCharCode(view[i]);
    }
    return chars.join('')
  }

  function bufferClone(buf) {
    if (buf.slice) {
      return buf.slice(0)
    } else {
      var view = new Uint8Array(buf.byteLength);
      view.set(new Uint8Array(buf));
      return view.buffer
    }
  }

  function Body() {
    this.bodyUsed = false;

    this._initBody = function(body) {
      this._bodyInit = body;
      if (!body) {
        this._bodyText = '';
      } else if (typeof body === 'string') {
        this._bodyText = body;
      } else if (support.blob && Blob.prototype.isPrototypeOf(body)) {
        this._bodyBlob = body;
      } else if (support.formData && FormData.prototype.isPrototypeOf(body)) {
        this._bodyFormData = body;
      } else if (support.searchParams && URLSearchParams.prototype.isPrototypeOf(body)) {
        this._bodyText = body.toString();
      } else if (support.arrayBuffer && support.blob && isDataView(body)) {
        this._bodyArrayBuffer = bufferClone(body.buffer);
        // IE 10-11 can't handle a DataView body.
        this._bodyInit = new Blob([this._bodyArrayBuffer]);
      } else if (support.arrayBuffer && (ArrayBuffer.prototype.isPrototypeOf(body) || isArrayBufferView(body))) {
        this._bodyArrayBuffer = bufferClone(body);
      } else {
        this._bodyText = body = Object.prototype.toString.call(body);
      }

      if (!this.headers.get('content-type')) {
        if (typeof body === 'string') {
          this.headers.set('content-type', 'text/plain;charset=UTF-8');
        } else if (this._bodyBlob && this._bodyBlob.type) {
          this.headers.set('content-type', this._bodyBlob.type);
        } else if (support.searchParams && URLSearchParams.prototype.isPrototypeOf(body)) {
          this.headers.set('content-type', 'application/x-www-form-urlencoded;charset=UTF-8');
        }
      }
    };

    if (support.blob) {
      this.blob = function() {
        var rejected = consumed(this);
        if (rejected) {
          return rejected
        }

        if (this._bodyBlob) {
          return Promise.resolve(this._bodyBlob)
        } else if (this._bodyArrayBuffer) {
          return Promise.resolve(new Blob([this._bodyArrayBuffer]))
        } else if (this._bodyFormData) {
          throw new Error('could not read FormData body as blob')
        } else {
          return Promise.resolve(new Blob([this._bodyText]))
        }
      };

      this.arrayBuffer = function() {
        if (this._bodyArrayBuffer) {
          return consumed(this) || Promise.resolve(this._bodyArrayBuffer)
        } else {
          return this.blob().then(readBlobAsArrayBuffer)
        }
      };
    }

    this.text = function() {
      var rejected = consumed(this);
      if (rejected) {
        return rejected
      }

      if (this._bodyBlob) {
        return readBlobAsText(this._bodyBlob)
      } else if (this._bodyArrayBuffer) {
        return Promise.resolve(readArrayBufferAsText(this._bodyArrayBuffer))
      } else if (this._bodyFormData) {
        throw new Error('could not read FormData body as text')
      } else {
        return Promise.resolve(this._bodyText)
      }
    };

    if (support.formData) {
      this.formData = function() {
        return this.text().then(decode)
      };
    }

    this.json = function() {
      return this.text().then(JSON.parse)
    };

    return this
  }

  // HTTP methods whose capitalization should be normalized
  var methods = ['DELETE', 'GET', 'HEAD', 'OPTIONS', 'POST', 'PUT'];

  function normalizeMethod(method) {
    var upcased = method.toUpperCase();
    return methods.indexOf(upcased) > -1 ? upcased : method
  }

  function Request(input, options) {
    options = options || {};
    var body = options.body;

    if (input instanceof Request) {
      if (input.bodyUsed) {
        throw new TypeError('Already read')
      }
      this.url = input.url;
      this.credentials = input.credentials;
      if (!options.headers) {
        this.headers = new Headers(input.headers);
      }
      this.method = input.method;
      this.mode = input.mode;
      this.signal = input.signal;
      if (!body && input._bodyInit != null) {
        body = input._bodyInit;
        input.bodyUsed = true;
      }
    } else {
      this.url = String(input);
    }

    this.credentials = options.credentials || this.credentials || 'same-origin';
    if (options.headers || !this.headers) {
      this.headers = new Headers(options.headers);
    }
    this.method = normalizeMethod(options.method || this.method || 'GET');
    this.mode = options.mode || this.mode || null;
    this.signal = options.signal || this.signal;
    this.referrer = null;

    if ((this.method === 'GET' || this.method === 'HEAD') && body) {
      throw new TypeError('Body not allowed for GET or HEAD requests')
    }
    this._initBody(body);
  }

  Request.prototype.clone = function() {
    return new Request(this, {body: this._bodyInit})
  };

  function decode(body) {
    var form = new FormData();
    body
      .trim()
      .split('&')
      .forEach(function(bytes) {
        if (bytes) {
          var split = bytes.split('=');
          var name = split.shift().replace(/\+/g, ' ');
          var value = split.join('=').replace(/\+/g, ' ');
          form.append(decodeURIComponent(name), decodeURIComponent(value));
        }
      });
    return form
  }

  function parseHeaders(rawHeaders) {
    var headers = new Headers();
    // Replace instances of \r\n and \n followed by at least one space or horizontal tab with a space
    // https://tools.ietf.org/html/rfc7230#section-3.2
    var preProcessedHeaders = rawHeaders.replace(/\r?\n[\t ]+/g, ' ');
    preProcessedHeaders.split(/\r?\n/).forEach(function(line) {
      var parts = line.split(':');
      var key = parts.shift().trim();
      if (key) {
        var value = parts.join(':').trim();
        headers.append(key, value);
      }
    });
    return headers
  }

  Body.call(Request.prototype);

  function Response(bodyInit, options) {
    if (!options) {
      options = {};
    }

    this.type = 'default';
    this.status = options.status === undefined ? 200 : options.status;
    this.ok = this.status >= 200 && this.status < 300;
    this.statusText = 'statusText' in options ? options.statusText : 'OK';
    this.headers = new Headers(options.headers);
    this.url = options.url || '';
    this._initBody(bodyInit);
  }

  Body.call(Response.prototype);

  Response.prototype.clone = function() {
    return new Response(this._bodyInit, {
      status: this.status,
      statusText: this.statusText,
      headers: new Headers(this.headers),
      url: this.url
    })
  };

  Response.error = function() {
    var response = new Response(null, {status: 0, statusText: ''});
    response.type = 'error';
    return response
  };

  var redirectStatuses = [301, 302, 303, 307, 308];

  Response.redirect = function(url, status) {
    if (redirectStatuses.indexOf(status) === -1) {
      throw new RangeError('Invalid status code')
    }

    return new Response(null, {status: status, headers: {location: url}})
  };

  exports.DOMException = self.DOMException;
  try {
    new exports.DOMException();
  } catch (err) {
    exports.DOMException = function(message, name) {
      this.message = message;
      this.name = name;
      var error = Error(message);
      this.stack = error.stack;
    };
    exports.DOMException.prototype = Object.create(Error.prototype);
    exports.DOMException.prototype.constructor = exports.DOMException;
  }

  function fetch(input, init) {
    return new Promise(function(resolve, reject) {
      var request = new Request(input, init);

      if (request.signal && request.signal.aborted) {
        return reject(new exports.DOMException('Aborted', 'AbortError'))
      }

      var xhr = new XMLHttpRequest();

      function abortXhr() {
        xhr.abort();
      }

      xhr.onload = function() {
        var options = {
          status: xhr.status,
          statusText: xhr.statusText,
          headers: parseHeaders(xhr.getAllResponseHeaders() || '')
        };
        options.url = 'responseURL' in xhr ? xhr.responseURL : options.headers.get('X-Request-URL');
        var body = 'response' in xhr ? xhr.response : xhr.responseText;
        resolve(new Response(body, options));
      };

      xhr.onerror = function() {
        reject(new TypeError('Network request failed'));
      };

      xhr.ontimeout = function() {
        reject(new TypeError('Network request failed'));
      };

      xhr.onabort = function() {
        reject(new exports.DOMException('Aborted', 'AbortError'));
      };

      xhr.open(request.method, request.url, true);

      if (request.credentials === 'include') {
        xhr.withCredentials = true;
      } else if (request.credentials === 'omit') {
        xhr.withCredentials = false;
      }

      if ('responseType' in xhr && support.blob) {
        xhr.responseType = 'blob';
      }

      request.headers.forEach(function(value, name) {
        xhr.setRequestHeader(name, value);
      });

      if (request.signal) {
        request.signal.addEventListener('abort', abortXhr);

        xhr.onreadystatechange = function() {
          // DONE (success or failure)
          if (xhr.readyState === 4) {
            request.signal.removeEventListener('abort', abortXhr);
          }
        };
      }

      xhr.send(typeof request._bodyInit === 'undefined' ? null : request._bodyInit);
    })
  }

  fetch.polyfill = true;

  if (!self.fetch) {
    self.fetch = fetch;
    self.Headers = Headers;
    self.Request = Request;
    self.Response = Response;
  }

  exports.Headers = Headers;
  exports.Request = Request;
  exports.Response = Response;
  exports.fetch = fetch;

  Object.defineProperty(exports, '__esModule', { value: true });

  return exports;

})({});
})(typeof self !== 'undefined' ? self : this);

},{}],66:[function(require,module,exports){
(function (global){(function (){
/**
 * lodash (Custom Build) <https://lodash.com/>
 * Build: `lodash modularize exports="npm" -o ./`
 * Copyright jQuery Foundation and other contributors <https://jquery.org/>
 * Released under MIT license <https://lodash.com/license>
 * Based on Underscore.js 1.8.3 <http://underscorejs.org/LICENSE>
 * Copyright Jeremy Ashkenas, DocumentCloud and Investigative Reporters & Editors
 */

/** Used as the size to enable large array optimizations. */
var LARGE_ARRAY_SIZE = 200;

/** Used to stand-in for `undefined` hash values. */
var HASH_UNDEFINED = '__lodash_hash_undefined__';

/** Used as references for various `Number` constants. */
var MAX_SAFE_INTEGER = 9007199254740991;

/** `Object#toString` result references. */
var argsTag = '[object Arguments]',
    arrayTag = '[object Array]',
    boolTag = '[object Boolean]',
    dateTag = '[object Date]',
    errorTag = '[object Error]',
    funcTag = '[object Function]',
    genTag = '[object GeneratorFunction]',
    mapTag = '[object Map]',
    numberTag = '[object Number]',
    objectTag = '[object Object]',
    promiseTag = '[object Promise]',
    regexpTag = '[object RegExp]',
    setTag = '[object Set]',
    stringTag = '[object String]',
    symbolTag = '[object Symbol]',
    weakMapTag = '[object WeakMap]';

var arrayBufferTag = '[object ArrayBuffer]',
    dataViewTag = '[object DataView]',
    float32Tag = '[object Float32Array]',
    float64Tag = '[object Float64Array]',
    int8Tag = '[object Int8Array]',
    int16Tag = '[object Int16Array]',
    int32Tag = '[object Int32Array]',
    uint8Tag = '[object Uint8Array]',
    uint8ClampedTag = '[object Uint8ClampedArray]',
    uint16Tag = '[object Uint16Array]',
    uint32Tag = '[object Uint32Array]';

/**
 * Used to match `RegExp`
 * [syntax characters](http://ecma-international.org/ecma-262/7.0/#sec-patterns).
 */
var reRegExpChar = /[\\^$.*+?()[\]{}|]/g;

/** Used to match `RegExp` flags from their coerced string values. */
var reFlags = /\w*$/;

/** Used to detect host constructors (Safari). */
var reIsHostCtor = /^\[object .+?Constructor\]$/;

/** Used to detect unsigned integer values. */
var reIsUint = /^(?:0|[1-9]\d*)$/;

/** Used to identify `toStringTag` values supported by `_.clone`. */
var cloneableTags = {};
cloneableTags[argsTag] = cloneableTags[arrayTag] =
cloneableTags[arrayBufferTag] = cloneableTags[dataViewTag] =
cloneableTags[boolTag] = cloneableTags[dateTag] =
cloneableTags[float32Tag] = cloneableTags[float64Tag] =
cloneableTags[int8Tag] = cloneableTags[int16Tag] =
cloneableTags[int32Tag] = cloneableTags[mapTag] =
cloneableTags[numberTag] = cloneableTags[objectTag] =
cloneableTags[regexpTag] = cloneableTags[setTag] =
cloneableTags[stringTag] = cloneableTags[symbolTag] =
cloneableTags[uint8Tag] = cloneableTags[uint8ClampedTag] =
cloneableTags[uint16Tag] = cloneableTags[uint32Tag] = true;
cloneableTags[errorTag] = cloneableTags[funcTag] =
cloneableTags[weakMapTag] = false;

/** Detect free variable `global` from Node.js. */
var freeGlobal = typeof global == 'object' && global && global.Object === Object && global;

/** Detect free variable `self`. */
var freeSelf = typeof self == 'object' && self && self.Object === Object && self;

/** Used as a reference to the global object. */
var root = freeGlobal || freeSelf || Function('return this')();

/** Detect free variable `exports`. */
var freeExports = typeof exports == 'object' && exports && !exports.nodeType && exports;

/** Detect free variable `module`. */
var freeModule = freeExports && typeof module == 'object' && module && !module.nodeType && module;

/** Detect the popular CommonJS extension `module.exports`. */
var moduleExports = freeModule && freeModule.exports === freeExports;

/**
 * Adds the key-value `pair` to `map`.
 *
 * @private
 * @param {Object} map The map to modify.
 * @param {Array} pair The key-value pair to add.
 * @returns {Object} Returns `map`.
 */
function addMapEntry(map, pair) {
  // Don't return `map.set` because it's not chainable in IE 11.
  map.set(pair[0], pair[1]);
  return map;
}

/**
 * Adds `value` to `set`.
 *
 * @private
 * @param {Object} set The set to modify.
 * @param {*} value The value to add.
 * @returns {Object} Returns `set`.
 */
function addSetEntry(set, value) {
  // Don't return `set.add` because it's not chainable in IE 11.
  set.add(value);
  return set;
}

/**
 * A specialized version of `_.forEach` for arrays without support for
 * iteratee shorthands.
 *
 * @private
 * @param {Array} [array] The array to iterate over.
 * @param {Function} iteratee The function invoked per iteration.
 * @returns {Array} Returns `array`.
 */
function arrayEach(array, iteratee) {
  var index = -1,
      length = array ? array.length : 0;

  while (++index < length) {
    if (iteratee(array[index], index, array) === false) {
      break;
    }
  }
  return array;
}

/**
 * Appends the elements of `values` to `array`.
 *
 * @private
 * @param {Array} array The array to modify.
 * @param {Array} values The values to append.
 * @returns {Array} Returns `array`.
 */
function arrayPush(array, values) {
  var index = -1,
      length = values.length,
      offset = array.length;

  while (++index < length) {
    array[offset + index] = values[index];
  }
  return array;
}

/**
 * A specialized version of `_.reduce` for arrays without support for
 * iteratee shorthands.
 *
 * @private
 * @param {Array} [array] The array to iterate over.
 * @param {Function} iteratee The function invoked per iteration.
 * @param {*} [accumulator] The initial value.
 * @param {boolean} [initAccum] Specify using the first element of `array` as
 *  the initial value.
 * @returns {*} Returns the accumulated value.
 */
function arrayReduce(array, iteratee, accumulator, initAccum) {
  var index = -1,
      length = array ? array.length : 0;

  if (initAccum && length) {
    accumulator = array[++index];
  }
  while (++index < length) {
    accumulator = iteratee(accumulator, array[index], index, array);
  }
  return accumulator;
}

/**
 * The base implementation of `_.times` without support for iteratee shorthands
 * or max array length checks.
 *
 * @private
 * @param {number} n The number of times to invoke `iteratee`.
 * @param {Function} iteratee The function invoked per iteration.
 * @returns {Array} Returns the array of results.
 */
function baseTimes(n, iteratee) {
  var index = -1,
      result = Array(n);

  while (++index < n) {
    result[index] = iteratee(index);
  }
  return result;
}

/**
 * Gets the value at `key` of `object`.
 *
 * @private
 * @param {Object} [object] The object to query.
 * @param {string} key The key of the property to get.
 * @returns {*} Returns the property value.
 */
function getValue(object, key) {
  return object == null ? undefined : object[key];
}

/**
 * Checks if `value` is a host object in IE < 9.
 *
 * @private
 * @param {*} value The value to check.
 * @returns {boolean} Returns `true` if `value` is a host object, else `false`.
 */
function isHostObject(value) {
  // Many host objects are `Object` objects that can coerce to strings
  // despite having improperly defined `toString` methods.
  var result = false;
  if (value != null && typeof value.toString != 'function') {
    try {
      result = !!(value + '');
    } catch (e) {}
  }
  return result;
}

/**
 * Converts `map` to its key-value pairs.
 *
 * @private
 * @param {Object} map The map to convert.
 * @returns {Array} Returns the key-value pairs.
 */
function mapToArray(map) {
  var index = -1,
      result = Array(map.size);

  map.forEach(function(value, key) {
    result[++index] = [key, value];
  });
  return result;
}

/**
 * Creates a unary function that invokes `func` with its argument transformed.
 *
 * @private
 * @param {Function} func The function to wrap.
 * @param {Function} transform The argument transform.
 * @returns {Function} Returns the new function.
 */
function overArg(func, transform) {
  return function(arg) {
    return func(transform(arg));
  };
}

/**
 * Converts `set` to an array of its values.
 *
 * @private
 * @param {Object} set The set to convert.
 * @returns {Array} Returns the values.
 */
function setToArray(set) {
  var index = -1,
      result = Array(set.size);

  set.forEach(function(value) {
    result[++index] = value;
  });
  return result;
}

/** Used for built-in method references. */
var arrayProto = Array.prototype,
    funcProto = Function.prototype,
    objectProto = Object.prototype;

/** Used to detect overreaching core-js shims. */
var coreJsData = root['__core-js_shared__'];

/** Used to detect methods masquerading as native. */
var maskSrcKey = (function() {
  var uid = /[^.]+$/.exec(coreJsData && coreJsData.keys && coreJsData.keys.IE_PROTO || '');
  return uid ? ('Symbol(src)_1.' + uid) : '';
}());

/** Used to resolve the decompiled source of functions. */
var funcToString = funcProto.toString;

/** Used to check objects for own properties. */
var hasOwnProperty = objectProto.hasOwnProperty;

/**
 * Used to resolve the
 * [`toStringTag`](http://ecma-international.org/ecma-262/7.0/#sec-object.prototype.tostring)
 * of values.
 */
var objectToString = objectProto.toString;

/** Used to detect if a method is native. */
var reIsNative = RegExp('^' +
  funcToString.call(hasOwnProperty).replace(reRegExpChar, '\\$&')
  .replace(/hasOwnProperty|(function).*?(?=\\\()| for .+?(?=\\\])/g, '$1.*?') + '$'
);

/** Built-in value references. */
var Buffer = moduleExports ? root.Buffer : undefined,
    Symbol = root.Symbol,
    Uint8Array = root.Uint8Array,
    getPrototype = overArg(Object.getPrototypeOf, Object),
    objectCreate = Object.create,
    propertyIsEnumerable = objectProto.propertyIsEnumerable,
    splice = arrayProto.splice;

/* Built-in method references for those with the same name as other `lodash` methods. */
var nativeGetSymbols = Object.getOwnPropertySymbols,
    nativeIsBuffer = Buffer ? Buffer.isBuffer : undefined,
    nativeKeys = overArg(Object.keys, Object);

/* Built-in method references that are verified to be native. */
var DataView = getNative(root, 'DataView'),
    Map = getNative(root, 'Map'),
    Promise = getNative(root, 'Promise'),
    Set = getNative(root, 'Set'),
    WeakMap = getNative(root, 'WeakMap'),
    nativeCreate = getNative(Object, 'create');

/** Used to detect maps, sets, and weakmaps. */
var dataViewCtorString = toSource(DataView),
    mapCtorString = toSource(Map),
    promiseCtorString = toSource(Promise),
    setCtorString = toSource(Set),
    weakMapCtorString = toSource(WeakMap);

/** Used to convert symbols to primitives and strings. */
var symbolProto = Symbol ? Symbol.prototype : undefined,
    symbolValueOf = symbolProto ? symbolProto.valueOf : undefined;

/**
 * Creates a hash object.
 *
 * @private
 * @constructor
 * @param {Array} [entries] The key-value pairs to cache.
 */
function Hash(entries) {
  var index = -1,
      length = entries ? entries.length : 0;

  this.clear();
  while (++index < length) {
    var entry = entries[index];
    this.set(entry[0], entry[1]);
  }
}

/**
 * Removes all key-value entries from the hash.
 *
 * @private
 * @name clear
 * @memberOf Hash
 */
function hashClear() {
  this.__data__ = nativeCreate ? nativeCreate(null) : {};
}

/**
 * Removes `key` and its value from the hash.
 *
 * @private
 * @name delete
 * @memberOf Hash
 * @param {Object} hash The hash to modify.
 * @param {string} key The key of the value to remove.
 * @returns {boolean} Returns `true` if the entry was removed, else `false`.
 */
function hashDelete(key) {
  return this.has(key) && delete this.__data__[key];
}

/**
 * Gets the hash value for `key`.
 *
 * @private
 * @name get
 * @memberOf Hash
 * @param {string} key The key of the value to get.
 * @returns {*} Returns the entry value.
 */
function hashGet(key) {
  var data = this.__data__;
  if (nativeCreate) {
    var result = data[key];
    return result === HASH_UNDEFINED ? undefined : result;
  }
  return hasOwnProperty.call(data, key) ? data[key] : undefined;
}

/**
 * Checks if a hash value for `key` exists.
 *
 * @private
 * @name has
 * @memberOf Hash
 * @param {string} key The key of the entry to check.
 * @returns {boolean} Returns `true` if an entry for `key` exists, else `false`.
 */
function hashHas(key) {
  var data = this.__data__;
  return nativeCreate ? data[key] !== undefined : hasOwnProperty.call(data, key);
}

/**
 * Sets the hash `key` to `value`.
 *
 * @private
 * @name set
 * @memberOf Hash
 * @param {string} key The key of the value to set.
 * @param {*} value The value to set.
 * @returns {Object} Returns the hash instance.
 */
function hashSet(key, value) {
  var data = this.__data__;
  data[key] = (nativeCreate && value === undefined) ? HASH_UNDEFINED : value;
  return this;
}

// Add methods to `Hash`.
Hash.prototype.clear = hashClear;
Hash.prototype['delete'] = hashDelete;
Hash.prototype.get = hashGet;
Hash.prototype.has = hashHas;
Hash.prototype.set = hashSet;

/**
 * Creates an list cache object.
 *
 * @private
 * @constructor
 * @param {Array} [entries] The key-value pairs to cache.
 */
function ListCache(entries) {
  var index = -1,
      length = entries ? entries.length : 0;

  this.clear();
  while (++index < length) {
    var entry = entries[index];
    this.set(entry[0], entry[1]);
  }
}

/**
 * Removes all key-value entries from the list cache.
 *
 * @private
 * @name clear
 * @memberOf ListCache
 */
function listCacheClear() {
  this.__data__ = [];
}

/**
 * Removes `key` and its value from the list cache.
 *
 * @private
 * @name delete
 * @memberOf ListCache
 * @param {string} key The key of the value to remove.
 * @returns {boolean} Returns `true` if the entry was removed, else `false`.
 */
function listCacheDelete(key) {
  var data = this.__data__,
      index = assocIndexOf(data, key);

  if (index < 0) {
    return false;
  }
  var lastIndex = data.length - 1;
  if (index == lastIndex) {
    data.pop();
  } else {
    splice.call(data, index, 1);
  }
  return true;
}

/**
 * Gets the list cache value for `key`.
 *
 * @private
 * @name get
 * @memberOf ListCache
 * @param {string} key The key of the value to get.
 * @returns {*} Returns the entry value.
 */
function listCacheGet(key) {
  var data = this.__data__,
      index = assocIndexOf(data, key);

  return index < 0 ? undefined : data[index][1];
}

/**
 * Checks if a list cache value for `key` exists.
 *
 * @private
 * @name has
 * @memberOf ListCache
 * @param {string} key The key of the entry to check.
 * @returns {boolean} Returns `true` if an entry for `key` exists, else `false`.
 */
function listCacheHas(key) {
  return assocIndexOf(this.__data__, key) > -1;
}

/**
 * Sets the list cache `key` to `value`.
 *
 * @private
 * @name set
 * @memberOf ListCache
 * @param {string} key The key of the value to set.
 * @param {*} value The value to set.
 * @returns {Object} Returns the list cache instance.
 */
function listCacheSet(key, value) {
  var data = this.__data__,
      index = assocIndexOf(data, key);

  if (index < 0) {
    data.push([key, value]);
  } else {
    data[index][1] = value;
  }
  return this;
}

// Add methods to `ListCache`.
ListCache.prototype.clear = listCacheClear;
ListCache.prototype['delete'] = listCacheDelete;
ListCache.prototype.get = listCacheGet;
ListCache.prototype.has = listCacheHas;
ListCache.prototype.set = listCacheSet;

/**
 * Creates a map cache object to store key-value pairs.
 *
 * @private
 * @constructor
 * @param {Array} [entries] The key-value pairs to cache.
 */
function MapCache(entries) {
  var index = -1,
      length = entries ? entries.length : 0;

  this.clear();
  while (++index < length) {
    var entry = entries[index];
    this.set(entry[0], entry[1]);
  }
}

/**
 * Removes all key-value entries from the map.
 *
 * @private
 * @name clear
 * @memberOf MapCache
 */
function mapCacheClear() {
  this.__data__ = {
    'hash': new Hash,
    'map': new (Map || ListCache),
    'string': new Hash
  };
}

/**
 * Removes `key` and its value from the map.
 *
 * @private
 * @name delete
 * @memberOf MapCache
 * @param {string} key The key of the value to remove.
 * @returns {boolean} Returns `true` if the entry was removed, else `false`.
 */
function mapCacheDelete(key) {
  return getMapData(this, key)['delete'](key);
}

/**
 * Gets the map value for `key`.
 *
 * @private
 * @name get
 * @memberOf MapCache
 * @param {string} key The key of the value to get.
 * @returns {*} Returns the entry value.
 */
function mapCacheGet(key) {
  return getMapData(this, key).get(key);
}

/**
 * Checks if a map value for `key` exists.
 *
 * @private
 * @name has
 * @memberOf MapCache
 * @param {string} key The key of the entry to check.
 * @returns {boolean} Returns `true` if an entry for `key` exists, else `false`.
 */
function mapCacheHas(key) {
  return getMapData(this, key).has(key);
}

/**
 * Sets the map `key` to `value`.
 *
 * @private
 * @name set
 * @memberOf MapCache
 * @param {string} key The key of the value to set.
 * @param {*} value The value to set.
 * @returns {Object} Returns the map cache instance.
 */
function mapCacheSet(key, value) {
  getMapData(this, key).set(key, value);
  return this;
}

// Add methods to `MapCache`.
MapCache.prototype.clear = mapCacheClear;
MapCache.prototype['delete'] = mapCacheDelete;
MapCache.prototype.get = mapCacheGet;
MapCache.prototype.has = mapCacheHas;
MapCache.prototype.set = mapCacheSet;

/**
 * Creates a stack cache object to store key-value pairs.
 *
 * @private
 * @constructor
 * @param {Array} [entries] The key-value pairs to cache.
 */
function Stack(entries) {
  this.__data__ = new ListCache(entries);
}

/**
 * Removes all key-value entries from the stack.
 *
 * @private
 * @name clear
 * @memberOf Stack
 */
function stackClear() {
  this.__data__ = new ListCache;
}

/**
 * Removes `key` and its value from the stack.
 *
 * @private
 * @name delete
 * @memberOf Stack
 * @param {string} key The key of the value to remove.
 * @returns {boolean} Returns `true` if the entry was removed, else `false`.
 */
function stackDelete(key) {
  return this.__data__['delete'](key);
}

/**
 * Gets the stack value for `key`.
 *
 * @private
 * @name get
 * @memberOf Stack
 * @param {string} key The key of the value to get.
 * @returns {*} Returns the entry value.
 */
function stackGet(key) {
  return this.__data__.get(key);
}

/**
 * Checks if a stack value for `key` exists.
 *
 * @private
 * @name has
 * @memberOf Stack
 * @param {string} key The key of the entry to check.
 * @returns {boolean} Returns `true` if an entry for `key` exists, else `false`.
 */
function stackHas(key) {
  return this.__data__.has(key);
}

/**
 * Sets the stack `key` to `value`.
 *
 * @private
 * @name set
 * @memberOf Stack
 * @param {string} key The key of the value to set.
 * @param {*} value The value to set.
 * @returns {Object} Returns the stack cache instance.
 */
function stackSet(key, value) {
  var cache = this.__data__;
  if (cache instanceof ListCache) {
    var pairs = cache.__data__;
    if (!Map || (pairs.length < LARGE_ARRAY_SIZE - 1)) {
      pairs.push([key, value]);
      return this;
    }
    cache = this.__data__ = new MapCache(pairs);
  }
  cache.set(key, value);
  return this;
}

// Add methods to `Stack`.
Stack.prototype.clear = stackClear;
Stack.prototype['delete'] = stackDelete;
Stack.prototype.get = stackGet;
Stack.prototype.has = stackHas;
Stack.prototype.set = stackSet;

/**
 * Creates an array of the enumerable property names of the array-like `value`.
 *
 * @private
 * @param {*} value The value to query.
 * @param {boolean} inherited Specify returning inherited property names.
 * @returns {Array} Returns the array of property names.
 */
function arrayLikeKeys(value, inherited) {
  // Safari 8.1 makes `arguments.callee` enumerable in strict mode.
  // Safari 9 makes `arguments.length` enumerable in strict mode.
  var result = (isArray(value) || isArguments(value))
    ? baseTimes(value.length, String)
    : [];

  var length = result.length,
      skipIndexes = !!length;

  for (var key in value) {
    if ((inherited || hasOwnProperty.call(value, key)) &&
        !(skipIndexes && (key == 'length' || isIndex(key, length)))) {
      result.push(key);
    }
  }
  return result;
}

/**
 * Assigns `value` to `key` of `object` if the existing value is not equivalent
 * using [`SameValueZero`](http://ecma-international.org/ecma-262/7.0/#sec-samevaluezero)
 * for equality comparisons.
 *
 * @private
 * @param {Object} object The object to modify.
 * @param {string} key The key of the property to assign.
 * @param {*} value The value to assign.
 */
function assignValue(object, key, value) {
  var objValue = object[key];
  if (!(hasOwnProperty.call(object, key) && eq(objValue, value)) ||
      (value === undefined && !(key in object))) {
    object[key] = value;
  }
}

/**
 * Gets the index at which the `key` is found in `array` of key-value pairs.
 *
 * @private
 * @param {Array} array The array to inspect.
 * @param {*} key The key to search for.
 * @returns {number} Returns the index of the matched value, else `-1`.
 */
function assocIndexOf(array, key) {
  var length = array.length;
  while (length--) {
    if (eq(array[length][0], key)) {
      return length;
    }
  }
  return -1;
}

/**
 * The base implementation of `_.assign` without support for multiple sources
 * or `customizer` functions.
 *
 * @private
 * @param {Object} object The destination object.
 * @param {Object} source The source object.
 * @returns {Object} Returns `object`.
 */
function baseAssign(object, source) {
  return object && copyObject(source, keys(source), object);
}

/**
 * The base implementation of `_.clone` and `_.cloneDeep` which tracks
 * traversed objects.
 *
 * @private
 * @param {*} value The value to clone.
 * @param {boolean} [isDeep] Specify a deep clone.
 * @param {boolean} [isFull] Specify a clone including symbols.
 * @param {Function} [customizer] The function to customize cloning.
 * @param {string} [key] The key of `value`.
 * @param {Object} [object] The parent object of `value`.
 * @param {Object} [stack] Tracks traversed objects and their clone counterparts.
 * @returns {*} Returns the cloned value.
 */
function baseClone(value, isDeep, isFull, customizer, key, object, stack) {
  var result;
  if (customizer) {
    result = object ? customizer(value, key, object, stack) : customizer(value);
  }
  if (result !== undefined) {
    return result;
  }
  if (!isObject(value)) {
    return value;
  }
  var isArr = isArray(value);
  if (isArr) {
    result = initCloneArray(value);
    if (!isDeep) {
      return copyArray(value, result);
    }
  } else {
    var tag = getTag(value),
        isFunc = tag == funcTag || tag == genTag;

    if (isBuffer(value)) {
      return cloneBuffer(value, isDeep);
    }
    if (tag == objectTag || tag == argsTag || (isFunc && !object)) {
      if (isHostObject(value)) {
        return object ? value : {};
      }
      result = initCloneObject(isFunc ? {} : value);
      if (!isDeep) {
        return copySymbols(value, baseAssign(result, value));
      }
    } else {
      if (!cloneableTags[tag]) {
        return object ? value : {};
      }
      result = initCloneByTag(value, tag, baseClone, isDeep);
    }
  }
  // Check for circular references and return its corresponding clone.
  stack || (stack = new Stack);
  var stacked = stack.get(value);
  if (stacked) {
    return stacked;
  }
  stack.set(value, result);

  if (!isArr) {
    var props = isFull ? getAllKeys(value) : keys(value);
  }
  arrayEach(props || value, function(subValue, key) {
    if (props) {
      key = subValue;
      subValue = value[key];
    }
    // Recursively populate clone (susceptible to call stack limits).
    assignValue(result, key, baseClone(subValue, isDeep, isFull, customizer, key, value, stack));
  });
  return result;
}

/**
 * The base implementation of `_.create` without support for assigning
 * properties to the created object.
 *
 * @private
 * @param {Object} prototype The object to inherit from.
 * @returns {Object} Returns the new object.
 */
function baseCreate(proto) {
  return isObject(proto) ? objectCreate(proto) : {};
}

/**
 * The base implementation of `getAllKeys` and `getAllKeysIn` which uses
 * `keysFunc` and `symbolsFunc` to get the enumerable property names and
 * symbols of `object`.
 *
 * @private
 * @param {Object} object The object to query.
 * @param {Function} keysFunc The function to get the keys of `object`.
 * @param {Function} symbolsFunc The function to get the symbols of `object`.
 * @returns {Array} Returns the array of property names and symbols.
 */
function baseGetAllKeys(object, keysFunc, symbolsFunc) {
  var result = keysFunc(object);
  return isArray(object) ? result : arrayPush(result, symbolsFunc(object));
}

/**
 * The base implementation of `getTag`.
 *
 * @private
 * @param {*} value The value to query.
 * @returns {string} Returns the `toStringTag`.
 */
function baseGetTag(value) {
  return objectToString.call(value);
}

/**
 * The base implementation of `_.isNative` without bad shim checks.
 *
 * @private
 * @param {*} value The value to check.
 * @returns {boolean} Returns `true` if `value` is a native function,
 *  else `false`.
 */
function baseIsNative(value) {
  if (!isObject(value) || isMasked(value)) {
    return false;
  }
  var pattern = (isFunction(value) || isHostObject(value)) ? reIsNative : reIsHostCtor;
  return pattern.test(toSource(value));
}

/**
 * The base implementation of `_.keys` which doesn't treat sparse arrays as dense.
 *
 * @private
 * @param {Object} object The object to query.
 * @returns {Array} Returns the array of property names.
 */
function baseKeys(object) {
  if (!isPrototype(object)) {
    return nativeKeys(object);
  }
  var result = [];
  for (var key in Object(object)) {
    if (hasOwnProperty.call(object, key) && key != 'constructor') {
      result.push(key);
    }
  }
  return result;
}

/**
 * Creates a clone of  `buffer`.
 *
 * @private
 * @param {Buffer} buffer The buffer to clone.
 * @param {boolean} [isDeep] Specify a deep clone.
 * @returns {Buffer} Returns the cloned buffer.
 */
function cloneBuffer(buffer, isDeep) {
  if (isDeep) {
    return buffer.slice();
  }
  var result = new buffer.constructor(buffer.length);
  buffer.copy(result);
  return result;
}

/**
 * Creates a clone of `arrayBuffer`.
 *
 * @private
 * @param {ArrayBuffer} arrayBuffer The array buffer to clone.
 * @returns {ArrayBuffer} Returns the cloned array buffer.
 */
function cloneArrayBuffer(arrayBuffer) {
  var result = new arrayBuffer.constructor(arrayBuffer.byteLength);
  new Uint8Array(result).set(new Uint8Array(arrayBuffer));
  return result;
}

/**
 * Creates a clone of `dataView`.
 *
 * @private
 * @param {Object} dataView The data view to clone.
 * @param {boolean} [isDeep] Specify a deep clone.
 * @returns {Object} Returns the cloned data view.
 */
function cloneDataView(dataView, isDeep) {
  var buffer = isDeep ? cloneArrayBuffer(dataView.buffer) : dataView.buffer;
  return new dataView.constructor(buffer, dataView.byteOffset, dataView.byteLength);
}

/**
 * Creates a clone of `map`.
 *
 * @private
 * @param {Object} map The map to clone.
 * @param {Function} cloneFunc The function to clone values.
 * @param {boolean} [isDeep] Specify a deep clone.
 * @returns {Object} Returns the cloned map.
 */
function cloneMap(map, isDeep, cloneFunc) {
  var array = isDeep ? cloneFunc(mapToArray(map), true) : mapToArray(map);
  return arrayReduce(array, addMapEntry, new map.constructor);
}

/**
 * Creates a clone of `regexp`.
 *
 * @private
 * @param {Object} regexp The regexp to clone.
 * @returns {Object} Returns the cloned regexp.
 */
function cloneRegExp(regexp) {
  var result = new regexp.constructor(regexp.source, reFlags.exec(regexp));
  result.lastIndex = regexp.lastIndex;
  return result;
}

/**
 * Creates a clone of `set`.
 *
 * @private
 * @param {Object} set The set to clone.
 * @param {Function} cloneFunc The function to clone values.
 * @param {boolean} [isDeep] Specify a deep clone.
 * @returns {Object} Returns the cloned set.
 */
function cloneSet(set, isDeep, cloneFunc) {
  var array = isDeep ? cloneFunc(setToArray(set), true) : setToArray(set);
  return arrayReduce(array, addSetEntry, new set.constructor);
}

/**
 * Creates a clone of the `symbol` object.
 *
 * @private
 * @param {Object} symbol The symbol object to clone.
 * @returns {Object} Returns the cloned symbol object.
 */
function cloneSymbol(symbol) {
  return symbolValueOf ? Object(symbolValueOf.call(symbol)) : {};
}

/**
 * Creates a clone of `typedArray`.
 *
 * @private
 * @param {Object} typedArray The typed array to clone.
 * @param {boolean} [isDeep] Specify a deep clone.
 * @returns {Object} Returns the cloned typed array.
 */
function cloneTypedArray(typedArray, isDeep) {
  var buffer = isDeep ? cloneArrayBuffer(typedArray.buffer) : typedArray.buffer;
  return new typedArray.constructor(buffer, typedArray.byteOffset, typedArray.length);
}

/**
 * Copies the values of `source` to `array`.
 *
 * @private
 * @param {Array} source The array to copy values from.
 * @param {Array} [array=[]] The array to copy values to.
 * @returns {Array} Returns `array`.
 */
function copyArray(source, array) {
  var index = -1,
      length = source.length;

  array || (array = Array(length));
  while (++index < length) {
    array[index] = source[index];
  }
  return array;
}

/**
 * Copies properties of `source` to `object`.
 *
 * @private
 * @param {Object} source The object to copy properties from.
 * @param {Array} props The property identifiers to copy.
 * @param {Object} [object={}] The object to copy properties to.
 * @param {Function} [customizer] The function to customize copied values.
 * @returns {Object} Returns `object`.
 */
function copyObject(source, props, object, customizer) {
  object || (object = {});

  var index = -1,
      length = props.length;

  while (++index < length) {
    var key = props[index];

    var newValue = customizer
      ? customizer(object[key], source[key], key, object, source)
      : undefined;

    assignValue(object, key, newValue === undefined ? source[key] : newValue);
  }
  return object;
}

/**
 * Copies own symbol properties of `source` to `object`.
 *
 * @private
 * @param {Object} source The object to copy symbols from.
 * @param {Object} [object={}] The object to copy symbols to.
 * @returns {Object} Returns `object`.
 */
function copySymbols(source, object) {
  return copyObject(source, getSymbols(source), object);
}

/**
 * Creates an array of own enumerable property names and symbols of `object`.
 *
 * @private
 * @param {Object} object The object to query.
 * @returns {Array} Returns the array of property names and symbols.
 */
function getAllKeys(object) {
  return baseGetAllKeys(object, keys, getSymbols);
}

/**
 * Gets the data for `map`.
 *
 * @private
 * @param {Object} map The map to query.
 * @param {string} key The reference key.
 * @returns {*} Returns the map data.
 */
function getMapData(map, key) {
  var data = map.__data__;
  return isKeyable(key)
    ? data[typeof key == 'string' ? 'string' : 'hash']
    : data.map;
}

/**
 * Gets the native function at `key` of `object`.
 *
 * @private
 * @param {Object} object The object to query.
 * @param {string} key The key of the method to get.
 * @returns {*} Returns the function if it's native, else `undefined`.
 */
function getNative(object, key) {
  var value = getValue(object, key);
  return baseIsNative(value) ? value : undefined;
}

/**
 * Creates an array of the own enumerable symbol properties of `object`.
 *
 * @private
 * @param {Object} object The object to query.
 * @returns {Array} Returns the array of symbols.
 */
var getSymbols = nativeGetSymbols ? overArg(nativeGetSymbols, Object) : stubArray;

/**
 * Gets the `toStringTag` of `value`.
 *
 * @private
 * @param {*} value The value to query.
 * @returns {string} Returns the `toStringTag`.
 */
var getTag = baseGetTag;

// Fallback for data views, maps, sets, and weak maps in IE 11,
// for data views in Edge < 14, and promises in Node.js.
if ((DataView && getTag(new DataView(new ArrayBuffer(1))) != dataViewTag) ||
    (Map && getTag(new Map) != mapTag) ||
    (Promise && getTag(Promise.resolve()) != promiseTag) ||
    (Set && getTag(new Set) != setTag) ||
    (WeakMap && getTag(new WeakMap) != weakMapTag)) {
  getTag = function(value) {
    var result = objectToString.call(value),
        Ctor = result == objectTag ? value.constructor : undefined,
        ctorString = Ctor ? toSource(Ctor) : undefined;

    if (ctorString) {
      switch (ctorString) {
        case dataViewCtorString: return dataViewTag;
        case mapCtorString: return mapTag;
        case promiseCtorString: return promiseTag;
        case setCtorString: return setTag;
        case weakMapCtorString: return weakMapTag;
      }
    }
    return result;
  };
}

/**
 * Initializes an array clone.
 *
 * @private
 * @param {Array} array The array to clone.
 * @returns {Array} Returns the initialized clone.
 */
function initCloneArray(array) {
  var length = array.length,
      result = array.constructor(length);

  // Add properties assigned by `RegExp#exec`.
  if (length && typeof array[0] == 'string' && hasOwnProperty.call(array, 'index')) {
    result.index = array.index;
    result.input = array.input;
  }
  return result;
}

/**
 * Initializes an object clone.
 *
 * @private
 * @param {Object} object The object to clone.
 * @returns {Object} Returns the initialized clone.
 */
function initCloneObject(object) {
  return (typeof object.constructor == 'function' && !isPrototype(object))
    ? baseCreate(getPrototype(object))
    : {};
}

/**
 * Initializes an object clone based on its `toStringTag`.
 *
 * **Note:** This function only supports cloning values with tags of
 * `Boolean`, `Date`, `Error`, `Number`, `RegExp`, or `String`.
 *
 * @private
 * @param {Object} object The object to clone.
 * @param {string} tag The `toStringTag` of the object to clone.
 * @param {Function} cloneFunc The function to clone values.
 * @param {boolean} [isDeep] Specify a deep clone.
 * @returns {Object} Returns the initialized clone.
 */
function initCloneByTag(object, tag, cloneFunc, isDeep) {
  var Ctor = object.constructor;
  switch (tag) {
    case arrayBufferTag:
      return cloneArrayBuffer(object);

    case boolTag:
    case dateTag:
      return new Ctor(+object);

    case dataViewTag:
      return cloneDataView(object, isDeep);

    case float32Tag: case float64Tag:
    case int8Tag: case int16Tag: case int32Tag:
    case uint8Tag: case uint8ClampedTag: case uint16Tag: case uint32Tag:
      return cloneTypedArray(object, isDeep);

    case mapTag:
      return cloneMap(object, isDeep, cloneFunc);

    case numberTag:
    case stringTag:
      return new Ctor(object);

    case regexpTag:
      return cloneRegExp(object);

    case setTag:
      return cloneSet(object, isDeep, cloneFunc);

    case symbolTag:
      return cloneSymbol(object);
  }
}

/**
 * Checks if `value` is a valid array-like index.
 *
 * @private
 * @param {*} value The value to check.
 * @param {number} [length=MAX_SAFE_INTEGER] The upper bounds of a valid index.
 * @returns {boolean} Returns `true` if `value` is a valid index, else `false`.
 */
function isIndex(value, length) {
  length = length == null ? MAX_SAFE_INTEGER : length;
  return !!length &&
    (typeof value == 'number' || reIsUint.test(value)) &&
    (value > -1 && value % 1 == 0 && value < length);
}

/**
 * Checks if `value` is suitable for use as unique object key.
 *
 * @private
 * @param {*} value The value to check.
 * @returns {boolean} Returns `true` if `value` is suitable, else `false`.
 */
function isKeyable(value) {
  var type = typeof value;
  return (type == 'string' || type == 'number' || type == 'symbol' || type == 'boolean')
    ? (value !== '__proto__')
    : (value === null);
}

/**
 * Checks if `func` has its source masked.
 *
 * @private
 * @param {Function} func The function to check.
 * @returns {boolean} Returns `true` if `func` is masked, else `false`.
 */
function isMasked(func) {
  return !!maskSrcKey && (maskSrcKey in func);
}

/**
 * Checks if `value` is likely a prototype object.
 *
 * @private
 * @param {*} value The value to check.
 * @returns {boolean} Returns `true` if `value` is a prototype, else `false`.
 */
function isPrototype(value) {
  var Ctor = value && value.constructor,
      proto = (typeof Ctor == 'function' && Ctor.prototype) || objectProto;

  return value === proto;
}

/**
 * Converts `func` to its source code.
 *
 * @private
 * @param {Function} func The function to process.
 * @returns {string} Returns the source code.
 */
function toSource(func) {
  if (func != null) {
    try {
      return funcToString.call(func);
    } catch (e) {}
    try {
      return (func + '');
    } catch (e) {}
  }
  return '';
}

/**
 * This method is like `_.clone` except that it recursively clones `value`.
 *
 * @static
 * @memberOf _
 * @since 1.0.0
 * @category Lang
 * @param {*} value The value to recursively clone.
 * @returns {*} Returns the deep cloned value.
 * @see _.clone
 * @example
 *
 * var objects = [{ 'a': 1 }, { 'b': 2 }];
 *
 * var deep = _.cloneDeep(objects);
 * console.log(deep[0] === objects[0]);
 * // => false
 */
function cloneDeep(value) {
  return baseClone(value, true, true);
}

/**
 * Performs a
 * [`SameValueZero`](http://ecma-international.org/ecma-262/7.0/#sec-samevaluezero)
 * comparison between two values to determine if they are equivalent.
 *
 * @static
 * @memberOf _
 * @since 4.0.0
 * @category Lang
 * @param {*} value The value to compare.
 * @param {*} other The other value to compare.
 * @returns {boolean} Returns `true` if the values are equivalent, else `false`.
 * @example
 *
 * var object = { 'a': 1 };
 * var other = { 'a': 1 };
 *
 * _.eq(object, object);
 * // => true
 *
 * _.eq(object, other);
 * // => false
 *
 * _.eq('a', 'a');
 * // => true
 *
 * _.eq('a', Object('a'));
 * // => false
 *
 * _.eq(NaN, NaN);
 * // => true
 */
function eq(value, other) {
  return value === other || (value !== value && other !== other);
}

/**
 * Checks if `value` is likely an `arguments` object.
 *
 * @static
 * @memberOf _
 * @since 0.1.0
 * @category Lang
 * @param {*} value The value to check.
 * @returns {boolean} Returns `true` if `value` is an `arguments` object,
 *  else `false`.
 * @example
 *
 * _.isArguments(function() { return arguments; }());
 * // => true
 *
 * _.isArguments([1, 2, 3]);
 * // => false
 */
function isArguments(value) {
  // Safari 8.1 makes `arguments.callee` enumerable in strict mode.
  return isArrayLikeObject(value) && hasOwnProperty.call(value, 'callee') &&
    (!propertyIsEnumerable.call(value, 'callee') || objectToString.call(value) == argsTag);
}

/**
 * Checks if `value` is classified as an `Array` object.
 *
 * @static
 * @memberOf _
 * @since 0.1.0
 * @category Lang
 * @param {*} value The value to check.
 * @returns {boolean} Returns `true` if `value` is an array, else `false`.
 * @example
 *
 * _.isArray([1, 2, 3]);
 * // => true
 *
 * _.isArray(document.body.children);
 * // => false
 *
 * _.isArray('abc');
 * // => false
 *
 * _.isArray(_.noop);
 * // => false
 */
var isArray = Array.isArray;

/**
 * Checks if `value` is array-like. A value is considered array-like if it's
 * not a function and has a `value.length` that's an integer greater than or
 * equal to `0` and less than or equal to `Number.MAX_SAFE_INTEGER`.
 *
 * @static
 * @memberOf _
 * @since 4.0.0
 * @category Lang
 * @param {*} value The value to check.
 * @returns {boolean} Returns `true` if `value` is array-like, else `false`.
 * @example
 *
 * _.isArrayLike([1, 2, 3]);
 * // => true
 *
 * _.isArrayLike(document.body.children);
 * // => true
 *
 * _.isArrayLike('abc');
 * // => true
 *
 * _.isArrayLike(_.noop);
 * // => false
 */
function isArrayLike(value) {
  return value != null && isLength(value.length) && !isFunction(value);
}

/**
 * This method is like `_.isArrayLike` except that it also checks if `value`
 * is an object.
 *
 * @static
 * @memberOf _
 * @since 4.0.0
 * @category Lang
 * @param {*} value The value to check.
 * @returns {boolean} Returns `true` if `value` is an array-like object,
 *  else `false`.
 * @example
 *
 * _.isArrayLikeObject([1, 2, 3]);
 * // => true
 *
 * _.isArrayLikeObject(document.body.children);
 * // => true
 *
 * _.isArrayLikeObject('abc');
 * // => false
 *
 * _.isArrayLikeObject(_.noop);
 * // => false
 */
function isArrayLikeObject(value) {
  return isObjectLike(value) && isArrayLike(value);
}

/**
 * Checks if `value` is a buffer.
 *
 * @static
 * @memberOf _
 * @since 4.3.0
 * @category Lang
 * @param {*} value The value to check.
 * @returns {boolean} Returns `true` if `value` is a buffer, else `false`.
 * @example
 *
 * _.isBuffer(new Buffer(2));
 * // => true
 *
 * _.isBuffer(new Uint8Array(2));
 * // => false
 */
var isBuffer = nativeIsBuffer || stubFalse;

/**
 * Checks if `value` is classified as a `Function` object.
 *
 * @static
 * @memberOf _
 * @since 0.1.0
 * @category Lang
 * @param {*} value The value to check.
 * @returns {boolean} Returns `true` if `value` is a function, else `false`.
 * @example
 *
 * _.isFunction(_);
 * // => true
 *
 * _.isFunction(/abc/);
 * // => false
 */
function isFunction(value) {
  // The use of `Object#toString` avoids issues with the `typeof` operator
  // in Safari 8-9 which returns 'object' for typed array and other constructors.
  var tag = isObject(value) ? objectToString.call(value) : '';
  return tag == funcTag || tag == genTag;
}

/**
 * Checks if `value` is a valid array-like length.
 *
 * **Note:** This method is loosely based on
 * [`ToLength`](http://ecma-international.org/ecma-262/7.0/#sec-tolength).
 *
 * @static
 * @memberOf _
 * @since 4.0.0
 * @category Lang
 * @param {*} value The value to check.
 * @returns {boolean} Returns `true` if `value` is a valid length, else `false`.
 * @example
 *
 * _.isLength(3);
 * // => true
 *
 * _.isLength(Number.MIN_VALUE);
 * // => false
 *
 * _.isLength(Infinity);
 * // => false
 *
 * _.isLength('3');
 * // => false
 */
function isLength(value) {
  return typeof value == 'number' &&
    value > -1 && value % 1 == 0 && value <= MAX_SAFE_INTEGER;
}

/**
 * Checks if `value` is the
 * [language type](http://www.ecma-international.org/ecma-262/7.0/#sec-ecmascript-language-types)
 * of `Object`. (e.g. arrays, functions, objects, regexes, `new Number(0)`, and `new String('')`)
 *
 * @static
 * @memberOf _
 * @since 0.1.0
 * @category Lang
 * @param {*} value The value to check.
 * @returns {boolean} Returns `true` if `value` is an object, else `false`.
 * @example
 *
 * _.isObject({});
 * // => true
 *
 * _.isObject([1, 2, 3]);
 * // => true
 *
 * _.isObject(_.noop);
 * // => true
 *
 * _.isObject(null);
 * // => false
 */
function isObject(value) {
  var type = typeof value;
  return !!value && (type == 'object' || type == 'function');
}

/**
 * Checks if `value` is object-like. A value is object-like if it's not `null`
 * and has a `typeof` result of "object".
 *
 * @static
 * @memberOf _
 * @since 4.0.0
 * @category Lang
 * @param {*} value The value to check.
 * @returns {boolean} Returns `true` if `value` is object-like, else `false`.
 * @example
 *
 * _.isObjectLike({});
 * // => true
 *
 * _.isObjectLike([1, 2, 3]);
 * // => true
 *
 * _.isObjectLike(_.noop);
 * // => false
 *
 * _.isObjectLike(null);
 * // => false
 */
function isObjectLike(value) {
  return !!value && typeof value == 'object';
}

/**
 * Creates an array of the own enumerable property names of `object`.
 *
 * **Note:** Non-object values are coerced to objects. See the
 * [ES spec](http://ecma-international.org/ecma-262/7.0/#sec-object.keys)
 * for more details.
 *
 * @static
 * @since 0.1.0
 * @memberOf _
 * @category Object
 * @param {Object} object The object to query.
 * @returns {Array} Returns the array of property names.
 * @example
 *
 * function Foo() {
 *   this.a = 1;
 *   this.b = 2;
 * }
 *
 * Foo.prototype.c = 3;
 *
 * _.keys(new Foo);
 * // => ['a', 'b'] (iteration order is not guaranteed)
 *
 * _.keys('hi');
 * // => ['0', '1']
 */
function keys(object) {
  return isArrayLike(object) ? arrayLikeKeys(object) : baseKeys(object);
}

/**
 * This method returns a new empty array.
 *
 * @static
 * @memberOf _
 * @since 4.13.0
 * @category Util
 * @returns {Array} Returns the new empty array.
 * @example
 *
 * var arrays = _.times(2, _.stubArray);
 *
 * console.log(arrays);
 * // => [[], []]
 *
 * console.log(arrays[0] === arrays[1]);
 * // => false
 */
function stubArray() {
  return [];
}

/**
 * This method returns `false`.
 *
 * @static
 * @memberOf _
 * @since 4.13.0
 * @category Util
 * @returns {boolean} Returns `false`.
 * @example
 *
 * _.times(2, _.stubFalse);
 * // => [false, false]
 */
function stubFalse() {
  return false;
}

module.exports = cloneDeep;

}).call(this)}).call(this,typeof global !== "undefined" ? global : typeof self !== "undefined" ? self : typeof window !== "undefined" ? window : {})
},{}],67:[function(require,module,exports){
"use strict";

var _transactions = require("@stacks/transactions");

//hex is something like 'b244296d5907de9864c0b0d51f98a13c52890be0404e83f273144cd5b9960eed01'
function getAddressFromPrivateHex(hex) {
    const addr = (0, _transactions.getAddressFromPrivateKey)(hex);
    return [addr, addr];
}

function isAddress(addr) {
  return addr.startsWith("S") && addr.length >= 38 && addr.length <= 44;
}

function toHexString(byteArray) {
  return Array.from(byteArray, function (byte) {
    return ('0' + (byte & 0xFF).toString(16)).slice(-2);
  }).join('');
}
    
    function swiftSuccessCallback(a, b) {
        if (a == "transaction") {
            window.webkit.messageHandlers.transaction.postMessage(b);
        }
    }

    function swiftFailureCallback(e) {
     window.webkit.messageHandlers.error.postMessage(e);
    }


async function sendToken(privateKey, to, amount, memo, nonce) {
  const txOptions = {
    recipient: to,
    amount: amount,
    senderKey: privateKey,
    network: 'mainnet',
    memo: memo,
    nonce: nonce,
    // set a nonce manually if you don't want builder to fetch from a Stacks node
    fee: 5000,
    // set a tx fee if you don't want the builder to estimate
    anchorMode: _transactions.AnchorMode.Any
  };
  const transaction = await (0, _transactions.makeSTXTokenTransfer)(txOptions); // to see the raw serialized tx

  const serializedTx = transaction.serialize(); // Uint8Array

  const serializedTxHex = toHexString(serializedTx); // hex string

  console.log(serializedTxHex); // broadcasting transaction to the specified network
  swiftSuccessCallback("transaction", serializedTxHex);
    
  //const broadcastResponse = await (0, _transactions.broadcastTransaction)(transaction);
  //const txId = broadcastResponse.txid;
  //console.log(txId);
}

module.exports = {
  getAddressFromPrivateHex: getAddressFromPrivateHex,
  isAddress: isAddress,
  sendToken: sendToken
};

},{"@stacks/transactions":46}]},{},[67])(67)
});
