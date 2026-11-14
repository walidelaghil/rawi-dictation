import AppKit
import Combine
import SwiftUI

/// The app window: a left rail and a content pane.
///
/// The rail lists **only what is built**. A greyed-out row for an unbuilt screen
/// is dead UI — it teaches you to stop reading the rail. Later phases add their
/// own rows as they land.
@MainActor
public final class MainWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let selection = ScreenSelection()
    private var selected: Screen {
        get { selection.screen }
        set { selection.screen = newValue }
    }
    private let model: HistoryViewModel
    private let vocabulary: VocabularyViewModel
    private let destinations: DestinationsViewModel
    private let store: HistoryStore
    public let transforms: TransformsViewModel
    public let commands: CommandsViewModel
    public let insights: InsightsViewModel
    /// What setup still has outstanding, shown in the rail.
    public let setup = SetupChecklistModel()
    /// Opens the setup window at a step.
    public var onOpenSetup: ((SetupStep) -> Void)? {
        get { setup.onOpen }
        set { setup.onOpen = newValue }
    }
    public let settings: SettingsViewModel

    public init(store: HistoryStore, vocabularyStore: VocabularyStore,
                destinationStore: DestinationStore, transformStore: TransformStore,
                commandStore: CommandStore = CommandStore(), appearance: ResolvedAppearance) {
        self.store = store
        self.model = HistoryViewModel(store: store)
        self.vocabulary = VocabularyViewModel(store: vocabularyStore, history: store)
        self.destinations = DestinationsViewModel(store: destinationStore)
        self.transforms = TransformsViewModel(store: transformStore)
        self.commands = CommandsViewModel(store: commandStore)
        self.insights = InsightsViewModel(store: store)
        self.settings = SettingsViewModel()
        super.init()
        model.appearance = appearance
        vocabulary.appearance = appearance
        destinations.appearance = appearance
        transforms.appearance = appearance
        commands.appearance = appearance
        insights.appearance = appearance
        settings.appearance = appearance
    }

    /// Opens on a particular screen — the gear in the menu panel opens Settings.
    public func show(_ screen: Screen? = nil) {
        if let screen { selected = screen }
        observeClose()
        reload()
        let window = window ?? makeWindow()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// ⌘F: the search box, wherever you were.
    public func focusSearch() {
        show(.history)
        model.focusSearch()
    }

    public func setAppearance(_ appearance: ResolvedAppearance) {
        model.appearance = appearance
        vocabulary.appearance = appearance
        destinations.appearance = appearance
        transforms.appearance = appearance
        commands.appearance = appearance
        insights.appearance = appearance
        settings.appearance = appearance
        window?.appearance = NSAppearance(named: appearance == .dark ? .darkAqua : .aqua)
    }

    /// Re-runs a failed dictation from the audio it kept.
    public var onRetry: ((HistoryEntry) -> Void)? {
        get { model.onRetry }
        set { model.onRetry = newValue }
    }

    /// Every screen that prints a shortcut reads it from here.
    public func setLabels(_ labels: HotkeyLabels) {
        model.labels = labels
        transforms.labels = labels
    }

    public func reload() {
        model.reload()
        vocabulary.reload()
        destinations.reload()
        transforms.reload()
        insights.reload()
        settings.reload()
    }

    /// Esc reaches AppKit through the model, because a SwiftUI view cannot close
    /// the window it is hosted in.
    private var closeObserver: AnyCancellable?
    private func observeClose() {
        guard closeObserver == nil else { return }
        closeObserver = selection.$closeToken
            .dropFirst()
            .sink { [weak self] _ in self?.window?.performClose(nil) }
    }

    /// The window's content, for the proof renders. Rendering a screen on its own
    /// hides density problems that only appear next to the rail at 980 points.
    public func testRootView() -> some View {
        MainWindowView(history: model, vocabulary: vocabulary, destinations: destinations,
                       transforms: transforms, commands: commands, insights: insights,
                       settings: settings, selection: selection, setup: setup)
    }

    public func close() { window?.close() }

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
        selection.closeToken = 0
        window.contentView = NSHostingView(
            rootView: MainWindowView(history: model, vocabulary: vocabulary,
                                     destinations: destinations, transforms: transforms,
                                     commands: commands, insights: insights, settings: settings,
                                     selection: selection, setup: setup))
        window.appearance = NSAppearance(
            named: model.appearance == .dark ? .darkAqua : .aqua)
        return window
    }
}

/// Which screen is showing, held outside the view so the menu bar can open one.
@MainActor
public final class ScreenSelection: ObservableObject {
    @Published var screen: Screen = .history
    /// Bumped to ask the window to close itself from inside SwiftUI.
    @Published var closeToken = 0
}

public enum Screen: String, CaseIterable {
    case history = "History"
    case transforms = "Transforms"
    case commands = "Commands"
    case insights = "Insights"
    case dictionary = "Dictionary"
    case snippets = "Snippets"
    case destinations = "Destinations"
    case settings = "Settings"

    var symbol: String {
        switch self {
        case .history: "clock"
        case .transforms: "wand.and.sparkles"
        case .commands: "bolt"
        case .insights: "chart.bar"
        case .dictionary: "character.book.closed"
        case .snippets: "scissors"
        case .destinations: "scope"
        case .settings: "gearshape"
        }
    }
}

struct MainWindowView: View {
    @ObservedObject var history: HistoryViewModel
    @ObservedObject var vocabulary: VocabularyViewModel
    @ObservedObject var destinations: DestinationsViewModel
    @ObservedObject var transforms: TransformsViewModel
    @ObservedObject var commands: CommandsViewModel
    @ObservedObject var insights: InsightsViewModel
    @ObservedObject var settings: SettingsViewModel
    @ObservedObject var selection: ScreenSelection
    @ObservedObject var setup: SetupChecklistModel
    private var screen: Screen { selection.screen }

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
            case .commands: CommandsView(model: commands)
            case .insights: InsightsView(model: insights)
            case .dictionary: DictionaryScreen(model: vocabulary)
            case .snippets: SnippetsScreen(model: vocabulary)
            case .destinations: DestinationsView(model: destinations)
            case .settings: SettingsView(model: settings)
            }
        }
        .background(c(.surface))
        .onExitCommand { selection.closeToken += 1 }
    }

    private var rail: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                RawiMarkShape()
                    .stroke(c(.saffron), style: RawiMarkShape.stroke(for: 20))
                    .frame(width: 20, height: 20)
                    .accessibilityHidden(true)
                Wordmark(appearance: history.appearance)
            }
            .padding(.horizontal, 10).padding(.top, 6).padding(.bottom, 16)

            // Only built screens appear. A greyed row for an unbuilt phase is dead
            // UI that teaches you to stop reading the rail.
            ForEach(Screen.allCases, id: \.self) { item in
                Button { selection.screen = item } label: {
                    railRow(item.rawValue, symbol: item.symbol, selected: screen == item,
                            shortcut: (Screen.allCases.firstIndex(of: item) ?? 0) + 1)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            SetupChecklistCard(model: setup, appearance: history.appearance)

            let privacy = PrivacyNote.describe(settings.config)
            VStack(alignment: .leading, spacing: 3) {
                Text(privacy.title)
                    .font(.system(size: TypeScale.small, weight: .semibold))
                    .foregroundStyle(c(.verdigris))
                Text(privacy.detail)
                    .font(.system(size: TypeScale.small))
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

    private func railRow(_ title: String, symbol: String, selected: Bool,
                         shortcut: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: TypeScale.heading))
            Text(title).font(.system(size: TypeScale.body, weight: selected ? .medium : .regular))
            Spacer()
            // The shortcut lives next to the thing it opens, which is how anyone
            // ever learns one.
            Text("⌘\(shortcut)")
                .font(.system(size: TypeScale.micro).monospaced())
                .foregroundStyle(selected ? c(.muted) : c(.faint))
        }
        .foregroundStyle(selected ? c(.bone) : c(.muted))
        .padding(.horizontal, 9).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: Radius.control)
            .fill(selected ? c(.raised) : .clear))
    }
}


/// The rail's "Complete setup" list.
@MainActor
public final class SetupChecklistModel: ObservableObject {
    @Published public var checklist: SetupChecklist?
    public var onOpen: ((SetupStep) -> Void)?
    public init() {}
}

struct SetupChecklistCard: View {
    @ObservedObject var model: SetupChecklistModel
    let appearance: ResolvedAppearance
    private func c(_ t: ColorToken) -> Color { RawiColors.color(t, appearance) }

    var body: some View {
        if let checklist = model.checklist, !checklist.isComplete {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Text("Complete setup")
                        .font(.system(size: TypeScale.small, weight: .semibold))
                        .foregroundStyle(c(.saffron))
                    Spacer()
                    Text("\(checklist.items.count - checklist.outstanding.count)/\(checklist.items.count)")
                        .font(.system(size: TypeScale.micro).monospacedDigit())
                        .foregroundStyle(c(.faint))
                }
                ForEach(checklist.items) { item in
                    Button { model.onOpen?(item.step) } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 7) {
                            Image(systemName: item.done ? "checkmark.circle.fill"
                                  : item.required ? "exclamationmark.circle" : "circle")
                                .font(.system(size: TypeScale.small))
                                .foregroundStyle(item.done ? c(.verdigris)
                                                 : item.required ? c(.clay) : c(.faint))
                            Text(item.title)
                                .font(.system(size: TypeScale.small))
                                .foregroundStyle(item.done ? c(.faint) : c(.bone))
                                .strikethrough(item.done, color: c(.faint))
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(item.done ? "Done" : item.detail)
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: Radius.control).fill(c(.raised))
                .overlay(RoundedRectangle(cornerRadius: Radius.control)
                    .strokeBorder(c(.saffron).opacity(checklist.isBlocked ? 0.55 : 0.3))))
            .padding(.bottom, 4)
        }
    }
}
