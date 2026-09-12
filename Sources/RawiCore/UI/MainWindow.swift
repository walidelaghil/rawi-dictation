import AppKit
import SwiftUI

/// The app window: a left rail and a content pane.
///
/// The rail lists **only what is built**. A greyed-out row for an unbuilt screen
/// is dead UI — it teaches you to stop reading the rail. Later phases add their
/// own rows as they land.
@MainActor
public final class MainWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let model: HistoryViewModel
    private let vocabulary: VocabularyViewModel
    private let destinations: DestinationsViewModel
    private let store: HistoryStore
    public let transforms: TransformsViewModel
    private let insights: InsightsViewModel

    public init(store: HistoryStore, vocabularyStore: VocabularyStore,
                destinationStore: DestinationStore, transformStore: TransformStore,
                appearance: ResolvedAppearance) {
        self.store = store
        self.model = HistoryViewModel(store: store)
        self.vocabulary = VocabularyViewModel(store: vocabularyStore, history: store)
        self.destinations = DestinationsViewModel(store: destinationStore)
        self.transforms = TransformsViewModel(store: transformStore)
        self.insights = InsightsViewModel(store: store)
        super.init()
        model.appearance = appearance
        vocabulary.appearance = appearance
        destinations.appearance = appearance
        transforms.appearance = appearance
        insights.appearance = appearance
    }

    public func show() {
        reload()
        let window = window ?? makeWindow()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func setAppearance(_ appearance: ResolvedAppearance) {
        model.appearance = appearance
        vocabulary.appearance = appearance
        destinations.appearance = appearance
        transforms.appearance = appearance
        insights.appearance = appearance
        window?.appearance = NSAppearance(named: appearance == .dark ? .darkAqua : .aqua)
    }

    public func reload() {
        model.reload()
        vocabulary.reload()
        destinations.reload()
        transforms.reload()
        insights.reload()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = "Rawi"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.minSize = NSSize(width: 760, height: 460)
        window.center()
        window.contentView = NSHostingView(
            rootView: MainWindowView(history: model, vocabulary: vocabulary,
                                     destinations: destinations, transforms: transforms,
                                     insights: insights))
        window.appearance = NSAppearance(
            named: model.appearance == .dark ? .darkAqua : .aqua)
        return window
    }
}

enum Screen: String, CaseIterable {
    case history = "History"
    case transforms = "Transforms"
    case insights = "Insights"
    case dictionary = "Dictionary"
    case snippets = "Snippets"
    case destinations = "Destinations"

    var symbol: String {
        switch self {
        case .history: "clock"
        case .transforms: "wand.and.sparkles"
        case .insights: "chart.bar"
        case .dictionary: "character.book.closed"
        case .snippets: "scissors"
        case .destinations: "scope"
        }
    }
}

struct MainWindowView: View {
    @ObservedObject var history: HistoryViewModel
    @ObservedObject var vocabulary: VocabularyViewModel
    @ObservedObject var destinations: DestinationsViewModel
    @ObservedObject var transforms: TransformsViewModel
    @ObservedObject var insights: InsightsViewModel
    @State private var screen: Screen = .history

    private func c(_ token: ColorToken) -> Color {
        RawiColors.color(token, history.appearance)
    }

    var body: some View {
        HStack(spacing: 0) {
            rail
            Divider().overlay(c(.edge))
            switch screen {
            case .history: HistoryView(model: history)
            case .transforms: TransformsView(model: transforms)
            case .insights: InsightsView(model: insights)
            case .dictionary: DictionaryScreen(model: vocabulary)
            case .snippets: SnippetsScreen(model: vocabulary)
            case .destinations: DestinationsView(model: destinations)
            }
        }
        .background(c(.surface))
    }

    private var rail: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text("Rawi").font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(c(.bone))
                Text("راوي").font(.system(size: 14))
                    .foregroundStyle(c(.faint))
                    .environment(\.layoutDirection, .rightToLeft)
            }
            .padding(.horizontal, 10).padding(.top, 6).padding(.bottom, 16)

            // Only built screens appear. A greyed row for an unbuilt phase is dead
            // UI that teaches you to stop reading the rail.
            ForEach(Screen.allCases, id: \.self) { item in
                Button { screen = item } label: {
                    railRow(item.rawValue, symbol: item.symbol, selected: screen == item)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            VStack(alignment: .leading, spacing: 3) {
                Text("Everything on device")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(c(.verdigris))
                Text("No account · no upload · no sync")
                    .font(.system(size: 10.5))
                    .foregroundStyle(c(.faint))
            }
            .padding(.horizontal, 10).padding(.top, 11)
            .overlay(alignment: .top) { Divider().overlay(c(.edge)) }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 14)
        .frame(width: 206)
        .background(c(.ink))
    }

    private func railRow(_ title: String, symbol: String, selected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 14))
            Text(title).font(.system(size: 12.5, weight: selected ? .medium : .regular))
            Spacer()
        }
        .foregroundStyle(selected ? c(.bone) : c(.muted))
        .padding(.horizontal, 9).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 7)
            .fill(selected ? c(.raised) : .clear))
    }
}
