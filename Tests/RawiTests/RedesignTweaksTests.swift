import Testing
import AppKit
@testable import RawiCore

@MainActor
@Suite("Redesign tweaks") struct RedesignTweaksTests {
    @Test("the key hint on Transforms and Commands opens Settings and can come back")
    func settingsAndBack() {
        let selection = ScreenSelection()
        selection.screen = .transforms
        selection.openSettings(from: .transforms)
        #expect(selection.screen == .settings)
        #expect(selection.returnTo == .transforms)
        selection.goBack()
        #expect(selection.screen == .transforms)
        #expect(selection.returnTo == nil)
    }

    @Test("picking a row in the rail forgets where you came from")
    func railForgets() {
        let selection = ScreenSelection()
        selection.openSettings(from: .commands)
        selection.go(.history)
        #expect(selection.screen == .history)
        #expect(selection.returnTo == nil)
    }

    @Test("sharing copies the image and the page can tell you so")
    func shareCopies() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("rawi-test-\(UUID().uuidString)"))
        let model = InsightsViewModel(store: HistoryStore(
            url: FileManager.default.temporaryDirectory.appendingPathComponent("s-\(UUID().uuidString).jsonl")))
        let image = NSImage(size: NSSize(width: 20, height: 10), flipped: false) { rect in
            NSColor.red.setFill(); rect.fill(); return true
        }
        model.copyToClipboard(image, pasteboard: pasteboard)
        #expect(model.copiedImage != nil)
        #expect(pasteboard.canReadObject(forClasses: [NSImage.self], options: nil))
        model.dismissCopied()
        #expect(model.copiedImage == nil)
    }
}

@MainActor
@Suite("Dictionary refresh asks first") struct RefreshConfirmationTests {
    func model() -> VocabularyViewModel {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return VocabularyViewModel(store: VocabularyStore(url: dir.appendingPathComponent("v.json")),
                                   history: HistoryStore(url: dir.appendingPathComponent("h.jsonl")))
    }

    @Test("the button asks, and only confirming runs the refresh") func asksFirst() {
        let m = model()
        m.askToRefresh()
        #expect(m.confirmingRefresh)
        #expect(m.refreshResult == nil)
        m.confirmRefresh()
        #expect(!m.confirmingRefresh)
        #expect(m.refreshResult == "Up to date")
    }

    @Test("cancelling leaves everything as it was") func cancel() {
        let m = model()
        m.askToRefresh()
        m.cancelRefresh()
        #expect(!m.confirmingRefresh)
        #expect(m.refreshResult == nil)
    }
}
