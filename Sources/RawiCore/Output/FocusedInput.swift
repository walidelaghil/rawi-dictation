import AppKit
import ApplicationServices

/// Whether there is somewhere for a dictation to go.
public enum FocusedInput: String, Equatable, Sendable {
    /// A text field, text area, search box or editable web element has focus.
    case editable
    /// Focus is somewhere that does not take typing: a file list, a canvas, the
    /// desktop. A synthetic ⌘V there does nothing at best, and at worst does
    /// something else entirely (pastes a layer, a file).
    case notEditable
    /// The app would not say. Treated as editable: an app that cannot be asked is
    /// usually one with its own text view, and pasting into it is the behaviour
    /// people had before this check existed.
    case unknown
}

public protocol FocusProbing: AnyObject, Sendable {
    /// Called at key-press, while you are still speaking.
    func prepare()
    /// Called at the moment of insertion.
    func probe() -> FocusedInput
    /// What the last probe saw, for the log.
    var lastSeen: String { get }
}

/// Never knows, so always pastes: the behaviour before focus was checked.
///
/// The controller's default, so nothing that builds one — every test included —
/// silently starts asking the real frontmost app on whatever Mac it runs on. The
/// app opts in to the real probe explicitly.
public final class NoFocusProbe: FocusProbing, @unchecked Sendable {
    public init() {}
    public func prepare() {}
    public func probe() -> FocusedInput { .unknown }
    public var lastSeen: String { "not checked" }
}

/// Asks the Accessibility API what has keyboard focus in the frontmost app.
///
/// Chromium browsers and Electron apps (Brave, Chrome, Slack, Notion, VS Code)
/// build their accessibility tree only when something asks for it, and until then
/// a focused web input looks like no input at all. `prepare` asks for it at
/// key-press, via `AXManualAccessibility`, so the tree has the length of your
/// sentence to build rather than having to be waited for at paste time.
///
/// `AXEnhancedUserInterface` would also switch it on, and is deliberately not
/// used: it is known to break window managers — Moom is installed here — by making
/// Chromium animate every programmatic resize.
public final class SystemFocusProbe: FocusProbing, @unchecked Sendable {
    /// Roles that take typing everywhere macOS draws them.
    static let textRoles: Set<String> = [
        kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole, "AXSearchField",
    ]

    /// A slow app must not stall the paste. A quarter of a second is past what any
    /// responsive app needs and short enough not to be felt.
    static let messagingTimeout: Float = 0.25

    private let lock = NSLock()
    private var prepared: Set<pid_t> = []
    private var seen = "nothing yet"
    public var lastSeen: String { lock.withLock { seen } }
    private func note(_ text: String) { lock.withLock { seen = text } }

    public init() {}

    public func prepare() {
        prepare(pid: NSWorkspace.shared.frontmostApplication?.processIdentifier)
    }

    func prepare(pid: pid_t?) {
        guard AXIsProcessTrusted(), let pid else { return }
        let fresh = lock.withLock { prepared.insert(pid).inserted }
        guard fresh else { return }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, Self.messagingTimeout)
        // Ignored by every app that is not Chromium or Electron, which is the point.
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    public func probe() -> FocusedInput {
        guard AXIsProcessTrusted(),
              let front = NSWorkspace.shared.frontmostApplication else {
            note("no Accessibility, or no frontmost app")
            return .unknown
        }
        let pid = front.processIdentifier
        let appName = front.localizedName ?? front.bundleIdentifier ?? "?"
        prepare(pid: pid)
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, Self.messagingTimeout)

        var focusedRef: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString,
                                                   &focusedRef)
        switch status {
        case .success:
            break
        case .noValue, .attributeUnsupported:
            // The app answered, and nothing in it has focus.
            note("\(appName): nothing focused")
            return .notEditable
        default:
            // Timed out, or the app does not speak Accessibility at all.
            note("\(appName): no answer (AXError \(status.rawValue))")
            return .unknown
        }
        guard let focusedRef, CFGetTypeID(focusedRef) == AXUIElementGetTypeID() else {
            note("\(appName): focus is not an element")
            return .unknown
        }
        let focused = focusedRef as! AXUIElement
        let role = Self.string(focused, kAXRoleAttribute)
        let settable = Self.settable(focused, kAXValueAttribute)
        let selection = Self.has(focused, kAXSelectedTextRangeAttribute)
        let verdict = Self.classify(role: role, valueSettable: settable,
                                    hasSelectedRange: selection)
        note("\(appName): \(role ?? "no role"), value settable \(settable), "
             + "selection \(selection) → \(verdict.rawValue)")
        return verdict
    }

    /// The decision, apart from the API calls, so it can be tested.
    ///
    /// A known text role is enough. Anything else counts only if it behaves like
    /// text: a value you can set *and* a text selection. Either alone is not —
    /// sliders have settable values, and read-only web text has a selection.
    static func classify(role: String?, valueSettable: Bool,
                         hasSelectedRange: Bool) -> FocusedInput {
        if let role, textRoles.contains(role) { return .editable }
        if valueSettable && hasSelectedRange { return .editable }
        return role == nil ? .unknown : .notEditable
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success
        else { return nil }
        return ref as? String
    }

    private static func settable(_ element: AXUIElement, _ attribute: String) -> Bool {
        var result: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(element, attribute as CFString, &result) == .success
        else { return false }
        return result.boolValue
    }

    private static func has(_ element: AXUIElement, _ attribute: String) -> Bool {
        var ref: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success
    }
}
