import Foundation

/// The kind of place you dictate into. Sorting by app answers "which app", which
/// nobody asked; sorting by kind answers "what do I use my voice for".
public enum DictationPlace: String, CaseIterable, Sendable {
    case aiPrompts, workMessages, documents, email, code, personalMessages, other

    public var label: String {
        switch self {
        case .aiPrompts: "AI prompts"
        case .workMessages: "Work messages"
        case .documents: "Documents"
        case .email: "Emails"
        case .code: "Code"
        case .personalMessages: "Personal messages"
        case .other: "Other tasks"
        }
    }

    /// The label for a count: "1 work message", "22 work messages".
    public func label(count: Int) -> String {
        count == 1 && label.hasSuffix("s") ? String(label.dropLast()) : label
    }

    /// SF Symbol for the row.
    public var symbol: String {
        switch self {
        case .aiPrompts: "sparkles"
        case .workMessages: "bubble.left.and.bubble.right"
        case .documents: "doc.text"
        case .email: "envelope"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .personalMessages: "message"
        case .other: "square.grid.2x2"
        }
    }

    static let byBundle: [String: DictationPlace] = [
        "com.anthropic.claudefordesktop": .aiPrompts, "com.openai.chat": .aiPrompts,
        "ai.perplexity.mac": .aiPrompts, "com.openai.atlas": .aiPrompts,
        "com.tinyspeck.slackmacgap": .workMessages, "com.microsoft.teams2": .workMessages,
        "com.microsoft.teams": .workMessages, "com.linear": .workMessages,
        "notion.id": .documents, "com.apple.iWork.Pages": .documents, "com.microsoft.Word": .documents,
        "com.apple.TextEdit": .documents, "md.obsidian": .documents, "com.apple.Notes": .documents,
        "com.apple.mail": .email, "com.microsoft.Outlook": .email, "com.superhuman.electron": .email,
        "com.readdle.smartemail-Mac": .email,
        "com.microsoft.VSCode": .code, "com.apple.dt.Xcode": .code, "com.todesktop.230313mzl4w4u92": .code,
        "com.apple.Terminal": .code, "com.googlecode.iterm2": .code, "dev.warp.Warp-Stable": .code,
        "com.mitchellh.ghostty": .code, "dev.zed.Zed": .code,
        "net.whatsapp.WhatsApp": .personalMessages, "ru.keepcoder.Telegram": .personalMessages,
        "com.hnc.Discord": .personalMessages, "com.apple.MobileSMS": .personalMessages,
    ]

    /// Browser tabs are known only by the destination rule that matched them — the
    /// URL itself is never stored — so a destination's name is the evidence.
    static let byDestinationWord: [(String, DictationPlace)] = [
        ("chatgpt", .aiPrompts), ("claude", .aiPrompts), ("gemini", .aiPrompts), ("prompt", .aiPrompts),
        ("gmail", .email), ("mail", .email), ("outlook", .email),
        ("slack", .workMessages), ("jira", .workMessages), ("linear", .workMessages),
        ("docs", .documents), ("notion", .documents), ("confluence", .documents),
        ("github", .code), ("whatsapp", .personalMessages),
    ]

    public static func of(bundleID: String?, destination: String?) -> DictationPlace {
        if let bundleID, let place = byBundle[bundleID] { return place }
        if let destination {
            let lower = destination.lowercased()
            if let hit = byDestinationWord.first(where: { lower.contains($0.0) }) { return hit.1 }
        }
        return .other
    }
}

/// Everything on the "Your usage" tab, computed from history in one pass.
public struct UsageInsights: Sendable, Equatable {
    public struct Place: Sendable, Equatable, Identifiable {
        public var id: String { place.rawValue }
        public let place: DictationPlace
        public let dictations: Int
        public let share: Double
    }

    public let words: Int
    public let dictations: Int
    public let wordsPerMinute: Int
    public let secondsSpoken: Double
    /// Words this calendar month and the month before, for the trend.
    public let wordsThisMonth: Int
    public let wordsLastMonth: Int
    /// Words Rawi removed or rewrote while cleaning up.
    public let wordsTidied: Int
    /// Words that came out spelled the way your dictionary says.
    public let dictionaryFixes: Int
    public let places: [Place]
    public let appsUsed: Int
    /// Words per day, keyed "yyyy-MM-dd".
    public let wordsByDay: [String: Int]
    public let currentStreak: Int
    public let longestStreak: Int
    public let latinWords: Int
    public let arabicWords: Int
    /// Dictations that used both scripts at once.
    public let mixedDictations: Int

    public var trend: Double? {
        guard wordsLastMonth > 0 else { return nil }
        return Double(wordsThisMonth - wordsLastMonth) / Double(wordsLastMonth)
    }

    /// Pages of writing, at the 250 words a page that a manuscript page is counted at.
    public var pages: Int { words / 250 }

    public var arabicShare: Double {
        let total = latinWords + arabicWords
        return total > 0 ? Double(arabicWords) / Double(total) : 0
    }

    public func minutesSaved(typingWPM: Int) -> Int {
        guard typingWPM > 0, words > 0 else { return 0 }
        return max(0, Int((Double(words) / Double(typingWPM) - secondsSpoken / 60).rounded()))
    }

    public static func compute(from entries: [HistoryEntry], terms: [String] = [],
                               now: Date = Date(), calendar: Calendar = .current) -> UsageInsights {
        let spoken = entries.filter { $0.kind == .dictation }
        let day = DateFormatter()
        day.dateFormat = "yyyy-MM-dd"
        day.calendar = calendar

        var words = 0, seconds = 0.0, thisMonth = 0, lastMonth = 0
        var tidied = 0, dictionary = 0, latin = 0, arabic = 0, mixed = 0
        var byDay: [String: Int] = [:]
        var placeCounts: [DictationPlace: Int] = [:]
        var apps = Set<String>()
        let termSet = Set(terms.map { $0.lowercased() })
        let monthNow = calendar.dateComponents([.year, .month], from: now)
        let previous = calendar.date(byAdding: .month, value: -1, to: now).map {
            calendar.dateComponents([.year, .month], from: $0)
        }

        for entry in spoken {
            let count = Insights.wordCount(entry.cleaned)
            words += count
            seconds += max(0, entry.durationSeconds)
            byDay[day.string(from: entry.at), default: 0] += count
            let month = calendar.dateComponents([.year, .month], from: entry.at)
            if month == monthNow { thisMonth += count } else if month == previous { lastMonth += count }
            placeCounts[DictationPlace.of(bundleID: entry.bundleID, destination: entry.destination), default: 0] += 1
            if let app = entry.bundleID ?? entry.appName { apps.insert(app) }

            let (changed, toTerms) = Self.changes(raw: entry.raw, cleaned: entry.cleaned, terms: termSet)
            tidied += changed
            dictionary += toTerms

            let share = ScriptDetector.arabicRatio(entry.cleaned)
            if share > 0 && share < 1 && entry.cleaned.contains(where: { $0.isASCII && $0.isLetter }) { mixed += 1 }
            if entry.script == .arabic { arabic += count } else { latin += count }
        }

        let total = Double(max(1, spoken.count))
        let places = placeCounts
            .map { Place(place: $0.key, dictations: $0.value, share: Double($0.value) / total) }
            .sorted { $0.dictations == $1.dictations ? $0.place.rawValue < $1.place.rawValue : $0.dictations > $1.dictations }
        let days = Set(byDay.keys)
        return UsageInsights(
            words: words, dictations: spoken.count,
            wordsPerMinute: seconds > 0 ? Int((Double(words) / (seconds / 60)).rounded()) : 0,
            secondsSpoken: seconds, wordsThisMonth: thisMonth, wordsLastMonth: lastMonth,
            wordsTidied: tidied, dictionaryFixes: dictionary, places: places, appsUsed: apps.count,
            wordsByDay: byDay,
            currentStreak: Insights.streak(endingAt: now, days: days, formatter: day),
            longestStreak: Insights.longest(days: days, formatter: day),
            latinWords: latin, arabicWords: arabic, mixedDictations: mixed)
    }

    /// Words cleanup changed, and how many of those landed on a dictionary spelling.
    static func changes(raw: String, cleaned: String, terms: Set<String>) -> (changed: Int, toTerms: Int) {
        guard raw != cleaned else { return (0, 0) }
        let before = EditLearner.words(raw).map { $0.lowercased() }
        let after = EditLearner.words(cleaned).map { $0.lowercased() }
        let kept = EditLearner.alignment(before, after).count
        let changed = max(0, before.count - kept)
        guard !terms.isEmpty else { return (changed, 0) }
        let beforeSet = Set(before)
        let toTerms = after.filter { terms.contains($0) && !beforeSet.contains($0) }.count
        return (changed, toTerms)
    }
}
