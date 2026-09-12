import Testing
import Foundation
@testable import RawiCore

@Suite("TermSuggester") struct TermSuggesterTests {
    func entry(_ raw: String) -> HistoryEntry {
        HistoryEntry(at: Date(), cleaned: raw, raw: raw, script: .latin,
                     appName: "Slack", bundleID: "x", durationSeconds: 1,
                     peakLevel: 0.3, guardRejected: false)
    }

    @Test("a word recurring enough is suggested") func recurrence() {
        let entries = (0..<3).map { _ in entry("ping Kanji about the rollout") }
        let s = TermSuggester.suggestions(from: entries, known: [])
        #expect(s.contains { $0.token == "kanji" })
        #expect(s.first { $0.token == "kanji" }?.occurrences == 3)
    }

    @Test("a word below the threshold is not suggested") func belowThreshold() {
        let entries = (0..<2).map { _ in entry("ping Kanji about it") }
        #expect(!TermSuggester.suggestions(from: entries, known: []).contains { $0.token == "kanji" })
    }

    @Test("common words are never suggested") func stopwords() {
        let entries = (0..<9).map { _ in entry("this that there they would should because") }
        #expect(TermSuggester.suggestions(from: entries, known: []).isEmpty)
    }

    @Test("a term already in the dictionary is not suggested again") func known() {
        let entries = (0..<5).map { _ in entry("ping Kanji again") }
        let s = TermSuggester.suggestions(from: entries,
                                          known: [DictionaryTerm(term: "Kanji")])
        #expect(!s.contains { $0.token == "kanji" })
    }

    @Test("suggestions are case-insensitively deduplicated") func dedupe() {
        let entries = [entry("Kanji here"), entry("kanji there"), entry("KANJI everywhere")]
        let s = TermSuggester.suggestions(from: entries, known: [])
        #expect(s.filter { $0.token == "kanji" }.count == 1)
        #expect(s.first { $0.token == "kanji" }?.occurrences == 3)
    }

    @Test("short words are ignored") func short() {
        let entries = (0..<5).map { _ in entry("api cd ui ok") }
        #expect(TermSuggester.suggestions(from: entries, known: []).isEmpty)
    }

    @Test("words containing digits are ignored") func digits() {
        let entries = (0..<5).map { _ in entry("build2024 shipped") }
        #expect(!TermSuggester.suggestions(from: entries, known: []).contains {
            $0.token == "build2024" })
    }

    @Test("a proper-noun shape ranks above a plain word") func ranking() {
        var entries = (0..<3).map { _ in entry("we deploy Kanji nightly") }
        entries += (0..<5).map { _ in entry("we deploy nightly rollout rollout rollout") }
        let s = TermSuggester.suggestions(from: entries, known: [])
        #expect(s.first?.token == "kanji", "proper nouns are what whisper mangles")
        #expect(s.first?.looksLikeName == true)
    }

    @Test("it reads the raw transcript, not the cleaned text") func usesRaw() {
        // A word cleanup removed is exactly the one worth suggesting.
        let e = HistoryEntry(at: Date(), cleaned: "all fine", raw: "Kanji Kanji Kanji",
                             script: .latin, appName: nil, bundleID: nil,
                             durationSeconds: 1, peakLevel: 0.3, guardRejected: false)
        #expect(TermSuggester.suggestions(from: [e], known: []).contains { $0.token == "kanji" })
    }

    @Test("an empty history suggests nothing") func emptyHistory() {
        #expect(TermSuggester.suggestions(from: [], known: []).isEmpty)
    }

    @Test("the list is capped") func cap() {
        // Letters only: the digit filter would (correctly) reject "Word1".
        let alphabet = "abcdefghijklmnopqrstuvwxyz"
        let words = alphabet.map { "Unusualword\($0)\($0)" }.joined(separator: " ")
        let entries = (0..<4).map { _ in entry(words) }
        #expect(TermSuggester.suggestions(from: entries, known: [], limit: 8).count == 8)
    }
}
