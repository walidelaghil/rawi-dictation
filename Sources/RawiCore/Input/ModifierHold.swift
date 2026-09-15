/// Tells holding a modifier apart from using it.
///
/// A key like ⌥ on its own is the most comfortable dictation key there is, and
/// also the most used key on the keyboard: ⌥← jumps a word, ⌥E types an accent,
/// ⌥⌘Space is Rawi's own transform key. Treating every ⌥ press as "start
/// recording" would switch the microphone on dozens of times an hour.
///
/// So a bare modifier becomes a dictation key only when it is held *alone*: past
/// a short delay, with no other key and no other modifier joining it. Anything
/// that joins it makes it a shortcut, and the shortcut goes on to the app as it
/// always did — the tap is listen-only and never consumes it.
///
/// Pure, like `TapPattern`, so every sequence can be tested without a keyboard.
public struct ModifierHold: Sendable {
    public enum Action: Equatable, Sendable {
        /// Start the arm delay.
        case armLater
        /// Held alone long enough: a press.
        case press
        /// Let go after a real press.
        case release
        /// Tapped and let go before the delay, alone: a tap, which is how a
        /// double tap for hands-free is made.
        case pressAndRelease
        /// It was a shortcut after all, and a press has already gone out: take
        /// the recording back.
        case abandon
        case none
    }

    private enum Phase: Sendable { case up, waiting, holding, chorded }
    private var phase: Phase = .up

    public init() {}

    /// How long a modifier must be held alone before it counts. Long enough to
    /// get a finger onto the next key of a shortcut; short enough not to clip the
    /// first syllable of a sentence.
    public static let armDelay: Duration = .milliseconds(150)

    public mutating func modifierDown(othersHeld: Bool) -> Action {
        // Pressed while ⌘ was already down: ⌘⌥ is a shortcut from the start.
        guard !othersHeld else { phase = .chorded; return .none }
        phase = .waiting
        return .armLater
    }

    /// Another modifier went down or up while this one stayed down.
    public mutating func othersChanged(othersHeld: Bool) -> Action {
        guard othersHeld else { return .none }
        return chord()
    }

    /// Any ordinary key while the modifier is down.
    public mutating func keyDown() -> Action { chord() }

    public mutating func armFired() -> Action {
        guard phase == .waiting else { return .none }
        phase = .holding
        return .press
    }

    public mutating func modifierUp() -> Action {
        defer { phase = .up }
        switch phase {
        case .waiting: return .pressAndRelease
        case .holding: return .release
        case .up, .chorded: return .none
        }
    }

    public mutating func reset() { phase = .up }

    private mutating func chord() -> Action {
        switch phase {
        case .waiting: phase = .chorded; return .none
        case .holding: phase = .chorded; return .abandon
        case .up, .chorded: return .none
        }
    }
}
