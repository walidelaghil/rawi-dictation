import SwiftUI

public enum PillLabel {
    public static func text(for state: DictationState) -> String {
        switch state {
        case .idle: "Ready"
        case .recording(.pushToTalk, _): "Recording"
        case .recording(.handsFree, _): "Hands-free"
        case .transcribing: "Transcribing…"
        case .cleaning: "Cleaning up…"
        case .inserting: "Inserting…"
        case .error(let message): message
        }
    }

    /// Only shown in the last minute of a hands-free session, so the pill stays
    /// quiet until the auto-stop is actually near.
    public static func countdown(_ remaining: Duration) -> String? {
        let seconds = max(0, Int(remaining.components.seconds))
        guard seconds < 60 else { return nil }
        return String(format: "0:%02d", seconds)
    }

    public static func elapsed(_ d: Duration) -> String {
        let total = max(0, Int(d.components.seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Observable state behind the pill. Updated at ~30 Hz while recording.
@MainActor
public final class PillModel: ObservableObject {
    @Published public var state: DictationState = .idle
    @Published public var level: Double = 0
    @Published public var elapsed: Duration = .zero
    @Published public var remaining: Duration?

    public init() {}
}

public struct PillView: View {
    @ObservedObject var model: PillModel

    public init(model: PillModel) { self.model = model }

    private var isRecording: Bool { model.state.recordingMode != nil }

    private var accent: Color {
        switch model.state {
        case .recording(.handsFree, _): .orange
        case .recording(.pushToTalk, _): .red
        case .error: .yellow
        default: .blue
        }
    }

    public var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(accent)

            Text(PillLabel.text(for: model.state))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .fixedSize()

            if isRecording {
                LevelMeter(level: model.level, accent: accent)
                Text(PillLabel.elapsed(model.elapsed))
                    .font(.system(size: 11, weight: .regular).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.65))

                if let remaining = model.remaining,
                   let countdown = PillLabel.countdown(remaining) {
                    Text(countdown)
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.orange)
                }
            } else if model.state == .transcribing || model.state == .cleaning {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
                    .frame(width: 14, height: 14)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            Capsule().fill(.black.opacity(0.82))
                .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1))
        )
        .shadow(color: .black.opacity(0.35), radius: 10, y: 3)
        .animation(.easeOut(duration: 0.15), value: model.state)
    }

    private var iconName: String {
        switch model.state {
        case .recording(.handsFree, _): "mic.badge.plus"
        case .recording(.pushToTalk, _): "mic.fill"
        case .transcribing, .cleaning, .inserting: "waveform"
        case .error: "exclamationmark.triangle.fill"
        case .idle: "mic"
        }
    }
}

/// 20-bar audio level meter. Bars light progressively with a mild curve so quiet
/// speech still shows movement.
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
                    .fill(scaled > threshold ? accent : Color.white.opacity(0.18))
                    .frame(width: 2, height: barHeight(index))
            }
        }
        .frame(height: 14)
        .animation(.linear(duration: 0.05), value: level)
    }

    private func barHeight(_ index: Int) -> CGFloat {
        let mid = Double(barCount - 1) / 2
        let distance = abs(Double(index) - mid) / mid
        return 5 + (1 - distance) * 9
    }
}
