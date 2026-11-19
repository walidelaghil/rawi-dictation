import Testing
import Foundation
@testable import RawiCore

/// Code-switched speech was being translated. Whisper decodes one language per
/// recording, so a sentence that starts in Arabic and turns English came back
/// all English, with the Arabic translated or dropped. Measured on synthetic
/// speech, 12 mixed sentences, whisper-large-v3-turbo on Groq: 6 of 12 lost or
/// translated a language. whisper-large-v3 with a mixed-script primer: 0 of 12.
/// The primer hurts clips under about two seconds, which is why they skip it.
@Suite("Mixed Arabic and English speech") struct MixedSpeechTests {
    @Test("a long enough clip with no chosen language uses the mixed-speech plan")
    func longAuto() {
        let plan = WhisperAPIEngine.plan(model: "whisper-large-v3-turbo",
                                         mixedModel: "whisper-large-v3",
                                         language: nil, seconds: 5, dictionary: "")
        #expect(plan.model == "whisper-large-v3")
        #expect(plan.prompt.contains("يعني"))
        #expect(plan.prompt.contains("project"))
    }

    @Test("a short clip keeps the fast model and no primer")
    func shortClip() {
        let plan = WhisperAPIEngine.plan(model: "whisper-large-v3-turbo",
                                         mixedModel: "whisper-large-v3",
                                         language: nil, seconds: 1.2, dictionary: "")
        #expect(plan.model == "whisper-large-v3-turbo")
        #expect(plan.prompt.isEmpty)
    }

    @Test("a language you chose is never second-guessed")
    func chosen() {
        let plan = WhisperAPIEngine.plan(model: "whisper-large-v3-turbo",
                                         mixedModel: "whisper-large-v3",
                                         language: "ar", seconds: 9, dictionary: "Salla")
        #expect(plan.model == "whisper-large-v3-turbo")
        #expect(plan.prompt == "Salla")
    }

    @Test("the dictionary rides along after the primer")
    func dictionary() {
        let plan = WhisperAPIEngine.plan(model: "m", mixedModel: "v3",
                                         language: nil, seconds: 4, dictionary: "Kandji")
        #expect(plan.prompt.hasSuffix("Kandji"))
    }

    @Test("no mixed model configured means nothing changes")
    func disabled() {
        let plan = WhisperAPIEngine.plan(model: "m", mixedModel: nil,
                                         language: nil, seconds: 9, dictionary: "x")
        #expect(plan.model == "m")
        #expect(plan.prompt == "x")
    }

    @Test("a recording's length is read from its size")
    func seconds() {
        // 16 kHz, 16-bit, mono: 32,000 bytes a second after the 44-byte header.
        #expect(abs(AudioFile.seconds(bytes: 44 + 64_000) - 2.0) < 0.001)
        #expect(AudioFile.seconds(bytes: 10) == 0)
    }
}

@Suite("Mixed speech primer") struct MixedPrimerTests {
    @Test("the primer is one short mixed sentence, not a passage the decoder can repeat")
    func shape() {
        let primer = WhisperAPIEngine.mixedPrimer
        #expect(primer.contains("project"))
        #expect(primer.contains("يعني"))
        #expect(primer.count < 60)
        #expect(!primer.contains("."))
    }
}

/// On the user's real mixed recording, whisper-large-v3 with the primer translated
/// English words into formal Arabic ("meeting" became مقابلة); turbo with only the
/// dictionary kept the speaker's own words and 8 of 14 English words in Latin, and
/// the restore pass took it to 14. So the primer path is opt-in, not the default.
@Suite("Mixed speech default") struct MixedSpeechDefaultTests {
    @Test("the long-model primer is off unless a config asks for it")
    func offByDefault() throws {
        let api = try JSONDecoder().decode(APISettings.self, from: Data("{}".utf8))
        #expect(api.groqMixedModel.isEmpty)
    }
}
