// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.chain.tron

import java.math.BigInteger

/** Bitcoin-alphabet Base58 (TRON addresses). */
internal object Base58 {
    private const val ALPHABET = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
    private val INDEXES = IntArray(128) { -1 }.also { idx -> ALPHABET.forEachIndexed { i, c -> idx[c.code] = i } }
    private val BASE = BigInteger.valueOf(58)

    fun encode(bytes: ByteArray): String {
        if (bytes.isEmpty()) return ""
        var value = BigInteger(1, bytes)
        val sb = StringBuilder()
        while (value.signum() > 0) {
            val (q, r) = value.divideAndRemainder(BASE)
            sb.append(ALPHABET[r.toInt()])
            value = q
        }
        for (b in bytes) {
            if (b.toInt() != 0) break
            sb.append(ALPHABET[0])
        }
        return sb.reverse().toString()
    }

    /** Decodes, or `null` on an invalid character. */
    fun decode(text: String): ByteArray? {
        if (text.isEmpty()) return ByteArray(0)
        var value = BigInteger.ZERO
        for (c in text) {
            val digit = if (c.code < 128) INDEXES[c.code] else -1
            if (digit < 0) return null
            value = value.multiply(BASE).add(BigInteger.valueOf(digit.toLong()))
        }
        val raw = value.toByteArray().let { if (it.size > 1 && it[0].toInt() == 0) it.copyOfRange(1, it.size) else it }
        val leadingZeros = text.takeWhile { it == ALPHABET[0] }.length
        val body = if (value.signum() == 0) ByteArray(0) else raw
        return ByteArray(leadingZeros) + body
    }
}

internal fun ByteArray.toHex(): String = joinToString("") { "%02x".format(it.toInt() and 0xff) }

internal fun String.hexToBytesOrNull(): ByteArray? {
    val s = removePrefix("0x").removePrefix("0X")
    if (s.length % 2 != 0 || s.any { Character.digit(it, 16) < 0 }) return null
    return ByteArray(s.length / 2) { i -> ((Character.digit(s[2 * i], 16) shl 4) or Character.digit(s[2 * i + 1], 16)).toByte() }
}

internal fun sha256(bytes: ByteArray): ByteArray = java.security.MessageDigest.getInstance("SHA-256").digest(bytes)

/** Stake 2.0 operations (iOS `BILDelegationController`) and the contract each one must carry. No vote in iOS. */
enum class TronStakingOperation(val raw: String, val contractType: Int) {
    /** FreezeBalanceV2 (energy / bandwidth). */
    STAKE("freezebalancev2", TronContractType.FREEZE_BALANCE_V2),

    /** UnfreezeBalanceV2 (starts the 14-day unlock). */
    UNSTAKE("unfreezebalancev2", TronContractType.UNFREEZE_BALANCE_V2),

    /** WithdrawExpireUnfreeze. */
    WITHDRAW("withdrawexpireunfreeze", TronContractType.WITHDRAW_EXPIRE_UNFREEZE),

    /** DelegateResource to another address (not self). */
    DELEGATE("delegateresource", TronContractType.DELEGATE_RESOURCE),

    /** UnDelegateResource of a listed delegation. */
    UNDELEGATE("undelegateresource", TronContractType.UNDELEGATE_RESOURCE),
}
