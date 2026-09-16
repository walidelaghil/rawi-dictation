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
    /// Latin only — see `stem(_:)` for why Arabic cannot use a prefix.
    static let stemLength = 4
    /// A dictated sentence with at least this many words of its own is substantial
    /// enough that losing it is a failure rather than an applied correction.
    /// Below it sits the false start a rewrite is *supposed* to delete: "no wait,
    /// scratch that" is three words and none of them survive on purpose.
    static let sentenceFloor = 5
    /// How much of such a sentence has to reach the rewrite. Deliberately low:
    /// this is a net for a sentence that is *gone*, not a rule about how much a
    /// rewrite may tighten. A retraction the speaker dictated at length ("forget
    /// what I said about the offsite dates") still leaves a word or two behind,
    /// and applying it is the feature working.
    static let minSentenceSurvival = 0.2

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

        // A rewrite applies the corrections you spoke; it does not drop a sentence
        // you meant. The ratios above cannot see that: losing the second of two
        // sentences still leaves more than half the characters, which the floor is
        // happy with. Measured — qwen2.5:3b deleted a whole Arabic sentence, put an
        // invented word where it had been, and passed every check above.
        let writtenStems = Set(written.map(stem))
        for sentence in SpokenParagraphs.sentencesOf(raw) {
            let own = significantWords(sentence).filter { !connectives.contains($0) }
            guard own.count >= sentenceFloor else { continue }
            let survived = own.filter { writtenStems.contains(stem($0)) }.count
            if Double(survived) / Double(own.count) < minSentenceSurvival {
                return .reject(reason: "a sentence you dictated is missing from the rewrite")
            }
        }
        return .accept
    }

    /// What identifies a word across the endings it can take.
    ///
    /// English inflects at the end, so its first four characters are the word and
    /// the rest is grammar. Arabic does the opposite: it attaches the article and
    /// the prepositions to the *front*, so four characters can be all grammar and
    /// no word — "بالمناسبة" (by the way) and "بالمتحزبين" (a word nobody said)
    /// share every one of them. That collision is how a model once deleted a
    /// dictated sentence and had the invented word replacing it counted as
    /// something the speaker had said. Arabic is therefore compared whole, after
    /// the prefixes and the spellings that vary freely are normalised away.
    static func stem(_ word: String) -> String {
        isArabic(word) ? arabicStem(word) : String(word.prefix(stemLength))
    }

    static func isArabic(_ word: String) -> Bool {
        word.unicodeScalars.contains { (0x0600...0x06FF).contains($0.value) }
    }

    /// Diacritics dropped, the letters that are written both ways folded together,
    /// and the proclitics peeled off — but only while a real word is left, so
    /// short words are never shaved down into each other.
    static func arabicStem(_ word: String) -> String {
        var out = ""
        for scalar in word.unicodeScalars {
            switch scalar.value {
            case 0x064B...0x0652, 0x0640, 0x0670: continue   // harakat, tatweel
            case 0x0622, 0x0623, 0x0625, 0x0671: out.append("ا")
            case 0x0649: out.append("ي")
            case 0x0629: out.append("ه")
            case 0x0624: out.append("و")
            case 0x0626: out.append("ي")
            default: out.unicodeScalars.append(scalar)
            }
        }
        // Longest first: "وبال" before "بال" before "و".
        let proclitics = ["وبال", "فبال", "وال", "فال", "كال", "بال", "لل", "ال",
                          "و", "ف", "ب", "ك", "ل", "س"]
        var changed = true
        while changed {
            changed = false
            for clitic in proclitics where out.hasPrefix(clitic) {
                let rest = String(out.dropFirst(clitic.count))
                guard rest.count >= 3 else { continue }
                out = rest
                changed = true
                break
            }
        }
        return out
    }

    /// Words long enough to carry meaning. Short ones are grammar, and grammar is
    /// exactly what a rewrite is allowed to change.
    static func significantWords(_ s: String) -> [String] {
        s.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" })
            .map(String.init)
            .filter { $0.count >= stemLength }
    }
}
