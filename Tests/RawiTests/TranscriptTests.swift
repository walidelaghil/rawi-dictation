import Testing
@testable import RawiCore

@Suite("What comes back from an engine") struct TranscriptTests {
    @Test("segments arrive on separate lines and leave as one") func joinsLines() {
        // whisper-server's own output, verbatim, for a single spoken sentence.
        let served = " Let us move the launch date back by one week, because the\n"
                   + " billing work is not finished.\n"
        #expect(Transcript.clean(served)
                == "Let us move the launch date back by one week, because the billing work "
                 + "is not finished.")
    }

    @Test("a dictated paragraph is one line, not four") func realCase() {
        let served = "One more thing, I don't have access to the privacy to\n"
                   + " enable this since the computer is controlled by an admin.\n"
                   + " So is there a way you can go around it or enable the\n"
                   + " feature without this?\n"
        let cleaned = Transcript.clean(served)
        #expect(!cleaned.contains("\n"))
        #expect(cleaned.hasPrefix("One more thing"))
        #expect(cleaned.hasSuffix("without this?"))
        #expect(!cleaned.contains("  "))
    }

    @Test("the engine's notes about the recording are not words you said") func annotations() {
        #expect(Transcript.clean("[BLANK_AUDIO] ship it on Monday") == "ship it on Monday")
        #expect(Transcript.clean("ship it (wind blowing) on Monday") == "ship it on Monday")
    }

    @Test("Arabic survives the join unchanged") func arabic() {
        let served = "نرسل التقرير إلى الفريق\n قبل يوم الاثنين.\n"
        #expect(Transcript.clean(served) == "نرسل التقرير إلى الفريق قبل يوم الاثنين.")
    }

    @Test("both engines answer the same way") func sameBehaviour() {
        let served = "first line\n second line\n"
        #expect(WhisperCppEngine.cleanTranscript(served) == Transcript.clean(served))
    }

    @Test("nothing in, nothing out") func empty() {
        #expect(Transcript.clean("   \n\n ") == "")
    }
}
