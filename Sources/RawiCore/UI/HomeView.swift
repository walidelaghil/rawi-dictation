import AppKit
import SwiftUI

@MainActor
public final class HomeViewModel: ObservableObject {
    @Published public var usage = UsageInsights.compute(from: [])
    @Published public var recent: [HistoryEntry] = []
    @Published public var appearance: ResolvedAppearance = .dark
    @Published public var copiedID: UUID?
    /// Opens the full History screen.
    public var onShowHistory: (() -> Void)?
    private let store: HistoryStore

    public init(store: HistoryStore) { self.store = store; reload() }

    public func reload() {
        let all = store.all()
        usage = UsageInsights.compute(from: all)
        recent = Array(all.filter { $0.kind == .dictation }
            .sorted { $0.at > $1.at }.prefix(5))
    }

    public func copy(_ entry: HistoryEntry) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.cleaned, forType: .string)
        copiedID = entry.id
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            if copiedID == entry.id { copiedID = nil }
        }
    }
}

/// Where the app opens: what you said lately, and how much you have used it.
struct HomeView: View {
    @ObservedObject var model: HomeViewModel
    let labels: HotkeyLabels
    private func c(_ t: ColorToken) -> Color { RawiColors.color(t, model.appearance) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Home").font(.system(size: TypeScale.title, weight: .semibold))
                .foregroundStyle(c(.bone))

            HStack(spacing: 12) {
                tile("\(model.usage.words.formatted())", "words dictated")
                tile("\(model.usage.wordsPerMinute)", "words per minute")
                tile("\(model.usage.currentStreak)", model.usage.currentStreak == 1 ? "day streak" : "day streak")
            }

            HStack {
                Text("Recent").font(.system(size: TypeScale.heading, weight: .semibold))
                    .foregroundStyle(c(.bone))
                Spacer()
                if !model.recent.isEmpty {
                    Button("See all") { model.onShowHistory?() }
                        .buttonStyle(.plain).font(.system(size: TypeScale.body))
                        .foregroundStyle(c(.saffron))
                }
            }

            if model.recent.isEmpty {
                EmptyHint(title: "Nothing dictated yet.",
                          detail: "Hold \(labels.dictate) anywhere and talk. It will show up here.",
                          appearance: model.appearance)
            } else {
                RowGroup(appearance: model.appearance, scrolls: false) {
                    ForEach(model.recent) { entry in
                        HomeRow(entry: entry, model: model)
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 24).padding(.vertical, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(c(.surface))
    }

    private func tile(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.system(size: TypeScale.figure, weight: .semibold).monospacedDigit())
                .foregroundStyle(c(.bone))
            Text(label).font(.system(size: TypeScale.small)).foregroundStyle(c(.muted))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.surface).fill(c(.raised))
            .overlay(RoundedRectangle(cornerRadius: Radius.surface).strokeBorder(c(.edge))))
    }
}

private struct HomeRow: View {
    let entry: HistoryEntry
    @ObservedObject var model: HomeViewModel
    @State private var hovered = false
    private func c(_ t: ColorToken) -> Color { RawiColors.color(t, model.appearance) }

    var body: some View {
        Row(appearance: model.appearance) {
            HStack(alignment: .top, spacing: 14) {
                Text(entry.at, style: .time)
                    .font(.system(size: TypeScale.small).monospacedDigit())
                    .foregroundStyle(c(.muted))
                    .frame(width: 64, alignment: .leading)
                Text(entry.cleaned)
                    .font(.system(size: TypeScale.body)).foregroundStyle(c(.bone))
                    .lineLimit(2)
                    .environment(\.layoutDirection, entry.script == .arabic ? .rightToLeft : .leftToRight)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button { model.copy(entry) } label: {
                    Image(systemName: model.copiedID == entry.id ? "checkmark" : "doc.on.doc")
                        .font(.system(size: TypeScale.small, weight: .semibold))
                        .foregroundStyle(model.copiedID == entry.id ? c(.verdigris) : c(.saffron))
                        .frame(width: 24, height: 24).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(hovered || model.copiedID == entry.id ? 1 : 0)
                .accessibilityLabel("Copy this dictation")
            }
        }
        .onHover { hovered = $0 }
    }
}
