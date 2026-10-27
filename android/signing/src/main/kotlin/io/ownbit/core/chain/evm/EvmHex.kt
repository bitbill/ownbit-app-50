// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.chain.evm

import io.ownbit.core.crypto.hash.Hashes
import io.ownbit.core.model.coin.ErcType
import java.math.BigDecimal
import java.math.BigInteger
import java.math.RoundingMode

/**
 * Hex / address / amount helpers used by the EVM engine, each mirroring the iOS helper named in its KDoc.
 */
object EvmHex {

    /** iOS `DEPLOY_CONTRACT` (`EthereumJSBridge.swift`): a destination of `0x0` means "contract creation" (`to = null`). */
    const val DEPLOY_CONTRACT: String = "0x0"

    /** 20-byte zero address. */
    const val ZERO_ADDRESS: String = "0x0000000000000000000000000000000000000000"

    private val HEX_BODY = Regex("^[0-9a-fA-F]+$")
    private val ADDRESS_BODY = Regex("^[0-9a-fA-F]{40}$")

    /**
     * iOS `ETHTransactionBuilder.validate(customData:)`: an optional `0x` prefix, at least one hex digit, an even
     * total length (after adding the prefix) and nothing else.
     */
    fun isValidCustomData(customData: String): Boolean {
        var data = customData.lowercase()
        if (!data.startsWith("0x")) data = "0x$data"
        if (data.length % 2 != 0) return false
        val body = data.substring(2)
        return body.isNotEmpty() && HEX_BODY.matches(body)
    }

    /**
     * The calldata string handed to the JS bundles (iOS `customData0x` in `EthereumJSBridge.buildTransaction` /
     * `EthereumExtJSBridge.buildEthTransaction`): lower-cased, `0x` added when missing, `""` when empty.
     * `"0x"` alone is treated as empty.
     */
    fun normalizeCalldata(customData: String?): String {
        val data = customData?.trim()?.lowercase().orEmpty()
        if (data.isEmpty() || data == "0x") return ""
        return if (data.startsWith("0x")) data else "0x$data"
    }

    /** iOS `NSDecimalNumber.toHexStringWith0x()`: `0x` + lower-case hex without leading zeros (`0` → `0x0`). */
    fun toHex0x(value: BigInteger): String {
        require(value.signum() >= 0) { "negative quantity" }
        return "0x" + value.toString(16)
    }

    /**
     * iOS `String.hexStringToDecimal()`: `0x` optional, empty → 0. Returns `null` for non-hex input (iOS would
     * silently produce garbage).
     */
    fun parseHexQuantity(hex: String?): BigInteger? {
        val body = hex?.trim()?.removePrefix("0x")?.removePrefix("0X") ?: return BigInteger.ZERO
        if (body.isEmpty()) return BigInteger.ZERO
        if (!HEX_BODY.matches(body)) return null
        return BigInteger(body, 16)
    }

    /** Removes a leading `0x` / `0X`. */
    fun strip0x(hex: String): String = if (hex.startsWith("0x") || hex.startsWith("0X")) hex.substring(2) else hex

    /** Lower-case hex of [bytes] with `0x`. */
    fun encode0x(bytes: ByteArray): String = "0x" + bytes.joinToString("") { "%02x".format(it.toInt() and 0xff) }

    /** Decodes `0x`-optional hex; `null` for odd length / non-hex. */
    fun decode(hex: String): ByteArray? {
        val body = strip0x(hex.trim())
        if (body.length % 2 != 0) return null
        if (body.isNotEmpty() && !HEX_BODY.matches(body)) return null
        return ByteArray(body.length / 2) { i -> body.substring(i * 2, i * 2 + 2).toInt(16).toByte() }
    }

    /**
     * web3 `isAddress` as used by iOS `EthereumJSBridge.validateAddress` (all EVM `checkAddress`), restricted to the
     * `0x`-prefixed form the engine passes to the bundles: 40 hex digits; mixed case must be a valid EIP-55 checksum.
     */
    fun isAddress(address: String): Boolean {
        if (!address.startsWith("0x") && !address.startsWith("0X")) return false
        val body = address.substring(2)
        if (!ADDRESS_BODY.matches(body)) return false
        if (body == body.lowercase() || body == body.uppercase()) return true
        return toChecksumAddress(address) == "0x$body"
    }

    /** EIP-55 checksum form of a 20-byte hex address (`0x` optional). */
    fun toChecksumAddress(address: String): String {
        val lower = strip0x(address).lowercase()
        require(ADDRESS_BODY.matches(lower)) { "not an EVM address" }
        val hash = Hashes.keccak256Hex(lower)
        val out = StringBuilder("0x")
        for (i in lower.indices) {
            val c = lower[i]
            out.append(if (c in 'a'..'f' && hash[i].digitToInt(16) >= 8) c.uppercaseChar() else c)
        }
        return out.toString()
    }

    /** Case-insensitive address equality (iOS compares `lowercased()` strings everywhere). */
    fun sameAddress(a: String?, b: String?): Boolean =
        !a.isNullOrBlank() && !b.isNullOrBlank() && a.trim().lowercase() == b.trim().lowercase()

    /**
     * Whole units → smallest units, truncated like iOS `NumberFormatter(roundingMode: .down)` of
     * `ETHWeiFromTokenAmountString` (`NSDecimalNumber(string:).multiplying(byPowerOf10:)`).
     */
    fun toMinor(amount: BigDecimal, decimals: Int): BigInteger =
        amount.movePointRight(decimals).setScale(0, RoundingMode.DOWN).toBigInteger()

    /** Smallest units → whole units at full precision (iOS `CoinFormatString(basicAmount:decimal:)`). */
    fun fromMinor(minor: BigInteger, decimals: Int): BigDecimal {
        val v = BigDecimal(minor).movePointLeft(decimals)
        return if (v.signum() == 0) BigDecimal.ZERO else v.stripTrailingZeros().let { if (it.scale() < 0) it.setScale(0) else it }
    }

    /** Wei → Gwei at full precision (iOS `ETHGweiFormatString`). */
    fun weiToGwei(wei: BigInteger): BigDecimal = fromMinor(wei, 9)

    /** 32-byte left-padded lower-case hex word (no `0x`) of an address. */
    internal fun addressWord(address: String): String = strip0x(address).lowercase().padStart(64, '0')

    /** 32-byte left-padded lower-case hex word (no `0x`) of an unsigned integer. */
    internal fun uintWord(value: BigInteger): String = value.toString(16).padStart(64, '0')

    /**
     * An NFT token id as the bundles read it (ethers `BigNumber.from(id)`: decimal text or `0x` hex); `null` when it is
     * neither or negative.
     */
    fun parseTokenId(tokenId: String): BigInteger? {
        val t = tokenId.trim()
        if (t.isEmpty()) return null
        val value = if (t.startsWith("0x") || t.startsWith("0X")) {
            t.substring(2).takeIf { it.isNotEmpty() }?.let { parseHexQuantity(t) }
        } else {
            t.toBigIntegerOrNull()
        }
        return value?.takeIf { it.signum() >= 0 }
    }

    /** `transfer(address,uint256)`. */
    private const val ERC20_TRANSFER = "0xa9059cbb"

    /** ERC721 `safeTransferFrom(address,address,uint256)`. */
    private const val ERC721_SAFE_TRANSFER = "0x42842e0e"

    /** ERC1155 `safeTransferFrom(address,address,uint256,uint256,bytes)`. */
    internal const val ERC1155_SAFE_TRANSFER = "0xf242432a"

    /**
     * The calldata the signing bundles produce for a token transfer — ERC20 `transfer(to, amount)`, ERC721
     * `safeTransferFrom(from, to, id)`, ERC1155 `safeTransferFrom(from, to, id, amount, "0x")`: iOS `ethjs-ext-v2.js`
     * `_signErc20|721|1155Transaction` (ethers ABI coder) and, with [legacyBundle], `ethereumjs-lib-app.min.js`
     * `createTokenData` / `createErc721TokenData` / `createErc1155TokenData`. The two encode identically except that the
     * legacy ERC1155 string appends one extra zero word after the empty `bytes` (harmless: ABI decoders ignore trailing
     * data). `null` when an NFT id is not a number.
     */
    internal fun tokenTransferData(
        ercType: ErcType,
        from: String,
        to: String,
        amount: BigInteger,
        tokenId: String,
        legacyBundle: Boolean,
    ): String? = when (ercType) {
        ErcType.ERC20 -> ERC20_TRANSFER + addressWord(to) + uintWord(amount)
        ErcType.ERC721 -> parseTokenId(tokenId)?.let {
            ERC721_SAFE_TRANSFER + addressWord(from) + addressWord(to) + uintWord(it)
        }
        ErcType.ERC1155 -> parseTokenId(tokenId)?.let {
            // bytes "0x": offset 0xa0 (5 head words), then length 0 (+ the legacy bundle's extra zero word).
            ERC1155_SAFE_TRANSFER + addressWord(from) + addressWord(to) + uintWord(it) + uintWord(amount) +
                uintWord(BigInteger.valueOf(0xa0)) + uintWord(BigInteger.ZERO) +
                (if (legacyBundle) uintWord(BigInteger.ZERO) else "")
        }
    }
}
