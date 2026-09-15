import Testing
import Foundation
@testable import RawiCore

@MainActor
@Suite("DictationController") struct DictationControllerTests {
    typealias Rig = (ctl: DictationController, rec: FakeRecorder, eng: FakeEngine,
                     clean: FakeCleanup, ins: FakeInserter, log: FakeLog)

    func make(cleanupFails: Bool = false, transcript: String = "um raw transcript",
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
        #expect(g.clean.received == ["um raw transcript"])
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
        #expect(g.ins.inserted == ["um raw transcript"])
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
        // The pill ends on the words that landed, not on an instruction.
        #expect(g.ctl.state == .notice("Cleaned transcript."))
    }

    // MARK: Where the text goes

    @Test("a focused text field gets the paste, and no hint") func pastesIntoAField() async {
        let g = make()
        let focus = FakeFocus(); focus.result = .editable
        g.ctl.focusProbe = focus
        await g.ctl.handle(.beganHold)
        #expect(focus.prepared == 1)          // asked at key-press, not at paste time
        await g.ctl.handle(.endedHold)
        #expect(g.ins.inserted == ["Cleaned transcript."])
        #expect(!g.ctl.awaitingManualPaste)
        #expect(g.ctl.state == .idle)
    }

    @Test("with no text field, nothing is pasted and the pill says Copied") func noField() async {
        var config = Config.default
        config.output.deliverRawFirst = false
        let g = make(config: config)
        let focus = FakeFocus(); focus.result = .notEditable
        g.ctl.focusProbe = focus
        await g.ctl.handle(.beganHold)
        await g.ctl.handle(.endedHold)
        #expect(g.ins.inserted.isEmpty)       // no synthetic ⌘V into a file list
        #expect(g.ins.staged == ["Cleaned transcript."])
        #expect(g.ctl.awaitingManualPaste)
        #expect(g.ctl.state == .notice("Copied"))
    }

    @Test("with no text field, the early raw text is upgraded without pasting") func noFieldEarly() async {
        let g = make()                        // deliverRawFirst is the default
        let focus = FakeFocus(); focus.result = .notEditable
        g.ctl.focusProbe = focus
        await g.ctl.handle(.beganHold)
        await g.ctl.handle(.endedHold)
        #expect(g.ins.inserted.isEmpty)
        #expect(g.ins.upgraded.map(\.to) == ["Cleaned transcript."])
        #expect(g.ctl.awaitingManualPaste)
        #expect(g.ctl.state == .notice("Copied"))
    }

    @Test("if you copied something else meanwhile, no hint points at the wrong text") func noFieldClipboardMoved() async {
        let g = make()
        g.ins.stagedSurvives = false
        let focus = FakeFocus(); focus.result = .notEditable
        g.ctl.focusProbe = focus
        await g.ctl.handle(.beganHold)
        await g.ctl.handle(.endedHold)
        #expect(!g.ctl.awaitingManualPaste)
        #expect(g.ctl.state == .notice("Cleaned transcript."))
    }

    @Test("an app that will not say still gets the paste") func unknownPastes() async {
        let g = make()
        let focus = FakeFocus(); focus.result = .unknown
        g.ctl.focusProbe = focus
        await g.ctl.handle(.beganHold)
        await g.ctl.handle(.endedHold)
        #expect(g.ins.inserted == ["Cleaned transcript."])
    }

    @Test("the hint is cleared when the next dictation starts") func hintResets() async {
        var config = Config.default
        config.output.deliverRawFirst = false
        let g = make(config: config)
        g.ctl.noticeDuration = .milliseconds(10)
        let focus = FakeFocus(); focus.result = .notEditable
        g.ctl.focusProbe = focus
        await g.ctl.handle(.beganHold)
        await g.ctl.handle(.endedHold)
        #expect(g.ctl.awaitingManualPaste)
        #expect(await waitUntil { g.ctl.state == .idle })
        focus.result = .editable
        await g.ctl.handle(.beganHold)
        #expect(!g.ctl.awaitingManualPaste)
    }

    @Test("the decision reads roles the way the probe measured them") func classify() {
        // Measured on this Mac: TextEdit, a Brave input, the Claude app's prompt.
        #expect(SystemFocusProbe.classify(role: "AXTextArea", valueSettable: true, hasSelectedRange: true) == .editable)
        #expect(SystemFocusProbe.classify(role: "AXTextField", valueSettable: true, hasSelectedRange: true) == .editable)
        // Finder's file list, and a Brave page with nothing focused.
        #expect(SystemFocusProbe.classify(role: "AXOutline", valueSettable: false, hasSelectedRange: false) == .notEditable)
        #expect(SystemFocusProbe.classify(role: "AXWebArea", valueSettable: false, hasSelectedRange: true) == .notEditable)
        // A slider has a settable value but no text selection.
        #expect(SystemFocusProbe.classify(role: "AXSlider", valueSettable: true, hasSelectedRange: false) == .notEditable)
        // A custom text view with an unusual role still behaves like text.
        #expect(SystemFocusProbe.classify(role: "AXGroup", valueSettable: true, hasSelectedRange: true) == .editable)
        #expect(SystemFocusProbe.classify(role: nil, valueSettable: false, hasSelectedRange: false) == .unknown)
    }

    // MARK: The key during a notice

    @Test("the key starts the next dictation while a notice is showing") func pressDuringNotice() async {
        var config = Config.default
        config.output.deliverRawFirst = false
        let g = make(config: config)
        let focus = FakeFocus(); focus.result = .notEditable
        g.ctl.focusProbe = focus
        await g.ctl.handle(.beganHold)
        await g.ctl.handle(.endedHold)
        #expect(g.ctl.state == .notice("Copied"))
        await g.ctl.handle(.beganHold)
        #expect(g.rec.isRecording)
        #expect(g.ctl.state.recordingMode == .pushToTalk)
    }

    @Test("a dictation still cleaning up finishes without taking over the next one") func pressDuringCleanup() async {
        let g = make()                                   // raw text is delivered early
        g.clean.delay = .milliseconds(300)
        await g.ctl.handle(.beganHold)
        let first = Task { await g.ctl.handle(.endedHold) }
        // The early notice: your words are on the clipboard, cleanup is still going.
        #expect(await waitUntil { if case .notice = g.ctl.state { true } else { false } })
        await g.ctl.handle(.beganHold)
        #expect(g.ctl.state.recordingMode == .pushToTalk)
        await first.value
        // The first dictation still landed…
        #expect(g.ins.inserted == ["Cleaned transcript."])
        // …and did not paint "Inserting" or "idle" over the recording in progress.
        #expect(g.rec.isRecording)
        #expect(g.ctl.state.recordingMode == .pushToTalk)
        #expect(g.rec.startedURLs.count == 2)
    }

    @Test("an old notice's timer does not clear a newer notice") func noticeTimerIsItsOwn() async {
        var config = Config.default
        config.output.deliverRawFirst = false
        let g = make(config: config)
        g.ctl.noticeDuration = .milliseconds(150)
        let focus = FakeFocus(); focus.result = .notEditable
        g.ctl.focusProbe = focus
        await g.ctl.handle(.beganHold)
        await g.ctl.handle(.endedHold)                   // "Copied", timer running
        g.eng.result = .success("second transcript")
        g.clean.result = .success("Second one.")
        await g.ctl.handle(.beganHold)
        await g.ctl.handle(.endedHold)                   // a new "Copied"
        try? await Task.sleep(for: .milliseconds(100))   // past half of the first timer
        #expect(g.ctl.state == .notice("Copied"))
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
        // No "Cleaning up…" on the fast path: the words are already pasteable by
        // then, and saying otherwise made people wait for polish they had not asked
        // to wait for.
        #expect(seen.contains { if case .notice = $0 { return true } else { return false } })
        #expect(seen.last == .idle)
    }

    @Test("a denied microphone asks again rather than dead-ending") func micDenied() async {
        // A rebuild invalidates the TCC grant, so this is the common case rather
        // than the exotic one. The message tells the user what to do.
        let g = make()
        g.rec.startError = AudioError.microphonePermissionDenied
        await g.ctl.handle(.beganHold)
        #expect(g.ctl.state == .error("Allow microphone access"))
        #expect(g.log.lines.contains { $0.lowercased().contains("rebuilt") })
    }

    @Test("any other start failure is reported as itself") func startFails() async {
        let g = make()
        g.rec.startError = AudioError.engineStartFailed("no device")
        await g.ctl.handle(.beganHold)
        #expect(g.ctl.state == .error(AudioError.engineStartFailed("no device").localizedDescription))
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

    @Test("a clipboard-only dictation is still in Recent") func clipboardOnly() async {
        let (ctl, inserter) = make()
        inserter.succeed = false
        await ctl.handle(.beganHold)
        await ctl.handle(.endedHold)
        // Same reasoning as history: without Accessibility the clipboard is how
        // text is delivered, so this dictation absolutely happened.
        #expect(ctl.recent.count == 1)
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
        e.result = .success("يعني يعني نرسل التقرير بكرة")
        c.result = .success("يعني تمام كذا")
        let ctl = DictationController(config: .default, recorder: r, engine: e,
                                      cleanup: c, inserter: FakeInserter(), log: FakeLog())
        await ctl.handle(.beganHold)
        await ctl.handle(.endedHold)
        #expect(ctl.lastDetectedLanguage == "AR")
        #expect(ctl.recent.first?.script == .arabic)
    }
}

@MainActor
@Suite("History recording") struct HistoryRecordingTests {
    func rig(cleanup: String = "Cleaned text.", fails: Bool = false,
             // Carries filler, so it still reaches the model. A transcript that is
             // already clean skips it entirely now.
             raw: String = "um raw transcript")
        -> (DictationController, FakeInserter, Recorded) {
        let r = FakeRecorder(), e = FakeEngine(), c = FakeCleanup()
        let i = FakeInserter(), l = FakeLog()
        e.result = .success(raw)
        c.result = fails ? .failure(CleanupError.badResponse("x")) : .success(cleanup)
        let ctl = DictationController(config: .default, recorder: r, engine: e,
                                      cleanup: c, inserter: i, log: l)
        ctl.frontmostApp = { ("Slack", "com.tinyspeck.slackmacgap") }
        let box = Recorded()
        ctl.onRecord = { box.append($0) }
        return (ctl, i, box)
    }

    @Test("an inserted dictation is recorded with both texts") func records() async {
        let (ctl, _, box) = rig()
        await ctl.handle(.beganHold)
        await ctl.handle(.endedHold)
        #expect(box.entries.count == 1)
        let e = box.entries[0]
        #expect(e.cleaned == "Cleaned text.")
        #expect(e.raw == "um raw transcript")     // what whisper actually heard
        #expect(e.appName == "Slack")
        #expect(e.bundleID == "com.tinyspeck.slackmacgap")
        #expect(!e.guardRejected)
    }

    @Test("a dictation that reached only the clipboard is still recorded") func clipboardOnly() async {
        let (ctl, inserter, box) = rig()
        inserter.succeed = false
        // On a Mac that cannot grant Accessibility the paste never succeeds, so
        // gating on it would leave history permanently empty. The clipboard is the
        // delivery mechanism there; ⌘V is the user finishing the job.
        await ctl.handle(.beganHold)
        await ctl.handle(.endedHold)
        #expect(box.entries.count == 1)
        #expect(box.entries.first?.cleaned == "Cleaned text.")
    }

    @Test("a cancelled dictation is not recorded") func cancelled() async {
        let (ctl, _, box) = rig()
        await ctl.handle(.beganHold)
        await ctl.cancelRequested()
        #expect(box.entries.isEmpty)
    }

    @Test("an empty transcript is not recorded") func emptyNotRecorded() async {
        let (ctl, _, box) = rig(cleanup: "   ", raw: "   ")
        await ctl.handle(.beganHold)
        await ctl.handle(.endedHold)
        #expect(box.entries.isEmpty)
    }

    @Test("a guard rejection is recorded as such") func guardFlag() async {
        // Cleanup that loses the dictation is discarded and the record says so.
        // The raw must be long enough for the guard to have an opinion — it
        // deliberately does not judge transcripts of a few words.
        let long = "we should move the deadline to Friday because the API work is not done"
        let (ctl, _, box) = rig(cleanup: "banana", raw: long)
        await ctl.handle(.beganHold)
        await ctl.handle(.endedHold)
        #expect(box.entries.first?.guardRejected == true)
        #expect(box.entries.first?.cleaned == long)
    }

    @Test("a normal cleanup is not flagged as a rejection") func notRejected() async {
        let long = "we should move the deadline to Friday because the API work is not done"
        let (ctl, _, box) = rig(cleanup: "We should move the deadline to Friday, "
                                       + "because the API work is not done.", raw: long)
        await ctl.handle(.beganHold)
        await ctl.handle(.endedHold)
        #expect(box.entries.first?.guardRejected == false)
    }

    @Test("the app is captured at key-press, not at insert") func capturedEarly() async {
        let (ctl, _, box) = rig()
        await ctl.handle(.beganHold)
        ctl.frontmostApp = { ("Finder", "com.apple.finder") }   // focus moved mid-dictation
        await ctl.handle(.endedHold)
        #expect(box.entries.first?.appName == "Slack")
    }

    @Test("script is recorded so history can set it in the right face") func script() async {
        let (ctl, _, box) = rig(cleanup: "يعني تمام كذا")
        await ctl.handle(.beganHold)
        await ctl.handle(.endedHold)
        #expect(box.entries.first?.script == .arabic)
    }
}

final class Recorded: @unchecked Sendable {
    private let lock = NSLock()
    private var _entries: [HistoryEntry] = []
    var entries: [HistoryEntry] { lock.withLock { _entries } }
    func append(_ e: HistoryEntry) { lock.withLock { _entries.append(e) } }
}
