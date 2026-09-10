import AVFoundation
import AppKit
import ApplicationServices
import IOKit.hid

public struct PermissionStatus: Equatable, Sendable {
    public let accessibility: Bool
    public let inputMonitoring: Bool
    public let microphone: Bool

    public init(accessibility: Bool, inputMonitoring: Bool, microphone: Bool) {
        self.accessibility = accessibility
        self.inputMonitoring = inputMonitoring
        self.microphone = microphone
    }

    public var allGranted: Bool { accessibility && inputMonitoring && microphone }

    /// Ordered the way the README asks the user to grant them.
    public var missing: [String] {
        var result: [String] = []
        if !accessibility { result.append("Accessibility") }
        if !inputMonitoring { result.append("Input Monitoring") }
        if !microphone { result.append("Microphone") }
        return result
    }
}

public enum Permissions {
    public enum SettingsPane: String, Sendable, CaseIterable {
        case accessibility, inputMonitoring, microphone

        var anchor: String {
            switch self {
            case .accessibility: "Privacy_Accessibility"
            case .inputMonitoring: "Privacy_ListenEvent"
            case .microphone: "Privacy_Microphone"
            }
        }

        public var title: String {
            switch self {
            case .accessibility: "Accessibility"
            case .inputMonitoring: "Input Monitoring"
            case .microphone: "Microphone"
            }
        }

        /// Why the app needs it, and what breaks without it.
        public var rationale: String {
            switch self {
            case .accessibility:
                "needed to paste at the cursor; without it text is only copied"
            case .inputMonitoring:
                "needed to watch the hotkey; without it the hotkey does nothing"
            case .microphone:
                "needed to record your voice"
            }
        }
    }

    public static func current() -> PermissionStatus {
        PermissionStatus(
            accessibility: AXIsProcessTrusted(),
            inputMonitoring: IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
                == kIOHIDAccessTypeGranted,
            microphone: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized)
    }

    public static func settingsURL(for pane: SettingsPane) -> URL {
        URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane.anchor)")!
    }

    @MainActor
    public static func openSettings(for pane: SettingsPane) {
        NSWorkspace.shared.open(settingsURL(for: pane))
    }

    /// Shows the system Accessibility prompt. Input Monitoring has no equivalent
    /// prompt — it must be added by hand — which is why the README says so.
    public static func requestAccessibilityPrompt() {
        // The `kAXTrustedCheckOptionPrompt` global is not concurrency-safe to
        // reference, so its documented string value is used directly.
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    public static func requestMicrophone() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    /// Asks the system for Input Monitoring. Returns the resulting grant, which is
    /// usually still false — macOS only reveals the pane, it does not grant inline.
    public static func requestInputMonitoring() -> Bool {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }
}
