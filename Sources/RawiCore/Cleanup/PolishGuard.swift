import Foundation

/// Sanity-checks a polished rewrite before it is typed into your document.
///
/// `CleanupGuard` cannot do this job. It demands that 70% of the dictated words
/// survive, which is the right rule for a cleaner and the wrong one for a rewrite:
/// applying "Monday, no wait, Tuesday" is *supposed* to lose words, and turning
/// speech into sentences is supposed to change them.
///
/// So the question is reversed. Not "did your words survive" but "is anything here
/// that you did not say" — which is the failure that matters, because a rewrite
/// that quietly invents a date or a number is worse than no rewrite at all.
public enum PolishGuard {
    public enum Verdict: Equatable, Sendable {
        case accept
        case reject(reason: String)
    }

    /// Words a rewrite is entitled to introduce: the joinery of written English
    /// that speech leaves out. Nothing here can carry a fact.
    static let connectives: Set<String> = [
        "that", "this", "these", "those", "then", "than", "with", "from", "have",
        "been", "were", "will", "would", "should", "could", "also", "because",
        "which", "while", "when", "what", "they", "them", "their", "there", "into",
        "about", "after", "before", "does", "need", "needs", "needing", "make",
        "makes", "make", "want", "wants", "your", "ours", "here", "some", "such",
        "very", "just", "only", "more", "most", "well", "each", "both", "over",
    ]

    /// How much of the rewrite may be words the dictation does not account for.
    /// Measured on real transcripts: an honest rewrite introduced one unfamiliar
    /// word in twenty. A fifth is far past that and still well short of a sentence
    /// the model made up.
    static let maxInventedShare = 0.2
    /// Below this the rewrite is a summary, not a rewrite.
    static let minLengthRatio = 0.45
    /// Above it, the model is padding — or answering.
    static let maxLengthRatio = 1.6
    /// Ratios mean nothing on a short dictation: punctuating and un-abbreviating
    /// "we ship monday, test tuesday" can honestly add half its length again. Below
    /// this many characters of difference, the ratio does not get a vote.
    static let lengthSlack = 40
    /// Stems this long identify a word across its inflections without colliding.
    static let stemLength = 4

    public static func check(raw: String, polished: String) -> Verdict {
        let trimmed = polished.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .reject(reason: "polish returned nothing") }

        // A rewrite stays in the language it was dictated in. Measured: gemma3:4b
        // silently answers clean Arabic in English.
        if case .reject(let why) = ScriptGuard.check(input: raw, output: trimmed) {
            return .reject(reason: why)
        }

        let ratio = Double(trimmed.count) / Double(max(raw.count, 1))
        let drift = abs(trimmed.count - raw.count)
        if ratio < minLengthRatio, drift > lengthSlack {
            return .reject(reason: String(format: "rewrite is %.0f%% of what was said",
                                          ratio * 100))
        }
        if ratio > maxLengthRatio, drift > lengthSlack {
            return .reject(reason: String(format: "rewrite is %.0f%% longer than what was said",
                                          (ratio - 1) * 100))
        }

        let spokenStems = Set(significantWords(raw).map(stem))
        let written = significantWords(trimmed)
        guard !written.isEmpty else { return .accept }
        // No floor on how short a rewrite has to be before this check applies. A
        // three-word answer is where the worst failure lives: "what is the capital
        // of France" coming back as "The capital of France is Paris."
        let invented = written.filter { !connectives.contains($0) && !spokenStems.contains(stem($0)) }
        let share = Double(invented.count) / Double(written.count)
        if share > maxInventedShare {
            return .reject(reason: "\(Int(share * 100))% of the rewrite is words that "
                                 + "were not dictated (\(invented.prefix(3).joined(separator: ", ")))")
        }
        return .accept
    }

    static func stem(_ word: String) -> String { String(word.prefix(stemLength)) }

    /// Words long enough to carry meaning. Short ones are grammar, and grammar is
    /// exactly what a rewrite is allowed to change.
    static func significantWords(_ s: String) -> [String] {
        s.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" })
            .map(String.init)
            .filter { $0.count >= stemLength }
    }
}
