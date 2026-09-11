import Testing
@testable import RawiCore

@Suite("ScriptDetector") struct ScriptDetectorTests {
    @Test("pure english is latin") func english() {
        #expect(ScriptDetector.detect("So I think we should ship on Friday.") == .latin)
    }

    @Test("pure arabic is arabic") func arabic() {
        #expect(ScriptDetector.detect("يعني أعتقد أنه لازم نأجل الاجتماع") == .arabic)
    }

    @Test("arabic with latin technical terms routes as arabic") func mixed() {
        // The normal bilingual case: mostly Arabic, English jargon left in Latin.
        #expect(ScriptDetector.detect("يعني الـ API مو شغال، لازم نسوي deploy مرة ثانية") == .arabic)
    }

    @Test("english quoting one arabic word stays latin") func mostlyLatin() {
        #expect(ScriptDetector.detect(
            "The Arabic word for narrator is راوي and it suits the app well enough") == .latin)
    }

    @Test("digits and punctuation do not sway the ratio") func nonLetters() {
        #expect(ScriptDetector.detect("12:30 — 45% (!!) يعني تمام كذا") == .arabic)
        #expect(ScriptDetector.detect("12:30 — 45% (!!) deploy to staging now") == .latin)
    }

    @Test("empty and whitespace are latin, never a crash") func empty() {
        #expect(ScriptDetector.detect("") == .latin)
        #expect(ScriptDetector.detect("   \n  ") == .latin)
        #expect(ScriptDetector.arabicRatio("") == 0)
    }

    @Test("ratio is a fraction of letters, not of characters") func ratio() {
        #expect(abs(ScriptDetector.arabicRatio("abcd راوي") - 0.5) < 0.01)
    }

    @Test("arabic-presentation and extended ranges count as arabic") func ranges() {
        #expect(ScriptDetector.detect("ﷺ ﷻ ﷲ") == .arabic)
        #expect(ScriptDetector.detect("پژگ چ") == .arabic)
    }

    @Test("the threshold is honoured") func threshold() {
        let s = "one two three راوي"
        #expect(ScriptDetector.detect(s, threshold: 0.9) == .latin)
        #expect(ScriptDetector.detect(s, threshold: 0.05) == .arabic)
    }
}
