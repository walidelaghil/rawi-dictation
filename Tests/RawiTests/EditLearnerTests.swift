import Testing
@testable import RawiCore

@Suite("Learning from what you fix") struct EditLearnerTests {
    /// The real spell checker, so these read the way the app will.
    func learn(_ inserted: String, _ current: String) -> [Correction] {
        EditLearner.corrections(inserted: inserted, current: current,
                                isOrdinaryWord: SpellCheck.isOrdinaryEnglish)
    }

    @Test("a name you fix is learned") func name() {
        let found = learn("Can you send the contract to Sala before Friday?",
                          "Can you send the contract to Salla before Friday?")
        #expect(found == [Correction(heard: "Sala", fixed: "Salla", aliasable: true)])
    }

    @Test("a fix at the very end of the dictation counts") func atTheEnd() {
        #expect(learn("I will send it to Sala", "I will send it to Salla").map(\.fixed) == ["Salla"])
    }

    @Test("a brand whisper cannot spell, fixed far from what it heard") func farButSame() {
        let found = learn("We manage the laptops with Kanjee now.",
                          "We manage the laptops with Kandji now.")
        #expect(found.map(\.fixed) == ["Kandji"])
        #expect(found.first?.aliasable == true)          // "kanjee" is not a word
    }

    @Test("fixing an ordinary word to a name does not make the word an alias") func notAlias() {
        let found = learn("Ask cloud to review the pull request.",
                          "Ask Claude to review the pull request.")
        #expect(found.map(\.fixed) == ["Claude"])
        #expect(found.first?.aliasable == false)         // every cloud stays a cloud
    }

    @Test("wording and grammar are not vocabulary") func wording() {
        #expect(learn("I think their going to be late today.",
                      "I think they're going to be late today.").isEmpty)
        #expect(learn("The meeting is on Tuesday at noon.",
                      "The meeting is on Friday at noon.").isEmpty)
    }

    @Test("capitalising the start of a sentence is not a name") func sentenceCase() {
        #expect(learn("okay send it over when ready", "Okay send it over when ready").isEmpty)
    }

    @Test("a rewrite teaches nothing") func rewrite() {
        #expect(learn("Can you send the contract to Sala before Friday?",
                      "Please forward the signed agreement to legal today.").isEmpty)
    }

    @Test("an unchanged dictation teaches nothing") func unchanged() {
        let text = "Send the deck to Salla before Friday."
        #expect(learn(text, text).isEmpty)
    }

    @Test("adding words is not correcting them") func additions() {
        #expect(learn("Send the deck before Friday.",
                      "Send the final deck to Salla before Friday morning.").isEmpty)
    }

    @Test("a two-word name fixed word for word") func twoWords() {
        let found = learn("Our client is Argo Seedy and they renew in May.",
                          "Our client is Argo CD and they renew in May.")
        #expect(found.isEmpty || found.allSatisfy { $0.fixed != "and" })
    }
}

@Suite("Learning from what you fix, the cases real use found") struct EditLearnerRealCases {
    func learn(_ inserted: String, _ current: String) -> [Correction] {
        EditLearner.corrections(inserted: inserted, current: current,
                                isOrdinaryWord: SpellCheck.isOrdinaryEnglish)
    }

    @Test("an ordinary word capitalised at the start of a sentence is not a name") func rawAtStart() {
        #expect(learn("Rawal is the app I am building.", "Raw is the app I am building.").isEmpty)
    }

    @Test("an ordinary word capitalised mid-sentence can be a product") func slackMidSentence() {
        #expect(learn("Post it in slak before lunch.", "Post it in Slack before lunch.").map(\.fixed) == ["Slack"])
    }

    @Test("the finished word is learned") func rawi() {
        #expect(learn("Rawal is the app I am building.", "Rawi is the app I am building.").map(\.fixed) == ["Rawi"])
    }

    @Test("sentence starts are found after any sentence end") func starts() {
        #expect(EditLearner.sentenceStarts("One two. Three four! five\nsix") == [0, 2, 4, 5])
    }
}
