import Foundation

/// Whether a transcript has anything for the polisher to do.
///
/// Polishing costs about half a second of GPU, and the GPU is shared with the next
/// dictation's transcription, so the cost is paid twice. The gate is therefore the
/// cleanup gate plus one thing: a transcript can be perfectly punctuated, properly
/// capitalised, free of filler — and still contain "no wait, Tuesday". That is the
/// case the old gate skipped and the whole reason polishing exists.
public enum PolishNeeded {
    /// Phrases people use to take back what they just said.
    static let corrections = [
        "actually no", "actually not", "no wait", "wait no", "i mean", "i meant",
        "scratch that", "sorry i mean", "sorry no", "no sorry", "or rather",
        "let me rephrase", "let me say that again", "strike that",
        "لا لا", "عفوا", "أقصد", "لا أقصد", "بالعكس",
    ]

    public static func check(_ raw: String) -> Bool {
        if CleanupNeeded.check(raw) { return true }
        let lower = raw.lowercased()
        return corrections.contains { lower.contains($0) }
    }
}
