// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.publicsigner.sign

/** Risk level of a warning on the review page (the app's security-center scale). */
enum class SignatureRisk(val wire: String, val rank: Int) {
    LOW("low", 0),
    MEDIUM("medium", 1),
    HIGH("high", 2),
    CRITICAL("critical", 3),
}
