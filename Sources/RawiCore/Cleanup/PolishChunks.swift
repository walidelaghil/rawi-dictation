import Foundation

/// Splits a long dictation into pieces small enough for the rewriter to be
/// trusted with.
///
/// A local model's faithfulness falls off with length, and it falls off quietly:
/// it does not refuse or truncate, it returns fluent text with a sentence of
/// yours missing. Measured on one 101-word transcript, qwen2.5:3b with the polish
/// prompt returned 82 words and had dropped the opening sentence entirely. The
/// same transcript, the same model, the same prompt, fed a sentence at a time:
/// 93 words and every sentence present.
///
/// So above a certain length the rewrite is done in pieces. Each piece is guarded
/// on its own, which turns "most of your words survived" from something measured
/// afterwards into something the shape of the work guarantees — a sentence cannot
/// vanish from a request that contained only it.
///
/// Pieces are several sentences long rather than one, because a spoken correction
/// often spans a boundary: "Monday. No wait, Tuesday." has to meet the model as
/// one piece or the correction cannot be applied.
public enum PolishChunks {
    /// Below this many words, the whole dictation goes at once. Short input is
    /// where the model is reliable, and one request keeps every correction in
    /// reach of the words it corrects.
    public static let threshold = 55
    /// What each piece aims for. Not a limit: a sentence is never split.
    public static let target = 40

    public static func split(_ text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard words(in: trimmed) > threshold else { return [trimmed] }

        let sentences = SpokenParagraphs.sentencesOf(trimmed)
        guard sentences.count > 1 else { return [trimmed] }

        var pieces: [String] = []
        var current: [String] = []
        var count = 0
        for sentence in sentences {
            current.append(sentence)
            count += words(in: sentence)
            if count >= target {
                pieces.append(current.joined(separator: " "))
                current = []
                count = 0
            }
        }
        if !current.isEmpty {
            // A stray tail joins the piece before it rather than meeting the model
            // alone, where a fragment reads like something to answer.
            if let last = pieces.popLast() {
                pieces.append(last + " " + current.joined(separator: " "))
            } else {
                pieces.append(current.joined(separator: " "))
            }
        }
        return pieces.isEmpty ? [trimmed] : pieces
    }

    static func words(in text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }
}
