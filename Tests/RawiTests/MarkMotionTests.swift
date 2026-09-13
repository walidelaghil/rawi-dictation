import Testing
import Foundation
@testable import RawiCore

@Suite("Mark motion") struct MarkMotionTests {
    let working = DictationState.transcribing
    let landed = DictationState.notice("hello")

    func advanced(_ state: DictationState, seconds: Double,
                  from start: MarkMotion = .rest, step: Double = 1.0 / 30) -> MarkMotion {
        var motion = start
        var elapsed = 0.0
        while elapsed < seconds {
            motion.advance(to: state, dt: step, elapsed: elapsed)
            elapsed += step
        }
        return motion
    }

    @Test("at rest nothing moves") func rest() {
        let motion = advanced(.idle, seconds: 2)
        #expect(motion == .rest)
    }

    @Test("working flattens the waveform, and it takes a beat") func flattens() {
        #expect(advanced(working, seconds: 0.05).flatten < 0.4)   // not a jump cut
        #expect(advanced(working, seconds: 0.6).flatten > 0.9)    // but it gets there
    }

    @Test("finishing unflattens it again") func unflattens() {
        let flat = advanced(working, seconds: 1)
        let back = advanced(.idle, seconds: 0.6, from: flat)
        #expect(back.flatten < 0.1)
    }

    @Test("the travelling bump goes there and comes back") func bump() {
        // A bump that jumps back to the start reads as a loading bar. This one
        // turns around, and it dwells at each end rather than ping-ponging.
        let period = MarkMotion.bumpPeriod
        let quarter = advanced(working, seconds: period * 0.25).bump
        let half = advanced(working, seconds: period * 0.5).bump
        let threeQuarters = advanced(working, seconds: period * 0.75).bump
        #expect(half > 0.97)                                   // reaches the far end
        #expect(quarter > 0.5)                                 // most of the way there
        #expect(abs((1 - threeQuarters) - quarter) < 0.1)      // symmetric coming back
    }

    @Test("landing springs once and settles") func spring() {
        let atPeak = advanced(landed, seconds: 0.17)
        let after = advanced(landed, seconds: 0.5)
        #expect(atPeak.spring > 0.3)
        #expect(after.spring < 0.05)
    }

    @Test("a long frame gap cannot overshoot the target") func clamped() {
        var motion = MarkMotion.rest
        motion.advance(to: working, dt: 10, elapsed: 0)     // app was asleep
        #expect(motion.flatten <= 1)
        #expect(motion.flatten >= 0.99)
    }

    @Test("it says when it has nothing left to animate") func settles() {
        #expect(MarkMotion.rest.isSettled)
        #expect(!advanced(working, seconds: 1).isSettled)
        #expect(advanced(.idle, seconds: 1, from: advanced(working, seconds: 1)).isSettled)
    }
}

@Suite("Mark geometry under motion") struct MarkGeometryTests {
    @Test("fully flattened, the waveform is gone and only the bump is left")
    func flat() {
        var motion = MarkMotion.rest
        motion.flatten = 1
        let points = RawiMark.svgPoints(level: 0, motion: motion)
        for point in points.dropFirst().dropLast() {
            // The bump only ever lifts, so nothing may sit below the line, and
            // nothing may rise further than the bump's own height.
            #expect(point.y <= 12.0001)
            #expect(point.y > 12 - 3.3)
        }
        // With the bump out of the way entirely, it is a line.
        motion.bump = 10                       // parked far off the end
        for point in RawiMark.svgPoints(level: 0, motion: motion).dropFirst().dropLast() {
            #expect(abs(point.y - 12) < 0.01)
        }
    }

    @Test("the ends never move, whatever the motion") func endsPinned() {
        for flatten in [0.0, 0.5, 1.0] {
            for bump in stride(from: 0.0, through: 1.0, by: 0.25) {
                var motion = MarkMotion.rest
                motion.flatten = flatten
                motion.bump = bump
                let points = RawiMark.svgPoints(level: 0.7, motion: motion)
                #expect(points.first == RawiMark.svgPoints.first)
                #expect(points.last == RawiMark.svgPoints.last)
            }
        }
    }

    @Test("the bump lifts the line, and where it lifts follows the phase") func travels() {
        var early = MarkMotion.rest; early.flatten = 1; early.bump = 0.1
        var late = MarkMotion.rest; late.flatten = 1; late.bump = 0.9
        let a = RawiMark.svgPoints(level: 0, motion: early)
        let b = RawiMark.svgPoints(level: 0, motion: late)
        #expect(a[1].y < b[1].y)      // the near point is lifted early
        #expect(b[5].y < a[5].y)      // the far point is lifted late
    }

    @Test("a flattened mark still fits the box") func bounds() {
        for bump in stride(from: 0.0, through: 1.0, by: 0.1) {
            var motion = MarkMotion.rest; motion.flatten = 1; motion.bump = bump
            for point in RawiMark.svgPoints(level: 1, motion: motion) {
                #expect(point.y >= 1 && point.y <= 23)
            }
        }
    }

    @Test("the landing spring makes the waveform bigger, briefly") func springScale() {
        var sprung = MarkMotion.rest; sprung.spring = 1
        let normal = RawiMark.svgPoints(level: 0)
        let big = RawiMark.svgPoints(level: 0, motion: sprung)
        #expect(big[3].y > normal[3].y)
        #expect(big[3].y - normal[3].y < 1)     // 6%, not a bounce
    }
}
