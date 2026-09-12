import Testing
import AppKit
import SwiftUI
@testable import RawiCore

/// Renders screens to look at. A development aid, not an assertion.
@MainActor
@Suite("Settings proof") struct SettingsProofTests {
    @Test("settings proof",
          .enabled(if: ProcessInfo.processInfo.environment["RAWI_PROOF"] != nil))
    func proof() throws {
        let out = URL(fileURLWithPath: ProcessInfo.processInfo.environment["RAWI_PROOF"]!)
        var images: [NSImage] = []
        for appearance in [ResolvedAppearance.dark, .light] {
            let model = scratchSettings()
            model.appearance = appearance
            let view = NSHostingView(rootView: SettingsView(model: model))
            view.frame = NSRect(x: 0, y: 0, width: 700, height: 940)
            view.layoutSubtreeIfNeeded()
            // After the first layout, so onAppear's reload from disk cannot
            // overwrite the state being rendered.
            model.config.hotkey = "option+space"
            model.config.cleanup.provider = .ollama
            model.config.cleanup.models = CleanupModels(latin: "qwen2.5:1.5b",
                                                        arabic: "qwen2.5:3b")
            model.installedOllama = ["qwen2.5:1.5b", "qwen2.5:3b", "gemma3:4b"]
            model.ollamaReachable = true
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
            view.layoutSubtreeIfNeeded()
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            let image = NSImage(size: view.bounds.size)
            image.addRepresentation(rep)
            images.append(image)
        }
        let gap: CGFloat = 14
        let width = images.reduce(0) { $0 + $1.size.width + gap } + gap
        let height = (images.map(\.size.height).max() ?? 0) + gap * 2
        let sheet = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            NSColor(white: 0.45, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: width, height: height).fill()
            var x = gap
            for image in images {
                image.draw(at: NSPoint(x: x, y: gap), from: .zero,
                           operation: .sourceOver, fraction: 1)
                x += image.size.width + gap
            }
            return true
        }
        try NSBitmapImageRep(data: sheet.tiffRepresentation!)!
            .representation(using: .png, properties: [:])!.write(to: out)
    }
}


@MainActor
@Suite("Screens proof") struct ScreensProofTests {
    func shot<V: View>(_ view: V, width: CGFloat, height: CGFloat) -> NSImage {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        host.layoutSubtreeIfNeeded()
        let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: rep)
        let image = NSImage(size: host.bounds.size)
        image.addRepresentation(rep)
        return image
    }

    func sheet(_ images: [NSImage], to out: URL) throws {
        let gap: CGFloat = 14
        let width = images.reduce(0) { $0 + $1.size.width + gap } + gap
        let height = (images.map(\.size.height).max() ?? 0) + gap * 2
        let sheet = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            NSColor(white: 0.45, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: width, height: height).fill()
            var x = gap
            for image in images {
                image.draw(at: NSPoint(x: x, y: gap), from: .zero,
                           operation: .sourceOver, fraction: 1)
                x += image.size.width + gap
            }
            return true
        }
        try NSBitmapImageRep(data: sheet.tiffRepresentation!)!
            .representation(using: .png, properties: [:])!.write(to: out)
    }

    @Test("screens proof",
          .enabled(if: ProcessInfo.processInfo.environment["RAWI_SCREENS"] != nil))
    func proof() throws {
        let out = URL(fileURLWithPath: ProcessInfo.processInfo.environment["RAWI_SCREENS"]!)
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())

        let history = HistoryStore(url: dir.appendingPathComponent("p-\(UUID()).jsonl"))
        let samples = [
            ("I also advise them that they have two focus areas right now", 26.0, "Claude"),
            ("نرسل التقرير الى سلة قبل يوم الاثنين", 9.0, "Brave"),
            ("Move the launch date back a week, the billing work is not done", 12.0, "Slack"),
            ("Can you review the migration before Thursday please", 8.0, "Slack"),
        ]
        for (index, sample) in samples.enumerated() {
            history.append(HistoryEntry(
                at: Date().addingTimeInterval(Double(-index) * 5000),
                cleaned: sample.0, raw: sample.0,
                script: sample.0.first!.isLetter && sample.0.first!.isASCII ? .latin : .arabic,
                appName: sample.2, bundleID: sample.2.lowercased(),
                durationSeconds: sample.1, peakLevel: 0.3, guardRejected: false))
        }

        let vocabulary = VocabularyStore(url: dir.appendingPathComponent("pv-\(UUID()).json"))
        _ = vocabulary.syncLearned([
            LearnedTerm(term: "Salla", occurrences: 11, days: 6),
            LearnedTerm(term: "Kandji", occurrences: 6, days: 3),
            LearnedTerm(term: "Elaghil", occurrences: 5, days: 4),
        ])
        _ = vocabulary.addTerm("Wispr", note: "")

        var images: [NSImage] = []
        for appearance in [ResolvedAppearance.dark, .light] {
            let vm = VocabularyViewModel(store: vocabulary, history: history)
            vm.appearance = appearance
            images.append(shot(DictionaryScreen(model: vm), width: 620, height: 520))

            let insights = InsightsViewModel(store: history)
            insights.appearance = appearance
            images.append(shot(InsightsView(model: insights), width: 620, height: 760))
        }
        try sheet(images, to: out)
    }
}
