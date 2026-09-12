import Testing
import AppKit
@testable import RawiCore

@MainActor
@Suite("Edit menu") struct EditMenuTests {
    func item(_ menu: NSMenu, _ title: String) -> NSMenuItem? {
        menu.items.compactMap(\.submenu).flatMap(\.items).first { $0.title == title }
    }

    @Test("the shortcuts an accessory app otherwise has no way to receive") func shortcuts() {
        // Without a main menu, ⌘A and ⌘C do nothing in this app's own windows:
        // AppKit resolves key equivalents through the menu, not the text field.
        // The search box had to be cleared one backspace at a time.
        let menu = EditMenu.make()
        for (title, key) in [("Select All", "a"), ("Copy", "c"),
                             ("Paste", "v"), ("Cut", "x"), ("Undo", "z")] {
            let found = item(menu, title)
            #expect(found != nil, Comment(rawValue: "no \(title) item"))
            #expect(found?.keyEquivalent == key)
            #expect(found?.keyEquivalentModifierMask == .command)
        }
    }

    @Test("redo is shift-command-z, not its own key") func redo() {
        let redo = item(EditMenu.make(), "Redo")
        #expect(redo?.keyEquivalent == "z")
        #expect(redo?.keyEquivalentModifierMask == [.command, .shift])
    }

    @Test("the editing items have no target, so they reach the first responder")
    func responderChain() {
        // A target would send them to that object instead of to whatever text field
        // has focus — which is the entire point of these items.
        for title in ["Select All", "Copy", "Paste", "Cut"] {
            #expect(item(EditMenu.make(), title)?.target == nil)
        }
    }
}
