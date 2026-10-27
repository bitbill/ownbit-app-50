// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.crypto.kdf

/**
 * scrypt work factors.
 *
 * @property n CPU/memory cost (power of two, > 1)
 * @property r block size
 * @property p parallelism
 * @property dkLen derived key length in bytes
 */
data class ScryptParams(val n: Int, val r: Int, val p: Int, val dkLen: Int) {
    init {
        require(isAcceptable(n, r, p, dkLen)) { "unacceptable scrypt parameters (n=$n r=$r p=$p dkLen=$dkLen)" }
    }

    /** Approximate memory needed by one derivation: `128 * r * n` bytes. */
    val memoryBytes: Long get() = 128L * r * n

    companion object {
        /**
         * OBV2 wallet-secret parameters (iOS `WalletSecretCipher` defaults: N=32768, r=8, p=1, 32 bytes,
         * ~0.8 s and 32 MiB per derivation on an iPhone).
         */
        val WALLET_SECRET = ScryptParams(n = 32768, r = 8, p = 1, dkLen = 32)


        /**
         * Upper bound for parameters read from untrusted/stored data (envelopes): 256 MiB of scrypt memory.
         * iOS only ever writes N=32768/r=8 (32 MiB); the bound stops a crafted envelope from exhausting memory.
         */
        const val MAX_MEMORY_BYTES: Long = 256L * 1024 * 1024

        /** Largest accepted derived key length. */
        const val MAX_DK_LEN = 64

        /**
         * True when the parameters are well-formed and within the resource bounds of this module.
         */
        fun isAcceptable(n: Int, r: Int, p: Int, dkLen: Int): Boolean {
            if (n <= 1 || (n and (n - 1)) != 0) return false
            if (r < 1 || p < 1) return false
            if (dkLen < 1 || dkLen > MAX_DK_LEN) return false
            if (r.toLong() * p >= (1L shl 30)) return false
            if (p > 16) return false
            return 128L * r * n <= MAX_MEMORY_BYTES
        }
    }
}
