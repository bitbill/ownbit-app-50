// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.chain.evm

import io.ownbit.core.crypto.hash.Hashes
import org.bouncycastle.asn1.x9.X9IntegerConverter
import org.bouncycastle.crypto.ec.CustomNamedCurves
import org.bouncycastle.crypto.params.ECDomainParameters
import org.bouncycastle.math.ec.ECAlgorithms
import org.bouncycastle.math.ec.ECPoint
import org.bouncycastle.math.ec.FixedPointCombMultiplier
import org.bouncycastle.math.ec.custom.sec.SecP256K1Curve
import java.math.BigInteger

/**
 * Read-only inspection of signed EVM transactions and signatures: RLP decoding, transaction hash, and secp256k1
 * public-key recovery. **Nothing here signs** — signing always happens in the JS bundles. The engine
 * uses this module to verify what the bundle produced (fields, chain id, sender) before anything is broadcast or
 * handed to a dApp, and to verify message signatures.
 */
object EvmTxCodec {

    // ---------------------------------------------------------------------------------------------------------------
    // RLP
    // ---------------------------------------------------------------------------------------------------------------

    /** A decoded RLP item; [encoded] is its exact encoding in the source bytes. */
    sealed class RlpItem(val encoded: ByteArray) {
        class Bytes(val bytes: ByteArray, encoded: ByteArray) : RlpItem(encoded)
        class Items(val items: List<RlpItem>, encoded: ByteArray) : RlpItem(encoded)
    }

    /** Thrown for malformed RLP / transaction bytes. */
    class DecodeException(message: String) : IllegalArgumentException(message)

    /** Decodes one RLP item that must span all of [input]. */
    fun rlpDecode(input: ByteArray): RlpItem {
        val (item, end) = decodeAt(input, 0)
        if (end != input.size) throw DecodeException("trailing bytes after RLP item")
        return item
    }

    private fun decodeAt(src: ByteArray, pos: Int): Pair<RlpItem, Int> {
        if (pos >= src.size) throw DecodeException("unexpected end of RLP")
        val prefix = src[pos].toInt() and 0xff
        return when {
            prefix < 0x80 -> RlpItem.Bytes(byteArrayOf(src[pos]), src.copyOfRange(pos, pos + 1)) to pos + 1
            prefix <= 0xb7 -> {
                val len = prefix - 0x80
                val start = pos + 1
                checkRange(src, start, len)
                val bytes = src.copyOfRange(start, start + len)
                if (len == 1 && (bytes[0].toInt() and 0xff) < 0x80) throw DecodeException("non-canonical single byte")
                RlpItem.Bytes(bytes, src.copyOfRange(pos, start + len)) to start + len
            }
            prefix <= 0xbf -> {
                val lenOfLen = prefix - 0xb7
                val len = readLength(src, pos + 1, lenOfLen)
                val start = pos + 1 + lenOfLen
                checkRange(src, start, len)
                RlpItem.Bytes(src.copyOfRange(start, start + len), src.copyOfRange(pos, start + len)) to start + len
            }
            else -> {
                val (payloadStart, len) = if (prefix <= 0xf7) {
                    (pos + 1) to (prefix - 0xc0)
                } else {
                    val lenOfLen = prefix - 0xf7
                    (pos + 1 + lenOfLen) to readLength(src, pos + 1, lenOfLen)
                }
                checkRange(src, payloadStart, len)
                val items = ArrayList<RlpItem>()
                var p = payloadStart
                val end = payloadStart + len
                while (p < end) {
                    val (item, next) = decodeAt(src, p)
                    items += item
                    p = next
                }
                if (p != end) throw DecodeException("list payload overrun")
                RlpItem.Items(items, src.copyOfRange(pos, end)) to end
            }
        }
    }

    private fun readLength(src: ByteArray, pos: Int, lenOfLen: Int): Int {
        if (lenOfLen < 1 || lenOfLen > 4) throw DecodeException("unsupported RLP length")
        checkRange(src, pos, lenOfLen)
        var len = 0L
        for (i in 0 until lenOfLen) len = (len shl 8) or (src[pos + i].toLong() and 0xff)
        if (len > Int.MAX_VALUE) throw DecodeException("RLP length too large")
        return len.toInt()
    }

    private fun checkRange(src: ByteArray, start: Int, len: Int) {
        if (len < 0 || start < 0 || start.toLong() + len > src.size) throw DecodeException("RLP item exceeds input")
    }

    /** RLP encoding of a byte string. */
    fun rlpEncodeBytes(bytes: ByteArray): ByteArray = when {
        bytes.size == 1 && (bytes[0].toInt() and 0xff) < 0x80 -> bytes.copyOf()
        else -> lengthPrefix(bytes.size, 0x80) + bytes
    }

    /** RLP encoding of a list whose items are already encoded. */
    fun rlpEncodeList(encodedItems: List<ByteArray>): ByteArray {
        val payload = encodedItems.fold(ByteArray(0)) { acc, b -> acc + b }
        return lengthPrefix(payload.size, 0xc0) + payload
    }

    /** RLP encoding of an unsigned integer (minimal big-endian, 0 = empty string). */
    fun rlpEncodeUInt(value: BigInteger): ByteArray = rlpEncodeBytes(unsignedBytes(value))

    private fun lengthPrefix(len: Int, offset: Int): ByteArray =
        if (len <= 55) {
            byteArrayOf((offset + len).toByte())
        } else {
            val lenBytes = unsignedBytes(BigInteger.valueOf(len.toLong()))
            byteArrayOf((offset + 55 + lenBytes.size).toByte()) + lenBytes
        }

    private fun unsignedBytes(value: BigInteger): ByteArray {
        require(value.signum() >= 0) { "negative" }
        if (value.signum() == 0) return ByteArray(0)
        val raw = value.toByteArray()
        return if (raw[0].toInt() == 0) raw.copyOfRange(1, raw.size) else raw
    }

    // ---------------------------------------------------------------------------------------------------------------
    // Transactions
    // ---------------------------------------------------------------------------------------------------------------

    /**
     * A decoded signed transaction.
     *
     * @property type 0 = legacy (EIP-155 or pre-155), 1 = EIP-2930, 2 = EIP-1559.
     * @property chainId the chain id (legacy: from `v`; `null` for a pre-EIP-155 signature).
     * @property gasPrice legacy / type-1 gas price, or the type-2 `maxFeePerGas`.
     * @property maxPriorityFeePerGas type-2 priority fee, `null` otherwise.
     * @property to lower-case `0x` recipient, `null` for contract creation.
     * @property hash `0x` keccak-256 of the raw bytes (the transaction hash).
     * @property from checksummed sender recovered from the signature, `null` if recovery failed.
     */
    data class DecodedTx(
        val type: Int,
        val chainId: Long?,
        val nonce: BigInteger,
        val gasPrice: BigInteger,
        val maxPriorityFeePerGas: BigInteger?,
        val gasLimit: BigInteger,
        val to: String?,
        val value: BigInteger,
        val data: ByteArray,
        val hash: String,
        val from: String?,
    ) {
        /** `0x` lower-case calldata (`0x` when empty). */
        val dataHex: String get() = EvmHex.encode0x(data)

        override fun equals(other: Any?): Boolean =
            other is DecodedTx && other.hash == hash && other.from == from

        override fun hashCode(): Int = hash.hashCode()
    }

    /** Decodes a `0x…` signed transaction (legacy / type 1 / type 2) and recovers its sender. */
    fun decodeSigned(rawHex: String): DecodedTx {
        val raw = EvmHex.decode(rawHex) ?: throw DecodeException("raw transaction is not hex")
        if (raw.isEmpty()) throw DecodeException("empty transaction")
        val hash = EvmHex.encode0x(Hashes.keccak256(raw))
        val first = raw[0].toInt() and 0xff
        return when {
            first >= 0xc0 -> decodeLegacy(raw, hash)
            first == 0x02 -> decodeTyped(raw, hash, type = 2)
            first == 0x01 -> decodeTyped(raw, hash, type = 1)
            else -> throw DecodeException("unsupported transaction type $first")
        }
    }

    private fun decodeLegacy(raw: ByteArray, hash: String): DecodedTx {
        val list = rlpDecode(raw) as? RlpItem.Items ?: throw DecodeException("legacy tx is not a list")
        val f = list.items
        if (f.size != 9) throw DecodeException("legacy tx must have 9 fields")
        val v = uint(f[6])
        val r = uint(f[7])
        val s = uint(f[8])
        val chainId: Long?
        val recId: Int
        val payload: ByteArray
        if (v >= BigInteger.valueOf(35)) {
            val cid = v.subtract(BigInteger.valueOf(35)).shiftRight(1)
            chainId = cid.toLong()
            recId = v.subtract(BigInteger.valueOf(35)).subtract(cid.shiftLeft(1)).toInt()
            payload = rlpEncodeList(f.subList(0, 6).map { it.encoded } + rlpEncodeUInt(cid) + rlpEncodeUInt(BigInteger.ZERO) + rlpEncodeUInt(BigInteger.ZERO))
        } else {
            chainId = null
            recId = v.toInt() - 27
            payload = rlpEncodeList(f.subList(0, 6).map { it.encoded })
        }
        val from = recoverAddress(Hashes.keccak256(payload), recId, r, s)
        return DecodedTx(
            type = 0,
            chainId = chainId,
            nonce = uint(f[0]),
            gasPrice = uint(f[1]),
            maxPriorityFeePerGas = null,
            gasLimit = uint(f[2]),
            to = address(f[3]),
            value = uint(f[4]),
            data = bytes(f[5]),
            hash = hash,
            from = from,
        )
    }

    private fun decodeTyped(raw: ByteArray, hash: String, type: Int): DecodedTx {
        val body = raw.copyOfRange(1, raw.size)
        val list = rlpDecode(body) as? RlpItem.Items ?: throw DecodeException("typed tx is not a list")
        val f = list.items
        val expected = if (type == 2) 12 else 11
        if (f.size != expected) throw DecodeException("type-$type tx must have $expected fields")
        val unsignedCount = expected - 3
        val payload = byteArrayOf(type.toByte()) + rlpEncodeList(f.subList(0, unsignedCount).map { it.encoded })
        val yParity = uint(f[unsignedCount]).toInt()
        val r = uint(f[unsignedCount + 1])
        val s = uint(f[unsignedCount + 2])
        val from = recoverAddress(Hashes.keccak256(payload), yParity, r, s)
        return if (type == 2) {
            DecodedTx(
                type = 2,
                chainId = uint(f[0]).toLong(),
                nonce = uint(f[1]),
                gasPrice = uint(f[3]),
                maxPriorityFeePerGas = uint(f[2]),
                gasLimit = uint(f[4]),
                to = address(f[5]),
                value = uint(f[6]),
                data = bytes(f[7]),
                hash = hash,
                from = from,
            )
        } else {
            DecodedTx(
                type = 1,
                chainId = uint(f[0]).toLong(),
                nonce = uint(f[1]),
                gasPrice = uint(f[2]),
                maxPriorityFeePerGas = null,
                gasLimit = uint(f[3]),
                to = address(f[4]),
                value = uint(f[5]),
                data = bytes(f[6]),
                hash = hash,
                from = from,
            )
        }
    }

    // ---------------------------------------------------------------------------------------------------------------
    // Unsigned transactions (public protocol: the exact bytes an `eth-sign-request` asks to sign)
    // ---------------------------------------------------------------------------------------------------------------

    /**
     * A decoded **unsigned** transaction: the `signData` of an `eth-sign-request` (dataType 1 legacy RLP, dataType 4
     * typed transaction), read independently of the engine that will sign it.
     *
     * @property type 0 = legacy EIP-155, 1 = EIP-2930, 2 = EIP-1559.
     * @property chainId always > 0 (pre-EIP-155 transactions are refused).
     * @property gasPrice legacy / type-1 gas price, `null` for type 2.
     * @property maxPriorityFeePerGas / [maxFeePerGas] type-2 fees, `null` otherwise.
     * @property to lower-case `0x` recipient, `null` for contract creation.
     * @property accessListEntries number of access-list entries (types 1 and 2; 0 for legacy).
     * @property signingHash keccak-256 of the exact input bytes: the digest the signature commits to (ethers
     *   `unsignedHash` equals it exactly when the input is canonical, which this decoder requires).
     */
    class UnsignedEvmTx(
        val type: Int,
        val chainId: Long,
        val nonce: BigInteger,
        val gasPrice: BigInteger?,
        val maxPriorityFeePerGas: BigInteger?,
        val maxFeePerGas: BigInteger?,
        val gasLimit: BigInteger,
        val to: String?,
        val value: BigInteger,
        val data: ByteArray,
        val accessListEntries: Int,
        val signingHash: ByteArray,
    ) {
        /** `0x` lower-case calldata (`0x` when empty). */
        val dataHex: String get() = EvmHex.encode0x(data)

        /** The fee per gas the transaction allows: `maxFeePerGas` (type 2) or `gasPrice`. */
        val feePerGas: BigInteger get() = maxFeePerGas ?: gasPrice ?: BigInteger.ZERO

        override fun toString(): String = "UnsignedEvmTx(type=$type, chainId=$chainId, data=${data.size} bytes)"
    }

    /**
     * Decodes the unsigned transaction [bytes] (types 0 / 1 / 2) with **strict** rules, so that what Kotlin reads is
     * exactly what the signature commits to:
     * - canonical RLP only (every length minimal, no single byte below `0x80` wrapped, no trailing bytes) — checked by
     *   re-encoding the decoded tree and comparing it with [bytes];
     * - integers without leading zero bytes (`0` = the empty string), at most 32 bytes; `chainId` > 0 and < 2⁶³;
     * - `to` empty (contract creation) or 20 bytes; access list = `[[address(20), [slot(32)…]]…]`;
     * - legacy: exactly the 9 EIP-155 fields `[nonce, gasPrice, gas, to, value, data, chainId, 0, 0]` (the 6-field
     *   pre-EIP-155 form has no chain id and is refused);
     * - type 1: 8 fields, type 2: 9 fields (a signed typed transaction has 3 more and is refused);
     * - every other first byte (blob type 3, EIP-7702 type 4, unknown) is refused.
     *
     * @throws DecodeException for anything else.
     */
    fun decodeUnsigned(bytes: ByteArray): UnsignedEvmTx {
        if (bytes.isEmpty()) throw DecodeException("empty transaction")
        val first = bytes[0].toInt() and 0xff
        val (type, body) = when {
            first >= 0xc0 -> 0 to bytes
            first == 0x01 || first == 0x02 -> first to bytes.copyOfRange(1, bytes.size)
            else -> throw DecodeException("unsupported transaction type $first")
        }
        val list = rlpDecode(body) as? RlpItem.Items ?: throw DecodeException("transaction is not an RLP list")
        if (!canonicalRlp(list).contentEquals(body)) throw DecodeException("non-canonical RLP")
        val f = list.items
        val hash = Hashes.keccak256(bytes)
        return when (type) {
            0 -> {
                when (f.size) {
                    9 -> Unit
                    6 -> throw DecodeException("pre-EIP-155 transaction without chain id")
                    else -> throw DecodeException("legacy transaction must have 9 fields")
                }
                if (strictUint(f[7]).signum() != 0 || strictUint(f[8]).signum() != 0) {
                    throw DecodeException("legacy transaction is already signed")
                }
                UnsignedEvmTx(
                    type = 0,
                    chainId = chainId(f[6]),
                    nonce = strictUint(f[0]),
                    gasPrice = strictUint(f[1]),
                    maxPriorityFeePerGas = null,
                    maxFeePerGas = null,
                    gasLimit = strictUint(f[2]),
                    to = address(f[3]),
                    value = strictUint(f[4]),
                    data = bytes(f[5]),
                    accessListEntries = 0,
                    signingHash = hash,
                )
            }
            1 -> {
                if (f.size != 8) throw DecodeException(if (f.size == 11) "type-1 transaction is already signed" else "type-1 transaction must have 8 fields")
                UnsignedEvmTx(
                    type = 1,
                    chainId = chainId(f[0]),
                    nonce = strictUint(f[1]),
                    gasPrice = strictUint(f[2]),
                    maxPriorityFeePerGas = null,
                    maxFeePerGas = null,
                    gasLimit = strictUint(f[3]),
                    to = address(f[4]),
                    value = strictUint(f[5]),
                    data = bytes(f[6]),
                    accessListEntries = accessList(f[7]),
                    signingHash = hash,
                )
            }
            else -> {
                if (f.size != 9) throw DecodeException(if (f.size == 12) "type-2 transaction is already signed" else "type-2 transaction must have 9 fields")
                UnsignedEvmTx(
                    type = 2,
                    chainId = chainId(f[0]),
                    nonce = strictUint(f[1]),
                    gasPrice = null,
                    maxPriorityFeePerGas = strictUint(f[2]),
                    maxFeePerGas = strictUint(f[3]),
                    gasLimit = strictUint(f[4]),
                    to = address(f[5]),
                    value = strictUint(f[6]),
                    data = bytes(f[7]),
                    accessListEntries = accessList(f[8]),
                    signingHash = hash,
                )
            }
        }
    }

    /** The canonical encoding of a decoded tree (equal to the source exactly when the source was canonical). */
    private fun canonicalRlp(item: RlpItem): ByteArray = when (item) {
        is RlpItem.Bytes -> rlpEncodeBytes(item.bytes)
        is RlpItem.Items -> rlpEncodeList(item.items.map(::canonicalRlp))
    }

    /** A canonical unsigned integer: no leading zero byte, at most 256 bits. */
    private fun strictUint(item: RlpItem): BigInteger {
        val b = bytes(item)
        if (b.isNotEmpty() && b[0].toInt() == 0) throw DecodeException("integer with a leading zero byte")
        if (b.size > 32) throw DecodeException("integer wider than 256 bits")
        return BigInteger(1, b)
    }

    private fun chainId(item: RlpItem): Long {
        val id = strictUint(item)
        if (id.signum() <= 0) throw DecodeException("chain id must be positive")
        // < 2^63 (fits a Long, as documented): bitLength 63 is still a positive Long.
        if (id.bitLength() >= Long.SIZE_BITS) throw DecodeException("chain id too large")
        return id.toLong()
    }

    /** Validates an EIP-2930 access list and returns its entry count. */
    private fun accessList(item: RlpItem): Int {
        val entries = (item as? RlpItem.Items)?.items ?: throw DecodeException("access list must be a list")
        for (entry in entries) {
            val pair = (entry as? RlpItem.Items)?.items ?: throw DecodeException("access-list entry must be a list")
            if (pair.size != 2 || bytes(pair[0]).size != 20) throw DecodeException("invalid access-list entry")
            val slots = (pair[1] as? RlpItem.Items)?.items ?: throw DecodeException("access-list slots must be a list")
            if (slots.any { bytes(it).size != 32 }) throw DecodeException("access-list slot must be 32 bytes")
        }
        return entries.size
    }

    private fun bytes(item: RlpItem): ByteArray =
        (item as? RlpItem.Bytes)?.bytes ?: throw DecodeException("expected a byte string")

    private fun uint(item: RlpItem): BigInteger = BigInteger(1, bytes(item))

    private fun address(item: RlpItem): String? {
        val b = bytes(item)
        if (b.isEmpty()) return null
        if (b.size != 20) throw DecodeException("address must be 20 bytes")
        return EvmHex.encode0x(b)
    }

    // ---------------------------------------------------------------------------------------------------------------
    // secp256k1 recovery
    // ---------------------------------------------------------------------------------------------------------------

    private val CURVE_PARAMS = CustomNamedCurves.getByName("secp256k1")
    private val CURVE = ECDomainParameters(CURVE_PARAMS.curve, CURVE_PARAMS.g, CURVE_PARAMS.n, CURVE_PARAMS.h)

    /**
     * Recovers the checksummed address that produced (r, s) with recovery id [recId] (0/1) over the 32-byte
     * [digest] (SEC 1 v2 §4.1.6). `null` when the signature is invalid.
     */
    fun recoverAddress(digest: ByteArray, recId: Int, r: BigInteger, s: BigInteger): String? {
        val pub = recoverPublicKey(digest, recId, r, s) ?: return null
        return publicKeyToAddress(pub)
    }

    /** Uncompressed (65-byte, `04`-prefixed) public key recovered from a signature, or `null`. */
    fun recoverPublicKey(digest: ByteArray, recId: Int, r: BigInteger, s: BigInteger): ByteArray? {
        if (digest.size != 32 || recId !in 0..3) return null
        val n = CURVE.n
        if (r.signum() <= 0 || r >= n || s.signum() <= 0 || s >= n) return null
        val x = r.add(BigInteger.valueOf((recId / 2).toLong()).multiply(n))
        if (x >= SecP256K1Curve.q) return null
        val rPoint = decompressKey(x, (recId and 1) == 1) ?: return null
        if (!rPoint.multiply(n).isInfinity) return null
        val e = BigInteger(1, digest)
        val eInv = BigInteger.ZERO.subtract(e).mod(n)
        val rInv = r.modInverse(n)
        val srInv = rInv.multiply(s).mod(n)
        val eInvrInv = rInv.multiply(eInv).mod(n)
        val q = ECAlgorithms.sumOfTwoMultiplies(CURVE.g, eInvrInv, rPoint, srInv).normalize()
        if (q.isInfinity) return null
        return q.getEncoded(false)
    }

    private fun decompressKey(x: BigInteger, yBit: Boolean): ECPoint? = try {
        val converter = X9IntegerConverter()
        val enc = converter.integerToBytes(x, 1 + converter.getByteLength(CURVE.curve))
        enc[0] = if (yBit) 0x03 else 0x02
        CURVE.curve.decodePoint(enc)
    } catch (e: IllegalArgumentException) {
        null
    }

    /**
     * Checksummed address of a secp256k1 private key (64 hex digits, `0x` optional) — the same 20 bytes TRON writes
     * after `41`. `null` when [privateKeyHex] is not a valid key. Native (no bundle); the key is a secret: the caller
     * keeps it local and never logs it.
     */
    fun addressOfPrivateKey(privateKeyHex: String): String? {
        val hex = privateKeyHex.trim().removePrefix("0x").removePrefix("0X")
        if (hex.length != 64 || !hex.all { Character.digit(it, 16) >= 0 }) return null
        val d = BigInteger(hex, 16)
        if (d.signum() <= 0 || d >= CURVE.n) return null
        return publicKeyToAddress(FixedPointCombMultiplier().multiply(CURVE.g, d).normalize().getEncoded(false))
    }

    /** Checksummed address of an uncompressed public key (65 bytes with `04`, or 64 raw bytes). */
    fun publicKeyToAddress(publicKey: ByteArray): String {
        val raw = when (publicKey.size) {
            65 -> publicKey.copyOfRange(1, 65)
            64 -> publicKey
            else -> throw IllegalArgumentException("public key must be 64 or 65 bytes")
        }
        val hash = Hashes.keccak256(raw)
        return EvmHex.toChecksumAddress(EvmHex.encode0x(hash.copyOfRange(12, 32)))
    }

    /**
     * Recovers the signer of a 65-byte `r‖s‖v` signature (`v` 27/28 or 0/1, hex with `0x`) over [digest].
     */
    fun recoverSigner(digest: ByteArray, signatureHex: String): String? {
        val sig = EvmHex.decode(signatureHex) ?: return null
        if (sig.size != 65) return null
        val r = BigInteger(1, sig.copyOfRange(0, 32))
        val s = BigInteger(1, sig.copyOfRange(32, 64))
        var v = sig[64].toInt() and 0xff
        if (v >= 27) v -= 27
        return recoverAddress(digest, v, r, s)
    }

    /** EIP-191 `personal_sign` digest of raw message bytes: keccak("\u0019Ethereum Signed Message:\n" + len + msg). */
    fun personalMessageDigest(message: ByteArray): ByteArray {
        val prefix = "\u0019Ethereum Signed Message:\n${message.size}".toByteArray(Charsets.UTF_8)
        return Hashes.keccak256(prefix + message)
    }
}
