import Foundation

/// The one line in the sidebar that says where your words go.
///
/// It used to read "Stays on this Mac · No account, no upload, no sync" whatever
/// the settings said, which stopped being true the moment transcription moved to
/// Groq. A privacy claim that is wrong some of the time is worse than none.
public enum PrivacyNote {
    public static func describe(_ config: Config) -> (title: String, detail: String) {
        let speech: String? = switch config.engine {
        case .whispercpp: nil
        case .groq: "Groq"
        case .openai: "OpenAI"
        }
        let text: String? = switch config.cleanup.provider {
        case .off, .ollama: nil
        case .groq: "Groq"
        case .openai: "OpenAI"
        case .anthropic: "Anthropic"
        }
        switch (speech, text) {
        case (nil, nil):
            return ("Stays on this Mac", "No account, no upload, no sync")
        case let (speech?, text?) where speech == text:
            return ("Voice and text go to \(speech)", "History stays on this Mac. No account, no sync")
        case let (speech?, text?):
            return ("Voice to \(speech), text to \(text)", "History stays on this Mac. No account, no sync")
        case let (speech?, nil):
            return ("Voice goes to \(speech)", "History stays on this Mac. No account, no sync")
        case let (nil, text?):
            return ("Text goes to \(text)", "Voice and history stay on this Mac")
        }
    }
}
