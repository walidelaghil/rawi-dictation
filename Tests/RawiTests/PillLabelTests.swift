import Testing
@testable import RawiCore

@Suite("PillLabel") struct PillLabelTests {
    let t0 = ContinuousClock.now

    @Test("labels name the mode and stage") func labels() {
        // "Listening" per the approved design — it reads as the app's state rather
        // than as a recorder's, which matters when it sits over someone's document.
        #expect(PillLabel.text(for: .recording(mode: .pushToTalk, startedAt: t0)) == "Listening")
        #expect(PillLabel.text(for: .recording(mode: .handsFree, startedAt: t0)) == "Hands-free")
        #expect(PillLabel.text(for: .transcribing) == "Transcribing…")
        #expect(PillLabel.text(for: .cleaning) == "Cleaning up…")
        #expect(PillLabel.text(for: .inserting) == "Inserting…")
        #expect(PillLabel.text(for: .error("no mic")) == "no mic")
    }

    @Test("state maps to the colour contract the design rests on") func tokens() {
        #expect(PillLabel.token(for: .recording(mode: .pushToTalk, startedAt: t0)) == .saffron)
        #expect(PillLabel.token(for: .recording(mode: .handsFree, startedAt: t0)) == .saffron)
        #expect(PillLabel.token(for: .transcribing) == .lapis)
        #expect(PillLabel.token(for: .cleaning) == .lapis)
        #expect(PillLabel.token(for: .error("x")) == .clay)
        #expect(PillLabel.token(for: .idle) == .verdigris)
    }

    @Test("countdown appears only under a minute") func countdown() {
        #expect(PillLabel.countdown(.seconds(90)) == nil)
        #expect(PillLabel.countdown(.seconds(60)) == nil)
        #expect(PillLabel.countdown(.seconds(59)) == "0:59")
        #expect(PillLabel.countdown(.seconds(5)) == "0:05")
        #expect(PillLabel.countdown(.seconds(0)) == "0:00")
    }

    @Test("a negative remaining clamps to zero rather than showing a minus") func negative() {
        #expect(PillLabel.countdown(.seconds(-3)) == "0:00")
    }

    @Test("elapsed formats as minutes and seconds") func elapsed() {
        #expect(PillLabel.elapsed(.seconds(0)) == "0:00")
        #expect(PillLabel.elapsed(.seconds(7)) == "0:07")
        #expect(PillLabel.elapsed(.seconds(75)) == "1:15")
        #expect(PillLabel.elapsed(.seconds(600)) == "10:00")
    }
}
