import Testing
@testable import RawiCore

/// whisper-large-v3 with a full-sentence primer answered "Testing the recording."
/// with "Testing the recording. Testing the recording." on real recordings, and
/// 6 of the 12 dictations of 2 seconds or more that followed were doubled. The
/// primer is fixed; this is the net for any other way a decoder says it twice.
@Suite("Repeated transcripts") struct RepeatedTranscriptTests {
    @Test("a sentence said twice, verbatim, is kept once")
    func doubled() {
        #expect(RepeatedTranscript.collapse("Testing the recording. Testing the recording.")
                == "Testing the recording.")
    }

    @Test("a whole passage said twice is kept once")
    func passage() {
        let once = "Fix the three points. Then run the app."
        #expect(RepeatedTranscript.collapse(once + " " + once) == once)
    }

    @Test("Arabic repeats too, ignoring punctuation and case")
    func arabic() {
        #expect(RepeatedTranscript.collapse("هل وصلتك الرسالة؟ هل وصلتك الرسالة") == "هل وصلتك الرسالة؟")
    }

    @Test("something said once is untouched")
    func once() {
        let text = "I think we should ship it today. Because the team is ready."
        #expect(RepeatedTranscript.collapse(text) == text)
    }

    @Test("a short emphatic repeat is a choice, not an error")
    func emphasis() {
        #expect(RepeatedTranscript.collapse("No. No.") == "No. No.")
        #expect(RepeatedTranscript.collapse("Go. Go.") == "Go. Go.")
    }

    @Test("a repeat that is not the whole text is left alone")
    func partial() {
        let text = "Testing the recording. Testing the recording. And then we stop."
        #expect(RepeatedTranscript.collapse(text) == text)
    }
}
