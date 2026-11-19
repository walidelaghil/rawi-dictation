import SwiftUI

@MainActor
public final class MenuPanelModel: ObservableObject {
    @Published public var state: DictationState = .idle
    @Published public var level: Double = 0
    @Published public var peak: Double = 0
    @Published public var elapsed: Duration = .zero
    @Published public var detectedLanguage: String?
    @Published public var recent: [RecentDictation] = []
    @Published public var appearance: ResolvedAppearance = .dark
    @Published public var recentOpen: Bool = true
    @Published public var motion: MarkMotion = .rest
    /// The shortcuts as bound, not as defaulted.
    @Published public var labels: HotkeyLabels = .placeholder
    /// Set when something from setup is still outstanding. The footer then offers
    /// to finish it rather than opening the window on a screen that will not say so.
    @Published public var setupOutstanding: SetupChecklist?

    public var onAction: ((String) -> Void)?
    public var onCopy: ((RecentDictation) -> Void)?
    public var onSettings: (() -> Void)?
    public var onOpenWindow: (() -> Void)?
    public var onOpenSetup: (() -> Void)?
    public var onQuit: (() -> Void)?
    public var onUndo: (() -> Void)?
    @Published public var canUndo = false

    public init() {}
}

/// The menu bar dropdown: one surface, sections divided by hairlines rather than
/// stacked as cards inside a card.
public struct MenuPanelView: View {
    @ObservedObject var model: MenuPanelModel
    @State private var hovered: String?
    /// The Recent row that was just copied, so its icon can say so for a moment.
    @State private var copiedRow: Int?

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
                // At rest the panel says whose it is; the moment it has something
                // to report it says that instead. A header that reads "Rawi" while
                // it is transcribing would be branding over the truth.
                if model.state == .idle {
                    Wordmark(appearance: model.appearance)
                } else {
                    Text(PillLabel.text(for: model.state))
                        .font(.system(size: TypeScale.heading, weight: .semibold))
                        .foregroundStyle(c(.bone))
                }
                Spacer()
                Text(isLive ? PillLabel.elapsed(model.elapsed) : model.labels.dictate)
                    .font(.system(size: TypeScale.small).monospacedDigit())
                    .foregroundStyle(isLive ? c(.muted) : c(.faint))
            }

            if isLive {
                LevelStrip(level: model.level, peak: model.peak, accent: c(.saffron), idle: c(.edge),
                           peakColor: c(.bone))
                if let language = model.detectedLanguage {
                    HStack(spacing: 7) {
                        Text("DETECTED")
                            .font(.system(size: TypeScale.micro, weight: .medium).monospaced())
                            .tracking(1.4)
                            .foregroundStyle(c(.faint))
                        Text(language)
                            .font(.system(size: TypeScale.small, weight: .semibold).monospaced())
                            .foregroundStyle(c(.lapis))
                    }
                }
            } else {
                Text("Hold \(model.labels.dictate) anywhere. Language is detected for you.")
                    .font(.system(size: TypeScale.small))
                    .foregroundStyle(c(.faint))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 15)
        .padding(.top, 13)
        .padding(.bottom, 12)
    }

    /// The Rawi mark, tinted by state — the same glyph and the same colours as the
    /// menu bar icon this panel hangs from, so the panel is visibly part of it
    /// rather than an anonymous dropdown. One glyph carries both the identity and
    /// what is happening, which is why it replaced the plain status dot.
    private var stateMark: some View {
        let token = model.state == .idle ? ColorToken.faint : PillLabel.token(for: model.state)
        return RawiMarkShape(level: isLive ? model.level : 0, motion: model.motion)
            .stroke(c(token), style: RawiMarkShape.stroke(for: 18))
            .frame(width: 18, height: 18)
            .accessibilityHidden(true)
    }

    // MARK: - Actions

    private var actionStrip: some View {
        HStack(spacing: 8) {
            ForEach(MenuActions.all(model.labels)) { actionCell($0) }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
    }

    /// A compact tile: the icon in a box, the name, and the key beneath it.
    private func actionCell(_ action: MenuAction) -> some View {
        let isDictate = action.id == "dictate"
        return Button { model.onAction?(action.id) } label: {
            HStack(spacing: 9) {
                Image(systemName: action.symbol)
                    .font(.system(size: TypeScale.body, weight: .semibold))
                    .foregroundStyle(isDictate ? c(.ink) : c(.lapis))
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: Radius.control)
                        .fill(isDictate ? c(.saffron) : c(.surface))
                        .overlay(RoundedRectangle(cornerRadius: Radius.control)
                            .strokeBorder(isDictate ? .clear : c(.edge))))
                VStack(alignment: .leading, spacing: 1) {
                    Text(action.title == "Transform clipboard" ? "Transform" : action.title)
                        .font(.system(size: TypeScale.body, weight: .semibold))
                        .foregroundStyle(c(.bone))
                    Text(action.shortcut)
                        .font(.system(size: TypeScale.micro, weight: .semibold).monospaced())
                        .foregroundStyle(c(.muted))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: Radius.surface)
                .fill(hovered == action.id ? c(.edge).opacity(0.5) : c(.raised))
                .overlay(RoundedRectangle(cornerRadius: Radius.surface).strokeBorder(c(.edge))))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 ? action.id : (hovered == action.id ? nil : hovered) }
        .help(action.title)
        .accessibilityLabel(action.title)
        .animation(.easeOut(duration: 0.12), value: hovered)
    }

    // MARK: - Recent

    /// The row that opens Recent.
    ///
    /// It used to be a 9pt label and a 10pt "▸", both in the faintest colour on the
    /// palette — which made the one control in this panel that *hides* something
    /// the least visible thing in it. It now carries the count, a real chevron, and
    /// a hover ground, so it reads as a control rather than as a section label.
    private var recentDisclosure: some View {
        Button { model.recentOpen.toggle() } label: {
            HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.system(size: TypeScale.micro, weight: .semibold))
                    .foregroundStyle(c(.muted))
                    .rotationEffect(.degrees(model.recentOpen ? 90 : 0))
                Text("RECENT")
                    .font(.system(size: TypeScale.micro, weight: .medium).monospaced())
                    .tracking(1.4)
                    .foregroundStyle(c(.muted))
                if !model.recent.isEmpty {
                    Text("\(model.recent.count)")
                        .font(.system(size: TypeScale.micro, weight: .medium).monospacedDigit())
                        .foregroundStyle(c(.bone))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(c(.raised)))
                }
                Spacer()
                Text(model.recentOpen ? "Hide" : "Show")
                    .font(.system(size: TypeScale.small))
                    .foregroundStyle(c(.faint))
            }
            .padding(.horizontal, 15).padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(hovered == "recent" ? c(.raised) : .clear)
        .onHover { hovered = $0 ? "recent" : (hovered == "recent" ? nil : hovered) }
        .animation(.easeOut(duration: 0.12), value: model.recentOpen)
    }

    @ViewBuilder private var recentList: some View {
        if model.recent.isEmpty {
            Text("Nothing dictated yet.")
                .font(.system(size: TypeScale.small))
                .foregroundStyle(c(.faint))
                .padding(.horizontal, 15).padding(.bottom, 9)
        } else {
            VStack(spacing: 0) {
                // Keyed by position: the rows are rebuilt from history on every
                // refresh, with fresh ids, and hover must not flicker off when they are.
                ForEach(Array(model.recent.prefix(3).enumerated()), id: \.element.id) { index, item in
                    recentRow(item, index: index)
                }
            }
            .padding(.bottom, 6)
        }
    }

    private func recentRow(_ item: RecentDictation, index: Int) -> some View {
        let key = "recent-\(index)"
        let isHovered = hovered == key
        let justCopied = copiedRow == index
        return Button { copy(item, row: index) } label: {
            HStack(spacing: 10) {
                Text(item.badge)
                    .font(.system(size: TypeScale.micro, weight: .medium).monospaced())
                    .foregroundStyle(item.isTransform ? c(.verdigris)
                                     : (item.script == .arabic ? c(.lapis) : c(.faint)))
                    .frame(width: 22, alignment: .leading)
                Text(item.oneLine)
                    .font(.system(size: TypeScale.body))
                    .foregroundStyle(c(.bone))
                    .lineLimit(1)
                    .environment(\.layoutDirection,
                                 item.script == .arabic ? .rightToLeft : .leftToRight)
                Spacer(minLength: 8)
                // The time and the copy icon share one slot at the far right, so
                // hovering never shifts the text or truncates it further.
                ZStack(alignment: .trailing) {
                    Text(item.timestamp)
                        .font(.system(size: TypeScale.micro).monospaced())
                        .foregroundStyle(c(.faint))
                        .opacity(isHovered || justCopied ? 0 : 1)
                    Image(systemName: justCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: TypeScale.small, weight: .semibold))
                        // Saffron is the invitation; verdigris is done — the same
                        // contract the pill and the menu bar mark keep.
                        .foregroundStyle(c(justCopied ? .verdigris : .saffron))
                        .opacity(isHovered || justCopied ? 1 : 0)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .padding(.horizontal, 15).padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isHovered ? c(.raised) : .clear)
        .onHover { hovered = $0 ? key : (hovered == key ? nil : hovered) }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .animation(.easeOut(duration: 0.12), value: justCopied)
        .help(justCopied ? "Copied" : "Copy")
        .accessibilityLabel("Copy: \(item.oneLine)")
    }

    private func copy(_ item: RecentDictation, row: Int) {
        model.onCopy?(item)
        copiedRow = row
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            if copiedRow == row { copiedRow = nil }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 14) {
            Button {
                model.setupOutstanding == nil ? model.onOpenWindow?() : model.onOpenSetup?()
            } label: {
                if let outstanding = model.setupOutstanding {
                    HStack(spacing: 6) {
                        Image(systemName: outstanding.isBlocked ? "exclamationmark.circle.fill" : "circle.dashed")
                            .font(.system(size: TypeScale.small))
                        Text("Complete setup").font(.system(size: TypeScale.body, weight: .medium))
                    }
                    .foregroundStyle(c(.saffron))
                    .help(outstanding.outstanding.map(\.title).joined(separator: ", ") + " still to do")
                } else {
                    Text("Open Rawi").font(.system(size: TypeScale.body)).foregroundStyle(c(.muted))
                }
            }
            .buttonStyle(.plain)
            Button { model.onSettings?() } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: TypeScale.body))
                    .foregroundStyle(c(.muted))
                    .frame(width: 24, height: 24).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Settings")
            .accessibilityLabel("Settings")
            if model.canUndo {
                Button { model.onUndo?() } label: {
                    Text("Undo transform")
                        .font(.system(size: TypeScale.body))
                        .foregroundStyle(c(.saffron))
                }
                .buttonStyle(.plain)
                .help("Put the clipboard back the way it was")
            }
            Spacer()
            Button { model.onQuit?() } label: {
                HStack(spacing: 5) {
                    Image(systemName: "power").font(.system(size: TypeScale.small))
                    Text("Quit").font(.system(size: TypeScale.body))
                }
                .foregroundStyle(hovered == "quit" ? c(.bone) : c(.muted))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: Radius.control)
                    .fill(hovered == "quit" ? c(.raised) : .clear))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovered = $0 ? "quit" : (hovered == "quit" ? nil : hovered) }
        }
        .padding(.horizontal, 15).padding(.vertical, 9)
        // `ink` is darker than `surface` in the dark theme and all but identical to
        // it in the light one, where the footer separated from the panel by 1.03:1.
        .background(model.appearance == .dark ? c(.ink) : c(.raised))
    }
}

/// The level meter as it appears in the menu — wider and flatter than the pill's.
struct LevelStrip: View {
    let level: Double
    var peak: Double = 0
    let accent: Color
    let idle: Color
    var peakColor: Color = .white

    var body: some View {
        let lit = MeterBars.lit(level: level, bars: 34)
        let peakIndex = MeterBars.peakIndex(peak: peak, bars: 34)
        HStack(spacing: 2) {
            ForEach(0..<34, id: \.self) { index in
                Capsule()
                    .fill(index < lit ? accent : index == peakIndex ? peakColor.opacity(0.85) : idle)
                    .frame(width: 2, height: barHeight(index))
            }
        }
        .frame(height: 15)
    }

    private func barHeight(_ index: Int) -> CGFloat {
        let mid = 16.5
        let distance = abs(Double(index) - mid) / mid
        return 4 + (1 - distance) * 10
    }
}
