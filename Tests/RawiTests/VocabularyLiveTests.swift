import Testing
import Foundation
@testable import RawiCore

/// The whole vocabulary path on real audio and the real models: transcribe →
/// clean → correct → expand. Everything a dictation does except capturing from
/// the microphone, which no automated test can stand in for.
@Suite("Vocabulary end to end") struct VocabularyLiveTests {
    static var ready: Bool {
        ModelStore.isInstalled(ModelStore.recommended)
            && WhisperCppEngine.resolveBinary("whisper-cli") != nil
            && OllamaCleanupIntegrationTests.isAvailable
    }

    func say(_ text: String) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("rawi-vocab-\(UUID().uuidString).wav")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        p.arguments = ["-o", url.path, "--data-format=LEI16@16000", text]
        try p.run(); p.waitUntilExit()
        return url
    }

    @Test("a dictionary term whisper mishears comes out spelled correctly",
          .enabled(if: VocabularyLiveTests.ready), .timeLimit(.minutes(3)))
    func correctsRealTranscript() async throws {
        let store = VocabularyStore(url: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("rawi-v-\(UUID().uuidString).json"))
        store.addTerm("Salla"); store.addTerm("Kandji")
        store.addSnippet(trigger: "my email", expansion: "rawi@example.com")
        let vocabulary = store.snapshot()

        let wav = try say("I am reviewing the Salla dashboard with Kandji "
                        + "and you can reach me at my email")
        defer { try? FileManager.default.removeItem(at: wav) }

        let engine = WhisperCppEngine(
            binary: "whisper-cli",
            model: ModelStore.url(for: ModelStore.recommended).path,
            language: "en", threads: 8)
        let raw = try await engine.transcribe(wav: wav, prompt: vocabulary.whisperPrompt)
        #expect(!raw.isEmpty)

        let cleanup = ChatCleanup(kind: .ollama, apiKey: nil, model: "qwen2.5:1.5b",
                                  prompt: defaultCleanupPrompt + vocabulary.glossary)
        var text = (try? await cleanup.clean(raw)) ?? raw
        if case .reject = CleanupGuard.check(raw: raw, cleaned: text) { text = raw }

        // The two steps that must not depend on a model's cooperation.
        text = TermCorrector.apply(text, terms: vocabulary.terms)
        text = SnippetExpander.expand(text, with: vocabulary.snippets)

        #expect(text.contains("Salla"), "raw was: \(raw)\nfinal: \(text)")
        #expect(text.contains("Kandji"), "raw was: \(raw)\nfinal: \(text)")
        #expect(text.contains("rawi@example.com"),
                "snippet did not expand\nraw: \(raw)\nfinal: \(text)")
        #expect(!text.contains("my email"), "trigger text survived: \(text)")
    }

    @Test("the corrector fixes what whisper actually got wrong",
          .enabled(if: VocabularyLiveTests.ready), .timeLimit(.minutes(3)))
    func fixesActualMishearing() async throws {
        // Spoken so whisper is likely to mishear, which is the real case.
        let wav = try say("the Sala team uses Kanji for devices")
        defer { try? FileManager.default.removeItem(at: wav) }

        let engine = WhisperCppEngine(
            binary: "whisper-cli",
            model: ModelStore.url(for: ModelStore.recommended).path,
            language: "en", threads: 8)
        let raw = try await engine.transcribe(wav: wav, prompt: "")
        let corrected = TermCorrector.apply(raw, terms: ["Salla", "Kandji"])

        // Whatever whisper produced, the dictionary spelling wins.
        #expect(corrected.contains("Salla") || !raw.lowercased().contains("sal"),
                "raw: \(raw)\ncorrected: \(corrected)")
        #expect(corrected.contains("Kandji") || !raw.lowercased().contains("kan"),
                "raw: \(raw)\ncorrected: \(corrected)")
    }
}
