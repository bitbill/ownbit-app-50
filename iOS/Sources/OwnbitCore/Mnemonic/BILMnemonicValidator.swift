//  BILMnemonicValidator.swift — Ownbit core (extracted from Ownbit iOS 5.x).
//  Copyright (c) 2017-2026 BITTOOL PTE. LTD.
//  SPDX-License-Identifier: MIT
//
//  Offline BIP39 mnemonic validation, as the app's import page does it before calling the JS: normalization (tabs,
//  newlines, ideographic space, lowercase, unspaced Chinese split per character), word-list membership, word count,
//  checksum, over the 8 word lists of mnemonic_words.txt (8 consecutive blocks of 2048 lines). Pure Foundation +
//  CryptoKit, nothing logged.
//  mnemonic_words.txt is read from `JSBridge.resourceBundle` (flat, `bitcoinjs-lib-bridge/` or `js/bitcoinjs-lib-bridge/`).

import Foundation
import CryptoKit

/// Order == order of the 8 consecutive 2048-line blocks of mnemonic_words.txt
public enum BILMnemonicLanguage: Int, CaseIterable {
    case english = 0
    case chineseSimplified
    case japanese
    case chineseTraditional
    case spanish
    case korean
    case french
    case italian
}

public enum BILMnemonicIssue: Equatable {
    case empty
    case invalidWords([String])
    case invalidCount(Int)
    case invalidChecksum
    case wordlistUnavailable
}

public struct BILMnemonicCheckResult {
    /// words joined by a single space, lowercased
    public let normalized: String
    public let words: [String]
    /// words that are not part of the wordlist (input order, duplicates removed)
    public let invalidWords: [String]
    /// language whose checksum passed; otherwise the best matching language; nil if unknown
    public let language: BILMnemonicLanguage?
    public let issue: BILMnemonicIssue?

    public var isValid: Bool {
        return issue == nil
    }
}

public final class BILMnemonicValidator {

    /// Loaded from `JSBridge.resourceBundle` on first access. Immutable after init, so it can be used from any thread.
    /// FAIL CLOSED: when the word list can't be read, every check() reports .wordlistUnavailable (and the next access
    /// tries to load it again, e.g. after the host set `JSBridge.resourceBundle`).
    public static var shared: BILMnemonicValidator {
        sharedLock.lock()
        defer { sharedLock.unlock() }
        if let validator = sharedValidator {
            return validator
        }
        let resource = JSBridge.Resource(name: "mnemonic_words", ext: "txt", directory: "bitcoinjs-lib-bridge")
        guard let url = JSBridge.resourceURL(resource), let data = try? Data(contentsOf: url),
              let contents = String(data: data, encoding: .utf8) else {
            return BILMnemonicValidator(wordlistText: "")
        }
        let validator = BILMnemonicValidator(wordlistText: contents)
        if validator.isLoaded {
            sharedValidator = validator
        }
        return validator
    }
    private static var sharedValidator: BILMnemonicValidator?
    private static let sharedLock = NSLock()

    public static let validWordCounts: Set<Int> = [12, 15, 18, 21, 24]

    private static let wordsPerLanguage = 2048

    /// 8 lists of 2048 words, index == BILMnemonicLanguage.rawValue. Empty when not loaded.
    private let wordLists: [[String]]
    /// word -> 11-bit index, per language
    private let wordIndexes: [[String: Int]]
    /// every word of every language
    private let allWords: Set<String>

    /// true only when exactly 8*2048 lines were loaded
    public let isLoaded: Bool

    /// `wordlistText` == content of mnemonic_words.txt (LF or CRLF line endings).
    public init(wordlistText: String) {
        let languageCount = BILMnemonicLanguage.allCases.count
        let perLanguage = BILMnemonicValidator.wordsPerLanguage

        //"\r\n" is ONE Character in Swift, isNewline covers \n, \r, \r\n
        let lines = wordlistText.split(whereSeparator: { $0.isNewline }).compactMap { (line) -> String? in
            let word = line.trimmingCharacters(in: BILMnemonicValidator.trimSet)
            return word.isEmpty ? nil : word
        }

        var lists = [[String]]()
        var indexes = [[String: Int]]()
        var all = Set<String>()
        var loaded = lines.count == languageCount * perLanguage

        if loaded {
            for language in 0 ..< languageCount {
                let list = Array(lines[(language * perLanguage) ..< ((language + 1) * perLanguage)])
                var map = [String: Int](minimumCapacity: perLanguage)
                for (index, word) in list.enumerated() {
                    map[word] = index
                }
                //a duplicated word inside one block means the file is damaged
                guard map.count == perLanguage else {
                    loaded = false
                    break
                }
                lists.append(list)
                indexes.append(map)
                all.formUnion(list)
            }
        }

        if loaded {
            wordLists = lists
            wordIndexes = indexes
            allWords = all
        } else {
            wordLists = []
            wordIndexes = []
            allWords = []
        }
        isLoaded = loaded
    }

    // MARK: - Normalize

    /// whitespace + BOM, used to clean wordlist lines
    private static let trimSet: CharacterSet = {
        var set = CharacterSet.whitespacesAndNewlines
        set.insert(charactersIn: "\u{FEFF}")
        return set
    }()

    /// \t \n \r, U+3000 (Japanese separator) and any other unicode blank all count as a separator
    private static func isSeparator(_ scalar: Unicode.Scalar) -> Bool {
        return CharacterSet.whitespacesAndNewlines.contains(scalar) || scalar.value == 0x3000 || scalar.value == 0xFEFF
    }

    private static func isHan(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x4E00 ... 0x9FFF,     //CJK Unified Ideographs
             0x3400 ... 0x4DBF,     //Extension A
             0xF900 ... 0xFAFF,     //Compatibility Ideographs
             0x20000 ... 0x2FA1F:   //Extension B... + Compatibility Supplement
            return true
        default:
            return false
        }
    }

    private func tokens(_ raw: String) -> [String] {
        var spaced = String.UnicodeScalarView()
        var allHan = true
        var hasContent = false
        for scalar in raw.unicodeScalars {
            if BILMnemonicValidator.isSeparator(scalar) {
                spaced.append(" ")
            } else {
                spaced.append(scalar)
                hasContent = true
                if allHan, !BILMnemonicValidator.isHan(scalar) {
                    allHan = false
                }
            }
        }
        guard hasContent else {
            return []
        }

        let pieces = String(spaced).lowercased().split(separator: " ", omittingEmptySubsequences: true)
        if allHan {
            //Chinese mnemonics are typed without spaces: one character == one word
            return pieces.flatMap { $0.map { String($0) } }
        }
        return pieces.map { String($0) }
    }

    public func normalize(_ raw: String) -> String {
        return tokens(raw).joined(separator: " ")
    }

    // MARK: - Check

    /// in ANY of the 8 lists
    public func contains(_ word: String) -> Bool {
        guard isLoaded else {
            return false
        }
        let tokenList = tokens(word)
        guard tokenList.count == 1 else {
            return false
        }
        return allWords.contains(tokenList[0])
    }

    /// issue precedence: wordlistUnavailable > empty > invalidWords > invalidCount > invalidChecksum
    public func check(_ raw: String) -> BILMnemonicCheckResult {
        let words = tokens(raw)
        let normalized = words.joined(separator: " ")

        func result(invalidWords: [String] = [], language: BILMnemonicLanguage? = nil, issue: BILMnemonicIssue?) -> BILMnemonicCheckResult {
            return BILMnemonicCheckResult(normalized: normalized, words: words, invalidWords: invalidWords, language: language, issue: issue)
        }

        guard isLoaded else {
            return result(issue: .wordlistUnavailable)
        }
        guard !words.isEmpty else {
            return result(issue: .empty)
        }

        //per language: how many of the words it knows
        var matchCounts = [Int](repeating: 0, count: wordIndexes.count)
        for word in words {
            for (language, map) in wordIndexes.enumerated() where map[word] != nil {
                matchCounts[language] += 1
            }
        }
        //languages that contain ALL words (simplified / traditional Chinese overlap)
        let candidates = matchCounts.indices.filter { matchCounts[$0] == words.count }

        var invalidWords = uniqued(words.filter { !allWords.contains($0) })
        if invalidWords.isEmpty, candidates.isEmpty {
            //every word exists somewhere but the phrase mixes languages:
            //report the words that do not belong to the dominant language
            var dominant = 0
            for language in matchCounts.indices where matchCounts[language] > matchCounts[dominant] {
                dominant = language
            }
            invalidWords = uniqued(words.filter { wordIndexes[dominant][$0] == nil })
            return result(invalidWords: invalidWords, language: BILMnemonicLanguage(rawValue: dominant), issue: .invalidWords(invalidWords))
        }

        //first language that knows every word, else the one that knows most of them
        var bestGuess = candidates.first.flatMap { BILMnemonicLanguage(rawValue: $0) }
        if bestGuess == nil, let most = matchCounts.max(), most > 0, let dominant = matchCounts.firstIndex(of: most) {
            bestGuess = BILMnemonicLanguage(rawValue: dominant)
        }

        guard invalidWords.isEmpty else {
            return result(invalidWords: invalidWords, language: bestGuess, issue: .invalidWords(invalidWords))
        }
        guard BILMnemonicValidator.validWordCounts.contains(words.count) else {
            return result(language: bestGuess, issue: .invalidCount(words.count))
        }

        for language in candidates where checksumPasses(words: words, language: language) {
            return result(language: BILMnemonicLanguage(rawValue: language), issue: nil)
        }
        return result(language: bestGuess, issue: .invalidChecksum)
    }

    private func uniqued(_ list: [String]) -> [String] {
        var seen = Set<String>()
        return list.filter { seen.insert($0).inserted }
    }

    /// Standard BIP39: 11 bits per word, last ENT/32 bits == first bits of SHA256(entropy)
    private func checksumPasses(words: [String], language: Int) -> Bool {
        let map = wordIndexes[language]
        let totalBits = words.count * 11
        let checksumBits = totalBits / 33
        let entropyBytes = (totalBits - checksumBits) / 8
        guard checksumBits > 0, checksumBits <= 8 else {
            return false
        }

        var bytes = [UInt8](repeating: 0, count: (totalBits + 7) / 8)
        var bitOffset = 0
        for word in words {
            guard let index = map[word] else {
                return false
            }
            for bit in 0 ..< 11 {
                if (index >> (10 - bit)) & 1 == 1 {
                    bytes[bitOffset / 8] |= UInt8(0x80 >> (bitOffset % 8))
                }
                bitOffset += 1
            }
        }

        //ENT is a multiple of 32 bits, so the checksum starts on a byte boundary
        guard entropyBytes < bytes.count else {
            return false
        }
        let shift = UInt8(8 - checksumBits)
        let expected = bytes[entropyBytes] >> shift
        var firstHashByte: UInt8 = 0
        for byte in SHA256.hash(data: Data(bytes[0 ..< entropyBytes])) {
            firstHashByte = byte
            break
        }
        return (firstHashByte >> shift) == expected
    }

    // MARK: - Helpers

    /// lowercase prefix match within the english block, wordlist order
    public func englishSuggestions(prefix: String, limit: Int) -> [String] {
        guard isLoaded, limit > 0 else {
            return []
        }
        let lowercasedPrefix = prefix.trimmingCharacters(in: BILMnemonicValidator.trimSet).lowercased()
        guard !lowercasedPrefix.isEmpty else {
            return []
        }
        var suggestions = [String]()
        for word in wordLists[BILMnemonicLanguage.english.rawValue] where word.hasPrefix(lowercasedPrefix) {
            suggestions.append(word)
            if suggestions.count >= limit {
                break
            }
        }
        return suggestions
    }

    /// Separators accepted by looksLikeMnemonic on top of whitespace ("abandon,abandon,..." / "的、一、是").
    private static let looseSeparators: CharacterSet = {
        var set = CharacterSet.whitespacesAndNewlines
        set.insert(charactersIn: ",;\u{FF0C}\u{FF1B}\u{3001}\u{3002}\u{3000}\u{FEFF}")
        return set
    }()

    /// A payload containing any of these is JSON / URI / base64 / key-value data, never a bare recovery phrase.
    private static let structuredPayloadCharacters = CharacterSet(charactersIn: "{}[]\"'/\\=_@<>|&%$^~+*?")
    /// 24 numbered, comma separated words stay well below this.
    private static let looseMaxLength = 600

    /// Like tokens(), but also splits on , ; and strips digits / punctuation around every piece ("1." "abandon," "#3:").
    private func looseTokens(_ raw: String) -> [String] {
        let nonLetters = CharacterSet.letters.inverted
        let pieces = raw.lowercased().components(separatedBy: BILMnemonicValidator.looseSeparators).compactMap { (piece) -> String? in
            let word = piece.trimmingCharacters(in: nonLetters)
            return word.isEmpty ? nil : word
        }
        let allHan = !pieces.contains { $0.unicodeScalars.contains { !BILMnemonicValidator.isHan($0) } }
        if allHan {
            return pieces.flatMap { $0.map { String($0) } }
        }
        return pieces
    }

    /// Used to avoid echoing a scanned / pasted recovery phrase back to the screen; false if the wordlist is unavailable.
    /// Deliberately tolerant (a false positive only hides a payload, a false negative shows a recovery phrase):
    /// >= 12 tokens AND (>= 11 consecutive wordlist words OR >= 80% wordlist words). Numbering ("1. abandon 2. ..."),
    /// comma separated lists, one typo or an appended passphrase must not turn the echo back on.
    public func looksLikeMnemonic(_ raw: String) -> Bool {
        guard isLoaded else {
            return false
        }
        // The QR scanner uses this on every non-import entry point: offline-signing / multisig / WalletConnect JSON and
        // URIs often contain BIP39 words such as "index" "value" "amount" and would match once punctuation is stripped.
        // A mnemonic QR code never contains these structural characters and is never this long.
        guard raw.count <= BILMnemonicValidator.looseMaxLength,
              raw.rangeOfCharacter(from: BILMnemonicValidator.structuredPayloadCharacters) == nil else {
            return false
        }
        let words = looseTokens(raw)
        guard words.count >= 12 else {
            return false
        }
        var validCount = 0
        var run = 0
        var longestRun = 0
        for word in words {
            if allWords.contains(word) {
                validCount += 1
                run += 1
                longestRun = max(longestRun, run)
            } else {
                run = 0
            }
        }
        return longestRun >= 11 || validCount * 5 >= words.count * 4
    }
}
