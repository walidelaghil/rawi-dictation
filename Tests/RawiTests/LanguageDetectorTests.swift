import Testing
import Foundation
@testable import RawiCore

@Suite("Language detection") struct LanguageDetectorTests {
    @Test("the floor is what stops a guess becoming a wrong transcription") func floorValue() {
        // Below it the caller pays for a full auto pass instead. Slow is
        // recoverable; Arabic transcribed as English is not.
        #expect(LanguageDetector.confidenceFloor > 0.5)
        #expect(LanguageDetector.confidenceFloor < 0.9)
    }

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

@Suite("Language detection over HTTP") struct LanguageDetectorJSONTests {
    private func data(_ s: String) -> Data { Data(s.utf8) }

    @Test("reads the language and the model's own confidence") func detected() throws {
        // A real answer from whisper-server, detect_language=true + verbose_json.
        let d = try #require(LanguageDetector.parse(json: data("""
        {"task":"transcribe","language":"arabic","duration":7.5,"text":"","segments":[],
         "detected_language":"arabic","detected_language_probability":0.999}
        """)))
        #expect(d.language == "arabic")
        #expect(abs(d.probability - 0.999) < 0.0001)
    }

    @Test("an unsure detection is reported unsure, not certain") func unsure() throws {
        // The regression this guards: the probability was hard-coded to 1, so a
        // coin-flip detection outranked `confidenceFloor` and got used anyway
        // instead of being handed back to the big model.
        let d = try #require(LanguageDetector.parse(json: data("""
        {"detected_language":"english","detected_language_probability":0.41}
        """)))
        #expect(d.probability < LanguageDetector.confidenceFloor)
    }

    @Test("falls back to the plain language field") func plainField() throws {
        let d = try #require(LanguageDetector.parse(json: data(#"{"language":"english"}"#)))
        #expect(d.language == "english")
        #expect(d.probability == 1)
    }

    @Test("nothing usable comes back as nothing") func unusable() {
        #expect(LanguageDetector.parse(json: data(#"{"language":"auto"}"#)) == nil)
        #expect(LanguageDetector.parse(json: data(#"{"language":""}"#)) == nil)
        #expect(LanguageDetector.parse(json: data(#"{"text":""}"#)) == nil)
        #expect(LanguageDetector.parse(json: data("not json at all")) == nil)
    }
}
