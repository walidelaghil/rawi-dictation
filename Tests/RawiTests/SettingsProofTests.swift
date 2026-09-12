import Testing
import AppKit
import SwiftUI
@testable import RawiCore

/// Renders the settings screen to look at. A development aid, not an assertion.
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
