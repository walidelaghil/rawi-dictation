import Testing
import Foundation
@testable import RawiCore

@Suite("The learned dictionary holds still between dictations") struct LearnedTermStabilityTests {
    func entry(_ text: String, daysAgo: Int) -> HistoryEntry {
        let at = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        return HistoryEntry(at: at, cleaned: text, raw: text, script: .latin,
                            appName: "Slack", bundleID: "slack", durationSeconds: 4,
                            peakLevel: 0.3, guardRejected: false)
    }

    /// Salla heard four ways, enough days to count, so it is learned on the first pass.
    var history: [HistoryEntry] {
        (0..<8).map { entry("we shipped \(["Salla", "Sala", "Salla", "Sallah"][$0 % 4]) today",
                            daysAgo: $0 % 3) }
    }

    func store() -> (VocabularyStore, URL) {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("rawi-stable-\(UUID().uuidString).json")
        return (VocabularyStore(url: url), url)
    }

    @Test("learning the same history again changes nothing") func idempotent() {
        let (vocabulary, url) = store(); defer { try? FileManager.default.removeItem(at: url) }
        var changes: [Int] = []
        for _ in 0..<5 {
            let change = vocabulary.learnTerms(from: history)
            changes.append(change.added.count + change.dropped.count)
        }
        // The first pass learns it. Every pass after that has nothing new to say.
        #expect(changes == [1, 0, 0, 0, 0])
        #expect(vocabulary.terms.map(\.term) == ["Salla"])
    }

    @Test("a term you added by hand is not learned over and not dropped") func manualStays() {
        let (vocabulary, url) = store(); defer { try? FileManager.default.removeItem(at: url) }
        vocabulary.addTerm("Salla")
        for _ in 0..<3 { _ = vocabulary.learnTerms(from: history) }
        #expect(vocabulary.terms.map(\.term) == ["Salla"])
        #expect(vocabulary.terms.first?.addedAutomatically == false)
    }
}
