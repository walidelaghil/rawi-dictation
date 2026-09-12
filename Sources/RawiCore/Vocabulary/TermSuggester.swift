import Foundation

public struct TermSuggestion: Sendable, Equatable, Identifiable {
    public var id: String { token }
    public let token: String
    public let occurrences: Int
    /// Appeared capitalised mid-sentence — the shape of a proper noun, which is
    /// what whisper mangles and what belongs in a dictionary.
    public let looksLikeName: Bool
}

/// Proposes dictionary terms from words that keep recurring in your own history.
///
/// This is *suggestion*, not learning. The approved design said terms would be
/// learned automatically after you corrected the same word twice — but observing
/// you edit inserted text needs the Accessibility API, which cannot be granted on
/// a managed Mac. Recurrence is the signal that is actually available, and you
/// confirm it with one click.
public enum TermSuggester {
    /// Words too ordinary to ever be dictionary terms.
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

    public static func suggestions(from entries: [HistoryEntry],
                                   known: [DictionaryTerm],
                                   minimumOccurrences: Int = 3,
                                   limit: Int = 8) -> [TermSuggestion] {
        let knownLower = Set(known.map { $0.term.lowercased() })
        var counts: [String: Int] = [:]
        var capitalised: Set<String> = []

        for entry in entries {
            // The raw transcript, not the cleaned text: a word whisper keeps
            // mangling is the one worth adding, and cleanup may have hidden it.
            let words = tokenize(entry.raw)
            for (index, word) in words.enumerated() {
                let lower = word.lowercased()
                guard word.count >= 4,
                      !stopwords.contains(lower),
                      !knownLower.contains(lower),
                      word.rangeOfCharacter(from: .decimalDigits) == nil
                else { continue }
                counts[lower, default: 0] += 1
                if index > 0, let first = word.first, first.isUppercase {
                    capitalised.insert(lower)
                }
            }
        }

        return counts
            .filter { $0.value >= minimumOccurrences }
            .map { TermSuggestion(token: $0.key, occurrences: $0.value,
                                  looksLikeName: capitalised.contains($0.key)) }
            // Proper-noun shape first, then by how often it recurs.
            .sorted {
                if $0.looksLikeName != $1.looksLikeName { return $0.looksLikeName }
                if $0.occurrences != $1.occurrences { return $0.occurrences > $1.occurrences }
                return $0.token < $1.token
            }
            .prefix(limit)
            .map { $0 }
    }

    static func tokenize(_ text: String) -> [String] {
        text.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
    }
}
