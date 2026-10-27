// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.publicsigner.scan

import io.ownbit.core.publicsigner.text.PublicSignError

/**
 * A request in another wallet's own QR format (TronLink; any TokenPocket text) that Ownbit cannot read or does not sign — refused **before** the engine: by the Kotlin
 * collectors (conflicting parts,
 * size) or the request mappers (types / actions not signed in v1, malformed content). [error] is the text to show
 * (with its arguments, e.g. TronLink's type number); [kind] how the scan session reports it.
 */
class OtherWalletRequestException(val kind: Kind, val error: PublicSignError) : Exception("Other wallet request refused: ${error.code}") {

    enum class Kind {
        /** Not readable as the format says (structure, hex, JSON, address). */
        MALFORMED,

        /** Readable, but not signed by Ownbit v1 (message types, multi-transaction requests, other chains …). */
        UNSUPPORTED,

        /** Parts of two different requests (a conflicting part, another part count, another address). */
        OTHER_REQUEST,

        /** Beyond the collectors' limits. */
        TOO_LARGE,
    }
}
