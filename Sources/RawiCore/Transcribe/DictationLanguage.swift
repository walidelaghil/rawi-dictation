import Foundation

/// Which language a dictation should be transcribed as.
///
/// Detection is right nearly always and wrong occasionally, and when it is wrong
/// it is wrong expensively: Arabic heard as English does not come back accented,
/// it comes back as unrelated English words. That is unrecoverable downstream, so
/// the answer is not a better detector but a way to say it yourself.
public enum DictationLanguage: String, Codable, Sendable, CaseIterable, Equatable {
    /// Let the detector decide, which is what it does unless told otherwise.
    case auto
    case english
    case arabic

    /// What whisper is told. `nil` means "work it out".
    public var whisperCode: String? {
        switch self {
        case .auto: nil
        case .english: "en"
        case .arabic: "ar"
        }
    }

    /// The label on the pill. Two characters, because the pill has no room for
    /// more and every reader of either language knows these two.
    public var badge: String {
        switch self {
        case .auto: "Auto"
        case .english: "En"
        case .arabic: "Ar"
        }
    }

    public var spokenName: String {
        switch self {
        case .auto: "Detect the language"
        case .english: "Always English"
        case .arabic: "Always Arabic"
        }
    }
}
