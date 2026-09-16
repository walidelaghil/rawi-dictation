import Foundation
import Testing
@testable import RawiCore

@Suite("Rewriting a long dictation in pieces") struct PolishChunksTests {
    let long = "I tried the transform for the below text but it just gave me the same "
             + "thing. Is this because the instructions are unclear in the app or is there "
             + "an issue? Also, can you enable users to edit the existing transformation? "
             + "One final thing. I have tried dictating the entire above message but there "
             + "was a lot of things that got cut off and adjusted to an extent that I felt "
             + "it was transformed. How can we ensure that the dictation does not remove "
             + "what the user actually said, but removes the filler words like um, and "
             + "provides better structure only."

    @Test("a short dictation goes to the model whole") func shortStaysWhole() {
        let short = "The meeting is on Monday, no wait, Tuesday at four o'clock."
        #expect(PolishChunks.split(short) == [short])
    }

    @Test("a long one is cut at sentence boundaries") func longIsSplit() {
        let pieces = PolishChunks.split(long)
        #expect(pieces.count > 1)
        // Nothing invented, nothing lost: the pieces put back together are the
        // dictation, word for word.
        let rejoined = pieces.joined(separator: " ").split(whereSeparator: \.isWhitespace)
        let original = long.split(whereSeparator: \.isWhitespace)
        #expect(rejoined.map(String.init) == original.map(String.init))
        // And no piece is a fragment: each ends a sentence.
        for piece in pieces {
            #expect(".?!".contains(piece.last!), "piece ends mid-sentence: \(piece)")
        }
    }

    @Test("a piece is several sentences, so a correction still meets its words")
    func piecesHoldContext() {
        for piece in PolishChunks.split(long) {
            #expect(SpokenParagraphs.sentencesOf(piece).count >= 2)
        }
    }

    @Test("one long sentence is not cut in half") func oneSentence() {
        let rambling = String(repeating: "and then we talked about the roadmap ", count: 12)
        #expect(PolishChunks.split(rambling).count == 1)
    }

    @Test("an empty dictation is one empty piece") func empty() {
        #expect(PolishChunks.split("   ") == [""])
    }
}
