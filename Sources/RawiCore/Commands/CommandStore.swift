import Foundation

/// Your commands, on disk.
///
/// Ships with five, because the design note is explicit about it: five commands
/// someone actually uses, not a framework. They are the ones that fit a product
/// manager building things on the side — capture an idea before it goes, put a
/// half-formed thought to Claude, file a ticket, remember a follow-up, protect an
/// hour. Three of them need a detail only you have (a Notion database, your Jira
/// site), so those ship turned off with the placeholder visible.
public final class CommandStore: @unchecked Sendable {
    private let url: URL
    private let lock = NSLock()
    private var stored: [SpokenCommand] = []

    public static var defaultURL: URL {
        Config.supportDirectory.appendingPathComponent("commands.json")
    }

    public init(url: URL = CommandStore.defaultURL) {
        self.url = url
        load()
    }

    public var commands: [SpokenCommand] { lock.withLock { stored } }

    public func add(_ command: SpokenCommand) { lock.withLock { stored.append(command); save() } }

    public func replace(_ command: SpokenCommand) {
        lock.withLock {
            guard let index = stored.firstIndex(where: { $0.id == command.id }) else { return }
            stored[index] = command
            save()
        }
    }

    public func remove(_ id: UUID) {
        lock.withLock {
            guard let index = stored.firstIndex(where: { $0.id == id }), !stored[index].isBuiltIn
            else { return }
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

    public static var defaults: [SpokenCommand] {
        [
            SpokenCommand(
                phrase: "ask Claude",
                action: .openLink("https://claude.ai/new?q={text}"),
                enabled: true, isBuiltIn: true,
                note: "Opens a new chat with what you said already typed in. Nothing is sent "
                    + "until you press return."),
            SpokenCommand(
                phrase: "remind me to",
                action: .reminder(list: ""),
                enabled: true, isBuiltIn: true,
                note: "Adds it to Reminders. The first one asks macOS for permission."),
            SpokenCommand(
                phrase: "capture idea",
                action: .notionPage(databaseID: ""),
                enabled: false, isBuiltIn: true,
                note: "Adds a page to your Notion backlog. Needs the database ID here and "
                    + "NOTION_TOKEN in ~/.config/rawi/.env."),
            SpokenCommand(
                phrase: "new ticket",
                action: .openLink("https://YOUR-SITE.atlassian.net/secure/CreateIssueDetails!init.jspa?summary={text}"),
                enabled: false, isBuiltIn: true,
                note: "Opens Jira's create form with the summary filled in. Put your own site "
                    + "in the link. Nothing is created until you save it there."),
            SpokenCommand(
                phrase: "deep work",
                action: .openApp("Shortcuts"),
                enabled: false, isBuiltIn: true,
                note: "A placeholder for your focus routine: point it at an app, or swap it for "
                    + "a link that starts a timer."),
        ]
    }

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([SpokenCommand].self, from: data) else {
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
