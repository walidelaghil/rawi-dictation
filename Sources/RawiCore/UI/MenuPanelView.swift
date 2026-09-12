import SwiftUI

@MainActor
public final class MenuPanelModel: ObservableObject {
    @Published public var state: DictationState = .idle
    @Published public var level: Double = 0
    @Published public var elapsed: Duration = .zero
    @Published public var detectedLanguage: String?
    @Published public var recent: [RecentDictation] = []
    @Published public var appearance: ResolvedAppearance = .dark
    @Published public var recentOpen: Bool = false

    public var onAction: ((String) -> Void)?
    public var onCopy: ((RecentDictation) -> Void)?
    public var onSettings: (() -> Void)?
    public var onOpenWindow: (() -> Void)?
    public var onQuit: (() -> Void)?

    public init() {}
}

/// The menu bar dropdown: one surface, sections divided by hairlines rather than
/// stacked as cards inside a card.
public struct MenuPanelView: View {
    @ObservedObject var model: MenuPanelModel
    @State private var hovered: String?

    public init(model: MenuPanelModel) { self.model = model }

    private func c(_ token: ColorToken) -> Color { RawiColors.color(token, model.appearance) }
    private var isLive: Bool { model.state.recordingMode != nil }

    public var body: some View {
        VStack(spacing: 0) {
            liveBlock
            Divider().overlay(c(.edge))
            actionStrip
            Divider().overlay(c(.edge))
            recentDisclosure
            if model.recentOpen { recentList }
            Divider().overlay(c(.edge))
            footer
        }
        .frame(width: 326)
        .background(c(.surface))
    }

    // MARK: - Live

    private var liveBlock: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                stateMark
                Text(PillLabel.text(for: model.state))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(c(.bone))
                Spacer()
                Text(isLive ? PillLabel.elapsed(model.elapsed) : "⌥Space")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(isLive ? c(.muted) : c(.faint))
            }

            if isLive {
                LevelStrip(level: model.level, accent: c(.saffron), idle: c(.edge))
                if let language = model.detectedLanguage {
                    HStack(spacing: 7) {
                        Text("DETECTED")
                            .font(.system(size: 9, weight: .medium).monospaced())
                            .tracking(1.4)
                            .foregroundStyle(c(.faint))
                        Text(language)
                            .font(.system(size: 10.5, weight: .semibold).monospaced())
                            .foregroundStyle(c(.lapis))
                    }
                }
            } else {
                Text("Hold the key anywhere. Language is detected for you.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(c(.faint))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 15)
        .padding(.top, 13)
        .padding(.bottom, 12)
    }

    @ViewBuilder private var stateMark: some View {
        let token = PillLabel.token(for: model.state)
        if isLive {
            Circle().fill(c(token)).frame(width: 8, height: 8)
                .overlay(Circle().stroke(c(token).opacity(0.22), lineWidth: 4))
        } else {
            Circle().strokeBorder(c(.faint), lineWidth: 1.5).frame(width: 8, height: 8)
        }
    }

    // MARK: - Actions

    private var actionStrip: some View {
        HStack(spacing: 0) {
            ForEach(Array(MenuActions.all.enumerated()), id: \.element.id) { index, action in
                if index > 0 { Rectangle().fill(c(.edge)).frame(width: 1, height: 34) }
                actionCell(action)
            }
        }
    }

    private func actionCell(_ action: MenuAction) -> some View {
        Button { model.onAction?(action.id) } label: {
            HStack(spacing: 7) {
                Image(systemName: action.symbol)
                    .font(.system(size: 13))
                    .foregroundStyle(action.id == "dictate" ? c(.saffron) : c(.faint))
                Text(action.shortcut)
                    .font(.system(size: 9.5).monospaced())
                    .foregroundStyle(c(.faint))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(hovered == action.id ? c(.raised) : .clear)
        .onHover { hovered = $0 ? action.id : (hovered == action.id ? nil : hovered) }
        // The name lives on hover AND on keyboard focus — a tooltip that only
        // answers to a mouse is not much of a label.
        .help(action.title)
        .accessibilityLabel(action.title)
        .overlay(alignment: .top) {
            if hovered == action.id {
                Text(action.title)
                    .font(.system(size: 10.5))
                    .foregroundStyle(c(.bone))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 5).fill(c(.ink))
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(c(.edge))))
                    .fixedSize()
                    .offset(y: -24)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.12), value: hovered)
    }

    // MARK: - Recent

    private var recentDisclosure: some View {
        Button { model.recentOpen.toggle() } label: {
            HStack(spacing: 9) {
                Text("RECENT")
                    .font(.system(size: 9, weight: .medium).monospaced())
                    .tracking(1.4)
                    .foregroundStyle(c(.faint))
                Spacer()
                Text(model.recentOpen ? "▾" : "▸")
                    .font(.system(size: 10))
                    .foregroundStyle(c(.faint))
            }
            .padding(.horizontal, 15).padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var recentList: some View {
        if model.recent.isEmpty {
            Text("Nothing yet today.")
                .font(.system(size: 11.5))
                .foregroundStyle(c(.faint))
                .padding(.horizontal, 15).padding(.bottom, 9)
        } else {
            VStack(spacing: 0) {
                ForEach(model.recent) { item in
                    Button { model.onCopy?(item) } label: {
                        HStack(spacing: 10) {
                            Text(item.script == .arabic ? "AR" : "EN")
                                .font(.system(size: 9, weight: .medium).monospaced())
                                .foregroundStyle(item.script == .arabic ? c(.lapis) : c(.faint))
                                .frame(width: 22, alignment: .leading)
                            Text(item.oneLine)
                                .font(.system(size: 12))
                                .foregroundStyle(c(.bone))
                                .lineLimit(1)
                                .environment(\.layoutDirection,
                                             item.script == .arabic ? .rightToLeft : .leftToRight)
                            Spacer(minLength: 8)
                            Text(item.timestamp)
                                .font(.system(size: 9.5).monospaced())
                                .foregroundStyle(c(.faint))
                        }
                        .padding(.horizontal, 15).padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Copy again")
                }
            }
            .padding(.bottom, 6)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 14) {
            Button { model.onOpenWindow?() } label: {
                Text("Open Rawi").font(.system(size: 12)).foregroundStyle(c(.muted))
            }
            .buttonStyle(.plain)
            Button { model.onSettings?() } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12))
                    .foregroundStyle(c(.muted))
            }
            .buttonStyle(.plain)
            .help("Settings")
            Spacer()
            Button { model.onQuit?() } label: {
                Text("Quit").font(.system(size: 12)).foregroundStyle(c(.faint))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 15).padding(.vertical, 9)
        .background(c(.ink))
    }
}

/// The level meter as it appears in the menu — wider and flatter than the pill's.
struct LevelStrip: View {
    let level: Double
    let accent: Color
    let idle: Color

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<34, id: \.self) { index in
                let lit = pow(min(max(level, 0), 1), 0.6) * 34 > Double(index)
                Capsule()
                    .fill(lit ? accent : idle)
                    .frame(width: 2, height: barHeight(index))
            }
        }
        .frame(height: 15)
        .animation(.linear(duration: 0.05), value: level)
    }

    private func barHeight(_ index: Int) -> CGFloat {
        let mid = 16.5
        let distance = abs(Double(index) - mid) / mid
        return 4 + (1 - distance) * 10
    }
}
