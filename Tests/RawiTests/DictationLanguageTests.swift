import Foundation
import Testing
@testable import RawiCore

@Suite("Saying which language this is") struct DictationLanguageTests {
    @Test("what whisper is told") func codes() {
        #expect(DictationLanguage.auto.whisperCode == nil)
        #expect(DictationLanguage.english.whisperCode == "en")
        #expect(DictationLanguage.arabic.whisperCode == "ar")
    }

    @Test("the pill has room for two characters") func badges() {
        #expect(DictationLanguage.english.badge == "En")
        #expect(DictationLanguage.arabic.badge == "Ar")
        // Auto is the globe on the pill; the word is for the tooltip and VoiceOver.
        #expect(DictationLanguage.auto.badge == "Auto")
        for language in DictationLanguage.allCases {
            #expect(!language.spokenName.isEmpty)
        }
    }
}

@Suite("Choosing a language from the pill") @MainActor struct LanguageChoiceTests {
    func make() -> (DictationController, FakeEngine) {
        let engine = FakeEngine()
        let controller = DictationController(
            config: .default, recorder: FakeRecorder(), engine: engine,
            cleanup: FakeCleanup(), inserter: FakeInserter(), log: FakeLog())
        return (controller, engine)
    }

    @Test("it starts out detecting") func defaultsToAuto() {
        let (controller, _) = make()
        #expect(controller.language == .auto)
    }

    @Test("the engine is told, and only when it changes") func tellsTheEngine() {
        let (controller, engine) = make()
        controller.choose(.arabic)
        #expect(controller.language == .arabic)
        #expect(engine.toldLanguages == [.arabic])
        // Choosing the same one again is not a change.
        controller.choose(.arabic)
        #expect(engine.toldLanguages == [.arabic])
        controller.choose(.auto)
        #expect(engine.toldLanguages == [.arabic, .auto])
    }

    @Test("a replacement engine inherits the choice") func survivesReconfigure() {
        let (controller, _) = make()
        controller.choose(.arabic)
        // The engine is rebuilt whenever the config changes, and when the resident
        // server hands over to the command line. A choice that quietly reset there
        // would look like the switcher not working.
        let replacement = FakeEngine()
        controller.reconfigure(config: .default, engine: replacement, cleanup: FakeCleanup())
        #expect(replacement.toldLanguages == [.arabic])
        #expect(controller.language == .arabic)
    }

    @Test("the change is announced so the pill can redraw") func announces() {
        let (controller, _) = make()
        var seen: [DictationLanguage] = []
        controller.onLanguageChange = { seen.append($0) }
        controller.choose(.english)
        controller.choose(.auto)
        #expect(seen == [.english, .auto])
    }
}
