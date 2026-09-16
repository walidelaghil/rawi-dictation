import AppKit
import SwiftUI
import Testing
@testable import RawiCore

@Suite("PillLabel") struct PillLabelTests {
    let t0 = ContinuousClock.now

    @Test("labels name the mode and stage") func labels() {
        // "Listening" per the approved design — it reads as the app's state rather
        // than as a recorder's, which matters when it sits over someone's document.
        #expect(PillLabel.text(for: .recording(mode: .pushToTalk, startedAt: t0)) == "Listening")
        #expect(PillLabel.text(for: .recording(mode: .handsFree, startedAt: t0)) == "Hands-free")
        #expect(PillLabel.text(for: .transcribing) == "Transcribing…")
        #expect(PillLabel.text(for: .cleaning) == "Writing…")
        #expect(PillLabel.text(for: .inserting) == "Inserting…")
        #expect(PillLabel.text(for: .error("no mic")) == "no mic")
    }

    @Test("state maps to the colour contract the design rests on") func tokens() {
        #expect(PillLabel.token(for: .recording(mode: .pushToTalk, startedAt: t0)) == .saffron)
        #expect(PillLabel.token(for: .recording(mode: .handsFree, startedAt: t0)) == .saffron)
        #expect(PillLabel.token(for: .transcribing) == .lapis)
        #expect(PillLabel.token(for: .cleaning) == .lapis)
        #expect(PillLabel.token(for: .error("x")) == .clay)
        #expect(PillLabel.token(for: .idle) == .verdigris)
    }

    @Test("countdown appears only under a minute") func countdown() {
        #expect(PillLabel.countdown(.seconds(90)) == nil)
        #expect(PillLabel.countdown(.seconds(60)) == nil)
        #expect(PillLabel.countdown(.seconds(59)) == "0:59")
        #expect(PillLabel.countdown(.seconds(5)) == "0:05")
        #expect(PillLabel.countdown(.seconds(0)) == "0:00")
    }

    @Test("a negative remaining clamps to zero rather than showing a minus") func negative() {
        #expect(PillLabel.countdown(.seconds(-3)) == "0:00")
    }

    @Test("elapsed formats as minutes and seconds") func elapsed() {
        #expect(PillLabel.elapsed(.seconds(0)) == "0:00")
        #expect(PillLabel.elapsed(.seconds(7)) == "0:07")
        #expect(PillLabel.elapsed(.seconds(75)) == "1:15")
        #expect(PillLabel.elapsed(.seconds(600)) == "10:00")
    }
}

@Suite("Language picker proof") @MainActor struct LanguagePickerProofTests {
    @Test("picker proof",
          .enabled(if: ProcessInfo.processInfo.environment["RAWI_PROOF_LANG"] != nil))
    func proof() throws {
        let out = URL(fileURLWithPath: ProcessInfo.processInfo.environment["RAWI_PROOF_LANG"]!)
        let labels = HotkeyLabels(dictate: "⌥", transform: "⌥⌘Space",
                                  cancel: "⌥esc", command: "⌃⌥C")
        // Every state the pill can be in while a language is chosen: hovered, so
        // the picker is open; and not hovered, where only a forced choice shows.
        let cases: [(DictationLanguage, Bool)] = [
            (.auto, true), (.arabic, true), (.english, true),
            (.arabic, false), (.auto, false),
        ]
        var shots: [NSBitmapImageRep] = []
        for (language, armed) in cases {
            let model = PillModel()
            model.state = .recording(mode: .pushToTalk, startedAt: .now)
            model.level = 0.03
            model.peak = 0.06
            model.elapsed = .seconds(4)
            model.labels = labels
            model.language = language
            model.armed = armed
            let host = NSHostingView(rootView: PillView(model: model).padding(16))
            host.frame = NSRect(x: 0, y: 0, width: 560, height: 78)
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.12))
            host.layoutSubtreeIfNeeded()
            let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: rep)
            shots.append(rep)
        }
        let sheet = NSImage(size: NSSize(width: 560, height: 78 * CGFloat(shots.count)))
        sheet.lockFocus()
        for (index, rep) in shots.enumerated() {
            rep.draw(in: NSRect(x: 0, y: CGFloat(shots.count - 1 - index) * 78,
                                width: 560, height: 78))
        }
        sheet.unlockFocus()
        let png = NSBitmapImageRep(data: sheet.tiffRepresentation!)!
            .representation(using: .png, properties: [:])!
        try png.write(to: out)
    }
}
