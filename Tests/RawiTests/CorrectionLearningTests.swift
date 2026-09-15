import Foundation
import Testing
@testable import RawiCore

@Suite("A correction becomes a dictionary term") struct CorrectionStoreTests {
    func store(_ json: String? = nil) -> (VocabularyStore, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vocab-\(UUID().uuidString).json")
        if let json { try? Data(json.utf8).write(to: url) }
        return (VocabularyStore(url: url), url)
    }

    @Test("a dictionary written before this change still loads, snippets and all") func oldFile() {
        let (s, _) = store(#"""
        {"terms":[{"id":"B0C82CFC-9646-47DB-9AA8-1DCDAAA436CD","term":"Salla","note":"","addedAutomatically":false}],
         "snippets":[{"id":"7F85FBBE-D715-40E7-8715-0880B9406143","trigger":"My email","expansion":"me@example.com"}]}
        """#)
        #expect(s.terms.map(\.term) == ["Salla"])
        #expect(s.snippets.map(\.trigger) == ["My email"])
        #expect(s.blocked.isEmpty)
    }

    @Test("a correction is learned with what was heard") func learns() {
        let (s, _) = store()
        #expect(s.learnCorrection(heard: "Kanjee", fixed: "Kandji", app: "Slack"))
        let term = try? #require(s.terms.first)
        #expect(term?.term == "Kandji")
        #expect(term?.learnedFromCorrection == true)
        #expect(term?.heardAs == ["kanjee"])
        #expect(s.snapshot().aliases == ["kanjee": "Kandji"])
    }

    @Test("correcting the same word again adds the new mishearing, not a second term") func again() {
        let (s, _) = store()
        s.learnCorrection(heard: "Kanjee", fixed: "Kandji", app: nil)
        #expect(!s.learnCorrection(heard: "Candy", fixed: "kandji", app: nil, alias: false))
        #expect(!s.learnCorrection(heard: "Kanji", fixed: "Kandji", app: nil))
        #expect(s.terms.count == 1)
        #expect(s.terms.first?.heardAs == ["kanjee", "kanji"])
    }

    @Test("a term you removed is not brought back by one correction") func blocked() {
        let (s, _) = store()
        s.learnCorrection(heard: "Sala", fixed: "Salla", app: nil)
        s.removeTerm(s.terms[0].id)
        #expect(!s.learnCorrection(heard: "Sala", fixed: "Salla", app: nil))
        #expect(s.terms.isEmpty)
    }

    @Test("the spelling learner cannot drop what you corrected") func survivesSync() {
        let (s, _) = store()
        s.learnCorrection(heard: "Sala", fixed: "Salla", app: nil)
        let change = s.syncLearned([])
        #expect(change.dropped.isEmpty)
        #expect(s.terms.map(\.term) == ["Salla"])
    }

    @Test("it survives a save and a reload") func persists() {
        let (s, url) = store()
        s.learnCorrection(heard: "Kanjee", fixed: "Kandji", app: nil)
        let reloaded = VocabularyStore(url: url)
        #expect(reloaded.terms.first?.heardAs == ["kanjee"])
        #expect(reloaded.terms.first?.learnedFromCorrection == true)
    }
}

@Suite("Using what you corrected") struct AliasCorrectorTests {
    @Test("a mishearing you fixed is fixed next time, however far off") func alias() {
        let out = TermCorrector.apply("We moved the laptops to Kanjee last week.",
                                      terms: ["Kandji"], aliases: ["kanjee": "Kandji"])
        #expect(out == "We moved the laptops to Kandji last week.")
    }

    @Test("only whole words are replaced") func wholeWords() {
        let out = TermCorrector.apply("kanjeeish is not a word", terms: [], aliases: ["kanjee": "Kandji"])
        #expect(out == "kanjeeish is not a word")
    }

    @Test("with the bad term gone, building stays building") func buildingIsBuilding() {
        #expect(TermCorrector.apply("The building is ready.", terms: ["Salla"]) == "The building is ready.")
    }
}

@MainActor
@Suite("Watching what was typed") struct EditWatchWiringTests {
    func rig() -> (DictationController, FakeInserter, FakeEditWatcher) {
        let r = FakeRecorder(), e = FakeEngine(), c = FakeCleanup(), i = FakeInserter(), l = FakeLog()
        var config = Config.default
        config.output.deliverRawFirst = false
        let ctl = DictationController(config: config, recorder: r, engine: e, cleanup: c,
                                      inserter: i, log: l)
        let watcher = FakeEditWatcher()
        ctl.editWatcher = watcher
        return (ctl, i, watcher)
    }

    @Test("a successful paste is watched") func watches() async {
        let (ctl, _, watcher) = rig()
        ctl.mayWatchEdits = { _ in true }
        await ctl.handle(.beganHold)
        await ctl.handle(.endedHold)
        #expect(watcher.watched.map(\.text) == ["Cleaned transcript."])
    }

    @Test("an excluded app is never watched") func excluded() async {
        let (ctl, _, watcher) = rig()
        ctl.mayWatchEdits = { _ in false }
        await ctl.handle(.beganHold)
        await ctl.handle(.endedHold)
        #expect(watcher.watched.isEmpty)
    }

    @Test("text left on the clipboard is not watched") func notPasted() async {
        let (ctl, ins, watcher) = rig()
        ctl.mayWatchEdits = { _ in true }
        ins.succeed = false
        await ctl.handle(.beganHold)
        await ctl.handle(.endedHold)
        #expect(watcher.watched.isEmpty)
    }

    @Test("the next dictation takes a last look first") func flushes() async {
        let (ctl, _, watcher) = rig()
        await ctl.handle(.beganHold)
        #expect(watcher.flushes == 1)
    }
}
