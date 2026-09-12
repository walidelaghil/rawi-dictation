import Testing
import AppKit
@testable import RawiCore

@Suite("Rawi mark") struct RawiMarkTests {
    @Test("the mark is the canvas path, seven points and no curves") func geometry() {
        let path = RawiMark.path(in: CGRect(x: 0, y: 0, width: 24, height: 24))
        #expect(path.elementCount == 7)
        for index in 0..<path.elementCount {
            #expect(path.element(at: index) == (index == 0 ? .moveTo : .lineTo))
        }
    }

    @Test("the mark stays inside the box it is given") func bounds() {
        for size in [CGFloat(16), 18, 44, 512] {
            let rect = CGRect(x: 0, y: 0, width: size, height: size)
            let bounds = RawiMark.path(in: rect).bounds
            #expect(rect.insetBy(dx: -1, dy: -1).contains(bounds))
            // And it fills it: a mark that shrinks to a dot would pass containment.
            #expect(bounds.width > size * 0.7)
        }
    }

    @Test("the stroke scales with the mark, so 16pt is not a hairline") func stroke() {
        let small = RawiMark.path(in: CGRect(x: 0, y: 0, width: 18, height: 18)).lineWidth
        let large = RawiMark.path(in: CGRect(x: 0, y: 0, width: 512, height: 512)).lineWidth
        #expect(small > 1.4 && small < 1.8)
        #expect(large > 40)
    }

    @Test("an untinted mark is a template, a tinted one is not") func template() {
        // The distinction is load-bearing: the menu bar recolours a template image to
        // match its own appearance, which would throw away a state colour.
        #expect(RawiMark.image().isTemplate)
        #expect(!RawiMark.image(tint: .red).isTemplate)
    }

    @Test("every state that matters gets its own menu-bar treatment") func states() {
        func png(_ image: NSImage) -> Data? {
            image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:))?
                .representation(using: .png, properties: [:])
        }
        let idle = RawiMark.statusImage(state: .idle, enabled: true, microphoneGranted: true)
        let recording = RawiMark.statusImage(
            state: .recording(mode: .pushToTalk, startedAt: .now),
            enabled: true, microphoneGranted: true)
        let noMic = RawiMark.statusImage(state: .idle, enabled: true, microphoneGranted: false)
        let off = RawiMark.statusImage(state: .idle, enabled: false, microphoneGranted: true)

        #expect(idle.isTemplate)
        #expect(!recording.isTemplate)
        #expect(png(idle) != png(recording))
        #expect(png(idle) != png(noMic))
        #expect(png(idle) != png(off))
        #expect(png(recording) != png(noMic))
    }

    @Test("the app icon is opaque where the body is and clear at the corner") func appIcon() {
        let size: CGFloat = 256
        let icon = RawiMark.appIcon(size: size)
        let rep = NSBitmapImageRep(data: icon.tiffRepresentation!)!
        // Middle of the body: painted.
        #expect((rep.colorAt(x: Int(size / 2), y: Int(size / 2))?.alphaComponent ?? 0) > 0.9)
        // Extreme corner: outside the rounded square, so nothing.
        #expect((rep.colorAt(x: 0, y: 0)?.alphaComponent ?? 1) < 0.1)
    }

    @Test("an iconset writes every size iconutil expects") func iconset() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("Rawi-\(UUID().uuidString).iconset")
        defer { try? FileManager.default.removeItem(at: dir) }
        try RawiMark.writeIconset(to: dir)
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
        #expect(names.count == 10)
        #expect(names.contains("icon_16x16.png"))
        #expect(names.contains("icon_512x512@2x.png"))
    }

    /// Renders a sheet of every state to look at, because "the tests pass" says
    /// nothing about whether an icon reads at 18 points.
    @Test("proof sheet", .enabled(if: ProcessInfo.processInfo.environment["RAWI_PROOF"] != nil))
    func proof() throws {
        let out = URL(fileURLWithPath: ProcessInfo.processInfo.environment["RAWI_PROOF"]!)
        let width: CGFloat = 520, height: CGFloat = 300
        let sheet = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            NSColor.white.setFill()
            CGRect(x: 0, y: 0, width: width, height: height).fill()
            // Two menu-bar strips: the template mark on light and on dark.
            for (row, bar) in [(CGFloat(250), NSColor.white), (200, NSColor(white: 0.13, alpha: 1))] {
                bar.setFill()
                CGRect(x: 0, y: row, width: width, height: 40).fill()
                let states: [(DictationState, Bool, Bool)] = [
                    (.idle, true, true),
                    (.recording(mode: .pushToTalk, startedAt: .now), true, true),
                    (.transforming, true, true),
                    (.idle, true, false),
                    (.idle, false, true),
                ]
                for (index, s) in states.enumerated() {
                    let image = RawiMark.statusImage(state: s.0, enabled: s.1,
                                                     microphoneGranted: s.2)
                    let box = CGRect(x: 18 + CGFloat(index) * 46, y: row + 11,
                                     width: 18, height: 18)
                    // Paint a template through its own alpha, as the menu bar does,
                    // so the faded "disabled" state shows up faded here too. The
                    // tinting happens in its own transparent image: composited
                    // straight onto the sheet, `sourceAtop` would fill the whole box.
                    if image.isTemplate {
                        let tinted = NSImage(size: image.size)
                        tinted.lockFocus()
                        image.draw(at: .zero, from: .zero, operation: .sourceOver,
                                   fraction: 1)
                        (bar == NSColor.white ? NSColor.black : NSColor.white).set()
                        NSRect(origin: .zero, size: image.size).fill(using: .sourceAtop)
                        tinted.unlockFocus()
                        tinted.draw(in: box)
                    } else {
                        image.draw(in: box)
                    }
                }
            }
            // The app icon at the sizes the Dock and Finder actually use.
            var x: CGFloat = 18
            for size in [CGFloat(128), 64, 32, 16] {
                RawiMark.appIcon(size: size).draw(in: CGRect(x: x, y: 40, width: size, height: size))
                x += size + 16
            }
            return true
        }
        let png = NSBitmapImageRep(data: sheet.tiffRepresentation!)!
            .representation(using: .png, properties: [:])!
        try png.write(to: out)
    }
}
