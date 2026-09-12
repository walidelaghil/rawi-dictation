import SwiftUI

@MainActor
public final class HistoryViewModel: ObservableObject {
    @Published public var entries: [HistoryEntry] = []
    @Published public var filter = HistoryFilter()
    @Published public var showInfo = false
    @Published public var confirmingPurge = false
    @Published public var appearance: ResolvedAppearance = .dark

    private let store: HistoryStore
    public init(store: HistoryStore) {
        self.store = store
        reload()
    }

    public func reload() { entries = store.all() }

    public var visible: [HistoryEntry] { HistorySearch.apply(filter, to: entries) }
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
            if !model.filter.query.isEmpty {
                Text("\(model.visible.count)")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(c(.faint))
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
        RowGroup(appearance: model.appearance) {
            ForEach(model.visible) { entry in
                Row(appearance: model.appearance) { row(entry) }
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
