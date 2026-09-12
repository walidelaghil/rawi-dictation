import AppKit
import SwiftUI

/// A panel that must never take focus. If it did, the synthesized ⌘V would land in
/// this app instead of the one being dictated into.
private final class NonActivatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
public final class PillWindow {
    private let model = PillModel()
    private var panel: NSPanel?
    private var proximity = PillProximity()
    private var cursorTimer: Timer?

    public init() {}

    public func show(state: DictationState, level: Double,
                     elapsed: Duration, remaining: Duration?, pasteHint: Bool = false) {
        update(state: state, level: level, elapsed: elapsed, remaining: remaining,
               pasteHint: pasteHint)
        let panel = panel ?? makePanel()
        self.panel = panel
        reposition(panel)
        panel.orderFrontRegardless()
        startCursorTracking()
    }

    public func update(state: DictationState, level: Double,
                       elapsed: Duration, remaining: Duration?, pasteHint: Bool = false) {
        model.pasteHint = pasteHint
        model.state = state
        model.level = level
        model.elapsed = elapsed
        model.remaining = remaining
    }

    public func hide() {
        stopCursorTracking()
        proximity.reset()
        model.armed = false
        panel?.ignoresMouseEvents = true
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let hosting = NSHostingView(rootView: PillView(model: model))
        let panel = NonActivatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 40),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)

        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // Click-through by default: this is what stops the pill eating a click
        // aimed at the app behind it. Flipped only once the cursor rests on it.
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        // Always dark, whatever the app appearance — see RawiColors.pill.
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.contentView = hosting
        panel.setContentSize(hosting.fittingSize)
        return panel
    }

    /// Polls the cursor. `NSEvent.mouseLocation` is unprivileged — it needs none of
    /// the permissions this Mac cannot grant, which is the whole reason the pill
    /// can be click-through *and* interactive.
    private func startCursorTracking() {
        guard cursorTimer == nil else { return }
        cursorTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { _ in
            MainActor.assumeIsolated { self.trackCursor() }
        }
    }

    private func stopCursorTracking() {
        cursorTimer?.invalidate()
        cursorTimer = nil
    }

    private func trackCursor() {
        guard let panel, panel.isVisible else { return }
        let armed = proximity.update(cursor: NSEvent.mouseLocation,
                                     frame: panel.frame,
                                     now: .now)
        guard armed != model.armed else { return }
        model.armed = armed
        panel.ignoresMouseEvents = !armed
    }

    /// Bottom-centre of whichever screen holds the cursor, 120 pt up.
    private func reposition(_ panel: NSPanel) {
        panel.setContentSize(panel.contentView?.fittingSize ?? NSSize(width: 340, height: 40))
        let screen = NSScreen.screens.first {
            NSMouseInRect(NSEvent.mouseLocation, $0.frame, false)
        } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.minY + 120))
    }
}
