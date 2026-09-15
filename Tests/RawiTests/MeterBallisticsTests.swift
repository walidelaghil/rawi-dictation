import Testing
@testable import RawiCore

@Suite("How the level meter moves") struct MeterBallisticsTests {
    let frame = 1.0 / 30

    @Test("it rises to your voice within a frame") func rises() {
        var m = MeterBallistics()
        m.advance(raw: 0.8, dt: frame)
        #expect(m.level > 0.75)
    }

    @Test("it falls slowly between syllables instead of dropping out") func fallsSlowly() {
        var m = MeterBallistics()
        m.advance(raw: 0.8, dt: frame)
        for _ in 0..<3 { m.advance(raw: 0, dt: frame) }       // a 100 ms gap
        #expect(m.level > 0.5)
    }

    @Test("silence empties it completely, from full, in about two seconds") func settles() {
        var m = MeterBallistics()
        m.advance(raw: 1, dt: frame)
        for _ in 0..<66 { m.advance(raw: 0, dt: frame) }
        #expect(m.level == 0)
        #expect(MeterBars.lit(level: m.level, bars: 20) == 0)
        #expect(m.peak < 0.05)
    }

    @Test("the peak stays put for its hold, then follows") func peakHold() {
        var m = MeterBallistics()
        m.advance(raw: 0.9, dt: frame)
        let top = m.peak
        for _ in 0..<15 { m.advance(raw: 0.2, dt: frame) }    // half a second
        #expect(m.peak == top)
        for _ in 0..<30 { m.advance(raw: 0.2, dt: frame) }    // well past the hold
        #expect(m.peak < top)
    }

    @Test("bars and peak marker agree on where they are") func bars() {
        #expect(MeterBars.lit(level: 0, bars: 20) == 0)
        #expect(MeterBars.lit(level: 1, bars: 20) == 20)
        #expect(MeterBars.peakIndex(peak: 0, bars: 20) == nil)
        #expect(MeterBars.peakIndex(peak: 1, bars: 20) == 19)
    }

    @Test("a single place reads in the singular") func plural() {
        #expect(DictationPlace.workMessages.label(count: 1) == "Work message")
        #expect(DictationPlace.workMessages.label(count: 2) == "Work messages")
        #expect(DictationPlace.code.label(count: 1) == "Code")
    }
}
