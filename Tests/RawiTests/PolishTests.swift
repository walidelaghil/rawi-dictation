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

    @Test("a sentence that vanishes is refused") func refusesDroppedSentence() {
        // Verbatim from the end-to-end run that found this: qwen2.5:3b kept the
        // first sentence, deleted the second, and put an invented word where it
        // had been. Every ratio the guard had was satisfied — more than half the
        // characters survived, and the invented word shared its first four
        // characters with a word that had been said.
        let raw = "المهاجرة انتهت الليلة الماضية وكل الخدمات رجعت تشتغل بشكل ممتاز. "
                + "بالمناسبة راجعت صفحة الأسعار وأعتقد أن الباقة الوسطى تربك العملاء."
        let polished = "المهاجرة انتهت الليلة الماضية وكل الخدمات رجعت تشتغل بشكل متاز بالمتحزبين."
        #expect(PolishGuard.check(raw: raw, polished: polished) != .accept)
    }

    @Test("an honest Arabic rewrite still passes") func acceptsArabic() {
        let raw = "راجعت صفحة الأسعار وأعتقد أن الباقة الوسطى تربك العملاء بصراحة."
        let polished = "راجعت صفحة الأسعار، وأعتقد أن الباقة الوسطى تربك العملاء."
        #expect(PolishGuard.check(raw: raw, polished: polished) == .accept)
    }

    @Test("Arabic words are told apart by the word, not by four characters of grammar")
    func arabicStemsDoNotCollide() {
        // "by the way" and a word nobody said share "بالم".
        #expect(PolishGuard.stem("بالمناسبة") != PolishGuard.stem("بالمتحزبين"))
        // The article and the conjunction are grammar, and do not make a new word.
        #expect(PolishGuard.stem("الخدمات") == PolishGuard.stem("خدمات"))
        #expect(PolishGuard.stem("والعملاء") == PolishGuard.stem("العملاء"))
        // A dropped letter is a different word, not an inflection of one.
        #expect(PolishGuard.stem("ممتاز") != PolishGuard.stem("متاز"))
    }

    @Test("a false start is still allowed to disappear") func keepsApplyingCorrections() {
        // The sentence check must not catch this: the middle sentence is a false
        // start, and deleting it is the whole point of polishing.
        let raw = "The pricing review moved to Tuesday because half the leadership "
                + "team is travelling on Monday. No wait, scratch that, it was "
                + "Wednesday. Either way the deck has to be finished before the weekend."
        let polished = "The pricing review moved to Wednesday because half the "
                     + "leadership team is travelling on Monday. Either way, the deck "
                     + "has to be finished before the weekend."
        #expect(PolishGuard.check(raw: raw, polished: polished) == .accept)
    }
}

@Suite("Choosing the polish model") struct PolishRoutingTests {
    @Test("English goes to the fast model, anything with Arabic to the one that keeps it") func routes() async throws {
        let latin = FakeCleanup(), arabic = FakeCleanup()
        latin.result = .success("latin")
        arabic.result = .success("arabic")
        let router = ScriptRoutedProvider(latin: latin, arabic: arabic)
        #expect(try await router.clean("Send it to Sara.", instruction: "") == "latin")
        #expect(try await router.clean("الاجتماع يوم الثلاثاء", instruction: "") == "arabic")
        // One Arabic word in an English sentence: the small model would translate it.
        #expect(try await router.clean("Send the تقرير to Sara before Friday.", instruction: "") == "arabic")
    }

    @Test("cancelling reaches both models") func cancelsBoth() {
        let latin = FakeCleanup(), arabic = FakeCleanup()
        ScriptRoutedProvider(latin: latin, arabic: arabic).cancel()
        #expect(latin.cancelCount == 1 && arabic.cancelCount == 1)
    }

    @Test("with two local models, polish routes; a pinned model is used for everything") func factory() throws {
        var config = Config.default
        config.cleanup.provider = .ollama
        config.cleanup.mode = .polish
        config.cleanup.models = CleanupModels(latin: "qwen2.5:1.5b", arabic: "qwen2.5:3b")
        let routed = try CleanupProviderFactory.makePolisher(config: config, env: DotEnv(contents: ""))
        #expect(routed is ScriptRoutedProvider)
        config.cleanup.polishModel = "qwen2.5:3b"
        let pinned = try CleanupProviderFactory.makePolisher(config: config, env: DotEnv(contents: ""))
        #expect(pinned is ChatCleanup)
        config.cleanup.mode = .clean
        let none = try CleanupProviderFactory.makePolisher(config: config, env: DotEnv(contents: ""))
        #expect(none == nil)
    }
}
