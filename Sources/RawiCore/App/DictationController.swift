import AppKit
import Foundation

public enum RecordingMode: Equatable, Sendable { case pushToTalk, handsFree }

/// What the recording is for. Captured at key-press, because it is the key you
/// pressed that decides — not anything discoverable later from the audio.
public enum RecordingIntent: Equatable, Sendable { case dictate, transform }

public enum DictationState: Equatable, Sendable {
    case idle
    case recording(mode: RecordingMode, startedAt: ContinuousClock.Instant)
    case transcribing
    case cleaning
    case inserting
    /// Rewriting the clipboard, rather than typing something new.
    case transforming
    /// Something finished and the user should know. Clears itself, like an error,
    /// but it is not one — a transform succeeds on the clipboard, not on screen.
    case notice(String)
    case error(String)

    public var isBusy: Bool { self != .idle }

    public var recordingMode: RecordingMode? {
        if case .recording(let mode, _) = self { return mode }
        return nil
    }
}

/// Orchestrates one dictation from key press to inserted text. The only component
/// that knows the whole flow; every dependency is a protocol so this is testable
/// with fakes and swappable at runtime.
@MainActor
public final class DictationController {
    private var config: Config
    private var recorder: any AudioRecording
    private var engine: any TranscriptionEngine
    private var cleanup: any CleanupProvider
    private let inserter: any TextInserting
    private let log: any Logging

    public private(set) var state: DictationState = .idle {
        didSet { if state != oldValue { onStateChange?(state) } }
    }

    public var onStateChange: ((DictationState) -> Void)?
    public var isEnabled: Bool = true

    /// Exposed so the pill can show elapsed time and the timeout can be scheduled.
    public private(set) var recordingStartedAt: ContinuousClock.Instant?

    /// The last few dictations, newest first. In memory only — Phase 3 replaces
    /// this with the persisted, searchable history.
    public private(set) var recent: [RecentDictation] = []
    private let recentLimit = 5

    /// The language whisper detected on the last transcript, for the menu.
    public private(set) var lastDetectedLanguage: String?

    /// Fired once a dictation has actually landed in a document. Not fired when
    /// the paste failed and the text only reached the clipboard — history records
    /// what happened, not what was attempted.
    public var onRecord: ((HistoryEntry) -> Void)?

    /// Which app had focus when the key went down. Injectable so tests do not
    /// depend on a live workspace.
    public var frontmostApp: () -> (name: String?, bundleID: String?) = {
        let app = NSWorkspace.shared.frontmostApplication
        return (app?.localizedName, app?.bundleIdentifier)
    }

    private var captured: (name: String?, bundleID: String?) = (nil, nil)
    private var capturedIntent: RecordingIntent = .dictate

    /// Set when transforms are wired. Absent, the transform key does nothing but say so.
    public var transformRunner: TransformRunner?

    /// Fired with the transform that ran, for the log and the menu.
    public var onTransform: ((TransformRunner.Outcome) -> Void)?

    /// Read at key-press so a dictation uses the vocabulary as it was when you
    /// started speaking, not as it might be by the time you stop.
    public var vocabulary: () -> VocabularySnapshot = { .empty }
    private var capturedVocabulary: VocabularySnapshot = .empty

    /// Resolves where this dictation is going. Given the frontmost bundle id so
    /// the app delegate can read a browser URL without the controller knowing
    /// anything about browsers.
    public var destination: (String?) -> DestinationRule? = { _ in nil }
    private var capturedDestination: DestinationRule?

    private var currentRecordingURL: URL?
    private var cancelled = false

    public init(config: Config,
                recorder: any AudioRecording,
                engine: any TranscriptionEngine,
                cleanup: any CleanupProvider,
                inserter: any TextInserting,
                log: any Logging) {
        self.config = config
        self.recorder = recorder
        self.engine = engine
        self.cleanup = cleanup
        self.inserter = inserter
        self.log = log
    }

    /// Swaps engine and cleanup provider after a config hot-reload.
    public func reconfigure(config: Config,
                            engine: any TranscriptionEngine,
                            cleanup: any CleanupProvider) {
        guard state == .idle else { return }
        self.config = config
        self.engine = engine
        self.cleanup = cleanup
    }

    public var currentConfig: Config { config }

    // MARK: - Input

    public func handle(_ outcome: TapOutcome, intent: RecordingIntent = .dictate) async {
        guard isEnabled else { return }
        switch outcome {
        case .beganHold:
            startRecording(mode: .pushToTalk, intent: intent)
        case .beganDoubleTap:
            promoteToHandsFree(intent: intent)
        case .endedHold, .stopHandsFree:
            await finishRecording()
        case .discardShortTap:
            discardRecording(reason: "tap too short to be speech")
        case .pendingShortTap, .ignored:
            break                     // keep recording; the timer decides
        }
    }

    /// Takes back the last transform while its result is still on the clipboard.
    @discardableResult
    public func undoTransform() -> Bool {
        guard let runner = transformRunner, runner.undo() else { return false }
        log.info("Transform undone; your text is back on the clipboard")
        state = .notice("Put back")
        scheduleErrorClear()
        return true
    }

    public var canUndoTransform: Bool { transformRunner?.canUndo ?? false }

    /// Esc. Drops a recording, or aborts work already running.
    public func cancelRequested() async {
        switch state {
        case .error:
            state = .idle                    // Esc acknowledges a failure
            return
        case .idle, .notice:
            return
        case .recording:
            discardRecording(reason: "cancelled")
        case .transcribing, .cleaning, .inserting, .transforming:
            cancelled = true
            engine.cancel()
            cleanup.cancel()
            transformRunner?.cancel()
            log.info("Cancelled in-flight transcription")
            state = .idle
        }
    }

    /// The 5-minute guard, so a forgotten hands-free session cannot run all afternoon.
    public func sessionTimedOut() async {
        guard state.recordingMode == .handsFree else { return }
        log.info("Hands-free session hit the \(config.maxSessionSeconds)s limit")
        await finishRecording()
    }

    // MARK: - Recording

    private func startRecording(mode: RecordingMode, intent: RecordingIntent = .dictate) {
        // A held error is dismissed by using the app again, which is the gesture
        // people actually make after reading one.
        if case .error = state { state = .idle }
        guard state == .idle else { return }        // ignore key repeat / re-entry
        let url = Config.recordingsDirectory
            .appendingPathComponent("dictation-\(Int(Date().timeIntervalSince1970)).wav")
        do {
            cancelled = false
            // Captured at key-press, not at insert: focus can move while you speak,
            // and the app you were looking at is the one that shaped the dictation.
            captured = frontmostApp()
            capturedIntent = intent
            capturedVocabulary = vocabulary()
            capturedDestination = destination(captured.bundleID)
            try recorder.start(to: url)
            currentRecordingURL = url
            let now = ContinuousClock.now
            recordingStartedAt = now
            state = .recording(mode: mode, startedAt: now)
        } catch AudioError.microphonePermissionDenied {
            // Usually means the app was rebuilt: TCC grants bind to the code
            // signature, and an ad-hoc signature changes every build. Asking again
            // re-prompts, rather than leaving the user with a dead hotkey and an
            // error they have to go and read in a log.
            log.warn("Microphone access denied — requesting it again. "
                   + "This usually means Rawi was rebuilt and macOS sees a new app.")
            state = .error("Allow microphone access")
            scheduleErrorClear()
            Task { @MainActor [weak self] in
                let granted = await Permissions.requestMicrophone()
                self?.log.info("Microphone access \(granted ? "granted" : "still denied")")
                if !granted {
                    self?.log.warn("Open System Settings → Privacy & Security → Microphone "
                                 + "and enable Rawi.")
                }
            }
        } catch {
            report(error, context: "start recording")
        }
    }

    /// A double tap arrives while the short first tap is still recording, so the
    /// audio continues seamlessly rather than restarting.
    private func promoteToHandsFree(intent: RecordingIntent = .dictate) {
        if case .recording(_, let startedAt) = state {
            state = .recording(mode: .handsFree, startedAt: startedAt)
        } else {
            // The intent travels with the press: a double-tapped transform key must
            // not quietly become a dictation.
            startRecording(mode: .handsFree, intent: intent)
        }
    }

    private func discardRecording(reason: String) {
        guard case .recording = state else { return }
        recorder.cancel()
        currentRecordingURL = nil
        recordingStartedAt = nil
        log.info("Recording discarded: \(reason)")
        state = .idle
    }

    // MARK: - Pipeline

    private func finishRecording() async {
        guard case .recording = state else { return }
        recordingStartedAt = nil

        let recording: RecordingResult
        do {
            state = .transcribing
            recording = try recorder.stop()
        } catch {
            report(error, context: "stop recording")
            return
        }

        log.info(String(format: "Recorded %.1fs, peak level %.3f",
                        Double(recording.duration.components.seconds)
                            + Double(recording.duration.components.attoseconds) / 1e18,
                        recording.peakLevel))
        if recording.isProbablySilent {
            log.warn("""
                Almost no audio was captured (peak \(String(format: "%.3f", recording.peakLevel))). \
                Check the input device in System Settings → Sound → Input, and that it \
                is not muted. Whisper invents words from silence.
                """)
        }

        // 1. Transcribe. On failure the WAV is retained and its path logged, so a
        //    dictation is never silently lost.
        let raw: String
        do {
            raw = try await engine.transcribe(wav: recording.url,
                                              prompt: capturedVocabulary.whisperPrompt)
        } catch {
            if cancelled { state = .idle; return }
            if case TranscriptionError.emptyResult = error {
                log.info("Nothing transcribed; discarding \(recording.url.lastPathComponent)")
                try? FileManager.default.removeItem(at: recording.url)
                state = .idle
                return
            }
            log.error("""
                Transcription failed (\(error.localizedDescription)). \
                Audio retained at \(recording.url.path) \
                (\(recording.url.lastPathComponent))
                """)
            // Written to history, not only to a log nobody has open: this is the
            // one moment in the product where words are lost, and it used to be
            // the one moment with no record.
            recordFailure(error, recording: recording)
            report(error, context: "transcribe")
            return
        }
        if cancelled { state = .idle; return }

        guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            log.info("Empty transcript; nothing to insert")
            try? FileManager.default.removeItem(at: recording.url)
            state = .idle
            return
        }

        // A transform diverges here: what you just said is the *instruction*, and
        // the material is the clipboard. Nothing below this line applies to it —
        // not the cleanup prompt, not the guard, not the dictionary.
        if capturedIntent == .transform {
            try? FileManager.default.removeItem(at: recording.url)
            await runTransform(spoken: raw)
            return
        }

        await finishText(raw, recordingURL: recording.url,
                         duration: Double(recording.duration.components.seconds),
                         peak: recording.peakLevel, keepAudio: false)
        currentRecordingURL = nil
    }


    /// Everything after the words exist: cleanup, the guard, the dictionary,
    /// snippets, insertion, and the record. Shared so a retry of kept audio takes
    /// exactly the path a fresh dictation takes.
    private func finishText(_ raw: String, recordingURL: URL, duration: Double,
                            peak: Double, keepAudio: Bool) async {
        // Cleanup. A cleanup failure must never lose the dictation, so the raw
        // transcript is inserted instead.
        var text = raw
        var rejected = false
        state = .cleaning
        do {
            let candidate = try await cleanup.clean(
                raw, instruction: capturedDestination?.instruction ?? "")
            // The model is not trusted blindly: a local model will sometimes answer
            // or obey the dictation instead of cleaning it. Inserting the raw
            // transcript is always better than inserting the model's invention.
            switch CleanupGuard.check(raw: raw, cleaned: candidate) {
            case .accept:
                text = candidate
            case .reject(let reason):
                rejected = true
                log.warn("Cleanup rejected (\(reason)); inserting raw transcript")
            }
        } catch {
            if cancelled { state = .idle; return }
            log.warn("LLM cleanup failed (\(error.localizedDescription)); inserting raw transcript")
        }
        if cancelled { state = .idle; return }

        // The dictionary, applied deterministically. The model layers are
        // unreliable — 1.5b ignores a glossary entirely — so the guarantee lives in
        // code that cannot decline.
        text = TermCorrector.apply(text, terms: capturedVocabulary.terms)

        // Snippets, after the guard, so an expanded address can never be mistaken
        // for the model rewriting your words.
        text = SnippetExpander.expand(text, with: capturedVocabulary.snippets)

        state = .inserting
        let pasted = inserter.insert(text,
                                     restoringClipboard: config.output.restorePreviousClipboard)
        // Recorded whether or not the synthetic paste landed. On a Mac that cannot
        // grant Accessibility the clipboard *is* the delivery mechanism — pressing
        // ⌘V is the user completing the insertion, not the dictation failing.
        remember(text)
        onRecord?(HistoryEntry(
            at: Date(), cleaned: text, raw: raw,
            destination: capturedDestination?.name,
            script: ScriptDetector.detect(text),
            appName: captured.name, bundleID: captured.bundleID,
            durationSeconds: duration, peakLevel: peak, guardRejected: rejected))

        if !keepAudio { try? FileManager.default.removeItem(at: recordingURL) }
        if pasted {
            log.info("Inserted \(text.count) characters")
            state = .idle
        } else {
            log.warn("""
                Could not paste: Accessibility permission is not granted. \
                The text is on the clipboard. Press Cmd-V to insert it.
                """)
            // Ends on your words rather than on an instruction: what you want to
            // know here is whether it heard you, not how to paste.
            state = .notice(PillLabel.landed(text))
            scheduleErrorClear()
        }
        currentRecordingURL = nil
    }

    /// Applies a spoken instruction to the clipboard. See `TransformRunner` for why
    /// `CleanupGuard` is deliberately absent.
    private func runTransform(spoken: String) async {
        guard let runner = transformRunner else {
            log.warn("Transform requested but no provider is configured")
            state = .error("Transforms need a cleanup provider")
            return
        }
        state = .transforming

        // The clipboard as it was goes to history before the model is called, so
        // an unwanted rewrite is always recoverable. The *result* is not recorded:
        // it is on the clipboard, and one row per transform beats two.
        runner.onOriginal = { [weak self] original in
            guard let self else { return }
            self.onRecord?(HistoryEntry(
                at: Date(), cleaned: original, raw: original,
                script: ScriptDetector.detect(original),
                appName: self.captured.name, bundleID: self.captured.bundleID,
                durationSeconds: 0, peakLevel: 0, guardRejected: false,
                kind: .transform))
        }

        do {
            let outcome = try await runner.run(spoken: spoken)
            if cancelled { state = .idle; return }
            log.info("""
                Transform “\(outcome.transform?.name ?? spoken)”:                 \(outcome.before.count) characters → \(outcome.after.count)
                """)
            remember(outcome.after)
            onTransform?(outcome)
            state = .notice(PillLabel.landed(outcome.after))
            scheduleErrorClear()
        } catch {
            if cancelled { state = .idle; return }
            // The clipboard still holds the original: the runner writes only on
            // success. Saying so is the whole reassurance the user needs.
            log.warn("Transform failed (\(error.localizedDescription)); clipboard unchanged")
            let message = (error as? TransformError)?.errorDescription ?? "Transform failed"
            state = .error(message)
        }
    }

    /// A failed dictation, with the audio that outlived it.
    private func recordFailure(_ error: any Error, recording: RecordingResult) {
        onRecord?(HistoryEntry(
            at: Date(), cleaned: "", raw: "", script: .latin,
            appName: captured.name, bundleID: captured.bundleID,
            durationSeconds: Double(recording.duration.components.seconds),
            peakLevel: recording.peakLevel, guardRejected: false,
            kind: .failed, failure: error.localizedDescription,
            audioPath: recording.url.path))
    }

    /// Runs the pipeline again on audio that was kept when it failed the first
    /// time. Everything downstream is the ordinary path.
    public func retry(audioPath: String, appName: String?, bundleID: String?) async {
        guard state == .idle else { return }
        let url = URL(fileURLWithPath: audioPath)
        guard FileManager.default.fileExists(atPath: audioPath) else {
            log.warn("The audio for that dictation is gone")
            state = .error("That recording is no longer on disk")
            return
        }
        cancelled = false
        captured = (appName, bundleID)
        capturedIntent = .dictate
        capturedVocabulary = vocabulary()
        capturedDestination = destination(bundleID)
        state = .transcribing
        let raw: String
        do {
            raw = try await engine.transcribe(wav: url,
                                              prompt: capturedVocabulary.whisperPrompt)
        } catch {
            log.error("Retry failed: \(error.localizedDescription)")
            report(error, context: "retry")
            return
        }
        guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            state = .error("Still nothing heard in that recording")
            return
        }
        await finishText(raw, recordingURL: url, duration: 0, peak: 0, keepAudio: true)
    }

    private func remember(_ text: String) {
        let script = ScriptDetector.detect(text)
        lastDetectedLanguage = script == .arabic ? "AR" : "EN"
        recent.insert(RecentDictation(text: text, script: script), at: 0)
        if recent.count > recentLimit { recent.removeLast(recent.count - recentLimit) }
    }

    // MARK: - Errors

    /// An error holds until you do something about it.
    ///
    /// It used to clear itself after 2.5 seconds onto a click-through pill at the
    /// bottom of a screen you were not looking at, which meant the only moment the
    /// product loses your words was also the only moment it told you nothing. The
    /// next key press, or Esc, is what dismisses it now.
    private func report(_ error: any Error, context: String) {
        log.error("\(context) failed: \(error.localizedDescription)")
        state = .error(error.localizedDescription)
    }

    /// Leaves a confirmation visible on the pill briefly, then returns to idle.
    /// Only notices clear themselves; a failure waits for you.
    private func scheduleErrorClear() {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard let self else { return }
            if case .notice = self.state { self.state = .idle }
        }
    }
}
