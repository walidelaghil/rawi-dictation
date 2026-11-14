import Testing
@testable import RawiCore

@Suite("FirstRunSetup") struct FirstRunSetupTests {
    func probes(env: Set<String> = [], ollama: Bool = false,
                bin: Bool = true, model: Bool = true, multi: Bool? = nil) -> Probes {
        Probes(envKeys: env, ollamaReachable: ollama,
               whisperBinaryFound: bin, whisperModelFound: model,
               multilingualModelFound: multi ?? model)
    }

    @Test("a Groq key wins even when local whisper is installed") func groqFirst() {
        #expect(FirstRunSetup.detect(probes(env: ["GROQ_API_KEY"])).engine == .groq)
    }

    @Test("local whisper is used when installed and there is no Groq key") func localEngine() {
        #expect(FirstRunSetup.detect(probes()).engine == .whispercpp)
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

    @Test("with nothing available it stays on Groq, and setup asks for the key") func nothing() {
        #expect(FirstRunSetup.detect(probes(bin: false, model: false)).engine == .groq)
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

    @Test("the cleanup models match the chosen provider, per script") func cleanupModel() {
        #expect(FirstRunSetup.detect(probes(env: ["OPENAI_API_KEY"])).cleanup.models.latin
                == "gpt-4o-mini")
        // Local cleanup needs a different model per script: the small one translates Arabic.
        let local = FirstRunSetup.detect(probes(ollama: true)).cleanup.models
        #expect(local.latin == "qwen2.5:1.5b")
        #expect(local.arabic == "qwen2.5:3b")
        #expect(FirstRunSetup.detect(probes(env: ["ANTHROPIC_API_KEY"])).cleanup.models.arabic
                == "claude-haiku-4-5-20251001")
    }

    @Test("an English-only model is not enough for the local path") func needsMultilingual() {
        // small.en present but no multilingual model: Arabic would fail outright,
        // so the local engine must not be chosen on that basis alone.
        let p = probes(env: ["GROQ_API_KEY"], model: true, multi: false)
        #expect(FirstRunSetup.detect(p).engine == .groq)
    }

    @Test("a multilingual model selects the local path with auto language") func multilingual() {
        let c = FirstRunSetup.detect(probes(ollama: true, multi: true))
        #expect(c.engine == .whispercpp)
        #expect(c.whispercpp.language == "auto")
        #expect(c.whispercpp.model.contains("large-v3-turbo"))
    }

    @Test("a config pointing at a missing model asks for a download") func needsDownload() {
        var c = Config.default
        c.engine = .whispercpp
        c.whispercpp.model = "/nowhere/ggml-medium.bin"
        #expect(c.needsModelDownload)
        c.engine = .groq
        #expect(!c.needsModelDownload)   // hosted engines need no local model
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
