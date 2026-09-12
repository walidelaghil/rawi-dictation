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

@MainActor
@Suite("View menu") struct ViewMenuTests {
    final class Target: NSObject {
        @objc func screen(_ sender: NSMenuItem) {}
        @objc func find() {}
    }

    /// NSMenuItem holds its target weakly, so the test has to keep it alive. In
    /// the app the target is the app delegate, which outlives everything.
    func viewMenu(_ target: Target) -> NSMenu? {
        EditMenu.make(viewTarget: target,
                             screenAction: #selector(Target.screen(_:)),
                             findAction: #selector(Target.find))
            .items.compactMap(\.submenu).first { $0.title == "View" }
    }

    @Test("every screen in the rail has a number key") func screens() throws {
        let target = Target()
        let menu = try #require(viewMenu(target))
        for (index, screen) in Screen.allCases.enumerated() {
            let item = menu.items.first { $0.title == screen.rawValue }
            #expect(item?.keyEquivalent == "\(index + 1)")
            #expect(item?.keyEquivalentModifierMask == .command)
            #expect(item?.representedObject as? String == screen.rawValue)
        }
    }

    @Test("find is ⌘F and reaches the app, not the first responder") func find() throws {
        let target = Target()
        let item = try #require(viewMenu(target)?.items.first { $0.title == "Find" })
        #expect(item.target === target)
        #expect(item.keyEquivalent == "f")
        #expect(item.target != nil)
    }

    @Test("without a target there is no View menu rather than a dead one") func noTarget() {
        let menu = EditMenu.make().items.compactMap(\.submenu).first { $0.title == "View" }
        #expect(menu == nil)
    }
}
