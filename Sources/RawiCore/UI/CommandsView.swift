import AppKit
import SwiftUI

@MainActor
public final class CommandsViewModel: ObservableObject {
    @Published public var commands: [SpokenCommand] = []
    @Published public var appearance: ResolvedAppearance = .dark
    @Published public var showInfo = false
    /// The command being edited, if any.
    @Published public var editing: UUID?
    @Published public var composing = false
    @Published public var draftPhrase = ""
    @Published public var draftKind = "link"
    @Published public var draftDetail = ""
    @Published public var draftConfirm = true
    /// What the try box would do, and what running it said.
    @Published public var tryText = ""
    @Published public var tryResult: String?
    @Published public var key = "⌃⌥C"

    private let store: CommandStore
    /// Runs a command for real, from the try box.
    public var perform: ((CommandAction, String) async throws -> String)?

    public init(store: CommandStore) {
        self.store = store
        reload()
    }

    public func reload() { commands = store.commands }

    public func toggle(_ command: SpokenCommand) { store.setEnabled(command.id, !command.enabled); reload() }
    public func remove(_ command: SpokenCommand) { store.remove(command.id); reload() }

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

public struct CommandsView: View {
    @ObservedObject var model: CommandsViewModel
    public init(model: CommandsViewModel) { self.model = model }
    private func c(_ t: ColorToken) -> Color { RawiColors.color(t, model.appearance) }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader(title: "Commands", appearance: model.appearance, showInfo: $model.showInfo,
                             info: "Hold \(model.key), say a command, let go. The phrase has to be the "
                                 + "start of what you said, matched here on this Mac, never by a model "
                                 + "guessing what you meant. Anything that creates something shows what "
                                 + "it will do and waits: tap \(model.key) again to run it, Esc to drop "
                                 + "it. What you say never reaches your document.")
                RowGroup(appearance: model.appearance) {
                    ForEach(model.commands) { command in
                        Row(appearance: model.appearance) { row(command) }
                    }
                }
                tryBox
                addCommand
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24).padding(.vertical, 22)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(c(.surface))
        .onAppear { model.reload() }
    }

    @ViewBuilder private func row(_ command: SpokenCommand) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Button { model.toggle(command) } label: {
                    Image(systemName: command.enabled ? "checkmark.square.fill" : "square")
                        .font(.system(size: TypeScale.heading))
                        .foregroundStyle(command.enabled ? c(.verdigris) : c(.faint))
                }
                .buttonStyle(.plain)
                .help(command.enabled ? "Turn off" : "Turn on")

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 9) {
                        Text("“\(command.phrase)”")
                            .font(.system(size: TypeScale.heading, weight: .medium))
                            .foregroundStyle(command.enabled ? c(.bone) : c(.faint))
                        Text(command.action.kindLabel.uppercased())
                            .font(.system(size: TypeScale.micro, weight: .medium)).tracking(1)
                            .foregroundStyle(c(.faint))
                        if command.confirm {
                            Text("ASKS FIRST")
                                .font(.system(size: TypeScale.micro, weight: .medium)).tracking(1)
                                .foregroundStyle(c(.saffron))
                        }
                    }
                    // Only when there is one: an empty detail used to fall back to the
                    // note, which then appeared twice in a row.
                    let detail = CommandsViewModel.detail(of: command.action)
                    if !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: TypeScale.small).monospaced())
                            .foregroundStyle(c(.muted))
                            .lineLimit(1).truncationMode(.middle)
                    }
                    if !command.note.isEmpty {
                        Text(command.note).font(.system(size: TypeScale.small))
                            .foregroundStyle(c(.faint))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                Button { model.editing = model.editing == command.id ? nil : command.id } label: {
                    Image(systemName: "slider.horizontal.3").font(.system(size: TypeScale.body))
                        .foregroundStyle(model.editing == command.id ? c(.saffron) : c(.faint))
                }
                .buttonStyle(.plain).help("Edit")
                if !command.isBuiltIn {
                    Button { model.remove(command) } label: {
                        Image(systemName: "xmark").font(.system(size: TypeScale.micro))
                            .foregroundStyle(c(.faint))
                    }
                    .buttonStyle(.plain).help("Delete")
                }
            }
            if model.editing == command.id { editor(command) }
        }
    }

    private func editor(_ command: SpokenCommand) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                labelled("Say", text: Binding(
                    get: { command.phrase },
                    set: { model.update(command, phrase: $0) }))
                labelled(CommandsViewModel.kinds.first { $0.id == CommandsViewModel.kind(of: command.action) }?.hint ?? "",
                         text: Binding(
                    get: { CommandsViewModel.detail(of: command.action) },
                    set: { model.update(command, detail: $0) }))
            }
            Toggle("Ask before running", isOn: Binding(
                get: { command.confirm },
                set: { model.update(command, confirm: $0) }))
                .toggleStyle(.checkbox)
                .font(.system(size: TypeScale.small))
                .foregroundStyle(c(.muted))
        }
        .padding(.leading, 34).padding(.top, 2)
    }

    private var tryBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Try one").font(.system(size: TypeScale.body, weight: .semibold)).foregroundStyle(c(.bone))
            HStack(spacing: 8) {
                labelled("Say it in writing, like: remind me to send the deck", text: $model.tryText)
                Button("Run") { model.runTry() }
                    .buttonStyle(.plain)
                    .font(.system(size: TypeScale.body, weight: .semibold))
                    .foregroundStyle(model.tryPreview == nil ? c(.faint) : c(.saffron))
                    .disabled(model.tryPreview == nil)
            }
            if let preview = model.tryPreview {
                Text(preview).font(.system(size: TypeScale.small)).foregroundStyle(c(.muted))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let result = model.tryResult {
                Text(result).font(.system(size: TypeScale.small)).foregroundStyle(c(.verdigris))
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: Radius.surface).fill(c(.raised))
            .overlay(RoundedRectangle(cornerRadius: Radius.surface).strokeBorder(c(.edge))))
    }

    private var addCommand: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Add a command").font(.system(size: TypeScale.body, weight: .semibold))
                    .foregroundStyle(c(.bone))
                Spacer()
                if !model.composing {
                    Button("New command") { model.composing = true }
                        .buttonStyle(.plain)
                        .font(.system(size: TypeScale.small, weight: .medium)).foregroundStyle(c(.saffron))
                }
            }
            if model.composing {
                HStack(spacing: 8) {
                    labelled("Say, like: capture idea", text: $model.draftPhrase)
                    Picker("", selection: $model.draftKind) {
                        ForEach(CommandsViewModel.kinds, id: \.id) { kind in Text(kind.label).tag(kind.id) }
                    }
                    .labelsHidden().frame(width: 150)
                }
                labelled(CommandsViewModel.kinds.first { $0.id == model.draftKind }?.hint ?? "",
                         text: $model.draftDetail)
                HStack {
                    Toggle("Ask before running", isOn: $model.draftConfirm)
                        .toggleStyle(.checkbox).font(.system(size: TypeScale.small))
                        .foregroundStyle(c(.muted))
                    Spacer()
                    Button("Add command") { model.saveDraft() }
                        .buttonStyle(.plain)
                        .font(.system(size: TypeScale.body, weight: .semibold))
                        .foregroundStyle(model.canSave ? c(.saffron) : c(.faint))
                        .disabled(!model.canSave)
                }
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: Radius.surface).fill(c(.raised))
            .overlay(RoundedRectangle(cornerRadius: Radius.surface).strokeBorder(c(.edge))))
    }

    private func labelled(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(.system(size: TypeScale.body))
            .foregroundStyle(c(.bone))
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: Radius.control).fill(c(.ink))
                .overlay(RoundedRectangle(cornerRadius: Radius.control).strokeBorder(c(.edge))))
    }
}
