// Copyright (c) 2017-2026 BITTOOL PTE. LTD.
// SPDX-License-Identifier: MIT
package io.ownbit.core.publicsigner.model

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/** How completely the engine decoded what will be signed (engine `decodeStatus`). Unknown values read as [OPAQUE]. */
enum class DecodeStatus(val wire: String) {
    FULLY_DECODED("fullyDecoded"),
    PARTIALLY_DECODED("partiallyDecoded"),
    OPAQUE("opaque"),
    ;

    companion object {
        fun fromWire(wire: String?): DecodeStatus = entries.firstOrNull { it.wire == wire } ?: OPAQUE
    }
}

/** The engine's risk level (`riskLevel`). Unknown values read as [HIGH] (fail closed). */
enum class RiskLevel(val wire: String) {
    NORMAL("normal"),
    WARNING("warning"),
    HIGH("high"),
    ;

    companion object {
        fun fromWire(wire: String?): RiskLevel = entries.firstOrNull { it.wire == wire } ?: HIGH
    }
}

/**
 * One "label: value" row of the engine review. Labels and values are the engine's English text (labels are localized
 * by the review presenter where the vocabulary knows them); values are shown whole, never cut (what is shown is what
 * is signed). [index] keeps the engine order.
 */
data class ReviewField(val index: Int, val label: String, val value: String) {
    /** The group of "Instruction 2 · Recipient" ("Instruction 2"), else `null`. */
    val group: String? get() = label.indexOf(GROUP_SEPARATOR).takeIf { it >= 0 }?.let { label.substring(0, it) }

    /** The label without its group. */
    val shortLabel: String
        get() = label.indexOf(GROUP_SEPARATOR).takeIf { it >= 0 }?.let { label.substring(it + GROUP_SEPARATOR.length) } ?: label

    private companion object {
        const val GROUP_SEPARATOR = " · "
    }
}

/** Network context the engine reports for this exact request (EVM chain id + name; BTC / TRON / SOL name only). */
data class ReviewNetwork(val chainId: String?, val name: String, val symbol: String?)

/**
 * Token the engine recognised from its bundled registry (engine `asset`; BitSigner `ReviewAsset`). Amounts are decimal
 * strings, never floating point.
 */
data class ReviewAsset(
    val chainFamily: String,
    val chainId: String?,
    val assetAddress: String,
    val name: String,
    val symbol: String,
    val decimals: Int,
    val tokenProgram: String?,
    val rawAmount: String?,
    val displayAmount: String?,
)

/**
 * The engine review of one request (`review` / `plan.review`, `src/util.js` `reviewResult`; BitSigner
 * `TransactionReview`). Review rows on the page come **only** from this object. Everything in it is untrusted
 * English text from the request's decoder: render through `UntrustedText`, addresses LTR.
 *
 * @property chain `null` for a chain this app does not know (the plan is then not signable).
 * @property warnings every engine warning, in order — **never filtered or truncated** (a dropped warning fails the
 *   review tests); unknown ones are shown verbatim in English.
 * @property requestHash the engine's hash of the normalized request (the "request fingerprint").
 * @property canSign the engine's own flag (`true` for every reviewed request today).
 */
data class PublicReview(
    val chain: PsChain?,
    val title: String,
    val summary: String,
    val fields: List<ReviewField>,
    val warnings: List<String>,
    val requestHash: String,
    val canSign: Boolean,
    val decodeStatus: DecodeStatus,
    val riskLevel: RiskLevel,
    val network: ReviewNetwork?,
    val display: PublicReviewDisplay?,
    val asset: ReviewAsset?,
) {
    /**
     * BitSigner's consent rule (`TransactionReview.requiresAcknowledgement`): incompletely decoded or high-risk requests
     * need an explicit per-request checkbox before signing. The engine itself insists only for partial / opaque
     * decoding (`riskAcknowledged`); the merged policy is `PublicSignPolicy`'s.
     */
    val requiresAcknowledgement: Boolean get() = decodeStatus != DecodeStatus.FULLY_DECODED || riskLevel == RiskLevel.HIGH

    /** The network name to show: the engine's network, else its "Network" field, else the chain's brand name. */
    val networkName: String
        get() = network?.name ?: fields.firstOrNull { it.label == "Network" }?.value ?: chain?.brandName.orEmpty()

    companion object {
        /** Reads an engine review object. Lenient like BitSigner (missing texts read as empty), fail closed on status. */
        fun fromEngine(raw: JsonObject): PublicReview {
            val chain = PsChain.fromWire(raw.str("chain"))
            val fields = (raw.arr("fields") ?: JsonArray(emptyList())).mapIndexedNotNull { i, element ->
                val field = element as? JsonObject ?: return@mapIndexedNotNull null
                ReviewField(index = i, label = field.str("label").orEmpty(), value = field["value"]?.displayText().orEmpty())
            }
            val warnings = (raw.arr("warnings") ?: JsonArray(emptyList())).map { it.displayText() }
            val network = raw.obj("network")?.let { n ->
                n.str("name")?.let { name -> ReviewNetwork(chainId = n.str("chainId"), name = name, symbol = n.str("symbol")) }
            }
            return PublicReview(
                chain = chain,
                title = raw.str("title").orEmpty(),
                summary = raw.str("summary").orEmpty(),
                fields = fields,
                warnings = warnings,
                requestHash = raw.str("requestHash").orEmpty(),
                canSign = raw.bool("canSign") ?: false,
                decodeStatus = DecodeStatus.fromWire(raw.str("decodeStatus")),
                riskLevel = RiskLevel.fromWire(raw.str("riskLevel")),
                network = network,
                display = PublicReviewDisplay.fromEngine(raw.obj("display")),
                asset = raw.obj("asset")?.let(::asset),
            )
        }

        /** BitSigner decodes the asset as a whole: a missing required key drops it. */
        private fun asset(raw: JsonObject): ReviewAsset? {
            return ReviewAsset(
                chainFamily = raw.str("chainFamily") ?: return null,
                chainId = raw.str("chainId"),
                assetAddress = raw.str("assetAddress") ?: return null,
                name = raw.str("name") ?: return null,
                symbol = raw.str("symbol") ?: return null,
                decimals = raw.int("decimals") ?: return null,
                tokenProgram = raw.str("tokenProgram"),
                rawAmount = raw.str("rawAmount"),
                displayAmount = raw.str("displayAmount"),
            )
        }
    }
}

/** What an NFT-aware review is about (engine `display.assetKind`); unknown values are ignored with every NFT key. */
enum class ReviewAssetKind(val wire: String) {
    /** The method only exists for NFTs, or the NFT status is proven. */
    NFT("nft"),

    /** Ambiguous: a selector shared by ERC-20 and ERC-721, or a 0-decimal SPL transfer of 1. */
    NFT_OR_TOKEN("nftOrToken"),

    /** ERC-1155: IDs may be fungible, never presented as an NFT. */
    MULTI_TOKEN("multiToken"),

    /** A marketplace order signature (Seaport, LooksRare, Blur). */
    NFT_ORDER("nftOrder"),
    ;

    companion object {
        fun fromWire(wire: String?): ReviewAssetKind? = entries.firstOrNull { it.wire == wire }
    }
}

/**
 * A bounded list of marketplace order lines ("You give" / "You receive" / "Also paid out"): at most
 * [PublicReviewDisplay.MAX_LIST_LINES] lines are kept; [more] counts the ones left out (the page shows a localized
 * "+N more (see Details)" line; the full values stay in the details).
 */
data class FlowLines(val lines: List<String>, val more: Int) {
    val isEmpty: Boolean get() = lines.isEmpty()

    companion object {
        val EMPTY: FlowLines = FlowLines(emptyList(), 0)
    }
}

/**
 * The structured headline the engine builds from the parsed signing bytes (`review.display`; port of BitSigner
 * `ReviewDisplay`). The original keys are read leniently; the NFT keys are type-checked, size-bounded and read only
 * together with a recognised [assetKind] (fail closed: no kind → no NFT box at all). Amounts are decimal strings.
 *
 * @property action the engine action (`Send`, `Approve All NFTs`, …), mapped to a localized label by the vocabulary.
 */
data class PublicReviewDisplay(
    val action: String,
    val amount: String? = null,
    val symbol: String? = null,
    val headline: String? = null,
    val counterpartyLabel: String? = null,
    val counterparty: String? = null,
    val fee: String? = null,
    val note: String? = null,
    val assetKind: ReviewAssetKind? = null,
    val assetContract: String? = null,
    val assetContractLabel: String? = null,
    val tokenId: String? = null,
    val give: FlowLines = FlowLines.EMPTY,
    val receive: FlowLines = FlowLines.EMPTY,
    val others: FlowLines = FlowLines.EMPTY,
) {
    val isNft: Boolean get() = assetKind != null

    /**
     * The full token ID when neither the headline nor the amount already shows it as `#<id>` (then the summary shows it
     * separately); `null` otherwise.
     */
    val summaryTokenId: String?
        get() {
            val id = tokenId ?: return null
            if (!isNft) return null
            val shown = listOfNotNull(headline, amount).any { textShowsTokenId(it, id) }
            return if (shown) null else id
        }

    /** The summary shows the contract / token ID box. */
    val showsAssetBox: Boolean get() = isNft && (assetContract != null || summaryTokenId != null)

    /** Non-empty order lists in reading order (give, receive, others). */
    val flowSections: List<Pair<FlowKind, FlowLines>>
        get() = if (!isNft) emptyList() else listOf(FlowKind.GIVE to give, FlowKind.RECEIVE to receive, FlowKind.OTHERS to others)
            .filter { !it.second.isEmpty }

    enum class FlowKind { GIVE, RECEIVE, OTHERS }

    companion object {
        const val MAX_LIST_LINES: Int = 32
        const val MAX_STRING_LENGTH: Int = 300

        /** Reads `review.display`; `null` when absent or without a string `action`. */
        fun fromEngine(raw: JsonObject?): PublicReviewDisplay? {
            raw ?: return null
            val action = raw.str("action") ?: return null
            val base = PublicReviewDisplay(
                action = action,
                amount = raw.str("amount"),
                symbol = raw.str("symbol"),
                headline = raw.str("headline"),
                counterpartyLabel = raw.str("counterpartyLabel"),
                counterparty = raw.str("counterparty"),
                fee = raw.str("fee"),
                note = raw.str("note"),
            )
            val kind = ReviewAssetKind.fromWire(raw.str("assetKind")) ?: return base
            return base.copy(
                assetKind = kind,
                assetContract = boundedValue(raw["assetContract"]),
                assetContractLabel = boundedValue(raw["assetContractLabel"]),
                tokenId = boundedValue(raw["tokenId"]),
                give = boundedLines(raw["give"]),
                receive = boundedLines(raw["receive"]),
                others = boundedLines(raw["others"]),
            )
        }

        /** An identifier is shown whole or not at all: a blank or over-long value is dropped, never cut. */
        internal fun boundedValue(value: Any?): String? {
            val text = (value as? JsonPrimitive)?.takeIf { it.isString }?.content ?: return null
            return text.takeIf { it.isNotBlank() && it.length <= MAX_STRING_LENGTH }
        }

        /**
         * A list is all strings or ignored. Blank lines are dropped, an over-long line is cut in the middle (start and end
         * stay), more than [MAX_LIST_LINES] lines keep the first `MAX_LIST_LINES − 1` and count the rest.
         */
        internal fun boundedLines(value: Any?): FlowLines {
            val array = value as? JsonArray ?: return FlowLines.EMPTY
            val strings = array.map { (it as? JsonPrimitive)?.takeIf { p -> p.isString }?.content ?: return FlowLines.EMPTY }
            val lines = strings.filter { it.isNotBlank() }.map(::boundedLine)
            if (lines.size <= MAX_LIST_LINES) return FlowLines(lines, 0)
            val shown = lines.take(MAX_LIST_LINES - 1)
            return FlowLines(shown, lines.size - shown.size)
        }

        /** Cuts an over-long line in the middle with `…`: the amount (start) and the recipient (end) both stay. */
        internal fun boundedLine(line: String): String {
            if (line.length <= MAX_STRING_LENGTH) return line
            val head = (MAX_STRING_LENGTH - 1) / 2
            // Never split a surrogate pair (an emoji in an NFT name) at either cut.
            val start = line.take(head).let { if (it.lastOrNull()?.isHighSurrogate() == true) it.dropLast(1) else it }
            val end = line.takeLast(MAX_STRING_LENGTH - 1 - head)
                .let { if (it.firstOrNull()?.isLowSurrogate() == true) it.drop(1) else it }
            return "$start…$end"
        }

        /**
         * `true` when [text] shows the whole [id] the way the engine writes IDs: `#<id>` not followed by another digit
         * (`#12345` does not show token 1234).
         */
        fun textShowsTokenId(text: String, id: String): Boolean {
            if (id.isEmpty()) return false
            val needle = "#$id"
            var from = 0
            while (true) {
                val at = text.indexOf(needle, from)
                if (at < 0) return false
                val end = at + needle.length
                if (end == text.length || text[end] !in '0'..'9') return true
                from = end
            }
        }
    }
}
