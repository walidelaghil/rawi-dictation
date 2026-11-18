import Foundation

/// Keeps a transcript once when a decoder has said all of it twice.
///
/// Only the whole text repeating counts: "A. B. A. B." becomes "A. B.", but "A. A.
/// and then B." is left as it is. And only when the repeated block is at least
/// three words, because "No. No." is something a person says.
public enum RepeatedTranscript {
    static let minimumWords = 3

    public static func collapse(_ text: String) -> String {
        let sentences = split(text)
        let count = sentences.count
        guard count >= 2 else { return text }
        let keys = sentences.map { key($0) }
        for period in 1...(count / 2) where count % period == 0 {
            let block = Array(keys[0..<period])
            let repeats = (0..<count).allSatisfy { keys[$0] == block[$0 % period] }
            guard repeats else { continue }
            let words = block.reduce(0) { $0 + $1.split(separator: " ").count }
            guard words >= minimumWords else { return text }
            return sentences[0..<period].joined(separator: " ")
        }
        return text
    }

    /// Sentences with their own punctuation kept, so the survivor reads as spoken.
    private static func split(_ text: String) -> [String] {
        var out: [String] = []
        var current = ""
        for character in text {
            current.append(character)
            if ".?!؟".contains(character) {
                out.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                current = ""
            }
        }
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { out.append(tail) }
        return out
    }

    private static func key(_ sentence: String) -> String {
        sentence.lowercased()
            .unicodeScalars.filter { CharacterSet.letters.union(.decimalDigits)
                .union(.whitespaces).contains($0) }
            .map(String.init).joined()
            .split(separator: " ").joined(separator: " ")
    }
}
