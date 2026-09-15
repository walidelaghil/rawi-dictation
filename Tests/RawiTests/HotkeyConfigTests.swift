import Testing
import CoreGraphics
@testable import RawiCore

@Suite("HotkeyConfig") struct HotkeyConfigTests {
    @Test("parses fn") func fn() {
        #expect(HotkeyConfig.parse("fn") == .modifierFlag(.maskSecondaryFn))
    }

    @Test("parses right option, case and spacing insensitive") func rightOption() {
        #expect(HotkeyConfig.parse("rightOption") == .modifierFlag(.maskAlternate))
        #expect(HotkeyConfig.parse("  RIGHT OPTION ") == .modifierFlag(.maskAlternate))
    }

    @Test("parses a modifier plus letter combination") func combo() {
        #expect(HotkeyConfig.parse("cmd+shift+d")
                == .keyCode(2, modifiers: [.maskCommand, .maskShift]))
    }

    @Test("parses a function key and space") func specialKeys() {
        #expect(HotkeyConfig.parse("ctrl+space") == .keyCode(49, modifiers: [.maskControl]))
        #expect(HotkeyConfig.parse("cmd+f5") == .keyCode(96, modifiers: [.maskCommand]))
    }

    @Test("rejects nonsense") func invalid() {
        #expect(HotkeyConfig.parse("") == nil)
        #expect(HotkeyConfig.parse("   ") == nil)
        #expect(HotkeyConfig.parse("banana+z9") == nil)
        #expect(HotkeyConfig.parse("shift") == nil)      // held for every capital letter
        #expect(HotkeyConfig.parse("shift+") == nil)
        #expect(HotkeyConfig.parse("d") == nil)          // bare letter needs a modifier
    }

    @Test("escape keycode is 53") func escape() {
        #expect(HotkeyConfig.escapeKeyCode == 53)
    }

    @Test("the shipped default hotkey parses") func defaultParses() {
        #expect(HotkeyConfig.parse(Config.default.hotkey) != nil)
    }
}
