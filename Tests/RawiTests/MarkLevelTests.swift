import Testing
import AppKit
@testable import RawiCore

@Suite("The mark hears you") struct MarkLevelTests {
    @Test("the mark's peaks follow the level") func responds() {
        let quiet = RawiMark.svgPoints(level: 0)
        let loud = RawiMark.svgPoints(level: 1)
        // SVG y counts downward: point 2 is the crest, point 3 the trough.
        #expect(loud[2].y < quiet[2].y)          // the crest rises
        #expect(loud[3].y > quiet[3].y)          // the trough deepens
    }

    @Test("silence is the mark exactly as it is drawn everywhere else") func restIsCanonical() {
        #expect(RawiMark.svgPoints(level: 0) == RawiMark.svgPoints)
    }

    @Test("the ends stay put, so the glyph keeps its silhouette") func endsFixed() {
        for level in [0.0, 0.4, 1.0] {
            let points = RawiMark.svgPoints(level: level)
            #expect(points.first == RawiMark.svgPoints.first)
            #expect(points.last == RawiMark.svgPoints.last)
        }
    }

    @Test("a level outside the meter cannot deform the mark") func clamped() {
        #expect(RawiMark.svgPoints(level: 9) == RawiMark.svgPoints(level: 1))
        #expect(RawiMark.svgPoints(level: -3) == RawiMark.svgPoints(level: 0))
    }

    @Test("the peaks never leave the box the icon is drawn in") func staysInBounds() {
        for level in stride(from: 0.0, through: 1.0, by: 0.1) {
            for point in RawiMark.svgPoints(level: level) {
                #expect(point.y >= 1 && point.y <= 23)
            }
        }
    }

    @Test("a loud frame draws a different icon than a quiet one") func imagesDiffer() {
        func png(_ image: NSImage) -> Data? {
            image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:))?
                .representation(using: .png, properties: [:])
        }
        let quiet = RawiMark.image(tint: .red, level: 0.05)
        let loud = RawiMark.image(tint: .red, level: 0.9)
        #expect(png(quiet) != png(loud))
    }

    @Test("only recording listens to the level") func onlyWhileRecording() {
        func png(_ image: NSImage) -> Data? {
            image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:))?
                .representation(using: .png, properties: [:])
        }
        // An idle icon that twitched with room noise would be a distraction, not
        // feedback.
        let idleQuiet = RawiMark.statusImage(state: .idle, enabled: true,
                                             microphoneGranted: true, level: 0)
        let idleLoud = RawiMark.statusImage(state: .idle, enabled: true,
                                            microphoneGranted: true, level: 0.9)
        #expect(png(idleQuiet) == png(idleLoud))

        let recording = DictationState.recording(mode: .pushToTalk, startedAt: .now)
        let liveQuiet = RawiMark.statusImage(state: recording, enabled: true,
                                             microphoneGranted: true, level: 0)
        let liveLoud = RawiMark.statusImage(state: recording, enabled: true,
                                            microphoneGranted: true, level: 0.9)
        #expect(png(liveQuiet) != png(liveLoud))
    }
}
