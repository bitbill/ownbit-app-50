var bridge = (() => {
  var __create = Object.create;
  var __defProp = Object.defineProperty;
  var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
  var __getOwnPropNames = Object.getOwnPropertyNames;
  var __getProtoOf = Object.getPrototypeOf, __hasOwnProp = Object.prototype.hasOwnProperty;
  var __esm = (fn, res, err) => function() {
    if (err) throw err[0];
    try {
      return fn && (res = (0, fn[__getOwnPropNames(fn)[0]])(fn = 0)), res;
    } catch (e) {
      throw err = [e], e;
    }
  };
  var __commonJS = (cb, mod) => function() {
    try {
      return mod || (0, cb[__getOwnPropNames(cb)[0]])((mod = { exports: {} }).exports, mod), mod.exports;
    } catch (e) {
      throw mod = 0, e;
    }
  };
  var __export = (target, all) => {
    for (var name in all)
      __defProp(target, name, { get: all[name], enumerable: !0 });
  }, __copyProps = (to, from, except, desc) => {
    if (from && typeof from == "object" || typeof from == "function")
      for (let key of __getOwnPropNames(from))
        !__hasOwnProp.call(to, key) && key !== except && __defProp(to, key, { get: () => from[key], enumerable: !(desc = __getOwnPropDesc(from, key)) || desc.enumerable });
    return to;
  };
  var __toESM = (mod, isNodeMode, target) => (target = mod != null ? __create(__getProtoOf(mod)) : {}, __copyProps(
    // If the importer is in node compatibility mode or this is not an ESM
    // file that has been converted to a CommonJS file using a Babel-
    // compatible transform (i.e. "__esModule" has not been set), then set
    // "default" to the CommonJS "module.exports" for node compatibility.
    isNodeMode || !mod || !mod.__esModule ? __defProp(target, "default", { value: mod, enumerable: !0 }) : target,
    mod
  )), __toCommonJS = (mod) => __copyProps(__defProp({}, "__esModule", { value: !0 }), mod);

  // node_modules/process/browser.js
  var require_browser = __commonJS({
    "node_modules/process/browser.js"(exports, module) {
      init_buffer_shim();
      init_process_shim();
      var process = module.exports = {}, cachedSetTimeout, cachedClearTimeout;
      function defaultSetTimout() {
        throw new Error("setTimeout has not been defined");
      }
      function defaultClearTimeout() {
        throw new Error("clearTimeout has not been defined");
      }
      (function() {
        try {
          typeof setTimeout == "function" ? cachedSetTimeout = setTimeout : cachedSetTimeout = defaultSetTimout;
        } catch {
          cachedSetTimeout = defaultSetTimout;
        }
        try {
          typeof clearTimeout == "function" ? cachedClearTimeout = clearTimeout : cachedClearTimeout = defaultClearTimeout;
        } catch {
          cachedClearTimeout = defaultClearTimeout;
        }
      })();
      function runTimeout(fun) {
        if (cachedSetTimeout === setTimeout)
          return setTimeout(fun, 0);
        if ((cachedSetTimeout === defaultSetTimout || !cachedSetTimeout) && setTimeout)
          return cachedSetTimeout = setTimeout, setTimeout(fun, 0);
        try {
          return cachedSetTimeout(fun, 0);
        } catch {
          try {
            return cachedSetTimeout.call(null, fun, 0);
          } catch {
            return cachedSetTimeout.call(this, fun, 0);
          }
        }
      }
      function runClearTimeout(marker) {
        if (cachedClearTimeout === clearTimeout)
          return clearTimeout(marker);
        if ((cachedClearTimeout === defaultClearTimeout || !cachedClearTimeout) && clearTimeout)
          return cachedClearTimeout = clearTimeout, clearTimeout(marker);
        try {
          return cachedClearTimeout(marker);
        } catch {
          try {
            return cachedClearTimeout.call(null, marker);
          } catch {
            return cachedClearTimeout.call(this, marker);
          }
        }
      }
      var queue = [], draining = !1, currentQueue, queueIndex = -1;
      function cleanUpNextTick() {
        !draining || !currentQueue || (draining = !1, currentQueue.length ? queue = currentQueue.concat(queue) : queueIndex = -1, queue.length && drainQueue());
      }
      function drainQueue() {
        if (!draining) {
          var timeout = runTimeout(cleanUpNextTick);
          draining = !0;
          for (var len = queue.length; len; ) {
            for (currentQueue = queue, queue = []; ++queueIndex < len; )
              currentQueue && currentQueue[queueIndex].run();
            queueIndex = -1, len = queue.length;
          }
          currentQueue = null, draining = !1, runClearTimeout(timeout);
        }
      }
      process.nextTick = function(fun) {
        var args = new Array(arguments.length - 1);
        if (arguments.length > 1)
          for (var i = 1; i < arguments.length; i++)
            args[i - 1] = arguments[i];
        queue.push(new Item(fun, args)), queue.length === 1 && !draining && runTimeout(drainQueue);
      };
      function Item(fun, array) {
        this.fun = fun, this.array = array;
      }
      Item.prototype.run = function() {
        this.fun.apply(null, this.array);
      };
      process.title = "browser";
      process.browser = !0;
      process.env = {};
      process.argv = [];
      process.version = "";
      process.versions = {};
      function noop() {
      }
      process.on = noop;
      process.addListener = noop;
      process.once = noop;
      process.off = noop;
      process.removeListener = noop;
      process.removeAllListeners = noop;
      process.emit = noop;
      process.prependListener = noop;
      process.prependOnceListener = noop;
      process.listeners = function(name) {
        return [];
      };
      process.binding = function(name) {
        throw new Error("process.binding is not supported");
      };
      process.cwd = function() {
        return "/";
      };
      process.chdir = function(dir) {
        throw new Error("process.chdir is not supported");
      };
      process.umask = function() {
        return 0;
      };
    }
  });

  // process-shim.js
  var import_browser, init_process_shim = __esm({
    "process-shim.js"() {
      import_browser = __toESM(require_browser());
    }
  });

  // node_modules/base64-js/index.js
  var require_base64_js = __commonJS({
    "node_modules/base64-js/index.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      exports.byteLength = byteLength;
      exports.toByteArray = toByteArray;
      exports.fromByteArray = fromByteArray;
      var lookup = [], revLookup = [], Arr = typeof Uint8Array < "u" ? Uint8Array : Array, code = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
      for (i = 0, len = code.length; i < len; ++i)
        lookup[i] = code[i], revLookup[code.charCodeAt(i)] = i;
      var i, len;
      revLookup[45] = 62;
      revLookup[95] = 63;
      function getLens(b64) {
        var len2 = b64.length;
        if (len2 % 4 > 0)
          throw new Error("Invalid string. Length must be a multiple of 4");
        var validLen = b64.indexOf("=");
        validLen === -1 && (validLen = len2);
        var placeHoldersLen = validLen === len2 ? 0 : 4 - validLen % 4;
        return [validLen, placeHoldersLen];
      }
      function byteLength(b64) {
        var lens = getLens(b64), validLen = lens[0], placeHoldersLen = lens[1];
        return (validLen + placeHoldersLen) * 3 / 4 - placeHoldersLen;
      }
      function _byteLength(b64, validLen, placeHoldersLen) {
        return (validLen + placeHoldersLen) * 3 / 4 - placeHoldersLen;
      }
      function toByteArray(b64) {
        var tmp, lens = getLens(b64), validLen = lens[0], placeHoldersLen = lens[1], arr = new Arr(_byteLength(b64, validLen, placeHoldersLen)), curByte = 0, len2 = placeHoldersLen > 0 ? validLen - 4 : validLen, i2;
        for (i2 = 0; i2 < len2; i2 += 4)
          tmp = revLookup[b64.charCodeAt(i2)] << 18 | revLookup[b64.charCodeAt(i2 + 1)] << 12 | revLookup[b64.charCodeAt(i2 + 2)] << 6 | revLookup[b64.charCodeAt(i2 + 3)], arr[curByte++] = tmp >> 16 & 255, arr[curByte++] = tmp >> 8 & 255, arr[curByte++] = tmp & 255;
        return placeHoldersLen === 2 && (tmp = revLookup[b64.charCodeAt(i2)] << 2 | revLookup[b64.charCodeAt(i2 + 1)] >> 4, arr[curByte++] = tmp & 255), placeHoldersLen === 1 && (tmp = revLookup[b64.charCodeAt(i2)] << 10 | revLookup[b64.charCodeAt(i2 + 1)] << 4 | revLookup[b64.charCodeAt(i2 + 2)] >> 2, arr[curByte++] = tmp >> 8 & 255, arr[curByte++] = tmp & 255), arr;
      }
      function tripletToBase64(num) {
        return lookup[num >> 18 & 63] + lookup[num >> 12 & 63] + lookup[num >> 6 & 63] + lookup[num & 63];
      }
      function encodeChunk(uint8, start, end) {
        for (var tmp, output = [], i2 = start; i2 < end; i2 += 3)
          tmp = (uint8[i2] << 16 & 16711680) + (uint8[i2 + 1] << 8 & 65280) + (uint8[i2 + 2] & 255), output.push(tripletToBase64(tmp));
        return output.join("");
      }
      function fromByteArray(uint8) {
        for (var tmp, len2 = uint8.length, extraBytes = len2 % 3, parts = [], maxChunkLength = 16383, i2 = 0, len22 = len2 - extraBytes; i2 < len22; i2 += maxChunkLength)
          parts.push(encodeChunk(uint8, i2, i2 + maxChunkLength > len22 ? len22 : i2 + maxChunkLength));
        return extraBytes === 1 ? (tmp = uint8[len2 - 1], parts.push(
          lookup[tmp >> 2] + lookup[tmp << 4 & 63] + "=="
        )) : extraBytes === 2 && (tmp = (uint8[len2 - 2] << 8) + uint8[len2 - 1], parts.push(
          lookup[tmp >> 10] + lookup[tmp >> 4 & 63] + lookup[tmp << 2 & 63] + "="
        )), parts.join("");
      }
    }
  });

  // node_modules/ieee754/index.js
  var require_ieee754 = __commonJS({
    "node_modules/ieee754/index.js"(exports) {
      init_buffer_shim();
      init_process_shim();
      exports.read = function(buffer, offset, isLE, mLen, nBytes) {
        var e, m, eLen = nBytes * 8 - mLen - 1, eMax = (1 << eLen) - 1, eBias = eMax >> 1, nBits = -7, i = isLE ? nBytes - 1 : 0, d = isLE ? -1 : 1, s = buffer[offset + i];
        for (i += d, e = s & (1 << -nBits) - 1, s >>= -nBits, nBits += eLen; nBits > 0; e = e * 256 + buffer[offset + i], i += d, nBits -= 8)
          ;
        for (m = e & (1 << -nBits) - 1, e >>= -nBits, nBits += mLen; nBits > 0; m = m * 256 + buffer[offset + i], i += d, nBits -= 8)
          ;
        if (e === 0)
          e = 1 - eBias;
        else {
          if (e === eMax)
            return m ? NaN : (s ? -1 : 1) * (1 / 0);
          m = m + Math.pow(2, mLen), e = e - eBias;
        }
        return (s ? -1 : 1) * m * Math.pow(2, e - mLen);
      };
      exports.write = function(buffer, value, offset, isLE, mLen, nBytes) {
        var e, m, c, eLen = nBytes * 8 - mLen - 1, eMax = (1 << eLen) - 1, eBias = eMax >> 1, rt = mLen === 23 ? Math.pow(2, -24) - Math.pow(2, -77) : 0, i = isLE ? 0 : nBytes - 1, d = isLE ? 1 : -1, s = value < 0 || value === 0 && 1 / value < 0 ? 1 : 0;
        for (value = Math.abs(value), isNaN(value) || value === 1 / 0 ? (m = isNaN(value) ? 1 : 0, e = eMax) : (e = Math.floor(Math.log(value) / Math.LN2), value * (c = Math.pow(2, -e)) < 1 && (e--, c *= 2), e + eBias >= 1 ? value += rt / c : value += rt * Math.pow(2, 1 - eBias), value * c >= 2 && (e++, c /= 2), e + eBias >= eMax ? (m = 0, e = eMax) : e + eBias >= 1 ? (m = (value * c - 1) * Math.pow(2, mLen), e = e + eBias) : (m = value * Math.pow(2, eBias - 1) * Math.pow(2, mLen), e = 0)); mLen >= 8; buffer[offset + i] = m & 255, i += d, m /= 256, mLen -= 8)
          ;
        for (e = e << mLen | m, eLen += mLen; eLen > 0; buffer[offset + i] = e & 255, i += d, e /= 256, eLen -= 8)
          ;
        buffer[offset + i - d] |= s * 128;
      };
    }
  });

  // node_modules/buffer/index.js
  var require_buffer = __commonJS({
    "node_modules/buffer/index.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      var base64 = require_base64_js(), ieee754 = require_ieee754(), customInspectSymbol = typeof Symbol == "function" && typeof Symbol.for == "function" ? /* @__PURE__ */ Symbol.for("nodejs.util.inspect.custom") : null;
      exports.Buffer = Buffer4;
      exports.SlowBuffer = SlowBuffer;
      exports.INSPECT_MAX_BYTES = 50;
      var K_MAX_LENGTH = 2147483647;
      exports.kMaxLength = K_MAX_LENGTH;
      Buffer4.TYPED_ARRAY_SUPPORT = typedArraySupport();
      !Buffer4.TYPED_ARRAY_SUPPORT && typeof console < "u" && typeof console.error == "function" && console.error(
        "This browser lacks typed array (Uint8Array) support which is required by `buffer` v5.x. Use `buffer` v4.x if you require old browser support."
      );
      function typedArraySupport() {
        try {
          let arr = new Uint8Array(1), proto = { foo: function() {
            return 42;
          } };
          return Object.setPrototypeOf(proto, Uint8Array.prototype), Object.setPrototypeOf(arr, proto), arr.foo() === 42;
        } catch {
          return !1;
        }
      }
      Object.defineProperty(Buffer4.prototype, "parent", {
        enumerable: !0,
        get: function() {
          if (Buffer4.isBuffer(this))
            return this.buffer;
        }
      });
      Object.defineProperty(Buffer4.prototype, "offset", {
        enumerable: !0,
        get: function() {
          if (Buffer4.isBuffer(this))
            return this.byteOffset;
        }
      });
      function createBuffer(length) {
        if (length > K_MAX_LENGTH)
          throw new RangeError('The value "' + length + '" is invalid for option "size"');
        let buf = new Uint8Array(length);
        return Object.setPrototypeOf(buf, Buffer4.prototype), buf;
      }
      function Buffer4(arg, encodingOrOffset, length) {
        if (typeof arg == "number") {
          if (typeof encodingOrOffset == "string")
            throw new TypeError(
              'The "string" argument must be of type string. Received type number'
            );
          return allocUnsafe(arg);
        }
        return from(arg, encodingOrOffset, length);
      }
      Buffer4.poolSize = 8192;
      function from(value, encodingOrOffset, length) {
        if (typeof value == "string")
          return fromString(value, encodingOrOffset);
        if (ArrayBuffer.isView(value))
          return fromArrayView(value);
        if (value == null)
          throw new TypeError(
            "The first argument must be one of type string, Buffer, ArrayBuffer, Array, or Array-like Object. Received type " + typeof value
          );
        if (isInstance(value, ArrayBuffer) || value && isInstance(value.buffer, ArrayBuffer) || typeof SharedArrayBuffer < "u" && (isInstance(value, SharedArrayBuffer) || value && isInstance(value.buffer, SharedArrayBuffer)))
          return fromArrayBuffer(value, encodingOrOffset, length);
        if (typeof value == "number")
          throw new TypeError(
            'The "value" argument must not be of type number. Received type number'
          );
        let valueOf = value.valueOf && value.valueOf();
        if (valueOf != null && valueOf !== value)
          return Buffer4.from(valueOf, encodingOrOffset, length);
        let b = fromObject(value);
        if (b) return b;
        if (typeof Symbol < "u" && Symbol.toPrimitive != null && typeof value[Symbol.toPrimitive] == "function")
          return Buffer4.from(value[Symbol.toPrimitive]("string"), encodingOrOffset, length);
        throw new TypeError(
          "The first argument must be one of type string, Buffer, ArrayBuffer, Array, or Array-like Object. Received type " + typeof value
        );
      }
      Buffer4.from = function(value, encodingOrOffset, length) {
        return from(value, encodingOrOffset, length);
      };
      Object.setPrototypeOf(Buffer4.prototype, Uint8Array.prototype);
      Object.setPrototypeOf(Buffer4, Uint8Array);
      function assertSize(size) {
        if (typeof size != "number")
          throw new TypeError('"size" argument must be of type number');
        if (size < 0)
          throw new RangeError('The value "' + size + '" is invalid for option "size"');
      }
      function alloc(size, fill, encoding) {
        return assertSize(size), size <= 0 ? createBuffer(size) : fill !== void 0 ? typeof encoding == "string" ? createBuffer(size).fill(fill, encoding) : createBuffer(size).fill(fill) : createBuffer(size);
      }
      Buffer4.alloc = function(size, fill, encoding) {
        return alloc(size, fill, encoding);
      };
      function allocUnsafe(size) {
        return assertSize(size), createBuffer(size < 0 ? 0 : checked(size) | 0);
      }
      Buffer4.allocUnsafe = function(size) {
        return allocUnsafe(size);
      };
      Buffer4.allocUnsafeSlow = function(size) {
        return allocUnsafe(size);
      };
      function fromString(string, encoding) {
        if ((typeof encoding != "string" || encoding === "") && (encoding = "utf8"), !Buffer4.isEncoding(encoding))
          throw new TypeError("Unknown encoding: " + encoding);
        let length = byteLength(string, encoding) | 0, buf = createBuffer(length), actual = buf.write(string, encoding);
        return actual !== length && (buf = buf.slice(0, actual)), buf;
      }
      function fromArrayLike(array) {
        let length = array.length < 0 ? 0 : checked(array.length) | 0, buf = createBuffer(length);
        for (let i = 0; i < length; i += 1)
          buf[i] = array[i] & 255;
        return buf;
      }
      function fromArrayView(arrayView) {
        if (isInstance(arrayView, Uint8Array)) {
          let copy = new Uint8Array(arrayView);
          return fromArrayBuffer(copy.buffer, copy.byteOffset, copy.byteLength);
        }
        return fromArrayLike(arrayView);
      }
      function fromArrayBuffer(array, byteOffset, length) {
        if (byteOffset < 0 || array.byteLength < byteOffset)
          throw new RangeError('"offset" is outside of buffer bounds');
        if (array.byteLength < byteOffset + (length || 0))
          throw new RangeError('"length" is outside of buffer bounds');
        let buf;
        return byteOffset === void 0 && length === void 0 ? buf = new Uint8Array(array) : length === void 0 ? buf = new Uint8Array(array, byteOffset) : buf = new Uint8Array(array, byteOffset, length), Object.setPrototypeOf(buf, Buffer4.prototype), buf;
      }
      function fromObject(obj) {
        if (Buffer4.isBuffer(obj)) {
          let len = checked(obj.length) | 0, buf = createBuffer(len);
          return buf.length === 0 || obj.copy(buf, 0, 0, len), buf;
        }
        if (obj.length !== void 0)
          return typeof obj.length != "number" || numberIsNaN(obj.length) ? createBuffer(0) : fromArrayLike(obj);
        if (obj.type === "Buffer" && Array.isArray(obj.data))
          return fromArrayLike(obj.data);
      }
      function checked(length) {
        if (length >= K_MAX_LENGTH)
          throw new RangeError("Attempt to allocate Buffer larger than maximum size: 0x" + K_MAX_LENGTH.toString(16) + " bytes");
        return length | 0;
      }
      function SlowBuffer(length) {
        return +length != length && (length = 0), Buffer4.alloc(+length);
      }
      Buffer4.isBuffer = function(b) {
        return b != null && b._isBuffer === !0 && b !== Buffer4.prototype;
      };
      Buffer4.compare = function(a, b) {
        if (isInstance(a, Uint8Array) && (a = Buffer4.from(a, a.offset, a.byteLength)), isInstance(b, Uint8Array) && (b = Buffer4.from(b, b.offset, b.byteLength)), !Buffer4.isBuffer(a) || !Buffer4.isBuffer(b))
          throw new TypeError(
            'The "buf1", "buf2" arguments must be one of type Buffer or Uint8Array'
          );
        if (a === b) return 0;
        let x = a.length, y = b.length;
        for (let i = 0, len = Math.min(x, y); i < len; ++i)
          if (a[i] !== b[i]) {
            x = a[i], y = b[i];
            break;
          }
        return x < y ? -1 : y < x ? 1 : 0;
      };
      Buffer4.isEncoding = function(encoding) {
        switch (String(encoding).toLowerCase()) {
          case "hex":
          case "utf8":
          case "utf-8":
          case "ascii":
          case "latin1":
          case "binary":
          case "base64":
          case "ucs2":
          case "ucs-2":
          case "utf16le":
          case "utf-16le":
            return !0;
          default:
            return !1;
        }
      };
      Buffer4.concat = function(list, length) {
        if (!Array.isArray(list))
          throw new TypeError('"list" argument must be an Array of Buffers');
        if (list.length === 0)
          return Buffer4.alloc(0);
        let i;
        if (length === void 0)
          for (length = 0, i = 0; i < list.length; ++i)
            length += list[i].length;
        let buffer = Buffer4.allocUnsafe(length), pos = 0;
        for (i = 0; i < list.length; ++i) {
          let buf = list[i];
          if (isInstance(buf, Uint8Array))
            pos + buf.length > buffer.length ? (Buffer4.isBuffer(buf) || (buf = Buffer4.from(buf)), buf.copy(buffer, pos)) : Uint8Array.prototype.set.call(
              buffer,
              buf,
              pos
            );
          else if (Buffer4.isBuffer(buf))
            buf.copy(buffer, pos);
          else
            throw new TypeError('"list" argument must be an Array of Buffers');
          pos += buf.length;
        }
        return buffer;
      };
      function byteLength(string, encoding) {
        if (Buffer4.isBuffer(string))
          return string.length;
        if (ArrayBuffer.isView(string) || isInstance(string, ArrayBuffer))
          return string.byteLength;
        if (typeof string != "string")
          throw new TypeError(
            'The "string" argument must be one of type string, Buffer, or ArrayBuffer. Received type ' + typeof string
          );
        let len = string.length, mustMatch = arguments.length > 2 && arguments[2] === !0;
        if (!mustMatch && len === 0) return 0;
        let loweredCase = !1;
        for (; ; )
          switch (encoding) {
            case "ascii":
            case "latin1":
            case "binary":
              return len;
            case "utf8":
            case "utf-8":
              return utf8ToBytes(string).length;
            case "ucs2":
            case "ucs-2":
            case "utf16le":
            case "utf-16le":
              return len * 2;
            case "hex":
              return len >>> 1;
            case "base64":
              return base64ToBytes(string).length;
            default:
              if (loweredCase)
                return mustMatch ? -1 : utf8ToBytes(string).length;
              encoding = ("" + encoding).toLowerCase(), loweredCase = !0;
          }
      }
      Buffer4.byteLength = byteLength;
      function slowToString(encoding, start, end) {
        let loweredCase = !1;
        if ((start === void 0 || start < 0) && (start = 0), start > this.length || ((end === void 0 || end > this.length) && (end = this.length), end <= 0) || (end >>>= 0, start >>>= 0, end <= start))
          return "";
        for (encoding || (encoding = "utf8"); ; )
          switch (encoding) {
            case "hex":
              return hexSlice(this, start, end);
            case "utf8":
            case "utf-8":
              return utf8Slice(this, start, end);
            case "ascii":
              return asciiSlice(this, start, end);
            case "latin1":
            case "binary":
              return latin1Slice(this, start, end);
            case "base64":
              return base64Slice(this, start, end);
            case "ucs2":
            case "ucs-2":
            case "utf16le":
            case "utf-16le":
              return utf16leSlice(this, start, end);
            default:
              if (loweredCase) throw new TypeError("Unknown encoding: " + encoding);
              encoding = (encoding + "").toLowerCase(), loweredCase = !0;
          }
      }
      Buffer4.prototype._isBuffer = !0;
      function swap(b, n, m) {
        let i = b[n];
        b[n] = b[m], b[m] = i;
      }
      Buffer4.prototype.swap16 = function() {
        let len = this.length;
        if (len % 2 !== 0)
          throw new RangeError("Buffer size must be a multiple of 16-bits");
        for (let i = 0; i < len; i += 2)
          swap(this, i, i + 1);
        return this;
      };
      Buffer4.prototype.swap32 = function() {
        let len = this.length;
        if (len % 4 !== 0)
          throw new RangeError("Buffer size must be a multiple of 32-bits");
        for (let i = 0; i < len; i += 4)
          swap(this, i, i + 3), swap(this, i + 1, i + 2);
        return this;
      };
      Buffer4.prototype.swap64 = function() {
        let len = this.length;
        if (len % 8 !== 0)
          throw new RangeError("Buffer size must be a multiple of 64-bits");
        for (let i = 0; i < len; i += 8)
          swap(this, i, i + 7), swap(this, i + 1, i + 6), swap(this, i + 2, i + 5), swap(this, i + 3, i + 4);
        return this;
      };
      Buffer4.prototype.toString = function() {
        let length = this.length;
        return length === 0 ? "" : arguments.length === 0 ? utf8Slice(this, 0, length) : slowToString.apply(this, arguments);
      };
      Buffer4.prototype.toLocaleString = Buffer4.prototype.toString;
      Buffer4.prototype.equals = function(b) {
        if (!Buffer4.isBuffer(b)) throw new TypeError("Argument must be a Buffer");
        return this === b ? !0 : Buffer4.compare(this, b) === 0;
      };
      Buffer4.prototype.inspect = function() {
        let str = "", max = exports.INSPECT_MAX_BYTES;
        return str = this.toString("hex", 0, max).replace(/(.{2})/g, "$1 ").trim(), this.length > max && (str += " ... "), "<Buffer " + str + ">";
      };
      customInspectSymbol && (Buffer4.prototype[customInspectSymbol] = Buffer4.prototype.inspect);
      Buffer4.prototype.compare = function(target, start, end, thisStart, thisEnd) {
        if (isInstance(target, Uint8Array) && (target = Buffer4.from(target, target.offset, target.byteLength)), !Buffer4.isBuffer(target))
          throw new TypeError(
            'The "target" argument must be one of type Buffer or Uint8Array. Received type ' + typeof target
          );
        if (start === void 0 && (start = 0), end === void 0 && (end = target ? target.length : 0), thisStart === void 0 && (thisStart = 0), thisEnd === void 0 && (thisEnd = this.length), start < 0 || end > target.length || thisStart < 0 || thisEnd > this.length)
          throw new RangeError("out of range index");
        if (thisStart >= thisEnd && start >= end)
          return 0;
        if (thisStart >= thisEnd)
          return -1;
        if (start >= end)
          return 1;
        if (start >>>= 0, end >>>= 0, thisStart >>>= 0, thisEnd >>>= 0, this === target) return 0;
        let x = thisEnd - thisStart, y = end - start, len = Math.min(x, y), thisCopy = this.slice(thisStart, thisEnd), targetCopy = target.slice(start, end);
        for (let i = 0; i < len; ++i)
          if (thisCopy[i] !== targetCopy[i]) {
            x = thisCopy[i], y = targetCopy[i];
            break;
          }
        return x < y ? -1 : y < x ? 1 : 0;
      };
      function bidirectionalIndexOf(buffer, val, byteOffset, encoding, dir) {
        if (buffer.length === 0) return -1;
        if (typeof byteOffset == "string" ? (encoding = byteOffset, byteOffset = 0) : byteOffset > 2147483647 ? byteOffset = 2147483647 : byteOffset < -2147483648 && (byteOffset = -2147483648), byteOffset = +byteOffset, numberIsNaN(byteOffset) && (byteOffset = dir ? 0 : buffer.length - 1), byteOffset < 0 && (byteOffset = buffer.length + byteOffset), byteOffset >= buffer.length) {
          if (dir) return -1;
          byteOffset = buffer.length - 1;
        } else if (byteOffset < 0)
          if (dir) byteOffset = 0;
          else return -1;
        if (typeof val == "string" && (val = Buffer4.from(val, encoding)), Buffer4.isBuffer(val))
          return val.length === 0 ? -1 : arrayIndexOf(buffer, val, byteOffset, encoding, dir);
        if (typeof val == "number")
          return val = val & 255, typeof Uint8Array.prototype.indexOf == "function" ? dir ? Uint8Array.prototype.indexOf.call(buffer, val, byteOffset) : Uint8Array.prototype.lastIndexOf.call(buffer, val, byteOffset) : arrayIndexOf(buffer, [val], byteOffset, encoding, dir);
        throw new TypeError("val must be string, number or Buffer");
      }
      function arrayIndexOf(arr, val, byteOffset, encoding, dir) {
        let indexSize = 1, arrLength = arr.length, valLength = val.length;
        if (encoding !== void 0 && (encoding = String(encoding).toLowerCase(), encoding === "ucs2" || encoding === "ucs-2" || encoding === "utf16le" || encoding === "utf-16le")) {
          if (arr.length < 2 || val.length < 2)
            return -1;
          indexSize = 2, arrLength /= 2, valLength /= 2, byteOffset /= 2;
        }
        function read(buf, i2) {
          return indexSize === 1 ? buf[i2] : buf.readUInt16BE(i2 * indexSize);
        }
        let i;
        if (dir) {
          let foundIndex = -1;
          for (i = byteOffset; i < arrLength; i++)
            if (read(arr, i) === read(val, foundIndex === -1 ? 0 : i - foundIndex)) {
              if (foundIndex === -1 && (foundIndex = i), i - foundIndex + 1 === valLength) return foundIndex * indexSize;
            } else
              foundIndex !== -1 && (i -= i - foundIndex), foundIndex = -1;
        } else
          for (byteOffset + valLength > arrLength && (byteOffset = arrLength - valLength), i = byteOffset; i >= 0; i--) {
            let found = !0;
            for (let j = 0; j < valLength; j++)
              if (read(arr, i + j) !== read(val, j)) {
                found = !1;
                break;
              }
            if (found) return i;
          }
        return -1;
      }
      Buffer4.prototype.includes = function(val, byteOffset, encoding) {
        return this.indexOf(val, byteOffset, encoding) !== -1;
      };
      Buffer4.prototype.indexOf = function(val, byteOffset, encoding) {
        return bidirectionalIndexOf(this, val, byteOffset, encoding, !0);
      };
      Buffer4.prototype.lastIndexOf = function(val, byteOffset, encoding) {
        return bidirectionalIndexOf(this, val, byteOffset, encoding, !1);
      };
      function hexWrite(buf, string, offset, length) {
        offset = Number(offset) || 0;
        let remaining = buf.length - offset;
        length ? (length = Number(length), length > remaining && (length = remaining)) : length = remaining;
        let strLen = string.length;
        length > strLen / 2 && (length = strLen / 2);
        let i;
        for (i = 0; i < length; ++i) {
          let parsed = parseInt(string.substr(i * 2, 2), 16);
          if (numberIsNaN(parsed)) return i;
          buf[offset + i] = parsed;
        }
        return i;
      }
      function utf8Write(buf, string, offset, length) {
        return blitBuffer(utf8ToBytes(string, buf.length - offset), buf, offset, length);
      }
      function asciiWrite(buf, string, offset, length) {
        return blitBuffer(asciiToBytes(string), buf, offset, length);
      }
      function base64Write(buf, string, offset, length) {
        return blitBuffer(base64ToBytes(string), buf, offset, length);
      }
      function ucs2Write(buf, string, offset, length) {
        return blitBuffer(utf16leToBytes(string, buf.length - offset), buf, offset, length);
      }
      Buffer4.prototype.write = function(string, offset, length, encoding) {
        if (offset === void 0)
          encoding = "utf8", length = this.length, offset = 0;
        else if (length === void 0 && typeof offset == "string")
          encoding = offset, length = this.length, offset = 0;
        else if (isFinite(offset))
          offset = offset >>> 0, isFinite(length) ? (length = length >>> 0, encoding === void 0 && (encoding = "utf8")) : (encoding = length, length = void 0);
        else
          throw new Error(
            "Buffer.write(string, encoding, offset[, length]) is no longer supported"
          );
        let remaining = this.length - offset;
        if ((length === void 0 || length > remaining) && (length = remaining), string.length > 0 && (length < 0 || offset < 0) || offset > this.length)
          throw new RangeError("Attempt to write outside buffer bounds");
        encoding || (encoding = "utf8");
        let loweredCase = !1;
        for (; ; )
          switch (encoding) {
            case "hex":
              return hexWrite(this, string, offset, length);
            case "utf8":
            case "utf-8":
              return utf8Write(this, string, offset, length);
            case "ascii":
            case "latin1":
            case "binary":
              return asciiWrite(this, string, offset, length);
            case "base64":
              return base64Write(this, string, offset, length);
            case "ucs2":
            case "ucs-2":
            case "utf16le":
            case "utf-16le":
              return ucs2Write(this, string, offset, length);
            default:
              if (loweredCase) throw new TypeError("Unknown encoding: " + encoding);
              encoding = ("" + encoding).toLowerCase(), loweredCase = !0;
          }
      };
      Buffer4.prototype.toJSON = function() {
        return {
          type: "Buffer",
          data: Array.prototype.slice.call(this._arr || this, 0)
        };
      };
      function base64Slice(buf, start, end) {
        return start === 0 && end === buf.length ? base64.fromByteArray(buf) : base64.fromByteArray(buf.slice(start, end));
      }
      function utf8Slice(buf, start, end) {
        end = Math.min(buf.length, end);
        let res = [], i = start;
        for (; i < end; ) {
          let firstByte = buf[i], codePoint = null, bytesPerSequence = firstByte > 239 ? 4 : firstByte > 223 ? 3 : firstByte > 191 ? 2 : 1;
          if (i + bytesPerSequence <= end) {
            let secondByte, thirdByte, fourthByte, tempCodePoint;
            switch (bytesPerSequence) {
              case 1:
                firstByte < 128 && (codePoint = firstByte);
                break;
              case 2:
                secondByte = buf[i + 1], (secondByte & 192) === 128 && (tempCodePoint = (firstByte & 31) << 6 | secondByte & 63, tempCodePoint > 127 && (codePoint = tempCodePoint));
                break;
              case 3:
                secondByte = buf[i + 1], thirdByte = buf[i + 2], (secondByte & 192) === 128 && (thirdByte & 192) === 128 && (tempCodePoint = (firstByte & 15) << 12 | (secondByte & 63) << 6 | thirdByte & 63, tempCodePoint > 2047 && (tempCodePoint < 55296 || tempCodePoint > 57343) && (codePoint = tempCodePoint));
                break;
              case 4:
                secondByte = buf[i + 1], thirdByte = buf[i + 2], fourthByte = buf[i + 3], (secondByte & 192) === 128 && (thirdByte & 192) === 128 && (fourthByte & 192) === 128 && (tempCodePoint = (firstByte & 15) << 18 | (secondByte & 63) << 12 | (thirdByte & 63) << 6 | fourthByte & 63, tempCodePoint > 65535 && tempCodePoint < 1114112 && (codePoint = tempCodePoint));
            }
          }
          codePoint === null ? (codePoint = 65533, bytesPerSequence = 1) : codePoint > 65535 && (codePoint -= 65536, res.push(codePoint >>> 10 & 1023 | 55296), codePoint = 56320 | codePoint & 1023), res.push(codePoint), i += bytesPerSequence;
        }
        return decodeCodePointsArray(res);
      }
      var MAX_ARGUMENTS_LENGTH = 4096;
      function decodeCodePointsArray(codePoints) {
        let len = codePoints.length;
        if (len <= MAX_ARGUMENTS_LENGTH)
          return String.fromCharCode.apply(String, codePoints);
        let res = "", i = 0;
        for (; i < len; )
          res += String.fromCharCode.apply(
            String,
            codePoints.slice(i, i += MAX_ARGUMENTS_LENGTH)
          );
        return res;
      }
      function asciiSlice(buf, start, end) {
        let ret = "";
        end = Math.min(buf.length, end);
        for (let i = start; i < end; ++i)
          ret += String.fromCharCode(buf[i] & 127);
        return ret;
      }
      function latin1Slice(buf, start, end) {
        let ret = "";
        end = Math.min(buf.length, end);
        for (let i = start; i < end; ++i)
          ret += String.fromCharCode(buf[i]);
        return ret;
      }
      function hexSlice(buf, start, end) {
        let len = buf.length;
        (!start || start < 0) && (start = 0), (!end || end < 0 || end > len) && (end = len);
        let out = "";
        for (let i = start; i < end; ++i)
          out += hexSliceLookupTable[buf[i]];
        return out;
      }
      function utf16leSlice(buf, start, end) {
        let bytes = buf.slice(start, end), res = "";
        for (let i = 0; i < bytes.length - 1; i += 2)
          res += String.fromCharCode(bytes[i] + bytes[i + 1] * 256);
        return res;
      }
      Buffer4.prototype.slice = function(start, end) {
        let len = this.length;
        start = ~~start, end = end === void 0 ? len : ~~end, start < 0 ? (start += len, start < 0 && (start = 0)) : start > len && (start = len), end < 0 ? (end += len, end < 0 && (end = 0)) : end > len && (end = len), end < start && (end = start);
        let newBuf = this.subarray(start, end);
        return Object.setPrototypeOf(newBuf, Buffer4.prototype), newBuf;
      };
      function checkOffset(offset, ext, length) {
        if (offset % 1 !== 0 || offset < 0) throw new RangeError("offset is not uint");
        if (offset + ext > length) throw new RangeError("Trying to access beyond buffer length");
      }
      Buffer4.prototype.readUintLE = Buffer4.prototype.readUIntLE = function(offset, byteLength2, noAssert) {
        offset = offset >>> 0, byteLength2 = byteLength2 >>> 0, noAssert || checkOffset(offset, byteLength2, this.length);
        let val = this[offset], mul = 1, i = 0;
        for (; ++i < byteLength2 && (mul *= 256); )
          val += this[offset + i] * mul;
        return val;
      };
      Buffer4.prototype.readUintBE = Buffer4.prototype.readUIntBE = function(offset, byteLength2, noAssert) {
        offset = offset >>> 0, byteLength2 = byteLength2 >>> 0, noAssert || checkOffset(offset, byteLength2, this.length);
        let val = this[offset + --byteLength2], mul = 1;
        for (; byteLength2 > 0 && (mul *= 256); )
          val += this[offset + --byteLength2] * mul;
        return val;
      };
      Buffer4.prototype.readUint8 = Buffer4.prototype.readUInt8 = function(offset, noAssert) {
        return offset = offset >>> 0, noAssert || checkOffset(offset, 1, this.length), this[offset];
      };
      Buffer4.prototype.readUint16LE = Buffer4.prototype.readUInt16LE = function(offset, noAssert) {
        return offset = offset >>> 0, noAssert || checkOffset(offset, 2, this.length), this[offset] | this[offset + 1] << 8;
      };
      Buffer4.prototype.readUint16BE = Buffer4.prototype.readUInt16BE = function(offset, noAssert) {
        return offset = offset >>> 0, noAssert || checkOffset(offset, 2, this.length), this[offset] << 8 | this[offset + 1];
      };
      Buffer4.prototype.readUint32LE = Buffer4.prototype.readUInt32LE = function(offset, noAssert) {
        return offset = offset >>> 0, noAssert || checkOffset(offset, 4, this.length), (this[offset] | this[offset + 1] << 8 | this[offset + 2] << 16) + this[offset + 3] * 16777216;
      };
      Buffer4.prototype.readUint32BE = Buffer4.prototype.readUInt32BE = function(offset, noAssert) {
        return offset = offset >>> 0, noAssert || checkOffset(offset, 4, this.length), this[offset] * 16777216 + (this[offset + 1] << 16 | this[offset + 2] << 8 | this[offset + 3]);
      };
      Buffer4.prototype.readBigUInt64LE = defineBigIntMethod(function(offset) {
        offset = offset >>> 0, validateNumber(offset, "offset");
        let first = this[offset], last = this[offset + 7];
        (first === void 0 || last === void 0) && boundsError(offset, this.length - 8);
        let lo = first + this[++offset] * 2 ** 8 + this[++offset] * 2 ** 16 + this[++offset] * 2 ** 24, hi = this[++offset] + this[++offset] * 2 ** 8 + this[++offset] * 2 ** 16 + last * 2 ** 24;
        return BigInt(lo) + (BigInt(hi) << BigInt(32));
      });
      Buffer4.prototype.readBigUInt64BE = defineBigIntMethod(function(offset) {
        offset = offset >>> 0, validateNumber(offset, "offset");
        let first = this[offset], last = this[offset + 7];
        (first === void 0 || last === void 0) && boundsError(offset, this.length - 8);
        let hi = first * 2 ** 24 + this[++offset] * 2 ** 16 + this[++offset] * 2 ** 8 + this[++offset], lo = this[++offset] * 2 ** 24 + this[++offset] * 2 ** 16 + this[++offset] * 2 ** 8 + last;
        return (BigInt(hi) << BigInt(32)) + BigInt(lo);
      });
      Buffer4.prototype.readIntLE = function(offset, byteLength2, noAssert) {
        offset = offset >>> 0, byteLength2 = byteLength2 >>> 0, noAssert || checkOffset(offset, byteLength2, this.length);
        let val = this[offset], mul = 1, i = 0;
        for (; ++i < byteLength2 && (mul *= 256); )
          val += this[offset + i] * mul;
        return mul *= 128, val >= mul && (val -= Math.pow(2, 8 * byteLength2)), val;
      };
      Buffer4.prototype.readIntBE = function(offset, byteLength2, noAssert) {
        offset = offset >>> 0, byteLength2 = byteLength2 >>> 0, noAssert || checkOffset(offset, byteLength2, this.length);
        let i = byteLength2, mul = 1, val = this[offset + --i];
        for (; i > 0 && (mul *= 256); )
          val += this[offset + --i] * mul;
        return mul *= 128, val >= mul && (val -= Math.pow(2, 8 * byteLength2)), val;
      };
      Buffer4.prototype.readInt8 = function(offset, noAssert) {
        return offset = offset >>> 0, noAssert || checkOffset(offset, 1, this.length), this[offset] & 128 ? (255 - this[offset] + 1) * -1 : this[offset];
      };
      Buffer4.prototype.readInt16LE = function(offset, noAssert) {
        offset = offset >>> 0, noAssert || checkOffset(offset, 2, this.length);
        let val = this[offset] | this[offset + 1] << 8;
        return val & 32768 ? val | 4294901760 : val;
      };
      Buffer4.prototype.readInt16BE = function(offset, noAssert) {
        offset = offset >>> 0, noAssert || checkOffset(offset, 2, this.length);
        let val = this[offset + 1] | this[offset] << 8;
        return val & 32768 ? val | 4294901760 : val;
      };
      Buffer4.prototype.readInt32LE = function(offset, noAssert) {
        return offset = offset >>> 0, noAssert || checkOffset(offset, 4, this.length), this[offset] | this[offset + 1] << 8 | this[offset + 2] << 16 | this[offset + 3] << 24;
      };
      Buffer4.prototype.readInt32BE = function(offset, noAssert) {
        return offset = offset >>> 0, noAssert || checkOffset(offset, 4, this.length), this[offset] << 24 | this[offset + 1] << 16 | this[offset + 2] << 8 | this[offset + 3];
      };
      Buffer4.prototype.readBigInt64LE = defineBigIntMethod(function(offset) {
        offset = offset >>> 0, validateNumber(offset, "offset");
        let first = this[offset], last = this[offset + 7];
        (first === void 0 || last === void 0) && boundsError(offset, this.length - 8);
        let val = this[offset + 4] + this[offset + 5] * 2 ** 8 + this[offset + 6] * 2 ** 16 + (last << 24);
        return (BigInt(val) << BigInt(32)) + BigInt(first + this[++offset] * 2 ** 8 + this[++offset] * 2 ** 16 + this[++offset] * 2 ** 24);
      });
      Buffer4.prototype.readBigInt64BE = defineBigIntMethod(function(offset) {
        offset = offset >>> 0, validateNumber(offset, "offset");
        let first = this[offset], last = this[offset + 7];
        (first === void 0 || last === void 0) && boundsError(offset, this.length - 8);
        let val = (first << 24) + // Overflow
        this[++offset] * 2 ** 16 + this[++offset] * 2 ** 8 + this[++offset];
        return (BigInt(val) << BigInt(32)) + BigInt(this[++offset] * 2 ** 24 + this[++offset] * 2 ** 16 + this[++offset] * 2 ** 8 + last);
      });
      Buffer4.prototype.readFloatLE = function(offset, noAssert) {
        return offset = offset >>> 0, noAssert || checkOffset(offset, 4, this.length), ieee754.read(this, offset, !0, 23, 4);
      };
      Buffer4.prototype.readFloatBE = function(offset, noAssert) {
        return offset = offset >>> 0, noAssert || checkOffset(offset, 4, this.length), ieee754.read(this, offset, !1, 23, 4);
      };
      Buffer4.prototype.readDoubleLE = function(offset, noAssert) {
        return offset = offset >>> 0, noAssert || checkOffset(offset, 8, this.length), ieee754.read(this, offset, !0, 52, 8);
      };
      Buffer4.prototype.readDoubleBE = function(offset, noAssert) {
        return offset = offset >>> 0, noAssert || checkOffset(offset, 8, this.length), ieee754.read(this, offset, !1, 52, 8);
      };
      function checkInt(buf, value, offset, ext, max, min) {
        if (!Buffer4.isBuffer(buf)) throw new TypeError('"buffer" argument must be a Buffer instance');
        if (value > max || value < min) throw new RangeError('"value" argument is out of bounds');
        if (offset + ext > buf.length) throw new RangeError("Index out of range");
      }
      Buffer4.prototype.writeUintLE = Buffer4.prototype.writeUIntLE = function(value, offset, byteLength2, noAssert) {
        if (value = +value, offset = offset >>> 0, byteLength2 = byteLength2 >>> 0, !noAssert) {
          let maxBytes = Math.pow(2, 8 * byteLength2) - 1;
          checkInt(this, value, offset, byteLength2, maxBytes, 0);
        }
        let mul = 1, i = 0;
        for (this[offset] = value & 255; ++i < byteLength2 && (mul *= 256); )
          this[offset + i] = value / mul & 255;
        return offset + byteLength2;
      };
      Buffer4.prototype.writeUintBE = Buffer4.prototype.writeUIntBE = function(value, offset, byteLength2, noAssert) {
        if (value = +value, offset = offset >>> 0, byteLength2 = byteLength2 >>> 0, !noAssert) {
          let maxBytes = Math.pow(2, 8 * byteLength2) - 1;
          checkInt(this, value, offset, byteLength2, maxBytes, 0);
        }
        let i = byteLength2 - 1, mul = 1;
        for (this[offset + i] = value & 255; --i >= 0 && (mul *= 256); )
          this[offset + i] = value / mul & 255;
        return offset + byteLength2;
      };
      Buffer4.prototype.writeUint8 = Buffer4.prototype.writeUInt8 = function(value, offset, noAssert) {
        return value = +value, offset = offset >>> 0, noAssert || checkInt(this, value, offset, 1, 255, 0), this[offset] = value & 255, offset + 1;
      };
      Buffer4.prototype.writeUint16LE = Buffer4.prototype.writeUInt16LE = function(value, offset, noAssert) {
        return value = +value, offset = offset >>> 0, noAssert || checkInt(this, value, offset, 2, 65535, 0), this[offset] = value & 255, this[offset + 1] = value >>> 8, offset + 2;
      };
      Buffer4.prototype.writeUint16BE = Buffer4.prototype.writeUInt16BE = function(value, offset, noAssert) {
        return value = +value, offset = offset >>> 0, noAssert || checkInt(this, value, offset, 2, 65535, 0), this[offset] = value >>> 8, this[offset + 1] = value & 255, offset + 2;
      };
      Buffer4.prototype.writeUint32LE = Buffer4.prototype.writeUInt32LE = function(value, offset, noAssert) {
        return value = +value, offset = offset >>> 0, noAssert || checkInt(this, value, offset, 4, 4294967295, 0), this[offset + 3] = value >>> 24, this[offset + 2] = value >>> 16, this[offset + 1] = value >>> 8, this[offset] = value & 255, offset + 4;
      };
      Buffer4.prototype.writeUint32BE = Buffer4.prototype.writeUInt32BE = function(value, offset, noAssert) {
        return value = +value, offset = offset >>> 0, noAssert || checkInt(this, value, offset, 4, 4294967295, 0), this[offset] = value >>> 24, this[offset + 1] = value >>> 16, this[offset + 2] = value >>> 8, this[offset + 3] = value & 255, offset + 4;
      };
      function wrtBigUInt64LE(buf, value, offset, min, max) {
        checkIntBI(value, min, max, buf, offset, 7);
        let lo = Number(value & BigInt(4294967295));
        buf[offset++] = lo, lo = lo >> 8, buf[offset++] = lo, lo = lo >> 8, buf[offset++] = lo, lo = lo >> 8, buf[offset++] = lo;
        let hi = Number(value >> BigInt(32) & BigInt(4294967295));
        return buf[offset++] = hi, hi = hi >> 8, buf[offset++] = hi, hi = hi >> 8, buf[offset++] = hi, hi = hi >> 8, buf[offset++] = hi, offset;
      }
      function wrtBigUInt64BE(buf, value, offset, min, max) {
        checkIntBI(value, min, max, buf, offset, 7);
        let lo = Number(value & BigInt(4294967295));
        buf[offset + 7] = lo, lo = lo >> 8, buf[offset + 6] = lo, lo = lo >> 8, buf[offset + 5] = lo, lo = lo >> 8, buf[offset + 4] = lo;
        let hi = Number(value >> BigInt(32) & BigInt(4294967295));
        return buf[offset + 3] = hi, hi = hi >> 8, buf[offset + 2] = hi, hi = hi >> 8, buf[offset + 1] = hi, hi = hi >> 8, buf[offset] = hi, offset + 8;
      }
      Buffer4.prototype.writeBigUInt64LE = defineBigIntMethod(function(value, offset = 0) {
        return wrtBigUInt64LE(this, value, offset, BigInt(0), BigInt("0xffffffffffffffff"));
      });
      Buffer4.prototype.writeBigUInt64BE = defineBigIntMethod(function(value, offset = 0) {
        return wrtBigUInt64BE(this, value, offset, BigInt(0), BigInt("0xffffffffffffffff"));
      });
      Buffer4.prototype.writeIntLE = function(value, offset, byteLength2, noAssert) {
        if (value = +value, offset = offset >>> 0, !noAssert) {
          let limit = Math.pow(2, 8 * byteLength2 - 1);
          checkInt(this, value, offset, byteLength2, limit - 1, -limit);
        }
        let i = 0, mul = 1, sub = 0;
        for (this[offset] = value & 255; ++i < byteLength2 && (mul *= 256); )
          value < 0 && sub === 0 && this[offset + i - 1] !== 0 && (sub = 1), this[offset + i] = (value / mul >> 0) - sub & 255;
        return offset + byteLength2;
      };
      Buffer4.prototype.writeIntBE = function(value, offset, byteLength2, noAssert) {
        if (value = +value, offset = offset >>> 0, !noAssert) {
          let limit = Math.pow(2, 8 * byteLength2 - 1);
          checkInt(this, value, offset, byteLength2, limit - 1, -limit);
        }
        let i = byteLength2 - 1, mul = 1, sub = 0;
        for (this[offset + i] = value & 255; --i >= 0 && (mul *= 256); )
          value < 0 && sub === 0 && this[offset + i + 1] !== 0 && (sub = 1), this[offset + i] = (value / mul >> 0) - sub & 255;
        return offset + byteLength2;
      };
      Buffer4.prototype.writeInt8 = function(value, offset, noAssert) {
        return value = +value, offset = offset >>> 0, noAssert || checkInt(this, value, offset, 1, 127, -128), value < 0 && (value = 255 + value + 1), this[offset] = value & 255, offset + 1;
      };
      Buffer4.prototype.writeInt16LE = function(value, offset, noAssert) {
        return value = +value, offset = offset >>> 0, noAssert || checkInt(this, value, offset, 2, 32767, -32768), this[offset] = value & 255, this[offset + 1] = value >>> 8, offset + 2;
      };
      Buffer4.prototype.writeInt16BE = function(value, offset, noAssert) {
        return value = +value, offset = offset >>> 0, noAssert || checkInt(this, value, offset, 2, 32767, -32768), this[offset] = value >>> 8, this[offset + 1] = value & 255, offset + 2;
      };
      Buffer4.prototype.writeInt32LE = function(value, offset, noAssert) {
        return value = +value, offset = offset >>> 0, noAssert || checkInt(this, value, offset, 4, 2147483647, -2147483648), this[offset] = value & 255, this[offset + 1] = value >>> 8, this[offset + 2] = value >>> 16, this[offset + 3] = value >>> 24, offset + 4;
      };
      Buffer4.prototype.writeInt32BE = function(value, offset, noAssert) {
        return value = +value, offset = offset >>> 0, noAssert || checkInt(this, value, offset, 4, 2147483647, -2147483648), value < 0 && (value = 4294967295 + value + 1), this[offset] = value >>> 24, this[offset + 1] = value >>> 16, this[offset + 2] = value >>> 8, this[offset + 3] = value & 255, offset + 4;
      };
      Buffer4.prototype.writeBigInt64LE = defineBigIntMethod(function(value, offset = 0) {
        return wrtBigUInt64LE(this, value, offset, -BigInt("0x8000000000000000"), BigInt("0x7fffffffffffffff"));
      });
      Buffer4.prototype.writeBigInt64BE = defineBigIntMethod(function(value, offset = 0) {
        return wrtBigUInt64BE(this, value, offset, -BigInt("0x8000000000000000"), BigInt("0x7fffffffffffffff"));
      });
      function checkIEEE754(buf, value, offset, ext, max, min) {
        if (offset + ext > buf.length) throw new RangeError("Index out of range");
        if (offset < 0) throw new RangeError("Index out of range");
      }
      function writeFloat(buf, value, offset, littleEndian, noAssert) {
        return value = +value, offset = offset >>> 0, noAssert || checkIEEE754(buf, value, offset, 4, 34028234663852886e22, -34028234663852886e22), ieee754.write(buf, value, offset, littleEndian, 23, 4), offset + 4;
      }
      Buffer4.prototype.writeFloatLE = function(value, offset, noAssert) {
        return writeFloat(this, value, offset, !0, noAssert);
      };
      Buffer4.prototype.writeFloatBE = function(value, offset, noAssert) {
        return writeFloat(this, value, offset, !1, noAssert);
      };
      function writeDouble(buf, value, offset, littleEndian, noAssert) {
        return value = +value, offset = offset >>> 0, noAssert || checkIEEE754(buf, value, offset, 8, 17976931348623157e292, -17976931348623157e292), ieee754.write(buf, value, offset, littleEndian, 52, 8), offset + 8;
      }
      Buffer4.prototype.writeDoubleLE = function(value, offset, noAssert) {
        return writeDouble(this, value, offset, !0, noAssert);
      };
      Buffer4.prototype.writeDoubleBE = function(value, offset, noAssert) {
        return writeDouble(this, value, offset, !1, noAssert);
      };
      Buffer4.prototype.copy = function(target, targetStart, start, end) {
        if (!Buffer4.isBuffer(target)) throw new TypeError("argument should be a Buffer");
        if (start || (start = 0), !end && end !== 0 && (end = this.length), targetStart >= target.length && (targetStart = target.length), targetStart || (targetStart = 0), end > 0 && end < start && (end = start), end === start || target.length === 0 || this.length === 0) return 0;
        if (targetStart < 0)
          throw new RangeError("targetStart out of bounds");
        if (start < 0 || start >= this.length) throw new RangeError("Index out of range");
        if (end < 0) throw new RangeError("sourceEnd out of bounds");
        end > this.length && (end = this.length), target.length - targetStart < end - start && (end = target.length - targetStart + start);
        let len = end - start;
        return this === target && typeof Uint8Array.prototype.copyWithin == "function" ? this.copyWithin(targetStart, start, end) : Uint8Array.prototype.set.call(
          target,
          this.subarray(start, end),
          targetStart
        ), len;
      };
      Buffer4.prototype.fill = function(val, start, end, encoding) {
        if (typeof val == "string") {
          if (typeof start == "string" ? (encoding = start, start = 0, end = this.length) : typeof end == "string" && (encoding = end, end = this.length), encoding !== void 0 && typeof encoding != "string")
            throw new TypeError("encoding must be a string");
          if (typeof encoding == "string" && !Buffer4.isEncoding(encoding))
            throw new TypeError("Unknown encoding: " + encoding);
          if (val.length === 1) {
            let code = val.charCodeAt(0);
            (encoding === "utf8" && code < 128 || encoding === "latin1") && (val = code);
          }
        } else typeof val == "number" ? val = val & 255 : typeof val == "boolean" && (val = Number(val));
        if (start < 0 || this.length < start || this.length < end)
          throw new RangeError("Out of range index");
        if (end <= start)
          return this;
        start = start >>> 0, end = end === void 0 ? this.length : end >>> 0, val || (val = 0);
        let i;
        if (typeof val == "number")
          for (i = start; i < end; ++i)
            this[i] = val;
        else {
          let bytes = Buffer4.isBuffer(val) ? val : Buffer4.from(val, encoding), len = bytes.length;
          if (len === 0)
            throw new TypeError('The value "' + val + '" is invalid for argument "value"');
          for (i = 0; i < end - start; ++i)
            this[i + start] = bytes[i % len];
        }
        return this;
      };
      var errors = {};
      function E(sym, getMessage, Base) {
        errors[sym] = class extends Base {
          constructor() {
            super(), Object.defineProperty(this, "message", {
              value: getMessage.apply(this, arguments),
              writable: !0,
              configurable: !0
            }), this.name = `${this.name} [${sym}]`, this.stack, delete this.name;
          }
          get code() {
            return sym;
          }
          set code(value) {
            Object.defineProperty(this, "code", {
              configurable: !0,
              enumerable: !0,
              value,
              writable: !0
            });
          }
          toString() {
            return `${this.name} [${sym}]: ${this.message}`;
          }
        };
      }
      E(
        "ERR_BUFFER_OUT_OF_BOUNDS",
        function(name) {
          return name ? `${name} is outside of buffer bounds` : "Attempt to access memory outside buffer bounds";
        },
        RangeError
      );
      E(
        "ERR_INVALID_ARG_TYPE",
        function(name, actual) {
          return `The "${name}" argument must be of type number. Received type ${typeof actual}`;
        },
        TypeError
      );
      E(
        "ERR_OUT_OF_RANGE",
        function(str, range, input) {
          let msg = `The value of "${str}" is out of range.`, received = input;
          return Number.isInteger(input) && Math.abs(input) > 2 ** 32 ? received = addNumericalSeparator(String(input)) : typeof input == "bigint" && (received = String(input), (input > BigInt(2) ** BigInt(32) || input < -(BigInt(2) ** BigInt(32))) && (received = addNumericalSeparator(received)), received += "n"), msg += ` It must be ${range}. Received ${received}`, msg;
        },
        RangeError
      );
      function addNumericalSeparator(val) {
        let res = "", i = val.length, start = val[0] === "-" ? 1 : 0;
        for (; i >= start + 4; i -= 3)
          res = `_${val.slice(i - 3, i)}${res}`;
        return `${val.slice(0, i)}${res}`;
      }
      function checkBounds(buf, offset, byteLength2) {
        validateNumber(offset, "offset"), (buf[offset] === void 0 || buf[offset + byteLength2] === void 0) && boundsError(offset, buf.length - (byteLength2 + 1));
      }
      function checkIntBI(value, min, max, buf, offset, byteLength2) {
        if (value > max || value < min) {
          let n = typeof min == "bigint" ? "n" : "", range;
          throw byteLength2 > 3 ? min === 0 || min === BigInt(0) ? range = `>= 0${n} and < 2${n} ** ${(byteLength2 + 1) * 8}${n}` : range = `>= -(2${n} ** ${(byteLength2 + 1) * 8 - 1}${n}) and < 2 ** ${(byteLength2 + 1) * 8 - 1}${n}` : range = `>= ${min}${n} and <= ${max}${n}`, new errors.ERR_OUT_OF_RANGE("value", range, value);
        }
        checkBounds(buf, offset, byteLength2);
      }
      function validateNumber(value, name) {
        if (typeof value != "number")
          throw new errors.ERR_INVALID_ARG_TYPE(name, "number", value);
      }
      function boundsError(value, length, type) {
        throw Math.floor(value) !== value ? (validateNumber(value, type), new errors.ERR_OUT_OF_RANGE(type || "offset", "an integer", value)) : length < 0 ? new errors.ERR_BUFFER_OUT_OF_BOUNDS() : new errors.ERR_OUT_OF_RANGE(
          type || "offset",
          `>= ${type ? 1 : 0} and <= ${length}`,
          value
        );
      }
      var INVALID_BASE64_RE = /[^+/0-9A-Za-z-_]/g;
      function base64clean(str) {
        if (str = str.split("=")[0], str = str.trim().replace(INVALID_BASE64_RE, ""), str.length < 2) return "";
        for (; str.length % 4 !== 0; )
          str = str + "=";
        return str;
      }
      function utf8ToBytes(string, units) {
        units = units || 1 / 0;
        let codePoint, length = string.length, leadSurrogate = null, bytes = [];
        for (let i = 0; i < length; ++i) {
          if (codePoint = string.charCodeAt(i), codePoint > 55295 && codePoint < 57344) {
            if (!leadSurrogate) {
              if (codePoint > 56319) {
                (units -= 3) > -1 && bytes.push(239, 191, 189);
                continue;
              } else if (i + 1 === length) {
                (units -= 3) > -1 && bytes.push(239, 191, 189);
                continue;
              }
              leadSurrogate = codePoint;
              continue;
            }
            if (codePoint < 56320) {
              (units -= 3) > -1 && bytes.push(239, 191, 189), leadSurrogate = codePoint;
              continue;
            }
            codePoint = (leadSurrogate - 55296 << 10 | codePoint - 56320) + 65536;
          } else leadSurrogate && (units -= 3) > -1 && bytes.push(239, 191, 189);
          if (leadSurrogate = null, codePoint < 128) {
            if ((units -= 1) < 0) break;
            bytes.push(codePoint);
          } else if (codePoint < 2048) {
            if ((units -= 2) < 0) break;
            bytes.push(
              codePoint >> 6 | 192,
              codePoint & 63 | 128
            );
          } else if (codePoint < 65536) {
            if ((units -= 3) < 0) break;
            bytes.push(
              codePoint >> 12 | 224,
              codePoint >> 6 & 63 | 128,
              codePoint & 63 | 128
            );
          } else if (codePoint < 1114112) {
            if ((units -= 4) < 0) break;
            bytes.push(
              codePoint >> 18 | 240,
              codePoint >> 12 & 63 | 128,
              codePoint >> 6 & 63 | 128,
              codePoint & 63 | 128
            );
          } else
            throw new Error("Invalid code point");
        }
        return bytes;
      }
      function asciiToBytes(str) {
        let byteArray = [];
        for (let i = 0; i < str.length; ++i)
          byteArray.push(str.charCodeAt(i) & 255);
        return byteArray;
      }
      function utf16leToBytes(str, units) {
        let c, hi, lo, byteArray = [];
        for (let i = 0; i < str.length && !((units -= 2) < 0); ++i)
          c = str.charCodeAt(i), hi = c >> 8, lo = c % 256, byteArray.push(lo), byteArray.push(hi);
        return byteArray;
      }
      function base64ToBytes(str) {
        return base64.toByteArray(base64clean(str));
      }
      function blitBuffer(src, dst, offset, length) {
        let i;
        for (i = 0; i < length && !(i + offset >= dst.length || i >= src.length); ++i)
          dst[i + offset] = src[i];
        return i;
      }
      function isInstance(obj, type) {
        return obj instanceof type || obj != null && obj.constructor != null && obj.constructor.name != null && obj.constructor.name === type.name;
      }
      function numberIsNaN(obj) {
        return obj !== obj;
      }
      var hexSliceLookupTable = (function() {
        let alphabet = "0123456789abcdef", table = new Array(256);
        for (let i = 0; i < 16; ++i) {
          let i16 = i * 16;
          for (let j = 0; j < 16; ++j)
            table[i16 + j] = alphabet[i] + alphabet[j];
        }
        return table;
      })();
      function defineBigIntMethod(fn) {
        return typeof BigInt > "u" ? BufferBigIntNotDefined : fn;
      }
      function BufferBigIntNotDefined() {
        throw new Error("BigInt not supported");
      }
    }
  });

  // buffer-shim.js
  var import_buffer, init_buffer_shim = __esm({
    "buffer-shim.js"() {
      import_buffer = __toESM(require_buffer());
    }
  });

  // node_modules/bitcoinjs-lib/src/networks.js
  var require_networks = __commonJS({
    "node_modules/bitcoinjs-lib/src/networks.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      exports.testnet = exports.regtest = exports.bitcoin = void 0;
      exports.bitcoin = {
        /**
         * The message prefix used for signing Bitcoin messages.
         */
        messagePrefix: `Bitcoin Signed Message:
`,
        /**
         * The Bech32 prefix used for Bitcoin addresses.
         */
        bech32: "bc",
        /**
         * The BIP32 key prefixes for Bitcoin.
         */
        bip32: {
          /**
           * The public key prefix for BIP32 extended public keys.
           */
          public: 76067358,
          /**
           * The private key prefix for BIP32 extended private keys.
           */
          private: 76066276
        },
        /**
         * The prefix for Bitcoin public key hashes.
         */
        pubKeyHash: 0,
        /**
         * The prefix for Bitcoin script hashes.
         */
        scriptHash: 5,
        /**
         * The prefix for Bitcoin Wallet Import Format (WIF) private keys.
         */
        wif: 128
      };
      exports.regtest = {
        messagePrefix: `Bitcoin Signed Message:
`,
        bech32: "bcrt",
        bip32: {
          public: 70617039,
          private: 70615956
        },
        pubKeyHash: 111,
        scriptHash: 196,
        wif: 239
      };
      exports.testnet = {
        messagePrefix: `Bitcoin Signed Message:
`,
        bech32: "tb",
        bip32: {
          public: 70617039,
          private: 70615956
        },
        pubKeyHash: 111,
        scriptHash: 196,
        wif: 239
      };
    }
  });

  // node_modules/bitcoinjs-lib/src/bip66.js
  var require_bip66 = __commonJS({
    "node_modules/bitcoinjs-lib/src/bip66.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      exports.encode = exports.decode = exports.check = void 0;
      function check(buffer) {
        if (buffer.length < 8 || buffer.length > 72 || buffer[0] !== 48 || buffer[1] !== buffer.length - 2 || buffer[2] !== 2) return !1;
        let lenR = buffer[3];
        if (lenR === 0 || 5 + lenR >= buffer.length || buffer[4 + lenR] !== 2) return !1;
        let lenS = buffer[5 + lenR];
        return !(lenS === 0 || 6 + lenR + lenS !== buffer.length || buffer[4] & 128 || lenR > 1 && buffer[4] === 0 && !(buffer[5] & 128) || buffer[lenR + 6] & 128 || lenS > 1 && buffer[lenR + 6] === 0 && !(buffer[lenR + 7] & 128));
      }
      exports.check = check;
      function decode(buffer) {
        if (buffer.length < 8) throw new Error("DER sequence length is too short");
        if (buffer.length > 72) throw new Error("DER sequence length is too long");
        if (buffer[0] !== 48) throw new Error("Expected DER sequence");
        if (buffer[1] !== buffer.length - 2)
          throw new Error("DER sequence length is invalid");
        if (buffer[2] !== 2) throw new Error("Expected DER integer");
        let lenR = buffer[3];
        if (lenR === 0) throw new Error("R length is zero");
        if (5 + lenR >= buffer.length) throw new Error("R length is too long");
        if (buffer[4 + lenR] !== 2) throw new Error("Expected DER integer (2)");
        let lenS = buffer[5 + lenR];
        if (lenS === 0) throw new Error("S length is zero");
        if (6 + lenR + lenS !== buffer.length) throw new Error("S length is invalid");
        if (buffer[4] & 128) throw new Error("R value is negative");
        if (lenR > 1 && buffer[4] === 0 && !(buffer[5] & 128))
          throw new Error("R value excessively padded");
        if (buffer[lenR + 6] & 128) throw new Error("S value is negative");
        if (lenS > 1 && buffer[lenR + 6] === 0 && !(buffer[lenR + 7] & 128))
          throw new Error("S value excessively padded");
        return {
          r: buffer.slice(4, 4 + lenR),
          s: buffer.slice(6 + lenR)
        };
      }
      exports.decode = decode;
      function encode(r, s) {
        let lenR = r.length, lenS = s.length;
        if (lenR === 0) throw new Error("R length is zero");
        if (lenS === 0) throw new Error("S length is zero");
        if (lenR > 33) throw new Error("R length is too long");
        if (lenS > 33) throw new Error("S length is too long");
        if (r[0] & 128) throw new Error("R value is negative");
        if (s[0] & 128) throw new Error("S value is negative");
        if (lenR > 1 && r[0] === 0 && !(r[1] & 128))
          throw new Error("R value excessively padded");
        if (lenS > 1 && s[0] === 0 && !(s[1] & 128))
          throw new Error("S value excessively padded");
        let signature = import_buffer.Buffer.allocUnsafe(6 + lenR + lenS);
        return signature[0] = 48, signature[1] = signature.length - 2, signature[2] = 2, signature[3] = r.length, r.copy(signature, 4), signature[4 + lenR] = 2, signature[5 + lenR] = s.length, s.copy(signature, 6 + lenR), signature;
      }
      exports.encode = encode;
    }
  });

  // node_modules/bitcoinjs-lib/src/ops.js
  var require_ops = __commonJS({
    "node_modules/bitcoinjs-lib/src/ops.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      exports.REVERSE_OPS = exports.OPS = void 0;
      var OPS = {
        OP_FALSE: 0,
        OP_0: 0,
        OP_PUSHDATA1: 76,
        OP_PUSHDATA2: 77,
        OP_PUSHDATA4: 78,
        OP_1NEGATE: 79,
        OP_RESERVED: 80,
        OP_TRUE: 81,
        OP_1: 81,
        OP_2: 82,
        OP_3: 83,
        OP_4: 84,
        OP_5: 85,
        OP_6: 86,
        OP_7: 87,
        OP_8: 88,
        OP_9: 89,
        OP_10: 90,
        OP_11: 91,
        OP_12: 92,
        OP_13: 93,
        OP_14: 94,
        OP_15: 95,
        OP_16: 96,
        OP_NOP: 97,
        OP_VER: 98,
        OP_IF: 99,
        OP_NOTIF: 100,
        OP_VERIF: 101,
        OP_VERNOTIF: 102,
        OP_ELSE: 103,
        OP_ENDIF: 104,
        OP_VERIFY: 105,
        OP_RETURN: 106,
        OP_TOALTSTACK: 107,
        OP_FROMALTSTACK: 108,
        OP_2DROP: 109,
        OP_2DUP: 110,
        OP_3DUP: 111,
        OP_2OVER: 112,
        OP_2ROT: 113,
        OP_2SWAP: 114,
        OP_IFDUP: 115,
        OP_DEPTH: 116,
        OP_DROP: 117,
        OP_DUP: 118,
        OP_NIP: 119,
        OP_OVER: 120,
        OP_PICK: 121,
        OP_ROLL: 122,
        OP_ROT: 123,
        OP_SWAP: 124,
        OP_TUCK: 125,
        OP_CAT: 126,
        OP_SUBSTR: 127,
        OP_LEFT: 128,
        OP_RIGHT: 129,
        OP_SIZE: 130,
        OP_INVERT: 131,
        OP_AND: 132,
        OP_OR: 133,
        OP_XOR: 134,
        OP_EQUAL: 135,
        OP_EQUALVERIFY: 136,
        OP_RESERVED1: 137,
        OP_RESERVED2: 138,
        OP_1ADD: 139,
        OP_1SUB: 140,
        OP_2MUL: 141,
        OP_2DIV: 142,
        OP_NEGATE: 143,
        OP_ABS: 144,
        OP_NOT: 145,
        OP_0NOTEQUAL: 146,
        OP_ADD: 147,
        OP_SUB: 148,
        OP_MUL: 149,
        OP_DIV: 150,
        OP_MOD: 151,
        OP_LSHIFT: 152,
        OP_RSHIFT: 153,
        OP_BOOLAND: 154,
        OP_BOOLOR: 155,
        OP_NUMEQUAL: 156,
        OP_NUMEQUALVERIFY: 157,
        OP_NUMNOTEQUAL: 158,
        OP_LESSTHAN: 159,
        OP_GREATERTHAN: 160,
        OP_LESSTHANOREQUAL: 161,
        OP_GREATERTHANOREQUAL: 162,
        OP_MIN: 163,
        OP_MAX: 164,
        OP_WITHIN: 165,
        OP_RIPEMD160: 166,
        OP_SHA1: 167,
        OP_SHA256: 168,
        OP_HASH160: 169,
        OP_HASH256: 170,
        OP_CODESEPARATOR: 171,
        OP_CHECKSIG: 172,
        OP_CHECKSIGVERIFY: 173,
        OP_CHECKMULTISIG: 174,
        OP_CHECKMULTISIGVERIFY: 175,
        OP_NOP1: 176,
        OP_NOP2: 177,
        OP_CHECKLOCKTIMEVERIFY: 177,
        OP_NOP3: 178,
        OP_CHECKSEQUENCEVERIFY: 178,
        OP_NOP4: 179,
        OP_NOP5: 180,
        OP_NOP6: 181,
        OP_NOP7: 182,
        OP_NOP8: 183,
        OP_NOP9: 184,
        OP_NOP10: 185,
        OP_CHECKSIGADD: 186,
        OP_PUBKEYHASH: 253,
        OP_PUBKEY: 254,
        OP_INVALIDOPCODE: 255
      };
      exports.OPS = OPS;
      var REVERSE_OPS = {};
      exports.REVERSE_OPS = REVERSE_OPS;
      for (let op of Object.keys(OPS)) {
        let code = OPS[op];
        REVERSE_OPS[code] = op;
      }
    }
  });

  // node_modules/bitcoinjs-lib/src/push_data.js
  var require_push_data = __commonJS({
    "node_modules/bitcoinjs-lib/src/push_data.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      exports.decode = exports.encode = exports.encodingLength = void 0;
      var ops_1 = require_ops();
      function encodingLength(i) {
        return i < ops_1.OPS.OP_PUSHDATA1 ? 1 : i <= 255 ? 2 : i <= 65535 ? 3 : 5;
      }
      exports.encodingLength = encodingLength;
      function encode(buffer, num, offset) {
        let size = encodingLength(num);
        return size === 1 ? buffer.writeUInt8(num, offset) : size === 2 ? (buffer.writeUInt8(ops_1.OPS.OP_PUSHDATA1, offset), buffer.writeUInt8(num, offset + 1)) : size === 3 ? (buffer.writeUInt8(ops_1.OPS.OP_PUSHDATA2, offset), buffer.writeUInt16LE(num, offset + 1)) : (buffer.writeUInt8(ops_1.OPS.OP_PUSHDATA4, offset), buffer.writeUInt32LE(num, offset + 1)), size;
      }
      exports.encode = encode;
      function decode(buffer, offset) {
        let opcode = buffer.readUInt8(offset), num, size;
        if (opcode < ops_1.OPS.OP_PUSHDATA1)
          num = opcode, size = 1;
        else if (opcode === ops_1.OPS.OP_PUSHDATA1) {
          if (offset + 2 > buffer.length) return null;
          num = buffer.readUInt8(offset + 1), size = 2;
        } else if (opcode === ops_1.OPS.OP_PUSHDATA2) {
          if (offset + 3 > buffer.length) return null;
          num = buffer.readUInt16LE(offset + 1), size = 3;
        } else {
          if (offset + 5 > buffer.length) return null;
          if (opcode !== ops_1.OPS.OP_PUSHDATA4) throw new Error("Unexpected opcode");
          num = buffer.readUInt32LE(offset + 1), size = 5;
        }
        return {
          opcode,
          number: num,
          size
        };
      }
      exports.decode = decode;
    }
  });

  // node_modules/bitcoinjs-lib/src/script_number.js
  var require_script_number = __commonJS({
    "node_modules/bitcoinjs-lib/src/script_number.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      exports.encode = exports.decode = void 0;
      function decode(buffer, maxLength, minimal) {
        maxLength = maxLength || 4, minimal = minimal === void 0 ? !0 : minimal;
        let length = buffer.length;
        if (length === 0) return 0;
        if (length > maxLength) throw new TypeError("Script number overflow");
        if (minimal && (buffer[length - 1] & 127) === 0 && (length <= 1 || (buffer[length - 2] & 128) === 0))
          throw new Error("Non-minimally encoded script number");
        if (length === 5) {
          let a = buffer.readUInt32LE(0), b = buffer.readUInt8(4);
          return b & 128 ? -((b & -129) * 4294967296 + a) : b * 4294967296 + a;
        }
        let result = 0;
        for (let i = 0; i < length; ++i)
          result |= buffer[i] << 8 * i;
        return buffer[length - 1] & 128 ? -(result & ~(128 << 8 * (length - 1))) : result;
      }
      exports.decode = decode;
      function scriptNumSize(i) {
        return i > 2147483647 ? 5 : i > 8388607 ? 4 : i > 32767 ? 3 : i > 127 ? 2 : i > 0 ? 1 : 0;
      }
      function encode(_number) {
        let value = Math.abs(_number), size = scriptNumSize(value), buffer = import_buffer.Buffer.allocUnsafe(size), negative = _number < 0;
        for (let i = 0; i < size; ++i)
          buffer.writeUInt8(value & 255, i), value >>= 8;
        return buffer[size - 1] & 128 ? buffer.writeUInt8(negative ? 128 : 0, size - 1) : negative && (buffer[size - 1] |= 128), buffer;
      }
      exports.encode = encode;
    }
  });

  // node_modules/typeforce/native.js
  var require_native = __commonJS({
    "node_modules/typeforce/native.js"(exports, module) {
      init_buffer_shim();
      init_process_shim();
      var types = {
        Array: function(value) {
          return value != null && value.constructor === Array;
        },
        Boolean: function(value) {
          return typeof value == "boolean";
        },
        Function: function(value) {
          return typeof value == "function";
        },
        Nil: function(value) {
          return value == null;
        },
        Number: function(value) {
          return typeof value == "number";
        },
        Object: function(value) {
          return typeof value == "object";
        },
        String: function(value) {
          return typeof value == "string";
        },
        "": function() {
          return !0;
        }
      };
      types.Null = types.Nil;
      for (typeName in types)
        types[typeName].toJSON = (function(t) {
          return t;
        }).bind(null, typeName);
      var typeName;
      module.exports = types;
    }
  });

  // node_modules/typeforce/errors.js
  var require_errors = __commonJS({
    "node_modules/typeforce/errors.js"(exports, module) {
      init_buffer_shim();
      init_process_shim();
      var native = require_native();
      function getTypeName(fn) {
        return fn.name || fn.toString().match(/function (.*?)\s*\(/)[1];
      }
      function getValueTypeName(value) {
        return native.Nil(value) ? "" : getTypeName(value.constructor);
      }
      function getValue(value) {
        return native.Function(value) ? "" : native.String(value) ? JSON.stringify(value) : value && native.Object(value) ? "" : value;
      }
      function captureStackTrace(e, t) {
        Error.captureStackTrace && Error.captureStackTrace(e, t);
      }
      function tfJSON(type) {
        return native.Function(type) ? type.toJSON ? type.toJSON() : getTypeName(type) : native.Array(type) ? "Array" : type && native.Object(type) ? "Object" : type !== void 0 ? type : "";
      }
      function tfErrorString(type, value, valueTypeName) {
        var valueJson = getValue(value);
        return "Expected " + tfJSON(type) + ", got" + (valueTypeName !== "" ? " " + valueTypeName : "") + (valueJson !== "" ? " " + valueJson : "");
      }
      function TfTypeError(type, value, valueTypeName) {
        valueTypeName = valueTypeName || getValueTypeName(value), this.message = tfErrorString(type, value, valueTypeName), captureStackTrace(this, TfTypeError), this.__type = type, this.__value = value, this.__valueTypeName = valueTypeName;
      }
      TfTypeError.prototype = Object.create(Error.prototype);
      TfTypeError.prototype.constructor = TfTypeError;
      function tfPropertyErrorString(type, label, name, value, valueTypeName) {
        var description = '" of type ';
        return label === "key" && (description = '" with key type '), tfErrorString('property "' + tfJSON(name) + description + tfJSON(type), value, valueTypeName);
      }
      function TfPropertyTypeError(type, property, label, value, valueTypeName) {
        type ? (valueTypeName = valueTypeName || getValueTypeName(value), this.message = tfPropertyErrorString(type, label, property, value, valueTypeName)) : this.message = 'Unexpected property "' + property + '"', captureStackTrace(this, TfTypeError), this.__label = label, this.__property = property, this.__type = type, this.__value = value, this.__valueTypeName = valueTypeName;
      }
      TfPropertyTypeError.prototype = Object.create(Error.prototype);
      TfPropertyTypeError.prototype.constructor = TfTypeError;
      function tfCustomError(expected, actual) {
        return new TfTypeError(expected, {}, actual);
      }
      function tfSubError(e, property, label) {
        return e instanceof TfPropertyTypeError ? (property = property + "." + e.__property, e = new TfPropertyTypeError(
          e.__type,
          property,
          e.__label,
          e.__value,
          e.__valueTypeName
        )) : e instanceof TfTypeError && (e = new TfPropertyTypeError(
          e.__type,
          property,
          label,
          e.__value,
          e.__valueTypeName
        )), captureStackTrace(e), e;
      }
      module.exports = {
        TfTypeError,
        TfPropertyTypeError,
        tfCustomError,
        tfSubError,
        tfJSON,
        getValueTypeName
      };
    }
  });

  // node_modules/typeforce/extra.js
  var require_extra = __commonJS({
    "node_modules/typeforce/extra.js"(exports, module) {
      init_buffer_shim();
      init_process_shim();
      var NATIVE = require_native(), ERRORS = require_errors();
      function _Buffer(value) {
        return import_buffer.Buffer.isBuffer(value);
      }
      function Hex(value) {
        return typeof value == "string" && /^([0-9a-f]{2})+$/i.test(value);
      }
      function _LengthN(type, length) {
        var name = type.toJSON();
        function Length(value) {
          if (!type(value)) return !1;
          if (value.length === length) return !0;
          throw ERRORS.tfCustomError(name + "(Length: " + length + ")", name + "(Length: " + value.length + ")");
        }
        return Length.toJSON = function() {
          return name;
        }, Length;
      }
      var _ArrayN = _LengthN.bind(null, NATIVE.Array), _BufferN = _LengthN.bind(null, _Buffer), _HexN = _LengthN.bind(null, Hex), _StringN = _LengthN.bind(null, NATIVE.String);
      function Range(a, b, f) {
        f = f || NATIVE.Number;
        function _range(value, strict) {
          return f(value, strict) && value > a && value < b;
        }
        return _range.toJSON = function() {
          return `${f.toJSON()} between [${a}, ${b}]`;
        }, _range;
      }
      var INT53_MAX = Math.pow(2, 53) - 1;
      function Finite(value) {
        return typeof value == "number" && isFinite(value);
      }
      function Int8(value) {
        return value << 24 >> 24 === value;
      }
      function Int16(value) {
        return value << 16 >> 16 === value;
      }
      function Int32(value) {
        return (value | 0) === value;
      }
      function Int53(value) {
        return typeof value == "number" && value >= -INT53_MAX && value <= INT53_MAX && Math.floor(value) === value;
      }
      function UInt8(value) {
        return (value & 255) === value;
      }
      function UInt16(value) {
        return (value & 65535) === value;
      }
      function UInt32(value) {
        return value >>> 0 === value;
      }
      function UInt53(value) {
        return typeof value == "number" && value >= 0 && value <= INT53_MAX && Math.floor(value) === value;
      }
      var types = {
        ArrayN: _ArrayN,
        Buffer: _Buffer,
        BufferN: _BufferN,
        Finite,
        Hex,
        HexN: _HexN,
        Int8,
        Int16,
        Int32,
        Int53,
        Range,
        StringN: _StringN,
        UInt8,
        UInt16,
        UInt32,
        UInt53
      };
      for (typeName in types)
        types[typeName].toJSON = (function(t) {
          return t;
        }).bind(null, typeName);
      var typeName;
      module.exports = types;
    }
  });

  // node_modules/typeforce/index.js
  var require_typeforce = __commonJS({
    "node_modules/typeforce/index.js"(exports, module) {
      init_buffer_shim();
      init_process_shim();
      var ERRORS = require_errors(), NATIVE = require_native(), tfJSON = ERRORS.tfJSON, TfTypeError = ERRORS.TfTypeError, TfPropertyTypeError = ERRORS.TfPropertyTypeError, tfSubError = ERRORS.tfSubError, getValueTypeName = ERRORS.getValueTypeName, TYPES = {
        arrayOf: function(type, options) {
          type = compile(type), options = options || {};
          function _arrayOf(array, strict) {
            return !NATIVE.Array(array) || NATIVE.Nil(array) || options.minLength !== void 0 && array.length < options.minLength || options.maxLength !== void 0 && array.length > options.maxLength || options.length !== void 0 && array.length !== options.length ? !1 : array.every(function(value, i) {
              try {
                return typeforce(type, value, strict);
              } catch (e) {
                throw tfSubError(e, i);
              }
            });
          }
          return _arrayOf.toJSON = function() {
            var str = "[" + tfJSON(type) + "]";
            return options.length !== void 0 ? str += "{" + options.length + "}" : (options.minLength !== void 0 || options.maxLength !== void 0) && (str += "{" + (options.minLength === void 0 ? 0 : options.minLength) + "," + (options.maxLength === void 0 ? 1 / 0 : options.maxLength) + "}"), str;
          }, _arrayOf;
        },
        maybe: function maybe(type) {
          type = compile(type);
          function _maybe(value, strict) {
            return NATIVE.Nil(value) || type(value, strict, maybe);
          }
          return _maybe.toJSON = function() {
            return "?" + tfJSON(type);
          }, _maybe;
        },
        map: function(propertyType, propertyKeyType) {
          propertyType = compile(propertyType), propertyKeyType && (propertyKeyType = compile(propertyKeyType));
          function _map(value, strict) {
            if (!NATIVE.Object(value) || NATIVE.Nil(value)) return !1;
            for (var propertyName in value) {
              try {
                propertyKeyType && typeforce(propertyKeyType, propertyName, strict);
              } catch (e) {
                throw tfSubError(e, propertyName, "key");
              }
              try {
                var propertyValue = value[propertyName];
                typeforce(propertyType, propertyValue, strict);
              } catch (e) {
                throw tfSubError(e, propertyName);
              }
            }
            return !0;
          }
          return propertyKeyType ? _map.toJSON = function() {
            return "{" + tfJSON(propertyKeyType) + ": " + tfJSON(propertyType) + "}";
          } : _map.toJSON = function() {
            return "{" + tfJSON(propertyType) + "}";
          }, _map;
        },
        object: function(uncompiled) {
          var type = {};
          for (var typePropertyName in uncompiled)
            type[typePropertyName] = compile(uncompiled[typePropertyName]);
          function _object(value, strict) {
            if (!NATIVE.Object(value) || NATIVE.Nil(value)) return !1;
            var propertyName;
            try {
              for (propertyName in type) {
                var propertyType = type[propertyName], propertyValue = value[propertyName];
                typeforce(propertyType, propertyValue, strict);
              }
            } catch (e) {
              throw tfSubError(e, propertyName);
            }
            if (strict) {
              for (propertyName in value)
                if (!type[propertyName])
                  throw new TfPropertyTypeError(void 0, propertyName);
            }
            return !0;
          }
          return _object.toJSON = function() {
            return tfJSON(type);
          }, _object;
        },
        anyOf: function() {
          var types = [].slice.call(arguments).map(compile);
          function _anyOf(value, strict) {
            return types.some(function(type) {
              try {
                return typeforce(type, value, strict);
              } catch {
                return !1;
              }
            });
          }
          return _anyOf.toJSON = function() {
            return types.map(tfJSON).join("|");
          }, _anyOf;
        },
        allOf: function() {
          var types = [].slice.call(arguments).map(compile);
          function _allOf(value, strict) {
            return types.every(function(type) {
              try {
                return typeforce(type, value, strict);
              } catch {
                return !1;
              }
            });
          }
          return _allOf.toJSON = function() {
            return types.map(tfJSON).join(" & ");
          }, _allOf;
        },
        quacksLike: function(type) {
          function _quacksLike(value) {
            return type === getValueTypeName(value);
          }
          return _quacksLike.toJSON = function() {
            return type;
          }, _quacksLike;
        },
        tuple: function() {
          var types = [].slice.call(arguments).map(compile);
          function _tuple(values, strict) {
            return NATIVE.Nil(values) || NATIVE.Nil(values.length) || strict && values.length !== types.length ? !1 : types.every(function(type, i) {
              try {
                return typeforce(type, values[i], strict);
              } catch (e) {
                throw tfSubError(e, i);
              }
            });
          }
          return _tuple.toJSON = function() {
            return "(" + types.map(tfJSON).join(", ") + ")";
          }, _tuple;
        },
        value: function(expected) {
          function _value(actual) {
            return actual === expected;
          }
          return _value.toJSON = function() {
            return expected;
          }, _value;
        }
      };
      TYPES.oneOf = TYPES.anyOf;
      function compile(type) {
        if (NATIVE.String(type))
          return type[0] === "?" ? TYPES.maybe(type.slice(1)) : NATIVE[type] || TYPES.quacksLike(type);
        if (type && NATIVE.Object(type)) {
          if (NATIVE.Array(type)) {
            if (type.length !== 1) throw new TypeError("Expected compile() parameter of type Array of length 1");
            return TYPES.arrayOf(type[0]);
          }
          return TYPES.object(type);
        } else if (NATIVE.Function(type))
          return type;
        return TYPES.value(type);
      }
      function typeforce(type, value, strict, surrogate) {
        if (NATIVE.Function(type)) {
          if (type(value, strict)) return !0;
          throw new TfTypeError(surrogate || type, value);
        }
        return typeforce(compile(type), value, strict);
      }
      for (typeName in NATIVE)
        typeforce[typeName] = NATIVE[typeName];
      var typeName;
      for (typeName in TYPES)
        typeforce[typeName] = TYPES[typeName];
      var EXTRA = require_extra();
      for (typeName in EXTRA)
        typeforce[typeName] = EXTRA[typeName];
      typeforce.compile = compile;
      typeforce.TfTypeError = TfTypeError;
      typeforce.TfPropertyTypeError = TfPropertyTypeError;
      module.exports = typeforce;
    }
  });

  // node_modules/bitcoinjs-lib/src/types.js
  var require_types = __commonJS({
    "node_modules/bitcoinjs-lib/src/types.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      exports.oneOf = exports.Null = exports.BufferN = exports.Function = exports.UInt32 = exports.UInt8 = exports.tuple = exports.maybe = exports.Hex = exports.Buffer = exports.String = exports.Boolean = exports.Array = exports.Number = exports.Hash256bit = exports.Hash160bit = exports.Buffer256bit = exports.isTaptree = exports.isTapleaf = exports.TAPLEAF_VERSION_MASK = exports.Satoshi = exports.isPoint = exports.stacksEqual = exports.typeforce = void 0;
      var buffer_1 = require_buffer();
      exports.typeforce = require_typeforce();
      var ZERO32 = buffer_1.Buffer.alloc(32, 0), EC_P = buffer_1.Buffer.from(
        "fffffffffffffffffffffffffffffffffffffffffffffffffffffffefffffc2f",
        "hex"
      );
      function stacksEqual(a, b) {
        return a.length !== b.length ? !1 : a.every((x, i) => x.equals(b[i]));
      }
      exports.stacksEqual = stacksEqual;
      function isPoint2(p) {
        if (!buffer_1.Buffer.isBuffer(p) || p.length < 33) return !1;
        let t = p[0], x = p.slice(1, 33);
        if (x.compare(ZERO32) === 0 || x.compare(EC_P) >= 0) return !1;
        if ((t === 2 || t === 3) && p.length === 33)
          return !0;
        let y = p.slice(33);
        return y.compare(ZERO32) === 0 || y.compare(EC_P) >= 0 ? !1 : t === 4 && p.length === 65;
      }
      exports.isPoint = isPoint2;
      var SATOSHI_MAX = 21 * 1e14;
      function Satoshi(value) {
        return exports.typeforce.UInt53(value) && value <= SATOSHI_MAX;
      }
      exports.Satoshi = Satoshi;
      exports.TAPLEAF_VERSION_MASK = 254;
      function isTapleaf(o) {
        return !o || !("output" in o) || !buffer_1.Buffer.isBuffer(o.output) ? !1 : o.version !== void 0 ? (o.version & exports.TAPLEAF_VERSION_MASK) === o.version : !0;
      }
      exports.isTapleaf = isTapleaf;
      function isTaptree(scriptTree) {
        return (0, exports.Array)(scriptTree) ? scriptTree.length !== 2 ? !1 : scriptTree.every((t) => isTaptree(t)) : isTapleaf(scriptTree);
      }
      exports.isTaptree = isTaptree;
      exports.Buffer256bit = exports.typeforce.BufferN(32);
      exports.Hash160bit = exports.typeforce.BufferN(20);
      exports.Hash256bit = exports.typeforce.BufferN(32);
      exports.Number = exports.typeforce.Number;
      exports.Array = exports.typeforce.Array;
      exports.Boolean = exports.typeforce.Boolean;
      exports.String = exports.typeforce.String;
      exports.Buffer = exports.typeforce.Buffer;
      exports.Hex = exports.typeforce.Hex;
      exports.maybe = exports.typeforce.maybe;
      exports.tuple = exports.typeforce.tuple;
      exports.UInt8 = exports.typeforce.UInt8;
      exports.UInt32 = exports.typeforce.UInt32;
      exports.Function = exports.typeforce.Function;
      exports.BufferN = exports.typeforce.BufferN;
      exports.Null = exports.typeforce.Null;
      exports.oneOf = exports.typeforce.oneOf;
    }
  });

  // node_modules/bitcoinjs-lib/src/script_signature.js
  var require_script_signature = __commonJS({
    "node_modules/bitcoinjs-lib/src/script_signature.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      exports.encode = exports.decode = void 0;
      var bip66 = require_bip66(), script_1 = require_script(), types = require_types(), { typeforce } = types, ZERO = import_buffer.Buffer.alloc(1, 0);
      function toDER(x) {
        let i = 0;
        for (; x[i] === 0; ) ++i;
        return i === x.length ? ZERO : (x = x.slice(i), x[0] & 128 ? import_buffer.Buffer.concat([ZERO, x], 1 + x.length) : x);
      }
      function fromDER(x) {
        x[0] === 0 && (x = x.slice(1));
        let buffer = import_buffer.Buffer.alloc(32, 0), bstart = Math.max(0, 32 - x.length);
        return x.copy(buffer, bstart), buffer;
      }
      function decode(buffer) {
        let hashType = buffer.readUInt8(buffer.length - 1);
        if (!(0, script_1.isDefinedHashType)(hashType))
          throw new Error("Invalid hashType " + hashType);
        let decoded = bip66.decode(buffer.slice(0, -1)), r = fromDER(decoded.r), s = fromDER(decoded.s);
        return { signature: import_buffer.Buffer.concat([r, s], 64), hashType };
      }
      exports.decode = decode;
      function encode(signature, hashType) {
        if (typeforce(
          {
            signature: types.BufferN(64),
            hashType: types.UInt8
          },
          { signature, hashType }
        ), !(0, script_1.isDefinedHashType)(hashType))
          throw new Error("Invalid hashType " + hashType);
        let hashTypeBuffer = import_buffer.Buffer.allocUnsafe(1);
        hashTypeBuffer.writeUInt8(hashType, 0);
        let r = toDER(signature.slice(0, 32)), s = toDER(signature.slice(32, 64));
        return import_buffer.Buffer.concat([bip66.encode(r, s), hashTypeBuffer]);
      }
      exports.encode = encode;
    }
  });

  // node_modules/bitcoinjs-lib/src/script.js
  var require_script = __commonJS({
    "node_modules/bitcoinjs-lib/src/script.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      exports.signature = exports.number = exports.isCanonicalScriptSignature = exports.isDefinedHashType = exports.isCanonicalPubKey = exports.toStack = exports.fromASM = exports.toASM = exports.decompile = exports.compile = exports.countNonPushOnlyOPs = exports.isPushOnly = exports.OPS = void 0;
      var bip66 = require_bip66(), ops_1 = require_ops();
      Object.defineProperty(exports, "OPS", {
        enumerable: !0,
        get: function() {
          return ops_1.OPS;
        }
      });
      var pushdata = require_push_data(), scriptNumber = require_script_number(), scriptSignature = require_script_signature(), types = require_types(), { typeforce } = types, OP_INT_BASE = ops_1.OPS.OP_RESERVED;
      function isOPInt(value) {
        return types.Number(value) && (value === ops_1.OPS.OP_0 || value >= ops_1.OPS.OP_1 && value <= ops_1.OPS.OP_16 || value === ops_1.OPS.OP_1NEGATE);
      }
      function isPushOnlyChunk(value) {
        return types.Buffer(value) || isOPInt(value);
      }
      function isPushOnly(value) {
        return types.Array(value) && value.every(isPushOnlyChunk);
      }
      exports.isPushOnly = isPushOnly;
      function countNonPushOnlyOPs(value) {
        return value.length - value.filter(isPushOnlyChunk).length;
      }
      exports.countNonPushOnlyOPs = countNonPushOnlyOPs;
      function asMinimalOP(buffer) {
        if (buffer.length === 0) return ops_1.OPS.OP_0;
        if (buffer.length === 1) {
          if (buffer[0] >= 1 && buffer[0] <= 16) return OP_INT_BASE + buffer[0];
          if (buffer[0] === 129) return ops_1.OPS.OP_1NEGATE;
        }
      }
      function chunksIsBuffer(buf) {
        return import_buffer.Buffer.isBuffer(buf);
      }
      function chunksIsArray(buf) {
        return types.Array(buf);
      }
      function singleChunkIsBuffer(buf) {
        return import_buffer.Buffer.isBuffer(buf);
      }
      function compile(chunks) {
        if (chunksIsBuffer(chunks)) return chunks;
        typeforce(types.Array, chunks);
        let bufferSize = chunks.reduce((accum, chunk) => singleChunkIsBuffer(chunk) ? chunk.length === 1 && asMinimalOP(chunk) !== void 0 ? accum + 1 : accum + pushdata.encodingLength(chunk.length) + chunk.length : accum + 1, 0), buffer = import_buffer.Buffer.allocUnsafe(bufferSize), offset = 0;
        if (chunks.forEach((chunk) => {
          if (singleChunkIsBuffer(chunk)) {
            let opcode = asMinimalOP(chunk);
            if (opcode !== void 0) {
              buffer.writeUInt8(opcode, offset), offset += 1;
              return;
            }
            offset += pushdata.encode(buffer, chunk.length, offset), chunk.copy(buffer, offset), offset += chunk.length;
          } else
            buffer.writeUInt8(chunk, offset), offset += 1;
        }), offset !== buffer.length) throw new Error("Could not decode chunks");
        return buffer;
      }
      exports.compile = compile;
      function decompile(buffer) {
        if (chunksIsArray(buffer)) return buffer;
        typeforce(types.Buffer, buffer);
        let chunks = [], i = 0;
        for (; i < buffer.length; ) {
          let opcode = buffer[i];
          if (opcode > ops_1.OPS.OP_0 && opcode <= ops_1.OPS.OP_PUSHDATA4) {
            let d = pushdata.decode(buffer, i);
            if (d === null || (i += d.size, i + d.number > buffer.length)) return null;
            let data = buffer.slice(i, i + d.number);
            i += d.number;
            let op = asMinimalOP(data);
            op !== void 0 ? chunks.push(op) : chunks.push(data);
          } else
            chunks.push(opcode), i += 1;
        }
        return chunks;
      }
      exports.decompile = decompile;
      function toASM(chunks) {
        if (chunksIsBuffer(chunks) && (chunks = decompile(chunks)), !chunks)
          throw new Error("Could not convert invalid chunks to ASM");
        return chunks.map((chunk) => {
          if (singleChunkIsBuffer(chunk)) {
            let op = asMinimalOP(chunk);
            if (op === void 0) return chunk.toString("hex");
            chunk = op;
          }
          return ops_1.REVERSE_OPS[chunk];
        }).join(" ");
      }
      exports.toASM = toASM;
      function fromASM(asm) {
        return typeforce(types.String, asm), compile(
          asm.split(" ").map((chunkStr) => ops_1.OPS[chunkStr] !== void 0 ? ops_1.OPS[chunkStr] : (typeforce(types.Hex, chunkStr), import_buffer.Buffer.from(chunkStr, "hex")))
        );
      }
      exports.fromASM = fromASM;
      function toStack(chunks) {
        return chunks = decompile(chunks), typeforce(isPushOnly, chunks), chunks.map((op) => singleChunkIsBuffer(op) ? op : op === ops_1.OPS.OP_0 ? import_buffer.Buffer.allocUnsafe(0) : scriptNumber.encode(op - OP_INT_BASE));
      }
      exports.toStack = toStack;
      function isCanonicalPubKey(buffer) {
        return types.isPoint(buffer);
      }
      exports.isCanonicalPubKey = isCanonicalPubKey;
      function isDefinedHashType(hashType) {
        let hashTypeMod = hashType & -129;
        return hashTypeMod > 0 && hashTypeMod < 4;
      }
      exports.isDefinedHashType = isDefinedHashType;
      function isCanonicalScriptSignature(buffer) {
        return !import_buffer.Buffer.isBuffer(buffer) || !isDefinedHashType(buffer[buffer.length - 1]) ? !1 : bip66.check(buffer.slice(0, -1));
      }
      exports.isCanonicalScriptSignature = isCanonicalScriptSignature;
      exports.number = scriptNumber;
      exports.signature = scriptSignature;
    }
  });

  // node_modules/bitcoinjs-lib/src/payments/lazy.js
  var require_lazy = __commonJS({
    "node_modules/bitcoinjs-lib/src/payments/lazy.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      exports.value = exports.prop = void 0;
      function prop(object, name, f) {
        Object.defineProperty(object, name, {
          configurable: !0,
          enumerable: !0,
          get() {
            let _value = f.call(this);
            return this[name] = _value, _value;
          },
          set(_value) {
            Object.defineProperty(this, name, {
              configurable: !0,
              enumerable: !0,
              value: _value,
              writable: !0
            });
          }
        });
      }
      exports.prop = prop;
      function value(f) {
        let _value;
        return () => (_value !== void 0 || (_value = f()), _value);
      }
      exports.value = value;
    }
  });

  // node_modules/bitcoinjs-lib/src/payments/embed.js
  var require_embed = __commonJS({
    "node_modules/bitcoinjs-lib/src/payments/embed.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      exports.p2data = void 0;
      var networks_1 = require_networks(), bscript = require_script(), types_1 = require_types(), lazy = require_lazy(), OPS = bscript.OPS;
      function p2data(a, opts) {
        if (!a.data && !a.output) throw new TypeError("Not enough data");
        opts = Object.assign({ validate: !0 }, opts || {}), (0, types_1.typeforce)(
          {
            network: types_1.typeforce.maybe(types_1.typeforce.Object),
            output: types_1.typeforce.maybe(types_1.typeforce.Buffer),
            data: types_1.typeforce.maybe(
              types_1.typeforce.arrayOf(types_1.typeforce.Buffer)
            )
          },
          a
        );
        let o = { name: "embed", network: a.network || networks_1.bitcoin };
        if (lazy.prop(o, "output", () => {
          if (a.data)
            return bscript.compile([OPS.OP_RETURN].concat(a.data));
        }), lazy.prop(o, "data", () => {
          if (a.output)
            return bscript.decompile(a.output).slice(1);
        }), opts.validate && a.output) {
          let chunks = bscript.decompile(a.output);
          if (chunks[0] !== OPS.OP_RETURN) throw new TypeError("Output is invalid");
          if (!chunks.slice(1).every(types_1.typeforce.Buffer))
            throw new TypeError("Output is invalid");
          if (a.data && !(0, types_1.stacksEqual)(a.data, o.data))
            throw new TypeError("Data mismatch");
        }
        return Object.assign(o, a);
      }
      exports.p2data = p2data;
    }
  });

  // node_modules/bitcoinjs-lib/src/payments/p2ms.js
  var require_p2ms = __commonJS({
    "node_modules/bitcoinjs-lib/src/payments/p2ms.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      exports.p2ms = void 0;
      var networks_1 = require_networks(), bscript = require_script(), types_1 = require_types(), lazy = require_lazy(), OPS = bscript.OPS, OP_INT_BASE = OPS.OP_RESERVED;
      function p2ms(a, opts) {
        if (!a.input && !a.output && !(a.pubkeys && a.m !== void 0) && !a.signatures)
          throw new TypeError("Not enough data");
        opts = Object.assign({ validate: !0 }, opts || {});
        function isAcceptableSignature(x) {
          return bscript.isCanonicalScriptSignature(x) || (opts.allowIncomplete && x === OPS.OP_0) !== void 0;
        }
        (0, types_1.typeforce)(
          {
            network: types_1.typeforce.maybe(types_1.typeforce.Object),
            m: types_1.typeforce.maybe(types_1.typeforce.Number),
            n: types_1.typeforce.maybe(types_1.typeforce.Number),
            output: types_1.typeforce.maybe(types_1.typeforce.Buffer),
            pubkeys: types_1.typeforce.maybe(
              types_1.typeforce.arrayOf(types_1.isPoint)
            ),
            signatures: types_1.typeforce.maybe(
              types_1.typeforce.arrayOf(isAcceptableSignature)
            ),
            input: types_1.typeforce.maybe(types_1.typeforce.Buffer)
          },
          a
        );
        let o = { network: a.network || networks_1.bitcoin }, chunks = [], decoded = !1;
        function decode(output) {
          decoded || (decoded = !0, chunks = bscript.decompile(output), o.m = chunks[0] - OP_INT_BASE, o.n = chunks[chunks.length - 2] - OP_INT_BASE, o.pubkeys = chunks.slice(1, -2));
        }
        if (lazy.prop(o, "output", () => {
          if (a.m && o.n && a.pubkeys)
            return bscript.compile(
              [].concat(
                OP_INT_BASE + a.m,
                a.pubkeys,
                OP_INT_BASE + o.n,
                OPS.OP_CHECKMULTISIG
              )
            );
        }), lazy.prop(o, "m", () => {
          if (o.output)
            return decode(o.output), o.m;
        }), lazy.prop(o, "n", () => {
          if (o.pubkeys)
            return o.pubkeys.length;
        }), lazy.prop(o, "pubkeys", () => {
          if (a.output)
            return decode(a.output), o.pubkeys;
        }), lazy.prop(o, "signatures", () => {
          if (a.input)
            return bscript.decompile(a.input).slice(1);
        }), lazy.prop(o, "input", () => {
          if (a.signatures)
            return bscript.compile([OPS.OP_0].concat(a.signatures));
        }), lazy.prop(o, "witness", () => {
          if (o.input)
            return [];
        }), lazy.prop(o, "name", () => {
          if (!(!o.m || !o.n))
            return `p2ms(${o.m} of ${o.n})`;
        }), opts.validate) {
          if (a.output) {
            if (decode(a.output), !types_1.typeforce.Number(chunks[0]))
              throw new TypeError("Output is invalid");
            if (!types_1.typeforce.Number(chunks[chunks.length - 2]))
              throw new TypeError("Output is invalid");
            if (chunks[chunks.length - 1] !== OPS.OP_CHECKMULTISIG)
              throw new TypeError("Output is invalid");
            if (o.m <= 0 || o.n > 16 || o.m > o.n || o.n !== chunks.length - 3)
              throw new TypeError("Output is invalid");
            if (!o.pubkeys.every((x) => (0, types_1.isPoint)(x)))
              throw new TypeError("Output is invalid");
            if (a.m !== void 0 && a.m !== o.m) throw new TypeError("m mismatch");
            if (a.n !== void 0 && a.n !== o.n) throw new TypeError("n mismatch");
            if (a.pubkeys && !(0, types_1.stacksEqual)(a.pubkeys, o.pubkeys))
              throw new TypeError("Pubkeys mismatch");
          }
          if (a.pubkeys) {
            if (a.n !== void 0 && a.n !== a.pubkeys.length)
              throw new TypeError("Pubkey count mismatch");
            if (o.n = a.pubkeys.length, o.n < o.m) throw new TypeError("Pubkey count cannot be less than m");
          }
          if (a.signatures) {
            if (a.signatures.length < o.m)
              throw new TypeError("Not enough signatures provided");
            if (a.signatures.length > o.m)
              throw new TypeError("Too many signatures provided");
          }
          if (a.input) {
            if (a.input[0] !== OPS.OP_0) throw new TypeError("Input is invalid");
            if (o.signatures.length === 0 || !o.signatures.every(isAcceptableSignature))
              throw new TypeError("Input has invalid signature(s)");
            if (a.signatures && !(0, types_1.stacksEqual)(a.signatures, o.signatures))
              throw new TypeError("Signature mismatch");
            if (a.m !== void 0 && a.m !== a.signatures.length)
              throw new TypeError("Signature count mismatch");
          }
        }
        return Object.assign(o, a);
      }
      exports.p2ms = p2ms;
    }
  });

  // node_modules/bitcoinjs-lib/src/payments/p2pk.js
  var require_p2pk = __commonJS({
    "node_modules/bitcoinjs-lib/src/payments/p2pk.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      exports.p2pk = void 0;
      var networks_1 = require_networks(), bscript = require_script(), types_1 = require_types(), lazy = require_lazy(), OPS = bscript.OPS;
      function p2pk(a, opts) {
        if (!a.input && !a.output && !a.pubkey && !a.input && !a.signature)
          throw new TypeError("Not enough data");
        opts = Object.assign({ validate: !0 }, opts || {}), (0, types_1.typeforce)(
          {
            network: types_1.typeforce.maybe(types_1.typeforce.Object),
            output: types_1.typeforce.maybe(types_1.typeforce.Buffer),
            pubkey: types_1.typeforce.maybe(types_1.isPoint),
            signature: types_1.typeforce.maybe(bscript.isCanonicalScriptSignature),
            input: types_1.typeforce.maybe(types_1.typeforce.Buffer)
          },
          a
        );
        let _chunks = lazy.value(() => bscript.decompile(a.input)), o = { name: "p2pk", network: a.network || networks_1.bitcoin };
        if (lazy.prop(o, "output", () => {
          if (a.pubkey)
            return bscript.compile([a.pubkey, OPS.OP_CHECKSIG]);
        }), lazy.prop(o, "pubkey", () => {
          if (a.output)
            return a.output.slice(1, -1);
        }), lazy.prop(o, "signature", () => {
          if (a.input)
            return _chunks()[0];
        }), lazy.prop(o, "input", () => {
          if (a.signature)
            return bscript.compile([a.signature]);
        }), lazy.prop(o, "witness", () => {
          if (o.input)
            return [];
        }), opts.validate) {
          if (a.output) {
            if (a.output[a.output.length - 1] !== OPS.OP_CHECKSIG)
              throw new TypeError("Output is invalid");
            if (!(0, types_1.isPoint)(o.pubkey))
              throw new TypeError("Output pubkey is invalid");
            if (a.pubkey && !a.pubkey.equals(o.pubkey))
              throw new TypeError("Pubkey mismatch");
          }
          if (a.signature && a.input && !a.input.equals(o.input))
            throw new TypeError("Signature mismatch");
          if (a.input) {
            if (_chunks().length !== 1) throw new TypeError("Input is invalid");
            if (!bscript.isCanonicalScriptSignature(o.signature))
              throw new TypeError("Input has invalid signature");
          }
        }
        return Object.assign(o, a);
      }
      exports.p2pk = p2pk;
    }
  });

  // node_modules/@noble/hashes/crypto.js
  var require_crypto = __commonJS({
    "node_modules/@noble/hashes/crypto.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      exports.crypto = void 0;
      exports.crypto = typeof globalThis == "object" && "crypto" in globalThis ? globalThis.crypto : void 0;
    }
  });

  // node_modules/@noble/hashes/utils.js
  var require_utils = __commonJS({
    "node_modules/@noble/hashes/utils.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      exports.wrapXOFConstructorWithOpts = exports.wrapConstructorWithOpts = exports.wrapConstructor = exports.Hash = exports.nextTick = exports.swap32IfBE = exports.byteSwapIfBE = exports.swap8IfBE = exports.isLE = void 0;
      exports.isBytes = isBytes;
      exports.anumber = anumber;
      exports.abytes = abytes;
      exports.ahash = ahash;
      exports.aexists = aexists;
      exports.aoutput = aoutput;
      exports.u8 = u8;
      exports.u32 = u32;
      exports.clean = clean;
      exports.createView = createView;
      exports.rotr = rotr;
      exports.rotl = rotl;
      exports.byteSwap = byteSwap;
      exports.byteSwap32 = byteSwap32;
      exports.bytesToHex = bytesToHex;
      exports.hexToBytes = hexToBytes;
      exports.asyncLoop = asyncLoop;
      exports.utf8ToBytes = utf8ToBytes;
      exports.bytesToUtf8 = bytesToUtf8;
      exports.toBytes = toBytes;
      exports.kdfInputToBytes = kdfInputToBytes;
      exports.concatBytes = concatBytes;
      exports.checkOpts = checkOpts;
      exports.createHasher = createHasher;
      exports.createOptHasher = createOptHasher;
      exports.createXOFer = createXOFer;
      exports.randomBytes = randomBytes;
      var crypto_1 = require_crypto();
      function isBytes(a) {
        return a instanceof Uint8Array || ArrayBuffer.isView(a) && a.constructor.name === "Uint8Array";
      }
      function anumber(n) {
        if (!Number.isSafeInteger(n) || n < 0)
          throw new Error("positive integer expected, got " + n);
      }
      function abytes(b, ...lengths) {
        if (!isBytes(b))
          throw new Error("Uint8Array expected");
        if (lengths.length > 0 && !lengths.includes(b.length))
          throw new Error("Uint8Array expected of length " + lengths + ", got length=" + b.length);
      }
      function ahash(h) {
        if (typeof h != "function" || typeof h.create != "function")
          throw new Error("Hash should be wrapped by utils.createHasher");
        anumber(h.outputLen), anumber(h.blockLen);
      }
      function aexists(instance, checkFinished = !0) {
        if (instance.destroyed)
          throw new Error("Hash instance has been destroyed");
        if (checkFinished && instance.finished)
          throw new Error("Hash#digest() has already been called");
      }
      function aoutput(out, instance) {
        abytes(out);
        let min = instance.outputLen;
        if (out.length < min)
          throw new Error("digestInto() expects output buffer of length at least " + min);
      }
      function u8(arr) {
        return new Uint8Array(arr.buffer, arr.byteOffset, arr.byteLength);
      }
      function u32(arr) {
        return new Uint32Array(arr.buffer, arr.byteOffset, Math.floor(arr.byteLength / 4));
      }
      function clean(...arrays) {
        for (let i = 0; i < arrays.length; i++)
          arrays[i].fill(0);
      }
      function createView(arr) {
        return new DataView(arr.buffer, arr.byteOffset, arr.byteLength);
      }
      function rotr(word, shift) {
        return word << 32 - shift | word >>> shift;
      }
      function rotl(word, shift) {
        return word << shift | word >>> 32 - shift >>> 0;
      }
      exports.isLE = new Uint8Array(new Uint32Array([287454020]).buffer)[0] === 68;
      function byteSwap(word) {
        return word << 24 & 4278190080 | word << 8 & 16711680 | word >>> 8 & 65280 | word >>> 24 & 255;
      }
      exports.swap8IfBE = exports.isLE ? (n) => n : (n) => byteSwap(n);
      exports.byteSwapIfBE = exports.swap8IfBE;
      function byteSwap32(arr) {
        for (let i = 0; i < arr.length; i++)
          arr[i] = byteSwap(arr[i]);
        return arr;
      }
      exports.swap32IfBE = exports.isLE ? (u) => u : byteSwap32;
      var hasHexBuiltin = /* @ts-ignore */ typeof Uint8Array.from([]).toHex == "function" && typeof Uint8Array.fromHex == "function", hexes = /* @__PURE__ */ Array.from({ length: 256 }, (_, i) => i.toString(16).padStart(2, "0"));
      function bytesToHex(bytes) {
        if (abytes(bytes), hasHexBuiltin)
          return bytes.toHex();
        let hex = "";
        for (let i = 0; i < bytes.length; i++)
          hex += hexes[bytes[i]];
        return hex;
      }
      var asciis = { _0: 48, _9: 57, A: 65, F: 70, a: 97, f: 102 };
      function asciiToBase16(ch) {
        if (ch >= asciis._0 && ch <= asciis._9)
          return ch - asciis._0;
        if (ch >= asciis.A && ch <= asciis.F)
          return ch - (asciis.A - 10);
        if (ch >= asciis.a && ch <= asciis.f)
          return ch - (asciis.a - 10);
      }
      function hexToBytes(hex) {
        if (typeof hex != "string")
          throw new Error("hex string expected, got " + typeof hex);
        if (hasHexBuiltin)
          return Uint8Array.fromHex(hex);
        let hl = hex.length, al = hl / 2;
        if (hl % 2)
          throw new Error("hex string expected, got unpadded hex of length " + hl);
        let array = new Uint8Array(al);
        for (let ai = 0, hi = 0; ai < al; ai++, hi += 2) {
          let n1 = asciiToBase16(hex.charCodeAt(hi)), n2 = asciiToBase16(hex.charCodeAt(hi + 1));
          if (n1 === void 0 || n2 === void 0) {
            let char = hex[hi] + hex[hi + 1];
            throw new Error('hex string expected, got non-hex character "' + char + '" at index ' + hi);
          }
          array[ai] = n1 * 16 + n2;
        }
        return array;
      }
      var nextTick = async () => {
      };
      exports.nextTick = nextTick;
      async function asyncLoop(iters, tick, cb) {
        let ts = Date.now();
        for (let i = 0; i < iters; i++) {
          cb(i);
          let diff = Date.now() - ts;
          diff >= 0 && diff < tick || (await (0, exports.nextTick)(), ts += diff);
        }
      }
      function utf8ToBytes(str) {
        if (typeof str != "string")
          throw new Error("string expected");
        return new Uint8Array(new TextEncoder().encode(str));
      }
      function bytesToUtf8(bytes) {
        return new TextDecoder().decode(bytes);
      }
      function toBytes(data) {
        return typeof data == "string" && (data = utf8ToBytes(data)), abytes(data), data;
      }
      function kdfInputToBytes(data) {
        return typeof data == "string" && (data = utf8ToBytes(data)), abytes(data), data;
      }
      function concatBytes(...arrays) {
        let sum = 0;
        for (let i = 0; i < arrays.length; i++) {
          let a = arrays[i];
          abytes(a), sum += a.length;
        }
        let res = new Uint8Array(sum);
        for (let i = 0, pad = 0; i < arrays.length; i++) {
          let a = arrays[i];
          res.set(a, pad), pad += a.length;
        }
        return res;
      }
      function checkOpts(defaults, opts) {
        if (opts !== void 0 && {}.toString.call(opts) !== "[object Object]")
          throw new Error("options should be object or undefined");
        return Object.assign(defaults, opts);
      }
      var Hash = class {
      };
      exports.Hash = Hash;
      function createHasher(hashCons) {
        let hashC = (msg) => hashCons().update(toBytes(msg)).digest(), tmp = hashCons();
        return hashC.outputLen = tmp.outputLen, hashC.blockLen = tmp.blockLen, hashC.create = () => hashCons(), hashC;
      }
      function createOptHasher(hashCons) {
        let hashC = (msg, opts) => hashCons(opts).update(toBytes(msg)).digest(), tmp = hashCons({});
        return hashC.outputLen = tmp.outputLen, hashC.blockLen = tmp.blockLen, hashC.create = (opts) => hashCons(opts), hashC;
      }
      function createXOFer(hashCons) {
        let hashC = (msg, opts) => hashCons(opts).update(toBytes(msg)).digest(), tmp = hashCons({});
        return hashC.outputLen = tmp.outputLen, hashC.blockLen = tmp.blockLen, hashC.create = (opts) => hashCons(opts), hashC;
      }
      exports.wrapConstructor = createHasher;
      exports.wrapConstructorWithOpts = createOptHasher;
      exports.wrapXOFConstructorWithOpts = createXOFer;
      function randomBytes(bytesLength = 32) {
        if (crypto_1.crypto && typeof crypto_1.crypto.getRandomValues == "function")
          return crypto_1.crypto.getRandomValues(new Uint8Array(bytesLength));
        if (crypto_1.crypto && typeof crypto_1.crypto.randomBytes == "function")
          return Uint8Array.from(crypto_1.crypto.randomBytes(bytesLength));
        throw new Error("crypto.getRandomValues must be defined");
      }
    }
  });

  // node_modules/@noble/hashes/_md.js
  var require_md = __commonJS({
    "node_modules/@noble/hashes/_md.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      exports.SHA512_IV = exports.SHA384_IV = exports.SHA224_IV = exports.SHA256_IV = exports.HashMD = void 0;
      exports.setBigUint64 = setBigUint64;
      exports.Chi = Chi;
      exports.Maj = Maj;
      var utils_ts_1 = require_utils();
      function setBigUint64(view, byteOffset, value, isLE) {
        if (typeof view.setBigUint64 == "function")
          return view.setBigUint64(byteOffset, value, isLE);
        let _32n = BigInt(32), _u32_max = BigInt(4294967295), wh = Number(value >> _32n & _u32_max), wl = Number(value & _u32_max), h = isLE ? 4 : 0, l = isLE ? 0 : 4;
        view.setUint32(byteOffset + h, wh, isLE), view.setUint32(byteOffset + l, wl, isLE);
      }
      function Chi(a, b, c) {
        return a & b ^ ~a & c;
      }
      function Maj(a, b, c) {
        return a & b ^ a & c ^ b & c;
      }
      var HashMD = class extends utils_ts_1.Hash {
        constructor(blockLen, outputLen, padOffset, isLE) {
          super(), this.finished = !1, this.length = 0, this.pos = 0, this.destroyed = !1, this.blockLen = blockLen, this.outputLen = outputLen, this.padOffset = padOffset, this.isLE = isLE, this.buffer = new Uint8Array(blockLen), this.view = (0, utils_ts_1.createView)(this.buffer);
        }
        update(data) {
          (0, utils_ts_1.aexists)(this), data = (0, utils_ts_1.toBytes)(data), (0, utils_ts_1.abytes)(data);
          let { view, buffer, blockLen } = this, len = data.length;
          for (let pos = 0; pos < len; ) {
            let take = Math.min(blockLen - this.pos, len - pos);
            if (take === blockLen) {
              let dataView = (0, utils_ts_1.createView)(data);
              for (; blockLen <= len - pos; pos += blockLen)
                this.process(dataView, pos);
              continue;
            }
            buffer.set(data.subarray(pos, pos + take), this.pos), this.pos += take, pos += take, this.pos === blockLen && (this.process(view, 0), this.pos = 0);
          }
          return this.length += data.length, this.roundClean(), this;
        }
        digestInto(out) {
          (0, utils_ts_1.aexists)(this), (0, utils_ts_1.aoutput)(out, this), this.finished = !0;
          let { buffer, view, blockLen, isLE } = this, { pos } = this;
          buffer[pos++] = 128, (0, utils_ts_1.clean)(this.buffer.subarray(pos)), this.padOffset > blockLen - pos && (this.process(view, 0), pos = 0);
          for (let i = pos; i < blockLen; i++)
            buffer[i] = 0;
          setBigUint64(view, blockLen - 8, BigInt(this.length * 8), isLE), this.process(view, 0);
          let oview = (0, utils_ts_1.createView)(out), len = this.outputLen;
          if (len % 4)
            throw new Error("_sha2: outputLen should be aligned to 32bit");
          let outLen = len / 4, state = this.get();
          if (outLen > state.length)
            throw new Error("_sha2: outputLen bigger than state");
          for (let i = 0; i < outLen; i++)
            oview.setUint32(4 * i, state[i], isLE);
        }
        digest() {
          let { buffer, outputLen } = this;
          this.digestInto(buffer);
          let res = buffer.slice(0, outputLen);
          return this.destroy(), res;
        }
        _cloneInto(to) {
          to || (to = new this.constructor()), to.set(...this.get());
          let { blockLen, buffer, length, finished, destroyed, pos } = this;
          return to.destroyed = destroyed, to.finished = finished, to.length = length, to.pos = pos, length % blockLen && to.buffer.set(buffer), to;
        }
        clone() {
          return this._cloneInto();
        }
      };
      exports.HashMD = HashMD;
      exports.SHA256_IV = Uint32Array.from([
        1779033703,
        3144134277,
        1013904242,
        2773480762,
        1359893119,
        2600822924,
        528734635,
        1541459225
      ]);
      exports.SHA224_IV = Uint32Array.from([
        3238371032,
        914150663,
        812702999,
        4144912697,
        4290775857,
        1750603025,
        1694076839,
        3204075428
      ]);
      exports.SHA384_IV = Uint32Array.from([
        3418070365,
        3238371032,
        1654270250,
        914150663,
        2438529370,
        812702999,
        355462360,
        4144912697,
        1731405415,
        4290775857,
        2394180231,
        1750603025,
        3675008525,
        1694076839,
        1203062813,
        3204075428
      ]);
      exports.SHA512_IV = Uint32Array.from([
        1779033703,
        4089235720,
        3144134277,
        2227873595,
        1013904242,
        4271175723,
        2773480762,
        1595750129,
        1359893119,
        2917565137,
        2600822924,
        725511199,
        528734635,
        4215389547,
        1541459225,
        327033209
      ]);
    }
  });

  // node_modules/@noble/hashes/legacy.js
  var require_legacy = __commonJS({
    "node_modules/@noble/hashes/legacy.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      exports.ripemd160 = exports.RIPEMD160 = exports.md5 = exports.MD5 = exports.sha1 = exports.SHA1 = void 0;
      var _md_ts_1 = require_md(), utils_ts_1 = require_utils(), SHA1_IV = /* @__PURE__ */ Uint32Array.from([
        1732584193,
        4023233417,
        2562383102,
        271733878,
        3285377520
      ]), SHA1_W = /* @__PURE__ */ new Uint32Array(80), SHA1 = class extends _md_ts_1.HashMD {
        constructor() {
          super(64, 20, 8, !1), this.A = SHA1_IV[0] | 0, this.B = SHA1_IV[1] | 0, this.C = SHA1_IV[2] | 0, this.D = SHA1_IV[3] | 0, this.E = SHA1_IV[4] | 0;
        }
        get() {
          let { A, B, C, D, E } = this;
          return [A, B, C, D, E];
        }
        set(A, B, C, D, E) {
          this.A = A | 0, this.B = B | 0, this.C = C | 0, this.D = D | 0, this.E = E | 0;
        }
        process(view, offset) {
          for (let i = 0; i < 16; i++, offset += 4)
            SHA1_W[i] = view.getUint32(offset, !1);
          for (let i = 16; i < 80; i++)
            SHA1_W[i] = (0, utils_ts_1.rotl)(SHA1_W[i - 3] ^ SHA1_W[i - 8] ^ SHA1_W[i - 14] ^ SHA1_W[i - 16], 1);
          let { A, B, C, D, E } = this;
          for (let i = 0; i < 80; i++) {
            let F, K2;
            i < 20 ? (F = (0, _md_ts_1.Chi)(B, C, D), K2 = 1518500249) : i < 40 ? (F = B ^ C ^ D, K2 = 1859775393) : i < 60 ? (F = (0, _md_ts_1.Maj)(B, C, D), K2 = 2400959708) : (F = B ^ C ^ D, K2 = 3395469782);
            let T = (0, utils_ts_1.rotl)(A, 5) + F + E + K2 + SHA1_W[i] | 0;
            E = D, D = C, C = (0, utils_ts_1.rotl)(B, 30), B = A, A = T;
          }
          A = A + this.A | 0, B = B + this.B | 0, C = C + this.C | 0, D = D + this.D | 0, E = E + this.E | 0, this.set(A, B, C, D, E);
        }
        roundClean() {
          (0, utils_ts_1.clean)(SHA1_W);
        }
        destroy() {
          this.set(0, 0, 0, 0, 0), (0, utils_ts_1.clean)(this.buffer);
        }
      };
      exports.SHA1 = SHA1;
      exports.sha1 = (0, utils_ts_1.createHasher)(() => new SHA1());
      var p32 = /* @__PURE__ */ Math.pow(2, 32), K = /* @__PURE__ */ Array.from({ length: 64 }, (_, i) => Math.floor(p32 * Math.abs(Math.sin(i + 1)))), MD5_IV = /* @__PURE__ */ SHA1_IV.slice(0, 4), MD5_W = /* @__PURE__ */ new Uint32Array(16), MD5 = class extends _md_ts_1.HashMD {
        constructor() {
          super(64, 16, 8, !0), this.A = MD5_IV[0] | 0, this.B = MD5_IV[1] | 0, this.C = MD5_IV[2] | 0, this.D = MD5_IV[3] | 0;
        }
        get() {
          let { A, B, C, D } = this;
          return [A, B, C, D];
        }
        set(A, B, C, D) {
          this.A = A | 0, this.B = B | 0, this.C = C | 0, this.D = D | 0;
        }
        process(view, offset) {
          for (let i = 0; i < 16; i++, offset += 4)
            MD5_W[i] = view.getUint32(offset, !0);
          let { A, B, C, D } = this;
          for (let i = 0; i < 64; i++) {
            let F, g, s;
            i < 16 ? (F = (0, _md_ts_1.Chi)(B, C, D), g = i, s = [7, 12, 17, 22]) : i < 32 ? (F = (0, _md_ts_1.Chi)(D, B, C), g = (5 * i + 1) % 16, s = [5, 9, 14, 20]) : i < 48 ? (F = B ^ C ^ D, g = (3 * i + 5) % 16, s = [4, 11, 16, 23]) : (F = C ^ (B | ~D), g = 7 * i % 16, s = [6, 10, 15, 21]), F = F + A + K[i] + MD5_W[g], A = D, D = C, C = B, B = B + (0, utils_ts_1.rotl)(F, s[i % 4]);
          }
          A = A + this.A | 0, B = B + this.B | 0, C = C + this.C | 0, D = D + this.D | 0, this.set(A, B, C, D);
        }
        roundClean() {
          (0, utils_ts_1.clean)(MD5_W);
        }
        destroy() {
          this.set(0, 0, 0, 0), (0, utils_ts_1.clean)(this.buffer);
        }
      };
      exports.MD5 = MD5;
      exports.md5 = (0, utils_ts_1.createHasher)(() => new MD5());
      var Rho160 = /* @__PURE__ */ Uint8Array.from([
        7,
        4,
        13,
        1,
        10,
        6,
        15,
        3,
        12,
        0,
        9,
        5,
        2,
        14,
        11,
        8
      ]), Id160 = Uint8Array.from(new Array(16).fill(0).map((_, i) => i)), Pi160 = Id160.map((i) => (9 * i + 5) % 16), idxLR = /* @__PURE__ */ (() => {
        let res = [[Id160], [Pi160]];
        for (let i = 0; i < 4; i++)
          for (let j of res)
            j.push(j[i].map((k) => Rho160[k]));
        return res;
      })(), idxL = idxLR[0], idxR = idxLR[1], shifts160 = /* @__PURE__ */ [
        [11, 14, 15, 12, 5, 8, 7, 9, 11, 13, 14, 15, 6, 7, 9, 8],
        [12, 13, 11, 15, 6, 9, 9, 7, 12, 15, 11, 13, 7, 8, 7, 7],
        [13, 15, 14, 11, 7, 7, 6, 8, 13, 14, 13, 12, 5, 5, 6, 9],
        [14, 11, 12, 14, 8, 6, 5, 5, 15, 12, 15, 14, 9, 9, 8, 6],
        [15, 12, 13, 13, 9, 5, 8, 6, 14, 11, 12, 11, 8, 6, 5, 5]
      ].map((i) => Uint8Array.from(i)), shiftsL160 = /* @__PURE__ */ idxL.map((idx, i) => idx.map((j) => shifts160[i][j])), shiftsR160 = /* @__PURE__ */ idxR.map((idx, i) => idx.map((j) => shifts160[i][j])), Kl160 = /* @__PURE__ */ Uint32Array.from([
        0,
        1518500249,
        1859775393,
        2400959708,
        2840853838
      ]), Kr160 = /* @__PURE__ */ Uint32Array.from([
        1352829926,
        1548603684,
        1836072691,
        2053994217,
        0
      ]);
      function ripemd_f(group, x, y, z) {
        return group === 0 ? x ^ y ^ z : group === 1 ? x & y | ~x & z : group === 2 ? (x | ~y) ^ z : group === 3 ? x & z | y & ~z : x ^ (y | ~z);
      }
      var BUF_160 = /* @__PURE__ */ new Uint32Array(16), RIPEMD160 = class extends _md_ts_1.HashMD {
        constructor() {
          super(64, 20, 8, !0), this.h0 = 1732584193, this.h1 = -271733879, this.h2 = -1732584194, this.h3 = 271733878, this.h4 = -1009589776;
        }
        get() {
          let { h0, h1, h2, h3, h4 } = this;
          return [h0, h1, h2, h3, h4];
        }
        set(h0, h1, h2, h3, h4) {
          this.h0 = h0 | 0, this.h1 = h1 | 0, this.h2 = h2 | 0, this.h3 = h3 | 0, this.h4 = h4 | 0;
        }
        process(view, offset) {
          for (let i = 0; i < 16; i++, offset += 4)
            BUF_160[i] = view.getUint32(offset, !0);
          let al = this.h0 | 0, ar = al, bl = this.h1 | 0, br = bl, cl = this.h2 | 0, cr = cl, dl = this.h3 | 0, dr = dl, el = this.h4 | 0, er = el;
          for (let group = 0; group < 5; group++) {
            let rGroup = 4 - group, hbl = Kl160[group], hbr = Kr160[group], rl = idxL[group], rr = idxR[group], sl = shiftsL160[group], sr = shiftsR160[group];
            for (let i = 0; i < 16; i++) {
              let tl = (0, utils_ts_1.rotl)(al + ripemd_f(group, bl, cl, dl) + BUF_160[rl[i]] + hbl, sl[i]) + el | 0;
              al = el, el = dl, dl = (0, utils_ts_1.rotl)(cl, 10) | 0, cl = bl, bl = tl;
            }
            for (let i = 0; i < 16; i++) {
              let tr = (0, utils_ts_1.rotl)(ar + ripemd_f(rGroup, br, cr, dr) + BUF_160[rr[i]] + hbr, sr[i]) + er | 0;
              ar = er, er = dr, dr = (0, utils_ts_1.rotl)(cr, 10) | 0, cr = br, br = tr;
            }
          }
          this.set(this.h1 + cl + dr | 0, this.h2 + dl + er | 0, this.h3 + el + ar | 0, this.h4 + al + br | 0, this.h0 + bl + cr | 0);
        }
        roundClean() {
          (0, utils_ts_1.clean)(BUF_160);
        }
        destroy() {
          this.destroyed = !0, (0, utils_ts_1.clean)(this.buffer), this.set(0, 0, 0, 0, 0);
        }
      };
      exports.RIPEMD160 = RIPEMD160;
      exports.ripemd160 = (0, utils_ts_1.createHasher)(() => new RIPEMD160());
    }
  });

  // node_modules/@noble/hashes/ripemd160.js
  var require_ripemd160 = __commonJS({
    "node_modules/@noble/hashes/ripemd160.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      exports.ripemd160 = exports.RIPEMD160 = void 0;
      var legacy_ts_1 = require_legacy();
      exports.RIPEMD160 = legacy_ts_1.RIPEMD160;
      exports.ripemd160 = legacy_ts_1.ripemd160;
    }
  });

  // node_modules/@noble/hashes/sha1.js
  var require_sha1 = __commonJS({
    "node_modules/@noble/hashes/sha1.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      exports.sha1 = exports.SHA1 = void 0;
      var legacy_ts_1 = require_legacy();
      exports.SHA1 = legacy_ts_1.SHA1;
      exports.sha1 = legacy_ts_1.sha1;
    }
  });

  // node_modules/@noble/hashes/_u64.js
  var require_u64 = __commonJS({
    "node_modules/@noble/hashes/_u64.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      exports.toBig = exports.shrSL = exports.shrSH = exports.rotrSL = exports.rotrSH = exports.rotrBL = exports.rotrBH = exports.rotr32L = exports.rotr32H = exports.rotlSL = exports.rotlSH = exports.rotlBL = exports.rotlBH = exports.add5L = exports.add5H = exports.add4L = exports.add4H = exports.add3L = exports.add3H = void 0;
      exports.add = add;
      exports.fromBig = fromBig;
      exports.split = split;
      var U32_MASK64 = /* @__PURE__ */ BigInt(2 ** 32 - 1), _32n = /* @__PURE__ */ BigInt(32);
      function fromBig(n, le = !1) {
        return le ? { h: Number(n & U32_MASK64), l: Number(n >> _32n & U32_MASK64) } : { h: Number(n >> _32n & U32_MASK64) | 0, l: Number(n & U32_MASK64) | 0 };
      }
      function split(lst, le = !1) {
        let len = lst.length, Ah = new Uint32Array(len), Al = new Uint32Array(len);
        for (let i = 0; i < len; i++) {
          let { h, l } = fromBig(lst[i], le);
          [Ah[i], Al[i]] = [h, l];
        }
        return [Ah, Al];
      }
      var toBig = (h, l) => BigInt(h >>> 0) << _32n | BigInt(l >>> 0);
      exports.toBig = toBig;
      var shrSH = (h, _l, s) => h >>> s;
      exports.shrSH = shrSH;
      var shrSL = (h, l, s) => h << 32 - s | l >>> s;
      exports.shrSL = shrSL;
      var rotrSH = (h, l, s) => h >>> s | l << 32 - s;
      exports.rotrSH = rotrSH;
      var rotrSL = (h, l, s) => h << 32 - s | l >>> s;
      exports.rotrSL = rotrSL;
      var rotrBH = (h, l, s) => h << 64 - s | l >>> s - 32;
      exports.rotrBH = rotrBH;
      var rotrBL = (h, l, s) => h >>> s - 32 | l << 64 - s;
      exports.rotrBL = rotrBL;
      var rotr32H = (_h, l) => l;
      exports.rotr32H = rotr32H;
      var rotr32L = (h, _l) => h;
      exports.rotr32L = rotr32L;
      var rotlSH = (h, l, s) => h << s | l >>> 32 - s;
      exports.rotlSH = rotlSH;
      var rotlSL = (h, l, s) => l << s | h >>> 32 - s;
      exports.rotlSL = rotlSL;
      var rotlBH = (h, l, s) => l << s - 32 | h >>> 64 - s;
      exports.rotlBH = rotlBH;
      var rotlBL = (h, l, s) => h << s - 32 | l >>> 64 - s;
      exports.rotlBL = rotlBL;
      function add(Ah, Al, Bh, Bl) {
        let l = (Al >>> 0) + (Bl >>> 0);
        return { h: Ah + Bh + (l / 2 ** 32 | 0) | 0, l: l | 0 };
      }
      var add3L = (Al, Bl, Cl) => (Al >>> 0) + (Bl >>> 0) + (Cl >>> 0);
      exports.add3L = add3L;
      var add3H = (low, Ah, Bh, Ch) => Ah + Bh + Ch + (low / 2 ** 32 | 0) | 0;
      exports.add3H = add3H;
      var add4L = (Al, Bl, Cl, Dl) => (Al >>> 0) + (Bl >>> 0) + (Cl >>> 0) + (Dl >>> 0);
      exports.add4L = add4L;
      var add4H = (low, Ah, Bh, Ch, Dh) => Ah + Bh + Ch + Dh + (low / 2 ** 32 | 0) | 0;
      exports.add4H = add4H;
      var add5L = (Al, Bl, Cl, Dl, El) => (Al >>> 0) + (Bl >>> 0) + (Cl >>> 0) + (Dl >>> 0) + (El >>> 0);
      exports.add5L = add5L;
      var add5H = (low, Ah, Bh, Ch, Dh, Eh) => Ah + Bh + Ch + Dh + Eh + (low / 2 ** 32 | 0) | 0;
      exports.add5H = add5H;
      var u64 = {
        fromBig,
        split,
        toBig,
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
    }
  });

  // node_modules/@noble/hashes/sha2.js
  var require_sha2 = __commonJS({
    "node_modules/@noble/hashes/sha2.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      exports.sha512_224 = exports.sha512_256 = exports.sha384 = exports.sha512 = exports.sha224 = exports.sha256 = exports.SHA512_256 = exports.SHA512_224 = exports.SHA384 = exports.SHA512 = exports.SHA224 = exports.SHA256 = void 0;
      var _md_ts_1 = require_md(), u64 = require_u64(), utils_ts_1 = require_utils(), SHA256_K = /* @__PURE__ */ Uint32Array.from([
        1116352408,
        1899447441,
        3049323471,
        3921009573,
        961987163,
        1508970993,
        2453635748,
        2870763221,
        3624381080,
        310598401,
        607225278,
        1426881987,
        1925078388,
        2162078206,
        2614888103,
        3248222580,
        3835390401,
        4022224774,
        264347078,
        604807628,
        770255983,
        1249150122,
        1555081692,
        1996064986,
        2554220882,
        2821834349,
        2952996808,
        3210313671,
        3336571891,
        3584528711,
        113926993,
        338241895,
        666307205,
        773529912,
        1294757372,
        1396182291,
        1695183700,
        1986661051,
        2177026350,
        2456956037,
        2730485921,
        2820302411,
        3259730800,
        3345764771,
        3516065817,
        3600352804,
        4094571909,
        275423344,
        430227734,
        506948616,
        659060556,
        883997877,
        958139571,
        1322822218,
        1537002063,
        1747873779,
        1955562222,
        2024104815,
        2227730452,
        2361852424,
        2428436474,
        2756734187,
        3204031479,
        3329325298
      ]), SHA256_W = /* @__PURE__ */ new Uint32Array(64), SHA256 = class extends _md_ts_1.HashMD {
        constructor(outputLen = 32) {
          super(64, outputLen, 8, !1), this.A = _md_ts_1.SHA256_IV[0] | 0, this.B = _md_ts_1.SHA256_IV[1] | 0, this.C = _md_ts_1.SHA256_IV[2] | 0, this.D = _md_ts_1.SHA256_IV[3] | 0, this.E = _md_ts_1.SHA256_IV[4] | 0, this.F = _md_ts_1.SHA256_IV[5] | 0, this.G = _md_ts_1.SHA256_IV[6] | 0, this.H = _md_ts_1.SHA256_IV[7] | 0;
        }
        get() {
          let { A, B, C, D, E, F, G, H } = this;
          return [A, B, C, D, E, F, G, H];
        }
        // prettier-ignore
        set(A, B, C, D, E, F, G, H) {
          this.A = A | 0, this.B = B | 0, this.C = C | 0, this.D = D | 0, this.E = E | 0, this.F = F | 0, this.G = G | 0, this.H = H | 0;
        }
        process(view, offset) {
          for (let i = 0; i < 16; i++, offset += 4)
            SHA256_W[i] = view.getUint32(offset, !1);
          for (let i = 16; i < 64; i++) {
            let W15 = SHA256_W[i - 15], W2 = SHA256_W[i - 2], s0 = (0, utils_ts_1.rotr)(W15, 7) ^ (0, utils_ts_1.rotr)(W15, 18) ^ W15 >>> 3, s1 = (0, utils_ts_1.rotr)(W2, 17) ^ (0, utils_ts_1.rotr)(W2, 19) ^ W2 >>> 10;
            SHA256_W[i] = s1 + SHA256_W[i - 7] + s0 + SHA256_W[i - 16] | 0;
          }
          let { A, B, C, D, E, F, G, H } = this;
          for (let i = 0; i < 64; i++) {
            let sigma1 = (0, utils_ts_1.rotr)(E, 6) ^ (0, utils_ts_1.rotr)(E, 11) ^ (0, utils_ts_1.rotr)(E, 25), T1 = H + sigma1 + (0, _md_ts_1.Chi)(E, F, G) + SHA256_K[i] + SHA256_W[i] | 0, T2 = ((0, utils_ts_1.rotr)(A, 2) ^ (0, utils_ts_1.rotr)(A, 13) ^ (0, utils_ts_1.rotr)(A, 22)) + (0, _md_ts_1.Maj)(A, B, C) | 0;
            H = G, G = F, F = E, E = D + T1 | 0, D = C, C = B, B = A, A = T1 + T2 | 0;
          }
          A = A + this.A | 0, B = B + this.B | 0, C = C + this.C | 0, D = D + this.D | 0, E = E + this.E | 0, F = F + this.F | 0, G = G + this.G | 0, H = H + this.H | 0, this.set(A, B, C, D, E, F, G, H);
        }
        roundClean() {
          (0, utils_ts_1.clean)(SHA256_W);
        }
        destroy() {
          this.set(0, 0, 0, 0, 0, 0, 0, 0), (0, utils_ts_1.clean)(this.buffer);
        }
      };
      exports.SHA256 = SHA256;
      var SHA224 = class extends SHA256 {
        constructor() {
          super(28), this.A = _md_ts_1.SHA224_IV[0] | 0, this.B = _md_ts_1.SHA224_IV[1] | 0, this.C = _md_ts_1.SHA224_IV[2] | 0, this.D = _md_ts_1.SHA224_IV[3] | 0, this.E = _md_ts_1.SHA224_IV[4] | 0, this.F = _md_ts_1.SHA224_IV[5] | 0, this.G = _md_ts_1.SHA224_IV[6] | 0, this.H = _md_ts_1.SHA224_IV[7] | 0;
        }
      };
      exports.SHA224 = SHA224;
      var K512 = u64.split([
        "0x428a2f98d728ae22",
        "0x7137449123ef65cd",
        "0xb5c0fbcfec4d3b2f",
        "0xe9b5dba58189dbbc",
        "0x3956c25bf348b538",
        "0x59f111f1b605d019",
        "0x923f82a4af194f9b",
        "0xab1c5ed5da6d8118",
        "0xd807aa98a3030242",
        "0x12835b0145706fbe",
        "0x243185be4ee4b28c",
        "0x550c7dc3d5ffb4e2",
        "0x72be5d74f27b896f",
        "0x80deb1fe3b1696b1",
        "0x9bdc06a725c71235",
        "0xc19bf174cf692694",
        "0xe49b69c19ef14ad2",
        "0xefbe4786384f25e3",
        "0x0fc19dc68b8cd5b5",
        "0x240ca1cc77ac9c65",
        "0x2de92c6f592b0275",
        "0x4a7484aa6ea6e483",
        "0x5cb0a9dcbd41fbd4",
        "0x76f988da831153b5",
        "0x983e5152ee66dfab",
        "0xa831c66d2db43210",
        "0xb00327c898fb213f",
        "0xbf597fc7beef0ee4",
        "0xc6e00bf33da88fc2",
        "0xd5a79147930aa725",
        "0x06ca6351e003826f",
        "0x142929670a0e6e70",
        "0x27b70a8546d22ffc",
        "0x2e1b21385c26c926",
        "0x4d2c6dfc5ac42aed",
        "0x53380d139d95b3df",
        "0x650a73548baf63de",
        "0x766a0abb3c77b2a8",
        "0x81c2c92e47edaee6",
        "0x92722c851482353b",
        "0xa2bfe8a14cf10364",
        "0xa81a664bbc423001",
        "0xc24b8b70d0f89791",
        "0xc76c51a30654be30",
        "0xd192e819d6ef5218",
        "0xd69906245565a910",
        "0xf40e35855771202a",
        "0x106aa07032bbd1b8",
        "0x19a4c116b8d2d0c8",
        "0x1e376c085141ab53",
        "0x2748774cdf8eeb99",
        "0x34b0bcb5e19b48a8",
        "0x391c0cb3c5c95a63",
        "0x4ed8aa4ae3418acb",
        "0x5b9cca4f7763e373",
        "0x682e6ff3d6b2b8a3",
        "0x748f82ee5defb2fc",
        "0x78a5636f43172f60",
        "0x84c87814a1f0ab72",
        "0x8cc702081a6439ec",
        "0x90befffa23631e28",
        "0xa4506cebde82bde9",
        "0xbef9a3f7b2c67915",
        "0xc67178f2e372532b",
        "0xca273eceea26619c",
        "0xd186b8c721c0c207",
        "0xeada7dd6cde0eb1e",
        "0xf57d4f7fee6ed178",
        "0x06f067aa72176fba",
        "0x0a637dc5a2c898a6",
        "0x113f9804bef90dae",
        "0x1b710b35131c471b",
        "0x28db77f523047d84",
        "0x32caab7b40c72493",
        "0x3c9ebe0a15c9bebc",
        "0x431d67c49c100d4c",
        "0x4cc5d4becb3e42b6",
        "0x597f299cfc657e2a",
        "0x5fcb6fab3ad6faec",
        "0x6c44198c4a475817"
      ].map((n) => BigInt(n))), SHA512_Kh = K512[0], SHA512_Kl = K512[1], SHA512_W_H = /* @__PURE__ */ new Uint32Array(80), SHA512_W_L = /* @__PURE__ */ new Uint32Array(80), SHA512 = class extends _md_ts_1.HashMD {
        constructor(outputLen = 64) {
          super(128, outputLen, 16, !1), this.Ah = _md_ts_1.SHA512_IV[0] | 0, this.Al = _md_ts_1.SHA512_IV[1] | 0, this.Bh = _md_ts_1.SHA512_IV[2] | 0, this.Bl = _md_ts_1.SHA512_IV[3] | 0, this.Ch = _md_ts_1.SHA512_IV[4] | 0, this.Cl = _md_ts_1.SHA512_IV[5] | 0, this.Dh = _md_ts_1.SHA512_IV[6] | 0, this.Dl = _md_ts_1.SHA512_IV[7] | 0, this.Eh = _md_ts_1.SHA512_IV[8] | 0, this.El = _md_ts_1.SHA512_IV[9] | 0, this.Fh = _md_ts_1.SHA512_IV[10] | 0, this.Fl = _md_ts_1.SHA512_IV[11] | 0, this.Gh = _md_ts_1.SHA512_IV[12] | 0, this.Gl = _md_ts_1.SHA512_IV[13] | 0, this.Hh = _md_ts_1.SHA512_IV[14] | 0, this.Hl = _md_ts_1.SHA512_IV[15] | 0;
        }
        // prettier-ignore
        get() {
          let { Ah, Al, Bh, Bl, Ch, Cl, Dh, Dl, Eh, El, Fh, Fl, Gh, Gl, Hh, Hl } = this;
          return [Ah, Al, Bh, Bl, Ch, Cl, Dh, Dl, Eh, El, Fh, Fl, Gh, Gl, Hh, Hl];
        }
        // prettier-ignore
        set(Ah, Al, Bh, Bl, Ch, Cl, Dh, Dl, Eh, El, Fh, Fl, Gh, Gl, Hh, Hl) {
          this.Ah = Ah | 0, this.Al = Al | 0, this.Bh = Bh | 0, this.Bl = Bl | 0, this.Ch = Ch | 0, this.Cl = Cl | 0, this.Dh = Dh | 0, this.Dl = Dl | 0, this.Eh = Eh | 0, this.El = El | 0, this.Fh = Fh | 0, this.Fl = Fl | 0, this.Gh = Gh | 0, this.Gl = Gl | 0, this.Hh = Hh | 0, this.Hl = Hl | 0;
        }
        process(view, offset) {
          for (let i = 0; i < 16; i++, offset += 4)
            SHA512_W_H[i] = view.getUint32(offset), SHA512_W_L[i] = view.getUint32(offset += 4);
          for (let i = 16; i < 80; i++) {
            let W15h = SHA512_W_H[i - 15] | 0, W15l = SHA512_W_L[i - 15] | 0, s0h = u64.rotrSH(W15h, W15l, 1) ^ u64.rotrSH(W15h, W15l, 8) ^ u64.shrSH(W15h, W15l, 7), s0l = u64.rotrSL(W15h, W15l, 1) ^ u64.rotrSL(W15h, W15l, 8) ^ u64.shrSL(W15h, W15l, 7), W2h = SHA512_W_H[i - 2] | 0, W2l = SHA512_W_L[i - 2] | 0, s1h = u64.rotrSH(W2h, W2l, 19) ^ u64.rotrBH(W2h, W2l, 61) ^ u64.shrSH(W2h, W2l, 6), s1l = u64.rotrSL(W2h, W2l, 19) ^ u64.rotrBL(W2h, W2l, 61) ^ u64.shrSL(W2h, W2l, 6), SUMl = u64.add4L(s0l, s1l, SHA512_W_L[i - 7], SHA512_W_L[i - 16]), SUMh = u64.add4H(SUMl, s0h, s1h, SHA512_W_H[i - 7], SHA512_W_H[i - 16]);
            SHA512_W_H[i] = SUMh | 0, SHA512_W_L[i] = SUMl | 0;
          }
          let { Ah, Al, Bh, Bl, Ch, Cl, Dh, Dl, Eh, El, Fh, Fl, Gh, Gl, Hh, Hl } = this;
          for (let i = 0; i < 80; i++) {
            let sigma1h = u64.rotrSH(Eh, El, 14) ^ u64.rotrSH(Eh, El, 18) ^ u64.rotrBH(Eh, El, 41), sigma1l = u64.rotrSL(Eh, El, 14) ^ u64.rotrSL(Eh, El, 18) ^ u64.rotrBL(Eh, El, 41), CHIh = Eh & Fh ^ ~Eh & Gh, CHIl = El & Fl ^ ~El & Gl, T1ll = u64.add5L(Hl, sigma1l, CHIl, SHA512_Kl[i], SHA512_W_L[i]), T1h = u64.add5H(T1ll, Hh, sigma1h, CHIh, SHA512_Kh[i], SHA512_W_H[i]), T1l = T1ll | 0, sigma0h = u64.rotrSH(Ah, Al, 28) ^ u64.rotrBH(Ah, Al, 34) ^ u64.rotrBH(Ah, Al, 39), sigma0l = u64.rotrSL(Ah, Al, 28) ^ u64.rotrBL(Ah, Al, 34) ^ u64.rotrBL(Ah, Al, 39), MAJh = Ah & Bh ^ Ah & Ch ^ Bh & Ch, MAJl = Al & Bl ^ Al & Cl ^ Bl & Cl;
            Hh = Gh | 0, Hl = Gl | 0, Gh = Fh | 0, Gl = Fl | 0, Fh = Eh | 0, Fl = El | 0, { h: Eh, l: El } = u64.add(Dh | 0, Dl | 0, T1h | 0, T1l | 0), Dh = Ch | 0, Dl = Cl | 0, Ch = Bh | 0, Cl = Bl | 0, Bh = Ah | 0, Bl = Al | 0;
            let All = u64.add3L(T1l, sigma0l, MAJl);
            Ah = u64.add3H(All, T1h, sigma0h, MAJh), Al = All | 0;
          }
          ({ h: Ah, l: Al } = u64.add(this.Ah | 0, this.Al | 0, Ah | 0, Al | 0)), { h: Bh, l: Bl } = u64.add(this.Bh | 0, this.Bl | 0, Bh | 0, Bl | 0), { h: Ch, l: Cl } = u64.add(this.Ch | 0, this.Cl | 0, Ch | 0, Cl | 0), { h: Dh, l: Dl } = u64.add(this.Dh | 0, this.Dl | 0, Dh | 0, Dl | 0), { h: Eh, l: El } = u64.add(this.Eh | 0, this.El | 0, Eh | 0, El | 0), { h: Fh, l: Fl } = u64.add(this.Fh | 0, this.Fl | 0, Fh | 0, Fl | 0), { h: Gh, l: Gl } = u64.add(this.Gh | 0, this.Gl | 0, Gh | 0, Gl | 0), { h: Hh, l: Hl } = u64.add(this.Hh | 0, this.Hl | 0, Hh | 0, Hl | 0), this.set(Ah, Al, Bh, Bl, Ch, Cl, Dh, Dl, Eh, El, Fh, Fl, Gh, Gl, Hh, Hl);
        }
        roundClean() {
          (0, utils_ts_1.clean)(SHA512_W_H, SHA512_W_L);
        }
        destroy() {
          (0, utils_ts_1.clean)(this.buffer), this.set(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
        }
      };
      exports.SHA512 = SHA512;
      var SHA384 = class extends SHA512 {
        constructor() {
          super(48), this.Ah = _md_ts_1.SHA384_IV[0] | 0, this.Al = _md_ts_1.SHA384_IV[1] | 0, this.Bh = _md_ts_1.SHA384_IV[2] | 0, this.Bl = _md_ts_1.SHA384_IV[3] | 0, this.Ch = _md_ts_1.SHA384_IV[4] | 0, this.Cl = _md_ts_1.SHA384_IV[5] | 0, this.Dh = _md_ts_1.SHA384_IV[6] | 0, this.Dl = _md_ts_1.SHA384_IV[7] | 0, this.Eh = _md_ts_1.SHA384_IV[8] | 0, this.El = _md_ts_1.SHA384_IV[9] | 0, this.Fh = _md_ts_1.SHA384_IV[10] | 0, this.Fl = _md_ts_1.SHA384_IV[11] | 0, this.Gh = _md_ts_1.SHA384_IV[12] | 0, this.Gl = _md_ts_1.SHA384_IV[13] | 0, this.Hh = _md_ts_1.SHA384_IV[14] | 0, this.Hl = _md_ts_1.SHA384_IV[15] | 0;
        }
      };
      exports.SHA384 = SHA384;
      var T224_IV = /* @__PURE__ */ Uint32Array.from([
        2352822216,
        424955298,
        1944164710,
        2312950998,
        502970286,
        855612546,
        1738396948,
        1479516111,
        258812777,
        2077511080,
        2011393907,
        79989058,
        1067287976,
        1780299464,
        286451373,
        2446758561
      ]), T256_IV = /* @__PURE__ */ Uint32Array.from([
        573645204,
        4230739756,
        2673172387,
        3360449730,
        596883563,
        1867755857,
        2520282905,
        1497426621,
        2519219938,
        2827943907,
        3193839141,
        1401305490,
        721525244,
        746961066,
        246885852,
        2177182882
      ]), SHA512_224 = class extends SHA512 {
        constructor() {
          super(28), this.Ah = T224_IV[0] | 0, this.Al = T224_IV[1] | 0, this.Bh = T224_IV[2] | 0, this.Bl = T224_IV[3] | 0, this.Ch = T224_IV[4] | 0, this.Cl = T224_IV[5] | 0, this.Dh = T224_IV[6] | 0, this.Dl = T224_IV[7] | 0, this.Eh = T224_IV[8] | 0, this.El = T224_IV[9] | 0, this.Fh = T224_IV[10] | 0, this.Fl = T224_IV[11] | 0, this.Gh = T224_IV[12] | 0, this.Gl = T224_IV[13] | 0, this.Hh = T224_IV[14] | 0, this.Hl = T224_IV[15] | 0;
        }
      };
      exports.SHA512_224 = SHA512_224;
      var SHA512_256 = class extends SHA512 {
        constructor() {
          super(32), this.Ah = T256_IV[0] | 0, this.Al = T256_IV[1] | 0, this.Bh = T256_IV[2] | 0, this.Bl = T256_IV[3] | 0, this.Ch = T256_IV[4] | 0, this.Cl = T256_IV[5] | 0, this.Dh = T256_IV[6] | 0, this.Dl = T256_IV[7] | 0, this.Eh = T256_IV[8] | 0, this.El = T256_IV[9] | 0, this.Fh = T256_IV[10] | 0, this.Fl = T256_IV[11] | 0, this.Gh = T256_IV[12] | 0, this.Gl = T256_IV[13] | 0, this.Hh = T256_IV[14] | 0, this.Hl = T256_IV[15] | 0;
        }
      };
      exports.SHA512_256 = SHA512_256;
      exports.sha256 = (0, utils_ts_1.createHasher)(() => new SHA256());
      exports.sha224 = (0, utils_ts_1.createHasher)(() => new SHA224());
      exports.sha512 = (0, utils_ts_1.createHasher)(() => new SHA512());
      exports.sha384 = (0, utils_ts_1.createHasher)(() => new SHA384());
      exports.sha512_256 = (0, utils_ts_1.createHasher)(() => new SHA512_256());
      exports.sha512_224 = (0, utils_ts_1.createHasher)(() => new SHA512_224());
    }
  });

  // node_modules/@noble/hashes/sha256.js
  var require_sha256 = __commonJS({
    "node_modules/@noble/hashes/sha256.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      exports.sha224 = exports.SHA224 = exports.sha256 = exports.SHA256 = void 0;
      var sha2_ts_1 = require_sha2();
      exports.SHA256 = sha2_ts_1.SHA256;
      exports.sha256 = sha2_ts_1.sha256;
      exports.SHA224 = sha2_ts_1.SHA224;
      exports.sha224 = sha2_ts_1.sha224;
    }
  });

  // node_modules/bitcoinjs-lib/src/crypto.js
  var require_crypto2 = __commonJS({
    "node_modules/bitcoinjs-lib/src/crypto.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      exports.taggedHash = exports.TAGGED_HASH_PREFIXES = exports.TAGS = exports.hash256 = exports.hash160 = exports.sha256 = exports.sha1 = exports.ripemd160 = void 0;
      var ripemd160_1 = require_ripemd160(), sha1_1 = require_sha1(), sha256_1 = require_sha256();
      function ripemd160(buffer) {
        return import_buffer.Buffer.from((0, ripemd160_1.ripemd160)(Uint8Array.from(buffer)));
      }
      exports.ripemd160 = ripemd160;
      function sha1(buffer) {
        return import_buffer.Buffer.from((0, sha1_1.sha1)(Uint8Array.from(buffer)));
      }
      exports.sha1 = sha1;
      function sha256(buffer) {
        return import_buffer.Buffer.from((0, sha256_1.sha256)(Uint8Array.from(buffer)));
      }
      exports.sha256 = sha256;
      function hash160(buffer) {
        return import_buffer.Buffer.from(
          (0, ripemd160_1.ripemd160)((0, sha256_1.sha256)(Uint8Array.from(buffer)))
        );
      }
      exports.hash160 = hash160;
      function hash256(buffer) {
        return import_buffer.Buffer.from(
          (0, sha256_1.sha256)((0, sha256_1.sha256)(Uint8Array.from(buffer)))
        );
      }
      exports.hash256 = hash256;
      exports.TAGS = [
        "BIP0340/challenge",
        "BIP0340/aux",
        "BIP0340/nonce",
        "TapLeaf",
        "TapBranch",
        "TapSighash",
        "TapTweak",
        "KeyAgg list",
        "KeyAgg coefficient"
      ];
      exports.TAGGED_HASH_PREFIXES = {
        "BIP0340/challenge": import_buffer.Buffer.from([
          123,
          181,
          45,
          122,
          159,
          239,
          88,
          50,
          62,
          177,
          191,
          122,
          64,
          125,
          179,
          130,
          210,
          243,
          242,
          216,
          27,
          177,
          34,
          79,
          73,
          254,
          81,
          143,
          109,
          72,
          211,
          124,
          123,
          181,
          45,
          122,
          159,
          239,
          88,
          50,
          62,
          177,
          191,
          122,
          64,
          125,
          179,
          130,
          210,
          243,
          242,
          216,
          27,
          177,
          34,
          79,
          73,
          254,
          81,
          143,
          109,
          72,
          211,
          124
        ]),
        "BIP0340/aux": import_buffer.Buffer.from([
          241,
          239,
          78,
          94,
          192,
          99,
          202,
          218,
          109,
          148,
          202,
          250,
          157,
          152,
          126,
          160,
          105,
          38,
          88,
          57,
          236,
          193,
          31,
          151,
          45,
          119,
          165,
          46,
          216,
          193,
          204,
          144,
          241,
          239,
          78,
          94,
          192,
          99,
          202,
          218,
          109,
          148,
          202,
          250,
          157,
          152,
          126,
          160,
          105,
          38,
          88,
          57,
          236,
          193,
          31,
          151,
          45,
          119,
          165,
          46,
          216,
          193,
          204,
          144
        ]),
        "BIP0340/nonce": import_buffer.Buffer.from([
          7,
          73,
          119,
          52,
          167,
          155,
          203,
          53,
          91,
          155,
          140,
          125,
          3,
          79,
          18,
          28,
          244,
          52,
          215,
          62,
          247,
          45,
          218,
          25,
          135,
          0,
          97,
          251,
          82,
          191,
          235,
          47,
          7,
          73,
          119,
          52,
          167,
          155,
          203,
          53,
          91,
          155,
          140,
          125,
          3,
          79,
          18,
          28,
          244,
          52,
          215,
          62,
          247,
          45,
          218,
          25,
          135,
          0,
          97,
          251,
          82,
          191,
          235,
          47
        ]),
        TapLeaf: import_buffer.Buffer.from([
          174,
          234,
          143,
          220,
          66,
          8,
          152,
          49,
          5,
          115,
          75,
          88,
          8,
          29,
          30,
          38,
          56,
          211,
          95,
          28,
          181,
          64,
          8,
          212,
          211,
          87,
          202,
          3,
          190,
          120,
          233,
          238,
          174,
          234,
          143,
          220,
          66,
          8,
          152,
          49,
          5,
          115,
          75,
          88,
          8,
          29,
          30,
          38,
          56,
          211,
          95,
          28,
          181,
          64,
          8,
          212,
          211,
          87,
          202,
          3,
          190,
          120,
          233,
          238
        ]),
        TapBranch: import_buffer.Buffer.from([
          25,
          65,
          161,
          242,
          229,
          110,
          185,
          95,
          162,
          169,
          241,
          148,
          190,
          92,
          1,
          247,
          33,
          111,
          51,
          237,
          130,
          176,
          145,
          70,
          52,
          144,
          208,
          91,
          245,
          22,
          160,
          21,
          25,
          65,
          161,
          242,
          229,
          110,
          185,
          95,
          162,
          169,
          241,
          148,
          190,
          92,
          1,
          247,
          33,
          111,
          51,
          237,
          130,
          176,
          145,
          70,
          52,
          144,
          208,
          91,
          245,
          22,
          160,
          21
        ]),
        TapSighash: import_buffer.Buffer.from([
          244,
          10,
          72,
          223,
          75,
          42,
          112,
          200,
          180,
          146,
          75,
          242,
          101,
          70,
          97,
          237,
          61,
          149,
          253,
          102,
          163,
          19,
          235,
          135,
          35,
          117,
          151,
          198,
          40,
          228,
          160,
          49,
          244,
          10,
          72,
          223,
          75,
          42,
          112,
          200,
          180,
          146,
          75,
          242,
          101,
          70,
          97,
          237,
          61,
          149,
          253,
          102,
          163,
          19,
          235,
          135,
          35,
          117,
          151,
          198,
          40,
          228,
          160,
          49
        ]),
        TapTweak: import_buffer.Buffer.from([
          232,
          15,
          225,
          99,
          156,
          156,
          160,
          80,
          227,
          175,
          27,
          57,
          193,
          67,
          198,
          62,
          66,
          156,
          188,
          235,
          21,
          217,
          64,
          251,
          181,
          197,
          161,
          244,
          175,
          87,
          197,
          233,
          232,
          15,
          225,
          99,
          156,
          156,
          160,
          80,
          227,
          175,
          27,
          57,
          193,
          67,
          198,
          62,
          66,
          156,
          188,
          235,
          21,
          217,
          64,
          251,
          181,
          197,
          161,
          244,
          175,
          87,
          197,
          233
        ]),
        "KeyAgg list": import_buffer.Buffer.from([
          72,
          28,
          151,
          28,
          60,
          11,
          70,
          215,
          240,
          178,
          117,
          174,
          89,
          141,
          78,
          44,
          126,
          215,
          49,
          156,
          89,
          74,
          92,
          110,
          199,
          158,
          160,
          212,
          153,
          2,
          148,
          240,
          72,
          28,
          151,
          28,
          60,
          11,
          70,
          215,
          240,
          178,
          117,
          174,
          89,
          141,
          78,
          44,
          126,
          215,
          49,
          156,
          89,
          74,
          92,
          110,
          199,
          158,
          160,
          212,
          153,
          2,
          148,
          240
        ]),
        "KeyAgg coefficient": import_buffer.Buffer.from([
          191,
          201,
          4,
          3,
          77,
          28,
          136,
          232,
          200,
          14,
          34,
          229,
          61,
          36,
          86,
          109,
          100,
          130,
          78,
          214,
          66,
          114,
          129,
          192,
          145,
          0,
          249,
          77,
          205,
          82,
          201,
          129,
          191,
          201,
          4,
          3,
          77,
          28,
          136,
          232,
          200,
          14,
          34,
          229,
          61,
          36,
          86,
          109,
          100,
          130,
          78,
          214,
          66,
          114,
          129,
          192,
          145,
          0,
          249,
          77,
          205,
          82,
          201,
          129
        ])
      };
      function taggedHash(prefix, data) {
        return sha256(import_buffer.Buffer.concat([exports.TAGGED_HASH_PREFIXES[prefix], data]));
      }
      exports.taggedHash = taggedHash;
    }
  });

  // node_modules/base-x/src/index.js
  var require_src = __commonJS({
    "node_modules/base-x/src/index.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      function base(ALPHABET) {
        if (ALPHABET.length >= 255)
          throw new TypeError("Alphabet too long");
        for (var BASE_MAP = new Uint8Array(256), j = 0; j < BASE_MAP.length; j++)
          BASE_MAP[j] = 255;
        for (var i = 0; i < ALPHABET.length; i++) {
          var x = ALPHABET.charAt(i), xc = x.charCodeAt(0);
          if (BASE_MAP[xc] !== 255)
            throw new TypeError(x + " is ambiguous");
          BASE_MAP[xc] = i;
        }
        var BASE = ALPHABET.length, LEADER = ALPHABET.charAt(0), FACTOR = Math.log(BASE) / Math.log(256), iFACTOR = Math.log(256) / Math.log(BASE);
        function encode(source) {
          if (source instanceof Uint8Array || (ArrayBuffer.isView(source) ? source = new Uint8Array(source.buffer, source.byteOffset, source.byteLength) : Array.isArray(source) && (source = Uint8Array.from(source))), !(source instanceof Uint8Array))
            throw new TypeError("Expected Uint8Array");
          if (source.length === 0)
            return "";
          for (var zeroes = 0, length = 0, pbegin = 0, pend = source.length; pbegin !== pend && source[pbegin] === 0; )
            pbegin++, zeroes++;
          for (var size = (pend - pbegin) * iFACTOR + 1 >>> 0, b58 = new Uint8Array(size); pbegin !== pend; ) {
            for (var carry = source[pbegin], i2 = 0, it1 = size - 1; (carry !== 0 || i2 < length) && it1 !== -1; it1--, i2++)
              carry += 256 * b58[it1] >>> 0, b58[it1] = carry % BASE >>> 0, carry = carry / BASE >>> 0;
            if (carry !== 0)
              throw new Error("Non-zero carry");
            length = i2, pbegin++;
          }
          for (var it2 = size - length; it2 !== size && b58[it2] === 0; )
            it2++;
          for (var str = LEADER.repeat(zeroes); it2 < size; ++it2)
            str += ALPHABET.charAt(b58[it2]);
          return str;
        }
        function decodeUnsafe(source) {
          if (typeof source != "string")
            throw new TypeError("Expected String");
          if (source.length === 0)
            return new Uint8Array();
          for (var psz = 0, zeroes = 0, length = 0; source[psz] === LEADER; )
            zeroes++, psz++;
          for (var size = (source.length - psz) * FACTOR + 1 >>> 0, b256 = new Uint8Array(size); source[psz]; ) {
            var charCode = source.charCodeAt(psz);
            if (charCode > 255)
              return;
            var carry = BASE_MAP[charCode];
            if (carry === 255)
              return;
            for (var i2 = 0, it3 = size - 1; (carry !== 0 || i2 < length) && it3 !== -1; it3--, i2++)
              carry += BASE * b256[it3] >>> 0, b256[it3] = carry % 256 >>> 0, carry = carry / 256 >>> 0;
            if (carry !== 0)
              throw new Error("Non-zero carry");
            length = i2, psz++;
          }
          for (var it4 = size - length; it4 !== size && b256[it4] === 0; )
            it4++;
          for (var vch = new Uint8Array(zeroes + (size - it4)), j2 = zeroes; it4 !== size; )
            vch[j2++] = b256[it4++];
          return vch;
        }
        function decode(string) {
          var buffer = decodeUnsafe(string);
          if (buffer)
            return buffer;
          throw new Error("Non-base" + BASE + " character");
        }
        return {
          encode,
          decodeUnsafe,
          decode
        };
      }
      module.exports = base;
    }
  });

  // node_modules/bs58/index.js
  var require_bs58 = __commonJS({
    "node_modules/bs58/index.js"(exports, module) {
      init_buffer_shim();
      init_process_shim();
      var basex = require_src(), ALPHABET = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";
      module.exports = basex(ALPHABET);
    }
  });

  // node_modules/bs58check/base.js
  var require_base = __commonJS({
    "node_modules/bs58check/base.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      var base58 = require_bs58();
      module.exports = function(checksumFn) {
        function encode(payload) {
          var payloadU8 = Uint8Array.from(payload), checksum = checksumFn(payloadU8), length = payloadU8.length + 4, both = new Uint8Array(length);
          return both.set(payloadU8, 0), both.set(checksum.subarray(0, 4), payloadU8.length), base58.encode(both, length);
        }
        function decodeRaw(buffer) {
          var payload = buffer.slice(0, -4), checksum = buffer.slice(-4), newChecksum = checksumFn(payload);
          if (!(checksum[0] ^ newChecksum[0] | checksum[1] ^ newChecksum[1] | checksum[2] ^ newChecksum[2] | checksum[3] ^ newChecksum[3]))
            return payload;
        }
        function decodeUnsafe(string) {
          var buffer = base58.decodeUnsafe(string);
          if (buffer)
            return decodeRaw(buffer);
        }
        function decode(string) {
          var buffer = base58.decode(string), payload = decodeRaw(buffer, checksumFn);
          if (!payload) throw new Error("Invalid checksum");
          return payload;
        }
        return {
          encode,
          decode,
          decodeUnsafe
        };
      };
    }
  });

  // node_modules/bs58check/index.js
  var require_bs58check = __commonJS({
    "node_modules/bs58check/index.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      var { sha256 } = require_sha256(), bs58checkBase = require_base();
      function sha256x2(buffer) {
        return sha256(sha256(buffer));
      }
      module.exports = bs58checkBase(sha256x2);
    }
  });

  // node_modules/bitcoinjs-lib/src/payments/p2pkh.js
  var require_p2pkh = __commonJS({
    "node_modules/bitcoinjs-lib/src/payments/p2pkh.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      exports.p2pkh = void 0;
      var bcrypto = require_crypto2(), networks_1 = require_networks(), bscript = require_script(), types_1 = require_types(), lazy = require_lazy(), bs58check = require_bs58check(), OPS = bscript.OPS;
      function p2pkh(a, opts) {
        if (!a.address && !a.hash && !a.output && !a.pubkey && !a.input)
          throw new TypeError("Not enough data");
        opts = Object.assign({ validate: !0 }, opts || {}), (0, types_1.typeforce)(
          {
            network: types_1.typeforce.maybe(types_1.typeforce.Object),
            address: types_1.typeforce.maybe(types_1.typeforce.String),
            hash: types_1.typeforce.maybe(types_1.typeforce.BufferN(20)),
            output: types_1.typeforce.maybe(types_1.typeforce.BufferN(25)),
            pubkey: types_1.typeforce.maybe(types_1.isPoint),
            signature: types_1.typeforce.maybe(bscript.isCanonicalScriptSignature),
            input: types_1.typeforce.maybe(types_1.typeforce.Buffer)
          },
          a
        );
        let _address = lazy.value(() => {
          let payload = import_buffer.Buffer.from(bs58check.decode(a.address)), version = payload.readUInt8(0), hash = payload.slice(1);
          return { version, hash };
        }), _chunks = lazy.value(() => bscript.decompile(a.input)), network2 = a.network || networks_1.bitcoin, o = { name: "p2pkh", network: network2 };
        if (lazy.prop(o, "address", () => {
          if (!o.hash) return;
          let payload = import_buffer.Buffer.allocUnsafe(21);
          return payload.writeUInt8(network2.pubKeyHash, 0), o.hash.copy(payload, 1), bs58check.encode(payload);
        }), lazy.prop(o, "hash", () => {
          if (a.output) return a.output.slice(3, 23);
          if (a.address) return _address().hash;
          if (a.pubkey || o.pubkey) return bcrypto.hash160(a.pubkey || o.pubkey);
        }), lazy.prop(o, "output", () => {
          if (o.hash)
            return bscript.compile([
              OPS.OP_DUP,
              OPS.OP_HASH160,
              o.hash,
              OPS.OP_EQUALVERIFY,
              OPS.OP_CHECKSIG
            ]);
        }), lazy.prop(o, "pubkey", () => {
          if (a.input)
            return _chunks()[1];
        }), lazy.prop(o, "signature", () => {
          if (a.input)
            return _chunks()[0];
        }), lazy.prop(o, "input", () => {
          if (a.pubkey && a.signature)
            return bscript.compile([a.signature, a.pubkey]);
        }), lazy.prop(o, "witness", () => {
          if (o.input)
            return [];
        }), opts.validate) {
          let hash = import_buffer.Buffer.from([]);
          if (a.address) {
            if (_address().version !== network2.pubKeyHash)
              throw new TypeError("Invalid version or Network mismatch");
            if (_address().hash.length !== 20) throw new TypeError("Invalid address");
            hash = _address().hash;
          }
          if (a.hash) {
            if (hash.length > 0 && !hash.equals(a.hash))
              throw new TypeError("Hash mismatch");
            hash = a.hash;
          }
          if (a.output) {
            if (a.output.length !== 25 || a.output[0] !== OPS.OP_DUP || a.output[1] !== OPS.OP_HASH160 || a.output[2] !== 20 || a.output[23] !== OPS.OP_EQUALVERIFY || a.output[24] !== OPS.OP_CHECKSIG)
              throw new TypeError("Output is invalid");
            let hash2 = a.output.slice(3, 23);
            if (hash.length > 0 && !hash.equals(hash2))
              throw new TypeError("Hash mismatch");
            hash = hash2;
          }
          if (a.pubkey) {
            let pkh = bcrypto.hash160(a.pubkey);
            if (hash.length > 0 && !hash.equals(pkh))
              throw new TypeError("Hash mismatch");
            hash = pkh;
          }
          if (a.input) {
            let chunks = _chunks();
            if (chunks.length !== 2) throw new TypeError("Input is invalid");
            if (!bscript.isCanonicalScriptSignature(chunks[0]))
              throw new TypeError("Input has invalid signature");
            if (!(0, types_1.isPoint)(chunks[1]))
              throw new TypeError("Input has invalid pubkey");
            if (a.signature && !a.signature.equals(chunks[0]))
              throw new TypeError("Signature mismatch");
            if (a.pubkey && !a.pubkey.equals(chunks[1]))
              throw new TypeError("Pubkey mismatch");
            let pkh = bcrypto.hash160(chunks[1]);
            if (hash.length > 0 && !hash.equals(pkh))
              throw new TypeError("Hash mismatch");
          }
        }
        return Object.assign(o, a);
      }
      exports.p2pkh = p2pkh;
    }
  });

  // node_modules/bitcoinjs-lib/src/payments/p2sh.js
  var require_p2sh = __commonJS({
    "node_modules/bitcoinjs-lib/src/payments/p2sh.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      exports.p2sh = void 0;
      var bcrypto = require_crypto2(), networks_1 = require_networks(), bscript = require_script(), types_1 = require_types(), lazy = require_lazy(), bs58check = require_bs58check(), OPS = bscript.OPS;
      function p2sh(a, opts) {
        if (!a.address && !a.hash && !a.output && !a.redeem && !a.input)
          throw new TypeError("Not enough data");
        opts = Object.assign({ validate: !0 }, opts || {}), (0, types_1.typeforce)(
          {
            network: types_1.typeforce.maybe(types_1.typeforce.Object),
            address: types_1.typeforce.maybe(types_1.typeforce.String),
            hash: types_1.typeforce.maybe(types_1.typeforce.BufferN(20)),
            output: types_1.typeforce.maybe(types_1.typeforce.BufferN(23)),
            redeem: types_1.typeforce.maybe({
              network: types_1.typeforce.maybe(types_1.typeforce.Object),
              output: types_1.typeforce.maybe(types_1.typeforce.Buffer),
              input: types_1.typeforce.maybe(types_1.typeforce.Buffer),
              witness: types_1.typeforce.maybe(
                types_1.typeforce.arrayOf(types_1.typeforce.Buffer)
              )
            }),
            input: types_1.typeforce.maybe(types_1.typeforce.Buffer),
            witness: types_1.typeforce.maybe(
              types_1.typeforce.arrayOf(types_1.typeforce.Buffer)
            )
          },
          a
        );
        let network2 = a.network;
        network2 || (network2 = a.redeem && a.redeem.network || networks_1.bitcoin);
        let o = { network: network2 }, _address = lazy.value(() => {
          let payload = import_buffer.Buffer.from(bs58check.decode(a.address)), version = payload.readUInt8(0), hash = payload.slice(1);
          return { version, hash };
        }), _chunks = lazy.value(() => bscript.decompile(a.input)), _redeem = lazy.value(() => {
          let chunks = _chunks(), lastChunk = chunks[chunks.length - 1];
          return {
            network: network2,
            output: lastChunk === OPS.OP_FALSE ? import_buffer.Buffer.from([]) : lastChunk,
            input: bscript.compile(chunks.slice(0, -1)),
            witness: a.witness || []
          };
        });
        if (lazy.prop(o, "address", () => {
          if (!o.hash) return;
          let payload = import_buffer.Buffer.allocUnsafe(21);
          return payload.writeUInt8(o.network.scriptHash, 0), o.hash.copy(payload, 1), bs58check.encode(payload);
        }), lazy.prop(o, "hash", () => {
          if (a.output) return a.output.slice(2, 22);
          if (a.address) return _address().hash;
          if (o.redeem && o.redeem.output) return bcrypto.hash160(o.redeem.output);
        }), lazy.prop(o, "output", () => {
          if (o.hash)
            return bscript.compile([OPS.OP_HASH160, o.hash, OPS.OP_EQUAL]);
        }), lazy.prop(o, "redeem", () => {
          if (a.input)
            return _redeem();
        }), lazy.prop(o, "input", () => {
          if (!(!a.redeem || !a.redeem.input || !a.redeem.output))
            return bscript.compile(
              [].concat(bscript.decompile(a.redeem.input), a.redeem.output)
            );
        }), lazy.prop(o, "witness", () => {
          if (o.redeem && o.redeem.witness) return o.redeem.witness;
          if (o.input) return [];
        }), lazy.prop(o, "name", () => {
          let nameParts = ["p2sh"];
          return o.redeem !== void 0 && o.redeem.name !== void 0 && nameParts.push(o.redeem.name), nameParts.join("-");
        }), opts.validate) {
          let hash = import_buffer.Buffer.from([]);
          if (a.address) {
            if (_address().version !== network2.scriptHash)
              throw new TypeError("Invalid version or Network mismatch");
            if (_address().hash.length !== 20) throw new TypeError("Invalid address");
            hash = _address().hash;
          }
          if (a.hash) {
            if (hash.length > 0 && !hash.equals(a.hash))
              throw new TypeError("Hash mismatch");
            hash = a.hash;
          }
          if (a.output) {
            if (a.output.length !== 23 || a.output[0] !== OPS.OP_HASH160 || a.output[1] !== 20 || a.output[22] !== OPS.OP_EQUAL)
              throw new TypeError("Output is invalid");
            let hash2 = a.output.slice(2, 22);
            if (hash.length > 0 && !hash.equals(hash2))
              throw new TypeError("Hash mismatch");
            hash = hash2;
          }
          let checkRedeem = (redeem) => {
            if (redeem.output) {
              let decompile = bscript.decompile(redeem.output);
              if (!decompile || decompile.length < 1)
                throw new TypeError("Redeem.output too short");
              if (redeem.output.byteLength > 520)
                throw new TypeError(
                  "Redeem.output unspendable if larger than 520 bytes"
                );
              if (bscript.countNonPushOnlyOPs(decompile) > 201)
                throw new TypeError(
                  "Redeem.output unspendable with more than 201 non-push ops"
                );
              let hash2 = bcrypto.hash160(redeem.output);
              if (hash.length > 0 && !hash.equals(hash2))
                throw new TypeError("Hash mismatch");
              hash = hash2;
            }
            if (redeem.input) {
              let hasInput = redeem.input.length > 0, hasWitness = redeem.witness && redeem.witness.length > 0;
              if (!hasInput && !hasWitness) throw new TypeError("Empty input");
              if (hasInput && hasWitness)
                throw new TypeError("Input and witness provided");
              if (hasInput) {
                let richunks = bscript.decompile(redeem.input);
                if (!bscript.isPushOnly(richunks))
                  throw new TypeError("Non push-only scriptSig");
              }
            }
          };
          if (a.input) {
            let chunks = _chunks();
            if (!chunks || chunks.length < 1) throw new TypeError("Input too short");
            if (!import_buffer.Buffer.isBuffer(_redeem().output))
              throw new TypeError("Input is invalid");
            checkRedeem(_redeem());
          }
          if (a.redeem) {
            if (a.redeem.network && a.redeem.network !== network2)
              throw new TypeError("Network mismatch");
            if (a.input) {
              let redeem = _redeem();
              if (a.redeem.output && !a.redeem.output.equals(redeem.output))
                throw new TypeError("Redeem.output mismatch");
              if (a.redeem.input && !a.redeem.input.equals(redeem.input))
                throw new TypeError("Redeem.input mismatch");
            }
            checkRedeem(a.redeem);
          }
          if (a.witness && a.redeem && a.redeem.witness && !(0, types_1.stacksEqual)(a.redeem.witness, a.witness))
            throw new TypeError("Witness and redeem.witness mismatch");
        }
        return Object.assign(o, a);
      }
      exports.p2sh = p2sh;
    }
  });

  // node_modules/bech32/dist/index.js
  var require_dist = __commonJS({
    "node_modules/bech32/dist/index.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      exports.bech32m = exports.bech32 = void 0;
      var ALPHABET = "qpzry9x8gf2tvdw0s3jn54khce6mua7l", ALPHABET_MAP = {};
      for (let z = 0; z < ALPHABET.length; z++) {
        let x = ALPHABET.charAt(z);
        ALPHABET_MAP[x] = z;
      }
      function polymodStep(pre) {
        let b = pre >> 25;
        return (pre & 33554431) << 5 ^ -(b >> 0 & 1) & 996825010 ^ -(b >> 1 & 1) & 642813549 ^ -(b >> 2 & 1) & 513874426 ^ -(b >> 3 & 1) & 1027748829 ^ -(b >> 4 & 1) & 705979059;
      }
      function prefixChk(prefix) {
        let chk = 1;
        for (let i = 0; i < prefix.length; ++i) {
          let c = prefix.charCodeAt(i);
          if (c < 33 || c > 126)
            return "Invalid prefix (" + prefix + ")";
          chk = polymodStep(chk) ^ c >> 5;
        }
        chk = polymodStep(chk);
        for (let i = 0; i < prefix.length; ++i) {
          let v = prefix.charCodeAt(i);
          chk = polymodStep(chk) ^ v & 31;
        }
        return chk;
      }
      function convert(data, inBits, outBits, pad) {
        let value = 0, bits = 0, maxV = (1 << outBits) - 1, result = [];
        for (let i = 0; i < data.length; ++i)
          for (value = value << inBits | data[i], bits += inBits; bits >= outBits; )
            bits -= outBits, result.push(value >> bits & maxV);
        if (pad)
          bits > 0 && result.push(value << outBits - bits & maxV);
        else {
          if (bits >= inBits)
            return "Excess padding";
          if (value << outBits - bits & maxV)
            return "Non-zero padding";
        }
        return result;
      }
      function toWords(bytes) {
        return convert(bytes, 8, 5, !0);
      }
      function fromWordsUnsafe(words) {
        let res = convert(words, 5, 8, !1);
        if (Array.isArray(res))
          return res;
      }
      function fromWords(words) {
        let res = convert(words, 5, 8, !1);
        if (Array.isArray(res))
          return res;
        throw new Error(res);
      }
      function getLibraryFromEncoding(encoding) {
        let ENCODING_CONST;
        encoding === "bech32" ? ENCODING_CONST = 1 : ENCODING_CONST = 734539939;
        function encode(prefix, words, LIMIT) {
          if (LIMIT = LIMIT || 90, prefix.length + 7 + words.length > LIMIT)
            throw new TypeError("Exceeds length limit");
          prefix = prefix.toLowerCase();
          let chk = prefixChk(prefix);
          if (typeof chk == "string")
            throw new Error(chk);
          let result = prefix + "1";
          for (let i = 0; i < words.length; ++i) {
            let x = words[i];
            if (x >> 5 !== 0)
              throw new Error("Non 5-bit word");
            chk = polymodStep(chk) ^ x, result += ALPHABET.charAt(x);
          }
          for (let i = 0; i < 6; ++i)
            chk = polymodStep(chk);
          chk ^= ENCODING_CONST;
          for (let i = 0; i < 6; ++i) {
            let v = chk >> (5 - i) * 5 & 31;
            result += ALPHABET.charAt(v);
          }
          return result;
        }
        function __decode(str, LIMIT) {
          if (LIMIT = LIMIT || 90, str.length < 8)
            return str + " too short";
          if (str.length > LIMIT)
            return "Exceeds length limit";
          let lowered = str.toLowerCase(), uppered = str.toUpperCase();
          if (str !== lowered && str !== uppered)
            return "Mixed-case string " + str;
          str = lowered;
          let split = str.lastIndexOf("1");
          if (split === -1)
            return "No separator character for " + str;
          if (split === 0)
            return "Missing prefix for " + str;
          let prefix = str.slice(0, split), wordChars = str.slice(split + 1);
          if (wordChars.length < 6)
            return "Data too short";
          let chk = prefixChk(prefix);
          if (typeof chk == "string")
            return chk;
          let words = [];
          for (let i = 0; i < wordChars.length; ++i) {
            let c = wordChars.charAt(i), v = ALPHABET_MAP[c];
            if (v === void 0)
              return "Unknown character " + c;
            chk = polymodStep(chk) ^ v, !(i + 6 >= wordChars.length) && words.push(v);
          }
          return chk !== ENCODING_CONST ? "Invalid checksum for " + str : { prefix, words };
        }
        function decodeUnsafe(str, LIMIT) {
          let res = __decode(str, LIMIT);
          if (typeof res == "object")
            return res;
        }
        function decode(str, LIMIT) {
          let res = __decode(str, LIMIT);
          if (typeof res == "object")
            return res;
          throw new Error(res);
        }
        return {
          decodeUnsafe,
          decode,
          encode,
          toWords,
          fromWordsUnsafe,
          fromWords
        };
      }
      exports.bech32 = getLibraryFromEncoding("bech32");
      exports.bech32m = getLibraryFromEncoding("bech32m");
    }
  });

  // node_modules/bitcoinjs-lib/src/payments/p2wpkh.js
  var require_p2wpkh = __commonJS({
    "node_modules/bitcoinjs-lib/src/payments/p2wpkh.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      exports.p2wpkh = void 0;
      var bcrypto = require_crypto2(), networks_1 = require_networks(), bscript = require_script(), types_1 = require_types(), lazy = require_lazy(), bech32_1 = require_dist(), OPS = bscript.OPS, EMPTY_BUFFER = import_buffer.Buffer.alloc(0);
      function p2wpkh(a, opts) {
        if (!a.address && !a.hash && !a.output && !a.pubkey && !a.witness)
          throw new TypeError("Not enough data");
        opts = Object.assign({ validate: !0 }, opts || {}), (0, types_1.typeforce)(
          {
            address: types_1.typeforce.maybe(types_1.typeforce.String),
            hash: types_1.typeforce.maybe(types_1.typeforce.BufferN(20)),
            input: types_1.typeforce.maybe(types_1.typeforce.BufferN(0)),
            network: types_1.typeforce.maybe(types_1.typeforce.Object),
            output: types_1.typeforce.maybe(types_1.typeforce.BufferN(22)),
            pubkey: types_1.typeforce.maybe(types_1.isPoint),
            signature: types_1.typeforce.maybe(bscript.isCanonicalScriptSignature),
            witness: types_1.typeforce.maybe(
              types_1.typeforce.arrayOf(types_1.typeforce.Buffer)
            )
          },
          a
        );
        let _address = lazy.value(() => {
          let result = bech32_1.bech32.decode(a.address), version = result.words.shift(), data = bech32_1.bech32.fromWords(result.words);
          return {
            version,
            prefix: result.prefix,
            data: import_buffer.Buffer.from(data)
          };
        }), network2 = a.network || networks_1.bitcoin, o = { name: "p2wpkh", network: network2 };
        if (lazy.prop(o, "address", () => {
          if (!o.hash) return;
          let words = bech32_1.bech32.toWords(o.hash);
          return words.unshift(0), bech32_1.bech32.encode(network2.bech32, words);
        }), lazy.prop(o, "hash", () => {
          if (a.output) return a.output.slice(2, 22);
          if (a.address) return _address().data;
          if (a.pubkey || o.pubkey) return bcrypto.hash160(a.pubkey || o.pubkey);
        }), lazy.prop(o, "output", () => {
          if (o.hash)
            return bscript.compile([OPS.OP_0, o.hash]);
        }), lazy.prop(o, "pubkey", () => {
          if (a.pubkey) return a.pubkey;
          if (a.witness)
            return a.witness[1];
        }), lazy.prop(o, "signature", () => {
          if (a.witness)
            return a.witness[0];
        }), lazy.prop(o, "input", () => {
          if (o.witness)
            return EMPTY_BUFFER;
        }), lazy.prop(o, "witness", () => {
          if (a.pubkey && a.signature)
            return [a.signature, a.pubkey];
        }), opts.validate) {
          let hash = import_buffer.Buffer.from([]);
          if (a.address) {
            if (network2 && network2.bech32 !== _address().prefix)
              throw new TypeError("Invalid prefix or Network mismatch");
            if (_address().version !== 0)
              throw new TypeError("Invalid address version");
            if (_address().data.length !== 20)
              throw new TypeError("Invalid address data");
            hash = _address().data;
          }
          if (a.hash) {
            if (hash.length > 0 && !hash.equals(a.hash))
              throw new TypeError("Hash mismatch");
            hash = a.hash;
          }
          if (a.output) {
            if (a.output.length !== 22 || a.output[0] !== OPS.OP_0 || a.output[1] !== 20)
              throw new TypeError("Output is invalid");
            if (hash.length > 0 && !hash.equals(a.output.slice(2)))
              throw new TypeError("Hash mismatch");
            hash = a.output.slice(2);
          }
          if (a.pubkey) {
            let pkh = bcrypto.hash160(a.pubkey);
            if (hash.length > 0 && !hash.equals(pkh))
              throw new TypeError("Hash mismatch");
            if (hash = pkh, !(0, types_1.isPoint)(a.pubkey) || a.pubkey.length !== 33)
              throw new TypeError("Invalid pubkey for p2wpkh");
          }
          if (a.witness) {
            if (a.witness.length !== 2) throw new TypeError("Witness is invalid");
            if (!bscript.isCanonicalScriptSignature(a.witness[0]))
              throw new TypeError("Witness has invalid signature");
            if (!(0, types_1.isPoint)(a.witness[1]) || a.witness[1].length !== 33)
              throw new TypeError("Witness has invalid pubkey");
            if (a.signature && !a.signature.equals(a.witness[0]))
              throw new TypeError("Signature mismatch");
            if (a.pubkey && !a.pubkey.equals(a.witness[1]))
              throw new TypeError("Pubkey mismatch");
            let pkh = bcrypto.hash160(a.witness[1]);
            if (hash.length > 0 && !hash.equals(pkh))
              throw new TypeError("Hash mismatch");
          }
        }
        return Object.assign(o, a);
      }
      exports.p2wpkh = p2wpkh;
    }
  });

  // node_modules/bitcoinjs-lib/src/payments/p2wsh.js
  var require_p2wsh = __commonJS({
    "node_modules/bitcoinjs-lib/src/payments/p2wsh.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      exports.p2wsh = void 0;
      var bcrypto = require_crypto2(), networks_1 = require_networks(), bscript = require_script(), types_1 = require_types(), lazy = require_lazy(), bech32_1 = require_dist(), OPS = bscript.OPS, EMPTY_BUFFER = import_buffer.Buffer.alloc(0);
      function chunkHasUncompressedPubkey(chunk) {
        return !!(import_buffer.Buffer.isBuffer(chunk) && chunk.length === 65 && chunk[0] === 4 && (0, types_1.isPoint)(chunk));
      }
      function p2wsh(a, opts) {
        if (!a.address && !a.hash && !a.output && !a.redeem && !a.witness)
          throw new TypeError("Not enough data");
        opts = Object.assign({ validate: !0 }, opts || {}), (0, types_1.typeforce)(
          {
            network: types_1.typeforce.maybe(types_1.typeforce.Object),
            address: types_1.typeforce.maybe(types_1.typeforce.String),
            hash: types_1.typeforce.maybe(types_1.typeforce.BufferN(32)),
            output: types_1.typeforce.maybe(types_1.typeforce.BufferN(34)),
            redeem: types_1.typeforce.maybe({
              input: types_1.typeforce.maybe(types_1.typeforce.Buffer),
              network: types_1.typeforce.maybe(types_1.typeforce.Object),
              output: types_1.typeforce.maybe(types_1.typeforce.Buffer),
              witness: types_1.typeforce.maybe(
                types_1.typeforce.arrayOf(types_1.typeforce.Buffer)
              )
            }),
            input: types_1.typeforce.maybe(types_1.typeforce.BufferN(0)),
            witness: types_1.typeforce.maybe(
              types_1.typeforce.arrayOf(types_1.typeforce.Buffer)
            )
          },
          a
        );
        let _address = lazy.value(() => {
          let result = bech32_1.bech32.decode(a.address), version = result.words.shift(), data = bech32_1.bech32.fromWords(result.words);
          return {
            version,
            prefix: result.prefix,
            data: import_buffer.Buffer.from(data)
          };
        }), _rchunks = lazy.value(() => bscript.decompile(a.redeem.input)), network2 = a.network;
        network2 || (network2 = a.redeem && a.redeem.network || networks_1.bitcoin);
        let o = { network: network2 };
        if (lazy.prop(o, "address", () => {
          if (!o.hash) return;
          let words = bech32_1.bech32.toWords(o.hash);
          return words.unshift(0), bech32_1.bech32.encode(network2.bech32, words);
        }), lazy.prop(o, "hash", () => {
          if (a.output) return a.output.slice(2);
          if (a.address) return _address().data;
          if (o.redeem && o.redeem.output) return bcrypto.sha256(o.redeem.output);
        }), lazy.prop(o, "output", () => {
          if (o.hash)
            return bscript.compile([OPS.OP_0, o.hash]);
        }), lazy.prop(o, "redeem", () => {
          if (a.witness)
            return {
              output: a.witness[a.witness.length - 1],
              input: EMPTY_BUFFER,
              witness: a.witness.slice(0, -1)
            };
        }), lazy.prop(o, "input", () => {
          if (o.witness)
            return EMPTY_BUFFER;
        }), lazy.prop(o, "witness", () => {
          if (a.redeem && a.redeem.input && a.redeem.input.length > 0 && a.redeem.output && a.redeem.output.length > 0) {
            let stack = bscript.toStack(_rchunks());
            return o.redeem = Object.assign({ witness: stack }, a.redeem), o.redeem.input = EMPTY_BUFFER, [].concat(stack, a.redeem.output);
          }
          if (a.redeem && a.redeem.output && a.redeem.witness)
            return [].concat(a.redeem.witness, a.redeem.output);
        }), lazy.prop(o, "name", () => {
          let nameParts = ["p2wsh"];
          return o.redeem !== void 0 && o.redeem.name !== void 0 && nameParts.push(o.redeem.name), nameParts.join("-");
        }), opts.validate) {
          let hash = import_buffer.Buffer.from([]);
          if (a.address) {
            if (_address().prefix !== network2.bech32)
              throw new TypeError("Invalid prefix or Network mismatch");
            if (_address().version !== 0)
              throw new TypeError("Invalid address version");
            if (_address().data.length !== 32)
              throw new TypeError("Invalid address data");
            hash = _address().data;
          }
          if (a.hash) {
            if (hash.length > 0 && !hash.equals(a.hash))
              throw new TypeError("Hash mismatch");
            hash = a.hash;
          }
          if (a.output) {
            if (a.output.length !== 34 || a.output[0] !== OPS.OP_0 || a.output[1] !== 32)
              throw new TypeError("Output is invalid");
            let hash2 = a.output.slice(2);
            if (hash.length > 0 && !hash.equals(hash2))
              throw new TypeError("Hash mismatch");
            hash = hash2;
          }
          if (a.redeem) {
            if (a.redeem.network && a.redeem.network !== network2)
              throw new TypeError("Network mismatch");
            if (a.redeem.input && a.redeem.input.length > 0 && a.redeem.witness && a.redeem.witness.length > 0)
              throw new TypeError("Ambiguous witness source");
            if (a.redeem.output) {
              let decompile = bscript.decompile(a.redeem.output);
              if (!decompile || decompile.length < 1)
                throw new TypeError("Redeem.output is invalid");
              if (a.redeem.output.byteLength > 3600)
                throw new TypeError(
                  "Redeem.output unspendable if larger than 3600 bytes"
                );
              if (bscript.countNonPushOnlyOPs(decompile) > 201)
                throw new TypeError(
                  "Redeem.output unspendable with more than 201 non-push ops"
                );
              let hash2 = bcrypto.sha256(a.redeem.output);
              if (hash.length > 0 && !hash.equals(hash2))
                throw new TypeError("Hash mismatch");
              hash = hash2;
            }
            if (a.redeem.input && !bscript.isPushOnly(_rchunks()))
              throw new TypeError("Non push-only scriptSig");
            if (a.witness && a.redeem.witness && !(0, types_1.stacksEqual)(a.witness, a.redeem.witness))
              throw new TypeError("Witness and redeem.witness mismatch");
            if (a.redeem.input && _rchunks().some(chunkHasUncompressedPubkey) || a.redeem.output && (bscript.decompile(a.redeem.output) || []).some(
              chunkHasUncompressedPubkey
            ))
              throw new TypeError(
                "redeem.input or redeem.output contains uncompressed pubkey"
              );
          }
          if (a.witness && a.witness.length > 0) {
            let wScript = a.witness[a.witness.length - 1];
            if (a.redeem && a.redeem.output && !a.redeem.output.equals(wScript))
              throw new TypeError("Witness and redeem.output mismatch");
            if (a.witness.some(chunkHasUncompressedPubkey) || (bscript.decompile(wScript) || []).some(chunkHasUncompressedPubkey))
              throw new TypeError("Witness contains uncompressed pubkey");
          }
        }
        return Object.assign(o, a);
      }
      exports.p2wsh = p2wsh;
    }
  });

  // node_modules/bitcoinjs-lib/src/ecc_lib.js
  var require_ecc_lib = __commonJS({
    "node_modules/bitcoinjs-lib/src/ecc_lib.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      exports.getEccLib = exports.initEccLib = void 0;
      var _ECCLIB_CACHE = {};
      function initEccLib2(eccLib, opts) {
        eccLib ? eccLib !== _ECCLIB_CACHE.eccLib && (opts?.DANGER_DO_NOT_VERIFY_ECCLIB || verifyEcc(eccLib), _ECCLIB_CACHE.eccLib = eccLib) : _ECCLIB_CACHE.eccLib = eccLib;
      }
      exports.initEccLib = initEccLib2;
      function getEccLib() {
        if (!_ECCLIB_CACHE.eccLib)
          throw new Error(
            "No ECC Library provided. You must call initEccLib() with a valid TinySecp256k1Interface instance"
          );
        return _ECCLIB_CACHE.eccLib;
      }
      exports.getEccLib = getEccLib;
      var h = (hex) => import_buffer.Buffer.from(hex, "hex");
      function verifyEcc(ecc2) {
        assert(typeof ecc2.isXOnlyPoint == "function"), assert(
          ecc2.isXOnlyPoint(
            h("79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798")
          )
        ), assert(
          ecc2.isXOnlyPoint(
            h("fffffffffffffffffffffffffffffffffffffffffffffffffffffffeeffffc2e")
          )
        ), assert(
          ecc2.isXOnlyPoint(
            h("f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9")
          )
        ), assert(
          ecc2.isXOnlyPoint(
            h("0000000000000000000000000000000000000000000000000000000000000001")
          )
        ), assert(
          !ecc2.isXOnlyPoint(
            h("0000000000000000000000000000000000000000000000000000000000000000")
          )
        ), assert(
          !ecc2.isXOnlyPoint(
            h("fffffffffffffffffffffffffffffffffffffffffffffffffffffffefffffc2f")
          )
        ), assert(typeof ecc2.xOnlyPointAddTweak == "function"), tweakAddVectors.forEach((t) => {
          let r = ecc2.xOnlyPointAddTweak(h(t.pubkey), h(t.tweak));
          t.result === null ? assert(r === null) : (assert(r !== null), assert(r.parity === t.parity), assert(import_buffer.Buffer.from(r.xOnlyPubkey).equals(h(t.result))));
        });
      }
      function assert(bool) {
        if (!bool) throw new Error("ecc library invalid");
      }
      var tweakAddVectors = [
        {
          pubkey: "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798",
          tweak: "fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364140",
          parity: -1,
          result: null
        },
        {
          pubkey: "1617d38ed8d8657da4d4761e8057bc396ea9e4b9d29776d4be096016dbd2509b",
          tweak: "a8397a935f0dfceba6ba9618f6451ef4d80637abf4e6af2669fbc9de6a8fd2ac",
          parity: 1,
          result: "e478f99dab91052ab39a33ea35fd5e6e4933f4d28023cd597c9a1f6760346adf"
        },
        {
          pubkey: "2c0b7cf95324a07d05398b240174dc0c2be444d96b159aa6c7f7b1e668680991",
          tweak: "823c3cd2142744b075a87eade7e1b8678ba308d566226a0056ca2b7a76f86b47",
          parity: 0,
          result: "9534f8dc8c6deda2dc007655981c78b49c5d96c778fbf363462a11ec9dfd948c"
        }
      ];
    }
  });

  // node_modules/safe-buffer/index.js
  var require_safe_buffer = __commonJS({
    "node_modules/safe-buffer/index.js"(exports, module) {
      init_buffer_shim();
      init_process_shim();
      var buffer = require_buffer(), Buffer4 = buffer.Buffer;
      function copyProps(src, dst) {
        for (var key in src)
          dst[key] = src[key];
      }
      Buffer4.from && Buffer4.alloc && Buffer4.allocUnsafe && Buffer4.allocUnsafeSlow ? module.exports = buffer : (copyProps(buffer, exports), exports.Buffer = SafeBuffer);
      function SafeBuffer(arg, encodingOrOffset, length) {
        return Buffer4(arg, encodingOrOffset, length);
      }
      SafeBuffer.prototype = Object.create(Buffer4.prototype);
      copyProps(Buffer4, SafeBuffer);
      SafeBuffer.from = function(arg, encodingOrOffset, length) {
        if (typeof arg == "number")
          throw new TypeError("Argument must not be a number");
        return Buffer4(arg, encodingOrOffset, length);
      };
      SafeBuffer.alloc = function(size, fill, encoding) {
        if (typeof size != "number")
          throw new TypeError("Argument must be a number");
        var buf = Buffer4(size);
        return fill !== void 0 ? typeof encoding == "string" ? buf.fill(fill, encoding) : buf.fill(fill) : buf.fill(0), buf;
      };
      SafeBuffer.allocUnsafe = function(size) {
        if (typeof size != "number")
          throw new TypeError("Argument must be a number");
        return Buffer4(size);
      };
      SafeBuffer.allocUnsafeSlow = function(size) {
        if (typeof size != "number")
          throw new TypeError("Argument must be a number");
        return buffer.SlowBuffer(size);
      };
    }
  });

  // node_modules/varuint-bitcoin/index.js
  var require_varuint_bitcoin = __commonJS({
    "node_modules/varuint-bitcoin/index.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      var Buffer4 = require_safe_buffer().Buffer, MAX_SAFE_INTEGER = 9007199254740991;
      function checkUInt53(n) {
        if (n < 0 || n > MAX_SAFE_INTEGER || n % 1 !== 0) throw new RangeError("value out of range");
      }
      function encode(number, buffer, offset) {
        if (checkUInt53(number), buffer || (buffer = Buffer4.allocUnsafe(encodingLength(number))), !Buffer4.isBuffer(buffer)) throw new TypeError("buffer must be a Buffer instance");
        return offset || (offset = 0), number < 253 ? (buffer.writeUInt8(number, offset), encode.bytes = 1) : number <= 65535 ? (buffer.writeUInt8(253, offset), buffer.writeUInt16LE(number, offset + 1), encode.bytes = 3) : number <= 4294967295 ? (buffer.writeUInt8(254, offset), buffer.writeUInt32LE(number, offset + 1), encode.bytes = 5) : (buffer.writeUInt8(255, offset), buffer.writeUInt32LE(number >>> 0, offset + 1), buffer.writeUInt32LE(number / 4294967296 | 0, offset + 5), encode.bytes = 9), buffer;
      }
      function decode(buffer, offset) {
        if (!Buffer4.isBuffer(buffer)) throw new TypeError("buffer must be a Buffer instance");
        offset || (offset = 0);
        var first = buffer.readUInt8(offset);
        if (first < 253)
          return decode.bytes = 1, first;
        if (first === 253)
          return decode.bytes = 3, buffer.readUInt16LE(offset + 1);
        if (first === 254)
          return decode.bytes = 5, buffer.readUInt32LE(offset + 1);
        decode.bytes = 9;
        var lo = buffer.readUInt32LE(offset + 1), hi = buffer.readUInt32LE(offset + 5), number = hi * 4294967296 + lo;
        return checkUInt53(number), number;
      }
      function encodingLength(number) {
        return checkUInt53(number), number < 253 ? 1 : number <= 65535 ? 3 : number <= 4294967295 ? 5 : 9;
      }
      module.exports = { encode, decode, encodingLength };
    }
  });

  // node_modules/bitcoinjs-lib/src/bufferutils.js
  var require_bufferutils = __commonJS({
    "node_modules/bitcoinjs-lib/src/bufferutils.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      exports.BufferReader = exports.BufferWriter = exports.cloneBuffer = exports.reverseBuffer = exports.writeUInt64LE = exports.readUInt64LE = exports.varuint = void 0;
      var types = require_types(), { typeforce } = types, varuint = require_varuint_bitcoin();
      exports.varuint = varuint;
      function verifuint(value, max) {
        if (typeof value != "number")
          throw new Error("cannot write a non-number as a number");
        if (value < 0)
          throw new Error("specified a negative value for writing an unsigned value");
        if (value > max) throw new Error("RangeError: value out of range");
        if (Math.floor(value) !== value)
          throw new Error("value has a fractional component");
      }
      function readUInt64LE(buffer, offset) {
        let a = buffer.readUInt32LE(offset), b = buffer.readUInt32LE(offset + 4);
        return b *= 4294967296, verifuint(b + a, 9007199254740991), b + a;
      }
      exports.readUInt64LE = readUInt64LE;
      function writeUInt64LE(buffer, value, offset) {
        return verifuint(value, 9007199254740991), buffer.writeInt32LE(value & -1, offset), buffer.writeUInt32LE(Math.floor(value / 4294967296), offset + 4), offset + 8;
      }
      exports.writeUInt64LE = writeUInt64LE;
      function reverseBuffer(buffer) {
        if (buffer.length < 1) return buffer;
        let j = buffer.length - 1, tmp = 0;
        for (let i = 0; i < buffer.length / 2; i++)
          tmp = buffer[i], buffer[i] = buffer[j], buffer[j] = tmp, j--;
        return buffer;
      }
      exports.reverseBuffer = reverseBuffer;
      function cloneBuffer(buffer) {
        let clone = import_buffer.Buffer.allocUnsafe(buffer.length);
        return buffer.copy(clone), clone;
      }
      exports.cloneBuffer = cloneBuffer;
      var BufferWriter = class _BufferWriter {
        static withCapacity(size) {
          return new _BufferWriter(import_buffer.Buffer.alloc(size));
        }
        constructor(buffer, offset = 0) {
          this.buffer = buffer, this.offset = offset, typeforce(types.tuple(types.Buffer, types.UInt32), [buffer, offset]);
        }
        writeUInt8(i) {
          this.offset = this.buffer.writeUInt8(i, this.offset);
        }
        writeInt32(i) {
          this.offset = this.buffer.writeInt32LE(i, this.offset);
        }
        writeUInt32(i) {
          this.offset = this.buffer.writeUInt32LE(i, this.offset);
        }
        writeUInt64(i) {
          this.offset = writeUInt64LE(this.buffer, i, this.offset);
        }
        writeVarInt(i) {
          varuint.encode(i, this.buffer, this.offset), this.offset += varuint.encode.bytes;
        }
        writeSlice(slice) {
          if (this.buffer.length < this.offset + slice.length)
            throw new Error("Cannot write slice out of bounds");
          this.offset += slice.copy(this.buffer, this.offset);
        }
        writeVarSlice(slice) {
          this.writeVarInt(slice.length), this.writeSlice(slice);
        }
        writeVector(vector) {
          this.writeVarInt(vector.length), vector.forEach((buf) => this.writeVarSlice(buf));
        }
        end() {
          if (this.buffer.length === this.offset)
            return this.buffer;
          throw new Error(`buffer size ${this.buffer.length}, offset ${this.offset}`);
        }
      };
      exports.BufferWriter = BufferWriter;
      var BufferReader = class {
        constructor(buffer, offset = 0) {
          this.buffer = buffer, this.offset = offset, typeforce(types.tuple(types.Buffer, types.UInt32), [buffer, offset]);
        }
        readUInt8() {
          let result = this.buffer.readUInt8(this.offset);
          return this.offset++, result;
        }
        readInt32() {
          let result = this.buffer.readInt32LE(this.offset);
          return this.offset += 4, result;
        }
        readUInt32() {
          let result = this.buffer.readUInt32LE(this.offset);
          return this.offset += 4, result;
        }
        readUInt64() {
          let result = readUInt64LE(this.buffer, this.offset);
          return this.offset += 8, result;
        }
        readVarInt() {
          let vi = varuint.decode(this.buffer, this.offset);
          return this.offset += varuint.decode.bytes, vi;
        }
        readSlice(n) {
          if (this.buffer.length < this.offset + n)
            throw new Error("Cannot read slice out of bounds");
          let result = this.buffer.slice(this.offset, this.offset + n);
          return this.offset += n, result;
        }
        readVarSlice() {
          return this.readSlice(this.readVarInt());
        }
        readVector() {
          let count = this.readVarInt(), vector = [];
          for (let i = 0; i < count; i++) vector.push(this.readVarSlice());
          return vector;
        }
      };
      exports.BufferReader = BufferReader;
    }
  });

  // node_modules/bitcoinjs-lib/src/payments/bip341.js
  var require_bip341 = __commonJS({
    "node_modules/bitcoinjs-lib/src/payments/bip341.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      exports.tweakKey = exports.tapTweakHash = exports.tapleafHash = exports.findScriptPath = exports.toHashTree = exports.rootHashFromPath = exports.MAX_TAPTREE_DEPTH = exports.LEAF_VERSION_TAPSCRIPT = void 0;
      var buffer_1 = require_buffer(), ecc_lib_1 = require_ecc_lib(), bcrypto = require_crypto2(), bufferutils_1 = require_bufferutils(), types_1 = require_types();
      exports.LEAF_VERSION_TAPSCRIPT = 192;
      exports.MAX_TAPTREE_DEPTH = 128;
      var isHashBranch = (ht) => "left" in ht && "right" in ht;
      function rootHashFromPath(controlBlock, leafHash) {
        if (controlBlock.length < 33)
          throw new TypeError(
            `The control-block length is too small. Got ${controlBlock.length}, expected min 33.`
          );
        let m = (controlBlock.length - 33) / 32, kj = leafHash;
        for (let j = 0; j < m; j++) {
          let ej = controlBlock.slice(33 + 32 * j, 65 + 32 * j);
          kj.compare(ej) < 0 ? kj = tapBranchHash(kj, ej) : kj = tapBranchHash(ej, kj);
        }
        return kj;
      }
      exports.rootHashFromPath = rootHashFromPath;
      function toHashTree(scriptTree) {
        if ((0, types_1.isTapleaf)(scriptTree))
          return { hash: tapleafHash(scriptTree) };
        let hashes = [toHashTree(scriptTree[0]), toHashTree(scriptTree[1])];
        hashes.sort((a, b) => a.hash.compare(b.hash));
        let [left, right] = hashes;
        return {
          hash: tapBranchHash(left.hash, right.hash),
          left,
          right
        };
      }
      exports.toHashTree = toHashTree;
      function findScriptPath(node, hash) {
        if (isHashBranch(node)) {
          let leftPath = findScriptPath(node.left, hash);
          if (leftPath !== void 0) return [...leftPath, node.right.hash];
          let rightPath = findScriptPath(node.right, hash);
          if (rightPath !== void 0) return [...rightPath, node.left.hash];
        } else if (node.hash.equals(hash))
          return [];
      }
      exports.findScriptPath = findScriptPath;
      function tapleafHash(leaf) {
        let version = leaf.version || exports.LEAF_VERSION_TAPSCRIPT;
        return bcrypto.taggedHash(
          "TapLeaf",
          buffer_1.Buffer.concat([
            buffer_1.Buffer.from([version]),
            serializeScript(leaf.output)
          ])
        );
      }
      exports.tapleafHash = tapleafHash;
      function tapTweakHash(pubKey, h) {
        return bcrypto.taggedHash(
          "TapTweak",
          buffer_1.Buffer.concat(h ? [pubKey, h] : [pubKey])
        );
      }
      exports.tapTweakHash = tapTweakHash;
      function tweakKey(pubKey, h) {
        if (!buffer_1.Buffer.isBuffer(pubKey) || pubKey.length !== 32 || h && h.length !== 32) return null;
        let tweakHash = tapTweakHash(pubKey, h), res = (0, ecc_lib_1.getEccLib)().xOnlyPointAddTweak(pubKey, tweakHash);
        return !res || res.xOnlyPubkey === null ? null : {
          parity: res.parity,
          x: buffer_1.Buffer.from(res.xOnlyPubkey)
        };
      }
      exports.tweakKey = tweakKey;
      function tapBranchHash(a, b) {
        return bcrypto.taggedHash("TapBranch", buffer_1.Buffer.concat([a, b]));
      }
      function serializeScript(s) {
        let varintLen = bufferutils_1.varuint.encodingLength(s.length), buffer = buffer_1.Buffer.allocUnsafe(varintLen);
        return bufferutils_1.varuint.encode(s.length, buffer), buffer_1.Buffer.concat([buffer, s]);
      }
    }
  });

  // node_modules/bitcoinjs-lib/src/payments/p2tr.js
  var require_p2tr = __commonJS({
    "node_modules/bitcoinjs-lib/src/payments/p2tr.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      exports.p2tr = void 0;
      var buffer_1 = require_buffer(), networks_1 = require_networks(), bscript = require_script(), types_1 = require_types(), ecc_lib_1 = require_ecc_lib(), bip341_1 = require_bip341(), lazy = require_lazy(), bech32_1 = require_dist(), address_1 = require_address(), OPS = bscript.OPS, TAPROOT_WITNESS_VERSION = 1, ANNEX_PREFIX = 80;
      function p2tr(a, opts) {
        if (!a.address && !a.output && !a.pubkey && !a.internalPubkey && !(a.witness && a.witness.length > 1))
          throw new TypeError("Not enough data");
        opts = Object.assign({ validate: !0 }, opts || {}), (0, types_1.typeforce)(
          {
            address: types_1.typeforce.maybe(types_1.typeforce.String),
            input: types_1.typeforce.maybe(types_1.typeforce.BufferN(0)),
            network: types_1.typeforce.maybe(types_1.typeforce.Object),
            output: types_1.typeforce.maybe(types_1.typeforce.BufferN(34)),
            internalPubkey: types_1.typeforce.maybe(types_1.typeforce.BufferN(32)),
            hash: types_1.typeforce.maybe(types_1.typeforce.BufferN(32)),
            pubkey: types_1.typeforce.maybe(types_1.typeforce.BufferN(32)),
            signature: types_1.typeforce.maybe(
              types_1.typeforce.anyOf(
                types_1.typeforce.BufferN(64),
                types_1.typeforce.BufferN(65)
              )
            ),
            witness: types_1.typeforce.maybe(
              types_1.typeforce.arrayOf(types_1.typeforce.Buffer)
            ),
            scriptTree: types_1.typeforce.maybe(types_1.isTaptree),
            redeem: types_1.typeforce.maybe({
              output: types_1.typeforce.maybe(types_1.typeforce.Buffer),
              redeemVersion: types_1.typeforce.maybe(types_1.typeforce.Number),
              witness: types_1.typeforce.maybe(
                types_1.typeforce.arrayOf(types_1.typeforce.Buffer)
              )
            }),
            redeemVersion: types_1.typeforce.maybe(types_1.typeforce.Number)
          },
          a
        );
        let _address = lazy.value(() => (0, address_1.fromBech32)(a.address)), _witness = lazy.value(() => {
          if (!(!a.witness || !a.witness.length))
            return a.witness.length >= 2 && a.witness[a.witness.length - 1][0] === ANNEX_PREFIX ? a.witness.slice(0, -1) : a.witness.slice();
        }), _hashTree = lazy.value(() => {
          if (a.scriptTree) return (0, bip341_1.toHashTree)(a.scriptTree);
          if (a.hash) return { hash: a.hash };
        }), network2 = a.network || networks_1.bitcoin, o = { name: "p2tr", network: network2 };
        if (lazy.prop(o, "address", () => {
          if (!o.pubkey) return;
          let words = bech32_1.bech32m.toWords(o.pubkey);
          return words.unshift(TAPROOT_WITNESS_VERSION), bech32_1.bech32m.encode(network2.bech32, words);
        }), lazy.prop(o, "hash", () => {
          let hashTree = _hashTree();
          if (hashTree) return hashTree.hash;
          let w = _witness();
          if (w && w.length > 1) {
            let controlBlock = w[w.length - 1], leafVersion = controlBlock[0] & types_1.TAPLEAF_VERSION_MASK, script2 = w[w.length - 2], leafHash = (0, bip341_1.tapleafHash)({
              output: script2,
              version: leafVersion
            });
            return (0, bip341_1.rootHashFromPath)(controlBlock, leafHash);
          }
          return null;
        }), lazy.prop(o, "output", () => {
          if (o.pubkey)
            return bscript.compile([OPS.OP_1, o.pubkey]);
        }), lazy.prop(o, "redeemVersion", () => a.redeemVersion ? a.redeemVersion : a.redeem && a.redeem.redeemVersion !== void 0 && a.redeem.redeemVersion !== null ? a.redeem.redeemVersion : bip341_1.LEAF_VERSION_TAPSCRIPT), lazy.prop(o, "redeem", () => {
          let witness = _witness();
          if (!(!witness || witness.length < 2))
            return {
              output: witness[witness.length - 2],
              witness: witness.slice(0, -2),
              redeemVersion: witness[witness.length - 1][0] & types_1.TAPLEAF_VERSION_MASK
            };
        }), lazy.prop(o, "pubkey", () => {
          if (a.pubkey) return a.pubkey;
          if (a.output) return a.output.slice(2);
          if (a.address) return _address().data;
          if (o.internalPubkey) {
            let tweakedKey = (0, bip341_1.tweakKey)(o.internalPubkey, o.hash);
            if (tweakedKey) return tweakedKey.x;
          }
        }), lazy.prop(o, "internalPubkey", () => {
          if (a.internalPubkey) return a.internalPubkey;
          let witness = _witness();
          if (witness && witness.length > 1)
            return witness[witness.length - 1].slice(1, 33);
        }), lazy.prop(o, "signature", () => {
          if (a.signature) return a.signature;
          let witness = _witness();
          if (!(!witness || witness.length !== 1))
            return witness[0];
        }), lazy.prop(o, "witness", () => {
          if (a.witness) return a.witness;
          let hashTree = _hashTree();
          if (hashTree && a.redeem && a.redeem.output && a.internalPubkey) {
            let leafHash = (0, bip341_1.tapleafHash)({
              output: a.redeem.output,
              version: o.redeemVersion
            }), path = (0, bip341_1.findScriptPath)(hashTree, leafHash);
            if (!path) return;
            let outputKey = (0, bip341_1.tweakKey)(a.internalPubkey, hashTree.hash);
            if (!outputKey) return;
            let controlBock = buffer_1.Buffer.concat(
              [
                buffer_1.Buffer.from([o.redeemVersion | outputKey.parity]),
                a.internalPubkey
              ].concat(path)
            );
            return [a.redeem.output, controlBock];
          }
          if (a.signature) return [a.signature];
        }), opts.validate) {
          let pubkey = buffer_1.Buffer.from([]);
          if (a.address) {
            if (network2 && network2.bech32 !== _address().prefix)
              throw new TypeError("Invalid prefix or Network mismatch");
            if (_address().version !== TAPROOT_WITNESS_VERSION)
              throw new TypeError("Invalid address version");
            if (_address().data.length !== 32)
              throw new TypeError("Invalid address data");
            pubkey = _address().data;
          }
          if (a.pubkey) {
            if (pubkey.length > 0 && !pubkey.equals(a.pubkey))
              throw new TypeError("Pubkey mismatch");
            pubkey = a.pubkey;
          }
          if (a.output) {
            if (a.output.length !== 34 || a.output[0] !== OPS.OP_1 || a.output[1] !== 32)
              throw new TypeError("Output is invalid");
            if (pubkey.length > 0 && !pubkey.equals(a.output.slice(2)))
              throw new TypeError("Pubkey mismatch");
            pubkey = a.output.slice(2);
          }
          if (a.internalPubkey) {
            let tweakedKey = (0, bip341_1.tweakKey)(a.internalPubkey, o.hash);
            if (pubkey.length > 0 && !pubkey.equals(tweakedKey.x))
              throw new TypeError("Pubkey mismatch");
            pubkey = tweakedKey.x;
          }
          if (pubkey && pubkey.length && !(0, ecc_lib_1.getEccLib)().isXOnlyPoint(pubkey))
            throw new TypeError("Invalid pubkey for p2tr");
          let hashTree = _hashTree();
          if (a.hash && hashTree && !a.hash.equals(hashTree.hash))
            throw new TypeError("Hash mismatch");
          if (a.redeem && a.redeem.output && hashTree) {
            let leafHash = (0, bip341_1.tapleafHash)({
              output: a.redeem.output,
              version: o.redeemVersion
            });
            if (!(0, bip341_1.findScriptPath)(hashTree, leafHash))
              throw new TypeError("Redeem script not in tree");
          }
          let witness = _witness();
          if (a.redeem && o.redeem) {
            if (a.redeem.redeemVersion && a.redeem.redeemVersion !== o.redeem.redeemVersion)
              throw new TypeError("Redeem.redeemVersion and witness mismatch");
            if (a.redeem.output) {
              if (bscript.decompile(a.redeem.output).length === 0)
                throw new TypeError("Redeem.output is invalid");
              if (o.redeem.output && !a.redeem.output.equals(o.redeem.output))
                throw new TypeError("Redeem.output and witness mismatch");
            }
            if (a.redeem.witness && o.redeem.witness && !(0, types_1.stacksEqual)(a.redeem.witness, o.redeem.witness))
              throw new TypeError("Redeem.witness and witness mismatch");
          }
          if (witness && witness.length)
            if (witness.length === 1) {
              if (a.signature && !a.signature.equals(witness[0]))
                throw new TypeError("Signature mismatch");
            } else {
              let controlBlock = witness[witness.length - 1];
              if (controlBlock.length < 33)
                throw new TypeError(
                  `The control-block length is too small. Got ${controlBlock.length}, expected min 33.`
                );
              if ((controlBlock.length - 33) % 32 !== 0)
                throw new TypeError(
                  `The control-block length of ${controlBlock.length} is incorrect!`
                );
              let m = (controlBlock.length - 33) / 32;
              if (m > 128)
                throw new TypeError(
                  `The script path is too long. Got ${m}, expected max 128.`
                );
              let internalPubkey = controlBlock.slice(1, 33);
              if (a.internalPubkey && !a.internalPubkey.equals(internalPubkey))
                throw new TypeError("Internal pubkey mismatch");
              if (!(0, ecc_lib_1.getEccLib)().isXOnlyPoint(internalPubkey))
                throw new TypeError("Invalid internalPubkey for p2tr witness");
              let leafVersion = controlBlock[0] & types_1.TAPLEAF_VERSION_MASK, script2 = witness[witness.length - 2], leafHash = (0, bip341_1.tapleafHash)({
                output: script2,
                version: leafVersion
              }), hash = (0, bip341_1.rootHashFromPath)(controlBlock, leafHash), outputKey = (0, bip341_1.tweakKey)(internalPubkey, hash);
              if (!outputKey)
                throw new TypeError("Invalid outputKey for p2tr witness");
              if (pubkey.length && !pubkey.equals(outputKey.x))
                throw new TypeError("Pubkey mismatch for p2tr witness");
              if (outputKey.parity !== (controlBlock[0] & 1))
                throw new Error("Incorrect parity");
            }
        }
        return Object.assign(o, a);
      }
      exports.p2tr = p2tr;
    }
  });

  // node_modules/bitcoinjs-lib/src/payments/index.js
  var require_payments = __commonJS({
    "node_modules/bitcoinjs-lib/src/payments/index.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      exports.p2tr = exports.p2wsh = exports.p2wpkh = exports.p2sh = exports.p2pkh = exports.p2pk = exports.p2ms = exports.embed = void 0;
      var embed_1 = require_embed();
      Object.defineProperty(exports, "embed", {
        enumerable: !0,
        get: function() {
          return embed_1.p2data;
        }
      });
      var p2ms_1 = require_p2ms();
      Object.defineProperty(exports, "p2ms", {
        enumerable: !0,
        get: function() {
          return p2ms_1.p2ms;
        }
      });
      var p2pk_1 = require_p2pk();
      Object.defineProperty(exports, "p2pk", {
        enumerable: !0,
        get: function() {
          return p2pk_1.p2pk;
        }
      });
      var p2pkh_1 = require_p2pkh();
      Object.defineProperty(exports, "p2pkh", {
        enumerable: !0,
        get: function() {
          return p2pkh_1.p2pkh;
        }
      });
      var p2sh_1 = require_p2sh();
      Object.defineProperty(exports, "p2sh", {
        enumerable: !0,
        get: function() {
          return p2sh_1.p2sh;
        }
      });
      var p2wpkh_1 = require_p2wpkh();
      Object.defineProperty(exports, "p2wpkh", {
        enumerable: !0,
        get: function() {
          return p2wpkh_1.p2wpkh;
        }
      });
      var p2wsh_1 = require_p2wsh();
      Object.defineProperty(exports, "p2wsh", {
        enumerable: !0,
        get: function() {
          return p2wsh_1.p2wsh;
        }
      });
      var p2tr_1 = require_p2tr();
      Object.defineProperty(exports, "p2tr", {
        enumerable: !0,
        get: function() {
          return p2tr_1.p2tr;
        }
      });
    }
  });

  // node_modules/bitcoinjs-lib/src/address.js
  var require_address = __commonJS({
    "node_modules/bitcoinjs-lib/src/address.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      exports.toOutputScript = exports.fromOutputScript = exports.toBech32 = exports.toBase58Check = exports.fromBech32 = exports.fromBase58Check = void 0;
      var networks2 = require_networks(), payments2 = require_payments(), bscript = require_script(), types_1 = require_types(), bech32_1 = require_dist(), bs58check = require_bs58check(), FUTURE_SEGWIT_MAX_SIZE = 40, FUTURE_SEGWIT_MIN_SIZE = 2, FUTURE_SEGWIT_MAX_VERSION = 16, FUTURE_SEGWIT_MIN_VERSION = 2, FUTURE_SEGWIT_VERSION_DIFF = 80, FUTURE_SEGWIT_VERSION_WARNING = "WARNING: Sending to a future segwit version address can lead to loss of funds. End users MUST be warned carefully in the GUI and asked if they wish to proceed with caution. Wallets should verify the segwit version from the output of fromBech32, then decide when it is safe to use which version of segwit.";
      function _toFutureSegwitAddress(output, network2) {
        let data = output.slice(2);
        if (data.length < FUTURE_SEGWIT_MIN_SIZE || data.length > FUTURE_SEGWIT_MAX_SIZE)
          throw new TypeError("Invalid program length for segwit address");
        let version = output[0] - FUTURE_SEGWIT_VERSION_DIFF;
        if (version < FUTURE_SEGWIT_MIN_VERSION || version > FUTURE_SEGWIT_MAX_VERSION)
          throw new TypeError("Invalid version for segwit address");
        if (output[1] !== data.length)
          throw new TypeError("Invalid script for segwit address");
        return console.warn(FUTURE_SEGWIT_VERSION_WARNING), toBech32(data, version, network2.bech32);
      }
      function fromBase58Check(address2) {
        let payload = import_buffer.Buffer.from(bs58check.decode(address2));
        if (payload.length < 21) throw new TypeError(address2 + " is too short");
        if (payload.length > 21) throw new TypeError(address2 + " is too long");
        let version = payload.readUInt8(0), hash = payload.slice(1);
        return { version, hash };
      }
      exports.fromBase58Check = fromBase58Check;
      function fromBech32(address2) {
        let result, version;
        try {
          result = bech32_1.bech32.decode(address2);
        } catch {
        }
        if (result) {
          if (version = result.words[0], version !== 0) throw new TypeError(address2 + " uses wrong encoding");
        } else if (result = bech32_1.bech32m.decode(address2), version = result.words[0], version === 0) throw new TypeError(address2 + " uses wrong encoding");
        let data = bech32_1.bech32.fromWords(result.words.slice(1));
        return {
          version,
          prefix: result.prefix,
          data: import_buffer.Buffer.from(data)
        };
      }
      exports.fromBech32 = fromBech32;
      function toBase58Check(hash, version) {
        (0, types_1.typeforce)(
          (0, types_1.tuple)(types_1.Hash160bit, types_1.UInt8),
          arguments
        );
        let payload = import_buffer.Buffer.allocUnsafe(21);
        return payload.writeUInt8(version, 0), hash.copy(payload, 1), bs58check.encode(payload);
      }
      exports.toBase58Check = toBase58Check;
      function toBech32(data, version, prefix) {
        let words = bech32_1.bech32.toWords(data);
        return words.unshift(version), version === 0 ? bech32_1.bech32.encode(prefix, words) : bech32_1.bech32m.encode(prefix, words);
      }
      exports.toBech32 = toBech32;
      function fromOutputScript(output, network2) {
        network2 = network2 || networks2.bitcoin;
        try {
          return payments2.p2pkh({ output, network: network2 }).address;
        } catch {
        }
        try {
          return payments2.p2sh({ output, network: network2 }).address;
        } catch {
        }
        try {
          return payments2.p2wpkh({ output, network: network2 }).address;
        } catch {
        }
        try {
          return payments2.p2wsh({ output, network: network2 }).address;
        } catch {
        }
        try {
          return payments2.p2tr({ output, network: network2 }).address;
        } catch {
        }
        try {
          return _toFutureSegwitAddress(output, network2);
        } catch {
        }
        throw new Error(bscript.toASM(output) + " has no matching Address");
      }
      exports.fromOutputScript = fromOutputScript;
      function toOutputScript(address2, network2) {
        network2 = network2 || networks2.bitcoin;
        let decodeBase58, decodeBech32;
        try {
          decodeBase58 = fromBase58Check(address2);
        } catch {
        }
        if (decodeBase58) {
          if (decodeBase58.version === network2.pubKeyHash)
            return payments2.p2pkh({ hash: decodeBase58.hash }).output;
          if (decodeBase58.version === network2.scriptHash)
            return payments2.p2sh({ hash: decodeBase58.hash }).output;
        } else {
          try {
            decodeBech32 = fromBech32(address2);
          } catch {
          }
          if (decodeBech32) {
            if (decodeBech32.prefix !== network2.bech32)
              throw new Error(address2 + " has an invalid prefix");
            if (decodeBech32.version === 0) {
              if (decodeBech32.data.length === 20)
                return payments2.p2wpkh({ hash: decodeBech32.data }).output;
              if (decodeBech32.data.length === 32)
                return payments2.p2wsh({ hash: decodeBech32.data }).output;
            } else if (decodeBech32.version === 1) {
              if (decodeBech32.data.length === 32)
                return payments2.p2tr({ pubkey: decodeBech32.data }).output;
            } else if (decodeBech32.version >= FUTURE_SEGWIT_MIN_VERSION && decodeBech32.version <= FUTURE_SEGWIT_MAX_VERSION && decodeBech32.data.length >= FUTURE_SEGWIT_MIN_SIZE && decodeBech32.data.length <= FUTURE_SEGWIT_MAX_SIZE)
              return console.warn(FUTURE_SEGWIT_VERSION_WARNING), bscript.compile([
                decodeBech32.version + FUTURE_SEGWIT_VERSION_DIFF,
                decodeBech32.data
              ]);
          }
        }
        throw new Error(address2 + " has no matching Script");
      }
      exports.toOutputScript = toOutputScript;
    }
  });

  // node_modules/bitcoinjs-lib/src/merkle.js
  var require_merkle = __commonJS({
    "node_modules/bitcoinjs-lib/src/merkle.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      exports.fastMerkleRoot = void 0;
      function fastMerkleRoot(values, digestFn, mutated) {
        if (!Array.isArray(values)) throw TypeError("Expected values Array");
        if (typeof digestFn != "function")
          throw TypeError("Expected digest Function");
        let length = values.length, results = values.concat();
        for (mutated && (mutated.value = !1); length > 1; ) {
          let j = 0;
          for (let i = 0; i < length; i += 2, ++j) {
            let left = results[i], right = i + 1 === length ? left : results[i + 1];
            mutated && i + 1 < length && left.equals(right) && (mutated.value = !0);
            let data = import_buffer.Buffer.concat([left, right]);
            results[j] = digestFn(data);
          }
          length = j;
        }
        return results[0];
      }
      exports.fastMerkleRoot = fastMerkleRoot;
    }
  });

  // node_modules/bitcoinjs-lib/src/transaction.js
  var require_transaction = __commonJS({
    "node_modules/bitcoinjs-lib/src/transaction.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      exports.Transaction = void 0;
      var bufferutils_1 = require_bufferutils(), bcrypto = require_crypto2(), bscript = require_script(), script_1 = require_script(), types = require_types(), { typeforce } = types;
      function varSliceSize(someScript) {
        let length = someScript.length;
        return bufferutils_1.varuint.encodingLength(length) + length;
      }
      function vectorSize(someVector) {
        let length = someVector.length;
        return bufferutils_1.varuint.encodingLength(length) + someVector.reduce((sum, witness) => sum + varSliceSize(witness), 0);
      }
      var EMPTY_BUFFER = import_buffer.Buffer.allocUnsafe(0), EMPTY_WITNESS = [], ZERO = import_buffer.Buffer.from(
        "0000000000000000000000000000000000000000000000000000000000000000",
        "hex"
      ), ONE = import_buffer.Buffer.from(
        "0000000000000000000000000000000000000000000000000000000000000001",
        "hex"
      ), VALUE_UINT64_MAX = import_buffer.Buffer.from("ffffffffffffffff", "hex"), BLANK_OUTPUT = {
        script: EMPTY_BUFFER,
        valueBuffer: VALUE_UINT64_MAX
      };
      function isOutput(out) {
        return out.value !== void 0;
      }
      var Transaction2 = class _Transaction {
        constructor() {
          this.version = 1, this.locktime = 0, this.ins = [], this.outs = [];
        }
        static fromBuffer(buffer, _NO_STRICT) {
          let bufferReader = new bufferutils_1.BufferReader(buffer), tx = new _Transaction();
          tx.version = bufferReader.readInt32();
          let marker = bufferReader.readUInt8(), flag = bufferReader.readUInt8(), hasWitnesses = !1;
          marker === _Transaction.ADVANCED_TRANSACTION_MARKER && flag === _Transaction.ADVANCED_TRANSACTION_FLAG ? hasWitnesses = !0 : bufferReader.offset -= 2;
          let vinLen = bufferReader.readVarInt();
          for (let i = 0; i < vinLen; ++i)
            tx.ins.push({
              hash: bufferReader.readSlice(32),
              index: bufferReader.readUInt32(),
              script: bufferReader.readVarSlice(),
              sequence: bufferReader.readUInt32(),
              witness: EMPTY_WITNESS
            });
          let voutLen = bufferReader.readVarInt();
          for (let i = 0; i < voutLen; ++i)
            tx.outs.push({
              value: bufferReader.readUInt64(),
              script: bufferReader.readVarSlice()
            });
          if (hasWitnesses) {
            for (let i = 0; i < vinLen; ++i)
              tx.ins[i].witness = bufferReader.readVector();
            if (!tx.hasWitnesses())
              throw new Error("Transaction has superfluous witness data");
          }
          if (tx.locktime = bufferReader.readUInt32(), _NO_STRICT) return tx;
          if (bufferReader.offset !== buffer.length)
            throw new Error("Transaction has unexpected data");
          return tx;
        }
        static fromHex(hex) {
          return _Transaction.fromBuffer(import_buffer.Buffer.from(hex, "hex"), !1);
        }
        static isCoinbaseHash(buffer) {
          typeforce(types.Hash256bit, buffer);
          for (let i = 0; i < 32; ++i)
            if (buffer[i] !== 0) return !1;
          return !0;
        }
        isCoinbase() {
          return this.ins.length === 1 && _Transaction.isCoinbaseHash(this.ins[0].hash);
        }
        addInput(hash, index, sequence, scriptSig) {
          return typeforce(
            types.tuple(
              types.Hash256bit,
              types.UInt32,
              types.maybe(types.UInt32),
              types.maybe(types.Buffer)
            ),
            arguments
          ), types.Null(sequence) && (sequence = _Transaction.DEFAULT_SEQUENCE), this.ins.push({
            hash,
            index,
            script: scriptSig || EMPTY_BUFFER,
            sequence,
            witness: EMPTY_WITNESS
          }) - 1;
        }
        addOutput(scriptPubKey, value) {
          return typeforce(types.tuple(types.Buffer, types.Satoshi), arguments), this.outs.push({
            script: scriptPubKey,
            value
          }) - 1;
        }
        hasWitnesses() {
          return this.ins.some((x) => x.witness.length !== 0);
        }
        stripWitnesses() {
          this.ins.forEach((input) => {
            input.witness = EMPTY_WITNESS;
          });
        }
        weight() {
          let base = this.byteLength(!1), total = this.byteLength(!0);
          return base * 3 + total;
        }
        virtualSize() {
          return Math.ceil(this.weight() / 4);
        }
        byteLength(_ALLOW_WITNESS = !0) {
          let hasWitnesses = _ALLOW_WITNESS && this.hasWitnesses();
          return (hasWitnesses ? 10 : 8) + bufferutils_1.varuint.encodingLength(this.ins.length) + bufferutils_1.varuint.encodingLength(this.outs.length) + this.ins.reduce((sum, input) => sum + 40 + varSliceSize(input.script), 0) + this.outs.reduce((sum, output) => sum + 8 + varSliceSize(output.script), 0) + (hasWitnesses ? this.ins.reduce((sum, input) => sum + vectorSize(input.witness), 0) : 0);
        }
        clone() {
          let newTx = new _Transaction();
          return newTx.version = this.version, newTx.locktime = this.locktime, newTx.ins = this.ins.map((txIn) => ({
            hash: txIn.hash,
            index: txIn.index,
            script: txIn.script,
            sequence: txIn.sequence,
            witness: txIn.witness
          })), newTx.outs = this.outs.map((txOut) => ({
            script: txOut.script,
            value: txOut.value
          })), newTx;
        }
        /**
         * Hash transaction for signing a specific input.
         *
         * Bitcoin uses a different hash for each signed transaction input.
         * This method copies the transaction, makes the necessary changes based on the
         * hashType, and then hashes the result.
         * This hash can then be used to sign the provided transaction input.
         */
        hashForSignature(inIndex, prevOutScript, hashType) {
          if (typeforce(
            types.tuple(
              types.UInt32,
              types.Buffer,
              /* types.UInt8 */
              types.Number
            ),
            arguments
          ), inIndex >= this.ins.length) return ONE;
          let ourScript = bscript.compile(
            bscript.decompile(prevOutScript).filter((x) => x !== script_1.OPS.OP_CODESEPARATOR)
          ), txTmp = this.clone();
          if ((hashType & 31) === _Transaction.SIGHASH_NONE)
            txTmp.outs = [], txTmp.ins.forEach((input, i) => {
              i !== inIndex && (input.sequence = 0);
            });
          else if ((hashType & 31) === _Transaction.SIGHASH_SINGLE) {
            if (inIndex >= this.outs.length) return ONE;
            txTmp.outs.length = inIndex + 1;
            for (let i = 0; i < inIndex; i++)
              txTmp.outs[i] = BLANK_OUTPUT;
            txTmp.ins.forEach((input, y) => {
              y !== inIndex && (input.sequence = 0);
            });
          }
          hashType & _Transaction.SIGHASH_ANYONECANPAY ? (txTmp.ins = [txTmp.ins[inIndex]], txTmp.ins[0].script = ourScript) : (txTmp.ins.forEach((input) => {
            input.script = EMPTY_BUFFER;
          }), txTmp.ins[inIndex].script = ourScript);
          let buffer = import_buffer.Buffer.allocUnsafe(txTmp.byteLength(!1) + 4);
          return buffer.writeInt32LE(hashType, buffer.length - 4), txTmp.__toBuffer(buffer, 0, !1), bcrypto.hash256(buffer);
        }
        hashForWitnessV1(inIndex, prevOutScripts, values, hashType, leafHash, annex) {
          if (typeforce(
            types.tuple(
              types.UInt32,
              typeforce.arrayOf(types.Buffer),
              typeforce.arrayOf(types.Satoshi),
              types.UInt32
            ),
            arguments
          ), values.length !== this.ins.length || prevOutScripts.length !== this.ins.length)
            throw new Error("Must supply prevout script and value for all inputs");
          let outputType = hashType === _Transaction.SIGHASH_DEFAULT ? _Transaction.SIGHASH_ALL : hashType & _Transaction.SIGHASH_OUTPUT_MASK, isAnyoneCanPay = (hashType & _Transaction.SIGHASH_INPUT_MASK) === _Transaction.SIGHASH_ANYONECANPAY, isNone = outputType === _Transaction.SIGHASH_NONE, isSingle = outputType === _Transaction.SIGHASH_SINGLE, hashPrevouts = EMPTY_BUFFER, hashAmounts = EMPTY_BUFFER, hashScriptPubKeys = EMPTY_BUFFER, hashSequences = EMPTY_BUFFER, hashOutputs = EMPTY_BUFFER;
          if (!isAnyoneCanPay) {
            let bufferWriter = bufferutils_1.BufferWriter.withCapacity(
              36 * this.ins.length
            );
            this.ins.forEach((txIn) => {
              bufferWriter.writeSlice(txIn.hash), bufferWriter.writeUInt32(txIn.index);
            }), hashPrevouts = bcrypto.sha256(bufferWriter.end()), bufferWriter = bufferutils_1.BufferWriter.withCapacity(
              8 * this.ins.length
            ), values.forEach((value) => bufferWriter.writeUInt64(value)), hashAmounts = bcrypto.sha256(bufferWriter.end()), bufferWriter = bufferutils_1.BufferWriter.withCapacity(
              prevOutScripts.map(varSliceSize).reduce((a, b) => a + b)
            ), prevOutScripts.forEach(
              (prevOutScript) => bufferWriter.writeVarSlice(prevOutScript)
            ), hashScriptPubKeys = bcrypto.sha256(bufferWriter.end()), bufferWriter = bufferutils_1.BufferWriter.withCapacity(
              4 * this.ins.length
            ), this.ins.forEach((txIn) => bufferWriter.writeUInt32(txIn.sequence)), hashSequences = bcrypto.sha256(bufferWriter.end());
          }
          if (isNone || isSingle) {
            if (isSingle && inIndex < this.outs.length) {
              let output = this.outs[inIndex], bufferWriter = bufferutils_1.BufferWriter.withCapacity(
                8 + varSliceSize(output.script)
              );
              bufferWriter.writeUInt64(output.value), bufferWriter.writeVarSlice(output.script), hashOutputs = bcrypto.sha256(bufferWriter.end());
            }
          } else {
            let txOutsSize = this.outs.map((output) => 8 + varSliceSize(output.script)).reduce((a, b) => a + b), bufferWriter = bufferutils_1.BufferWriter.withCapacity(txOutsSize);
            this.outs.forEach((out) => {
              bufferWriter.writeUInt64(out.value), bufferWriter.writeVarSlice(out.script);
            }), hashOutputs = bcrypto.sha256(bufferWriter.end());
          }
          let spendType = (leafHash ? 2 : 0) + (annex ? 1 : 0), sigMsgSize = 174 - (isAnyoneCanPay ? 49 : 0) - (isNone ? 32 : 0) + (annex ? 32 : 0) + (leafHash ? 37 : 0), sigMsgWriter = bufferutils_1.BufferWriter.withCapacity(sigMsgSize);
          if (sigMsgWriter.writeUInt8(hashType), sigMsgWriter.writeInt32(this.version), sigMsgWriter.writeUInt32(this.locktime), sigMsgWriter.writeSlice(hashPrevouts), sigMsgWriter.writeSlice(hashAmounts), sigMsgWriter.writeSlice(hashScriptPubKeys), sigMsgWriter.writeSlice(hashSequences), isNone || isSingle || sigMsgWriter.writeSlice(hashOutputs), sigMsgWriter.writeUInt8(spendType), isAnyoneCanPay) {
            let input = this.ins[inIndex];
            sigMsgWriter.writeSlice(input.hash), sigMsgWriter.writeUInt32(input.index), sigMsgWriter.writeUInt64(values[inIndex]), sigMsgWriter.writeVarSlice(prevOutScripts[inIndex]), sigMsgWriter.writeUInt32(input.sequence);
          } else
            sigMsgWriter.writeUInt32(inIndex);
          if (annex) {
            let bufferWriter = bufferutils_1.BufferWriter.withCapacity(
              varSliceSize(annex)
            );
            bufferWriter.writeVarSlice(annex), sigMsgWriter.writeSlice(bcrypto.sha256(bufferWriter.end()));
          }
          return isSingle && sigMsgWriter.writeSlice(hashOutputs), leafHash && (sigMsgWriter.writeSlice(leafHash), sigMsgWriter.writeUInt8(0), sigMsgWriter.writeUInt32(4294967295)), bcrypto.taggedHash(
            "TapSighash",
            import_buffer.Buffer.concat([import_buffer.Buffer.from([0]), sigMsgWriter.end()])
          );
        }
        hashForWitnessV0(inIndex, prevOutScript, value, hashType) {
          typeforce(
            types.tuple(types.UInt32, types.Buffer, types.Satoshi, types.UInt32),
            arguments
          );
          let tbuffer = import_buffer.Buffer.from([]), bufferWriter, hashOutputs = ZERO, hashPrevouts = ZERO, hashSequence = ZERO;
          if (hashType & _Transaction.SIGHASH_ANYONECANPAY || (tbuffer = import_buffer.Buffer.allocUnsafe(36 * this.ins.length), bufferWriter = new bufferutils_1.BufferWriter(tbuffer, 0), this.ins.forEach((txIn) => {
            bufferWriter.writeSlice(txIn.hash), bufferWriter.writeUInt32(txIn.index);
          }), hashPrevouts = bcrypto.hash256(tbuffer)), !(hashType & _Transaction.SIGHASH_ANYONECANPAY) && (hashType & 31) !== _Transaction.SIGHASH_SINGLE && (hashType & 31) !== _Transaction.SIGHASH_NONE && (tbuffer = import_buffer.Buffer.allocUnsafe(4 * this.ins.length), bufferWriter = new bufferutils_1.BufferWriter(tbuffer, 0), this.ins.forEach((txIn) => {
            bufferWriter.writeUInt32(txIn.sequence);
          }), hashSequence = bcrypto.hash256(tbuffer)), (hashType & 31) !== _Transaction.SIGHASH_SINGLE && (hashType & 31) !== _Transaction.SIGHASH_NONE) {
            let txOutsSize = this.outs.reduce((sum, output) => sum + 8 + varSliceSize(output.script), 0);
            tbuffer = import_buffer.Buffer.allocUnsafe(txOutsSize), bufferWriter = new bufferutils_1.BufferWriter(tbuffer, 0), this.outs.forEach((out) => {
              bufferWriter.writeUInt64(out.value), bufferWriter.writeVarSlice(out.script);
            }), hashOutputs = bcrypto.hash256(tbuffer);
          } else if ((hashType & 31) === _Transaction.SIGHASH_SINGLE && inIndex < this.outs.length) {
            let output = this.outs[inIndex];
            tbuffer = import_buffer.Buffer.allocUnsafe(8 + varSliceSize(output.script)), bufferWriter = new bufferutils_1.BufferWriter(tbuffer, 0), bufferWriter.writeUInt64(output.value), bufferWriter.writeVarSlice(output.script), hashOutputs = bcrypto.hash256(tbuffer);
          }
          tbuffer = import_buffer.Buffer.allocUnsafe(156 + varSliceSize(prevOutScript)), bufferWriter = new bufferutils_1.BufferWriter(tbuffer, 0);
          let input = this.ins[inIndex];
          return bufferWriter.writeInt32(this.version), bufferWriter.writeSlice(hashPrevouts), bufferWriter.writeSlice(hashSequence), bufferWriter.writeSlice(input.hash), bufferWriter.writeUInt32(input.index), bufferWriter.writeVarSlice(prevOutScript), bufferWriter.writeUInt64(value), bufferWriter.writeUInt32(input.sequence), bufferWriter.writeSlice(hashOutputs), bufferWriter.writeUInt32(this.locktime), bufferWriter.writeUInt32(hashType), bcrypto.hash256(tbuffer);
        }
        getHash(forWitness) {
          return forWitness && this.isCoinbase() ? import_buffer.Buffer.alloc(32, 0) : bcrypto.hash256(this.__toBuffer(void 0, void 0, forWitness));
        }
        getId() {
          return (0, bufferutils_1.reverseBuffer)(this.getHash(!1)).toString(
            "hex"
          );
        }
        toBuffer(buffer, initialOffset) {
          return this.__toBuffer(buffer, initialOffset, !0);
        }
        toHex() {
          return this.toBuffer(void 0, void 0).toString("hex");
        }
        setInputScript(index, scriptSig) {
          typeforce(types.tuple(types.Number, types.Buffer), arguments), this.ins[index].script = scriptSig;
        }
        setWitness(index, witness) {
          typeforce(types.tuple(types.Number, [types.Buffer]), arguments), this.ins[index].witness = witness;
        }
        __toBuffer(buffer, initialOffset, _ALLOW_WITNESS = !1) {
          buffer || (buffer = import_buffer.Buffer.allocUnsafe(this.byteLength(_ALLOW_WITNESS)));
          let bufferWriter = new bufferutils_1.BufferWriter(
            buffer,
            initialOffset || 0
          );
          bufferWriter.writeInt32(this.version);
          let hasWitnesses = _ALLOW_WITNESS && this.hasWitnesses();
          return hasWitnesses && (bufferWriter.writeUInt8(_Transaction.ADVANCED_TRANSACTION_MARKER), bufferWriter.writeUInt8(_Transaction.ADVANCED_TRANSACTION_FLAG)), bufferWriter.writeVarInt(this.ins.length), this.ins.forEach((txIn) => {
            bufferWriter.writeSlice(txIn.hash), bufferWriter.writeUInt32(txIn.index), bufferWriter.writeVarSlice(txIn.script), bufferWriter.writeUInt32(txIn.sequence);
          }), bufferWriter.writeVarInt(this.outs.length), this.outs.forEach((txOut) => {
            isOutput(txOut) ? bufferWriter.writeUInt64(txOut.value) : bufferWriter.writeSlice(txOut.valueBuffer), bufferWriter.writeVarSlice(txOut.script);
          }), hasWitnesses && this.ins.forEach((input) => {
            bufferWriter.writeVector(input.witness);
          }), bufferWriter.writeUInt32(this.locktime), initialOffset !== void 0 ? buffer.slice(initialOffset, bufferWriter.offset) : buffer;
        }
      };
      exports.Transaction = Transaction2;
      Transaction2.DEFAULT_SEQUENCE = 4294967295;
      Transaction2.SIGHASH_DEFAULT = 0;
      Transaction2.SIGHASH_ALL = 1;
      Transaction2.SIGHASH_NONE = 2;
      Transaction2.SIGHASH_SINGLE = 3;
      Transaction2.SIGHASH_ANYONECANPAY = 128;
      Transaction2.SIGHASH_OUTPUT_MASK = 3;
      Transaction2.SIGHASH_INPUT_MASK = 128;
      Transaction2.ADVANCED_TRANSACTION_MARKER = 0;
      Transaction2.ADVANCED_TRANSACTION_FLAG = 1;
    }
  });

  // node_modules/bitcoinjs-lib/src/block.js
  var require_block = __commonJS({
    "node_modules/bitcoinjs-lib/src/block.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      exports.Block = void 0;
      var bufferutils_1 = require_bufferutils(), bcrypto = require_crypto2(), merkle_1 = require_merkle(), transaction_1 = require_transaction(), types = require_types(), { typeforce } = types, errorMerkleNoTxes = new TypeError(
        "Cannot compute merkle root for zero transactions"
      ), errorWitnessNotSegwit = new TypeError(
        "Cannot compute witness commit for non-segwit block"
      ), Block = class _Block {
        constructor() {
          this.version = 1, this.prevHash = void 0, this.merkleRoot = void 0, this.timestamp = 0, this.witnessCommit = void 0, this.bits = 0, this.nonce = 0, this.transactions = void 0;
        }
        static fromBuffer(buffer) {
          if (buffer.length < 80) throw new Error("Buffer too small (< 80 bytes)");
          let bufferReader = new bufferutils_1.BufferReader(buffer), block = new _Block();
          if (block.version = bufferReader.readInt32(), block.prevHash = bufferReader.readSlice(32), block.merkleRoot = bufferReader.readSlice(32), block.timestamp = bufferReader.readUInt32(), block.bits = bufferReader.readUInt32(), block.nonce = bufferReader.readUInt32(), buffer.length === 80) return block;
          let readTransaction = () => {
            let tx = transaction_1.Transaction.fromBuffer(
              bufferReader.buffer.slice(bufferReader.offset),
              !0
            );
            return bufferReader.offset += tx.byteLength(), tx;
          }, nTransactions = bufferReader.readVarInt();
          block.transactions = [];
          for (let i = 0; i < nTransactions; ++i) {
            let tx = readTransaction();
            block.transactions.push(tx);
          }
          let witnessCommit = block.getWitnessCommit();
          return witnessCommit && (block.witnessCommit = witnessCommit), block;
        }
        static fromHex(hex) {
          return _Block.fromBuffer(import_buffer.Buffer.from(hex, "hex"));
        }
        static calculateTarget(bits) {
          let exponent = ((bits & 4278190080) >> 24) - 3, mantissa = bits & 8388607, target = import_buffer.Buffer.alloc(32, 0);
          return target.writeUIntBE(mantissa, 29 - exponent, 3), target;
        }
        static calculateMerkleRoot(transactions, forWitness, mutated) {
          if (typeforce([{ getHash: types.Function }], transactions), transactions.length === 0) throw errorMerkleNoTxes;
          if (forWitness && !txesHaveWitnessCommit(transactions))
            throw errorWitnessNotSegwit;
          let hashes = transactions.map(
            (transaction) => transaction.getHash(forWitness)
          ), rootHash = (0, merkle_1.fastMerkleRoot)(
            hashes,
            bcrypto.hash256,
            mutated
          );
          return forWitness ? bcrypto.hash256(
            import_buffer.Buffer.concat([rootHash, transactions[0].ins[0].witness[0]])
          ) : rootHash;
        }
        getWitnessCommit() {
          if (!txesHaveWitnessCommit(this.transactions)) return null;
          let witnessCommits = this.transactions[0].outs.filter(
            (out) => out.script.slice(0, 6).equals(import_buffer.Buffer.from("6a24aa21a9ed", "hex"))
          ).map((out) => out.script.slice(6, 38));
          if (witnessCommits.length === 0) return null;
          let result = witnessCommits[witnessCommits.length - 1];
          return result instanceof import_buffer.Buffer && result.length === 32 ? result : null;
        }
        hasWitnessCommit() {
          return this.witnessCommit instanceof import_buffer.Buffer && this.witnessCommit.length === 32 || this.getWitnessCommit() !== null;
        }
        hasWitness() {
          return anyTxHasWitness(this.transactions);
        }
        weight() {
          let base = this.byteLength(!1, !1), total = this.byteLength(!1, !0);
          return base * 3 + total;
        }
        byteLength(headersOnly, allowWitness = !0) {
          return headersOnly || !this.transactions ? 80 : 80 + bufferutils_1.varuint.encodingLength(this.transactions.length) + this.transactions.reduce((a, x) => a + x.byteLength(allowWitness), 0);
        }
        getHash() {
          return bcrypto.hash256(this.toBuffer(!0));
        }
        getId() {
          return (0, bufferutils_1.reverseBuffer)(this.getHash()).toString("hex");
        }
        getUTCDate() {
          let date = /* @__PURE__ */ new Date(0);
          return date.setUTCSeconds(this.timestamp), date;
        }
        // TODO: buffer, offset compatibility
        toBuffer(headersOnly) {
          let buffer = import_buffer.Buffer.allocUnsafe(this.byteLength(headersOnly)), bufferWriter = new bufferutils_1.BufferWriter(buffer);
          return bufferWriter.writeInt32(this.version), bufferWriter.writeSlice(this.prevHash), bufferWriter.writeSlice(this.merkleRoot), bufferWriter.writeUInt32(this.timestamp), bufferWriter.writeUInt32(this.bits), bufferWriter.writeUInt32(this.nonce), headersOnly || !this.transactions || (bufferutils_1.varuint.encode(
            this.transactions.length,
            buffer,
            bufferWriter.offset
          ), bufferWriter.offset += bufferutils_1.varuint.encode.bytes, this.transactions.forEach((tx) => {
            let txSize = tx.byteLength();
            tx.toBuffer(buffer, bufferWriter.offset), bufferWriter.offset += txSize;
          })), buffer;
        }
        toHex(headersOnly) {
          return this.toBuffer(headersOnly).toString("hex");
        }
        checkTxRoots() {
          let hasWitnessCommit = this.hasWitnessCommit();
          return !hasWitnessCommit && this.hasWitness() ? !1 : this.__checkMerkleRoot() && (hasWitnessCommit ? this.__checkWitnessCommit() : !0);
        }
        checkProofOfWork() {
          let hash = (0, bufferutils_1.reverseBuffer)(this.getHash()), target = _Block.calculateTarget(this.bits);
          return hash.compare(target) <= 0;
        }
        __checkMerkleRoot() {
          if (!this.transactions) throw errorMerkleNoTxes;
          let mutated = { value: !1 }, actualMerkleRoot = _Block.calculateMerkleRoot(
            this.transactions,
            !1,
            mutated
          );
          return !mutated.value && this.merkleRoot.compare(actualMerkleRoot) === 0;
        }
        __checkWitnessCommit() {
          if (!this.transactions) throw errorMerkleNoTxes;
          if (!this.hasWitnessCommit()) throw errorWitnessNotSegwit;
          let actualWitnessCommit = _Block.calculateMerkleRoot(
            this.transactions,
            !0
          );
          return this.witnessCommit.compare(actualWitnessCommit) === 0;
        }
      };
      exports.Block = Block;
      function txesHaveWitnessCommit(transactions) {
        return transactions instanceof Array && transactions[0] && transactions[0].ins && transactions[0].ins instanceof Array && transactions[0].ins[0] && transactions[0].ins[0].witness && transactions[0].ins[0].witness instanceof Array && transactions[0].ins[0].witness.length > 0;
      }
      function anyTxHasWitness(transactions) {
        return transactions instanceof Array && transactions.some(
          (tx) => typeof tx == "object" && tx.ins instanceof Array && tx.ins.some(
            (input) => typeof input == "object" && input.witness instanceof Array && input.witness.length > 0
          )
        );
      }
    }
  });

  // node_modules/bip174/src/lib/typeFields.js
  var require_typeFields = __commonJS({
    "node_modules/bip174/src/lib/typeFields.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      var GlobalTypes;
      (function(GlobalTypes2) {
        GlobalTypes2[GlobalTypes2.UNSIGNED_TX = 0] = "UNSIGNED_TX", GlobalTypes2[GlobalTypes2.GLOBAL_XPUB = 1] = "GLOBAL_XPUB";
      })(GlobalTypes = exports.GlobalTypes || (exports.GlobalTypes = {}));
      exports.GLOBAL_TYPE_NAMES = ["unsignedTx", "globalXpub"];
      var InputTypes;
      (function(InputTypes2) {
        InputTypes2[InputTypes2.NON_WITNESS_UTXO = 0] = "NON_WITNESS_UTXO", InputTypes2[InputTypes2.WITNESS_UTXO = 1] = "WITNESS_UTXO", InputTypes2[InputTypes2.PARTIAL_SIG = 2] = "PARTIAL_SIG", InputTypes2[InputTypes2.SIGHASH_TYPE = 3] = "SIGHASH_TYPE", InputTypes2[InputTypes2.REDEEM_SCRIPT = 4] = "REDEEM_SCRIPT", InputTypes2[InputTypes2.WITNESS_SCRIPT = 5] = "WITNESS_SCRIPT", InputTypes2[InputTypes2.BIP32_DERIVATION = 6] = "BIP32_DERIVATION", InputTypes2[InputTypes2.FINAL_SCRIPTSIG = 7] = "FINAL_SCRIPTSIG", InputTypes2[InputTypes2.FINAL_SCRIPTWITNESS = 8] = "FINAL_SCRIPTWITNESS", InputTypes2[InputTypes2.POR_COMMITMENT = 9] = "POR_COMMITMENT", InputTypes2[InputTypes2.TAP_KEY_SIG = 19] = "TAP_KEY_SIG", InputTypes2[InputTypes2.TAP_SCRIPT_SIG = 20] = "TAP_SCRIPT_SIG", InputTypes2[InputTypes2.TAP_LEAF_SCRIPT = 21] = "TAP_LEAF_SCRIPT", InputTypes2[InputTypes2.TAP_BIP32_DERIVATION = 22] = "TAP_BIP32_DERIVATION", InputTypes2[InputTypes2.TAP_INTERNAL_KEY = 23] = "TAP_INTERNAL_KEY", InputTypes2[InputTypes2.TAP_MERKLE_ROOT = 24] = "TAP_MERKLE_ROOT";
      })(InputTypes = exports.InputTypes || (exports.InputTypes = {}));
      exports.INPUT_TYPE_NAMES = [
        "nonWitnessUtxo",
        "witnessUtxo",
        "partialSig",
        "sighashType",
        "redeemScript",
        "witnessScript",
        "bip32Derivation",
        "finalScriptSig",
        "finalScriptWitness",
        "porCommitment",
        "tapKeySig",
        "tapScriptSig",
        "tapLeafScript",
        "tapBip32Derivation",
        "tapInternalKey",
        "tapMerkleRoot"
      ];
      var OutputTypes;
      (function(OutputTypes2) {
        OutputTypes2[OutputTypes2.REDEEM_SCRIPT = 0] = "REDEEM_SCRIPT", OutputTypes2[OutputTypes2.WITNESS_SCRIPT = 1] = "WITNESS_SCRIPT", OutputTypes2[OutputTypes2.BIP32_DERIVATION = 2] = "BIP32_DERIVATION", OutputTypes2[OutputTypes2.TAP_INTERNAL_KEY = 5] = "TAP_INTERNAL_KEY", OutputTypes2[OutputTypes2.TAP_TREE = 6] = "TAP_TREE", OutputTypes2[OutputTypes2.TAP_BIP32_DERIVATION = 7] = "TAP_BIP32_DERIVATION";
      })(OutputTypes = exports.OutputTypes || (exports.OutputTypes = {}));
      exports.OUTPUT_TYPE_NAMES = [
        "redeemScript",
        "witnessScript",
        "bip32Derivation",
        "tapInternalKey",
        "tapTree",
        "tapBip32Derivation"
      ];
    }
  });

  // node_modules/bip174/src/lib/converter/global/globalXpub.js
  var require_globalXpub = __commonJS({
    "node_modules/bip174/src/lib/converter/global/globalXpub.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      var typeFields_1 = require_typeFields(), range = (n) => [...Array(n).keys()];
      function decode(keyVal) {
        if (keyVal.key[0] !== typeFields_1.GlobalTypes.GLOBAL_XPUB)
          throw new Error(
            "Decode Error: could not decode globalXpub with key 0x" + keyVal.key.toString("hex")
          );
        if (keyVal.key.length !== 79 || ![2, 3].includes(keyVal.key[46]))
          throw new Error(
            "Decode Error: globalXpub has invalid extended pubkey in key 0x" + keyVal.key.toString("hex")
          );
        if (keyVal.value.length / 4 % 1 !== 0)
          throw new Error(
            "Decode Error: Global GLOBAL_XPUB value length should be multiple of 4"
          );
        let extendedPubkey = keyVal.key.slice(1), data = {
          masterFingerprint: keyVal.value.slice(0, 4),
          extendedPubkey,
          path: "m"
        };
        for (let i of range(keyVal.value.length / 4 - 1)) {
          let val = keyVal.value.readUInt32LE(i * 4 + 4), isHard = !!(val & 2147483648), idx = val & 2147483647;
          data.path += "/" + idx.toString(10) + (isHard ? "'" : "");
        }
        return data;
      }
      exports.decode = decode;
      function encode(data) {
        let head = import_buffer.Buffer.from([typeFields_1.GlobalTypes.GLOBAL_XPUB]), key = import_buffer.Buffer.concat([head, data.extendedPubkey]), splitPath = data.path.split("/"), value = import_buffer.Buffer.allocUnsafe(splitPath.length * 4);
        data.masterFingerprint.copy(value, 0);
        let offset = 4;
        return splitPath.slice(1).forEach((level) => {
          let isHard = level.slice(-1) === "'", num = 2147483647 & parseInt(isHard ? level.slice(0, -1) : level, 10);
          isHard && (num += 2147483648), value.writeUInt32LE(num, offset), offset += 4;
        }), {
          key,
          value
        };
      }
      exports.encode = encode;
      exports.expected = "{ masterFingerprint: Buffer; extendedPubkey: Buffer; path: string; }";
      function check(data) {
        let epk = data.extendedPubkey, mfp = data.masterFingerprint, p = data.path;
        return import_buffer.Buffer.isBuffer(epk) && epk.length === 78 && [2, 3].indexOf(epk[45]) > -1 && import_buffer.Buffer.isBuffer(mfp) && mfp.length === 4 && typeof p == "string" && !!p.match(/^m(\/\d+'?)*$/);
      }
      exports.check = check;
      function canAddToArray(array, item, dupeSet) {
        let dupeString = item.extendedPubkey.toString("hex");
        return dupeSet.has(dupeString) ? !1 : (dupeSet.add(dupeString), array.filter((v) => v.extendedPubkey.equals(item.extendedPubkey)).length === 0);
      }
      exports.canAddToArray = canAddToArray;
    }
  });

  // node_modules/bip174/src/lib/converter/global/unsignedTx.js
  var require_unsignedTx = __commonJS({
    "node_modules/bip174/src/lib/converter/global/unsignedTx.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      var typeFields_1 = require_typeFields();
      function encode(data) {
        return {
          key: import_buffer.Buffer.from([typeFields_1.GlobalTypes.UNSIGNED_TX]),
          value: data.toBuffer()
        };
      }
      exports.encode = encode;
    }
  });

  // node_modules/bip174/src/lib/converter/input/finalScriptSig.js
  var require_finalScriptSig = __commonJS({
    "node_modules/bip174/src/lib/converter/input/finalScriptSig.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      var typeFields_1 = require_typeFields();
      function decode(keyVal) {
        if (keyVal.key[0] !== typeFields_1.InputTypes.FINAL_SCRIPTSIG)
          throw new Error(
            "Decode Error: could not decode finalScriptSig with key 0x" + keyVal.key.toString("hex")
          );
        return keyVal.value;
      }
      exports.decode = decode;
      function encode(data) {
        return {
          key: import_buffer.Buffer.from([typeFields_1.InputTypes.FINAL_SCRIPTSIG]),
          value: data
        };
      }
      exports.encode = encode;
      exports.expected = "Buffer";
      function check(data) {
        return import_buffer.Buffer.isBuffer(data);
      }
      exports.check = check;
      function canAdd(currentData, newData) {
        return !!currentData && !!newData && currentData.finalScriptSig === void 0;
      }
      exports.canAdd = canAdd;
    }
  });

  // node_modules/bip174/src/lib/converter/input/finalScriptWitness.js
  var require_finalScriptWitness = __commonJS({
    "node_modules/bip174/src/lib/converter/input/finalScriptWitness.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      var typeFields_1 = require_typeFields();
      function decode(keyVal) {
        if (keyVal.key[0] !== typeFields_1.InputTypes.FINAL_SCRIPTWITNESS)
          throw new Error(
            "Decode Error: could not decode finalScriptWitness with key 0x" + keyVal.key.toString("hex")
          );
        return keyVal.value;
      }
      exports.decode = decode;
      function encode(data) {
        return {
          key: import_buffer.Buffer.from([typeFields_1.InputTypes.FINAL_SCRIPTWITNESS]),
          value: data
        };
      }
      exports.encode = encode;
      exports.expected = "Buffer";
      function check(data) {
        return import_buffer.Buffer.isBuffer(data);
      }
      exports.check = check;
      function canAdd(currentData, newData) {
        return !!currentData && !!newData && currentData.finalScriptWitness === void 0;
      }
      exports.canAdd = canAdd;
    }
  });

  // node_modules/bip174/src/lib/converter/input/nonWitnessUtxo.js
  var require_nonWitnessUtxo = __commonJS({
    "node_modules/bip174/src/lib/converter/input/nonWitnessUtxo.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      var typeFields_1 = require_typeFields();
      function decode(keyVal) {
        if (keyVal.key[0] !== typeFields_1.InputTypes.NON_WITNESS_UTXO)
          throw new Error(
            "Decode Error: could not decode nonWitnessUtxo with key 0x" + keyVal.key.toString("hex")
          );
        return keyVal.value;
      }
      exports.decode = decode;
      function encode(data) {
        return {
          key: import_buffer.Buffer.from([typeFields_1.InputTypes.NON_WITNESS_UTXO]),
          value: data
        };
      }
      exports.encode = encode;
      exports.expected = "Buffer";
      function check(data) {
        return import_buffer.Buffer.isBuffer(data);
      }
      exports.check = check;
      function canAdd(currentData, newData) {
        return !!currentData && !!newData && currentData.nonWitnessUtxo === void 0;
      }
      exports.canAdd = canAdd;
    }
  });

  // node_modules/bip174/src/lib/converter/input/partialSig.js
  var require_partialSig = __commonJS({
    "node_modules/bip174/src/lib/converter/input/partialSig.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      var typeFields_1 = require_typeFields();
      function decode(keyVal) {
        if (keyVal.key[0] !== typeFields_1.InputTypes.PARTIAL_SIG)
          throw new Error(
            "Decode Error: could not decode partialSig with key 0x" + keyVal.key.toString("hex")
          );
        if (!(keyVal.key.length === 34 || keyVal.key.length === 66) || ![2, 3, 4].includes(keyVal.key[1]))
          throw new Error(
            "Decode Error: partialSig has invalid pubkey in key 0x" + keyVal.key.toString("hex")
          );
        return {
          pubkey: keyVal.key.slice(1),
          signature: keyVal.value
        };
      }
      exports.decode = decode;
      function encode(pSig) {
        let head = import_buffer.Buffer.from([typeFields_1.InputTypes.PARTIAL_SIG]);
        return {
          key: import_buffer.Buffer.concat([head, pSig.pubkey]),
          value: pSig.signature
        };
      }
      exports.encode = encode;
      exports.expected = "{ pubkey: Buffer; signature: Buffer; }";
      function check(data) {
        return import_buffer.Buffer.isBuffer(data.pubkey) && import_buffer.Buffer.isBuffer(data.signature) && [33, 65].includes(data.pubkey.length) && [2, 3, 4].includes(data.pubkey[0]) && isDerSigWithSighash(data.signature);
      }
      exports.check = check;
      function isDerSigWithSighash(buf) {
        if (!import_buffer.Buffer.isBuffer(buf) || buf.length < 9 || buf[0] !== 48 || buf.length !== buf[1] + 3 || buf[2] !== 2) return !1;
        let rLen = buf[3];
        if (rLen > 33 || rLen < 1 || buf[3 + rLen + 1] !== 2) return !1;
        let sLen = buf[3 + rLen + 2];
        return !(sLen > 33 || sLen < 1 || buf.length !== 3 + rLen + 2 + sLen + 2);
      }
      function canAddToArray(array, item, dupeSet) {
        let dupeString = item.pubkey.toString("hex");
        return dupeSet.has(dupeString) ? !1 : (dupeSet.add(dupeString), array.filter((v) => v.pubkey.equals(item.pubkey)).length === 0);
      }
      exports.canAddToArray = canAddToArray;
    }
  });

  // node_modules/bip174/src/lib/converter/input/porCommitment.js
  var require_porCommitment = __commonJS({
    "node_modules/bip174/src/lib/converter/input/porCommitment.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      var typeFields_1 = require_typeFields();
      function decode(keyVal) {
        if (keyVal.key[0] !== typeFields_1.InputTypes.POR_COMMITMENT)
          throw new Error(
            "Decode Error: could not decode porCommitment with key 0x" + keyVal.key.toString("hex")
          );
        return keyVal.value.toString("utf8");
      }
      exports.decode = decode;
      function encode(data) {
        return {
          key: import_buffer.Buffer.from([typeFields_1.InputTypes.POR_COMMITMENT]),
          value: import_buffer.Buffer.from(data, "utf8")
        };
      }
      exports.encode = encode;
      exports.expected = "string";
      function check(data) {
        return typeof data == "string";
      }
      exports.check = check;
      function canAdd(currentData, newData) {
        return !!currentData && !!newData && currentData.porCommitment === void 0;
      }
      exports.canAdd = canAdd;
    }
  });

  // node_modules/bip174/src/lib/converter/input/sighashType.js
  var require_sighashType = __commonJS({
    "node_modules/bip174/src/lib/converter/input/sighashType.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      var typeFields_1 = require_typeFields();
      function decode(keyVal) {
        if (keyVal.key[0] !== typeFields_1.InputTypes.SIGHASH_TYPE)
          throw new Error(
            "Decode Error: could not decode sighashType with key 0x" + keyVal.key.toString("hex")
          );
        return keyVal.value.readUInt32LE(0);
      }
      exports.decode = decode;
      function encode(data) {
        let key = import_buffer.Buffer.from([typeFields_1.InputTypes.SIGHASH_TYPE]), value = import_buffer.Buffer.allocUnsafe(4);
        return value.writeUInt32LE(data, 0), {
          key,
          value
        };
      }
      exports.encode = encode;
      exports.expected = "number";
      function check(data) {
        return typeof data == "number";
      }
      exports.check = check;
      function canAdd(currentData, newData) {
        return !!currentData && !!newData && currentData.sighashType === void 0;
      }
      exports.canAdd = canAdd;
    }
  });

  // node_modules/bip174/src/lib/converter/input/tapKeySig.js
  var require_tapKeySig = __commonJS({
    "node_modules/bip174/src/lib/converter/input/tapKeySig.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      var typeFields_1 = require_typeFields();
      function decode(keyVal) {
        if (keyVal.key[0] !== typeFields_1.InputTypes.TAP_KEY_SIG || keyVal.key.length !== 1)
          throw new Error(
            "Decode Error: could not decode tapKeySig with key 0x" + keyVal.key.toString("hex")
          );
        if (!check(keyVal.value))
          throw new Error(
            "Decode Error: tapKeySig not a valid 64-65-byte BIP340 signature"
          );
        return keyVal.value;
      }
      exports.decode = decode;
      function encode(value) {
        return { key: import_buffer.Buffer.from([typeFields_1.InputTypes.TAP_KEY_SIG]), value };
      }
      exports.encode = encode;
      exports.expected = "Buffer";
      function check(data) {
        return import_buffer.Buffer.isBuffer(data) && (data.length === 64 || data.length === 65);
      }
      exports.check = check;
      function canAdd(currentData, newData) {
        return !!currentData && !!newData && currentData.tapKeySig === void 0;
      }
      exports.canAdd = canAdd;
    }
  });

  // node_modules/bip174/src/lib/converter/input/tapLeafScript.js
  var require_tapLeafScript = __commonJS({
    "node_modules/bip174/src/lib/converter/input/tapLeafScript.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      var typeFields_1 = require_typeFields();
      function decode(keyVal) {
        if (keyVal.key[0] !== typeFields_1.InputTypes.TAP_LEAF_SCRIPT)
          throw new Error(
            "Decode Error: could not decode tapLeafScript with key 0x" + keyVal.key.toString("hex")
          );
        if ((keyVal.key.length - 2) % 32 !== 0)
          throw new Error(
            "Decode Error: tapLeafScript has invalid control block in key 0x" + keyVal.key.toString("hex")
          );
        let leafVersion = keyVal.value[keyVal.value.length - 1];
        if ((keyVal.key[1] & 254) !== leafVersion)
          throw new Error(
            "Decode Error: tapLeafScript bad leaf version in key 0x" + keyVal.key.toString("hex")
          );
        let script2 = keyVal.value.slice(0, -1);
        return { controlBlock: keyVal.key.slice(1), script: script2, leafVersion };
      }
      exports.decode = decode;
      function encode(tScript) {
        let head = import_buffer.Buffer.from([typeFields_1.InputTypes.TAP_LEAF_SCRIPT]), verBuf = import_buffer.Buffer.from([tScript.leafVersion]);
        return {
          key: import_buffer.Buffer.concat([head, tScript.controlBlock]),
          value: import_buffer.Buffer.concat([tScript.script, verBuf])
        };
      }
      exports.encode = encode;
      exports.expected = "{ controlBlock: Buffer; leafVersion: number, script: Buffer; }";
      function check(data) {
        return import_buffer.Buffer.isBuffer(data.controlBlock) && (data.controlBlock.length - 1) % 32 === 0 && (data.controlBlock[0] & 254) === data.leafVersion && import_buffer.Buffer.isBuffer(data.script);
      }
      exports.check = check;
      function canAddToArray(array, item, dupeSet) {
        let dupeString = item.controlBlock.toString("hex");
        return dupeSet.has(dupeString) ? !1 : (dupeSet.add(dupeString), array.filter((v) => v.controlBlock.equals(item.controlBlock)).length === 0);
      }
      exports.canAddToArray = canAddToArray;
    }
  });

  // node_modules/bip174/src/lib/converter/input/tapMerkleRoot.js
  var require_tapMerkleRoot = __commonJS({
    "node_modules/bip174/src/lib/converter/input/tapMerkleRoot.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      var typeFields_1 = require_typeFields();
      function decode(keyVal) {
        if (keyVal.key[0] !== typeFields_1.InputTypes.TAP_MERKLE_ROOT || keyVal.key.length !== 1)
          throw new Error(
            "Decode Error: could not decode tapMerkleRoot with key 0x" + keyVal.key.toString("hex")
          );
        if (!check(keyVal.value))
          throw new Error("Decode Error: tapMerkleRoot not a 32-byte hash");
        return keyVal.value;
      }
      exports.decode = decode;
      function encode(value) {
        return { key: import_buffer.Buffer.from([typeFields_1.InputTypes.TAP_MERKLE_ROOT]), value };
      }
      exports.encode = encode;
      exports.expected = "Buffer";
      function check(data) {
        return import_buffer.Buffer.isBuffer(data) && data.length === 32;
      }
      exports.check = check;
      function canAdd(currentData, newData) {
        return !!currentData && !!newData && currentData.tapMerkleRoot === void 0;
      }
      exports.canAdd = canAdd;
    }
  });

  // node_modules/bip174/src/lib/converter/input/tapScriptSig.js
  var require_tapScriptSig = __commonJS({
    "node_modules/bip174/src/lib/converter/input/tapScriptSig.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      var typeFields_1 = require_typeFields();
      function decode(keyVal) {
        if (keyVal.key[0] !== typeFields_1.InputTypes.TAP_SCRIPT_SIG)
          throw new Error(
            "Decode Error: could not decode tapScriptSig with key 0x" + keyVal.key.toString("hex")
          );
        if (keyVal.key.length !== 65)
          throw new Error(
            "Decode Error: tapScriptSig has invalid key 0x" + keyVal.key.toString("hex")
          );
        if (keyVal.value.length !== 64 && keyVal.value.length !== 65)
          throw new Error(
            "Decode Error: tapScriptSig has invalid signature in key 0x" + keyVal.key.toString("hex")
          );
        let pubkey = keyVal.key.slice(1, 33), leafHash = keyVal.key.slice(33);
        return {
          pubkey,
          leafHash,
          signature: keyVal.value
        };
      }
      exports.decode = decode;
      function encode(tSig) {
        let head = import_buffer.Buffer.from([typeFields_1.InputTypes.TAP_SCRIPT_SIG]);
        return {
          key: import_buffer.Buffer.concat([head, tSig.pubkey, tSig.leafHash]),
          value: tSig.signature
        };
      }
      exports.encode = encode;
      exports.expected = "{ pubkey: Buffer; leafHash: Buffer; signature: Buffer; }";
      function check(data) {
        return import_buffer.Buffer.isBuffer(data.pubkey) && import_buffer.Buffer.isBuffer(data.leafHash) && import_buffer.Buffer.isBuffer(data.signature) && data.pubkey.length === 32 && data.leafHash.length === 32 && (data.signature.length === 64 || data.signature.length === 65);
      }
      exports.check = check;
      function canAddToArray(array, item, dupeSet) {
        let dupeString = item.pubkey.toString("hex") + item.leafHash.toString("hex");
        return dupeSet.has(dupeString) ? !1 : (dupeSet.add(dupeString), array.filter(
          (v) => v.pubkey.equals(item.pubkey) && v.leafHash.equals(item.leafHash)
        ).length === 0);
      }
      exports.canAddToArray = canAddToArray;
    }
  });

  // node_modules/bip174/src/lib/converter/varint.js
  var require_varint = __commonJS({
    "node_modules/bip174/src/lib/converter/varint.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      var MAX_SAFE_INTEGER = 9007199254740991;
      function checkUInt53(n) {
        if (n < 0 || n > MAX_SAFE_INTEGER || n % 1 !== 0)
          throw new RangeError("value out of range");
      }
      function encode(_number, buffer, offset) {
        if (checkUInt53(_number), buffer || (buffer = import_buffer.Buffer.allocUnsafe(encodingLength(_number))), !import_buffer.Buffer.isBuffer(buffer))
          throw new TypeError("buffer must be a Buffer instance");
        return offset || (offset = 0), _number < 253 ? (buffer.writeUInt8(_number, offset), Object.assign(encode, { bytes: 1 })) : _number <= 65535 ? (buffer.writeUInt8(253, offset), buffer.writeUInt16LE(_number, offset + 1), Object.assign(encode, { bytes: 3 })) : _number <= 4294967295 ? (buffer.writeUInt8(254, offset), buffer.writeUInt32LE(_number, offset + 1), Object.assign(encode, { bytes: 5 })) : (buffer.writeUInt8(255, offset), buffer.writeUInt32LE(_number >>> 0, offset + 1), buffer.writeUInt32LE(_number / 4294967296 | 0, offset + 5), Object.assign(encode, { bytes: 9 })), buffer;
      }
      exports.encode = encode;
      function decode(buffer, offset) {
        if (!import_buffer.Buffer.isBuffer(buffer))
          throw new TypeError("buffer must be a Buffer instance");
        offset || (offset = 0);
        let first = buffer.readUInt8(offset);
        if (first < 253)
          return Object.assign(decode, { bytes: 1 }), first;
        if (first === 253)
          return Object.assign(decode, { bytes: 3 }), buffer.readUInt16LE(offset + 1);
        if (first === 254)
          return Object.assign(decode, { bytes: 5 }), buffer.readUInt32LE(offset + 1);
        {
          Object.assign(decode, { bytes: 9 });
          let lo = buffer.readUInt32LE(offset + 1), _number = buffer.readUInt32LE(offset + 5) * 4294967296 + lo;
          return checkUInt53(_number), _number;
        }
      }
      exports.decode = decode;
      function encodingLength(_number) {
        return checkUInt53(_number), _number < 253 ? 1 : _number <= 65535 ? 3 : _number <= 4294967295 ? 5 : 9;
      }
      exports.encodingLength = encodingLength;
    }
  });

  // node_modules/bip174/src/lib/converter/tools.js
  var require_tools = __commonJS({
    "node_modules/bip174/src/lib/converter/tools.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      var varuint = require_varint();
      exports.range = (n) => [...Array(n).keys()];
      function reverseBuffer(buffer) {
        if (buffer.length < 1) return buffer;
        let j = buffer.length - 1, tmp = 0;
        for (let i = 0; i < buffer.length / 2; i++)
          tmp = buffer[i], buffer[i] = buffer[j], buffer[j] = tmp, j--;
        return buffer;
      }
      exports.reverseBuffer = reverseBuffer;
      function keyValsToBuffer(keyVals) {
        let buffers = keyVals.map(keyValToBuffer);
        return buffers.push(import_buffer.Buffer.from([0])), import_buffer.Buffer.concat(buffers);
      }
      exports.keyValsToBuffer = keyValsToBuffer;
      function keyValToBuffer(keyVal) {
        let keyLen = keyVal.key.length, valLen = keyVal.value.length, keyVarIntLen = varuint.encodingLength(keyLen), valVarIntLen = varuint.encodingLength(valLen), buffer = import_buffer.Buffer.allocUnsafe(
          keyVarIntLen + keyLen + valVarIntLen + valLen
        );
        return varuint.encode(keyLen, buffer, 0), keyVal.key.copy(buffer, keyVarIntLen), varuint.encode(valLen, buffer, keyVarIntLen + keyLen), keyVal.value.copy(buffer, keyVarIntLen + keyLen + valVarIntLen), buffer;
      }
      exports.keyValToBuffer = keyValToBuffer;
      function verifuint(value, max) {
        if (typeof value != "number")
          throw new Error("cannot write a non-number as a number");
        if (value < 0)
          throw new Error("specified a negative value for writing an unsigned value");
        if (value > max) throw new Error("RangeError: value out of range");
        if (Math.floor(value) !== value)
          throw new Error("value has a fractional component");
      }
      function readUInt64LE(buffer, offset) {
        let a = buffer.readUInt32LE(offset), b = buffer.readUInt32LE(offset + 4);
        return b *= 4294967296, verifuint(b + a, 9007199254740991), b + a;
      }
      exports.readUInt64LE = readUInt64LE;
      function writeUInt64LE(buffer, value, offset) {
        return verifuint(value, 9007199254740991), buffer.writeInt32LE(value & -1, offset), buffer.writeUInt32LE(Math.floor(value / 4294967296), offset + 4), offset + 8;
      }
      exports.writeUInt64LE = writeUInt64LE;
    }
  });

  // node_modules/bip174/src/lib/converter/input/witnessUtxo.js
  var require_witnessUtxo = __commonJS({
    "node_modules/bip174/src/lib/converter/input/witnessUtxo.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      var typeFields_1 = require_typeFields(), tools_1 = require_tools(), varuint = require_varint();
      function decode(keyVal) {
        if (keyVal.key[0] !== typeFields_1.InputTypes.WITNESS_UTXO)
          throw new Error(
            "Decode Error: could not decode witnessUtxo with key 0x" + keyVal.key.toString("hex")
          );
        let value = tools_1.readUInt64LE(keyVal.value, 0), _offset = 8, scriptLen = varuint.decode(keyVal.value, _offset);
        _offset += varuint.encodingLength(scriptLen);
        let script2 = keyVal.value.slice(_offset);
        if (script2.length !== scriptLen)
          throw new Error("Decode Error: WITNESS_UTXO script is not proper length");
        return {
          script: script2,
          value
        };
      }
      exports.decode = decode;
      function encode(data) {
        let { script: script2, value } = data, varintLen = varuint.encodingLength(script2.length), result = import_buffer.Buffer.allocUnsafe(8 + varintLen + script2.length);
        return tools_1.writeUInt64LE(result, value, 0), varuint.encode(script2.length, result, 8), script2.copy(result, 8 + varintLen), {
          key: import_buffer.Buffer.from([typeFields_1.InputTypes.WITNESS_UTXO]),
          value: result
        };
      }
      exports.encode = encode;
      exports.expected = "{ script: Buffer; value: number; }";
      function check(data) {
        return import_buffer.Buffer.isBuffer(data.script) && typeof data.value == "number";
      }
      exports.check = check;
      function canAdd(currentData, newData) {
        return !!currentData && !!newData && currentData.witnessUtxo === void 0;
      }
      exports.canAdd = canAdd;
    }
  });

  // node_modules/bip174/src/lib/converter/output/tapTree.js
  var require_tapTree = __commonJS({
    "node_modules/bip174/src/lib/converter/output/tapTree.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      var typeFields_1 = require_typeFields(), varuint = require_varint();
      function decode(keyVal) {
        if (keyVal.key[0] !== typeFields_1.OutputTypes.TAP_TREE || keyVal.key.length !== 1)
          throw new Error(
            "Decode Error: could not decode tapTree with key 0x" + keyVal.key.toString("hex")
          );
        let _offset = 0, data = [];
        for (; _offset < keyVal.value.length; ) {
          let depth = keyVal.value[_offset++], leafVersion = keyVal.value[_offset++], scriptLen = varuint.decode(keyVal.value, _offset);
          _offset += varuint.encodingLength(scriptLen), data.push({
            depth,
            leafVersion,
            script: keyVal.value.slice(_offset, _offset + scriptLen)
          }), _offset += scriptLen;
        }
        return { leaves: data };
      }
      exports.decode = decode;
      function encode(tree) {
        let key = import_buffer.Buffer.from([typeFields_1.OutputTypes.TAP_TREE]), bufs = [].concat(
          ...tree.leaves.map((tapLeaf) => [
            import_buffer.Buffer.of(tapLeaf.depth, tapLeaf.leafVersion),
            varuint.encode(tapLeaf.script.length),
            tapLeaf.script
          ])
        );
        return {
          key,
          value: import_buffer.Buffer.concat(bufs)
        };
      }
      exports.encode = encode;
      exports.expected = "{ leaves: [{ depth: number; leafVersion: number, script: Buffer; }] }";
      function check(data) {
        return Array.isArray(data.leaves) && data.leaves.every(
          (tapLeaf) => tapLeaf.depth >= 0 && tapLeaf.depth <= 128 && (tapLeaf.leafVersion & 254) === tapLeaf.leafVersion && import_buffer.Buffer.isBuffer(tapLeaf.script)
        );
      }
      exports.check = check;
      function canAdd(currentData, newData) {
        return !!currentData && !!newData && currentData.tapTree === void 0;
      }
      exports.canAdd = canAdd;
    }
  });

  // node_modules/bip174/src/lib/converter/shared/bip32Derivation.js
  var require_bip32Derivation = __commonJS({
    "node_modules/bip174/src/lib/converter/shared/bip32Derivation.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      var range = (n) => [...Array(n).keys()], isValidDERKey = (pubkey) => pubkey.length === 33 && [2, 3].includes(pubkey[0]) || pubkey.length === 65 && pubkey[0] === 4;
      function makeConverter(TYPE_BYTE, isValidPubkey = isValidDERKey) {
        function decode(keyVal) {
          if (keyVal.key[0] !== TYPE_BYTE)
            throw new Error(
              "Decode Error: could not decode bip32Derivation with key 0x" + keyVal.key.toString("hex")
            );
          let pubkey = keyVal.key.slice(1);
          if (!isValidPubkey(pubkey))
            throw new Error(
              "Decode Error: bip32Derivation has invalid pubkey in key 0x" + keyVal.key.toString("hex")
            );
          if (keyVal.value.length / 4 % 1 !== 0)
            throw new Error(
              "Decode Error: Input BIP32_DERIVATION value length should be multiple of 4"
            );
          let data = {
            masterFingerprint: keyVal.value.slice(0, 4),
            pubkey,
            path: "m"
          };
          for (let i of range(keyVal.value.length / 4 - 1)) {
            let val = keyVal.value.readUInt32LE(i * 4 + 4), isHard = !!(val & 2147483648), idx = val & 2147483647;
            data.path += "/" + idx.toString(10) + (isHard ? "'" : "");
          }
          return data;
        }
        function encode(data) {
          let head = import_buffer.Buffer.from([TYPE_BYTE]), key = import_buffer.Buffer.concat([head, data.pubkey]), splitPath = data.path.split("/"), value = import_buffer.Buffer.allocUnsafe(splitPath.length * 4);
          data.masterFingerprint.copy(value, 0);
          let offset = 4;
          return splitPath.slice(1).forEach((level) => {
            let isHard = level.slice(-1) === "'", num = 2147483647 & parseInt(isHard ? level.slice(0, -1) : level, 10);
            isHard && (num += 2147483648), value.writeUInt32LE(num, offset), offset += 4;
          }), {
            key,
            value
          };
        }
        let expected = "{ masterFingerprint: Buffer; pubkey: Buffer; path: string; }";
        function check(data) {
          return import_buffer.Buffer.isBuffer(data.pubkey) && import_buffer.Buffer.isBuffer(data.masterFingerprint) && typeof data.path == "string" && isValidPubkey(data.pubkey) && data.masterFingerprint.length === 4;
        }
        function canAddToArray(array, item, dupeSet) {
          let dupeString = item.pubkey.toString("hex");
          return dupeSet.has(dupeString) ? !1 : (dupeSet.add(dupeString), array.filter((v) => v.pubkey.equals(item.pubkey)).length === 0);
        }
        return {
          decode,
          encode,
          check,
          expected,
          canAddToArray
        };
      }
      exports.makeConverter = makeConverter;
    }
  });

  // node_modules/bip174/src/lib/converter/shared/checkPubkey.js
  var require_checkPubkey = __commonJS({
    "node_modules/bip174/src/lib/converter/shared/checkPubkey.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      function makeChecker(pubkeyTypes) {
        return checkPubkey;
        function checkPubkey(keyVal) {
          let pubkey;
          if (pubkeyTypes.includes(keyVal.key[0]) && (pubkey = keyVal.key.slice(1), !(pubkey.length === 33 || pubkey.length === 65) || ![2, 3, 4].includes(pubkey[0])))
            throw new Error(
              "Format Error: invalid pubkey in key 0x" + keyVal.key.toString("hex")
            );
          return pubkey;
        }
      }
      exports.makeChecker = makeChecker;
    }
  });

  // node_modules/bip174/src/lib/converter/shared/redeemScript.js
  var require_redeemScript = __commonJS({
    "node_modules/bip174/src/lib/converter/shared/redeemScript.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      function makeConverter(TYPE_BYTE) {
        function decode(keyVal) {
          if (keyVal.key[0] !== TYPE_BYTE)
            throw new Error(
              "Decode Error: could not decode redeemScript with key 0x" + keyVal.key.toString("hex")
            );
          return keyVal.value;
        }
        function encode(data) {
          return {
            key: import_buffer.Buffer.from([TYPE_BYTE]),
            value: data
          };
        }
        let expected = "Buffer";
        function check(data) {
          return import_buffer.Buffer.isBuffer(data);
        }
        function canAdd(currentData, newData) {
          return !!currentData && !!newData && currentData.redeemScript === void 0;
        }
        return {
          decode,
          encode,
          check,
          expected,
          canAdd
        };
      }
      exports.makeConverter = makeConverter;
    }
  });

  // node_modules/bip174/src/lib/converter/shared/tapBip32Derivation.js
  var require_tapBip32Derivation = __commonJS({
    "node_modules/bip174/src/lib/converter/shared/tapBip32Derivation.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      var varuint = require_varint(), bip32Derivation = require_bip32Derivation(), isValidBIP340Key = (pubkey) => pubkey.length === 32;
      function makeConverter(TYPE_BYTE) {
        let parent = bip32Derivation.makeConverter(TYPE_BYTE, isValidBIP340Key);
        function decode(keyVal) {
          let nHashes = varuint.decode(keyVal.value), nHashesLen = varuint.encodingLength(nHashes), base = parent.decode({
            key: keyVal.key,
            value: keyVal.value.slice(nHashesLen + nHashes * 32)
          }), leafHashes = new Array(nHashes);
          for (let i = 0, _offset = nHashesLen; i < nHashes; i++, _offset += 32)
            leafHashes[i] = keyVal.value.slice(_offset, _offset + 32);
          return Object.assign({}, base, { leafHashes });
        }
        function encode(data) {
          let base = parent.encode(data), nHashesLen = varuint.encodingLength(data.leafHashes.length), nHashesBuf = import_buffer.Buffer.allocUnsafe(nHashesLen);
          varuint.encode(data.leafHashes.length, nHashesBuf);
          let value = import_buffer.Buffer.concat([nHashesBuf, ...data.leafHashes, base.value]);
          return Object.assign({}, base, { value });
        }
        let expected = "{ masterFingerprint: Buffer; pubkey: Buffer; path: string; leafHashes: Buffer[]; }";
        function check(data) {
          return Array.isArray(data.leafHashes) && data.leafHashes.every(
            (leafHash) => import_buffer.Buffer.isBuffer(leafHash) && leafHash.length === 32
          ) && parent.check(data);
        }
        return {
          decode,
          encode,
          check,
          expected,
          canAddToArray: parent.canAddToArray
        };
      }
      exports.makeConverter = makeConverter;
    }
  });

  // node_modules/bip174/src/lib/converter/shared/tapInternalKey.js
  var require_tapInternalKey = __commonJS({
    "node_modules/bip174/src/lib/converter/shared/tapInternalKey.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      function makeConverter(TYPE_BYTE) {
        function decode(keyVal) {
          if (keyVal.key[0] !== TYPE_BYTE || keyVal.key.length !== 1)
            throw new Error(
              "Decode Error: could not decode tapInternalKey with key 0x" + keyVal.key.toString("hex")
            );
          if (keyVal.value.length !== 32)
            throw new Error(
              "Decode Error: tapInternalKey not a 32-byte x-only pubkey"
            );
          return keyVal.value;
        }
        function encode(value) {
          return { key: import_buffer.Buffer.from([TYPE_BYTE]), value };
        }
        let expected = "Buffer";
        function check(data) {
          return import_buffer.Buffer.isBuffer(data) && data.length === 32;
        }
        function canAdd(currentData, newData) {
          return !!currentData && !!newData && currentData.tapInternalKey === void 0;
        }
        return {
          decode,
          encode,
          check,
          expected,
          canAdd
        };
      }
      exports.makeConverter = makeConverter;
    }
  });

  // node_modules/bip174/src/lib/converter/shared/witnessScript.js
  var require_witnessScript = __commonJS({
    "node_modules/bip174/src/lib/converter/shared/witnessScript.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      function makeConverter(TYPE_BYTE) {
        function decode(keyVal) {
          if (keyVal.key[0] !== TYPE_BYTE)
            throw new Error(
              "Decode Error: could not decode witnessScript with key 0x" + keyVal.key.toString("hex")
            );
          return keyVal.value;
        }
        function encode(data) {
          return {
            key: import_buffer.Buffer.from([TYPE_BYTE]),
            value: data
          };
        }
        let expected = "Buffer";
        function check(data) {
          return import_buffer.Buffer.isBuffer(data);
        }
        function canAdd(currentData, newData) {
          return !!currentData && !!newData && currentData.witnessScript === void 0;
        }
        return {
          decode,
          encode,
          check,
          expected,
          canAdd
        };
      }
      exports.makeConverter = makeConverter;
    }
  });

  // node_modules/bip174/src/lib/converter/index.js
  var require_converter = __commonJS({
    "node_modules/bip174/src/lib/converter/index.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      var typeFields_1 = require_typeFields(), globalXpub = require_globalXpub(), unsignedTx = require_unsignedTx(), finalScriptSig = require_finalScriptSig(), finalScriptWitness = require_finalScriptWitness(), nonWitnessUtxo = require_nonWitnessUtxo(), partialSig = require_partialSig(), porCommitment = require_porCommitment(), sighashType = require_sighashType(), tapKeySig = require_tapKeySig(), tapLeafScript = require_tapLeafScript(), tapMerkleRoot = require_tapMerkleRoot(), tapScriptSig = require_tapScriptSig(), witnessUtxo = require_witnessUtxo(), tapTree = require_tapTree(), bip32Derivation = require_bip32Derivation(), checkPubkey = require_checkPubkey(), redeemScript = require_redeemScript(), tapBip32Derivation = require_tapBip32Derivation(), tapInternalKey = require_tapInternalKey(), witnessScript = require_witnessScript(), globals = {
        unsignedTx,
        globalXpub,
        // pass an Array of key bytes that require pubkey beside the key
        checkPubkey: checkPubkey.makeChecker([])
      };
      exports.globals = globals;
      var inputs = {
        nonWitnessUtxo,
        partialSig,
        sighashType,
        finalScriptSig,
        finalScriptWitness,
        porCommitment,
        witnessUtxo,
        bip32Derivation: bip32Derivation.makeConverter(
          typeFields_1.InputTypes.BIP32_DERIVATION
        ),
        redeemScript: redeemScript.makeConverter(
          typeFields_1.InputTypes.REDEEM_SCRIPT
        ),
        witnessScript: witnessScript.makeConverter(
          typeFields_1.InputTypes.WITNESS_SCRIPT
        ),
        checkPubkey: checkPubkey.makeChecker([
          typeFields_1.InputTypes.PARTIAL_SIG,
          typeFields_1.InputTypes.BIP32_DERIVATION
        ]),
        tapKeySig,
        tapScriptSig,
        tapLeafScript,
        tapBip32Derivation: tapBip32Derivation.makeConverter(
          typeFields_1.InputTypes.TAP_BIP32_DERIVATION
        ),
        tapInternalKey: tapInternalKey.makeConverter(
          typeFields_1.InputTypes.TAP_INTERNAL_KEY
        ),
        tapMerkleRoot
      };
      exports.inputs = inputs;
      var outputs = {
        bip32Derivation: bip32Derivation.makeConverter(
          typeFields_1.OutputTypes.BIP32_DERIVATION
        ),
        redeemScript: redeemScript.makeConverter(
          typeFields_1.OutputTypes.REDEEM_SCRIPT
        ),
        witnessScript: witnessScript.makeConverter(
          typeFields_1.OutputTypes.WITNESS_SCRIPT
        ),
        checkPubkey: checkPubkey.makeChecker([
          typeFields_1.OutputTypes.BIP32_DERIVATION
        ]),
        tapBip32Derivation: tapBip32Derivation.makeConverter(
          typeFields_1.OutputTypes.TAP_BIP32_DERIVATION
        ),
        tapTree,
        tapInternalKey: tapInternalKey.makeConverter(
          typeFields_1.OutputTypes.TAP_INTERNAL_KEY
        )
      };
      exports.outputs = outputs;
    }
  });

  // node_modules/bip174/src/lib/parser/fromBuffer.js
  var require_fromBuffer = __commonJS({
    "node_modules/bip174/src/lib/parser/fromBuffer.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      var convert = require_converter(), tools_1 = require_tools(), varuint = require_varint(), typeFields_1 = require_typeFields();
      function psbtFromBuffer(buffer, txGetter) {
        let offset = 0;
        function varSlice() {
          let keyLen = varuint.decode(buffer, offset);
          offset += varuint.encodingLength(keyLen);
          let key = buffer.slice(offset, offset + keyLen);
          return offset += keyLen, key;
        }
        function readUInt32BE() {
          let num = buffer.readUInt32BE(offset);
          return offset += 4, num;
        }
        function readUInt8() {
          let num = buffer.readUInt8(offset);
          return offset += 1, num;
        }
        function getKeyValue() {
          let key = varSlice(), value = varSlice();
          return {
            key,
            value
          };
        }
        function checkEndOfKeyValPairs() {
          if (offset >= buffer.length)
            throw new Error("Format Error: Unexpected End of PSBT");
          let isEnd = buffer.readUInt8(offset) === 0;
          return isEnd && offset++, isEnd;
        }
        if (readUInt32BE() !== 1886610036)
          throw new Error("Format Error: Invalid Magic Number");
        if (readUInt8() !== 255)
          throw new Error(
            "Format Error: Magic Number must be followed by 0xff separator"
          );
        let globalMapKeyVals = [], globalKeyIndex = {};
        for (; !checkEndOfKeyValPairs(); ) {
          let keyVal = getKeyValue(), hexKey = keyVal.key.toString("hex");
          if (globalKeyIndex[hexKey])
            throw new Error(
              "Format Error: Keys must be unique for global keymap: key " + hexKey
            );
          globalKeyIndex[hexKey] = 1, globalMapKeyVals.push(keyVal);
        }
        let unsignedTxMaps = globalMapKeyVals.filter(
          (keyVal) => keyVal.key[0] === typeFields_1.GlobalTypes.UNSIGNED_TX
        );
        if (unsignedTxMaps.length !== 1)
          throw new Error("Format Error: Only one UNSIGNED_TX allowed");
        let unsignedTx = txGetter(unsignedTxMaps[0].value), { inputCount, outputCount } = unsignedTx.getInputOutputCounts(), inputKeyVals = [], outputKeyVals = [];
        for (let index of tools_1.range(inputCount)) {
          let inputKeyIndex = {}, input = [];
          for (; !checkEndOfKeyValPairs(); ) {
            let keyVal = getKeyValue(), hexKey = keyVal.key.toString("hex");
            if (inputKeyIndex[hexKey])
              throw new Error(
                "Format Error: Keys must be unique for each input: input index " + index + " key " + hexKey
              );
            inputKeyIndex[hexKey] = 1, input.push(keyVal);
          }
          inputKeyVals.push(input);
        }
        for (let index of tools_1.range(outputCount)) {
          let outputKeyIndex = {}, output = [];
          for (; !checkEndOfKeyValPairs(); ) {
            let keyVal = getKeyValue(), hexKey = keyVal.key.toString("hex");
            if (outputKeyIndex[hexKey])
              throw new Error(
                "Format Error: Keys must be unique for each output: output index " + index + " key " + hexKey
              );
            outputKeyIndex[hexKey] = 1, output.push(keyVal);
          }
          outputKeyVals.push(output);
        }
        return psbtFromKeyVals(unsignedTx, {
          globalMapKeyVals,
          inputKeyVals,
          outputKeyVals
        });
      }
      exports.psbtFromBuffer = psbtFromBuffer;
      function checkKeyBuffer(type, keyBuf, keyNum) {
        if (!keyBuf.equals(import_buffer.Buffer.from([keyNum])))
          throw new Error(
            `Format Error: Invalid ${type} key: ${keyBuf.toString("hex")}`
          );
      }
      exports.checkKeyBuffer = checkKeyBuffer;
      function psbtFromKeyVals(unsignedTx, { globalMapKeyVals, inputKeyVals, outputKeyVals }) {
        let globalMap = {
          unsignedTx
        }, txCount = 0;
        for (let keyVal of globalMapKeyVals)
          switch (keyVal.key[0]) {
            case typeFields_1.GlobalTypes.UNSIGNED_TX:
              if (checkKeyBuffer(
                "global",
                keyVal.key,
                typeFields_1.GlobalTypes.UNSIGNED_TX
              ), txCount > 0)
                throw new Error("Format Error: GlobalMap has multiple UNSIGNED_TX");
              txCount++;
              break;
            case typeFields_1.GlobalTypes.GLOBAL_XPUB:
              globalMap.globalXpub === void 0 && (globalMap.globalXpub = []), globalMap.globalXpub.push(convert.globals.globalXpub.decode(keyVal));
              break;
            default:
              globalMap.unknownKeyVals || (globalMap.unknownKeyVals = []), globalMap.unknownKeyVals.push(keyVal);
          }
        let inputCount = inputKeyVals.length, outputCount = outputKeyVals.length, inputs = [], outputs = [];
        for (let index of tools_1.range(inputCount)) {
          let input = {};
          for (let keyVal of inputKeyVals[index])
            switch (convert.inputs.checkPubkey(keyVal), keyVal.key[0]) {
              case typeFields_1.InputTypes.NON_WITNESS_UTXO:
                if (checkKeyBuffer(
                  "input",
                  keyVal.key,
                  typeFields_1.InputTypes.NON_WITNESS_UTXO
                ), input.nonWitnessUtxo !== void 0)
                  throw new Error(
                    "Format Error: Input has multiple NON_WITNESS_UTXO"
                  );
                input.nonWitnessUtxo = convert.inputs.nonWitnessUtxo.decode(keyVal);
                break;
              case typeFields_1.InputTypes.WITNESS_UTXO:
                if (checkKeyBuffer(
                  "input",
                  keyVal.key,
                  typeFields_1.InputTypes.WITNESS_UTXO
                ), input.witnessUtxo !== void 0)
                  throw new Error("Format Error: Input has multiple WITNESS_UTXO");
                input.witnessUtxo = convert.inputs.witnessUtxo.decode(keyVal);
                break;
              case typeFields_1.InputTypes.PARTIAL_SIG:
                input.partialSig === void 0 && (input.partialSig = []), input.partialSig.push(convert.inputs.partialSig.decode(keyVal));
                break;
              case typeFields_1.InputTypes.SIGHASH_TYPE:
                if (checkKeyBuffer(
                  "input",
                  keyVal.key,
                  typeFields_1.InputTypes.SIGHASH_TYPE
                ), input.sighashType !== void 0)
                  throw new Error("Format Error: Input has multiple SIGHASH_TYPE");
                input.sighashType = convert.inputs.sighashType.decode(keyVal);
                break;
              case typeFields_1.InputTypes.REDEEM_SCRIPT:
                if (checkKeyBuffer(
                  "input",
                  keyVal.key,
                  typeFields_1.InputTypes.REDEEM_SCRIPT
                ), input.redeemScript !== void 0)
                  throw new Error("Format Error: Input has multiple REDEEM_SCRIPT");
                input.redeemScript = convert.inputs.redeemScript.decode(keyVal);
                break;
              case typeFields_1.InputTypes.WITNESS_SCRIPT:
                if (checkKeyBuffer(
                  "input",
                  keyVal.key,
                  typeFields_1.InputTypes.WITNESS_SCRIPT
                ), input.witnessScript !== void 0)
                  throw new Error("Format Error: Input has multiple WITNESS_SCRIPT");
                input.witnessScript = convert.inputs.witnessScript.decode(keyVal);
                break;
              case typeFields_1.InputTypes.BIP32_DERIVATION:
                input.bip32Derivation === void 0 && (input.bip32Derivation = []), input.bip32Derivation.push(
                  convert.inputs.bip32Derivation.decode(keyVal)
                );
                break;
              case typeFields_1.InputTypes.FINAL_SCRIPTSIG:
                checkKeyBuffer(
                  "input",
                  keyVal.key,
                  typeFields_1.InputTypes.FINAL_SCRIPTSIG
                ), input.finalScriptSig = convert.inputs.finalScriptSig.decode(keyVal);
                break;
              case typeFields_1.InputTypes.FINAL_SCRIPTWITNESS:
                checkKeyBuffer(
                  "input",
                  keyVal.key,
                  typeFields_1.InputTypes.FINAL_SCRIPTWITNESS
                ), input.finalScriptWitness = convert.inputs.finalScriptWitness.decode(
                  keyVal
                );
                break;
              case typeFields_1.InputTypes.POR_COMMITMENT:
                checkKeyBuffer(
                  "input",
                  keyVal.key,
                  typeFields_1.InputTypes.POR_COMMITMENT
                ), input.porCommitment = convert.inputs.porCommitment.decode(keyVal);
                break;
              case typeFields_1.InputTypes.TAP_KEY_SIG:
                checkKeyBuffer(
                  "input",
                  keyVal.key,
                  typeFields_1.InputTypes.TAP_KEY_SIG
                ), input.tapKeySig = convert.inputs.tapKeySig.decode(keyVal);
                break;
              case typeFields_1.InputTypes.TAP_SCRIPT_SIG:
                input.tapScriptSig === void 0 && (input.tapScriptSig = []), input.tapScriptSig.push(convert.inputs.tapScriptSig.decode(keyVal));
                break;
              case typeFields_1.InputTypes.TAP_LEAF_SCRIPT:
                input.tapLeafScript === void 0 && (input.tapLeafScript = []), input.tapLeafScript.push(convert.inputs.tapLeafScript.decode(keyVal));
                break;
              case typeFields_1.InputTypes.TAP_BIP32_DERIVATION:
                input.tapBip32Derivation === void 0 && (input.tapBip32Derivation = []), input.tapBip32Derivation.push(
                  convert.inputs.tapBip32Derivation.decode(keyVal)
                );
                break;
              case typeFields_1.InputTypes.TAP_INTERNAL_KEY:
                checkKeyBuffer(
                  "input",
                  keyVal.key,
                  typeFields_1.InputTypes.TAP_INTERNAL_KEY
                ), input.tapInternalKey = convert.inputs.tapInternalKey.decode(keyVal);
                break;
              case typeFields_1.InputTypes.TAP_MERKLE_ROOT:
                checkKeyBuffer(
                  "input",
                  keyVal.key,
                  typeFields_1.InputTypes.TAP_MERKLE_ROOT
                ), input.tapMerkleRoot = convert.inputs.tapMerkleRoot.decode(keyVal);
                break;
              default:
                input.unknownKeyVals || (input.unknownKeyVals = []), input.unknownKeyVals.push(keyVal);
            }
          inputs.push(input);
        }
        for (let index of tools_1.range(outputCount)) {
          let output = {};
          for (let keyVal of outputKeyVals[index])
            switch (convert.outputs.checkPubkey(keyVal), keyVal.key[0]) {
              case typeFields_1.OutputTypes.REDEEM_SCRIPT:
                if (checkKeyBuffer(
                  "output",
                  keyVal.key,
                  typeFields_1.OutputTypes.REDEEM_SCRIPT
                ), output.redeemScript !== void 0)
                  throw new Error("Format Error: Output has multiple REDEEM_SCRIPT");
                output.redeemScript = convert.outputs.redeemScript.decode(keyVal);
                break;
              case typeFields_1.OutputTypes.WITNESS_SCRIPT:
                if (checkKeyBuffer(
                  "output",
                  keyVal.key,
                  typeFields_1.OutputTypes.WITNESS_SCRIPT
                ), output.witnessScript !== void 0)
                  throw new Error("Format Error: Output has multiple WITNESS_SCRIPT");
                output.witnessScript = convert.outputs.witnessScript.decode(keyVal);
                break;
              case typeFields_1.OutputTypes.BIP32_DERIVATION:
                output.bip32Derivation === void 0 && (output.bip32Derivation = []), output.bip32Derivation.push(
                  convert.outputs.bip32Derivation.decode(keyVal)
                );
                break;
              case typeFields_1.OutputTypes.TAP_INTERNAL_KEY:
                checkKeyBuffer(
                  "output",
                  keyVal.key,
                  typeFields_1.OutputTypes.TAP_INTERNAL_KEY
                ), output.tapInternalKey = convert.outputs.tapInternalKey.decode(keyVal);
                break;
              case typeFields_1.OutputTypes.TAP_TREE:
                checkKeyBuffer(
                  "output",
                  keyVal.key,
                  typeFields_1.OutputTypes.TAP_TREE
                ), output.tapTree = convert.outputs.tapTree.decode(keyVal);
                break;
              case typeFields_1.OutputTypes.TAP_BIP32_DERIVATION:
                output.tapBip32Derivation === void 0 && (output.tapBip32Derivation = []), output.tapBip32Derivation.push(
                  convert.outputs.tapBip32Derivation.decode(keyVal)
                );
                break;
              default:
                output.unknownKeyVals || (output.unknownKeyVals = []), output.unknownKeyVals.push(keyVal);
            }
          outputs.push(output);
        }
        return { globalMap, inputs, outputs };
      }
      exports.psbtFromKeyVals = psbtFromKeyVals;
    }
  });

  // node_modules/bip174/src/lib/parser/toBuffer.js
  var require_toBuffer = __commonJS({
    "node_modules/bip174/src/lib/parser/toBuffer.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      var convert = require_converter(), tools_1 = require_tools();
      function psbtToBuffer({ globalMap, inputs, outputs }) {
        let { globalKeyVals, inputKeyVals, outputKeyVals } = psbtToKeyVals({
          globalMap,
          inputs,
          outputs
        }), globalBuffer = tools_1.keyValsToBuffer(globalKeyVals), keyValsOrEmptyToBuffer = (keyVals) => keyVals.length === 0 ? [import_buffer.Buffer.from([0])] : keyVals.map(tools_1.keyValsToBuffer), inputBuffers = keyValsOrEmptyToBuffer(inputKeyVals), outputBuffers = keyValsOrEmptyToBuffer(outputKeyVals), header = import_buffer.Buffer.allocUnsafe(5);
        return header.writeUIntBE(482972169471, 0, 5), import_buffer.Buffer.concat(
          [header, globalBuffer].concat(inputBuffers, outputBuffers)
        );
      }
      exports.psbtToBuffer = psbtToBuffer;
      var sortKeyVals = (a, b) => a.key.compare(b.key);
      function keyValsFromMap(keyValMap, converterFactory) {
        let keyHexSet = /* @__PURE__ */ new Set(), keyVals = Object.entries(keyValMap).reduce((result, [key, value]) => {
          if (key === "unknownKeyVals") return result;
          let converter = converterFactory[key];
          if (converter === void 0) return result;
          let encodedKeyVals = (Array.isArray(value) ? value : [value]).map(
            converter.encode
          );
          return encodedKeyVals.map((kv) => kv.key.toString("hex")).forEach((hex) => {
            if (keyHexSet.has(hex))
              throw new Error("Serialize Error: Duplicate key: " + hex);
            keyHexSet.add(hex);
          }), result.concat(encodedKeyVals);
        }, []), otherKeyVals = keyValMap.unknownKeyVals ? keyValMap.unknownKeyVals.filter((keyVal) => !keyHexSet.has(keyVal.key.toString("hex"))) : [];
        return keyVals.concat(otherKeyVals).sort(sortKeyVals);
      }
      function psbtToKeyVals({ globalMap, inputs, outputs }) {
        return {
          globalKeyVals: keyValsFromMap(globalMap, convert.globals),
          inputKeyVals: inputs.map((i) => keyValsFromMap(i, convert.inputs)),
          outputKeyVals: outputs.map((o) => keyValsFromMap(o, convert.outputs))
        };
      }
      exports.psbtToKeyVals = psbtToKeyVals;
    }
  });

  // node_modules/bip174/src/lib/parser/index.js
  var require_parser = __commonJS({
    "node_modules/bip174/src/lib/parser/index.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      function __export2(m) {
        for (var p in m) exports.hasOwnProperty(p) || (exports[p] = m[p]);
      }
      Object.defineProperty(exports, "__esModule", { value: !0 });
      __export2(require_fromBuffer());
      __export2(require_toBuffer());
    }
  });

  // node_modules/bip174/src/lib/combiner/index.js
  var require_combiner = __commonJS({
    "node_modules/bip174/src/lib/combiner/index.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      var parser_1 = require_parser();
      function combine(psbts) {
        let self2 = psbts[0], selfKeyVals = parser_1.psbtToKeyVals(self2), others = psbts.slice(1);
        if (others.length === 0) throw new Error("Combine: Nothing to combine");
        let selfTx = getTx(self2);
        if (selfTx === void 0)
          throw new Error("Combine: Self missing transaction");
        let selfGlobalSet = getKeySet(selfKeyVals.globalKeyVals), selfInputSets = selfKeyVals.inputKeyVals.map(getKeySet), selfOutputSets = selfKeyVals.outputKeyVals.map(getKeySet);
        for (let other of others) {
          let otherTx = getTx(other);
          if (otherTx === void 0 || !otherTx.toBuffer().equals(selfTx.toBuffer()))
            throw new Error(
              "Combine: One of the Psbts does not have the same transaction."
            );
          let otherKeyVals = parser_1.psbtToKeyVals(other);
          getKeySet(otherKeyVals.globalKeyVals).forEach(
            keyPusher(
              selfGlobalSet,
              selfKeyVals.globalKeyVals,
              otherKeyVals.globalKeyVals
            )
          ), otherKeyVals.inputKeyVals.map(getKeySet).forEach(
            (inputSet, idx) => inputSet.forEach(
              keyPusher(
                selfInputSets[idx],
                selfKeyVals.inputKeyVals[idx],
                otherKeyVals.inputKeyVals[idx]
              )
            )
          ), otherKeyVals.outputKeyVals.map(getKeySet).forEach(
            (outputSet, idx) => outputSet.forEach(
              keyPusher(
                selfOutputSets[idx],
                selfKeyVals.outputKeyVals[idx],
                otherKeyVals.outputKeyVals[idx]
              )
            )
          );
        }
        return parser_1.psbtFromKeyVals(selfTx, {
          globalMapKeyVals: selfKeyVals.globalKeyVals,
          inputKeyVals: selfKeyVals.inputKeyVals,
          outputKeyVals: selfKeyVals.outputKeyVals
        });
      }
      exports.combine = combine;
      function keyPusher(selfSet, selfKeyVals, otherKeyVals) {
        return (key) => {
          if (selfSet.has(key)) return;
          let newKv = otherKeyVals.filter((kv) => kv.key.toString("hex") === key)[0];
          selfKeyVals.push(newKv), selfSet.add(key);
        };
      }
      function getTx(psbt) {
        return psbt.globalMap.unsignedTx;
      }
      function getKeySet(keyVals) {
        let set = /* @__PURE__ */ new Set();
        return keyVals.forEach((keyVal) => {
          let hex = keyVal.key.toString("hex");
          if (set.has(hex))
            throw new Error("Combine: KeyValue Map keys should be unique");
          set.add(hex);
        }), set;
      }
    }
  });

  // node_modules/bip174/src/lib/utils.js
  var require_utils2 = __commonJS({
    "node_modules/bip174/src/lib/utils.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      var converter = require_converter();
      function checkForInput(inputs, inputIndex) {
        let input = inputs[inputIndex];
        if (input === void 0) throw new Error(`No input #${inputIndex}`);
        return input;
      }
      exports.checkForInput = checkForInput;
      function checkForOutput(outputs, outputIndex) {
        let output = outputs[outputIndex];
        if (output === void 0) throw new Error(`No output #${outputIndex}`);
        return output;
      }
      exports.checkForOutput = checkForOutput;
      function checkHasKey(checkKeyVal, keyVals, enumLength) {
        if (checkKeyVal.key[0] < enumLength)
          throw new Error(
            "Use the method for your specific key instead of addUnknownKeyVal*"
          );
        if (keyVals && keyVals.filter((kv) => kv.key.equals(checkKeyVal.key)).length !== 0)
          throw new Error(`Duplicate Key: ${checkKeyVal.key.toString("hex")}`);
      }
      exports.checkHasKey = checkHasKey;
      function getEnumLength(myenum) {
        let count = 0;
        return Object.keys(myenum).forEach((val) => {
          Number(isNaN(Number(val))) && count++;
        }), count;
      }
      exports.getEnumLength = getEnumLength;
      function inputCheckUncleanFinalized(inputIndex, input) {
        let result = !1;
        if (input.nonWitnessUtxo || input.witnessUtxo) {
          let needScriptSig = !!input.redeemScript, needWitnessScript = !!input.witnessScript, scriptSigOK = !needScriptSig || !!input.finalScriptSig, witnessScriptOK = !needWitnessScript || !!input.finalScriptWitness, hasOneFinal = !!input.finalScriptSig || !!input.finalScriptWitness;
          result = scriptSigOK && witnessScriptOK && hasOneFinal;
        }
        if (result === !1)
          throw new Error(
            `Input #${inputIndex} has too much or too little data to clean`
          );
      }
      exports.inputCheckUncleanFinalized = inputCheckUncleanFinalized;
      function throwForUpdateMaker(typeName, name, expected, data) {
        throw new Error(
          `Data for ${typeName} key ${name} is incorrect: Expected ${expected} and got ${JSON.stringify(data)}`
        );
      }
      function updateMaker(typeName) {
        return (updateData, mainData) => {
          for (let name of Object.keys(updateData)) {
            let data = updateData[name], { canAdd, canAddToArray, check, expected } = (
              // @ts-ignore
              converter[typeName + "s"][name] || {}
            ), isArray = !!canAddToArray;
            if (check)
              if (isArray) {
                if (!Array.isArray(data) || // @ts-ignore
                mainData[name] && !Array.isArray(mainData[name]))
                  throw new Error(`Key type ${name} must be an array`);
                data.every(check) || throwForUpdateMaker(typeName, name, expected, data);
                let arr = mainData[name] || [], dupeCheckSet = /* @__PURE__ */ new Set();
                if (!data.every((v) => canAddToArray(arr, v, dupeCheckSet)))
                  throw new Error("Can not add duplicate data to array");
                mainData[name] = arr.concat(data);
              } else {
                if (check(data) || throwForUpdateMaker(typeName, name, expected, data), !canAdd(mainData, data))
                  throw new Error(`Can not add duplicate data to ${typeName}`);
                mainData[name] = data;
              }
          }
        };
      }
      exports.updateGlobal = updateMaker("global");
      exports.updateInput = updateMaker("input");
      exports.updateOutput = updateMaker("output");
      function addInputAttributes(inputs, data) {
        let index = inputs.length - 1, input = checkForInput(inputs, index);
        exports.updateInput(data, input);
      }
      exports.addInputAttributes = addInputAttributes;
      function addOutputAttributes(outputs, data) {
        let index = outputs.length - 1, output = checkForOutput(outputs, index);
        exports.updateOutput(data, output);
      }
      exports.addOutputAttributes = addOutputAttributes;
      function defaultVersionSetter(version, txBuf) {
        if (!import_buffer.Buffer.isBuffer(txBuf) || txBuf.length < 4)
          throw new Error("Set Version: Invalid Transaction");
        return txBuf.writeUInt32LE(version, 0), txBuf;
      }
      exports.defaultVersionSetter = defaultVersionSetter;
      function defaultLocktimeSetter(locktime, txBuf) {
        if (!import_buffer.Buffer.isBuffer(txBuf) || txBuf.length < 4)
          throw new Error("Set Locktime: Invalid Transaction");
        return txBuf.writeUInt32LE(locktime, txBuf.length - 4), txBuf;
      }
      exports.defaultLocktimeSetter = defaultLocktimeSetter;
    }
  });

  // node_modules/bip174/src/lib/psbt.js
  var require_psbt = __commonJS({
    "node_modules/bip174/src/lib/psbt.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      var combiner_1 = require_combiner(), parser_1 = require_parser(), typeFields_1 = require_typeFields(), utils_1 = require_utils2(), Psbt2 = class {
        constructor(tx) {
          this.inputs = [], this.outputs = [], this.globalMap = {
            unsignedTx: tx
          };
        }
        static fromBase64(data, txFromBuffer) {
          let buffer = import_buffer.Buffer.from(data, "base64");
          return this.fromBuffer(buffer, txFromBuffer);
        }
        static fromHex(data, txFromBuffer) {
          let buffer = import_buffer.Buffer.from(data, "hex");
          return this.fromBuffer(buffer, txFromBuffer);
        }
        static fromBuffer(buffer, txFromBuffer) {
          let results = parser_1.psbtFromBuffer(buffer, txFromBuffer), psbt = new this(results.globalMap.unsignedTx);
          return Object.assign(psbt, results), psbt;
        }
        toBase64() {
          return this.toBuffer().toString("base64");
        }
        toHex() {
          return this.toBuffer().toString("hex");
        }
        toBuffer() {
          return parser_1.psbtToBuffer(this);
        }
        updateGlobal(updateData) {
          return utils_1.updateGlobal(updateData, this.globalMap), this;
        }
        updateInput(inputIndex, updateData) {
          let input = utils_1.checkForInput(this.inputs, inputIndex);
          return utils_1.updateInput(updateData, input), this;
        }
        updateOutput(outputIndex, updateData) {
          let output = utils_1.checkForOutput(this.outputs, outputIndex);
          return utils_1.updateOutput(updateData, output), this;
        }
        addUnknownKeyValToGlobal(keyVal) {
          return utils_1.checkHasKey(
            keyVal,
            this.globalMap.unknownKeyVals,
            utils_1.getEnumLength(typeFields_1.GlobalTypes)
          ), this.globalMap.unknownKeyVals || (this.globalMap.unknownKeyVals = []), this.globalMap.unknownKeyVals.push(keyVal), this;
        }
        addUnknownKeyValToInput(inputIndex, keyVal) {
          let input = utils_1.checkForInput(this.inputs, inputIndex);
          return utils_1.checkHasKey(
            keyVal,
            input.unknownKeyVals,
            utils_1.getEnumLength(typeFields_1.InputTypes)
          ), input.unknownKeyVals || (input.unknownKeyVals = []), input.unknownKeyVals.push(keyVal), this;
        }
        addUnknownKeyValToOutput(outputIndex, keyVal) {
          let output = utils_1.checkForOutput(this.outputs, outputIndex);
          return utils_1.checkHasKey(
            keyVal,
            output.unknownKeyVals,
            utils_1.getEnumLength(typeFields_1.OutputTypes)
          ), output.unknownKeyVals || (output.unknownKeyVals = []), output.unknownKeyVals.push(keyVal), this;
        }
        addInput(inputData) {
          this.globalMap.unsignedTx.addInput(inputData), this.inputs.push({
            unknownKeyVals: []
          });
          let addKeyVals = inputData.unknownKeyVals || [], inputIndex = this.inputs.length - 1;
          if (!Array.isArray(addKeyVals))
            throw new Error("unknownKeyVals must be an Array");
          return addKeyVals.forEach(
            (keyVal) => this.addUnknownKeyValToInput(inputIndex, keyVal)
          ), utils_1.addInputAttributes(this.inputs, inputData), this;
        }
        addOutput(outputData) {
          this.globalMap.unsignedTx.addOutput(outputData), this.outputs.push({
            unknownKeyVals: []
          });
          let addKeyVals = outputData.unknownKeyVals || [], outputIndex = this.outputs.length - 1;
          if (!Array.isArray(addKeyVals))
            throw new Error("unknownKeyVals must be an Array");
          return addKeyVals.forEach(
            (keyVal) => this.addUnknownKeyValToOutput(outputIndex, keyVal)
          ), utils_1.addOutputAttributes(this.outputs, outputData), this;
        }
        clearFinalizedInput(inputIndex) {
          let input = utils_1.checkForInput(this.inputs, inputIndex);
          utils_1.inputCheckUncleanFinalized(inputIndex, input);
          for (let key of Object.keys(input))
            [
              "witnessUtxo",
              "nonWitnessUtxo",
              "finalScriptSig",
              "finalScriptWitness",
              "unknownKeyVals"
            ].includes(key) || delete input[key];
          return this;
        }
        combine(...those) {
          let result = combiner_1.combine([this].concat(those));
          return Object.assign(this, result), this;
        }
        getTransaction() {
          return this.globalMap.unsignedTx.toBuffer();
        }
      };
      exports.Psbt = Psbt2;
    }
  });

  // node_modules/bitcoinjs-lib/src/psbt/psbtutils.js
  var require_psbtutils = __commonJS({
    "node_modules/bitcoinjs-lib/src/psbt/psbtutils.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      exports.signatureBlocksAction = exports.checkInputForSig = exports.pubkeyInScript = exports.pubkeyPositionInScript = exports.witnessStackToScriptWitness = exports.isP2TR = exports.isP2SHScript = exports.isP2WSHScript = exports.isP2WPKH = exports.isP2PKH = exports.isP2PK = exports.isP2MS = void 0;
      var varuint = require_varint(), bscript = require_script(), transaction_1 = require_transaction(), crypto_1 = require_crypto2(), payments2 = require_payments();
      function isPaymentFactory(payment) {
        return (script2) => {
          try {
            return payment({ output: script2 }), !0;
          } catch {
            return !1;
          }
        };
      }
      exports.isP2MS = isPaymentFactory(payments2.p2ms);
      exports.isP2PK = isPaymentFactory(payments2.p2pk);
      exports.isP2PKH = isPaymentFactory(payments2.p2pkh);
      exports.isP2WPKH = isPaymentFactory(payments2.p2wpkh);
      exports.isP2WSHScript = isPaymentFactory(payments2.p2wsh);
      exports.isP2SHScript = isPaymentFactory(payments2.p2sh);
      exports.isP2TR = isPaymentFactory(payments2.p2tr);
      function witnessStackToScriptWitness(witness) {
        let buffer = import_buffer.Buffer.allocUnsafe(0);
        function writeSlice(slice) {
          buffer = import_buffer.Buffer.concat([buffer, import_buffer.Buffer.from(slice)]);
        }
        function writeVarInt(i) {
          let currentLen = buffer.length, varintLen = varuint.encodingLength(i);
          buffer = import_buffer.Buffer.concat([buffer, import_buffer.Buffer.allocUnsafe(varintLen)]), varuint.encode(i, buffer, currentLen);
        }
        function writeVarSlice(slice) {
          writeVarInt(slice.length), writeSlice(slice);
        }
        function writeVector(vector) {
          writeVarInt(vector.length), vector.forEach(writeVarSlice);
        }
        return writeVector(witness), buffer;
      }
      exports.witnessStackToScriptWitness = witnessStackToScriptWitness;
      function pubkeyPositionInScript(pubkey, script2) {
        let pubkeyHash = (0, crypto_1.hash160)(pubkey), pubkeyXOnly = pubkey.slice(1, 33), decompiled = bscript.decompile(script2);
        if (decompiled === null) throw new Error("Unknown script error");
        return decompiled.findIndex((element) => typeof element == "number" ? !1 : element.equals(pubkey) || element.equals(pubkeyHash) || element.equals(pubkeyXOnly));
      }
      exports.pubkeyPositionInScript = pubkeyPositionInScript;
      function pubkeyInScript(pubkey, script2) {
        return pubkeyPositionInScript(pubkey, script2) !== -1;
      }
      exports.pubkeyInScript = pubkeyInScript;
      function checkInputForSig(input, action) {
        return extractPartialSigs(input).some(
          (pSig) => signatureBlocksAction(pSig, bscript.signature.decode, action)
        );
      }
      exports.checkInputForSig = checkInputForSig;
      function signatureBlocksAction(signature, signatureDecodeFn, action) {
        let { hashType } = signatureDecodeFn(signature), whitelist = [];
        switch (hashType & transaction_1.Transaction.SIGHASH_ANYONECANPAY && whitelist.push("addInput"), hashType & 31) {
          case transaction_1.Transaction.SIGHASH_ALL:
            break;
          case transaction_1.Transaction.SIGHASH_SINGLE:
          case transaction_1.Transaction.SIGHASH_NONE:
            whitelist.push("addOutput"), whitelist.push("setInputSequence");
            break;
        }
        return whitelist.indexOf(action) === -1;
      }
      exports.signatureBlocksAction = signatureBlocksAction;
      function extractPartialSigs(input) {
        let pSigs = [];
        if ((input.partialSig || []).length === 0) {
          if (!input.finalScriptSig && !input.finalScriptWitness) return [];
          pSigs = getPsigsFromInputFinalScripts(input);
        } else
          pSigs = input.partialSig;
        return pSigs.map((p) => p.signature);
      }
      function getPsigsFromInputFinalScripts(input) {
        let scriptItems = input.finalScriptSig ? bscript.decompile(input.finalScriptSig) || [] : [], witnessItems = input.finalScriptWitness ? bscript.decompile(input.finalScriptWitness) || [] : [];
        return scriptItems.concat(witnessItems).filter((item) => import_buffer.Buffer.isBuffer(item) && bscript.isCanonicalScriptSignature(item)).map((sig) => ({ signature: sig }));
      }
    }
  });

  // node_modules/bitcoinjs-lib/src/psbt/bip371.js
  var require_bip371 = __commonJS({
    "node_modules/bitcoinjs-lib/src/psbt/bip371.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      exports.checkTaprootInputForSigs = exports.tapTreeFromList = exports.tapTreeToList = exports.tweakInternalPubKey = exports.checkTaprootOutputFields = exports.checkTaprootInputFields = exports.isTaprootOutput = exports.isTaprootInput = exports.serializeTaprootSignature = exports.tapScriptFinalizer = exports.toXOnly = void 0;
      var types_1 = require_types(), transaction_1 = require_transaction(), psbtutils_1 = require_psbtutils(), bip341_1 = require_bip341(), payments_1 = require_payments(), psbtutils_2 = require_psbtutils(), toXOnly2 = (pubKey) => pubKey.length === 32 ? pubKey : pubKey.slice(1, 33);
      exports.toXOnly = toXOnly2;
      function tapScriptFinalizer(inputIndex, input, tapLeafHashToFinalize) {
        let tapLeaf = findTapLeafToFinalize(
          input,
          inputIndex,
          tapLeafHashToFinalize
        );
        try {
          let witness = sortSignatures(input, tapLeaf).concat(tapLeaf.script).concat(tapLeaf.controlBlock);
          return {
            finalScriptWitness: (0, psbtutils_1.witnessStackToScriptWitness)(witness)
          };
        } catch (err) {
          throw new Error(`Can not finalize taproot input #${inputIndex}: ${err}`);
        }
      }
      exports.tapScriptFinalizer = tapScriptFinalizer;
      function serializeTaprootSignature(sig, sighashType) {
        let sighashTypeByte = sighashType ? import_buffer.Buffer.from([sighashType]) : import_buffer.Buffer.from([]);
        return import_buffer.Buffer.concat([sig, sighashTypeByte]);
      }
      exports.serializeTaprootSignature = serializeTaprootSignature;
      function isTaprootInput(input) {
        return input && !!(input.tapInternalKey || input.tapMerkleRoot || input.tapLeafScript && input.tapLeafScript.length || input.tapBip32Derivation && input.tapBip32Derivation.length || input.witnessUtxo && (0, psbtutils_1.isP2TR)(input.witnessUtxo.script));
      }
      exports.isTaprootInput = isTaprootInput;
      function isTaprootOutput(output, script2) {
        return output && !!(output.tapInternalKey || output.tapTree || output.tapBip32Derivation && output.tapBip32Derivation.length || script2 && (0, psbtutils_1.isP2TR)(script2));
      }
      exports.isTaprootOutput = isTaprootOutput;
      function checkTaprootInputFields(inputData, newInputData, action) {
        checkMixedTaprootAndNonTaprootInputFields(inputData, newInputData, action), checkIfTapLeafInTree(inputData, newInputData, action);
      }
      exports.checkTaprootInputFields = checkTaprootInputFields;
      function checkTaprootOutputFields(outputData, newOutputData, action) {
        checkMixedTaprootAndNonTaprootOutputFields(outputData, newOutputData, action), checkTaprootScriptPubkey(outputData, newOutputData);
      }
      exports.checkTaprootOutputFields = checkTaprootOutputFields;
      function checkTaprootScriptPubkey(outputData, newOutputData) {
        if (!newOutputData.tapTree && !newOutputData.tapInternalKey) return;
        let tapInternalKey = newOutputData.tapInternalKey || outputData.tapInternalKey, tapTree = newOutputData.tapTree || outputData.tapTree;
        if (tapInternalKey) {
          let { script: scriptPubkey } = outputData, script2 = getTaprootScripPubkey(tapInternalKey, tapTree);
          if (scriptPubkey && !scriptPubkey.equals(script2))
            throw new Error("Error adding output. Script or address missmatch.");
        }
      }
      function getTaprootScripPubkey(tapInternalKey, tapTree) {
        let scriptTree = tapTree && tapTreeFromList(tapTree.leaves), { output } = (0, payments_1.p2tr)({
          internalPubkey: tapInternalKey,
          scriptTree
        });
        return output;
      }
      function tweakInternalPubKey(inputIndex, input) {
        let tapInternalKey = input.tapInternalKey, outputKey = tapInternalKey && (0, bip341_1.tweakKey)(tapInternalKey, input.tapMerkleRoot);
        if (!outputKey)
          throw new Error(
            `Cannot tweak tap internal key for input #${inputIndex}. Public key: ${tapInternalKey && tapInternalKey.toString("hex")}`
          );
        return outputKey.x;
      }
      exports.tweakInternalPubKey = tweakInternalPubKey;
      function tapTreeToList(tree) {
        if (!(0, types_1.isTaptree)(tree))
          throw new Error(
            "Cannot convert taptree to tapleaf list. Expecting a tapree structure."
          );
        return _tapTreeToList(tree);
      }
      exports.tapTreeToList = tapTreeToList;
      function tapTreeFromList(leaves = []) {
        return leaves.length === 1 && leaves[0].depth === 0 ? {
          output: leaves[0].script,
          version: leaves[0].leafVersion
        } : instertLeavesInTree(leaves);
      }
      exports.tapTreeFromList = tapTreeFromList;
      function checkTaprootInputForSigs(input, action) {
        return extractTaprootSigs(input).some(
          (sig) => (0, psbtutils_2.signatureBlocksAction)(sig, decodeSchnorrSignature, action)
        );
      }
      exports.checkTaprootInputForSigs = checkTaprootInputForSigs;
      function decodeSchnorrSignature(signature) {
        return {
          signature: signature.slice(0, 64),
          hashType: signature.slice(64)[0] || transaction_1.Transaction.SIGHASH_DEFAULT
        };
      }
      function extractTaprootSigs(input) {
        let sigs = [];
        if (input.tapKeySig && sigs.push(input.tapKeySig), input.tapScriptSig && sigs.push(...input.tapScriptSig.map((s) => s.signature)), !sigs.length) {
          let finalTapKeySig = getTapKeySigFromWithness(input.finalScriptWitness);
          finalTapKeySig && sigs.push(finalTapKeySig);
        }
        return sigs;
      }
      function getTapKeySigFromWithness(finalScriptWitness) {
        if (!finalScriptWitness) return;
        let witness = finalScriptWitness.slice(2);
        if (witness.length === 64 || witness.length === 65) return witness;
      }
      function _tapTreeToList(tree, leaves = [], depth = 0) {
        if (depth > bip341_1.MAX_TAPTREE_DEPTH)
          throw new Error("Max taptree depth exceeded.");
        return tree ? (0, types_1.isTapleaf)(tree) ? (leaves.push({
          depth,
          leafVersion: tree.version || bip341_1.LEAF_VERSION_TAPSCRIPT,
          script: tree.output
        }), leaves) : (tree[0] && _tapTreeToList(tree[0], leaves, depth + 1), tree[1] && _tapTreeToList(tree[1], leaves, depth + 1), leaves) : [];
      }
      function instertLeavesInTree(leaves) {
        let tree;
        for (let leaf of leaves)
          if (tree = instertLeafInTree(leaf, tree), !tree) throw new Error("No room left to insert tapleaf in tree");
        return tree;
      }
      function instertLeafInTree(leaf, tree, depth = 0) {
        if (depth > bip341_1.MAX_TAPTREE_DEPTH)
          throw new Error("Max taptree depth exceeded.");
        if (leaf.depth === depth)
          return tree ? void 0 : {
            output: leaf.script,
            version: leaf.leafVersion
          };
        if ((0, types_1.isTapleaf)(tree)) return;
        let leftSide = instertLeafInTree(leaf, tree && tree[0], depth + 1);
        if (leftSide) return [leftSide, tree && tree[1]];
        let rightSide = instertLeafInTree(leaf, tree && tree[1], depth + 1);
        if (rightSide) return [tree && tree[0], rightSide];
      }
      function checkMixedTaprootAndNonTaprootInputFields(inputData, newInputData, action) {
        let isBadTaprootUpdate = isTaprootInput(inputData) && hasNonTaprootFields(newInputData), isBadNonTaprootUpdate = hasNonTaprootFields(inputData) && isTaprootInput(newInputData), hasMixedFields = inputData === newInputData && isTaprootInput(newInputData) && hasNonTaprootFields(newInputData);
        if (isBadTaprootUpdate || isBadNonTaprootUpdate || hasMixedFields)
          throw new Error(
            `Invalid arguments for Psbt.${action}. Cannot use both taproot and non-taproot fields.`
          );
      }
      function checkMixedTaprootAndNonTaprootOutputFields(inputData, newInputData, action) {
        let isBadTaprootUpdate = isTaprootOutput(inputData) && hasNonTaprootFields(newInputData), isBadNonTaprootUpdate = hasNonTaprootFields(inputData) && isTaprootOutput(newInputData), hasMixedFields = inputData === newInputData && isTaprootOutput(newInputData) && hasNonTaprootFields(newInputData);
        if (isBadTaprootUpdate || isBadNonTaprootUpdate || hasMixedFields)
          throw new Error(
            `Invalid arguments for Psbt.${action}. Cannot use both taproot and non-taproot fields.`
          );
      }
      function checkIfTapLeafInTree(inputData, newInputData, action) {
        if (newInputData.tapMerkleRoot) {
          let newLeafsInTree = (newInputData.tapLeafScript || []).every(
            (l) => isTapLeafInTree(l, newInputData.tapMerkleRoot)
          ), oldLeafsInTree = (inputData.tapLeafScript || []).every(
            (l) => isTapLeafInTree(l, newInputData.tapMerkleRoot)
          );
          if (!newLeafsInTree || !oldLeafsInTree)
            throw new Error(
              `Invalid arguments for Psbt.${action}. Tapleaf not part of taptree.`
            );
        } else if (inputData.tapMerkleRoot && !(newInputData.tapLeafScript || []).every(
          (l) => isTapLeafInTree(l, inputData.tapMerkleRoot)
        ))
          throw new Error(
            `Invalid arguments for Psbt.${action}. Tapleaf not part of taptree.`
          );
      }
      function isTapLeafInTree(tapLeaf, merkleRoot) {
        if (!merkleRoot) return !0;
        let leafHash = (0, bip341_1.tapleafHash)({
          output: tapLeaf.script,
          version: tapLeaf.leafVersion
        });
        return (0, bip341_1.rootHashFromPath)(
          tapLeaf.controlBlock,
          leafHash
        ).equals(merkleRoot);
      }
      function sortSignatures(input, tapLeaf) {
        let leafHash = (0, bip341_1.tapleafHash)({
          output: tapLeaf.script,
          version: tapLeaf.leafVersion
        });
        return (input.tapScriptSig || []).filter((tss) => tss.leafHash.equals(leafHash)).map((tss) => addPubkeyPositionInScript(tapLeaf.script, tss)).sort((t1, t2) => t2.positionInScript - t1.positionInScript).map((t) => t.signature);
      }
      function addPubkeyPositionInScript(script2, tss) {
        return Object.assign(
          {
            positionInScript: (0, psbtutils_1.pubkeyPositionInScript)(
              tss.pubkey,
              script2
            )
          },
          tss
        );
      }
      function findTapLeafToFinalize(input, inputIndex, leafHashToFinalize) {
        if (!input.tapScriptSig || !input.tapScriptSig.length)
          throw new Error(
            `Can not finalize taproot input #${inputIndex}. No tapleaf script signature provided.`
          );
        let tapLeaf = (input.tapLeafScript || []).sort((a, b) => a.controlBlock.length - b.controlBlock.length).find(
          (leaf) => canFinalizeLeaf(leaf, input.tapScriptSig, leafHashToFinalize)
        );
        if (!tapLeaf)
          throw new Error(
            `Can not finalize taproot input #${inputIndex}. Signature for tapleaf script not found.`
          );
        return tapLeaf;
      }
      function canFinalizeLeaf(leaf, tapScriptSig, hash) {
        let leafHash = (0, bip341_1.tapleafHash)({
          output: leaf.script,
          version: leaf.leafVersion
        });
        return (!hash || hash.equals(leafHash)) && tapScriptSig.find((tss) => tss.leafHash.equals(leafHash)) !== void 0;
      }
      function hasNonTaprootFields(io) {
        return io && !!(io.redeemScript || io.witnessScript || io.bip32Derivation && io.bip32Derivation.length);
      }
    }
  });

  // node_modules/bitcoinjs-lib/src/psbt.js
  var require_psbt2 = __commonJS({
    "node_modules/bitcoinjs-lib/src/psbt.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      exports.Psbt = void 0;
      var bip174_1 = require_psbt(), varuint = require_varint(), utils_1 = require_utils2(), address_1 = require_address(), bufferutils_1 = require_bufferutils(), networks_1 = require_networks(), payments2 = require_payments(), bip341_1 = require_bip341(), bscript = require_script(), transaction_1 = require_transaction(), bip371_1 = require_bip371(), psbtutils_1 = require_psbtutils(), DEFAULT_OPTS = {
        /**
         * A bitcoinjs Network object. This is only used if you pass an `address`
         * parameter to addOutput. Otherwise it is not needed and can be left default.
         */
        network: networks_1.bitcoin,
        /**
         * When extractTransaction is called, the fee rate is checked.
         * THIS IS NOT TO BE RELIED ON.
         * It is only here as a last ditch effort to prevent sending a 500 BTC fee etc.
         */
        maximumFeeRate: 5e3
        // satoshi per byte
      }, Psbt2 = class _Psbt {
        static fromBase64(data, opts = {}) {
          let buffer = import_buffer.Buffer.from(data, "base64");
          return this.fromBuffer(buffer, opts);
        }
        static fromHex(data, opts = {}) {
          let buffer = import_buffer.Buffer.from(data, "hex");
          return this.fromBuffer(buffer, opts);
        }
        static fromBuffer(buffer, opts = {}) {
          let psbtBase = bip174_1.Psbt.fromBuffer(buffer, transactionFromBuffer), psbt = new _Psbt(opts, psbtBase);
          return checkTxForDupeIns(psbt.__CACHE.__TX, psbt.__CACHE), psbt;
        }
        constructor(opts = {}, data = new bip174_1.Psbt(new PsbtTransaction())) {
          this.data = data, this.opts = Object.assign({}, DEFAULT_OPTS, opts), this.__CACHE = {
            __NON_WITNESS_UTXO_TX_CACHE: [],
            __NON_WITNESS_UTXO_BUF_CACHE: [],
            __TX_IN_CACHE: {},
            __TX: this.data.globalMap.unsignedTx.tx,
            // Psbt's predecessor (TransactionBuilder - now removed) behavior
            // was to not confirm input values  before signing.
            // Even though we highly encourage people to get
            // the full parent transaction to verify values, the ability to
            // sign non-segwit inputs without the full transaction was often
            // requested. So the only way to activate is to use @ts-ignore.
            // We will disable exporting the Psbt when unsafe sign is active.
            // because it is not BIP174 compliant.
            __UNSAFE_SIGN_NONSEGWIT: !1
          }, this.data.inputs.length === 0 && this.setVersion(2);
          let dpew = (obj, attr, enumerable, writable) => Object.defineProperty(obj, attr, {
            enumerable,
            writable
          });
          dpew(this, "__CACHE", !1, !0), dpew(this, "opts", !1, !0);
        }
        get inputCount() {
          return this.data.inputs.length;
        }
        get version() {
          return this.__CACHE.__TX.version;
        }
        set version(version) {
          this.setVersion(version);
        }
        get locktime() {
          return this.__CACHE.__TX.locktime;
        }
        set locktime(locktime) {
          this.setLocktime(locktime);
        }
        get txInputs() {
          return this.__CACHE.__TX.ins.map((input) => ({
            hash: (0, bufferutils_1.cloneBuffer)(input.hash),
            index: input.index,
            sequence: input.sequence
          }));
        }
        get txOutputs() {
          return this.__CACHE.__TX.outs.map((output) => {
            let address2;
            try {
              address2 = (0, address_1.fromOutputScript)(
                output.script,
                this.opts.network
              );
            } catch {
            }
            return {
              script: (0, bufferutils_1.cloneBuffer)(output.script),
              value: output.value,
              address: address2
            };
          });
        }
        combine(...those) {
          return this.data.combine(...those.map((o) => o.data)), this;
        }
        clone() {
          let res = _Psbt.fromBuffer(this.data.toBuffer());
          return res.opts = JSON.parse(JSON.stringify(this.opts)), res;
        }
        setMaximumFeeRate(satoshiPerByte) {
          check32Bit(satoshiPerByte), this.opts.maximumFeeRate = satoshiPerByte;
        }
        setVersion(version) {
          check32Bit(version), checkInputsForPartialSig(this.data.inputs, "setVersion");
          let c = this.__CACHE;
          return c.__TX.version = version, c.__EXTRACTED_TX = void 0, this;
        }
        setLocktime(locktime) {
          check32Bit(locktime), checkInputsForPartialSig(this.data.inputs, "setLocktime");
          let c = this.__CACHE;
          return c.__TX.locktime = locktime, c.__EXTRACTED_TX = void 0, this;
        }
        setInputSequence(inputIndex, sequence) {
          check32Bit(sequence), checkInputsForPartialSig(this.data.inputs, "setInputSequence");
          let c = this.__CACHE;
          if (c.__TX.ins.length <= inputIndex)
            throw new Error("Input index too high");
          return c.__TX.ins[inputIndex].sequence = sequence, c.__EXTRACTED_TX = void 0, this;
        }
        addInputs(inputDatas) {
          return inputDatas.forEach((inputData) => this.addInput(inputData)), this;
        }
        addInput(inputData) {
          if (arguments.length > 1 || !inputData || inputData.hash === void 0 || inputData.index === void 0)
            throw new Error(
              "Invalid arguments for Psbt.addInput. Requires single object with at least [hash] and [index]"
            );
          (0, bip371_1.checkTaprootInputFields)(inputData, inputData, "addInput"), checkInputsForPartialSig(this.data.inputs, "addInput"), inputData.witnessScript && checkInvalidP2WSH(inputData.witnessScript);
          let c = this.__CACHE;
          this.data.addInput(inputData);
          let txIn = c.__TX.ins[c.__TX.ins.length - 1];
          checkTxInputCache(c, txIn);
          let inputIndex = this.data.inputs.length - 1, input = this.data.inputs[inputIndex];
          return input.nonWitnessUtxo && addNonWitnessTxCache(this.__CACHE, input, inputIndex), c.__FEE = void 0, c.__FEE_RATE = void 0, c.__EXTRACTED_TX = void 0, this;
        }
        addOutputs(outputDatas) {
          return outputDatas.forEach((outputData) => this.addOutput(outputData)), this;
        }
        addOutput(outputData) {
          if (arguments.length > 1 || !outputData || outputData.value === void 0 || outputData.address === void 0 && outputData.script === void 0)
            throw new Error(
              "Invalid arguments for Psbt.addOutput. Requires single object with at least [script or address] and [value]"
            );
          checkInputsForPartialSig(this.data.inputs, "addOutput");
          let { address: address2 } = outputData;
          if (typeof address2 == "string") {
            let { network: network2 } = this.opts, script2 = (0, address_1.toOutputScript)(address2, network2);
            outputData = Object.assign({}, outputData, { script: script2 });
          }
          (0, bip371_1.checkTaprootOutputFields)(outputData, outputData, "addOutput");
          let c = this.__CACHE;
          return this.data.addOutput(outputData), c.__FEE = void 0, c.__FEE_RATE = void 0, c.__EXTRACTED_TX = void 0, this;
        }
        extractTransaction(disableFeeCheck) {
          if (!this.data.inputs.every(isFinalized)) throw new Error("Not finalized");
          let c = this.__CACHE;
          if (disableFeeCheck || checkFees(this, c, this.opts), c.__EXTRACTED_TX) return c.__EXTRACTED_TX;
          let tx = c.__TX.clone();
          return inputFinalizeGetAmts(this.data.inputs, tx, c, !0), tx;
        }
        getFeeRate() {
          return getTxCacheValue(
            "__FEE_RATE",
            "fee rate",
            this.data.inputs,
            this.__CACHE
          );
        }
        getFee() {
          return getTxCacheValue("__FEE", "fee", this.data.inputs, this.__CACHE);
        }
        finalizeAllInputs() {
          return (0, utils_1.checkForInput)(this.data.inputs, 0), range(this.data.inputs.length).forEach((idx) => this.finalizeInput(idx)), this;
        }
        finalizeInput(inputIndex, finalScriptsFunc) {
          let input = (0, utils_1.checkForInput)(this.data.inputs, inputIndex);
          return (0, bip371_1.isTaprootInput)(input) ? this._finalizeTaprootInput(
            inputIndex,
            input,
            void 0,
            finalScriptsFunc
          ) : this._finalizeInput(inputIndex, input, finalScriptsFunc);
        }
        finalizeTaprootInput(inputIndex, tapLeafHashToFinalize, finalScriptsFunc = bip371_1.tapScriptFinalizer) {
          let input = (0, utils_1.checkForInput)(this.data.inputs, inputIndex);
          if ((0, bip371_1.isTaprootInput)(input))
            return this._finalizeTaprootInput(
              inputIndex,
              input,
              tapLeafHashToFinalize,
              finalScriptsFunc
            );
          throw new Error(`Cannot finalize input #${inputIndex}. Not Taproot.`);
        }
        _finalizeInput(inputIndex, input, finalScriptsFunc = getFinalScripts) {
          let { script: script2, isP2SH, isP2WSH, isSegwit } = getScriptFromInput(
            inputIndex,
            input,
            this.__CACHE
          );
          if (!script2) throw new Error(`No script found for input #${inputIndex}`);
          checkPartialSigSighashes(input);
          let { finalScriptSig, finalScriptWitness } = finalScriptsFunc(
            inputIndex,
            input,
            script2,
            isSegwit,
            isP2SH,
            isP2WSH
          );
          if (finalScriptSig && this.data.updateInput(inputIndex, { finalScriptSig }), finalScriptWitness && this.data.updateInput(inputIndex, { finalScriptWitness }), !finalScriptSig && !finalScriptWitness)
            throw new Error(`Unknown error finalizing input #${inputIndex}`);
          return this.data.clearFinalizedInput(inputIndex), this;
        }
        _finalizeTaprootInput(inputIndex, input, tapLeafHashToFinalize, finalScriptsFunc = bip371_1.tapScriptFinalizer) {
          if (!input.witnessUtxo)
            throw new Error(
              `Cannot finalize input #${inputIndex}. Missing withness utxo.`
            );
          if (input.tapKeySig) {
            let payment = payments2.p2tr({
              output: input.witnessUtxo.script,
              signature: input.tapKeySig
            }), finalScriptWitness = (0, psbtutils_1.witnessStackToScriptWitness)(
              payment.witness
            );
            this.data.updateInput(inputIndex, { finalScriptWitness });
          } else {
            let { finalScriptWitness } = finalScriptsFunc(
              inputIndex,
              input,
              tapLeafHashToFinalize
            );
            this.data.updateInput(inputIndex, { finalScriptWitness });
          }
          return this.data.clearFinalizedInput(inputIndex), this;
        }
        getInputType(inputIndex) {
          let input = (0, utils_1.checkForInput)(this.data.inputs, inputIndex), script2 = getScriptFromUtxo(inputIndex, input, this.__CACHE), result = getMeaningfulScript(
            script2,
            inputIndex,
            "input",
            input.redeemScript || redeemFromFinalScriptSig(input.finalScriptSig),
            input.witnessScript || redeemFromFinalWitnessScript(input.finalScriptWitness)
          ), type = result.type === "raw" ? "" : result.type + "-", mainType = classifyScript(result.meaningfulScript);
          return type + mainType;
        }
        inputHasPubkey(inputIndex, pubkey) {
          let input = (0, utils_1.checkForInput)(this.data.inputs, inputIndex);
          return pubkeyInInput(pubkey, input, inputIndex, this.__CACHE);
        }
        inputHasHDKey(inputIndex, root) {
          let input = (0, utils_1.checkForInput)(this.data.inputs, inputIndex), derivationIsMine = bip32DerivationIsMine(root);
          return !!input.bip32Derivation && input.bip32Derivation.some(derivationIsMine);
        }
        outputHasPubkey(outputIndex, pubkey) {
          let output = (0, utils_1.checkForOutput)(this.data.outputs, outputIndex);
          return pubkeyInOutput(pubkey, output, outputIndex, this.__CACHE);
        }
        outputHasHDKey(outputIndex, root) {
          let output = (0, utils_1.checkForOutput)(this.data.outputs, outputIndex), derivationIsMine = bip32DerivationIsMine(root);
          return !!output.bip32Derivation && output.bip32Derivation.some(derivationIsMine);
        }
        validateSignaturesOfAllInputs(validator) {
          return (0, utils_1.checkForInput)(this.data.inputs, 0), range(this.data.inputs.length).map(
            (idx) => this.validateSignaturesOfInput(idx, validator)
          ).reduce((final, res) => res === !0 && final, !0);
        }
        validateSignaturesOfInput(inputIndex, validator, pubkey) {
          let input = this.data.inputs[inputIndex];
          return (0, bip371_1.isTaprootInput)(input) ? this.validateSignaturesOfTaprootInput(
            inputIndex,
            validator,
            pubkey
          ) : this._validateSignaturesOfInput(inputIndex, validator, pubkey);
        }
        _validateSignaturesOfInput(inputIndex, validator, pubkey) {
          let input = this.data.inputs[inputIndex], partialSig = (input || {}).partialSig;
          if (!input || !partialSig || partialSig.length < 1)
            throw new Error("No signatures to validate");
          if (typeof validator != "function")
            throw new Error("Need validator function to validate signatures");
          let mySigs = pubkey ? partialSig.filter((sig) => sig.pubkey.equals(pubkey)) : partialSig;
          if (mySigs.length < 1) throw new Error("No signatures for this pubkey");
          let results = [], hashCache, scriptCache, sighashCache;
          for (let pSig of mySigs) {
            let sig = bscript.signature.decode(pSig.signature), { hash, script: script2 } = sighashCache !== sig.hashType ? getHashForSig(
              inputIndex,
              Object.assign({}, input, { sighashType: sig.hashType }),
              this.__CACHE,
              !0
            ) : { hash: hashCache, script: scriptCache };
            sighashCache = sig.hashType, hashCache = hash, scriptCache = script2, checkScriptForPubkey(pSig.pubkey, script2, "verify"), results.push(validator(pSig.pubkey, hash, sig.signature));
          }
          return results.every((res) => res === !0);
        }
        validateSignaturesOfTaprootInput(inputIndex, validator, pubkey) {
          let input = this.data.inputs[inputIndex], tapKeySig = (input || {}).tapKeySig, tapScriptSig = (input || {}).tapScriptSig;
          if (!input && !tapKeySig && !(tapScriptSig && !tapScriptSig.length))
            throw new Error("No signatures to validate");
          if (typeof validator != "function")
            throw new Error("Need validator function to validate signatures");
          pubkey = pubkey && (0, bip371_1.toXOnly)(pubkey);
          let allHashses = pubkey ? getTaprootHashesForSig(
            inputIndex,
            input,
            this.data.inputs,
            pubkey,
            this.__CACHE
          ) : getAllTaprootHashesForSig(
            inputIndex,
            input,
            this.data.inputs,
            this.__CACHE
          );
          if (!allHashses.length) throw new Error("No signatures for this pubkey");
          let tapKeyHash = allHashses.find((h) => !h.leafHash), validationResultCount = 0;
          if (tapKeySig && tapKeyHash) {
            if (!validator(
              tapKeyHash.pubkey,
              tapKeyHash.hash,
              trimTaprootSig(tapKeySig)
            )) return !1;
            validationResultCount++;
          }
          if (tapScriptSig)
            for (let tapSig of tapScriptSig) {
              let tapSigHash = allHashses.find((h) => tapSig.pubkey.equals(h.pubkey));
              if (tapSigHash) {
                if (!validator(
                  tapSig.pubkey,
                  tapSigHash.hash,
                  trimTaprootSig(tapSig.signature)
                )) return !1;
                validationResultCount++;
              }
            }
          return validationResultCount > 0;
        }
        signAllInputsHD(hdKeyPair, sighashTypes = [transaction_1.Transaction.SIGHASH_ALL]) {
          if (!hdKeyPair || !hdKeyPair.publicKey || !hdKeyPair.fingerprint)
            throw new Error("Need HDSigner to sign input");
          let results = [];
          for (let i of range(this.data.inputs.length))
            try {
              this.signInputHD(i, hdKeyPair, sighashTypes), results.push(!0);
            } catch {
              results.push(!1);
            }
          if (results.every((v) => v === !1))
            throw new Error("No inputs were signed");
          return this;
        }
        signAllInputsHDAsync(hdKeyPair, sighashTypes = [transaction_1.Transaction.SIGHASH_ALL]) {
          return new Promise((resolve, reject) => {
            if (!hdKeyPair || !hdKeyPair.publicKey || !hdKeyPair.fingerprint)
              return reject(new Error("Need HDSigner to sign input"));
            let results = [], promises = [];
            for (let i of range(this.data.inputs.length))
              promises.push(
                this.signInputHDAsync(i, hdKeyPair, sighashTypes).then(
                  () => {
                    results.push(!0);
                  },
                  () => {
                    results.push(!1);
                  }
                )
              );
            return Promise.all(promises).then(() => {
              if (results.every((v) => v === !1))
                return reject(new Error("No inputs were signed"));
              resolve();
            });
          });
        }
        signInputHD(inputIndex, hdKeyPair, sighashTypes = [transaction_1.Transaction.SIGHASH_ALL]) {
          if (!hdKeyPair || !hdKeyPair.publicKey || !hdKeyPair.fingerprint)
            throw new Error("Need HDSigner to sign input");
          return getSignersFromHD(inputIndex, this.data.inputs, hdKeyPair).forEach((signer) => this.signInput(inputIndex, signer, sighashTypes)), this;
        }
        signInputHDAsync(inputIndex, hdKeyPair, sighashTypes = [transaction_1.Transaction.SIGHASH_ALL]) {
          return new Promise((resolve, reject) => {
            if (!hdKeyPair || !hdKeyPair.publicKey || !hdKeyPair.fingerprint)
              return reject(new Error("Need HDSigner to sign input"));
            let promises = getSignersFromHD(inputIndex, this.data.inputs, hdKeyPair).map(
              (signer) => this.signInputAsync(inputIndex, signer, sighashTypes)
            );
            return Promise.all(promises).then(() => {
              resolve();
            }).catch(reject);
          });
        }
        signAllInputs(keyPair, sighashTypes) {
          if (!keyPair || !keyPair.publicKey)
            throw new Error("Need Signer to sign input");
          let results = [];
          for (let i of range(this.data.inputs.length))
            try {
              this.signInput(i, keyPair, sighashTypes), results.push(!0);
            } catch {
              results.push(!1);
            }
          if (results.every((v) => v === !1))
            throw new Error("No inputs were signed");
          return this;
        }
        signAllInputsAsync(keyPair, sighashTypes) {
          return new Promise((resolve, reject) => {
            if (!keyPair || !keyPair.publicKey)
              return reject(new Error("Need Signer to sign input"));
            let results = [], promises = [];
            for (let [i] of this.data.inputs.entries())
              promises.push(
                this.signInputAsync(i, keyPair, sighashTypes).then(
                  () => {
                    results.push(!0);
                  },
                  () => {
                    results.push(!1);
                  }
                )
              );
            return Promise.all(promises).then(() => {
              if (results.every((v) => v === !1))
                return reject(new Error("No inputs were signed"));
              resolve();
            });
          });
        }
        signInput(inputIndex, keyPair, sighashTypes) {
          if (!keyPair || !keyPair.publicKey)
            throw new Error("Need Signer to sign input");
          let input = (0, utils_1.checkForInput)(this.data.inputs, inputIndex);
          return (0, bip371_1.isTaprootInput)(input) ? this._signTaprootInput(
            inputIndex,
            input,
            keyPair,
            void 0,
            sighashTypes
          ) : this._signInput(inputIndex, keyPair, sighashTypes);
        }
        signTaprootInput(inputIndex, keyPair, tapLeafHashToSign, sighashTypes) {
          if (!keyPair || !keyPair.publicKey)
            throw new Error("Need Signer to sign input");
          let input = (0, utils_1.checkForInput)(this.data.inputs, inputIndex);
          if ((0, bip371_1.isTaprootInput)(input))
            return this._signTaprootInput(
              inputIndex,
              input,
              keyPair,
              tapLeafHashToSign,
              sighashTypes
            );
          throw new Error(`Input #${inputIndex} is not of type Taproot.`);
        }
        _signInput(inputIndex, keyPair, sighashTypes = [transaction_1.Transaction.SIGHASH_ALL]) {
          let { hash, sighashType } = getHashAndSighashType(
            this.data.inputs,
            inputIndex,
            keyPair.publicKey,
            this.__CACHE,
            sighashTypes
          ), partialSig = [
            {
              pubkey: keyPair.publicKey,
              signature: bscript.signature.encode(keyPair.sign(hash), sighashType)
            }
          ];
          return this.data.updateInput(inputIndex, { partialSig }), this;
        }
        _signTaprootInput(inputIndex, input, keyPair, tapLeafHashToSign, allowedSighashTypes = [transaction_1.Transaction.SIGHASH_DEFAULT]) {
          let hashesForSig = this.checkTaprootHashesForSig(
            inputIndex,
            input,
            keyPair,
            tapLeafHashToSign,
            allowedSighashTypes
          ), tapKeySig = hashesForSig.filter((h) => !h.leafHash).map(
            (h) => (0, bip371_1.serializeTaprootSignature)(
              keyPair.signSchnorr(h.hash),
              input.sighashType
            )
          )[0], tapScriptSig = hashesForSig.filter((h) => !!h.leafHash).map((h) => ({
            pubkey: (0, bip371_1.toXOnly)(keyPair.publicKey),
            signature: (0, bip371_1.serializeTaprootSignature)(
              keyPair.signSchnorr(h.hash),
              input.sighashType
            ),
            leafHash: h.leafHash
          }));
          return tapKeySig && this.data.updateInput(inputIndex, { tapKeySig }), tapScriptSig.length && this.data.updateInput(inputIndex, { tapScriptSig }), this;
        }
        signInputAsync(inputIndex, keyPair, sighashTypes) {
          return Promise.resolve().then(() => {
            if (!keyPair || !keyPair.publicKey)
              throw new Error("Need Signer to sign input");
            let input = (0, utils_1.checkForInput)(this.data.inputs, inputIndex);
            return (0, bip371_1.isTaprootInput)(input) ? this._signTaprootInputAsync(
              inputIndex,
              input,
              keyPair,
              void 0,
              sighashTypes
            ) : this._signInputAsync(inputIndex, keyPair, sighashTypes);
          });
        }
        signTaprootInputAsync(inputIndex, keyPair, tapLeafHash, sighashTypes) {
          return Promise.resolve().then(() => {
            if (!keyPair || !keyPair.publicKey)
              throw new Error("Need Signer to sign input");
            let input = (0, utils_1.checkForInput)(this.data.inputs, inputIndex);
            if ((0, bip371_1.isTaprootInput)(input))
              return this._signTaprootInputAsync(
                inputIndex,
                input,
                keyPair,
                tapLeafHash,
                sighashTypes
              );
            throw new Error(`Input #${inputIndex} is not of type Taproot.`);
          });
        }
        _signInputAsync(inputIndex, keyPair, sighashTypes = [transaction_1.Transaction.SIGHASH_ALL]) {
          let { hash, sighashType } = getHashAndSighashType(
            this.data.inputs,
            inputIndex,
            keyPair.publicKey,
            this.__CACHE,
            sighashTypes
          );
          return Promise.resolve(keyPair.sign(hash)).then((signature) => {
            let partialSig = [
              {
                pubkey: keyPair.publicKey,
                signature: bscript.signature.encode(signature, sighashType)
              }
            ];
            this.data.updateInput(inputIndex, { partialSig });
          });
        }
        async _signTaprootInputAsync(inputIndex, input, keyPair, tapLeafHash, sighashTypes = [transaction_1.Transaction.SIGHASH_DEFAULT]) {
          let hashesForSig = this.checkTaprootHashesForSig(
            inputIndex,
            input,
            keyPair,
            tapLeafHash,
            sighashTypes
          ), signaturePromises = [], tapKeyHash = hashesForSig.filter((h) => !h.leafHash)[0];
          if (tapKeyHash) {
            let tapKeySigPromise = Promise.resolve(
              keyPair.signSchnorr(tapKeyHash.hash)
            ).then((sig) => ({
              tapKeySig: (0, bip371_1.serializeTaprootSignature)(
                sig,
                input.sighashType
              )
            }));
            signaturePromises.push(tapKeySigPromise);
          }
          let tapScriptHashes = hashesForSig.filter((h) => !!h.leafHash);
          if (tapScriptHashes.length) {
            let tapScriptSigPromises = tapScriptHashes.map((tsh) => Promise.resolve(keyPair.signSchnorr(tsh.hash)).then(
              (signature) => ({ tapScriptSig: [
                {
                  pubkey: (0, bip371_1.toXOnly)(keyPair.publicKey),
                  signature: (0, bip371_1.serializeTaprootSignature)(
                    signature,
                    input.sighashType
                  ),
                  leafHash: tsh.leafHash
                }
              ] })
            ));
            signaturePromises.push(...tapScriptSigPromises);
          }
          return Promise.all(signaturePromises).then((results) => {
            results.forEach((v) => this.data.updateInput(inputIndex, v));
          });
        }
        checkTaprootHashesForSig(inputIndex, input, keyPair, tapLeafHashToSign, allowedSighashTypes) {
          if (typeof keyPair.signSchnorr != "function")
            throw new Error(
              `Need Schnorr Signer to sign taproot input #${inputIndex}.`
            );
          let hashesForSig = getTaprootHashesForSig(
            inputIndex,
            input,
            this.data.inputs,
            keyPair.publicKey,
            this.__CACHE,
            tapLeafHashToSign,
            allowedSighashTypes
          );
          if (!hashesForSig || !hashesForSig.length)
            throw new Error(
              `Can not sign for input #${inputIndex} with the key ${keyPair.publicKey.toString(
                "hex"
              )}`
            );
          return hashesForSig;
        }
        toBuffer() {
          return checkCache(this.__CACHE), this.data.toBuffer();
        }
        toHex() {
          return checkCache(this.__CACHE), this.data.toHex();
        }
        toBase64() {
          return checkCache(this.__CACHE), this.data.toBase64();
        }
        updateGlobal(updateData) {
          return this.data.updateGlobal(updateData), this;
        }
        updateInput(inputIndex, updateData) {
          return updateData.witnessScript && checkInvalidP2WSH(updateData.witnessScript), (0, bip371_1.checkTaprootInputFields)(
            this.data.inputs[inputIndex],
            updateData,
            "updateInput"
          ), this.data.updateInput(inputIndex, updateData), updateData.nonWitnessUtxo && addNonWitnessTxCache(
            this.__CACHE,
            this.data.inputs[inputIndex],
            inputIndex
          ), this;
        }
        updateOutput(outputIndex, updateData) {
          let outputData = this.data.outputs[outputIndex];
          return (0, bip371_1.checkTaprootOutputFields)(
            outputData,
            updateData,
            "updateOutput"
          ), this.data.updateOutput(outputIndex, updateData), this;
        }
        addUnknownKeyValToGlobal(keyVal) {
          return this.data.addUnknownKeyValToGlobal(keyVal), this;
        }
        addUnknownKeyValToInput(inputIndex, keyVal) {
          return this.data.addUnknownKeyValToInput(inputIndex, keyVal), this;
        }
        addUnknownKeyValToOutput(outputIndex, keyVal) {
          return this.data.addUnknownKeyValToOutput(outputIndex, keyVal), this;
        }
        clearFinalizedInput(inputIndex) {
          return this.data.clearFinalizedInput(inputIndex), this;
        }
      };
      exports.Psbt = Psbt2;
      var transactionFromBuffer = (buffer) => new PsbtTransaction(buffer), PsbtTransaction = class {
        constructor(buffer = import_buffer.Buffer.from([2, 0, 0, 0, 0, 0, 0, 0, 0, 0])) {
          this.tx = transaction_1.Transaction.fromBuffer(buffer), checkTxEmpty(this.tx), Object.defineProperty(this, "tx", {
            enumerable: !1,
            writable: !0
          });
        }
        getInputOutputCounts() {
          return {
            inputCount: this.tx.ins.length,
            outputCount: this.tx.outs.length
          };
        }
        addInput(input) {
          if (input.hash === void 0 || input.index === void 0 || !import_buffer.Buffer.isBuffer(input.hash) && typeof input.hash != "string" || typeof input.index != "number")
            throw new Error("Error adding input.");
          let hash = typeof input.hash == "string" ? (0, bufferutils_1.reverseBuffer)(import_buffer.Buffer.from(input.hash, "hex")) : input.hash;
          this.tx.addInput(hash, input.index, input.sequence);
        }
        addOutput(output) {
          if (output.script === void 0 || output.value === void 0 || !import_buffer.Buffer.isBuffer(output.script) || typeof output.value != "number")
            throw new Error("Error adding output.");
          this.tx.addOutput(output.script, output.value);
        }
        toBuffer() {
          return this.tx.toBuffer();
        }
      };
      function canFinalize(input, script2, scriptType2) {
        switch (scriptType2) {
          case "pubkey":
          case "pubkeyhash":
          case "witnesspubkeyhash":
            return hasSigs(1, input.partialSig);
          case "multisig":
            let p2ms = payments2.p2ms({ output: script2 });
            return hasSigs(p2ms.m, input.partialSig, p2ms.pubkeys);
          default:
            return !1;
        }
      }
      function checkCache(cache) {
        if (cache.__UNSAFE_SIGN_NONSEGWIT !== !1)
          throw new Error("Not BIP174 compliant, can not export");
      }
      function hasSigs(neededSigs, partialSig, pubkeys) {
        if (!partialSig) return !1;
        let sigs;
        if (pubkeys ? sigs = pubkeys.map((pkey) => {
          let pubkey = compressPubkey(pkey);
          return partialSig.find((pSig) => pSig.pubkey.equals(pubkey));
        }).filter((v) => !!v) : sigs = partialSig, sigs.length > neededSigs) throw new Error("Too many signatures");
        return sigs.length === neededSigs;
      }
      function isFinalized(input) {
        return !!input.finalScriptSig || !!input.finalScriptWitness;
      }
      function bip32DerivationIsMine(root) {
        return (d) => !(!d.masterFingerprint.equals(root.fingerprint) || !root.derivePath(d.path).publicKey.equals(d.pubkey));
      }
      function check32Bit(num) {
        if (typeof num != "number" || num !== Math.floor(num) || num > 4294967295 || num < 0)
          throw new Error("Invalid 32 bit integer");
      }
      function checkFees(psbt, cache, opts) {
        let feeRate = cache.__FEE_RATE || psbt.getFeeRate(), vsize = cache.__EXTRACTED_TX.virtualSize(), satoshis = feeRate * vsize;
        if (feeRate >= opts.maximumFeeRate)
          throw new Error(
            `Warning: You are paying around ${(satoshis / 1e8).toFixed(8)} in fees, which is ${feeRate} satoshi per byte for a transaction with a VSize of ${vsize} bytes (segwit counted as 0.25 byte per byte). Use setMaximumFeeRate method to raise your threshold, or pass true to the first arg of extractTransaction.`
          );
      }
      function checkInputsForPartialSig(inputs, action) {
        inputs.forEach((input) => {
          if ((0, bip371_1.isTaprootInput)(input) ? (0, bip371_1.checkTaprootInputForSigs)(input, action) : (0, psbtutils_1.checkInputForSig)(input, action))
            throw new Error("Can not modify transaction, signatures exist.");
        });
      }
      function checkPartialSigSighashes(input) {
        if (!input.sighashType || !input.partialSig) return;
        let { partialSig, sighashType } = input;
        partialSig.forEach((pSig) => {
          let { hashType } = bscript.signature.decode(pSig.signature);
          if (sighashType !== hashType)
            throw new Error("Signature sighash does not match input sighash type");
        });
      }
      function checkScriptForPubkey(pubkey, script2, action) {
        if (!(0, psbtutils_1.pubkeyInScript)(pubkey, script2))
          throw new Error(
            `Can not ${action} for this input with the key ${pubkey.toString("hex")}`
          );
      }
      function checkTxEmpty(tx) {
        if (!tx.ins.every(
          (input) => input.script && input.script.length === 0 && input.witness && input.witness.length === 0
        ))
          throw new Error("Format Error: Transaction ScriptSigs are not empty");
      }
      function checkTxForDupeIns(tx, cache) {
        tx.ins.forEach((input) => {
          checkTxInputCache(cache, input);
        });
      }
      function checkTxInputCache(cache, input) {
        let key = (0, bufferutils_1.reverseBuffer)(import_buffer.Buffer.from(input.hash)).toString("hex") + ":" + input.index;
        if (cache.__TX_IN_CACHE[key]) throw new Error("Duplicate input detected.");
        cache.__TX_IN_CACHE[key] = 1;
      }
      function scriptCheckerFactory(payment, paymentScriptName) {
        return (inputIndex, scriptPubKey, redeemScript, ioType) => {
          let redeemScriptOutput = payment({
            redeem: { output: redeemScript }
          }).output;
          if (!scriptPubKey.equals(redeemScriptOutput))
            throw new Error(
              `${paymentScriptName} for ${ioType} #${inputIndex} doesn't match the scriptPubKey in the prevout`
            );
        };
      }
      var checkRedeemScript = scriptCheckerFactory(payments2.p2sh, "Redeem script"), checkWitnessScript = scriptCheckerFactory(
        payments2.p2wsh,
        "Witness script"
      );
      function getTxCacheValue(key, name, inputs, c) {
        if (!inputs.every(isFinalized))
          throw new Error(`PSBT must be finalized to calculate ${name}`);
        if (key === "__FEE_RATE" && c.__FEE_RATE) return c.__FEE_RATE;
        if (key === "__FEE" && c.__FEE) return c.__FEE;
        let tx, mustFinalize = !0;
        if (c.__EXTRACTED_TX ? (tx = c.__EXTRACTED_TX, mustFinalize = !1) : tx = c.__TX.clone(), inputFinalizeGetAmts(inputs, tx, c, mustFinalize), key === "__FEE_RATE") return c.__FEE_RATE;
        if (key === "__FEE") return c.__FEE;
      }
      function getFinalScripts(inputIndex, input, script2, isSegwit, isP2SH, isP2WSH) {
        let scriptType2 = classifyScript(script2);
        if (!canFinalize(input, script2, scriptType2))
          throw new Error(`Can not finalize input #${inputIndex}`);
        return prepareFinalScripts(
          script2,
          scriptType2,
          input.partialSig,
          isSegwit,
          isP2SH,
          isP2WSH
        );
      }
      function prepareFinalScripts(script2, scriptType2, partialSig, isSegwit, isP2SH, isP2WSH) {
        let finalScriptSig, finalScriptWitness, payment = getPayment(script2, scriptType2, partialSig), p2wsh = isP2WSH ? payments2.p2wsh({ redeem: payment }) : null, p2sh = isP2SH ? payments2.p2sh({ redeem: p2wsh || payment }) : null;
        return isSegwit ? (p2wsh ? finalScriptWitness = (0, psbtutils_1.witnessStackToScriptWitness)(
          p2wsh.witness
        ) : finalScriptWitness = (0, psbtutils_1.witnessStackToScriptWitness)(
          payment.witness
        ), p2sh && (finalScriptSig = p2sh.input)) : p2sh ? finalScriptSig = p2sh.input : finalScriptSig = payment.input, {
          finalScriptSig,
          finalScriptWitness
        };
      }
      function getHashAndSighashType(inputs, inputIndex, pubkey, cache, sighashTypes) {
        let input = (0, utils_1.checkForInput)(inputs, inputIndex), { hash, sighashType, script: script2 } = getHashForSig(
          inputIndex,
          input,
          cache,
          !1,
          sighashTypes
        );
        return checkScriptForPubkey(pubkey, script2, "sign"), {
          hash,
          sighashType
        };
      }
      function getHashForSig(inputIndex, input, cache, forValidate, sighashTypes) {
        let unsignedTx = cache.__TX, sighashType = input.sighashType || transaction_1.Transaction.SIGHASH_ALL;
        checkSighashTypeAllowed(sighashType, sighashTypes);
        let hash, prevout;
        if (input.nonWitnessUtxo) {
          let nonWitnessUtxoTx = nonWitnessUtxoTxFromCache(
            cache,
            input,
            inputIndex
          ), prevoutHash = unsignedTx.ins[inputIndex].hash, utxoHash = nonWitnessUtxoTx.getHash();
          if (!prevoutHash.equals(utxoHash))
            throw new Error(
              `Non-witness UTXO hash for input #${inputIndex} doesn't match the hash specified in the prevout`
            );
          let prevoutIndex = unsignedTx.ins[inputIndex].index;
          prevout = nonWitnessUtxoTx.outs[prevoutIndex];
        } else if (input.witnessUtxo)
          prevout = input.witnessUtxo;
        else
          throw new Error("Need a Utxo input item for signing");
        let { meaningfulScript, type } = getMeaningfulScript(
          prevout.script,
          inputIndex,
          "input",
          input.redeemScript,
          input.witnessScript
        );
        if (["p2sh-p2wsh", "p2wsh"].indexOf(type) >= 0)
          hash = unsignedTx.hashForWitnessV0(
            inputIndex,
            meaningfulScript,
            prevout.value,
            sighashType
          );
        else if ((0, psbtutils_1.isP2WPKH)(meaningfulScript)) {
          let signingScript = payments2.p2pkh({
            hash: meaningfulScript.slice(2)
          }).output;
          hash = unsignedTx.hashForWitnessV0(
            inputIndex,
            signingScript,
            prevout.value,
            sighashType
          );
        } else {
          if (input.nonWitnessUtxo === void 0 && cache.__UNSAFE_SIGN_NONSEGWIT === !1)
            throw new Error(
              `Input #${inputIndex} has witnessUtxo but non-segwit script: ${meaningfulScript.toString("hex")}`
            );
          !forValidate && cache.__UNSAFE_SIGN_NONSEGWIT !== !1 && console.warn(
            `Warning: Signing non-segwit inputs without the full parent transaction means there is a chance that a miner could feed you incorrect information to trick you into paying large fees. This behavior is the same as Psbt's predecessor (TransactionBuilder - now removed) when signing non-segwit scripts. You are not able to export this Psbt with toBuffer|toBase64|toHex since it is not BIP174 compliant.
*********************
PROCEED WITH CAUTION!
*********************`
          ), hash = unsignedTx.hashForSignature(
            inputIndex,
            meaningfulScript,
            sighashType
          );
        }
        return {
          script: meaningfulScript,
          sighashType,
          hash
        };
      }
      function getAllTaprootHashesForSig(inputIndex, input, inputs, cache) {
        let allPublicKeys = [];
        if (input.tapInternalKey) {
          let key = getPrevoutTaprootKey(inputIndex, input, cache);
          key && allPublicKeys.push(key);
        }
        if (input.tapScriptSig) {
          let tapScriptPubkeys = input.tapScriptSig.map((tss) => tss.pubkey);
          allPublicKeys.push(...tapScriptPubkeys);
        }
        return allPublicKeys.map(
          (pubicKey) => getTaprootHashesForSig(inputIndex, input, inputs, pubicKey, cache)
        ).flat();
      }
      function getPrevoutTaprootKey(inputIndex, input, cache) {
        let { script: script2 } = getScriptAndAmountFromUtxo(inputIndex, input, cache);
        return (0, psbtutils_1.isP2TR)(script2) ? script2.subarray(2, 34) : null;
      }
      function trimTaprootSig(signature) {
        return signature.length === 64 ? signature : signature.subarray(0, 64);
      }
      function getTaprootHashesForSig(inputIndex, input, inputs, pubkey, cache, tapLeafHashToSign, allowedSighashTypes) {
        let unsignedTx = cache.__TX, sighashType = input.sighashType || transaction_1.Transaction.SIGHASH_DEFAULT;
        checkSighashTypeAllowed(sighashType, allowedSighashTypes);
        let prevOuts = inputs.map(
          (i, index) => getScriptAndAmountFromUtxo(index, i, cache)
        ), signingScripts = prevOuts.map((o) => o.script), values = prevOuts.map((o) => o.value), hashes = [];
        if (input.tapInternalKey && !tapLeafHashToSign) {
          let outputKey = getPrevoutTaprootKey(inputIndex, input, cache) || import_buffer.Buffer.from([]);
          if ((0, bip371_1.toXOnly)(pubkey).equals(outputKey)) {
            let tapKeyHash = unsignedTx.hashForWitnessV1(
              inputIndex,
              signingScripts,
              values,
              sighashType
            );
            hashes.push({ pubkey, hash: tapKeyHash });
          }
        }
        let tapLeafHashes = (input.tapLeafScript || []).filter((tapLeaf) => (0, psbtutils_1.pubkeyInScript)(pubkey, tapLeaf.script)).map((tapLeaf) => {
          let hash = (0, bip341_1.tapleafHash)({
            output: tapLeaf.script,
            version: tapLeaf.leafVersion
          });
          return Object.assign({ hash }, tapLeaf);
        }).filter(
          (tapLeaf) => !tapLeafHashToSign || tapLeafHashToSign.equals(tapLeaf.hash)
        ).map((tapLeaf) => {
          let tapScriptHash = unsignedTx.hashForWitnessV1(
            inputIndex,
            signingScripts,
            values,
            sighashType,
            tapLeaf.hash
          );
          return {
            pubkey,
            hash: tapScriptHash,
            leafHash: tapLeaf.hash
          };
        });
        return hashes.concat(tapLeafHashes);
      }
      function checkSighashTypeAllowed(sighashType, sighashTypes) {
        if (sighashTypes && sighashTypes.indexOf(sighashType) < 0) {
          let str = sighashTypeToString(sighashType);
          throw new Error(
            `Sighash type is not allowed. Retry the sign method passing the sighashTypes array of whitelisted types. Sighash type: ${str}`
          );
        }
      }
      function getPayment(script2, scriptType2, partialSig) {
        let payment;
        switch (scriptType2) {
          case "multisig":
            let sigs = getSortedSigs(script2, partialSig);
            payment = payments2.p2ms({
              output: script2,
              signatures: sigs
            });
            break;
          case "pubkey":
            payment = payments2.p2pk({
              output: script2,
              signature: partialSig[0].signature
            });
            break;
          case "pubkeyhash":
            payment = payments2.p2pkh({
              output: script2,
              pubkey: partialSig[0].pubkey,
              signature: partialSig[0].signature
            });
            break;
          case "witnesspubkeyhash":
            payment = payments2.p2wpkh({
              output: script2,
              pubkey: partialSig[0].pubkey,
              signature: partialSig[0].signature
            });
            break;
        }
        return payment;
      }
      function getScriptFromInput(inputIndex, input, cache) {
        let unsignedTx = cache.__TX, res = {
          script: null,
          isSegwit: !1,
          isP2SH: !1,
          isP2WSH: !1
        };
        if (res.isP2SH = !!input.redeemScript, res.isP2WSH = !!input.witnessScript, input.witnessScript)
          res.script = input.witnessScript;
        else if (input.redeemScript)
          res.script = input.redeemScript;
        else if (input.nonWitnessUtxo) {
          let nonWitnessUtxoTx = nonWitnessUtxoTxFromCache(
            cache,
            input,
            inputIndex
          ), prevoutIndex = unsignedTx.ins[inputIndex].index;
          res.script = nonWitnessUtxoTx.outs[prevoutIndex].script;
        } else input.witnessUtxo && (res.script = input.witnessUtxo.script);
        return (input.witnessScript || (0, psbtutils_1.isP2WPKH)(res.script)) && (res.isSegwit = !0), res;
      }
      function getSignersFromHD(inputIndex, inputs, hdKeyPair) {
        let input = (0, utils_1.checkForInput)(inputs, inputIndex);
        if (!input.bip32Derivation || input.bip32Derivation.length === 0)
          throw new Error("Need bip32Derivation to sign with HD");
        let myDerivations = input.bip32Derivation.map((bipDv) => {
          if (bipDv.masterFingerprint.equals(hdKeyPair.fingerprint))
            return bipDv;
        }).filter((v) => !!v);
        if (myDerivations.length === 0)
          throw new Error(
            "Need one bip32Derivation masterFingerprint to match the HDSigner fingerprint"
          );
        return myDerivations.map((bipDv) => {
          let node = hdKeyPair.derivePath(bipDv.path);
          if (!bipDv.pubkey.equals(node.publicKey))
            throw new Error("pubkey did not match bip32Derivation");
          return node;
        });
      }
      function getSortedSigs(script2, partialSig) {
        return payments2.p2ms({ output: script2 }).pubkeys.map((pk) => (partialSig.filter((ps) => ps.pubkey.equals(pk))[0] || {}).signature).filter((v) => !!v);
      }
      function scriptWitnessToWitnessStack(buffer) {
        let offset = 0;
        function readSlice(n) {
          return offset += n, buffer.slice(offset - n, offset);
        }
        function readVarInt() {
          let vi = varuint.decode(buffer, offset);
          return offset += varuint.decode.bytes, vi;
        }
        function readVarSlice() {
          return readSlice(readVarInt());
        }
        function readVector() {
          let count = readVarInt(), vector = [];
          for (let i = 0; i < count; i++) vector.push(readVarSlice());
          return vector;
        }
        return readVector();
      }
      function sighashTypeToString(sighashType) {
        let text = sighashType & transaction_1.Transaction.SIGHASH_ANYONECANPAY ? "SIGHASH_ANYONECANPAY | " : "";
        switch (sighashType & 31) {
          case transaction_1.Transaction.SIGHASH_ALL:
            text += "SIGHASH_ALL";
            break;
          case transaction_1.Transaction.SIGHASH_SINGLE:
            text += "SIGHASH_SINGLE";
            break;
          case transaction_1.Transaction.SIGHASH_NONE:
            text += "SIGHASH_NONE";
            break;
        }
        return text;
      }
      function addNonWitnessTxCache(cache, input, inputIndex) {
        cache.__NON_WITNESS_UTXO_BUF_CACHE[inputIndex] = input.nonWitnessUtxo;
        let tx = transaction_1.Transaction.fromBuffer(input.nonWitnessUtxo);
        cache.__NON_WITNESS_UTXO_TX_CACHE[inputIndex] = tx;
        let self2 = cache, selfIndex = inputIndex;
        delete input.nonWitnessUtxo, Object.defineProperty(input, "nonWitnessUtxo", {
          enumerable: !0,
          get() {
            let buf = self2.__NON_WITNESS_UTXO_BUF_CACHE[selfIndex], txCache = self2.__NON_WITNESS_UTXO_TX_CACHE[selfIndex];
            if (buf !== void 0)
              return buf;
            {
              let newBuf = txCache.toBuffer();
              return self2.__NON_WITNESS_UTXO_BUF_CACHE[selfIndex] = newBuf, newBuf;
            }
          },
          set(data) {
            self2.__NON_WITNESS_UTXO_BUF_CACHE[selfIndex] = data;
          }
        });
      }
      function inputFinalizeGetAmts(inputs, tx, cache, mustFinalize) {
        let inputAmount = 0;
        inputs.forEach((input, idx) => {
          if (mustFinalize && input.finalScriptSig && (tx.ins[idx].script = input.finalScriptSig), mustFinalize && input.finalScriptWitness && (tx.ins[idx].witness = scriptWitnessToWitnessStack(
            input.finalScriptWitness
          )), input.witnessUtxo)
            inputAmount += input.witnessUtxo.value;
          else if (input.nonWitnessUtxo) {
            let nwTx = nonWitnessUtxoTxFromCache(cache, input, idx), vout = tx.ins[idx].index, out = nwTx.outs[vout];
            inputAmount += out.value;
          }
        });
        let outputAmount = tx.outs.reduce((total, o) => total + o.value, 0), fee = inputAmount - outputAmount;
        if (fee < 0)
          throw new Error("Outputs are spending more than Inputs");
        let bytes = tx.virtualSize();
        cache.__FEE = fee, cache.__EXTRACTED_TX = tx, cache.__FEE_RATE = Math.floor(fee / bytes);
      }
      function nonWitnessUtxoTxFromCache(cache, input, inputIndex) {
        let c = cache.__NON_WITNESS_UTXO_TX_CACHE;
        return c[inputIndex] || addNonWitnessTxCache(cache, input, inputIndex), c[inputIndex];
      }
      function getScriptFromUtxo(inputIndex, input, cache) {
        let { script: script2 } = getScriptAndAmountFromUtxo(inputIndex, input, cache);
        return script2;
      }
      function getScriptAndAmountFromUtxo(inputIndex, input, cache) {
        if (input.witnessUtxo !== void 0)
          return {
            script: input.witnessUtxo.script,
            value: input.witnessUtxo.value
          };
        if (input.nonWitnessUtxo !== void 0) {
          let o = nonWitnessUtxoTxFromCache(
            cache,
            input,
            inputIndex
          ).outs[cache.__TX.ins[inputIndex].index];
          return { script: o.script, value: o.value };
        } else
          throw new Error("Can't find pubkey in input without Utxo data");
      }
      function pubkeyInInput(pubkey, input, inputIndex, cache) {
        let script2 = getScriptFromUtxo(inputIndex, input, cache), { meaningfulScript } = getMeaningfulScript(
          script2,
          inputIndex,
          "input",
          input.redeemScript,
          input.witnessScript
        );
        return (0, psbtutils_1.pubkeyInScript)(pubkey, meaningfulScript);
      }
      function pubkeyInOutput(pubkey, output, outputIndex, cache) {
        let script2 = cache.__TX.outs[outputIndex].script, { meaningfulScript } = getMeaningfulScript(
          script2,
          outputIndex,
          "output",
          output.redeemScript,
          output.witnessScript
        );
        return (0, psbtutils_1.pubkeyInScript)(pubkey, meaningfulScript);
      }
      function redeemFromFinalScriptSig(finalScript) {
        if (!finalScript) return;
        let decomp = bscript.decompile(finalScript);
        if (!decomp) return;
        let lastItem = decomp[decomp.length - 1];
        if (!(!import_buffer.Buffer.isBuffer(lastItem) || isPubkeyLike(lastItem) || isSigLike(lastItem) || !bscript.decompile(lastItem)))
          return lastItem;
      }
      function redeemFromFinalWitnessScript(finalScript) {
        if (!finalScript) return;
        let decomp = scriptWitnessToWitnessStack(finalScript), lastItem = decomp[decomp.length - 1];
        if (!(isPubkeyLike(lastItem) || !bscript.decompile(lastItem)))
          return lastItem;
      }
      function compressPubkey(pubkey) {
        if (pubkey.length === 65) {
          let parity = pubkey[64] & 1, newKey = pubkey.slice(0, 33);
          return newKey[0] = 2 | parity, newKey;
        }
        return pubkey.slice();
      }
      function isPubkeyLike(buf) {
        return buf.length === 33 && bscript.isCanonicalPubKey(buf);
      }
      function isSigLike(buf) {
        return bscript.isCanonicalScriptSignature(buf);
      }
      function getMeaningfulScript(script2, index, ioType, redeemScript, witnessScript) {
        let isP2SH = (0, psbtutils_1.isP2SHScript)(script2), isP2SHP2WSH = isP2SH && redeemScript && (0, psbtutils_1.isP2WSHScript)(redeemScript), isP2WSH = (0, psbtutils_1.isP2WSHScript)(script2);
        if (isP2SH && redeemScript === void 0)
          throw new Error("scriptPubkey is P2SH but redeemScript missing");
        if ((isP2WSH || isP2SHP2WSH) && witnessScript === void 0)
          throw new Error(
            "scriptPubkey or redeemScript is P2WSH but witnessScript missing"
          );
        let meaningfulScript;
        return isP2SHP2WSH ? (meaningfulScript = witnessScript, checkRedeemScript(index, script2, redeemScript, ioType), checkWitnessScript(index, redeemScript, witnessScript, ioType), checkInvalidP2WSH(meaningfulScript)) : isP2WSH ? (meaningfulScript = witnessScript, checkWitnessScript(index, script2, witnessScript, ioType), checkInvalidP2WSH(meaningfulScript)) : isP2SH ? (meaningfulScript = redeemScript, checkRedeemScript(index, script2, redeemScript, ioType)) : meaningfulScript = script2, {
          meaningfulScript,
          type: isP2SHP2WSH ? "p2sh-p2wsh" : isP2SH ? "p2sh" : isP2WSH ? "p2wsh" : "raw"
        };
      }
      function checkInvalidP2WSH(script2) {
        if ((0, psbtutils_1.isP2WPKH)(script2) || (0, psbtutils_1.isP2SHScript)(script2))
          throw new Error("P2WPKH or P2SH can not be contained within P2WSH");
      }
      function classifyScript(script2) {
        return (0, psbtutils_1.isP2WPKH)(script2) ? "witnesspubkeyhash" : (0, psbtutils_1.isP2PKH)(script2) ? "pubkeyhash" : (0, psbtutils_1.isP2MS)(script2) ? "multisig" : (0, psbtutils_1.isP2PK)(script2) ? "pubkey" : "nonstandard";
      }
      function range(n) {
        return [...Array(n).keys()];
      }
    }
  });

  // node_modules/bitcoinjs-lib/src/index.js
  var require_src2 = __commonJS({
    "node_modules/bitcoinjs-lib/src/index.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      exports.initEccLib = exports.Transaction = exports.opcodes = exports.Psbt = exports.Block = exports.script = exports.payments = exports.networks = exports.crypto = exports.address = void 0;
      var address2 = require_address();
      exports.address = address2;
      var crypto2 = require_crypto2();
      exports.crypto = crypto2;
      var networks2 = require_networks();
      exports.networks = networks2;
      var payments2 = require_payments();
      exports.payments = payments2;
      var script2 = require_script();
      exports.script = script2;
      var block_1 = require_block();
      Object.defineProperty(exports, "Block", {
        enumerable: !0,
        get: function() {
          return block_1.Block;
        }
      });
      var psbt_1 = require_psbt2();
      Object.defineProperty(exports, "Psbt", {
        enumerable: !0,
        get: function() {
          return psbt_1.Psbt;
        }
      });
      var ops_1 = require_ops();
      Object.defineProperty(exports, "opcodes", {
        enumerable: !0,
        get: function() {
          return ops_1.OPS;
        }
      });
      var transaction_1 = require_transaction();
      Object.defineProperty(exports, "Transaction", {
        enumerable: !0,
        get: function() {
          return transaction_1.Transaction;
        }
      });
      var ecc_lib_1 = require_ecc_lib();
      Object.defineProperty(exports, "initEccLib", {
        enumerable: !0,
        get: function() {
          return ecc_lib_1.initEccLib;
        }
      });
    }
  });

  // node_modules/@noble/hashes/hmac.js
  var require_hmac = __commonJS({
    "node_modules/@noble/hashes/hmac.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      exports.hmac = exports.HMAC = void 0;
      var utils_ts_1 = require_utils(), HMAC = class extends utils_ts_1.Hash {
        constructor(hash, _key) {
          super(), this.finished = !1, this.destroyed = !1, (0, utils_ts_1.ahash)(hash);
          let key = (0, utils_ts_1.toBytes)(_key);
          if (this.iHash = hash.create(), typeof this.iHash.update != "function")
            throw new Error("Expected instance of class which extends utils.Hash");
          this.blockLen = this.iHash.blockLen, this.outputLen = this.iHash.outputLen;
          let blockLen = this.blockLen, pad = new Uint8Array(blockLen);
          pad.set(key.length > blockLen ? hash.create().update(key).digest() : key);
          for (let i = 0; i < pad.length; i++)
            pad[i] ^= 54;
          this.iHash.update(pad), this.oHash = hash.create();
          for (let i = 0; i < pad.length; i++)
            pad[i] ^= 106;
          this.oHash.update(pad), (0, utils_ts_1.clean)(pad);
        }
        update(buf) {
          return (0, utils_ts_1.aexists)(this), this.iHash.update(buf), this;
        }
        digestInto(out) {
          (0, utils_ts_1.aexists)(this), (0, utils_ts_1.abytes)(out, this.outputLen), this.finished = !0, this.iHash.digestInto(out), this.oHash.update(out), this.oHash.digestInto(out), this.destroy();
        }
        digest() {
          let out = new Uint8Array(this.oHash.outputLen);
          return this.digestInto(out), out;
        }
        _cloneInto(to) {
          to || (to = Object.create(Object.getPrototypeOf(this), {}));
          let { oHash, iHash, finished, destroyed, blockLen, outputLen } = this;
          return to = to, to.finished = finished, to.destroyed = destroyed, to.blockLen = blockLen, to.outputLen = outputLen, to.oHash = oHash._cloneInto(to.oHash), to.iHash = iHash._cloneInto(to.iHash), to;
        }
        clone() {
          return this._cloneInto();
        }
        destroy() {
          this.destroyed = !0, this.oHash.destroy(), this.iHash.destroy();
        }
      };
      exports.HMAC = HMAC;
      var hmac = (hash, key, message) => new HMAC(hash, key).update(message).digest();
      exports.hmac = hmac;
      exports.hmac.create = (hash, key) => new HMAC(hash, key);
    }
  });

  // node_modules/@noble/curves/utils.js
  var require_utils3 = __commonJS({
    "node_modules/@noble/curves/utils.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      exports.notImplemented = exports.bitMask = exports.utf8ToBytes = exports.randomBytes = exports.isBytes = exports.hexToBytes = exports.concatBytes = exports.bytesToUtf8 = exports.bytesToHex = exports.anumber = exports.abytes = void 0;
      exports.abool = abool;
      exports._abool2 = _abool2;
      exports._abytes2 = _abytes2;
      exports.numberToHexUnpadded = numberToHexUnpadded;
      exports.hexToNumber = hexToNumber;
      exports.bytesToNumberBE = bytesToNumberBE;
      exports.bytesToNumberLE = bytesToNumberLE;
      exports.numberToBytesBE = numberToBytesBE;
      exports.numberToBytesLE = numberToBytesLE;
      exports.numberToVarBytesBE = numberToVarBytesBE;
      exports.ensureBytes = ensureBytes;
      exports.equalBytes = equalBytes;
      exports.copyBytes = copyBytes;
      exports.asciiToBytes = asciiToBytes;
      exports.inRange = inRange;
      exports.aInRange = aInRange;
      exports.bitLen = bitLen;
      exports.bitGet = bitGet;
      exports.bitSet = bitSet;
      exports.createHmacDrbg = createHmacDrbg;
      exports.validateObject = validateObject;
      exports.isHash = isHash;
      exports._validateObject = _validateObject;
      exports.memoized = memoized;
      var utils_js_1 = require_utils(), utils_js_2 = require_utils();
      Object.defineProperty(exports, "abytes", { enumerable: !0, get: function() {
        return utils_js_2.abytes;
      } });
      Object.defineProperty(exports, "anumber", { enumerable: !0, get: function() {
        return utils_js_2.anumber;
      } });
      Object.defineProperty(exports, "bytesToHex", { enumerable: !0, get: function() {
        return utils_js_2.bytesToHex;
      } });
      Object.defineProperty(exports, "bytesToUtf8", { enumerable: !0, get: function() {
        return utils_js_2.bytesToUtf8;
      } });
      Object.defineProperty(exports, "concatBytes", { enumerable: !0, get: function() {
        return utils_js_2.concatBytes;
      } });
      Object.defineProperty(exports, "hexToBytes", { enumerable: !0, get: function() {
        return utils_js_2.hexToBytes;
      } });
      Object.defineProperty(exports, "isBytes", { enumerable: !0, get: function() {
        return utils_js_2.isBytes;
      } });
      Object.defineProperty(exports, "randomBytes", { enumerable: !0, get: function() {
        return utils_js_2.randomBytes;
      } });
      Object.defineProperty(exports, "utf8ToBytes", { enumerable: !0, get: function() {
        return utils_js_2.utf8ToBytes;
      } });
      var _0n = /* @__PURE__ */ BigInt(0), _1n = /* @__PURE__ */ BigInt(1);
      function abool(title, value) {
        if (typeof value != "boolean")
          throw new Error(title + " boolean expected, got " + value);
      }
      function _abool2(value, title = "") {
        if (typeof value != "boolean") {
          let prefix = title && `"${title}"`;
          throw new Error(prefix + "expected boolean, got type=" + typeof value);
        }
        return value;
      }
      function _abytes2(value, length, title = "") {
        let bytes = (0, utils_js_1.isBytes)(value), len = value?.length, needsLen = length !== void 0;
        if (!bytes || needsLen && len !== length) {
          let prefix = title && `"${title}" `, ofLen = needsLen ? ` of length ${length}` : "", got = bytes ? `length=${len}` : `type=${typeof value}`;
          throw new Error(prefix + "expected Uint8Array" + ofLen + ", got " + got);
        }
        return value;
      }
      function numberToHexUnpadded(num) {
        let hex = num.toString(16);
        return hex.length & 1 ? "0" + hex : hex;
      }
      function hexToNumber(hex) {
        if (typeof hex != "string")
          throw new Error("hex string expected, got " + typeof hex);
        return hex === "" ? _0n : BigInt("0x" + hex);
      }
      function bytesToNumberBE(bytes) {
        return hexToNumber((0, utils_js_1.bytesToHex)(bytes));
      }
      function bytesToNumberLE(bytes) {
        return (0, utils_js_1.abytes)(bytes), hexToNumber((0, utils_js_1.bytesToHex)(Uint8Array.from(bytes).reverse()));
      }
      function numberToBytesBE(n, len) {
        return (0, utils_js_1.hexToBytes)(n.toString(16).padStart(len * 2, "0"));
      }
      function numberToBytesLE(n, len) {
        return numberToBytesBE(n, len).reverse();
      }
      function numberToVarBytesBE(n) {
        return (0, utils_js_1.hexToBytes)(numberToHexUnpadded(n));
      }
      function ensureBytes(title, hex, expectedLength) {
        let res;
        if (typeof hex == "string")
          try {
            res = (0, utils_js_1.hexToBytes)(hex);
          } catch (e) {
            throw new Error(title + " must be hex string or Uint8Array, cause: " + e);
          }
        else if ((0, utils_js_1.isBytes)(hex))
          res = Uint8Array.from(hex);
        else
          throw new Error(title + " must be hex string or Uint8Array");
        let len = res.length;
        if (typeof expectedLength == "number" && len !== expectedLength)
          throw new Error(title + " of length " + expectedLength + " expected, got " + len);
        return res;
      }
      function equalBytes(a, b) {
        if (a.length !== b.length)
          return !1;
        let diff = 0;
        for (let i = 0; i < a.length; i++)
          diff |= a[i] ^ b[i];
        return diff === 0;
      }
      function copyBytes(bytes) {
        return Uint8Array.from(bytes);
      }
      function asciiToBytes(ascii) {
        return Uint8Array.from(ascii, (c, i) => {
          let charCode = c.charCodeAt(0);
          if (c.length !== 1 || charCode > 127)
            throw new Error(`string contains non-ASCII character "${ascii[i]}" with code ${charCode} at position ${i}`);
          return charCode;
        });
      }
      var isPosBig = (n) => typeof n == "bigint" && _0n <= n;
      function inRange(n, min, max) {
        return isPosBig(n) && isPosBig(min) && isPosBig(max) && min <= n && n < max;
      }
      function aInRange(title, n, min, max) {
        if (!inRange(n, min, max))
          throw new Error("expected valid " + title + ": " + min + " <= n < " + max + ", got " + n);
      }
      function bitLen(n) {
        let len;
        for (len = 0; n > _0n; n >>= _1n, len += 1)
          ;
        return len;
      }
      function bitGet(n, pos) {
        return n >> BigInt(pos) & _1n;
      }
      function bitSet(n, pos, value) {
        return n | (value ? _1n : _0n) << BigInt(pos);
      }
      var bitMask = (n) => (_1n << BigInt(n)) - _1n;
      exports.bitMask = bitMask;
      function createHmacDrbg(hashLen, qByteLen, hmacFn) {
        if (typeof hashLen != "number" || hashLen < 2)
          throw new Error("hashLen must be a number");
        if (typeof qByteLen != "number" || qByteLen < 2)
          throw new Error("qByteLen must be a number");
        if (typeof hmacFn != "function")
          throw new Error("hmacFn must be a function");
        let u8n = (len) => new Uint8Array(len), u8of = (byte) => Uint8Array.of(byte), v = u8n(hashLen), k = u8n(hashLen), i = 0, reset = () => {
          v.fill(1), k.fill(0), i = 0;
        }, h = (...b) => hmacFn(k, v, ...b), reseed = (seed = u8n(0)) => {
          k = h(u8of(0), seed), v = h(), seed.length !== 0 && (k = h(u8of(1), seed), v = h());
        }, gen = () => {
          if (i++ >= 1e3)
            throw new Error("drbg: tried 1000 values");
          let len = 0, out = [];
          for (; len < qByteLen; ) {
            v = h();
            let sl = v.slice();
            out.push(sl), len += v.length;
          }
          return (0, utils_js_1.concatBytes)(...out);
        };
        return (seed, pred) => {
          reset(), reseed(seed);
          let res;
          for (; !(res = pred(gen())); )
            reseed();
          return reset(), res;
        };
      }
      var validatorFns = {
        bigint: (val) => typeof val == "bigint",
        function: (val) => typeof val == "function",
        boolean: (val) => typeof val == "boolean",
        string: (val) => typeof val == "string",
        stringOrUint8Array: (val) => typeof val == "string" || (0, utils_js_1.isBytes)(val),
        isSafeInteger: (val) => Number.isSafeInteger(val),
        array: (val) => Array.isArray(val),
        field: (val, object) => object.Fp.isValid(val),
        hash: (val) => typeof val == "function" && Number.isSafeInteger(val.outputLen)
      };
      function validateObject(object, validators, optValidators = {}) {
        let checkField = (fieldName, type, isOptional) => {
          let checkVal = validatorFns[type];
          if (typeof checkVal != "function")
            throw new Error("invalid validator function");
          let val = object[fieldName];
          if (!(isOptional && val === void 0) && !checkVal(val, object))
            throw new Error("param " + String(fieldName) + " is invalid. Expected " + type + ", got " + val);
        };
        for (let [fieldName, type] of Object.entries(validators))
          checkField(fieldName, type, !1);
        for (let [fieldName, type] of Object.entries(optValidators))
          checkField(fieldName, type, !0);
        return object;
      }
      function isHash(val) {
        return typeof val == "function" && Number.isSafeInteger(val.outputLen);
      }
      function _validateObject(object, fields, optFields = {}) {
        if (!object || typeof object != "object")
          throw new Error("expected valid options object");
        function checkField(fieldName, expectedType, isOpt) {
          let val = object[fieldName];
          if (isOpt && val === void 0)
            return;
          let current = typeof val;
          if (current !== expectedType || val === null)
            throw new Error(`param "${fieldName}" is invalid: expected ${expectedType}, got ${current}`);
        }
        Object.entries(fields).forEach(([k, v]) => checkField(k, v, !1)), Object.entries(optFields).forEach(([k, v]) => checkField(k, v, !0));
      }
      var notImplemented = () => {
        throw new Error("not implemented");
      };
      exports.notImplemented = notImplemented;
      function memoized(fn) {
        let map = /* @__PURE__ */ new WeakMap();
        return (arg, ...args) => {
          let val = map.get(arg);
          if (val !== void 0)
            return val;
          let computed = fn(arg, ...args);
          return map.set(arg, computed), computed;
        };
      }
    }
  });

  // node_modules/@noble/curves/abstract/modular.js
  var require_modular = __commonJS({
    "node_modules/@noble/curves/abstract/modular.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      exports.isNegativeLE = void 0;
      exports.mod = mod;
      exports.pow = pow;
      exports.pow2 = pow2;
      exports.invert = invert;
      exports.tonelliShanks = tonelliShanks;
      exports.FpSqrt = FpSqrt;
      exports.validateField = validateField;
      exports.FpPow = FpPow;
      exports.FpInvertBatch = FpInvertBatch;
      exports.FpDiv = FpDiv;
      exports.FpLegendre = FpLegendre;
      exports.FpIsSquare = FpIsSquare;
      exports.nLength = nLength;
      exports.Field = Field;
      exports.FpSqrtOdd = FpSqrtOdd;
      exports.FpSqrtEven = FpSqrtEven;
      exports.hashToPrivateScalar = hashToPrivateScalar;
      exports.getFieldBytesLength = getFieldBytesLength;
      exports.getMinHashLength = getMinHashLength;
      exports.mapHashToField = mapHashToField;
      var utils_ts_1 = require_utils3(), _0n = BigInt(0), _1n = BigInt(1), _2n = /* @__PURE__ */ BigInt(2), _3n = /* @__PURE__ */ BigInt(3), _4n = /* @__PURE__ */ BigInt(4), _5n = /* @__PURE__ */ BigInt(5), _7n = /* @__PURE__ */ BigInt(7), _8n = /* @__PURE__ */ BigInt(8), _9n = /* @__PURE__ */ BigInt(9), _16n = /* @__PURE__ */ BigInt(16);
      function mod(a, b) {
        let result = a % b;
        return result >= _0n ? result : b + result;
      }
      function pow(num, power, modulo) {
        return FpPow(Field(modulo), num, power);
      }
      function pow2(x, power, modulo) {
        let res = x;
        for (; power-- > _0n; )
          res *= res, res %= modulo;
        return res;
      }
      function invert(number, modulo) {
        if (number === _0n)
          throw new Error("invert: expected non-zero number");
        if (modulo <= _0n)
          throw new Error("invert: expected positive modulus, got " + modulo);
        let a = mod(number, modulo), b = modulo, x = _0n, y = _1n, u = _1n, v = _0n;
        for (; a !== _0n; ) {
          let q = b / a, r = b % a, m = x - u * q, n = y - v * q;
          b = a, a = r, x = u, y = v, u = m, v = n;
        }
        if (b !== _1n)
          throw new Error("invert: does not exist");
        return mod(x, modulo);
      }
      function assertIsSquare(Fp, root, n) {
        if (!Fp.eql(Fp.sqr(root), n))
          throw new Error("Cannot find square root");
      }
      function sqrt3mod4(Fp, n) {
        let p1div4 = (Fp.ORDER + _1n) / _4n, root = Fp.pow(n, p1div4);
        return assertIsSquare(Fp, root, n), root;
      }
      function sqrt5mod8(Fp, n) {
        let p5div8 = (Fp.ORDER - _5n) / _8n, n2 = Fp.mul(n, _2n), v = Fp.pow(n2, p5div8), nv = Fp.mul(n, v), i = Fp.mul(Fp.mul(nv, _2n), v), root = Fp.mul(nv, Fp.sub(i, Fp.ONE));
        return assertIsSquare(Fp, root, n), root;
      }
      function sqrt9mod16(P) {
        let Fp_ = Field(P), tn = tonelliShanks(P), c1 = tn(Fp_, Fp_.neg(Fp_.ONE)), c2 = tn(Fp_, c1), c3 = tn(Fp_, Fp_.neg(c1)), c4 = (P + _7n) / _16n;
        return (Fp, n) => {
          let tv1 = Fp.pow(n, c4), tv2 = Fp.mul(tv1, c1), tv3 = Fp.mul(tv1, c2), tv4 = Fp.mul(tv1, c3), e1 = Fp.eql(Fp.sqr(tv2), n), e2 = Fp.eql(Fp.sqr(tv3), n);
          tv1 = Fp.cmov(tv1, tv2, e1), tv2 = Fp.cmov(tv4, tv3, e2);
          let e3 = Fp.eql(Fp.sqr(tv2), n), root = Fp.cmov(tv1, tv2, e3);
          return assertIsSquare(Fp, root, n), root;
        };
      }
      function tonelliShanks(P) {
        if (P < _3n)
          throw new Error("sqrt is not defined for small field");
        let Q = P - _1n, S = 0;
        for (; Q % _2n === _0n; )
          Q /= _2n, S++;
        let Z = _2n, _Fp = Field(P);
        for (; FpLegendre(_Fp, Z) === 1; )
          if (Z++ > 1e3)
            throw new Error("Cannot find square root: probably non-prime P");
        if (S === 1)
          return sqrt3mod4;
        let cc = _Fp.pow(Z, Q), Q1div2 = (Q + _1n) / _2n;
        return function(Fp, n) {
          if (Fp.is0(n))
            return n;
          if (FpLegendre(Fp, n) !== 1)
            throw new Error("Cannot find square root");
          let M = S, c = Fp.mul(Fp.ONE, cc), t = Fp.pow(n, Q), R = Fp.pow(n, Q1div2);
          for (; !Fp.eql(t, Fp.ONE); ) {
            if (Fp.is0(t))
              return Fp.ZERO;
            let i = 1, t_tmp = Fp.sqr(t);
            for (; !Fp.eql(t_tmp, Fp.ONE); )
              if (i++, t_tmp = Fp.sqr(t_tmp), i === M)
                throw new Error("Cannot find square root");
            let exponent = _1n << BigInt(M - i - 1), b = Fp.pow(c, exponent);
            M = i, c = Fp.sqr(b), t = Fp.mul(t, c), R = Fp.mul(R, b);
          }
          return R;
        };
      }
      function FpSqrt(P) {
        return P % _4n === _3n ? sqrt3mod4 : P % _8n === _5n ? sqrt5mod8 : P % _16n === _9n ? sqrt9mod16(P) : tonelliShanks(P);
      }
      var isNegativeLE = (num, modulo) => (mod(num, modulo) & _1n) === _1n;
      exports.isNegativeLE = isNegativeLE;
      var FIELD_FIELDS = [
        "create",
        "isValid",
        "is0",
        "neg",
        "inv",
        "sqrt",
        "sqr",
        "eql",
        "add",
        "sub",
        "mul",
        "pow",
        "div",
        "addN",
        "subN",
        "mulN",
        "sqrN"
      ];
      function validateField(field) {
        let initial = {
          ORDER: "bigint",
          MASK: "bigint",
          BYTES: "number",
          BITS: "number"
        }, opts = FIELD_FIELDS.reduce((map, val) => (map[val] = "function", map), initial);
        return (0, utils_ts_1._validateObject)(field, opts), field;
      }
      function FpPow(Fp, num, power) {
        if (power < _0n)
          throw new Error("invalid exponent, negatives unsupported");
        if (power === _0n)
          return Fp.ONE;
        if (power === _1n)
          return num;
        let p = Fp.ONE, d = num;
        for (; power > _0n; )
          power & _1n && (p = Fp.mul(p, d)), d = Fp.sqr(d), power >>= _1n;
        return p;
      }
      function FpInvertBatch(Fp, nums, passZero = !1) {
        let inverted = new Array(nums.length).fill(passZero ? Fp.ZERO : void 0), multipliedAcc = nums.reduce((acc, num, i) => Fp.is0(num) ? acc : (inverted[i] = acc, Fp.mul(acc, num)), Fp.ONE), invertedAcc = Fp.inv(multipliedAcc);
        return nums.reduceRight((acc, num, i) => Fp.is0(num) ? acc : (inverted[i] = Fp.mul(acc, inverted[i]), Fp.mul(acc, num)), invertedAcc), inverted;
      }
      function FpDiv(Fp, lhs, rhs) {
        return Fp.mul(lhs, typeof rhs == "bigint" ? invert(rhs, Fp.ORDER) : Fp.inv(rhs));
      }
      function FpLegendre(Fp, n) {
        let p1mod2 = (Fp.ORDER - _1n) / _2n, powered = Fp.pow(n, p1mod2), yes = Fp.eql(powered, Fp.ONE), zero = Fp.eql(powered, Fp.ZERO), no = Fp.eql(powered, Fp.neg(Fp.ONE));
        if (!yes && !zero && !no)
          throw new Error("invalid Legendre symbol result");
        return yes ? 1 : zero ? 0 : -1;
      }
      function FpIsSquare(Fp, n) {
        return FpLegendre(Fp, n) === 1;
      }
      function nLength(n, nBitLength) {
        nBitLength !== void 0 && (0, utils_ts_1.anumber)(nBitLength);
        let _nBitLength = nBitLength !== void 0 ? nBitLength : n.toString(2).length, nByteLength = Math.ceil(_nBitLength / 8);
        return { nBitLength: _nBitLength, nByteLength };
      }
      function Field(ORDER, bitLenOrOpts, isLE = !1, opts = {}) {
        if (ORDER <= _0n)
          throw new Error("invalid field: expected ORDER > 0, got " + ORDER);
        let _nbitLength, _sqrt, modFromBytes = !1, allowedLengths;
        if (typeof bitLenOrOpts == "object" && bitLenOrOpts != null) {
          if (opts.sqrt || isLE)
            throw new Error("cannot specify opts in two arguments");
          let _opts = bitLenOrOpts;
          _opts.BITS && (_nbitLength = _opts.BITS), _opts.sqrt && (_sqrt = _opts.sqrt), typeof _opts.isLE == "boolean" && (isLE = _opts.isLE), typeof _opts.modFromBytes == "boolean" && (modFromBytes = _opts.modFromBytes), allowedLengths = _opts.allowedLengths;
        } else
          typeof bitLenOrOpts == "number" && (_nbitLength = bitLenOrOpts), opts.sqrt && (_sqrt = opts.sqrt);
        let { nBitLength: BITS, nByteLength: BYTES } = nLength(ORDER, _nbitLength);
        if (BYTES > 2048)
          throw new Error("invalid field: expected ORDER of <= 2048 bytes");
        let sqrtP, f = Object.freeze({
          ORDER,
          isLE,
          BITS,
          BYTES,
          MASK: (0, utils_ts_1.bitMask)(BITS),
          ZERO: _0n,
          ONE: _1n,
          allowedLengths,
          create: (num) => mod(num, ORDER),
          isValid: (num) => {
            if (typeof num != "bigint")
              throw new Error("invalid field element: expected bigint, got " + typeof num);
            return _0n <= num && num < ORDER;
          },
          is0: (num) => num === _0n,
          // is valid and invertible
          isValidNot0: (num) => !f.is0(num) && f.isValid(num),
          isOdd: (num) => (num & _1n) === _1n,
          neg: (num) => mod(-num, ORDER),
          eql: (lhs, rhs) => lhs === rhs,
          sqr: (num) => mod(num * num, ORDER),
          add: (lhs, rhs) => mod(lhs + rhs, ORDER),
          sub: (lhs, rhs) => mod(lhs - rhs, ORDER),
          mul: (lhs, rhs) => mod(lhs * rhs, ORDER),
          pow: (num, power) => FpPow(f, num, power),
          div: (lhs, rhs) => mod(lhs * invert(rhs, ORDER), ORDER),
          // Same as above, but doesn't normalize
          sqrN: (num) => num * num,
          addN: (lhs, rhs) => lhs + rhs,
          subN: (lhs, rhs) => lhs - rhs,
          mulN: (lhs, rhs) => lhs * rhs,
          inv: (num) => invert(num, ORDER),
          sqrt: _sqrt || ((n) => (sqrtP || (sqrtP = FpSqrt(ORDER)), sqrtP(f, n))),
          toBytes: (num) => isLE ? (0, utils_ts_1.numberToBytesLE)(num, BYTES) : (0, utils_ts_1.numberToBytesBE)(num, BYTES),
          fromBytes: (bytes, skipValidation = !0) => {
            if (allowedLengths) {
              if (!allowedLengths.includes(bytes.length) || bytes.length > BYTES)
                throw new Error("Field.fromBytes: expected " + allowedLengths + " bytes, got " + bytes.length);
              let padded = new Uint8Array(BYTES);
              padded.set(bytes, isLE ? 0 : padded.length - bytes.length), bytes = padded;
            }
            if (bytes.length !== BYTES)
              throw new Error("Field.fromBytes: expected " + BYTES + " bytes, got " + bytes.length);
            let scalar = isLE ? (0, utils_ts_1.bytesToNumberLE)(bytes) : (0, utils_ts_1.bytesToNumberBE)(bytes);
            if (modFromBytes && (scalar = mod(scalar, ORDER)), !skipValidation && !f.isValid(scalar))
              throw new Error("invalid field element: outside of range 0..ORDER");
            return scalar;
          },
          // TODO: we don't need it here, move out to separate fn
          invertBatch: (lst) => FpInvertBatch(f, lst),
          // We can't move this out because Fp6, Fp12 implement it
          // and it's unclear what to return in there.
          cmov: (a, b, c) => c ? b : a
        });
        return Object.freeze(f);
      }
      function FpSqrtOdd(Fp, elm) {
        if (!Fp.isOdd)
          throw new Error("Field doesn't have isOdd");
        let root = Fp.sqrt(elm);
        return Fp.isOdd(root) ? root : Fp.neg(root);
      }
      function FpSqrtEven(Fp, elm) {
        if (!Fp.isOdd)
          throw new Error("Field doesn't have isOdd");
        let root = Fp.sqrt(elm);
        return Fp.isOdd(root) ? Fp.neg(root) : root;
      }
      function hashToPrivateScalar(hash, groupOrder, isLE = !1) {
        hash = (0, utils_ts_1.ensureBytes)("privateHash", hash);
        let hashLen = hash.length, minLen = nLength(groupOrder).nByteLength + 8;
        if (minLen < 24 || hashLen < minLen || hashLen > 1024)
          throw new Error("hashToPrivateScalar: expected " + minLen + "-1024 bytes of input, got " + hashLen);
        let num = isLE ? (0, utils_ts_1.bytesToNumberLE)(hash) : (0, utils_ts_1.bytesToNumberBE)(hash);
        return mod(num, groupOrder - _1n) + _1n;
      }
      function getFieldBytesLength(fieldOrder) {
        if (typeof fieldOrder != "bigint")
          throw new Error("field order must be bigint");
        let bitLength = fieldOrder.toString(2).length;
        return Math.ceil(bitLength / 8);
      }
      function getMinHashLength(fieldOrder) {
        let length = getFieldBytesLength(fieldOrder);
        return length + Math.ceil(length / 2);
      }
      function mapHashToField(key, fieldOrder, isLE = !1) {
        let len = key.length, fieldLen = getFieldBytesLength(fieldOrder), minLen = getMinHashLength(fieldOrder);
        if (len < 16 || len < minLen || len > 1024)
          throw new Error("expected " + minLen + "-1024 bytes of input, got " + len);
        let num = isLE ? (0, utils_ts_1.bytesToNumberLE)(key) : (0, utils_ts_1.bytesToNumberBE)(key), reduced = mod(num, fieldOrder - _1n) + _1n;
        return isLE ? (0, utils_ts_1.numberToBytesLE)(reduced, fieldLen) : (0, utils_ts_1.numberToBytesBE)(reduced, fieldLen);
      }
    }
  });

  // node_modules/@noble/curves/abstract/curve.js
  var require_curve = __commonJS({
    "node_modules/@noble/curves/abstract/curve.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      exports.wNAF = void 0;
      exports.negateCt = negateCt;
      exports.normalizeZ = normalizeZ;
      exports.mulEndoUnsafe = mulEndoUnsafe;
      exports.pippenger = pippenger;
      exports.precomputeMSMUnsafe = precomputeMSMUnsafe;
      exports.validateBasic = validateBasic;
      exports._createCurveFields = _createCurveFields;
      var utils_ts_1 = require_utils3(), modular_ts_1 = require_modular(), _0n = BigInt(0), _1n = BigInt(1);
      function negateCt(condition, item) {
        let neg = item.negate();
        return condition ? neg : item;
      }
      function normalizeZ(c, points) {
        let invertedZs = (0, modular_ts_1.FpInvertBatch)(c.Fp, points.map((p) => p.Z));
        return points.map((p, i) => c.fromAffine(p.toAffine(invertedZs[i])));
      }
      function validateW(W, bits) {
        if (!Number.isSafeInteger(W) || W <= 0 || W > bits)
          throw new Error("invalid window size, expected [1.." + bits + "], got W=" + W);
      }
      function calcWOpts(W, scalarBits) {
        validateW(W, scalarBits);
        let windows = Math.ceil(scalarBits / W) + 1, windowSize = 2 ** (W - 1), maxNumber = 2 ** W, mask = (0, utils_ts_1.bitMask)(W), shiftBy = BigInt(W);
        return { windows, windowSize, mask, maxNumber, shiftBy };
      }
      function calcOffsets(n, window2, wOpts) {
        let { windowSize, mask, maxNumber, shiftBy } = wOpts, wbits = Number(n & mask), nextN = n >> shiftBy;
        wbits > windowSize && (wbits -= maxNumber, nextN += _1n);
        let offsetStart = window2 * windowSize, offset = offsetStart + Math.abs(wbits) - 1, isZero = wbits === 0, isNeg = wbits < 0, isNegF = window2 % 2 !== 0;
        return { nextN, offset, isZero, isNeg, isNegF, offsetF: offsetStart };
      }
      function validateMSMPoints(points, c) {
        if (!Array.isArray(points))
          throw new Error("array expected");
        points.forEach((p, i) => {
          if (!(p instanceof c))
            throw new Error("invalid point at index " + i);
        });
      }
      function validateMSMScalars(scalars, field) {
        if (!Array.isArray(scalars))
          throw new Error("array of scalars expected");
        scalars.forEach((s, i) => {
          if (!field.isValid(s))
            throw new Error("invalid scalar at index " + i);
        });
      }
      var pointPrecomputes = /* @__PURE__ */ new WeakMap(), pointWindowSizes = /* @__PURE__ */ new WeakMap();
      function getW(P) {
        return pointWindowSizes.get(P) || 1;
      }
      function assert0(n) {
        if (n !== _0n)
          throw new Error("invalid wNAF");
      }
      var wNAF = class {
        // Parametrized with a given Point class (not individual point)
        constructor(Point, bits) {
          this.BASE = Point.BASE, this.ZERO = Point.ZERO, this.Fn = Point.Fn, this.bits = bits;
        }
        // non-const time multiplication ladder
        _unsafeLadder(elm, n, p = this.ZERO) {
          let d = elm;
          for (; n > _0n; )
            n & _1n && (p = p.add(d)), d = d.double(), n >>= _1n;
          return p;
        }
        /**
         * Creates a wNAF precomputation window. Used for caching.
         * Default window size is set by `utils.precompute()` and is equal to 8.
         * Number of precomputed points depends on the curve size:
         * 2^(𝑊−1) * (Math.ceil(𝑛 / 𝑊) + 1), where:
         * - 𝑊 is the window size
         * - 𝑛 is the bitlength of the curve order.
         * For a 256-bit curve and window size 8, the number of precomputed points is 128 * 33 = 4224.
         * @param point Point instance
         * @param W window size
         * @returns precomputed point tables flattened to a single array
         */
        precomputeWindow(point, W) {
          let { windows, windowSize } = calcWOpts(W, this.bits), points = [], p = point, base = p;
          for (let window2 = 0; window2 < windows; window2++) {
            base = p, points.push(base);
            for (let i = 1; i < windowSize; i++)
              base = base.add(p), points.push(base);
            p = base.double();
          }
          return points;
        }
        /**
         * Implements ec multiplication using precomputed tables and w-ary non-adjacent form.
         * More compact implementation:
         * https://github.com/paulmillr/noble-secp256k1/blob/47cb1669b6e506ad66b35fe7d76132ae97465da2/index.ts#L502-L541
         * @returns real and fake (for const-time) points
         */
        wNAF(W, precomputes, n) {
          if (!this.Fn.isValid(n))
            throw new Error("invalid scalar");
          let p = this.ZERO, f = this.BASE, wo = calcWOpts(W, this.bits);
          for (let window2 = 0; window2 < wo.windows; window2++) {
            let { nextN, offset, isZero, isNeg, isNegF, offsetF } = calcOffsets(n, window2, wo);
            n = nextN, isZero ? f = f.add(negateCt(isNegF, precomputes[offsetF])) : p = p.add(negateCt(isNeg, precomputes[offset]));
          }
          return assert0(n), { p, f };
        }
        /**
         * Implements ec unsafe (non const-time) multiplication using precomputed tables and w-ary non-adjacent form.
         * @param acc accumulator point to add result of multiplication
         * @returns point
         */
        wNAFUnsafe(W, precomputes, n, acc = this.ZERO) {
          let wo = calcWOpts(W, this.bits);
          for (let window2 = 0; window2 < wo.windows && n !== _0n; window2++) {
            let { nextN, offset, isZero, isNeg } = calcOffsets(n, window2, wo);
            if (n = nextN, !isZero) {
              let item = precomputes[offset];
              acc = acc.add(isNeg ? item.negate() : item);
            }
          }
          return assert0(n), acc;
        }
        getPrecomputes(W, point, transform) {
          let comp = pointPrecomputes.get(point);
          return comp || (comp = this.precomputeWindow(point, W), W !== 1 && (typeof transform == "function" && (comp = transform(comp)), pointPrecomputes.set(point, comp))), comp;
        }
        cached(point, scalar, transform) {
          let W = getW(point);
          return this.wNAF(W, this.getPrecomputes(W, point, transform), scalar);
        }
        unsafe(point, scalar, transform, prev) {
          let W = getW(point);
          return W === 1 ? this._unsafeLadder(point, scalar, prev) : this.wNAFUnsafe(W, this.getPrecomputes(W, point, transform), scalar, prev);
        }
        // We calculate precomputes for elliptic curve point multiplication
        // using windowed method. This specifies window size and
        // stores precomputed values. Usually only base point would be precomputed.
        createCache(P, W) {
          validateW(W, this.bits), pointWindowSizes.set(P, W), pointPrecomputes.delete(P);
        }
        hasCache(elm) {
          return getW(elm) !== 1;
        }
      };
      exports.wNAF = wNAF;
      function mulEndoUnsafe(Point, point, k1, k2) {
        let acc = point, p1 = Point.ZERO, p2 = Point.ZERO;
        for (; k1 > _0n || k2 > _0n; )
          k1 & _1n && (p1 = p1.add(acc)), k2 & _1n && (p2 = p2.add(acc)), acc = acc.double(), k1 >>= _1n, k2 >>= _1n;
        return { p1, p2 };
      }
      function pippenger(c, fieldN, points, scalars) {
        validateMSMPoints(points, c), validateMSMScalars(scalars, fieldN);
        let plength = points.length, slength = scalars.length;
        if (plength !== slength)
          throw new Error("arrays of points and scalars must have equal length");
        let zero = c.ZERO, wbits = (0, utils_ts_1.bitLen)(BigInt(plength)), windowSize = 1;
        wbits > 12 ? windowSize = wbits - 3 : wbits > 4 ? windowSize = wbits - 2 : wbits > 0 && (windowSize = 2);
        let MASK = (0, utils_ts_1.bitMask)(windowSize), buckets = new Array(Number(MASK) + 1).fill(zero), lastBits = Math.floor((fieldN.BITS - 1) / windowSize) * windowSize, sum = zero;
        for (let i = lastBits; i >= 0; i -= windowSize) {
          buckets.fill(zero);
          for (let j = 0; j < slength; j++) {
            let scalar = scalars[j], wbits2 = Number(scalar >> BigInt(i) & MASK);
            buckets[wbits2] = buckets[wbits2].add(points[j]);
          }
          let resI = zero;
          for (let j = buckets.length - 1, sumI = zero; j > 0; j--)
            sumI = sumI.add(buckets[j]), resI = resI.add(sumI);
          if (sum = sum.add(resI), i !== 0)
            for (let j = 0; j < windowSize; j++)
              sum = sum.double();
        }
        return sum;
      }
      function precomputeMSMUnsafe(c, fieldN, points, windowSize) {
        validateW(windowSize, fieldN.BITS), validateMSMPoints(points, c);
        let zero = c.ZERO, tableSize = 2 ** windowSize - 1, chunks = Math.ceil(fieldN.BITS / windowSize), MASK = (0, utils_ts_1.bitMask)(windowSize), tables = points.map((p) => {
          let res = [];
          for (let i = 0, acc = p; i < tableSize; i++)
            res.push(acc), acc = acc.add(p);
          return res;
        });
        return (scalars) => {
          if (validateMSMScalars(scalars, fieldN), scalars.length > points.length)
            throw new Error("array of scalars must be smaller than array of points");
          let res = zero;
          for (let i = 0; i < chunks; i++) {
            if (res !== zero)
              for (let j = 0; j < windowSize; j++)
                res = res.double();
            let shiftBy = BigInt(chunks * windowSize - (i + 1) * windowSize);
            for (let j = 0; j < scalars.length; j++) {
              let n = scalars[j], curr = Number(n >> shiftBy & MASK);
              curr && (res = res.add(tables[j][curr - 1]));
            }
          }
          return res;
        };
      }
      function validateBasic(curve) {
        return (0, modular_ts_1.validateField)(curve.Fp), (0, utils_ts_1.validateObject)(curve, {
          n: "bigint",
          h: "bigint",
          Gx: "field",
          Gy: "field"
        }, {
          nBitLength: "isSafeInteger",
          nByteLength: "isSafeInteger"
        }), Object.freeze({
          ...(0, modular_ts_1.nLength)(curve.n, curve.nBitLength),
          ...curve,
          p: curve.Fp.ORDER
        });
      }
      function createField(order, field, isLE) {
        if (field) {
          if (field.ORDER !== order)
            throw new Error("Field.ORDER must match order: Fp == p, Fn == n");
          return (0, modular_ts_1.validateField)(field), field;
        } else
          return (0, modular_ts_1.Field)(order, { isLE });
      }
      function _createCurveFields(type, CURVE, curveOpts = {}, FpFnLE) {
        if (FpFnLE === void 0 && (FpFnLE = type === "edwards"), !CURVE || typeof CURVE != "object")
          throw new Error(`expected valid ${type} CURVE object`);
        for (let p of ["p", "n", "h"]) {
          let val = CURVE[p];
          if (!(typeof val == "bigint" && val > _0n))
            throw new Error(`CURVE.${p} must be positive bigint`);
        }
        let Fp = createField(CURVE.p, curveOpts.Fp, FpFnLE), Fn = createField(CURVE.n, curveOpts.Fn, FpFnLE), params = ["Gx", "Gy", "a", type === "weierstrass" ? "b" : "d"];
        for (let p of params)
          if (!Fp.isValid(CURVE[p]))
            throw new Error(`CURVE.${p} must be valid field element of CURVE.Fp`);
        return CURVE = Object.freeze(Object.assign({}, CURVE)), { CURVE, Fp, Fn };
      }
    }
  });

  // node_modules/@noble/curves/abstract/weierstrass.js
  var require_weierstrass = __commonJS({
    "node_modules/@noble/curves/abstract/weierstrass.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      exports.DER = exports.DERErr = void 0;
      exports._splitEndoScalar = _splitEndoScalar;
      exports._normFnElement = _normFnElement;
      exports.weierstrassN = weierstrassN;
      exports.SWUFpSqrtRatio = SWUFpSqrtRatio;
      exports.mapToCurveSimpleSWU = mapToCurveSimpleSWU;
      exports.ecdh = ecdh;
      exports.ecdsa = ecdsa;
      exports.weierstrassPoints = weierstrassPoints;
      exports._legacyHelperEquat = _legacyHelperEquat;
      exports.weierstrass = weierstrass;
      var hmac_js_1 = require_hmac(), utils_1 = require_utils(), utils_ts_1 = require_utils3(), curve_ts_1 = require_curve(), modular_ts_1 = require_modular(), divNearest = (num, den) => (num + (num >= 0 ? den : -den) / _2n) / den;
      function _splitEndoScalar(k, basis, n) {
        let [[a1, b1], [a2, b2]] = basis, c1 = divNearest(b2 * k, n), c2 = divNearest(-b1 * k, n), k1 = k - c1 * a1 - c2 * a2, k2 = -c1 * b1 - c2 * b2, k1neg = k1 < _0n, k2neg = k2 < _0n;
        k1neg && (k1 = -k1), k2neg && (k2 = -k2);
        let MAX_NUM = (0, utils_ts_1.bitMask)(Math.ceil((0, utils_ts_1.bitLen)(n) / 2)) + _1n;
        if (k1 < _0n || k1 >= MAX_NUM || k2 < _0n || k2 >= MAX_NUM)
          throw new Error("splitScalar (endomorphism): failed, k=" + k);
        return { k1neg, k1, k2neg, k2 };
      }
      function validateSigFormat(format) {
        if (!["compact", "recovered", "der"].includes(format))
          throw new Error('Signature format must be "compact", "recovered", or "der"');
        return format;
      }
      function validateSigOpts(opts, def) {
        let optsn = {};
        for (let optName of Object.keys(def))
          optsn[optName] = opts[optName] === void 0 ? def[optName] : opts[optName];
        return (0, utils_ts_1._abool2)(optsn.lowS, "lowS"), (0, utils_ts_1._abool2)(optsn.prehash, "prehash"), optsn.format !== void 0 && validateSigFormat(optsn.format), optsn;
      }
      var DERErr = class extends Error {
        constructor(m = "") {
          super(m);
        }
      };
      exports.DERErr = DERErr;
      exports.DER = {
        // asn.1 DER encoding utils
        Err: DERErr,
        // Basic building block is TLV (Tag-Length-Value)
        _tlv: {
          encode: (tag, data) => {
            let { Err: E } = exports.DER;
            if (tag < 0 || tag > 256)
              throw new E("tlv.encode: wrong tag");
            if (data.length & 1)
              throw new E("tlv.encode: unpadded data");
            let dataLen = data.length / 2, len = (0, utils_ts_1.numberToHexUnpadded)(dataLen);
            if (len.length / 2 & 128)
              throw new E("tlv.encode: long form length too big");
            let lenLen = dataLen > 127 ? (0, utils_ts_1.numberToHexUnpadded)(len.length / 2 | 128) : "";
            return (0, utils_ts_1.numberToHexUnpadded)(tag) + lenLen + len + data;
          },
          // v - value, l - left bytes (unparsed)
          decode(tag, data) {
            let { Err: E } = exports.DER, pos = 0;
            if (tag < 0 || tag > 256)
              throw new E("tlv.encode: wrong tag");
            if (data.length < 2 || data[pos++] !== tag)
              throw new E("tlv.decode: wrong tlv");
            let first = data[pos++], isLong = !!(first & 128), length = 0;
            if (!isLong)
              length = first;
            else {
              let lenLen = first & 127;
              if (!lenLen)
                throw new E("tlv.decode(long): indefinite length not supported");
              if (lenLen > 4)
                throw new E("tlv.decode(long): byte length is too big");
              let lengthBytes = data.subarray(pos, pos + lenLen);
              if (lengthBytes.length !== lenLen)
                throw new E("tlv.decode: length bytes not complete");
              if (lengthBytes[0] === 0)
                throw new E("tlv.decode(long): zero leftmost byte");
              for (let b of lengthBytes)
                length = length << 8 | b;
              if (pos += lenLen, length < 128)
                throw new E("tlv.decode(long): not minimal encoding");
            }
            let v = data.subarray(pos, pos + length);
            if (v.length !== length)
              throw new E("tlv.decode: wrong value length");
            return { v, l: data.subarray(pos + length) };
          }
        },
        // https://crypto.stackexchange.com/a/57734 Leftmost bit of first byte is 'negative' flag,
        // since we always use positive integers here. It must always be empty:
        // - add zero byte if exists
        // - if next byte doesn't have a flag, leading zero is not allowed (minimal encoding)
        _int: {
          encode(num) {
            let { Err: E } = exports.DER;
            if (num < _0n)
              throw new E("integer: negative integers are not allowed");
            let hex = (0, utils_ts_1.numberToHexUnpadded)(num);
            if (Number.parseInt(hex[0], 16) & 8 && (hex = "00" + hex), hex.length & 1)
              throw new E("unexpected DER parsing assertion: unpadded hex");
            return hex;
          },
          decode(data) {
            let { Err: E } = exports.DER;
            if (data[0] & 128)
              throw new E("invalid signature integer: negative");
            if (data[0] === 0 && !(data[1] & 128))
              throw new E("invalid signature integer: unnecessary leading zero");
            return (0, utils_ts_1.bytesToNumberBE)(data);
          }
        },
        toSig(hex) {
          let { Err: E, _int: int, _tlv: tlv } = exports.DER, data = (0, utils_ts_1.ensureBytes)("signature", hex), { v: seqBytes, l: seqLeftBytes } = tlv.decode(48, data);
          if (seqLeftBytes.length)
            throw new E("invalid signature: left bytes after parsing");
          let { v: rBytes, l: rLeftBytes } = tlv.decode(2, seqBytes), { v: sBytes, l: sLeftBytes } = tlv.decode(2, rLeftBytes);
          if (sLeftBytes.length)
            throw new E("invalid signature: left bytes after parsing");
          return { r: int.decode(rBytes), s: int.decode(sBytes) };
        },
        hexFromSig(sig) {
          let { _tlv: tlv, _int: int } = exports.DER, rs = tlv.encode(2, int.encode(sig.r)), ss = tlv.encode(2, int.encode(sig.s)), seq = rs + ss;
          return tlv.encode(48, seq);
        }
      };
      var _0n = BigInt(0), _1n = BigInt(1), _2n = BigInt(2), _3n = BigInt(3), _4n = BigInt(4);
      function _normFnElement(Fn, key) {
        let { BYTES: expected } = Fn, num;
        if (typeof key == "bigint")
          num = key;
        else {
          let bytes = (0, utils_ts_1.ensureBytes)("private key", key);
          try {
            num = Fn.fromBytes(bytes);
          } catch {
            throw new Error(`invalid private key: expected ui8a of size ${expected}, got ${typeof key}`);
          }
        }
        if (!Fn.isValidNot0(num))
          throw new Error("invalid private key: out of range [1..N-1]");
        return num;
      }
      function weierstrassN(params, extraOpts = {}) {
        let validated = (0, curve_ts_1._createCurveFields)("weierstrass", params, extraOpts), { Fp, Fn } = validated, CURVE = validated.CURVE, { h: cofactor, n: CURVE_ORDER } = CURVE;
        (0, utils_ts_1._validateObject)(extraOpts, {}, {
          allowInfinityPoint: "boolean",
          clearCofactor: "function",
          isTorsionFree: "function",
          fromBytes: "function",
          toBytes: "function",
          endo: "object",
          wrapPrivateKey: "boolean"
        });
        let { endo } = extraOpts;
        if (endo && (!Fp.is0(CURVE.a) || typeof endo.beta != "bigint" || !Array.isArray(endo.basises)))
          throw new Error('invalid endo: expected "beta": bigint and "basises": array');
        let lengths = getWLengths(Fp, Fn);
        function assertCompressionIsSupported() {
          if (!Fp.isOdd)
            throw new Error("compression is not supported: Field does not have .isOdd()");
        }
        function pointToBytes(_c, point, isCompressed) {
          let { x, y } = point.toAffine(), bx = Fp.toBytes(x);
          if ((0, utils_ts_1._abool2)(isCompressed, "isCompressed"), isCompressed) {
            assertCompressionIsSupported();
            let hasEvenY = !Fp.isOdd(y);
            return (0, utils_ts_1.concatBytes)(pprefix(hasEvenY), bx);
          } else
            return (0, utils_ts_1.concatBytes)(Uint8Array.of(4), bx, Fp.toBytes(y));
        }
        function pointFromBytes(bytes) {
          (0, utils_ts_1._abytes2)(bytes, void 0, "Point");
          let { publicKey: comp, publicKeyUncompressed: uncomp } = lengths, length = bytes.length, head = bytes[0], tail = bytes.subarray(1);
          if (length === comp && (head === 2 || head === 3)) {
            let x = Fp.fromBytes(tail);
            if (!Fp.isValid(x))
              throw new Error("bad point: is not on curve, wrong x");
            let y2 = weierstrassEquation(x), y;
            try {
              y = Fp.sqrt(y2);
            } catch (sqrtError) {
              let err = sqrtError instanceof Error ? ": " + sqrtError.message : "";
              throw new Error("bad point: is not on curve, sqrt error" + err);
            }
            assertCompressionIsSupported();
            let isYOdd = Fp.isOdd(y);
            return (head & 1) === 1 !== isYOdd && (y = Fp.neg(y)), { x, y };
          } else if (length === uncomp && head === 4) {
            let L = Fp.BYTES, x = Fp.fromBytes(tail.subarray(0, L)), y = Fp.fromBytes(tail.subarray(L, L * 2));
            if (!isValidXY(x, y))
              throw new Error("bad point: is not on curve");
            return { x, y };
          } else
            throw new Error(`bad point: got length ${length}, expected compressed=${comp} or uncompressed=${uncomp}`);
        }
        let encodePoint = extraOpts.toBytes || pointToBytes, decodePoint = extraOpts.fromBytes || pointFromBytes;
        function weierstrassEquation(x) {
          let x2 = Fp.sqr(x), x3 = Fp.mul(x2, x);
          return Fp.add(Fp.add(x3, Fp.mul(x, CURVE.a)), CURVE.b);
        }
        function isValidXY(x, y) {
          let left = Fp.sqr(y), right = weierstrassEquation(x);
          return Fp.eql(left, right);
        }
        if (!isValidXY(CURVE.Gx, CURVE.Gy))
          throw new Error("bad curve params: generator point");
        let _4a3 = Fp.mul(Fp.pow(CURVE.a, _3n), _4n), _27b2 = Fp.mul(Fp.sqr(CURVE.b), BigInt(27));
        if (Fp.is0(Fp.add(_4a3, _27b2)))
          throw new Error("bad curve params: a or b");
        function acoord(title, n, banZero = !1) {
          if (!Fp.isValid(n) || banZero && Fp.is0(n))
            throw new Error(`bad point coordinate ${title}`);
          return n;
        }
        function aprjpoint(other) {
          if (!(other instanceof Point))
            throw new Error("ProjectivePoint expected");
        }
        function splitEndoScalarN(k) {
          if (!endo || !endo.basises)
            throw new Error("no endo");
          return _splitEndoScalar(k, endo.basises, Fn.ORDER);
        }
        let toAffineMemo = (0, utils_ts_1.memoized)((p, iz) => {
          let { X, Y, Z } = p;
          if (Fp.eql(Z, Fp.ONE))
            return { x: X, y: Y };
          let is0 = p.is0();
          iz == null && (iz = is0 ? Fp.ONE : Fp.inv(Z));
          let x = Fp.mul(X, iz), y = Fp.mul(Y, iz), zz = Fp.mul(Z, iz);
          if (is0)
            return { x: Fp.ZERO, y: Fp.ZERO };
          if (!Fp.eql(zz, Fp.ONE))
            throw new Error("invZ was invalid");
          return { x, y };
        }), assertValidMemo = (0, utils_ts_1.memoized)((p) => {
          if (p.is0()) {
            if (extraOpts.allowInfinityPoint && !Fp.is0(p.Y))
              return;
            throw new Error("bad point: ZERO");
          }
          let { x, y } = p.toAffine();
          if (!Fp.isValid(x) || !Fp.isValid(y))
            throw new Error("bad point: x or y not field elements");
          if (!isValidXY(x, y))
            throw new Error("bad point: equation left != right");
          if (!p.isTorsionFree())
            throw new Error("bad point: not in prime-order subgroup");
          return !0;
        });
        function finishEndo(endoBeta, k1p, k2p, k1neg, k2neg) {
          return k2p = new Point(Fp.mul(k2p.X, endoBeta), k2p.Y, k2p.Z), k1p = (0, curve_ts_1.negateCt)(k1neg, k1p), k2p = (0, curve_ts_1.negateCt)(k2neg, k2p), k1p.add(k2p);
        }
        class Point {
          /** Does NOT validate if the point is valid. Use `.assertValidity()`. */
          constructor(X, Y, Z) {
            this.X = acoord("x", X), this.Y = acoord("y", Y, !0), this.Z = acoord("z", Z), Object.freeze(this);
          }
          static CURVE() {
            return CURVE;
          }
          /** Does NOT validate if the point is valid. Use `.assertValidity()`. */
          static fromAffine(p) {
            let { x, y } = p || {};
            if (!p || !Fp.isValid(x) || !Fp.isValid(y))
              throw new Error("invalid affine point");
            if (p instanceof Point)
              throw new Error("projective point not allowed");
            return Fp.is0(x) && Fp.is0(y) ? Point.ZERO : new Point(x, y, Fp.ONE);
          }
          static fromBytes(bytes) {
            let P = Point.fromAffine(decodePoint((0, utils_ts_1._abytes2)(bytes, void 0, "point")));
            return P.assertValidity(), P;
          }
          static fromHex(hex) {
            return Point.fromBytes((0, utils_ts_1.ensureBytes)("pointHex", hex));
          }
          get x() {
            return this.toAffine().x;
          }
          get y() {
            return this.toAffine().y;
          }
          /**
           *
           * @param windowSize
           * @param isLazy true will defer table computation until the first multiplication
           * @returns
           */
          precompute(windowSize = 8, isLazy = !0) {
            return wnaf.createCache(this, windowSize), isLazy || this.multiply(_3n), this;
          }
          // TODO: return `this`
          /** A point on curve is valid if it conforms to equation. */
          assertValidity() {
            assertValidMemo(this);
          }
          hasEvenY() {
            let { y } = this.toAffine();
            if (!Fp.isOdd)
              throw new Error("Field doesn't support isOdd");
            return !Fp.isOdd(y);
          }
          /** Compare one point to another. */
          equals(other) {
            aprjpoint(other);
            let { X: X1, Y: Y1, Z: Z1 } = this, { X: X2, Y: Y2, Z: Z2 } = other, U1 = Fp.eql(Fp.mul(X1, Z2), Fp.mul(X2, Z1)), U2 = Fp.eql(Fp.mul(Y1, Z2), Fp.mul(Y2, Z1));
            return U1 && U2;
          }
          /** Flips point to one corresponding to (x, -y) in Affine coordinates. */
          negate() {
            return new Point(this.X, Fp.neg(this.Y), this.Z);
          }
          // Renes-Costello-Batina exception-free doubling formula.
          // There is 30% faster Jacobian formula, but it is not complete.
          // https://eprint.iacr.org/2015/1060, algorithm 3
          // Cost: 8M + 3S + 3*a + 2*b3 + 15add.
          double() {
            let { a, b } = CURVE, b3 = Fp.mul(b, _3n), { X: X1, Y: Y1, Z: Z1 } = this, X3 = Fp.ZERO, Y3 = Fp.ZERO, Z3 = Fp.ZERO, t0 = Fp.mul(X1, X1), t1 = Fp.mul(Y1, Y1), t2 = Fp.mul(Z1, Z1), t3 = Fp.mul(X1, Y1);
            return t3 = Fp.add(t3, t3), Z3 = Fp.mul(X1, Z1), Z3 = Fp.add(Z3, Z3), X3 = Fp.mul(a, Z3), Y3 = Fp.mul(b3, t2), Y3 = Fp.add(X3, Y3), X3 = Fp.sub(t1, Y3), Y3 = Fp.add(t1, Y3), Y3 = Fp.mul(X3, Y3), X3 = Fp.mul(t3, X3), Z3 = Fp.mul(b3, Z3), t2 = Fp.mul(a, t2), t3 = Fp.sub(t0, t2), t3 = Fp.mul(a, t3), t3 = Fp.add(t3, Z3), Z3 = Fp.add(t0, t0), t0 = Fp.add(Z3, t0), t0 = Fp.add(t0, t2), t0 = Fp.mul(t0, t3), Y3 = Fp.add(Y3, t0), t2 = Fp.mul(Y1, Z1), t2 = Fp.add(t2, t2), t0 = Fp.mul(t2, t3), X3 = Fp.sub(X3, t0), Z3 = Fp.mul(t2, t1), Z3 = Fp.add(Z3, Z3), Z3 = Fp.add(Z3, Z3), new Point(X3, Y3, Z3);
          }
          // Renes-Costello-Batina exception-free addition formula.
          // There is 30% faster Jacobian formula, but it is not complete.
          // https://eprint.iacr.org/2015/1060, algorithm 1
          // Cost: 12M + 0S + 3*a + 3*b3 + 23add.
          add(other) {
            aprjpoint(other);
            let { X: X1, Y: Y1, Z: Z1 } = this, { X: X2, Y: Y2, Z: Z2 } = other, X3 = Fp.ZERO, Y3 = Fp.ZERO, Z3 = Fp.ZERO, a = CURVE.a, b3 = Fp.mul(CURVE.b, _3n), t0 = Fp.mul(X1, X2), t1 = Fp.mul(Y1, Y2), t2 = Fp.mul(Z1, Z2), t3 = Fp.add(X1, Y1), t4 = Fp.add(X2, Y2);
            t3 = Fp.mul(t3, t4), t4 = Fp.add(t0, t1), t3 = Fp.sub(t3, t4), t4 = Fp.add(X1, Z1);
            let t5 = Fp.add(X2, Z2);
            return t4 = Fp.mul(t4, t5), t5 = Fp.add(t0, t2), t4 = Fp.sub(t4, t5), t5 = Fp.add(Y1, Z1), X3 = Fp.add(Y2, Z2), t5 = Fp.mul(t5, X3), X3 = Fp.add(t1, t2), t5 = Fp.sub(t5, X3), Z3 = Fp.mul(a, t4), X3 = Fp.mul(b3, t2), Z3 = Fp.add(X3, Z3), X3 = Fp.sub(t1, Z3), Z3 = Fp.add(t1, Z3), Y3 = Fp.mul(X3, Z3), t1 = Fp.add(t0, t0), t1 = Fp.add(t1, t0), t2 = Fp.mul(a, t2), t4 = Fp.mul(b3, t4), t1 = Fp.add(t1, t2), t2 = Fp.sub(t0, t2), t2 = Fp.mul(a, t2), t4 = Fp.add(t4, t2), t0 = Fp.mul(t1, t4), Y3 = Fp.add(Y3, t0), t0 = Fp.mul(t5, t4), X3 = Fp.mul(t3, X3), X3 = Fp.sub(X3, t0), t0 = Fp.mul(t3, t1), Z3 = Fp.mul(t5, Z3), Z3 = Fp.add(Z3, t0), new Point(X3, Y3, Z3);
          }
          subtract(other) {
            return this.add(other.negate());
          }
          is0() {
            return this.equals(Point.ZERO);
          }
          /**
           * Constant time multiplication.
           * Uses wNAF method. Windowed method may be 10% faster,
           * but takes 2x longer to generate and consumes 2x memory.
           * Uses precomputes when available.
           * Uses endomorphism for Koblitz curves.
           * @param scalar by which the point would be multiplied
           * @returns New point
           */
          multiply(scalar) {
            let { endo: endo2 } = extraOpts;
            if (!Fn.isValidNot0(scalar))
              throw new Error("invalid scalar: out of range");
            let point, fake, mul = (n) => wnaf.cached(this, n, (p) => (0, curve_ts_1.normalizeZ)(Point, p));
            if (endo2) {
              let { k1neg, k1, k2neg, k2 } = splitEndoScalarN(scalar), { p: k1p, f: k1f } = mul(k1), { p: k2p, f: k2f } = mul(k2);
              fake = k1f.add(k2f), point = finishEndo(endo2.beta, k1p, k2p, k1neg, k2neg);
            } else {
              let { p, f } = mul(scalar);
              point = p, fake = f;
            }
            return (0, curve_ts_1.normalizeZ)(Point, [point, fake])[0];
          }
          /**
           * Non-constant-time multiplication. Uses double-and-add algorithm.
           * It's faster, but should only be used when you don't care about
           * an exposed secret key e.g. sig verification, which works over *public* keys.
           */
          multiplyUnsafe(sc) {
            let { endo: endo2 } = extraOpts, p = this;
            if (!Fn.isValid(sc))
              throw new Error("invalid scalar: out of range");
            if (sc === _0n || p.is0())
              return Point.ZERO;
            if (sc === _1n)
              return p;
            if (wnaf.hasCache(this))
              return this.multiply(sc);
            if (endo2) {
              let { k1neg, k1, k2neg, k2 } = splitEndoScalarN(sc), { p1, p2 } = (0, curve_ts_1.mulEndoUnsafe)(Point, p, k1, k2);
              return finishEndo(endo2.beta, p1, p2, k1neg, k2neg);
            } else
              return wnaf.unsafe(p, sc);
          }
          multiplyAndAddUnsafe(Q, a, b) {
            let sum = this.multiplyUnsafe(a).add(Q.multiplyUnsafe(b));
            return sum.is0() ? void 0 : sum;
          }
          /**
           * Converts Projective point to affine (x, y) coordinates.
           * @param invertedZ Z^-1 (inverted zero) - optional, precomputation is useful for invertBatch
           */
          toAffine(invertedZ) {
            return toAffineMemo(this, invertedZ);
          }
          /**
           * Checks whether Point is free of torsion elements (is in prime subgroup).
           * Always torsion-free for cofactor=1 curves.
           */
          isTorsionFree() {
            let { isTorsionFree } = extraOpts;
            return cofactor === _1n ? !0 : isTorsionFree ? isTorsionFree(Point, this) : wnaf.unsafe(this, CURVE_ORDER).is0();
          }
          clearCofactor() {
            let { clearCofactor } = extraOpts;
            return cofactor === _1n ? this : clearCofactor ? clearCofactor(Point, this) : this.multiplyUnsafe(cofactor);
          }
          isSmallOrder() {
            return this.multiplyUnsafe(cofactor).is0();
          }
          toBytes(isCompressed = !0) {
            return (0, utils_ts_1._abool2)(isCompressed, "isCompressed"), this.assertValidity(), encodePoint(Point, this, isCompressed);
          }
          toHex(isCompressed = !0) {
            return (0, utils_ts_1.bytesToHex)(this.toBytes(isCompressed));
          }
          toString() {
            return `<Point ${this.is0() ? "ZERO" : this.toHex()}>`;
          }
          // TODO: remove
          get px() {
            return this.X;
          }
          get py() {
            return this.X;
          }
          get pz() {
            return this.Z;
          }
          toRawBytes(isCompressed = !0) {
            return this.toBytes(isCompressed);
          }
          _setWindowSize(windowSize) {
            this.precompute(windowSize);
          }
          static normalizeZ(points) {
            return (0, curve_ts_1.normalizeZ)(Point, points);
          }
          static msm(points, scalars) {
            return (0, curve_ts_1.pippenger)(Point, Fn, points, scalars);
          }
          static fromPrivateKey(privateKey) {
            return Point.BASE.multiply(_normFnElement(Fn, privateKey));
          }
        }
        Point.BASE = new Point(CURVE.Gx, CURVE.Gy, Fp.ONE), Point.ZERO = new Point(Fp.ZERO, Fp.ONE, Fp.ZERO), Point.Fp = Fp, Point.Fn = Fn;
        let bits = Fn.BITS, wnaf = new curve_ts_1.wNAF(Point, extraOpts.endo ? Math.ceil(bits / 2) : bits);
        return Point.BASE.precompute(8), Point;
      }
      function pprefix(hasEvenY) {
        return Uint8Array.of(hasEvenY ? 2 : 3);
      }
      function SWUFpSqrtRatio(Fp, Z) {
        let q = Fp.ORDER, l = _0n;
        for (let o = q - _1n; o % _2n === _0n; o /= _2n)
          l += _1n;
        let c1 = l, _2n_pow_c1_1 = _2n << c1 - _1n - _1n, _2n_pow_c1 = _2n_pow_c1_1 * _2n, c2 = (q - _1n) / _2n_pow_c1, c3 = (c2 - _1n) / _2n, c4 = _2n_pow_c1 - _1n, c5 = _2n_pow_c1_1, c6 = Fp.pow(Z, c2), c7 = Fp.pow(Z, (c2 + _1n) / _2n), sqrtRatio = (u, v) => {
          let tv1 = c6, tv2 = Fp.pow(v, c4), tv3 = Fp.sqr(tv2);
          tv3 = Fp.mul(tv3, v);
          let tv5 = Fp.mul(u, tv3);
          tv5 = Fp.pow(tv5, c3), tv5 = Fp.mul(tv5, tv2), tv2 = Fp.mul(tv5, v), tv3 = Fp.mul(tv5, u);
          let tv4 = Fp.mul(tv3, tv2);
          tv5 = Fp.pow(tv4, c5);
          let isQR = Fp.eql(tv5, Fp.ONE);
          tv2 = Fp.mul(tv3, c7), tv5 = Fp.mul(tv4, tv1), tv3 = Fp.cmov(tv2, tv3, isQR), tv4 = Fp.cmov(tv5, tv4, isQR);
          for (let i = c1; i > _1n; i--) {
            let tv52 = i - _2n;
            tv52 = _2n << tv52 - _1n;
            let tvv5 = Fp.pow(tv4, tv52), e1 = Fp.eql(tvv5, Fp.ONE);
            tv2 = Fp.mul(tv3, tv1), tv1 = Fp.mul(tv1, tv1), tvv5 = Fp.mul(tv4, tv1), tv3 = Fp.cmov(tv2, tv3, e1), tv4 = Fp.cmov(tvv5, tv4, e1);
          }
          return { isValid: isQR, value: tv3 };
        };
        if (Fp.ORDER % _4n === _3n) {
          let c12 = (Fp.ORDER - _3n) / _4n, c22 = Fp.sqrt(Fp.neg(Z));
          sqrtRatio = (u, v) => {
            let tv1 = Fp.sqr(v), tv2 = Fp.mul(u, v);
            tv1 = Fp.mul(tv1, tv2);
            let y1 = Fp.pow(tv1, c12);
            y1 = Fp.mul(y1, tv2);
            let y2 = Fp.mul(y1, c22), tv3 = Fp.mul(Fp.sqr(y1), v), isQR = Fp.eql(tv3, u), y = Fp.cmov(y2, y1, isQR);
            return { isValid: isQR, value: y };
          };
        }
        return sqrtRatio;
      }
      function mapToCurveSimpleSWU(Fp, opts) {
        (0, modular_ts_1.validateField)(Fp);
        let { A, B, Z } = opts;
        if (!Fp.isValid(A) || !Fp.isValid(B) || !Fp.isValid(Z))
          throw new Error("mapToCurveSimpleSWU: invalid opts");
        let sqrtRatio = SWUFpSqrtRatio(Fp, Z);
        if (!Fp.isOdd)
          throw new Error("Field does not have .isOdd()");
        return (u) => {
          let tv1, tv2, tv3, tv4, tv5, tv6, x, y;
          tv1 = Fp.sqr(u), tv1 = Fp.mul(tv1, Z), tv2 = Fp.sqr(tv1), tv2 = Fp.add(tv2, tv1), tv3 = Fp.add(tv2, Fp.ONE), tv3 = Fp.mul(tv3, B), tv4 = Fp.cmov(Z, Fp.neg(tv2), !Fp.eql(tv2, Fp.ZERO)), tv4 = Fp.mul(tv4, A), tv2 = Fp.sqr(tv3), tv6 = Fp.sqr(tv4), tv5 = Fp.mul(tv6, A), tv2 = Fp.add(tv2, tv5), tv2 = Fp.mul(tv2, tv3), tv6 = Fp.mul(tv6, tv4), tv5 = Fp.mul(tv6, B), tv2 = Fp.add(tv2, tv5), x = Fp.mul(tv1, tv3);
          let { isValid, value } = sqrtRatio(tv2, tv6);
          y = Fp.mul(tv1, u), y = Fp.mul(y, value), x = Fp.cmov(x, tv3, isValid), y = Fp.cmov(y, value, isValid);
          let e1 = Fp.isOdd(u) === Fp.isOdd(y);
          y = Fp.cmov(Fp.neg(y), y, e1);
          let tv4_inv = (0, modular_ts_1.FpInvertBatch)(Fp, [tv4], !0)[0];
          return x = Fp.mul(x, tv4_inv), { x, y };
        };
      }
      function getWLengths(Fp, Fn) {
        return {
          secretKey: Fn.BYTES,
          publicKey: 1 + Fp.BYTES,
          publicKeyUncompressed: 1 + 2 * Fp.BYTES,
          publicKeyHasPrefix: !0,
          signature: 2 * Fn.BYTES
        };
      }
      function ecdh(Point, ecdhOpts = {}) {
        let { Fn } = Point, randomBytes_ = ecdhOpts.randomBytes || utils_ts_1.randomBytes, lengths = Object.assign(getWLengths(Point.Fp, Fn), { seed: (0, modular_ts_1.getMinHashLength)(Fn.ORDER) });
        function isValidSecretKey(secretKey) {
          try {
            return !!_normFnElement(Fn, secretKey);
          } catch {
            return !1;
          }
        }
        function isValidPublicKey(publicKey, isCompressed) {
          let { publicKey: comp, publicKeyUncompressed } = lengths;
          try {
            let l = publicKey.length;
            return isCompressed === !0 && l !== comp || isCompressed === !1 && l !== publicKeyUncompressed ? !1 : !!Point.fromBytes(publicKey);
          } catch {
            return !1;
          }
        }
        function randomSecretKey(seed = randomBytes_(lengths.seed)) {
          return (0, modular_ts_1.mapHashToField)((0, utils_ts_1._abytes2)(seed, lengths.seed, "seed"), Fn.ORDER);
        }
        function getPublicKey(secretKey, isCompressed = !0) {
          return Point.BASE.multiply(_normFnElement(Fn, secretKey)).toBytes(isCompressed);
        }
        function keygen(seed) {
          let secretKey = randomSecretKey(seed);
          return { secretKey, publicKey: getPublicKey(secretKey) };
        }
        function isProbPub(item) {
          if (typeof item == "bigint")
            return !1;
          if (item instanceof Point)
            return !0;
          let { secretKey, publicKey, publicKeyUncompressed } = lengths;
          if (Fn.allowedLengths || secretKey === publicKey)
            return;
          let l = (0, utils_ts_1.ensureBytes)("key", item).length;
          return l === publicKey || l === publicKeyUncompressed;
        }
        function getSharedSecret(secretKeyA, publicKeyB, isCompressed = !0) {
          if (isProbPub(secretKeyA) === !0)
            throw new Error("first arg must be private key");
          if (isProbPub(publicKeyB) === !1)
            throw new Error("second arg must be public key");
          let s = _normFnElement(Fn, secretKeyA);
          return Point.fromHex(publicKeyB).multiply(s).toBytes(isCompressed);
        }
        return Object.freeze({ getPublicKey, getSharedSecret, keygen, Point, utils: {
          isValidSecretKey,
          isValidPublicKey,
          randomSecretKey,
          // TODO: remove
          isValidPrivateKey: isValidSecretKey,
          randomPrivateKey: randomSecretKey,
          normPrivateKeyToScalar: (key) => _normFnElement(Fn, key),
          precompute(windowSize = 8, point = Point.BASE) {
            return point.precompute(windowSize, !1);
          }
        }, lengths });
      }
      function ecdsa(Point, hash, ecdsaOpts = {}) {
        (0, utils_1.ahash)(hash), (0, utils_ts_1._validateObject)(ecdsaOpts, {}, {
          hmac: "function",
          lowS: "boolean",
          randomBytes: "function",
          bits2int: "function",
          bits2int_modN: "function"
        });
        let randomBytes = ecdsaOpts.randomBytes || utils_ts_1.randomBytes, hmac = ecdsaOpts.hmac || ((key, ...msgs) => (0, hmac_js_1.hmac)(hash, key, (0, utils_ts_1.concatBytes)(...msgs))), { Fp, Fn } = Point, { ORDER: CURVE_ORDER, BITS: fnBits } = Fn, { keygen, getPublicKey, getSharedSecret, utils, lengths } = ecdh(Point, ecdsaOpts), defaultSigOpts = {
          prehash: !1,
          lowS: typeof ecdsaOpts.lowS == "boolean" ? ecdsaOpts.lowS : !1,
          format: void 0,
          //'compact' as ECDSASigFormat,
          extraEntropy: !1
        }, defaultSigOpts_format = "compact";
        function isBiggerThanHalfOrder(number) {
          let HALF = CURVE_ORDER >> _1n;
          return number > HALF;
        }
        function validateRS(title, num) {
          if (!Fn.isValidNot0(num))
            throw new Error(`invalid signature ${title}: out of range 1..Point.Fn.ORDER`);
          return num;
        }
        function validateSigLength(bytes, format) {
          validateSigFormat(format);
          let size = lengths.signature, sizer = format === "compact" ? size : format === "recovered" ? size + 1 : void 0;
          return (0, utils_ts_1._abytes2)(bytes, sizer, `${format} signature`);
        }
        class Signature {
          constructor(r, s, recovery) {
            this.r = validateRS("r", r), this.s = validateRS("s", s), recovery != null && (this.recovery = recovery), Object.freeze(this);
          }
          static fromBytes(bytes, format = defaultSigOpts_format) {
            validateSigLength(bytes, format);
            let recid;
            if (format === "der") {
              let { r: r2, s: s2 } = exports.DER.toSig((0, utils_ts_1._abytes2)(bytes));
              return new Signature(r2, s2);
            }
            format === "recovered" && (recid = bytes[0], format = "compact", bytes = bytes.subarray(1));
            let L = Fn.BYTES, r = bytes.subarray(0, L), s = bytes.subarray(L, L * 2);
            return new Signature(Fn.fromBytes(r), Fn.fromBytes(s), recid);
          }
          static fromHex(hex, format) {
            return this.fromBytes((0, utils_ts_1.hexToBytes)(hex), format);
          }
          addRecoveryBit(recovery) {
            return new Signature(this.r, this.s, recovery);
          }
          recoverPublicKey(messageHash) {
            let FIELD_ORDER = Fp.ORDER, { r, s, recovery: rec } = this;
            if (rec == null || ![0, 1, 2, 3].includes(rec))
              throw new Error("recovery id invalid");
            if (CURVE_ORDER * _2n < FIELD_ORDER && rec > 1)
              throw new Error("recovery id is ambiguous for h>1 curve");
            let radj = rec === 2 || rec === 3 ? r + CURVE_ORDER : r;
            if (!Fp.isValid(radj))
              throw new Error("recovery id 2 or 3 invalid");
            let x = Fp.toBytes(radj), R = Point.fromBytes((0, utils_ts_1.concatBytes)(pprefix((rec & 1) === 0), x)), ir = Fn.inv(radj), h = bits2int_modN((0, utils_ts_1.ensureBytes)("msgHash", messageHash)), u1 = Fn.create(-h * ir), u2 = Fn.create(s * ir), Q = Point.BASE.multiplyUnsafe(u1).add(R.multiplyUnsafe(u2));
            if (Q.is0())
              throw new Error("point at infinify");
            return Q.assertValidity(), Q;
          }
          // Signatures should be low-s, to prevent malleability.
          hasHighS() {
            return isBiggerThanHalfOrder(this.s);
          }
          toBytes(format = defaultSigOpts_format) {
            if (validateSigFormat(format), format === "der")
              return (0, utils_ts_1.hexToBytes)(exports.DER.hexFromSig(this));
            let r = Fn.toBytes(this.r), s = Fn.toBytes(this.s);
            if (format === "recovered") {
              if (this.recovery == null)
                throw new Error("recovery bit must be present");
              return (0, utils_ts_1.concatBytes)(Uint8Array.of(this.recovery), r, s);
            }
            return (0, utils_ts_1.concatBytes)(r, s);
          }
          toHex(format) {
            return (0, utils_ts_1.bytesToHex)(this.toBytes(format));
          }
          // TODO: remove
          assertValidity() {
          }
          static fromCompact(hex) {
            return Signature.fromBytes((0, utils_ts_1.ensureBytes)("sig", hex), "compact");
          }
          static fromDER(hex) {
            return Signature.fromBytes((0, utils_ts_1.ensureBytes)("sig", hex), "der");
          }
          normalizeS() {
            return this.hasHighS() ? new Signature(this.r, Fn.neg(this.s), this.recovery) : this;
          }
          toDERRawBytes() {
            return this.toBytes("der");
          }
          toDERHex() {
            return (0, utils_ts_1.bytesToHex)(this.toBytes("der"));
          }
          toCompactRawBytes() {
            return this.toBytes("compact");
          }
          toCompactHex() {
            return (0, utils_ts_1.bytesToHex)(this.toBytes("compact"));
          }
        }
        let bits2int = ecdsaOpts.bits2int || function(bytes) {
          if (bytes.length > 8192)
            throw new Error("input is too large");
          let num = (0, utils_ts_1.bytesToNumberBE)(bytes), delta = bytes.length * 8 - fnBits;
          return delta > 0 ? num >> BigInt(delta) : num;
        }, bits2int_modN = ecdsaOpts.bits2int_modN || function(bytes) {
          return Fn.create(bits2int(bytes));
        }, ORDER_MASK = (0, utils_ts_1.bitMask)(fnBits);
        function int2octets(num) {
          return (0, utils_ts_1.aInRange)("num < 2^" + fnBits, num, _0n, ORDER_MASK), Fn.toBytes(num);
        }
        function validateMsgAndHash(message, prehash) {
          return (0, utils_ts_1._abytes2)(message, void 0, "message"), prehash ? (0, utils_ts_1._abytes2)(hash(message), void 0, "prehashed message") : message;
        }
        function prepSig(message, privateKey, opts) {
          if (["recovered", "canonical"].some((k) => k in opts))
            throw new Error("sign() legacy options not supported");
          let { lowS, prehash, extraEntropy } = validateSigOpts(opts, defaultSigOpts);
          message = validateMsgAndHash(message, prehash);
          let h1int = bits2int_modN(message), d = _normFnElement(Fn, privateKey), seedArgs = [int2octets(d), int2octets(h1int)];
          if (extraEntropy != null && extraEntropy !== !1) {
            let e = extraEntropy === !0 ? randomBytes(lengths.secretKey) : extraEntropy;
            seedArgs.push((0, utils_ts_1.ensureBytes)("extraEntropy", e));
          }
          let seed = (0, utils_ts_1.concatBytes)(...seedArgs), m = h1int;
          function k2sig(kBytes) {
            let k = bits2int(kBytes);
            if (!Fn.isValidNot0(k))
              return;
            let ik = Fn.inv(k), q = Point.BASE.multiply(k).toAffine(), r = Fn.create(q.x);
            if (r === _0n)
              return;
            let s = Fn.create(ik * Fn.create(m + r * d));
            if (s === _0n)
              return;
            let recovery = (q.x === r ? 0 : 2) | Number(q.y & _1n), normS = s;
            return lowS && isBiggerThanHalfOrder(s) && (normS = Fn.neg(s), recovery ^= 1), new Signature(r, normS, recovery);
          }
          return { seed, k2sig };
        }
        function sign(message, secretKey, opts = {}) {
          message = (0, utils_ts_1.ensureBytes)("message", message);
          let { seed, k2sig } = prepSig(message, secretKey, opts);
          return (0, utils_ts_1.createHmacDrbg)(hash.outputLen, Fn.BYTES, hmac)(seed, k2sig);
        }
        function tryParsingSig(sg) {
          let sig, isHex = typeof sg == "string" || (0, utils_ts_1.isBytes)(sg), isObj = !isHex && sg !== null && typeof sg == "object" && typeof sg.r == "bigint" && typeof sg.s == "bigint";
          if (!isHex && !isObj)
            throw new Error("invalid signature, expected Uint8Array, hex string or Signature instance");
          if (isObj)
            sig = new Signature(sg.r, sg.s);
          else if (isHex) {
            try {
              sig = Signature.fromBytes((0, utils_ts_1.ensureBytes)("sig", sg), "der");
            } catch (derError) {
              if (!(derError instanceof exports.DER.Err))
                throw derError;
            }
            if (!sig)
              try {
                sig = Signature.fromBytes((0, utils_ts_1.ensureBytes)("sig", sg), "compact");
              } catch {
                return !1;
              }
          }
          return sig || !1;
        }
        function verify2(signature, message, publicKey, opts = {}) {
          let { lowS, prehash, format } = validateSigOpts(opts, defaultSigOpts);
          if (publicKey = (0, utils_ts_1.ensureBytes)("publicKey", publicKey), message = validateMsgAndHash((0, utils_ts_1.ensureBytes)("message", message), prehash), "strict" in opts)
            throw new Error("options.strict was renamed to lowS");
          let sig = format === void 0 ? tryParsingSig(signature) : Signature.fromBytes((0, utils_ts_1.ensureBytes)("sig", signature), format);
          if (sig === !1)
            return !1;
          try {
            let P = Point.fromBytes(publicKey);
            if (lowS && sig.hasHighS())
              return !1;
            let { r, s } = sig, h = bits2int_modN(message), is = Fn.inv(s), u1 = Fn.create(h * is), u2 = Fn.create(r * is), R = Point.BASE.multiplyUnsafe(u1).add(P.multiplyUnsafe(u2));
            return R.is0() ? !1 : Fn.create(R.x) === r;
          } catch {
            return !1;
          }
        }
        function recoverPublicKey(signature, message, opts = {}) {
          let { prehash } = validateSigOpts(opts, defaultSigOpts);
          return message = validateMsgAndHash(message, prehash), Signature.fromBytes(signature, "recovered").recoverPublicKey(message).toBytes();
        }
        return Object.freeze({
          keygen,
          getPublicKey,
          getSharedSecret,
          utils,
          lengths,
          Point,
          sign,
          verify: verify2,
          recoverPublicKey,
          Signature,
          hash
        });
      }
      function weierstrassPoints(c) {
        let { CURVE, curveOpts } = _weierstrass_legacy_opts_to_new(c), Point = weierstrassN(CURVE, curveOpts);
        return _weierstrass_new_output_to_legacy(c, Point);
      }
      function _weierstrass_legacy_opts_to_new(c) {
        let CURVE = {
          a: c.a,
          b: c.b,
          p: c.Fp.ORDER,
          n: c.n,
          h: c.h,
          Gx: c.Gx,
          Gy: c.Gy
        }, Fp = c.Fp, allowedLengths = c.allowedPrivateKeyLengths ? Array.from(new Set(c.allowedPrivateKeyLengths.map((l) => Math.ceil(l / 2)))) : void 0, Fn = (0, modular_ts_1.Field)(CURVE.n, {
          BITS: c.nBitLength,
          allowedLengths,
          modFromBytes: c.wrapPrivateKey
        }), curveOpts = {
          Fp,
          Fn,
          allowInfinityPoint: c.allowInfinityPoint,
          endo: c.endo,
          isTorsionFree: c.isTorsionFree,
          clearCofactor: c.clearCofactor,
          fromBytes: c.fromBytes,
          toBytes: c.toBytes
        };
        return { CURVE, curveOpts };
      }
      function _ecdsa_legacy_opts_to_new(c) {
        let { CURVE, curveOpts } = _weierstrass_legacy_opts_to_new(c), ecdsaOpts = {
          hmac: c.hmac,
          randomBytes: c.randomBytes,
          lowS: c.lowS,
          bits2int: c.bits2int,
          bits2int_modN: c.bits2int_modN
        };
        return { CURVE, curveOpts, hash: c.hash, ecdsaOpts };
      }
      function _legacyHelperEquat(Fp, a, b) {
        function weierstrassEquation(x) {
          let x2 = Fp.sqr(x), x3 = Fp.mul(x2, x);
          return Fp.add(Fp.add(x3, Fp.mul(x, a)), b);
        }
        return weierstrassEquation;
      }
      function _weierstrass_new_output_to_legacy(c, Point) {
        let { Fp, Fn } = Point;
        function isWithinCurveOrder(num) {
          return (0, utils_ts_1.inRange)(num, _1n, Fn.ORDER);
        }
        let weierstrassEquation = _legacyHelperEquat(Fp, c.a, c.b);
        return Object.assign({}, {
          CURVE: c,
          Point,
          ProjectivePoint: Point,
          normPrivateKeyToScalar: (key) => _normFnElement(Fn, key),
          weierstrassEquation,
          isWithinCurveOrder
        });
      }
      function _ecdsa_new_output_to_legacy(c, _ecdsa) {
        let Point = _ecdsa.Point;
        return Object.assign({}, _ecdsa, {
          ProjectivePoint: Point,
          CURVE: Object.assign({}, c, (0, modular_ts_1.nLength)(Point.Fn.ORDER, Point.Fn.BITS))
        });
      }
      function weierstrass(c) {
        let { CURVE, curveOpts, hash, ecdsaOpts } = _ecdsa_legacy_opts_to_new(c), Point = weierstrassN(CURVE, curveOpts), signs = ecdsa(Point, hash, ecdsaOpts);
        return _ecdsa_new_output_to_legacy(c, signs);
      }
    }
  });

  // node_modules/@noble/curves/_shortw_utils.js
  var require_shortw_utils = __commonJS({
    "node_modules/@noble/curves/_shortw_utils.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      exports.getHash = getHash;
      exports.createCurve = createCurve;
      var weierstrass_ts_1 = require_weierstrass();
      function getHash(hash) {
        return { hash };
      }
      function createCurve(curveDef, defHash) {
        let create = (hash) => (0, weierstrass_ts_1.weierstrass)({ ...curveDef, hash });
        return { ...create(defHash), create };
      }
    }
  });

  // node_modules/@noble/curves/abstract/hash-to-curve.js
  var require_hash_to_curve = __commonJS({
    "node_modules/@noble/curves/abstract/hash-to-curve.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      exports._DST_scalar = void 0;
      exports.expand_message_xmd = expand_message_xmd;
      exports.expand_message_xof = expand_message_xof;
      exports.hash_to_field = hash_to_field;
      exports.isogenyMap = isogenyMap;
      exports.createHasher = createHasher;
      var utils_ts_1 = require_utils3(), modular_ts_1 = require_modular(), os2ip = utils_ts_1.bytesToNumberBE;
      function i2osp(value, length) {
        if (anum(value), anum(length), value < 0 || value >= 1 << 8 * length)
          throw new Error("invalid I2OSP input: " + value);
        let res = Array.from({ length }).fill(0);
        for (let i = length - 1; i >= 0; i--)
          res[i] = value & 255, value >>>= 8;
        return new Uint8Array(res);
      }
      function strxor(a, b) {
        let arr = new Uint8Array(a.length);
        for (let i = 0; i < a.length; i++)
          arr[i] = a[i] ^ b[i];
        return arr;
      }
      function anum(item) {
        if (!Number.isSafeInteger(item))
          throw new Error("number expected");
      }
      function normDST(DST) {
        if (!(0, utils_ts_1.isBytes)(DST) && typeof DST != "string")
          throw new Error("DST must be Uint8Array or string");
        return typeof DST == "string" ? (0, utils_ts_1.utf8ToBytes)(DST) : DST;
      }
      function expand_message_xmd(msg, DST, lenInBytes, H) {
        (0, utils_ts_1.abytes)(msg), anum(lenInBytes), DST = normDST(DST), DST.length > 255 && (DST = H((0, utils_ts_1.concatBytes)((0, utils_ts_1.utf8ToBytes)("H2C-OVERSIZE-DST-"), DST)));
        let { outputLen: b_in_bytes, blockLen: r_in_bytes } = H, ell = Math.ceil(lenInBytes / b_in_bytes);
        if (lenInBytes > 65535 || ell > 255)
          throw new Error("expand_message_xmd: invalid lenInBytes");
        let DST_prime = (0, utils_ts_1.concatBytes)(DST, i2osp(DST.length, 1)), Z_pad = i2osp(0, r_in_bytes), l_i_b_str = i2osp(lenInBytes, 2), b = new Array(ell), b_0 = H((0, utils_ts_1.concatBytes)(Z_pad, msg, l_i_b_str, i2osp(0, 1), DST_prime));
        b[0] = H((0, utils_ts_1.concatBytes)(b_0, i2osp(1, 1), DST_prime));
        for (let i = 1; i <= ell; i++) {
          let args = [strxor(b_0, b[i - 1]), i2osp(i + 1, 1), DST_prime];
          b[i] = H((0, utils_ts_1.concatBytes)(...args));
        }
        return (0, utils_ts_1.concatBytes)(...b).slice(0, lenInBytes);
      }
      function expand_message_xof(msg, DST, lenInBytes, k, H) {
        if ((0, utils_ts_1.abytes)(msg), anum(lenInBytes), DST = normDST(DST), DST.length > 255) {
          let dkLen = Math.ceil(2 * k / 8);
          DST = H.create({ dkLen }).update((0, utils_ts_1.utf8ToBytes)("H2C-OVERSIZE-DST-")).update(DST).digest();
        }
        if (lenInBytes > 65535 || DST.length > 255)
          throw new Error("expand_message_xof: invalid lenInBytes");
        return H.create({ dkLen: lenInBytes }).update(msg).update(i2osp(lenInBytes, 2)).update(DST).update(i2osp(DST.length, 1)).digest();
      }
      function hash_to_field(msg, count, options) {
        (0, utils_ts_1._validateObject)(options, {
          p: "bigint",
          m: "number",
          k: "number",
          hash: "function"
        });
        let { p, k, m, hash, expand, DST } = options;
        if (!(0, utils_ts_1.isHash)(options.hash))
          throw new Error("expected valid hash");
        (0, utils_ts_1.abytes)(msg), anum(count);
        let log2p = p.toString(2).length, L = Math.ceil((log2p + k) / 8), len_in_bytes = count * m * L, prb;
        if (expand === "xmd")
          prb = expand_message_xmd(msg, DST, len_in_bytes, hash);
        else if (expand === "xof")
          prb = expand_message_xof(msg, DST, len_in_bytes, k, hash);
        else if (expand === "_internal_pass")
          prb = msg;
        else
          throw new Error('expand must be "xmd" or "xof"');
        let u = new Array(count);
        for (let i = 0; i < count; i++) {
          let e = new Array(m);
          for (let j = 0; j < m; j++) {
            let elm_offset = L * (j + i * m), tv = prb.subarray(elm_offset, elm_offset + L);
            e[j] = (0, modular_ts_1.mod)(os2ip(tv), p);
          }
          u[i] = e;
        }
        return u;
      }
      function isogenyMap(field, map) {
        let coeff = map.map((i) => Array.from(i).reverse());
        return (x, y) => {
          let [xn, xd, yn, yd] = coeff.map((val) => val.reduce((acc, i) => field.add(field.mul(acc, x), i))), [xd_inv, yd_inv] = (0, modular_ts_1.FpInvertBatch)(field, [xd, yd], !0);
          return x = field.mul(xn, xd_inv), y = field.mul(y, field.mul(yn, yd_inv)), { x, y };
        };
      }
      exports._DST_scalar = (0, utils_ts_1.utf8ToBytes)("HashToScalar-");
      function createHasher(Point, mapToCurve, defaults) {
        if (typeof mapToCurve != "function")
          throw new Error("mapToCurve() must be defined");
        function map(num) {
          return Point.fromAffine(mapToCurve(num));
        }
        function clear(initial) {
          let P = initial.clearCofactor();
          return P.equals(Point.ZERO) ? Point.ZERO : (P.assertValidity(), P);
        }
        return {
          defaults,
          hashToCurve(msg, options) {
            let opts = Object.assign({}, defaults, options), u = hash_to_field(msg, 2, opts), u0 = map(u[0]), u1 = map(u[1]);
            return clear(u0.add(u1));
          },
          encodeToCurve(msg, options) {
            let optsDst = defaults.encodeDST ? { DST: defaults.encodeDST } : {}, opts = Object.assign({}, defaults, optsDst, options), u = hash_to_field(msg, 1, opts), u0 = map(u[0]);
            return clear(u0);
          },
          /** See {@link H2CHasher} */
          mapToCurve(scalars) {
            if (!Array.isArray(scalars))
              throw new Error("expected array of bigints");
            for (let i of scalars)
              if (typeof i != "bigint")
                throw new Error("expected array of bigints");
            return clear(map(scalars));
          },
          // hash_to_scalar can produce 0: https://www.rfc-editor.org/errata/eid8393
          // RFC 9380, draft-irtf-cfrg-bbs-signatures-08
          hashToScalar(msg, options) {
            let N = Point.Fn.ORDER, opts = Object.assign({}, defaults, { p: N, m: 1, DST: exports._DST_scalar }, options);
            return hash_to_field(msg, 1, opts)[0][0];
          }
        };
      }
    }
  });

  // node_modules/@noble/curves/secp256k1.js
  var require_secp256k1 = __commonJS({
    "node_modules/@noble/curves/secp256k1.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      exports.encodeToCurve = exports.hashToCurve = exports.secp256k1_hasher = exports.schnorr = exports.secp256k1 = void 0;
      var sha2_js_1 = require_sha2(), utils_js_1 = require_utils(), _shortw_utils_ts_1 = require_shortw_utils(), hash_to_curve_ts_1 = require_hash_to_curve(), modular_ts_1 = require_modular(), weierstrass_ts_1 = require_weierstrass(), utils_ts_1 = require_utils3(), secp256k1_CURVE = {
        p: BigInt("0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffefffffc2f"),
        n: BigInt("0xfffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141"),
        h: BigInt(1),
        a: BigInt(0),
        b: BigInt(7),
        Gx: BigInt("0x79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"),
        Gy: BigInt("0x483ada7726a3c4655da4fbfc0e1108a8fd17b448a68554199c47d08ffb10d4b8")
      }, secp256k1_ENDO = {
        beta: BigInt("0x7ae96a2b657c07106e64479eac3434e99cf0497512f58995c1396c28719501ee"),
        basises: [
          [BigInt("0x3086d221a7d46bcde86c90e49284eb15"), -BigInt("0xe4437ed6010e88286f547fa90abfe4c3")],
          [BigInt("0x114ca50f7a8e2f3f657c1108d9d44cfd8"), BigInt("0x3086d221a7d46bcde86c90e49284eb15")]
        ]
      }, _0n = /* @__PURE__ */ BigInt(0), _1n = /* @__PURE__ */ BigInt(1), _2n = /* @__PURE__ */ BigInt(2);
      function sqrtMod(y) {
        let P = secp256k1_CURVE.p, _3n = BigInt(3), _6n = BigInt(6), _11n = BigInt(11), _22n = BigInt(22), _23n = BigInt(23), _44n = BigInt(44), _88n = BigInt(88), b2 = y * y * y % P, b3 = b2 * b2 * y % P, b6 = (0, modular_ts_1.pow2)(b3, _3n, P) * b3 % P, b9 = (0, modular_ts_1.pow2)(b6, _3n, P) * b3 % P, b11 = (0, modular_ts_1.pow2)(b9, _2n, P) * b2 % P, b22 = (0, modular_ts_1.pow2)(b11, _11n, P) * b11 % P, b44 = (0, modular_ts_1.pow2)(b22, _22n, P) * b22 % P, b88 = (0, modular_ts_1.pow2)(b44, _44n, P) * b44 % P, b176 = (0, modular_ts_1.pow2)(b88, _88n, P) * b88 % P, b220 = (0, modular_ts_1.pow2)(b176, _44n, P) * b44 % P, b223 = (0, modular_ts_1.pow2)(b220, _3n, P) * b3 % P, t1 = (0, modular_ts_1.pow2)(b223, _23n, P) * b22 % P, t2 = (0, modular_ts_1.pow2)(t1, _6n, P) * b2 % P, root = (0, modular_ts_1.pow2)(t2, _2n, P);
        if (!Fpk1.eql(Fpk1.sqr(root), y))
          throw new Error("Cannot find square root");
        return root;
      }
      var Fpk1 = (0, modular_ts_1.Field)(secp256k1_CURVE.p, { sqrt: sqrtMod });
      exports.secp256k1 = (0, _shortw_utils_ts_1.createCurve)({ ...secp256k1_CURVE, Fp: Fpk1, lowS: !0, endo: secp256k1_ENDO }, sha2_js_1.sha256);
      var TAGGED_HASH_PREFIXES = {};
      function taggedHash(tag, ...messages) {
        let tagP = TAGGED_HASH_PREFIXES[tag];
        if (tagP === void 0) {
          let tagH = (0, sha2_js_1.sha256)((0, utils_ts_1.utf8ToBytes)(tag));
          tagP = (0, utils_ts_1.concatBytes)(tagH, tagH), TAGGED_HASH_PREFIXES[tag] = tagP;
        }
        return (0, sha2_js_1.sha256)((0, utils_ts_1.concatBytes)(tagP, ...messages));
      }
      var pointToBytes = (point) => point.toBytes(!0).slice(1), Pointk1 = exports.secp256k1.Point, hasEven = (y) => y % _2n === _0n;
      function schnorrGetExtPubKey(priv) {
        let { Fn, BASE } = Pointk1, d_ = (0, weierstrass_ts_1._normFnElement)(Fn, priv), p = BASE.multiply(d_);
        return { scalar: hasEven(p.y) ? d_ : Fn.neg(d_), bytes: pointToBytes(p) };
      }
      function lift_x(x) {
        let Fp = Fpk1;
        if (!Fp.isValidNot0(x))
          throw new Error("invalid x: Fail if x \u2265 p");
        let xx = Fp.create(x * x), c = Fp.create(xx * x + BigInt(7)), y = Fp.sqrt(c);
        hasEven(y) || (y = Fp.neg(y));
        let p = Pointk1.fromAffine({ x, y });
        return p.assertValidity(), p;
      }
      var num = utils_ts_1.bytesToNumberBE;
      function challenge(...args) {
        return Pointk1.Fn.create(num(taggedHash("BIP0340/challenge", ...args)));
      }
      function schnorrGetPublicKey(secretKey) {
        return schnorrGetExtPubKey(secretKey).bytes;
      }
      function schnorrSign(message, secretKey, auxRand = (0, utils_js_1.randomBytes)(32)) {
        let { Fn } = Pointk1, m = (0, utils_ts_1.ensureBytes)("message", message), { bytes: px, scalar: d } = schnorrGetExtPubKey(secretKey), a = (0, utils_ts_1.ensureBytes)("auxRand", auxRand, 32), t = Fn.toBytes(d ^ num(taggedHash("BIP0340/aux", a))), rand = taggedHash("BIP0340/nonce", t, px, m), { bytes: rx, scalar: k } = schnorrGetExtPubKey(rand), e = challenge(rx, px, m), sig = new Uint8Array(64);
        if (sig.set(rx, 0), sig.set(Fn.toBytes(Fn.create(k + e * d)), 32), !schnorrVerify(sig, m, px))
          throw new Error("sign: Invalid signature produced");
        return sig;
      }
      function schnorrVerify(signature, message, publicKey) {
        let { Fn, BASE } = Pointk1, sig = (0, utils_ts_1.ensureBytes)("signature", signature, 64), m = (0, utils_ts_1.ensureBytes)("message", message), pub = (0, utils_ts_1.ensureBytes)("publicKey", publicKey, 32);
        try {
          let P = lift_x(num(pub)), r = num(sig.subarray(0, 32));
          if (!(0, utils_ts_1.inRange)(r, _1n, secp256k1_CURVE.p))
            return !1;
          let s = num(sig.subarray(32, 64));
          if (!(0, utils_ts_1.inRange)(s, _1n, secp256k1_CURVE.n))
            return !1;
          let e = challenge(Fn.toBytes(r), pointToBytes(P), m), R = BASE.multiplyUnsafe(s).add(P.multiplyUnsafe(Fn.neg(e))), { x, y } = R.toAffine();
          return !(R.is0() || !hasEven(y) || x !== r);
        } catch {
          return !1;
        }
      }
      exports.schnorr = (() => {
        let randomSecretKey = (seed = (0, utils_js_1.randomBytes)(48)) => (0, modular_ts_1.mapHashToField)(seed, secp256k1_CURVE.n);
        exports.secp256k1.utils.randomSecretKey;
        function keygen(seed) {
          let secretKey = randomSecretKey(seed);
          return { secretKey, publicKey: schnorrGetPublicKey(secretKey) };
        }
        return {
          keygen,
          getPublicKey: schnorrGetPublicKey,
          sign: schnorrSign,
          verify: schnorrVerify,
          Point: Pointk1,
          utils: {
            randomSecretKey,
            randomPrivateKey: randomSecretKey,
            taggedHash,
            // TODO: remove
            lift_x,
            pointToBytes,
            numberToBytesBE: utils_ts_1.numberToBytesBE,
            bytesToNumberBE: utils_ts_1.bytesToNumberBE,
            mod: modular_ts_1.mod
          },
          lengths: {
            secretKey: 32,
            publicKey: 32,
            publicKeyHasPrefix: !1,
            signature: 64,
            seed: 48
          }
        };
      })();
      var isoMap = (0, hash_to_curve_ts_1.isogenyMap)(Fpk1, [
        // xNum
        [
          "0x8e38e38e38e38e38e38e38e38e38e38e38e38e38e38e38e38e38e38daaaaa8c7",
          "0x7d3d4c80bc321d5b9f315cea7fd44c5d595d2fc0bf63b92dfff1044f17c6581",
          "0x534c328d23f234e6e2a413deca25caece4506144037c40314ecbd0b53d9dd262",
          "0x8e38e38e38e38e38e38e38e38e38e38e38e38e38e38e38e38e38e38daaaaa88c"
        ],
        // xDen
        [
          "0xd35771193d94918a9ca34ccbb7b640dd86cd409542f8487d9fe6b745781eb49b",
          "0xedadc6f64383dc1df7c4b2d51b54225406d36b641f5e41bbc52a56612a8c6d14",
          "0x0000000000000000000000000000000000000000000000000000000000000001"
          // LAST 1
        ],
        // yNum
        [
          "0x4bda12f684bda12f684bda12f684bda12f684bda12f684bda12f684b8e38e23c",
          "0xc75e0c32d5cb7c0fa9d0a54b12a0a6d5647ab046d686da6fdffc90fc201d71a3",
          "0x29a6194691f91a73715209ef6512e576722830a201be2018a765e85a9ecee931",
          "0x2f684bda12f684bda12f684bda12f684bda12f684bda12f684bda12f38e38d84"
        ],
        // yDen
        [
          "0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffefffff93b",
          "0x7a06534bb8bdb49fd5e9e6632722c2989467c1bfc8e8d978dfb425d2685c2573",
          "0x6484aa716545ca2cf3a70c3fa8fe337e0a3d21162f0d6299a7bf8192bfd2a76f",
          "0x0000000000000000000000000000000000000000000000000000000000000001"
          // LAST 1
        ]
      ].map((i) => i.map((j) => BigInt(j)))), mapSWU = (0, weierstrass_ts_1.mapToCurveSimpleSWU)(Fpk1, {
        A: BigInt("0x3f8731abdd661adca08a5558f0f5d272e953d363cb6f0e5d405447c01a444533"),
        B: BigInt("1771"),
        Z: Fpk1.create(BigInt("-11"))
      });
      exports.secp256k1_hasher = (0, hash_to_curve_ts_1.createHasher)(exports.secp256k1.Point, (scalars) => {
        let { x, y } = mapSWU(Fpk1.create(scalars[0]));
        return isoMap(x, y);
      }, {
        DST: "secp256k1_XMD:SHA-256_SSWU_RO_",
        encodeDST: "secp256k1_XMD:SHA-256_SSWU_NU_",
        p: Fpk1.ORDER,
        m: 1,
        k: 128,
        expand: "xmd",
        hash: sha2_js_1.sha256
      });
      exports.hashToCurve = exports.secp256k1_hasher.hashToCurve;
      exports.encodeToCurve = exports.secp256k1_hasher.encodeToCurve;
    }
  });

  // node_modules/@noble/curves/abstract/utils.js
  var require_utils4 = __commonJS({
    "node_modules/@noble/curves/abstract/utils.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      exports.isHash = exports.validateObject = exports.memoized = exports.notImplemented = exports.createHmacDrbg = exports.bitMask = exports.bitSet = exports.bitGet = exports.bitLen = exports.aInRange = exports.inRange = exports.asciiToBytes = exports.copyBytes = exports.equalBytes = exports.ensureBytes = exports.numberToVarBytesBE = exports.numberToBytesLE = exports.numberToBytesBE = exports.bytesToNumberLE = exports.bytesToNumberBE = exports.hexToNumber = exports.numberToHexUnpadded = exports.abool = exports.utf8ToBytes = exports.randomBytes = exports.isBytes = exports.hexToBytes = exports.concatBytes = exports.bytesToUtf8 = exports.bytesToHex = exports.anumber = exports.abytes = void 0;
      var u = require_utils3();
      exports.abytes = u.abytes;
      exports.anumber = u.anumber;
      exports.bytesToHex = u.bytesToHex;
      exports.bytesToUtf8 = u.bytesToUtf8;
      exports.concatBytes = u.concatBytes;
      exports.hexToBytes = u.hexToBytes;
      exports.isBytes = u.isBytes;
      exports.randomBytes = u.randomBytes;
      exports.utf8ToBytes = u.utf8ToBytes;
      exports.abool = u.abool;
      exports.numberToHexUnpadded = u.numberToHexUnpadded;
      exports.hexToNumber = u.hexToNumber;
      exports.bytesToNumberBE = u.bytesToNumberBE;
      exports.bytesToNumberLE = u.bytesToNumberLE;
      exports.numberToBytesBE = u.numberToBytesBE;
      exports.numberToBytesLE = u.numberToBytesLE;
      exports.numberToVarBytesBE = u.numberToVarBytesBE;
      exports.ensureBytes = u.ensureBytes;
      exports.equalBytes = u.equalBytes;
      exports.copyBytes = u.copyBytes;
      exports.asciiToBytes = u.asciiToBytes;
      exports.inRange = u.inRange;
      exports.aInRange = u.aInRange;
      exports.bitLen = u.bitLen;
      exports.bitGet = u.bitGet;
      exports.bitSet = u.bitSet;
      exports.bitMask = u.bitMask;
      exports.createHmacDrbg = u.createHmacDrbg;
      exports.notImplemented = u.notImplemented;
      exports.memoized = u.memoized;
      exports.validateObject = u.validateObject;
      exports.isHash = u.isHash;
    }
  });

  // node_modules/@bitcoinerlab/secp256k1/dist/index.js
  var require_dist2 = __commonJS({
    "node_modules/@bitcoinerlab/secp256k1/dist/index.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      var secp256k1 = require_secp256k1(), mod = require_modular(), utils = require_utils4();
      function _interopNamespaceDefault(e) {
        var n = /* @__PURE__ */ Object.create(null);
        return e && Object.keys(e).forEach(function(k) {
          if (k !== "default") {
            var d = Object.getOwnPropertyDescriptor(e, k);
            Object.defineProperty(n, k, d.get ? d : {
              enumerable: !0,
              get: function() {
                return e[k];
              }
            });
          }
        }), n.default = e, Object.freeze(n);
      }
      var mod__namespace = /* @__PURE__ */ _interopNamespaceDefault(mod), utils__namespace = /* @__PURE__ */ _interopNamespaceDefault(utils), Point = secp256k1.secp256k1.ProjectivePoint, THROW_BAD_PRIVATE = "Expected Private", THROW_BAD_POINT = "Expected Point", THROW_BAD_TWEAK = "Expected Tweak", THROW_BAD_HASH = "Expected Hash", THROW_BAD_SIGNATURE = "Expected Signature", THROW_BAD_EXTRA_DATA = "Expected Extra Data (32 bytes)", THROW_BAD_SCALAR = "Expected Scalar", THROW_BAD_RECOVERY_ID = "Bad Recovery Id", HASH_SIZE = 32, TWEAK_SIZE = 32, BN32_N = new Uint8Array([
        255,
        255,
        255,
        255,
        255,
        255,
        255,
        255,
        255,
        255,
        255,
        255,
        255,
        255,
        255,
        254,
        186,
        174,
        220,
        230,
        175,
        72,
        160,
        59,
        191,
        210,
        94,
        140,
        208,
        54,
        65,
        65
      ]), EXTRA_DATA_SIZE = 32, BN32_ZERO = new Uint8Array(32), BN32_P_MINUS_N = new Uint8Array([
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        1,
        69,
        81,
        35,
        25,
        80,
        183,
        95,
        196,
        64,
        45,
        161,
        114,
        47,
        201,
        186,
        238
      ]), _1n = BigInt(1);
      function isUint8Array(value) {
        return value instanceof Uint8Array;
      }
      function cmpBN32(data1, data2) {
        for (let i = 0; i < 32; ++i)
          if (data1[i] !== data2[i])
            return data1[i] < data2[i] ? -1 : 1;
        return 0;
      }
      function isZero(x) {
        return cmpBN32(x, BN32_ZERO) === 0;
      }
      function isTweak(tweak) {
        return !(!(tweak instanceof Uint8Array) || tweak.length !== TWEAK_SIZE || cmpBN32(tweak, BN32_N) >= 0);
      }
      function isSignature(signature) {
        return signature instanceof Uint8Array && signature.length === 64 && cmpBN32(signature.subarray(0, 32), BN32_N) < 0 && cmpBN32(signature.subarray(32, 64), BN32_N) < 0;
      }
      function isSigrLessThanPMinusN(signature) {
        return isUint8Array(signature) && signature.length === 64 && cmpBN32(signature.subarray(0, 32), BN32_P_MINUS_N) < 0;
      }
      function isSignatureNonzeroRS(signature) {
        return !(isZero(signature.subarray(0, 32)) || isZero(signature.subarray(32, 64)));
      }
      function isHash(h) {
        return h instanceof Uint8Array && h.length === HASH_SIZE;
      }
      function isExtraData(e) {
        return e === void 0 || e instanceof Uint8Array && e.length === EXTRA_DATA_SIZE;
      }
      function normalizeScalar(scalar) {
        let num;
        if (typeof scalar == "bigint")
          num = scalar;
        else if (typeof scalar == "number" && Number.isSafeInteger(scalar) && scalar >= 0)
          num = BigInt(scalar);
        else if (typeof scalar == "string") {
          if (scalar.length !== 64)
            throw new Error("Expected 32 bytes of private scalar");
          num = utils__namespace.hexToNumber(scalar);
        } else if (scalar instanceof Uint8Array) {
          if (scalar.length !== 32)
            throw new Error("Expected 32 bytes of private scalar");
          num = utils__namespace.bytesToNumberBE(scalar);
        } else
          throw new TypeError("Expected valid private scalar");
        if (num < 0) throw new Error("Expected private scalar >= 0");
        return num;
      }
      function normalizePrivateKey(privateKey) {
        return secp256k1.secp256k1.utils.normPrivateKeyToScalar(privateKey);
      }
      function _privateAdd(privateKey, tweak) {
        let p = normalizePrivateKey(privateKey), t = normalizeScalar(tweak), add = utils__namespace.numberToBytesBE(mod__namespace.mod(p + t, secp256k1.secp256k1.CURVE.n), 32);
        return secp256k1.secp256k1.utils.isValidPrivateKey(add) ? add : null;
      }
      function _privateSub(privateKey, tweak) {
        let p = normalizePrivateKey(privateKey), t = normalizeScalar(tweak), sub = utils__namespace.numberToBytesBE(mod__namespace.mod(p - t, secp256k1.secp256k1.CURVE.n), 32);
        return secp256k1.secp256k1.utils.isValidPrivateKey(sub) ? sub : null;
      }
      function _privateNegate(privateKey) {
        let p = normalizePrivateKey(privateKey), not = utils__namespace.numberToBytesBE(secp256k1.secp256k1.CURVE.n - p, 32);
        return secp256k1.secp256k1.utils.isValidPrivateKey(not) ? not : null;
      }
      function _pointAddScalar(p, tweak, isCompressed) {
        let P = fromHex(p), t = normalizeScalar(tweak), Q = Point.BASE.multiplyAndAddUnsafe(P, t, _1n);
        if (!Q) throw new Error("Tweaked point at infinity");
        return Q.toRawBytes(isCompressed);
      }
      function _pointMultiply(p, tweak, isCompressed) {
        let P = fromHex(p), h = typeof tweak == "string" ? tweak : utils__namespace.bytesToHex(tweak), t = utils__namespace.hexToNumber(h);
        return P.multiply(t).toRawBytes(isCompressed);
      }
      function assumeCompression(compressed, p) {
        return compressed === void 0 ? p !== void 0 ? isPointCompressed(p) : !0 : !!compressed;
      }
      function throwToNull(fn) {
        try {
          return fn();
        } catch {
          return null;
        }
      }
      function fromXOnly(bytes) {
        return secp256k1.schnorr.utils.lift_x(utils__namespace.bytesToNumberBE(bytes));
      }
      function fromHex(bytes) {
        return bytes.length === 32 ? fromXOnly(bytes) : Point.fromHex(bytes);
      }
      function _isPoint(p, xOnly) {
        if (p.length === 32 !== xOnly) return !1;
        try {
          return xOnly ? !!fromXOnly(p) : !!Point.fromHex(p);
        } catch {
          return !1;
        }
      }
      function isPoint2(p) {
        return _isPoint(p, !1);
      }
      function isPointCompressed(p) {
        return _isPoint(p, !1) && p.length === 33;
      }
      function isPrivate(d) {
        return secp256k1.secp256k1.utils.isValidPrivateKey(d);
      }
      function isXOnlyPoint(p) {
        return _isPoint(p, !0);
      }
      function xOnlyPointAddTweak(p, tweak) {
        if (!isXOnlyPoint(p))
          throw new Error(THROW_BAD_POINT);
        if (!isTweak(tweak))
          throw new Error(THROW_BAD_TWEAK);
        return throwToNull(() => {
          let P = _pointAddScalar(p, tweak, !0);
          return { parity: P[0] % 2 === 1 ? 1 : 0, xOnlyPubkey: P.slice(1) };
        });
      }
      function xOnlyPointFromPoint(p) {
        if (!isPoint2(p))
          throw new Error(THROW_BAD_POINT);
        return p.slice(1, 33);
      }
      function pointFromScalar(sk, compressed) {
        if (!isPrivate(sk))
          throw new Error(THROW_BAD_PRIVATE);
        return throwToNull(
          () => secp256k1.secp256k1.getPublicKey(sk, assumeCompression(compressed))
        );
      }
      function xOnlyPointFromScalar(d) {
        if (!isPrivate(d))
          throw new Error(THROW_BAD_PRIVATE);
        return xOnlyPointFromPoint(pointFromScalar(d));
      }
      function pointCompress(p, compressed) {
        if (!isPoint2(p))
          throw new Error(THROW_BAD_POINT);
        return fromHex(p).toRawBytes(assumeCompression(compressed, p));
      }
      function pointMultiply(a, tweak, compressed) {
        if (!isPoint2(a))
          throw new Error(THROW_BAD_POINT);
        if (!isTweak(tweak))
          throw new Error(THROW_BAD_TWEAK);
        return throwToNull(
          () => _pointMultiply(a, tweak, assumeCompression(compressed, a))
        );
      }
      function pointAdd(a, b, compressed) {
        if (!isPoint2(a) || !isPoint2(b))
          throw new Error(THROW_BAD_POINT);
        return throwToNull(() => {
          let A = fromHex(a), B = fromHex(b);
          return A.equals(B.negate()) ? null : A.add(B).toRawBytes(assumeCompression(compressed, a));
        });
      }
      function pointAddScalar(p, tweak, compressed) {
        if (!isPoint2(p))
          throw new Error(THROW_BAD_POINT);
        if (!isTweak(tweak))
          throw new Error(THROW_BAD_TWEAK);
        return throwToNull(
          () => _pointAddScalar(p, tweak, assumeCompression(compressed, p))
        );
      }
      function privateAdd(d, tweak) {
        if (!isPrivate(d))
          throw new Error(THROW_BAD_PRIVATE);
        if (!isTweak(tweak))
          throw new Error(THROW_BAD_TWEAK);
        return throwToNull(() => _privateAdd(d, tweak));
      }
      function privateSub(d, tweak) {
        if (!isPrivate(d))
          throw new Error(THROW_BAD_PRIVATE);
        if (!isTweak(tweak))
          throw new Error(THROW_BAD_TWEAK);
        return throwToNull(() => _privateSub(d, tweak));
      }
      function privateNegate(d) {
        if (!isPrivate(d))
          throw new Error(THROW_BAD_PRIVATE);
        return _privateNegate(d);
      }
      function sign(h, d, e) {
        if (!isPrivate(d))
          throw new Error(THROW_BAD_PRIVATE);
        if (!isHash(h))
          throw new Error(THROW_BAD_SCALAR);
        if (!isExtraData(e))
          throw new Error(THROW_BAD_EXTRA_DATA);
        return secp256k1.secp256k1.sign(h, d, { extraEntropy: e }).toCompactRawBytes();
      }
      function signRecoverable(h, d, e) {
        if (!isPrivate(d))
          throw new Error(THROW_BAD_PRIVATE);
        if (!isHash(h))
          throw new Error(THROW_BAD_SCALAR);
        if (!isExtraData(e))
          throw new Error(THROW_BAD_EXTRA_DATA);
        let sig = secp256k1.secp256k1.sign(h, d, { extraEntropy: e });
        return {
          signature: sig.toCompactRawBytes(),
          recoveryId: sig.recovery
        };
      }
      function signSchnorr(h, d, e) {
        if (!isPrivate(d))
          throw new Error(THROW_BAD_PRIVATE);
        if (!isHash(h))
          throw new Error(THROW_BAD_SCALAR);
        if (!isExtraData(e))
          throw new Error(THROW_BAD_EXTRA_DATA);
        return secp256k1.schnorr.sign(h, d, e);
      }
      function recover(h, signature, recoveryId, compressed) {
        if (!isHash(h))
          throw new Error(THROW_BAD_HASH);
        if (!isSignature(signature) || !isSignatureNonzeroRS(signature))
          throw new Error(THROW_BAD_SIGNATURE);
        if (recoveryId & 2 && !isSigrLessThanPMinusN(signature))
          throw new Error(THROW_BAD_RECOVERY_ID);
        if (!isXOnlyPoint(signature.subarray(0, 32)))
          throw new Error(THROW_BAD_SIGNATURE);
        let Q = secp256k1.secp256k1.Signature.fromCompact(signature).addRecoveryBit(recoveryId).recoverPublicKey(h);
        if (!Q) throw new Error(THROW_BAD_SIGNATURE);
        return Q.toRawBytes(assumeCompression(compressed));
      }
      function verify2(h, Q, signature, strict) {
        if (!isPoint2(Q))
          throw new Error(THROW_BAD_POINT);
        if (!isSignature(signature))
          throw new Error(THROW_BAD_SIGNATURE);
        if (!isHash(h))
          throw new Error(THROW_BAD_SCALAR);
        return secp256k1.secp256k1.verify(signature, h, Q, { lowS: strict });
      }
      function verifySchnorr2(h, Q, signature) {
        if (!isXOnlyPoint(Q))
          throw new Error(THROW_BAD_POINT);
        if (!isSignature(signature))
          throw new Error(THROW_BAD_SIGNATURE);
        if (!isHash(h))
          throw new Error(THROW_BAD_SCALAR);
        return secp256k1.schnorr.verify(signature, h, Q);
      }
      exports.isPoint = isPoint2;
      exports.isPointCompressed = isPointCompressed;
      exports.isPrivate = isPrivate;
      exports.isXOnlyPoint = isXOnlyPoint;
      exports.pointAdd = pointAdd;
      exports.pointAddScalar = pointAddScalar;
      exports.pointCompress = pointCompress;
      exports.pointFromScalar = pointFromScalar;
      exports.pointMultiply = pointMultiply;
      exports.privateAdd = privateAdd;
      exports.privateNegate = privateNegate;
      exports.privateSub = privateSub;
      exports.recover = recover;
      exports.sign = sign;
      exports.signRecoverable = signRecoverable;
      exports.signSchnorr = signSchnorr;
      exports.verify = verify2;
      exports.verifySchnorr = verifySchnorr2;
      exports.xOnlyPointAddTweak = xOnlyPointAddTweak;
      exports.xOnlyPointFromPoint = xOnlyPointFromPoint;
      exports.xOnlyPointFromScalar = xOnlyPointFromScalar;
    }
  });

  // node_modules/@noble/hashes/sha512.js
  var require_sha512 = __commonJS({
    "node_modules/@noble/hashes/sha512.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      exports.sha512_256 = exports.SHA512_256 = exports.sha512_224 = exports.SHA512_224 = exports.sha384 = exports.SHA384 = exports.sha512 = exports.SHA512 = void 0;
      var sha2_ts_1 = require_sha2();
      exports.SHA512 = sha2_ts_1.SHA512;
      exports.sha512 = sha2_ts_1.sha512;
      exports.SHA384 = sha2_ts_1.SHA384;
      exports.sha384 = sha2_ts_1.sha384;
      exports.SHA512_224 = sha2_ts_1.SHA512_224;
      exports.sha512_224 = sha2_ts_1.sha512_224;
      exports.SHA512_256 = sha2_ts_1.SHA512_256;
      exports.sha512_256 = sha2_ts_1.sha512_256;
    }
  });

  // node_modules/bip32/src/crypto.js
  var require_crypto3 = __commonJS({
    "node_modules/bip32/src/crypto.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      exports.hmacSHA512 = exports.hash160 = void 0;
      var hmac_1 = require_hmac(), ripemd160_1 = require_ripemd160(), sha256_1 = require_sha256(), sha512_1 = require_sha512();
      function hash160(buffer) {
        let sha256Hash = (0, sha256_1.sha256)(Uint8Array.from(buffer));
        return import_buffer.Buffer.from((0, ripemd160_1.ripemd160)(sha256Hash));
      }
      exports.hash160 = hash160;
      function hmacSHA512(key, data) {
        return import_buffer.Buffer.from((0, hmac_1.hmac)(sha512_1.sha512, key, data));
      }
      exports.hmacSHA512 = hmacSHA512;
    }
  });

  // node_modules/bip32/src/testecc.js
  var require_testecc = __commonJS({
    "node_modules/bip32/src/testecc.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      exports.testEcc = void 0;
      var h = (hex) => import_buffer.Buffer.from(hex, "hex");
      function testEcc(ecc2) {
        if (assert(ecc2.isPoint(h("0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"))), assert(!ecc2.isPoint(h("030000000000000000000000000000000000000000000000000000000000000005"))), assert(ecc2.isPrivate(h("79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"))), assert(ecc2.isPrivate(h("fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364140"))), assert(!ecc2.isPrivate(h("0000000000000000000000000000000000000000000000000000000000000000"))), assert(!ecc2.isPrivate(h("fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141"))), assert(!ecc2.isPrivate(h("fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364142"))), assert(import_buffer.Buffer.from(ecc2.pointFromScalar(h("b1121e4088a66a28f5b6b0f5844943ecd9f610196d7bb83b25214b60452c09af"))).equals(h("02b07ba9dca9523b7ef4bd97703d43d20399eb698e194704791a25ce77a400df99"))), ecc2.xOnlyPointAddTweak) {
          assert(ecc2.xOnlyPointAddTweak(h("79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"), h("fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364140")) === null);
          let xOnlyRes = ecc2.xOnlyPointAddTweak(h("1617d38ed8d8657da4d4761e8057bc396ea9e4b9d29776d4be096016dbd2509b"), h("a8397a935f0dfceba6ba9618f6451ef4d80637abf4e6af2669fbc9de6a8fd2ac"));
          assert(import_buffer.Buffer.from(xOnlyRes.xOnlyPubkey).equals(h("e478f99dab91052ab39a33ea35fd5e6e4933f4d28023cd597c9a1f6760346adf")) && xOnlyRes.parity === 1), xOnlyRes = ecc2.xOnlyPointAddTweak(h("2c0b7cf95324a07d05398b240174dc0c2be444d96b159aa6c7f7b1e668680991"), h("823c3cd2142744b075a87eade7e1b8678ba308d566226a0056ca2b7a76f86b47"));
        }
        assert(import_buffer.Buffer.from(ecc2.pointAddScalar(h("0379be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"), h("0000000000000000000000000000000000000000000000000000000000000003"))).equals(h("02c6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5"))), assert(import_buffer.Buffer.from(ecc2.privateAdd(h("fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd036413e"), h("0000000000000000000000000000000000000000000000000000000000000002"))).equals(h("fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364140"))), ecc2.privateNegate && (assert(import_buffer.Buffer.from(ecc2.privateNegate(h("0000000000000000000000000000000000000000000000000000000000000001"))).equals(h("fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364140"))), assert(import_buffer.Buffer.from(ecc2.privateNegate(h("fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd036413e"))).equals(h("0000000000000000000000000000000000000000000000000000000000000003"))), assert(import_buffer.Buffer.from(ecc2.privateNegate(h("b1121e4088a66a28f5b6b0f5844943ecd9f610196d7bb83b25214b60452c09af"))).equals(h("4eede1bf775995d70a494f0a7bb6bc11e0b8cccd41cce8009ab1132c8b0a3792")))), assert(import_buffer.Buffer.from(ecc2.sign(h("5e9f0a0d593efdcf78ac923bc3313e4e7d408d574354ee2b3288c0da9fbba6ed"), h("fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364140"))).equals(h("54c4a33c6423d689378f160a7ff8b61330444abb58fb470f96ea16d99d4a2fed07082304410efa6b2943111b6a4e0aaa7b7db55a07e9861d1fb3cb1f421044a5"))), assert(ecc2.verify(h("5e9f0a0d593efdcf78ac923bc3313e4e7d408d574354ee2b3288c0da9fbba6ed"), h("0379be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"), h("54c4a33c6423d689378f160a7ff8b61330444abb58fb470f96ea16d99d4a2fed07082304410efa6b2943111b6a4e0aaa7b7db55a07e9861d1fb3cb1f421044a5"))), ecc2.signSchnorr && assert(import_buffer.Buffer.from(ecc2.signSchnorr(h("7e2d58d8b3bcdf1abadec7829054f90dda9805aab56c77333024b9d0a508b75c"), h("c90fdaa22168c234c4c6628b80dc1cd129024e088a67cc74020bbea63b14e5c9"), h("c87aa53824b4d7ae2eb035a2b5bbbccc080e76cdc6d1692c4b0b62d798e6d906"))).equals(h("5831aaeed7b44bb74e5eab94ba9d4294c49bcf2a60728d8b4c200f50dd313c1bab745879a5ad954a72c45a91c3a51d3c7adea98d82f8481e0e1e03674a6f3fb7"))), ecc2.verifySchnorr && assert(ecc2.verifySchnorr(h("7e2d58d8b3bcdf1abadec7829054f90dda9805aab56c77333024b9d0a508b75c"), h("dd308afec5777e13121fa72b9cc1b7cc0139715309b086c960e18fd969774eb8"), h("5831aaeed7b44bb74e5eab94ba9d4294c49bcf2a60728d8b4c200f50dd313c1bab745879a5ad954a72c45a91c3a51d3c7adea98d82f8481e0e1e03674a6f3fb7")));
      }
      exports.testEcc = testEcc;
      function assert(bool) {
        if (!bool)
          throw new Error("ecc library invalid");
      }
    }
  });

  // node_modules/@scure/base/lib/index.js
  var require_lib = __commonJS({
    "node_modules/@scure/base/lib/index.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      exports.bytes = exports.stringToBytes = exports.str = exports.bytesToString = exports.hex = exports.utf8 = exports.bech32m = exports.bech32 = exports.base58check = exports.createBase58check = exports.base58xmr = exports.base58xrp = exports.base58flickr = exports.base58 = exports.base64urlnopad = exports.base64url = exports.base64nopad = exports.base64 = exports.base32crockford = exports.base32hexnopad = exports.base32hex = exports.base32nopad = exports.base32 = exports.base16 = exports.utils = void 0;
      function isBytes(a) {
        return a instanceof Uint8Array || ArrayBuffer.isView(a) && a.constructor.name === "Uint8Array";
      }
      function abytes(b, ...lengths) {
        if (!isBytes(b))
          throw new Error("Uint8Array expected");
        if (lengths.length > 0 && !lengths.includes(b.length))
          throw new Error("Uint8Array expected of length " + lengths + ", got length=" + b.length);
      }
      function isArrayOf(isString, arr) {
        return Array.isArray(arr) ? arr.length === 0 ? !0 : isString ? arr.every((item) => typeof item == "string") : arr.every((item) => Number.isSafeInteger(item)) : !1;
      }
      function afn(input) {
        if (typeof input != "function")
          throw new Error("function expected");
        return !0;
      }
      function astr(label, input) {
        if (typeof input != "string")
          throw new Error(`${label}: string expected`);
        return !0;
      }
      function anumber(n) {
        if (!Number.isSafeInteger(n))
          throw new Error(`invalid integer: ${n}`);
      }
      function aArr(input) {
        if (!Array.isArray(input))
          throw new Error("array expected");
      }
      function astrArr(label, input) {
        if (!isArrayOf(!0, input))
          throw new Error(`${label}: array of strings expected`);
      }
      function anumArr(label, input) {
        if (!isArrayOf(!1, input))
          throw new Error(`${label}: array of numbers expected`);
      }
      // @__NO_SIDE_EFFECTS__
      function chain(...args) {
        let id = (a) => a, wrap = (a, b) => (c) => a(b(c)), encode = args.map((x) => x.encode).reduceRight(wrap, id), decode = args.map((x) => x.decode).reduce(wrap, id);
        return { encode, decode };
      }
      // @__NO_SIDE_EFFECTS__
      function alphabet(letters) {
        let lettersA = typeof letters == "string" ? letters.split("") : letters, len = lettersA.length;
        astrArr("alphabet", lettersA);
        let indexes = new Map(lettersA.map((l, i) => [l, i]));
        return {
          encode: (digits) => (aArr(digits), digits.map((i) => {
            if (!Number.isSafeInteger(i) || i < 0 || i >= len)
              throw new Error(`alphabet.encode: digit index outside alphabet "${i}". Allowed: ${letters}`);
            return lettersA[i];
          })),
          decode: (input) => (aArr(input), input.map((letter) => {
            astr("alphabet.decode", letter);
            let i = indexes.get(letter);
            if (i === void 0)
              throw new Error(`Unknown letter: "${letter}". Allowed: ${letters}`);
            return i;
          }))
        };
      }
      // @__NO_SIDE_EFFECTS__
      function join(separator = "") {
        return astr("join", separator), {
          encode: (from) => (astrArr("join.decode", from), from.join(separator)),
          decode: (to) => (astr("join.decode", to), to.split(separator))
        };
      }
      // @__NO_SIDE_EFFECTS__
      function padding(bits, chr = "=") {
        return anumber(bits), astr("padding", chr), {
          encode(data) {
            for (astrArr("padding.encode", data); data.length * bits % 8; )
              data.push(chr);
            return data;
          },
          decode(input) {
            astrArr("padding.decode", input);
            let end = input.length;
            if (end * bits % 8)
              throw new Error("padding: invalid, string should have whole number of bytes");
            for (; end > 0 && input[end - 1] === chr; end--)
              if ((end - 1) * bits % 8 === 0)
                throw new Error("padding: invalid, string has too much padding");
            return input.slice(0, end);
          }
        };
      }
      // @__NO_SIDE_EFFECTS__
      function normalize(fn) {
        return afn(fn), { encode: (from) => from, decode: (to) => fn(to) };
      }
      function convertRadix(data, from, to) {
        if (from < 2)
          throw new Error(`convertRadix: invalid from=${from}, base cannot be less than 2`);
        if (to < 2)
          throw new Error(`convertRadix: invalid to=${to}, base cannot be less than 2`);
        if (aArr(data), !data.length)
          return [];
        let pos = 0, res = [], digits = Array.from(data, (d) => {
          if (anumber(d), d < 0 || d >= from)
            throw new Error(`invalid integer: ${d}`);
          return d;
        }), dlen = digits.length;
        for (; ; ) {
          let carry = 0, done = !0;
          for (let i = pos; i < dlen; i++) {
            let digit = digits[i], fromCarry = from * carry, digitBase = fromCarry + digit;
            if (!Number.isSafeInteger(digitBase) || fromCarry / from !== carry || digitBase - digit !== fromCarry)
              throw new Error("convertRadix: carry overflow");
            let div = digitBase / to;
            carry = digitBase % to;
            let rounded = Math.floor(div);
            if (digits[i] = rounded, !Number.isSafeInteger(rounded) || rounded * to + carry !== digitBase)
              throw new Error("convertRadix: carry overflow");
            if (done)
              rounded ? done = !1 : pos = i;
            else continue;
          }
          if (res.push(carry), done)
            break;
        }
        for (let i = 0; i < data.length - 1 && data[i] === 0; i++)
          res.push(0);
        return res.reverse();
      }
      var gcd = (a, b) => b === 0 ? a : gcd(b, a % b), radix2carry = /* @__NO_SIDE_EFFECTS__ */ (from, to) => from + (to - gcd(from, to)), powers = /* @__PURE__ */ (() => {
        let res = [];
        for (let i = 0; i < 40; i++)
          res.push(2 ** i);
        return res;
      })();
      function convertRadix2(data, from, to, padding2) {
        if (aArr(data), from <= 0 || from > 32)
          throw new Error(`convertRadix2: wrong from=${from}`);
        if (to <= 0 || to > 32)
          throw new Error(`convertRadix2: wrong to=${to}`);
        if (/* @__PURE__ */ radix2carry(from, to) > 32)
          throw new Error(`convertRadix2: carry overflow from=${from} to=${to} carryBits=${/* @__PURE__ */ radix2carry(from, to)}`);
        let carry = 0, pos = 0, max = powers[from], mask = powers[to] - 1, res = [];
        for (let n of data) {
          if (anumber(n), n >= max)
            throw new Error(`convertRadix2: invalid data word=${n} from=${from}`);
          if (carry = carry << from | n, pos + from > 32)
            throw new Error(`convertRadix2: carry overflow pos=${pos} from=${from}`);
          for (pos += from; pos >= to; pos -= to)
            res.push((carry >> pos - to & mask) >>> 0);
          let pow = powers[pos];
          if (pow === void 0)
            throw new Error("invalid carry");
          carry &= pow - 1;
        }
        if (carry = carry << to - pos & mask, !padding2 && pos >= from)
          throw new Error("Excess padding");
        if (!padding2 && carry > 0)
          throw new Error(`Non-zero padding: ${carry}`);
        return padding2 && pos > 0 && res.push(carry >>> 0), res;
      }
      // @__NO_SIDE_EFFECTS__
      function radix(num) {
        anumber(num);
        let _256 = 2 ** 8;
        return {
          encode: (bytes) => {
            if (!isBytes(bytes))
              throw new Error("radix.encode input should be Uint8Array");
            return convertRadix(Array.from(bytes), _256, num);
          },
          decode: (digits) => (anumArr("radix.decode", digits), Uint8Array.from(convertRadix(digits, num, _256)))
        };
      }
      // @__NO_SIDE_EFFECTS__
      function radix2(bits, revPadding = !1) {
        if (anumber(bits), bits <= 0 || bits > 32)
          throw new Error("radix2: bits should be in (0..32]");
        if (/* @__PURE__ */ radix2carry(8, bits) > 32 || /* @__PURE__ */ radix2carry(bits, 8) > 32)
          throw new Error("radix2: carry overflow");
        return {
          encode: (bytes) => {
            if (!isBytes(bytes))
              throw new Error("radix2.encode input should be Uint8Array");
            return convertRadix2(Array.from(bytes), 8, bits, !revPadding);
          },
          decode: (digits) => (anumArr("radix2.decode", digits), Uint8Array.from(convertRadix2(digits, bits, 8, revPadding)))
        };
      }
      function unsafeWrapper(fn) {
        return afn(fn), function(...args) {
          try {
            return fn.apply(null, args);
          } catch {
          }
        };
      }
      function checksum(len, fn) {
        return anumber(len), afn(fn), {
          encode(data) {
            if (!isBytes(data))
              throw new Error("checksum.encode: input should be Uint8Array");
            let sum = fn(data).slice(0, len), res = new Uint8Array(data.length + len);
            return res.set(data), res.set(sum, data.length), res;
          },
          decode(data) {
            if (!isBytes(data))
              throw new Error("checksum.decode: input should be Uint8Array");
            let payload = data.slice(0, -len), oldChecksum = data.slice(-len), newChecksum = fn(payload).slice(0, len);
            for (let i = 0; i < len; i++)
              if (newChecksum[i] !== oldChecksum[i])
                throw new Error("Invalid checksum");
            return payload;
          }
        };
      }
      exports.utils = {
        alphabet,
        chain,
        checksum,
        convertRadix,
        convertRadix2,
        radix,
        radix2,
        join,
        padding
      };
      exports.base16 = /* @__PURE__ */ chain(/* @__PURE__ */ radix2(4), /* @__PURE__ */ alphabet("0123456789ABCDEF"), /* @__PURE__ */ join(""));
      exports.base32 = /* @__PURE__ */ chain(/* @__PURE__ */ radix2(5), /* @__PURE__ */ alphabet("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"), /* @__PURE__ */ padding(5), /* @__PURE__ */ join(""));
      exports.base32nopad = /* @__PURE__ */ chain(/* @__PURE__ */ radix2(5), /* @__PURE__ */ alphabet("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"), /* @__PURE__ */ join(""));
      exports.base32hex = /* @__PURE__ */ chain(/* @__PURE__ */ radix2(5), /* @__PURE__ */ alphabet("0123456789ABCDEFGHIJKLMNOPQRSTUV"), /* @__PURE__ */ padding(5), /* @__PURE__ */ join(""));
      exports.base32hexnopad = /* @__PURE__ */ chain(/* @__PURE__ */ radix2(5), /* @__PURE__ */ alphabet("0123456789ABCDEFGHIJKLMNOPQRSTUV"), /* @__PURE__ */ join(""));
      exports.base32crockford = /* @__PURE__ */ chain(/* @__PURE__ */ radix2(5), /* @__PURE__ */ alphabet("0123456789ABCDEFGHJKMNPQRSTVWXYZ"), /* @__PURE__ */ join(""), /* @__PURE__ */ normalize((s) => s.toUpperCase().replace(/O/g, "0").replace(/[IL]/g, "1")));
      var hasBase64Builtin = typeof Uint8Array.from([]).toBase64 == "function" && typeof Uint8Array.fromBase64 == "function", decodeBase64Builtin = (s, isUrl) => {
        astr("base64", s);
        let re = isUrl ? /^[A-Za-z0-9=_-]+$/ : /^[A-Za-z0-9=+/]+$/, alphabet2 = isUrl ? "base64url" : "base64";
        if (s.length > 0 && !re.test(s))
          throw new Error("invalid base64");
        return Uint8Array.fromBase64(s, { alphabet: alphabet2, lastChunkHandling: "strict" });
      };
      exports.base64 = hasBase64Builtin ? {
        encode(b) {
          return abytes(b), b.toBase64();
        },
        decode(s) {
          return decodeBase64Builtin(s, !1);
        }
      } : /* @__PURE__ */ chain(/* @__PURE__ */ radix2(6), /* @__PURE__ */ alphabet("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"), /* @__PURE__ */ padding(6), /* @__PURE__ */ join(""));
      exports.base64nopad = /* @__PURE__ */ chain(/* @__PURE__ */ radix2(6), /* @__PURE__ */ alphabet("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"), /* @__PURE__ */ join(""));
      exports.base64url = hasBase64Builtin ? {
        encode(b) {
          return abytes(b), b.toBase64({ alphabet: "base64url" });
        },
        decode(s) {
          return decodeBase64Builtin(s, !0);
        }
      } : /* @__PURE__ */ chain(/* @__PURE__ */ radix2(6), /* @__PURE__ */ alphabet("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"), /* @__PURE__ */ padding(6), /* @__PURE__ */ join(""));
      exports.base64urlnopad = /* @__PURE__ */ chain(/* @__PURE__ */ radix2(6), /* @__PURE__ */ alphabet("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"), /* @__PURE__ */ join(""));
      var genBase58 = /* @__NO_SIDE_EFFECTS__ */ (abc) => /* @__PURE__ */ chain(/* @__PURE__ */ radix(58), /* @__PURE__ */ alphabet(abc), /* @__PURE__ */ join(""));
      exports.base58 = /* @__PURE__ */ genBase58("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz");
      exports.base58flickr = /* @__PURE__ */ genBase58("123456789abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ");
      exports.base58xrp = /* @__PURE__ */ genBase58("rpshnaf39wBUDNEGHJKLM4PQRST7VWXYZ2bcdeCg65jkm8oFqi1tuvAxyz");
      var XMR_BLOCK_LEN = [0, 2, 3, 5, 6, 7, 9, 10, 11];
      exports.base58xmr = {
        encode(data) {
          let res = "";
          for (let i = 0; i < data.length; i += 8) {
            let block = data.subarray(i, i + 8);
            res += exports.base58.encode(block).padStart(XMR_BLOCK_LEN[block.length], "1");
          }
          return res;
        },
        decode(str) {
          let res = [];
          for (let i = 0; i < str.length; i += 11) {
            let slice = str.slice(i, i + 11), blockLen = XMR_BLOCK_LEN.indexOf(slice.length), block = exports.base58.decode(slice);
            for (let j = 0; j < block.length - blockLen; j++)
              if (block[j] !== 0)
                throw new Error("base58xmr: wrong padding");
            res = res.concat(Array.from(block.slice(block.length - blockLen)));
          }
          return Uint8Array.from(res);
        }
      };
      var createBase58check = (sha256) => /* @__PURE__ */ chain(checksum(4, (data) => sha256(sha256(data))), exports.base58);
      exports.createBase58check = createBase58check;
      exports.base58check = exports.createBase58check;
      var BECH_ALPHABET = /* @__PURE__ */ chain(/* @__PURE__ */ alphabet("qpzry9x8gf2tvdw0s3jn54khce6mua7l"), /* @__PURE__ */ join("")), POLYMOD_GENERATORS = [996825010, 642813549, 513874426, 1027748829, 705979059];
      function bech32Polymod(pre) {
        let b = pre >> 25, chk = (pre & 33554431) << 5;
        for (let i = 0; i < POLYMOD_GENERATORS.length; i++)
          (b >> i & 1) === 1 && (chk ^= POLYMOD_GENERATORS[i]);
        return chk;
      }
      function bechChecksum(prefix, words, encodingConst = 1) {
        let len = prefix.length, chk = 1;
        for (let i = 0; i < len; i++) {
          let c = prefix.charCodeAt(i);
          if (c < 33 || c > 126)
            throw new Error(`Invalid prefix (${prefix})`);
          chk = bech32Polymod(chk) ^ c >> 5;
        }
        chk = bech32Polymod(chk);
        for (let i = 0; i < len; i++)
          chk = bech32Polymod(chk) ^ prefix.charCodeAt(i) & 31;
        for (let v of words)
          chk = bech32Polymod(chk) ^ v;
        for (let i = 0; i < 6; i++)
          chk = bech32Polymod(chk);
        return chk ^= encodingConst, BECH_ALPHABET.encode(convertRadix2([chk % powers[30]], 30, 5, !1));
      }
      // @__NO_SIDE_EFFECTS__
      function genBech32(encoding) {
        let ENCODING_CONST = encoding === "bech32" ? 1 : 734539939, _words = /* @__PURE__ */ radix2(5), fromWords = _words.decode, toWords = _words.encode, fromWordsUnsafe = unsafeWrapper(fromWords);
        function encode(prefix, words, limit = 90) {
          astr("bech32.encode prefix", prefix), isBytes(words) && (words = Array.from(words)), anumArr("bech32.encode", words);
          let plen = prefix.length;
          if (plen === 0)
            throw new TypeError(`Invalid prefix length ${plen}`);
          let actualLength = plen + 7 + words.length;
          if (limit !== !1 && actualLength > limit)
            throw new TypeError(`Length ${actualLength} exceeds limit ${limit}`);
          let lowered = prefix.toLowerCase(), sum = bechChecksum(lowered, words, ENCODING_CONST);
          return `${lowered}1${BECH_ALPHABET.encode(words)}${sum}`;
        }
        function decode(str, limit = 90) {
          astr("bech32.decode input", str);
          let slen = str.length;
          if (slen < 8 || limit !== !1 && slen > limit)
            throw new TypeError(`invalid string length: ${slen} (${str}). Expected (8..${limit})`);
          let lowered = str.toLowerCase();
          if (str !== lowered && str !== str.toUpperCase())
            throw new Error("String must be lowercase or uppercase");
          let sepIndex = lowered.lastIndexOf("1");
          if (sepIndex === 0 || sepIndex === -1)
            throw new Error('Letter "1" must be present between prefix and data only');
          let prefix = lowered.slice(0, sepIndex), data = lowered.slice(sepIndex + 1);
          if (data.length < 6)
            throw new Error("Data must be at least 6 characters long");
          let words = BECH_ALPHABET.decode(data).slice(0, -6), sum = bechChecksum(prefix, words, ENCODING_CONST);
          if (!data.endsWith(sum))
            throw new Error(`Invalid checksum in ${str}: expected "${sum}"`);
          return { prefix, words };
        }
        let decodeUnsafe = unsafeWrapper(decode);
        function decodeToBytes(str) {
          let { prefix, words } = decode(str, !1);
          return { prefix, words, bytes: fromWords(words) };
        }
        function encodeFromBytes(prefix, bytes) {
          return encode(prefix, toWords(bytes));
        }
        return {
          encode,
          decode,
          encodeFromBytes,
          decodeToBytes,
          decodeUnsafe,
          fromWords,
          fromWordsUnsafe,
          toWords
        };
      }
      exports.bech32 = /* @__PURE__ */ genBech32("bech32");
      exports.bech32m = /* @__PURE__ */ genBech32("bech32m");
      exports.utf8 = {
        encode: (data) => new TextDecoder().decode(data),
        decode: (str) => new TextEncoder().encode(str)
      };
      var hasHexBuiltin = typeof Uint8Array.from([]).toHex == "function" && typeof Uint8Array.fromHex == "function", hexBuiltin = {
        encode(data) {
          return abytes(data), data.toHex();
        },
        decode(s) {
          return astr("hex", s), Uint8Array.fromHex(s);
        }
      };
      exports.hex = hasHexBuiltin ? hexBuiltin : /* @__PURE__ */ chain(/* @__PURE__ */ radix2(4), /* @__PURE__ */ alphabet("0123456789abcdef"), /* @__PURE__ */ join(""), /* @__PURE__ */ normalize((s) => {
        if (typeof s != "string" || s.length % 2 !== 0)
          throw new TypeError(`hex.decode: expected string, got ${typeof s} with length ${s.length}`);
        return s.toLowerCase();
      }));
      var CODERS = {
        utf8: exports.utf8,
        hex: exports.hex,
        base16: exports.base16,
        base32: exports.base32,
        base64: exports.base64,
        base64url: exports.base64url,
        base58: exports.base58,
        base58xmr: exports.base58xmr
      }, coderTypeError = "Invalid encoding type. Available types: utf8, hex, base16, base32, base64, base64url, base58, base58xmr", bytesToString = (type, bytes) => {
        if (typeof type != "string" || !CODERS.hasOwnProperty(type))
          throw new TypeError(coderTypeError);
        if (!isBytes(bytes))
          throw new TypeError("bytesToString() expects Uint8Array");
        return CODERS[type].encode(bytes);
      };
      exports.bytesToString = bytesToString;
      exports.str = exports.bytesToString;
      var stringToBytes = (type, str) => {
        if (!CODERS.hasOwnProperty(type))
          throw new TypeError(coderTypeError);
        if (typeof str != "string")
          throw new TypeError("stringToBytes() expects string");
        return CODERS[type].decode(str);
      };
      exports.stringToBytes = stringToBytes;
      exports.bytes = exports.stringToBytes;
    }
  });

  // node_modules/inherits/inherits_browser.js
  var require_inherits_browser = __commonJS({
    "node_modules/inherits/inherits_browser.js"(exports, module) {
      init_buffer_shim();
      init_process_shim();
      typeof Object.create == "function" ? module.exports = function(ctor, superCtor) {
        superCtor && (ctor.super_ = superCtor, ctor.prototype = Object.create(superCtor.prototype, {
          constructor: {
            value: ctor,
            enumerable: !1,
            writable: !0,
            configurable: !0
          }
        }));
      } : module.exports = function(ctor, superCtor) {
        if (superCtor) {
          ctor.super_ = superCtor;
          var TempCtor = function() {
          };
          TempCtor.prototype = superCtor.prototype, ctor.prototype = new TempCtor(), ctor.prototype.constructor = ctor;
        }
      };
    }
  });

  // node_modules/to-buffer/node_modules/isarray/index.js
  var require_isarray = __commonJS({
    "node_modules/to-buffer/node_modules/isarray/index.js"(exports, module) {
      init_buffer_shim();
      init_process_shim();
      var toString = {}.toString;
      module.exports = Array.isArray || function(arr) {
        return toString.call(arr) == "[object Array]";
      };
    }
  });

  // node_modules/es-errors/type.js
  var require_type = __commonJS({
    "node_modules/es-errors/type.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      module.exports = TypeError;
    }
  });

  // node_modules/es-object-atoms/index.js
  var require_es_object_atoms = __commonJS({
    "node_modules/es-object-atoms/index.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      module.exports = Object;
    }
  });

  // node_modules/es-errors/index.js
  var require_es_errors = __commonJS({
    "node_modules/es-errors/index.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      module.exports = Error;
    }
  });

  // node_modules/es-errors/eval.js
  var require_eval = __commonJS({
    "node_modules/es-errors/eval.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      module.exports = EvalError;
    }
  });

  // node_modules/es-errors/range.js
  var require_range = __commonJS({
    "node_modules/es-errors/range.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      module.exports = RangeError;
    }
  });

  // node_modules/es-errors/ref.js
  var require_ref = __commonJS({
    "node_modules/es-errors/ref.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      module.exports = ReferenceError;
    }
  });

  // node_modules/es-errors/syntax.js
  var require_syntax = __commonJS({
    "node_modules/es-errors/syntax.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      module.exports = SyntaxError;
    }
  });

  // node_modules/es-errors/uri.js
  var require_uri = __commonJS({
    "node_modules/es-errors/uri.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      module.exports = URIError;
    }
  });

  // node_modules/math-intrinsics/abs.js
  var require_abs = __commonJS({
    "node_modules/math-intrinsics/abs.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      module.exports = Math.abs;
    }
  });

  // node_modules/math-intrinsics/floor.js
  var require_floor = __commonJS({
    "node_modules/math-intrinsics/floor.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      module.exports = Math.floor;
    }
  });

  // node_modules/math-intrinsics/max.js
  var require_max = __commonJS({
    "node_modules/math-intrinsics/max.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      module.exports = Math.max;
    }
  });

  // node_modules/math-intrinsics/min.js
  var require_min = __commonJS({
    "node_modules/math-intrinsics/min.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      module.exports = Math.min;
    }
  });

  // node_modules/math-intrinsics/pow.js
  var require_pow = __commonJS({
    "node_modules/math-intrinsics/pow.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      module.exports = Math.pow;
    }
  });

  // node_modules/math-intrinsics/round.js
  var require_round = __commonJS({
    "node_modules/math-intrinsics/round.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      module.exports = Math.round;
    }
  });

  // node_modules/math-intrinsics/isNaN.js
  var require_isNaN = __commonJS({
    "node_modules/math-intrinsics/isNaN.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      module.exports = Number.isNaN || function(a) {
        return a !== a;
      };
    }
  });

  // node_modules/math-intrinsics/sign.js
  var require_sign = __commonJS({
    "node_modules/math-intrinsics/sign.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      var $isNaN = require_isNaN();
      module.exports = function(number) {
        return $isNaN(number) || number === 0 ? number : number < 0 ? -1 : 1;
      };
    }
  });

  // node_modules/gopd/gOPD.js
  var require_gOPD = __commonJS({
    "node_modules/gopd/gOPD.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      module.exports = Object.getOwnPropertyDescriptor;
    }
  });

  // node_modules/gopd/index.js
  var require_gopd = __commonJS({
    "node_modules/gopd/index.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      var $gOPD = require_gOPD();
      if ($gOPD)
        try {
          $gOPD([], "length");
        } catch {
          $gOPD = null;
        }
      module.exports = $gOPD;
    }
  });

  // node_modules/es-define-property/index.js
  var require_es_define_property = __commonJS({
    "node_modules/es-define-property/index.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      var $defineProperty = Object.defineProperty || !1;
      if ($defineProperty)
        try {
          $defineProperty({}, "a", { value: 1 });
        } catch {
          $defineProperty = !1;
        }
      module.exports = $defineProperty;
    }
  });

  // node_modules/has-symbols/shams.js
  var require_shams = __commonJS({
    "node_modules/has-symbols/shams.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      module.exports = function() {
        if (typeof Symbol != "function" || typeof Object.getOwnPropertySymbols != "function")
          return !1;
        if (typeof Symbol.iterator == "symbol")
          return !0;
        var obj = {}, sym = /* @__PURE__ */ Symbol("test"), symObj = Object(sym);
        if (typeof sym == "string" || Object.prototype.toString.call(sym) !== "[object Symbol]" || Object.prototype.toString.call(symObj) !== "[object Symbol]")
          return !1;
        var symVal = 42;
        obj[sym] = symVal;
        for (var _ in obj)
          return !1;
        if (typeof Object.keys == "function" && Object.keys(obj).length !== 0 || typeof Object.getOwnPropertyNames == "function" && Object.getOwnPropertyNames(obj).length !== 0)
          return !1;
        var syms = Object.getOwnPropertySymbols(obj);
        if (syms.length !== 1 || syms[0] !== sym || !Object.prototype.propertyIsEnumerable.call(obj, sym))
          return !1;
        if (typeof Object.getOwnPropertyDescriptor == "function") {
          var descriptor = (
            /** @type {PropertyDescriptor} */
            Object.getOwnPropertyDescriptor(obj, sym)
          );
          if (descriptor.value !== symVal || descriptor.enumerable !== !0)
            return !1;
        }
        return !0;
      };
    }
  });

  // node_modules/has-symbols/index.js
  var require_has_symbols = __commonJS({
    "node_modules/has-symbols/index.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      var origSymbol = typeof Symbol < "u" && Symbol, hasSymbolSham = require_shams();
      module.exports = function() {
        return typeof origSymbol != "function" || typeof Symbol != "function" || typeof origSymbol("foo") != "symbol" || typeof /* @__PURE__ */ Symbol("bar") != "symbol" ? !1 : hasSymbolSham();
      };
    }
  });

  // node_modules/get-proto/Reflect.getPrototypeOf.js
  var require_Reflect_getPrototypeOf = __commonJS({
    "node_modules/get-proto/Reflect.getPrototypeOf.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      module.exports = typeof Reflect < "u" && Reflect.getPrototypeOf || null;
    }
  });

  // node_modules/get-proto/Object.getPrototypeOf.js
  var require_Object_getPrototypeOf = __commonJS({
    "node_modules/get-proto/Object.getPrototypeOf.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      var $Object = require_es_object_atoms();
      module.exports = $Object.getPrototypeOf || null;
    }
  });

  // node_modules/function-bind/implementation.js
  var require_implementation = __commonJS({
    "node_modules/function-bind/implementation.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      var ERROR_MESSAGE = "Function.prototype.bind called on incompatible ", toStr = Object.prototype.toString, max = Math.max, funcType = "[object Function]", concatty = function(a, b) {
        for (var arr = [], i = 0; i < a.length; i += 1)
          arr[i] = a[i];
        for (var j = 0; j < b.length; j += 1)
          arr[j + a.length] = b[j];
        return arr;
      }, slicy = function(arrLike, offset) {
        for (var arr = [], i = offset || 0, j = 0; i < arrLike.length; i += 1, j += 1)
          arr[j] = arrLike[i];
        return arr;
      }, joiny = function(arr, joiner) {
        for (var str = "", i = 0; i < arr.length; i += 1)
          str += arr[i], i + 1 < arr.length && (str += joiner);
        return str;
      };
      module.exports = function(that) {
        var target = this;
        if (typeof target != "function" || toStr.apply(target) !== funcType)
          throw new TypeError(ERROR_MESSAGE + target);
        for (var args = slicy(arguments, 1), bound, binder = function() {
          if (this instanceof bound) {
            var result = target.apply(
              this,
              concatty(args, arguments)
            );
            return Object(result) === result ? result : this;
          }
          return target.apply(
            that,
            concatty(args, arguments)
          );
        }, boundLength = max(0, target.length - args.length), boundArgs = [], i = 0; i < boundLength; i++)
          boundArgs[i] = "$" + i;
        if (bound = Function("binder", "return function (" + joiny(boundArgs, ",") + "){ return binder.apply(this,arguments); }")(binder), target.prototype) {
          var Empty = function() {
          };
          Empty.prototype = target.prototype, bound.prototype = new Empty(), Empty.prototype = null;
        }
        return bound;
      };
    }
  });

  // node_modules/function-bind/index.js
  var require_function_bind = __commonJS({
    "node_modules/function-bind/index.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      var implementation = require_implementation();
      module.exports = Function.prototype.bind || implementation;
    }
  });

  // node_modules/call-bind-apply-helpers/functionCall.js
  var require_functionCall = __commonJS({
    "node_modules/call-bind-apply-helpers/functionCall.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      module.exports = Function.prototype.call;
    }
  });

  // node_modules/call-bind-apply-helpers/functionApply.js
  var require_functionApply = __commonJS({
    "node_modules/call-bind-apply-helpers/functionApply.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      module.exports = Function.prototype.apply;
    }
  });

  // node_modules/call-bind-apply-helpers/reflectApply.js
  var require_reflectApply = __commonJS({
    "node_modules/call-bind-apply-helpers/reflectApply.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      module.exports = typeof Reflect < "u" && Reflect && Reflect.apply;
    }
  });

  // node_modules/call-bind-apply-helpers/actualApply.js
  var require_actualApply = __commonJS({
    "node_modules/call-bind-apply-helpers/actualApply.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      var bind = require_function_bind(), $apply = require_functionApply(), $call = require_functionCall(), $reflectApply = require_reflectApply();
      module.exports = $reflectApply || bind.call($call, $apply);
    }
  });

  // node_modules/call-bind-apply-helpers/index.js
  var require_call_bind_apply_helpers = __commonJS({
    "node_modules/call-bind-apply-helpers/index.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      var bind = require_function_bind(), $TypeError = require_type(), $call = require_functionCall(), $actualApply = require_actualApply();
      module.exports = function(args) {
        if (args.length < 1 || typeof args[0] != "function")
          throw new $TypeError("a function is required");
        return $actualApply(bind, $call, args);
      };
    }
  });

  // node_modules/dunder-proto/get.js
  var require_get = __commonJS({
    "node_modules/dunder-proto/get.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      var callBind = require_call_bind_apply_helpers(), gOPD = require_gopd(), hasProtoAccessor;
      try {
        hasProtoAccessor = /** @type {{ __proto__?: typeof Array.prototype }} */
        [].__proto__ === Array.prototype;
      } catch (e) {
        if (!e || typeof e != "object" || !("code" in e) || e.code !== "ERR_PROTO_ACCESS")
          throw e;
      }
      var desc = !!hasProtoAccessor && gOPD && gOPD(
        Object.prototype,
        /** @type {keyof typeof Object.prototype} */
        "__proto__"
      ), $Object = Object, $getPrototypeOf = $Object.getPrototypeOf;
      module.exports = desc && typeof desc.get == "function" ? callBind([desc.get]) : typeof $getPrototypeOf == "function" ? (
        /** @type {import('./get')} */
        function(value) {
          return $getPrototypeOf(value == null ? value : $Object(value));
        }
      ) : !1;
    }
  });

  // node_modules/get-proto/index.js
  var require_get_proto = __commonJS({
    "node_modules/get-proto/index.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      var reflectGetProto = require_Reflect_getPrototypeOf(), originalGetProto = require_Object_getPrototypeOf(), getDunderProto = require_get();
      module.exports = reflectGetProto ? function(O) {
        return reflectGetProto(O);
      } : originalGetProto ? function(O) {
        if (!O || typeof O != "object" && typeof O != "function")
          throw new TypeError("getProto: not an object");
        return originalGetProto(O);
      } : getDunderProto ? function(O) {
        return getDunderProto(O);
      } : null;
    }
  });

  // node_modules/hasown/index.js
  var require_hasown = __commonJS({
    "node_modules/hasown/index.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      var call = Function.prototype.call, $hasOwn = Object.prototype.hasOwnProperty, bind = require_function_bind();
      module.exports = bind.call(call, $hasOwn);
    }
  });

  // node_modules/get-intrinsic/index.js
  var require_get_intrinsic = __commonJS({
    "node_modules/get-intrinsic/index.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      var undefined2, $Object = require_es_object_atoms(), $Error = require_es_errors(), $EvalError = require_eval(), $RangeError = require_range(), $ReferenceError = require_ref(), $SyntaxError = require_syntax(), $TypeError = require_type(), $URIError = require_uri(), abs = require_abs(), floor = require_floor(), max = require_max(), min = require_min(), pow = require_pow(), round = require_round(), sign = require_sign(), $Function = Function, getEvalledConstructor = function(expressionSyntax) {
        try {
          return $Function('"use strict"; return (' + expressionSyntax + ").constructor;")();
        } catch {
        }
      }, $gOPD = require_gopd(), $defineProperty = require_es_define_property(), throwTypeError = function() {
        throw new $TypeError();
      }, ThrowTypeError = $gOPD ? (function() {
        try {
          return arguments.callee, throwTypeError;
        } catch {
          try {
            return $gOPD(arguments, "callee").get;
          } catch {
            return throwTypeError;
          }
        }
      })() : throwTypeError, hasSymbols = require_has_symbols()(), getProto = require_get_proto(), $ObjectGPO = require_Object_getPrototypeOf(), $ReflectGPO = require_Reflect_getPrototypeOf(), $apply = require_functionApply(), $call = require_functionCall(), needsEval = {}, TypedArray = typeof Uint8Array > "u" || !getProto ? undefined2 : getProto(Uint8Array), INTRINSICS = {
        __proto__: null,
        "%AggregateError%": typeof AggregateError > "u" ? undefined2 : AggregateError,
        "%Array%": Array,
        "%ArrayBuffer%": typeof ArrayBuffer > "u" ? undefined2 : ArrayBuffer,
        "%ArrayIteratorPrototype%": hasSymbols && getProto ? getProto([][Symbol.iterator]()) : undefined2,
        "%AsyncFromSyncIteratorPrototype%": undefined2,
        "%AsyncFunction%": needsEval,
        "%AsyncGenerator%": needsEval,
        "%AsyncGeneratorFunction%": needsEval,
        "%AsyncIteratorPrototype%": needsEval,
        "%Atomics%": typeof Atomics > "u" ? undefined2 : Atomics,
        "%BigInt%": typeof BigInt > "u" ? undefined2 : BigInt,
        "%BigInt64Array%": typeof BigInt64Array > "u" ? undefined2 : BigInt64Array,
        "%BigUint64Array%": typeof BigUint64Array > "u" ? undefined2 : BigUint64Array,
        "%Boolean%": Boolean,
        "%DataView%": typeof DataView > "u" ? undefined2 : DataView,
        "%Date%": Date,
        "%decodeURI%": decodeURI,
        "%decodeURIComponent%": decodeURIComponent,
        "%encodeURI%": encodeURI,
        "%encodeURIComponent%": encodeURIComponent,
        "%Error%": $Error,
        "%eval%": eval,
        // eslint-disable-line no-eval
        "%EvalError%": $EvalError,
        "%Float16Array%": typeof Float16Array > "u" ? undefined2 : Float16Array,
        "%Float32Array%": typeof Float32Array > "u" ? undefined2 : Float32Array,
        "%Float64Array%": typeof Float64Array > "u" ? undefined2 : Float64Array,
        "%FinalizationRegistry%": typeof FinalizationRegistry > "u" ? undefined2 : FinalizationRegistry,
        "%Function%": $Function,
        "%GeneratorFunction%": needsEval,
        "%Int8Array%": typeof Int8Array > "u" ? undefined2 : Int8Array,
        "%Int16Array%": typeof Int16Array > "u" ? undefined2 : Int16Array,
        "%Int32Array%": typeof Int32Array > "u" ? undefined2 : Int32Array,
        "%isFinite%": isFinite,
        "%isNaN%": isNaN,
        "%IteratorPrototype%": hasSymbols && getProto ? getProto(getProto([][Symbol.iterator]())) : undefined2,
        "%JSON%": typeof JSON == "object" ? JSON : undefined2,
        "%Map%": typeof Map > "u" ? undefined2 : Map,
        "%MapIteratorPrototype%": typeof Map > "u" || !hasSymbols || !getProto ? undefined2 : getProto((/* @__PURE__ */ new Map())[Symbol.iterator]()),
        "%Math%": Math,
        "%Number%": Number,
        "%Object%": $Object,
        "%Object.getOwnPropertyDescriptor%": $gOPD,
        "%parseFloat%": parseFloat,
        "%parseInt%": parseInt,
        "%Promise%": typeof Promise > "u" ? undefined2 : Promise,
        "%Proxy%": typeof Proxy > "u" ? undefined2 : Proxy,
        "%RangeError%": $RangeError,
        "%ReferenceError%": $ReferenceError,
        "%Reflect%": typeof Reflect > "u" ? undefined2 : Reflect,
        "%RegExp%": RegExp,
        "%Set%": typeof Set > "u" ? undefined2 : Set,
        "%SetIteratorPrototype%": typeof Set > "u" || !hasSymbols || !getProto ? undefined2 : getProto((/* @__PURE__ */ new Set())[Symbol.iterator]()),
        "%SharedArrayBuffer%": typeof SharedArrayBuffer > "u" ? undefined2 : SharedArrayBuffer,
        "%String%": String,
        "%StringIteratorPrototype%": hasSymbols && getProto ? getProto(""[Symbol.iterator]()) : undefined2,
        "%Symbol%": hasSymbols ? Symbol : undefined2,
        "%SyntaxError%": $SyntaxError,
        "%ThrowTypeError%": ThrowTypeError,
        "%TypedArray%": TypedArray,
        "%TypeError%": $TypeError,
        "%Uint8Array%": typeof Uint8Array > "u" ? undefined2 : Uint8Array,
        "%Uint8ClampedArray%": typeof Uint8ClampedArray > "u" ? undefined2 : Uint8ClampedArray,
        "%Uint16Array%": typeof Uint16Array > "u" ? undefined2 : Uint16Array,
        "%Uint32Array%": typeof Uint32Array > "u" ? undefined2 : Uint32Array,
        "%URIError%": $URIError,
        "%WeakMap%": typeof WeakMap > "u" ? undefined2 : WeakMap,
        "%WeakRef%": typeof WeakRef > "u" ? undefined2 : WeakRef,
        "%WeakSet%": typeof WeakSet > "u" ? undefined2 : WeakSet,
        "%Function.prototype.call%": $call,
        "%Function.prototype.apply%": $apply,
        "%Object.defineProperty%": $defineProperty,
        "%Object.getPrototypeOf%": $ObjectGPO,
        "%Math.abs%": abs,
        "%Math.floor%": floor,
        "%Math.max%": max,
        "%Math.min%": min,
        "%Math.pow%": pow,
        "%Math.round%": round,
        "%Math.sign%": sign,
        "%Reflect.getPrototypeOf%": $ReflectGPO
      };
      if (getProto)
        try {
          null.error;
        } catch (e) {
          errorProto = getProto(getProto(e)), INTRINSICS["%Error.prototype%"] = errorProto;
        }
      var errorProto, doEval = function doEval2(name) {
        var value;
        if (name === "%AsyncFunction%")
          value = getEvalledConstructor("async function () {}");
        else if (name === "%GeneratorFunction%")
          value = getEvalledConstructor("function* () {}");
        else if (name === "%AsyncGeneratorFunction%")
          value = getEvalledConstructor("async function* () {}");
        else if (name === "%AsyncGenerator%") {
          var fn = doEval2("%AsyncGeneratorFunction%");
          fn && (value = fn.prototype);
        } else if (name === "%AsyncIteratorPrototype%") {
          var gen = doEval2("%AsyncGenerator%");
          gen && getProto && (value = getProto(gen.prototype));
        }
        return INTRINSICS[name] = value, value;
      }, LEGACY_ALIASES = {
        __proto__: null,
        "%ArrayBufferPrototype%": ["ArrayBuffer", "prototype"],
        "%ArrayPrototype%": ["Array", "prototype"],
        "%ArrayProto_entries%": ["Array", "prototype", "entries"],
        "%ArrayProto_forEach%": ["Array", "prototype", "forEach"],
        "%ArrayProto_keys%": ["Array", "prototype", "keys"],
        "%ArrayProto_values%": ["Array", "prototype", "values"],
        "%AsyncFunctionPrototype%": ["AsyncFunction", "prototype"],
        "%AsyncGenerator%": ["AsyncGeneratorFunction", "prototype"],
        "%AsyncGeneratorPrototype%": ["AsyncGeneratorFunction", "prototype", "prototype"],
        "%BooleanPrototype%": ["Boolean", "prototype"],
        "%DataViewPrototype%": ["DataView", "prototype"],
        "%DatePrototype%": ["Date", "prototype"],
        "%ErrorPrototype%": ["Error", "prototype"],
        "%EvalErrorPrototype%": ["EvalError", "prototype"],
        "%Float32ArrayPrototype%": ["Float32Array", "prototype"],
        "%Float64ArrayPrototype%": ["Float64Array", "prototype"],
        "%FunctionPrototype%": ["Function", "prototype"],
        "%Generator%": ["GeneratorFunction", "prototype"],
        "%GeneratorPrototype%": ["GeneratorFunction", "prototype", "prototype"],
        "%Int8ArrayPrototype%": ["Int8Array", "prototype"],
        "%Int16ArrayPrototype%": ["Int16Array", "prototype"],
        "%Int32ArrayPrototype%": ["Int32Array", "prototype"],
        "%JSONParse%": ["JSON", "parse"],
        "%JSONStringify%": ["JSON", "stringify"],
        "%MapPrototype%": ["Map", "prototype"],
        "%NumberPrototype%": ["Number", "prototype"],
        "%ObjectPrototype%": ["Object", "prototype"],
        "%ObjProto_toString%": ["Object", "prototype", "toString"],
        "%ObjProto_valueOf%": ["Object", "prototype", "valueOf"],
        "%PromisePrototype%": ["Promise", "prototype"],
        "%PromiseProto_then%": ["Promise", "prototype", "then"],
        "%Promise_all%": ["Promise", "all"],
        "%Promise_reject%": ["Promise", "reject"],
        "%Promise_resolve%": ["Promise", "resolve"],
        "%RangeErrorPrototype%": ["RangeError", "prototype"],
        "%ReferenceErrorPrototype%": ["ReferenceError", "prototype"],
        "%RegExpPrototype%": ["RegExp", "prototype"],
        "%SetPrototype%": ["Set", "prototype"],
        "%SharedArrayBufferPrototype%": ["SharedArrayBuffer", "prototype"],
        "%StringPrototype%": ["String", "prototype"],
        "%SymbolPrototype%": ["Symbol", "prototype"],
        "%SyntaxErrorPrototype%": ["SyntaxError", "prototype"],
        "%TypedArrayPrototype%": ["TypedArray", "prototype"],
        "%TypeErrorPrototype%": ["TypeError", "prototype"],
        "%Uint8ArrayPrototype%": ["Uint8Array", "prototype"],
        "%Uint8ClampedArrayPrototype%": ["Uint8ClampedArray", "prototype"],
        "%Uint16ArrayPrototype%": ["Uint16Array", "prototype"],
        "%Uint32ArrayPrototype%": ["Uint32Array", "prototype"],
        "%URIErrorPrototype%": ["URIError", "prototype"],
        "%WeakMapPrototype%": ["WeakMap", "prototype"],
        "%WeakSetPrototype%": ["WeakSet", "prototype"]
      }, bind = require_function_bind(), hasOwn = require_hasown(), $concat = bind.call($call, Array.prototype.concat), $spliceApply = bind.call($apply, Array.prototype.splice), $replace = bind.call($call, String.prototype.replace), $strSlice = bind.call($call, String.prototype.slice), $exec = bind.call($call, RegExp.prototype.exec), rePropName = /[^%.[\]]+|\[(?:(-?\d+(?:\.\d+)?)|(["'])((?:(?!\2)[^\\]|\\.)*?)\2)\]|(?=(?:\.|\[\])(?:\.|\[\]|%$))/g, reEscapeChar = /\\(\\)?/g, stringToPath = function(string) {
        var first = $strSlice(string, 0, 1), last = $strSlice(string, -1);
        if (first === "%" && last !== "%")
          throw new $SyntaxError("invalid intrinsic syntax, expected closing `%`");
        if (last === "%" && first !== "%")
          throw new $SyntaxError("invalid intrinsic syntax, expected opening `%`");
        var result = [];
        return $replace(string, rePropName, function(match, number, quote, subString) {
          result[result.length] = quote ? $replace(subString, reEscapeChar, "$1") : number || match;
        }), result;
      }, getBaseIntrinsic = function(name, allowMissing) {
        var intrinsicName = name, alias;
        if (hasOwn(LEGACY_ALIASES, intrinsicName) && (alias = LEGACY_ALIASES[intrinsicName], intrinsicName = "%" + alias[0] + "%"), hasOwn(INTRINSICS, intrinsicName)) {
          var value = INTRINSICS[intrinsicName];
          if (value === needsEval && (value = doEval(intrinsicName)), typeof value > "u" && !allowMissing)
            throw new $TypeError("intrinsic " + name + " exists, but is not available. Please file an issue!");
          return {
            alias,
            name: intrinsicName,
            value
          };
        }
        throw new $SyntaxError("intrinsic " + name + " does not exist!");
      };
      module.exports = function(name, allowMissing) {
        if (typeof name != "string" || name.length === 0)
          throw new $TypeError("intrinsic name must be a non-empty string");
        if (arguments.length > 1 && typeof allowMissing != "boolean")
          throw new $TypeError('"allowMissing" argument must be a boolean');
        if ($exec(/^%?[^%]*%?$/, name) === null)
          throw new $SyntaxError("`%` may not be present anywhere but at the beginning and end of the intrinsic name");
        var parts = stringToPath(name), intrinsicBaseName = parts.length > 0 ? parts[0] : "", intrinsic = getBaseIntrinsic("%" + intrinsicBaseName + "%", allowMissing), intrinsicRealName = intrinsic.name, value = intrinsic.value, skipFurtherCaching = !1, alias = intrinsic.alias;
        alias && (intrinsicBaseName = alias[0], $spliceApply(parts, $concat([0, 1], alias)));
        for (var i = 1, isOwn = !0; i < parts.length; i += 1) {
          var part = parts[i], first = $strSlice(part, 0, 1), last = $strSlice(part, -1);
          if ((first === '"' || first === "'" || first === "`" || last === '"' || last === "'" || last === "`") && first !== last)
            throw new $SyntaxError("property names with quotes must have matching quotes");
          if ((part === "constructor" || !isOwn) && (skipFurtherCaching = !0), intrinsicBaseName += "." + part, intrinsicRealName = "%" + intrinsicBaseName + "%", hasOwn(INTRINSICS, intrinsicRealName))
            value = INTRINSICS[intrinsicRealName];
          else if (value != null) {
            if (!(part in value)) {
              if (!allowMissing)
                throw new $TypeError("base intrinsic for " + name + " exists, but the property is not available.");
              return;
            }
            if ($gOPD && i + 1 >= parts.length) {
              var desc = $gOPD(value, part);
              isOwn = !!desc, isOwn && "get" in desc && !("originalValue" in desc.get) ? value = desc.get : value = value[part];
            } else
              isOwn = hasOwn(value, part), value = value[part];
            isOwn && !skipFurtherCaching && (INTRINSICS[intrinsicRealName] = value);
          }
        }
        return value;
      };
    }
  });

  // node_modules/call-bound/index.js
  var require_call_bound = __commonJS({
    "node_modules/call-bound/index.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      var GetIntrinsic = require_get_intrinsic(), callBindBasic = require_call_bind_apply_helpers(), $indexOf = callBindBasic([GetIntrinsic("%String.prototype.indexOf%")]);
      module.exports = function(name, allowMissing) {
        var intrinsic = (
          /** @type {(this: unknown, ...args: unknown[]) => unknown} */
          GetIntrinsic(name, !!allowMissing)
        );
        return typeof intrinsic == "function" && $indexOf(name, ".prototype.") > -1 ? callBindBasic(
          /** @type {const} */
          [intrinsic]
        ) : intrinsic;
      };
    }
  });

  // node_modules/is-callable/index.js
  var require_is_callable = __commonJS({
    "node_modules/is-callable/index.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      var fnToStr = Function.prototype.toString, reflectApply = typeof Reflect == "object" && Reflect !== null && Reflect.apply, badArrayLike, isCallableMarker;
      if (typeof reflectApply == "function" && typeof Object.defineProperty == "function")
        try {
          badArrayLike = Object.defineProperty({}, "length", {
            get: function() {
              throw isCallableMarker;
            }
          }), isCallableMarker = {}, reflectApply(function() {
            throw 42;
          }, null, badArrayLike);
        } catch (_) {
          _ !== isCallableMarker && (reflectApply = null);
        }
      else
        reflectApply = null;
      var constructorRegex = /^\s*class\b/, isES6ClassFn = function(value) {
        try {
          var fnStr = fnToStr.call(value);
          return constructorRegex.test(fnStr);
        } catch {
          return !1;
        }
      }, tryFunctionObject = function(value) {
        try {
          return isES6ClassFn(value) ? !1 : (fnToStr.call(value), !0);
        } catch {
          return !1;
        }
      }, toStr = Object.prototype.toString, objectClass = "[object Object]", fnClass = "[object Function]", genClass = "[object GeneratorFunction]", ddaClass = "[object HTMLAllCollection]", ddaClass2 = "[object HTML document.all class]", ddaClass3 = "[object HTMLCollection]", hasToStringTag = typeof Symbol == "function" && !!Symbol.toStringTag, isIE68 = !(0 in [,]), isDDA = function() {
        return !1;
      };
      typeof document == "object" && (all = document.all, toStr.call(all) === toStr.call(document.all) && (isDDA = function(value) {
        if ((isIE68 || !value) && (typeof value > "u" || typeof value == "object"))
          try {
            var str = toStr.call(value);
            return (str === ddaClass || str === ddaClass2 || str === ddaClass3 || str === objectClass) && value("") == null;
          } catch {
          }
        return !1;
      }));
      var all;
      module.exports = reflectApply ? function(value) {
        if (isDDA(value))
          return !0;
        if (!value || typeof value != "function" && typeof value != "object")
          return !1;
        try {
          reflectApply(value, null, badArrayLike);
        } catch (e) {
          if (e !== isCallableMarker)
            return !1;
        }
        return !isES6ClassFn(value) && tryFunctionObject(value);
      } : function(value) {
        if (isDDA(value))
          return !0;
        if (!value || typeof value != "function" && typeof value != "object")
          return !1;
        if (hasToStringTag)
          return tryFunctionObject(value);
        if (isES6ClassFn(value))
          return !1;
        var strClass = toStr.call(value);
        return strClass !== fnClass && strClass !== genClass && !/^\[object HTML/.test(strClass) ? !1 : tryFunctionObject(value);
      };
    }
  });

  // node_modules/for-each/index.js
  var require_for_each = __commonJS({
    "node_modules/for-each/index.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      var isCallable = require_is_callable(), toStr = Object.prototype.toString, hasOwnProperty = Object.prototype.hasOwnProperty, forEachArray = function(array, iterator, receiver) {
        for (var i = 0, len = array.length; i < len; i++)
          hasOwnProperty.call(array, i) && (receiver == null ? iterator(array[i], i, array) : iterator.call(receiver, array[i], i, array));
      }, forEachString = function(string, iterator, receiver) {
        for (var i = 0, len = string.length; i < len; i++)
          receiver == null ? iterator(string.charAt(i), i, string) : iterator.call(receiver, string.charAt(i), i, string);
      }, forEachObject = function(object, iterator, receiver) {
        for (var k in object)
          hasOwnProperty.call(object, k) && (receiver == null ? iterator(object[k], k, object) : iterator.call(receiver, object[k], k, object));
      };
      function isArray(x) {
        return toStr.call(x) === "[object Array]";
      }
      module.exports = function(list, iterator, thisArg) {
        if (!isCallable(iterator))
          throw new TypeError("iterator must be a function");
        var receiver;
        arguments.length >= 3 && (receiver = thisArg), isArray(list) ? forEachArray(list, iterator, receiver) : typeof list == "string" ? forEachString(list, iterator, receiver) : forEachObject(list, iterator, receiver);
      };
    }
  });

  // node_modules/possible-typed-array-names/index.js
  var require_possible_typed_array_names = __commonJS({
    "node_modules/possible-typed-array-names/index.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      module.exports = [
        "Float16Array",
        "Float32Array",
        "Float64Array",
        "Int8Array",
        "Int16Array",
        "Int32Array",
        "Uint8Array",
        "Uint8ClampedArray",
        "Uint16Array",
        "Uint32Array",
        "BigInt64Array",
        "BigUint64Array"
      ];
    }
  });

  // node_modules/available-typed-arrays/index.js
  var require_available_typed_arrays = __commonJS({
    "node_modules/available-typed-arrays/index.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      var possibleNames = require_possible_typed_array_names(), g = globalThis;
      module.exports = function() {
        for (var out = [], i = 0; i < possibleNames.length; i++)
          typeof g[possibleNames[i]] == "function" && (out[out.length] = possibleNames[i]);
        return out;
      };
    }
  });

  // node_modules/define-data-property/index.js
  var require_define_data_property = __commonJS({
    "node_modules/define-data-property/index.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      var $defineProperty = require_es_define_property(), $SyntaxError = require_syntax(), $TypeError = require_type(), gopd = require_gopd();
      module.exports = function(obj, property, value) {
        if (!obj || typeof obj != "object" && typeof obj != "function")
          throw new $TypeError("`obj` must be an object or a function`");
        if (typeof property != "string" && typeof property != "symbol")
          throw new $TypeError("`property` must be a string or a symbol`");
        if (arguments.length > 3 && typeof arguments[3] != "boolean" && arguments[3] !== null)
          throw new $TypeError("`nonEnumerable`, if provided, must be a boolean or null");
        if (arguments.length > 4 && typeof arguments[4] != "boolean" && arguments[4] !== null)
          throw new $TypeError("`nonWritable`, if provided, must be a boolean or null");
        if (arguments.length > 5 && typeof arguments[5] != "boolean" && arguments[5] !== null)
          throw new $TypeError("`nonConfigurable`, if provided, must be a boolean or null");
        if (arguments.length > 6 && typeof arguments[6] != "boolean")
          throw new $TypeError("`loose`, if provided, must be a boolean");
        var nonEnumerable = arguments.length > 3 ? arguments[3] : null, nonWritable = arguments.length > 4 ? arguments[4] : null, nonConfigurable = arguments.length > 5 ? arguments[5] : null, loose = arguments.length > 6 ? arguments[6] : !1, desc = !!gopd && gopd(obj, property);
        if ($defineProperty)
          $defineProperty(obj, property, {
            configurable: nonConfigurable === null && desc ? desc.configurable : !nonConfigurable,
            enumerable: nonEnumerable === null && desc ? desc.enumerable : !nonEnumerable,
            value,
            writable: nonWritable === null && desc ? desc.writable : !nonWritable
          });
        else if (loose || !nonEnumerable && !nonWritable && !nonConfigurable)
          obj[property] = value;
        else
          throw new $SyntaxError("This environment does not support defining a property as non-configurable, non-writable, or non-enumerable.");
      };
    }
  });

  // node_modules/has-property-descriptors/index.js
  var require_has_property_descriptors = __commonJS({
    "node_modules/has-property-descriptors/index.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      var $defineProperty = require_es_define_property(), hasPropertyDescriptors = function() {
        return !!$defineProperty;
      };
      hasPropertyDescriptors.hasArrayLengthDefineBug = function() {
        if (!$defineProperty)
          return null;
        try {
          return $defineProperty([], "length", { value: 1 }).length !== 1;
        } catch {
          return !0;
        }
      };
      module.exports = hasPropertyDescriptors;
    }
  });

  // node_modules/set-function-length/index.js
  var require_set_function_length = __commonJS({
    "node_modules/set-function-length/index.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      var GetIntrinsic = require_get_intrinsic(), define = require_define_data_property(), hasDescriptors = require_has_property_descriptors()(), gOPD = require_gopd(), $TypeError = require_type(), $floor = GetIntrinsic("%Math.floor%");
      module.exports = function(fn, length) {
        if (typeof fn != "function")
          throw new $TypeError("`fn` is not a function");
        if (typeof length != "number" || length < 0 || length > 4294967295 || $floor(length) !== length)
          throw new $TypeError("`length` must be a positive 32-bit integer");
        var loose = arguments.length > 2 && !!arguments[2], functionLengthIsConfigurable = !0, functionLengthIsWritable = !0;
        if ("length" in fn && gOPD) {
          var desc = gOPD(fn, "length");
          desc && !desc.configurable && (functionLengthIsConfigurable = !1), desc && !desc.writable && (functionLengthIsWritable = !1);
        }
        return (functionLengthIsConfigurable || functionLengthIsWritable || !loose) && (hasDescriptors ? define(
          /** @type {Parameters<define>[0]} */
          fn,
          "length",
          length,
          !0,
          !0
        ) : define(
          /** @type {Parameters<define>[0]} */
          fn,
          "length",
          length
        )), fn;
      };
    }
  });

  // node_modules/call-bind-apply-helpers/applyBind.js
  var require_applyBind = __commonJS({
    "node_modules/call-bind-apply-helpers/applyBind.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      var bind = require_function_bind(), $apply = require_functionApply(), actualApply = require_actualApply();
      module.exports = function() {
        return actualApply(bind, $apply, arguments);
      };
    }
  });

  // node_modules/call-bind/index.js
  var require_call_bind = __commonJS({
    "node_modules/call-bind/index.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      var setFunctionLength = require_set_function_length(), $defineProperty = require_es_define_property(), callBindBasic = require_call_bind_apply_helpers(), applyBind = require_applyBind();
      module.exports = function(originalFunction) {
        var func = callBindBasic(arguments), adjustedLength = 1 + originalFunction.length - (arguments.length - 1);
        return setFunctionLength(
          func,
          adjustedLength > 0 ? adjustedLength : 0,
          !0
        );
      };
      $defineProperty ? $defineProperty(module.exports, "apply", { value: applyBind }) : module.exports.apply = applyBind;
    }
  });

  // node_modules/has-tostringtag/shams.js
  var require_shams2 = __commonJS({
    "node_modules/has-tostringtag/shams.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      var hasSymbols = require_shams();
      module.exports = function() {
        return hasSymbols() && !!Symbol.toStringTag;
      };
    }
  });

  // node_modules/which-typed-array/index.js
  var require_which_typed_array = __commonJS({
    "node_modules/which-typed-array/index.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      var forEach = require_for_each(), availableTypedArrays = require_available_typed_arrays(), callBind = require_call_bind(), callBound = require_call_bound(), gOPD = require_gopd(), getProto = require_get_proto(), $toString = callBound("Object.prototype.toString"), hasToStringTag = require_shams2()(), g = globalThis, typedArrays = availableTypedArrays(), $slice = callBound("String.prototype.slice"), $indexOf = callBound("Array.prototype.indexOf", !0) || function(array, value) {
        for (var i = 0; i < array.length; i += 1)
          if (array[i] === value)
            return i;
        return -1;
      }, cache = { __proto__: null };
      hasToStringTag && gOPD && getProto ? forEach(typedArrays, function(typedArray) {
        var arr = new g[typedArray]();
        if (Symbol.toStringTag in arr && getProto) {
          var proto = getProto(arr), descriptor = gOPD(proto, Symbol.toStringTag);
          if (!descriptor && proto) {
            var superProto = getProto(proto);
            descriptor = gOPD(superProto, Symbol.toStringTag);
          }
          if (descriptor && descriptor.get) {
            var bound = callBind(descriptor.get);
            cache[
              /** @type {`$${TypedArrayName}`} */
              "$" + typedArray
            ] = bound;
          }
        }
      }) : forEach(typedArrays, function(typedArray) {
        var arr = new g[typedArray](), fn = arr.slice || arr.set;
        if (fn) {
          var bound = (
            /** @type {typeof BoundSlice | typeof BoundSet} */
            // @ts-expect-error TODO FIXME
            callBind(fn)
          );
          cache[
            /** @type {`$${TypedArrayName}`} */
            "$" + typedArray
          ] = bound;
        }
      });
      function tryTypedArrays(value) {
        var found = !1;
        return forEach(
          /** @type {Record<`$${TypedArrayName}`, Getter>} */
          cache,
          /** @param {Getter} getter @param {`$${TypedArrayName}`} typedArray */
          function(getter, typedArray) {
            if (!found)
              try {
                "$" + getter(value) === typedArray && (found = /** @type {TypedArrayName} */
                $slice(typedArray, 1));
              } catch {
              }
          }
        ), found;
      }
      function trySlices(value) {
        var found = !1;
        return forEach(
          /** @type {Record<`$${TypedArrayName}`, Getter>} */
          cache,
          /** @param {Getter} getter @param {`$${TypedArrayName}`} name */
          function(getter, name) {
            if (!found)
              try {
                getter(value), found = /** @type {TypedArrayName} */
                $slice(name, 1);
              } catch {
              }
          }
        ), found;
      }
      function isTATag(tag) {
        return $indexOf(typedArrays, tag) > -1;
      }
      function whichTypedArray(value) {
        if (!value || typeof value != "object")
          return !1;
        if (!hasToStringTag) {
          var tag = $slice($toString(value), 8, -1);
          return isTATag(tag) ? tag : tag !== "Object" ? !1 : trySlices(value);
        }
        return gOPD ? tryTypedArrays(value) : null;
      }
      module.exports = whichTypedArray;
    }
  });

  // node_modules/is-typed-array/index.js
  var require_is_typed_array = __commonJS({
    "node_modules/is-typed-array/index.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      var whichTypedArray = require_which_typed_array();
      module.exports = function(value) {
        return !!whichTypedArray(value);
      };
    }
  });

  // node_modules/typed-array-buffer/index.js
  var require_typed_array_buffer = __commonJS({
    "node_modules/typed-array-buffer/index.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      var $TypeError = require_type(), callBound = require_call_bound(), $typedArrayBuffer = callBound("TypedArray.prototype.buffer", !0), isTypedArray = require_is_typed_array();
      module.exports = $typedArrayBuffer || function(x) {
        if (!isTypedArray(x))
          throw new $TypeError("Not a Typed Array");
        return x.buffer;
      };
    }
  });

  // node_modules/to-buffer/index.js
  var require_to_buffer = __commonJS({
    "node_modules/to-buffer/index.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      var Buffer4 = require_safe_buffer().Buffer, isArray = require_isarray(), typedArrayBuffer = require_typed_array_buffer(), isView = ArrayBuffer.isView || function(obj) {
        try {
          return typedArrayBuffer(obj), !0;
        } catch {
          return !1;
        }
      }, useUint8Array = typeof Uint8Array < "u", useArrayBuffer = typeof ArrayBuffer < "u" && typeof Uint8Array < "u", useFromArrayBuffer = useArrayBuffer && (Buffer4.prototype instanceof Uint8Array || Buffer4.TYPED_ARRAY_SUPPORT);
      module.exports = function(data, encoding) {
        if (Buffer4.isBuffer(data))
          return data.constructor && !("isBuffer" in data) ? Buffer4.from(data) : data;
        if (typeof data == "string")
          return Buffer4.from(data, encoding);
        if (useArrayBuffer && isView(data)) {
          if (data.byteLength === 0)
            return Buffer4.alloc(0);
          if (useFromArrayBuffer) {
            var res = Buffer4.from(data.buffer, data.byteOffset, data.byteLength);
            if (res.byteLength === data.byteLength)
              return res;
          }
          var uint8 = data instanceof Uint8Array ? data : new Uint8Array(data.buffer, data.byteOffset, data.byteLength), result = Buffer4.from(uint8);
          if (result.length === data.byteLength)
            return result;
        }
        if (useUint8Array && data instanceof Uint8Array)
          return Buffer4.from(data);
        var isArr = isArray(data);
        if (isArr)
          for (var i = 0; i < data.length; i += 1) {
            var x = data[i];
            if (typeof x != "number" || x < 0 || x > 255 || ~~x !== x)
              throw new RangeError("Array items must be numbers in the range 0-255.");
          }
        if (isArr || Buffer4.isBuffer(data) && data.constructor && typeof data.constructor.isBuffer == "function" && data.constructor.isBuffer(data))
          return Buffer4.from(data);
        throw new TypeError('The "data" argument must be a string, an Array, a Buffer, a Uint8Array, or a DataView.');
      };
    }
  });

  // node_modules/hash-base/to-buffer.js
  var require_to_buffer2 = __commonJS({
    "node_modules/hash-base/to-buffer.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      var Buffer4 = require_safe_buffer().Buffer, toBuffer = require_to_buffer(), useUint8Array = typeof Uint8Array < "u", useArrayBuffer = useUint8Array && typeof ArrayBuffer < "u", isView = useArrayBuffer && ArrayBuffer.isView;
      module.exports = function(thing, encoding) {
        if (typeof thing == "string" || Buffer4.isBuffer(thing) || useUint8Array && thing instanceof Uint8Array || isView && isView(thing))
          return toBuffer(thing, encoding);
        throw new TypeError('The "data" argument must be a string, a Buffer, a Uint8Array, or a DataView');
      };
    }
  });

  // node_modules/process-nextick-args/index.js
  var require_process_nextick_args = __commonJS({
    "node_modules/process-nextick-args/index.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      typeof import_browser.default > "u" || !import_browser.default.version || import_browser.default.version.indexOf("v0.") === 0 || import_browser.default.version.indexOf("v1.") === 0 && import_browser.default.version.indexOf("v1.8.") !== 0 ? module.exports = { nextTick } : module.exports = import_browser.default;
      function nextTick(fn, arg1, arg2, arg3) {
        if (typeof fn != "function")
          throw new TypeError('"callback" argument must be a function');
        var len = arguments.length, args, i;
        switch (len) {
          case 0:
          case 1:
            return import_browser.default.nextTick(fn);
          case 2:
            return import_browser.default.nextTick(function() {
              fn.call(null, arg1);
            });
          case 3:
            return import_browser.default.nextTick(function() {
              fn.call(null, arg1, arg2);
            });
          case 4:
            return import_browser.default.nextTick(function() {
              fn.call(null, arg1, arg2, arg3);
            });
          default:
            for (args = new Array(len - 1), i = 0; i < args.length; )
              args[i++] = arguments[i];
            return import_browser.default.nextTick(function() {
              fn.apply(null, args);
            });
        }
      }
    }
  });

  // node_modules/isarray/index.js
  var require_isarray2 = __commonJS({
    "node_modules/isarray/index.js"(exports, module) {
      init_buffer_shim();
      init_process_shim();
      var toString = {}.toString;
      module.exports = Array.isArray || function(arr) {
        return toString.call(arr) == "[object Array]";
      };
    }
  });

  // node_modules/events/events.js
  var require_events = __commonJS({
    "node_modules/events/events.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      var R = typeof Reflect == "object" ? Reflect : null, ReflectApply = R && typeof R.apply == "function" ? R.apply : function(target, receiver, args) {
        return Function.prototype.apply.call(target, receiver, args);
      }, ReflectOwnKeys;
      R && typeof R.ownKeys == "function" ? ReflectOwnKeys = R.ownKeys : Object.getOwnPropertySymbols ? ReflectOwnKeys = function(target) {
        return Object.getOwnPropertyNames(target).concat(Object.getOwnPropertySymbols(target));
      } : ReflectOwnKeys = function(target) {
        return Object.getOwnPropertyNames(target);
      };
      function ProcessEmitWarning(warning) {
        console && console.warn && console.warn(warning);
      }
      var NumberIsNaN = Number.isNaN || function(value) {
        return value !== value;
      };
      function EventEmitter() {
        EventEmitter.init.call(this);
      }
      module.exports = EventEmitter;
      module.exports.once = once;
      EventEmitter.EventEmitter = EventEmitter;
      EventEmitter.prototype._events = void 0;
      EventEmitter.prototype._eventsCount = 0;
      EventEmitter.prototype._maxListeners = void 0;
      var defaultMaxListeners = 10;
      function checkListener(listener) {
        if (typeof listener != "function")
          throw new TypeError('The "listener" argument must be of type Function. Received type ' + typeof listener);
      }
      Object.defineProperty(EventEmitter, "defaultMaxListeners", {
        enumerable: !0,
        get: function() {
          return defaultMaxListeners;
        },
        set: function(arg) {
          if (typeof arg != "number" || arg < 0 || NumberIsNaN(arg))
            throw new RangeError('The value of "defaultMaxListeners" is out of range. It must be a non-negative number. Received ' + arg + ".");
          defaultMaxListeners = arg;
        }
      });
      EventEmitter.init = function() {
        (this._events === void 0 || this._events === Object.getPrototypeOf(this)._events) && (this._events = /* @__PURE__ */ Object.create(null), this._eventsCount = 0), this._maxListeners = this._maxListeners || void 0;
      };
      EventEmitter.prototype.setMaxListeners = function(n) {
        if (typeof n != "number" || n < 0 || NumberIsNaN(n))
          throw new RangeError('The value of "n" is out of range. It must be a non-negative number. Received ' + n + ".");
        return this._maxListeners = n, this;
      };
      function _getMaxListeners(that) {
        return that._maxListeners === void 0 ? EventEmitter.defaultMaxListeners : that._maxListeners;
      }
      EventEmitter.prototype.getMaxListeners = function() {
        return _getMaxListeners(this);
      };
      EventEmitter.prototype.emit = function(type) {
        for (var args = [], i = 1; i < arguments.length; i++) args.push(arguments[i]);
        var doError = type === "error", events = this._events;
        if (events !== void 0)
          doError = doError && events.error === void 0;
        else if (!doError)
          return !1;
        if (doError) {
          var er;
          if (args.length > 0 && (er = args[0]), er instanceof Error)
            throw er;
          var err = new Error("Unhandled error." + (er ? " (" + er.message + ")" : ""));
          throw err.context = er, err;
        }
        var handler = events[type];
        if (handler === void 0)
          return !1;
        if (typeof handler == "function")
          ReflectApply(handler, this, args);
        else
          for (var len = handler.length, listeners = arrayClone(handler, len), i = 0; i < len; ++i)
            ReflectApply(listeners[i], this, args);
        return !0;
      };
      function _addListener(target, type, listener, prepend) {
        var m, events, existing;
        if (checkListener(listener), events = target._events, events === void 0 ? (events = target._events = /* @__PURE__ */ Object.create(null), target._eventsCount = 0) : (events.newListener !== void 0 && (target.emit(
          "newListener",
          type,
          listener.listener ? listener.listener : listener
        ), events = target._events), existing = events[type]), existing === void 0)
          existing = events[type] = listener, ++target._eventsCount;
        else if (typeof existing == "function" ? existing = events[type] = prepend ? [listener, existing] : [existing, listener] : prepend ? existing.unshift(listener) : existing.push(listener), m = _getMaxListeners(target), m > 0 && existing.length > m && !existing.warned) {
          existing.warned = !0;
          var w = new Error("Possible EventEmitter memory leak detected. " + existing.length + " " + String(type) + " listeners added. Use emitter.setMaxListeners() to increase limit");
          w.name = "MaxListenersExceededWarning", w.emitter = target, w.type = type, w.count = existing.length, ProcessEmitWarning(w);
        }
        return target;
      }
      EventEmitter.prototype.addListener = function(type, listener) {
        return _addListener(this, type, listener, !1);
      };
      EventEmitter.prototype.on = EventEmitter.prototype.addListener;
      EventEmitter.prototype.prependListener = function(type, listener) {
        return _addListener(this, type, listener, !0);
      };
      function onceWrapper() {
        if (!this.fired)
          return this.target.removeListener(this.type, this.wrapFn), this.fired = !0, arguments.length === 0 ? this.listener.call(this.target) : this.listener.apply(this.target, arguments);
      }
      function _onceWrap(target, type, listener) {
        var state = { fired: !1, wrapFn: void 0, target, type, listener }, wrapped = onceWrapper.bind(state);
        return wrapped.listener = listener, state.wrapFn = wrapped, wrapped;
      }
      EventEmitter.prototype.once = function(type, listener) {
        return checkListener(listener), this.on(type, _onceWrap(this, type, listener)), this;
      };
      EventEmitter.prototype.prependOnceListener = function(type, listener) {
        return checkListener(listener), this.prependListener(type, _onceWrap(this, type, listener)), this;
      };
      EventEmitter.prototype.removeListener = function(type, listener) {
        var list, events, position, i, originalListener;
        if (checkListener(listener), events = this._events, events === void 0)
          return this;
        if (list = events[type], list === void 0)
          return this;
        if (list === listener || list.listener === listener)
          --this._eventsCount === 0 ? this._events = /* @__PURE__ */ Object.create(null) : (delete events[type], events.removeListener && this.emit("removeListener", type, list.listener || listener));
        else if (typeof list != "function") {
          for (position = -1, i = list.length - 1; i >= 0; i--)
            if (list[i] === listener || list[i].listener === listener) {
              originalListener = list[i].listener, position = i;
              break;
            }
          if (position < 0)
            return this;
          position === 0 ? list.shift() : spliceOne(list, position), list.length === 1 && (events[type] = list[0]), events.removeListener !== void 0 && this.emit("removeListener", type, originalListener || listener);
        }
        return this;
      };
      EventEmitter.prototype.off = EventEmitter.prototype.removeListener;
      EventEmitter.prototype.removeAllListeners = function(type) {
        var listeners, events, i;
        if (events = this._events, events === void 0)
          return this;
        if (events.removeListener === void 0)
          return arguments.length === 0 ? (this._events = /* @__PURE__ */ Object.create(null), this._eventsCount = 0) : events[type] !== void 0 && (--this._eventsCount === 0 ? this._events = /* @__PURE__ */ Object.create(null) : delete events[type]), this;
        if (arguments.length === 0) {
          var keys = Object.keys(events), key;
          for (i = 0; i < keys.length; ++i)
            key = keys[i], key !== "removeListener" && this.removeAllListeners(key);
          return this.removeAllListeners("removeListener"), this._events = /* @__PURE__ */ Object.create(null), this._eventsCount = 0, this;
        }
        if (listeners = events[type], typeof listeners == "function")
          this.removeListener(type, listeners);
        else if (listeners !== void 0)
          for (i = listeners.length - 1; i >= 0; i--)
            this.removeListener(type, listeners[i]);
        return this;
      };
      function _listeners(target, type, unwrap) {
        var events = target._events;
        if (events === void 0)
          return [];
        var evlistener = events[type];
        return evlistener === void 0 ? [] : typeof evlistener == "function" ? unwrap ? [evlistener.listener || evlistener] : [evlistener] : unwrap ? unwrapListeners(evlistener) : arrayClone(evlistener, evlistener.length);
      }
      EventEmitter.prototype.listeners = function(type) {
        return _listeners(this, type, !0);
      };
      EventEmitter.prototype.rawListeners = function(type) {
        return _listeners(this, type, !1);
      };
      EventEmitter.listenerCount = function(emitter, type) {
        return typeof emitter.listenerCount == "function" ? emitter.listenerCount(type) : listenerCount.call(emitter, type);
      };
      EventEmitter.prototype.listenerCount = listenerCount;
      function listenerCount(type) {
        var events = this._events;
        if (events !== void 0) {
          var evlistener = events[type];
          if (typeof evlistener == "function")
            return 1;
          if (evlistener !== void 0)
            return evlistener.length;
        }
        return 0;
      }
      EventEmitter.prototype.eventNames = function() {
        return this._eventsCount > 0 ? ReflectOwnKeys(this._events) : [];
      };
      function arrayClone(arr, n) {
        for (var copy = new Array(n), i = 0; i < n; ++i)
          copy[i] = arr[i];
        return copy;
      }
      function spliceOne(list, index) {
        for (; index + 1 < list.length; index++)
          list[index] = list[index + 1];
        list.pop();
      }
      function unwrapListeners(arr) {
        for (var ret = new Array(arr.length), i = 0; i < ret.length; ++i)
          ret[i] = arr[i].listener || arr[i];
        return ret;
      }
      function once(emitter, name) {
        return new Promise(function(resolve, reject) {
          function errorListener(err) {
            emitter.removeListener(name, resolver), reject(err);
          }
          function resolver() {
            typeof emitter.removeListener == "function" && emitter.removeListener("error", errorListener), resolve([].slice.call(arguments));
          }
          eventTargetAgnosticAddListener(emitter, name, resolver, { once: !0 }), name !== "error" && addErrorHandlerIfEventEmitter(emitter, errorListener, { once: !0 });
        });
      }
      function addErrorHandlerIfEventEmitter(emitter, handler, flags) {
        typeof emitter.on == "function" && eventTargetAgnosticAddListener(emitter, "error", handler, flags);
      }
      function eventTargetAgnosticAddListener(emitter, name, listener, flags) {
        if (typeof emitter.on == "function")
          flags.once ? emitter.once(name, listener) : emitter.on(name, listener);
        else if (typeof emitter.addEventListener == "function")
          emitter.addEventListener(name, function wrapListener(arg) {
            flags.once && emitter.removeEventListener(name, wrapListener), listener(arg);
          });
        else
          throw new TypeError('The "emitter" argument must be of type EventEmitter. Received type ' + typeof emitter);
      }
    }
  });

  // node_modules/readable-stream/lib/internal/streams/stream-browser.js
  var require_stream_browser = __commonJS({
    "node_modules/readable-stream/lib/internal/streams/stream-browser.js"(exports, module) {
      init_buffer_shim();
      init_process_shim();
      module.exports = require_events().EventEmitter;
    }
  });

  // node_modules/readable-stream/node_modules/safe-buffer/index.js
  var require_safe_buffer2 = __commonJS({
    "node_modules/readable-stream/node_modules/safe-buffer/index.js"(exports, module) {
      init_buffer_shim();
      init_process_shim();
      var buffer = require_buffer(), Buffer4 = buffer.Buffer;
      function copyProps(src, dst) {
        for (var key in src)
          dst[key] = src[key];
      }
      Buffer4.from && Buffer4.alloc && Buffer4.allocUnsafe && Buffer4.allocUnsafeSlow ? module.exports = buffer : (copyProps(buffer, exports), exports.Buffer = SafeBuffer);
      function SafeBuffer(arg, encodingOrOffset, length) {
        return Buffer4(arg, encodingOrOffset, length);
      }
      copyProps(Buffer4, SafeBuffer);
      SafeBuffer.from = function(arg, encodingOrOffset, length) {
        if (typeof arg == "number")
          throw new TypeError("Argument must not be a number");
        return Buffer4(arg, encodingOrOffset, length);
      };
      SafeBuffer.alloc = function(size, fill, encoding) {
        if (typeof size != "number")
          throw new TypeError("Argument must be a number");
        var buf = Buffer4(size);
        return fill !== void 0 ? typeof encoding == "string" ? buf.fill(fill, encoding) : buf.fill(fill) : buf.fill(0), buf;
      };
      SafeBuffer.allocUnsafe = function(size) {
        if (typeof size != "number")
          throw new TypeError("Argument must be a number");
        return Buffer4(size);
      };
      SafeBuffer.allocUnsafeSlow = function(size) {
        if (typeof size != "number")
          throw new TypeError("Argument must be a number");
        return buffer.SlowBuffer(size);
      };
    }
  });

  // node_modules/core-util-is/lib/util.js
  var require_util = __commonJS({
    "node_modules/core-util-is/lib/util.js"(exports) {
      init_buffer_shim();
      init_process_shim();
      function isArray(arg) {
        return Array.isArray ? Array.isArray(arg) : objectToString(arg) === "[object Array]";
      }
      exports.isArray = isArray;
      function isBoolean(arg) {
        return typeof arg == "boolean";
      }
      exports.isBoolean = isBoolean;
      function isNull(arg) {
        return arg === null;
      }
      exports.isNull = isNull;
      function isNullOrUndefined(arg) {
        return arg == null;
      }
      exports.isNullOrUndefined = isNullOrUndefined;
      function isNumber(arg) {
        return typeof arg == "number";
      }
      exports.isNumber = isNumber;
      function isString(arg) {
        return typeof arg == "string";
      }
      exports.isString = isString;
      function isSymbol(arg) {
        return typeof arg == "symbol";
      }
      exports.isSymbol = isSymbol;
      function isUndefined(arg) {
        return arg === void 0;
      }
      exports.isUndefined = isUndefined;
      function isRegExp(re) {
        return objectToString(re) === "[object RegExp]";
      }
      exports.isRegExp = isRegExp;
      function isObject(arg) {
        return typeof arg == "object" && arg !== null;
      }
      exports.isObject = isObject;
      function isDate(d) {
        return objectToString(d) === "[object Date]";
      }
      exports.isDate = isDate;
      function isError(e) {
        return objectToString(e) === "[object Error]" || e instanceof Error;
      }
      exports.isError = isError;
      function isFunction(arg) {
        return typeof arg == "function";
      }
      exports.isFunction = isFunction;
      function isPrimitive(arg) {
        return arg === null || typeof arg == "boolean" || typeof arg == "number" || typeof arg == "string" || typeof arg == "symbol" || // ES6 symbol
        typeof arg > "u";
      }
      exports.isPrimitive = isPrimitive;
      exports.isBuffer = require_buffer().Buffer.isBuffer;
      function objectToString(o) {
        return Object.prototype.toString.call(o);
      }
    }
  });

  // (disabled):util
  var require_util2 = __commonJS({
    "(disabled):util"() {
      init_buffer_shim();
      init_process_shim();
    }
  });

  // node_modules/readable-stream/lib/internal/streams/BufferList.js
  var require_BufferList = __commonJS({
    "node_modules/readable-stream/lib/internal/streams/BufferList.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      function _classCallCheck(instance, Constructor) {
        if (!(instance instanceof Constructor))
          throw new TypeError("Cannot call a class as a function");
      }
      var Buffer4 = require_safe_buffer2().Buffer, util = require_util2();
      function copyBuffer(src, target, offset) {
        src.copy(target, offset);
      }
      module.exports = (function() {
        function BufferList() {
          _classCallCheck(this, BufferList), this.head = null, this.tail = null, this.length = 0;
        }
        return BufferList.prototype.push = function(v) {
          var entry = { data: v, next: null };
          this.length > 0 ? this.tail.next = entry : this.head = entry, this.tail = entry, ++this.length;
        }, BufferList.prototype.unshift = function(v) {
          var entry = { data: v, next: this.head };
          this.length === 0 && (this.tail = entry), this.head = entry, ++this.length;
        }, BufferList.prototype.shift = function() {
          if (this.length !== 0) {
            var ret = this.head.data;
            return this.length === 1 ? this.head = this.tail = null : this.head = this.head.next, --this.length, ret;
          }
        }, BufferList.prototype.clear = function() {
          this.head = this.tail = null, this.length = 0;
        }, BufferList.prototype.join = function(s) {
          if (this.length === 0) return "";
          for (var p = this.head, ret = "" + p.data; p = p.next; )
            ret += s + p.data;
          return ret;
        }, BufferList.prototype.concat = function(n) {
          if (this.length === 0) return Buffer4.alloc(0);
          for (var ret = Buffer4.allocUnsafe(n >>> 0), p = this.head, i = 0; p; )
            copyBuffer(p.data, ret, i), i += p.data.length, p = p.next;
          return ret;
        }, BufferList;
      })();
      util && util.inspect && util.inspect.custom && (module.exports.prototype[util.inspect.custom] = function() {
        var obj = util.inspect({ length: this.length });
        return this.constructor.name + " " + obj;
      });
    }
  });

  // node_modules/readable-stream/lib/internal/streams/destroy.js
  var require_destroy = __commonJS({
    "node_modules/readable-stream/lib/internal/streams/destroy.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      var pna = require_process_nextick_args();
      function destroy(err, cb) {
        var _this = this, readableDestroyed = this._readableState && this._readableState.destroyed, writableDestroyed = this._writableState && this._writableState.destroyed;
        return readableDestroyed || writableDestroyed ? (cb ? cb(err) : err && (this._writableState ? this._writableState.errorEmitted || (this._writableState.errorEmitted = !0, pna.nextTick(emitErrorNT, this, err)) : pna.nextTick(emitErrorNT, this, err)), this) : (this._readableState && (this._readableState.destroyed = !0), this._writableState && (this._writableState.destroyed = !0), this._destroy(err || null, function(err2) {
          !cb && err2 ? _this._writableState ? _this._writableState.errorEmitted || (_this._writableState.errorEmitted = !0, pna.nextTick(emitErrorNT, _this, err2)) : pna.nextTick(emitErrorNT, _this, err2) : cb && cb(err2);
        }), this);
      }
      function undestroy() {
        this._readableState && (this._readableState.destroyed = !1, this._readableState.reading = !1, this._readableState.ended = !1, this._readableState.endEmitted = !1), this._writableState && (this._writableState.destroyed = !1, this._writableState.ended = !1, this._writableState.ending = !1, this._writableState.finalCalled = !1, this._writableState.prefinished = !1, this._writableState.finished = !1, this._writableState.errorEmitted = !1);
      }
      function emitErrorNT(self2, err) {
        self2.emit("error", err);
      }
      module.exports = {
        destroy,
        undestroy
      };
    }
  });

  // node_modules/util-deprecate/browser.js
  var require_browser2 = __commonJS({
    "node_modules/util-deprecate/browser.js"(exports, module) {
      init_buffer_shim();
      init_process_shim();
      module.exports = deprecate;
      function deprecate(fn, msg) {
        if (config("noDeprecation"))
          return fn;
        var warned = !1;
        function deprecated() {
          if (!warned) {
            if (config("throwDeprecation"))
              throw new Error(msg);
            config("traceDeprecation") ? console.trace(msg) : console.warn(msg), warned = !0;
          }
          return fn.apply(this, arguments);
        }
        return deprecated;
      }
      function config(name) {
        try {
          if (!globalThis.localStorage) return !1;
        } catch {
          return !1;
        }
        var val = globalThis.localStorage[name];
        return val == null ? !1 : String(val).toLowerCase() === "true";
      }
    }
  });

  // node_modules/readable-stream/lib/_stream_writable.js
  var require_stream_writable = __commonJS({
    "node_modules/readable-stream/lib/_stream_writable.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      var pna = require_process_nextick_args();
      module.exports = Writable;
      function CorkedRequest(state) {
        var _this = this;
        this.next = null, this.entry = null, this.finish = function() {
          onCorkedFinish(_this, state);
        };
      }
      var asyncWrite = !import_browser.default.browser && ["v0.10", "v0.9."].indexOf(import_browser.default.version.slice(0, 5)) > -1 ? setImmediate : pna.nextTick, Duplex;
      Writable.WritableState = WritableState;
      var util = Object.create(require_util());
      util.inherits = require_inherits_browser();
      var internalUtil = {
        deprecate: require_browser2()
      }, Stream = require_stream_browser(), Buffer4 = require_safe_buffer2().Buffer, OurUint8Array = (typeof globalThis < "u" ? globalThis : typeof window < "u" ? window : typeof self < "u" ? self : {}).Uint8Array || function() {
      };
      function _uint8ArrayToBuffer(chunk) {
        return Buffer4.from(chunk);
      }
      function _isUint8Array(obj) {
        return Buffer4.isBuffer(obj) || obj instanceof OurUint8Array;
      }
      var destroyImpl = require_destroy();
      util.inherits(Writable, Stream);
      function nop() {
      }
      function WritableState(options, stream) {
        Duplex = Duplex || require_stream_duplex(), options = options || {};
        var isDuplex = stream instanceof Duplex;
        this.objectMode = !!options.objectMode, isDuplex && (this.objectMode = this.objectMode || !!options.writableObjectMode);
        var hwm = options.highWaterMark, writableHwm = options.writableHighWaterMark, defaultHwm = this.objectMode ? 16 : 16 * 1024;
        hwm || hwm === 0 ? this.highWaterMark = hwm : isDuplex && (writableHwm || writableHwm === 0) ? this.highWaterMark = writableHwm : this.highWaterMark = defaultHwm, this.highWaterMark = Math.floor(this.highWaterMark), this.finalCalled = !1, this.needDrain = !1, this.ending = !1, this.ended = !1, this.finished = !1, this.destroyed = !1;
        var noDecode = options.decodeStrings === !1;
        this.decodeStrings = !noDecode, this.defaultEncoding = options.defaultEncoding || "utf8", this.length = 0, this.writing = !1, this.corked = 0, this.sync = !0, this.bufferProcessing = !1, this.onwrite = function(er) {
          onwrite(stream, er);
        }, this.writecb = null, this.writelen = 0, this.bufferedRequest = null, this.lastBufferedRequest = null, this.pendingcb = 0, this.prefinished = !1, this.errorEmitted = !1, this.bufferedRequestCount = 0, this.corkedRequestsFree = new CorkedRequest(this);
      }
      WritableState.prototype.getBuffer = function() {
        for (var current = this.bufferedRequest, out = []; current; )
          out.push(current), current = current.next;
        return out;
      };
      (function() {
        try {
          Object.defineProperty(WritableState.prototype, "buffer", {
            get: internalUtil.deprecate(function() {
              return this.getBuffer();
            }, "_writableState.buffer is deprecated. Use _writableState.getBuffer instead.", "DEP0003")
          });
        } catch {
        }
      })();
      var realHasInstance;
      typeof Symbol == "function" && Symbol.hasInstance && typeof Function.prototype[Symbol.hasInstance] == "function" ? (realHasInstance = Function.prototype[Symbol.hasInstance], Object.defineProperty(Writable, Symbol.hasInstance, {
        value: function(object) {
          return realHasInstance.call(this, object) ? !0 : this !== Writable ? !1 : object && object._writableState instanceof WritableState;
        }
      })) : realHasInstance = function(object) {
        return object instanceof this;
      };
      function Writable(options) {
        if (Duplex = Duplex || require_stream_duplex(), !realHasInstance.call(Writable, this) && !(this instanceof Duplex))
          return new Writable(options);
        this._writableState = new WritableState(options, this), this.writable = !0, options && (typeof options.write == "function" && (this._write = options.write), typeof options.writev == "function" && (this._writev = options.writev), typeof options.destroy == "function" && (this._destroy = options.destroy), typeof options.final == "function" && (this._final = options.final)), Stream.call(this);
      }
      Writable.prototype.pipe = function() {
        this.emit("error", new Error("Cannot pipe, not readable"));
      };
      function writeAfterEnd(stream, cb) {
        var er = new Error("write after end");
        stream.emit("error", er), pna.nextTick(cb, er);
      }
      function validChunk(stream, state, chunk, cb) {
        var valid = !0, er = !1;
        return chunk === null ? er = new TypeError("May not write null values to stream") : typeof chunk != "string" && chunk !== void 0 && !state.objectMode && (er = new TypeError("Invalid non-string/buffer chunk")), er && (stream.emit("error", er), pna.nextTick(cb, er), valid = !1), valid;
      }
      Writable.prototype.write = function(chunk, encoding, cb) {
        var state = this._writableState, ret = !1, isBuf = !state.objectMode && _isUint8Array(chunk);
        return isBuf && !Buffer4.isBuffer(chunk) && (chunk = _uint8ArrayToBuffer(chunk)), typeof encoding == "function" && (cb = encoding, encoding = null), isBuf ? encoding = "buffer" : encoding || (encoding = state.defaultEncoding), typeof cb != "function" && (cb = nop), state.ended ? writeAfterEnd(this, cb) : (isBuf || validChunk(this, state, chunk, cb)) && (state.pendingcb++, ret = writeOrBuffer(this, state, isBuf, chunk, encoding, cb)), ret;
      };
      Writable.prototype.cork = function() {
        var state = this._writableState;
        state.corked++;
      };
      Writable.prototype.uncork = function() {
        var state = this._writableState;
        state.corked && (state.corked--, !state.writing && !state.corked && !state.bufferProcessing && state.bufferedRequest && clearBuffer(this, state));
      };
      Writable.prototype.setDefaultEncoding = function(encoding) {
        if (typeof encoding == "string" && (encoding = encoding.toLowerCase()), !(["hex", "utf8", "utf-8", "ascii", "binary", "base64", "ucs2", "ucs-2", "utf16le", "utf-16le", "raw"].indexOf((encoding + "").toLowerCase()) > -1)) throw new TypeError("Unknown encoding: " + encoding);
        return this._writableState.defaultEncoding = encoding, this;
      };
      function decodeChunk(state, chunk, encoding) {
        return !state.objectMode && state.decodeStrings !== !1 && typeof chunk == "string" && (chunk = Buffer4.from(chunk, encoding)), chunk;
      }
      Object.defineProperty(Writable.prototype, "writableHighWaterMark", {
        // making it explicit this property is not enumerable
        // because otherwise some prototype manipulation in
        // userland will fail
        enumerable: !1,
        get: function() {
          return this._writableState.highWaterMark;
        }
      });
      function writeOrBuffer(stream, state, isBuf, chunk, encoding, cb) {
        if (!isBuf) {
          var newChunk = decodeChunk(state, chunk, encoding);
          chunk !== newChunk && (isBuf = !0, encoding = "buffer", chunk = newChunk);
        }
        var len = state.objectMode ? 1 : chunk.length;
        state.length += len;
        var ret = state.length < state.highWaterMark;
        if (ret || (state.needDrain = !0), state.writing || state.corked) {
          var last = state.lastBufferedRequest;
          state.lastBufferedRequest = {
            chunk,
            encoding,
            isBuf,
            callback: cb,
            next: null
          }, last ? last.next = state.lastBufferedRequest : state.bufferedRequest = state.lastBufferedRequest, state.bufferedRequestCount += 1;
        } else
          doWrite(stream, state, !1, len, chunk, encoding, cb);
        return ret;
      }
      function doWrite(stream, state, writev, len, chunk, encoding, cb) {
        state.writelen = len, state.writecb = cb, state.writing = !0, state.sync = !0, writev ? stream._writev(chunk, state.onwrite) : stream._write(chunk, encoding, state.onwrite), state.sync = !1;
      }
      function onwriteError(stream, state, sync, er, cb) {
        --state.pendingcb, sync ? (pna.nextTick(cb, er), pna.nextTick(finishMaybe, stream, state), stream._writableState.errorEmitted = !0, stream.emit("error", er)) : (cb(er), stream._writableState.errorEmitted = !0, stream.emit("error", er), finishMaybe(stream, state));
      }
      function onwriteStateUpdate(state) {
        state.writing = !1, state.writecb = null, state.length -= state.writelen, state.writelen = 0;
      }
      function onwrite(stream, er) {
        var state = stream._writableState, sync = state.sync, cb = state.writecb;
        if (onwriteStateUpdate(state), er) onwriteError(stream, state, sync, er, cb);
        else {
          var finished = needFinish(state);
          !finished && !state.corked && !state.bufferProcessing && state.bufferedRequest && clearBuffer(stream, state), sync ? asyncWrite(afterWrite, stream, state, finished, cb) : afterWrite(stream, state, finished, cb);
        }
      }
      function afterWrite(stream, state, finished, cb) {
        finished || onwriteDrain(stream, state), state.pendingcb--, cb(), finishMaybe(stream, state);
      }
      function onwriteDrain(stream, state) {
        state.length === 0 && state.needDrain && (state.needDrain = !1, stream.emit("drain"));
      }
      function clearBuffer(stream, state) {
        state.bufferProcessing = !0;
        var entry = state.bufferedRequest;
        if (stream._writev && entry && entry.next) {
          var l = state.bufferedRequestCount, buffer = new Array(l), holder = state.corkedRequestsFree;
          holder.entry = entry;
          for (var count = 0, allBuffers = !0; entry; )
            buffer[count] = entry, entry.isBuf || (allBuffers = !1), entry = entry.next, count += 1;
          buffer.allBuffers = allBuffers, doWrite(stream, state, !0, state.length, buffer, "", holder.finish), state.pendingcb++, state.lastBufferedRequest = null, holder.next ? (state.corkedRequestsFree = holder.next, holder.next = null) : state.corkedRequestsFree = new CorkedRequest(state), state.bufferedRequestCount = 0;
        } else {
          for (; entry; ) {
            var chunk = entry.chunk, encoding = entry.encoding, cb = entry.callback, len = state.objectMode ? 1 : chunk.length;
            if (doWrite(stream, state, !1, len, chunk, encoding, cb), entry = entry.next, state.bufferedRequestCount--, state.writing)
              break;
          }
          entry === null && (state.lastBufferedRequest = null);
        }
        state.bufferedRequest = entry, state.bufferProcessing = !1;
      }
      Writable.prototype._write = function(chunk, encoding, cb) {
        cb(new Error("_write() is not implemented"));
      };
      Writable.prototype._writev = null;
      Writable.prototype.end = function(chunk, encoding, cb) {
        var state = this._writableState;
        typeof chunk == "function" ? (cb = chunk, chunk = null, encoding = null) : typeof encoding == "function" && (cb = encoding, encoding = null), chunk != null && this.write(chunk, encoding), state.corked && (state.corked = 1, this.uncork()), state.ending || endWritable(this, state, cb);
      };
      function needFinish(state) {
        return state.ending && state.length === 0 && state.bufferedRequest === null && !state.finished && !state.writing;
      }
      function callFinal(stream, state) {
        stream._final(function(err) {
          state.pendingcb--, err && stream.emit("error", err), state.prefinished = !0, stream.emit("prefinish"), finishMaybe(stream, state);
        });
      }
      function prefinish(stream, state) {
        !state.prefinished && !state.finalCalled && (typeof stream._final == "function" ? (state.pendingcb++, state.finalCalled = !0, pna.nextTick(callFinal, stream, state)) : (state.prefinished = !0, stream.emit("prefinish")));
      }
      function finishMaybe(stream, state) {
        var need = needFinish(state);
        return need && (prefinish(stream, state), state.pendingcb === 0 && (state.finished = !0, stream.emit("finish"))), need;
      }
      function endWritable(stream, state, cb) {
        state.ending = !0, finishMaybe(stream, state), cb && (state.finished ? pna.nextTick(cb) : stream.once("finish", cb)), state.ended = !0, stream.writable = !1;
      }
      function onCorkedFinish(corkReq, state, err) {
        var entry = corkReq.entry;
        for (corkReq.entry = null; entry; ) {
          var cb = entry.callback;
          state.pendingcb--, cb(err), entry = entry.next;
        }
        state.corkedRequestsFree.next = corkReq;
      }
      Object.defineProperty(Writable.prototype, "destroyed", {
        get: function() {
          return this._writableState === void 0 ? !1 : this._writableState.destroyed;
        },
        set: function(value) {
          this._writableState && (this._writableState.destroyed = value);
        }
      });
      Writable.prototype.destroy = destroyImpl.destroy;
      Writable.prototype._undestroy = destroyImpl.undestroy;
      Writable.prototype._destroy = function(err, cb) {
        this.end(), cb(err);
      };
    }
  });

  // node_modules/readable-stream/lib/_stream_duplex.js
  var require_stream_duplex = __commonJS({
    "node_modules/readable-stream/lib/_stream_duplex.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      var pna = require_process_nextick_args(), objectKeys = Object.keys || function(obj) {
        var keys2 = [];
        for (var key in obj)
          keys2.push(key);
        return keys2;
      };
      module.exports = Duplex;
      var util = Object.create(require_util());
      util.inherits = require_inherits_browser();
      var Readable = require_stream_readable(), Writable = require_stream_writable();
      util.inherits(Duplex, Readable);
      for (keys = objectKeys(Writable.prototype), v = 0; v < keys.length; v++)
        method = keys[v], Duplex.prototype[method] || (Duplex.prototype[method] = Writable.prototype[method]);
      var keys, method, v;
      function Duplex(options) {
        if (!(this instanceof Duplex)) return new Duplex(options);
        Readable.call(this, options), Writable.call(this, options), options && options.readable === !1 && (this.readable = !1), options && options.writable === !1 && (this.writable = !1), this.allowHalfOpen = !0, options && options.allowHalfOpen === !1 && (this.allowHalfOpen = !1), this.once("end", onend);
      }
      Object.defineProperty(Duplex.prototype, "writableHighWaterMark", {
        // making it explicit this property is not enumerable
        // because otherwise some prototype manipulation in
        // userland will fail
        enumerable: !1,
        get: function() {
          return this._writableState.highWaterMark;
        }
      });
      function onend() {
        this.allowHalfOpen || this._writableState.ended || pna.nextTick(onEndNT, this);
      }
      function onEndNT(self2) {
        self2.end();
      }
      Object.defineProperty(Duplex.prototype, "destroyed", {
        get: function() {
          return this._readableState === void 0 || this._writableState === void 0 ? !1 : this._readableState.destroyed && this._writableState.destroyed;
        },
        set: function(value) {
          this._readableState === void 0 || this._writableState === void 0 || (this._readableState.destroyed = value, this._writableState.destroyed = value);
        }
      });
      Duplex.prototype._destroy = function(err, cb) {
        this.push(null), this.end(), pna.nextTick(cb, err);
      };
    }
  });

  // node_modules/string_decoder/node_modules/safe-buffer/index.js
  var require_safe_buffer3 = __commonJS({
    "node_modules/string_decoder/node_modules/safe-buffer/index.js"(exports, module) {
      init_buffer_shim();
      init_process_shim();
      var buffer = require_buffer(), Buffer4 = buffer.Buffer;
      function copyProps(src, dst) {
        for (var key in src)
          dst[key] = src[key];
      }
      Buffer4.from && Buffer4.alloc && Buffer4.allocUnsafe && Buffer4.allocUnsafeSlow ? module.exports = buffer : (copyProps(buffer, exports), exports.Buffer = SafeBuffer);
      function SafeBuffer(arg, encodingOrOffset, length) {
        return Buffer4(arg, encodingOrOffset, length);
      }
      copyProps(Buffer4, SafeBuffer);
      SafeBuffer.from = function(arg, encodingOrOffset, length) {
        if (typeof arg == "number")
          throw new TypeError("Argument must not be a number");
        return Buffer4(arg, encodingOrOffset, length);
      };
      SafeBuffer.alloc = function(size, fill, encoding) {
        if (typeof size != "number")
          throw new TypeError("Argument must be a number");
        var buf = Buffer4(size);
        return fill !== void 0 ? typeof encoding == "string" ? buf.fill(fill, encoding) : buf.fill(fill) : buf.fill(0), buf;
      };
      SafeBuffer.allocUnsafe = function(size) {
        if (typeof size != "number")
          throw new TypeError("Argument must be a number");
        return Buffer4(size);
      };
      SafeBuffer.allocUnsafeSlow = function(size) {
        if (typeof size != "number")
          throw new TypeError("Argument must be a number");
        return buffer.SlowBuffer(size);
      };
    }
  });

  // node_modules/string_decoder/lib/string_decoder.js
  var require_string_decoder = __commonJS({
    "node_modules/string_decoder/lib/string_decoder.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      var Buffer4 = require_safe_buffer3().Buffer, isEncoding = Buffer4.isEncoding || function(encoding) {
        switch (encoding = "" + encoding, encoding && encoding.toLowerCase()) {
          case "hex":
          case "utf8":
          case "utf-8":
          case "ascii":
          case "binary":
          case "base64":
          case "ucs2":
          case "ucs-2":
          case "utf16le":
          case "utf-16le":
          case "raw":
            return !0;
          default:
            return !1;
        }
      };
      function _normalizeEncoding(enc) {
        if (!enc) return "utf8";
        for (var retried; ; )
          switch (enc) {
            case "utf8":
            case "utf-8":
              return "utf8";
            case "ucs2":
            case "ucs-2":
            case "utf16le":
            case "utf-16le":
              return "utf16le";
            case "latin1":
            case "binary":
              return "latin1";
            case "base64":
            case "ascii":
            case "hex":
              return enc;
            default:
              if (retried) return;
              enc = ("" + enc).toLowerCase(), retried = !0;
          }
      }
      function normalizeEncoding(enc) {
        var nenc = _normalizeEncoding(enc);
        if (typeof nenc != "string" && (Buffer4.isEncoding === isEncoding || !isEncoding(enc))) throw new Error("Unknown encoding: " + enc);
        return nenc || enc;
      }
      exports.StringDecoder = StringDecoder;
      function StringDecoder(encoding) {
        this.encoding = normalizeEncoding(encoding);
        var nb;
        switch (this.encoding) {
          case "utf16le":
            this.text = utf16Text, this.end = utf16End, nb = 4;
            break;
          case "utf8":
            this.fillLast = utf8FillLast, nb = 4;
            break;
          case "base64":
            this.text = base64Text, this.end = base64End, nb = 3;
            break;
          default:
            this.write = simpleWrite, this.end = simpleEnd;
            return;
        }
        this.lastNeed = 0, this.lastTotal = 0, this.lastChar = Buffer4.allocUnsafe(nb);
      }
      StringDecoder.prototype.write = function(buf) {
        if (buf.length === 0) return "";
        var r, i;
        if (this.lastNeed) {
          if (r = this.fillLast(buf), r === void 0) return "";
          i = this.lastNeed, this.lastNeed = 0;
        } else
          i = 0;
        return i < buf.length ? r ? r + this.text(buf, i) : this.text(buf, i) : r || "";
      };
      StringDecoder.prototype.end = utf8End;
      StringDecoder.prototype.text = utf8Text;
      StringDecoder.prototype.fillLast = function(buf) {
        if (this.lastNeed <= buf.length)
          return buf.copy(this.lastChar, this.lastTotal - this.lastNeed, 0, this.lastNeed), this.lastChar.toString(this.encoding, 0, this.lastTotal);
        buf.copy(this.lastChar, this.lastTotal - this.lastNeed, 0, buf.length), this.lastNeed -= buf.length;
      };
      function utf8CheckByte(byte) {
        return byte <= 127 ? 0 : byte >> 5 === 6 ? 2 : byte >> 4 === 14 ? 3 : byte >> 3 === 30 ? 4 : byte >> 6 === 2 ? -1 : -2;
      }
      function utf8CheckIncomplete(self2, buf, i) {
        var j = buf.length - 1;
        if (j < i) return 0;
        var nb = utf8CheckByte(buf[j]);
        return nb >= 0 ? (nb > 0 && (self2.lastNeed = nb - 1), nb) : --j < i || nb === -2 ? 0 : (nb = utf8CheckByte(buf[j]), nb >= 0 ? (nb > 0 && (self2.lastNeed = nb - 2), nb) : --j < i || nb === -2 ? 0 : (nb = utf8CheckByte(buf[j]), nb >= 0 ? (nb > 0 && (nb === 2 ? nb = 0 : self2.lastNeed = nb - 3), nb) : 0));
      }
      function utf8CheckExtraBytes(self2, buf, p) {
        if ((buf[0] & 192) !== 128)
          return self2.lastNeed = 0, "\uFFFD";
        if (self2.lastNeed > 1 && buf.length > 1) {
          if ((buf[1] & 192) !== 128)
            return self2.lastNeed = 1, "\uFFFD";
          if (self2.lastNeed > 2 && buf.length > 2 && (buf[2] & 192) !== 128)
            return self2.lastNeed = 2, "\uFFFD";
        }
      }
      function utf8FillLast(buf) {
        var p = this.lastTotal - this.lastNeed, r = utf8CheckExtraBytes(this, buf, p);
        if (r !== void 0) return r;
        if (this.lastNeed <= buf.length)
          return buf.copy(this.lastChar, p, 0, this.lastNeed), this.lastChar.toString(this.encoding, 0, this.lastTotal);
        buf.copy(this.lastChar, p, 0, buf.length), this.lastNeed -= buf.length;
      }
      function utf8Text(buf, i) {
        var total = utf8CheckIncomplete(this, buf, i);
        if (!this.lastNeed) return buf.toString("utf8", i);
        this.lastTotal = total;
        var end = buf.length - (total - this.lastNeed);
        return buf.copy(this.lastChar, 0, end), buf.toString("utf8", i, end);
      }
      function utf8End(buf) {
        var r = buf && buf.length ? this.write(buf) : "";
        return this.lastNeed ? r + "\uFFFD" : r;
      }
      function utf16Text(buf, i) {
        if ((buf.length - i) % 2 === 0) {
          var r = buf.toString("utf16le", i);
          if (r) {
            var c = r.charCodeAt(r.length - 1);
            if (c >= 55296 && c <= 56319)
              return this.lastNeed = 2, this.lastTotal = 4, this.lastChar[0] = buf[buf.length - 2], this.lastChar[1] = buf[buf.length - 1], r.slice(0, -1);
          }
          return r;
        }
        return this.lastNeed = 1, this.lastTotal = 2, this.lastChar[0] = buf[buf.length - 1], buf.toString("utf16le", i, buf.length - 1);
      }
      function utf16End(buf) {
        var r = buf && buf.length ? this.write(buf) : "";
        if (this.lastNeed) {
          var end = this.lastTotal - this.lastNeed;
          return r + this.lastChar.toString("utf16le", 0, end);
        }
        return r;
      }
      function base64Text(buf, i) {
        var n = (buf.length - i) % 3;
        return n === 0 ? buf.toString("base64", i) : (this.lastNeed = 3 - n, this.lastTotal = 3, n === 1 ? this.lastChar[0] = buf[buf.length - 1] : (this.lastChar[0] = buf[buf.length - 2], this.lastChar[1] = buf[buf.length - 1]), buf.toString("base64", i, buf.length - n));
      }
      function base64End(buf) {
        var r = buf && buf.length ? this.write(buf) : "";
        return this.lastNeed ? r + this.lastChar.toString("base64", 0, 3 - this.lastNeed) : r;
      }
      function simpleWrite(buf) {
        return buf.toString(this.encoding);
      }
      function simpleEnd(buf) {
        return buf && buf.length ? this.write(buf) : "";
      }
    }
  });

  // node_modules/readable-stream/lib/_stream_readable.js
  var require_stream_readable = __commonJS({
    "node_modules/readable-stream/lib/_stream_readable.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      var pna = require_process_nextick_args();
      module.exports = Readable;
      var isArray = require_isarray2(), Duplex;
      Readable.ReadableState = ReadableState;
      var EE = require_events().EventEmitter, EElistenerCount = function(emitter, type) {
        return emitter.listeners(type).length;
      }, Stream = require_stream_browser(), Buffer4 = require_safe_buffer2().Buffer, OurUint8Array = (typeof globalThis < "u" ? globalThis : typeof window < "u" ? window : typeof self < "u" ? self : {}).Uint8Array || function() {
      };
      function _uint8ArrayToBuffer(chunk) {
        return Buffer4.from(chunk);
      }
      function _isUint8Array(obj) {
        return Buffer4.isBuffer(obj) || obj instanceof OurUint8Array;
      }
      var util = Object.create(require_util());
      util.inherits = require_inherits_browser();
      var debugUtil = require_util2(), debug = void 0;
      debugUtil && debugUtil.debuglog ? debug = debugUtil.debuglog("stream") : debug = function() {
      };
      var BufferList = require_BufferList(), destroyImpl = require_destroy(), StringDecoder;
      util.inherits(Readable, Stream);
      var kProxyEvents = ["error", "close", "destroy", "pause", "resume"];
      function prependListener(emitter, event, fn) {
        if (typeof emitter.prependListener == "function") return emitter.prependListener(event, fn);
        !emitter._events || !emitter._events[event] ? emitter.on(event, fn) : isArray(emitter._events[event]) ? emitter._events[event].unshift(fn) : emitter._events[event] = [fn, emitter._events[event]];
      }
      function ReadableState(options, stream) {
        Duplex = Duplex || require_stream_duplex(), options = options || {};
        var isDuplex = stream instanceof Duplex;
        this.objectMode = !!options.objectMode, isDuplex && (this.objectMode = this.objectMode || !!options.readableObjectMode);
        var hwm = options.highWaterMark, readableHwm = options.readableHighWaterMark, defaultHwm = this.objectMode ? 16 : 16 * 1024;
        hwm || hwm === 0 ? this.highWaterMark = hwm : isDuplex && (readableHwm || readableHwm === 0) ? this.highWaterMark = readableHwm : this.highWaterMark = defaultHwm, this.highWaterMark = Math.floor(this.highWaterMark), this.buffer = new BufferList(), this.length = 0, this.pipes = null, this.pipesCount = 0, this.flowing = null, this.ended = !1, this.endEmitted = !1, this.reading = !1, this.sync = !0, this.needReadable = !1, this.emittedReadable = !1, this.readableListening = !1, this.resumeScheduled = !1, this.destroyed = !1, this.defaultEncoding = options.defaultEncoding || "utf8", this.awaitDrain = 0, this.readingMore = !1, this.decoder = null, this.encoding = null, options.encoding && (StringDecoder || (StringDecoder = require_string_decoder().StringDecoder), this.decoder = new StringDecoder(options.encoding), this.encoding = options.encoding);
      }
      function Readable(options) {
        if (Duplex = Duplex || require_stream_duplex(), !(this instanceof Readable)) return new Readable(options);
        this._readableState = new ReadableState(options, this), this.readable = !0, options && (typeof options.read == "function" && (this._read = options.read), typeof options.destroy == "function" && (this._destroy = options.destroy)), Stream.call(this);
      }
      Object.defineProperty(Readable.prototype, "destroyed", {
        get: function() {
          return this._readableState === void 0 ? !1 : this._readableState.destroyed;
        },
        set: function(value) {
          this._readableState && (this._readableState.destroyed = value);
        }
      });
      Readable.prototype.destroy = destroyImpl.destroy;
      Readable.prototype._undestroy = destroyImpl.undestroy;
      Readable.prototype._destroy = function(err, cb) {
        this.push(null), cb(err);
      };
      Readable.prototype.push = function(chunk, encoding) {
        var state = this._readableState, skipChunkCheck;
        return state.objectMode ? skipChunkCheck = !0 : typeof chunk == "string" && (encoding = encoding || state.defaultEncoding, encoding !== state.encoding && (chunk = Buffer4.from(chunk, encoding), encoding = ""), skipChunkCheck = !0), readableAddChunk(this, chunk, encoding, !1, skipChunkCheck);
      };
      Readable.prototype.unshift = function(chunk) {
        return readableAddChunk(this, chunk, null, !0, !1);
      };
      function readableAddChunk(stream, chunk, encoding, addToFront, skipChunkCheck) {
        var state = stream._readableState;
        if (chunk === null)
          state.reading = !1, onEofChunk(stream, state);
        else {
          var er;
          skipChunkCheck || (er = chunkInvalid(state, chunk)), er ? stream.emit("error", er) : state.objectMode || chunk && chunk.length > 0 ? (typeof chunk != "string" && !state.objectMode && Object.getPrototypeOf(chunk) !== Buffer4.prototype && (chunk = _uint8ArrayToBuffer(chunk)), addToFront ? state.endEmitted ? stream.emit("error", new Error("stream.unshift() after end event")) : addChunk(stream, state, chunk, !0) : state.ended ? stream.emit("error", new Error("stream.push() after EOF")) : (state.reading = !1, state.decoder && !encoding ? (chunk = state.decoder.write(chunk), state.objectMode || chunk.length !== 0 ? addChunk(stream, state, chunk, !1) : maybeReadMore(stream, state)) : addChunk(stream, state, chunk, !1))) : addToFront || (state.reading = !1);
        }
        return needMoreData(state);
      }
      function addChunk(stream, state, chunk, addToFront) {
        state.flowing && state.length === 0 && !state.sync ? (stream.emit("data", chunk), stream.read(0)) : (state.length += state.objectMode ? 1 : chunk.length, addToFront ? state.buffer.unshift(chunk) : state.buffer.push(chunk), state.needReadable && emitReadable(stream)), maybeReadMore(stream, state);
      }
      function chunkInvalid(state, chunk) {
        var er;
        return !_isUint8Array(chunk) && typeof chunk != "string" && chunk !== void 0 && !state.objectMode && (er = new TypeError("Invalid non-string/buffer chunk")), er;
      }
      function needMoreData(state) {
        return !state.ended && (state.needReadable || state.length < state.highWaterMark || state.length === 0);
      }
      Readable.prototype.isPaused = function() {
        return this._readableState.flowing === !1;
      };
      Readable.prototype.setEncoding = function(enc) {
        return StringDecoder || (StringDecoder = require_string_decoder().StringDecoder), this._readableState.decoder = new StringDecoder(enc), this._readableState.encoding = enc, this;
      };
      var MAX_HWM = 8388608;
      function computeNewHighWaterMark(n) {
        return n >= MAX_HWM ? n = MAX_HWM : (n--, n |= n >>> 1, n |= n >>> 2, n |= n >>> 4, n |= n >>> 8, n |= n >>> 16, n++), n;
      }
      function howMuchToRead(n, state) {
        return n <= 0 || state.length === 0 && state.ended ? 0 : state.objectMode ? 1 : n !== n ? state.flowing && state.length ? state.buffer.head.data.length : state.length : (n > state.highWaterMark && (state.highWaterMark = computeNewHighWaterMark(n)), n <= state.length ? n : state.ended ? state.length : (state.needReadable = !0, 0));
      }
      Readable.prototype.read = function(n) {
        debug("read", n), n = parseInt(n, 10);
        var state = this._readableState, nOrig = n;
        if (n !== 0 && (state.emittedReadable = !1), n === 0 && state.needReadable && (state.length >= state.highWaterMark || state.ended))
          return debug("read: emitReadable", state.length, state.ended), state.length === 0 && state.ended ? endReadable(this) : emitReadable(this), null;
        if (n = howMuchToRead(n, state), n === 0 && state.ended)
          return state.length === 0 && endReadable(this), null;
        var doRead = state.needReadable;
        debug("need readable", doRead), (state.length === 0 || state.length - n < state.highWaterMark) && (doRead = !0, debug("length less than watermark", doRead)), state.ended || state.reading ? (doRead = !1, debug("reading or ended", doRead)) : doRead && (debug("do read"), state.reading = !0, state.sync = !0, state.length === 0 && (state.needReadable = !0), this._read(state.highWaterMark), state.sync = !1, state.reading || (n = howMuchToRead(nOrig, state)));
        var ret;
        return n > 0 ? ret = fromList(n, state) : ret = null, ret === null ? (state.needReadable = !0, n = 0) : state.length -= n, state.length === 0 && (state.ended || (state.needReadable = !0), nOrig !== n && state.ended && endReadable(this)), ret !== null && this.emit("data", ret), ret;
      };
      function onEofChunk(stream, state) {
        if (!state.ended) {
          if (state.decoder) {
            var chunk = state.decoder.end();
            chunk && chunk.length && (state.buffer.push(chunk), state.length += state.objectMode ? 1 : chunk.length);
          }
          state.ended = !0, emitReadable(stream);
        }
      }
      function emitReadable(stream) {
        var state = stream._readableState;
        state.needReadable = !1, state.emittedReadable || (debug("emitReadable", state.flowing), state.emittedReadable = !0, state.sync ? pna.nextTick(emitReadable_, stream) : emitReadable_(stream));
      }
      function emitReadable_(stream) {
        debug("emit readable"), stream.emit("readable"), flow(stream);
      }
      function maybeReadMore(stream, state) {
        state.readingMore || (state.readingMore = !0, pna.nextTick(maybeReadMore_, stream, state));
      }
      function maybeReadMore_(stream, state) {
        for (var len = state.length; !state.reading && !state.flowing && !state.ended && state.length < state.highWaterMark && (debug("maybeReadMore read 0"), stream.read(0), len !== state.length); )
          len = state.length;
        state.readingMore = !1;
      }
      Readable.prototype._read = function(n) {
        this.emit("error", new Error("_read() is not implemented"));
      };
      Readable.prototype.pipe = function(dest, pipeOpts) {
        var src = this, state = this._readableState;
        switch (state.pipesCount) {
          case 0:
            state.pipes = dest;
            break;
          case 1:
            state.pipes = [state.pipes, dest];
            break;
          default:
            state.pipes.push(dest);
            break;
        }
        state.pipesCount += 1, debug("pipe count=%d opts=%j", state.pipesCount, pipeOpts);
        var doEnd = (!pipeOpts || pipeOpts.end !== !1) && dest !== import_browser.default.stdout && dest !== import_browser.default.stderr, endFn = doEnd ? onend : unpipe;
        state.endEmitted ? pna.nextTick(endFn) : src.once("end", endFn), dest.on("unpipe", onunpipe);
        function onunpipe(readable, unpipeInfo) {
          debug("onunpipe"), readable === src && unpipeInfo && unpipeInfo.hasUnpiped === !1 && (unpipeInfo.hasUnpiped = !0, cleanup());
        }
        function onend() {
          debug("onend"), dest.end();
        }
        var ondrain = pipeOnDrain(src);
        dest.on("drain", ondrain);
        var cleanedUp = !1;
        function cleanup() {
          debug("cleanup"), dest.removeListener("close", onclose), dest.removeListener("finish", onfinish), dest.removeListener("drain", ondrain), dest.removeListener("error", onerror), dest.removeListener("unpipe", onunpipe), src.removeListener("end", onend), src.removeListener("end", unpipe), src.removeListener("data", ondata), cleanedUp = !0, state.awaitDrain && (!dest._writableState || dest._writableState.needDrain) && ondrain();
        }
        var increasedAwaitDrain = !1;
        src.on("data", ondata);
        function ondata(chunk) {
          debug("ondata"), increasedAwaitDrain = !1;
          var ret = dest.write(chunk);
          ret === !1 && !increasedAwaitDrain && ((state.pipesCount === 1 && state.pipes === dest || state.pipesCount > 1 && indexOf(state.pipes, dest) !== -1) && !cleanedUp && (debug("false write response, pause", state.awaitDrain), state.awaitDrain++, increasedAwaitDrain = !0), src.pause());
        }
        function onerror(er) {
          debug("onerror", er), unpipe(), dest.removeListener("error", onerror), EElistenerCount(dest, "error") === 0 && dest.emit("error", er);
        }
        prependListener(dest, "error", onerror);
        function onclose() {
          dest.removeListener("finish", onfinish), unpipe();
        }
        dest.once("close", onclose);
        function onfinish() {
          debug("onfinish"), dest.removeListener("close", onclose), unpipe();
        }
        dest.once("finish", onfinish);
        function unpipe() {
          debug("unpipe"), src.unpipe(dest);
        }
        return dest.emit("pipe", src), state.flowing || (debug("pipe resume"), src.resume()), dest;
      };
      function pipeOnDrain(src) {
        return function() {
          var state = src._readableState;
          debug("pipeOnDrain", state.awaitDrain), state.awaitDrain && state.awaitDrain--, state.awaitDrain === 0 && EElistenerCount(src, "data") && (state.flowing = !0, flow(src));
        };
      }
      Readable.prototype.unpipe = function(dest) {
        var state = this._readableState, unpipeInfo = { hasUnpiped: !1 };
        if (state.pipesCount === 0) return this;
        if (state.pipesCount === 1)
          return dest && dest !== state.pipes ? this : (dest || (dest = state.pipes), state.pipes = null, state.pipesCount = 0, state.flowing = !1, dest && dest.emit("unpipe", this, unpipeInfo), this);
        if (!dest) {
          var dests = state.pipes, len = state.pipesCount;
          state.pipes = null, state.pipesCount = 0, state.flowing = !1;
          for (var i = 0; i < len; i++)
            dests[i].emit("unpipe", this, { hasUnpiped: !1 });
          return this;
        }
        var index = indexOf(state.pipes, dest);
        return index === -1 ? this : (state.pipes.splice(index, 1), state.pipesCount -= 1, state.pipesCount === 1 && (state.pipes = state.pipes[0]), dest.emit("unpipe", this, unpipeInfo), this);
      };
      Readable.prototype.on = function(ev, fn) {
        var res = Stream.prototype.on.call(this, ev, fn);
        if (ev === "data")
          this._readableState.flowing !== !1 && this.resume();
        else if (ev === "readable") {
          var state = this._readableState;
          !state.endEmitted && !state.readableListening && (state.readableListening = state.needReadable = !0, state.emittedReadable = !1, state.reading ? state.length && emitReadable(this) : pna.nextTick(nReadingNextTick, this));
        }
        return res;
      };
      Readable.prototype.addListener = Readable.prototype.on;
      function nReadingNextTick(self2) {
        debug("readable nexttick read 0"), self2.read(0);
      }
      Readable.prototype.resume = function() {
        var state = this._readableState;
        return state.flowing || (debug("resume"), state.flowing = !0, resume(this, state)), this;
      };
      function resume(stream, state) {
        state.resumeScheduled || (state.resumeScheduled = !0, pna.nextTick(resume_, stream, state));
      }
      function resume_(stream, state) {
        state.reading || (debug("resume read 0"), stream.read(0)), state.resumeScheduled = !1, state.awaitDrain = 0, stream.emit("resume"), flow(stream), state.flowing && !state.reading && stream.read(0);
      }
      Readable.prototype.pause = function() {
        return debug("call pause flowing=%j", this._readableState.flowing), this._readableState.flowing !== !1 && (debug("pause"), this._readableState.flowing = !1, this.emit("pause")), this;
      };
      function flow(stream) {
        var state = stream._readableState;
        for (debug("flow", state.flowing); state.flowing && stream.read() !== null; )
          ;
      }
      Readable.prototype.wrap = function(stream) {
        var _this = this, state = this._readableState, paused = !1;
        stream.on("end", function() {
          if (debug("wrapped end"), state.decoder && !state.ended) {
            var chunk = state.decoder.end();
            chunk && chunk.length && _this.push(chunk);
          }
          _this.push(null);
        }), stream.on("data", function(chunk) {
          if (debug("wrapped data"), state.decoder && (chunk = state.decoder.write(chunk)), !(state.objectMode && chunk == null) && !(!state.objectMode && (!chunk || !chunk.length))) {
            var ret = _this.push(chunk);
            ret || (paused = !0, stream.pause());
          }
        });
        for (var i in stream)
          this[i] === void 0 && typeof stream[i] == "function" && (this[i] = /* @__PURE__ */ (function(method) {
            return function() {
              return stream[method].apply(stream, arguments);
            };
          })(i));
        for (var n = 0; n < kProxyEvents.length; n++)
          stream.on(kProxyEvents[n], this.emit.bind(this, kProxyEvents[n]));
        return this._read = function(n2) {
          debug("wrapped _read", n2), paused && (paused = !1, stream.resume());
        }, this;
      };
      Object.defineProperty(Readable.prototype, "readableHighWaterMark", {
        // making it explicit this property is not enumerable
        // because otherwise some prototype manipulation in
        // userland will fail
        enumerable: !1,
        get: function() {
          return this._readableState.highWaterMark;
        }
      });
      Readable._fromList = fromList;
      function fromList(n, state) {
        if (state.length === 0) return null;
        var ret;
        return state.objectMode ? ret = state.buffer.shift() : !n || n >= state.length ? (state.decoder ? ret = state.buffer.join("") : state.buffer.length === 1 ? ret = state.buffer.head.data : ret = state.buffer.concat(state.length), state.buffer.clear()) : ret = fromListPartial(n, state.buffer, state.decoder), ret;
      }
      function fromListPartial(n, list, hasStrings) {
        var ret;
        return n < list.head.data.length ? (ret = list.head.data.slice(0, n), list.head.data = list.head.data.slice(n)) : n === list.head.data.length ? ret = list.shift() : ret = hasStrings ? copyFromBufferString(n, list) : copyFromBuffer(n, list), ret;
      }
      function copyFromBufferString(n, list) {
        var p = list.head, c = 1, ret = p.data;
        for (n -= ret.length; p = p.next; ) {
          var str = p.data, nb = n > str.length ? str.length : n;
          if (nb === str.length ? ret += str : ret += str.slice(0, n), n -= nb, n === 0) {
            nb === str.length ? (++c, p.next ? list.head = p.next : list.head = list.tail = null) : (list.head = p, p.data = str.slice(nb));
            break;
          }
          ++c;
        }
        return list.length -= c, ret;
      }
      function copyFromBuffer(n, list) {
        var ret = Buffer4.allocUnsafe(n), p = list.head, c = 1;
        for (p.data.copy(ret), n -= p.data.length; p = p.next; ) {
          var buf = p.data, nb = n > buf.length ? buf.length : n;
          if (buf.copy(ret, ret.length - n, 0, nb), n -= nb, n === 0) {
            nb === buf.length ? (++c, p.next ? list.head = p.next : list.head = list.tail = null) : (list.head = p, p.data = buf.slice(nb));
            break;
          }
          ++c;
        }
        return list.length -= c, ret;
      }
      function endReadable(stream) {
        var state = stream._readableState;
        if (state.length > 0) throw new Error('"endReadable()" called on non-empty stream');
        state.endEmitted || (state.ended = !0, pna.nextTick(endReadableNT, state, stream));
      }
      function endReadableNT(state, stream) {
        !state.endEmitted && state.length === 0 && (state.endEmitted = !0, stream.readable = !1, stream.emit("end"));
      }
      function indexOf(xs, x) {
        for (var i = 0, l = xs.length; i < l; i++)
          if (xs[i] === x) return i;
        return -1;
      }
    }
  });

  // node_modules/readable-stream/lib/_stream_transform.js
  var require_stream_transform = __commonJS({
    "node_modules/readable-stream/lib/_stream_transform.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      module.exports = Transform;
      var Duplex = require_stream_duplex(), util = Object.create(require_util());
      util.inherits = require_inherits_browser();
      util.inherits(Transform, Duplex);
      function afterTransform(er, data) {
        var ts = this._transformState;
        ts.transforming = !1;
        var cb = ts.writecb;
        if (!cb)
          return this.emit("error", new Error("write callback called multiple times"));
        ts.writechunk = null, ts.writecb = null, data != null && this.push(data), cb(er);
        var rs = this._readableState;
        rs.reading = !1, (rs.needReadable || rs.length < rs.highWaterMark) && this._read(rs.highWaterMark);
      }
      function Transform(options) {
        if (!(this instanceof Transform)) return new Transform(options);
        Duplex.call(this, options), this._transformState = {
          afterTransform: afterTransform.bind(this),
          needTransform: !1,
          transforming: !1,
          writecb: null,
          writechunk: null,
          writeencoding: null
        }, this._readableState.needReadable = !0, this._readableState.sync = !1, options && (typeof options.transform == "function" && (this._transform = options.transform), typeof options.flush == "function" && (this._flush = options.flush)), this.on("prefinish", prefinish);
      }
      function prefinish() {
        var _this = this;
        typeof this._flush == "function" ? this._flush(function(er, data) {
          done(_this, er, data);
        }) : done(this, null, null);
      }
      Transform.prototype.push = function(chunk, encoding) {
        return this._transformState.needTransform = !1, Duplex.prototype.push.call(this, chunk, encoding);
      };
      Transform.prototype._transform = function(chunk, encoding, cb) {
        throw new Error("_transform() is not implemented");
      };
      Transform.prototype._write = function(chunk, encoding, cb) {
        var ts = this._transformState;
        if (ts.writecb = cb, ts.writechunk = chunk, ts.writeencoding = encoding, !ts.transforming) {
          var rs = this._readableState;
          (ts.needTransform || rs.needReadable || rs.length < rs.highWaterMark) && this._read(rs.highWaterMark);
        }
      };
      Transform.prototype._read = function(n) {
        var ts = this._transformState;
        ts.writechunk !== null && ts.writecb && !ts.transforming ? (ts.transforming = !0, this._transform(ts.writechunk, ts.writeencoding, ts.afterTransform)) : ts.needTransform = !0;
      };
      Transform.prototype._destroy = function(err, cb) {
        var _this2 = this;
        Duplex.prototype._destroy.call(this, err, function(err2) {
          cb(err2), _this2.emit("close");
        });
      };
      function done(stream, er, data) {
        if (er) return stream.emit("error", er);
        if (data != null && stream.push(data), stream._writableState.length) throw new Error("Calling transform done when ws.length != 0");
        if (stream._transformState.transforming) throw new Error("Calling transform done when still transforming");
        return stream.push(null);
      }
    }
  });

  // node_modules/readable-stream/lib/_stream_passthrough.js
  var require_stream_passthrough = __commonJS({
    "node_modules/readable-stream/lib/_stream_passthrough.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      module.exports = PassThrough;
      var Transform = require_stream_transform(), util = Object.create(require_util());
      util.inherits = require_inherits_browser();
      util.inherits(PassThrough, Transform);
      function PassThrough(options) {
        if (!(this instanceof PassThrough)) return new PassThrough(options);
        Transform.call(this, options);
      }
      PassThrough.prototype._transform = function(chunk, encoding, cb) {
        cb(null, chunk);
      };
    }
  });

  // node_modules/readable-stream/readable-browser.js
  var require_readable_browser = __commonJS({
    "node_modules/readable-stream/readable-browser.js"(exports, module) {
      init_buffer_shim();
      init_process_shim();
      exports = module.exports = require_stream_readable();
      exports.Stream = exports;
      exports.Readable = exports;
      exports.Writable = require_stream_writable();
      exports.Duplex = require_stream_duplex();
      exports.Transform = require_stream_transform();
      exports.PassThrough = require_stream_passthrough();
    }
  });

  // node_modules/hash-base/index.js
  var require_hash_base = __commonJS({
    "node_modules/hash-base/index.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      var Buffer4 = require_safe_buffer().Buffer, toBuffer = require_to_buffer2(), Transform = require_readable_browser().Transform, inherits = require_inherits_browser();
      function HashBase(blockSize) {
        Transform.call(this), this._block = Buffer4.allocUnsafe(blockSize), this._blockSize = blockSize, this._blockOffset = 0, this._length = [0, 0, 0, 0], this._finalized = !1;
      }
      inherits(HashBase, Transform);
      HashBase.prototype._transform = function(chunk, encoding, callback) {
        var error = null;
        try {
          this.update(chunk, encoding);
        } catch (err) {
          error = err;
        }
        callback(error);
      };
      HashBase.prototype._flush = function(callback) {
        var error = null;
        try {
          this.push(this.digest());
        } catch (err) {
          error = err;
        }
        callback(error);
      };
      HashBase.prototype.update = function(data, encoding) {
        if (this._finalized)
          throw new Error("Digest already called");
        for (var dataBuffer = toBuffer(data, encoding), block = this._block, offset = 0; this._blockOffset + dataBuffer.length - offset >= this._blockSize; ) {
          for (var i = this._blockOffset; i < this._blockSize; )
            block[i] = dataBuffer[offset], i += 1, offset += 1;
          this._update(), this._blockOffset = 0;
        }
        for (; offset < dataBuffer.length; )
          block[this._blockOffset] = dataBuffer[offset], this._blockOffset += 1, offset += 1;
        for (var j = 0, carry = dataBuffer.length * 8; carry > 0; ++j)
          this._length[j] += carry, carry = this._length[j] / 4294967296 | 0, carry > 0 && (this._length[j] -= 4294967296 * carry);
        return this;
      };
      HashBase.prototype._update = function() {
        throw new Error("_update is not implemented");
      };
      HashBase.prototype.digest = function(encoding) {
        if (this._finalized)
          throw new Error("Digest already called");
        this._finalized = !0;
        var digest = this._digest();
        encoding !== void 0 && (digest = digest.toString(encoding)), this._block.fill(0), this._blockOffset = 0;
        for (var i = 0; i < 4; ++i)
          this._length[i] = 0;
        return digest;
      };
      HashBase.prototype._digest = function() {
        throw new Error("_digest is not implemented");
      };
      module.exports = HashBase;
    }
  });

  // node_modules/md5.js/index.js
  var require_md5 = __commonJS({
    "node_modules/md5.js/index.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      var inherits = require_inherits_browser(), HashBase = require_hash_base(), Buffer4 = require_safe_buffer().Buffer, ARRAY16 = new Array(16);
      function MD5() {
        HashBase.call(this, 64), this._a = 1732584193, this._b = 4023233417, this._c = 2562383102, this._d = 271733878;
      }
      inherits(MD5, HashBase);
      MD5.prototype._update = function() {
        for (var M = ARRAY16, i = 0; i < 16; ++i) M[i] = this._block.readInt32LE(i * 4);
        var a = this._a, b = this._b, c = this._c, d = this._d;
        a = fnF(a, b, c, d, M[0], 3614090360, 7), d = fnF(d, a, b, c, M[1], 3905402710, 12), c = fnF(c, d, a, b, M[2], 606105819, 17), b = fnF(b, c, d, a, M[3], 3250441966, 22), a = fnF(a, b, c, d, M[4], 4118548399, 7), d = fnF(d, a, b, c, M[5], 1200080426, 12), c = fnF(c, d, a, b, M[6], 2821735955, 17), b = fnF(b, c, d, a, M[7], 4249261313, 22), a = fnF(a, b, c, d, M[8], 1770035416, 7), d = fnF(d, a, b, c, M[9], 2336552879, 12), c = fnF(c, d, a, b, M[10], 4294925233, 17), b = fnF(b, c, d, a, M[11], 2304563134, 22), a = fnF(a, b, c, d, M[12], 1804603682, 7), d = fnF(d, a, b, c, M[13], 4254626195, 12), c = fnF(c, d, a, b, M[14], 2792965006, 17), b = fnF(b, c, d, a, M[15], 1236535329, 22), a = fnG(a, b, c, d, M[1], 4129170786, 5), d = fnG(d, a, b, c, M[6], 3225465664, 9), c = fnG(c, d, a, b, M[11], 643717713, 14), b = fnG(b, c, d, a, M[0], 3921069994, 20), a = fnG(a, b, c, d, M[5], 3593408605, 5), d = fnG(d, a, b, c, M[10], 38016083, 9), c = fnG(c, d, a, b, M[15], 3634488961, 14), b = fnG(b, c, d, a, M[4], 3889429448, 20), a = fnG(a, b, c, d, M[9], 568446438, 5), d = fnG(d, a, b, c, M[14], 3275163606, 9), c = fnG(c, d, a, b, M[3], 4107603335, 14), b = fnG(b, c, d, a, M[8], 1163531501, 20), a = fnG(a, b, c, d, M[13], 2850285829, 5), d = fnG(d, a, b, c, M[2], 4243563512, 9), c = fnG(c, d, a, b, M[7], 1735328473, 14), b = fnG(b, c, d, a, M[12], 2368359562, 20), a = fnH(a, b, c, d, M[5], 4294588738, 4), d = fnH(d, a, b, c, M[8], 2272392833, 11), c = fnH(c, d, a, b, M[11], 1839030562, 16), b = fnH(b, c, d, a, M[14], 4259657740, 23), a = fnH(a, b, c, d, M[1], 2763975236, 4), d = fnH(d, a, b, c, M[4], 1272893353, 11), c = fnH(c, d, a, b, M[7], 4139469664, 16), b = fnH(b, c, d, a, M[10], 3200236656, 23), a = fnH(a, b, c, d, M[13], 681279174, 4), d = fnH(d, a, b, c, M[0], 3936430074, 11), c = fnH(c, d, a, b, M[3], 3572445317, 16), b = fnH(b, c, d, a, M[6], 76029189, 23), a = fnH(a, b, c, d, M[9], 3654602809, 4), d = fnH(d, a, b, c, M[12], 3873151461, 11), c = fnH(c, d, a, b, M[15], 530742520, 16), b = fnH(b, c, d, a, M[2], 3299628645, 23), a = fnI(a, b, c, d, M[0], 4096336452, 6), d = fnI(d, a, b, c, M[7], 1126891415, 10), c = fnI(c, d, a, b, M[14], 2878612391, 15), b = fnI(b, c, d, a, M[5], 4237533241, 21), a = fnI(a, b, c, d, M[12], 1700485571, 6), d = fnI(d, a, b, c, M[3], 2399980690, 10), c = fnI(c, d, a, b, M[10], 4293915773, 15), b = fnI(b, c, d, a, M[1], 2240044497, 21), a = fnI(a, b, c, d, M[8], 1873313359, 6), d = fnI(d, a, b, c, M[15], 4264355552, 10), c = fnI(c, d, a, b, M[6], 2734768916, 15), b = fnI(b, c, d, a, M[13], 1309151649, 21), a = fnI(a, b, c, d, M[4], 4149444226, 6), d = fnI(d, a, b, c, M[11], 3174756917, 10), c = fnI(c, d, a, b, M[2], 718787259, 15), b = fnI(b, c, d, a, M[9], 3951481745, 21), this._a = this._a + a | 0, this._b = this._b + b | 0, this._c = this._c + c | 0, this._d = this._d + d | 0;
      };
      MD5.prototype._digest = function() {
        this._block[this._blockOffset++] = 128, this._blockOffset > 56 && (this._block.fill(0, this._blockOffset, 64), this._update(), this._blockOffset = 0), this._block.fill(0, this._blockOffset, 56), this._block.writeUInt32LE(this._length[0], 56), this._block.writeUInt32LE(this._length[1], 60), this._update();
        var buffer = Buffer4.allocUnsafe(16);
        return buffer.writeInt32LE(this._a, 0), buffer.writeInt32LE(this._b, 4), buffer.writeInt32LE(this._c, 8), buffer.writeInt32LE(this._d, 12), buffer;
      };
      function rotl(x, n) {
        return x << n | x >>> 32 - n;
      }
      function fnF(a, b, c, d, m, k, s) {
        return rotl(a + (b & c | ~b & d) + m + k | 0, s) + b | 0;
      }
      function fnG(a, b, c, d, m, k, s) {
        return rotl(a + (b & d | c & ~d) + m + k | 0, s) + b | 0;
      }
      function fnH(a, b, c, d, m, k, s) {
        return rotl(a + (b ^ c ^ d) + m + k | 0, s) + b | 0;
      }
      function fnI(a, b, c, d, m, k, s) {
        return rotl(a + (c ^ (b | ~d)) + m + k | 0, s) + b | 0;
      }
      module.exports = MD5;
    }
  });

  // node_modules/ripemd160/index.js
  var require_ripemd1602 = __commonJS({
    "node_modules/ripemd160/index.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      var Buffer4 = require_buffer().Buffer, inherits = require_inherits_browser(), HashBase = require_hash_base(), ARRAY16 = new Array(16), zl = [
        0,
        1,
        2,
        3,
        4,
        5,
        6,
        7,
        8,
        9,
        10,
        11,
        12,
        13,
        14,
        15,
        7,
        4,
        13,
        1,
        10,
        6,
        15,
        3,
        12,
        0,
        9,
        5,
        2,
        14,
        11,
        8,
        3,
        10,
        14,
        4,
        9,
        15,
        8,
        1,
        2,
        7,
        0,
        6,
        13,
        11,
        5,
        12,
        1,
        9,
        11,
        10,
        0,
        8,
        12,
        4,
        13,
        3,
        7,
        15,
        14,
        5,
        6,
        2,
        4,
        0,
        5,
        9,
        7,
        12,
        2,
        10,
        14,
        1,
        3,
        8,
        11,
        6,
        15,
        13
      ], zr = [
        5,
        14,
        7,
        0,
        9,
        2,
        11,
        4,
        13,
        6,
        15,
        8,
        1,
        10,
        3,
        12,
        6,
        11,
        3,
        7,
        0,
        13,
        5,
        10,
        14,
        15,
        8,
        12,
        4,
        9,
        1,
        2,
        15,
        5,
        1,
        3,
        7,
        14,
        6,
        9,
        11,
        8,
        12,
        2,
        10,
        0,
        4,
        13,
        8,
        6,
        4,
        1,
        3,
        11,
        15,
        0,
        5,
        12,
        2,
        13,
        9,
        7,
        10,
        14,
        12,
        15,
        10,
        4,
        1,
        5,
        8,
        7,
        6,
        2,
        13,
        14,
        0,
        3,
        9,
        11
      ], sl = [
        11,
        14,
        15,
        12,
        5,
        8,
        7,
        9,
        11,
        13,
        14,
        15,
        6,
        7,
        9,
        8,
        7,
        6,
        8,
        13,
        11,
        9,
        7,
        15,
        7,
        12,
        15,
        9,
        11,
        7,
        13,
        12,
        11,
        13,
        6,
        7,
        14,
        9,
        13,
        15,
        14,
        8,
        13,
        6,
        5,
        12,
        7,
        5,
        11,
        12,
        14,
        15,
        14,
        15,
        9,
        8,
        9,
        14,
        5,
        6,
        8,
        6,
        5,
        12,
        9,
        15,
        5,
        11,
        6,
        8,
        13,
        12,
        5,
        12,
        13,
        14,
        11,
        8,
        5,
        6
      ], sr = [
        8,
        9,
        9,
        11,
        13,
        15,
        15,
        5,
        7,
        7,
        8,
        11,
        14,
        14,
        12,
        6,
        9,
        13,
        15,
        7,
        12,
        8,
        9,
        11,
        7,
        7,
        12,
        7,
        6,
        15,
        13,
        11,
        9,
        7,
        15,
        11,
        8,
        6,
        6,
        14,
        12,
        13,
        5,
        14,
        13,
        13,
        7,
        5,
        15,
        5,
        8,
        11,
        14,
        14,
        6,
        14,
        6,
        9,
        12,
        9,
        12,
        5,
        15,
        8,
        8,
        5,
        12,
        9,
        12,
        5,
        14,
        6,
        8,
        13,
        6,
        5,
        15,
        13,
        11,
        11
      ], hl = [0, 1518500249, 1859775393, 2400959708, 2840853838], hr = [1352829926, 1548603684, 1836072691, 2053994217, 0];
      function rotl(x, n) {
        return x << n | x >>> 32 - n;
      }
      function fn1(a, b, c, d, e, m, k, s) {
        return rotl(a + (b ^ c ^ d) + m + k | 0, s) + e | 0;
      }
      function fn2(a, b, c, d, e, m, k, s) {
        return rotl(a + (b & c | ~b & d) + m + k | 0, s) + e | 0;
      }
      function fn3(a, b, c, d, e, m, k, s) {
        return rotl(a + ((b | ~c) ^ d) + m + k | 0, s) + e | 0;
      }
      function fn4(a, b, c, d, e, m, k, s) {
        return rotl(a + (b & d | c & ~d) + m + k | 0, s) + e | 0;
      }
      function fn5(a, b, c, d, e, m, k, s) {
        return rotl(a + (b ^ (c | ~d)) + m + k | 0, s) + e | 0;
      }
      function RIPEMD160() {
        HashBase.call(this, 64), this._a = 1732584193, this._b = 4023233417, this._c = 2562383102, this._d = 271733878, this._e = 3285377520;
      }
      inherits(RIPEMD160, HashBase);
      RIPEMD160.prototype._update = function() {
        for (var words = ARRAY16, j = 0; j < 16; ++j)
          words[j] = this._block.readInt32LE(j * 4);
        for (var al = this._a | 0, bl = this._b | 0, cl = this._c | 0, dl = this._d | 0, el = this._e | 0, ar = this._a | 0, br = this._b | 0, cr = this._c | 0, dr = this._d | 0, er = this._e | 0, i = 0; i < 80; i += 1) {
          var tl, tr;
          i < 16 ? (tl = fn1(al, bl, cl, dl, el, words[zl[i]], hl[0], sl[i]), tr = fn5(ar, br, cr, dr, er, words[zr[i]], hr[0], sr[i])) : i < 32 ? (tl = fn2(al, bl, cl, dl, el, words[zl[i]], hl[1], sl[i]), tr = fn4(ar, br, cr, dr, er, words[zr[i]], hr[1], sr[i])) : i < 48 ? (tl = fn3(al, bl, cl, dl, el, words[zl[i]], hl[2], sl[i]), tr = fn3(ar, br, cr, dr, er, words[zr[i]], hr[2], sr[i])) : i < 64 ? (tl = fn4(al, bl, cl, dl, el, words[zl[i]], hl[3], sl[i]), tr = fn2(ar, br, cr, dr, er, words[zr[i]], hr[3], sr[i])) : (tl = fn5(al, bl, cl, dl, el, words[zl[i]], hl[4], sl[i]), tr = fn1(ar, br, cr, dr, er, words[zr[i]], hr[4], sr[i])), al = el, el = dl, dl = rotl(cl, 10), cl = bl, bl = tl, ar = er, er = dr, dr = rotl(cr, 10), cr = br, br = tr;
        }
        var t = this._b + cl + dr | 0;
        this._b = this._c + dl + er | 0, this._c = this._d + el + ar | 0, this._d = this._e + al + br | 0, this._e = this._a + bl + cr | 0, this._a = t;
      };
      RIPEMD160.prototype._digest = function() {
        this._block[this._blockOffset] = 128, this._blockOffset += 1, this._blockOffset > 56 && (this._block.fill(0, this._blockOffset, 64), this._update(), this._blockOffset = 0), this._block.fill(0, this._blockOffset, 56), this._block.writeUInt32LE(this._length[0], 56), this._block.writeUInt32LE(this._length[1], 60), this._update();
        var buffer = Buffer4.alloc ? Buffer4.alloc(20) : new Buffer4(20);
        return buffer.writeInt32LE(this._a, 0), buffer.writeInt32LE(this._b, 4), buffer.writeInt32LE(this._c, 8), buffer.writeInt32LE(this._d, 12), buffer.writeInt32LE(this._e, 16), buffer;
      };
      module.exports = RIPEMD160;
    }
  });

  // node_modules/sha.js/hash.js
  var require_hash = __commonJS({
    "node_modules/sha.js/hash.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      var Buffer4 = require_safe_buffer().Buffer, toBuffer = require_to_buffer();
      function Hash(blockSize, finalSize) {
        this._block = Buffer4.alloc(blockSize), this._finalSize = finalSize, this._blockSize = blockSize, this._len = 0;
      }
      Hash.prototype.update = function(data, enc) {
        data = toBuffer(data, enc || "utf8");
        for (var block = this._block, blockSize = this._blockSize, length = data.length, accum = this._len, offset = 0; offset < length; ) {
          for (var assigned = accum % blockSize, remainder = Math.min(length - offset, blockSize - assigned), i = 0; i < remainder; i++)
            block[assigned + i] = data[offset + i];
          accum += remainder, offset += remainder, accum % blockSize === 0 && this._update(block);
        }
        return this._len += length, this;
      };
      Hash.prototype.digest = function(enc) {
        var rem = this._len % this._blockSize;
        this._block[rem] = 128, this._block.fill(0, rem + 1), rem >= this._finalSize && (this._update(this._block), this._block.fill(0));
        var bits = this._len * 8;
        if (bits <= 4294967295)
          this._block.writeUInt32BE(bits, this._blockSize - 4);
        else {
          var lowBits = (bits & 4294967295) >>> 0, highBits = (bits - lowBits) / 4294967296;
          this._block.writeUInt32BE(highBits, this._blockSize - 8), this._block.writeUInt32BE(lowBits, this._blockSize - 4);
        }
        this._update(this._block);
        var hash = this._hash();
        return enc ? hash.toString(enc) : hash;
      };
      Hash.prototype._update = function() {
        throw new Error("_update must be implemented by subclass");
      };
      module.exports = Hash;
    }
  });

  // node_modules/sha.js/sha.js
  var require_sha = __commonJS({
    "node_modules/sha.js/sha.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      var inherits = require_inherits_browser(), Hash = require_hash(), Buffer4 = require_safe_buffer().Buffer, K = [
        1518500249,
        1859775393,
        -1894007588,
        -899497514
      ], W = new Array(80);
      function Sha() {
        this.init(), this._w = W, Hash.call(this, 64, 56);
      }
      inherits(Sha, Hash);
      Sha.prototype.init = function() {
        return this._a = 1732584193, this._b = 4023233417, this._c = 2562383102, this._d = 271733878, this._e = 3285377520, this;
      };
      function rotl5(num) {
        return num << 5 | num >>> 27;
      }
      function rotl30(num) {
        return num << 30 | num >>> 2;
      }
      function ft(s, b, c, d) {
        return s === 0 ? b & c | ~b & d : s === 2 ? b & c | b & d | c & d : b ^ c ^ d;
      }
      Sha.prototype._update = function(M) {
        for (var w = this._w, a = this._a | 0, b = this._b | 0, c = this._c | 0, d = this._d | 0, e = this._e | 0, i = 0; i < 16; ++i)
          w[i] = M.readInt32BE(i * 4);
        for (; i < 80; ++i)
          w[i] = w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16];
        for (var j = 0; j < 80; ++j) {
          var s = ~~(j / 20), t = rotl5(a) + ft(s, b, c, d) + e + w[j] + K[s] | 0;
          e = d, d = c, c = rotl30(b), b = a, a = t;
        }
        this._a = a + this._a | 0, this._b = b + this._b | 0, this._c = c + this._c | 0, this._d = d + this._d | 0, this._e = e + this._e | 0;
      };
      Sha.prototype._hash = function() {
        var H = Buffer4.allocUnsafe(20);
        return H.writeInt32BE(this._a | 0, 0), H.writeInt32BE(this._b | 0, 4), H.writeInt32BE(this._c | 0, 8), H.writeInt32BE(this._d | 0, 12), H.writeInt32BE(this._e | 0, 16), H;
      };
      module.exports = Sha;
    }
  });

  // node_modules/sha.js/sha1.js
  var require_sha12 = __commonJS({
    "node_modules/sha.js/sha1.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      var inherits = require_inherits_browser(), Hash = require_hash(), Buffer4 = require_safe_buffer().Buffer, K = [
        1518500249,
        1859775393,
        -1894007588,
        -899497514
      ], W = new Array(80);
      function Sha1() {
        this.init(), this._w = W, Hash.call(this, 64, 56);
      }
      inherits(Sha1, Hash);
      Sha1.prototype.init = function() {
        return this._a = 1732584193, this._b = 4023233417, this._c = 2562383102, this._d = 271733878, this._e = 3285377520, this;
      };
      function rotl1(num) {
        return num << 1 | num >>> 31;
      }
      function rotl5(num) {
        return num << 5 | num >>> 27;
      }
      function rotl30(num) {
        return num << 30 | num >>> 2;
      }
      function ft(s, b, c, d) {
        return s === 0 ? b & c | ~b & d : s === 2 ? b & c | b & d | c & d : b ^ c ^ d;
      }
      Sha1.prototype._update = function(M) {
        for (var w = this._w, a = this._a | 0, b = this._b | 0, c = this._c | 0, d = this._d | 0, e = this._e | 0, i = 0; i < 16; ++i)
          w[i] = M.readInt32BE(i * 4);
        for (; i < 80; ++i)
          w[i] = rotl1(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16]);
        for (var j = 0; j < 80; ++j) {
          var s = ~~(j / 20), t = rotl5(a) + ft(s, b, c, d) + e + w[j] + K[s] | 0;
          e = d, d = c, c = rotl30(b), b = a, a = t;
        }
        this._a = a + this._a | 0, this._b = b + this._b | 0, this._c = c + this._c | 0, this._d = d + this._d | 0, this._e = e + this._e | 0;
      };
      Sha1.prototype._hash = function() {
        var H = Buffer4.allocUnsafe(20);
        return H.writeInt32BE(this._a | 0, 0), H.writeInt32BE(this._b | 0, 4), H.writeInt32BE(this._c | 0, 8), H.writeInt32BE(this._d | 0, 12), H.writeInt32BE(this._e | 0, 16), H;
      };
      module.exports = Sha1;
    }
  });

  // node_modules/sha.js/sha256.js
  var require_sha2562 = __commonJS({
    "node_modules/sha.js/sha256.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      var inherits = require_inherits_browser(), Hash = require_hash(), Buffer4 = require_safe_buffer().Buffer, K = [
        1116352408,
        1899447441,
        3049323471,
        3921009573,
        961987163,
        1508970993,
        2453635748,
        2870763221,
        3624381080,
        310598401,
        607225278,
        1426881987,
        1925078388,
        2162078206,
        2614888103,
        3248222580,
        3835390401,
        4022224774,
        264347078,
        604807628,
        770255983,
        1249150122,
        1555081692,
        1996064986,
        2554220882,
        2821834349,
        2952996808,
        3210313671,
        3336571891,
        3584528711,
        113926993,
        338241895,
        666307205,
        773529912,
        1294757372,
        1396182291,
        1695183700,
        1986661051,
        2177026350,
        2456956037,
        2730485921,
        2820302411,
        3259730800,
        3345764771,
        3516065817,
        3600352804,
        4094571909,
        275423344,
        430227734,
        506948616,
        659060556,
        883997877,
        958139571,
        1322822218,
        1537002063,
        1747873779,
        1955562222,
        2024104815,
        2227730452,
        2361852424,
        2428436474,
        2756734187,
        3204031479,
        3329325298
      ], W = new Array(64);
      function Sha256() {
        this.init(), this._w = W, Hash.call(this, 64, 56);
      }
      inherits(Sha256, Hash);
      Sha256.prototype.init = function() {
        return this._a = 1779033703, this._b = 3144134277, this._c = 1013904242, this._d = 2773480762, this._e = 1359893119, this._f = 2600822924, this._g = 528734635, this._h = 1541459225, this;
      };
      function ch(x, y, z) {
        return z ^ x & (y ^ z);
      }
      function maj(x, y, z) {
        return x & y | z & (x | y);
      }
      function sigma0(x) {
        return (x >>> 2 | x << 30) ^ (x >>> 13 | x << 19) ^ (x >>> 22 | x << 10);
      }
      function sigma1(x) {
        return (x >>> 6 | x << 26) ^ (x >>> 11 | x << 21) ^ (x >>> 25 | x << 7);
      }
      function gamma0(x) {
        return (x >>> 7 | x << 25) ^ (x >>> 18 | x << 14) ^ x >>> 3;
      }
      function gamma1(x) {
        return (x >>> 17 | x << 15) ^ (x >>> 19 | x << 13) ^ x >>> 10;
      }
      Sha256.prototype._update = function(M) {
        for (var w = this._w, a = this._a | 0, b = this._b | 0, c = this._c | 0, d = this._d | 0, e = this._e | 0, f = this._f | 0, g = this._g | 0, h = this._h | 0, i = 0; i < 16; ++i)
          w[i] = M.readInt32BE(i * 4);
        for (; i < 64; ++i)
          w[i] = gamma1(w[i - 2]) + w[i - 7] + gamma0(w[i - 15]) + w[i - 16] | 0;
        for (var j = 0; j < 64; ++j) {
          var T1 = h + sigma1(e) + ch(e, f, g) + K[j] + w[j] | 0, T2 = sigma0(a) + maj(a, b, c) | 0;
          h = g, g = f, f = e, e = d + T1 | 0, d = c, c = b, b = a, a = T1 + T2 | 0;
        }
        this._a = a + this._a | 0, this._b = b + this._b | 0, this._c = c + this._c | 0, this._d = d + this._d | 0, this._e = e + this._e | 0, this._f = f + this._f | 0, this._g = g + this._g | 0, this._h = h + this._h | 0;
      };
      Sha256.prototype._hash = function() {
        var H = Buffer4.allocUnsafe(32);
        return H.writeInt32BE(this._a, 0), H.writeInt32BE(this._b, 4), H.writeInt32BE(this._c, 8), H.writeInt32BE(this._d, 12), H.writeInt32BE(this._e, 16), H.writeInt32BE(this._f, 20), H.writeInt32BE(this._g, 24), H.writeInt32BE(this._h, 28), H;
      };
      module.exports = Sha256;
    }
  });

  // node_modules/sha.js/sha224.js
  var require_sha224 = __commonJS({
    "node_modules/sha.js/sha224.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      var inherits = require_inherits_browser(), Sha256 = require_sha2562(), Hash = require_hash(), Buffer4 = require_safe_buffer().Buffer, W = new Array(64);
      function Sha224() {
        this.init(), this._w = W, Hash.call(this, 64, 56);
      }
      inherits(Sha224, Sha256);
      Sha224.prototype.init = function() {
        return this._a = 3238371032, this._b = 914150663, this._c = 812702999, this._d = 4144912697, this._e = 4290775857, this._f = 1750603025, this._g = 1694076839, this._h = 3204075428, this;
      };
      Sha224.prototype._hash = function() {
        var H = Buffer4.allocUnsafe(28);
        return H.writeInt32BE(this._a, 0), H.writeInt32BE(this._b, 4), H.writeInt32BE(this._c, 8), H.writeInt32BE(this._d, 12), H.writeInt32BE(this._e, 16), H.writeInt32BE(this._f, 20), H.writeInt32BE(this._g, 24), H;
      };
      module.exports = Sha224;
    }
  });

  // node_modules/sha.js/sha512.js
  var require_sha5122 = __commonJS({
    "node_modules/sha.js/sha512.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      var inherits = require_inherits_browser(), Hash = require_hash(), Buffer4 = require_safe_buffer().Buffer, K = [
        1116352408,
        3609767458,
        1899447441,
        602891725,
        3049323471,
        3964484399,
        3921009573,
        2173295548,
        961987163,
        4081628472,
        1508970993,
        3053834265,
        2453635748,
        2937671579,
        2870763221,
        3664609560,
        3624381080,
        2734883394,
        310598401,
        1164996542,
        607225278,
        1323610764,
        1426881987,
        3590304994,
        1925078388,
        4068182383,
        2162078206,
        991336113,
        2614888103,
        633803317,
        3248222580,
        3479774868,
        3835390401,
        2666613458,
        4022224774,
        944711139,
        264347078,
        2341262773,
        604807628,
        2007800933,
        770255983,
        1495990901,
        1249150122,
        1856431235,
        1555081692,
        3175218132,
        1996064986,
        2198950837,
        2554220882,
        3999719339,
        2821834349,
        766784016,
        2952996808,
        2566594879,
        3210313671,
        3203337956,
        3336571891,
        1034457026,
        3584528711,
        2466948901,
        113926993,
        3758326383,
        338241895,
        168717936,
        666307205,
        1188179964,
        773529912,
        1546045734,
        1294757372,
        1522805485,
        1396182291,
        2643833823,
        1695183700,
        2343527390,
        1986661051,
        1014477480,
        2177026350,
        1206759142,
        2456956037,
        344077627,
        2730485921,
        1290863460,
        2820302411,
        3158454273,
        3259730800,
        3505952657,
        3345764771,
        106217008,
        3516065817,
        3606008344,
        3600352804,
        1432725776,
        4094571909,
        1467031594,
        275423344,
        851169720,
        430227734,
        3100823752,
        506948616,
        1363258195,
        659060556,
        3750685593,
        883997877,
        3785050280,
        958139571,
        3318307427,
        1322822218,
        3812723403,
        1537002063,
        2003034995,
        1747873779,
        3602036899,
        1955562222,
        1575990012,
        2024104815,
        1125592928,
        2227730452,
        2716904306,
        2361852424,
        442776044,
        2428436474,
        593698344,
        2756734187,
        3733110249,
        3204031479,
        2999351573,
        3329325298,
        3815920427,
        3391569614,
        3928383900,
        3515267271,
        566280711,
        3940187606,
        3454069534,
        4118630271,
        4000239992,
        116418474,
        1914138554,
        174292421,
        2731055270,
        289380356,
        3203993006,
        460393269,
        320620315,
        685471733,
        587496836,
        852142971,
        1086792851,
        1017036298,
        365543100,
        1126000580,
        2618297676,
        1288033470,
        3409855158,
        1501505948,
        4234509866,
        1607167915,
        987167468,
        1816402316,
        1246189591
      ], W = new Array(160);
      function Sha512() {
        this.init(), this._w = W, Hash.call(this, 128, 112);
      }
      inherits(Sha512, Hash);
      Sha512.prototype.init = function() {
        return this._ah = 1779033703, this._bh = 3144134277, this._ch = 1013904242, this._dh = 2773480762, this._eh = 1359893119, this._fh = 2600822924, this._gh = 528734635, this._hh = 1541459225, this._al = 4089235720, this._bl = 2227873595, this._cl = 4271175723, this._dl = 1595750129, this._el = 2917565137, this._fl = 725511199, this._gl = 4215389547, this._hl = 327033209, this;
      };
      function Ch(x, y, z) {
        return z ^ x & (y ^ z);
      }
      function maj(x, y, z) {
        return x & y | z & (x | y);
      }
      function sigma0(x, xl) {
        return (x >>> 28 | xl << 4) ^ (xl >>> 2 | x << 30) ^ (xl >>> 7 | x << 25);
      }
      function sigma1(x, xl) {
        return (x >>> 14 | xl << 18) ^ (x >>> 18 | xl << 14) ^ (xl >>> 9 | x << 23);
      }
      function Gamma0(x, xl) {
        return (x >>> 1 | xl << 31) ^ (x >>> 8 | xl << 24) ^ x >>> 7;
      }
      function Gamma0l(x, xl) {
        return (x >>> 1 | xl << 31) ^ (x >>> 8 | xl << 24) ^ (x >>> 7 | xl << 25);
      }
      function Gamma1(x, xl) {
        return (x >>> 19 | xl << 13) ^ (xl >>> 29 | x << 3) ^ x >>> 6;
      }
      function Gamma1l(x, xl) {
        return (x >>> 19 | xl << 13) ^ (xl >>> 29 | x << 3) ^ (x >>> 6 | xl << 26);
      }
      function getCarry(a, b) {
        return a >>> 0 < b >>> 0 ? 1 : 0;
      }
      Sha512.prototype._update = function(M) {
        for (var w = this._w, ah = this._ah | 0, bh = this._bh | 0, ch = this._ch | 0, dh = this._dh | 0, eh = this._eh | 0, fh = this._fh | 0, gh = this._gh | 0, hh = this._hh | 0, al = this._al | 0, bl = this._bl | 0, cl = this._cl | 0, dl = this._dl | 0, el = this._el | 0, fl = this._fl | 0, gl = this._gl | 0, hl = this._hl | 0, i = 0; i < 32; i += 2)
          w[i] = M.readInt32BE(i * 4), w[i + 1] = M.readInt32BE(i * 4 + 4);
        for (; i < 160; i += 2) {
          var xh = w[i - 30], xl = w[i - 30 + 1], gamma0 = Gamma0(xh, xl), gamma0l = Gamma0l(xl, xh);
          xh = w[i - 4], xl = w[i - 4 + 1];
          var gamma1 = Gamma1(xh, xl), gamma1l = Gamma1l(xl, xh), Wi7h = w[i - 14], Wi7l = w[i - 14 + 1], Wi16h = w[i - 32], Wi16l = w[i - 32 + 1], Wil = gamma0l + Wi7l | 0, Wih = gamma0 + Wi7h + getCarry(Wil, gamma0l) | 0;
          Wil = Wil + gamma1l | 0, Wih = Wih + gamma1 + getCarry(Wil, gamma1l) | 0, Wil = Wil + Wi16l | 0, Wih = Wih + Wi16h + getCarry(Wil, Wi16l) | 0, w[i] = Wih, w[i + 1] = Wil;
        }
        for (var j = 0; j < 160; j += 2) {
          Wih = w[j], Wil = w[j + 1];
          var majh = maj(ah, bh, ch), majl = maj(al, bl, cl), sigma0h = sigma0(ah, al), sigma0l = sigma0(al, ah), sigma1h = sigma1(eh, el), sigma1l = sigma1(el, eh), Kih = K[j], Kil = K[j + 1], chh = Ch(eh, fh, gh), chl = Ch(el, fl, gl), t1l = hl + sigma1l | 0, t1h = hh + sigma1h + getCarry(t1l, hl) | 0;
          t1l = t1l + chl | 0, t1h = t1h + chh + getCarry(t1l, chl) | 0, t1l = t1l + Kil | 0, t1h = t1h + Kih + getCarry(t1l, Kil) | 0, t1l = t1l + Wil | 0, t1h = t1h + Wih + getCarry(t1l, Wil) | 0;
          var t2l = sigma0l + majl | 0, t2h = sigma0h + majh + getCarry(t2l, sigma0l) | 0;
          hh = gh, hl = gl, gh = fh, gl = fl, fh = eh, fl = el, el = dl + t1l | 0, eh = dh + t1h + getCarry(el, dl) | 0, dh = ch, dl = cl, ch = bh, cl = bl, bh = ah, bl = al, al = t1l + t2l | 0, ah = t1h + t2h + getCarry(al, t1l) | 0;
        }
        this._al = this._al + al | 0, this._bl = this._bl + bl | 0, this._cl = this._cl + cl | 0, this._dl = this._dl + dl | 0, this._el = this._el + el | 0, this._fl = this._fl + fl | 0, this._gl = this._gl + gl | 0, this._hl = this._hl + hl | 0, this._ah = this._ah + ah + getCarry(this._al, al) | 0, this._bh = this._bh + bh + getCarry(this._bl, bl) | 0, this._ch = this._ch + ch + getCarry(this._cl, cl) | 0, this._dh = this._dh + dh + getCarry(this._dl, dl) | 0, this._eh = this._eh + eh + getCarry(this._el, el) | 0, this._fh = this._fh + fh + getCarry(this._fl, fl) | 0, this._gh = this._gh + gh + getCarry(this._gl, gl) | 0, this._hh = this._hh + hh + getCarry(this._hl, hl) | 0;
      };
      Sha512.prototype._hash = function() {
        var H = Buffer4.allocUnsafe(64);
        function writeInt64BE(h, l, offset) {
          H.writeInt32BE(h, offset), H.writeInt32BE(l, offset + 4);
        }
        return writeInt64BE(this._ah, this._al, 0), writeInt64BE(this._bh, this._bl, 8), writeInt64BE(this._ch, this._cl, 16), writeInt64BE(this._dh, this._dl, 24), writeInt64BE(this._eh, this._el, 32), writeInt64BE(this._fh, this._fl, 40), writeInt64BE(this._gh, this._gl, 48), writeInt64BE(this._hh, this._hl, 56), H;
      };
      module.exports = Sha512;
    }
  });

  // node_modules/sha.js/sha384.js
  var require_sha384 = __commonJS({
    "node_modules/sha.js/sha384.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      var inherits = require_inherits_browser(), SHA512 = require_sha5122(), Hash = require_hash(), Buffer4 = require_safe_buffer().Buffer, W = new Array(160);
      function Sha384() {
        this.init(), this._w = W, Hash.call(this, 128, 112);
      }
      inherits(Sha384, SHA512);
      Sha384.prototype.init = function() {
        return this._ah = 3418070365, this._bh = 1654270250, this._ch = 2438529370, this._dh = 355462360, this._eh = 1731405415, this._fh = 2394180231, this._gh = 3675008525, this._hh = 1203062813, this._al = 3238371032, this._bl = 914150663, this._cl = 812702999, this._dl = 4144912697, this._el = 4290775857, this._fl = 1750603025, this._gl = 1694076839, this._hl = 3204075428, this;
      };
      Sha384.prototype._hash = function() {
        var H = Buffer4.allocUnsafe(48);
        function writeInt64BE(h, l, offset) {
          H.writeInt32BE(h, offset), H.writeInt32BE(l, offset + 4);
        }
        return writeInt64BE(this._ah, this._al, 0), writeInt64BE(this._bh, this._bl, 8), writeInt64BE(this._ch, this._cl, 16), writeInt64BE(this._dh, this._dl, 24), writeInt64BE(this._eh, this._el, 32), writeInt64BE(this._fh, this._fl, 40), H;
      };
      module.exports = Sha384;
    }
  });

  // node_modules/sha.js/index.js
  var require_sha3 = __commonJS({
    "node_modules/sha.js/index.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      module.exports = function(algorithm) {
        var alg = algorithm.toLowerCase(), Algorithm = module.exports[alg];
        if (!Algorithm)
          throw new Error(alg + " is not supported (we accept pull requests)");
        return new Algorithm();
      };
      module.exports.sha = require_sha();
      module.exports.sha1 = require_sha12();
      module.exports.sha224 = require_sha224();
      module.exports.sha256 = require_sha2562();
      module.exports.sha384 = require_sha384();
      module.exports.sha512 = require_sha5122();
    }
  });

  // node_modules/stream-browserify/node_modules/readable-stream/lib/internal/streams/stream-browser.js
  var require_stream_browser2 = __commonJS({
    "node_modules/stream-browserify/node_modules/readable-stream/lib/internal/streams/stream-browser.js"(exports, module) {
      init_buffer_shim();
      init_process_shim();
      module.exports = require_events().EventEmitter;
    }
  });

  // node_modules/stream-browserify/node_modules/readable-stream/lib/internal/streams/buffer_list.js
  var require_buffer_list = __commonJS({
    "node_modules/stream-browserify/node_modules/readable-stream/lib/internal/streams/buffer_list.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      function ownKeys(object, enumerableOnly) {
        var keys = Object.keys(object);
        if (Object.getOwnPropertySymbols) {
          var symbols = Object.getOwnPropertySymbols(object);
          enumerableOnly && (symbols = symbols.filter(function(sym) {
            return Object.getOwnPropertyDescriptor(object, sym).enumerable;
          })), keys.push.apply(keys, symbols);
        }
        return keys;
      }
      function _objectSpread(target) {
        for (var i = 1; i < arguments.length; i++) {
          var source = arguments[i] != null ? arguments[i] : {};
          i % 2 ? ownKeys(Object(source), !0).forEach(function(key) {
            _defineProperty(target, key, source[key]);
          }) : Object.getOwnPropertyDescriptors ? Object.defineProperties(target, Object.getOwnPropertyDescriptors(source)) : ownKeys(Object(source)).forEach(function(key) {
            Object.defineProperty(target, key, Object.getOwnPropertyDescriptor(source, key));
          });
        }
        return target;
      }
      function _defineProperty(obj, key, value) {
        return key = _toPropertyKey(key), key in obj ? Object.defineProperty(obj, key, { value, enumerable: !0, configurable: !0, writable: !0 }) : obj[key] = value, obj;
      }
      function _classCallCheck(instance, Constructor) {
        if (!(instance instanceof Constructor))
          throw new TypeError("Cannot call a class as a function");
      }
      function _defineProperties(target, props) {
        for (var i = 0; i < props.length; i++) {
          var descriptor = props[i];
          descriptor.enumerable = descriptor.enumerable || !1, descriptor.configurable = !0, "value" in descriptor && (descriptor.writable = !0), Object.defineProperty(target, _toPropertyKey(descriptor.key), descriptor);
        }
      }
      function _createClass(Constructor, protoProps, staticProps) {
        return protoProps && _defineProperties(Constructor.prototype, protoProps), staticProps && _defineProperties(Constructor, staticProps), Object.defineProperty(Constructor, "prototype", { writable: !1 }), Constructor;
      }
      function _toPropertyKey(arg) {
        var key = _toPrimitive(arg, "string");
        return typeof key == "symbol" ? key : String(key);
      }
      function _toPrimitive(input, hint) {
        if (typeof input != "object" || input === null) return input;
        var prim = input[Symbol.toPrimitive];
        if (prim !== void 0) {
          var res = prim.call(input, hint || "default");
          if (typeof res != "object") return res;
          throw new TypeError("@@toPrimitive must return a primitive value.");
        }
        return (hint === "string" ? String : Number)(input);
      }
      var _require = require_buffer(), Buffer4 = _require.Buffer, _require2 = require_util2(), inspect = _require2.inspect, custom = inspect && inspect.custom || "inspect";
      function copyBuffer(src, target, offset) {
        Buffer4.prototype.copy.call(src, target, offset);
      }
      module.exports = /* @__PURE__ */ (function() {
        function BufferList() {
          _classCallCheck(this, BufferList), this.head = null, this.tail = null, this.length = 0;
        }
        return _createClass(BufferList, [{
          key: "push",
          value: function(v) {
            var entry = {
              data: v,
              next: null
            };
            this.length > 0 ? this.tail.next = entry : this.head = entry, this.tail = entry, ++this.length;
          }
        }, {
          key: "unshift",
          value: function(v) {
            var entry = {
              data: v,
              next: this.head
            };
            this.length === 0 && (this.tail = entry), this.head = entry, ++this.length;
          }
        }, {
          key: "shift",
          value: function() {
            if (this.length !== 0) {
              var ret = this.head.data;
              return this.length === 1 ? this.head = this.tail = null : this.head = this.head.next, --this.length, ret;
            }
          }
        }, {
          key: "clear",
          value: function() {
            this.head = this.tail = null, this.length = 0;
          }
        }, {
          key: "join",
          value: function(s) {
            if (this.length === 0) return "";
            for (var p = this.head, ret = "" + p.data; p = p.next; ) ret += s + p.data;
            return ret;
          }
        }, {
          key: "concat",
          value: function(n) {
            if (this.length === 0) return Buffer4.alloc(0);
            for (var ret = Buffer4.allocUnsafe(n >>> 0), p = this.head, i = 0; p; )
              copyBuffer(p.data, ret, i), i += p.data.length, p = p.next;
            return ret;
          }
          // Consumes a specified amount of bytes or characters from the buffered data.
        }, {
          key: "consume",
          value: function(n, hasStrings) {
            var ret;
            return n < this.head.data.length ? (ret = this.head.data.slice(0, n), this.head.data = this.head.data.slice(n)) : n === this.head.data.length ? ret = this.shift() : ret = hasStrings ? this._getString(n) : this._getBuffer(n), ret;
          }
        }, {
          key: "first",
          value: function() {
            return this.head.data;
          }
          // Consumes a specified amount of characters from the buffered data.
        }, {
          key: "_getString",
          value: function(n) {
            var p = this.head, c = 1, ret = p.data;
            for (n -= ret.length; p = p.next; ) {
              var str = p.data, nb = n > str.length ? str.length : n;
              if (nb === str.length ? ret += str : ret += str.slice(0, n), n -= nb, n === 0) {
                nb === str.length ? (++c, p.next ? this.head = p.next : this.head = this.tail = null) : (this.head = p, p.data = str.slice(nb));
                break;
              }
              ++c;
            }
            return this.length -= c, ret;
          }
          // Consumes a specified amount of bytes from the buffered data.
        }, {
          key: "_getBuffer",
          value: function(n) {
            var ret = Buffer4.allocUnsafe(n), p = this.head, c = 1;
            for (p.data.copy(ret), n -= p.data.length; p = p.next; ) {
              var buf = p.data, nb = n > buf.length ? buf.length : n;
              if (buf.copy(ret, ret.length - n, 0, nb), n -= nb, n === 0) {
                nb === buf.length ? (++c, p.next ? this.head = p.next : this.head = this.tail = null) : (this.head = p, p.data = buf.slice(nb));
                break;
              }
              ++c;
            }
            return this.length -= c, ret;
          }
          // Make sure the linked list only shows the minimal necessary information.
        }, {
          key: custom,
          value: function(_, options) {
            return inspect(this, _objectSpread(_objectSpread({}, options), {}, {
              // Only inspect one level.
              depth: 0,
              // It should not recurse.
              customInspect: !1
            }));
          }
        }]), BufferList;
      })();
    }
  });

  // node_modules/stream-browserify/node_modules/readable-stream/lib/internal/streams/destroy.js
  var require_destroy2 = __commonJS({
    "node_modules/stream-browserify/node_modules/readable-stream/lib/internal/streams/destroy.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      function destroy(err, cb) {
        var _this = this, readableDestroyed = this._readableState && this._readableState.destroyed, writableDestroyed = this._writableState && this._writableState.destroyed;
        return readableDestroyed || writableDestroyed ? (cb ? cb(err) : err && (this._writableState ? this._writableState.errorEmitted || (this._writableState.errorEmitted = !0, import_browser.default.nextTick(emitErrorNT, this, err)) : import_browser.default.nextTick(emitErrorNT, this, err)), this) : (this._readableState && (this._readableState.destroyed = !0), this._writableState && (this._writableState.destroyed = !0), this._destroy(err || null, function(err2) {
          !cb && err2 ? _this._writableState ? _this._writableState.errorEmitted ? import_browser.default.nextTick(emitCloseNT, _this) : (_this._writableState.errorEmitted = !0, import_browser.default.nextTick(emitErrorAndCloseNT, _this, err2)) : import_browser.default.nextTick(emitErrorAndCloseNT, _this, err2) : cb ? (import_browser.default.nextTick(emitCloseNT, _this), cb(err2)) : import_browser.default.nextTick(emitCloseNT, _this);
        }), this);
      }
      function emitErrorAndCloseNT(self2, err) {
        emitErrorNT(self2, err), emitCloseNT(self2);
      }
      function emitCloseNT(self2) {
        self2._writableState && !self2._writableState.emitClose || self2._readableState && !self2._readableState.emitClose || self2.emit("close");
      }
      function undestroy() {
        this._readableState && (this._readableState.destroyed = !1, this._readableState.reading = !1, this._readableState.ended = !1, this._readableState.endEmitted = !1), this._writableState && (this._writableState.destroyed = !1, this._writableState.ended = !1, this._writableState.ending = !1, this._writableState.finalCalled = !1, this._writableState.prefinished = !1, this._writableState.finished = !1, this._writableState.errorEmitted = !1);
      }
      function emitErrorNT(self2, err) {
        self2.emit("error", err);
      }
      function errorOrDestroy(stream, err) {
        var rState = stream._readableState, wState = stream._writableState;
        rState && rState.autoDestroy || wState && wState.autoDestroy ? stream.destroy(err) : stream.emit("error", err);
      }
      module.exports = {
        destroy,
        undestroy,
        errorOrDestroy
      };
    }
  });

  // node_modules/stream-browserify/node_modules/readable-stream/errors-browser.js
  var require_errors_browser = __commonJS({
    "node_modules/stream-browserify/node_modules/readable-stream/errors-browser.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      function _inheritsLoose(subClass, superClass) {
        subClass.prototype = Object.create(superClass.prototype), subClass.prototype.constructor = subClass, subClass.__proto__ = superClass;
      }
      var codes = {};
      function createErrorType(code, message, Base) {
        Base || (Base = Error);
        function getMessage(arg1, arg2, arg3) {
          return typeof message == "string" ? message : message(arg1, arg2, arg3);
        }
        var NodeError = /* @__PURE__ */ (function(_Base) {
          _inheritsLoose(NodeError2, _Base);
          function NodeError2(arg1, arg2, arg3) {
            return _Base.call(this, getMessage(arg1, arg2, arg3)) || this;
          }
          return NodeError2;
        })(Base);
        NodeError.prototype.name = Base.name, NodeError.prototype.code = code, codes[code] = NodeError;
      }
      function oneOf(expected, thing) {
        if (Array.isArray(expected)) {
          var len = expected.length;
          return expected = expected.map(function(i) {
            return String(i);
          }), len > 2 ? "one of ".concat(thing, " ").concat(expected.slice(0, len - 1).join(", "), ", or ") + expected[len - 1] : len === 2 ? "one of ".concat(thing, " ").concat(expected[0], " or ").concat(expected[1]) : "of ".concat(thing, " ").concat(expected[0]);
        } else
          return "of ".concat(thing, " ").concat(String(expected));
      }
      function startsWith(str, search, pos) {
        return str.substr(!pos || pos < 0 ? 0 : +pos, search.length) === search;
      }
      function endsWith(str, search, this_len) {
        return (this_len === void 0 || this_len > str.length) && (this_len = str.length), str.substring(this_len - search.length, this_len) === search;
      }
      function includes(str, search, start) {
        return typeof start != "number" && (start = 0), start + search.length > str.length ? !1 : str.indexOf(search, start) !== -1;
      }
      createErrorType("ERR_INVALID_OPT_VALUE", function(name, value) {
        return 'The value "' + value + '" is invalid for option "' + name + '"';
      }, TypeError);
      createErrorType("ERR_INVALID_ARG_TYPE", function(name, expected, actual) {
        var determiner;
        typeof expected == "string" && startsWith(expected, "not ") ? (determiner = "must not be", expected = expected.replace(/^not /, "")) : determiner = "must be";
        var msg;
        if (endsWith(name, " argument"))
          msg = "The ".concat(name, " ").concat(determiner, " ").concat(oneOf(expected, "type"));
        else {
          var type = includes(name, ".") ? "property" : "argument";
          msg = 'The "'.concat(name, '" ').concat(type, " ").concat(determiner, " ").concat(oneOf(expected, "type"));
        }
        return msg += ". Received type ".concat(typeof actual), msg;
      }, TypeError);
      createErrorType("ERR_STREAM_PUSH_AFTER_EOF", "stream.push() after EOF");
      createErrorType("ERR_METHOD_NOT_IMPLEMENTED", function(name) {
        return "The " + name + " method is not implemented";
      });
      createErrorType("ERR_STREAM_PREMATURE_CLOSE", "Premature close");
      createErrorType("ERR_STREAM_DESTROYED", function(name) {
        return "Cannot call " + name + " after a stream was destroyed";
      });
      createErrorType("ERR_MULTIPLE_CALLBACK", "Callback called multiple times");
      createErrorType("ERR_STREAM_CANNOT_PIPE", "Cannot pipe, not readable");
      createErrorType("ERR_STREAM_WRITE_AFTER_END", "write after end");
      createErrorType("ERR_STREAM_NULL_VALUES", "May not write null values to stream", TypeError);
      createErrorType("ERR_UNKNOWN_ENCODING", function(arg) {
        return "Unknown encoding: " + arg;
      }, TypeError);
      createErrorType("ERR_STREAM_UNSHIFT_AFTER_END_EVENT", "stream.unshift() after end event");
      module.exports.codes = codes;
    }
  });

  // node_modules/stream-browserify/node_modules/readable-stream/lib/internal/streams/state.js
  var require_state = __commonJS({
    "node_modules/stream-browserify/node_modules/readable-stream/lib/internal/streams/state.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      var ERR_INVALID_OPT_VALUE = require_errors_browser().codes.ERR_INVALID_OPT_VALUE;
      function highWaterMarkFrom(options, isDuplex, duplexKey) {
        return options.highWaterMark != null ? options.highWaterMark : isDuplex ? options[duplexKey] : null;
      }
      function getHighWaterMark(state, options, duplexKey, isDuplex) {
        var hwm = highWaterMarkFrom(options, isDuplex, duplexKey);
        if (hwm != null) {
          if (!(isFinite(hwm) && Math.floor(hwm) === hwm) || hwm < 0) {
            var name = isDuplex ? duplexKey : "highWaterMark";
            throw new ERR_INVALID_OPT_VALUE(name, hwm);
          }
          return Math.floor(hwm);
        }
        return state.objectMode ? 16 : 16 * 1024;
      }
      module.exports = {
        getHighWaterMark
      };
    }
  });

  // node_modules/stream-browserify/node_modules/readable-stream/lib/_stream_writable.js
  var require_stream_writable2 = __commonJS({
    "node_modules/stream-browserify/node_modules/readable-stream/lib/_stream_writable.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      module.exports = Writable;
      function CorkedRequest(state) {
        var _this = this;
        this.next = null, this.entry = null, this.finish = function() {
          onCorkedFinish(_this, state);
        };
      }
      var Duplex;
      Writable.WritableState = WritableState;
      var internalUtil = {
        deprecate: require_browser2()
      }, Stream = require_stream_browser2(), Buffer4 = require_buffer().Buffer, OurUint8Array = (typeof globalThis < "u" ? globalThis : typeof window < "u" ? window : typeof self < "u" ? self : {}).Uint8Array || function() {
      };
      function _uint8ArrayToBuffer(chunk) {
        return Buffer4.from(chunk);
      }
      function _isUint8Array(obj) {
        return Buffer4.isBuffer(obj) || obj instanceof OurUint8Array;
      }
      var destroyImpl = require_destroy2(), _require = require_state(), getHighWaterMark = _require.getHighWaterMark, _require$codes = require_errors_browser().codes, ERR_INVALID_ARG_TYPE = _require$codes.ERR_INVALID_ARG_TYPE, ERR_METHOD_NOT_IMPLEMENTED = _require$codes.ERR_METHOD_NOT_IMPLEMENTED, ERR_MULTIPLE_CALLBACK = _require$codes.ERR_MULTIPLE_CALLBACK, ERR_STREAM_CANNOT_PIPE = _require$codes.ERR_STREAM_CANNOT_PIPE, ERR_STREAM_DESTROYED = _require$codes.ERR_STREAM_DESTROYED, ERR_STREAM_NULL_VALUES = _require$codes.ERR_STREAM_NULL_VALUES, ERR_STREAM_WRITE_AFTER_END = _require$codes.ERR_STREAM_WRITE_AFTER_END, ERR_UNKNOWN_ENCODING = _require$codes.ERR_UNKNOWN_ENCODING, errorOrDestroy = destroyImpl.errorOrDestroy;
      require_inherits_browser()(Writable, Stream);
      function nop() {
      }
      function WritableState(options, stream, isDuplex) {
        Duplex = Duplex || require_stream_duplex2(), options = options || {}, typeof isDuplex != "boolean" && (isDuplex = stream instanceof Duplex), this.objectMode = !!options.objectMode, isDuplex && (this.objectMode = this.objectMode || !!options.writableObjectMode), this.highWaterMark = getHighWaterMark(this, options, "writableHighWaterMark", isDuplex), this.finalCalled = !1, this.needDrain = !1, this.ending = !1, this.ended = !1, this.finished = !1, this.destroyed = !1;
        var noDecode = options.decodeStrings === !1;
        this.decodeStrings = !noDecode, this.defaultEncoding = options.defaultEncoding || "utf8", this.length = 0, this.writing = !1, this.corked = 0, this.sync = !0, this.bufferProcessing = !1, this.onwrite = function(er) {
          onwrite(stream, er);
        }, this.writecb = null, this.writelen = 0, this.bufferedRequest = null, this.lastBufferedRequest = null, this.pendingcb = 0, this.prefinished = !1, this.errorEmitted = !1, this.emitClose = options.emitClose !== !1, this.autoDestroy = !!options.autoDestroy, this.bufferedRequestCount = 0, this.corkedRequestsFree = new CorkedRequest(this);
      }
      WritableState.prototype.getBuffer = function() {
        for (var current = this.bufferedRequest, out = []; current; )
          out.push(current), current = current.next;
        return out;
      };
      (function() {
        try {
          Object.defineProperty(WritableState.prototype, "buffer", {
            get: internalUtil.deprecate(function() {
              return this.getBuffer();
            }, "_writableState.buffer is deprecated. Use _writableState.getBuffer instead.", "DEP0003")
          });
        } catch {
        }
      })();
      var realHasInstance;
      typeof Symbol == "function" && Symbol.hasInstance && typeof Function.prototype[Symbol.hasInstance] == "function" ? (realHasInstance = Function.prototype[Symbol.hasInstance], Object.defineProperty(Writable, Symbol.hasInstance, {
        value: function(object) {
          return realHasInstance.call(this, object) ? !0 : this !== Writable ? !1 : object && object._writableState instanceof WritableState;
        }
      })) : realHasInstance = function(object) {
        return object instanceof this;
      };
      function Writable(options) {
        Duplex = Duplex || require_stream_duplex2();
        var isDuplex = this instanceof Duplex;
        if (!isDuplex && !realHasInstance.call(Writable, this)) return new Writable(options);
        this._writableState = new WritableState(options, this, isDuplex), this.writable = !0, options && (typeof options.write == "function" && (this._write = options.write), typeof options.writev == "function" && (this._writev = options.writev), typeof options.destroy == "function" && (this._destroy = options.destroy), typeof options.final == "function" && (this._final = options.final)), Stream.call(this);
      }
      Writable.prototype.pipe = function() {
        errorOrDestroy(this, new ERR_STREAM_CANNOT_PIPE());
      };
      function writeAfterEnd(stream, cb) {
        var er = new ERR_STREAM_WRITE_AFTER_END();
        errorOrDestroy(stream, er), import_browser.default.nextTick(cb, er);
      }
      function validChunk(stream, state, chunk, cb) {
        var er;
        return chunk === null ? er = new ERR_STREAM_NULL_VALUES() : typeof chunk != "string" && !state.objectMode && (er = new ERR_INVALID_ARG_TYPE("chunk", ["string", "Buffer"], chunk)), er ? (errorOrDestroy(stream, er), import_browser.default.nextTick(cb, er), !1) : !0;
      }
      Writable.prototype.write = function(chunk, encoding, cb) {
        var state = this._writableState, ret = !1, isBuf = !state.objectMode && _isUint8Array(chunk);
        return isBuf && !Buffer4.isBuffer(chunk) && (chunk = _uint8ArrayToBuffer(chunk)), typeof encoding == "function" && (cb = encoding, encoding = null), isBuf ? encoding = "buffer" : encoding || (encoding = state.defaultEncoding), typeof cb != "function" && (cb = nop), state.ending ? writeAfterEnd(this, cb) : (isBuf || validChunk(this, state, chunk, cb)) && (state.pendingcb++, ret = writeOrBuffer(this, state, isBuf, chunk, encoding, cb)), ret;
      };
      Writable.prototype.cork = function() {
        this._writableState.corked++;
      };
      Writable.prototype.uncork = function() {
        var state = this._writableState;
        state.corked && (state.corked--, !state.writing && !state.corked && !state.bufferProcessing && state.bufferedRequest && clearBuffer(this, state));
      };
      Writable.prototype.setDefaultEncoding = function(encoding) {
        if (typeof encoding == "string" && (encoding = encoding.toLowerCase()), !(["hex", "utf8", "utf-8", "ascii", "binary", "base64", "ucs2", "ucs-2", "utf16le", "utf-16le", "raw"].indexOf((encoding + "").toLowerCase()) > -1)) throw new ERR_UNKNOWN_ENCODING(encoding);
        return this._writableState.defaultEncoding = encoding, this;
      };
      Object.defineProperty(Writable.prototype, "writableBuffer", {
        // making it explicit this property is not enumerable
        // because otherwise some prototype manipulation in
        // userland will fail
        enumerable: !1,
        get: function() {
          return this._writableState && this._writableState.getBuffer();
        }
      });
      function decodeChunk(state, chunk, encoding) {
        return !state.objectMode && state.decodeStrings !== !1 && typeof chunk == "string" && (chunk = Buffer4.from(chunk, encoding)), chunk;
      }
      Object.defineProperty(Writable.prototype, "writableHighWaterMark", {
        // making it explicit this property is not enumerable
        // because otherwise some prototype manipulation in
        // userland will fail
        enumerable: !1,
        get: function() {
          return this._writableState.highWaterMark;
        }
      });
      function writeOrBuffer(stream, state, isBuf, chunk, encoding, cb) {
        if (!isBuf) {
          var newChunk = decodeChunk(state, chunk, encoding);
          chunk !== newChunk && (isBuf = !0, encoding = "buffer", chunk = newChunk);
        }
        var len = state.objectMode ? 1 : chunk.length;
        state.length += len;
        var ret = state.length < state.highWaterMark;
        if (ret || (state.needDrain = !0), state.writing || state.corked) {
          var last = state.lastBufferedRequest;
          state.lastBufferedRequest = {
            chunk,
            encoding,
            isBuf,
            callback: cb,
            next: null
          }, last ? last.next = state.lastBufferedRequest : state.bufferedRequest = state.lastBufferedRequest, state.bufferedRequestCount += 1;
        } else
          doWrite(stream, state, !1, len, chunk, encoding, cb);
        return ret;
      }
      function doWrite(stream, state, writev, len, chunk, encoding, cb) {
        state.writelen = len, state.writecb = cb, state.writing = !0, state.sync = !0, state.destroyed ? state.onwrite(new ERR_STREAM_DESTROYED("write")) : writev ? stream._writev(chunk, state.onwrite) : stream._write(chunk, encoding, state.onwrite), state.sync = !1;
      }
      function onwriteError(stream, state, sync, er, cb) {
        --state.pendingcb, sync ? (import_browser.default.nextTick(cb, er), import_browser.default.nextTick(finishMaybe, stream, state), stream._writableState.errorEmitted = !0, errorOrDestroy(stream, er)) : (cb(er), stream._writableState.errorEmitted = !0, errorOrDestroy(stream, er), finishMaybe(stream, state));
      }
      function onwriteStateUpdate(state) {
        state.writing = !1, state.writecb = null, state.length -= state.writelen, state.writelen = 0;
      }
      function onwrite(stream, er) {
        var state = stream._writableState, sync = state.sync, cb = state.writecb;
        if (typeof cb != "function") throw new ERR_MULTIPLE_CALLBACK();
        if (onwriteStateUpdate(state), er) onwriteError(stream, state, sync, er, cb);
        else {
          var finished = needFinish(state) || stream.destroyed;
          !finished && !state.corked && !state.bufferProcessing && state.bufferedRequest && clearBuffer(stream, state), sync ? import_browser.default.nextTick(afterWrite, stream, state, finished, cb) : afterWrite(stream, state, finished, cb);
        }
      }
      function afterWrite(stream, state, finished, cb) {
        finished || onwriteDrain(stream, state), state.pendingcb--, cb(), finishMaybe(stream, state);
      }
      function onwriteDrain(stream, state) {
        state.length === 0 && state.needDrain && (state.needDrain = !1, stream.emit("drain"));
      }
      function clearBuffer(stream, state) {
        state.bufferProcessing = !0;
        var entry = state.bufferedRequest;
        if (stream._writev && entry && entry.next) {
          var l = state.bufferedRequestCount, buffer = new Array(l), holder = state.corkedRequestsFree;
          holder.entry = entry;
          for (var count = 0, allBuffers = !0; entry; )
            buffer[count] = entry, entry.isBuf || (allBuffers = !1), entry = entry.next, count += 1;
          buffer.allBuffers = allBuffers, doWrite(stream, state, !0, state.length, buffer, "", holder.finish), state.pendingcb++, state.lastBufferedRequest = null, holder.next ? (state.corkedRequestsFree = holder.next, holder.next = null) : state.corkedRequestsFree = new CorkedRequest(state), state.bufferedRequestCount = 0;
        } else {
          for (; entry; ) {
            var chunk = entry.chunk, encoding = entry.encoding, cb = entry.callback, len = state.objectMode ? 1 : chunk.length;
            if (doWrite(stream, state, !1, len, chunk, encoding, cb), entry = entry.next, state.bufferedRequestCount--, state.writing)
              break;
          }
          entry === null && (state.lastBufferedRequest = null);
        }
        state.bufferedRequest = entry, state.bufferProcessing = !1;
      }
      Writable.prototype._write = function(chunk, encoding, cb) {
        cb(new ERR_METHOD_NOT_IMPLEMENTED("_write()"));
      };
      Writable.prototype._writev = null;
      Writable.prototype.end = function(chunk, encoding, cb) {
        var state = this._writableState;
        return typeof chunk == "function" ? (cb = chunk, chunk = null, encoding = null) : typeof encoding == "function" && (cb = encoding, encoding = null), chunk != null && this.write(chunk, encoding), state.corked && (state.corked = 1, this.uncork()), state.ending || endWritable(this, state, cb), this;
      };
      Object.defineProperty(Writable.prototype, "writableLength", {
        // making it explicit this property is not enumerable
        // because otherwise some prototype manipulation in
        // userland will fail
        enumerable: !1,
        get: function() {
          return this._writableState.length;
        }
      });
      function needFinish(state) {
        return state.ending && state.length === 0 && state.bufferedRequest === null && !state.finished && !state.writing;
      }
      function callFinal(stream, state) {
        stream._final(function(err) {
          state.pendingcb--, err && errorOrDestroy(stream, err), state.prefinished = !0, stream.emit("prefinish"), finishMaybe(stream, state);
        });
      }
      function prefinish(stream, state) {
        !state.prefinished && !state.finalCalled && (typeof stream._final == "function" && !state.destroyed ? (state.pendingcb++, state.finalCalled = !0, import_browser.default.nextTick(callFinal, stream, state)) : (state.prefinished = !0, stream.emit("prefinish")));
      }
      function finishMaybe(stream, state) {
        var need = needFinish(state);
        if (need && (prefinish(stream, state), state.pendingcb === 0 && (state.finished = !0, stream.emit("finish"), state.autoDestroy))) {
          var rState = stream._readableState;
          (!rState || rState.autoDestroy && rState.endEmitted) && stream.destroy();
        }
        return need;
      }
      function endWritable(stream, state, cb) {
        state.ending = !0, finishMaybe(stream, state), cb && (state.finished ? import_browser.default.nextTick(cb) : stream.once("finish", cb)), state.ended = !0, stream.writable = !1;
      }
      function onCorkedFinish(corkReq, state, err) {
        var entry = corkReq.entry;
        for (corkReq.entry = null; entry; ) {
          var cb = entry.callback;
          state.pendingcb--, cb(err), entry = entry.next;
        }
        state.corkedRequestsFree.next = corkReq;
      }
      Object.defineProperty(Writable.prototype, "destroyed", {
        // making it explicit this property is not enumerable
        // because otherwise some prototype manipulation in
        // userland will fail
        enumerable: !1,
        get: function() {
          return this._writableState === void 0 ? !1 : this._writableState.destroyed;
        },
        set: function(value) {
          this._writableState && (this._writableState.destroyed = value);
        }
      });
      Writable.prototype.destroy = destroyImpl.destroy;
      Writable.prototype._undestroy = destroyImpl.undestroy;
      Writable.prototype._destroy = function(err, cb) {
        cb(err);
      };
    }
  });

  // node_modules/stream-browserify/node_modules/readable-stream/lib/_stream_duplex.js
  var require_stream_duplex2 = __commonJS({
    "node_modules/stream-browserify/node_modules/readable-stream/lib/_stream_duplex.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      var objectKeys = Object.keys || function(obj) {
        var keys2 = [];
        for (var key in obj) keys2.push(key);
        return keys2;
      };
      module.exports = Duplex;
      var Readable = require_stream_readable2(), Writable = require_stream_writable2();
      require_inherits_browser()(Duplex, Readable);
      for (keys = objectKeys(Writable.prototype), v = 0; v < keys.length; v++)
        method = keys[v], Duplex.prototype[method] || (Duplex.prototype[method] = Writable.prototype[method]);
      var keys, method, v;
      function Duplex(options) {
        if (!(this instanceof Duplex)) return new Duplex(options);
        Readable.call(this, options), Writable.call(this, options), this.allowHalfOpen = !0, options && (options.readable === !1 && (this.readable = !1), options.writable === !1 && (this.writable = !1), options.allowHalfOpen === !1 && (this.allowHalfOpen = !1, this.once("end", onend)));
      }
      Object.defineProperty(Duplex.prototype, "writableHighWaterMark", {
        // making it explicit this property is not enumerable
        // because otherwise some prototype manipulation in
        // userland will fail
        enumerable: !1,
        get: function() {
          return this._writableState.highWaterMark;
        }
      });
      Object.defineProperty(Duplex.prototype, "writableBuffer", {
        // making it explicit this property is not enumerable
        // because otherwise some prototype manipulation in
        // userland will fail
        enumerable: !1,
        get: function() {
          return this._writableState && this._writableState.getBuffer();
        }
      });
      Object.defineProperty(Duplex.prototype, "writableLength", {
        // making it explicit this property is not enumerable
        // because otherwise some prototype manipulation in
        // userland will fail
        enumerable: !1,
        get: function() {
          return this._writableState.length;
        }
      });
      function onend() {
        this._writableState.ended || import_browser.default.nextTick(onEndNT, this);
      }
      function onEndNT(self2) {
        self2.end();
      }
      Object.defineProperty(Duplex.prototype, "destroyed", {
        // making it explicit this property is not enumerable
        // because otherwise some prototype manipulation in
        // userland will fail
        enumerable: !1,
        get: function() {
          return this._readableState === void 0 || this._writableState === void 0 ? !1 : this._readableState.destroyed && this._writableState.destroyed;
        },
        set: function(value) {
          this._readableState === void 0 || this._writableState === void 0 || (this._readableState.destroyed = value, this._writableState.destroyed = value);
        }
      });
    }
  });

  // node_modules/stream-browserify/node_modules/readable-stream/lib/internal/streams/end-of-stream.js
  var require_end_of_stream = __commonJS({
    "node_modules/stream-browserify/node_modules/readable-stream/lib/internal/streams/end-of-stream.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      var ERR_STREAM_PREMATURE_CLOSE = require_errors_browser().codes.ERR_STREAM_PREMATURE_CLOSE;
      function once(callback) {
        var called = !1;
        return function() {
          if (!called) {
            called = !0;
            for (var _len = arguments.length, args = new Array(_len), _key = 0; _key < _len; _key++)
              args[_key] = arguments[_key];
            callback.apply(this, args);
          }
        };
      }
      function noop() {
      }
      function isRequest(stream) {
        return stream.setHeader && typeof stream.abort == "function";
      }
      function eos(stream, opts, callback) {
        if (typeof opts == "function") return eos(stream, null, opts);
        opts || (opts = {}), callback = once(callback || noop);
        var readable = opts.readable || opts.readable !== !1 && stream.readable, writable = opts.writable || opts.writable !== !1 && stream.writable, onlegacyfinish = function() {
          stream.writable || onfinish();
        }, writableEnded = stream._writableState && stream._writableState.finished, onfinish = function() {
          writable = !1, writableEnded = !0, readable || callback.call(stream);
        }, readableEnded = stream._readableState && stream._readableState.endEmitted, onend = function() {
          readable = !1, readableEnded = !0, writable || callback.call(stream);
        }, onerror = function(err) {
          callback.call(stream, err);
        }, onclose = function() {
          var err;
          if (readable && !readableEnded)
            return (!stream._readableState || !stream._readableState.ended) && (err = new ERR_STREAM_PREMATURE_CLOSE()), callback.call(stream, err);
          if (writable && !writableEnded)
            return (!stream._writableState || !stream._writableState.ended) && (err = new ERR_STREAM_PREMATURE_CLOSE()), callback.call(stream, err);
        }, onrequest = function() {
          stream.req.on("finish", onfinish);
        };
        return isRequest(stream) ? (stream.on("complete", onfinish), stream.on("abort", onclose), stream.req ? onrequest() : stream.on("request", onrequest)) : writable && !stream._writableState && (stream.on("end", onlegacyfinish), stream.on("close", onlegacyfinish)), stream.on("end", onend), stream.on("finish", onfinish), opts.error !== !1 && stream.on("error", onerror), stream.on("close", onclose), function() {
          stream.removeListener("complete", onfinish), stream.removeListener("abort", onclose), stream.removeListener("request", onrequest), stream.req && stream.req.removeListener("finish", onfinish), stream.removeListener("end", onlegacyfinish), stream.removeListener("close", onlegacyfinish), stream.removeListener("finish", onfinish), stream.removeListener("end", onend), stream.removeListener("error", onerror), stream.removeListener("close", onclose);
        };
      }
      module.exports = eos;
    }
  });

  // node_modules/stream-browserify/node_modules/readable-stream/lib/internal/streams/async_iterator.js
  var require_async_iterator = __commonJS({
    "node_modules/stream-browserify/node_modules/readable-stream/lib/internal/streams/async_iterator.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      var _Object$setPrototypeO;
      function _defineProperty(obj, key, value) {
        return key = _toPropertyKey(key), key in obj ? Object.defineProperty(obj, key, { value, enumerable: !0, configurable: !0, writable: !0 }) : obj[key] = value, obj;
      }
      function _toPropertyKey(arg) {
        var key = _toPrimitive(arg, "string");
        return typeof key == "symbol" ? key : String(key);
      }
      function _toPrimitive(input, hint) {
        if (typeof input != "object" || input === null) return input;
        var prim = input[Symbol.toPrimitive];
        if (prim !== void 0) {
          var res = prim.call(input, hint || "default");
          if (typeof res != "object") return res;
          throw new TypeError("@@toPrimitive must return a primitive value.");
        }
        return (hint === "string" ? String : Number)(input);
      }
      var finished = require_end_of_stream(), kLastResolve = /* @__PURE__ */ Symbol("lastResolve"), kLastReject = /* @__PURE__ */ Symbol("lastReject"), kError = /* @__PURE__ */ Symbol("error"), kEnded = /* @__PURE__ */ Symbol("ended"), kLastPromise = /* @__PURE__ */ Symbol("lastPromise"), kHandlePromise = /* @__PURE__ */ Symbol("handlePromise"), kStream = /* @__PURE__ */ Symbol("stream");
      function createIterResult(value, done) {
        return {
          value,
          done
        };
      }
      function readAndResolve(iter) {
        var resolve = iter[kLastResolve];
        if (resolve !== null) {
          var data = iter[kStream].read();
          data !== null && (iter[kLastPromise] = null, iter[kLastResolve] = null, iter[kLastReject] = null, resolve(createIterResult(data, !1)));
        }
      }
      function onReadable(iter) {
        import_browser.default.nextTick(readAndResolve, iter);
      }
      function wrapForNext(lastPromise, iter) {
        return function(resolve, reject) {
          lastPromise.then(function() {
            if (iter[kEnded]) {
              resolve(createIterResult(void 0, !0));
              return;
            }
            iter[kHandlePromise](resolve, reject);
          }, reject);
        };
      }
      var AsyncIteratorPrototype = Object.getPrototypeOf(function() {
      }), ReadableStreamAsyncIteratorPrototype = Object.setPrototypeOf((_Object$setPrototypeO = {
        get stream() {
          return this[kStream];
        },
        next: function() {
          var _this = this, error = this[kError];
          if (error !== null)
            return Promise.reject(error);
          if (this[kEnded])
            return Promise.resolve(createIterResult(void 0, !0));
          if (this[kStream].destroyed)
            return new Promise(function(resolve, reject) {
              import_browser.default.nextTick(function() {
                _this[kError] ? reject(_this[kError]) : resolve(createIterResult(void 0, !0));
              });
            });
          var lastPromise = this[kLastPromise], promise;
          if (lastPromise)
            promise = new Promise(wrapForNext(lastPromise, this));
          else {
            var data = this[kStream].read();
            if (data !== null)
              return Promise.resolve(createIterResult(data, !1));
            promise = new Promise(this[kHandlePromise]);
          }
          return this[kLastPromise] = promise, promise;
        }
      }, _defineProperty(_Object$setPrototypeO, Symbol.asyncIterator, function() {
        return this;
      }), _defineProperty(_Object$setPrototypeO, "return", function() {
        var _this2 = this;
        return new Promise(function(resolve, reject) {
          _this2[kStream].destroy(null, function(err) {
            if (err) {
              reject(err);
              return;
            }
            resolve(createIterResult(void 0, !0));
          });
        });
      }), _Object$setPrototypeO), AsyncIteratorPrototype), createReadableStreamAsyncIterator = function(stream) {
        var _Object$create, iterator = Object.create(ReadableStreamAsyncIteratorPrototype, (_Object$create = {}, _defineProperty(_Object$create, kStream, {
          value: stream,
          writable: !0
        }), _defineProperty(_Object$create, kLastResolve, {
          value: null,
          writable: !0
        }), _defineProperty(_Object$create, kLastReject, {
          value: null,
          writable: !0
        }), _defineProperty(_Object$create, kError, {
          value: null,
          writable: !0
        }), _defineProperty(_Object$create, kEnded, {
          value: stream._readableState.endEmitted,
          writable: !0
        }), _defineProperty(_Object$create, kHandlePromise, {
          value: function(resolve, reject) {
            var data = iterator[kStream].read();
            data ? (iterator[kLastPromise] = null, iterator[kLastResolve] = null, iterator[kLastReject] = null, resolve(createIterResult(data, !1))) : (iterator[kLastResolve] = resolve, iterator[kLastReject] = reject);
          },
          writable: !0
        }), _Object$create));
        return iterator[kLastPromise] = null, finished(stream, function(err) {
          if (err && err.code !== "ERR_STREAM_PREMATURE_CLOSE") {
            var reject = iterator[kLastReject];
            reject !== null && (iterator[kLastPromise] = null, iterator[kLastResolve] = null, iterator[kLastReject] = null, reject(err)), iterator[kError] = err;
            return;
          }
          var resolve = iterator[kLastResolve];
          resolve !== null && (iterator[kLastPromise] = null, iterator[kLastResolve] = null, iterator[kLastReject] = null, resolve(createIterResult(void 0, !0))), iterator[kEnded] = !0;
        }), stream.on("readable", onReadable.bind(null, iterator)), iterator;
      };
      module.exports = createReadableStreamAsyncIterator;
    }
  });

  // node_modules/stream-browserify/node_modules/readable-stream/lib/internal/streams/from-browser.js
  var require_from_browser = __commonJS({
    "node_modules/stream-browserify/node_modules/readable-stream/lib/internal/streams/from-browser.js"(exports, module) {
      init_buffer_shim();
      init_process_shim();
      module.exports = function() {
        throw new Error("Readable.from is not available in the browser");
      };
    }
  });

  // node_modules/stream-browserify/node_modules/readable-stream/lib/_stream_readable.js
  var require_stream_readable2 = __commonJS({
    "node_modules/stream-browserify/node_modules/readable-stream/lib/_stream_readable.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      module.exports = Readable;
      var Duplex;
      Readable.ReadableState = ReadableState;
      var EE = require_events().EventEmitter, EElistenerCount = function(emitter, type) {
        return emitter.listeners(type).length;
      }, Stream = require_stream_browser2(), Buffer4 = require_buffer().Buffer, OurUint8Array = (typeof globalThis < "u" ? globalThis : typeof window < "u" ? window : typeof self < "u" ? self : {}).Uint8Array || function() {
      };
      function _uint8ArrayToBuffer(chunk) {
        return Buffer4.from(chunk);
      }
      function _isUint8Array(obj) {
        return Buffer4.isBuffer(obj) || obj instanceof OurUint8Array;
      }
      var debugUtil = require_util2(), debug;
      debugUtil && debugUtil.debuglog ? debug = debugUtil.debuglog("stream") : debug = function() {
      };
      var BufferList = require_buffer_list(), destroyImpl = require_destroy2(), _require = require_state(), getHighWaterMark = _require.getHighWaterMark, _require$codes = require_errors_browser().codes, ERR_INVALID_ARG_TYPE = _require$codes.ERR_INVALID_ARG_TYPE, ERR_STREAM_PUSH_AFTER_EOF = _require$codes.ERR_STREAM_PUSH_AFTER_EOF, ERR_METHOD_NOT_IMPLEMENTED = _require$codes.ERR_METHOD_NOT_IMPLEMENTED, ERR_STREAM_UNSHIFT_AFTER_END_EVENT = _require$codes.ERR_STREAM_UNSHIFT_AFTER_END_EVENT, StringDecoder, createReadableStreamAsyncIterator, from;
      require_inherits_browser()(Readable, Stream);
      var errorOrDestroy = destroyImpl.errorOrDestroy, kProxyEvents = ["error", "close", "destroy", "pause", "resume"];
      function prependListener(emitter, event, fn) {
        if (typeof emitter.prependListener == "function") return emitter.prependListener(event, fn);
        !emitter._events || !emitter._events[event] ? emitter.on(event, fn) : Array.isArray(emitter._events[event]) ? emitter._events[event].unshift(fn) : emitter._events[event] = [fn, emitter._events[event]];
      }
      function ReadableState(options, stream, isDuplex) {
        Duplex = Duplex || require_stream_duplex2(), options = options || {}, typeof isDuplex != "boolean" && (isDuplex = stream instanceof Duplex), this.objectMode = !!options.objectMode, isDuplex && (this.objectMode = this.objectMode || !!options.readableObjectMode), this.highWaterMark = getHighWaterMark(this, options, "readableHighWaterMark", isDuplex), this.buffer = new BufferList(), this.length = 0, this.pipes = null, this.pipesCount = 0, this.flowing = null, this.ended = !1, this.endEmitted = !1, this.reading = !1, this.sync = !0, this.needReadable = !1, this.emittedReadable = !1, this.readableListening = !1, this.resumeScheduled = !1, this.paused = !0, this.emitClose = options.emitClose !== !1, this.autoDestroy = !!options.autoDestroy, this.destroyed = !1, this.defaultEncoding = options.defaultEncoding || "utf8", this.awaitDrain = 0, this.readingMore = !1, this.decoder = null, this.encoding = null, options.encoding && (StringDecoder || (StringDecoder = require_string_decoder().StringDecoder), this.decoder = new StringDecoder(options.encoding), this.encoding = options.encoding);
      }
      function Readable(options) {
        if (Duplex = Duplex || require_stream_duplex2(), !(this instanceof Readable)) return new Readable(options);
        var isDuplex = this instanceof Duplex;
        this._readableState = new ReadableState(options, this, isDuplex), this.readable = !0, options && (typeof options.read == "function" && (this._read = options.read), typeof options.destroy == "function" && (this._destroy = options.destroy)), Stream.call(this);
      }
      Object.defineProperty(Readable.prototype, "destroyed", {
        // making it explicit this property is not enumerable
        // because otherwise some prototype manipulation in
        // userland will fail
        enumerable: !1,
        get: function() {
          return this._readableState === void 0 ? !1 : this._readableState.destroyed;
        },
        set: function(value) {
          this._readableState && (this._readableState.destroyed = value);
        }
      });
      Readable.prototype.destroy = destroyImpl.destroy;
      Readable.prototype._undestroy = destroyImpl.undestroy;
      Readable.prototype._destroy = function(err, cb) {
        cb(err);
      };
      Readable.prototype.push = function(chunk, encoding) {
        var state = this._readableState, skipChunkCheck;
        return state.objectMode ? skipChunkCheck = !0 : typeof chunk == "string" && (encoding = encoding || state.defaultEncoding, encoding !== state.encoding && (chunk = Buffer4.from(chunk, encoding), encoding = ""), skipChunkCheck = !0), readableAddChunk(this, chunk, encoding, !1, skipChunkCheck);
      };
      Readable.prototype.unshift = function(chunk) {
        return readableAddChunk(this, chunk, null, !0, !1);
      };
      function readableAddChunk(stream, chunk, encoding, addToFront, skipChunkCheck) {
        debug("readableAddChunk", chunk);
        var state = stream._readableState;
        if (chunk === null)
          state.reading = !1, onEofChunk(stream, state);
        else {
          var er;
          if (skipChunkCheck || (er = chunkInvalid(state, chunk)), er)
            errorOrDestroy(stream, er);
          else if (state.objectMode || chunk && chunk.length > 0)
            if (typeof chunk != "string" && !state.objectMode && Object.getPrototypeOf(chunk) !== Buffer4.prototype && (chunk = _uint8ArrayToBuffer(chunk)), addToFront)
              state.endEmitted ? errorOrDestroy(stream, new ERR_STREAM_UNSHIFT_AFTER_END_EVENT()) : addChunk(stream, state, chunk, !0);
            else if (state.ended)
              errorOrDestroy(stream, new ERR_STREAM_PUSH_AFTER_EOF());
            else {
              if (state.destroyed)
                return !1;
              state.reading = !1, state.decoder && !encoding ? (chunk = state.decoder.write(chunk), state.objectMode || chunk.length !== 0 ? addChunk(stream, state, chunk, !1) : maybeReadMore(stream, state)) : addChunk(stream, state, chunk, !1);
            }
          else addToFront || (state.reading = !1, maybeReadMore(stream, state));
        }
        return !state.ended && (state.length < state.highWaterMark || state.length === 0);
      }
      function addChunk(stream, state, chunk, addToFront) {
        state.flowing && state.length === 0 && !state.sync ? (state.awaitDrain = 0, stream.emit("data", chunk)) : (state.length += state.objectMode ? 1 : chunk.length, addToFront ? state.buffer.unshift(chunk) : state.buffer.push(chunk), state.needReadable && emitReadable(stream)), maybeReadMore(stream, state);
      }
      function chunkInvalid(state, chunk) {
        var er;
        return !_isUint8Array(chunk) && typeof chunk != "string" && chunk !== void 0 && !state.objectMode && (er = new ERR_INVALID_ARG_TYPE("chunk", ["string", "Buffer", "Uint8Array"], chunk)), er;
      }
      Readable.prototype.isPaused = function() {
        return this._readableState.flowing === !1;
      };
      Readable.prototype.setEncoding = function(enc) {
        StringDecoder || (StringDecoder = require_string_decoder().StringDecoder);
        var decoder = new StringDecoder(enc);
        this._readableState.decoder = decoder, this._readableState.encoding = this._readableState.decoder.encoding;
        for (var p = this._readableState.buffer.head, content = ""; p !== null; )
          content += decoder.write(p.data), p = p.next;
        return this._readableState.buffer.clear(), content !== "" && this._readableState.buffer.push(content), this._readableState.length = content.length, this;
      };
      var MAX_HWM = 1073741824;
      function computeNewHighWaterMark(n) {
        return n >= MAX_HWM ? n = MAX_HWM : (n--, n |= n >>> 1, n |= n >>> 2, n |= n >>> 4, n |= n >>> 8, n |= n >>> 16, n++), n;
      }
      function howMuchToRead(n, state) {
        return n <= 0 || state.length === 0 && state.ended ? 0 : state.objectMode ? 1 : n !== n ? state.flowing && state.length ? state.buffer.head.data.length : state.length : (n > state.highWaterMark && (state.highWaterMark = computeNewHighWaterMark(n)), n <= state.length ? n : state.ended ? state.length : (state.needReadable = !0, 0));
      }
      Readable.prototype.read = function(n) {
        debug("read", n), n = parseInt(n, 10);
        var state = this._readableState, nOrig = n;
        if (n !== 0 && (state.emittedReadable = !1), n === 0 && state.needReadable && ((state.highWaterMark !== 0 ? state.length >= state.highWaterMark : state.length > 0) || state.ended))
          return debug("read: emitReadable", state.length, state.ended), state.length === 0 && state.ended ? endReadable(this) : emitReadable(this), null;
        if (n = howMuchToRead(n, state), n === 0 && state.ended)
          return state.length === 0 && endReadable(this), null;
        var doRead = state.needReadable;
        debug("need readable", doRead), (state.length === 0 || state.length - n < state.highWaterMark) && (doRead = !0, debug("length less than watermark", doRead)), state.ended || state.reading ? (doRead = !1, debug("reading or ended", doRead)) : doRead && (debug("do read"), state.reading = !0, state.sync = !0, state.length === 0 && (state.needReadable = !0), this._read(state.highWaterMark), state.sync = !1, state.reading || (n = howMuchToRead(nOrig, state)));
        var ret;
        return n > 0 ? ret = fromList(n, state) : ret = null, ret === null ? (state.needReadable = state.length <= state.highWaterMark, n = 0) : (state.length -= n, state.awaitDrain = 0), state.length === 0 && (state.ended || (state.needReadable = !0), nOrig !== n && state.ended && endReadable(this)), ret !== null && this.emit("data", ret), ret;
      };
      function onEofChunk(stream, state) {
        if (debug("onEofChunk"), !state.ended) {
          if (state.decoder) {
            var chunk = state.decoder.end();
            chunk && chunk.length && (state.buffer.push(chunk), state.length += state.objectMode ? 1 : chunk.length);
          }
          state.ended = !0, state.sync ? emitReadable(stream) : (state.needReadable = !1, state.emittedReadable || (state.emittedReadable = !0, emitReadable_(stream)));
        }
      }
      function emitReadable(stream) {
        var state = stream._readableState;
        debug("emitReadable", state.needReadable, state.emittedReadable), state.needReadable = !1, state.emittedReadable || (debug("emitReadable", state.flowing), state.emittedReadable = !0, import_browser.default.nextTick(emitReadable_, stream));
      }
      function emitReadable_(stream) {
        var state = stream._readableState;
        debug("emitReadable_", state.destroyed, state.length, state.ended), !state.destroyed && (state.length || state.ended) && (stream.emit("readable"), state.emittedReadable = !1), state.needReadable = !state.flowing && !state.ended && state.length <= state.highWaterMark, flow(stream);
      }
      function maybeReadMore(stream, state) {
        state.readingMore || (state.readingMore = !0, import_browser.default.nextTick(maybeReadMore_, stream, state));
      }
      function maybeReadMore_(stream, state) {
        for (; !state.reading && !state.ended && (state.length < state.highWaterMark || state.flowing && state.length === 0); ) {
          var len = state.length;
          if (debug("maybeReadMore read 0"), stream.read(0), len === state.length)
            break;
        }
        state.readingMore = !1;
      }
      Readable.prototype._read = function(n) {
        errorOrDestroy(this, new ERR_METHOD_NOT_IMPLEMENTED("_read()"));
      };
      Readable.prototype.pipe = function(dest, pipeOpts) {
        var src = this, state = this._readableState;
        switch (state.pipesCount) {
          case 0:
            state.pipes = dest;
            break;
          case 1:
            state.pipes = [state.pipes, dest];
            break;
          default:
            state.pipes.push(dest);
            break;
        }
        state.pipesCount += 1, debug("pipe count=%d opts=%j", state.pipesCount, pipeOpts);
        var doEnd = (!pipeOpts || pipeOpts.end !== !1) && dest !== import_browser.default.stdout && dest !== import_browser.default.stderr, endFn = doEnd ? onend : unpipe;
        state.endEmitted ? import_browser.default.nextTick(endFn) : src.once("end", endFn), dest.on("unpipe", onunpipe);
        function onunpipe(readable, unpipeInfo) {
          debug("onunpipe"), readable === src && unpipeInfo && unpipeInfo.hasUnpiped === !1 && (unpipeInfo.hasUnpiped = !0, cleanup());
        }
        function onend() {
          debug("onend"), dest.end();
        }
        var ondrain = pipeOnDrain(src);
        dest.on("drain", ondrain);
        var cleanedUp = !1;
        function cleanup() {
          debug("cleanup"), dest.removeListener("close", onclose), dest.removeListener("finish", onfinish), dest.removeListener("drain", ondrain), dest.removeListener("error", onerror), dest.removeListener("unpipe", onunpipe), src.removeListener("end", onend), src.removeListener("end", unpipe), src.removeListener("data", ondata), cleanedUp = !0, state.awaitDrain && (!dest._writableState || dest._writableState.needDrain) && ondrain();
        }
        src.on("data", ondata);
        function ondata(chunk) {
          debug("ondata");
          var ret = dest.write(chunk);
          debug("dest.write", ret), ret === !1 && ((state.pipesCount === 1 && state.pipes === dest || state.pipesCount > 1 && indexOf(state.pipes, dest) !== -1) && !cleanedUp && (debug("false write response, pause", state.awaitDrain), state.awaitDrain++), src.pause());
        }
        function onerror(er) {
          debug("onerror", er), unpipe(), dest.removeListener("error", onerror), EElistenerCount(dest, "error") === 0 && errorOrDestroy(dest, er);
        }
        prependListener(dest, "error", onerror);
        function onclose() {
          dest.removeListener("finish", onfinish), unpipe();
        }
        dest.once("close", onclose);
        function onfinish() {
          debug("onfinish"), dest.removeListener("close", onclose), unpipe();
        }
        dest.once("finish", onfinish);
        function unpipe() {
          debug("unpipe"), src.unpipe(dest);
        }
        return dest.emit("pipe", src), state.flowing || (debug("pipe resume"), src.resume()), dest;
      };
      function pipeOnDrain(src) {
        return function() {
          var state = src._readableState;
          debug("pipeOnDrain", state.awaitDrain), state.awaitDrain && state.awaitDrain--, state.awaitDrain === 0 && EElistenerCount(src, "data") && (state.flowing = !0, flow(src));
        };
      }
      Readable.prototype.unpipe = function(dest) {
        var state = this._readableState, unpipeInfo = {
          hasUnpiped: !1
        };
        if (state.pipesCount === 0) return this;
        if (state.pipesCount === 1)
          return dest && dest !== state.pipes ? this : (dest || (dest = state.pipes), state.pipes = null, state.pipesCount = 0, state.flowing = !1, dest && dest.emit("unpipe", this, unpipeInfo), this);
        if (!dest) {
          var dests = state.pipes, len = state.pipesCount;
          state.pipes = null, state.pipesCount = 0, state.flowing = !1;
          for (var i = 0; i < len; i++) dests[i].emit("unpipe", this, {
            hasUnpiped: !1
          });
          return this;
        }
        var index = indexOf(state.pipes, dest);
        return index === -1 ? this : (state.pipes.splice(index, 1), state.pipesCount -= 1, state.pipesCount === 1 && (state.pipes = state.pipes[0]), dest.emit("unpipe", this, unpipeInfo), this);
      };
      Readable.prototype.on = function(ev, fn) {
        var res = Stream.prototype.on.call(this, ev, fn), state = this._readableState;
        return ev === "data" ? (state.readableListening = this.listenerCount("readable") > 0, state.flowing !== !1 && this.resume()) : ev === "readable" && !state.endEmitted && !state.readableListening && (state.readableListening = state.needReadable = !0, state.flowing = !1, state.emittedReadable = !1, debug("on readable", state.length, state.reading), state.length ? emitReadable(this) : state.reading || import_browser.default.nextTick(nReadingNextTick, this)), res;
      };
      Readable.prototype.addListener = Readable.prototype.on;
      Readable.prototype.removeListener = function(ev, fn) {
        var res = Stream.prototype.removeListener.call(this, ev, fn);
        return ev === "readable" && import_browser.default.nextTick(updateReadableListening, this), res;
      };
      Readable.prototype.removeAllListeners = function(ev) {
        var res = Stream.prototype.removeAllListeners.apply(this, arguments);
        return (ev === "readable" || ev === void 0) && import_browser.default.nextTick(updateReadableListening, this), res;
      };
      function updateReadableListening(self2) {
        var state = self2._readableState;
        state.readableListening = self2.listenerCount("readable") > 0, state.resumeScheduled && !state.paused ? state.flowing = !0 : self2.listenerCount("data") > 0 && self2.resume();
      }
      function nReadingNextTick(self2) {
        debug("readable nexttick read 0"), self2.read(0);
      }
      Readable.prototype.resume = function() {
        var state = this._readableState;
        return state.flowing || (debug("resume"), state.flowing = !state.readableListening, resume(this, state)), state.paused = !1, this;
      };
      function resume(stream, state) {
        state.resumeScheduled || (state.resumeScheduled = !0, import_browser.default.nextTick(resume_, stream, state));
      }
      function resume_(stream, state) {
        debug("resume", state.reading), state.reading || stream.read(0), state.resumeScheduled = !1, stream.emit("resume"), flow(stream), state.flowing && !state.reading && stream.read(0);
      }
      Readable.prototype.pause = function() {
        return debug("call pause flowing=%j", this._readableState.flowing), this._readableState.flowing !== !1 && (debug("pause"), this._readableState.flowing = !1, this.emit("pause")), this._readableState.paused = !0, this;
      };
      function flow(stream) {
        var state = stream._readableState;
        for (debug("flow", state.flowing); state.flowing && stream.read() !== null; ) ;
      }
      Readable.prototype.wrap = function(stream) {
        var _this = this, state = this._readableState, paused = !1;
        stream.on("end", function() {
          if (debug("wrapped end"), state.decoder && !state.ended) {
            var chunk = state.decoder.end();
            chunk && chunk.length && _this.push(chunk);
          }
          _this.push(null);
        }), stream.on("data", function(chunk) {
          if (debug("wrapped data"), state.decoder && (chunk = state.decoder.write(chunk)), !(state.objectMode && chunk == null) && !(!state.objectMode && (!chunk || !chunk.length))) {
            var ret = _this.push(chunk);
            ret || (paused = !0, stream.pause());
          }
        });
        for (var i in stream)
          this[i] === void 0 && typeof stream[i] == "function" && (this[i] = /* @__PURE__ */ (function(method) {
            return function() {
              return stream[method].apply(stream, arguments);
            };
          })(i));
        for (var n = 0; n < kProxyEvents.length; n++)
          stream.on(kProxyEvents[n], this.emit.bind(this, kProxyEvents[n]));
        return this._read = function(n2) {
          debug("wrapped _read", n2), paused && (paused = !1, stream.resume());
        }, this;
      };
      typeof Symbol == "function" && (Readable.prototype[Symbol.asyncIterator] = function() {
        return createReadableStreamAsyncIterator === void 0 && (createReadableStreamAsyncIterator = require_async_iterator()), createReadableStreamAsyncIterator(this);
      });
      Object.defineProperty(Readable.prototype, "readableHighWaterMark", {
        // making it explicit this property is not enumerable
        // because otherwise some prototype manipulation in
        // userland will fail
        enumerable: !1,
        get: function() {
          return this._readableState.highWaterMark;
        }
      });
      Object.defineProperty(Readable.prototype, "readableBuffer", {
        // making it explicit this property is not enumerable
        // because otherwise some prototype manipulation in
        // userland will fail
        enumerable: !1,
        get: function() {
          return this._readableState && this._readableState.buffer;
        }
      });
      Object.defineProperty(Readable.prototype, "readableFlowing", {
        // making it explicit this property is not enumerable
        // because otherwise some prototype manipulation in
        // userland will fail
        enumerable: !1,
        get: function() {
          return this._readableState.flowing;
        },
        set: function(state) {
          this._readableState && (this._readableState.flowing = state);
        }
      });
      Readable._fromList = fromList;
      Object.defineProperty(Readable.prototype, "readableLength", {
        // making it explicit this property is not enumerable
        // because otherwise some prototype manipulation in
        // userland will fail
        enumerable: !1,
        get: function() {
          return this._readableState.length;
        }
      });
      function fromList(n, state) {
        if (state.length === 0) return null;
        var ret;
        return state.objectMode ? ret = state.buffer.shift() : !n || n >= state.length ? (state.decoder ? ret = state.buffer.join("") : state.buffer.length === 1 ? ret = state.buffer.first() : ret = state.buffer.concat(state.length), state.buffer.clear()) : ret = state.buffer.consume(n, state.decoder), ret;
      }
      function endReadable(stream) {
        var state = stream._readableState;
        debug("endReadable", state.endEmitted), state.endEmitted || (state.ended = !0, import_browser.default.nextTick(endReadableNT, state, stream));
      }
      function endReadableNT(state, stream) {
        if (debug("endReadableNT", state.endEmitted, state.length), !state.endEmitted && state.length === 0 && (state.endEmitted = !0, stream.readable = !1, stream.emit("end"), state.autoDestroy)) {
          var wState = stream._writableState;
          (!wState || wState.autoDestroy && wState.finished) && stream.destroy();
        }
      }
      typeof Symbol == "function" && (Readable.from = function(iterable, opts) {
        return from === void 0 && (from = require_from_browser()), from(Readable, iterable, opts);
      });
      function indexOf(xs, x) {
        for (var i = 0, l = xs.length; i < l; i++)
          if (xs[i] === x) return i;
        return -1;
      }
    }
  });

  // node_modules/stream-browserify/node_modules/readable-stream/lib/_stream_transform.js
  var require_stream_transform2 = __commonJS({
    "node_modules/stream-browserify/node_modules/readable-stream/lib/_stream_transform.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      module.exports = Transform;
      var _require$codes = require_errors_browser().codes, ERR_METHOD_NOT_IMPLEMENTED = _require$codes.ERR_METHOD_NOT_IMPLEMENTED, ERR_MULTIPLE_CALLBACK = _require$codes.ERR_MULTIPLE_CALLBACK, ERR_TRANSFORM_ALREADY_TRANSFORMING = _require$codes.ERR_TRANSFORM_ALREADY_TRANSFORMING, ERR_TRANSFORM_WITH_LENGTH_0 = _require$codes.ERR_TRANSFORM_WITH_LENGTH_0, Duplex = require_stream_duplex2();
      require_inherits_browser()(Transform, Duplex);
      function afterTransform(er, data) {
        var ts = this._transformState;
        ts.transforming = !1;
        var cb = ts.writecb;
        if (cb === null)
          return this.emit("error", new ERR_MULTIPLE_CALLBACK());
        ts.writechunk = null, ts.writecb = null, data != null && this.push(data), cb(er);
        var rs = this._readableState;
        rs.reading = !1, (rs.needReadable || rs.length < rs.highWaterMark) && this._read(rs.highWaterMark);
      }
      function Transform(options) {
        if (!(this instanceof Transform)) return new Transform(options);
        Duplex.call(this, options), this._transformState = {
          afterTransform: afterTransform.bind(this),
          needTransform: !1,
          transforming: !1,
          writecb: null,
          writechunk: null,
          writeencoding: null
        }, this._readableState.needReadable = !0, this._readableState.sync = !1, options && (typeof options.transform == "function" && (this._transform = options.transform), typeof options.flush == "function" && (this._flush = options.flush)), this.on("prefinish", prefinish);
      }
      function prefinish() {
        var _this = this;
        typeof this._flush == "function" && !this._readableState.destroyed ? this._flush(function(er, data) {
          done(_this, er, data);
        }) : done(this, null, null);
      }
      Transform.prototype.push = function(chunk, encoding) {
        return this._transformState.needTransform = !1, Duplex.prototype.push.call(this, chunk, encoding);
      };
      Transform.prototype._transform = function(chunk, encoding, cb) {
        cb(new ERR_METHOD_NOT_IMPLEMENTED("_transform()"));
      };
      Transform.prototype._write = function(chunk, encoding, cb) {
        var ts = this._transformState;
        if (ts.writecb = cb, ts.writechunk = chunk, ts.writeencoding = encoding, !ts.transforming) {
          var rs = this._readableState;
          (ts.needTransform || rs.needReadable || rs.length < rs.highWaterMark) && this._read(rs.highWaterMark);
        }
      };
      Transform.prototype._read = function(n) {
        var ts = this._transformState;
        ts.writechunk !== null && !ts.transforming ? (ts.transforming = !0, this._transform(ts.writechunk, ts.writeencoding, ts.afterTransform)) : ts.needTransform = !0;
      };
      Transform.prototype._destroy = function(err, cb) {
        Duplex.prototype._destroy.call(this, err, function(err2) {
          cb(err2);
        });
      };
      function done(stream, er, data) {
        if (er) return stream.emit("error", er);
        if (data != null && stream.push(data), stream._writableState.length) throw new ERR_TRANSFORM_WITH_LENGTH_0();
        if (stream._transformState.transforming) throw new ERR_TRANSFORM_ALREADY_TRANSFORMING();
        return stream.push(null);
      }
    }
  });

  // node_modules/stream-browserify/node_modules/readable-stream/lib/_stream_passthrough.js
  var require_stream_passthrough2 = __commonJS({
    "node_modules/stream-browserify/node_modules/readable-stream/lib/_stream_passthrough.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      module.exports = PassThrough;
      var Transform = require_stream_transform2();
      require_inherits_browser()(PassThrough, Transform);
      function PassThrough(options) {
        if (!(this instanceof PassThrough)) return new PassThrough(options);
        Transform.call(this, options);
      }
      PassThrough.prototype._transform = function(chunk, encoding, cb) {
        cb(null, chunk);
      };
    }
  });

  // node_modules/stream-browserify/node_modules/readable-stream/lib/internal/streams/pipeline.js
  var require_pipeline = __commonJS({
    "node_modules/stream-browserify/node_modules/readable-stream/lib/internal/streams/pipeline.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      var eos;
      function once(callback) {
        var called = !1;
        return function() {
          called || (called = !0, callback.apply(void 0, arguments));
        };
      }
      var _require$codes = require_errors_browser().codes, ERR_MISSING_ARGS = _require$codes.ERR_MISSING_ARGS, ERR_STREAM_DESTROYED = _require$codes.ERR_STREAM_DESTROYED;
      function noop(err) {
        if (err) throw err;
      }
      function isRequest(stream) {
        return stream.setHeader && typeof stream.abort == "function";
      }
      function destroyer(stream, reading, writing, callback) {
        callback = once(callback);
        var closed = !1;
        stream.on("close", function() {
          closed = !0;
        }), eos === void 0 && (eos = require_end_of_stream()), eos(stream, {
          readable: reading,
          writable: writing
        }, function(err) {
          if (err) return callback(err);
          closed = !0, callback();
        });
        var destroyed = !1;
        return function(err) {
          if (!closed && !destroyed) {
            if (destroyed = !0, isRequest(stream)) return stream.abort();
            if (typeof stream.destroy == "function") return stream.destroy();
            callback(err || new ERR_STREAM_DESTROYED("pipe"));
          }
        };
      }
      function call(fn) {
        fn();
      }
      function pipe(from, to) {
        return from.pipe(to);
      }
      function popCallback(streams) {
        return !streams.length || typeof streams[streams.length - 1] != "function" ? noop : streams.pop();
      }
      function pipeline() {
        for (var _len = arguments.length, streams = new Array(_len), _key = 0; _key < _len; _key++)
          streams[_key] = arguments[_key];
        var callback = popCallback(streams);
        if (Array.isArray(streams[0]) && (streams = streams[0]), streams.length < 2)
          throw new ERR_MISSING_ARGS("streams");
        var error, destroys = streams.map(function(stream, i) {
          var reading = i < streams.length - 1, writing = i > 0;
          return destroyer(stream, reading, writing, function(err) {
            error || (error = err), err && destroys.forEach(call), !reading && (destroys.forEach(call), callback(error));
          });
        });
        return streams.reduce(pipe);
      }
      module.exports = pipeline;
    }
  });

  // node_modules/stream-browserify/index.js
  var require_stream_browserify = __commonJS({
    "node_modules/stream-browserify/index.js"(exports, module) {
      init_buffer_shim();
      init_process_shim();
      module.exports = Stream;
      var EE = require_events().EventEmitter, inherits = require_inherits_browser();
      inherits(Stream, EE);
      Stream.Readable = require_stream_readable2();
      Stream.Writable = require_stream_writable2();
      Stream.Duplex = require_stream_duplex2();
      Stream.Transform = require_stream_transform2();
      Stream.PassThrough = require_stream_passthrough2();
      Stream.finished = require_end_of_stream();
      Stream.pipeline = require_pipeline();
      Stream.Stream = Stream;
      function Stream() {
        EE.call(this);
      }
      Stream.prototype.pipe = function(dest, options) {
        var source = this;
        function ondata(chunk) {
          dest.writable && dest.write(chunk) === !1 && source.pause && source.pause();
        }
        source.on("data", ondata);
        function ondrain() {
          source.readable && source.resume && source.resume();
        }
        dest.on("drain", ondrain), !dest._isStdio && (!options || options.end !== !1) && (source.on("end", onend), source.on("close", onclose));
        var didOnEnd = !1;
        function onend() {
          didOnEnd || (didOnEnd = !0, dest.end());
        }
        function onclose() {
          didOnEnd || (didOnEnd = !0, typeof dest.destroy == "function" && dest.destroy());
        }
        function onerror(er) {
          if (cleanup(), EE.listenerCount(this, "error") === 0)
            throw er;
        }
        source.on("error", onerror), dest.on("error", onerror);
        function cleanup() {
          source.removeListener("data", ondata), dest.removeListener("drain", ondrain), source.removeListener("end", onend), source.removeListener("close", onclose), source.removeListener("error", onerror), dest.removeListener("error", onerror), source.removeListener("end", cleanup), source.removeListener("close", cleanup), dest.removeListener("close", cleanup);
        }
        return source.on("end", cleanup), source.on("close", cleanup), dest.on("close", cleanup), dest.emit("pipe", source), dest;
      };
    }
  });

  // node_modules/cipher-base/index.js
  var require_cipher_base = __commonJS({
    "node_modules/cipher-base/index.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      var Buffer4 = require_safe_buffer().Buffer, Transform = require_stream_browserify().Transform, StringDecoder = require_string_decoder().StringDecoder, inherits = require_inherits_browser(), toBuffer = require_to_buffer();
      function CipherBase(hashMode) {
        Transform.call(this), this.hashMode = typeof hashMode == "string", this.hashMode ? this[hashMode] = this._finalOrDigest : this.final = this._finalOrDigest, this._final && (this.__final = this._final, this._final = null), this._decoder = null, this._encoding = null;
      }
      inherits(CipherBase, Transform);
      CipherBase.prototype.update = function(data, inputEnc, outputEnc) {
        var bufferData = toBuffer(data, inputEnc), outData = this._update(bufferData);
        return this.hashMode ? this : (outputEnc && (outData = this._toString(outData, outputEnc)), outData);
      };
      CipherBase.prototype.setAutoPadding = function() {
      };
      CipherBase.prototype.getAuthTag = function() {
        throw new Error("trying to get auth tag in unsupported state");
      };
      CipherBase.prototype.setAuthTag = function() {
        throw new Error("trying to set auth tag in unsupported state");
      };
      CipherBase.prototype.setAAD = function() {
        throw new Error("trying to set aad in unsupported state");
      };
      CipherBase.prototype._transform = function(data, _, next) {
        var err;
        try {
          this.hashMode ? this._update(data) : this.push(this._update(data));
        } catch (e) {
          err = e;
        } finally {
          next(err);
        }
      };
      CipherBase.prototype._flush = function(done) {
        var err;
        try {
          this.push(this.__final());
        } catch (e) {
          err = e;
        }
        done(err);
      };
      CipherBase.prototype._finalOrDigest = function(outputEnc) {
        var outData = this.__final() || Buffer4.alloc(0);
        return outputEnc && (outData = this._toString(outData, outputEnc, !0)), outData;
      };
      CipherBase.prototype._toString = function(value, enc, fin) {
        if (this._decoder || (this._decoder = new StringDecoder(enc), this._encoding = enc), this._encoding !== enc)
          throw new Error("can\u2019t switch encodings");
        var out = this._decoder.write(value);
        return fin && (out += this._decoder.end()), out;
      };
      module.exports = CipherBase;
    }
  });

  // node_modules/create-hash/browser.js
  var require_browser3 = __commonJS({
    "node_modules/create-hash/browser.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      var inherits = require_inherits_browser(), MD5 = require_md5(), RIPEMD160 = require_ripemd1602(), sha = require_sha3(), Base = require_cipher_base();
      function Hash(hash) {
        Base.call(this, "digest"), this._hash = hash;
      }
      inherits(Hash, Base);
      Hash.prototype._update = function(data) {
        this._hash.update(data);
      };
      Hash.prototype._final = function() {
        return this._hash.digest();
      };
      module.exports = function(alg) {
        return alg = alg.toLowerCase(), alg === "md5" ? new MD5() : alg === "rmd160" || alg === "ripemd160" ? new RIPEMD160() : new Hash(sha(alg));
      };
    }
  });

  // node_modules/wif/node_modules/base-x/src/index.js
  var require_src3 = __commonJS({
    "node_modules/wif/node_modules/base-x/src/index.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      var _Buffer = require_safe_buffer().Buffer;
      function base(ALPHABET) {
        if (ALPHABET.length >= 255)
          throw new TypeError("Alphabet too long");
        for (var BASE_MAP = new Uint8Array(256), j = 0; j < BASE_MAP.length; j++)
          BASE_MAP[j] = 255;
        for (var i = 0; i < ALPHABET.length; i++) {
          var x = ALPHABET.charAt(i), xc = x.charCodeAt(0);
          if (BASE_MAP[xc] !== 255)
            throw new TypeError(x + " is ambiguous");
          BASE_MAP[xc] = i;
        }
        var BASE = ALPHABET.length, LEADER = ALPHABET.charAt(0), FACTOR = Math.log(BASE) / Math.log(256), iFACTOR = Math.log(256) / Math.log(BASE);
        function encode(source) {
          if ((Array.isArray(source) || source instanceof Uint8Array) && (source = _Buffer.from(source)), !_Buffer.isBuffer(source))
            throw new TypeError("Expected Buffer");
          if (source.length === 0)
            return "";
          for (var zeroes = 0, length = 0, pbegin = 0, pend = source.length; pbegin !== pend && source[pbegin] === 0; )
            pbegin++, zeroes++;
          for (var size = (pend - pbegin) * iFACTOR + 1 >>> 0, b58 = new Uint8Array(size); pbegin !== pend; ) {
            for (var carry = source[pbegin], i2 = 0, it1 = size - 1; (carry !== 0 || i2 < length) && it1 !== -1; it1--, i2++)
              carry += 256 * b58[it1] >>> 0, b58[it1] = carry % BASE >>> 0, carry = carry / BASE >>> 0;
            if (carry !== 0)
              throw new Error("Non-zero carry");
            length = i2, pbegin++;
          }
          for (var it2 = size - length; it2 !== size && b58[it2] === 0; )
            it2++;
          for (var str = LEADER.repeat(zeroes); it2 < size; ++it2)
            str += ALPHABET.charAt(b58[it2]);
          return str;
        }
        function decodeUnsafe(source) {
          if (typeof source != "string")
            throw new TypeError("Expected String");
          if (source.length === 0)
            return _Buffer.alloc(0);
          for (var psz = 0, zeroes = 0, length = 0; source[psz] === LEADER; )
            zeroes++, psz++;
          for (var size = (source.length - psz) * FACTOR + 1 >>> 0, b256 = new Uint8Array(size); psz < source.length; ) {
            var charCode = source.charCodeAt(psz);
            if (charCode > 255)
              return;
            var carry = BASE_MAP[charCode];
            if (carry === 255)
              return;
            for (var i2 = 0, it3 = size - 1; (carry !== 0 || i2 < length) && it3 !== -1; it3--, i2++)
              carry += BASE * b256[it3] >>> 0, b256[it3] = carry % 256 >>> 0, carry = carry / 256 >>> 0;
            if (carry !== 0)
              throw new Error("Non-zero carry");
            length = i2, psz++;
          }
          for (var it4 = size - length; it4 !== size && b256[it4] === 0; )
            it4++;
          var vch = _Buffer.allocUnsafe(zeroes + (size - it4));
          vch.fill(0, 0, zeroes);
          for (var j2 = zeroes; it4 !== size; )
            vch[j2++] = b256[it4++];
          return vch;
        }
        function decode(string) {
          var buffer = decodeUnsafe(string);
          if (buffer)
            return buffer;
          throw new Error("Non-base" + BASE + " character");
        }
        return {
          encode,
          decodeUnsafe,
          decode
        };
      }
      module.exports = base;
    }
  });

  // node_modules/wif/node_modules/bs58/index.js
  var require_bs582 = __commonJS({
    "node_modules/wif/node_modules/bs58/index.js"(exports, module) {
      init_buffer_shim();
      init_process_shim();
      var basex = require_src3(), ALPHABET = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";
      module.exports = basex(ALPHABET);
    }
  });

  // node_modules/wif/node_modules/bs58check/base.js
  var require_base2 = __commonJS({
    "node_modules/wif/node_modules/bs58check/base.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      var base58 = require_bs582(), Buffer4 = require_safe_buffer().Buffer;
      module.exports = function(checksumFn) {
        function encode(payload) {
          var checksum = checksumFn(payload);
          return base58.encode(Buffer4.concat([
            payload,
            checksum
          ], payload.length + 4));
        }
        function decodeRaw(buffer) {
          var payload = buffer.slice(0, -4), checksum = buffer.slice(-4), newChecksum = checksumFn(payload);
          if (!(checksum[0] ^ newChecksum[0] | checksum[1] ^ newChecksum[1] | checksum[2] ^ newChecksum[2] | checksum[3] ^ newChecksum[3]))
            return payload;
        }
        function decodeUnsafe(string) {
          var buffer = base58.decodeUnsafe(string);
          if (buffer)
            return decodeRaw(buffer);
        }
        function decode(string) {
          var buffer = base58.decode(string), payload = decodeRaw(buffer, checksumFn);
          if (!payload) throw new Error("Invalid checksum");
          return payload;
        }
        return {
          encode,
          decode,
          decodeUnsafe
        };
      };
    }
  });

  // node_modules/wif/node_modules/bs58check/index.js
  var require_bs58check2 = __commonJS({
    "node_modules/wif/node_modules/bs58check/index.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      var createHash = require_browser3(), bs58checkBase = require_base2();
      function sha256x2(buffer) {
        var tmp = createHash("sha256").update(buffer).digest();
        return createHash("sha256").update(tmp).digest();
      }
      module.exports = bs58checkBase(sha256x2);
    }
  });

  // node_modules/wif/index.js
  var require_wif = __commonJS({
    "node_modules/wif/index.js"(exports, module) {
      init_buffer_shim();
      init_process_shim();
      var bs58check = require_bs58check2();
      function decodeRaw(buffer, version) {
        if (version !== void 0 && buffer[0] !== version) throw new Error("Invalid network version");
        if (buffer.length === 33)
          return {
            version: buffer[0],
            privateKey: buffer.slice(1, 33),
            compressed: !1
          };
        if (buffer.length !== 34) throw new Error("Invalid WIF length");
        if (buffer[33] !== 1) throw new Error("Invalid compression flag");
        return {
          version: buffer[0],
          privateKey: buffer.slice(1, 33),
          compressed: !0
        };
      }
      function encodeRaw(version, privateKey, compressed) {
        var result = new import_buffer.Buffer(compressed ? 34 : 33);
        return result.writeUInt8(version, 0), privateKey.copy(result, 1), compressed && (result[33] = 1), result;
      }
      function decode(string, version) {
        return decodeRaw(bs58check.decode(string), version);
      }
      function encode(version, privateKey, compressed) {
        return typeof version == "number" ? bs58check.encode(encodeRaw(version, privateKey, compressed)) : bs58check.encode(
          encodeRaw(
            version.version,
            version.privateKey,
            version.compressed
          )
        );
      }
      module.exports = {
        decode,
        decodeRaw,
        encode,
        encodeRaw
      };
    }
  });

  // node_modules/bip32/src/bip32.js
  var require_bip32 = __commonJS({
    "node_modules/bip32/src/bip32.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      exports.BIP32Factory = void 0;
      var crypto2 = require_crypto3(), testecc_1 = require_testecc(), base_1 = require_lib(), sha256_1 = require_sha256(), typeforce = require_typeforce(), wif = require_wif(), _bs58check = (0, base_1.base58check)(sha256_1.sha256), bs58check = {
        encode: (data) => _bs58check.encode(Uint8Array.from(data)),
        decode: (str) => import_buffer.Buffer.from(_bs58check.decode(str))
      };
      function BIP32Factory2(ecc2) {
        (0, testecc_1.testEcc)(ecc2);
        let UINT256_TYPE = typeforce.BufferN(32), NETWORK_TYPE = typeforce.compile({
          wif: typeforce.UInt8,
          bip32: {
            public: typeforce.UInt32,
            private: typeforce.UInt32
          }
        }), BITCOIN = {
          messagePrefix: `Bitcoin Signed Message:
`,
          bech32: "bc",
          bip32: {
            public: 76067358,
            private: 76066276
          },
          pubKeyHash: 0,
          scriptHash: 5,
          wif: 128
        }, HIGHEST_BIT = 2147483648, UINT31_MAX = Math.pow(2, 31) - 1;
        function BIP32Path(value) {
          return typeforce.String(value) && value.match(/^(m\/)?(\d+'?\/)*\d+'?$/) !== null;
        }
        function UInt31(value) {
          return typeforce.UInt32(value) && value <= UINT31_MAX;
        }
        function toXOnly2(pubKey) {
          return pubKey.length === 32 ? pubKey : pubKey.slice(1, 33);
        }
        class Bip32Signer {
          constructor(__D, __Q) {
            this.__D = __D, this.__Q = __Q, this.lowR = !1;
          }
          get publicKey() {
            return this.__Q === void 0 && (this.__Q = import_buffer.Buffer.from(ecc2.pointFromScalar(this.__D, !0))), this.__Q;
          }
          get privateKey() {
            return this.__D;
          }
          sign(hash, lowR) {
            if (!this.privateKey)
              throw new Error("Missing private key");
            if (lowR === void 0 && (lowR = this.lowR), lowR === !1)
              return import_buffer.Buffer.from(ecc2.sign(hash, this.privateKey));
            {
              let sig = import_buffer.Buffer.from(ecc2.sign(hash, this.privateKey)), extraData = import_buffer.Buffer.alloc(32, 0), counter = 0;
              for (; sig[0] > 127; )
                counter++, extraData.writeUIntLE(counter, 0, 6), sig = import_buffer.Buffer.from(ecc2.sign(hash, this.privateKey, extraData));
              return sig;
            }
          }
          signSchnorr(hash) {
            if (!this.privateKey)
              throw new Error("Missing private key");
            if (!ecc2.signSchnorr)
              throw new Error("signSchnorr not supported by ecc library");
            return import_buffer.Buffer.from(ecc2.signSchnorr(hash, this.privateKey));
          }
          verify(hash, signature) {
            return ecc2.verify(hash, this.publicKey, signature);
          }
          verifySchnorr(hash, signature) {
            if (!ecc2.verifySchnorr)
              throw new Error("verifySchnorr not supported by ecc library");
            return ecc2.verifySchnorr(hash, this.publicKey.subarray(1, 33), signature);
          }
        }
        class BIP32 extends Bip32Signer {
          constructor(__D, __Q, chainCode, network2, __DEPTH = 0, __INDEX = 0, __PARENT_FINGERPRINT = 0) {
            super(__D, __Q), this.chainCode = chainCode, this.network = network2, this.__DEPTH = __DEPTH, this.__INDEX = __INDEX, this.__PARENT_FINGERPRINT = __PARENT_FINGERPRINT, typeforce(NETWORK_TYPE, network2);
          }
          get depth() {
            return this.__DEPTH;
          }
          get index() {
            return this.__INDEX;
          }
          get parentFingerprint() {
            return this.__PARENT_FINGERPRINT;
          }
          get identifier() {
            return crypto2.hash160(this.publicKey);
          }
          get fingerprint() {
            return this.identifier.slice(0, 4);
          }
          get compressed() {
            return !0;
          }
          // Private === not neutered
          // Public === neutered
          isNeutered() {
            return this.__D === void 0;
          }
          neutered() {
            return fromPublicKeyLocal(this.publicKey, this.chainCode, this.network, this.depth, this.index, this.parentFingerprint);
          }
          toBase58() {
            let network2 = this.network, version = this.isNeutered() ? network2.bip32.public : network2.bip32.private, buffer = import_buffer.Buffer.allocUnsafe(78);
            return buffer.writeUInt32BE(version, 0), buffer.writeUInt8(this.depth, 4), buffer.writeUInt32BE(this.parentFingerprint, 5), buffer.writeUInt32BE(this.index, 9), this.chainCode.copy(buffer, 13), this.isNeutered() ? this.publicKey.copy(buffer, 45) : (buffer.writeUInt8(0, 45), this.privateKey.copy(buffer, 46)), bs58check.encode(buffer);
          }
          toWIF() {
            if (!this.privateKey)
              throw new TypeError("Missing private key");
            return wif.encode(this.network.wif, this.privateKey, !0);
          }
          // https://github.com/bitcoin/bips/blob/master/bip-0032.mediawiki#child-key-derivation-ckd-functions
          derive(index) {
            typeforce(typeforce.UInt32, index);
            let isHardened = index >= HIGHEST_BIT, data = import_buffer.Buffer.allocUnsafe(37);
            if (isHardened) {
              if (this.isNeutered())
                throw new TypeError("Missing private key for hardened child key");
              data[0] = 0, this.privateKey.copy(data, 1), data.writeUInt32BE(index, 33);
            } else
              this.publicKey.copy(data, 0), data.writeUInt32BE(index, 33);
            let I = crypto2.hmacSHA512(this.chainCode, data), IL = I.slice(0, 32), IR = I.slice(32);
            if (!ecc2.isPrivate(IL))
              return this.derive(index + 1);
            let hd;
            if (this.isNeutered()) {
              let Ki = import_buffer.Buffer.from(ecc2.pointAddScalar(this.publicKey, IL, !0));
              if (Ki === null)
                return this.derive(index + 1);
              hd = fromPublicKeyLocal(Ki, IR, this.network, this.depth + 1, index, this.fingerprint.readUInt32BE(0));
            } else {
              let ki = import_buffer.Buffer.from(ecc2.privateAdd(this.privateKey, IL));
              if (ki == null)
                return this.derive(index + 1);
              hd = fromPrivateKeyLocal(ki, IR, this.network, this.depth + 1, index, this.fingerprint.readUInt32BE(0));
            }
            return hd;
          }
          deriveHardened(index) {
            return typeforce(UInt31, index), this.derive(index + HIGHEST_BIT);
          }
          derivePath(path) {
            typeforce(BIP32Path, path);
            let splitPath = path.split("/");
            if (splitPath[0] === "m") {
              if (this.parentFingerprint)
                throw new TypeError("Expected master, got child");
              splitPath = splitPath.slice(1);
            }
            return splitPath.reduce((prevHd, indexStr) => {
              let index;
              return indexStr.slice(-1) === "'" ? (index = parseInt(indexStr.slice(0, -1), 10), prevHd.deriveHardened(index)) : (index = parseInt(indexStr, 10), prevHd.derive(index));
            }, this);
          }
          tweak(t) {
            return this.privateKey ? this.tweakFromPrivateKey(t) : this.tweakFromPublicKey(t);
          }
          tweakFromPublicKey(t) {
            let xOnlyPubKey = toXOnly2(this.publicKey);
            if (!ecc2.xOnlyPointAddTweak)
              throw new Error("xOnlyPointAddTweak not supported by ecc library");
            let tweakedPublicKey = ecc2.xOnlyPointAddTweak(xOnlyPubKey, t);
            if (!tweakedPublicKey || tweakedPublicKey.xOnlyPubkey === null)
              throw new Error("Cannot tweak public key!");
            let parityByte = import_buffer.Buffer.from([
              tweakedPublicKey.parity === 0 ? 2 : 3
            ]), tweakedPublicKeyCompresed = import_buffer.Buffer.concat([
              parityByte,
              tweakedPublicKey.xOnlyPubkey
            ]);
            return new Bip32Signer(void 0, tweakedPublicKeyCompresed);
          }
          tweakFromPrivateKey(t) {
            let hasOddY = this.publicKey[0] === 3 || this.publicKey[0] === 4 && (this.publicKey[64] & 1) === 1, privateKey = (() => {
              if (hasOddY) {
                if (ecc2.privateNegate)
                  return ecc2.privateNegate(this.privateKey);
                throw new Error("privateNegate not supported by ecc library");
              } else return this.privateKey;
            })(), tweakedPrivateKey = ecc2.privateAdd(privateKey, t);
            if (!tweakedPrivateKey)
              throw new Error("Invalid tweaked private key!");
            return new Bip32Signer(import_buffer.Buffer.from(tweakedPrivateKey), void 0);
          }
        }
        function fromBase58(inString, network2) {
          let buffer = bs58check.decode(inString);
          if (buffer.length !== 78)
            throw new TypeError("Invalid buffer length");
          network2 = network2 || BITCOIN;
          let version = buffer.readUInt32BE(0);
          if (version !== network2.bip32.private && version !== network2.bip32.public)
            throw new TypeError("Invalid network version");
          let depth = buffer[4], parentFingerprint = buffer.readUInt32BE(5);
          if (depth === 0 && parentFingerprint !== 0)
            throw new TypeError("Invalid parent fingerprint");
          let index = buffer.readUInt32BE(9);
          if (depth === 0 && index !== 0)
            throw new TypeError("Invalid index");
          let chainCode = buffer.slice(13, 45), hd;
          if (version === network2.bip32.private) {
            if (buffer.readUInt8(45) !== 0)
              throw new TypeError("Invalid private key");
            let k = buffer.slice(46, 78);
            hd = fromPrivateKeyLocal(k, chainCode, network2, depth, index, parentFingerprint);
          } else {
            let X = buffer.slice(45, 78);
            hd = fromPublicKeyLocal(X, chainCode, network2, depth, index, parentFingerprint);
          }
          return hd;
        }
        function fromPrivateKey(privateKey, chainCode, network2) {
          return fromPrivateKeyLocal(privateKey, chainCode, network2);
        }
        function fromPrivateKeyLocal(privateKey, chainCode, network2, depth, index, parentFingerprint) {
          if (typeforce({
            privateKey: UINT256_TYPE,
            chainCode: UINT256_TYPE
          }, { privateKey, chainCode }), network2 = network2 || BITCOIN, !ecc2.isPrivate(privateKey))
            throw new TypeError("Private key not in range [1, n)");
          return new BIP32(privateKey, void 0, chainCode, network2, depth, index, parentFingerprint);
        }
        function fromPublicKey(publicKey, chainCode, network2) {
          return fromPublicKeyLocal(publicKey, chainCode, network2);
        }
        function fromPublicKeyLocal(publicKey, chainCode, network2, depth, index, parentFingerprint) {
          if (typeforce({
            publicKey: typeforce.BufferN(33),
            chainCode: UINT256_TYPE
          }, { publicKey, chainCode }), network2 = network2 || BITCOIN, !ecc2.isPoint(publicKey))
            throw new TypeError("Point is not on the curve");
          return new BIP32(void 0, publicKey, chainCode, network2, depth, index, parentFingerprint);
        }
        function fromSeed(seed, network2) {
          if (typeforce(typeforce.Buffer, seed), seed.length < 16)
            throw new TypeError("Seed should be at least 128 bits");
          if (seed.length > 64)
            throw new TypeError("Seed should be at most 512 bits");
          network2 = network2 || BITCOIN;
          let I = crypto2.hmacSHA512(import_buffer.Buffer.from("Bitcoin seed", "utf8"), seed), IL = I.slice(0, 32), IR = I.slice(32);
          return fromPrivateKey(IL, IR, network2);
        }
        return {
          fromSeed,
          fromBase58,
          fromPublicKey,
          fromPrivateKey
        };
      }
      exports.BIP32Factory = BIP32Factory2;
    }
  });

  // node_modules/bip32/src/index.js
  var require_src4 = __commonJS({
    "node_modules/bip32/src/index.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      exports.BIP32Factory = exports.default = void 0;
      var bip32_1 = require_bip32();
      Object.defineProperty(exports, "default", { enumerable: !0, get: function() {
        return bip32_1.BIP32Factory;
      } });
      Object.defineProperty(exports, "BIP32Factory", { enumerable: !0, get: function() {
        return bip32_1.BIP32Factory;
      } });
    }
  });

  // node_modules/ecpair/src/networks.js
  var require_networks2 = __commonJS({
    "node_modules/ecpair/src/networks.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      exports.testnet = exports.bitcoin = void 0;
      exports.bitcoin = {
        messagePrefix: `Bitcoin Signed Message:
`,
        bech32: "bc",
        bip32: {
          public: 76067358,
          private: 76066276
        },
        pubKeyHash: 0,
        scriptHash: 5,
        wif: 128
      };
      exports.testnet = {
        messagePrefix: `Bitcoin Signed Message:
`,
        bech32: "tb",
        bip32: {
          public: 70617039,
          private: 70615956
        },
        pubKeyHash: 111,
        scriptHash: 196,
        wif: 239
      };
    }
  });

  // node_modules/ecpair/src/types.js
  var require_types2 = __commonJS({
    "node_modules/ecpair/src/types.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      exports.maybe = exports.Boolean = exports.Array = exports.Buffer256bit = exports.Network = exports.typeforce = void 0;
      exports.typeforce = require_typeforce();
      exports.Network = exports.typeforce.compile({
        messagePrefix: exports.typeforce.oneOf(
          exports.typeforce.Buffer,
          exports.typeforce.String
        ),
        bip32: {
          public: exports.typeforce.UInt32,
          private: exports.typeforce.UInt32
        },
        pubKeyHash: exports.typeforce.UInt8,
        scriptHash: exports.typeforce.UInt8,
        wif: exports.typeforce.UInt8
      });
      exports.Buffer256bit = exports.typeforce.BufferN(32);
      exports.Array = exports.typeforce.Array;
      exports.Boolean = exports.typeforce.Boolean;
      exports.maybe = exports.typeforce.maybe;
    }
  });

  // node_modules/randombytes/browser.js
  var require_browser4 = __commonJS({
    "node_modules/randombytes/browser.js"(exports, module) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      var MAX_BYTES = 65536, MAX_UINT32 = 4294967295;
      function oldBrowser() {
        throw new Error(`Secure random number generation is not supported by this browser.
Use Chrome, Firefox or Internet Explorer 11`);
      }
      var Buffer4 = require_safe_buffer().Buffer, crypto2 = globalThis.crypto || globalThis.msCrypto;
      crypto2 && crypto2.getRandomValues ? module.exports = randomBytes : module.exports = oldBrowser;
      function randomBytes(size, cb) {
        if (size > MAX_UINT32) throw new RangeError("requested too many random bytes");
        var bytes = Buffer4.allocUnsafe(size);
        if (size > 0)
          if (size > MAX_BYTES)
            for (var generated = 0; generated < size; generated += MAX_BYTES)
              crypto2.getRandomValues(bytes.slice(generated, generated + MAX_BYTES));
          else
            crypto2.getRandomValues(bytes);
        return typeof cb == "function" ? import_browser.default.nextTick(function() {
          cb(null, bytes);
        }) : bytes;
      }
    }
  });

  // node_modules/ecpair/src/testecc.js
  var require_testecc2 = __commonJS({
    "node_modules/ecpair/src/testecc.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      exports.testEcc = void 0;
      var h = (hex) => import_buffer.Buffer.from(hex, "hex");
      function testEcc(ecc2) {
        assert(
          ecc2.isPoint(
            h("0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798")
          )
        ), assert(
          !ecc2.isPoint(
            h("030000000000000000000000000000000000000000000000000000000000000005")
          )
        ), assert(
          ecc2.isPrivate(
            h("79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798")
          )
        ), assert(
          ecc2.isPrivate(
            h("fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364140")
          )
        ), assert(
          !ecc2.isPrivate(
            h("0000000000000000000000000000000000000000000000000000000000000000")
          )
        ), assert(
          !ecc2.isPrivate(
            h("fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141")
          )
        ), assert(
          !ecc2.isPrivate(
            h("fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364142")
          )
        ), assert(
          import_buffer.Buffer.from(
            ecc2.privateAdd(
              h("0000000000000000000000000000000000000000000000000000000000000001"),
              h("0000000000000000000000000000000000000000000000000000000000000000")
            )
          ).equals(
            h("0000000000000000000000000000000000000000000000000000000000000001")
          )
        ), assert(
          ecc2.privateAdd(
            h("fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd036413e"),
            h("0000000000000000000000000000000000000000000000000000000000000003")
          ) === null
        ), assert(
          import_buffer.Buffer.from(
            ecc2.privateAdd(
              h("e211078564db65c3ce7704f08262b1f38f1ef412ad15b5ac2d76657a63b2c500"),
              h("b51fbb69051255d1becbd683de5848242a89c229348dd72896a87ada94ae8665")
            )
          ).equals(
            h("9730c2ee69edbb958d42db7460bafa18fef9d955325aec99044c81c8282b0a24")
          )
        ), assert(
          import_buffer.Buffer.from(
            ecc2.privateNegate(
              h("0000000000000000000000000000000000000000000000000000000000000001")
            )
          ).equals(
            h("fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364140")
          )
        ), assert(
          import_buffer.Buffer.from(
            ecc2.privateNegate(
              h("fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd036413e")
            )
          ).equals(
            h("0000000000000000000000000000000000000000000000000000000000000003")
          )
        ), assert(
          import_buffer.Buffer.from(
            ecc2.privateNegate(
              h("b1121e4088a66a28f5b6b0f5844943ecd9f610196d7bb83b25214b60452c09af")
            )
          ).equals(
            h("4eede1bf775995d70a494f0a7bb6bc11e0b8cccd41cce8009ab1132c8b0a3792")
          )
        ), assert(
          import_buffer.Buffer.from(
            ecc2.pointCompress(
              h(
                "0479be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798483ada7726a3c4655da4fbfc0e1108a8fd17b448a68554199c47d08ffb10d4b8"
              ),
              !0
            )
          ).equals(
            h("0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798")
          )
        ), assert(
          import_buffer.Buffer.from(
            ecc2.pointCompress(
              h(
                "0479be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798483ada7726a3c4655da4fbfc0e1108a8fd17b448a68554199c47d08ffb10d4b8"
              ),
              !1
            )
          ).equals(
            h(
              "0479be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798483ada7726a3c4655da4fbfc0e1108a8fd17b448a68554199c47d08ffb10d4b8"
            )
          )
        ), assert(
          import_buffer.Buffer.from(
            ecc2.pointCompress(
              h("0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"),
              !0
            )
          ).equals(
            h("0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798")
          )
        ), assert(
          import_buffer.Buffer.from(
            ecc2.pointCompress(
              h("0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"),
              !1
            )
          ).equals(
            h(
              "0479be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798483ada7726a3c4655da4fbfc0e1108a8fd17b448a68554199c47d08ffb10d4b8"
            )
          )
        ), assert(
          import_buffer.Buffer.from(
            ecc2.pointFromScalar(
              h("b1121e4088a66a28f5b6b0f5844943ecd9f610196d7bb83b25214b60452c09af")
            )
          ).equals(
            h("02b07ba9dca9523b7ef4bd97703d43d20399eb698e194704791a25ce77a400df99")
          )
        ), assert(
          ecc2.xOnlyPointAddTweak(
            h("79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"),
            h("fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364140")
          ) === null
        );
        let xOnlyRes = ecc2.xOnlyPointAddTweak(
          h("1617d38ed8d8657da4d4761e8057bc396ea9e4b9d29776d4be096016dbd2509b"),
          h("a8397a935f0dfceba6ba9618f6451ef4d80637abf4e6af2669fbc9de6a8fd2ac")
        );
        assert(
          import_buffer.Buffer.from(xOnlyRes.xOnlyPubkey).equals(
            h("e478f99dab91052ab39a33ea35fd5e6e4933f4d28023cd597c9a1f6760346adf")
          ) && xOnlyRes.parity === 1
        ), xOnlyRes = ecc2.xOnlyPointAddTweak(
          h("2c0b7cf95324a07d05398b240174dc0c2be444d96b159aa6c7f7b1e668680991"),
          h("823c3cd2142744b075a87eade7e1b8678ba308d566226a0056ca2b7a76f86b47")
        ), assert(
          import_buffer.Buffer.from(xOnlyRes.xOnlyPubkey).equals(
            h("9534f8dc8c6deda2dc007655981c78b49c5d96c778fbf363462a11ec9dfd948c")
          ) && xOnlyRes.parity === 0
        ), assert(
          import_buffer.Buffer.from(
            ecc2.sign(
              h("5e9f0a0d593efdcf78ac923bc3313e4e7d408d574354ee2b3288c0da9fbba6ed"),
              h("fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364140")
            )
          ).equals(
            h(
              "54c4a33c6423d689378f160a7ff8b61330444abb58fb470f96ea16d99d4a2fed07082304410efa6b2943111b6a4e0aaa7b7db55a07e9861d1fb3cb1f421044a5"
            )
          )
        ), assert(
          ecc2.verify(
            h("5e9f0a0d593efdcf78ac923bc3313e4e7d408d574354ee2b3288c0da9fbba6ed"),
            h("0379be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"),
            h(
              "54c4a33c6423d689378f160a7ff8b61330444abb58fb470f96ea16d99d4a2fed07082304410efa6b2943111b6a4e0aaa7b7db55a07e9861d1fb3cb1f421044a5"
            )
          )
        ), ecc2.signSchnorr && assert(
          import_buffer.Buffer.from(
            ecc2.signSchnorr(
              h("7e2d58d8b3bcdf1abadec7829054f90dda9805aab56c77333024b9d0a508b75c"),
              h("c90fdaa22168c234c4c6628b80dc1cd129024e088a67cc74020bbea63b14e5c9"),
              h("c87aa53824b4d7ae2eb035a2b5bbbccc080e76cdc6d1692c4b0b62d798e6d906")
            )
          ).equals(
            h(
              "5831aaeed7b44bb74e5eab94ba9d4294c49bcf2a60728d8b4c200f50dd313c1bab745879a5ad954a72c45a91c3a51d3c7adea98d82f8481e0e1e03674a6f3fb7"
            )
          )
        ), ecc2.verifySchnorr && assert(
          ecc2.verifySchnorr(
            h("7e2d58d8b3bcdf1abadec7829054f90dda9805aab56c77333024b9d0a508b75c"),
            h("dd308afec5777e13121fa72b9cc1b7cc0139715309b086c960e18fd969774eb8"),
            h(
              "5831aaeed7b44bb74e5eab94ba9d4294c49bcf2a60728d8b4c200f50dd313c1bab745879a5ad954a72c45a91c3a51d3c7adea98d82f8481e0e1e03674a6f3fb7"
            )
          )
        );
      }
      exports.testEcc = testEcc;
      function assert(bool) {
        if (!bool) throw new Error("ecc library invalid");
      }
    }
  });

  // node_modules/ecpair/src/ecpair.js
  var require_ecpair = __commonJS({
    "node_modules/ecpair/src/ecpair.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      exports.ECPairFactory = exports.networks = void 0;
      var networks2 = require_networks2();
      exports.networks = networks2;
      var types = require_types2(), randomBytes = require_browser4(), wif = require_wif(), testecc_1 = require_testecc2(), isOptions = types.typeforce.maybe(
        types.typeforce.compile({
          compressed: types.maybe(types.Boolean),
          network: types.maybe(types.Network)
        })
      ), toXOnly2 = (pubKey) => pubKey.length === 32 ? pubKey : pubKey.slice(1, 33);
      function ECPairFactory2(ecc2) {
        (0, testecc_1.testEcc)(ecc2);
        function isPoint2(maybePoint) {
          return ecc2.isPoint(maybePoint);
        }
        function fromPrivateKey(buffer, options) {
          if (types.typeforce(types.Buffer256bit, buffer), !ecc2.isPrivate(buffer))
            throw new TypeError("Private key not in range [1, n)");
          return types.typeforce(isOptions, options), new ECPair2(buffer, void 0, options);
        }
        function fromPublicKey(buffer, options) {
          return types.typeforce(ecc2.isPoint, buffer), types.typeforce(isOptions, options), new ECPair2(void 0, buffer, options);
        }
        function fromWIF(wifString, network2) {
          let decoded = wif.decode(wifString), version = decoded.version;
          if (types.Array(network2)) {
            if (network2 = network2.filter((x) => version === x.wif).pop(), !network2) throw new Error("Unknown network version");
          } else if (network2 = network2 || networks2.bitcoin, version !== network2.wif) throw new Error("Invalid network version");
          return fromPrivateKey(decoded.privateKey, {
            compressed: decoded.compressed,
            network: network2
          });
        }
        function makeRandom(options) {
          types.typeforce(isOptions, options), options === void 0 && (options = {});
          let rng = options.rng || randomBytes, d;
          do
            d = rng(32), types.typeforce(types.Buffer256bit, d);
          while (!ecc2.isPrivate(d));
          return fromPrivateKey(d, options);
        }
        class ECPair2 {
          __D;
          __Q;
          compressed;
          network;
          lowR;
          constructor(__D, __Q, options) {
            this.__D = __D, this.__Q = __Q, this.lowR = !1, options === void 0 && (options = {}), this.compressed = options.compressed === void 0 ? !0 : options.compressed, this.network = options.network || networks2.bitcoin, __Q !== void 0 && (this.__Q = import_buffer.Buffer.from(ecc2.pointCompress(__Q, this.compressed)));
          }
          get privateKey() {
            return this.__D;
          }
          get publicKey() {
            if (!this.__Q) {
              let p = ecc2.pointFromScalar(this.__D, this.compressed);
              this.__Q = import_buffer.Buffer.from(p);
            }
            return this.__Q;
          }
          toWIF() {
            if (!this.__D) throw new Error("Missing private key");
            return wif.encode(this.network.wif, this.__D, this.compressed);
          }
          tweak(t) {
            return this.privateKey ? this.tweakFromPrivateKey(t) : this.tweakFromPublicKey(t);
          }
          sign(hash, lowR) {
            if (!this.__D) throw new Error("Missing private key");
            if (lowR === void 0 && (lowR = this.lowR), lowR === !1)
              return import_buffer.Buffer.from(ecc2.sign(hash, this.__D));
            {
              let sig = ecc2.sign(hash, this.__D), extraData = import_buffer.Buffer.alloc(32, 0), counter = 0;
              for (; sig[0] > 127; )
                counter++, extraData.writeUIntLE(counter, 0, 6), sig = ecc2.sign(hash, this.__D, extraData);
              return import_buffer.Buffer.from(sig);
            }
          }
          signSchnorr(hash) {
            if (!this.privateKey) throw new Error("Missing private key");
            if (!ecc2.signSchnorr)
              throw new Error("signSchnorr not supported by ecc library");
            return import_buffer.Buffer.from(ecc2.signSchnorr(hash, this.privateKey));
          }
          verify(hash, signature) {
            return ecc2.verify(hash, this.publicKey, signature);
          }
          verifySchnorr(hash, signature) {
            if (!ecc2.verifySchnorr)
              throw new Error("verifySchnorr not supported by ecc library");
            return ecc2.verifySchnorr(hash, this.publicKey.subarray(1, 33), signature);
          }
          tweakFromPublicKey(t) {
            let xOnlyPubKey = toXOnly2(this.publicKey), tweakedPublicKey = ecc2.xOnlyPointAddTweak(xOnlyPubKey, t);
            if (!tweakedPublicKey || tweakedPublicKey.xOnlyPubkey === null)
              throw new Error("Cannot tweak public key!");
            let parityByte = import_buffer.Buffer.from([
              tweakedPublicKey.parity === 0 ? 2 : 3
            ]);
            return fromPublicKey(
              import_buffer.Buffer.concat([parityByte, tweakedPublicKey.xOnlyPubkey]),
              { network: this.network, compressed: this.compressed }
            );
          }
          tweakFromPrivateKey(t) {
            let privateKey = this.publicKey[0] === 3 || this.publicKey[0] === 4 && (this.publicKey[64] & 1) === 1 ? ecc2.privateNegate(this.privateKey) : this.privateKey, tweakedPrivateKey = ecc2.privateAdd(privateKey, t);
            if (!tweakedPrivateKey) throw new Error("Invalid tweaked private key!");
            return fromPrivateKey(import_buffer.Buffer.from(tweakedPrivateKey), {
              network: this.network,
              compressed: this.compressed
            });
          }
        }
        return {
          isPoint: isPoint2,
          fromPrivateKey,
          fromPublicKey,
          fromWIF,
          makeRandom
        };
      }
      exports.ECPairFactory = ECPairFactory2;
    }
  });

  // node_modules/ecpair/src/index.js
  var require_src5 = __commonJS({
    "node_modules/ecpair/src/index.js"(exports) {
      "use strict";
      init_buffer_shim();
      init_process_shim();
      Object.defineProperty(exports, "__esModule", { value: !0 });
      exports.networks = exports.ECPairFactory = exports.default = void 0;
      var ecpair_1 = require_ecpair();
      Object.defineProperty(exports, "default", {
        enumerable: !0,
        get: function() {
          return ecpair_1.ECPairFactory;
        }
      });
      Object.defineProperty(exports, "ECPairFactory", {
        enumerable: !0,
        get: function() {
          return ecpair_1.ECPairFactory;
        }
      });
      Object.defineProperty(exports, "networks", {
        enumerable: !0,
        get: function() {
          return ecpair_1.networks;
        }
      });
    }
  });

  // src/index.js
  var index_exports = {};
  __export(index_exports, {
    bip322Hashes: () => bip322Hashes,
    buildTransaction: () => buildTransaction,
    buildTransactionWithPrivateKey: () => buildTransactionWithPrivateKey,
    getTaprootAddressFromPublicKey: () => getTaprootAddressFromPublicKey,
    getTaprootAddresses: () => getTaprootAddresses,
    getTaprootXpubs: () => getTaprootXpubs,
    isTaprootAddress: () => isTaprootAddress,
    signMessageBip322: () => signMessageBip322,
    signMessageBip322WithPrivateKey: () => signMessageBip322WithPrivateKey,
    validateAddress: () => validateAddress,
    verifyMessageBip322: () => verifyMessageBip322
  });
  init_buffer_shim();
  init_process_shim();
  var bitcoin = __toESM(require_src2()), ecc = __toESM(require_dist2()), import_bip32 = __toESM(require_src4()), import_ecpair = __toESM(require_src5()), import_buffer2 = __toESM(require_buffer());
  bitcoin.initEccLib(ecc);
  var bip32 = (0, import_bip32.default)(ecc), ECPair = (0, import_ecpair.default)(ecc), network = bitcoin.networks.bitcoin, TAPROOT_RECEIVE_PATH = "m/86'/0'/0'/0", TAPROOT_CHANGE_PATH = "m/86'/0'/0'/1";
  function toXOnly(pubkey) {
    return pubkey.length === 32 ? pubkey : pubkey.subarray(1, 33);
  }
  function rootFromSeed(seedHex) {
    return bip32.fromSeed(import_buffer2.Buffer.from(seedHex, "hex"), network);
  }
  function p2trForInternalKey(internalPubkey) {
    return bitcoin.payments.p2tr({ internalPubkey, network });
  }
  function getTaprootXpubs(seedHex) {
    let root = rootFromSeed(seedHex);
    return [
      root.derivePath(TAPROOT_RECEIVE_PATH).neutered().toBase58(),
      root.derivePath(TAPROOT_CHANGE_PATH).neutered().toBase58()
    ];
  }
  function getTaprootAddresses(xpub, fromIndex, toIndex) {
    let node = bip32.fromBase58(xpub, network), addresses = [];
    for (let i = fromIndex; i <= toIndex; i++)
      addresses.push(p2trForInternalKey(toXOnly(node.derive(i).publicKey)).address);
    return addresses;
  }
  function validateAddress(address2) {
    try {
      return bitcoin.address.toOutputScript(address2, network), !0;
    } catch {
      return !1;
    }
  }
  function isTaprootAddress(address2) {
    try {
      let decoded = bitcoin.address.fromBech32(address2);
      return decoded.prefix === network.bech32 && decoded.version === 1 && decoded.data.length === 32;
    } catch {
      return !1;
    }
  }
  function checkScript(input, script2) {
    let expected = input.scriptPubKey;
    if (expected && expected.toLowerCase() !== script2.toString("hex"))
      throw new Error("scriptPubKey mismatch for " + input.txHash + ":" + input.index);
  }
  function checkAddress(input, address2) {
    let expected = input.address;
    if (expected && expected.toLowerCase() !== address2.toLowerCase())
      throw new Error("address mismatch for " + input.txHash + ":" + input.index);
  }
  function getTaprootAddressFromPublicKey(publicKeyHex) {
    return p2trForInternalKey(toXOnly(import_buffer2.Buffer.from(publicKeyHex, "hex"))).address;
  }
  function keyPairFromPrivateKey(privateKey) {
    return /^[0-9a-f]+$/i.test(privateKey) ? ECPair.fromPrivateKey(import_buffer2.Buffer.from(privateKey, "hex"), { compressed: !1, network }) : ECPair.fromWIF(privateKey, network);
  }
  function tapTweakSigner(signer, internalPubkey) {
    return signer.tweak(bitcoin.crypto.taggedHash("TapTweak", internalPubkey));
  }
  function signTransaction(data, keys) {
    let inputs = data.inputs, outputs = data.outputs, hasOpReturn = !!(data.ophex && data.ophex.length > 0), sequence = hasOpReturn ? 4294967295 : 4294967293, psbt = new bitcoin.Psbt({ network });
    data.locktime && data.locktime > 0 && psbt.setLocktime(data.locktime);
    let signers = inputs.map(function(input) {
      let base = { hash: input.txHash, index: input.index, sequence };
      if (input.segwit === "T") {
        let key = keys.taproot(input), payment = p2trForInternalKey(key.internalPubkey);
        return checkScript(input, payment.output), checkAddress(input, payment.address), psbt.addInput(Object.assign(base, {
          witnessUtxo: { script: payment.output, value: input.satoshis },
          tapInternalKey: key.internalPubkey
        })), key.signer;
      }
      let keyPair = keys.other(input);
      if (input.segwit === "P") {
        let payment = bitcoin.payments.p2sh({ redeem: bitcoin.payments.p2wpkh({ pubkey: keyPair.publicKey, network }), network });
        checkScript(input, payment.output), psbt.addInput(Object.assign(base, {
          witnessUtxo: { script: payment.output, value: input.satoshis },
          redeemScript: payment.redeem.output
        }));
      } else if (input.segwit === "D") {
        let payment = bitcoin.payments.p2wpkh({ pubkey: keyPair.publicKey, network });
        checkScript(input, payment.output), psbt.addInput(Object.assign(base, {
          witnessUtxo: { script: payment.output, value: input.satoshis }
        }));
      } else
        psbt.addInput(Object.assign(base, {
          nonWitnessUtxo: import_buffer2.Buffer.from(input.txHex, "hex")
        }));
      return keyPair;
    });
    hasOpReturn && psbt.addOutput({ script: bitcoin.payments.embed({ data: [import_buffer2.Buffer.from(data.ophex, "hex")] }).output, value: 0 }), outputs.forEach(function(output) {
      psbt.addOutput({ address: output.address, value: output.amount });
    }), signers.forEach(function(signer, i) {
      psbt.signInput(i, signer);
    }), psbt.finalizeAllInputs();
    let tx = psbt.extractTransaction();
    return [tx.getId(), tx.toHex()];
  }
  function buildTransaction(seedHex, data) {
    let root = null;
    return signTransaction(JSON.parse(data), {
      taproot: function(input) {
        root = root || rootFromSeed(seedHex);
        let node = root.derivePath(input.isChange ? TAPROOT_CHANGE_PATH : TAPROOT_RECEIVE_PATH).derive(input.bip39Index), internalPubkey = toXOnly(node.publicKey);
        return { internalPubkey, signer: tapTweakSigner(node, internalPubkey) };
      },
      other: function(input) {
        return ECPair.fromWIF(input.wif, network);
      }
    });
  }
  function buildTransactionWithPrivateKey(privateKey, data) {
    let keyPair = keyPairFromPrivateKey(privateKey), internalPubkey = toXOnly(keyPair.publicKey), tweaked = tapTweakSigner(keyPair, internalPubkey);
    return signTransaction(JSON.parse(data), {
      taproot: function() {
        return { internalPubkey, signer: tweaked };
      },
      other: function() {
        return keyPair;
      }
    });
  }
  var BIP322_SIGNATURE_PREFIX = "", OP_RETURN_SCRIPT = import_buffer2.Buffer.from([106]);
  function bip322MessageHash(message) {
    let tag = bitcoin.crypto.sha256(import_buffer2.Buffer.from("BIP0322-signed-message", "utf8"));
    return bitcoin.crypto.sha256(import_buffer2.Buffer.concat([tag, tag, import_buffer2.Buffer.from(message, "utf8")]));
  }
  function bip322ToSpend(scriptPubKey, message) {
    let tx = new bitcoin.Transaction();
    return tx.version = 0, tx.locktime = 0, tx.addInput(import_buffer2.Buffer.alloc(32, 0), 4294967295, 0, bitcoin.script.compile([bitcoin.opcodes.OP_0, bip322MessageHash(message)])), tx.addOutput(scriptPubKey, 0), tx;
  }
  function bip322ToSign(toSpend) {
    let tx = new bitcoin.Transaction();
    return tx.version = 0, tx.locktime = 0, tx.addInput(toSpend.getHash(), 0, 0), tx.addOutput(OP_RETURN_SCRIPT, 0), tx;
  }
  function varIntBuffer(n) {
    if (n < 253) return import_buffer2.Buffer.from([n]);
    if (n <= 65535) {
      let b2 = import_buffer2.Buffer.alloc(3);
      return b2[0] = 253, b2.writeUInt16LE(n, 1), b2;
    }
    let b = import_buffer2.Buffer.alloc(5);
    return b[0] = 254, b.writeUInt32LE(n, 1), b;
  }
  function encodeWitness(stack) {
    let parts = [varIntBuffer(stack.length)];
    return stack.forEach(function(item) {
      parts.push(varIntBuffer(item.length), item);
    }), import_buffer2.Buffer.concat(parts);
  }
  function decodeWitness(buf) {
    let pos = 0;
    function readVarInt() {
      if (pos >= buf.length) throw new Error("truncated");
      let first = buf[pos++];
      if (first < 253) return first;
      if (first === 255) throw new Error("var-int too large");
      let size = first === 253 ? 2 : 4;
      if (pos + size > buf.length) throw new Error("truncated");
      let n = size === 2 ? buf.readUInt16LE(pos) : buf.readUInt32LE(pos);
      if (pos += size, size === 2 && n < 253 || size === 4 && n <= 65535) throw new Error("non-canonical var-int");
      return n;
    }
    let count = readVarInt(), stack = [];
    for (let i = 0; i < count; i++) {
      let len = readVarInt();
      if (pos + len > buf.length) throw new Error("truncated");
      stack.push(buf.subarray(pos, pos + len)), pos += len;
    }
    if (pos !== buf.length) throw new Error("trailing bytes");
    return stack;
  }
  function decodeBase64Strict(text) {
    if (text.length === 0 || text.length % 4 !== 0 || !/^[A-Za-z0-9+/]+={0,2}$/.test(text)) return null;
    let buf = import_buffer2.Buffer.from(text, "base64");
    return buf.toString("base64") === text ? buf : null;
  }
  function scriptType(script2) {
    return script2.length === 34 && script2[0] === 81 && script2[1] === 32 ? "p2tr" : script2.length === 22 && script2[0] === 0 && script2[1] === 20 ? "p2wpkh" : script2.length === 34 && script2[0] === 0 && script2[1] === 32 ? "p2wsh" : script2.length === 23 && script2[0] === 169 && script2[1] === 20 && script2[22] === 135 ? "p2sh" : script2.length === 25 && script2[0] === 118 && script2[1] === 169 && script2[2] === 20 && script2[23] === 136 && script2[24] === 172 ? "p2pkh" : "other";
  }
  function checkEcdsa(sighash, signatureWithType, pubkey) {
    let decoded;
    try {
      decoded = bitcoin.script.signature.decode(signatureWithType);
    } catch {
      return !1;
    }
    return decoded.hashType !== bitcoin.Transaction.SIGHASH_ALL || !ecc.isPoint(pubkey) ? !1 : ecc.verify(sighash(decoded.hashType), pubkey, decoded.signature, !0);
  }
  function bip322VerifyInput(toSign, script2, type) {
    let input = toSign.ins[0], witness = input.witness || [];
    if (type === "p2tr") {
      if (input.script.length !== 0 || witness.length === 0) return "invalid";
      let last = witness[witness.length - 1];
      if (witness.length >= 2 && last.length > 0 && last[0] === 80 || witness.length !== 1) return "unsupported";
      let sig = witness[0], hashType;
      if (sig.length === 64)
        hashType = bitcoin.Transaction.SIGHASH_DEFAULT;
      else if (sig.length === 65 && sig[64] === bitcoin.Transaction.SIGHASH_ALL)
        hashType = bitcoin.Transaction.SIGHASH_ALL;
      else
        return "invalid";
      let hash = toSign.hashForWitnessV1(0, [script2], [0], hashType);
      return ecc.verifySchnorr(hash, script2.subarray(2, 34), sig.subarray(0, 64)) ? "valid" : "invalid";
    }
    if (type === "p2wpkh" || type === "p2sh") {
      let program;
      if (type === "p2sh") {
        let chunks = bitcoin.script.decompile(input.script);
        if (!chunks || chunks.length === 0 || !bitcoin.script.compile(chunks).equals(input.script)) return "invalid";
        let redeem = chunks[chunks.length - 1];
        if (!import_buffer2.Buffer.isBuffer(redeem) || !bitcoin.crypto.hash160(redeem).equals(script2.subarray(2, 22))) return "invalid";
        if (chunks.length !== 1 || redeem.length !== 22 || redeem[0] !== 0 || redeem[1] !== 20) return "unsupported";
        program = redeem.subarray(2);
      } else {
        if (input.script.length !== 0) return "invalid";
        program = script2.subarray(2, 22);
      }
      if (witness.length !== 2 || witness[1].length !== 33 || !bitcoin.crypto.hash160(witness[1]).equals(program)) return "invalid";
      let scriptCode = bitcoin.payments.p2pkh({ hash: program }).output;
      return checkEcdsa(function(hashType) {
        return toSign.hashForWitnessV0(0, scriptCode, 0, hashType);
      }, witness[0], witness[1]) ? "valid" : "invalid";
    }
    if (type === "p2pkh") {
      if (witness.length !== 0) return "invalid";
      let chunks = bitcoin.script.decompile(input.script);
      return !chunks || chunks.length !== 2 || !import_buffer2.Buffer.isBuffer(chunks[0]) || !import_buffer2.Buffer.isBuffer(chunks[1]) || !bitcoin.script.compile(chunks).equals(input.script) || !bitcoin.crypto.hash160(chunks[1]).equals(script2.subarray(3, 23)) ? "invalid" : checkEcdsa(function(hashType) {
        return toSign.hashForSignature(0, script2, hashType);
      }, chunks[0], chunks[1]) ? "valid" : "invalid";
    }
    return type === "p2wsh" && (input.script.length !== 0 || witness.length === 0 || !bitcoin.crypto.sha256(witness[witness.length - 1]).equals(script2.subarray(2, 34))) ? "invalid" : "unsupported";
  }
  function bip322SignTaproot(keyPair, expectedAddress, message) {
    let internalPubkey = toXOnly(keyPair.publicKey), payment = p2trForInternalKey(internalPubkey);
    if (payment.address !== expectedAddress)
      throw new Error("address mismatch");
    let hash = bip322ToSign(bip322ToSpend(payment.output, message)).hashForWitnessV1(0, [payment.output], [0], bitcoin.Transaction.SIGHASH_DEFAULT), signature = import_buffer2.Buffer.from(tapTweakSigner(keyPair, internalPubkey).signSchnorr(hash));
    if (!ecc.verifySchnorr(hash, payment.output.subarray(2, 34), signature))
      throw new Error("signature self-check failed");
    return BIP322_SIGNATURE_PREFIX + encodeWitness([signature]).toString("base64");
  }
  function signMessageBip322(seedHex, isChange, index, address2, message) {
    if (!Number.isInteger(index) || index < 0 || index >= 2147483648)
      throw new Error("bad index");
    let node = rootFromSeed(seedHex).derivePath(isChange ? TAPROOT_CHANGE_PATH : TAPROOT_RECEIVE_PATH).derive(index);
    return bip322SignTaproot(node, address2, String(message));
  }
  function signMessageBip322WithPrivateKey(privateKey, address2, message) {
    return bip322SignTaproot(keyPairFromPrivateKey(privateKey), address2, String(message));
  }
  function verifyMessageBip322(address2, message, signature) {
    let script2;
    try {
      script2 = bitcoin.address.toOutputScript(String(address2), network);
    } catch {
      return "invalid";
    }
    let type = scriptType(script2), text = String(signature).replace(/\s+/g, ""), variant = "smp";
    if (text.startsWith("smp"))
      text = text.slice(3);
    else if (text.startsWith("ful"))
      variant = "ful", text = text.slice(3);
    else if (text.startsWith("pof"))
      return "unsupported";
    let bytes = decodeBase64Strict(text);
    if (!bytes) return "invalid";
    let toSpend = bip322ToSpend(script2, String(message)), toSign;
    if (variant === "smp") {
      if (type !== "p2tr" && type !== "p2wpkh" && type !== "p2wsh") return "invalid";
      let witness;
      try {
        witness = decodeWitness(bytes);
      } catch {
        return "invalid";
      }
      toSign = bip322ToSign(toSpend), toSign.setWitness(0, witness);
    } else {
      try {
        toSign = bitcoin.Transaction.fromBuffer(bytes);
      } catch {
        return "invalid";
      }
      if (toSign.ins.length !== 1 || toSign.outs.length !== 1 || !toSign.ins[0].hash.equals(toSpend.getHash()) || toSign.ins[0].index !== 0 || toSign.outs[0].value !== 0 || !toSign.outs[0].script.equals(OP_RETURN_SCRIPT)) return "invalid";
      if (toSign.version !== 0 && toSign.version !== 2) return "unsupported";
    }
    return bip322VerifyInput(toSign, script2, type);
  }
  function bip322Hashes(address2, message) {
    let toSpend = bip322ToSpend(bitcoin.address.toOutputScript(String(address2), network), String(message));
    return [bip322MessageHash(String(message)).toString("hex"), toSpend.getId(), bip322ToSign(toSpend).getId()];
  }
  return __toCommonJS(index_exports);
})();
/*! Bundled license information:

ieee754/index.js:
  (*! ieee754. BSD-3-Clause License. Feross Aboukhadijeh <https://feross.org/opensource> *)

buffer/index.js:
  (*!
   * The buffer module from node.js, for the browser.
   *
   * @author   Feross Aboukhadijeh <https://feross.org>
   * @license  MIT
   *)

@noble/hashes/utils.js:
  (*! noble-hashes - MIT License (c) 2022 Paul Miller (paulmillr.com) *)

safe-buffer/index.js:
  (*! safe-buffer. MIT License. Feross Aboukhadijeh <https://feross.org/opensource> *)

@noble/curves/utils.js:
@noble/curves/abstract/modular.js:
@noble/curves/abstract/curve.js:
@noble/curves/abstract/weierstrass.js:
@noble/curves/_shortw_utils.js:
@noble/curves/secp256k1.js:
  (*! noble-curves - MIT License (c) 2022 Paul Miller (paulmillr.com) *)

@scure/base/lib/index.js:
  (*! scure-base - MIT License (c) 2022 Paul Miller (paulmillr.com) *)
*/
