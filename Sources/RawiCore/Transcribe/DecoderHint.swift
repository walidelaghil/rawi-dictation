import Foundation

/// Decides whether the dictionary is worth whispering to the decoder.
///
/// `--prompt` primes whisper with text it pretends it just transcribed, so the
/// decoder continues in that vein. That is the whole trick, and it is also the
/// danger: prime an Arabic recording with Latin words and the decoder can decide
/// the speech ended early. Measured on `large-v3-turbo-q5_0`, one Arabic
/// recording, temperature 0:
///
///   - no hint                 → both sentences, verbatim
///   - hint `"Salla, Kandji"`  → both sentences, verbatim
///   - hint `"Rawi"`           → the second sentence gone, replaced by a word
///                               nobody said
///
/// Half a dictation, silently, from a dictionary entry the speaker added for an
/// unrelated reason. Nothing downstream can recover it — the words never reach
/// the app at all.
///
/// The hint was never the mechanism: `TermCorrector` is what actually enforces a
/// spelling, in code that cannot decline. So when the hint cannot help, it does
/// not get to run the risk.
public enum DecoderHint {
    /// Arabic speech is not spelled any better by Latin terms, and can be spelled
    /// far worse. A hint is offered only when it is written in the script being
    /// spoken.
    public static func usable(_ prompt: String, forLanguage language: String) -> Bool {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        // "auto" means the model decides, and there is no script to compare with.
        // The hint is kept: dropping it would lose the dictionary on every Mac
        // that has no language detector installed.
        guard isArabic(language) else { return true }
        return ScriptDetector.detect(trimmed) == .arabic
    }

    /// The hint to send, which is sometimes none.
    public static func filtered(_ prompt: String, forLanguage language: String) -> String {
        usable(prompt, forLanguage: language) ? prompt : ""
    }

    static func isArabic(_ language: String) -> Bool {
        let code = language.lowercased().prefix(2)
        return code == "ar"
    }
}
