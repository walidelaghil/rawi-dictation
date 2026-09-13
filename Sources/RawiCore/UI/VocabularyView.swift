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

    public var learnedCount: Int { terms.filter(\.addedAutomatically).count }

    public func addTerm() {
        guard store.addTerm(newTerm) else { return }
        newTerm = ""
        reload()
    }
    public func removeTerm(_ term: DictionaryTerm) { store.removeTerm(term.id); reload() }

    public func addSnippet() {
        guard store.addSnippet(trigger: newTrigger, expansion: newExpansion) else { return }
        newTrigger = ""; newExpansion = ""
        reload()
    }
    public func removeSnippet(_ snippet: Snippet) { store.removeSnippet(snippet.id); reload() }
}

public struct DictionaryScreen: View {
    @ObservedObject var model: VocabularyViewModel
    public init(model: VocabularyViewModel) { self.model = model }
    private func c(_ t: ColorToken) -> Color { RawiColors.color(t, model.appearance) }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScreenHeader(title: "Dictionary", appearance: model.appearance,
                         showInfo: $model.showInfo,
                         info: "Rawi learns the names and jargon you actually use, from your "
                             + "own history. A word has to recur over several days before it "
                             + "counts, and anything close to an ordinary English word is "
                             + "refused: enforcing the wrong spelling is worse than enforcing "
                             + "none. Terms are applied as a hint to whisper, as a glossary for "
                             + "the cleanup model, and as a direct correction in code. Only the "
                             + "third always works.")

            if model.terms.isEmpty {
                EmptyHint(title: "Nothing learned yet.",
                          detail: "Say a name a few times over a few days and it appears here. "
                                + "You can also add one below.",
                          appearance: model.appearance)
            } else {
                RowGroup(appearance: model.appearance) {
                    ForEach(model.terms) { term in
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
                                .foregroundStyle(c(.faint))
                            Spacer(minLength: 8)
                            Button { model.removeTerm(term) } label: {
                                Image(systemName: "xmark").font(.system(size: TypeScale.micro))
                                    .foregroundStyle(c(.faint))
                            }
                            .buttonStyle(.plain)
                            .help(term.addedAutomatically
                                  ? "Remove, and stop learning this word"
                                  : "Remove")
                        }
                      }
                    }
                }
            }

            HStack(spacing: 9) {
                TextField("Add a term Rawi has not heard enough yet", text: $model.newTerm)
                    .textFieldStyle(.plain).font(.system(size: TypeScale.heading))
                    .foregroundStyle(c(.bone))
                    .onSubmit { model.addTerm() }
                Button("Add") { model.addTerm() }
                    .buttonStyle(.plain)
                    .font(.system(size: TypeScale.body)).foregroundStyle(c(.saffron))
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: Radius.control).fill(c(.ink))
                .overlay(RoundedRectangle(cornerRadius: Radius.control)
                    .strokeBorder(c(.edge))))

            Spacer()
        }
        .padding(.horizontal, 24).padding(.vertical, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(c(.surface))
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

            HStack(spacing: 9) {
                TextField("When I say…", text: $model.newTrigger)
                    .textFieldStyle(.plain).font(.system(size: TypeScale.heading)).foregroundStyle(c(.bone))
                    .frame(width: 170)
                Text("→").foregroundStyle(c(.faint))
                TextField("…type this", text: $model.newExpansion)
                    .textFieldStyle(.plain).font(.system(size: TypeScale.heading)).foregroundStyle(c(.bone))
                    .onSubmit { model.addSnippet() }
                Button("Add") { model.addSnippet() }
                    .buttonStyle(.plain).font(.system(size: TypeScale.body)).foregroundStyle(c(.saffron))
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: Radius.control).fill(c(.ink))
                .overlay(RoundedRectangle(cornerRadius: Radius.control).strokeBorder(c(.edge))))

            if model.snippets.isEmpty {
                EmptyHint(title: "No snippets yet.",
                          detail: "Try “my email” or “my calendar”. Anything you say often.",
                          appearance: model.appearance)
            } else {
                RowGroup(appearance: model.appearance) {
                    ForEach(model.snippets) { snippet in
                        HStack(spacing: 11) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("“\(snippet.trigger)”").font(.system(size: TypeScale.heading))
                                    .foregroundStyle(c(.bone))
                                Text("→ \(snippet.expansion)")
                                    .font(.system(size: TypeScale.small).monospaced())
                                    .foregroundStyle(c(.faint)).lineLimit(1)
                            }
                            Spacer()
                            Button { model.removeSnippet(snippet) } label: {
                                Image(systemName: "xmark").font(.system(size: TypeScale.micro))
                                    .foregroundStyle(c(.faint))
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 24).padding(.vertical, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(c(.surface))
    }
}

// MARK: - Shared pieces

struct ScreenHeader: View {
    let title: String
    let appearance: ResolvedAppearance
    @Binding var showInfo: Bool
    let info: String
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
