import Testing
@testable import RawiCore

@Suite("Is cleanup worth a second") struct CleanupNeededTests {
    @Test("filler earns the round trip") func filler() {
        #expect(CleanupNeeded.check("Um so I think we should ship on Friday"))
        #expect(CleanupNeeded.check("We should, you know, ship this on Friday."))
        #expect(CleanupNeeded.check("It is basically ready to go out today."))
    }

    @Test("clean, punctuated text does not") func clean() {
        // Whisper punctuates and capitalises on its own most of the time. Paying a
        // model to confirm that is a second of GPU spent to change nothing.
        #expect(!CleanupNeeded.check("Move the launch date back a week, the billing work is not done."))
        #expect(!CleanupNeeded.check("Can you review the migration before Thursday?"))
    }

    @Test("a few words are never worth it") func short() {
        #expect(!CleanupNeeded.check("Thank you."))
        #expect(!CleanupNeeded.check("Sounds good"))
        #expect(!CleanupNeeded.check(""))
    }

    @Test("missing punctuation or capitals earns it") func broken() {
        #expect(CleanupNeeded.check("move the launch date back a week please"))
        #expect(CleanupNeeded.check("Move the launch date back a week please"))
    }

    @Test("a filler inside a longer word does not count") func wordBoundaries() {
        // "um" lives inside "number", "summary" and "document".
        #expect(!CleanupNeeded.check("The number in the summary document is correct."))
        #expect(!CleanupNeeded.check("Actuarial tables are in the appendix."))
    }

    @Test("Arabic punctuation counts as punctuation") func arabic() {
        #expect(!CleanupNeeded.check("نرسل التقرير إلى الفريق قبل يوم الاثنين."))
        #expect(!CleanupNeeded.check("نرسل التقرير إلى الفريق قبل يوم الاثنين؟"))
        #expect(CleanupNeeded.check("نرسل التقرير إلى الفريق قبل يوم الاثنين"))
    }

    @Test("one long unpunctuated run earns it") func runOn() {
        let long = Array(repeating: "word", count: 70).joined(separator: " ")
        #expect(CleanupNeeded.check("A" + long.dropFirst()))
    }
}
