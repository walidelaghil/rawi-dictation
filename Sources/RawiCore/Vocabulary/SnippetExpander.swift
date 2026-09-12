import Foundation

public enum SnippetExpander {
    /// Expands spoken triggers into their values.
    ///
    /// Runs **after** cleanup and after `CleanupGuard`, so neither can mangle an
    /// expanded URL or address, and so an expansion can never be mistaken for the
    /// model rewriting your words.
    ///
    /// Single pass by design: an expansion that contains another trigger is not
    /// re-expanded, because that is how you get a loop.
    public static func expand(_ text: String, with snippets: [Snippet]) -> String {
        guard !snippets.isEmpty, !text.isEmpty else { return text }

        // Longest trigger first, so "my work email" wins over "my email".
        let ordered = snippets.sorted { $0.trigger.count > $1.trigger.count }
        var result = text
        var consumed: [Range<String.Index>] = []

        for snippet in ordered {
            let trigger = snippet.trigger.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trigger.isEmpty else { continue }
            var searchFrom = result.startIndex
            while let found = result.range(of: trigger, options: [.caseInsensitive],
                                           range: searchFrom..<result.endIndex) {
                guard isWholePhrase(found, in: result),
                      !consumed.contains(where: { $0.overlaps(found) }) else {
                    searchFrom = found.upperBound
                    if searchFrom >= result.endIndex { break }
                    continue
                }
                result.replaceSubrange(found, with: snippet.expansion)
                let end = result.index(found.lowerBound, offsetBy: snippet.expansion.count)
                consumed.append(found.lowerBound..<end)
                searchFrom = end
                if searchFrom >= result.endIndex { break }
            }
        }
        return result
    }

    /// A trigger must sit on word boundaries — saying "email" inside "emailing"
    /// is not saying the trigger.
    private static func isWholePhrase(_ range: Range<String.Index>, in text: String) -> Bool {
        if range.lowerBound > text.startIndex {
            let before = text[text.index(before: range.lowerBound)]
            if before.isLetter || before.isNumber { return false }
        }
        if range.upperBound < text.endIndex {
            let after = text[range.upperBound]
            if after.isLetter || after.isNumber { return false }
        }
        return true
    }
}
