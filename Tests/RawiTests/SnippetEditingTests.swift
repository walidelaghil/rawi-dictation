import Foundation
import Testing
@testable import RawiCore

@Suite("Snippet editing") struct SnippetEditingTests {
    private func store() -> VocabularyStore {
        VocabularyStore(url: FileManager.default.temporaryDirectory
            .appendingPathComponent("snip-\(UUID()).json"))
    }

    @Test("a snippet can be edited, and keeps its place") func edit() {
        let s = store()
        s.addSnippet(trigger: "a", expansion: "one")
        s.addSnippet(trigger: "b", expansion: "two")
        let id = s.snippets[0].id
        #expect(s.updateSnippet(id, trigger: "a2", expansion: "uno", sensitive: true))
        #expect(s.snippets[0].trigger == "a2" && s.snippets[0].sensitive)
    }

    @Test("an edit cannot take another snippet's trigger") func duplicate() {
        let s = store()
        s.addSnippet(trigger: "a", expansion: "one")
        s.addSnippet(trigger: "b", expansion: "two")
        #expect(!s.updateSnippet(s.snippets[1].id, trigger: "A", expansion: "x", sensitive: false))
    }

    @Test("undo puts a deleted snippet back where it was") func undo() {
        let s = store()
        s.addSnippet(trigger: "a", expansion: "one")
        s.addSnippet(trigger: "b", expansion: "two")
        let gone = s.snippets[0]
        s.removeSnippet(gone.id)
        s.restoreSnippet(gone, at: 0)
        #expect(s.snippets.map(\.trigger) == ["a", "b"])
    }

    @Test("a file written before 'sensitive' existed still loads") func oldFile() throws {
        let json = #"{"id":"\#(UUID())","trigger":"t","expansion":"e"}"#
        let snippet = try JSONDecoder().decode(Snippet.self, from: Data(json.utf8))
        #expect(!snippet.sensitive)
    }

    @Test("a snippet that fires is counted") func usage() {
        let snippet = Snippet(trigger: "my email", expansion: "a@b.c")
        let result = SnippetExpander.expandReporting("send to my email now", with: [snippet])
        #expect(result.used == [snippet.id])
        let s = store()
        s.addSnippet(trigger: "my email", expansion: "a@b.c")
        s.recordUse(of: [s.snippets[0].id]); s.recordUse(of: [s.snippets[0].id])
        #expect(s.snippets[0].uses == 2)
    }
}
