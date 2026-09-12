import Testing
import Foundation
@testable import RawiCore

@Suite("What landed") struct LandedTests {
    @Test("the pill ends on your words, not on an instruction") func showsWords() {
        // The question at that moment is "did it hear me right", not "how do I
        // paste". The old last word was "Copied, press Command V".
        #expect(PillLabel.landed("move the launch date back a week")
                == "move the launch date back a week")
    }

    @Test("a long transcript is cut to a glance, at a word") func trims() {
        let long = "So I think what we should probably do here is move the launch "
                 + "date back by a week because the billing work is not finished"
        let shown = PillLabel.landed(long)
        #expect(shown.count <= 44)
        #expect(shown.hasSuffix("…"))
        #expect(!shown.contains("  "))
        // Cut between words: a pill ending mid-syllable reads as a rendering bug.
        #expect(long.hasPrefix(shown.dropLast().trimmingCharacters(in: .whitespaces)))
    }

    @Test("the words come from the start, where the sentence begins") func fromStart() {
        #expect(PillLabel.landed("Ship it on Monday.").hasPrefix("Ship it"))
    }

    @Test("whitespace and newlines collapse to one line") func oneLine() {
        #expect(PillLabel.landed("first line\n\nsecond   line") == "first line second line")
    }

    @Test("nothing to show falls back to a plain confirmation") func empty() {
        #expect(PillLabel.landed("   \n ") == "Copied")
        #expect(PillLabel.landed("") == "Copied")
    }

    @Test("Arabic is shown as spoken") func arabic() {
        #expect(PillLabel.landed("نرسل التقرير غدا") == "نرسل التقرير غدا")
    }
}
