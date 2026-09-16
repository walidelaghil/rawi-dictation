import AppKit
import EventKit
import Foundation

public enum CommandError: Error, LocalizedError, Equatable {
    case noMatch(String)
    case needsText(String)
    case failed(String)
    case missingKey(String)

    public var errorDescription: String? {
        switch self {
        case .noMatch(let said): "No command for “\(said)”"
        case .needsText(let phrase): "Say something after “\(phrase)”"
        case .failed(let why): why
        case .missingKey(let key): "Add \(key) to ~/.config/rawi/.env"
        }
    }
}

/// Carries out a command. Everything here is something Rawi does itself.
public protocol CommandPerforming: Sendable {
    func perform(_ action: CommandAction, text: String) async throws -> String
}

public struct SystemCommandPerformer: CommandPerforming {
    let env: DotEnv
    public init(env: DotEnv) { self.env = env }

    public func perform(_ action: CommandAction, text: String) async throws -> String {
        switch action {
        case .openLink(let template):
            let filled = SpokenCommand.fill(template, with: text, encoded: true)
            guard let url = URL(string: filled), url.scheme != nil else {
                throw CommandError.failed("That link is not valid")
            }
            await MainActor.run { NSWorkspace.shared.open(url) }
            return "Opened \(url.host ?? url.absoluteString)"

        case .openApp(let name):
            let found = await MainActor.run { NSWorkspace.shared.urlForApplication(withBundleIdentifier: name) }
                ?? URL(fileURLWithPath: "/Applications/\(name).app")
            guard FileManager.default.fileExists(atPath: found.path) else {
                throw CommandError.failed("\(name) is not installed")
            }
            await MainActor.run {
                NSWorkspace.shared.openApplication(at: found, configuration: NSWorkspace.OpenConfiguration())
            }
            return "Opened \(name)"

        case .copy(let template):
            let filled = SpokenCommand.fill(template, with: text)
            await MainActor.run {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(filled, forType: .string)
            }
            return "Copied"

        case .reminder(let list):
            return try await Reminders.add(title: text, list: list)

        case .notionPage(let databaseID):
            guard let token = env["NOTION_TOKEN"], !token.isEmpty else {
                throw CommandError.missingKey("NOTION_TOKEN")
            }
            try await Notion.addPage(title: text, databaseID: databaseID, token: token)
            return "Added to Notion"
        }
    }
}

/// Adds a reminder through EventKit.
///
/// AppleScript was tried first and refused: "Not authorized to send Apple events to
/// Reminders." Automation permission is granted per app *pair*, is asked for in a
/// dialog that macOS will not always show again, and once declined leaves no way
/// back from inside Rawi. EventKit asks for Reminders directly, in a prompt that
/// names what it is for, and reports refusal as something this code can explain.
enum Reminders {
    @discardableResult
    static func add(title: String, list: String) async throws -> String {
        guard !title.isEmpty else { throw CommandError.failed("Nothing to remind you about") }
        let store = EKEventStore()
        let granted: Bool
        if #available(macOS 14.0, *) {
            granted = (try? await store.requestFullAccessToReminders()) ?? false
        } else {
            granted = await withCheckedContinuation { continuation in
                store.requestAccess(to: .reminder) { ok, _ in continuation.resume(returning: ok) }
            }
        }
        guard granted else {
            throw CommandError.failed("Rawi is not allowed to add reminders. Turn it on in "
                                      + "System Settings, Privacy & Security, Reminders.")
        }
        let parsed = SpokenDate.parse(title)
        let reminder = EKReminder(eventStore: store)
        reminder.title = parsed.title
        if let due = parsed.due {
            var calendar = Calendar.current
            calendar.timeZone = .current
            reminder.dueDateComponents = calendar.dateComponents(
                parsed.hasTime ? [.year, .month, .day, .hour, .minute] : [.year, .month, .day],
                from: due)
            // A due date without an alarm never says anything. Reminders only nags
            // you if something is set to.
            reminder.addAlarm(EKAlarm(absoluteDate: due))
        }
        let named = list.trimmingCharacters(in: .whitespaces)
        if !named.isEmpty,
           let match = store.calendars(for: .reminder).first(where: {
               $0.title.compare(named, options: .caseInsensitive) == .orderedSame
           }) {
            reminder.calendar = match
        } else if let fallback = store.defaultCalendarForNewReminders() {
            reminder.calendar = fallback
        } else {
            throw CommandError.failed("No Reminders list to add to")
        }
        do { try store.save(reminder, commit: true) }
        catch { throw CommandError.failed(error.localizedDescription) }
        return parsed.due.map { "Reminder set \(SpokenDate.describe($0, hasTime: parsed.hasTime))" }
            ?? "Reminder added"
    }
}

/// Adds a page to a Notion database, with the title you spoke.
enum Notion {
    static func addPage(title: String, databaseID: String, token: String) async throws {
        guard !title.isEmpty else { throw CommandError.failed("Nothing to add") }
        var request = URLRequest(url: URL(string: "https://api.notion.com/v1/pages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("2022-06-28", forHTTPHeaderField: "Notion-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "parent": ["database_id": databaseID],
            "properties": ["title": ["title": [["text": ["content": title]]]]],
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { $0?["message"] as? String } ?? "HTTP \(status)"
            throw CommandError.failed("Notion said: \(message)")
        }
    }
}

/// Decides what a spoken command does, and runs it once you have agreed.
@MainActor
public final class CommandRunner {
    public struct Pending: Equatable, Sendable {
        public let match: CommandMatcher.Match
        public var summary: String { match.command.action.describe(text: match.text) }
    }

    private let store: CommandStore
    private let performer: any CommandPerforming
    /// What is waiting for your confirmation, and when it expires.
    public private(set) var pending: Pending?
    private var pendingSince: Date?
    /// A confirmation nobody answers is dropped rather than run later by surprise.
    public static let confirmWindow: TimeInterval = 12

    public init(store: CommandStore, performer: any CommandPerforming) {
        self.store = store
        self.performer = performer
    }

    /// What you said, on the command key. Returns what to show on the pill.
    public func heard(_ spoken: String) async throws -> String {
        guard let match = CommandMatcher.match(spoken, in: store.commands) else {
            throw CommandError.noMatch(spoken.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if match.text.isEmpty, match.command.action.needsText {
            throw CommandError.needsText(match.command.phrase)
        }
        guard match.command.confirm else { return try await run(match) }
        pending = Pending(match: match)
        pendingSince = Date()
        return "\(Pending(match: match).summary)?"
    }

    /// The command key pressed again while a confirmation is up.
    public func confirm() async throws -> String? {
        guard let pending, let since = pendingSince else { return nil }
        self.pending = nil
        pendingSince = nil
        guard Date().timeIntervalSince(since) <= Self.confirmWindow else { return nil }
        return try await run(pending.match)
    }

    public func cancel() -> Bool {
        guard pending != nil else { return false }
        pending = nil
        pendingSince = nil
        return true
    }

    private func run(_ match: CommandMatcher.Match) async throws -> String {
        try await performer.perform(match.command.action, text: match.text)
    }
}

extension CommandAction {
    /// Whether the action is meaningless without words after the phrase.
    var needsText: Bool {
        switch self {
        case .openApp: false
        case .openLink(let template), .copy(let template): template.contains("{text}")
        case .reminder, .notionPage: true
        }
    }
}
