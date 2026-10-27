// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.model.coin

/** EVM token standard as the bundles number it (iOS `ercType`: 0 = ERC20, 1 = ERC721, 2 = ERC1155). */
enum class ErcType(val raw: Int) {
    ERC20(0),
    ERC721(1),
    ERC1155(2),
    ;

    /** `true` for ERC721 / ERC1155. */
    val isNft: Boolean get() = this != ERC20

    companion object {
        /** Unknown values fall back to [ERC20], as iOS does for a missing field. */
        fun fromRaw(raw: Int?): ErcType = entries.firstOrNull { it.raw == raw } ?: ERC20
    }
}
