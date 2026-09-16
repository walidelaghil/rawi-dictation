import Testing
import Foundation
@testable import RawiCore

/// Proves the decoder hint actually changes what whisper produces — the whole
/// premise of layer one. Skipped when the model or binary is absent.
@Suite("Dictionary, live", .serialized) struct DictionaryLiveTests {
    /// A glossary in the cleanup prompt works on a capable model and is ignored by
    /// a small one. Measured: qwen2.5:3b applies it with any phrasing; qwen2.5:1.5b
    /// applies it with none — and 1.5b is what English routes to. So this is
    /// recorded as a *bonus*, never the mechanism. TermCorrector is the guarantee.
    @Test("the glossary helps on a capable model, and is not relied on",
          .enabled(if: DictionaryLiveTests.ready && OllamaCleanupIntegrationTests.isAvailable),
          .timeLimit(.minutes(2)))
    func glossaryIsABonus() async throws {
        let store = VocabularyStore(url: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("rawi-gloss-\(UUID().uuidString).json"))
        store.addTerm("Salla", note: "heard as Sala")
        let cleanup = ChatCleanup(kind: .ollama, apiKey: nil, model: "qwen2.5:3b",
                                  prompt: defaultCleanupPrompt + store.glossaryClause())
        let out = try await cleanup.clean("I am reviewing the Sala merchant dashboard today")
        #expect(out.contains("Salla"), "the capable model should apply it: \(out)")
    }

    static var ready: Bool {
        ModelStore.isInstalled(ModelStore.recommended)
            && WhisperCppEngine.resolveBinary("whisper-cli") != nil
    }

    func engine() -> WhisperCppEngine {
        WhisperCppEngine(binary: "whisper-cli",
                         model: ModelStore.url(for: ModelStore.recommended).path,
                         language: "en", threads: 8)
    }

    func say(_ text: String) throws -> URL {
        try SpokenAudio.wav(text, prefix: "rawi-dict")
    }

    @Test("a decoder hint never makes the transcript worse",
          .enabled(if: DictionaryLiveTests.ready), .timeLimit(.minutes(3)))
    func hintIsHarmless() async throws {
        // Measured on large-v3-turbo: a comma-list hint does not reliably shift
        // the decoder — only one hand-written phrasing did, and every list-shaped
        // sentence failed. It worked on small.en, which is not what ships. So the
        // contract here is the honest one: the hint must not *hurt*. Spelling is
        // enforced by the cleanup glossary, covered by `glossaryFixesSpelling`.
        let wav = try say("The deploy to staging finished successfully")
        defer { try? FileManager.default.removeItem(at: wav) }

        let without = try await engine().transcribe(wav: wav, prompt: "")
        let with = try await engine().transcribe(wav: wav, prompt: "Salla, Kandji, Argo CD")
        for word in ["deploy", "staging"] {
            #expect(with.lowercased().contains(word),
                    "hint degraded the transcript\n without: \(without)\n    with: \(with)")
        }
    }


    @Test("an empty hint changes nothing",
          .enabled(if: DictionaryLiveTests.ready), .timeLimit(.minutes(3)))
    func emptyHintIsInert() async throws {
        let wav = try say("The deploy to staging finished")
        defer { try? FileManager.default.removeItem(at: wav) }
        let a = try await engine().transcribe(wav: wav, prompt: "")
        let b = try await engine().transcribe(wav: wav, prompt: "")
        #expect(a == b)
    }
}
