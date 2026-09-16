import Foundation

/// Pulls a time out of what you said, and leaves the rest as the title.
///
/// "remind me to send the deck tomorrow at 9" should produce a reminder called
/// "send the deck", due tomorrow morning — not one called "send the deck tomorrow
/// at 9" with no due date, which is what it did before.
///
/// macOS already has a date parser, the one that underlines dates in Mail, and it
/// handles far more than a hand-written matcher would: "next Tuesday", "in twenty
/// minutes", "on the 3rd at 4pm". What it does not do is decide *whether* you meant
/// a date, and that is the risk: "check the Monday standup notes" contains a date
/// that is part of the title. So a match only counts when it sits at one end of
/// what you said, where a time belongs, never in the middle.
public enum SpokenDate {
    public struct Parsed: Equatable, Sendable {
        public let title: String
        public let due: Date?
        /// True when you said a time, not just a day.
        public let hasTime: Bool
    }

    /// When a day is named with no time. Reminders' own default for "tomorrow".
    public static let defaultHour = 9

    public static func parse(_ text: String, now: Date = Date(),
                             calendar: Calendar = .current) -> Parsed {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 2,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        else { return Parsed(title: trimmed, due: nil, hasTime: false) }

        // "in twenty minutes" is the one common way of saying a time that macOS's
        // parser does not read at all, so it is read here first.
        if let soon = relative(in: trimmed, now: now) { return soon }

        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        let matches = detector.matches(in: trimmed, range: range)
            .filter { anchored($0.range, in: trimmed) }
            .sorted { $0.range.length > $1.range.length }
        guard let match = matches.first, let date = match.date,
              let matched = Range(match.range, in: trimmed) else {
            return Parsed(title: trimmed, due: nil, hasTime: false)
        }

        var title = trimmed
        title.removeSubrange(matched)
        title = tidy(title)
        // A phrase that is *only* a date is a title of nothing: keep the words.
        guard !title.isEmpty else { return Parsed(title: trimmed, due: nil, hasTime: false) }

        // macOS does not say whether a match carried a time, so the matched words
        // are asked: "tomorrow" is a day, "tomorrow at 9" is a time.
        let hasTime = mentionsTime(String(trimmed[matched]))
        let due = hasTime ? date : calendar.date(bySettingHour: defaultHour, minute: 0, second: 0,
                                                 of: date) ?? date
        return Parsed(title: title, due: due, hasTime: hasTime)
    }

    /// "in 30 minutes", "in an hour", "in 2 days": a stretch from now, at either end
    /// of what you said.
    static func relative(in text: String, now: Date) -> Parsed? {
        let pattern = #"\bin\s+(a|an|one|half an|\d{1,3})\s+(minute|minutes|hour|hours|day|days|week|weeks)\b"#
        guard let found = text.range(of: pattern, options: [.regularExpression, .caseInsensitive])
        else { return nil }
        let before = String(text[text.startIndex..<found.lowerBound])
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,"))
        let after = String(text[found.upperBound...])
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,.!?"))
        // Same rule as a date: at one end, never buried in the middle.
        guard before.isEmpty || after.isEmpty else { return nil }

        let words = text[found].lowercased()
            .replacingOccurrences(of: "half an", with: "half")
            .split(separator: " ").map(String.init)
        let amount: Double = switch words[1] {
        case "a", "an", "one": 1
        case "half": 0.5
        default: Double(words[1]) ?? 1
        }
        let unit = words.last ?? "minutes"
        let seconds: Double = if unit.hasPrefix("minute") { 60 }
            else if unit.hasPrefix("hour") { 3_600 }
            else if unit.hasPrefix("day") { 86_400 }
            else { 604_800 }
        let title = tidy(before + " " + after)
        guard !title.isEmpty else { return nil }
        return Parsed(title: title, due: now.addingTimeInterval(amount * seconds),
                      hasTime: unit.hasPrefix("minute") || unit.hasPrefix("hour"))
    }

    /// Whether the matched words name a time of day rather than only a day.
    static func mentionsTime(_ matched: String) -> Bool {
        let lower = matched.lowercased()
        for word in ["noon", "midnight", "morning", "afternoon", "evening", "tonight",
                     "minute", "minutes", "hour", "hours", "o'clock", "oclock"]
        where lower.contains(word) { return true }
        // "at 9", "9:30", "4pm", "16:00".
        let patterns = [#"\b\d{1,2}:\d{2}"#, #"\b\d{1,2}\s*(am|pm|a\.m\.|p\.m\.)"#,
                        #"\bat\s+\d{1,2}\b"#]
        return patterns.contains {
            lower.range(of: $0, options: [.regularExpression]) != nil
        }
    }

    /// Whether the match sits at the start or the end, allowing the words that
    /// introduce it ("at", "on", "by") and trailing punctuation.
    static func anchored(_ range: NSRange, in text: String) -> Bool {
        let head = (text as NSString).substring(to: range.location)
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,"))
        let tail = (text as NSString).substring(from: range.location + range.length)
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,.!?"))
        let leadIns = ["at", "on", "by", "for", "in", "this", "next", "tomorrow", "today"]
        let headEndsWithLeadIn = leadIns.contains(head.split(separator: " ").last.map(String.init)?
            .lowercased() ?? "")
        // At the end: nothing after it. At the start: nothing before it.
        return tail.isEmpty || head.isEmpty || (headEndsWithLeadIn && tail.isEmpty)
    }

    /// What is left after the date is taken out, without the preposition that
    /// introduced it or a dangling comma.
    static func tidy(_ text: String) -> String {
        var words = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        let danglers = ["at", "on", "by", "for", "in", "this", "next", "and", "then"]
        while let last = words.last, danglers.contains(last.lowercased()
            .trimmingCharacters(in: CharacterSet.alphanumerics.inverted)) { words.removeLast() }
        while let first = words.first, danglers.contains(first.lowercased()) { words.removeFirst() }
        return words.joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,.;"))
    }

    /// "tomorrow at 9:00 a.m." as a person would read it back.
    public static func describe(_ due: Date, hasTime: Bool, now: Date = Date(),
                                calendar: Calendar = .current) -> String {
        let day = DateFormatter()
        day.calendar = calendar
        day.timeZone = calendar.timeZone
        day.locale = Locale(identifier: "en_US")
        let time = DateFormatter()
        time.calendar = calendar
        time.timeZone = calendar.timeZone
        time.locale = Locale(identifier: "en_US")
        time.dateFormat = calendar.component(.minute, from: due) == 0 ? "h a" : "h:mm a"

        let today = calendar.startOfDay(for: now)
        let dueDay = calendar.startOfDay(for: due)
        let days = calendar.dateComponents([.day], from: today, to: dueDay).day ?? 0
        let when: String = switch days {
        case 0: "today"
        case 1: "tomorrow"
        case 2...6: { day.dateFormat = "EEEE"; return "on \(day.string(from: due))" }()
        default: { day.dateFormat = "d MMM"; return "on \(day.string(from: due))" }()
        }
        return hasTime ? "\(when) at \(time.string(from: due).lowercased())" : when
    }
}
