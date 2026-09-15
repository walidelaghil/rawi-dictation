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

    /// Says each variant in turn, across several days.
    func heard(_ variants: [String], times: Int, overDays: Int = 3) -> [HistoryEntry] {
        (0..<times).map { index in
            entry("we shipped \(variants[index % variants.count]) today",
                  daysAgo: index % overDays)
        }
    }

    @Test("a name whisper cannot spell consistently is learned") func learnsUnstable() {
        // This is the whole point: the dictionary exists to fix words whisper gets
        // wrong, and the evidence that it is getting one wrong is that it spells it
        // differently from one dictation to the next.
        let learned = TermLearner.learn(from: heard(["Salla", "Sala", "Salla", "Sallah"],
                                                    times: 8), known: [], blocked: [])
        #expect(learned.map(\.term) == ["Salla"])
    }

    @Test("a word it always spells the same way is left alone") func ignoresStable() {
        // "database" and "actually" were both learned by the previous rule, which
        // asked only whether a word recurred. Everything you say often recurs.
        for word in ["database", "actually", "migration", "billing", "Kubernetes"] {
            let learned = TermLearner.learn(from: heard([word], times: 11, overDays: 4),
                                            known: [], blocked: [])
            #expect(learned.isEmpty, Comment(rawValue: "learned \(word)"))
        }
    }

    @Test("the spelling enforced is the one you use most") func dominant() {
        let learned = TermLearner.learn(
            from: heard(["Salla", "Salla", "Salla", "Sala"], times: 8),
            known: [], blocked: [])
        #expect(learned.first?.term == "Salla")
    }

    @Test("a word with no dominant spelling is not worth enforcing") func noDominant() {
        // Four ways of saying it and none of them a favourite means we would be
        // guessing which one you meant.
        let learned = TermLearner.learn(
            from: heard(["Sala", "Salah", "Sallah", "Salaa"], times: 8),
            known: [], blocked: [])
        #expect(learned.isEmpty)
    }

    @Test("variants only count when they are variants of each other") func notRelated() {
        // "report" and "support" are not two spellings of one word.
        let learned = TermLearner.learn(from: heard(["report", "support"], times: 10),
                                        known: [], blocked: [])
        #expect(learned.isEmpty)
    }

    @Test("said once, or all in one sitting, is not evidence") func needsRepetition() {
        #expect(TermLearner.learn(from: [entry("deploy Kubernetes")],
                                  known: [], blocked: []).isEmpty)
        let sameDay = (0..<6).map { _ in entry("ship Salla and Sala", daysAgo: 0) }
        #expect(TermLearner.learn(from: sameDay, known: [], blocked: []).isEmpty)
    }

    @Test("ordinary words are never learned, however they are spelled") func stopwords() {
        let learned = TermLearner.learn(from: heard(["please", "pleese"], times: 8),
                                        known: [], blocked: [])
        #expect(learned.isEmpty)
    }

    @Test("a word one edit from a common word is refused") func nearCommonWord() {
        // Promote "Sals" and the corrector starts rewriting "sale" and "salt".
        let learned = TermLearner.learn(from: heard(["Sals", "Salz"], times: 8),
                                        known: [], blocked: [])
        #expect(learned.isEmpty)
    }

    @Test("a term already in the dictionary is not learned twice") func known() {
        let existing = [DictionaryTerm(term: "Salla")]
        #expect(TermLearner.learn(from: heard(["Salla", "Sala"], times: 8),
                                  known: existing, blocked: []).isEmpty)
    }

    @Test("a term you removed stays removed") func blocked() {
        #expect(TermLearner.learn(from: heard(["Salla", "Sala"], times: 9),
                                  known: [], blocked: ["salla"]).isEmpty)
    }

    @Test("numbers and short tokens are not terms") func shapes() {
        let learned = TermLearner.learn(from: heard(["v2", "api", "1234", "qa"], times: 8),
                                        known: [], blocked: [])
        #expect(learned.isEmpty)
    }

    @Test("Arabic is judged the same way, by inconsistency") func arabic() {
        // Three times the way you mean it, once the way whisper slipped.
        let unstable = TermLearner.learn(
            from: heard(["التقرير", "التقرير", "التقرير", "التقرر"], times: 8),
            known: [], blocked: [])
        #expect(unstable.first?.term == "التقرير")
        let stable = TermLearner.learn(from: heard(["التقرير"], times: 11), known: [],
                                       blocked: [])
        #expect(stable.isEmpty)
    }

    @Test("what was learned says why, in evidence you can check") func evidence() {
        let learned = TermLearner.learn(from: heard(["Salla", "Sala"], times: 8, overDays: 4),
                                        known: [], blocked: [])
        let term = learned.first!
        #expect(term.occurrences == 8)
        #expect(term.days == 4)
        #expect(term.note.contains("8"))
        #expect(term.note.contains("spellings") || term.note.contains("ways"))
    }

    @Test("only the strongest evidence is kept — the prompt has a budget") func capped() {
        // Distinct first letters, or every one of these is a variant of the next
        // and they collapse into a single cluster.
        var entries: [HistoryEntry] = []
        for (index, letter) in "BCDFGHJKLMNPQRSTVWXZ".enumerated() {
            entries += heard(["\(letter)ephyrium", "\(letter)ephyriom"], times: 4 + index)
        }
        let learned = TermLearner.learn(from: entries, known: [], blocked: [])
        #expect(learned.count <= TermLearner.limit)
        #expect(learned.first!.occurrences >= learned.last!.occurrences)
    }

    @Test("two real words a letter or two apart are not one term") func billingBuilding() {
        // What actually happened: replays of a test sentence said "billing" 26
        // times, one real dictation said "building", and the pair was learned as
        // one word heard two ways.
        let entries = heard(["billing", "billing", "building", "billing"], times: 7, overDays: 3)
        let learned = TermLearner.learn(from: entries, known: [], blocked: [])
        #expect(!learned.contains { $0.term.lowercased() == "billing" })
        #expect(!learned.contains { $0.term.lowercased() == "building" })
    }

    @Test("an ordinary word is never enforced, even with a garbled neighbour") func actually() {
        let entries = heard(["actually", "actually", "actualy", "actually"], times: 6, overDays: 3)
        let learned = TermLearner.learn(from: entries, known: [], blocked: [])
        #expect(!learned.contains { $0.term.lowercased() == "actually" })
    }

    @Test("the spell checker knows ordinary words and not names") func spellCheck() {
        #expect(SpellCheck.isOrdinaryEnglish("billing"))
        #expect(SpellCheck.isOrdinaryEnglish("actually"))
        #expect(!SpellCheck.isOrdinaryEnglish("sallah"))
    }
}

