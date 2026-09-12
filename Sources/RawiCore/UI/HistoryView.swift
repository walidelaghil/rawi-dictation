import SwiftUI

@MainActor
public final class HistoryViewModel: ObservableObject {
    @Published public var entries: [HistoryEntry] = []
    @Published public var filter = HistoryFilter()
    @Published public var showInfo = false
    @Published public var confirmingPurge = false
    @Published public var appearance: ResolvedAppearance = .dark
    /// The row the keyboard is on. Kept as an id rather than an index so a filter
    /// or a delete cannot silently move the selection to a different dictation.
    @Published public var selectedID: UUID?
    /// Bumped to ask the view to put the caret in the search field.
    @Published public var focusSearchToken = 0
    /// Bumped to ask the view to scroll the selection into sight.
    @Published public var scrollToken = 0

    private let store: HistoryStore
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
        NSPasteboard.general.setString(entry.cleaned, forType: .string)
    }
    public func delete(_ entry: HistoryEntry) { store.remove(entry.id); reload() }
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
        .overlay(alignment: .topLeading) { if model.showInfo { infoOverlay } }
        // The list owns the arrows, Return and Delete once the search box does not.
        .focusable(!searchFocused)
        .onKeyPress(.upArrow) { model.moveSelection(by: -1); return .handled }
        .onKeyPress(.downArrow) { model.moveSelection(by: 1); return .handled }
        .onKeyPress(.return) { model.copySelected() ? .handled : .ignored }
        .onKeyPress(.delete) { model.deleteSelected(); return .handled }
        .onKeyPress(.escape) {
            model.escape() == .nothingToClear ? .ignored : .handled
        }
        .onChange(of: model.focusSearchToken) { _, _ in searchFocused = true }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .lastTextBaseline, spacing: 10) {
            Text("History")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(c(.bone))
            Button { model.showInfo.toggle() } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(c(.faint))
            }
            .buttonStyle(.plain)
            .help("About history")
            Spacer()
            Button { model.confirmingPurge = true } label: {
                Text("Clear all").font(.system(size: 12)).foregroundStyle(c(.clay))
            }
            .buttonStyle(.plain)
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

    /// The explanation sits behind the ⓘ because it is scaffolding you stop
    /// needing — on screen it would be permanent clutter.
    private var infoOverlay: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text("About history").font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(c(.bone))
                Spacer()
                Button { model.showInfo = false } label: {
                    Text("×").font(.system(size: 15)).foregroundStyle(c(.faint))
                }.buttonStyle(.plain)
            }
            Text("Both the cleaned text and what whisper actually heard. Search covers "
               + "both, which is what you need when you remember what you said rather "
               + "than what came out. "
               + "Capped at \(model.entries.count > 0 ? "500" : "500") entries; password "
               + "managers and private messages are never recorded.")
                .font(.system(size: 11.5))
                .foregroundStyle(c(.muted))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(15)
        .frame(width: 380, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.surface).fill(c(.raised))
            .overlay(RoundedRectangle(cornerRadius: Radius.surface).strokeBorder(c(.edge))))
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
        .offset(x: 0, y: 52)
    }

    // MARK: - Search and filters

    private var search: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12)).foregroundStyle(c(.faint))
            TextField("Search what you said or what was typed", text: $model.filter.query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(c(.bone))
                .focused($searchFocused)
                .onSubmit { searchFocused = false }
                .onExitCommand { model.escape(); searchFocused = false }
            if !model.filter.query.isEmpty {
                Text("\(model.visible.count)")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(c(.faint))
                Button { model.escape() } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 12))
                        .foregroundStyle(c(.faint))
                }
                .buttonStyle(.plain)
                .help("Clear")
            } else {
                Text("⌘F")
                    .font(.system(size: 10).monospaced())
                    .foregroundStyle(c(.faint).opacity(0.7))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: Radius.control).fill(c(.ink))
            .overlay(RoundedRectangle(cornerRadius: Radius.control).strokeBorder(c(.edge))))
    }

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
            ForEach(model.apps, id: \.id) { app in
                chip(app.name, active: model.filter.bundleID == app.id) {
                    model.filter.bundleID = model.filter.bundleID == app.id ? nil : app.id
                }
            }
            Spacer()
            Text("\(model.entries.count) kept")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(c(.faint))
        }
    }

    private func chip(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5))
                .foregroundStyle(active ? c(.bone) : c(.muted))
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
                .font(.system(size: 13)).foregroundStyle(c(.muted))
            Text(model.entries.isEmpty
                 ? "Hold ⌥Space anywhere and speak."
                 : "Try a word you remember saying. Search covers the raw transcript too.")
                .font(.system(size: 11.5)).foregroundStyle(c(.faint))
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
                .font(.system(size: 10.5).monospacedDigit())
                .foregroundStyle(c(.faint))
                .frame(width: 36, alignment: .leading)
                .padding(.top, 1)

            Text(entry.script == .arabic ? "AR" : "EN")
                .font(.system(size: 9, weight: .medium).monospaced())
                .foregroundStyle(entry.script == .arabic ? c(.lapis) : c(.faint))
                .frame(width: 22, alignment: .leading)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.oneLine)
                    .font(.system(size: 12.5))
                    .foregroundStyle(c(.bone))
                    .environment(\.layoutDirection,
                                 entry.script == .arabic ? .rightToLeft : .leftToRight)
                    .fixedSize(horizontal: false, vertical: true)
                if entry.guardRejected {
                    Text("cleanup rejected, your words were kept")
                        .font(.system(size: 10.5).monospaced())
                        .foregroundStyle(c(.clay))
                } else if entry.wasCleaned {
                    Text("heard · \(entry.raw)")
                        .font(.system(size: 10.5).monospaced())
                        .foregroundStyle(c(.faint))
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            if let app = entry.appName {
                Text(app).font(.system(size: 11)).foregroundStyle(c(.faint)).padding(.top, 1)
            }
            Button { model.copy(entry) } label: {
                Text("Copy").font(.system(size: 11)).foregroundStyle(c(.muted))
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: Radius.control)
                        .strokeBorder(c(.edge)))
            }
            .buttonStyle(.plain)
            Button { model.delete(entry) } label: {
                Image(systemName: "xmark").font(.system(size: 9))
                    .foregroundStyle(c(.faint))
            }
            .buttonStyle(.plain)
            .help("Delete this entry")
        }
    }
}
