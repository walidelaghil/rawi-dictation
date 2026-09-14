import Foundation

/// Refuses a rewrite written in a language nobody asked for.
///
/// Asked to translate into Arabic, qwen2.5:3b answered in Chinese — it is an
/// Alibaba model, and under-instructed it goes home. Measured: the same request
/// produced 50 Han characters and no Arabic at all, with the strict prompt as well
/// as the loose one. The model was replaced, but a guard costs nothing and the next
/// model will have a home of its own.
///
/// This is `CleanupGuard`'s sibling, and the same rule applies: the clipboard keeps
/// what it had rather than taking something wrong.
public enum ScriptGuard {
    public enum Verdict: Equatable {
        case accept
        case reject(String)
    }

    /// A script that is more than this share of the output, while being absent from
    /// the input, is the model wandering off rather than translating.
    static let strayShare = 0.05
    /// A translation may leave product names in Latin, but not half the text.
    static let residueShare = 0.4

    /// `instruction` is what makes this judgeable: translation is *supposed* to
    /// introduce a script the input never had, so the target has to come from what
    /// was asked rather than from what arrived.
    public static func check(input: String, output: String,
                             instruction: String = "") -> Verdict {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .reject("nothing came back") }

        let outputCounts = counts(in: trimmed)
        let total = outputCounts.values.reduce(0, +)
        guard total > 0 else { return .reject("no words came back") }

        let target = requestedScript(in: instruction)
        // Allowed: whatever the input already used, plus whatever was asked for.
        var allowed = scripts(in: input)
        if let target { allowed.insert(target) }

        for (script, count) in outputCounts where !allowed.contains(script) {
            if Double(count) / Double(total) > strayShare {
                return .reject("answered in \(script.name), which was not asked for")
            }
        }

        // Asked for a language and mostly did not use it: half a translation is not
        // a translation, and it is worse than none because it looks finished.
        if let target {
            let share = Double(outputCounts[target] ?? 0) / Double(total)
            if share < 1 - residueShare {
                return .reject("only part of it came back in \(target.name)")
            }
        }
        return .accept
    }

    /// The script a language name implies. Only the languages a transform is likely
    /// to name; anything unrecognised means "no target", and the guard falls back to
    /// "do not wander out of the input's scripts".
    static func requestedScript(in instruction: String) -> Script? {
        let lower = instruction.lowercased()
        let table: [(String, Script)] = [
            ("arabic", .arabic), ("العربية", .arabic), ("عربي", .arabic),
            ("chinese", .han), ("mandarin", .han), ("japanese", .han),
            ("russian", .cyrillic), ("ukrainian", .cyrillic),
            ("english", .latin), ("french", .latin), ("spanish", .latin),
            ("german", .latin), ("italian", .latin), ("portuguese", .latin),
            ("dutch", .latin), ("turkish", .latin), ("indonesian", .latin),
        ]
        for (name, script) in table where lower.contains(name) { return script }
        return nil
    }

    enum Script: Hashable {
        case latin, arabic, han, cyrillic, other

        var name: String {
            switch self {
            case .latin: "Latin"
            case .arabic: "Arabic"
            case .han: "Chinese"
            case .cyrillic: "Cyrillic"
            case .other: "another script"
            }
        }
    }

    static func script(of character: Character) -> Script? {
        guard let scalar = character.unicodeScalars.first, character.isLetter else { return nil }
        switch scalar.value {
        case 0x0041...0x024F: return .latin
        case 0x0600...0x06FF, 0x0750...0x077F, 0xFB50...0xFDFF: return .arabic
        case 0x4E00...0x9FFF, 0x3400...0x4DBF, 0x3040...0x30FF: return .han
        case 0x0400...0x04FF: return .cyrillic
        default: return .other
        }
    }

    static func counts(in text: String) -> [Script: Int] {
        var counts: [Script: Int] = [:]
        for character in text {
            if let script = script(of: character) { counts[script, default: 0] += 1 }
        }
        return counts
    }

    static func scripts(in text: String) -> Set<Script> {
        let counts = counts(in: text)
        let total = counts.values.reduce(0, +)
        guard total > 0 else { return [] }
        // A stray character in the input does not license a whole answer in it.
        return Set(counts.filter { Double($0.value) / Double(total) > 0.02 }.keys)
    }
}
