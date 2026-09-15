import AppKit
import SwiftUI

/// A panel that must never take focus. If it did, the synthesized ⌘V would land in
/// this app instead of the one being dictated into.
private final class NonActivatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Takes the first click. A panel that never becomes key would otherwise spend
/// the click on "activating" and the × would need pressing twice.
private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
public final class PillWindow {
    private let model = PillModel()
    private var panel: NSPanel?
    private var proximity = PillProximity()
    private var cursorTimer: Timer?

    public init() {}

    public func show(state: DictationState, level: Double, peak: Double = 0,
                     elapsed: Duration, remaining: Duration?, pasteHint: Bool = false,
                     motion: MarkMotion = .rest) {
        update(state: state, level: level, peak: peak, elapsed: elapsed, remaining: remaining,
               pasteHint: pasteHint, motion: motion)
        let panel = panel ?? makePanel()
        self.panel = panel
        reposition(panel)
        panel.orderFrontRegardless()
        startCursorTracking()
    }

    public func update(state: DictationState, level: Double, peak: Double = 0,
                       elapsed: Duration, remaining: Duration?, pasteHint: Bool = false,
                       motion: MarkMotion = .rest) {
        model.motion = motion
        model.pasteHint = pasteHint
        model.state = state
        // A pill asking a question takes the mouse whether or not the cursor has
        // rested on it: the buttons are the answer, and waiting for proximity to
        // arm them would mean clicking into a pill that ignores clicks.
        if case .confirming = state {
            panel?.ignoresMouseEvents = false
            model.armed = true
        }
        model.level = level
        model.peak = peak
        model.elapsed = elapsed
        model.remaining = remaining
    }

    public func setLabels(_ labels: HotkeyLabels) { model.labels = labels }

    /// Says yes to a command waiting for confirmation.
    public var onConfirm: (() -> Void)? {
        get { model.onConfirm }
        set { model.onConfirm = newValue }
    }

    /// Called when the × is clicked.
    public var onCancel: (() -> Void)? {
        get { model.onCancel }
        set { model.onCancel = newValue }
    }

    public func hide() {
        stopCursorTracking()
        proximity.reset()
        model.armed = false
        panel?.ignoresMouseEvents = true
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let hosting = FirstClickHostingView(rootView: PillView(model: model))
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
        // While it is asking, it stays clickable.
        if case .confirming = model.state { return }
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
