import AppKit
import SwiftUI

@MainActor
public final class CommandsViewModel: ObservableObject {
    @Published public var commands: [SpokenCommand] = []
    @Published public var appearance: ResolvedAppearance = .dark
    @Published public var showInfo = false
    public var undo: UndoCenter?
    /// The command being edited, if any.
    @Published public var editing: UUID?
    @Published public var composing = false
    @Published public var query = ""
    @Published public var editPhrase = ""
    @Published public var editDetail = ""
    @Published public var editConfirm = true
    @Published public var draftPhrase = ""
    @Published public var draftKind = "link"
    @Published public var draftDetail = ""
    @Published public var draftConfirm = true
    /// What the try box would do, and what running it said.
    @Published public var tryText = ""
    @Published public var tryResult: String?
    @Published public var key = "⌃⌥C"
    /// The key hint at the top right opens Settings, where the key is changed.
    public var onOpenSettings: (() -> Void)?

    private let store: CommandStore
    /// Runs a command for real, from the try box.
    public var perform: ((CommandAction, String) async throws -> String)?

    public init(store: CommandStore) {
        self.store = store
        reload()
    }

    public func reload() { commands = store.commands }

    public var filtered: [SpokenCommand] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return commands }
        return commands.filter {
            $0.phrase.localizedCaseInsensitiveContains(q)
                || Self.detail(of: $0.action).localizedCaseInsensitiveContains(q)
        }
    }

    public func beginEditing(_ command: SpokenCommand) {
        editing = command.id
        editPhrase = command.phrase
        editDetail = Self.detail(of: command.action)
        editConfirm = command.confirm
    }
    public func cancelEditing() { editing = nil }
    public func saveEdit() {
        guard let id = editing, let command = commands.first(where: { $0.id == id }),
              !editPhrase.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        update(command, phrase: editPhrase.trimmingCharacters(in: .whitespaces),
               detail: editDetail.trimmingCharacters(in: .whitespaces), confirm: editConfirm)
        editing = nil
    }

    public func toggle(_ command: SpokenCommand) { store.setEnabled(command.id, !command.enabled); reload() }
    public func remove(_ command: SpokenCommand) {
        let index = store.commands.firstIndex { $0.id == command.id } ?? store.commands.count
        store.remove(command.id); reload()
        undo?.offer("Deleted “\(command.phrase)”") { [store, weak self] in
            store.restore(command, at: index); self?.reload()
        }
    }

    public func update(_ command: SpokenCommand, phrase: String? = nil, detail: String? = nil,
                       confirm: Bool? = nil) {
        var edited = command
        if let phrase { edited.phrase = phrase }
        if let confirm { edited.confirm = confirm }
        if let detail { edited.action = Self.action(kind: Self.kind(of: command.action), detail: detail) }
        store.replace(edited)
        reload()
    }

    public static let kinds: [(id: String, label: String, hint: String)] = [
        ("link", "Open a link", "https://claude.ai/new?q={text}"),
        ("app", "Open an app", "Notion"),
        ("copy", "Copy text", "{text}"),
        ("reminder", "Add a reminder", "list name, or leave empty"),
        ("notion", "Add to Notion", "database ID"),
    ]

    public static func kind(of action: CommandAction) -> String {
        switch action {
        case .openLink: "link"
        case .openApp: "app"
        case .copy: "copy"
        case .reminder: "reminder"
        case .notionPage: "notion"
        }
    }

    public static func detail(of action: CommandAction) -> String {
        switch action {
        case .openLink(let value), .openApp(let value), .copy(let value): value
        case .reminder(let list): list
        case .notionPage(let id): id
        }
    }

    public static func action(kind: String, detail: String) -> CommandAction {
        switch kind {
        case "app": .openApp(detail)
        case "copy": .copy(detail)
        case "reminder": .reminder(list: detail)
        case "notion": .notionPage(databaseID: detail)
        default: .openLink(detail)
        }
    }

    public var canSave: Bool {
        !draftPhrase.trimmingCharacters(in: .whitespaces).isEmpty
            && !(draftKind != "reminder" && draftDetail.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    public func saveDraft() {
        guard canSave else { return }
        store.add(SpokenCommand(phrase: draftPhrase.trimmingCharacters(in: .whitespaces),
                                action: Self.action(kind: draftKind,
                                                    detail: draftDetail.trimmingCharacters(in: .whitespaces)),
                                confirm: draftConfirm))
        draftPhrase = ""; draftDetail = ""; draftConfirm = true; composing = false
        reload()
    }

    /// What the try box would do, without doing it.
    public var tryPreview: String? {
        guard let match = CommandMatcher.match(tryText, in: commands) else {
            return tryText.trimmingCharacters(in: .whitespaces).isEmpty
                ? nil : "No command matches that."
        }
        return match.command.action.describe(text: match.text)
            + (match.command.confirm ? "  ·  asks first" : "")
    }

    public func runTry() {
        guard let match = CommandMatcher.match(tryText, in: commands), let perform else { return }
        tryResult = "Running…"
        Task {
            do { tryResult = try await perform(match.command.action, match.text) }
            catch { tryResult = error.localizedDescription }
        }
    }
}

struct CommandRow: View {
    let command: SpokenCommand
    @ObservedObject var model: CommandsViewModel
    @State private var hovered = false
    private func c(_ t: ColorToken) -> Color { RawiColors.color(t, model.appearance) }
    private var editing: Bool { model.editing == command.id }

    var body: some View { if editing { editor } else { display } }

    private var display: some View {
        Row(appearance: model.appearance) {
            HStack(alignment: .top, spacing: 12) {
                Button { model.toggle(command) } label: {
                    Image(systemName: command.enabled ? "checkmark.square.fill" : "square")
                        .font(.system(size: TypeScale.heading))
                        .foregroundStyle(command.enabled ? c(.verdigris) : c(.muted))
                        .frame(width: 24, height: 24).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(command.enabled ? "Turn off" : "Turn on")
                .accessibilityLabel(command.enabled ? "Turn off \(command.phrase)" : "Turn on \(command.phrase)")

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 9) {
                        Text("“\(command.phrase)”")
                            .font(.system(size: TypeScale.heading, weight: .medium))
                            .foregroundStyle(command.enabled ? c(.bone) : c(.muted))
                        Text(command.action.kindLabel.uppercased())
                            .font(.system(size: TypeScale.micro, weight: .medium)).tracking(1)
                            .foregroundStyle(c(.muted))
                        if command.confirm {
                            Text("ASKS FIRST")
                                .font(.system(size: TypeScale.micro, weight: .medium)).tracking(1)
                                .foregroundStyle(c(.saffron))
                        }
                    }
                    let detail = CommandsViewModel.detail(of: command.action)
                    if !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: TypeScale.small).monospaced())
                            .foregroundStyle(c(.muted))
                            .lineLimit(1).truncationMode(.middle)
                    }
                    if !command.note.isEmpty {
                        Text(command.note).font(.system(size: TypeScale.small))
                            .foregroundStyle(c(.muted))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                if !command.isBuiltIn {
                    RemoveButton(visible: hovered, label: "Delete \(command.phrase)",
                                 appearance: model.appearance) { model.remove(command) }
                }
            }
        }
        .onHover { hovered = $0 }
        .onTapGesture { model.beginEditing(command) }
        .help("Click to edit")
    }

    private var editor: some View {
        FormCard(appearance: model.appearance) {
            GrowingField(placeholder: "When I say…", text: $model.editPhrase, lines: 1...2,
                         weight: .medium, size: TypeScale.heading, appearance: model.appearance)
            Rectangle().fill(c(.edge)).frame(height: 1)
            GrowingField(placeholder: CommandsViewModel.kinds
                            .first { $0.id == CommandsViewModel.kind(of: command.action) }?.hint ?? "",
                         text: $model.editDetail, lines: 1...4, appearance: model.appearance)
            HStack(spacing: 12) {
                Toggle("Ask before running", isOn: $model.editConfirm)
                    .toggleStyle(.checkbox).font(.system(size: TypeScale.small))
                    .foregroundStyle(c(.muted))
                Spacer()
                Button("Cancel", action: model.cancelEditing)
                    .buttonStyle(.plain).font(.system(size: TypeScale.body))
                    .foregroundStyle(c(.muted)).keyboardShortcut(.escape, modifiers: [])
                PrimaryButton(title: "Save", appearance: model.appearance) { model.saveEdit() }
                    .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(.horizontal, 8)
    }
}

public struct CommandsView: View {
    @ObservedObject var model: CommandsViewModel
    public init(model: CommandsViewModel) { self.model = model }
    private func c(_ t: ColorToken) -> Color { RawiColors.color(t, model.appearance) }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader(title: "Commands", appearance: model.appearance,
                         subtitle: "Say a command and Rawi acts on it. Nothing is typed.",
                         trailing: AnyView(KeyHint(label: "Command key", key: model.key,
                                                       appearance: model.appearance) {
                                 model.onOpenSettings?()
                             }))

                addCard

                if model.commands.count > 3 {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(c(.muted))
                        TextField("Search commands", text: $model.query)
                            .textFieldStyle(.plain).font(.system(size: TypeScale.body))
                            .foregroundStyle(c(.bone))
                    }
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: Radius.control).fill(c(.ink))
                        .overlay(RoundedRectangle(cornerRadius: Radius.control).strokeBorder(c(.edge))))
                }

                if model.filtered.isEmpty {
                    EmptyHint(title: model.commands.isEmpty ? "No commands yet."
                                  : "No command matches “\(model.query)”.",
                              detail: "", appearance: model.appearance)
                } else {
                    RowGroup(appearance: model.appearance, scrolls: false) {
                        ForEach(model.filtered) { CommandRow(command: $0, model: model) }
                    }
                }

                tryBox
            }
            .padding(.horizontal, 24).padding(.vertical, 22)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(c(.surface))
        .onAppear { model.reload() }
    }

    /// Same shape as Snippets: what you say on top, what happens below.
    private var addCard: some View {
        FormCard(appearance: model.appearance) {
            GrowingField(placeholder: "When I say…  (like: capture idea)", text: $model.draftPhrase,
                         lines: 1...2, weight: .medium, size: TypeScale.heading,
                         appearance: model.appearance)
            Rectangle().fill(c(.edge)).frame(height: 1)
            HStack(spacing: 10) {
                Text("then").font(.system(size: TypeScale.body)).foregroundStyle(c(.muted))
                Picker("", selection: $model.draftKind) {
                    ForEach(CommandsViewModel.kinds, id: \.id) { Text($0.label).tag($0.id) }
                }
                .labelsHidden().pickerStyle(.menu).fixedSize()
                Spacer()
            }
            GrowingField(placeholder: CommandsViewModel.kinds
                            .first { $0.id == model.draftKind }?.hint ?? "",
                         text: $model.draftDetail, lines: 1...4, appearance: model.appearance)
            HStack(spacing: 12) {
                Toggle("Ask before running", isOn: $model.draftConfirm)
                    .toggleStyle(.checkbox).font(.system(size: TypeScale.small))
                    .foregroundStyle(c(.muted))
                Spacer()
                PrimaryButton(title: "Add command", enabled: model.canSave,
                              appearance: model.appearance) { model.saveDraft() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .help("Add (⌘Return)")
            }
        }
    }

    private var tryBox: some View {
        FormCard(appearance: model.appearance) {
            Text("Try one").font(.system(size: TypeScale.body, weight: .semibold))
                .foregroundStyle(c(.bone))
            GrowingField(placeholder: "Say it in writing, like: remind me to send the deck",
                         text: $model.tryText, lines: 1...3, appearance: model.appearance)
            HStack(spacing: 10) {
                if let preview = model.tryPreview {
                    Text(preview).font(.system(size: TypeScale.small)).foregroundStyle(c(.muted))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                PrimaryButton(title: "Run", enabled: model.tryPreview != nil,
                              appearance: model.appearance) { model.runTry() }
            }
            if let result = model.tryResult {
                Text(result).font(.system(size: TypeScale.small)).foregroundStyle(c(.verdigris))
            }
        }
    }
}
