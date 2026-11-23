import Foundation

/// Makes the English-restore pass safe to trust.
///
/// Speech engines write English words they hear inside Arabic speech in Arabic
/// letters (ميتنغ for "meeting"). A model is asked to put them back. This guard
/// accepts its answer only when the *only* change is an Arabic-script token turned
/// into a Latin one, with the same number of tokens in the same order. A
/// translation, a dropped or added word, or any other edit rejects the whole
/// answer, and the caller keeps the original text.
public enum EnglishRestoreGuard {
    public typealias Verdict = PolishGuard.Verdict

    public static func check(original: String, restored: String) -> Verdict {
        let before = original.split(whereSeparator: \.isWhitespace).map(String.init)
        let after = restored.split(whereSeparator: \.isWhitespace).map(String.init)
        guard before.count == after.count, !before.isEmpty else {
            return .reject(reason: "token count changed (\(before.count) -> \(after.count))")
        }
        for (a, b) in zip(before, after) where a != b {
            guard hasArabic(a) else { return .reject(reason: "a word that was not Arabic changed") }
            guard isRestoredLoanword(from: a, to: b) else {
                return .reject(reason: "a word changed into something other than English letters")
            }
        }
        return .accept
    }

    private static func isArabicScalar(_ s: Unicode.Scalar) -> Bool {
        (0x0600...0x06FF).contains(s.value)
    }

    private static func isLatinLetter(_ s: Unicode.Scalar) -> Bool {
        (0x41...0x5A).contains(s.value) || (0x61...0x7A).contains(s.value)
    }

    private static func hasArabic(_ word: String) -> Bool {
        word.unicodeScalars.contains(where: isArabicScalar)
    }

    /// The new token must contain English letters. Any Arabic left in it has to be
    /// a prefix of the old token (الميتنغ -> الmeeting), and punctuation stays put.
    private static func isRestoredLoanword(from old: String, to new: String) -> Bool {
        let scalars = Array(new.unicodeScalars)
        guard scalars.contains(where: isLatinLetter) else { return false }
        let oldScalars = Array(old.unicodeScalars)
        var i = 0
        while i < scalars.count, isArabicScalar(scalars[i]) { i += 1 }
        // Arabic prefix: must match the start of the old token exactly.
        guard i <= oldScalars.count, Array(scalars[0..<i]) == Array(oldScalars[0..<i]) else { return false }
        // Whatever follows must be Latin letters, digits and joiners, then
        // trailing punctuation shared with the old token.
        var end = scalars.count
        let oldTrailing = trailingPunctuation(oldScalars)
        if !oldTrailing.isEmpty, Array(scalars.suffix(oldTrailing.count)) == oldTrailing {
            end -= oldTrailing.count
        }
        let body = scalars[i..<end]
        guard !body.isEmpty else { return false }
        return body.allSatisfy { isLatinLetter($0) || ($0.properties.numericType != nil)
            || $0 == "-" || $0 == "'" || $0 == "_" || $0 == "." }
    }

    private static func trailingPunctuation(_ scalars: [Unicode.Scalar]) -> [Unicode.Scalar] {
        var out: [Unicode.Scalar] = []
        for s in scalars.reversed() {
            guard s.properties.generalCategory.isPunctuation else { break }
            out.insert(s, at: 0)
        }
        return out
    }
}

private extension Unicode.GeneralCategory {
    var isPunctuation: Bool {
        switch self {
        case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
             .initialPunctuation, .finalPunctuation, .otherPunctuation: true
        default: false
        }
    }
}
