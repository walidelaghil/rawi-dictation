import AppKit
import Foundation

public enum RecordingMode: Equatable, Sendable { case pushToTalk, handsFree }

public enum DictationState: Equatable, Sendable {
    case idle
    case recording(mode: RecordingMode, startedAt: ContinuousClock.Instant)
    case transcribing
    case cleaning
    case inserting
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

    /// Read at key-press so a dictation uses the vocabulary as it was when you
    /// started speaking, not as it might be by the time you stop.
    public var vocabulary: () -> VocabularySnapshot = { .empty }
    private var capturedVocabulary: VocabularySnapshot = .empty

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

    public func handle(_ outcome: TapOutcome) async {
        guard isEnabled else { return }
        switch outcome {
        case .beganHold:
            startRecording(mode: .pushToTalk)
        case .beganDoubleTap:
            promoteToHandsFree()
        case .endedHold, .stopHandsFree:
            await finishRecording()
        case .discardShortTap:
            discardRecording(reason: "tap too short to be speech")
        case .pendingShortTap, .ignored:
            break                     // keep recording; the timer decides
        }
    }

    /// Esc. Drops a recording, or aborts work already running.
    public func cancelRequested() async {
        switch state {
        case .idle, .error:
            return
        case .recording:
            discardRecording(reason: "cancelled")
        case .transcribing, .cleaning, .inserting:
            cancelled = true
            engine.cancel()
            cleanup.cancel()
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

    private func startRecording(mode: RecordingMode) {
        guard state == .idle else { return }        // ignore key repeat / re-entry
        let url = Config.recordingsDirectory
            .appendingPathComponent("dictation-\(Int(Date().timeIntervalSince1970)).wav")
        do {
            cancelled = false
            // Captured at key-press, not at insert: focus can move while you speak,
            // and the app you were looking at is the one that shaped the dictation.
            captured = frontmostApp()
            capturedVocabulary = vocabulary()
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
    private func promoteToHandsFree() {
        if case .recording(_, let startedAt) = state {
            state = .recording(mode: .handsFree, startedAt: startedAt)
        } else {
            startRecording(mode: .handsFree)
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

        // 2. Clean up. A cleanup failure must never lose the dictation, so the raw
        //    transcript is inserted instead.
        var text = raw
        var rejected = false
        state = .cleaning
        do {
            let candidate = try await cleanup.clean(raw)
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

        // 3. Apply the dictionary deterministically. The model layers are
        //    unreliable — 1.5b ignores a glossary entirely — so the guarantee
        //    lives in code that cannot decline.
        text = TermCorrector.apply(text, terms: capturedVocabulary.terms)

        // 4. Expand snippets — after the guard, so an expanded address can never
        //    be mistaken for the model rewriting your words.
        text = SnippetExpander.expand(text, with: capturedVocabulary.snippets)

        // 5. Insert.
        state = .inserting
        let pasted = inserter.insert(text,
                                     restoringClipboard: config.output.restorePreviousClipboard)
        // Recorded whether or not the synthetic paste landed. On a Mac that cannot
        // grant Accessibility the clipboard *is* the delivery mechanism — pressing
        // ⌘V is the user completing the insertion, not the dictation failing. Gating
        // on `pasted` left history permanently empty on exactly that machine.
        remember(text)
        onRecord?(HistoryEntry(
            at: Date(), cleaned: text, raw: raw,
            script: ScriptDetector.detect(text),
            appName: captured.name, bundleID: captured.bundleID,
            durationSeconds: Double(recording.duration.components.seconds),
            peakLevel: recording.peakLevel, guardRejected: rejected))

        if pasted {
            log.info("Inserted \(text.count) characters")
            try? FileManager.default.removeItem(at: recording.url)
            state = .idle
        } else {
            log.warn("""
                Could not paste: Accessibility permission is not granted. \
                The text is on the clipboard — press Cmd-V to insert it.
                """)
            try? FileManager.default.removeItem(at: recording.url)
            state = .error("Copied — press ⌘V")
            scheduleErrorClear()
        }
        currentRecordingURL = nil
    }

    private func remember(_ text: String) {
        let script = ScriptDetector.detect(text)
        lastDetectedLanguage = script == .arabic ? "AR" : "EN"
        recent.insert(RecentDictation(text: text, script: script), at: 0)
        if recent.count > recentLimit { recent.removeLast(recent.count - recentLimit) }
    }

    // MARK: - Errors

    private func report(_ error: any Error, context: String) {
        log.error("\(context) failed: \(error.localizedDescription)")
        state = .error(error.localizedDescription)
        scheduleErrorClear()
    }

    /// Leaves an error visible on the pill briefly, then returns to idle.
    private func scheduleErrorClear() {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard let self else { return }
            if case .error = self.state { self.state = .idle }
        }
    }
}
