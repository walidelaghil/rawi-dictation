import AppKit
import Foundation

/// What a command does when it runs.
///
/// Rawi performs these itself. The design note for Commands suggested leaning on
/// Apple's Shortcuts, and that is a fair way to reach hundreds of apps, but it puts
/// the work on you: build a Shortcut, then point a command at it. Everything here
/// needs nothing but the command itself.
public enum CommandAction: Codable, Sendable, Equatable {
    /// Open a link. `{text}` in the template is replaced with what you said,
    /// percent-encoded.
    case openLink(String)
    /// Open an app by name, as you would in Spotlight.
    case openApp(String)
    /// Put text on the clipboard. `{text}` is replaced.
    case copy(String)
    /// Add a reminder, in a list of your choosing.
    case reminder(list: String)
    /// Add a page to a Notion database. The token comes from ~/.config/rawi/.env,
    /// never from this file.
    case notionPage(databaseID: String)

    public var kindLabel: String {
        switch self {
        case .openLink: "Open a link"
        case .openApp: "Open an app"
        case .copy: "Copy text"
        case .reminder: "Add a reminder"
        case .notionPage: "Add to Notion"
        }
    }

    /// What it will do, in one line, for the list and the confirmation.
    public func describe(text: String) -> String {
        switch self {
        case .openLink(let template): "Open \(SpokenCommand.fill(template, with: text, encoded: true))"
        case .openApp(let name): "Open \(name)"
        case .copy(let template): "Copy “\(SpokenCommand.fill(template, with: text))”"
        case .reminder(let list): "Add “\(text)” to your \(list.isEmpty ? "Reminders" : list) list"
        case .notionPage: "Add “\(text)” to Notion"
        }
    }

    /// Whether running it changes something outside Rawi. Those ask first.
    public var creates: Bool {
        switch self {
        case .openLink, .openApp, .copy: false
        case .reminder, .notionPage: true
        }
    }
}

/// A phrase you say, and what it does.
public struct SpokenCommand: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    /// What you say first. Everything after it is the text the action receives.
    public var phrase: String
    public var action: CommandAction
    /// Show what it will do and wait, before it runs.
    public var confirm: Bool
    public var enabled: Bool
    public var isBuiltIn: Bool
    /// Filled in by whoever ships it: why this one is here.
    public var note: String

    public init(id: UUID = UUID(), phrase: String, action: CommandAction, confirm: Bool? = nil,
                enabled: Bool = true, isBuiltIn: Bool = false, note: String = "") {
        self.id = id
        self.phrase = phrase
        self.action = action
        // Anything that creates something asks first unless you say otherwise.
        self.confirm = confirm ?? action.creates
        self.enabled = enabled
        self.isBuiltIn = isBuiltIn
        self.note = note
    }

    private enum CodingKeys: String, CodingKey {
        case id, phrase, action, confirm, enabled, isBuiltIn, note
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        phrase = try c.decode(String.self, forKey: .phrase)
        action = try c.decode(CommandAction.self, forKey: .action)
        confirm = try c.decodeIfPresent(Bool.self, forKey: .confirm) ?? action.creates
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        isBuiltIn = try c.decodeIfPresent(Bool.self, forKey: .isBuiltIn) ?? false
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
    }

    /// `{text}` replaced by what you said.
    public static func fill(_ template: String, with text: String, encoded: Bool = false) -> String {
        let value = encoded
            ? text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
            : text
        return template.replacingOccurrences(of: "{text}", with: value)
    }
}

/// Matches what you said against your commands.
///
/// Deterministic and local: the phrase has to be the start of what you said. No
/// model decides whether you meant a command, because "log this as a bet" is
/// indistinguishable from dictating those words, and a command you did not mean is
/// far worse than a sentence you did not mean.
public enum CommandMatcher {
    public struct Match: Equatable, Sendable {
        public let command: SpokenCommand
        public let text: String
    }

    public static func match(_ spoken: String, in commands: [SpokenCommand]) -> Match? {
        let said = normalise(spoken)
        // Longest phrase first: "new ticket for Jira" beats "new ticket".
        let candidates = commands.filter(\.enabled)
            .sorted { normalise($0.phrase).count > normalise($1.phrase).count }
        for command in candidates {
            let phrase = normalise(command.phrase)
            guard !phrase.isEmpty, said == phrase || said.hasPrefix(phrase + " ") else { continue }
            let rest = String(said.dropFirst(phrase.count)).trimmingCharacters(in: .whitespaces)
            // The original casing and punctuation, not the flattened form.
            return Match(command: command, text: rest.isEmpty ? "" : original(spoken, keepingLast: rest))
        }
        return nil
    }

    /// Lower-cased, punctuation dropped, spaces collapsed, so "Capture idea:" and
    /// "capture idea" are the same phrase.
    static func normalise(_ text: String) -> String {
        text.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .joined(separator: " ")
    }

    /// The tail of the spoken text as it was actually said, matched by word count.
    static func original(_ spoken: String, keepingLast rest: String) -> String {
        let words = rest.split(separator: " ").count
        let spokenWords = spoken.split(whereSeparator: \.isWhitespace)
        guard words > 0, spokenWords.count >= words else { return rest }
        return spokenWords.suffix(words).joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " .,!?"))
    }
}
