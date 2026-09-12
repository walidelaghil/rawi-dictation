import Foundation

/// How output should be shaped for a particular place it lands.
///
/// Rules change **structure, register and punctuation**. They never add facts —
/// `CleanupGuard` still runs afterwards, and a destination rule is not an
/// exemption from it.
public struct DestinationRule: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public var name: String
    /// Empty means any app.
    public var bundleIDs: [String]
    /// Glob against the browser's active tab URL. Nil means any page.
    public var urlPattern: String?
    public var instruction: String
    public var enabled: Bool
    public var isBuiltIn: Bool

    public init(id: UUID = UUID(), name: String, bundleIDs: [String] = [],
                urlPattern: String? = nil, instruction: String,
                enabled: Bool = true, isBuiltIn: Bool = false) {
        self.id = id
        self.name = name
        self.bundleIDs = bundleIDs
        self.urlPattern = urlPattern
        self.instruction = instruction
        self.enabled = enabled
        self.isBuiltIn = isBuiltIn
    }

    /// How specific this rule is. Used to pick a winner, not shown to the user.
    public var specificity: Int {
        var score = 0
        if !bundleIDs.isEmpty { score += 10 }
        if let pattern = urlPattern { score += 100 + pattern.count }
        return score
    }

    /// What the user sees in the rule list.
    public var matchDescription: String {
        if let pattern = urlPattern { return pattern }
        if bundleIDs.isEmpty { return "any app" }
        return bundleIDs.map { $0.components(separatedBy: ".").last ?? $0 }
            .joined(separator: " · ")
    }
}

public enum Browsers {
    /// Brave first: it is the browser actually in use here.
    public static let bundleIDs = ["com.brave.Browser", "com.google.Chrome",
                                   "com.apple.Safari", "company.thebrowser.Browser",
                                   "com.microsoft.edgemac"]
}

public final class DestinationStore: @unchecked Sendable {
    private let url: URL
    private let lock = NSLock()
    private var stored: [DestinationRule] = []

    public static var defaultURL: URL {
        Config.supportDirectory.appendingPathComponent("destinations.json")
    }

    public init(url: URL = DestinationStore.defaultURL) {
        self.url = url
        load()
    }

    public var rules: [DestinationRule] { lock.withLock { stored } }

    public func add(_ rule: DestinationRule) {
        lock.withLock { stored.append(rule); save() }
    }

    /// Built-in rules can be disabled but not deleted — deleting one leaves no
    /// way to get it back, and "off" is what the user actually wants.
    public func remove(_ id: UUID) {
        lock.withLock {
            guard let index = stored.firstIndex(where: { $0.id == id }),
                  !stored[index].isBuiltIn else { return }
            stored.remove(at: index)
            save()
        }
    }

    public func setEnabled(_ id: UUID, _ enabled: Bool) {
        lock.withLock {
            guard let index = stored.firstIndex(where: { $0.id == id }) else { return }
            stored[index].enabled = enabled
            save()
        }
    }

    public static var defaults: [DestinationRule] {
        [
            DestinationRule(
                name: "Jira ticket", bundleIDs: Browsers.bundleIDs,
                urlPattern: "*/browse/*",
                instruction: "Shape this as a ticket: a one-line summary first, then any steps "
                           + "or criteria as short list items. Keep every detail that was spoken.",
                isBuiltIn: true),
            DestinationRule(
                name: "Google Docs", bundleIDs: Browsers.bundleIDs,
                urlPattern: "*docs.google.com/document*",
                instruction: "Full prose with complete sentences. No chat shorthand.",
                isBuiltIn: true),
            DestinationRule(
                name: "Slack · direct message", bundleIDs: Browsers.bundleIDs,
                urlPattern: "*app.slack.com/client/*/D*",
                instruction: "Keep it brief and conversational. No greeting, no sign-off.",
                isBuiltIn: true),
            DestinationRule(
                name: "Slack", bundleIDs: ["com.tinyspeck.slackmacgap"] + Browsers.bundleIDs,
                urlPattern: "*app.slack.com/client/*",
                instruction: "One short paragraph. Keep contractions. No greeting, no sign-off.",
                isBuiltIn: true),
            DestinationRule(
                name: "Commit message",
                bundleIDs: ["com.apple.Terminal", "com.googlecode.iterm2",
                            "com.apple.dt.Xcode", "dev.warp.Warp-Stable"],
                instruction: "Imperative mood. A short summary on the first line, then the "
                           + "detail on following lines. Preserve identifiers exactly.",
                isBuiltIn: true),
            DestinationRule(
                name: "Mail",
                bundleIDs: ["com.apple.mail", "com.microsoft.Outlook", "com.readdle.smartemail-Mac"],
                instruction: "Complete sentences and full punctuation. Expand contractions.",
                isBuiltIn: true),
        ]
    }

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([DestinationRule].self, from: data),
              !decoded.isEmpty else {
            stored = Self.defaults
            save()
            return
        }
        stored = decoded
    }

    /// Caller holds the lock.
    private func save() {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try? encoder.encode(stored).write(to: url, options: .atomic)
    }
}
