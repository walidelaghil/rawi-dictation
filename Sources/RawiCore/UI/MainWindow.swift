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
    private let store: HistoryStore

    public init(store: HistoryStore, appearance: ResolvedAppearance) {
        self.store = store
        self.model = HistoryViewModel(store: store)
        super.init()
        model.appearance = appearance
    }

    public func show() {
        model.reload()
        let window = window ?? makeWindow()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func setAppearance(_ appearance: ResolvedAppearance) {
        model.appearance = appearance
        window?.appearance = NSAppearance(named: appearance == .dark ? .darkAqua : .aqua)
    }

    public func reload() { model.reload() }

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
        window.contentView = NSHostingView(rootView: MainWindowView(history: model))
        window.appearance = NSAppearance(
            named: model.appearance == .dark ? .darkAqua : .aqua)
        return window
    }
}

struct MainWindowView: View {
    @ObservedObject var history: HistoryViewModel

    private func c(_ token: ColorToken) -> Color {
        RawiColors.color(token, history.appearance)
    }

    var body: some View {
        HStack(spacing: 0) {
            rail
            Divider().overlay(c(.edge))
            HistoryView(model: history)
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

            railRow("History", symbol: "clock", selected: true)

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
