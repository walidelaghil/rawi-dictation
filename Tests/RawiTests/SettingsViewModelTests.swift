import Testing
import Foundation
@testable import RawiCore

@MainActor
@Suite("Settings") struct SettingsViewModelTests {
    @Test("each key reads and writes its own config field") func fields() {
        let model = SettingsViewModel(config: .default)
        #expect(model.value(for: .dictate) == Config.default.hotkey)
        #expect(model.value(for: .transform) == Config.default.transformHotkey)
        #expect(model.value(for: .cancel) == Config.default.cancelHotkey)
    }

    @Test("choosing a Carbon-compatible dictation key sets the fallback with it")
    func fallbackFollows() {
        // On a Mac that cannot grant Input Monitoring the fallback is the key you
        // actually get. Leaving it behind would hand you a different shortcut than
        // the one you just chose.
        let model = SettingsViewModel(config: .default)
        model.config.hotkey = "option+space"
        model.config.fallbackHotkey = "ctrl+option+space"
        model.set("shift+cmd+d", for: .dictate)
        #expect(model.config.fallbackHotkey == "shift+cmd+d")
    }

    @Test("a bare modifier leaves the fallback alone — Carbon cannot bind one")
    func fallbackStays() {
        let model = SettingsViewModel(config: .default)
        model.config.fallbackHotkey = "ctrl+option+space"
        model.set("fn", for: .dictate)
        #expect(model.config.hotkey == "fn")
        #expect(model.config.fallbackHotkey == "ctrl+option+space")
    }

    @Test("a clash is reported against both keys, by name") func clash() {
        let model = SettingsViewModel(config: .default)
        model.config.hotkey = "ctrl+option+space"
        model.config.transformHotkey = "ctrl+option+space"
        #expect(model.clashes(.dictate))
        #expect(model.clashes(.transform))
        #expect(!model.clashes(.cancel))
    }

    @Test("saving writes the file the running app watches") func save() throws {
        // The settings screen has no private channel to the app: it writes
        // config.json, exactly as a hand edit would, and the watcher does the rest.
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("rawi-settings-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        var config = Config.default
        config.transformHotkey = "ctrl+shift+t"
        config.appearance = .light
        try config.save(to: url)
        let loaded = try Config.load(from: url)
        #expect(loaded.transformHotkey == "ctrl+shift+t")
        #expect(loaded.appearance == .light)
    }

    @Test("switching provider takes that provider's tuned models with it") func providerSwitch() {
        let model = SettingsViewModel(config: .default)
        model.config.cleanup.provider = .ollama
        model.config.cleanup.models = CleanupProviderFactory.defaultModels(for: .ollama)
        #expect(model.config.cleanup.models.arabic == "qwen2.5:3b")
        model.config.cleanup.models = CleanupProviderFactory.defaultModels(for: .anthropic)
        #expect(model.config.cleanup.models.latin == model.config.cleanup.models.arabic)
    }
}
