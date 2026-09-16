import Testing
import Foundation
@testable import RawiCore

@Suite("MenuActions") struct MenuActionsTests {
    let labels = HotkeyLabels(config: .default, inputMonitoringGranted: false)

    @Test("the shipped actions are dictate and transform only") func shipped() {
        // Commands is designed but deferred — see docs/BACKLOG.md.
        #expect(MenuActions.all(labels).map(\.id) == ["dictate", "transform"])
    }

    @Test("the shortcuts shown are the ones actually bound") func boundKeys() {
        // They were glyph literals, so rebinding a key changed the key and not the
        // label — and on a Mac without Input Monitoring the literal was wrong from
        // the first launch.
        var config = Config.default
        config.hotkey = "fn"
        config.fallbackHotkey = "shift+cmd+d"
        let bound = HotkeyLabels(config: config, inputMonitoringGranted: false)
        #expect(MenuActions.all(bound).first { $0.id == "dictate" }?.shortcut == "⇧⌘D")
    }

    @Test("every action names a title, a shortcut and a symbol") func complete() {
        for a in MenuActions.all(labels) {
            #expect(!a.title.isEmpty)
            #expect(!a.shortcut.isEmpty)
            #expect(!a.symbol.isEmpty)
        }
    }

    @Test("ids are unique") func unique() {
        #expect(Set(MenuActions.all(labels).map(\.id)).count == MenuActions.all(labels).count)
    }
}

@Suite("RecentDictation") struct RecentDictationTests {
    @Test("a multi-line transcript collapses to one line for the menu") func oneLine() {
        let r = RecentDictation(text: "first line\nsecond line", script: .latin)
        #expect(r.oneLine == "first line second line")
        #expect(!r.oneLine.contains("\n"))
    }

    @Test("the timestamp renders as a short clock time") func stamp() {
        var c = DateComponents(); c.year = 2026; c.month = 9; c.day = 11; c.hour = 14; c.minute = 5
        let date = Calendar.current.date(from: c)!
        #expect(RecentDictation(text: "x", script: .latin, at: date).timestamp == "14:05")
    }

    @Test("script travels with the entry so the menu can set it in the right face") func script() {
        #expect(RecentDictation(text: "مرحبا", script: .arabic).script == .arabic)
    }

    @Test("a rewrite is badged as one, not as a language you spoke") func transformBadge() {
        // Transforms were filtered out of the list entirely, so a rewrite you had
        // just watched land in your document was missing from the one place that
        // shows what Rawi has been doing — and from the only way to copy it back.
        let spoken = RecentDictation(text: "Ship it on Monday.", script: .latin)
        let rewritten = RecentDictation(text: "Ship Monday.", script: .latin,
                                        isTransform: true)
        #expect(spoken.badge == "EN")
        #expect(rewritten.badge == "TR")
        #expect(RecentDictation(text: "مرحبا", script: .arabic).badge == "AR")
        // Arabic that came out of a transform is still a transform.
        #expect(RecentDictation(text: "مرحبا", script: .arabic,
                                isTransform: true).badge == "TR")
    }
}
