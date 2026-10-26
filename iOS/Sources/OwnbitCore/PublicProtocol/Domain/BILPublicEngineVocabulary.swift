//  BILPublicEngineVocabulary.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Engine English → the app's `PublicProtocol.*` strings (spec §8.6, OQ-7, C-DISP). The engine's review is English free
//  text; this table maps what the vocabulary of the pinned engine marks for translation: every `display.action`, the
//  common field labels and the 25 most frequent warnings (+ 3 engine warnings shown with Ownbit's own wording), plus
//  the decode / risk banners. **Anything it does not know returns nil and is shown verbatim** (English + EN tag) — a
//  warning is never dropped.
//
//  Port of Android core/publicsigner text/EngineVocabulary.kt (notes R5 §6). Texts are byte-exact copies of the
//  engine vocabulary (`engine_vocabulary.json`, incl. U+2019 in btcChangeVerified); the domain suite compares them.
//  Matching is anchored and whole-text: placeholder-free entries win over templates, among templates the longest text
//  wins; index placeholders (`Input %1$s`, `Output %1$s`, `Instruction %1$s · …`) match digits only, so longer engine
//  labels such as `Output 1 ownership` stay verbatim. Pure Foundation.
//

import Foundation

enum BILPublicEngineVocabulary {

    /// One vocabulary entry: `text` in the vocabulary's template syntax (`%1$s`, `%%`), `key` the full iOS string key,
    /// `digitArgs` = placeholders that are indexes (match `[0-9]+` only).
    struct Entry: Equatable {
        let id: String
        let key: String
        let text: String
        let digitArgs: Set<Int>
    }

    /// Warning colour: `.danger` for `HIGH RISK` / `UNLIMITED` / `HIGH FEE`, else `.warning`.
    enum Severity: Equatable {
        case warning, danger
    }

    /// SHA-256 of the pinned engine (`signer.js`) this vocabulary was checked against.
    static let engineSHA256 = "d89f76bdeec85d90fd88f07372100e9f4c07ab789530ac2bcffd52be536e7b05"

    /// Vocabulary id of the engine's Solana durable-nonce warning (alias → `warn.durableNonce`).
    static let durableNonceId = "thisTransactionUsesADurableNonce"
    /// Vocabulary id of the engine's SegWit v0 witness-only input warning (alias → `warn.btcWitnessOnly`, R2-2).
    static let btcWitnessOnlyId = "btcWitnessOnly"
    /// Vocabulary id of the engine's TronLink ownership-check warning (alias → `warn.ownershipProof`, R2-7).
    static let ownershipProofId = "ownershipProof"
    /// Vocabulary id of the engine's "network not in the signed domain" warning (Ownbit's `warn.noChainId` meaning).
    static let typedDataAnyChainId = "typedDataAnyChain"

    // MARK: - Tables

    /// The 26 engine actions (`display.action`), vocabulary order: id → exact engine text. Key = `PublicProtocol.action.<id>`.
    static let actions: [(id: String, text: String)] = [
        ("send", "Send"),
        ("consolidate", "Consolidate"),
        ("approve", "Approve (NFT or token)"),
        ("approveAllNfts", "Approve All NFTs"),
        ("batch", "Batch Transaction"),
        ("blurBulkListing", "Blur Bulk Listing (blind)"),
        ("clearNftApproval", "Clear NFT Approval (if ERC-721)"),
        ("contractCall", "Contract Interaction"),
        ("deploy", "Deploy Contract"),
        ("permit", "Permit Spending"),
        ("revokeNftApproval", "Revoke NFT Approval"),
        ("sendErc1155Batch", "Send ERC-1155 Batch"),
        ("sendErc1155", "Send ERC-1155 Token"),
        ("sendNft", "Send NFT"),
        ("signMessage", "Sign Message"),
        ("signTypedData", "Sign Typed Data"),
        ("transfer", "Transfer"),
        ("transferNftOrToken", "Transfer (NFT or token)"),
        ("sendCoreNft", "Send Core NFT"),
        ("sendTokenLikelyNft", "Send Token (likely NFT)"),
        ("sendCompressedNft", "Send compressed NFT"),
        ("signTransaction", "Sign Transaction"),
        ("updatePermissions", "Update Permissions"),
        ("approveSpending", "Approve Spending"),
        ("revokeApproval", "Revoke Approval"),
        ("verifyOwnership", "Verify Ownership"),
    ]

    /// The 31 keyed field labels (`PublicProtocol.label.<id>`, except `Derivation path` → `PublicProtocol.pair.derivationPath`).
    static let labels: [Entry] = [
        Entry("network", "PublicProtocol.label.network", "Network"),
        Entry("input", "PublicProtocol.label.input", "Input %1$s", digitArgs: [1]),
        Entry("inputSighash", "PublicProtocol.label.inputSighash", "Input %1$s sighash", digitArgs: [1]),
        Entry("networkContext", "PublicProtocol.label.networkContext", "Network context"),
        Entry("instruction", "PublicProtocol.label.instruction", "Instruction %1$s \u{00B7} %2$s", digitArgs: [1]),
        Entry("derivationPath", "PublicProtocol.pair.derivationPath", "Derivation path"),
        Entry("requestedSigner", "PublicProtocol.label.requestedSigner", "Requested signer"),
        Entry("output", "PublicProtocol.label.output", "Output %1$s", digitArgs: [1]),
        Entry("inputs", "PublicProtocol.label.inputs", "Inputs"),
        Entry("locktime", "PublicProtocol.label.locktime", "Locktime"),
        Entry("networkFee", "PublicProtocol.label.networkFee", "Network fee"),
        Entry("totalOutput", "PublicProtocol.label.totalOutput", "Total output"),
        Entry("nativeAmountWei", "PublicProtocol.label.nativeAmountWei", "Native amount (wei)"),
        Entry("recipientOrContract", "PublicProtocol.label.recipientOrContract", "Recipient / contract"),
        Entry("chainId", "PublicProtocol.label.chainId", "Chain ID"),
        Entry("gasLimit", "PublicProtocol.label.gasLimit", "Gas limit"),
        Entry("maxGasPriceWei", "PublicProtocol.label.maxGasPriceWei", "Maximum gas price (wei)"),
        Entry("maxNetworkFee", "PublicProtocol.label.maxNetworkFee", "Maximum network fee (%1$s)"),
        Entry("nonce", "PublicProtocol.label.nonce", "Nonce"),
        Entry("transactionType", "PublicProtocol.label.transactionType", "Transaction type"),
        Entry("message", "PublicProtocol.label.message", "Message"),
        Entry("nativeAmount", "PublicProtocol.label.nativeAmount", "Native amount (%1$s)"),
        Entry("recipient", "PublicProtocol.label.recipient", "Recipient"),
        Entry("exactCalldata", "PublicProtocol.label.exactCalldata", "Exact calldata"),
        Entry("exactMessageBytes", "PublicProtocol.label.exactMessageBytes", "Exact message bytes"),
        Entry("account", "PublicProtocol.label.account", "Account"),
        Entry("transactionId", "PublicProtocol.label.transactionId", "Transaction ID"),
        Entry("expirationUtc", "PublicProtocol.label.expirationUtc", "Expiration (UTC)"),
        Entry("permissionId", "PublicProtocol.label.permissionId", "Permission ID"),
        Entry("maxEnergyFeeTrx", "PublicProtocol.label.maxEnergyFeeTrx", "Maximum energy fee (TRX)"),
        Entry("signedData", "PublicProtocol.label.signedData", "Signed data"),
    ]

    /// The 25 warnings the vocabulary translates (`translate: true`), vocabulary order. Key = `PublicProtocol.warn.<id>`.
    static let warnings: [Entry] = [
        Entry("btcOutputsShown", "PublicProtocol.warn.btcOutputsShown",
              "Every output is shown. Change ownership and the intended multisig policy are not inferred from untrusted PSBT labels."),
        Entry("btcHighFee", "PublicProtocol.warn.btcHighFee",
              "HIGH FEE: Fee exceeds 0.01 BTC, or exceeds half of the amount sent (and 0.0001 BTC). Verify it carefully."),
        Entry("evmMessageAuthorizes", "PublicProtocol.warn.evmMessageAuthorizes",
              "Message signatures can authorize logins, orders or asset actions. Verify the entire message and origin."),
        Entry("solOfflineLimits", "PublicProtocol.warn.solOfflineLimits",
              "Blockhash freshness, network identity, account state and base network fee cannot be verified offline."),
        Entry("contractUnverified", "PublicProtocol.warn.contractUnverified",
              "Contract identity, current permissions and on-chain state are not verified offline."),
        Entry("tronOfflineLimits", "PublicProtocol.warn.tronOfflineLimits",
              "TRON chain identity and current account permissions cannot be verified from transaction bytes offline. Verify the intended network in the hot wallet."),
        Entry("tronOwnerPermission", "PublicProtocol.warn.tronOwnerPermission",
              "Owner permission ID 0 may use weighted multisig members. Current membership, weights and threshold are unverified offline."),
        Entry("btcInputAmounts", "PublicProtocol.warn.btcInputAmounts",
              "Input amounts are supplied by the coordinator. Taproot ALL/DEFAULT commits every input amount; incorrect values invalidate the signature."),
        Entry("solMessageRaw", "PublicProtocol.warn.solMessageRaw",
              "Solana signs exact message bytes without a mandatory domain prefix. Only sign a message you recognize."),
        Entry("btcChangeVerified", "PublicProtocol.warn.btcChangeVerified",
              "Every output is shown. Outputs marked as returning to your wallet were verified from the signing wallet\u{2019}s own public keys."),
        Entry("typedDataUnverified", "PublicProtocol.warn.typedDataUnverified",
              "The verifying contract, domain name and current chain state are not verified offline."),
        Entry("unlimitedApproval", "PublicProtocol.warn.unlimitedApproval",
              "UNLIMITED spending approval."),
        Entry("tronMessageAuthorizes", "PublicProtocol.warn.tronMessageAuthorizes",
              "A personal signature may authorize logins, orders or other asset actions. Verify the full message and origin."),
        Entry("solHighFee", "PublicProtocol.warn.solHighFee",
              "HIGH FEE: This transaction allows up to %1$s SOL in priority fees. Check the fee settings in your other wallet."),
        Entry("tronHighFee", "PublicProtocol.warn.tronHighFee",
              "HIGH FEE: This transaction allows up to %1$s TRX in energy fees. Check the fee limit in your other wallet."),
        Entry("evmHighFee", "PublicProtocol.warn.evmHighFee",
              "HIGH FEE: This transaction allows up to %1$s in network fees. Check the gas settings in your other wallet."),
        Entry("messageLooksLikeHash", "PublicProtocol.warn.messageLooksLikeHash",
              "HIGH RISK: This 32-byte message looks like a hash. Signing a hash you cannot read can authorize anything."),
        Entry("unknownMethod", "PublicProtocol.warn.unknownMethod",
              "HIGH RISK: This contract method is not decoded. The contract may move assets or change permissions."),
        Entry("permitSpending", "PublicProtocol.warn.permitSpending",
              "HIGH RISK: This permit authorizes token spending without another signature. Verify the spender, amount, expiry and nonce."),
        Entry("approveSharedSelector", "PublicProtocol.warn.approveSharedSelector",
              "This authorizes another address to spend assets. Unknown ERC20 allowance and ERC721 token approval share this selector."),
        Entry("rollupFees", "PublicProtocol.warn.rollupFees",
              "Additional L1 data or rollup fees are not bound by gasLimit \u{00D7} gas price and cannot be calculated fully offline."),
        Entry("tronMultisigMember", "PublicProtocol.warn.tronMultisigMember",
              "Multisig member weights and whether the selected permission is current are unverified offline. This adds one signature only."),
        Entry("typedDataAnyChain", "PublicProtocol.warn.typedDataAnyChain",
              "Network context not included in the signed domain; this signature may be reusable on other networks."),
        Entry("tronOwnerSignerDiffers", "PublicProtocol.warn.tronOwnerSignerDiffers",
              "Owner permission (ID 0): the requested signer differs from the account address. Current owner membership, weights and threshold are unverified offline. This adds one member signature only; the coordinator must verify membership and sufficient total weight before broadcast."),
        Entry("btcDataOutput", "PublicProtocol.warn.btcDataOutput",
              "The transaction includes an unspendable data output."),
    ]

    /// Engine warnings outside the 25 (`translate: false`) that say exactly what one of Ownbit's own warnings says:
    /// shown with that Ownbit string (`id` = the vocabulary id); the policy then does not add its own copy.
    static let aliases: [Entry] = [
        Entry(durableNonceId, "PublicProtocol.warn.durableNonce",
              "This transaction uses a durable nonce, so it does not expire. It can be submitted until the nonce account advances."),
        Entry(btcWitnessOnlyId, "PublicProtocol.warn.btcWitnessOnly",
              "Input amounts of SegWit v0 inputs are supplied by the coordinator without full previous transactions. The fee is computed from those amounts; each signature commits only to its own input amount. Never sign two different requests that spend the same inputs."),
        Entry(ownershipProofId, "PublicProtocol.warn.ownershipProof",
              "This signature only proves that this wallet holds the key of the account. It is not a transaction and cannot move funds."),
    ]

    // MARK: - Lookups

    /// The localized key of an exact `display.action`, or of `Safe: <action>` (`safePrefix == true`: the view keeps the
    /// brand "Safe" in front of the translated action). nil for unknown actions (shown verbatim).
    static func localizedAction(_ a: String) -> (key: String, safePrefix: Bool)? {
        if let id = exactActionId(a) { return (actionKey(id), false) }
        if let rest = stripSafePrefix(a), let id = exactActionId(rest) { return (actionKey(id), true) }
        return nil
    }

    /// The vocabulary id of a `display.action` (`Send` → `send`, `Safe: Send` → `send`); nil for an action the
    /// vocabulary does not know (`Transfer SOL`) — the wire id of an offline-signing record.
    static func actionId(_ a: String) -> String? {
        if let id = exactActionId(a) { return id }
        if let rest = stripSafePrefix(a) { return exactActionId(rest) }
        return nil
    }

    /// The key of a placeholder-free engine label with exactly this text, else nil (`Input 3` → nil).
    static func label(_ t: String) -> String? {
        return compiledLabels.first { $0.placeholders == 0 && BILPublicDomainText.same($0.entry.text, t) }?.entry.key
    }

    /// The localized form of an engine field label, templates included (`Input 3` → `label.input` with ["3"];
    /// `Instruction 2 · Recipient` → `label.instruction` with ["2", "Recipient"]). nil = show verbatim.
    static func localizedLabel(_ t: String) -> (key: String, args: [String])? {
        guard let (entry, args) = match(compiledLabels, t) else { return nil }
        return (entry.key, args)
    }

    /// The localized form of an engine warning: one of the 25, else an alias. nil = show verbatim (never drop it).
    static func warning(_ t: String) -> (id: String, key: String, args: [String], severity: Severity)? {
        guard let (entry, args) = match(compiledWarnings, t) ?? match(compiledAliases, t) else { return nil }
        return (entry.id, entry.key, args, severity(t))
    }

    /// `HIGH RISK`, `UNLIMITED` or `HIGH FEE` at the start (after Kotlin-whitespace trimming, POSIX upper case) → danger.
    static func severity(_ t: String) -> Severity {
        let upper = BILPublicDomainText.trimStart(t).uppercased(with: Locale(identifier: "en_US_POSIX"))
        for prefix in ["HIGH RISK", "UNLIMITED", "HIGH FEE"] where upper.utf16.starts(with: prefix.utf16) {
            return .danger
        }
        return .warning
    }

    /// The vocabulary's `pattern` of `text`: `^` + literal parts with regex specials (`.*+?^${}()|[]\`) escaped by a
    /// backslash, `%N$s` → `([0-9]+)` if N ∈ `digitArgs` else `([\s\S]+?)`, `%%` → `%`, + `$`.
    static func toPattern(_ text: String, digitArgs: Set<Int>) -> String {
        let t = Array(text.utf16)
        var out: [UInt16] = [0x5E]                                                   // ^
        var i = 0
        while i < t.count {
            let c = t[i]
            if c == 0x25 && i + 3 < t.count && t[i + 1] >= 0x31 && t[i + 1] <= 0x39 && t[i + 2] == 0x24 && t[i + 3] == 0x73 {
                let n = Int(t[i + 1] - 0x30)
                out.append(contentsOf: (digitArgs.contains(n) ? "([0-9]+)" : "([\\s\\S]+?)").utf16)
                i += 4
            } else if c == 0x25 && i + 1 < t.count && t[i + 1] == 0x25 {
                out.append(0x25)
                i += 2
            } else {
                if regexSpecials.contains(c) { out.append(0x5C) }
                out.append(c)
                i += 1
            }
        }
        out.append(0x24)                                                             // $
        return String(decoding: out, as: UTF16.self)
    }

    /// Decode badge key: fullyDecoded → `decode.full`, partiallyDecoded → `decode.partial`, anything else → `decode.none`
    /// (Android `DecodeStatus.fromWire` reads unknown as opaque).
    static func decodeStatusKey(_ wire: String) -> String {
        if BILPublicDomainText.same(wire, "fullyDecoded") { return "PublicProtocol.decode.full" }
        if BILPublicDomainText.same(wire, "partiallyDecoded") { return "PublicProtocol.decode.partial" }
        return "PublicProtocol.decode.none"
    }

    /// Risk pill key: high → `risk.high`, warning → `risk.warning`, normal → nil; any other value reads as high
    /// (Android `RiskLevel.fromWire` fails closed).
    static func riskPillKey(_ wire: String) -> String? {
        if BILPublicDomainText.same(wire, "normal") { return nil }
        if BILPublicDomainText.same(wire, "warning") { return "PublicProtocol.risk.warning" }
        return "PublicProtocol.risk.high"
    }

    // MARK: - Matching (Android `EngineVocabulary.match`)

    private struct Compiled {
        let entry: Entry
        let placeholders: Int
        /// nil only if the generated pattern did not compile (never for the shipped tables): the entry never matches.
        let regex: NSRegularExpression?
    }

    private static let compiledLabels: [Compiled] = labels.map(compile)
    private static let compiledWarnings: [Compiled] = warnings.map(compile)
    private static let compiledAliases: [Compiled] = aliases.map(compile)

    /// `.*+?^${}()|[]\`
    private static let regexSpecials: Set<UInt16> = Set(".*+?^${}()|[]\\".utf16)

    private static let safePrefix = "Safe: "

    private static func compile(_ e: Entry) -> Compiled {
        // Kotlin `matches` / `matchEntire` = whole input: the pattern's final `$` becomes `\z` (ICU `$` would also
        // match before a final line terminator); `wholeMatch` adds the anchored full-range check.
        var pattern = toPattern(e.text, digitArgs: e.digitArgs)
        pattern.removeLast()
        pattern += "\\z"
        return Compiled(entry: e, placeholders: placeholderCount(e.text),
                        regex: try? NSRegularExpression(pattern: pattern, options: []))
    }

    /// Kotlin `Regex("%(\\d)\\$s").findAll(text).count()`.
    private static func placeholderCount(_ text: String) -> Int {
        let t = Array(text.utf16)
        var i = 0
        var n = 0
        while i < t.count {
            if t[i] == 0x25 && i + 3 < t.count && t[i + 1] >= 0x30 && t[i + 1] <= 0x39 && t[i + 2] == 0x24 && t[i + 3] == 0x73 {
                n += 1
                i += 4
            } else {
                i += 1
            }
        }
        return n
    }

    /// First placeholder-free entry (table order) whose pattern matches the whole text → (entry, []); else among the
    /// templates matching the whole text the one with the longest template text (first on a tie) → (entry, groups).
    private static func match(_ entries: [Compiled], _ text: String) -> (Entry, [String])? {
        for c in entries where c.placeholders == 0 {
            if let re = c.regex, BILPublicDomainText.wholeMatch(re, text) != nil { return (c.entry, []) }
        }
        var best: (Entry, [String])?
        var bestLength = -1
        for c in entries where c.placeholders > 0 {
            guard let re = c.regex, let m = BILPublicDomainText.wholeMatch(re, text) else { continue }
            let length = c.entry.text.utf16.count
            guard length > bestLength else { continue }
            var groups: [String] = []
            if m.numberOfRanges > 1 {
                for g in 1..<m.numberOfRanges { groups.append(BILPublicDomainText.group(m, g, in: text)) }
            }
            best = (c.entry, groups)
            bestLength = length
        }
        return best
    }

    private static func exactActionId(_ a: String) -> String? {
        return actions.first { BILPublicDomainText.same($0.text, a) }?.id
    }

    private static func stripSafePrefix(_ a: String) -> String? {
        let units = Array(a.utf16)
        let prefix = Array(safePrefix.utf16)
        guard units.count >= prefix.count, Array(units[0..<prefix.count]) == prefix else { return nil }
        return String(decoding: units[prefix.count...], as: UTF16.self)
    }

    private static func actionKey(_ id: String) -> String {
        return "PublicProtocol.action." + id
    }
}

private extension BILPublicEngineVocabulary.Entry {
    /// Table shorthand (the memberwise initializer stays available).
    init(_ id: String, _ key: String, _ text: String, digitArgs: Set<Int> = []) {
        self.init(id: id, key: key, text: text, digitArgs: digitArgs)
    }
}
