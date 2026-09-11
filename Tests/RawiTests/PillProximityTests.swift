import Testing
import Foundation
@testable import RawiCore

@Suite("PillProximity") struct PillProximityTests {
    let frame = CGRect(x: 100, y: 100, width: 200, height: 40)
    let inside = CGPoint(x: 200, y: 120)
    let outside = CGPoint(x: 500, y: 500)

    func make() -> PillProximity { PillProximity(armDelay: .milliseconds(250), slop: 6) }

    @Test("a cursor far away never arms it") func away() {
        var p = make(); let t = ContinuousClock.now
        #expect(p.update(cursor: outside, frame: frame, now: t) == false)
        #expect(p.update(cursor: outside, frame: frame, now: t.advanced(by: .seconds(5))) == false)
    }

    @Test("hovering arms only after the delay") func delay() {
        var p = make(); let t = ContinuousClock.now
        #expect(p.update(cursor: inside, frame: frame, now: t) == false)
        #expect(p.update(cursor: inside, frame: frame, now: t.advanced(by: .milliseconds(200))) == false)
        #expect(p.update(cursor: inside, frame: frame, now: t.advanced(by: .milliseconds(260))) == true)
    }

    @Test("passing through without stopping never arms it") func passingThrough() {
        // The whole point: a cursor crossing the pill must not swallow the click
        // the user aimed at the app behind it.
        var p = make(); let t = ContinuousClock.now
        #expect(p.update(cursor: inside, frame: frame, now: t) == false)
        #expect(p.update(cursor: outside, frame: frame, now: t.advanced(by: .milliseconds(100))) == false)
        #expect(p.update(cursor: inside, frame: frame, now: t.advanced(by: .milliseconds(200))) == false)
        #expect(p.update(cursor: inside, frame: frame, now: t.advanced(by: .milliseconds(400))) == false)
    }

    @Test("leaving disarms immediately") func leave() {
        var p = make(); let t = ContinuousClock.now
        _ = p.update(cursor: inside, frame: frame, now: t)
        #expect(p.update(cursor: inside, frame: frame, now: t.advanced(by: .milliseconds(300))) == true)
        #expect(p.update(cursor: outside, frame: frame, now: t.advanced(by: .milliseconds(310))) == false)
        #expect(p.isArmed == false)
    }

    @Test("slop keeps the edge from flickering") func slop() {
        var p = make(); let t = ContinuousClock.now
        let justOutside = CGPoint(x: frame.maxX + 4, y: frame.midY)
        _ = p.update(cursor: inside, frame: frame, now: t)
        #expect(p.update(cursor: inside, frame: frame, now: t.advanced(by: .milliseconds(300))) == true)
        #expect(p.update(cursor: justOutside, frame: frame, now: t.advanced(by: .milliseconds(320))) == true)
        let wellOutside = CGPoint(x: frame.maxX + 40, y: frame.midY)
        #expect(p.update(cursor: wellOutside, frame: frame, now: t.advanced(by: .milliseconds(330))) == false)
    }

    @Test("reset disarms and forgets the dwell") func reset() {
        var p = make(); let t = ContinuousClock.now
        _ = p.update(cursor: inside, frame: frame, now: t)
        p.reset()
        #expect(p.isArmed == false)
        #expect(p.update(cursor: inside, frame: frame, now: t.advanced(by: .milliseconds(300))) == false)
    }

    @Test("an empty frame can never arm") func emptyFrame() {
        var p = make(); let t = ContinuousClock.now
        #expect(p.update(cursor: inside, frame: .zero, now: t) == false)
        #expect(p.update(cursor: inside, frame: .zero, now: t.advanced(by: .seconds(2))) == false)
    }

    @Test("slop does not let a never-armed pill arm from outside") func slopNeedsArming() {
        // Slop is hysteresis on the way out, not a wider target on the way in.
        var p = make(); let t = ContinuousClock.now
        let justOutside = CGPoint(x: frame.maxX + 4, y: frame.midY)
        #expect(p.update(cursor: justOutside, frame: frame, now: t) == false)
        #expect(p.update(cursor: justOutside, frame: frame, now: t.advanced(by: .seconds(1))) == false)
    }
}
