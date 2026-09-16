import Foundation
import Testing
@testable import RawiCore

/// macOS's date parser works from the real clock and the real time zone, so these
/// read the same way: expectations are built from `now`, not from a fixed date.
@Suite("Times you say out loud") struct SpokenDateTests {
    let calendar = Calendar.current
    let now = Date()
    func parse(_ text: String) -> SpokenDate.Parsed { SpokenDate.parse(text, now: now) }

    func expected(daysFromToday days: Int, hour: Int, minute: Int = 0) -> Date {
        let day = calendar.date(byAdding: .day, value: days, to: now)!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    @Test("a time at the end becomes the due date, not part of the title") func tomorrowAtNine() {
        let result = parse("send the deck tomorrow at 9")
        #expect(result.title == "send the deck")
        #expect(result.hasTime)
        #expect(result.due == expected(daysFromToday: 1, hour: 9))
    }

    @Test("a day with no time is due in the morning, not at noon") func dayOnly() {
        let result = parse("call the bank next Tuesday")
        #expect(result.title == "call the bank")
        #expect(!result.hasTime)
        #expect(calendar.component(.hour, from: result.due!) == SpokenDate.defaultHour)
        #expect(calendar.component(.weekday, from: result.due!) == 3)   // Tuesday
    }

    @Test("in half an hour, and in thirty minutes") func soon() {
        let minutes = parse("check the build in 30 minutes")
        #expect(minutes.title == "check the build")
        #expect(minutes.hasTime)
        #expect(abs(minutes.due!.timeIntervalSince(now) - 1_800) < 2)

        let half = parse("in half an hour ping the vendor")
        #expect(half.title == "ping the vendor")
        #expect(abs(half.due!.timeIntervalSince(now) - 1_800) < 2)

        let days = parse("follow up in 3 days")
        #expect(days.title == "follow up")
        #expect(!days.hasTime)
    }

    @Test("a date in the middle of a title is left alone") func middle() {
        let result = parse("read the Monday standup notes before the review")
        #expect(result.title == "read the Monday standup notes before the review")
        #expect(result.due == nil)
    }

    @Test("no time at all leaves the words exactly as they were") func none() {
        let result = parse("water the plants")
        #expect(result.title == "water the plants")
        #expect(result.due == nil)
    }

    @Test("a phrase that is only a time keeps its words rather than emptying") func onlyATime() {
        #expect(parse("tomorrow at 9").due == nil)
        #expect(parse("in 20 minutes").due == nil)
    }

    @Test("tonight is this evening, not tomorrow morning") func tonight() {
        let result = parse("call Sara tonight")
        #expect(result.title == "call Sara")
        #expect(result.hasTime)
        #expect(calendar.isDate(result.due!, inSameDayAs: now) || result.due! > now)
    }

    @Test("it reads back the way a person would say it") func described() {
        #expect(SpokenDate.describe(expected(daysFromToday: 1, hour: 9), hasTime: true, now: now)
                == "tomorrow at 9 am")
        #expect(SpokenDate.describe(expected(daysFromToday: 1, hour: 9), hasTime: false, now: now)
                == "tomorrow")
        #expect(SpokenDate.describe(expected(daysFromToday: 0, hour: 16, minute: 30), hasTime: true, now: now)
                == "today at 4:30 pm")
    }

    @Test("the confirmation shows the title and the time, not the raw words") func confirmation() {
        let text = CommandAction.reminder(list: "Ideas").describe(text: "send the deck tomorrow at 9")
        #expect(text.contains("Add “send the deck” to your Ideas list"))
        #expect(text.contains("tomorrow at 9"))
    }
}
