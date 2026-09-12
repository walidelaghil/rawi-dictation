import AppKit

/// Standard editing shortcuts for an app with no menu bar of its own.
///
/// Rawi is an accessory app (`LSUIElement`), so it never shows a menu bar — and
/// without a main menu, ⌘A, ⌘C, ⌘V, ⌘X and ⌘Z do nothing in its own windows,
/// because AppKit routes those key equivalents through the main menu rather than
/// through the text field. The result was a search box you had to clear one
/// backspace at a time.
///
/// The menu is never displayed. It exists only so the key equivalents resolve.
public enum EditMenu {
    public static func install(appName: String = "Rawi", viewTarget: AnyObject? = nil,
                               screenAction: Selector? = nil, findAction: Selector? = nil) {
        guard NSApp.mainMenu == nil else { return }
        NSApp.mainMenu = make(appName: appName, viewTarget: viewTarget,
                              screenAction: screenAction, findAction: findAction)
    }

    public static func make(appName: String = "Rawi", viewTarget: AnyObject? = nil,
                            screenAction: Selector? = nil,
                            findAction: Selector? = nil) -> NSMenu {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Hide \(appName)",
                        action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit \(appName)",
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        // Undo and redo are not on a public selector, so they are named. A first
        // responder that does not implement them simply disables the item.
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(redo)
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Delete", action: #selector(NSText.delete(_:)), keyEquivalent: "")
        edit.addItem(withTitle: "Select All",
                     action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.addItem(.separator())
        let find = NSMenuItem(title: "Find", action: #selector(NSResponder.complete(_:)),
                              keyEquivalent: "f")
        find.isEnabled = false
        edit.addItem(find)
        editItem.submenu = edit
        main.addItem(editItem)

        // View: the screens, numbered in rail order. A Mac app that cannot be
        // driven from the keyboard feels generated however it looks.
        if let target = viewTarget {
            let viewItem = NSMenuItem()
            let view = NSMenu(title: "View")
            let find = NSMenuItem(title: "Find", action: findAction, keyEquivalent: "f")
            find.target = target
            view.addItem(find)
            view.addItem(.separator())
            for (index, screen) in Screen.allCases.enumerated() where index < 9 {
                let item = NSMenuItem(title: screen.rawValue, action: screenAction,
                                      keyEquivalent: "\(index + 1)")
                item.target = target
                item.representedObject = screen.rawValue
                view.addItem(item)
            }
            viewItem.submenu = view
            main.addItem(viewItem)
        }

        let windowItem = NSMenuItem()
        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close",
                       action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.addItem(withTitle: "Minimise",
                       action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = window
        main.addItem(windowItem)
        return main
    }
}
