import Testing
@testable import RawiCore

@Suite("TermCorrector") struct TermCorrectorTests {
    let terms = ["Salla", "Kandji", "Michael", "Grafana", "Argo CD"]

    // MARK: - The cases this exists for

    @Test("corrects the misses the models would not") func fixesNearMisses() {
        // Measured: qwen2.5:1.5b leaves both of these wrong with every glossary
        // phrasing tried, and 1.5b is what English routes to.
        #expect(TermCorrector.apply("reviewing the Sala dashboard", terms: terms)
                == "reviewing the Salla dashboard")
        #expect(TermCorrector.apply("we ship with Kanji today", terms: terms)
                == "we ship with Kandji today")
        #expect(TermCorrector.apply("Mikhail is reviewing it", terms: terms)
                == "Michael is reviewing it")
    }

    @Test("preserves surrounding punctuation and spacing") func punctuation() {
        #expect(TermCorrector.apply("Is it Sala, or Kanji?", terms: terms)
                == "Is it Salla, or Kandji?")
    }

    @Test("leaves an exact term untouched") func exact() {
        #expect(TermCorrector.apply("the Salla dashboard", terms: terms)
                == "the Salla dashboard")
    }

    @Test("normalises casing to the term as written") func casing() {
        #expect(TermCorrector.apply("the salla dashboard", terms: terms)
                == "the Salla dashboard")
    }

    // MARK: - The cases it must NOT touch

    @Test("a genuinely different name is left alone") func differentName() {
        // Turning Sara into Salla would be far worse than leaving Sala alone.
        #expect(TermCorrector.apply("Sara reviewed it", terms: terms) == "Sara reviewed it")
    }

    @Test("common words are protected even when one edit away") func protectedWords() {
        #expect(TermCorrector.apply("the raw transcript", terms: ["Rawi"]) == "the raw transcript")
        #expect(TermCorrector.apply("the sale closed", terms: terms) == "the sale closed")
        #expect(TermCorrector.apply("make a call", terms: terms) == "make a call")
    }

    @Test("short tokens are never corrected") func shortTokens() {
        #expect(TermCorrector.apply("go to it", terms: ["goto"]) == "go to it")
    }

    @Test("short terms are not added, so they cannot over-match") func shortTerms() {
        #expect(TermCorrector.apply("the cat sat", terms: ["car"]) == "the cat sat")
    }

    @Test("a distant word is left alone") func distant() {
        #expect(TermCorrector.apply("the platform works", terms: terms) == "the platform works")
    }

    @Test("no terms means no changes") func noTerms() {
        #expect(TermCorrector.apply("anything at all", terms: []) == "anything at all")
    }

    // MARK: - Shape

    @Test("multi-word terms are normalised") func phrase() {
        #expect(TermCorrector.apply("deploy via argo cd tonight", terms: terms)
                == "deploy via Argo CD tonight")
    }

    @Test("Arabic passes through untouched") func arabic() {
        let text = "يعني لازم نأجل الاجتماع"
        #expect(TermCorrector.apply(text, terms: terms) == text)
    }

    @Test("edit distance is correct") func distance() {
        #expect(TermCorrector.editDistance("sala", "salla") == 1)
        #expect(TermCorrector.editDistance("kanji", "kandji") == 1)
        #expect(TermCorrector.editDistance("mikhail", "michael") == 2)
        // 2, not 3: substitute r→l, then insert l. Close enough that "Sara" is
        // protected by the allowance (1 edit for a 5-character term), not by
        // distance — which is exactly why the allowance is tight.
        #expect(TermCorrector.editDistance("sara", "salla") == 2)
        #expect(TermCorrector.editDistance("same", "same") == 0)
    }

    @Test("the nearest term wins when two are close") func nearest() {
        #expect(TermCorrector.correction(for: "Sala", terms: ["Salla", "Sallam"]) == "Salla")
    }
}

@MainActor
@Suite("Dictionary end to end") struct DictionaryPipelineTests {
    /// The contract that matters: whatever the cleanup model does or refuses to
    /// do, the inserted text uses your spelling.
    func rig(cleanupReturns: String, terms: [String])
        -> (DictationController, FakeInserter) {
        let r = FakeRecorder(), e = FakeEngine(), c = FakeCleanup()
        let i = FakeInserter()
        e.result = .success("um raw transcript here")
        c.result = .success(cleanupReturns)
        let ctl = DictationController(config: .default, recorder: r, engine: e,
                                      cleanup: c, inserter: i, log: FakeLog())
        ctl.vocabulary = {
            VocabularySnapshot(whisperPrompt: terms.joined(separator: ", "),
                               glossary: "", terms: terms, snippets: [])
        }
        return (ctl, i)
    }

    @Test("spelling is corrected even when the cleanup model ignored the glossary") func corrects() async {
        // qwen2.5:1.5b does exactly this — returns the misspelling untouched.
        let (ctl, inserter) = rig(cleanupReturns: "Reviewing the Sala dashboard with Kanji.",
                                  terms: ["Salla", "Kandji"])
        await ctl.handle(.beganHold)
        await ctl.handle(.endedHold)
        #expect(inserter.inserted.first == "Reviewing the Salla dashboard with Kandji.")
    }

    @Test("with no dictionary the text is untouched") func noTerms() async {
        let (ctl, inserter) = rig(cleanupReturns: "Reviewing the Sala dashboard.", terms: [])
        await ctl.handle(.beganHold)
        await ctl.handle(.endedHold)
        #expect(inserter.inserted.first == "Reviewing the Sala dashboard.")
    }

    @Test("correction runs before snippet expansion, not after") func order() async {
        let r = FakeRecorder(), e = FakeEngine(), c = FakeCleanup()
        let i = FakeInserter()
        e.result = .success("um raw")
        c.result = .success("ping Kanji now")
        let ctl = DictationController(config: .default, recorder: r, engine: e,
                                      cleanup: c, inserter: i, log: FakeLog())
        ctl.vocabulary = {
            VocabularySnapshot(whisperPrompt: "", glossary: "", terms: ["Kandji"],
                               snippets: [Snippet(trigger: "Kandji", expansion: "the MDM")])
        }
        await ctl.handle(.beganHold)
        await ctl.handle(.endedHold)
        // Corrected to "Kandji" first, which the snippet then matches.
        #expect(i.inserted.first == "ping the MDM now")
    }
}
