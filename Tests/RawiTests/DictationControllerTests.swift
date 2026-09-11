import Testing
import Foundation
@testable import RawiCore

@MainActor
@Suite("DictationController") struct DictationControllerTests {
    typealias Rig = (ctl: DictationController, rec: FakeRecorder, eng: FakeEngine,
                     clean: FakeCleanup, ins: FakeInserter, log: FakeLog)

    func make(cleanupFails: Bool = false, transcript: String = "raw transcript",
              config: Config = .default) -> Rig {
        let r = FakeRecorder(), e = FakeEngine(), c = FakeCleanup()
        let i = FakeInserter(), l = FakeLog()
        e.result = .success(transcript)
        if cleanupFails { c.result = .failure(CleanupError.badResponse("boom")) }
        let ctl = DictationController(config: config, recorder: r, engine: e,
                                      cleanup: c, inserter: i, log: l)
        return (ctl, r, e, c, i, l)
    }

    @Test("a full push-to-talk cycle inserts cleaned text and returns to idle") func happyPath() async {
        let g = make()
        await g.ctl.handle(.beganHold)
        #expect(g.rec.isRecording)
        #expect(g.ctl.state.recordingMode == .pushToTalk)
        await g.ctl.handle(.endedHold)
        #expect(g.clean.received == ["raw transcript"])
        #expect(g.ins.inserted == ["Cleaned transcript."])
        #expect(g.ctl.state == .idle)
    }

    @Test("a double tap starts a hands-free recording") func handsFree() async {
        let g = make()
        await g.ctl.handle(.beganDoubleTap)
        #expect(g.rec.isRecording)
        #expect(g.ctl.state == .recording(mode: .handsFree, startedAt: g.ctl.recordingStartedAt!))
    }

    @Test("a double tap during a pending short tap keeps the same audio") func promote() async {
        let g = make()
        await g.ctl.handle(.beganHold)
        await g.ctl.handle(.pendingShortTap)
        #expect(g.rec.isRecording)                 // still capturing
        await g.ctl.handle(.beganDoubleTap)
        #expect(g.ctl.state.recordingMode == .handsFree)
        #expect(g.rec.startedURLs.count == 1)      // not restarted
    }

    @Test("stopHandsFree runs the pipeline") func handsFreeStop() async {
        let g = make()
        await g.ctl.handle(.beganDoubleTap)
        await g.ctl.handle(.stopHandsFree)
        #expect(g.ins.inserted.count == 1)
        #expect(g.ctl.state == .idle)
    }

    @Test("an expired short tap discards the recording") func discard() async {
        let g = make()
        await g.ctl.handle(.beganHold)
        await g.ctl.handle(.pendingShortTap)
        await g.ctl.handle(.discardShortTap)
        #expect(g.rec.cancelled)
        #expect(g.eng.callCount == 0)
        #expect(g.ctl.state == .idle)
    }

    @Test("esc while recording drops the audio and inserts nothing") func cancelRecording() async {
        let g = make()
        await g.ctl.handle(.beganHold)
        await g.ctl.cancelRequested()
        #expect(g.rec.cancelled)
        #expect(g.eng.callCount == 0)
        #expect(g.ins.inserted.isEmpty)
        #expect(g.ctl.state == .idle)
    }

    @Test("esc while idle does nothing") func cancelIdle() async {
        let g = make()
        await g.ctl.cancelRequested()
        #expect(!g.rec.cancelled)
        #expect(g.ctl.state == .idle)
    }

    @Test("a cleanup failure still inserts the raw transcript") func cleanupFallback() async {
        let g = make(cleanupFails: true)
        await g.ctl.handle(.beganHold)
        await g.ctl.handle(.endedHold)
        #expect(g.ins.inserted == ["raw transcript"])
        #expect(g.log.lines.contains { $0.lowercased().contains("cleanup") })
        #expect(g.ctl.state == .idle)
    }

    @Test("an empty transcript inserts nothing and returns to idle") func emptyTranscript() async {
        let g = make(transcript: "   ")
        await g.ctl.handle(.beganHold)
        await g.ctl.handle(.endedHold)
        #expect(g.ins.inserted.isEmpty)
        #expect(g.ctl.state == .idle)
    }

    @Test("a transcription failure retains the wav and logs its path") func transcriptionFailure() async {
        let g = make()
        g.eng.result = .failure(TranscriptionError.processFailed(exitCode: 1, stderrTail: "boom"))
        await g.ctl.handle(.beganHold)
        let wav = g.rec.startedURLs.last!
        await g.ctl.handle(.endedHold)
        #expect(g.ins.inserted.isEmpty)
        #expect(g.log.lines.contains { $0.contains(wav.lastPathComponent) })
        #expect(g.log.lines.contains { $0.contains("retained") })
    }

    @Test("the 5 minute timeout stops only a hands-free session") func timeout() async {
        let g = make()
        await g.ctl.handle(.beganDoubleTap)
        await g.ctl.sessionTimedOut()
        #expect(g.ins.inserted.count == 1)

        let h = make()
        await h.ctl.handle(.beganHold)
        await h.ctl.sessionTimedOut()
        #expect(h.ins.inserted.isEmpty)          // push-to-talk is unaffected
        #expect(h.ctl.state.recordingMode == .pushToTalk)
    }

    @Test("a disabled controller ignores every tap") func disabled() async {
        let g = make()
        g.ctl.isEnabled = false
        await g.ctl.handle(.beganHold)
        #expect(!g.rec.isRecording)
        #expect(g.ctl.state == .idle)
    }

    @Test("a failed paste leaves the text on the clipboard and reports it") func pasteDenied() async {
        let g = make()
        g.ins.succeed = false
        await g.ctl.handle(.beganHold)
        await g.ctl.handle(.endedHold)
        #expect(g.log.lines.contains { $0.lowercased().contains("accessibility") })
        #expect(g.ctl.state == .error("Copied — press ⌘V"))
    }

    @Test("a second beganHold while recording is ignored") func reentrancy() async {
        let g = make()
        await g.ctl.handle(.beganHold)
        g.rec.startedURLs.removeAll()
        await g.ctl.handle(.beganHold)
        #expect(g.rec.startedURLs.isEmpty)
    }

    @Test("the restore-clipboard flag is passed through from config") func restoreFlag() async {
        var config = Config.default
        config.output.restorePreviousClipboard = true
        let g = make(config: config)
        await g.ctl.handle(.beganHold)
        await g.ctl.handle(.endedHold)
        #expect(g.ins.restoreFlags == [true])
    }

    @Test("state changes are published to observers") func observer() async {
        let g = make()
        var seen: [DictationState] = []
        g.ctl.onStateChange = { seen.append($0) }
        await g.ctl.handle(.beganHold)
        await g.ctl.handle(.endedHold)
        #expect(seen.contains { $0.recordingMode == .pushToTalk })
        #expect(seen.contains(.transcribing))
        #expect(seen.contains(.cleaning))
        #expect(seen.last == .idle)
    }

    @Test("a recorder that cannot start reports an error rather than hanging") func startFails() async {
        let g = make()
        g.rec.startError = AudioError.microphonePermissionDenied
        await g.ctl.handle(.beganHold)
        #expect(g.ctl.state == .error(AudioError.microphonePermissionDenied.localizedDescription))
        #expect(g.log.lines.contains { $0.lowercased().contains("microphone") })
    }
}

@MainActor
@Suite("Recent dictations") struct RecentDictationRingTests {
    func make() -> (DictationController, FakeInserter) {
        let r = FakeRecorder(), e = FakeEngine(), c = FakeCleanup()
        let i = FakeInserter(), l = FakeLog()
        c.result = .success("Cleaned text.")
        return (DictationController(config: .default, recorder: r, engine: e,
                                    cleanup: c, inserter: i, log: l), i)
    }

    @Test("an inserted dictation is remembered") func remembers() async {
        let (ctl, _) = make()
        await ctl.handle(.beganHold)
        await ctl.handle(.endedHold)
        #expect(ctl.recent.count == 1)
        #expect(ctl.recent.first?.text == "Cleaned text.")
        #expect(ctl.recent.first?.script == .latin)
    }

    @Test("a dictation that was never pasted is not remembered") func notPasted() async {
        let (ctl, inserter) = make()
        inserter.succeed = false
        await ctl.handle(.beganHold)
        await ctl.handle(.endedHold)
        // It is on the clipboard, but it never reached a document — Recent is a
        // record of what landed, not of what was attempted.
        #expect(ctl.recent.isEmpty)
    }

    @Test("the ring holds five and drops the oldest") func ring() async {
        let (ctl, _) = make()
        for _ in 0..<7 {
            await ctl.handle(.beganHold)
            await ctl.handle(.endedHold)
        }
        #expect(ctl.recent.count == 5)
    }

    @Test("newest is first") func order() async {
        let (ctl, _) = make()
        await ctl.handle(.beganHold); await ctl.handle(.endedHold)
        let first = ctl.recent.first?.id
        await ctl.handle(.beganHold); await ctl.handle(.endedHold)
        #expect(ctl.recent.first?.id != first)
        #expect(ctl.recent.last?.id == first)
    }

    @Test("the detected language is exposed for the menu") func language() async {
        let r = FakeRecorder(), e = FakeEngine(), c = FakeCleanup()
        c.result = .success("يعني تمام كذا")
        let ctl = DictationController(config: .default, recorder: r, engine: e,
                                      cleanup: c, inserter: FakeInserter(), log: FakeLog())
        await ctl.handle(.beganHold)
        await ctl.handle(.endedHold)
        #expect(ctl.lastDetectedLanguage == "AR")
        #expect(ctl.recent.first?.script == .arabic)
    }
}
