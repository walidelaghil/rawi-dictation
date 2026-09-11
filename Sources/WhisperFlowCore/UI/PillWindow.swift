import AppKit
import SwiftUI

/// A panel that must never take focus. If it did, the synthesized Cmd-V would land
/// in this app instead of the one being dictated into, so `canBecomeKey` is false
/// and the style mask includes `.nonactivatingPanel`.
private final class NonActivatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
public final class PillWindow {
    private let model = PillModel()
    private var panel: NSPanel?

    public init() {}

    public func show(state: DictationState, level: Double,
                     elapsed: Duration, remaining: Duration?) {
        update(state: state, level: level, elapsed: elapsed, remaining: remaining)
        let panel = panel ?? makePanel()
        self.panel = panel
        reposition(panel)
        panel.orderFrontRegardless()
    }

    public func update(state: DictationState, level: Double,
                       elapsed: Duration, remaining: Duration?) {
        model.state = state
        model.level = level
        model.elapsed = elapsed
        model.remaining = remaining
    }

    public func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let hosting = NSHostingView(rootView: PillView(model: model))
        hosting.translatesAutoresizingMaskIntoConstraints = false

        let panel = NonActivatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 40),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)

        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false                 // SwiftUI draws its own
        panel.ignoresMouseEvents = true
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = hosting
        panel.setContentSize(hosting.fittingSize)
        return panel
    }

    /// Bottom-centre of whichever screen holds the mouse, 120 pt up.
    private func reposition(_ panel: NSPanel) {
        panel.setContentSize(panel.contentView?.fittingSize ?? NSSize(width: 320, height: 40))
        let screen = NSScreen.screens.first {
            NSMouseInRect(NSEvent.mouseLocation, $0.frame, false)
        } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(
            x: frame.midX - size.width / 2,
            y: frame.minY + 120))
    }
}
