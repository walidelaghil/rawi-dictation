import Foundation

/// Statistics derived from history.
///
/// Everything here is *computed* from the stored entries rather than accumulated
/// in counters. A counter drifts: delete a history entry and the total stops
/// matching the list it claims to describe. Recomputing is cheap at 500 rows and
/// cannot disagree with the record.
public struct Insights: Sendable, Equatable {
    public let wordsDictated: Int
    public let secondsSpoken: Double
    public let wordsPerMinute: Int
    public let dictations: Int
    public let cleanupsRejected: Int
    public let entriesCleaned: Int
    public let byApp: [AppShare]
    public let activeDays: Set<String>
    public let currentStreak: Int
    public let longestStreak: Int

    public struct AppShare: Sendable, Equatable, Identifiable {
        public var id: String { name }
        public let name: String
        public let count: Int
        public let share: Double
    }

    public static let empty = Insights(
        wordsDictated: 0, secondsSpoken: 0, wordsPerMinute: 0, dictations: 0,
        cleanupsRejected: 0, entriesCleaned: 0, byApp: [], activeDays: [],
        currentStreak: 0, longestStreak: 0)

    /// An estimate, and labelled as one wherever it is shown.
    public func minutesSavedVersusTyping(at typingWPM: Int = 41) -> Int {
        guard typingWPM > 0, wordsDictated > 0 else { return 0 }
        let typingMinutes = Double(wordsDictated) / Double(typingWPM)
        let spokenMinutes = secondsSpoken / 60
        return max(0, Int((typingMinutes - spokenMinutes).rounded()))
    }

    public static func compute(from entries: [HistoryEntry], now: Date = Date()) -> Insights {
        guard !entries.isEmpty else { return .empty }

        // Spoken-word statistics count dictations only. A transform's row holds
        // clipboard text nobody said; a failed row holds no text at all. Counting
        // either would inflate the totals with words that were never delivered.
        let spoken = entries.filter { $0.kind == .dictation }
        let words = spoken.reduce(0) { $0 + wordCount($1.cleaned) }
        let seconds = spoken.reduce(0.0) { $0 + max(0, $1.durationSeconds) }
        // Guard the divide: a history of zero-duration entries must not produce
        // an infinite rate.
        let wpm = seconds > 0 ? Int((Double(words) / (seconds / 60)).rounded()) : 0

        var counts: [String: Int] = [:]
        for entry in entries {
            counts[entry.appName ?? "Unknown", default: 0] += 1
        }
        let total = Double(entries.count)
        let shares = counts
            .map { AppShare(name: $0.key, count: $0.value, share: Double($0.value) / total) }
            .sorted { $0.count == $1.count ? $0.name < $1.name : $0.count > $1.count }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let days = Set(entries.map { formatter.string(from: $0.at) })

        return Insights(
            wordsDictated: words,
            secondsSpoken: seconds,
            wordsPerMinute: wpm,
            dictations: spoken.count,
            cleanupsRejected: spoken.filter(\.guardRejected).count,
            entriesCleaned: spoken.filter(\.wasCleaned).count,
            byApp: shares,
            activeDays: days,
            currentStreak: streak(endingAt: now, days: days, formatter: formatter),
            longestStreak: longest(days: days, formatter: formatter))
    }

    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    /// Consecutive days ending today — or yesterday, so a streak is not declared
    /// broken before the day is over.
    static func streak(endingAt now: Date, days: Set<String>,
                       formatter: DateFormatter) -> Int {
        let calendar = Calendar.current
        var cursor = calendar.startOfDay(for: now)
        if !days.contains(formatter.string(from: cursor)) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor),
                  days.contains(formatter.string(from: yesterday)) else { return 0 }
            cursor = yesterday
        }
        var count = 0
        while days.contains(formatter.string(from: cursor)) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor)
            else { break }
            cursor = previous
        }
        return count
    }

    static func longest(days: Set<String>, formatter: DateFormatter) -> Int {
        let calendar = Calendar.current
        let dates = days.compactMap { formatter.date(from: $0) }
            .map { calendar.startOfDay(for: $0) }
            .sorted()
        guard !dates.isEmpty else { return 0 }
        var best = 1, run = 1
        for i in 1..<dates.count {
            let gap = calendar.dateComponents([.day], from: dates[i - 1], to: dates[i]).day ?? 0
            run = gap == 1 ? run + 1 : 1
            best = max(best, run)
        }
        return best
    }
}
