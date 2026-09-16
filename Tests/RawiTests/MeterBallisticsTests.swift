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

    @Test("the meter spends its width on the levels speech actually reaches")
    func speechFillsTheMeter() {
        // Reported as "the meter doesn't move". It did move — between five bars
        // and seven, because it scaled amplitude directly and speech measures
        // three to six hundredths of full scale. These are real peaks from the
        // log, and they have to land far apart.
        let quiet = MeterBars.lit(level: 0.010, bars: 34)
        let normal = MeterBars.lit(level: 0.030, bars: 34)
        let loud = MeterBars.lit(level: 0.064, bars: 34)

        #expect(MeterBars.lit(level: 0.002, bars: 34) == 0)   // a quiet room is empty
        #expect(quiet >= 6)
        #expect(normal >= quiet + 5)
        #expect(loud >= normal + 4)
        #expect(loud <= 34)
        // Half the meter or better for an ordinary speaking voice.
        #expect(normal >= 17)
    }

    @Test("every step up the scale is a step along the meter") func monotonic() {
        var last = -1
        for level in stride(from: 0.0, through: 1.0, by: 0.01) {
            let bars = MeterBars.lit(level: level, bars: 34)
            #expect(bars >= last)
            last = bars
        }
    }

    @Test("a single place reads in the singular") func plural() {
        #expect(DictationPlace.workMessages.label(count: 1) == "Work message")
        #expect(DictationPlace.workMessages.label(count: 2) == "Work messages")
        #expect(DictationPlace.code.label(count: 1) == "Code")
    }
}
