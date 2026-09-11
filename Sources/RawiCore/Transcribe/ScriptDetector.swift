import Foundation

public enum Script: String, Sendable, Equatable, Codable {
    case latin, arabic
}

/// Decides which script a transcript is written in, so cleanup can be routed to a
/// model that will not mangle it.
///
/// This exists because of a measured failure, not a preference: `qwen2.5:1.5b`
/// silently *translates* Arabic into English and cannot be instructed out of it —
/// it was told explicitly and ignored the instruction. Routing has to happen
/// before the model sees the text, which means it cannot involve a model.
///
/// The decision is a **ratio**, not "contains any Arabic", because the normal
/// bilingual sentence is mixed in both directions:
///
///   - `"يعني الـ API مو شغال، لازم نسوي deploy"` is mostly Arabic carrying Latin
///     technical terms, and must route to the Arabic-capable model.
///   - `"The Arabic word for narrator is راوي"` is English quoting one Arabic
///     word, and must not.
public enum ScriptDetector {
    /// Unicode blocks that count as Arabic script.
    private static let arabicRanges: [ClosedRange<UInt32>] = [
        0x0600...0x06FF,   // Arabic
        0x0750...0x077F,   // Arabic Supplement
        0x08A0...0x08FF,   // Arabic Extended-A
        0xFB50...0xFDFF,   // Arabic Presentation Forms-A
        0xFE70...0xFEFF,   // Arabic Presentation Forms-B
    ]

    private static func isArabic(_ scalar: Unicode.Scalar) -> Bool {
        arabicRanges.contains { $0.contains(scalar.value) }
    }

    /// Fraction of the *letters* in `text` that are Arabic script, 0...1.
    /// Digits, punctuation and whitespace are ignored, so a timestamp or a
    /// percentage cannot tip the balance either way.
    public static func arabicRatio(_ text: String) -> Double {
        var letters = 0
        var arabic = 0
        for character in text where character.isLetter {
            letters += 1
            if character.unicodeScalars.contains(where: isArabic) { arabic += 1 }
        }
        guard letters > 0 else { return 0 }
        return Double(arabic) / Double(letters)
    }

    /// Arabic when Arabic-script letters make up at least `threshold` of the
    /// letters present. Text with no letters at all is Latin — there is nothing
    /// to clean, and Latin is the cheaper, more faithful route.
    public static func detect(_ text: String, threshold: Double = 0.15) -> Script {
        arabicRatio(text) >= threshold ? .arabic : .latin
    }
}
