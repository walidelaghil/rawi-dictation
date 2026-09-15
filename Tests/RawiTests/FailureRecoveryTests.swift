import Testing
import Foundation
@testable import RawiCore

/// Waits for a condition instead of for a number of seconds.
///
/// A fixed sleep is a bet that the main actor is free, and under the full suite it
/// is not: these tests passed alone and failed together, which is the signature of
/// a timing assumption rather than a defect.
@MainActor
func waitUntil(_ timeout: Duration = .seconds(5),
               _ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return condition()
}

@MainActor
@Suite("A failure you can see and undo") struct FailureRecoveryTests {
    func rig(fails: Bool, pastes: Bool = true)
        -> (DictationController, HistoryStore, FakeLog) {
        let r = FakeRecorder(), e = FakeEngine(), c = FakeCleanup()
        let i = FakeInserter(), l = FakeLog()
        i.succeed = pastes
        e.result = fails
            ? .failure(TranscriptionError.binaryNotFound("whisper-cli"))
            : .success("hello there")
        let store = HistoryStore(url: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("rawi-fail-\(UUID().uuidString).jsonl"))
        let ctl = DictationController(config: .default, recorder: r, engine: e,
                                      cleanup: c, inserter: i, log: l)
        ctl.onRecord = { store.append($0) }
        return (ctl, store, l)
    }

    @Test("a failed dictation is recorded, not just logged") func recorded() async {
        // It used to vanish: 2.5 seconds on a click-through pill, then nothing.
        // From inside the app a dictation that failed looked exactly like one that
        // never happened.
        let (ctl, store, _) = rig(fails: true)
        await ctl.handle(.beganHold)
        await ctl.handle(.endedHold)
        #expect(store.all().count == 1)
        #expect(store.all().first?.kind == .failed)
        #expect(store.all().first?.failure?.contains("whisper") == true)
    }

    @Test("the audio it kept is named in the entry, not only in a log file")
    func keepsAudio() async {
        let (ctl, store, _) = rig(fails: true)
        await ctl.handle(.beganHold)
        await ctl.handle(.endedHold)
        let entry = store.all().first
        #expect(entry?.audioPath != nil)
        #expect(entry?.audioPath?.hasSuffix(".wav") == true)
    }

    @Test("a failure holds on the pill instead of clearing itself") func holds() async {
        // The one moment the user loses work was the one moment the UI gave them
        // 2.5 seconds and then removed the evidence.
        let (ctl, _, _) = rig(fails: true)
        await ctl.handle(.beganHold)
        await ctl.handle(.endedHold)
        guard case .error = ctl.state else { Issue.record("not an error state"); return }
        ctl.noticeDuration = .milliseconds(80)
        // A failure must still be there after everything a notice would have
        // outlived several times over.
        try? await Task.sleep(for: .milliseconds(600))
        guard case .error = ctl.state else {
            Issue.record("the failure cleared itself")
            return
        }
    }

    @Test("the next key press clears it") func dismissedByUse() async {
        let (ctl, _, _) = rig(fails: true)
        await ctl.handle(.beganHold)
        await ctl.handle(.endedHold)
        await ctl.handle(.beganHold)
        #expect(ctl.state.recordingMode == .pushToTalk)
    }

    @Test("cancelling clears it too") func dismissedByEscape() async {
        let (ctl, _, _) = rig(fails: true)
        await ctl.handle(.beganHold)
        await ctl.handle(.endedHold)
        await ctl.cancelRequested()
        #expect(ctl.state == .idle)
    }

    @Test("a success still clears itself after a moment") func noticeStillClears() async {
        // Only failure is sticky. A confirmation that would not go away is nagging.
        // The notice is the Accessibility-blocked path, which is this Mac.
        let (ctl, _, _) = rig(fails: false, pastes: false)
        ctl.noticeDuration = .milliseconds(80)
        await ctl.handle(.beganHold)
        await ctl.handle(.endedHold)
        if case .notice = ctl.state {} else { Issue.record("expected a notice") }
        #expect(await waitUntil { ctl.state == .idle })
    }

    @Test("failures do not count as words you dictated") func excludedFromInsights() async {
        let (ctl, store, _) = rig(fails: true)
        await ctl.handle(.beganHold)
        await ctl.handle(.endedHold)
        let insights = Insights.compute(from: store.all())
        #expect(insights.wordsDictated == 0)
        #expect(insights.dictations == 0)
    }

    @Test("a failed entry can be retried while its audio survives") func nothingToCopy() throws {
        let audio = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("rawi-retry-\(UUID().uuidString).wav")
        try Data("fake".utf8).write(to: audio)
        defer { try? FileManager.default.removeItem(at: audio) }
        let entry = HistoryEntry(at: Date(), cleaned: "", raw: "", script: .latin,
                                 appName: "Slack", bundleID: "slack", durationSeconds: 4,
                                 peakLevel: 0.3, guardRejected: false, kind: .failed,
                                 failure: "whisper-cli not found", audioPath: audio.path)
        #expect(entry.oneLine.isEmpty)
        #expect(entry.isRetryable)
        // And not once the audio has been cleaned up.
        try FileManager.default.removeItem(at: audio)
        #expect(!entry.isRetryable)
    }

    @Test("a failed entry with no audio left cannot be retried") func gone() {
        let entry = HistoryEntry(at: Date(), cleaned: "", raw: "", script: .latin,
                                 appName: nil, bundleID: nil, durationSeconds: 4,
                                 peakLevel: 0.3, guardRejected: false, kind: .failed,
                                 failure: "out of memory", audioPath: nil)
        #expect(!entry.isRetryable)
    }
}
