import Foundation

/// Turns what a transcription engine returns into what you dictated.
///
/// Both engines need this and only one of them had it, which is how dictation
/// started arriving in several short lines: whisper segments long speech and
/// `whisper-server` returns those segments separated by newlines, while the
/// command-line path had always joined them. Nobody dictating a sentence wants it
/// delivered as four.
public enum Transcript {
    public static func clean(_ raw: String) -> String {
        var text = raw
        // Whisper narrates its own silences: [BLANK_AUDIO], (wind blowing), and
        // similar. They are annotations about the recording, not words you said.
        for pattern in [#"\[[^\]]*\]"#, #"\([^)]*\)"#] {
            text = text.replacingOccurrences(of: pattern, with: " ",
                                             options: [.regularExpression])
        }
        return text
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
