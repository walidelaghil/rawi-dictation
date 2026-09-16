import Foundation
import Testing
@testable import RawiCore

@Suite("Whether the dictionary reaches the decoder") struct DecoderHintTests {
    @Test("Latin terms are held back from Arabic speech") func latinHintArabicSpeech() {
        #expect(!DecoderHint.usable("Rawi, Salla, Kandji", forLanguage: "ar"))
        #expect(DecoderHint.filtered("Rawi", forLanguage: "ar").isEmpty)
    }

    @Test("Arabic terms still reach Arabic speech") func arabicHintArabicSpeech() {
        #expect(DecoderHint.usable("سلة، راوي", forLanguage: "ar"))
    }

    @Test("English speech keeps its dictionary") func latinHintLatinSpeech() {
        #expect(DecoderHint.usable("Rawi, Salla, Kandji", forLanguage: "en"))
        #expect(DecoderHint.filtered("Rawi", forLanguage: "en") == "Rawi")
    }

    @Test("with no detected language the hint is kept") func autoKeepsHint() {
        // A Mac without the detector model asks the model to decide. Dropping the
        // hint there would lose the dictionary on every dictation.
        #expect(DecoderHint.usable("Rawi", forLanguage: "auto"))
    }

    @Test("an empty dictionary is nothing to send") func emptyHint() {
        #expect(!DecoderHint.usable("", forLanguage: "en"))
        #expect(!DecoderHint.usable("   ", forLanguage: "ar"))
    }
}
