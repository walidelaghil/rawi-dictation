import Testing
import Foundation
@testable import RawiCore

@Suite("Insights") struct InsightsTests {
    func entry(_ text: String, seconds: Double = 10, at: Date = Date(),
               app: String = "Slack", rejected: Bool = false,
               raw: String? = nil) -> HistoryEntry {
        HistoryEntry(at: at, cleaned: text, raw: raw ?? text, script: .latin,
                     appName: app, bundleID: app, durationSeconds: seconds,
                     peakLevel: 0.3, guardRejected: rejected)
    }
    func day(_ offset: Int, from now: Date = Date()) -> Date {
        Calendar.current.date(byAdding: .day, value: offset,
                              to: Calendar.current.startOfDay(for: now))!
    }

    @Test("words and time come from the entries themselves") func totals() {
        let i = Insights.compute(from: [entry("one two three", seconds: 6),
                                        entry("four five", seconds: 4)])
        #expect(i.wordsDictated == 5)
        #expect(i.secondsSpoken == 10)
        #expect(i.dictations == 2)
    }

    @Test("words per minute is words over time spoken, not wall clock") func wpm() {
        // 30 words in 60 seconds is 30 wpm, regardless of when they happened.
        let words = Array(repeating: "word", count: 30).joined(separator: " ")
        #expect(Insights.compute(from: [entry(words, seconds: 60)]).wordsPerMinute == 30)
    }

    @Test("an empty history yields zeroes, never a divide by zero") func empty() {
        let i = Insights.compute(from: [])
        #expect(i == .empty)
        #expect(i.wordsPerMinute == 0)
        #expect(i.minutesSavedVersusTyping() == 0)
    }

    @Test("a zero-duration entry cannot produce an infinite rate") func zeroDuration() {
        let i = Insights.compute(from: [entry("some words here", seconds: 0)])
        #expect(i.wordsPerMinute == 0)
        #expect(i.wordsDictated == 3)
    }

    @Test("app shares sum to one") func shares() {
        let i = Insights.compute(from: [entry("a", app: "Slack"), entry("b", app: "Slack"),
                                        entry("c", app: "Xcode")])
        #expect(abs(i.byApp.reduce(0) { $0 + $1.share } - 1.0) < 0.0001)
        #expect(i.byApp.first?.name == "Slack")
        #expect(i.byApp.first?.count == 2)
    }

    @Test("an entry with no app is counted, not dropped") func unknownApp() {
        let e = HistoryEntry(at: Date(), cleaned: "x", raw: "x", script: .latin,
                             appName: nil, bundleID: nil, durationSeconds: 1,
                             peakLevel: 0.3, guardRejected: false)
        #expect(Insights.compute(from: [e]).byApp.first?.name == "Unknown")
    }

    @Test("rejections and cleanups are counted from the record") func flags() {
        let i = Insights.compute(from: [
            entry("clean text", raw: "um clean text"),
            entry("untouched", raw: "untouched"),
            entry("kept raw", rejected: true, raw: "kept raw")])
        #expect(i.cleanupsRejected == 1)
        #expect(i.entriesCleaned == 1)
    }

    @Test("a streak counts consecutive days ending today") func streak() {
        let now = Date()
        let entries = [entry("a", at: day(0, from: now)),
                       entry("b", at: day(-1, from: now)),
                       entry("c", at: day(-2, from: now))]
        #expect(Insights.compute(from: entries, now: now).currentStreak == 3)
    }

    @Test("a gap breaks the streak") func gap() {
        let now = Date()
        let entries = [entry("a", at: day(0, from: now)),
                       entry("c", at: day(-3, from: now))]
        #expect(Insights.compute(from: entries, now: now).currentStreak == 1)
    }

    @Test("a streak ending yesterday still counts — the day is not over") func yesterday() {
        let now = Date()
        let entries = [entry("a", at: day(-1, from: now)), entry("b", at: day(-2, from: now))]
        #expect(Insights.compute(from: entries, now: now).currentStreak == 2)
    }

    @Test("the longest streak survives a later gap") func longest() {
        let now = Date()
        let entries = [entry("a", at: day(-10, from: now)), entry("b", at: day(-9, from: now)),
                       entry("c", at: day(-8, from: now)), entry("d", at: day(-7, from: now)),
                       entry("e", at: day(0, from: now))]
        let i = Insights.compute(from: entries, now: now)
        #expect(i.longestStreak == 4)
        #expect(i.currentStreak == 1)
    }

    @Test("time saved is measured against a stated typing baseline") func saved() {
        // 410 words spoken in 60s: typing at 41wpm would be 10 minutes, so ~9 saved.
        let words = Array(repeating: "word", count: 410).joined(separator: " ")
        let i = Insights.compute(from: [entry(words, seconds: 60)])
        #expect(i.minutesSavedVersusTyping(at: 41) == 9)
        // A faster typist saves less. The baseline is not decoration.
        #expect(i.minutesSavedVersusTyping(at: 100) < i.minutesSavedVersusTyping(at: 41))
    }

    @Test("time saved never goes negative") func neverNegative() {
        let i = Insights.compute(from: [entry("two words", seconds: 600)])
        #expect(i.minutesSavedVersusTyping() == 0)
    }
}

@Suite("Insights and transforms") struct InsightsTransformTests {
    func transformEntry(_ text: String, at: Date = Date()) -> HistoryEntry {
        HistoryEntry(at: at, cleaned: text, raw: text, script: .latin,
                     appName: "Brave", bundleID: "com.brave.Browser",
                     durationSeconds: 0, peakLevel: 0, guardRejected: false,
                     kind: .transform)
    }

    @Test("a transform's clipboard text is not counted as words you spoke") func excluded() {
        let spoken = HistoryEntry(at: Date(), cleaned: "one two three", raw: "one two three",
                                  script: .latin, appName: "Slack", bundleID: "slack",
                                  durationSeconds: 6, peakLevel: 0.3, guardRejected: false)
        let long = Array(repeating: "word", count: 500).joined(separator: " ")
        let i = Insights.compute(from: [spoken, transformEntry(long)])
        #expect(i.wordsDictated == 3)
        #expect(i.dictations == 1)
        // 3 words in 6 seconds is 30 wpm. Counting the 500 pasted words would
        // report 5030 — a number the history list would flatly contradict.
        #expect(i.wordsPerMinute == 30)
    }

    @Test("a day you only transformed still counts toward the streak") func streakCounts() {
        let now = Date()
        let day = { (o: Int) in Calendar.current.date(byAdding: .day, value: o,
                        to: Calendar.current.startOfDay(for: now))! }
        let i = Insights.compute(from: [transformEntry("x", at: day(0)),
                                        transformEntry("y", at: day(-1))], now: now)
        #expect(i.currentStreak == 2)
    }

    @Test("a history of nothing but transforms reports no rate, not a crash") func onlyTransforms() {
        let i = Insights.compute(from: [transformEntry("a b c")])
        #expect(i.wordsDictated == 0)
        #expect(i.wordsPerMinute == 0)
        #expect(i.minutesSavedVersusTyping() == 0)
    }

    @Test("an entry written before transforms existed still decodes as a dictation")
    func backCompat() throws {
        let line = """
            {"id":"\(UUID().uuidString)","at":760000000,"cleaned":"hello there",\
            "raw":"hello there","script":"latin","durationSeconds":2,\
            "peakLevel":0.4,"guardRejected":false}
            """
        let entry = try JSONDecoder().decode(HistoryEntry.self, from: Data(line.utf8))
        #expect(entry.kind == .dictation)
        #expect(Insights.compute(from: [entry]).wordsDictated == 2)
    }
}
