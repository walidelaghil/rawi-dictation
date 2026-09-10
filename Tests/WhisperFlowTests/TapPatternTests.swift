import Testing
@testable import WhisperFlowCore

@Suite("TapPattern") struct TapPatternTests {
    let clock = ContinuousClock()
    func make() -> TapPattern {
        TapPattern(doubleTapWindow: .milliseconds(350), minHold: .milliseconds(250))
    }

    @Test("a long press begins and ends a hold") func longPress() {
        var p = make(); let t0 = clock.now
        #expect(p.press(at: t0) == .beganHold)
        #expect(p.release(at: t0.advanced(by: .milliseconds(900))) == .endedHold)
    }

    @Test("a press released under minHold becomes pending, not a hold") func shortPress() {
        var p = make(); let t0 = clock.now
        #expect(p.press(at: t0) == .beganHold)
        #expect(p.release(at: t0.advanced(by: .milliseconds(120))) == .pendingShortTap)
    }

    @Test("a second press inside the window promotes to hands-free") func doubleTap() {
        var p = make(); let t0 = clock.now
        _ = p.press(at: t0)
        _ = p.release(at: t0.advanced(by: .milliseconds(120)))
        #expect(p.press(at: t0.advanced(by: .milliseconds(300))) == .beganDoubleTap)
    }

    @Test("the window is measured from the first press, not its release") func windowOrigin() {
        var p = make(); let t0 = clock.now
        _ = p.press(at: t0)
        _ = p.release(at: t0.advanced(by: .milliseconds(240)))
        // 300ms after the release is 540ms after the first press: outside the window.
        #expect(p.press(at: t0.advanced(by: .milliseconds(540))) == .beganHold)
    }

    @Test("an expired pending tap is discarded") func expiry() {
        var p = make(); let t0 = clock.now
        _ = p.press(at: t0)
        _ = p.release(at: t0.advanced(by: .milliseconds(100)))
        #expect(p.pendingExpired(at: t0.advanced(by: .milliseconds(350))) == .discardShortTap)
    }

    @Test("exactly at the boundary counts as inside the window") func boundary() {
        var p = make(); let t0 = clock.now
        _ = p.press(at: t0)
        _ = p.release(at: t0.advanced(by: .milliseconds(100)))
        #expect(p.press(at: t0.advanced(by: .milliseconds(350))) == .beganDoubleTap)
    }

    @Test("any press stops a hands-free session, however brief") func stopsHandsFree() {
        var p = make(); let t0 = clock.now
        p.handsFreeDidStart()
        #expect(p.press(at: t0) == .stopHandsFree)
        #expect(p.release(at: t0.advanced(by: .milliseconds(5))) == .ignored)
    }

    @Test("a long press stops a hands-free session too") func longPressStopsHandsFree() {
        var p = make(); let t0 = clock.now
        p.handsFreeDidStart()
        #expect(p.press(at: t0) == .stopHandsFree)
        #expect(p.release(at: t0.advanced(by: .seconds(2))) == .ignored)
    }

    @Test("a double tap leaves the pattern in a hands-free session") func doubleTapEntersHandsFree() {
        var p = make(); let t0 = clock.now
        _ = p.press(at: t0)
        _ = p.release(at: t0.advanced(by: .milliseconds(100)))
        #expect(p.press(at: t0.advanced(by: .milliseconds(200))) == .beganDoubleTap)
        #expect(p.press(at: t0.advanced(by: .seconds(4))) == .stopHandsFree)
    }

    @Test("a release with no matching press is ignored") func strayRelease() {
        var p = make()
        #expect(p.release(at: clock.now) == .ignored)
    }

    @Test("reset returns to a clean idle state") func resets() {
        var p = make(); let t0 = clock.now
        _ = p.press(at: t0); p.reset()
        #expect(p.release(at: t0.advanced(by: .seconds(1))) == .ignored)
    }

    @Test("a repeated press while holding is ignored") func keyRepeat() {
        var p = make(); let t0 = clock.now
        #expect(p.press(at: t0) == .beganHold)
        #expect(p.press(at: t0.advanced(by: .milliseconds(50))) == .ignored)
    }
}
