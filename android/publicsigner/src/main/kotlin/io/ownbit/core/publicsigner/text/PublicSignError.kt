// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.publicsigner.text

/**
 * A public-protocol refusal as the UI shows it: [message] is the name of the app's localized string (e.g.
 * `publicprotocol_err_integrity`; the strings themselves are UI and not part of this repository), [args] its format
 * arguments (data such as the TRON owner address — a `String` — or a number for a `%d` placeholder), and — for the
 * "details from the signing engine (English)" disclosure only — the engine [code] and its bounded English
 * [engineMessage] (never log it; only [code] may be logged).
 */
data class PublicSignError(
    val message: String,
    val args: List<Any> = emptyList(),
    val code: String? = null,
    val engineMessage: String? = null,
) {
    /** The code only. */
    override fun toString(): String = "PublicSignError(code=$code)"
}
