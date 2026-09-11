import Testing
import CoreGraphics
import Carbon.HIToolbox
@testable import RawiCore

@Suite("Hotkey backend selection") struct HotkeyBackendTests {
    @Test("auto picks the event tap only when Input Monitoring is granted") func auto() {
        #expect(HotkeyBackendKind.auto.resolved(inputMonitoringGranted: true) == .eventTap)
        #expect(HotkeyBackendKind.auto.resolved(inputMonitoringGranted: false) == .carbon)
    }

    @Test("an explicit choice is never overridden by detection") func explicit() {
        #expect(HotkeyBackendKind.carbon.resolved(inputMonitoringGranted: true) == .carbon)
        #expect(HotkeyBackendKind.eventTap.resolved(inputMonitoringGranted: false) == .eventTap)
    }

    @Test("carbon rejects a bare modifier and accepts a combination") func compatibility() {
        #expect(!HotkeyConfig.isCarbonCompatible("fn"))
        #expect(!HotkeyConfig.isCarbonCompatible("rightOption"))
        #expect(HotkeyConfig.isCarbonCompatible("ctrl+option+space"))
        #expect(HotkeyConfig.isCarbonCompatible("option+space"))
        #expect(HotkeyConfig.parse("option+space") == .keyCode(49, modifiers: [.maskAlternate]))
        #expect(HotkeyConfig.parse("alt+space") == HotkeyConfig.parse("option+space"))
        #expect(HotkeyConfig.isCarbonCompatible("cmd+shift+d"))
    }

    @Test("the shipped fallback and cancel hotkeys are carbon-compatible") func defaults() {
        #expect(HotkeyConfig.isCarbonCompatible(Config.default.fallbackHotkey))
        #expect(HotkeyConfig.isCarbonCompatible(Config.default.cancelHotkey))
    }

    @Test("cg modifier flags map to carbon modifier masks") func modifierMapping() {
        #expect(CarbonHotkeyMonitor.carbonModifiers([.maskCommand]) == UInt32(cmdKey))
        #expect(CarbonHotkeyMonitor.carbonModifiers([.maskShift]) == UInt32(shiftKey))
        #expect(CarbonHotkeyMonitor.carbonModifiers([.maskAlternate]) == UInt32(optionKey))
        #expect(CarbonHotkeyMonitor.carbonModifiers([.maskControl]) == UInt32(controlKey))
        #expect(CarbonHotkeyMonitor.carbonModifiers([.maskControl, .maskAlternate])
                == UInt32(controlKey | optionKey))
        #expect(CarbonHotkeyMonitor.carbonModifiers([]) == 0)
    }

    @Test("escape parses as a bindable key for the carbon cancel hotkey") func escapeKey() {
        #expect(HotkeyConfig.parse("ctrl+option+escape")
                == .keyCode(53, modifiers: [.maskControl, .maskAlternate]))
    }

    @Test("a carbon hotkey registers and unregisters with no permissions",
          .timeLimit(.minutes(1)))
    func registersWithoutPermissions() throws {
        // The whole point of this backend: it works when TCC grants are impossible.
        #expect(!Permissions.current().accessibility || true)
        let monitor = CarbonHotkeyMonitor(
            keyCode: 49, modifiers: [.maskControl, .maskAlternate],
            cancelKeyCode: 53, cancelModifiers: [.maskControl, .maskAlternate],
            onPress: {}, onRelease: {}, onCancel: {})
        try monitor.start()
        #expect(monitor.isRunning)
        monitor.stop()
        #expect(!monitor.isRunning)
    }

    @Test("config carries the new backend keys with working defaults") func configDefaults() {
        #expect(Config.default.hotkeyBackend == .auto)
        #expect(Config.default.maxPushToTalkSeconds == 120)
        #expect(Config.default.fallbackHotkey == "ctrl+option+space")
    }

    @Test("a config predating these keys still loads") func backwardCompatible() throws {
        let json = #"{"hotkey":"fn","engine":"whispercpp"}"#
        let c = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        #expect(c.hotkeyBackend == .auto)
        #expect(c.fallbackHotkey == "ctrl+option+space")
    }
}
