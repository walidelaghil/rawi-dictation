import Testing
@testable import RawiCore

@Suite("Deciding whether to polish") struct PolishNeededTests {
    @Test("a spoken correction earns a round trip on its own") func corrections() {
        // Capitalised, punctuated, no filler: the cleanup gate skips all of these.
        let takenBack = "The meeting is on Monday, no wait, Tuesday at four."
        #expect(!CleanupNeeded.check(takenBack))
        #expect(PolishNeeded.check(takenBack))
        #expect(PolishNeeded.check("Send it to Ahmed, I mean Sara."))
        #expect(PolishNeeded.check("الاجتماع الاثنين، لا لا الثلاثاء."))
    }

    @Test("everything cleanup would have done, polish does too") func superset() {
        for text in ["um so can you send me the report by friday",
                     "we should probably reach out to the vendor and see",
                     "so yeah that is the plan for the quarter ahead"] {
            if CleanupNeeded.check(text) { #expect(PolishNeeded.check(text)) }
        }
    }

    @Test("clean prose still costs nothing") func skipsCleanText() {
        let clean = "Let us move the launch date back by one week."
        #expect(!PolishNeeded.check(clean))
    }
}

@Suite("Guarding a rewrite") struct PolishGuardTests {
    @Test("applying a correction is not losing words") func correctionAccepted() {
        // CleanupGuard would reject this: "Monday" and "no wait" are gone.
        let raw = "The meeting is on Monday, no wait, Tuesday at four o'clock."
        let polished = "The meeting is on Tuesday at four o'clock."
        #expect(PolishGuard.check(raw: raw, polished: polished) == .accept)
    }

    @Test("an answer instead of a rewrite is refused") func refusesAnswers() {
        let verdict = PolishGuard.check(raw: "what is the capital of france",
                                        polished: "The capital of France is Paris.")
        #expect(verdict != .accept)
    }

    @Test("a rewrite that leaves the language is refused") func refusesTranslation() {
        // Measured: gemma3:4b answers clean Arabic in English.
        let raw = "نرسل التقرير إلى الفريق قبل يوم الاثنين."
        let verdict = PolishGuard.check(raw: raw,
                                        polished: "We send the report to the team before Monday.")
        #expect(verdict != .accept)
    }

    @Test("a summary is not a rewrite") func refusesSummary() {
        let raw = "So I was thinking that we should probably reach out to the vendor "
                + "and see if they can give us a better price, because the current "
                + "one is too high for what we are getting out of it right now."
        #expect(PolishGuard.check(raw: raw, polished: "Contact the vendor.") != .accept)
    }

    @Test("padding the answer is refused") func refusesInvention() {
        let raw = "Send the deck to Sara before Friday."
        let padded = "Send the deck to Sara before Friday. Please ensure that the "
                   + "presentation includes quarterly revenue projections and the "
                   + "updated organisational roadmap for stakeholder alignment."
        #expect(PolishGuard.check(raw: raw, polished: padded) != .accept)
    }

    @Test("nothing back is refused") func refusesEmpty() {
        #expect(PolishGuard.check(raw: "Send the deck to Sara.", polished: "  ") != .accept)
    }

    @Test("an honest rewrite passes") func acceptsRealWork() {
        // Verbatim from the benchmark against qwen2.5:3b on a real transcript.
        let raw = "It's actually remarkably fast and I love it but somehow the quality "
                + "I don't know it keeps adding things in different lines and I need "
                + "to ensure that quality is high."
        let polished = "It's actually remarkably fast and I love it, but somehow the "
                     + "quality keeps adding things in different lines and I need to "
                     + "ensure that the quality is high."
        #expect(PolishGuard.check(raw: raw, polished: polished) == .accept)
    }

    @Test("grammar the speaker skipped is allowed in") func allowsConnectives() {
        let raw = "we ship monday, test tuesday"
        let polished = "We will ship on Monday, and then we will test on Tuesday."
        #expect(PolishGuard.check(raw: raw, polished: polished) == .accept)
    }
}
