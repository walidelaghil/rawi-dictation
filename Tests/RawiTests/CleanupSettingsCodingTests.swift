import Foundation
import Testing
@testable import RawiCore

@Suite("Cleanup settings survive a save") struct CleanupSettingsCodingTests {
    private func roundTrip(_ settings: CleanupSettings) throws -> CleanupSettings {
        try JSONDecoder().decode(CleanupSettings.self,
                                 from: JSONEncoder().encode(settings))
    }

    @Test("the transform model is written back, not dropped") func transformModel() throws {
        // A save that forgot this key silently moved transforms back onto the model
        // that answered Arabic requests in Chinese.
        var settings = Config.defaultCleanup
        settings.transformModel = "gemma3:4b"
        #expect(try roundTrip(settings).transformModel == "gemma3:4b")
    }

    @Test("the mode and the polish model are read and written") func polish() throws {
        var settings = Config.defaultCleanup
        settings.mode = .clean
        settings.polishModel = "qwen2.5:1.5b"
        let back = try roundTrip(settings)
        #expect(back.mode == .clean)
        #expect(back.polishModel == "qwen2.5:1.5b")
    }

    @Test("a config written by hand is honoured") func handWritten() throws {
        let json = #"{"provider":"ollama","mode":"clean","polishModel":"x","transformModel":"y"}"#
        let settings = try JSONDecoder().decode(CleanupSettings.self, from: Data(json.utf8))
        #expect(settings.mode == .clean)
        #expect(settings.polishModel == "x")
        #expect(settings.transformModel == "y")
    }

    @Test("an older config without the new keys gets the defaults") func older() throws {
        let settings = try JSONDecoder().decode(CleanupSettings.self,
                                                from: Data(#"{"provider":"ollama"}"#.utf8))
        #expect(settings.mode == .polish)
        #expect(settings.polishModel == "")
        #expect(settings.transformModel == "")
    }

    @Test("an unknown mode falls back rather than failing the whole config") func unknownMode() throws {
        let settings = try JSONDecoder().decode(
            CleanupSettings.self, from: Data(#"{"provider":"ollama","mode":"shiny"}"#.utf8))
        #expect(settings.mode == .polish)
    }
}
