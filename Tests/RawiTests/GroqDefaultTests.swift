import Foundation
import Testing
@testable import RawiCore

@Suite("Groq by default") struct GroqDefaultTests {
    func probes(keys: Set<String> = [], local: Bool = false, ollama: Bool = false) -> Probes {
        Probes(envKeys: keys, ollamaReachable: ollama, whisperBinaryFound: local,
               whisperModelFound: local, multilingualModelFound: local)
    }

    @Test("a fresh install is Groq for speech and polish") func defaults() {
        #expect(Config.default.engine == .groq)
        #expect(Config.default.cleanup.provider == .groq)
        #expect(Config.default.cleanup.models == CleanupProviderFactory.defaultModels(for: .groq))
    }

    @Test("a Groq key wins over a local install") func keyWins() {
        let c = FirstRunSetup.detect(probes(keys: ["GROQ_API_KEY"], local: true, ollama: true))
        #expect(c.engine == .groq)
        #expect(c.cleanup.provider == .groq)
    }

    @Test("without a key, what is installed locally is used") func localWithoutKey() {
        let c = FirstRunSetup.detect(probes(local: true, ollama: true))
        #expect(c.engine == .whispercpp)
        #expect(c.cleanup.provider == .ollama)
    }

    @Test("with nothing at all, Groq stays selected and setup asks for the key") func nothing() {
        let c = FirstRunSetup.detect(probes())
        #expect(c.engine == .groq)
        let status = SetupStatus(microphone: true, accessibility: true, inputMonitoring: true,
                                 whisperInstalled: true, transcriptionModel: false,
                                 detectorModel: true, ollamaReachable: false, ollamaMissing: [])
        let speech = SetupChecklist.make(status: status, config: c).items.first { $0.title == "Speech model" }
        #expect(speech?.done == false)
        #expect(speech?.detail.contains("Groq key") == true)
    }

    @Test("polish on Groq is ready only with the key") func polish() {
        var s = SetupStatus(microphone: true, accessibility: true, inputMonitoring: true,
                            whisperInstalled: true, transcriptionModel: true, detectorModel: true,
                            ollamaReachable: false, ollamaMissing: [])
        #expect(!s.polishReady(provider: .groq))
        s.groqKey = true
        #expect(s.polishReady(provider: .groq))
    }

    @Test("saving a key replaces every old line and keeps the rest") func save() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = dir.appendingPathComponent(".env")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try "OPENAI_API_KEY=sk-1\nGROQ_API_KEY=your-key-here\n# note\nexport GROQ_API_KEY=old\n"
            .write(to: url, atomically: true, encoding: .utf8)
        try GroqKey.save("  gsk_new \n", to: url)
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text == "OPENAI_API_KEY=sk-1\n# note\nGROQ_API_KEY=gsk_new\n")
        let mode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        #expect(mode == 0o600)
        #expect(throws: GroqKey.Problem.self) { try GroqKey.save("  ", to: url) }
    }

    @Test("switching to Groq drops pins made for another provider") func useGroq() {
        var c = Config.default
        c.engine = .whispercpp
        c.cleanup.provider = .ollama
        c.cleanup.transformModel = "gemma3:4b"
        GroqKey.useGroq(&c)
        #expect(c.engine == .groq && c.cleanup.provider == .groq)
        #expect(c.cleanup.transformModel.isEmpty)
    }

    @Test("the sidebar says where your words go") func privacy() {
        var c = Config.default
        #expect(PrivacyNote.describe(c).title == "Voice and text go to Groq")
        c.engine = .whispercpp; c.cleanup.provider = .off
        #expect(PrivacyNote.describe(c).title == "Stays on this Mac")
        c.cleanup.provider = .ollama
        #expect(PrivacyNote.describe(c).title == "Stays on this Mac")
        c.cleanup.provider = .anthropic
        #expect(PrivacyNote.describe(c).title == "Text goes to Anthropic")
        c.engine = .groq
        #expect(PrivacyNote.describe(c).title == "Voice to Groq, text to Anthropic")
    }
}
