import AppKit
import CoreGraphics

public protocol TextInserting: AnyObject, Sendable {
    /// Returns false when Accessibility is not granted. The text is still placed on
    /// the clipboard, so the caller can tell the user to paste it by hand.
    func insert(_ text: String, restoringClipboard: Bool) -> Bool
}

/// Places text on the pasteboard and synthesizes Cmd-V into the focused app.
///
/// Clipboard restore is inherently racy: `restoreDelay` is a guess at how long the
/// target app takes to read the pasteboard, and a slow app can lose the paste.
/// That is why `output.restorePreviousClipboard` defaults to false.
public final class TextInserter: TextInserting, @unchecked Sendable {
    private let restoreDelay: Duration
    private let virtualKeyV: CGKeyCode = 9      // kVK_ANSI_V

    public init(restoreDelay: Duration = .milliseconds(300)) {
        self.restoreDelay = restoreDelay
    }

    public func insert(_ text: String, restoringClipboard: Bool) -> Bool {
        let pasteboard = NSPasteboard.general
        let stash = restoringClipboard ? PasteboardStash.capture(pasteboard) : nil

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        guard AXIsProcessTrusted() else { return false }
        guard postCommandV() else { return false }

        if let stash {
            let delay = Double(restoreDelay.components.seconds)
                + Double(restoreDelay.components.attoseconds) / 1e18
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                stash.restore(to: pasteboard)
            }
        }
        return true
    }

    private func postCommandV() -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return false }
        guard let down = CGEvent(keyboardEventSource: source,
                                 virtualKey: virtualKeyV, keyDown: true),
              let up = CGEvent(keyboardEventSource: source,
                               virtualKey: virtualKeyV, keyDown: false) else { return false }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }
}
