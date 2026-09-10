import Testing
@testable import WhisperFlowCore

@Suite("FirstRunSetup") struct FirstRunSetupTests {
    func probes(env: Set<String> = [], ollama: Bool = false,
                bin: Bool = true, model: Bool = true) -> Probes {
        Probes(envKeys: env, ollamaReachable: ollama,
               whisperBinaryFound: bin, whisperModelFound: model)
    }

    @Test("local whisper wins when binary and model are present") func localEngine() {
        #expect(FirstRunSetup.detect(probes(env: ["GROQ_API_KEY"])).engine == .whispercpp)
    }

    @Test("falls back to groq when the model is missing") func groqFallback() {
        #expect(FirstRunSetup.detect(probes(env: ["GROQ_API_KEY"], model: false)).engine == .groq)
    }

    @Test("falls back to openai when only that key exists") func openaiFallback() {
        #expect(FirstRunSetup.detect(probes(env: ["OPENAI_API_KEY"], bin: false, model: false))
                .engine == .openai)
    }

    @Test("groq is preferred over openai for transcription") func groqBeatsOpenAI() {
        let p = probes(env: ["GROQ_API_KEY", "OPENAI_API_KEY"], bin: false, model: false)
        #expect(FirstRunSetup.detect(p).engine == .groq)
    }

    @Test("with nothing available it still names a working local engine") func nothing() {
        #expect(FirstRunSetup.detect(probes(bin: false, model: false)).engine == .whispercpp)
    }

    @Test("openai key wins for cleanup") func cleanupOpenAI() {
        #expect(FirstRunSetup.detect(probes(env: ["OPENAI_API_KEY"], ollama: true))
                .cleanup.provider == .openai)
    }

    @Test("anthropic is used when it is the only key") func cleanupAnthropic() {
        #expect(FirstRunSetup.detect(probes(env: ["ANTHROPIC_API_KEY"], ollama: true))
                .cleanup.provider == .anthropic)
    }

    @Test("ollama is used when no key exists but it is running") func cleanupOllama() {
        #expect(FirstRunSetup.detect(probes(ollama: true)).cleanup.provider == .ollama)
    }

    @Test("cleanup is off with no keys and no ollama") func cleanupOff() {
        #expect(FirstRunSetup.detect(probes()).cleanup.provider == .off)
    }

    @Test("the cleanup model matches the chosen provider") func cleanupModel() {
        #expect(FirstRunSetup.detect(probes(env: ["OPENAI_API_KEY"])).cleanup.model == "gpt-4o-mini")
        #expect(FirstRunSetup.detect(probes(ollama: true)).cleanup.model == "qwen2.5:3b")
        #expect(FirstRunSetup.detect(probes(env: ["ANTHROPIC_API_KEY"])).cleanup.model
                == "claude-haiku-4-5-20251001")
    }

    @Test("detection never leaves the hotkey unset") func hotkey() {
        #expect(FirstRunSetup.detect(probes()).hotkey == "fn")
        #expect(FirstRunSetup.detect(probes()).maxSessionSeconds == 300)
    }

    @Test("a detected config always builds working providers") func buildsProviders() throws {
        let env = DotEnv(contents: "")
        let config = FirstRunSetup.detect(probes())
        _ = try TranscriptionEngineFactory.make(config: config, env: env)
        _ = try CleanupProviderFactory.make(config: config, env: env)
    }
}
