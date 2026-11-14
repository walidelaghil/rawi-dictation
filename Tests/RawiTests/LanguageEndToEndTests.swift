import Testing
import Foundation
@testable import RawiCore

/// Proves the real pipeline handles both languages through ONE configuration —
/// the thing v1 could not do, because its model was English-only.
/// Skipped when the multilingual model or whisper-cli is absent.
@Suite("Language end to end", .serialized) struct LanguageEndToEndTests {
    static var ready: Bool {
        ModelStore.isInstalled(ModelStore.recommended)
            && WhisperCppEngine.resolveBinary("whisper-cli") != nil
    }

    func engine() -> WhisperCppEngine {
        WhisperCppEngine(binary: "whisper-cli",
                         model: ModelStore.url(for: ModelStore.recommended).path,
                         language: "auto", threads: 8)
    }

    func say(_ text: String, voice: String?) throws -> URL {
        try SpokenAudio.wav(text, voice: voice, prefix: "rawi-e2e")
    }

    @Test("one configuration transcribes English",
          .enabled(if: LanguageEndToEndTests.ready), .timeLimit(.minutes(2)))
    func english() async throws {
        let wav = try say("The deploy to staging finished successfully", voice: nil)
        defer { try? FileManager.default.removeItem(at: wav) }
        let text = try await engine().transcribe(wav: wav).lowercased()
        #expect(text.contains("deploy"))
        #expect(text.contains("staging"))
        #expect(ScriptDetector.detect(text) == .latin)
    }

    @Test("the same configuration transcribes Arabic",
          .enabled(if: LanguageEndToEndTests.ready), .timeLimit(.minutes(2)))
    func arabic() async throws {
        let wav = try say("الاجتماع يوم الاثنين والتقرير غير جاهز", voice: "Majed")
        defer { try? FileManager.default.removeItem(at: wav) }
        let text = try await engine().transcribe(wav: wav)
        #expect(!text.isEmpty)
        // The v1 bug: this came back English or empty. It must now be Arabic.
        #expect(ScriptDetector.detect(text) == .arabic, "expected Arabic script, got: \(text)")
    }

    @Test("each language routes to a cleanup model that will not break it",
          .enabled(if: LanguageEndToEndTests.ready), .timeLimit(.minutes(2)))
    func routing() async throws {
        let wav = try say("الاجتماع يوم الاثنين والتقرير غير جاهز", voice: "Majed")
        defer { try? FileManager.default.removeItem(at: wav) }
        let text = try await engine().transcribe(wav: wav)

        let router = RoutedCleanup(kind: .ollama, apiKey: nil,
                                   models: CleanupProviderFactory.defaultModels(for: .ollama),
                                   prompt: "P")
        #expect(router.model(for: text) == "qwen2.5:3b")
        #expect(router.model(for: "ship the release on Friday") == "qwen2.5:1.5b")
    }
}
