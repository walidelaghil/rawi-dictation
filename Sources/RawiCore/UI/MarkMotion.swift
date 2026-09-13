import Foundation

/// Where the mark is in its animation, as plain numbers.
///
/// Split out from the drawing so the motion can be tested without rendering
/// anything, and so the menu bar, the pill and the panel all animate from one
/// timeline rather than three that drift apart.
///
/// The shape of the idea: the waveform listens, flattens to a line while the
/// model works, and springs back when your words land. One glyph the whole way
/// through, because a spinner is furniture every app owns and this mark is not.
public struct MarkMotion: Equatable, Sendable {
    /// 0 is the waveform, 1 is a flat line.
    public var flatten: Double = 0
    /// Where the travelling bump is along the line, 0 to 1.
    public var bump: Double = 0
    /// The single overshoot on landing.
    public var spring: Double = 0

    public static let rest = MarkMotion()

    /// A time constant, not a duration: the flatten covers most of its distance
    /// in about this long and finishes asymptotically, which is what stops the
    /// transition looking like a cut.
    static let flattenTau = 0.2
    /// One pass of the bump, there and back.
    static let bumpPeriod = 1.3
    static let springDuration = 0.34

    /// Below a hundredth the motion is invisible, and holding a frame timer alive
    /// for it is the kind of thing that shows up in a battery graph.
    static let epsilon = 0.01

    public var isSettled: Bool {
        flatten < Self.epsilon && spring < Self.epsilon
    }

    /// Advances one frame. `elapsed` is how long the current state has been on
    /// screen, which is what the bump's phase is measured from.
    public mutating func advance(to state: DictationState, dt: Double, elapsed: Double) {
        let target: Double
        switch state {
        case .transcribing, .cleaning, .transforming: target = 1
        default: target = 0
        }
        // min(1, …) so a long frame gap — the app was asleep, the display woke —
        // lands exactly on the target instead of overshooting past it.
        flatten += (target - flatten) * min(1, dt / Self.flattenTau)

        if target > 0 {
            let phase = (elapsed.truncatingRemainder(dividingBy: Self.bumpPeriod))
                / Self.bumpPeriod
            // There and back, eased at both ends, so it dwells rather than
            // ping-ponging. A bump that snaps back to the start reads as a
            // progress bar, and this is not progress: it is thinking.
            bump = phase < 0.5 ? easeOut(phase * 2) : 1 - easeOut((phase - 0.5) * 2)
        }

        if case .notice = state {
            let t = min(1, elapsed / Self.springDuration)
            spring = sin(t * .pi) * (1 - t)
        } else {
            spring += (0 - spring) * min(1, dt / 0.2)
            if spring < Self.epsilon { spring = 0 }
        }
        if flatten < Self.epsilon { flatten = 0 }
    }

    private func easeOut(_ t: Double) -> Double {
        let clamped = min(max(t, 0), 1)
        return 1 - pow(1 - clamped, 3)
    }
}
