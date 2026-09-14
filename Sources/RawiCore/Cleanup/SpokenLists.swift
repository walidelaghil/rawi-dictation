import Foundation

/// Turns a spoken enumeration into a written list.
///
/// "…what we need to do is first focus on the customer, second identify the pain,
/// third develop the solution" is a list. Everyone who says it means a list, and
/// everyone who types it types a list. Dictation that hands back one long sentence
/// has heard the words and missed the shape.
///
/// This is deliberately not the cleanup model's job. Cleanup is told to preserve
/// every clause and never reorder, because a small local model asked to "improve
/// structure" starts inventing — and the transcript that prompted this fix never
/// reached the model anyway: it was already punctuated and capitalised, so
/// `CleanupNeeded` skipped it. Structure that only appears when the GPU is free
/// and the model is in the mood is not a feature. So it lives here, in code that
/// cannot decline, beside the dictionary and the snippets.
///
/// Nothing is invented: every word you said survives, the ordinal becomes the
/// numeral it already was, and the line breaks go where you paused.
public enum SpokenLists {
    /// Ordinals that mean "here comes the next item", in both languages Rawi hears.
    static let ordinals: [String: Int] = [
        "first": 1, "firstly": 1, "second": 2, "secondly": 2, "third": 3,
        "thirdly": 3, "fourth": 4, "fourthly": 4, "fifth": 5, "fifthly": 5,
        "sixth": 6, "seventh": 7, "eighth": 8, "ninth": 9, "tenth": 10,
        "أولا": 1, "أولاً": 1, "ثانيا": 2, "ثانياً": 2, "ثالثا": 3, "ثالثاً": 3,
        "رابعا": 4, "رابعاً": 4, "خامسا": 5, "خامساً": 5, "سادسا": 6, "سادساً": 6,
    ]

    /// An ordinal after one of these is counting a noun, not the items in a list:
    /// "the first day", "my second attempt". Nothing here ever precedes an
    /// enumeration, so the whole class can be refused at once.
    static let determiners: Set<String> = [
        "the", "a", "an", "my", "our", "your", "his", "her", "their", "its",
        "this", "that", "these", "those", "every", "each", "any", "some", "no",
        "another", "one", "next", "last", "whose", "which",
    ]

    /// Words a speaker puts before the next item that the written list does not need.
    static let leadIns: Set<String> = ["and", "then", "also", "next", "so", "plus", "ثم", "و"]

    /// The shortest thing worth calling a list. One "first" is a word; two in
    /// sequence is a structure.
    static let minimumItems = 2

    public static func format(_ text: String) -> String {
        // Already laid out — by the user, by a snippet, or by a previous run.
        guard !text.contains("\n") else { return text }

        let tokens = tokenize(text)
        let cues = cueRun(in: tokens)
        guard cues.count >= minimumItems else { return text }

        let intro = String(text[text.startIndex..<cues[0].start])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var items: [String] = []
        for (index, cue) in cues.enumerated() {
            let end = index + 1 < cues.count ? cues[index + 1].start : text.endIndex
            let item = tidy(String(text[cue.end..<end]))
            // An empty item means this was not the structure it looked like.
            guard !item.isEmpty else { return text }
            items.append(item)
        }

        var lines: [String] = []
        if !intro.isEmpty { lines.append(introducing(intro)) }
        for (index, item) in items.enumerated() { lines.append("\(index + 1). \(item)") }
        return lines.joined(separator: "\n")
    }

    // MARK: - Finding the run

    private struct Cue { let value: Int; let start: String.Index; let end: String.Index }

    private struct Token { let word: String; let start: String.Index; let end: String.Index }

    private static func tokenize(_ text: String) -> [Token] {
        var tokens: [Token] = []
        var index = text.startIndex
        while index < text.endIndex {
            guard text[index].isLetter || text[index].isNumber else {
                index = text.index(after: index); continue
            }
            let start = index
            while index < text.endIndex, text[index].isLetter || text[index].isNumber {
                index = text.index(after: index)
            }
            tokens.append(Token(word: String(text[start..<index]).lowercased(),
                                start: start, end: index))
        }
        return tokens
    }

    /// The ordinals that actually count: starting at one and climbing by one.
    ///
    /// Starting at one matters. A dictation that says "second" without ever saying
    /// "first" is talking about something, not enumerating it, and a list that
    /// opens at item 2 is worse than no list at all.
    private static func cueRun(in tokens: [Token]) -> [Cue] {
        var run: [Cue] = []
        for (index, token) in tokens.enumerated() {
            guard let value = ordinals[token.word] else { continue }
            if index > 0, determiners.contains(tokens[index - 1].word) { continue }
            // The ordinal has to be followed by the item it introduces.
            guard index + 1 < tokens.count else { continue }

            if value == 1 {
                // A later "first" starts a new list only if the current one never began.
                if run.isEmpty { run = [Cue(value: 1, start: token.start, end: token.end)] }
            } else if value == run.count + 1 {
                run.append(Cue(value: value, start: token.start, end: token.end))
            }
        }
        return run
    }

    // MARK: - Shaping the pieces

    /// One item, without the joins that only exist in speech.
    ///
    /// The joins sit on both ends: "we ship it, and secondly we tell them" leaves
    /// a dangling "and" on item one and nothing on item two. Both get trimmed, and
    /// trimming one can expose another ("it, and" -> "it," -> "it"), so it repeats
    /// until there is nothing left to take.
    static func tidy(_ raw: String) -> String {
        var words = raw.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        var changed = true
        while changed, !words.isEmpty {
            changed = false
            for end in [false, true] {
                guard let candidate = end ? words.last : words.first else { continue }
                let bare = candidate.lowercased()
                    .trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
                if bare.isEmpty || leadIns.contains(bare) {
                    end ? words.removeLast() : words.removeFirst()
                    changed = true
                }
            }
        }
        var item = words.joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,;:،"))

        // A fragment does not need a full stop; a sentence keeps the one it has.
        let isFragment = !item.dropLast().contains(where: { ".!?۔؟".contains($0) })
        if isFragment, let last = item.last, ".،,".contains(last) { item.removeLast() }

        return capitalizingFirst(item.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// The words before the list become its lead-in, and a lead-in ends in a colon.
    static func introducing(_ intro: String) -> String {
        var line = intro.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:"))
        if let last = line.last, ".!?۔؟".contains(last) { return line }
        line.append(":")
        return line
    }

    /// Only Latin has a capital to give; Arabic is left exactly as it was.
    static func capitalizingFirst(_ s: String) -> String {
        guard let first = s.first, first.isLowercase, first.isLetter else { return s }
        return first.uppercased() + s.dropFirst()
    }
}
