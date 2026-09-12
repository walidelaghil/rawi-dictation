import Testing
import Foundation
@testable import RawiCore

@Suite("WhisperCppEngine") struct WhisperCppEngineTests {
    @Test("strips residual bracket tokens and collapses whitespace") func clean() {
        #expect(WhisperCppEngine.cleanTranscript("  [BLANK_AUDIO]\n Hello   there. \n")
                == "Hello there.")
        #expect(WhisperCppEngine.cleanTranscript("(wind blowing) Testing one two")
                == "Testing one two")
        #expect(WhisperCppEngine.cleanTranscript("Line one.\nLine two.")
                == "Line one. Line two.")
    }

    @Test("an all-noise transcript cleans to empty") func allNoise() {
        #expect(WhisperCppEngine.cleanTranscript("[BLANK_AUDIO]").isEmpty)
        #expect(WhisperCppEngine.cleanTranscript("   \n  ").isEmpty)
    }

    @Test("resolves the homebrew binary on this machine") func resolve() throws {
        let url = try #require(WhisperCppEngine.resolveBinary("whisper-cli"))
        #expect(FileManager.default.isExecutableFile(atPath: url.path))
    }

    @Test("a missing binary resolves to nil") func missing() {
        #expect(WhisperCppEngine.resolveBinary("definitely-not-a-real-binary-xyz") == nil)
    }

    @Test("an absolute path is honoured, and rejected when not executable") func absolute() {
        #expect(WhisperCppEngine.resolveBinary("/bin/sh") != nil)
        #expect(WhisperCppEngine.resolveBinary("/nope/whisper-cli") == nil)
    }

    @Test("a missing model surfaces modelNotFound before spawning") func noModel() async {
        let e = WhisperCppEngine(binary: "whisper-cli", model: "/nope/missing.bin",
                                 language: "en", threads: 4)
        await #expect(throws: TranscriptionError.modelNotFound("/nope/missing.bin")) {
            _ = try await e.transcribe(wav: URL(fileURLWithPath: "/tmp/x.wav"))
        }
    }

    @Test("a missing binary surfaces binaryNotFound before spawning") func noBinary() async {
        let e = WhisperCppEngine(binary: "not-a-real-binary-xyz", model: "/tmp/m.bin",
                                 language: "en", threads: 4)
        await #expect(throws: TranscriptionError.binaryNotFound("not-a-real-binary-xyz")) {
            _ = try await e.transcribe(wav: URL(fileURLWithPath: "/tmp/x.wav"))
        }
    }
}
