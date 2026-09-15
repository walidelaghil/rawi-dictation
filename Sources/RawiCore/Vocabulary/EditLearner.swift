import Foundation

/// A word you fixed after Rawi typed it.
public struct Correction: Equatable, Sendable {
    public let heard: String
    public let fixed: String
    /// Whether `heard` is safe to replace on sight next time. Never an ordinary
    /// word: fixing "cloud" to "Claude" once must not rewrite every cloud.
    public let aliasable: Bool
}

/// Works out which words you corrected, from what Rawi typed and what the text
/// field says now.
///
/// This is how Wispr Flow's dictionary fills itself: it does not ask, it watches
/// you fix its spelling. Doing that needs Accessibility, which this Mac could
/// not grant when the dictionary was designed, so the spelling-inconsistency
/// learner stood in for it. With the permission, the real signal is available:
/// a correction is someone telling you the right spelling, once, explicitly.
///
/// Most edits are not spelling corrections, so almost everything is refused:
/// - words are aligned first, so an edit is only read between words that did
///   not change — text around the dictation is never mistaken for part of it
/// - only one word replaced by one word, and only when the two are close
///   ("Sala" → "Salla"), not a different word ("Tuesday" → "Friday")
/// - never an ordinary English word written in lower case: that is wording or
///   grammar ("their" → "there"), not vocabulary
/// - nothing at all if most of what was typed is gone, which is a rewrite
public enum EditLearner {
    /// Below this share of the dictation still in place, it was rewritten, and a
    /// rewrite is not evidence about spelling.
    static let minimumSurviving = 0.6

    /// `current` is the dictated stretch as it reads now — the watcher finds it by
    /// the field's own text on either side — so an edit at either end is as
    /// readable as one in the middle.
    public static func corrections(inserted: String, current: String,
                                   isOrdinaryWord: (String) -> Bool) -> [Correction] {
        let typed = words(inserted)
        let now = words(current)
        guard !typed.isEmpty, !now.isEmpty else { return [] }

        let matched = alignment(typed.map { $0.lowercased() }, now.map { $0.lowercased() })
        if typed.count >= 4 {
            guard Double(matched.count) / Double(typed.count) >= minimumSurviving else { return [] }
        } else {
            // Too short for a share to mean anything: only a word-for-word edit.
            guard typed.count == now.count else { return [] }
        }

        var found: [Correction] = []
        func consider(_ heard: String, _ fixed: String) {
            guard let correction = judge(heard: heard, fixed: fixed,
                                         isOrdinaryWord: isOrdinaryWord),
                  !found.contains(where: { $0.fixed == correction.fixed }) else { return }
            found.append(correction)
        }

        // The stretches between words that did not change, including before the
        // first and after the last.
        let bounds = [(-1, -1)] + matched + [(typed.count, now.count)]
        for (left, right) in zip(bounds, bounds.dropFirst()) {
            let typedGap = Array(typed[(left.0 + 1)..<right.0])
            let nowGap = Array(now[(left.1 + 1)..<right.1])
            // One for one, or a short run replaced word for word.
            guard typedGap.count == nowGap.count, (1...2).contains(typedGap.count) else { continue }
            for (heard, fixed) in zip(typedGap, nowGap) { consider(heard, fixed) }
        }
        // Aligned words whose case you changed: "salla" → "Salla".
        for (i, j) in matched where typed[i] != now[j] { consider(typed[i], now[j]) }
        return found
    }

    static func judge(heard: String, fixed: String,
                      isOrdinaryWord: (String) -> Bool) -> Correction? {
        guard heard != fixed, fixed.count >= 3, fixed.contains(where: \.isLetter) else { return nil }
        let heardLower = heard.lowercased(), fixedLower = fixed.lowercased()
        let fixedIsOrdinary = isOrdinaryWord(fixedLower)

        if heardLower == fixedLower {
            // Case only. Capitalising an ordinary word is sentence structure, not a
            // name: only a word the dictionary does not know earns it.
            guard !fixedIsOrdinary, fixed.first?.isUppercase == true else { return nil }
            return Correction(heard: heard, fixed: fixed, aliasable: false)
        }
        // Wording, not spelling.
        if fixedIsOrdinary && fixed == fixedLower { return nil }
        // Close enough to be the same word spelled differently.
        let longest = max(heardLower.count, fixedLower.count)
        let allowance = max(2, longest / 2)
        guard TermCorrector.editDistance(heardLower, fixedLower) <= allowance,
              heardLower.first == fixedLower.first
                || TermCorrector.editDistance(heardLower, fixedLower) <= 1 else { return nil }
        return Correction(heard: heard, fixed: fixed, aliasable: !isOrdinaryWord(heardLower))
    }

    static func words(_ text: String) -> [String] {
        text.split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "'" || $0 == "’") })
            .map(String.init)
    }

    /// Longest common subsequence, as index pairs in order.
    static func alignment(_ a: [String], _ b: [String]) -> [(Int, Int)] {
        let n = a.count, m = b.count
        var table = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                table[i][j] = a[i] == b[j] ? table[i + 1][j + 1] + 1
                                           : max(table[i + 1][j], table[i][j + 1])
            }
        }
        var pairs: [(Int, Int)] = []
        var i = 0, j = 0
        while i < n, j < m {
            if a[i] == b[j] { pairs.append((i, j)); i += 1; j += 1 }
            else if table[i + 1][j] >= table[i][j + 1] { i += 1 }
            else { j += 1 }
        }
        return pairs
    }
}
