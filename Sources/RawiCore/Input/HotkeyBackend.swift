import Foundation

/// A source of hotkey press/release events. Two implementations exist because the
/// permission each needs is different, and on a managed Mac the user may not be
/// able to grant the better one.
public protocol HotkeyBackend: AnyObject {
    func start() throws
    func stop()
    var isRunning: Bool { get }
    /// Shown in the menu bar and the doctor so it is obvious which is in use.
    var describeBackend: String { get }
}

public enum HotkeyBackendKind: String, Codable, Sendable, CaseIterable {
    /// CGEventTap. Needs Input Monitoring. Supports a bare `fn` and passive Esc.
    case eventTap
    /// Carbon RegisterEventHotKey. Needs **no permission at all**, but can only bind
    /// a modifier+key combination, and the combination is consumed.
    case carbon
    /// Event tap if Input Monitoring is granted, Carbon otherwise.
    case auto

    public func resolved(inputMonitoringGranted: Bool) -> HotkeyBackendKind {
        guard self == .auto else { return self }
        return inputMonitoringGranted ? .eventTap : .carbon
    }
}
