import Foundation

/// A term Rawi decided to learn, and the evidence it decided on.
public struct LearnedTerm: Sendable, Equatable, Identifiable {
    public var id: String { term.lowercased() }
    public let term: String
    public let occurrences: Int
    /// Distinct days it was heard on. Repetition over time is the signal;
    /// repetition inside one sitting is one story told once.
    public let days: Int

    public var note: String {
        "heard \(occurrences) times on \(days) day\(days == 1 ? "" : "s")"
    }
}

/// Builds the dictionary from what you actually say, without asking.
///
/// The earlier design asked you to confirm each term. That is maintenance work
/// handed back to the user for a job the app can do itself — so it now promotes
/// terms on evidence and shows you what it learned, rather than a queue of
/// decisions to make.
///
/// Every rule here errs toward learning nothing. A dictionary term is not a
/// suggestion: `TermCorrector` rewrites near-misses into it, so a wrong term
/// actively corrupts text that was already right. The bar is therefore high, and
/// the refusals below matter more than the promotions.
public enum TermLearner {
    /// How much evidence before a word becomes a term.
    public static let minimumOccurrences = 4
    public static let minimumDays = 2
    /// The whisper prompt has a budget and the corrector's cost grows with the
    /// list, so only the best-evidenced terms are kept.
    public static let limit = 12

    /// Words too ordinary to ever be a dictionary term. The near-common-word fence
    /// catches most of these anyway; this is the cheap first pass.
    private static let stopwords: Set<String> = [
        "about", "after", "again", "also", "another", "because", "been", "before",
        "being", "between", "both", "could", "does", "doing", "done", "down",
        "each", "every", "from", "have", "here", "into", "just", "like", "make",
        "more", "most", "much", "need", "next", "only", "other", "over", "same",
        "should", "some", "still", "such", "than", "that", "them", "then", "there",
        "these", "they", "thing", "think", "this", "those", "through", "time",
        "very", "want", "well", "were", "what", "when", "which", "while", "will",
        "with", "would", "your", "yours", "today", "tomorrow", "please", "thanks",
        "going", "know", "look", "made", "many", "back", "good", "work", "working",
    ]


    static func tokenize(_ text: String) -> [String] {
        text.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
    }

    public static func learn(from entries: [HistoryEntry],
                             known: [DictionaryTerm],
                             blocked: [String]) -> [LearnedTerm] {
        let knownLower = Set(known.map { $0.term.lowercased() })
        let blockedLower = Set(blocked.map { $0.lowercased() })

        var spellings: [String: [String: Int]] = [:]     // lowered -> spelling -> count
        var days: [String: Set<String>] = [:]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        for entry in entries {
            let day = formatter.string(from: entry.at)
            // The raw transcript: a word whisper keeps mangling is the one worth
            // learning, and cleanup may already have hidden it.
            for word in tokenize(entry.raw) {
                let lower = word.lowercased()
                guard isCandidate(word, lower: lower),
                      !knownLower.contains(lower),
                      !blockedLower.contains(lower) else { continue }
                spellings[lower, default: [:]][word, default: 0] += 1
                days[lower, default: []].insert(day)
            }
        }

        return spellings.compactMap { lowered, variants -> LearnedTerm? in
            let occurrences = variants.values.reduce(0, +)
            let dayCount = days[lowered]?.count ?? 0
            guard occurrences >= minimumOccurrences, dayCount >= minimumDays else { return nil }
            // The spelling you used most is the spelling that gets enforced.
            guard let spelling = variants.max(by: {
                $0.value == $1.value ? $0.key < $1.key : $0.value < $1.value
            })?.key else { return nil }
            return LearnedTerm(term: spelling, occurrences: occurrences, days: dayCount)
        }
        .sorted {
            $0.occurrences == $1.occurrences
                ? $0.term.lowercased() < $1.term.lowercased()
                : $0.occurrences > $1.occurrences
        }
        .prefix(limit)
        .map { $0 }
    }

    /// The shape of something that could be a term at all.
    private static func isCandidate(_ word: String, lower: String) -> Bool {
        guard word.count >= 4 else { return false }
        guard word.rangeOfCharacter(from: .decimalDigits) == nil else { return false }
        guard !stopwords.contains(lower) else { return false }
        // Latin words get one more test the others do not need: English is where
        // the corrector's edit-distance rules bite.
        guard ScriptDetector.detect(word) != .latin || !isNearCommonWord(lower) else {
            return false
        }
        return true
    }

    /// Refuses anything the corrector could confuse with ordinary language.
    ///
    /// This is the rule that makes automatic learning safe to ship. Learn "Sals"
    /// and every "sale", "salt" and "sails" you dictate afterwards is silently
    /// rewritten into it. A term that cannot be told apart from a common word is
    /// not worth having, however often it is said.
    static func isNearCommonWord(_ lower: String) -> Bool {
        if CommonWords.contains(lower) { return true }
        let allowance = lower.count <= 5 ? 1 : 2
        return CommonWords.within(distance: allowance, of: lower)
    }
}
