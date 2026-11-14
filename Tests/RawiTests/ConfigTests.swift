import Testing
import Foundation
@testable import RawiCore

@Suite("Config") struct ConfigTests {
    @Test("defaults match the spec") func defaults() {
        let c = Config.default
        #expect(c.hotkey == "fn")
        #expect(c.doubleTapWindowMs == 350)
        #expect(c.minHoldMs == 250)
        #expect(c.maxSessionSeconds == 300)
        #expect(c.engine == .groq)
        #expect(c.output.restorePreviousClipboard == false)
    }

    @Test("partial config fills missing keys from defaults") func partial() throws {
        let json = #"{"hotkey":"rightOption","engine":"groq"}"#
        let c = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        #expect(c.hotkey == "rightOption")
        #expect(c.engine == .groq)
        #expect(c.maxSessionSeconds == 300)
        #expect(c.cleanup.provider == Config.default.cleanup.provider)
    }

    @Test("a partial nested object fills its own siblings from defaults") func partialNested() throws {
        let json = #"{"cleanup":{"provider":"ollama"}}"#
        let c = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        #expect(c.cleanup.provider == .ollama)
        #expect(c.cleanup.prompt == defaultCleanupPrompt)
    }

    @Test("round-trips through save and load") func roundTrip() throws {
        var c = Config.default
        c.maxSessionSeconds = 120
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wf-\(UUID().uuidString).json")
        try c.save(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try Config.load(from: url).maxSessionSeconds == 120)
    }

    @Test("unknown enum value throws rather than silently defaulting") func badEnum() {
        let json = #"{"engine":"nonsense"}"#
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        }
    }

    @Test("expands a leading tilde in configured paths") func tilde() {
        #expect(!Config.expand("~/x").hasPrefix("~"))
        #expect(Config.expand("/abs/x") == "/abs/x")
    }
}

@Suite("Cleanup models") struct CleanupModelsTests {
    @Test("defaults are the measured winners per script") func defaults() {
        let m = Config.default.cleanup.models
        #expect(m.latin == "qwen/qwen3.8-27b")
        #expect(m.arabic == "openai/gpt-oss-120b")
        #expect(m.model(for: .latin) == "qwen/qwen3.8-27b")
        #expect(m.model(for: .arabic) == "openai/gpt-oss-120b")
        let local = CleanupProviderFactory.defaultModels(for: .ollama)
        #expect(local.latin == "qwen2.5:1.5b")
        #expect(local.arabic == "qwen2.5:3b")
    }

    @Test("whisper now runs with automatic language detection") func autoLang() {
        #expect(Config.default.whispercpp.language == "auto")
        #expect(Config.default.whispercpp.model.contains("large-v3-turbo"))
    }

    @Test("a v1 config carrying cleanup.model still loads") func migratesOldKey() throws {
        let json = #"{"cleanup":{"provider":"ollama","model":"qwen2.5:1.5b"}}"#
        let c = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        #expect(c.cleanup.models.latin == "qwen2.5:1.5b")
        #expect(c.cleanup.models.arabic == "qwen2.5:3b")
    }

    @Test("an explicit models block wins over the legacy key") func explicitWins() throws {
        let json = #"{"cleanup":{"model":"old","models":{"latin":"a","arabic":"b"}}}"#
        let c = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        #expect(c.cleanup.models.latin == "a")
        #expect(c.cleanup.models.arabic == "b")
    }

    @Test("saving drops the legacy key") func saveDropsLegacy() throws {
        let json = #"{"cleanup":{"model":"qwen2.5:1.5b"}}"#
        let c = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("rawi-\(UUID().uuidString).json")
        try c.save(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        // Scoped to the cleanup object: whispercpp legitimately has its own `model` key.
        let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        let cleanup = raw["cleanup"] as! [String: Any]
        #expect(cleanup["model"] == nil, "legacy key survived a save")
        #expect(cleanup["models"] != nil)
    }
}
