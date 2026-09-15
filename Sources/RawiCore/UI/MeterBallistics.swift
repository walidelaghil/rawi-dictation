import Foundation

/// How the level meter moves: up at once, down slowly, with the loudest recent
/// moment left behind for a beat.
///
/// The raw microphone level drops to nothing between syllables, so a meter that
/// follows it looks nervous — it flickers where you hear continuous speech. Audio
/// meters on a mixing desk solve this with separate rise and fall times, and this
/// is that. The numbers are the ones chosen in the prototype: a rise short enough
/// to prove it heard you start, a fall long enough to join syllables into words.
public struct MeterBallistics: Sendable, Equatable {
    public private(set) var level: Double = 0
    public private(set) var peak: Double = 0
    private var peakAge: Double = 0

    public static let attack = 0.010
    public static let release = 0.350
    public static let peakHold = 0.700
    static let silence = 0.004

    public init() {}

    public mutating func advance(raw: Double, dt: Double) {
        let target = min(max(raw, 0), 1)
        let tau = target > level ? Self.attack : Self.release
        level += (target - level) * (1 - exp(-max(0, dt) / tau))
        if level >= peak {
            peak = level
            peakAge = 0
        } else {
            peakAge += dt
            if peakAge > Self.peakHold {
                peak += (level - peak) * (1 - exp(-max(0, dt) / Self.release))
            }
        }
        // The bar mapping lights one bar for anything above zero, so a tail that
        // decays towards zero forever keeps a bar lit forever. Below this it is
        // silence, and silence is an empty meter.
        if level < Self.silence { level = 0 }
        if peak < Self.silence { peak = 0 }
    }

    public mutating func reset() { self = MeterBallistics() }
}
