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
        #expect(c.engine == .whispercpp)
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
