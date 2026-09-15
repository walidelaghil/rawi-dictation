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
    /// Words that identify the field, matched against its label, placeholder and
    /// identifier; `|` separates alternatives. Nil means any field.
    public var fieldPattern: String?
    public var instruction: String
    public var enabled: Bool
    public var isBuiltIn: Bool

    public init(id: UUID = UUID(), name: String, bundleIDs: [String] = [],
                urlPattern: String? = nil, fieldPattern: String? = nil, instruction: String,
                enabled: Bool = true, isBuiltIn: Bool = false) {
        self.id = id
        self.name = name
        self.bundleIDs = bundleIDs
        self.urlPattern = urlPattern
        self.fieldPattern = fieldPattern
        self.instruction = instruction
        self.enabled = enabled
        self.isBuiltIn = isBuiltIn
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, bundleIDs, urlPattern, fieldPattern, instruction, enabled, isBuiltIn
    }

    /// Tolerant: a rules file written before field patterns existed must still load.
    /// The store falls back to its defaults when decoding fails, so a strict decoder
    /// here would have replaced every rule you wrote with the built-ins.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        bundleIDs = try c.decodeIfPresent([String].self, forKey: .bundleIDs) ?? []
        urlPattern = try c.decodeIfPresent(String.self, forKey: .urlPattern)
        fieldPattern = try c.decodeIfPresent(String.self, forKey: .fieldPattern)
        instruction = try c.decode(String.self, forKey: .instruction)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        isBuiltIn = try c.decodeIfPresent(Bool.self, forKey: .isBuiltIn) ?? false
    }

    /// How specific this rule is. Used to pick a winner, not shown to the user.
    /// A field beats a page, a page beats an app: the narrower the place, the more
    /// the rule knows about what belongs there.
    public var specificity: Int {
        var score = 0
        if !bundleIDs.isEmpty { score += 10 }
        if let pattern = urlPattern { score += 100 + pattern.count }
        if let field = fieldPattern, !field.isEmpty { score += 1_000 + field.count }
        return score
    }

    /// What the user sees in the rule list.
    public var matchDescription: String {
        var place: String
        if let pattern = urlPattern { place = pattern }
        else if bundleIDs.isEmpty { place = "any app" }
        else {
            place = bundleIDs.map { $0.components(separatedBy: ".").last ?? $0 }
                .joined(separator: " · ")
        }
        if let field = fieldPattern, !field.isEmpty { place += "  ›  field: \(field)" }
        return place
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
                name: "Jira · summary", bundleIDs: Browsers.bundleIDs,
                urlPattern: "*atlassian.net*", fieldPattern: "summary",
                instruction: "A ticket title: one short line in sentence case. No trailing full "
                           + "stop, no list, no greeting.",
                isBuiltIn: true),
            DestinationRule(
                name: "Jira · description", bundleIDs: Browsers.bundleIDs,
                urlPattern: "*atlassian.net*", fieldPattern: "description|main content area",
                instruction: "Shape this as a ticket description: the context in a sentence or "
                           + "two, then any steps or acceptance criteria as short list items. "
                           + "Keep every detail that was spoken.",
                isBuiltIn: true),
            DestinationRule(
                name: "Email subject",
                bundleIDs: ["com.apple.mail", "com.microsoft.Outlook", "com.readdle.smartemail-Mac"]
                    + Browsers.bundleIDs,
                fieldPattern: "subject",
                instruction: "A subject line: a few words, no trailing full stop, no greeting.",
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
        // Built-ins added in a later version reach an existing rules file too, by
        // name, without touching the rules already there.
        let names = Set(stored.map(\.name))
        let missing = Self.defaults.filter { $0.isBuiltIn && !names.contains($0.name) }
        if !missing.isEmpty {
            stored.append(contentsOf: missing)
            save()
        }
    }

    public func replace(_ rule: DestinationRule) {
        lock.withLock {
            guard let index = stored.firstIndex(where: { $0.id == rule.id }) else { return }
            stored[index] = rule
            save()
        }
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
