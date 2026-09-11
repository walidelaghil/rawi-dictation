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
            try recorder.start(to: url)
            currentRecordingURL = url
            let now = ContinuousClock.now
            recordingStartedAt = now
            state = .recording(mode: mode, startedAt: now)
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

        // 1. Transcribe. On failure the WAV is retained and its path logged, so a
        //    dictation is never silently lost.
        let raw: String
        do {
            raw = try await engine.transcribe(wav: recording.url)
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
        state = .cleaning
        do {
            text = try await cleanup.clean(raw)
        } catch {
            if cancelled { state = .idle; return }
            log.warn("LLM cleanup failed (\(error.localizedDescription)); inserting raw transcript")
        }
        if cancelled { state = .idle; return }

        // 3. Insert.
        state = .inserting
        let pasted = inserter.insert(text,
                                     restoringClipboard: config.output.restorePreviousClipboard)
        if pasted {
            log.info("Inserted \(text.count) characters")
            try? FileManager.default.removeItem(at: recording.url)
            state = .idle
        } else {
            log.warn("""
                Could not paste: Accessibility permission is not granted. \
                The text is on the clipboard — press Cmd-V to insert it.
                """)
            state = .error("Copied — press ⌘V")
            scheduleErrorClear()
        }
        currentRecordingURL = nil
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
