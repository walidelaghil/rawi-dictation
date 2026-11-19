import AppKit
import Foundation

/// Thrown to skip the cleanup stage without treating it as a failure.
enum CleanupSkipped: Error { case nothingToDo }

public enum RecordingMode: Equatable, Sendable { case pushToTalk, handsFree }

/// What the recording is for. Captured at key-press, because it is the key you
/// pressed that decides — not anything discoverable later from the audio.
public enum RecordingIntent: Equatable, Sendable { case dictate, transform, command }

public enum DictationState: Equatable, Sendable {
    case idle
    /// A command is waiting for you to say yes. Unlike a notice, it does not clear
    /// itself: something is about to happen, and it holds until you answer or it
    /// times out.
    case confirming(String)
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
    /// The language you told it to use, or `.auto` to let the detector decide.
    ///
    /// Sticky for the session and never written to disk: a forced language that
    /// survived a relaunch would be a setting nobody remembers turning on, and
    /// the failure it causes — Arabic transcribed as English words — looks like
    /// the app breaking rather than like a choice.
    public private(set) var language: DictationLanguage = .auto

    /// Called when the language changes, so the pill can redraw.
    public var onLanguageChange: ((DictationLanguage) -> Void)?

    public func choose(_ language: DictationLanguage) {
        guard language != self.language else { return }
        self.language = language
        transcriber.use(language: language)
        log.info("Language set to \(language.badge.lowercased() == "auto" ? "detect" : language.badge)")
        onLanguageChange?(language)
    }

    public private(set) var recent: [RecentDictation] = []
    private let recentLimit = 5

    /// True while the last dictation is sitting on the clipboard waiting for ⌘V:
    /// there was no text field to put it in, or no permission to paste. The pill
    /// shows the ⌘V hint from this, and only from this — a hint shown after the
    /// text already landed teaches you to press a key that pastes it twice.
    public private(set) var awaitingManualPaste = false

    /// Reads back what was just typed, so a spelling you fix is learned.
    public var editWatcher: (any EditWatching)?
    /// Whether this app's fields may be read back at all. Set by the app from the
    /// same privacy exclusions history uses: a password manager's fields are
    /// never looked at, corrected or not.
    public var mayWatchEdits: (String?) -> Bool = { _ in false }

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
    /// Puts English words the engine spelled in Arabic letters back into English.
    public var englishRestorer: (any CleanupProvider)?
    /// Plans one paragraph per idea in a long dictation. Set from outside, and
    /// only when transcription already goes to the cloud. See `IdeaParagraphs`.
    public var paragraphPlanner: (any ParagraphPlanner)?

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
    /// Transcribes a long dictation while it is still being spoken. Nil between
    /// dictations, and for anything that is not a dictation.
    private var rolling: RollingTranscriber?

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
        /// False for a verification run. A benchmark replaying the same recording
        /// is not something you said, and history is what the dictionary learns
        /// from: 26 replays of one test sentence taught it "billing".
        var records = true
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
        // A new engine starts out detecting, which would silently undo a choice
        // you made — and the engine is rebuilt whenever the config changes or the
        // resident server hands over to the command line.
        engine.use(language: language)
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
        // A confirmation waiting for you is the first thing Esc should drop.
        if commandRunner?.cancel() == true {
            log.info("Command cancelled")
            state = .idle
            return
        }
        switch state {
        case .error, .confirming:
            state = .idle                    // Esc acknowledges a failure or a question
            return
        case .idle, .notice:
            return
        case .recording:
            discardRecording(reason: "cancelled")
        case .transcribing, .cleaning, .inserting, .transforming:
            cancelled = true
            rolling?.cancel()
            rolling = nil
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
            // The last dictation's field gets one final look before this one
            // types anything that could move it.
            editWatcher?.flush()
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
            // Whatever the engine needs to load, it loads while you speak.
            transcriber.prefetch()
            rolling?.cancel()
            if intent == .dictate {
                let source = recorder
                let roller = RollingTranscriber(
                    engine: transcriber, prompt: capturedVocabulary.whisperPrompt,
                    log: log, read: { source.samples(from: $0) })
                roller.start()
                rolling = roller
            } else {
                rolling = nil
            }
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
        rolling?.cancel()
        rolling = nil
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
        let roller = rolling
        rolling = nil
        do {
            // Most of a long dictation was transcribed while it was spoken; only
            // the tail is left. Nil means nothing was rolled (a short dictation)
            // or a chunk failed, and the whole file goes through as it always did.
            if let roller, let rolled = try await roller.finish() {
                raw = rolled
            } else {
                raw = try await transcriber.transcribe(wav: recording.url,
                                                  prompt: capturedVocabulary.whisperPrompt)
            }
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
        // Lengths only, never the words. When a dictation comes out twice this is
        // what says whether the engine returned it that way or a later stage did.
        log.info("Transcript from engine: \(raw.count) characters, \(raw.split(separator: " ").count) words")

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
        // A command is not text either: what you said names an action, and the
        // words never reach your document.
        if capturedIntent == .command {
            try? FileManager.default.removeItem(at: recording.url)
            await runCommand(spoken: raw)
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
        // A dictation that enumerates something is structure, and the rewriter is
        // the one stage that can destroy it. Measured on qwen2.5:1.5b, the model
        // English routes to: asked to polish "we need to test the bullet feature.
        // First, we need X. Second, we need Y." it moved every ordinal to the end
        // of its clause and dropped a phrase, and what came out was a list of the
        // wrong things. The guard cannot catch that — the result is still a list,
        // just not the one that was spoken.
        //
        // So a spoken list goes to the cleaner instead. It is the weaker rewrite
        // and that is the point: its prompt is written to preserve every clause,
        // and `CleanupGuard` demands most of the words survive, where the polish
        // guard deliberately allows a rewrite to lose them. Filler inside an item
        // survives where polish would have removed it. That is the trade, and it
        // is not close: a tidy list of the wrong things is worse than an untidy
        // list of the right ones.
        let spokenList = config.output.formatSpokenLists && SpokenLists.makesAList(raw)
        if spokenList, config.cleanup.mode == .polish {
            log.info("A list was spoken; cleaning rather than rewriting, to keep its shape")
        }
        let polisher = config.cleanup.mode == .polish && !spokenList ? self.polisher : nil
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
                let candidate = try await polished(raw, instruction: instruction,
                                                   using: polisher)
                switch PolishGuard.check(raw: raw, polished: candidate) {
                case .accept:
                    text = candidate
                case .reject(let reason):
                    // Not straight back to the raw transcript. A refused rewrite
                    // means the model took liberties, not that you wanted your
                    // "um"s back — and handing them back is how a guard doing its
                    // job still reads as the product getting worse. The cleaner has
                    // no licence to delete, so it is asked instead: filler gone,
                    // punctuation fixed, every clause where you left it.
                    log.warn("Polish rejected (\(reason)); cleaning instead")
                    let second = try await cleanup.cleanKeepingShape(raw, instruction: instruction)
                    switch CleanupGuard.check(raw: raw, cleaned: second) {
                    case .accept:
                        text = second
                    case .reject(let reason):
                        rejected = true
                        log.warn("Cleanup rejected too (\(reason)); inserting raw transcript")
                    }
                }
            } else {
                // A spoken list goes to the bigger model even in English, because
                // the small one rearranges the very words that mark it.
                let candidate = spokenList
                    ? try await cleanup.cleanKeepingShape(raw, instruction: instruction)
                    : try await cleanup.clean(raw, instruction: instruction)
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

        // English words the engine wrote in Arabic letters (ميتنغ) go back to English
        // letters. Guarded token by token, so it can only ever swap such a word.
        if let restorer = englishRestorer, !text.isEmpty, !rejected {
            let restored = await EnglishRestore.apply(text, using: restorer)
            if restored != text {
                log.info("Restored English spelling in \(zip(text.split(separator: " "), restored.split(separator: " ")).filter { $0 != $1 }.count) words")
                text = restored
            }
            if cancelled { publish(.idle, for: gen); return }
        }

        // The dictionary, applied deterministically. The model layers are
        // unreliable — 1.5b ignores a glossary entirely — so the guarantee lives in
        // code that cannot decline.
        text = TermCorrector.apply(text, terms: context.vocabulary.terms,
                                  aliases: context.vocabulary.aliases)

        // Snippets, after the guard, so an expanded address can never be mistaken
        // for the model rewriting your words.
        text = SnippetExpander.expand(text, with: context.vocabulary.snippets)

        // "first…, second…, third…" is a list, and here it becomes one. Last,
        // because it is the only stage that adds line breaks, and every stage
        // before it reads the text as one line.
        if config.output.formatSpokenLists {
            let ideas = await ideaParagraphs(text)
            if cancelled { publish(.idle, for: gen); return }
            text = SpokenStructure.format(text, ideas: ideas)
        }

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
        if context.records { remember(text) }
        if context.records { onRecord?(HistoryEntry(
            at: Date(), cleaned: text, raw: raw,
            destination: context.destination?.name,
            script: ScriptDetector.detect(text),
            appName: context.app.name, bundleID: context.app.bundleID,
            durationSeconds: duration, peakLevel: peak, guardRejected: rejected)) }

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
            if context.records, gen == self.generation, mayWatchEdits(context.app.bundleID) {
                editWatcher?.watch(inserted: text, appName: context.app.name)
            }
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

        do {
            let outcome = try await runner.run(spoken: spoken)
            if cancelled { state = .idle; return }
            log.info("""
                Transform “\(outcome.transform?.name ?? spoken)”:                 \(outcome.before.count) characters → \(outcome.after.count)
                """)
            // One row carrying both sides. It used to record the clipboard as it
            // was and deliberately not the result, so History showed the text you
            // had *before* the transform — which reads exactly like the transform
            // never ran. `raw` keeps the original, so an unwanted rewrite is still
            // recoverable from the row, and `cleaned` is what you actually got.
            onRecord?(HistoryEntry(
                at: Date(), cleaned: outcome.after, raw: outcome.before,
                script: ScriptDetector.detect(outcome.after),
                appName: captured.name, bundleID: captured.bundleID,
                durationSeconds: 0, peakLevel: 0, guardRejected: false,
                kind: .transform))
            remember(outcome.after)
            onTransform?(outcome)
            deliverTransform(outcome.after)
        } catch {
            if cancelled { state = .idle; return }
            // The clipboard still holds the original: the runner writes only on
            // success. Saying so is the whole reassurance the user needs.
            log.warn("Transform failed (\(error.localizedDescription)); clipboard unchanged")
            let message = (error as? TransformError)?.errorDescription ?? "Transform failed"
            state = .error(message)
        }
    }

    /// Rewrites the dictation, in pieces when it is long enough that the model
    /// would start losing sentences out of it. See `PolishChunks`.
    ///
    /// Each piece is guarded on its own and falls back to its own words, so one
    /// piece the model mishandles costs that piece and not the dictation.
    /// One paragraph per idea, or nil to leave the text as one block. Never fails a
    /// dictation: an error or a slow answer costs the paragraphs, not the words.
    private func ideaParagraphs(_ text: String) async -> [String]? {
        guard let paragraphPlanner, IdeaParagraphs.worthPlanning(text) else { return nil }
        let began = ContinuousClock.now
        do {
            let ideas = try await IdeaParagraphs.plan(text, using: paragraphPlanner)
            log.info("Paragraphs: \(ideas?.count ?? 1) in \(began.duration(to: .now).milliseconds)ms")
            return ideas
        } catch {
            log.warn("""
                Paragraphs skipped (\(error.localizedDescription)) after \
                \(began.duration(to: .now).milliseconds)ms
                """)
            return nil
        }
    }

    private func polished(_ raw: String, instruction: String,
                          using polisher: any CleanupProvider) async throws -> String {
        let pieces = PolishChunks.split(raw)
        guard pieces.count > 1 else {
            return try await polisher.clean(raw, instruction: instruction)
        }
        log.info("Rewriting in \(pieces.count) pieces; the model loses sentences out of a long one")
        var written: [String] = []
        for piece in pieces {
            let candidate = try await polisher.clean(piece, instruction: instruction)
            switch PolishGuard.check(raw: piece, polished: candidate) {
            case .accept:
                written.append(candidate)
            case .reject(let reason):
                log.warn("A piece was refused (\(reason)); keeping it as spoken")
                written.append(piece)
            }
        }
        return written.joined(separator: " ")
    }

    /// Puts a finished transform where a finished dictation goes.
    ///
    /// The runner leaves its result on the clipboard, and that used to be the end
    /// of it: the pill showed the new text and nothing else happened. So a rewrite
    /// of the sentence you had selected appeared nowhere, and — alone among the
    /// things Rawi produces — never said that ⌘V would fetch it.
    ///
    /// The clipboard is not restored afterwards, whatever the setting says:
    /// leaving the rewrite there is the whole point of a transform, and putting
    /// the old text back a moment later would undo the feature.
    private func deliverTransform(_ text: String) {
        let focus = focusProbe.probe()
        log.info("Focus: \(focusProbe.lastSeen)")
        guard focus != .notEditable,
              inserter.insert(text, restoringClipboard: false) else {
            log.info("No text field has focus; left \(text.count) characters on the clipboard")
            awaitingManualPaste = true
            state = .notice("Copied")
            scheduleErrorClear()
            return
        }
        log.info("Inserted \(text.count) characters")
        state = .notice(PillLabel.landed(text))
        scheduleErrorClear()
    }

    /// Runs what you said as a command, or says why it could not.
    public var commandRunner: CommandRunner?

    /// The command path, as if you had spoken it. Used by the verification trigger.
    public func runSpokenCommand(_ spoken: String) async { await runCommand(spoken: spoken) }

    private func runCommand(spoken: String) async {
        guard let commandRunner else {
            state = .error("Commands are not set up")
            return
        }
        do {
            let message = try await commandRunner.heard(spoken)
            log.info("Command: \(message)")
            if commandRunner.pending != nil {
                state = .confirming(message)
                scheduleConfirmExpiry()
            } else {
                state = .notice(message)
                scheduleErrorClear()
            }
        } catch {
            log.warn("Command: \(error.localizedDescription)")
            state = .error(error.localizedDescription)
        }
    }

    /// A question nobody answers goes away on its own, and takes the command with
    /// it: an action that fires minutes later is worse than one that never ran.
    private func scheduleConfirmExpiry() {
        let window = commandConfirmWindow
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(window))
            guard let self, let runner = self.commandRunner, runner.pending != nil else { return }
            _ = runner.cancel()
            if case .confirming = self.state { self.state = .idle }
            self.log.info("Command confirmation expired")
        }
    }

    /// Injectable so the test does not wait twelve seconds.
    public var commandConfirmWindow: TimeInterval = CommandRunner.confirmWindow

    /// Says yes to what is waiting, from the key or from the pill.
    @discardableResult
    public func runPendingCommand() async -> Bool { await confirmCommand() }

    /// The command key again, while a confirmation is showing: yes.
    public func confirmCommand() async -> Bool {
        guard let commandRunner, commandRunner.pending != nil else { return false }
        do {
            guard let message = try await commandRunner.confirm() else {
                state = .idle
                return true
            }
            log.info("Command ran: \(message)")
            state = .notice(message)
            scheduleErrorClear()
        } catch {
            log.warn("Command failed: \(error.localizedDescription)")
            state = .error(error.localizedDescription)
        }
        return true
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
    public func retry(audioPath: String, appName: String?, bundleID: String?,
                      records: Bool = true) async {
        // Asking again dismisses whatever the last attempt left on the pill, the
        // same way pressing the key does — see `startRecording`. Without it, one
        // failed retry left `.error` standing, errors do not clear themselves,
        // and every later retry returned here silently: the button did nothing,
        // the log said nothing, and only relaunching the app fixed it.
        if case .error = state { state = .idle }
        if case .notice = state { state = .idle }
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
                         context: { var c = currentContext; c.records = records; return c }(),
                         generation: generation)
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
