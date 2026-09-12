import Testing
import Foundation
@testable import RawiCore

@Suite("Learning terms without being asked") struct TermLearnerTests {
    func entry(_ text: String, daysAgo: Int = 0) -> HistoryEntry {
        let at = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        return HistoryEntry(at: at, cleaned: text, raw: text, script: .latin,
                            appName: "Slack", bundleID: "slack", durationSeconds: 4,
                            peakLevel: 0.3, guardRejected: false)
    }
    func said(_ text: String, times: Int, overDays: Int = 3) -> [HistoryEntry] {
        (0..<times).map { entry(text, daysAgo: $0 % overDays) }
    }

    @Test("a name you keep saying is learned on its own") func learns() {
        let learned = TermLearner.learn(from: said("we shipped Salla today", times: 4),
                                        known: [], blocked: [])
        #expect(learned.map(\.term) == ["Salla"])
        #expect(learned.first?.occurrences == 4)
    }

    @Test("the spelling learned is the one you actually used") func casing() {
        // Lowercasing everything would put "salla" in the whisper prompt and
        // correct the right spelling into the wrong one.
        let learned = TermLearner.learn(from: said("ship Salla now", times: 5), known: [],
                                        blocked: [])
        #expect(learned.first?.term == "Salla")
    }

    @Test("said once, or all in one sitting, is not evidence") func needsRepetition() {
        #expect(TermLearner.learn(from: [entry("deploy Kubernetes")],
                                  known: [], blocked: []).isEmpty)
        // Four times in a single day is one story, not a habit.
        let sameDay = (0..<4).map { _ in entry("deploy Kubernetes", daysAgo: 0) }
        #expect(TermLearner.learn(from: sameDay, known: [], blocked: []).isEmpty)
    }

    @Test("ordinary words are never learned, however often you say them") func stopwords() {
        let learned = TermLearner.learn(from: said("please could you review this", times: 8),
                                        known: [], blocked: [])
        #expect(learned.isEmpty)
    }

    @Test("a word one edit from a common word is refused") func nearCommonWord() {
        // This is the whole risk of learning: promote "Sala" and the corrector
        // starts rewriting "sale" and "salt" into it. Doing nothing is better.
        let learned = TermLearner.learn(from: said("the Sals report", times: 6),
                                        known: [], blocked: [])
        #expect(learned.isEmpty)
    }

    @Test("a term already in the dictionary is not learned twice") func known() {
        let existing = [DictionaryTerm(term: "Salla")]
        #expect(TermLearner.learn(from: said("ship Salla", times: 6),
                                  known: existing, blocked: []).isEmpty)
    }

    @Test("a term you removed stays removed") func blocked() {
        // Otherwise removing it is pointless: it returns on the next dictation.
        #expect(TermLearner.learn(from: said("ship Salla", times: 9),
                                  known: [], blocked: ["salla"]).isEmpty)
    }

    @Test("only the strongest evidence is kept — the prompt has a budget") func capped() {
        var entries: [HistoryEntry] = []
        for (index, suffix) in "abcdefghijklmnopqrst".enumerated() {
            entries += said("the Zephyr\(suffix)nium reading", times: 4 + index)
        }
        let learned = TermLearner.learn(from: entries, known: [], blocked: [])
        #expect(learned.count <= TermLearner.limit)
        // Strongest first, so the cap keeps what matters.
        #expect(learned.first!.occurrences >= learned.last!.occurrences)
    }

    @Test("numbers and short tokens are not terms") func shapes() {
        let learned = TermLearner.learn(from: said("v2 api 1234 qa", times: 8),
                                        known: [], blocked: [])
        #expect(learned.isEmpty)
    }

    @Test("Arabic words are learned too") func arabic() {
        let learned = TermLearner.learn(from: said("نرسل التقرير الى سلة", times: 5),
                                        known: [], blocked: [])
        #expect(learned.contains { $0.term == "التقرير" })
    }

    @Test("what was learned says why, in evidence you can check") func evidence() {
        let learned = TermLearner.learn(from: said("ship Salla today", times: 5,
                                                   overDays: 4), known: [], blocked: [])
        let term = learned.first!
        #expect(term.occurrences == 5)
        #expect(term.days == 4)
        #expect(term.note.contains("5"))
    }
}

@Suite("The dictionary keeps itself") struct LearnedSyncTests {
    func store() -> VocabularyStore {
        VocabularyStore(url: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("rawi-vocab-\(UUID().uuidString).json"))
    }
    func learned(_ term: String, _ occurrences: Int = 5) -> LearnedTerm {
        LearnedTerm(term: term, occurrences: occurrences, days: 3)
    }

    @Test("learned terms arrive without being asked for") func adds() throws {
        let s = store()
        let change = s.syncLearned([learned("Salla"), learned("Kandji")])
        #expect(Set(change.added) == ["Salla", "Kandji"])
        #expect(s.terms.filter(\.addedAutomatically).count == 2)
        #expect(s.terms.first { $0.term == "Salla" }?.note.contains("heard") == true)
    }

    @Test("a term you typed yourself is never touched by learning") func manualSurvives() throws {
        let s = store()
        _ = s.addTerm("Wispr", note: "mine")
        _ = s.syncLearned([learned("Salla")])
        _ = s.syncLearned([])                       // evidence gone entirely
        #expect(s.terms.map(\.term) == ["Wispr"])
    }

    @Test("a learned term whose evidence faded is dropped, not hoarded") func drops() {
        let s = store()
        _ = s.syncLearned([learned("Salla"), learned("Kandji")])
        let change = s.syncLearned([learned("Salla")])
        #expect(change.dropped == ["Kandji"])
        #expect(s.terms.map(\.term) == ["Salla"])
    }

    @Test("removing a learned term blocks it from coming back") func blocks() {
        let s = store()
        _ = s.syncLearned([learned("Salla")])
        s.removeTerm(s.terms.first!.id)
        #expect(s.blocked == ["salla"])
        // The learner is handed the block list, so the evidence no longer matters.
        #expect(TermLearner.learn(from: [], known: s.terms, blocked: s.blocked).isEmpty)
    }

    @Test("removing a term you typed does not block it") func manualRemoval() {
        let s = store()
        _ = s.addTerm("Wispr")
        s.removeTerm(s.terms.first!.id)
        #expect(s.blocked.isEmpty)
    }

    @Test("syncing the same evidence twice changes nothing") func idempotent() {
        let s = store()
        _ = s.syncLearned([learned("Salla")])
        let second = s.syncLearned([learned("Salla")])
        #expect(second.added.isEmpty && second.dropped.isEmpty)
        #expect(s.terms.count == 1)
    }

    @Test("a learned term reaches the whisper prompt and the glossary") func reaches() {
        let s = store()
        _ = s.syncLearned([learned("Salla")])
        #expect(s.whisperPrompt().contains("Salla"))
        #expect(s.glossaryClause().contains("Salla"))
        #expect(s.snapshot().terms.contains("Salla"))
    }
}
