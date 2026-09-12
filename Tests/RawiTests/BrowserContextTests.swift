import Testing
import Foundation
@testable import RawiCore

@Suite("BrowserContext") struct BrowserContextTests {
    @Test("a non-browser never runs a script") func nonBrowser() {
        // Dictating in Terminal must not pay for an AppleScript round trip.
        #expect(BrowserContext.activeURL(bundleID: "com.apple.Terminal") == nil)
        #expect(BrowserContext.activeURL(bundleID: nil) == nil)
        #expect(BrowserContext.activeURL(bundleID: "com.unknown.App") == nil)
    }

    @Test("the browsers actually in use are covered") func coverage() {
        // Brave first: it is the browser in use here.
        #expect(BrowserContext.scriptable["com.brave.Browser"] == "Brave Browser")
        for id in ["com.google.Chrome", "com.apple.Safari",
                   "company.thebrowser.Browser", "com.microsoft.edgemac"] {
            #expect(BrowserContext.scriptable[id] != nil, "\(id) not scriptable")
        }
    }

    @Test("every scriptable browser is also in the destination browser list") func consistent() {
        // Otherwise a rule could name a browser whose URL can never be read.
        for id in Browsers.bundleIDs {
            #expect(BrowserContext.scriptable[id] != nil,
                    "\(id) is in Browsers.bundleIDs but is not scriptable")
        }
    }

    @Test("a running browser answers, or returns nil without hanging",
          .timeLimit(.minutes(1)))
    func liveOrNil() {
        // Not asserting a URL: whether a window is open is not this test's business.
        // What must hold is that it returns promptly either way.
        let started = Date()
        _ = BrowserContext.activeURL(bundleID: "com.brave.Browser", timeout: 0.5)
        #expect(Date().timeIntervalSince(started) < 2.0, "a slow browser must not stall dictation")
    }
}
