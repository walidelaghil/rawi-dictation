import Testing
import AppKit
import Foundation
@testable import RawiCore

@Suite("Appearance") struct AppearanceTests {
    @Test("system follows whatever the OS is doing") func system() {
        #expect(Appearance.system.resolved(systemIsDark: true) == .dark)
        #expect(Appearance.system.resolved(systemIsDark: false) == .light)
    }

    @Test("an explicit choice overrides the OS in both directions") func explicit() {
        #expect(Appearance.dark.resolved(systemIsDark: false) == .dark)
        #expect(Appearance.light.resolved(systemIsDark: true) == .light)
    }

    @Test("system maps to no NSAppearance, meaning inherit") func nsName() {
        #expect(Appearance.system.nsAppearanceName == nil)
        #expect(Appearance.dark.nsAppearanceName == .darkAqua)
        #expect(Appearance.light.nsAppearanceName == .aqua)
    }

    @Test("every case is user-presentable") func names() {
        for a in Appearance.allCases { #expect(!a.displayName.isEmpty) }
    }

    @Test("config defaults to following the system") func configDefault() {
        #expect(Config.default.appearance == .system)
    }

    @Test("a config predating the key still loads") func backCompat() throws {
        let c = try JSONDecoder().decode(Config.self, from: Data(#"{"hotkey":"fn"}"#.utf8))
        #expect(c.appearance == .system)
    }

    @Test("an explicit appearance round-trips") func roundTrip() throws {
        let c = try JSONDecoder().decode(Config.self, from: Data(#"{"appearance":"light"}"#.utf8))
        #expect(c.appearance == .light)
    }
}
