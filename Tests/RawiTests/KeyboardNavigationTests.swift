import Testing
import Foundation
@testable import RawiCore

@MainActor
@Suite("Keyboard") struct KeyboardNavigationTests {
    func rig(_ count: Int = 4) -> HistoryViewModel {
        let store = HistoryStore(url: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("rawi-kb-\(UUID().uuidString).jsonl"))
        for index in 0..<count {
            store.append(HistoryEntry(at: Date().addingTimeInterval(Double(-index)),
                                      cleaned: "entry \(index)", raw: "entry \(index)",
                                      script: .latin, appName: "Slack", bundleID: "slack",
                                      durationSeconds: 3, peakLevel: 0.3, guardRejected: false))
        }
        // History is newest first, so the rows read ["entry 0"... ] reversed:
        // the last one appended sits at the top.
        return HistoryViewModel(store: store)
    }

    @Test("the rows are newest first, which is what the arrows move through") func order() {
        #expect(rig().visible.map(\.cleaned) == ["entry 3", "entry 2", "entry 1", "entry 0"])
    }

    @Test("down selects the first row when nothing is selected") func firstDown() {
        let model = rig()
        model.moveSelection(by: 1)
        #expect(model.selected?.cleaned == "entry 3")
    }

    @Test("up from nothing selects the last row") func firstUp() {
        let model = rig()
        model.moveSelection(by: -1)
        #expect(model.selected?.cleaned == "entry 0")
    }

    @Test("selection moves and stops at the ends rather than wrapping") func clamps() {
        // Wrapping from the bottom back to the top loses your place in a list you
        // are scanning.
        let model = rig()
        model.moveSelection(by: 1)
        model.moveSelection(by: -1)
        #expect(model.selected?.cleaned == "entry 3")    // already at the top
        for _ in 0..<10 { model.moveSelection(by: 1) }
        #expect(model.selected?.cleaned == "entry 0")    // and stops at the bottom
    }

    @Test("selection follows the filter, never points at a hidden row") func filtered() {
        let model = rig()
        model.moveSelection(by: 1)
        model.moveSelection(by: 1)                       // entry 1
        model.filter.query = "entry 3"
        // The selected row is no longer on screen, so nothing is highlighted
        // rather than the highlight jumping to a dictation you did not choose.
        #expect(model.selected == nil)
        model.moveSelection(by: 1)
        #expect(model.selected?.cleaned == "entry 3")
        model.filter.query = "nothing matches"
        #expect(model.selected == nil)
    }

    @Test("deleting keeps you where you were, on the next row down") func deleteKeepsPlace() {
        let model = rig()
        model.moveSelection(by: 1)
        model.moveSelection(by: 1)                       // entry 1
        model.deleteSelected()
        #expect(model.selected?.cleaned == "entry 1")
        #expect(model.visible.count == 3)
    }

    @Test("deleting the last row selects the one above it") func deleteLast() {
        let model = rig()
        for _ in 0..<4 { model.moveSelection(by: 1) }    // the bottom row
        model.deleteSelected()
        #expect(model.selected?.cleaned == "entry 1")
    }

    @Test("deleting the only row leaves nothing selected") func deleteOnly() {
        let model = rig(1)
        model.moveSelection(by: 1)
        model.deleteSelected()
        #expect(model.selected == nil)
        #expect(model.visible.isEmpty)
    }

    @Test("copy needs a selection and reports whether it acted") func copy() {
        let model = rig()
        #expect(!model.copySelected())
        model.moveSelection(by: 1)
        #expect(model.copySelected())
    }

    @Test("escape clears a search before it closes anything") func escape() {
        // Two jobs on one key, in the order you want them: the search box is the
        // thing you are most likely to be escaping from.
        let model = rig()
        model.filter.query = "launch"
        #expect(model.escape() == .clearedSearch)
        #expect(model.filter.query.isEmpty)
        #expect(model.escape() == .nothingToClear)
        model.moveSelection(by: 1)
        #expect(model.escape() == .clearedSelection)
        #expect(model.escape() == .nothingToClear)
    }
}
