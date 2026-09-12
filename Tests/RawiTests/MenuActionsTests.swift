import Testing
import Foundation
@testable import RawiCore

@Suite("MenuActions") struct MenuActionsTests {
    @Test("the shipped actions are dictate and transform only") func shipped() {
        // Commands is designed but deferred — see docs/BACKLOG.md.
        #expect(MenuActions.all.map(\.id) == ["dictate", "transform"])
    }

    @Test("every action names a title, a shortcut and a symbol") func complete() {
        for a in MenuActions.all {
            #expect(!a.title.isEmpty)
            #expect(!a.shortcut.isEmpty)
            #expect(!a.symbol.isEmpty)
        }
    }

    @Test("ids are unique") func unique() {
        #expect(Set(MenuActions.all.map(\.id)).count == MenuActions.all.count)
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
}
