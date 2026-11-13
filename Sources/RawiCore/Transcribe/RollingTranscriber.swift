import Foundation

/// Transcribes a long dictation while it is still being spoken.
///
/// Rawi used to wait for the key to come up before transcribing anything, so the
/// wait grew with the dictation: 102 seconds of speech was 102 seconds of audio
/// sitting in front of the model at the moment you let go. Caught in a real log
/// at 76 seconds to paste, on a 16 GB Mac with 15 GB in swap.
///
/// MacWhisper does not wait. Its bundled ArgmaxSDK exposes a
/// `StreamingTranscriber` that confirms text as the speech arrives, so release
/// only has the last few seconds left to do. This is the same idea built on the
/// engines Rawi already has. Once 20 seconds or more have not been transcribed, it
/// cuts at the first real pause past 15 seconds (between phrases, never
/// mid-word), transcribes that chunk in the background, and moves on. On release
/// only the tail is left.
///
/// A dictation that never reaches 20 seconds never reaches this code, so the
/// short dictations that are most of the day behave exactly as before. A chunk
/// that fails turns rolling off for the rest of that dictation, and the caller
/// falls back to transcribing the whole file, so nothing is lost.
public final class RollingTranscriber: @unchecked Sendable {
    static let sampleRate = 16_000
    /// Start a chunk once this much untranscribed audio has built up.
    static let chunkTrigger = 20 * sampleRate
    /// No cut before this, measured from the last cut.
    static let earliestCut = 15 * sampleRate
    /// With no pause by here, cut at the quietest point anyway. Whisper's window
    /// is 30 seconds, so a longer chunk is two windows, which still works.
    static let forcedCut = 45 * sampleRate
    /// Whisper invents "Thank you." from silence. A chunk this quiet throughout
    /// is skipped rather than sent.
    static let silenceRMS = 0.01

    private let engine: any TranscriptionEngine
    private let prompt: String
    private let read: @Sendable (Int) -> [Int16]
    private let directory: URL
    private let log: any Logging

    private let lock = NSLock()
    private var committed = 0           // samples already transcribed
    private var texts: [String] = []
    private var failed = false
    private var stopping = false
    private var loop: Task<Void, Never>?

    public init(engine: any TranscriptionEngine, prompt: String,
                directory: URL = FileManager.default.temporaryDirectory,
                log: any Logging,
                read: @escaping @Sendable (Int) -> [Int16]) {
        self.engine = engine
        self.prompt = prompt
        self.directory = directory
        self.log = log
        self.read = read
    }

    public func start() {
        loop = Task.detached(priority: .userInitiated) { [weak self] in
            while true {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, !Task.isCancelled,
                      !self.lock.withLock({ self.stopping || self.failed }) else { return }
                await self.step(final: false)
            }
        }
    }

    /// Whether any audio has been transcribed already. If not, the caller should
    /// take its ordinary path, so a short dictation is not affected at all.
    public var hasCommitted: Bool { lock.withLock { committed > 0 } }

    /// Stops rolling, transcribes what is left, and returns the whole transcript.
    /// Returns nil when rolling never committed anything or a chunk failed; the
    /// caller then transcribes the full recording as it always did.
    public func finish() async throws -> String? {
        // A flag, not `Task.cancel()`: the engines tie their HTTP request to task
        // cancellation, so cancelling the loop would kill the chunk in flight.
        lock.withLock { stopping = true }
        await loop?.value
        guard lock.withLock({ committed > 0 && !failed }) else { return nil }
        await step(final: true)
        if Task.isCancelled { throw TranscriptionError.cancelled }
        return lock.withLock { failed ? nil : texts.joined(separator: " ") }
    }

    public func cancel() {
        lock.withLock { stopping = true; failed = true }
        loop?.cancel()
        engine.cancel()
    }

    // MARK: - One step

    private func step(final: Bool) async {
        let start = lock.withLock { committed }
        let pending = read(start)
        let length: Int
        if final {
            length = pending.count
            guard length > 0 else { return }
        } else {
            guard pending.count >= Self.chunkTrigger,
                  let cut = Self.cutPoint(in: pending) else { return }
            length = cut
        }
        let chunk = Array(pending[0..<length])
        var text = ""
        if Self.peakFrameRMS(chunk) >= Self.silenceRMS {
            let began = ContinuousClock.now
            do {
                text = try await transcribe(chunk)
            } catch TranscriptionError.emptyResult {
                text = ""
            } catch {
                log.warn("Rolling chunk failed (\(error.localizedDescription)); "
                       + "the whole recording will be transcribed on release")
                lock.withLock { failed = true }
                return
            }
            let ms = began.duration(to: .now).milliseconds
            log.info(String(format: "%@ chunk: %.1fs of audio in %dms",
                            final ? "Final" : "Rolling",
                            Double(length) / Double(Self.sampleRate), ms))
        }
        lock.withLock {
            committed = start + length
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { texts.append(trimmed) }
        }
    }

    private func transcribe(_ samples: [Int16]) async throws -> String {
        let url = directory.appendingPathComponent("rawi-chunk-\(UUID().uuidString).wav")
        let writer = try WAVWriter(url: url)
        try writer.append(samples)
        try writer.finalize()
        defer { try? FileManager.default.removeItem(at: url) }
        return try await engine.transcribe(wav: url, prompt: prompt)
    }

    // MARK: - Where to cut

    /// The middle of the quietest 400 ms window from `earliestCut` on. A pause
    /// between phrases is where a cut costs nothing; mid-word is where it costs
    /// words. Whisper does not only lose the split word: given "...if it takes
    /// longer to tran" and then silence, it dropped the whole trailing clause.
    ///
    /// So the window has to be a real pause, quiet against how loud this speaker
    /// talks. Until one turns up, wait for more audio, up to `forcedCut`, rather
    /// than cut through speech. Checked four times a second, so the first good
    /// pause past 15 seconds is the one taken.
    static func cutPoint(in samples: [Int16]) -> Int? {
        let frame = sampleRate / 50                   // 20 ms
        let window = 20                               // 20 frames = 400 ms
        let lower = earliestCut
        let upper = min(samples.count, forcedCut)
        guard upper - lower >= frame * (window + 1) else { return nil }
        let energies: [Double] = stride(from: lower, to: upper - frame, by: frame).map {
            rms(Array(samples[$0..<($0 + frame)]))
        }
        var sum = energies[0..<window].reduce(0, +)
        var best = sum, bestIndex = 0
        for i in window..<energies.count {
            sum += energies[i] - energies[i - window]
            if sum < best { best = sum; bestIndex = i - window + 1 }
        }
        // How loud this speaker talks: the 75th percentile of 20 ms frames.
        let sorted = energies.sorted()
        let speech = sorted[sorted.count * 3 / 4]
        let isPause = best / Double(window) <= max(silenceRMS * 0.5, speech * 0.2)
        guard isPause || samples.count >= forcedCut else { return nil }
        return lower + (bestIndex + window / 2) * frame
    }

    static func rms(_ samples: [Int16]) -> Double { rmsLevel(samples) }

    /// The loudest 20 ms in the chunk, so one spoken word in a long silence still
    /// counts as speech.
    static func peakFrameRMS(_ samples: [Int16]) -> Double {
        let frame = sampleRate / 50
        var peak = 0.0
        var i = 0
        while i + frame <= samples.count {
            peak = max(peak, rmsLevel(Array(samples[i..<(i + frame)])))
            i += frame
        }
        return peak
    }
}
