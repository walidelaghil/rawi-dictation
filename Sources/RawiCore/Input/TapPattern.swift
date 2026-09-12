/// What a press or release means, once hold-vs-double-tap has been resolved.
public enum TapOutcome: Equatable, Sendable {
    case beganHold          // long press started; start recording
    case endedHold          // long press released; transcribe
    case pendingShortTap    // too short to be speech; hold audio, await a second tap
    case beganDoubleTap     // second tap inside the window; promote to hands-free
    case discardShortTap    // window expired with no second tap
    case stopHandsFree      // any press while a hands-free session runs
    case ignored
}

/// Resolves raw key press/release timestamps into dictation intent.
///
/// Two rules from the spec are load-bearing and easy to get wrong:
///   1. The double-tap window is measured from the **first press**, not from its
///      release, so a slow first tap cannot stretch the window.
///   2. Inside a hands-free session **any** press stops it, however briefly held —
///      hold-to-talk semantics do not apply once hands-free is running.
public struct TapPattern: Sendable {
    private enum Phase: Sendable {
        case idle
        case holding(firstPress: ContinuousClock.Instant)
        case pendingSecondTap(firstPress: ContinuousClock.Instant)
        case handsFree
    }

    private var phase: Phase = .idle
    private let doubleTapWindow: Duration
    private let minHold: Duration

    public init(doubleTapWindow: Duration, minHold: Duration) {
        self.doubleTapWindow = doubleTapWindow
        self.minHold = minHold
    }

    public mutating func press(at t: ContinuousClock.Instant) -> TapOutcome {
        switch phase {
        case .handsFree:
            phase = .idle
            return .stopHandsFree

        case .pendingSecondTap(let firstPress):
            if firstPress.duration(to: t) <= doubleTapWindow {
                phase = .handsFree
                return .beganDoubleTap
            }
            phase = .holding(firstPress: t)
            return .beganHold

        case .idle:
            phase = .holding(firstPress: t)
            return .beganHold

        case .holding:
            return .ignored          // key repeat, or a press we already saw
        }
    }

    public mutating func release(at t: ContinuousClock.Instant) -> TapOutcome {
        switch phase {
        case .holding(let firstPress):
            if firstPress.duration(to: t) >= minHold {
                phase = .idle
                return .endedHold
            }
            phase = .pendingSecondTap(firstPress: firstPress)
            return .pendingShortTap

        case .idle, .pendingSecondTap, .handsFree:
            return .ignored
        }
    }

    /// Called when the controller's pending-tap timer fires.
    public mutating func pendingExpired(at t: ContinuousClock.Instant) -> TapOutcome {
        if case .pendingSecondTap = phase {
            phase = .idle
            return .discardShortTap
        }
        return .ignored
    }

    /// Lets the controller tell the pattern a hands-free session is live, for
    /// paths that start one without going through a double tap.
    public mutating func handsFreeDidStart() { phase = .handsFree }

    public mutating func reset() { phase = .idle }
}
