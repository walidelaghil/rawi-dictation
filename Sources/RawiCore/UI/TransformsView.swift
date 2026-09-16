import SwiftUI

@MainActor
public final class TransformsViewModel: ObservableObject {
    @Published public var transforms: [Transform] = []
    @Published public var appearance: ResolvedAppearance = .dark
    @Published public var showInfo = false

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

    private let store: TransformStore

    /// Runs one rewrite. Nil when no cleanup provider is configured — then the
    /// try-it box says so instead of failing silently.
    public var preview: ((_ text: String, _ instruction: String) async throws -> String)?

    public init(store: TransformStore) {
        self.store = store
        reload()
    }

    public func reload() { transforms = store.transforms }

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
        store.remove(transform.id)
        reload()
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

public struct TransformsView: View {
    @ObservedObject var model: TransformsViewModel
    public init(model: TransformsViewModel) { self.model = model }
    private func c(_ t: ColorToken) -> Color { RawiColors.color(t, model.appearance) }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader(title: "Transforms", appearance: model.appearance,
                             showInfo: $model.showInfo,
                             info: "Copy some text, hold \(model.labels.transform) and say what "
                                 + "to do with it. The clipboard comes back rewritten. Saying a "
                                 + "transform's "
                                 + "name uses its tuned instruction; anything else is used as "
                                 + "you said it. The original goes to History before the model "
                                 + "runs, and a failed transform leaves your clipboard exactly "
                                 + "as it was.")

                tryIt
                list
                addForm
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(c(.surface))
    }

    // MARK: - Try it

    private var tryIt: some View {
        VStack(alignment: .leading, spacing: 10) {
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

            HStack(alignment: .top, spacing: 10) {
                field("Text", text: $model.tryText, lines: 4)
                field("Say", text: $model.trySpoken, lines: 4)
            }

            HStack(spacing: 10) {
                // No provider, no button. A greyed-out control is a promise the
                // screen cannot keep; the sentence says what to do instead.
                if model.preview == nil {
                    Text("Transforms need a cleanup provider. Turn one on in Settings.")
                        .font(.system(size: TypeScale.body)).foregroundStyle(c(.faint))
                } else {
                    Button { Task { await model.runTry() } } label: {
                        Text(model.trying ? "Rewriting…" : "Rewrite")
                            .font(.system(size: TypeScale.body, weight: .medium))
                            .foregroundStyle(c(.ink))
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: Radius.control)
                                .fill(c(.saffron)))
                    }
                    .buttonStyle(.plain)
                    .disabled(model.trying)
                }
                if let error = model.tryError {
                    Text(error).font(.system(size: TypeScale.small)).foregroundStyle(c(.clay))
                }
                Spacer()
            }

            if !model.tryResult.isEmpty {
                Text(model.tryResult)
                    .font(.system(size: TypeScale.body))
                    .foregroundStyle(c(.bone))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: Radius.control).fill(c(.surface))
                        .overlay(RoundedRectangle(cornerRadius: Radius.control)
                            .strokeBorder(c(.verdigris).opacity(0.45))))
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Radius.surface).fill(c(.raised))
            .overlay(RoundedRectangle(cornerRadius: Radius.surface).strokeBorder(c(.edge))))
    }

    private func field(_ label: String, text: Binding<String>, lines: Int) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label.uppercased())
                .font(.system(size: TypeScale.micro, weight: .medium).monospaced()).tracking(1.1)
                .foregroundStyle(c(.faint))
            TextEditor(text: text)
                .font(.system(size: TypeScale.body))
                .scrollContentBackground(.hidden)
                .frame(height: CGFloat(lines) * 17)
                .padding(7)
                .background(RoundedRectangle(cornerRadius: Radius.control).fill(c(.surface))
                    .overlay(RoundedRectangle(cornerRadius: Radius.control).strokeBorder(c(.edge))))
        }
    }

    /// The row, open. Name and instruction both editable, because what you say to
    /// reach a transform is as much a preference as what it then does.
    private var editor: some View {
        VStack(alignment: .leading, spacing: 7) {
            TextField("What you will say", text: $model.editName)
                .textFieldStyle(.plain)
                .font(.system(size: TypeScale.body))
                .foregroundStyle(c(.bone))
                .padding(.horizontal, 9).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: Radius.control).fill(c(.ink)))
            TextEditor(text: $model.editInstruction)
                .font(.system(size: TypeScale.body))
                .foregroundStyle(c(.bone))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 66)
                .padding(.horizontal, 5).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: Radius.control).fill(c(.ink)))
            HStack(spacing: 8) {
                Button("Save", action: model.saveEdit)
                    .buttonStyle(.plain)
                    .font(.system(size: TypeScale.small, weight: .semibold))
                    .foregroundStyle(model.canSaveEdit ? c(.ink) : c(.faint))
                    .padding(.horizontal, 11).padding(.vertical, 5)
                    .background(Capsule().fill(model.canSaveEdit ? c(.saffron) : c(.raised)))
                    .disabled(!model.canSaveEdit)
                Button("Cancel", action: model.cancelEditing)
                    .buttonStyle(.plain)
                    .font(.system(size: TypeScale.small))
                    .foregroundStyle(c(.muted))
            }
        }
        .frame(maxWidth: 620, alignment: .leading)
    }

    // MARK: - List

    private var list: some View {
        RowGroup(appearance: model.appearance) {
            ForEach(model.transforms) { transform in
              Row(appearance: model.appearance) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 9) {
                        Text(transform.name)
                            .font(.system(size: TypeScale.heading, weight: .medium))
                            .foregroundStyle(c(.bone))
                        if !transform.isBuiltIn {
                            Text("yours")
                                .font(.system(size: TypeScale.micro, weight: .medium))
                                .foregroundStyle(c(.verdigris))
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(Capsule().fill(c(.verdigris).opacity(0.14)))
                        }
                        Spacer(minLength: 8)
                        if model.canRestore(transform) {
                            Button { model.restore(transform) } label: {
                                Text("Reset")
                                    .font(.system(size: TypeScale.micro, weight: .medium))
                                    .foregroundStyle(c(.faint))
                            }.buttonStyle(.plain).help("Put the shipped wording back")
                        }
                        Button { model.beginEditing(transform) } label: {
                            Image(systemName: "pencil").font(.system(size: TypeScale.micro))
                                .foregroundStyle(c(.faint))
                        }.buttonStyle(.plain).help("Edit this transform")
                        if !transform.isBuiltIn {
                            Button { model.remove(transform) } label: {
                                Image(systemName: "xmark").font(.system(size: TypeScale.micro))
                                    .foregroundStyle(c(.faint))
                            }.buttonStyle(.plain).help("Delete")
                        }
                    }
                    if model.editingID == transform.id {
                        editor
                    } else {
                        Text(transform.instruction)
                            .font(.system(size: TypeScale.body))
                            .foregroundStyle(c(.muted))
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: 620, alignment: .leading)
                    }
                }
              }
            }
        }
        .frame(minHeight: 200)
    }

    // MARK: - Add

    private var addForm: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Add a transform").font(.system(size: TypeScale.body, weight: .semibold))
                .foregroundStyle(c(.bone))
            HStack(spacing: 9) {
                TextField("Name, what you will say", text: $model.draftName)
                    .textFieldStyle(.plain).font(.system(size: TypeScale.body))
                    .padding(8).frame(width: 200)
                    .background(RoundedRectangle(cornerRadius: Radius.control).fill(c(.surface))
                        .overlay(RoundedRectangle(cornerRadius: Radius.control).strokeBorder(c(.edge))))
                TextField("Instruction, what the model should do", text: $model.draftInstruction)
                    .textFieldStyle(.plain).font(.system(size: TypeScale.body))
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: Radius.control).fill(c(.surface))
                        .overlay(RoundedRectangle(cornerRadius: Radius.control).strokeBorder(c(.edge))))
                Button { model.add() } label: {
                    Text("Add").font(.system(size: TypeScale.small, weight: .medium))
                        .foregroundStyle(c(.ink))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: Radius.control).fill(c(.bone)))
                }
                .buttonStyle(.plain)
                .disabled(!model.canAdd)
                .opacity(model.canAdd ? 1 : 0.4)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Radius.surface).fill(c(.raised))
            .overlay(RoundedRectangle(cornerRadius: Radius.surface).strokeBorder(c(.edge))))
    }
}
