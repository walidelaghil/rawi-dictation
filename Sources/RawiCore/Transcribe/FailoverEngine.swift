import Foundation

/// A hosted engine first, the local model when the hosted one cannot answer.
///
/// Why hosted first: on a 16 GB Mac the resident model does not stay resident.
/// Across 243 dictations in a real log, the same model on the same machine took
/// a median 1.6 s when used within two minutes of the last dictation, 3.1 s after
/// two to thirty minutes idle and 8.0 s after more than thirty, worst 77 s. macOS
/// had paged the weights to swap. A hosted model's latency does not depend on
/// what else the Mac is doing.
///
/// Why local behind it: no network, a bad key, a rate limit or an outage must
/// still produce text. The fallback is loaded only when it is needed, so it adds
/// nothing to the memory pressure that caused the problem.
///
/// After a failure the hosted engine is skipped for a while, so being offline
/// costs one timeout, not one per dictation.
public final class FailoverEngine: TranscriptionEngine, @unchecked Sendable {
    public let primary: any TranscriptionEngine
    public let fallback: any TranscriptionEngine
    private let log: any Logging
    private let deadline: @Sendable (TimeInterval) -> Duration
    private let cooldown: Duration

    private let lock = NSLock()
    private var skipPrimaryUntil: ContinuousClock.Instant?

    /// `deadline` maps seconds of audio to how long the hosted engine gets.
    public init(primary: any TranscriptionEngine, fallback: any TranscriptionEngine,
                log: any Logging,
                cooldown: Duration = .seconds(60),
                deadline: @escaping @Sendable (TimeInterval) -> Duration = FailoverEngine.defaultDeadline) {
        self.primary = primary
        self.fallback = fallback
        self.log = log
        self.cooldown = cooldown
        self.deadline = deadline
    }

    /// Groq answers a short clip in well under a second and a 45 s chunk in one
    /// or two. Four seconds plus a tenth of the audio leaves room for a slow
    /// uplink without making an outage feel like a hang.
    public static let defaultDeadline: @Sendable (TimeInterval) -> Duration = { seconds in
        .milliseconds(Int((4 + seconds * 0.1) * 1000))
    }

    public func transcribe(wav: URL, prompt: String) async throws -> String {
        if primaryAvailable {
            do {
                return try await withDeadline(deadline(Self.seconds(of: wav))) {
                    try await self.primary.transcribe(wav: wav, prompt: prompt)
                }
            } catch TranscriptionError.emptyResult {
                throw TranscriptionError.emptyResult      // silence; local would agree
            } catch {
                if Task.isCancelled { throw TranscriptionError.cancelled }
                benchPrimary(after: error)
            }
        }
        return try await fallback.transcribe(wav: wav, prompt: prompt)
    }

    public func cancel() {
        primary.cancel()
        fallback.cancel()
    }

    public func use(language: DictationLanguage) {
        primary.use(language: language)
        fallback.use(language: language)
    }

    public func prefetch() {
        if primaryAvailable { primary.prefetch() } else { fallback.prefetch() }
    }

    // MARK: -

    private var primaryAvailable: Bool {
        lock.withLock {
            guard let until = skipPrimaryUntil else { return true }
            if ContinuousClock.now >= until { skipPrimaryUntil = nil; return true }
            return false
        }
    }

    private func benchPrimary(after error: Error) {
        let reason: String
        var wait = cooldown
        switch error {
        case FailoverError.timedOut:
            reason = "took too long"
        case TranscriptionError.apiError(let status, _) where status == 401 || status == 403:
            reason = "rejected the API key"
            wait = .seconds(60 * 30)
        case TranscriptionError.apiError(let status, _) where status == 429:
            reason = "is rate limiting"
        default:
            reason = "failed (\(error.localizedDescription))"
        }
        lock.withLock { skipPrimaryUntil = .now + wait }
        log.warn("Cloud transcription \(reason); using the local model for "
               + "\(wait.components.seconds)s")
    }

    private func withDeadline<T: Sendable>(_ limit: Duration,
                                           _ work: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await work() }
            group.addTask {
                try await Task.sleep(for: limit)
                throw FailoverError.timedOut
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }

    static func seconds(of wav: URL) -> TimeInterval {
        let bytes = (try? FileManager.default.attributesOfItem(atPath: wav.path)[.size] as? Int) ?? 0
        return Double(max(0, bytes - 44)) / 32_000
    }
}

enum FailoverError: Error { case timedOut }
