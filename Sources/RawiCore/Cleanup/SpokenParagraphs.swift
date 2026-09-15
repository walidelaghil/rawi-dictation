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

    static func opensATopic(_ sentence: String) -> Bool {
        let lower = sentence.lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: " \"'“”«»"))
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
}
