import SwiftUI

@MainActor
public final class HistoryViewModel: ObservableObject {
    @Published public var entries: [HistoryEntry] = []
    @Published public var filter = HistoryFilter()
    @Published public var showInfo = false
    public var undo: UndoCenter?
    @Published public var confirmingPurge = false
    @Published public var confirmingDelete = false
    @Published public var appearance: ResolvedAppearance = .dark
    /// The row the keyboard is on. Kept as an id rather than an index so a filter
    /// or a delete cannot silently move the selection to a different dictation.
    @Published public var selectedID: UUID?
    /// Bumped to ask the view to put the caret in the search field.
    @Published public var focusSearchToken = 0
    /// Bumped to ask the view to scroll the selection into sight.
    @Published public var scrollToken = 0
    @Published public var labels: HotkeyLabels = .placeholder
    /// Set by the app: re-runs a failed dictation from the audio it kept.
    public var onRetry: ((HistoryEntry) -> Void)?
    /// Puts the raw transcript back on the clipboard when cleanup rewrote you.
    public func useRaw(_ entry: HistoryEntry) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Transcript.clean(entry.raw), forType: .string)
    }

    private let store: HistoryStore
    /// The real cap, rather than a number typed into a sentence.
    public var limit: Int { store.cap }

    public init(store: HistoryStore) {
        self.store = store
        reload()
    }

    public func reload() { entries = store.all() }

    public var visible: [HistoryEntry] { HistorySearch.apply(filter, to: entries) }

    /// Nil whenever the selected row is not on screen, so the highlight can never
    /// point at something the filter is hiding.
    public var selected: HistoryEntry? {
        guard let selectedID else { return nil }
        return visible.first { $0.id == selectedID }
    }

    public enum EscapeOutcome: Equatable { case clearedSearch, clearedSelection, nothingToClear }

    /// Escape, in the order you want it: the search box first, then the selection.
    @discardableResult
    public func escape() -> EscapeOutcome {
        if !filter.query.isEmpty { filter.query = ""; return .clearedSearch }
        if selected != nil { selectedID = nil; return .clearedSelection }
        return .nothingToClear
    }

    /// Arrow keys. Stops at the ends: wrapping loses your place in a list you are
    /// scanning.
    public func moveSelection(by step: Int) {
        let rows = visible
        guard !rows.isEmpty else { selectedID = nil; return }
        guard let current = selected, let index = rows.firstIndex(of: current) else {
            selectedID = (step > 0 ? rows.first : rows.last)?.id
            scrollToken += 1
            return
        }
        let next = min(max(index + step, 0), rows.count - 1)
        selectedID = rows[next].id
        scrollToken += 1
    }

    @discardableResult
    public func copySelected() -> Bool {
        guard let entry = selected else { return false }
        copy(entry)
        return true
    }

    /// Deleting keeps your place: the row below takes the selection, or the row
    /// above when you were at the bottom.
    public func deleteSelected() {
        guard let entry = selected else { return }
        let rows = visible
        let index = rows.firstIndex(of: entry)
        delete(entry)
        let remaining = visible
        guard !remaining.isEmpty, let index else { selectedID = nil; return }
        selectedID = remaining[min(index, remaining.count - 1)].id
    }

    public func focusSearch() { focusSearchToken += 1 }
    public var apps: [(id: String, name: String)] { HistorySearch.apps(in: entries) }

    public func copy(_ entry: HistoryEntry) {
        NSPasteboard.general.clearContents()
        // Cleaned on the way out, not on the way in: entries recorded before the
        // server's segment breaks were joined still hold them, and pasting one
        // should give you the sentence you spoke, not the four lines it arrived in.
        NSPasteboard.general.setString(Transcript.clean(entry.cleaned), forType: .string)
    }
    public func delete(_ entry: HistoryEntry) {
        store.remove(entry.id); reload()
        undo?.offer("Deleted that dictation") { [store, weak self] in
            store.restore(entry); self?.reload()
        }
    }
    public func purge() { store.purge(); reload(); confirmingPurge = false }
}

public struct HistoryView: View {
    @ObservedObject var model: HistoryViewModel
    @FocusState private var searchFocused: Bool
    public init(model: HistoryViewModel) { self.model = model }

    private func c(_ token: ColorToken) -> Color { RawiColors.color(token, model.appearance) }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            search
            filters
            if model.visible.isEmpty { emptyState } else { list }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(c(.surface))
        // The list owns the arrows, Return and Delete once the search box does not.
        // The ring is suppressed: a focus ring around an entire screen is not
        // telling anyone anything, and it drew a blue line down the window.
        .focusable(!searchFocused)
        .focusEffectDisabled()
        .onKeyPress(.upArrow) { model.moveSelection(by: -1); return .handled }
        .onKeyPress(.downArrow) { model.moveSelection(by: 1); return .handled }
        .onKeyPress(.return) { model.copySelected() ? .handled : .ignored }
        // Confirmed, like Clear all. It was the only destructive action in the app
        // without a guard, and the easiest one to hit by accident.
        .onKeyPress(.delete) {
            guard model.selected != nil else { return .ignored }
            model.confirmingDelete = true
            return .handled
        }
        .onKeyPress(.escape) {
            model.escape() == .nothingToClear ? .ignored : .handled
        }
        .onChange(of: model.focusSearchToken) { _, _ in searchFocused = true }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("History")
                    .font(.system(size: TypeScale.title, weight: .semibold))
                    .foregroundStyle(c(.bone))
                Text("Everything you dictated. It stays on this Mac.")
                    .font(.system(size: TypeScale.body)).foregroundStyle(c(.muted))
            }
            Spacer()
            Button { model.confirmingPurge = true } label: {
                Text("Clear all").font(.system(size: TypeScale.body)).foregroundStyle(c(.clay))
            }
            .buttonStyle(.plain)
            .confirmationDialog(
                "Delete this dictation?",
                isPresented: $model.confirmingDelete,
                presenting: model.selected
            ) { entry in
                Button("Delete", role: .destructive) { model.deleteSelected() }
                Button("Keep", role: .cancel) { }
            } message: { entry in
                Text(entry.oneLine)
            }
            .confirmationDialog("Delete every stored dictation?",
                                isPresented: $model.confirmingPurge) {
                Button("Delete \(model.entries.count) entries", role: .destructive) {
                    model.purge()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The text is gone for good. Nothing else on your Mac is touched.")
            }
        }
    }

    // MARK: - Search and filters

    private var search: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: TypeScale.body)).foregroundStyle(c(.faint))
            TextField("Search what you said or what was typed", text: $model.filter.query)
                .textFieldStyle(.plain)
                .font(.system(size: TypeScale.heading))
                .foregroundStyle(c(.bone))
                .focused($searchFocused)
                .onSubmit { searchFocused = false }
                .onExitCommand { model.escape(); searchFocused = false }
            if !model.filter.query.isEmpty {
                Text("\(model.visible.count)")
                    .font(.system(size: TypeScale.small).monospacedDigit())
                    .foregroundStyle(c(.faint))
                Button { model.escape() } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: TypeScale.body))
                        .foregroundStyle(c(.faint))
                }
                .buttonStyle(.plain)
                .help("Clear")
            } else {
                Text("⌘F")
                    .font(.system(size: TypeScale.micro).monospaced())
                    .foregroundStyle(c(.faint))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: Radius.control).fill(c(.ink))
            .overlay(RoundedRectangle(cornerRadius: Radius.control).strokeBorder(c(.edge))))
    }

    /// Languages are two chips; apps are one menu. An app per chip squeezed a dozen
    /// capsules into one row until the names wrapped a letter per line.
    private var filters: some View {
        HStack(spacing: 8) {
            chip("All", active: model.filter.script == nil && model.filter.bundleID == nil) {
                model.filter.script = nil; model.filter.bundleID = nil
            }
            chip("English", active: model.filter.script == .latin) {
                model.filter.script = model.filter.script == .latin ? nil : .latin
            }
            chip("العربية", active: model.filter.script == .arabic) {
                model.filter.script = model.filter.script == .arabic ? nil : .arabic
            }
            if !model.apps.isEmpty { appMenu }
            Spacer(minLength: 8)
            Text("\(model.entries.count) kept")
                .font(.system(size: TypeScale.small).monospacedDigit())
                .foregroundStyle(c(.faint))
                .lineLimit(1)
                .fixedSize()
        }
    }

    private var appMenu: some View {
        let selected = model.apps.first { $0.id == model.filter.bundleID }
        return Menu {
            Button("All apps") { model.filter.bundleID = nil }
            Divider()
            ForEach(model.apps, id: \.id) { app in
                Button {
                    model.filter.bundleID = app.id
                } label: {
                    if app.id == model.filter.bundleID {
                        Label(app.name, systemImage: "checkmark")
                    } else {
                        Text(app.name)
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(selected?.name ?? "All apps")
                Image(systemName: "chevron.down").font(.system(size: TypeScale.micro, weight: .semibold))
            }
            .font(.system(size: TypeScale.small))
            .foregroundStyle(selected != nil ? c(.bone) : c(.muted))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(selected != nil ? c(.raised) : .clear)
                .overlay(Capsule().strokeBorder(selected != nil ? c(.saffron) : c(.edge))))
            .contentShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func chip(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: TypeScale.small))
                .foregroundStyle(active ? c(.bone) : c(.muted))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(active ? c(.raised) : .clear)
                    .overlay(Capsule().strokeBorder(active ? c(.saffron) : c(.edge))))
        }
        .buttonStyle(.plain)
    }

    // MARK: - List

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.entries.isEmpty ? "Nothing dictated yet." : "No matches.")
                .font(.system(size: TypeScale.heading)).foregroundStyle(c(.muted))
            Text(model.entries.isEmpty
                 ? "Hold \(model.labels.dictate) anywhere and speak."
                 : "Try a word you remember saying. Search covers the raw transcript too.")
                .font(.system(size: TypeScale.small)).foregroundStyle(c(.faint))
        }
        .padding(.top, 20)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            RowGroup(appearance: model.appearance) {
                ForEach(model.visible) { entry in
                    Row(appearance: model.appearance,
                        selected: entry.id == model.selectedID) { row(entry) }
                        .id(entry.id)
                        .onTapGesture { model.selectedID = entry.id }
                }
            }
            .onChange(of: model.scrollToken) { _, _ in
                guard let id = model.selected?.id else { return }
                withAnimation(.easeOut(duration: 0.14)) { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }

    private func row(_ entry: HistoryEntry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(entry.timestamp)
                .font(.system(size: TypeScale.small).monospacedDigit())
                .foregroundStyle(c(.faint))
                .frame(width: 36, alignment: .leading)
                .padding(.top, 1)

            Text(entry.script == .arabic ? "AR" : "EN")
                .font(.system(size: TypeScale.micro, weight: .medium).monospaced())
                .foregroundStyle(entry.script == .arabic ? c(.lapis) : c(.faint))
                .frame(width: 22, alignment: .leading)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                if entry.kind == .failed {
                    Text(entry.failure ?? "Something went wrong")
                        .font(.system(size: TypeScale.body))
                        .foregroundStyle(c(.clay))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(entry.isRetryable
                         ? "Your recording was kept."
                         : "The recording has since been cleaned up.")
                        .font(.system(size: TypeScale.small))
                        .foregroundStyle(c(.faint))
                } else {
                    Text(entry.oneLine)
                        .font(.system(size: TypeScale.body))
                        .foregroundStyle(c(.bone))
                        .environment(\.layoutDirection,
                                     entry.script == .arabic ? .rightToLeft : .leftToRight)
                        .fixedSize(horizontal: false, vertical: true)
                    if entry.guardRejected {
                        Text("cleanup rejected, your words were kept")
                            .font(.system(size: TypeScale.small))
                            .foregroundStyle(c(.clay))
                    } else if entry.wasCleaned {
                        Text("heard: \(entry.raw)")
                            .font(.system(size: TypeScale.small))
                            .foregroundStyle(c(.muted))
                            .environment(\.layoutDirection,
                                         entry.script == .arabic ? .rightToLeft : .leftToRight)
                            .lineLimit(2)
                    }
                }
            }

            Spacer(minLength: 8)

            if let app = entry.appName {
                Text(app).font(.system(size: TypeScale.small)).foregroundStyle(c(.faint))
                    .padding(.top, 1)
            }

            if entry.kind == .failed {
                if entry.isRetryable {
                    Button { model.onRetry?(entry) } label: {
                        Text("Retry").font(.system(size: TypeScale.small, weight: .medium))
                            .foregroundStyle(c(.ink))
                            .padding(.horizontal, 10).padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: Radius.control)
                                .fill(c(.saffron)))
                    }
                    .buttonStyle(.plain)
                    .help("Transcribe the recording again")
                }
            } else {
                // The way back from a rewrite. The guard detects it and the row
                // shows it; this is the control that acts on it.
                if entry.wasCleaned {
                    Button { model.useRaw(entry) } label: {
                        Text("Use what I said")
                            .font(.system(size: TypeScale.small))
                            .foregroundStyle(c(.muted))
                            .padding(.horizontal, 9).padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: Radius.control)
                                .strokeBorder(c(.edge)))
                    }
                    .buttonStyle(.plain)
                    .help("Copy the raw transcript instead of the cleaned text")
                }
                Button { model.copy(entry) } label: {
                    Text("Copy").font(.system(size: TypeScale.small)).foregroundStyle(c(.muted))
                        .padding(.horizontal, 9).padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: Radius.control)
                            .strokeBorder(c(.edge)))
                }
                .buttonStyle(.plain)
                .help("Copy this text")
            }

            Button { model.delete(entry) } label: {
                Image(systemName: "xmark").font(.system(size: TypeScale.small))
                    .foregroundStyle(c(.muted)).frame(width: 24, height: 24).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Delete this entry")
            .accessibilityLabel("Delete this entry")
        }
    }
}
