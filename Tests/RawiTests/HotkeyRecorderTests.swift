import Testing
import CoreGraphics
@testable import RawiCore

@Suite("Hotkey recording") struct HotkeyRecorderTests {
    @Test("a keypress becomes the string the config file uses") func record() {
        #expect(HotkeyConfig.string(keyCode: 49, modifiers: [.maskAlternate]) == "option+space")
        #expect(HotkeyConfig.string(keyCode: 49, modifiers: [.maskControl, .maskAlternate])
                == "ctrl+option+space")
        // Written in the order macOS displays modifiers, whatever order they were
        // pressed in. The parser does not care, but a config file people read does.
        #expect(HotkeyConfig.string(keyCode: 2, modifiers: [.maskCommand, .maskShift])
                == "shift+cmd+d")
    }

    @Test("what is recorded is what parses back") func roundTrip() {
        for (code, mods) in [(UInt16(49), CGEventFlags.maskAlternate),
                             (2, [.maskCommand, .maskShift]),
                             (122, .maskControl)] {
            let raw = HotkeyConfig.string(keyCode: code, modifiers: mods)
            #expect(raw != nil)
            #expect(HotkeyConfig.parse(raw!) == .keyCode(code, modifiers: mods))
        }
    }

    @Test("a bare key with no modifier is refused") func needsModifier() {
        // It would swallow the letter A everywhere.
        #expect(HotkeyConfig.string(keyCode: 0, modifiers: []) == nil)
        #expect(HotkeyConfig.string(keyCode: 49, modifiers: []) == nil)
    }

    @Test("modifier-only and unknown keys record nothing") func ignored() {
        #expect(HotkeyConfig.string(keyCode: 55, modifiers: [.maskCommand]) == nil)   // ⌘ itself
        #expect(HotkeyConfig.string(keyCode: 999, modifiers: [.maskCommand]) == nil)
    }

    @Test("caps lock and the numeric keypad flag are not part of a shortcut") func noise() {
        #expect(HotkeyConfig.string(keyCode: 49,
                                    modifiers: [.maskAlternate, .maskAlphaShift,
                                                .maskNumericPad]) == "option+space")
    }

    @Test("shortcuts render the way macOS writes them") func symbols() {
        #expect(HotkeyConfig.symbolic("ctrl+option+space") == "⌃⌥Space")
        #expect(HotkeyConfig.symbolic("option+space") == "⌥Space")
        #expect(HotkeyConfig.symbolic("cmd+shift+d") == "⇧⌘D")
        #expect(HotkeyConfig.symbolic("ctrl+option+escape") == "⌃⌥esc")
        #expect(HotkeyConfig.symbolic("fn") == "fn")
        // Modifiers always in the order the Mac shows them, whatever order they
        // were typed in the config.
        #expect(HotkeyConfig.symbolic("shift+cmd+d") == "⇧⌘D")
    }

    @Test("an unparseable string renders as itself rather than vanishing") func passthrough() {
        #expect(HotkeyConfig.symbolic("nonsense+zz") == "nonsense+zz")
    }

    @Test("two keys on the same combination are reported as the clash they are")
    func clashes() {
        let clashing = HotkeyConfig.clashes(in: [("Dictate", "option+space"),
                                                 ("Transform", "option+space"),
                                                 ("Cancel", "ctrl+option+escape")])
        #expect(clashing == ["Dictate", "Transform"])
    }

    @Test("different spellings of the same chord still clash") func spelling() {
        // "opt+space" and "option+space" are one key, and the second registration
        // would silently lose.
        #expect(HotkeyConfig.clashes(in: [("A", "opt+space"), ("B", "option+space")])
                == ["A", "B"])
    }

    @Test("no clash reports nothing") func clean() {
        #expect(HotkeyConfig.clashes(in: [("A", "option+space"),
                                          ("B", "ctrl+option+space")]).isEmpty)
    }
}
