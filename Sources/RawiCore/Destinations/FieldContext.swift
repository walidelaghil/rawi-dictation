import AppKit
import ApplicationServices

/// The text field you are in, as far as a rule needs to know it.
///
/// Read through Accessibility at key-press: its label, placeholder, identifier and
/// whether it takes more than one line. Enough to tell Jira's Summary box from its
/// Description, or a mail subject from its body. The text inside the field is
/// never read here.
public struct FieldContext: Sendable, Equatable {
    /// What the field calls itself, most human first: label, placeholder,
    /// description, identifier.
    public let labels: [String]
    public let multiline: Bool

    public init(labels: [String], multiline: Bool) {
        self.labels = labels.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        self.multiline = multiline
    }

    /// Everything a pattern is matched against, lower-cased.
    public var signature: String { labels.joined(separator: " | ").lowercased() }

    /// The name a person would give it, for the rule editor and the log.
    public var name: String? { labels.first }

    /// Whether a rule's field pattern fits: any `|`-separated alternative found in
    /// the signature, ignoring case.
    public func matches(_ pattern: String) -> Bool {
        let alternatives = pattern.lowercased().split(separator: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return alternatives.contains { signature.contains($0) }
    }

    /// The focused field of the frontmost app, or nil without Accessibility or focus.
    public static func focused() -> FieldContext? {
        guard AXIsProcessTrusted(),
              let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &ref) == .success,
              let ref, CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
        let element = ref as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.25)

        func string(_ attribute: String) -> String? {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
            else { return nil }
            return value as? String
        }
        var labels: [String] = []
        // A visible label is often a separate element pointing at the field.
        var titleElement: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXTitleUIElementAttribute as CFString, &titleElement) == .success,
           let titleElement, CFGetTypeID(titleElement) == AXUIElementGetTypeID() {
            var title: CFTypeRef?
            AXUIElementCopyAttributeValue(titleElement as! AXUIElement, kAXValueAttribute as CFString, &title)
            if let title = title as? String { labels.append(title) }
        }
        for attribute in [kAXTitleAttribute, kAXDescriptionAttribute, kAXPlaceholderValueAttribute,
                          kAXHelpAttribute, "AXDOMIdentifier", kAXIdentifierAttribute] {
            if let value = string(attribute), !labels.contains(value) { labels.append(value) }
        }
        let role = string(kAXRoleAttribute)
        return FieldContext(labels: labels, multiline: role == kAXTextAreaRole || role == "AXWebArea")
    }
}
