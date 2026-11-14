import Foundation

/// Puts a blank line where the speaker changed the subject.
///
/// Not by understanding the subject — by listening for the words people say when
/// they are about to change it. "Separately", "another thing", "by the way": a
/// speaker announces a topic change out loud, because their listener cannot see
/// the paragraph break they would have typed.
///
/// This was a model's job for exactly one benchmark. Asking qwen2.5:1.5b for
/// paragraph breaks made it delete the very word that marked the change, and made
/// qwen2.5:3b stop applying Arabic corrections. A rule this mechanical does not
/// need a model, and a model this small should not be asked.
public enum SpokenParagraphs {
    /// Openers that announce a new subject. Matched at the start of a sentence
    /// only: "separately" mid-sentence is an adverb doing ordinary work.
    static let openers = [
        "separately", "on another note", "another thing", "one more thing",
        "one last thing", "moving on", "next topic", "switching gears",
        "by the way", "on a different note", "changing the subject",
        "unrelated to that", "in other news",
        "بالمناسبة", "شيء آخر", "موضوع آخر", "على فكرة", "بخصوص موضوع آخر",
    ]

    /// Sentences per paragraph beyond which a break is welcome anyway — but only at
    /// an opener, never mid-thought.
    public static func split(_ text: String) -> [String] {
        let sentences = sentencesOf(text)
        guard sentences.count > 1 else { return [text] }

        var paragraphs: [String] = []
        var current: [String] = []
        for (index, sentence) in sentences.enumerated() {
            // A break before the first sentence is not a break.
            if index > 0, opensATopic(sentence), !current.isEmpty {
                paragraphs.append(current.joined(separator: " "))
                current = []
            }
            current.append(sentence)
        }
        if !current.isEmpty { paragraphs.append(current.joined(separator: " ")) }
        // Nothing to break means nothing to rebuild. Handing back the original
        // string rather than a re-joined copy keeps this stage incapable of
        // changing spacing it was never asked to touch.
        return paragraphs.count > 1 ? paragraphs : [text]
    }

    /// Words that ride in front of an opener without changing it. People do not
    /// start a new subject on the exact words in the list above — they say "and
    /// by the way", "oh, one more thing", "so separately".
    static let leadIns = ["and", "so", "oh", "ok", "okay", "but", "well", "now",
                          "also", "anyway", "أه", "طيب", "يعني", "و"]

    /// Adverbs that intensify an opener without being part of it: "on a completely
    /// different note" is the same announcement as "on a different note".
    static let intensifiers = ["completely", "totally", "entirely", "wholly",
                               "slightly", "somewhat", "very", "quite", "rather"]

    static func opensATopic(_ sentence: String) -> Bool {
        var lower = sentence.lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: " \"'“”«»"))
        for lead in leadIns.sorted(by: { $0.count > $1.count }) where lower.hasPrefix(lead) {
            let rest = lower.dropFirst(lead.count)
            // Only when the lead-in is a word of its own: "sofa" does not begin
            // with "so" the way "so separately" does.
            guard let next = rest.first, !next.isLetter else { continue }
            lower = rest.trimmingCharacters(in: CharacterSet(charactersIn: " ,،-—"))
            break
        }
        for intensifier in intensifiers {
            lower = lower.replacingOccurrences(of: " \(intensifier) ", with: " ")
        }
        return openers.contains { lower.hasPrefix($0) }
    }

    /// Sentence boundaries, in both scripts' punctuation.
    static func sentencesOf(_ text: String) -> [String] {
        var sentences: [String] = []
        var current = ""
        let characters = Array(text)
        for (index, character) in characters.enumerated() {
            current.append(character)
            guard ".!?۔؟".contains(character) else { continue }
            // A full stop only ends a sentence when something follows it that could
            // start one. The period in "release 4.2" ends nothing, and splitting
            // there turned a version number into two sentences.
            let next = index + 1 < characters.count ? characters[index + 1] : " "
            guard next.isWhitespace else { continue }
            let trimmed = current.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { sentences.append(trimmed) }
            current = ""
        }
        let tail = current.trimmingCharacters(in: .whitespaces)
        if !tail.isEmpty { sentences.append(tail) }
        return sentences
    }
}

/// The written shape of what was said: paragraphs first, then lists inside them.
///
/// Order matters and only one order works. Lists add single line breaks and
/// paragraphs add double ones, and whichever runs second has to read around the
/// other's output — so paragraphs cut the text into blocks, and each block is
/// offered to the list formatter on its own, still as one line.
public enum SpokenStructure {
    public static func format(_ text: String) -> String {
        SpokenParagraphs.split(text)
            .map(SpokenLists.format)
            .joined(separator: "\n\n")
    }

    /// The same, with paragraphs already planned by idea (`IdeaParagraphs`). The
    /// spoken-opener rule still applies inside each one.
    ///
    /// A spoken list wins. "First…, second…, third…" spans exactly the sentences an
    /// idea planner puts in separate paragraphs, and cut apart, no piece has the
    /// two ordinals it takes to be a list.
    public static func format(_ text: String, ideas: [String]?) -> String {
        let plain = format(text)
        guard let ideas, ideas.count > 1 else { return plain }
        let hasList = SpokenParagraphs.split(text).contains { SpokenLists.format($0) != $0 }
        guard !hasList else { return plain }
        return ideas.flatMap(SpokenParagraphs.split)
            .map(SpokenLists.format)
            .joined(separator: "\n\n")
    }
}
