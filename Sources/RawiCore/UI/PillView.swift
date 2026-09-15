import SwiftUI

public enum PillLabel {
    public static func text(for state: DictationState) -> String {
        switch state {
        case .idle: "Ready"
        case .recording(.pushToTalk, _): "Listening"
        case .recording(.handsFree, _): "Hands-free"
        case .transcribing: "Transcribing…"
        case .cleaning: "Writing…"
        case .inserting: "Inserting…"
        case .transforming: "Rewriting…"
        case .notice(let message): message
        case .error(let message): message
        }
    }

    /// The first words of what just landed, for the moment after a dictation.
    ///
    /// Rawi's last word used to be "Copied - press Command V", which answers a
    /// question nobody has. What you want to know is whether it heard you.
    public static func landed(_ text: String, limit: Int = 42) -> String {
        let flat = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !flat.isEmpty else { return "Copied" }
        guard flat.count > limit else { return flat }
        // Cut at a word: a pill ending mid-syllable reads as a rendering bug.
        let head = flat.prefix(limit)
        let cut = head.lastIndex(of: " ").map { String(head[head.startIndex..<$0]) }
            ?? String(head)
        return cut + "…"
    }

    /// Only in the last minute of a hands-free session — the pill stays quiet
    /// until the auto-stop is genuinely near.
    public static func countdown(_ remaining: Duration) -> String? {
        let seconds = max(0, Int(remaining.components.seconds))
        guard seconds < 60 else { return nil }
        return String(format: "0:%02d", seconds)
    }

    public static func elapsed(_ d: Duration) -> String {
        let total = max(0, Int(d.components.seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// The state colour. This is the contract the design rests on: saffron is live,
    /// verdigris is finished, lapis is a detected language, clay is a problem.
    public static func token(for state: DictationState) -> ColorToken {
        switch state {
        case .recording: .saffron
        case .transcribing, .cleaning, .inserting, .transforming: .lapis
        case .error: .clay
        case .idle, .notice: .verdigris
        }
    }
}

@MainActor
public final class PillModel: ObservableObject {
    @Published public var state: DictationState = .idle
    @Published public var level: Double = 0
    @Published public var elapsed: Duration = .zero
    @Published public var remaining: Duration?
    /// True once the cursor has genuinely rested on the pill — see `PillProximity`.
    @Published public var armed: Bool = false
    /// Whether the text still needs pasting by hand, which is only true where
    /// Accessibility was never granted.
    @Published public var pasteHint: Bool = false
    @Published public var motion: MarkMotion = .rest
    @Published public var labels: HotkeyLabels = .placeholder
    /// What the × does. Not published: it never changes what is drawn.
    public var onCancel: (() -> Void)?
    public init() {}
}

public struct PillView: View {
    @ObservedObject var model: PillModel
    public init(model: PillModel) { self.model = model }

    private var isRecording: Bool { model.state.recordingMode != nil }
    @State private var hoveringCancel = false

    /// Whether there is anything for × to stop. A notice has already landed and
    /// idle has nothing running; everything else — recording, the work after it,
    /// an error waiting to be dismissed — is what the cancel key already handles.
    private var canCancel: Bool {
        switch model.state {
        case .idle, .notice: false
        default: true
        }
    }
    private var accent: Color { RawiColors.pill(PillLabel.token(for: model.state)) }

    public var body: some View {
        HStack(spacing: 10) {
            mark
            Text(PillLabel.text(for: model.state))
                .font(.system(size: TypeScale.body, weight: .medium))
                .foregroundStyle(RawiColors.pill(.bone))
                .fixedSize()

            if isRecording {
                LevelMeter(level: model.level, accent: accent)
                Text(PillLabel.elapsed(model.elapsed))
                    .font(.system(size: TypeScale.small).monospacedDigit())
                    .foregroundStyle(RawiColors.pill(.muted))
                if let remaining = model.remaining,
                   let countdown = PillLabel.countdown(remaining) {
                    Text(countdown)
                        .font(.system(size: TypeScale.small, weight: .semibold).monospacedDigit())
                        .foregroundStyle(RawiColors.pill(.saffron))
                }
            }

            // The paste hint is secondary now, and only appears where it is true:
            // on a Mac that can auto-paste, there is nothing to press.
            if model.pasteHint, case .notice = model.state {
                Text("⌘V to paste")
                    .font(.system(size: TypeScale.small, weight: .medium))
                    .foregroundStyle(RawiColors.pill(.saffron))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(RawiColors.pill(.raised)))
                    .transition(.opacity)
            }

            // The cursor has rested on the pill, so it can be clicked. The key is
            // shown beside the button rather than instead of it: the click is the
            // answer for the hand already on the mouse, the keycap teaches the
            // faster gesture for next time.
            if model.armed, canCancel {
                HStack(spacing: 7) {
                    Text(model.labels.cancel)
                        .font(.system(size: TypeScale.micro, weight: .medium).monospaced())
                        .foregroundStyle(RawiColors.pill(.faint))
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.mark)
                                .strokeBorder(RawiColors.pill(.edge), lineWidth: 1))
                        .fixedSize()
                    cancelButton
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .trailing)))
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 9)
        .background(
            Capsule()
                .fill(RawiColors.pill(.ink).opacity(0.94))
                .overlay(Capsule().strokeBorder(RawiColors.pill(.edge), lineWidth: 1))
        )
        .shadow(color: .black.opacity(0.38), radius: 12, y: 4)
        .scaleEffect(model.armed ? 1.03 : 1.0)
        .animation(.easeOut(duration: 0.16), value: model.armed)
        .animation(.easeOut(duration: 0.16), value: model.state)
    }

    private var cancelButton: some View {
        Button { model.onCancel?() } label: {
            Image(systemName: "xmark")
                .font(.system(size: TypeScale.micro, weight: .bold))
                .foregroundStyle(RawiColors.pill(hoveringCancel ? .bone : .muted))
                .frame(width: 20, height: 20)
                .background(Circle().fill(RawiColors.pill(hoveringCancel ? .clay : .raised)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hoveringCancel = $0 }
        .animation(.easeOut(duration: 0.12), value: hoveringCancel)
        .help(model.state.recordingMode != nil ? "Discard this recording" : "Cancel")
        .accessibilityLabel(model.state.recordingMode != nil ? "Discard recording" : "Cancel")
    }

    /// The mark, all the way through. The spinner that used to sit here while the
    /// model worked was furniture every app owns; this is the same seven points
    /// the menu bar draws, flattening to a line and springing back.
    private var mark: some View {
        RawiMarkShape(level: isRecording ? model.level : 0, motion: model.motion)
            .stroke(accent, style: RawiMarkShape.stroke(for: 17))
            .frame(width: 17, height: 17)
            .accessibilityHidden(true)
    }
}

/// Level meter. Bars light with a mild curve so quiet speech still shows movement —
/// a flat mapping makes a normal speaking voice look like silence.
struct LevelMeter: View {
    let level: Double
    let accent: Color
    private let barCount = 20

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<barCount, id: \.self) { index in
                let threshold = Double(index) / Double(barCount)
                let scaled = pow(min(max(level, 0), 1), 0.6)
                Capsule()
                    .fill(scaled > threshold ? accent : RawiColors.pill(.edge))
                    .frame(width: 2, height: barHeight(index))
            }
        }
        .frame(height: 15)
        .animation(.linear(duration: 0.05), value: level)
    }

    private func barHeight(_ index: Int) -> CGFloat {
        let mid = Double(barCount - 1) / 2
        let distance = abs(Double(index) - mid) / mid
        return 5 + (1 - distance) * 9
    }
}
