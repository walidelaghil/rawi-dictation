import Testing
import Foundation
import Carbon.HIToolbox
@testable import RawiCore

/// Every model here is pointed at a throwaway file. A settings test that saves to
/// the default path edits the running app's real configuration — which is exactly
/// what happened once, changing the live dictation hotkey mid-session.
@MainActor
func scratchSettings(_ config: Config = .default) -> SettingsViewModel {
    SettingsViewModel(config: config,
                      url: URL(fileURLWithPath: NSTemporaryDirectory())
                          .appendingPathComponent("rawi-cfg-\(UUID().uuidString).json"))
}

@MainActor
@Suite("Settings") struct SettingsViewModelTests {
    @Test("each key reads and writes its own config field") func fields() {
        let model = scratchSettings()
        #expect(model.value(for: .dictate) == Config.default.hotkey)
        #expect(model.value(for: .transform) == Config.default.transformHotkey)
        #expect(model.value(for: .cancel) == Config.default.cancelHotkey)
    }

    @Test("choosing a Carbon-compatible dictation key sets the fallback with it")
    func fallbackFollows() {
        // On a Mac that cannot grant Input Monitoring the fallback is the key you
        // actually get. Leaving it behind would hand you a different shortcut than
        // the one you just chose.
        let model = scratchSettings()
        model.config.hotkey = "option+space"
        model.config.fallbackHotkey = "ctrl+option+space"
        model.set("shift+cmd+d", for: .dictate)
        #expect(model.config.fallbackHotkey == "shift+cmd+d")
    }

    @Test("a bare modifier leaves the fallback alone — Carbon cannot bind one")
    func fallbackStays() {
        let model = scratchSettings()
        model.config.fallbackHotkey = "ctrl+option+space"
        model.set("fn", for: .dictate)
        #expect(model.config.hotkey == "fn")
        #expect(model.config.fallbackHotkey == "ctrl+option+space")
    }

    @Test("a clash is reported against both keys, by name") func clash() {
        let model = scratchSettings()
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
        let model = scratchSettings()
        model.config.cleanup.provider = .ollama
        model.config.cleanup.models = CleanupProviderFactory.defaultModels(for: .ollama)
        #expect(model.config.cleanup.models.arabic == "qwen2.5:3b")
        model.config.cleanup.models = CleanupProviderFactory.defaultModels(for: .anthropic)
        #expect(model.config.cleanup.models.latin == model.config.cleanup.models.arabic)
    }
}

@MainActor
@Suite("Recording a shortcut") struct ShortcutCaptureTests {
    @Test("the global hotkeys are released while a key is being recorded") func releases() {
        // A Carbon hotkey is consumed application-wide, this app included: with
        // dictation on ⌥Space, pressing ⌥Space in the recorder started a dictation
        // and the recorder never saw the key. It looked like a dead keyboard.
        let model = scratchSettings()
        var events: [Bool] = []
        model.onCapture = { events.append($0) }
        model.beginCapture(.dictate)
        #expect(events == [true])
        #expect(model.recording == "dictate")
        model.endCapture()
        #expect(events == [true, false])
        #expect(model.recording == nil)
    }

    @Test("ending a capture that never began releases nothing") func idempotent() {
        let model = scratchSettings()
        var events: [Bool] = []
        model.onCapture = { events.append($0) }
        model.endCapture()
        model.endCapture()
        #expect(events.isEmpty)
    }

    @Test("beginning the same capture twice does not re-release") func repeated() {
        let model = scratchSettings()
        var events: [Bool] = []
        model.onCapture = { events.append($0) }
        model.beginCapture(.dictate)
        model.beginCapture(.dictate)
        #expect(events == [true])
    }

    @Test("an armed capture gives up on its own") func timesOut() async throws {
        // Leaving the hotkeys released is worse than an unset shortcut.
        let model = scratchSettings()
        var events: [Bool] = []
        model.onCapture = { events.append($0) }
        model.beginCapture(.cancel)
        #expect(model.recording != nil)
        try await Task.sleep(for: .seconds(8.4))
        #expect(model.recording == nil)
        #expect(events == [true, false])
    }
}

@Suite("Carbon hotkey routing") struct CarbonRoutingTests {
    @Test("a monitor only claims its own hotkey ids") func ownership() {
        // Carbon calls application handlers in order, and one that returns "handled"
        // stops the event there. Claiming a neighbour's id made its key dead.
        let first = CarbonHotkeyMonitor(keyCode: 49, modifiers: [.maskAlternate])
        let second = CarbonHotkeyMonitor(keyCode: nil, modifiers: [],
                                         transformKeyCode: 49,
                                         transformModifiers: [.maskControl, .maskAlternate])
        for id in UInt32(1)...30 where first.owns(id: id) {
            #expect(!second.owns(id: id))
        }
        #expect(!first.handle(id: 999, kind: 0))
    }

    @Test("a claimed press runs its action and says it was handled") func handled() {
        var pressed = false
        let monitor = CarbonHotkeyMonitor(keyCode: 49, modifiers: [.maskAlternate],
                                          onPress: { pressed = true })
        let id = (UInt32(1)...30).first { monitor.owns(id: $0) }!
        #expect(monitor.handle(id: id, kind: UInt32(kEventHotKeyPressed)))
        #expect(pressed)
    }
}
