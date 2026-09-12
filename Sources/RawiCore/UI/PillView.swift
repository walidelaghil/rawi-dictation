import SwiftUI

public enum PillLabel {
    public static func text(for state: DictationState) -> String {
        switch state {
        case .idle: "Ready"
        case .recording(.pushToTalk, _): "Listening"
        case .recording(.handsFree, _): "Hands-free"
        case .transcribing: "Transcribing…"
        case .cleaning: "Cleaning up…"
        case .inserting: "Inserting…"
        case .transforming: "Rewriting…"
        case .notice(let message): message
        case .error(let message): message
        }
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
    public init() {}
}

public struct PillView: View {
    @ObservedObject var model: PillModel
    public init(model: PillModel) { self.model = model }

    private var isRecording: Bool { model.state.recordingMode != nil }
    private var accent: Color { RawiColors.pill(PillLabel.token(for: model.state)) }

    public var body: some View {
        HStack(spacing: 10) {
            mark
            Text(PillLabel.text(for: model.state))
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(RawiColors.pill(.bone))
                .fixedSize()

            if isRecording {
                LevelMeter(level: model.level, accent: accent)
                Text(PillLabel.elapsed(model.elapsed))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(RawiColors.pill(.muted))
                if let remaining = model.remaining,
                   let countdown = PillLabel.countdown(remaining) {
                    Text(countdown)
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(RawiColors.pill(.saffron))
                }
            }

            if model.armed {
                Text("⌃⌥Esc to cancel")
                    .font(.system(size: 10.5))
                    .foregroundStyle(RawiColors.pill(.faint))
                    .transition(.opacity)
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

    @ViewBuilder private var mark: some View {
        switch model.state {
        case .recording:
            Circle().fill(accent).frame(width: 8, height: 8)
        case .transcribing, .cleaning, .inserting, .transforming:
            ProgressView().controlSize(.small).scaleEffect(0.62).frame(width: 13, height: 13)
        case .error, .notice:
            Circle().fill(accent).frame(width: 8, height: 8)
        case .idle:
            RoundedRectangle(cornerRadius: 2).fill(accent).frame(width: 8, height: 8)
        }
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
