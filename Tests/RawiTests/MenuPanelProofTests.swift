import Testing
import AppKit
import SwiftUI
@testable import RawiCore

/// Renders the menu panel to a PNG to look at. Gated on an environment variable:
/// it is a development aid, not an assertion.
@MainActor
@Suite("Menu panel proof") struct MenuPanelProofTests {
    @Test("panel proof",
          .enabled(if: ProcessInfo.processInfo.environment["RAWI_PROOF"] != nil))
    func proof() throws {
        let out = URL(fileURLWithPath: ProcessInfo.processInfo.environment["RAWI_PROOF"]!)
        var images: [NSImage] = []

        for (appearance, open) in [(ResolvedAppearance.dark, false), (.dark, true),
                                   (.light, true)] {
            let model = MenuPanelModel()
            model.appearance = appearance
            model.recentOpen = open
            model.recent = [
                RecentDictation(text: "I also advise them that they have two focus areas",
                                script: .latin),
                RecentDictation(text: "هذا اختبار للغة العربية", script: .arabic),
                RecentDictation(text: "They are testing the model they are working on",
                                script: .latin),
                RecentDictation(text: "Ship Monday. Deck by Friday.", script: .latin,
                                isTransform: true),
            ]
            let view = NSHostingView(rootView: MenuPanelView(model: model))
            view.frame = NSRect(origin: .zero, size: view.fittingSize)
            view.layoutSubtreeIfNeeded()
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            let image = NSImage(size: view.bounds.size)
            image.addRepresentation(rep)
            images.append(image)
        }

        let gap: CGFloat = 16
        let width = images.reduce(0) { $0 + $1.size.width + gap } + gap
        let height = (images.map(\.size.height).max() ?? 0) + gap * 2
        let sheet = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            NSColor(white: 0.45, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: width, height: height).fill()
            var x = gap
            for image in images {
                image.draw(at: NSPoint(x: x, y: height - gap - image.size.height),
                           from: .zero, operation: .sourceOver, fraction: 1)
                x += image.size.width + gap
            }
            return true
        }
        let png = NSBitmapImageRep(data: sheet.tiffRepresentation!)!
            .representation(using: .png, properties: [:])!
        try png.write(to: out)
    }
}
