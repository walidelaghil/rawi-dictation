import AppKit
import Foundation

/// Thrown to skip the cleanup stage without treating it as a failure.
enum CleanupSkipped: Error { case nothingToDo }

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
    private var transcriber: any TranscriptionEngine
    private var cleanup: any CleanupProvider
    private let inserter: any TextInserting
    private let log: any Logging

    public private(set) var state: DictationState = .idle {
        didSet { if state != oldValue { onStateChange?(state) } }
    }

    public var onStateChange: ((DictationState) -> Void)?
    public var isEnabled: Bool = true
    /// How long a confirmation stays on the pill. Injectable so tests assert the
    /// behaviour rather than racing a wall clock.
    public var noticeDuration: Duration = .seconds(2.5)

    /// Exposed so the pill can show elapsed time and the timeout can be scheduled.
    public private(set) var recordingStartedAt: ContinuousClock.Instant?

    /// The last few dictations, newest first. In memory only — Phase 3 replaces
    /// this with the persisted, searchable history.
    public private(set) var recent: [RecentDictation] = []
    private let recentLimit = 5

    /// True while the last dictation is sitting on the clipboard waiting for ⌘V:
    /// there was no text field to put it in, or no permission to paste. The pill
    /// shows the ⌘V hint from this, and only from this — a hint shown after the
    /// text already landed teaches you to press a key that pastes it twice.
    public private(set) var awaitingManualPaste = false

    /// Decides whether there is a text field to paste into.
    public var focusProbe: any FocusProbing = NoFocusProbe()

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
    /// The polisher, when `cleanup.mode` is `polish`. Set from outside like the
    /// transform runner, because both are the same provider graph the app already
    /// builds, and the controller has no business building providers.
    public var polisher: (any CleanupProvider)?

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

    /// Everything a dictation captured at key-press, as one value.
    ///
    /// The live `captured…` properties belong to whichever dictation started most
    /// recently. Once a new dictation may begin while the last one is still
    /// cleaning up, the old pipeline has to finish on its own copy, or its history
    /// row names the app you are dictating into now.
    struct DictationContext {
        let app: (name: String?, bundleID: String?)
        let vocabulary: VocabularySnapshot
        let destination: DestinationRule?
    }

    /// Incremented whenever a new dictation starts. A pipeline remembers the
    /// number it started under, and stops speaking for the pill once a newer one
    /// exists — it still delivers and records its text, silently.
    private var generation = 0

    private var currentContext: DictationContext {
        DictationContext(app: captured, vocabulary: capturedVocabulary,
                         destination: capturedDestination)
    }

    /// Sets the state on behalf of pipeline `gen`, unless a newer dictation owns it.
    private func publish(_ newState: DictationState, for gen: Int) {
        guard gen == generation else { return }
        state = newState
    }
    private var cancelled = false

    public init(config: Config,
                recorder: any AudioRecording,
                engine: any TranscriptionEngine,
                cleanup: any CleanupProvider,
                inserter: any TextInserting,
                log: any Logging) {
        self.config = config
        self.recorder = recorder
        self.transcriber = engine
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
        self.transcriber = engine
        self.cleanup = cleanup
    }

    public var currentConfig: Config { config }
    /// Exposed so the app can warm a resident model without owning the graph twice.
    public var engine: any TranscriptionEngine { transcriber }

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
            transcriber.cancel()
            cleanup.cancel()
            polisher?.cancel()
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
        // A notice is a confirmation, not work in progress: pressing the key again
        // means the next dictation. If the last one is still cleaning up behind its
        // early notice, it finishes on its own generation and stops touching the
        // pill — see `publish`.
        if case .notice = state { state = .idle }
        guard state == .idle else { return }        // ignore key repeat / re-entry
        // Unique, not just timestamped. Named by the second, two dictations started
        // in the same second shared one file — and once the key works during a
        // notice, the first one's cleanup would delete the second one's audio
        // while you were still speaking into it.
        let stamp = Int(Date().timeIntervalSince1970)
        let url = Config.recordingsDirectory
            .appendingPathComponent("dictation-\(stamp)-\(UUID().uuidString.prefix(8)).wav")
        do {
            cancelled = false
            // Captured at key-press, not at insert: focus can move while you speak,
            // and the app you were looking at is the one that shaped the dictation.
            captured = frontmostApp()
            awaitingManualPaste = false
            // Chromium and Electron build their accessibility tree on request.
            // Asking now gives it the whole sentence to finish.
            focusProbe.prepare()
            capturedIntent = intent
            capturedVocabulary = vocabulary()
            capturedDestination = destination(captured.bundleID)
            // Before the recorder can fail: an error from this press must not be
            // painted over by the pipeline it interrupted.
            generation += 1
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
        // Taken the moment the key comes up, before anything is awaited.
        let gen = generation
        let context = currentContext

        let recording: RecordingResult
        do {
            state = .transcribing
            recording = try recorder.stop()
        } catch {
            report(error, context: "stop recording")
            return
        }

        // Nothing was captured, so there is nothing to transcribe and nothing to
        // report. This used to travel all the way to the server and come back as a
        // failure with a retry button for a file containing no audio.
        guard AudioFile.hasAudio(at: recording.url) else {
            log.info("That was too short to catch anything; nothing recorded")
            try? FileManager.default.removeItem(at: recording.url)
            state = .idle
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
        let transcribeStarted = ContinuousClock.now
        do {
            raw = try await transcriber.transcribe(wav: recording.url,
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
        let transcribeMs = transcribeStarted.duration(to: .now).milliseconds

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
                         peak: recording.peakLevel, keepAudio: false,
                         timings: Timings(transcribe: transcribeMs),
                         context: context, generation: gen)
        if gen == generation { currentRecordingURL = nil }
    }


    /// Everything after the words exist: cleanup, the guard, the dictionary,
    /// snippets, insertion, and the record. Shared so a retry of kept audio takes
    /// exactly the path a fresh dictation takes.
    /// How long each stage of the last dictation took. Logged every time, because
    /// the only way anyone found the 1.4 seconds that `auto` was costing was by
    /// measuring instead of assuming.
    struct Timings {
        var transcribe: Int = 0
        var cleanup: Int = 0
        var insert: Int = 0
        /// When the words became pasteable, which is the number that decides
        /// whether this feels fast. Everything after it is polish.
        var ready: Int = 0
        var total: Int { transcribe + cleanup + insert }
    }
    private func finishText(_ raw: String, recordingURL: URL, duration: Double,
                            peak: Double, keepAudio: Bool, timings: Timings,
                            context: DictationContext, generation gen: Int) async {
        var stageTimings = timings
        // Your words go on the clipboard now, before cleanup runs. Cleanup takes
        // about four tenths of a second and only ever removes filler; waiting for
        // it meant waiting to be able to paste at all. If you paste in that window
        // you get the raw transcript, which is what the guard would have fallen
        // back to anyway.
        var text = raw
        var rejected = false
        // The two settings contradict each other: one puts text on the clipboard
        // early, the other promises to put your old clipboard back. Restoring wins,
        // because it is the one you had to turn on deliberately.
        // Only worth doing where the clipboard might be the delivery. With a text
        // field focused the words are about to be typed, and showing them on the
        // pill first made the second or two before they appeared look like a
        // failure — the pill said "done" while the document said nothing. It also
        // spent your clipboard on a copy nobody needed.
        let earlyPaste = config.output.deliverRawFirst
            && !config.output.restorePreviousClipboard
            && focusProbe.probe() != .editable
        if earlyPaste {
            _ = inserter.stage(raw)
            // And say so. Staging the text early while the pill still read
            // "Cleaning up…" meant the words were ready and nothing told you; you
            // waited for a stage whose only job is to remove filler.
            stageTimings.ready = stageTimings.transcribe
            log.info("Ready to paste after \(stageTimings.ready)ms")
            publish(.notice(PillLabel.landed(raw)), for: gen)
        }
        let cleanupStarted = ContinuousClock.now
        // Nothing to clean, nothing to wait for. Whisper punctuates and capitalises
        // on its own; asking a model to confirm that costs a second of GPU and
        // slows the next dictation down too.
        // Polishing is cleanup's stronger sibling, not a second round trip: when it
        // runs it does the cleaner's job as well, so the text meets exactly one
        // model either way and the stage costs what it always cost.
        let polisher = config.cleanup.mode == .polish ? self.polisher : nil
        let worthCleaning = polisher != nil ? PolishNeeded.check(raw)
                                            : CleanupNeeded.check(raw)
        if !worthCleaning {
            log.info("Nothing to clean up; keeping the transcript as heard")
        }
        if !earlyPaste, worthCleaning { publish(.cleaning, for: gen) }
        do {
            guard worthCleaning else { throw CleanupSkipped.nothingToDo }
            let instruction = context.destination?.instruction ?? ""
            // The model is not trusted blindly: a local model will sometimes answer
            // or obey the dictation instead of cleaning it. Inserting the raw
            // transcript is always better than inserting the model's invention.
            if let polisher {
                let candidate = try await polisher.clean(raw, instruction: instruction)
                switch PolishGuard.check(raw: raw, polished: candidate) {
                case .accept:
                    text = candidate
                case .reject(let reason):
                    rejected = true
                    log.warn("Polish rejected (\(reason)); inserting raw transcript")
                }
            } else {
                let candidate = try await cleanup.clean(raw, instruction: instruction)
                switch CleanupGuard.check(raw: raw, cleaned: candidate) {
                case .accept:
                    text = candidate
                case .reject(let reason):
                    rejected = true
                    log.warn("Cleanup rejected (\(reason)); inserting raw transcript")
                }
            }
        } catch is CleanupSkipped {
            // Expected, and not a failure: the transcript was already clean.
        } catch {
            if cancelled { publish(.idle, for: gen); return }
            log.warn("LLM cleanup failed (\(error.localizedDescription)); inserting raw transcript")
        }
        if cancelled { publish(.idle, for: gen); return }

        // The dictionary, applied deterministically. The model layers are
        // unreliable — 1.5b ignores a glossary entirely — so the guarantee lives in
        // code that cannot decline.
        text = TermCorrector.apply(text, terms: context.vocabulary.terms)

        // Snippets, after the guard, so an expanded address can never be mistaken
        // for the model rewriting your words.
        text = SnippetExpander.expand(text, with: context.vocabulary.snippets)

        // "first…, second…, third…" is a list, and here it becomes one. Last,
        // because it is the only stage that adds line breaks, and every stage
        // before it reads the text as one line.
        if config.output.formatSpokenLists { text = SpokenStructure.format(text) }

        stageTimings.cleanup = cleanupStarted.duration(to: .now).milliseconds
        let insertStarted = ContinuousClock.now
        publish(.inserting, for: gen)
        // Where the cursor is decides the delivery. A text field gets the paste;
        // anywhere else gets the clipboard and a hint, because a synthetic ⌘V into
        // a file list or a canvas does nothing at best and something else at worst.
        let focus = focusProbe.probe()
        log.info("Focus: \(focusProbe.lastSeen)")
        let pasted: Bool
        var onClipboard = true
        if focus == .notEditable {
            pasted = false
            if earlyPaste {
                // The raw text is already there; upgrade it if it is still yours.
                if text != raw { onClipboard = inserter.upgrade(staged: raw, with: text) }
            } else {
                inserter.stage(text)
            }
        } else {
            // If the raw text is still the thing on the clipboard, upgrade it. If
            // you have already pasted or copied something else, it is left alone.
            pasted = earlyPaste && text != raw
                ? inserter.replace(staged: raw, with: text)
                : inserter.insert(text,
                                  restoringClipboard: config.output.restorePreviousClipboard)
        }
        // Recorded whether or not the synthetic paste landed. On a Mac that cannot
        // grant Accessibility the clipboard *is* the delivery mechanism — pressing
        // ⌘V is the user completing the insertion, not the dictation failing.
        remember(text)
        onRecord?(HistoryEntry(
            at: Date(), cleaned: text, raw: raw,
            destination: context.destination?.name,
            script: ScriptDetector.detect(text),
            appName: context.app.name, bundleID: context.app.bundleID,
            durationSeconds: duration, peakLevel: peak, guardRejected: rejected))

        stageTimings.insert = insertStarted.duration(to: .now).milliseconds
        if earlyPaste, case .notice = state {
            // The clipboard was quietly upgraded underneath a message that is
            // already correct. Leave it alone rather than flashing a second one.
            if gen == self.generation { scheduleErrorClear() }
        }
        log.info("""
            Timing: transcribe \(stageTimings.transcribe)ms, \
            cleanup \(stageTimings.cleanup)ms, deliver \(stageTimings.insert)ms, \
            pasteable after \(stageTimings.ready > 0 ? stageTimings.ready : stageTimings.total)ms, \
            total \(stageTimings.total)ms for \(text.split(separator: " ").count) words
            """)
        if !keepAudio { try? FileManager.default.removeItem(at: recordingURL) }
        if pasted {
            log.info("Inserted \(text.count) characters")
            publish(.idle, for: gen)
        } else if focus == .notEditable {
            log.info("No text field has focus; left \(text.count) characters on the clipboard")
            // Said plainly, the way the clipboard is: it was not typed anywhere,
            // it is ready to paste wherever you are going next.
            if gen == self.generation { awaitingManualPaste = onClipboard }
            publish(.notice(onClipboard ? "Copied" : PillLabel.landed(text)), for: gen)
            if gen == self.generation { scheduleErrorClear() }
        } else {
            log.warn("""
                Could not paste: Accessibility permission is not granted. \
                The text is on the clipboard. Press Cmd-V to insert it.
                """)
            if gen == self.generation { awaitingManualPaste = true }
            // Ends on your words rather than on an instruction: what you want to
            // know here is whether it heard you, not how to paste.
            publish(.notice(PillLabel.landed(text)), for: gen)
            if gen == self.generation { scheduleErrorClear() }
        }
        if gen == self.generation { currentRecordingURL = nil }
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
        let started = ContinuousClock.now
        do {
            raw = try await transcriber.transcribe(wav: url,
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
        await finishText(raw, recordingURL: url, duration: 0, peak: 0, keepAudio: true,
                         timings: Timings(transcribe: started.duration(to: .now).milliseconds),
                         context: currentContext, generation: generation)
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
        let duration = noticeDuration
        // The notice this timer is for. A newer dictation's notice is not this
        // timer's to clear, however similar it looks.
        let shown = state
        Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard let self else { return }
            if case .notice = self.state, self.state == shown { self.state = .idle }
        }
    }
}
