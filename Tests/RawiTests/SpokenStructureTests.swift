import Testing
@testable import RawiCore

@Suite("Bullets said out loud") struct SpokenBulletTests {
    @Test("bullet point becomes a bullet") func bullets() {
        let spoken = "The agenda is bullet point the budget, bullet point hiring, "
                   + "bullet point the roadmap."
        #expect(SpokenLists.format(spoken) == """
            The agenda is:
            - The budget
            - Hiring
            - The roadmap
            """)
    }

    @Test("the word point is swallowed, with or without it") func pointOptional() {
        #expect(SpokenLists.format("Bring bullet a laptop, bullet a charger.")
                == "Bring:\n- A laptop\n- A charger")
    }

    @Test("one bullet is a word about ammunition") func needsTwo() {
        let one = "He dodged a bullet when the release slipped by a week."
        #expect(SpokenLists.format(one) == one)
    }

    @Test("ordinals win when a dictation uses both") func ordinalsFirst() {
        let spoken = "First write the bullet points, second review them."
        #expect(SpokenLists.format(spoken) == "1. Write the bullet points\n2. Review them")
    }
}

@Suite("A change of subject becomes a paragraph") struct SpokenParagraphTests {
    @Test("the speaker announces the change and gets a blank line") func separately() {
        let spoken = "The build is green. I checked it twice. Separately, the design "
                   + "review is moved to Thursday."
        #expect(SpokenStructure.format(spoken) == """
            The build is green. I checked it twice.

            Separately, the design review is moved to Thursday.
            """)
    }

    @Test("the marker mid-sentence is just a word") func midSentence() {
        let prose = "We priced it separately from the hardware and it still works out."
        #expect(SpokenStructure.format(prose) == prose)
    }

    @Test("a break before the first sentence is not a break") func noLeadingBreak() {
        let spoken = "By the way, the invoice went out this morning."
        #expect(SpokenStructure.format(spoken) == spoken)
    }

    @Test("Arabic announces it too") func arabic() {
        let spoken = "أرسلنا التقرير أمس. بالمناسبة، الاجتماع تأجل إلى الخميس."
        #expect(SpokenStructure.format(spoken).contains("\n\n"))
    }

    @Test("paragraphs and lists compose, each inside its own block") func together() {
        let spoken = "We shipped the beta. One more thing, the plan is first fix the "
                   + "crash, second cut the scope."
        #expect(SpokenStructure.format(spoken) == """
            We shipped the beta.

            One more thing, the plan is:
            1. Fix the crash
            2. Cut the scope
            """)
    }

    @Test("a decimal point does not end a sentence") func decimals() {
        // Caught by the vocabulary suite: splitting here made "release 4.2" into
        // "release 4. 2." on the way into the document.
        let text = "Call Sala about release 4.2."
        #expect(SpokenStructure.format(text) == text)
        #expect(SpokenStructure.format("Ship 1.5 and then 2.0 by March.")
                == "Ship 1.5 and then 2.0 by March.")
    }

    @Test("ordinary prose comes back untouched") func prose() {
        let prose = "Let us move the launch date back by one week. The billing work "
                  + "is not finished."
        #expect(SpokenStructure.format(prose) == prose)
    }
}
