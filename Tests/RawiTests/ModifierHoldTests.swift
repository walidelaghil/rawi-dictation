import Testing
@testable import RawiCore

@Suite("Holding ⌥ versus using it") struct ModifierHoldTests {
    @Test("held alone past the delay, it is a dictation key") func hold() {
        var h = ModifierHold()
        #expect(h.modifierDown(othersHeld: false) == .armLater)
        #expect(h.armFired() == .press)
        #expect(h.modifierUp() == .release)
    }

    @Test("⌥← before the delay never reaches the microphone") func quickShortcut() {
        var h = ModifierHold()
        _ = h.modifierDown(othersHeld: false)
        #expect(h.keyDown() == .none)
        #expect(h.armFired() == .none)          // the delay lands after the chord
        #expect(h.modifierUp() == .none)
    }

    @Test("a shortcut after the delay takes its recording back") func slowShortcut() {
        var h = ModifierHold()
        _ = h.modifierDown(othersHeld: false)
        #expect(h.armFired() == .press)
        #expect(h.keyDown() == .abandon)
        #expect(h.keyDown() == .none)            // ⌥← ← ← abandons once
        #expect(h.modifierUp() == .none)         // and the release is not a stop
    }

    @Test("another modifier joining makes it a shortcut") func otherModifier() {
        var h = ModifierHold()
        _ = h.modifierDown(othersHeld: false)
        #expect(h.othersChanged(othersHeld: true) == .none)   // ⌥ then ⌘: ⌥⌘Space
        #expect(h.armFired() == .none)
        #expect(h.modifierUp() == .none)
    }

    @Test("pressed while another modifier is already down, it never arms") func alreadyChorded() {
        var h = ModifierHold()
        #expect(h.modifierDown(othersHeld: true) == .none)
        #expect(h.armFired() == .none)
        #expect(h.modifierUp() == .none)
    }

    @Test("a quick tap alone is still a tap, so double tap still starts hands-free") func tap() {
        var h = ModifierHold()
        _ = h.modifierDown(othersHeld: false)
        #expect(h.modifierUp() == .pressAndRelease)
        _ = h.modifierDown(othersHeld: false)
        #expect(h.modifierUp() == .pressAndRelease)
    }

    @Test("each press starts fresh after a shortcut") func freshAfterChord() {
        var h = ModifierHold()
        _ = h.modifierDown(othersHeld: false)
        _ = h.keyDown()
        _ = h.modifierUp()
        #expect(h.modifierDown(othersHeld: false) == .armLater)
        #expect(h.armFired() == .press)
    }
}
