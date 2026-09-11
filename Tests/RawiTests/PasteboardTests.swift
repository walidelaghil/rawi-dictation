import Testing
import AppKit
@testable import RawiCore

@Suite("Pasteboard") struct PasteboardTests {
    func scratch() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("wf-test-\(UUID().uuidString)"))
    }

    @Test("captures and restores a string") func roundTrip() {
        let pb = scratch()
        pb.clearContents(); pb.setString("original", forType: .string)

        let stash = PasteboardStash.capture(pb)
        pb.clearContents(); pb.setString("replacement", forType: .string)
        #expect(pb.string(forType: .string) == "replacement")

        stash.restore(to: pb)
        #expect(pb.string(forType: .string) == "original")
    }

    @Test("captures an empty pasteboard without crashing") func empty() {
        let pb = scratch()
        pb.clearContents()
        let stash = PasteboardStash.capture(pb)
        #expect(stash.isEmpty)
        stash.restore(to: pb)
        #expect(pb.string(forType: .string) == nil)
    }

    @Test("preserves multiple types on one item") func multiType() {
        let pb = scratch()
        pb.clearContents()
        let item = NSPasteboardItem()
        item.setString("plain", forType: .string)
        item.setString("<b>rich</b>", forType: .html)
        pb.writeObjects([item])

        let stash = PasteboardStash.capture(pb)
        pb.clearContents(); pb.setString("gone", forType: .string)
        stash.restore(to: pb)

        #expect(pb.string(forType: .string) == "plain")
        #expect(pb.string(forType: .html) == "<b>rich</b>")
    }

    @Test("preserves binary data such as an image") func binary() {
        let pb = scratch()
        pb.clearContents()
        let bytes = Data([0x89, 0x50, 0x4E, 0x47, 0x00, 0xFF])
        let item = NSPasteboardItem()
        item.setData(bytes, forType: .png)
        pb.writeObjects([item])

        let stash = PasteboardStash.capture(pb)
        pb.clearContents(); pb.setString("gone", forType: .string)
        stash.restore(to: pb)

        #expect(pb.data(forType: .png) == bytes)
    }
}
