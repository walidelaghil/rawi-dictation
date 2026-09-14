import Testing
import Foundation
@testable import RawiCore

@MainActor
@Suite("Delivering the raw text first") struct RawFirstTests {
    func rig(cleanupTo cleaned: String = "Cleaned transcript.",
             rawFirst: Bool = true) -> (DictationController, FakeInserter, FakeCleanup) {
        let r = FakeRecorder(), e = FakeEngine(), c = FakeCleanup()
        let i = FakeInserter(), l = FakeLog()
        e.result = .success("um raw transcript")
        c.result = .success(cleaned)
        var config = Config.default
        config.output.deliverRawFirst = rawFirst
        return (DictationController(config: config, recorder: r, engine: e, cleanup: c,
                                    inserter: i, log: l), i, c)
    }

    @Test("the words are on the clipboard before cleanup runs") func stagesEarly() async {
        // Cleanup costs about four tenths of a second. Waiting for it was waiting
        // to be able to paste at all.
        let (ctl, inserter, _) = rig()
        await ctl.handle(.beganHold)
        await ctl.handle(.endedHold)
        #expect(inserter.staged == ["um raw transcript"])
    }

    @Test("cleanup upgrades what was staged") func upgrades() async {
        let (ctl, inserter, _) = rig()
        await ctl.handle(.beganHold)
        await ctl.handle(.endedHold)
        #expect(inserter.replaced.count == 1)
        #expect(inserter.replaced.first?.from == "um raw transcript")
        #expect(inserter.replaced.first?.to == "Cleaned transcript.")
    }

    @Test("a clipboard you changed in the meantime is left alone") func respectsYou() async {
        let (ctl, inserter, _) = rig()
        inserter.stagedSurvives = false
        await ctl.handle(.beganHold)
        await ctl.handle(.endedHold)
        #expect(inserter.replaced.isEmpty)
    }

    @Test("when cleanup changes nothing, nothing is rewritten") func noChange() async {
        let (ctl, inserter, _) = rig(cleanupTo: "um raw transcript")
        await ctl.handle(.beganHold)
        await ctl.handle(.endedHold)
        #expect(inserter.replaced.isEmpty)
        #expect(inserter.staged == ["um raw transcript"])
    }

    @Test("turning it off restores the old single-write behaviour") func optOut() async {
        let (ctl, inserter, _) = rig(rawFirst: false)
        await ctl.handle(.beganHold)
        await ctl.handle(.endedHold)
        #expect(inserter.staged.isEmpty)
        #expect(inserter.inserted == ["Cleaned transcript."])
    }

    @Test("history still records the cleaned text, not the staged one") func history() async {
        let (ctl, _, _) = rig()
        var recorded: [HistoryEntry] = []
        ctl.onRecord = { recorded.append($0) }
        await ctl.handle(.beganHold)
        await ctl.handle(.endedHold)
        #expect(recorded.first?.cleaned == "Cleaned transcript.")
        #expect(recorded.first?.raw == "um raw transcript")
    }
}
