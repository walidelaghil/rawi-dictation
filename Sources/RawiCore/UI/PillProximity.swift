import Foundation

/// Decides whether the pill should be interactive, from the cursor position alone.
///
/// The pill is click-through by default so it cannot steal a click meant for the
/// app behind it. It becomes solid only when the cursor genuinely *rests* on it.
/// Two details make that behave:
///
/// - **A dwell delay.** Without it, a cursor merely crossing the pill on its way
///   somewhere else would arm it and swallow the very click it was meant to let
///   through.
/// - **Slop, on the way out only.** Once armed, a few points of hysteresis stop
///   the pill flickering when the cursor rests on its border. It is not a wider
///   target on the way in — arming still requires being genuinely inside.
///
/// Pure and clock-injected, so every one of those rules is testable.
public struct PillProximity: Sendable {
    private let armDelay: Duration
    private let slop: CGFloat

    private var enteredAt: ContinuousClock.Instant?
    private var armed = false

    public init(armDelay: Duration = .milliseconds(250), slop: CGFloat = 6) {
        self.armDelay = armDelay
        self.slop = slop
    }

    public var isArmed: Bool { armed }

    public mutating func update(cursor: CGPoint, frame: CGRect,
                                now: ContinuousClock.Instant) -> Bool {
        guard !frame.isEmpty else {
            reset()
            return false
        }

        // Hysteresis applies only while already armed.
        let region = armed ? frame.insetBy(dx: -slop, dy: -slop) : frame
        guard region.contains(cursor) else {
            reset()
            return false
        }

        guard let enteredAt else {
            self.enteredAt = now
            return armed
        }
        if enteredAt.duration(to: now) >= armDelay { armed = true }
        return armed
    }

    public mutating func reset() {
        enteredAt = nil
        armed = false
    }
}
