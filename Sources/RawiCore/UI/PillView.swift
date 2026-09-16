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
        case .confirming(let question): question
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
        case .confirming: .saffron
        }
    }
}

@MainActor
public final class PillModel: ObservableObject {
    @Published public var state: DictationState = .idle
    @Published public var level: Double = 0
    /// The loudest recent moment, left behind by `MeterBallistics`.
    @Published public var peak: Double = 0
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
    /// Says yes to a command waiting for confirmation.
    public var onConfirm: (() -> Void)?
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

    private var isAsking: Bool {
        if case .confirming = model.state { return true }
        return false
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
                LevelMeter(level: model.level, peak: model.peak, accent: accent)
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

            // A question needs an answer within reach: the key is faster once you know
            // it, and the button is there the first time, when you do not.
            if isAsking {
                HStack(spacing: 7) {
                    Button { model.onConfirm?() } label: {
                        HStack(spacing: 5) {
                            Text("Run").font(.system(size: TypeScale.small, weight: .semibold))
                            Text(model.labels.command)
                                .font(.system(size: TypeScale.micro).monospaced())
                                .opacity(0.7)
                        }
                        .foregroundStyle(RawiColors.pill(.ink))
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Capsule().fill(RawiColors.pill(.saffron)))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Run this command")
                    cancelButton
                }
                .transition(.opacity)
            }

            // The cursor has rested on the pill, so it can be clicked. The key is
            // shown beside the button rather than instead of it: the click is the
            // answer for the hand already on the mouse, the keycap teaches the
            // faster gesture for next time.
            if model.armed, canCancel, !isAsking {
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
/// a flat mapping makes a normal speaking voice look like silence. The motion comes
/// from `MeterBallistics`; this only draws where it has got to.
struct LevelMeter: View {
    let level: Double
    var peak: Double = 0
    let accent: Color
    var barCount = 20
    var tallest: CGFloat = 14
    var shortest: CGFloat = 5

    var body: some View {
        let lit = MeterBars.lit(level: level, bars: barCount)
        let peakIndex = MeterBars.peakIndex(peak: peak, bars: barCount)
        HStack(spacing: 2) {
            ForEach(0..<barCount, id: \.self) { index in
                Capsule()
                    .fill(index < lit ? accent
                          : index == peakIndex ? RawiColors.pill(.bone).opacity(0.85)
                          : RawiColors.pill(.edge))
                    .frame(width: 2, height: barHeight(index))
            }
        }
        .frame(height: tallest + 1)
    }

    private func barHeight(_ index: Int) -> CGFloat {
        let mid = Double(barCount - 1) / 2
        let distance = abs(Double(index) - mid) / mid
        return shortest + (1 - distance) * (tallest - shortest)
    }
}

/// Which bars are lit, shared by the pill and the menu panel so both meters agree.
/// How far along the meter a level sits.
///
/// Speech is quiet as a number and enormous as a ratio. Measured across real
/// dictations on this Mac, peak amplitude ran 0.030 to 0.064 of full scale —
/// and the old mapping, which scaled amplitude directly, spent that entire
/// range between five bars and seven out of thirty-four. Silence lit one. The
/// meter had ballistics, a peak marker and nothing to show with them, because
/// eighty per cent of its width was reserved for loudness a microphone in a room
/// never produces.
///
/// Ears hear ratios, so the meter shows decibels, and its window is the range
/// speech actually occupies rather than full scale, which only a clipped
/// recording reaches.
enum MeterBars {
    /// Below this, the room rather than the speaker.
    static let floorDB = -50.0
    /// At this, the meter is full. Louder is still full, and that is honest:
    /// beyond here you are shouting at your laptop.
    static let ceilingDB = -10.0

    /// 0...1 along the meter, from an amplitude in 0...1.
    static func fraction(level: Double) -> Double {
        guard level > 0 else { return 0 }
        let decibels = 20 * log10(min(level, 1))
        return min(max((decibels - floorDB) / (ceilingDB - floorDB), 0), 1)
    }

    static func lit(level: Double, bars: Int) -> Int {
        Int((fraction(level: level) * Double(bars)).rounded(.up))
    }

    /// The bar the peak marker sits on, or nil when the peak is only room noise.
    static func peakIndex(peak: Double, bars: Int) -> Int? {
        let along = fraction(level: peak)
        guard along > 0 else { return nil }
        return min(bars - 1, max(0, Int((along * Double(bars)).rounded(.up)) - 1))
    }
}
