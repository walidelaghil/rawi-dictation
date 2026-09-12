import Foundation

/// Sends each transcript to a cleanup model that will not break it.
///
/// Routing lives behind the `CleanupProvider` protocol on purpose: the controller
/// already holds exactly one provider and has no business learning about scripts.
/// Which model to use is a property of cleanup, so it stays here.
///
/// Providers are built lazily and cached, because each one holds a warm
/// connection and most sessions only ever touch one script.
public final class RoutedCleanup: CleanupProvider, @unchecked Sendable {
    private let models: CleanupModels
    private let makeProvider: (String) -> any CleanupProvider

    private let lock = NSLock()
    private var built: [String: any CleanupProvider] = [:]
    private var lastUsed: (any CleanupProvider)?

    /// `glossary` is the second layer of the dictionary — it catches terms the
    /// decoder hint missed. Measured: the hint alone did not rescue Sala→Salla.
    public init(kind: CleanupKind, apiKey: String?, models: CleanupModels,
                prompt: String, glossary: String = "",
                makeProvider: ((String) -> any CleanupProvider)? = nil) {
        self.models = models
        let full = glossary.isEmpty ? prompt : prompt + glossary
        self.makeProvider = makeProvider ?? { model in
            ChatCleanup(kind: kind, apiKey: apiKey, model: model, prompt: full)
        }
    }

    /// The model that would serve this transcript. Exposed so the log can say
    /// which one ran without having to run it.
    public func model(for transcript: String) -> String {
        models.model(for: ScriptDetector.detect(transcript))
    }

    public func clean(_ transcript: String) async throws -> String {
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return transcript
        }
        let name = model(for: transcript)
        let provider: any CleanupProvider = lock.withLock {
            if let existing = built[name] { lastUsed = existing; return existing }
            let fresh = makeProvider(name)
            built[name] = fresh
            lastUsed = fresh
            return fresh
        }
        return try await provider.clean(transcript)
    }

    /// Cancels whichever child is in flight. The route is decided per call, so
    /// there is no single child to assume.
    public func cancel() {
        lock.withLock { lastUsed }?.cancel()
    }
}
