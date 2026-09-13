import Testing
import Foundation
@testable import RawiCore

@Suite("The key that is actually bound") struct EffectiveHotkeyTests {
    func config(hotkey: String, fallback: String, backend: HotkeyBackendKind = .auto) -> Config {
        var c = Config.default
        c.hotkey = hotkey
        c.fallbackHotkey = fallback
        c.hotkeyBackend = backend
        return c
    }

    @Test("with Input Monitoring, the key you chose is the key you get") func eventTap() {
        let c = config(hotkey: "fn", fallback: "ctrl+option+space")
        #expect(c.effectiveDictateHotkey(inputMonitoringGranted: true) == "fn")
    }

    @Test("without it, a bare modifier falls back and the screen must say so") func carbon() {
        // Carbon cannot bind a bare modifier, so the fallback is what is really
        // listening. Showing "fn" on a Mac that cannot grant Input Monitoring is
        // showing a key that does nothing.
        let c = config(hotkey: "fn", fallback: "ctrl+option+space")
        #expect(c.effectiveDictateHotkey(inputMonitoringGranted: false) == "ctrl+option+space")
    }

    @Test("a combination binds directly on either backend") func combination() {
        let c = config(hotkey: "option+space", fallback: "ctrl+option+space")
        #expect(c.effectiveDictateHotkey(inputMonitoringGranted: false) == "option+space")
        #expect(c.effectiveDictateHotkey(inputMonitoringGranted: true) == "option+space")
    }

    @Test("an explicit backend choice is honoured over what is granted") func explicit() {
        let carbon = config(hotkey: "fn", fallback: "ctrl+option+space", backend: .carbon)
        #expect(carbon.effectiveDictateHotkey(inputMonitoringGranted: true) == "ctrl+option+space")
        let tap = config(hotkey: "fn", fallback: "ctrl+option+space", backend: .eventTap)
        #expect(tap.effectiveDictateHotkey(inputMonitoringGranted: false) == "fn")
    }

    @Test("the shipped defaults do not put two actions on one chord") func defaultsDoNotCollide() {
        // They did: fallbackHotkey and transformHotkey were both ctrl+option+space,
        // so on the one Mac this app was built for, a fresh install bound dictate
        // and transform to the same key and one of them silently lost.
        let d = Config.default
        let bound = d.effectiveDictateHotkey(inputMonitoringGranted: false)
        #expect(HotkeyConfig.parse(bound) != HotkeyConfig.parse(d.transformHotkey))
        #expect(HotkeyConfig.parse(bound) != HotkeyConfig.parse(d.cancelHotkey))
        #expect(HotkeyConfig.parse(d.transformHotkey) != HotkeyConfig.parse(d.cancelHotkey))
    }

    @Test("every shipped key is bindable without a permission this Mac cannot grant")
    func allCarbonCompatible() {
        let d = Config.default
        for raw in [d.fallbackHotkey, d.transformHotkey, d.cancelHotkey] {
            #expect(HotkeyConfig.isCarbonCompatible(raw), Comment(rawValue: raw))
        }
    }

    @Test("what the app shows is what the app bound") func labels() {
        let c = config(hotkey: "fn", fallback: "shift+cmd+d")
        let labels = HotkeyLabels(config: c, inputMonitoringGranted: false)
        #expect(labels.dictate == "⇧⌘D")
        #expect(labels.transform == HotkeyConfig.symbolic(c.transformHotkey))
        #expect(labels.cancel == HotkeyConfig.symbolic(c.cancelHotkey))
    }

    @Test("the labels follow a rebind rather than staying at the default") func rebind() {
        var c = config(hotkey: "option+space", fallback: "option+space")
        c.transformHotkey = "ctrl+shift+t"
        let labels = HotkeyLabels(config: c, inputMonitoringGranted: false)
        #expect(labels.dictate == "⌥Space")
        #expect(labels.transform == "⌃⇧T")
    }
}
