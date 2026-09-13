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
        // Dictate shows the key that is bound, which on a Mac without Input
        // Monitoring is the fallback rather than the bare modifier requested.
        #expect(model.value(for: .dictate)
                == Config.default.effectiveDictateHotkey(inputMonitoringGranted: false))
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

    @Test("an armed capture gives up eventually, and says it did") func timesOut() async throws {
        // A backstop so the hotkeys cannot stay released forever, but long enough
        // that clicking the field and looking down at the keyboard is not a race.
        // Eight seconds was: the capture ended, the keypress reached the hotkey it
        // was meant to replace, and started a dictation.
        let model = scratchSettings()
        var events: [Bool] = []
        model.onCapture = { events.append($0) }
        model.beginCapture(.cancel)
        #expect(model.recording != nil)
        try await Task.sleep(for: .seconds(2))
        #expect(model.recording != nil)           // still waiting for you
        #expect(!model.captureExpired)
        model.endCapture()
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
        for id in [first.ids.dictate, first.ids.cancel, first.ids.transform] {
            #expect(!second.owns(id: id))
        }
        #expect(first.owns(id: first.ids.dictate))
        #expect(!first.handle(id: 999, kind: 0))
    }

    @Test("a claimed press runs its action and says it was handled") func handled() {
        var pressed = false
        let monitor = CarbonHotkeyMonitor(keyCode: 49, modifiers: [.maskAlternate],
                                          onPress: { pressed = true })
        #expect(monitor.handle(id: monitor.ids.dictate, kind: UInt32(kEventHotKeyPressed)))
        #expect(pressed)
    }
}

@MainActor
@Suite("Assigning a shortcut") struct ShortcutAssignmentTests {
    func model() -> SettingsViewModel {
        let m = scratchSettings()
        m.config.hotkey = "option+space"
        m.config.transformHotkey = "ctrl+option+space"
        m.config.cancelHotkey = "ctrl+option+escape"
        return m
    }

    @Test("a free combination is simply taken") func free() {
        let m = model()
        #expect(m.assign("shift+cmd+d", to: .transform) == .saved)
        #expect(m.config.transformHotkey == "shift+cmd+d")
    }

    @Test("a combination another key owns is refused, and says which") func refused() {
        // Saving it and reporting the clash afterwards is what produced a config
        // where dictation and transform were the same key and one silently lost.
        let m = model()
        #expect(m.assign("option+space", to: .transform) == .clashes(with: .dictate))
        #expect(m.config.transformHotkey == "ctrl+option+space")   // unchanged
        #expect(m.clashing.isEmpty)
    }

    @Test("pressing the key a shortcut already has is not a clash") func same() {
        let m = model()
        #expect(m.assign("option+space", to: .dictate) == .saved)
    }

    @Test("a swap gives each key the other's combination") func swap() {
        let m = model()
        #expect(m.assign("option+space", to: .transform) == .clashes(with: .dictate))
        m.swapPending()
        #expect(m.config.transformHotkey == "option+space")
        #expect(m.config.hotkey == "ctrl+option+space")
        #expect(m.clashing.isEmpty)
    }

    @Test("a swap the other way round works the same") func swapBack() {
        let m = model()
        #expect(m.assign("ctrl+option+space", to: .dictate) == .clashes(with: .transform))
        m.swapPending()
        #expect(m.config.hotkey == "ctrl+option+space")
        #expect(m.config.transformHotkey == "option+space")
    }

    @Test("dismissing a clash changes nothing") func dismiss() {
        let m = model()
        _ = m.assign("option+space", to: .transform)
        m.dismissPending()
        #expect(m.pendingClash == nil)
        #expect(m.config.transformHotkey == "ctrl+option+space")
    }

    @Test("a bare modifier is refused for a key Carbon has to bind") func needsModifier() {
        let m = model()
        #expect(m.assign("space", to: .transform) == .unusable)
        #expect(m.config.transformHotkey == "ctrl+option+space")
    }

    @Test("a config that already clashes can be repaired from the screen") func repair() {
        // The state this replaces: both keys on ⌥Space, and no way to fix
        // transform because every attempt was rejected as a clash with itself.
        let m = model()
        m.config.transformHotkey = "option+space"
        #expect(m.clashes(.transform))
        #expect(m.assign("ctrl+shift+t", to: .transform) == .saved)
        #expect(m.clashing.isEmpty)
    }
}
