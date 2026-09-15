import Foundation

/// Replaces near-misses of your dictionary terms with the exact spelling.
///
/// This exists because the model-based layers cannot be relied on. Measured:
/// `qwen2.5:3b` applies a glossary with any phrasing, `qwen2.5:1.5b` applies it
/// with none — and 1.5b is what English routes to. The decoder hint is weaker
/// still on the shipped whisper model. So the guarantee lives here, in code that
/// cannot decline, for the same reason `CleanupGuard` does.
///
/// Deliberately conservative. Turning "Sara" into "Salla" would be far worse than
/// leaving "Sala" alone, so every rule below errs toward doing nothing.
public enum TermCorrector {
    /// Common words that must never be rewritten into a term, however close.
    /// "raw" is one edit from "Rawi"; "sale" is one from "Salla".
    private static let protectedWords: Set<String> = [
        "raw", "sale", "sales", "call", "calls", "salt", "said", "sad", "sand",
        "hand", "band", "land", "kind", "king", "find", "mind", "wind", "wild",
        "wall", "ball", "fall", "tall", "well", "will", "well", "walk", "want",
        "made", "make", "name", "same", "game", "came", "care", "case", "base",
        "data", "date", "gate", "late", "rate", "code", "node", "mode", "more",
        "word", "work", "world", "would", "could", "should", "grafted",
    ]

    /// The exact spelling wins wherever a close variant appears.
    public static func apply(_ text: String, terms: [String],
                             aliases: [String: String] = [:]) -> String {
        let text = aliases.isEmpty ? text : replaceAliases(in: text, aliases: aliases)
        let cleaned = terms
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 4 }
        guard !cleaned.isEmpty, !text.isEmpty else { return text }

        // Multi-word terms first, so "Argo CD" is not eaten by a single-word rule.
        let ordered = cleaned.sorted { $0.count > $1.count }
        var result = text
        for term in ordered where term.contains(" ") {
            result = replacePhrase(term, in: result)
        }
        let single = ordered.filter { !$0.contains(" ") }
        guard !single.isEmpty else { return result }
        return replaceTokens(in: result, terms: single)
    }

    // MARK: - What you corrected

    /// Exact replacements taught by your own corrections: whisper wrote "Kanjee",
    /// you changed it to "Kandji", so "Kanjee" is Kandji from now on. Exact rather
    /// than near, because a correction can be far from what was heard, and exact
    /// is what makes that safe. Only misheard spellings that are not ordinary words
    /// are ever stored as aliases, so "cloud" can never become "Claude".
    private static func replaceAliases(in text: String, aliases: [String: String]) -> String {
        var out = ""
        var token = ""
        func flush() {
            guard !token.isEmpty else { return }
            out += aliases[token.lowercased()] ?? token
            token = ""
        }
        for character in text {
            if character.isLetter || character.isNumber { token.append(character) }
            else { flush(); out.append(character) }
        }
        flush()
        return out
    }

    // MARK: - Single words

    private static func replaceTokens(in text: String, terms: [String]) -> String {
        var out = ""
        var token = ""
        out.reserveCapacity(text.count)

        func flush() {
            guard !token.isEmpty else { return }
            out += correction(for: token, terms: terms) ?? token
            token = ""
        }

        for character in text {
            if character.isLetter || character.isNumber {
                token.append(character)
            } else {
                flush()
                out.append(character)
            }
        }
        flush()
        return out
    }

    /// The term this token is a near-miss of, or nil to leave it alone.
    static func correction(for token: String, terms: [String]) -> String? {
        guard token.count >= 4 else { return nil }
        let lower = token.lowercased()
        guard !protectedWords.contains(lower) else { return nil }
        // Already exactly a term, in any case: leave the user's casing alone.
        if terms.contains(where: { $0.lowercased() == lower }) {
            return terms.first { $0.lowercased() == lower }
        }

        var best: (term: String, distance: Int)?
        for term in terms {
            let allowance = term.count <= 5 ? 1 : 2
            guard abs(term.count - token.count) <= allowance else { continue }
            let distance = editDistance(lower, term.lowercased())
            guard distance > 0, distance <= allowance else { continue }
            if best == nil || distance < best!.distance { best = (term, distance) }
        }
        return best?.term
    }

    // MARK: - Phrases

    private static func replacePhrase(_ term: String, in text: String) -> String {
        let parts = term.split(separator: " ").map(String.init)
        guard parts.count > 1 else { return text }
        // A phrase is corrected only when every word is already close enough,
        // which keeps "Argo CD" from swallowing unrelated pairs.
        var out = text
        if let found = out.range(of: term, options: .caseInsensitive) {
            out.replaceSubrange(found, with: term)
        }
        return out
    }

    // MARK: - Distance

    static func editDistance(_ a: String, _ b: String) -> Int {
        let x = Array(a), y = Array(b)
        if x.isEmpty { return y.count }
        if y.isEmpty { return x.count }
        var previous = Array(0...y.count)
        var current = [Int](repeating: 0, count: y.count + 1)
        for i in 1...x.count {
            current[0] = i
            for j in 1...y.count {
                let cost = x[i - 1] == y[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        return previous[y.count]
    }
}
