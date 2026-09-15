import Foundation

/// What your dictations say about how you talk. Counted, not guessed: everything
/// here is a tally over history. The one written part is `VoiceProfile`.
public struct VoiceInsights: Sendable, Equatable {
    /// Your most repeated phrase, when one repeats enough to be a habit.
    public let catchphrase: String?
    public let mostUsedWord: String?
    /// The word Rawi's cleanup changed most often, filler aside.
    public let mostCorrectedWord: String?
    /// The filler you lean on, by how often cleanup took it out.
    public let filler: (word: String, count: Int)?
    public let peakDay: String?
    public let peakHour: Int?
    public let peakApp: String?
    public let longestDictationWords: Int
    public let words: Int

    public static func == (a: VoiceInsights, b: VoiceInsights) -> Bool {
        a.catchphrase == b.catchphrase && a.mostUsedWord == b.mostUsedWord
            && a.mostCorrectedWord == b.mostCorrectedWord && a.filler?.word == b.filler?.word
            && a.filler?.count == b.filler?.count && a.peakDay == b.peakDay && a.peakHour == b.peakHour
            && a.peakApp == b.peakApp && a.longestDictationWords == b.longestDictationWords && a.words == b.words
    }

    /// "Tuesday at 2 p.m."
    public var peakMoment: String? {
        guard let peakDay, let peakHour else { return nil }
        let hour12 = peakHour % 12 == 0 ? 12 : peakHour % 12
        return "\(peakDay) at \(hour12) \(peakHour < 12 ? "a.m." : "p.m.")"
    }

    static let stopwords: Set<String> = [
        "the", "a", "an", "and", "or", "but", "so", "to", "of", "in", "on", "at", "for", "with", "by",
        "is", "are", "was", "were", "be", "been", "it", "its", "it's", "this", "that", "these", "those",
        "i", "i'm", "you", "your", "we", "our", "they", "them", "he", "she", "me", "my", "us", "do",
        "does", "did", "have", "has", "had", "not", "no", "yes", "if", "then", "there", "here", "as",
        "from", "can", "will", "just", "what", "which", "who", "how", "when", "where", "all", "any",
        "also", "about", "into", "out", "up", "down", "than", "too", "very", "one", "some", "more",
        "don't", "let's", "okay", "ok", "like", "um", "uh", "really", "would", "could", "should",
        "في", "من", "على", "إلى", "الى", "عن", "مع", "هذا", "هذه", "ان", "أن", "إن", "و", "ما", "لا",
        "هو", "هي", "كان", "كل", "او", "أو", "ثم", "لو", "يعني", "بس", "انا", "أنا",
    ]

    static let fillers: Set<String> = ["um", "uh", "erm", "like", "actually", "basically", "literally",
                                       "so", "right", "well", "okay", "yeah", "يعني"]

    /// `taught` are the words you corrected Rawi into, newest first. A word you had
    /// to fix yourself is a truer "most corrected" than anything cleanup changed.
    public static func compute(from entries: [HistoryEntry], taught: [String] = [],
                               calendar: Calendar = .current) -> VoiceInsights {
        let spoken = entries.filter { $0.kind == .dictation }
        var wordCounts: [String: Int] = [:]
        var phrases: [String: (count: Int, dictations: Set<UUID>)] = [:]
        var changed: [String: Int] = [:]
        var removedFillers: [String: Int] = [:]
        var byMoment: [String: Int] = [:]
        var appAtMoment: [String: [String: Int]] = [:]
        var longest = 0, total = 0
        let weekday = DateFormatter()
        weekday.dateFormat = "EEEE"
        weekday.locale = Locale(identifier: "en_US")

        for entry in spoken {
            let tokens = EditLearner.words(entry.cleaned).map { $0.lowercased() }
            total += tokens.count
            longest = max(longest, tokens.count)
            for token in tokens where token.count >= 3 && !stopwords.contains(token)
                && !fillers.contains(token) && !token.allSatisfy(\.isNumber) {
                wordCounts[token, default: 0] += 1
            }
            for size in [3, 2] where tokens.count >= size {
                for start in 0...(tokens.count - size) {
                    let gram = Array(tokens[start..<(start + size)])
                    guard gram.contains(where: { !stopwords.contains($0) }),
                          !gram.allSatisfy({ stopwords.contains($0) || fillers.contains($0) }) else { continue }
                    let key = gram.joined(separator: " ")
                    var slot = phrases[key] ?? (0, [])
                    slot.count += 1
                    slot.dictations.insert(entry.id)
                    phrases[key] = slot
                }
            }
            // What cleanup took out or changed.
            if entry.raw != entry.cleaned {
                let before = EditLearner.words(entry.raw).map { $0.lowercased() }
                let after = EditLearner.words(entry.cleaned).map { $0.lowercased() }
                let kept = Set(EditLearner.alignment(before, after).map(\.0))
                for (index, word) in before.enumerated() where !kept.contains(index) {
                    if fillers.contains(word) { removedFillers[word, default: 0] += 1 }
                    else if word.count >= 3, !stopwords.contains(word) { changed[word, default: 0] += 1 }
                }
            }
            let hour = calendar.component(.hour, from: entry.at)
            let moment = "\(weekday.string(from: entry.at))|\(hour)"
            byMoment[moment, default: 0] += tokens.count
            if let app = entry.appName { appAtMoment[moment, default: [:]][app, default: 0] += 1 }
        }

        func top<T>(_ table: [String: T], by value: (T) -> Int, minimum: Int = 1) -> String? {
            table.filter { value($0.value) >= minimum }
                .max { value($0.value) == value($1.value) ? $0.key > $1.key : value($0.value) < value($1.value) }?.key
        }
        // A habit, not a coincidence: said at least three times, in at least two dictations.
        let habitual = phrases.filter { $0.value.count >= 3 && $0.value.dictations.count >= 2 }
        let catchphrase = habitual.max {
            let a = $0.value.count * $0.key.split(separator: " ").count
            let b = $1.value.count * $1.key.split(separator: " ").count
            return a == b ? $0.key > $1.key : a < b
        }?.key
        let peak = top(byMoment, by: { $0 })
        let parts = peak?.split(separator: "|")
        let fillerWord = top(removedFillers, by: { $0 })

        return VoiceInsights(
            catchphrase: catchphrase.map { $0.prefix(1).uppercased() + $0.dropFirst() },
            mostUsedWord: top(wordCounts, by: { $0 }, minimum: 2),
            mostCorrectedWord: taught.first ?? top(changed, by: { $0 }, minimum: 2),
            filler: fillerWord.map { ($0, removedFillers[$0] ?? 0) },
            peakDay: parts.map { String($0[0]) },
            peakHour: parts.flatMap { Int($0[1]) },
            peakApp: peak.flatMap { top(appAtMoment[$0] ?? [:], by: { $0 }) },
            longestDictationWords: longest, words: total)
    }
}

/// The written part of "Your voice": a short read of how you use dictation, by the
/// local model, from your own dictations. Stored sealed, since it is about you.
public struct VoiceProfile: Codable, Sendable, Equatable {
    public var archetype: String
    public var summary: String
    public var peak: String
    public var createdAt: Date
    public var wordsAtCreation: Int

    /// New words before the profile is written again. Frequent enough to follow
    /// how you change, rare enough that it is not rewritten every afternoon.
    public static let refreshEvery = 1_500
    /// Below this, there is not enough of you in the history to describe.
    public static let minimumWords = 300

    public func wordsUntilUpdate(currentWords: Int) -> Int {
        max(0, Self.refreshEvery - (currentWords - wordsAtCreation))
    }

    public static let systemPrompt = """
    You describe how one person uses voice dictation, from a sample of what they \
    dictated and a few counts. Reply with a single JSON object and nothing else:
    {"archetype": "two or three words in Title Case naming the role their voice plays, like Insightful Clarifier or Decisive Delegator",
     "summary": "two short sentences, under 45 words in all, in the second person, about what they use their voice for and how they phrase things",
     "peak": "one short sentence, under 18 words, about when and where they dictate most, using the peak moment and app given"}
    Ground every claim in the sample. Never invent facts, names or numbers, never repeat \
    private details such as email addresses, phone numbers, addresses or amounts, and use \
    no emoji. Write plainly and warmly.
    """

    /// The message sent with the prompt: the counts, then a redacted sample.
    public static func request(entries: [HistoryEntry], voice: VoiceInsights,
                               usage: UsageInsights) -> String {
        var lines: [String] = []
        lines.append("Words dictated: \(usage.words). Dictations: \(usage.dictations).")
        if let moment = voice.peakMoment {
            lines.append("Peak moment: \(moment)\(voice.peakApp.map { " in \($0)" } ?? "").")
        }
        lines.append("Where they dictate: " + usage.places.prefix(4)
            .map { "\($0.place.label) \(Int(($0.share * 100).rounded()))%" }.joined(separator: ", ") + ".")
        if usage.arabicWords > 0 {
            lines.append("Languages: \(Int(((1 - usage.arabicShare) * 100).rounded()))% English, "
                         + "\(Int((usage.arabicShare * 100).rounded()))% Arabic.")
        }
        if let phrase = voice.catchphrase { lines.append("Most repeated phrase: \(phrase).") }
        lines.append("")
        lines.append("Sample of recent dictations:")
        var budget = 3_500
        for entry in entries where entry.kind == .dictation {
            let text = redact(String(entry.cleaned.prefix(220)))
            guard budget - text.count > 0 else { break }
            budget -= text.count
            lines.append("- \(text)")
        }
        return lines.joined(separator: "\n")
    }

    /// Takes out what the profile must never repeat, before the model sees it.
    static func redact(_ text: String) -> String {
        var out = text
        let patterns = [
            #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,           // email addresses
            #"https?://\S+"#,                                     // links
            #"\+?\d[\d\s().-]{6,}\d"#,                            // phone numbers and long numbers
        ]
        for pattern in patterns {
            out = out.replacingOccurrences(of: pattern, with: "[removed]",
                                           options: [.regularExpression, .caseInsensitive])
        }
        return out
    }

    /// Reads the model's reply, refusing anything malformed rather than showing it.
    public static func parse(_ reply: String, words: Int, now: Date = Date()) -> VoiceProfile? {
        var text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        if let open = text.firstIndex(of: "{"), let close = text.lastIndex(of: "}") {
            text = String(text[open...close])
        }
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let archetype = (json["archetype"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let summary = (json["summary"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let peak = (json["peak"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !archetype.isEmpty, !summary.isEmpty,
              archetype.split(separator: " ").count <= 4, archetype.count <= 40,
              summary.count <= 480,
              redact(summary) == summary, redact(peak) == peak else { return nil }
        // Asked for under eighteen words, the peak line still ran to twenty-five.
        // Rather than show a sentence that drags, the screen falls back to the
        // counted one: an empty peak means "say it plainly".
        return VoiceProfile(archetype: archetype, summary: summary,
                            peak: peak.count <= 120 ? peak : "",
                            createdAt: now, wordsAtCreation: words)
    }
}

/// Where the profile is kept between launches.
public final class VoiceProfileStore: @unchecked Sendable {
    private let url: URL
    private let cipher: (any HistoryCipher)?

    public static var defaultURL: URL { Config.supportDirectory.appendingPathComponent("voice-profile") }

    public init(url: URL = VoiceProfileStore.defaultURL, cipher: (any HistoryCipher)?) {
        self.url = url
        self.cipher = cipher
    }

    public func load() -> VoiceProfile? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let plain = cipher.flatMap { try? $0.open(data) } ?? (cipher == nil ? data : nil)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return plain.flatMap { try? decoder.decode(VoiceProfile.self, from: $0) }
    }

    public func save(_ profile: VoiceProfile) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(profile) else { return }
        let sealed = cipher.flatMap { try? $0.seal(data) } ?? (cipher == nil ? data : nil)
        try? sealed?.write(to: url, options: .atomic)
    }

    public func clear() { try? FileManager.default.removeItem(at: url) }
}
