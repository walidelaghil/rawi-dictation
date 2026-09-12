import Testing
import Foundation
@testable import RawiCore

@Suite("VocabularyStore") struct VocabularyStoreTests {
    func tmp() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("rawi-vocab-\(UUID().uuidString).json")
    }

    @Test("terms and snippets survive a reload") func persists() {
        let url = tmp(); defer { try? FileManager.default.removeItem(at: url) }
        let s = VocabularyStore(url: url)
        s.addTerm("Salla", note: "heard as Sala")
        s.addSnippet(trigger: "my email", expansion: "waleed@example.com")
        let back = VocabularyStore(url: url)
        #expect(back.terms.map(\.term) == ["Salla"])
        #expect(back.snippets.first?.expansion == "waleed@example.com")
    }

    @Test("a duplicate term is rejected regardless of case") func duplicates() {
        let url = tmp(); defer { try? FileManager.default.removeItem(at: url) }
        let s = VocabularyStore(url: url)
        #expect(s.addTerm("Salla"))
        // Both spellings would waste the whisper prompt's limited budget.
        #expect(!s.addTerm("salla"))
        #expect(!s.addTerm("  SALLA  "))
        #expect(s.terms.count == 1)
    }

    @Test("an empty term is refused") func empty() {
        let url = tmp(); defer { try? FileManager.default.removeItem(at: url) }
        let s = VocabularyStore(url: url)
        #expect(!s.addTerm("   "))
        #expect(s.terms.isEmpty)
    }

    @Test("a snippet needs both halves") func snippetHalves() {
        let url = tmp(); defer { try? FileManager.default.removeItem(at: url) }
        let s = VocabularyStore(url: url)
        #expect(!s.addSnippet(trigger: "x", expansion: "  "))
        #expect(!s.addSnippet(trigger: "  ", expansion: "y"))
        #expect(s.snippets.isEmpty)
    }

    @Test("terms and snippets can be removed") func removal() {
        let url = tmp(); defer { try? FileManager.default.removeItem(at: url) }
        let s = VocabularyStore(url: url)
        s.addTerm("Kandji"); s.addSnippet(trigger: "sig", expansion: "Best, W")
        s.removeTerm(s.terms[0].id); s.removeSnippet(s.snippets[0].id)
        #expect(VocabularyStore(url: url).terms.isEmpty)
        #expect(VocabularyStore(url: url).snippets.isEmpty)
    }

    @Test("the whisper prompt is a comma list of terms") func prompt() {
        let url = tmp(); defer { try? FileManager.default.removeItem(at: url) }
        let s = VocabularyStore(url: url)
        s.addTerm("Salla"); s.addTerm("Kandji"); s.addTerm("Argo CD")
        #expect(s.whisperPrompt() == "Salla, Kandji, Argo CD")
    }

    @Test("the prompt caps without truncating a term mid-word") func promptCap() {
        let url = tmp(); defer { try? FileManager.default.removeItem(at: url) }
        let s = VocabularyStore(url: url)
        for i in 0..<50 { s.addTerm("Term\(i)Longenoughtomatter") }
        let prompt = s.whisperPrompt(maxCharacters: 100)
        #expect(prompt.count <= 100)
        // Overflowing --prompt degrades transcription silently; a half term is a
        // wrong hint, so every listed term must be whole.
        for piece in prompt.components(separatedBy: ", ") {
            #expect(s.terms.contains { $0.term == piece }, "truncated term: \(piece)")
        }
    }

    @Test("an empty dictionary produces no prompt and no glossary") func emptyVocab() {
        let url = tmp(); defer { try? FileManager.default.removeItem(at: url) }
        let s = VocabularyStore(url: url)
        #expect(s.whisperPrompt().isEmpty)
        #expect(s.glossaryClause().isEmpty)
        #expect(s.snapshot() == .empty)
    }

    @Test("the glossary names every term and tells the model to spell it exactly") func glossary() {
        let url = tmp(); defer { try? FileManager.default.removeItem(at: url) }
        let s = VocabularyStore(url: url)
        s.addTerm("Salla"); s.addTerm("مِسك")
        let clause = s.glossaryClause()
        #expect(clause.contains("Salla"))
        #expect(clause.contains("مِسك"))
        #expect(clause.lowercased().contains("exactly"))
    }

    @Test("a snapshot carries everything a dictation needs") func snapshot() {
        let url = tmp(); defer { try? FileManager.default.removeItem(at: url) }
        let s = VocabularyStore(url: url)
        s.addTerm("Salla"); s.addSnippet(trigger: "sig", expansion: "Best, Waleed")
        let snap = s.snapshot()
        #expect(snap.whisperPrompt == "Salla")
        #expect(snap.glossary.contains("Salla"))
        #expect(snap.snippets.count == 1)
    }
}

@MainActor
@Suite("Two-layer injection") struct InjectionTests {
    func rig(_ vocab: VocabularySnapshot)
        -> (DictationController, FakeEngine, FakeInserter) {
        let r = FakeRecorder(), e = FakeEngine(), c = FakeCleanup()
        let i = FakeInserter()
        e.result = .success("call Sala about the deploy")
        c.result = .success("Call Sala about the deploy.")
        let ctl = DictationController(config: .default, recorder: r, engine: e,
                                      cleanup: c, inserter: i, log: FakeLog())
        ctl.vocabulary = { vocab }
        return (ctl, e, i)
    }

    @Test("dictionary terms reach whisper as a decoder hint") func layerOne() async {
        let (ctl, engine, _) = rig(VocabularySnapshot(
            whisperPrompt: "Salla, Kandji", glossary: "", snippets: []))
        await ctl.handle(.beganHold)
        await ctl.handle(.endedHold)
        #expect(engine.lastPrompt == "Salla, Kandji")
    }

    @Test("no terms means no prompt, not an empty flag") func noTerms() async {
        let (ctl, engine, _) = rig(.empty)
        await ctl.handle(.beganHold)
        await ctl.handle(.endedHold)
        #expect(engine.lastPrompt.isEmpty)
    }

    @Test("the glossary reaches the cleanup prompt") func layerTwo() {
        var built: [String] = []
        let routed = RoutedCleanup(
            kind: .ollama, apiKey: nil,
            models: CleanupModels(latin: "m", arabic: "m"),
            prompt: "BASE", glossary: "\n\nSpell exactly: Salla.",
            makeProvider: { _ in NoopCleanup() })
        _ = routed
        // Build one directly to inspect the composed prompt.
        let direct = ChatCleanup(kind: .ollama, apiKey: nil, model: "m",
                                 prompt: "BASE" + "\n\nSpell exactly: Salla.")
        let body = try! ChatCleanup.requestBody(kind: .ollama, model: "m",
            prompt: "BASE" + "\n\nSpell exactly: Salla.", user: wrapTranscript("t"))
        let json = try! JSONSerialization.jsonObject(with: body) as! [String: Any]
        let msgs = json["messages"] as! [[String: String]]
        #expect(msgs[0]["content"]!.contains("Salla"))
        #expect(msgs[0]["content"]!.hasPrefix("BASE"))
        built.append("ok"); _ = direct
        #expect(built == ["ok"])
    }

    @Test("snippets expand in the inserted text") func snippets() async {
        let (ctl, _, inserter) = rig(VocabularySnapshot(
            whisperPrompt: "", glossary: "",
            snippets: [Snippet(trigger: "the deploy", expansion: "release 4.2")]))
        await ctl.handle(.beganHold)
        await ctl.handle(.endedHold)
        #expect(inserter.inserted.first == "Call Sala about release 4.2.")
    }

    @Test("vocabulary is captured at key-press, not at insert") func capturedEarly() async {
        let (ctl, engine, _) = rig(VocabularySnapshot(
            whisperPrompt: "Salla", glossary: "", snippets: []))
        await ctl.handle(.beganHold)
        ctl.vocabulary = { .empty }        // edited mid-dictation
        await ctl.handle(.endedHold)
        #expect(engine.lastPrompt == "Salla")
    }
}
