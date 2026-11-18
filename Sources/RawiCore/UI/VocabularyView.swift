import SwiftUI

@MainActor
public final class VocabularyViewModel: ObservableObject {
    @Published public var terms: [DictionaryTerm] = []
    @Published public var snippets: [Snippet] = []
    @Published public var appearance: ResolvedAppearance = .dark
    @Published public var showInfo = false
    @Published public var newTerm = ""
    @Published public var newTrigger = ""
    @Published public var newExpansion = ""
    @Published public var newSensitive = false
    @Published public var query = ""
    @Published public var editingID: UUID?
    @Published public var editTrigger = ""
    @Published public var editExpansion = ""
    @Published public var editSensitive = false
    /// Shown as "Removed. Undo" for a few seconds after a delete.
    @Published public var undoMessage: String?
    private var undoAction: (() -> Void)?
    private var undoTask: Task<Void, Never>?

    private let store: VocabularyStore
    private let history: HistoryStore

    public init(store: VocabularyStore, history: HistoryStore) {
        self.store = store
        self.history = history
        reload()
    }

    public func reload() {
        terms = store.terms
        snippets = store.snippets
    }

    /// What the last refresh found, shown beside the button for a moment.
    @Published public var refreshResult: String?
    @Published public var refreshing = false

    /// Reads the dictionary again and re-runs learning over your history now,
    /// rather than waiting for the next dictation to do it.
    public func refresh() {
        refreshing = true
        store.reloadFromDisk()
        let before = Set(store.terms.map { $0.term.lowercased() })
        let learned = TermLearner.learn(from: history.all(), known: store.terms,
                                        blocked: store.blocked)
        let change = store.syncLearned(learned)
        reload()
        let added = terms.filter { !before.contains($0.term.lowercased()) }.count
        refreshResult = switch (added, change.dropped.count) {
        case (0, 0): "Up to date"
        case (let a, 0): "\(a) new"
        case (0, let d): "\(d) removed"
        case (let a, let d): "\(a) new, \(d) removed"
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            refreshing = false
            try? await Task.sleep(for: .seconds(2.5))
            refreshResult = nil
        }
    }

    public var learnedCount: Int { terms.filter(\.addedAutomatically).count }

    public func addTerm() {
        guard store.addTerm(newTerm) else { return }
        newTerm = ""
        reload()
    }
    public func removeTerm(_ term: DictionaryTerm) {
        let index = terms.firstIndex(of: term) ?? terms.count
        store.removeTerm(term.id); reload()
        offerUndo("Removed “\(term.term)”") { [store] in store.restoreTerm(term, at: index) }
    }

    private func offerUndo(_ message: String, _ action: @escaping () -> Void) {
        undoMessage = message
        undoAction = action
        undoTask?.cancel()
        undoTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(6))
            if !Task.isCancelled { undoMessage = nil; undoAction = nil }
        }
    }

    public func undo() {
        undoAction?()
        undoMessage = nil; undoAction = nil; undoTask?.cancel()
        reload()
    }

    public func addSnippet() {
        guard store.addSnippet(trigger: newTrigger, expansion: newExpansion,
                               sensitive: newSensitive) else { return }
        newTrigger = ""; newExpansion = ""; newSensitive = false
        reload()
    }
    public func removeSnippet(_ snippet: Snippet) {
        let index = snippets.firstIndex(of: snippet) ?? snippets.count
        store.removeSnippet(snippet.id); reload()
        offerUndo("Removed “\(snippet.trigger)”") { [store] in store.restoreSnippet(snippet, at: index) }
    }

    public var canAddSnippet: Bool {
        !newTrigger.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !newExpansion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var filteredSnippets: [Snippet] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return snippets }
        // A sensitive snippet matches on its trigger only: searching must not
        // reveal what is hidden.
        return snippets.filter {
            $0.trigger.localizedCaseInsensitiveContains(q)
                || (!$0.sensitive && $0.expansion.localizedCaseInsensitiveContains(q))
        }
    }

    public func beginEditing(_ snippet: Snippet) {
        editingID = snippet.id
        editTrigger = snippet.trigger; editExpansion = snippet.expansion
        editSensitive = snippet.sensitive
    }
    public func saveEdit() {
        guard let id = editingID,
              store.updateSnippet(id, trigger: editTrigger, expansion: editExpansion,
                                  sensitive: editSensitive) else { return }
        editingID = nil
        reload()
    }
    public func cancelEdit() { editingID = nil }
}

public struct DictionaryScreen: View {
    @ObservedObject var model: VocabularyViewModel
    public init(model: VocabularyViewModel) { self.model = model }
    private func c(_ t: ColorToken) -> Color { RawiColors.color(t, model.appearance) }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScreenHeader(title: "Dictionary", appearance: model.appearance,
                         showInfo: $model.showInfo,
                         info: "Rawi learns the names and jargon you use without being asked. "
                             + "When you fix a word it typed, say Sala to Salla, it learns the "
                             + "spelling you chose and uses it next time. It also notices names "
                             + "whisper spells differently from day to day. Ordinary English "
                             + "words are never learned: enforcing the wrong spelling is worse "
                             + "than enforcing none.",
                         trailing: AnyView(refreshButton))

            if model.terms.isEmpty {
                EmptyHint(title: "Nothing learned yet.",
                          detail: "Fix a name Rawi misspells, right after it types it, and the "
                                + "spelling appears here. You can also add one below.",
                          appearance: model.appearance)
            } else {
                RowGroup(appearance: model.appearance) {
                    ForEach(model.terms) { term in
                      TermRow(term: term, model: model)
                    }
                }
            }

            FormCard(appearance: model.appearance) {
                GrowingField(placeholder: "Add a term Rawi has not heard enough yet",
                             text: $model.newTerm, lines: 1...3,
                             size: TypeScale.heading, appearance: model.appearance)
                HStack {
                    Spacer()
                    PrimaryButton(title: "Add term",
                                  enabled: !model.newTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                                  appearance: model.appearance) { model.addTerm() }
                        .keyboardShortcut(.return, modifiers: .command)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 24).padding(.vertical, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(c(.surface))
        .overlay(alignment: .bottom) { undoToast(model) }
    }
}

/// Shared by Dictionary and Snippets.
@MainActor @ViewBuilder
func undoToast(_ model: VocabularyViewModel) -> some View {
    if let message = model.undoMessage {
        UndoToast(message: message, appearance: model.appearance) {
            withAnimation(.easeOut(duration: 0.15)) { model.undo() }
        }
        .padding(.bottom, 18)
    }
}

struct TermRow: View {
    let term: DictionaryTerm
    @ObservedObject var model: VocabularyViewModel
    @State private var hovered = false
    private func c(_ t: ColorToken) -> Color { RawiColors.color(t, model.appearance) }

    var body: some View {
        Row(appearance: model.appearance) {
            HStack(spacing: 14) {
                Text(term.term)
                    .font(.system(size: TypeScale.heading, weight: .medium))
                    .foregroundStyle(c(.bone))
                    .frame(minWidth: 150, alignment: .leading)
                    .fixedSize()
                Text(term.addedAutomatically
                     ? term.note
                     : (term.note.isEmpty ? "added by you" : term.note))
                    .font(.system(size: TypeScale.body))
                    .foregroundStyle(c(.muted))
                Spacer(minLength: 8)
                RemoveButton(visible: hovered,
                             label: "Remove \(term.term)" + (term.addedAutomatically
                                 ? ", and stop learning it" : ""),
                             appearance: model.appearance) { model.removeTerm(term) }
            }
        }
        .onHover { hovered = $0 }
    }
}

extension DictionaryScreen {
    var refreshButton: some View {
        HStack(spacing: 8) {
            if let result = model.refreshResult {
                Text(result)
                    .font(.system(size: TypeScale.small))
                    .foregroundStyle(c(.muted))
                    .transition(.opacity)
            }
            Button { model.refresh() } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: TypeScale.body, weight: .medium))
                    .foregroundStyle(c(.muted))
                    .rotationEffect(.degrees(model.refreshing ? 360 : 0))
                    .animation(model.refreshing ? .easeInOut(duration: 0.45) : nil,
                               value: model.refreshing)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: Radius.control).fill(c(.raised)))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Check your history for new terms now")
            .accessibilityLabel("Refresh dictionary")
        }
        .animation(.easeOut(duration: 0.15), value: model.refreshResult)
    }
}

struct SnippetRow: View {
    let snippet: Snippet
    @ObservedObject var model: VocabularyViewModel
    @State private var hovered = false
    @State private var revealed = false
    @State private var expanded = false
    private func c(_ t: ColorToken) -> Color { RawiColors.color(t, model.appearance) }
    private var editing: Bool { model.editingID == snippet.id }
    private var hidden: Bool { snippet.sensitive && !revealed }
    private var isLong: Bool { snippet.expansion.count > 140 || snippet.expansion.contains("\n") }

    var body: some View {
        if editing { editor } else { display }
    }

    private var display: some View {
        Row(appearance: model.appearance) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(snippet.trigger)
                        .font(.system(size: TypeScale.heading, weight: .medium))
                        .foregroundStyle(c(.bone))
                    if snippet.uses > 0 {
                        Text(snippet.uses == 1 ? "used once" : "used \(snippet.uses) times")
                            .font(.system(size: TypeScale.small)).foregroundStyle(c(.muted))
                    }
                }
                .frame(width: 150, alignment: .leading)
                Image(systemName: "arrow.right")
                    .font(.system(size: TypeScale.micro))
                    .foregroundStyle(c(.muted))
                    .padding(.top, 4)
                VStack(alignment: .leading, spacing: 4) {
                    if hidden {
                        Text("••••••••").font(.system(size: TypeScale.body)).foregroundStyle(c(.muted))
                    } else {
                        Text(snippet.expansion)
                            .font(.system(size: TypeScale.body))
                            .foregroundStyle(c(.bone))
                            .lineLimit(expanded ? nil : 3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !hidden, isLong {
                        Button(expanded ? "Show less" : "Show more") { expanded.toggle() }
                            .buttonStyle(.plain)
                            .font(.system(size: TypeScale.small)).foregroundStyle(c(.saffron))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if snippet.sensitive {
                    Button { revealed.toggle() } label: {
                        Image(systemName: revealed ? "eye.slash" : "eye")
                            .font(.system(size: TypeScale.body)).foregroundStyle(c(.muted))
                            .frame(width: 24, height: 24).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(revealed ? "Hide the text" : "Show the text")
                }
                RemoveButton(visible: hovered, label: "Delete the snippet for \(snippet.trigger)",
                             appearance: model.appearance) { model.removeSnippet(snippet) }
            }
        }
        .onHover { hovered = $0 }
        .onTapGesture { model.beginEditing(snippet) }
        .help("Click to edit")
    }

    private var editor: some View {
        FormCard(appearance: model.appearance) {
            GrowingField(placeholder: "When I say…", text: $model.editTrigger, lines: 1...2,
                         weight: .medium, size: TypeScale.heading, appearance: model.appearance)
            Rectangle().fill(c(.edge)).frame(height: 1)
            GrowingField(placeholder: "…type this", text: $model.editExpansion, lines: 2...8,
                         appearance: model.appearance)
            HStack(spacing: 12) {
                Toggle("Hide this text", isOn: $model.editSensitive)
                    .toggleStyle(.checkbox).font(.system(size: TypeScale.small))
                    .foregroundStyle(c(.muted))
                Spacer()
                Button("Cancel") { model.cancelEdit() }
                    .buttonStyle(.plain).font(.system(size: TypeScale.body))
                    .foregroundStyle(c(.muted))
                    .keyboardShortcut(.escape, modifiers: [])
                PrimaryButton(title: "Save", appearance: model.appearance) { model.saveEdit() }
                    .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(.horizontal, 8)
    }
}

public struct SnippetsScreen: View {
    @ObservedObject var model: VocabularyViewModel
    public init(model: VocabularyViewModel) { self.model = model }
    private func c(_ t: ColorToken) -> Color { RawiColors.color(t, model.appearance) }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScreenHeader(title: "Snippets", appearance: model.appearance,
                         showInfo: $model.showInfo,
                         info: "Say the phrase mid-dictation and it expands in place. Unlike a "
                             + "keyboard expander this only fires while you are speaking, so it "
                             + "cannot surprise you inside a word or a password field.")

            FormCard(appearance: model.appearance) {
                GrowingField(placeholder: "When I say…", text: $model.newTrigger, lines: 1...2,
                             weight: .medium, size: TypeScale.heading, appearance: model.appearance)
                Rectangle().fill(c(.edge)).frame(height: 1)
                GrowingField(placeholder: "…type this", text: $model.newExpansion, lines: 2...8,
                             appearance: model.appearance)
                HStack(spacing: 12) {
                    Toggle("Hide this text (passwords, card numbers)", isOn: $model.newSensitive)
                        .toggleStyle(.checkbox).font(.system(size: TypeScale.small))
                        .foregroundStyle(c(.muted))
                    Spacer()
                    PrimaryButton(title: "Add snippet", enabled: model.canAddSnippet,
                                  appearance: model.appearance) { model.addSnippet() }
                        .keyboardShortcut(.return, modifiers: .command)
                        .help("Add (⌘Return)")
                }
            }

            if model.snippets.count > 3 {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(c(.muted))
                    TextField("Search snippets", text: $model.query)
                        .textFieldStyle(.plain).font(.system(size: TypeScale.body))
                        .foregroundStyle(c(.bone))
                }
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: Radius.control).fill(c(.ink))
                    .overlay(RoundedRectangle(cornerRadius: Radius.control).strokeBorder(c(.edge))))
            }

            if model.snippets.isEmpty {
                EmptyHint(title: "No snippets yet.",
                          detail: "Try “my email” or “my calendar”. Anything you say often.",
                          appearance: model.appearance)
            } else if model.filteredSnippets.isEmpty {
                EmptyHint(title: "No snippet matches “\(model.query)”.", detail: "",
                          appearance: model.appearance)
            } else {
                RowGroup(appearance: model.appearance) {
                    ForEach(model.filteredSnippets) { SnippetRow(snippet: $0, model: model) }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 24).padding(.vertical, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(c(.surface))
        .overlay(alignment: .bottom) { undoToast(model) }
        .animation(.easeOut(duration: 0.15), value: model.undoMessage)
    }
}
// MARK: - Shared pieces

struct ScreenHeader: View {
    let title: String
    let appearance: ResolvedAppearance
    @Binding var showInfo: Bool
    let info: String
    var trailing: AnyView? = nil
    private func c(_ t: ColorToken) -> Color { RawiColors.color(t, appearance) }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                Text(title).font(.system(size: TypeScale.title, weight: .semibold)).foregroundStyle(c(.bone))
                Button { showInfo.toggle() } label: {
                    Image(systemName: "info.circle").font(.system(size: TypeScale.heading))
                        .foregroundStyle(c(.faint))
                }.buttonStyle(.plain).help("About \(title.lowercased())")
                Spacer()
                if let trailing { trailing }
            }
            if showInfo {
                Text(info)
                    .font(.system(size: TypeScale.small)).foregroundStyle(c(.muted))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(13)
                    .frame(maxWidth: 520, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: Radius.surface).fill(c(.raised))
                        .overlay(RoundedRectangle(cornerRadius: Radius.surface).strokeBorder(c(.edge))))
            }
        }
    }
}

struct EmptyHint: View {
    let title: String, detail: String, appearance: ResolvedAppearance
    private func c(_ t: ColorToken) -> Color { RawiColors.color(t, appearance) }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: TypeScale.heading)).foregroundStyle(c(.muted))
            Text(detail).font(.system(size: TypeScale.small)).foregroundStyle(c(.faint))
        }.padding(.top, 14)
    }
}

struct RowList<Content: View>: View {
    let appearance: ResolvedAppearance
    @ViewBuilder var content: Content
    private func c(_ t: ColorToken) -> Color { RawiColors.color(t, appearance) }
    var body: some View {
        ScrollView { LazyVStack(spacing: 0) { content } }
            .background(RoundedRectangle(cornerRadius: Radius.surface).fill(c(.raised))
                .overlay(RoundedRectangle(cornerRadius: Radius.surface).strokeBorder(c(.edge))))
    }
}

/// Wraps chips onto as many lines as they need.
struct FlowRow: Layout {
    var spacing: CGFloat = 7
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 400
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += lineHeight + spacing; lineHeight = 0 }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: width, height: y + lineHeight)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX; y += lineHeight + spacing; lineHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
