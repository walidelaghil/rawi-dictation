import SwiftUI

@MainActor
public final class TransformsViewModel: ObservableObject {
    @Published public var transforms: [Transform] = []
    @Published public var appearance: ResolvedAppearance = .dark
    @Published public var showInfo = false
    public var undo: UndoCenter?

    @Published public var query = ""

    // The add form.
    @Published public var draftName = ""
    @Published public var draftInstruction = ""

    // The try-it box. Deliberately in this screen rather than a separate one:
    // a transform you cannot try is a transform you cannot tune.
    @Published public var tryText = ""
    @Published public var trySpoken = ""
    @Published public var tryResult = ""
    @Published public var tryError: String?
    @Published public var trying = false
    @Published public var labels: HotkeyLabels = .placeholder
    /// The key hint at the top right opens Settings, where the key is changed.
    public var onOpenSettings: (() -> Void)?

    private let store: TransformStore

    /// Runs one rewrite. Nil when no cleanup provider is configured — then the
    /// try-it box says so instead of failing silently.
    public var preview: ((_ text: String, _ instruction: String) async throws -> String)?

    public init(store: TransformStore) {
        self.store = store
        reload()
    }

    public func reload() { transforms = store.transforms }

    public var filtered: [Transform] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return transforms }
        return transforms.filter {
            $0.name.localizedCaseInsensitiveContains(q) || $0.instruction.localizedCaseInsensitiveContains(q)
        }
    }

    public var canAdd: Bool {
        !draftName.trimmingCharacters(in: .whitespaces).isEmpty
            && !draftInstruction.trimmingCharacters(in: .whitespaces).isEmpty
    }

    public func add() {
        guard canAdd else { return }
        store.add(name: draftName, instruction: draftInstruction)
        draftName = ""
        draftInstruction = ""
        reload()
    }

    public func remove(_ transform: Transform) {
        let index = store.transforms.firstIndex { $0.id == transform.id } ?? store.transforms.count
        store.remove(transform.id)
        reload()
        undo?.offer("Deleted “\(transform.name)”") { [store, weak self] in
            store.restore(transform, at: index); self?.reload()
        }
    }

    // MARK: - Editing

    /// Which row is open for editing, and the text being typed into it. Held here
    /// rather than in the row so opening a second one closes the first: two rows
    /// half-edited is a way to lose work.
    @Published public var editingID: UUID?
    @Published public var editName: String = ""
    @Published public var editInstruction: String = ""

    public func beginEditing(_ transform: Transform) {
        editingID = transform.id
        editName = transform.name
        editInstruction = transform.instruction
    }

    public func cancelEditing() { editingID = nil }

    public var canSaveEdit: Bool {
        !editName.trimmingCharacters(in: .whitespaces).isEmpty
            && !editInstruction.trimmingCharacters(in: .whitespaces).isEmpty
    }

    public func saveEdit() {
        guard let id = editingID, canSaveEdit else { return }
        store.update(id, name: editName, instruction: editInstruction)
        editingID = nil
        reload()
    }

    /// Only offered where there is something to go back to.
    public func canRestore(_ transform: Transform) -> Bool {
        !transform.isBuiltIn && store.hasDefault(transform.id)
    }

    public func restore(_ transform: Transform) {
        store.restoreDefault(transform.id)
        if editingID == transform.id { editingID = nil }
        reload()
    }

    /// What the spoken phrase resolves to, shown live so the matching rule is
    /// visible rather than folklore.
    public var matched: Transform? { store.match(spoken: trySpoken) }

    public func runTry() async {
        let text = tryText.trimmingCharacters(in: .whitespacesAndNewlines)
        let spoken = trySpoken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !spoken.isEmpty, let preview else { return }
        trying = true
        tryError = nil
        tryResult = ""
        do {
            tryResult = try await preview(text, matched?.instruction ?? spoken)
        } catch {
            tryError = error.localizedDescription
        }
        trying = false
    }
}

struct TransformRow: View {
    let transform: Transform
    @ObservedObject var model: TransformsViewModel
    @State private var hovered = false
    @State private var expanded = false
    private func c(_ t: ColorToken) -> Color { RawiColors.color(t, model.appearance) }
    private var editing: Bool { model.editingID == transform.id }
    private var isLong: Bool { transform.instruction.count > 140 || transform.instruction.contains("\n") }

    var body: some View { if editing { editor } else { display } }

    private var display: some View {
        Row(appearance: model.appearance) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(transform.name)
                        .font(.system(size: TypeScale.heading, weight: .medium))
                        .foregroundStyle(c(.bone))
                    if !transform.isBuiltIn {
                        Text("yours").font(.system(size: TypeScale.small))
                            .foregroundStyle(c(.verdigris))
                    }
                }
                .frame(width: 150, alignment: .leading)
                Image(systemName: "arrow.right")
                    .font(.system(size: TypeScale.micro)).foregroundStyle(c(.muted)).padding(.top, 4)
                VStack(alignment: .leading, spacing: 4) {
                    Text(transform.instruction)
                        .font(.system(size: TypeScale.body)).foregroundStyle(c(.bone))
                        .lineLimit(expanded ? nil : 3)
                        .fixedSize(horizontal: false, vertical: true)
                    if isLong {
                        Button(expanded ? "Show less" : "Show more") { expanded.toggle() }
                            .buttonStyle(.plain).font(.system(size: TypeScale.small))
                            .foregroundStyle(c(.saffron))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if model.canRestore(transform) {
                    Button("Reset") { model.restore(transform) }
                        .buttonStyle(.plain).font(.system(size: TypeScale.small))
                        .foregroundStyle(c(.muted)).help("Put the shipped wording back")
                        .opacity(hovered ? 1 : 0)
                }
                if !transform.isBuiltIn {
                    RemoveButton(visible: hovered, label: "Delete \(transform.name)",
                                 appearance: model.appearance) { model.remove(transform) }
                }
            }
        }
        .onHover { hovered = $0 }
        .onTapGesture { model.beginEditing(transform) }
        .help("Click to edit")
    }

    private var editor: some View {
        FormCard(appearance: model.appearance) {
            GrowingField(placeholder: "What you will say", text: $model.editName, lines: 1...2,
                         weight: .medium, size: TypeScale.heading, appearance: model.appearance)
            Rectangle().fill(c(.edge)).frame(height: 1)
            GrowingField(placeholder: "What the model should do", text: $model.editInstruction,
                         lines: 2...8, appearance: model.appearance)
            HStack(spacing: 12) {
                Spacer()
                Button("Cancel", action: model.cancelEditing)
                    .buttonStyle(.plain).font(.system(size: TypeScale.body))
                    .foregroundStyle(c(.muted)).keyboardShortcut(.escape, modifiers: [])
                PrimaryButton(title: "Save", enabled: model.canSaveEdit,
                              appearance: model.appearance) { model.saveEdit() }
                    .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(.horizontal, 8)
    }
}

public struct TransformsView: View {
    @ObservedObject var model: TransformsViewModel
    public init(model: TransformsViewModel) { self.model = model }
    private func c(_ t: ColorToken) -> Color { RawiColors.color(t, model.appearance) }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader(title: "Transforms", appearance: model.appearance,
                         subtitle: "Copy text, hold \(model.labels.transform), and say how to rewrite it.",
                         trailing: AnyView(KeyHint(label: "Transform key", key: model.labels.transform,
                                                       appearance: model.appearance) {
                                 model.onOpenSettings?()
                             }))

                FormCard(appearance: model.appearance) {
                    GrowingField(placeholder: "When I say…", text: $model.draftName, lines: 1...2,
                                 weight: .medium, size: TypeScale.heading,
                                 appearance: model.appearance)
                    Rectangle().fill(c(.edge)).frame(height: 1)
                    GrowingField(placeholder: "…rewrite the text like this", text: $model.draftInstruction,
                                 lines: 2...8, appearance: model.appearance)
                    HStack {
                        Spacer()
                        PrimaryButton(title: "Add transform", enabled: model.canAdd,
                                      appearance: model.appearance) { model.add() }
                            .keyboardShortcut(.return, modifiers: .command)
                            .help("Add (⌘Return)")
                    }
                }

                if model.transforms.count > 3 {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(c(.muted))
                        TextField("Search transforms", text: $model.query)
                            .textFieldStyle(.plain).font(.system(size: TypeScale.body))
                            .foregroundStyle(c(.bone))
                    }
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: Radius.control).fill(c(.ink))
                        .overlay(RoundedRectangle(cornerRadius: Radius.control).strokeBorder(c(.edge))))
                }

                if model.filtered.isEmpty {
                    EmptyHint(title: model.transforms.isEmpty ? "No transforms yet."
                                  : "No transform matches “\(model.query)”.",
                              detail: "", appearance: model.appearance)
                } else {
                    RowGroup(appearance: model.appearance, scrolls: false) {
                        ForEach(model.filtered) { TransformRow(transform: $0, model: model) }
                    }
                }

                tryIt
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(c(.surface))
    }

    // MARK: - Try it

    private var tryIt: some View {
        FormCard(appearance: model.appearance) {
            HStack(spacing: 8) {
                Text("Try one").font(.system(size: TypeScale.body, weight: .semibold))
                    .foregroundStyle(c(.bone))
                Spacer()
                if let matched = model.matched {
                    Text(matched.name.uppercased())
                        .font(.system(size: TypeScale.micro, weight: .medium).monospaced()).tracking(1.1)
                        .foregroundStyle(c(.saffron))
                } else if !model.trySpoken.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text("USED AS SPOKEN")
                        .font(.system(size: TypeScale.micro, weight: .medium).monospaced()).tracking(1.1)
                        .foregroundStyle(c(.lapis))
                }
            }
            GrowingField(placeholder: "Paste some text…", text: $model.tryText, lines: 2...8,
                         appearance: model.appearance)
            Rectangle().fill(c(.edge)).frame(height: 1)
            GrowingField(placeholder: "…and say what to do with it", text: $model.trySpoken,
                         lines: 1...3, appearance: model.appearance)
            HStack(spacing: 10) {
                // No provider, no button: the sentence says what to do instead.
                if model.preview == nil {
                    Text("Transforms need a cleanup provider. Turn one on in Settings.")
                        .font(.system(size: TypeScale.small)).foregroundStyle(c(.muted))
                } else if let error = model.tryError {
                    Text(error).font(.system(size: TypeScale.small)).foregroundStyle(c(.clay))
                }
                Spacer()
                if model.preview != nil {
                    PrimaryButton(title: model.trying ? "Rewriting…" : "Rewrite",
                                  enabled: !model.trying, appearance: model.appearance) {
                        Task { await model.runTry() }
                    }
                }
            }
            if !model.tryResult.isEmpty {
                Text(model.tryResult)
                    .font(.system(size: TypeScale.body)).foregroundStyle(c(.bone))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: Radius.control).fill(c(.surface))
                        .overlay(RoundedRectangle(cornerRadius: Radius.control)
                            .strokeBorder(c(.verdigris).opacity(0.45))))
            }
        }
    }
}
