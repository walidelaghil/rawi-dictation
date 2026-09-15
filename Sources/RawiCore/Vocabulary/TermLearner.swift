import Foundation

/// A term Rawi decided to learn, and the evidence it decided on.
public struct LearnedTerm: Sendable, Equatable, Identifiable {
    public var id: String { term.lowercased() }
    public let term: String
    public let occurrences: Int
    /// Distinct days it was heard on. Repetition over time is the signal;
    /// repetition inside one sitting is one story told once.
    public let days: Int

    /// How many ways whisper spelled it. Two or more is the reason it is here.
    public let spellings: Int

    public var note: String {
        "heard \(occurrences) times on \(days) day\(days == 1 ? "" : "s"), "
        + "\(spellings) spellings"
    }

    public init(term: String, occurrences: Int, days: Int, spellings: Int = 2) {
        self.term = term
        self.occurrences = occurrences
        self.days = days
        self.spellings = spellings
    }
}

/// Builds the dictionary from what you actually say, without asking.
///
/// The rule is not "a word you say often". Everything you say often recurs, which
/// is how "database" and "actually" ended up in a dictionary meant for names and
/// jargon. A dictionary term exists to fix a word whisper gets *wrong*, and the
/// evidence that it is getting one wrong is that it spells it differently from one
/// dictation to the next: Salla, Sala, Sallah. A word it spells the same way every
/// time is not a problem to solve, whatever it is.
///
/// That test is also language-agnostic, which matters here: no word list was ever
/// going to cover English and Arabic, and the spell checker on this machine
/// already "knows" Kandji and Notion because it learned them from typing.
///
/// Every other rule errs toward learning nothing. `TermCorrector` rewrites
/// near-misses into whatever is promoted, so a wrong term actively corrupts text
/// that was already right.
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
                             blocked: [String],
                             isOrdinaryWord: (String) -> Bool = SpellCheck.isOrdinaryEnglish)
        -> [LearnedTerm] {
        let knownLower = Set(known.map { $0.term.lowercased() })
        let blockedLower = Set(blocked.map { $0.lowercased() })

        var counts: [String: Int] = [:]                  // spelling -> times heard
        var days: [String: Set<String>] = [:]            // spelling -> days heard on
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        for entry in entries {
            let day = formatter.string(from: entry.at)
            // The raw transcript: the whole question is what whisper produced,
            // before cleanup smoothed any of it over.
            // Shape only at this stage. The near-common-word fence comes later,
            // because a misspelling like "Sala" is exactly the evidence that
            // whisper is getting "Salla" wrong — filtering it out here left one
            // spelling behind and nothing to learn from.
            for word in tokenize(entry.raw) where hasTermShape(word) {
                counts[word, default: 0] += 1
                days[word, default: []].insert(day)
            }
        }

        var used = Set<String>()
        var learned: [LearnedTerm] = []
        // Strongest first, so a cluster forms around the spelling you use most.
        for spelling in counts.keys.sorted(by: { (counts[$0] ?? 0) > (counts[$1] ?? 0) }) {
            guard !used.contains(spelling) else { continue }
            // Transitive: Sala is a variant of Salah, Salah of Sallah, so all three
            // are one word heard three ways. Stopping at direct neighbours split
            // them into pairs and each pair looked like it had a clear favourite.
            var cluster: Set<String> = [spelling]
            var frontier = [spelling]
            while let current = frontier.popLast() {
                for candidate in counts.keys
                where !cluster.contains(candidate) && !used.contains(candidate)
                    && areVariants(current, candidate) {
                    cluster.insert(candidate)
                    frontier.append(candidate)
                }
            }
            used.formUnion(cluster)

            let distinct = Set(cluster.map { $0.lowercased() })
            // One spelling is one spelling, however often you said it.
            guard distinct.count >= 2 else { continue }
            // Two real words are two words, not one word heard two ways. "billing"
            // and "building" are two letters apart, and treating them as spellings
            // of one term taught the corrector to turn every building into billing.
            // A garble leaves a non-word behind; without one there is no evidence.
            let latin = cluster.filter { ScriptDetector.detect($0) == .latin }
            if !latin.isEmpty, latin.allSatisfy({ isOrdinaryWord($0.lowercased()) }) { continue }

            let occurrences = cluster.reduce(0) { $0 + (counts[$1] ?? 0) }
            let dayCount = Set(cluster.flatMap { days[$0] ?? [] }).count
            guard occurrences >= minimumOccurrences, dayCount >= minimumDays else { continue }

            // The spelling to enforce has to be one that is safe to enforce, so
            // the confusable ones are taken out before the vote rather than after
            // it. Ties break alphabetically, so the same history always learns the
            // same term.
            let enforceable = cluster
                .filter { ScriptDetector.detect($0) != .latin
                          || !isNearCommonWord($0.lowercased()) }
                .sorted {
                    (counts[$0] ?? 0) == (counts[$1] ?? 0)
                        ? $0 < $1
                        : (counts[$0] ?? 0) > (counts[$1] ?? 0)
                }
            guard let dominant = enforceable.first else { continue }
            // An ordinary word written in lower case is never a term, whatever its
            // neighbours look like: enforcing "actually" rewrites "actual". A
            // capitalised one may be a name — Notion is a word and a product.
            if ScriptDetector.detect(dominant) == .latin, dominant == dominant.lowercased(),
               isOrdinaryWord(dominant) { continue }
            let dominantCount = counts[dominant] ?? 0
            // Without a favourite we would be guessing which spelling you meant,
            // and enforcing a guess is worse than enforcing nothing.
            guard Double(dominantCount) / Double(occurrences) >= 0.4 else { continue }
            guard !knownLower.contains(dominant.lowercased()),
                  !blockedLower.contains(dominant.lowercased()) else { continue }

            learned.append(LearnedTerm(term: dominant, occurrences: occurrences,
                                       days: dayCount, spellings: distinct.count))
        }

        return learned
            .sorted {
                $0.occurrences == $1.occurrences
                    ? $0.term.lowercased() < $1.term.lowercased()
                    : $0.occurrences > $1.occurrences
            }
            .prefix(limit)
            .map { $0 }
    }

    /// Whether two spellings are close enough to be the same word heard twice.
    /// Same first letter, because "report" and "support" are not variants of each
    /// other however close the rest gets.
    static func areVariants(_ a: String, _ b: String) -> Bool {
        let x = a.lowercased(), y = b.lowercased()
        if x == y { return true }
        guard x.first == y.first else { return false }
        let allowance = min(x.count, y.count) <= 5 ? 1 : 2
        guard abs(x.count - y.count) <= allowance else { return false }
        return CommonWords.editDistance(x, y, cap: allowance) <= allowance
    }

    /// The shape of something that could be a term at all: long enough to be a
    /// word, no digits, not ordinary English.
    static func hasTermShape(_ word: String) -> Bool {
        guard word.count >= 4 else { return false }
        guard word.rangeOfCharacter(from: .decimalDigits) == nil else { return false }
        return !stopwords.contains(word.lowercased())
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
