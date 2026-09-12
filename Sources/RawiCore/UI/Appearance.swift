import AppKit

/// The concrete appearance to paint — what `system` becomes once the OS has been asked.
public enum ResolvedAppearance: String, Sendable, CaseIterable {
    case dark, light
}

public enum Appearance: String, Codable, Sendable, CaseIterable, Equatable {
    case system, dark, light

    public var displayName: String {
        switch self {
        case .system: "Match System"
        case .dark: "Dark"
        case .light: "Light"
        }
    }

    public func resolved(systemIsDark: Bool) -> ResolvedAppearance {
        switch self {
        case .system: systemIsDark ? .dark : .light
        case .dark: .dark
        case .light: .light
        }
    }

    /// `nil` for `system`, which is what AppKit expects for "inherit" — assigning a
    /// concrete appearance there would pin the app and stop it following the OS.
    public var nsAppearanceName: NSAppearance.Name? {
        switch self {
        case .system: nil
        case .dark: .darkAqua
        case .light: .aqua
        }
    }

    /// Whether the OS is currently in dark mode.
    @MainActor public static var systemIsDark: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
}
