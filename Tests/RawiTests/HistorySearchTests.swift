import Testing
import Foundation
@testable import RawiCore

@Suite("HistorySearch") struct HistorySearchTests {
    func e(_ cleaned: String, _ raw: String, script: Script = .latin,
           bundle: String = "com.slack", app: String = "Slack") -> HistoryEntry {
        HistoryEntry(at: Date(), cleaned: cleaned, raw: raw, script: script,
                     appName: app, bundleID: bundle, durationSeconds: 1,
                     peakLevel: 0.3, guardRejected: false)
    }
    var corpus: [HistoryEntry] {
        [e("Ship the release on Friday.", "um ship the release on friday basically"),
         e("يعني لازم نأجل الاجتماع", "يعني لازم نأجل الاجتماع", script: .arabic),
         e("The deploy failed again.", "the deploy failed again",
           bundle: "com.apple.dt.Xcode", app: "Xcode")]
    }

    @Test("an empty query returns everything") func empty() {
        #expect(HistorySearch.apply(HistoryFilter(), to: corpus).count == 3)
    }

    @Test("matches the cleaned text") func cleaned() {
        #expect(HistorySearch.apply(HistoryFilter(query: "release"), to: corpus).count == 1)
    }

    @Test("matches a filler word that cleanup removed") func rawOnly() {
        // You remember what you said, not what came out.
        let hits = HistorySearch.apply(HistoryFilter(query: "basically"), to: corpus)
        #expect(hits.count == 1)
        #expect(HistorySearch.matchedRawOnly("basically", hits[0]))
    }

    @Test("a match in both is not flagged as raw-only") func bothMatch() {
        let hits = HistorySearch.apply(HistoryFilter(query: "release"), to: corpus)
        #expect(!HistorySearch.matchedRawOnly("release", hits[0]))
    }

    @Test("is case-insensitive") func caseInsensitive() {
        #expect(HistorySearch.apply(HistoryFilter(query: "SHIP"), to: corpus).count == 1)
    }

    @Test("finds Arabic") func arabic() {
        #expect(HistorySearch.apply(HistoryFilter(query: "الاجتماع"), to: corpus).count == 1)
    }

    @Test("filters by script") func script() {
        #expect(HistorySearch.apply(HistoryFilter(script: .arabic), to: corpus).count == 1)
        #expect(HistorySearch.apply(HistoryFilter(script: .latin), to: corpus).count == 2)
    }

    @Test("filters by app") func app() {
        #expect(HistorySearch.apply(HistoryFilter(bundleID: "com.apple.dt.Xcode"),
                                    to: corpus).count == 1)
    }

    @Test("query and filter compose") func compose() {
        #expect(HistorySearch.apply(HistoryFilter(query: "deploy", bundleID: "com.slack"),
                                    to: corpus).isEmpty)
    }

    @Test("whitespace-only is treated as empty") func whitespace() {
        #expect(HistorySearch.apply(HistoryFilter(query: "   "), to: corpus).count == 3)
    }

    @Test("no match is an empty result, not everything") func noMatch() {
        #expect(HistorySearch.apply(HistoryFilter(query: "zzzz"), to: corpus).isEmpty)
    }

    @Test("the app list is deduplicated and named") func apps() {
        let apps = HistorySearch.apps(in: corpus)
        #expect(apps.count == 2)
        #expect(apps.map(\.name) == ["Slack", "Xcode"])
    }
}
