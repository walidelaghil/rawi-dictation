import Testing
@testable import RawiCore

@Suite("A spoken enumeration becomes a written list") struct SpokenListsTests {
    @Test("the dictation that prompted this") func theReportedCase() {
        let spoken = "This is a text with bullets so what we need to do is first "
                   + "focus on the customer, second identify the pain, third "
                   + "develop the solution."
        #expect(SpokenLists.format(spoken) == """
            This is a text with bullets so what we need to do is:
            1. Focus on the customer
            2. Identify the pain
            3. Develop the solution
            """)
    }

    @Test("a list with no lead-in starts at the first item") func noIntro() {
        #expect(SpokenLists.format("First call the bank, second send the invoice.")
                == "1. Call the bank\n2. Send the invoice")
    }

    @Test("the joins that only exist in speech are dropped") func leadIns() {
        let spoken = "Firstly we ship it, and secondly we tell them, "
                   + "and then thirdly we watch the logs."
        #expect(SpokenLists.format(spoken) == """
            1. We ship it
            2. We tell them
            3. We watch the logs
            """)
    }

    @Test("two items are a list; one ordinal is a word") func needsTwo() {
        let one = "I first met him in 2019 and we have worked together since."
        #expect(SpokenLists.format(one) == one)
        let opener = "First, let me say thank you for all of the help this week."
        #expect(SpokenLists.format(opener) == opener)
    }

    @Test("an ordinal counting a noun is not an item") func determiners() {
        let counted = "The first day was quiet and the second day was busier."
        #expect(SpokenLists.format(counted) == counted)
        let mine = "My first attempt failed and my second attempt worked."
        #expect(SpokenLists.format(mine) == mine)
    }

    @Test("short items that end in a determiner are still a list") func shortItems() {
        // Reported from real use. Every cue after the first was refused: the item
        // before it ended in "this" or "that", and the guard against "the first
        // day" only looked at the word before the ordinal, not at whether that
        // word was attached to it.
        let out = SpokenLists.format("First this, second that, third the other.")
        #expect(out == "1. This\n2. That\n3. The other", "got: \(out)")
    }

    @Test("a list that never says first is not a list") func mustStartAtOne() {
        let text = "We talked about the plan, second guessing every part of it."
        #expect(SpokenLists.format(text) == text)
    }

    @Test("items that are whole sentences keep their punctuation") func sentences() {
        let spoken = "Two things. First, the build is green. I checked it twice. "
                   + "Second, the release notes are written."
        let out = SpokenLists.format(spoken)
        #expect(out.contains("1. The build is green. I checked it twice."))
        #expect(out.contains("2. The release notes are written"))
    }

    @Test("Arabic counts the same way") func arabic() {
        let spoken = "الخطة هي أولا نراجع الطلب، ثانيا نرسل الفاتورة، ثالثا نتابع معهم."
        let out = SpokenLists.format(spoken)
        #expect(out.hasPrefix("الخطة هي:\n1. "))
        #expect(out.contains("\n2. "))
        #expect(out.contains("\n3. "))
        #expect(!out.contains("ثانيا"))
    }

    @Test("text that is already laid out is left alone") func alreadyFormatted() {
        let done = "Plan:\n1. First draft\n2. Second draft"
        #expect(SpokenLists.format(done) == done)
    }

    @Test("every word you said survives the reshaping") func nothingLost() {
        let spoken = "We agreed on three things, first hire the designer, second "
                   + "cut the scope, third ship in March."
        let out = SpokenLists.format(spoken)
        let lowered = out.lowercased()
        for word in ["hire", "designer", "cut", "scope", "ship", "march", "agreed"] {
            #expect(lowered.contains(word), "lost \(word)")
        }
    }

    @Test("ordinary prose is returned untouched") func leavesProseAlone() {
        let prose = "Let us move the launch date back by one week."
        #expect(SpokenLists.format(prose) == prose)
        #expect(SpokenLists.format("") == "")
    }
}
