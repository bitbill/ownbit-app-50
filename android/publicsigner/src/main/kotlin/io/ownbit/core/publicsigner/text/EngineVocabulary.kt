// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.publicsigner.text

import io.ownbit.core.publicsigner.model.DecodeStatus
import io.ownbit.core.publicsigner.model.RiskLevel

/** A localized engine text: the string [res] filled with [args] (raw engine values: amounts, indexes, symbols). */
data class LocalizedText(val res: String, val args: List<String> = emptyList())

/**
 * A localized engine warning. [id] is the vocabulary id (`engine_vocabulary.json`), [severity] the BitSigner rule
 * ([EngineVocabulary.severity]).
 */
data class LocalizedWarning(
    val id: String,
    val res: String,
    val args: List<String> = emptyList(),
    val severity: WarningSeverity,
)

/** How a warning is shown: [DANGER] for `HIGH RISK` / `UNLIMITED` / `HIGH FEE`, else [WARNING] (BitSigner `isSevere`). */
enum class WarningSeverity { WARNING, DANGER }

/**
 * Engine English → the app's `PublicProtocol.*` strings. The engine's review is English free text; this table maps
 * what the vocabulary of the pinned engine
 * (`iOS/Tests/OwnbitCoreTests/PublicProtocol/Fixtures/engine_vocabulary.json`, extracted from the engine)
 * marks for translation: every `display.action`, the common field labels and the 25 most frequent warnings, plus the
 * decode / risk banners. **Anything it does not know returns `null` and is shown verbatim** (English, `EN` tag, under
 * "Details from the signing engine") — a warning is never dropped. `EngineVocabularyTest` fails when the engine's
 * vocabulary and this table disagree (a new engine build must be mapped or consciously left verbatim).
 *
 * Templates use Android `%1$s` placeholders with `%%` for a literal percent, exactly the vocabulary's `text`; matching
 * is anchored and whole-text. Placeholder-free entries win over templates; among templates the longest text wins
 * (vocabulary rule); index placeholders (`Input %1$s`, `Output %1$s`, `Instruction %1$s · …`) match digits only, so
 * longer engine labels such as `Output 1 ownership` stay verbatim instead of being half-translated.
 */
object EngineVocabulary {

    // Declared first: the tables below are built from them during object initialization.
    private val PLACEHOLDER = Regex("%(\\d)\\\$s")
    private val SEVERE_PREFIXES = listOf("HIGH RISK", "UNLIMITED", "HIGH FEE")

    /** Vocabulary id of the engine's Solana durable-nonce warning ([OWNBIT_ALIASES] → `warn.durableNonce`). */
    const val DURABLE_NONCE_ID: String = "thisTransactionUsesADurableNonce"

    /** Vocabulary id of the engine's SegWit v0 witness-only input warning ([OWNBIT_ALIASES] → `warn.btcWitnessOnly`). */
    const val BTC_WITNESS_ONLY_ID: String = "btcWitnessOnly"

    /** Vocabulary id of the engine's TronLink ownership-check warning ([OWNBIT_ALIASES] → `warn.ownershipProof`). */
    const val OWNERSHIP_PROOF_ID: String = "ownershipProof"

    /** Vocabulary id of the engine's "network not in the signed domain" warning (Ownbit's `warn.noChainId` meaning). */
    const val TYPED_DATA_ANY_CHAIN_ID: String = "typedDataAnyChain"

    /** The localized label of an exact `display.action` (26 engine actions), `null` otherwise. */
        fun action(action: String): String? = ACTIONS[action]

    /**
     * [action] plus the engine's `Safe: ` prefix (`Safe: Send` → [LocalizedAction] with `prefix = "Safe"`, the brand is
     * never translated). `null` for unknown actions (verbatim, or `action.generic` in the headline).
     */
    fun localizedAction(action: String): LocalizedAction? {
        ACTIONS[action]?.let { return LocalizedAction(it, null) }
        if (action.startsWith(SAFE_PREFIX)) ACTIONS[action.removePrefix(SAFE_PREFIX)]?.let { return LocalizedAction(it, SAFE) }
        return null
    }

    /** A localized action and the brand prefix the engine put in front of it (`Safe`), if any. */
    data class LocalizedAction(val res: String, val prefix: String?)

    /**
     * The vocabulary id of an engine `display.action` (`Send` → `send`, `Safe: Send` → `send`), `null` for an action the
     * vocabulary does not know — the wire id of an offline-signing record (the record page maps ids, never
     * engine English).
     */
    fun actionId(action: String): String? =
        ACTION_IDS[action] ?: action.takeIf { it.startsWith(SAFE_PREFIX) }?.let { ACTION_IDS[it.removePrefix(SAFE_PREFIX)] }

    /** The localized label of a placeholder-free engine field label, `null` otherwise. */
        fun label(text: String): String? = LABELS.firstOrNull { it.placeholders == 0 && it.text == text }?.res

    /** The localized form of an engine field label, templates included (`Input 3` → `label.input` with `3`). */
    fun localizedLabel(text: String): LocalizedText? = match(LABELS, text)?.let { (e, args) -> LocalizedText(e.res, args) }

    /**
     * The localized form of an engine warning, or `null` (show it verbatim): one of the 25 vocabulary warnings,
     * else an [OWNBIT_ALIASES] text (an engine warning with the meaning of one of Ownbit's own `warn.*` strings).
     */
    fun warning(text: String): LocalizedWarning? =
        (match(WARNINGS, text) ?: match(OWNBIT_ALIASES, text))?.let { (e, args) -> LocalizedWarning(e.id, e.res, args, severity(text)) }

    /** BitSigner `RequestReviewView.isSevere`: `HIGH RISK`, `UNLIMITED` or `HIGH FEE` at the start → danger. */
    fun severity(text: String): WarningSeverity {
        val upper = text.trimStart().uppercase(java.util.Locale.ROOT)
        return if (SEVERE_PREFIXES.any { upper.startsWith(it) }) WarningSeverity.DANGER else WarningSeverity.WARNING
    }

    /** The decode badge ("Decoded on device" / "Partially decoded" / "Not decoded"). */
        fun decodeStatus(status: DecodeStatus): String = when (status) {
        DecodeStatus.FULLY_DECODED -> "publicprotocol_decode_full"
        DecodeStatus.PARTIALLY_DECODED -> "publicprotocol_decode_partial"
        DecodeStatus.OPAQUE -> "publicprotocol_decode_none"
    }

    /** The risk pill: "High risk" / "Warning"; `null` for a normal request. */
        fun riskLevel(level: RiskLevel): String? = when (level) {
        RiskLevel.HIGH -> "publicprotocol_risk_high"
        RiskLevel.WARNING -> "publicprotocol_risk_warning"
        RiskLevel.NORMAL -> null
    }

    // ---- tables ---------------------------------------------------------------------------------------------------

    /** One vocabulary entry: [text] in the vocabulary's template syntax, [digitArgs] = placeholders that are indexes. */
    internal class Entry(val id: String, val res: String, val text: String, val digitArgs: Set<Int> = emptySet()) {
        val placeholders: Int = PLACEHOLDER.findAll(text).count()
        val regex: Regex = toRegex(text, digitArgs)
    }

    internal val ACTION_TEXTS: Map<String, String> = linkedMapOf(
        "send" to "Send",
        "consolidate" to "Consolidate",
        "approve" to "Approve (NFT or token)",
        "approveAllNfts" to "Approve All NFTs",
        "batch" to "Batch Transaction",
        "blurBulkListing" to "Blur Bulk Listing (blind)",
        "clearNftApproval" to "Clear NFT Approval (if ERC-721)",
        "contractCall" to "Contract Interaction",
        "deploy" to "Deploy Contract",
        "permit" to "Permit Spending",
        "revokeNftApproval" to "Revoke NFT Approval",
        "sendErc1155Batch" to "Send ERC-1155 Batch",
        "sendErc1155" to "Send ERC-1155 Token",
        "sendNft" to "Send NFT",
        "signMessage" to "Sign Message",
        "signTypedData" to "Sign Typed Data",
        "transfer" to "Transfer",
        "transferNftOrToken" to "Transfer (NFT or token)",
        "sendCoreNft" to "Send Core NFT",
        "sendTokenLikelyNft" to "Send Token (likely NFT)",
        "sendCompressedNft" to "Send compressed NFT",
        "signTransaction" to "Sign Transaction",
        "updatePermissions" to "Update Permissions",
        "approveSpending" to "Approve Spending",
        "revokeApproval" to "Revoke Approval",
        "verifyOwnership" to "Verify Ownership",
    )

    internal val ACTION_RES: Map<String, String> = mapOf(
        "send" to "publicprotocol_action_send",
        "consolidate" to "publicprotocol_action_consolidate",
        "approve" to "publicprotocol_action_approve",
        "approveAllNfts" to "publicprotocol_action_approveallnfts",
        "batch" to "publicprotocol_action_batch",
        "blurBulkListing" to "publicprotocol_action_blurbulklisting",
        "clearNftApproval" to "publicprotocol_action_clearnftapproval",
        "contractCall" to "publicprotocol_action_contractcall",
        "deploy" to "publicprotocol_action_deploy",
        "permit" to "publicprotocol_action_permit",
        "revokeNftApproval" to "publicprotocol_action_revokenftapproval",
        "sendErc1155Batch" to "publicprotocol_action_senderc1155batch",
        "sendErc1155" to "publicprotocol_action_senderc1155",
        "sendNft" to "publicprotocol_action_sendnft",
        "signMessage" to "publicprotocol_action_signmessage",
        "signTypedData" to "publicprotocol_action_signtypeddata",
        "transfer" to "publicprotocol_action_transfer",
        "transferNftOrToken" to "publicprotocol_action_transfernftortoken",
        "sendCoreNft" to "publicprotocol_action_sendcorenft",
        "sendTokenLikelyNft" to "publicprotocol_action_sendtokenlikelynft",
        "sendCompressedNft" to "publicprotocol_action_sendcompressednft",
        "signTransaction" to "publicprotocol_action_signtransaction",
        "updatePermissions" to "publicprotocol_action_updatepermissions",
        "approveSpending" to "publicprotocol_action_approvespending",
        "revokeApproval" to "publicprotocol_action_revokeapproval",
        "verifyOwnership" to "publicprotocol_action_verifyownership",
    )

    private val ACTIONS: Map<String, String> = ACTION_TEXTS.entries.associate { (id, text) -> text to ACTION_RES.getValue(id) }

    private val ACTION_IDS: Map<String, String> = ACTION_TEXTS.entries.associate { (id, text) -> text to id }

    /** Generic headline for an action the table does not know ("Sign request"). */
        val GENERIC_ACTION: String = "publicprotocol_action_generic"

    internal val LABELS: List<Entry> = listOf(
        Entry("network", "publicprotocol_label_network", "Network"),
        Entry("input", "publicprotocol_label_input", "Input %1\$s", digitArgs = setOf(1)),
        Entry("inputSighash", "publicprotocol_label_inputsighash", "Input %1\$s sighash", digitArgs = setOf(1)),
        Entry("networkContext", "publicprotocol_label_networkcontext", "Network context"),
        Entry("instruction", "publicprotocol_label_instruction", "Instruction %1\$s · %2\$s", digitArgs = setOf(1)),
        Entry("derivationPath", "publicprotocol_pair_derivationpath", "Derivation path"),
        Entry("requestedSigner", "publicprotocol_label_requestedsigner", "Requested signer"),
        Entry("output", "publicprotocol_label_output", "Output %1\$s", digitArgs = setOf(1)),
        Entry("inputs", "publicprotocol_label_inputs", "Inputs"),
        Entry("locktime", "publicprotocol_label_locktime", "Locktime"),
        Entry("networkFee", "publicprotocol_label_networkfee", "Network fee"),
        Entry("totalOutput", "publicprotocol_label_totaloutput", "Total output"),
        Entry("nativeAmountWei", "publicprotocol_label_nativeamountwei", "Native amount (wei)"),
        Entry("recipientOrContract", "publicprotocol_label_recipientorcontract", "Recipient / contract"),
        Entry("chainId", "publicprotocol_label_chainid", "Chain ID"),
        Entry("gasLimit", "publicprotocol_label_gaslimit", "Gas limit"),
        Entry("maxGasPriceWei", "publicprotocol_label_maxgaspricewei", "Maximum gas price (wei)"),
        Entry("maxNetworkFee", "publicprotocol_label_maxnetworkfee", "Maximum network fee (%1\$s)"),
        Entry("nonce", "publicprotocol_label_nonce", "Nonce"),
        Entry("transactionType", "publicprotocol_label_transactiontype", "Transaction type"),
        Entry("message", "publicprotocol_label_message", "Message"),
        Entry("nativeAmount", "publicprotocol_label_nativeamount", "Native amount (%1\$s)"),
        Entry("recipient", "publicprotocol_label_recipient", "Recipient"),
        Entry("exactCalldata", "publicprotocol_label_exactcalldata", "Exact calldata"),
        Entry("exactMessageBytes", "publicprotocol_label_exactmessagebytes", "Exact message bytes"),
        // Round 2 (TRON reviews in the golden vectors): now among the most frequent engine labels.
        Entry("account", "publicprotocol_label_account", "Account"),
        Entry("transactionId", "publicprotocol_label_transactionid", "Transaction ID"),
        Entry("expirationUtc", "publicprotocol_label_expirationutc", "Expiration (UTC)"),
        Entry("permissionId", "publicprotocol_label_permissionid", "Permission ID"),
        Entry("maxEnergyFeeTrx", "publicprotocol_label_maxenergyfeetrx", "Maximum energy fee (TRX)"),
        // The detail row of TronLink's ownership check (the placeholder's name; no transaction id).
        Entry("signedData", "publicprotocol_label_signeddata", "Signed data"),
    )

    internal val WARNINGS: List<Entry> = listOf(
        Entry("btcOutputsShown", "publicprotocol_warn_btcoutputsshown", "Every output is shown. Change ownership and the intended multisig policy are not inferred from untrusted PSBT labels."),
        Entry("btcHighFee", "publicprotocol_warn_btchighfee", "HIGH FEE: Fee exceeds 0.01 BTC, or exceeds half of the amount sent (and 0.0001 BTC). Verify it carefully."),
        Entry("evmMessageAuthorizes", "publicprotocol_warn_evmmessageauthorizes", "Message signatures can authorize logins, orders or asset actions. Verify the entire message and origin."),
        Entry("solOfflineLimits", "publicprotocol_warn_solofflinelimits", "Blockhash freshness, network identity, account state and base network fee cannot be verified offline."),
        Entry("contractUnverified", "publicprotocol_warn_contractunverified", "Contract identity, current permissions and on-chain state are not verified offline."),
        Entry("tronOfflineLimits", "publicprotocol_warn_tronofflinelimits", "TRON chain identity and current account permissions cannot be verified from transaction bytes offline. Verify the intended network in the hot wallet."),
        Entry("tronOwnerPermission", "publicprotocol_warn_tronownerpermission", "Owner permission ID 0 may use weighted multisig members. Current membership, weights and threshold are unverified offline."),
        Entry("btcInputAmounts", "publicprotocol_warn_btcinputamounts", "Input amounts are supplied by the coordinator. Taproot ALL/DEFAULT commits every input amount; incorrect values invalidate the signature."),
        Entry("solMessageRaw", "publicprotocol_warn_solmessageraw", "Solana signs exact message bytes without a mandatory domain prefix. Only sign a message you recognize."),
        Entry("btcChangeVerified", "publicprotocol_warn_btcchangeverified", "Every output is shown. Outputs marked as returning to your wallet were verified from the signing wallet’s own public keys."),
        Entry("typedDataUnverified", "publicprotocol_warn_typeddataunverified", "The verifying contract, domain name and current chain state are not verified offline."),
        Entry("unlimitedApproval", "publicprotocol_warn_unlimitedapproval", "UNLIMITED spending approval."),
        Entry("tronMessageAuthorizes", "publicprotocol_warn_tronmessageauthorizes", "A personal signature may authorize logins, orders or other asset actions. Verify the full message and origin."),
        Entry("solHighFee", "publicprotocol_warn_solhighfee", "HIGH FEE: This transaction allows up to %1\$s SOL in priority fees. Check the fee settings in your other wallet."),
        Entry("tronHighFee", "publicprotocol_warn_tronhighfee", "HIGH FEE: This transaction allows up to %1\$s TRX in energy fees. Check the fee limit in your other wallet."),
        Entry("evmHighFee", "publicprotocol_warn_evmhighfee", "HIGH FEE: This transaction allows up to %1\$s in network fees. Check the gas settings in your other wallet."),
        Entry("messageLooksLikeHash", "publicprotocol_warn_messagelookslikehash", "HIGH RISK: This 32-byte message looks like a hash. Signing a hash you cannot read can authorize anything."),
        Entry("unknownMethod", "publicprotocol_warn_unknownmethod", "HIGH RISK: This contract method is not decoded. The contract may move assets or change permissions."),
        Entry("permitSpending", "publicprotocol_warn_permitspending", "HIGH RISK: This permit authorizes token spending without another signature. Verify the spender, amount, expiry and nonce."),
        Entry("approveSharedSelector", "publicprotocol_warn_approvesharedselector", "This authorizes another address to spend assets. Unknown ERC20 allowance and ERC721 token approval share this selector."),
        Entry("rollupFees", "publicprotocol_warn_rollupfees", "Additional L1 data or rollup fees are not bound by gasLimit × gas price and cannot be calculated fully offline."),
        Entry("tronMultisigMember", "publicprotocol_warn_tronmultisigmember", "Multisig member weights and whether the selected permission is current are unverified offline. This adds one signature only."),
        Entry("typedDataAnyChain", "publicprotocol_warn_typeddataanychain", "Network context not included in the signed domain; this signature may be reusable on other networks."),
        Entry(
            "tronOwnerSignerDiffers",
            "publicprotocol_warn_tronownersignerdiffers",
            "Owner permission (ID 0): the requested signer differs from the account address. Current owner membership, weights and threshold are unverified offline. This adds one member signature only; the coordinator must verify membership and sufficient total weight before broadcast.",
        ),
        Entry("btcDataOutput", "publicprotocol_warn_btcdataoutput", "The transaction includes an unspendable data output."),
    )

    /**
     * Engine warnings outside the 25 translated ones (`translate: false` in the vocabulary) that say exactly what one of
     * Ownbit's own warnings says: shown with that Ownbit string, and [io.ownbit.core.publicsigner.sign.PublicSignPolicy]
     * then does not add its own copy (one warning, localized, instead of the same text twice). [Entry.id] is the
     * vocabulary id.
     */
    internal val OWNBIT_ALIASES: List<Entry> = listOf(
        Entry(
            DURABLE_NONCE_ID,
            "publicprotocol_warn_durablenonce",
            "This transaction uses a durable nonce, so it does not expire. It can be submitted until the nonce account advances.",
        ),
        // SegWit v0 inputs with witnessUtxo only. Ownbit's wording names the outpoint-amount memory.
        Entry(
            BTC_WITNESS_ONLY_ID,
            "publicprotocol_warn_btcwitnessonly",
            "Input amounts of SegWit v0 inputs are supplied by the coordinator without full previous transactions. The fee is computed from those amounts; each signature commits only to its own input amount. Never sign two different requests that spend the same inputs.",
        ),
        // The TronLink ownership check (fixed placeholder, not a transaction).
        Entry(
            OWNERSHIP_PROOF_ID,
            "publicprotocol_warn_ownershipproof",
            "This signature only proves that this wallet holds the key of the account. It is not a transaction and cannot move funds.",
        ),
    )

    // ---- matching -------------------------------------------------------------------------------------------------

    private const val SAFE_PREFIX = "Safe: "
    private const val SAFE = "Safe"

    /**
     * The vocabulary's `pattern` of [text] (`extract-vocabulary.mjs`): anchored, regex specials of the literal parts
     * escaped with a backslash, `%N$s` → `([\s\S]+?)` (`([0-9]+)` for [digitArgs]), `%%` → `%`.
     */
    internal fun toPattern(text: String, digitArgs: Set<Int> = emptySet()): String {
        val out = StringBuilder("^")
        var i = 0
        while (i < text.length) {
            val c = text[i]
            val isPlaceholder = c == '%' && i + 3 < text.length && text[i + 1] in '1'..'9' && text[i + 2] == '$' && text[i + 3] == 's'
            when {
                isPlaceholder -> {
                    out.append(if ((text[i + 1] - '0') in digitArgs) "([0-9]+)" else "([\\s\\S]+?)")
                    i += 4
                }
                c == '%' && i + 1 < text.length && text[i + 1] == '%' -> {
                    out.append('%')
                    i += 2
                }
                else -> {
                    if (c in REGEX_SPECIALS) out.append('\\')
                    out.append(c)
                    i++
                }
            }
        }
        return out.append('$').toString()
    }

    private fun toRegex(text: String, digitArgs: Set<Int>): Regex = Regex(toPattern(text, digitArgs))

    private const val REGEX_SPECIALS = ".*+?^\${}()|[]\\"

    private fun match(entries: List<Entry>, text: String): Pair<Entry, List<String>>? {
        entries.firstOrNull { it.placeholders == 0 && it.regex.matches(text) }?.let { return it to emptyList() }
        return entries.filter { it.placeholders > 0 }
            .mapNotNull { e -> e.regex.matchEntire(text)?.let { m -> e to m.groupValues.drop(1) } }
            .maxByOrNull { it.first.text.length }
    }
}
