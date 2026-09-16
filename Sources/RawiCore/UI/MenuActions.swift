import Foundation

/// One row in the menu's action strip: an icon and its shortcut, side by side.
public struct MenuAction: Identifiable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let shortcut: String
    public let symbol: String

    public init(id: String, title: String, shortcut: String, symbol: String) {
        self.id = id
        self.title = title
        self.shortcut = shortcut
        self.symbol = symbol
    }
}

public enum MenuActions {
    /// Two, not three. Commands is designed but deferred — see docs/BACKLOG.md.
    /// Adding a third here is also the point at which the hover-only labels stop
    /// being defensible and need to come back on screen.
    public static func all(_ labels: HotkeyLabels) -> [MenuAction] {
        [
            MenuAction(id: "dictate", title: "Dictate",
                       shortcut: labels.dictate, symbol: "mic"),
            MenuAction(id: "transform", title: "Transform clipboard",
                       shortcut: labels.transform, symbol: "wand.and.sparkles"),
        ]
    }
}

/// A dictation recent enough to still be worth re-copying.
///
/// Held in memory only. Phase 3 replaces this with the persisted, searchable
/// history — this exists so the menu's Recent section is real rather than a
/// placeholder waiting on it.
public struct RecentDictation: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let text: String
    public let script: Script
    public let at: Date
    /// A rewrite rather than something you said. Marked because the list is the
    /// one place both appear, and "EN" against text you never spoke is a lie.
    public let isTransform: Bool

    public init(id: UUID = UUID(), text: String, script: Script, at: Date = Date(),
                isTransform: Bool = false) {
        self.id = id
        self.text = text
        self.script = script
        self.at = at
        self.isTransform = isTransform
    }

    /// What sits in the badge column: the script for a dictation, and for a
    /// transform the fact that it is one.
    public var badge: String { isTransform ? "TR" : (script == .arabic ? "AR" : "EN") }

    public var timestamp: String {
        let f = DateFormatter()
        f.dateFormat = "H:mm"
        return f.string(from: at)
    }

    /// One line, whatever the transcript did.
    public var oneLine: String {
        text.split(whereSeparator: \.isNewline).joined(separator: " ")
    }
}
