import Testing
import Foundation
@testable import RawiCore

@Suite("Language detection") struct LanguageDetectorTests {
    @Test("reads the language and how sure it is") func parse() {
        let line = "whisper_full_with_state: auto-detected language: ar (p = 0.995071)"
        let d = LanguageDetector.parse(line)
        #expect(d?.language == "ar")
        #expect(abs((d?.probability ?? 0) - 0.995071) < 0.0001)
    }

    @Test("finds it among the model's other chatter") func noise() {
        let output = """
            whisper_init_with_params_no_state: use gpu    = 1
            ggml_metal_library_init: using embedded metal library
            whisper_full_with_state: auto-detected language: en (p = 0.888381)
            whisper_print_timings:     load time =   203.80 ms
            """
        #expect(LanguageDetector.parse(output)?.language == "en")
    }

    @Test("says nothing rather than guessing when the line is absent") func absent() {
        #expect(LanguageDetector.parse("") == nil)
        #expect(LanguageDetector.parse("whisper_print_timings: load time = 1 ms") == nil)
    }

    @Test("a missing probability is treated as certain, not as zero") func noProbability() {
        let d = LanguageDetector.parse("auto-detected language: fr")
        #expect(d?.language == "fr")
        #expect(d?.probability == 1)
    }

    @Test("the floor is what stops a guess becoming a wrong transcription") func floor() {
        // Below it the caller pays for a full auto pass instead. Slow is
        // recoverable; Arabic transcribed as English is not.
        #expect(LanguageDetector.confidenceFloor > 0.5)
        #expect(LanguageDetector.confidenceFloor < 0.9)
    }
}
